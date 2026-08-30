//! First-cut Waku-style worktree snapshot (isolated temp index).
//!
//! `captureWorktreeCommit` writes a dangling commit of the live
//! worktree plus untracked files. `GIT_INDEX_FILE` is a
//! `faku-checkpoint-index-*` under the repo `git-common-dir` so
//! the user's index is never staged or unstaged. Identity is
//! `-c user.name=Faku` `-c user.email=faku@localhost`. Message is
//! `Faku worktree snapshot`. No `-p` (empty parents). Always
//! deletes the temp index and `.lock`. Sync `std.process.run`
//! like `rewind.captureHead` — not a Native spawn and not
//! `/bin/sh -c` interpolation. Leftovers: `refs/waku/` /
//! `refs/faku/` update-ref, `capture_turn_start`, turn-end
//! capture, `restore_ref`, force, background work, daemon
//! WorkspaceOperation.

const std = @import("std");
const rewind = @import("rewind.zig");

pub const env_bin = "/usr/bin/env";
pub const git_bin = "git";
pub const index_prefix = "faku-checkpoint-index-";
pub const snapshot_message = "Faku worktree snapshot";
pub const identity_name = "user.name=Faku";
pub const identity_email = "user.email=faku@localhost";
pub const commit_gpgsign = "commit.gpgsign=false";

const env_prefix = "GIT_INDEX_FILE=";
const index_nonce_len: usize = 16;

/// Isolated-index worktree snapshot. Returns a 40-hex sha or null.
/// Missing / non-git / failed plumbing is quiet.
pub fn captureWorktreeCommit(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    dest: []u8,
) ?[]const u8 {
    if (!rewind.isGitWorkTree(io, project_path)) return null;

    var common_buf: [std.fs.max_path_bytes]u8 = undefined;
    const common = gitCommonDir(allocator, io, project_path, &common_buf) orelse return null;

    var index_buf: [std.fs.max_path_bytes]u8 = undefined;
    const index_path = uniqueIndexPath(common, &index_buf) orelse return null;

    var env_buf: [std.fs.max_path_bytes + env_prefix.len]u8 = undefined;
    const env_slot = std.fmt.bufPrint(&env_buf, "{s}{s}", .{ env_prefix, index_path }) catch return null;

    const captured = captureFromIndex(allocator, io, project_path, env_slot, dest);
    deleteIndex(io, index_path);
    return captured;
}

fn captureFromIndex(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    env_slot: []const u8,
    dest: []u8,
) ?[]const u8 {
    var head_buf: [rewind.max_sha]u8 = undefined;
    if (rewind.revParseHead(allocator, io, project_path, &head_buf) != null) {
        if (!runGit(allocator, io, env_slot, project_path, &.{ "read-tree", "HEAD" }, null)) return null;
    }
    if (!runGit(allocator, io, env_slot, project_path, &.{ "add", "-A", "--", "." }, null)) return null;

    var tree_buf: [rewind.stored_sha_len]u8 = undefined;
    const tree = runGitOut(allocator, io, env_slot, project_path, &.{"write-tree"}, &tree_buf) orelse return null;

    var commit_buf: [rewind.stored_sha_len]u8 = undefined;
    const commit = runGitOut(allocator, io, env_slot, project_path, &.{
        "-c",
        identity_name,
        "-c",
        identity_email,
        "-c",
        commit_gpgsign,
        "commit-tree",
        tree,
        "-m",
        snapshot_message,
    }, &commit_buf) orelse return null;
    if (!rewind.isStoredSha(commit)) return null;
    if (commit.len > dest.len) return null;
    @memcpy(dest[0..commit.len], commit);
    return dest[0..commit.len];
}

fn gitCommonDir(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    dest: []u8,
) ?[]const u8 {
    const result = std.process.run(allocator, io, .{
        .argv = &.{ git_bin, "-C", project_path, "rev-parse", "--git-common-dir" },
        .stdout_limit = .limited(512),
        .stderr_limit = .limited(256),
    }) catch return null;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    if (result.term != .exited or result.term.exited != 0) return null;
    const printed = std.mem.trim(u8, result.stdout, " \r\n\t");
    if (printed.len == 0) return null;
    if (printed[0] == '/') {
        if (printed.len > dest.len) return null;
        @memcpy(dest[0..printed.len], printed);
        return dest[0..printed.len];
    }
    const joined = std.fmt.bufPrint(dest, "{s}{s}{s}", .{
        project_path,
        std.fs.path.sep_str,
        printed,
    }) catch return null;
    return joined;
}

fn uniqueIndexPath(common_dir: []const u8, dest: []u8) ?[]const u8 {
    var nonce: [index_nonce_len / 2]u8 = undefined;
    std.crypto.random.bytes(&nonce);
    const hex = std.fmt.bytesToHex(nonce, .lower);
    return std.fmt.bufPrint(dest, "{s}{s}{s}{s}", .{
        common_dir,
        std.fs.path.sep_str,
        index_prefix,
        hex[0..],
    }) catch null;
}

fn runGit(
    allocator: std.mem.Allocator,
    io: std.Io,
    env_slot: []const u8,
    project_path: []const u8,
    git_args: []const []const u8,
    dest: ?[]u8,
) bool {
    return runGitOut(allocator, io, env_slot, project_path, git_args, dest orelse &.{}) != null;
}

fn runGitOut(
    allocator: std.mem.Allocator,
    io: std.Io,
    env_slot: []const u8,
    project_path: []const u8,
    git_args: []const []const u8,
    dest: []u8,
) ?[]const u8 {
    var argv_buf: [24][]const u8 = undefined;
    var n: usize = 0;
    argv_buf[n] = env_bin;
    n += 1;
    argv_buf[n] = env_slot;
    n += 1;
    argv_buf[n] = git_bin;
    n += 1;
    argv_buf[n] = "-C";
    n += 1;
    argv_buf[n] = project_path;
    n += 1;
    for (git_args) |arg| {
        if (n >= argv_buf.len) return null;
        argv_buf[n] = arg;
        n += 1;
    }
    const result = std.process.run(allocator, io, .{
        .argv = argv_buf[0..n],
        .stdout_limit = .limited(128),
        .stderr_limit = .limited(512),
    }) catch return null;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    if (result.term != .exited or result.term.exited != 0) return null;
    if (dest.len == 0) return "";
    const trimmed = std.mem.trim(u8, result.stdout, " \r\n\t");
    if (trimmed.len == 0 or trimmed.len > dest.len) return null;
    @memcpy(dest[0..trimmed.len], trimmed);
    return dest[0..trimmed.len];
}

fn deleteIndex(io: std.Io, index_path: []const u8) void {
    deleteQuiet(io, index_path);
    var lock_buf: [std.fs.max_path_bytes]u8 = undefined;
    const lock = std.fmt.bufPrint(&lock_buf, "{s}.lock", .{index_path}) catch return;
    deleteQuiet(io, lock);
}

fn deleteQuiet(io: std.Io, path: []const u8) void {
    std.Io.Dir.cwd().deleteFile(io, path) catch {};
}

test "captureWorktreeCommit includes dirty and untracked and leaves the user index alone" {
    const testing = std.testing;
    const allocator = testing.allocator;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [256]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, ".zig-cache/tmp/{s}/snap", .{tmp.sub_path[0..]});
    const head = try initTestRepo(allocator, testing.io, path);
    defer allocator.free(head);

    try writeRepoFile(testing.io, path, "README", "dirty\n");
    try writeRepoFile(testing.io, path, "untracked.txt", "new\n");
    try writeRepoFile(testing.io, path, "staged.txt", "staged\n");
    try runGitPlain(allocator, testing.io, &.{ "git", "-C", path, "add", "staged.txt" });

    const before = try porcelain(allocator, testing.io, path);
    defer allocator.free(before);
    try testing.expect(std.mem.indexOf(u8, before, "staged.txt") != null);
    try testing.expect(std.mem.indexOf(u8, before, "untracked.txt") != null);

    var sha_buf: [rewind.stored_sha_len]u8 = undefined;
    const snap = captureWorktreeCommit(allocator, testing.io, path, &sha_buf) orelse return error.MissingSnapshot;
    try testing.expect(rewind.isStoredSha(snap));
    try testing.expect(!std.mem.eql(u8, head, snap));

    const after = try porcelain(allocator, testing.io, path);
    defer allocator.free(after);
    try testing.expectEqualStrings(before, after);

    const cached = try runGitCapture(allocator, testing.io, &.{ "git", "-C", path, "diff", "--cached", "--name-only" });
    defer allocator.free(cached);
    try testing.expect(std.mem.indexOf(u8, cached, "staged.txt") != null);

    const vs_head = try runGitCapture(allocator, testing.io, &.{ "git", "-C", path, "diff", "--name-status", head, snap });
    defer allocator.free(vs_head);
    try testing.expect(std.mem.indexOf(u8, vs_head, "README") != null);
    try testing.expect(std.mem.indexOf(u8, vs_head, "untracked.txt") != null);
    try testing.expect(std.mem.indexOf(u8, vs_head, "staged.txt") != null);

    const vs_worktree = try runGitCapture(allocator, testing.io, &.{ "git", "-C", path, "diff", "--name-status", snap });
    defer allocator.free(vs_worktree);
    try testing.expectEqual(@as(usize, 0), std.mem.trim(u8, vs_worktree, " \r\n\t").len);

    const parents = try runGitCapture(allocator, testing.io, &.{
        "git",
        "-C",
        path,
        "rev-list",
        "--parents",
        "-n",
        "1",
        snap,
    });
    defer allocator.free(parents);
    try testing.expectEqualStrings(snap, std.mem.trim(u8, parents, " \r\n\t"));

    try testing.expect(!leftoverIndex(testing.io, path));
}

test "captureWorktreeCommit is null for missing and non-git paths" {
    const testing = std.testing;
    var sha_buf: [rewind.stored_sha_len]u8 = undefined;
    try testing.expect(captureWorktreeCommit(testing.allocator, testing.io, "", &sha_buf) == null);
    try testing.expect(captureWorktreeCommit(testing.allocator, testing.io, ".zig-cache/tmp/faku-checkpoint-missing", &sha_buf) == null);

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [256]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, ".zig-cache/tmp/{s}/plain", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(testing.io, path);
    try testing.expect(captureWorktreeCommit(testing.allocator, testing.io, path, &sha_buf) == null);
}

fn leftoverIndex(io: std.Io, project_path: []const u8) bool {
    var git_buf: [std.fs.max_path_bytes]u8 = undefined;
    const git_path = std.fmt.bufPrint(&git_buf, "{s}{s}.git", .{ project_path, std.fs.path.sep_str }) catch return true;
    var dir = std.fs.cwd().openDir(git_path, .{ .iterate = true }) catch return false;
    defer dir.close();
    var it = dir.iterate();
    while (it.next() catch return true) |entry| {
        if (std.mem.startsWith(u8, entry.name, index_prefix)) return true;
        if (std.mem.startsWith(u8, entry.name, "waku-checkpoint-index-")) return true;
    }
    return false;
}

fn initTestRepo(allocator: std.mem.Allocator, io: std.Io, path: []const u8) ![]u8 {
    try std.Io.Dir.cwd().createDirPath(io, path);
    try runGitPlain(allocator, io, &.{ "git", "-C", path, "init" });
    try writeRepoFile(io, path, "README", "rewind\n");
    try runGitPlain(allocator, io, &.{ "git", "-C", path, "add", "README" });
    try runGitPlain(allocator, io, &.{
        "git",
        "-C",
        path,
        "-c",
        "user.email=checkpoint@test",
        "-c",
        "user.name=Checkpoint",
        "-c",
        commit_gpgsign,
        "commit",
        "-m",
        "init",
    });
    var sha_buf: [rewind.max_sha]u8 = undefined;
    const sha = rewind.revParseHead(allocator, io, path, &sha_buf) orelse return error.GitHead;
    return allocator.dupe(u8, sha);
}

fn writeRepoFile(io: std.Io, path: []const u8, name: []const u8, contents: []const u8) !void {
    var file_buf: [std.fs.max_path_bytes]u8 = undefined;
    const file_path = try std.fmt.bufPrint(&file_buf, "{s}{s}{s}", .{ path, std.fs.path.sep_str, name });
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = file_path, .data = contents });
}

fn porcelain(allocator: std.mem.Allocator, io: std.Io, path: []const u8) ![]u8 {
    return runGitCapture(allocator, io, &.{ "git", "-C", path, "status", "--porcelain" });
}

fn runGitPlain(allocator: std.mem.Allocator, io: std.Io, argv: []const []const u8) !void {
    const result = try std.process.run(allocator, io, .{
        .argv = argv,
        .stdout_limit = .limited(1024),
        .stderr_limit = .limited(4096),
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    if (result.term != .exited or result.term.exited != 0) return error.GitFailed;
}

fn runGitCapture(allocator: std.mem.Allocator, io: std.Io, argv: []const []const u8) ![]u8 {
    const result = try std.process.run(allocator, io, .{
        .argv = argv,
        .stdout_limit = .limited(4096),
        .stderr_limit = .limited(4096),
    });
    defer allocator.free(result.stderr);
    if (result.term != .exited or result.term.exited != 0) {
        allocator.free(result.stdout);
        return error.GitFailed;
    }
    return result.stdout;
}
