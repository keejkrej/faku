//! First-cut Waku Environment Compare / Review file list.
//!
//! Environment Compare and header +/- close the Environment
//! Summary popover (when open) and open the right-panel Diff tab
//! with this Review body inline. Diff-tab default source is
//! Uncommitted (Waku web `changes` defaults `uncommitted`); if
//! Compare is already active, that source is kept and refreshed.
//! `open` still starts Branch for unit tests of the probe stack.
//! `git diff --numstat @{upstream}...HEAD` (symmetric range,
//! same spirit as ahead/behind). Uncommitted is a switchable
//! first-cut: tracked `git diff --numstat HEAD` plus
//! untracked, non-ignored paths from
//! `git ls-files --others --exclude-standard` (synthetic
//! `N\t0\tpath` rows; no text-only / size filter). Unix packs
//! this under Native `max_effect_argv` as chdir + nested
//! `/bin/sh -c`; Windows Uncommitted uses PowerShell
//! `-Command` + `-Args`.
//! Staged is a switchable first-cut: one-shot
//! `git diff --numstat --cached` (index vs HEAD;
//! untracked cannot appear unless already staged). Unstaged is a
//! switchable first-cut: one-shot `git diff --numstat`
//! (worktree vs index, tracked only; no `--cached`, no `HEAD`
//! range). Committed is a switchable first-cut: one-shot
//! `git diff --numstat origin/HEAD...HEAD` (merge-base of
//! the default remote branch and HEAD → HEAD; distinct from
//! Branch `@{upstream}...HEAD`). Missing `origin/HEAD` (non-zero
//! git exit) retries the same argv with last-slot `main...HEAD`,
//! then `master...HEAD`; all three failing stays
//! `Could not compare.` A successful origin/HEAD probe with
//! zero files is `No changes to compare` (no main/master
//! fall-through). LastTurn is a switchable first-cut: one-shot
//! `git diff --numstat` of the last completed turn.
//! When both finish-time turn-diff (`worktree_turn_diff_sha`)
//! and turn-end (`worktree_turn_end_sha`) are valid 40-hex,
//! the operand is `diff..end` (two-dot). Else when both
//! send-time start (`worktree_snapshot_sha`) and finish-time
//! end are valid 40-hex, the operand is `start..end` (two-dot,
//! own argv slot; Waku `git diff from to` / `A..B` is the tree
//! of A vs the tree of B). Else a valid start is a bare 40-hex
//! two-dot vs the live worktree. Else send-time rewind
//! `git diff --numstat <sha>...HEAD` (`latestRewindSha`
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
//! Clicking a tracked numstat row one-shots `git diff`
//! for that path (current source + the Committed range that
//! already succeeded, or the stored LastTurn range).
//! `--` and the path are own argv slots.
//! Uncommitted `?` rows one-shot
//! `git diff --no-index -- /dev/null <path>` on Unix (POSIX
//! empty left side) and `git.exe -C PATH diff --no-index --
//! NUL <path>` on Windows (`NUL` is the Git for Windows
//! null device). `--no-index` implies `--exit-code`, so
//! exit 1 with a body is a successful patch. `--no-index`,
//! `--`, `/dev/null` / `NUL`, and the path are own argv
//! slots (Unix 11 / Windows 8; under Native
//! `max_effect_argv` 16). A `?` directory that
//! makes git fail is `Could not show diff.` — no invented
//! tree listing. Hunk
//! spawn-key band 520+ is distinct from file-list 510+.
//! Unix uses the `/bin/sh -c` `fx_ask_chdir_script` chdir
//! workaround. Last-slot operands (`@{upstream}...HEAD` /
//! `--cached` / `origin/HEAD...HEAD` / `main...HEAD` /
//! `master...HEAD` / `<40-hex>..<40-hex>` / `<40-hex>` /
//! `<40-hex>...HEAD`) are their
//! own argv slots — never interpolated into `-c`. Uncommitted packs
//! `HEAD` into the nested script (not a last-slot `HEAD`).
//! Unstaged has no trailing operand, so its Unix argv is 8 slots
//! (the 9-slot detector still accepts Branch / Staged /
//! Committed / LastTurn). Distinct
//! spawn-key band 510+ (after git-common-dir
//! 500+). Cap 64 rows. Empty / clean is `No changes to compare`.
//! Failed / no upstream / missing workspace is a short muted
//! status — no invented files. First-cut selected-file hunks
//! parse into HunkHeader / Context / Addition / Deletion / Gap
//! rows (Waku `review_diff` Gap model). Native paints a
//! `shown_line` gutter (`new_line` else `old_line`); code-row
//! body matches Waku `Line.content` (unified-diff marker
//! stripped). Syntax-token highlighting still does not (Native
//! has no per-span Token). File-list rows paint a first-cut nested
//! directory tree matching Waku `review_diff_tree_rows` (Directory +
//! File, default collapsed, basename leaves). First-cut path filter
//! matches Waku `right_panel_diff_filter`: trim + ascii-lowercase
//! contains on the full path; a non-empty query auto-expands ancestor
//! directories. Empty / whitespace-only query is today's collapsed
//! tree. Status stays on the file label; Waku-style `+N` / `-M` (success /
//! destructive) come from numstat when those counts are non-zero
//! (daemon CollectReviewDiff and local `--numstat`; zeros omitted).
//! `completeContext` daemon patches collapse long context into
//! expandable Gaps; local compact `git diff` inserts count-only
//! Gaps between hunks (hidden empty — expand is a no-op). Expand
//! rearranges retained lines in memory (`expand_gap`); no new git
//! spawn. Line retain/render caps match Waku `MAX_RENDERED_DIFF_LINES`
//! 50_000. Byte caps are a Faku fixed table (~32 B/line × that cap);
//! Waku has no byte cap. Parse/expand scratch and the hunk / Gap
//! stores are heap last-windows so `Model` / `initialModel()` stay
//! return-by-value safe (inline 50_000-row tables would blow the
//! stack). Native daemon stdout is still `daemon_line_bytes`. The
//! right-panel Diff tab hosts this same body (not a second git
//! probe stack).
//! First-cut daemon `WorkspaceOperation::CollectReviewDiff` ships
//! when `WAKU_DAEMON_ADDRESS` or persisted `last_daemon_address`
//! is set: hello + CollectReviewDiff for Branch / Uncommitted /
//! Staged / Unstaged / Committed on open / refresh / source-switch
//! (same moments as today's local numstat probes). Ok nested
//! `reviewDiff.data` paints the file list from `numstat` (cap 64)
//! including per-file addition/deletion counts, and stores `patch`
//! for selected-file hunk display (no per-file hunk spawn when that
//! patch is usable). LastTurn stays local. Overflow / spawn failure
//! / non-ok / unusable parse fall back to local `--numstat`. Leftovers still blocked or deferred:
//! syntax-token highlighting (no per-span Token), GPUI match
//! washes, circular GPUI gauge, file-mention 50k index (Faku cap
//! 256), chart 12% fill opacity, amend/force over daemon, remote
//! `--track` over daemon.
//! Not transcript checkpoint +/-.
//! LastTurn uses stored shas, not the refs, and not a
//! `refs/waku/` Compare operand.
//!
//! Windows cannot use `/bin/sh` or the Uncommitted nested
//! `uncommitted_untracked_script`. Branch / Staged /
//! Unstaged / Committed / LastTurn numstat and tracked
//! hunks stay `git.exe -C <project_path>` (path is its own
//! argv slot). Explicit `git.exe` like siblings. Uncommitted
//! numstat is `powershell.exe -NoProfile -Command
//! {scriptblock} -Args <project_path>` (`$args[0]`; path is
//! its own argv slot, not interpolated into `-Command`).
//! After `Set-Location -LiteralPath $args[0]`, the script
//! runs `git.exe diff --numstat HEAD` then synthetic
//! `N\t0\tpath` rows from `git.exe ls-files --others
//! --exclude-standard` (every non-empty path; no
//! git_numstat binary / 1MiB / zero-line filters). Distinct
//! script body from `git_numstat.windowsArgvFor`. Tracked
//! hunks are `git.exe -C PATH diff [operand] -- <path>`.
//! Untracked `?` hunks are `git.exe -C PATH diff --no-index
//! -- NUL <path>` (`NUL` and the path are own argv slots).
//! Numstat / hunk stdout is already CRLF-trimmed.
//! app.zon already includes windows.
//!
//! Spawn/line/exit orchestration lives here. Effect keys stay
//! file-list 510+ and hunk 520+. First-cut daemon
//! `WorkspaceOperation::CollectReviewDiff` reuses `next_daemon_key`
//! assigned onto `review_diff_key` so `applyLine` / `handleExit`
//! still own the probe. LastTurn stays local this cut (no invented
//! turn UUIDs). Native 4 KiB stdin overflow / sidecar failure /
//! unusable parse fall back to today's local numstat + hunk
//! probes. No address keeps the local path unchanged.

const std = @import("std");
const builtin = @import("builtin");
const native_sdk = @import("native_sdk");
const main = @import("main.zig");
const git_ahead_behind = @import("git_ahead_behind.zig");
const git_checkout = @import("git_checkout.zig");
const git_common_dir = @import("git_common_dir.zig");
const rewind = @import("rewind.zig");
const store = @import("store.zig");
const daemon_proxy = @import("daemon_proxy.zig");
const protocol = @import("protocol.zig");
const composer = @import("composer.zig");
const file_mention = @import("file_mention.zig");

const Model = main.Model;
const Effects = main.Effects;
const writeFixed = main.writeFixed;

/// One-shot Review `git diff --numstat` (Branch,
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
/// or untracked `git diff --no-index -- /dev/null <path>`
/// (Unix) / `NUL` (Windows).
/// Distinct from file-list 510+. Band is 520+. Incremented
/// per file click so a cancelled spawn cannot paint a later
/// click or session.
pub const review_diff_hunk_key_first: u64 = 520;

/// Compare / header +/- open the Diff tab on Uncommitted when no
/// compare is active. Uncommitted is first-cut
/// tracked `git diff --numstat HEAD` plus untracked
/// `git ls-files --others --exclude-standard` (`N\t0\tpath`
/// rows parsed as `?`; Unix nested `uncommitted_untracked_script`,
/// Windows PowerShell `$args[0]`). Staged
/// is first-cut index vs HEAD `git diff --numstat --cached`.
/// Unstaged is first-cut worktree vs index `git diff
/// --numstat` (tracked only). Committed is first-cut
/// `git diff --numstat origin/HEAD...HEAD`, then local
/// `main...HEAD` / `master...HEAD` on a still-current non-zero
/// exit. LastTurn is first-cut last-completed-turn
/// `git diff --numstat diff..end` when turn-diff and
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
/// Unique parent dirs derived from the 64-file store. Same cap as
/// files so the tree cannot outgrow the list it is built from.
pub const max_review_diff_dirs: usize = 64;
/// Dir-row ids start here so `select_review_diff_file:{r.id}` cannot
/// collide with 1-based file ids (`1..=max_review_diff_files`).
pub const review_diff_dir_id_base: u32 = 1000;
/// Native spacer per tree depth. Waku dirs are `7 + depth*14` and
/// files `23 + depth*14`; Native padding/gap plus this step
/// approximate that without GPUI `px()`.
pub const tree_indent_step: f32 = 14;
/// Extra file gutter so leaves sit past dir chevron + folder.
pub const tree_file_indent_extra: f32 = 16;
pub const max_review_diff_path: usize = 255;
/// `X ` plus path. Rename/copy uses the destination path only.
pub const max_review_diff_label: usize = 258;
pub const max_review_diff_status: usize = 32;

pub const git_bin = "git";
/// PATH-resolved Windows Git (explicit `.exe` like sibling
/// `powershell.exe` / `explorer.exe` / `wt.exe` / `cmd.exe`).
pub const windows_git_bin = "git.exe";
pub const git_c_flag = "-C";
pub const git_diff_cmd = "diff";
pub const git_numstat = "--numstat";
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
/// Windows null device (Git for Windows `--no-index` left
/// side). Own argv slot. Never interpolated into a script.
pub const git_nul = "NUL";
pub const sh_bin = "/bin/sh";
/// PATH-resolved Windows PowerShell (no STA: this is git
/// stdout, not WinForms). Explicit `.exe` like sibling
/// maximize / pickers / `git_numstat`.
pub const powershell_bin = "powershell.exe";
pub const powershell_noprofile = "-NoProfile";
pub const powershell_command = "-Command";
pub const powershell_args_flag = "-Args";

/// Packed into one `-c` string so Uncommitted stays under Native
/// `max_effect_argv` (16). Real `git diff --numstat HEAD`
/// first; then synthetic `N\t0\tpath` rows for every non-empty
/// `git ls-files --others --exclude-standard` path. Non-zero
/// from the diff exits without inventing untracked.
pub const uncommitted_untracked_script =
    \\git diff --numstat HEAD || exit $?
    \\git ls-files --others --exclude-standard 2>/dev/null | while IFS= read -r f || [ -n "$f" ]; do
    \\[ -z "$f" ] && continue
    \\printf 'N\t0\t%s\n' "$f"
    \\done
;

/// Scriptblock + `$args[0]`: project path is its own argv slot after
/// `-Args`, not spliced into the `-Command` body. `Set-Location` then
/// `git.exe diff --numstat HEAD` (fail the spawn on non-zero; do
/// not invent untracked), then `git.exe ls-files --others
/// --exclude-standard`. Skip empty; print `N\t0\tpath` with `/`
/// separators. No binary / 1MiB / zero-line filters (unlike
/// `git_numstat.powershell_untracked_script`). Six argv slots total.
pub const powershell_uncommitted_untracked_script =
    "{ $ErrorActionPreference='Stop'; Set-Location -LiteralPath $args[0]; git.exe diff --numstat HEAD; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; foreach ($f in @(git.exe ls-files --others --exclude-standard 2>$null)) { if (-not $f) { continue }; $rel=([string]$f -replace '\\\\','/'); if (-not $rel) { continue }; Write-Output ('N'+[char]9+'0'+[char]9+'{0}' -f $rel) } }";

/// Unix `/bin/sh -c` chdir + `git diff --numstat` + last-slot
/// operand (Branch / Staged / Committed / LastTurn) is 9. Windows
/// `git.exe -C` is 6; this is the spawn buffer (max of the two).
pub const argv_len: usize = 9;
pub const unix_argv_len: usize = 9;
pub const windows_argv_len: usize = 6;
/// Unstaged: Unix chdir prefix, no trailing operand (8). Windows
/// `git.exe -C PATH diff --numstat` is 5.
pub const argv_len_unstaged: usize = 8;
pub const unix_argv_len_unstaged: usize = 8;
pub const windows_argv_len_unstaged: usize = 5;
/// Uncommitted: Unix chdir + `/bin/sh -c` + `uncommitted_untracked_script`
/// (8). Windows powershell `-Command` + `-Args` is 6.
pub const argv_len_uncommitted: usize = 8;
pub const unix_argv_len_uncommitted: usize = 8;
pub const windows_argv_len_uncommitted: usize = 6;
/// Hunk with operand: Unix chdir + `git diff <operand> -- <path>` (10).
/// Windows `git.exe -C PATH diff <operand> -- <path>` is 7.
pub const argv_len_hunk: usize = 10;
pub const unix_argv_len_hunk: usize = 10;
pub const windows_argv_len_hunk: usize = 7;
/// Unstaged hunk: Unix chdir + `git diff -- <path>` (9). Windows
/// `git.exe -C PATH diff -- <path>` is 6.
pub const argv_len_hunk_unstaged: usize = 9;
pub const unix_argv_len_hunk_unstaged: usize = 9;
pub const windows_argv_len_hunk_unstaged: usize = 6;
/// Untracked `?` hunk: Unix chdir + `git diff --no-index -- /dev/null <path>`
/// (11). Windows `git.exe -C PATH diff --no-index -- NUL <path>` is 8.
/// `argv_len_hunk_untracked` is the spawn buffer (max of the two).
pub const argv_len_hunk_untracked: usize = 11;
pub const unix_argv_len_hunk_untracked: usize = 11;
pub const windows_argv_len_hunk_untracked: usize = 8;
/// Waku `DEFAULT_EXPANSION_LINE_COUNT`. Start/End reveal this many
/// retained hidden lines; Both reveals up to twice this.
pub const default_expansion_line_count: usize = 100;
/// Waku `COLLAPSED_CONTEXT_LINES` kept on each side of a change.
pub const collapsed_context_lines: usize = 3;
/// Waku `COLLAPSED_CONTEXT_THRESHOLD`: hide a context run only when
/// more than this many lines would go into the Gap.
pub const collapsed_context_threshold: usize = 1;
/// Visible painted rows after collapse. Matches Waku
/// `MAX_RENDERED_DIFF_LINES` 50_000. Heap last-window on Model, not
/// an unbounded Vec and not a 50k-row stack table.
pub const max_rendered_diff_lines: usize = 50_000;
/// Retained source lines (stdout / daemon extract). Same bound as
/// the visible table so a complete-context patch can fill Gaps.
pub const max_review_diff_hunk_lines: usize = 50_000;
/// ~32 bytes/line × `max_review_diff_hunk_lines`. Waku has no byte
/// cap; Faku keeps this fixed table so the line cap is not secretly
/// defeated by a 128 KiB clip. Extra stdout is dropped, not invented.
pub const max_review_diff_hunk: usize = max_review_diff_hunk_lines * 32;
/// Hidden context copied out of collapsed runs. Same bound as
/// retained source lines.
pub const max_review_diff_hidden_lines: usize = 50_000;
pub const max_review_diff_hunk_status: usize = 32;
/// Stored daemon `patch` for selected-file filter. Match the hunk
/// retain cap so a `completeContext` body can still extract later
/// files. Native daemon stdout is still `daemon_line_bytes` (64 KiB
/// JSON lines), so a CollectReviewDiff payload larger than that is
/// still clipped before this table.
pub const max_review_diff_daemon_patch: usize = max_review_diff_hunk;
/// Gap label buffer (`{n} unmodified lines`).
pub const max_review_diff_gap_label: usize = 40;

pub const comparing_status = "Comparing…";
pub const empty_status = "No changes to compare";
pub const failed_status = "Could not compare.";
pub const no_workspace_status = "No workspace.";
pub const hunk_empty_status = "No hunks";
pub const hunk_failed_status = "Could not show diff.";

/// Native `for each="review_diff_rows"` row. File `id` is 1-based
/// into `review_diff_file_store`. Directory `id` is
/// `review_diff_dir_id_base + parent_index`. File `label` is
/// `{status} {basename}`; directory `label` is the path segment.
/// Optional `+N` / `-M` live in `additions_label` / `deletions_label`
/// (empty when the count is 0, and empty on directory rows).
pub const ReviewDiffRow = struct {
    id: u32,
    label: []const u8,
    selected: bool = false,
    additions_label: []const u8 = "",
    deletions_label: []const u8 = "",
    has_additions: bool = false,
    has_deletions: bool = false,
    is_directory: bool = false,
    expanded: bool = false,
    depth: u32 = 0,
    has_indent: bool = false,
    indent: f32 = 0,
};

/// Waku `LineKind` without syntax tokens. `gap` holds collapsed
/// context between or around changes.
pub const LineKind = enum(u8) {
    file_header,
    hunk_header,
    context,
    addition,
    deletion,
    meta,
    gap,
};

/// Waku `GapPosition`.
pub const GapPosition = enum(u8) {
    leading,
    between,
    trailing,
};

/// Waku `ExpansionDirection`.
pub const ExpansionDirection = enum(u8) {
    start,
    end,
    both,
    all,
};

/// One parsed / visible / hidden diff row. `content_off`/`content_len`
/// index `review_diff_hunk_storage`. Context / addition / deletion
/// skip the first unified-diff marker byte (Waku `Line.content`).
/// Meta and headers keep the full raw line. `old_line`/`new_line` 0
/// means none. Gap rows use `gap_*` / `hidden_*` (hidden indexes the
/// hidden table).
pub const DiffLine = struct {
    kind: LineKind = .context,
    gap_position: GapPosition = .between,
    content_len: u16 = 0,
    old_line: u32 = 0,
    new_line: u32 = 0,
    content_off: u32 = 0,
    gap_id: u32 = 0,
    gap_count: u32 = 0,
    hidden_off: u32 = 0,
    hidden_len: u32 = 0,
};

/// Native `for each="review_diff_hunk_rows"` row. `id` is 1-based
/// visible-row index (the expand payload). `text` is Waku-style
/// code-row body (marker stripped) or `gapLabel`. `line_number` is
/// Waku `shown_line` (`new_line` else `old_line`) as an arena decimal.
pub const ReviewDiffHunkRow = struct {
    id: u32,
    text: []const u8,
    line_number: []const u8 = "",
    is_addition: bool = false,
    is_deletion: bool = false,
    is_gap: bool = false,
    has_line_number: bool = false,
    can_expand_start: bool = false,
    can_expand_end: bool = false,
    can_expand_both: bool = false,
    can_expand_all: bool = false,
};

pub const ChangedFile = struct {
    status: u8 = 0,
    additions: u64 = 0,
    deletions: u64 = 0,
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
        self.setCounts(status, file_path, 0, 0);
    }

    pub fn setCounts(self: *ChangedFile, status: u8, file_path: []const u8, additions: u64, deletions: u64) void {
        self.status = status;
        self.additions = additions;
        self.deletions = deletions;
        writeFixed(&self.path_storage, &self.path_len, file_path);
        const written = std.fmt.bufPrint(&self.label_storage, "{c} {s}", .{ status, self.path() }) catch {
            self.label_len = 0;
            return;
        };
        self.label_len = written.len;
    }
};

/// Last argv slot for sources that have one. Unstaged is `null`
/// (`git diff --numstat` with no range / `--cached`).
/// Uncommitted is `null` (Unix packs `HEAD` in the nested
/// script; Windows last-slot `HEAD` is filled by the argv
/// builder). Committed reads `committed_range` (default first
/// probe is `origin/HEAD...HEAD`). LastTurn reads the captured
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
/// uses last-slot `HEAD` (Unix numstat packs `HEAD` in the
/// nested script; Windows numstat last-slot is `HEAD`).
/// Unstaged omits the operand. Committed reads the range
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

fn windowsGitBinOk(bin: []const u8) bool {
    return std.mem.eql(u8, bin, windows_git_bin) or std.mem.eql(u8, bin, git_bin);
}

fn scriptHas(script: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, script, needle) != null;
}

fn isKnownNumstatOperand(last: []const u8) bool {
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

pub fn unixArgvForSource(source: Source, cwd: []const u8, buf: *[argv_len][]const u8) []const []const u8 {
    return unixArgvForSourceRange(source, .origin, cwd, buf);
}

pub fn unixArgvForSourceRange(
    source: Source,
    committed_range: CommittedRange,
    cwd: []const u8,
    buf: *[argv_len][]const u8,
) []const []const u8 {
    return unixArgvForSourceRangeWith(source, committed_range, "", cwd, buf);
}

/// Unix LastTurn numstat: 9-slot chdir + `git diff --numstat`
/// + `diff..end` / `start..end`, snapshot `40-hex`, or rewind
/// `<sha>...HEAD`. Operand is one own argv slot.
pub fn unixArgvForLastTurn(cwd: []const u8, last_turn_range: []const u8, buf: *[argv_len][]const u8) []const []const u8 {
    return unixArgvForSourceRangeWith(.last_turn, .origin, last_turn_range, cwd, buf);
}

pub fn unixArgvForSourceRangeWith(
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
        return buf[0..unix_argv_len_uncommitted];
    }
    buf[5] = git_bin;
    buf[6] = git_diff_cmd;
    buf[7] = git_numstat;
    if (lastOperandRange(source, committed_range, last_turn_range)) |operand| {
        buf[8] = operand;
        return buf[0..unix_argv_len];
    }
    return buf[0..unix_argv_len_unstaged];
}

/// Windows: Branch / Staged / Unstaged / Committed / LastTurn stay
/// `git.exe -C <project_path> diff --numstat [operand]`.
/// Path is its own argv slot. Uncommitted is powershell
/// `-Command` + `-Args` (`$args[0]`; tracked numstat plus
/// synthetic `N\t0\tpath`).
pub fn windowsArgvForSourceRangeWith(
    source: Source,
    committed_range: CommittedRange,
    last_turn_range: []const u8,
    cwd: []const u8,
    buf: *[argv_len][]const u8,
) []const []const u8 {
    if (source == .uncommitted) {
        buf[0] = powershell_bin;
        buf[1] = powershell_noprofile;
        buf[2] = powershell_command;
        buf[3] = powershell_uncommitted_untracked_script;
        buf[4] = powershell_args_flag;
        buf[5] = cwd;
        return buf[0..windows_argv_len_uncommitted];
    }
    buf[0] = windows_git_bin;
    buf[1] = git_c_flag;
    buf[2] = cwd;
    buf[3] = git_diff_cmd;
    buf[4] = git_numstat;
    if (lastOperandRange(source, committed_range, last_turn_range)) |operand| {
        buf[5] = operand;
        return buf[0..windows_argv_len];
    }
    return buf[0..windows_argv_len_unstaged];
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

/// LastTurn numstat. Operand is one own argv slot.
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
    return switch (builtin.os.tag) {
        .windows => windowsArgvForSourceRangeWith(source, committed_range, last_turn_range, cwd, buf),
        else => unixArgvForSourceRangeWith(source, committed_range, last_turn_range, cwd, buf),
    };
}

pub fn unixArgvForHunk(
    source: Source,
    committed_range: CommittedRange,
    cwd: []const u8,
    path: []const u8,
    buf: *[argv_len_hunk][]const u8,
) []const []const u8 {
    return unixArgvForHunkRange(source, committed_range, "", cwd, path, buf);
}

pub fn unixArgvForHunkLastTurn(
    cwd: []const u8,
    last_turn_range: []const u8,
    path: []const u8,
    buf: *[argv_len_hunk][]const u8,
) []const []const u8 {
    return unixArgvForHunkRange(.last_turn, .origin, last_turn_range, cwd, path, buf);
}

/// `/bin/sh -c <chdir> sh <cwd> git diff [operand] -- <path>`.
/// `--` and the path are own argv slots. Never interpolate the
/// path into `-c`.
pub fn unixArgvForHunkRange(
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
        return buf[0..unix_argv_len_hunk];
    }
    buf[7] = git_pathspec_end;
    buf[8] = path;
    return buf[0..unix_argv_len_hunk_unstaged];
}

/// Windows: `git.exe -C <project_path> diff [operand] -- <path>`.
/// `--` and the path are own argv slots. Unstaged omits the operand.
pub fn windowsArgvForHunkRange(
    source: Source,
    committed_range: CommittedRange,
    last_turn_range: []const u8,
    cwd: []const u8,
    path: []const u8,
    buf: *[argv_len_hunk][]const u8,
) []const []const u8 {
    buf[0] = windows_git_bin;
    buf[1] = git_c_flag;
    buf[2] = cwd;
    buf[3] = git_diff_cmd;
    if (hunkOperandRange(source, committed_range, last_turn_range)) |operand| {
        buf[4] = operand;
        buf[5] = git_pathspec_end;
        buf[6] = path;
        return buf[0..windows_argv_len_hunk];
    }
    buf[4] = git_pathspec_end;
    buf[5] = path;
    return buf[0..windows_argv_len_hunk_unstaged];
}

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
    return switch (builtin.os.tag) {
        .windows => windowsArgvForHunkRange(source, committed_range, last_turn_range, cwd, path, buf),
        else => unixArgvForHunkRange(source, committed_range, last_turn_range, cwd, path, buf),
    };
}

/// `/bin/sh -c <chdir> sh <cwd> git diff --no-index -- /dev/null <path>`.
/// `--no-index`, `--`, `/dev/null`, and the path are own argv slots.
/// Never interpolate the path (or `/dev/null`) into `-c`.
pub fn unixArgvForUntrackedHunk(
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
    return buf[0..unix_argv_len_hunk_untracked];
}

/// Windows: `git.exe -C <project_path> diff --no-index -- NUL <path>`.
/// `--no-index`, `--`, `NUL`, and the path are own argv slots.
/// Never interpolate the path (or `NUL`) into a script.
pub fn windowsArgvForUntrackedHunk(
    cwd: []const u8,
    path: []const u8,
    buf: *[argv_len_hunk_untracked][]const u8,
) []const []const u8 {
    buf[0] = windows_git_bin;
    buf[1] = git_c_flag;
    buf[2] = cwd;
    buf[3] = git_diff_cmd;
    buf[4] = git_no_index;
    buf[5] = git_pathspec_end;
    buf[6] = git_nul;
    buf[7] = path;
    return buf[0..windows_argv_len_hunk_untracked];
}

pub fn argvForUntrackedHunk(
    cwd: []const u8,
    path: []const u8,
    buf: *[argv_len_hunk_untracked][]const u8,
) []const []const u8 {
    return switch (builtin.os.tag) {
        .windows => windowsArgvForUntrackedHunk(cwd, path, buf),
        else => unixArgvForUntrackedHunk(cwd, path, buf),
    };
}

/// Branch argv. `open` still uses this shape. Diff tab / header +/-
/// default to Uncommitted via `ensureDiff`.
pub fn unixArgvFor(cwd: []const u8, buf: *[argv_len][]const u8) []const []const u8 {
    return unixArgvForSource(.branch, cwd, buf);
}

pub fn windowsArgvFor(cwd: []const u8, buf: *[argv_len][]const u8) []const []const u8 {
    return windowsArgvForSourceRangeWith(.branch, .origin, "", cwd, buf);
}

pub fn argvFor(cwd: []const u8, buf: *[argv_len][]const u8) []const []const u8 {
    return argvForSource(.branch, cwd, buf);
}

fn isUnixGitReviewUncommittedArgv(argv: []const []const u8) bool {
    if (argv.len != unix_argv_len_uncommitted) return false;
    if (!std.mem.eql(u8, argv[0], sh_bin)) return false;
    if (!std.mem.eql(u8, argv[1], "-c")) return false;
    if (!std.mem.eql(u8, argv[2], main.fx_ask_chdir_script)) return false;
    if (!std.mem.eql(u8, argv[5], sh_bin)) return false;
    if (!std.mem.eql(u8, argv[6], "-c")) return false;
    return std.mem.eql(u8, argv[7], uncommitted_untracked_script);
}

fn isWindowsGitReviewUncommittedArgv(argv: []const []const u8) bool {
    if (argv.len != windows_argv_len_uncommitted) return false;
    if (!std.mem.eql(u8, argv[0], powershell_bin)) return false;
    if (!std.mem.eql(u8, argv[1], powershell_noprofile)) return false;
    if (!std.mem.eql(u8, argv[2], powershell_command)) return false;
    if (!std.mem.eql(u8, argv[3], powershell_uncommitted_untracked_script)) return false;
    if (!std.mem.eql(u8, argv[4], powershell_args_flag)) return false;
    if (argv[5].len == 0) return false;
    if (!scriptHas(argv[3], "$args[0]")) return false;
    if (!scriptHas(argv[3], windows_git_bin)) return false;
    if (!scriptHas(argv[3], git_diff_cmd)) return false;
    if (!scriptHas(argv[3], git_numstat)) return false;
    if (!scriptHas(argv[3], git_head)) return false;
    if (!scriptHas(argv[3], git_ls_files_cmd)) return false;
    if (!scriptHas(argv[3], git_ls_files_others)) return false;
    if (!scriptHas(argv[3], git_ls_files_exclude_standard)) return false;
    if (scriptHas(argv[3], "--name-status")) return false;
    if (scriptHas(argv[3], "1048576")) return false;
    return true;
}

pub fn isGitReviewUncommittedArgv(argv: []const []const u8) bool {
    return isUnixGitReviewUncommittedArgv(argv) or isWindowsGitReviewUncommittedArgv(argv);
}

fn isUnixGitReviewDiffArgv(argv: []const []const u8) bool {
    if (argv.len != unix_argv_len and argv.len != unix_argv_len_unstaged) return false;
    if (!std.mem.eql(u8, argv[0], sh_bin)) return false;
    if (!std.mem.eql(u8, argv[1], "-c")) return false;
    if (!std.mem.eql(u8, argv[2], main.fx_ask_chdir_script)) return false;
    if (!std.mem.eql(u8, argv[5], git_bin)) return false;
    if (!std.mem.eql(u8, argv[6], git_diff_cmd)) return false;
    if (!std.mem.eql(u8, argv[7], git_numstat)) return false;
    if (argv.len == unix_argv_len_unstaged) return true;
    return isKnownNumstatOperand(argv[8]);
}

fn isWindowsGitReviewDiffArgv(argv: []const []const u8) bool {
    if (argv.len != windows_argv_len and argv.len != windows_argv_len_unstaged) return false;
    if (!windowsGitBinOk(argv[0])) return false;
    if (!std.mem.eql(u8, argv[1], git_c_flag)) return false;
    if (argv[2].len == 0) return false;
    if (!std.mem.eql(u8, argv[3], git_diff_cmd)) return false;
    if (!std.mem.eql(u8, argv[4], git_numstat)) return false;
    if (argv.len == windows_argv_len_unstaged) return true;
    return isKnownNumstatOperand(argv[5]);
}

pub fn isGitReviewDiffArgv(argv: []const []const u8) bool {
    if (isGitReviewUncommittedArgv(argv)) return true;
    return isUnixGitReviewDiffArgv(argv) or isWindowsGitReviewDiffArgv(argv);
}

fn isUnixGitReviewHunkArgv(argv: []const []const u8) bool {
    if (argv.len != unix_argv_len_hunk and
        argv.len != unix_argv_len_hunk_unstaged and
        argv.len != unix_argv_len_hunk_untracked) return false;
    if (!std.mem.eql(u8, argv[0], sh_bin)) return false;
    if (!std.mem.eql(u8, argv[1], "-c")) return false;
    if (!std.mem.eql(u8, argv[2], main.fx_ask_chdir_script)) return false;
    if (!std.mem.eql(u8, argv[5], git_bin)) return false;
    if (!std.mem.eql(u8, argv[6], git_diff_cmd)) return false;
    if (argv.len == unix_argv_len_hunk_untracked) {
        return std.mem.eql(u8, argv[7], git_no_index) and
            std.mem.eql(u8, argv[8], git_pathspec_end) and
            std.mem.eql(u8, argv[9], git_dev_null);
    }
    if (argv.len == unix_argv_len_hunk_unstaged) {
        return std.mem.eql(u8, argv[7], git_pathspec_end);
    }
    return isKnownHunkOperand(argv[7]) and std.mem.eql(u8, argv[8], git_pathspec_end);
}

fn isWindowsGitReviewHunkArgv(argv: []const []const u8) bool {
    if (argv.len != windows_argv_len_hunk and
        argv.len != windows_argv_len_hunk_unstaged and
        argv.len != windows_argv_len_hunk_untracked) return false;
    if (!windowsGitBinOk(argv[0])) return false;
    if (!std.mem.eql(u8, argv[1], git_c_flag)) return false;
    if (argv[2].len == 0) return false;
    if (!std.mem.eql(u8, argv[3], git_diff_cmd)) return false;
    if (argv.len == windows_argv_len_hunk_untracked) {
        return std.mem.eql(u8, argv[4], git_no_index) and
            std.mem.eql(u8, argv[5], git_pathspec_end) and
            std.mem.eql(u8, argv[6], git_nul);
    }
    if (argv.len == windows_argv_len_hunk_unstaged) {
        return std.mem.eql(u8, argv[4], git_pathspec_end);
    }
    return isKnownHunkOperand(argv[4]) and std.mem.eql(u8, argv[5], git_pathspec_end);
}

/// Hunk argv: Unix chdir + `git diff [operand] -- <path>`, or the
/// 11-slot untracked `git diff --no-index -- /dev/null <path>`;
/// Windows `git.exe -C` tracked hunks or 8-slot untracked
/// `git.exe -C PATH diff --no-index -- NUL <path>`. Rejects
/// file-list (`--numstat`) and Uncommitted nested `sh -c`
/// / PowerShell.
pub fn isGitReviewHunkArgv(argv: []const []const u8) bool {
    return isUnixGitReviewHunkArgv(argv) or isWindowsGitReviewHunkArgv(argv);
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

/// One `added\tdeleted\tpath` numstat row from daemon ReviewDiffData.
/// Rename dest after a third tab. Binary `-` columns still yield a
/// file (`M`) with that column counted as 0. Untracked synthetic
/// `N\t0\tpath` is `?` with additions 0. Blank / malformed lines are
/// omitted.
pub fn parseNumstatFileLine(raw: []const u8) ?struct { status: u8, path: []const u8, additions: u64, deletions: u64 } {
    const line = std.mem.trim(u8, raw, " \t\r\n");
    if (line.len == 0) return null;
    const first_tab = std.mem.indexOfScalar(u8, line, '\t') orelse return null;
    const added_s = std.mem.trim(u8, line[0..first_tab], " \t");
    const rest = line[first_tab + 1 ..];
    const second_tab = std.mem.indexOfScalar(u8, rest, '\t') orelse return null;
    const deleted_s = std.mem.trim(u8, rest[0..second_tab], " \t");
    var path = std.mem.trim(u8, rest[second_tab + 1 ..], " \t");
    if (path.len == 0) return null;
    const additions = parseNumstatCount(added_s);
    const deletions = parseNumstatCount(deleted_s);
    if (std.mem.indexOfScalar(u8, path, '\t')) |third| {
        const dest = std.mem.trim(u8, path[third + 1 ..], " \t");
        if (dest.len > 0) return .{ .status = 'R', .path = dest, .additions = additions, .deletions = deletions };
        path = std.mem.trim(u8, path[0..third], " \t");
        if (path.len == 0) return null;
    }
    const added_zero = std.mem.eql(u8, added_s, "0");
    const deleted_zero = std.mem.eql(u8, deleted_s, "0");
    const binary = std.mem.eql(u8, added_s, "-") or std.mem.eql(u8, deleted_s, "-");
    const untracked = std.mem.eql(u8, added_s, "N") and deleted_zero;
    const status: u8 = if (untracked)
        '?'
    else if (binary)
        'M'
    else if (added_zero and !deleted_zero)
        'D'
    else if (deleted_zero and !added_zero)
        'A'
    else
        'M';
    return .{ .status = status, .path = path, .additions = additions, .deletions = deletions };
}

/// Binary `-` and untracked `N` columns are 0. Non-decimal stays 0
/// so today's status-letter mapping is unchanged.
fn parseNumstatCount(raw: []const u8) u64 {
    if (std.mem.eql(u8, raw, "-") or std.mem.eql(u8, raw, "N")) return 0;
    return std.fmt.parseInt(u64, raw, 10) catch 0;
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
    const file_n = model.review_diff_file_count;
    if (file_n == 0) return &.{};

    var path_buf: [max_review_diff_files][]const u8 = undefined;
    var dir_buf: [max_review_diff_dirs][]const u8 = undefined;
    const dir_n = collectDirParents(model, &path_buf, &dir_buf);

    var indexes: [max_review_diff_files]usize = undefined;
    var i: usize = 0;
    while (i < file_n) : (i += 1) indexes[i] = i;
    std.mem.sort(usize, indexes[0..file_n], model, fileIndexLessThan);

    var expanded_buf: [max_review_diff_dirs][]const u8 = undefined;
    const expanded = expandedKeys(model, &expanded_buf);
    const filter = pathFilter(model);
    const filtering = filter.len > 0;

    const cap = file_n + dir_n;
    const out = arena.alloc(ReviewDiffRow, cap) catch return &.{};
    var n: usize = 0;
    var emitted_n: usize = 0;
    var emitted: [max_review_diff_dirs][]const u8 = undefined;

    for (indexes[0..file_n]) |file_index| {
        const file = &model.review_diff_file_store[file_index];
        const path = file.path();
        if (!pathFilterMatches(path, filter)) continue;
        var start: usize = 0;
        var depth: u32 = 0;
        var visible = true;
        while (std.mem.indexOfScalarPos(u8, path, start, '/')) |slash| {
            const directory = path[0..slash];
            const dir_expanded = filtering or containsKey(expanded, directory);
            if (visible and !containsKey(emitted[0..emitted_n], directory)) {
                if (emitted_n < emitted.len) {
                    emitted[emitted_n] = directory;
                    emitted_n += 1;
                }
                if (dirIdOf(dir_buf[0..dir_n], directory)) |id| {
                    if (n < out.len) {
                        out[n] = makeDirRow(directory, id, depth, dir_expanded);
                        n += 1;
                    }
                }
            }
            if (!dir_expanded) {
                visible = false;
                break;
            }
            start = slash + 1;
            depth += 1;
        }
        if (visible and n < out.len) {
            out[n] = makeFileRow(arena, model, file, @intCast(file_index + 1), depth);
            n += 1;
        }
    }
    return out[0..n];
}

fn signedCountLabel(arena: std.mem.Allocator, sign: u8, count: u64) []const u8 {
    return std.fmt.allocPrint(arena, "{c}{d}", .{ sign, count }) catch "";
}

fn fileIndexLessThan(model: *const Model, a: usize, b: usize) bool {
    const order = pathOrderIgnoreCase(model.review_diff_file_store[a].path(), model.review_diff_file_store[b].path());
    if (order != .eq) return order == .lt;
    return a < b;
}

fn pathOrderIgnoreCase(a: []const u8, b: []const u8) std.math.Order {
    const n = @min(a.len, b.len);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const ca = std.ascii.toLower(a[i]);
        const cb = std.ascii.toLower(b[i]);
        if (ca < cb) return .lt;
        if (ca > cb) return .gt;
    }
    if (a.len < b.len) return .lt;
    if (a.len > b.len) return .gt;
    return .eq;
}

fn makeDirRow(path: []const u8, id: u32, depth: u32, expanded: bool) ReviewDiffRow {
    const indent = @as(f32, @floatFromInt(depth)) * tree_indent_step;
    return .{
        .id = id,
        .label = composer.fileMentionBasename(path),
        .is_directory = true,
        .expanded = expanded,
        .depth = depth,
        .has_indent = indent > 0,
        .indent = indent,
    };
}

fn makeFileRow(arena: std.mem.Allocator, model: *const Model, file: *const ChangedFile, id: u32, depth: u32) ReviewDiffRow {
    const basename = composer.fileMentionBasename(file.path());
    const label = std.fmt.allocPrint(arena, "{c} {s}", .{ file.status, basename }) catch file.label();
    const indent = @as(f32, @floatFromInt(depth)) * tree_indent_step + tree_file_indent_extra;
    var row: ReviewDiffRow = .{
        .id = id,
        .label = label,
        .selected = model.review_diff_selected_id == id,
        .additions_label = if (file.additions > 0) signedCountLabel(arena, '+', file.additions) else "",
        .deletions_label = if (file.deletions > 0) signedCountLabel(arena, '-', file.deletions) else "",
        .depth = depth,
        .has_indent = indent > 0,
        .indent = indent,
    };
    row.has_additions = row.additions_label.len != 0;
    row.has_deletions = row.deletions_label.len != 0;
    return row;
}

fn collectDirParents(
    model: *const Model,
    path_buf: *[max_review_diff_files][]const u8,
    dir_buf: *[max_review_diff_dirs][]const u8,
) usize {
    const n = @min(model.review_diff_file_count, max_review_diff_files);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        path_buf[i] = model.review_diff_file_store[i].path();
    }
    return file_mention.collectDerivedDirParents(path_buf[0..n], dir_buf);
}

fn dirIdOf(dirs: []const []const u8, path: []const u8) ?u32 {
    for (dirs, 0..) |dir, i| {
        if (std.mem.eql(u8, dir, path)) return review_diff_dir_id_base + @as(u32, @intCast(i));
    }
    return null;
}

pub fn dirId(index: usize) u32 {
    return review_diff_dir_id_base + @as(u32, @intCast(index));
}

fn expandedKeys(model: *const Model, buf: [][]const u8) []const []const u8 {
    const n = @min(model.review_diff_expanded_count, buf.len);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        buf[i] = model.review_diff_expanded_store[i].text();
    }
    return buf[0..n];
}

fn containsKey(keys: []const []const u8, needle: []const u8) bool {
    for (keys) |item| {
        if (std.mem.eql(u8, item, needle)) return true;
    }
    return false;
}

fn indexOfExpanded(model: *const Model, key: []const u8) ?usize {
    var i: usize = 0;
    while (i < model.review_diff_expanded_count) : (i += 1) {
        if (std.mem.eql(u8, model.review_diff_expanded_store[i].text(), key)) return i;
    }
    return null;
}

fn removeExpandedAt(model: *Model, index: usize) void {
    if (index >= model.review_diff_expanded_count) return;
    var i = index;
    while (i + 1 < model.review_diff_expanded_count) : (i += 1) {
        model.review_diff_expanded_store[i] = model.review_diff_expanded_store[i + 1];
    }
    model.review_diff_expanded_count -= 1;
}

fn clearExpanded(model: *Model) void {
    model.review_diff_expanded_count = 0;
}

/// Toggle a Diff directory row. File ids and missing dir ids are
/// no-ops. Cap is `max_review_diff_dirs`. Paint-only — does not
/// re-probe CollectReviewDiff / numstat.
pub fn toggleDir(model: *Model, id: u32) void {
    if (id < review_diff_dir_id_base) return;
    const dir_index = id - review_diff_dir_id_base;
    var path_buf: [max_review_diff_files][]const u8 = undefined;
    var dir_buf: [max_review_diff_dirs][]const u8 = undefined;
    const dir_n = collectDirParents(model, &path_buf, &dir_buf);
    if (dir_index >= dir_n) return;
    const key = dir_buf[dir_index];
    if (key.len == 0) return;
    if (indexOfExpanded(model, key)) |index| {
        removeExpandedAt(model, index);
        return;
    }
    if (model.review_diff_expanded_count >= max_review_diff_dirs) return;
    model.review_diff_expanded_store[model.review_diff_expanded_count].set(key);
    model.review_diff_expanded_count += 1;
}

/// Trimmed Waku `right_panel_diff_filter`. Empty / whitespace-only
/// is no filter (collapsed-by-default tree).
pub fn pathFilter(model: *const Model) []const u8 {
    return std.mem.trim(u8, model.review_diff_filter_buffer.text(), " \t\r\n");
}

fn pathFilterMatches(path: []const u8, query: []const u8) bool {
    if (query.len == 0) return true;
    return main.asciiContainsIgnoreCase(path, query);
}

pub fn applyFilter(model: *Model, edit: native_sdk.canvas.TextInputEvent) void {
    model.review_diff_filter_buffer.apply(edit);
}

pub fn clearFilter(model: *Model) void {
    model.review_diff_filter_buffer.clear();
}

/// Drop the runtime path filter when leaving the Diff surface
/// (tab switch / panel hide). Matches Usage Projects
/// `leaveUsage`.
pub fn leaveSurface(model: *Model) void {
    clearFilter(model);
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

pub fn hasReviewDiffHunkRows(model: *const Model) bool {
    return model.review_diff_visible_count > 0;
}

fn lineContent(model: *const Model, line: DiffLine) []const u8 {
    const off = @min(@as(usize, line.content_off), model.review_diff_hunk_len);
    const len = @min(@as(usize, line.content_len), model.review_diff_hunk_len - off);
    return model.review_diff_hunk_storage[off .. off + len];
}

fn gapIsExpandable(line: DiffLine) bool {
    return line.kind == .gap and line.gap_count > 0 and line.hidden_len == line.gap_count;
}

fn gapLabel(arena: std.mem.Allocator, count: u32) []const u8 {
    if (count == 1) return "1 unmodified line";
    var buf: [max_review_diff_gap_label]u8 = undefined;
    const label = std.fmt.bufPrint(&buf, "{d} unmodified lines", .{count}) catch return "";
    const out = arena.alloc(u8, label.len) catch return "";
    @memcpy(out, label);
    return out;
}

pub fn reviewDiffHunkRows(model: *const Model, arena: std.mem.Allocator) []const ReviewDiffHunkRow {
    const n = model.review_diff_visible_count;
    if (n == 0) return &.{};
    const out = arena.alloc(ReviewDiffHunkRow, n) catch return &.{};
    var written: usize = 0;
    for (model.review_diff_visible_store[0..n], 0..) |line, i| {
        if (line.kind == .file_header) continue;
        var row: ReviewDiffHunkRow = .{
            .id = @intCast(i + 1),
            .text = lineContent(model, line),
        };
        switch (line.kind) {
            .addition => row.is_addition = true,
            .deletion => row.is_deletion = true,
            .gap => {
                row.is_gap = true;
                row.text = gapLabel(arena, line.gap_count);
                if (gapIsExpandable(line)) {
                    const chunked = line.gap_count > default_expansion_line_count;
                    row.can_expand_all = true;
                    switch (line.gap_position) {
                        .leading => row.can_expand_end = true,
                        .trailing => row.can_expand_start = true,
                        .between => {
                            if (chunked) {
                                row.can_expand_start = true;
                                row.can_expand_end = true;
                            } else {
                                row.can_expand_both = true;
                            }
                        },
                    }
                }
            },
            else => {},
        }
        if (line.kind == .context or line.kind == .addition or line.kind == .deletion) {
            const shown = if (line.new_line != 0) line.new_line else line.old_line;
            if (shown != 0) {
                row.line_number = std.fmt.allocPrint(arena, "{d}", .{shown}) catch "";
                row.has_line_number = row.line_number.len != 0;
            }
        }
        out[written] = row;
        written += 1;
    }
    return out[0..written];
}

fn parseHunkStarts(line: []const u8) ?struct { old: u32, new: u32 } {
    const after = if (std.mem.startsWith(u8, line, "@@ ")) line[3..] else return null;
    const ranges = if (std.mem.indexOf(u8, after, " @@")) |at| after[0..at] else return null;
    var it = std.mem.tokenizeScalar(u8, ranges, ' ');
    const old_part = it.next() orelse return null;
    const new_part = it.next() orelse return null;
    const old_body = if (std.mem.startsWith(u8, old_part, "-")) old_part[1..] else return null;
    const new_body = if (std.mem.startsWith(u8, new_part, "+")) new_part[1..] else return null;
    const old = parseRangeStart(old_body) orelse return null;
    const new = parseRangeStart(new_body) orelse return null;
    return .{ .old = old, .new = new };
}

fn parseRangeStart(range: []const u8) ?u32 {
    const start = if (std.mem.indexOfScalar(u8, range, ',')) |comma| range[0..comma] else range;
    return std.fmt.parseInt(u32, start, 10) catch null;
}

fn pushParsed(lines: []DiffLine, n: *usize, line: DiffLine) bool {
    if (n.* >= lines.len) return false;
    lines[n.*] = line;
    n.* += 1;
    return true;
}

fn parsePatchLines(patch: []const u8, complete_context: bool, lines: []DiffLine, next_gap_id: *u32) usize {
    var n: usize = 0;
    var old_line: u32 = 0;
    var new_line: u32 = 0;
    var previous_old_next: u32 = 1;
    var previous_new_next: u32 = 1;
    var positioned = true;
    var offset: usize = 0;
    while (offset < patch.len) {
        const rest = patch[offset..];
        const line_end = std.mem.indexOfScalar(u8, rest, '\n') orelse rest.len;
        const raw = rest[0..line_end];
        const line_off: u32 = @intCast(offset);
        const next_off = if (line_end == rest.len) patch.len else offset + line_end + 1;
        defer offset = next_off;

        if (std.mem.startsWith(u8, raw, "diff --git ")) {
            old_line = 0;
            new_line = 0;
            previous_old_next = 1;
            previous_new_next = 1;
            positioned = true;
            _ = pushParsed(lines, &n, .{
                .kind = .file_header,
                .content_off = line_off,
                .content_len = @intCast(@min(raw.len, std.math.maxInt(u16))),
            });
            continue;
        }
        if (std.mem.startsWith(u8, raw, "new file mode ") or
            std.mem.startsWith(u8, raw, "deleted file mode ") or
            std.mem.startsWith(u8, raw, "index ") or
            std.mem.startsWith(u8, raw, "--- ") or
            std.mem.startsWith(u8, raw, "+++ ") or
            std.mem.startsWith(u8, raw, "old mode ") or
            std.mem.startsWith(u8, raw, "new mode "))
        {
            continue;
        }
        if (std.mem.startsWith(u8, raw, "Binary files ") or std.mem.eql(u8, raw, "GIT binary patch")) {
            _ = pushParsed(lines, &n, .{
                .kind = .meta,
                .content_off = line_off,
                .content_len = @intCast(@min(raw.len, std.math.maxInt(u16))),
            });
            continue;
        }

        if (std.mem.startsWith(u8, raw, "@@") and parseHunkStarts(raw) == null) {
            positioned = false;
            continue;
        }

        if (parseHunkStarts(raw)) |starts| {
            positioned = true;
            const old_gap = starts.old -| previous_old_next;
            const new_gap = starts.new -| previous_new_next;
            const gap = @max(old_gap, new_gap);
            if (!complete_context and gap > 0) {
                const first_hunk = previous_old_next == 1 and previous_new_next == 1;
                _ = pushParsed(lines, &n, .{
                    .kind = .gap,
                    .gap_position = if (first_hunk) .leading else .between,
                    .gap_id = next_gap_id.*,
                    .gap_count = gap,
                });
                next_gap_id.* +%= 1;
            } else if (!complete_context and (previous_old_next != 1 or previous_new_next != 1)) {
                _ = pushParsed(lines, &n, .{
                    .kind = .hunk_header,
                    .content_off = line_off,
                    .content_len = @intCast(@min(raw.len, std.math.maxInt(u16))),
                });
            }
            old_line = starts.old;
            new_line = starts.new;
            continue;
        }

        if (raw.len == 0) continue;
        const marker = raw[0];
        var kind: LineKind = undefined;
        var shown_old: u32 = 0;
        var shown_new: u32 = 0;
        switch (marker) {
            ' ' => {
                kind = .context;
                if (positioned) {
                    shown_old = old_line;
                    shown_new = new_line;
                }
                old_line +|= 1;
                new_line +|= 1;
            },
            '-' => {
                kind = .deletion;
                if (positioned) shown_old = old_line;
                old_line +|= 1;
            },
            '+' => {
                kind = .addition;
                if (positioned) shown_new = new_line;
                new_line +|= 1;
            },
            '\\' => {
                kind = .meta;
            },
            else => continue,
        }
        previous_old_next = old_line;
        previous_new_next = new_line;
        // Waku `Line.content = raw.get(1..)` for code rows; Meta keeps
        // the full raw line (Waku Meta has empty tokens; not a code row).
        const skip_marker = kind == .context or kind == .addition or kind == .deletion;
        const body = if (skip_marker) raw[1..] else raw;
        const content_off: u32 = if (skip_marker) line_off + 1 else line_off;
        const content_len: u16 = @intCast(@min(body.len, std.math.maxInt(u16)));
        _ = pushParsed(lines, &n, .{
            .kind = kind,
            .old_line = shown_old,
            .new_line = shown_new,
            .content_off = content_off,
            .content_len = content_len,
        });
    }
    return n;
}

fn isChangeLine(line: DiffLine) bool {
    return line.kind == .addition or line.kind == .deletion;
}

fn ensureHeapSlice(comptime T: type, slot: *[]T, cap: usize) bool {
    if (slot.len == cap) return true;
    if (slot.len != 0) {
        std.heap.page_allocator.free(slot.*);
        slot.* = &.{};
    }
    const buf = std.heap.page_allocator.alloc(T, cap) catch return false;
    slot.* = buf;
    return true;
}

fn freeHeapSlice(comptime T: type, slot: *[]T) void {
    if (slot.len != 0) {
        std.heap.page_allocator.free(slot.*);
        slot.* = &.{};
    }
}

fn ensureHunkBodyStore(model: *Model) bool {
    return ensureHeapSlice(u8, &model.review_diff_hunk_storage, max_review_diff_hunk);
}

fn ensureHunkRowStores(model: *Model) bool {
    return ensureHeapSlice(DiffLine, &model.review_diff_visible_store, max_rendered_diff_lines) and
        ensureHeapSlice(DiffLine, &model.review_diff_hidden_store, max_review_diff_hidden_lines);
}

fn ensureDaemonPatchStore(model: *Model) bool {
    return ensureHeapSlice(u8, &model.review_diff_daemon_patch_storage, max_review_diff_daemon_patch);
}

/// Drop heap last-windows. Called from close so `Model` copies and
/// tests do not keep 50_000-row tables after the Review card goes away.
fn freeReviewDiffStores(model: *Model) void {
    freeHeapSlice(u8, &model.review_diff_hunk_storage);
    model.review_diff_hunk_len = 0;
    model.review_diff_hunk_line_count = 0;
    freeHeapSlice(DiffLine, &model.review_diff_visible_store);
    model.review_diff_visible_count = 0;
    freeHeapSlice(DiffLine, &model.review_diff_hidden_store);
    model.review_diff_hidden_count = 0;
    freeHeapSlice(u8, &model.review_diff_daemon_patch_storage);
    model.review_diff_daemon_patch_len = 0;
}

fn copyHidden(model: *Model, src: []const DiffLine) ?struct { off: u32, len: u32 } {
    if (src.len == 0) return null;
    const off = model.review_diff_hidden_count;
    if (off + src.len > max_review_diff_hidden_lines) return null;
    @memcpy(model.review_diff_hidden_store[off .. off + src.len], src);
    model.review_diff_hidden_count = off + src.len;
    return .{ .off = @intCast(off), .len = @intCast(src.len) };
}

fn pushVisible(model: *Model, line: DiffLine) bool {
    if (model.review_diff_visible_count >= max_rendered_diff_lines) {
        model.review_diff_truncated = true;
        return false;
    }
    model.review_diff_visible_store[model.review_diff_visible_count] = line;
    model.review_diff_visible_count += 1;
    return true;
}

fn pushVisibleSlice(model: *Model, src: []const DiffLine) bool {
    for (src) |line| {
        if (!pushVisible(model, line)) return false;
    }
    return true;
}

fn pushContextGap(model: *Model, hidden: []const DiffLine, position: GapPosition, next_gap_id: *u32) bool {
    if (hidden.len == 0) return true;
    const stored = copyHidden(model, hidden) orelse {
        return pushVisibleSlice(model, hidden);
    };
    const count: u32 = @intCast(hidden.len);
    return pushVisible(model, .{
        .kind = .gap,
        .gap_position = position,
        .gap_id = next_gap_id.*,
        .gap_count = count,
        .hidden_off = stored.off,
        .hidden_len = stored.len,
    });
}

fn collapseLeading(model: *Model, run: []const DiffLine, next_gap_id: *u32) bool {
    const kept = @min(collapsed_context_lines, run.len);
    const hidden = run[0 .. run.len - kept];
    if (hidden.len <= collapsed_context_threshold) return pushVisibleSlice(model, run);
    if (!pushContextGap(model, hidden, .leading, next_gap_id)) return false;
    next_gap_id.* +%= 1;
    return pushVisibleSlice(model, run[run.len - kept ..]);
}

fn collapseTrailing(model: *Model, run: []const DiffLine, next_gap_id: *u32) bool {
    const kept = @min(collapsed_context_lines, run.len);
    const hidden = run[kept..];
    if (hidden.len <= collapsed_context_threshold) return pushVisibleSlice(model, run);
    if (!pushVisibleSlice(model, run[0..kept])) return false;
    if (!pushContextGap(model, hidden, .trailing, next_gap_id)) return false;
    next_gap_id.* +%= 1;
    return true;
}

fn collapseBetween(model: *Model, run: []const DiffLine, next_gap_id: *u32) bool {
    const kept_start = @min(collapsed_context_lines, run.len);
    const kept_end = @min(collapsed_context_lines, run.len - kept_start);
    const hidden = run[kept_start .. run.len - kept_end];
    if (hidden.len <= collapsed_context_threshold) return pushVisibleSlice(model, run);
    if (!pushVisibleSlice(model, run[0..kept_start])) return false;
    if (!pushContextGap(model, hidden, .between, next_gap_id)) return false;
    next_gap_id.* +%= 1;
    return pushVisibleSlice(model, run[run.len - kept_end ..]);
}

fn collapseContext(model: *Model, lines: []const DiffLine, next_gap_id: *u32) void {
    const n = lines.len;
    const change_after = std.heap.page_allocator.alloc(bool, n + 1) catch {
        _ = pushVisibleSlice(model, lines);
        return;
    };
    defer std.heap.page_allocator.free(change_after);
    change_after[n] = false;
    var i: usize = n;
    while (i > 0) {
        i -= 1;
        change_after[i] = change_after[i + 1] or isChangeLine(lines[i]);
    }
    var saw_change = false;
    var index: usize = 0;
    while (index < n) {
        if (lines[index].kind != .context) {
            saw_change = saw_change or isChangeLine(lines[index]);
            if (!pushVisible(model, lines[index])) return;
            index += 1;
            continue;
        }
        const run_start = index;
        while (index < n and lines[index].kind == .context) : (index += 1) {}
        const run = lines[run_start..index];
        const has_later_change = change_after[index];
        const ok = switch (saw_change) {
            false => if (has_later_change)
                collapseLeading(model, run, next_gap_id)
            else
                pushVisibleSlice(model, run),
            true => if (has_later_change)
                collapseBetween(model, run, next_gap_id)
            else
                collapseTrailing(model, run, next_gap_id),
        };
        if (!ok) return;
    }
}

fn clearHunkRows(model: *Model) void {
    model.review_diff_visible_count = 0;
    model.review_diff_hidden_count = 0;
    model.review_diff_next_gap_id = 0;
    model.review_diff_truncated = false;
}

fn rebuildHunkRows(model: *Model) void {
    clearHunkRows(model);
    const patch = reviewDiffHunk(model);
    if (patch.len == 0) return;
    if (!ensureHunkRowStores(model)) return;
    const parsed = std.heap.page_allocator.alloc(DiffLine, max_review_diff_hunk_lines) catch return;
    defer std.heap.page_allocator.free(parsed);
    var next_gap_id: u32 = 0;
    const n = parsePatchLines(patch, model.review_diff_complete_context, parsed, &next_gap_id);
    if (model.review_diff_complete_context) {
        collapseContext(model, parsed[0..n], &next_gap_id);
    } else {
        _ = pushVisibleSlice(model, parsed[0..n]);
    }
    model.review_diff_next_gap_id = next_gap_id;
}

fn hiddenSlice(model: *Model, line: DiffLine) []DiffLine {
    const off = @min(@as(usize, line.hidden_off), model.review_diff_hidden_count);
    const len = @min(@as(usize, line.hidden_len), model.review_diff_hidden_count - off);
    return model.review_diff_hidden_store[off .. off + len];
}

fn spliceVisibleParts(
    model: *Model,
    at: usize,
    prefix: []const DiffLine,
    maybe_gap: ?DiffLine,
    suffix: []const DiffLine,
) void {
    const dest = model.review_diff_visible_store;
    const count = model.review_diff_visible_count;
    if (at >= count or dest.len < max_rendered_diff_lines) return;
    const tail_len = count - at - 1;
    const gap_n: usize = if (maybe_gap != null) 1 else 0;
    const repl_len = prefix.len + gap_n + suffix.len;
    var new_count = at + repl_len + tail_len;
    if (new_count > max_rendered_diff_lines) {
        model.review_diff_truncated = true;
        new_count = max_rendered_diff_lines;
    }
    const take_repl = @min(repl_len, new_count - at);
    const keep_tail = @min(tail_len, new_count -| (at + repl_len));

    var remain = take_repl;
    const take_prefix = @min(prefix.len, remain);
    remain -= take_prefix;
    const take_gap: usize = if (gap_n == 1 and remain > 0) 1 else 0;
    remain -= take_gap;
    const take_suffix = @min(suffix.len, remain);

    const tail_src = at + 1;
    const tail_dest = at + take_repl;
    if (keep_tail > 0 and tail_dest != tail_src) {
        const src = dest[tail_src .. tail_src + keep_tail];
        const dst = dest[tail_dest .. tail_dest + keep_tail];
        if (tail_dest > tail_src) {
            std.mem.copyBackwards(DiffLine, dst, src);
        } else {
            std.mem.copyForwards(DiffLine, dst, src);
        }
    }
    if (take_prefix > 0) {
        @memcpy(dest[at .. at + take_prefix], prefix[0..take_prefix]);
    }
    if (take_gap == 1) {
        dest[at + take_prefix] = maybe_gap.?;
    }
    if (take_suffix > 0) {
        const off = at + take_prefix + take_gap;
        @memcpy(dest[off .. off + take_suffix], suffix[0..take_suffix]);
    }
    model.review_diff_visible_count = at + take_repl + keep_tail;
}

fn remainingGapLine(gap: DiffLine, hidden_off: u32, hidden_len: u32) ?DiffLine {
    if (hidden_len == 0) return null;
    var next = gap;
    next.hidden_off = hidden_off;
    next.hidden_len = hidden_len;
    next.gap_count = hidden_len;
    return next;
}

/// Reveal retained hidden context. No git spawn. Payload `row_id` is
/// the 1-based visible-row id from `review_diff_hunk_rows`.
pub fn expandGap(model: *Model, row_id: u32, direction: ExpansionDirection) void {
    if (row_id == 0 or row_id > model.review_diff_visible_count) return;
    const idx = row_id - 1;
    var gap = model.review_diff_visible_store[idx];
    if (!gapIsExpandable(gap)) return;

    const visible_without_gap = model.review_diff_visible_count -| 1;
    const available = max_rendered_diff_lines -| visible_without_gap;
    if (available == 0) {
        model.review_diff_truncated = true;
        return;
    }
    const hidden = hiddenSlice(model, gap);
    const requested: usize = switch (direction) {
        .start, .end => default_expansion_line_count,
        .both => default_expansion_line_count * 2,
        .all => hidden.len,
    };
    const reveal_count = @min(@min(requested, hidden.len), available);
    if (reveal_count == 0) return;
    if (direction == .all and reveal_count < hidden.len) model.review_diff_truncated = true;

    var prefix: []const DiffLine = &.{};
    var suffix: []const DiffLine = &.{};
    var remain_gap: ?DiffLine = null;

    switch (direction) {
        .start => {
            prefix = hidden[0..reveal_count];
            gap.hidden_off += @intCast(reveal_count);
            gap.hidden_len -= @intCast(reveal_count);
            gap.gap_count = gap.hidden_len;
            if (gap.hidden_len > 0) remain_gap = gap;
        },
        .end => {
            const split = hidden.len - reveal_count;
            remain_gap = remainingGapLine(gap, gap.hidden_off, @intCast(split));
            suffix = hidden[split..];
        },
        .both => {
            if (reveal_count == hidden.len) {
                prefix = hidden;
            } else {
                const from_start = (reveal_count + 1) / 2;
                const from_end = reveal_count - from_start;
                prefix = hidden[0..from_start];
                const remain_off = gap.hidden_off + @as(u32, @intCast(from_start));
                const remain_len: u32 = @intCast(hidden.len - from_start - from_end);
                remain_gap = remainingGapLine(gap, remain_off, remain_len);
                suffix = hidden[hidden.len - from_end ..];
            }
        },
        .all => {
            if (reveal_count == hidden.len) {
                prefix = hidden;
            } else switch (gap.gap_position) {
                .leading => {
                    const split = hidden.len - reveal_count;
                    remain_gap = remainingGapLine(gap, gap.hidden_off, @intCast(split));
                    suffix = hidden[split..];
                },
                .trailing => {
                    prefix = hidden[0..reveal_count];
                    gap.hidden_off += @intCast(reveal_count);
                    gap.hidden_len -= @intCast(reveal_count);
                    gap.gap_count = gap.hidden_len;
                    if (gap.hidden_len > 0) remain_gap = gap;
                },
                .between => {
                    const from_start = (reveal_count + 1) / 2;
                    const from_end = reveal_count - from_start;
                    prefix = hidden[0..from_start];
                    const remain_off = gap.hidden_off + @as(u32, @intCast(from_start));
                    const remain_len: u32 = if (from_end == 0)
                        @intCast(hidden.len - from_start)
                    else
                        @intCast(hidden.len - from_start - from_end);
                    remain_gap = remainingGapLine(gap, remain_off, remain_len);
                    if (from_end > 0) suffix = hidden[hidden.len - from_end ..];
                },
            }
        },
    }
    spliceVisibleParts(model, idx, prefix, remain_gap, suffix);
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
    clearHunkRows(model);
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

fn clearDaemonPatch(model: *Model) void {
    model.review_diff_daemon_patch_len = 0;
}

fn clearDaemonFlags(model: *Model) void {
    model.review_diff_via_daemon = false;
    model.review_diff_daemon_ok = false;
    model.review_diff_last_via_daemon = false;
    model.review_diff_complete_context = false;
    clearDaemonPatch(model);
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
    return true;
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

/// Cancel any in-flight probe, drop files / status / hunks, and close the card.
pub fn close(model: *Model, fx: *Effects) void {
    cancelInFlight(model, fx);
    cancelHunkInFlight(model, fx);
    clearFiles(model);
    clearStatus(model);
    clearHunks(model);
    clearExpanded(model);
    clearFilter(model);
    model.review_diff_probe_session = 0;
    model.review_diff_probe_path_len = 0;
    model.review_diff_committed_range = .origin;
    clearLastTurnRange(model);
    clearDaemonFlags(model);
    model.review_diff_source = .branch;
    model.review_diff_active = false;
    freeReviewDiffStores(model);
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
    git_checkout.closePushConfirm(model);
    model.closeProjectEdit();
    close(model, fx);
}

fn startProbe(model: *Model, fx: *Effects) void {
    cancelInFlight(model, fx);
    cancelHunkInFlight(model, fx);
    clearFiles(model);
    clearStatus(model);
    clearHunks(model);
    clearDaemonFlags(model);
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

    model.review_diff_probe_session = model.selected;
    writeFixed(&model.review_diff_probe_path_storage, &model.review_diff_probe_path_len, cwd);
    setStatus(model, comparing_status);
    if (shouldPreferDaemon(model) and trySpawnDaemonCollectReviewDiff(model, fx, cwd)) return;
    spawnLocalReviewDiff(model, fx, cwd);
}

fn shouldPreferDaemon(model: *const Model) bool {
    return switch (model.review_diff_source) {
        .branch, .uncommitted, .staged, .unstaged => true,
        .committed => model.review_diff_committed_range == .origin,
        .last_turn => false,
    };
}

fn daemonSource(source: Source) ?protocol.ReviewDiffSource {
    return switch (source) {
        .branch => .branch,
        .uncommitted => .uncommitted,
        .staged => .staged,
        .unstaged => .unstaged,
        .committed => .committed,
        .last_turn => null,
    };
}

/// Best-effort hello + `WorkspaceOperation::CollectReviewDiff` when a
/// daemon address is set. Own daemon spawn key assigned to
/// `review_diff_key` so `applyLine` / `handleExit` still own the
/// probe. Missing address or Native 4 KiB stdin overflow returns
/// false and leaves local numstat.
fn trySpawnDaemonCollectReviewDiff(model: *Model, fx: *Effects, cwd: []const u8) bool {
    const address = store.resolveDaemonMirrorAddress(model);
    if (address.len == 0) return false;
    const source = daemonSource(model.review_diff_source) orelse return false;
    var stdin_buf: [4096]u8 = undefined;
    const stdin = daemon_proxy.writeWorkspaceStdin(&stdin_buf, .{
        .token = model.daemonToken(),
        .operation = .{ .collect_review_diff = .{ .cwd = cwd, .source = source } },
    }) catch return false;

    const key = model.next_daemon_key;
    model.next_daemon_key += 1;
    model.review_diff_key = key;
    model.review_diff_via_daemon = true;
    model.review_diff_daemon_ok = false;
    model.review_diff_last_via_daemon = false;
    fx.spawn(.{
        .key = key,
        .argv = &.{ model.sidecarPath(), daemon_proxy.SUBCOMMAND, address },
        .stdin = stdin,
        .max_line_bytes = main.daemon_line_bytes,
        .on_line = Effects.lineMsg(.fx_line),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
    return true;
}

fn spawnLocalReviewDiff(model: *Model, fx: *Effects, cwd: []const u8) void {
    const key = model.next_review_diff_key;
    model.next_review_diff_key = key + 1;
    model.review_diff_key = key;
    model.review_diff_via_daemon = false;
    model.review_diff_daemon_ok = false;
    model.review_diff_last_via_daemon = false;
    clearDaemonPatch(model);
    model.review_diff_probe_session = model.selected;
    const probed = model.review_diff_probe_path_storage[0..model.review_diff_probe_path_len];
    if (cwd.ptr != probed.ptr) {
        writeFixed(&model.review_diff_probe_path_storage, &model.review_diff_probe_path_len, cwd);
    }

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
/// and one-shot Branch numstat when cwd exists. Missing / Local
/// path still opens the card with `No workspace.` Streaming and
/// in-flight git mutations are a no-op (popover already closed).
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

/// Switch the Review numstat source, cancel any in-flight
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
    model.review_diff_complete_context = false;
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

/// Click a 1-based Review file row. After a daemon CollectReviewDiff
/// fill, filters the stored `patch` for that path (no per-file hunk
/// spawn). Otherwise tracked rows one-shot a hunk probe for the
/// current source (`argvForHunk`). Untracked `?` one-shots
/// `git diff --no-index -- /dev/null <path>` (Unix) or
/// `git.exe -C PATH diff --no-index -- NUL <path>` (Windows).
/// Cancels any in-flight hunk and clears the previous body.
pub fn selectFile(model: *Model, fx: *Effects, id: u32) void {
    if (!model.review_diff_active) return;
    if (id == 0 or id >= review_diff_dir_id_base) return;
    if (id > model.review_diff_file_count) return;
    const file = &model.review_diff_file_store[id - 1];
    cancelHunkInFlight(model, fx);
    clearHunkBody(model);
    clearHunkStatus(model);
    model.review_diff_selected_id = id;
    if (model.review_diff_last_via_daemon) {
        paintDaemonHunk(model, file.path());
        return;
    }
    const no_index = file.status == '?' and model.review_diff_source != .last_turn;
    startHunkProbe(model, fx, file.path(), no_index);
}

fn paintDaemonHunk(model: *Model, file_path: []const u8) void {
    const patch = model.review_diff_daemon_patch_storage[0..model.review_diff_daemon_patch_len];
    const extracted = extractFilePatch(patch, file_path);
    if (extracted.len == 0) {
        setHunkStatus(model, hunk_empty_status);
        return;
    }
    var it = std.mem.splitScalar(u8, extracted, '\n');
    while (it.next()) |line| {
        appendHunkLine(model, line);
    }
    if (model.review_diff_hunk_len == 0) {
        setHunkStatus(model, hunk_empty_status);
        return;
    }
    rebuildHunkRows(model);
}

/// Slice the unified-diff `diff --git` block whose a/ or b/ path
/// matches `file_path`. Empty when the stored patch has no such file.
fn extractFilePatch(patch: []const u8, file_path: []const u8) []const u8 {
    if (patch.len == 0 or file_path.len == 0) return "";
    var start: ?usize = null;
    var i: usize = 0;
    while (i < patch.len) {
        const rest = patch[i..];
        const line_end = std.mem.indexOfScalar(u8, rest, '\n') orelse rest.len;
        const line = rest[0..line_end];
        if (std.mem.startsWith(u8, line, "diff --git ")) {
            if (start != null) return std.mem.trimEnd(u8, patch[start.?..i], "\r\n");
            if (diffGitMentionsPath(line, file_path)) start = i;
        }
        if (line_end == rest.len) break;
        i += line_end + 1;
    }
    if (start) |s| return std.mem.trimEnd(u8, patch[s..], "\r\n");
    return "";
}

fn diffGitMentionsPath(header: []const u8, file_path: []const u8) bool {
    if (header.len == 0 or file_path.len == 0) return false;
    var needle_buf: [max_review_diff_path + 3]u8 = undefined;
    const b_path = std.fmt.bufPrint(&needle_buf, " b/{s}", .{file_path}) catch return std.mem.indexOf(u8, header, file_path) != null;
    if (std.mem.indexOf(u8, header, b_path) != null) return true;
    const a_path = std.fmt.bufPrint(&needle_buf, " a/{s}", .{file_path}) catch return false;
    return std.mem.indexOf(u8, header, a_path) != null;
}

pub fn applyLine(model: *Model, line: native_sdk.EffectLine) void {
    if (line.key != model.review_diff_key or model.review_diff_key == 0) return;
    if (!probeStillCurrent(model)) return;
    if (!model.review_diff_active) return;
    if (model.review_diff_via_daemon) {
        applyDaemonReviewDiffLine(model, line.line);
        return;
    }
    appendParsedNumstat(model, line.line);
}

fn applyDaemonReviewDiffLine(model: *Model, raw: []const u8) void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const parsed = protocol.parseReviewDiff(arena_state.allocator(), raw);
    if (!parsed.ok) return;
    if (!ensureDaemonPatchStore(model)) return;
    clearFiles(model);
    appendParsedNumstat(model, parsed.numstat);
    writeFixed(model.review_diff_daemon_patch_storage, &model.review_diff_daemon_patch_len, parsed.patch);
    model.review_diff_complete_context = parsed.complete_context;
    model.review_diff_daemon_ok = true;
    model.review_diff_last_via_daemon = true;
}

fn appendParsedNumstat(model: *Model, raw: []const u8) void {
    var it = std.mem.splitScalar(u8, raw, '\n');
    while (it.next()) |line| {
        if (model.review_diff_file_count >= max_review_diff_files) return;
        const parsed = parseNumstatFileLine(line) orelse continue;
        const slot = &model.review_diff_file_store[model.review_diff_file_count];
        slot.setCounts(parsed.status, parsed.path, parsed.additions, parsed.deletions);
        model.review_diff_file_count += 1;
    }
}

pub fn handleExit(model: *Model, fx: *Effects, exit: native_sdk.EffectExit) void {
    if (exit.key != model.review_diff_key or model.review_diff_key == 0) return;
    const current = probeStillCurrent(model);
    const via_daemon = model.review_diff_via_daemon;
    const daemon_ok = model.review_diff_daemon_ok;
    model.review_diff_key = 0;
    model.review_diff_via_daemon = false;
    model.review_diff_daemon_ok = false;
    if (!model.review_diff_active) {
        clearFiles(model);
        clearStatus(model);
        clearDaemonFlags(model);
        return;
    }
    if (!current) {
        clearFiles(model);
        clearDaemonFlags(model);
        setStatus(model, failed_status);
        return;
    }
    if (via_daemon) {
        if (daemon_ok) {
            if (model.review_diff_file_count == 0) {
                setStatus(model, empty_status);
            } else {
                clearStatus(model);
            }
            return;
        }
        model.review_diff_last_via_daemon = false;
        clearDaemonPatch(model);
        clearFiles(model);
        const cwd = model.review_diff_probe_path_storage[0..model.review_diff_probe_path_len];
        if (cwd.len == 0) {
            setStatus(model, failed_status);
            return;
        }
        setStatus(model, comparing_status);
        spawnLocalReviewDiff(model, fx, cwd);
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
    if (!ensureHunkBodyStore(model)) return;
    const line = std.mem.trimEnd(u8, raw, "\r\n");
    var used = model.review_diff_hunk_len;
    const dest = model.review_diff_hunk_storage;
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
    model.review_diff_complete_context = false;
    rebuildHunkRows(model);
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

test "argv is chdir script plus git diff --numstat @{upstream}...HEAD" {
    const git_branch = @import("git_branch.zig");
    const git_dirty = @import("git_dirty.zig");
    const composer_numstat = @import("git_numstat.zig");
    var buf: [argv_len][]const u8 = undefined;
    const argv = unixArgvFor("/tmp/faku-review", &buf);
    try std.testing.expectEqual(@as(usize, 9), argv.len);
    try std.testing.expectEqualStrings(sh_bin, argv[0]);
    try std.testing.expectEqualStrings("-c", argv[1]);
    try std.testing.expectEqualStrings(main.fx_ask_chdir_script, argv[2]);
    try std.testing.expectEqualStrings("sh", argv[3]);
    try std.testing.expectEqualStrings("/tmp/faku-review", argv[4]);
    try std.testing.expectEqualStrings(git_bin, argv[5]);
    try std.testing.expectEqualStrings(git_diff_cmd, argv[6]);
    try std.testing.expectEqualStrings(git_numstat, argv[7]);
    try std.testing.expectEqualStrings(git_upstream_range, argv[8]);
    try std.testing.expectEqualStrings("@{upstream}...HEAD", argv[8]);
    try std.testing.expect(isGitReviewDiffArgv(argv));
    try std.testing.expect(std.mem.indexOf(u8, argv[2], git_upstream_range) == null);
    try std.testing.expect(std.mem.indexOf(u8, argv[2], git_numstat) == null);
    try std.testing.expect(std.mem.indexOf(u8, argv[2], git_diff_cmd) == null);
    try std.testing.expect(std.mem.indexOf(u8, argv[2], git_head) == null);
    try std.testing.expect(!isGitReviewDiffArgv(&.{ git_bin, git_diff_cmd, git_numstat, git_upstream_range }));
    var uncommitted_buf: [argv_len][]const u8 = undefined;
    const uncommitted = unixArgvForSource(.uncommitted, "/tmp/faku-review", &uncommitted_buf);
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
    try std.testing.expect(std.mem.indexOf(u8, uncommitted[2], git_numstat) == null);
    try std.testing.expect(std.mem.indexOf(u8, uncommitted[2], uncommitted_untracked_script) == null);
    try std.testing.expect(scriptHas(uncommitted[7], git_diff_cmd));
    try std.testing.expect(scriptHas(uncommitted[7], git_numstat));
    try std.testing.expect(scriptHas(uncommitted[7], git_head));
    try std.testing.expect(scriptHas(uncommitted[7], git_ls_files_cmd));
    try std.testing.expect(scriptHas(uncommitted[7], git_ls_files_others));
    try std.testing.expect(scriptHas(uncommitted[7], git_ls_files_exclude_standard));
    try std.testing.expect(scriptHas(uncommitted[7], "N\\t0\\t"));
    try std.testing.expect(!isGitReviewDiffArgv(&.{ git_bin, git_diff_cmd, git_numstat, git_head }));
    try std.testing.expect(!isGitReviewUncommittedArgv(&.{
        sh_bin,
        "-c",
        main.fx_ask_chdir_script,
        "sh",
        "/tmp/faku-review",
        git_bin,
        git_diff_cmd,
        git_numstat,
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
        git_numstat,
        git_head,
    }));
    var staged_buf: [argv_len][]const u8 = undefined;
    const staged = unixArgvForSource(.staged, "/tmp/faku-review", &staged_buf);
    try std.testing.expectEqual(@as(usize, 9), staged.len);
    try std.testing.expectEqualStrings(sh_bin, staged[0]);
    try std.testing.expectEqualStrings("-c", staged[1]);
    try std.testing.expectEqualStrings(main.fx_ask_chdir_script, staged[2]);
    try std.testing.expectEqualStrings("sh", staged[3]);
    try std.testing.expectEqualStrings("/tmp/faku-review", staged[4]);
    try std.testing.expectEqualStrings(git_bin, staged[5]);
    try std.testing.expectEqualStrings(git_diff_cmd, staged[6]);
    try std.testing.expectEqualStrings(git_numstat, staged[7]);
    try std.testing.expectEqualStrings(git_cached_flag, staged[8]);
    try std.testing.expectEqualStrings("--cached", staged[8]);
    try std.testing.expectEqualStrings(@import("git_commit.zig").git_cached_flag, staged[8]);
    try std.testing.expect(isGitReviewDiffArgv(staged));
    try std.testing.expect(std.mem.indexOf(u8, staged[2], git_cached_flag) == null);
    try std.testing.expect(std.mem.indexOf(u8, staged[2], git_numstat) == null);
    try std.testing.expect(!isGitReviewDiffArgv(&.{ git_bin, git_diff_cmd, git_numstat, git_cached_flag }));
    var unstaged_buf: [argv_len][]const u8 = undefined;
    const unstaged = unixArgvForSource(.unstaged, "/tmp/faku-review", &unstaged_buf);
    try std.testing.expectEqual(@as(usize, 8), unstaged.len);
    try std.testing.expectEqual(argv_len_unstaged, unstaged.len);
    try std.testing.expectEqualStrings(sh_bin, unstaged[0]);
    try std.testing.expectEqualStrings("-c", unstaged[1]);
    try std.testing.expectEqualStrings(main.fx_ask_chdir_script, unstaged[2]);
    try std.testing.expectEqualStrings("sh", unstaged[3]);
    try std.testing.expectEqualStrings("/tmp/faku-review", unstaged[4]);
    try std.testing.expectEqualStrings(git_bin, unstaged[5]);
    try std.testing.expectEqualStrings(git_diff_cmd, unstaged[6]);
    try std.testing.expectEqualStrings(git_numstat, unstaged[7]);
    try std.testing.expect(lastOperand(.unstaged, .origin) == null);
    try std.testing.expect(isGitReviewDiffArgv(unstaged));
    try std.testing.expect(std.mem.indexOf(u8, unstaged[2], git_numstat) == null);
    try std.testing.expect(std.mem.indexOf(u8, unstaged[2], git_diff_cmd) == null);
    try std.testing.expect(std.mem.indexOf(u8, unstaged[2], "/tmp/faku-review") == null);
    try std.testing.expect(!isGitReviewDiffArgv(&.{ git_bin, git_diff_cmd, git_numstat }));
    var committed_buf: [argv_len][]const u8 = undefined;
    const committed = unixArgvForSource(.committed, "/tmp/faku-review", &committed_buf);
    try std.testing.expectEqual(@as(usize, 9), committed.len);
    try std.testing.expectEqual(argv_len, committed.len);
    try std.testing.expectEqualStrings(sh_bin, committed[0]);
    try std.testing.expectEqualStrings("-c", committed[1]);
    try std.testing.expectEqualStrings(main.fx_ask_chdir_script, committed[2]);
    try std.testing.expectEqualStrings("sh", committed[3]);
    try std.testing.expectEqualStrings("/tmp/faku-review", committed[4]);
    try std.testing.expectEqualStrings(git_bin, committed[5]);
    try std.testing.expectEqualStrings(git_diff_cmd, committed[6]);
    try std.testing.expectEqualStrings(git_numstat, committed[7]);
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
    try std.testing.expect(std.mem.indexOf(u8, committed[2], git_numstat) == null);
    try std.testing.expect(std.mem.indexOf(u8, committed[2], git_upstream_range) == null);
    try std.testing.expect(!isGitReviewDiffArgv(&.{ git_bin, git_diff_cmd, git_numstat, git_committed_range }));
    var committed_main_buf: [argv_len][]const u8 = undefined;
    const committed_main = unixArgvForSourceRange(.committed, .main, "/tmp/faku-review", &committed_main_buf);
    try std.testing.expectEqual(@as(usize, 9), committed_main.len);
    try std.testing.expectEqualStrings(git_committed_range_main, committed_main[8]);
    try std.testing.expect(isGitReviewDiffArgv(committed_main));
    try std.testing.expect(std.mem.indexOf(u8, committed_main[2], git_committed_range_main) == null);
    try std.testing.expect(!isGitReviewDiffArgv(&.{ git_bin, git_diff_cmd, git_numstat, git_committed_range_main }));
    var committed_master_buf: [argv_len][]const u8 = undefined;
    const committed_master = unixArgvForSourceRange(.committed, .master, "/tmp/faku-review", &committed_master_buf);
    try std.testing.expectEqualStrings(git_committed_range_master, committed_master[8]);
    try std.testing.expect(isGitReviewDiffArgv(committed_master));
    try std.testing.expect(std.mem.indexOf(u8, committed_master[2], git_committed_range_master) == null);
    try std.testing.expect(!isGitReviewDiffArgv(&.{ git_bin, git_diff_cmd, git_numstat, git_committed_range_master }));
    var interpolated_main = committed_main_buf;
    interpolated_main[2] = "cd \"$1\" && git diff --numstat main...HEAD";
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
    const last_turn = unixArgvForLastTurn("/tmp/faku-review", last_turn_range, &last_turn_buf);
    try std.testing.expectEqual(@as(usize, 9), last_turn.len);
    try std.testing.expectEqual(argv_len, last_turn.len);
    try std.testing.expectEqualStrings(sh_bin, last_turn[0]);
    try std.testing.expectEqualStrings("-c", last_turn[1]);
    try std.testing.expectEqualStrings(main.fx_ask_chdir_script, last_turn[2]);
    try std.testing.expectEqualStrings("sh", last_turn[3]);
    try std.testing.expectEqualStrings("/tmp/faku-review", last_turn[4]);
    try std.testing.expectEqualStrings(git_bin, last_turn[5]);
    try std.testing.expectEqualStrings(git_diff_cmd, last_turn[6]);
    try std.testing.expectEqualStrings(git_numstat, last_turn[7]);
    try std.testing.expectEqualStrings(last_turn_range, last_turn[8]);
    try std.testing.expectEqualStrings("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa...HEAD", last_turn[8]);
    try std.testing.expect(isGitReviewDiffArgv(last_turn));
    var last_turn_two_dot_buf: [argv_len][]const u8 = undefined;
    const last_turn_two_dot = unixArgvForLastTurn("/tmp/faku-review", last_turn_snap, &last_turn_two_dot_buf);
    try std.testing.expectEqual(argv_len, last_turn_two_dot.len);
    try std.testing.expectEqualStrings(last_turn_sha, last_turn_two_dot[8]);
    try std.testing.expect(std.mem.indexOf(u8, last_turn_two_dot[8], git_last_turn_range_suffix) == null);
    try std.testing.expect(isGitReviewDiffArgv(last_turn_two_dot));
    var last_turn_start_end_argv_buf: [argv_len][]const u8 = undefined;
    const last_turn_start_end_argv = unixArgvForLastTurn("/tmp/faku-review", last_turn_start_end, &last_turn_start_end_argv_buf);
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
    try std.testing.expect(!isGitReviewDiffArgv(&.{ git_bin, git_diff_cmd, git_numstat, last_turn_range }));
    const head_tilde = [_][]const u8{
        sh_bin,
        "-c",
        main.fx_ask_chdir_script,
        "sh",
        "/tmp/faku-review",
        git_bin,
        git_diff_cmd,
        git_numstat,
        "HEAD~1",
    };
    try std.testing.expect(!isGitReviewDiffArgv(&head_tilde));
    var interpolated_last_turn = last_turn_buf;
    interpolated_last_turn[2] = "cd \"$1\" && git diff --numstat aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa...HEAD";
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
    var numstat_buf: [composer_numstat.argv_len][]const u8 = undefined;
    const numstat = composer_numstat.unixArgvFor("/tmp/faku-review", &numstat_buf);
    try std.testing.expect(!isGitReviewDiffArgv(numstat));
    try std.testing.expect(!isGitReviewUncommittedArgv(numstat));
    try std.testing.expect(!composer_numstat.isGitNumstatArgv(argv));
    try std.testing.expect(!composer_numstat.isGitNumstatArgv(uncommitted));
    try std.testing.expect(!file_mention.isGitLsFilesArgv(argv));
    try std.testing.expect(!file_mention.isGitLsFilesArgv(uncommitted));
    try std.testing.expect(review_diff_key_first >= 510);
    try std.testing.expect(review_diff_key_first > git_common_dir.git_common_dir_key_first);
    try std.testing.expect(git_common_dir.git_common_dir_key_first >= 500);
    try std.testing.expect(review_diff_hunk_key_first >= 520);
    try std.testing.expect(review_diff_hunk_key_first > review_diff_key_first);
    try std.testing.expect(argv_len_hunk_untracked == 11);
    try std.testing.expect(unix_argv_len_hunk_untracked == 11);
    try std.testing.expect(windows_argv_len_hunk_untracked == 8);
    try std.testing.expect(argv_len_hunk_untracked < 16);
    try std.testing.expect(windows_argv_len_hunk_untracked < 16);
    try std.testing.expect(argv_len_hunk == 10);
    try std.testing.expect(argv_len_hunk_unstaged == 9);
    try std.testing.expect(windows_argv_len == 6);
    try std.testing.expect(windows_argv_len_unstaged == 5);
    try std.testing.expect(windows_argv_len_uncommitted == 6);
    try std.testing.expect(windows_argv_len_hunk == 7);
    try std.testing.expect(windows_argv_len_hunk_unstaged == 6);
    try std.testing.expect(windows_argv_len < 16);
    try std.testing.expect(windows_argv_len_hunk < 16);
}

test "windows git argv is git.exe -C PATH; path is its own slot" {
    const git_branch = @import("git_branch.zig");
    const git_dirty = @import("git_dirty.zig");
    const composer_numstat = @import("git_numstat.zig");
    const cwd = "C:\\Users\\me\\proj";
    var buf: [argv_len][]const u8 = undefined;
    const argv = windowsArgvFor(cwd, &buf);
    try std.testing.expectEqual(@as(usize, windows_argv_len), argv.len);
    try std.testing.expect(argv.len <= 16);
    try std.testing.expectEqualStrings(windows_git_bin, argv[0]);
    try std.testing.expectEqualStrings(git_c_flag, argv[1]);
    try std.testing.expectEqualStrings(cwd, argv[2]);
    try std.testing.expectEqualStrings(git_diff_cmd, argv[3]);
    try std.testing.expectEqualStrings(git_numstat, argv[4]);
    try std.testing.expectEqualStrings(git_upstream_range, argv[5]);
    try std.testing.expect(isGitReviewDiffArgv(argv));
    try std.testing.expect(!isGitReviewHunkArgv(argv));
    try std.testing.expect(!isGitReviewUncommittedArgv(argv));
    try std.testing.expect(!std.mem.eql(u8, argv[0], sh_bin));
    try std.testing.expect(!isGitReviewDiffArgv(&.{ windows_git_bin, git_c_flag, cwd }));
    try std.testing.expect(!isGitReviewDiffArgv(&.{
        windows_git_bin,
        git_c_flag,
        cwd,
        git_diff_cmd,
    }));
    var git_only: [argv_len][]const u8 = undefined;
    git_only[0] = git_bin;
    git_only[1] = git_c_flag;
    git_only[2] = cwd;
    git_only[3] = git_diff_cmd;
    git_only[4] = git_numstat;
    git_only[5] = git_upstream_range;
    try std.testing.expect(isGitReviewDiffArgv(git_only[0..windows_argv_len]));

    var uncommitted_buf: [argv_len][]const u8 = undefined;
    const uncommitted = windowsArgvForSourceRangeWith(.uncommitted, .origin, "", cwd, &uncommitted_buf);
    try std.testing.expectEqual(@as(usize, windows_argv_len_uncommitted), uncommitted.len);
    try std.testing.expect(uncommitted.len <= 16);
    try std.testing.expectEqualStrings(powershell_bin, uncommitted[0]);
    try std.testing.expectEqualStrings(powershell_noprofile, uncommitted[1]);
    try std.testing.expectEqualStrings(powershell_command, uncommitted[2]);
    try std.testing.expectEqualStrings(powershell_uncommitted_untracked_script, uncommitted[3]);
    try std.testing.expectEqualStrings(powershell_args_flag, uncommitted[4]);
    try std.testing.expectEqualStrings(cwd, uncommitted[5]);
    try std.testing.expect(isGitReviewUncommittedArgv(uncommitted));
    try std.testing.expect(isGitReviewDiffArgv(uncommitted));
    try std.testing.expect(!isGitReviewHunkArgv(uncommitted));
    try std.testing.expect(!std.mem.eql(u8, uncommitted[0], sh_bin));
    try std.testing.expect(!std.mem.eql(u8, uncommitted[0], windows_git_bin));
    try std.testing.expect(std.mem.indexOf(u8, uncommitted[3], cwd) == null);
    try std.testing.expect(scriptHas(uncommitted[3], "$args[0]"));
    try std.testing.expect(scriptHas(uncommitted[3], "Set-Location"));
    try std.testing.expect(scriptHas(uncommitted[3], windows_git_bin));
    try std.testing.expect(scriptHas(uncommitted[3], git_diff_cmd));
    try std.testing.expect(scriptHas(uncommitted[3], git_numstat));
    try std.testing.expect(scriptHas(uncommitted[3], git_head));
    try std.testing.expect(scriptHas(uncommitted[3], git_ls_files_cmd));
    try std.testing.expect(scriptHas(uncommitted[3], git_ls_files_others));
    try std.testing.expect(scriptHas(uncommitted[3], git_ls_files_exclude_standard));
    try std.testing.expect(scriptHas(uncommitted[3], "'N'+[char]9+'0'+[char]9+'{0}'"));
    try std.testing.expect(!scriptHas(uncommitted[3], "--name-status"));
    try std.testing.expect(!scriptHas(uncommitted[3], "1048576"));
    try std.testing.expect(!isGitReviewUncommittedArgv(&.{ powershell_bin, powershell_noprofile, powershell_command }));
    try std.testing.expect(!isGitReviewUncommittedArgv(&.{
        powershell_bin,
        powershell_noprofile,
        powershell_command,
        powershell_uncommitted_untracked_script,
        powershell_args_flag,
    }));
    try std.testing.expect(!isGitReviewUncommittedArgv(&.{
        powershell_bin,
        powershell_noprofile,
        powershell_command,
        "Get-Date",
        powershell_args_flag,
        cwd,
    }));
    try std.testing.expect(!isGitReviewDiffArgv(&.{
        windows_git_bin,
        git_c_flag,
        cwd,
        git_diff_cmd,
        git_numstat,
        git_head,
    }));
    try std.testing.expect(!isGitReviewUncommittedArgv(&.{
        windows_git_bin,
        git_c_flag,
        cwd,
        git_diff_cmd,
        git_numstat,
        git_head,
    }));

    var staged_buf: [argv_len][]const u8 = undefined;
    const staged = windowsArgvForSourceRangeWith(.staged, .origin, "", cwd, &staged_buf);
    try std.testing.expectEqual(@as(usize, windows_argv_len), staged.len);
    try std.testing.expectEqualStrings(git_cached_flag, staged[5]);
    try std.testing.expect(isGitReviewDiffArgv(staged));
    try std.testing.expect(!isGitReviewUncommittedArgv(staged));

    var unstaged_buf: [argv_len][]const u8 = undefined;
    const unstaged = windowsArgvForSourceRangeWith(.unstaged, .origin, "", cwd, &unstaged_buf);
    try std.testing.expectEqual(@as(usize, windows_argv_len_unstaged), unstaged.len);
    try std.testing.expectEqualStrings(git_numstat, unstaged[4]);
    try std.testing.expect(isGitReviewDiffArgv(unstaged));
    try std.testing.expect(!isGitReviewUncommittedArgv(unstaged));
    try std.testing.expect(!isGitReviewHunkArgv(unstaged));

    var committed_buf: [argv_len][]const u8 = undefined;
    const committed = windowsArgvForSourceRangeWith(.committed, .origin, "", cwd, &committed_buf);
    try std.testing.expectEqualStrings(git_committed_range, committed[5]);
    try std.testing.expect(isGitReviewDiffArgv(committed));
    var committed_main_buf: [argv_len][]const u8 = undefined;
    const committed_main = windowsArgvForSourceRangeWith(.committed, .main, "", cwd, &committed_main_buf);
    try std.testing.expectEqualStrings(git_committed_range_main, committed_main[5]);
    try std.testing.expect(isGitReviewDiffArgv(committed_main));
    var committed_master_buf: [argv_len][]const u8 = undefined;
    const committed_master = windowsArgvForSourceRangeWith(.committed, .master, "", cwd, &committed_master_buf);
    try std.testing.expectEqualStrings(git_committed_range_master, committed_master[5]);
    try std.testing.expect(isGitReviewDiffArgv(committed_master));

    const last_turn_sha = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    var last_turn_range_buf: [last_turn_range_len]u8 = undefined;
    const last_turn_range = formatLastTurnRange(last_turn_sha, &last_turn_range_buf) orelse return error.MissingLastTurnRange;
    var last_turn_buf: [argv_len][]const u8 = undefined;
    const last_turn = windowsArgvForSourceRangeWith(.last_turn, .origin, last_turn_range, cwd, &last_turn_buf);
    try std.testing.expectEqual(@as(usize, windows_argv_len), last_turn.len);
    try std.testing.expectEqualStrings(last_turn_range, last_turn[5]);
    try std.testing.expect(isGitReviewDiffArgv(last_turn));
    try std.testing.expect(std.mem.indexOf(u8, last_turn[2], last_turn_sha) == null);

    var hunk_buf: [argv_len_hunk][]const u8 = undefined;
    const hunk = windowsArgvForHunkRange(.branch, .origin, "", cwd, "src/a.zig", &hunk_buf);
    try std.testing.expectEqual(@as(usize, windows_argv_len_hunk), hunk.len);
    try std.testing.expectEqualStrings(windows_git_bin, hunk[0]);
    try std.testing.expectEqualStrings(git_c_flag, hunk[1]);
    try std.testing.expectEqualStrings(cwd, hunk[2]);
    try std.testing.expectEqualStrings(git_diff_cmd, hunk[3]);
    try std.testing.expectEqualStrings(git_upstream_range, hunk[4]);
    try std.testing.expectEqualStrings(git_pathspec_end, hunk[5]);
    try std.testing.expectEqualStrings("src/a.zig", hunk[6]);
    try std.testing.expect(isGitReviewHunkArgv(hunk));
    try std.testing.expect(!isGitReviewDiffArgv(hunk));
    try std.testing.expect(std.mem.indexOf(u8, hunk[2], "src/a.zig") == null);

    var uncommitted_hunk_buf: [argv_len_hunk][]const u8 = undefined;
    const uncommitted_hunk = windowsArgvForHunkRange(.uncommitted, .origin, "", cwd, "tracked.zig", &uncommitted_hunk_buf);
    try std.testing.expectEqual(@as(usize, windows_argv_len_hunk), uncommitted_hunk.len);
    try std.testing.expectEqualStrings(git_head, uncommitted_hunk[4]);
    try std.testing.expectEqualStrings(git_pathspec_end, uncommitted_hunk[5]);
    try std.testing.expectEqualStrings("tracked.zig", uncommitted_hunk[6]);
    try std.testing.expect(isGitReviewHunkArgv(uncommitted_hunk));
    try std.testing.expect(!isGitReviewDiffArgv(uncommitted_hunk));
    try std.testing.expect(!isGitReviewUncommittedArgv(uncommitted_hunk));

    var unstaged_hunk_buf: [argv_len_hunk][]const u8 = undefined;
    const unstaged_hunk = windowsArgvForHunkRange(.unstaged, .origin, "", cwd, "unstaged.zig", &unstaged_hunk_buf);
    try std.testing.expectEqual(@as(usize, windows_argv_len_hunk_unstaged), unstaged_hunk.len);
    try std.testing.expectEqualStrings(git_pathspec_end, unstaged_hunk[4]);
    try std.testing.expectEqualStrings("unstaged.zig", unstaged_hunk[5]);
    try std.testing.expect(isGitReviewHunkArgv(unstaged_hunk));
    try std.testing.expect(!isGitReviewDiffArgv(unstaged_hunk));

    var last_turn_hunk_buf: [argv_len_hunk][]const u8 = undefined;
    const last_turn_hunk = windowsArgvForHunkRange(.last_turn, .origin, last_turn_range, cwd, "last-turn.zig", &last_turn_hunk_buf);
    try std.testing.expectEqualStrings(last_turn_range, last_turn_hunk[4]);
    try std.testing.expectEqualStrings(git_pathspec_end, last_turn_hunk[5]);
    try std.testing.expectEqualStrings("last-turn.zig", last_turn_hunk[6]);
    try std.testing.expect(isGitReviewHunkArgv(last_turn_hunk));

    var untracked_buf: [argv_len_hunk_untracked][]const u8 = undefined;
    const untracked = windowsArgvForUntrackedHunk(cwd, "new file.txt", &untracked_buf);
    try std.testing.expectEqual(@as(usize, windows_argv_len_hunk_untracked), untracked.len);
    try std.testing.expect(untracked.len <= 16);
    try std.testing.expectEqualStrings(windows_git_bin, untracked[0]);
    try std.testing.expectEqualStrings(git_c_flag, untracked[1]);
    try std.testing.expectEqualStrings(cwd, untracked[2]);
    try std.testing.expectEqualStrings(git_diff_cmd, untracked[3]);
    try std.testing.expectEqualStrings(git_no_index, untracked[4]);
    try std.testing.expectEqualStrings("--no-index", untracked[4]);
    try std.testing.expectEqualStrings(git_pathspec_end, untracked[5]);
    try std.testing.expectEqualStrings(git_nul, untracked[6]);
    try std.testing.expectEqualStrings("NUL", untracked[6]);
    try std.testing.expectEqualStrings("new file.txt", untracked[7]);
    try std.testing.expect(isGitReviewHunkArgv(untracked));
    try std.testing.expect(!isGitReviewDiffArgv(untracked));
    try std.testing.expect(!isGitReviewUncommittedArgv(untracked));
    try std.testing.expect(std.mem.indexOf(u8, untracked[2], git_no_index) == null);
    try std.testing.expect(std.mem.indexOf(u8, untracked[2], git_nul) == null);
    try std.testing.expect(std.mem.indexOf(u8, untracked[2], "new file.txt") == null);
    try std.testing.expect(!isGitReviewHunkArgv(&.{
        windows_git_bin,
        git_c_flag,
        cwd,
        git_diff_cmd,
        git_no_index,
        git_pathspec_end,
        git_nul,
    }));
    try std.testing.expect(!isGitReviewHunkArgv(&.{
        windows_git_bin,
        git_c_flag,
        cwd,
        git_diff_cmd,
        git_numstat,
        git_head,
    }));
    try std.testing.expect(!isGitReviewHunkArgv(uncommitted));

    var branch_buf: [git_branch.argv_len][]const u8 = undefined;
    try std.testing.expect(!isGitReviewDiffArgv(git_branch.windowsArgvFor(cwd, &branch_buf)));
    try std.testing.expect(!isGitReviewHunkArgv(git_branch.windowsArgvFor(cwd, &branch_buf)));
    try std.testing.expect(!git_branch.isGitBranchArgv(argv));
    var dirty_buf: [git_dirty.argv_len][]const u8 = undefined;
    try std.testing.expect(!isGitReviewDiffArgv(git_dirty.windowsArgvFor(cwd, &dirty_buf)));
    try std.testing.expect(!git_dirty.isGitDirtyArgv(argv));
    var numstat_buf: [composer_numstat.argv_len][]const u8 = undefined;
    try std.testing.expect(!isGitReviewDiffArgv(composer_numstat.windowsArgvFor(cwd, &numstat_buf)));
    try std.testing.expect(!isGitReviewUncommittedArgv(composer_numstat.windowsArgvFor(cwd, &numstat_buf)));
    try std.testing.expect(!composer_numstat.isGitNumstatArgv(argv));
    try std.testing.expect(!composer_numstat.isGitNumstatArgv(uncommitted));
    try std.testing.expect(!std.mem.eql(u8, uncommitted[3], composer_numstat.powershell_untracked_script));
    var ahead_buf: [git_ahead_behind.argv_len][]const u8 = undefined;
    try std.testing.expect(!isGitReviewDiffArgv(git_ahead_behind.windowsArgvFor(cwd, &ahead_buf)));
    try std.testing.expect(!git_ahead_behind.isGitAheadBehindArgv(argv));
    var mention_buf: [file_mention.git_argv_len][]const u8 = undefined;
    try std.testing.expect(!isGitReviewDiffArgv(file_mention.windowsArgvFor(cwd, &mention_buf)));
    try std.testing.expect(!file_mention.isGitLsFilesArgv(argv));
}

test "host argvFor matches the process OS" {
    var buf: [argv_len][]const u8 = undefined;
    const argv = argvFor("/tmp/faku-review", &buf);
    try std.testing.expect(isGitReviewDiffArgv(argv));
    try std.testing.expect(!isGitReviewHunkArgv(argv));
    switch (builtin.os.tag) {
        .windows => {
            try std.testing.expectEqualStrings(windows_git_bin, argv[0]);
            try std.testing.expectEqualStrings(git_c_flag, argv[1]);
            try std.testing.expectEqualStrings(git_diff_cmd, argv[3]);
            try std.testing.expectEqualStrings(git_numstat, argv[4]);
            try std.testing.expectEqualStrings(git_upstream_range, argv[5]);
        },
        else => {
            try std.testing.expectEqualStrings(sh_bin, argv[0]);
            try std.testing.expectEqualStrings(git_numstat, argv[7]);
            try std.testing.expectEqualStrings(git_upstream_range, argv[8]);
        },
    }
    var uncommitted_buf: [argv_len][]const u8 = undefined;
    const uncommitted = argvForSource(.uncommitted, "/tmp/faku-review", &uncommitted_buf);
    try std.testing.expect(isGitReviewUncommittedArgv(uncommitted));
    switch (builtin.os.tag) {
        .windows => {
            try std.testing.expectEqualStrings(powershell_bin, uncommitted[0]);
            try std.testing.expectEqualStrings(powershell_noprofile, uncommitted[1]);
            try std.testing.expectEqualStrings(powershell_command, uncommitted[2]);
            try std.testing.expectEqualStrings(powershell_uncommitted_untracked_script, uncommitted[3]);
            try std.testing.expectEqualStrings(powershell_args_flag, uncommitted[4]);
        },
        else => {
            try std.testing.expectEqualStrings(uncommitted_untracked_script, uncommitted[7]);
        },
    }
    var hunk_buf: [argv_len_hunk][]const u8 = undefined;
    const hunk = argvForHunk(.branch, .origin, "/tmp/faku-review", "src/a.zig", &hunk_buf);
    try std.testing.expect(isGitReviewHunkArgv(hunk));
    switch (builtin.os.tag) {
        .windows => {
            try std.testing.expectEqualStrings(windows_git_bin, hunk[0]);
            try std.testing.expectEqualStrings(git_pathspec_end, hunk[5]);
            try std.testing.expectEqualStrings("src/a.zig", hunk[6]);
        },
        else => {
            try std.testing.expectEqualStrings(sh_bin, hunk[0]);
            try std.testing.expectEqualStrings(git_pathspec_end, hunk[8]);
            try std.testing.expectEqualStrings("src/a.zig", hunk[9]);
        },
    }
    var untracked_buf: [argv_len_hunk_untracked][]const u8 = undefined;
    const untracked = argvForUntrackedHunk("/tmp/faku-review", "new file.txt", &untracked_buf);
    try std.testing.expect(isGitReviewHunkArgv(untracked));
    try std.testing.expect(!isGitReviewDiffArgv(untracked));
    switch (builtin.os.tag) {
        .windows => {
            try std.testing.expectEqualStrings(windows_git_bin, untracked[0]);
            try std.testing.expectEqualStrings(git_no_index, untracked[4]);
            try std.testing.expectEqualStrings(git_nul, untracked[6]);
            try std.testing.expectEqualStrings("new file.txt", untracked[7]);
        },
        else => {
            try std.testing.expectEqualStrings(sh_bin, untracked[0]);
            try std.testing.expectEqualStrings(git_no_index, untracked[7]);
            try std.testing.expectEqualStrings(git_dev_null, untracked[9]);
            try std.testing.expectEqualStrings("new file.txt", untracked[10]);
        },
    }
}

test "probeSupported is true on macOS, Linux, and Windows" {
    try std.testing.expect(probeSupported());
}

test "parseNameStatusLine is status letter plus path; rename uses dest" {
    try std.testing.expectEqualStrings("src/a.zig", parseNameStatusLine("M\tsrc/a.zig\n").?.path);
    try std.testing.expectEqualStrings("src/a.zig", parseNameStatusLine("M\tsrc/a.zig\r\n").?.path);
    try std.testing.expectEqual(@as(u8, 'M'), parseNameStatusLine("M\tsrc/a.zig\r\n").?.status);
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

test "parseNumstatFileLine maps added/deleted into ChangedFile status letters" {
    try std.testing.expectEqual(@as(u8, 'A'), parseNumstatFileLine("1\t0\tsrc/a.zig\n").?.status);
    try std.testing.expectEqualStrings("src/a.zig", parseNumstatFileLine("1\t0\tsrc/a.zig\n").?.path);
    try std.testing.expectEqual(@as(u64, 1), parseNumstatFileLine("1\t0\tsrc/a.zig\n").?.additions);
    try std.testing.expectEqual(@as(u64, 0), parseNumstatFileLine("1\t0\tsrc/a.zig\n").?.deletions);
    try std.testing.expectEqual(@as(u8, 'D'), parseNumstatFileLine("0\t4\tgone.txt").?.status);
    try std.testing.expectEqual(@as(u64, 0), parseNumstatFileLine("0\t4\tgone.txt").?.additions);
    try std.testing.expectEqual(@as(u64, 4), parseNumstatFileLine("0\t4\tgone.txt").?.deletions);
    try std.testing.expectEqual(@as(u8, 'M'), parseNumstatFileLine("2\t1\tsrc/b.zig\r\n").?.status);
    try std.testing.expectEqual(@as(u64, 2), parseNumstatFileLine("2\t1\tsrc/b.zig\r\n").?.additions);
    try std.testing.expectEqual(@as(u64, 1), parseNumstatFileLine("2\t1\tsrc/b.zig\r\n").?.deletions);
    try std.testing.expectEqual(@as(u8, 'M'), parseNumstatFileLine("-\t-\tbin.dat").?.status);
    try std.testing.expectEqualStrings("bin.dat", parseNumstatFileLine("-\t-\tbin.dat").?.path);
    try std.testing.expectEqual(@as(u64, 0), parseNumstatFileLine("-\t-\tbin.dat").?.additions);
    try std.testing.expectEqual(@as(u64, 0), parseNumstatFileLine("-\t-\tbin.dat").?.deletions);
    try std.testing.expectEqual(@as(u8, '?'), parseNumstatFileLine("N\t0\tuntracked.txt").?.status);
    try std.testing.expectEqual(@as(u64, 0), parseNumstatFileLine("N\t0\tuntracked.txt").?.additions);
    try std.testing.expectEqual(@as(u64, 0), parseNumstatFileLine("N\t0\tuntracked.txt").?.deletions);
    try std.testing.expectEqual(@as(u8, 'R'), parseNumstatFileLine("1\t0\told.txt\tnew.txt").?.status);
    try std.testing.expectEqualStrings("new.txt", parseNumstatFileLine("1\t0\told.txt\tnew.txt").?.path);
    try std.testing.expectEqual(@as(u64, 1), parseNumstatFileLine("1\t0\told.txt\tnew.txt").?.additions);
    try std.testing.expect(parseNumstatFileLine("") == null);
    try std.testing.expect(parseNumstatFileLine("1\t0") == null);
    try std.testing.expect(parseNumstatFileLine("M\tsrc/a.zig") == null);
}

test "open with a daemon address spawns CollectReviewDiff sidecar" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/review-daemon", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    const id = model.addSession("review daemon", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);

    open(&model, &fx);
    const sidecar = pendingSpawnKey(&fx, model.review_diff_key) orelse return error.MissingDaemonCollectReviewDiff;
    try std.testing.expect(daemon_proxy.isSidecarArgv(sidecar.argv));
    try std.testing.expect(!isGitReviewDiffArgv(sidecar.argv));
    try std.testing.expectEqualStrings("faku", sidecar.argv[0]);
    try std.testing.expectEqualStrings(daemon_proxy.SUBCOMMAND, sidecar.argv[1]);
    try std.testing.expectEqualStrings("127.0.0.1:8787", sidecar.argv[2]);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"hello\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"workspace\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"collectReviewDiff\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"source\":\"branch\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"prompt\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"attachSession\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, project) != null);
    try std.testing.expect(model.review_diff_via_daemon);
    try std.testing.expect(!model.review_diff_last_via_daemon);
    try std.testing.expectEqual(sidecar.key, model.review_diff_key);
    try std.testing.expect(sidecar.key < review_diff_key_first);
    try std.testing.expectEqualStrings(comparing_status, reviewDiffStatus(&model));

    setSource(&model, &fx, .uncommitted);
    const uncommitted = pendingSpawnKey(&fx, model.review_diff_key) orelse return error.MissingDaemonUncommitted;
    try std.testing.expect(daemon_proxy.isSidecarArgv(uncommitted.argv));
    try std.testing.expect(std.mem.indexOf(u8, uncommitted.stdin, "\"source\":\"uncommitted\"") != null);
    setSource(&model, &fx, .staged);
    const staged = pendingSpawnKey(&fx, model.review_diff_key) orelse return error.MissingDaemonStaged;
    try std.testing.expect(std.mem.indexOf(u8, staged.stdin, "\"source\":\"staged\"") != null);
    setSource(&model, &fx, .unstaged);
    const unstaged = pendingSpawnKey(&fx, model.review_diff_key) orelse return error.MissingDaemonUnstaged;
    try std.testing.expect(std.mem.indexOf(u8, unstaged.stdin, "\"source\":\"unstaged\"") != null);
    setSource(&model, &fx, .committed);
    const committed = pendingSpawnKey(&fx, model.review_diff_key) orelse return error.MissingDaemonCommitted;
    try std.testing.expect(std.mem.indexOf(u8, committed.stdin, "\"source\":\"committed\"") != null);
}

test "open without a daemon address still uses local numstat" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/review-local", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    model.setSidecarPath("faku");
    const id = model.addSession("review local", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);
    try std.testing.expectEqual(@as(usize, 0), store.resolveDaemonMirrorAddress(&model).len);

    open(&model, &fx);
    const git = pendingSpawnKey(&fx, model.review_diff_key) orelse return error.MissingLocalNumstat;
    try std.testing.expect(isGitReviewDiffArgv(git.argv));
    try expectNumstatOperand(git.argv, git_upstream_range);
    try std.testing.expect(!daemon_proxy.isSidecarArgv(git.argv));
    try std.testing.expectEqualStrings("", git.stdin);
    try std.testing.expect(!model.review_diff_via_daemon);
    try std.testing.expectEqual(review_diff_key_first, model.review_diff_key);
}

test "CollectReviewDiff sidecar paints file list from numstat and selected hunk from patch" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/review-fill", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    defer freeReviewDiffStores(&model);
    model.store_io = std.testing.io;
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    const id = model.addSession("review fill", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);

    open(&model, &fx);
    const sidecar = pendingSpawnKey(&fx, model.review_diff_key) orelse return error.MissingDaemonCollectReviewDiffFill;
    applyLine(&model, .{ .key = sidecar.key, .line = "{\"type\":\"hello\"}" });
    try std.testing.expectEqual(@as(u32, 0), model.review_diff_file_count);
    const ok_line = "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000014\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"workspace\",\"result\":{\"type\":\"reviewDiff\",\"data\":{\"source\":\"branch\",\"numstat\":\"1\\t0\\tsrc/a.zig\\n0\\t2\\tgone.txt\\n\",\"patch\":\"diff --git a/src/a.zig b/src/a.zig\\n--- a/src/a.zig\\n+++ b/src/a.zig\\n@@ -1 +1 @@\\n-old\\n+new\\ndiff --git a/gone.txt b/gone.txt\\n--- a/gone.txt\\n+++ /dev/null\\n@@ -1 +0,0 @@\\n-bye\\n\",\"completeContext\":false}}}}}";
    applyLine(&model, .{ .key = sidecar.key, .line = ok_line });
    try std.testing.expect(model.review_diff_daemon_ok);
    try std.testing.expect(model.review_diff_last_via_daemon);
    try std.testing.expectEqual(@as(u32, 2), model.review_diff_file_count);
    try std.testing.expectEqualStrings("A src/a.zig", model.review_diff_file_store[0].label());
    try std.testing.expectEqual(@as(u64, 1), model.review_diff_file_store[0].additions);
    try std.testing.expectEqual(@as(u64, 0), model.review_diff_file_store[0].deletions);
    try std.testing.expectEqualStrings("D gone.txt", model.review_diff_file_store[1].label());
    try std.testing.expectEqual(@as(u64, 0), model.review_diff_file_store[1].additions);
    try std.testing.expectEqual(@as(u64, 2), model.review_diff_file_store[1].deletions);
    {
        var rows_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer rows_arena.deinit();
        const rows = reviewDiffRows(&model, rows_arena.allocator());
        try std.testing.expectEqual(@as(usize, 2), rows.len);
        try std.testing.expectEqualStrings("D gone.txt", rows[0].label);
        try std.testing.expectEqual(@as(u32, 2), rows[0].id);
        try std.testing.expect(!rows[0].has_additions);
        try std.testing.expect(rows[0].has_deletions);
        try std.testing.expectEqualStrings("-2", rows[0].deletions_label);
        try std.testing.expectEqualStrings("src", rows[1].label);
        try std.testing.expect(rows[1].is_directory);
        try std.testing.expect(!rows[1].expanded);
        toggleDir(&model, rows[1].id);
        const expanded = reviewDiffRows(&model, rows_arena.allocator());
        try std.testing.expectEqual(@as(usize, 3), expanded.len);
        try std.testing.expectEqualStrings("src", expanded[1].label);
        try std.testing.expect(expanded[1].expanded);
        try std.testing.expectEqualStrings("A a.zig", expanded[2].label);
        try std.testing.expectEqual(@as(u32, 1), expanded[2].id);
        try std.testing.expect(expanded[2].has_additions);
        try std.testing.expect(!expanded[2].has_deletions);
        try std.testing.expectEqualStrings("+1", expanded[2].additions_label);
        try std.testing.expect(expanded[0].has_deletions);
        try std.testing.expectEqualStrings("-2", expanded[0].deletions_label);
    }
    handleExit(&model, &fx, .{ .key = sidecar.key, .reason = .exited, .code = 0 });
    try std.testing.expectEqual(@as(u64, 0), model.review_diff_key);
    try std.testing.expect(!model.review_diff_via_daemon);
    try std.testing.expect(model.review_diff_last_via_daemon);
    try std.testing.expect(!hasReviewDiffStatus(&model));

    selectFile(&model, &fx, 1);
    try std.testing.expectEqual(@as(u32, 1), model.review_diff_selected_id);
    try std.testing.expectEqual(@as(u64, 0), model.review_diff_hunk_key);
    try std.testing.expect(hasReviewDiffHunk(&model));
    try std.testing.expect(std.mem.indexOf(u8, reviewDiffHunk(&model), "diff --git a/src/a.zig b/src/a.zig") != null);
    try std.testing.expect(std.mem.indexOf(u8, reviewDiffHunk(&model), "+new") != null);
    try std.testing.expect(std.mem.indexOf(u8, reviewDiffHunk(&model), "gone.txt") == null);

    selectFile(&model, &fx, 2);
    try std.testing.expectEqual(@as(u32, 2), model.review_diff_selected_id);
    try std.testing.expectEqual(@as(u64, 0), model.review_diff_hunk_key);
    try std.testing.expect(std.mem.indexOf(u8, reviewDiffHunk(&model), "diff --git a/gone.txt b/gone.txt") != null);
    try std.testing.expect(std.mem.indexOf(u8, reviewDiffHunk(&model), "+new") == null);
}

test "CollectReviewDiff sidecar non-ok falls back to local numstat" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/review-fallback", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    model.setDaemonAddress("10.0.0.2:9");
    model.setSidecarPath("faku");
    const id = model.addSession("review fallback", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);

    open(&model, &fx);
    const sidecar = pendingSpawnKey(&fx, model.review_diff_key) orelse return error.MissingDaemonCollectReviewDiffFallback;
    applyLine(&model, .{
        .key = sidecar.key,
        .line = "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000014\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"workspace\",\"result\":{\"type\":\"ack\"}}}}",
    });
    try std.testing.expectEqual(@as(u32, 0), model.review_diff_file_count);
    handleExit(&model, &fx, .{ .key = sidecar.key, .reason = .exited, .code = 1 });
    try std.testing.expect(!model.review_diff_via_daemon);
    try std.testing.expect(!model.review_diff_last_via_daemon);
    const git = pendingSpawnKey(&fx, model.review_diff_key) orelse return error.MissingLocalNumstatFallback;
    try std.testing.expect(isGitReviewDiffArgv(git.argv));
    try expectNumstatOperand(git.argv, git_upstream_range);
    try std.testing.expect(!daemon_proxy.isSidecarArgv(git.argv));
    try std.testing.expectEqualStrings("", git.stdin);
    try std.testing.expect(git.key >= review_diff_key_first);
    try std.testing.expectEqualStrings(comparing_status, reviewDiffStatus(&model));
}

test "LastTurn with a daemon address stays on the local probe" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/review-last-turn-local", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    const id = model.addSession("review last turn", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);

    open(&model, &fx);
    setSource(&model, &fx, .last_turn);
    try std.testing.expectEqual(Source.last_turn, model.review_diff_source);
    try std.testing.expect(!model.review_diff_via_daemon);
    try std.testing.expectEqual(@as(u64, 0), model.review_diff_key);
    try std.testing.expectEqualStrings(failed_status, reviewDiffStatus(&model));
}

test "Uncommitted argv is nested sh -c; old HEAD-only argv is not Review" {
    var buf: [argv_len][]const u8 = undefined;
    const argv = unixArgvForSource(.uncommitted, "/tmp/faku-uncommitted", &buf);
    try std.testing.expectEqual(argv_len_uncommitted, argv.len);
    try std.testing.expectEqualStrings(sh_bin, argv[5]);
    try std.testing.expectEqualStrings("-c", argv[6]);
    try std.testing.expectEqualStrings(uncommitted_untracked_script, argv[7]);
    try std.testing.expect(isGitReviewUncommittedArgv(argv));
    try std.testing.expect(isGitReviewDiffArgv(argv));
    try std.testing.expect(lastOperand(.uncommitted, .origin) == null);
    try std.testing.expect(scriptHas(argv[7], "git diff --numstat HEAD"));
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
        git_numstat,
        git_head,
    };
    try std.testing.expect(!isGitReviewUncommittedArgv(&old_head));
    try std.testing.expect(!isGitReviewDiffArgv(&old_head));
    var unstaged_buf: [argv_len][]const u8 = undefined;
    const unstaged = unixArgvForSource(.unstaged, "/tmp/faku-uncommitted", &unstaged_buf);
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

test "numstat lines fill capped rows; empty and fail stay honest" {
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
    applyLine(&model, .{ .key = key, .line = "2\t1\tsrc/a.zig\n4\t0\tnew.txt\n" });
    applyLine(&model, .{ .key = key, .line = "0\t3\tgone.txt\n1\t0\told.txt\trenamed.txt\n" });
    try std.testing.expectEqual(@as(u32, 4), model.review_diff_file_count);
    try std.testing.expectEqualStrings("M src/a.zig", model.review_diff_file_store[0].label());
    try std.testing.expectEqual(@as(u64, 2), model.review_diff_file_store[0].additions);
    try std.testing.expectEqual(@as(u64, 1), model.review_diff_file_store[0].deletions);
    try std.testing.expectEqualStrings("A new.txt", model.review_diff_file_store[1].label());
    try std.testing.expectEqual(@as(u64, 4), model.review_diff_file_store[1].additions);
    try std.testing.expectEqual(@as(u64, 0), model.review_diff_file_store[1].deletions);
    try std.testing.expectEqualStrings("D gone.txt", model.review_diff_file_store[2].label());
    try std.testing.expectEqual(@as(u64, 0), model.review_diff_file_store[2].additions);
    try std.testing.expectEqual(@as(u64, 3), model.review_diff_file_store[2].deletions);
    try std.testing.expectEqualStrings("R renamed.txt", model.review_diff_file_store[3].label());
    try std.testing.expectEqual(@as(u64, 1), model.review_diff_file_store[3].additions);
    try std.testing.expectEqual(@as(u64, 0), model.review_diff_file_store[3].deletions);
    {
        var rows_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer rows_arena.deinit();
        const rows = reviewDiffRows(&model, rows_arena.allocator());
        try std.testing.expectEqual(@as(usize, 4), rows.len);
        try std.testing.expectEqualStrings("D gone.txt", rows[0].label);
        try std.testing.expectEqual(@as(u32, 3), rows[0].id);
        try std.testing.expectEqualStrings("-3", rows[0].deletions_label);
        try std.testing.expectEqualStrings("A new.txt", rows[1].label);
        try std.testing.expectEqual(@as(u32, 2), rows[1].id);
        try std.testing.expectEqualStrings("+4", rows[1].additions_label);
        try std.testing.expect(!rows[1].has_deletions);
        try std.testing.expectEqualStrings("R renamed.txt", rows[2].label);
        try std.testing.expectEqual(@as(u32, 4), rows[2].id);
        try std.testing.expectEqualStrings("+1", rows[2].additions_label);
        try std.testing.expect(!rows[2].has_deletions);
        try std.testing.expectEqualStrings("src", rows[3].label);
        try std.testing.expect(rows[3].is_directory);
        try std.testing.expect(!rows[3].expanded);
        toggleDir(&model, rows[3].id);
        const expanded = reviewDiffRows(&model, rows_arena.allocator());
        try std.testing.expectEqual(@as(usize, 5), expanded.len);
        try std.testing.expectEqualStrings("src", expanded[3].label);
        try std.testing.expect(expanded[3].expanded);
        try std.testing.expectEqualStrings("M a.zig", expanded[4].label);
        try std.testing.expectEqual(@as(u32, 1), expanded[4].id);
        try std.testing.expect(expanded[4].has_additions);
        try std.testing.expect(expanded[4].has_deletions);
        try std.testing.expectEqualStrings("+2", expanded[4].additions_label);
        try std.testing.expectEqualStrings("-1", expanded[4].deletions_label);
    }

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
    applyLine(&model, .{ .key = fail_key, .line = "1\t0\tshould-drop.zig\n" });
    handleExit(&model, &fx, .{ .key = fail_key, .reason = .exited, .code = 128 });
    try std.testing.expectEqual(@as(u32, 0), model.review_diff_file_count);
    try std.testing.expectEqualStrings(failed_status, reviewDiffStatus(&model));
    try std.testing.expect(model.review_diff_active);

    dismiss(&model, &fx);
    try std.testing.expect(!model.review_diff_active);
    try std.testing.expectEqual(Source.branch, model.review_diff_source);
    try std.testing.expectEqual(@as(u32, 0), model.review_diff_file_count);
}

test "reviewDiffRows paints a collapsed directory tree and +N / -M on expanded leaves" {
    var model = Model{};
    model.review_diff_file_store[0].setCounts('A', "src/a.zig", 1, 0);
    model.review_diff_file_store[1].setCounts('M', "src/b.zig", 2, 1);
    model.review_diff_file_store[2].set('D', "gone.txt");
    model.review_diff_file_count = 3;
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    {
        const rows = reviewDiffRows(&model, arena);
        try std.testing.expectEqual(@as(usize, 2), rows.len);
        try std.testing.expectEqualStrings("D gone.txt", rows[0].label);
        try std.testing.expectEqual(@as(u32, 3), rows[0].id);
        try std.testing.expect(!rows[0].is_directory);
        try std.testing.expectEqual(@as(u32, 0), rows[0].depth);
        try std.testing.expect(!rows[0].has_additions);
        try std.testing.expectEqualStrings("src", rows[1].label);
        try std.testing.expect(rows[1].is_directory);
        try std.testing.expect(!rows[1].expanded);
        try std.testing.expectEqual(dirId(0), rows[1].id);
        try std.testing.expectEqual(@as(u32, 0), rows[1].depth);
        try std.testing.expect(!rows[1].has_additions);
        try std.testing.expect(!rows[1].has_deletions);
    }

    toggleDir(&model, dirId(0));
    {
        const rows = reviewDiffRows(&model, arena);
        try std.testing.expectEqual(@as(usize, 4), rows.len);
        try std.testing.expectEqualStrings("D gone.txt", rows[0].label);
        try std.testing.expectEqualStrings("src", rows[1].label);
        try std.testing.expect(rows[1].expanded);
        try std.testing.expectEqualStrings("A a.zig", rows[2].label);
        try std.testing.expectEqual(@as(u32, 1), rows[2].id);
        try std.testing.expectEqual(@as(u32, 1), rows[2].depth);
        try std.testing.expect(rows[2].has_indent);
        try std.testing.expectEqual(tree_indent_step + tree_file_indent_extra, rows[2].indent);
        try std.testing.expectEqualStrings("+1", rows[2].additions_label);
        try std.testing.expect(rows[2].has_additions);
        try std.testing.expect(!rows[2].has_deletions);
        try std.testing.expectEqualStrings("M b.zig", rows[3].label);
        try std.testing.expectEqual(@as(u32, 2), rows[3].id);
        try std.testing.expectEqualStrings("+2", rows[3].additions_label);
        try std.testing.expectEqualStrings("-1", rows[3].deletions_label);
        try std.testing.expect(rows[3].has_additions);
        try std.testing.expect(rows[3].has_deletions);
    }

    toggleDir(&model, 0);
    toggleDir(&model, 1);
    toggleDir(&model, dirId(99));
    try std.testing.expectEqual(@as(u32, 1), model.review_diff_expanded_count);
    toggleDir(&model, dirId(0));
    try std.testing.expectEqual(@as(u32, 0), model.review_diff_expanded_count);
}

test "reviewDiffRows flat root files have no directory rows" {
    var model = Model{};
    model.review_diff_file_store[0].setCounts('A', "new.txt", 4, 0);
    model.review_diff_file_store[1].set('D', "gone.txt");
    model.review_diff_file_count = 2;
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const rows = reviewDiffRows(&model, arena_state.allocator());
    try std.testing.expectEqual(@as(usize, 2), rows.len);
    try std.testing.expectEqualStrings("D gone.txt", rows[0].label);
    try std.testing.expect(!rows[0].is_directory);
    try std.testing.expectEqual(@as(u32, 2), rows[0].id);
    try std.testing.expectEqualStrings("A new.txt", rows[1].label);
    try std.testing.expectEqual(@as(u32, 1), rows[1].id);
    try std.testing.expectEqualStrings("+4", rows[1].additions_label);
    try std.testing.expect(!rows[0].is_directory and !rows[1].is_directory);
}

test "reviewDiffRows builds shared directories once and hides collapsed descendants" {
    var model = Model{};
    model.review_diff_file_store[0].set('M', "README.md");
    model.review_diff_file_store[1].set('M', "src/app/runtime.rs");
    model.review_diff_file_store[2].set('M', "src/app/view.rs");
    model.review_diff_file_store[3].set('M', "src/lib.rs");
    model.review_diff_file_store[4].set('M', "tests/review.rs");
    model.review_diff_file_count = 5;
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    {
        const rows = reviewDiffRows(&model, arena);
        try std.testing.expectEqual(@as(usize, 3), rows.len);
        try std.testing.expectEqualStrings("M README.md", rows[0].label);
        try std.testing.expectEqual(@as(u32, 1), rows[0].id);
        try std.testing.expectEqual(@as(u32, 0), rows[0].depth);
        try std.testing.expectEqualStrings("src", rows[1].label);
        try std.testing.expect(rows[1].is_directory);
        try std.testing.expect(!rows[1].expanded);
        try std.testing.expectEqualStrings("tests", rows[2].label);
        try std.testing.expect(rows[2].is_directory);
        try std.testing.expect(!rows[2].expanded);
    }

    const src_id = dirIdOfPath(&model, "src") orelse return error.MissingSrcDir;
    const tests_id = dirIdOfPath(&model, "tests") orelse return error.MissingTestsDir;
    const src_app_id = dirIdOfPath(&model, "src/app") orelse return error.MissingSrcAppDir;
    toggleDir(&model, src_id);
    toggleDir(&model, tests_id);
    {
        const rows = reviewDiffRows(&model, arena);
        try std.testing.expectEqual(@as(usize, 6), rows.len);
        try std.testing.expectEqualStrings("M README.md", rows[0].label);
        try std.testing.expectEqualStrings("src", rows[1].label);
        try std.testing.expect(rows[1].expanded);
        try std.testing.expectEqualStrings("app", rows[2].label);
        try std.testing.expect(rows[2].is_directory);
        try std.testing.expect(!rows[2].expanded);
        try std.testing.expectEqual(@as(u32, 1), rows[2].depth);
        try std.testing.expectEqual(src_app_id, rows[2].id);
        try std.testing.expectEqualStrings("M lib.rs", rows[3].label);
        try std.testing.expectEqual(@as(u32, 4), rows[3].id);
        try std.testing.expectEqual(@as(u32, 1), rows[3].depth);
        try std.testing.expectEqualStrings("tests", rows[4].label);
        try std.testing.expect(rows[4].expanded);
        try std.testing.expectEqualStrings("M review.rs", rows[5].label);
        try std.testing.expectEqual(@as(u32, 5), rows[5].id);
        var i: usize = 0;
        while (i < rows.len) : (i += 1) {
            try std.testing.expect(rows[i].id != 2);
            try std.testing.expect(rows[i].id != 3);
        }
    }

    toggleDir(&model, src_app_id);
    {
        const rows = reviewDiffRows(&model, arena);
        try std.testing.expectEqual(@as(usize, 8), rows.len);
        try std.testing.expectEqualStrings("app", rows[2].label);
        try std.testing.expect(rows[2].expanded);
        try std.testing.expectEqualStrings("M runtime.rs", rows[3].label);
        try std.testing.expectEqual(@as(u32, 2), rows[3].id);
        try std.testing.expectEqual(@as(u32, 2), rows[3].depth);
        try std.testing.expectEqualStrings("M view.rs", rows[4].label);
        try std.testing.expectEqual(@as(u32, 3), rows[4].id);
        try std.testing.expectEqualStrings("M lib.rs", rows[5].label);
    }
}

fn dirIdOfPath(model: *const Model, path: []const u8) ?u32 {
    var path_buf: [max_review_diff_files][]const u8 = undefined;
    var dir_buf: [max_review_diff_dirs][]const u8 = undefined;
    const dir_n = collectDirParents(model, &path_buf, &dir_buf);
    return dirIdOf(dir_buf[0..dir_n], path);
}

test "reviewDiffRows path filter contains-match expands ancestors" {
    var model = Model{};
    model.review_diff_file_store[0].set('M', "README.md");
    model.review_diff_file_store[1].set('M', "src/app/runtime.rs");
    model.review_diff_file_store[2].set('M', "src/app/view.rs");
    model.review_diff_file_store[3].set('M', "src/lib.rs");
    model.review_diff_file_store[4].set('M', "tests/review.rs");
    model.review_diff_file_count = 5;
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    {
        const rows = reviewDiffRows(&model, arena);
        try std.testing.expectEqual(@as(usize, 3), rows.len);
        try std.testing.expectEqualStrings("M README.md", rows[0].label);
        try std.testing.expectEqual(@as(u32, 1), rows[0].id);
        try std.testing.expectEqualStrings("src", rows[1].label);
        try std.testing.expect(rows[1].is_directory);
        try std.testing.expect(!rows[1].expanded);
        try std.testing.expectEqual((dirIdOfPath(&model, "src") orelse return error.MissingSrcDir), rows[1].id);
        try std.testing.expectEqualStrings("tests", rows[2].label);
        try std.testing.expect(!rows[2].expanded);
    }

    applyFilter(&model, .{ .insert_text = "  \t" });
    try std.testing.expectEqualStrings("", pathFilter(&model));
    {
        const rows = reviewDiffRows(&model, arena);
        try std.testing.expectEqual(@as(usize, 3), rows.len);
        try std.testing.expect(!rows[1].expanded);
        try std.testing.expect(!rows[2].expanded);
    }

    clearFilter(&model);
    applyFilter(&model, .{ .insert_text = "RUNTIME" });
    try std.testing.expectEqualStrings("RUNTIME", pathFilter(&model));
    try std.testing.expectEqual(@as(u32, 0), model.review_diff_expanded_count);
    {
        const rows = reviewDiffRows(&model, arena);
        try std.testing.expectEqual(@as(usize, 3), rows.len);
        try std.testing.expectEqualStrings("src", rows[0].label);
        try std.testing.expect(rows[0].is_directory);
        try std.testing.expect(rows[0].expanded);
        try std.testing.expectEqual((dirIdOfPath(&model, "src") orelse return error.MissingSrcDir), rows[0].id);
        try std.testing.expectEqualStrings("app", rows[1].label);
        try std.testing.expect(rows[1].is_directory);
        try std.testing.expect(rows[1].expanded);
        try std.testing.expectEqual((dirIdOfPath(&model, "src/app") orelse return error.MissingSrcAppDir), rows[1].id);
        try std.testing.expectEqualStrings("M runtime.rs", rows[2].label);
        try std.testing.expect(!rows[2].is_directory);
        try std.testing.expectEqual(@as(u32, 2), rows[2].id);
        try std.testing.expectEqual(@as(u32, 2), rows[2].depth);
    }

    clearFilter(&model);
    applyFilter(&model, .{ .insert_text = "zzzz" });
    {
        const rows = reviewDiffRows(&model, arena);
        try std.testing.expectEqual(@as(usize, 0), rows.len);
    }

    leaveSurface(&model);
    try std.testing.expectEqualStrings("", pathFilter(&model));
    try std.testing.expectEqualStrings("", model.review_diff_filter_buffer.text());
    {
        const rows = reviewDiffRows(&model, arena);
        try std.testing.expectEqual(@as(usize, 3), rows.len);
        try std.testing.expectEqualStrings("M README.md", rows[0].label);
        try std.testing.expectEqualStrings("src", rows[1].label);
        try std.testing.expect(!rows[1].expanded);
        try std.testing.expectEqualStrings("tests", rows[2].label);
        try std.testing.expect(!rows[2].expanded);
    }
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
    try expectNumstatOperand(branch_argv.?, git_upstream_range);
    applyLine(&model, .{ .key = branch_key, .line = "1\t1\tbranch-only.zig\n" });
    try std.testing.expectEqual(@as(u32, 1), model.review_diff_file_count);

    setSource(&model, &fx, .staged);
    try std.testing.expect(model.review_diff_active);
    try std.testing.expectEqual(Source.staged, model.review_diff_source);
    try std.testing.expect(model.review_diff_key != branch_key);
    try std.testing.expect(model.review_diff_key >= review_diff_key_first);
    try std.testing.expectEqual(@as(u32, 0), model.review_diff_file_count);
    try std.testing.expectEqualStrings(comparing_status, reviewDiffStatus(&model));

    applyLine(&model, .{ .key = branch_key, .line = "1\t0\tshould-ignore.txt\n" });
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
    try expectNumstatOperand(staged_argv orelse return error.MissingStagedArgv, git_cached_flag);
    applyLine(&model, .{ .key = staged_key, .line = "1\t0\tstaged.zig\n" });
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

    applyLine(&model, .{ .key = staged_key, .line = "1\t1\tshould-ignore-staged.zig\n" });
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
    try expectUncommittedArgv(uncommitted_argv orelse return error.MissingUncommittedArgv);
    applyLine(&model, .{ .key = uncommitted_key, .line = "2\t1\ttracked.zig\nN\t0\tnew.txt\n" });
    handleExit(&model, &fx, .{ .key = uncommitted_key, .reason = .exited, .code = 0 });
    try std.testing.expectEqual(@as(u32, 2), model.review_diff_file_count);
    try std.testing.expectEqualStrings("M tracked.zig", model.review_diff_file_store[0].label());
    try std.testing.expectEqual(@as(u64, 2), model.review_diff_file_store[0].additions);
    try std.testing.expectEqual(@as(u64, 1), model.review_diff_file_store[0].deletions);
    try std.testing.expectEqualStrings("? new.txt", model.review_diff_file_store[1].label());
    try std.testing.expectEqual(@as(u8, '?'), model.review_diff_file_store[1].status);
    try std.testing.expectEqual(@as(u64, 0), model.review_diff_file_store[1].additions);
    try std.testing.expectEqual(@as(u64, 0), model.review_diff_file_store[1].deletions);
    try std.testing.expect(!hasReviewDiffStatus(&model));

    setSource(&model, &fx, .unstaged);
    try std.testing.expect(model.review_diff_active);
    try std.testing.expectEqual(Source.unstaged, model.review_diff_source);
    try std.testing.expect(model.review_diff_key != uncommitted_key);
    try std.testing.expectEqual(@as(u32, 0), model.review_diff_file_count);
    try std.testing.expectEqualStrings(comparing_status, reviewDiffStatus(&model));

    applyLine(&model, .{ .key = uncommitted_key, .line = "1\t1\tshould-ignore-uncommitted.zig\n" });
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
    try expectUnstagedNumstatArgv(unstaged_argv orelse return error.MissingUnstagedArgv);
    applyLine(&model, .{ .key = unstaged_key, .line = "3\t1\tunstaged.zig\n" });
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

    applyLine(&model, .{ .key = unstaged_key, .line = "1\t1\tshould-ignore-unstaged.zig\n" });
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
    try expectNumstatOperand(committed_argv orelse return error.MissingCommittedArgv, git_committed_range);
    try std.testing.expectEqualStrings("origin/HEAD...HEAD", git_committed_range);
    applyLine(&model, .{ .key = committed_key, .line = "1\t1\tcommitted.zig\n" });
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
    try expectNumstatOperand(back_argv orelse return error.MissingBranchBackArgv, git_upstream_range);
    try std.testing.expectEqualStrings("@{upstream}...HEAD", git_upstream_range);

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

fn findSpawnArgv(fx: *Effects, key: u64) ?[]const []const u8 {
    var i: usize = 0;
    while (fx.pendingSpawnAt(i)) |spawn| : (i += 1) {
        if (spawn.key == key) return spawn.argv;
    }
    return null;
}

fn pendingSpawnKey(fx: *Effects, key: u64) ?@TypeOf(fx.pendingSpawnAt(0).?) {
    var i: usize = 0;
    while (fx.pendingSpawnAt(i)) |spawn| : (i += 1) {
        if (spawn.key == key) return spawn;
    }
    return null;
}

fn expectNumstatOperand(argv: []const []const u8, operand: []const u8) !void {
    try std.testing.expect(isGitReviewDiffArgv(argv));
    try std.testing.expect(!isGitReviewHunkArgv(argv));
    switch (builtin.os.tag) {
        .windows => {
            try std.testing.expectEqual(@as(usize, windows_argv_len), argv.len);
            try std.testing.expectEqualStrings(windows_git_bin, argv[0]);
            try std.testing.expectEqualStrings(git_c_flag, argv[1]);
            try std.testing.expectEqualStrings(git_diff_cmd, argv[3]);
            try std.testing.expectEqualStrings(git_numstat, argv[4]);
            try std.testing.expectEqualStrings(operand, argv[5]);
        },
        else => {
            try std.testing.expectEqual(@as(usize, unix_argv_len), argv.len);
            try std.testing.expectEqualStrings(git_numstat, argv[7]);
            try std.testing.expectEqualStrings(operand, argv[8]);
            try std.testing.expect(std.mem.indexOf(u8, argv[2], operand) == null);
            try std.testing.expect(std.mem.indexOf(u8, argv[2], git_numstat) == null);
        },
    }
}

fn expectUncommittedArgv(argv: []const []const u8) !void {
    try std.testing.expect(isGitReviewUncommittedArgv(argv));
    try std.testing.expect(isGitReviewDiffArgv(argv));
    try std.testing.expect(!isGitReviewHunkArgv(argv));
    switch (builtin.os.tag) {
        .windows => {
            try std.testing.expectEqual(@as(usize, windows_argv_len_uncommitted), argv.len);
            try std.testing.expectEqualStrings(powershell_bin, argv[0]);
            try std.testing.expectEqualStrings(powershell_uncommitted_untracked_script, argv[3]);
            try std.testing.expectEqualStrings(powershell_args_flag, argv[4]);
            try std.testing.expect(std.mem.indexOf(u8, argv[3], argv[5]) == null);
            try std.testing.expect(scriptHas(argv[3], git_numstat));
            try std.testing.expect(scriptHas(argv[3], "'N'+[char]9+'0'"));
        },
        else => {
            try std.testing.expectEqual(argv_len_uncommitted, argv.len);
            try std.testing.expectEqualStrings(uncommitted_untracked_script, argv[7]);
            try std.testing.expect(scriptHas(argv[7], git_numstat));
            try std.testing.expect(scriptHas(argv[7], "N\\t0\\t"));
            try std.testing.expect(std.mem.indexOf(u8, argv[2], git_head) == null);
            try std.testing.expect(std.mem.indexOf(u8, argv[2], uncommitted_untracked_script) == null);
        },
    }
}

fn expectUnstagedNumstatArgv(argv: []const []const u8) !void {
    try std.testing.expect(isGitReviewDiffArgv(argv));
    try std.testing.expect(!isGitReviewUncommittedArgv(argv));
    switch (builtin.os.tag) {
        .windows => {
            try std.testing.expectEqual(@as(usize, windows_argv_len_unstaged), argv.len);
            try std.testing.expectEqualStrings(git_numstat, argv[4]);
        },
        else => {
            try std.testing.expectEqual(argv_len_unstaged, argv.len);
            try std.testing.expectEqualStrings(git_numstat, argv[7]);
            try std.testing.expect(std.mem.indexOf(u8, argv[2], git_numstat) == null);
        },
    }
}

fn expectHunkArgv(argv: []const []const u8, operand: ?[]const u8, path: []const u8) !void {
    try std.testing.expect(isGitReviewHunkArgv(argv));
    try std.testing.expect(!isGitReviewDiffArgv(argv));
    try std.testing.expectEqualStrings(path, argv[argv.len - 1]);
    try std.testing.expectEqualStrings(git_pathspec_end, argv[argv.len - 2]);
    if (operand) |op| {
        try std.testing.expectEqualStrings(op, argv[argv.len - 3]);
    }
    switch (builtin.os.tag) {
        .windows => {
            const want: usize = if (operand == null) windows_argv_len_hunk_unstaged else windows_argv_len_hunk;
            try std.testing.expectEqual(want, argv.len);
            try std.testing.expectEqualStrings(windows_git_bin, argv[0]);
        },
        else => {
            const want: usize = if (operand == null) argv_len_hunk_unstaged else argv_len_hunk;
            try std.testing.expectEqual(want, argv.len);
            try std.testing.expect(std.mem.indexOf(u8, argv[2], path) == null);
            if (operand) |op| {
                try std.testing.expect(std.mem.indexOf(u8, argv[2], op) == null);
            }
        },
    }
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
    try expectNumstatOperand(origin_argv, git_committed_range);
    try std.testing.expectEqualStrings("origin/HEAD...HEAD", git_committed_range);

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
    try expectNumstatOperand(main_argv, git_committed_range_main);
    try std.testing.expectEqualStrings("main...HEAD", git_committed_range_main);

    handleExit(&model, &fx, .{ .key = main_key, .reason = .exited, .code = 128 });
    try std.testing.expectEqual(Source.committed, model.review_diff_source);
    try std.testing.expectEqual(CommittedRange.master, model.review_diff_committed_range);
    try std.testing.expectEqualStrings(comparing_status, reviewDiffStatus(&model));
    try std.testing.expect(model.review_diff_key != main_key);
    const master_key = model.review_diff_key;
    const master_argv = findSpawnArgv(&fx, master_key) orelse return error.MissingMasterArgv;
    try expectNumstatOperand(master_argv, git_committed_range_master);
    try std.testing.expectEqualStrings("master...HEAD", git_committed_range_master);

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
    try expectNumstatOperand(empty_origin_argv, git_committed_range);
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
    try expectNumstatOperand(main_argv, git_committed_range_main);

    setSource(&model, &fx, .branch);
    try std.testing.expectEqual(Source.branch, model.review_diff_source);
    try std.testing.expectEqual(CommittedRange.origin, model.review_diff_committed_range);
    try std.testing.expectEqualStrings(comparing_status, reviewDiffStatus(&model));
    try std.testing.expect(model.review_diff_key != main_key);
    const branch_key = model.review_diff_key;
    const branch_argv = findSpawnArgv(&fx, branch_key) orelse return error.MissingBranchAfterSwitch;
    try expectNumstatOperand(branch_argv, git_upstream_range);

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
    try expectNumstatOperand(origin_again_argv, git_committed_range);
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
    try expectNumstatOperand(last_turn_argv, range);
    try std.testing.expectEqualStrings("cccccccccccccccccccccccccccccccccccccccc...HEAD", range);
    try std.testing.expectEqualStrings(range, lastTurnRange(&model));

    applyLine(&model, .{ .key = last_turn_key, .line = "1\t1\tlast-turn.zig\n" });
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
    try expectHunkArgv(hunk_argv, range, "last-turn.zig");
    try std.testing.expect(std.mem.indexOf(u8, hunk_argv[hunk_argv.len - 3], "dddddddddddddddddddddddddddddddddddddddd") == null);

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
    try expectNumstatOperand(last_turn_argv, snap);
    try std.testing.expectEqualStrings(snap, snap_range);
    try std.testing.expect(std.mem.indexOf(u8, snap, git_last_turn_range_suffix) == null);
    try std.testing.expectEqualStrings(snap, lastTurnRange(&model));

    applyLine(&model, .{ .key = model.review_diff_key, .line = "1\t1\tsnap.zig\n" });
    handleExit(&model, &fx, .{ .key = model.review_diff_key, .reason = .exited, .code = 0 });
    if (model.sessionById(id)) |session| {
        session.appendRewindRef("dddddddddddddddddddddddddddddddddddddddd", rewind.recorded_ref, 2);
        session.setWorktreeSnapshotSha("eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee");
    }
    selectFile(&model, &fx, 1);
    const hunk_argv = findSpawnArgv(&fx, model.review_diff_hunk_key) orelse return error.MissingLastTurnSnapHunk;
    try std.testing.expect(isGitReviewHunkArgv(hunk_argv));
    try expectHunkArgv(hunk_argv, snap, "snap.zig");
    try std.testing.expect(std.mem.indexOf(u8, hunk_argv[hunk_argv.len - 3], git_last_turn_range_suffix) == null);
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
    try expectNumstatOperand(last_turn_argv, range);
    try std.testing.expectEqualStrings("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa..bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", range);
    try std.testing.expectEqual(@as(usize, 82), range.len);
    try std.testing.expect(std.mem.indexOf(u8, range, "...") == null);
    try std.testing.expectEqualStrings(range, lastTurnRange(&model));

    applyLine(&model, .{ .key = model.review_diff_key, .line = "1\t1\tstart-end.zig\n" });
    handleExit(&model, &fx, .{ .key = model.review_diff_key, .reason = .exited, .code = 0 });
    if (model.sessionById(id)) |session| {
        session.appendRewindRef("dddddddddddddddddddddddddddddddddddddddd", rewind.recorded_ref, 2);
        session.setWorktreeSnapshotSha("eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee");
        session.setWorktreeTurnEndSha("ffffffffffffffffffffffffffffffffffffffff");
    }
    selectFile(&model, &fx, 1);
    const hunk_argv = findSpawnArgv(&fx, model.review_diff_hunk_key) orelse return error.MissingLastTurnStartEndHunk;
    try std.testing.expect(isGitReviewHunkArgv(hunk_argv));
    try expectHunkArgv(hunk_argv, range, "start-end.zig");
    try std.testing.expect(std.mem.indexOf(u8, hunk_argv[hunk_argv.len - 3], "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee") == null);
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
    try expectNumstatOperand(last_turn_argv, range);
    try std.testing.expect(std.mem.indexOf(u8, range, start) == null);
    try std.testing.expectEqualStrings(range, lastTurnRange(&model));

    applyLine(&model, .{ .key = model.review_diff_key, .line = "1\t1\tdiff-end.zig\n" });
    handleExit(&model, &fx, .{ .key = model.review_diff_key, .reason = .exited, .code = 0 });
    if (model.sessionById(id)) |session| {
        session.setWorktreeSnapshotSha("eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee");
        session.setWorktreeTurnEndSha("ffffffffffffffffffffffffffffffffffffffff");
        session.setWorktreeTurnDiffSha("1111111111111111111111111111111111111111");
    }
    selectFile(&model, &fx, 1);
    const hunk_argv = findSpawnArgv(&fx, model.review_diff_hunk_key) orelse return error.MissingLastTurnDiffEndHunk;
    try std.testing.expect(isGitReviewHunkArgv(hunk_argv));
    try expectHunkArgv(hunk_argv, range, "diff-end.zig");
}

test "LastTurn start..end two-dot numstat is the edited path only" {
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
    const argv = unixArgvForLastTurn(path, range, &argv_buf);
    try testing.expectEqual(argv_len, argv.len);
    try testing.expectEqualStrings(range, argv[8]);
    try testing.expect(isGitReviewDiffArgv(argv));
    try testing.expect(!std.mem.eql(u8, argv[8], three));
    try testing.expect(std.mem.indexOf(u8, argv[8], "...") == null);
    try testing.expect(std.mem.indexOf(u8, argv[2], range) == null);

    var hunk_buf: [argv_len_hunk][]const u8 = undefined;
    const hunk = unixArgvForHunkLastTurn(path, range, "keep-a.txt", &hunk_buf);
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
        "--numstat",
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

test "cap stays at 64; extra numstat rows are dropped" {
    var model = Model{};
    model.review_diff_active = true;
    model.review_diff_key = review_diff_key_first;
    model.review_diff_probe_session = 0;
    var i: usize = 0;
    while (i < max_review_diff_files + 8) : (i += 1) {
        var line_buf: [32]u8 = undefined;
        const line = try std.fmt.bufPrint(&line_buf, "2\t1\tfile-{d}.txt\n", .{i});
        appendParsedNumstat(&model, line);
    }
    try std.testing.expectEqual(@as(u32, max_review_diff_files), model.review_diff_file_count);
}

test "hunk argv is chdir plus git diff operand -- path; Unstaged omits operand" {
    var buf: [argv_len_hunk][]const u8 = undefined;
    const branch = unixArgvForHunk(.branch, .origin, "/tmp/faku-hunk", "src/a.zig", &buf);
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
    const uncommitted = unixArgvForHunk(.uncommitted, .origin, "/tmp/faku-hunk", "tracked.zig", &uncommitted_buf);
    try std.testing.expectEqual(argv_len_hunk, uncommitted.len);
    try std.testing.expectEqualStrings(git_head, uncommitted[7]);
    try std.testing.expectEqualStrings(git_pathspec_end, uncommitted[8]);
    try std.testing.expectEqualStrings("tracked.zig", uncommitted[9]);
    try std.testing.expect(isGitReviewHunkArgv(uncommitted));
    try std.testing.expect(!isGitReviewDiffArgv(uncommitted));
    try std.testing.expect(!isGitReviewUncommittedArgv(uncommitted));
    try std.testing.expect(std.mem.indexOf(u8, uncommitted[2], git_head) == null);

    var staged_buf: [argv_len_hunk][]const u8 = undefined;
    const staged = unixArgvForHunk(.staged, .origin, "/tmp/faku-hunk", "staged.zig", &staged_buf);
    try std.testing.expectEqualStrings(git_cached_flag, staged[7]);
    try std.testing.expectEqualStrings(git_pathspec_end, staged[8]);
    try std.testing.expectEqualStrings("staged.zig", staged[9]);
    try std.testing.expect(isGitReviewHunkArgv(staged));
    try std.testing.expect(!isGitReviewDiffArgv(staged));
    try std.testing.expect(std.mem.indexOf(u8, staged[2], git_cached_flag) == null);

    var unstaged_buf: [argv_len_hunk][]const u8 = undefined;
    const unstaged = unixArgvForHunk(.unstaged, .origin, "/tmp/faku-hunk", "unstaged.zig", &unstaged_buf);
    try std.testing.expectEqual(argv_len_hunk_unstaged, unstaged.len);
    try std.testing.expectEqualStrings(git_pathspec_end, unstaged[7]);
    try std.testing.expectEqualStrings("unstaged.zig", unstaged[8]);
    try std.testing.expect(hunkOperand(.unstaged, .origin) == null);
    try std.testing.expect(isGitReviewHunkArgv(unstaged));
    try std.testing.expect(!isGitReviewDiffArgv(unstaged));
    try std.testing.expect(std.mem.indexOf(u8, unstaged[2], "unstaged.zig") == null);

    var committed_buf: [argv_len_hunk][]const u8 = undefined;
    const committed = unixArgvForHunk(.committed, .origin, "/tmp/faku-hunk", "committed.zig", &committed_buf);
    try std.testing.expectEqualStrings(git_committed_range, committed[7]);
    try std.testing.expectEqualStrings(git_pathspec_end, committed[8]);
    try std.testing.expect(isGitReviewHunkArgv(committed));
    try std.testing.expect(!isGitReviewDiffArgv(committed));

    var committed_main_buf: [argv_len_hunk][]const u8 = undefined;
    const committed_main = unixArgvForHunk(.committed, .main, "/tmp/faku-hunk", "committed.zig", &committed_main_buf);
    try std.testing.expectEqualStrings(git_committed_range_main, committed_main[7]);
    try std.testing.expectEqualStrings(git_pathspec_end, committed_main[8]);
    try std.testing.expect(isGitReviewHunkArgv(committed_main));
    try std.testing.expect(!isGitReviewDiffArgv(committed_main));

    var committed_master_buf: [argv_len_hunk][]const u8 = undefined;
    const committed_master = unixArgvForHunk(.committed, .master, "/tmp/faku-hunk", "committed.zig", &committed_master_buf);
    try std.testing.expectEqualStrings(git_committed_range_master, committed_master[7]);
    try std.testing.expect(isGitReviewHunkArgv(committed_master));
    try std.testing.expect(!isGitReviewDiffArgv(committed_master));

    const last_turn_sha = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    var last_turn_range_buf: [last_turn_range_len]u8 = undefined;
    const last_turn_range = formatLastTurnRange(last_turn_sha, &last_turn_range_buf) orelse return error.MissingLastTurnHunkRange;
    var last_turn_hunk_buf: [argv_len_hunk][]const u8 = undefined;
    const last_turn_hunk = unixArgvForHunkLastTurn("/tmp/faku-hunk", last_turn_range, "last-turn.zig", &last_turn_hunk_buf);
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
    const last_turn_snap_hunk = unixArgvForHunkLastTurn("/tmp/faku-hunk", last_turn_snap, "last-turn.zig", &last_turn_snap_hunk_buf);
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
    const last_turn_start_end_hunk = unixArgvForHunkLastTurn("/tmp/faku-hunk", last_turn_start_end_hunk_range, "last-turn.zig", &last_turn_start_end_hunk_buf);
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
    const untracked = unixArgvForUntrackedHunk("/tmp/faku-hunk", "new file.txt", &untracked_buf);
    try std.testing.expectEqual(unix_argv_len_hunk_untracked, untracked.len);
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

test "isGitReviewHunkArgv does not match numstat; numstat detector rejects hunks" {
    var name_buf: [argv_len][]const u8 = undefined;
    const name = unixArgvFor("/tmp/faku-hunk", &name_buf);
    try std.testing.expect(isGitReviewDiffArgv(name));
    try std.testing.expect(!isGitReviewHunkArgv(name));

    var uncommitted_buf: [argv_len][]const u8 = undefined;
    const uncommitted = unixArgvForSource(.uncommitted, "/tmp/faku-hunk", &uncommitted_buf);
    try std.testing.expect(isGitReviewDiffArgv(uncommitted));
    try std.testing.expect(isGitReviewUncommittedArgv(uncommitted));
    try std.testing.expect(!isGitReviewHunkArgv(uncommitted));

    var unstaged_name_buf: [argv_len][]const u8 = undefined;
    const unstaged_name = unixArgvForSource(.unstaged, "/tmp/faku-hunk", &unstaged_name_buf);
    try std.testing.expect(isGitReviewDiffArgv(unstaged_name));
    try std.testing.expect(!isGitReviewHunkArgv(unstaged_name));

    var hunk_buf: [argv_len_hunk][]const u8 = undefined;
    const hunk = unixArgvForHunk(.branch, .origin, "/tmp/faku-hunk", "src/a.zig", &hunk_buf);
    try std.testing.expect(isGitReviewHunkArgv(hunk));
    try std.testing.expect(!isGitReviewDiffArgv(hunk));
    try std.testing.expect(!isGitReviewUncommittedArgv(hunk));

    var unstaged_hunk_buf: [argv_len_hunk][]const u8 = undefined;
    const unstaged_hunk = unixArgvForHunk(.unstaged, .origin, "/tmp/faku-hunk", "src/a.zig", &unstaged_hunk_buf);
    try std.testing.expect(isGitReviewHunkArgv(unstaged_hunk));
    try std.testing.expect(!isGitReviewDiffArgv(unstaged_hunk));

    var untracked_buf: [argv_len_hunk_untracked][]const u8 = undefined;
    const untracked = unixArgvForUntrackedHunk("/tmp/faku-hunk", "new file.txt", &untracked_buf);
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
        git_numstat,
        git_upstream_range,
    }));
}

test "hunk path and -- are own argv slots; space in path stays last-slot" {
    var buf: [argv_len_hunk][]const u8 = undefined;
    const path = "src/my file.zig";
    const argv = unixArgvForHunk(.branch, .origin, "/tmp/faku hunk", path, &buf);
    try std.testing.expectEqual(argv_len_hunk, argv.len);
    try std.testing.expectEqualStrings(git_pathspec_end, argv[8]);
    try std.testing.expectEqualStrings(path, argv[9]);
    try std.testing.expect(std.mem.indexOf(u8, argv[2], path) == null);
    try std.testing.expect(std.mem.indexOf(u8, argv[2], "my file.zig") == null);
    try std.testing.expect(isGitReviewHunkArgv(argv));
    try std.testing.expect(!isGitReviewDiffArgv(argv));

    var unstaged_buf: [argv_len_hunk][]const u8 = undefined;
    const unstaged = unixArgvForHunk(.unstaged, .origin, "/tmp/faku hunk", path, &unstaged_buf);
    try std.testing.expectEqual(argv_len_hunk_unstaged, unstaged.len);
    try std.testing.expectEqualStrings(git_pathspec_end, unstaged[7]);
    try std.testing.expectEqualStrings(path, unstaged[8]);
    try std.testing.expect(std.mem.indexOf(u8, unstaged[2], path) == null);
    try std.testing.expect(isGitReviewHunkArgv(unstaged));

    var untracked_buf: [argv_len_hunk_untracked][]const u8 = undefined;
    const untracked_path = "new file.txt";
    const untracked = unixArgvForUntrackedHunk("/tmp/faku hunk", untracked_path, &untracked_buf);
    try std.testing.expectEqual(unix_argv_len_hunk_untracked, untracked.len);
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
    defer freeReviewDiffStores(&model);
    model.store_io = std.testing.io;
    const id = model.addSession("review hunk", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);

    _ = try openWithFiles(&model, &fx, "2\t1\tsrc/a.zig\n4\t0\tnew.txt\n");
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
    try expectHunkArgv(hunk_argv, git_upstream_range, "src/a.zig");

    applyHunkLine(&model, .{ .key = hunk_key, .line = "diff --git a/src/a.zig b/src/a.zig\n" });
    applyHunkLine(&model, .{ .key = hunk_key, .line = "--- a/src/a.zig\n+++ b/src/a.zig\n@@ -1 +1 @@\n-old\n+new\n" });
    handleHunkExit(&model, &fx, .{ .key = hunk_key, .reason = .exited, .code = 0 });
    try std.testing.expect(hasReviewDiffHunk(&model));
    try std.testing.expect(!hasReviewDiffHunkStatus(&model));
    try std.testing.expect(std.mem.indexOf(u8, reviewDiffHunk(&model), "diff --git a/src/a.zig b/src/a.zig") != null);
    try std.testing.expect(std.mem.indexOf(u8, reviewDiffHunk(&model), "+new") != null);
    try std.testing.expectEqual(@as(u64, 0), model.review_diff_hunk_key);
    try std.testing.expect(hasReviewDiffHunkRows(&model));
    var found_add = false;
    var found_del = false;
    for (model.review_diff_visible_store[0..model.review_diff_visible_count]) |line| {
        if (line.kind == .addition) found_add = true;
        if (line.kind == .deletion) found_del = true;
    }
    try std.testing.expect(found_add);
    try std.testing.expect(found_del);

    selectFile(&model, &fx, 2);
    try std.testing.expectEqual(@as(u32, 2), model.review_diff_selected_id);
    try std.testing.expect(!hasReviewDiffHunk(&model));
    try std.testing.expect(model.review_diff_hunk_key != hunk_key);
    const empty_key = model.review_diff_hunk_key;
    const empty_argv = findSpawnArgv(&fx, empty_key) orelse return error.MissingEmptyHunkArgv;
    try std.testing.expectEqualStrings("new.txt", empty_argv[empty_argv.len - 1]);
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
    var absent_buf: [32]u8 = undefined;
    const absent = try std.fmt.bufPrint(&absent_buf, "+line-{d}", .{max_review_diff_hunk_lines});
    try std.testing.expect(std.mem.indexOf(u8, reviewDiffHunk(&model), absent) == null);
}

fn loadHunkPatch(model: *Model, patch: []const u8, complete_context: bool) void {
    if (!ensureHunkBodyStore(model)) return;
    writeFixed(model.review_diff_hunk_storage, &model.review_diff_hunk_len, patch);
    model.review_diff_complete_context = complete_context;
    rebuildHunkRows(model);
}

fn firstGapIndex(model: *const Model) ?usize {
    for (model.review_diff_visible_store[0..model.review_diff_visible_count], 0..) |line, i| {
        if (line.kind == .gap) return i;
    }
    return null;
}

fn gapAt(model: *const Model, index: usize) DiffLine {
    return model.review_diff_visible_store[index];
}

fn fullContextPatch(total_lines: u32, changes: []const u32) ![]u8 {
    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(std.testing.allocator);
    try buf.appendSlice(std.testing.allocator, "diff --git a/src/lib.rs b/src/lib.rs\nindex 1111111..2222222 100644\n--- a/src/lib.rs\n+++ b/src/lib.rs\n");
    var hunk_buf: [64]u8 = undefined;
    const hunk = try std.fmt.bufPrint(&hunk_buf, "@@ -1,{d} +1,{d} @@\n", .{ total_lines, total_lines });
    try buf.appendSlice(std.testing.allocator, hunk);
    var line_buf: [64]u8 = undefined;
    var line_no: u32 = 1;
    while (line_no <= total_lines) : (line_no += 1) {
        var is_change = false;
        for (changes) |c| {
            if (c == line_no) is_change = true;
        }
        const piece = if (is_change)
            try std.fmt.bufPrint(&line_buf, "-let value_{d} = \"old\";\n+let value_{d} = \"new\";\n", .{ line_no, line_no })
        else
            try std.fmt.bufPrint(&line_buf, " line {d}\n", .{line_no});
        try buf.appendSlice(std.testing.allocator, piece);
    }
    return buf.toOwnedSlice(std.testing.allocator);
}

test "compact hunk parse inserts a non-expandable leading Gap" {
    var model = Model{};
    defer freeReviewDiffStores(&model);
    const patch =
        \\diff --git a/src/lib.rs b/src/lib.rs
        \\index 1111111..2222222 100644
        \\--- a/src/lib.rs
        \\+++ b/src/lib.rs
        \\@@ -5,2 +5,3 @@
        \\-let old = 1;
        \\+let fresh = 2;
        \\+return fresh;
        \\ context();
        \\
    ;
    loadHunkPatch(&model, patch, false);
    const gap_i = firstGapIndex(&model) orelse return error.MissingGap;
    const gap = gapAt(&model, gap_i);
    try std.testing.expectEqual(@as(u32, 4), gap.gap_count);
    try std.testing.expectEqual(GapPosition.leading, gap.gap_position);
    try std.testing.expect(!gapIsExpandable(gap));
    try std.testing.expectEqual(@as(u32, 5), model.review_diff_visible_store[gap_i + 1].old_line);
    try std.testing.expectEqual(LineKind.deletion, model.review_diff_visible_store[gap_i + 1].kind);
    try std.testing.expectEqual(LineKind.addition, model.review_diff_visible_store[gap_i + 2].kind);
    expandGap(&model, @intCast(gap_i + 1), .end);
    try std.testing.expectEqual(@as(u32, 4), gapAt(&model, firstGapIndex(&model).?).gap_count);
}

test "complete context collapses around changes and All expands the between Gap" {
    var model = Model{};
    defer freeReviewDiffStores(&model);
    const patch = try fullContextPatch(30, &.{ 8, 17 });
    defer std.testing.allocator.free(patch);
    loadHunkPatch(&model, patch, true);

    var leading: ?u32 = null;
    var between: ?u32 = null;
    var trailing: ?u32 = null;
    var between_index: usize = 0;
    for (model.review_diff_visible_store[0..model.review_diff_visible_count], 0..) |line, i| {
        if (line.kind != .gap) continue;
        switch (line.gap_position) {
            .leading => leading = line.gap_count,
            .between => {
                between = line.gap_count;
                between_index = i;
            },
            .trailing => trailing = line.gap_count,
        }
        try std.testing.expect(gapIsExpandable(line));
    }
    try std.testing.expectEqual(@as(u32, 4), leading.?);
    try std.testing.expectEqual(@as(u32, 2), between.?);
    try std.testing.expectEqual(@as(u32, 10), trailing.?);

    const previous_len = model.review_diff_visible_count;
    expandGap(&model, @intCast(between_index + 1), .all);
    try std.testing.expectEqual(previous_len + 1, model.review_diff_visible_count);
    var saw_12 = false;
    var saw_13 = false;
    for (model.review_diff_visible_store[0..model.review_diff_visible_count]) |line| {
        const text = lineContent(&model, line);
        if (std.mem.eql(u8, text, "line 12")) saw_12 = true;
        if (std.mem.eql(u8, text, "line 13")) saw_13 = true;
    }
    try std.testing.expect(saw_12);
    try std.testing.expect(saw_13);
}

test "End expansion reveals 100 retained lines from the gap edge" {
    var model = Model{};
    defer freeReviewDiffStores(&model);
    const patch = try fullContextPatch(230, &.{221});
    defer std.testing.allocator.free(patch);
    loadHunkPatch(&model, patch, true);
    const gap_i = firstGapIndex(&model) orelse return error.MissingLeadingGap;
    try std.testing.expectEqual(GapPosition.leading, gapAt(&model, gap_i).gap_position);
    try std.testing.expect(gapIsExpandable(gapAt(&model, gap_i)));

    expandGap(&model, @intCast(gap_i + 1), .end);
    try std.testing.expectEqual(LineKind.gap, gapAt(&model, gap_i).kind);
    try std.testing.expectEqual(@as(u32, 117), gapAt(&model, gap_i).gap_count);
    try std.testing.expectEqual(@as(u32, 118), model.review_diff_visible_store[gap_i + 1].new_line);

    expandGap(&model, @intCast(gap_i + 1), .end);
    try std.testing.expectEqual(@as(u32, 17), gapAt(&model, gap_i).gap_count);
    try std.testing.expectEqual(@as(u32, 18), model.review_diff_visible_store[gap_i + 1].new_line);

    expandGap(&model, @intCast(gap_i + 1), .end);
    try std.testing.expectEqual(LineKind.context, gapAt(&model, gap_i).kind);
    try std.testing.expectEqual(@as(u32, 1), model.review_diff_visible_store[gap_i].new_line);
}

test "Both expansion reveals 100 lines from each gap edge" {
    var model = Model{};
    defer freeReviewDiffStores(&model);
    const patch = try fullContextPatch(230, &.{221});
    defer std.testing.allocator.free(patch);
    loadHunkPatch(&model, patch, true);
    const gap_i = firstGapIndex(&model) orelse return error.MissingLeadingGap;
    expandGap(&model, @intCast(gap_i + 1), .both);
    try std.testing.expectEqual(@as(u32, 1), model.review_diff_visible_store[gap_i].new_line);
    try std.testing.expectEqual(LineKind.gap, model.review_diff_visible_store[gap_i + 100].kind);
    try std.testing.expectEqual(@as(u32, 17), model.review_diff_visible_store[gap_i + 100].gap_count);
    try std.testing.expectEqual(@as(u32, 118), model.review_diff_visible_store[gap_i + 101].new_line);
}

test "review diff line caps match Waku 50000 with proportional byte caps" {
    try std.testing.expectEqual(@as(usize, 50_000), max_rendered_diff_lines);
    try std.testing.expectEqual(@as(usize, 50_000), max_review_diff_hunk_lines);
    try std.testing.expectEqual(@as(usize, 50_000), max_review_diff_hidden_lines);
    try std.testing.expectEqual(max_review_diff_hunk_lines * 32, max_review_diff_hunk);
    try std.testing.expectEqual(max_review_diff_hunk, max_review_diff_daemon_patch);
}

test "complete-context Gap retain exceeds the old 4096-line cap" {
    var model = Model{};
    defer freeReviewDiffStores(&model);
    const patch = try fullContextPatch(5000, &.{4200});
    defer std.testing.allocator.free(patch);
    loadHunkPatch(&model, patch, true);
    const gap_i = firstGapIndex(&model) orelse return error.MissingLeadingGap;
    try std.testing.expectEqual(GapPosition.leading, gapAt(&model, gap_i).gap_position);
    try std.testing.expect(gapAt(&model, gap_i).gap_count > 4096);
    try std.testing.expect(gapIsExpandable(gapAt(&model, gap_i)));

    expandGap(&model, @intCast(gap_i + 1), .all);
    try std.testing.expect(model.review_diff_visible_count > 4096);
}

test "review_diff_hunk_rows expose addition deletion and gap expand controls" {
    var model = Model{};
    defer freeReviewDiffStores(&model);
    const patch = try fullContextPatch(30, &.{8});
    defer std.testing.allocator.free(patch);
    loadHunkPatch(&model, patch, true);
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const rows = reviewDiffHunkRows(&model, arena_state.allocator());
    try std.testing.expect(rows.len > 0);
    var saw_add = false;
    var saw_del = false;
    var saw_gap = false;
    for (rows) |row| {
        if (row.is_addition) saw_add = true;
        if (row.is_deletion) saw_del = true;
        if (row.is_gap) {
            saw_gap = true;
            try std.testing.expect(std.mem.indexOf(u8, row.text, "unmodified") != null);
            try std.testing.expect(row.can_expand_all);
        }
    }
    try std.testing.expect(saw_add);
    try std.testing.expect(saw_del);
    try std.testing.expect(saw_gap);
}

test "review_diff_hunk_rows expose Waku shown_line gutter numbers" {
    var model = Model{};
    defer freeReviewDiffStores(&model);
    const patch =
        \\diff --git a/src/lib.rs b/src/lib.rs
        \\--- a/src/lib.rs
        \\+++ b/src/lib.rs
        \\@@ -10,2 +10,4 @@
        \\ keep
        \\-drop
        \\+add
        \\+extra
        \\ still
        \\
    ;
    loadHunkPatch(&model, patch, false);
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const rows = reviewDiffHunkRows(&model, arena_state.allocator());

    var saw_gap = false;
    var saw_keep = false;
    var saw_drop = false;
    var saw_add = false;
    var saw_extra = false;
    var saw_still = false;
    for (rows) |row| {
        if (row.is_gap) {
            try std.testing.expect(!row.has_line_number);
            try std.testing.expectEqualStrings("", row.line_number);
            saw_gap = true;
            continue;
        }
        if (std.mem.eql(u8, row.text, "keep")) {
            try std.testing.expect(row.has_line_number);
            try std.testing.expectEqualStrings("10", row.line_number);
            saw_keep = true;
        } else if (row.is_deletion) {
            try std.testing.expect(row.has_line_number);
            try std.testing.expectEqualStrings("11", row.line_number);
            try std.testing.expectEqualStrings("drop", row.text);
            saw_drop = true;
        } else if (row.is_addition and std.mem.eql(u8, row.text, "add")) {
            try std.testing.expect(row.has_line_number);
            try std.testing.expectEqualStrings("11", row.line_number);
            saw_add = true;
        } else if (row.is_addition and std.mem.eql(u8, row.text, "extra")) {
            try std.testing.expect(row.has_line_number);
            try std.testing.expectEqualStrings("12", row.line_number);
            saw_extra = true;
        } else if (std.mem.eql(u8, row.text, "still")) {
            try std.testing.expect(row.has_line_number);
            try std.testing.expectEqualStrings("13", row.line_number);
            saw_still = true;
        }
    }
    try std.testing.expect(saw_gap);
    try std.testing.expect(saw_keep);
    try std.testing.expect(saw_drop);
    try std.testing.expect(saw_add);
    try std.testing.expect(saw_extra);
    try std.testing.expect(saw_still);
}

test "review_diff_hunk_rows omit gutter when unpositioned or zero" {
    var model = Model{};
    defer freeReviewDiffStores(&model);
    const patch =
        \\diff --git a/src/a.zig b/src/a.zig
        \\@@
        \\ keep
        \\-old
        \\+new
        \\
    ;
    loadHunkPatch(&model, patch, false);
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const rows = reviewDiffHunkRows(&model, arena_state.allocator());
    try std.testing.expect(rows.len >= 3);
    var saw_ctx = false;
    var saw_del = false;
    var saw_add = false;
    for (rows) |row| {
        try std.testing.expect(!row.has_line_number);
        try std.testing.expectEqualStrings("", row.line_number);
        if (std.mem.eql(u8, row.text, "keep")) saw_ctx = true;
        if (row.is_deletion) saw_del = true;
        if (row.is_addition) saw_add = true;
    }
    try std.testing.expect(saw_ctx);
    try std.testing.expect(saw_del);
    try std.testing.expect(saw_add);

    const zero_patch =
        \\diff --git a/src/a.zig b/src/a.zig
        \\+hello
        \\
    ;
    loadHunkPatch(&model, zero_patch, false);
    const zero_rows = reviewDiffHunkRows(&model, arena_state.allocator());
    try std.testing.expectEqual(@as(usize, 1), zero_rows.len);
    try std.testing.expect(zero_rows[0].is_addition);
    try std.testing.expect(!zero_rows[0].has_line_number);
    try std.testing.expectEqualStrings("", zero_rows[0].line_number);
    try std.testing.expectEqualStrings("hello", zero_rows[0].text);
}

test "review_diff_hunk_rows code body omits unified-diff marker" {
    var model = Model{};
    defer freeReviewDiffStores(&model);
    const patch =
        \\diff --git a/src/a.zig b/src/a.zig
        \\--- a/src/a.zig
        \\+++ b/src/a.zig
        \\@@ -1,2 +1,3 @@
        \\ keep
        \\-drop
        \\+add
        \\+
        \\\ No newline at end of file
        \\
    ;
    loadHunkPatch(&model, patch, false);
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const rows = reviewDiffHunkRows(&model, arena_state.allocator());

    var saw_keep = false;
    var saw_drop = false;
    var saw_add = false;
    var saw_empty_add = false;
    var saw_meta = false;
    for (rows) |row| {
        if (row.is_gap) continue;
        if (std.mem.eql(u8, row.text, "keep")) {
            try std.testing.expect(!row.is_addition);
            try std.testing.expect(!row.is_deletion);
            saw_keep = true;
        } else if (row.is_deletion) {
            try std.testing.expectEqualStrings("drop", row.text);
            saw_drop = true;
        } else if (row.is_addition and std.mem.eql(u8, row.text, "add")) {
            saw_add = true;
        } else if (row.is_addition and row.text.len == 0) {
            saw_empty_add = true;
        } else if (std.mem.eql(u8, row.text, "\\ No newline at end of file")) {
            try std.testing.expect(!row.is_addition);
            try std.testing.expect(!row.is_deletion);
            try std.testing.expect(!row.has_line_number);
            saw_meta = true;
        }
        if (row.is_addition or row.is_deletion or std.mem.eql(u8, row.text, "keep")) {
            try std.testing.expect(!std.mem.startsWith(u8, row.text, "+"));
            try std.testing.expect(!std.mem.startsWith(u8, row.text, "-"));
        }
    }
    try std.testing.expect(saw_keep);
    try std.testing.expect(saw_drop);
    try std.testing.expect(saw_add);
    try std.testing.expect(saw_empty_add);
    try std.testing.expect(saw_meta);
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
    defer freeReviewDiffStores(&model);
    model.store_io = std.testing.io;
    const id = model.addSession("review hunk untracked", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);

    open(&model, &fx);
    setSource(&model, &fx, .uncommitted);
    const name_key = model.review_diff_key;
    applyLine(&model, .{ .key = name_key, .line = "2\t1\ttracked.zig\nN\t0\tnew file.txt\n" });
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
    switch (builtin.os.tag) {
        .windows => {
            try std.testing.expectEqual(windows_argv_len_hunk_untracked, untracked_argv.len);
            try std.testing.expectEqualStrings(windows_git_bin, untracked_argv[0]);
            try std.testing.expectEqualStrings(git_c_flag, untracked_argv[1]);
            try std.testing.expectEqualStrings(git_diff_cmd, untracked_argv[3]);
            try std.testing.expectEqualStrings(git_no_index, untracked_argv[4]);
            try std.testing.expectEqualStrings(git_pathspec_end, untracked_argv[5]);
            try std.testing.expectEqualStrings(git_nul, untracked_argv[6]);
            try std.testing.expectEqualStrings("new file.txt", untracked_argv[7]);
            try std.testing.expect(std.mem.indexOf(u8, untracked_argv[2], "new file.txt") == null);
            try std.testing.expect(std.mem.indexOf(u8, untracked_argv[2], git_nul) == null);
        },
        else => {
            try std.testing.expectEqual(unix_argv_len_hunk_untracked, untracked_argv.len);
            try std.testing.expectEqualStrings(git_bin, untracked_argv[5]);
            try std.testing.expectEqualStrings(git_diff_cmd, untracked_argv[6]);
            try std.testing.expectEqualStrings(git_no_index, untracked_argv[7]);
            try std.testing.expectEqualStrings(git_pathspec_end, untracked_argv[8]);
            try std.testing.expectEqualStrings(git_dev_null, untracked_argv[9]);
            try std.testing.expectEqualStrings("new file.txt", untracked_argv[10]);
            try std.testing.expect(std.mem.indexOf(u8, untracked_argv[2], "new file.txt") == null);
            try std.testing.expect(std.mem.indexOf(u8, untracked_argv[2], git_dev_null) == null);
        },
    }

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
    try expectHunkArgv(tracked_argv, git_head, "tracked.zig");
    try std.testing.expect(!std.mem.eql(u8, tracked_argv[tracked_argv.len - 3], git_no_index));
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
    defer freeReviewDiffStores(&model);
    model.store_io = std.testing.io;
    const id = model.addSession("review hunk cancel", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);

    _ = try openWithFiles(&model, &fx, "2\t1\tsrc/a.zig\n");
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

    applyLine(&model, .{ .key = model.review_diff_key, .line = "1\t0\tstaged.zig\n" });
    handleExit(&model, &fx, .{ .key = model.review_diff_key, .reason = .exited, .code = 0 });
    selectFile(&model, &fx, 1);
    const again = model.review_diff_hunk_key;
    try std.testing.expect(again != hunk_key);
    const staged_argv = findSpawnArgv(&fx, again) orelse return error.MissingStagedHunk;
    try expectHunkArgv(staged_argv, git_cached_flag, "staged.zig");

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
    applyLine(&model, .{ .key = model.review_diff_key, .line = "1\t1\tcommitted.zig\n" });
    handleExit(&model, &fx, .{ .key = model.review_diff_key, .reason = .exited, .code = 0 });
    try std.testing.expectEqual(CommittedRange.main, model.review_diff_committed_range);

    selectFile(&model, &fx, 1);
    const hunk_key = model.review_diff_hunk_key;
    const hunk_argv = findSpawnArgv(&fx, hunk_key) orelse return error.MissingCommittedHunk;
    try expectHunkArgv(hunk_argv, git_committed_range_main, "committed.zig");
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
