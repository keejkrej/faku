//! One-shot waku-daemon sidecar.
//!
//! Native `fx.spawn` writes stdin once and then closes it. This module
//! builds that buffer (hello + attachSession + start + prompt when no
//! runtime id, hello + attachSession + prompt when one is stored, hello +
//! saveTaskState, hello + loadTaskState, hello + hydrateSession,
//! hello + closeSession, hello + cancel, hello + steer, hello +
//! `goal`, or hello + `workspace`) and,
//! when run as `faku daemon-proxy <addr>`, forwards those JSON frames over
//! `ws://{addr}/v1`, prints each incoming text frame as one stdout line,
//! and exits on `turnFinished` / `rejected` / `error`. A save-only stdin
//! (no prompt) exits after server hello / response. A load-only stdin
//! waits for the `taskState` response (not hello) because a nil
//! `requestId` is a notify and would never return the catalog. A
//! hydrate-only stdin waits for the `session` response the same way. A
//! close-only, cancel-only, or steer-only stdin exits after server
//! hello / response like save. A goal-only stdin waits for a response
//! or `goalUpdated` / `error` (not hello) so a same-batch event can
//! reach stdout; missing event keeps last-known local goal fields.
//! A workspace-only stdin waits for a `response` / `rejected` /
//! `shutting_down` frame (not hello, not a driver event) like save/close,
//! prints that line, and exits non-zero unless the response is an ok
//! workspace ack (Push / Commit / CaptureTurnStart / WriteTextFile), `worktreeCreated` (CreateWorktree),
//! or `branches` with a usable snapshot (InspectBranches), or
//! `branchChanged` with a usable snapshot (CheckoutBranch), or
//! `commitSnapshot` with a usable snapshot (InspectCommit), or
//! `checkpoint` with a nested checkpoint object (CaptureTurn), or
//! `commitMessage` with a string `message` (GenerateCommitMessage), or
//! `workingTree` with a parsed `entries` array (ListTree), or
//! `reviewDiff` with nested `data` (CollectReviewDiff), or
//! `directory` with `path` + `entries` (BrowseDirectory), or
//! `textFile` with a string `content` (ReadTextFile).
//!
//! The desktop update loop never holds a WebSocket. Catalog persist stays
//! local `sessions.json`; `loadTaskState` / `saveTaskState` on the wire
//! talk to the daemon only and do not replace the store.

const std = @import("std");
const protocol = @import("protocol.zig");

pub const SUBCOMMAND = "daemon-proxy";
pub const CLIENT_ID = "00000000-0000-0000-0000-00000000000f";
pub const WS_PATH = "/v1";
pub const WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

const WriteError = error{NoSpaceLeft};

pub const TurnStdin = struct {
    token: []const u8 = "",
    client_id: []const u8 = CLIENT_ID,
    request_id: []const u8 = protocol.NIL_UUID,
    attach_request_id: []const u8 = ATTACH_REQUEST_ID,
    session_id: []const u8 = protocol.NIL_UUID,
    runtime_id: []const u8 = protocol.NIL_UUID,
    prompt: []const u8,
    /// Present only for a first send with no persisted runtime id.
    start: ?protocol.StartOptions = null,
};

pub const SaveStdin = struct {
    token: []const u8 = "",
    client_id: []const u8 = CLIENT_ID,
    request_id: []const u8 = protocol.NIL_UUID,
    runtime_id: []const u8 = protocol.NIL_UUID,
    skeleton: protocol.TaskStateSkeleton,
};

/// Non-nil: a nil `requestId` is a notify and the daemon sends no `taskState`.
pub const LOAD_REQUEST_ID = "00000000-0000-0000-0000-000000000010";
/// Non-nil: a nil `requestId` is a notify and the daemon sends no `session`.
pub const HYDRATE_REQUEST_ID = "00000000-0000-0000-0000-000000000011";
/// Non-nil: a nil `requestId` is a notify and the daemon sends no `sessionRuntime`.
pub const ATTACH_REQUEST_ID = "00000000-0000-0000-0000-000000000012";

pub const LoadStdin = struct {
    token: []const u8 = "",
    client_id: []const u8 = CLIENT_ID,
    request_id: []const u8 = LOAD_REQUEST_ID,
    session_id: []const u8 = protocol.NIL_UUID,
    runtime_id: []const u8 = protocol.NIL_UUID,
};

pub const HydrateStdin = struct {
    token: []const u8 = "",
    client_id: []const u8 = CLIENT_ID,
    request_id: []const u8 = HYDRATE_REQUEST_ID,
    session_id: []const u8,
};

pub const CloseStdin = struct {
    token: []const u8 = "",
    client_id: []const u8 = CLIENT_ID,
    request_id: []const u8 = protocol.NIL_UUID,
    session_id: []const u8,
    runtime_id: []const u8 = protocol.NIL_UUID,
};

pub const CancelStdin = struct {
    token: []const u8 = "",
    client_id: []const u8 = CLIENT_ID,
    request_id: []const u8 = protocol.NIL_UUID,
    session_id: []const u8,
    runtime_id: []const u8 = protocol.NIL_UUID,
};

pub const SteerStdin = struct {
    token: []const u8 = "",
    client_id: []const u8 = CLIENT_ID,
    request_id: []const u8 = protocol.NIL_UUID,
    session_id: []const u8,
    runtime_id: []const u8 = protocol.NIL_UUID,
    prompt: []const u8,
};

pub const GoalStdin = struct {
    token: []const u8 = "",
    client_id: []const u8 = CLIENT_ID,
    request_id: []const u8 = protocol.NIL_UUID,
    session_id: []const u8,
    runtime_id: []const u8 = protocol.NIL_UUID,
    operation: protocol.GoalOperation,
};

/// Non-nil: a nil `requestId` is a notify and the daemon sends no
/// workspace `response`.
pub const WORKSPACE_REQUEST_ID = "00000000-0000-0000-0000-000000000014";

pub const WorkspaceStdin = struct {
    token: []const u8 = "",
    client_id: []const u8 = CLIENT_ID,
    request_id: []const u8 = WORKSPACE_REQUEST_ID,
    session_id: []const u8 = protocol.NIL_UUID,
    runtime_id: []const u8 = protocol.NIL_UUID,
    operation: protocol.WorkspaceOperation,
};

pub const ParsedAddress = struct {
    host: []const u8,
    port: u16,
    path: []const u8 = WS_PATH,
};

/// Format a local session id as a v3-looking nil-prefixed UUID.
pub fn wireUuid(local_id: u32, buf: *[36]u8) []const u8 {
    return std.fmt.bufPrint(buf, "00000000-0000-0000-0000-{x:0>12}", .{local_id}) catch protocol.NIL_UUID;
}

/// Reverse of `wireUuid`. Other UUID shapes are not a local id.
pub fn localIdFromWire(uuid: []const u8) ?u32 {
    const prefix = "00000000-0000-0000-0000-";
    if (!std.mem.startsWith(u8, uuid, prefix)) return null;
    const hex = uuid[prefix.len..];
    if (hex.len != 12) return null;
    return std.fmt.parseInt(u32, hex, 16) catch null;
}

pub fn parseAddress(raw: []const u8) ?ParsedAddress {
    var rest = std.mem.trim(u8, raw, " \t\r\n");
    if (rest.len == 0) return null;
    if (std.mem.startsWith(u8, rest, "ws://")) rest = rest["ws://".len..];
    if (std.mem.startsWith(u8, rest, "http://")) rest = rest["http://".len..];

    var path: []const u8 = WS_PATH;
    if (std.mem.indexOfScalar(u8, rest, '/')) |slash| {
        path = rest[slash..];
        rest = rest[0..slash];
    }
    if (rest.len == 0) return null;

    const colon = std.mem.lastIndexOfScalar(u8, rest, ':') orelse return null;
    if (colon == 0 or colon + 1 >= rest.len) return null;
    const port = std.fmt.parseUnsigned(u16, rest[colon + 1 ..], 10) catch return null;
    const host = rest[0..colon];
    if (host.len == 0) return null;
    return .{ .host = host, .port = port, .path = path };
}

const Cursor = struct {
    buf: []u8,
    pos: usize = 0,

    fn remaining(self: *Cursor) []u8 {
        return self.buf[self.pos..];
    }

    fn write(self: *Cursor, bytes: []const u8) WriteError!void {
        if (self.pos + bytes.len > self.buf.len) return error.NoSpaceLeft;
        @memcpy(self.buf[self.pos..][0..bytes.len], bytes);
        self.pos += bytes.len;
    }

    fn slice(self: *const Cursor) []const u8 {
        return self.buf[0..self.pos];
    }
};

/// NDJSON stdin for one sidecar spawn. Fits Native's 4 KiB stdin cap
/// for a 512-byte composer draft. Hello + bare attachSession, then
/// `start` when `args.start` is set (no persisted runtime id), then
/// prompt. Verified Waku `sendPrompt` order is attach, start if no
/// runtime, prompt. Prompt may carry a persisted runtime id; attach
/// uses nil. loadTaskState is not part of this turn batch.
pub fn writeTurnStdin(buf: []u8, args: TurnStdin) WriteError![]const u8 {
    var cur = Cursor{ .buf = buf };
    const hello = try protocol.writeClientHello(cur.remaining(), args.token, args.client_id, &.{});
    cur.pos += hello.len;
    try cur.write("\n");
    const attach = try protocol.writeAttachSession(
        cur.remaining(),
        args.attach_request_id,
        args.session_id,
    );
    cur.pos += attach.len;
    try cur.write("\n");
    if (args.start) |options| {
        const start = try protocol.writeStart(
            cur.remaining(),
            args.request_id,
            args.session_id,
            args.runtime_id,
            options,
        );
        cur.pos += start.len;
        try cur.write("\n");
    }
    const prompt = try protocol.writePrompt(
        cur.remaining(),
        args.request_id,
        args.session_id,
        args.runtime_id,
        args.prompt,
    );
    cur.pos += prompt.len;
    try cur.write("\n");
    return cur.slice();
}

/// NDJSON stdin for a persist-time catalog mirror. Hello + saveTaskState,
/// no prompt. Native stdin is still one buffer.
pub fn writeSaveStdin(buf: []u8, args: SaveStdin) WriteError![]const u8 {
    var cur = Cursor{ .buf = buf };
    const hello = try protocol.writeClientHello(cur.remaining(), args.token, args.client_id, &.{});
    cur.pos += hello.len;
    try cur.write("\n");
    const save = try protocol.writeSaveTaskState(
        cur.remaining(),
        args.request_id,
        args.runtime_id,
        args.skeleton,
    );
    cur.pos += save.len;
    try cur.write("\n");
    return cur.slice();
}

/// NDJSON stdin for a first-run catalog fill. Hello + loadTaskState,
/// no prompt. Uses a non-nil requestId so the daemon replies.
pub fn writeLoadStdin(buf: []u8, args: LoadStdin) WriteError![]const u8 {
    var cur = Cursor{ .buf = buf };
    const hello = try protocol.writeClientHello(cur.remaining(), args.token, args.client_id, &.{});
    cur.pos += hello.len;
    try cur.write("\n");
    const load = try protocol.writeBareCommand(
        cur.remaining(),
        args.request_id,
        args.session_id,
        args.runtime_id,
        .load_task_state,
    );
    cur.pos += load.len;
    try cur.write("\n");
    return cur.slice();
}

/// NDJSON stdin for an empty-transcript hydrate. Hello + hydrateSession,
/// no prompt. Uses a non-nil requestId so the daemon replies.
pub fn writeHydrateStdin(buf: []u8, args: HydrateStdin) WriteError![]const u8 {
    var cur = Cursor{ .buf = buf };
    const hello = try protocol.writeClientHello(cur.remaining(), args.token, args.client_id, &.{});
    cur.pos += hello.len;
    try cur.write("\n");
    const hydrate = try protocol.writeHydrateSession(cur.remaining(), args.request_id, args.session_id);
    cur.pos += hydrate.len;
    try cur.write("\n");
    return cur.slice();
}

/// NDJSON stdin for a local-remove notify. Hello + bare closeSession,
/// no prompt and no attachSession. Native stdin is still one buffer.
pub fn writeCloseStdin(buf: []u8, args: CloseStdin) WriteError![]const u8 {
    var cur = Cursor{ .buf = buf };
    const hello = try protocol.writeClientHello(cur.remaining(), args.token, args.client_id, &.{});
    cur.pos += hello.len;
    try cur.write("\n");
    const close = try protocol.writeBareCommand(
        cur.remaining(),
        args.request_id,
        args.session_id,
        args.runtime_id,
        .close_session,
    );
    cur.pos += close.len;
    try cur.write("\n");
    return cur.slice();
}

/// NDJSON stdin for Stop / Esc of a live daemon turn. Hello + bare
/// `cancel` (request-frame `sessionId` / `runtimeId`, no payload).
/// Native cannot write into the running prompt sidecar, so this is a
/// second one-shot on its own spawn key. No attachSession, no prompt.
pub fn writeCancelStdin(buf: []u8, args: CancelStdin) WriteError![]const u8 {
    var cur = Cursor{ .buf = buf };
    const hello = try protocol.writeClientHello(cur.remaining(), args.token, args.client_id, &.{});
    cur.pos += hello.len;
    try cur.write("\n");
    const cancel = try protocol.writeBareCommand(
        cur.remaining(),
        args.request_id,
        args.session_id,
        args.runtime_id,
        .cancel,
    );
    cur.pos += cancel.len;
    try cur.write("\n");
    return cur.slice();
}

/// NDJSON stdin for a live-turn steer. Hello + `steer` (request-frame
/// `sessionId` / `runtimeId`, command payload `prompt`). Native cannot
/// write into the running prompt sidecar, so this is a second one-shot
/// on its own spawn key. No attachSession, no prompt command.
pub fn writeSteerStdin(buf: []u8, args: SteerStdin) WriteError![]const u8 {
    var cur = Cursor{ .buf = buf };
    const hello = try protocol.writeClientHello(cur.remaining(), args.token, args.client_id, &.{});
    cur.pos += hello.len;
    try cur.write("\n");
    const steer = try protocol.writeSteer(
        cur.remaining(),
        args.request_id,
        args.session_id,
        args.runtime_id,
        args.prompt,
    );
    cur.pos += steer.len;
    try cur.write("\n");
    return cur.slice();
}

/// NDJSON stdin for a Codex `/goal` mutation. Hello + `goal` (request-frame
/// `sessionId` / `runtimeId`, command payload `operation`). Own spawn
/// key — Native cannot write into a running prompt sidecar. No
/// attachSession, no prompt command. Outcome is async `goalUpdated`.
pub fn writeGoalStdin(buf: []u8, args: GoalStdin) WriteError![]const u8 {
    var cur = Cursor{ .buf = buf };
    const hello = try protocol.writeClientHello(cur.remaining(), args.token, args.client_id, &.{});
    cur.pos += hello.len;
    try cur.write("\n");
    const goal = try protocol.writeGoal(
        cur.remaining(),
        args.request_id,
        args.session_id,
        args.runtime_id,
        args.operation,
    );
    cur.pos += goal.len;
    try cur.write("\n");
    return cur.slice();
}

/// NDJSON stdin for first-cut workspace Push / CreateWorktree / Commit /
/// InspectBranches / CheckoutBranch / InspectCommit / CaptureTurnStart /
/// CaptureTurn / GenerateCommitMessage / ListTree /
/// CollectReviewDiff / BrowseDirectory / ReadTextFile / WriteTextFile.
/// Hello + `workspace`
/// (nil request-frame `sessionId` / `runtimeId`, command payload
/// `operation`). Own spawn key — Native cannot write into a running
/// prompt sidecar. No attachSession, no prompt command. Wait for a
/// `response` frame (ok or error), not a driver event.
pub fn writeWorkspaceStdin(buf: []u8, args: WorkspaceStdin) WriteError![]const u8 {
    var cur = Cursor{ .buf = buf };
    const hello = try protocol.writeClientHello(cur.remaining(), args.token, args.client_id, &.{});
    cur.pos += hello.len;
    try cur.write("\n");
    const workspace = try protocol.writeWorkspace(
        cur.remaining(),
        args.request_id,
        args.session_id,
        args.runtime_id,
        args.operation,
    );
    cur.pos += workspace.len;
    try cur.write("\n");
    return cur.slice();
}

fn outboundWaitsForTurn(outbound: []const u8) bool {
    return std.mem.indexOf(u8, outbound, "\"type\":\"prompt\"") != null;
}

fn outboundWaitsForLoadResponse(outbound: []const u8) bool {
    return std.mem.indexOf(u8, outbound, "\"type\":\"loadTaskState\"") != null and
        std.mem.indexOf(u8, outbound, "\"type\":\"prompt\"") == null and
        std.mem.indexOf(u8, outbound, "\"type\":\"saveTaskState\"") == null;
}

fn outboundWaitsForHydrateResponse(outbound: []const u8) bool {
    return std.mem.indexOf(u8, outbound, "\"type\":\"hydrateSession\"") != null and
        std.mem.indexOf(u8, outbound, "\"type\":\"prompt\"") == null and
        std.mem.indexOf(u8, outbound, "\"type\":\"saveTaskState\"") == null;
}

fn outboundWaitsForGoal(outbound: []const u8) bool {
    return std.mem.indexOf(u8, outbound, "\"type\":\"goal\"") != null and
        std.mem.indexOf(u8, outbound, "\"type\":\"prompt\"") == null and
        std.mem.indexOf(u8, outbound, "\"type\":\"saveTaskState\"") == null;
}

fn outboundWaitsForWorkspace(outbound: []const u8) bool {
    return std.mem.indexOf(u8, outbound, "\"type\":\"workspace\"") != null and
        std.mem.indexOf(u8, outbound, "\"type\":\"prompt\"") == null;
}

fn isSaveOnlyTerminal(parsed: protocol.ParsedServer) bool {
    return switch (parsed.frame) {
        .hello, .rejected, .response, .task_state_changed, .shutting_down => true,
        .event => parsed.event_kind == .@"error",
        else => false,
    };
}

fn isLoadOnlyTerminal(parsed: protocol.ParsedServer) bool {
    return switch (parsed.frame) {
        .rejected, .response, .shutting_down => true,
        .event => parsed.event_kind == .@"error",
        else => false,
    };
}

fn isGoalOnlyTerminal(parsed: protocol.ParsedServer) bool {
    return switch (parsed.frame) {
        .rejected, .response, .shutting_down => true,
        .event => parsed.event_kind == .@"error" or parsed.event_kind == .goal_updated,
        else => false,
    };
}

fn isWorkspaceOnlyTerminal(parsed: protocol.ParsedServer) bool {
    return switch (parsed.frame) {
        .rejected, .response, .shutting_down => true,
        else => false,
    };
}

pub fn isSidecarArgv(args: []const []const u8) bool {
    return args.len >= 2 and std.mem.eql(u8, args[1], SUBCOMMAND);
}

pub fn sidecarAddressArg(args: []const []const u8) []const u8 {
    return if (args.len >= 3) args[2] else "";
}

/// `true` once this process is the sidecar (do not start the GUI).
pub fn maybeRun(init: std.process.Init) !bool {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (!isSidecarArgv(args)) return false;
    try runFromStdio(init.io, sidecarAddressArg(args));
    return true;
}

pub fn runFromStdio(io: std.Io, address: []const u8) !void {
    // Native spawn stdin is one 4 KiB buffer, then EOF.
    var read_buf: [512]u8 = undefined;
    var stdin_reader = std.Io.File.stdin().reader(io, &read_buf);
    var collected: [4096]u8 = undefined;
    const n = stdin_reader.interface.readSliceShort(&collected) catch 0;
    var stdout_buf: [1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(io, &stdout_buf);
    try run(io, address, collected[0..n], &stdout.interface);
    try stdout.interface.flush();
}

pub fn run(io: std.Io, address: []const u8, outbound: []const u8, stdout: *std.Io.Writer) !void {
    const parsed_addr = parseAddress(address) orelse {
        try writeStdoutLine(stdout, "{\"type\":\"rejected\",\"message\":\"missing daemon address\"}");
        return error.MissingAddress;
    };
    const host = if (std.mem.eql(u8, parsed_addr.host, "localhost")) "127.0.0.1" else parsed_addr.host;
    const resolved = std.Io.net.IpAddress.resolve(io, host, parsed_addr.port) catch {
        try writeStdoutLine(stdout, "{\"type\":\"rejected\",\"message\":\"resolve failed\"}");
        return error.ResolveFailed;
    };
    const stream = std.Io.net.IpAddress.connect(&resolved, io, .{ .mode = .stream, .protocol = .tcp }) catch {
        try writeStdoutLine(stdout, "{\"type\":\"rejected\",\"message\":\"connect failed\"}");
        return error.ConnectFailed;
    };
    defer stream.close(io);

    var key_raw: [16]u8 = undefined;
    io.random(&key_raw);
    var key_b64: [24]u8 = undefined;
    const key = std.base64.standard.Encoder.encode(&key_b64, &key_raw);

    var write_buf: [2048]u8 = undefined;
    var read_buf: [4096]u8 = undefined;
    var writer = stream.writer(io, &write_buf);
    var reader = stream.reader(io, &read_buf);

    if (!handshake(&writer.interface, &reader.interface, parsed_addr.host, parsed_addr.port, parsed_addr.path, key)) {
        try writeStdoutLine(stdout, "{\"type\":\"rejected\",\"message\":\"websocket handshake failed\"}");
        return error.HandshakeFailed;
    }

    var line_start: usize = 0;
    while (line_start < outbound.len) {
        const rest = outbound[line_start..];
        const nl = std.mem.indexOfScalar(u8, rest, '\n') orelse rest.len;
        const frame = std.mem.trim(u8, rest[0..nl], " \t\r\n");
        line_start += nl + 1;
        if (frame.len == 0) continue;
        writeTextFrame(io, &writer.interface, frame) catch {
            try writeStdoutLine(stdout, "{\"type\":\"rejected\",\"message\":\"send failed\"}");
            return error.SendFailed;
        };
        writer.interface.flush() catch {
            try writeStdoutLine(stdout, "{\"type\":\"rejected\",\"message\":\"send failed\"}");
            return error.SendFailed;
        };
    }

    const wait_for_turn = outboundWaitsForTurn(outbound);
    const wait_for_load = outboundWaitsForLoadResponse(outbound);
    const wait_for_hydrate = outboundWaitsForHydrateResponse(outbound);
    const wait_for_goal = outboundWaitsForGoal(outbound);
    const wait_for_workspace = outboundWaitsForWorkspace(outbound);
    var payload_buf: [nativeLineCap]u8 = undefined;
    while (true) {
        const n = readTextFrame(&reader.interface, &payload_buf) catch |err| switch (err) {
            error.Closed => {
                if (wait_for_workspace) return error.Rejected;
                return;
            },
            else => {
                try writeStdoutLine(stdout, "{\"type\":\"rejected\",\"message\":\"read failed\"}");
                return err;
            },
        };
        const line = payload_buf[0..n];
        try writeStdoutLine(stdout, line);
        try stdout.flush();
        var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena_state.deinit();
        const parsed = protocol.parseServerFrame(arena_state.allocator(), line);
        if (wait_for_workspace) {
            if (isWorkspaceOnlyTerminal(parsed)) {
                if (protocol.isWorkspaceSuccess(arena_state.allocator(), line)) return;
                return error.Rejected;
            }
            continue;
        }
        if (protocol.isTerminalServerFrame(parsed)) return;
        if (wait_for_turn) continue;
        if (wait_for_load or wait_for_hydrate) {
            if (isLoadOnlyTerminal(parsed)) return;
            continue;
        }
        if (wait_for_goal) {
            if (isGoalOnlyTerminal(parsed)) return;
            continue;
        }
        if (isSaveOnlyTerminal(parsed)) return;
    }
}

const nativeLineCap = 64 * 1024;

fn writeStdoutLine(stdout: *std.Io.Writer, line: []const u8) !void {
    try stdout.writeAll(line);
    try stdout.writeByte('\n');
}

pub fn wsAcceptKey(key_b64: []const u8, dest: []u8) []const u8 {
    var hasher = std.crypto.hash.Sha1.init(.{});
    hasher.update(key_b64);
    hasher.update(WS_GUID);
    var digest: [std.crypto.hash.Sha1.digest_length]u8 = undefined;
    hasher.final(&digest);
    return std.base64.standard.Encoder.encode(dest, &digest);
}

pub fn writeHandshakeRequest(
    dest: []u8,
    host: []const u8,
    port: u16,
    path: []const u8,
    key_b64: []const u8,
) WriteError![]const u8 {
    return std.fmt.bufPrint(
        dest,
        "GET {s} HTTP/1.1\r\nHost: {s}:{d}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: {s}\r\nSec-WebSocket-Version: 13\r\n\r\n",
        .{ path, host, port, key_b64 },
    ) catch error.NoSpaceLeft;
}

fn handshake(
    writer: *std.Io.Writer,
    reader: *std.Io.Reader,
    host: []const u8,
    port: u16,
    path: []const u8,
    key_b64: []const u8,
) bool {
    var req_buf: [512]u8 = undefined;
    const request = writeHandshakeRequest(&req_buf, host, port, path, key_b64) catch return false;
    writer.writeAll(request) catch return false;
    writer.flush() catch return false;

    var head: [2048]u8 = undefined;
    var n: usize = 0;
    while (n + 4 <= head.len) {
        const took = reader.readSliceShort(head[n .. n + 1]) catch return false;
        if (took == 0) return false;
        n += took;
        if (n >= 4 and std.mem.eql(u8, head[n - 4 .. n], "\r\n\r\n")) break;
    }
    const response = head[0..n];
    if (!std.mem.startsWith(u8, response, "HTTP/1.1 101") and !std.mem.startsWith(u8, response, "HTTP/1.0 101")) {
        return false;
    }
    var accept_buf: [28]u8 = undefined;
    const expect = wsAcceptKey(key_b64, &accept_buf);
    return std.mem.indexOf(u8, response, expect) != null;
}

pub fn writeTextFrame(io: std.Io, writer: *std.Io.Writer, payload: []const u8) !void {
    var mask: [4]u8 = undefined;
    io.random(&mask);
    try writeTextFrameMasked(writer, payload, mask);
}

pub fn writeTextFrameMasked(writer: *std.Io.Writer, payload: []const u8, mask: [4]u8) !void {
    try writer.writeByte(0x81);
    if (payload.len <= 125) {
        try writer.writeByte(0x80 | @as(u8, @intCast(payload.len)));
    } else if (payload.len <= 65535) {
        try writer.writeByte(0x80 | 126);
        try writer.writeByte(@intCast((payload.len >> 8) & 0xff));
        try writer.writeByte(@intCast(payload.len & 0xff));
    } else {
        try writer.writeByte(0x80 | 127);
        var i: u6 = 8;
        while (i > 0) {
            i -= 1;
            try writer.writeByte(@intCast((payload.len >> (i * 8)) & 0xff));
        }
    }
    try writer.writeAll(&mask);
    for (payload, 0..) |byte, i| {
        try writer.writeByte(byte ^ mask[i % 4]);
    }
}

/// Server-to-client text frames are unmasked. Client-to-server frames
/// (used by the fake peer in tests) may be masked.
pub fn writeServerTextFrame(writer: *std.Io.Writer, payload: []const u8) !void {
    try writer.writeByte(0x81);
    if (payload.len <= 125) {
        try writer.writeByte(@as(u8, @intCast(payload.len)));
    } else if (payload.len <= 65535) {
        try writer.writeByte(126);
        try writer.writeByte(@intCast((payload.len >> 8) & 0xff));
        try writer.writeByte(@intCast(payload.len & 0xff));
    } else {
        return error.FrameTooLarge;
    }
    try writer.writeAll(payload);
}

pub fn readTextFrame(reader: *std.Io.Reader, dest: []u8) !usize {
    while (true) {
        var header: [2]u8 = undefined;
        try reader.readSliceAll(&header);
        const opcode = header[0] & 0x0f;
        const masked = header[1] & 0x80 != 0;
        var len: usize = header[1] & 0x7f;
        if (len == 126) {
            var ext: [2]u8 = undefined;
            try reader.readSliceAll(&ext);
            len = (@as(usize, ext[0]) << 8) | ext[1];
        } else if (len == 127) {
            var ext: [8]u8 = undefined;
            try reader.readSliceAll(&ext);
            len = 0;
            for (ext) |b| len = (len << 8) | b;
        }
        var mask = [_]u8{0} ** 4;
        if (masked) try reader.readSliceAll(&mask);
        if (len > dest.len) return error.FrameTooLarge;
        const payload = dest[0..len];
        try reader.readSliceAll(payload);
        if (masked) {
            for (payload, 0..) |*byte, i| byte.* ^= mask[i % 4];
        }
        switch (opcode) {
            0x1 => return len,
            0x8 => return error.Closed,
            0x9 => continue, // ping: ignore; one-shot does not pong
            0xA => continue,
            else => continue,
        }
    }
}

test "writeTurnStdin emits hello attachSession and prompt JSON" {
    var buf: [1024]u8 = undefined;
    const stdin = try writeTurnStdin(&buf, .{
        .token = "secret",
        .session_id = "00000000-0000-0000-0000-000000000001",
        .runtime_id = "00000000-0000-0000-0000-000000000003",
        .prompt = "trace the listener",
    });
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"hello\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"protocolVersion\":4") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"token\":\"secret\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"attachSession\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"requestId\":\"" ++ ATTACH_REQUEST_ID) != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"prompt\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"runtimeId\":\"00000000-0000-0000-0000-000000000003\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "trace the listener") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"loadTaskState\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"start\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\n") != null);
    const attach_at = std.mem.indexOf(u8, stdin, "\"type\":\"attachSession\"").?;
    const prompt_at = std.mem.indexOf(u8, stdin, "\"type\":\"prompt\"").?;
    try std.testing.expect(attach_at < prompt_at);
}

test "writeTurnStdin still attaches before prompt for a new session" {
    var buf: [1024]u8 = undefined;
    const stdin = try writeTurnStdin(&buf, .{
        .prompt = "first",
    });
    try std.testing.expect(std.mem.indexOf(u8, stdin, "loadTaskState") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"hello\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"attachSession\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"prompt\"") != null);
}

test "writeTurnStdin emits start with mapped options before prompt when set" {
    var buf: [1536]u8 = undefined;
    const stdin = try writeTurnStdin(&buf, .{
        .session_id = "00000000-0000-0000-0000-000000000001",
        .prompt = "first",
        .start = .{
            .provider = "fx",
            .binary = "fx",
            .cwd = "/tmp/faku-start",
            .mode = "ask",
            .interaction_mode = "plan",
            .model = "openai/gpt-5.4",
            .computer_use_enabled = false,
        },
    });
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"hello\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"attachSession\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"start\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"provider\":\"fx\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"binary\":\"fx\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"cwd\":\"/tmp/faku-start\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"mode\":\"ask\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"interactionMode\":\"plan\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"model\":\"openai/gpt-5.4\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"computerUseEnabled\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"prompt\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"loadTaskState\"") == null);
    const attach_at = std.mem.indexOf(u8, stdin, "\"type\":\"attachSession\"").?;
    const start_at = std.mem.indexOf(u8, stdin, "\"type\":\"start\"").?;
    const prompt_at = std.mem.indexOf(u8, stdin, "\"type\":\"prompt\"").?;
    try std.testing.expect(attach_at < start_at);
    try std.testing.expect(start_at < prompt_at);
}

test "writeSaveStdin emits hello and saveTaskState without a prompt" {
    var buf: [1024]u8 = undefined;
    const stdin = try writeSaveStdin(&buf, .{
        .token = "secret",
        .skeleton = .{
            .session_id = "00000000-0000-0000-0000-000000000001",
            .title = "mirror me",
            .provider = "fx",
            .project_path = "/tmp/faku",
            .has_started = true,
        },
    });
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"hello\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"token\":\"secret\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"saveTaskState\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"liveSessionIds\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "mirror me") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"prompt\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "loadTaskState") == null);
    try std.testing.expect(!outboundWaitsForTurn(stdin));
}

test "writeLoadStdin emits hello and loadTaskState with a non-nil requestId" {
    var buf: [1024]u8 = undefined;
    const stdin = try writeLoadStdin(&buf, .{
        .token = "secret",
    });
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"hello\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"token\":\"secret\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"loadTaskState\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"prompt\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"saveTaskState\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"requestId\":\"" ++ LOAD_REQUEST_ID) != null);
    try std.testing.expect(!outboundWaitsForTurn(stdin));
    try std.testing.expect(outboundWaitsForLoadResponse(stdin));
}

test "writeHydrateStdin emits hello and hydrateSession with a non-nil requestId" {
    var buf: [1024]u8 = undefined;
    const stdin = try writeHydrateStdin(&buf, .{
        .token = "secret",
        .session_id = "00000000-0000-0000-0000-000000000007",
    });
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"hello\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"token\":\"secret\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"hydrateSession\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"sessionId\":\"00000000-0000-0000-0000-000000000007\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"prompt\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"loadTaskState\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"requestId\":\"" ++ HYDRATE_REQUEST_ID) != null);
    try std.testing.expect(!outboundWaitsForTurn(stdin));
    try std.testing.expect(outboundWaitsForHydrateResponse(stdin));
}

test "writeCloseStdin emits hello and bare closeSession without a prompt" {
    var buf: [1024]u8 = undefined;
    const stdin = try writeCloseStdin(&buf, .{
        .token = "secret",
        .session_id = "00000000-0000-0000-0000-000000000007",
    });
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"hello\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"token\":\"secret\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"closeSession\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"sessionId\":\"00000000-0000-0000-0000-000000000007\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"command\":{\"type\":\"closeSession\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"prompt\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"attachSession\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"removeSession\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"hydrateSession\"") == null);
    try std.testing.expect(!outboundWaitsForTurn(stdin));
    try std.testing.expect(!outboundWaitsForLoadResponse(stdin));
    try std.testing.expect(!outboundWaitsForHydrateResponse(stdin));
}

test "writeCancelStdin emits hello and bare cancel without a prompt" {
    var buf: [1024]u8 = undefined;
    const stdin = try writeCancelStdin(&buf, .{
        .token = "secret",
        .session_id = "00000000-0000-0000-0000-000000000007",
        .runtime_id = "00000000-0000-0000-0000-000000000003",
    });
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"hello\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"token\":\"secret\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"cancel\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"sessionId\":\"00000000-0000-0000-0000-000000000007\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"runtimeId\":\"00000000-0000-0000-0000-000000000003\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"command\":{\"type\":\"cancel\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"prompt\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"attachSession\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"steer\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"closeSession\"") == null);
    try std.testing.expect(!outboundWaitsForTurn(stdin));
    try std.testing.expect(!outboundWaitsForLoadResponse(stdin));
    try std.testing.expect(!outboundWaitsForHydrateResponse(stdin));
}

test "writeSteerStdin emits hello and steer with prompt payload" {
    var buf: [1024]u8 = undefined;
    const stdin = try writeSteerStdin(&buf, .{
        .token = "secret",
        .session_id = "00000000-0000-0000-0000-000000000007",
        .runtime_id = "00000000-0000-0000-0000-000000000003",
        .prompt = "keep going on the listener",
    });
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"hello\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"token\":\"secret\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"steer\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"sessionId\":\"00000000-0000-0000-0000-000000000007\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"runtimeId\":\"00000000-0000-0000-0000-000000000003\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"command\":{\"type\":\"steer\",\"prompt\":\"keep going on the listener\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"prompt\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"attachSession\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"cancel\"") == null);
    try std.testing.expect(!outboundWaitsForTurn(stdin));
    try std.testing.expect(!outboundWaitsForLoadResponse(stdin));
    try std.testing.expect(!outboundWaitsForHydrateResponse(stdin));
}

test "writeGoalStdin emits hello and goal operation without a prompt" {
    var buf: [1024]u8 = undefined;
    const stdin = try writeGoalStdin(&buf, .{
        .token = "secret",
        .session_id = "00000000-0000-0000-0000-000000000007",
        .runtime_id = "00000000-0000-0000-0000-000000000003",
        .operation = .{
            .set = .{
                .objective = "Ship the feature",
                .status = "active",
                .replace = false,
            },
        },
    });
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"hello\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"token\":\"secret\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"goal\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"sessionId\":\"00000000-0000-0000-0000-000000000007\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"runtimeId\":\"00000000-0000-0000-0000-000000000003\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"command\":{\"type\":\"goal\",\"operation\":{\"kind\":\"set\",\"objective\":\"Ship the feature\",\"status\":\"active\",\"replace\":false}}") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"prompt\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"attachSession\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"steer\"") == null);
    try std.testing.expect(!outboundWaitsForTurn(stdin));
    try std.testing.expect(!outboundWaitsForLoadResponse(stdin));
    try std.testing.expect(!outboundWaitsForHydrateResponse(stdin));
    try std.testing.expect(outboundWaitsForGoal(stdin));
    try std.testing.expect(!outboundWaitsForWorkspace(stdin));

    const refresh = try writeGoalStdin(&buf, .{
        .session_id = "00000000-0000-0000-0000-000000000007",
        .operation = .refresh,
    });
    try std.testing.expect(std.mem.indexOf(u8, refresh, "\"kind\":\"refresh\"") != null);
    try std.testing.expect(outboundWaitsForGoal(refresh));

    const clear = try writeGoalStdin(&buf, .{
        .session_id = "00000000-0000-0000-0000-000000000007",
        .operation = .clear,
    });
    try std.testing.expect(std.mem.indexOf(u8, clear, "\"kind\":\"clear\"") != null);
}

test "writeWorkspaceStdin emits hello and workspace push without a prompt" {
    var buf: [1024]u8 = undefined;
    const stdin = try writeWorkspaceStdin(&buf, .{
        .token = "secret",
        .operation = .{ .push = .{ .cwd = "/tmp/faku" } },
    });
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"hello\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"token\":\"secret\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"workspace\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"sessionId\":\"" ++ protocol.NIL_UUID ++ "\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"runtimeId\":\"" ++ protocol.NIL_UUID ++ "\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"requestId\":\"" ++ WORKSPACE_REQUEST_ID) != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"command\":{\"type\":\"workspace\",\"operation\":{\"type\":\"push\",\"cwd\":\"/tmp/faku\"}}") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"prompt\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"attachSession\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"goal\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "force") == null);
    try std.testing.expect(!outboundWaitsForTurn(stdin));
    try std.testing.expect(!outboundWaitsForLoadResponse(stdin));
    try std.testing.expect(!outboundWaitsForHydrateResponse(stdin));
    try std.testing.expect(!outboundWaitsForGoal(stdin));
    try std.testing.expect(outboundWaitsForWorkspace(stdin));
}

test "writeWorkspaceStdin emits hello and workspace createWorktree without a prompt command" {
    var buf: [2048]u8 = undefined;
    const stdin = try writeWorkspaceStdin(&buf, .{
        .token = "secret",
        .operation = .{ .create_worktree = .{
            .project_path = "/tmp/faku",
            .project_id = "00000000-0000-0000-0000-000000000007",
            .session_id = "00000000-0000-0000-0000-000000000007",
            .prompt = "ship the worktree cut",
            .base_branch = "feat",
        } },
    });
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"hello\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"token\":\"secret\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"workspace\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"sessionId\":\"" ++ protocol.NIL_UUID ++ "\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"runtimeId\":\"" ++ protocol.NIL_UUID ++ "\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"requestId\":\"" ++ WORKSPACE_REQUEST_ID) != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"createWorktree\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"project_path\":\"/tmp/faku\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"project_id\":\"00000000-0000-0000-0000-000000000007\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"session_id\":\"00000000-0000-0000-0000-000000000007\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"prompt\":\"ship the worktree cut\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"base_branch\":\"feat\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"prompt\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"attachSession\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"push\"") == null);
    try std.testing.expect(outboundWaitsForWorkspace(stdin));

    const no_base = try writeWorkspaceStdin(&buf, .{
        .operation = .{ .create_worktree = .{
            .project_path = "/tmp/faku",
            .project_id = "00000000-0000-0000-0000-000000000007",
            .session_id = "00000000-0000-0000-0000-000000000007",
            .prompt = "no base",
        } },
    });
    try std.testing.expect(std.mem.indexOf(u8, no_base, "\"base_branch\":null") != null);
    try std.testing.expect(outboundWaitsForWorkspace(no_base));
}

test "writeWorkspaceStdin emits hello and workspace commit without a prompt" {
    var buf: [2048]u8 = undefined;
    const stdin = try writeWorkspaceStdin(&buf, .{
        .token = "secret",
        .operation = .{ .commit = .{
            .cwd = "/tmp/faku",
            .message = "ship the commit cut",
            .include_unstaged = true,
            .push = false,
        } },
    });
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"hello\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"token\":\"secret\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"workspace\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"sessionId\":\"" ++ protocol.NIL_UUID ++ "\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"runtimeId\":\"" ++ protocol.NIL_UUID ++ "\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"requestId\":\"" ++ WORKSPACE_REQUEST_ID) != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"command\":{\"type\":\"workspace\",\"operation\":{\"type\":\"commit\",\"cwd\":\"/tmp/faku\",\"message\":\"ship the commit cut\",\"include_unstaged\":true,\"push\":false}}") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"prompt\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"attachSession\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"push\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"createWorktree\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "includeUnstaged") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "force") == null);
    try std.testing.expect(!outboundWaitsForTurn(stdin));
    try std.testing.expect(!outboundWaitsForLoadResponse(stdin));
    try std.testing.expect(!outboundWaitsForHydrateResponse(stdin));
    try std.testing.expect(!outboundWaitsForGoal(stdin));
    try std.testing.expect(outboundWaitsForWorkspace(stdin));

    const pushed = try writeWorkspaceStdin(&buf, .{
        .operation = .{ .commit = .{
            .cwd = "/tmp/faku",
            .message = "ship and push",
            .include_unstaged = false,
            .push = true,
        } },
    });
    try std.testing.expect(std.mem.indexOf(u8, pushed, "\"include_unstaged\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, pushed, "\"push\":true") != null);
    try std.testing.expect(outboundWaitsForWorkspace(pushed));
}

test "writeWorkspaceStdin emits hello and workspace inspectBranches without a prompt" {
    var buf: [1024]u8 = undefined;
    const stdin = try writeWorkspaceStdin(&buf, .{
        .token = "secret",
        .operation = .{ .inspect_branches = .{ .cwd = "/tmp/faku" } },
    });
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"hello\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"token\":\"secret\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"workspace\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"sessionId\":\"" ++ protocol.NIL_UUID ++ "\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"runtimeId\":\"" ++ protocol.NIL_UUID ++ "\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"requestId\":\"" ++ WORKSPACE_REQUEST_ID) != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"command\":{\"type\":\"workspace\",\"operation\":{\"type\":\"inspectBranches\",\"cwd\":\"/tmp/faku\"}}") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"prompt\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"attachSession\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"push\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"commit\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"inspectCommit\"") == null);
    try std.testing.expect(!outboundWaitsForTurn(stdin));
    try std.testing.expect(outboundWaitsForWorkspace(stdin));
}

test "writeWorkspaceStdin emits hello and workspace checkoutBranch without a prompt" {
    var buf: [1024]u8 = undefined;
    const stdin = try writeWorkspaceStdin(&buf, .{
        .token = "secret",
        .operation = .{ .checkout_branch = .{ .cwd = "/tmp/faku", .branch = "feat", .create = false } },
    });
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"hello\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"token\":\"secret\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"workspace\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"sessionId\":\"" ++ protocol.NIL_UUID ++ "\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"runtimeId\":\"" ++ protocol.NIL_UUID ++ "\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"requestId\":\"" ++ WORKSPACE_REQUEST_ID) != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"command\":{\"type\":\"workspace\",\"operation\":{\"type\":\"checkoutBranch\",\"cwd\":\"/tmp/faku\",\"branch\":\"feat\",\"create\":false}}") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"prompt\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"attachSession\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"inspectBranches\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"inspectCommit\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"push\"") == null);
    try std.testing.expect(!outboundWaitsForTurn(stdin));
    try std.testing.expect(outboundWaitsForWorkspace(stdin));

    const created = try writeWorkspaceStdin(&buf, .{
        .operation = .{ .checkout_branch = .{ .cwd = "/tmp/faku", .branch = "feat/new", .create = true } },
    });
    try std.testing.expect(std.mem.indexOf(u8, created, "\"create\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, created, "\"create\":false") == null);
    try std.testing.expect(outboundWaitsForWorkspace(created));

    var tiny: [32]u8 = undefined;
    try std.testing.expectError(error.NoSpaceLeft, writeWorkspaceStdin(&tiny, .{
        .operation = .{ .checkout_branch = .{ .cwd = "/tmp/faku", .branch = "feat", .create = false } },
    }));
}

test "writeWorkspaceStdin emits hello and workspace inspectCommit without a prompt" {
    var buf: [1024]u8 = undefined;
    const stdin = try writeWorkspaceStdin(&buf, .{
        .token = "secret",
        .operation = .{ .inspect_commit = .{ .cwd = "/tmp/faku" } },
    });
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"hello\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"token\":\"secret\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"workspace\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"sessionId\":\"" ++ protocol.NIL_UUID ++ "\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"runtimeId\":\"" ++ protocol.NIL_UUID ++ "\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"requestId\":\"" ++ WORKSPACE_REQUEST_ID) != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"command\":{\"type\":\"workspace\",\"operation\":{\"type\":\"inspectCommit\",\"cwd\":\"/tmp/faku\"}}") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"prompt\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"attachSession\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"inspectBranches\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"checkoutBranch\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"push\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"commit\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "amend") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "force") == null);
    try std.testing.expect(!outboundWaitsForTurn(stdin));
    try std.testing.expect(outboundWaitsForWorkspace(stdin));

    var tiny: [32]u8 = undefined;
    try std.testing.expectError(error.NoSpaceLeft, writeWorkspaceStdin(&tiny, .{
        .operation = .{ .inspect_commit = .{ .cwd = "/tmp/faku" } },
    }));
}

test "writeWorkspaceStdin emits hello and workspace captureTurnStart without a prompt" {
    var buf: [1024]u8 = undefined;
    const stdin = try writeWorkspaceStdin(&buf, .{
        .token = "secret",
        .operation = .{
            .capture_turn_start = .{
                .cwd = "/tmp/faku",
                .session_id = "00000000-0000-0000-0000-000000000007",
                .turn_count = 2,
            },
        },
    });
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"hello\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"token\":\"secret\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"workspace\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"sessionId\":\"" ++ protocol.NIL_UUID ++ "\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"runtimeId\":\"" ++ protocol.NIL_UUID ++ "\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"requestId\":\"" ++ WORKSPACE_REQUEST_ID) != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"command\":{\"type\":\"workspace\",\"operation\":{\"type\":\"captureTurnStart\",\"cwd\":\"/tmp/faku\",\"sessionId\":\"00000000-0000-0000-0000-000000000007\",\"turnCount\":2}}") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"prompt\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"attachSession\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"inspectCommit\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"inspectBranches\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"captureTurn\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"push\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"commit\"") == null);
    try std.testing.expect(!outboundWaitsForTurn(stdin));
    try std.testing.expect(outboundWaitsForWorkspace(stdin));

    var tiny: [32]u8 = undefined;
    try std.testing.expectError(error.NoSpaceLeft, writeWorkspaceStdin(&tiny, .{
        .operation = .{
            .capture_turn_start = .{
                .cwd = "/tmp/faku",
                .session_id = "00000000-0000-0000-0000-000000000007",
                .turn_count = 1,
            },
        },
    }));
}

test "writeWorkspaceStdin emits hello and workspace captureTurn without a prompt" {
    var buf: [1024]u8 = undefined;
    const stdin = try writeWorkspaceStdin(&buf, .{
        .token = "secret",
        .operation = .{
            .capture_turn = .{
                .cwd = "/tmp/faku",
                .session_id = "00000000-0000-0000-0000-000000000007",
                .turn_count = 2,
            },
        },
    });
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"hello\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"token\":\"secret\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"workspace\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"sessionId\":\"" ++ protocol.NIL_UUID ++ "\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"runtimeId\":\"" ++ protocol.NIL_UUID ++ "\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"requestId\":\"" ++ WORKSPACE_REQUEST_ID) != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"command\":{\"type\":\"workspace\",\"operation\":{\"type\":\"captureTurn\",\"cwd\":\"/tmp/faku\",\"sessionId\":\"00000000-0000-0000-0000-000000000007\",\"turnCount\":2}}") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"prompt\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"attachSession\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"captureTurnStart\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"inspectCommit\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"inspectBranches\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"push\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"commit\"") == null);
    try std.testing.expect(!outboundWaitsForTurn(stdin));
    try std.testing.expect(outboundWaitsForWorkspace(stdin));

    var tiny: [32]u8 = undefined;
    try std.testing.expectError(error.NoSpaceLeft, writeWorkspaceStdin(&tiny, .{
        .operation = .{
            .capture_turn = .{
                .cwd = "/tmp/faku",
                .session_id = "00000000-0000-0000-0000-000000000007",
                .turn_count = 1,
            },
        },
    }));
}

test "writeWorkspaceStdin emits hello and workspace generateCommitMessage without a prompt" {
    var buf: [1024]u8 = undefined;
    const stdin = try writeWorkspaceStdin(&buf, .{
        .token = "secret",
        .operation = .{
            .generate_commit_message = .{
                .cwd = "/tmp/faku",
                .include_unstaged = true,
                .invocation = .{
                    .provider = "fx",
                    .binary = "/home/me/.fx/bin/fx",
                    .model = "gpt-5",
                    .reasoning_effort = "high",
                },
            },
        },
    });
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"hello\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"token\":\"secret\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"workspace\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"sessionId\":\"" ++ protocol.NIL_UUID ++ "\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"runtimeId\":\"" ++ protocol.NIL_UUID ++ "\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"requestId\":\"" ++ WORKSPACE_REQUEST_ID) != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"command\":{\"type\":\"workspace\",\"operation\":{\"type\":\"generateCommitMessage\",\"cwd\":\"/tmp/faku\",\"includeUnstaged\":true,\"invocation\":{\"provider\":\"fx\",\"binary\":\"/home/me/.fx/bin/fx\",\"model\":\"gpt-5\",\"reasoning_effort\":\"high\"}}}") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"prompt\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"attachSession\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"inspectCommit\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"commit\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "include_unstaged") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "reasoningEffort") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "amend") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "force") == null);
    try std.testing.expect(!outboundWaitsForTurn(stdin));
    try std.testing.expect(outboundWaitsForWorkspace(stdin));

    const omitted = try writeWorkspaceStdin(&buf, .{
        .operation = .{
            .generate_commit_message = .{
                .cwd = "/tmp/faku",
                .include_unstaged = false,
                .invocation = .{
                    .provider = "claude",
                    .binary = "claude",
                },
            },
        },
    });
    try std.testing.expect(std.mem.indexOf(u8, omitted, "\"includeUnstaged\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, omitted, "\"model\":null") != null);
    try std.testing.expect(std.mem.indexOf(u8, omitted, "\"reasoning_effort\":null") != null);
    try std.testing.expect(std.mem.indexOf(u8, omitted, "\"type\":\"prompt\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, omitted, "\"type\":\"attachSession\"") == null);

    var tiny: [32]u8 = undefined;
    try std.testing.expectError(error.NoSpaceLeft, writeWorkspaceStdin(&tiny, .{
        .operation = .{
            .generate_commit_message = .{
                .cwd = "/tmp/faku",
                .include_unstaged = true,
                .invocation = .{
                    .provider = "fx",
                    .binary = "fx",
                },
            },
        },
    }));
}

test "writeWorkspaceStdin emits hello and workspace listTree with expanded_paths" {
    var buf: [1024]u8 = undefined;
    const stdin = try writeWorkspaceStdin(&buf, .{
        .token = "secret",
        .operation = .{
            .list_tree = .{
                .root = "/tmp/faku",
                .expanded_paths = &.{ "/tmp/faku/src", "/tmp/faku/src/lib" },
            },
        },
    });
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"hello\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"token\":\"secret\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"workspace\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"sessionId\":\"" ++ protocol.NIL_UUID ++ "\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"runtimeId\":\"" ++ protocol.NIL_UUID ++ "\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"requestId\":\"" ++ WORKSPACE_REQUEST_ID) != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"command\":{\"type\":\"workspace\",\"operation\":{\"type\":\"listTree\",\"root\":\"/tmp/faku\",\"expanded_paths\":[\"/tmp/faku/src\",\"/tmp/faku/src/lib\"]}}") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"expanded_paths\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "expandedPaths") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"prompt\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"attachSession\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"inspectCommit\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"inspectBranches\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"generateCommitMessage\"") == null);
    try std.testing.expect(!outboundWaitsForTurn(stdin));
    try std.testing.expect(outboundWaitsForWorkspace(stdin));

    const empty = try writeWorkspaceStdin(&buf, .{
        .operation = .{ .list_tree = .{ .root = "/tmp/faku" } },
    });
    try std.testing.expect(std.mem.indexOf(u8, empty, "\"expanded_paths\":[]") != null);
    try std.testing.expect(std.mem.indexOf(u8, empty, "expandedPaths") == null);
    try std.testing.expect(outboundWaitsForWorkspace(empty));

    var tiny: [32]u8 = undefined;
    try std.testing.expectError(error.NoSpaceLeft, writeWorkspaceStdin(&tiny, .{
        .operation = .{ .list_tree = .{ .root = "/tmp/faku" } },
    }));
}

test "writeWorkspaceStdin emits hello and workspace collectReviewDiff without a prompt" {
    var buf: [1024]u8 = undefined;
    const stdin = try writeWorkspaceStdin(&buf, .{
        .token = "secret",
        .operation = .{
            .collect_review_diff = .{ .cwd = "/tmp/faku", .source = .branch },
        },
    });
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"hello\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"token\":\"secret\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"workspace\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"sessionId\":\"" ++ protocol.NIL_UUID ++ "\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"runtimeId\":\"" ++ protocol.NIL_UUID ++ "\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"requestId\":\"" ++ WORKSPACE_REQUEST_ID) != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"command\":{\"type\":\"workspace\",\"operation\":{\"type\":\"collectReviewDiff\",\"cwd\":\"/tmp/faku\",\"source\":\"branch\"}}") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"prompt\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"attachSession\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"listTree\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"inspectCommit\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "amend") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "force") == null);
    try std.testing.expect(!outboundWaitsForTurn(stdin));
    try std.testing.expect(outboundWaitsForWorkspace(stdin));

    const uncommitted = try writeWorkspaceStdin(&buf, .{
        .operation = .{ .collect_review_diff = .{ .cwd = "/tmp/faku", .source = .uncommitted } },
    });
    try std.testing.expect(std.mem.indexOf(u8, uncommitted, "\"source\":\"uncommitted\"") != null);
    const staged = try writeWorkspaceStdin(&buf, .{
        .operation = .{ .collect_review_diff = .{ .cwd = "/tmp/faku", .source = .staged } },
    });
    try std.testing.expect(std.mem.indexOf(u8, staged, "\"source\":\"staged\"") != null);
    const unstaged = try writeWorkspaceStdin(&buf, .{
        .operation = .{ .collect_review_diff = .{ .cwd = "/tmp/faku", .source = .unstaged } },
    });
    try std.testing.expect(std.mem.indexOf(u8, unstaged, "\"source\":\"unstaged\"") != null);
    const committed = try writeWorkspaceStdin(&buf, .{
        .operation = .{ .collect_review_diff = .{ .cwd = "/tmp/faku", .source = .committed } },
    });
    try std.testing.expect(std.mem.indexOf(u8, committed, "\"source\":\"committed\"") != null);
    try std.testing.expect(outboundWaitsForWorkspace(committed));

    const last_turn = try writeWorkspaceStdin(&buf, .{
        .operation = .{
            .collect_review_diff = .{
                .cwd = "/tmp/faku",
                .source = .{ .last_turn = .{
                    .session_id = "11111111-1111-1111-1111-111111111111",
                    .turn_id = "22222222-2222-2222-2222-222222222222",
                    .turn_count = 2,
                } },
            },
        },
    });
    try std.testing.expect(std.mem.indexOf(u8, last_turn, "\"source\":{\"lastTurn\":{\"session_id\":\"11111111-1111-1111-1111-111111111111\",\"turn_id\":\"22222222-2222-2222-2222-222222222222\",\"turn_count\":2}}") != null);
    try std.testing.expect(std.mem.indexOf(u8, last_turn, "turnCount") == null);

    var tiny: [32]u8 = undefined;
    try std.testing.expectError(error.NoSpaceLeft, writeWorkspaceStdin(&tiny, .{
        .operation = .{ .collect_review_diff = .{ .cwd = "/tmp/faku", .source = .branch } },
    }));
}

test "writeWorkspaceStdin emits hello and workspace browseDirectory with null or absolute path" {
    var buf: [1024]u8 = undefined;
    const home = try writeWorkspaceStdin(&buf, .{
        .token = "secret",
        .operation = .{ .browse_directory = .{} },
    });
    try std.testing.expect(std.mem.indexOf(u8, home, "\"type\":\"hello\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, home, "\"token\":\"secret\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, home, "\"type\":\"workspace\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, home, "\"sessionId\":\"" ++ protocol.NIL_UUID ++ "\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, home, "\"runtimeId\":\"" ++ protocol.NIL_UUID ++ "\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, home, "\"requestId\":\"" ++ WORKSPACE_REQUEST_ID) != null);
    try std.testing.expect(std.mem.indexOf(u8, home, "\"command\":{\"type\":\"workspace\",\"operation\":{\"type\":\"browseDirectory\",\"path\":null}}") != null);
    try std.testing.expect(std.mem.indexOf(u8, home, "\"type\":\"prompt\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, home, "\"type\":\"attachSession\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, home, "\"type\":\"listTree\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, home, "\"type\":\"collectReviewDiff\"") == null);
    try std.testing.expect(!outboundWaitsForTurn(home));
    try std.testing.expect(outboundWaitsForWorkspace(home));

    const abs = try writeWorkspaceStdin(&buf, .{
        .operation = .{ .browse_directory = .{ .path = "/abs/dir" } },
    });
    try std.testing.expect(std.mem.indexOf(u8, abs, "\"path\":\"/abs/dir\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, abs, "\"path\":null") == null);
    try std.testing.expect(outboundWaitsForWorkspace(abs));

    var tiny: [32]u8 = undefined;
    try std.testing.expectError(error.NoSpaceLeft, writeWorkspaceStdin(&tiny, .{
        .operation = .{ .browse_directory = .{ .path = "/abs/dir" } },
    }));
}

test "writeWorkspaceStdin emits hello and workspace readTextFile with snake_case relative_path" {
    var buf: [1024]u8 = undefined;
    const stdin = try writeWorkspaceStdin(&buf, .{
        .token = "secret",
        .operation = .{ .read_text_file = .{ .root = "/tmp/faku", .relative_path = "src/main.zig" } },
    });
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"hello\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"token\":\"secret\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"workspace\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"sessionId\":\"" ++ protocol.NIL_UUID ++ "\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"runtimeId\":\"" ++ protocol.NIL_UUID ++ "\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"requestId\":\"" ++ WORKSPACE_REQUEST_ID) != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"command\":{\"type\":\"workspace\",\"operation\":{\"type\":\"readTextFile\",\"root\":\"/tmp/faku\",\"relative_path\":\"src/main.zig\"}}") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "relativePath") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"prompt\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"attachSession\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"listTree\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"browseDirectory\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"writeTextFile\"") == null);
    try std.testing.expect(!outboundWaitsForTurn(stdin));
    try std.testing.expect(outboundWaitsForWorkspace(stdin));

    var tiny: [32]u8 = undefined;
    try std.testing.expectError(error.NoSpaceLeft, writeWorkspaceStdin(&tiny, .{
        .operation = .{ .read_text_file = .{ .root = "/tmp/faku", .relative_path = "src/main.zig" } },
    }));
}

test "writeWorkspaceStdin emits hello and workspace writeTextFile with snake_case relative_path and content" {
    var buf: [1024]u8 = undefined;
    const stdin = try writeWorkspaceStdin(&buf, .{
        .token = "secret",
        .operation = .{ .write_text_file = .{ .root = "/tmp/faku", .relative_path = "src/main.zig", .content = "hello\nworld" } },
    });
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"hello\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"token\":\"secret\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"workspace\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"sessionId\":\"" ++ protocol.NIL_UUID ++ "\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"runtimeId\":\"" ++ protocol.NIL_UUID ++ "\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"requestId\":\"" ++ WORKSPACE_REQUEST_ID) != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"command\":{\"type\":\"workspace\",\"operation\":{\"type\":\"writeTextFile\",\"root\":\"/tmp/faku\",\"relative_path\":\"src/main.zig\",\"content\":\"hello\\nworld\"}}") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"writeTextFile\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "relativePath") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"readTextFile\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"prompt\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"attachSession\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"listTree\"") == null);
    try std.testing.expect(!outboundWaitsForTurn(stdin));
    try std.testing.expect(outboundWaitsForWorkspace(stdin));

    var tiny: [32]u8 = undefined;
    try std.testing.expectError(error.NoSpaceLeft, writeWorkspaceStdin(&tiny, .{
        .operation = .{ .write_text_file = .{ .root = "/tmp/faku", .relative_path = "src/main.zig", .content = "hello" } },
    }));
}

test "localIdFromWire reverses wireUuid" {
    var buf: [36]u8 = undefined;
    const encoded = wireUuid(7, &buf);
    try std.testing.expectEqual(@as(?u32, 7), localIdFromWire(encoded));
    try std.testing.expectEqual(@as(?u32, 0), localIdFromWire(protocol.NIL_UUID));
    try std.testing.expect(localIdFromWire("a1b2c3d4-e5f6-7890-abcd-ef1234567890") == null);
}

test "parseAddress strips ws scheme and keeps /v1" {
    const parsed = parseAddress("ws://127.0.0.1:8787/v1").?;
    try std.testing.expectEqualStrings("127.0.0.1", parsed.host);
    try std.testing.expectEqual(@as(u16, 8787), parsed.port);
    try std.testing.expectEqualStrings("/v1", parsed.path);
    try std.testing.expect(parseAddress("") == null);
    try std.testing.expect(parseAddress("no-port") == null);
}

test "websocket accept key matches RFC 6455 example" {
    var dest: [28]u8 = undefined;
    const accept = wsAcceptKey("dGhlIHNhbXBsZSBub25jZQ==", &dest);
    try std.testing.expectEqualStrings("s3pPLMBiTxaQ9kYGzzhZRbK+xOo=", accept);
}

test "handshake request is an HTTP upgrade to /v1" {
    var buf: [512]u8 = undefined;
    const req = try writeHandshakeRequest(&buf, "127.0.0.1", 8787, "/v1", "dGhlIHNhbXBsZSBub25jZQ==");
    try std.testing.expect(std.mem.startsWith(u8, req, "GET /v1 HTTP/1.1\r\n"));
    try std.testing.expect(std.mem.indexOf(u8, req, "Upgrade: websocket") != null);
    try std.testing.expect(std.mem.indexOf(u8, req, "Sec-WebSocket-Version: 13") != null);
}
