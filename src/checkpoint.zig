//! First-cut Waku-style worktree snapshot (isolated temp index).
//!
//! `captureTurnStartCommit` (Send) writes a dangling commit of
//! the live worktree plus untracked files. `GIT_INDEX_FILE` is a
//! `faku-checkpoint-index-*` under the repo `git-common-dir` so
//! the user's index is never staged or unstaged. Identity is
//! `-c user.name=Faku` `-c user.email=faku@localhost`. Message is
//! `Faku turn start snapshot` plus a `Faku-Turn-Start: ` JSON
//! line (`head`, `branch`, `refs`). `commit-tree` gets `-p` for
//! HEAD (when present) then unique `for-each-ref` commits from
//! `refs/heads`, `refs/remotes`, `refs/tags` (tags peeled to
//! commits). `captureWorktreeCommit` (finish) still uses
//! `Faku worktree snapshot` and no `-p`. Always deletes the
//! temp index and `.lock`. After a successful capture, Send
//! names that commit with one-shot
//! `git update-ref refs/faku/session-{Session.id}-turn-start-{n}`
//! (`captureTurnStart` / `updateFakuRef`). `{n}` is the 1-based
//! prompt ordinal of this Send: `Model.turnCount / 2 + 1` at
//! record time, before the user+assistant pair is appended
//! (first Send is `turn-start-1`). If
//! `refs/faku/session-{id}-turn-{n-1}` is missing, the same
//! commit is also named as that baseline. On successful
//! finish, a NEW isolated snapshot is named
//! `refs/faku/session-{id}-turn-{n}` (`captureTurnEnd`;
//! `{n}` is `turnCount / 2` after the pair is appended).
//! After that name is written, `prepareTurnDiffBase` names
//! `refs/faku/session-{id}-turn-diff-{n}` from the turn-start
//! `Faku-Turn-Start: ` JSON (`head` / `branch` / `refs`) so
//! LastTurn after a mid-turn branch switch does not treat
//! other-branch history as turn edits. Same-line (start
//! metadata.branch == end `symbolic-ref` HEAD, or both
//! detached and metadata.head == end HEAD) uses the start
//! snapshot. Else `target_branch_start` plus
//! `virtual_branch_start` (`merge-tree --write-tree` when
//! dirty files were carried). LastTurn / Review prefer
//! stored turn-diff…end two-dot `diff..end` when both are
//! valid 40-hex, else start…end
//! (`worktree_snapshot_sha`..`worktree_turn_end_sha`,
//! Waku `git diff from to`), else the send-time 40-hex, else
//! rewind `sha...HEAD` — not the ref. Failed update-ref is
//! quiet and does not clear the stored sha. Header Rewind
//! restores that stored 40-hex with `restoreRef` (`git
//! restore --source <sha> --worktree --staged -- .`, `git
//! clean -fd -- .`, then `git reset --quiet -- .` when HEAD
//! exists). Sync `std.process.run` like `rewind.captureHead`
//! — not a Native spawn and not `/bin/sh -c` interpolation.
//! Leftovers: force, background work, daemon
//! WorkspaceOperation. Not transcript checkpoint +/-.

const std = @import("std");
const rewind = @import("rewind.zig");

pub const env_bin = "/usr/bin/env";
pub const git_bin = "git";
pub const index_prefix = "faku-checkpoint-index-";
pub const snapshot_message = "Faku worktree snapshot";
pub const turn_start_subject = "Faku turn start snapshot";
pub const turn_start_metadata_prefix = "Faku-Turn-Start: ";
pub const turn_diff_base_message = "Faku turn diff base";
pub const empty_turn_diff_base_message = "Faku empty turn diff base";
pub const empty_tree = "4b825dc642cb6eb9a060e54bf8d69288fbee4904";
pub const identity_name = "user.name=Faku";
pub const identity_email = "user.email=faku@localhost";
pub const commit_gpgsign = "commit.gpgsign=false";
pub const faku_ref_prefix = "refs/faku/";
pub const max_faku_ref_name: usize = 128;
const repo_ref_format = "--format=%(refname)%09%(objecttype)%09%(objectname)%09%(*objecttype)%09%(*objectname)";
const max_repo_refs: usize = 64;
const max_repo_ref_name: usize = 255;
const max_commit_parents: usize = max_repo_refs + 1;
const turn_start_message_max: usize = 24 * 1024;
const repo_ref_stdout_limit: usize = 128 * 1024;
const commit_tree_argv_cap: usize = 160;
const git_c_argv_cap: usize = 24;
const turn_start_show_limit: usize = turn_start_message_max;
const rev_list_stdout_limit: usize = 4096;
const merge_tree_stdout_limit: usize = 8 * 1024;

const RepoRef = struct {
    name_storage: [max_repo_ref_name]u8 = [_]u8{0} ** max_repo_ref_name,
    name_len: usize = 0,
    sha_storage: [rewind.stored_sha_len]u8 = [_]u8{0} ** rewind.stored_sha_len,

    fn name(self: *const RepoRef) []const u8 {
        return self.name_storage[0..self.name_len];
    }

    fn sha(self: *const RepoRef) []const u8 {
        return self.sha_storage[0..rewind.stored_sha_len];
    }
};

const env_prefix = "GIT_INDEX_FILE=";

/// Isolated-index worktree snapshot. Finish / turn-end shape:
/// message `Faku worktree snapshot`, empty parents. Returns a
/// 40-hex sha or null. Missing / non-git / failed plumbing is
/// quiet.
pub fn captureWorktreeCommit(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    dest: []u8,
) ?[]const u8 {
    return captureIsolated(allocator, io, project_path, dest, snapshot_message, &.{});
}

/// Isolated-index turn-start snapshot. Message is
/// `Faku turn start snapshot` plus `Faku-Turn-Start: ` JSON
/// (`head`, `branch`, `refs`). Parents are HEAD (when present)
/// then unique peeled repository-ref commits. Returns a 40-hex
/// sha or null. Missing / non-git / failed plumbing is quiet.
pub fn captureTurnStartCommit(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    dest: []u8,
) ?[]const u8 {
    if (!rewind.isGitWorkTree(io, project_path)) return null;

    var head_buf: [rewind.max_sha]u8 = undefined;
    const head: ?[]const u8 = blk: {
        const raw = rewind.revParseHead(allocator, io, project_path, &head_buf) orelse break :blk null;
        break :blk if (rewind.isStoredSha(raw)) raw else null;
    };

    var branch_buf: [max_repo_ref_name]u8 = undefined;
    const branch = symbolicHead(allocator, io, project_path, &branch_buf);

    var refs: [max_repo_refs]RepoRef = undefined;
    const ref_count = collectRepositoryRefs(allocator, io, project_path, &refs);

    var message_buf: [turn_start_message_max]u8 = undefined;
    const message = buildTurnStartMessage(&message_buf, head, branch, refs[0..ref_count]) orelse return null;

    var parent_slots: [max_commit_parents][]const u8 = undefined;
    const parent_count = collectParents(head, refs[0..ref_count], &parent_slots);

    return captureIsolated(allocator, io, project_path, dest, message, parent_slots[0..parent_count]);
}

fn captureIsolated(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    dest: []u8,
    message: []const u8,
    parents: []const []const u8,
) ?[]const u8 {
    if (!rewind.isGitWorkTree(io, project_path)) return null;

    var common_buf: [std.fs.max_path_bytes]u8 = undefined;
    const common = gitCommonDir(allocator, io, project_path, &common_buf) orelse return null;

    var index_buf: [std.fs.max_path_bytes]u8 = undefined;
    const index_path = uniqueIndexPath(io, common, &index_buf) orelse return null;

    var env_buf: [std.fs.max_path_bytes + env_prefix.len]u8 = undefined;
    const env_slot = std.fmt.bufPrint(&env_buf, "{s}{s}", .{ env_prefix, index_path }) catch return null;

    const captured = captureFromIndex(allocator, io, project_path, env_slot, dest, message, parents);
    deleteIndex(io, index_path);
    return captured;
}

fn captureFromIndex(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    env_slot: []const u8,
    dest: []u8,
    message: []const u8,
    parents: []const []const u8,
) ?[]const u8 {
    var head_buf: [rewind.max_sha]u8 = undefined;
    if (rewind.revParseHead(allocator, io, project_path, &head_buf) != null) {
        if (!runGit(allocator, io, env_slot, project_path, &.{ "read-tree", "HEAD" }, null)) return null;
    }
    if (!runGit(allocator, io, env_slot, project_path, &.{ "add", "-A", "--", "." }, null)) return null;

    var tree_buf: [rewind.stored_sha_len]u8 = undefined;
    const tree = runGitOut(allocator, io, env_slot, project_path, &.{"write-tree"}, &tree_buf) orelse return null;

    var git_args: [8 + max_commit_parents * 2][]const u8 = undefined;
    var n: usize = 0;
    git_args[n] = "-c";
    n += 1;
    git_args[n] = identity_name;
    n += 1;
    git_args[n] = "-c";
    n += 1;
    git_args[n] = identity_email;
    n += 1;
    git_args[n] = "-c";
    n += 1;
    git_args[n] = commit_gpgsign;
    n += 1;
    git_args[n] = "commit-tree";
    n += 1;
    git_args[n] = tree;
    n += 1;
    git_args[n] = "-m";
    n += 1;
    git_args[n] = message;
    n += 1;
    for (parents) |parent| {
        if (n + 1 >= git_args.len) return null;
        git_args[n] = "-p";
        n += 1;
        git_args[n] = parent;
        n += 1;
    }

    var commit_buf: [rewind.stored_sha_len]u8 = undefined;
    const commit = runGitOut(allocator, io, env_slot, project_path, git_args[0..n], &commit_buf) orelse return null;
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

/// 1-based prompt ordinal at successful finish.
/// `transcript_turns` is `Model.turnCount` after the
/// user+assistant pair is already appended, so this matches
/// `fakuSendTurn` from the same Send.
pub fn fakuFinishTurn(transcript_turns: u32) u32 {
    return transcript_turns / 2;
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

/// `refs/faku/session-{session_id}-turn-diff-{turn_count}` into
/// `dest`. Same fit / `isFakuRefName` rules as the other
/// session refs (`-` is already allowed). Null when the name
/// would not fit `dest` or `max_faku_ref_name`.
pub fn formatFakuSessionTurnDiffRef(dest: []u8, session_id: u32, turn_count: u32) ?[]const u8 {
    const printed = std.fmt.bufPrint(dest, "refs/faku/session-{d}-turn-diff-{d}", .{ session_id, turn_count }) catch return null;
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
/// `turn-{n}` (that is `captureTurnEnd` at finish). Quiet
/// false only when the turn-start update fails; a failed
/// baseline seed is still true.
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

/// Name the stored 40-hex as `turn-{n}`. Requires a valid
/// 40-hex sha. Does not write turn-start refs. Quiet false on
/// bad sha / bad ref / failed update-ref.
pub fn captureTurnEnd(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    session_id: u32,
    turn_count: u32,
    sha: []const u8,
) bool {
    if (!rewind.isStoredSha(sha)) return false;
    var end_buf: [max_faku_ref_name]u8 = undefined;
    const end_ref = formatFakuSessionTurnRef(&end_buf, session_id, turn_count) orelse return false;
    return updateFakuRef(allocator, io, project_path, end_ref, sha);
}

/// After `turn-{n}` is named, compute a branch-switch-aware
/// LastTurn base and name it `turn-diff-{n}`. Requires
/// `turn-start-{n}`. Same-line uses the start snapshot.
/// Else target-branch start plus a virtual merge of carried
/// dirty files. Quiet null on missing start ref / non-git /
/// failed plumbing. Failed update-ref still returns the
/// computed 40-hex so LastTurn can use the stored sha.
pub fn prepareTurnDiffBase(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    session_id: u32,
    turn_count: u32,
    dest: []u8,
) ?[]const u8 {
    if (!rewind.isGitWorkTree(io, project_path)) return null;
    var start_buf: [max_faku_ref_name]u8 = undefined;
    const start_ref = formatFakuSessionTurnStartRef(&start_buf, session_id, turn_count) orelse return null;
    if (!hasFakuRef(allocator, io, project_path, start_ref)) return null;

    var meta = TurnStartMeta{};
    if (!loadTurnStartMetadata(allocator, io, project_path, start_ref, &meta)) return null;

    var end_head_buf: [rewind.max_sha]u8 = undefined;
    const end_head: ?[]const u8 = blk: {
        const raw = rewind.revParseHead(allocator, io, project_path, &end_head_buf) orelse break :blk null;
        break :blk if (rewind.isStoredSha(raw)) raw else null;
    };
    var end_branch_buf: [max_repo_ref_name]u8 = undefined;
    const end_branch = symbolicHead(allocator, io, project_path, &end_branch_buf);

    const same_line = sameLine(meta.branch(), end_branch, meta.head(), end_head);

    var commit_buf: [rewind.stored_sha_len]u8 = undefined;
    const commit = if (same_line)
        resolveCommit(allocator, io, project_path, start_ref, &commit_buf) orelse return null
    else blk: {
        var target_buf: [rewind.stored_sha_len]u8 = undefined;
        const target_base = targetBranchStart(
            allocator,
            io,
            project_path,
            start_ref,
            &meta,
            end_head,
            end_branch,
            &target_buf,
        ) orelse return null;
        break :blk virtualBranchStart(
            allocator,
            io,
            project_path,
            start_ref,
            meta.head(),
            target_base,
            &commit_buf,
        ) orelse return null;
    };

    var diff_buf: [max_faku_ref_name]u8 = undefined;
    if (formatFakuSessionTurnDiffRef(&diff_buf, session_id, turn_count)) |diff_ref| {
        _ = updateFakuRef(allocator, io, project_path, diff_ref, commit);
    }
    return copySha(commit, dest);
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

const TurnStartMeta = struct {
    head_storage: [rewind.stored_sha_len]u8 = [_]u8{0} ** rewind.stored_sha_len,
    head_len: usize = 0,
    branch_storage: [max_repo_ref_name]u8 = [_]u8{0} ** max_repo_ref_name,
    branch_len: usize = 0,
    refs: [max_repo_refs]RepoRef = [_]RepoRef{.{}} ** max_repo_refs,
    ref_count: usize = 0,

    fn head(self: *const TurnStartMeta) ?[]const u8 {
        if (self.head_len == 0) return null;
        return self.head_storage[0..self.head_len];
    }

    fn branch(self: *const TurnStartMeta) ?[]const u8 {
        if (self.branch_len == 0) return null;
        return self.branch_storage[0..self.branch_len];
    }

    fn refSha(self: *const TurnStartMeta, name: []const u8) ?[]const u8 {
        for (self.refs[0..self.ref_count]) |ref| {
            if (std.mem.eql(u8, ref.name(), name)) return ref.sha();
        }
        return null;
    }
};

fn sameLine(start_branch: ?[]const u8, end_branch: ?[]const u8, start_head: ?[]const u8, end_head: ?[]const u8) bool {
    if (start_branch) |start| {
        const end = end_branch orelse return false;
        return std.mem.eql(u8, start, end);
    }
    if (end_branch != null) return false;
    return optionalEql(start_head, end_head);
}

fn optionalEql(a: ?[]const u8, b: ?[]const u8) bool {
    const left = a orelse {
        return b == null;
    };
    const right = b orelse return false;
    return std.mem.eql(u8, left, right);
}

fn loadTurnStartMetadata(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    start_ref: []const u8,
    dest: *TurnStartMeta,
) bool {
    var message_buf: [turn_start_message_max]u8 = undefined;
    const message = runGitCOut(
        allocator,
        io,
        project_path,
        &.{ "show", "-s", "--format=%B", start_ref },
        &message_buf,
        turn_start_show_limit,
    ) orelse return false;
    const parsed = parseTurnStartMetadata(allocator, message) catch return false;
    defer parsed.deinit();
    return fillTurnStartMeta(parsed.value, dest);
}

fn fillTurnStartMeta(value: std.json.Value, dest: *TurnStartMeta) bool {
    if (value != .object) return false;
    dest.* = .{};
    if (value.object.get("head")) |head_val| {
        switch (head_val) {
            .null => {},
            .string => |s| {
                if (!rewind.isStoredSha(s)) return false;
                @memcpy(&dest.head_storage, s);
                dest.head_len = rewind.stored_sha_len;
            },
            else => return false,
        }
    }
    if (value.object.get("branch")) |branch_val| {
        switch (branch_val) {
            .null => {},
            .string => |s| {
                if (s.len == 0 or s.len > max_repo_ref_name) return false;
                @memcpy(dest.branch_storage[0..s.len], s);
                dest.branch_len = s.len;
            },
            else => return false,
        }
    }
    const refs_val = value.object.get("refs") orelse return false;
    if (refs_val != .object) return false;
    var it = refs_val.object.iterator();
    while (it.next()) |entry| {
        if (dest.ref_count >= max_repo_refs) break;
        const name = entry.key_ptr.*;
        if (name.len == 0 or name.len > max_repo_ref_name) continue;
        const sha = switch (entry.value_ptr.*) {
            .string => |s| s,
            else => continue,
        };
        if (!rewind.isStoredSha(sha)) continue;
        var ref = &dest.refs[dest.ref_count];
        @memcpy(ref.name_storage[0..name.len], name);
        ref.name_len = name.len;
        @memcpy(&ref.sha_storage, sha);
        dest.ref_count += 1;
    }
    return true;
}

fn targetBranchStart(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    start_ref: []const u8,
    metadata: *const TurnStartMeta,
    end_head: ?[]const u8,
    end_branch: ?[]const u8,
    dest: []u8,
) ?[]const u8 {
    if (end_branch) |branch| {
        if (metadata.refSha(branch)) |commit| return copySha(commit, dest);
    }
    const head = end_head orelse return emptyTreeCommit(allocator, io, project_path, dest);
    var list_buf: [rewind.stored_sha_len]u8 = undefined;
    const listed = runGitCFirstLine(
        allocator,
        io,
        project_path,
        &.{ "rev-list", "--first-parent", "--reverse", head, "--not", start_ref },
        &list_buf,
        rev_list_stdout_limit,
    ) orelse return null;
    const first = listed;
    if (first.len == 0) return copySha(head, dest);
    if (!rewind.isStoredSha(first)) return null;
    var parent_spec: [rewind.stored_sha_len + 2]u8 = undefined;
    const spec = std.fmt.bufPrint(&parent_spec, "{s}^1", .{first}) catch return null;
    var parent_buf: [rewind.stored_sha_len]u8 = undefined;
    if (resolveCommit(allocator, io, project_path, spec, &parent_buf)) |parent| {
        return copySha(parent, dest);
    }
    return emptyTreeCommit(allocator, io, project_path, dest);
}

fn virtualBranchStart(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    start_ref: []const u8,
    start_head: ?[]const u8,
    target_base: []const u8,
    dest: []u8,
) ?[]const u8 {
    const head = start_head orelse return copySha(target_base, dest);
    if (std.mem.eql(u8, head, target_base)) {
        return resolveCommit(allocator, io, project_path, start_ref, dest);
    }
    const names_empty = gitDiffNameOnlyEmpty(allocator, io, project_path, head, start_ref) orelse return null;
    if (names_empty) return copySha(target_base, dest);

    var merge_buf: [merge_tree_stdout_limit]u8 = undefined;
    const merge_out = runGitCOut(
        allocator,
        io,
        project_path,
        &.{ "merge-tree", "--write-tree", "--merge-base", head, target_base, start_ref },
        &merge_buf,
        merge_tree_stdout_limit,
    ) orelse return null;
    const tree = firstNonEmptyLine(merge_out);
    if (tree.len == 0) return null;
    return commitTreeIsolated(allocator, io, project_path, dest, tree, turn_diff_base_message);
}

fn emptyTreeCommit(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    dest: []u8,
) ?[]const u8 {
    if (commitTreeIsolated(allocator, io, project_path, dest, empty_tree, empty_turn_diff_base_message)) |sha| {
        return sha;
    }
    var common_buf: [std.fs.max_path_bytes]u8 = undefined;
    const common = gitCommonDir(allocator, io, project_path, &common_buf) orelse return null;
    var index_buf: [std.fs.max_path_bytes]u8 = undefined;
    const index_path = uniqueIndexPath(io, common, &index_buf) orelse return null;
    var env_buf: [std.fs.max_path_bytes + env_prefix.len]u8 = undefined;
    const env_slot = std.fmt.bufPrint(&env_buf, "{s}{s}", .{ env_prefix, index_path }) catch return null;
    var tree_buf: [rewind.stored_sha_len]u8 = undefined;
    const tree = runGitOut(allocator, io, env_slot, project_path, &.{"write-tree"}, &tree_buf);
    const commit = if (tree) |oid|
        commitTreeFromIndex(allocator, io, env_slot, project_path, dest, oid, empty_turn_diff_base_message)
    else
        null;
    deleteIndex(io, index_path);
    return commit;
}

fn commitTreeIsolated(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    dest: []u8,
    tree: []const u8,
    message: []const u8,
) ?[]const u8 {
    if (!rewind.isGitWorkTree(io, project_path)) return null;
    var common_buf: [std.fs.max_path_bytes]u8 = undefined;
    const common = gitCommonDir(allocator, io, project_path, &common_buf) orelse return null;
    var index_buf: [std.fs.max_path_bytes]u8 = undefined;
    const index_path = uniqueIndexPath(io, common, &index_buf) orelse return null;
    var env_buf: [std.fs.max_path_bytes + env_prefix.len]u8 = undefined;
    const env_slot = std.fmt.bufPrint(&env_buf, "{s}{s}", .{ env_prefix, index_path }) catch return null;
    const commit = commitTreeFromIndex(allocator, io, env_slot, project_path, dest, tree, message);
    deleteIndex(io, index_path);
    return commit;
}

fn commitTreeFromIndex(
    allocator: std.mem.Allocator,
    io: std.Io,
    env_slot: []const u8,
    project_path: []const u8,
    dest: []u8,
    tree: []const u8,
    message: []const u8,
) ?[]const u8 {
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
        message,
    }, dest) orelse return null;
    if (!rewind.isStoredSha(commit)) return null;
    return commit;
}

fn resolveCommit(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    git_ref: []const u8,
    dest: []u8,
) ?[]const u8 {
    const parsed = runGitCOut(
        allocator,
        io,
        project_path,
        &.{ "rev-parse", "--verify", git_ref },
        dest,
        128,
    ) orelse return null;
    if (!rewind.isStoredSha(parsed)) return null;
    return parsed;
}

fn gitDiffNameOnlyEmpty(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    left: []const u8,
    right: []const u8,
) ?bool {
    var argv_buf: [git_c_argv_cap][]const u8 = undefined;
    var n: usize = 0;
    argv_buf[n] = git_bin;
    n += 1;
    argv_buf[n] = "-C";
    n += 1;
    argv_buf[n] = project_path;
    n += 1;
    argv_buf[n] = "diff";
    n += 1;
    argv_buf[n] = "--name-only";
    n += 1;
    argv_buf[n] = left;
    n += 1;
    argv_buf[n] = right;
    n += 1;
    const result = std.process.run(allocator, io, .{
        .argv = argv_buf[0..n],
        .stdout_limit = .limited(256),
        .stderr_limit = .limited(512),
    }) catch return null;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    if (result.term != .exited or result.term.exited != 0) return null;
    return std.mem.trim(u8, result.stdout, " \r\n\t").len == 0;
}

fn copySha(src: []const u8, dest: []u8) ?[]const u8 {
    if (!rewind.isStoredSha(src)) return null;
    if (src.len > dest.len) return null;
    @memcpy(dest[0..src.len], src);
    return dest[0..src.len];
}

fn firstNonEmptyLine(text: []const u8) []const u8 {
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \r\n\t");
        if (line.len != 0) return line;
    }
    return "";
}

fn runGitCOut(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    git_args: []const []const u8,
    dest: []u8,
    stdout_limit: usize,
) ?[]const u8 {
    const raw = runGitCRaw(allocator, io, project_path, git_args, stdout_limit) orelse return null;
    defer allocator.free(raw.stdout);
    defer allocator.free(raw.stderr);
    if (raw.term != .exited or raw.term.exited != 0) return null;
    const trimmed = std.mem.trim(u8, raw.stdout, " \r\n\t");
    if (trimmed.len > dest.len) return null;
    if (trimmed.len == 0) return dest[0..0];
    @memcpy(dest[0..trimmed.len], trimmed);
    return dest[0..trimmed.len];
}

fn runGitCFirstLine(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    git_args: []const []const u8,
    dest: []u8,
    stdout_limit: usize,
) ?[]const u8 {
    const raw = runGitCRaw(allocator, io, project_path, git_args, stdout_limit) orelse return null;
    defer allocator.free(raw.stdout);
    defer allocator.free(raw.stderr);
    if (raw.term != .exited or raw.term.exited != 0) return null;
    const line = firstNonEmptyLine(raw.stdout);
    if (line.len > dest.len) return null;
    if (line.len == 0) return dest[0..0];
    @memcpy(dest[0..line.len], line);
    return dest[0..line.len];
}

fn runGitCRaw(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    git_args: []const []const u8,
    stdout_limit: usize,
) ?std.process.RunResult {
    var argv_buf: [git_c_argv_cap][]const u8 = undefined;
    var n: usize = 0;
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
    return std.process.run(allocator, io, .{
        .argv = argv_buf[0..n],
        .stdout_limit = .limited(stdout_limit),
        .stderr_limit = .limited(2048),
    }) catch null;
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
    var argv_buf: [commit_tree_argv_cap][]const u8 = undefined;
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

fn symbolicHead(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    dest: []u8,
) ?[]const u8 {
    const result = std.process.run(allocator, io, .{
        .argv = &.{ git_bin, "-C", project_path, "symbolic-ref", "--quiet", "HEAD" },
        .stdout_limit = .limited(256),
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

fn collectRepositoryRefs(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    dest: []RepoRef,
) usize {
    const result = std.process.run(allocator, io, .{
        .argv = &.{
            git_bin,
            "-C",
            project_path,
            "for-each-ref",
            repo_ref_format,
            "refs/heads",
            "refs/remotes",
            "refs/tags",
        },
        .stdout_limit = .limited(repo_ref_stdout_limit),
        .stderr_limit = .limited(512),
    }) catch return 0;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    if (result.term != .exited or result.term.exited != 0) return 0;

    var n: usize = 0;
    var lines = std.mem.splitScalar(u8, result.stdout, '\n');
    while (lines.next()) |raw| {
        if (n >= dest.len) break;
        const line = std.mem.trim(u8, raw, " \r\n\t");
        if (line.len == 0) continue;
        if (parseRepoRef(line, &dest[n])) n += 1;
    }
    sortRepoRefs(dest[0..n]);
    return n;
}

fn parseRepoRef(line: []const u8, dest: *RepoRef) bool {
    var fields = std.mem.splitScalar(u8, line, '\t');
    const refname = fields.next() orelse return false;
    const object_type = fields.next() orelse return false;
    const object = fields.next() orelse return false;
    const peeled_type = fields.next() orelse "";
    const peeled = fields.next() orelse "";
    const commit = if (std.mem.eql(u8, object_type, "commit"))
        object
    else if (std.mem.eql(u8, peeled_type, "commit"))
        peeled
    else
        return false;
    if (refname.len == 0 or refname.len > max_repo_ref_name) return false;
    if (!rewind.isStoredSha(commit)) return false;
    @memcpy(dest.name_storage[0..refname.len], refname);
    dest.name_len = refname.len;
    @memcpy(&dest.sha_storage, commit);
    return true;
}

fn sortRepoRefs(refs: []RepoRef) void {
    var i: usize = 1;
    while (i < refs.len) : (i += 1) {
        var j = i;
        while (j > 0 and std.mem.lessThan(u8, refs[j].name(), refs[j - 1].name())) {
            const tmp = refs[j];
            refs[j] = refs[j - 1];
            refs[j - 1] = tmp;
            j -= 1;
        }
    }
}

fn collectParents(
    head: ?[]const u8,
    refs: []const RepoRef,
    dest: [][]const u8,
) usize {
    var n: usize = 0;
    if (head) |h| {
        if (rewind.isStoredSha(h) and n < dest.len) {
            dest[n] = h;
            n += 1;
        }
    }
    for (refs) |ref| {
        if (n >= dest.len) break;
        if (parentSeen(dest[0..n], ref.sha())) continue;
        dest[n] = ref.sha();
        n += 1;
    }
    return n;
}

fn parentSeen(parents: []const []const u8, sha: []const u8) bool {
    for (parents) |parent| {
        if (std.mem.eql(u8, parent, sha)) return true;
    }
    return false;
}

fn buildTurnStartMessage(
    dest: []u8,
    head: ?[]const u8,
    branch: ?[]const u8,
    refs: []const RepoRef,
) ?[]const u8 {
    var n: usize = 0;
    if (!appendSlice(dest, &n, turn_start_subject)) return null;
    if (!appendSlice(dest, &n, "\n\n")) return null;
    if (!appendSlice(dest, &n, turn_start_metadata_prefix)) return null;
    if (!appendSlice(dest, &n, "{\"head\":")) return null;
    if (!appendJsonOptionalString(dest, &n, head)) return null;
    if (!appendSlice(dest, &n, ",\"branch\":")) return null;
    if (!appendJsonOptionalString(dest, &n, branch)) return null;
    if (!appendSlice(dest, &n, ",\"refs\":{")) return null;
    for (refs, 0..) |ref, i| {
        if (i != 0 and !appendSlice(dest, &n, ",")) return null;
        if (!appendJsonString(dest, &n, ref.name())) return null;
        if (!appendSlice(dest, &n, ":")) return null;
        if (!appendJsonString(dest, &n, ref.sha())) return null;
    }
    if (!appendSlice(dest, &n, "}}")) return null;
    return dest[0..n];
}

fn appendJsonOptionalString(dest: []u8, n: *usize, value: ?[]const u8) bool {
    if (value) |text| return appendJsonString(dest, n, text);
    return appendSlice(dest, n, "null");
}

fn appendJsonString(dest: []u8, n: *usize, text: []const u8) bool {
    if (!appendByte(dest, n, '"')) return false;
    for (text) |c| {
        switch (c) {
            '"' => {
                if (!appendSlice(dest, n, "\\\"")) return false;
            },
            '\\' => {
                if (!appendSlice(dest, n, "\\\\")) return false;
            },
            '\n' => {
                if (!appendSlice(dest, n, "\\n")) return false;
            },
            '\r' => {
                if (!appendSlice(dest, n, "\\r")) return false;
            },
            '\t' => {
                if (!appendSlice(dest, n, "\\t")) return false;
            },
            else => {
                if (c < 0x20) {
                    var hex: [6]u8 = undefined;
                    const piece = std.fmt.bufPrint(&hex, "\\u{x:0>4}", .{c}) catch return false;
                    if (!appendSlice(dest, n, piece)) return false;
                } else if (!appendByte(dest, n, c)) {
                    return false;
                }
            },
        }
    }
    return appendByte(dest, n, '"');
}

fn appendSlice(dest: []u8, n: *usize, text: []const u8) bool {
    if (n.* + text.len > dest.len) return false;
    @memcpy(dest[n.* ..][0..text.len], text);
    n.* += text.len;
    return true;
}

fn appendByte(dest: []u8, n: *usize, byte: u8) bool {
    if (n.* >= dest.len) return false;
    dest[n.*] = byte;
    n.* += 1;
    return true;
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

    const message = try runGitCapture(allocator, testing.io, &.{
        "git",
        "-C",
        path,
        "log",
        "-1",
        "--format=%B",
        snap,
    });
    defer allocator.free(message);
    try testing.expectEqualStrings(snapshot_message, std.mem.trim(u8, message, " \r\n\t"));
    try testing.expect(std.mem.indexOf(u8, message, turn_start_subject) == null);
    try testing.expect(std.mem.indexOf(u8, message, turn_start_metadata_prefix) == null);

    try testing.expect(!leftoverIndex(allocator, testing.io, path));
}

test "captureWorktreeCommit is null for missing and non-git paths" {
    const testing = std.testing;
    var sha_buf: [rewind.stored_sha_len]u8 = undefined;
    try testing.expect(captureWorktreeCommit(testing.allocator, testing.io, "", &sha_buf) == null);
    try testing.expect(captureWorktreeCommit(testing.allocator, testing.io, ".zig-cache/tmp/faku-checkpoint-missing", &sha_buf) == null);
    try testing.expect(captureTurnStartCommit(testing.allocator, testing.io, "", &sha_buf) == null);
    try testing.expect(captureTurnStartCommit(testing.allocator, testing.io, ".zig-cache/tmp/faku-checkpoint-missing", &sha_buf) == null);

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [256]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, ".zig-cache/tmp/{s}/plain", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(testing.io, path);
    try testing.expect(captureWorktreeCommit(testing.allocator, testing.io, path, &sha_buf) == null);
    try testing.expect(captureTurnStartCommit(testing.allocator, testing.io, path, &sha_buf) == null);
}

test "captureTurnStartCommit records parents and Faku-Turn-Start metadata" {
    const testing = std.testing;
    const allocator = testing.allocator;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [256]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, ".zig-cache/tmp/{s}/turn-start-meta", .{tmp.sub_path[0..]});
    const head = try initTestRepo(allocator, testing.io, path);
    defer allocator.free(head);

    try writeRepoFile(testing.io, path, "README", "dirty\n");
    try writeRepoFile(testing.io, path, "untracked.txt", "new\n");

    var sha_buf: [rewind.stored_sha_len]u8 = undefined;
    const snap = captureTurnStartCommit(allocator, testing.io, path, &sha_buf) orelse return error.MissingSnapshot;
    try testing.expect(rewind.isStoredSha(snap));
    try testing.expect(!std.mem.eql(u8, head, snap));

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
    const parent_line = std.mem.trim(u8, parents, " \r\n\t");
    try testing.expect(std.mem.startsWith(u8, parent_line, snap));
    try testing.expect(std.mem.indexOf(u8, parent_line, head) != null);
    try testing.expect(parentCount(parent_line) >= 1);

    const message = try runGitCapture(allocator, testing.io, &.{
        "git",
        "-C",
        path,
        "log",
        "-1",
        "--format=%B",
        snap,
    });
    defer allocator.free(message);
    try testing.expect(std.mem.indexOf(u8, message, turn_start_subject) != null);
    try testing.expect(std.mem.indexOf(u8, message, snapshot_message) == null);
    const meta = try parseTurnStartMetadata(allocator, message);
    defer meta.deinit();
    try expectJsonString(meta.value, "head", head);
    const branch = try runGitCapture(allocator, testing.io, &.{
        "git",
        "-C",
        path,
        "symbolic-ref",
        "--quiet",
        "HEAD",
    });
    defer allocator.free(branch);
    try expectJsonString(meta.value, "branch", std.mem.trim(u8, branch, " \r\n\t"));
    const refs = meta.value.object.get("refs") orelse return error.MissingRefs;
    try testing.expect(refs == .object);
    try testing.expect(refs.object.count() >= 1);
    try testing.expectEqualStrings(head, refs.object.get(std.mem.trim(u8, branch, " \r\n\t")).?.string);

    try testing.expect(!leftoverIndex(allocator, testing.io, path));
}

test "captureTurnStartCommit detached HEAD leaves branch null and still parents HEAD" {
    const testing = std.testing;
    const allocator = testing.allocator;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [256]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, ".zig-cache/tmp/{s}/turn-start-detach", .{tmp.sub_path[0..]});
    const head = try initTestRepo(allocator, testing.io, path);
    defer allocator.free(head);
    try runGitPlain(allocator, testing.io, &.{ "git", "-C", path, "checkout", "--detach", "--quiet" });

    var sha_buf: [rewind.stored_sha_len]u8 = undefined;
    const snap = captureTurnStartCommit(allocator, testing.io, path, &sha_buf) orelse return error.MissingSnapshot;

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
    try testing.expect(std.mem.indexOf(u8, std.mem.trim(u8, parents, " \r\n\t"), head) != null);

    const message = try runGitCapture(allocator, testing.io, &.{
        "git",
        "-C",
        path,
        "log",
        "-1",
        "--format=%B",
        snap,
    });
    defer allocator.free(message);
    const meta = try parseTurnStartMetadata(allocator, message);
    defer meta.deinit();
    try expectJsonString(meta.value, "head", head);
    try testing.expect(meta.value.object.get("branch").? == .null);
}

test "captureTurnStartCommit peels annotated tags and dedupes shared commits" {
    const testing = std.testing;
    const allocator = testing.allocator;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [256]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, ".zig-cache/tmp/{s}/turn-start-tag", .{tmp.sub_path[0..]});
    const head = try initTestRepo(allocator, testing.io, path);
    defer allocator.free(head);
    try runGitPlain(allocator, testing.io, &.{
        "git",
        "-C",
        path,
        "-c",
        "user.email=checkpoint@test",
        "-c",
        "user.name=Checkpoint",
        "-c",
        commit_gpgsign,
        "tag",
        "-a",
        "v1",
        "-m",
        "annotated",
    });

    var sha_buf: [rewind.stored_sha_len]u8 = undefined;
    const snap = captureTurnStartCommit(allocator, testing.io, path, &sha_buf) orelse return error.MissingSnapshot;
    const message = try runGitCapture(allocator, testing.io, &.{
        "git",
        "-C",
        path,
        "log",
        "-1",
        "--format=%B",
        snap,
    });
    defer allocator.free(message);
    const meta = try parseTurnStartMetadata(allocator, message);
    defer meta.deinit();
    const refs = meta.value.object.get("refs").?.object;
    try testing.expectEqualStrings(head, refs.get("refs/tags/v1").?.string);

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
    try testing.expectEqual(@as(usize, 1), parentCount(std.mem.trim(u8, parents, " \r\n\t")));
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
    try testing.expectEqual(@as(u32, 0), fakuFinishTurn(0));
    try testing.expectEqual(@as(u32, 0), fakuFinishTurn(1));
    try testing.expectEqual(@as(u32, 1), fakuFinishTurn(2));
    try testing.expectEqual(@as(u32, 1), fakuFinishTurn(3));
    try testing.expectEqual(@as(u32, 2), fakuFinishTurn(4));
    try testing.expectEqual(fakuSendTurn(0), fakuFinishTurn(2));
    try testing.expectEqual(fakuSendTurn(2), fakuFinishTurn(4));
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

test "formatFakuSessionTurnDiffRef uses session id and prompt ordinal" {
    const testing = std.testing;
    var buf: [max_faku_ref_name]u8 = undefined;
    const name = formatFakuSessionTurnDiffRef(&buf, 7, 3) orelse return error.MissingFakuRef;
    try testing.expectEqualStrings("refs/faku/session-7-turn-diff-3", name);
    try testing.expect(isFakuRefName(name));
    try testing.expect(isFakuRefName("refs/faku/session-1-turn-diff-1"));
    var tiny: [8]u8 = undefined;
    try testing.expect(formatFakuSessionTurnDiffRef(&tiny, 1, 1) == null);
}

test "prepareTurnDiffBase same-line is the start snapshot sha" {
    const testing = std.testing;
    const allocator = testing.allocator;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [256]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, ".zig-cache/tmp/{s}/turn-diff-same", .{tmp.sub_path[0..]});
    const head = try initTestRepo(allocator, testing.io, path);
    defer allocator.free(head);

    var start_sha_buf: [rewind.stored_sha_len]u8 = undefined;
    const start = captureTurnStartCommit(allocator, testing.io, path, &start_sha_buf) orelse return error.MissingStart;
    try testing.expect(captureTurnStart(allocator, testing.io, path, 4, 1, start));

    try writeRepoFile(testing.io, path, "README", "edited on the same line\n");
    var end_sha_buf: [rewind.stored_sha_len]u8 = undefined;
    const end = captureWorktreeCommit(allocator, testing.io, path, &end_sha_buf) orelse return error.MissingEnd;
    try testing.expect(captureTurnEnd(allocator, testing.io, path, 4, 1, end));

    var diff_sha_buf: [rewind.stored_sha_len]u8 = undefined;
    const diff_base = prepareTurnDiffBase(allocator, testing.io, path, 4, 1, &diff_sha_buf) orelse return error.MissingDiffBase;
    try testing.expectEqualStrings(start, diff_base);

    var diff_ref_buf: [max_faku_ref_name]u8 = undefined;
    const diff_ref = formatFakuSessionTurnDiffRef(&diff_ref_buf, 4, 1) orelse return error.MissingDiffRef;
    try testing.expectEqualStrings("refs/faku/session-4-turn-diff-1", diff_ref);
    try testing.expect(hasFakuRef(allocator, testing.io, path, diff_ref));
    const parsed = try runGitCapture(allocator, testing.io, &.{ "git", "-C", path, "rev-parse", diff_ref });
    defer allocator.free(parsed);
    try testing.expectEqualStrings(start, std.mem.trim(u8, parsed, " \r\n\t"));

    const names = try runGitCapture(allocator, testing.io, &.{ "git", "-C", path, "diff", "--name-only", diff_base, end });
    defer allocator.free(names);
    try testing.expect(std.mem.indexOf(u8, names, "README") != null);
}

test "prepareTurnDiffBase branch-switch with no edits is empty vs end" {
    const testing = std.testing;
    const allocator = testing.allocator;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [256]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, ".zig-cache/tmp/{s}/turn-diff-switch", .{tmp.sub_path[0..]});
    const head = try initDivergedRepo(allocator, testing.io, path);
    defer allocator.free(head);

    var start_sha_buf: [rewind.stored_sha_len]u8 = undefined;
    const start = captureTurnStartCommit(allocator, testing.io, path, &start_sha_buf) orelse return error.MissingStart;
    try testing.expect(captureTurnStart(allocator, testing.io, path, 5, 1, start));

    try runGitPlain(allocator, testing.io, &.{ "git", "-C", path, "checkout", "--quiet", "feature" });
    var end_sha_buf: [rewind.stored_sha_len]u8 = undefined;
    const end = captureWorktreeCommit(allocator, testing.io, path, &end_sha_buf) orelse return error.MissingEnd;
    try testing.expect(captureTurnEnd(allocator, testing.io, path, 5, 1, end));

    var diff_sha_buf: [rewind.stored_sha_len]u8 = undefined;
    const diff_base = prepareTurnDiffBase(allocator, testing.io, path, 5, 1, &diff_sha_buf) orelse return error.MissingDiffBase;
    try testing.expect(rewind.isStoredSha(diff_base));
    try testing.expect(!std.mem.eql(u8, start, diff_base));

    const names = try runGitCapture(allocator, testing.io, &.{ "git", "-C", path, "diff", "--name-only", diff_base, end });
    defer allocator.free(names);
    try testing.expectEqualStrings("", std.mem.trim(u8, names, " \r\n\t"));
    try testing.expect(std.mem.indexOf(u8, names, "feature-only.txt") == null);
    try testing.expect(std.mem.indexOf(u8, names, "main-only.txt") == null);
}

test "prepareTurnDiffBase branch-switch reports only edits on the target" {
    const testing = std.testing;
    const allocator = testing.allocator;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [256]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, ".zig-cache/tmp/{s}/turn-diff-target", .{tmp.sub_path[0..]});
    const head = try initDivergedRepo(allocator, testing.io, path);
    defer allocator.free(head);

    var start_sha_buf: [rewind.stored_sha_len]u8 = undefined;
    const start = captureTurnStartCommit(allocator, testing.io, path, &start_sha_buf) orelse return error.MissingStart;
    try testing.expect(captureTurnStart(allocator, testing.io, path, 6, 1, start));

    try runGitPlain(allocator, testing.io, &.{ "git", "-C", path, "checkout", "--quiet", "feature" });
    try writeRepoFile(testing.io, path, "target.txt", "changed during turn\n");
    try runGitPlain(allocator, testing.io, &.{ "git", "-C", path, "add", "target.txt" });
    try runGitPlain(allocator, testing.io, &.{
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
        "turn change",
    });
    try writeRepoFile(testing.io, path, "untracked.txt", "new during turn\n");

    var end_sha_buf: [rewind.stored_sha_len]u8 = undefined;
    const end = captureWorktreeCommit(allocator, testing.io, path, &end_sha_buf) orelse return error.MissingEnd;
    try testing.expect(captureTurnEnd(allocator, testing.io, path, 6, 1, end));

    var diff_sha_buf: [rewind.stored_sha_len]u8 = undefined;
    const diff_base = prepareTurnDiffBase(allocator, testing.io, path, 6, 1, &diff_sha_buf) orelse return error.MissingDiffBase;

    const names = try runGitCapture(allocator, testing.io, &.{ "git", "-C", path, "diff", "--name-only", diff_base, end });
    defer allocator.free(names);
    try testing.expect(std.mem.indexOf(u8, names, "target.txt") != null);
    try testing.expect(std.mem.indexOf(u8, names, "untracked.txt") != null);
    try testing.expect(std.mem.indexOf(u8, names, "feature-only.txt") == null);
    try testing.expect(std.mem.indexOf(u8, names, "main-only.txt") == null);
}

test "prepareTurnDiffBase does not attribute dirty files carried across a switch" {
    const testing = std.testing;
    const allocator = testing.allocator;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [256]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, ".zig-cache/tmp/{s}/turn-diff-dirty", .{tmp.sub_path[0..]});
    const head = try initDivergedRepo(allocator, testing.io, path);
    defer allocator.free(head);

    try writeRepoFile(testing.io, path, "shared.txt", "already dirty\n");
    var start_sha_buf: [rewind.stored_sha_len]u8 = undefined;
    const start = captureTurnStartCommit(allocator, testing.io, path, &start_sha_buf) orelse return error.MissingStart;
    try testing.expect(captureTurnStart(allocator, testing.io, path, 8, 1, start));

    try runGitPlain(allocator, testing.io, &.{ "git", "-C", path, "checkout", "--quiet", "feature" });
    var end_sha_buf: [rewind.stored_sha_len]u8 = undefined;
    const end = captureWorktreeCommit(allocator, testing.io, path, &end_sha_buf) orelse return error.MissingEnd;
    try testing.expect(captureTurnEnd(allocator, testing.io, path, 8, 1, end));

    var diff_sha_buf: [rewind.stored_sha_len]u8 = undefined;
    const diff_base = prepareTurnDiffBase(allocator, testing.io, path, 8, 1, &diff_sha_buf) orelse return error.MissingDiffBase;
    const names = try runGitCapture(allocator, testing.io, &.{ "git", "-C", path, "diff", "--name-only", diff_base, end });
    defer allocator.free(names);
    try testing.expectEqualStrings("", std.mem.trim(u8, names, " \r\n\t"));
}

test "prepareTurnDiffBase is null and quiet without a turn-start ref" {
    const testing = std.testing;
    const allocator = testing.allocator;
    var sha_buf: [rewind.stored_sha_len]u8 = undefined;
    try testing.expect(prepareTurnDiffBase(allocator, testing.io, "", 1, 1, &sha_buf) == null);
    try testing.expect(prepareTurnDiffBase(allocator, testing.io, ".zig-cache/tmp/faku-turn-diff-missing", 1, 1, &sha_buf) == null);

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [256]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, ".zig-cache/tmp/{s}/turn-diff-none", .{tmp.sub_path[0..]});
    const head = try initTestRepo(allocator, testing.io, path);
    defer allocator.free(head);
    try testing.expect(prepareTurnDiffBase(allocator, testing.io, path, 1, 1, &sha_buf) == null);
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

test "captureTurnEnd writes turn-n and does not write turn-start" {
    const testing = std.testing;
    const allocator = testing.allocator;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [256]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, ".zig-cache/tmp/{s}/turn-end", .{tmp.sub_path[0..]});
    const head = try initTestRepo(allocator, testing.io, path);
    defer allocator.free(head);

    var sha_buf: [rewind.stored_sha_len]u8 = undefined;
    const snap = captureWorktreeCommit(allocator, testing.io, path, &sha_buf) orelse return error.MissingSnapshot;
    try testing.expect(captureTurnEnd(allocator, testing.io, path, 12, 4, snap));

    var end_buf: [max_faku_ref_name]u8 = undefined;
    const end_ref = formatFakuSessionTurnRef(&end_buf, 12, 4) orelse return error.MissingFakuRef;
    try testing.expectEqualStrings("refs/faku/session-12-turn-4", end_ref);
    try testing.expect(hasFakuRef(allocator, testing.io, path, end_ref));
    const end_parsed = try runGitCapture(allocator, testing.io, &.{ "git", "-C", path, "rev-parse", end_ref });
    defer allocator.free(end_parsed);
    try testing.expectEqualStrings(snap, std.mem.trim(u8, end_parsed, " \r\n\t"));

    var start_buf: [max_faku_ref_name]u8 = undefined;
    const start_ref = formatFakuSessionTurnStartRef(&start_buf, 12, 4) orelse return error.MissingFakuRef;
    try testing.expect(!hasFakuRef(allocator, testing.io, path, start_ref));

    var baseline_buf: [max_faku_ref_name]u8 = undefined;
    const baseline = formatFakuSessionTurnRef(&baseline_buf, 12, 3) orelse return error.MissingFakuRef;
    try testing.expect(!hasFakuRef(allocator, testing.io, path, baseline));

    try testing.expect(!captureTurnEnd(allocator, testing.io, path, 12, 4, "not-a-sha"));
    try testing.expect(!captureTurnEnd(allocator, testing.io, "", 12, 4, snap));
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

fn parentCount(line: []const u8) usize {
    var n: usize = 0;
    var it = std.mem.tokenizeScalar(u8, line, ' ');
    _ = it.next();
    while (it.next()) |_| n += 1;
    return n;
}

fn turnStartMetadataJson(message: []const u8) ?[]const u8 {
    var lines = std.mem.splitScalar(u8, message, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, " \r\t");
        if (std.mem.startsWith(u8, line, turn_start_metadata_prefix)) {
            return std.mem.trim(u8, line[turn_start_metadata_prefix.len..], " \r\t");
        }
    }
    return null;
}

fn parseTurnStartMetadata(allocator: std.mem.Allocator, message: []const u8) !std.json.Parsed(std.json.Value) {
    const json = turnStartMetadataJson(message) orelse return error.MissingMetadata;
    return std.json.parseFromSlice(std.json.Value, allocator, json, .{});
}

fn expectJsonString(value: std.json.Value, key: []const u8, expected: []const u8) !void {
    const item = value.object.get(key) orelse return error.MissingJsonKey;
    try std.testing.expectEqualStrings(expected, item.string);
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

fn initDivergedRepo(allocator: std.mem.Allocator, io: std.Io, path: []const u8) ![]u8 {
    const head = try initTestRepo(allocator, io, path);
    allocator.free(head);

    try writeRepoFile(io, path, "shared.txt", "shared\n");
    try runGitPlain(allocator, io, &.{ "git", "-C", path, "add", "shared.txt" });
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
        "baseline",
    });

    try runGitPlain(allocator, io, &.{ "git", "-C", path, "checkout", "-b", "feature" });
    try writeRepoFile(io, path, "feature-only.txt", "feature\n");
    try writeRepoFile(io, path, "target.txt", "feature baseline\n");
    try runGitPlain(allocator, io, &.{ "git", "-C", path, "add", "feature-only.txt", "target.txt" });
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
        "feature",
    });

    try runGitPlain(allocator, io, &.{ "git", "-C", path, "checkout", "--quiet", "-" });
    try writeRepoFile(io, path, "main-only.txt", "main\n");
    try runGitPlain(allocator, io, &.{ "git", "-C", path, "add", "main-only.txt" });
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
        "main",
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
