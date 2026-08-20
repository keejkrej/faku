//! One-shot waku-daemon sidecar.
//!
//! Native `fx.spawn` writes stdin once and then closes it. This module
//! builds that buffer (hello + optional loadTaskState + prompt) and, when
//! run as `faku daemon-proxy <addr>`, forwards those JSON frames over
//! `ws://{addr}/v1`, prints each incoming text frame as one stdout line,
//! and exits on `turnFinished` / `rejected` / `error`.
//!
//! The desktop update loop never holds a WebSocket. Catalog persist stays
//! local `sessions.json`; `loadTaskState` on the wire is only for the
//! daemon, not a replacement for the store.

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
    session_id: []const u8 = protocol.NIL_UUID,
    runtime_id: []const u8 = protocol.NIL_UUID,
    prompt: []const u8,
    load_task_state: bool = false,
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
/// for a 512-byte composer draft.
pub fn writeTurnStdin(buf: []u8, args: TurnStdin) WriteError![]const u8 {
    var cur = Cursor{ .buf = buf };
    const hello = try protocol.writeClientHello(cur.remaining(), args.token, args.client_id, &.{});
    cur.pos += hello.len;
    try cur.write("\n");
    if (args.load_task_state) {
        const load = try protocol.writeBareCommand(
            cur.remaining(),
            args.request_id,
            args.session_id,
            args.runtime_id,
            .load_task_state,
        );
        cur.pos += load.len;
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
    std.crypto.random.bytes(&key_raw);
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
        writeTextFrame(&writer.interface, frame) catch {
            try writeStdoutLine(stdout, "{\"type\":\"rejected\",\"message\":\"send failed\"}");
            return error.SendFailed;
        };
        writer.interface.flush() catch {
            try writeStdoutLine(stdout, "{\"type\":\"rejected\",\"message\":\"send failed\"}");
            return error.SendFailed;
        };
    }

    var payload_buf: [nativeLineCap]u8 = undefined;
    while (true) {
        const n = readTextFrame(&reader.interface, &payload_buf) catch |err| switch (err) {
            error.Closed => return,
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
        if (protocol.isTerminalServerFrame(parsed)) return;
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

pub fn writeTextFrame(writer: *std.Io.Writer, payload: []const u8) !void {
    var mask: [4]u8 = undefined;
    std.crypto.random.bytes(&mask);
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

test "writeTurnStdin emits hello loadTaskState and prompt JSON" {
    var buf: [1024]u8 = undefined;
    const stdin = try writeTurnStdin(&buf, .{
        .token = "secret",
        .session_id = "00000000-0000-0000-0000-000000000001",
        .prompt = "trace the listener",
        .load_task_state = true,
    });
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"hello\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"protocolVersion\":3") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"token\":\"secret\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"loadTaskState\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"prompt\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "trace the listener") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\n") != null);
}

test "writeTurnStdin skips loadTaskState for a new session" {
    var buf: [1024]u8 = undefined;
    const stdin = try writeTurnStdin(&buf, .{
        .prompt = "first",
        .load_task_state = false,
    });
    try std.testing.expect(std.mem.indexOf(u8, stdin, "loadTaskState") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"hello\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdin, "\"type\":\"prompt\"") != null);
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
