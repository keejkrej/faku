//! First-cut local + remote-tracking branch list, checkout, create,
//! safe delete, fetch, push, and New worktree… for the composer
//! project row.
//!
//! Native has no git/workspace effect. When the selected session has a
//! non-empty `project_path` that exists, Faku `fx.spawn`s
//! `git for-each-ref --format=%(refname)%00%(worktreepath) refs/heads refs/remotes`
//! through the same `/bin/sh -c` chdir workaround `fx ask` uses
//! (`fx_ask_chdir_script`). `%(refname)` (not `:short`) is required
//! so `refs/heads/feat/foo` is not confused with a remote.
//! `%(worktreepath)` marks a local head checked out in another
//! worktree: non-empty path that is not this session's ready
//! `git rev-parse --show-toplevel` (or, while that probe is empty,
//! the session `project_path` / list-probe cwd — `project_path` may
//! be a subdirectory of that worktree). Occupied locals stay in the
//! picker with a short label marker and are refused for checkout and
//! safe-delete. Remotes are never occupied. Empty `%(worktreepath)`
//! is not occupied. Ready toplevel compares `worktreepath` equal to
//! that root; otherwise today's path-prefix heuristic.
//! Checking out a listed local name one-shots `git checkout <name>`
//! with that name as its own argv slot — never interpolated into the
//! `-c` script. A listed remote-tracking name one-shots
//! `git checkout --track <name>` the same way (`--track` and the name
//! each their own slot; same checkout key band). New branch…
//! one-shots `git checkout -b <name>` from current HEAD. Delete
//! branch… one-shots `git branch -d <name>` for listed local heads
//! that are not occupied (safe delete; never `-D`; never `origin/…`).
//! Fetch… one-shots `git fetch --prune` (`--prune` its own argv
//! slot; never interpolated into the `-c` script). Push… is offered
//! only when Waku `can_push` would be true: ahead of `@{upstream}`,
//! or the ahead/behind probe failed / that name does not exist
//! and a remotes probe found at least one remote (first-push
//! `--set-upstream` path). Hidden while those probes are in flight
//! and when it resolved an upstream with ahead 0. Failed / empty
//! remotes on the no-upstream path hide Push…. Push… probes
//! `@{upstream}` and
//! one-shots `git push` when that name exists (`push` its own argv
//! slot). When there is no upstream it one-shots
//! `git push --set-upstream <remote> <branch>`
//! (`--set-upstream`, remote, and branch each their own argv slot;
//! remote prefers `origin` from `git remote`, else the first name).
//! Detached HEAD or no remotes set a short composer status and do
//! not spawn a push. New worktree… prefills the runtime-only card
//! from a prompt slug of the selected session title (empty /
//! non-ascii-only → `new-worktree`; user can still edit). Confirm
//! probes `git symbolic-ref --quiet --short refs/remotes/origin/HEAD`
//! (chdir script; no interpolation; key band 390+) then one-shots
//! `git worktree add -b faku/<name> <path>` with that default base
//! as its own trailing argv slot when one resolves (`-b`, the
//! branch, the path, and the optional base each their own slot;
//! `mkdir -p` of `~/.faku/worktrees/<nest>` via a fixed script and
//! the parent as an argv slot). `origin/<name>` prefers `<name>`
//! when that is a plausible branch; otherwise the whole
//! `origin/<name>` string when it is a safe argv. Failed / empty /
//! exit 1 falls back to the cached composer branch label
//! (`pushBranchFromLabel`, not a detached short SHA) and otherwise
//! omits the base (today's HEAD). Dest is
//! `~/.faku/worktrees/<16-hex of source common-dir or toplevel or project_path>/<name>`
//! (FNV-1a 64 of the ready `--git-common-dir` path, resolved to
//! absolute when git prints a relative path like `.git`, when that
//! probe finished, else the ready `show-toplevel` root, else the
//! probe cwd used for `git worktree add`; not a daemon UUID /
//! `{project_id}`). A taken dest
//! directory or listed local
//! `faku/<name>` skips to the next Waku candidate (`slug`,
//! `slug-2`, … `slug-8`; cap 8 because Native is one-shot, not
//! Waku's 100 + session-id hex). A failed `worktree add` retries
//! the next free candidate the same way. Exhausted candidates set
//! status and leave `project_path` alone. Success retargets the
//! selected session `project_path` to the dest actually used. Not
//! force, not daemon `WorkspaceOperation::Push` / `NewWorktree`,
//! not `InspectCommit` / `Commit`. Cap is 64 local heads plus 32
//! remote-tracking names that have no local counterpart (skip
//! symbolic `*/HEAD`), sorted lexicographically. Not Waku's daemon
//! `InspectBranches` picker, live watch, `waku/` prefix /
//! `~/.waku/worktrees/{project_id}` UUID nest, defer-until-Send
//! workspace mode, base-ref picker UI, prune-alone, stash, merge,
//! force delete, or Environment Summary. Composer Push… still
//! closes any open Commit… card; a push started from that card
//! keeps it open with in-dialog Pushing… until the push ends.
//! Leftovers: force / amend, daemon `WorkspaceOperation`.
//!
//! Spawn/line/exit orchestration lives here. Windows is skipped
//! (app.zon is macos/linux; no Windows spawn path).

const std = @import("std");
const builtin = @import("builtin");
const native_sdk = @import("native_sdk");
const main = @import("main.zig");
const git_branch = @import("git_branch.zig");
const git_dirty = @import("git_dirty.zig");
const git_numstat = @import("git_numstat.zig");
const git_ahead_behind = @import("git_ahead_behind.zig");
const git_remotes = @import("git_remotes.zig");
const git_toplevel = @import("git_toplevel.zig");
const git_common_dir = @import("git_common_dir.zig");
const file_mention = @import("file_mention.zig");

const Model = main.Model;
const Effects = main.Effects;
const writeFixed = main.writeFixed;

/// One-shot `refs/heads` + `refs/remotes` list. Distinct from
/// git_branch (200+), git_checkout (275+; also `--track`),
/// git_create (290+), git_dirty (300+), git_delete (320+),
/// git_fetch (340+), git_numstat (350+), git_push (360+),
/// git_worktree_add (370+), git_ahead_behind (380+),
/// git_worktree_base (390+), and file_mention (400+). Incremented
/// per refresh so a cancelled spawn cannot paint a later session.
pub const git_branch_list_key_first: u64 = 250;

/// One-shot `git checkout <name>` or `git checkout --track <name>`.
/// Distinct from the list family (250+), git_create (290+),
/// git_branch (200+), git_dirty (300+), git_delete (320+),
/// git_fetch (340+), git_numstat (350+), git_push (360+),
/// git_worktree_add (370+), git_ahead_behind (380+),
/// git_worktree_base (390+), and file_mention (400+).
pub const git_checkout_key_first: u64 = 275;

/// One-shot `git checkout -b <name>`. Distinct from list (250+),
/// checkout (275+), git_dirty (300+), git_delete (320+),
/// git_fetch (340+), git_numstat (350+), git_push (360+),
/// git_ahead_behind (380+), and file_mention (400+). Band is
/// 290+ (below dirty 300+).
pub const git_create_key_first: u64 = 290;

/// One-shot `git branch -d <name>`. Distinct from list (250+),
/// checkout (275+), create (290+), git_dirty (300+), git_fetch
/// (340+), git_numstat (350+), git_push (360+),
/// git_ahead_behind (380+), and file_mention (400+). Band is
/// 320+ (between dirty 300+ and fetch 340+).
pub const git_delete_key_first: u64 = 320;

/// One-shot `git fetch --prune`. Distinct from list (250+),
/// checkout (275+), create (290+), git_dirty (300+), git_delete
/// (320+), git_numstat (350+), git_push (360+),
/// git_ahead_behind (380+), and file_mention (400+). Band is
/// 340+ (between delete 320+ and numstat 350+).
pub const git_fetch_key_first: u64 = 340;

/// One-shot `git push` (bare or `--set-upstream`) plus the upstream /
/// show-current / remotes probes that choose the path. Distinct from
/// list (250+), checkout (275+), create (290+), git_dirty (300+),
/// git_delete (320+), git_fetch (340+), git_numstat (350+),
/// git_worktree_add (370+), git_ahead_behind (380+), and
/// file_mention (400+). Band is 360+ (between numstat 350+ and
/// worktree-add 370+). Incremented per spawn so a cancelled
/// push cannot paint a later session.
pub const git_push_key_first: u64 = 360;

/// Push… probe / push stages that share `git_push_key` (360+).
pub const GitPushPhase = enum(u8) {
    idle,
    upstream,
    show_current,
    remotes,
    push,
};

/// One-shot `git worktree add -b`. Distinct from list (250+),
/// checkout (275+), create (290+), git_dirty (300+), git_delete
/// (320+), git_fetch (340+), git_numstat (350+), git_push (360+),
/// git_ahead_behind (380+), git_worktree_base (390+), and
/// file_mention (400+). Band is 370+ (between push 360+ and
/// ahead-behind 380+). Incremented per spawn so a cancelled
/// worktree-add cannot paint a later session.
pub const git_worktree_add_key_first: u64 = 370;

/// One-shot `git symbolic-ref --quiet --short refs/remotes/origin/HEAD`
/// probe that chooses the New worktree… base ref. Distinct from
/// git_worktree_add (370+), git_ahead_behind (380+), and
/// file_mention (400+). Band is 390+ (between ahead-behind 380+
/// and file_mention 400+). Incremented per probe so a cancelled
/// spawn cannot drive a later add.
pub const git_worktree_base_key_first: u64 = 390;

pub const max_local_branches: usize = 64;
pub const max_remote_branches: usize = 32;
pub const max_listed_branches: usize = max_local_branches + max_remote_branches;
pub const checkout_failed_status = "Could not check out branch.";
pub const occupied_checkout_status = "Already checked out in another worktree.";
pub const occupied_picker_suffix = " (worktree)";
pub const create_failed_status = "Could not create branch.";
pub const delete_failed_status = "Could not delete branch.";
pub const fetch_failed_status = "Could not fetch.";
pub const push_failed_status = "Could not push.";
pub const worktree_add_failed_status = "Could not create worktree.";

pub const git_bin = git_branch.git_bin;
pub const git_for_each_ref_cmd = "for-each-ref";
pub const git_refname_format = "--format=%(refname)%00%(worktreepath)";
pub const git_heads_ref = "refs/heads";
pub const git_remotes_ref = "refs/remotes";
pub const git_heads_prefix = "refs/heads/";
pub const git_remotes_prefix = "refs/remotes/";
pub const git_checkout_cmd = "checkout";
pub const git_track_flag = "--track";
pub const git_create_b_flag = "-b";
pub const git_branch_cmd = git_branch.git_branch_cmd;
pub const git_delete_d_flag = "-d";
pub const git_fetch_cmd = "fetch";
pub const git_prune_flag = "--prune";
pub const git_push_cmd = "push";
pub const git_set_upstream_flag = "--set-upstream";
pub const git_remote_cmd = "remote";
pub const git_rev_parse_cmd = git_branch.git_rev_parse_cmd;
pub const git_abbrev_ref = "--abbrev-ref";
pub const git_symbolic_full_name = "--symbolic-full-name";
pub const git_upstream_rev = "@{upstream}";
pub const git_origin_remote = "origin";
pub const git_worktree_cmd = "worktree";
pub const git_worktree_add_cmd = "add";
pub const git_symbolic_ref_cmd = "symbolic-ref";
pub const git_quiet_flag = "--quiet";
pub const git_short_flag = "--short";
pub const git_origin_head_ref = "refs/remotes/origin/HEAD";
pub const worktree_branch_prefix = "faku/";
pub const worktree_parent_suffix = ".faku/worktrees";
pub const worktree_slug_default = "new-worktree";
pub const max_worktree_slug_bytes: usize = 48;
pub const max_worktree_slug_words: usize = 6;
/// Native one-shot cap: `slug`, `slug-2`, … `slug-8`. Not Waku's
/// 100-candidate loop or `{slug}-{8 hex of session_id}` fallback.
pub const max_worktree_candidates: u32 = 8;
/// 16 lowercase hex chars of FNV-1a 64 of the source `project_path`.
/// Not a daemon UUID / `{project_id}`.
pub const worktree_nest_key_len: usize = 16;
/// `mkdir -p` the parent (`$1`), then chdir to the repo (`$2`) and
/// exec the remaining argv. Parent, cwd, branch, and path stay
/// argv slots — never interpolated into this script.
pub const git_worktree_mkdir_chdir_script = "mkdir -p -- \"$1\" && cd -- \"$2\" && shift 2 && exec \"$@\"";
pub const sh_bin = git_branch.sh_bin;

const list_argv_len: usize = 10;
const checkout_argv_len: usize = 8;
const track_checkout_argv_len: usize = 9;
const create_argv_len: usize = 9;
const delete_argv_len: usize = 9;
const fetch_argv_len: usize = 8;
const push_argv_len: usize = 7;
const upstream_argv_len: usize = 10;
pub const remote_argv_len: usize = 7;
const show_current_argv_len: usize = 8;
const set_upstream_push_argv_len: usize = 10;
const worktree_add_no_base_argv_len: usize = 12;
const worktree_add_argv_len: usize = 13;
const worktree_base_argv_len: usize = 10;

pub const CachedBranch = struct {
    storage: [git_branch.max_git_branch]u8 = [_]u8{0} ** git_branch.max_git_branch,
    len: usize = 0,
    remote: bool = false,
    occupied: bool = false,

    pub fn text(self: *const CachedBranch) []const u8 {
        return self.storage[0..self.len];
    }

    pub fn set(self: *CachedBranch, name: []const u8, remote: bool, occupied: bool) void {
        writeFixed(&self.storage, &self.len, name);
        self.remote = remote;
        self.occupied = occupied and !remote;
    }
};

pub const ParsedRef = struct {
    name: []const u8,
    remote: bool,
    occupied: bool = false,
};

pub fn listArgvFor(cwd: []const u8, buf: *[list_argv_len][]const u8) []const []const u8 {
    buf.* = .{
        sh_bin,
        "-c",
        main.fx_ask_chdir_script,
        "sh",
        cwd,
        git_bin,
        git_for_each_ref_cmd,
        git_refname_format,
        git_heads_ref,
        git_remotes_ref,
    };
    return buf;
}

pub fn isGitBranchListArgv(argv: []const []const u8) bool {
    if (argv.len != list_argv_len) return false;
    if (!std.mem.eql(u8, argv[0], sh_bin)) return false;
    if (!std.mem.eql(u8, argv[1], "-c")) return false;
    if (!std.mem.eql(u8, argv[2], main.fx_ask_chdir_script)) return false;
    if (!std.mem.eql(u8, argv[5], git_bin)) return false;
    if (!std.mem.eql(u8, argv[6], git_for_each_ref_cmd)) return false;
    if (!std.mem.eql(u8, argv[7], git_refname_format)) return false;
    if (!std.mem.eql(u8, argv[8], git_heads_ref)) return false;
    return std.mem.eql(u8, argv[9], git_remotes_ref);
}

/// `git checkout <name>` as a trailing argv slot. Rejects names that
/// fail `isPlausibleBranchName` so a raw string never reaches the
/// shell script.
pub fn checkoutArgvFor(cwd: []const u8, name: []const u8, buf: *[checkout_argv_len][]const u8) ?[]const []const u8 {
    if (!git_branch.isPlausibleBranchName(name)) return null;
    buf.* = .{
        sh_bin,
        "-c",
        main.fx_ask_chdir_script,
        "sh",
        cwd,
        git_bin,
        git_checkout_cmd,
        name,
    };
    return buf;
}

pub fn isGitCheckoutArgv(argv: []const []const u8) bool {
    if (argv.len != checkout_argv_len) return false;
    if (!std.mem.eql(u8, argv[0], sh_bin)) return false;
    if (!std.mem.eql(u8, argv[1], "-c")) return false;
    if (!std.mem.eql(u8, argv[2], main.fx_ask_chdir_script)) return false;
    if (!std.mem.eql(u8, argv[5], git_bin)) return false;
    if (!std.mem.eql(u8, argv[6], git_checkout_cmd)) return false;
    return git_branch.isPlausibleBranchName(argv[7]);
}

/// `git checkout --track <name>` as trailing argv slots. Rejects names
/// that fail `isPlausibleBranchName` so a raw string never reaches the
/// shell script.
pub fn trackCheckoutArgvFor(cwd: []const u8, name: []const u8, buf: *[track_checkout_argv_len][]const u8) ?[]const []const u8 {
    if (!git_branch.isPlausibleBranchName(name)) return null;
    buf.* = .{
        sh_bin,
        "-c",
        main.fx_ask_chdir_script,
        "sh",
        cwd,
        git_bin,
        git_checkout_cmd,
        git_track_flag,
        name,
    };
    return buf;
}

pub fn isGitTrackCheckoutArgv(argv: []const []const u8) bool {
    if (argv.len != track_checkout_argv_len) return false;
    if (!std.mem.eql(u8, argv[0], sh_bin)) return false;
    if (!std.mem.eql(u8, argv[1], "-c")) return false;
    if (!std.mem.eql(u8, argv[2], main.fx_ask_chdir_script)) return false;
    if (!std.mem.eql(u8, argv[5], git_bin)) return false;
    if (!std.mem.eql(u8, argv[6], git_checkout_cmd)) return false;
    if (!std.mem.eql(u8, argv[7], git_track_flag)) return false;
    return git_branch.isPlausibleBranchName(argv[8]);
}

/// `git checkout -b <name>` with the name as a trailing argv slot.
/// Rejects names that fail `isPlausibleBranchName` so a raw string
/// never reaches the shell script.
pub fn createArgvFor(cwd: []const u8, name: []const u8, buf: *[create_argv_len][]const u8) ?[]const []const u8 {
    if (!git_branch.isPlausibleBranchName(name)) return null;
    buf.* = .{
        sh_bin,
        "-c",
        main.fx_ask_chdir_script,
        "sh",
        cwd,
        git_bin,
        git_checkout_cmd,
        git_create_b_flag,
        name,
    };
    return buf;
}

pub fn isGitCreateArgv(argv: []const []const u8) bool {
    if (argv.len != create_argv_len) return false;
    if (!std.mem.eql(u8, argv[0], sh_bin)) return false;
    if (!std.mem.eql(u8, argv[1], "-c")) return false;
    if (!std.mem.eql(u8, argv[2], main.fx_ask_chdir_script)) return false;
    if (!std.mem.eql(u8, argv[5], git_bin)) return false;
    if (!std.mem.eql(u8, argv[6], git_checkout_cmd)) return false;
    if (!std.mem.eql(u8, argv[7], git_create_b_flag)) return false;
    return git_branch.isPlausibleBranchName(argv[8]);
}

/// `git branch -d <name>` with the name as a trailing argv slot.
/// Rejects names that fail `isPlausibleBranchName` so a raw string
/// never reaches the shell script. Never emits `-D`.
pub fn deleteArgvFor(cwd: []const u8, name: []const u8, buf: *[delete_argv_len][]const u8) ?[]const []const u8 {
    if (!git_branch.isPlausibleBranchName(name)) return null;
    buf.* = .{
        sh_bin,
        "-c",
        main.fx_ask_chdir_script,
        "sh",
        cwd,
        git_bin,
        git_branch_cmd,
        git_delete_d_flag,
        name,
    };
    return buf;
}

pub fn isGitDeleteArgv(argv: []const []const u8) bool {
    if (argv.len != delete_argv_len) return false;
    if (!std.mem.eql(u8, argv[0], sh_bin)) return false;
    if (!std.mem.eql(u8, argv[1], "-c")) return false;
    if (!std.mem.eql(u8, argv[2], main.fx_ask_chdir_script)) return false;
    if (!std.mem.eql(u8, argv[5], git_bin)) return false;
    if (!std.mem.eql(u8, argv[6], git_branch_cmd)) return false;
    if (!std.mem.eql(u8, argv[7], git_delete_d_flag)) return false;
    return git_branch.isPlausibleBranchName(argv[8]);
}

/// `git fetch --prune` with `--prune` as its own argv slot — never
/// interpolated into the `-c` script.
pub fn fetchArgvFor(cwd: []const u8, buf: *[fetch_argv_len][]const u8) []const []const u8 {
    buf.* = .{
        sh_bin,
        "-c",
        main.fx_ask_chdir_script,
        "sh",
        cwd,
        git_bin,
        git_fetch_cmd,
        git_prune_flag,
    };
    return buf;
}

pub fn isGitFetchArgv(argv: []const []const u8) bool {
    if (argv.len != fetch_argv_len) return false;
    if (!std.mem.eql(u8, argv[0], sh_bin)) return false;
    if (!std.mem.eql(u8, argv[1], "-c")) return false;
    if (!std.mem.eql(u8, argv[2], main.fx_ask_chdir_script)) return false;
    if (!std.mem.eql(u8, argv[5], git_bin)) return false;
    if (!std.mem.eql(u8, argv[6], git_fetch_cmd)) return false;
    return std.mem.eql(u8, argv[7], git_prune_flag);
}

/// `git push` with no extra flags — `push` is its own argv slot,
/// never interpolated into the `-c` script. Not `--set-upstream`,
/// not `-u`, not `--force`, not `--tags`.
pub fn pushArgvFor(cwd: []const u8, buf: *[push_argv_len][]const u8) []const []const u8 {
    buf.* = .{
        sh_bin,
        "-c",
        main.fx_ask_chdir_script,
        "sh",
        cwd,
        git_bin,
        git_push_cmd,
    };
    return buf;
}

pub fn isGitPushArgv(argv: []const []const u8) bool {
    if (argv.len != push_argv_len) return false;
    if (!std.mem.eql(u8, argv[0], sh_bin)) return false;
    if (!std.mem.eql(u8, argv[1], "-c")) return false;
    if (!std.mem.eql(u8, argv[2], main.fx_ask_chdir_script)) return false;
    if (!std.mem.eql(u8, argv[5], git_bin)) return false;
    return std.mem.eql(u8, argv[6], git_push_cmd);
}

/// `git rev-parse --abbrev-ref --symbolic-full-name @{upstream}`.
/// `@{upstream}` is its own argv slot — never interpolated into the
/// `-c` script. Missing / failed stdout means no upstream.
pub fn upstreamArgvFor(cwd: []const u8, buf: *[upstream_argv_len][]const u8) []const []const u8 {
    buf.* = .{
        sh_bin,
        "-c",
        main.fx_ask_chdir_script,
        "sh",
        cwd,
        git_bin,
        git_rev_parse_cmd,
        git_abbrev_ref,
        git_symbolic_full_name,
        git_upstream_rev,
    };
    return buf;
}

pub fn isGitUpstreamArgv(argv: []const []const u8) bool {
    if (argv.len != upstream_argv_len) return false;
    if (!std.mem.eql(u8, argv[0], sh_bin)) return false;
    if (!std.mem.eql(u8, argv[1], "-c")) return false;
    if (!std.mem.eql(u8, argv[2], main.fx_ask_chdir_script)) return false;
    if (!std.mem.eql(u8, argv[5], git_bin)) return false;
    if (!std.mem.eql(u8, argv[6], git_rev_parse_cmd)) return false;
    if (!std.mem.eql(u8, argv[7], git_abbrev_ref)) return false;
    if (!std.mem.eql(u8, argv[8], git_symbolic_full_name)) return false;
    return std.mem.eql(u8, argv[9], git_upstream_rev);
}

/// `git remote` with `remote` as its own argv slot.
pub fn remoteArgvFor(cwd: []const u8, buf: *[remote_argv_len][]const u8) []const []const u8 {
    buf.* = .{
        sh_bin,
        "-c",
        main.fx_ask_chdir_script,
        "sh",
        cwd,
        git_bin,
        git_remote_cmd,
    };
    return buf;
}

pub fn isGitRemoteArgv(argv: []const []const u8) bool {
    if (argv.len != remote_argv_len) return false;
    if (!std.mem.eql(u8, argv[0], sh_bin)) return false;
    if (!std.mem.eql(u8, argv[1], "-c")) return false;
    if (!std.mem.eql(u8, argv[2], main.fx_ask_chdir_script)) return false;
    if (!std.mem.eql(u8, argv[5], git_bin)) return false;
    return std.mem.eql(u8, argv[6], git_remote_cmd);
}

/// `git push --set-upstream <remote> <branch>` — flag, remote, and
/// branch each their own argv slot, never interpolated into the `-c`
/// script. Rejects implausible names so a raw string never reaches
/// the shell script. Not `-u`, not `--force`.
pub fn setUpstreamPushArgvFor(
    cwd: []const u8,
    remote: []const u8,
    branch: []const u8,
    buf: *[set_upstream_push_argv_len][]const u8,
) ?[]const []const u8 {
    if (!isPlausibleRemoteName(remote)) return null;
    if (!git_branch.isPlausibleBranchName(branch)) return null;
    buf.* = .{
        sh_bin,
        "-c",
        main.fx_ask_chdir_script,
        "sh",
        cwd,
        git_bin,
        git_push_cmd,
        git_set_upstream_flag,
        remote,
        branch,
    };
    return buf;
}

pub fn isGitSetUpstreamPushArgv(argv: []const []const u8) bool {
    if (argv.len != set_upstream_push_argv_len) return false;
    if (!std.mem.eql(u8, argv[0], sh_bin)) return false;
    if (!std.mem.eql(u8, argv[1], "-c")) return false;
    if (!std.mem.eql(u8, argv[2], main.fx_ask_chdir_script)) return false;
    if (!std.mem.eql(u8, argv[5], git_bin)) return false;
    if (!std.mem.eql(u8, argv[6], git_push_cmd)) return false;
    if (!std.mem.eql(u8, argv[7], git_set_upstream_flag)) return false;
    if (!isPlausibleRemoteName(argv[8])) return false;
    return git_branch.isPlausibleBranchName(argv[9]);
}

/// Non-empty first stdout line means `@{upstream}` resolved.
pub fn stdoutHasUpstream(raw: []const u8) bool {
    return git_branch.firstStdoutBranch(raw).len > 0;
}

/// Remote names use the same conservative check-ref-format subset as
/// local heads. `origin` is the Waku-preferred default.
pub fn isPlausibleRemoteName(name: []const u8) bool {
    return git_branch.isPlausibleBranchName(name);
}

/// Prefer `origin` when listed; otherwise the first plausible name.
/// Slices alias `raw`.
pub fn pickRemoteName(raw: []const u8) []const u8 {
    var chosen: []const u8 = "";
    var it = std.mem.splitScalar(u8, raw, '\n');
    while (it.next()) |line| {
        const name = std.mem.trim(u8, line, " \t\r\n");
        if (!isPlausibleRemoteName(name)) continue;
        if (chosen.len == 0) chosen = name;
        if (std.mem.eql(u8, name, git_origin_remote)) return name;
    }
    return chosen;
}

/// Cached composer label is reusable when it is a real branch name,
/// not a detached short SHA. Otherwise Push… probes `--show-current`.
pub fn pushBranchFromLabel(label: []const u8) ?[]const u8 {
    if (!git_branch.isPlausibleBranchName(label)) return null;
    if (git_branch.isPlausibleShortSha(label)) return null;
    return label;
}

/// Prompt slug for New worktree… (pure, no I/O). Lowercase ASCII,
/// split on non-ascii-alnum, take six words, join with `-`,
/// truncate to 48 bytes. Empty → `new-worktree`. Same rules as
/// Waku's `worktree_slug`; not a collision suffix and not a
/// `{project_id}` nest.
pub fn worktreeSlug(prompt: []const u8, buf: []u8) []const u8 {
    var out_len: usize = 0;
    var words: usize = 0;
    var in_word = false;
    for (prompt) |c| {
        if (std.ascii.isAlphanumeric(c)) {
            if (!in_word) {
                if (words >= max_worktree_slug_words) break;
                if (words > 0) {
                    if (out_len >= max_worktree_slug_bytes) break;
                    if (out_len < buf.len) {
                        buf[out_len] = '-';
                        out_len += 1;
                    } else break;
                }
                words += 1;
                in_word = true;
            }
            if (out_len >= max_worktree_slug_bytes) break;
            if (out_len >= buf.len) break;
            buf[out_len] = std.ascii.toLower(c);
            out_len += 1;
        } else {
            in_word = false;
        }
    }
    if (out_len == 0) return worktree_slug_default;
    return buf[0..out_len];
}

/// First stdout line of `symbolic-ref --quiet --short refs/remotes/origin/HEAD`.
/// `origin/<name>` prefers `<name>` when that is a plausible branch;
/// otherwise the whole line when it is a safe argv. Empty / unsafe
/// is a miss so the caller can fall back to the cached label.
pub fn worktreeBaseFromSymbolicRef(raw: []const u8) ?[]const u8 {
    const line = git_branch.firstStdoutBranch(raw);
    if (line.len == 0) return null;
    if (std.mem.startsWith(u8, line, "origin/")) {
        const local = line["origin/".len..];
        if (git_branch.isPlausibleBranchName(local)) return local;
    }
    if (git_branch.isPlausibleBranchName(line)) return line;
    return null;
}

/// `git symbolic-ref --quiet --short refs/remotes/origin/HEAD` as
/// trailing argv slots — never interpolated into the `-c` script.
pub fn worktreeBaseArgvFor(cwd: []const u8, buf: *[worktree_base_argv_len][]const u8) []const []const u8 {
    buf.* = .{
        sh_bin,
        "-c",
        main.fx_ask_chdir_script,
        "sh",
        cwd,
        git_bin,
        git_symbolic_ref_cmd,
        git_quiet_flag,
        git_short_flag,
        git_origin_head_ref,
    };
    return buf;
}

pub fn isGitWorktreeBaseArgv(argv: []const []const u8) bool {
    if (argv.len != worktree_base_argv_len) return false;
    if (!std.mem.eql(u8, argv[0], sh_bin)) return false;
    if (!std.mem.eql(u8, argv[1], "-c")) return false;
    if (!std.mem.eql(u8, argv[2], main.fx_ask_chdir_script)) return false;
    if (!std.mem.eql(u8, argv[5], git_bin)) return false;
    if (!std.mem.eql(u8, argv[6], git_symbolic_ref_cmd)) return false;
    if (!std.mem.eql(u8, argv[7], git_quiet_flag)) return false;
    if (!std.mem.eql(u8, argv[8], git_short_flag)) return false;
    return std.mem.eql(u8, argv[9], git_origin_head_ref);
}

/// Trim + `isPlausibleBranchName`, and refuse `/` so the dest is one
/// directory under the per-project nest. Empty / unsafe names stay
/// refused — this is not a rewrite sanitizer.
pub fn sanitizeWorktreeName(raw: []const u8) ?[]const u8 {
    const name = std.mem.trim(u8, raw, " \t\r\n");
    if (!git_branch.isPlausibleBranchName(name)) return null;
    if (std.mem.indexOfScalar(u8, name, '/') != null) return null;
    if (worktree_branch_prefix.len + name.len > git_branch.max_git_branch) return null;
    return name;
}

pub fn worktreeBranchName(name: []const u8, buf: []u8) ?[]const u8 {
    const sanitized = sanitizeWorktreeName(name) orelse return null;
    return std.fmt.bufPrint(buf, "{s}{s}", .{ worktree_branch_prefix, sanitized }) catch null;
}

/// 16 lowercase hex chars of FNV-1a 64 of the trimmed source
/// `project_path` (the cwd used for `git worktree add`). Empty /
/// `..` / NUL after trim → null. Relative paths are allowed.
/// Prefer `worktreeNestKeyFor` when a ready `--git-common-dir`
/// (else `show-toplevel`) should win.
pub fn worktreeNestKey(project_path: []const u8, buf: []u8) ?[]const u8 {
    return worktreeNestKeyFor(project_path, buf, null);
}

/// Same FNV nest as `worktreeNestKey`, hashing the ready
/// `--git-common-dir` path when that probe finished so linked
/// worktrees of the same repo share `~/.faku/worktrees/<nest>/`.
/// Falls back to ready `show-toplevel`, then `project_path`.
pub fn worktreeNestKeyFor(project_path: []const u8, buf: []u8, model: ?*const Model) ?[]const u8 {
    const source = blk: {
        if (model) |m| {
            const common = git_common_dir.readyPath(m);
            if (common.len > 0) break :blk common;
            const top = git_toplevel.readyPath(m);
            if (top.len > 0) break :blk top;
        }
        break :blk project_path;
    };
    const trimmed = std.mem.trim(u8, source, " \t\r\n");
    if (trimmed.len == 0) return null;
    if (std.mem.indexOf(u8, trimmed, "..") != null) return null;
    if (std.mem.indexOfScalar(u8, trimmed, 0) != null) return null;
    if (buf.len < worktree_nest_key_len) return null;
    const digest = std.hash.Fnv1a_64.hash(trimmed);
    return std.fmt.bufPrint(buf, "{x:0>16}", .{digest}) catch null;
}

/// `{home}/.faku/worktrees/<nest>` — the mkdir -p parent. Nest is
/// `worktreeNestKey(project_path)`. Root suffix stays
/// `worktree_parent_suffix`.
pub fn worktreeParentPath(home: []const u8, project_path: []const u8, buf: []u8) ?[]const u8 {
    return worktreeParentPathFor(home, project_path, buf, null);
}

pub fn worktreeParentPathFor(home: []const u8, project_path: []const u8, buf: []u8, model: ?*const Model) ?[]const u8 {
    const trimmed = std.mem.trim(u8, home, " \t\r\n");
    if (trimmed.len == 0) return null;
    if (trimmed[0] != '/') return null;
    var nest_buf: [worktree_nest_key_len]u8 = undefined;
    const nest = worktreeNestKeyFor(project_path, nest_buf[0..], model) orelse return null;
    return std.fmt.bufPrint(buf, "{s}/{s}/{s}", .{ trimmed, worktree_parent_suffix, nest }) catch null;
}

pub fn worktreeDestPath(home: []const u8, project_path: []const u8, name: []const u8, buf: []u8) ?[]const u8 {
    return worktreeDestPathFor(home, project_path, name, buf, null);
}

pub fn worktreeDestPathFor(home: []const u8, project_path: []const u8, name: []const u8, buf: []u8, model: ?*const Model) ?[]const u8 {
    const sanitized = sanitizeWorktreeName(name) orelse return null;
    const parent = worktreeParentPathFor(home, project_path, buf, model) orelse return null;
    if (parent.len + 1 + sanitized.len > buf.len) return null;
    buf[parent.len] = '/';
    @memcpy(buf[parent.len + 1 ..][0..sanitized.len], sanitized);
    return buf[0 .. parent.len + 1 + sanitized.len];
}

/// Waku `candidate_name`: index 0 is `slug`; else `{slug}-{index+1}`
/// so `slug`, `slug-2`, `slug-3`, … Cap is `max_worktree_candidates`
/// (`slug` … `slug-8`). Not a session-id hex fallback.
pub fn worktreeCandidateName(slug: []const u8, index: u32, buf: []u8) ?[]const u8 {
    if (index >= max_worktree_candidates) return null;
    const sanitized = sanitizeWorktreeName(slug) orelse return null;
    if (index == 0) {
        if (sanitized.len > buf.len) return null;
        @memcpy(buf[0..sanitized.len], sanitized);
        return buf[0..sanitized.len];
    }
    return std.fmt.bufPrint(buf, "{s}-{d}", .{ sanitized, index + 1 }) catch null;
}

/// Waku occupancy: a candidate is taken when the dest exists or the
/// local `faku/<name>` head exists. Callers supply those facts (dest
/// directory and last `for-each-ref` list); this is not a live
/// `show-ref` spawn.
pub fn worktreeCandidateOccupied(path_exists: bool, local_branch_exists: bool) bool {
    return path_exists or local_branch_exists;
}

pub fn isSafeWorktreePath(path: []const u8) bool {
    if (path.len == 0 or path.len > main.max_project_path) return false;
    if (path[0] != '/') return false;
    if (std.mem.indexOf(u8, path, "..") != null) return false;
    if (std.mem.indexOfScalar(u8, path, 0) != null) return false;
    return true;
}

/// `mkdir -p -- <parent> && cd -- <cwd> && git worktree add -b <branch> <path> [base]`.
/// Parent, cwd, branch, path, and optional base are argv slots.
/// Empty `base` omits the trailing slot (today's HEAD). Rejects
/// unsafe names so a raw string never reaches the shell script.
pub fn worktreeAddArgvFor(
    cwd: []const u8,
    parent: []const u8,
    branch: []const u8,
    path: []const u8,
    base: []const u8,
    buf: *[worktree_add_argv_len][]const u8,
) ?[]const []const u8 {
    if (cwd.len == 0 or !isSafeWorktreePath(parent) or !isSafeWorktreePath(path)) return null;
    if (!git_branch.isPlausibleBranchName(branch)) return null;
    if (!std.mem.startsWith(u8, branch, worktree_branch_prefix)) return null;
    if (sanitizeWorktreeName(branch[worktree_branch_prefix.len..]) == null) return null;
    if (!std.mem.startsWith(u8, path, parent)) return null;
    if (base.len > 0 and !git_branch.isPlausibleBranchName(base)) return null;
    buf[0] = sh_bin;
    buf[1] = "-c";
    buf[2] = git_worktree_mkdir_chdir_script;
    buf[3] = "sh";
    buf[4] = parent;
    buf[5] = cwd;
    buf[6] = git_bin;
    buf[7] = git_worktree_cmd;
    buf[8] = git_worktree_add_cmd;
    buf[9] = git_create_b_flag;
    buf[10] = branch;
    buf[11] = path;
    if (base.len == 0) return buf[0..worktree_add_no_base_argv_len];
    buf[12] = base;
    return buf[0..worktree_add_argv_len];
}

pub fn isGitWorktreeAddArgv(argv: []const []const u8) bool {
    if (argv.len != worktree_add_no_base_argv_len and argv.len != worktree_add_argv_len) return false;
    if (!std.mem.eql(u8, argv[0], sh_bin)) return false;
    if (!std.mem.eql(u8, argv[1], "-c")) return false;
    if (!std.mem.eql(u8, argv[2], git_worktree_mkdir_chdir_script)) return false;
    if (!isSafeWorktreePath(argv[4])) return false;
    if (argv[5].len == 0) return false;
    if (!std.mem.eql(u8, argv[6], git_bin)) return false;
    if (!std.mem.eql(u8, argv[7], git_worktree_cmd)) return false;
    if (!std.mem.eql(u8, argv[8], git_worktree_add_cmd)) return false;
    if (!std.mem.eql(u8, argv[9], git_create_b_flag)) return false;
    if (!git_branch.isPlausibleBranchName(argv[10])) return false;
    if (!std.mem.startsWith(u8, argv[10], worktree_branch_prefix)) return false;
    if (sanitizeWorktreeName(argv[10][worktree_branch_prefix.len..]) == null) return false;
    if (!isSafeWorktreePath(argv[11])) return false;
    if (argv.len == worktree_add_argv_len) return git_branch.isPlausibleBranchName(argv[12]);
    return true;
}

fn parsedRefLessThan(_: void, a: ParsedRef, b: ParsedRef) bool {
    return std.mem.lessThan(u8, a.name, b.name);
}

fn isRemoteHeadName(name: []const u8) bool {
    return std.mem.eql(u8, name, "HEAD") or std.mem.endsWith(u8, name, "/HEAD");
}

/// Short name after the first path segment (`origin/feat` → `feat`).
pub fn remoteLocalCounterpart(name: []const u8) []const u8 {
    const slash = std.mem.indexOfScalar(u8, name, '/') orelse return "";
    return name[slash + 1 ..];
}

/// Split one `for-each-ref` stdout line into `refname` and
/// `worktreepath`. A missing NUL (older git / missing field) is a
/// valid refname with empty worktreepath.
pub fn splitRefWorktreeLine(line: []const u8) struct { refname: []const u8, worktreepath: []const u8 } {
    if (std.mem.indexOfScalar(u8, line, 0)) |nul| {
        return .{ .refname = line[0..nul], .worktreepath = line[nul + 1 ..] };
    }
    return .{ .refname = line, .worktreepath = "" };
}

/// This-worktree path-prefix heuristic: `worktreepath` equals
/// `project_path`, or `project_path` starts with `worktreepath` + "/".
/// Prefer `isThisWorktreePathFor` when a ready `show-toplevel` should
/// win (worktreepath equal to that root).
pub fn isThisWorktreePath(worktreepath: []const u8, project_path: []const u8) bool {
    return isThisWorktreePathFor(worktreepath, project_path, null);
}

pub fn isThisWorktreePathFor(worktreepath: []const u8, project_path: []const u8, model: ?*const Model) bool {
    const wt = std.mem.trim(u8, worktreepath, " \t\r\n");
    if (model) |m| {
        const top = std.mem.trim(u8, git_toplevel.readyPath(m), " \t\r\n");
        if (top.len > 0) return wt.len > 0 and std.mem.eql(u8, wt, top);
    }
    const proj = std.mem.trim(u8, project_path, " \t\r\n");
    if (wt.len == 0 or proj.len == 0) return false;
    if (std.mem.eql(u8, wt, proj)) return true;
    return proj.len > wt.len and std.mem.startsWith(u8, proj, wt) and proj[wt.len] == '/';
}

/// Local heads only. Non-empty trimmed worktreepath that is not this
/// worktree. Remotes and empty paths are never occupied.
pub fn localHeadOccupied(remote: bool, worktreepath: []const u8, project_path: []const u8) bool {
    return localHeadOccupiedFor(remote, worktreepath, project_path, null);
}

pub fn localHeadOccupiedFor(remote: bool, worktreepath: []const u8, project_path: []const u8, model: ?*const Model) bool {
    if (remote) return false;
    const wt = std.mem.trim(u8, worktreepath, " \t\r\n");
    if (wt.len == 0) return false;
    return !isThisWorktreePathFor(wt, project_path, model);
}

/// Classify one `%(refname)` (NUL field already split off). Locals
/// are `refs/heads/<name>`; remotes are `refs/remotes/<name>` minus
/// symbolic `*/HEAD`.
pub fn classifyRefname(raw: []const u8) ?ParsedRef {
    const trimmed = std.mem.trim(u8, raw, " \t\r\n");
    if (std.mem.startsWith(u8, trimmed, git_heads_prefix)) {
        const name = trimmed[git_heads_prefix.len..];
        if (!git_branch.isPlausibleBranchName(name)) return null;
        return .{ .name = name, .remote = false };
    }
    if (std.mem.startsWith(u8, trimmed, git_remotes_prefix)) {
        const name = trimmed[git_remotes_prefix.len..];
        if (isRemoteHeadName(name)) return null;
        if (!git_branch.isPlausibleBranchName(name)) return null;
        return .{ .name = name, .remote = true };
    }
    return null;
}

fn parsedRefNameEquals(refs: []const ParsedRef, name: []const u8) bool {
    for (refs) |item| {
        if (std.mem.eql(u8, item.name, name)) return true;
    }
    return false;
}

fn parseRefLine(line: []const u8, project_path: []const u8, model: ?*const Model) ?ParsedRef {
    const split = splitRefWorktreeLine(line);
    var parsed = classifyRefname(split.refname) orelse return null;
    parsed.occupied = localHeadOccupiedFor(parsed.remote, split.worktreepath, project_path, model);
    return parsed;
}

fn occupancyCwd(model: *const Model) []const u8 {
    const probed = model.git_branch_list_probe_path_storage[0..model.git_branch_list_probe_path_len];
    if (probed.len > 0) return probed;
    return model.selectedProjectPath();
}

/// Parse `%(refname)%00%(worktreepath)` lines. Locals first (cap 64),
/// then remotes that are not `*/HEAD` and whose local counterpart is
/// not already in this batch (cap 32). Occupancy is local-only via
/// the ready toplevel when that probe finished, else the
/// `project_path` / probe-cwd heuristic. Skip empty / implausible
/// names. Then sort by display name. Slices alias `raw`.
pub fn collectStdoutRefs(raw: []const u8, project_path: []const u8, out: []ParsedRef) usize {
    return collectStdoutRefsFor(raw, project_path, out, null);
}

pub fn collectStdoutRefsFor(raw: []const u8, project_path: []const u8, out: []ParsedRef, model: ?*const Model) usize {
    var n: usize = 0;
    var local_n: usize = 0;
    var it = std.mem.splitScalar(u8, raw, '\n');
    while (it.next()) |line| {
        if (n >= out.len or local_n >= max_local_branches) break;
        const parsed = parseRefLine(line, project_path, model) orelse continue;
        if (parsed.remote) continue;
        if (parsedRefNameEquals(out[0..n], parsed.name)) continue;
        out[n] = parsed;
        n += 1;
        local_n += 1;
    }
    var remote_n: usize = 0;
    it = std.mem.splitScalar(u8, raw, '\n');
    while (it.next()) |line| {
        if (n >= out.len or remote_n >= max_remote_branches) break;
        const parsed = parseRefLine(line, project_path, model) orelse continue;
        if (!parsed.remote) continue;
        const counterpart = remoteLocalCounterpart(parsed.name);
        if (counterpart.len > 0 and parsedRefNameEquals(out[0..local_n], counterpart)) continue;
        if (parsedRefNameEquals(out[0..n], parsed.name)) continue;
        out[n] = parsed;
        n += 1;
        remote_n += 1;
    }
    std.mem.sort(ParsedRef, out[0..n], {}, parsedRefLessThan);
    return n;
}

fn cachedBranchLessThan(_: void, a: CachedBranch, b: CachedBranch) bool {
    return std.mem.lessThan(u8, a.text(), b.text());
}

pub fn sortListedBranches(model: *Model) void {
    const n = model.git_branch_list_count;
    if (n < 2) return;
    std.mem.sort(CachedBranch, model.git_branch_list_store[0..n], {}, cachedBranchLessThan);
}

pub fn listedBranch(model: *const Model, index: usize) []const u8 {
    if (index >= model.git_branch_list_count) return "";
    return model.git_branch_list_store[index].text();
}

pub fn listedBranchIsRemote(model: *const Model, index: usize) bool {
    if (index >= model.git_branch_list_count) return false;
    return model.git_branch_list_store[index].remote;
}

pub fn listedBranchIsOccupied(model: *const Model, index: usize) bool {
    if (index >= model.git_branch_list_count) return false;
    const item = model.git_branch_list_store[index];
    return item.occupied and !item.remote;
}

pub fn listedLocalNameIsOccupied(model: *const Model, name: []const u8) bool {
    var i: usize = 0;
    while (i < model.git_branch_list_count) : (i += 1) {
        if (listedBranchIsRemote(model, i)) continue;
        if (std.mem.eql(u8, listedBranch(model, i), name)) return listedBranchIsOccupied(model, i);
    }
    return false;
}

pub fn hasListedBranches(model: *const Model) bool {
    return model.git_branch_list_count > 0;
}

pub fn canPickGitBranch(model: *const Model) bool {
    return git_branch.hasGitBranch(model) or hasListedBranches(model);
}

fn listedKindCount(model: *const Model, remote: bool) usize {
    var n: usize = 0;
    var i: usize = 0;
    while (i < model.git_branch_list_count) : (i += 1) {
        if (model.git_branch_list_store[i].remote == remote) n += 1;
    }
    return n;
}

fn hasListedLocalName(model: *const Model, name: []const u8) bool {
    var i: usize = 0;
    while (i < model.git_branch_list_count) : (i += 1) {
        if (model.git_branch_list_store[i].remote) continue;
        if (std.mem.eql(u8, listedBranch(model, i), name)) return true;
    }
    return false;
}

pub fn isListedRemoteName(model: *const Model, name: []const u8) bool {
    var i: usize = 0;
    while (i < model.git_branch_list_count) : (i += 1) {
        if (!model.git_branch_list_store[i].remote) continue;
        if (std.mem.eql(u8, listedBranch(model, i), name)) return true;
    }
    return false;
}

/// True when at least one listed local head is not the current branch
/// and is not occupied in another worktree. Remote-tracking rows are
/// never deletable. Detached HEAD (sha label) treats every unoccupied
/// listed local head as deletable.
pub fn canDeleteGitBranch(model: *const Model) bool {
    const current = git_branch.gitBranchLabel(model);
    var i: usize = 0;
    while (i < model.git_branch_list_count) : (i += 1) {
        if (listedBranchIsRemote(model, i)) continue;
        if (listedBranchIsOccupied(model, i)) continue;
        const name = listedBranch(model, i);
        if (!git_branch.isPlausibleBranchName(name)) continue;
        if (std.mem.eql(u8, name, current)) continue;
        return true;
    }
    return false;
}

pub fn gitBranchDeleteLabel(model: *const Model) []const u8 {
    return model.git_branch_delete_storage[0..model.git_branch_delete_len];
}

fn isListedNonCurrent(model: *const Model, name: []const u8) bool {
    if (!git_branch.isPlausibleBranchName(name)) return false;
    if (std.mem.eql(u8, name, git_branch.gitBranchLabel(model))) return false;
    var i: usize = 0;
    while (i < model.git_branch_list_count) : (i += 1) {
        if (listedBranchIsRemote(model, i)) continue;
        if (listedBranchIsOccupied(model, i)) continue;
        if (std.mem.eql(u8, listedBranch(model, i), name)) return true;
    }
    return false;
}

pub fn clearListedBranches(model: *Model) void {
    model.git_branch_list_count = 0;
}

pub fn closePicker(model: *Model) void {
    model.git_branch_picker_open = false;
}

pub fn closeCreate(model: *Model) void {
    model.git_branch_create_active = false;
    model.git_branch_create_buffer.clear();
}

pub fn closeWorktreeCreate(model: *Model) void {
    model.git_worktree_create_active = false;
    model.git_worktree_create_buffer.clear();
}

fn closeCommitCard(model: *Model) void {
    model.git_commit_active = false;
    model.git_commit_buffer.clear();
    model.git_commit_numstat_key = 0;
    model.git_commit_numstat_additions = 0;
    model.git_commit_numstat_deletions = 0;
    model.git_commit_numstat_label_len = 0;
    model.git_commit_generate_key = 0;
    model.git_commit_generate_stdout_len = 0;
}

fn dropCommitSnapshot(model: *Model, fx: *Effects) void {
    if (model.git_commit_numstat_key != 0) {
        fx.cancel(model.git_commit_numstat_key);
        model.git_commit_numstat_key = 0;
    }
    model.git_commit_numstat_additions = 0;
    model.git_commit_numstat_deletions = 0;
    model.git_commit_numstat_label_len = 0;
}

/// Esc / Cancel: close the card and drop an in-flight base probe so a
/// late exit cannot spawn add. Distinct from `closeWorktreeCreate`,
/// which only hides the card (Push… / Fetch… still no-op via
/// `gitMutationInFlight` while the probe or add is live).
pub fn dismissWorktreeCreate(model: *Model, fx: *Effects) void {
    cancelWorktreeBase(model, fx);
    closeWorktreeCreate(model);
}

pub fn closeDelete(model: *Model) void {
    model.git_branch_delete_active = false;
    model.git_branch_delete_picker_open = false;
    model.git_branch_delete_len = 0;
}

/// Dismiss the select list and open the runtime-only create card.
/// Draft name is not persisted.
pub fn startCreate(model: *Model) void {
    closePicker(model);
    closeDelete(model);
    closeWorktreeCreate(model);
    closeCommitCard(model);
    model.closeProjectEdit();
    model.git_branch_create_active = true;
}

/// Dismiss the select list and open the runtime-only New worktree…
/// card. Prefills a prompt slug from the selected session title
/// (`new-worktree` when that slugs empty). Draft name is not
/// persisted; the user can still edit.
pub fn startWorktreeCreate(model: *Model) void {
    closePicker(model);
    closeCreate(model);
    closeDelete(model);
    closeWorktreeCreate(model);
    closeCommitCard(model);
    model.closeProjectEdit();
    model.git_worktree_create_active = true;
    const title = if (model.sessionByIdConst(model.selected)) |session| session.title() else "";
    var slug_buf: [max_worktree_slug_bytes]u8 = undefined;
    const slug = worktreeSlug(title, slug_buf[0..]);
    model.git_worktree_create_buffer.apply(.{ .insert_text = slug });
}

/// Dismiss the select list and open the runtime-only delete card of
/// non-current, unoccupied listed local heads. Selected name is not
/// persisted.
pub fn startDelete(model: *Model) void {
    closePicker(model);
    closeCreate(model);
    closeWorktreeCreate(model);
    closeCommitCard(model);
    model.closeProjectEdit();
    model.git_branch_delete_active = true;
    model.git_branch_delete_picker_open = false;
    model.git_branch_delete_len = 0;
}

pub fn closeDeletePicker(model: *Model) void {
    model.git_branch_delete_picker_open = false;
}

pub fn toggleDeletePicker(model: *Model) void {
    if (!model.git_branch_delete_active) {
        model.git_branch_delete_picker_open = false;
        return;
    }
    model.git_branch_delete_picker_open = !model.git_branch_delete_picker_open;
}

/// Remember a listed non-current name on the delete card. Does not spawn.
pub fn pickDeleteName(model: *Model, name: []const u8) void {
    model.git_branch_delete_picker_open = false;
    if (!isListedNonCurrent(model, name)) return;
    writeFixed(&model.git_branch_delete_storage, &model.git_branch_delete_len, name);
}

fn appendListedBranch(model: *Model, name: []const u8, remote: bool, occupied: bool) void {
    if (model.git_branch_list_count >= max_listed_branches) return;
    if (!git_branch.isPlausibleBranchName(name)) return;
    if (remote) {
        if (listedKindCount(model, true) >= max_remote_branches) return;
        const counterpart = remoteLocalCounterpart(name);
        if (counterpart.len > 0 and hasListedLocalName(model, counterpart)) return;
    } else if (listedKindCount(model, false) >= max_local_branches) return;
    var i: usize = 0;
    while (i < model.git_branch_list_count) : (i += 1) {
        if (std.mem.eql(u8, listedBranch(model, i), name)) return;
    }
    model.git_branch_list_store[model.git_branch_list_count].set(name, remote, occupied);
    model.git_branch_list_count += 1;
}

pub fn applyStdoutBranches(model: *Model, raw: []const u8) void {
    var refs: [max_listed_branches]ParsedRef = undefined;
    const n = collectStdoutRefsFor(raw, occupancyCwd(model), refs[0..], model);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (!refs[i].remote) appendListedBranch(model, refs[i].name, false, refs[i].occupied);
    }
    i = 0;
    while (i < n) : (i += 1) {
        if (refs[i].remote) appendListedBranch(model, refs[i].name, true, refs[i].occupied);
    }
}

fn dropRemotesWithLocalCounterpart(model: *Model) void {
    var write: u32 = 0;
    var i: u32 = 0;
    while (i < model.git_branch_list_count) : (i += 1) {
        const item = model.git_branch_list_store[i];
        if (item.remote) {
            const counterpart = remoteLocalCounterpart(item.text());
            if (counterpart.len > 0 and hasListedLocalName(model, counterpart)) continue;
        }
        if (write != i) model.git_branch_list_store[write] = item;
        write += 1;
    }
    model.git_branch_list_count = write;
}

/// Drop remotes whose local counterpart arrived later, then sort.
pub fn finalizeListedBranches(model: *Model) void {
    dropRemotesWithLocalCounterpart(model);
    sortListedBranches(model);
}

fn cancelList(model: *Model, fx: *Effects) void {
    if (model.git_branch_list_key == 0) return;
    fx.cancel(model.git_branch_list_key);
    model.git_branch_list_key = 0;
}

fn cancelCheckout(model: *Model, fx: *Effects) void {
    if (model.git_checkout_key == 0) return;
    fx.cancel(model.git_checkout_key);
    model.git_checkout_key = 0;
}

fn cancelCreate(model: *Model, fx: *Effects) void {
    if (model.git_create_key == 0) return;
    fx.cancel(model.git_create_key);
    model.git_create_key = 0;
}

fn cancelDelete(model: *Model, fx: *Effects) void {
    if (model.git_delete_key == 0) return;
    fx.cancel(model.git_delete_key);
    model.git_delete_key = 0;
}

fn cancelFetch(model: *Model, fx: *Effects) void {
    if (model.git_fetch_key == 0) return;
    fx.cancel(model.git_fetch_key);
    model.git_fetch_key = 0;
}

fn resetPushState(model: *Model) void {
    model.git_push_phase = .idle;
    model.git_push_has_upstream = false;
    model.git_push_branch_len = 0;
    model.git_push_remote_len = 0;
}

pub fn cancelPush(model: *Model, fx: *Effects) void {
    if (model.git_push_key == 0) return;
    fx.cancel(model.git_push_key);
    model.git_push_key = 0;
    resetPushState(model);
}

fn gitPushBranch(model: *const Model) []const u8 {
    return model.git_push_branch_storage[0..model.git_push_branch_len];
}

fn gitPushRemote(model: *const Model) []const u8 {
    return model.git_push_remote_storage[0..model.git_push_remote_len];
}

fn pushCwd(model: *const Model) []const u8 {
    const probed = model.git_push_probe_path_storage[0..model.git_push_probe_path_len];
    if (probed.len > 0) return probed;
    return probePath(model);
}

fn failPush(model: *Model) void {
    model.git_push_key = 0;
    resetPushState(model);
    closeCommitCard(model);
    model.setAttachStatus(push_failed_status);
}

fn applyRemoteCandidate(model: *Model, name: []const u8) void {
    if (!isPlausibleRemoteName(name)) return;
    const current = gitPushRemote(model);
    if (current.len == 0) {
        writeFixed(&model.git_push_remote_storage, &model.git_push_remote_len, name);
        return;
    }
    if (std.mem.eql(u8, current, git_origin_remote)) return;
    if (std.mem.eql(u8, name, git_origin_remote)) {
        writeFixed(&model.git_push_remote_storage, &model.git_push_remote_len, name);
    }
}

fn spawnPushCmd(model: *Model, fx: *Effects, cwd: []const u8, argv: []const []const u8, phase: GitPushPhase) void {
    const key = model.next_git_push_key;
    model.next_git_push_key = key + 1;
    model.git_push_key = key;
    model.git_push_phase = phase;
    model.git_push_probe_session = model.selected;
    const probed = model.git_push_probe_path_storage[0..model.git_push_probe_path_len];
    if (cwd.ptr != probed.ptr) {
        writeFixed(&model.git_push_probe_path_storage, &model.git_push_probe_path_len, cwd);
    }
    fx.spawn(.{
        .key = key,
        .argv = argv,
        .on_line = Effects.lineMsg(.fx_line),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
}

fn spawnBarePush(model: *Model, fx: *Effects) void {
    const cwd = pushCwd(model);
    if (cwd.len == 0) {
        failPush(model);
        return;
    }
    var argv_buf: [push_argv_len][]const u8 = undefined;
    spawnPushCmd(model, fx, cwd, pushArgvFor(cwd, &argv_buf), .push);
}

fn spawnShowCurrent(model: *Model, fx: *Effects) void {
    const cwd = pushCwd(model);
    if (cwd.len == 0) {
        failPush(model);
        return;
    }
    var argv_buf: [show_current_argv_len][]const u8 = undefined;
    spawnPushCmd(model, fx, cwd, git_branch.argvFor(cwd, &argv_buf), .show_current);
}

fn spawnRemotes(model: *Model, fx: *Effects) void {
    const cwd = pushCwd(model);
    if (cwd.len == 0) {
        failPush(model);
        return;
    }
    model.git_push_remote_len = 0;
    var argv_buf: [remote_argv_len][]const u8 = undefined;
    spawnPushCmd(model, fx, cwd, remoteArgvFor(cwd, &argv_buf), .remotes);
}

fn spawnSetUpstreamPush(model: *Model, fx: *Effects) void {
    const cwd = pushCwd(model);
    if (cwd.len == 0) {
        failPush(model);
        return;
    }
    var argv_buf: [set_upstream_push_argv_len][]const u8 = undefined;
    const argv = setUpstreamPushArgvFor(cwd, gitPushRemote(model), gitPushBranch(model), &argv_buf) orelse {
        failPush(model);
        return;
    };
    spawnPushCmd(model, fx, cwd, argv, .push);
}

fn continueNoUpstream(model: *Model, fx: *Effects) void {
    if (pushBranchFromLabel(git_branch.gitBranchLabel(model))) |branch| {
        writeFixed(&model.git_push_branch_storage, &model.git_push_branch_len, branch);
        spawnRemotes(model, fx);
        return;
    }
    spawnShowCurrent(model, fx);
}

fn resetWorktreeAddState(model: *Model) void {
    model.git_worktree_add_dest_len = 0;
    model.git_worktree_add_branch_len = 0;
    model.git_worktree_add_slug_len = 0;
    model.git_worktree_add_attempt = 0;
    model.git_worktree_base_len = 0;
}

fn cancelWorktreeAdd(model: *Model, fx: *Effects) void {
    if (model.git_worktree_add_key == 0) return;
    fx.cancel(model.git_worktree_add_key);
    model.git_worktree_add_key = 0;
    resetWorktreeAddState(model);
}

fn cancelWorktreeBase(model: *Model, fx: *Effects) void {
    if (model.git_worktree_base_key == 0) return;
    fx.cancel(model.git_worktree_base_key);
    model.git_worktree_base_key = 0;
    resetWorktreeAddState(model);
}

fn probeSupported() bool {
    return builtin.os.tag != .windows;
}

fn probePath(model: *const Model) []const u8 {
    const path = model.selectedProjectPath();
    if (path.len == 0) return "";
    const io = model.store_io orelse return "";
    if (!main.directoryExists(io, path)) return "";
    return path;
}

/// Cancel any in-flight list / checkout / create / delete / fetch /
/// push / worktree-add, drop the cached heads and remotes, and spawn
/// `for-each-ref` when the selected session has an existing
/// `project_path`. Empty / missing / Windows skips the spawn so the
/// picker stays omitted unless `has_git_branch` is already true.
pub fn refresh(model: *Model, fx: *Effects) void {
    cancelList(model, fx);
    cancelCheckout(model, fx);
    cancelCreate(model, fx);
    cancelDelete(model, fx);
    cancelFetch(model, fx);
    cancelPush(model, fx);
    cancelWorktreeAdd(model, fx);
    cancelWorktreeBase(model, fx);
    clearListedBranches(model);
    closePicker(model);
    closeCreate(model);
    closeWorktreeCreate(model);
    closeDelete(model);
    if (model.git_commit_generate_key != 0) {
        fx.cancel(model.git_commit_generate_key);
        model.git_commit_generate_key = 0;
        model.git_commit_generate_stdout_len = 0;
        model.setAttachStatus("Could not commit.");
    }
    if (model.git_commit_key != 0) {
        fx.cancel(model.git_commit_key);
        model.git_commit_key = 0;
        model.git_commit_phase = .idle;
        model.git_commit_message_len = 0;
        model.setAttachStatus("Could not commit.");
    }
    model.git_commit_then_push = false;
    dropCommitSnapshot(model, fx);
    closeCommitCard(model);
    if (!probeSupported()) return;
    const cwd = probePath(model);
    if (cwd.len == 0) return;

    const key = model.next_git_branch_list_key;
    model.next_git_branch_list_key = key + 1;
    model.git_branch_list_key = key;
    model.git_branch_list_probe_session = model.selected;
    writeFixed(&model.git_branch_list_probe_path_storage, &model.git_branch_list_probe_path_len, cwd);

    var argv_buf: [list_argv_len][]const u8 = undefined;
    fx.spawn(.{
        .key = key,
        .argv = listArgvFor(cwd, &argv_buf),
        .on_line = Effects.lineMsg(.fx_line),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
}

fn listStillCurrent(model: *const Model) bool {
    if (model.git_branch_list_key == 0) return false;
    if (model.git_branch_list_probe_session != model.selected) return false;
    const path = model.selectedProjectPath();
    const probed = model.git_branch_list_probe_path_storage[0..model.git_branch_list_probe_path_len];
    return std.mem.eql(u8, path, probed);
}

fn checkoutStillCurrent(model: *const Model) bool {
    if (model.git_checkout_key == 0) return false;
    if (model.git_checkout_probe_session != model.selected) return false;
    const path = model.selectedProjectPath();
    const probed = model.git_checkout_probe_path_storage[0..model.git_checkout_probe_path_len];
    return std.mem.eql(u8, path, probed);
}

fn createStillCurrent(model: *const Model) bool {
    if (model.git_create_key == 0) return false;
    if (model.git_create_probe_session != model.selected) return false;
    const path = model.selectedProjectPath();
    const probed = model.git_create_probe_path_storage[0..model.git_create_probe_path_len];
    return std.mem.eql(u8, path, probed);
}

fn deleteStillCurrent(model: *const Model) bool {
    if (model.git_delete_key == 0) return false;
    if (model.git_delete_probe_session != model.selected) return false;
    const path = model.selectedProjectPath();
    const probed = model.git_delete_probe_path_storage[0..model.git_delete_probe_path_len];
    return std.mem.eql(u8, path, probed);
}

fn fetchStillCurrent(model: *const Model) bool {
    if (model.git_fetch_key == 0) return false;
    if (model.git_fetch_probe_session != model.selected) return false;
    const path = model.selectedProjectPath();
    const probed = model.git_fetch_probe_path_storage[0..model.git_fetch_probe_path_len];
    return std.mem.eql(u8, path, probed);
}

fn pushStillCurrent(model: *const Model) bool {
    if (model.git_push_key == 0) return false;
    if (model.git_push_probe_session != model.selected) return false;
    const path = model.selectedProjectPath();
    const probed = model.git_push_probe_path_storage[0..model.git_push_probe_path_len];
    return std.mem.eql(u8, path, probed);
}

fn worktreeAddStillCurrent(model: *const Model) bool {
    if (model.git_worktree_add_key == 0) return false;
    if (model.git_worktree_add_probe_session != model.selected) return false;
    const path = model.selectedProjectPath();
    const probed = model.git_worktree_add_probe_path_storage[0..model.git_worktree_add_probe_path_len];
    return std.mem.eql(u8, path, probed);
}

fn worktreeBaseStillCurrent(model: *const Model) bool {
    if (model.git_worktree_base_key == 0) return false;
    if (model.git_worktree_add_probe_session != model.selected) return false;
    const path = model.selectedProjectPath();
    const probed = model.git_worktree_add_probe_path_storage[0..model.git_worktree_add_probe_path_len];
    return std.mem.eql(u8, path, probed);
}

pub fn gitMutationInFlight(model: *const Model) bool {
    return model.git_create_key != 0 or model.git_checkout_key != 0 or model.git_delete_key != 0 or model.git_fetch_key != 0 or model.git_push_key != 0 or model.git_worktree_add_key != 0 or model.git_worktree_base_key != 0 or model.git_commit_key != 0 or model.git_commit_generate_key != 0;
}

pub fn applyListLine(model: *Model, line: native_sdk.EffectLine) void {
    if (line.key != model.git_branch_list_key or model.git_branch_list_key == 0) return;
    if (!listStillCurrent(model)) return;
    applyStdoutBranches(model, line.line);
}

pub fn handleListExit(model: *Model, exit: native_sdk.EffectExit) void {
    if (exit.key != model.git_branch_list_key or model.git_branch_list_key == 0) return;
    const current = listStillCurrent(model);
    model.git_branch_list_key = 0;
    if (!current or exit.reason != .exited or exit.code != 0) {
        clearListedBranches(model);
        if (!git_branch.hasGitBranch(model)) closePicker(model);
        return;
    }
    finalizeListedBranches(model);
}

pub fn refreshWorkspaceProbes(model: *Model, fx: *Effects) void {
    git_branch.refresh(model, fx);
    git_dirty.refresh(model, fx);
    git_numstat.refresh(model, fx);
    git_ahead_behind.refresh(model, fx);
    git_remotes.refresh(model, fx);
    git_toplevel.refresh(model, fx);
    git_common_dir.refresh(model, fx);
    file_mention.refresh(model, fx);
    refresh(model, fx);
}

/// Selecting the current branch closes the picker. A listed
/// remote-tracking name one-shots `git checkout --track` even when
/// its local counterpart is the current branch. Another plausible
/// local name one-shots `git checkout` unless that local is occupied
/// in another worktree (status, no spawn). Implausible names are
/// ignored. In-flight create, delete, fetch, or push is a no-op so
/// the one-shots do not overlap.
pub fn pickBranch(model: *Model, fx: *Effects, name: []const u8) void {
    closePicker(model);
    if (model.git_create_key != 0 or model.git_delete_key != 0 or model.git_fetch_key != 0 or model.git_push_key != 0 or model.git_worktree_add_key != 0 or model.git_worktree_base_key != 0 or model.git_commit_key != 0 or model.git_commit_generate_key != 0) return;
    if (!git_branch.isPlausibleBranchName(name)) return;
    const remote = isListedRemoteName(model, name);
    if (!remote and std.mem.eql(u8, name, git_branch.gitBranchLabel(model))) return;
    if (!remote and listedLocalNameIsOccupied(model, name)) {
        model.setAttachStatus(occupied_checkout_status);
        return;
    }
    if (!probeSupported()) return;
    const cwd = probePath(model);
    if (cwd.len == 0) return;

    if (remote) {
        var track_buf: [track_checkout_argv_len][]const u8 = undefined;
        const argv = trackCheckoutArgvFor(cwd, name, &track_buf) orelse return;
        spawnCheckout(model, fx, cwd, argv);
        return;
    }

    var argv_buf: [checkout_argv_len][]const u8 = undefined;
    const argv = checkoutArgvFor(cwd, name, &argv_buf) orelse return;
    spawnCheckout(model, fx, cwd, argv);
}

fn spawnCheckout(model: *Model, fx: *Effects, cwd: []const u8, argv: []const []const u8) void {
    cancelCheckout(model, fx);
    const key = model.next_git_checkout_key;
    model.next_git_checkout_key = key + 1;
    model.git_checkout_key = key;
    model.git_checkout_probe_session = model.selected;
    writeFixed(&model.git_checkout_probe_path_storage, &model.git_checkout_probe_path_len, cwd);

    fx.spawn(.{
        .key = key,
        .argv = argv,
        .on_line = Effects.lineMsg(.fx_line),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
}

pub fn handleCheckoutExit(model: *Model, fx: *Effects, exit: native_sdk.EffectExit) void {
    if (exit.key != model.git_checkout_key or model.git_checkout_key == 0) return;
    const current = checkoutStillCurrent(model);
    model.git_checkout_key = 0;
    if (!current) return;
    if (exit.reason == .exited and exit.code == 0) {
        refreshWorkspaceProbes(model, fx);
        return;
    }
    model.setAttachStatus(checkout_failed_status);
}

/// Confirm the create card: plausible draft one-shots `git checkout -b`.
/// Empty / implausible names do not spawn and keep the field open.
/// Busy session or in-flight create/checkout/delete/fetch/push is a no-op.
pub fn confirmCreate(model: *Model, fx: *Effects) void {
    if (gitMutationInFlight(model)) return;
    if (model.is_streaming()) return;
    const name = std.mem.trim(u8, model.git_branch_create_buffer.text(), " \t\r\n");
    if (!git_branch.isPlausibleBranchName(name)) return;
    if (!probeSupported()) return;
    const cwd = probePath(model);
    if (cwd.len == 0) return;

    var argv_buf: [create_argv_len][]const u8 = undefined;
    const argv = createArgvFor(cwd, name, &argv_buf) orelse return;

    const key = model.next_git_create_key;
    model.next_git_create_key = key + 1;
    model.git_create_key = key;
    model.git_create_probe_session = model.selected;
    writeFixed(&model.git_create_probe_path_storage, &model.git_create_probe_path_len, cwd);

    fx.spawn(.{
        .key = key,
        .argv = argv,
        .on_line = Effects.lineMsg(.fx_line),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
}

pub fn handleCreateExit(model: *Model, fx: *Effects, exit: native_sdk.EffectExit) void {
    if (exit.key != model.git_create_key or model.git_create_key == 0) return;
    const current = createStillCurrent(model);
    model.git_create_key = 0;
    if (!current) return;
    if (exit.reason == .exited and exit.code == 0) {
        closeCreate(model);
        refreshWorkspaceProbes(model, fx);
        return;
    }
    model.setAttachStatus(create_failed_status);
}

/// Confirm the delete card: a listed non-current, unoccupied name
/// one-shots `git branch -d`. Empty / current / occupied /
/// implausible names do not spawn and keep the card open. Busy
/// session or in-flight checkout/create/delete/fetch/push is a no-op.
pub fn confirmDelete(model: *Model, fx: *Effects) void {
    if (gitMutationInFlight(model)) return;
    if (model.is_streaming()) return;
    const name = std.mem.trim(u8, gitBranchDeleteLabel(model), " \t\r\n");
    if (!isListedNonCurrent(model, name)) return;
    if (!probeSupported()) return;
    const cwd = probePath(model);
    if (cwd.len == 0) return;

    var argv_buf: [delete_argv_len][]const u8 = undefined;
    const argv = deleteArgvFor(cwd, name, &argv_buf) orelse return;

    const key = model.next_git_delete_key;
    model.next_git_delete_key = key + 1;
    model.git_delete_key = key;
    model.git_delete_probe_session = model.selected;
    writeFixed(&model.git_delete_probe_path_storage, &model.git_delete_probe_path_len, cwd);

    fx.spawn(.{
        .key = key,
        .argv = argv,
        .on_line = Effects.lineMsg(.fx_line),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
}

pub fn handleDeleteExit(model: *Model, fx: *Effects, exit: native_sdk.EffectExit) void {
    if (exit.key != model.git_delete_key or model.git_delete_key == 0) return;
    const current = deleteStillCurrent(model);
    model.git_delete_key = 0;
    if (!current) return;
    if (exit.reason == .exited and exit.code == 0) {
        closeDelete(model);
        refreshWorkspaceProbes(model, fx);
        return;
    }
    model.setAttachStatus(delete_failed_status);
}

/// Fetch… closes the picker and one-shots `git fetch --prune`.
/// Busy session or in-flight checkout/create/delete/fetch/push is a no-op.
pub fn startFetch(model: *Model, fx: *Effects) void {
    closePicker(model);
    closeCreate(model);
    closeWorktreeCreate(model);
    closeDelete(model);
    dropCommitSnapshot(model, fx);
    closeCommitCard(model);
    if (gitMutationInFlight(model)) return;
    if (model.is_streaming()) return;
    if (!probeSupported()) return;
    const cwd = probePath(model);
    if (cwd.len == 0) return;

    var argv_buf: [fetch_argv_len][]const u8 = undefined;
    const argv = fetchArgvFor(cwd, &argv_buf);

    const key = model.next_git_fetch_key;
    model.next_git_fetch_key = key + 1;
    model.git_fetch_key = key;
    model.git_fetch_probe_session = model.selected;
    writeFixed(&model.git_fetch_probe_path_storage, &model.git_fetch_probe_path_len, cwd);

    fx.spawn(.{
        .key = key,
        .argv = argv,
        .on_line = Effects.lineMsg(.fx_line),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
}

pub fn handleFetchExit(model: *Model, fx: *Effects, exit: native_sdk.EffectExit) void {
    if (exit.key != model.git_fetch_key or model.git_fetch_key == 0) return;
    const current = fetchStillCurrent(model);
    model.git_fetch_key = 0;
    if (!current) return;
    if (exit.reason == .exited and exit.code == 0) {
        refreshWorkspaceProbes(model, fx);
        return;
    }
    model.setAttachStatus(fetch_failed_status);
}

fn spawnUpstreamProbe(model: *Model, fx: *Effects, cwd: []const u8) void {
    resetPushState(model);
    var argv_buf: [upstream_argv_len][]const u8 = undefined;
    spawnPushCmd(model, fx, cwd, upstreamArgvFor(cwd, &argv_buf), .upstream);
}

fn preparePushUi(model: *Model, fx: *Effects, keep_commit_card: bool) void {
    closePicker(model);
    closeCreate(model);
    closeWorktreeCreate(model);
    closeDelete(model);
    dropCommitSnapshot(model, fx);
    if (!keep_commit_card) closeCommitCard(model);
}

fn startGatedPush(model: *Model, fx: *Effects) void {
    if (!git_ahead_behind.canPushGitBranch(model)) return;
    if (gitMutationInFlight(model)) return;
    if (model.is_streaming()) return;
    if (!probeSupported()) return;
    const cwd = probePath(model);
    if (cwd.len == 0) return;
    spawnUpstreamProbe(model, fx, cwd);
}

/// Composer menu Push…. Closes any open Commit… card, then probes
/// `@{upstream}`. A resolved upstream one-shots `git push` (no extra
/// flags). No upstream one-shots
/// `git push --set-upstream <remote> <branch>` after resolving the
/// current branch and a remote (`origin` preferred). Detached HEAD
/// or no remotes set `Could not push.` and do not spawn a push. Not
/// force, not daemon `WorkspaceOperation::Push`. Offered only when
/// `canPushGitBranch` (Waku `can_push` with
/// remotes-required-for-first-push). Busy session or in-flight
/// checkout/create/delete/fetch/push is a no-op. Does not require
/// an open Commit… card.
pub fn startPush(model: *Model, fx: *Effects) void {
    preparePushUi(model, fx, false);
    startGatedPush(model, fx);
}

/// Gated Push… from the Commit… card. Same `canPushGitBranch`
/// gates as `startPush`, but keeps the card open so Native can
/// show Pushing… until the push terminates.
pub fn startPushFromCommitCard(model: *Model, fx: *Effects) void {
    preparePushUi(model, fx, true);
    startGatedPush(model, fx);
}

/// Ungated Push… probe/spawn for Commit and Push. Reuses the same
/// upstream → bare `git push` / `--set-upstream` path as `startPush`.
/// Does not re-check `canPushGitBranch`: after a just-created commit
/// the ahead/behind probe is stale (often ahead=0). Waku
/// `CommitAndPush` does not re-check `can_push`. Keeps the Commit…
/// card open for in-dialog Pushing…; composer `startPush` still
/// closes it. Sets `Could not push.` and dismisses the card when
/// the probe cannot start (missing cwd, streaming, another git
/// mutation, Windows). Detached HEAD / no remotes still fail later
/// in `handlePushExit` the same way as Push…. Does not re-check
/// remotes-required-for-first-push vs ahead: the Commit and Push
/// UI gate is what hides no-remotes first-push.
pub fn beginPushAfterCommit(model: *Model, fx: *Effects) void {
    preparePushUi(model, fx, true);
    if (gitMutationInFlight(model) or model.is_streaming() or !probeSupported()) {
        closeCommitCard(model);
        model.setAttachStatus(push_failed_status);
        return;
    }
    const cwd = probePath(model);
    if (cwd.len == 0) {
        closeCommitCard(model);
        model.setAttachStatus(push_failed_status);
        return;
    }
    spawnUpstreamProbe(model, fx, cwd);
}

pub fn applyPushLine(model: *Model, line: native_sdk.EffectLine) void {
    if (line.key != model.git_push_key or model.git_push_key == 0) return;
    if (!pushStillCurrent(model)) return;
    switch (model.git_push_phase) {
        .upstream => {
            if (stdoutHasUpstream(line.line)) model.git_push_has_upstream = true;
        },
        .show_current => {
            if (git_branch.takeBranchName(line.line)) |name| {
                writeFixed(&model.git_push_branch_storage, &model.git_push_branch_len, name);
            }
        },
        .remotes => {
            var it = std.mem.splitScalar(u8, line.line, '\n');
            while (it.next()) |raw| {
                applyRemoteCandidate(model, std.mem.trim(u8, raw, " \t\r\n"));
            }
        },
        .idle, .push => {},
    }
}

pub fn handlePushExit(model: *Model, fx: *Effects, exit: native_sdk.EffectExit) void {
    if (exit.key != model.git_push_key or model.git_push_key == 0) return;
    const current = pushStillCurrent(model);
    const phase = model.git_push_phase;
    const has_upstream = model.git_push_has_upstream;
    model.git_push_key = 0;
    if (!current) {
        resetPushState(model);
        closeCommitCard(model);
        return;
    }
    switch (phase) {
        .idle => {
            resetPushState(model);
            closeCommitCard(model);
        },
        .upstream => {
            if (exit.reason == .exited and exit.code == 0 and has_upstream) {
                spawnBarePush(model, fx);
                return;
            }
            continueNoUpstream(model, fx);
        },
        .show_current => {
            if (exit.reason == .exited and exit.code == 0 and git_branch.isPlausibleBranchName(gitPushBranch(model))) {
                spawnRemotes(model, fx);
                return;
            }
            failPush(model);
        },
        .remotes => {
            if (exit.reason == .exited and exit.code == 0 and isPlausibleRemoteName(gitPushRemote(model)) and git_branch.isPlausibleBranchName(gitPushBranch(model))) {
                spawnSetUpstreamPush(model, fx);
                return;
            }
            failPush(model);
        },
        .push => {
            resetPushState(model);
            closeCommitCard(model);
            if (exit.reason == .exited and exit.code == 0) {
                refreshWorkspaceProbes(model, fx);
                return;
            }
            model.setAttachStatus(push_failed_status);
        },
    }
}

fn gitWorktreeBase(model: *const Model) []const u8 {
    return model.git_worktree_base_storage[0..model.git_worktree_base_len];
}

fn gitWorktreeAddSlug(model: *const Model) []const u8 {
    return model.git_worktree_add_slug_storage[0..model.git_worktree_add_slug_len];
}

fn worktreeDestExists(model: *const Model, dest: []const u8) bool {
    const io = model.store_io orelse return false;
    return main.directoryExists(io, dest);
}

fn assignWorktreeCandidate(model: *Model, home: []const u8, project_path: []const u8, slug: []const u8, index: u32) bool {
    var name_buf: [git_branch.max_git_branch]u8 = undefined;
    const name = worktreeCandidateName(slug, index, name_buf[0..]) orelse return false;
    var dest_buf: [main.max_project_path]u8 = undefined;
    const dest = worktreeDestPathFor(home, project_path, name, dest_buf[0..], model) orelse return false;
    var branch_buf: [git_branch.max_git_branch]u8 = undefined;
    const branch = worktreeBranchName(name, branch_buf[0..]) orelse return false;
    writeFixed(&model.git_worktree_add_dest_storage, &model.git_worktree_add_dest_len, dest);
    writeFixed(&model.git_worktree_add_branch_storage, &model.git_worktree_add_branch_len, branch);
    model.git_worktree_add_attempt = index;
    return true;
}

fn worktreeCandidateIsTaken(model: *const Model, dest: []const u8, branch: []const u8) bool {
    return worktreeCandidateOccupied(worktreeDestExists(model, dest), hasListedLocalName(model, branch));
}

fn pickWorktreeCandidate(model: *Model, home: []const u8, project_path: []const u8, slug: []const u8, start: u32) bool {
    var index = start;
    while (index < max_worktree_candidates) : (index += 1) {
        if (!assignWorktreeCandidate(model, home, project_path, slug, index)) continue;
        const dest = model.git_worktree_add_dest_storage[0..model.git_worktree_add_dest_len];
        const branch = model.git_worktree_add_branch_storage[0..model.git_worktree_add_branch_len];
        if (worktreeCandidateIsTaken(model, dest, branch)) continue;
        return true;
    }
    return false;
}

fn retryWorktreeAdd(model: *Model, fx: *Effects) bool {
    const slug = gitWorktreeAddSlug(model);
    if (slug.len == 0) return false;
    const stored_cwd = model.git_worktree_add_probe_path_storage[0..model.git_worktree_add_probe_path_len];
    if (!pickWorktreeCandidate(model, model.homeDir(), stored_cwd, slug, model.git_worktree_add_attempt + 1)) return false;
    spawnWorktreeAdd(model, fx);
    return model.git_worktree_add_key != 0;
}

fn spawnWorktreeAdd(model: *Model, fx: *Effects) void {
    const stored_cwd = model.git_worktree_add_probe_path_storage[0..model.git_worktree_add_probe_path_len];
    const stored_dest = model.git_worktree_add_dest_storage[0..model.git_worktree_add_dest_len];
    const stored_branch = model.git_worktree_add_branch_storage[0..model.git_worktree_add_branch_len];
    const slash = std.mem.lastIndexOfScalar(u8, stored_dest, '/') orelse return;
    const stored_parent = stored_dest[0..slash];
    var argv_buf: [worktree_add_argv_len][]const u8 = undefined;
    const argv = worktreeAddArgvFor(stored_cwd, stored_parent, stored_branch, stored_dest, gitWorktreeBase(model), &argv_buf) orelse return;

    const key = model.next_git_worktree_add_key;
    model.next_git_worktree_add_key = key + 1;
    model.git_worktree_add_key = key;
    fx.spawn(.{
        .key = key,
        .argv = argv,
        .on_line = Effects.lineMsg(.fx_line),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
}

/// Confirm the New worktree… card: a safe name probes
/// `refs/remotes/origin/HEAD` then one-shots
/// `mkdir -p ~/.faku/worktrees/<nest>` plus
/// `git worktree add -b faku/<name> <path> [base]`. Occupied dest
/// or listed `faku/<name>` walks Waku candidates (`slug` …
/// `slug-8`) and keeps the original slug. Empty / unsafe names do
/// not spawn and keep the field open. All candidates taken sets
/// status. Busy session or in-flight
/// checkout/create/delete/fetch/push/worktree-add/base probe is a
/// no-op.
pub fn confirmWorktreeAdd(model: *Model, fx: *Effects) void {
    if (gitMutationInFlight(model)) return;
    if (model.is_streaming()) return;
    const raw = std.mem.trim(u8, model.git_worktree_create_buffer.text(), " \t\r\n");
    const name = sanitizeWorktreeName(raw) orelse return;
    if (!probeSupported()) return;
    const cwd = probePath(model);
    if (cwd.len == 0) return;
    const home = model.homeDir();

    var parent_buf: [main.max_project_path]u8 = undefined;
    const parent = worktreeParentPathFor(home, cwd, parent_buf[0..], model) orelse return;
    writeFixed(&model.git_worktree_add_slug_storage, &model.git_worktree_add_slug_len, name);
    if (!pickWorktreeCandidate(model, home, cwd, name, 0)) {
        resetWorktreeAddState(model);
        model.setAttachStatus(worktree_add_failed_status);
        return;
    }

    model.git_worktree_add_probe_session = model.selected;
    writeFixed(&model.git_worktree_add_probe_path_storage, &model.git_worktree_add_probe_path_len, cwd);
    model.git_worktree_base_len = 0;

    const stored_dest = model.git_worktree_add_dest_storage[0..model.git_worktree_add_dest_len];
    if (!std.mem.startsWith(u8, stored_dest, parent)) return;
    if (stored_dest.len <= parent.len or stored_dest[parent.len] != '/') return;

    const key = model.next_git_worktree_base_key;
    model.next_git_worktree_base_key = key + 1;
    model.git_worktree_base_key = key;

    var argv_buf: [worktree_base_argv_len][]const u8 = undefined;
    fx.spawn(.{
        .key = key,
        .argv = worktreeBaseArgvFor(cwd, &argv_buf),
        .on_line = Effects.lineMsg(.fx_line),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
}

pub fn applyWorktreeBaseLine(model: *Model, line: native_sdk.EffectLine) void {
    if (line.key != model.git_worktree_base_key or model.git_worktree_base_key == 0) return;
    if (!worktreeBaseStillCurrent(model)) return;
    if (worktreeBaseFromSymbolicRef(line.line)) |base| {
        writeFixed(&model.git_worktree_base_storage, &model.git_worktree_base_len, base);
    }
}

pub fn handleWorktreeBaseExit(model: *Model, fx: *Effects, exit: native_sdk.EffectExit) void {
    if (exit.key != model.git_worktree_base_key or model.git_worktree_base_key == 0) return;
    const current = worktreeBaseStillCurrent(model);
    model.git_worktree_base_key = 0;
    if (!current) {
        model.git_worktree_base_len = 0;
        return;
    }
    if (gitWorktreeBase(model).len == 0) {
        if (pushBranchFromLabel(git_branch.gitBranchLabel(model))) |branch| {
            writeFixed(&model.git_worktree_base_storage, &model.git_worktree_base_len, branch);
        }
    }
    spawnWorktreeAdd(model, fx);
}

/// On success, retarget the selected session `project_path` to the
/// dest actually used (absolute) and return true so the caller can
/// persist + refresh via `persistComposerProject`. A failed add
/// retries the next free candidate (`slug-2` … `slug-8`) via
/// `fx.spawn`. Exhausted candidates set a short status and leave
/// `project_path` unchanged.
pub fn handleWorktreeAddExit(model: *Model, fx: *Effects, exit: native_sdk.EffectExit) bool {
    if (exit.key != model.git_worktree_add_key or model.git_worktree_add_key == 0) return false;
    const current = worktreeAddStillCurrent(model);
    model.git_worktree_add_key = 0;
    if (!current) return false;
    if (exit.reason == .exited and exit.code == 0) {
        const dest = model.git_worktree_add_dest_storage[0..model.git_worktree_add_dest_len];
        if (dest.len > 0) model.setSelectedProjectPath(dest);
        closeWorktreeCreate(model);
        resetWorktreeAddState(model);
        return true;
    }
    if (retryWorktreeAdd(model, fx)) return false;
    resetWorktreeAddState(model);
    model.setAttachStatus(worktree_add_failed_status);
    return false;
}

test "list argv is chdir script plus for-each-ref refs/heads and refs/remotes" {
    var buf: [list_argv_len][]const u8 = undefined;
    const argv = listArgvFor("/tmp/faku-heads", &buf);
    try std.testing.expectEqualStrings(sh_bin, argv[0]);
    try std.testing.expectEqualStrings("-c", argv[1]);
    try std.testing.expectEqualStrings(main.fx_ask_chdir_script, argv[2]);
    try std.testing.expectEqualStrings("sh", argv[3]);
    try std.testing.expectEqualStrings("/tmp/faku-heads", argv[4]);
    try std.testing.expectEqualStrings(git_bin, argv[5]);
    try std.testing.expectEqualStrings(git_for_each_ref_cmd, argv[6]);
    try std.testing.expectEqualStrings(git_refname_format, argv[7]);
    try std.testing.expectEqualStrings("--format=%(refname)%00%(worktreepath)", argv[7]);
    try std.testing.expectEqualStrings(git_heads_ref, argv[8]);
    try std.testing.expectEqualStrings(git_remotes_ref, argv[9]);
    try std.testing.expect(isGitBranchListArgv(argv));
    try std.testing.expect(!isGitBranchListArgv(&.{
        sh_bin,
        "-c",
        main.fx_ask_chdir_script,
        "sh",
        "/tmp/faku-heads",
        git_bin,
        git_for_each_ref_cmd,
        "--format=%(refname)",
        git_heads_ref,
        git_remotes_ref,
    }));
    try std.testing.expect(!isGitBranchListArgv(&.{ git_bin, git_for_each_ref_cmd, git_refname_format, git_heads_ref }));
    try std.testing.expect(!isGitBranchListArgv(&.{
        sh_bin,
        "-c",
        main.fx_ask_chdir_script,
        "sh",
        "/tmp/faku-heads",
        git_bin,
        git_for_each_ref_cmd,
        "--format=%(refname:short)",
        git_heads_ref,
    }));
    try std.testing.expect(!git_branch.isGitBranchArgv(argv));
    try std.testing.expect(!isGitCheckoutArgv(argv));
    try std.testing.expect(!isGitTrackCheckoutArgv(argv));
    try std.testing.expect(!isGitCreateArgv(argv));
    try std.testing.expect(!isGitDeleteArgv(argv));
    try std.testing.expect(!isGitFetchArgv(argv));
    try std.testing.expect(!isGitPushArgv(argv));
    try std.testing.expect(!isGitWorktreeAddArgv(argv));
}

test "checkout argv keeps the name as its own slot and rejects implausible names" {
    var buf: [checkout_argv_len][]const u8 = undefined;
    const argv = checkoutArgvFor("/tmp/faku-co", "feat/composer", &buf).?;
    try std.testing.expectEqualStrings(sh_bin, argv[0]);
    try std.testing.expectEqualStrings(main.fx_ask_chdir_script, argv[2]);
    try std.testing.expectEqualStrings("/tmp/faku-co", argv[4]);
    try std.testing.expectEqualStrings(git_bin, argv[5]);
    try std.testing.expectEqualStrings(git_checkout_cmd, argv[6]);
    try std.testing.expectEqualStrings("feat/composer", argv[7]);
    try std.testing.expect(isGitCheckoutArgv(argv));
    try std.testing.expect(!isGitTrackCheckoutArgv(argv));
    try std.testing.expect(!isGitBranchListArgv(argv));
    try std.testing.expect(!isGitCreateArgv(argv));
    try std.testing.expect(!isGitDeleteArgv(argv));
    try std.testing.expect(!isGitFetchArgv(argv));
    try std.testing.expect(!isGitPushArgv(argv));
    try std.testing.expect(!isGitWorktreeAddArgv(argv));
    try std.testing.expect(!git_branch.isGitBranchArgv(argv));
    try std.testing.expect(std.mem.indexOf(u8, argv[2], "feat/composer") == null);

    try std.testing.expect(checkoutArgvFor("/tmp/faku-co", "not a branch", &buf) == null);
    try std.testing.expect(checkoutArgvFor("/tmp/faku-co", "../escape", &buf) == null);
    try std.testing.expect(checkoutArgvFor("/tmp/faku-co", "/abs", &buf) == null);
    try std.testing.expect(checkoutArgvFor("/tmp/faku-co", ".hidden", &buf) == null);
    try std.testing.expect(checkoutArgvFor("/tmp/faku-co", "trailing.", &buf) == null);
    try std.testing.expect(checkoutArgvFor("/tmp/faku-co", "@", &buf) == null);
    try std.testing.expect(checkoutArgvFor("/tmp/faku-co", "foo@{bar", &buf) == null);
    try std.testing.expect(checkoutArgvFor("/tmp/faku-co", "", &buf) == null);
    try std.testing.expect(git_checkout_key_first > git_branch_list_key_first);
    try std.testing.expect(git_create_key_first > git_checkout_key_first);
    try std.testing.expect(git_branch_list_key_first > git_branch.git_branch_key_first);
    try std.testing.expect(git_dirty.git_dirty_key_first > git_create_key_first);
    try std.testing.expect(git_delete_key_first > git_dirty.git_dirty_key_first);
    try std.testing.expect(git_fetch_key_first > git_delete_key_first);
    try std.testing.expect(git_numstat.git_numstat_key_first > git_fetch_key_first);
    try std.testing.expect(git_push_key_first > git_numstat.git_numstat_key_first);
    try std.testing.expect(git_worktree_add_key_first > git_push_key_first);
    try std.testing.expect(git_ahead_behind.git_ahead_behind_key_first > git_worktree_add_key_first);
    try std.testing.expect(file_mention.file_mention_key_first > git_ahead_behind.git_ahead_behind_key_first);
}

test "track checkout argv is checkout --track with the name as its own slot and rejects implausible names" {
    var buf: [track_checkout_argv_len][]const u8 = undefined;
    const argv = trackCheckoutArgvFor("/tmp/faku-track", "origin/feat", &buf).?;
    try std.testing.expectEqualStrings(sh_bin, argv[0]);
    try std.testing.expectEqualStrings("-c", argv[1]);
    try std.testing.expectEqualStrings(main.fx_ask_chdir_script, argv[2]);
    try std.testing.expectEqualStrings("sh", argv[3]);
    try std.testing.expectEqualStrings("/tmp/faku-track", argv[4]);
    try std.testing.expectEqualStrings(git_bin, argv[5]);
    try std.testing.expectEqualStrings(git_checkout_cmd, argv[6]);
    try std.testing.expectEqualStrings(git_track_flag, argv[7]);
    try std.testing.expectEqualStrings("origin/feat", argv[8]);
    try std.testing.expect(isGitTrackCheckoutArgv(argv));
    try std.testing.expect(!isGitCheckoutArgv(argv));
    try std.testing.expect(!isGitCreateArgv(argv));
    try std.testing.expect(!isGitBranchListArgv(argv));
    try std.testing.expect(!isGitDeleteArgv(argv));
    try std.testing.expect(!isGitFetchArgv(argv));
    try std.testing.expect(!isGitPushArgv(argv));
    try std.testing.expect(!isGitWorktreeAddArgv(argv));
    try std.testing.expect(!git_branch.isGitBranchArgv(argv));
    try std.testing.expect(std.mem.indexOf(u8, argv[2], "origin/feat") == null);
    try std.testing.expect(std.mem.indexOf(u8, argv[2], "--track") == null);

    try std.testing.expect(trackCheckoutArgvFor("/tmp/faku-track", "not a branch", &buf) == null);
    try std.testing.expect(trackCheckoutArgvFor("/tmp/faku-track", "../escape", &buf) == null);
    try std.testing.expect(trackCheckoutArgvFor("/tmp/faku-track", "/abs", &buf) == null);
    try std.testing.expect(trackCheckoutArgvFor("/tmp/faku-track", ".hidden", &buf) == null);
    try std.testing.expect(trackCheckoutArgvFor("/tmp/faku-track", "trailing.", &buf) == null);
    try std.testing.expect(trackCheckoutArgvFor("/tmp/faku-track", "@", &buf) == null);
    try std.testing.expect(trackCheckoutArgvFor("/tmp/faku-track", "foo@{bar", &buf) == null);
    try std.testing.expect(trackCheckoutArgvFor("/tmp/faku-track", "", &buf) == null);
}

test "create argv is checkout -b with the name as its own slot and rejects implausible names" {
    var buf: [create_argv_len][]const u8 = undefined;
    const argv = createArgvFor("/tmp/faku-new", "feat/new-branch", &buf).?;
    try std.testing.expectEqualStrings(sh_bin, argv[0]);
    try std.testing.expectEqualStrings("-c", argv[1]);
    try std.testing.expectEqualStrings(main.fx_ask_chdir_script, argv[2]);
    try std.testing.expectEqualStrings("sh", argv[3]);
    try std.testing.expectEqualStrings("/tmp/faku-new", argv[4]);
    try std.testing.expectEqualStrings(git_bin, argv[5]);
    try std.testing.expectEqualStrings(git_checkout_cmd, argv[6]);
    try std.testing.expectEqualStrings(git_create_b_flag, argv[7]);
    try std.testing.expectEqualStrings("feat/new-branch", argv[8]);
    try std.testing.expect(isGitCreateArgv(argv));
    try std.testing.expect(!isGitCheckoutArgv(argv));
    try std.testing.expect(!isGitTrackCheckoutArgv(argv));
    try std.testing.expect(!isGitBranchListArgv(argv));
    try std.testing.expect(!isGitDeleteArgv(argv));
    try std.testing.expect(!isGitFetchArgv(argv));
    try std.testing.expect(!isGitPushArgv(argv));
    try std.testing.expect(!isGitWorktreeAddArgv(argv));
    try std.testing.expect(!git_branch.isGitBranchArgv(argv));
    try std.testing.expect(std.mem.indexOf(u8, argv[2], "feat/new-branch") == null);

    try std.testing.expect(createArgvFor("/tmp/faku-new", "not a branch", &buf) == null);
    try std.testing.expect(createArgvFor("/tmp/faku-new", "../escape", &buf) == null);
    try std.testing.expect(createArgvFor("/tmp/faku-new", "/abs", &buf) == null);
    try std.testing.expect(createArgvFor("/tmp/faku-new", ".hidden", &buf) == null);
    try std.testing.expect(createArgvFor("/tmp/faku-new", "trailing.", &buf) == null);
    try std.testing.expect(createArgvFor("/tmp/faku-new", "@", &buf) == null);
    try std.testing.expect(createArgvFor("/tmp/faku-new", "foo@{bar", &buf) == null);
    try std.testing.expect(createArgvFor("/tmp/faku-new", "", &buf) == null);
}

test "delete argv is branch -d with the name as its own slot and rejects implausible names" {
    var buf: [delete_argv_len][]const u8 = undefined;
    const argv = deleteArgvFor("/tmp/faku-del", "feat/old-branch", &buf).?;
    try std.testing.expectEqualStrings(sh_bin, argv[0]);
    try std.testing.expectEqualStrings("-c", argv[1]);
    try std.testing.expectEqualStrings(main.fx_ask_chdir_script, argv[2]);
    try std.testing.expectEqualStrings("sh", argv[3]);
    try std.testing.expectEqualStrings("/tmp/faku-del", argv[4]);
    try std.testing.expectEqualStrings(git_bin, argv[5]);
    try std.testing.expectEqualStrings(git_branch_cmd, argv[6]);
    try std.testing.expectEqualStrings(git_delete_d_flag, argv[7]);
    try std.testing.expectEqualStrings("feat/old-branch", argv[8]);
    try std.testing.expect(isGitDeleteArgv(argv));
    try std.testing.expect(!isGitCreateArgv(argv));
    try std.testing.expect(!isGitCheckoutArgv(argv));
    try std.testing.expect(!isGitTrackCheckoutArgv(argv));
    try std.testing.expect(!isGitBranchListArgv(argv));
    try std.testing.expect(!isGitFetchArgv(argv));
    try std.testing.expect(!isGitPushArgv(argv));
    try std.testing.expect(!isGitWorktreeAddArgv(argv));
    try std.testing.expect(!git_branch.isGitBranchArgv(argv));
    try std.testing.expect(std.mem.indexOf(u8, argv[2], "feat/old-branch") == null);
    try std.testing.expect(!std.mem.eql(u8, argv[7], "-D"));

    try std.testing.expect(deleteArgvFor("/tmp/faku-del", "not a branch", &buf) == null);
    try std.testing.expect(deleteArgvFor("/tmp/faku-del", "../escape", &buf) == null);
    try std.testing.expect(deleteArgvFor("/tmp/faku-del", "/abs", &buf) == null);
    try std.testing.expect(deleteArgvFor("/tmp/faku-del", ".hidden", &buf) == null);
    try std.testing.expect(deleteArgvFor("/tmp/faku-del", "trailing.", &buf) == null);
    try std.testing.expect(deleteArgvFor("/tmp/faku-del", "@", &buf) == null);
    try std.testing.expect(deleteArgvFor("/tmp/faku-del", "foo@{bar", &buf) == null);
    try std.testing.expect(deleteArgvFor("/tmp/faku-del", "", &buf) == null);
    try std.testing.expect(!isGitDeleteArgv(&.{
        sh_bin,
        "-c",
        main.fx_ask_chdir_script,
        "sh",
        "/tmp/faku-del",
        git_bin,
        git_branch_cmd,
        "-D",
        "feat/old-branch",
    }));
}

test "fetch argv is fetch --prune as its own slot and is not fetch-without-prune" {
    var buf: [fetch_argv_len][]const u8 = undefined;
    const argv = fetchArgvFor("/tmp/faku-fetch", &buf);
    try std.testing.expectEqualStrings(sh_bin, argv[0]);
    try std.testing.expectEqualStrings("-c", argv[1]);
    try std.testing.expectEqualStrings(main.fx_ask_chdir_script, argv[2]);
    try std.testing.expectEqualStrings("sh", argv[3]);
    try std.testing.expectEqualStrings("/tmp/faku-fetch", argv[4]);
    try std.testing.expectEqualStrings(git_bin, argv[5]);
    try std.testing.expectEqualStrings(git_fetch_cmd, argv[6]);
    try std.testing.expectEqualStrings(git_prune_flag, argv[7]);
    try std.testing.expect(isGitFetchArgv(argv));
    try std.testing.expect(!isGitPushArgv(argv));
    try std.testing.expect(!isGitDeleteArgv(argv));
    try std.testing.expect(!isGitCreateArgv(argv));
    try std.testing.expect(!isGitCheckoutArgv(argv));
    try std.testing.expect(!isGitTrackCheckoutArgv(argv));
    try std.testing.expect(!isGitBranchListArgv(argv));
    try std.testing.expect(!isGitWorktreeAddArgv(argv));
    try std.testing.expect(!git_branch.isGitBranchArgv(argv));
    try std.testing.expect(std.mem.indexOf(u8, argv[2], git_fetch_cmd) == null);
    try std.testing.expect(std.mem.indexOf(u8, argv[2], git_prune_flag) == null);
    try std.testing.expect(!isGitFetchArgv(&.{
        sh_bin,
        "-c",
        main.fx_ask_chdir_script,
        "sh",
        "/tmp/faku-fetch",
        git_bin,
        git_fetch_cmd,
    }));
    try std.testing.expect(!isGitFetchArgv(&.{
        sh_bin,
        "-c",
        main.fx_ask_chdir_script,
        "sh",
        "/tmp/faku-fetch",
        git_bin,
        git_fetch_cmd,
        "-p",
    }));
    try std.testing.expect(!isGitFetchArgv(&.{
        sh_bin,
        "-c",
        main.fx_ask_chdir_script,
        "sh",
        "/tmp/faku-fetch",
        git_bin,
        "prune",
    }));
    try std.testing.expect(git_fetch_key_first > git_delete_key_first);
    try std.testing.expect(git_numstat.git_numstat_key_first > git_fetch_key_first);
    try std.testing.expect(git_push_key_first > git_numstat.git_numstat_key_first);
    try std.testing.expect(git_worktree_add_key_first > git_push_key_first);
    try std.testing.expect(git_ahead_behind.git_ahead_behind_key_first > git_worktree_add_key_first);
    try std.testing.expect(file_mention.file_mention_key_first > git_ahead_behind.git_ahead_behind_key_first);
}

test "push argv is git push with no extra flags and is not fetch/checkout/create/delete" {
    var buf: [push_argv_len][]const u8 = undefined;
    const argv = pushArgvFor("/tmp/faku-push", &buf);
    try std.testing.expectEqual(@as(usize, 7), argv.len);
    try std.testing.expectEqualStrings(sh_bin, argv[0]);
    try std.testing.expectEqualStrings("-c", argv[1]);
    try std.testing.expectEqualStrings(main.fx_ask_chdir_script, argv[2]);
    try std.testing.expectEqualStrings("sh", argv[3]);
    try std.testing.expectEqualStrings("/tmp/faku-push", argv[4]);
    try std.testing.expectEqualStrings(git_bin, argv[5]);
    try std.testing.expectEqualStrings(git_push_cmd, argv[6]);
    try std.testing.expect(isGitPushArgv(argv));
    try std.testing.expect(!isGitFetchArgv(argv));
    try std.testing.expect(!isGitDeleteArgv(argv));
    try std.testing.expect(!isGitCreateArgv(argv));
    try std.testing.expect(!isGitCheckoutArgv(argv));
    try std.testing.expect(!isGitTrackCheckoutArgv(argv));
    try std.testing.expect(!isGitBranchListArgv(argv));
    try std.testing.expect(!isGitWorktreeAddArgv(argv));
    try std.testing.expect(!git_branch.isGitBranchArgv(argv));
    try std.testing.expect(std.mem.indexOf(u8, argv[2], git_push_cmd) == null);
    try std.testing.expect(!isGitPushArgv(&.{
        sh_bin,
        "-c",
        main.fx_ask_chdir_script,
        "sh",
        "/tmp/faku-push",
        git_bin,
        git_fetch_cmd,
        git_prune_flag,
    }));
    try std.testing.expect(!isGitPushArgv(&.{
        sh_bin,
        "-c",
        main.fx_ask_chdir_script,
        "sh",
        "/tmp/faku-push",
        git_bin,
        git_checkout_cmd,
        "main",
    }));
    try std.testing.expect(!isGitPushArgv(&.{
        sh_bin,
        "-c",
        main.fx_ask_chdir_script,
        "sh",
        "/tmp/faku-push",
        git_bin,
        git_checkout_cmd,
        git_create_b_flag,
        "feat/new",
    }));
    try std.testing.expect(!isGitPushArgv(&.{
        sh_bin,
        "-c",
        main.fx_ask_chdir_script,
        "sh",
        "/tmp/faku-push",
        git_bin,
        git_branch_cmd,
        git_delete_d_flag,
        "feat/old",
    }));
    try std.testing.expect(!isGitPushArgv(&.{
        sh_bin,
        "-c",
        main.fx_ask_chdir_script,
        "sh",
        "/tmp/faku-push",
        git_bin,
        git_push_cmd,
        "--set-upstream",
    }));
    try std.testing.expect(!isGitSetUpstreamPushArgv(argv));
    try std.testing.expect(!isGitUpstreamArgv(argv));
    try std.testing.expect(!isGitRemoteArgv(argv));
    try std.testing.expect(git_push_key_first > git_numstat.git_numstat_key_first);
    try std.testing.expect(git_worktree_add_key_first > git_push_key_first);
    try std.testing.expect(git_ahead_behind.git_ahead_behind_key_first > git_worktree_add_key_first);
    try std.testing.expect(file_mention.file_mention_key_first > git_ahead_behind.git_ahead_behind_key_first);
}

test "worktree name sanitization refuses empty, slash, and implausible names" {
    try std.testing.expectEqualStrings("feat", sanitizeWorktreeName("feat").?);
    try std.testing.expectEqualStrings("feat-foo", sanitizeWorktreeName("  feat-foo  ").?);
    try std.testing.expect(sanitizeWorktreeName("") == null);
    try std.testing.expect(sanitizeWorktreeName("   ") == null);
    try std.testing.expect(sanitizeWorktreeName("feat/foo") == null);
    try std.testing.expect(sanitizeWorktreeName("not a branch") == null);
    try std.testing.expect(sanitizeWorktreeName("../escape") == null);
    try std.testing.expect(sanitizeWorktreeName("/abs") == null);
    try std.testing.expect(sanitizeWorktreeName(".hidden") == null);
    try std.testing.expect(sanitizeWorktreeName("trailing.") == null);
    try std.testing.expect(sanitizeWorktreeName("@") == null);
    try std.testing.expect(sanitizeWorktreeName("foo@{bar") == null);

    var branch_buf: [git_branch.max_git_branch]u8 = undefined;
    try std.testing.expectEqualStrings("faku/feat", worktreeBranchName("feat", branch_buf[0..]).?);
    try std.testing.expect(worktreeBranchName("feat/foo", branch_buf[0..]) == null);
    try std.testing.expect(worktreeBranchName("", branch_buf[0..]) == null);
}

test "worktreeNestKey is stable FNV-1a and dest nests under it" {
    var nest_buf: [worktree_nest_key_len]u8 = undefined;
    var nest_other_buf: [worktree_nest_key_len]u8 = undefined;
    try std.testing.expectEqualStrings("2599eb06cf360587", worktreeNestKey("/tmp/proj", nest_buf[0..]).?);
    try std.testing.expectEqualStrings("2599eb06cf360587", worktreeNestKey("  /tmp/proj  \n", nest_buf[0..]).?);
    try std.testing.expectEqualStrings("4793ca890685cfee", worktreeNestKey("/tmp/other", nest_other_buf[0..]).?);
    try std.testing.expect(!std.mem.eql(u8, worktreeNestKey("/tmp/proj", nest_buf[0..]).?, worktreeNestKey("/tmp/other", nest_other_buf[0..]).?));
    try std.testing.expect(worktreeNestKey("", nest_buf[0..]) == null);
    try std.testing.expect(worktreeNestKey("   \t", nest_buf[0..]) == null);
    try std.testing.expect(worktreeNestKey("..", nest_buf[0..]) == null);
    try std.testing.expect(worktreeNestKey("../escape", nest_buf[0..]) == null);
    try std.testing.expect(worktreeNestKey("/tmp/proj/../other", nest_buf[0..]) == null);
    const with_nul = "/tmp/proj\x00x";
    try std.testing.expect(worktreeNestKey(with_nul, nest_buf[0..]) == null);
    const relative = worktreeNestKey(".zig-cache/tmp/x", nest_buf[0..]).?;
    try std.testing.expectEqual(@as(usize, 16), relative.len);
    try std.testing.expectEqualStrings("884e24b2b0483c33", relative);

    var path_buf: [main.max_project_path]u8 = undefined;
    try std.testing.expectEqualStrings(
        "/home/u/.faku/worktrees/2599eb06cf360587",
        worktreeParentPath("/home/u", "/tmp/proj", path_buf[0..]).?,
    );
    try std.testing.expect(worktreeParentPath("", "/tmp/proj", path_buf[0..]) == null);
    try std.testing.expect(worktreeParentPath("relative", "/tmp/proj", path_buf[0..]) == null);
    try std.testing.expect(worktreeParentPath("/home/u", "", path_buf[0..]) == null);
    try std.testing.expect(worktreeParentPath("/home/u", "..", path_buf[0..]) == null);
    try std.testing.expectEqualStrings(
        "/home/u/.faku/worktrees/2599eb06cf360587/feat",
        worktreeDestPath("/home/u", "/tmp/proj", "feat", path_buf[0..]).?,
    );
    try std.testing.expectEqualStrings(
        "/home/u/.faku/worktrees/2599eb06cf360587/feat-2",
        worktreeDestPath("/home/u", "/tmp/proj", "feat-2", path_buf[0..]).?,
    );
    try std.testing.expectEqualStrings(
        "/home/u/.faku/worktrees/4793ca890685cfee/feat",
        worktreeDestPath("/home/u", "/tmp/other", "feat", path_buf[0..]).?,
    );
    try std.testing.expect(worktreeDestPath("/home/u", "/tmp/proj", "feat/foo", path_buf[0..]) == null);
    try std.testing.expect(worktreeDestPath("", "/tmp/proj", "feat", path_buf[0..]) == null);
    try std.testing.expect(worktreeDestPath("/home/u", "", "feat", path_buf[0..]) == null);
}

test "worktreeCandidateName matches Waku slug, slug-2, … slug-8" {
    var buf: [git_branch.max_git_branch]u8 = undefined;
    try std.testing.expectEqualStrings("feat", worktreeCandidateName("feat", 0, buf[0..]).?);
    try std.testing.expectEqualStrings("feat-2", worktreeCandidateName("feat", 1, buf[0..]).?);
    try std.testing.expectEqualStrings("feat-3", worktreeCandidateName("feat", 2, buf[0..]).?);
    try std.testing.expectEqualStrings("feat-8", worktreeCandidateName("feat", 7, buf[0..]).?);
    try std.testing.expect(worktreeCandidateName("feat", 8, buf[0..]) == null);
    try std.testing.expect(worktreeCandidateName("feat", 100, buf[0..]) == null);
    try std.testing.expectEqualStrings("feat-foo", worktreeCandidateName("  feat-foo  ", 0, buf[0..]).?);
    try std.testing.expectEqualStrings("feat-foo-2", worktreeCandidateName("  feat-foo  ", 1, buf[0..]).?);
    try std.testing.expect(worktreeCandidateName("", 0, buf[0..]) == null);
    try std.testing.expect(worktreeCandidateName("feat/foo", 0, buf[0..]) == null);
    try std.testing.expect(worktreeCandidateName("feat/foo", 1, buf[0..]) == null);
    try std.testing.expectEqual(@as(u32, 8), max_worktree_candidates);
}

test "worktreeCandidateOccupied is dest or listed local branch" {
    try std.testing.expect(!worktreeCandidateOccupied(false, false));
    try std.testing.expect(worktreeCandidateOccupied(true, false));
    try std.testing.expect(worktreeCandidateOccupied(false, true));
    try std.testing.expect(worktreeCandidateOccupied(true, true));
}

test "worktree slug lowercases, splits, caps words, and truncates" {
    var buf: [max_worktree_slug_bytes]u8 = undefined;
    try std.testing.expectEqualStrings("fix-project-worktree-picker", worktreeSlug("Fix Project/Worktree Picker!", buf[0..]));
    try std.testing.expectEqualStrings(worktree_slug_default, worktreeSlug("你好 👋", buf[0..]));
    try std.testing.expectEqualStrings(worktree_slug_default, worktreeSlug("", buf[0..]));
    try std.testing.expectEqualStrings(worktree_slug_default, worktreeSlug("   \t", buf[0..]));
    try std.testing.expectEqualStrings("worktree-add", worktreeSlug("worktree add", buf[0..]));
    try std.testing.expectEqualStrings("foo-bar-baz", worktreeSlug("foo-bar baz", buf[0..]));
    try std.testing.expectEqualStrings("one-two-three-four-five-six", worktreeSlug("one two three four five six seven", buf[0..]));
    const long = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    const truncated = worktreeSlug(long, buf[0..]);
    try std.testing.expect(truncated.len <= max_worktree_slug_bytes);
    try std.testing.expectEqual(@as(usize, 48), truncated.len);
    try std.testing.expect(truncated.len < long.len);
}

test "worktreeBaseFromSymbolicRef prefers origin local name then whole ref" {
    try std.testing.expectEqualStrings("main", worktreeBaseFromSymbolicRef("origin/main\n").?);
    try std.testing.expectEqualStrings("feat/foo", worktreeBaseFromSymbolicRef("  origin/feat/foo \n").?);
    try std.testing.expectEqualStrings("main", worktreeBaseFromSymbolicRef("main\n").?);
    try std.testing.expect(worktreeBaseFromSymbolicRef("") == null);
    try std.testing.expect(worktreeBaseFromSymbolicRef("   \n") == null);
    try std.testing.expect(worktreeBaseFromSymbolicRef("not a branch\n") == null);
}

test "worktree base argv is symbolic-ref --quiet --short origin/HEAD" {
    var buf: [worktree_base_argv_len][]const u8 = undefined;
    const argv = worktreeBaseArgvFor("/tmp/faku-wt-base", &buf);
    try std.testing.expectEqual(@as(usize, 10), argv.len);
    try std.testing.expectEqualStrings(sh_bin, argv[0]);
    try std.testing.expectEqualStrings("-c", argv[1]);
    try std.testing.expectEqualStrings(main.fx_ask_chdir_script, argv[2]);
    try std.testing.expectEqualStrings("sh", argv[3]);
    try std.testing.expectEqualStrings("/tmp/faku-wt-base", argv[4]);
    try std.testing.expectEqualStrings(git_bin, argv[5]);
    try std.testing.expectEqualStrings(git_symbolic_ref_cmd, argv[6]);
    try std.testing.expectEqualStrings(git_quiet_flag, argv[7]);
    try std.testing.expectEqualStrings(git_short_flag, argv[8]);
    try std.testing.expectEqualStrings(git_origin_head_ref, argv[9]);
    try std.testing.expect(isGitWorktreeBaseArgv(argv));
    try std.testing.expect(!isGitWorktreeAddArgv(argv));
    try std.testing.expect(!isGitUpstreamArgv(argv));
    try std.testing.expect(!git_branch.isGitBranchArgv(argv));
    try std.testing.expect(std.mem.indexOf(u8, argv[2], git_origin_head_ref) == null);
    try std.testing.expect(std.mem.indexOf(u8, argv[2], git_symbolic_ref_cmd) == null);
    try std.testing.expect(git_worktree_base_key_first > git_ahead_behind.git_ahead_behind_key_first);
    try std.testing.expect(file_mention.file_mention_key_first > git_worktree_base_key_first);
}

test "worktree add argv is mkdir+chdir plus worktree add -b with and without base" {
    var buf: [worktree_add_argv_len][]const u8 = undefined;
    var parent_buf: [main.max_project_path]u8 = undefined;
    const parent = worktreeParentPath("/home/u", "/tmp/faku-repo", parent_buf[0..]).?;
    var dest_buf: [main.max_project_path]u8 = undefined;
    const dest = worktreeDestPath("/home/u", "/tmp/faku-repo", "feat", dest_buf[0..]).?;
    try std.testing.expectEqualStrings("/home/u/.faku/worktrees/7d4ac9355fd03f74", parent);
    try std.testing.expectEqualStrings("/home/u/.faku/worktrees/7d4ac9355fd03f74/feat", dest);

    const argv = worktreeAddArgvFor(
        "/tmp/faku-repo",
        parent,
        "faku/feat",
        dest,
        "",
        &buf,
    ).?;
    try std.testing.expectEqual(@as(usize, 12), argv.len);
    try std.testing.expectEqualStrings(sh_bin, argv[0]);
    try std.testing.expectEqualStrings("-c", argv[1]);
    try std.testing.expectEqualStrings(git_worktree_mkdir_chdir_script, argv[2]);
    try std.testing.expectEqualStrings("sh", argv[3]);
    try std.testing.expectEqualStrings(parent, argv[4]);
    try std.testing.expectEqualStrings("/tmp/faku-repo", argv[5]);
    try std.testing.expectEqualStrings(git_bin, argv[6]);
    try std.testing.expectEqualStrings(git_worktree_cmd, argv[7]);
    try std.testing.expectEqualStrings(git_worktree_add_cmd, argv[8]);
    try std.testing.expectEqualStrings(git_create_b_flag, argv[9]);
    try std.testing.expectEqualStrings("faku/feat", argv[10]);
    try std.testing.expectEqualStrings(dest, argv[11]);
    try std.testing.expect(isGitWorktreeAddArgv(argv));
    try std.testing.expect(!isGitWorktreeBaseArgv(argv));
    try std.testing.expect(!isGitCreateArgv(argv));
    try std.testing.expect(!isGitCheckoutArgv(argv));
    try std.testing.expect(!isGitTrackCheckoutArgv(argv));
    try std.testing.expect(!isGitPushArgv(argv));
    try std.testing.expect(!isGitFetchArgv(argv));
    try std.testing.expect(!isGitDeleteArgv(argv));
    try std.testing.expect(!isGitBranchListArgv(argv));
    try std.testing.expect(!git_branch.isGitBranchArgv(argv));
    try std.testing.expect(std.mem.indexOf(u8, argv[2], "faku/feat") == null);
    try std.testing.expect(std.mem.indexOf(u8, argv[2], dest) == null);
    try std.testing.expect(std.mem.indexOf(u8, argv[2], "feat") == null);

    const with_base = worktreeAddArgvFor(
        "/tmp/faku-repo",
        parent,
        "faku/feat",
        dest,
        "main",
        &buf,
    ).?;
    try std.testing.expectEqual(@as(usize, 13), with_base.len);
    try std.testing.expectEqualStrings("faku/feat", with_base[10]);
    try std.testing.expectEqualStrings(dest, with_base[11]);
    try std.testing.expectEqualStrings("main", with_base[12]);
    try std.testing.expect(isGitWorktreeAddArgv(with_base));
    try std.testing.expect(std.mem.indexOf(u8, with_base[2], "main") == null);

    const origin_base = worktreeAddArgvFor(
        "/tmp/faku-repo",
        parent,
        "faku/feat",
        dest,
        "origin/main",
        &buf,
    ).?;
    try std.testing.expectEqualStrings("origin/main", origin_base[12]);
    try std.testing.expect(isGitWorktreeAddArgv(origin_base));

    try std.testing.expect(worktreeAddArgvFor("/tmp/repo", parent, "feat", dest, "", &buf) == null);
    try std.testing.expect(worktreeAddArgvFor("/tmp/repo", parent, "faku/feat/foo", dest, "", &buf) == null);
    try std.testing.expect(worktreeAddArgvFor("/tmp/repo", "relative", "faku/feat", dest, "", &buf) == null);
    try std.testing.expect(worktreeAddArgvFor("/tmp/repo", parent, "faku/feat", "/tmp/other/feat", "", &buf) == null);
    try std.testing.expect(worktreeAddArgvFor("/tmp/repo", parent, "faku/feat", "/home/u/.faku/worktrees/feat", "", &buf) == null);
    try std.testing.expect(worktreeAddArgvFor("", parent, "faku/feat", dest, "", &buf) == null);
    try std.testing.expect(worktreeAddArgvFor("/tmp/repo", parent, "faku/feat", dest, "not a branch", &buf) == null);
    try std.testing.expect(!isGitWorktreeAddArgv(&.{
        sh_bin,
        "-c",
        main.fx_ask_chdir_script,
        "sh",
        "/tmp/repo",
        git_bin,
        git_checkout_cmd,
        git_create_b_flag,
        "faku/feat",
    }));
    try std.testing.expect(git_worktree_add_key_first > git_push_key_first);
    try std.testing.expect(git_ahead_behind.git_ahead_behind_key_first > git_worktree_add_key_first);
    try std.testing.expect(git_worktree_base_key_first > git_ahead_behind.git_ahead_behind_key_first);
    try std.testing.expect(file_mention.file_mention_key_first > git_worktree_base_key_first);
}

test "handleWorktreeAddExit success retargets project_path; failure leaves it" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    const id = model.addSession("worktree dest", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath("/tmp/proj");
    try std.testing.expectEqualStrings("/tmp/proj", model.selectedProjectPath());

    model.git_worktree_add_key = git_worktree_add_key_first;
    model.git_worktree_add_probe_session = id;
    writeFixed(&model.git_worktree_add_probe_path_storage, &model.git_worktree_add_probe_path_len, "/tmp/proj");
    writeFixed(&model.git_worktree_add_dest_storage, &model.git_worktree_add_dest_len, "/home/u/.faku/worktrees/2599eb06cf360587/feat");
    model.git_worktree_create_active = true;

    const failed = handleWorktreeAddExit(&model, &fx, .{ .key = git_worktree_add_key_first, .reason = .exited, .code = 1 });
    try std.testing.expect(!failed);
    try std.testing.expectEqualStrings("/tmp/proj", model.selectedProjectPath());
    try std.testing.expectEqualStrings(worktree_add_failed_status, model.attach_status());
    try std.testing.expect(model.git_worktree_create_active);
    try std.testing.expectEqual(@as(u64, 0), model.git_worktree_add_key);
    try std.testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());

    model.clearAttachStatus();
    model.git_worktree_add_key = git_worktree_add_key_first + 1;
    model.git_worktree_add_probe_session = id;
    writeFixed(&model.git_worktree_add_probe_path_storage, &model.git_worktree_add_probe_path_len, "/tmp/proj");
    writeFixed(&model.git_worktree_add_dest_storage, &model.git_worktree_add_dest_len, "/home/u/.faku/worktrees/2599eb06cf360587/feat");
    const ok = handleWorktreeAddExit(&model, &fx, .{ .key = git_worktree_add_key_first + 1, .reason = .exited, .code = 0 });
    try std.testing.expect(ok);
    try std.testing.expectEqualStrings("/home/u/.faku/worktrees/2599eb06cf360587/feat", model.selectedProjectPath());
    try std.testing.expect(!model.git_worktree_create_active);
    try std.testing.expect(!model.has_attach_status());
    try std.testing.expectEqual(@as(u64, 0), model.git_worktree_add_key);
}

test "handleWorktreeAddExit retries slug-2 and success retargets that dest" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setHome("/home/u");
    const id = model.addSession("worktree retry", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath("/tmp/proj");

    model.git_worktree_add_key = git_worktree_add_key_first;
    model.next_git_worktree_add_key = git_worktree_add_key_first + 1;
    model.git_worktree_add_probe_session = id;
    writeFixed(&model.git_worktree_add_probe_path_storage, &model.git_worktree_add_probe_path_len, "/tmp/proj");
    writeFixed(&model.git_worktree_add_dest_storage, &model.git_worktree_add_dest_len, "/home/u/.faku/worktrees/2599eb06cf360587/feat");
    writeFixed(&model.git_worktree_add_branch_storage, &model.git_worktree_add_branch_len, "faku/feat");
    writeFixed(&model.git_worktree_add_slug_storage, &model.git_worktree_add_slug_len, "feat");
    model.git_worktree_add_attempt = 0;
    model.git_worktree_create_active = true;

    const retrying = handleWorktreeAddExit(&model, &fx, .{ .key = git_worktree_add_key_first, .reason = .exited, .code = 1 });
    try std.testing.expect(!retrying);
    try std.testing.expectEqualStrings("/tmp/proj", model.selectedProjectPath());
    try std.testing.expect(!model.has_attach_status());
    try std.testing.expect(model.git_worktree_create_active);
    try std.testing.expectEqual(git_worktree_add_key_first + 1, model.git_worktree_add_key);
    try std.testing.expectEqual(@as(u32, 1), model.git_worktree_add_attempt);
    try std.testing.expectEqualStrings("/home/u/.faku/worktrees/2599eb06cf360587/feat-2", model.git_worktree_add_dest_storage[0..model.git_worktree_add_dest_len]);
    try std.testing.expectEqualStrings("faku/feat-2", model.git_worktree_add_branch_storage[0..model.git_worktree_add_branch_len]);
    try std.testing.expectEqualStrings("feat", model.git_worktree_add_slug_storage[0..model.git_worktree_add_slug_len]);
    try std.testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());
    const spawn = fx.pendingSpawnAt(0).?;
    try std.testing.expect(isGitWorktreeAddArgv(spawn.argv));
    try std.testing.expectEqual(git_worktree_add_key_first + 1, spawn.key);
    try std.testing.expectEqualStrings("/home/u/.faku/worktrees/2599eb06cf360587", spawn.argv[4]);
    try std.testing.expectEqualStrings("faku/feat-2", spawn.argv[10]);
    try std.testing.expectEqualStrings("/home/u/.faku/worktrees/2599eb06cf360587/feat-2", spawn.argv[11]);

    const dest_two = model.git_worktree_add_dest_storage[0..model.git_worktree_add_dest_len];
    const ok = handleWorktreeAddExit(&model, &fx, .{ .key = git_worktree_add_key_first + 1, .reason = .exited, .code = 0 });
    try std.testing.expect(ok);
    try std.testing.expectEqualStrings(dest_two, model.selectedProjectPath());
    try std.testing.expectEqualStrings("/home/u/.faku/worktrees/2599eb06cf360587/feat-2", model.selectedProjectPath());
    try std.testing.expect(!model.git_worktree_create_active);
    try std.testing.expect(!model.has_attach_status());
    try std.testing.expectEqual(@as(u64, 0), model.git_worktree_add_key);
}

test "handleWorktreeAddExit sets status after the last candidate fails" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setHome("/home/u");
    const id = model.addSession("worktree exhaust", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath("/tmp/proj");

    model.git_worktree_add_key = git_worktree_add_key_first;
    model.next_git_worktree_add_key = git_worktree_add_key_first + 1;
    model.git_worktree_add_probe_session = id;
    writeFixed(&model.git_worktree_add_probe_path_storage, &model.git_worktree_add_probe_path_len, "/tmp/proj");
    writeFixed(&model.git_worktree_add_dest_storage, &model.git_worktree_add_dest_len, "/home/u/.faku/worktrees/2599eb06cf360587/feat-8");
    writeFixed(&model.git_worktree_add_branch_storage, &model.git_worktree_add_branch_len, "faku/feat-8");
    writeFixed(&model.git_worktree_add_slug_storage, &model.git_worktree_add_slug_len, "feat");
    model.git_worktree_add_attempt = max_worktree_candidates - 1;
    model.git_worktree_create_active = true;

    const exhausted = handleWorktreeAddExit(&model, &fx, .{ .key = git_worktree_add_key_first, .reason = .exited, .code = 1 });
    try std.testing.expect(!exhausted);
    try std.testing.expectEqualStrings("/tmp/proj", model.selectedProjectPath());
    try std.testing.expectEqualStrings(worktree_add_failed_status, model.attach_status());
    try std.testing.expect(model.git_worktree_create_active);
    try std.testing.expectEqual(@as(u64, 0), model.git_worktree_add_key);
    try std.testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
}

test "pickWorktreeCandidate skips listed faku/name then fails when all are taken" {
    var model = Model{};
    model.setHome("/home/u");
    model.git_branch_list_store[0].set("faku/feat", false, false);
    model.git_branch_list_count = 1;
    try std.testing.expect(pickWorktreeCandidate(&model, "/home/u", "/tmp/proj", "feat", 0));
    try std.testing.expectEqual(@as(u32, 1), model.git_worktree_add_attempt);
    try std.testing.expectEqualStrings("/home/u/.faku/worktrees/2599eb06cf360587/feat-2", model.git_worktree_add_dest_storage[0..model.git_worktree_add_dest_len]);
    try std.testing.expectEqualStrings("faku/feat-2", model.git_worktree_add_branch_storage[0..model.git_worktree_add_branch_len]);

    var i: usize = 0;
    while (i < max_worktree_candidates) : (i += 1) {
        var name_buf: [git_branch.max_git_branch]u8 = undefined;
        const name = worktreeCandidateName("feat", @intCast(i), name_buf[0..]).?;
        var branch_buf: [git_branch.max_git_branch]u8 = undefined;
        const branch = worktreeBranchName(name, branch_buf[0..]).?;
        model.git_branch_list_store[i].set(branch, false, false);
    }
    model.git_branch_list_count = max_worktree_candidates;
    try std.testing.expect(!pickWorktreeCandidate(&model, "/home/u", "/tmp/proj", "feat", 0));
}

test "startWorktreeCreate prefills a prompt slug from the session title" {
    var model = Model{};
    const id = model.addSession("worktree add", .fx);
    model.selected = id;
    startWorktreeCreate(&model);
    try std.testing.expect(model.git_worktree_create_active);
    try std.testing.expectEqualStrings("worktree-add", model.git_worktree_create());

    const empty = model.addSession("", .fx);
    model.selected = empty;
    startWorktreeCreate(&model);
    try std.testing.expectEqualStrings("new-worktree", model.git_worktree_create());

    const non_ascii = model.addSession("你好 👋", .fx);
    model.selected = non_ascii;
    startWorktreeCreate(&model);
    try std.testing.expectEqualStrings("new-worktree", model.git_worktree_create());
}

test "set-upstream push argv keeps flag, remote, and branch as their own slots" {
    var buf: [set_upstream_push_argv_len][]const u8 = undefined;
    const argv = setUpstreamPushArgvFor("/tmp/faku-push-u", "origin", "feat/new", &buf).?;
    try std.testing.expectEqual(@as(usize, 10), argv.len);
    try std.testing.expectEqualStrings(sh_bin, argv[0]);
    try std.testing.expectEqualStrings("-c", argv[1]);
    try std.testing.expectEqualStrings(main.fx_ask_chdir_script, argv[2]);
    try std.testing.expectEqualStrings("sh", argv[3]);
    try std.testing.expectEqualStrings("/tmp/faku-push-u", argv[4]);
    try std.testing.expectEqualStrings(git_bin, argv[5]);
    try std.testing.expectEqualStrings(git_push_cmd, argv[6]);
    try std.testing.expectEqualStrings(git_set_upstream_flag, argv[7]);
    try std.testing.expectEqualStrings("origin", argv[8]);
    try std.testing.expectEqualStrings("feat/new", argv[9]);
    try std.testing.expect(isGitSetUpstreamPushArgv(argv));
    try std.testing.expect(!isGitPushArgv(argv));
    try std.testing.expect(!isGitFetchArgv(argv));
    try std.testing.expect(!isGitUpstreamArgv(argv));
    try std.testing.expect(!isGitRemoteArgv(argv));
    try std.testing.expect(!git_branch.isGitBranchArgv(argv));
    try std.testing.expect(std.mem.indexOf(u8, argv[2], git_push_cmd) == null);
    try std.testing.expect(std.mem.indexOf(u8, argv[2], git_set_upstream_flag) == null);
    try std.testing.expect(std.mem.indexOf(u8, argv[2], "origin") == null);
    try std.testing.expect(std.mem.indexOf(u8, argv[2], "feat/new") == null);

    try std.testing.expect(setUpstreamPushArgvFor("/tmp/faku-push-u", "origin", "not a branch", &buf) == null);
    try std.testing.expect(setUpstreamPushArgvFor("/tmp/faku-push-u", "../escape", "main", &buf) == null);
    try std.testing.expect(setUpstreamPushArgvFor("/tmp/faku-push-u", "", "main", &buf) == null);
    try std.testing.expect(setUpstreamPushArgvFor("/tmp/faku-push-u", "origin", "", &buf) == null);
    try std.testing.expect(!isGitSetUpstreamPushArgv(&.{
        sh_bin,
        "-c",
        main.fx_ask_chdir_script,
        "sh",
        "/tmp/faku-push-u",
        git_bin,
        git_push_cmd,
        "-u",
        "origin",
        "feat/new",
    }));
    try std.testing.expect(!isGitSetUpstreamPushArgv(&.{
        sh_bin,
        "-c",
        main.fx_ask_chdir_script,
        "sh",
        "/tmp/faku-push-u",
        git_bin,
        git_push_cmd,
    }));
}

test "upstream argv is rev-parse symbolic-full-name @{upstream}" {
    var buf: [upstream_argv_len][]const u8 = undefined;
    const argv = upstreamArgvFor("/tmp/faku-up", &buf);
    try std.testing.expectEqual(@as(usize, 10), argv.len);
    try std.testing.expectEqualStrings(sh_bin, argv[0]);
    try std.testing.expectEqualStrings(main.fx_ask_chdir_script, argv[2]);
    try std.testing.expectEqualStrings("/tmp/faku-up", argv[4]);
    try std.testing.expectEqualStrings(git_bin, argv[5]);
    try std.testing.expectEqualStrings(git_rev_parse_cmd, argv[6]);
    try std.testing.expectEqualStrings(git_abbrev_ref, argv[7]);
    try std.testing.expectEqualStrings(git_symbolic_full_name, argv[8]);
    try std.testing.expectEqualStrings(git_upstream_rev, argv[9]);
    try std.testing.expect(isGitUpstreamArgv(argv));
    try std.testing.expect(!isGitPushArgv(argv));
    try std.testing.expect(!isGitSetUpstreamPushArgv(argv));
    try std.testing.expect(!git_branch.isGitRevParseArgv(argv));
    try std.testing.expect(std.mem.indexOf(u8, argv[2], git_upstream_rev) == null);
}

test "remote argv is git remote and is not bare push" {
    var buf: [remote_argv_len][]const u8 = undefined;
    const argv = remoteArgvFor("/tmp/faku-remote", &buf);
    try std.testing.expectEqual(@as(usize, 7), argv.len);
    try std.testing.expectEqualStrings(git_remote_cmd, argv[6]);
    try std.testing.expect(isGitRemoteArgv(argv));
    try std.testing.expect(!isGitPushArgv(argv));
    try std.testing.expect(!isGitSetUpstreamPushArgv(argv));
    try std.testing.expect(!isGitUpstreamArgv(argv));
    try std.testing.expect(!isGitFetchArgv(argv));
}

test "pickRemoteName prefers origin then first plausible name" {
    try std.testing.expectEqualStrings("origin", pickRemoteName("upstream\norigin\n"));
    try std.testing.expectEqualStrings("origin", pickRemoteName("origin\nfoo\n"));
    try std.testing.expectEqualStrings("origin", pickRemoteName("foo\nbar\norigin\n"));
    try std.testing.expectEqualStrings("upstream", pickRemoteName("upstream\n"));
    try std.testing.expectEqualStrings("upstream", pickRemoteName("  upstream \n\n"));
    try std.testing.expectEqualStrings("", pickRemoteName(""));
    try std.testing.expectEqualStrings("", pickRemoteName("   \n\n"));
    try std.testing.expectEqualStrings("", pickRemoteName("not a remote\n../escape\n"));
}

test "stdoutHasUpstream and pushBranchFromLabel decide the push path" {
    try std.testing.expect(stdoutHasUpstream("origin/main\n"));
    try std.testing.expect(stdoutHasUpstream("  origin/feat/foo \n"));
    try std.testing.expect(!stdoutHasUpstream(""));
    try std.testing.expect(!stdoutHasUpstream("   \n"));
    try std.testing.expect(!stdoutHasUpstream("\n"));

    try std.testing.expectEqualStrings("main", pushBranchFromLabel("main").?);
    try std.testing.expectEqualStrings("feat/foo", pushBranchFromLabel("feat/foo").?);
    try std.testing.expect(pushBranchFromLabel("") == null);
    try std.testing.expect(pushBranchFromLabel("not a branch") == null);
    try std.testing.expect(pushBranchFromLabel("a1b2c3d") == null);
    try std.testing.expect(pushBranchFromLabel("DEADBEEF") == null);
}

test "collectStdoutRefs skips remote HEAD, de-dupes local counterparts, and caps remotes" {
    var refs: [max_listed_branches]ParsedRef = undefined;
    const raw =
        \\  refs/heads/zeta 
        \\
        \\refs/heads/main
        \\not a branch
        \\../escape
        \\refs/heads/feat/a
        \\refs/remotes/origin/HEAD
        \\refs/remotes/origin/main
        \\refs/remotes/origin/feat/a
        \\refs/remotes/origin/feat/foo
        \\refs/heads/feat/foo
        \\refs/remotes/origin/only
        \\refs/remotes/upstream/other
        \\
    ;
    const n = collectStdoutRefs(raw, "", refs[0..]);
    try std.testing.expectEqual(@as(usize, 6), n);
    try std.testing.expectEqualStrings("feat/a", refs[0].name);
    try std.testing.expect(!refs[0].remote);
    try std.testing.expect(!refs[0].occupied);
    try std.testing.expectEqualStrings("feat/foo", refs[1].name);
    try std.testing.expect(!refs[1].remote);
    try std.testing.expect(!refs[1].occupied);
    try std.testing.expectEqualStrings("main", refs[2].name);
    try std.testing.expect(!refs[2].remote);
    try std.testing.expect(!refs[2].occupied);
    try std.testing.expectEqualStrings("origin/only", refs[3].name);
    try std.testing.expect(refs[3].remote);
    try std.testing.expect(!refs[3].occupied);
    try std.testing.expectEqualStrings("upstream/other", refs[4].name);
    try std.testing.expect(refs[4].remote);
    try std.testing.expect(!refs[4].occupied);
    try std.testing.expectEqualStrings("zeta", refs[5].name);
    try std.testing.expect(!refs[5].remote);
    try std.testing.expect(!refs[5].occupied);

    try std.testing.expectEqual(@as(usize, 0), collectStdoutRefs("   \n\n", "", refs[0..]));
    try std.testing.expectEqual(@as(usize, 0), collectStdoutRefs("", "", refs[0..]));
    try std.testing.expectEqual(@as(usize, 0), collectStdoutRefs("main\nfeat/a\norigin/feat\n", "", refs[0..]));
    try std.testing.expect(classifyRefname("refs/remotes/origin/HEAD") == null);
    try std.testing.expect(classifyRefname("refs/remotes/HEAD") == null);
    try std.testing.expectEqualStrings("feat", remoteLocalCounterpart("origin/feat"));
    try std.testing.expectEqualStrings("feat/foo", remoteLocalCounterpart("origin/feat/foo"));

    var tiny: [1]ParsedRef = undefined;
    const capped = collectStdoutRefs("refs/heads/c\nrefs/heads/b\nrefs/heads/a\n", "", tiny[0..]);
    try std.testing.expectEqual(@as(usize, 1), capped);
    try std.testing.expectEqualStrings("c", tiny[0].name);

    var remote_model = Model{};
    var i: usize = 0;
    while (i < max_remote_branches + 1) : (i += 1) {
        var line_buf: [64]u8 = undefined;
        const line = std.fmt.bufPrint(&line_buf, "refs/remotes/origin/r{d}\n", .{i}) catch unreachable;
        applyStdoutBranches(&remote_model, line);
    }
    try std.testing.expectEqual(@as(u32, max_remote_branches), remote_model.git_branch_list_count);
}

test "finalizeListedBranches drops remotes after a later local counterpart arrives" {
    var model = Model{};
    applyStdoutBranches(&model, "refs/remotes/origin/feat\nrefs/remotes/origin/HEAD\n");
    try std.testing.expectEqual(@as(u32, 1), model.git_branch_list_count);
    try std.testing.expectEqualStrings("origin/feat", listedBranch(&model, 0));
    try std.testing.expect(listedBranchIsRemote(&model, 0));
    applyStdoutBranches(&model, "refs/heads/feat\n");
    try std.testing.expectEqual(@as(u32, 2), model.git_branch_list_count);
    finalizeListedBranches(&model);
    try std.testing.expectEqual(@as(u32, 1), model.git_branch_list_count);
    try std.testing.expectEqualStrings("feat", listedBranch(&model, 0));
    try std.testing.expect(!listedBranchIsRemote(&model, 0));
    try std.testing.expect(!listedBranchIsOccupied(&model, 0));
    try std.testing.expect(!isListedRemoteName(&model, "origin/feat"));
}

const OccupancyCase = struct {
    raw: []const u8,
    project_path: []const u8,
    name: []const u8,
    remote: bool,
    occupied: bool,
};

test "collectStdoutRefs occupancy is local-only via project_path heuristic" {
    const cases = [_]OccupancyCase{
        .{ .raw = "refs/heads/main\x00\n", .project_path = "/tmp/proj", .name = "main", .remote = false, .occupied = false },
        .{ .raw = "refs/heads/main\n", .project_path = "/tmp/proj", .name = "main", .remote = false, .occupied = false },
        .{ .raw = "refs/heads/occupied\x00/tmp/other-worktree\n", .project_path = "/tmp/proj", .name = "occupied", .remote = false, .occupied = true },
        .{ .raw = "refs/heads/feat\x00/tmp/proj\n", .project_path = "/tmp/proj", .name = "feat", .remote = false, .occupied = false },
        .{ .raw = "refs/heads/feat\x00/tmp/proj\n", .project_path = "/tmp/proj/src", .name = "feat", .remote = false, .occupied = false },
        .{ .raw = "refs/remotes/origin/occupied\x00/whatever\n", .project_path = "/tmp/proj", .name = "origin/occupied", .remote = true, .occupied = false },
    };
    var refs: [max_listed_branches]ParsedRef = undefined;
    for (cases) |case| {
        const n = collectStdoutRefs(case.raw, case.project_path, refs[0..]);
        try std.testing.expectEqual(@as(usize, 1), n);
        try std.testing.expectEqualStrings(case.name, refs[0].name);
        try std.testing.expectEqual(case.remote, refs[0].remote);
        try std.testing.expectEqual(case.occupied, refs[0].occupied);
    }

    const mixed =
        "refs/heads/main\x00\n" ++
        "refs/heads/occupied\x00/tmp/other-worktree\n" ++
        "refs/heads/feat\x00/tmp/proj\n" ++
        "refs/remotes/origin/HEAD\x00/tmp/proj\n" ++
        "refs/remotes/origin/main\x00/tmp/proj\n" ++
        "refs/remotes/origin/occupied\x00/whatever\n" ++
        "refs/remotes/origin/only\x00/whatever\n";
    const n = collectStdoutRefs(mixed, "/tmp/proj", refs[0..]);
    try std.testing.expectEqual(@as(usize, 4), n);
    try std.testing.expectEqualStrings("feat", refs[0].name);
    try std.testing.expect(!refs[0].remote);
    try std.testing.expect(!refs[0].occupied);
    try std.testing.expectEqualStrings("main", refs[1].name);
    try std.testing.expect(!refs[1].remote);
    try std.testing.expect(!refs[1].occupied);
    try std.testing.expectEqualStrings("occupied", refs[2].name);
    try std.testing.expect(!refs[2].remote);
    try std.testing.expect(refs[2].occupied);
    try std.testing.expectEqualStrings("origin/only", refs[3].name);
    try std.testing.expect(refs[3].remote);
    try std.testing.expect(!refs[3].occupied);

    const sub = collectStdoutRefs("refs/heads/feat\x00/tmp/proj\n", "/tmp/proj/src", refs[0..]);
    try std.testing.expectEqual(@as(usize, 1), sub);
    try std.testing.expect(!refs[0].occupied);

    var model = Model{};
    const id = model.addSession("occupancy", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath("/tmp/proj");
    applyStdoutBranches(&model, mixed);
    try std.testing.expectEqual(@as(u32, 4), model.git_branch_list_count);
    try std.testing.expectEqualStrings("feat", listedBranch(&model, 0));
    try std.testing.expect(!listedBranchIsOccupied(&model, 0));
    try std.testing.expectEqualStrings("main", listedBranch(&model, 1));
    try std.testing.expect(!listedBranchIsOccupied(&model, 1));
    try std.testing.expectEqualStrings("occupied", listedBranch(&model, 2));
    try std.testing.expect(listedBranchIsOccupied(&model, 2));
    try std.testing.expectEqualStrings("origin/only", listedBranch(&model, 3));
    try std.testing.expect(listedBranchIsRemote(&model, 3));
    try std.testing.expect(!listedBranchIsOccupied(&model, 3));
    try std.testing.expect(listedLocalNameIsOccupied(&model, "occupied"));
    try std.testing.expect(!listedLocalNameIsOccupied(&model, "feat"));
}

test "pickBranch refuses occupied locals and no-ops the current name" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.git_branch_list_store[0].set("feat", false, false);
    model.git_branch_list_store[1].set("main", false, false);
    model.git_branch_list_store[2].set("occupied", false, true);
    model.git_branch_list_count = 3;
    writeFixed(&model.git_branch_storage, &model.git_branch_len, "main");

    pickBranch(&model, &fx, "occupied");
    try std.testing.expectEqual(@as(u64, 0), model.git_checkout_key);
    try std.testing.expectEqualStrings(occupied_checkout_status, model.attach_status());
    try std.testing.expect(model.has_attach_status());

    model.clearAttachStatus();
    pickBranch(&model, &fx, "main");
    try std.testing.expectEqual(@as(u64, 0), model.git_checkout_key);
    try std.testing.expect(!model.has_attach_status());

    model.git_branch_list_store[1].set("main", false, true);
    pickBranch(&model, &fx, "main");
    try std.testing.expectEqual(@as(u64, 0), model.git_checkout_key);
    try std.testing.expect(!model.has_attach_status());
}

test "delete rows omit occupied locals" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var model = Model{};
    model.git_branch_list_store[0].set("feat", false, false);
    model.git_branch_list_store[1].set("main", false, false);
    model.git_branch_list_store[2].set("occupied", false, true);
    model.git_branch_list_store[3].set("origin/only", true, false);
    model.git_branch_list_count = 4;
    writeFixed(&model.git_branch_storage, &model.git_branch_len, "main");

    try std.testing.expect(canDeleteGitBranch(&model));
    const rows = model.git_branch_delete_rows(arena);
    try std.testing.expectEqual(@as(usize, 1), rows.len);
    try std.testing.expectEqualStrings("feat", rows[0].id);
    try std.testing.expectEqualStrings("feat", rows[0].label);

    pickDeleteName(&model, "occupied");
    try std.testing.expectEqualStrings("", gitBranchDeleteLabel(&model));
    pickDeleteName(&model, "origin/only");
    try std.testing.expectEqualStrings("", gitBranchDeleteLabel(&model));
    pickDeleteName(&model, "feat");
    try std.testing.expectEqualStrings("feat", gitBranchDeleteLabel(&model));

    const picker = model.git_branch_picker_rows(arena);
    try std.testing.expectEqual(@as(usize, 4), picker.len);
    try std.testing.expectEqualStrings("feat", picker[0].id);
    try std.testing.expectEqualStrings("feat", picker[0].label);
    try std.testing.expectEqualStrings("occupied", picker[2].id);
    try std.testing.expectEqualStrings("occupied (worktree)", picker[2].label);
    try std.testing.expectEqualStrings("origin/only", picker[3].id);
    try std.testing.expectEqualStrings("origin/only", picker[3].label);

    model.git_branch_list_store[0].set("occupied", false, true);
    model.git_branch_list_store[1].set("main", false, false);
    model.git_branch_list_count = 2;
    try std.testing.expect(!canDeleteGitBranch(&model));
    const none = model.git_branch_delete_rows(arena);
    try std.testing.expectEqual(@as(usize, 0), none.len);
}

test "beginPushAfterCommit starts the upstream probe when canPushGitBranch is false" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/git-begin-push", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("begin push", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);
    model.git_ahead_behind_ready = true;
    model.git_ahead_behind_has_upstream = true;
    model.git_ahead_behind_ahead = 0;
    try std.testing.expect(!git_ahead_behind.canPushGitBranch(&model));

    startPush(&model, &fx);
    try std.testing.expectEqual(@as(u64, 0), model.git_push_key);
    try std.testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());

    beginPushAfterCommit(&model, &fx);
    try std.testing.expect(model.git_push_key >= git_push_key_first);
    try std.testing.expectEqual(GitPushPhase.upstream, model.git_push_phase);
    try std.testing.expect(!model.has_attach_status());
    const spawn = fx.pendingSpawnAt(0).?;
    try std.testing.expect(isGitUpstreamArgv(spawn.argv));
    try std.testing.expectEqual(model.git_push_key, spawn.key);
}

test "beginPushAfterCommit sets Could not push when cwd is missing" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    const id = model.addSession("begin push no cwd", .fx);
    model.selected = id;
    model.git_commit_active = true;
    beginPushAfterCommit(&model, &fx);
    try std.testing.expectEqual(@as(u64, 0), model.git_push_key);
    try std.testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
    try std.testing.expectEqualStrings(push_failed_status, model.attach_status());
    try std.testing.expect(!model.git_commit_active);
}

test "startPush does not require an open commit card and closes one if open" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/git-menu-push", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("menu push", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);
    model.git_ahead_behind_ready = true;
    model.git_ahead_behind_has_upstream = true;
    model.git_ahead_behind_ahead = 1;
    try std.testing.expect(git_ahead_behind.canPushGitBranch(&model));
    try std.testing.expect(!model.git_commit_active);

    startPush(&model, &fx);
    try std.testing.expect(model.git_push_key >= git_push_key_first);
    try std.testing.expectEqual(GitPushPhase.upstream, model.git_push_phase);
    try std.testing.expect(!model.git_commit_active);
    try std.testing.expect(!model.has_git_commit_pushing());

    model.git_push_key = 0;
    model.git_push_phase = .idle;
    model.git_commit_active = true;
    startPush(&model, &fx);
    try std.testing.expect(!model.git_commit_active);
    try std.testing.expect(!model.has_git_commit_pushing());
    try std.testing.expect(model.git_push_key >= git_push_key_first);
}

test "beginPushAfterCommit keeps an open commit card until push exit" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/git-begin-push-card", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("begin push card", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);
    model.git_ahead_behind_ready = true;
    model.git_ahead_behind_has_upstream = true;
    model.git_ahead_behind_ahead = 0;
    try std.testing.expect(!git_ahead_behind.canPushGitBranch(&model));
    model.git_commit_active = true;

    beginPushAfterCommit(&model, &fx);
    try std.testing.expect(model.git_commit_active);
    try std.testing.expect(model.has_git_commit_pushing());
    try std.testing.expect(model.git_push_key >= git_push_key_first);
    const key = model.git_push_key;
    applyPushLine(&model, .{ .key = key, .line = "origin/main\n" });
    handlePushExit(&model, &fx, .{ .key = key, .reason = .exited, .code = 0 });
    try std.testing.expect(model.git_commit_active);
    try std.testing.expectEqual(GitPushPhase.push, model.git_push_phase);
    const push = model.git_push_key;
    handlePushExit(&model, &fx, .{ .key = push, .reason = .exited, .code = 1 });
    try std.testing.expect(!model.git_commit_active);
    try std.testing.expect(!model.has_git_commit_pushing());
    try std.testing.expectEqualStrings(push_failed_status, model.attach_status());
}
