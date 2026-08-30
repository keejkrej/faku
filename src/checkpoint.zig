//! First-cut Waku-style worktree snapshot (isolated temp index).
//!
//! `captureWorktreeCommit` writes a dangling commit of the live
//! worktree plus untracked files. `GIT_INDEX_FILE` is a
//! `faku-checkpoint-index-*` under the repo `git-common-dir` so
//! the user's index is never staged or unstaged. Identity is
//! `-c user.name=Faku` `-c user.email=faku@localhost`. Message is
//! `Faku worktree snapshot`. No `-p` (empty parents). Always
//! deletes the temp index and `.lock`. After a successful
//! capture, Send names that commit with one-shot
//! `git update-ref refs/faku/session-{Session.id}-turn-start-{n}`
//! (`captureTurnStart` / `updateFakuRef`). `{n}` is the 1-based
//! prompt ordinal of this Send: `Model.turnCount / 2 + 1` at
//! record time, before the user+assistant pair is appended
//! (first Send is `turn-start-1`). If
//! `refs/faku/session-{id}-turn-{n-1}` is missing, the same
//! commit is also named as that baseline. LastTurn / Review
//! still use the stored 40-hex (`worktree_snapshot_sha`), not
//! the ref. Failed update-ref is quiet and does not clear the
//! stored sha. Header Rewind restores that stored 40-hex with
//! `restoreRef` (`git restore --source <sha> --worktree --staged
//! -- .`, `git clean -fd -- .`, then `git reset --quiet -- .`
//! when HEAD exists). Sync `std.process.run` like
//! `rewind.captureHead` — not a Native spawn and not `/bin/sh
//! -c` interpolation. Leftovers: turn-end capture (`turn-{n}`
//! at finish), parents/metadata in the commit message, force,
//! background work, daemon WorkspaceOperation.

const std = @import("std");
const rewind = @import("rewind.zig");

pub const env_bin = "/usr/bin/env";
pub const git_bin = "git";
pub const index_prefix = "faku-checkpoint-index-";
pub const snapshot_message = "Faku worktree snapshot";
pub const identity_name = "user.name=Faku";
pub const identity_email = "user.email=faku@localhost";
pub const commit_gpgsign = "commit.gpgsign=false";
pub const faku_ref_prefix = "refs/faku/";
pub const max_faku_ref_name: usize = 128;

const env_prefix = "GIT_INDEX_FILE=";

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
    const index_path = uniqueIndexPath(io, common, &index_buf) orelse return null;

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

/// 1-based prompt ordinal for `refs/faku/session-*-turn-*`.
/// `transcript_turns` is `Model.turnCount` at Send record time
/// (before this Send appends the user+assistant pair).
pub fn fakuSendTurn(transcript_turns: u32) u32 {
    return transcript_turns / 2 + 1;
}

/// `refs/faku/session-{session_id}-turn-{turn_count}` into `dest`.
/// Null when the name would not fit `dest` or `max_faku_ref_name`.
pub fn formatFakuSessionTurnRef(dest: []u8, session_id: u32, turn_count: u32) ?[]const u8 {
    const printed = std.fmt.bufPrint(dest, "refs/faku/session-{d}-turn-{d}", .{ session_id, turn_count }) catch return null;
    if (printed.len == 0 or printed.len > max_faku_ref_name) return null;
    return printed;
}

/// `refs/faku/session-{session_id}-turn-start-{turn_count}` into
/// `dest`. Same fit / `isFakuRefName` rules as the turn-end
/// name (`-` is already allowed). Null when the name would not
/// fit `dest` or `max_faku_ref_name`.
pub fn formatFakuSessionTurnStartRef(dest: []u8, session_id: u32, turn_count: u32) ?[]const u8 {
    const printed = std.fmt.bufPrint(dest, "refs/faku/session-{d}-turn-start-{d}", .{ session_id, turn_count }) catch return null;
    if (printed.len == 0 or printed.len > max_faku_ref_name) return null;
    return printed;
}

pub fn isFakuRefName(ref_name: []const u8) bool {
    if (ref_name.len == 0 or ref_name.len > max_faku_ref_name) return false;
    if (!std.mem.startsWith(u8, ref_name, faku_ref_prefix)) return false;
    const rest = ref_name[faku_ref_prefix.len..];
    if (rest.len == 0) return false;
    for (rest) |c| {
        const letter = c >= 'a' and c <= 'z';
        const digit = c >= '0' and c <= '9';
        if (!letter and !digit and c != '-' and c != '_') return false;
    }
    return true;
}

/// One-shot `git -C <path> update-ref <ref> <40-hex>`. No Native
/// git API and not `/bin/sh -c`. Missing / non-git / bad sha /
/// bad ref / failed update-ref is quiet false.
pub fn updateFakuRef(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    ref_name: []const u8,
    sha: []const u8,
) bool {
    if (!rewind.isStoredSha(sha)) return false;
    if (!isFakuRefName(ref_name)) return false;
    if (!rewind.isGitWorkTree(io, project_path)) return false;
    const result = std.process.run(allocator, io, .{
        .argv = &.{ git_bin, "-C", project_path, "update-ref", ref_name, sha },
        .stdout_limit = .limited(256),
        .stderr_limit = .limited(512),
    }) catch return false;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    return result.term == .exited and result.term.exited == 0;
}

/// Quiet bool: one-shot `git -C <path> show-ref --verify --quiet
/// <ref>`. Missing / non-git / bad ref is false. No `/bin/sh -c`.
pub fn hasFakuRef(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    ref_name: []const u8,
) bool {
    if (!isFakuRefName(ref_name)) return false;
    if (!rewind.isGitWorkTree(io, project_path)) return false;
    const result = std.process.run(allocator, io, .{
        .argv = &.{ git_bin, "-C", project_path, "show-ref", "--verify", "--quiet", ref_name },
        .stdout_limit = .limited(256),
        .stderr_limit = .limited(512),
    }) catch return false;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    return result.term == .exited and result.term.exited == 0;
}

/// Name the stored 40-hex as `turn-start-{n}`. If
/// `turn-{n-1}` (or `turn-0` when `n` is 0) is missing, also
/// name that baseline with the same sha. Does not write
/// `turn-{n}` (that is turn-end leftover). Quiet false only
/// when the turn-start update fails; a failed baseline seed
/// is still true.
pub fn captureTurnStart(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    session_id: u32,
    turn_count: u32,
    sha: []const u8,
) bool {
    if (!rewind.isStoredSha(sha)) return false;
    var start_buf: [max_faku_ref_name]u8 = undefined;
    const start_ref = formatFakuSessionTurnStartRef(&start_buf, session_id, turn_count) orelse return false;
    if (!updateFakuRef(allocator, io, project_path, start_ref, sha)) return false;

    const baseline_n: u32 = if (turn_count >= 1) turn_count - 1 else 0;
    var baseline_buf: [max_faku_ref_name]u8 = undefined;
    if (formatFakuSessionTurnRef(&baseline_buf, session_id, baseline_n)) |baseline_ref| {
        if (!hasFakuRef(allocator, io, project_path, baseline_ref)) {
            _ = updateFakuRef(allocator, io, project_path, baseline_ref, sha);
        }
    }
    return true;
}

/// Restore the worktree from a stored 40-hex snapshot commit.
/// Documented sequence: `git restore --source <sha> --worktree
/// --staged -- .`, then `git clean -fd -- .`, then `git reset
/// --quiet -- .` when HEAD exists. Does not move HEAD. Input is
/// the stored sha, not `refs/faku/`. Missing / non-git / bad
/// sha / failed git is quiet false.
pub fn restoreRef(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    sha: []const u8,
) bool {
    if (!rewind.isStoredSha(sha)) return false;
    if (!rewind.isGitWorkTree(io, project_path)) return false;
    if (!runGitC(allocator, io, project_path, &.{
        "restore",
        "--source",
        sha,
        "--worktree",
        "--staged",
        "--",
        ".",
    })) return false;
    if (!runGitC(allocator, io, project_path, &.{ "clean", "-fd", "--", "." })) return false;
    var head_buf: [rewind.max_sha]u8 = undefined;
    if (rewind.revParseHead(allocator, io, project_path, &head_buf) != null) {
        if (!runGitC(allocator, io, project_path, &.{ "reset", "--quiet", "--", "." })) return false;
    }
    return true;
}

fn runGitC(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    git_args: []const []const u8,
) bool {
    var argv_buf: [16][]const u8 = undefined;
    var n: usize = 0;
    argv_buf[n] = git_bin;
    n += 1;
    argv_buf[n] = "-C";
    n += 1;
    argv_buf[n] = project_path;
    n += 1;
    for (git_args) |arg| {
        if (n >= argv_buf.len) return false;
        argv_buf[n] = arg;
        n += 1;
    }
    const result = std.process.run(allocator, io, .{
        .argv = argv_buf[0..n],
        .stdout_limit = .limited(4096),
        .stderr_limit = .limited(512),
    }) catch return false;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    return result.term == .exited and result.term.exited == 0;
}

fn gitCommonDir(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    dest: []u8,
) ?[]const u8 {
    const printed = revParseCommonDir(allocator, io, project_path, true) orelse
        revParseCommonDir(allocator, io, project_path, false) orelse return null;
    defer allocator.free(printed);
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
    if (joined[0] == '/') return joined;
    return realpathInto(allocator, io, joined, dest);
}

fn revParseCommonDir(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    absolute: bool,
) ?[]u8 {
    const result = if (absolute)
        std.process.run(allocator, io, .{
            .argv = &.{ git_bin, "-C", project_path, "rev-parse", "--path-format=absolute", "--git-common-dir" },
            .stdout_limit = .limited(512),
            .stderr_limit = .limited(256),
        })
    else
        std.process.run(allocator, io, .{
            .argv = &.{ git_bin, "-C", project_path, "rev-parse", "--git-common-dir" },
            .stdout_limit = .limited(512),
            .stderr_limit = .limited(256),
        });
    const ran = result catch return null;
    defer allocator.free(ran.stderr);
    if (ran.term != .exited or ran.term.exited != 0) {
        allocator.free(ran.stdout);
        return null;
    }
    const trimmed = std.mem.trim(u8, ran.stdout, " \r\n\t");
    if (trimmed.len == 0) {
        allocator.free(ran.stdout);
        return null;
    }
    const out = allocator.dupe(u8, trimmed) catch {
        allocator.free(ran.stdout);
        return null;
    };
    allocator.free(ran.stdout);
    return out;
}

fn realpathInto(
    allocator: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
    dest: []u8,
) ?[]const u8 {
    const result = std.process.run(allocator, io, .{
        .argv = &.{ "realpath", "--", path },
        .stdout_limit = .limited(512),
        .stderr_limit = .limited(256),
    }) catch return null;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    if (result.term != .exited or result.term.exited != 0) return null;
    const trimmed = std.mem.trim(u8, result.stdout, " \r\n\t");
    if (trimmed.len == 0 or trimmed[0] != '/' or trimmed.len > dest.len) return null;
    @memcpy(dest[0..trimmed.len], trimmed);
    return dest[0..trimmed.len];
}

var index_seq: u32 = 0;

fn uniqueIndexPath(io: std.Io, common_dir: []const u8, dest: []u8) ?[]const u8 {
    index_seq +%= 1;
    const stamp: u64 = @bitCast(std.Io.Clock.real.now(io).toSeconds());
    return std.fmt.bufPrint(dest, "{s}{s}{s}{x:0>8}{x:0>8}", .{
        common_dir,
        std.fs.path.sep_str,
        index_prefix,
        @as(u32, @truncate(stamp)),
        index_seq,
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

    const tree = try runGitCapture(allocator, testing.io, &.{ "git", "-C", path, "ls-tree", "-r", "--name-only", snap });
    defer allocator.free(tree);
    try testing.expect(std.mem.indexOf(u8, tree, "README") != null);
    try testing.expect(std.mem.indexOf(u8, tree, "untracked.txt") != null);
    try testing.expect(std.mem.indexOf(u8, tree, "staged.txt") != null);

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

    try testing.expect(!leftoverIndex(allocator, testing.io, path));
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

test "formatFakuSessionTurnRef uses session id and prompt ordinal" {
    const testing = std.testing;
    var buf: [max_faku_ref_name]u8 = undefined;
    const name = formatFakuSessionTurnRef(&buf, 7, 3) orelse return error.MissingFakuRef;
    try testing.expectEqualStrings("refs/faku/session-7-turn-3", name);
    try testing.expect(isFakuRefName(name));
    try testing.expectEqual(@as(u32, 1), fakuSendTurn(0));
    try testing.expectEqual(@as(u32, 1), fakuSendTurn(1));
    try testing.expectEqual(@as(u32, 2), fakuSendTurn(2));
    try testing.expectEqual(@as(u32, 2), fakuSendTurn(3));
    try testing.expectEqual(@as(u32, 3), fakuSendTurn(4));
    var tiny: [8]u8 = undefined;
    try testing.expect(formatFakuSessionTurnRef(&tiny, 1, 1) == null);
    try testing.expect(!isFakuRefName(""));
    try testing.expect(!isFakuRefName("refs/heads/main"));
    try testing.expect(!isFakuRefName("refs/faku/"));
    try testing.expect(!isFakuRefName("refs/faku/../heads/main"));
}

test "formatFakuSessionTurnStartRef uses session id and prompt ordinal" {
    const testing = std.testing;
    var buf: [max_faku_ref_name]u8 = undefined;
    const name = formatFakuSessionTurnStartRef(&buf, 7, 3) orelse return error.MissingFakuRef;
    try testing.expectEqualStrings("refs/faku/session-7-turn-start-3", name);
    try testing.expect(isFakuRefName(name));
    var tiny: [8]u8 = undefined;
    try testing.expect(formatFakuSessionTurnStartRef(&tiny, 1, 1) == null);
}

test "captureWorktreeCommit plus updateFakuRef names the dangling commit" {
    const testing = std.testing;
    const allocator = testing.allocator;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [256]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, ".zig-cache/tmp/{s}/faku-ref", .{tmp.sub_path[0..]});
    const head = try initTestRepo(allocator, testing.io, path);
    defer allocator.free(head);

    var sha_buf: [rewind.stored_sha_len]u8 = undefined;
    const snap = captureWorktreeCommit(allocator, testing.io, path, &sha_buf) orelse return error.MissingSnapshot;
    var ref_buf: [max_faku_ref_name]u8 = undefined;
    const ref_name = formatFakuSessionTurnRef(&ref_buf, 12, 4) orelse return error.MissingFakuRef;
    try testing.expect(updateFakuRef(allocator, testing.io, path, ref_name, snap));

    const parsed = try runGitCapture(allocator, testing.io, &.{ "git", "-C", path, "rev-parse", ref_name });
    defer allocator.free(parsed);
    try testing.expectEqualStrings(snap, std.mem.trim(u8, parsed, " \r\n\t"));

    const reachable = try runGitCapture(allocator, testing.io, &.{
        "git",
        "-C",
        path,
        "rev-list",
        "--max-count=1",
        ref_name,
    });
    defer allocator.free(reachable);
    try testing.expectEqualStrings(snap, std.mem.trim(u8, reachable, " \r\n\t"));

    const kind = try runGitCapture(allocator, testing.io, &.{ "git", "-C", path, "cat-file", "-t", snap });
    defer allocator.free(kind);
    try testing.expectEqualStrings("commit", std.mem.trim(u8, kind, " \r\n\t"));
}

test "updateFakuRef is false and quiet on missing, non-git, and bad inputs" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const sha = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    try testing.expect(!updateFakuRef(allocator, testing.io, "", "refs/faku/session-1-turn-1", sha));
    try testing.expect(!updateFakuRef(allocator, testing.io, ".zig-cache/tmp/faku-ref-missing", "refs/faku/session-1-turn-1", sha));
    try testing.expect(!updateFakuRef(allocator, testing.io, ".", "refs/heads/main", sha));
    try testing.expect(!updateFakuRef(allocator, testing.io, ".", "refs/faku/session-1-turn-1", "not-a-sha"));
    try testing.expect(!updateFakuRef(allocator, testing.io, ".", "refs/faku/session-1-turn-1", ""));

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [256]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, ".zig-cache/tmp/{s}/plain", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(testing.io, path);
    try testing.expect(!updateFakuRef(allocator, testing.io, path, "refs/faku/session-1-turn-1", sha));
}

test "hasFakuRef is false for missing and true after update" {
    const testing = std.testing;
    const allocator = testing.allocator;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [256]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, ".zig-cache/tmp/{s}/has-ref", .{tmp.sub_path[0..]});
    const head = try initTestRepo(allocator, testing.io, path);
    defer allocator.free(head);

    var ref_buf: [max_faku_ref_name]u8 = undefined;
    const ref_name = formatFakuSessionTurnStartRef(&ref_buf, 3, 2) orelse return error.MissingFakuRef;
    try testing.expect(!hasFakuRef(allocator, testing.io, path, ref_name));
    try testing.expect(!hasFakuRef(allocator, testing.io, "", ref_name));
    try testing.expect(!hasFakuRef(allocator, testing.io, ".zig-cache/tmp/faku-has-ref-missing", ref_name));
    try testing.expect(!hasFakuRef(allocator, testing.io, path, "refs/heads/main"));
    try testing.expect(!hasFakuRef(allocator, testing.io, path, ""));

    var sha_buf: [rewind.stored_sha_len]u8 = undefined;
    const snap = captureWorktreeCommit(allocator, testing.io, path, &sha_buf) orelse return error.MissingSnapshot;
    try testing.expect(updateFakuRef(allocator, testing.io, path, ref_name, snap));
    try testing.expect(hasFakuRef(allocator, testing.io, path, ref_name));
}

test "captureTurnStart writes turn-start and seeds a missing baseline" {
    const testing = std.testing;
    const allocator = testing.allocator;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [256]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, ".zig-cache/tmp/{s}/turn-start", .{tmp.sub_path[0..]});
    const head = try initTestRepo(allocator, testing.io, path);
    defer allocator.free(head);

    var sha_buf: [rewind.stored_sha_len]u8 = undefined;
    const snap = captureWorktreeCommit(allocator, testing.io, path, &sha_buf) orelse return error.MissingSnapshot;
    try testing.expect(captureTurnStart(allocator, testing.io, path, 12, 4, snap));

    var start_buf: [max_faku_ref_name]u8 = undefined;
    const start_ref = formatFakuSessionTurnStartRef(&start_buf, 12, 4) orelse return error.MissingFakuRef;
    try testing.expect(hasFakuRef(allocator, testing.io, path, start_ref));
    const start_parsed = try runGitCapture(allocator, testing.io, &.{ "git", "-C", path, "rev-parse", start_ref });
    defer allocator.free(start_parsed);
    try testing.expectEqualStrings(snap, std.mem.trim(u8, start_parsed, " \r\n\t"));

    var baseline_buf: [max_faku_ref_name]u8 = undefined;
    const baseline = formatFakuSessionTurnRef(&baseline_buf, 12, 3) orelse return error.MissingFakuRef;
    try testing.expect(hasFakuRef(allocator, testing.io, path, baseline));
    const baseline_parsed = try runGitCapture(allocator, testing.io, &.{ "git", "-C", path, "rev-parse", baseline });
    defer allocator.free(baseline_parsed);
    try testing.expectEqualStrings(snap, std.mem.trim(u8, baseline_parsed, " \r\n\t"));

    var end_buf: [max_faku_ref_name]u8 = undefined;
    const end_ref = formatFakuSessionTurnRef(&end_buf, 12, 4) orelse return error.MissingFakuRef;
    try testing.expect(!hasFakuRef(allocator, testing.io, path, end_ref));

    try testing.expect(!captureTurnStart(allocator, testing.io, path, 12, 4, "not-a-sha"));
    try testing.expect(!captureTurnStart(allocator, testing.io, "", 12, 4, snap));
}

test "captureTurnStart does not overwrite an existing baseline" {
    const testing = std.testing;
    const allocator = testing.allocator;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [256]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, ".zig-cache/tmp/{s}/turn-start-keep", .{tmp.sub_path[0..]});
    const head = try initTestRepo(allocator, testing.io, path);
    defer allocator.free(head);

    var first_buf: [rewind.stored_sha_len]u8 = undefined;
    const first = captureWorktreeCommit(allocator, testing.io, path, &first_buf) orelse return error.MissingSnapshot;
    var baseline_buf: [max_faku_ref_name]u8 = undefined;
    const baseline = formatFakuSessionTurnRef(&baseline_buf, 9, 2) orelse return error.MissingFakuRef;
    try testing.expect(updateFakuRef(allocator, testing.io, path, baseline, first));

    try writeRepoFile(testing.io, path, "later.txt", "later\n");
    var second_buf: [rewind.stored_sha_len]u8 = undefined;
    const second = captureWorktreeCommit(allocator, testing.io, path, &second_buf) orelse return error.MissingSnapshot;
    try testing.expect(!std.mem.eql(u8, first, second));
    try testing.expect(captureTurnStart(allocator, testing.io, path, 9, 3, second));

    const baseline_parsed = try runGitCapture(allocator, testing.io, &.{ "git", "-C", path, "rev-parse", baseline });
    defer allocator.free(baseline_parsed);
    try testing.expectEqualStrings(first, std.mem.trim(u8, baseline_parsed, " \r\n\t"));

    var start_buf: [max_faku_ref_name]u8 = undefined;
    const start_ref = formatFakuSessionTurnStartRef(&start_buf, 9, 3) orelse return error.MissingFakuRef;
    const start_parsed = try runGitCapture(allocator, testing.io, &.{ "git", "-C", path, "rev-parse", start_ref });
    defer allocator.free(start_parsed);
    try testing.expectEqualStrings(second, std.mem.trim(u8, start_parsed, " \r\n\t"));

    var end_buf: [max_faku_ref_name]u8 = undefined;
    const end_ref = formatFakuSessionTurnRef(&end_buf, 9, 3) orelse return error.MissingFakuRef;
    try testing.expect(!hasFakuRef(allocator, testing.io, path, end_ref));
}

test "restoreRef restores dirty and untracked, cleans later files, and leaves HEAD and the user index" {
    const testing = std.testing;
    const allocator = testing.allocator;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [256]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, ".zig-cache/tmp/{s}/restore", .{tmp.sub_path[0..]});
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

    const after_capture = try porcelain(allocator, testing.io, path);
    defer allocator.free(after_capture);
    try testing.expectEqualStrings(before, after_capture);

    const cached_before = try runGitCapture(allocator, testing.io, &.{ "git", "-C", path, "diff", "--cached", "--name-only" });
    defer allocator.free(cached_before);
    try testing.expect(std.mem.indexOf(u8, cached_before, "staged.txt") != null);

    try writeRepoFile(testing.io, path, "README", "later\n");
    try writeRepoFile(testing.io, path, "untracked.txt", "changed\n");
    try writeRepoFile(testing.io, path, "after.txt", "post-snap\n");

    try testing.expect(restoreRef(allocator, testing.io, path, snap));

    var still_buf: [rewind.max_sha]u8 = undefined;
    const still = rewind.revParseHead(allocator, testing.io, path, &still_buf) orelse return error.GitHead;
    try testing.expectEqualStrings(head, still);

    const readme = try readRepoFile(allocator, testing.io, path, "README");
    defer allocator.free(readme);
    try testing.expectEqualStrings("dirty\n", readme);
    const untracked = try readRepoFile(allocator, testing.io, path, "untracked.txt");
    defer allocator.free(untracked);
    try testing.expectEqualStrings("new\n", untracked);
    const staged = try readRepoFile(allocator, testing.io, path, "staged.txt");
    defer allocator.free(staged);
    try testing.expectEqualStrings("staged\n", staged);
    try testing.expect(!repoFileExists(testing.io, path, "after.txt"));

    const cached_after = try runGitCapture(allocator, testing.io, &.{ "git", "-C", path, "diff", "--cached", "--name-only" });
    defer allocator.free(cached_after);
    try testing.expectEqualStrings("", std.mem.trim(u8, cached_after, " \r\n\t"));

    try testing.expect(!leftoverIndex(allocator, testing.io, path));
}

test "restoreRef is false and quiet on missing, non-git, and bad sha" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const unknown = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    try testing.expect(!restoreRef(allocator, testing.io, "", unknown));
    try testing.expect(!restoreRef(allocator, testing.io, ".zig-cache/tmp/faku-restore-missing", unknown));
    try testing.expect(!restoreRef(allocator, testing.io, ".", "not-a-sha"));
    try testing.expect(!restoreRef(allocator, testing.io, ".", ""));

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var plain_buf: [256]u8 = undefined;
    const plain = try std.fmt.bufPrint(&plain_buf, ".zig-cache/tmp/{s}/plain", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(testing.io, plain);
    try testing.expect(!restoreRef(allocator, testing.io, plain, unknown));

    var repo_buf: [256]u8 = undefined;
    const repo = try std.fmt.bufPrint(&repo_buf, ".zig-cache/tmp/{s}/unknown", .{tmp.sub_path[0..]});
    const head = try initTestRepo(allocator, testing.io, repo);
    defer allocator.free(head);
    try writeRepoFile(testing.io, repo, "README", "keep\n");
    try testing.expect(!restoreRef(allocator, testing.io, repo, unknown));
    var still_buf: [rewind.max_sha]u8 = undefined;
    const still = rewind.revParseHead(allocator, testing.io, repo, &still_buf) orelse return error.GitHead;
    try testing.expectEqualStrings(head, still);
    const readme = try readRepoFile(allocator, testing.io, repo, "README");
    defer allocator.free(readme);
    try testing.expectEqualStrings("keep\n", readme);
}

fn leftoverIndex(allocator: std.mem.Allocator, io: std.Io, project_path: []const u8) bool {
    var git_buf: [std.fs.max_path_bytes]u8 = undefined;
    const git_path = std.fmt.bufPrint(&git_buf, "{s}{s}.git", .{ project_path, std.fs.path.sep_str }) catch return true;
    const faku = runGitCapture(allocator, io, &.{
        "find",
        git_path,
        "-maxdepth",
        "1",
        "-name",
        "faku-checkpoint-index-*",
    }) catch return true;
    defer allocator.free(faku);
    if (std.mem.trim(u8, faku, " \r\n\t").len != 0) return true;
    const waku = runGitCapture(allocator, io, &.{
        "find",
        git_path,
        "-maxdepth",
        "1",
        "-name",
        "waku-checkpoint-index-*",
    }) catch return true;
    defer allocator.free(waku);
    return std.mem.trim(u8, waku, " \r\n\t").len != 0;
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

fn readRepoFile(allocator: std.mem.Allocator, io: std.Io, path: []const u8, name: []const u8) ![]u8 {
    var file_buf: [std.fs.max_path_bytes]u8 = undefined;
    const file_path = try std.fmt.bufPrint(&file_buf, "{s}{s}{s}", .{ path, std.fs.path.sep_str, name });
    return std.Io.Dir.cwd().readFileAlloc(io, file_path, allocator, .limited(64));
}

fn repoFileExists(io: std.Io, path: []const u8, name: []const u8) bool {
    var file_buf: [std.fs.max_path_bytes]u8 = undefined;
    const file_path = std.fmt.bufPrint(&file_buf, "{s}{s}{s}", .{ path, std.fs.path.sep_str, name }) catch return false;
    var file = std.Io.Dir.cwd().openFile(io, file_path, .{}) catch return false;
    file.close(io);
    return true;
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
