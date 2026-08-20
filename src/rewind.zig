//! Workspace HEAD snapshots for a later rewind. This cut only records.
//!
//! After a successful turn, Faku stores `{ sha, ref, recorded_at }` on the
//! session when `project_path` is a git work tree. It does not run
//! `git reset` / `checkout`, create extra refs, or offer rewind UI.

const std = @import("std");

pub const max_refs: usize = 20;
pub const max_sha: usize = 64;
pub const max_ref_name: usize = 16;
pub const recorded_ref = "HEAD";

pub const Ref = struct {
    sha_storage: [max_sha]u8 = [_]u8{0} ** max_sha,
    sha_len: usize = 0,
    ref_storage: [max_ref_name]u8 = [_]u8{0} ** max_ref_name,
    ref_len: usize = 0,
    recorded_at: i64 = 0,

    pub fn sha(self: *const Ref) []const u8 {
        return self.sha_storage[0..self.sha_len];
    }

    pub fn refName(self: *const Ref) []const u8 {
        return self.ref_storage[0..self.ref_len];
    }
};

pub const Capture = struct {
    sha: []const u8,
    recorded_at: i64,
};

pub fn isGitWorkTree(io: std.Io, project_path: []const u8) bool {
    if (project_path.len == 0) return false;
    var git_buf: [std.fs.max_path_bytes]u8 = undefined;
    const git_path = std.fmt.bufPrint(&git_buf, "{s}{s}.git", .{ project_path, std.fs.path.sep_str }) catch return false;
    return directoryExists(io, git_path) or fileExists(io, git_path);
}

/// One-shot `git -C <path> rev-parse HEAD`. No Native git API.
pub fn revParseHead(allocator: std.mem.Allocator, io: std.Io, project_path: []const u8, dest: []u8) ?[]const u8 {
    if (project_path.len == 0 or dest.len == 0) return null;
    const result = std.process.run(allocator, io, .{
        .argv = &.{ "git", "-C", project_path, "rev-parse", "HEAD" },
        .stdout_limit = .limited(128),
        .stderr_limit = .limited(256),
    }) catch return null;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    if (result.term != .exited or result.term.exited != 0) return null;
    const trimmed = std.mem.trim(u8, result.stdout, " \r\n\t");
    if (trimmed.len == 0 or trimmed.len > dest.len) return null;
    @memcpy(dest[0..trimmed.len], trimmed);
    return dest[0..trimmed.len];
}

pub fn nowUnixSeconds(io: std.Io) i64 {
    return std.Io.Clock.real.now(io).toSeconds();
}

/// Record HEAD when `project_path` exists and is a git work tree. Missing
/// or non-git paths skip quietly.
pub fn captureHead(allocator: std.mem.Allocator, io: std.Io, project_path: []const u8, dest: []u8) ?Capture {
    if (!isGitWorkTree(io, project_path)) return null;
    const sha = revParseHead(allocator, io, project_path, dest) orelse return null;
    return .{ .sha = sha, .recorded_at = nowUnixSeconds(io) };
}

pub fn append(dest: *[max_refs]Ref, count: *usize, sha: []const u8, ref_name: []const u8, recorded_at: i64) void {
    if (sha.len == 0) return;
    if (count.* == max_refs) {
        std.mem.copyForwards(Ref, dest[0 .. max_refs - 1], dest[1..max_refs]);
        count.* = max_refs - 1;
    }
    dest[count.*] = .{
        .recorded_at = recorded_at,
    };
    copyFixed(&dest[count.*].sha_storage, &dest[count.*].sha_len, sha);
    copyFixed(&dest[count.*].ref_storage, &dest[count.*].ref_len, ref_name);
    count.* += 1;
}

fn copyFixed(storage: []u8, len: *usize, text: []const u8) void {
    const take = @min(storage.len, text.len);
    @memcpy(storage[0..take], text[0..take]);
    len.* = take;
}

fn directoryExists(io: std.Io, path: []const u8) bool {
    var dir = std.Io.Dir.cwd().openDir(io, path, .{}) catch return false;
    dir.close(io);
    return true;
}

fn fileExists(io: std.Io, path: []const u8) bool {
    var file = std.Io.Dir.cwd().openFile(io, path, .{}) catch return false;
    file.close(io);
    return true;
}

test "isGitWorkTree is false for missing and non-git paths" {
    const testing = std.testing;
    try testing.expect(!isGitWorkTree(testing.io, ""));
    try testing.expect(!isGitWorkTree(testing.io, ".zig-cache/tmp/faku-rewind-missing"));

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [256]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, ".zig-cache/tmp/{s}/plain", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(testing.io, path);
    try testing.expect(!isGitWorkTree(testing.io, path));
}

test "captureHead records rev-parse HEAD in a temp git repo" {
    const testing = std.testing;
    const allocator = testing.allocator;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [256]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, ".zig-cache/tmp/{s}/repo", .{tmp.sub_path[0..]});
    const expected = try initTestRepo(allocator, testing.io, path);
    defer allocator.free(expected);

    try testing.expect(isGitWorkTree(testing.io, path));
    var sha_buf: [max_sha]u8 = undefined;
    const captured = captureHead(allocator, testing.io, path, &sha_buf) orelse return error.MissingCapture;
    try testing.expectEqualStrings(expected, captured.sha);
    try testing.expect(captured.recorded_at > 0);
}

test "append keeps the last 20 refs" {
    const testing = std.testing;
    var refs: [max_refs]Ref = [_]Ref{.{}} ** max_refs;
    var count: usize = 0;
    var i: usize = 0;
    while (i < 25) : (i += 1) {
        var sha = [_]u8{ 'a', '0' + @as(u8, @intCast(i % 10)) };
        append(&refs, &count, &sha, recorded_ref, @intCast(i));
    }
    try testing.expectEqual(@as(usize, 20), count);
    try testing.expectEqual(@as(i64, 5), refs[0].recorded_at);
    try testing.expectEqual(@as(i64, 24), refs[19].recorded_at);
    try testing.expectEqualStrings(recorded_ref, refs[19].refName());
}

fn initTestRepo(allocator: std.mem.Allocator, io: std.Io, path: []const u8) ![]u8 {
    try std.Io.Dir.cwd().createDirPath(io, path);
    try runGit(allocator, io, &.{ "git", "-C", path, "init" });
    var readme_buf: [std.fs.max_path_bytes]u8 = undefined;
    const readme = try std.fmt.bufPrint(&readme_buf, "{s}{s}README", .{ path, std.fs.path.sep_str });
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = readme, .data = "rewind\n" });
    try runGit(allocator, io, &.{ "git", "-C", path, "add", "README" });
    try runGit(allocator, io, &.{
        "git",
        "-C",
        path,
        "-c",
        "user.email=rewind@test",
        "-c",
        "user.name=Rewind",
        "-c",
        "commit.gpgsign=false",
        "commit",
        "-m",
        "init",
    });
    var sha_buf: [max_sha]u8 = undefined;
    const sha = revParseHead(allocator, io, path, &sha_buf) orelse return error.GitHead;
    return allocator.dupe(u8, sha);
}

fn runGit(allocator: std.mem.Allocator, io: std.Io, argv: []const []const u8) !void {
    const result = try std.process.run(allocator, io, .{
        .argv = argv,
        .stdout_limit = .limited(1024),
        .stderr_limit = .limited(4096),
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    if (result.term != .exited or result.term.exited != 0) return error.GitFailed;
}
