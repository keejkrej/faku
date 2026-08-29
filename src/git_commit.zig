//! First-cut InspectCommit flags + include-unstaged Commit… / Commit
//! and Push / Push-only, plus a one-shot CommitSnapshot numstat
//! label and an fx-first empty-message `generate_message`, for the
//! composer project row.
//!
//! Native has no git effect. `canCommitGit` follows Waku `can_commit`:
//! dirty probe idle, and staged or (include_unstaged and unstaged).
//! Confirm with include_unstaged one-shots `git add -A -- .` then
//! always `git diff --cached --quiet --` (Waku's commit gate). Exit
//! `1` means there are staged changes and proceeds to
//! `git commit -m <message>`; exit `0` is
//! `Nothing staged to commit.` and does not run commit; any other
//! exit or spawn failure is `Could not commit.`. With the toggle
//! off it skips add and one-shots the same cached-quiet preflight
//! then commit. Every flag and operand is its own argv slot —
//! never interpolated into the `-c` script
//! (`fx_ask_chdir_script`). Message is trimmed, taken as a single
//! line, and capped at 200 chars (Waku `chars().take(200)`). Empty
//! / whitespace on Commit / Commit and Push one-shots documented
//! `fx ask --no-save --auto --json` when `fx_available` and
//! `fxPath` are set, fills the normalized subject, then
//! auto-proceeds into the same add/preflight/commit path. If fx is
//! unavailable or the path is empty, it sets
//! `Enter a commit message.` and does not spawn. Generate fail
//! / empty output keeps the card open with
//! `Could not generate a commit message.` Commit and Push uses
//! the same commit path; on successful commit it starts the existing
//! Push… probe/spawn via `beginPushAfterCommit` (ungated vs
//! `canPushGitBranch` — ahead/behind is stale after the commit).
//! Commit stays commit-only. Push-only (Waku `CommitAction::Push`)
//! does not commit, generate, or run this preflight; it is gated
//! by `canPushGitBranch` (same as composer Push…) and, after
//! dismissing the card the same way Cancel does, reuses
//! `startPush`. Empty / whitespace message is fine. In-flight
//! generate or add/preflight/commit is a no-op. First cut closes
//! the card then starts Push… — not Waku's in-dialog pending
//! spinner. Opening the card one-shots CommitSnapshot
//! numstat (include-unstaged on reuses the project-row
//! `git_numstat` script: tracked `git diff --numstat HEAD --` plus
//! untracked text-line additions; index vs HEAD `--cached` when
//! off). The toggle cancels and re-probes. Cancel / Esc /
//! session-switch drop an in-flight generate/add/preflight/commit
//! and the snapshot probe, and do not start a push. Commit and
//! Push is offered only when `canCommitGit` and first-push remotes
//! are OK (known upstream, or remotes ready with at least one
//! remote). Push-only is offered only when `canPushGitBranch`.
//! Not git-common-dir nest identity, not force / amend, not
//! in-dialog Pushing spinner, and not daemon `WorkspaceOperation`.
//!
//! Spawn/line/exit orchestration lives here. Windows is skipped
//! (app.zon is macos/linux; no Windows spawn path).

const std = @import("std");
const builtin = @import("builtin");
const native_sdk = @import("native_sdk");
const main = @import("main.zig");
const git_branch = @import("git_branch.zig");
const git_checkout = @import("git_checkout.zig");
const git_dirty = @import("git_dirty.zig");
const git_numstat = @import("git_numstat.zig");
const git_ahead_behind = @import("git_ahead_behind.zig");
const git_remotes = @import("git_remotes.zig");
const file_mention = @import("file_mention.zig");

const Model = main.Model;
const Effects = main.Effects;
const writeFixed = main.writeFixed;

/// One-shot `git add -A -- .` then `git commit -m` on one spawn-key
/// band. Distinct from file_mention (400+); sits after that band with
/// headroom so it does not occupy 400–409. Incremented per spawn so
/// a cancelled add cannot paint a later session's commit. CommitSnapshot
/// numstat uses `git_commit_numstat_key_first` (460+) so the two
/// families do not share keys.
pub const git_commit_key_first: u64 = 450;

/// One-shot CommitSnapshot numstat for the Commit… card. Distinct from
/// add/commit (450+), project-row `git_numstat` (350+), and
/// file_mention (400+). Incremented per probe so a cancelled spawn
/// cannot paint a later card.
pub const git_commit_numstat_key_first: u64 = 460;

/// One-shot empty-message `fx ask` generate for the Commit… card.
/// Distinct from add/commit (450+) and CommitSnapshot numstat (460+).
/// Incremented per spawn so a cancelled generate cannot paint a later
/// card.
pub const git_commit_generate_key_first: u64 = 470;

/// Waku `chars().take(200)` plus a byte cap on the runtime TextBuffer.
pub const max_commit_message: usize = 200;

/// Enough for one `fx ask --json` object whose `output` is a subject.
pub const max_generate_stdout: usize = 4096;

pub const empty_message_status = "Enter a commit message.";
pub const commit_failed_status = "Could not commit.";
pub const nothing_staged_status = "Nothing staged to commit.";
pub const generate_failed_status = "Could not generate a commit message.";

pub const fx_ask_cmd = "ask";
pub const fx_ask_no_save = "--no-save";
pub const fx_ask_auto = "--auto";
pub const fx_ask_json = "--json";
pub const fx_ask_dash = "--";

/// Include-unstaged on: inspect staged, unstaged, and untracked.
pub const generate_prompt_include_unstaged =
    "Write a one-line Git commit subject for the current uncommitted changes that will be included (staged, unstaged, and untracked). Inspect the repository yourself. Use imperative mood. Do not use quotes, Markdown, a conventional prefix, an explanation, or a trailing period. At most 72 characters.";

/// Include-unstaged off: inspect staged changes only.
pub const generate_prompt_staged =
    "Write a one-line Git commit subject for the staged changes only. Inspect the repository yourself. Use imperative mood. Do not use quotes, Markdown, a conventional prefix, an explanation, or a trailing period. At most 72 characters.";

/// Add / cached-quiet preflight / commit stages that share
/// `git_commit_key` (450+).
pub const GitCommitPhase = enum(u8) {
    idle,
    add,
    cached_quiet,
    commit,
};

pub const git_bin = git_branch.git_bin;
pub const git_add_cmd = "add";
pub const git_add_all_flag = "-A";
pub const git_pathspec_dash = "--";
pub const git_pathspec_dot = ".";
pub const git_commit_cmd = "commit";
pub const git_message_flag = "-m";
pub const git_diff_cmd = git_numstat.git_diff_cmd;
pub const git_numstat_flag = git_numstat.git_numstat;
pub const git_cached_flag = "--cached";
pub const git_quiet_flag = "--quiet";
pub const sh_bin = git_branch.sh_bin;

pub const add_argv_len: usize = 10;
pub const cached_quiet_argv_len: usize = 10;
pub const commit_argv_len: usize = 9;
/// Max CommitSnapshot argv slots. Cached is 10; include-unstaged
/// reuses `git_numstat.argv_len` (8) inside this buffer.
pub const commit_numstat_argv_len: usize = 10;
pub const generate_argv_len: usize = 12;

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

fn commitCwd(model: *const Model) []const u8 {
    const probed = model.git_commit_probe_path_storage[0..model.git_commit_probe_path_len];
    if (probed.len > 0) return probed;
    return probePath(model);
}

fn commitStillCurrent(model: *const Model) bool {
    if (model.git_commit_key == 0) return false;
    if (model.git_commit_probe_session != model.selected) return false;
    const path = model.selectedProjectPath();
    const probed = model.git_commit_probe_path_storage[0..model.git_commit_probe_path_len];
    return std.mem.eql(u8, path, probed);
}

fn resetCommitState(model: *Model) void {
    model.git_commit_phase = .idle;
    model.git_commit_message_len = 0;
    model.git_commit_then_push = false;
}

fn failCommit(model: *Model) void {
    model.git_commit_key = 0;
    resetCommitState(model);
    model.setAttachStatus(commit_failed_status);
}

/// Hide while the dirty probe is in flight; show when porcelain XY
/// has staged, or unstaged while `include_unstaged` is on (Waku
/// `can_commit`).
pub fn canCommitGit(model: *const Model) bool {
    if (model.git_dirty_key != 0) return false;
    if (model.git_has_staged) return true;
    return model.git_commit_include_unstaged and model.git_has_unstaged;
}

/// Commit and Push: `can_commit` plus first-push remotes. Known
/// upstream allows (post-commit push can work when ahead was 0).
/// No-upstream / unknown requires remotes ready and at least one
/// remote. Hide while remotes are still needed or in-flight on that
/// path (no flash).
pub fn canCommitAndPushGit(model: *const Model) bool {
    if (!canCommitGit(model)) return false;
    return git_remotes.firstPushRemotesOk(model);
}

/// Trim ends, take the first line, then at most 200 UTF-8 scalars
/// (Waku `chars().take(200)`). Null when the result is empty.
pub fn normalizeMessage(raw: []const u8, out: *[max_commit_message]u8) ?[]const u8 {
    const trimmed = std.mem.trim(u8, raw, " \t\r\n");
    if (trimmed.len == 0) return null;
    const line_end = std.mem.indexOfAny(u8, trimmed, "\r\n") orelse trimmed.len;
    const line = std.mem.trim(u8, trimmed[0..line_end], " \t\r\n");
    if (line.len == 0) return null;
    var n: usize = 0;
    var chars: usize = 0;
    while (n < line.len and chars < max_commit_message) {
        const taken = std.unicode.utf8ByteSequenceLength(line[n]) catch break;
        if (n + taken > line.len) break;
        if (n + taken > out.len) break;
        @memcpy(out[n .. n + taken], line[n .. n + taken]);
        n += taken;
        chars += 1;
    }
    if (n == 0) return null;
    return out[0..n];
}

pub fn addArgvFor(cwd: []const u8, buf: *[add_argv_len][]const u8) []const []const u8 {
    buf.* = .{
        sh_bin,
        "-c",
        main.fx_ask_chdir_script,
        "sh",
        cwd,
        git_bin,
        git_add_cmd,
        git_add_all_flag,
        git_pathspec_dash,
        git_pathspec_dot,
    };
    return buf;
}

pub fn isGitCommitAddArgv(argv: []const []const u8) bool {
    if (argv.len != add_argv_len) return false;
    if (!std.mem.eql(u8, argv[0], sh_bin)) return false;
    if (!std.mem.eql(u8, argv[1], "-c")) return false;
    if (!std.mem.eql(u8, argv[2], main.fx_ask_chdir_script)) return false;
    if (!std.mem.eql(u8, argv[5], git_bin)) return false;
    if (!std.mem.eql(u8, argv[6], git_add_cmd)) return false;
    if (!std.mem.eql(u8, argv[7], git_add_all_flag)) return false;
    if (!std.mem.eql(u8, argv[8], git_pathspec_dash)) return false;
    return std.mem.eql(u8, argv[9], git_pathspec_dot);
}

pub fn commitArgvFor(cwd: []const u8, message: []const u8, buf: *[commit_argv_len][]const u8) []const []const u8 {
    buf.* = .{
        sh_bin,
        "-c",
        main.fx_ask_chdir_script,
        "sh",
        cwd,
        git_bin,
        git_commit_cmd,
        git_message_flag,
        message,
    };
    return buf;
}

pub fn isGitCommitArgv(argv: []const []const u8) bool {
    if (argv.len != commit_argv_len) return false;
    if (!std.mem.eql(u8, argv[0], sh_bin)) return false;
    if (!std.mem.eql(u8, argv[1], "-c")) return false;
    if (!std.mem.eql(u8, argv[2], main.fx_ask_chdir_script)) return false;
    if (!std.mem.eql(u8, argv[5], git_bin)) return false;
    if (!std.mem.eql(u8, argv[6], git_commit_cmd)) return false;
    return std.mem.eql(u8, argv[7], git_message_flag);
}

/// `git diff --cached --quiet --`. Same chdir script as add/commit;
/// every flag is its own argv slot. Distinct from CommitSnapshot
/// cached numstat (`--numstat`) and the project-row working-tree
/// numstat script.
pub fn cachedQuietArgvFor(cwd: []const u8, buf: *[cached_quiet_argv_len][]const u8) []const []const u8 {
    buf.* = .{
        sh_bin,
        "-c",
        main.fx_ask_chdir_script,
        "sh",
        cwd,
        git_bin,
        git_diff_cmd,
        git_cached_flag,
        git_quiet_flag,
        git_pathspec_dash,
    };
    return buf;
}

pub fn isGitCommitCachedQuietArgv(argv: []const []const u8) bool {
    if (argv.len != cached_quiet_argv_len) return false;
    if (!std.mem.eql(u8, argv[0], sh_bin)) return false;
    if (!std.mem.eql(u8, argv[1], "-c")) return false;
    if (!std.mem.eql(u8, argv[2], main.fx_ask_chdir_script)) return false;
    if (!std.mem.eql(u8, argv[5], git_bin)) return false;
    if (!std.mem.eql(u8, argv[6], git_diff_cmd)) return false;
    if (!std.mem.eql(u8, argv[7], git_cached_flag)) return false;
    if (!std.mem.eql(u8, argv[8], git_quiet_flag)) return false;
    return std.mem.eql(u8, argv[9], git_pathspec_dash);
}

fn isChdirGitDiffArgv(argv: []const []const u8) bool {
    if (argv.len != commit_numstat_argv_len) return false;
    if (!std.mem.eql(u8, argv[0], sh_bin)) return false;
    if (!std.mem.eql(u8, argv[1], "-c")) return false;
    if (!std.mem.eql(u8, argv[2], main.fx_ask_chdir_script)) return false;
    if (!std.mem.eql(u8, argv[5], git_bin)) return false;
    return std.mem.eql(u8, argv[6], git_diff_cmd);
}

/// Index vs HEAD: `git diff --cached --numstat --`. Staged only;
/// no untracked rows.
pub fn commitNumstatCachedArgvFor(cwd: []const u8, buf: *[commit_numstat_argv_len][]const u8) []const []const u8 {
    buf.* = .{
        sh_bin,
        "-c",
        main.fx_ask_chdir_script,
        "sh",
        cwd,
        git_bin,
        git_diff_cmd,
        git_cached_flag,
        git_numstat_flag,
        git_pathspec_dash,
    };
    return buf;
}

/// Include-unstaged on: reuse `git_numstat.argvFor` (len 8, inner
/// `sh -c` + `numstat_untracked_script`). Off: cached numstat
/// (len 10). Cwd stays its own argv slot; nothing is interpolated
/// into the chdir `-c` script.
pub fn commitNumstatArgvFor(cwd: []const u8, include_unstaged: bool, buf: *[commit_numstat_argv_len][]const u8) []const []const u8 {
    if (include_unstaged) {
        var work: [git_numstat.argv_len][]const u8 = undefined;
        const argv = git_numstat.argvFor(cwd, &work);
        for (argv, 0..) |slot, i| buf[i] = slot;
        return buf[0..argv.len];
    }
    return commitNumstatCachedArgvFor(cwd, buf);
}

/// Include-unstaged on: same argv as the project-row probe.
/// Distinct spawn-key band (460+) keeps the two probes apart.
pub fn isGitCommitNumstatWorkingTreeArgv(argv: []const []const u8) bool {
    return git_numstat.isGitNumstatArgv(argv);
}

pub fn isGitCommitNumstatCachedArgv(argv: []const []const u8) bool {
    if (!isChdirGitDiffArgv(argv)) return false;
    if (!std.mem.eql(u8, argv[7], git_cached_flag)) return false;
    if (!std.mem.eql(u8, argv[8], git_numstat_flag)) return false;
    return std.mem.eql(u8, argv[9], git_pathspec_dash);
}

pub fn isGitCommitNumstatArgv(argv: []const []const u8) bool {
    return isGitCommitNumstatWorkingTreeArgv(argv) or isGitCommitNumstatCachedArgv(argv);
}

pub fn generatePromptFor(include_unstaged: bool) []const u8 {
    if (include_unstaged) return generate_prompt_include_unstaged;
    return generate_prompt_staged;
}

/// `/bin/sh -c` chdir + `fx ask --no-save --auto --json -- <prompt>`.
/// Documented fx-ask flags only. Prompt is its own argv slot.
pub fn generateArgvFor(
    cwd: []const u8,
    fx_path: []const u8,
    include_unstaged: bool,
    buf: *[generate_argv_len][]const u8,
) []const []const u8 {
    buf.* = .{
        sh_bin,
        "-c",
        main.fx_ask_chdir_script,
        "sh",
        cwd,
        fx_path,
        fx_ask_cmd,
        fx_ask_no_save,
        fx_ask_auto,
        fx_ask_json,
        fx_ask_dash,
        generatePromptFor(include_unstaged),
    };
    return buf;
}

pub fn isGitCommitGenerateArgv(argv: []const []const u8) bool {
    if (argv.len != generate_argv_len) return false;
    if (!std.mem.eql(u8, argv[0], sh_bin)) return false;
    if (!std.mem.eql(u8, argv[1], "-c")) return false;
    if (!std.mem.eql(u8, argv[2], main.fx_ask_chdir_script)) return false;
    if (!std.mem.eql(u8, argv[6], fx_ask_cmd)) return false;
    if (!std.mem.eql(u8, argv[7], fx_ask_no_save)) return false;
    if (!std.mem.eql(u8, argv[8], fx_ask_auto)) return false;
    if (!std.mem.eql(u8, argv[9], fx_ask_json)) return false;
    return std.mem.eql(u8, argv[10], fx_ask_dash);
}

pub fn gitCommitNumstatLabel(model: *const Model) []const u8 {
    return model.git_commit_numstat_label_storage[0..model.git_commit_numstat_label_len];
}

pub fn hasGitCommitNumstat(model: *const Model) bool {
    return model.git_commit_numstat_additions > 0 or model.git_commit_numstat_deletions > 0;
}

pub fn hasGitCommitGenerate(model: *const Model) bool {
    return model.git_commit_generate_key != 0;
}

fn setCommitNumstat(model: *Model, additions: u64, deletions: u64) void {
    model.git_commit_numstat_additions = additions;
    model.git_commit_numstat_deletions = deletions;
    if (additions == 0 and deletions == 0) {
        model.git_commit_numstat_label_len = 0;
        return;
    }
    const written = git_numstat.numstatLabel(additions, deletions, &model.git_commit_numstat_label_storage);
    model.git_commit_numstat_label_len = written.len;
}

fn addCommitNumstat(model: *Model, delta: git_numstat.NumstatDelta) void {
    if (delta.additions == 0 and delta.deletions == 0) return;
    setCommitNumstat(
        model,
        model.git_commit_numstat_additions +| delta.additions,
        model.git_commit_numstat_deletions +| delta.deletions,
    );
}

fn clearCommitNumstat(model: *Model) void {
    setCommitNumstat(model, 0, 0);
}

fn cancelCommitNumstat(model: *Model, fx: *Effects) void {
    if (model.git_commit_numstat_key == 0) return;
    fx.cancel(model.git_commit_numstat_key);
    model.git_commit_numstat_key = 0;
}

fn commitNumstatStillCurrent(model: *const Model) bool {
    if (model.git_commit_numstat_key == 0) return false;
    if (!model.git_commit_active) return false;
    if (model.git_commit_numstat_probe_session != model.selected) return false;
    const path = model.selectedProjectPath();
    const probed = model.git_commit_numstat_probe_path_storage[0..model.git_commit_numstat_probe_path_len];
    return std.mem.eql(u8, path, probed);
}

/// Cancel any in-flight snapshot probe, drop the label, and spawn
/// again for the current include-unstaged mode when the Commit… card
/// is open and cwd exists. Empty / missing / Windows skips the spawn
/// so the label stays omitted.
pub fn refreshCommitNumstat(model: *Model, fx: *Effects) void {
    cancelCommitNumstat(model, fx);
    clearCommitNumstat(model);
    if (!probeSupported()) return;
    if (!model.git_commit_active) return;
    const cwd = probePath(model);
    if (cwd.len == 0) return;

    const key = model.next_git_commit_numstat_key;
    model.next_git_commit_numstat_key = key + 1;
    model.git_commit_numstat_key = key;
    model.git_commit_numstat_probe_session = model.selected;
    writeFixed(&model.git_commit_numstat_probe_path_storage, &model.git_commit_numstat_probe_path_len, cwd);

    var argv_buf: [commit_numstat_argv_len][]const u8 = undefined;
    fx.spawn(.{
        .key = key,
        .argv = commitNumstatArgvFor(cwd, model.git_commit_include_unstaged, &argv_buf),
        .on_line = Effects.lineMsg(.fx_line),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
}

/// Drop an in-flight snapshot probe and clear the label. Safe when
/// no probe is live.
pub fn dropCommitNumstat(model: *Model, fx: *Effects) void {
    cancelCommitNumstat(model, fx);
    clearCommitNumstat(model);
}

pub fn applyNumstatLine(model: *Model, line: native_sdk.EffectLine) void {
    if (line.key != model.git_commit_numstat_key or model.git_commit_numstat_key == 0) return;
    if (!commitNumstatStillCurrent(model)) return;
    addCommitNumstat(model, git_numstat.sumNumstat(line.line));
}

pub fn handleNumstatExit(model: *Model, exit: native_sdk.EffectExit) void {
    if (exit.key != model.git_commit_numstat_key or model.git_commit_numstat_key == 0) return;
    const current = commitNumstatStillCurrent(model);
    model.git_commit_numstat_key = 0;
    if (!current or exit.reason != .exited or exit.code != 0) {
        clearCommitNumstat(model);
    }
}

pub fn closeCommit(model: *Model) void {
    model.git_commit_active = false;
    model.git_commit_buffer.clear();
    model.git_commit_numstat_key = 0;
    model.git_commit_generate_key = 0;
    model.git_commit_generate_stdout_len = 0;
    clearCommitNumstat(model);
}

fn cancelCommit(model: *Model, fx: *Effects) void {
    if (model.git_commit_key == 0) return;
    fx.cancel(model.git_commit_key);
    model.git_commit_key = 0;
    resetCommitState(model);
}

fn cancelGenerate(model: *Model, fx: *Effects) void {
    if (model.git_commit_generate_key == 0) return;
    fx.cancel(model.git_commit_generate_key);
    model.git_commit_generate_key = 0;
    model.git_commit_generate_stdout_len = 0;
    model.git_commit_then_push = false;
}

/// Drop an in-flight generate/add/preflight/commit (session /
/// project refresh) so a late exit cannot paint a later card.
/// Also drops the CommitSnapshot numstat probe. Sets
/// `Could not commit.`
pub fn cancelInFlight(model: *Model, fx: *Effects) void {
    dropCommitNumstat(model, fx);
    const in_flight = model.git_commit_key != 0 or model.git_commit_generate_key != 0;
    cancelGenerate(model, fx);
    if (model.git_commit_key == 0) {
        if (in_flight) model.setAttachStatus(commit_failed_status);
        return;
    }
    cancelCommit(model, fx);
    model.setAttachStatus(commit_failed_status);
}

/// Esc / Cancel: close the card and drop an in-flight generate /
/// add/preflight/commit and snapshot probe so a late exit cannot
/// spawn the next phase or paint the +/- label. Sets
/// `Could not commit.` when a spawn was live.
pub fn dismissCommit(model: *Model, fx: *Effects) void {
    const in_flight = model.git_commit_key != 0 or model.git_commit_generate_key != 0;
    cancelGenerate(model, fx);
    cancelCommit(model, fx);
    dropCommitNumstat(model, fx);
    closeCommit(model);
    model.git_commit_then_push = false;
    if (in_flight) model.setAttachStatus(commit_failed_status);
}

/// Dismiss the select list and other git cards, then open the
/// runtime-only Commit… card and one-shot CommitSnapshot numstat
/// for the default include-unstaged mode. Draft message is not
/// persisted. No-op when gated, a git mutation is in flight, the
/// session is streaming, or cwd is missing.
pub fn startCommit(model: *Model, fx: *Effects) void {
    git_checkout.closePicker(model);
    git_checkout.closeCreate(model);
    git_checkout.closeWorktreeCreate(model);
    git_checkout.closeDelete(model);
    dropCommitNumstat(model, fx);
    closeCommit(model);
    model.closeProjectEdit();
    if (!canCommitGit(model)) return;
    if (git_checkout.gitMutationInFlight(model)) return;
    if (model.is_streaming()) return;
    if (!probeSupported()) return;
    if (probePath(model).len == 0) return;
    model.git_commit_include_unstaged = true;
    model.git_commit_active = true;
    refreshCommitNumstat(model, fx);
}

/// Runtime-only Commit… toggle. Not persisted. Cancels an in-flight
/// snapshot probe and re-probes for the new include-unstaged mode.
pub fn toggleIncludeUnstaged(model: *Model, fx: *Effects) void {
    model.git_commit_include_unstaged = !model.git_commit_include_unstaged;
    if (!model.git_commit_active) return;
    refreshCommitNumstat(model, fx);
}

fn spawnCommitCmd(model: *Model, fx: *Effects, cwd: []const u8, argv: []const []const u8, phase: GitCommitPhase) void {
    const key = model.next_git_commit_key;
    model.next_git_commit_key = key + 1;
    model.git_commit_key = key;
    model.git_commit_phase = phase;
    model.git_commit_probe_session = model.selected;
    const probed = model.git_commit_probe_path_storage[0..model.git_commit_probe_path_len];
    if (cwd.ptr != probed.ptr) {
        writeFixed(&model.git_commit_probe_path_storage, &model.git_commit_probe_path_len, cwd);
    }
    fx.spawn(.{
        .key = key,
        .argv = argv,
        .on_line = Effects.lineMsg(.fx_line),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
}

fn spawnAdd(model: *Model, fx: *Effects) void {
    const cwd = commitCwd(model);
    if (cwd.len == 0) {
        failCommit(model);
        return;
    }
    var argv_buf: [add_argv_len][]const u8 = undefined;
    spawnCommitCmd(model, fx, cwd, addArgvFor(cwd, &argv_buf), .add);
}

fn spawnCommit(model: *Model, fx: *Effects) void {
    const cwd = commitCwd(model);
    const message = model.git_commit_message_storage[0..model.git_commit_message_len];
    if (cwd.len == 0 or message.len == 0) {
        failCommit(model);
        return;
    }
    var argv_buf: [commit_argv_len][]const u8 = undefined;
    spawnCommitCmd(model, fx, cwd, commitArgvFor(cwd, message, &argv_buf), .commit);
}

fn spawnCachedQuiet(model: *Model, fx: *Effects) void {
    const cwd = commitCwd(model);
    if (cwd.len == 0) {
        failCommit(model);
        return;
    }
    var argv_buf: [cached_quiet_argv_len][]const u8 = undefined;
    spawnCommitCmd(model, fx, cwd, cachedQuietArgvFor(cwd, &argv_buf), .cached_quiet);
}

fn failNothingStaged(model: *Model) void {
    model.git_commit_key = 0;
    resetCommitState(model);
    model.setAttachStatus(nothing_staged_status);
}

fn generateAvailable(model: *const Model) bool {
    return model.fx_available and model.fxPath().len > 0;
}

fn generateStillCurrent(model: *const Model) bool {
    if (model.git_commit_generate_key == 0) return false;
    if (!model.git_commit_active) return false;
    if (model.git_commit_probe_session != model.selected) return false;
    const path = model.selectedProjectPath();
    const probed = model.git_commit_probe_path_storage[0..model.git_commit_probe_path_len];
    return std.mem.eql(u8, path, probed);
}

fn appendGenerateStdout(model: *Model, chunk: []const u8) void {
    const dest = model.git_commit_generate_stdout_storage[0..];
    const used = model.git_commit_generate_stdout_len;
    if (used >= dest.len) return;
    const take = @min(dest.len - used, chunk.len);
    @memcpy(dest[used .. used + take], chunk[0..take]);
    model.git_commit_generate_stdout_len = used + take;
}

fn failGenerate(model: *Model) void {
    model.git_commit_generate_key = 0;
    model.git_commit_generate_stdout_len = 0;
    model.git_commit_then_push = false;
    model.setAttachStatus(generate_failed_status);
}

fn spawnAddOrCommit(model: *Model, fx: *Effects) void {
    if (model.git_commit_include_unstaged) {
        spawnAdd(model, fx);
    } else {
        spawnCachedQuiet(model, fx);
    }
}

fn spawnGenerate(model: *Model, fx: *Effects) void {
    const cwd = commitCwd(model);
    const fx_path = model.fxPath();
    if (cwd.len == 0 or fx_path.len == 0) {
        failGenerate(model);
        return;
    }
    model.git_commit_generate_stdout_len = 0;
    const key = model.next_git_commit_generate_key;
    model.next_git_commit_generate_key = key + 1;
    model.git_commit_generate_key = key;
    model.git_commit_probe_session = model.selected;
    const probed = model.git_commit_probe_path_storage[0..model.git_commit_probe_path_len];
    if (cwd.ptr != probed.ptr) {
        writeFixed(&model.git_commit_probe_path_storage, &model.git_commit_probe_path_len, cwd);
    }
    var argv_buf: [generate_argv_len][]const u8 = undefined;
    fx.spawn(.{
        .key = key,
        .argv = generateArgvFor(cwd, fx_path, model.git_commit_include_unstaged, &argv_buf),
        .on_line = Effects.lineMsg(.fx_line),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
}

fn confirmCommitWith(model: *Model, fx: *Effects, then_push: bool) void {
    if (!canCommitGit(model)) return;
    if (git_checkout.gitMutationInFlight(model)) return;
    if (model.is_streaming()) return;
    if (!probeSupported()) return;
    const cwd = probePath(model);
    if (cwd.len == 0) return;

    var msg_buf: [max_commit_message]u8 = undefined;
    const message = normalizeMessage(model.git_commit_buffer.text(), &msg_buf) orelse {
        if (!generateAvailable(model)) {
            model.git_commit_then_push = false;
            model.setAttachStatus(empty_message_status);
            return;
        }
        writeFixed(&model.git_commit_probe_path_storage, &model.git_commit_probe_path_len, cwd);
        model.git_commit_then_push = then_push;
        model.clearAttachStatus();
        spawnGenerate(model, fx);
        return;
    };
    writeFixed(&model.git_commit_message_storage, &model.git_commit_message_len, message);
    writeFixed(&model.git_commit_probe_path_storage, &model.git_commit_probe_path_len, cwd);
    model.git_commit_then_push = then_push;
    spawnAddOrCommit(model, fx);
}

/// Confirm the Commit… card: a non-empty normalized message one-shots
/// `git add -A -- .` then `git diff --cached --quiet --` then
/// `git commit -m` when include-unstaged is on; otherwise the same
/// preflight then `git commit -m` only. Empty / whitespace one-shots
/// `fx ask` generate when fx is available, then auto-proceeds; if fx
/// is not available it sets `Enter a commit message.` and does not
/// spawn. Confirm while generate is in flight is a no-op. Gated /
/// busy / in-flight / missing cwd is a no-op. Commit-only: does not
/// start a push after success.
pub fn confirmCommit(model: *Model, fx: *Effects) void {
    confirmCommitWith(model, fx, false);
}

/// Same commit path as `confirmCommit`, gated by
/// `canCommitAndPushGit` (first-push remotes). On successful commit,
/// close the card and start the existing Push… path without
/// re-checking `canPushGitBranch`. Empty message generates then
/// commits when fx is available; it does not wait for a second
/// Confirm. No-op when the remotes gate fails.
pub fn confirmCommitAndPush(model: *Model, fx: *Effects) void {
    if (!canCommitAndPushGit(model)) return;
    confirmCommitWith(model, fx, true);
}

/// Push-only on the Commit… card (Waku `CommitAction::Push`). Does
/// not commit, does not require a message, does not generate.
/// Gated by `canPushGitBranch` (same as composer Push…). In-flight
/// generate or add/preflight/commit is a no-op (Waku
/// `commit_operation` is Some). Check those gates before
/// dismissing so a failed gate cannot close the card without
/// pushing. On start, dismiss the
/// card the same way Cancel does, then the existing gated
/// `startPush` path — not `beginPushAfterCommit` (ungated; that is
/// for post-commit when ahead is stale). First cut: close then
/// Push… — no in-dialog pending spinner.
pub fn confirmPushOnly(model: *Model, fx: *Effects) void {
    if (!git_ahead_behind.canPushGitBranch(model)) return;
    if (model.git_commit_generate_key != 0) return;
    if (model.git_commit_key != 0 or model.git_commit_phase != .idle) return;
    if (git_checkout.gitMutationInFlight(model)) return;
    if (model.is_streaming()) return;
    if (!probeSupported()) return;
    if (probePath(model).len == 0) return;

    dismissCommit(model, fx);
    git_checkout.startPush(model, fx);
}

/// JSON `.output` first line, else the first non-empty trimmed stdout
/// line, then `normalizeMessage` (single line, max 200). A parsed
/// object with an `output` field does not fall back to the raw JSON
/// when that field is empty.
pub fn takeGeneratedSubject(raw: []const u8, out: *[max_commit_message]u8) ?[]const u8 {
    const trimmed = std.mem.trim(u8, raw, " \t\r\n");
    if (trimmed.len == 0) return null;
    if (trimmed[0] == '{') {
        var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena_state.deinit();
        if (std.json.parseFromSliceLeaky(std.json.Value, arena_state.allocator(), trimmed, .{})) |root| {
            switch (root) {
                .object => |obj| {
                    if (obj.get("output")) |raw_out| {
                        switch (raw_out) {
                            .string => |s| return normalizeMessage(s, out),
                            else => {},
                        }
                    }
                },
                else => {},
            }
        } else |_| {}
    }
    return normalizeMessage(trimmed, out);
}

pub fn applyGenerateLine(model: *Model, line: native_sdk.EffectLine) void {
    if (line.key != model.git_commit_generate_key or model.git_commit_generate_key == 0) return;
    if (!generateStillCurrent(model)) return;
    appendGenerateStdout(model, line.line);
}

pub fn handleGenerateExit(model: *Model, fx: *Effects, exit: native_sdk.EffectExit) void {
    if (exit.key != model.git_commit_generate_key or model.git_commit_generate_key == 0) return;
    const current = generateStillCurrent(model);
    const stdout = model.git_commit_generate_stdout_storage[0..model.git_commit_generate_stdout_len];
    model.git_commit_generate_key = 0;
    model.git_commit_generate_stdout_len = 0;
    if (!current) {
        model.git_commit_then_push = false;
        return;
    }
    if (exit.reason != .exited or exit.code != 0) {
        failGenerate(model);
        return;
    }
    var msg_buf: [max_commit_message]u8 = undefined;
    const message = takeGeneratedSubject(stdout, &msg_buf) orelse {
        failGenerate(model);
        return;
    };
    model.git_commit_buffer.clear();
    model.git_commit_buffer.apply(.{ .insert_text = message });
    writeFixed(&model.git_commit_message_storage, &model.git_commit_message_len, message);
    spawnAddOrCommit(model, fx);
}

pub fn applyLine(model: *Model, line: native_sdk.EffectLine) void {
    if (line.key != model.git_commit_key or model.git_commit_key == 0) return;
    _ = commitStillCurrent(model);
}

pub fn handleCommitExit(model: *Model, fx: *Effects, exit: native_sdk.EffectExit) void {
    if (exit.key != model.git_commit_key or model.git_commit_key == 0) return;
    const current = commitStillCurrent(model);
    const phase = model.git_commit_phase;
    model.git_commit_key = 0;
    if (!current) {
        resetCommitState(model);
        model.setAttachStatus(commit_failed_status);
        return;
    }
    switch (phase) {
        .idle => resetCommitState(model),
        .add => {
            if (exit.reason == .exited and exit.code == 0) {
                spawnCachedQuiet(model, fx);
                return;
            }
            failCommit(model);
        },
        .cached_quiet => {
            if (exit.reason == .exited and exit.code == 1) {
                spawnCommit(model, fx);
                return;
            }
            if (exit.reason == .exited and exit.code == 0) {
                failNothingStaged(model);
                return;
            }
            failCommit(model);
        },
        .commit => {
            const then_push = model.git_commit_then_push;
            resetCommitState(model);
            if (exit.reason == .exited and exit.code == 0) {
                dropCommitNumstat(model, fx);
                closeCommit(model);
                if (then_push) {
                    git_checkout.beginPushAfterCommit(model, fx);
                    if (model.git_push_key == 0) {
                        if (!model.has_attach_status()) {
                            model.setAttachStatus(git_checkout.push_failed_status);
                        }
                        git_checkout.refreshWorkspaceProbes(model, fx);
                    }
                    return;
                }
                git_checkout.refreshWorkspaceProbes(model, fx);
                return;
            }
            if (!model.git_commit_include_unstaged) {
                model.setAttachStatus(nothing_staged_status);
            } else {
                model.setAttachStatus(commit_failed_status);
            }
        },
    }
}

test "add argv is chdir script plus git add -A -- ." {
    var buf: [add_argv_len][]const u8 = undefined;
    const argv = addArgvFor("/tmp/faku-commit", &buf);
    try std.testing.expectEqual(@as(usize, 10), argv.len);
    try std.testing.expectEqualStrings(sh_bin, argv[0]);
    try std.testing.expectEqualStrings("-c", argv[1]);
    try std.testing.expectEqualStrings(main.fx_ask_chdir_script, argv[2]);
    try std.testing.expectEqualStrings("sh", argv[3]);
    try std.testing.expectEqualStrings("/tmp/faku-commit", argv[4]);
    try std.testing.expectEqualStrings(git_bin, argv[5]);
    try std.testing.expectEqualStrings(git_add_cmd, argv[6]);
    try std.testing.expectEqualStrings(git_add_all_flag, argv[7]);
    try std.testing.expectEqualStrings(git_pathspec_dash, argv[8]);
    try std.testing.expectEqualStrings(git_pathspec_dot, argv[9]);
    try std.testing.expect(isGitCommitAddArgv(argv));
    try std.testing.expect(!isGitCommitArgv(argv));
    try std.testing.expect(!isGitCommitCachedQuietArgv(argv));
    try std.testing.expect(!git_checkout.isGitPushArgv(argv));
    try std.testing.expect(!git_checkout.isGitFetchArgv(argv));
    try std.testing.expect(std.mem.indexOf(u8, argv[2], git_add_cmd) == null);
    try std.testing.expect(std.mem.indexOf(u8, argv[2], git_add_all_flag) == null);
    try std.testing.expect(std.mem.indexOf(u8, argv[2], git_pathspec_dot) == null);
    try std.testing.expect(git_commit_key_first >= 450);
    try std.testing.expect(git_commit_key_first > file_mention.file_mention_key_first);
    try std.testing.expect(git_commit_key_first > file_mention.file_mention_key_first + 9);
    try std.testing.expect(git_commit_numstat_key_first >= 460);
    try std.testing.expect(git_commit_numstat_key_first > git_commit_key_first);
    try std.testing.expect(git_commit_numstat_key_first > git_numstat.git_numstat_key_first);
    try std.testing.expect(git_commit_generate_key_first >= 470);
    try std.testing.expect(git_commit_generate_key_first > git_commit_numstat_key_first);
    try std.testing.expect(git_remotes.git_remotes_key_first > git_commit_generate_key_first);
}

test "commit argv is chdir script plus git commit -m and its own message slot" {
    var buf: [commit_argv_len][]const u8 = undefined;
    const argv = commitArgvFor("/tmp/faku-commit", "fix dirty count", &buf);
    try std.testing.expectEqual(@as(usize, 9), argv.len);
    try std.testing.expectEqualStrings(sh_bin, argv[0]);
    try std.testing.expectEqualStrings("-c", argv[1]);
    try std.testing.expectEqualStrings(main.fx_ask_chdir_script, argv[2]);
    try std.testing.expectEqualStrings("sh", argv[3]);
    try std.testing.expectEqualStrings("/tmp/faku-commit", argv[4]);
    try std.testing.expectEqualStrings(git_bin, argv[5]);
    try std.testing.expectEqualStrings(git_commit_cmd, argv[6]);
    try std.testing.expectEqualStrings(git_message_flag, argv[7]);
    try std.testing.expectEqualStrings("fix dirty count", argv[8]);
    try std.testing.expect(isGitCommitArgv(argv));
    try std.testing.expect(!isGitCommitAddArgv(argv));
    try std.testing.expect(!isGitCommitCachedQuietArgv(argv));
    try std.testing.expect(!git_checkout.isGitPushArgv(argv));
    try std.testing.expect(!git_checkout.isGitFetchArgv(argv));
    try std.testing.expect(std.mem.indexOf(u8, argv[2], git_commit_cmd) == null);
    try std.testing.expect(std.mem.indexOf(u8, argv[2], git_message_flag) == null);
    try std.testing.expect(std.mem.indexOf(u8, argv[2], "fix dirty count") == null);

    var push_buf: [7][]const u8 = undefined;
    const push = git_checkout.pushArgvFor("/tmp/faku-commit", &push_buf);
    try std.testing.expect(!isGitCommitArgv(push));
    try std.testing.expect(!isGitCommitAddArgv(push));
    var fetch_buf: [8][]const u8 = undefined;
    const fetch = git_checkout.fetchArgvFor("/tmp/faku-commit", &fetch_buf);
    try std.testing.expect(!isGitCommitArgv(fetch));
    try std.testing.expect(!isGitCommitAddArgv(fetch));
    try std.testing.expect(!isGitCommitCachedQuietArgv(fetch));
}

test "cached-quiet argv is chdir script plus git diff --cached --quiet --" {
    var buf: [cached_quiet_argv_len][]const u8 = undefined;
    const argv = cachedQuietArgvFor("/tmp/faku-commit", &buf);
    try std.testing.expectEqual(@as(usize, 10), argv.len);
    try std.testing.expectEqualStrings(sh_bin, argv[0]);
    try std.testing.expectEqualStrings("-c", argv[1]);
    try std.testing.expectEqualStrings(main.fx_ask_chdir_script, argv[2]);
    try std.testing.expectEqualStrings("sh", argv[3]);
    try std.testing.expectEqualStrings("/tmp/faku-commit", argv[4]);
    try std.testing.expectEqualStrings(git_bin, argv[5]);
    try std.testing.expectEqualStrings(git_diff_cmd, argv[6]);
    try std.testing.expectEqualStrings(git_cached_flag, argv[7]);
    try std.testing.expectEqualStrings(git_quiet_flag, argv[8]);
    try std.testing.expectEqualStrings(git_pathspec_dash, argv[9]);
    try std.testing.expect(isGitCommitCachedQuietArgv(argv));
    try std.testing.expect(!isGitCommitAddArgv(argv));
    try std.testing.expect(!isGitCommitArgv(argv));
    try std.testing.expect(!isGitCommitNumstatArgv(argv));
    try std.testing.expect(!isGitCommitNumstatCachedArgv(argv));
    try std.testing.expect(!isGitCommitNumstatWorkingTreeArgv(argv));
    try std.testing.expect(!git_numstat.isGitNumstatArgv(argv));
    try std.testing.expect(!git_checkout.isGitPushArgv(argv));
    try std.testing.expect(std.mem.indexOf(u8, argv[2], git_diff_cmd) == null);
    try std.testing.expect(std.mem.indexOf(u8, argv[2], git_cached_flag) == null);
    try std.testing.expect(std.mem.indexOf(u8, argv[2], git_quiet_flag) == null);

    var numstat_buf: [commit_numstat_argv_len][]const u8 = undefined;
    const cached_numstat = commitNumstatCachedArgvFor("/tmp/faku-commit", &numstat_buf);
    try std.testing.expect(isGitCommitNumstatCachedArgv(cached_numstat));
    try std.testing.expect(!isGitCommitCachedQuietArgv(cached_numstat));
}

test "empty or whitespace message does not spawn" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/git-commit-empty", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("commit empty", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);
    markDirtyUnstaged(&model, 2);
    try std.testing.expect(canCommitGit(&model));

    startCommit(&model, &fx);
    try std.testing.expect(model.git_commit_active);
    try std.testing.expect(model.git_commit_numstat_key != 0);
    try std.testing.expect(findPendingArgv(&fx, &isGitCommitNumstatArgv) != null);
    confirmCommit(&model, &fx);
    try std.testing.expectEqual(@as(u64, 0), model.git_commit_key);
    try std.testing.expectEqual(@as(u64, 0), model.git_commit_generate_key);
    try std.testing.expect(findPendingArgv(&fx, &isGitCommitAddArgv) == null);
    try std.testing.expect(findPendingArgv(&fx, &isGitCommitArgv) == null);
    try std.testing.expect(findPendingArgv(&fx, &isGitCommitCachedQuietArgv) == null);
    try std.testing.expect(findPendingArgv(&fx, &isGitCommitGenerateArgv) == null);
    try std.testing.expectEqualStrings(empty_message_status, model.attach_status());

    model.git_commit_buffer.apply(.{ .insert_text = "   \n\t  " });
    model.clearAttachStatus();
    confirmCommit(&model, &fx);
    try std.testing.expectEqual(@as(u64, 0), model.git_commit_key);
    try std.testing.expectEqual(@as(u64, 0), model.git_commit_generate_key);
    try std.testing.expect(findPendingArgv(&fx, &isGitCommitAddArgv) == null);
    try std.testing.expect(findPendingArgv(&fx, &isGitCommitArgv) == null);
    try std.testing.expect(findPendingArgv(&fx, &isGitCommitCachedQuietArgv) == null);
    try std.testing.expect(findPendingArgv(&fx, &isGitCommitGenerateArgv) == null);
    try std.testing.expectEqualStrings(empty_message_status, model.attach_status());
}

test "canCommitGit follows staged / include_unstaged / unstaged" {
    var model = Model{};
    try std.testing.expect(model.git_commit_include_unstaged);
    try std.testing.expect(!canCommitGit(&model));
    try std.testing.expect(!model.can_commit_git());

    model.git_has_unstaged = true;
    try std.testing.expect(canCommitGit(&model));
    try std.testing.expect(model.can_commit_git());

    model.git_commit_include_unstaged = false;
    try std.testing.expect(!canCommitGit(&model));
    try std.testing.expect(!model.can_commit_git());

    model.git_has_staged = true;
    try std.testing.expect(canCommitGit(&model));
    try std.testing.expect(model.can_commit_git());

    model.git_has_unstaged = false;
    try std.testing.expect(canCommitGit(&model));
    model.git_commit_include_unstaged = true;
    try std.testing.expect(canCommitGit(&model));

    model.git_dirty_key = git_dirty.git_dirty_key_first;
    try std.testing.expect(!canCommitGit(&model));
    try std.testing.expect(!model.can_commit_git());

    model.git_dirty_key = 0;
    model.git_has_staged = false;
    model.git_has_unstaged = false;
    try std.testing.expect(!canCommitGit(&model));
}

test "canCommitAndPushGit requires remotes on no-upstream and allows known upstream" {
    var model = Model{};
    try std.testing.expect(!canCommitAndPushGit(&model));
    try std.testing.expect(!model.can_commit_and_push_git());

    markDirtyUnstaged(&model, 1);
    try std.testing.expect(canCommitGit(&model));
    try std.testing.expect(!canCommitAndPushGit(&model));

    markFirstPushRemotesOk(&model);
    try std.testing.expect(canCommitAndPushGit(&model));
    try std.testing.expect(model.can_commit_and_push_git());

    model.git_has_remote = false;
    try std.testing.expect(!canCommitAndPushGit(&model));

    model.git_remotes_key = git_remotes.git_remotes_key_first;
    model.git_has_remote = true;
    try std.testing.expect(!canCommitAndPushGit(&model));

    model.git_remotes_key = 0;
    model.git_remotes_ready = false;
    try std.testing.expect(!canCommitAndPushGit(&model));

    markStaleCanPush(&model);
    model.git_remotes_ready = false;
    model.git_has_remote = false;
    try std.testing.expect(canCommitAndPushGit(&model));

    model.git_dirty_key = git_dirty.git_dirty_key_first;
    try std.testing.expect(!canCommitAndPushGit(&model));
}

test "confirmCommitAndPush no-ops when remotes gate fails" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/git-commit-and-push-noremote", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("commit and push no remote", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);
    markDirtyUnstaged(&model, 1);
    model.git_ahead_behind_key = 0;
    model.git_ahead_behind_ready = true;
    model.git_ahead_behind_has_upstream = false;
    model.git_remotes_key = 0;
    model.git_remotes_ready = true;
    model.git_has_remote = false;
    try std.testing.expect(!canCommitAndPushGit(&model));
    try std.testing.expect(!model.can_commit_and_push_git());

    startCommit(&model, &fx);
    model.git_commit_buffer.apply(.{ .insert_text = "should not commit" });
    confirmCommitAndPush(&model, &fx);
    try std.testing.expectEqual(@as(u64, 0), model.git_commit_key);
    try std.testing.expectEqual(@as(u64, 0), model.git_commit_generate_key);
    try std.testing.expectEqual(@as(u64, 0), model.git_push_key);
    try std.testing.expect(!model.git_commit_then_push);
    try std.testing.expect(findPendingArgv(&fx, &isGitCommitAddArgv) == null);
    try std.testing.expect(findPendingArgv(&fx, &isGitCommitArgv) == null);
    try std.testing.expect(model.git_commit_active);

    model.git_remotes_key = git_remotes.git_remotes_key_first;
    model.git_has_remote = true;
    confirmCommitAndPush(&model, &fx);
    try std.testing.expectEqual(@as(u64, 0), model.git_commit_key);
    try std.testing.expect(!model.git_commit_then_push);
}

test "add failure sets Could not commit and does not spawn commit" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/git-commit-add-fail", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("commit add fail", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);
    markDirtyUnstaged(&model, 1);

    startCommit(&model, &fx);
    model.git_commit_buffer.apply(.{ .insert_text = "save work" });
    confirmCommit(&model, &fx);
    try std.testing.expectEqual(git_commit_key_first, model.git_commit_key);
    try std.testing.expectEqual(GitCommitPhase.add, model.git_commit_phase);
    const add = findPending(&fx, model.git_commit_key, &isGitCommitAddArgv) orelse return error.MissingGitAddSpawn;
    try std.testing.expect(!isGitCommitArgv(add.argv));
    try std.testing.expect(add.key >= git_commit_key_first);
    try std.testing.expect(add.key != file_mention.file_mention_key_first);
    try std.testing.expect(add.key != model.git_commit_numstat_key);

    handleCommitExit(&model, &fx, .{ .key = add.key, .reason = .exited, .code = 1 });
    try std.testing.expectEqualStrings(commit_failed_status, model.attach_status());
    try std.testing.expectEqual(@as(u64, 0), model.git_commit_key);
    try std.testing.expectEqual(GitCommitPhase.idle, model.git_commit_phase);
    try std.testing.expect(findPendingArgv(&fx, &isGitCommitArgv) == null);
    try std.testing.expect(findPendingArgv(&fx, &isGitCommitCachedQuietArgv) == null);
    try std.testing.expect(model.git_commit_active);
}

test "commit success refreshes the same workspace probes as other git mutations" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/git-commit-ok", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("commit ok", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);
    markDirtyUnstaged(&model, 4);

    startCommit(&model, &fx);
    try std.testing.expect(model.git_commit_active);
    model.git_commit_buffer.apply(.{ .insert_text = "  wrap the dirty probe  " });
    confirmCommit(&model, &fx);
    const add = findPending(&fx, model.git_commit_key, &isGitCommitAddArgv) orelse return error.MissingGitAddSpawn;
    try std.testing.expect(isGitCommitAddArgv(add.argv));
    handleCommitExit(&model, &fx, .{ .key = add.key, .reason = .exited, .code = 0 });
    try std.testing.expect(!model.has_attach_status());
    try std.testing.expectEqual(GitCommitPhase.cached_quiet, model.git_commit_phase);
    try std.testing.expect(model.git_commit_key != 0);
    try std.testing.expect(model.git_commit_key != add.key);
    try std.testing.expect(findPendingArgv(&fx, &isGitCommitArgv) == null);
    const commit = try advanceCachedQuietToCommit(&model, &fx);
    try std.testing.expectEqualStrings("wrap the dirty probe", commit.argv[8]);
    try std.testing.expect(std.mem.indexOf(u8, commit.argv[2], "wrap the dirty probe") == null);
    try std.testing.expect(commit.key >= git_commit_key_first);
    try std.testing.expect(commit.key > file_mention.file_mention_key_first + 9);

    handleCommitExit(&model, &fx, .{ .key = commit.key, .reason = .exited, .code = 0 });
    try std.testing.expect(!model.git_commit_active);
    try std.testing.expectEqual(@as(u64, 0), model.git_commit_key);
    try std.testing.expectEqual(@as(u64, 0), model.git_push_key);
    try std.testing.expect(!model.git_commit_then_push);
    try std.testing.expect(!model.has_attach_status());
    try std.testing.expect(model.git_branch_key != 0);
    try std.testing.expect(model.git_dirty_key != 0);
    try std.testing.expect(model.git_numstat_key != 0);
    try std.testing.expect(model.git_ahead_behind_key != 0);
    try std.testing.expect(model.git_remotes_key != 0);
    try std.testing.expect(model.file_mention_key != 0);
    try std.testing.expect(model.git_branch_list_key != 0);
}

test "normalizeMessage trims, takes one line, and caps at 200 chars" {
    var buf: [max_commit_message]u8 = undefined;
    try std.testing.expect(normalizeMessage("   \n", &buf) == null);
    try std.testing.expectEqualStrings("fix probe", normalizeMessage("  fix probe  \n", &buf).?);
    try std.testing.expectEqualStrings("first", normalizeMessage("first\nsecond", &buf).?);
    var long: [240]u8 = undefined;
    @memset(long[0..], 'a');
    const capped = normalizeMessage(long[0..], &buf).?;
    try std.testing.expectEqual(@as(usize, 200), capped.len);
}

test "startCommit and confirm no-op when gated, busy, or cwd is missing" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    const id = model.addSession("commit gate", .fx);
    model.selected = id;
    markDirtyUnstaged(&model, 1);
    startCommit(&model, &fx);
    try std.testing.expect(!model.git_commit_active);
    try std.testing.expectEqual(@as(u64, 0), model.git_commit_key);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/git-commit-gate", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);
    model.store_io = std.testing.io;
    if (model.sessionById(id)) |session| session.setProjectPath(project);

    model.git_dirty_key = git_dirty.git_dirty_key_first;
    startCommit(&model, &fx);
    try std.testing.expect(!model.git_commit_active);
    model.git_dirty_key = 0;

    model.git_push_key = git_checkout.git_push_key_first;
    startCommit(&model, &fx);
    try std.testing.expect(!model.git_commit_active);
    try std.testing.expect(git_checkout.gitMutationInFlight(&model));
    model.git_push_key = 0;

    startCommit(&model, &fx);
    try std.testing.expect(model.git_commit_active);
    try std.testing.expect(model.git_commit_numstat_key != 0);
    model.git_commit_buffer.apply(.{ .insert_text = "ok" });
    model.phase = .streaming;
    confirmCommit(&model, &fx);
    try std.testing.expectEqual(@as(u64, 0), model.git_commit_key);
    try std.testing.expect(findPendingArgv(&fx, &isGitCommitAddArgv) == null);
    try std.testing.expect(findPendingArgv(&fx, &isGitCommitArgv) == null);
    try std.testing.expect(findPendingArgv(&fx, &isGitCommitCachedQuietArgv) == null);
}

fn findPending(fx: *Effects, key: u64, pred: *const fn ([]const []const u8) bool) ?@TypeOf(fx.pendingSpawnAt(0).?) {
    var i: usize = 0;
    while (i < fx.pendingSpawnCount()) : (i += 1) {
        const spawn = fx.pendingSpawnAt(i).?;
        if (spawn.key == key and pred(spawn.argv)) return spawn;
    }
    return null;
}

fn findPendingArgv(fx: *Effects, pred: *const fn ([]const []const u8) bool) ?@TypeOf(fx.pendingSpawnAt(0).?) {
    var i: usize = 0;
    while (i < fx.pendingSpawnCount()) : (i += 1) {
        const spawn = fx.pendingSpawnAt(i).?;
        if (pred(spawn.argv)) return spawn;
    }
    return null;
}

fn advanceCachedQuietToCommit(model: *Model, fx: *Effects) !@TypeOf(fx.pendingSpawnAt(0).?) {
    try std.testing.expectEqual(GitCommitPhase.cached_quiet, model.git_commit_phase);
    const preflight = findPending(fx, model.git_commit_key, &isGitCommitCachedQuietArgv) orelse return error.MissingGitCachedQuietSpawn;
    try std.testing.expect(!isGitCommitArgv(preflight.argv));
    try std.testing.expect(!isGitCommitAddArgv(preflight.argv));
    try std.testing.expect(!isGitCommitNumstatArgv(preflight.argv));
    handleCommitExit(model, fx, .{ .key = preflight.key, .reason = .exited, .code = 1 });
    try std.testing.expectEqual(GitCommitPhase.commit, model.git_commit_phase);
    return findPending(fx, model.git_commit_key, &isGitCommitArgv) orelse return error.MissingGitCommitSpawn;
}

fn markDirtyUnstaged(model: *Model, count: u32) void {
    model.git_dirty_count = count;
    model.git_dirty_key = 0;
    model.git_has_staged = false;
    model.git_has_unstaged = count > 0;
}

fn markDirtyStaged(model: *Model, count: u32) void {
    model.git_dirty_count = count;
    model.git_dirty_key = 0;
    model.git_has_staged = count > 0;
    model.git_has_unstaged = false;
}

fn markStaleCanPush(model: *Model) void {
    model.git_ahead_behind_key = 0;
    model.git_ahead_behind_ready = true;
    model.git_ahead_behind_has_upstream = true;
    model.git_ahead_behind_ahead = 0;
}

fn markFirstPushRemotesOk(model: *Model) void {
    model.git_remotes_key = 0;
    model.git_remotes_ready = true;
    model.git_has_remote = true;
}

test "confirm and push with a message add-then-commit then starts the push probe" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/git-commit-and-push", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("commit and push", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);
    markDirtyUnstaged(&model, 2);
    markStaleCanPush(&model);
    try std.testing.expect(!git_ahead_behind.canPushGitBranch(&model));
    git_checkout.startPush(&model, &fx);
    try std.testing.expectEqual(@as(u64, 0), model.git_push_key);

    startCommit(&model, &fx);
    model.git_commit_buffer.apply(.{ .insert_text = "  ship the dirty probe  " });
    confirmCommitAndPush(&model, &fx);
    try std.testing.expect(model.git_commit_then_push);
    try std.testing.expectEqual(GitCommitPhase.add, model.git_commit_phase);
    const add = findPending(&fx, model.git_commit_key, &isGitCommitAddArgv) orelse return error.MissingGitAddSpawn;
    try std.testing.expect(add.key >= git_commit_key_first);
    try std.testing.expect(!isGitCommitArgv(add.argv));
    try std.testing.expect(!git_checkout.isGitUpstreamArgv(add.argv));

    handleCommitExit(&model, &fx, .{ .key = add.key, .reason = .exited, .code = 0 });
    try std.testing.expect(model.git_commit_then_push);
    try std.testing.expectEqual(GitCommitPhase.cached_quiet, model.git_commit_phase);
    try std.testing.expect(findPendingArgv(&fx, &isGitCommitArgv) == null);
    const commit = try advanceCachedQuietToCommit(&model, &fx);
    try std.testing.expectEqualStrings("ship the dirty probe", commit.argv[8]);
    try std.testing.expect(std.mem.indexOf(u8, commit.argv[2], "ship the dirty probe") == null);
    try std.testing.expect(commit.key != add.key);
    try std.testing.expectEqual(@as(u64, 0), model.git_push_key);

    handleCommitExit(&model, &fx, .{ .key = commit.key, .reason = .exited, .code = 0 });
    try std.testing.expect(!model.git_commit_active);
    try std.testing.expectEqual(@as(u64, 0), model.git_commit_key);
    try std.testing.expect(!model.git_commit_then_push);
    try std.testing.expect(model.git_push_key != 0);
    try std.testing.expectEqual(git_checkout.GitPushPhase.upstream, model.git_push_phase);
    try std.testing.expect(!model.has_attach_status());
    try std.testing.expectEqual(@as(u64, 0), model.git_dirty_key);
    try std.testing.expectEqual(@as(u64, 0), model.git_ahead_behind_key);
    const probe = findPending(&fx, model.git_push_key, &git_checkout.isGitUpstreamArgv) orelse return error.MissingGitUpstreamSpawn;
    try std.testing.expectEqual(model.git_push_key, probe.key);
    try std.testing.expect(probe.key >= git_checkout.git_push_key_first);
    try std.testing.expect(std.mem.indexOf(u8, probe.argv[2], "ship the dirty probe") == null);
    try std.testing.expect(!isGitCommitArgv(probe.argv));
    try std.testing.expect(!isGitCommitAddArgv(probe.argv));
    try std.testing.expect(!isGitCommitCachedQuietArgv(probe.argv));
}

test "confirm and push empty message does not spawn and does not start a push" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/git-commit-and-push-empty", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("commit and push empty", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);
    markDirtyUnstaged(&model, 1);
    markFirstPushRemotesOk(&model);

    startCommit(&model, &fx);
    confirmCommitAndPush(&model, &fx);
    try std.testing.expectEqual(@as(u64, 0), model.git_commit_key);
    try std.testing.expectEqual(@as(u64, 0), model.git_commit_generate_key);
    try std.testing.expectEqual(@as(u64, 0), model.git_push_key);
    try std.testing.expect(!model.git_commit_then_push);
    try std.testing.expect(findPendingArgv(&fx, &isGitCommitAddArgv) == null);
    try std.testing.expect(findPendingArgv(&fx, &isGitCommitArgv) == null);
    try std.testing.expect(findPendingArgv(&fx, &isGitCommitCachedQuietArgv) == null);
    try std.testing.expect(findPendingArgv(&fx, &isGitCommitGenerateArgv) == null);
    try std.testing.expectEqualStrings(empty_message_status, model.attach_status());

    model.git_commit_buffer.apply(.{ .insert_text = "   \n\t  " });
    model.clearAttachStatus();
    confirmCommitAndPush(&model, &fx);
    try std.testing.expectEqual(@as(u64, 0), model.git_commit_key);
    try std.testing.expectEqual(@as(u64, 0), model.git_commit_generate_key);
    try std.testing.expectEqual(@as(u64, 0), model.git_push_key);
    try std.testing.expect(!model.git_commit_then_push);
    try std.testing.expect(findPendingArgv(&fx, &isGitCommitAddArgv) == null);
    try std.testing.expect(findPendingArgv(&fx, &isGitCommitArgv) == null);
    try std.testing.expect(findPendingArgv(&fx, &isGitCommitCachedQuietArgv) == null);
    try std.testing.expect(findPendingArgv(&fx, &isGitCommitGenerateArgv) == null);
    try std.testing.expectEqualStrings(empty_message_status, model.attach_status());
}

test "confirm and push add failure sets Could not commit and does not start a push" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/git-commit-and-push-add-fail", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("commit and push add fail", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);
    markDirtyUnstaged(&model, 1);
    markFirstPushRemotesOk(&model);

    startCommit(&model, &fx);
    model.git_commit_buffer.apply(.{ .insert_text = "save work" });
    confirmCommitAndPush(&model, &fx);
    try std.testing.expect(model.git_commit_then_push);
    const add = findPending(&fx, model.git_commit_key, &isGitCommitAddArgv) orelse return error.MissingGitAddSpawn;
    handleCommitExit(&model, &fx, .{ .key = add.key, .reason = .exited, .code = 1 });
    try std.testing.expectEqualStrings(commit_failed_status, model.attach_status());
    try std.testing.expectEqual(@as(u64, 0), model.git_commit_key);
    try std.testing.expectEqual(@as(u64, 0), model.git_push_key);
    try std.testing.expect(!model.git_commit_then_push);
    try std.testing.expectEqual(GitCommitPhase.idle, model.git_commit_phase);
    try std.testing.expect(findPending(&fx, model.git_commit_key, &isGitCommitArgv) == null);
    try std.testing.expect(findPending(&fx, model.git_push_key, &git_checkout.isGitUpstreamArgv) == null);
    try std.testing.expect(model.git_commit_active);
}

test "confirm and push commit failure sets Could not commit and does not start a push" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/git-commit-and-push-fail", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("commit and push fail", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);
    markDirtyUnstaged(&model, 1);
    markFirstPushRemotesOk(&model);

    startCommit(&model, &fx);
    model.git_commit_buffer.apply(.{ .insert_text = "broken commit" });
    confirmCommitAndPush(&model, &fx);
    const add = findPending(&fx, model.git_commit_key, &isGitCommitAddArgv) orelse return error.MissingGitAddSpawn;
    handleCommitExit(&model, &fx, .{ .key = add.key, .reason = .exited, .code = 0 });
    const commit = try advanceCachedQuietToCommit(&model, &fx);
    handleCommitExit(&model, &fx, .{ .key = commit.key, .reason = .exited, .code = 1 });
    try std.testing.expectEqualStrings(commit_failed_status, model.attach_status());
    try std.testing.expectEqual(@as(u64, 0), model.git_commit_key);
    try std.testing.expectEqual(@as(u64, 0), model.git_push_key);
    try std.testing.expect(!model.git_commit_then_push);
    try std.testing.expect(findPending(&fx, model.git_push_key, &git_checkout.isGitUpstreamArgv) == null);
    try std.testing.expect(model.git_commit_active);
}

test "confirmPushOnly closes the card and starts the existing push probe" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/git-commit-push-only", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("commit push only", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);
    markDirtyUnstaged(&model, 2);

    startCommit(&model, &fx);
    try std.testing.expect(model.git_commit_active);
    model.git_ahead_behind_ready = true;
    markFirstPushRemotesOk(&model);
    try std.testing.expect(git_ahead_behind.canPushGitBranch(&model));
    toggleIncludeUnstaged(&model, &fx);
    try std.testing.expect(!canCommitGit(&model));
    try std.testing.expect(!canCommitAndPushGit(&model));
    try std.testing.expect(git_ahead_behind.canPushGitBranch(&model));

    confirmPushOnly(&model, &fx);
    try std.testing.expect(!model.git_commit_active);
    try std.testing.expectEqual(@as(u64, 0), model.git_commit_key);
    try std.testing.expectEqual(@as(u64, 0), model.git_commit_generate_key);
    try std.testing.expect(!model.git_commit_then_push);
    try std.testing.expect(findPendingArgv(&fx, &isGitCommitAddArgv) == null);
    try std.testing.expect(findPendingArgv(&fx, &isGitCommitArgv) == null);
    try std.testing.expect(findPendingArgv(&fx, &isGitCommitCachedQuietArgv) == null);
    try std.testing.expect(findPendingArgv(&fx, &isGitCommitGenerateArgv) == null);
    try std.testing.expectEqual(GitCommitPhase.idle, model.git_commit_phase);
    try std.testing.expect(model.git_push_key != 0);
    try std.testing.expectEqual(git_checkout.GitPushPhase.upstream, model.git_push_phase);
    const probe = findPending(&fx, model.git_push_key, &git_checkout.isGitUpstreamArgv) orelse return error.MissingGitUpstreamSpawn;
    try std.testing.expectEqual(model.git_push_key, probe.key);
    try std.testing.expect(probe.key >= git_checkout.git_push_key_first);
    try std.testing.expect(!isGitCommitArgv(probe.argv));
    try std.testing.expect(!isGitCommitAddArgv(probe.argv));
    try std.testing.expect(!isGitCommitCachedQuietArgv(probe.argv));
}

test "confirmPushOnly empty message still starts a push" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/git-commit-push-only-empty", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("commit push only empty", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);
    markDirtyUnstaged(&model, 1);

    startCommit(&model, &fx);
    model.git_ahead_behind_ready = true;
    markFirstPushRemotesOk(&model);
    try std.testing.expectEqualStrings("", model.git_commit_buffer.text());
    confirmPushOnly(&model, &fx);
    try std.testing.expect(!model.git_commit_active);
    try std.testing.expectEqual(@as(u64, 0), model.git_commit_key);
    try std.testing.expectEqual(@as(u64, 0), model.git_commit_generate_key);
    try std.testing.expect(!model.git_commit_then_push);
    try std.testing.expect(findPendingArgv(&fx, &isGitCommitAddArgv) == null);
    try std.testing.expect(findPendingArgv(&fx, &isGitCommitArgv) == null);
    try std.testing.expect(findPendingArgv(&fx, &isGitCommitCachedQuietArgv) == null);
    try std.testing.expect(findPendingArgv(&fx, &isGitCommitGenerateArgv) == null);
    try std.testing.expectEqual(GitCommitPhase.idle, model.git_commit_phase);
    try std.testing.expect(model.git_push_key != 0);
    try std.testing.expectEqual(git_checkout.GitPushPhase.upstream, model.git_push_phase);
    try std.testing.expect(findPending(&fx, model.git_push_key, &git_checkout.isGitUpstreamArgv) != null);
    try std.testing.expect(!model.has_attach_status());

    model.git_push_key = 0;
    model.git_push_phase = .idle;
    startCommit(&model, &fx);
    model.git_ahead_behind_ready = true;
    markFirstPushRemotesOk(&model);
    model.git_commit_buffer.apply(.{ .insert_text = "   \n\t  " });
    confirmPushOnly(&model, &fx);
    try std.testing.expect(!model.git_commit_active);
    try std.testing.expectEqual(@as(u64, 0), model.git_commit_key);
    try std.testing.expectEqual(@as(u64, 0), model.git_commit_generate_key);
    try std.testing.expect(findPendingArgv(&fx, &isGitCommitGenerateArgv) == null);
    try std.testing.expect(model.git_push_key != 0);
    try std.testing.expectEqual(git_checkout.GitPushPhase.upstream, model.git_push_phase);
}

test "confirmPushOnly no-ops when canPushGitBranch is false" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/git-commit-push-only-stale", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("commit push only stale", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);
    markDirtyUnstaged(&model, 1);
    markStaleCanPush(&model);
    try std.testing.expect(!git_ahead_behind.canPushGitBranch(&model));
    try std.testing.expect(canCommitAndPushGit(&model));

    startCommit(&model, &fx);
    model.git_commit_buffer.apply(.{ .insert_text = "should not push only" });
    confirmPushOnly(&model, &fx);
    try std.testing.expect(model.git_commit_active);
    try std.testing.expectEqual(@as(u64, 0), model.git_commit_key);
    try std.testing.expectEqual(@as(u64, 0), model.git_push_key);
    try std.testing.expect(!model.git_commit_then_push);
    try std.testing.expect(findPendingArgv(&fx, &isGitCommitAddArgv) == null);
    try std.testing.expect(findPendingArgv(&fx, &isGitCommitArgv) == null);
    try std.testing.expect(findPendingArgv(&fx, &isGitCommitCachedQuietArgv) == null);
    try std.testing.expect(findPending(&fx, model.git_push_key, &git_checkout.isGitUpstreamArgv) == null);

    confirmCommitAndPush(&model, &fx);
    try std.testing.expect(model.git_commit_then_push);
    try std.testing.expectEqual(GitCommitPhase.add, model.git_commit_phase);
    try std.testing.expect(findPending(&fx, model.git_commit_key, &isGitCommitAddArgv) != null);
    try std.testing.expectEqual(@as(u64, 0), model.git_push_key);
}

test "confirmPushOnly no-ops while generate or add is in flight" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/git-commit-push-only-busy", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    enableFx(&model);
    const id = model.addSession("commit push only busy", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);
    markDirtyUnstaged(&model, 1);

    startCommit(&model, &fx);
    model.git_ahead_behind_ready = true;
    markFirstPushRemotesOk(&model);
    try std.testing.expect(git_ahead_behind.canPushGitBranch(&model));
    confirmCommit(&model, &fx);
    const gen_key = model.git_commit_generate_key;
    try std.testing.expect(gen_key != 0);
    confirmPushOnly(&model, &fx);
    try std.testing.expect(model.git_commit_active);
    try std.testing.expectEqual(gen_key, model.git_commit_generate_key);
    try std.testing.expectEqual(@as(u64, 0), model.git_commit_key);
    try std.testing.expectEqual(@as(u64, 0), model.git_push_key);
    try std.testing.expect(findPendingArgv(&fx, &isGitCommitAddArgv) == null);
    try std.testing.expect(findPending(&fx, model.git_push_key, &git_checkout.isGitUpstreamArgv) == null);

    handleGenerateExit(&model, &fx, .{ .key = gen_key, .reason = .exited, .code = 1 });
    try std.testing.expect(model.git_commit_active);
    model.git_commit_buffer.apply(.{ .insert_text = "typed after generate" });
    confirmCommit(&model, &fx);
    try std.testing.expectEqual(GitCommitPhase.add, model.git_commit_phase);
    const add_key = model.git_commit_key;
    try std.testing.expect(add_key != 0);
    confirmPushOnly(&model, &fx);
    try std.testing.expect(model.git_commit_active);
    try std.testing.expectEqual(add_key, model.git_commit_key);
    try std.testing.expectEqual(GitCommitPhase.add, model.git_commit_phase);
    try std.testing.expectEqual(@as(u64, 0), model.git_push_key);
    try std.testing.expect(findPending(&fx, add_key, &isGitCommitAddArgv) != null);
    try std.testing.expect(findPending(&fx, model.git_push_key, &git_checkout.isGitUpstreamArgv) == null);

    handleCommitExit(&model, &fx, .{ .key = add_key, .reason = .exited, .code = 0 });
    try std.testing.expectEqual(GitCommitPhase.cached_quiet, model.git_commit_phase);
    const preflight_key = model.git_commit_key;
    try std.testing.expect(preflight_key != 0);
    try std.testing.expect(findPending(&fx, preflight_key, &isGitCommitCachedQuietArgv) != null);
    confirmPushOnly(&model, &fx);
    try std.testing.expect(model.git_commit_active);
    try std.testing.expectEqual(preflight_key, model.git_commit_key);
    try std.testing.expectEqual(GitCommitPhase.cached_quiet, model.git_commit_phase);
    try std.testing.expectEqual(@as(u64, 0), model.git_push_key);
    try std.testing.expect(findPendingArgv(&fx, &isGitCommitArgv) == null);
}

test "cancel or session change while commit-and-push is in flight does not start a push" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/git-commit-and-push-cancel", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("commit and push cancel", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);
    markDirtyUnstaged(&model, 3);
    markStaleCanPush(&model);

    startCommit(&model, &fx);
    model.git_commit_buffer.apply(.{ .insert_text = "do not push" });
    confirmCommitAndPush(&model, &fx);
    const add = findPending(&fx, model.git_commit_key, &isGitCommitAddArgv) orelse return error.MissingGitAddSpawn;
    dismissCommit(&model, &fx);
    try std.testing.expect(!model.git_commit_then_push);
    try std.testing.expectEqual(@as(u64, 0), model.git_commit_key);
    handleCommitExit(&model, &fx, .{ .key = add.key, .reason = .exited, .code = 0 });
    try std.testing.expectEqual(@as(u64, 0), model.git_push_key);
    try std.testing.expect(findPending(&fx, model.git_commit_key, &isGitCommitArgv) == null);
    try std.testing.expect(findPending(&fx, model.git_push_key, &git_checkout.isGitUpstreamArgv) == null);
    try std.testing.expectEqualStrings(commit_failed_status, model.attach_status());

    startCommit(&model, &fx);
    model.git_commit_buffer.apply(.{ .insert_text = "still no push" });
    confirmCommitAndPush(&model, &fx);
    const add2 = findPending(&fx, model.git_commit_key, &isGitCommitAddArgv) orelse return error.MissingGitAddSpawn2;
    handleCommitExit(&model, &fx, .{ .key = add2.key, .reason = .exited, .code = 0 });
    try std.testing.expectEqual(GitCommitPhase.cached_quiet, model.git_commit_phase);
    dismissCommit(&model, &fx);
    try std.testing.expect(!model.git_commit_then_push);
    try std.testing.expectEqual(@as(u64, 0), model.git_commit_key);
    try std.testing.expectEqual(@as(u64, 0), model.git_push_key);
    try std.testing.expect(findPendingArgv(&fx, &isGitCommitArgv) == null);
    try std.testing.expect(findPending(&fx, model.git_push_key, &git_checkout.isGitUpstreamArgv) == null);

    startCommit(&model, &fx);
    model.git_commit_buffer.apply(.{ .insert_text = "still no push" });
    confirmCommitAndPush(&model, &fx);
    const add2b = findPending(&fx, model.git_commit_key, &isGitCommitAddArgv) orelse return error.MissingGitAddSpawn2b;
    handleCommitExit(&model, &fx, .{ .key = add2b.key, .reason = .exited, .code = 0 });
    const commit = try advanceCachedQuietToCommit(&model, &fx);
    try std.testing.expect(model.git_commit_then_push);
    dismissCommit(&model, &fx);
    try std.testing.expect(!model.git_commit_then_push);
    handleCommitExit(&model, &fx, .{ .key = commit.key, .reason = .exited, .code = 0 });
    try std.testing.expectEqual(@as(u64, 0), model.git_push_key);
    try std.testing.expect(findPending(&fx, model.git_push_key, &git_checkout.isGitUpstreamArgv) == null);

    startCommit(&model, &fx);
    model.git_commit_buffer.apply(.{ .insert_text = "session switch" });
    confirmCommitAndPush(&model, &fx);
    const add3 = findPending(&fx, model.git_commit_key, &isGitCommitAddArgv) orelse return error.MissingGitAddSpawn3;
    try std.testing.expect(model.git_commit_then_push);
    git_checkout.refresh(&model, &fx);
    try std.testing.expect(!model.git_commit_then_push);
    try std.testing.expectEqual(@as(u64, 0), model.git_commit_key);
    handleCommitExit(&model, &fx, .{ .key = add3.key, .reason = .exited, .code = 0 });
    try std.testing.expectEqual(@as(u64, 0), model.git_push_key);
    try std.testing.expect(findPending(&fx, model.git_push_key, &git_checkout.isGitUpstreamArgv) == null);
    try std.testing.expectEqualStrings(commit_failed_status, model.attach_status());
}

test "confirm skips add when include_unstaged is false" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/git-commit-staged-only", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("commit staged only", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);
    markDirtyStaged(&model, 1);

    startCommit(&model, &fx);
    try std.testing.expect(model.git_commit_include_unstaged);
    toggleIncludeUnstaged(&model, &fx);
    try std.testing.expect(!model.git_commit_include_unstaged);
    try std.testing.expect(canCommitGit(&model));
    model.git_commit_buffer.apply(.{ .insert_text = "  staged only  " });
    confirmCommit(&model, &fx);
    try std.testing.expectEqual(GitCommitPhase.cached_quiet, model.git_commit_phase);
    try std.testing.expect(findPending(&fx, model.git_commit_key, &isGitCommitAddArgv) == null);
    try std.testing.expect(findPending(&fx, model.git_commit_key, &isGitCommitArgv) == null);
    const commit = try advanceCachedQuietToCommit(&model, &fx);
    try std.testing.expectEqualStrings("staged only", commit.argv[8]);
    try std.testing.expect(commit.key >= git_commit_key_first);

    handleCommitExit(&model, &fx, .{ .key = commit.key, .reason = .exited, .code = 0 });
    try std.testing.expect(!model.git_commit_active);
    try std.testing.expectEqual(@as(u64, 0), model.git_commit_key);
    try std.testing.expect(!model.has_attach_status());
    try std.testing.expect(model.git_dirty_key != 0);
}

test "confirm and push skips add when include_unstaged is false" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/git-commit-and-push-staged", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("commit and push staged", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);
    markDirtyStaged(&model, 2);
    markStaleCanPush(&model);

    startCommit(&model, &fx);
    toggleIncludeUnstaged(&model, &fx);
    model.git_commit_buffer.apply(.{ .insert_text = "ship staged" });
    confirmCommitAndPush(&model, &fx);
    try std.testing.expect(model.git_commit_then_push);
    try std.testing.expectEqual(GitCommitPhase.cached_quiet, model.git_commit_phase);
    try std.testing.expect(findPending(&fx, model.git_commit_key, &isGitCommitAddArgv) == null);
    try std.testing.expect(findPending(&fx, model.git_commit_key, &isGitCommitArgv) == null);
    const commit = try advanceCachedQuietToCommit(&model, &fx);
    try std.testing.expectEqualStrings("ship staged", commit.argv[8]);

    handleCommitExit(&model, &fx, .{ .key = commit.key, .reason = .exited, .code = 0 });
    try std.testing.expect(!model.git_commit_active);
    try std.testing.expect(!model.git_commit_then_push);
    try std.testing.expect(model.git_push_key != 0);
    try std.testing.expectEqual(git_checkout.GitPushPhase.upstream, model.git_push_phase);
    try std.testing.expect(!model.has_attach_status());
}

test "staged-only commit failure sets Nothing staged to commit" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/git-commit-nothing-staged", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("nothing staged", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);
    markDirtyStaged(&model, 1);
    markFirstPushRemotesOk(&model);

    startCommit(&model, &fx);
    toggleIncludeUnstaged(&model, &fx);
    model.git_commit_buffer.apply(.{ .insert_text = "should fail" });
    confirmCommitAndPush(&model, &fx);
    try std.testing.expectEqual(GitCommitPhase.cached_quiet, model.git_commit_phase);
    try std.testing.expect(findPending(&fx, model.git_commit_key, &isGitCommitAddArgv) == null);
    const commit = try advanceCachedQuietToCommit(&model, &fx);
    handleCommitExit(&model, &fx, .{ .key = commit.key, .reason = .exited, .code = 1 });
    try std.testing.expectEqualStrings(nothing_staged_status, model.attach_status());
    try std.testing.expectEqual(@as(u64, 0), model.git_commit_key);
    try std.testing.expectEqual(@as(u64, 0), model.git_push_key);
    try std.testing.expect(!model.git_commit_then_push);
    try std.testing.expect(model.git_commit_active);
}

test "include-unstaged add then cached-quiet exit 0 is Nothing staged and does not commit" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/git-commit-preflight-empty", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("commit preflight empty", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);
    markDirtyUnstaged(&model, 1);
    markFirstPushRemotesOk(&model);

    startCommit(&model, &fx);
    model.git_commit_buffer.apply(.{ .insert_text = "nothing to stage" });
    confirmCommitAndPush(&model, &fx);
    try std.testing.expect(model.git_commit_then_push);
    const add = findPending(&fx, model.git_commit_key, &isGitCommitAddArgv) orelse return error.MissingGitAddSpawn;
    handleCommitExit(&model, &fx, .{ .key = add.key, .reason = .exited, .code = 0 });
    try std.testing.expectEqual(GitCommitPhase.cached_quiet, model.git_commit_phase);
    try std.testing.expect(model.git_commit_then_push);
    const preflight = findPending(&fx, model.git_commit_key, &isGitCommitCachedQuietArgv) orelse return error.MissingGitCachedQuietSpawn;
    try std.testing.expect(!isGitCommitArgv(preflight.argv));
    try std.testing.expect(!isGitCommitNumstatArgv(preflight.argv));
    handleCommitExit(&model, &fx, .{ .key = preflight.key, .reason = .exited, .code = 0 });
    try std.testing.expectEqualStrings(nothing_staged_status, model.attach_status());
    try std.testing.expectEqual(@as(u64, 0), model.git_commit_key);
    try std.testing.expectEqual(GitCommitPhase.idle, model.git_commit_phase);
    try std.testing.expectEqual(@as(u64, 0), model.git_push_key);
    try std.testing.expect(!model.git_commit_then_push);
    try std.testing.expect(findPendingArgv(&fx, &isGitCommitArgv) == null);
    try std.testing.expect(findPending(&fx, model.git_push_key, &git_checkout.isGitUpstreamArgv) == null);
    try std.testing.expect(model.git_commit_active);
}

test "cached-quiet other exit or spawn failure is Could not commit" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/git-commit-preflight-fail", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("commit preflight fail", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);
    markDirtyStaged(&model, 1);
    markFirstPushRemotesOk(&model);

    startCommit(&model, &fx);
    toggleIncludeUnstaged(&model, &fx);
    model.git_commit_buffer.apply(.{ .insert_text = "inspect failed" });
    confirmCommitAndPush(&model, &fx);
    try std.testing.expectEqual(GitCommitPhase.cached_quiet, model.git_commit_phase);
    const preflight = findPending(&fx, model.git_commit_key, &isGitCommitCachedQuietArgv) orelse return error.MissingGitCachedQuietSpawn;
    handleCommitExit(&model, &fx, .{ .key = preflight.key, .reason = .exited, .code = 128 });
    try std.testing.expectEqualStrings(commit_failed_status, model.attach_status());
    try std.testing.expectEqual(@as(u64, 0), model.git_commit_key);
    try std.testing.expectEqual(GitCommitPhase.idle, model.git_commit_phase);
    try std.testing.expectEqual(@as(u64, 0), model.git_push_key);
    try std.testing.expect(!model.git_commit_then_push);
    try std.testing.expect(findPendingArgv(&fx, &isGitCommitArgv) == null);
    try std.testing.expect(model.git_commit_active);

    model.clearAttachStatus();
    confirmCommit(&model, &fx);
    const preflight2 = findPending(&fx, model.git_commit_key, &isGitCommitCachedQuietArgv) orelse return error.MissingGitCachedQuietSpawn2;
    handleCommitExit(&model, &fx, .{ .key = preflight2.key, .reason = .rejected, .code = 1 });
    try std.testing.expectEqualStrings(commit_failed_status, model.attach_status());
    try std.testing.expectEqual(@as(u64, 0), model.git_commit_key);
    try std.testing.expect(findPendingArgv(&fx, &isGitCommitArgv) == null);
    try std.testing.expect(model.git_commit_active);
}

test "startCommit resets include_unstaged to true" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/git-commit-reset-toggle", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);
    model.store_io = std.testing.io;
    const id = model.addSession("reset toggle", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);
    markDirtyStaged(&model, 1);
    model.git_commit_include_unstaged = false;
    startCommit(&model, &fx);
    try std.testing.expect(model.git_commit_active);
    try std.testing.expect(model.git_commit_include_unstaged);
}

test "commit snapshot argv is numstat untracked script when include-unstaged and --cached when off" {
    var work_buf: [commit_numstat_argv_len][]const u8 = undefined;
    const work = commitNumstatArgvFor("/tmp/faku-commit-snap", true, &work_buf);
    try std.testing.expectEqual(git_numstat.argv_len, work.len);
    try std.testing.expectEqualStrings(sh_bin, work[0]);
    try std.testing.expectEqualStrings("-c", work[1]);
    try std.testing.expectEqualStrings(main.fx_ask_chdir_script, work[2]);
    try std.testing.expectEqualStrings("sh", work[3]);
    try std.testing.expectEqualStrings("/tmp/faku-commit-snap", work[4]);
    try std.testing.expectEqualStrings(sh_bin, work[5]);
    try std.testing.expectEqualStrings("-c", work[6]);
    try std.testing.expectEqualStrings(git_numstat.numstat_untracked_script, work[7]);
    try std.testing.expect(git_numstat.isGitNumstatArgv(work));
    try std.testing.expect(isGitCommitNumstatWorkingTreeArgv(work));
    try std.testing.expect(!isGitCommitNumstatCachedArgv(work));
    try std.testing.expect(isGitCommitNumstatArgv(work));
    try std.testing.expect(!isGitCommitAddArgv(work));
    try std.testing.expect(!isGitCommitArgv(work));
    try std.testing.expect(!isGitCommitCachedQuietArgv(work));
    try std.testing.expect(std.mem.indexOf(u8, work[2], git_diff_cmd) == null);
    try std.testing.expect(std.mem.indexOf(u8, work[2], git_numstat.numstat_untracked_script) == null);
    try std.testing.expect(std.mem.indexOf(u8, work[7], git_numstat.git_ls_files_others) != null);
    try std.testing.expect(std.mem.indexOf(u8, work[7], git_numstat.untracked_max_bytes_s) != null);

    var cached_buf: [commit_numstat_argv_len][]const u8 = undefined;
    const cached = commitNumstatArgvFor("/tmp/faku-commit-snap", false, &cached_buf);
    try std.testing.expectEqual(@as(usize, 10), cached.len);
    try std.testing.expectEqualStrings(git_diff_cmd, cached[6]);
    try std.testing.expectEqualStrings(git_cached_flag, cached[7]);
    try std.testing.expectEqualStrings(git_numstat_flag, cached[8]);
    try std.testing.expectEqualStrings(git_pathspec_dash, cached[9]);
    try std.testing.expect(isGitCommitNumstatCachedArgv(cached));
    try std.testing.expect(!isGitCommitNumstatWorkingTreeArgv(cached));
    try std.testing.expect(isGitCommitNumstatArgv(cached));
    try std.testing.expect(!isGitCommitCachedQuietArgv(cached));
    try std.testing.expect(!git_numstat.isGitNumstatArgv(cached));
    try std.testing.expect(std.mem.indexOf(u8, cached[2], git_cached_flag) == null);
    try std.testing.expect(std.mem.indexOf(u8, cached[2], git_numstat_flag) == null);
}

test "startCommit kicks a commit-snapshot probe that does not reuse project-row numstat keys" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/git-commit-snap-start", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("commit snap start", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);
    markDirtyUnstaged(&model, 2);
    model.git_numstat_additions = 9;
    model.git_numstat_deletions = 1;
    model.git_numstat_key = git_numstat.git_numstat_key_first;

    startCommit(&model, &fx);
    try std.testing.expect(model.git_commit_active);
    try std.testing.expectEqual(git_commit_numstat_key_first, model.git_commit_numstat_key);
    try std.testing.expectEqual(git_numstat.git_numstat_key_first, model.git_numstat_key);
    try std.testing.expectEqual(@as(u64, 9), model.git_numstat_additions);
    try std.testing.expect(!hasGitCommitNumstat(&model));
    try std.testing.expect(!model.has_git_commit_numstat());
    const probe = findPending(&fx, model.git_commit_numstat_key, &isGitCommitNumstatWorkingTreeArgv) orelse return error.MissingCommitNumstatSpawn;
    try std.testing.expect(probe.key >= git_commit_numstat_key_first);
    try std.testing.expect(probe.key != model.git_numstat_key);
    try std.testing.expect(probe.key != model.git_commit_key);
    try std.testing.expectEqualStrings(project, probe.argv[4]);
    try std.testing.expect(!isGitCommitNumstatCachedArgv(probe.argv));
    try std.testing.expect(git_numstat.isGitNumstatArgv(probe.argv));
    try std.testing.expectEqualStrings(git_numstat.numstat_untracked_script, probe.argv[7]);
}

test "commit snapshot label omits zero fail empty and in-flight" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/git-commit-snap-omit", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("commit snap omit", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);
    markDirtyUnstaged(&model, 1);

    startCommit(&model, &fx);
    const key = model.git_commit_numstat_key;
    try std.testing.expect(key != 0);
    try std.testing.expect(!hasGitCommitNumstat(&model));
    try std.testing.expectEqualStrings("", gitCommitNumstatLabel(&model));

    applyNumstatLine(&model, .{ .key = key, .line = "0\t0\tclean.zig\n" });
    try std.testing.expect(!hasGitCommitNumstat(&model));

    applyNumstatLine(&model, .{ .key = key, .line = "3\t1\tsrc/a.zig\n" });
    applyNumstatLine(&model, .{ .key = key, .line = "5\t0\tnew.txt\n" });
    try std.testing.expect(hasGitCommitNumstat(&model));
    try std.testing.expectEqualStrings("+8 −1", gitCommitNumstatLabel(&model));
    try std.testing.expectEqualStrings("+8 −1", model.git_commit_numstat_label());

    handleNumstatExit(&model, .{ .key = key, .reason = .exited, .code = 1 });
    try std.testing.expectEqual(@as(u64, 0), model.git_commit_numstat_key);
    try std.testing.expect(!hasGitCommitNumstat(&model));
    try std.testing.expectEqualStrings("", gitCommitNumstatLabel(&model));

    refreshCommitNumstat(&model, &fx);
    const key2 = model.git_commit_numstat_key;
    applyNumstatLine(&model, .{ .key = key2, .line = "2\t0\tb.zig\n" });
    handleNumstatExit(&model, .{ .key = key2, .reason = .exited, .code = 0 });
    try std.testing.expectEqualStrings("+2 −0", gitCommitNumstatLabel(&model));

    refreshCommitNumstat(&model, &fx);
    const key3 = model.git_commit_numstat_key;
    try std.testing.expect(!hasGitCommitNumstat(&model));
    applyNumstatLine(&model, .{ .key = key3, .line = "-\t-\tbin.dat\n" });
    handleNumstatExit(&model, .{ .key = key3, .reason = .exited, .code = 0 });
    try std.testing.expect(!hasGitCommitNumstat(&model));
}

test "toggle refreshes commit snapshot probe and cancel clears the label" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/git-commit-snap-toggle", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("commit snap toggle", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);
    markDirtyStaged(&model, 1);

    startCommit(&model, &fx);
    const first = findPending(&fx, model.git_commit_numstat_key, &isGitCommitNumstatWorkingTreeArgv) orelse return error.MissingWorkingTreeNumstat;
    try std.testing.expect(git_numstat.isGitNumstatArgv(first.argv));
    applyNumstatLine(&model, .{ .key = first.key, .line = "4\t2\ta.zig\n" });
    applyNumstatLine(&model, .{ .key = first.key, .line = "6\t0\tuntracked.txt\n" });
    handleNumstatExit(&model, .{ .key = first.key, .reason = .exited, .code = 0 });
    try std.testing.expectEqualStrings("+10 −2", gitCommitNumstatLabel(&model));

    toggleIncludeUnstaged(&model, &fx);
    try std.testing.expect(!model.git_commit_include_unstaged);
    try std.testing.expect(!hasGitCommitNumstat(&model));
    try std.testing.expect(model.git_commit_numstat_key != first.key);
    const second = findPending(&fx, model.git_commit_numstat_key, &isGitCommitNumstatCachedArgv) orelse return error.MissingCachedNumstat;
    try std.testing.expect(second.key != first.key);
    try std.testing.expect(!isGitCommitNumstatWorkingTreeArgv(second.argv));
    applyNumstatLine(&model, .{ .key = second.key, .line = "1\t0\tstaged.zig\n" });
    handleNumstatExit(&model, .{ .key = second.key, .reason = .exited, .code = 0 });
    try std.testing.expectEqualStrings("+1 −0", gitCommitNumstatLabel(&model));

    toggleIncludeUnstaged(&model, &fx);
    try std.testing.expect(model.git_commit_include_unstaged);
    const third = findPending(&fx, model.git_commit_numstat_key, &isGitCommitNumstatWorkingTreeArgv) orelse return error.MissingWorkingTreeNumstat2;
    try std.testing.expect(third.key != second.key);
    applyNumstatLine(&model, .{ .key = third.key, .line = "8\t3\tc.zig\n" });
    try std.testing.expectEqualStrings("+8 −3", gitCommitNumstatLabel(&model));

    dismissCommit(&model, &fx);
    try std.testing.expect(!model.git_commit_active);
    try std.testing.expectEqual(@as(u64, 0), model.git_commit_numstat_key);
    try std.testing.expect(!hasGitCommitNumstat(&model));
    try std.testing.expectEqualStrings("", gitCommitNumstatLabel(&model));
    applyNumstatLine(&model, .{ .key = third.key, .line = "99\t99\tlate.zig\n" });
    handleNumstatExit(&model, .{ .key = third.key, .reason = .exited, .code = 0 });
    try std.testing.expect(!hasGitCommitNumstat(&model));

    startCommit(&model, &fx);
    const fourth = findPending(&fx, model.git_commit_numstat_key, &isGitCommitNumstatWorkingTreeArgv) orelse return error.MissingWorkingTreeNumstat3;
    applyNumstatLine(&model, .{ .key = fourth.key, .line = "5\t1\td.zig\n" });
    try std.testing.expectEqualStrings("+5 −1", gitCommitNumstatLabel(&model));
    git_checkout.refresh(&model, &fx);
    try std.testing.expect(!model.git_commit_active);
    try std.testing.expectEqual(@as(u64, 0), model.git_commit_numstat_key);
    try std.testing.expect(!hasGitCommitNumstat(&model));
}

fn enableFx(model: *Model) void {
    model.fx_available = true;
    model.setFxPath("fx");
}

fn expectGenerateArgv(argv: []const []const u8, cwd: []const u8, include_unstaged: bool) !void {
    try std.testing.expect(isGitCommitGenerateArgv(argv));
    try std.testing.expectEqualStrings(sh_bin, argv[0]);
    try std.testing.expectEqualStrings("-c", argv[1]);
    try std.testing.expectEqualStrings(main.fx_ask_chdir_script, argv[2]);
    try std.testing.expectEqualStrings("sh", argv[3]);
    try std.testing.expectEqualStrings(cwd, argv[4]);
    try std.testing.expectEqualStrings("fx", argv[5]);
    try std.testing.expectEqualStrings(fx_ask_cmd, argv[6]);
    try std.testing.expectEqualStrings(fx_ask_no_save, argv[7]);
    try std.testing.expectEqualStrings(fx_ask_auto, argv[8]);
    try std.testing.expectEqualStrings(fx_ask_json, argv[9]);
    try std.testing.expectEqualStrings(fx_ask_dash, argv[10]);
    try std.testing.expectEqualStrings(generatePromptFor(include_unstaged), argv[11]);
    try std.testing.expect(std.mem.indexOf(u8, argv[2], fx_ask_cmd) == null);
    try std.testing.expect(std.mem.indexOf(u8, argv[2], generatePromptFor(include_unstaged)) == null);
    try std.testing.expect(std.mem.indexOf(u8, argv[2], fx_ask_no_save) == null);
    try std.testing.expect(std.mem.indexOf(u8, argv[11], "--yolo") == null);
    try std.testing.expect(std.mem.indexOf(u8, argv[11], "--resume") == null);
    var i: usize = 0;
    while (i < argv.len) : (i += 1) {
        try std.testing.expect(!std.mem.eql(u8, argv[i], "--yolo"));
        try std.testing.expect(!std.mem.eql(u8, argv[i], "--resume"));
    }
    try std.testing.expect(!isGitCommitAddArgv(argv));
    try std.testing.expect(!isGitCommitArgv(argv));
    try std.testing.expect(!isGitCommitCachedQuietArgv(argv));
    try std.testing.expect(!isGitCommitNumstatArgv(argv));
}

test "generate argv is chdir plus fx ask with documented flags and a prompt slot" {
    var on_buf: [generate_argv_len][]const u8 = undefined;
    const on_argv = generateArgvFor("/tmp/faku-generate", "fx", true, &on_buf);
    try std.testing.expectEqual(@as(usize, 12), on_argv.len);
    try expectGenerateArgv(on_argv, "/tmp/faku-generate", true);
    try std.testing.expect(std.mem.indexOf(u8, on_argv[11], "unstaged") != null);
    try std.testing.expect(std.mem.indexOf(u8, on_argv[11], "untracked") != null);

    var off_buf: [generate_argv_len][]const u8 = undefined;
    const off_argv = generateArgvFor("/tmp/faku-generate", "fx", false, &off_buf);
    try expectGenerateArgv(off_argv, "/tmp/faku-generate", false);
    try std.testing.expect(std.mem.indexOf(u8, off_argv[11], "staged changes only") != null);
    try std.testing.expect(!std.mem.eql(u8, on_argv[11], off_argv[11]));
}

test "takeGeneratedSubject prefers JSON output then first stdout line" {
    var buf: [max_commit_message]u8 = undefined;
    try std.testing.expectEqualStrings("wrap the dirty probe", takeGeneratedSubject("  wrap the dirty probe  \nmore\n", &buf).?);
    try std.testing.expectEqualStrings("ship it", takeGeneratedSubject("{\"output\":\"  ship it  \\nbody\"}", &buf).?);
    try std.testing.expect(takeGeneratedSubject("{\"output\":\"   \"}", &buf) == null);
    try std.testing.expect(takeGeneratedSubject("   \n", &buf) == null);
}

test "empty plus fx available one-shots generate; include_unstaged changes the prompt" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/git-commit-generate-argv", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    enableFx(&model);
    const id = model.addSession("commit generate argv", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);
    markDirtyUnstaged(&model, 2);
    model.git_has_staged = true;

    startCommit(&model, &fx);
    confirmCommit(&model, &fx);
    try std.testing.expectEqual(git_commit_generate_key_first, model.git_commit_generate_key);
    try std.testing.expect(model.git_commit_generate_key >= git_commit_generate_key_first);
    try std.testing.expect(model.git_commit_generate_key != model.git_commit_key);
    try std.testing.expect(model.git_commit_generate_key != model.git_commit_numstat_key);
    try std.testing.expect(hasGitCommitGenerate(&model));
    try std.testing.expect(model.has_git_commit_generate());
    try std.testing.expect(git_checkout.gitMutationInFlight(&model));
    const gen = findPending(&fx, model.git_commit_generate_key, &isGitCommitGenerateArgv) orelse return error.MissingGenerateSpawn;
    try expectGenerateArgv(gen.argv, project, true);
    try std.testing.expect(findPendingArgv(&fx, &isGitCommitAddArgv) == null);
    try std.testing.expect(findPendingArgv(&fx, &isGitCommitArgv) == null);

    handleGenerateExit(&model, &fx, .{ .key = gen.key, .reason = .exited, .code = 1 });
    try std.testing.expectEqualStrings(generate_failed_status, model.attach_status());
    try std.testing.expectEqual(@as(u64, 0), model.git_commit_generate_key);
    try std.testing.expect(model.git_commit_active);

    toggleIncludeUnstaged(&model, &fx);
    model.clearAttachStatus();
    confirmCommit(&model, &fx);
    const gen_off = findPending(&fx, model.git_commit_generate_key, &isGitCommitGenerateArgv) orelse return error.MissingGenerateSpawnOff;
    try expectGenerateArgv(gen_off.argv, project, false);
    try std.testing.expect(gen_off.key != gen.key);
    try std.testing.expect(gen_off.key >= git_commit_generate_key_first);
}

test "generate success fills the subject and auto-adds" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/git-commit-generate-ok", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    enableFx(&model);
    const id = model.addSession("commit generate ok", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);
    markDirtyUnstaged(&model, 3);

    startCommit(&model, &fx);
    confirmCommit(&model, &fx);
    const gen = findPending(&fx, model.git_commit_generate_key, &isGitCommitGenerateArgv) orelse return error.MissingGenerateSpawn;
    applyGenerateLine(&model, .{ .key = gen.key, .line = "  wrap the dirty probe  \nmore\n" });
    handleGenerateExit(&model, &fx, .{ .key = gen.key, .reason = .exited, .code = 0 });
    try std.testing.expectEqual(@as(u64, 0), model.git_commit_generate_key);
    try std.testing.expectEqualStrings("wrap the dirty probe", model.git_commit_buffer.text());
    try std.testing.expectEqual(GitCommitPhase.add, model.git_commit_phase);
    const add = findPending(&fx, model.git_commit_key, &isGitCommitAddArgv) orelse return error.MissingGitAddSpawn;
    try std.testing.expect(add.key >= git_commit_key_first);
    try std.testing.expect(add.key != gen.key);
    handleCommitExit(&model, &fx, .{ .key = add.key, .reason = .exited, .code = 0 });
    const commit = try advanceCachedQuietToCommit(&model, &fx);
    try std.testing.expectEqualStrings("wrap the dirty probe", commit.argv[8]);
    try std.testing.expectEqual(@as(u64, 0), model.git_push_key);
}

test "generate JSON output then commit when include_unstaged is off" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/git-commit-generate-json", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    enableFx(&model);
    const id = model.addSession("commit generate json", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);
    markDirtyStaged(&model, 1);

    startCommit(&model, &fx);
    toggleIncludeUnstaged(&model, &fx);
    confirmCommit(&model, &fx);
    const gen = findPending(&fx, model.git_commit_generate_key, &isGitCommitGenerateArgv) orelse return error.MissingGenerateSpawn;
    try expectGenerateArgv(gen.argv, project, false);
    applyGenerateLine(&model, .{ .key = gen.key, .line = "{\"output\":\"  staged only  \\nbody\"}\n" });
    handleGenerateExit(&model, &fx, .{ .key = gen.key, .reason = .exited, .code = 0 });
    try std.testing.expectEqual(GitCommitPhase.cached_quiet, model.git_commit_phase);
    try std.testing.expect(findPending(&fx, model.git_commit_key, &isGitCommitAddArgv) == null);
    try std.testing.expect(findPending(&fx, model.git_commit_key, &isGitCommitArgv) == null);
    const commit = try advanceCachedQuietToCommit(&model, &fx);
    try std.testing.expectEqualStrings("staged only", commit.argv[8]);
}

test "generate then commit and push starts push only after successful commit" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/git-commit-generate-push", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    enableFx(&model);
    const id = model.addSession("commit generate push", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);
    markDirtyUnstaged(&model, 2);
    markStaleCanPush(&model);

    startCommit(&model, &fx);
    confirmCommitAndPush(&model, &fx);
    try std.testing.expect(model.git_commit_then_push);
    const gen = findPending(&fx, model.git_commit_generate_key, &isGitCommitGenerateArgv) orelse return error.MissingGenerateSpawn;
    try std.testing.expectEqual(@as(u64, 0), model.git_push_key);
    applyGenerateLine(&model, .{ .key = gen.key, .line = "ship the dirty probe\n" });
    handleGenerateExit(&model, &fx, .{ .key = gen.key, .reason = .exited, .code = 0 });
    try std.testing.expect(model.git_commit_then_push);
    try std.testing.expectEqual(@as(u64, 0), model.git_push_key);
    const add = findPending(&fx, model.git_commit_key, &isGitCommitAddArgv) orelse return error.MissingGitAddSpawn;
    handleCommitExit(&model, &fx, .{ .key = add.key, .reason = .exited, .code = 0 });
    try std.testing.expectEqual(@as(u64, 0), model.git_push_key);
    const commit = try advanceCachedQuietToCommit(&model, &fx);
    try std.testing.expectEqualStrings("ship the dirty probe", commit.argv[8]);
    try std.testing.expectEqual(@as(u64, 0), model.git_push_key);
    handleCommitExit(&model, &fx, .{ .key = commit.key, .reason = .exited, .code = 0 });
    try std.testing.expect(!model.git_commit_active);
    try std.testing.expect(!model.git_commit_then_push);
    try std.testing.expect(model.git_push_key != 0);
    try std.testing.expectEqual(git_checkout.GitPushPhase.upstream, model.git_push_phase);
}

test "generate fail or empty stdout keeps the card open and does not commit" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/git-commit-generate-fail", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    enableFx(&model);
    const id = model.addSession("commit generate fail", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);
    markDirtyUnstaged(&model, 1);
    markFirstPushRemotesOk(&model);

    startCommit(&model, &fx);
    confirmCommitAndPush(&model, &fx);
    const gen = findPending(&fx, model.git_commit_generate_key, &isGitCommitGenerateArgv) orelse return error.MissingGenerateSpawn;
    handleGenerateExit(&model, &fx, .{ .key = gen.key, .reason = .exited, .code = 1 });
    try std.testing.expectEqualStrings(generate_failed_status, model.attach_status());
    try std.testing.expect(model.git_commit_active);
    try std.testing.expectEqual(@as(u64, 0), model.git_commit_key);
    try std.testing.expectEqual(@as(u64, 0), model.git_commit_generate_key);
    try std.testing.expectEqual(@as(u64, 0), model.git_push_key);
    try std.testing.expect(!model.git_commit_then_push);
    try std.testing.expect(findPendingArgv(&fx, &isGitCommitAddArgv) == null);
    try std.testing.expect(findPendingArgv(&fx, &isGitCommitArgv) == null);

    model.clearAttachStatus();
    confirmCommit(&model, &fx);
    const gen2 = findPending(&fx, model.git_commit_generate_key, &isGitCommitGenerateArgv) orelse return error.MissingGenerateSpawn2;
    handleGenerateExit(&model, &fx, .{ .key = gen2.key, .reason = .exited, .code = 0 });
    try std.testing.expectEqualStrings(generate_failed_status, model.attach_status());
    try std.testing.expect(model.git_commit_active);
    try std.testing.expectEqual(@as(u64, 0), model.git_commit_key);
    try std.testing.expect(findPendingArgv(&fx, &isGitCommitAddArgv) == null);

    model.clearAttachStatus();
    confirmCommit(&model, &fx);
    const gen3 = findPending(&fx, model.git_commit_generate_key, &isGitCommitGenerateArgv) orelse return error.MissingGenerateSpawn3;
    applyGenerateLine(&model, .{ .key = gen3.key, .line = "{\"output\":\"   \"}\n" });
    handleGenerateExit(&model, &fx, .{ .key = gen3.key, .reason = .exited, .code = 0 });
    try std.testing.expectEqualStrings(generate_failed_status, model.attach_status());
    try std.testing.expect(model.git_commit_active);
    try std.testing.expectEqual(@as(u64, 0), model.git_commit_key);
    try std.testing.expectEqual(@as(u64, 0), model.git_push_key);
}

test "cancel or session-switch drops generate and does not commit" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/git-commit-generate-cancel", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    enableFx(&model);
    const id = model.addSession("commit generate cancel", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);
    markDirtyUnstaged(&model, 2);
    markFirstPushRemotesOk(&model);

    startCommit(&model, &fx);
    confirmCommitAndPush(&model, &fx);
    const gen = findPending(&fx, model.git_commit_generate_key, &isGitCommitGenerateArgv) orelse return error.MissingGenerateSpawn;
    dismissCommit(&model, &fx);
    try std.testing.expect(!model.git_commit_active);
    try std.testing.expectEqual(@as(u64, 0), model.git_commit_generate_key);
    try std.testing.expectEqual(@as(u64, 0), model.git_commit_key);
    try std.testing.expectEqual(@as(u64, 0), model.git_push_key);
    try std.testing.expect(!model.git_commit_then_push);
    handleGenerateExit(&model, &fx, .{ .key = gen.key, .reason = .exited, .code = 0 });
    try std.testing.expectEqual(@as(u64, 0), model.git_commit_key);
    try std.testing.expect(findPendingArgv(&fx, &isGitCommitAddArgv) == null);
    try std.testing.expect(findPendingArgv(&fx, &isGitCommitArgv) == null);

    startCommit(&model, &fx);
    confirmCommit(&model, &fx);
    const gen2 = findPending(&fx, model.git_commit_generate_key, &isGitCommitGenerateArgv) orelse return error.MissingGenerateSpawn2;
    git_checkout.refresh(&model, &fx);
    try std.testing.expect(!model.git_commit_active);
    try std.testing.expectEqual(@as(u64, 0), model.git_commit_generate_key);
    try std.testing.expectEqual(@as(u64, 0), model.git_commit_key);
    try std.testing.expectEqual(@as(u64, 0), model.git_push_key);
    handleGenerateExit(&model, &fx, .{ .key = gen2.key, .reason = .exited, .code = 0 });
    try std.testing.expect(findPendingArgv(&fx, &isGitCommitAddArgv) == null);
    try std.testing.expectEqualStrings(commit_failed_status, model.attach_status());
}

test "confirm while generating is a no-op" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/git-commit-generate-busy", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    enableFx(&model);
    const id = model.addSession("commit generate busy", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);
    markDirtyUnstaged(&model, 1);

    startCommit(&model, &fx);
    confirmCommit(&model, &fx);
    const key = model.git_commit_generate_key;
    try std.testing.expect(key != 0);
    model.git_commit_buffer.apply(.{ .insert_text = "typed while generating" });
    confirmCommit(&model, &fx);
    confirmCommitAndPush(&model, &fx);
    try std.testing.expectEqual(key, model.git_commit_generate_key);
    try std.testing.expectEqual(@as(u64, 0), model.git_commit_key);
    try std.testing.expect(findPendingArgv(&fx, &isGitCommitAddArgv) == null);
    try std.testing.expect(findPendingArgv(&fx, &isGitCommitArgv) == null);
}

test "non-empty typed message skips generate and goes straight to add" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/git-commit-generate-skip", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    enableFx(&model);
    const id = model.addSession("commit generate skip", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);
    markDirtyUnstaged(&model, 1);

    startCommit(&model, &fx);
    model.git_commit_buffer.apply(.{ .insert_text = "typed subject" });
    confirmCommit(&model, &fx);
    try std.testing.expectEqual(@as(u64, 0), model.git_commit_generate_key);
    try std.testing.expect(findPendingArgv(&fx, &isGitCommitGenerateArgv) == null);
    const add = findPending(&fx, model.git_commit_key, &isGitCommitAddArgv) orelse return error.MissingGitAddSpawn;
    try std.testing.expect(add.key >= git_commit_key_first);
}

test "empty plus fx available with empty fx path stays on Enter a commit message" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/git-commit-generate-nopath", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    model.fx_available = true;
    const id = model.addSession("commit generate nopath", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);
    markDirtyUnstaged(&model, 1);

    startCommit(&model, &fx);
    confirmCommit(&model, &fx);
    try std.testing.expectEqual(@as(u64, 0), model.git_commit_generate_key);
    try std.testing.expectEqual(@as(u64, 0), model.git_commit_key);
    try std.testing.expect(findPendingArgv(&fx, &isGitCommitGenerateArgv) == null);
    try std.testing.expectEqualStrings(empty_message_status, model.attach_status());
}
