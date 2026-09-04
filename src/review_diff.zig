//! First-cut Waku Environment Compare / Review file list.
//!
//! Environment Compare and header +/- close the Environment
//! Summary popover (when open) and open the right-panel Diff tab
//! with this Review body inline. Diff-tab default source is
//! Uncommitted (Waku web `changes` defaults `uncommitted`); if
//! Compare is already active, that source is kept and refreshed.
//! `open` still starts Branch for unit tests of the probe stack.
//! `git diff --name-status @{upstream}...HEAD` (symmetric range,
//! same spirit as ahead/behind). Uncommitted is a switchable
//! first-cut: tracked `git diff --name-status HEAD` plus
//! untracked, non-ignored paths from
//! `git ls-files --others --exclude-standard` (synthetic
//! `?\tpath` rows; no text-only / size filter). Packed under
//! Native `max_effect_argv` as chdir + nested `/bin/sh -c`.
//! Staged is a switchable first-cut: one-shot
//! `git diff --name-status --cached` (index vs HEAD;
//! untracked cannot appear unless already staged). Unstaged is a
//! switchable first-cut: one-shot `git diff --name-status`
//! (worktree vs index, tracked only; no `--cached`, no `HEAD`
//! range). Committed is a switchable first-cut: one-shot
//! `git diff --name-status origin/HEAD...HEAD` (merge-base of
//! the default remote branch and HEAD → HEAD; distinct from
//! Branch `@{upstream}...HEAD`). Missing `origin/HEAD` (non-zero
//! git exit) retries the same argv with last-slot `main...HEAD`,
//! then `master...HEAD`; all three failing stays
//! `Could not compare.` A successful origin/HEAD probe with
//! zero files is `No changes to compare` (no main/master
//! fall-through). LastTurn is a switchable first-cut: one-shot
//! `git diff --name-status` of the last completed turn.
//! When both finish-time turn-diff (`worktree_turn_diff_sha`)
//! and turn-end (`worktree_turn_end_sha`) are valid 40-hex,
//! the operand is `diff..end` (two-dot). Else when both
//! send-time start (`worktree_snapshot_sha`) and finish-time
//! end are valid 40-hex, the operand is `start..end` (two-dot,
//! own argv slot; Waku `git diff from to` / `A..B` is the tree
//! of A vs the tree of B). Else a valid start is a bare 40-hex
//! two-dot vs the live worktree. Else send-time rewind
//! `git diff --name-status <sha>...HEAD` (`latestRewindSha`
//! / `rewind_refs`). Isolated index, dangling commits
//! named `refs/faku/session-{id}-turn-start-{n}` (plus
//! `turn-{n-1}` when that baseline is missing), finish
//! `turn-{n}`, and `turn-diff-{n}` from
//! `prepareTurnDiffBase`. Compare uses the stored shas, not
//! the refs. Not `HEAD~1`, not `refs/waku/`. Missing all
//! three does not spawn and stays `Could not compare.` (no
//! main/master fallback). The chosen operand lives on the
//! model so hunk clicks reuse it if later snapshots or
//! `rewind_refs` change.
//! Tracked files only (no untracked `?`, no `--no-index`).
//! Clicking a tracked name-status row one-shots `git diff`
//! for that path (current source + the Committed range that
//! already succeeded, or the stored LastTurn range).
//! `--` and the path are own argv slots.
//! Uncommitted `?` rows one-shot
//! `git diff --no-index -- /dev/null <path>` (POSIX empty
//! left side; `--no-index` implies `--exit-code`, so exit 1
//! with a body is a successful patch). `--no-index`, `--`,
//! `/dev/null`, and the path are own argv slots (11 total;
//! under Native `max_effect_argv` 16). A `?` directory that
//! makes git fail is `Could not show diff.` — no invented
//! tree listing. Hunk
//! spawn-key band 520+ is distinct from name-status 510+.
//! All six use the `/bin/sh -c` `fx_ask_chdir_script` chdir
//! workaround. Last-slot operands (`@{upstream}...HEAD` /
//! `--cached` / `origin/HEAD...HEAD` / `main...HEAD` /
//! `master...HEAD` / `<40-hex>..<40-hex>` / `<40-hex>` /
//! `<40-hex>...HEAD`) are their
//! own argv slots — never interpolated into `-c`. Uncommitted packs
//! `HEAD` into the nested script (not a last-slot `HEAD`).
//! Unstaged has no trailing operand, so its argv is 8 slots
//! (the 9-slot detector still accepts Branch / Staged /
//! Committed / LastTurn). Distinct
//! spawn-key band 510+ (after git-common-dir
//! 500+). Cap 64 rows. Empty / clean is `No changes to compare`.
//! Failed / no upstream / missing workspace is a short muted
//! status — no invented files. First-cut hunks only: no
//! syntax highlighting, no gap expansion. The right-panel Diff
//! tab hosts this same body (not a second git probe stack).
//! Leftovers: force, background work, daemon

//! WorkspaceOperation. Not transcript checkpoint +/-.
//! LastTurn uses stored shas, not the refs, and not a
//! `refs/waku/` Compare operand.
//!
//! Spawn/line/exit orchestration lives here. Windows is skipped
//! this cut (app.zon already includes windows; no `git.exe -C`
//! spawn path yet). Remaining leftover after composer git_checkout
//! Windows.

const std = @import("std");
const builtin = @import("builtin");
const native_sdk = @import("native_sdk");
const main = @import("main.zig");
const git_ahead_behind = @import("git_ahead_behind.zig");
const git_checkout = @import("git_checkout.zig");
const git_common_dir = @import("git_common_dir.zig");
const rewind = @import("rewind.zig");

const Model = main.Model;
const Effects = main.Effects;
const writeFixed = main.writeFixed;

/// One-shot Review `git diff --name-status` (Branch,
/// Uncommitted, Staged, Unstaged, Committed, or LastTurn). Distinct from git_branch
/// (200+), git_dirty (300+), git_numstat (350+), git_push
/// (360+), git_worktree_add (370+), git_ahead_behind (380+),
/// git_worktree_base (390+), file_mention (400+), git_commit
/// (450+), git_commit_numstat (460+), generate (470+), remotes
/// (480+), toplevel (490+), and common-dir (500+). Band is 510+.
/// Incremented per open / source switch so a cancelled spawn
/// cannot paint a later session.
pub const review_diff_key_first: u64 = 510;

/// One-shot Review `git diff [operand] -- <path>` hunk probe,
/// or untracked `git diff --no-index -- /dev/null <path>`.
/// Distinct from name-status 510+. Band is 520+. Incremented
/// per file click so a cancelled spawn cannot paint a later
/// click or session.
pub const review_diff_hunk_key_first: u64 = 520;

/// Compare / header +/- open the Diff tab on Uncommitted when no
/// compare is active. Uncommitted is first-cut
/// tracked `git diff --name-status HEAD` plus untracked
/// `git ls-files --others --exclude-standard` (`?` rows). Staged
/// is first-cut index vs HEAD `git diff --name-status --cached`.
/// Unstaged is first-cut worktree vs index `git diff
/// --name-status` (tracked only). Committed is first-cut
/// `git diff --name-status origin/HEAD...HEAD`, then local
/// `main...HEAD` / `master...HEAD` on a still-current non-zero
/// exit. LastTurn is first-cut last-completed-turn
/// `git diff --name-status diff..end` when turn-diff and
/// turn-end exist, else `start..end` when both snapshots
/// exist, else send-time `<40-hex>` (rewind `<sha>...HEAD`
/// fallback; not HEAD~1). `open` still starts Branch.
pub const Source = enum {
    branch,
    uncommitted,
    staged,
    unstaged,
    committed,
    last_turn,
};

/// First-cut Committed range probe. Always starts at
/// `origin/HEAD...HEAD`. A still-current non-zero exit advances
/// to `main...HEAD`, then `master...HEAD`. Reset when leaving
/// or re-selecting Committed.
pub const CommittedRange = enum {
    origin,
    main,
    master,
};

pub const max_review_diff_files: usize = 64;
pub const max_review_diff_path: usize = 255;
/// `X ` plus path. Rename/copy uses the destination path only.
pub const max_review_diff_label: usize = 258;
pub const max_review_diff_status: usize = 32;

pub const git_bin = "git";
pub const git_diff_cmd = "diff";
pub const git_name_status = "--name-status";
pub const git_upstream_range = git_ahead_behind.git_upstream_range;
pub const git_head = "HEAD";
pub const git_ls_files_cmd = "ls-files";
pub const git_ls_files_others = "--others";
pub const git_ls_files_exclude_standard = "--exclude-standard";
/// Same `--cached` as `git_commit.git_cached_flag`. Local to avoid
/// a review_diff ↔ git_commit import cycle. Own argv slot.
pub const git_cached_flag = "--cached";
/// Symmetric range vs the default remote branch. Own argv slot,
/// parallel to Branch `git_upstream_range` (`@{upstream}...HEAD`).
pub const git_committed_range = "origin/HEAD...HEAD";
/// Local default-branch fallbacks when `origin/HEAD` is missing.
/// Three-dot form matches the origin probe (merge-base of that
/// branch and HEAD → HEAD). Own argv slots.
pub const git_committed_range_main = "main...HEAD";
pub const git_committed_range_master = "master...HEAD";
/// Two-dot infix for LastTurn start…end. Own argv slot —
/// never interpolated into `-c`. `git diff A..B` is the tree
/// of A vs the tree of B (same as `git diff A B`).
pub const git_last_turn_start_end_dots = "..";
/// Three-dot suffix for LastTurn rewind fallback. Own argv slot
/// together with the 40-char send-time rewind sha — never
/// interpolated into `-c`. Snapshot LastTurn uses the bare 40-hex.
pub const git_last_turn_range_suffix = "...HEAD";
/// Exact rewind operand length: `40-hex...HEAD`.
pub const last_turn_rewind_range_len: usize = rewind.stored_sha_len + git_last_turn_range_suffix.len;
/// Exact start…end operand length: `40-hex..40-hex`.
pub const last_turn_start_end_range_len: usize = rewind.stored_sha_len + git_last_turn_start_end_dots.len + rewind.stored_sha_len;
/// Max LastTurn operand: `40-hex..40-hex` (also holds
/// `40-hex...HEAD` and bare `40-hex`). Stored on the model
/// when LastTurn starts.
pub const last_turn_range_len: usize = last_turn_start_end_range_len;
/// Own argv slot before the path. Never interpolated into `-c`.
pub const git_pathspec_end = "--";
/// Documented `git diff --no-index` (implies `--exit-code`).
/// Own argv slot. Untracked `?` hunks only.
pub const git_no_index = "--no-index";
/// POSIX empty left side for `--no-index`. Own argv slot.
/// Never interpolated into `-c`.
pub const git_dev_null = "/dev/null";
pub const sh_bin = "/bin/sh";

/// Packed into one `-c` string so Uncommitted stays under Native
/// `max_effect_argv` (16). Real `git diff --name-status HEAD`
/// first; then synthetic `?\tpath` rows for every non-empty
/// `git ls-files --others --exclude-standard` path. Non-zero
/// from the diff exits without inventing untracked.
pub const uncommitted_untracked_script =
    \\git diff --name-status HEAD || exit $?
    \\git ls-files --others --exclude-standard 2>/dev/null | while IFS= read -r f || [ -n "$f" ]; do
    \\[ -z "$f" ] && continue
    \\printf '?\t%s\n' "$f"
    \\done
;

/// `/bin/sh -c` chdir + `git diff --name-status` + last-slot operand
/// (Branch / Staged / Committed / LastTurn). Unstaged omits the
/// operand. Uncommitted is chdir + nested `/bin/sh -c` + this script.
pub const argv_len: usize = 9;
/// Unstaged: same chdir prefix, no trailing operand.
pub const argv_len_unstaged: usize = 8;
/// Uncommitted: chdir + `/bin/sh -c` + `uncommitted_untracked_script`.
pub const argv_len_uncommitted: usize = 8;
/// Hunk with operand: chdir + `git diff <operand> -- <path>`.
pub const argv_len_hunk: usize = 10;
/// Unstaged hunk: chdir + `git diff -- <path>` (no operand).
pub const argv_len_hunk_unstaged: usize = 9;
/// Untracked `?` hunk: chdir + `git diff --no-index -- /dev/null <path>`.
pub const argv_len_hunk_untracked: usize = 11;
/// First-cut body cap. Extra stdout is dropped, not invented.
pub const max_review_diff_hunk_lines: usize = 160;
/// Enough for 160 short unified-diff lines. Longer lines still
/// fill this buffer and stop; the line cap also stops early.
pub const max_review_diff_hunk: usize = 8192;
pub const max_review_diff_hunk_status: usize = 32;

pub const comparing_status = "Comparing…";
pub const empty_status = "No changes to compare";
pub const failed_status = "Could not compare.";
pub const no_workspace_status = "No workspace.";
pub const hunk_empty_status = "No hunks";
pub const hunk_failed_status = "Could not show diff.";

/// Native `for each="review_diff_rows"` row. `id` is 1-based.
pub const ReviewDiffRow = struct {
    id: u32,
    label: []const u8,
    selected: bool = false,
};

pub const ChangedFile = struct {
    status: u8 = 0,
    path_storage: [max_review_diff_path]u8 = [_]u8{0} ** max_review_diff_path,
    path_len: usize = 0,
    label_storage: [max_review_diff_label]u8 = [_]u8{0} ** max_review_diff_label,
    label_len: usize = 0,

    pub fn path(self: *const ChangedFile) []const u8 {
        return self.path_storage[0..self.path_len];
    }

    pub fn label(self: *const ChangedFile) []const u8 {
        return self.label_storage[0..self.label_len];
    }

    pub fn set(self: *ChangedFile, status: u8, file_path: []const u8) void {
        self.status = status;
        writeFixed(&self.path_storage, &self.path_len, file_path);
        const written = std.fmt.bufPrint(&self.label_storage, "{c} {s}", .{ status, self.path() }) catch {
            self.label_len = 0;
            return;
        };
        self.label_len = written.len;
    }
};

/// Last argv slot for sources that have one. Unstaged is `null`
/// (`git diff --name-status` with no range / `--cached`).
/// Uncommitted is `null` (`HEAD` lives in the nested script).
/// Committed reads `committed_range` (default first probe is
/// `origin/HEAD...HEAD`). LastTurn reads the captured
/// `diff..end` / `start..end`, snapshot `40-hex`, or rewind
/// `<40-hex>...HEAD`.
pub fn lastOperand(source: Source, committed_range: CommittedRange) ?[]const u8 {
    return lastOperandRange(source, committed_range, "");
}

pub fn lastOperandRange(
    source: Source,
    committed_range: CommittedRange,
    last_turn_range: []const u8,
) ?[]const u8 {
    return switch (source) {
        .branch => git_upstream_range,
        .uncommitted => null,
        .staged => git_cached_flag,
        .unstaged => null,
        .committed => switch (committed_range) {
            .origin => git_committed_range,
            .main => git_committed_range_main,
            .master => git_committed_range_master,
        },
        .last_turn => if (isLastTurnRange(last_turn_range)) last_turn_range else null,
    };
}

/// Hunk operand for the current Review source. Uncommitted tracked
/// uses last-slot `HEAD` (name-status packs `HEAD` in the nested
/// script). Unstaged omits the operand. Committed reads the range
/// that already succeeded — no origin/HEAD fall-through on a
/// hunk click. LastTurn reuses the stored `diff..end` /
/// `start..end`, snapshot `40-hex`, or rewind `<sha>...HEAD`.
pub fn hunkOperand(source: Source, committed_range: CommittedRange) ?[]const u8 {
    return hunkOperandRange(source, committed_range, "");
}

pub fn hunkOperandRange(
    source: Source,
    committed_range: CommittedRange,
    last_turn_range: []const u8,
) ?[]const u8 {
    return switch (source) {
        .branch => git_upstream_range,
        .uncommitted => git_head,
        .staged => git_cached_flag,
        .unstaged => null,
        .committed => lastOperandRange(.committed, committed_range, last_turn_range),
        .last_turn => lastOperandRange(.last_turn, committed_range, last_turn_range),
    };
}

/// Format send-time rewind sha as `<40-hex>...HEAD`. Rejects
/// anything that is not a stored 40-char hex sha (including
/// `HEAD~1`). Snapshot LastTurn uses `formatLastTurnSnapshot`.
/// Start…end LastTurn uses `formatLastTurnStartEnd`.
pub fn formatLastTurnRange(sha: []const u8, dest: *[last_turn_range_len]u8) ?[]const u8 {
    if (!rewind.isStoredSha(sha)) return null;
    const written = std.fmt.bufPrint(dest, "{s}{s}", .{ sha, git_last_turn_range_suffix }) catch return null;
    if (!isLastTurnRewindRange(written)) return null;
    return written;
}

/// Format send-time start (or turn-diff base) and
/// finish-time end as `<40-hex>..<40-hex>` (two-dot).
/// Rejects `HEAD~1`, three-dot `start...end`, and any
/// non-40-hex side.
pub fn formatLastTurnStartEnd(start: []const u8, end: []const u8, dest: *[last_turn_range_len]u8) ?[]const u8 {
    if (!rewind.isStoredSha(start) or !rewind.isStoredSha(end)) return null;
    const written = std.fmt.bufPrint(dest, "{s}{s}{s}", .{ start, git_last_turn_start_end_dots, end }) catch return null;
    if (!isLastTurnStartEndRange(written)) return null;
    return written;
}

/// Format send-time worktree snapshot as a bare 40-hex (two-dot
/// `git diff <sha>`). Rejects `HEAD~1` and `...HEAD`.
pub fn formatLastTurnSnapshot(sha: []const u8, dest: *[last_turn_range_len]u8) ?[]const u8 {
    if (!rewind.isStoredSha(sha)) return null;
    if (sha.len > dest.len) return null;
    @memcpy(dest[0..sha.len], sha);
    if (!isLastTurnSnapshotRange(dest[0..sha.len])) return null;
    return dest[0..sha.len];
}

/// True for a bare 40-hex snapshot operand. Rejects `...HEAD`
/// and `HEAD~1`.
pub fn isLastTurnSnapshotRange(operand: []const u8) bool {
    return rewind.isStoredSha(operand);
}

/// True only for `<40-hex>..<40-hex>`. Rejects `...HEAD`,
/// three-dot `start...end`, `HEAD~1`, short hex, and any
/// interpolated `-c` string.
pub fn isLastTurnStartEndRange(operand: []const u8) bool {
    if (operand.len != last_turn_start_end_range_len) return false;
    const mid = rewind.stored_sha_len;
    if (!std.mem.eql(u8, operand[mid .. mid + git_last_turn_start_end_dots.len], git_last_turn_start_end_dots)) return false;
    return rewind.isStoredSha(operand[0..mid]) and rewind.isStoredSha(operand[mid + git_last_turn_start_end_dots.len ..]);
}

/// True only for `<40-hex>...HEAD`. Rejects `HEAD~1`, short
/// hex, start…end, and any interpolated `-c` string.
pub fn isLastTurnRewindRange(operand: []const u8) bool {
    if (operand.len != last_turn_rewind_range_len) return false;
    if (!std.mem.eql(u8, operand[rewind.stored_sha_len..], git_last_turn_range_suffix)) return false;
    return rewind.isStoredSha(operand[0..rewind.stored_sha_len]);
}

/// True for any LastTurn operand: `diff..end` /
/// `start..end`, snapshot `40-hex`, or rewind
/// `<40-hex>...HEAD`.
pub fn isLastTurnRange(operand: []const u8) bool {
    return isLastTurnStartEndRange(operand) or isLastTurnSnapshotRange(operand) or isLastTurnRewindRange(operand);
}

fn lastTurnRange(model: *const Model) []const u8 {
    return model.review_diff_last_turn_range_storage[0..model.review_diff_last_turn_range_len];
}

fn clearLastTurnRange(model: *Model) void {
    model.review_diff_last_turn_range_len = 0;
}

/// Capture the selected session's LastTurn operand.
/// Preference: valid turn-diff+end → `diff..end`; else
/// valid start+end → `start..end`; else valid start →
/// bare 40-hex; else latest rewind → `<sha>...HEAD`.
/// Returns false when none are 40-hex (do not spawn).
fn captureLastTurnRange(model: *Model) bool {
    clearLastTurnRange(model);
    const session = model.sessionById(model.selected) orelse return false;
    if (formatLastTurnStartEnd(
        session.worktreeTurnDiffSha(),
        session.worktreeTurnEndSha(),
        &model.review_diff_last_turn_range_storage,
    )) |written| {
        model.review_diff_last_turn_range_len = written.len;
        return true;
    }
    if (formatLastTurnStartEnd(
        session.worktreeSnapshotSha(),
        session.worktreeTurnEndSha(),
        &model.review_diff_last_turn_range_storage,
    )) |written| {
        model.review_diff_last_turn_range_len = written.len;
        return true;
    }
    if (formatLastTurnSnapshot(session.worktreeSnapshotSha(), &model.review_diff_last_turn_range_storage)) |written| {
        model.review_diff_last_turn_range_len = written.len;
        return true;
    }
    const sha = session.latestRewindSha() orelse return false;
    const written = formatLastTurnRange(sha, &model.review_diff_last_turn_range_storage) orelse return false;
    model.review_diff_last_turn_range_len = written.len;
    return true;
}

pub fn argvForSource(source: Source, cwd: []const u8, buf: *[argv_len][]const u8) []const []const u8 {
    return argvForSourceRange(source, .origin, cwd, buf);
}

pub fn argvForSourceRange(
    source: Source,
    committed_range: CommittedRange,
    cwd: []const u8,
    buf: *[argv_len][]const u8,
) []const []const u8 {
    return argvForSourceRangeWith(source, committed_range, "", cwd, buf);
}

/// LastTurn name-status: 9-slot chdir + `git diff --name-status`
/// + `diff..end` / `start..end`, snapshot `40-hex`, or rewind
/// `<sha>...HEAD`. Operand is one own argv slot.
pub fn argvForLastTurn(cwd: []const u8, last_turn_range: []const u8, buf: *[argv_len][]const u8) []const []const u8 {
    return argvForSourceRangeWith(.last_turn, .origin, last_turn_range, cwd, buf);
}

pub fn argvForSourceRangeWith(
    source: Source,
    committed_range: CommittedRange,
    last_turn_range: []const u8,
    cwd: []const u8,
    buf: *[argv_len][]const u8,
) []const []const u8 {
    buf[0] = sh_bin;
    buf[1] = "-c";
    buf[2] = main.fx_ask_chdir_script;
    buf[3] = "sh";
    buf[4] = cwd;
    if (source == .uncommitted) {
        buf[5] = sh_bin;
        buf[6] = "-c";
        buf[7] = uncommitted_untracked_script;
        return buf[0..argv_len_uncommitted];
    }
    buf[5] = git_bin;
    buf[6] = git_diff_cmd;
    buf[7] = git_name_status;
    if (lastOperandRange(source, committed_range, last_turn_range)) |operand| {
        buf[8] = operand;
        return buf[0..argv_len];
    }
    return buf[0..argv_len_unstaged];
}

/// `/bin/sh -c <chdir> sh <cwd> git diff [operand] -- <path>`.
/// `--` and the path are own argv slots. Never interpolate the
/// path into `-c`.
pub fn argvForHunk(
    source: Source,
    committed_range: CommittedRange,
    cwd: []const u8,
    path: []const u8,
    buf: *[argv_len_hunk][]const u8,
) []const []const u8 {
    return argvForHunkRange(source, committed_range, "", cwd, path, buf);
}

/// LastTurn hunk: same `diff..end` / `start..end`, snapshot
/// `40-hex`, or rewind `<sha>...HEAD` operand + `--` + path.
pub fn argvForHunkLastTurn(
    cwd: []const u8,
    last_turn_range: []const u8,
    path: []const u8,
    buf: *[argv_len_hunk][]const u8,
) []const []const u8 {
    return argvForHunkRange(.last_turn, .origin, last_turn_range, cwd, path, buf);
}

pub fn argvForHunkRange(
    source: Source,
    committed_range: CommittedRange,
    last_turn_range: []const u8,
    cwd: []const u8,
    path: []const u8,
    buf: *[argv_len_hunk][]const u8,
) []const []const u8 {
    buf[0] = sh_bin;
    buf[1] = "-c";
    buf[2] = main.fx_ask_chdir_script;
    buf[3] = "sh";
    buf[4] = cwd;
    buf[5] = git_bin;
    buf[6] = git_diff_cmd;
    if (hunkOperandRange(source, committed_range, last_turn_range)) |operand| {
        buf[7] = operand;
        buf[8] = git_pathspec_end;
        buf[9] = path;
        return buf[0..argv_len_hunk];
    }
    buf[7] = git_pathspec_end;
    buf[8] = path;
    return buf[0..argv_len_hunk_unstaged];
}

/// `/bin/sh -c <chdir> sh <cwd> git diff --no-index -- /dev/null <path>`.
/// `--no-index`, `--`, `/dev/null`, and the path are own argv slots.
/// Never interpolate the path (or `/dev/null`) into `-c`.
pub fn argvForUntrackedHunk(
    cwd: []const u8,
    path: []const u8,
    buf: *[argv_len_hunk_untracked][]const u8,
) []const []const u8 {
    buf[0] = sh_bin;
    buf[1] = "-c";
    buf[2] = main.fx_ask_chdir_script;
    buf[3] = "sh";
    buf[4] = cwd;
    buf[5] = git_bin;
    buf[6] = git_diff_cmd;
    buf[7] = git_no_index;
    buf[8] = git_pathspec_end;
    buf[9] = git_dev_null;
    buf[10] = path;
    return buf[0..argv_len_hunk_untracked];
}

/// Branch argv. `open` still uses this shape. Diff tab / header +/-
/// default to Uncommitted via `ensureDiff`.
pub fn argvFor(cwd: []const u8, buf: *[argv_len][]const u8) []const []const u8 {
    return argvForSource(.branch, cwd, buf);
}

pub fn isGitReviewUncommittedArgv(argv: []const []const u8) bool {
    if (argv.len != argv_len_uncommitted) return false;
    if (!std.mem.eql(u8, argv[0], sh_bin)) return false;
    if (!std.mem.eql(u8, argv[1], "-c")) return false;
    if (!std.mem.eql(u8, argv[2], main.fx_ask_chdir_script)) return false;
    if (!std.mem.eql(u8, argv[5], sh_bin)) return false;
    if (!std.mem.eql(u8, argv[6], "-c")) return false;
    return std.mem.eql(u8, argv[7], uncommitted_untracked_script);
}

pub fn isGitReviewDiffArgv(argv: []const []const u8) bool {
    if (isGitReviewUncommittedArgv(argv)) return true;
    if (argv.len != argv_len and argv.len != argv_len_unstaged) return false;
    if (!std.mem.eql(u8, argv[0], sh_bin)) return false;
    if (!std.mem.eql(u8, argv[1], "-c")) return false;
    if (!std.mem.eql(u8, argv[2], main.fx_ask_chdir_script)) return false;
    if (!std.mem.eql(u8, argv[5], git_bin)) return false;
    if (!std.mem.eql(u8, argv[6], git_diff_cmd)) return false;
    if (!std.mem.eql(u8, argv[7], git_name_status)) return false;
    if (argv.len == argv_len_unstaged) return true;
    const last = argv[8];
    return std.mem.eql(u8, last, git_upstream_range) or
        std.mem.eql(u8, last, git_cached_flag) or
        std.mem.eql(u8, last, git_committed_range) or
        std.mem.eql(u8, last, git_committed_range_main) or
        std.mem.eql(u8, last, git_committed_range_master) or
        isLastTurnRange(last);
}

fn isKnownHunkOperand(last: []const u8) bool {
    return std.mem.eql(u8, last, git_upstream_range) or
        std.mem.eql(u8, last, git_head) or
        std.mem.eql(u8, last, git_cached_flag) or
        std.mem.eql(u8, last, git_committed_range) or
        std.mem.eql(u8, last, git_committed_range_main) or
        std.mem.eql(u8, last, git_committed_range_master) or
        isLastTurnRange(last);
}

/// Hunk argv: chdir + `git diff [operand] -- <path>`, or the
/// 11-slot untracked `git diff --no-index -- /dev/null <path>`.
/// Rejects name-status (`--name-status`) and Uncommitted nested `sh -c`.
pub fn isGitReviewHunkArgv(argv: []const []const u8) bool {
    if (argv.len != argv_len_hunk and
        argv.len != argv_len_hunk_unstaged and
        argv.len != argv_len_hunk_untracked) return false;
    if (!std.mem.eql(u8, argv[0], sh_bin)) return false;
    if (!std.mem.eql(u8, argv[1], "-c")) return false;
    if (!std.mem.eql(u8, argv[2], main.fx_ask_chdir_script)) return false;
    if (!std.mem.eql(u8, argv[5], git_bin)) return false;
    if (!std.mem.eql(u8, argv[6], git_diff_cmd)) return false;
    if (argv.len == argv_len_hunk_untracked) {
        return std.mem.eql(u8, argv[7], git_no_index) and
            std.mem.eql(u8, argv[8], git_pathspec_end) and
            std.mem.eql(u8, argv[9], git_dev_null);
    }
    if (argv.len == argv_len_hunk_unstaged) {
        return std.mem.eql(u8, argv[7], git_pathspec_end);
    }
    return isKnownHunkOperand(argv[7]) and std.mem.eql(u8, argv[8], git_pathspec_end);
}

/// One `XY\tpath` or `R100\told\tnew` name-status row. Blank /
/// malformed lines are omitted. Rename/copy uses the destination
/// path; the status letter is the first ASCII letter (`R` / `C`).
pub fn parseNameStatusLine(raw: []const u8) ?struct { status: u8, path: []const u8 } {
    const line = std.mem.trim(u8, raw, " \t\r\n");
    if (line.len == 0) return null;
    const tab = std.mem.indexOfScalar(u8, line, '\t') orelse return null;
    const code = std.mem.trim(u8, line[0..tab], " \t");
    if (code.len == 0) return null;
    const status = statusLetter(code) orelse return null;
    var rest = std.mem.trim(u8, line[tab + 1 ..], " \t");
    if (rest.len == 0) return null;
    if (status == 'R' or status == 'C') {
        if (std.mem.indexOfScalar(u8, rest, '\t')) |second| {
            const dest = std.mem.trim(u8, rest[second + 1 ..], " \t");
            if (dest.len > 0) rest = dest;
        }
    }
    if (rest.len == 0) return null;
    return .{ .status = status, .path = rest };
}

fn statusLetter(code: []const u8) ?u8 {
    const first = code[0];
    if (first == '?') return '?';
    if (first < 'A' or first > 'Z') return null;
    return first;
}

pub fn reviewDiffStatus(model: *const Model) []const u8 {
    return model.review_diff_status_storage[0..model.review_diff_status_len];
}

pub fn hasReviewDiffStatus(model: *const Model) bool {
    return model.review_diff_status_len > 0;
}

pub fn hasReviewDiffFiles(model: *const Model) bool {
    return model.review_diff_file_count > 0;
}

pub fn reviewDiffRows(model: *const Model, arena: std.mem.Allocator) []const ReviewDiffRow {
    const n = model.review_diff_file_count;
    if (n == 0) return &.{};
    const out = arena.alloc(ReviewDiffRow, n) catch return &.{};
    for (model.review_diff_file_store[0..n], 0..) |*file, i| {
        out[i] = .{
            .id = @intCast(i + 1),
            .label = file.label(),
            .selected = model.review_diff_selected_id == i + 1,
        };
    }
    return out;
}

pub fn reviewDiffHunk(model: *const Model) []const u8 {
    return model.review_diff_hunk_storage[0..model.review_diff_hunk_len];
}

pub fn hasReviewDiffHunk(model: *const Model) bool {
    return model.review_diff_hunk_len > 0;
}

pub fn reviewDiffHunkStatus(model: *const Model) []const u8 {
    return model.review_diff_hunk_status_storage[0..model.review_diff_hunk_status_len];
}

pub fn hasReviewDiffHunkStatus(model: *const Model) bool {
    return model.review_diff_hunk_status_len > 0;
}

fn setStatus(model: *Model, text: []const u8) void {
    writeFixed(&model.review_diff_status_storage, &model.review_diff_status_len, text);
}

fn clearStatus(model: *Model) void {
    model.review_diff_status_len = 0;
}

fn clearFiles(model: *Model) void {
    model.review_diff_file_count = 0;
    for (&model.review_diff_file_store) |*file| {
        file.* = .{};
    }
}

fn setHunkStatus(model: *Model, text: []const u8) void {
    writeFixed(&model.review_diff_hunk_status_storage, &model.review_diff_hunk_status_len, text);
}

fn clearHunkStatus(model: *Model) void {
    model.review_diff_hunk_status_len = 0;
}

fn clearHunkBody(model: *Model) void {
    model.review_diff_hunk_len = 0;
    model.review_diff_hunk_line_count = 0;
}

fn clearHunks(model: *Model) void {
    clearHunkBody(model);
    clearHunkStatus(model);
    model.review_diff_selected_id = 0;
    model.review_diff_hunk_probe_session = 0;
    model.review_diff_hunk_probe_path_len = 0;
    model.review_diff_hunk_path_len = 0;
    model.review_diff_hunk_no_index = false;
}

fn cancelInFlight(model: *Model, fx: *Effects) void {
    if (model.review_diff_key == 0) return;
    fx.cancel(model.review_diff_key);
    model.review_diff_key = 0;
}

fn cancelHunkInFlight(model: *Model, fx: *Effects) void {
    if (model.review_diff_hunk_key == 0) return;
    fx.cancel(model.review_diff_hunk_key);
    model.review_diff_hunk_key = 0;
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

fn probeStillCurrent(model: *const Model) bool {
    if (model.review_diff_key == 0) return false;
    if (model.review_diff_probe_session != model.selected) return false;
    const path = model.selectedProjectPath();
    const probed = model.review_diff_probe_path_storage[0..model.review_diff_probe_path_len];
    return std.mem.eql(u8, path, probed);
}

fn appendParsed(model: *Model, raw: []const u8) void {
    var it = std.mem.splitScalar(u8, raw, '\n');
    while (it.next()) |line| {
        if (model.review_diff_file_count >= max_review_diff_files) return;
        const parsed = parseNameStatusLine(line) orelse continue;
        const slot = &model.review_diff_file_store[model.review_diff_file_count];
        slot.set(parsed.status, parsed.path);
        model.review_diff_file_count += 1;
    }
}

/// Cancel any in-flight probe, drop files / status / hunks, and close the card.
pub fn close(model: *Model, fx: *Effects) void {
    cancelInFlight(model, fx);
    cancelHunkInFlight(model, fx);
    clearFiles(model);
    clearStatus(model);
    clearHunks(model);
    model.review_diff_probe_session = 0;
    model.review_diff_probe_path_len = 0;
    model.review_diff_committed_range = .origin;
    clearLastTurnRange(model);
    model.review_diff_source = .branch;
    model.review_diff_active = false;
}

/// Esc / Cancel: same as close. Does not invent a fail status.
pub fn dismiss(model: *Model, fx: *Effects) void {
    close(model, fx);
}

fn prepareCard(model: *Model, fx: *Effects) void {
    git_checkout.closePicker(model);
    git_checkout.closeCreate(model);
    git_checkout.closeWorktreeCreate(model);
    git_checkout.closeDelete(model);
    model.closeProjectEdit();
    close(model, fx);
}

fn startProbe(model: *Model, fx: *Effects) void {
    cancelInFlight(model, fx);
    cancelHunkInFlight(model, fx);
    clearFiles(model);
    clearStatus(model);
    clearHunks(model);
    model.review_diff_probe_session = 0;
    model.review_diff_probe_path_len = 0;
    if (!probeSupported()) {
        setStatus(model, failed_status);
        return;
    }
    const cwd = probePath(model);
    if (cwd.len == 0) {
        setStatus(model, no_workspace_status);
        return;
    }
    if (model.review_diff_source == .last_turn) {
        if (!captureLastTurnRange(model)) {
            setStatus(model, failed_status);
            return;
        }
    } else {
        clearLastTurnRange(model);
    }

    const key = model.next_review_diff_key;
    model.next_review_diff_key = key + 1;
    model.review_diff_key = key;
    model.review_diff_probe_session = model.selected;
    writeFixed(&model.review_diff_probe_path_storage, &model.review_diff_probe_path_len, cwd);
    setStatus(model, comparing_status);

    var argv_buf: [argv_len][]const u8 = undefined;
    fx.spawn(.{
        .key = key,
        .argv = argvForSourceRangeWith(
            model.review_diff_source,
            model.review_diff_committed_range,
            lastTurnRange(model),
            cwd,
            &argv_buf,
        ),
        .on_line = Effects.lineMsg(.fx_line),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
}

/// Close other composer git cards, open the Review card on Branch,
/// and one-shot Branch name-status when cwd exists. Missing / Local
/// path still opens the card with `No workspace.` Streaming and
/// in-flight git mutations are a no-op (popover already closed).
/// Windows skips the spawn and leaves the card with the fail
/// status only when a workspace exists (no Windows spawn path).
/// Environment Compare / Diff tab use `ensureDiff` instead.
pub fn open(model: *Model, fx: *Effects) void {
    prepareCard(model, fx);
    if (git_checkout.gitMutationInFlight(model)) return;
    if (model.is_streaming()) return;
    model.review_diff_active = true;
    model.review_diff_source = .branch;
    startProbe(model, fx);
}

/// Diff tab / Environment Compare: start Uncommitted when no compare
/// is active; keep the current source and refresh when it is.
/// Same streaming / git-mutation gate as `open`.
pub fn ensureDiff(model: *Model, fx: *Effects) void {
    if (git_checkout.gitMutationInFlight(model)) return;
    if (model.is_streaming()) return;
    if (model.review_diff_active) {
        startProbe(model, fx);
        return;
    }
    prepareCard(model, fx);
    model.review_diff_active = true;
    model.review_diff_source = .uncommitted;
    startProbe(model, fx);
}

/// Switch the Review name-status source, cancel any in-flight
/// 510+ spawn, clear rows / status, and re-probe. Committed
/// always restarts at `origin/HEAD...HEAD` (no leftover
/// main/master retry). LastTurn captures the selected session's
/// start…end / send-time snapshot / rewind fallback or fails
/// without spawn (never HEAD~1).
/// No-op when the card is closed, unless the Diff tab is showing
/// (chips can restart Compare after Esc / Cancel).
pub fn setSource(model: *Model, fx: *Effects, source: Source) void {
    if (!model.review_diff_active) {
        if (!(model.right_panel_open and model.right_panel_tab == .diff)) return;
        if (git_checkout.gitMutationInFlight(model) or model.is_streaming()) return;
        model.review_diff_active = true;
    }
    model.review_diff_source = source;
    model.review_diff_committed_range = .origin;
    startProbe(model, fx);
}

fn hunkStillCurrent(model: *const Model) bool {
    if (model.review_diff_hunk_key == 0) return false;
    if (model.review_diff_hunk_probe_session != model.selected) return false;
    const path = model.selectedProjectPath();
    const probed = model.review_diff_hunk_probe_path_storage[0..model.review_diff_hunk_probe_path_len];
    return std.mem.eql(u8, path, probed);
}

fn startHunkProbe(model: *Model, fx: *Effects, file_path: []const u8, no_index: bool) void {
    cancelHunkInFlight(model, fx);
    clearHunkBody(model);
    clearHunkStatus(model);
    model.review_diff_hunk_probe_session = 0;
    model.review_diff_hunk_probe_path_len = 0;
    model.review_diff_hunk_path_len = 0;
    model.review_diff_hunk_no_index = false;
    if (!probeSupported()) {
        setHunkStatus(model, hunk_failed_status);
        return;
    }
    const cwd = probePath(model);
    if (cwd.len == 0) {
        setHunkStatus(model, hunk_failed_status);
        return;
    }

    writeFixed(&model.review_diff_hunk_path_storage, &model.review_diff_hunk_path_len, file_path);
    const path = model.review_diff_hunk_path_storage[0..model.review_diff_hunk_path_len];
    const key = model.next_review_diff_hunk_key;
    model.next_review_diff_hunk_key = key + 1;
    model.review_diff_hunk_key = key;
    model.review_diff_hunk_probe_session = model.selected;
    model.review_diff_hunk_no_index = no_index;
    writeFixed(&model.review_diff_hunk_probe_path_storage, &model.review_diff_hunk_probe_path_len, cwd);

    if (no_index) {
        var argv_buf: [argv_len_hunk_untracked][]const u8 = undefined;
        fx.spawn(.{
            .key = key,
            .argv = argvForUntrackedHunk(cwd, path, &argv_buf),
            .on_line = Effects.lineMsg(.fx_line),
            .on_exit = Effects.exitMsg(.fx_exit),
        });
        return;
    }
    var argv_buf: [argv_len_hunk][]const u8 = undefined;
    fx.spawn(.{
        .key = key,
        .argv = argvForHunkRange(
            model.review_diff_source,
            model.review_diff_committed_range,
            lastTurnRange(model),
            cwd,
            path,
            &argv_buf,
        ),
        .on_line = Effects.lineMsg(.fx_line),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
}

/// Click a 1-based Review file row. Tracked rows one-shot a hunk
/// probe for the current source (`argvForHunk`). Untracked `?`
/// one-shots `git diff --no-index -- /dev/null <path>`. Cancels
/// any in-flight hunk and clears the previous body.
pub fn selectFile(model: *Model, fx: *Effects, id: u32) void {
    if (!model.review_diff_active) return;
    if (id == 0 or id > model.review_diff_file_count) return;
    const file = &model.review_diff_file_store[id - 1];
    cancelHunkInFlight(model, fx);
    clearHunkBody(model);
    clearHunkStatus(model);
    model.review_diff_selected_id = id;
    const no_index = file.status == '?' and model.review_diff_source != .last_turn;
    startHunkProbe(model, fx, file.path(), no_index);
}

pub fn applyLine(model: *Model, line: native_sdk.EffectLine) void {
    if (line.key != model.review_diff_key or model.review_diff_key == 0) return;
    if (!probeStillCurrent(model)) return;
    if (!model.review_diff_active) return;
    appendParsed(model, line.line);
}

pub fn handleExit(model: *Model, fx: *Effects, exit: native_sdk.EffectExit) void {
    if (exit.key != model.review_diff_key or model.review_diff_key == 0) return;
    const current = probeStillCurrent(model);
    model.review_diff_key = 0;
    if (!model.review_diff_active) {
        clearFiles(model);
        clearStatus(model);
        return;
    }
    if (!current) {
        clearFiles(model);
        setStatus(model, failed_status);
        return;
    }
    if (exit.reason != .exited or exit.code != 0) {
        if (startCommittedFallback(model, fx)) return;
        clearFiles(model);
        setStatus(model, failed_status);
        return;
    }
    if (model.review_diff_file_count == 0) {
        setStatus(model, empty_status);
        return;
    }
    clearStatus(model);
}

pub fn applyHunkLine(model: *Model, line: native_sdk.EffectLine) void {
    if (line.key != model.review_diff_hunk_key or model.review_diff_hunk_key == 0) return;
    if (!hunkStillCurrent(model)) return;
    if (!model.review_diff_active) return;
    appendHunkLine(model, line.line);
}

fn appendHunkLine(model: *Model, raw: []const u8) void {
    if (model.review_diff_hunk_line_count >= max_review_diff_hunk_lines) return;
    const line = std.mem.trimEnd(u8, raw, "\r\n");
    var used = model.review_diff_hunk_len;
    const dest = model.review_diff_hunk_storage[0..];
    if (used > 0) {
        if (used >= dest.len) return;
        dest[used] = '\n';
        used += 1;
    }
    if (used >= dest.len) return;
    const take = @min(dest.len - used, line.len);
    @memcpy(dest[used .. used + take], line[0..take]);
    model.review_diff_hunk_len = used + take;
    model.review_diff_hunk_line_count += 1;
}

pub fn handleHunkExit(model: *Model, fx: *Effects, exit: native_sdk.EffectExit) void {
    _ = fx;
    if (exit.key != model.review_diff_hunk_key or model.review_diff_hunk_key == 0) return;
    const current = hunkStillCurrent(model);
    model.review_diff_hunk_key = 0;
    if (!model.review_diff_active) {
        clearHunkBody(model);
        clearHunkStatus(model);
        return;
    }
    if (!current) {
        clearHunkBody(model);
        setHunkStatus(model, hunk_failed_status);
        return;
    }
    const ok = if (model.review_diff_hunk_no_index)
        exit.reason == .exited and (exit.code == 0 or exit.code == 1)
    else
        exit.reason == .exited and exit.code == 0;
    if (!ok) {
        clearHunkBody(model);
        setHunkStatus(model, hunk_failed_status);
        return;
    }
    if (model.review_diff_hunk_len == 0) {
        setHunkStatus(model, hunk_empty_status);
        return;
    }
    clearHunkStatus(model);
}

/// Still-current Committed non-zero exit: retry `main...HEAD`,
/// then `master...HEAD`. Keeps `Comparing…` (no flashed fail).
/// Returns false when this was not a Committed probe or both
/// local fallbacks already failed.
fn startCommittedFallback(model: *Model, fx: *Effects) bool {
    if (model.review_diff_source != .committed) return false;
    const next: CommittedRange = switch (model.review_diff_committed_range) {
        .origin => .main,
        .main => .master,
        .master => return false,
    };
    model.review_diff_committed_range = next;
    startProbe(model, fx);
    return true;
}

test "argv is chdir script plus git diff --name-status @{upstream}...HEAD" {
    const git_branch = @import("git_branch.zig");
    const git_dirty = @import("git_dirty.zig");
    const git_numstat = @import("git_numstat.zig");
    const file_mention = @import("file_mention.zig");
    var buf: [argv_len][]const u8 = undefined;
    const argv = argvFor("/tmp/faku-review", &buf);
    try std.testing.expectEqual(@as(usize, 9), argv.len);
    try std.testing.expectEqualStrings(sh_bin, argv[0]);
    try std.testing.expectEqualStrings("-c", argv[1]);
    try std.testing.expectEqualStrings(main.fx_ask_chdir_script, argv[2]);
    try std.testing.expectEqualStrings("sh", argv[3]);
    try std.testing.expectEqualStrings("/tmp/faku-review", argv[4]);
    try std.testing.expectEqualStrings(git_bin, argv[5]);
    try std.testing.expectEqualStrings(git_diff_cmd, argv[6]);
    try std.testing.expectEqualStrings(git_name_status, argv[7]);
    try std.testing.expectEqualStrings(git_upstream_range, argv[8]);
    try std.testing.expectEqualStrings("@{upstream}...HEAD", argv[8]);
    try std.testing.expect(isGitReviewDiffArgv(argv));
    try std.testing.expect(std.mem.indexOf(u8, argv[2], git_upstream_range) == null);
    try std.testing.expect(std.mem.indexOf(u8, argv[2], git_name_status) == null);
    try std.testing.expect(std.mem.indexOf(u8, argv[2], git_diff_cmd) == null);
    try std.testing.expect(std.mem.indexOf(u8, argv[2], git_head) == null);
    try std.testing.expect(!isGitReviewDiffArgv(&.{ git_bin, git_diff_cmd, git_name_status, git_upstream_range }));
    var uncommitted_buf: [argv_len][]const u8 = undefined;
    const uncommitted = argvForSource(.uncommitted, "/tmp/faku-review", &uncommitted_buf);
    try std.testing.expectEqual(argv_len_uncommitted, uncommitted.len);
    try std.testing.expectEqualStrings(sh_bin, uncommitted[0]);
    try std.testing.expectEqualStrings("-c", uncommitted[1]);
    try std.testing.expectEqualStrings(main.fx_ask_chdir_script, uncommitted[2]);
    try std.testing.expectEqualStrings("sh", uncommitted[3]);
    try std.testing.expectEqualStrings("/tmp/faku-review", uncommitted[4]);
    try std.testing.expectEqualStrings(sh_bin, uncommitted[5]);
    try std.testing.expectEqualStrings("-c", uncommitted[6]);
    try std.testing.expectEqualStrings(uncommitted_untracked_script, uncommitted[7]);
    try std.testing.expect(lastOperand(.uncommitted, .origin) == null);
    try std.testing.expect(isGitReviewUncommittedArgv(uncommitted));
    try std.testing.expect(isGitReviewDiffArgv(uncommitted));
    try std.testing.expect(std.mem.indexOf(u8, uncommitted[2], git_head) == null);
    try std.testing.expect(std.mem.indexOf(u8, uncommitted[2], git_name_status) == null);
    try std.testing.expect(std.mem.indexOf(u8, uncommitted[2], uncommitted_untracked_script) == null);
    try std.testing.expect(scriptHas(uncommitted[7], git_diff_cmd));
    try std.testing.expect(scriptHas(uncommitted[7], git_name_status));
    try std.testing.expect(scriptHas(uncommitted[7], git_head));
    try std.testing.expect(scriptHas(uncommitted[7], git_ls_files_cmd));
    try std.testing.expect(scriptHas(uncommitted[7], git_ls_files_others));
    try std.testing.expect(scriptHas(uncommitted[7], git_ls_files_exclude_standard));
    try std.testing.expect(scriptHas(uncommitted[7], "?\\t"));
    try std.testing.expect(!isGitReviewDiffArgv(&.{ git_bin, git_diff_cmd, git_name_status, git_head }));
    try std.testing.expect(!isGitReviewUncommittedArgv(&.{
        sh_bin,
        "-c",
        main.fx_ask_chdir_script,
        "sh",
        "/tmp/faku-review",
        git_bin,
        git_diff_cmd,
        git_name_status,
        git_head,
    }));
    try std.testing.expect(!isGitReviewDiffArgv(&.{
        sh_bin,
        "-c",
        main.fx_ask_chdir_script,
        "sh",
        "/tmp/faku-review",
        git_bin,
        git_diff_cmd,
        git_name_status,
        git_head,
    }));
    var staged_buf: [argv_len][]const u8 = undefined;
    const staged = argvForSource(.staged, "/tmp/faku-review", &staged_buf);
    try std.testing.expectEqual(@as(usize, 9), staged.len);
    try std.testing.expectEqualStrings(sh_bin, staged[0]);
    try std.testing.expectEqualStrings("-c", staged[1]);
    try std.testing.expectEqualStrings(main.fx_ask_chdir_script, staged[2]);
    try std.testing.expectEqualStrings("sh", staged[3]);
    try std.testing.expectEqualStrings("/tmp/faku-review", staged[4]);
    try std.testing.expectEqualStrings(git_bin, staged[5]);
    try std.testing.expectEqualStrings(git_diff_cmd, staged[6]);
    try std.testing.expectEqualStrings(git_name_status, staged[7]);
    try std.testing.expectEqualStrings(git_cached_flag, staged[8]);
    try std.testing.expectEqualStrings("--cached", staged[8]);
    try std.testing.expectEqualStrings(@import("git_commit.zig").git_cached_flag, staged[8]);
    try std.testing.expect(isGitReviewDiffArgv(staged));
    try std.testing.expect(std.mem.indexOf(u8, staged[2], git_cached_flag) == null);
    try std.testing.expect(std.mem.indexOf(u8, staged[2], git_name_status) == null);
    try std.testing.expect(!isGitReviewDiffArgv(&.{ git_bin, git_diff_cmd, git_name_status, git_cached_flag }));
    var unstaged_buf: [argv_len][]const u8 = undefined;
    const unstaged = argvForSource(.unstaged, "/tmp/faku-review", &unstaged_buf);
    try std.testing.expectEqual(@as(usize, 8), unstaged.len);
    try std.testing.expectEqual(argv_len_unstaged, unstaged.len);
    try std.testing.expectEqualStrings(sh_bin, unstaged[0]);
    try std.testing.expectEqualStrings("-c", unstaged[1]);
    try std.testing.expectEqualStrings(main.fx_ask_chdir_script, unstaged[2]);
    try std.testing.expectEqualStrings("sh", unstaged[3]);
    try std.testing.expectEqualStrings("/tmp/faku-review", unstaged[4]);
    try std.testing.expectEqualStrings(git_bin, unstaged[5]);
    try std.testing.expectEqualStrings(git_diff_cmd, unstaged[6]);
    try std.testing.expectEqualStrings(git_name_status, unstaged[7]);
    try std.testing.expect(lastOperand(.unstaged, .origin) == null);
    try std.testing.expect(isGitReviewDiffArgv(unstaged));
    try std.testing.expect(std.mem.indexOf(u8, unstaged[2], git_name_status) == null);
    try std.testing.expect(std.mem.indexOf(u8, unstaged[2], git_diff_cmd) == null);
    try std.testing.expect(std.mem.indexOf(u8, unstaged[2], "/tmp/faku-review") == null);
    try std.testing.expect(!isGitReviewDiffArgv(&.{ git_bin, git_diff_cmd, git_name_status }));
    var committed_buf: [argv_len][]const u8 = undefined;
    const committed = argvForSource(.committed, "/tmp/faku-review", &committed_buf);
    try std.testing.expectEqual(@as(usize, 9), committed.len);
    try std.testing.expectEqual(argv_len, committed.len);
    try std.testing.expectEqualStrings(sh_bin, committed[0]);
    try std.testing.expectEqualStrings("-c", committed[1]);
    try std.testing.expectEqualStrings(main.fx_ask_chdir_script, committed[2]);
    try std.testing.expectEqualStrings("sh", committed[3]);
    try std.testing.expectEqualStrings("/tmp/faku-review", committed[4]);
    try std.testing.expectEqualStrings(git_bin, committed[5]);
    try std.testing.expectEqualStrings(git_diff_cmd, committed[6]);
    try std.testing.expectEqualStrings(git_name_status, committed[7]);
    try std.testing.expectEqualStrings(git_committed_range, committed[8]);
    try std.testing.expectEqualStrings("origin/HEAD...HEAD", committed[8]);
    try std.testing.expect(lastOperand(.committed, .origin) != null);
    try std.testing.expectEqualStrings(git_committed_range, lastOperand(.committed, .origin).?);
    try std.testing.expectEqualStrings("origin/HEAD...HEAD", lastOperand(.committed, .origin).?);
    try std.testing.expectEqualStrings(git_committed_range_main, lastOperand(.committed, .main).?);
    try std.testing.expectEqualStrings("main...HEAD", lastOperand(.committed, .main).?);
    try std.testing.expectEqualStrings(git_committed_range_master, lastOperand(.committed, .master).?);
    try std.testing.expectEqualStrings("master...HEAD", lastOperand(.committed, .master).?);
    try std.testing.expect(isGitReviewDiffArgv(committed));
    try std.testing.expect(std.mem.indexOf(u8, committed[2], git_committed_range) == null);
    try std.testing.expect(std.mem.indexOf(u8, committed[2], git_name_status) == null);
    try std.testing.expect(std.mem.indexOf(u8, committed[2], git_upstream_range) == null);
    try std.testing.expect(!isGitReviewDiffArgv(&.{ git_bin, git_diff_cmd, git_name_status, git_committed_range }));
    var committed_main_buf: [argv_len][]const u8 = undefined;
    const committed_main = argvForSourceRange(.committed, .main, "/tmp/faku-review", &committed_main_buf);
    try std.testing.expectEqual(@as(usize, 9), committed_main.len);
    try std.testing.expectEqualStrings(git_committed_range_main, committed_main[8]);
    try std.testing.expect(isGitReviewDiffArgv(committed_main));
    try std.testing.expect(std.mem.indexOf(u8, committed_main[2], git_committed_range_main) == null);
    try std.testing.expect(!isGitReviewDiffArgv(&.{ git_bin, git_diff_cmd, git_name_status, git_committed_range_main }));
    var committed_master_buf: [argv_len][]const u8 = undefined;
    const committed_master = argvForSourceRange(.committed, .master, "/tmp/faku-review", &committed_master_buf);
    try std.testing.expectEqualStrings(git_committed_range_master, committed_master[8]);
    try std.testing.expect(isGitReviewDiffArgv(committed_master));
    try std.testing.expect(std.mem.indexOf(u8, committed_master[2], git_committed_range_master) == null);
    try std.testing.expect(!isGitReviewDiffArgv(&.{ git_bin, git_diff_cmd, git_name_status, git_committed_range_master }));
    var interpolated_main = committed_main_buf;
    interpolated_main[2] = "cd \"$1\" && git diff --name-status main...HEAD";
    interpolated_main[8] = git_committed_range_main;
    try std.testing.expect(!isGitReviewDiffArgv(interpolated_main[0..argv_len]));
    const last_turn_sha = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    var last_turn_range_buf: [last_turn_range_len]u8 = undefined;
    const last_turn_range = formatLastTurnRange(last_turn_sha, &last_turn_range_buf) orelse return error.MissingLastTurnRange;
    try std.testing.expectEqualStrings("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa...HEAD", last_turn_range);
    try std.testing.expect(isLastTurnRange(last_turn_range));
    try std.testing.expect(isLastTurnRewindRange(last_turn_range));
    try std.testing.expect(!isLastTurnSnapshotRange(last_turn_range));
    try std.testing.expect(!isLastTurnRange("HEAD~1"));
    try std.testing.expect(!isLastTurnRange("HEAD~1...HEAD"));
    var last_turn_snap_buf: [last_turn_range_len]u8 = undefined;
    const last_turn_snap = formatLastTurnSnapshot(last_turn_sha, &last_turn_snap_buf) orelse return error.MissingLastTurnSnapshot;
    try std.testing.expectEqualStrings(last_turn_sha, last_turn_snap);
    try std.testing.expect(isLastTurnRange(last_turn_snap));
    try std.testing.expect(isLastTurnSnapshotRange(last_turn_snap));
    try std.testing.expect(!isLastTurnRewindRange(last_turn_snap));
    try std.testing.expect(formatLastTurnSnapshot("HEAD~1", &last_turn_snap_buf) == null);
    try std.testing.expectEqual(last_turn_start_end_range_len, last_turn_range_len);
    try std.testing.expectEqual(@as(usize, 82), last_turn_range_len);
    try std.testing.expectEqual(@as(usize, 47), last_turn_rewind_range_len);
    try std.testing.expectEqualStrings("..", git_last_turn_start_end_dots);
    try std.testing.expectEqualStrings("...HEAD", git_last_turn_range_suffix);
    const last_turn_end_sha = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    var last_turn_start_end_buf: [last_turn_range_len]u8 = undefined;
    const last_turn_start_end = formatLastTurnStartEnd(last_turn_sha, last_turn_end_sha, &last_turn_start_end_buf) orelse return error.MissingLastTurnStartEnd;
    try std.testing.expectEqualStrings("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa..bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", last_turn_start_end);
    try std.testing.expectEqual(@as(usize, 82), last_turn_start_end.len);
    try std.testing.expect(std.mem.indexOf(u8, last_turn_start_end, "...") == null);
    try std.testing.expect(isLastTurnRange(last_turn_start_end));
    try std.testing.expect(isLastTurnStartEndRange(last_turn_start_end));
    try std.testing.expect(!isLastTurnSnapshotRange(last_turn_start_end));
    try std.testing.expect(!isLastTurnRewindRange(last_turn_start_end));
    try std.testing.expect(!isLastTurnStartEndRange(last_turn_range));
    try std.testing.expect(!isLastTurnStartEndRange(last_turn_snap));
    try std.testing.expect(!isLastTurnStartEndRange("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa...bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"));
    try std.testing.expect(!isLastTurnRange("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa...bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"));
    try std.testing.expect(formatLastTurnStartEnd("HEAD~1", last_turn_end_sha, &last_turn_start_end_buf) == null);
    try std.testing.expect(formatLastTurnStartEnd(last_turn_sha, "HEAD~1", &last_turn_start_end_buf) == null);
    try std.testing.expect(formatLastTurnStartEnd(last_turn_sha, "", &last_turn_start_end_buf) == null);
    try std.testing.expect(lastOperandRange(.last_turn, .origin, last_turn_start_end) != null);
    try std.testing.expectEqualStrings(last_turn_start_end, lastOperandRange(.last_turn, .origin, last_turn_start_end).?);
    try std.testing.expect(lastOperandRange(.last_turn, .origin, last_turn_range) != null);
    try std.testing.expectEqualStrings(last_turn_range, lastOperandRange(.last_turn, .origin, last_turn_range).?);
    try std.testing.expect(lastOperand(.last_turn, .origin) == null);
    var last_turn_buf: [argv_len][]const u8 = undefined;
    const last_turn = argvForLastTurn("/tmp/faku-review", last_turn_range, &last_turn_buf);
    try std.testing.expectEqual(@as(usize, 9), last_turn.len);
    try std.testing.expectEqual(argv_len, last_turn.len);
    try std.testing.expectEqualStrings(sh_bin, last_turn[0]);
    try std.testing.expectEqualStrings("-c", last_turn[1]);
    try std.testing.expectEqualStrings(main.fx_ask_chdir_script, last_turn[2]);
    try std.testing.expectEqualStrings("sh", last_turn[3]);
    try std.testing.expectEqualStrings("/tmp/faku-review", last_turn[4]);
    try std.testing.expectEqualStrings(git_bin, last_turn[5]);
    try std.testing.expectEqualStrings(git_diff_cmd, last_turn[6]);
    try std.testing.expectEqualStrings(git_name_status, last_turn[7]);
    try std.testing.expectEqualStrings(last_turn_range, last_turn[8]);
    try std.testing.expectEqualStrings("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa...HEAD", last_turn[8]);
    try std.testing.expect(isGitReviewDiffArgv(last_turn));
    var last_turn_two_dot_buf: [argv_len][]const u8 = undefined;
    const last_turn_two_dot = argvForLastTurn("/tmp/faku-review", last_turn_snap, &last_turn_two_dot_buf);
    try std.testing.expectEqual(argv_len, last_turn_two_dot.len);
    try std.testing.expectEqualStrings(last_turn_sha, last_turn_two_dot[8]);
    try std.testing.expect(std.mem.indexOf(u8, last_turn_two_dot[8], git_last_turn_range_suffix) == null);
    try std.testing.expect(isGitReviewDiffArgv(last_turn_two_dot));
    var last_turn_start_end_argv_buf: [argv_len][]const u8 = undefined;
    const last_turn_start_end_argv = argvForLastTurn("/tmp/faku-review", last_turn_start_end, &last_turn_start_end_argv_buf);
    try std.testing.expectEqual(argv_len, last_turn_start_end_argv.len);
    try std.testing.expectEqualStrings(last_turn_start_end, last_turn_start_end_argv[8]);
    try std.testing.expectEqualStrings("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa..bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", last_turn_start_end_argv[8]);
    try std.testing.expectEqual(@as(usize, 82), last_turn_start_end_argv[8].len);
    try std.testing.expect(std.mem.indexOf(u8, last_turn_start_end_argv[8], "...") == null);
    try std.testing.expect(isGitReviewDiffArgv(last_turn_start_end_argv));
    try std.testing.expect(std.mem.indexOf(u8, last_turn_start_end_argv[2], last_turn_sha) == null);
    try std.testing.expect(std.mem.indexOf(u8, last_turn_start_end_argv[2], last_turn_end_sha) == null);
    try std.testing.expect(std.mem.indexOf(u8, last_turn_start_end_argv[2], last_turn_start_end) == null);
    try std.testing.expect(std.mem.indexOf(u8, last_turn_two_dot[2], last_turn_sha) == null);
    try std.testing.expect(std.mem.indexOf(u8, last_turn[2], last_turn_sha) == null);
    try std.testing.expect(std.mem.indexOf(u8, last_turn[2], last_turn_range) == null);
    try std.testing.expect(std.mem.indexOf(u8, last_turn[2], git_last_turn_range_suffix) == null);
    try std.testing.expect(std.mem.indexOf(u8, last_turn[2], "HEAD~1") == null);
    try std.testing.expect(!isGitReviewDiffArgv(&.{ git_bin, git_diff_cmd, git_name_status, last_turn_range }));
    const head_tilde = [_][]const u8{
        sh_bin,
        "-c",
        main.fx_ask_chdir_script,
        "sh",
        "/tmp/faku-review",
        git_bin,
        git_diff_cmd,
        git_name_status,
        "HEAD~1",
    };
    try std.testing.expect(!isGitReviewDiffArgv(&head_tilde));
    var interpolated_last_turn = last_turn_buf;
    interpolated_last_turn[2] = "cd \"$1\" && git diff --name-status aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa...HEAD";
    interpolated_last_turn[8] = last_turn_range;
    try std.testing.expect(!isGitReviewDiffArgv(interpolated_last_turn[0..argv_len]));
    var ahead_buf: [git_ahead_behind.argv_len][]const u8 = undefined;
    const ahead = git_ahead_behind.argvFor("/tmp/faku-review", &ahead_buf);
    try std.testing.expect(!isGitReviewDiffArgv(ahead));
    try std.testing.expect(!git_ahead_behind.isGitAheadBehindArgv(argv));
    var branch_buf: [8][]const u8 = undefined;
    const branch = git_branch.argvFor("/tmp/faku-review", &branch_buf);
    try std.testing.expect(!isGitReviewDiffArgv(branch));
    var dirty_buf: [8][]const u8 = undefined;
    const dirty = git_dirty.argvFor("/tmp/faku-review", &dirty_buf);
    try std.testing.expect(!isGitReviewDiffArgv(dirty));
    var numstat_buf: [git_numstat.argv_len][]const u8 = undefined;
    const numstat = git_numstat.unixArgvFor("/tmp/faku-review", &numstat_buf);
    try std.testing.expect(!isGitReviewDiffArgv(numstat));
    try std.testing.expect(!isGitReviewUncommittedArgv(numstat));
    try std.testing.expect(!git_numstat.isGitNumstatArgv(argv));
    try std.testing.expect(!git_numstat.isGitNumstatArgv(uncommitted));
    try std.testing.expect(!file_mention.isGitLsFilesArgv(argv));
    try std.testing.expect(!file_mention.isGitLsFilesArgv(uncommitted));
    try std.testing.expect(review_diff_key_first >= 510);
    try std.testing.expect(review_diff_key_first > git_common_dir.git_common_dir_key_first);
    try std.testing.expect(git_common_dir.git_common_dir_key_first >= 500);
    try std.testing.expect(review_diff_hunk_key_first >= 520);
    try std.testing.expect(review_diff_hunk_key_first > review_diff_key_first);
    try std.testing.expect(argv_len_hunk_untracked == 11);
    try std.testing.expect(argv_len_hunk_untracked < 16);
    try std.testing.expect(argv_len_hunk == 10);
    try std.testing.expect(argv_len_hunk_unstaged == 9);
}

test "parseNameStatusLine is status letter plus path; rename uses dest" {
    try std.testing.expectEqualStrings("src/a.zig", parseNameStatusLine("M\tsrc/a.zig\n").?.path);
    try std.testing.expectEqual(@as(u8, 'M'), parseNameStatusLine("M\tsrc/a.zig\n").?.status);
    try std.testing.expectEqual(@as(u8, 'A'), parseNameStatusLine("A\tnew.txt").?.status);
    try std.testing.expectEqualStrings("new.txt", parseNameStatusLine("A\tnew.txt").?.path);
    try std.testing.expectEqual(@as(u8, 'D'), parseNameStatusLine("D\tgone.txt\n").?.status);
    try std.testing.expectEqual(@as(u8, 'T'), parseNameStatusLine("T\tmode.txt").?.status);
    try std.testing.expectEqual(@as(u8, 'R'), parseNameStatusLine("R100\told.txt\tnew.txt\n").?.status);
    try std.testing.expectEqualStrings("new.txt", parseNameStatusLine("R100\told.txt\tnew.txt\n").?.path);
    try std.testing.expectEqual(@as(u8, 'C'), parseNameStatusLine("C80\ta.txt\tb.txt").?.status);
    try std.testing.expectEqualStrings("b.txt", parseNameStatusLine("C80\ta.txt\tb.txt").?.path);
    try std.testing.expectEqualStrings("only-dest", parseNameStatusLine("R\tonly-dest").?.path);
    try std.testing.expectEqual(@as(u8, '?'), parseNameStatusLine("?\tnew.txt").?.status);
    try std.testing.expectEqualStrings("new.txt", parseNameStatusLine("?\tnew.txt").?.path);
    try std.testing.expectEqual(@as(u8, '?'), parseNameStatusLine("??\tuntracked.txt\n").?.status);
    try std.testing.expectEqualStrings("untracked.txt", parseNameStatusLine("??\tuntracked.txt\n").?.path);
    try std.testing.expect(parseNameStatusLine("?\t") == null);
    try std.testing.expect(parseNameStatusLine("?") == null);
    try std.testing.expect(parseNameStatusLine("") == null);
    try std.testing.expect(parseNameStatusLine("   \n") == null);
    try std.testing.expect(parseNameStatusLine("not-status") == null);
    try std.testing.expect(parseNameStatusLine("M") == null);
    try std.testing.expect(parseNameStatusLine("M\t") == null);
    try std.testing.expect(parseNameStatusLine("1\tbad.txt") == null);
}

test "Uncommitted argv is nested sh -c; old HEAD-only argv is not Review" {
    var buf: [argv_len][]const u8 = undefined;
    const argv = argvForSource(.uncommitted, "/tmp/faku-uncommitted", &buf);
    try std.testing.expectEqual(argv_len_uncommitted, argv.len);
    try std.testing.expectEqualStrings(sh_bin, argv[5]);
    try std.testing.expectEqualStrings("-c", argv[6]);
    try std.testing.expectEqualStrings(uncommitted_untracked_script, argv[7]);
    try std.testing.expect(isGitReviewUncommittedArgv(argv));
    try std.testing.expect(isGitReviewDiffArgv(argv));
    try std.testing.expect(lastOperand(.uncommitted, .origin) == null);
    try std.testing.expect(scriptHas(argv[7], "git diff --name-status HEAD"));
    try std.testing.expect(scriptHas(argv[7], "git ls-files --others --exclude-standard"));
    try std.testing.expect(scriptHas(argv[7], "|| exit $?"));
    try std.testing.expect(std.mem.indexOf(u8, argv[2], git_head) == null);
    const old_head = [_][]const u8{
        sh_bin,
        "-c",
        main.fx_ask_chdir_script,
        "sh",
        "/tmp/faku-uncommitted",
        git_bin,
        git_diff_cmd,
        git_name_status,
        git_head,
    };
    try std.testing.expect(!isGitReviewUncommittedArgv(&old_head));
    try std.testing.expect(!isGitReviewDiffArgv(&old_head));
    var unstaged_buf: [argv_len][]const u8 = undefined;
    const unstaged = argvForSource(.unstaged, "/tmp/faku-uncommitted", &unstaged_buf);
    try std.testing.expect(!isGitReviewUncommittedArgv(unstaged));
    try std.testing.expect(isGitReviewDiffArgv(unstaged));
}

test "open closes nothing extra when gated; missing cwd is No workspace" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    const id = model.addSession("review gate", .fx);
    model.selected = id;
    open(&model, &fx);
    try std.testing.expect(model.review_diff_active);
    try std.testing.expectEqual(Source.branch, model.review_diff_source);
    try std.testing.expectEqualStrings(no_workspace_status, reviewDiffStatus(&model));
    try std.testing.expectEqual(@as(u32, 0), model.review_diff_file_count);
    try std.testing.expectEqual(@as(u64, 0), model.review_diff_key);

    close(&model, &fx);
    try std.testing.expect(!model.review_diff_active);
    try std.testing.expectEqual(Source.branch, model.review_diff_source);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/review-gate", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);
    model.store_io = std.testing.io;
    if (model.sessionById(id)) |session| session.setProjectPath(project);

    model.phase = .streaming;
    open(&model, &fx);
    try std.testing.expect(!model.review_diff_active);
    model.phase = .idle;

    model.git_push_key = git_checkout.git_push_key_first;
    open(&model, &fx);
    try std.testing.expect(!model.review_diff_active);
    try std.testing.expect(git_checkout.gitMutationInFlight(&model));
}

test "name-status lines fill capped rows; empty and fail stay honest" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/review-lines", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("review lines", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);

    open(&model, &fx);
    try std.testing.expect(model.review_diff_active);
    try std.testing.expectEqual(Source.branch, model.review_diff_source);
    try std.testing.expect(model.review_diff_key >= review_diff_key_first);
    try std.testing.expectEqualStrings(comparing_status, reviewDiffStatus(&model));

    const key = model.review_diff_key;
    applyLine(&model, .{ .key = key, .line = "M\tsrc/a.zig\nA\tnew.txt\n" });
    applyLine(&model, .{ .key = key, .line = "D\tgone.txt\nR100\told.txt\trenamed.txt\n" });
    try std.testing.expectEqual(@as(u32, 4), model.review_diff_file_count);
    try std.testing.expectEqualStrings("M src/a.zig", model.review_diff_file_store[0].label());
    try std.testing.expectEqualStrings("A new.txt", model.review_diff_file_store[1].label());
    try std.testing.expectEqualStrings("D gone.txt", model.review_diff_file_store[2].label());
    try std.testing.expectEqualStrings("R renamed.txt", model.review_diff_file_store[3].label());

    handleExit(&model, &fx, .{ .key = key, .reason = .exited, .code = 0 });
    try std.testing.expect(model.review_diff_active);
    try std.testing.expectEqual(@as(u64, 0), model.review_diff_key);
    try std.testing.expect(!hasReviewDiffStatus(&model));
    try std.testing.expect(hasReviewDiffFiles(&model));

    open(&model, &fx);
    const empty_key = model.review_diff_key;
    handleExit(&model, &fx, .{ .key = empty_key, .reason = .exited, .code = 0 });
    try std.testing.expectEqual(@as(u32, 0), model.review_diff_file_count);
    try std.testing.expectEqualStrings(empty_status, reviewDiffStatus(&model));

    open(&model, &fx);
    const fail_key = model.review_diff_key;
    applyLine(&model, .{ .key = fail_key, .line = "M\tshould-drop.zig\n" });
    handleExit(&model, &fx, .{ .key = fail_key, .reason = .exited, .code = 128 });
    try std.testing.expectEqual(@as(u32, 0), model.review_diff_file_count);
    try std.testing.expectEqualStrings(failed_status, reviewDiffStatus(&model));
    try std.testing.expect(model.review_diff_active);

    dismiss(&model, &fx);
    try std.testing.expect(!model.review_diff_active);
    try std.testing.expectEqual(Source.branch, model.review_diff_source);
    try std.testing.expectEqual(@as(u32, 0), model.review_diff_file_count);
}

test "source switch cancels in-flight Branch and re-probes Staged Uncommitted Unstaged Committed" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/review-source", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("review source", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);

    open(&model, &fx);
    try std.testing.expectEqual(Source.branch, model.review_diff_source);
    const branch_key = model.review_diff_key;
    var i: usize = 0;
    var branch_argv: ?[]const []const u8 = null;
    while (fx.pendingSpawnAt(i)) |spawn| : (i += 1) {
        if (spawn.key == branch_key) branch_argv = spawn.argv;
    }
    try std.testing.expect(isGitReviewDiffArgv(branch_argv orelse return error.MissingBranchArgv));
    try std.testing.expectEqualStrings(git_upstream_range, branch_argv.?[8]);
    applyLine(&model, .{ .key = branch_key, .line = "M\tbranch-only.zig\n" });
    try std.testing.expectEqual(@as(u32, 1), model.review_diff_file_count);

    setSource(&model, &fx, .staged);
    try std.testing.expect(model.review_diff_active);
    try std.testing.expectEqual(Source.staged, model.review_diff_source);
    try std.testing.expect(model.review_diff_key != branch_key);
    try std.testing.expect(model.review_diff_key >= review_diff_key_first);
    try std.testing.expectEqual(@as(u32, 0), model.review_diff_file_count);
    try std.testing.expectEqualStrings(comparing_status, reviewDiffStatus(&model));

    applyLine(&model, .{ .key = branch_key, .line = "A\tshould-ignore.txt\n" });
    try std.testing.expectEqual(@as(u32, 0), model.review_diff_file_count);
    handleExit(&model, &fx, .{ .key = branch_key, .reason = .exited, .code = 0 });
    try std.testing.expectEqual(Source.staged, model.review_diff_source);
    try std.testing.expectEqualStrings(comparing_status, reviewDiffStatus(&model));

    const staged_key = model.review_diff_key;
    i = 0;
    var staged_argv: ?[]const []const u8 = null;
    while (fx.pendingSpawnAt(i)) |spawn| : (i += 1) {
        if (spawn.key == staged_key) staged_argv = spawn.argv;
    }
    try std.testing.expect(isGitReviewDiffArgv(staged_argv orelse return error.MissingStagedArgv));
    try std.testing.expectEqualStrings(git_cached_flag, staged_argv.?[8]);
    try std.testing.expect(std.mem.indexOf(u8, staged_argv.?[2], git_cached_flag) == null);
    applyLine(&model, .{ .key = staged_key, .line = "A\tstaged.zig\n" });
    handleExit(&model, &fx, .{ .key = staged_key, .reason = .exited, .code = 0 });
    try std.testing.expectEqual(@as(u32, 1), model.review_diff_file_count);
    try std.testing.expectEqualStrings("A staged.zig", model.review_diff_file_store[0].label());
    try std.testing.expect(!hasReviewDiffStatus(&model));

    setSource(&model, &fx, .uncommitted);
    try std.testing.expect(model.review_diff_active);
    try std.testing.expectEqual(Source.uncommitted, model.review_diff_source);
    try std.testing.expect(model.review_diff_key != staged_key);
    try std.testing.expectEqual(@as(u32, 0), model.review_diff_file_count);
    try std.testing.expectEqualStrings(comparing_status, reviewDiffStatus(&model));

    applyLine(&model, .{ .key = staged_key, .line = "M\tshould-ignore-staged.zig\n" });
    try std.testing.expectEqual(@as(u32, 0), model.review_diff_file_count);
    handleExit(&model, &fx, .{ .key = staged_key, .reason = .exited, .code = 0 });
    try std.testing.expectEqual(Source.uncommitted, model.review_diff_source);
    try std.testing.expectEqualStrings(comparing_status, reviewDiffStatus(&model));

    const uncommitted_key = model.review_diff_key;
    i = 0;
    var uncommitted_argv: ?[]const []const u8 = null;
    while (fx.pendingSpawnAt(i)) |spawn| : (i += 1) {
        if (spawn.key == uncommitted_key) uncommitted_argv = spawn.argv;
    }
    try std.testing.expect(isGitReviewDiffArgv(uncommitted_argv orelse return error.MissingUncommittedArgv));
    try std.testing.expect(isGitReviewUncommittedArgv(uncommitted_argv.?));
    try std.testing.expectEqual(argv_len_uncommitted, uncommitted_argv.?.len);
    try std.testing.expectEqualStrings(uncommitted_untracked_script, uncommitted_argv.?[7]);
    try std.testing.expect(std.mem.indexOf(u8, uncommitted_argv.?[2], git_head) == null);
    try std.testing.expect(std.mem.indexOf(u8, uncommitted_argv.?[2], uncommitted_untracked_script) == null);
    applyLine(&model, .{ .key = uncommitted_key, .line = "M\ttracked.zig\n?\tnew.txt\n" });
    handleExit(&model, &fx, .{ .key = uncommitted_key, .reason = .exited, .code = 0 });
    try std.testing.expectEqual(@as(u32, 2), model.review_diff_file_count);
    try std.testing.expectEqualStrings("M tracked.zig", model.review_diff_file_store[0].label());
    try std.testing.expectEqualStrings("? new.txt", model.review_diff_file_store[1].label());
    try std.testing.expect(!hasReviewDiffStatus(&model));

    setSource(&model, &fx, .unstaged);
    try std.testing.expect(model.review_diff_active);
    try std.testing.expectEqual(Source.unstaged, model.review_diff_source);
    try std.testing.expect(model.review_diff_key != uncommitted_key);
    try std.testing.expectEqual(@as(u32, 0), model.review_diff_file_count);
    try std.testing.expectEqualStrings(comparing_status, reviewDiffStatus(&model));

    applyLine(&model, .{ .key = uncommitted_key, .line = "M\tshould-ignore-uncommitted.zig\n" });
    try std.testing.expectEqual(@as(u32, 0), model.review_diff_file_count);
    handleExit(&model, &fx, .{ .key = uncommitted_key, .reason = .exited, .code = 0 });
    try std.testing.expectEqual(Source.unstaged, model.review_diff_source);
    try std.testing.expectEqualStrings(comparing_status, reviewDiffStatus(&model));

    const unstaged_key = model.review_diff_key;
    i = 0;
    var unstaged_argv: ?[]const []const u8 = null;
    while (fx.pendingSpawnAt(i)) |spawn| : (i += 1) {
        if (spawn.key == unstaged_key) unstaged_argv = spawn.argv;
    }
    try std.testing.expect(isGitReviewDiffArgv(unstaged_argv orelse return error.MissingUnstagedArgv));
    try std.testing.expectEqual(argv_len_unstaged, unstaged_argv.?.len);
    try std.testing.expectEqualStrings(git_name_status, unstaged_argv.?[7]);
    try std.testing.expect(std.mem.indexOf(u8, unstaged_argv.?[2], git_name_status) == null);
    try std.testing.expect(std.mem.indexOf(u8, unstaged_argv.?[2], git_head) == null);
    try std.testing.expect(std.mem.indexOf(u8, unstaged_argv.?[2], git_cached_flag) == null);
    applyLine(&model, .{ .key = unstaged_key, .line = "M\tunstaged.zig\n" });
    handleExit(&model, &fx, .{ .key = unstaged_key, .reason = .exited, .code = 0 });
    try std.testing.expectEqual(@as(u32, 1), model.review_diff_file_count);
    try std.testing.expectEqualStrings("M unstaged.zig", model.review_diff_file_store[0].label());
    try std.testing.expect(!hasReviewDiffStatus(&model));

    setSource(&model, &fx, .committed);
    try std.testing.expect(model.review_diff_active);
    try std.testing.expectEqual(Source.committed, model.review_diff_source);
    try std.testing.expect(model.review_diff_key != unstaged_key);
    try std.testing.expectEqual(@as(u32, 0), model.review_diff_file_count);
    try std.testing.expectEqualStrings(comparing_status, reviewDiffStatus(&model));

    applyLine(&model, .{ .key = unstaged_key, .line = "M\tshould-ignore-unstaged.zig\n" });
    try std.testing.expectEqual(@as(u32, 0), model.review_diff_file_count);
    handleExit(&model, &fx, .{ .key = unstaged_key, .reason = .exited, .code = 0 });
    try std.testing.expectEqual(Source.committed, model.review_diff_source);
    try std.testing.expectEqualStrings(comparing_status, reviewDiffStatus(&model));

    const committed_key = model.review_diff_key;
    i = 0;
    var committed_argv: ?[]const []const u8 = null;
    while (fx.pendingSpawnAt(i)) |spawn| : (i += 1) {
        if (spawn.key == committed_key) committed_argv = spawn.argv;
    }
    try std.testing.expect(isGitReviewDiffArgv(committed_argv orelse return error.MissingCommittedArgv));
    try std.testing.expectEqual(argv_len, committed_argv.?.len);
    try std.testing.expectEqualStrings(git_committed_range, committed_argv.?[8]);
    try std.testing.expectEqualStrings("origin/HEAD...HEAD", committed_argv.?[8]);
    try std.testing.expect(std.mem.indexOf(u8, committed_argv.?[2], git_committed_range) == null);
    try std.testing.expect(std.mem.indexOf(u8, committed_argv.?[2], git_upstream_range) == null);
    applyLine(&model, .{ .key = committed_key, .line = "M\tcommitted.zig\n" });
    handleExit(&model, &fx, .{ .key = committed_key, .reason = .exited, .code = 0 });
    try std.testing.expectEqual(@as(u32, 1), model.review_diff_file_count);
    try std.testing.expectEqualStrings("M committed.zig", model.review_diff_file_store[0].label());
    try std.testing.expect(!hasReviewDiffStatus(&model));

    setSource(&model, &fx, .branch);
    try std.testing.expectEqual(Source.branch, model.review_diff_source);
    try std.testing.expect(model.review_diff_key != committed_key);
    try std.testing.expectEqual(@as(u32, 0), model.review_diff_file_count);
    try std.testing.expectEqualStrings(comparing_status, reviewDiffStatus(&model));

    const back_key = model.review_diff_key;
    i = 0;
    var back_argv: ?[]const []const u8 = null;
    while (fx.pendingSpawnAt(i)) |spawn| : (i += 1) {
        if (spawn.key == back_key) back_argv = spawn.argv;
    }
    try std.testing.expect(isGitReviewDiffArgv(back_argv orelse return error.MissingBranchBackArgv));
    try std.testing.expectEqualStrings(git_upstream_range, back_argv.?[8]);
    try std.testing.expectEqualStrings("@{upstream}...HEAD", back_argv.?[8]);

    handleExit(&model, &fx, .{ .key = back_key, .reason = .exited, .code = 0 });
    try std.testing.expectEqualStrings(empty_status, reviewDiffStatus(&model));

    setSource(&model, &fx, .committed);
    try std.testing.expectEqual(CommittedRange.origin, model.review_diff_committed_range);
    const fail_key = model.review_diff_key;
    handleExit(&model, &fx, .{ .key = fail_key, .reason = .exited, .code = 128 });
    try std.testing.expectEqualStrings(comparing_status, reviewDiffStatus(&model));
    try std.testing.expectEqual(Source.committed, model.review_diff_source);
    try std.testing.expectEqual(CommittedRange.main, model.review_diff_committed_range);
    try std.testing.expect(model.review_diff_key != fail_key);
    try std.testing.expect(model.review_diff_key >= review_diff_key_first);

    dismiss(&model, &fx);
    try std.testing.expect(!model.review_diff_active);
    try std.testing.expectEqual(Source.branch, model.review_diff_source);

    setSource(&model, &fx, .committed);
    try std.testing.expect(!model.review_diff_active);
    try std.testing.expectEqual(Source.branch, model.review_diff_source);
}

fn scriptHas(script: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, script, needle) != null;
}

fn findSpawnArgv(fx: *Effects, key: u64) ?[]const []const u8 {
    var i: usize = 0;
    while (fx.pendingSpawnAt(i)) |spawn| : (i += 1) {
        if (spawn.key == key) return spawn.argv;
    }
    return null;
}

test "Committed missing origin/HEAD retries main then master; zero-file origin stays empty" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/review-committed-fallback", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("review committed fallback", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);

    open(&model, &fx);
    setSource(&model, &fx, .committed);
    try std.testing.expectEqual(Source.committed, model.review_diff_source);
    try std.testing.expectEqual(CommittedRange.origin, model.review_diff_committed_range);
    const origin_key = model.review_diff_key;
    const origin_argv = findSpawnArgv(&fx, origin_key) orelse return error.MissingOriginArgv;
    try std.testing.expect(isGitReviewDiffArgv(origin_argv));
    try std.testing.expectEqualStrings(git_committed_range, origin_argv[8]);
    try std.testing.expectEqualStrings("origin/HEAD...HEAD", origin_argv[8]);
    try std.testing.expect(std.mem.indexOf(u8, origin_argv[2], git_committed_range) == null);

    handleExit(&model, &fx, .{ .key = origin_key, .reason = .exited, .code = 128 });
    try std.testing.expect(model.review_diff_active);
    try std.testing.expectEqual(Source.committed, model.review_diff_source);
    try std.testing.expectEqual(CommittedRange.main, model.review_diff_committed_range);
    try std.testing.expectEqualStrings(comparing_status, reviewDiffStatus(&model));
    try std.testing.expect(model.review_diff_key != origin_key);
    try std.testing.expect(model.review_diff_key >= review_diff_key_first);
    try std.testing.expectEqual(@as(u32, 0), model.review_diff_file_count);
    const main_key = model.review_diff_key;
    const main_argv = findSpawnArgv(&fx, main_key) orelse return error.MissingMainArgv;
    try std.testing.expect(isGitReviewDiffArgv(main_argv));
    try std.testing.expectEqual(argv_len, main_argv.len);
    try std.testing.expectEqualStrings(git_committed_range_main, main_argv[8]);
    try std.testing.expectEqualStrings("main...HEAD", main_argv[8]);
    try std.testing.expect(std.mem.indexOf(u8, main_argv[2], git_committed_range_main) == null);

    handleExit(&model, &fx, .{ .key = main_key, .reason = .exited, .code = 128 });
    try std.testing.expectEqual(Source.committed, model.review_diff_source);
    try std.testing.expectEqual(CommittedRange.master, model.review_diff_committed_range);
    try std.testing.expectEqualStrings(comparing_status, reviewDiffStatus(&model));
    try std.testing.expect(model.review_diff_key != main_key);
    const master_key = model.review_diff_key;
    const master_argv = findSpawnArgv(&fx, master_key) orelse return error.MissingMasterArgv;
    try std.testing.expect(isGitReviewDiffArgv(master_argv));
    try std.testing.expectEqualStrings(git_committed_range_master, master_argv[8]);
    try std.testing.expectEqualStrings("master...HEAD", master_argv[8]);
    try std.testing.expect(std.mem.indexOf(u8, master_argv[2], git_committed_range_master) == null);

    handleExit(&model, &fx, .{ .key = master_key, .reason = .exited, .code = 128 });
    try std.testing.expectEqualStrings(failed_status, reviewDiffStatus(&model));
    try std.testing.expectEqual(Source.committed, model.review_diff_source);
    try std.testing.expectEqual(CommittedRange.master, model.review_diff_committed_range);
    try std.testing.expectEqual(@as(u64, 0), model.review_diff_key);
    try std.testing.expectEqual(@as(u32, 0), model.review_diff_file_count);

    setSource(&model, &fx, .committed);
    try std.testing.expectEqual(CommittedRange.origin, model.review_diff_committed_range);
    try std.testing.expectEqualStrings(comparing_status, reviewDiffStatus(&model));
    const empty_origin_key = model.review_diff_key;
    const empty_origin_argv = findSpawnArgv(&fx, empty_origin_key) orelse return error.MissingEmptyOriginArgv;
    try std.testing.expectEqualStrings(git_committed_range, empty_origin_argv[8]);
    handleExit(&model, &fx, .{ .key = empty_origin_key, .reason = .exited, .code = 0 });
    try std.testing.expectEqualStrings(empty_status, reviewDiffStatus(&model));
    try std.testing.expectEqual(CommittedRange.origin, model.review_diff_committed_range);
    try std.testing.expectEqual(@as(u64, 0), model.review_diff_key);
    try std.testing.expectEqual(@as(u32, 0), model.review_diff_file_count);
}

test "Committed fallback does not hang after source switch or close" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/review-committed-cancel", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("review committed cancel", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);

    open(&model, &fx);
    setSource(&model, &fx, .committed);
    const origin_key = model.review_diff_key;
    handleExit(&model, &fx, .{ .key = origin_key, .reason = .exited, .code = 128 });
    try std.testing.expectEqual(CommittedRange.main, model.review_diff_committed_range);
    try std.testing.expectEqualStrings(comparing_status, reviewDiffStatus(&model));
    const main_key = model.review_diff_key;
    const main_argv = findSpawnArgv(&fx, main_key) orelse return error.MissingMainBeforeSwitch;
    try std.testing.expectEqualStrings(git_committed_range_main, main_argv[8]);

    setSource(&model, &fx, .branch);
    try std.testing.expectEqual(Source.branch, model.review_diff_source);
    try std.testing.expectEqual(CommittedRange.origin, model.review_diff_committed_range);
    try std.testing.expectEqualStrings(comparing_status, reviewDiffStatus(&model));
    try std.testing.expect(model.review_diff_key != main_key);
    const branch_key = model.review_diff_key;
    const branch_argv = findSpawnArgv(&fx, branch_key) orelse return error.MissingBranchAfterSwitch;
    try std.testing.expectEqualStrings(git_upstream_range, branch_argv[8]);

    handleExit(&model, &fx, .{ .key = main_key, .reason = .exited, .code = 128 });
    try std.testing.expectEqual(Source.branch, model.review_diff_source);
    try std.testing.expectEqual(CommittedRange.origin, model.review_diff_committed_range);
    try std.testing.expectEqual(branch_key, model.review_diff_key);
    try std.testing.expectEqualStrings(comparing_status, reviewDiffStatus(&model));
    try std.testing.expect(findSpawnArgv(&fx, main_key + 1) == null or model.review_diff_key == branch_key);

    setSource(&model, &fx, .committed);
    const origin_again = model.review_diff_key;
    const origin_again_argv = findSpawnArgv(&fx, origin_again) orelse return error.MissingOriginReselect;
    try std.testing.expectEqual(CommittedRange.origin, model.review_diff_committed_range);
    try std.testing.expectEqualStrings(git_committed_range, origin_again_argv[8]);
    handleExit(&model, &fx, .{ .key = origin_again, .reason = .exited, .code = 128 });
    const main_again = model.review_diff_key;
    try std.testing.expectEqual(CommittedRange.main, model.review_diff_committed_range);

    close(&model, &fx);
    try std.testing.expect(!model.review_diff_active);
    try std.testing.expectEqual(Source.branch, model.review_diff_source);
    try std.testing.expectEqual(CommittedRange.origin, model.review_diff_committed_range);
    try std.testing.expectEqual(@as(u64, 0), model.review_diff_key);
    handleExit(&model, &fx, .{ .key = main_again, .reason = .exited, .code = 128 });
    try std.testing.expect(!model.review_diff_active);
    try std.testing.expectEqual(@as(u64, 0), model.review_diff_key);
    try std.testing.expectEqual(CommittedRange.origin, model.review_diff_committed_range);
}

test "setSource last_turn with rewind sha spawns Comparing; without sha does not spawn" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/review-last-turn", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("review last turn", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);

    const sha = "cccccccccccccccccccccccccccccccccccccccc";
    var range_buf: [last_turn_range_len]u8 = undefined;
    const range = formatLastTurnRange(sha, &range_buf) orelse return error.MissingLastTurnRange;
    try std.testing.expectEqualStrings("cccccccccccccccccccccccccccccccccccccccc...HEAD", range);

    open(&model, &fx);
    try std.testing.expectEqual(Source.branch, model.review_diff_source);
    const branch_key = model.review_diff_key;
    setSource(&model, &fx, .last_turn);
    try std.testing.expect(model.review_diff_active);
    try std.testing.expectEqual(Source.last_turn, model.review_diff_source);
    try std.testing.expectEqual(@as(u64, 0), model.review_diff_key);
    try std.testing.expectEqualStrings(failed_status, reviewDiffStatus(&model));
    try std.testing.expect(findSpawnArgv(&fx, branch_key + 1) == null);
    try std.testing.expect(std.mem.indexOf(u8, reviewDiffStatus(&model), "HEAD~1") == null);

    if (model.sessionById(id)) |session| {
        session.appendRewindRef(sha, rewind.recorded_ref, 1);
        try std.testing.expectEqualStrings(sha, session.latestRewindSha().?);
    }

    setSource(&model, &fx, .last_turn);
    try std.testing.expect(model.review_diff_active);
    try std.testing.expectEqual(Source.last_turn, model.review_diff_source);
    try std.testing.expect(model.review_diff_key != branch_key);
    try std.testing.expect(model.review_diff_key >= review_diff_key_first);
    try std.testing.expectEqualStrings(comparing_status, reviewDiffStatus(&model));
    const last_turn_key = model.review_diff_key;
    const last_turn_argv = findSpawnArgv(&fx, last_turn_key) orelse return error.MissingLastTurnArgv;
    try std.testing.expect(isGitReviewDiffArgv(last_turn_argv));
    try std.testing.expectEqual(argv_len, last_turn_argv.len);
    try std.testing.expectEqualStrings(range, last_turn_argv[8]);
    try std.testing.expectEqualStrings("cccccccccccccccccccccccccccccccccccccccc...HEAD", last_turn_argv[8]);
    try std.testing.expect(std.mem.indexOf(u8, last_turn_argv[2], sha) == null);
    try std.testing.expect(std.mem.indexOf(u8, last_turn_argv[2], "HEAD~1") == null);
    try std.testing.expectEqualStrings(range, lastTurnRange(&model));

    applyLine(&model, .{ .key = last_turn_key, .line = "M\tlast-turn.zig\n" });
    handleExit(&model, &fx, .{ .key = last_turn_key, .reason = .exited, .code = 0 });
    try std.testing.expectEqual(@as(u32, 1), model.review_diff_file_count);
    try std.testing.expectEqualStrings("M last-turn.zig", model.review_diff_file_store[0].label());
    try std.testing.expect(!hasReviewDiffStatus(&model));

    if (model.sessionById(id)) |session| {
        session.appendRewindRef("dddddddddddddddddddddddddddddddddddddddd", rewind.recorded_ref, 2);
    }
    selectFile(&model, &fx, 1);
    const hunk_key = model.review_diff_hunk_key;
    try std.testing.expect(hunk_key >= review_diff_hunk_key_first);
    const hunk_argv = findSpawnArgv(&fx, hunk_key) orelse return error.MissingLastTurnHunk;
    try std.testing.expect(isGitReviewHunkArgv(hunk_argv));
    try std.testing.expectEqualStrings(range, hunk_argv[7]);
    try std.testing.expectEqualStrings(git_pathspec_end, hunk_argv[8]);
    try std.testing.expectEqualStrings("last-turn.zig", hunk_argv[9]);
    try std.testing.expect(std.mem.indexOf(u8, hunk_argv[2], sha) == null);
    try std.testing.expect(std.mem.indexOf(u8, hunk_argv[7], "dddddddddddddddddddddddddddddddddddddddd") == null);

    handleHunkExit(&model, &fx, .{ .key = hunk_key, .reason = .exited, .code = 0 });
    setSource(&model, &fx, .last_turn);
    const fail_key = model.review_diff_key;
    handleExit(&model, &fx, .{ .key = fail_key, .reason = .exited, .code = 128 });
    try std.testing.expectEqualStrings(failed_status, reviewDiffStatus(&model));
    try std.testing.expectEqual(Source.last_turn, model.review_diff_source);
    try std.testing.expectEqual(CommittedRange.origin, model.review_diff_committed_range);
    try std.testing.expectEqual(@as(u64, 0), model.review_diff_key);
    try std.testing.expectEqual(@as(u32, 0), model.review_diff_file_count);

    setSource(&model, &fx, .committed);
    const origin_key = model.review_diff_key;
    handleExit(&model, &fx, .{ .key = origin_key, .reason = .exited, .code = 128 });
    try std.testing.expectEqual(CommittedRange.main, model.review_diff_committed_range);
    try std.testing.expectEqualStrings(comparing_status, reviewDiffStatus(&model));
    const main_key = model.review_diff_key;
    setSource(&model, &fx, .last_turn);
    try std.testing.expectEqual(Source.last_turn, model.review_diff_source);
    try std.testing.expectEqual(CommittedRange.origin, model.review_diff_committed_range);
    try std.testing.expect(model.review_diff_key != main_key);
    handleExit(&model, &fx, .{ .key = main_key, .reason = .exited, .code = 128 });
    try std.testing.expectEqual(Source.last_turn, model.review_diff_source);
    try std.testing.expectEqual(CommittedRange.origin, model.review_diff_committed_range);

    dismiss(&model, &fx);
    try std.testing.expect(!model.review_diff_active);
    try std.testing.expectEqual(Source.branch, model.review_diff_source);
    try std.testing.expectEqual(@as(usize, 0), model.review_diff_last_turn_range_len);
}

test "setSource last_turn with snapshot sha spawns two-dot; prefers snapshot over rewind" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/review-last-turn-snap", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("review last turn snap", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);

    const snap = "ffffffffffffffffffffffffffffffffffffffff";
    const rewind_sha = "cccccccccccccccccccccccccccccccccccccccc";
    var snap_buf: [last_turn_range_len]u8 = undefined;
    const snap_range = formatLastTurnSnapshot(snap, &snap_buf) orelse return error.MissingLastTurnSnapshot;

    open(&model, &fx);
    setSource(&model, &fx, .last_turn);
    try std.testing.expectEqual(@as(u64, 0), model.review_diff_key);
    try std.testing.expectEqualStrings(failed_status, reviewDiffStatus(&model));

    if (model.sessionById(id)) |session| {
        session.appendRewindRef(rewind_sha, rewind.recorded_ref, 1);
        session.setWorktreeSnapshotSha(snap);
    }

    setSource(&model, &fx, .last_turn);
    try std.testing.expectEqualStrings(comparing_status, reviewDiffStatus(&model));
    const last_turn_argv = findSpawnArgv(&fx, model.review_diff_key) orelse return error.MissingLastTurnSnapArgv;
    try std.testing.expect(isGitReviewDiffArgv(last_turn_argv));
    try std.testing.expectEqual(argv_len, last_turn_argv.len);
    try std.testing.expectEqualStrings(snap, last_turn_argv[8]);
    try std.testing.expectEqualStrings(snap_range, last_turn_argv[8]);
    try std.testing.expect(std.mem.indexOf(u8, last_turn_argv[8], git_last_turn_range_suffix) == null);
    try std.testing.expect(std.mem.indexOf(u8, last_turn_argv[2], snap) == null);
    try std.testing.expect(std.mem.indexOf(u8, last_turn_argv[2], rewind_sha) == null);
    try std.testing.expectEqualStrings(snap, lastTurnRange(&model));

    applyLine(&model, .{ .key = model.review_diff_key, .line = "M\tsnap.zig\n" });
    handleExit(&model, &fx, .{ .key = model.review_diff_key, .reason = .exited, .code = 0 });
    if (model.sessionById(id)) |session| {
        session.appendRewindRef("dddddddddddddddddddddddddddddddddddddddd", rewind.recorded_ref, 2);
        session.setWorktreeSnapshotSha("eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee");
    }
    selectFile(&model, &fx, 1);
    const hunk_argv = findSpawnArgv(&fx, model.review_diff_hunk_key) orelse return error.MissingLastTurnSnapHunk;
    try std.testing.expect(isGitReviewHunkArgv(hunk_argv));
    try std.testing.expectEqualStrings(snap, hunk_argv[7]);
    try std.testing.expectEqualStrings(git_pathspec_end, hunk_argv[8]);
    try std.testing.expectEqualStrings("snap.zig", hunk_argv[9]);
    try std.testing.expect(std.mem.indexOf(u8, hunk_argv[7], git_last_turn_range_suffix) == null);
}

test "setSource last_turn prefers start..end when both snapshots exist" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/review-last-turn-start-end", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("review last turn start end", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);

    const start = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    const end = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    const rewind_sha = "cccccccccccccccccccccccccccccccccccccccc";
    var range_buf: [last_turn_range_len]u8 = undefined;
    const range = formatLastTurnStartEnd(start, end, &range_buf) orelse return error.MissingLastTurnStartEndRange;
    try std.testing.expectEqualStrings("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa..bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", range);
    try std.testing.expectEqual(@as(usize, 82), range.len);
    try std.testing.expect(std.mem.indexOf(u8, range, "...") == null);

    open(&model, &fx);
    setSource(&model, &fx, .last_turn);
    try std.testing.expectEqual(@as(u64, 0), model.review_diff_key);
    try std.testing.expectEqualStrings(failed_status, reviewDiffStatus(&model));

    if (model.sessionById(id)) |session| {
        session.appendRewindRef(rewind_sha, rewind.recorded_ref, 1);
        session.setWorktreeSnapshotSha(start);
        session.setWorktreeTurnEndSha(end);
    }

    setSource(&model, &fx, .last_turn);
    try std.testing.expectEqualStrings(comparing_status, reviewDiffStatus(&model));
    const last_turn_argv = findSpawnArgv(&fx, model.review_diff_key) orelse return error.MissingLastTurnStartEndArgv;
    try std.testing.expect(isGitReviewDiffArgv(last_turn_argv));
    try std.testing.expectEqual(argv_len, last_turn_argv.len);
    try std.testing.expectEqualStrings(range, last_turn_argv[8]);
    try std.testing.expectEqualStrings("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa..bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", last_turn_argv[8]);
    try std.testing.expectEqual(@as(usize, 82), last_turn_argv[8].len);
    try std.testing.expect(std.mem.indexOf(u8, last_turn_argv[8], "...") == null);
    try std.testing.expect(std.mem.indexOf(u8, last_turn_argv[2], start) == null);
    try std.testing.expect(std.mem.indexOf(u8, last_turn_argv[2], end) == null);
    try std.testing.expect(std.mem.indexOf(u8, last_turn_argv[2], rewind_sha) == null);
    try std.testing.expectEqualStrings(range, lastTurnRange(&model));

    applyLine(&model, .{ .key = model.review_diff_key, .line = "M\tstart-end.zig\n" });
    handleExit(&model, &fx, .{ .key = model.review_diff_key, .reason = .exited, .code = 0 });
    if (model.sessionById(id)) |session| {
        session.appendRewindRef("dddddddddddddddddddddddddddddddddddddddd", rewind.recorded_ref, 2);
        session.setWorktreeSnapshotSha("eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee");
        session.setWorktreeTurnEndSha("ffffffffffffffffffffffffffffffffffffffff");
    }
    selectFile(&model, &fx, 1);
    const hunk_argv = findSpawnArgv(&fx, model.review_diff_hunk_key) orelse return error.MissingLastTurnStartEndHunk;
    try std.testing.expect(isGitReviewHunkArgv(hunk_argv));
    try std.testing.expectEqualStrings(range, hunk_argv[7]);
    try std.testing.expectEqualStrings(git_pathspec_end, hunk_argv[8]);
    try std.testing.expectEqualStrings("start-end.zig", hunk_argv[9]);
    try std.testing.expect(std.mem.indexOf(u8, hunk_argv[2], start) == null);
    try std.testing.expect(std.mem.indexOf(u8, hunk_argv[7], "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee") == null);
}

test "setSource last_turn prefers diff..end when turn-diff and turn-end exist" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/review-last-turn-diff-end", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("review last turn diff end", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);

    const start = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    const end = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    const diff = "cccccccccccccccccccccccccccccccccccccccc";
    const rewind_sha = "dddddddddddddddddddddddddddddddddddddddd";
    var range_buf: [last_turn_range_len]u8 = undefined;
    const range = formatLastTurnStartEnd(diff, end, &range_buf) orelse return error.MissingLastTurnDiffEndRange;
    try std.testing.expectEqualStrings("cccccccccccccccccccccccccccccccccccccccc..bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", range);

    open(&model, &fx);
    if (model.sessionById(id)) |session| {
        session.appendRewindRef(rewind_sha, rewind.recorded_ref, 1);
        session.setWorktreeSnapshotSha(start);
        session.setWorktreeTurnEndSha(end);
        session.setWorktreeTurnDiffSha(diff);
    }

    setSource(&model, &fx, .last_turn);
    try std.testing.expectEqualStrings(comparing_status, reviewDiffStatus(&model));
    const last_turn_argv = findSpawnArgv(&fx, model.review_diff_key) orelse return error.MissingLastTurnDiffEndArgv;
    try std.testing.expect(isGitReviewDiffArgv(last_turn_argv));
    try std.testing.expectEqual(argv_len, last_turn_argv.len);
    try std.testing.expectEqualStrings(range, last_turn_argv[8]);
    try std.testing.expect(std.mem.indexOf(u8, last_turn_argv[8], start) == null);
    try std.testing.expect(std.mem.indexOf(u8, last_turn_argv[2], diff) == null);
    try std.testing.expectEqualStrings(range, lastTurnRange(&model));

    applyLine(&model, .{ .key = model.review_diff_key, .line = "M\tdiff-end.zig\n" });
    handleExit(&model, &fx, .{ .key = model.review_diff_key, .reason = .exited, .code = 0 });
    if (model.sessionById(id)) |session| {
        session.setWorktreeSnapshotSha("eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee");
        session.setWorktreeTurnEndSha("ffffffffffffffffffffffffffffffffffffffff");
        session.setWorktreeTurnDiffSha("1111111111111111111111111111111111111111");
    }
    selectFile(&model, &fx, 1);
    const hunk_argv = findSpawnArgv(&fx, model.review_diff_hunk_key) orelse return error.MissingLastTurnDiffEndHunk;
    try std.testing.expect(isGitReviewHunkArgv(hunk_argv));
    try std.testing.expectEqualStrings(range, hunk_argv[7]);
    try std.testing.expectEqualStrings(git_pathspec_end, hunk_argv[8]);
    try std.testing.expectEqualStrings("diff-end.zig", hunk_argv[9]);
}

test "LastTurn start..end two-dot name-status is the edited path only" {
    const checkpoint = @import("checkpoint.zig");
    const testing = std.testing;
    const allocator = testing.allocator;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [256]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, ".zig-cache/tmp/{s}/last-turn-two-dot", .{tmp.sub_path[0..]});
    const head = try initLastTurnRepo(allocator, testing.io, path);
    defer allocator.free(head);

    var start_buf: [rewind.stored_sha_len]u8 = undefined;
    const start = checkpoint.captureTurnStartCommit(allocator, testing.io, path, &start_buf) orelse return error.MissingTurnStart;
    try testing.expect(rewind.isStoredSha(start));

    try writeLastTurnFile(testing.io, path, "keep-a.txt", "edited\n");

    var end_buf: [rewind.stored_sha_len]u8 = undefined;
    const end = checkpoint.captureWorktreeCommit(allocator, testing.io, path, &end_buf) orelse return error.MissingTurnEnd;
    try testing.expect(rewind.isStoredSha(end));
    try testing.expect(!std.mem.eql(u8, start, end));

    var range_buf: [last_turn_range_len]u8 = undefined;
    const range = formatLastTurnStartEnd(start, end, &range_buf) orelse return error.MissingLastTurnTwoDot;
    try testing.expectEqual(last_turn_start_end_range_len, range.len);
    try testing.expectEqual(@as(usize, 82), range.len);
    try testing.expect(isLastTurnStartEndRange(range));
    try testing.expect(std.mem.startsWith(u8, range, start));
    try testing.expect(std.mem.endsWith(u8, range, end));
    try testing.expectEqualStrings("..", range[rewind.stored_sha_len .. rewind.stored_sha_len + git_last_turn_start_end_dots.len]);
    try testing.expect(std.mem.indexOf(u8, range, "...") == null);
    try testing.expect(std.mem.indexOf(u8, range, git_last_turn_range_suffix) == null);

    var three_buf: [rewind.stored_sha_len + 3 + rewind.stored_sha_len]u8 = undefined;
    const three = try std.fmt.bufPrint(&three_buf, "{s}...{s}", .{ start, end });
    try testing.expectEqual(@as(usize, 83), three.len);
    try testing.expect(!isLastTurnStartEndRange(three));
    try testing.expect(!isLastTurnRange(three));

    var argv_buf: [argv_len][]const u8 = undefined;
    const argv = argvForLastTurn(path, range, &argv_buf);
    try testing.expectEqual(argv_len, argv.len);
    try testing.expectEqualStrings(range, argv[8]);
    try testing.expect(isGitReviewDiffArgv(argv));
    try testing.expect(!std.mem.eql(u8, argv[8], three));
    try testing.expect(std.mem.indexOf(u8, argv[8], "...") == null);
    try testing.expect(std.mem.indexOf(u8, argv[2], range) == null);

    var hunk_buf: [argv_len_hunk][]const u8 = undefined;
    const hunk = argvForHunkLastTurn(path, range, "keep-a.txt", &hunk_buf);
    try testing.expectEqual(argv_len_hunk, hunk.len);
    try testing.expectEqualStrings(range, hunk[7]);
    try testing.expectEqualStrings(git_pathspec_end, hunk[8]);
    try testing.expectEqualStrings("keep-a.txt", hunk[9]);
    try testing.expect(isGitReviewHunkArgv(hunk));
    try testing.expect(!std.mem.eql(u8, hunk[7], three));

    const name_status = try runLastTurnGitCapture(allocator, testing.io, &.{
        "git",
        "-C",
        path,
        "diff",
        "--name-status",
        range,
    });
    defer allocator.free(name_status);
    const trimmed = std.mem.trim(u8, name_status, " \r\n\t");
    try testing.expect(std.mem.indexOf(u8, trimmed, "keep-a.txt") != null);
    try testing.expect(std.mem.indexOf(u8, trimmed, "README") == null);
    try testing.expect(std.mem.indexOf(u8, trimmed, "keep-b.txt") == null);
    var rows: usize = 0;
    var it = std.mem.splitScalar(u8, trimmed, '\n');
    while (it.next()) |line| {
        if (line.len != 0) rows += 1;
    }
    try testing.expectEqual(@as(usize, 1), rows);
}

test "cap stays at 64; extra name-status rows are dropped" {
    var model = Model{};
    model.review_diff_active = true;
    model.review_diff_key = review_diff_key_first;
    model.review_diff_probe_session = 0;
    var i: usize = 0;
    while (i < max_review_diff_files + 8) : (i += 1) {
        var line_buf: [32]u8 = undefined;
        const line = try std.fmt.bufPrint(&line_buf, "M\tfile-{d}.txt\n", .{i});
        appendParsed(&model, line);
    }
    try std.testing.expectEqual(@as(u32, max_review_diff_files), model.review_diff_file_count);
}

test "hunk argv is chdir plus git diff operand -- path; Unstaged omits operand" {
    var buf: [argv_len_hunk][]const u8 = undefined;
    const branch = argvForHunk(.branch, .origin, "/tmp/faku-hunk", "src/a.zig", &buf);
    try std.testing.expectEqual(argv_len_hunk, branch.len);
    try std.testing.expectEqualStrings(sh_bin, branch[0]);
    try std.testing.expectEqualStrings("-c", branch[1]);
    try std.testing.expectEqualStrings(main.fx_ask_chdir_script, branch[2]);
    try std.testing.expectEqualStrings("sh", branch[3]);
    try std.testing.expectEqualStrings("/tmp/faku-hunk", branch[4]);
    try std.testing.expectEqualStrings(git_bin, branch[5]);
    try std.testing.expectEqualStrings(git_diff_cmd, branch[6]);
    try std.testing.expectEqualStrings(git_upstream_range, branch[7]);
    try std.testing.expectEqualStrings(git_pathspec_end, branch[8]);
    try std.testing.expectEqualStrings("src/a.zig", branch[9]);
    try std.testing.expect(isGitReviewHunkArgv(branch));
    try std.testing.expect(!isGitReviewDiffArgv(branch));
    try std.testing.expect(std.mem.indexOf(u8, branch[2], git_upstream_range) == null);
    try std.testing.expect(std.mem.indexOf(u8, branch[2], "src/a.zig") == null);

    var uncommitted_buf: [argv_len_hunk][]const u8 = undefined;
    const uncommitted = argvForHunk(.uncommitted, .origin, "/tmp/faku-hunk", "tracked.zig", &uncommitted_buf);
    try std.testing.expectEqual(argv_len_hunk, uncommitted.len);
    try std.testing.expectEqualStrings(git_head, uncommitted[7]);
    try std.testing.expectEqualStrings(git_pathspec_end, uncommitted[8]);
    try std.testing.expectEqualStrings("tracked.zig", uncommitted[9]);
    try std.testing.expect(isGitReviewHunkArgv(uncommitted));
    try std.testing.expect(!isGitReviewDiffArgv(uncommitted));
    try std.testing.expect(!isGitReviewUncommittedArgv(uncommitted));
    try std.testing.expect(std.mem.indexOf(u8, uncommitted[2], git_head) == null);

    var staged_buf: [argv_len_hunk][]const u8 = undefined;
    const staged = argvForHunk(.staged, .origin, "/tmp/faku-hunk", "staged.zig", &staged_buf);
    try std.testing.expectEqualStrings(git_cached_flag, staged[7]);
    try std.testing.expectEqualStrings(git_pathspec_end, staged[8]);
    try std.testing.expectEqualStrings("staged.zig", staged[9]);
    try std.testing.expect(isGitReviewHunkArgv(staged));
    try std.testing.expect(!isGitReviewDiffArgv(staged));
    try std.testing.expect(std.mem.indexOf(u8, staged[2], git_cached_flag) == null);

    var unstaged_buf: [argv_len_hunk][]const u8 = undefined;
    const unstaged = argvForHunk(.unstaged, .origin, "/tmp/faku-hunk", "unstaged.zig", &unstaged_buf);
    try std.testing.expectEqual(argv_len_hunk_unstaged, unstaged.len);
    try std.testing.expectEqualStrings(git_pathspec_end, unstaged[7]);
    try std.testing.expectEqualStrings("unstaged.zig", unstaged[8]);
    try std.testing.expect(hunkOperand(.unstaged, .origin) == null);
    try std.testing.expect(isGitReviewHunkArgv(unstaged));
    try std.testing.expect(!isGitReviewDiffArgv(unstaged));
    try std.testing.expect(std.mem.indexOf(u8, unstaged[2], "unstaged.zig") == null);

    var committed_buf: [argv_len_hunk][]const u8 = undefined;
    const committed = argvForHunk(.committed, .origin, "/tmp/faku-hunk", "committed.zig", &committed_buf);
    try std.testing.expectEqualStrings(git_committed_range, committed[7]);
    try std.testing.expectEqualStrings(git_pathspec_end, committed[8]);
    try std.testing.expect(isGitReviewHunkArgv(committed));
    try std.testing.expect(!isGitReviewDiffArgv(committed));

    var committed_main_buf: [argv_len_hunk][]const u8 = undefined;
    const committed_main = argvForHunk(.committed, .main, "/tmp/faku-hunk", "committed.zig", &committed_main_buf);
    try std.testing.expectEqualStrings(git_committed_range_main, committed_main[7]);
    try std.testing.expectEqualStrings(git_pathspec_end, committed_main[8]);
    try std.testing.expect(isGitReviewHunkArgv(committed_main));
    try std.testing.expect(!isGitReviewDiffArgv(committed_main));

    var committed_master_buf: [argv_len_hunk][]const u8 = undefined;
    const committed_master = argvForHunk(.committed, .master, "/tmp/faku-hunk", "committed.zig", &committed_master_buf);
    try std.testing.expectEqualStrings(git_committed_range_master, committed_master[7]);
    try std.testing.expect(isGitReviewHunkArgv(committed_master));
    try std.testing.expect(!isGitReviewDiffArgv(committed_master));

    const last_turn_sha = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    var last_turn_range_buf: [last_turn_range_len]u8 = undefined;
    const last_turn_range = formatLastTurnRange(last_turn_sha, &last_turn_range_buf) orelse return error.MissingLastTurnHunkRange;
    var last_turn_hunk_buf: [argv_len_hunk][]const u8 = undefined;
    const last_turn_hunk = argvForHunkLastTurn("/tmp/faku-hunk", last_turn_range, "last-turn.zig", &last_turn_hunk_buf);
    try std.testing.expectEqual(argv_len_hunk, last_turn_hunk.len);
    try std.testing.expectEqualStrings(last_turn_range, last_turn_hunk[7]);
    try std.testing.expectEqualStrings("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb...HEAD", last_turn_hunk[7]);
    try std.testing.expectEqualStrings(git_pathspec_end, last_turn_hunk[8]);
    try std.testing.expectEqualStrings("last-turn.zig", last_turn_hunk[9]);
    try std.testing.expect(isGitReviewHunkArgv(last_turn_hunk));
    try std.testing.expect(!isGitReviewDiffArgv(last_turn_hunk));
    try std.testing.expect(std.mem.indexOf(u8, last_turn_hunk[2], last_turn_sha) == null);
    try std.testing.expect(std.mem.indexOf(u8, last_turn_hunk[2], last_turn_range) == null);
    try std.testing.expect(std.mem.indexOf(u8, last_turn_hunk[2], "HEAD~1") == null);
    var last_turn_snap_buf: [last_turn_range_len]u8 = undefined;
    const last_turn_snap = formatLastTurnSnapshot(last_turn_sha, &last_turn_snap_buf) orelse return error.MissingLastTurnSnapHunkRange;
    var last_turn_snap_hunk_buf: [argv_len_hunk][]const u8 = undefined;
    const last_turn_snap_hunk = argvForHunkLastTurn("/tmp/faku-hunk", last_turn_snap, "last-turn.zig", &last_turn_snap_hunk_buf);
    try std.testing.expectEqual(argv_len_hunk, last_turn_snap_hunk.len);
    try std.testing.expectEqualStrings(last_turn_sha, last_turn_snap_hunk[7]);
    try std.testing.expect(std.mem.indexOf(u8, last_turn_snap_hunk[7], git_last_turn_range_suffix) == null);
    try std.testing.expect(isGitReviewHunkArgv(last_turn_snap_hunk));
    try std.testing.expect(std.mem.indexOf(u8, last_turn_snap_hunk[2], last_turn_sha) == null);
    var last_turn_start_end_hunk_range_buf: [last_turn_range_len]u8 = undefined;
    const last_turn_start_end_hunk_range = formatLastTurnStartEnd(
        last_turn_sha,
        "cccccccccccccccccccccccccccccccccccccccc",
        &last_turn_start_end_hunk_range_buf,
    ) orelse return error.MissingLastTurnStartEndHunkRange;
    var last_turn_start_end_hunk_buf: [argv_len_hunk][]const u8 = undefined;
    const last_turn_start_end_hunk = argvForHunkLastTurn("/tmp/faku-hunk", last_turn_start_end_hunk_range, "last-turn.zig", &last_turn_start_end_hunk_buf);
    try std.testing.expectEqual(argv_len_hunk, last_turn_start_end_hunk.len);
    try std.testing.expectEqualStrings(last_turn_start_end_hunk_range, last_turn_start_end_hunk[7]);
    try std.testing.expectEqualStrings("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb..cccccccccccccccccccccccccccccccccccccccc", last_turn_start_end_hunk[7]);
    try std.testing.expectEqual(@as(usize, 82), last_turn_start_end_hunk[7].len);
    try std.testing.expect(std.mem.indexOf(u8, last_turn_start_end_hunk[7], "...") == null);
    try std.testing.expectEqualStrings(git_pathspec_end, last_turn_start_end_hunk[8]);
    try std.testing.expectEqualStrings("last-turn.zig", last_turn_start_end_hunk[9]);
    try std.testing.expect(isGitReviewHunkArgv(last_turn_start_end_hunk));
    try std.testing.expect(std.mem.indexOf(u8, last_turn_start_end_hunk[2], last_turn_sha) == null);
    try std.testing.expect(std.mem.indexOf(u8, last_turn_start_end_hunk[2], last_turn_start_end_hunk_range) == null);
    const head_tilde_hunk = [_][]const u8{
        sh_bin,
        "-c",
        main.fx_ask_chdir_script,
        "sh",
        "/tmp/faku-hunk",
        git_bin,
        git_diff_cmd,
        "HEAD~1",
        git_pathspec_end,
        "last-turn.zig",
    };
    try std.testing.expect(!isGitReviewHunkArgv(&head_tilde_hunk));

    var untracked_buf: [argv_len_hunk_untracked][]const u8 = undefined;
    const untracked = argvForUntrackedHunk("/tmp/faku-hunk", "new file.txt", &untracked_buf);
    try std.testing.expectEqual(argv_len_hunk_untracked, untracked.len);
    try std.testing.expectEqual(@as(usize, 11), untracked.len);
    try std.testing.expectEqualStrings(git_bin, untracked[5]);
    try std.testing.expectEqualStrings(git_diff_cmd, untracked[6]);
    try std.testing.expectEqualStrings(git_no_index, untracked[7]);
    try std.testing.expectEqualStrings("--no-index", untracked[7]);
    try std.testing.expectEqualStrings(git_pathspec_end, untracked[8]);
    try std.testing.expectEqualStrings(git_dev_null, untracked[9]);
    try std.testing.expectEqualStrings("/dev/null", untracked[9]);
    try std.testing.expectEqualStrings("new file.txt", untracked[10]);
    try std.testing.expect(isGitReviewHunkArgv(untracked));
    try std.testing.expect(!isGitReviewDiffArgv(untracked));
    try std.testing.expect(!isGitReviewUncommittedArgv(untracked));
    try std.testing.expect(std.mem.indexOf(u8, untracked[2], git_no_index) == null);
    try std.testing.expect(std.mem.indexOf(u8, untracked[2], git_dev_null) == null);
    try std.testing.expect(std.mem.indexOf(u8, untracked[2], "new file.txt") == null);
}

test "isGitReviewHunkArgv does not match name-status; name-status detector rejects hunks" {
    var name_buf: [argv_len][]const u8 = undefined;
    const name = argvFor("/tmp/faku-hunk", &name_buf);
    try std.testing.expect(isGitReviewDiffArgv(name));
    try std.testing.expect(!isGitReviewHunkArgv(name));

    var uncommitted_buf: [argv_len][]const u8 = undefined;
    const uncommitted = argvForSource(.uncommitted, "/tmp/faku-hunk", &uncommitted_buf);
    try std.testing.expect(isGitReviewDiffArgv(uncommitted));
    try std.testing.expect(isGitReviewUncommittedArgv(uncommitted));
    try std.testing.expect(!isGitReviewHunkArgv(uncommitted));

    var unstaged_name_buf: [argv_len][]const u8 = undefined;
    const unstaged_name = argvForSource(.unstaged, "/tmp/faku-hunk", &unstaged_name_buf);
    try std.testing.expect(isGitReviewDiffArgv(unstaged_name));
    try std.testing.expect(!isGitReviewHunkArgv(unstaged_name));

    var hunk_buf: [argv_len_hunk][]const u8 = undefined;
    const hunk = argvForHunk(.branch, .origin, "/tmp/faku-hunk", "src/a.zig", &hunk_buf);
    try std.testing.expect(isGitReviewHunkArgv(hunk));
    try std.testing.expect(!isGitReviewDiffArgv(hunk));
    try std.testing.expect(!isGitReviewUncommittedArgv(hunk));

    var unstaged_hunk_buf: [argv_len_hunk][]const u8 = undefined;
    const unstaged_hunk = argvForHunk(.unstaged, .origin, "/tmp/faku-hunk", "src/a.zig", &unstaged_hunk_buf);
    try std.testing.expect(isGitReviewHunkArgv(unstaged_hunk));
    try std.testing.expect(!isGitReviewDiffArgv(unstaged_hunk));

    var untracked_buf: [argv_len_hunk_untracked][]const u8 = undefined;
    const untracked = argvForUntrackedHunk("/tmp/faku-hunk", "new file.txt", &untracked_buf);
    try std.testing.expect(isGitReviewHunkArgv(untracked));
    try std.testing.expect(!isGitReviewDiffArgv(untracked));
    try std.testing.expect(!isGitReviewUncommittedArgv(untracked));
    try std.testing.expect(!isGitReviewHunkArgv(name));
    try std.testing.expect(!isGitReviewDiffArgv(untracked));

    try std.testing.expect(!isGitReviewHunkArgv(&.{ git_bin, git_diff_cmd, git_upstream_range, git_pathspec_end, "src/a.zig" }));
    try std.testing.expect(!isGitReviewHunkArgv(&.{
        sh_bin,
        "-c",
        main.fx_ask_chdir_script,
        "sh",
        "/tmp/faku-hunk",
        git_bin,
        git_diff_cmd,
        git_name_status,
        git_upstream_range,
    }));
}

test "hunk path and -- are own argv slots; space in path stays last-slot" {
    var buf: [argv_len_hunk][]const u8 = undefined;
    const path = "src/my file.zig";
    const argv = argvForHunk(.branch, .origin, "/tmp/faku hunk", path, &buf);
    try std.testing.expectEqual(argv_len_hunk, argv.len);
    try std.testing.expectEqualStrings(git_pathspec_end, argv[8]);
    try std.testing.expectEqualStrings(path, argv[9]);
    try std.testing.expect(std.mem.indexOf(u8, argv[2], path) == null);
    try std.testing.expect(std.mem.indexOf(u8, argv[2], "my file.zig") == null);
    try std.testing.expect(isGitReviewHunkArgv(argv));
    try std.testing.expect(!isGitReviewDiffArgv(argv));

    var unstaged_buf: [argv_len_hunk][]const u8 = undefined;
    const unstaged = argvForHunk(.unstaged, .origin, "/tmp/faku hunk", path, &unstaged_buf);
    try std.testing.expectEqual(argv_len_hunk_unstaged, unstaged.len);
    try std.testing.expectEqualStrings(git_pathspec_end, unstaged[7]);
    try std.testing.expectEqualStrings(path, unstaged[8]);
    try std.testing.expect(std.mem.indexOf(u8, unstaged[2], path) == null);
    try std.testing.expect(isGitReviewHunkArgv(unstaged));

    var untracked_buf: [argv_len_hunk_untracked][]const u8 = undefined;
    const untracked_path = "new file.txt";
    const untracked = argvForUntrackedHunk("/tmp/faku hunk", untracked_path, &untracked_buf);
    try std.testing.expectEqual(argv_len_hunk_untracked, untracked.len);
    try std.testing.expectEqualStrings(git_no_index, untracked[7]);
    try std.testing.expectEqualStrings(git_pathspec_end, untracked[8]);
    try std.testing.expectEqualStrings(git_dev_null, untracked[9]);
    try std.testing.expectEqualStrings(untracked_path, untracked[10]);
    try std.testing.expect(std.mem.indexOf(u8, untracked[2], untracked_path) == null);
    try std.testing.expect(std.mem.indexOf(u8, untracked[2], "new file") == null);
    try std.testing.expect(std.mem.indexOf(u8, untracked[2], git_dev_null) == null);
    try std.testing.expect(isGitReviewHunkArgv(untracked));
    try std.testing.expect(!isGitReviewDiffArgv(untracked));
}

fn openWithFiles(model: *Model, fx: *Effects, line: []const u8) !u64 {
    open(model, fx);
    const key = model.review_diff_key;
    applyLine(model, .{ .key = key, .line = line });
    handleExit(model, fx, .{ .key = key, .reason = .exited, .code = 0 });
    return key;
}

test "clicking a tracked row fills capped patch text; empty and fail stay honest" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/review-hunk", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("review hunk", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);

    _ = try openWithFiles(&model, &fx, "M\tsrc/a.zig\nA\tnew.txt\n");
    try std.testing.expectEqual(@as(u32, 2), model.review_diff_file_count);
    try std.testing.expectEqual(@as(u32, 0), model.review_diff_selected_id);
    try std.testing.expectEqual(@as(u64, 0), model.review_diff_hunk_key);

    selectFile(&model, &fx, 1);
    try std.testing.expectEqual(@as(u32, 1), model.review_diff_selected_id);
    try std.testing.expect(model.review_diff_hunk_key >= review_diff_hunk_key_first);
    try std.testing.expect(model.review_diff_hunk_key != model.review_diff_key);
    const hunk_key = model.review_diff_hunk_key;
    const hunk_argv = findSpawnArgv(&fx, hunk_key) orelse return error.MissingHunkArgv;
    try std.testing.expect(isGitReviewHunkArgv(hunk_argv));
    try std.testing.expect(!isGitReviewDiffArgv(hunk_argv));
    try std.testing.expectEqualStrings(git_upstream_range, hunk_argv[7]);
    try std.testing.expectEqualStrings(git_pathspec_end, hunk_argv[8]);
    try std.testing.expectEqualStrings("src/a.zig", hunk_argv[9]);
    try std.testing.expect(std.mem.indexOf(u8, hunk_argv[2], "src/a.zig") == null);

    applyHunkLine(&model, .{ .key = hunk_key, .line = "diff --git a/src/a.zig b/src/a.zig\n" });
    applyHunkLine(&model, .{ .key = hunk_key, .line = "--- a/src/a.zig\n+++ b/src/a.zig\n@@ -1 +1 @@\n-old\n+new\n" });
    handleHunkExit(&model, &fx, .{ .key = hunk_key, .reason = .exited, .code = 0 });
    try std.testing.expect(hasReviewDiffHunk(&model));
    try std.testing.expect(!hasReviewDiffHunkStatus(&model));
    try std.testing.expect(std.mem.indexOf(u8, reviewDiffHunk(&model), "diff --git a/src/a.zig b/src/a.zig") != null);
    try std.testing.expect(std.mem.indexOf(u8, reviewDiffHunk(&model), "+new") != null);
    try std.testing.expectEqual(@as(u64, 0), model.review_diff_hunk_key);

    selectFile(&model, &fx, 2);
    try std.testing.expectEqual(@as(u32, 2), model.review_diff_selected_id);
    try std.testing.expect(!hasReviewDiffHunk(&model));
    try std.testing.expect(model.review_diff_hunk_key != hunk_key);
    const empty_key = model.review_diff_hunk_key;
    const empty_argv = findSpawnArgv(&fx, empty_key) orelse return error.MissingEmptyHunkArgv;
    try std.testing.expectEqualStrings("new.txt", empty_argv[9]);
    handleHunkExit(&model, &fx, .{ .key = empty_key, .reason = .exited, .code = 0 });
    try std.testing.expect(!hasReviewDiffHunk(&model));
    try std.testing.expectEqualStrings(hunk_empty_status, reviewDiffHunkStatus(&model));

    selectFile(&model, &fx, 1);
    const fail_key = model.review_diff_hunk_key;
    applyHunkLine(&model, .{ .key = fail_key, .line = "should-drop\n" });
    handleHunkExit(&model, &fx, .{ .key = fail_key, .reason = .exited, .code = 128 });
    try std.testing.expect(!hasReviewDiffHunk(&model));
    try std.testing.expectEqualStrings(hunk_failed_status, reviewDiffHunkStatus(&model));

    selectFile(&model, &fx, 1);
    const cap_key = model.review_diff_hunk_key;
    var i: usize = 0;
    while (i < max_review_diff_hunk_lines + 8) : (i += 1) {
        var line_buf: [24]u8 = undefined;
        const line = try std.fmt.bufPrint(&line_buf, "+line-{d}", .{i});
        applyHunkLine(&model, .{ .key = cap_key, .line = line });
    }
    try std.testing.expectEqual(@as(u32, max_review_diff_hunk_lines), model.review_diff_hunk_line_count);
    handleHunkExit(&model, &fx, .{ .key = cap_key, .reason = .exited, .code = 0 });
    try std.testing.expect(hasReviewDiffHunk(&model));
    try std.testing.expect(std.mem.indexOf(u8, reviewDiffHunk(&model), "+line-0") != null);
    try std.testing.expect(std.mem.indexOf(u8, reviewDiffHunk(&model), "+line-160") == null);
}

test "clicking a ? untracked row one-shots git diff --no-index" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/review-hunk-untracked", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("review hunk untracked", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);

    open(&model, &fx);
    setSource(&model, &fx, .uncommitted);
    const name_key = model.review_diff_key;
    applyLine(&model, .{ .key = name_key, .line = "M\ttracked.zig\n?\tnew file.txt\n" });
    handleExit(&model, &fx, .{ .key = name_key, .reason = .exited, .code = 0 });
    try std.testing.expectEqual(@as(u32, 2), model.review_diff_file_count);
    try std.testing.expectEqual(@as(u8, '?'), model.review_diff_file_store[1].status);

    selectFile(&model, &fx, 2);
    try std.testing.expectEqual(@as(u32, 2), model.review_diff_selected_id);
    try std.testing.expect(model.review_diff_hunk_key >= review_diff_hunk_key_first);
    try std.testing.expect(model.review_diff_hunk_no_index);
    const untracked_key = model.review_diff_hunk_key;
    const untracked_argv = findSpawnArgv(&fx, untracked_key) orelse return error.MissingUntrackedHunk;
    try std.testing.expect(isGitReviewHunkArgv(untracked_argv));
    try std.testing.expect(!isGitReviewDiffArgv(untracked_argv));
    try std.testing.expectEqual(argv_len_hunk_untracked, untracked_argv.len);
    try std.testing.expectEqualStrings(git_bin, untracked_argv[5]);
    try std.testing.expectEqualStrings(git_diff_cmd, untracked_argv[6]);
    try std.testing.expectEqualStrings(git_no_index, untracked_argv[7]);
    try std.testing.expectEqualStrings(git_pathspec_end, untracked_argv[8]);
    try std.testing.expectEqualStrings(git_dev_null, untracked_argv[9]);
    try std.testing.expectEqualStrings("new file.txt", untracked_argv[10]);
    try std.testing.expect(std.mem.indexOf(u8, untracked_argv[2], "new file.txt") == null);
    try std.testing.expect(std.mem.indexOf(u8, untracked_argv[2], git_dev_null) == null);

    applyHunkLine(&model, .{ .key = untracked_key, .line = "diff --git a/new file.txt b/new file.txt\n+hello\n" });
    handleHunkExit(&model, &fx, .{ .key = untracked_key, .reason = .exited, .code = 1 });
    try std.testing.expect(hasReviewDiffHunk(&model));
    try std.testing.expect(!hasReviewDiffHunkStatus(&model));
    try std.testing.expect(std.mem.indexOf(u8, reviewDiffHunk(&model), "diff --git") != null);
    try std.testing.expectEqual(@as(u64, 0), model.review_diff_hunk_key);

    selectFile(&model, &fx, 2);
    const empty_key = model.review_diff_hunk_key;
    try std.testing.expect(model.review_diff_hunk_no_index);
    handleHunkExit(&model, &fx, .{ .key = empty_key, .reason = .exited, .code = 1 });
    try std.testing.expect(!hasReviewDiffHunk(&model));
    try std.testing.expectEqualStrings(hunk_empty_status, reviewDiffHunkStatus(&model));

    selectFile(&model, &fx, 2);
    const fail_128 = model.review_diff_hunk_key;
    applyHunkLine(&model, .{ .key = fail_128, .line = "should-drop\n" });
    handleHunkExit(&model, &fx, .{ .key = fail_128, .reason = .exited, .code = 128 });
    try std.testing.expect(!hasReviewDiffHunk(&model));
    try std.testing.expectEqualStrings(hunk_failed_status, reviewDiffHunkStatus(&model));

    selectFile(&model, &fx, 2);
    const fail_2 = model.review_diff_hunk_key;
    applyHunkLine(&model, .{ .key = fail_2, .line = "should-drop-too\n" });
    handleHunkExit(&model, &fx, .{ .key = fail_2, .reason = .exited, .code = 2 });
    try std.testing.expect(!hasReviewDiffHunk(&model));
    try std.testing.expectEqualStrings(hunk_failed_status, reviewDiffHunkStatus(&model));

    selectFile(&model, &fx, 1);
    try std.testing.expectEqual(@as(u32, 1), model.review_diff_selected_id);
    try std.testing.expect(model.review_diff_hunk_key >= review_diff_hunk_key_first);
    try std.testing.expect(!model.review_diff_hunk_no_index);
    const tracked_argv = findSpawnArgv(&fx, model.review_diff_hunk_key) orelse return error.MissingTrackedHunk;
    try std.testing.expect(isGitReviewHunkArgv(tracked_argv));
    try std.testing.expect(!isGitReviewDiffArgv(tracked_argv));
    try std.testing.expectEqual(argv_len_hunk, tracked_argv.len);
    try std.testing.expectEqualStrings(git_head, tracked_argv[7]);
    try std.testing.expectEqualStrings(git_pathspec_end, tracked_argv[8]);
    try std.testing.expectEqualStrings("tracked.zig", tracked_argv[9]);
    try std.testing.expect(!std.mem.eql(u8, tracked_argv[7], git_no_index));
}

test "source switch and dismiss cancel in-flight hunk spawn" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/review-hunk-cancel", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("review hunk cancel", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);

    _ = try openWithFiles(&model, &fx, "M\tsrc/a.zig\n");
    selectFile(&model, &fx, 1);
    const hunk_key = model.review_diff_hunk_key;
    try std.testing.expect(hunk_key >= review_diff_hunk_key_first);
    applyHunkLine(&model, .{ .key = hunk_key, .line = "partial\n" });
    try std.testing.expect(hasReviewDiffHunk(&model));

    setSource(&model, &fx, .staged);
    try std.testing.expectEqual(Source.staged, model.review_diff_source);
    try std.testing.expectEqual(@as(u32, 0), model.review_diff_selected_id);
    try std.testing.expectEqual(@as(u64, 0), model.review_diff_hunk_key);
    try std.testing.expect(!hasReviewDiffHunk(&model));
    try std.testing.expect(!hasReviewDiffHunkStatus(&model));
    applyHunkLine(&model, .{ .key = hunk_key, .line = "should-ignore\n" });
    try std.testing.expect(!hasReviewDiffHunk(&model));
    handleHunkExit(&model, &fx, .{ .key = hunk_key, .reason = .exited, .code = 0 });
    try std.testing.expect(!hasReviewDiffHunk(&model));
    try std.testing.expectEqual(Source.staged, model.review_diff_source);

    applyLine(&model, .{ .key = model.review_diff_key, .line = "A\tstaged.zig\n" });
    handleExit(&model, &fx, .{ .key = model.review_diff_key, .reason = .exited, .code = 0 });
    selectFile(&model, &fx, 1);
    const again = model.review_diff_hunk_key;
    try std.testing.expect(again != hunk_key);
    const staged_argv = findSpawnArgv(&fx, again) orelse return error.MissingStagedHunk;
    try std.testing.expectEqualStrings(git_cached_flag, staged_argv[7]);

    dismiss(&model, &fx);
    try std.testing.expect(!model.review_diff_active);
    try std.testing.expectEqual(@as(u64, 0), model.review_diff_hunk_key);
    try std.testing.expectEqual(@as(u32, 0), model.review_diff_selected_id);
    try std.testing.expect(!hasReviewDiffHunk(&model));
    applyHunkLine(&model, .{ .key = again, .line = "after-dismiss\n" });
    handleHunkExit(&model, &fx, .{ .key = again, .reason = .exited, .code = 0 });
    try std.testing.expect(!hasReviewDiffHunk(&model));
    try std.testing.expect(!model.review_diff_active);
}

test "Committed hunk uses the range that already succeeded" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/review-hunk-committed", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    const sid = model.addSession("review hunk committed", .fx);
    model.selected = sid;
    if (model.sessionById(sid)) |session| session.setProjectPath(project);

    open(&model, &fx);
    setSource(&model, &fx, .committed);
    try std.testing.expectEqual(CommittedRange.origin, model.review_diff_committed_range);
    const origin_key = model.review_diff_key;
    handleExit(&model, &fx, .{ .key = origin_key, .reason = .exited, .code = 128 });
    try std.testing.expectEqual(CommittedRange.main, model.review_diff_committed_range);
    applyLine(&model, .{ .key = model.review_diff_key, .line = "M\tcommitted.zig\n" });
    handleExit(&model, &fx, .{ .key = model.review_diff_key, .reason = .exited, .code = 0 });
    try std.testing.expectEqual(CommittedRange.main, model.review_diff_committed_range);

    selectFile(&model, &fx, 1);
    const hunk_key = model.review_diff_hunk_key;
    const hunk_argv = findSpawnArgv(&fx, hunk_key) orelse return error.MissingCommittedHunk;
    try std.testing.expect(isGitReviewHunkArgv(hunk_argv));
    try std.testing.expectEqualStrings(git_committed_range_main, hunk_argv[7]);
    try std.testing.expectEqualStrings(git_pathspec_end, hunk_argv[8]);
    try std.testing.expectEqualStrings("committed.zig", hunk_argv[9]);
    try std.testing.expect(std.mem.indexOf(u8, hunk_argv[2], git_committed_range_main) == null);
    try std.testing.expect(std.mem.indexOf(u8, hunk_argv[2], git_committed_range) == null);
}

fn initLastTurnRepo(allocator: std.mem.Allocator, io: std.Io, path: []const u8) ![]u8 {
    try std.Io.Dir.cwd().createDirPath(io, path);
    try runLastTurnGitPlain(allocator, io, &.{ "git", "-C", path, "init" });
    try writeLastTurnFile(io, path, "README", "keep\n");
    try writeLastTurnFile(io, path, "keep-a.txt", "a\n");
    try writeLastTurnFile(io, path, "keep-b.txt", "b\n");
    try runLastTurnGitPlain(allocator, io, &.{ "git", "-C", path, "add", "README", "keep-a.txt", "keep-b.txt" });
    try runLastTurnGitPlain(allocator, io, &.{
        "git",
        "-C",
        path,
        "-c",
        "user.email=review-diff@test",
        "-c",
        "user.name=ReviewDiff",
        "-c",
        "commit.gpgsign=false",
        "commit",
        "-m",
        "init",
    });
    var sha_buf: [rewind.max_sha]u8 = undefined;
    const sha = rewind.revParseHead(allocator, io, path, &sha_buf) orelse return error.GitHead;
    return allocator.dupe(u8, sha);
}

fn writeLastTurnFile(io: std.Io, path: []const u8, name: []const u8, contents: []const u8) !void {
    var file_buf: [std.fs.max_path_bytes]u8 = undefined;
    const file_path = try std.fmt.bufPrint(&file_buf, "{s}{s}{s}", .{ path, std.fs.path.sep_str, name });
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = file_path, .data = contents });
}

fn runLastTurnGitPlain(allocator: std.mem.Allocator, io: std.Io, argv: []const []const u8) !void {
    const result = try std.process.run(allocator, io, .{
        .argv = argv,
        .stdout_limit = .limited(1024),
        .stderr_limit = .limited(4096),
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    if (result.term != .exited or result.term.exited != 0) return error.GitFailed;
}

fn runLastTurnGitCapture(allocator: std.mem.Allocator, io: std.Io, argv: []const []const u8) ![]u8 {
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
