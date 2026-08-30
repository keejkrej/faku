//! Workspace HEAD snapshots and conversation-aware rewind.
//!
//! At Send / spawn (turn start), Faku stores `{ sha, ref: "HEAD", recorded_at }`
//! on the session when `project_path` is a git work tree. That Send-time sha is
//! the no-snapshot Rewind fallback — not a post-turn HEAD, and not a
//! provider session fork.
//! After-success capture is omitted: a later snapshot would become
//! `latestStoredSha` and restore the post-turn tree instead of undoing it.
//! The next Send records the then-current HEAD as its own checkpoint.
//!
//! Header Rewind prefers `checkpoint.restoreRef` on the stored
//! worktree snapshot when set. This module's `resetHard` is the
//! no-snapshot fallback: `git reset --hard` the latest stored
//! 40-char hex sha. The caller pops that entry so a second
//! Rewind walks the previous checkpoint, and drops the last
//! prompt's transcript turns after a successful restore.
//! Missing / non-git / unknown sha is a no-op. No extra git refs, no invented
//! shas. Native has no git API — one-shot `git -C` only.

const std = @import("std");

pub const max_refs: usize = 20;
pub const max_sha: usize = 64;
pub const stored_sha_len: usize = 40;
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

pub fn isStoredSha(sha: []const u8) bool {
    if (sha.len != stored_sha_len) return false;
    for (sha) |c| {
        const digit = c >= '0' and c <= '9';
        const lower = c >= 'a' and c <= 'f';
        const upper = c >= 'A' and c <= 'F';
        if (!digit and !lower and !upper) return false;
    }
    return true;
}

/// Latest recorded 40-char hex sha. Skips entries that are not stored shas.
/// Rewind uses this value — the Send-time HEAD of the last prompted turn.
pub fn latestStoredSha(refs: []const Ref) ?[]const u8 {
    var i = refs.len;
    while (i > 0) {
        i -= 1;
        if (isStoredSha(refs[i].sha())) return refs[i].sha();
    }
    return null;
}

/// Consume the latest stored 40-char sha (and any trailing non-sha entries
/// after it) so the next Rewind walks the previous checkpoint.
pub fn popLatestStored(dest: *[max_refs]Ref, count: *usize) void {
    var i = count.*;
    while (i > 0) {
        i -= 1;
        if (isStoredSha(dest[i].sha())) {
            count.* = i;
            return;
        }
    }
}

/// One-shot `git -C <path> reset --hard <sha>`. No Native git API.
/// Missing / non-git / unknown sha is a no-op.
pub fn resetHard(allocator: std.mem.Allocator, io: std.Io, project_path: []const u8, sha: []const u8) bool {
    if (!isStoredSha(sha)) return false;
    if (!isGitWorkTree(io, project_path)) return false;
    const result = std.process.run(allocator, io, .{
        .argv = &.{ "git", "-C", project_path, "reset", "--hard", sha },
        .stdout_limit = .limited(256),
        .stderr_limit = .limited(512),
    }) catch return false;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    return result.term == .exited and result.term.exited == 0;
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

test "isStoredSha accepts only 40-char hex" {
    const testing = std.testing;
    try testing.expect(isStoredSha("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"));
    try testing.expect(isStoredSha("0123456789ABCDEFabcdef0123456789ABCDEF01"));
    try testing.expect(!isStoredSha(""));
    try testing.expect(!isStoredSha("abc"));
    try testing.expect(!isStoredSha("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"));
    try testing.expect(!isStoredSha("gggggggggggggggggggggggggggggggggggggggg"));
}

test "latestStoredSha prefers the last 40-char hex" {
    const testing = std.testing;
    var refs: [max_refs]Ref = [_]Ref{.{}} ** max_refs;
    var count: usize = 0;
    append(&refs, &count, "short", recorded_ref, 1);
    append(&refs, &count, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", recorded_ref, 2);
    append(&refs, &count, "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", recorded_ref, 3);
    append(&refs, &count, "not-a-sha", recorded_ref, 4);
    try testing.expectEqualStrings("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", latestStoredSha(refs[0..count]).?);
}

test "popLatestStored consumes the latest stored sha" {
    const testing = std.testing;
    var refs: [max_refs]Ref = [_]Ref{.{}} ** max_refs;
    var count: usize = 0;
    append(&refs, &count, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", recorded_ref, 1);
    append(&refs, &count, "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", recorded_ref, 2);
    append(&refs, &count, "not-a-sha", recorded_ref, 3);
    popLatestStored(&refs, &count);
    try testing.expectEqual(@as(usize, 1), count);
    try testing.expectEqualStrings("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", latestStoredSha(refs[0..count]).?);
    popLatestStored(&refs, &count);
    try testing.expectEqual(@as(usize, 0), count);
    try testing.expect(latestStoredSha(refs[0..count]) == null);
    popLatestStored(&refs, &count);
    try testing.expectEqual(@as(usize, 0), count);
}

test "resetHard restores a recorded sha after dirty and advanced HEAD" {
    const testing = std.testing;
    const allocator = testing.allocator;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [256]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, ".zig-cache/tmp/{s}/reset", .{tmp.sub_path[0..]});
    const expected = try initTestRepo(allocator, testing.io, path);
    defer allocator.free(expected);

    try dirtyAndAdvance(allocator, testing.io, path, "advance\n");
    var after_buf: [max_sha]u8 = undefined;
    const after = revParseHead(allocator, testing.io, path, &after_buf) orelse return error.GitHead;
    try testing.expect(!std.mem.eql(u8, expected, after));

    try testing.expect(resetHard(allocator, testing.io, path, expected));
    var restored_buf: [max_sha]u8 = undefined;
    const restored = revParseHead(allocator, testing.io, path, &restored_buf) orelse return error.GitHead;
    try testing.expectEqualStrings(expected, restored);
    const readme_bytes = try readReadme(allocator, testing.io, path);
    defer allocator.free(readme_bytes);
    try testing.expectEqualStrings("rewind\n", readme_bytes);
}

test "resetHard is a no-op for missing path, non-git, and unknown sha" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const unknown = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    try testing.expect(!resetHard(allocator, testing.io, "", unknown));
    try testing.expect(!resetHard(allocator, testing.io, ".zig-cache/tmp/faku-rewind-missing", unknown));

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var plain_buf: [256]u8 = undefined;
    const plain = try std.fmt.bufPrint(&plain_buf, ".zig-cache/tmp/{s}/plain", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(testing.io, plain);
    try testing.expect(!resetHard(allocator, testing.io, plain, unknown));

    var repo_buf: [256]u8 = undefined;
    const repo = try std.fmt.bufPrint(&repo_buf, ".zig-cache/tmp/{s}/unknown", .{tmp.sub_path[0..]});
    const expected = try initTestRepo(allocator, testing.io, repo);
    defer allocator.free(expected);
    try testing.expect(!resetHard(allocator, testing.io, repo, unknown));
    var still_buf: [max_sha]u8 = undefined;
    const still = revParseHead(allocator, testing.io, repo, &still_buf) orelse return error.GitHead;
    try testing.expectEqualStrings(expected, still);
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

fn dirtyAndAdvance(allocator: std.mem.Allocator, io: std.Io, path: []const u8, contents: []const u8) !void {
    var readme_buf: [std.fs.max_path_bytes]u8 = undefined;
    const readme = try std.fmt.bufPrint(&readme_buf, "{s}{s}README", .{ path, std.fs.path.sep_str });
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = readme, .data = "dirty\n" });
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = readme, .data = contents });
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
        "advance",
    });
}

fn readReadme(allocator: std.mem.Allocator, io: std.Io, path: []const u8) ![]u8 {
    var readme_buf: [std.fs.max_path_bytes]u8 = undefined;
    const readme = try std.fmt.bufPrint(&readme_buf, "{s}{s}README", .{ path, std.fs.path.sep_str });
    return std.Io.Dir.cwd().readFileAlloc(io, readme, allocator, .limited(64));
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
