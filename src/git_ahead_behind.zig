//! One-shot ahead/behind vs `@{upstream}` for the composer project row.
//!
//! Native has no git/workspace effect. When the selected session has a
//! non-empty `project_path` that exists, Faku `fx.spawn`s
//! `git rev-list --left-right --count @{upstream}...HEAD` through the
//! same `/bin/sh -c` chdir workaround `fx ask` uses
//! (`fx_ask_chdir_script`). `@{upstream}...HEAD` is its own argv slot
//! — never interpolated into the `-c` script (same pattern as Push
//! `@{upstream}`). The first stdout line is `behind\tahead` (or
//! space-separated). Left count = behind upstream; right count =
//! ahead of upstream. Either side > 0 paints a muted `↑A ↓B` (omit a
//! side when that count is 0). Both-zero / failed / empty / no
//! upstream omits the label — this cut does not invent "synced" or
//! "0 ahead". A separate ready / has-upstream bit (not the label)
//! plus a remotes probe (480+) gates composer Push… the way Waku
//! `can_push` does: ahead > 0, or no upstream and at least one
//! remote (first-push `--set-upstream` path). In-flight and
//! never-finished stay hidden so the row does not flash. Failed /
//! empty remotes on the no-upstream path hide Push…. Not a live
//! watch, not a base-ref picker, not Waku's daemon
//! `InspectBranches`, and not Environment Summary.
//!
//! Spawn/line/exit orchestration lives here. Windows is skipped
//! (app.zon is macos/linux; no Windows spawn path).

const std = @import("std");
const builtin = @import("builtin");
const native_sdk = @import("native_sdk");
const main = @import("main.zig");
const git_remotes = @import("git_remotes.zig");

const Model = main.Model;
const Effects = main.Effects;
const writeFixed = main.writeFixed;

/// One-shot `git rev-list --left-right --count @{upstream}...HEAD`
/// probe. Distinct from git_branch (200+), git_dirty (300+),
/// git_numstat (350+), git_push (360+), git_worktree_add (370+),
/// maximize / pick-image / fx-ask / daemon / clipboard / probe keys,
/// and from file_mention (400+). Band is 380+ (between worktree-add
/// 370+ and worktree-base 390+). Incremented per refresh so a
/// cancelled spawn cannot paint a later session.
pub const git_ahead_behind_key_first: u64 = 380;

/// `↑18446744073709551615 ↓18446744073709551615` is 47 bytes.
pub const max_git_ahead_behind_label: usize = 48;

pub const git_bin = "git";
pub const git_rev_list_cmd = "rev-list";
pub const git_left_right = "--left-right";
pub const git_count = "--count";
/// Symmetric range vs the tracked upstream. Own argv slot, matching
/// Push `@{upstream}` (`git_checkout.upstreamArgvFor`).
pub const git_upstream_range = "@{upstream}...HEAD";
pub const sh_bin = "/bin/sh";

pub const argv_len: usize = 10;

pub const AheadBehind = struct {
    behind: u64 = 0,
    ahead: u64 = 0,
};

pub fn argvFor(cwd: []const u8, buf: *[argv_len][]const u8) []const []const u8 {
    buf.* = .{
        sh_bin,
        "-c",
        main.fx_ask_chdir_script,
        "sh",
        cwd,
        git_bin,
        git_rev_list_cmd,
        git_left_right,
        git_count,
        git_upstream_range,
    };
    return buf;
}

pub fn isGitAheadBehindArgv(argv: []const []const u8) bool {
    if (argv.len != argv_len) return false;
    if (!std.mem.eql(u8, argv[0], sh_bin)) return false;
    if (!std.mem.eql(u8, argv[1], "-c")) return false;
    if (!std.mem.eql(u8, argv[2], main.fx_ask_chdir_script)) return false;
    if (!std.mem.eql(u8, argv[5], git_bin)) return false;
    if (!std.mem.eql(u8, argv[6], git_rev_list_cmd)) return false;
    if (!std.mem.eql(u8, argv[7], git_left_right)) return false;
    if (!std.mem.eql(u8, argv[8], git_count)) return false;
    return std.mem.eql(u8, argv[9], git_upstream_range);
}

/// First stdout line, trimmed. Empty / whitespace is not a count.
pub fn firstStdoutLine(raw: []const u8) []const u8 {
    const trimmed = std.mem.trim(u8, raw, " \t\r\n");
    if (trimmed.len == 0) return "";
    const end = std.mem.indexOfAny(u8, trimmed, "\r\n") orelse trimmed.len;
    return std.mem.trim(u8, trimmed[0..end], " \t");
}

fn splitCountPair(line: []const u8) ?struct { left: []const u8, right: []const u8 } {
    if (std.mem.indexOfScalar(u8, line, '\t')) |tab| {
        return .{ .left = line[0..tab], .right = line[tab + 1 ..] };
    }
    if (std.mem.indexOfScalar(u8, line, ' ')) |sp| {
        return .{ .left = line[0..sp], .right = line[sp + 1 ..] };
    }
    return null;
}

/// First `behind\tahead` (or space-separated) pair. Non-numeric /
/// empty / one-field lines are omitted.
pub fn parseAheadBehindLine(raw: []const u8) ?AheadBehind {
    const line = firstStdoutLine(raw);
    if (line.len == 0) return null;
    const parts = splitCountPair(line) orelse return null;
    const left = std.mem.trim(u8, parts.left, " \t");
    const right = std.mem.trim(u8, parts.right, " \t");
    if (std.mem.indexOfAny(u8, right, " \t") != null) return null;
    const behind = std.fmt.parseInt(u64, left, 10) catch return null;
    const ahead = std.fmt.parseInt(u64, right, 10) catch return null;
    return .{ .behind = behind, .ahead = ahead };
}

/// `↑A`, `↓B`, or `↑A ↓B`. Empty when both counts are 0 (do not
/// invent "synced" / "0 ahead"). Exact numbers even when huge.
pub fn aheadBehindLabel(ahead: u64, behind: u64, buf: *[max_git_ahead_behind_label]u8) []const u8 {
    if (ahead == 0 and behind == 0) return "";
    if (ahead > 0 and behind > 0) {
        return std.fmt.bufPrint(buf, "↑{d} ↓{d}", .{ ahead, behind }) catch "";
    }
    if (ahead > 0) {
        return std.fmt.bufPrint(buf, "↑{d}", .{ahead}) catch "";
    }
    return std.fmt.bufPrint(buf, "↓{d}", .{behind}) catch "";
}

pub fn gitAheadBehindLabel(model: *const Model) []const u8 {
    return model.git_ahead_behind_label_storage[0..model.git_ahead_behind_label_len];
}

pub fn hasGitAheadBehind(model: *const Model) bool {
    return model.git_ahead_behind_ahead > 0 or model.git_ahead_behind_behind > 0;
}

/// Waku `can_push` with remotes-required-for-first-push: hide while
/// the ahead/behind spawn is in flight or has never finished; show
/// when ahead > 0, or when `@{upstream}` did not resolve and a
/// remotes probe found at least one remote. Hide while remotes are
/// in-flight on the no-upstream path (no flash). Failed / empty
/// remotes stay hidden. Synced and behind-only (resolved + ahead 0)
/// stay hidden.
pub fn canPushGitBranch(model: *const Model) bool {
    if (model.git_ahead_behind_key != 0) return false;
    if (!model.git_ahead_behind_ready) return false;
    if (model.git_ahead_behind_has_upstream) return model.git_ahead_behind_ahead > 0;
    return git_remotes.remotesReadyForFirstPush(model);
}

pub fn clearGitAheadBehind(model: *Model) void {
    setAheadBehind(model, 0, 0);
    model.git_ahead_behind_has_upstream = false;
    model.git_ahead_behind_ready = false;
}

fn setAheadBehind(model: *Model, ahead: u64, behind: u64) void {
    model.git_ahead_behind_ahead = ahead;
    model.git_ahead_behind_behind = behind;
    if (ahead == 0 and behind == 0) {
        model.git_ahead_behind_label_len = 0;
        return;
    }
    const written = aheadBehindLabel(ahead, behind, &model.git_ahead_behind_label_storage);
    model.git_ahead_behind_label_len = written.len;
}

fn cancelInFlight(model: *Model, fx: *Effects) void {
    if (model.git_ahead_behind_key == 0) return;
    fx.cancel(model.git_ahead_behind_key);
    model.git_ahead_behind_key = 0;
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
    clearGitAheadBehind(model);
    if (builtin.os.tag == .windows) return;
    const cwd = probePath(model);
    if (cwd.len == 0) return;

    const key = model.next_git_ahead_behind_key;
    model.next_git_ahead_behind_key = key + 1;
    model.git_ahead_behind_key = key;
    model.git_ahead_behind_probe_session = model.selected;
    writeFixed(&model.git_ahead_behind_probe_path_storage, &model.git_ahead_behind_probe_path_len, cwd);

    var argv_buf: [argv_len][]const u8 = undefined;
    fx.spawn(.{
        .key = key,
        .argv = argvFor(cwd, &argv_buf),
        .on_line = Effects.lineMsg(.fx_line),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
}

fn probeStillCurrent(model: *const Model) bool {
    if (model.git_ahead_behind_key == 0) return false;
    if (model.git_ahead_behind_probe_session != model.selected) return false;
    const path = model.selectedProjectPath();
    const probed = model.git_ahead_behind_probe_path_storage[0..model.git_ahead_behind_probe_path_len];
    return std.mem.eql(u8, path, probed);
}

pub fn applyLine(model: *Model, line: native_sdk.EffectLine) void {
    if (line.key != model.git_ahead_behind_key or model.git_ahead_behind_key == 0) return;
    if (!probeStillCurrent(model)) return;
    const parsed = parseAheadBehindLine(line.line) orelse return;
    setAheadBehind(model, parsed.ahead, parsed.behind);
    model.git_ahead_behind_has_upstream = true;
}

pub fn handleExit(model: *Model, exit: native_sdk.EffectExit) void {
    if (exit.key != model.git_ahead_behind_key or model.git_ahead_behind_key == 0) return;
    const current = probeStillCurrent(model);
    model.git_ahead_behind_key = 0;
    if (!current or exit.reason != .exited) {
        clearGitAheadBehind(model);
        return;
    }
    if (exit.code != 0) {
        setAheadBehind(model, 0, 0);
        model.git_ahead_behind_has_upstream = false;
        model.git_ahead_behind_ready = true;
        return;
    }
    model.git_ahead_behind_ready = true;
    model.git_ahead_behind_has_upstream = true;
}

test "argv is chdir script plus git rev-list --left-right --count @{upstream}...HEAD" {
    const git_branch = @import("git_branch.zig");
    const git_checkout = @import("git_checkout.zig");
    const git_dirty = @import("git_dirty.zig");
    const git_numstat = @import("git_numstat.zig");
    const file_mention = @import("file_mention.zig");
    var buf: [argv_len][]const u8 = undefined;
    const argv = argvFor("/tmp/faku-ahead", &buf);
    try std.testing.expectEqual(@as(usize, 10), argv.len);
    try std.testing.expectEqualStrings(sh_bin, argv[0]);
    try std.testing.expectEqualStrings("-c", argv[1]);
    try std.testing.expectEqualStrings(main.fx_ask_chdir_script, argv[2]);
    try std.testing.expectEqualStrings("sh", argv[3]);
    try std.testing.expectEqualStrings("/tmp/faku-ahead", argv[4]);
    try std.testing.expectEqualStrings(git_bin, argv[5]);
    try std.testing.expectEqualStrings(git_rev_list_cmd, argv[6]);
    try std.testing.expectEqualStrings(git_left_right, argv[7]);
    try std.testing.expectEqualStrings(git_count, argv[8]);
    try std.testing.expectEqualStrings(git_upstream_range, argv[9]);
    try std.testing.expectEqualStrings("@{upstream}...HEAD", argv[9]);
    try std.testing.expect(isGitAheadBehindArgv(argv));
    try std.testing.expect(std.mem.indexOf(u8, argv[2], git_upstream_range) == null);
    try std.testing.expect(std.mem.indexOf(u8, argv[2], git_rev_list_cmd) == null);
    try std.testing.expect(!isGitAheadBehindArgv(&.{ git_bin, git_rev_list_cmd, git_left_right, git_count, git_upstream_range }));
    var upstream_buf: [10][]const u8 = undefined;
    const upstream = git_checkout.upstreamArgvFor("/tmp/faku-ahead", &upstream_buf);
    try std.testing.expect(!isGitAheadBehindArgv(upstream));
    try std.testing.expect(!git_checkout.isGitUpstreamArgv(argv));
    var branch_buf: [8][]const u8 = undefined;
    const branch = git_branch.argvFor("/tmp/faku-ahead", &branch_buf);
    try std.testing.expect(!isGitAheadBehindArgv(branch));
    try std.testing.expect(!git_branch.isGitBranchArgv(argv));
    var dirty_buf: [8][]const u8 = undefined;
    const dirty = git_dirty.argvFor("/tmp/faku-ahead", &dirty_buf);
    try std.testing.expect(!isGitAheadBehindArgv(dirty));
    try std.testing.expect(!git_dirty.isGitDirtyArgv(argv));
    var numstat_buf: [git_numstat.argv_len][]const u8 = undefined;
    const numstat = git_numstat.argvFor("/tmp/faku-ahead", &numstat_buf);
    try std.testing.expect(!isGitAheadBehindArgv(numstat));
    try std.testing.expect(!git_numstat.isGitNumstatArgv(argv));
    try std.testing.expect(!file_mention.isGitLsFilesArgv(argv));
    try std.testing.expect(git_ahead_behind_key_first > git_checkout.git_worktree_add_key_first);
    try std.testing.expect(git_checkout.git_worktree_base_key_first > git_ahead_behind_key_first);
    try std.testing.expect(file_mention.file_mention_key_first > git_checkout.git_worktree_base_key_first);
    try std.testing.expect(git_ahead_behind_key_first > git_checkout.git_push_key_first);
}

test "parseAheadBehindLine is behind then ahead; label omits a zero side" {
    try std.testing.expectEqual(AheadBehind{ .behind = 3, .ahead = 2 }, parseAheadBehindLine("3\t2\n").?);
    try std.testing.expectEqual(AheadBehind{ .behind = 0, .ahead = 2 }, parseAheadBehindLine("0\t2").?);
    try std.testing.expectEqual(AheadBehind{ .behind = 3, .ahead = 0 }, parseAheadBehindLine("3 0\n").?);
    try std.testing.expectEqual(AheadBehind{ .behind = 1, .ahead = 4 }, parseAheadBehindLine("  1 4 \nextra\n").?);
    try std.testing.expectEqual(AheadBehind{ .behind = 0, .ahead = 0 }, parseAheadBehindLine("0\t0\n").?);
    try std.testing.expect(parseAheadBehindLine("") == null);
    try std.testing.expect(parseAheadBehindLine("   \n") == null);
    try std.testing.expect(parseAheadBehindLine("not-counts") == null);
    try std.testing.expect(parseAheadBehindLine("3\n") == null);
    try std.testing.expect(parseAheadBehindLine("3\tabc\n") == null);
    try std.testing.expect(parseAheadBehindLine("abc\t2\n") == null);
    var buf: [max_git_ahead_behind_label]u8 = undefined;
    try std.testing.expectEqualStrings("", aheadBehindLabel(0, 0, &buf));
    try std.testing.expectEqualStrings("↑2", aheadBehindLabel(2, 0, &buf));
    try std.testing.expectEqualStrings("↓3", aheadBehindLabel(0, 3, &buf));
    try std.testing.expectEqualStrings("↑2 ↓1", aheadBehindLabel(2, 1, &buf));
    const max_u64 = std.math.maxInt(u64);
    try std.testing.expectEqualStrings("↑18446744073709551615 ↓18446744073709551615", aheadBehindLabel(max_u64, max_u64, &buf));
}

test "canPushGitBranch is ahead>0 or no-upstream with remotes; hides in-flight" {
    const git_remotes = @import("git_remotes.zig");
    var model = Model{};
    try std.testing.expect(!canPushGitBranch(&model));

    model.git_ahead_behind_key = git_ahead_behind_key_first;
    try std.testing.expect(!canPushGitBranch(&model));

    model.git_ahead_behind_key = 0;
    model.git_ahead_behind_ready = true;
    model.git_ahead_behind_has_upstream = true;
    model.git_ahead_behind_ahead = 2;
    try std.testing.expect(canPushGitBranch(&model));

    model.git_ahead_behind_ahead = 0;
    try std.testing.expect(!canPushGitBranch(&model));

    model.git_ahead_behind_behind = 3;
    try std.testing.expect(!canPushGitBranch(&model));

    model.git_ahead_behind_has_upstream = false;
    try std.testing.expect(!canPushGitBranch(&model));

    model.git_remotes_ready = true;
    try std.testing.expect(!canPushGitBranch(&model));

    model.git_has_remote = true;
    try std.testing.expect(canPushGitBranch(&model));

    model.git_remotes_key = git_remotes.git_remotes_key_first;
    try std.testing.expect(!canPushGitBranch(&model));

    model.git_remotes_key = 0;
    model.git_ahead_behind_has_upstream = true;
    model.git_ahead_behind_ahead = 2;
    model.git_has_remote = false;
    try std.testing.expect(canPushGitBranch(&model));

    model.git_ahead_behind_ready = false;
    try std.testing.expect(!canPushGitBranch(&model));

    model.git_ahead_behind_ready = true;
    model.git_ahead_behind_has_upstream = false;
    model.git_has_remote = true;
    model.git_ahead_behind_key = git_ahead_behind_key_first + 1;
    try std.testing.expect(!canPushGitBranch(&model));
}
