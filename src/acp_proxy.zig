//! One-shot ACP sidecar (`fx acp`, probed `{binary} acp`).
//!
//! Native `fx.spawn` writes stdin once and then closes it. This process
//! is `faku acp-proxy -- <child argv…>`. It reads that ACP NDJSON batch
//! (initialize / session/new|resume / set_mode / set_config_option /
//! session/prompt), spawns the child, writes the batch, and keeps the
//! child's stdin open so official `session/request_permission` can be
//! answered from the access mode already on this run (env / set_mode).
//! Other agent requests are rejected so they do not hang. The window
//! never writes after spawn. This sidecar does not speak daemon JSON.

const std = @import("std");
const acp = @import("acp.zig");

pub const SUBCOMMAND = "acp-proxy";

const nativeLineCap = 64 * 1024;
const stdinCap = 8192;

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
    writer.interface.writeAll(batch) catch {};
    writer.interface.flush() catch {};

    var stdout_buf: [1024]u8 = undefined;
    var host = std.Io.File.stdout().writerStreaming(io, &stdout_buf);
    var line_read_buf: [512]u8 = undefined;
    var reader = child_out.readerStreaming(io, &line_read_buf);
    var line_buf: [nativeLineCap]u8 = undefined;
    var reply_buf: [512]u8 = undefined;

    while (readLine(&reader.interface, &line_buf)) |line| {
        writeStdoutLine(&host.interface, line) catch break;
        host.interface.flush() catch break;
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
