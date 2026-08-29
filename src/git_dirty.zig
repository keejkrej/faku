//! One-shot dirty-file count plus porcelain XY flags for the composer
//! project row / Commit… gate.
//!
//! Native has no git/workspace effect. When the selected session has a
//! non-empty `project_path` that exists, Faku `fx.spawn`s
//! `git status --porcelain` through the same `/bin/sh -c` chdir
//! workaround `fx ask` uses (`fx_ask_chdir_script`). Non-empty stdout
//! lines are counted as dirty files (porcelain one line per path).
//! The same stdout also sets `has_staged` / `has_unstaged` with Waku
//! `status_flags` rules (X not space/`?` → staged; Y not space or
//! X is `?` → unstaged). Zero / failed / empty / cancel / session
//! switch omits the label and clears both flags — this cut does not
//! invent "clean". Not Waku's daemon `InspectBranches`, not a live
//! watch, not commit-card snapshot numstat, and not Waku's Environment
//! Summary.
//!
//! Spawn/line/exit orchestration lives here. Windows is skipped
//! (app.zon is macos/linux; no Windows spawn path).

const std = @import("std");
const builtin = @import("builtin");
const native_sdk = @import("native_sdk");
const main = @import("main.zig");

const Model = main.Model;
const Effects = main.Effects;
const writeFixed = main.writeFixed;

/// One-shot `git status --porcelain` probe. Distinct from git_branch
/// (200+), git_numstat (350+), git_push (360+), git_worktree_add
/// (370+), git_ahead_behind (380+), maximize / pick-image / fx-ask /
/// daemon / clipboard / probe keys, and from file_mention (400+).
/// Incremented per refresh so a cancelled spawn cannot paint a later
/// session.
pub const git_dirty_key_first: u64 = 300;

/// `4294967295 changes` is 19 bytes. Keep headroom.
pub const max_git_dirty_label: usize = 24;

pub const git_bin = "git";
pub const git_status_cmd = "status";
pub const git_porcelain = "--porcelain";
pub const sh_bin = "/bin/sh";

const chdir_argv_len: usize = 8;

pub fn argvFor(cwd: []const u8, buf: *[chdir_argv_len][]const u8) []const []const u8 {
    buf.* = .{
        sh_bin,
        "-c",
        main.fx_ask_chdir_script,
        "sh",
        cwd,
        git_bin,
        git_status_cmd,
        git_porcelain,
    };
    return buf;
}

pub fn isGitDirtyArgv(argv: []const []const u8) bool {
    if (argv.len != chdir_argv_len) return false;
    if (!std.mem.eql(u8, argv[0], sh_bin)) return false;
    if (!std.mem.eql(u8, argv[1], "-c")) return false;
    if (!std.mem.eql(u8, argv[2], main.fx_ask_chdir_script)) return false;
    if (!std.mem.eql(u8, argv[5], git_bin)) return false;
    if (!std.mem.eql(u8, argv[6], git_status_cmd)) return false;
    return std.mem.eql(u8, argv[7], git_porcelain);
}

/// Non-empty porcelain lines (trim whitespace). Blank lines ignored.
pub fn isCountedDirtyLine(raw: []const u8) bool {
    return std.mem.trim(u8, raw, " \t\r\n").len > 0;
}

/// Waku `status_flags` over one `git status --porcelain` (v1) line.
/// Leading spaces are status, not padding — do not trim the left side.
pub const PorcelainFlags = struct {
    has_staged: bool = false,
    has_unstaged: bool = false,

    pub fn merge(self: *PorcelainFlags, other: PorcelainFlags) void {
        self.has_staged = self.has_staged or other.has_staged;
        self.has_unstaged = self.has_unstaged or other.has_unstaged;
    }
};

/// Staged when X is not space or `?`. Unstaged when Y is not space or
/// X is `?` (untracked `??`). Lines shorter than two columns are ignored.
pub fn porcelainFlagsForLine(raw: []const u8) PorcelainFlags {
    const row = std.mem.trimEnd(u8, raw, "\r");
    if (row.len < 2) return .{};
    const x = row[0];
    const y = row[1];
    return .{
        .has_staged = x != ' ' and x != '?',
        .has_unstaged = y != ' ' or x == '?',
    };
}

/// Fold XY flags across a stdout chunk. Blank / short lines skipped.
pub fn porcelainFlags(raw: []const u8) PorcelainFlags {
    var flags = PorcelainFlags{};
    var it = std.mem.splitScalar(u8, raw, '\n');
    while (it.next()) |line| {
        flags.merge(porcelainFlagsForLine(line));
    }
    return flags;
}

/// Count non-empty lines in a stdout chunk. `on_line` is usually one
/// path; a batched payload still counts each porcelain line.
pub fn countNonEmptyLines(raw: []const u8) u32 {
    var n: u32 = 0;
    var it = std.mem.splitScalar(u8, raw, '\n');
    while (it.next()) |line| {
        if (!isCountedDirtyLine(line)) continue;
        n +|= 1;
    }
    return n;
}

/// `1 change` / `N changes`. Empty when count is 0 (do not invent
/// "clean"). Exact number even when huge; `buf` holds u32 + word.
pub fn dirtyLabel(count: u32, buf: *[max_git_dirty_label]u8) []const u8 {
    if (count == 0) return "";
    const word: []const u8 = if (count == 1) "change" else "changes";
    return std.fmt.bufPrint(buf, "{d} {s}", .{ count, word }) catch "";
}

pub fn gitDirtyLabel(model: *const Model) []const u8 {
    return model.git_dirty_label_storage[0..model.git_dirty_label_len];
}

pub fn hasGitDirty(model: *const Model) bool {
    return model.git_dirty_count > 0;
}

pub fn clearGitDirty(model: *Model) void {
    setDirtyCount(model, 0);
    model.git_has_staged = false;
    model.git_has_unstaged = false;
}

fn setDirtyCount(model: *Model, count: u32) void {
    model.git_dirty_count = count;
    if (count == 0) {
        model.git_dirty_label_len = 0;
        return;
    }
    const written = dirtyLabel(count, &model.git_dirty_label_storage);
    model.git_dirty_label_len = written.len;
}

fn addDirtyLines(model: *Model, n: u32) void {
    if (n == 0) return;
    setDirtyCount(model, model.git_dirty_count +| n);
}

fn cancelInFlight(model: *Model, fx: *Effects) void {
    if (model.git_dirty_key == 0) return;
    fx.cancel(model.git_dirty_key);
    model.git_dirty_key = 0;
}

fn probePath(model: *const Model) []const u8 {
    const path = model.selectedProjectPath();
    if (path.len == 0) return "";
    const io = model.store_io orelse return "";
    if (!main.directoryExists(io, path)) return "";
    return path;
}

/// Cancel any in-flight probe, drop the label, and spawn again when the
/// selected session has an existing `project_path`. Empty / missing /
/// Windows skips the spawn so the label stays omitted.
pub fn refresh(model: *Model, fx: *Effects) void {
    cancelInFlight(model, fx);
    clearGitDirty(model);
    if (builtin.os.tag == .windows) return;
    const cwd = probePath(model);
    if (cwd.len == 0) return;

    const key = model.next_git_dirty_key;
    model.next_git_dirty_key = key + 1;
    model.git_dirty_key = key;
    model.git_dirty_probe_session = model.selected;
    writeFixed(&model.git_dirty_probe_path_storage, &model.git_dirty_probe_path_len, cwd);

    var argv_buf: [chdir_argv_len][]const u8 = undefined;
    fx.spawn(.{
        .key = key,
        .argv = argvFor(cwd, &argv_buf),
        .on_line = Effects.lineMsg(.fx_line),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
}

fn probeStillCurrent(model: *const Model) bool {
    if (model.git_dirty_key == 0) return false;
    if (model.git_dirty_probe_session != model.selected) return false;
    const path = model.selectedProjectPath();
    const probed = model.git_dirty_probe_path_storage[0..model.git_dirty_probe_path_len];
    return std.mem.eql(u8, path, probed);
}

pub fn applyLine(model: *Model, line: native_sdk.EffectLine) void {
    if (line.key != model.git_dirty_key or model.git_dirty_key == 0) return;
    if (!probeStillCurrent(model)) return;
    addDirtyLines(model, countNonEmptyLines(line.line));
    const flags = porcelainFlags(line.line);
    model.git_has_staged = model.git_has_staged or flags.has_staged;
    model.git_has_unstaged = model.git_has_unstaged or flags.has_unstaged;
}

pub fn handleExit(model: *Model, exit: native_sdk.EffectExit) void {
    if (exit.key != model.git_dirty_key or model.git_dirty_key == 0) return;
    const current = probeStillCurrent(model);
    model.git_dirty_key = 0;
    if (!current or exit.reason != .exited or exit.code != 0) {
        clearGitDirty(model);
    }
}

test "argv is chdir script plus git status --porcelain" {
    const git_branch = @import("git_branch.zig");
    const git_numstat = @import("git_numstat.zig");
    const git_ahead_behind = @import("git_ahead_behind.zig");
    const file_mention = @import("file_mention.zig");
    var buf: [chdir_argv_len][]const u8 = undefined;
    const argv = argvFor("/tmp/faku-dirty", &buf);
    try std.testing.expectEqualStrings(sh_bin, argv[0]);
    try std.testing.expectEqualStrings("-c", argv[1]);
    try std.testing.expectEqualStrings(main.fx_ask_chdir_script, argv[2]);
    try std.testing.expectEqualStrings("sh", argv[3]);
    try std.testing.expectEqualStrings("/tmp/faku-dirty", argv[4]);
    try std.testing.expectEqualStrings(git_bin, argv[5]);
    try std.testing.expectEqualStrings(git_status_cmd, argv[6]);
    try std.testing.expectEqualStrings(git_porcelain, argv[7]);
    try std.testing.expect(isGitDirtyArgv(argv));
    try std.testing.expect(!isGitDirtyArgv(&.{ git_bin, git_status_cmd, git_porcelain }));
    var branch_buf: [8][]const u8 = undefined;
    const branch = git_branch.argvFor("/tmp/faku-dirty", &branch_buf);
    try std.testing.expect(!isGitDirtyArgv(branch));
    try std.testing.expect(!git_branch.isGitBranchArgv(argv));
    var numstat_buf: [git_numstat.argv_len][]const u8 = undefined;
    const numstat = git_numstat.argvFor("/tmp/faku-dirty", &numstat_buf);
    try std.testing.expect(!isGitDirtyArgv(numstat));
    try std.testing.expect(!git_numstat.isGitNumstatArgv(argv));
    var ahead_buf: [git_ahead_behind.argv_len][]const u8 = undefined;
    const ahead = git_ahead_behind.argvFor("/tmp/faku-dirty", &ahead_buf);
    try std.testing.expect(!isGitDirtyArgv(ahead));
    try std.testing.expect(!git_ahead_behind.isGitAheadBehindArgv(argv));
    try std.testing.expect(!file_mention.isGitLsFilesArgv(argv));
    try std.testing.expect(git_dirty_key_first > git_branch.git_branch_key_first);
    try std.testing.expect(git_numstat.git_numstat_key_first > git_dirty_key_first);
    try std.testing.expect(git_ahead_behind.git_ahead_behind_key_first > git_numstat.git_numstat_key_first);
    try std.testing.expect(file_mention.file_mention_key_first > git_ahead_behind.git_ahead_behind_key_first);
}

test "countNonEmptyLines ignores blanks; dirtyLabel is change/changes" {
    try std.testing.expectEqual(@as(u32, 0), countNonEmptyLines(""));
    try std.testing.expectEqual(@as(u32, 0), countNonEmptyLines("   \n\n  \t"));
    try std.testing.expectEqual(@as(u32, 1), countNonEmptyLines(" M src/a.zig\n"));
    try std.testing.expectEqual(@as(u32, 1), countNonEmptyLines("?? new.txt"));
    try std.testing.expectEqual(@as(u32, 2), countNonEmptyLines(" M src/a.zig\n\n M src/b.zig\n"));
    try std.testing.expectEqual(@as(u32, 3), countNonEmptyLines("M  a\n M b\n?? c\n"));
    var buf: [max_git_dirty_label]u8 = undefined;
    try std.testing.expectEqualStrings("", dirtyLabel(0, &buf));
    try std.testing.expectEqualStrings("1 change", dirtyLabel(1, &buf));
    try std.testing.expectEqualStrings("3 changes", dirtyLabel(3, &buf));
    try std.testing.expectEqualStrings("2500 changes", dirtyLabel(2500, &buf));
    try std.testing.expectEqualStrings("4294967295 changes", dirtyLabel(std.math.maxInt(u32), &buf));
}

test "porcelainFlags is Waku XY: staged-only unstaged-only untracked mixed blanks" {
    const staged_only = porcelainFlags("M  src/a.zig\n");
    try std.testing.expect(staged_only.has_staged);
    try std.testing.expect(!staged_only.has_unstaged);

    const unstaged_only = porcelainFlags(" M src/a.zig\n");
    try std.testing.expect(!unstaged_only.has_staged);
    try std.testing.expect(unstaged_only.has_unstaged);

    const untracked = porcelainFlags("?? new.txt\n");
    try std.testing.expect(!untracked.has_staged);
    try std.testing.expect(untracked.has_unstaged);

    const both_on_one = porcelainFlags("MM src/a.zig\n");
    try std.testing.expect(both_on_one.has_staged);
    try std.testing.expect(both_on_one.has_unstaged);

    const mixed = porcelainFlags("M  a\n M b\n?? c\n");
    try std.testing.expect(mixed.has_staged);
    try std.testing.expect(mixed.has_unstaged);

    const blanks = porcelainFlags("");
    try std.testing.expect(!blanks.has_staged);
    try std.testing.expect(!blanks.has_unstaged);
    const whitespace = porcelainFlags("   \n\n  \t\n");
    try std.testing.expect(!whitespace.has_staged);
    try std.testing.expect(!whitespace.has_unstaged);
    const mixed_blanks = porcelainFlags("\nM  staged.zig\n\n?? extra.txt\n");
    try std.testing.expect(mixed_blanks.has_staged);
    try std.testing.expect(mixed_blanks.has_unstaged);

    const added = porcelainFlagsForLine("A  new.zig");
    try std.testing.expect(added.has_staged);
    try std.testing.expect(!added.has_unstaged);
    const deleted_worktree = porcelainFlagsForLine(" D gone.zig");
    try std.testing.expect(!deleted_worktree.has_staged);
    try std.testing.expect(deleted_worktree.has_unstaged);
    try std.testing.expect(!porcelainFlagsForLine("M").has_staged);
    try std.testing.expect(!porcelainFlagsForLine("").has_unstaged);
}
