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
//! title is the stable `Monitor` label). Matching Claude user
//! `tool_result` (`tool_use_id`) fills a bounded runtime-only
//! 512KB last-window log on that row (newlines kept; not
//! sessions.json). Environment Summary `detail` stays a short
//! one-line preview; the right-panel Background body shows a
//! 100ms CSI-stripped render cache of that stored log. Live Monitor
//! rows set `can_stop`; Stop is Faku-side dismiss of that slot
//! (compact + free the heap log, ignore later output for that
//! `tool_use` id) on one-shot `claude -p --output-format
//! stream-json`. It does not invoke Claude's TaskStop tool
//! mid-turn (no long-lived session, no undocumented stdin). The
//! underlying Monitor may keep feeding the Claude process until
//! the turn ends; Faku stops showing and accumulating that row.
//! Live Subagent rows come from real
//! Claude stream-json `parent_tool_use_id` / Agent `tool_use`
//! signals. Live Subagent rows set `can_stop`; Stop is Faku-side
//! dismiss of that slot (compact + remember the id so later
//! `noteLiveSubagent` / `parent_tool_use_id` / Agent `tool_use`
//! cannot resurrect it until `clearDismissedSubagentIds` on the
//! next `startPrompt`) on one-shot
//! `claude -p`. It does not invoke Claude TaskStop / control_request
//! mid-turn (Native `fx.spawn` is one-buffer-then-close-stdin; no
//! official `claude acp`, no mid-turn stdin on print-mode `-p`).
//! Non-empty `parent_tool_use_id` plus text (`text_delta` /
//! assistant text content) fills a bounded runtime-only 512KB
//! last-window on that Subagent row — same size/policy as Monitor
//! (heap per row; drain-from-front on a UTF-8 boundary; newlines
//! kept; CSI stored raw and stripped for display). That text
//! still does not `appendToTurn` on the main stream. Environment
//! Summary `detail` stays a short one-line preview; the
//! right-panel Background body shows the 100ms CSI-stripped
//! render cache of that stored log. When the
//! turn settles (`finishStream` completed / failed, `stopStream`
//! stopped), currently-live Monitor and Subagent rows stay in
//! this runtime registry as settled (status from that Process
//! settle; Monitor / Subagent last-window kept; Faku-side
//! Dismiss via `can_stop`, not live Stop / not Claude TaskStop).
//! Honest about one-shot `claude -p`: after the run's
//! final result, Monitor / Subagent work is dead — settled
//! rows, not live / Running / Monitoring. `startPrompt` / a
//! queued restart does not wipe settled rows (it still clears
//! the dismissed-id list so a later turn can re-register the
//! same Agent / `parent_tool_use_id` as a new live row). Visible
//! fill is Process (live or last-turn settle), then Monitor
//! (live first, then settled), then Subagent (live first, then
//! settled), stopping at the cap. Settled Monitor / Subagent
//! (and Process) are keyed by session id so switching hides
//! another session's rows without clearing them; a new Process
//! settle overwrites the cap-1 Process slot; remove session
//! drops that session's Process settle and its Monitor /
//! Subagent slots (heap logs freed). Dismiss all settled
//! clears that selected session's visible leftovers (settled
//! Monitor / Subagent plus the cap-1 Process settle) without
//! stopping a live stream. Not persisted to
//! sessions.json / drafts.json. Header info trigger uses button
//! `selected` while the dropdown is open or this section would show.
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
//! fallback; not `refs/waku/`; not HEAD~1. Clicking a visible
//! Background row closes this dropdown and opens the right-panel
//! Background surface for that row (kind, title, live-or-settled
//! status, Monitor / Subagent 512KB last-window log, Stop when the selected
//! row is a live Process, live Monitor, or live Subagent; Dismiss
//! when the selected row is a settled Monitor or Subagent). Faku-side
//! Dismiss all settled ships for the selected session (settled
//! Monitor / Subagent slots plus the cap-1 Process settle; live
//! rows and the stream stay). Leftovers: Claude CLI TaskStop /
//! long-lived ACP, daemon `refreshBackgroundWork` /
//! WorkspaceOperation, full BackgroundWorkRegistry event/reconcile
//! parity. Kind chrome, Process registry,
//! first-cut live Monitor rows from Claude `Monitor` tool_use plus
//! a Waku-sized 512KB last-window log from matching user
//! `tool_result` (Environment Summary stays a one-line preview;
//! right-panel Background reads a 100ms CSI-stripped render cache
//! of that stored log — piggybacks `now_ms` / the stream tick;
//! Native has no GPUI SharedString and no dedicated 100ms timer)
//! and Faku-side
//! Monitor Stop on one-shot `-p`, first-cut live Subagent rows
//! from Claude `parent_tool_use_id` plus a matching 512KB
//! last-window from forwarded `parent_tool_use_id` text
//! (`text_delta` / assistant text; still off the main turn; same
//! 100ms render cache) and
//! Faku-side Subagent Stop on one-shot `-p` (dismiss that live
//! row; not Claude TaskStop mid-turn), first-cut settled Monitor /
//! Subagent persist after the turn (status from Process settle;
//! Monitor / Subagent last-window kept; Faku-side Dismiss, not
//! Claude TaskStop / daemon `refreshBackgroundWork`), Faku-side
//! Dismiss all settled for the selected session, and
//! first-cut right-panel Background ship; not Waku
//! BackgroundWorkRegistry event/reconcile/driver parity.
//! Not transcript checkpoint +/-. First-cut Force push ships on
//! composer Push… / Commit… (runtime-only ghost). New worktree…
//! first-cut Base picker ships. First-cut defer-until-Send
//! workspace mode ships (composer Work in; Send prep reuses
//! New worktree… `git worktree add`; optional `baseBranch` persist
//! ships on that draft). First-cut daemon `WorkspaceOperation::Push`
//! and `CreateWorktree` ship in `git_checkout` / Send prep. First-cut
//! daemon `WorkspaceOperation::Commit` ships in `git_commit`. First-cut
//! daemon `WorkspaceOperation::InspectBranches` ships in
//! `git_checkout`. First-cut daemon `WorkspaceOperation::CheckoutBranch`
//! ships in `git_checkout` (picker local-head checkout / New branch
//! create). First-cut daemon `WorkspaceOperation::InspectCommit`
//! ships in `git_commit` (Commit… open / include-unstaged re-probe).
//! Leftovers: other daemon `WorkspaceOperation`
//! variants (CaptureTurn, ListTree, GenerateCommitMessage, CollectReviewDiff, ref ops,
//! remotes-on-daemon-list, amend/force over daemon, remote `--track`
//! over daemon, …).

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
/// then settled Monitor from Claude `Monitor` tool_use (bounded
/// 512KB last-window log from matching user `tool_result`;
/// Summary `detail` is a one-line preview), and live then
/// settled Subagent from Claude `parent_tool_use_id` / Agent
/// `tool_use` (bounded 512KB last-window from forwarded
/// `parent_tool_use_id` text; Summary `detail` is a one-line
/// preview).
pub const BackgroundKind = enum {
    process,
    monitor,
    subagent,
};

pub const kind_process_label = "Process";
pub const kind_monitor_label = "Monitor";
pub const kind_subagent_label = "Subagent";

/// Bounded visible registry. Process takes one slot; remaining
/// slots are Monitor (live first, then settled) then Subagent
/// (live first, then settled).
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

/// Waku-sized Monitor / Subagent last-window
/// (`MAX_BACKGROUND_OUTPUT_BYTES`). Drain-from-front on a UTF-8
/// char boundary. Heap-allocated per live or settled row so
/// `Model` / `initialModel()` stay return-by-value safe (inline
/// `[512*1024]u8` × 7 is ~3.5MB). Runtime-only; kept after the
/// turn settles; freed when the row is dismissed, trimmed, or the
/// session is removed. Not sessions.json / drafts.json.
pub const max_monitor_output: usize = 512 * 1024;
pub const max_subagent_output: usize = max_monitor_output;

/// Environment Summary one-line preview cap. Collapsed whitespace,
/// CSI/ANSI stripped, trimmed; hidden when empty. Not the panel log.
pub const max_monitor_preview: usize = 512;
pub const max_subagent_preview: usize = max_monitor_preview;

/// Waku `OUTPUT_CACHE_REFRESH_INTERVAL`. Rebuilt CSI-stripped
/// display is throttled to this many milliseconds of `model.now_ms`.
/// Piggybacks the update loop / stream tick; Native has no
/// dedicated 100ms timer this cut.
pub const output_cache_refresh_interval_ms: i64 = 100;

/// Shared heap last-window + one-line preview + CSI-stripped
/// render cache. Monitor and Subagent both embed this so append /
/// preview / strip / free stay one implementation. Raw bytes stay
/// in `output_*`. `rendered_*` is runtime-only (same 512KB cap,
/// not sessions.json) and is rebuilt only when `dirty_output` and
/// at least `output_cache_refresh_interval_ms` have passed.
pub const LastWindow = struct {
    output_storage: []u8 = &.{},
    output_len: usize = 0,
    preview_storage: [max_monitor_preview]u8 = [_]u8{0} ** max_monitor_preview,
    preview_len: usize = 0,
    rendered_storage: []u8 = &.{},
    rendered_len: usize = 0,
    dirty_output: bool = false,

    pub fn output(self: *const LastWindow) []const u8 {
        return self.output_storage[0..self.output_len];
    }

    pub fn preview(self: *const LastWindow) []const u8 {
        return self.preview_storage[0..self.preview_len];
    }

    /// CSI-stripped last-window for the right-panel body. Empty
    /// until `refreshBackgroundOutputCache` rebuilds it.
    pub fn rendered(self: *const LastWindow) []const u8 {
        return self.rendered_storage[0..self.rendered_len];
    }
};

/// Runtime-only Subagent slot. Keyed by
/// `parent_tool_use_id` / Agent `tool_use` id. `settled == .none`
/// is live; otherwise a first-cut persist-after-settle row that
/// keeps the heap last-window. Not persisted. First-cut title is
/// the stable `Subagent` label. Output is a bounded 512KB
/// last-window from forwarded `parent_tool_use_id` text
/// (`text_delta` / assistant text; newlines kept; CSI stored raw
/// and stripped for display). Empty until the first matching
/// text. Does not register a row on append alone.
pub const LiveSubagent = struct {
    id_storage: [max_subagent_id]u8 = [_]u8{0} ** max_subagent_id,
    id_len: usize = 0,
    title_storage: [max_subagent_title]u8 = [_]u8{0} ** max_subagent_title,
    title_len: usize = 0,
    session_id: u32 = 0,
    settled: SettledStatus = .none,
    log: LastWindow = .{},

    pub fn parentId(self: *const LiveSubagent) []const u8 {
        return self.id_storage[0..self.id_len];
    }

    pub fn title(self: *const LiveSubagent) []const u8 {
        if (self.title_len == 0) return kind_subagent_label;
        return self.title_storage[0..self.title_len];
    }

    pub fn output(self: *const LiveSubagent) []const u8 {
        return self.log.output();
    }

    /// Single-line preview for Environment Summary. Collapsed
    /// whitespace, CSI/ANSI stripped, trimmed. Empty when no
    /// visible output has landed (chrome hides it).
    pub fn preview(self: *const LiveSubagent) []const u8 {
        return self.log.preview();
    }
};

/// Runtime-only dismissed Subagent id. `noteLiveSubagent` skips
/// these until `clearDismissedSubagentIds` (next `startPrompt`)
/// or a full `clearLiveSubagents`. Cap matches live slots; when
/// full, the oldest dismissed id is dropped so a later signal for
/// that old id could register again. Not persisted.
pub const DismissedSubagentId = struct {
    storage: [max_subagent_id]u8 = [_]u8{0} ** max_subagent_id,
    len: usize = 0,

    pub fn id(self: *const DismissedSubagentId) []const u8 {
        return self.storage[0..self.len];
    }
};

/// Runtime-only Monitor slot. Keyed by Claude `Monitor`
/// `tool_use` id. `settled == .none` is live; otherwise a
/// first-cut persist-after-settle row that keeps the heap
/// last-window. Not persisted. First-cut title is the stable
/// `Monitor` label (no undocumented input scrape). Output is a
/// bounded 512KB last-window from matching user `tool_result`
/// text (newlines kept; CSI stored raw and stripped for display).
pub const LiveMonitor = struct {
    id_storage: [max_monitor_id]u8 = [_]u8{0} ** max_monitor_id,
    id_len: usize = 0,
    title_storage: [max_monitor_title]u8 = [_]u8{0} ** max_monitor_title,
    title_len: usize = 0,
    session_id: u32 = 0,
    settled: SettledStatus = .none,
    /// Heap last-window (`max_monitor_output`). Empty until the
    /// first matching `tool_result`. Kept after settle; freed
    /// when the row is dismissed, trimmed, or the session is
    /// removed.
    log: LastWindow = .{},

    pub fn toolUseId(self: *const LiveMonitor) []const u8 {
        return self.id_storage[0..self.id_len];
    }

    pub fn title(self: *const LiveMonitor) []const u8 {
        if (self.title_len == 0) return kind_monitor_label;
        return self.title_storage[0..self.title_len];
    }

    pub fn output(self: *const LiveMonitor) []const u8 {
        return self.log.output();
    }

    /// Single-line preview for Environment Summary. Collapsed
    /// whitespace, CSI/ANSI stripped, trimmed. Empty when no
    /// visible output has landed (chrome hides it).
    pub fn preview(self: *const LiveMonitor) []const u8 {
        return self.log.preview();
    }
};

/// Process-kind row title. Honest about Faku-side stream state
/// (not an OS process watch).
pub const process_row_label = "Agent turn";
pub const settled_completed_label = "Completed";
pub const settled_stopped_label = "Stopped";
pub const settled_failed_label = "Failed";
/// Live Process / Subagent status on the right-panel Background
/// surface. Not a new registry — derived from `BackgroundRow.live`.
pub const live_running_label = "Running";
/// Live Monitor status. Same derivation as `live_running_label`.
pub const live_monitoring_label = "Monitoring";
pub const empty_background_work_label = "No background work";
pub const no_output_label = "No output";
/// Process Stop. Same composer Stop / `stopStream` path.
pub const process_stop_label = "Stop agent";
/// Monitor Stop. Faku-side dismiss of that live row; not Claude
/// TaskStop on one-shot `claude -p`. Distinct from composer Stop.
pub const monitor_stop_label = "Stop monitor";
/// Settled Monitor dismiss. Faku-side clear of that leftover row;
/// not live Stop and not Claude TaskStop.
pub const monitor_dismiss_label = "Dismiss monitor";
/// Subagent Stop. Faku-side dismiss of that live row; not Claude
/// TaskStop on one-shot `claude -p`. Distinct from Process / Monitor.
pub const subagent_stop_label = "Stop subagent";
/// Settled Subagent dismiss. Faku-side clear of that leftover row;
/// not live Stop and not Claude TaskStop.
pub const subagent_dismiss_label = "Dismiss subagent";

/// Visible Background registry row. Native `background_rows`
/// iterates this. Not persisted to sessions.json / drafts.json.
pub const BackgroundRow = struct {
    id: u32,
    kind: BackgroundKind,
    kind_label: []const u8,
    title: []const u8,
    live: bool,
    can_stop: bool,
    /// Process: `Stop agent` while live (empty when settled).
    /// Monitor: `Stop monitor` while live, `Dismiss monitor` when
    /// settled. Subagent: `Stop subagent` while live, `Dismiss
    /// subagent` when settled. Empty when `can_stop` is false.
    /// Native binds this so one press handler can label Process vs
    /// Monitor vs Subagent without new widgets.
    stop_label: []const u8,
    has_status: bool,
    settled_status: []const u8,
    /// Monitor / Subagent one-line preview. Process stays empty so
    /// Completed / Stopped / Failed is not reused. Hidden when
    /// empty. The right-panel body reads the stored log, not this
    /// field.
    has_detail: bool,
    detail: []const u8,
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

/// Drop the cap-1 Process row when that session is removed, plus
/// that session's Monitor / Subagent slots (heap logs freed).
/// Other sessions keep their rows.
pub fn clearSettledIfSession(model: *Model, session_id: u32) void {
    if (session_id == 0) return;
    if (model.background_settled_session == session_id) clearSettled(model);
    var i: u32 = 0;
    while (i < model.background_monitor_count) {
        if (model.background_monitors[i].session_id == session_id) {
            removeMonitorAt(model, i);
            continue;
        }
        i += 1;
    }
    i = 0;
    while (i < model.background_subagent_count) {
        if (model.background_subagents[i].session_id == session_id) {
            removeSubagentAt(model, i);
            continue;
        }
        i += 1;
    }
}

/// Convert currently-live Monitor / Subagent rows (`settled ==
/// .none`) to `status` without freeing heap last-windows.
/// Fill then keeps `can_stop` with Dismiss labels (not live Stop).
/// Status matches Process settle (`.completed` / `.failed` /
/// `.stopped`). `.none` is a no-op. Does not persist to sessions.json.
pub fn settleLiveBackgroundSignals(model: *Model, session_id: u32, status: SettledStatus) void {
    if (status == .none) return;
    var i: u32 = 0;
    while (i < model.background_monitor_count) : (i += 1) {
        const slot = &model.background_monitors[i];
        if (slot.settled != .none) continue;
        slot.settled = status;
        if (slot.session_id == 0) slot.session_id = session_id;
    }
    i = 0;
    while (i < model.background_subagent_count) : (i += 1) {
        const slot = &model.background_subagents[i];
        if (slot.settled != .none) continue;
        slot.settled = status;
        if (slot.session_id == 0) slot.session_id = session_id;
    }
    // Settled rows stay visible with no further stream ticks;
    // rebuild dirty rendered buffers even inside the 100ms window.
    _ = refreshBackgroundOutputCacheNow(model);
}

/// Drop the dismissed-id list so a later turn can re-register the
/// same Agent / `parent_tool_use_id` as a new live row. Does not
/// wipe settled Monitor / Subagent.
pub fn clearDismissedSubagentIds(model: *Model) void {
    var i: u32 = 0;
    while (i < max_live_subagents) : (i += 1) {
        model.background_dismissed_subagents[i] = .{};
    }
    model.background_dismissed_subagent_count = 0;
}

/// Drop every Subagent slot (live and settled), free their heap
/// last-windows, and clear the dismissed-id list. Walks every
/// slot so a count-only reset cannot leak a buffer. Test /
/// full-wipe helper; turn settle does not call this.
pub fn clearLiveSubagents(model: *Model) void {
    var i: u32 = 0;
    while (i < max_live_subagents) : (i += 1) {
        releaseLog(&model.background_subagents[i].log);
        model.background_subagents[i] = .{};
    }
    model.background_subagent_count = 0;
    clearDismissedSubagentIds(model);
}

/// Drop every Monitor slot (live and settled) and free their
/// heap last-windows. Walks every slot so a count-only reset
/// cannot leak a buffer. Test / full-wipe helper; turn settle
/// does not call this.
pub fn clearLiveMonitors(model: *Model) void {
    var i: u32 = 0;
    while (i < max_live_monitors) : (i += 1) {
        releaseLog(&model.background_monitors[i].log);
        model.background_monitors[i] = .{};
    }
    model.background_monitor_count = 0;
}

/// Drop every Monitor and Subagent slot together. Full wipe;
/// turn settle / `startPrompt` do not call this.
pub fn clearLiveBackgroundSignals(model: *Model) void {
    clearLiveMonitors(model);
    clearLiveSubagents(model);
}

fn statusLabel(status: SettledStatus) []const u8 {
    return switch (status) {
        .none => "",
        .completed => settled_completed_label,
        .stopped => settled_stopped_label,
        .failed => settled_failed_label,
    };
}

fn settledSessionVisible(model: *const Model, session_id: u32) bool {
    if (session_id == 0) return false;
    if (session_id != model.selected) return false;
    return model.sessionByIdConst(session_id) != null;
}

/// Register a live Subagent keyed by non-empty
/// `parent_tool_use_id` / Agent `tool_use` id. Duplicate *live*
/// ids are a no-op. A settled row of the same id is left settled;
/// unique Claude `toolu_…` ids across turns are expected, so a
/// later-turn duplicate becomes a new live slot. Dismissed ids
/// stay ignored until `clearDismissedSubagentIds`. Cap
/// `max_live_subagents` (Process keeps a slot); oldest settled
/// is trimmed before refusing a new live row. Title is the
/// stable `Subagent` label this cut. Stamps `session_id` from
/// `model.streaming_session`.
pub fn noteLiveSubagent(model: *Model, parent_id: []const u8) void {
    if (parent_id.len == 0) return;
    if (isDismissedSubagent(model, parent_id)) return;
    var i: u32 = 0;
    while (i < model.background_subagent_count) : (i += 1) {
        const slot = &model.background_subagents[i];
        if (slot.settled != .none) continue;
        if (std.mem.eql(u8, slot.parentId(), parent_id)) return;
    }
    if (model.background_subagent_count >= max_live_subagents) {
        if (!trimOldestSettledSubagent(model)) return;
    }
    const slot = &model.background_subagents[model.background_subagent_count];
    releaseLog(&slot.log);
    slot.* = .{};
    const writeFixed = main.writeFixed;
    writeFixed(&slot.id_storage, &slot.id_len, parent_id);
    writeFixed(&slot.title_storage, &slot.title_len, kind_subagent_label);
    slot.session_id = model.streaming_session;
    slot.settled = .none;
    model.background_subagent_count += 1;
}

/// Register a live Monitor keyed by non-empty Claude `Monitor`
/// `tool_use` id. Duplicate *live* ids are a no-op. A settled
/// row of the same id is left settled; a later-turn duplicate
/// becomes a new live slot. Cap `max_live_monitors` (Process
/// keeps a slot); oldest settled is trimmed (heap log freed)
/// before refusing a new live row. Title is the stable
/// `Monitor` label this cut. Not Bash, Agent, or
/// `parent_tool_use_id`. Output append does not register a row.
/// Stamps `session_id` from `model.streaming_session`.
pub fn noteLiveMonitor(model: *Model, tool_use_id: []const u8) void {
    if (tool_use_id.len == 0) return;
    var i: u32 = 0;
    while (i < model.background_monitor_count) : (i += 1) {
        const slot = &model.background_monitors[i];
        if (slot.settled != .none) continue;
        if (std.mem.eql(u8, slot.toolUseId(), tool_use_id)) return;
    }
    if (model.background_monitor_count >= max_live_monitors) {
        if (!trimOldestSettledMonitor(model)) return;
    }
    const slot = &model.background_monitors[model.background_monitor_count];
    releaseLog(&slot.log);
    slot.* = .{};
    const writeFixed = main.writeFixed;
    writeFixed(&slot.id_storage, &slot.id_len, tool_use_id);
    writeFixed(&slot.title_storage, &slot.title_len, kind_monitor_label);
    slot.session_id = model.streaming_session;
    slot.settled = .none;
    model.background_monitor_count += 1;
}

/// Append output onto a *live* Monitor whose `tool_use` id
/// matches. No-op when id/text is empty, no live row is
/// registered, or the matching row is already settled (one-shot
/// `-p` is done). Does not create a Monitor row (Bash / Agent /
/// unknown ids stay ignored). Duplicate apply of the same delta
/// just appends. Last-window drain-from-front at
/// `max_monitor_output`; UTF-8 char-boundary safe. Stored bytes
/// keep newlines and raw CSI; Environment Summary `preview`
/// collapses whitespace and strips complete CSI. Marks the 100ms
/// render cache dirty; the panel buffer is rebuilt on
/// `refreshBackgroundOutputCache`, not here.
pub fn appendLiveMonitorOutput(model: *Model, tool_use_id: []const u8, text: []const u8) void {
    if (tool_use_id.len == 0 or text.len == 0) return;
    var i: u32 = 0;
    while (i < model.background_monitor_count) : (i += 1) {
        const slot = &model.background_monitors[i];
        if (slot.settled != .none) continue;
        if (!std.mem.eql(u8, slot.toolUseId(), tool_use_id)) continue;
        const storage = ensureLog(&slot.log);
        if (storage.len == 0) return;
        appendBounded(storage, &slot.log.output_len, text);
        rebuildPreview(&slot.log);
        slot.log.dirty_output = true;
        return;
    }
}

/// Append output onto a *live* Subagent whose parent /
/// Agent `tool_use` id matches. No-op when id/text is empty, no
/// live row is registered, or the matching row is already
/// settled (one-shot `-p` is done). Does not create a Subagent
/// row (empty / unknown / dismissed ids stay ignored). Duplicate
/// apply of the same delta just appends. Last-window
/// drain-from-front at `max_subagent_output`; UTF-8
/// char-boundary safe. Stored bytes keep newlines and raw CSI;
/// Environment Summary `preview` collapses whitespace and strips
/// complete CSI. Marks the 100ms render cache dirty; the panel
/// buffer is rebuilt on `refreshBackgroundOutputCache`, not here.
/// Same size/policy as Monitor.
pub fn appendLiveSubagentOutput(model: *Model, parent_id: []const u8, text: []const u8) void {
    if (parent_id.len == 0 or text.len == 0) return;
    var i: u32 = 0;
    while (i < model.background_subagent_count) : (i += 1) {
        const slot = &model.background_subagents[i];
        if (slot.settled != .none) continue;
        if (!std.mem.eql(u8, slot.parentId(), parent_id)) continue;
        const storage = ensureLog(&slot.log);
        if (storage.len == 0) return;
        appendBounded(storage, &slot.log.output_len, text);
        rebuildPreview(&slot.log);
        slot.log.dirty_output = true;
        return;
    }
}

fn collapseWsByte(c: u8) u8 {
    return switch (c) {
        '\n', '\r', '\t' => ' ',
        else => c,
    };
}

fn utf8AlignForward(bytes: []const u8, start: usize) usize {
    var i = start;
    while (i < bytes.len and (bytes[i] & 0xC0) == 0x80) i += 1;
    return i;
}

fn isCsiFinal(c: u8) bool {
    return c >= '@' and c <= '~';
}

/// Complete CSI length at `i` (`ESC [ … final` in `@`…`~`), or 0
/// when the sequence is missing or split across the buffer end.
fn completeCsiLen(bytes: []const u8, i: usize) usize {
    if (i >= bytes.len or bytes[i] != 0x1b) return 0;
    if (i + 1 >= bytes.len or bytes[i + 1] != '[') return 0;
    var j = i + 2;
    while (j < bytes.len and !isCsiFinal(bytes[j])) : (j += 1) {}
    if (j >= bytes.len) return 0;
    return j + 1 - i;
}

/// Strip complete CSI for display. Incomplete CSI at the end is
/// left as-is. Refresh runs this against the concatenated raw
/// last-window so a sequence split across deltas is stripped once
/// it is complete in the buffer.
fn stripAnsi(src: []const u8, dest: []u8) usize {
    var n: usize = 0;
    var i: usize = 0;
    while (i < src.len) {
        const csi = completeCsiLen(src, i);
        if (csi > 0) {
            i += csi;
            continue;
        }
        if (n >= dest.len) break;
        dest[n] = src[i];
        n += 1;
        i += 1;
    }
    return n;
}

fn ensureLog(log: *LastWindow) []u8 {
    if (log.output_storage.len == max_monitor_output) return log.output_storage;
    if (log.output_storage.len != 0) {
        std.heap.page_allocator.free(log.output_storage);
        log.output_storage = &.{};
        log.output_len = 0;
    }
    const buf = std.heap.page_allocator.alloc(u8, max_monitor_output) catch return &.{};
    log.output_storage = buf;
    log.output_len = 0;
    return buf;
}

fn releaseLog(log: *LastWindow) void {
    if (log.output_storage.len != 0) {
        std.heap.page_allocator.free(log.output_storage);
    }
    if (log.rendered_storage.len != 0) {
        std.heap.page_allocator.free(log.rendered_storage);
    }
    log.output_storage = &.{};
    log.output_len = 0;
    log.preview_len = 0;
    log.rendered_storage = &.{};
    log.rendered_len = 0;
    log.dirty_output = false;
}

fn ensureRendered(log: *LastWindow) []u8 {
    if (log.rendered_storage.len == max_monitor_output) return log.rendered_storage;
    if (log.rendered_storage.len != 0) {
        std.heap.page_allocator.free(log.rendered_storage);
        log.rendered_storage = &.{};
        log.rendered_len = 0;
    }
    const buf = std.heap.page_allocator.alloc(u8, max_monitor_output) catch return &.{};
    log.rendered_storage = buf;
    log.rendered_len = 0;
    return buf;
}

fn rebuildRendered(log: *LastWindow) void {
    log.dirty_output = false;
    const raw = log.output();
    if (raw.len == 0) {
        log.rendered_len = 0;
        return;
    }
    const dest = ensureRendered(log);
    if (dest.len == 0) {
        log.dirty_output = true;
        return;
    }
    log.rendered_len = stripAnsi(raw, dest);
}

fn anyDirtyBackgroundOutput(model: *const Model) bool {
    var i: u32 = 0;
    while (i < model.background_monitor_count) : (i += 1) {
        if (model.background_monitors[i].log.dirty_output) return true;
    }
    i = 0;
    while (i < model.background_subagent_count) : (i += 1) {
        if (model.background_subagents[i].log.dirty_output) return true;
    }
    return false;
}

/// True while at least one Monitor / Subagent last-window still
/// needs a cache rebuild. A retry is requested only while dirty.
pub fn backgroundOutputCacheDirty(model: *const Model) bool {
    return anyDirtyBackgroundOutput(model);
}

fn refreshBackgroundOutputCacheAt(model: *Model, force: bool) bool {
    if (!anyDirtyBackgroundOutput(model)) return false;
    if (!force) {
        if (model.background_output_cache_refresh_ms) |last| {
            if (model.now_ms >= last and model.now_ms - last < output_cache_refresh_interval_ms) {
                return false;
            }
        }
    }
    var i: u32 = 0;
    while (i < model.background_monitor_count) : (i += 1) {
        const log = &model.background_monitors[i].log;
        if (log.dirty_output) rebuildRendered(log);
    }
    i = 0;
    while (i < model.background_subagent_count) : (i += 1) {
        const log = &model.background_subagents[i].log;
        if (log.dirty_output) rebuildRendered(log);
    }
    model.background_output_cache_refresh_ms = model.now_ms;
    return true;
}

/// Rebuild dirty CSI-stripped last-window caches at most once per
/// `output_cache_refresh_interval_ms` of `model.now_ms`. Returns
/// true when at least one buffer was rebuilt. Unchanged snapshots
/// (not dirty) are a no-op. Paint / Native view bind must not call
/// this; `backgroundWorkOutput` reads the cache only.
pub fn refreshBackgroundOutputCache(model: *Model) bool {
    return refreshBackgroundOutputCacheAt(model, false);
}

fn refreshBackgroundOutputCacheNow(model: *Model) bool {
    return refreshBackgroundOutputCacheAt(model, true);
}

fn appendBounded(storage: []u8, len: *usize, text: []const u8) void {
    if (text.len == 0 or storage.len == 0) return;
    if (text.len >= storage.len) {
        const start = utf8AlignForward(text, text.len - storage.len);
        const chunk = text[start..];
        @memcpy(storage[0..chunk.len], chunk);
        len.* = chunk.len;
        return;
    }
    const combined = len.* + text.len;
    if (combined > storage.len) {
        const drop = combined - storage.len;
        const start = utf8AlignForward(storage[0..len.*], drop);
        const keep = len.* - start;
        if (start > 0 and keep > 0) {
            std.mem.copyForwards(u8, storage[0..keep], storage[start..len.*]);
        }
        len.* = keep;
    }
    const n = len.*;
    @memcpy(storage[n .. n + text.len], text);
    len.* = n + text.len;
}

fn rebuildPreview(log: *LastWindow) void {
    log.preview_len = 0;
    const raw = log.output();
    var visible: usize = 0;
    var i: usize = 0;
    while (i < raw.len) {
        const csi = completeCsiLen(raw, i);
        if (csi > 0) {
            i += csi;
            continue;
        }
        visible += 1;
        i += 1;
    }
    const skip = if (visible > max_monitor_preview) visible - max_monitor_preview else 0;
    i = 0;
    var seen: usize = 0;
    while (i < raw.len) {
        const csi = completeCsiLen(raw, i);
        if (csi > 0) {
            i += csi;
            continue;
        }
        const c = collapseWsByte(raw[i]);
        i += 1;
        if (seen < skip) {
            seen += 1;
            continue;
        }
        log.preview_storage[log.preview_len] = c;
        log.preview_len += 1;
        if (log.preview_len == max_monitor_preview) break;
    }
    if (log.preview_len > 0) {
        const aligned = utf8AlignForward(log.preview_storage[0..log.preview_len], 0);
        if (aligned > 0) {
            const keep = log.preview_len - aligned;
            if (keep > 0) {
                std.mem.copyForwards(u8, log.preview_storage[0..keep], log.preview_storage[aligned..log.preview_len]);
            }
            log.preview_len = keep;
        }
    }
    const slice = log.preview_storage[0..log.preview_len];
    const trimmed = std.mem.trim(u8, slice, " ");
    if (trimmed.len == 0) {
        log.preview_len = 0;
        return;
    }
    if (trimmed.ptr != slice.ptr) {
        std.mem.copyForwards(u8, log.preview_storage[0..trimmed.len], trimmed);
    }
    log.preview_len = trimmed.len;
}

/// Live Subagent rows (`settled == .none`) exist only while
/// streaming. Settled rows use `fillBackgroundRows`.
pub fn liveSubagentCount(model: *const Model) u32 {
    if (!model.is_streaming()) return 0;
    var n: u32 = 0;
    var i: u32 = 0;
    while (i < model.background_subagent_count) : (i += 1) {
        if (model.background_subagents[i].settled == .none) n += 1;
    }
    return n;
}

/// Live Monitor rows (`settled == .none`) exist only while
/// streaming. Settled rows use `fillBackgroundRows`.
pub fn liveMonitorCount(model: *const Model) u32 {
    if (!model.is_streaming()) return 0;
    var n: u32 = 0;
    var i: u32 = 0;
    while (i < model.background_monitor_count) : (i += 1) {
        if (model.background_monitors[i].settled == .none) n += 1;
    }
    return n;
}

fn visibleLiveMonitor(model: *const Model, index: u32) bool {
    if (!model.is_streaming()) return false;
    if (index >= model.background_monitor_count) return false;
    return model.background_monitors[index].settled == .none;
}

fn visibleSettledMonitor(model: *const Model, index: u32) bool {
    if (index >= model.background_monitor_count) return false;
    const slot = &model.background_monitors[index];
    if (slot.settled == .none) return false;
    return settledSessionVisible(model, slot.session_id);
}

fn visibleLiveSubagent(model: *const Model, index: u32) bool {
    if (!model.is_streaming()) return false;
    if (index >= model.background_subagent_count) return false;
    return model.background_subagents[index].settled == .none;
}

fn visibleSettledSubagent(model: *const Model, index: u32) bool {
    if (index >= model.background_subagent_count) return false;
    const slot = &model.background_subagents[index];
    if (slot.settled == .none) return false;
    return settledSessionVisible(model, slot.session_id);
}

fn hasVisibleSettledSignals(model: *const Model) bool {
    var i: u32 = 0;
    while (i < model.background_monitor_count) : (i += 1) {
        if (visibleSettledMonitor(model, i)) return true;
    }
    i = 0;
    while (i < model.background_subagent_count) : (i += 1) {
        if (visibleSettledSubagent(model, i)) return true;
    }
    return false;
}

/// At least one dismissable settled leftover for the selected
/// session: visible last-turn Process, and/or a visible settled
/// Monitor / Subagent. Gates Environment Summary **Dismiss all
/// settled**. Live-only streaming is false (live Stop is unchanged).
pub fn hasDismissableSettledBackground(model: *const Model) bool {
    return hasSettledBackground(model) or hasVisibleSettledSignals(model);
}

/// Visible settled Process row for the selected session. Hidden
/// while `is_streaming` so a queued restart stays on the Process
/// row instead of flashing Completed.
pub fn hasSettledBackground(model: *const Model) bool {
    if (model.is_streaming()) return false;
    if (model.background_settled == .none) return false;
    return settledSessionVisible(model, model.background_settled_session);
}

/// Background section: live Process, the selected session's
/// settled last-turn Process, and/or that session's settled
/// Monitor / Subagent rows.
pub fn hasBackgroundSection(model: *const Model) bool {
    return model.is_streaming() or hasSettledBackground(model) or hasVisibleSettledSignals(model);
}

pub fn settledStatusLabel(model: *const Model) []const u8 {
    if (!hasSettledBackground(model)) return "";
    return statusLabel(model.background_settled);
}

fn fillMonitorRow(slot: *const LiveMonitor, index: u32) BackgroundRow {
    const live = slot.settled == .none;
    const status = if (live) "" else statusLabel(slot.settled);
    const detail = slot.preview();
    return .{
        .id = monitor_row_id_first + index,
        .kind = .monitor,
        .kind_label = backgroundKindLabel(.monitor),
        .title = slot.title(),
        .live = live,
        .can_stop = true,
        .stop_label = if (live) monitor_stop_label else monitor_dismiss_label,
        .has_status = status.len > 0,
        .settled_status = status,
        .has_detail = detail.len > 0,
        .detail = detail,
    };
}

fn fillSubagentRow(slot: *const LiveSubagent, index: u32) BackgroundRow {
    const live = slot.settled == .none;
    const status = if (live) "" else statusLabel(slot.settled);
    const detail = slot.preview();
    return .{
        .id = subagent_row_id_first + index,
        .kind = .subagent,
        .kind_label = backgroundKindLabel(.subagent),
        .title = slot.title(),
        .live = live,
        .can_stop = true,
        .stop_label = if (live) subagent_stop_label else subagent_dismiss_label,
        .has_status = status.len > 0,
        .settled_status = status,
        .has_detail = detail.len > 0,
        .detail = detail,
    };
}

/// Project the runtime registry into `out` (cap `max_background_rows`).
/// Streaming wins so a queued `finishStream` restart stays on the
/// live Process row instead of flashing Completed. Fill order:
/// Process (live or last-turn settle), then Monitor (live first,
/// then settled for the selected session), then Subagent (live
/// first, then settled). Monitor / Subagent `detail` is the one-line
/// preview; the right-panel body reads the stored log. Fill stops at the cap.
pub fn fillBackgroundRows(model: *const Model, out: *[max_background_rows]BackgroundRow) []const BackgroundRow {
    if (!hasBackgroundSection(model)) return out[0..0];
    var n: usize = 0;
    const live = model.is_streaming();
    if (live or hasSettledBackground(model)) {
        const status = if (live) "" else settledStatusLabel(model);
        out[0] = .{
            .id = process_row_id,
            .kind = .process,
            .kind_label = backgroundKindLabel(.process),
            .title = process_row_label,
            .live = live,
            .can_stop = live,
            .stop_label = if (live) process_stop_label else "",
            .has_status = status.len > 0,
            .settled_status = status,
            .has_detail = false,
            .detail = "",
        };
        n = 1;
    }
    var mi: u32 = 0;
    while (mi < model.background_monitor_count and n < max_background_rows) : (mi += 1) {
        if (!visibleLiveMonitor(model, mi)) continue;
        out[n] = fillMonitorRow(&model.background_monitors[mi], mi);
        n += 1;
    }
    mi = 0;
    while (mi < model.background_monitor_count and n < max_background_rows) : (mi += 1) {
        if (!visibleSettledMonitor(model, mi)) continue;
        out[n] = fillMonitorRow(&model.background_monitors[mi], mi);
        n += 1;
    }
    var i: u32 = 0;
    while (i < model.background_subagent_count and n < max_background_rows) : (i += 1) {
        if (!visibleLiveSubagent(model, i)) continue;
        out[n] = fillSubagentRow(&model.background_subagents[i], i);
        n += 1;
    }
    i = 0;
    while (i < model.background_subagent_count and n < max_background_rows) : (i += 1) {
        if (!visibleSettledSubagent(model, i)) continue;
        out[n] = fillSubagentRow(&model.background_subagents[i], i);
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

/// Close the popover, then dispatch Stop / Dismiss by Native
/// `background_rows` id. Process (`process_row_id`) cancels the live
/// turn the same way as composer Stop (`stopStream`) and records
/// Stopped; idle Process is a no-op. Monitor ids (live or settled,
/// including idle after the turn) dismiss that Faku-side slot only
/// (compact + free heap log; later `tool_result` for that `tool_use`
/// id is ignored because the slot is gone). Subagent ids (live or
/// settled) dismiss that Faku-side slot only (compact + free heap
/// log; live dismiss also remembers the id so later
/// `noteLiveSubagent` is ignored until `clearDismissedSubagentIds`.
/// Settled dismiss skips remember: that list only matters mid-turn
/// for a live slot, and `startPrompt` already clears it). Does not
/// `stopStream` for a Monitor or Subagent. Unknown / Process-idle
/// ids are no-ops. Not Claude TaskStop: one-shot `claude -p` has no
/// mid-turn stdin / long-lived session.
pub fn stopBackground(model: *Model, fx: *Effects, row_id: u32) void {
    if (row_id == process_row_id) {
        if (!model.is_streaming()) return;
        close(model);
        turn_stream.stopStream(model, fx);
        return;
    }
    if (monitorIndex(model, row_id)) |index| {
        close(model);
        dismissMonitor(model, index);
        return;
    }
    const sub_index = subagentIndex(model, row_id) orelse return;
    close(model);
    dismissSubagent(model, sub_index);
}

/// Faku-side bulk dismiss of settled Background leftovers for the
/// selected session. Removes every visible settled Monitor and
/// Subagent slot (heap logs freed, right-panel selection remapped;
/// settled Subagent skips remember-dismissed-id, same as per-row
/// Dismiss). Clears the cap-1 Process settle with `clearSettled`
/// when that slot belongs to the selected session. Does not stop
/// a live stream, does not dismiss live Monitor / Subagent
/// (`settled == .none`), and does not `stopStream`. Other sessions'
/// leftovers stay. Closes the Environment Summary dropdown.
/// Not Claude TaskStop / daemon `refreshBackgroundWork`.
pub fn dismissSettledBackground(model: *Model) void {
    close(model);
    const session_id = model.selected;
    if (session_id == 0) return;

    var i: u32 = 0;
    while (i < model.background_monitor_count) {
        if (visibleSettledMonitor(model, i)) {
            dismissMonitor(model, i);
            continue;
        }
        i += 1;
    }
    i = 0;
    while (i < model.background_subagent_count) {
        if (visibleSettledSubagent(model, i)) {
            dismissSubagent(model, i);
            continue;
        }
        i += 1;
    }

    if (model.background_settled_session == session_id) {
        if (!model.is_streaming() and model.right_panel_background_row_id == process_row_id) {
            model.right_panel_background_row_id = 0;
        }
        clearSettled(model);
    }
}

/// Monitor array index for `row_id`, live or settled. Null when
/// unknown / not a Monitor key. Idle after the turn is fine.
fn monitorIndex(model: *const Model, row_id: u32) ?u32 {
    if (row_id < monitor_row_id_first) return null;
    const idx = row_id - monitor_row_id_first;
    if (idx >= model.background_monitor_count) return null;
    return idx;
}

/// Compact-remove a Monitor slot (live or settled), free its heap
/// last-window, and remap right-panel selection.
fn removeMonitorAt(model: *Model, index: u32) void {
    if (index >= model.background_monitor_count) return;
    const old_count = model.background_monitor_count;
    const removed_id = monitor_row_id_first + index;
    remapBackgroundSelectionAfterMonitorRemove(model, removed_id, old_count);
    releaseLog(&model.background_monitors[index].log);
    var j = index;
    while (j + 1 < model.background_monitor_count) : (j += 1) {
        model.background_monitors[j] = model.background_monitors[j + 1];
    }
    model.background_monitor_count -= 1;
    model.background_monitors[model.background_monitor_count] = .{};
}

/// Drop the oldest settled Monitor (array order) to make room for
/// a new live row. Returns false when there is no settled slot.
fn trimOldestSettledMonitor(model: *Model) bool {
    var i: u32 = 0;
    while (i < model.background_monitor_count) : (i += 1) {
        if (model.background_monitors[i].settled == .none) continue;
        removeMonitorAt(model, i);
        return true;
    }
    return false;
}

/// Faku-side Monitor dismiss: free the heap last-window, compact
/// remaining slots, and clear or remap right-panel selection so a
/// selected stopped row becomes empty ("No background work"). Live
/// or settled. Does not cancel the Process / stream.
fn dismissMonitor(model: *Model, index: u32) void {
    removeMonitorAt(model, index);
}

fn remapBackgroundSelectionAfterMonitorRemove(model: *Model, removed_id: u32, old_count: u32) void {
    const selected = model.right_panel_background_row_id;
    if (selected == removed_id) {
        model.right_panel_background_row_id = 0;
        return;
    }
    if (old_count == 0) return;
    const last_id = monitor_row_id_first + old_count - 1;
    if (selected > removed_id and selected <= last_id) {
        model.right_panel_background_row_id -= 1;
    }
}

/// Subagent array index for `row_id`, live or settled. Null when
/// unknown / not a Subagent key. Monitor ids start at
/// `monitor_row_id_first` and must not match here. Idle after the
/// turn is fine.
fn subagentIndex(model: *const Model, row_id: u32) ?u32 {
    if (row_id < subagent_row_id_first or row_id >= monitor_row_id_first) return null;
    const idx = row_id - subagent_row_id_first;
    if (idx >= model.background_subagent_count) return null;
    return idx;
}

fn isDismissedSubagent(model: *const Model, parent_id: []const u8) bool {
    var i: u32 = 0;
    while (i < model.background_dismissed_subagent_count) : (i += 1) {
        if (std.mem.eql(u8, model.background_dismissed_subagents[i].id(), parent_id)) return true;
    }
    return false;
}

/// Remember a dismissed Subagent id so later `noteLiveSubagent`
/// cannot resurrect it this turn. Cap `max_live_subagents`; when
/// full, drop the oldest dismissed id.
fn rememberDismissedSubagent(model: *Model, parent_id: []const u8) void {
    if (parent_id.len == 0) return;
    if (isDismissedSubagent(model, parent_id)) return;
    if (model.background_dismissed_subagent_count >= max_live_subagents) {
        var i: u32 = 0;
        while (i + 1 < model.background_dismissed_subagent_count) : (i += 1) {
            model.background_dismissed_subagents[i] = model.background_dismissed_subagents[i + 1];
        }
        model.background_dismissed_subagent_count -= 1;
        model.background_dismissed_subagents[model.background_dismissed_subagent_count] = .{};
    }
    const slot = &model.background_dismissed_subagents[model.background_dismissed_subagent_count];
    main.writeFixed(&slot.storage, &slot.len, parent_id);
    model.background_dismissed_subagent_count += 1;
}

/// Compact-remove a Subagent slot (live or settled), free its
/// heap last-window, and remap right-panel selection. Does not
/// remember a dismissed id.
fn removeSubagentAt(model: *Model, index: u32) void {
    if (index >= model.background_subagent_count) return;
    const old_count = model.background_subagent_count;
    const removed_id = subagent_row_id_first + index;
    remapBackgroundSelectionAfterSubagentRemove(model, removed_id, old_count);
    releaseLog(&model.background_subagents[index].log);
    var j = index;
    while (j + 1 < model.background_subagent_count) : (j += 1) {
        model.background_subagents[j] = model.background_subagents[j + 1];
    }
    model.background_subagent_count -= 1;
    model.background_subagents[model.background_subagent_count] = .{};
}

/// Drop the oldest settled Subagent (array order) to make room
/// for a new live row. Frees that slot's heap log. Returns false
/// when there is no settled slot.
fn trimOldestSettledSubagent(model: *Model) bool {
    var i: u32 = 0;
    while (i < model.background_subagent_count) : (i += 1) {
        if (model.background_subagents[i].settled == .none) continue;
        removeSubagentAt(model, i);
        return true;
    }
    return false;
}

/// Faku-side Subagent dismiss: free the heap last-window, compact
/// remaining slots, and clear or remap right-panel selection so a
/// selected stopped row becomes empty ("No background work"). Live
/// dismiss remembers the id so later `noteLiveSubagent` is ignored
/// until `clearDismissedSubagentIds`. Settled dismiss skips
/// remember — that list only gates mid-turn live re-register, and
/// `startPrompt` already clears it. Does not cancel the Process /
/// stream and does not touch Monitor rows.
fn dismissSubagent(model: *Model, index: u32) void {
    if (index >= model.background_subagent_count) return;
    if (model.background_subagents[index].settled == .none) {
        rememberDismissedSubagent(model, model.background_subagents[index].parentId());
    }
    removeSubagentAt(model, index);
}

fn remapBackgroundSelectionAfterSubagentRemove(model: *Model, removed_id: u32, old_count: u32) void {
    const selected = model.right_panel_background_row_id;
    if (selected == removed_id) {
        model.right_panel_background_row_id = 0;
        return;
    }
    if (old_count == 0) return;
    const last_id = subagent_row_id_first + old_count - 1;
    if (selected > removed_id and selected <= last_id) {
        model.right_panel_background_row_id -= 1;
    }
}

/// Visible registry row for `row_id`, or null when id is 0 / unknown.
/// Slices inside the row point at model storage or string literals.
pub fn findBackgroundRow(model: *const Model, row_id: u32) ?BackgroundRow {
    if (row_id == 0) return null;
    var buf: [max_background_rows]BackgroundRow = undefined;
    const rows = fillBackgroundRows(model, &buf);
    for (rows) |row| {
        if (row.id == row_id) return row;
    }
    return null;
}

pub fn selectedBackgroundRow(model: *const Model) ?BackgroundRow {
    return findBackgroundRow(model, model.right_panel_background_row_id);
}

/// Live Running / Monitoring, or settled Completed / Stopped / Failed.
/// Empty when there is no selected visible row.
pub fn backgroundWorkStatus(row: BackgroundRow) []const u8 {
    if (row.has_status) return row.settled_status;
    if (!row.live) return "";
    return switch (row.kind) {
        .monitor => live_monitoring_label,
        .process, .subagent => live_running_label,
    };
}

/// Right-panel Background body. Monitor and Subagent rows return
/// the CSI-stripped render cache (newlines kept), live or settled.
/// Does not `stripAnsi` on the Native view bind. Process stays
/// empty so the pane shows "No output".
pub fn backgroundWorkOutput(model: *const Model) []const u8 {
    const row = selectedBackgroundRow(model) orelse return "";
    switch (row.kind) {
        .monitor => {
            const idx = row.id - monitor_row_id_first;
            if (idx >= model.background_monitor_count) return "";
            return model.background_monitors[idx].log.rendered();
        },
        .subagent => {
            const idx = row.id - subagent_row_id_first;
            if (idx >= model.background_subagent_count) return "";
            return model.background_subagents[idx].log.rendered();
        },
        .process => return "",
    }
}

/// Close the popover and open the right-panel Background surface on
/// `row_id`. Unknown / 0 is a no-op (dropdown stays open), same
/// spirit as Monitor output ignoring Bash / unknown ids.
pub fn openBackgroundWork(model: *Model, fx: *Effects, row_id: u32) void {
    if (findBackgroundRow(model, row_id) == null) return;
    close(model);
    right_panel.selectBackground(model, fx, row_id);
    _ = refreshBackgroundOutputCache(model);
}

fn refreshPanelCache(model: *Model) void {
    _ = refreshBackgroundOutputCache(model);
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
    try std.testing.expectEqualStrings(process_stop_label, rows[0].stop_label);
    try std.testing.expect(!rows[0].has_status);
    try std.testing.expectEqualStrings("", rows[0].settled_status);
    try std.testing.expect(!rows[0].has_detail);
    try std.testing.expectEqualStrings("", rows[0].detail);
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
    try std.testing.expectEqualStrings("", rows[0].stop_label);
    try std.testing.expect(rows[0].has_status);
    try std.testing.expectEqualStrings(status, rows[0].settled_status);
    try std.testing.expect(!rows[0].has_detail);
    try std.testing.expectEqualStrings("", rows[0].detail);
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

    stopBackground(&model, &fx, process_row_id);
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
    main.update(&model, .{ .environment_stop_background = process_row_id }, &fx);
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

    stopBackground(&model, &fx, process_row_id);
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

    main.update(&model, .{ .environment_stop_background = process_row_id }, &fx);
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
    try std.testing.expect(rows[1].can_stop);
    try std.testing.expectEqualStrings(subagent_stop_label, rows[1].stop_label);
    try std.testing.expect(!rows[1].has_status);
    try std.testing.expect(!rows[1].has_detail);
    try std.testing.expectEqualStrings("", rows[1].detail);
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

test "finishStream and stopStream settle live Subagent rows" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    const id = model.addSession("env settle subagent", .claude);
    model.selected = id;
    model.phase = .streaming;
    model.streaming_session = id;
    noteLiveSubagent(&model, "toolu_clear_1");
    try std.testing.expectEqual(id, model.background_subagents[0].session_id);
    try std.testing.expectEqual(SettledStatus.none, model.background_subagents[0].settled);
    var buf: [max_background_rows]BackgroundRow = undefined;
    try std.testing.expectEqual(@as(usize, 2), fillBackgroundRows(&model, &buf).len);

    turn_stream.finishStream(&model, &fx, true);
    try std.testing.expectEqual(@as(u32, 1), model.background_subagent_count);
    try std.testing.expectEqual(SettledStatus.completed, model.background_subagents[0].settled);
    try std.testing.expectEqual(id, model.background_subagents[0].session_id);
    var rows = fillBackgroundRows(&model, &buf);
    try std.testing.expectEqual(@as(usize, 2), rows.len);
    try std.testing.expectEqual(BackgroundKind.process, rows[0].kind);
    try std.testing.expectEqualStrings(settled_completed_label, rows[0].settled_status);
    try std.testing.expectEqual(BackgroundKind.subagent, rows[1].kind);
    try std.testing.expect(!rows[1].live);
    try std.testing.expect(rows[1].can_stop);
    try std.testing.expectEqualStrings(subagent_dismiss_label, rows[1].stop_label);
    try std.testing.expectEqualStrings(settled_completed_label, rows[1].settled_status);

    model.phase = .streaming;
    model.streaming_session = id;
    if (model.sessionById(id)) |session| session.busy = true;
    noteLiveSubagent(&model, "toolu_clear_2");
    try std.testing.expectEqual(@as(u32, 2), model.background_subagent_count);
    rows = fillBackgroundRows(&model, &buf);
    try std.testing.expectEqual(@as(usize, 3), rows.len);
    try std.testing.expect(rows[1].live);
    try std.testing.expect(rows[1].can_stop);
    try std.testing.expect(!rows[2].live);
    turn_stream.stopStream(&model, &fx);
    try std.testing.expectEqual(@as(u32, 2), model.background_subagent_count);
    try std.testing.expectEqual(SettledStatus.stopped, model.background_subagents[1].settled);
    try std.testing.expectEqual(SettledStatus.completed, model.background_subagents[0].settled);
    rows = fillBackgroundRows(&model, &buf);
    try std.testing.expectEqual(@as(usize, 3), rows.len);
    try std.testing.expectEqualStrings(settled_stopped_label, rows[0].settled_status);
    try std.testing.expect(rows[1].can_stop);
    try std.testing.expectEqualStrings(subagent_dismiss_label, rows[1].stop_label);
    try std.testing.expect(rows[2].can_stop);
    try std.testing.expectEqualStrings(subagent_dismiss_label, rows[2].stop_label);
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
    try std.testing.expect(rows[1].can_stop);
    try std.testing.expectEqualStrings(monitor_stop_label, rows[1].stop_label);
    try std.testing.expect(!rows[1].has_status);
    try std.testing.expect(!rows[1].has_detail);
    try std.testing.expectEqualStrings("", rows[1].detail);
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
    try std.testing.expect(rows[1].can_stop);
    try std.testing.expectEqualStrings(monitor_stop_label, rows[1].stop_label);
    try std.testing.expect(!rows[1].has_detail);
    try std.testing.expectEqual(BackgroundKind.subagent, rows[2].kind);
    try std.testing.expectEqual(subagent_row_id_first, rows[2].id);
    try std.testing.expect(rows[2].can_stop);
    try std.testing.expectEqualStrings(subagent_stop_label, rows[2].stop_label);
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

test "finishStream and stopStream settle live Monitor rows and keep the log" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    defer clearLiveMonitors(&model);
    const id = model.addSession("env settle monitor", .claude);
    model.selected = id;
    model.phase = .streaming;
    model.streaming_session = id;
    noteLiveMonitor(&model, "toolu_mon_clear_1");
    appendLiveMonitorOutput(&model, "toolu_mon_clear_1", "line from monitor");
    try std.testing.expectEqual(id, model.background_monitors[0].session_id);
    var buf: [max_background_rows]BackgroundRow = undefined;
    const live_rows = fillBackgroundRows(&model, &buf);
    try std.testing.expectEqual(@as(usize, 2), live_rows.len);
    try std.testing.expect(live_rows[1].has_detail);
    try std.testing.expectEqualStrings("line from monitor", live_rows[1].detail);

    turn_stream.finishStream(&model, &fx, true);
    try std.testing.expectEqual(@as(u32, 1), model.background_monitor_count);
    try std.testing.expectEqual(SettledStatus.completed, model.background_monitors[0].settled);
    try std.testing.expectEqualStrings("line from monitor", model.background_monitors[0].output());
    var rows = fillBackgroundRows(&model, &buf);
    try std.testing.expectEqual(@as(usize, 2), rows.len);
    try std.testing.expectEqual(BackgroundKind.process, rows[0].kind);
    try std.testing.expectEqualStrings(settled_completed_label, rows[0].settled_status);
    try std.testing.expectEqual(BackgroundKind.monitor, rows[1].kind);
    try std.testing.expect(!rows[1].live);
    try std.testing.expect(rows[1].can_stop);
    try std.testing.expectEqualStrings(monitor_dismiss_label, rows[1].stop_label);
    try std.testing.expectEqualStrings(settled_completed_label, rows[1].settled_status);
    try std.testing.expectEqualStrings("line from monitor", rows[1].detail);
    model.right_panel_background_row_id = monitor_row_id_first;
    try std.testing.expectEqualStrings("line from monitor", backgroundWorkOutput(&model));
    try std.testing.expectEqualStrings(settled_completed_label, backgroundWorkStatus(selectedBackgroundRow(&model).?));

    model.phase = .streaming;
    model.streaming_session = id;
    if (model.sessionById(id)) |session| session.busy = true;
    noteLiveMonitor(&model, "toolu_mon_clear_2");
    try std.testing.expectEqual(@as(u32, 2), model.background_monitor_count);
    turn_stream.stopStream(&model, &fx);
    try std.testing.expectEqual(@as(u32, 2), model.background_monitor_count);
    try std.testing.expectEqual(SettledStatus.stopped, model.background_monitors[1].settled);
    try std.testing.expectEqual(SettledStatus.completed, model.background_monitors[0].settled);
    try std.testing.expectEqualStrings("line from monitor", model.background_monitors[0].output());
    rows = fillBackgroundRows(&model, &buf);
    try std.testing.expectEqual(@as(usize, 3), rows.len);
    try std.testing.expectEqualStrings(settled_stopped_label, rows[0].settled_status);
    try std.testing.expect(rows[1].can_stop);
    try std.testing.expectEqualStrings(monitor_dismiss_label, rows[1].stop_label);
    try std.testing.expect(rows[2].can_stop);
    try std.testing.expectEqualStrings(monitor_dismiss_label, rows[2].stop_label);
}

test "startPrompt keeps settled Monitor log; a new live Monitor can appear alongside" {
    const prompt_spawn = @import("spawn.zig");
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    defer clearLiveMonitors(&model);
    defer clearLiveSubagents(&model);
    const id = model.addSession("env send keeps monitor", .claude);
    model.selected = id;
    model.phase = .streaming;
    model.streaming_session = id;
    noteLiveMonitor(&model, "toolu_mon_send_1");
    appendLiveMonitorOutput(&model, "toolu_mon_send_1", "preview that must stay");
    noteLiveSubagent(&model, "toolu_agent_send_1");
    appendLiveSubagentOutput(&model, "toolu_agent_send_1", "subagent that must stay");
    turn_stream.finishStream(&model, &fx, true);
    try std.testing.expectEqual(@as(u32, 1), model.background_monitor_count);
    try std.testing.expectEqual(SettledStatus.completed, model.background_monitors[0].settled);
    try std.testing.expectEqualStrings("preview that must stay", model.background_monitors[0].output());
    try std.testing.expectEqual(@as(u32, 1), model.background_subagent_count);
    try std.testing.expectEqual(SettledStatus.completed, model.background_subagents[0].settled);
    try std.testing.expectEqualStrings("subagent that must stay", model.background_subagents[0].output());

    prompt_spawn.startPrompt(&model, &fx, id, "next turn");
    try std.testing.expectEqual(@as(u32, 1), model.background_monitor_count);
    try std.testing.expectEqualStrings("preview that must stay", model.background_monitors[0].output());
    try std.testing.expectEqual(SettledStatus.completed, model.background_monitors[0].settled);
    try std.testing.expectEqual(@as(u32, 1), model.background_subagent_count);
    try std.testing.expectEqual(SettledStatus.completed, model.background_subagents[0].settled);
    try std.testing.expectEqualStrings("subagent that must stay", model.background_subagents[0].output());
    try std.testing.expectEqual(@as(u32, 0), model.background_dismissed_subagent_count);
    try std.testing.expect(model.is_streaming());

    noteLiveMonitor(&model, "toolu_mon_send_2");
    try std.testing.expectEqual(@as(u32, 2), model.background_monitor_count);
    try std.testing.expectEqual(SettledStatus.none, model.background_monitors[1].settled);
    try std.testing.expectEqual(SettledStatus.completed, model.background_monitors[0].settled);
    var buf: [max_background_rows]BackgroundRow = undefined;
    const rows = fillBackgroundRows(&model, &buf);
    try std.testing.expectEqual(@as(usize, 4), rows.len);
    try std.testing.expectEqual(BackgroundKind.process, rows[0].kind);
    try std.testing.expect(rows[0].live);
    try std.testing.expectEqual(BackgroundKind.monitor, rows[1].kind);
    try std.testing.expect(rows[1].live);
    try std.testing.expect(rows[1].can_stop);
    try std.testing.expectEqual(BackgroundKind.monitor, rows[2].kind);
    try std.testing.expect(!rows[2].live);
    try std.testing.expect(rows[2].can_stop);
    try std.testing.expectEqualStrings(monitor_dismiss_label, rows[2].stop_label);
    try std.testing.expectEqualStrings("preview that must stay", rows[2].detail);
    try std.testing.expectEqual(BackgroundKind.subagent, rows[3].kind);
    try std.testing.expect(!rows[3].live);
    try std.testing.expect(rows[3].can_stop);
    try std.testing.expectEqualStrings(subagent_dismiss_label, rows[3].stop_label);
    try std.testing.expectEqualStrings("subagent that must stay", rows[3].detail);
}

test "appendLiveMonitorOutput fills preview; unknown id and empty text are no-ops" {
    var model = Model{};
    defer clearLiveMonitors(&model);
    const id = model.addSession("env monitor output", .claude);
    model.selected = id;
    model.phase = .streaming;
    model.streaming_session = id;

    appendLiveMonitorOutput(&model, "toolu_mon_1", "before row");
    try std.testing.expectEqual(@as(u32, 0), model.background_monitor_count);
    try expectLiveProcessRow(&model);

    noteLiveMonitor(&model, "toolu_mon_1");
    var buf: [max_background_rows]BackgroundRow = undefined;
    var rows = fillBackgroundRows(&model, &buf);
    try std.testing.expectEqual(@as(usize, 2), rows.len);
    try std.testing.expect(!rows[1].has_detail);
    try std.testing.expectEqualStrings("", rows[1].detail);
    try std.testing.expect(!rows[1].has_status);
    try std.testing.expectEqualStrings("", rows[1].settled_status);

    appendLiveMonitorOutput(&model, "", "ignored");
    appendLiveMonitorOutput(&model, "toolu_mon_1", "");
    appendLiveMonitorOutput(&model, "toolu_unknown", "no row");
    rows = fillBackgroundRows(&model, &buf);
    try std.testing.expectEqual(@as(usize, 2), rows.len);
    try std.testing.expect(!rows[1].has_detail);
    try std.testing.expectEqual(@as(u32, 1), model.background_monitor_count);

    appendLiveMonitorOutput(&model, "toolu_mon_1", "first\nline");
    appendLiveMonitorOutput(&model, "toolu_mon_1", " first\nline");
    rows = fillBackgroundRows(&model, &buf);
    try std.testing.expect(rows[1].has_detail);
    try std.testing.expectEqualStrings("first line first line", rows[1].detail);
    try std.testing.expect(std.mem.indexOf(u8, rows[1].detail, "\n") == null);
    try std.testing.expect(std.mem.indexOf(u8, rows[1].detail, "first\nline") == null);
    try std.testing.expectEqualStrings("first\nline first\nline", model.background_monitors[0].output());
    try std.testing.expect(!rows[1].has_status);
    try std.testing.expectEqualStrings(kind_monitor_label, rows[1].title);
    try std.testing.expect(!rows[0].has_detail);
    model.right_panel_background_row_id = monitor_row_id_first;
    refreshPanelCache(&model);
    try std.testing.expectEqualStrings("first\nline first\nline", backgroundWorkOutput(&model));
    try std.testing.expect(backgroundWorkOutput(&model).len > rows[1].detail.len or std.mem.indexOf(u8, backgroundWorkOutput(&model), "\n") != null);

    noteLiveSubagent(&model, "toolu_agent_1");
    rows = fillBackgroundRows(&model, &buf);
    try std.testing.expectEqual(@as(usize, 3), rows.len);
    try std.testing.expect(!rows[2].has_detail);
    try std.testing.expectEqualStrings("", rows[2].detail);
}

test "appendLiveMonitorOutput drains from the front at the 512KB cap" {
    var model = Model{};
    defer clearLiveMonitors(&model);
    const id = model.addSession("env monitor overflow", .claude);
    model.selected = id;
    model.phase = .streaming;
    model.streaming_session = id;
    noteLiveMonitor(&model, "toolu_mon_cap");

    appendLiveMonitorOutput(&model, "toolu_mon_cap", "é");
    const chunk = "x" ** 4096;
    while (model.background_monitors[0].output().len + chunk.len <= max_monitor_output) {
        appendLiveMonitorOutput(&model, "toolu_mon_cap", chunk);
    }
    const remain = max_monitor_output - model.background_monitors[0].output().len;
    if (remain > 0) {
        appendLiveMonitorOutput(&model, "toolu_mon_cap", chunk[0..remain]);
    }
    try std.testing.expectEqual(max_monitor_output, model.background_monitors[0].output().len);
    try std.testing.expect(std.mem.startsWith(u8, model.background_monitors[0].output(), "é"));

    appendLiveMonitorOutput(&model, "toolu_mon_cap", "y");
    const out = model.background_monitors[0].output();
    try std.testing.expect(out.len <= max_monitor_output);
    try std.testing.expect(out.len > 0);
    try std.testing.expect(out[0] != 0xA9);
    try std.testing.expect(out[out.len - 1] == 'y');
    try std.testing.expect(!std.mem.startsWith(u8, out, "é"));
}

test "Monitor stored log keeps newlines and CSI; Summary is one line; panel strips ANSI" {
    var model = Model{};
    defer clearLiveMonitors(&model);
    const id = model.addSession("env monitor ansi", .claude);
    model.selected = id;
    model.phase = .streaming;
    model.streaming_session = id;
    noteLiveMonitor(&model, "toolu_mon_ansi");
    appendLiveMonitorOutput(&model, "toolu_mon_ansi", "\x1b[31mred\x1b[0m\nnext");

    var buf: [max_background_rows]BackgroundRow = undefined;
    const rows = fillBackgroundRows(&model, &buf);
    try std.testing.expectEqualStrings("red next", rows[1].detail);
    try std.testing.expect(std.mem.indexOf(u8, rows[1].detail, "\x1b") == null);
    try std.testing.expect(std.mem.indexOf(u8, rows[1].detail, "\n") == null);
    try std.testing.expectEqualStrings("\x1b[31mred\x1b[0m\nnext", model.background_monitors[0].output());

    model.right_panel_background_row_id = monitor_row_id_first;
    refreshPanelCache(&model);
    const panel = backgroundWorkOutput(&model);
    try std.testing.expectEqualStrings("red\nnext", panel);
    try std.testing.expect(std.mem.indexOf(u8, panel, "\x1b") == null);
    try std.testing.expect(std.mem.indexOf(u8, panel, "\n") != null);
    try std.testing.expect(panel.len > rows[1].detail.len or std.mem.eql(u8, panel, "red\nnext"));
}

test "Monitor panel log is larger than the one-line Summary preview" {
    var model = Model{};
    defer clearLiveMonitors(&model);
    const id = model.addSession("env monitor preview cap", .claude);
    model.selected = id;
    model.phase = .streaming;
    model.streaming_session = id;
    noteLiveMonitor(&model, "toolu_mon_preview");
    const chunk = "x" ** 200;
    appendLiveMonitorOutput(&model, "toolu_mon_preview", chunk);
    appendLiveMonitorOutput(&model, "toolu_mon_preview", "\n");
    appendLiveMonitorOutput(&model, "toolu_mon_preview", chunk);
    appendLiveMonitorOutput(&model, "toolu_mon_preview", chunk);
    appendLiveMonitorOutput(&model, "toolu_mon_preview", chunk);

    var buf: [max_background_rows]BackgroundRow = undefined;
    const rows = fillBackgroundRows(&model, &buf);
    try std.testing.expect(rows[1].has_detail);
    try std.testing.expect(rows[1].detail.len <= max_monitor_preview);
    try std.testing.expect(std.mem.indexOf(u8, rows[1].detail, "\n") == null);
    try std.testing.expect(model.background_monitors[0].output().len > rows[1].detail.len);
    try std.testing.expect(std.mem.indexOf(u8, model.background_monitors[0].output(), "\n") != null);

    model.right_panel_background_row_id = monitor_row_id_first;
    refreshPanelCache(&model);
    const panel = backgroundWorkOutput(&model);
    try std.testing.expect(panel.len > rows[1].detail.len);
    try std.testing.expect(std.mem.indexOf(u8, panel, "\n") != null);
}

test "appendLiveSubagentOutput fills preview; unknown id and empty text are no-ops" {
    var model = Model{};
    defer clearLiveSubagents(&model);
    const id = model.addSession("env subagent output", .claude);
    model.selected = id;
    model.phase = .streaming;
    model.streaming_session = id;

    appendLiveSubagentOutput(&model, "toolu_agent_1", "before row");
    try std.testing.expectEqual(@as(u32, 0), model.background_subagent_count);
    try expectLiveProcessRow(&model);

    noteLiveSubagent(&model, "toolu_agent_1");
    var buf: [max_background_rows]BackgroundRow = undefined;
    var rows = fillBackgroundRows(&model, &buf);
    try std.testing.expectEqual(@as(usize, 2), rows.len);
    try std.testing.expect(!rows[1].has_detail);
    try std.testing.expectEqualStrings("", rows[1].detail);
    try std.testing.expect(!rows[1].has_status);
    try std.testing.expectEqualStrings("", rows[1].settled_status);

    appendLiveSubagentOutput(&model, "", "ignored");
    appendLiveSubagentOutput(&model, "toolu_agent_1", "");
    appendLiveSubagentOutput(&model, "toolu_unknown", "no row");
    rows = fillBackgroundRows(&model, &buf);
    try std.testing.expectEqual(@as(usize, 2), rows.len);
    try std.testing.expect(!rows[1].has_detail);
    try std.testing.expectEqual(@as(u32, 1), model.background_subagent_count);

    appendLiveSubagentOutput(&model, "toolu_agent_1", "first\nline");
    appendLiveSubagentOutput(&model, "toolu_agent_1", " first\nline");
    rows = fillBackgroundRows(&model, &buf);
    try std.testing.expect(rows[1].has_detail);
    try std.testing.expectEqualStrings("first line first line", rows[1].detail);
    try std.testing.expect(std.mem.indexOf(u8, rows[1].detail, "\n") == null);
    try std.testing.expectEqualStrings("first\nline first\nline", model.background_subagents[0].output());
    try std.testing.expect(!rows[1].has_status);
    try std.testing.expectEqualStrings(kind_subagent_label, rows[1].title);
    try std.testing.expect(!rows[0].has_detail);
    model.right_panel_background_row_id = subagent_row_id_first;
    refreshPanelCache(&model);
    try std.testing.expectEqualStrings("first\nline first\nline", backgroundWorkOutput(&model));
    try std.testing.expect(backgroundWorkOutput(&model).len > rows[1].detail.len or std.mem.indexOf(u8, backgroundWorkOutput(&model), "\n") != null);

    noteLiveMonitor(&model, "toolu_mon_1");
    rows = fillBackgroundRows(&model, &buf);
    try std.testing.expectEqual(@as(usize, 3), rows.len);
    try std.testing.expectEqual(BackgroundKind.monitor, rows[1].kind);
    try std.testing.expect(!rows[1].has_detail);
    try std.testing.expectEqual(BackgroundKind.subagent, rows[2].kind);
    try std.testing.expect(rows[2].has_detail);
}

test "appendLiveSubagentOutput drains from the front at the 512KB cap" {
    var model = Model{};
    defer clearLiveSubagents(&model);
    const id = model.addSession("env subagent overflow", .claude);
    model.selected = id;
    model.phase = .streaming;
    model.streaming_session = id;
    noteLiveSubagent(&model, "toolu_agent_cap");

    appendLiveSubagentOutput(&model, "toolu_agent_cap", "é");
    const chunk = "x" ** 4096;
    while (model.background_subagents[0].output().len + chunk.len <= max_subagent_output) {
        appendLiveSubagentOutput(&model, "toolu_agent_cap", chunk);
    }
    const remain = max_subagent_output - model.background_subagents[0].output().len;
    if (remain > 0) {
        appendLiveSubagentOutput(&model, "toolu_agent_cap", chunk[0..remain]);
    }
    try std.testing.expectEqual(max_subagent_output, model.background_subagents[0].output().len);
    try std.testing.expect(std.mem.startsWith(u8, model.background_subagents[0].output(), "é"));

    appendLiveSubagentOutput(&model, "toolu_agent_cap", "y");
    const out = model.background_subagents[0].output();
    try std.testing.expect(out.len <= max_subagent_output);
    try std.testing.expect(out.len > 0);
    try std.testing.expect(out[0] != 0xA9);
    try std.testing.expect(out[out.len - 1] == 'y');
    try std.testing.expect(!std.mem.startsWith(u8, out, "é"));
}

test "Subagent stored log keeps newlines and CSI; Summary is one line; panel strips ANSI" {
    var model = Model{};
    defer clearLiveSubagents(&model);
    const id = model.addSession("env subagent ansi", .claude);
    model.selected = id;
    model.phase = .streaming;
    model.streaming_session = id;
    noteLiveSubagent(&model, "toolu_agent_ansi");
    appendLiveSubagentOutput(&model, "toolu_agent_ansi", "\x1b[31mred\x1b[0m\nnext");

    var buf: [max_background_rows]BackgroundRow = undefined;
    const rows = fillBackgroundRows(&model, &buf);
    try std.testing.expectEqualStrings("red next", rows[1].detail);
    try std.testing.expect(std.mem.indexOf(u8, rows[1].detail, "\x1b") == null);
    try std.testing.expect(std.mem.indexOf(u8, rows[1].detail, "\n") == null);
    try std.testing.expectEqualStrings("\x1b[31mred\x1b[0m\nnext", model.background_subagents[0].output());

    model.right_panel_background_row_id = subagent_row_id_first;
    refreshPanelCache(&model);
    const panel = backgroundWorkOutput(&model);
    try std.testing.expectEqualStrings("red\nnext", panel);
    try std.testing.expect(std.mem.indexOf(u8, panel, "\x1b") == null);
    try std.testing.expect(std.mem.indexOf(u8, panel, "\n") != null);
}

test "openBackgroundWork opens Process row; unknown id is a no-op; dropdown closes" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    const id = model.addSession("env open background", .fx);
    model.selected = id;
    model.phase = .streaming;
    model.streaming_session = id;
    model.environment_summary_open = true;
    try expectLiveProcessRow(&model);

    openBackgroundWork(&model, &fx, 99);
    try std.testing.expect(model.environment_summary_open);
    try std.testing.expect(!model.right_panel_open);
    try std.testing.expectEqual(right_panel.Tab.files, model.right_panel_tab);
    try std.testing.expectEqual(@as(u32, 0), model.right_panel_background_row_id);

    openBackgroundWork(&model, &fx, 0);
    try std.testing.expect(model.environment_summary_open);
    try std.testing.expect(!model.right_panel_open);

    openBackgroundWork(&model, &fx, process_row_id);
    try std.testing.expect(!model.environment_summary_open);
    try std.testing.expect(model.right_panel_open);
    try std.testing.expectEqual(right_panel.Tab.background, model.right_panel_tab);
    try std.testing.expectEqual(process_row_id, model.right_panel_background_row_id);
    try std.testing.expectEqual(@as(f32, 460), model.right_panel_width);
    const row = selectedBackgroundRow(&model).?;
    try std.testing.expectEqual(BackgroundKind.process, row.kind);
    try std.testing.expectEqualStrings(process_row_label, row.title);
    try std.testing.expectEqualStrings(live_running_label, backgroundWorkStatus(row));
    try std.testing.expectEqualStrings("", backgroundWorkOutput(&model));
}

test "openBackgroundWork shows Monitor log; Files and Diff still open; gone row is empty" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    defer clearLiveMonitors(&model);
    const id = model.addSession("env background monitor panel", .claude);
    model.selected = id;
    model.phase = .streaming;
    model.streaming_session = id;
    noteLiveMonitor(&model, "toolu_mon_1");
    appendLiveMonitorOutput(&model, "toolu_mon_1", "line from monitor");
    model.environment_summary_open = true;

    openBackgroundWork(&model, &fx, monitor_row_id_first);
    try std.testing.expect(!model.environment_summary_open);
    try std.testing.expectEqual(right_panel.Tab.background, model.right_panel_tab);
    try std.testing.expectEqual(monitor_row_id_first, model.right_panel_background_row_id);
    const mon = selectedBackgroundRow(&model).?;
    try std.testing.expectEqual(BackgroundKind.monitor, mon.kind);
    try std.testing.expectEqualStrings(kind_monitor_label, mon.title);
    try std.testing.expectEqualStrings(live_monitoring_label, backgroundWorkStatus(mon));
    try std.testing.expectEqualStrings("line from monitor", backgroundWorkOutput(&model));

    right_panel.selectFiles(&model, &fx);
    try std.testing.expectEqual(right_panel.Tab.files, model.right_panel_tab);
    try std.testing.expectEqual(monitor_row_id_first, model.right_panel_background_row_id);
    right_panel.selectDiff(&model, &fx);
    try std.testing.expectEqual(right_panel.Tab.diff, model.right_panel_tab);
    right_panel.selectBackground(&model, &fx, 0);
    try std.testing.expectEqual(right_panel.Tab.background, model.right_panel_tab);
    try std.testing.expectEqual(monitor_row_id_first, model.right_panel_background_row_id);

    model.phase = .idle;
    model.streaming_session = 0;
    settle(&model, id, .completed);
    try std.testing.expect(selectedBackgroundRow(&model) == null);
    try std.testing.expectEqual(monitor_row_id_first, model.right_panel_background_row_id);
    try std.testing.expectEqual(right_panel.Tab.background, model.right_panel_tab);
}

test "openBackgroundWork Subagent row is Running with empty output" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    const id = model.addSession("env background subagent panel", .claude);
    model.selected = id;
    model.phase = .streaming;
    model.streaming_session = id;
    noteLiveSubagent(&model, "toolu_agent_1");
    model.environment_summary_open = true;

    openBackgroundWork(&model, &fx, subagent_row_id_first);
    try std.testing.expect(!model.environment_summary_open);
    try std.testing.expectEqual(right_panel.Tab.background, model.right_panel_tab);
    const row = selectedBackgroundRow(&model).?;
    try std.testing.expectEqual(BackgroundKind.subagent, row.kind);
    try std.testing.expect(row.can_stop);
    try std.testing.expectEqualStrings(subagent_stop_label, row.stop_label);
    try std.testing.expectEqualStrings(live_running_label, backgroundWorkStatus(row));
    try std.testing.expectEqualStrings("", backgroundWorkOutput(&model));
}

test "openBackgroundWork shows Subagent log; settle keeps it; dismiss frees it" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    defer clearLiveSubagents(&model);
    const id = model.addSession("env background subagent log", .claude);
    model.selected = id;
    model.phase = .streaming;
    model.streaming_session = id;
    if (model.sessionById(id)) |session| session.busy = true;
    noteLiveSubagent(&model, "toolu_agent_log");
    appendLiveSubagentOutput(&model, "toolu_agent_log", "line from subagent");
    model.environment_summary_open = true;

    openBackgroundWork(&model, &fx, subagent_row_id_first);
    try std.testing.expectEqualStrings("line from subagent", backgroundWorkOutput(&model));
    var buf: [max_background_rows]BackgroundRow = undefined;
    var rows = fillBackgroundRows(&model, &buf);
    try std.testing.expectEqualStrings("line from subagent", rows[1].detail);

    turn_stream.finishStream(&model, &fx, true);
    try std.testing.expectEqual(SettledStatus.completed, model.background_subagents[0].settled);
    try std.testing.expectEqualStrings("line from subagent", backgroundWorkOutput(&model));
    try std.testing.expectEqualStrings("line from subagent", model.background_subagents[0].output());
    rows = fillBackgroundRows(&model, &buf);
    try std.testing.expect(rows[1].can_stop);
    try std.testing.expectEqualStrings(subagent_dismiss_label, rows[1].stop_label);
    try std.testing.expectEqualStrings("line from subagent", rows[1].detail);

    stopBackground(&model, &fx, subagent_row_id_first);
    try std.testing.expectEqual(@as(u32, 0), model.background_subagent_count);
    try std.testing.expectEqual(@as(usize, 0), model.background_subagents[0].output().len);
    try std.testing.expectEqual(@as(u32, 0), model.right_panel_background_row_id);
    try std.testing.expectEqual(@as(u32, 0), model.background_dismissed_subagent_count);

    model.phase = .streaming;
    model.streaming_session = id;
    noteLiveSubagent(&model, "toolu_agent_live");
    appendLiveSubagentOutput(&model, "toolu_agent_live", "live log");
    stopBackground(&model, &fx, subagent_row_id_first);
    try std.testing.expectEqual(@as(u32, 0), model.background_subagent_count);
    try std.testing.expectEqual(@as(u32, 1), model.background_dismissed_subagent_count);
}

test "settled Process row on Background keeps Completed / Stopped / Failed" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    const id = model.addSession("env background settled", .fx);
    model.selected = id;
    settle(&model, id, .completed);
    model.environment_summary_open = true;
    openBackgroundWork(&model, &fx, process_row_id);
    try std.testing.expectEqualStrings(settled_completed_label, backgroundWorkStatus(selectedBackgroundRow(&model).?));

    settle(&model, id, .stopped);
    try std.testing.expectEqualStrings(settled_stopped_label, backgroundWorkStatus(selectedBackgroundRow(&model).?));
    settle(&model, id, .failed);
    try std.testing.expectEqualStrings(settled_failed_label, backgroundWorkStatus(selectedBackgroundRow(&model).?));
}

test "live Monitor can_stop; stop by monitor id removes only that monitor" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    defer clearLiveMonitors(&model);
    const id = model.addSession("env stop monitor", .claude);
    model.selected = id;
    model.phase = .streaming;
    model.streaming_session = id;
    if (model.sessionById(id)) |session| session.busy = true;
    noteLiveMonitor(&model, "toolu_mon_stop_1");
    noteLiveMonitor(&model, "toolu_mon_stop_2");
    noteLiveSubagent(&model, "toolu_agent_keep");
    appendLiveMonitorOutput(&model, "toolu_mon_stop_1", "first monitor log");
    appendLiveMonitorOutput(&model, "toolu_mon_stop_2", "second monitor log");
    model.environment_summary_open = true;

    var buf: [max_background_rows]BackgroundRow = undefined;
    var rows = fillBackgroundRows(&model, &buf);
    try std.testing.expectEqual(@as(usize, 4), rows.len);
    try std.testing.expect(rows[0].can_stop);
    try std.testing.expectEqualStrings(process_stop_label, rows[0].stop_label);
    try std.testing.expect(rows[1].can_stop);
    try std.testing.expectEqualStrings(monitor_stop_label, rows[1].stop_label);
    try std.testing.expectEqual(monitor_row_id_first, rows[1].id);
    try std.testing.expect(rows[2].can_stop);
    try std.testing.expectEqual(monitor_row_id_first + 1, rows[2].id);
    try std.testing.expect(rows[3].can_stop);
    try std.testing.expectEqualStrings(subagent_stop_label, rows[3].stop_label);
    try std.testing.expectEqual(BackgroundKind.subagent, rows[3].kind);

    stopBackground(&model, &fx, 99);
    try std.testing.expect(model.environment_summary_open);
    try std.testing.expect(model.is_streaming());
    try std.testing.expectEqual(@as(u32, 2), model.background_monitor_count);

    stopBackground(&model, &fx, 50);
    try std.testing.expect(model.environment_summary_open);
    try std.testing.expectEqual(@as(u32, 1), model.background_subagent_count);
    try std.testing.expectEqual(@as(u32, 2), model.background_monitor_count);

    stopBackground(&model, &fx, monitor_row_id_first);
    try std.testing.expect(!model.environment_summary_open);
    try std.testing.expect(model.is_streaming());
    try std.testing.expectEqual(id, model.streaming_session);
    try std.testing.expect(model.sessionById(id).?.busy);
    try std.testing.expectEqual(@as(u32, 1), model.background_monitor_count);
    try std.testing.expectEqualStrings("toolu_mon_stop_2", model.background_monitors[0].toolUseId());
    try std.testing.expectEqualStrings("second monitor log", model.background_monitors[0].output());
    try std.testing.expectEqual(@as(u32, 1), model.background_subagent_count);
    rows = fillBackgroundRows(&model, &buf);
    try std.testing.expectEqual(@as(usize, 3), rows.len);
    try std.testing.expectEqual(BackgroundKind.process, rows[0].kind);
    try std.testing.expect(rows[0].live);
    try std.testing.expect(rows[0].can_stop);
    try std.testing.expectEqual(BackgroundKind.monitor, rows[1].kind);
    try std.testing.expectEqual(monitor_row_id_first, rows[1].id);
    try std.testing.expectEqualStrings("second monitor log", rows[1].detail);
    try std.testing.expectEqual(BackgroundKind.subagent, rows[2].kind);

    appendLiveMonitorOutput(&model, "toolu_mon_stop_1", "ignored after stop");
    try std.testing.expectEqual(@as(u32, 1), model.background_monitor_count);
    try std.testing.expectEqualStrings("second monitor log", model.background_monitors[0].output());
    appendLiveMonitorOutput(&model, "toolu_mon_stop_2", " still live");
    try std.testing.expectEqualStrings("second monitor log still live", model.background_monitors[0].output());
}

test "stopBackground Process still stopStream while a Monitor is live" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    defer clearLiveMonitors(&model);
    const id = model.addSession("env stop process with monitor", .claude);
    model.selected = id;
    model.phase = .streaming;
    model.streaming_session = id;
    if (model.sessionById(id)) |session| session.busy = true;
    noteLiveMonitor(&model, "toolu_mon_with_process");
    model.environment_summary_open = true;

    stopBackground(&model, &fx, process_row_id);
    try std.testing.expect(!model.environment_summary_open);
    try std.testing.expect(!model.is_streaming());
    try std.testing.expectEqual(main.Phase.idle, model.phase);
    try std.testing.expectEqual(@as(u32, 0), model.streaming_session);
    try std.testing.expect(!model.sessionById(id).?.busy);
    try std.testing.expectEqual(@as(u32, 1), model.background_monitor_count);
    try std.testing.expectEqual(SettledStatus.stopped, model.background_monitors[0].settled);
    try std.testing.expect(hasSettledBackground(&model));
    var buf: [max_background_rows]BackgroundRow = undefined;
    const rows = fillBackgroundRows(&model, &buf);
    try std.testing.expectEqual(@as(usize, 2), rows.len);
    try std.testing.expectEqualStrings(settled_stopped_label, rows[0].settled_status);
    try std.testing.expectEqual(BackgroundKind.monitor, rows[1].kind);
    try std.testing.expect(!rows[1].live);
    try std.testing.expect(rows[1].can_stop);
    try std.testing.expectEqualStrings(settled_stopped_label, rows[1].settled_status);
}

test "right-panel selection clears when the stopped Monitor was selected" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    defer clearLiveMonitors(&model);
    const id = model.addSession("env stop monitor selection", .claude);
    model.selected = id;
    model.phase = .streaming;
    model.streaming_session = id;
    noteLiveMonitor(&model, "toolu_mon_sel_1");
    noteLiveMonitor(&model, "toolu_mon_sel_2");
    appendLiveMonitorOutput(&model, "toolu_mon_sel_1", "keep me until stop");
    model.right_panel_open = true;
    model.right_panel_tab = right_panel.Tab.background;
    model.right_panel_background_row_id = monitor_row_id_first;
    try std.testing.expectEqual(monitor_row_id_first, selectedBackgroundRow(&model).?.id);
    refreshPanelCache(&model);
    try std.testing.expectEqualStrings("keep me until stop", backgroundWorkOutput(&model));

    stopBackground(&model, &fx, monitor_row_id_first);
    try std.testing.expect(model.is_streaming());
    try std.testing.expectEqual(@as(u32, 0), model.right_panel_background_row_id);
    try std.testing.expect(selectedBackgroundRow(&model) == null);
    try std.testing.expectEqualStrings("", backgroundWorkOutput(&model));
    try std.testing.expectEqual(right_panel.Tab.background, model.right_panel_tab);
    try std.testing.expectEqual(@as(u32, 1), model.background_monitor_count);
    try std.testing.expectEqualStrings("toolu_mon_sel_2", model.background_monitors[0].toolUseId());

    noteLiveMonitor(&model, "toolu_mon_sel_3");
    model.right_panel_background_row_id = monitor_row_id_first + 1;
    try std.testing.expectEqual(monitor_row_id_first + 1, selectedBackgroundRow(&model).?.id);
    stopBackground(&model, &fx, monitor_row_id_first);
    try std.testing.expectEqual(monitor_row_id_first, model.right_panel_background_row_id);
    try std.testing.expectEqual(monitor_row_id_first, selectedBackgroundRow(&model).?.id);
    try std.testing.expectEqualStrings("toolu_mon_sel_3", model.background_monitors[0].toolUseId());

    model.right_panel_background_row_id = process_row_id;
    stopBackground(&model, &fx, monitor_row_id_first);
    try std.testing.expectEqual(process_row_id, model.right_panel_background_row_id);
    try std.testing.expectEqual(process_row_id, selectedBackgroundRow(&model).?.id);
    try std.testing.expect(model.is_streaming());
    try std.testing.expectEqual(@as(u32, 0), model.background_monitor_count);
}

test "environment_stop_background monitor id leaves Process streaming" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    defer clearLiveMonitors(&model);
    const id = model.addSession("env stop monitor msg", .claude);
    model.selected = id;
    model.phase = .streaming;
    model.streaming_session = id;
    if (model.sessionById(id)) |session| session.busy = true;
    noteLiveMonitor(&model, "toolu_mon_msg");
    model.environment_summary_open = true;

    main.update(&model, .{ .environment_stop_background = monitor_row_id_first }, &fx);
    try std.testing.expect(!model.environment_summary_open);
    try std.testing.expect(model.is_streaming());
    try std.testing.expectEqual(@as(u32, 0), model.background_monitor_count);
    try std.testing.expect(model.sessionById(id).?.busy);
    try expectLiveProcessRow(&model);
}

test "live Subagent can_stop; stop by subagent id removes only that subagent" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    defer clearLiveMonitors(&model);
    const id = model.addSession("env stop subagent", .claude);
    model.selected = id;
    model.phase = .streaming;
    model.streaming_session = id;
    if (model.sessionById(id)) |session| session.busy = true;
    noteLiveMonitor(&model, "toolu_mon_keep");
    appendLiveMonitorOutput(&model, "toolu_mon_keep", "monitor stays");
    noteLiveSubagent(&model, "toolu_agent_stop_1");
    noteLiveSubagent(&model, "toolu_agent_stop_2");
    model.environment_summary_open = true;

    var buf: [max_background_rows]BackgroundRow = undefined;
    var rows = fillBackgroundRows(&model, &buf);
    try std.testing.expectEqual(@as(usize, 4), rows.len);
    try std.testing.expect(rows[0].can_stop);
    try std.testing.expectEqualStrings(process_stop_label, rows[0].stop_label);
    try std.testing.expectEqual(BackgroundKind.monitor, rows[1].kind);
    try std.testing.expect(rows[1].can_stop);
    try std.testing.expectEqualStrings(monitor_stop_label, rows[1].stop_label);
    try std.testing.expect(rows[2].can_stop);
    try std.testing.expectEqualStrings(subagent_stop_label, rows[2].stop_label);
    try std.testing.expectEqual(subagent_row_id_first, rows[2].id);
    try std.testing.expect(rows[3].can_stop);
    try std.testing.expectEqual(subagent_row_id_first + 1, rows[3].id);

    stopBackground(&model, &fx, 99);
    try std.testing.expect(model.environment_summary_open);
    try std.testing.expect(model.is_streaming());
    try std.testing.expectEqual(@as(u32, 2), model.background_subagent_count);
    try std.testing.expectEqual(@as(u32, 1), model.background_monitor_count);

    stopBackground(&model, &fx, subagent_row_id_first);
    try std.testing.expect(!model.environment_summary_open);
    try std.testing.expect(model.is_streaming());
    try std.testing.expectEqual(id, model.streaming_session);
    try std.testing.expect(model.sessionById(id).?.busy);
    try std.testing.expectEqual(@as(u32, 1), model.background_subagent_count);
    try std.testing.expectEqualStrings("toolu_agent_stop_2", model.background_subagents[0].parentId());
    try std.testing.expectEqual(@as(u32, 1), model.background_monitor_count);
    try std.testing.expectEqualStrings("toolu_mon_keep", model.background_monitors[0].toolUseId());
    try std.testing.expectEqualStrings("monitor stays", model.background_monitors[0].output());
    try std.testing.expectEqual(@as(u32, 1), model.background_dismissed_subagent_count);
    rows = fillBackgroundRows(&model, &buf);
    try std.testing.expectEqual(@as(usize, 3), rows.len);
    try std.testing.expectEqual(BackgroundKind.process, rows[0].kind);
    try std.testing.expect(rows[0].live);
    try std.testing.expect(rows[0].can_stop);
    try std.testing.expectEqual(BackgroundKind.monitor, rows[1].kind);
    try std.testing.expectEqualStrings("monitor stays", rows[1].detail);
    try std.testing.expectEqual(BackgroundKind.subagent, rows[2].kind);
    try std.testing.expectEqual(subagent_row_id_first, rows[2].id);
    try std.testing.expectEqualStrings(subagent_stop_label, rows[2].stop_label);

    noteLiveSubagent(&model, "toolu_agent_stop_1");
    try std.testing.expectEqual(@as(u32, 1), model.background_subagent_count);
    try std.testing.expectEqualStrings("toolu_agent_stop_2", model.background_subagents[0].parentId());
    noteLiveSubagent(&model, "toolu_agent_stop_3");
    try std.testing.expectEqual(@as(u32, 2), model.background_subagent_count);
    try std.testing.expectEqualStrings("toolu_agent_stop_3", model.background_subagents[1].parentId());
}

test "stopBackground Process still stopStream while a Subagent is live" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    const id = model.addSession("env stop process with subagent", .claude);
    model.selected = id;
    model.phase = .streaming;
    model.streaming_session = id;
    if (model.sessionById(id)) |session| session.busy = true;
    noteLiveSubagent(&model, "toolu_agent_with_process");
    model.environment_summary_open = true;

    stopBackground(&model, &fx, process_row_id);
    try std.testing.expect(!model.environment_summary_open);
    try std.testing.expect(!model.is_streaming());
    try std.testing.expectEqual(main.Phase.idle, model.phase);
    try std.testing.expectEqual(@as(u32, 0), model.streaming_session);
    try std.testing.expect(!model.sessionById(id).?.busy);
    try std.testing.expectEqual(@as(u32, 1), model.background_subagent_count);
    try std.testing.expectEqual(SettledStatus.stopped, model.background_subagents[0].settled);
    try std.testing.expectEqual(@as(u32, 0), model.background_dismissed_subagent_count);
    try std.testing.expect(hasSettledBackground(&model));
    var buf: [max_background_rows]BackgroundRow = undefined;
    const rows = fillBackgroundRows(&model, &buf);
    try std.testing.expectEqual(@as(usize, 2), rows.len);
    try std.testing.expectEqualStrings(settled_stopped_label, rows[0].settled_status);
    try std.testing.expectEqual(BackgroundKind.subagent, rows[1].kind);
    try std.testing.expect(rows[1].can_stop);
    try std.testing.expectEqualStrings(subagent_dismiss_label, rows[1].stop_label);
    try std.testing.expectEqualStrings(settled_stopped_label, rows[1].settled_status);
}

test "right-panel selection clears when the stopped Subagent was selected" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    defer clearLiveMonitors(&model);
    const id = model.addSession("env stop subagent selection", .claude);
    model.selected = id;
    model.phase = .streaming;
    model.streaming_session = id;
    noteLiveMonitor(&model, "toolu_mon_untouched");
    appendLiveMonitorOutput(&model, "toolu_mon_untouched", "keep monitor");
    noteLiveSubagent(&model, "toolu_agent_sel_1");
    noteLiveSubagent(&model, "toolu_agent_sel_2");
    model.right_panel_open = true;
    model.right_panel_tab = right_panel.Tab.background;
    model.right_panel_background_row_id = subagent_row_id_first;
    try std.testing.expectEqual(subagent_row_id_first, selectedBackgroundRow(&model).?.id);
    try std.testing.expectEqualStrings("", backgroundWorkOutput(&model));

    stopBackground(&model, &fx, subagent_row_id_first);
    try std.testing.expect(model.is_streaming());
    try std.testing.expectEqual(@as(u32, 0), model.right_panel_background_row_id);
    try std.testing.expect(selectedBackgroundRow(&model) == null);
    try std.testing.expectEqualStrings("", backgroundWorkOutput(&model));
    try std.testing.expectEqual(right_panel.Tab.background, model.right_panel_tab);
    try std.testing.expectEqual(@as(u32, 1), model.background_subagent_count);
    try std.testing.expectEqualStrings("toolu_agent_sel_2", model.background_subagents[0].parentId());
    try std.testing.expectEqual(@as(u32, 1), model.background_monitor_count);
    try std.testing.expectEqualStrings("keep monitor", model.background_monitors[0].output());

    noteLiveSubagent(&model, "toolu_agent_sel_3");
    model.right_panel_background_row_id = subagent_row_id_first + 1;
    try std.testing.expectEqual(subagent_row_id_first + 1, selectedBackgroundRow(&model).?.id);
    stopBackground(&model, &fx, subagent_row_id_first);
    try std.testing.expectEqual(subagent_row_id_first, model.right_panel_background_row_id);
    try std.testing.expectEqual(subagent_row_id_first, selectedBackgroundRow(&model).?.id);
    try std.testing.expectEqualStrings("toolu_agent_sel_3", model.background_subagents[0].parentId());

    model.right_panel_background_row_id = process_row_id;
    stopBackground(&model, &fx, subagent_row_id_first);
    try std.testing.expectEqual(process_row_id, model.right_panel_background_row_id);
    try std.testing.expectEqual(process_row_id, selectedBackgroundRow(&model).?.id);
    try std.testing.expect(model.is_streaming());
    try std.testing.expectEqual(@as(u32, 0), model.background_subagent_count);

    model.right_panel_background_row_id = monitor_row_id_first;
    noteLiveSubagent(&model, "toolu_agent_sel_4");
    stopBackground(&model, &fx, subagent_row_id_first);
    try std.testing.expectEqual(monitor_row_id_first, model.right_panel_background_row_id);
    try std.testing.expectEqual(monitor_row_id_first, selectedBackgroundRow(&model).?.id);
    refreshPanelCache(&model);
    try std.testing.expectEqualStrings("keep monitor", backgroundWorkOutput(&model));
}

test "environment_stop_background subagent id leaves Process streaming" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    const id = model.addSession("env stop subagent msg", .claude);
    model.selected = id;
    model.phase = .streaming;
    model.streaming_session = id;
    if (model.sessionById(id)) |session| session.busy = true;
    noteLiveSubagent(&model, "toolu_agent_msg");
    model.environment_summary_open = true;

    main.update(&model, .{ .environment_stop_background = subagent_row_id_first }, &fx);
    try std.testing.expect(!model.environment_summary_open);
    try std.testing.expect(model.is_streaming());
    try std.testing.expectEqual(@as(u32, 0), model.background_subagent_count);
    try std.testing.expect(model.sessionById(id).?.busy);
    try expectLiveProcessRow(&model);
}

test "dismissed Subagent id stays ignored until clearLiveSubagents" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    const id = model.addSession("env dismissed subagent", .claude);
    model.selected = id;
    model.phase = .streaming;
    model.streaming_session = id;
    noteLiveSubagent(&model, "toolu_agent_dismiss");
    stopBackground(&model, &fx, subagent_row_id_first);
    try std.testing.expectEqual(@as(u32, 0), model.background_subagent_count);
    try std.testing.expectEqual(@as(u32, 1), model.background_dismissed_subagent_count);

    noteLiveSubagent(&model, "toolu_agent_dismiss");
    try std.testing.expectEqual(@as(u32, 0), model.background_subagent_count);
    noteLiveSubagent(&model, "toolu_agent_fresh");
    try std.testing.expectEqual(@as(u32, 1), model.background_subagent_count);
    try std.testing.expectEqualStrings("toolu_agent_fresh", model.background_subagents[0].parentId());

    clearLiveSubagents(&model);
    try std.testing.expectEqual(@as(u32, 0), model.background_subagent_count);
    try std.testing.expectEqual(@as(u32, 0), model.background_dismissed_subagent_count);
    noteLiveSubagent(&model, "toolu_agent_dismiss");
    try std.testing.expectEqual(@as(u32, 1), model.background_subagent_count);
    try std.testing.expectEqualStrings("toolu_agent_dismiss", model.background_subagents[0].parentId());
}

test "drain=false finishStream settles Monitor and Subagent Failed" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    defer clearLiveMonitors(&model);
    defer clearLiveSubagents(&model);
    const id = model.addSession("env settle failed signals", .claude);
    model.selected = id;
    model.phase = .streaming;
    model.streaming_session = id;
    noteLiveMonitor(&model, "toolu_mon_fail");
    appendLiveMonitorOutput(&model, "toolu_mon_fail", "fail log");
    noteLiveSubagent(&model, "toolu_agent_fail");
    appendLiveSubagentOutput(&model, "toolu_agent_fail", "fail subagent log");

    turn_stream.finishStream(&model, &fx, false);
    try std.testing.expectEqual(SettledStatus.failed, model.background_settled);
    try std.testing.expectEqual(SettledStatus.failed, model.background_monitors[0].settled);
    try std.testing.expectEqual(SettledStatus.failed, model.background_subagents[0].settled);
    try std.testing.expectEqualStrings("fail log", model.background_monitors[0].output());
    try std.testing.expectEqualStrings("fail subagent log", model.background_subagents[0].output());
    var buf: [max_background_rows]BackgroundRow = undefined;
    const rows = fillBackgroundRows(&model, &buf);
    try std.testing.expectEqual(@as(usize, 3), rows.len);
    try std.testing.expectEqualStrings(settled_failed_label, rows[0].settled_status);
    try std.testing.expectEqual(BackgroundKind.monitor, rows[1].kind);
    try std.testing.expectEqualStrings(settled_failed_label, rows[1].settled_status);
    try std.testing.expect(rows[1].can_stop);
    try std.testing.expectEqualStrings(monitor_dismiss_label, rows[1].stop_label);
    try std.testing.expectEqual(BackgroundKind.subagent, rows[2].kind);
    try std.testing.expectEqualStrings(settled_failed_label, rows[2].settled_status);
    try std.testing.expect(rows[2].can_stop);
    try std.testing.expectEqualStrings(subagent_dismiss_label, rows[2].stop_label);
    try std.testing.expectEqualStrings("fail subagent log", rows[2].detail);
    appendLiveMonitorOutput(&model, "toolu_mon_fail", " ignored after settle");
    try std.testing.expectEqualStrings("fail log", model.background_monitors[0].output());
    appendLiveSubagentOutput(&model, "toolu_agent_fail", " ignored after settle");
    try std.testing.expectEqualStrings("fail subagent log", model.background_subagents[0].output());
}

test "session switch hides another session's settled Monitor and Subagent; remove frees the log" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    defer clearLiveMonitors(&model);
    defer clearLiveSubagents(&model);
    const first = model.addSession("env settle session a", .claude);
    const second = model.addSession("env settle session b", .claude);
    model.selected = first;
    model.phase = .streaming;
    model.streaming_session = first;
    noteLiveMonitor(&model, "toolu_mon_a");
    appendLiveMonitorOutput(&model, "toolu_mon_a", "session a log");
    noteLiveSubagent(&model, "toolu_agent_a");
    appendLiveSubagentOutput(&model, "toolu_agent_a", "session a subagent");
    turn_stream.finishStream(&model, &fx, true);
    try std.testing.expectEqual(SettledStatus.completed, model.background_monitors[0].settled);
    try std.testing.expectEqual(SettledStatus.completed, model.background_subagents[0].settled);

    var buf: [max_background_rows]BackgroundRow = undefined;
    var rows = fillBackgroundRows(&model, &buf);
    try std.testing.expectEqual(@as(usize, 3), rows.len);
    try std.testing.expectEqual(BackgroundKind.monitor, rows[1].kind);
    try std.testing.expectEqual(BackgroundKind.subagent, rows[2].kind);
    try std.testing.expectEqualStrings("session a subagent", rows[2].detail);

    model.selected = second;
    try std.testing.expect(!hasSettledBackground(&model));
    try expectNoBackgroundRows(&model);

    model.selected = first;
    rows = fillBackgroundRows(&model, &buf);
    try std.testing.expectEqual(@as(usize, 3), rows.len);
    try std.testing.expectEqualStrings("session a log", rows[1].detail);
    try std.testing.expectEqualStrings("session a subagent", rows[2].detail);
    model.right_panel_background_row_id = monitor_row_id_first;
    try std.testing.expectEqualStrings("session a log", backgroundWorkOutput(&model));
    model.right_panel_background_row_id = subagent_row_id_first;
    try std.testing.expectEqualStrings("session a subagent", backgroundWorkOutput(&model));

    clearSettledIfSession(&model, first);
    try std.testing.expectEqual(@as(u32, 0), model.background_monitor_count);
    try std.testing.expectEqual(@as(u32, 0), model.background_subagent_count);
    try std.testing.expectEqual(SettledStatus.none, model.background_settled);
    try std.testing.expectEqual(@as(u32, 0), model.right_panel_background_row_id);
    try expectNoBackgroundRows(&model);
}

test "cap trim drops oldest settled Monitor before live" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    defer clearLiveMonitors(&model);
    const id = model.addSession("env trim settled", .claude);
    model.selected = id;
    model.phase = .streaming;
    model.streaming_session = id;
    var i: usize = 0;
    while (i < max_live_monitors) : (i += 1) {
        var id_buf: [32]u8 = undefined;
        const label = std.fmt.bufPrint(&id_buf, "toolu_mon_trim_{d}", .{i}) catch unreachable;
        noteLiveMonitor(&model, label);
        appendLiveMonitorOutput(&model, label, "old");
    }
    try std.testing.expectEqual(@as(u32, @intCast(max_live_monitors)), model.background_monitor_count);
    turn_stream.finishStream(&model, &fx, true);
    try std.testing.expectEqual(SettledStatus.completed, model.background_monitors[0].settled);
    try std.testing.expectEqualStrings("toolu_mon_trim_0", model.background_monitors[0].toolUseId());

    model.phase = .streaming;
    model.streaming_session = id;
    noteLiveMonitor(&model, "toolu_mon_trim_live");
    try std.testing.expectEqual(@as(u32, @intCast(max_live_monitors)), model.background_monitor_count);
    try std.testing.expectEqualStrings("toolu_mon_trim_1", model.background_monitors[0].toolUseId());
    try std.testing.expectEqual(SettledStatus.completed, model.background_monitors[0].settled);
    const last = model.background_monitor_count - 1;
    try std.testing.expectEqualStrings("toolu_mon_trim_live", model.background_monitors[last].toolUseId());
    try std.testing.expectEqual(SettledStatus.none, model.background_monitors[last].settled);

    var buf: [max_background_rows]BackgroundRow = undefined;
    const rows = fillBackgroundRows(&model, &buf);
    try std.testing.expectEqual(max_background_rows, rows.len);
    try std.testing.expectEqual(BackgroundKind.process, rows[0].kind);
    try std.testing.expect(rows[1].live);
    try std.testing.expectEqualStrings(kind_monitor_label, rows[1].title);
    try std.testing.expect(!rows[2].live);

    noteLiveMonitor(&model, "toolu_mon_trim_0");
    try std.testing.expectEqual(@as(u32, @intCast(max_live_monitors)), model.background_monitor_count);
    try std.testing.expectEqualStrings("toolu_mon_trim_2", model.background_monitors[0].toolUseId());
}

test "cap trim drops oldest settled Subagent and frees its log" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    defer clearLiveSubagents(&model);
    const id = model.addSession("env trim settled subagent", .claude);
    model.selected = id;
    model.phase = .streaming;
    model.streaming_session = id;
    var i: usize = 0;
    while (i < max_live_subagents) : (i += 1) {
        var id_buf: [32]u8 = undefined;
        const label = std.fmt.bufPrint(&id_buf, "toolu_agent_trim_{d}", .{i}) catch unreachable;
        noteLiveSubagent(&model, label);
        appendLiveSubagentOutput(&model, label, "old");
    }
    try std.testing.expectEqual(@as(u32, @intCast(max_live_subagents)), model.background_subagent_count);
    turn_stream.finishStream(&model, &fx, true);
    try std.testing.expectEqual(SettledStatus.completed, model.background_subagents[0].settled);
    try std.testing.expectEqualStrings("toolu_agent_trim_0", model.background_subagents[0].parentId());
    try std.testing.expectEqualStrings("old", model.background_subagents[0].output());

    model.phase = .streaming;
    model.streaming_session = id;
    noteLiveSubagent(&model, "toolu_agent_trim_live");
    try std.testing.expectEqual(@as(u32, @intCast(max_live_subagents)), model.background_subagent_count);
    try std.testing.expectEqualStrings("toolu_agent_trim_1", model.background_subagents[0].parentId());
    try std.testing.expectEqual(SettledStatus.completed, model.background_subagents[0].settled);
    try std.testing.expectEqualStrings("old", model.background_subagents[0].output());
    const last = model.background_subagent_count - 1;
    try std.testing.expectEqualStrings("toolu_agent_trim_live", model.background_subagents[last].parentId());
    try std.testing.expectEqual(SettledStatus.none, model.background_subagents[last].settled);
    try std.testing.expectEqual(@as(usize, 0), model.background_subagents[last].output().len);

    noteLiveSubagent(&model, "toolu_agent_trim_0");
    try std.testing.expectEqual(@as(u32, @intCast(max_live_subagents)), model.background_subagent_count);
    try std.testing.expectEqualStrings("toolu_agent_trim_2", model.background_subagents[0].parentId());
}

test "duplicate settled Monitor id becomes a new live slot" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    defer clearLiveMonitors(&model);
    const id = model.addSession("env duplicate settled", .claude);
    model.selected = id;
    model.phase = .streaming;
    model.streaming_session = id;
    noteLiveMonitor(&model, "toolu_mon_dup");
    appendLiveMonitorOutput(&model, "toolu_mon_dup", "settled log");
    noteLiveSubagent(&model, "toolu_agent_dup");
    turn_stream.finishStream(&model, &fx, true);

    model.phase = .streaming;
    model.streaming_session = id;
    noteLiveMonitor(&model, "toolu_mon_dup");
    noteLiveSubagent(&model, "toolu_agent_dup");
    try std.testing.expectEqual(@as(u32, 2), model.background_monitor_count);
    try std.testing.expectEqual(SettledStatus.completed, model.background_monitors[0].settled);
    try std.testing.expectEqual(SettledStatus.none, model.background_monitors[1].settled);
    try std.testing.expectEqualStrings("settled log", model.background_monitors[0].output());
    try std.testing.expectEqual(@as(usize, 0), model.background_monitors[1].output().len);
    try std.testing.expectEqual(@as(u32, 2), model.background_subagent_count);
    try std.testing.expectEqual(SettledStatus.completed, model.background_subagents[0].settled);
    try std.testing.expectEqual(SettledStatus.none, model.background_subagents[1].settled);

    var buf: [max_background_rows]BackgroundRow = undefined;
    const rows = fillBackgroundRows(&model, &buf);
    try std.testing.expectEqual(@as(usize, 5), rows.len);
    try std.testing.expect(rows[1].live);
    try std.testing.expect(rows[1].can_stop);
    try std.testing.expect(!rows[2].live);
    try std.testing.expect(rows[2].can_stop);
    try std.testing.expectEqualStrings(monitor_dismiss_label, rows[2].stop_label);
    try std.testing.expect(rows[3].live);
    try std.testing.expect(!rows[4].live);
    try std.testing.expect(rows[4].can_stop);
    try std.testing.expectEqualStrings(subagent_dismiss_label, rows[4].stop_label);
}

test "queued finishStream restart keeps settled Monitor log" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    defer clearLiveMonitors(&model);
    const id = model.addSession("env queue keeps monitor", .claude);
    model.selected = id;
    model.phase = .streaming;
    model.streaming_session = id;
    if (model.sessionById(id)) |session| session.busy = true;
    noteLiveMonitor(&model, "toolu_mon_queue");
    appendLiveMonitorOutput(&model, "toolu_mon_queue", "queued keep");
    _ = model.enqueue(id, "follow-up");

    turn_stream.finishStream(&model, &fx, true);
    try std.testing.expect(model.is_streaming());
    try std.testing.expect(!hasSettledBackground(&model));
    try std.testing.expectEqual(@as(u32, 1), model.background_monitor_count);
    try std.testing.expectEqual(SettledStatus.completed, model.background_monitors[0].settled);
    try std.testing.expectEqualStrings("queued keep", model.background_monitors[0].output());

    noteLiveMonitor(&model, "toolu_mon_queue_live");
    var buf: [max_background_rows]BackgroundRow = undefined;
    const rows = fillBackgroundRows(&model, &buf);
    try std.testing.expectEqual(@as(usize, 3), rows.len);
    try std.testing.expect(rows[0].live);
    try std.testing.expect(rows[1].live);
    try std.testing.expect(!rows[2].live);
    try std.testing.expect(rows[2].can_stop);
    try std.testing.expectEqualStrings(monitor_dismiss_label, rows[2].stop_label);
    try std.testing.expectEqualStrings("queued keep", rows[2].detail);
}

test "settled Monitor and Subagent can_stop dismiss; stopBackground removes the slot" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    defer clearLiveMonitors(&model);
    defer clearLiveSubagents(&model);
    const id = model.addSession("env settled dismiss", .claude);
    model.selected = id;
    model.phase = .streaming;
    model.streaming_session = id;
    if (model.sessionById(id)) |session| session.busy = true;
    noteLiveMonitor(&model, "toolu_mon_dismiss");
    appendLiveMonitorOutput(&model, "toolu_mon_dismiss", "monitor keep");
    noteLiveSubagent(&model, "toolu_agent_dismiss_settled");
    appendLiveSubagentOutput(&model, "toolu_agent_dismiss_settled", "subagent keep");

    settleLiveBackgroundSignals(&model, id, .completed);
    settle(&model, id, .completed);
    model.phase = .idle;
    model.streaming_session = 0;
    if (model.sessionById(id)) |session| session.busy = false;

    var buf: [max_background_rows]BackgroundRow = undefined;
    var rows = fillBackgroundRows(&model, &buf);
    try std.testing.expectEqual(@as(usize, 3), rows.len);
    try std.testing.expectEqual(BackgroundKind.process, rows[0].kind);
    try std.testing.expect(!rows[0].live);
    try std.testing.expect(!rows[0].can_stop);
    try std.testing.expectEqualStrings("", rows[0].stop_label);
    try std.testing.expectEqual(BackgroundKind.monitor, rows[1].kind);
    try std.testing.expect(!rows[1].live);
    try std.testing.expect(rows[1].can_stop);
    try std.testing.expectEqualStrings(monitor_dismiss_label, rows[1].stop_label);
    try std.testing.expectEqual(BackgroundKind.subagent, rows[2].kind);
    try std.testing.expect(!rows[2].live);
    try std.testing.expect(rows[2].can_stop);
    try std.testing.expectEqualStrings(subagent_dismiss_label, rows[2].stop_label);

    model.right_panel_open = true;
    model.right_panel_tab = right_panel.Tab.background;
    model.right_panel_background_row_id = monitor_row_id_first;
    try std.testing.expectEqualStrings("monitor keep", backgroundWorkOutput(&model));
    try std.testing.expect(selectedBackgroundRow(&model).?.can_stop);
    try std.testing.expectEqualStrings(monitor_dismiss_label, selectedBackgroundRow(&model).?.stop_label);

    stopBackground(&model, &fx, monitor_row_id_first);
    try std.testing.expectEqual(@as(u32, 0), model.background_monitor_count);
    try std.testing.expectEqual(@as(usize, 0), model.background_monitors[0].output().len);
    try std.testing.expectEqual(@as(usize, 0), model.background_monitors[0].log.output_storage.len);
    try std.testing.expectEqual(@as(u32, 0), model.right_panel_background_row_id);
    try std.testing.expect(selectedBackgroundRow(&model) == null);
    try std.testing.expectEqual(@as(u32, 1), model.background_subagent_count);
    try std.testing.expectEqualStrings("subagent keep", model.background_subagents[0].output());
    try std.testing.expect(!model.is_streaming());
    try std.testing.expectEqual(SettledStatus.completed, model.background_settled);

    stopBackground(&model, &fx, process_row_id);
    try std.testing.expectEqual(SettledStatus.completed, model.background_settled);
    try std.testing.expect(!model.is_streaming());

    model.right_panel_background_row_id = subagent_row_id_first;
    try std.testing.expectEqualStrings("subagent keep", backgroundWorkOutput(&model));
    stopBackground(&model, &fx, subagent_row_id_first);
    try std.testing.expectEqual(@as(u32, 0), model.background_subagent_count);
    try std.testing.expectEqual(@as(usize, 0), model.background_subagents[0].output().len);
    try std.testing.expectEqual(@as(u32, 0), model.right_panel_background_row_id);
    try std.testing.expectEqual(@as(u32, 0), model.background_dismissed_subagent_count);

    rows = fillBackgroundRows(&model, &buf);
    try std.testing.expectEqual(@as(usize, 1), rows.len);
    try std.testing.expectEqual(BackgroundKind.process, rows[0].kind);
    try std.testing.expect(!rows[0].can_stop);

    model.phase = .streaming;
    model.streaming_session = id;
    if (model.sessionById(id)) |session| session.busy = true;
    noteLiveMonitor(&model, "toolu_mon_live_stop");
    appendLiveMonitorOutput(&model, "toolu_mon_live_stop", "live log");
    rows = fillBackgroundRows(&model, &buf);
    try std.testing.expect(rows[1].live);
    try std.testing.expect(rows[1].can_stop);
    try std.testing.expectEqualStrings(monitor_stop_label, rows[1].stop_label);
    stopBackground(&model, &fx, monitor_row_id_first);
    try std.testing.expectEqual(@as(u32, 0), model.background_monitor_count);
    try std.testing.expect(model.is_streaming());
    try std.testing.expect(model.sessionById(id).?.busy);
}

test "hasDismissableSettledBackground is true after settle; live-only streaming is false" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    defer clearLiveMonitors(&model);
    defer clearLiveSubagents(&model);
    const id = model.addSession("env dismiss all helper", .claude);
    model.selected = id;
    try std.testing.expect(!hasDismissableSettledBackground(&model));
    try std.testing.expect(!model.has_dismissable_settled_background());

    model.phase = .streaming;
    model.streaming_session = id;
    try std.testing.expect(!hasDismissableSettledBackground(&model));
    try expectLiveProcessRow(&model);

    noteLiveMonitor(&model, "toolu_mon_helper");
    noteLiveSubagent(&model, "toolu_agent_helper");
    try std.testing.expect(!hasDismissableSettledBackground(&model));

    turn_stream.finishStream(&model, &fx, true);
    try std.testing.expect(hasDismissableSettledBackground(&model));
    try std.testing.expect(model.has_dismissable_settled_background());
    try std.testing.expect(hasSettledBackground(&model));

    dismissSettledBackground(&model);
    try std.testing.expect(!hasDismissableSettledBackground(&model));
    try std.testing.expect(!hasSettledBackground(&model));
    try expectNoBackgroundRows(&model);
}

test "dismissSettledBackground removes settled Monitor Subagent and Process; frees logs; clears selection" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    defer clearLiveMonitors(&model);
    defer clearLiveSubagents(&model);
    const id = model.addSession("env dismiss all settled", .claude);
    model.selected = id;
    model.phase = .streaming;
    model.streaming_session = id;
    if (model.sessionById(id)) |session| session.busy = true;
    noteLiveMonitor(&model, "toolu_mon_all");
    appendLiveMonitorOutput(&model, "toolu_mon_all", "monitor leftover");
    noteLiveSubagent(&model, "toolu_agent_all");
    appendLiveSubagentOutput(&model, "toolu_agent_all", "subagent leftover");
    model.environment_summary_open = true;

    turn_stream.finishStream(&model, &fx, true);
    try std.testing.expect(hasDismissableSettledBackground(&model));
    try std.testing.expectEqual(@as(u32, 1), model.background_monitor_count);
    try std.testing.expectEqual(@as(u32, 1), model.background_subagent_count);
    try std.testing.expectEqual(SettledStatus.completed, model.background_settled);
    try std.testing.expectEqual(id, model.background_settled_session);

    model.right_panel_open = true;
    model.right_panel_tab = right_panel.Tab.background;
    model.right_panel_background_row_id = monitor_row_id_first;
    try std.testing.expectEqualStrings("monitor leftover", backgroundWorkOutput(&model));

    main.update(&model, .environment_dismiss_settled_background, &fx);
    try std.testing.expect(!model.environment_summary_open);
    try std.testing.expectEqual(@as(u32, 0), model.background_monitor_count);
    try std.testing.expectEqual(@as(u32, 0), model.background_subagent_count);
    try std.testing.expectEqual(@as(usize, 0), model.background_monitors[0].output().len);
    try std.testing.expectEqual(@as(usize, 0), model.background_monitors[0].log.output_storage.len);
    try std.testing.expectEqual(@as(usize, 0), model.background_subagents[0].output().len);
    try std.testing.expectEqual(@as(usize, 0), model.background_subagents[0].log.output_storage.len);
    try std.testing.expectEqual(SettledStatus.none, model.background_settled);
    try std.testing.expectEqual(@as(u32, 0), model.background_settled_session);
    try std.testing.expectEqual(@as(u32, 0), model.right_panel_background_row_id);
    try std.testing.expect(selectedBackgroundRow(&model) == null);
    try std.testing.expectEqual(@as(u32, 0), model.background_dismissed_subagent_count);
    try std.testing.expect(!model.is_streaming());
    try std.testing.expect(!hasDismissableSettledBackground(&model));
    try expectNoBackgroundRows(&model);
}

test "dismissSettledBackground leaves live rows and does not stopStream" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    defer clearLiveMonitors(&model);
    defer clearLiveSubagents(&model);
    const id = model.addSession("env dismiss all live stay", .claude);
    model.selected = id;
    model.phase = .streaming;
    model.streaming_session = id;
    if (model.sessionById(id)) |session| session.busy = true;
    noteLiveMonitor(&model, "toolu_mon_old");
    appendLiveMonitorOutput(&model, "toolu_mon_old", "settled keep");
    noteLiveSubagent(&model, "toolu_agent_old");
    appendLiveSubagentOutput(&model, "toolu_agent_old", "settled sub");
    turn_stream.finishStream(&model, &fx, true);

    model.phase = .streaming;
    model.streaming_session = id;
    if (model.sessionById(id)) |session| session.busy = true;
    noteLiveMonitor(&model, "toolu_mon_live");
    appendLiveMonitorOutput(&model, "toolu_mon_live", "live monitor");
    noteLiveSubagent(&model, "toolu_agent_live");
    appendLiveSubagentOutput(&model, "toolu_agent_live", "live subagent");
    try std.testing.expect(hasDismissableSettledBackground(&model));
    try std.testing.expect(model.is_streaming());

    model.right_panel_background_row_id = monitor_row_id_first + 1;
    try std.testing.expectEqualStrings("toolu_mon_live", model.background_monitors[1].toolUseId());

    dismissSettledBackground(&model);
    try std.testing.expect(model.is_streaming());
    try std.testing.expect(model.sessionById(id).?.busy);
    try std.testing.expectEqual(id, model.streaming_session);
    try std.testing.expectEqual(@as(u32, 1), model.background_monitor_count);
    try std.testing.expectEqual(SettledStatus.none, model.background_monitors[0].settled);
    try std.testing.expectEqualStrings("toolu_mon_live", model.background_monitors[0].toolUseId());
    try std.testing.expectEqualStrings("live monitor", model.background_monitors[0].output());
    try std.testing.expectEqual(@as(u32, 1), model.background_subagent_count);
    try std.testing.expectEqual(SettledStatus.none, model.background_subagents[0].settled);
    try std.testing.expectEqualStrings("toolu_agent_live", model.background_subagents[0].parentId());
    try std.testing.expectEqualStrings("live subagent", model.background_subagents[0].output());
    try std.testing.expectEqual(@as(u32, 0), model.background_dismissed_subagent_count);
    try std.testing.expect(!hasDismissableSettledBackground(&model));
    try std.testing.expectEqual(monitor_row_id_first, model.right_panel_background_row_id);
    try std.testing.expect(selectedBackgroundRow(&model).?.live);
    try std.testing.expectEqual(monitor_row_id_first, selectedBackgroundRow(&model).?.id);

    var buf: [max_background_rows]BackgroundRow = undefined;
    const rows = fillBackgroundRows(&model, &buf);
    try std.testing.expectEqual(@as(usize, 3), rows.len);
    try std.testing.expect(rows[0].live);
    try std.testing.expectEqual(BackgroundKind.process, rows[0].kind);
    try std.testing.expect(rows[1].live);
    try std.testing.expectEqual(BackgroundKind.monitor, rows[1].kind);
    try std.testing.expect(rows[2].live);
    try std.testing.expectEqual(BackgroundKind.subagent, rows[2].kind);

    stopBackground(&model, &fx, process_row_id);
    try std.testing.expect(!model.is_streaming());
    try std.testing.expectEqual(SettledStatus.stopped, model.background_settled);
    try std.testing.expectEqual(SettledStatus.stopped, model.background_monitors[0].settled);
    try std.testing.expectEqual(SettledStatus.stopped, model.background_subagents[0].settled);
}

test "dismissSettledBackground is session-scoped" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    defer clearLiveMonitors(&model);
    defer clearLiveSubagents(&model);
    const first = model.addSession("env dismiss all session a", .claude);
    const second = model.addSession("env dismiss all session b", .claude);

    model.selected = first;
    model.phase = .streaming;
    model.streaming_session = first;
    if (model.sessionById(first)) |session| session.busy = true;
    noteLiveMonitor(&model, "toolu_mon_a");
    appendLiveMonitorOutput(&model, "toolu_mon_a", "session a monitor");
    noteLiveSubagent(&model, "toolu_agent_a");
    appendLiveSubagentOutput(&model, "toolu_agent_a", "session a subagent");
    turn_stream.finishStream(&model, &fx, true);

    model.selected = second;
    model.phase = .streaming;
    model.streaming_session = second;
    if (model.sessionById(second)) |session| session.busy = true;
    noteLiveMonitor(&model, "toolu_mon_b");
    appendLiveMonitorOutput(&model, "toolu_mon_b", "session b monitor");
    noteLiveSubagent(&model, "toolu_agent_b");
    appendLiveSubagentOutput(&model, "toolu_agent_b", "session b subagent");
    turn_stream.finishStream(&model, &fx, true);

    try std.testing.expectEqual(@as(u32, 2), model.background_monitor_count);
    try std.testing.expectEqual(@as(u32, 2), model.background_subagent_count);
    try std.testing.expectEqual(second, model.background_settled_session);

    model.selected = first;
    try std.testing.expect(hasDismissableSettledBackground(&model));
    try std.testing.expect(!hasSettledBackground(&model));
    model.right_panel_background_row_id = monitor_row_id_first;
    dismissSettledBackground(&model);
    try std.testing.expectEqual(@as(u32, 1), model.background_monitor_count);
    try std.testing.expectEqualStrings("toolu_mon_b", model.background_monitors[0].toolUseId());
    try std.testing.expectEqualStrings("session b monitor", model.background_monitors[0].output());
    try std.testing.expectEqual(@as(u32, 1), model.background_subagent_count);
    try std.testing.expectEqualStrings("toolu_agent_b", model.background_subagents[0].parentId());
    try std.testing.expectEqualStrings("session b subagent", model.background_subagents[0].output());
    try std.testing.expectEqual(second, model.background_settled_session);
    try std.testing.expectEqual(SettledStatus.completed, model.background_settled);
    try std.testing.expectEqual(@as(u32, 0), model.right_panel_background_row_id);
    try std.testing.expect(!hasDismissableSettledBackground(&model));
    try expectNoBackgroundRows(&model);

    model.selected = second;
    try std.testing.expect(hasDismissableSettledBackground(&model));
    var buf: [max_background_rows]BackgroundRow = undefined;
    const rows = fillBackgroundRows(&model, &buf);
    try std.testing.expectEqual(@as(usize, 3), rows.len);
    try std.testing.expectEqual(BackgroundKind.process, rows[0].kind);
    try std.testing.expectEqual(BackgroundKind.monitor, rows[1].kind);
    try std.testing.expectEqualStrings("session b monitor", rows[1].detail);
    try std.testing.expectEqual(BackgroundKind.subagent, rows[2].kind);
}

test "dismissSettledBackground clears Process-only settle and Process selection" {
    var model = Model{};
    const id = model.addSession("env dismiss all process only", .fx);
    model.selected = id;
    settle(&model, id, .completed);
    try std.testing.expect(hasDismissableSettledBackground(&model));
    model.right_panel_background_row_id = process_row_id;
    model.environment_summary_open = true;
    dismissSettledBackground(&model);
    try std.testing.expect(!model.environment_summary_open);
    try std.testing.expectEqual(SettledStatus.none, model.background_settled);
    try std.testing.expectEqual(@as(u32, 0), model.right_panel_background_row_id);
    try std.testing.expect(!hasDismissableSettledBackground(&model));
    try expectNoBackgroundRows(&model);
}

fn streamingClaudeModel(title: []const u8) Model {
    var model = Model{};
    const id = model.addSession(title, .claude);
    model.selected = id;
    model.phase = .streaming;
    model.streaming_session = id;
    return model;
}

test "Background output cache: first dirty refresh strips CSI; unchanged is a no-op" {
    var model = streamingClaudeModel("cache first refresh");
    defer clearLiveMonitors(&model);
    noteLiveMonitor(&model, "toolu_cache_1");
    appendLiveMonitorOutput(&model, "toolu_cache_1", "\x1b[31mred\x1b[0m");
    try std.testing.expect(backgroundOutputCacheDirty(&model));
    try std.testing.expectEqual(@as(usize, 0), model.background_monitors[0].log.rendered().len);

    try std.testing.expect(refreshBackgroundOutputCache(&model));
    try std.testing.expect(!backgroundOutputCacheDirty(&model));
    model.right_panel_background_row_id = monitor_row_id_first;
    try std.testing.expectEqualStrings("red", backgroundWorkOutput(&model));

    try std.testing.expect(!refreshBackgroundOutputCache(&model));
    try std.testing.expectEqualStrings("red", backgroundWorkOutput(&model));
    try std.testing.expectEqual(model.background_monitors[0].log.rendered().ptr, backgroundWorkOutput(&model).ptr);
}

test "Background output cache throttles a second refresh within 100ms" {
    var model = streamingClaudeModel("cache throttle");
    defer clearLiveMonitors(&model);
    noteLiveMonitor(&model, "toolu_cache_2");
    appendLiveMonitorOutput(&model, "toolu_cache_2", "first");
    try std.testing.expect(refreshBackgroundOutputCache(&model));
    model.right_panel_background_row_id = monitor_row_id_first;
    try std.testing.expectEqualStrings("first", backgroundWorkOutput(&model));

    appendLiveMonitorOutput(&model, "toolu_cache_2", " second");
    try std.testing.expect(backgroundOutputCacheDirty(&model));
    try std.testing.expect(!refreshBackgroundOutputCache(&model));
    try std.testing.expect(backgroundOutputCacheDirty(&model));
    try std.testing.expectEqualStrings("first", backgroundWorkOutput(&model));

    model.now_ms += output_cache_refresh_interval_ms;
    try std.testing.expect(refreshBackgroundOutputCache(&model));
    try std.testing.expect(!backgroundOutputCacheDirty(&model));
    try std.testing.expectEqualStrings("first second", backgroundWorkOutput(&model));
}

test "Background output cache strips CSI split across two appends" {
    var model = streamingClaudeModel("cache split csi");
    defer clearLiveMonitors(&model);
    noteLiveMonitor(&model, "toolu_cache_split");
    appendLiveMonitorOutput(&model, "toolu_cache_split", "\x1b");
    appendLiveMonitorOutput(&model, "toolu_cache_split", "[31mred\x1b[0m");
    try std.testing.expectEqualStrings("\x1b[31mred\x1b[0m", model.background_monitors[0].output());
    try std.testing.expect(refreshBackgroundOutputCache(&model));
    model.right_panel_background_row_id = monitor_row_id_first;
    try std.testing.expectEqualStrings("red", backgroundWorkOutput(&model));
}

test "backgroundWorkOutput returns the cached slice after refresh" {
    var model = streamingClaudeModel("cache slice identity");
    defer clearLiveMonitors(&model);
    noteLiveMonitor(&model, "toolu_cache_ptr");
    appendLiveMonitorOutput(&model, "toolu_cache_ptr", "\x1b[31mred\x1b[0m\nnext");
    model.right_panel_background_row_id = monitor_row_id_first;
    try std.testing.expectEqualStrings("", backgroundWorkOutput(&model));
    try std.testing.expect(refreshBackgroundOutputCache(&model));
    const cached = model.background_monitors[0].log.rendered();
    const panel = backgroundWorkOutput(&model);
    try std.testing.expectEqual(cached.ptr, panel.ptr);
    try std.testing.expectEqual(cached.len, panel.len);
    try std.testing.expectEqualStrings("red\nnext", panel);
}

test "Environment Summary preview updates on append without the render cache" {
    var model = streamingClaudeModel("cache preview vs panel");
    defer clearLiveMonitors(&model);
    noteLiveMonitor(&model, "toolu_cache_preview");
    appendLiveMonitorOutput(&model, "toolu_cache_preview", "\x1b[31mred\x1b[0m\nnext");
    var buf: [max_background_rows]BackgroundRow = undefined;
    const rows = fillBackgroundRows(&model, &buf);
    try std.testing.expectEqualStrings("red next", rows[1].detail);
    try std.testing.expectEqual(@as(usize, 0), model.background_monitors[0].log.rendered().len);
    model.right_panel_background_row_id = monitor_row_id_first;
    try std.testing.expectEqualStrings("", backgroundWorkOutput(&model));
}

test "settle keeps the rendered log; dismiss and remove session free it" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = streamingClaudeModel("cache settle free");
    defer clearLiveMonitors(&model);
    defer clearLiveSubagents(&model);
    const id = model.selected;
    if (model.sessionById(id)) |session| session.busy = true;
    noteLiveMonitor(&model, "toolu_cache_keep");
    appendLiveMonitorOutput(&model, "toolu_cache_keep", "keep after settle");
    noteLiveSubagent(&model, "toolu_cache_sub");
    appendLiveSubagentOutput(&model, "toolu_cache_sub", "sub stay");
    model.right_panel_background_row_id = monitor_row_id_first;
    try std.testing.expectEqualStrings("", backgroundWorkOutput(&model));

    turn_stream.finishStream(&model, &fx, true);
    try std.testing.expect(!backgroundOutputCacheDirty(&model));
    try std.testing.expectEqualStrings("keep after settle", backgroundWorkOutput(&model));
    try std.testing.expectEqual(max_monitor_output, model.background_monitors[0].log.rendered_storage.len);
    model.right_panel_background_row_id = subagent_row_id_first;
    try std.testing.expectEqualStrings("sub stay", backgroundWorkOutput(&model));

    model.phase = .streaming;
    model.streaming_session = id;
    noteLiveMonitor(&model, "toolu_cache_live");
    appendLiveMonitorOutput(&model, "toolu_cache_live", "live log");
    model.now_ms += output_cache_refresh_interval_ms;
    refreshPanelCache(&model);
    try std.testing.expectEqual(max_monitor_output, model.background_monitors[1].log.rendered_storage.len);
    stopBackground(&model, &fx, monitor_row_id_first + 1);
    try std.testing.expectEqual(@as(u32, 1), model.background_monitor_count);
    try std.testing.expectEqualStrings("keep after settle", model.background_monitors[0].output());
    try std.testing.expectEqual(@as(usize, 0), model.background_monitors[1].log.rendered_storage.len);
    try std.testing.expectEqual(@as(usize, 0), model.background_monitors[1].log.output_storage.len);

    clearSettledIfSession(&model, id);
    try std.testing.expectEqual(@as(u32, 0), model.background_monitor_count);
    try std.testing.expectEqual(@as(u32, 0), model.background_subagent_count);
    try std.testing.expectEqual(@as(usize, 0), model.background_monitors[0].log.rendered_storage.len);
    try std.testing.expectEqual(@as(usize, 0), model.background_subagents[0].log.rendered_storage.len);
}

test "trim oldest settled Monitor frees the rendered heap" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = streamingClaudeModel("cache trim free");
    defer clearLiveMonitors(&model);
    var i: usize = 0;
    while (i < max_live_monitors) : (i += 1) {
        var id_buf: [32]u8 = undefined;
        const label = std.fmt.bufPrint(&id_buf, "toolu_cache_trim_{d}", .{i}) catch unreachable;
        noteLiveMonitor(&model, label);
        appendLiveMonitorOutput(&model, label, "old");
    }
    turn_stream.finishStream(&model, &fx, true);
    try std.testing.expectEqual(max_monitor_output, model.background_monitors[0].log.rendered_storage.len);

    model.phase = .streaming;
    model.streaming_session = model.selected;
    noteLiveMonitor(&model, "toolu_cache_trim_new");
    try std.testing.expectEqual(@as(u32, @intCast(max_live_monitors)), model.background_monitor_count);
    try std.testing.expectEqualStrings("toolu_cache_trim_1", model.background_monitors[0].toolUseId());
    try std.testing.expectEqualStrings("toolu_cache_trim_new", model.background_monitors[model.background_monitor_count - 1].toolUseId());
    try std.testing.expectEqual(@as(usize, 0), model.background_monitors[model.background_monitor_count - 1].log.rendered_storage.len);
}

test "Process Background output stays empty after the render cache" {
    var model = streamingClaudeModel("cache process empty");
    defer clearLiveMonitors(&model);
    noteLiveMonitor(&model, "toolu_cache_proc");
    appendLiveMonitorOutput(&model, "toolu_cache_proc", "monitor only");
    refreshPanelCache(&model);
    model.right_panel_background_row_id = process_row_id;
    try std.testing.expectEqualStrings("", backgroundWorkOutput(&model));
}

test "Subagent output cache throttles and strips split CSI" {
    var model = streamingClaudeModel("cache subagent");
    defer clearLiveSubagents(&model);
    noteLiveSubagent(&model, "toolu_cache_sub_split");
    appendLiveSubagentOutput(&model, "toolu_cache_sub_split", "\x1b");
    try std.testing.expect(refreshBackgroundOutputCache(&model));
    appendLiveSubagentOutput(&model, "toolu_cache_sub_split", "[31mred\x1b[0m");
    try std.testing.expect(backgroundOutputCacheDirty(&model));
    try std.testing.expect(!refreshBackgroundOutputCache(&model));
    model.right_panel_background_row_id = subagent_row_id_first;
    try std.testing.expectEqualStrings("\x1b", backgroundWorkOutput(&model));

    model.now_ms += output_cache_refresh_interval_ms;
    try std.testing.expect(refreshBackgroundOutputCache(&model));
    try std.testing.expectEqualStrings("red", backgroundWorkOutput(&model));
    try std.testing.expectEqual(model.background_subagents[0].log.rendered().ptr, backgroundWorkOutput(&model).ptr);
}

