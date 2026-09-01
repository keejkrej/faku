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
//! empty), and a first-cut Background section with Process /
//! Monitor / Subagent kind chrome. Visible rows come from a
//! runtime-only multi-row registry (cap 8) rendered via Native
//! `background_rows`. This cut populates Process from
//! window-side stream/settle: a live "Agent turn" row plus
//! Stop agent while `is_streaming` (same composer Stop /
//! `stopStream` path), and one last-turn settle when idle
//! (Completed on successful `finishStream` drain with no
//! queued restart, Stopped on `stopStream`, Failed on
//! drain=false paths that already end the stream; cap 1,
//! overwrite). Live Monitor rows come from real Claude
//! stream-json `tool_use` / `content_block` whose `name` is
//! `Monitor` (code.claude.com/docs/en/tools-reference; first-cut
//! title is the stable `Monitor` label). Live Subagent rows
//! come from real Claude stream-json `parent_tool_use_id` /
//! Agent `tool_use` signals. Both are runtime-only while
//! streaming (cleared when the turn settles or the stream
//! ends; not sessions.json). Visible fill is Process, then
//! live Monitor, then live Subagent, stopping at the cap.
//! Idle settle stays Process-only. Settled is keyed by
//! session id so switching hides another session's row
//! without clearing it; a new settle overwrites; remove
//! session clears that row. Not persisted to sessions.json /
//! drafts.json. Header info trigger uses button `selected`
//! while the dropdown is open or this section would show.
//! Header +N −M reuses the composer project-row numstat probe
//! (omit a zero side; muted ghost; click opens the right-panel
//! Diff tab, default Uncommitted).
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
//! prune-alone, Monitor output log, daemon
//! `refreshBackgroundWork` / WorkspaceOperation, right-panel
//! BackgroundWork tab. Kind chrome, Process registry, first-cut
//! live Monitor rows from Claude `Monitor` tool_use, and
//! first-cut live Subagent rows from Claude `parent_tool_use_id`
//! ship; not a Waku BackgroundWorkRegistry.
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

/// Cap-1 last-turn Background settle. Runtime-only.
pub const SettledStatus = enum { none, completed, stopped, failed };

/// Background kind chrome. Stable labels match Waku's Process ·
/// Monitor · Subagent grouping. This cut fills Process, live
/// Monitor from Claude `Monitor` tool_use, and live Subagent
/// from Claude `parent_tool_use_id` / Agent `tool_use`.
pub const BackgroundKind = enum {
    process,
    monitor,
    subagent,
};

pub const kind_process_label = "Process";
pub const kind_monitor_label = "Monitor";
pub const kind_subagent_label = "Subagent";

/// Bounded visible registry. Process takes one slot; remaining
/// slots are live Monitor then live Subagent rows.
pub const max_background_rows: usize = 8;

/// Stable Native `for` key for the Process row (live or settled).
pub const process_row_id: u32 = 1;

/// First Native `for` key for live Subagent rows (`id` 2…).
pub const subagent_row_id_first: u32 = 2;

/// First Native `for` key for live Monitor rows. Offset from
/// `process_row_id` (1) and `subagent_row_id_first` (2…) so
/// `for` keys never collide when Process + Monitor + Subagent
/// share the visible cap.
pub const monitor_row_id_first: u32 = 100;

/// Live Monitor / Subagent caps: leave one slot for Process.
/// Visible fill still stops at `max_background_rows`.
pub const max_live_monitors: usize = max_background_rows - 1;
pub const max_live_subagents: usize = max_background_rows - 1;

/// `parent_tool_use_id` / Agent `tool_use` id, and Monitor
/// `tool_use` id. Same cap as ACP tool-call ids (documented
/// Claude ids are `toolu_…`).
pub const max_subagent_id: usize = 128;
pub const max_monitor_id: usize = max_subagent_id;

/// Subagent / Monitor row titles. First-cut stable labels.
pub const max_subagent_title: usize = 32;
pub const max_monitor_title: usize = max_subagent_title;

/// Runtime-only live Subagent slot. Keyed by
/// `parent_tool_use_id` / Agent `tool_use` id. Not persisted.
pub const LiveSubagent = struct {
    id_storage: [max_subagent_id]u8 = [_]u8{0} ** max_subagent_id,
    id_len: usize = 0,
    title_storage: [max_subagent_title]u8 = [_]u8{0} ** max_subagent_title,
    title_len: usize = 0,

    pub fn parentId(self: *const LiveSubagent) []const u8 {
        return self.id_storage[0..self.id_len];
    }

    pub fn title(self: *const LiveSubagent) []const u8 {
        if (self.title_len == 0) return kind_subagent_label;
        return self.title_storage[0..self.title_len];
    }
};

/// Runtime-only live Monitor slot. Keyed by Claude `Monitor`
/// `tool_use` id. Not persisted. First-cut title is the stable
/// `Monitor` label (no undocumented input scrape).
pub const LiveMonitor = struct {
    id_storage: [max_monitor_id]u8 = [_]u8{0} ** max_monitor_id,
    id_len: usize = 0,
    title_storage: [max_monitor_title]u8 = [_]u8{0} ** max_monitor_title,
    title_len: usize = 0,

    pub fn toolUseId(self: *const LiveMonitor) []const u8 {
        return self.id_storage[0..self.id_len];
    }

    pub fn title(self: *const LiveMonitor) []const u8 {
        if (self.title_len == 0) return kind_monitor_label;
        return self.title_storage[0..self.title_len];
    }
};

/// Process-kind row title. Honest about Faku-side stream state
/// (not an OS process watch).
pub const process_row_label = "Agent turn";
pub const settled_completed_label = "Completed";
pub const settled_stopped_label = "Stopped";
pub const settled_failed_label = "Failed";

/// Visible Background registry row. Native `background_rows`
/// iterates this. Not persisted to sessions.json / drafts.json.
pub const BackgroundRow = struct {
    id: u32,
    kind: BackgroundKind,
    kind_label: []const u8,
    title: []const u8,
    live: bool,
    can_stop: bool,
    has_status: bool,
    settled_status: []const u8,
};

pub fn backgroundKindLabel(kind: BackgroundKind) []const u8 {
    return switch (kind) {
        .process => kind_process_label,
        .monitor => kind_monitor_label,
        .subagent => kind_subagent_label,
    };
}

/// Record the single last-turn row. `session_id == 0` or `.none`
/// clears. A new settle overwrites (cap 1).
pub fn settle(model: *Model, session_id: u32, status: SettledStatus) void {
    if (session_id == 0 or status == .none) {
        clearSettled(model);
        return;
    }
    model.background_settled_session = session_id;
    model.background_settled = status;
}

pub fn clearSettled(model: *Model) void {
    model.background_settled_session = 0;
    model.background_settled = .none;
}

/// Drop the cap-1 row when that session is removed. Other
/// sessions keep their (overwritten) slot until a new settle.
pub fn clearSettledIfSession(model: *Model, session_id: u32) void {
    if (model.background_settled_session == session_id) clearSettled(model);
}

/// Drop live Subagent rows. Called when a turn starts, settles,
/// or is stopped. Runtime-only; nothing to persist.
pub fn clearLiveSubagents(model: *Model) void {
    model.background_subagent_count = 0;
}

/// Drop live Monitor rows. Same lifetime as Subagent.
pub fn clearLiveMonitors(model: *Model) void {
    model.background_monitor_count = 0;
}

/// Drop live Monitor and Subagent rows together.
pub fn clearLiveBackgroundSignals(model: *Model) void {
    clearLiveMonitors(model);
    clearLiveSubagents(model);
}

/// Register a live Subagent keyed by non-empty
/// `parent_tool_use_id` / Agent `tool_use` id. Duplicate ids are
/// a no-op. Cap `max_live_subagents` (Process keeps a slot).
/// Title is the stable `Subagent` label this cut.
pub fn noteLiveSubagent(model: *Model, parent_id: []const u8) void {
    if (parent_id.len == 0) return;
    var i: u32 = 0;
    while (i < model.background_subagent_count) : (i += 1) {
        if (std.mem.eql(u8, model.background_subagents[i].parentId(), parent_id)) return;
    }
    if (model.background_subagent_count >= max_live_subagents) return;
    const slot = &model.background_subagents[model.background_subagent_count];
    const writeFixed = main.writeFixed;
    writeFixed(&slot.id_storage, &slot.id_len, parent_id);
    writeFixed(&slot.title_storage, &slot.title_len, kind_subagent_label);
    model.background_subagent_count += 1;
}

/// Register a live Monitor keyed by non-empty Claude `Monitor`
/// `tool_use` id. Duplicate ids are a no-op. Cap
/// `max_live_monitors` (Process keeps a slot). Title is the
/// stable `Monitor` label this cut. Not Bash, Agent, or
/// `parent_tool_use_id`.
pub fn noteLiveMonitor(model: *Model, tool_use_id: []const u8) void {
    if (tool_use_id.len == 0) return;
    var i: u32 = 0;
    while (i < model.background_monitor_count) : (i += 1) {
        if (std.mem.eql(u8, model.background_monitors[i].toolUseId(), tool_use_id)) return;
    }
    if (model.background_monitor_count >= max_live_monitors) return;
    const slot = &model.background_monitors[model.background_monitor_count];
    const writeFixed = main.writeFixed;
    writeFixed(&slot.id_storage, &slot.id_len, tool_use_id);
    writeFixed(&slot.title_storage, &slot.title_len, kind_monitor_label);
    model.background_monitor_count += 1;
}

/// Live Subagent rows exist only while streaming. Idle settle is
/// Process-only this cut.
pub fn liveSubagentCount(model: *const Model) u32 {
    if (!model.is_streaming()) return 0;
    return @min(model.background_subagent_count, @as(u32, @intCast(max_live_subagents)));
}

/// Live Monitor rows exist only while streaming. Idle settle is
/// Process-only this cut.
pub fn liveMonitorCount(model: *const Model) u32 {
    if (!model.is_streaming()) return 0;
    return @min(model.background_monitor_count, @as(u32, @intCast(max_live_monitors)));
}

/// Visible settled row for the selected session. Hidden while
/// `is_streaming` so a queued restart stays on the Process row
/// instead of flashing Completed.
pub fn hasSettledBackground(model: *const Model) bool {
    if (model.is_streaming()) return false;
    if (model.background_settled == .none) return false;
    if (model.background_settled_session == 0) return false;
    if (model.background_settled_session != model.selected) return false;
    return model.sessionByIdConst(model.background_settled_session) != null;
}

/// Background section: live Process row and/or the selected
/// session's settled last-turn row.
pub fn hasBackgroundSection(model: *const Model) bool {
    return model.is_streaming() or hasSettledBackground(model);
}

pub fn settledStatusLabel(model: *const Model) []const u8 {
    if (!hasSettledBackground(model)) return "";
    return switch (model.background_settled) {
        .none => "",
        .completed => settled_completed_label,
        .stopped => settled_stopped_label,
        .failed => settled_failed_label,
    };
}

/// Project the runtime registry into `out` (cap `max_background_rows`).
/// Streaming wins so a queued `finishStream` restart stays on the
/// live Process row instead of flashing Completed. Live Monitor
/// rows follow Process from Claude `Monitor` `tool_use`. Live
/// Subagent rows follow those from `parent_tool_use_id` / Agent
/// `tool_use`. Fill stops at the cap.
pub fn fillBackgroundRows(model: *const Model, out: *[max_background_rows]BackgroundRow) []const BackgroundRow {
    if (!hasBackgroundSection(model)) return out[0..0];
    const live = model.is_streaming();
    const status = if (live) "" else settledStatusLabel(model);
    out[0] = .{
        .id = process_row_id,
        .kind = .process,
        .kind_label = backgroundKindLabel(.process),
        .title = process_row_label,
        .live = live,
        .can_stop = live,
        .has_status = status.len > 0,
        .settled_status = status,
    };
    var n: usize = 1;
    const mon_n = liveMonitorCount(model);
    var mi: u32 = 0;
    while (mi < mon_n and n < max_background_rows) : (mi += 1) {
        const slot = &model.background_monitors[mi];
        out[n] = .{
            .id = monitor_row_id_first + mi,
            .kind = .monitor,
            .kind_label = backgroundKindLabel(.monitor),
            .title = slot.title(),
            .live = true,
            .can_stop = false,
            .has_status = false,
            .settled_status = "",
        };
        n += 1;
    }
    const sub_n = liveSubagentCount(model);
    var i: u32 = 0;
    while (i < sub_n and n < max_background_rows) : (i += 1) {
        const slot = &model.background_subagents[i];
        out[n] = .{
            .id = subagent_row_id_first + i,
            .kind = .subagent,
            .kind_label = backgroundKindLabel(.subagent),
            .title = slot.title(),
            .live = true,
            .can_stop = false,
            .has_status = false,
            .settled_status = "",
        };
        n += 1;
    }
    return out[0..n];
}

/// Arena copy of `fillBackgroundRows` for Native `background_rows`.
pub fn backgroundRows(model: *const Model, arena: std.mem.Allocator) []const BackgroundRow {
    var buf: [max_background_rows]BackgroundRow = undefined;
    const filled = fillBackgroundRows(model, &buf);
    if (filled.len == 0) return &.{};
    const out = arena.alloc(BackgroundRow, filled.len) catch return &.{};
    @memcpy(out, filled);
    return out;
}

/// Header info trigger: selected while the dropdown is open or
/// Background would show (streaming Process or visible settle).
pub fn environmentInfoSelected(model: *const Model) bool {
    return model.environment_summary_open or hasBackgroundSection(model);
}

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
/// composer Stop (`stopStream`). Idle is a no-op: Stop agent is
/// omitted when not streaming. `stopStream` records the Stopped
/// settle; this does not invent spawn/kill paths.
pub fn stopBackground(model: *Model, fx: *Effects) void {
    if (!model.is_streaming()) return;
    close(model);
    turn_stream.stopStream(model, fx);
}

fn expectNoBackgroundRows(model: *const Model) !void {
    var buf: [max_background_rows]BackgroundRow = undefined;
    try std.testing.expectEqual(@as(usize, 0), fillBackgroundRows(model, &buf).len);
}

fn expectOnlyProcessKinds(rows: []const BackgroundRow) !void {
    try std.testing.expect(rows.len <= max_background_rows);
    for (rows) |row| {
        try std.testing.expectEqual(BackgroundKind.process, row.kind);
        try std.testing.expectEqualStrings(kind_process_label, row.kind_label);
        try std.testing.expect(row.kind != .monitor);
        try std.testing.expect(row.kind != .subagent);
        try std.testing.expect(!std.mem.eql(u8, row.kind_label, kind_monitor_label));
        try std.testing.expect(!std.mem.eql(u8, row.kind_label, kind_subagent_label));
    }
}

fn expectLiveProcessRow(model: *const Model) !void {
    var buf: [max_background_rows]BackgroundRow = undefined;
    const rows = fillBackgroundRows(model, &buf);
    try expectOnlyProcessKinds(rows);
    try std.testing.expectEqual(@as(usize, 1), rows.len);
    try std.testing.expectEqual(process_row_id, rows[0].id);
    try std.testing.expectEqualStrings(process_row_label, rows[0].title);
    try std.testing.expect(rows[0].live);
    try std.testing.expect(rows[0].can_stop);
    try std.testing.expect(!rows[0].has_status);
    try std.testing.expectEqualStrings("", rows[0].settled_status);
}

fn expectSettledProcessRow(model: *const Model, status: []const u8) !void {
    var buf: [max_background_rows]BackgroundRow = undefined;
    const rows = fillBackgroundRows(model, &buf);
    try expectOnlyProcessKinds(rows);
    try std.testing.expectEqual(@as(usize, 1), rows.len);
    try std.testing.expectEqual(process_row_id, rows[0].id);
    try std.testing.expectEqualStrings(process_row_label, rows[0].title);
    try std.testing.expect(!rows[0].live);
    try std.testing.expect(!rows[0].can_stop);
    try std.testing.expect(rows[0].has_status);
    try std.testing.expectEqualStrings(status, rows[0].settled_status);
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
    try std.testing.expect(!hasSettledBackground(&model));
    try std.testing.expect(!hasBackgroundSection(&model));
    try std.testing.expect(environmentInfoSelected(&model));
    try expectNoBackgroundRows(&model);

    close(&model);
    try std.testing.expect(!environmentInfoSelected(&model));

    model.environment_summary_open = true;
    main.update(&model, .environment_stop_background, &fx);
    try std.testing.expect(model.environment_summary_open);
    try std.testing.expect(!model.is_streaming());
    try std.testing.expect(!hasSettledBackground(&model));
    try expectNoBackgroundRows(&model);
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
    try expectLiveProcessRow(&model);

    stopBackground(&model, &fx);
    try std.testing.expect(!model.environment_summary_open);
    try std.testing.expect(!model.is_streaming());
    try std.testing.expectEqual(main.Phase.idle, model.phase);
    try std.testing.expectEqual(@as(u32, 0), model.streaming_session);
    try std.testing.expect(!model.sessionById(id).?.busy);
    try std.testing.expectEqual(@as(usize, 0), fx.pendingTimerCount());
    try std.testing.expect(hasSettledBackground(&model));
    try std.testing.expectEqualStrings(settled_stopped_label, settledStatusLabel(&model));
    try std.testing.expect(hasBackgroundSection(&model));
    try expectSettledProcessRow(&model, settled_stopped_label);
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
    try expectLiveProcessRow(&model);

    main.update(&model, .environment_stop_background, &fx);
    try std.testing.expect(!model.environment_summary_open);
    try std.testing.expect(!model.is_streaming());
    try std.testing.expect(!model.sessionById(id).?.busy);
    try std.testing.expectEqual(@as(u32, 0), model.streaming_session);
    try std.testing.expectEqual(@as(usize, 0), fx.pendingTimerCount());
    try std.testing.expect(hasSettledBackground(&model));
    try std.testing.expectEqualStrings(settled_stopped_label, settledStatusLabel(&model));
    try expectSettledProcessRow(&model, settled_stopped_label);
}

test "idle with no settle omits Background; streaming shows the section" {
    var model = Model{};
    const id = model.addSession("env idle omit", .fx);
    model.selected = id;
    try std.testing.expect(!hasBackgroundSection(&model));
    try std.testing.expect(!hasSettledBackground(&model));
    try std.testing.expect(!environmentInfoSelected(&model));
    try std.testing.expectEqualStrings("", settledStatusLabel(&model));
    try expectNoBackgroundRows(&model);

    model.environment_summary_open = true;
    try std.testing.expect(environmentInfoSelected(&model));
    try std.testing.expect(!hasBackgroundSection(&model));
    try expectNoBackgroundRows(&model);

    model.phase = .streaming;
    model.streaming_session = id;
    try std.testing.expect(hasBackgroundSection(&model));
    try std.testing.expect(!hasSettledBackground(&model));
    try std.testing.expect(environmentInfoSelected(&model));
    try expectLiveProcessRow(&model);
}

test "successful finishStream without a queue settles Completed" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    const id = model.addSession("env settle complete", .fx);
    model.selected = id;
    main.update(&model, .{ .draft_edit = .{ .insert_text = "go" } }, &fx);
    main.update(&model, .send, &fx);
    try std.testing.expect(model.is_streaming());
    try std.testing.expect(hasBackgroundSection(&model));
    try std.testing.expect(!hasSettledBackground(&model));
    try std.testing.expect(environmentInfoSelected(&model));
    try expectLiveProcessRow(&model);

    var n: u32 = 0;
    while (n < 16 and model.is_streaming()) : (n += 1) {
        main.update(&model, .{ .tick = .{ .key = main.stream_timer_key } }, &fx);
    }
    try std.testing.expect(!model.is_streaming());
    try std.testing.expect(hasSettledBackground(&model));
    try std.testing.expectEqualStrings(settled_completed_label, settledStatusLabel(&model));
    try std.testing.expect(hasBackgroundSection(&model));
    try std.testing.expect(environmentInfoSelected(&model));
    try std.testing.expectEqual(id, model.background_settled_session);
    try std.testing.expectEqual(SettledStatus.completed, model.background_settled);
    try expectSettledProcessRow(&model, settled_completed_label);
}

test "queued finishStream restart stays on Process and does not flash Completed" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    const id = model.addSession("env settle queue", .fx);
    model.selected = id;
    main.update(&model, .{ .draft_edit = .{ .insert_text = "first" } }, &fx);
    main.update(&model, .send, &fx);
    try std.testing.expect(model.is_streaming());
    main.update(&model, .{ .draft_edit = .{ .insert_text = "queued follow-up" } }, &fx);
    main.update(&model, .send, &fx);
    try std.testing.expectEqual(@as(u32, 1), model.queuedCount(id));

    var n: u32 = 0;
    while (n < 16 and model.queuedCount(id) > 0) : (n += 1) {
        main.update(&model, .{ .tick = .{ .key = main.stream_timer_key } }, &fx);
    }
    try std.testing.expect(model.is_streaming());
    try std.testing.expectEqual(@as(u32, 0), model.queuedCount(id));
    try std.testing.expect(!hasSettledBackground(&model));
    try std.testing.expectEqual(SettledStatus.none, model.background_settled);
    try std.testing.expect(hasBackgroundSection(&model));
    try expectLiveProcessRow(&model);
}

test "stopStream and Esc settle Stopped" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    const id = model.addSession("env settle stop", .fx);
    model.selected = id;
    main.update(&model, .{ .draft_edit = .{ .insert_text = "go" } }, &fx);
    main.update(&model, .send, &fx);
    try std.testing.expect(model.is_streaming());
    main.update(&model, .stop_turn, &fx);
    try std.testing.expect(!model.is_streaming());
    try std.testing.expectEqualStrings(settled_stopped_label, settledStatusLabel(&model));
    try expectSettledProcessRow(&model, settled_stopped_label);

    var esc = Model{};
    const esc_id = esc.addSession("env settle esc", .fx);
    esc.selected = esc_id;
    main.update(&esc, .{ .draft_edit = .{ .insert_text = "go" } }, &fx);
    main.update(&esc, .send, &fx);
    try std.testing.expect(esc.is_streaming());
    main.update(&esc, .stop, &fx);
    try std.testing.expect(!esc.is_streaming());
    try std.testing.expectEqualStrings(settled_stopped_label, settledStatusLabel(&esc));
    try expectSettledProcessRow(&esc, settled_stopped_label);
}

test "drain=false finishStream settles Failed" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    const id = model.addSession("env settle fail", .fx);
    model.selected = id;
    main.update(&model, .{ .draft_edit = .{ .insert_text = "go" } }, &fx);
    main.update(&model, .send, &fx);
    try std.testing.expect(model.is_streaming());
    model.fx_spawn_key = main.fx_ask_key;
    main.update(&model, .{ .fx_exit = .{
        .key = main.fx_ask_key,
        .code = 1,
        .reason = .exited,
    } }, &fx);
    try std.testing.expect(!model.is_streaming());
    try std.testing.expectEqualStrings(settled_failed_label, settledStatusLabel(&model));
    try std.testing.expectEqual(SettledStatus.failed, model.background_settled);
    try expectSettledProcessRow(&model, settled_failed_label);
}

test "cap-1 settle overwrites; session switch hides another session's row" {
    var model = Model{};
    const first = model.addSession("env settle first", .fx);
    const second = model.addSession("env settle second", .fx);
    model.selected = first;
    settle(&model, first, .completed);
    try std.testing.expectEqualStrings(settled_completed_label, settledStatusLabel(&model));
    try std.testing.expect(hasBackgroundSection(&model));
    try expectSettledProcessRow(&model, settled_completed_label);

    settle(&model, first, .stopped);
    try std.testing.expectEqualStrings(settled_stopped_label, settledStatusLabel(&model));
    try std.testing.expectEqual(first, model.background_settled_session);
    try expectSettledProcessRow(&model, settled_stopped_label);

    settle(&model, second, .failed);
    try std.testing.expectEqual(second, model.background_settled_session);
    try std.testing.expectEqual(SettledStatus.failed, model.background_settled);
    try std.testing.expect(!hasSettledBackground(&model));
    try std.testing.expect(!hasBackgroundSection(&model));
    try expectNoBackgroundRows(&model);

    model.selected = second;
    try std.testing.expectEqualStrings(settled_failed_label, settledStatusLabel(&model));
    try std.testing.expect(hasBackgroundSection(&model));
    try expectSettledProcessRow(&model, settled_failed_label);

    model.selected = first;
    try std.testing.expect(!hasSettledBackground(&model));
    try std.testing.expectEqualStrings("", settledStatusLabel(&model));
    try expectNoBackgroundRows(&model);

    clearSettledIfSession(&model, second);
    try std.testing.expectEqual(SettledStatus.none, model.background_settled);
    try std.testing.expectEqual(@as(u32, 0), model.background_settled_session);
    model.selected = second;
    try std.testing.expect(!hasBackgroundSection(&model));
    try expectNoBackgroundRows(&model);
}

test "backgroundKindLabel is stable for Process Monitor Subagent" {
    try std.testing.expectEqualStrings(kind_process_label, backgroundKindLabel(.process));
    try std.testing.expectEqualStrings(kind_monitor_label, backgroundKindLabel(.monitor));
    try std.testing.expectEqualStrings(kind_subagent_label, backgroundKindLabel(.subagent));
    try std.testing.expectEqualStrings("Process", backgroundKindLabel(.process));
    try std.testing.expectEqualStrings("Monitor", backgroundKindLabel(.monitor));
    try std.testing.expectEqualStrings("Subagent", backgroundKindLabel(.subagent));
}

test "background registry never emits Monitor or Subagent from stream or settle without signals" {
    var model = Model{};
    const id = model.addSession("env kinds only process", .fx);
    model.selected = id;
    try expectNoBackgroundRows(&model);

    model.phase = .streaming;
    model.streaming_session = id;
    try expectLiveProcessRow(&model);

    model.phase = .idle;
    model.streaming_session = 0;
    settle(&model, id, .completed);
    try expectSettledProcessRow(&model, settled_completed_label);
    settle(&model, id, .stopped);
    try expectSettledProcessRow(&model, settled_stopped_label);
    settle(&model, id, .failed);
    try expectSettledProcessRow(&model, settled_failed_label);

    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena_rows = backgroundRows(&model, arena_state.allocator());
    try expectOnlyProcessKinds(arena_rows);
    try std.testing.expectEqual(@as(usize, 1), arena_rows.len);
    try std.testing.expectEqual(BackgroundKind.process, arena_rows[0].kind);

    const via_model = model.background_rows(arena_state.allocator());
    try expectOnlyProcessKinds(via_model);
    try std.testing.expectEqual(@as(usize, 1), via_model.len);
    try std.testing.expectEqualStrings(kind_process_label, via_model[0].kind_label);
}

test "fillBackgroundRows emits Subagent while live parent_tool_use_id signals exist" {
    var model = Model{};
    const id = model.addSession("env live subagent", .claude);
    model.selected = id;
    model.phase = .streaming;
    model.streaming_session = id;
    try expectLiveProcessRow(&model);

    noteLiveSubagent(&model, "");
    try expectLiveProcessRow(&model);

    noteLiveSubagent(&model, "toolu_agent_1");
    noteLiveSubagent(&model, "toolu_agent_1");
    var buf: [max_background_rows]BackgroundRow = undefined;
    var rows = fillBackgroundRows(&model, &buf);
    try std.testing.expectEqual(@as(usize, 2), rows.len);
    try std.testing.expectEqual(BackgroundKind.process, rows[0].kind);
    try std.testing.expectEqualStrings(process_row_label, rows[0].title);
    try std.testing.expect(rows[0].live);
    try std.testing.expect(rows[0].can_stop);
    try std.testing.expectEqual(subagent_row_id_first, rows[1].id);
    try std.testing.expectEqual(BackgroundKind.subagent, rows[1].kind);
    try std.testing.expectEqualStrings(kind_subagent_label, rows[1].kind_label);
    try std.testing.expectEqualStrings(kind_subagent_label, rows[1].title);
    try std.testing.expect(rows[1].live);
    try std.testing.expect(!rows[1].can_stop);
    try std.testing.expect(!rows[1].has_status);
    try std.testing.expect(rows[1].kind != .monitor);

    noteLiveSubagent(&model, "toolu_agent_2");
    rows = fillBackgroundRows(&model, &buf);
    try std.testing.expectEqual(@as(usize, 3), rows.len);
    try std.testing.expectEqual(BackgroundKind.subagent, rows[2].kind);
    try std.testing.expectEqual(subagent_row_id_first + 1, rows[2].id);

    model.phase = .idle;
    model.streaming_session = 0;
    settle(&model, id, .completed);
    try expectSettledProcessRow(&model, settled_completed_label);

    clearLiveSubagents(&model);
    try std.testing.expectEqual(@as(u32, 0), model.background_subagent_count);
    try expectSettledProcessRow(&model, settled_completed_label);
}

test "finishStream and stopStream clear live Subagent rows" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    const id = model.addSession("env clear subagent", .claude);
    model.selected = id;
    model.phase = .streaming;
    model.streaming_session = id;
    noteLiveSubagent(&model, "toolu_clear_1");
    var buf: [max_background_rows]BackgroundRow = undefined;
    try std.testing.expectEqual(@as(usize, 2), fillBackgroundRows(&model, &buf).len);

    turn_stream.finishStream(&model, &fx, true);
    try std.testing.expectEqual(@as(u32, 0), model.background_subagent_count);
    try expectSettledProcessRow(&model, settled_completed_label);

    model.phase = .streaming;
    model.streaming_session = id;
    if (model.sessionById(id)) |session| session.busy = true;
    noteLiveSubagent(&model, "toolu_clear_2");
    try std.testing.expectEqual(@as(usize, 2), fillBackgroundRows(&model, &buf).len);
    turn_stream.stopStream(&model, &fx);
    try std.testing.expectEqual(@as(u32, 0), model.background_subagent_count);
    try expectSettledProcessRow(&model, settled_stopped_label);
}

test "fillBackgroundRows emits Monitor while live Monitor tool_use signals exist" {
    var model = Model{};
    const id = model.addSession("env live monitor", .claude);
    model.selected = id;
    model.phase = .streaming;
    model.streaming_session = id;
    try expectLiveProcessRow(&model);

    noteLiveMonitor(&model, "");
    try expectLiveProcessRow(&model);

    noteLiveMonitor(&model, "toolu_mon_1");
    noteLiveMonitor(&model, "toolu_mon_1");
    var buf: [max_background_rows]BackgroundRow = undefined;
    var rows = fillBackgroundRows(&model, &buf);
    try std.testing.expectEqual(@as(usize, 2), rows.len);
    try std.testing.expectEqual(BackgroundKind.process, rows[0].kind);
    try std.testing.expectEqualStrings(process_row_label, rows[0].title);
    try std.testing.expect(rows[0].live);
    try std.testing.expect(rows[0].can_stop);
    try std.testing.expectEqual(monitor_row_id_first, rows[1].id);
    try std.testing.expectEqual(BackgroundKind.monitor, rows[1].kind);
    try std.testing.expectEqualStrings(kind_monitor_label, rows[1].kind_label);
    try std.testing.expectEqualStrings(kind_monitor_label, rows[1].title);
    try std.testing.expect(rows[1].live);
    try std.testing.expect(!rows[1].can_stop);
    try std.testing.expect(!rows[1].has_status);
    try std.testing.expect(rows[1].kind != .subagent);

    noteLiveMonitor(&model, "toolu_mon_2");
    rows = fillBackgroundRows(&model, &buf);
    try std.testing.expectEqual(@as(usize, 3), rows.len);
    try std.testing.expectEqual(BackgroundKind.monitor, rows[2].kind);
    try std.testing.expectEqual(monitor_row_id_first + 1, rows[2].id);

    model.phase = .idle;
    model.streaming_session = 0;
    settle(&model, id, .completed);
    try expectSettledProcessRow(&model, settled_completed_label);

    clearLiveMonitors(&model);
    try std.testing.expectEqual(@as(u32, 0), model.background_monitor_count);
    try expectSettledProcessRow(&model, settled_completed_label);
}

test "fillBackgroundRows emits Process then Monitor then Subagent under the cap" {
    var model = Model{};
    const id = model.addSession("env monitor subagent coexist", .claude);
    model.selected = id;
    model.phase = .streaming;
    model.streaming_session = id;

    noteLiveMonitor(&model, "toolu_mon_1");
    noteLiveSubagent(&model, "toolu_agent_1");
    var buf: [max_background_rows]BackgroundRow = undefined;
    var rows = fillBackgroundRows(&model, &buf);
    try std.testing.expectEqual(@as(usize, 3), rows.len);
    try std.testing.expectEqual(BackgroundKind.process, rows[0].kind);
    try std.testing.expectEqual(process_row_id, rows[0].id);
    try std.testing.expectEqual(BackgroundKind.monitor, rows[1].kind);
    try std.testing.expectEqual(monitor_row_id_first, rows[1].id);
    try std.testing.expectEqualStrings(kind_monitor_label, rows[1].title);
    try std.testing.expect(!rows[1].can_stop);
    try std.testing.expectEqual(BackgroundKind.subagent, rows[2].kind);
    try std.testing.expectEqual(subagent_row_id_first, rows[2].id);
    try std.testing.expect(rows[1].id != rows[2].id);
    try std.testing.expect(rows[1].id != process_row_id);

    var i: usize = 2;
    while (i <= max_live_monitors) : (i += 1) {
        var id_buf: [32]u8 = undefined;
        const label = std.fmt.bufPrint(&id_buf, "toolu_mon_{d}", .{i}) catch unreachable;
        noteLiveMonitor(&model, label);
    }
    noteLiveSubagent(&model, "toolu_agent_2");
    rows = fillBackgroundRows(&model, &buf);
    try std.testing.expectEqual(max_background_rows, rows.len);
    try std.testing.expectEqual(BackgroundKind.process, rows[0].kind);
    var n: usize = 1;
    while (n < max_background_rows) : (n += 1) {
        try std.testing.expectEqual(BackgroundKind.monitor, rows[n].kind);
        try std.testing.expectEqual(monitor_row_id_first + @as(u32, @intCast(n - 1)), rows[n].id);
    }
}

test "finishStream and stopStream clear live Monitor rows" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    const id = model.addSession("env clear monitor", .claude);
    model.selected = id;
    model.phase = .streaming;
    model.streaming_session = id;
    noteLiveMonitor(&model, "toolu_mon_clear_1");
    var buf: [max_background_rows]BackgroundRow = undefined;
    try std.testing.expectEqual(@as(usize, 2), fillBackgroundRows(&model, &buf).len);

    turn_stream.finishStream(&model, &fx, true);
    try std.testing.expectEqual(@as(u32, 0), model.background_monitor_count);
    try expectSettledProcessRow(&model, settled_completed_label);

    model.phase = .streaming;
    model.streaming_session = id;
    if (model.sessionById(id)) |session| session.busy = true;
    noteLiveMonitor(&model, "toolu_mon_clear_2");
    try std.testing.expectEqual(@as(usize, 2), fillBackgroundRows(&model, &buf).len);
    turn_stream.stopStream(&model, &fx);
    try std.testing.expectEqual(@as(u32, 0), model.background_monitor_count);
    try expectSettledProcessRow(&model, settled_stopped_label);
}

test "Send start clears live Monitor rows" {
    const prompt_spawn = @import("spawn.zig");
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    const id = model.addSession("env send clears monitor", .claude);
    model.selected = id;
    model.phase = .streaming;
    model.streaming_session = id;
    noteLiveMonitor(&model, "toolu_mon_send_1");
    noteLiveSubagent(&model, "toolu_agent_send_1");
    try std.testing.expectEqual(@as(u32, 1), model.background_monitor_count);
    try std.testing.expectEqual(@as(u32, 1), model.background_subagent_count);

    prompt_spawn.startPrompt(&model, &fx, id, "next turn");
    try std.testing.expectEqual(@as(u32, 0), model.background_monitor_count);
    try std.testing.expectEqual(@as(u32, 0), model.background_subagent_count);
    try std.testing.expect(model.is_streaming());
    try expectLiveProcessRow(&model);
}

