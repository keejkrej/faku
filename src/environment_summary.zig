//! First-cut Waku Environment Summary chrome.
//!
//! Header info trigger plus a runtime-only dropdown titled
//! Environment: Commit or Push (ungated open of the existing
//! Commit… card), Compare (opens the right-panel Diff tab on
//! Uncommitted when no compare is active; Branch / Uncommitted /
//! Staged / Unstaged / Committed / LastTurn are switchable on the
//! Diff body), Copy task ID
//! (local session id via `fx.writeClipboard`), Copy agent CLI
//! thread ID when the selected session has a non-empty
//! `fx_session_id` / ACP sessionId (same `copyFxSessionId`
//! path as palette Copy provider session id; omitted when
//! empty), and a first-cut Background Stop row when
//! `is_streaming` (same composer Stop / `stopStream` path;
//! omitted when idle; Faku-side stream state only). Header +N −M
//! reuses the composer project-row numstat probe (omit a zero
//! side; muted ghost; click opens the right-panel Diff tab,
//! default Uncommitted).
//! First-cut per-file hunks live on the Diff-tab Review body (tracked
//! `git diff`; Uncommitted `?` rows one-shot
//! `git diff --no-index -- /dev/null <path>`). LastTurn
//! prefers turn-diff…end two-dot `diff..end` when both
//! finish-time (`worktree_turn_diff_sha` and
//! `worktree_turn_end_sha`) 40-hex exist; else start…end
//! when send-time (`worktree_snapshot_sha`) and finish-time
//! end exist; else send-time `git diff --name-status
//! <40-hex>` (isolated index, dangling commit named
//! `refs/faku/session-{id}-turn-start-{n}`, plus
//! `turn-{n-1}` when that baseline is missing; successful
//! finish also names a NEW snapshot `turn-{n}` and
//! `prepareTurnDiffBase` names `turn-diff-{n}`; Compare uses
//! stored shas, not the refs); rewind `<sha>...HEAD`
//! fallback; not `refs/waku/`; not HEAD~1. Leftovers:
//! prune-alone, fuller background registry / settled rows /
//! multi-kind Process·Monitor·Subagent, daemon
//! WorkspaceOperation. Not a Waku BackgroundWorkRegistry.
//! Not transcript checkpoint +/-. Not force push (Waku
//! `git_commit::push` has no `--force`).

const std = @import("std");
const main = @import("main.zig");
const git_commit = @import("git_commit.zig");
const git_numstat = @import("git_numstat.zig");
const review_diff = @import("review_diff.zig");
const right_panel = @import("right_panel.zig");
const copy_helpers = @import("copy.zig");
const session_switcher = @import("switcher.zig");
const turn_stream = @import("stream.zig");

const Model = main.Model;
const Effects = main.Effects;

/// Scratch for `headerGitNumstatLabel`. Native copies the slice
/// during the view bind; composer `git_numstat_label` stays the
/// both-sides `+N −M` string.
var header_numstat_buf: [git_numstat.max_git_numstat_label]u8 = undefined;

/// Waku header change counts: omit a zero side. Empty when both
/// are 0 (do not invent "clean"). Same `−` as the composer label.
pub fn headerNumstatLabel(additions: u64, deletions: u64, buf: *[git_numstat.max_git_numstat_label]u8) []const u8 {
    if (additions == 0 and deletions == 0) return "";
    if (deletions == 0) return std.fmt.bufPrint(buf, "+{d}", .{additions}) catch "";
    if (additions == 0) return std.fmt.bufPrint(buf, "−{d}", .{deletions}) catch "";
    return std.fmt.bufPrint(buf, "+{d} −{d}", .{ additions, deletions }) catch "";
}

/// Header +/- from the existing composer numstat counts. No new
/// spawn. Empty when `hasGitNumstat` is false.
pub fn headerGitNumstatLabel(model: *const Model) []const u8 {
    return headerNumstatLabel(model.git_numstat_additions, model.git_numstat_deletions, &header_numstat_buf);
}

pub fn close(model: *Model) void {
    model.environment_summary_open = false;
}

pub fn toggle(model: *Model) void {
    if (!model.environment_summary_open) {
        session_switcher.closeSwitcher(model);
        if (model.palette_open) model.closePalette();
        model.closeComposerPickers();
        model.closeSettingsEffortPicker();
    }
    model.environment_summary_open = !model.environment_summary_open;
}

/// Close the popover, then open the existing Commit… card without
/// `canCommitGit` so Push-only still works on a clean tree.
pub fn commitOrPush(model: *Model, fx: *Effects) void {
    close(model);
    git_commit.openCommitDialog(model, fx);
}

/// Close the popover, then copy the selected local session id the
/// same way as palette Copy session id.
pub fn copyTaskId(model: *Model, fx: *Effects) void {
    close(model);
    copy_helpers.copySessionId(model, fx);
}

/// Selected session has a non-empty `fx_session_id` / ACP
/// sessionId. Same presence as Waku `session.provider_native_id()`
/// Some — gates Copy agent CLI thread ID so an empty id does not
/// show a dead row that only sets status.
pub fn hasProviderSessionId(model: *const Model) bool {
    const session = model.sessionByIdConst(model.selected) orelse return false;
    return session.fxSessionId().len > 0;
}

/// Close the popover, then copy the selected `fx_session_id` the
/// same way as palette Copy provider session id.
pub fn copyAgentCliThreadId(model: *Model, fx: *Effects) void {
    close(model);
    copy_helpers.copyFxSessionId(model, fx);
}

/// Close the popover and any Commit… card, then open the right-panel
/// Diff tab. Uncommitted is the Diff-tab default when no compare is
/// active; an already-active source is kept and refreshed.
pub fn compare(model: *Model, fx: *Effects) void {
    close(model);
    git_commit.dropCommitNumstat(model, fx);
    git_commit.closeCommit(model);
    right_panel.selectDiff(model, fx);
}

/// Close the popover, then cancel the live turn the same way as
/// composer Stop (`stopStream`). Idle is a no-op: the Background
/// section is omitted, and this does not invent spawn/kill paths.
pub fn stopBackground(model: *Model, fx: *Effects) void {
    if (!model.is_streaming()) return;
    close(model);
    turn_stream.stopStream(model, fx);
}

test "headerNumstatLabel omits a zero side" {
    var buf: [git_numstat.max_git_numstat_label]u8 = undefined;
    try std.testing.expectEqualStrings("", headerNumstatLabel(0, 0, &buf));
    try std.testing.expectEqualStrings("+3 −1", headerNumstatLabel(3, 1, &buf));
    try std.testing.expectEqualStrings("+12", headerNumstatLabel(12, 0, &buf));
    try std.testing.expectEqualStrings("−4", headerNumstatLabel(0, 4, &buf));
    try std.testing.expectEqualStrings("+5", headerNumstatLabel(5, 0, &buf));
    const max_u64 = std.math.maxInt(u64);
    try std.testing.expectEqualStrings("+18446744073709551615", headerNumstatLabel(max_u64, 0, &buf));
    try std.testing.expectEqualStrings("−18446744073709551615", headerNumstatLabel(0, max_u64, &buf));
    try std.testing.expectEqualStrings("+18446744073709551615 −18446744073709551615", headerNumstatLabel(max_u64, max_u64, &buf));
}

test "headerGitNumstatLabel reads composer numstat counts" {
    var model = Model{};
    try std.testing.expectEqualStrings("", headerGitNumstatLabel(&model));
    try std.testing.expectEqualStrings("", model.header_git_numstat_label());
    model.git_numstat_additions = 12;
    try std.testing.expectEqualStrings("+12", headerGitNumstatLabel(&model));
    try std.testing.expectEqualStrings("+12", model.header_git_numstat_label());
    model.git_numstat_deletions = 4;
    try std.testing.expectEqualStrings("+12 −4", headerGitNumstatLabel(&model));
    model.git_numstat_additions = 0;
    try std.testing.expectEqualStrings("−4", headerGitNumstatLabel(&model));
    try std.testing.expect(git_numstat.hasGitNumstat(&model));
}

test "toggle opens and closes the environment summary" {
    var model = Model{};
    try std.testing.expect(!model.environment_summary_open);
    toggle(&model);
    try std.testing.expect(model.environment_summary_open);
    toggle(&model);
    try std.testing.expect(!model.environment_summary_open);
}

test "commitOrPush opens the commit card without requiring dirty" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/env-commit", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("env commit", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);
    model.environment_summary_open = true;
    try std.testing.expect(!git_commit.canCommitGit(&model));

    commitOrPush(&model, &fx);
    try std.testing.expect(!model.environment_summary_open);
    try std.testing.expect(model.git_commit_active);
    try std.testing.expect(model.git_commit_include_unstaged);
    try std.testing.expect(!model.git_commit_amend);
    try std.testing.expect(model.git_commit_numstat_key != 0);
    try std.testing.expect(!git_commit.canCommitGit(&model));
}

test "commitOrPush no-ops when cwd is missing, streaming, or a git mutation is in flight" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    const id = model.addSession("env gate", .fx);
    model.selected = id;
    model.environment_summary_open = true;
    commitOrPush(&model, &fx);
    try std.testing.expect(!model.environment_summary_open);
    try std.testing.expect(!model.git_commit_active);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/env-commit-gate", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);
    model.store_io = std.testing.io;
    if (model.sessionById(id)) |session| session.setProjectPath(project);

    model.environment_summary_open = true;
    model.phase = .streaming;
    commitOrPush(&model, &fx);
    try std.testing.expect(!model.git_commit_active);
    model.phase = .idle;

    model.environment_summary_open = true;
    model.git_push_key = @import("git_checkout.zig").git_push_key_first;
    commitOrPush(&model, &fx);
    try std.testing.expect(!model.git_commit_active);
    try std.testing.expect(@import("git_checkout.zig").gitMutationInFlight(&model));
}

test "compare closes Environment Summary and opens the Review card" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/env-compare", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("env compare", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);
    model.environment_summary_open = true;
    model.git_commit_active = true;

    compare(&model, &fx);
    try std.testing.expect(!model.environment_summary_open);
    try std.testing.expect(!model.git_commit_active);
    try std.testing.expect(model.review_diff_active);
    try std.testing.expect(model.right_panel_open);
    try std.testing.expectEqual(right_panel.Tab.diff, model.right_panel_tab);
    try std.testing.expectEqual(review_diff.Source.uncommitted, model.review_diff_source);
    try std.testing.expect(model.review_diff_key >= review_diff.review_diff_key_first);
    try std.testing.expectEqualStrings(review_diff.comparing_status, review_diff.reviewDiffStatus(&model));
}

test "compare opens Review when Environment Summary is already closed" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/env-compare-header", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("env compare header", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);
    try std.testing.expect(!model.environment_summary_open);

    compare(&model, &fx);
    try std.testing.expect(!model.environment_summary_open);
    try std.testing.expect(model.review_diff_active);
    try std.testing.expect(model.right_panel_open);
    try std.testing.expectEqual(right_panel.Tab.diff, model.right_panel_tab);
    try std.testing.expectEqual(review_diff.Source.uncommitted, model.review_diff_source);
    try std.testing.expect(model.review_diff_key >= review_diff.review_diff_key_first);
    try std.testing.expectEqualStrings(review_diff.comparing_status, review_diff.reviewDiffStatus(&model));
}

test "compare no-ops the Review card when streaming or a git mutation is in flight" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/env-compare-gate", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("env compare gate", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);

    model.environment_summary_open = true;
    model.phase = .streaming;
    compare(&model, &fx);
    try std.testing.expect(!model.environment_summary_open);
    try std.testing.expect(!model.review_diff_active);
    try std.testing.expect(model.right_panel_open);
    try std.testing.expectEqual(right_panel.Tab.diff, model.right_panel_tab);
    model.phase = .idle;

    model.environment_summary_open = true;
    model.git_push_key = @import("git_checkout.zig").git_push_key_first;
    compare(&model, &fx);
    try std.testing.expect(!model.review_diff_active);
    try std.testing.expect(model.right_panel_open);
    try std.testing.expectEqual(right_panel.Tab.diff, model.right_panel_tab);
}

test "copyTaskId writes the local session id and no-ops without a selection" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    const id = model.addSession("env copy", .fx);
    model.selected = id;
    model.environment_summary_open = true;
    copyTaskId(&model, &fx);
    try std.testing.expect(!model.environment_summary_open);
    try std.testing.expectEqual(@as(usize, 1), fx.pendingClipboardCount());
    const first = fx.pendingClipboardAt(0).?;
    try std.testing.expectEqual(main.copy_turn_key, first.key);
    try std.testing.expectEqual(@import("native_sdk").EffectClipboardOp.write, first.op);
    var id_buf: [16]u8 = undefined;
    const expected = try std.fmt.bufPrint(&id_buf, "{d}", .{id});
    try std.testing.expectEqualStrings(expected, first.text);

    var empty_fx = Effects.init(std.testing.allocator);
    defer empty_fx.deinit();
    empty_fx.executor = .fake;
    model.selected = 0;
    model.environment_summary_open = true;
    copyTaskId(&model, &empty_fx);
    try std.testing.expect(!model.environment_summary_open);
    try std.testing.expectEqual(@as(usize, 0), empty_fx.pendingClipboardCount());
}

test "copyAgentCliThreadId writes fx_session_id; empty and no selection match copyFxSessionId" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    const id = model.addSession("env copy thread", .fx);
    model.selected = id;
    try std.testing.expect(!hasProviderSessionId(&model));
    try std.testing.expect(!model.has_provider_session_id());
    if (model.sessionById(id)) |session| session.setFxSessionId("fx-sess-env");
    try std.testing.expect(hasProviderSessionId(&model));
    try std.testing.expect(model.has_provider_session_id());
    model.environment_summary_open = true;
    copyAgentCliThreadId(&model, &fx);
    try std.testing.expect(!model.environment_summary_open);
    try std.testing.expectEqual(@as(usize, 1), fx.pendingClipboardCount());
    const first = fx.pendingClipboardAt(0).?;
    try std.testing.expectEqual(main.copy_turn_key, first.key);
    try std.testing.expectEqual(@import("native_sdk").EffectClipboardOp.write, first.op);
    try std.testing.expectEqualStrings("fx-sess-env", first.text);

    if (model.sessionById(id)) |session| session.setFxSessionId("");
    try std.testing.expect(!hasProviderSessionId(&model));
    try std.testing.expect(!model.has_provider_session_id());
    var empty_fx = Effects.init(std.testing.allocator);
    defer empty_fx.deinit();
    empty_fx.executor = .fake;
    model.environment_summary_open = true;
    copyAgentCliThreadId(&model, &empty_fx);
    try std.testing.expect(!model.environment_summary_open);
    try std.testing.expectEqual(@as(usize, 0), empty_fx.pendingClipboardCount());
    try std.testing.expectEqualStrings(copy_helpers.no_provider_session_id_status, model.window_status());

    var none_fx = Effects.init(std.testing.allocator);
    defer none_fx.deinit();
    none_fx.executor = .fake;
    model.selected = 0;
    model.clearWindowStatus();
    try std.testing.expect(!hasProviderSessionId(&model));
    try std.testing.expect(!model.has_provider_session_id());
    model.environment_summary_open = true;
    copyAgentCliThreadId(&model, &none_fx);
    try std.testing.expect(!model.environment_summary_open);
    try std.testing.expectEqual(@as(usize, 0), none_fx.pendingClipboardCount());
    try std.testing.expectEqual(@as(usize, 0), model.window_status().len);
}

test "Esc, session switch, and palette close the environment summary" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    const first = model.addSession("env first", .fx);
    const second = model.addSession("env second", .fx);
    model.selected = first;
    model.environment_summary_open = true;
    main.update(&model, .stop, &fx);
    try std.testing.expect(!model.environment_summary_open);

    model.environment_summary_open = true;
    main.update(&model, .{ .select = second }, &fx);
    try std.testing.expect(!model.environment_summary_open);
    try std.testing.expectEqual(second, model.selected);

    model.environment_summary_open = true;
    main.update(&model, .start_search, &fx);
    try std.testing.expect(model.palette_open);
    try std.testing.expect(!model.environment_summary_open);
}

test "composer startCommit still requires canCommitGit" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/env-composer-commit", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("env composer commit", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);
    try std.testing.expect(!git_commit.canCommitGit(&model));

    main.update(&model, .start_git_commit, &fx);
    try std.testing.expect(!model.git_commit_active);

    main.update(&model, .environment_commit_or_push, &fx);
    try std.testing.expect(model.git_commit_active);
    try std.testing.expect(!git_commit.canCommitGit(&model));

    main.update(&model, .environment_compare, &fx);
    try std.testing.expect(!model.git_commit_active);
    try std.testing.expect(model.review_diff_active);
    try std.testing.expect(model.right_panel_open);
    try std.testing.expectEqual(right_panel.Tab.diff, model.right_panel_tab);
    try std.testing.expectEqual(review_diff.Source.uncommitted, model.review_diff_source);
}

test "stopBackground no-ops when not streaming" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    const id = model.addSession("env stop idle", .fx);
    model.selected = id;
    model.environment_summary_open = true;
    try std.testing.expect(!model.is_streaming());

    stopBackground(&model, &fx);
    try std.testing.expect(model.environment_summary_open);
    try std.testing.expect(!model.is_streaming());
    try std.testing.expectEqual(@as(u32, 0), model.streaming_session);
    try std.testing.expectEqual(main.Phase.idle, model.phase);
    try std.testing.expectEqual(@as(usize, 0), fx.pendingTimerCount());

    main.update(&model, .environment_stop_background, &fx);
    try std.testing.expect(model.environment_summary_open);
    try std.testing.expect(!model.is_streaming());
}

test "stopBackground closes summary and stops via stopStream" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    const id = model.addSession("env stop live", .fx);
    model.selected = id;
    model.environment_summary_open = true;
    model.phase = .streaming;
    model.streaming_session = id;
    if (model.sessionById(id)) |session| session.busy = true;

    stopBackground(&model, &fx);
    try std.testing.expect(!model.environment_summary_open);
    try std.testing.expect(!model.is_streaming());
    try std.testing.expectEqual(main.Phase.idle, model.phase);
    try std.testing.expectEqual(@as(u32, 0), model.streaming_session);
    try std.testing.expect(!model.sessionById(id).?.busy);
    try std.testing.expectEqual(@as(usize, 0), fx.pendingTimerCount());
}

test "environment_stop_background uses the same stopStream path as Stop" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    const id = model.addSession("env stop send", .fx);
    model.selected = id;
    main.update(&model, .{ .draft_edit = .{ .insert_text = "go" } }, &fx);
    main.update(&model, .send, &fx);
    try std.testing.expect(model.is_streaming());
    try std.testing.expect(model.sessionById(id).?.busy);
    try std.testing.expectEqual(@as(usize, 1), fx.pendingTimerCount());
    try std.testing.expectEqual(main.stream_timer_key, fx.pendingTimerAt(0).?.key);
    model.environment_summary_open = true;

    main.update(&model, .environment_stop_background, &fx);
    try std.testing.expect(!model.environment_summary_open);
    try std.testing.expect(!model.is_streaming());
    try std.testing.expect(!model.sessionById(id).?.busy);
    try std.testing.expectEqual(@as(u32, 0), model.streaming_session);
    try std.testing.expectEqual(@as(usize, 0), fx.pendingTimerCount());
}
