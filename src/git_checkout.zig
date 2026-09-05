//! First-cut local + remote-tracking branch list, checkout, create,
//! safe/force delete, fetch, push, and New worktree… for the composer
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
//! delete. Remotes are never occupied. Empty `%(worktreepath)`
//! is not occupied. Ready toplevel compares `worktreepath` equal to
//! that root; otherwise today's path-prefix heuristic.
//! Checking out a listed local name one-shots `git checkout <name>`
//! with that name as its own argv slot — never interpolated into the
//! `-c` script. A listed remote-tracking name one-shots
//! `git checkout --track <name>` the same way (`--track` and the name
//! each their own slot; same checkout key band). New branch…
//! one-shots `git checkout -b <name>` from current HEAD. Delete
//! branch… one-shots `git branch -d <name>` (or `git branch -D
//! <name>` when the first-cut Force ghost toggle is on) for listed
//! local heads that are not occupied (never `origin/…`; Force is
//! runtime-only, default off, reset when the card opens, not
//! persisted; `-d` / `-D` each their own argv slot).
//! Fetch… one-shots `git fetch --prune` (`--prune` its own argv
//! slot; never interpolated into the `-c` script). Push… is offered
//! only when Waku `can_push` would be true: ahead of `@{upstream}`,
//! or the ahead/behind probe failed / that name does not exist
//! and a remotes probe found at least one remote (first-push
//! `--set-upstream` path). Hidden while those probes are in flight
//! and when it resolved an upstream with ahead 0. Failed / empty
//! remotes on the no-upstream path hide Push…. Menu Push… opens a
//! first-cut confirm row (ghost Force + Push + Cancel; same card UX
//! as Delete branch…). Force is runtime-only, default off, reset
//! when that confirm or Commit… opens, not persisted. Confirm keeps
//! today's gates and probes `@{upstream}`, then one-shots `git push`
//! when that name exists (`push` its own argv slot). When there is
//! no upstream it one-shots
//! `git push --set-upstream <remote> <branch>`
//! (`--set-upstream`, remote, and branch each their own argv slot;
//! remote prefers `origin` from `git remote`, else the first name).
//! When Force is on, `--force` is its own argv slot after `push`
//! (before `--set-upstream` / remote / branch). Off matches today's
//! non-force push exactly. Commit… in-dialog Push and Commit and
//! Push honor the same Force toggle. Detached HEAD or no remotes
//! set a short composer status and do not spawn a push. New worktree… prefills the runtime-only card
//! from a prompt slug of the selected session title (empty /
//! non-ascii-only → `new-worktree`; user can still edit). A first-cut
//! ghost Base control on that card picks a listed unoccupied local
//! head as the worktree start-point (runtime-only override on that
//! card; remotes and occupied locals are omitted, same refusal
//! as checkout/delete; reset when the card opens or is cancelled
//! unless the selected session is already a Work-in `newWorktree`
//! draft). Confirm uses that override as the trailing `git worktree add -b
//! … <path> <base>` argv slot when it is non-empty (own slot; skip
//! the origin/HEAD probe). Composer Work-in Base on a `newWorktree`
//! draft writes the same override and persists camelCase `baseBranch`
//! on `sessions.json` (Waku `NewWorktree { base_branch }`; omitted
//! when empty). Send prep / `beginWorktreeAdd` prefer that stored
//! base for the trailing argv slot the same way a runtime override
//! does. When the override / stored base is empty, confirm
//! probes `git symbolic-ref --quiet --short refs/remotes/origin/HEAD`
//! (chdir script; no interpolation; key band 390+) then one-shots
//! `git worktree add -b faku/<name> <path>` with that default base
//! as its own trailing argv slot when one resolves (`-b`, the
//! branch, the path, and the optional base each their own slot;
//! `mkdir -p` of `~/.faku/worktrees/<nest>` via a fixed script and
//! the parent as an argv slot). Windows cannot use `/bin/sh`:
//! `powershell.exe -NoProfile -Command {scriptblock} -Args` with
//! parent, cwd, `git.exe`, `worktree`, `add`, `-b`, branch, dest,
//! and optional base each their own argv slot (paths never inside
//! the scriptblock). `origin/<name>` prefers `<name>`
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
//! `{project_id}`). Stored dest/parent slash-normalize `\` to `/`
//! so nest FNV + dest identity is stable on Windows drive-letter
//! homes (`USERPROFILE`). A taken dest
//! directory or listed local
//! `faku/<name>` skips to the next Waku candidate (`slug`,
//! `slug-2`, … `slug-8`; cap 8 because Native is one-shot, not
//! Waku's 100 + session-id hex). A failed `worktree add` retries
//! the next free candidate the same way. Exhausted candidates set
//! status and leave `project_path` alone. Success retargets the
//! selected session `project_path` to the dest actually used. Not
//! daemon `WorkspaceOperation::Push` / `NewWorktree`, not
//! `InspectCommit` / `Commit`. Cap is 64 local heads plus 32
//! remote-tracking names that have no local counterpart (skip
//! symbolic `*/HEAD`), sorted lexicographically. Not Waku's daemon
//! `InspectBranches` picker, live watch, `waku/` prefix /
//! `~/.waku/worktrees/{project_id}` UUID nest. Composer Push… still
//! closes any open Commit… card; a push started from that card
//! keeps it open with in-dialog Pushing… until the push ends.
//! Leftovers: daemon `WorkspaceOperation`. Fetch
//! already `--prune`; there is no prune-alone menu (not in Waku).
//! First-cut defer-until-Send Work in reuses this same add path on
//! Send (`session_workspace`); optional `baseBranch` persist ships
//! on that draft. The branch-menu New worktree… card still creates
//! immediately.
//!
//! Unix uses the same `/bin/sh -c` chdir workaround `fx ask` uses
//! (`fx_ask_chdir_script`). Windows cannot use `/bin/sh`:
//! `git.exe -C <project_path>` (path is its own argv slot, not
//! interpolated into a script). Explicit `git.exe` like siblings.
//! List is `git.exe -C PATH for-each-ref --format=%(refname)%00%(worktreepath) refs/heads refs/remotes`;
//! checkout is `git.exe -C PATH checkout <name>`; track is
//! `git.exe -C PATH checkout --track <name>`; create is
//! `git.exe -C PATH checkout -b <name>`; delete is
//! `git.exe -C PATH branch -d|-D <name>`; fetch is
//! `git.exe -C PATH fetch --prune`; push is `git.exe -C PATH push`
//! or `git.exe -C PATH push --force`;
//! upstream is `git.exe -C PATH rev-parse --abbrev-ref --symbolic-full-name @{upstream}`;
//! remotes is `git.exe -C PATH remote`; set-upstream is
//! `git.exe -C PATH push [--force] --set-upstream <remote> <branch>`; worktree
//! base is `git.exe -C PATH symbolic-ref --quiet --short refs/remotes/origin/HEAD`.
//! CRLF stdout is already trimmed in the line helpers. app.zon
//! already includes windows.
//!
//! Spawn/line/exit orchestration lives here. Effect keys stay
//! git_checkout bands (250+ list, 275+ checkout, 290+ create,
//! 320+ delete, 340+ fetch, 360+ push, 370+ worktree add,
//! 390+ worktree base).

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

/// One-shot `git branch -d <name>` or `git branch -D <name>`.
/// Distinct from list (250+), checkout (275+), create (290+),
/// git_dirty (300+), git_fetch (340+), git_numstat (350+),
/// git_push (360+), git_ahead_behind (380+), and file_mention
/// (400+). Band is 320+ (between dirty 300+ and fetch 340+).
/// Force reuses this band; `-d` / `-D` are argv slots, not a
/// new key family.
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
/// PATH-resolved Windows Git (explicit `.exe` like sibling
/// `powershell.exe` / `explorer.exe` / `wt.exe` / `cmd.exe`).
pub const windows_git_bin = git_branch.windows_git_bin;
pub const git_c_flag = git_branch.git_c_flag;
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
pub const git_delete_force_flag = "-D";
pub const git_fetch_cmd = "fetch";
pub const git_prune_flag = "--prune";
pub const git_push_cmd = "push";
pub const git_push_force_flag = "--force";
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
/// Honest New worktree… Base label when no override and no
/// resolved / composer branch is available (detached / empty).
pub const worktree_base_fallback_label = "HEAD";
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
pub const powershell_bin = file_mention.powershell_bin;
pub const powershell_noprofile = file_mention.powershell_noprofile;
pub const powershell_command = file_mention.powershell_command;
pub const powershell_args_flag = file_mention.powershell_args_flag;
/// Windows analog of `git_worktree_mkdir_chdir_script`: mkdir parent
/// (`$args[0]`), chdir to the repo (`$args[1]`), then invoke git
/// from the remaining `-Args` slots (`git.exe`, `worktree`, `add`,
/// `-b`, branch, dest, optional base). Paths are never inside this
/// scriptblock. `exit $LASTEXITCODE` keeps git's status (PowerShell
/// does not `exec`).
pub const git_worktree_mkdir_chdir_ps_script = "{ $ErrorActionPreference='Stop'; New-Item -ItemType Directory -Force -LiteralPath $args[0] | Out-Null; Set-Location -LiteralPath $args[1]; if ($args.Length -ge 9) { & $args[2] $args[3] $args[4] $args[5] $args[6] $args[7] $args[8] } else { & $args[2] $args[3] $args[4] $args[5] $args[6] $args[7] }; exit $LASTEXITCODE }";

/// Unix `/bin/sh -c` chdir + git for-each-ref (10). Windows
/// `git.exe -C` is 7; this is the spawn buffer (max of the two).
const list_argv_len: usize = 10;
const unix_list_argv_len: usize = 10;
const windows_list_argv_len: usize = 7;
/// Unix `/bin/sh -c` chdir + git checkout <name> (8). Windows
/// `git.exe -C` is 5.
const checkout_argv_len: usize = 8;
const unix_checkout_argv_len: usize = 8;
const windows_checkout_argv_len: usize = 5;
/// Unix `/bin/sh -c` chdir + git checkout --track <name> (9).
/// Windows `git.exe -C` is 6.
const track_checkout_argv_len: usize = 9;
const unix_track_checkout_argv_len: usize = 9;
const windows_track_checkout_argv_len: usize = 6;
/// Unix `/bin/sh -c` chdir + git checkout -b <name> (9). Windows
/// `git.exe -C` is 6.
const create_argv_len: usize = 9;
const unix_create_argv_len: usize = 9;
const windows_create_argv_len: usize = 6;
/// Unix `/bin/sh -c` chdir + git branch -d|-D <name> (9). Windows
/// `git.exe -C` is 6.
const delete_argv_len: usize = 9;
const unix_delete_argv_len: usize = 9;
const windows_delete_argv_len: usize = 6;
/// Unix `/bin/sh -c` chdir + git fetch --prune (8). Windows
/// `git.exe -C` is 5.
const fetch_argv_len: usize = 8;
const unix_fetch_argv_len: usize = 8;
const windows_fetch_argv_len: usize = 5;
/// Unix `/bin/sh -c` chdir + git push (7) or git push --force (8).
/// Windows `git.exe -C` is 4 / 5. Buffer is the max (Unix force).
pub const push_argv_len: usize = 8;
const unix_push_argv_len: usize = 7;
const unix_push_force_argv_len: usize = 8;
const windows_push_argv_len: usize = 4;
const windows_push_force_argv_len: usize = 5;
/// Unix `/bin/sh -c` chdir + git rev-parse --abbrev-ref
/// --symbolic-full-name @{upstream} (10). Windows `git.exe -C` is 7.
const upstream_argv_len: usize = 10;
const unix_upstream_argv_len: usize = 10;
const windows_upstream_argv_len: usize = 7;
/// Unix `/bin/sh -c` chdir + git remote (7). Windows `git.exe -C` is 4.
pub const remote_argv_len: usize = 7;
pub const unix_remote_argv_len: usize = 7;
pub const windows_remote_argv_len: usize = 4;
const show_current_argv_len: usize = 8;
/// Unix `/bin/sh -c` chdir + git push --set-upstream (10) or
/// git push --force --set-upstream (11). Windows `git.exe -C` is 7 / 8.
const set_upstream_push_argv_len: usize = 11;
const unix_set_upstream_push_argv_len: usize = 10;
const unix_set_upstream_push_force_argv_len: usize = 11;
const windows_set_upstream_push_argv_len: usize = 7;
const windows_set_upstream_push_force_argv_len: usize = 8;
/// Unix mkdir+chdir + git worktree add -b (12 / 13 with base).
/// Windows powershell `-Command` + `-Args` is 13 / 14; this is
/// the spawn buffer (max of the two).
const unix_worktree_add_no_base_argv_len: usize = 12;
const unix_worktree_add_argv_len: usize = 13;
const windows_worktree_add_no_base_argv_len: usize = 13;
const windows_worktree_add_argv_len: usize = 14;
const worktree_add_argv_len: usize = 14;
/// Unix `/bin/sh -c` chdir + git symbolic-ref (10). Windows
/// `git.exe -C` is 7.
const worktree_base_argv_len: usize = 10;
const unix_worktree_base_argv_len: usize = 10;
const windows_worktree_base_argv_len: usize = 7;

fn windowsGitBinOk(bin: []const u8) bool {
    return std.mem.eql(u8, bin, windows_git_bin) or std.mem.eql(u8, bin, git_bin);
}

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

pub fn unixListArgvFor(cwd: []const u8, buf: *[list_argv_len][]const u8) []const []const u8 {
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
    return buf[0..unix_list_argv_len];
}

/// Windows: `git.exe -C <project_path> for-each-ref --format=… refs/heads refs/remotes`.
/// Path is its own argv slot (no `/bin/sh`, no packing into a cmd string).
pub fn windowsListArgvFor(cwd: []const u8, buf: *[list_argv_len][]const u8) []const []const u8 {
    buf[0] = windows_git_bin;
    buf[1] = git_c_flag;
    buf[2] = cwd;
    buf[3] = git_for_each_ref_cmd;
    buf[4] = git_refname_format;
    buf[5] = git_heads_ref;
    buf[6] = git_remotes_ref;
    return buf[0..windows_list_argv_len];
}

pub fn listArgvFor(cwd: []const u8, buf: *[list_argv_len][]const u8) []const []const u8 {
    return switch (builtin.os.tag) {
        .windows => windowsListArgvFor(cwd, buf),
        else => unixListArgvFor(cwd, buf),
    };
}

fn isUnixGitBranchListArgv(argv: []const []const u8) bool {
    if (argv.len != unix_list_argv_len) return false;
    if (!std.mem.eql(u8, argv[0], sh_bin)) return false;
    if (!std.mem.eql(u8, argv[1], "-c")) return false;
    if (!std.mem.eql(u8, argv[2], main.fx_ask_chdir_script)) return false;
    if (!std.mem.eql(u8, argv[5], git_bin)) return false;
    if (!std.mem.eql(u8, argv[6], git_for_each_ref_cmd)) return false;
    if (!std.mem.eql(u8, argv[7], git_refname_format)) return false;
    if (!std.mem.eql(u8, argv[8], git_heads_ref)) return false;
    return std.mem.eql(u8, argv[9], git_remotes_ref);
}

fn isWindowsGitBranchListArgv(argv: []const []const u8) bool {
    if (argv.len != windows_list_argv_len) return false;
    if (!windowsGitBinOk(argv[0])) return false;
    if (!std.mem.eql(u8, argv[1], git_c_flag)) return false;
    if (argv[2].len == 0) return false;
    if (!std.mem.eql(u8, argv[3], git_for_each_ref_cmd)) return false;
    if (!std.mem.eql(u8, argv[4], git_refname_format)) return false;
    if (!std.mem.eql(u8, argv[5], git_heads_ref)) return false;
    return std.mem.eql(u8, argv[6], git_remotes_ref);
}

pub fn isGitBranchListArgv(argv: []const []const u8) bool {
    return isUnixGitBranchListArgv(argv) or isWindowsGitBranchListArgv(argv);
}

/// `git checkout <name>` as a trailing argv slot. Rejects names that
/// fail `isPlausibleBranchName` so a raw string never reaches the
/// shell script.
pub fn unixCheckoutArgvFor(cwd: []const u8, name: []const u8, buf: *[checkout_argv_len][]const u8) ?[]const []const u8 {
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
    return buf[0..unix_checkout_argv_len];
}

/// Windows: `git.exe -C <project_path> checkout <name>`. Path and
/// name are their own argv slots.
pub fn windowsCheckoutArgvFor(cwd: []const u8, name: []const u8, buf: *[checkout_argv_len][]const u8) ?[]const []const u8 {
    if (!git_branch.isPlausibleBranchName(name)) return null;
    buf[0] = windows_git_bin;
    buf[1] = git_c_flag;
    buf[2] = cwd;
    buf[3] = git_checkout_cmd;
    buf[4] = name;
    return buf[0..windows_checkout_argv_len];
}

pub fn checkoutArgvFor(cwd: []const u8, name: []const u8, buf: *[checkout_argv_len][]const u8) ?[]const []const u8 {
    return switch (builtin.os.tag) {
        .windows => windowsCheckoutArgvFor(cwd, name, buf),
        else => unixCheckoutArgvFor(cwd, name, buf),
    };
}

fn isUnixGitCheckoutArgv(argv: []const []const u8) bool {
    if (argv.len != unix_checkout_argv_len) return false;
    if (!std.mem.eql(u8, argv[0], sh_bin)) return false;
    if (!std.mem.eql(u8, argv[1], "-c")) return false;
    if (!std.mem.eql(u8, argv[2], main.fx_ask_chdir_script)) return false;
    if (!std.mem.eql(u8, argv[5], git_bin)) return false;
    if (!std.mem.eql(u8, argv[6], git_checkout_cmd)) return false;
    return git_branch.isPlausibleBranchName(argv[7]);
}

fn isWindowsGitCheckoutArgv(argv: []const []const u8) bool {
    if (argv.len != windows_checkout_argv_len) return false;
    if (!windowsGitBinOk(argv[0])) return false;
    if (!std.mem.eql(u8, argv[1], git_c_flag)) return false;
    if (argv[2].len == 0) return false;
    if (!std.mem.eql(u8, argv[3], git_checkout_cmd)) return false;
    return git_branch.isPlausibleBranchName(argv[4]);
}

pub fn isGitCheckoutArgv(argv: []const []const u8) bool {
    return isUnixGitCheckoutArgv(argv) or isWindowsGitCheckoutArgv(argv);
}

/// `git checkout --track <name>` as trailing argv slots. Rejects names
/// that fail `isPlausibleBranchName` so a raw string never reaches the
/// shell script.
pub fn unixTrackCheckoutArgvFor(cwd: []const u8, name: []const u8, buf: *[track_checkout_argv_len][]const u8) ?[]const []const u8 {
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
    return buf[0..unix_track_checkout_argv_len];
}

/// Windows: `git.exe -C <project_path> checkout --track <name>`.
pub fn windowsTrackCheckoutArgvFor(cwd: []const u8, name: []const u8, buf: *[track_checkout_argv_len][]const u8) ?[]const []const u8 {
    if (!git_branch.isPlausibleBranchName(name)) return null;
    buf[0] = windows_git_bin;
    buf[1] = git_c_flag;
    buf[2] = cwd;
    buf[3] = git_checkout_cmd;
    buf[4] = git_track_flag;
    buf[5] = name;
    return buf[0..windows_track_checkout_argv_len];
}

pub fn trackCheckoutArgvFor(cwd: []const u8, name: []const u8, buf: *[track_checkout_argv_len][]const u8) ?[]const []const u8 {
    return switch (builtin.os.tag) {
        .windows => windowsTrackCheckoutArgvFor(cwd, name, buf),
        else => unixTrackCheckoutArgvFor(cwd, name, buf),
    };
}

fn isUnixGitTrackCheckoutArgv(argv: []const []const u8) bool {
    if (argv.len != unix_track_checkout_argv_len) return false;
    if (!std.mem.eql(u8, argv[0], sh_bin)) return false;
    if (!std.mem.eql(u8, argv[1], "-c")) return false;
    if (!std.mem.eql(u8, argv[2], main.fx_ask_chdir_script)) return false;
    if (!std.mem.eql(u8, argv[5], git_bin)) return false;
    if (!std.mem.eql(u8, argv[6], git_checkout_cmd)) return false;
    if (!std.mem.eql(u8, argv[7], git_track_flag)) return false;
    return git_branch.isPlausibleBranchName(argv[8]);
}

fn isWindowsGitTrackCheckoutArgv(argv: []const []const u8) bool {
    if (argv.len != windows_track_checkout_argv_len) return false;
    if (!windowsGitBinOk(argv[0])) return false;
    if (!std.mem.eql(u8, argv[1], git_c_flag)) return false;
    if (argv[2].len == 0) return false;
    if (!std.mem.eql(u8, argv[3], git_checkout_cmd)) return false;
    if (!std.mem.eql(u8, argv[4], git_track_flag)) return false;
    return git_branch.isPlausibleBranchName(argv[5]);
}

pub fn isGitTrackCheckoutArgv(argv: []const []const u8) bool {
    return isUnixGitTrackCheckoutArgv(argv) or isWindowsGitTrackCheckoutArgv(argv);
}

/// `git checkout -b <name>` with the name as a trailing argv slot.
/// Rejects names that fail `isPlausibleBranchName` so a raw string
/// never reaches the shell script.
pub fn unixCreateArgvFor(cwd: []const u8, name: []const u8, buf: *[create_argv_len][]const u8) ?[]const []const u8 {
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
    return buf[0..unix_create_argv_len];
}

/// Windows: `git.exe -C <project_path> checkout -b <name>`.
pub fn windowsCreateArgvFor(cwd: []const u8, name: []const u8, buf: *[create_argv_len][]const u8) ?[]const []const u8 {
    if (!git_branch.isPlausibleBranchName(name)) return null;
    buf[0] = windows_git_bin;
    buf[1] = git_c_flag;
    buf[2] = cwd;
    buf[3] = git_checkout_cmd;
    buf[4] = git_create_b_flag;
    buf[5] = name;
    return buf[0..windows_create_argv_len];
}

pub fn createArgvFor(cwd: []const u8, name: []const u8, buf: *[create_argv_len][]const u8) ?[]const []const u8 {
    return switch (builtin.os.tag) {
        .windows => windowsCreateArgvFor(cwd, name, buf),
        else => unixCreateArgvFor(cwd, name, buf),
    };
}

fn isUnixGitCreateArgv(argv: []const []const u8) bool {
    if (argv.len != unix_create_argv_len) return false;
    if (!std.mem.eql(u8, argv[0], sh_bin)) return false;
    if (!std.mem.eql(u8, argv[1], "-c")) return false;
    if (!std.mem.eql(u8, argv[2], main.fx_ask_chdir_script)) return false;
    if (!std.mem.eql(u8, argv[5], git_bin)) return false;
    if (!std.mem.eql(u8, argv[6], git_checkout_cmd)) return false;
    if (!std.mem.eql(u8, argv[7], git_create_b_flag)) return false;
    return git_branch.isPlausibleBranchName(argv[8]);
}

fn isWindowsGitCreateArgv(argv: []const []const u8) bool {
    if (argv.len != windows_create_argv_len) return false;
    if (!windowsGitBinOk(argv[0])) return false;
    if (!std.mem.eql(u8, argv[1], git_c_flag)) return false;
    if (argv[2].len == 0) return false;
    if (!std.mem.eql(u8, argv[3], git_checkout_cmd)) return false;
    if (!std.mem.eql(u8, argv[4], git_create_b_flag)) return false;
    return git_branch.isPlausibleBranchName(argv[5]);
}

pub fn isGitCreateArgv(argv: []const []const u8) bool {
    return isUnixGitCreateArgv(argv) or isWindowsGitCreateArgv(argv);
}

fn unixDeleteArgvWithFlag(cwd: []const u8, name: []const u8, flag: []const u8, buf: *[delete_argv_len][]const u8) ?[]const []const u8 {
    if (!git_branch.isPlausibleBranchName(name)) return null;
    buf.* = .{
        sh_bin,
        "-c",
        main.fx_ask_chdir_script,
        "sh",
        cwd,
        git_bin,
        git_branch_cmd,
        flag,
        name,
    };
    return buf[0..unix_delete_argv_len];
}

fn windowsDeleteArgvWithFlag(cwd: []const u8, name: []const u8, flag: []const u8, buf: *[delete_argv_len][]const u8) ?[]const []const u8 {
    if (!git_branch.isPlausibleBranchName(name)) return null;
    buf[0] = windows_git_bin;
    buf[1] = git_c_flag;
    buf[2] = cwd;
    buf[3] = git_branch_cmd;
    buf[4] = flag;
    buf[5] = name;
    return buf[0..windows_delete_argv_len];
}

fn deleteArgvWithFlag(cwd: []const u8, name: []const u8, flag: []const u8, buf: *[delete_argv_len][]const u8) ?[]const []const u8 {
    return switch (builtin.os.tag) {
        .windows => windowsDeleteArgvWithFlag(cwd, name, flag, buf),
        else => unixDeleteArgvWithFlag(cwd, name, flag, buf),
    };
}

fn isUnixGitDeleteArgvWithFlag(argv: []const []const u8, flag: []const u8) bool {
    if (argv.len != unix_delete_argv_len) return false;
    if (!std.mem.eql(u8, argv[0], sh_bin)) return false;
    if (!std.mem.eql(u8, argv[1], "-c")) return false;
    if (!std.mem.eql(u8, argv[2], main.fx_ask_chdir_script)) return false;
    if (!std.mem.eql(u8, argv[5], git_bin)) return false;
    if (!std.mem.eql(u8, argv[6], git_branch_cmd)) return false;
    if (!std.mem.eql(u8, argv[7], flag)) return false;
    return git_branch.isPlausibleBranchName(argv[8]);
}

fn isWindowsGitDeleteArgvWithFlag(argv: []const []const u8, flag: []const u8) bool {
    if (argv.len != windows_delete_argv_len) return false;
    if (!windowsGitBinOk(argv[0])) return false;
    if (!std.mem.eql(u8, argv[1], git_c_flag)) return false;
    if (argv[2].len == 0) return false;
    if (!std.mem.eql(u8, argv[3], git_branch_cmd)) return false;
    if (!std.mem.eql(u8, argv[4], flag)) return false;
    return git_branch.isPlausibleBranchName(argv[5]);
}

fn isGitDeleteArgvWithFlag(argv: []const []const u8, flag: []const u8) bool {
    return isUnixGitDeleteArgvWithFlag(argv, flag) or isWindowsGitDeleteArgvWithFlag(argv, flag);
}

/// `git branch -d <name>` with the name as a trailing argv slot.
/// Rejects names that fail `isPlausibleBranchName` so a raw string
/// never reaches the shell script. Never emits `-D`.
pub fn unixDeleteArgvFor(cwd: []const u8, name: []const u8, buf: *[delete_argv_len][]const u8) ?[]const []const u8 {
    return unixDeleteArgvWithFlag(cwd, name, git_delete_d_flag, buf);
}

pub fn windowsDeleteArgvFor(cwd: []const u8, name: []const u8, buf: *[delete_argv_len][]const u8) ?[]const []const u8 {
    return windowsDeleteArgvWithFlag(cwd, name, git_delete_d_flag, buf);
}

pub fn deleteArgvFor(cwd: []const u8, name: []const u8, buf: *[delete_argv_len][]const u8) ?[]const []const u8 {
    return deleteArgvWithFlag(cwd, name, git_delete_d_flag, buf);
}

pub fn isGitDeleteArgv(argv: []const []const u8) bool {
    return isGitDeleteArgvWithFlag(argv, git_delete_d_flag);
}

/// `git branch -D <name>` with the name as a trailing argv slot.
/// Same plausibility gate as `deleteArgvFor`. `-D` is its own slot.
pub fn unixDeleteForceArgvFor(cwd: []const u8, name: []const u8, buf: *[delete_argv_len][]const u8) ?[]const []const u8 {
    return unixDeleteArgvWithFlag(cwd, name, git_delete_force_flag, buf);
}

pub fn windowsDeleteForceArgvFor(cwd: []const u8, name: []const u8, buf: *[delete_argv_len][]const u8) ?[]const []const u8 {
    return windowsDeleteArgvWithFlag(cwd, name, git_delete_force_flag, buf);
}

pub fn deleteForceArgvFor(cwd: []const u8, name: []const u8, buf: *[delete_argv_len][]const u8) ?[]const []const u8 {
    return deleteArgvWithFlag(cwd, name, git_delete_force_flag, buf);
}

pub fn isGitDeleteForceArgv(argv: []const []const u8) bool {
    return isGitDeleteArgvWithFlag(argv, git_delete_force_flag);
}

/// `git fetch --prune` with `--prune` as its own argv slot — never
/// interpolated into the `-c` script.
pub fn unixFetchArgvFor(cwd: []const u8, buf: *[fetch_argv_len][]const u8) []const []const u8 {
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
    return buf[0..unix_fetch_argv_len];
}

/// Windows: `git.exe -C <project_path> fetch --prune`.
pub fn windowsFetchArgvFor(cwd: []const u8, buf: *[fetch_argv_len][]const u8) []const []const u8 {
    buf[0] = windows_git_bin;
    buf[1] = git_c_flag;
    buf[2] = cwd;
    buf[3] = git_fetch_cmd;
    buf[4] = git_prune_flag;
    return buf[0..windows_fetch_argv_len];
}

pub fn fetchArgvFor(cwd: []const u8, buf: *[fetch_argv_len][]const u8) []const []const u8 {
    return switch (builtin.os.tag) {
        .windows => windowsFetchArgvFor(cwd, buf),
        else => unixFetchArgvFor(cwd, buf),
    };
}

fn isUnixGitFetchArgv(argv: []const []const u8) bool {
    if (argv.len != unix_fetch_argv_len) return false;
    if (!std.mem.eql(u8, argv[0], sh_bin)) return false;
    if (!std.mem.eql(u8, argv[1], "-c")) return false;
    if (!std.mem.eql(u8, argv[2], main.fx_ask_chdir_script)) return false;
    if (!std.mem.eql(u8, argv[5], git_bin)) return false;
    if (!std.mem.eql(u8, argv[6], git_fetch_cmd)) return false;
    return std.mem.eql(u8, argv[7], git_prune_flag);
}

fn isWindowsGitFetchArgv(argv: []const []const u8) bool {
    if (argv.len != windows_fetch_argv_len) return false;
    if (!windowsGitBinOk(argv[0])) return false;
    if (!std.mem.eql(u8, argv[1], git_c_flag)) return false;
    if (argv[2].len == 0) return false;
    if (!std.mem.eql(u8, argv[3], git_fetch_cmd)) return false;
    return std.mem.eql(u8, argv[4], git_prune_flag);
}

pub fn isGitFetchArgv(argv: []const []const u8) bool {
    return isUnixGitFetchArgv(argv) or isWindowsGitFetchArgv(argv);
}

/// `git push` — `push` is its own argv slot, never interpolated
/// into the `-c` script. Optional `--force` is its own slot after
/// `push`. Not `--set-upstream`, not `-u`, not `--force-with-lease`,
/// not `--tags`.
fn writeUnixPushArgv(cwd: []const u8, force: bool, buf: *[push_argv_len][]const u8) []const []const u8 {
    buf[0] = sh_bin;
    buf[1] = "-c";
    buf[2] = main.fx_ask_chdir_script;
    buf[3] = "sh";
    buf[4] = cwd;
    buf[5] = git_bin;
    buf[6] = git_push_cmd;
    if (!force) return buf[0..unix_push_argv_len];
    buf[7] = git_push_force_flag;
    return buf[0..unix_push_force_argv_len];
}

pub fn unixPushArgvFor(cwd: []const u8, buf: *[push_argv_len][]const u8) []const []const u8 {
    return writeUnixPushArgv(cwd, false, buf);
}

pub fn unixPushForceArgvFor(cwd: []const u8, buf: *[push_argv_len][]const u8) []const []const u8 {
    return writeUnixPushArgv(cwd, true, buf);
}

/// Windows: `git.exe -C <project_path> push` (optional `--force`).
fn writeWindowsPushArgv(cwd: []const u8, force: bool, buf: *[push_argv_len][]const u8) []const []const u8 {
    buf[0] = windows_git_bin;
    buf[1] = git_c_flag;
    buf[2] = cwd;
    buf[3] = git_push_cmd;
    if (!force) return buf[0..windows_push_argv_len];
    buf[4] = git_push_force_flag;
    return buf[0..windows_push_force_argv_len];
}

pub fn windowsPushArgvFor(cwd: []const u8, buf: *[push_argv_len][]const u8) []const []const u8 {
    return writeWindowsPushArgv(cwd, false, buf);
}

pub fn windowsPushForceArgvFor(cwd: []const u8, buf: *[push_argv_len][]const u8) []const []const u8 {
    return writeWindowsPushArgv(cwd, true, buf);
}

pub fn pushArgvFor(cwd: []const u8, buf: *[push_argv_len][]const u8) []const []const u8 {
    return switch (builtin.os.tag) {
        .windows => windowsPushArgvFor(cwd, buf),
        else => unixPushArgvFor(cwd, buf),
    };
}

pub fn pushForceArgvFor(cwd: []const u8, buf: *[push_argv_len][]const u8) []const []const u8 {
    return switch (builtin.os.tag) {
        .windows => windowsPushForceArgvFor(cwd, buf),
        else => unixPushForceArgvFor(cwd, buf),
    };
}

fn isUnixGitPushArgv(argv: []const []const u8) bool {
    const force = argv.len == unix_push_force_argv_len;
    if (!force and argv.len != unix_push_argv_len) return false;
    if (!std.mem.eql(u8, argv[0], sh_bin)) return false;
    if (!std.mem.eql(u8, argv[1], "-c")) return false;
    if (!std.mem.eql(u8, argv[2], main.fx_ask_chdir_script)) return false;
    if (!std.mem.eql(u8, argv[5], git_bin)) return false;
    if (!std.mem.eql(u8, argv[6], git_push_cmd)) return false;
    if (!force) return true;
    return std.mem.eql(u8, argv[7], git_push_force_flag);
}

fn isWindowsGitPushArgv(argv: []const []const u8) bool {
    const force = argv.len == windows_push_force_argv_len;
    if (!force and argv.len != windows_push_argv_len) return false;
    if (!windowsGitBinOk(argv[0])) return false;
    if (!std.mem.eql(u8, argv[1], git_c_flag)) return false;
    if (argv[2].len == 0) return false;
    if (!std.mem.eql(u8, argv[3], git_push_cmd)) return false;
    if (!force) return true;
    return std.mem.eql(u8, argv[4], git_push_force_flag);
}

pub fn isGitPushArgv(argv: []const []const u8) bool {
    return isUnixGitPushArgv(argv) or isWindowsGitPushArgv(argv);
}

pub fn isGitPushForceArgv(argv: []const []const u8) bool {
    if (isUnixGitPushArgv(argv)) return argv.len == unix_push_force_argv_len;
    if (isWindowsGitPushArgv(argv)) return argv.len == windows_push_force_argv_len;
    return false;
}

/// `git rev-parse --abbrev-ref --symbolic-full-name @{upstream}`.
/// `@{upstream}` is its own argv slot — never interpolated into the
/// `-c` script. Missing / failed stdout means no upstream.
pub fn unixUpstreamArgvFor(cwd: []const u8, buf: *[upstream_argv_len][]const u8) []const []const u8 {
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
    return buf[0..unix_upstream_argv_len];
}

/// Windows: `git.exe -C <project_path> rev-parse --abbrev-ref
/// --symbolic-full-name @{upstream}`. Same flags as Unix.
pub fn windowsUpstreamArgvFor(cwd: []const u8, buf: *[upstream_argv_len][]const u8) []const []const u8 {
    buf[0] = windows_git_bin;
    buf[1] = git_c_flag;
    buf[2] = cwd;
    buf[3] = git_rev_parse_cmd;
    buf[4] = git_abbrev_ref;
    buf[5] = git_symbolic_full_name;
    buf[6] = git_upstream_rev;
    return buf[0..windows_upstream_argv_len];
}

pub fn upstreamArgvFor(cwd: []const u8, buf: *[upstream_argv_len][]const u8) []const []const u8 {
    return switch (builtin.os.tag) {
        .windows => windowsUpstreamArgvFor(cwd, buf),
        else => unixUpstreamArgvFor(cwd, buf),
    };
}

fn isUnixGitUpstreamArgv(argv: []const []const u8) bool {
    if (argv.len != unix_upstream_argv_len) return false;
    if (!std.mem.eql(u8, argv[0], sh_bin)) return false;
    if (!std.mem.eql(u8, argv[1], "-c")) return false;
    if (!std.mem.eql(u8, argv[2], main.fx_ask_chdir_script)) return false;
    if (!std.mem.eql(u8, argv[5], git_bin)) return false;
    if (!std.mem.eql(u8, argv[6], git_rev_parse_cmd)) return false;
    if (!std.mem.eql(u8, argv[7], git_abbrev_ref)) return false;
    if (!std.mem.eql(u8, argv[8], git_symbolic_full_name)) return false;
    return std.mem.eql(u8, argv[9], git_upstream_rev);
}

fn isWindowsGitUpstreamArgv(argv: []const []const u8) bool {
    if (argv.len != windows_upstream_argv_len) return false;
    if (!windowsGitBinOk(argv[0])) return false;
    if (!std.mem.eql(u8, argv[1], git_c_flag)) return false;
    if (argv[2].len == 0) return false;
    if (!std.mem.eql(u8, argv[3], git_rev_parse_cmd)) return false;
    if (!std.mem.eql(u8, argv[4], git_abbrev_ref)) return false;
    if (!std.mem.eql(u8, argv[5], git_symbolic_full_name)) return false;
    return std.mem.eql(u8, argv[6], git_upstream_rev);
}

pub fn isGitUpstreamArgv(argv: []const []const u8) bool {
    return isUnixGitUpstreamArgv(argv) or isWindowsGitUpstreamArgv(argv);
}

/// `git remote` with `remote` as its own argv slot.
pub fn unixRemoteArgvFor(cwd: []const u8, buf: *[remote_argv_len][]const u8) []const []const u8 {
    buf.* = .{
        sh_bin,
        "-c",
        main.fx_ask_chdir_script,
        "sh",
        cwd,
        git_bin,
        git_remote_cmd,
    };
    return buf[0..unix_remote_argv_len];
}

/// Windows: `git.exe -C <project_path> remote`.
pub fn windowsRemoteArgvFor(cwd: []const u8, buf: *[remote_argv_len][]const u8) []const []const u8 {
    buf[0] = windows_git_bin;
    buf[1] = git_c_flag;
    buf[2] = cwd;
    buf[3] = git_remote_cmd;
    return buf[0..windows_remote_argv_len];
}

pub fn remoteArgvFor(cwd: []const u8, buf: *[remote_argv_len][]const u8) []const []const u8 {
    return switch (builtin.os.tag) {
        .windows => windowsRemoteArgvFor(cwd, buf),
        else => unixRemoteArgvFor(cwd, buf),
    };
}

fn isUnixGitRemoteArgv(argv: []const []const u8) bool {
    if (argv.len != unix_remote_argv_len) return false;
    if (!std.mem.eql(u8, argv[0], sh_bin)) return false;
    if (!std.mem.eql(u8, argv[1], "-c")) return false;
    if (!std.mem.eql(u8, argv[2], main.fx_ask_chdir_script)) return false;
    if (!std.mem.eql(u8, argv[5], git_bin)) return false;
    return std.mem.eql(u8, argv[6], git_remote_cmd);
}

fn isWindowsGitRemoteArgv(argv: []const []const u8) bool {
    if (argv.len != windows_remote_argv_len) return false;
    if (!windowsGitBinOk(argv[0])) return false;
    if (!std.mem.eql(u8, argv[1], git_c_flag)) return false;
    if (argv[2].len == 0) return false;
    return std.mem.eql(u8, argv[3], git_remote_cmd);
}

pub fn isGitRemoteArgv(argv: []const []const u8) bool {
    return isUnixGitRemoteArgv(argv) or isWindowsGitRemoteArgv(argv);
}

/// `git push --set-upstream <remote> <branch>` — flag, remote, and
/// branch each their own argv slot, never interpolated into the `-c`
/// script. Optional `--force` is its own slot after `push` and
/// before `--set-upstream`. Rejects implausible names so a raw
/// string never reaches the shell script. Not `-u`, not
/// `--force-with-lease`.
fn writeUnixSetUpstreamPushArgv(
    cwd: []const u8,
    remote: []const u8,
    branch: []const u8,
    force: bool,
    buf: *[set_upstream_push_argv_len][]const u8,
) ?[]const []const u8 {
    if (!isPlausibleRemoteName(remote)) return null;
    if (!git_branch.isPlausibleBranchName(branch)) return null;
    buf[0] = sh_bin;
    buf[1] = "-c";
    buf[2] = main.fx_ask_chdir_script;
    buf[3] = "sh";
    buf[4] = cwd;
    buf[5] = git_bin;
    buf[6] = git_push_cmd;
    var i: usize = 7;
    if (force) {
        buf[i] = git_push_force_flag;
        i += 1;
    }
    buf[i] = git_set_upstream_flag;
    buf[i + 1] = remote;
    buf[i + 2] = branch;
    return buf[0 .. i + 3];
}

pub fn unixSetUpstreamPushArgvFor(
    cwd: []const u8,
    remote: []const u8,
    branch: []const u8,
    buf: *[set_upstream_push_argv_len][]const u8,
) ?[]const []const u8 {
    return writeUnixSetUpstreamPushArgv(cwd, remote, branch, false, buf);
}

pub fn unixSetUpstreamPushForceArgvFor(
    cwd: []const u8,
    remote: []const u8,
    branch: []const u8,
    buf: *[set_upstream_push_argv_len][]const u8,
) ?[]const []const u8 {
    return writeUnixSetUpstreamPushArgv(cwd, remote, branch, true, buf);
}

/// Windows: `git.exe -C <project_path> push [--force] --set-upstream <remote> <branch>`.
fn writeWindowsSetUpstreamPushArgv(
    cwd: []const u8,
    remote: []const u8,
    branch: []const u8,
    force: bool,
    buf: *[set_upstream_push_argv_len][]const u8,
) ?[]const []const u8 {
    if (!isPlausibleRemoteName(remote)) return null;
    if (!git_branch.isPlausibleBranchName(branch)) return null;
    buf[0] = windows_git_bin;
    buf[1] = git_c_flag;
    buf[2] = cwd;
    buf[3] = git_push_cmd;
    var i: usize = 4;
    if (force) {
        buf[i] = git_push_force_flag;
        i += 1;
    }
    buf[i] = git_set_upstream_flag;
    buf[i + 1] = remote;
    buf[i + 2] = branch;
    return buf[0 .. i + 3];
}

pub fn windowsSetUpstreamPushArgvFor(
    cwd: []const u8,
    remote: []const u8,
    branch: []const u8,
    buf: *[set_upstream_push_argv_len][]const u8,
) ?[]const []const u8 {
    return writeWindowsSetUpstreamPushArgv(cwd, remote, branch, false, buf);
}

pub fn windowsSetUpstreamPushForceArgvFor(
    cwd: []const u8,
    remote: []const u8,
    branch: []const u8,
    buf: *[set_upstream_push_argv_len][]const u8,
) ?[]const []const u8 {
    return writeWindowsSetUpstreamPushArgv(cwd, remote, branch, true, buf);
}

pub fn setUpstreamPushArgvFor(
    cwd: []const u8,
    remote: []const u8,
    branch: []const u8,
    buf: *[set_upstream_push_argv_len][]const u8,
) ?[]const []const u8 {
    return switch (builtin.os.tag) {
        .windows => windowsSetUpstreamPushArgvFor(cwd, remote, branch, buf),
        else => unixSetUpstreamPushArgvFor(cwd, remote, branch, buf),
    };
}

pub fn setUpstreamPushForceArgvFor(
    cwd: []const u8,
    remote: []const u8,
    branch: []const u8,
    buf: *[set_upstream_push_argv_len][]const u8,
) ?[]const []const u8 {
    return switch (builtin.os.tag) {
        .windows => windowsSetUpstreamPushForceArgvFor(cwd, remote, branch, buf),
        else => unixSetUpstreamPushForceArgvFor(cwd, remote, branch, buf),
    };
}

fn isUnixGitSetUpstreamPushArgv(argv: []const []const u8) bool {
    const force = argv.len == unix_set_upstream_push_force_argv_len;
    if (!force and argv.len != unix_set_upstream_push_argv_len) return false;
    if (!std.mem.eql(u8, argv[0], sh_bin)) return false;
    if (!std.mem.eql(u8, argv[1], "-c")) return false;
    if (!std.mem.eql(u8, argv[2], main.fx_ask_chdir_script)) return false;
    if (!std.mem.eql(u8, argv[5], git_bin)) return false;
    if (!std.mem.eql(u8, argv[6], git_push_cmd)) return false;
    var i: usize = 7;
    if (force) {
        if (!std.mem.eql(u8, argv[i], git_push_force_flag)) return false;
        i += 1;
    }
    if (!std.mem.eql(u8, argv[i], git_set_upstream_flag)) return false;
    if (!isPlausibleRemoteName(argv[i + 1])) return false;
    return git_branch.isPlausibleBranchName(argv[i + 2]);
}

fn isWindowsGitSetUpstreamPushArgv(argv: []const []const u8) bool {
    const force = argv.len == windows_set_upstream_push_force_argv_len;
    if (!force and argv.len != windows_set_upstream_push_argv_len) return false;
    if (!windowsGitBinOk(argv[0])) return false;
    if (!std.mem.eql(u8, argv[1], git_c_flag)) return false;
    if (argv[2].len == 0) return false;
    if (!std.mem.eql(u8, argv[3], git_push_cmd)) return false;
    var i: usize = 4;
    if (force) {
        if (!std.mem.eql(u8, argv[i], git_push_force_flag)) return false;
        i += 1;
    }
    if (!std.mem.eql(u8, argv[i], git_set_upstream_flag)) return false;
    if (!isPlausibleRemoteName(argv[i + 1])) return false;
    return git_branch.isPlausibleBranchName(argv[i + 2]);
}

pub fn isGitSetUpstreamPushArgv(argv: []const []const u8) bool {
    return isUnixGitSetUpstreamPushArgv(argv) or isWindowsGitSetUpstreamPushArgv(argv);
}

pub fn isGitSetUpstreamPushForceArgv(argv: []const []const u8) bool {
    if (isUnixGitSetUpstreamPushArgv(argv)) return argv.len == unix_set_upstream_push_force_argv_len;
    if (isWindowsGitSetUpstreamPushArgv(argv)) return argv.len == windows_set_upstream_push_force_argv_len;
    return false;
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
pub fn unixWorktreeBaseArgvFor(cwd: []const u8, buf: *[worktree_base_argv_len][]const u8) []const []const u8 {
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
    return buf[0..unix_worktree_base_argv_len];
}

/// Windows: `git.exe -C <project_path> symbolic-ref --quiet --short refs/remotes/origin/HEAD`.
pub fn windowsWorktreeBaseArgvFor(cwd: []const u8, buf: *[worktree_base_argv_len][]const u8) []const []const u8 {
    buf[0] = windows_git_bin;
    buf[1] = git_c_flag;
    buf[2] = cwd;
    buf[3] = git_symbolic_ref_cmd;
    buf[4] = git_quiet_flag;
    buf[5] = git_short_flag;
    buf[6] = git_origin_head_ref;
    return buf[0..windows_worktree_base_argv_len];
}

pub fn worktreeBaseArgvFor(cwd: []const u8, buf: *[worktree_base_argv_len][]const u8) []const []const u8 {
    return switch (builtin.os.tag) {
        .windows => windowsWorktreeBaseArgvFor(cwd, buf),
        else => unixWorktreeBaseArgvFor(cwd, buf),
    };
}

fn isUnixGitWorktreeBaseArgv(argv: []const []const u8) bool {
    if (argv.len != unix_worktree_base_argv_len) return false;
    if (!std.mem.eql(u8, argv[0], sh_bin)) return false;
    if (!std.mem.eql(u8, argv[1], "-c")) return false;
    if (!std.mem.eql(u8, argv[2], main.fx_ask_chdir_script)) return false;
    if (!std.mem.eql(u8, argv[5], git_bin)) return false;
    if (!std.mem.eql(u8, argv[6], git_symbolic_ref_cmd)) return false;
    if (!std.mem.eql(u8, argv[7], git_quiet_flag)) return false;
    if (!std.mem.eql(u8, argv[8], git_short_flag)) return false;
    return std.mem.eql(u8, argv[9], git_origin_head_ref);
}

fn isWindowsGitWorktreeBaseArgv(argv: []const []const u8) bool {
    if (argv.len != windows_worktree_base_argv_len) return false;
    if (!windowsGitBinOk(argv[0])) return false;
    if (!std.mem.eql(u8, argv[1], git_c_flag)) return false;
    if (argv[2].len == 0) return false;
    if (!std.mem.eql(u8, argv[3], git_symbolic_ref_cmd)) return false;
    if (!std.mem.eql(u8, argv[4], git_quiet_flag)) return false;
    if (!std.mem.eql(u8, argv[5], git_short_flag)) return false;
    return std.mem.eql(u8, argv[6], git_origin_head_ref);
}

pub fn isGitWorktreeBaseArgv(argv: []const []const u8) bool {
    return isUnixGitWorktreeBaseArgv(argv) or isWindowsGitWorktreeBaseArgv(argv);
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
    if (!git_common_dir.isAbsoluteCommonDir(trimmed)) return null;
    var nest_buf: [worktree_nest_key_len]u8 = undefined;
    const nest = worktreeNestKeyFor(project_path, nest_buf[0..], model) orelse return null;
    const printed = std.fmt.bufPrint(buf, "{s}/{s}/{s}", .{ trimmed, worktree_parent_suffix, nest }) catch return null;
    slashNormalizeInPlace(printed);
    return printed;
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
    if (!git_common_dir.isAbsoluteCommonDir(path)) return false;
    if (std.mem.indexOf(u8, path, "..") != null) return false;
    if (std.mem.indexOfScalar(u8, path, 0) != null) return false;
    return true;
}

fn slashNormalizeInPlace(path: []u8) void {
    for (path) |*ch| {
        if (ch.* == '\\') ch.* = '/';
    }
}

fn slashNormalizedEql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |ca, cb| {
        const na: u8 = if (ca == '\\') '/' else ca;
        const nb: u8 = if (cb == '\\') '/' else cb;
        if (na != nb) return false;
    }
    return true;
}

fn slashNormalizedStartsWith(haystack: []const u8, needle: []const u8) bool {
    if (haystack.len < needle.len) return false;
    return slashNormalizedEql(haystack[0..needle.len], needle);
}

fn isPathSep(c: u8) bool {
    return c == '/' or c == '\\';
}

fn worktreeAddSlotsOk(cwd: []const u8, parent: []const u8, branch: []const u8, path: []const u8, base: []const u8) bool {
    if (cwd.len == 0 or !isSafeWorktreePath(parent) or !isSafeWorktreePath(path)) return false;
    if (!git_branch.isPlausibleBranchName(branch)) return false;
    if (!std.mem.startsWith(u8, branch, worktree_branch_prefix)) return false;
    if (sanitizeWorktreeName(branch[worktree_branch_prefix.len..]) == null) return false;
    if (!std.mem.startsWith(u8, path, parent)) return false;
    if (base.len > 0 and !git_branch.isPlausibleBranchName(base)) return false;
    return true;
}

/// Unix: `mkdir -p -- <parent> && cd -- <cwd> && git worktree add -b <branch> <path> [base]`.
/// Parent, cwd, branch, path, and optional base are argv slots.
/// Empty `base` omits the trailing slot (today's HEAD). Rejects
/// unsafe names so a raw string never reaches the shell script.
pub fn unixWorktreeAddArgvFor(
    cwd: []const u8,
    parent: []const u8,
    branch: []const u8,
    path: []const u8,
    base: []const u8,
    buf: *[worktree_add_argv_len][]const u8,
) ?[]const []const u8 {
    if (!worktreeAddSlotsOk(cwd, parent, branch, path, base)) return null;
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
    if (base.len == 0) return buf[0..unix_worktree_add_no_base_argv_len];
    buf[12] = base;
    return buf[0..unix_worktree_add_argv_len];
}

/// Windows: `powershell.exe -NoProfile -Command {scriptblock} -Args`
/// parent, cwd, git.exe, worktree, add, -b, branch, dest, [base].
/// Paths are never inside the scriptblock. Empty `base` omits the
/// trailing slot (today's HEAD), same as Unix.
pub fn windowsWorktreeAddArgvFor(
    cwd: []const u8,
    parent: []const u8,
    branch: []const u8,
    path: []const u8,
    base: []const u8,
    buf: *[worktree_add_argv_len][]const u8,
) ?[]const []const u8 {
    if (!worktreeAddSlotsOk(cwd, parent, branch, path, base)) return null;
    buf[0] = powershell_bin;
    buf[1] = powershell_noprofile;
    buf[2] = powershell_command;
    buf[3] = git_worktree_mkdir_chdir_ps_script;
    buf[4] = powershell_args_flag;
    buf[5] = parent;
    buf[6] = cwd;
    buf[7] = windows_git_bin;
    buf[8] = git_worktree_cmd;
    buf[9] = git_worktree_add_cmd;
    buf[10] = git_create_b_flag;
    buf[11] = branch;
    buf[12] = path;
    if (base.len == 0) return buf[0..windows_worktree_add_no_base_argv_len];
    buf[13] = base;
    return buf[0..windows_worktree_add_argv_len];
}

pub fn worktreeAddArgvFor(
    cwd: []const u8,
    parent: []const u8,
    branch: []const u8,
    path: []const u8,
    base: []const u8,
    buf: *[worktree_add_argv_len][]const u8,
) ?[]const []const u8 {
    return switch (builtin.os.tag) {
        .windows => windowsWorktreeAddArgvFor(cwd, parent, branch, path, base, buf),
        else => unixWorktreeAddArgvFor(cwd, parent, branch, path, base, buf),
    };
}

fn isUnixGitWorktreeAddArgv(argv: []const []const u8) bool {
    if (argv.len != unix_worktree_add_no_base_argv_len and argv.len != unix_worktree_add_argv_len) return false;
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
    if (argv.len == unix_worktree_add_argv_len) return git_branch.isPlausibleBranchName(argv[12]);
    return true;
}

fn isWindowsGitWorktreeAddArgv(argv: []const []const u8) bool {
    if (argv.len != windows_worktree_add_no_base_argv_len and argv.len != windows_worktree_add_argv_len) return false;
    if (!std.mem.eql(u8, argv[0], powershell_bin)) return false;
    if (!std.mem.eql(u8, argv[1], powershell_noprofile)) return false;
    if (!std.mem.eql(u8, argv[2], powershell_command)) return false;
    if (!std.mem.eql(u8, argv[3], git_worktree_mkdir_chdir_ps_script)) return false;
    if (!std.mem.eql(u8, argv[4], powershell_args_flag)) return false;
    if (!isSafeWorktreePath(argv[5])) return false;
    if (argv[6].len == 0) return false;
    if (!windowsGitBinOk(argv[7])) return false;
    if (!std.mem.eql(u8, argv[8], git_worktree_cmd)) return false;
    if (!std.mem.eql(u8, argv[9], git_worktree_add_cmd)) return false;
    if (!std.mem.eql(u8, argv[10], git_create_b_flag)) return false;
    if (!git_branch.isPlausibleBranchName(argv[11])) return false;
    if (!std.mem.startsWith(u8, argv[11], worktree_branch_prefix)) return false;
    if (sanitizeWorktreeName(argv[11][worktree_branch_prefix.len..]) == null) return false;
    if (!isSafeWorktreePath(argv[12])) return false;
    if (argv.len == windows_worktree_add_argv_len) return git_branch.isPlausibleBranchName(argv[13]);
    return true;
}

pub fn isGitWorktreeAddArgv(argv: []const []const u8) bool {
    return isUnixGitWorktreeAddArgv(argv) or isWindowsGitWorktreeAddArgv(argv);
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
        if (top.len > 0) return wt.len > 0 and slashNormalizedEql(wt, top);
    }
    const proj = std.mem.trim(u8, project_path, " \t\r\n");
    if (wt.len == 0 or proj.len == 0) return false;
    if (slashNormalizedEql(wt, proj)) return true;
    return proj.len > wt.len and slashNormalizedStartsWith(proj, wt) and isPathSep(proj[wt.len]);
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

/// Listed unoccupied local head. Remotes and occupied locals are
/// omitted so a Base pick matches checkout/delete refusal. Current
/// is allowed (unlike delete).
fn isListedLocalUnoccupied(model: *const Model, name: []const u8) bool {
    if (!git_branch.isPlausibleBranchName(name)) return false;
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
    model.git_worktree_base_picker_open = false;
    if (!sessionIsNewWorktree(model)) {
        model.git_worktree_base_override_len = 0;
    }
}

fn sessionIsNewWorktree(model: *const Model) bool {
    const session = model.sessionByIdConst(model.selected) orelse return false;
    return session.workspace_kind == .new_worktree;
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
    model.git_commit_then_push = false;
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
    model.git_branch_delete_force = false;
}

/// Hide the Push… confirm row without resetting Force (Commit…
/// in-dialog Push may still need the toggle).
pub fn closePushConfirm(model: *Model) void {
    model.git_push_confirm_active = false;
}

/// Esc / Cancel on the Push… confirm row. Resets Force.
pub fn cancelPushConfirm(model: *Model) void {
    closePushConfirm(model);
    model.git_push_force = false;
}

/// Dismiss the select list and open the runtime-only create card.
/// Draft name is not persisted.
pub fn startCreate(model: *Model) void {
    closePicker(model);
    closeDelete(model);
    closePushConfirm(model);
    closeWorktreeCreate(model);
    closeCommitCard(model);
    model.closeProjectEdit();
    model.git_branch_create_active = true;
}

/// Dismiss the select list and open the runtime-only New worktree…
/// card. Prefills a prompt slug from the selected session title
/// (`new-worktree` when that slugs empty). Draft name is not
/// persisted; the user can still edit. Resets the runtime-only
/// base override unless the selected session is already a Work-in
/// `newWorktree` draft (that Base is `baseBranch` on
/// `sessions.json`). Closes the Base picker.
pub fn startWorktreeCreate(model: *Model) void {
    closePicker(model);
    closeCreate(model);
    closeDelete(model);
    closePushConfirm(model);
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
/// persisted. Resets Force to off.
pub fn startDelete(model: *Model) void {
    closePicker(model);
    closeCreate(model);
    closeWorktreeCreate(model);
    closePushConfirm(model);
    closeCommitCard(model);
    model.closeProjectEdit();
    model.git_branch_delete_active = true;
    model.git_branch_delete_picker_open = false;
    model.git_branch_delete_len = 0;
    model.git_branch_delete_force = false;
}

pub fn closeDeletePicker(model: *Model) void {
    model.git_branch_delete_picker_open = false;
}

pub fn closeWorktreeBasePicker(model: *Model) void {
    model.git_worktree_base_picker_open = false;
}

pub fn toggleWorktreeBasePicker(model: *Model) void {
    if (!model.git_worktree_create_active and !sessionIsNewWorktree(model)) {
        model.git_worktree_base_picker_open = false;
        return;
    }
    model.git_worktree_base_picker_open = !model.git_worktree_base_picker_open;
}

/// Remember a listed unoccupied local head as the New worktree…
/// / Work-in Base. Does not spawn. Remotes and occupied names are
/// refused. Empty `name` clears. While the selected session is
/// `newWorktree`, also writes `workspace` `baseBranch` and keeps
/// `git_worktree_base_override_*` in sync. The immediate New
/// worktree… card on a Local session stays runtime-only.
pub fn pickWorktreeBaseName(model: *Model, name: []const u8) void {
    model.git_worktree_base_picker_open = false;
    if (name.len == 0) {
        clearWorktreeBaseName(model);
        return;
    }
    if (!isListedLocalUnoccupied(model, name)) return;
    writeFixed(&model.git_worktree_base_override_storage, &model.git_worktree_base_override_len, name);
    if (sessionIsNewWorktree(model)) {
        if (model.sessionById(model.selected)) |session| {
            session.setWorkspaceBaseBranch(name);
        }
    }
}

/// Clear the runtime Base override. While `newWorktree`, also
/// clears stored `baseBranch`.
pub fn clearWorktreeBaseName(model: *Model) void {
    model.git_worktree_base_picker_open = false;
    model.git_worktree_base_override_len = 0;
    if (sessionIsNewWorktree(model)) {
        if (model.sessionById(model.selected)) |session| {
            session.clearWorkspaceBaseBranch();
        }
    }
}

/// Copy stored `newWorktree` `baseBranch` onto the runtime
/// override so Send prep / the Base chip see it after hydrate or
/// select. Other kinds clear the override unless the immediate
/// New worktree… card still owns it (`closeWorktreeCreate`).
pub fn syncWorktreeBaseOverrideFromSession(model: *Model) void {
    if (model.git_worktree_create_active and !sessionIsNewWorktree(model)) return;
    model.git_worktree_base_override_len = 0;
    const session = model.sessionByIdConst(model.selected) orelse return;
    if (session.workspace_kind != .new_worktree) return;
    const base = session.workspaceBaseBranch();
    if (base.len == 0) return;
    writeFixed(&model.git_worktree_base_override_storage, &model.git_worktree_base_override_len, base);
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

/// Runtime-only Delete branch… Force toggle. Default off. Not
/// persisted. No-op while a delete spawn is in flight.
pub fn toggleDeleteForce(model: *Model, fx: *Effects) void {
    _ = fx;
    if (model.git_delete_key != 0) return;
    model.git_branch_delete_force = !model.git_branch_delete_force;
}

/// Runtime-only Push… / Commit… Force toggle. Default off. Not
/// persisted. No-op while a push spawn is in flight.
pub fn togglePushForce(model: *Model, fx: *Effects) void {
    _ = fx;
    if (model.git_push_key != 0) return;
    model.git_push_force = !model.git_push_force;
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
    const argv = if (model.git_push_force)
        pushForceArgvFor(cwd, &argv_buf)
    else
        pushArgvFor(cwd, &argv_buf);
    spawnPushCmd(model, fx, cwd, argv, .push);
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
    const argv = (if (model.git_push_force)
        setUpstreamPushForceArgvFor(cwd, gitPushRemote(model), gitPushBranch(model), &argv_buf)
    else
        setUpstreamPushArgvFor(cwd, gitPushRemote(model), gitPushBranch(model), &argv_buf)) orelse {
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
    if (model.workspace_prep_active) model.abortWorkspacePrep();
}

fn cancelWorktreeBase(model: *Model, fx: *Effects) void {
    if (model.git_worktree_base_key == 0) return;
    fx.cancel(model.git_worktree_base_key);
    model.git_worktree_base_key = 0;
    resetWorktreeAddState(model);
    if (model.workspace_prep_active) model.abortWorkspacePrep();
}

fn probeSupported() bool {
    return true;
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
/// `project_path`. Empty / missing skips the spawn so the
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
    syncWorktreeBaseOverrideFromSession(model);
    closeDelete(model);
    closePushConfirm(model);
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
    model.maybeEnsureSkillsScanned(fx);
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
/// one-shots `git branch -d`, or `git branch -D` when Force is on.
/// Empty / current / occupied / implausible names do not spawn and
/// keep the card open. Busy session or in-flight
/// checkout/create/delete/fetch/push is a no-op.
pub fn confirmDelete(model: *Model, fx: *Effects) void {
    if (gitMutationInFlight(model)) return;
    if (model.is_streaming()) return;
    const name = std.mem.trim(u8, gitBranchDeleteLabel(model), " \t\r\n");
    if (!isListedNonCurrent(model, name)) return;
    if (!probeSupported()) return;
    const cwd = probePath(model);
    if (cwd.len == 0) return;

    var argv_buf: [delete_argv_len][]const u8 = undefined;
    const argv = if (model.git_branch_delete_force)
        deleteForceArgvFor(cwd, name, &argv_buf) orelse return
    else
        deleteArgvFor(cwd, name, &argv_buf) orelse return;

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
    closePushConfirm(model);
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
    closePushConfirm(model);
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

/// Composer menu Push…. Opens a first-cut confirm row (ghost Force
/// + Push + Cancel). Does not spawn until `confirmPush`. Resets
/// Force to off. Closes any open Commit… card. Offered only when
/// `canPushGitBranch` (Waku `can_push` with
/// remotes-required-for-first-push). Busy session or in-flight
/// checkout/create/delete/fetch/push is a no-op. Does not require
/// an open Commit… card.
pub fn startPush(model: *Model, fx: *Effects) void {
    preparePushUi(model, fx, false);
    if (!git_ahead_behind.canPushGitBranch(model)) return;
    if (gitMutationInFlight(model)) return;
    if (model.is_streaming()) return;
    if (!probeSupported()) return;
    if (probePath(model).len == 0) return;
    model.git_push_force = false;
    model.git_push_confirm_active = true;
}

/// Confirm on the Push… row. Same `canPushGitBranch` gates and
/// probe sequence as today's Push…: `@{upstream}` then bare
/// `git push`, or remotes then `git push --set-upstream`. When
/// Force is on, `--force` is its own argv slot after `push`.
pub fn confirmPush(model: *Model, fx: *Effects) void {
    if (!model.git_push_confirm_active) return;
    startGatedPush(model, fx);
}

/// Gated Push… from the Commit… card. Same `canPushGitBranch`
/// gates as `confirmPush`, but keeps the card open so Native can
/// show Pushing… until the push terminates. Honors `git_push_force`.
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
/// mutation). Detached HEAD / no remotes still fail later
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
        closePushConfirm(model);
        return;
    }
    switch (phase) {
        .idle => {
            resetPushState(model);
            closeCommitCard(model);
            closePushConfirm(model);
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

pub fn gitWorktreeBaseOverride(model: *const Model) []const u8 {
    return model.git_worktree_base_override_storage[0..model.git_worktree_base_override_len];
}

fn gitWorktreeBase(model: *const Model) []const u8 {
    return model.git_worktree_base_storage[0..model.git_worktree_base_len];
}

/// Worktree-add start-point: stored `newWorktree` `baseBranch` wins
/// when non-empty, else the runtime override.
pub fn gitWorktreeStartBase(model: *const Model) []const u8 {
    if (model.sessionByIdConst(model.selected)) |session| {
        if (session.workspace_kind == .new_worktree) {
            const stored = session.workspaceBaseBranch();
            if (stored.len > 0) return stored;
        }
    }
    return gitWorktreeBaseOverride(model);
}

/// Trailing `git worktree add` base: stored / override wins when
/// non-empty, else the origin/HEAD probe result (or composer-label
/// fallback).
fn gitWorktreeAddBase(model: *const Model) []const u8 {
    const start = gitWorktreeStartBase(model);
    if (start.len > 0) return start;
    return gitWorktreeBase(model);
}

/// Effective Base label on the New worktree… card / Work-in ghost.
/// Stored / override if set, else resolved origin/HEAD /
/// composer-label fallback already stored on confirm, else the
/// current composer branch, else `HEAD`.
pub fn gitWorktreeBaseLabel(model: *const Model) []const u8 {
    const start = gitWorktreeStartBase(model);
    if (start.len > 0) return start;
    const resolved = gitWorktreeBase(model);
    if (resolved.len > 0) return resolved;
    if (pushBranchFromLabel(git_branch.gitBranchLabel(model))) |branch| return branch;
    return worktree_base_fallback_label;
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
    const argv = worktreeAddArgvFor(stored_cwd, stored_parent, stored_branch, stored_dest, gitWorktreeAddBase(model), &argv_buf) orelse return;

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

/// Confirm the New worktree… card: a non-empty Base (stored
/// `newWorktree` `baseBranch` or runtime override) skips
/// the origin/HEAD probe and one-shots `git worktree add -b
/// faku/<name> <path> <base>`. When that start-point is empty, a
/// safe name probes `refs/remotes/origin/HEAD` then one-shots
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
    beginWorktreeAdd(model, fx, name);
}

/// Shared by the New worktree… confirm card and defer-until-Send.
/// `name` is a dest slug (`sanitizeWorktreeName`); empty / unsafe is
/// a no-op. Same spawn / retry / candidate path as confirm.
/// Non-empty stored `newWorktree` `baseBranch` skips the
/// origin/HEAD probe the same way a runtime override does.
pub fn beginWorktreeAdd(model: *Model, fx: *Effects, name: []const u8) void {
    if (gitMutationInFlight(model)) return;
    if (model.is_streaming()) return;
    const slug = sanitizeWorktreeName(name) orelse return;
    if (!probeSupported()) return;
    const cwd = probePath(model);
    if (cwd.len == 0) return;
    const home = model.homeDir();

    var parent_buf: [main.max_project_path]u8 = undefined;
    const parent = worktreeParentPathFor(home, cwd, parent_buf[0..], model) orelse return;
    writeFixed(&model.git_worktree_add_slug_storage, &model.git_worktree_add_slug_len, slug);
    if (!pickWorktreeCandidate(model, home, cwd, slug, 0)) {
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

    if (gitWorktreeStartBase(model).len > 0) {
        spawnWorktreeAdd(model, fx);
        return;
    }

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
        if (model.workspace_prep_active) model.abortWorkspacePrep();
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
    if (!current) {
        if (model.workspace_prep_active) model.abortWorkspacePrep();
        return false;
    }
    if (exit.reason == .exited and exit.code == 0) {
        const dest = model.git_worktree_add_dest_storage[0..model.git_worktree_add_dest_len];
        const branch = model.git_worktree_add_branch_storage[0..model.git_worktree_add_branch_len];
        if (dest.len > 0) model.setSelectedProjectPath(dest);
        if (model.workspace_prep_active) {
            if (model.sessionById(model.selected)) |session| {
                session.setWorkspaceWorktree(dest, branch);
            }
        }
        closeWorktreeCreate(model);
        resetWorktreeAddState(model);
        return true;
    }
    if (retryWorktreeAdd(model, fx)) return false;
    resetWorktreeAddState(model);
    model.setAttachStatus(worktree_add_failed_status);
    return false;
}

fn pendingSpawnKey(fx: *Effects, key: u64) ?@TypeOf(fx.pendingSpawnAt(0).?) {
    var i: usize = 0;
    while (fx.pendingSpawnAt(i)) |spawn| : (i += 1) {
        if (spawn.key == key) return spawn;
    }
    return null;
}

test "list argv is chdir script plus for-each-ref refs/heads and refs/remotes" {
    var buf: [list_argv_len][]const u8 = undefined;
    const argv = unixListArgvFor("/tmp/faku-heads", &buf);
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
    const argv = unixCheckoutArgvFor("/tmp/faku-co", "feat/composer", &buf).?;
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

    try std.testing.expect(unixCheckoutArgvFor("/tmp/faku-co", "not a branch", &buf) == null);
    try std.testing.expect(unixCheckoutArgvFor("/tmp/faku-co", "../escape", &buf) == null);
    try std.testing.expect(unixCheckoutArgvFor("/tmp/faku-co", "/abs", &buf) == null);
    try std.testing.expect(unixCheckoutArgvFor("/tmp/faku-co", ".hidden", &buf) == null);
    try std.testing.expect(unixCheckoutArgvFor("/tmp/faku-co", "trailing.", &buf) == null);
    try std.testing.expect(unixCheckoutArgvFor("/tmp/faku-co", "@", &buf) == null);
    try std.testing.expect(unixCheckoutArgvFor("/tmp/faku-co", "foo@{bar", &buf) == null);
    try std.testing.expect(unixCheckoutArgvFor("/tmp/faku-co", "", &buf) == null);
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
    const argv = unixTrackCheckoutArgvFor("/tmp/faku-track", "origin/feat", &buf).?;
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

    try std.testing.expect(unixTrackCheckoutArgvFor("/tmp/faku-track", "not a branch", &buf) == null);
    try std.testing.expect(unixTrackCheckoutArgvFor("/tmp/faku-track", "../escape", &buf) == null);
    try std.testing.expect(unixTrackCheckoutArgvFor("/tmp/faku-track", "/abs", &buf) == null);
    try std.testing.expect(unixTrackCheckoutArgvFor("/tmp/faku-track", ".hidden", &buf) == null);
    try std.testing.expect(unixTrackCheckoutArgvFor("/tmp/faku-track", "trailing.", &buf) == null);
    try std.testing.expect(unixTrackCheckoutArgvFor("/tmp/faku-track", "@", &buf) == null);
    try std.testing.expect(unixTrackCheckoutArgvFor("/tmp/faku-track", "foo@{bar", &buf) == null);
    try std.testing.expect(unixTrackCheckoutArgvFor("/tmp/faku-track", "", &buf) == null);
}

test "create argv is checkout -b with the name as its own slot and rejects implausible names" {
    var buf: [create_argv_len][]const u8 = undefined;
    const argv = unixCreateArgvFor("/tmp/faku-new", "feat/new-branch", &buf).?;
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

    try std.testing.expect(unixCreateArgvFor("/tmp/faku-new", "not a branch", &buf) == null);
    try std.testing.expect(unixCreateArgvFor("/tmp/faku-new", "../escape", &buf) == null);
    try std.testing.expect(unixCreateArgvFor("/tmp/faku-new", "/abs", &buf) == null);
    try std.testing.expect(unixCreateArgvFor("/tmp/faku-new", ".hidden", &buf) == null);
    try std.testing.expect(unixCreateArgvFor("/tmp/faku-new", "trailing.", &buf) == null);
    try std.testing.expect(unixCreateArgvFor("/tmp/faku-new", "@", &buf) == null);
    try std.testing.expect(unixCreateArgvFor("/tmp/faku-new", "foo@{bar", &buf) == null);
    try std.testing.expect(unixCreateArgvFor("/tmp/faku-new", "", &buf) == null);
}

test "delete argv is branch -d with the name as its own slot and rejects implausible names" {
    var buf: [delete_argv_len][]const u8 = undefined;
    const argv = unixDeleteArgvFor("/tmp/faku-del", "feat/old-branch", &buf).?;
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
    try std.testing.expect(!isGitDeleteForceArgv(argv));
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

    try std.testing.expect(unixDeleteArgvFor("/tmp/faku-del", "not a branch", &buf) == null);
    try std.testing.expect(unixDeleteArgvFor("/tmp/faku-del", "../escape", &buf) == null);
    try std.testing.expect(unixDeleteArgvFor("/tmp/faku-del", "/abs", &buf) == null);
    try std.testing.expect(unixDeleteArgvFor("/tmp/faku-del", ".hidden", &buf) == null);
    try std.testing.expect(unixDeleteArgvFor("/tmp/faku-del", "trailing.", &buf) == null);
    try std.testing.expect(unixDeleteArgvFor("/tmp/faku-del", "@", &buf) == null);
    try std.testing.expect(unixDeleteArgvFor("/tmp/faku-del", "foo@{bar", &buf) == null);
    try std.testing.expect(unixDeleteArgvFor("/tmp/faku-del", "", &buf) == null);
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

test "force delete argv is branch -D with the name as its own slot and rejects implausible names" {
    var buf: [delete_argv_len][]const u8 = undefined;
    const argv = unixDeleteForceArgvFor("/tmp/faku-del", "feat/old-branch", &buf).?;
    try std.testing.expectEqualStrings(sh_bin, argv[0]);
    try std.testing.expectEqualStrings("-c", argv[1]);
    try std.testing.expectEqualStrings(main.fx_ask_chdir_script, argv[2]);
    try std.testing.expectEqualStrings("sh", argv[3]);
    try std.testing.expectEqualStrings("/tmp/faku-del", argv[4]);
    try std.testing.expectEqualStrings(git_bin, argv[5]);
    try std.testing.expectEqualStrings(git_branch_cmd, argv[6]);
    try std.testing.expectEqualStrings(git_delete_force_flag, argv[7]);
    try std.testing.expectEqualStrings("feat/old-branch", argv[8]);
    try std.testing.expect(isGitDeleteForceArgv(argv));
    try std.testing.expect(!isGitDeleteArgv(argv));
    try std.testing.expect(!isGitCreateArgv(argv));
    try std.testing.expect(!isGitCheckoutArgv(argv));
    try std.testing.expect(!isGitTrackCheckoutArgv(argv));
    try std.testing.expect(!isGitBranchListArgv(argv));
    try std.testing.expect(!isGitFetchArgv(argv));
    try std.testing.expect(!isGitPushArgv(argv));
    try std.testing.expect(!isGitWorktreeAddArgv(argv));
    try std.testing.expect(!git_branch.isGitBranchArgv(argv));
    try std.testing.expect(std.mem.indexOf(u8, argv[2], "feat/old-branch") == null);
    try std.testing.expect(std.mem.indexOf(u8, argv[2], git_delete_force_flag) == null);
    try std.testing.expect(!std.mem.eql(u8, argv[7], git_delete_d_flag));

    try std.testing.expect(unixDeleteForceArgvFor("/tmp/faku-del", "not a branch", &buf) == null);
    try std.testing.expect(unixDeleteForceArgvFor("/tmp/faku-del", "../escape", &buf) == null);
    try std.testing.expect(unixDeleteForceArgvFor("/tmp/faku-del", "/abs", &buf) == null);
    try std.testing.expect(unixDeleteForceArgvFor("/tmp/faku-del", ".hidden", &buf) == null);
    try std.testing.expect(unixDeleteForceArgvFor("/tmp/faku-del", "trailing.", &buf) == null);
    try std.testing.expect(unixDeleteForceArgvFor("/tmp/faku-del", "@", &buf) == null);
    try std.testing.expect(unixDeleteForceArgvFor("/tmp/faku-del", "foo@{bar", &buf) == null);
    try std.testing.expect(unixDeleteForceArgvFor("/tmp/faku-del", "", &buf) == null);
    try std.testing.expect(!isGitDeleteForceArgv(&.{
        sh_bin,
        "-c",
        main.fx_ask_chdir_script,
        "sh",
        "/tmp/faku-del",
        git_bin,
        git_branch_cmd,
        git_delete_d_flag,
        "feat/old-branch",
    }));
}

test "startDelete resets Force to off" {
    var model = Model{};
    model.git_branch_delete_force = true;
    startDelete(&model);
    try std.testing.expect(model.git_branch_delete_active);
    try std.testing.expect(!model.git_branch_delete_force);
    try std.testing.expectEqual(@as(usize, 0), model.git_branch_delete_len);
}

test "toggleDeleteForce defaults off, flips, and no-ops while delete is in flight" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    try std.testing.expect(!model.git_branch_delete_force);
    startDelete(&model);
    try std.testing.expect(!model.git_branch_delete_force);
    toggleDeleteForce(&model, &fx);
    try std.testing.expect(model.git_branch_delete_force);
    toggleDeleteForce(&model, &fx);
    try std.testing.expect(!model.git_branch_delete_force);
    toggleDeleteForce(&model, &fx);
    try std.testing.expect(model.git_branch_delete_force);

    model.git_delete_key = git_delete_key_first;
    toggleDeleteForce(&model, &fx);
    try std.testing.expect(model.git_branch_delete_force);
    model.git_delete_key = 0;
    toggleDeleteForce(&model, &fx);
    try std.testing.expect(!model.git_branch_delete_force);

    model.git_branch_delete_force = true;
    closeDelete(&model);
    try std.testing.expect(!model.git_branch_delete_active);
    try std.testing.expect(!model.git_branch_delete_force);
}

test "confirmDelete picks -d vs -D from the Force toggle" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/git-del-force", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("delete force", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);
    writeFixed(&model.git_branch_storage, &model.git_branch_len, "main");
    model.git_branch_list_store[0].set("feat/old", false, false);
    model.git_branch_list_store[1].set("main", false, false);
    model.git_branch_list_count = 2;

    startDelete(&model);
    try std.testing.expect(!model.git_branch_delete_force);
    pickDeleteName(&model, "feat/old");
    confirmDelete(&model, &fx);
    const safe = pendingSpawnKey(&fx, model.git_delete_key) orelse return error.MissingGitDeleteSpawn;
    try std.testing.expect(isGitDeleteArgv(safe.argv));
    try std.testing.expect(!isGitDeleteForceArgv(safe.argv));
    try std.testing.expectEqualStrings(git_delete_d_flag, safe.argv[safe.argv.len - 2]);
    try std.testing.expectEqualStrings("feat/old", safe.argv[safe.argv.len - 1]);
    if (std.mem.eql(u8, safe.argv[0], sh_bin)) {
        try std.testing.expect(std.mem.indexOf(u8, safe.argv[2], git_delete_d_flag) == null);
    }
    try std.testing.expect(safe.key >= git_delete_key_first);
    try std.testing.expect(safe.key < git_fetch_key_first);

    handleDeleteExit(&model, &fx, .{ .key = safe.key, .reason = .exited, .code = 1 });
    try std.testing.expectEqual(@as(u64, 0), model.git_delete_key);
    try std.testing.expect(model.git_branch_delete_active);
    try std.testing.expectEqualStrings(delete_failed_status, model.attach_status());

    toggleDeleteForce(&model, &fx);
    try std.testing.expect(model.git_branch_delete_force);
    confirmDelete(&model, &fx);
    const forced = pendingSpawnKey(&fx, model.git_delete_key) orelse return error.MissingGitDeleteForceSpawn;
    try std.testing.expect(isGitDeleteForceArgv(forced.argv));
    try std.testing.expect(!isGitDeleteArgv(forced.argv));
    try std.testing.expectEqualStrings(git_delete_force_flag, forced.argv[forced.argv.len - 2]);
    try std.testing.expectEqualStrings("feat/old", forced.argv[forced.argv.len - 1]);
    if (std.mem.eql(u8, forced.argv[0], sh_bin)) {
        try std.testing.expect(std.mem.indexOf(u8, forced.argv[2], git_delete_force_flag) == null);
    }
    try std.testing.expect(forced.key >= git_delete_key_first);
    try std.testing.expect(forced.key < git_fetch_key_first);
    try std.testing.expect(forced.key != safe.key);

    handleDeleteExit(&model, &fx, .{ .key = forced.key, .reason = .exited, .code = 0 });
    try std.testing.expectEqual(@as(u64, 0), model.git_delete_key);
    try std.testing.expect(!model.git_branch_delete_active);
    try std.testing.expect(!model.git_branch_delete_force);
}

test "fetch argv is fetch --prune as its own slot and is not fetch-without-prune" {
    var buf: [fetch_argv_len][]const u8 = undefined;
    const argv = unixFetchArgvFor("/tmp/faku-fetch", &buf);
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
    const argv = unixPushArgvFor("/tmp/faku-push", &buf);
    try std.testing.expectEqual(@as(usize, 7), argv.len);
    try std.testing.expectEqualStrings(sh_bin, argv[0]);
    try std.testing.expectEqualStrings("-c", argv[1]);
    try std.testing.expectEqualStrings(main.fx_ask_chdir_script, argv[2]);
    try std.testing.expectEqualStrings("sh", argv[3]);
    try std.testing.expectEqualStrings("/tmp/faku-push", argv[4]);
    try std.testing.expectEqualStrings(git_bin, argv[5]);
    try std.testing.expectEqualStrings(git_push_cmd, argv[6]);
    try std.testing.expect(isGitPushArgv(argv));
    try std.testing.expect(!isGitPushForceArgv(argv));
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

test "force push argv is git push --force as its own slot and still classifies as push" {
    var buf: [push_argv_len][]const u8 = undefined;
    const argv = unixPushForceArgvFor("/tmp/faku-push-force", &buf);
    try std.testing.expectEqual(@as(usize, unix_push_force_argv_len), argv.len);
    try std.testing.expectEqualStrings(sh_bin, argv[0]);
    try std.testing.expectEqualStrings("-c", argv[1]);
    try std.testing.expectEqualStrings(main.fx_ask_chdir_script, argv[2]);
    try std.testing.expectEqualStrings("sh", argv[3]);
    try std.testing.expectEqualStrings("/tmp/faku-push-force", argv[4]);
    try std.testing.expectEqualStrings(git_bin, argv[5]);
    try std.testing.expectEqualStrings(git_push_cmd, argv[6]);
    try std.testing.expectEqualStrings(git_push_force_flag, argv[7]);
    try std.testing.expect(isGitPushArgv(argv));
    try std.testing.expect(isGitPushForceArgv(argv));
    try std.testing.expect(!isGitSetUpstreamPushArgv(argv));
    try std.testing.expect(!isGitFetchArgv(argv));
    try std.testing.expect(std.mem.indexOf(u8, argv[2], git_push_cmd) == null);
    try std.testing.expect(std.mem.indexOf(u8, argv[2], git_push_force_flag) == null);
    try std.testing.expect(!isGitPushArgv(&.{
        sh_bin,
        "-c",
        main.fx_ask_chdir_script,
        "sh",
        "/tmp/faku-push-force",
        git_bin,
        git_push_cmd,
        "--force-with-lease",
    }));
    try std.testing.expect(!isGitPushForceArgv(&.{
        sh_bin,
        "-c",
        main.fx_ask_chdir_script,
        "sh",
        "/tmp/faku-push-force",
        git_bin,
        git_push_cmd,
    }));
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
        "C:/Users/u/.faku/worktrees/2599eb06cf360587",
        worktreeParentPath("C:\\Users\\u", "/tmp/proj", path_buf[0..]).?,
    );
    try std.testing.expectEqualStrings(
        "C:/Users/u/.faku/worktrees/2599eb06cf360587",
        worktreeParentPath("C:/Users/u", "/tmp/proj", path_buf[0..]).?,
    );
    try std.testing.expectEqualStrings(
        "C:/Users/u/.faku/worktrees/2599eb06cf360587/feat",
        worktreeDestPath("C:\\Users\\u", "/tmp/proj", "feat", path_buf[0..]).?,
    );
    try std.testing.expectEqualStrings(
        "C:/Users/u/.faku/worktrees/2599eb06cf360587/feat",
        worktreeDestPath("C:/Users/u", "/tmp/proj", "feat", path_buf[0..]).?,
    );
    try std.testing.expect(worktreeParentPath("Users\\u", "/tmp/proj", path_buf[0..]) == null);
    try std.testing.expect(worktreeDestPath("relative", "/tmp/proj", "feat", path_buf[0..]) == null);
    try std.testing.expect(isSafeWorktreePath("/home/u/.faku/worktrees/2599eb06cf360587/feat"));
    try std.testing.expect(isSafeWorktreePath("C:/Users/u/.faku/worktrees/2599eb06cf360587/feat"));
    try std.testing.expect(isSafeWorktreePath("C:\\Users\\u\\.faku\\worktrees\\nest\\feat"));
    try std.testing.expect(!isSafeWorktreePath("relative"));
    try std.testing.expect(!isSafeWorktreePath("../escape"));
    try std.testing.expect(!isSafeWorktreePath(""));
    try std.testing.expect(!isSafeWorktreePath("/tmp/proj/../other"));
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
    const argv = unixWorktreeBaseArgvFor("/tmp/faku-wt-base", &buf);
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

    const argv = unixWorktreeAddArgvFor(
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

    const with_base = unixWorktreeAddArgvFor(
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

    const origin_base = unixWorktreeAddArgvFor(
        "/tmp/faku-repo",
        parent,
        "faku/feat",
        dest,
        "origin/main",
        &buf,
    ).?;
    try std.testing.expectEqualStrings("origin/main", origin_base[12]);
    try std.testing.expect(isGitWorktreeAddArgv(origin_base));

    try std.testing.expect(unixWorktreeAddArgvFor("/tmp/repo", parent, "feat", dest, "", &buf) == null);
    try std.testing.expect(unixWorktreeAddArgvFor("/tmp/repo", parent, "faku/feat/foo", dest, "", &buf) == null);
    try std.testing.expect(unixWorktreeAddArgvFor("/tmp/repo", "relative", "faku/feat", dest, "", &buf) == null);
    try std.testing.expect(unixWorktreeAddArgvFor("/tmp/repo", parent, "faku/feat", "/tmp/other/feat", "", &buf) == null);
    try std.testing.expect(unixWorktreeAddArgvFor("/tmp/repo", parent, "faku/feat", "/home/u/.faku/worktrees/feat", "", &buf) == null);
    try std.testing.expect(unixWorktreeAddArgvFor("", parent, "faku/feat", dest, "", &buf) == null);
    try std.testing.expect(unixWorktreeAddArgvFor("/tmp/repo", parent, "faku/feat", dest, "not a branch", &buf) == null);
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
    try std.testing.expectEqualStrings("faku/feat-2", spawn.argv[spawn.argv.len - 2]);
    try std.testing.expectEqualStrings("/home/u/.faku/worktrees/2599eb06cf360587/feat-2", spawn.argv[spawn.argv.len - 1]);
    if (std.mem.eql(u8, spawn.argv[0], sh_bin)) {
        try std.testing.expectEqualStrings("/home/u/.faku/worktrees/2599eb06cf360587", spawn.argv[4]);
    } else {
        try std.testing.expectEqualStrings("/home/u/.faku/worktrees/2599eb06cf360587", spawn.argv[5]);
    }

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

test "startWorktreeCreate and cancel reset the Base override and picker" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    const id = model.addSession("worktree base", .fx);
    model.selected = id;
    model.git_branch_list_store[0].set("main", false, false);
    model.git_branch_list_store[1].set("feat", false, false);
    model.git_branch_list_count = 2;
    writeFixed(&model.git_branch_storage, &model.git_branch_len, "main");

    startWorktreeCreate(&model);
    try std.testing.expect(model.git_worktree_create_active);
    try std.testing.expect(!model.git_worktree_base_picker_open);
    try std.testing.expectEqual(@as(usize, 0), model.git_worktree_base_override_len);
    try std.testing.expectEqualStrings("main", gitWorktreeBaseLabel(&model));

    toggleWorktreeBasePicker(&model);
    try std.testing.expect(model.git_worktree_base_picker_open);
    pickWorktreeBaseName(&model, "feat");
    try std.testing.expect(!model.git_worktree_base_picker_open);
    try std.testing.expectEqualStrings("feat", gitWorktreeBaseOverride(&model));
    try std.testing.expectEqualStrings("feat", gitWorktreeBaseLabel(&model));

    startWorktreeCreate(&model);
    try std.testing.expectEqual(@as(usize, 0), model.git_worktree_base_override_len);
    try std.testing.expect(!model.git_worktree_base_picker_open);
    try std.testing.expectEqualStrings("main", gitWorktreeBaseLabel(&model));

    pickWorktreeBaseName(&model, "feat");
    try std.testing.expectEqualStrings("feat", gitWorktreeBaseOverride(&model));
    dismissWorktreeCreate(&model, &fx);
    try std.testing.expect(!model.git_worktree_create_active);
    try std.testing.expectEqual(@as(usize, 0), model.git_worktree_base_override_len);
    try std.testing.expect(!model.git_worktree_base_picker_open);
}

test "pickWorktreeBaseName keeps listed locals and refuses remotes and occupied" {
    var model = Model{};
    writeFixed(&model.git_branch_storage, &model.git_branch_len, "main");
    model.git_branch_list_store[0].set("main", false, false);
    model.git_branch_list_store[1].set("feat", false, false);
    model.git_branch_list_store[2].set("busy", false, true);
    model.git_branch_list_store[3].set("origin/main", true, false);
    model.git_branch_list_count = 4;
    model.git_worktree_create_active = true;

    pickWorktreeBaseName(&model, "origin/main");
    try std.testing.expectEqual(@as(usize, 0), model.git_worktree_base_override_len);
    pickWorktreeBaseName(&model, "busy");
    try std.testing.expectEqual(@as(usize, 0), model.git_worktree_base_override_len);
    pickWorktreeBaseName(&model, "not-listed");
    try std.testing.expectEqual(@as(usize, 0), model.git_worktree_base_override_len);

    model.git_worktree_base_picker_open = true;
    pickWorktreeBaseName(&model, "main");
    try std.testing.expect(!model.git_worktree_base_picker_open);
    try std.testing.expectEqualStrings("main", gitWorktreeBaseOverride(&model));
    pickWorktreeBaseName(&model, "feat");
    try std.testing.expectEqualStrings("feat", gitWorktreeBaseOverride(&model));
}

test "gitWorktreeBaseLabel prefers override then resolved then branch then HEAD" {
    var model = Model{};
    try std.testing.expectEqualStrings(worktree_base_fallback_label, gitWorktreeBaseLabel(&model));

    writeFixed(&model.git_branch_storage, &model.git_branch_len, "a1b2c3d");
    try std.testing.expectEqualStrings(worktree_base_fallback_label, gitWorktreeBaseLabel(&model));

    writeFixed(&model.git_branch_storage, &model.git_branch_len, "develop");
    try std.testing.expectEqualStrings("develop", gitWorktreeBaseLabel(&model));

    writeFixed(&model.git_worktree_base_storage, &model.git_worktree_base_len, "main");
    try std.testing.expectEqualStrings("main", gitWorktreeBaseLabel(&model));

    writeFixed(&model.git_worktree_base_override_storage, &model.git_worktree_base_override_len, "feat");
    try std.testing.expectEqualStrings("feat", gitWorktreeBaseLabel(&model));
}

test "confirmWorktreeAdd override skips origin/HEAD probe and wins the add argv" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/git-wt-base", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);
    var home_buf: [256]u8 = undefined;
    const home = try std.fmt.bufPrint(&home_buf, "/tmp/faku-wt-base-{s}", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, home);

    var model = Model{};
    model.store_io = std.testing.io;
    model.setHome(home);
    const id = model.addSession("worktree base override", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);
    writeFixed(&model.git_branch_storage, &model.git_branch_len, "main");
    model.git_branch_list_store[0].set("main", false, false);
    model.git_branch_list_store[1].set("feat", false, false);
    model.git_branch_list_count = 2;

    startWorktreeCreate(&model);
    model.git_worktree_create_buffer.clear();
    model.git_worktree_create_buffer.apply(.{ .insert_text = "feat-new" });
    writeFixed(&model.git_worktree_base_storage, &model.git_worktree_base_len, "main");
    pickWorktreeBaseName(&model, "feat");
    try std.testing.expectEqualStrings("feat", gitWorktreeBaseOverride(&model));

    confirmWorktreeAdd(&model, &fx);
    try std.testing.expectEqual(@as(u64, 0), model.git_worktree_base_key);
    try std.testing.expect(model.git_worktree_add_key >= git_worktree_add_key_first);
    const spawned = pendingSpawnKey(&fx, model.git_worktree_add_key) orelse return error.MissingGitWorktreeAddOverride;
    try std.testing.expect(isGitWorktreeAddArgv(spawned.argv));
    try std.testing.expectEqualStrings("feat", spawned.argv[spawned.argv.len - 1]);
    try std.testing.expect(!isGitWorktreeBaseArgv(spawned.argv));
    if (std.mem.eql(u8, spawned.argv[0], sh_bin)) {
        try std.testing.expectEqual(@as(usize, unix_worktree_add_argv_len), spawned.argv.len);
        try std.testing.expect(std.mem.indexOf(u8, spawned.argv[2], "feat") == null);
    } else {
        try std.testing.expectEqual(@as(usize, windows_worktree_add_argv_len), spawned.argv.len);
        try std.testing.expect(std.mem.indexOf(u8, spawned.argv[3], "feat") == null);
    }
}

test "confirmWorktreeAdd with empty override still probes origin/HEAD" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/git-wt-base-auto", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);
    var home_buf: [256]u8 = undefined;
    const home = try std.fmt.bufPrint(&home_buf, "/tmp/faku-wt-base-auto-{s}", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, home);

    var model = Model{};
    model.store_io = std.testing.io;
    model.setHome(home);
    const id = model.addSession("worktree base auto", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);
    writeFixed(&model.git_branch_storage, &model.git_branch_len, "main");

    startWorktreeCreate(&model);
    model.git_worktree_create_buffer.clear();
    model.git_worktree_create_buffer.apply(.{ .insert_text = "feat-auto" });
    try std.testing.expectEqual(@as(usize, 0), model.git_worktree_base_override_len);
    confirmWorktreeAdd(&model, &fx);
    try std.testing.expectEqual(@as(u64, 0), model.git_worktree_add_key);
    try std.testing.expect(model.git_worktree_base_key >= git_worktree_base_key_first);
    const probe = pendingSpawnKey(&fx, model.git_worktree_base_key) orelse return error.MissingGitWorktreeBaseProbe;
    try std.testing.expect(isGitWorktreeBaseArgv(probe.argv));
    try std.testing.expect(!isGitWorktreeAddArgv(probe.argv));
}

test "set-upstream push argv keeps flag, remote, and branch as their own slots" {
    var buf: [set_upstream_push_argv_len][]const u8 = undefined;
    const argv = unixSetUpstreamPushArgvFor("/tmp/faku-push-u", "origin", "feat/new", &buf).?;
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
    try std.testing.expect(!isGitSetUpstreamPushForceArgv(argv));
    try std.testing.expect(!isGitPushArgv(argv));
    try std.testing.expect(!isGitFetchArgv(argv));
    try std.testing.expect(!isGitUpstreamArgv(argv));
    try std.testing.expect(!isGitRemoteArgv(argv));
    try std.testing.expect(!git_branch.isGitBranchArgv(argv));
    try std.testing.expect(std.mem.indexOf(u8, argv[2], git_push_cmd) == null);
    try std.testing.expect(std.mem.indexOf(u8, argv[2], git_set_upstream_flag) == null);
    try std.testing.expect(std.mem.indexOf(u8, argv[2], "origin") == null);
    try std.testing.expect(std.mem.indexOf(u8, argv[2], "feat/new") == null);

    try std.testing.expect(unixSetUpstreamPushArgvFor("/tmp/faku-push-u", "origin", "not a branch", &buf) == null);
    try std.testing.expect(unixSetUpstreamPushArgvFor("/tmp/faku-push-u", "../escape", "main", &buf) == null);
    try std.testing.expect(unixSetUpstreamPushArgvFor("/tmp/faku-push-u", "", "main", &buf) == null);
    try std.testing.expect(unixSetUpstreamPushArgvFor("/tmp/faku-push-u", "origin", "", &buf) == null);
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

test "force set-upstream push argv keeps --force after push as its own slot" {
    var buf: [set_upstream_push_argv_len][]const u8 = undefined;
    const argv = unixSetUpstreamPushForceArgvFor("/tmp/faku-push-u-force", "origin", "feat/new", &buf).?;
    try std.testing.expectEqual(@as(usize, unix_set_upstream_push_force_argv_len), argv.len);
    try std.testing.expectEqualStrings(git_push_cmd, argv[6]);
    try std.testing.expectEqualStrings(git_push_force_flag, argv[7]);
    try std.testing.expectEqualStrings(git_set_upstream_flag, argv[8]);
    try std.testing.expectEqualStrings("origin", argv[9]);
    try std.testing.expectEqualStrings("feat/new", argv[10]);
    try std.testing.expect(isGitSetUpstreamPushArgv(argv));
    try std.testing.expect(isGitSetUpstreamPushForceArgv(argv));
    try std.testing.expect(!isGitPushArgv(argv));
    try std.testing.expect(!isGitPushForceArgv(argv));
    try std.testing.expect(std.mem.indexOf(u8, argv[2], git_push_force_flag) == null);
    try std.testing.expect(std.mem.indexOf(u8, argv[2], git_set_upstream_flag) == null);
    try std.testing.expect(unixSetUpstreamPushForceArgvFor("/tmp/faku-push-u-force", "origin", "not a branch", &buf) == null);
}

test "upstream argv is rev-parse symbolic-full-name @{upstream}" {
    var buf: [upstream_argv_len][]const u8 = undefined;
    const argv = unixUpstreamArgvFor("/tmp/faku-up", &buf);
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
    const argv = unixRemoteArgvFor("/tmp/faku-remote", &buf);
    try std.testing.expectEqual(@as(usize, 7), argv.len);
    try std.testing.expectEqualStrings(git_remote_cmd, argv[6]);
    try std.testing.expect(isGitRemoteArgv(argv));
    try std.testing.expect(!isGitPushArgv(argv));
    try std.testing.expect(!isGitSetUpstreamPushArgv(argv));
    try std.testing.expect(!isGitUpstreamArgv(argv));
    try std.testing.expect(!isGitFetchArgv(argv));
}

fn expectRejectsSiblingWindowsArgv(pred: *const fn ([]const []const u8) bool, cwd: []const u8) !void {
    var branch_buf: [git_branch.argv_len][]const u8 = undefined;
    try std.testing.expect(!pred(git_branch.windowsArgvFor(cwd, &branch_buf)));
    var dirty_buf: [git_dirty.argv_len][]const u8 = undefined;
    try std.testing.expect(!pred(git_dirty.windowsArgvFor(cwd, &dirty_buf)));
    var numstat_buf: [git_numstat.argv_len][]const u8 = undefined;
    try std.testing.expect(!pred(git_numstat.windowsArgvFor(cwd, &numstat_buf)));
    var ahead_buf: [git_ahead_behind.argv_len][]const u8 = undefined;
    try std.testing.expect(!pred(git_ahead_behind.windowsArgvFor(cwd, &ahead_buf)));
    var remotes_buf: [git_remotes.argv_len][]const u8 = undefined;
    try std.testing.expect(!pred(git_remotes.windowsArgvFor(cwd, &remotes_buf)));
    var top_buf: [git_toplevel.argv_len][]const u8 = undefined;
    try std.testing.expect(!pred(git_toplevel.windowsArgvFor(cwd, &top_buf)));
    var common_buf: [git_common_dir.argv_len][]const u8 = undefined;
    try std.testing.expect(!pred(git_common_dir.windowsArgvFor(cwd, &common_buf)));
    var mention_buf: [file_mention.git_argv_len][]const u8 = undefined;
    try std.testing.expect(!pred(file_mention.windowsArgvFor(cwd, &mention_buf)));
    try std.testing.expect(!pred(&.{ windows_git_bin, git_c_flag, cwd, "add", "-A", "--", "." }));
    try std.testing.expect(!pred(&.{ windows_git_bin, git_c_flag, cwd, "commit", "-m", "msg" }));
}

test "windows git argv is git.exe -C PATH; path is its own slot" {
    const cwd = "C:\\Users\\me\\proj";
    var list_buf: [list_argv_len][]const u8 = undefined;
    const list = windowsListArgvFor(cwd, &list_buf);
    try std.testing.expectEqual(@as(usize, windows_list_argv_len), list.len);
    try std.testing.expect(list.len <= 16);
    try std.testing.expectEqualStrings(windows_git_bin, list[0]);
    try std.testing.expectEqualStrings(git_c_flag, list[1]);
    try std.testing.expectEqualStrings(cwd, list[2]);
    try std.testing.expectEqualStrings(git_for_each_ref_cmd, list[3]);
    try std.testing.expectEqualStrings(git_refname_format, list[4]);
    try std.testing.expectEqualStrings(git_heads_ref, list[5]);
    try std.testing.expectEqualStrings(git_remotes_ref, list[6]);
    try std.testing.expect(isGitBranchListArgv(list));
    try std.testing.expect(!isGitCheckoutArgv(list));
    try std.testing.expect(!isGitBranchListArgv(&.{ windows_git_bin, git_c_flag, cwd }));
    var git_only: [list_argv_len][]const u8 = undefined;
    git_only[0] = git_bin;
    git_only[1] = git_c_flag;
    git_only[2] = cwd;
    git_only[3] = git_for_each_ref_cmd;
    git_only[4] = git_refname_format;
    git_only[5] = git_heads_ref;
    git_only[6] = git_remotes_ref;
    try std.testing.expect(isGitBranchListArgv(git_only[0..windows_list_argv_len]));
    try expectRejectsSiblingWindowsArgv(&isGitBranchListArgv, cwd);

    var co_buf: [checkout_argv_len][]const u8 = undefined;
    const co = windowsCheckoutArgvFor(cwd, "feat/composer", &co_buf).?;
    try std.testing.expectEqual(@as(usize, windows_checkout_argv_len), co.len);
    try std.testing.expectEqualStrings(git_checkout_cmd, co[3]);
    try std.testing.expectEqualStrings("feat/composer", co[4]);
    try std.testing.expect(isGitCheckoutArgv(co));
    try std.testing.expect(!isGitTrackCheckoutArgv(co));
    try std.testing.expect(!isGitCreateArgv(co));
    try std.testing.expect(!isGitCheckoutArgv(&.{ windows_git_bin, git_c_flag, cwd }));
    try expectRejectsSiblingWindowsArgv(&isGitCheckoutArgv, cwd);
    try std.testing.expect(windowsCheckoutArgvFor(cwd, "not a branch", &co_buf) == null);

    var track_buf: [track_checkout_argv_len][]const u8 = undefined;
    const track = windowsTrackCheckoutArgvFor(cwd, "origin/feat", &track_buf).?;
    try std.testing.expectEqual(@as(usize, windows_track_checkout_argv_len), track.len);
    try std.testing.expectEqualStrings(git_track_flag, track[4]);
    try std.testing.expectEqualStrings("origin/feat", track[5]);
    try std.testing.expect(isGitTrackCheckoutArgv(track));
    try std.testing.expect(!isGitCheckoutArgv(track));
    try std.testing.expect(!isGitTrackCheckoutArgv(&.{ windows_git_bin, git_c_flag, cwd }));
    try expectRejectsSiblingWindowsArgv(&isGitTrackCheckoutArgv, cwd);

    var create_buf: [create_argv_len][]const u8 = undefined;
    const created = windowsCreateArgvFor(cwd, "feat/new", &create_buf).?;
    try std.testing.expectEqual(@as(usize, windows_create_argv_len), created.len);
    try std.testing.expectEqualStrings(git_create_b_flag, created[4]);
    try std.testing.expect(isGitCreateArgv(created));
    try std.testing.expect(!isGitCheckoutArgv(created));
    try expectRejectsSiblingWindowsArgv(&isGitCreateArgv, cwd);

    var del_buf: [delete_argv_len][]const u8 = undefined;
    const del = windowsDeleteArgvFor(cwd, "feat/old", &del_buf).?;
    try std.testing.expectEqual(@as(usize, windows_delete_argv_len), del.len);
    try std.testing.expectEqualStrings(git_branch_cmd, del[3]);
    try std.testing.expectEqualStrings(git_delete_d_flag, del[4]);
    try std.testing.expect(isGitDeleteArgv(del));
    try std.testing.expect(!isGitDeleteForceArgv(del));
    try expectRejectsSiblingWindowsArgv(&isGitDeleteArgv, cwd);
    const forced = windowsDeleteForceArgvFor(cwd, "feat/old", &del_buf).?;
    try std.testing.expectEqualStrings(git_delete_force_flag, forced[4]);
    try std.testing.expect(isGitDeleteForceArgv(forced));
    try std.testing.expect(!isGitDeleteArgv(forced));
    try expectRejectsSiblingWindowsArgv(&isGitDeleteForceArgv, cwd);

    var fetch_buf: [fetch_argv_len][]const u8 = undefined;
    const fetched = windowsFetchArgvFor(cwd, &fetch_buf);
    try std.testing.expectEqual(@as(usize, windows_fetch_argv_len), fetched.len);
    try std.testing.expectEqualStrings(git_fetch_cmd, fetched[3]);
    try std.testing.expectEqualStrings(git_prune_flag, fetched[4]);
    try std.testing.expect(isGitFetchArgv(fetched));
    try std.testing.expect(!isGitFetchArgv(&.{ windows_git_bin, git_c_flag, cwd }));
    try expectRejectsSiblingWindowsArgv(&isGitFetchArgv, cwd);

    var push_buf: [push_argv_len][]const u8 = undefined;
    const pushed = windowsPushArgvFor(cwd, &push_buf);
    try std.testing.expectEqual(@as(usize, windows_push_argv_len), pushed.len);
    try std.testing.expectEqualStrings(git_push_cmd, pushed[3]);
    try std.testing.expect(isGitPushArgv(pushed));
    try std.testing.expect(!isGitPushForceArgv(pushed));
    try std.testing.expect(!isGitSetUpstreamPushArgv(pushed));
    try std.testing.expect(!isGitPushArgv(&.{ windows_git_bin, git_c_flag, cwd }));
    try expectRejectsSiblingWindowsArgv(&isGitPushArgv, cwd);
    const pushed_force = windowsPushForceArgvFor(cwd, &push_buf);
    try std.testing.expectEqual(@as(usize, windows_push_force_argv_len), pushed_force.len);
    try std.testing.expectEqualStrings(git_push_cmd, pushed_force[3]);
    try std.testing.expectEqualStrings(git_push_force_flag, pushed_force[4]);
    try std.testing.expect(isGitPushArgv(pushed_force));
    try std.testing.expect(isGitPushForceArgv(pushed_force));
    try std.testing.expect(!isGitSetUpstreamPushArgv(pushed_force));
    try expectRejectsSiblingWindowsArgv(&isGitPushForceArgv, cwd);

    var up_buf: [upstream_argv_len][]const u8 = undefined;
    const up = windowsUpstreamArgvFor(cwd, &up_buf);
    try std.testing.expectEqual(@as(usize, windows_upstream_argv_len), up.len);
    try std.testing.expectEqualStrings(git_rev_parse_cmd, up[3]);
    try std.testing.expectEqualStrings(git_abbrev_ref, up[4]);
    try std.testing.expectEqualStrings(git_symbolic_full_name, up[5]);
    try std.testing.expectEqualStrings(git_upstream_rev, up[6]);
    try std.testing.expect(isGitUpstreamArgv(up));
    try std.testing.expect(!git_branch.isGitRevParseArgv(up));
    try std.testing.expect(!isGitUpstreamArgv(&.{ windows_git_bin, git_c_flag, cwd }));
    try expectRejectsSiblingWindowsArgv(&isGitUpstreamArgv, cwd);

    var remote_buf: [remote_argv_len][]const u8 = undefined;
    const remote = windowsRemoteArgvFor(cwd, &remote_buf);
    try std.testing.expectEqual(@as(usize, windows_remote_argv_len), remote.len);
    try std.testing.expectEqualStrings(git_remote_cmd, remote[3]);
    try std.testing.expect(isGitRemoteArgv(remote));
    try std.testing.expect(git_remotes.isGitRemotesArgv(remote));
    try std.testing.expect(!isGitPushArgv(remote));
    try std.testing.expect(!isGitRemoteArgv(&.{ windows_git_bin, git_c_flag, cwd }));
    var branch_buf: [git_branch.argv_len][]const u8 = undefined;
    try std.testing.expect(!isGitRemoteArgv(git_branch.windowsArgvFor(cwd, &branch_buf)));
    var dirty_buf: [git_dirty.argv_len][]const u8 = undefined;
    try std.testing.expect(!isGitRemoteArgv(git_dirty.windowsArgvFor(cwd, &dirty_buf)));

    var set_buf: [set_upstream_push_argv_len][]const u8 = undefined;
    const set_up = windowsSetUpstreamPushArgvFor(cwd, "origin", "feat/new", &set_buf).?;
    try std.testing.expectEqual(@as(usize, windows_set_upstream_push_argv_len), set_up.len);
    try std.testing.expectEqualStrings(git_set_upstream_flag, set_up[4]);
    try std.testing.expectEqualStrings("origin", set_up[5]);
    try std.testing.expectEqualStrings("feat/new", set_up[6]);
    try std.testing.expect(isGitSetUpstreamPushArgv(set_up));
    try std.testing.expect(!isGitSetUpstreamPushForceArgv(set_up));
    try std.testing.expect(!isGitPushArgv(set_up));
    try expectRejectsSiblingWindowsArgv(&isGitSetUpstreamPushArgv, cwd);
    try std.testing.expect(windowsSetUpstreamPushArgvFor(cwd, "origin", "not a branch", &set_buf) == null);
    const set_force = windowsSetUpstreamPushForceArgvFor(cwd, "origin", "feat/new", &set_buf).?;
    try std.testing.expectEqual(@as(usize, windows_set_upstream_push_force_argv_len), set_force.len);
    try std.testing.expectEqualStrings(git_push_cmd, set_force[3]);
    try std.testing.expectEqualStrings(git_push_force_flag, set_force[4]);
    try std.testing.expectEqualStrings(git_set_upstream_flag, set_force[5]);
    try std.testing.expectEqualStrings("origin", set_force[6]);
    try std.testing.expectEqualStrings("feat/new", set_force[7]);
    try std.testing.expect(isGitSetUpstreamPushArgv(set_force));
    try std.testing.expect(isGitSetUpstreamPushForceArgv(set_force));
    try std.testing.expect(!isGitPushArgv(set_force));
    try expectRejectsSiblingWindowsArgv(&isGitSetUpstreamPushForceArgv, cwd);

    var base_buf: [worktree_base_argv_len][]const u8 = undefined;
    const base = windowsWorktreeBaseArgvFor(cwd, &base_buf);
    try std.testing.expectEqual(@as(usize, windows_worktree_base_argv_len), base.len);
    try std.testing.expectEqualStrings(git_symbolic_ref_cmd, base[3]);
    try std.testing.expectEqualStrings(git_quiet_flag, base[4]);
    try std.testing.expectEqualStrings(git_short_flag, base[5]);
    try std.testing.expectEqualStrings(git_origin_head_ref, base[6]);
    try std.testing.expect(isGitWorktreeBaseArgv(base));
    try std.testing.expect(!isGitWorktreeAddArgv(base));
    try std.testing.expect(!isGitWorktreeBaseArgv(&.{ windows_git_bin, git_c_flag, cwd }));
    try expectRejectsSiblingWindowsArgv(&isGitWorktreeBaseArgv, cwd);
}

test "windows worktree add argv is powershell -Command + -Args; paths stay slots" {
    var buf: [worktree_add_argv_len][]const u8 = undefined;
    var parent_buf: [main.max_project_path]u8 = undefined;
    const parent = worktreeParentPath("C:\\Users\\u", "C:\\tmp\\faku-repo", parent_buf[0..]).?;
    var dest_buf: [main.max_project_path]u8 = undefined;
    const dest = worktreeDestPath("C:\\Users\\u", "C:\\tmp\\faku-repo", "feat", dest_buf[0..]).?;
    try std.testing.expect(std.mem.startsWith(u8, parent, "C:/Users/u/.faku/worktrees/"));
    try std.testing.expect(std.mem.startsWith(u8, dest, parent));
    try std.testing.expect(std.mem.endsWith(u8, dest, "/feat"));
    try std.testing.expect(std.mem.indexOfScalar(u8, parent, '\\') == null);
    try std.testing.expect(std.mem.indexOfScalar(u8, dest, '\\') == null);

    const argv = windowsWorktreeAddArgvFor("C:\\tmp\\faku-repo", parent, "faku/feat", dest, "", &buf).?;
    try std.testing.expectEqual(@as(usize, windows_worktree_add_no_base_argv_len), argv.len);
    try std.testing.expect(argv.len <= 16);
    try std.testing.expectEqualStrings(powershell_bin, argv[0]);
    try std.testing.expectEqualStrings(powershell_noprofile, argv[1]);
    try std.testing.expectEqualStrings(powershell_command, argv[2]);
    try std.testing.expectEqualStrings(git_worktree_mkdir_chdir_ps_script, argv[3]);
    try std.testing.expectEqualStrings(powershell_args_flag, argv[4]);
    try std.testing.expectEqualStrings(parent, argv[5]);
    try std.testing.expectEqualStrings("C:\\tmp\\faku-repo", argv[6]);
    try std.testing.expectEqualStrings(windows_git_bin, argv[7]);
    try std.testing.expectEqualStrings(git_worktree_cmd, argv[8]);
    try std.testing.expectEqualStrings(git_worktree_add_cmd, argv[9]);
    try std.testing.expectEqualStrings(git_create_b_flag, argv[10]);
    try std.testing.expectEqualStrings("faku/feat", argv[11]);
    try std.testing.expectEqualStrings(dest, argv[12]);
    try std.testing.expect(isGitWorktreeAddArgv(argv));
    try std.testing.expect(!isGitWorktreeBaseArgv(argv));
    try std.testing.expect(!isGitCreateArgv(argv));
    try std.testing.expect(!file_mention.isWalkArgv(argv));
    try std.testing.expect(std.mem.indexOf(u8, argv[3], parent) == null);
    try std.testing.expect(std.mem.indexOf(u8, argv[3], dest) == null);
    try std.testing.expect(std.mem.indexOf(u8, argv[3], "faku/feat") == null);
    try std.testing.expect(std.mem.indexOf(u8, argv[3], "C:\\tmp\\faku-repo") == null);
    try expectRejectsSiblingWindowsArgv(&isGitWorktreeAddArgv, "C:\\tmp\\faku-repo");
    var walk_buf: [file_mention.walk_argv_len][]const u8 = undefined;
    try std.testing.expect(!isGitWorktreeAddArgv(file_mention.windowsWalkArgvFor("C:\\tmp\\faku-repo", &walk_buf)));

    const with_base = windowsWorktreeAddArgvFor("C:\\tmp\\faku-repo", parent, "faku/feat", dest, "main", &buf).?;
    try std.testing.expectEqual(@as(usize, windows_worktree_add_argv_len), with_base.len);
    try std.testing.expectEqualStrings("main", with_base[13]);
    try std.testing.expect(isGitWorktreeAddArgv(with_base));
    try std.testing.expect(std.mem.indexOf(u8, with_base[3], "main") == null);

    try std.testing.expect(windowsWorktreeAddArgvFor("C:\\tmp\\repo", parent, "feat", dest, "", &buf) == null);
    try std.testing.expect(windowsWorktreeAddArgvFor("C:\\tmp\\repo", "relative", "faku/feat", dest, "", &buf) == null);
    try std.testing.expect(!isGitWorktreeAddArgv(&.{
        powershell_bin,
        powershell_noprofile,
        powershell_command,
        git_worktree_mkdir_chdir_ps_script,
        powershell_args_flag,
        parent,
    }));
}

test "host argvFor matches the process OS" {
    var list_buf: [list_argv_len][]const u8 = undefined;
    const list = listArgvFor("/tmp/faku-heads", &list_buf);
    try std.testing.expect(isGitBranchListArgv(list));
    var co_buf: [checkout_argv_len][]const u8 = undefined;
    const co = checkoutArgvFor("/tmp/faku-co", "feat", &co_buf).?;
    try std.testing.expect(isGitCheckoutArgv(co));
    var track_buf: [track_checkout_argv_len][]const u8 = undefined;
    const track = trackCheckoutArgvFor("/tmp/faku-track", "origin/feat", &track_buf).?;
    try std.testing.expect(isGitTrackCheckoutArgv(track));
    var create_buf: [create_argv_len][]const u8 = undefined;
    const created = createArgvFor("/tmp/faku-new", "feat/new", &create_buf).?;
    try std.testing.expect(isGitCreateArgv(created));
    var del_buf: [delete_argv_len][]const u8 = undefined;
    const del = deleteArgvFor("/tmp/faku-del", "feat/old", &del_buf).?;
    try std.testing.expect(isGitDeleteArgv(del));
    var fetch_buf: [fetch_argv_len][]const u8 = undefined;
    const fetched = fetchArgvFor("/tmp/faku-fetch", &fetch_buf);
    try std.testing.expect(isGitFetchArgv(fetched));
    var push_buf: [push_argv_len][]const u8 = undefined;
    const pushed = pushArgvFor("/tmp/faku-push", &push_buf);
    try std.testing.expect(isGitPushArgv(pushed));
    var up_buf: [upstream_argv_len][]const u8 = undefined;
    const up = upstreamArgvFor("/tmp/faku-up", &up_buf);
    try std.testing.expect(isGitUpstreamArgv(up));
    var remote_buf: [remote_argv_len][]const u8 = undefined;
    const remote = remoteArgvFor("/tmp/faku-remote", &remote_buf);
    try std.testing.expect(isGitRemoteArgv(remote));
    var set_buf: [set_upstream_push_argv_len][]const u8 = undefined;
    const set_up = setUpstreamPushArgvFor("/tmp/faku-push-u", "origin", "feat/new", &set_buf).?;
    try std.testing.expect(isGitSetUpstreamPushArgv(set_up));
    var base_buf: [worktree_base_argv_len][]const u8 = undefined;
    const base = worktreeBaseArgvFor("/tmp/faku-wt-base", &base_buf);
    try std.testing.expect(isGitWorktreeBaseArgv(base));
    var parent_buf: [main.max_project_path]u8 = undefined;
    const parent = worktreeParentPath("/home/u", "/tmp/faku-repo", parent_buf[0..]).?;
    var dest_buf: [main.max_project_path]u8 = undefined;
    const dest = worktreeDestPath("/home/u", "/tmp/faku-repo", "feat", dest_buf[0..]).?;
    var wt_buf: [worktree_add_argv_len][]const u8 = undefined;
    const wt = worktreeAddArgvFor("/tmp/faku-repo", parent, "faku/feat", dest, "", &wt_buf).?;
    try std.testing.expect(isGitWorktreeAddArgv(wt));
    switch (builtin.os.tag) {
        .windows => {
            try std.testing.expectEqualStrings(windows_git_bin, list[0]);
            try std.testing.expectEqualStrings(git_c_flag, list[1]);
            try std.testing.expectEqualStrings(windows_git_bin, co[0]);
            try std.testing.expectEqualStrings(windows_git_bin, pushed[0]);
            try std.testing.expectEqualStrings(powershell_bin, wt[0]);
            try std.testing.expectEqualStrings(powershell_args_flag, wt[4]);
        },
        else => {
            try std.testing.expectEqualStrings(sh_bin, list[0]);
            try std.testing.expectEqualStrings(sh_bin, co[0]);
            try std.testing.expectEqualStrings(sh_bin, pushed[0]);
            try std.testing.expectEqualStrings(sh_bin, wt[0]);
            try std.testing.expectEqualStrings(git_worktree_mkdir_chdir_script, wt[2]);
        },
    }
}

test "probeSupported is true on macOS, Linux, and Windows" {
    try std.testing.expect(probeSupported());
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
        .{ .raw = "refs/heads/feat\x00C:\\tmp\\proj\n", .project_path = "C:/tmp/proj", .name = "feat", .remote = false, .occupied = false },
        .{ .raw = "refs/heads/feat\x00C:\\tmp\\proj\n", .project_path = "C:/tmp/proj/src", .name = "feat", .remote = false, .occupied = false },
        .{ .raw = "refs/heads/occupied\x00C:\\tmp\\other\n", .project_path = "C:/tmp/proj", .name = "occupied", .remote = false, .occupied = true },
    };
    var refs: [max_listed_branches]ParsedRef = undefined;
    for (cases) |case| {
        const n = collectStdoutRefs(case.raw, case.project_path, refs[0..]);
        try std.testing.expectEqual(@as(usize, 1), n);
        try std.testing.expectEqualStrings(case.name, refs[0].name);
        try std.testing.expectEqual(case.remote, refs[0].remote);
        try std.testing.expectEqual(case.occupied, refs[0].occupied);
    }

    try std.testing.expect(isThisWorktreePath("C:\\tmp\\proj", "C:/tmp/proj"));
    try std.testing.expect(isThisWorktreePath("C:\\tmp\\proj", "C:/tmp/proj/src"));
    try std.testing.expect(isThisWorktreePath("C:/tmp/proj", "C:\\tmp\\proj\\src"));
    try std.testing.expect(!isThisWorktreePath("", "C:/tmp/proj"));
    try std.testing.expect(!isThisWorktreePath("C:\\tmp\\other", "C:/tmp/proj"));

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
    try std.testing.expect(model.git_push_confirm_active);
    try std.testing.expect(!model.git_push_force);
    try std.testing.expectEqual(@as(u64, 0), model.git_push_key);
    try std.testing.expect(!model.git_commit_active);
    try std.testing.expect(!model.has_git_commit_pushing());
    confirmPush(&model, &fx);
    try std.testing.expect(model.git_push_key >= git_push_key_first);
    try std.testing.expectEqual(GitPushPhase.upstream, model.git_push_phase);
    try std.testing.expect(model.git_push_confirm_active);
    try std.testing.expect(!model.has_git_commit_pushing());

    model.git_push_key = 0;
    model.git_push_phase = .idle;
    cancelPush(&model, &fx);
    model.git_commit_active = true;
    model.git_push_force = true;
    startPush(&model, &fx);
    try std.testing.expect(!model.git_commit_active);
    try std.testing.expect(!model.has_git_commit_pushing());
    try std.testing.expect(model.git_push_confirm_active);
    try std.testing.expect(!model.git_push_force);
    try std.testing.expectEqual(@as(u64, 0), model.git_push_key);
    confirmPush(&model, &fx);
    try std.testing.expect(model.git_push_key >= git_push_key_first);
}

test "startPush resets Force to off" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/git-push-force-reset", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("push force reset", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);
    model.git_ahead_behind_ready = true;
    model.git_ahead_behind_has_upstream = true;
    model.git_ahead_behind_ahead = 1;
    model.git_push_force = true;
    startPush(&model, &fx);
    try std.testing.expect(model.git_push_confirm_active);
    try std.testing.expect(!model.git_push_force);
    try std.testing.expectEqual(@as(u64, 0), model.git_push_key);
}

test "togglePushForce defaults off, flips, and no-ops while push is in flight" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/git-push-force-toggle", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("push force toggle", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);
    model.git_ahead_behind_ready = true;
    model.git_ahead_behind_has_upstream = true;
    model.git_ahead_behind_ahead = 1;
    try std.testing.expect(!model.git_push_force);
    startPush(&model, &fx);
    try std.testing.expect(!model.git_push_force);
    togglePushForce(&model, &fx);
    try std.testing.expect(model.git_push_force);
    togglePushForce(&model, &fx);
    try std.testing.expect(!model.git_push_force);
    togglePushForce(&model, &fx);
    try std.testing.expect(model.git_push_force);

    confirmPush(&model, &fx);
    try std.testing.expect(model.git_push_key >= git_push_key_first);
    togglePushForce(&model, &fx);
    try std.testing.expect(model.git_push_force);
    model.git_push_key = 0;
    togglePushForce(&model, &fx);
    try std.testing.expect(!model.git_push_force);

    model.git_push_force = true;
    cancelPushConfirm(&model);
    try std.testing.expect(!model.git_push_confirm_active);
    try std.testing.expect(!model.git_push_force);
}

test "confirmPush picks --force from the Force toggle" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/git-push-force-spawn", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("push force spawn", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);
    model.git_ahead_behind_ready = true;
    model.git_ahead_behind_has_upstream = true;
    model.git_ahead_behind_ahead = 1;

    startPush(&model, &fx);
    try std.testing.expect(!model.git_push_force);
    confirmPush(&model, &fx);
    const up = pendingSpawnKey(&fx, model.git_push_key) orelse return error.MissingGitUpstreamSpawn;
    try std.testing.expect(isGitUpstreamArgv(up.argv));
    applyPushLine(&model, .{ .key = up.key, .line = "origin/main\n" });
    handlePushExit(&model, &fx, .{ .key = up.key, .reason = .exited, .code = 0 });
    const safe = pendingSpawnKey(&fx, model.git_push_key) orelse return error.MissingGitPushSpawn;
    try std.testing.expect(isGitPushArgv(safe.argv));
    try std.testing.expect(!isGitPushForceArgv(safe.argv));
    try std.testing.expectEqualStrings(git_push_cmd, safe.argv[safe.argv.len - 1]);
    if (std.mem.eql(u8, safe.argv[0], sh_bin)) {
        try std.testing.expect(std.mem.indexOf(u8, safe.argv[2], git_push_force_flag) == null);
    }
    handlePushExit(&model, &fx, .{ .key = safe.key, .reason = .exited, .code = 1 });
    try std.testing.expectEqual(@as(u64, 0), model.git_push_key);
    try std.testing.expect(model.git_push_confirm_active);
    try std.testing.expectEqualStrings(push_failed_status, model.attach_status());

    togglePushForce(&model, &fx);
    try std.testing.expect(model.git_push_force);
    confirmPush(&model, &fx);
    const up_force = pendingSpawnKey(&fx, model.git_push_key) orelse return error.MissingGitUpstreamForceSpawn;
    applyPushLine(&model, .{ .key = up_force.key, .line = "origin/main\n" });
    handlePushExit(&model, &fx, .{ .key = up_force.key, .reason = .exited, .code = 0 });
    const forced = pendingSpawnKey(&fx, model.git_push_key) orelse return error.MissingGitPushForceSpawn;
    try std.testing.expect(isGitPushForceArgv(forced.argv));
    try std.testing.expect(isGitPushArgv(forced.argv));
    try std.testing.expectEqualStrings(git_push_force_flag, forced.argv[forced.argv.len - 1]);
    try std.testing.expectEqualStrings(git_push_cmd, forced.argv[forced.argv.len - 2]);
    if (std.mem.eql(u8, forced.argv[0], sh_bin)) {
        try std.testing.expect(std.mem.indexOf(u8, forced.argv[2], git_push_force_flag) == null);
    }
    try std.testing.expect(forced.key != safe.key);

    handlePushExit(&model, &fx, .{ .key = forced.key, .reason = .exited, .code = 0 });
    try std.testing.expectEqual(@as(u64, 0), model.git_push_key);
    try std.testing.expect(!model.git_push_confirm_active);
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
