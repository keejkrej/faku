//! One-shot ACP sidecar (`fx acp`, probed `{binary} acp`).
//!
//! Native `fx.spawn` writes stdin once and then closes it. This process
//! is `faku acp-proxy -- <child argv…>`. It reads that ACP NDJSON batch
//! (initialize / session/new|resume / set_mode / set_config_option /
//! session/prompt, including a first-cut image content block when the
//! window attached one), spawns the child, writes the batch, and keeps the
//! child's stdin open so official `session/request_permission` can be
//! answered from the access mode already on this run (env / set_mode).
//! Other agent requests are rejected so they do not hang. The window
//! never writes after spawn. This sidecar does not speak daemon JSON.

const std = @import("std");
const acp = @import("acp.zig");

pub const SUBCOMMAND = "acp-proxy";

const nativeLineCap = 64 * 1024;
const stdinCap = acp.stdin_cap;

pub fn isSidecarArgv(args: []const []const u8) bool {
    return args.len >= 2 and std.mem.eql(u8, args[1], SUBCOMMAND);
}

/// Child argv after `--`. Empty when the separator or the child is missing.
pub fn childArgvAfterDash(args: []const []const u8) []const []const u8 {
    for (args, 0..) |arg, i| {
        if (std.mem.eql(u8, arg, "--") and i + 1 < args.len) return args[i + 1 ..];
    }
    return &.{};
}

/// `true` once this process is the sidecar (do not start the GUI).
pub fn maybeRun(init: std.process.Init) !bool {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (!isSidecarArgv(args)) return false;
    try runFromStdio(init.io, args);
    return true;
}

pub fn runFromStdio(io: std.Io, args: []const []const u8) !void {
    var read_buf: [512]u8 = undefined;
    var stdin_reader = std.Io.File.stdin().reader(io, &read_buf);
    var collected: [stdinCap]u8 = undefined;
    const n = readAll(&stdin_reader.interface, &collected);
    const child_argv = childArgvAfterDash(args);
    if (child_argv.len == 0) return error.MissingChild;
    const access_mode = acp.accessModeFromSidecarRun(child_argv, collected[0..n]);
    try run(io, child_argv, collected[0..n], access_mode);
}

fn readAll(reader: *std.Io.Reader, dest: []u8) usize {
    var n: usize = 0;
    while (n < dest.len) {
        const got = reader.readSliceShort(dest[n..]) catch break;
        if (got == 0) break;
        n += got;
    }
    return n;
}

pub const BatchSplit = struct {
    prefix: []const u8,
    suffix: []const u8,
    needs_session_id: bool,
};

/// Finds `"method": "session/new"` in an ACP NDJSON batch, allowing optional whitespace.
pub fn findSessionNewMethod(batch: []const u8) ?usize {
    const key = "\"method\"";
    var start: usize = 0;
    while (std.mem.indexOfPos(u8, batch, start, key)) |pos| {
        var cur = pos + key.len;
        while (cur < batch.len and (batch[cur] == ' ' or batch[cur] == '\t')) cur += 1;
        if (cur < batch.len and batch[cur] == ':') {
            cur += 1;
            while (cur < batch.len and (batch[cur] == ' ' or batch[cur] == '\t')) cur += 1;
            const target = "\"session/new\"";
            if (cur + target.len <= batch.len and std.mem.eql(u8, batch[cur .. cur + target.len], target)) {
                return cur + target.len;
            }
        }
        start = pos + key.len;
    }
    return null;
}

/// Splits an incoming ACP NDJSON batch around `session/new`.
/// When creating a new session, the child mints `sessionId` in its
/// response to `session/new`. Subsequent commands (`session/set_mode`,
/// `session/set_config_option`, `session/prompt`) carry an empty
/// `sessionId: ""` that must be rewritten with the minted id.
pub fn splitBatch(batch: []const u8) BatchSplit {
    if (findSessionNewMethod(batch)) |pos| {
        if (std.mem.indexOfScalarPos(u8, batch, pos, '\n')) |nl| {
            return .{
                .prefix = batch[0 .. nl + 1],
                .suffix = batch[nl + 1 ..],
                .needs_session_id = true,
            };
        }
    }
    return .{
        .prefix = batch,
        .suffix = &.{},
        .needs_session_id = false,
    };
}

pub const EmptySessionIdMatch = struct {
    start: usize,
    end: usize,
};

/// Finds an empty `"sessionId": ""` (with optional whitespace) in a JSON line.
pub fn findEmptySessionId(line: []const u8) ?EmptySessionIdMatch {
    const key = "\"sessionId\"";
    const pos = std.mem.indexOf(u8, line, key) orelse return null;
    var cur = pos + key.len;
    while (cur < line.len and (line[cur] == ' ' or line[cur] == '\t')) cur += 1;
    if (cur >= line.len or line[cur] != ':') return null;
    cur += 1;
    while (cur < line.len and (line[cur] == ' ' or line[cur] == '\t')) cur += 1;
    if (cur + 1 < line.len and line[cur] == '"' and line[cur + 1] == '"') {
        return .{ .start = pos, .end = cur + 2 };
    }
    return null;
}

/// Writes `suffix` lines to `writer`, replacing empty `"sessionId": ""`
/// in each line with `"sessionId":"<session_id>"`.
pub fn writeSuffixWithSessionId(writer: anytype, suffix: []const u8, session_id: []const u8) !void {
    var rest = suffix;
    while (rest.len > 0) {
        const line_len = if (std.mem.indexOfScalar(u8, rest, '\n')) |nl| nl else rest.len;
        var line = rest[0..line_len];
        rest = if (line_len < rest.len) rest[line_len + 1 ..] else &.{};
        if (line.len > 0 and line[line.len - 1] == '\r') {
            line = line[0 .. line.len - 1];
        }
        if (findEmptySessionId(line)) |match| {
            try writer.writeAll(line[0..match.start]);
            try writer.writeAll("\"sessionId\":\"");
            try writer.writeAll(session_id);
            try writer.writeAll("\"");
            try writer.writeAll(line[match.end..]);
        } else {
            try writer.writeAll(line);
        }
        try writer.writeByte('\n');
    }
}

pub fn run(io: std.Io, child_argv: []const []const u8, batch: []const u8, access_mode: []const u8) !void {
    var child = try std.process.spawn(io, .{
        .argv = child_argv,
        .stdin = .pipe,
        .stdout = .pipe,
        .stderr = .inherit,
    });

    const child_in = child.stdin orelse return error.MissingStdinPipe;
    const child_out = child.stdout orelse return error.MissingStdoutPipe;

    var write_buf: [1024]u8 = undefined;
    var writer = child_in.writerStreaming(io, &write_buf);

    const split = splitBatch(batch);
    writer.interface.writeAll(split.prefix) catch {};
    writer.interface.flush() catch {};

    var stdout_buf: [1024]u8 = undefined;
    var host = std.Io.File.stdout().writerStreaming(io, &stdout_buf);
    var line_read_buf: [512]u8 = undefined;
    var reader = child_out.readerStreaming(io, &line_read_buf);
    var line_buf: [nativeLineCap]u8 = undefined;
    var reply_buf: [512]u8 = undefined;

    var waiting_for_session_id = split.needs_session_id and split.suffix.len > 0;

    while (readLine(&reader.interface, &line_buf)) |line| {
        writeStdoutLine(&host.interface, line) catch break;
        host.interface.flush() catch break;

        if (waiting_for_session_id) {
            const parsed = acp.parseLine(line);
            const minted = acp.mintedSessionId(parsed);
            if (minted.len > 0) {
                writeSuffixWithSessionId(&writer.interface, split.suffix, minted) catch {};
                writer.interface.flush() catch {};
                waiting_for_session_id = false;
            } else if (parsed.has_error and parsed.id == acp.ID_SESSION) {
                writer.interface.writeAll(split.suffix) catch {};
                writer.interface.flush() catch {};
                waiting_for_session_id = false;
            }
        }

        if (acp.replyForAgentRequest(line, access_mode, &reply_buf)) |reply| {
            writer.interface.writeAll(reply) catch break;
            writer.interface.flush() catch break;
        }
    }

    _ = child.wait(io) catch {};
}

fn readLine(reader: *std.Io.Reader, dest: []u8) ?[]const u8 {
    var n: usize = 0;
    while (n < dest.len) {
        const byte = reader.takeByte() catch return if (n == 0) null else dest[0..n];
        if (byte == '\n') return dest[0..n];
        dest[n] = byte;
        n += 1;
    }
    return dest[0..n];
}

fn writeStdoutLine(stdout: *std.Io.Writer, line: []const u8) !void {
    try stdout.writeAll(line);
    try stdout.writeByte('\n');
}

test "acp-proxy argv is the subcommand plus child after --" {
    try std.testing.expect(isSidecarArgv(&.{ "faku", SUBCOMMAND, "--", "fx", "acp" }));
    try std.testing.expect(!isSidecarArgv(&.{ "faku", "daemon-proxy", "127.0.0.1:9" }));
    try std.testing.expect(!isSidecarArgv(&.{ "faku" }));

    const child = childArgvAfterDash(&.{ "faku", SUBCOMMAND, "--", "fx", "acp" });
    try std.testing.expectEqual(@as(usize, 2), child.len);
    try std.testing.expectEqualStrings("fx", child[0]);
    try std.testing.expectEqualStrings("acp", child[1]);
    try std.testing.expectEqual(@as(usize, 0), childArgvAfterDash(&.{ "faku", SUBCOMMAND }).len);
    try std.testing.expectEqual(@as(usize, 0), childArgvAfterDash(&.{ "faku", SUBCOMMAND, "--" }).len);
}

test "splitBatch isolates prefix and suffix around session/new" {
    const batch_new =
        "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\"}\n" ++
        "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"session/new\",\"params\":{\"cwd\":\".\"}}\n" ++
        "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"session/set_mode\",\"params\":{\"sessionId\":\"\"}}\n" ++
        "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"session/prompt\",\"params\":{\"sessionId\":\"\"}}\n";

    const split = splitBatch(batch_new);
    try std.testing.expect(split.needs_session_id);
    try std.testing.expect(std.mem.indexOf(u8, split.prefix, "\"method\":\"session/new\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, split.prefix, "\"method\":\"session/prompt\"") == null);
    const batch_new_spaced =
        "{\"jsonrpc\": \"2.0\", \"id\": 1, \"method\": \"initialize\"}\n" ++
        "{\"jsonrpc\": \"2.0\", \"id\": 2, \"method\": \"session/new\", \"params\": {\"cwd\": \".\"}}\n" ++
        "{\"jsonrpc\": \"2.0\", \"id\": 4, \"method\": \"session/prompt\", \"params\": {\"sessionId\": \"\"}}\n";

    const split_spaced = splitBatch(batch_new_spaced);
    try std.testing.expect(split_spaced.needs_session_id);
    try std.testing.expect(std.mem.indexOf(u8, split_spaced.prefix, "\"session/new\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, split_spaced.suffix, "\"session/prompt\"") != null);

    const batch_resume =
        "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\"}\n" ++
        "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"session/resume\",\"params\":{\"sessionId\":\"abc\"}}\n" ++
        "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"session/prompt\",\"params\":{\"sessionId\":\"abc\"}}\n";

    const split_resume = splitBatch(batch_resume);
    try std.testing.expect(!split_resume.needs_session_id);
    try std.testing.expectEqualStrings(batch_resume, split_resume.prefix);
    try std.testing.expectEqual(@as(usize, 0), split_resume.suffix.len);
}

test "writeSuffixWithSessionId rewrites empty sessionId with minted id" {
    const suffix =
        "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"session/set_mode\",\"params\":{\"sessionId\":\"\",\"modeId\":\"code\"}}\n" ++
        "{\"jsonrpc\": \"2.0\", \"id\": 4, \"method\": \"session/prompt\", \"params\": {\"sessionId\": \"\", \"prompt\": [{\"type\": \"text\", \"text\": \"hello\"}]}}\n";

    var out_buf: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&out_buf);
    try writeSuffixWithSessionId(&writer, suffix, "minted-xyz-123");

    const result = writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, result, "\"sessionId\":\"minted-xyz-123\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "\"sessionId\":\"\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, result, "\"sessionId\": \"\"") == null);
}
