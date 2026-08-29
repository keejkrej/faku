//! First-cut Waku Environment Compare / Review file list.
//!
//! Environment Compare and header +/- close the Environment
//! Summary popover (when open) and open a runtime-only Review
//! card. Initial source is Branch: one-shot
//! `git diff --name-status @{upstream}...HEAD` (symmetric range,
//! same spirit as ahead/behind). Uncommitted is a switchable
//! first-cut: one-shot `git diff --name-status HEAD` (tracked
//! staged+unstaged vs HEAD). Staged is a switchable first-cut:
//! one-shot `git diff --name-status --cached` (index vs HEAD;
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
//! fall-through). Faku has no checkpoint `capture_worktree_commit`;
//! LastTurn, hunks, and untracked-in-Uncommitted stay leftover.
//! All five use the `/bin/sh -c` `fx_ask_chdir_script` chdir
//! workaround. Last-slot operands (`@{upstream}...HEAD` / `HEAD`
//! / `--cached` / `origin/HEAD...HEAD` / `main...HEAD` /
//! `master...HEAD`) are their own argv slots — never
//! interpolated into `-c`. Unstaged has no trailing operand, so
//! its argv is 8 slots (the 9-slot detector still accepts the
//! others). Distinct spawn-key band 510+ (after git-common-dir
//! 500+). Cap 64 rows. Empty / clean is `No changes to compare`.
//! Failed / no upstream / missing workspace is a short muted
//! status — no invented files. Not hunk rendering, not LastTurn,
//! not background work, and not daemon WorkspaceOperation.
//!
//! Spawn/line/exit orchestration lives here. Windows is skipped
//! (app.zon is macos/linux; no Windows spawn path).

const std = @import("std");
const builtin = @import("builtin");
const native_sdk = @import("native_sdk");
const main = @import("main.zig");
const git_ahead_behind = @import("git_ahead_behind.zig");
const git_checkout = @import("git_checkout.zig");
const git_common_dir = @import("git_common_dir.zig");

const Model = main.Model;
const Effects = main.Effects;
const writeFixed = main.writeFixed;

/// One-shot Review `git diff --name-status` (Branch,
/// Uncommitted, Staged, Unstaged, or Committed). Distinct from git_branch
/// (200+), git_dirty (300+), git_numstat (350+), git_push
/// (360+), git_worktree_add (370+), git_ahead_behind (380+),
/// git_worktree_base (390+), file_mention (400+), git_commit
/// (450+), git_commit_numstat (460+), generate (470+), remotes
/// (480+), toplevel (490+), and common-dir (500+). Band is 510+.
/// Incremented per open / source switch so a cancelled spawn
/// cannot paint a later session.
pub const review_diff_key_first: u64 = 510;

/// Compare / header +/- open Branch. Uncommitted is first-cut
/// tracked `git diff --name-status HEAD` (not untracked). Staged
/// is first-cut index vs HEAD `git diff --name-status --cached`.
/// Unstaged is first-cut worktree vs index `git diff
/// --name-status` (tracked only). Committed is first-cut
/// `git diff --name-status origin/HEAD...HEAD`, then local
/// `main...HEAD` / `master...HEAD` on a still-current non-zero
/// exit. LastTurn / hunks / untracked-in-Uncommitted stay leftover.
pub const Source = enum {
    branch,
    uncommitted,
    staged,
    unstaged,
    committed,
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
pub const sh_bin = "/bin/sh";

/// `/bin/sh -c` chdir + `git diff --name-status` + last-slot operand
/// (Branch / Uncommitted / Staged / Committed). Unstaged omits the operand.
pub const argv_len: usize = 9;
/// Unstaged: same chdir prefix, no trailing operand.
pub const argv_len_unstaged: usize = 8;

pub const comparing_status = "Comparing…";
pub const empty_status = "No changes to compare";
pub const failed_status = "Could not compare.";
pub const no_workspace_status = "No workspace.";

/// Native `for each="review_diff_rows"` row. `id` is 1-based.
pub const ReviewDiffRow = struct {
    id: u32,
    label: []const u8,
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
/// Committed reads `committed_range` (default first probe is
/// `origin/HEAD...HEAD`).
pub fn lastOperand(source: Source, committed_range: CommittedRange) ?[]const u8 {
    return switch (source) {
        .branch => git_upstream_range,
        .uncommitted => git_head,
        .staged => git_cached_flag,
        .unstaged => null,
        .committed => switch (committed_range) {
            .origin => git_committed_range,
            .main => git_committed_range_main,
            .master => git_committed_range_master,
        },
    };
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
    buf[0] = sh_bin;
    buf[1] = "-c";
    buf[2] = main.fx_ask_chdir_script;
    buf[3] = "sh";
    buf[4] = cwd;
    buf[5] = git_bin;
    buf[6] = git_diff_cmd;
    buf[7] = git_name_status;
    if (lastOperand(source, committed_range)) |operand| {
        buf[8] = operand;
        return buf[0..argv_len];
    }
    return buf[0..argv_len_unstaged];
}

/// Branch argv. Compare / header +/- still use this shape.
pub fn argvFor(cwd: []const u8, buf: *[argv_len][]const u8) []const []const u8 {
    return argvForSource(.branch, cwd, buf);
}

pub fn isGitReviewDiffArgv(argv: []const []const u8) bool {
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
        std.mem.eql(u8, last, git_head) or
        std.mem.eql(u8, last, git_cached_flag) or
        std.mem.eql(u8, last, git_committed_range) or
        std.mem.eql(u8, last, git_committed_range_main) or
        std.mem.eql(u8, last, git_committed_range_master);
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
        };
    }
    return out;
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

fn cancelInFlight(model: *Model, fx: *Effects) void {
    if (model.review_diff_key == 0) return;
    fx.cancel(model.review_diff_key);
    model.review_diff_key = 0;
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

/// Cancel any in-flight probe, drop files / status, and close the card.
pub fn close(model: *Model, fx: *Effects) void {
    cancelInFlight(model, fx);
    clearFiles(model);
    clearStatus(model);
    model.review_diff_probe_session = 0;
    model.review_diff_probe_path_len = 0;
    model.review_diff_committed_range = .origin;
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
    clearFiles(model);
    clearStatus(model);
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

    const key = model.next_review_diff_key;
    model.next_review_diff_key = key + 1;
    model.review_diff_key = key;
    model.review_diff_probe_session = model.selected;
    writeFixed(&model.review_diff_probe_path_storage, &model.review_diff_probe_path_len, cwd);
    setStatus(model, comparing_status);

    var argv_buf: [argv_len][]const u8 = undefined;
    fx.spawn(.{
        .key = key,
        .argv = argvForSourceRange(
            model.review_diff_source,
            model.review_diff_committed_range,
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
pub fn open(model: *Model, fx: *Effects) void {
    prepareCard(model, fx);
    if (git_checkout.gitMutationInFlight(model)) return;
    if (model.is_streaming()) return;
    model.review_diff_active = true;
    model.review_diff_source = .branch;
    startProbe(model, fx);
}

/// Switch the Review name-status source, cancel any in-flight
/// 510+ spawn, clear rows / status, and re-probe. Committed
/// always restarts at `origin/HEAD...HEAD` (no leftover
/// main/master retry). No-op when the card is closed. Does not
/// invent LastTurn.
pub fn setSource(model: *Model, fx: *Effects, source: Source) void {
    if (!model.review_diff_active) return;
    model.review_diff_source = source;
    model.review_diff_committed_range = .origin;
    startProbe(model, fx);
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
    try std.testing.expectEqual(@as(usize, 9), uncommitted.len);
    try std.testing.expectEqualStrings(sh_bin, uncommitted[0]);
    try std.testing.expectEqualStrings("-c", uncommitted[1]);
    try std.testing.expectEqualStrings(main.fx_ask_chdir_script, uncommitted[2]);
    try std.testing.expectEqualStrings("sh", uncommitted[3]);
    try std.testing.expectEqualStrings("/tmp/faku-review", uncommitted[4]);
    try std.testing.expectEqualStrings(git_bin, uncommitted[5]);
    try std.testing.expectEqualStrings(git_diff_cmd, uncommitted[6]);
    try std.testing.expectEqualStrings(git_name_status, uncommitted[7]);
    try std.testing.expectEqualStrings(git_head, uncommitted[8]);
    try std.testing.expectEqualStrings("HEAD", uncommitted[8]);
    try std.testing.expect(isGitReviewDiffArgv(uncommitted));
    try std.testing.expect(std.mem.indexOf(u8, uncommitted[2], git_head) == null);
    try std.testing.expect(std.mem.indexOf(u8, uncommitted[2], git_name_status) == null);
    try std.testing.expect(!isGitReviewDiffArgv(&.{ git_bin, git_diff_cmd, git_name_status, git_head }));
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
    const numstat = git_numstat.argvFor("/tmp/faku-review", &numstat_buf);
    try std.testing.expect(!isGitReviewDiffArgv(numstat));
    try std.testing.expect(!git_numstat.isGitNumstatArgv(argv));
    try std.testing.expect(!file_mention.isGitLsFilesArgv(argv));
    try std.testing.expect(review_diff_key_first >= 510);
    try std.testing.expect(review_diff_key_first > git_common_dir.git_common_dir_key_first);
    try std.testing.expect(git_common_dir.git_common_dir_key_first >= 500);
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
    try std.testing.expect(parseNameStatusLine("") == null);
    try std.testing.expect(parseNameStatusLine("   \n") == null);
    try std.testing.expect(parseNameStatusLine("not-status") == null);
    try std.testing.expect(parseNameStatusLine("M") == null);
    try std.testing.expect(parseNameStatusLine("M\t") == null);
    try std.testing.expect(parseNameStatusLine("1\tbad.txt") == null);
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
    try std.testing.expectEqualStrings(git_head, uncommitted_argv.?[8]);
    try std.testing.expect(std.mem.indexOf(u8, uncommitted_argv.?[2], git_head) == null);
    applyLine(&model, .{ .key = uncommitted_key, .line = "M\ttracked.zig\n" });
    handleExit(&model, &fx, .{ .key = uncommitted_key, .reason = .exited, .code = 0 });
    try std.testing.expectEqual(@as(u32, 1), model.review_diff_file_count);
    try std.testing.expectEqualStrings("M tracked.zig", model.review_diff_file_store[0].label());
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
