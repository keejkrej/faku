//! In-memory per-session right-panel restore (expand + tab +
//! open/closed + nested Files/Diff list widths + Files/Diff
//! selection + bounded Files preview editors + Background selected
//! row + Browser occupancy/histories/active + Terminal
//! occupancy/active).
//!
//! Waku keeps `expanded_paths` / `diff_expanded_paths`,
//! `active_surface`, `files_selected_path`, `diff_source`,
//! `diff_selected_file`, `file_editors`, `file_tree_width`,
//! `RightPanelSurface::BackgroundWork { key, title }`, and Browser
//! / Terminal `surfaces` on `RightPanelSessionState` and restores via
//! `take_or_closed` (missing key → empty/collapsed/closed +
//! `DEFAULT_FILE_TREE_WIDTH` 184). Faku matches that on session switch
//! / New Task / remove: take the leaving session's live sets into a
//! bounded table keyed by session id, then restore the destination
//! (or empty). Not written to `sessions.json`. Cap `max_states`
//! (last-N / LRU when full) so Zig stays bounded — no HashMap growth.
//! First-cut Files preview editors are a bounded in-session table
//! keyed by relpath (cap `max_file_editors` 4, same order of magnitude
//! as Browser / Terminal slots — not an unbounded HashMap). Each
//! entry is relpath + draft + disk baseline, capped at the Files
//! preview read window. Same-session switch-file while dirty/editing
//! upserts the leaving buffer and restores a stashed path on reopen,
//! without Discard. Close / hide still park Discard for the active
//! buffer only. Nested `file_tree_width` (Waku) and Diff file-list
//! width (Faku parallel, same FILE_TREE clamps) restore from this
//! stash; missing / empty is `DEFAULT_FILE_TREE_WIDTH` 184. Outer
//! `right_panel_width` stays global. `sessions.json` extras remain
//! the last-live global fallback for cold start — not per-session
//! nested widths, Browser occupancy, or Terminal occupancy. Background selected row
//! (`right_panel_background_row_id`) restores from this stash;
//! missing / empty / stale → 0. Browser occupancy, committed URLs,
//! history rings/index, and the active index restore from this stash
//! via `browser_pane.capturePersisted` / `restoreFromPersist` (same
//! `PersistedSlot` shape as the global extras); missing / cleared is
//! today's `default_slots` (slot 0 occupied, empty history).
//! `reload_token` stays runtime-only. Occupied Terminal slots and the
//! active index restore from this stash via `pty_terminal.capturePersisted`
//! / `restoreFromPersist` (bool occupancy + active, same shape as the
//! global extras); missing / cleared is today's empty persist (no
//! pending, lazy single spawn on Terminal tab open). Live PTY
//! process / scrollback are not claimed across chat sessions: restore
//! `ptyKill`s the leaving session's live shells (keys 700..703 stay
//! reserved until cancelled, then `spawnShell` re-spawns). Every
//! restore (including missing-key empty) resets Files preview
//! find/replace (Waku `reset_file_search_for_session`): close the bar,
//! clear matches, and clear find + replace buffers.
//!
//! Live Files expand still lives on `right_panel_expanded_store` (heap
//! last-window; `file_mention.clearCache` frees it). Live Diff expand
//! still lives on `review_diff_expanded_store` (`review_diff.close`
//! zeroes the count). Stash copies the keys so refresh/close cannot
//! permanently wipe a session you are leaving or returning to. After
//! refresh on enter, restored keys are re-applied into those live
//! stores; unknown/stale keys are ignored by today's tree filter.
//!
//! Files preview path and Diff selected path are stored as relpaths
//! (not 1-based ids, which churn on each fill). Session switch
//! `refresh` / `review_diff.close` empty those indexes before
//! restore, so a miss at restore time arms a pending path and
//! `afterFilesIndexReady` / `afterDiffTreeReady` re-apply when the
//! next fill lands. A stashed dirty/editing Files preview for that
//! relpath is re-applied after it reopens; other table entries stay
//! parked. Stale / missing path drops that entry and closes (Waku
//! missing-key empty). Diff snapshot bodies stay today's re-fetch;
//! only selection is re-applied.

const std = @import("std");
const main = @import("main.zig");
const file_mention = @import("file_mention.zig");
const review_diff = @import("review_diff.zig");
const right_panel = @import("right_panel.zig");
const file_preview_images = @import("file_preview_images.zig");
const file_preview_details = @import("file_preview_details.zig");
const file_preview_issue_link = @import("file_preview_issue_link.zig");
const browser_pane = @import("browser_pane.zig");
const pty_terminal = @import("pty_terminal.zig");
const open_url = @import("open_url.zig");

const Model = main.Model;
const Effects = main.Effects;
const CachedPath = file_mention.CachedPath;

/// Matches `model.max_sessions`. Fixed table, not an unbounded map.
pub const max_states: usize = 16;

/// In-session dirty/editing Files preview editors (Waku
/// `file_editors`). Cap 4 — same order of magnitude as Browser /
/// Terminal slots. Not an unbounded HashMap. Heap last-window per
/// entry (`right_panel.max_file_preview_bytes`). Not sessions.json.
pub const max_file_editors: usize = 4;

pub const FileEditor = struct {
    path: CachedPath = .{},
    stamp: u32 = 0,
    has_disk: bool = false,
    draft: []u8 = &.{},
    disk: []u8 = &.{},
};

pub const State = struct {
    session_id: u32 = 0,
    stamp: u32 = 0,
    /// Panel open/closed at take. Missing / cleared slot is closed
    /// (Waku `take_or_closed` empty).
    open: bool = false,
    tab: right_panel.Tab = .files,
    files_store: []CachedPath = &.{},
    files_count: u32 = 0,
    files_selected: CachedPath = .{},
    diff_store: []CachedPath = &.{},
    diff_count: u32 = 0,
    diff_selected: CachedPath = .{},
    diff_source: review_diff.Source = .branch,
    /// True when Compare was active or the Diff tab was showing, so a
    /// default `.branch` from a never-opened Review is not restored
    /// over Diff-tab `ensureDiff`'s Uncommitted default.
    diff_source_set: bool = false,
    /// Dirty/editing Files preview editors (Waku `file_editors`).
    /// Bounded table keyed by relpath, cap `max_file_editors`.
    /// Heap last-window, cap `right_panel.max_file_preview_bytes`.
    /// Not sessions.json.
    files_editors: [max_file_editors]FileEditor = [_]FileEditor{.{}} ** max_file_editors,
    files_editor_stamp: u32 = 0,
    /// Nested Files-tree width (Waku `file_tree_width`). Default
    /// `DEFAULT_FILE_TREE_WIDTH` 184. Missing / cleared slot is 184.
    file_tree_width: f32 = main.right_panel_default_width,
    /// Nested Diff file-list width (Faku parallel; same FILE_TREE
    /// clamps). Default 184. Missing / cleared slot is 184.
    diff_file_list_width: f32 = main.right_panel_default_width,
    /// Selected Environment Summary Background row
    /// (`right_panel_background_row_id`). 0 = none. Missing /
    /// cleared slot is 0. Not sessions.json.
    background_row_id: u32 = 0,
    /// Occupied Browser slots + committed URLs + history rings/index
    /// (Waku Browser `surfaces`). Same `PersistedSlot` shape as
    /// `sessions.json` extras `browser_slots` / `browser_histories`;
    /// not written per-session. Slices point at `browser_url_store` /
    /// `browser_history_store`. Missing / cleared → `default_slots`.
    browser_slots: [browser_pane.max_sessions]browser_pane.PersistedSlot = [_]browser_pane.PersistedSlot{.{}} ** browser_pane.max_sessions,
    browser_active: u8 = 0,
    browser_present: bool = false,
    browser_url_store: [browser_pane.max_sessions][]u8 = [_][]u8{&.{}} ** browser_pane.max_sessions,
    browser_history_store: [browser_pane.max_sessions][browser_pane.max_history][]u8 = [_][browser_pane.max_history][]u8{
        [_][]u8{&.{}} ** browser_pane.max_history,
    } ** browser_pane.max_sessions,
    /// Occupied Terminal slots + active index (Waku Terminal
    /// `surfaces`). Same bool occupancy shape as `sessions.json`
    /// extras `terminal_slots` / `terminal_active`; not written
    /// per-session. No heap stores — persist is occupancy only.
    /// Missing / cleared → empty persist (no pending, today's lazy
    /// single spawn).
    terminal_slots: [pty_terminal.max_sessions]bool = [_]bool{false} ** pty_terminal.max_sessions,
    terminal_active: u8 = 0,
    terminal_present: bool = false,
};

/// Copy the live Files + Diff expand sets, tab, panel open/closed,
/// nested Files-tree / Diff list widths, Files preview path, Diff
/// selection, dirty/editing Files preview editors, Background selected
/// row, Browser occupancy / histories / active, and Terminal
/// occupancy / active under `model.selected`. No-op when nothing is
/// selected. Evicts the least-recently-taken slot when the table is
/// full of other session ids. The editor table is the whole bounded
/// map (not a single `files_editor`); take upserts the live preview
/// without dropping other parked paths. Browser uses
/// `browser_pane.capturePersisted` (+ active); `reload_token` is not
/// stashed. Terminal uses `pty_terminal.capturePersisted` (+ active);
/// scrollback / status / live PTY are not stashed.
pub fn take(model: *Model) void {
    const session_id = model.selected;
    if (session_id == 0) return;
    const slot = slotForTake(model, session_id) orelse return;
    slot.session_id = session_id;
    slot.stamp = bumpStamp(model);
    slot.open = model.right_panel_open;
    slot.tab = model.right_panel_tab;
    slot.file_tree_width = fittedNestedListWidth(model, model.right_panel_file_tree_width);
    slot.diff_file_list_width = fittedNestedListWidth(model, model.right_panel_diff_file_list_width);
    slot.background_row_id = model.right_panel_background_row_id;
    clonePaths(
        &slot.files_store,
        &slot.files_count,
        model.right_panel_expanded_store,
        model.right_panel_expanded_count,
        file_mention.max_file_mention_dirs,
    );
    copyPath(&slot.files_selected, liveFilesSelectedPath(model));
    clonePaths(
        &slot.diff_store,
        &slot.diff_count,
        &model.review_diff_expanded_store,
        model.review_diff_expanded_count,
        review_diff.max_review_diff_dirs,
    );
    copyPath(&slot.diff_selected, liveDiffSelectedPath(model));
    slot.diff_source = model.review_diff_source;
    slot.diff_source_set = model.review_diff_active or model.right_panel_tab == .diff;
    takeFilesEditor(slot, model);
    takeBrowser(slot, model);
    takeTerminal(slot, model);
}

/// Restore panel open/closed, nested Files-tree / Diff list widths,
/// tab, Files + Diff expand, Files preview path, Diff selection,
/// dirty/editing Files preview editors, Background selected row, Browser
/// occupancy / histories / active, and Terminal occupancy / active
/// for `model.selected`. Missing key is Waku `take_or_closed`: closed
/// panel, Files tab, collapsed trees, closed preview, empty editor
/// table, no Diff selection, nested widths 184, Background row 0,
/// default Browser (slot 0 occupied, empty history), empty Terminal
/// (no pending, today's lazy single spawn). Re-applies expand into
/// the live stores so `clearCache` / `review_diff.close` on the way
/// in cannot keep the leaving session's keys. Visibility is applied
/// first via `setOpen` so an open restore paints through the existing
/// select helpers. Nested widths land before `applyTab` so Files
/// preview / Diff hunk layouts use this session's splits. Background
/// row is applied before `applyTab` so a Background-tab restore can
/// pass that id into `selectBackground` (including 0, which
/// `selectBackground` itself does not clear). Browser
/// `restoreFromPersist` lands before `applyTab` so a Browser-tab
/// restore parks/snaps the same way a tab click does. Terminal
/// `releaseLive` then `restoreFromPersist` land before `applyTab` so
/// a Terminal-tab restore parks/snaps the same way a tab click does
/// (fresh shells; live PTY / scrollback from the leaving session are
/// torn down first). Every restore resets Files preview find/replace.
pub fn restore(model: *Model, fx: *Effects) void {
    const session_id = model.selected;
    if (session_id == 0) {
        restoreEmpty(model, fx);
        return;
    }
    const slot = slotById(model, session_id) orelse {
        restoreEmpty(model, fx);
        return;
    };
    right_panel.setOpen(model, slot.open);
    applyNestedListWidths(model, slot.file_tree_width, slot.diff_file_list_width);
    applyLiveFiles(model, slot.files_store, slot.files_count);
    applyLiveDiff(model, slot.diff_store, slot.diff_count);
    copyPath(&model.right_panel_session_pending_files, slot.files_selected.text());
    copyPath(&model.right_panel_session_pending_diff, slot.diff_selected.text());
    model.right_panel_session_pending_diff_source = slot.diff_source;
    model.right_panel_session_pending_diff_source_set = slot.diff_source_set;
    right_panel.applyBackgroundRow(model, slot.background_row_id);
    restoreBrowser(model, slot);
    restoreTerminal(model, fx, slot);
    right_panel.resetFilePreviewFindForSession(model);
    applyTab(model, fx, slot.tab);
    afterFilesIndexReady(model, fx);
    afterDiffTreeReady(model, fx);
}

/// Re-open a pending Files preview after the Files index fills
/// (`file_mention.handleExit` / a test refill). No-op when nothing
/// is pending. Empty index keeps the pending path. Non-empty index
/// without that relpath closes the preview (stale).
pub fn afterFilesIndexReady(model: *Model, fx: *Effects) void {
    const pending = model.right_panel_session_pending_files.text();
    if (pending.len == 0) return;
    if (model.file_mention_count == 0) return;
    var path_buf: [file_mention.max_file_mention_path]u8 = undefined;
    const n = @min(pending.len, path_buf.len);
    @memcpy(path_buf[0..n], pending[0..n]);
    const path = path_buf[0..n];
    const id = fileIdForRelpath(model, path) orelse {
        model.right_panel_session_pending_files = .{};
        file_preview_images.drop(model, fx);
        file_preview_details.drop(model);
        right_panel.clearFilePreview(model);
        dropEditorForPath(model, path);
        return;
    };
    file_preview_images.drop(model, fx);
    file_preview_details.drop(model);
    right_panel.clearFilePreview(model);
    copyPath(&model.right_panel_session_pending_files, path);
    right_panel.selectCachedFile(model, fx, id);
    if (model.right_panel_file_preview_id != id) {
        model.right_panel_session_pending_files = .{};
        return;
    }
    applyOpenedFilesEditor(model);
    // Restore-to-edit can land after `selectCachedFile`'s refresh.
    file_preview_details.drop(model);
    file_preview_images.refresh(model, fx);
    file_preview_issue_link.refresh(model, fx);
}

/// Re-select a pending Diff file after the Review tree fills
/// (`review_diff.handleExit` / a test refill). No-op when nothing is
/// pending or Compare is inactive. Empty tree keeps the pending
/// path. Non-empty tree without that path clears selection (stale).
pub fn afterDiffTreeReady(model: *Model, fx: *Effects) void {
    const path = model.right_panel_session_pending_diff.text();
    if (path.len == 0) return;
    if (model.review_diff_file_count == 0) return;
    const id = diffIdForPath(model, path) orelse {
        model.right_panel_session_pending_diff = .{};
        if (model.review_diff_active) model.review_diff_selected_id = 0;
        return;
    };
    if (!model.review_diff_active) return;
    review_diff.selectFile(model, fx, id);
}

/// Drop a session's stash entry. No-op when missing.
pub fn drop(model: *Model, session_id: u32) void {
    if (session_id == 0) return;
    const slot = slotById(model, session_id) orelse return;
    clearSlot(slot);
}

/// Free per-slot path heaps. Tests that `take` should `defer` this
/// (same class as `file_mention.clearCache`). `clearCache` must not
/// call this — refresh would wipe remembered sets.
pub fn freeStores(model: *Model) void {
    for (&model.right_panel_session_store) |*slot| {
        clearSlot(slot);
    }
    model.right_panel_session_stamp = 0;
    clearPending(model);
}

pub fn hasState(model: *const Model, session_id: u32) bool {
    return slotByIdConst(model, session_id) != null;
}

fn bumpStamp(model: *Model) u32 {
    model.right_panel_session_stamp +%= 1;
    if (model.right_panel_session_stamp == 0) model.right_panel_session_stamp = 1;
    return model.right_panel_session_stamp;
}

fn slotById(model: *Model, session_id: u32) ?*State {
    if (session_id == 0) return null;
    for (&model.right_panel_session_store) |*slot| {
        if (slot.session_id == session_id) return slot;
    }
    return null;
}

fn slotByIdConst(model: *const Model, session_id: u32) ?*const State {
    if (session_id == 0) return null;
    for (&model.right_panel_session_store) |*slot| {
        if (slot.session_id == session_id) return slot;
    }
    return null;
}

fn slotForTake(model: *Model, session_id: u32) ?*State {
    if (slotById(model, session_id)) |slot| return slot;
    for (&model.right_panel_session_store) |*slot| {
        if (slot.session_id == 0) return slot;
    }
    return oldestSlot(model);
}

fn oldestSlot(model: *Model) ?*State {
    var best: ?*State = null;
    var best_stamp: u32 = std.math.maxInt(u32);
    for (&model.right_panel_session_store) |*slot| {
        if (slot.session_id == 0) continue;
        if (slot.stamp <= best_stamp) {
            best_stamp = slot.stamp;
            best = slot;
        }
    }
    if (best) |slot| clearSlot(slot);
    return best;
}

fn clearSlot(slot: *State) void {
    freeSlice(&slot.files_store);
    slot.files_count = 0;
    slot.files_selected = .{};
    freeSlice(&slot.diff_store);
    slot.diff_count = 0;
    slot.diff_selected = .{};
    slot.open = false;
    slot.tab = .files;
    slot.diff_source = .branch;
    slot.diff_source_set = false;
    slot.file_tree_width = main.right_panel_default_width;
    slot.diff_file_list_width = main.right_panel_default_width;
    slot.background_row_id = 0;
    clearFilesEditor(slot);
    clearBrowser(slot);
    clearTerminal(slot);
    slot.session_id = 0;
    slot.stamp = 0;
}

fn clearPending(model: *Model) void {
    model.right_panel_session_pending_files = .{};
    model.right_panel_session_pending_diff = .{};
    model.right_panel_session_pending_diff_source_set = false;
}

fn restoreEmpty(model: *Model, fx: *Effects) void {
    right_panel.setOpen(model, false);
    applyNestedListWidths(model, main.right_panel_default_width, main.right_panel_default_width);
    applyLiveFiles(model, &.{}, 0);
    applyLiveDiff(model, &.{}, 0);
    clearPending(model);
    right_panel.applyBackgroundRow(model, 0);
    restoreBrowser(model, null);
    restoreTerminal(model, fx, null);
    right_panel.resetFilePreviewFindForSession(model);
    applyTab(model, fx, .files);
}

fn fittedNestedListWidth(model: *const Model, stored: f32) f32 {
    const raw = if (stored > 0) stored else main.right_panel_default_width;
    return right_panel.clampNestedListWidthForPersist(model.right_panel_width, raw);
}

fn applyNestedListWidths(model: *Model, file_tree_width: f32, diff_file_list_width: f32) void {
    model.right_panel_file_tree_width = fittedNestedListWidth(model, file_tree_width);
    model.right_panel_diff_file_list_width = fittedNestedListWidth(model, diff_file_list_width);
}

/// Upsert the live dirty/editing preview into the current session's
/// table. Same-session switch-file calls this before opening the
/// destination so Discard is not required. Evicts the oldest other
/// path when the table is full — never drops `protect_path`.
pub fn stashLivePreview(model: *Model, protect_path: []const u8) void {
    if (!right_panel.previewEditorStashable(model)) return;
    const path = model.file_preview_path();
    if (path.len == 0) return;
    const slot = slotForSelected(model) orelse return;
    upsertEditor(slot, path, model.file_preview_draft(), model.file_preview_body(), protect_path);
}

/// Re-apply a table entry for the open preview path. No-op when that
/// relpath is missing (Waku HashMap miss → today's disk load).
pub fn applyOpenedFilesEditor(model: *Model) void {
    const slot = slotById(model, model.selected) orelse return;
    const opened = model.file_preview_path();
    const ed = editorByPath(slot, opened) orelse return;
    const disk: ?[]const u8 = if (ed.has_disk) ed.disk else null;
    right_panel.applyRestoredPreviewEditor(model, ed.draft, disk);
    ed.stamp = bumpEditorStamp(slot);
}

/// Drop the open preview's table entry. Discard of the active buffer
/// uses this so other parked editors remain.
pub fn dropOpenedFilesEditor(model: *Model) void {
    dropEditorForPath(model, model.file_preview_path());
}

/// After Save / Reload: upsert when still stashable, else drop this
/// path so a stale dirty draft cannot resurrect.
pub fn syncOpenedFilesEditor(model: *Model) void {
    if (right_panel.previewEditorStashable(model)) {
        stashLivePreview(model, model.file_preview_path());
        return;
    }
    dropOpenedFilesEditor(model);
}

pub fn hasFilesEditor(model: *const Model, session_id: u32) bool {
    return filesEditorCountFor(model, session_id) != 0;
}

pub fn hasFilesEditorPath(model: *const Model, session_id: u32, path: []const u8) bool {
    const slot = slotByIdConst(model, session_id) orelse return false;
    return editorByPathConst(slot, path) != null;
}

pub fn filesEditorCountFor(model: *const Model, session_id: u32) u32 {
    const slot = slotByIdConst(model, session_id) orelse return 0;
    return filesEditorCount(slot);
}

fn takeFilesEditor(slot: *State, model: *const Model) void {
    const path = liveFilesSelectedPath(model);
    if (right_panel.previewEditorStashable(model)) {
        upsertEditor(slot, path, model.file_preview_draft(), model.file_preview_body(), path);
        return;
    }
    if (path.len != 0) dropEditorPath(slot, path);
}

fn takeBrowser(slot: *State, model: *const Model) void {
    var captured: [browser_pane.max_sessions]browser_pane.PersistedSlot = undefined;
    browser_pane.capturePersisted(model, &captured);
    ownBrowserPersisted(slot, &captured);
    slot.browser_active = @intCast(browser_pane.activeIndex(model));
    slot.browser_present = true;
}

fn restoreBrowser(model: *Model, slot: ?*const State) void {
    const stashed = slot orelse {
        browser_pane.restoreFromPersist(model, &.{}, 0);
        return;
    };
    if (!stashed.browser_present) {
        browser_pane.restoreFromPersist(model, &.{}, 0);
        return;
    }
    browser_pane.restoreFromPersist(model, &stashed.browser_slots, stashed.browser_active);
}

fn ownBrowserPersisted(slot: *State, src: *const [browser_pane.max_sessions]browser_pane.PersistedSlot) void {
    clearBrowserHeaps(slot);
    slot.browser_slots = [_]browser_pane.PersistedSlot{.{}} ** browser_pane.max_sessions;
    for (0..browser_pane.max_sessions) |i| {
        const src_slot = src[i];
        if (!src_slot.occupied) continue;
        var owned = browser_pane.PersistedSlot{
            .occupied = true,
            .history_present = src_slot.history_present,
        };
        if (cloneUrl(&slot.browser_url_store[i], src_slot.url)) {
            owned.url = slot.browser_url_store[i];
        }
        const count = @min(src_slot.history_count, browser_pane.max_history);
        var n: usize = 0;
        var j: usize = 0;
        while (j < count) : (j += 1) {
            if (!cloneUrl(&slot.browser_history_store[i][n], src_slot.history_urls[j])) continue;
            owned.history_urls[n] = slot.browser_history_store[i][n];
            n += 1;
        }
        owned.history_count = n;
        owned.history_index = if (n == 0) 0 else @min(src_slot.history_index, n - 1);
        slot.browser_slots[i] = owned;
    }
}

fn clearBrowserHeaps(slot: *State) void {
    for (0..browser_pane.max_sessions) |i| {
        freeBytes(&slot.browser_url_store[i]);
        for (0..browser_pane.max_history) |j| {
            freeBytes(&slot.browser_history_store[i][j]);
        }
    }
}

fn clearBrowser(slot: *State) void {
    clearBrowserHeaps(slot);
    slot.browser_slots = [_]browser_pane.PersistedSlot{.{}} ** browser_pane.max_sessions;
    slot.browser_active = 0;
    slot.browser_present = false;
}

fn takeTerminal(slot: *State, model: *const Model) void {
    pty_terminal.capturePersisted(model, &slot.terminal_slots);
    slot.terminal_active = @intCast(pty_terminal.activeIndex(model));
    slot.terminal_present = true;
}

fn restoreTerminal(model: *Model, fx: *Effects, slot: ?*const State) void {
    pty_terminal.releaseLive(model, fx);
    const stashed = slot orelse {
        pty_terminal.restoreFromPersist(model, &.{}, 0);
        return;
    };
    if (!stashed.terminal_present) {
        pty_terminal.restoreFromPersist(model, &.{}, 0);
        return;
    }
    pty_terminal.restoreFromPersist(model, &stashed.terminal_slots, stashed.terminal_active);
}

fn clearTerminal(slot: *State) void {
    slot.terminal_slots = [_]bool{false} ** pty_terminal.max_sessions;
    slot.terminal_active = 0;
    slot.terminal_present = false;
}

fn cloneUrl(dest: *[]u8, src: []const u8) bool {
    const n = @min(src.len, open_url.max_spawn_url);
    if (n == 0) {
        freeBytes(dest);
        return true;
    }
    if (dest.len != n) {
        freeBytes(dest);
        dest.* = std.heap.page_allocator.alloc(u8, n) catch return false;
    }
    @memcpy(dest.*, src[0..n]);
    return true;
}

fn slotForSelected(model: *Model) ?*State {
    const session_id = model.selected;
    if (session_id == 0) return null;
    const slot = slotForTake(model, session_id) orelse return null;
    if (slot.session_id != session_id) {
        slot.session_id = session_id;
        slot.stamp = bumpStamp(model);
    }
    return slot;
}

fn dropEditorForPath(model: *Model, path: []const u8) void {
    const slot = slotById(model, model.selected) orelse return;
    dropEditorPath(slot, path);
}

fn editorOccupied(ed: *const FileEditor) bool {
    return ed.path.text().len != 0;
}

fn editorByPath(slot: *State, path: []const u8) ?*FileEditor {
    if (path.len == 0) return null;
    for (&slot.files_editors) |*ed| {
        if (std.mem.eql(u8, ed.path.text(), path)) return ed;
    }
    return null;
}

fn editorByPathConst(slot: *const State, path: []const u8) ?*const FileEditor {
    if (path.len == 0) return null;
    for (&slot.files_editors) |*ed| {
        if (std.mem.eql(u8, ed.path.text(), path)) return ed;
    }
    return null;
}

fn emptyEditor(slot: *State) ?*FileEditor {
    for (&slot.files_editors) |*ed| {
        if (!editorOccupied(ed)) return ed;
    }
    return null;
}

fn bumpEditorStamp(slot: *State) u32 {
    slot.files_editor_stamp +%= 1;
    if (slot.files_editor_stamp == 0) slot.files_editor_stamp = 1;
    return slot.files_editor_stamp;
}

fn evictOldestEditor(slot: *State, protect_path: []const u8) ?*FileEditor {
    var best: ?*FileEditor = null;
    var best_stamp: u32 = std.math.maxInt(u32);
    for (&slot.files_editors) |*ed| {
        if (!editorOccupied(ed)) continue;
        if (protect_path.len != 0 and std.mem.eql(u8, ed.path.text(), protect_path)) continue;
        if (ed.stamp <= best_stamp) {
            best_stamp = ed.stamp;
            best = ed;
        }
    }
    if (best) |ed| {
        clearOneEditor(ed);
        return ed;
    }
    return null;
}

fn upsertEditor(
    slot: *State,
    path: []const u8,
    draft: []const u8,
    disk: []const u8,
    protect_path: []const u8,
) void {
    if (path.len == 0) return;
    const ed = editorByPath(slot, path)
        orelse emptyEditor(slot)
        orelse evictOldestEditor(slot, protect_path)
        orelse return;
    copyPath(&ed.path, path);
    if (!cloneBytes(&ed.draft, draft)) {
        clearOneEditor(ed);
        return;
    }
    ed.has_disk = cloneBytes(&ed.disk, disk);
    ed.stamp = bumpEditorStamp(slot);
}

fn dropEditorPath(slot: *State, path: []const u8) void {
    if (editorByPath(slot, path)) |ed| clearOneEditor(ed);
}

fn filesEditorCount(slot: *const State) u32 {
    var n: u32 = 0;
    for (&slot.files_editors) |*ed| {
        if (editorOccupied(ed)) n += 1;
    }
    return n;
}

fn clearOneEditor(ed: *FileEditor) void {
    freeBytes(&ed.draft);
    freeBytes(&ed.disk);
    ed.* = .{};
}

fn clearFilesEditor(slot: *State) void {
    for (&slot.files_editors) |*ed| {
        clearOneEditor(ed);
    }
    slot.files_editor_stamp = 0;
}

fn copyPath(dest: *CachedPath, src: []const u8) void {
    dest.* = .{};
    if (src.len == 0) return;
    dest.set(src);
}

fn liveFilesSelectedPath(model: *const Model) []const u8 {
    if (model.right_panel_file_preview_id == 0) return "";
    return model.file_preview_path();
}

fn liveDiffSelectedPath(model: *const Model) []const u8 {
    const id = model.review_diff_selected_id;
    if (id == 0 or id > model.review_diff_file_count) return "";
    return model.review_diff_file_store[id - 1].path();
}

fn fileIdForRelpath(model: *const Model, relpath: []const u8) ?u32 {
    if (relpath.len == 0) return null;
    var i: usize = 0;
    while (i < model.file_mention_count) : (i += 1) {
        const path = file_mention.cachedPath(model, i);
        if (file_mention.isDirSentinel(path)) continue;
        if (std.mem.eql(u8, path, relpath)) return file_mention.fileMentionId(i);
    }
    return null;
}

fn diffIdForPath(model: *const Model, relpath: []const u8) ?u32 {
    if (relpath.len == 0) return null;
    var i: u32 = 0;
    while (i < model.review_diff_file_count) : (i += 1) {
        if (std.mem.eql(u8, model.review_diff_file_store[i].path(), relpath)) return i + 1;
    }
    return null;
}

/// Restore the tab without opening a closed panel. Restore sets
/// visibility first; when the panel is open, reuse the existing
/// select helpers so Diff starts Compare (pending `diff_source` is
/// consumed by `ensureDiff`), widths bump, and Terminal/Browser side
/// effects match a tab click. Background passes the already-applied
/// `right_panel_background_row_id` (0 after `applyBackgroundRow` is
/// a real none, not a leftover from the previous session).
fn applyTab(model: *Model, fx: *Effects, tab: right_panel.Tab) void {
    if (!model.right_panel_open) {
        if (model.right_panel_tab == .diff and tab != .diff) {
            review_diff.leaveSurface(model);
        }
        model.right_panel_tab = tab;
        return;
    }
    switch (tab) {
        .files => right_panel.selectFiles(model, fx),
        .diff => right_panel.selectDiff(model, fx),
        .browser => right_panel.selectBrowser(model, fx),
        .terminal => right_panel.selectTerminal(model, fx),
        .background => right_panel.selectBackground(model, fx, model.right_panel_background_row_id),
    }
}

fn freeSlice(slot: *[]CachedPath) void {
    if (slot.len != 0) {
        std.heap.page_allocator.free(slot.*);
        slot.* = &.{};
    }
}

fn freeBytes(slot: *[]u8) void {
    if (slot.len != 0) {
        std.heap.page_allocator.free(slot.*);
        slot.* = &.{};
    }
}

fn cloneBytes(dest: *[]u8, src: []const u8) bool {
    const n = @min(src.len, right_panel.max_file_preview_bytes);
    if (n == 0) {
        freeBytes(dest);
        return true;
    }
    if (dest.len != n) {
        freeBytes(dest);
        dest.* = std.heap.page_allocator.alloc(u8, n) catch return false;
    }
    @memcpy(dest.*, src[0..n]);
    return true;
}

fn clonePaths(
    dest: *[]CachedPath,
    dest_count: *u32,
    src: []const CachedPath,
    src_count: u32,
    cap: usize,
) void {
    const n = @min(@min(@as(usize, src_count), src.len), cap);
    if (n == 0) {
        dest_count.* = 0;
        return;
    }
    if (dest.len < n) {
        freeSlice(dest);
        dest.* = std.heap.page_allocator.alloc(CachedPath, n) catch {
            dest_count.* = 0;
            return;
        };
    }
    var i: usize = 0;
    while (i < n) : (i += 1) {
        dest.*[i] = src[i];
    }
    dest_count.* = @intCast(n);
}

fn applyLiveFiles(model: *Model, src: []const CachedPath, src_count: u32) void {
    file_mention.freeExpandedStore(model);
    const n = @min(@as(usize, src_count), src.len);
    if (n == 0) return;
    if (!file_mention.ensureRightPanelExpandedStore(model)) return;
    const cap = @min(n, model.right_panel_expanded_store.len);
    var i: usize = 0;
    while (i < cap) : (i += 1) {
        model.right_panel_expanded_store[i] = src[i];
    }
    model.right_panel_expanded_count = @intCast(cap);
}

fn applyLiveDiff(model: *Model, src: []const CachedPath, src_count: u32) void {
    model.review_diff_expanded_count = 0;
    const n = @min(@min(@as(usize, src_count), src.len), model.review_diff_expanded_store.len);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        model.review_diff_expanded_store[i] = src[i];
    }
    model.review_diff_expanded_count = @intCast(n);
}

fn setLiveFiles(model: *Model, keys: []const []const u8) void {
    file_mention.freeExpandedStore(model);
    if (keys.len == 0) return;
    if (!file_mention.ensureRightPanelExpandedStore(model)) return;
    const n = @min(keys.len, model.right_panel_expanded_store.len);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        model.right_panel_expanded_store[i].set(keys[i]);
    }
    model.right_panel_expanded_count = @intCast(n);
}

fn setLiveDiff(model: *Model, keys: []const []const u8) void {
    model.review_diff_expanded_count = 0;
    const n = @min(keys.len, model.review_diff_expanded_store.len);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        model.review_diff_expanded_store[i].set(keys[i]);
        model.review_diff_expanded_count += 1;
    }
}

fn liveFilesHas(model: *const Model, key: []const u8) bool {
    const n = @min(model.right_panel_expanded_count, model.right_panel_expanded_store.len);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (std.mem.eql(u8, model.right_panel_expanded_store[i].text(), key)) return true;
    }
    return false;
}

fn liveDiffHas(model: *const Model, key: []const u8) bool {
    var i: usize = 0;
    while (i < model.review_diff_expanded_count) : (i += 1) {
        if (std.mem.eql(u8, model.review_diff_expanded_store[i].text(), key)) return true;
    }
    return false;
}

test "Files and Diff expand round-trip across session switch" {
    const palette_run = @import("palette_run.zig");
    var fx = main.Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    defer file_mention.clearCache(&model);
    defer freeStores(&model);

    const session_a = model.addSession("expand a", .fx);
    const session_b = model.addSession("expand b", .fx);
    model.selected = session_a;
    setLiveFiles(&model, &.{ "src", "src/lib" });
    setLiveDiff(&model, &.{"src"});

    palette_run.applySessionSelection(&model, &fx, session_b);
    try std.testing.expectEqual(session_b, model.selected);
    try std.testing.expectEqual(@as(u32, 0), model.right_panel_expanded_count);
    try std.testing.expectEqual(@as(u32, 0), model.review_diff_expanded_count);
    try std.testing.expect(hasState(&model, session_a));
    try std.testing.expect(!hasState(&model, session_b));

    setLiveFiles(&model, &.{"docs"});
    setLiveDiff(&model, &.{"docs"});

    palette_run.applySessionSelection(&model, &fx, session_a);
    try std.testing.expectEqual(session_a, model.selected);
    try std.testing.expectEqual(@as(u32, 2), model.right_panel_expanded_count);
    try std.testing.expect(liveFilesHas(&model, "src"));
    try std.testing.expect(liveFilesHas(&model, "src/lib"));
    try std.testing.expect(!liveFilesHas(&model, "docs"));
    try std.testing.expectEqual(@as(u32, 1), model.review_diff_expanded_count);
    try std.testing.expect(liveDiffHas(&model, "src"));
    try std.testing.expect(!liveDiffHas(&model, "docs"));
    try std.testing.expect(hasState(&model, session_b));

    palette_run.applySessionSelection(&model, &fx, session_b);
    try std.testing.expectEqual(session_b, model.selected);
    try std.testing.expectEqual(@as(u32, 1), model.right_panel_expanded_count);
    try std.testing.expect(liveFilesHas(&model, "docs"));
    try std.testing.expect(!liveFilesHas(&model, "src"));
    try std.testing.expectEqual(@as(u32, 1), model.review_diff_expanded_count);
    try std.testing.expect(liveDiffHas(&model, "docs"));
}

test "restored stale Files keys stay in the store and are ignored by the tree" {
    const palette_run = @import("palette_run.zig");
    var fx = main.Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, "/tmp/faku-expand-stale-{s}", .{tmp.sub_path});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    defer file_mention.clearCache(&model);
    defer freeStores(&model);
    model.store_io = std.testing.io;

    const session_a = model.addSession("stale a", .fx);
    const session_b = model.addSession("stale b", .fx);
    model.selected = session_a;
    model.setSelectedProjectPath(project);
    model.right_panel_open = true;
    file_mention.applyStdoutPaths(&model,
        \\src/main.zig
        \\README.md
    );
    setLiveFiles(&model, &.{ "src", "gone" });

    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    palette_run.applySessionSelection(&model, &fx, session_b);
    palette_run.applySessionSelection(&model, &fx, session_a);
    try std.testing.expect(model.right_panel_open);
    try std.testing.expect(liveFilesHas(&model, "src"));
    try std.testing.expect(liveFilesHas(&model, "gone"));

    model.setSelectedProjectPath(project);
    file_mention.applyStdoutPaths(&model,
        \\src/main.zig
        \\README.md
    );
    const visible = right_panel.rows(&model, arena);
    try std.testing.expectEqual(@as(usize, 3), visible.len);
    try std.testing.expectEqualStrings("README.md", visible[0].path);
    try std.testing.expectEqualStrings("src/", visible[1].path);
    try std.testing.expect(visible[1].expanded);
    try std.testing.expectEqualStrings("src/main.zig", visible[2].path);
    var i: usize = 0;
    while (i < visible.len) : (i += 1) {
        try std.testing.expect(std.mem.indexOf(u8, visible[i].path, "gone") == null);
    }
}

test "remove session drops that stash entry" {
    const palette_run = @import("palette_run.zig");
    const session_actions = @import("session_actions.zig");
    var fx = main.Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    defer file_mention.clearCache(&model);
    defer freeStores(&model);

    const session_a = model.addSession("drop a", .fx);
    const session_b = model.addSession("drop b", .fx);
    model.selected = session_a;
    setLiveFiles(&model, &.{"src"});
    setLiveDiff(&model, &.{"src"});
    palette_run.applySessionSelection(&model, &fx, session_b);
    setLiveFiles(&model, &.{"docs"});
    setLiveDiff(&model, &.{"docs"});
    try std.testing.expect(hasState(&model, session_a));

    model.dropSession(session_a);
    try std.testing.expect(!hasState(&model, session_a));
    try std.testing.expectEqual(session_b, model.selected);

    session_actions.handleRemoveSession(&model, &fx, session_a);
    try std.testing.expect(!hasState(&model, session_a));
    try std.testing.expect(liveFilesHas(&model, "docs"));
    try std.testing.expect(liveDiffHas(&model, "docs"));
}

test "new session starts collapsed; leaving session restores on return" {
    const session_actions = @import("session_actions.zig");
    const palette_run = @import("palette_run.zig");
    var fx = main.Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    defer file_mention.clearCache(&model);
    defer freeStores(&model);

    const session_a = model.addSession("new from", .fx);
    model.selected = session_a;
    model.right_panel_tab = .diff;
    model.showRightPanel();
    setLiveFiles(&model, &.{"src"});
    setLiveDiff(&model, &.{"src"});
    model.right_panel_background_row_id = 1;

    session_actions.handleNewSession(&model, &fx);
    const session_new = model.selected;
    try std.testing.expect(session_new != session_a);
    try std.testing.expectEqual(@as(u32, 0), model.right_panel_expanded_count);
    try std.testing.expectEqual(@as(u32, 0), model.review_diff_expanded_count);
    try std.testing.expectEqual(right_panel.Tab.files, model.right_panel_tab);
    try std.testing.expect(!model.right_panel_open);
    try std.testing.expectEqual(@as(u32, 0), model.right_panel_background_row_id);
    try std.testing.expect(hasState(&model, session_a));
    try std.testing.expect(!hasState(&model, session_new));

    palette_run.applySessionSelection(&model, &fx, session_a);
    try std.testing.expect(liveFilesHas(&model, "src"));
    try std.testing.expect(liveDiffHas(&model, "src"));
    try std.testing.expectEqual(right_panel.Tab.diff, model.right_panel_tab);
    try std.testing.expect(model.right_panel_open);
}

test "stash table evicts the least-recently-taken session when full" {
    var model = Model{};
    defer file_mention.clearCache(&model);
    defer freeStores(&model);

    var i: u32 = 1;
    while (i <= max_states) : (i += 1) {
        model.selected = i;
        setLiveFiles(&model, &.{"src"});
        take(&model);
        try std.testing.expect(hasState(&model, i));
    }
    try std.testing.expect(hasState(&model, 1));
    model.selected = @intCast(max_states + 1);
    setLiveFiles(&model, &.{"docs"});
    take(&model);
    try std.testing.expect(!hasState(&model, 1));
    try std.testing.expect(hasState(&model, 2));
    try std.testing.expect(hasState(&model, @intCast(max_states + 1)));
    try std.testing.expect(liveFilesHas(&model, "docs"));
}

test "tab round-trip across session switch; missing key is Files" {
    const palette_run = @import("palette_run.zig");
    var fx = main.Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    defer file_mention.clearCache(&model);
    defer freeStores(&model);

    const session_a = model.addSession("tab a", .fx);
    const session_b = model.addSession("tab b", .fx);
    model.selected = session_a;
    model.right_panel_tab = .browser;

    palette_run.applySessionSelection(&model, &fx, session_b);
    try std.testing.expectEqual(session_b, model.selected);
    try std.testing.expectEqual(right_panel.Tab.files, model.right_panel_tab);
    try std.testing.expect(!model.right_panel_open);
    try std.testing.expect(hasState(&model, session_a));
    try std.testing.expect(!hasState(&model, session_b));

    model.right_panel_tab = .terminal;
    palette_run.applySessionSelection(&model, &fx, session_a);
    try std.testing.expectEqual(right_panel.Tab.browser, model.right_panel_tab);
    try std.testing.expect(!model.right_panel_open);

    palette_run.applySessionSelection(&model, &fx, session_b);
    try std.testing.expectEqual(right_panel.Tab.terminal, model.right_panel_tab);
    try std.testing.expect(!model.right_panel_open);
}

test "panel open round-trip across session switch; missing key is closed" {
    const palette_run = @import("palette_run.zig");
    var fx = main.Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    defer file_mention.clearCache(&model);
    defer freeStores(&model);

    const session_a = model.addSession("open a", .fx);
    const session_b = model.addSession("open b", .fx);
    model.selected = session_a;
    model.right_panel_file_tree_width = 220;
    right_panel.selectDiff(&model, &fx);
    try std.testing.expect(model.right_panel_open);
    try std.testing.expectEqual(right_panel.Tab.diff, model.right_panel_tab);
    try std.testing.expect(model.review_diff_active);

    palette_run.applySessionSelection(&model, &fx, session_b);
    try std.testing.expectEqual(session_b, model.selected);
    try std.testing.expect(!model.right_panel_open);
    try std.testing.expectEqual(right_panel.Tab.files, model.right_panel_tab);
    try std.testing.expect(!model.review_diff_active);
    try std.testing.expect(!hasState(&model, session_b));
    try std.testing.expectEqual(@as(f32, 184), model.right_panel_file_tree_width);

    palette_run.applySessionSelection(&model, &fx, session_a);
    try std.testing.expect(model.right_panel_open);
    try std.testing.expectEqual(right_panel.Tab.diff, model.right_panel_tab);
    try std.testing.expect(model.review_diff_active);
    try std.testing.expectEqual(@as(f32, 220), model.right_panel_file_tree_width);

    palette_run.applySessionSelection(&model, &fx, session_b);
    try std.testing.expect(!model.right_panel_open);
    try std.testing.expectEqual(right_panel.Tab.files, model.right_panel_tab);
    try std.testing.expect(!model.review_diff_active);
}

test "remove session drops open stash; destination missing is closed" {
    const palette_run = @import("palette_run.zig");
    const session_actions = @import("session_actions.zig");
    var fx = main.Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    defer file_mention.clearCache(&model);
    defer freeStores(&model);

    const session_a = model.addSession("vis drop a", .fx);
    const session_b = model.addSession("vis drop b", .fx);
    model.selected = session_a;
    model.showRightPanel();
    try std.testing.expect(model.right_panel_open);

    palette_run.applySessionSelection(&model, &fx, session_b);
    try std.testing.expect(!model.right_panel_open);

    take(&model);
    model.dropSession(session_b);
    try std.testing.expect(!hasState(&model, session_b));
    try std.testing.expectEqual(session_a, model.selected);
    restore(&model, &fx);
    try std.testing.expect(model.right_panel_open);

    session_actions.handleRemoveSession(&model, &fx, session_b);
    try std.testing.expect(!hasState(&model, session_b));
    try std.testing.expect(model.right_panel_open);

    const session_c = model.addSession("vis drop c", .fx);
    palette_run.applySessionSelection(&model, &fx, session_c);
    try std.testing.expect(!model.right_panel_open);

    take(&model);
    model.dropSession(session_a);
    try std.testing.expect(!hasState(&model, session_a));
    try std.testing.expectEqual(session_c, model.selected);
    restore(&model, &fx);
    try std.testing.expect(!model.right_panel_open);

    session_actions.handleRemoveSession(&model, &fx, session_a);
    try std.testing.expect(!hasState(&model, session_a));
    try std.testing.expect(!model.right_panel_open);
}

test "nested Files tree and Diff list width round-trip across session switch" {
    const palette_run = @import("palette_run.zig");
    const session_actions = @import("session_actions.zig");
    var fx = main.Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    defer file_mention.clearCache(&model);
    defer freeStores(&model);

    const session_a = model.addSession("width a", .fx);
    const session_b = model.addSession("width b", .fx);
    if (model.sessionById(session_a)) |session| session.has_started = true;
    if (model.sessionById(session_b)) |session| session.has_started = true;
    model.selected = session_a;
    model.right_panel_file_tree_width = 248;
    model.right_panel_diff_file_list_width = 220;

    palette_run.applySessionSelection(&model, &fx, session_b);
    try std.testing.expectEqual(session_b, model.selected);
    try std.testing.expect(!hasState(&model, session_b));
    try std.testing.expectEqual(@as(f32, 184), model.right_panel_file_tree_width);
    try std.testing.expectEqual(@as(f32, 184), model.right_panel_diff_file_list_width);

    palette_run.applySessionSelection(&model, &fx, session_a);
    try std.testing.expectEqual(session_a, model.selected);
    try std.testing.expectEqual(@as(f32, 248), model.right_panel_file_tree_width);
    try std.testing.expectEqual(@as(f32, 220), model.right_panel_diff_file_list_width);

    session_actions.handleNewSession(&model, &fx);
    const session_new = model.selected;
    try std.testing.expect(session_new != session_a);
    try std.testing.expect(!hasState(&model, session_new));
    try std.testing.expectEqual(@as(f32, 184), model.right_panel_file_tree_width);
    try std.testing.expectEqual(@as(f32, 184), model.right_panel_diff_file_list_width);

    palette_run.applySessionSelection(&model, &fx, session_a);
    try std.testing.expectEqual(@as(f32, 248), model.right_panel_file_tree_width);
    try std.testing.expectEqual(@as(f32, 220), model.right_panel_diff_file_list_width);

    drop(&model, session_a);
    try std.testing.expect(!hasState(&model, session_a));
    restore(&model, &fx);
    try std.testing.expectEqual(@as(f32, 184), model.right_panel_file_tree_width);
    try std.testing.expectEqual(@as(f32, 184), model.right_panel_diff_file_list_width);
}

test "Files preview path round-trip; stale path closes" {
    const palette_run = @import("palette_run.zig");
    var fx = main.Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, "/tmp/faku-rps-preview-{s}", .{tmp.sub_path});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);
    var abs_buf: [300]u8 = undefined;
    const abs = try std.fmt.bufPrint(&abs_buf, "{s}/note.txt", .{project});
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = abs, .data = "hello\n" });

    var model = Model{};
    defer file_mention.clearCache(&model);
    defer right_panel.clearFilePreview(&model);
    defer freeStores(&model);
    model.store_io = std.testing.io;

    const session_a = model.addSession("preview a", .fx);
    const session_b = model.addSession("preview b", .fx);
    model.selected = session_a;
    model.setSelectedProjectPath(project);
    file_mention.applyStdoutPaths(&model, "note.txt\nREADME.md\n");
    right_panel.selectCachedFile(&model, &fx, 1);
    try std.testing.expectEqual(@as(u32, 1), model.right_panel_file_preview_id);
    try std.testing.expectEqualStrings("note.txt", model.file_preview_path());

    palette_run.applySessionSelection(&model, &fx, session_b);
    try std.testing.expectEqual(@as(u32, 0), model.right_panel_file_preview_id);
    try std.testing.expectEqual(@as(usize, 0), model.file_preview_path().len);

    palette_run.applySessionSelection(&model, &fx, session_a);
    try std.testing.expectEqual(@as(u32, 0), model.right_panel_file_preview_id);
    try std.testing.expectEqualStrings("note.txt", model.right_panel_session_pending_files.text());

    model.setSelectedProjectPath(project);
    file_mention.applyStdoutPaths(&model, "note.txt\nREADME.md\n");
    afterFilesIndexReady(&model, &fx);
    try std.testing.expectEqualStrings("note.txt", model.file_preview_path());
    try std.testing.expect(model.right_panel_file_preview_id != 0);
    try std.testing.expectEqual(@as(usize, 0), model.right_panel_session_pending_files.text().len);

    palette_run.applySessionSelection(&model, &fx, session_b);
    palette_run.applySessionSelection(&model, &fx, session_a);
    model.setSelectedProjectPath(project);
    file_mention.applyStdoutPaths(&model, "README.md\n");
    afterFilesIndexReady(&model, &fx);
    try std.testing.expectEqual(@as(u32, 0), model.right_panel_file_preview_id);
    try std.testing.expectEqual(@as(usize, 0), model.file_preview_path().len);
    try std.testing.expectEqual(@as(usize, 0), model.right_panel_session_pending_files.text().len);
}

test "Diff selected file and source round-trip; stale path clears" {
    const palette_run = @import("palette_run.zig");
    var fx = main.Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    defer file_mention.clearCache(&model);
    defer freeStores(&model);

    const session_a = model.addSession("diff a", .fx);
    const session_b = model.addSession("diff b", .fx);
    model.selected = session_a;
    model.right_panel_tab = .diff;
    model.review_diff_active = true;
    model.review_diff_source = .staged;
    model.review_diff_file_store[0].set('M', "src/a.zig");
    model.review_diff_file_store[1].set('A', "src/b.zig");
    model.review_diff_file_count = 2;
    model.review_diff_selected_id = 2;

    palette_run.applySessionSelection(&model, &fx, session_b);
    try std.testing.expectEqual(right_panel.Tab.files, model.right_panel_tab);
    try std.testing.expectEqual(@as(u32, 0), model.review_diff_selected_id);
    try std.testing.expect(!model.review_diff_active);
    try std.testing.expect(!model.right_panel_open);

    palette_run.applySessionSelection(&model, &fx, session_a);
    try std.testing.expectEqual(right_panel.Tab.diff, model.right_panel_tab);
    try std.testing.expect(!model.right_panel_open);
    try std.testing.expectEqual(@as(u32, 0), model.review_diff_selected_id);
    try std.testing.expectEqualStrings("src/b.zig", model.right_panel_session_pending_diff.text());
    try std.testing.expect(model.right_panel_session_pending_diff_source_set);
    try std.testing.expectEqual(review_diff.Source.staged, model.right_panel_session_pending_diff_source);

    model.review_diff_active = true;
    model.review_diff_file_store[0].set('M', "src/a.zig");
    model.review_diff_file_store[1].set('A', "src/b.zig");
    model.review_diff_file_count = 2;
    afterDiffTreeReady(&model, &fx);
    try std.testing.expectEqual(@as(u32, 2), model.review_diff_selected_id);
    try std.testing.expectEqual(@as(usize, 0), model.right_panel_session_pending_diff.text().len);

    palette_run.applySessionSelection(&model, &fx, session_b);
    palette_run.applySessionSelection(&model, &fx, session_a);
    model.review_diff_active = true;
    model.review_diff_file_store[0].set('M', "src/a.zig");
    model.review_diff_file_count = 1;
    afterDiffTreeReady(&model, &fx);
    try std.testing.expectEqual(@as(u32, 0), model.review_diff_selected_id);
    try std.testing.expectEqual(@as(usize, 0), model.right_panel_session_pending_diff.text().len);
}

fn loadPreviewNote(model: *Model, fx: *Effects, project: []const u8, body: []const u8) !void {
    var abs_buf: [300]u8 = undefined;
    const abs = try std.fmt.bufPrint(&abs_buf, "{s}/note.txt", .{project});
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = abs, .data = body });
    model.store_io = std.testing.io;
    model.setSelectedProjectPath(project);
    model.right_panel_open = true;
    file_mention.applyStdoutPaths(model, "note.txt\nREADME.md\n");
    right_panel.selectCachedFile(model, fx, 1);
}

fn refillPreviewNote(model: *Model, fx: *Effects, project: []const u8) void {
    model.setSelectedProjectPath(project);
    file_mention.applyStdoutPaths(model, "note.txt\nREADME.md\n");
    afterFilesIndexReady(model, fx);
}

test "dirty Files preview stash-and-switch restores draft" {
    const palette_run = @import("palette_run.zig");
    var fx = main.Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, "/tmp/faku-rps-editor-{s}", .{tmp.sub_path});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    defer file_mention.clearCache(&model);
    defer right_panel.clearFilePreview(&model);
    defer freeStores(&model);

    const session_a = model.addSession("editor a", .fx);
    const session_b = model.addSession("editor b", .fx);
    model.selected = session_a;
    try loadPreviewNote(&model, &fx, project, "hello\n");
    right_panel.startFilePreviewEdit(&model);
    right_panel.applyFilePreviewEdit(&model, .{ .insert_text = "dirty" });
    try std.testing.expect(model.file_preview_dirty());
    try std.testing.expectEqualStrings("hello\ndirty", model.file_preview_draft());

    palette_run.applySessionSelection(&model, &fx, session_b);
    try std.testing.expectEqual(session_b, model.selected);
    try std.testing.expect(!model.file_preview_discard_confirm());
    try std.testing.expect(!model.right_panel_file_preview_open());
    try std.testing.expect(!model.file_preview_dirty());
    try std.testing.expect(hasFilesEditor(&model, session_a));
    try std.testing.expect(right_panel.pendingDiscard(&model) == .none);

    palette_run.applySessionSelection(&model, &fx, session_a);
    try std.testing.expectEqual(session_a, model.selected);
    try std.testing.expectEqualStrings("note.txt", model.right_panel_session_pending_files.text());
    refillPreviewNote(&model, &fx, project);
    try std.testing.expectEqualStrings("note.txt", model.file_preview_path());
    try std.testing.expect(model.right_panel_file_preview_editing);
    try std.testing.expect(model.file_preview_dirty());
    try std.testing.expectEqualStrings("hello\ndirty", model.file_preview_draft());
    try std.testing.expectEqualStrings("hello\n", model.file_preview_body());
}

test "clean editing Files preview restores editing without dirty" {
    const palette_run = @import("palette_run.zig");
    var fx = main.Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, "/tmp/faku-rps-editor-clean-{s}", .{tmp.sub_path});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    defer file_mention.clearCache(&model);
    defer right_panel.clearFilePreview(&model);
    defer freeStores(&model);

    const session_a = model.addSession("edit clean a", .fx);
    const session_b = model.addSession("edit clean b", .fx);
    model.selected = session_a;
    try loadPreviewNote(&model, &fx, project, "hello\n");
    right_panel.startFilePreviewEdit(&model);
    try std.testing.expect(model.right_panel_file_preview_editing);
    try std.testing.expect(!model.file_preview_dirty());

    palette_run.applySessionSelection(&model, &fx, session_b);
    try std.testing.expectEqual(session_b, model.selected);
    try std.testing.expect(hasFilesEditor(&model, session_a));

    palette_run.applySessionSelection(&model, &fx, session_a);
    refillPreviewNote(&model, &fx, project);
    try std.testing.expect(model.right_panel_file_preview_editing);
    try std.testing.expect(!model.file_preview_dirty());
    try std.testing.expectEqualStrings("hello\n", model.file_preview_draft());
}

test "missing Files preview editor stash stays empty" {
    const palette_run = @import("palette_run.zig");
    var fx = main.Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, "/tmp/faku-rps-editor-miss-{s}", .{tmp.sub_path});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    defer file_mention.clearCache(&model);
    defer right_panel.clearFilePreview(&model);
    defer freeStores(&model);

    const session_a = model.addSession("editor miss a", .fx);
    const session_b = model.addSession("editor miss b", .fx);
    model.selected = session_a;
    try loadPreviewNote(&model, &fx, project, "hello\n");
    try std.testing.expect(!model.right_panel_file_preview_editing);

    palette_run.applySessionSelection(&model, &fx, session_b);
    try std.testing.expect(!hasFilesEditor(&model, session_a));
    try std.testing.expect(!hasState(&model, session_b));

    palette_run.applySessionSelection(&model, &fx, session_a);
    refillPreviewNote(&model, &fx, project);
    try std.testing.expectEqualStrings("note.txt", model.file_preview_path());
    try std.testing.expect(!model.right_panel_file_preview_editing);
    try std.testing.expect(!model.file_preview_dirty());
    try std.testing.expectEqual(@as(usize, 0), model.file_preview_draft().len);
}

test "drop and freeStores free stashed Files preview editor" {
    const palette_run = @import("palette_run.zig");
    var fx = main.Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, "/tmp/faku-rps-editor-drop-{s}", .{tmp.sub_path});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    defer file_mention.clearCache(&model);
    defer right_panel.clearFilePreview(&model);
    defer freeStores(&model);

    const session_a = model.addSession("editor drop a", .fx);
    const session_b = model.addSession("editor drop b", .fx);
    model.selected = session_a;
    try loadPreviewNote(&model, &fx, project, "hello\n");
    right_panel.startFilePreviewEdit(&model);
    right_panel.applyFilePreviewEdit(&model, .{ .insert_text = "x" });

    palette_run.applySessionSelection(&model, &fx, session_b);
    try std.testing.expect(hasFilesEditor(&model, session_a));
    drop(&model, session_a);
    try std.testing.expect(!hasState(&model, session_a));
    try std.testing.expect(!hasFilesEditor(&model, session_a));

    palette_run.applySessionSelection(&model, &fx, session_a);
    try std.testing.expectEqual(@as(u32, 0), model.right_panel_file_preview_id);
    try std.testing.expect(!model.right_panel_file_preview_editing);
    try std.testing.expect(!model.file_preview_dirty());

    try loadPreviewNote(&model, &fx, project, "hello\n");
    right_panel.startFilePreviewEdit(&model);
    right_panel.applyFilePreviewEdit(&model, .{ .insert_text = "y" });
    take(&model);
    try std.testing.expect(hasFilesEditor(&model, session_a));
    freeStores(&model);
    try std.testing.expect(!hasState(&model, session_a));
    try std.testing.expect(!hasFilesEditor(&model, session_a));
}

test "LRU eviction frees a stashed Files preview editor" {
    var fx = main.Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, "/tmp/faku-rps-editor-lru-{s}", .{tmp.sub_path});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    defer file_mention.clearCache(&model);
    defer right_panel.clearFilePreview(&model);
    defer freeStores(&model);
    const host = model.addSession("lru editor", .fx);
    model.selected = host;
    try loadPreviewNote(&model, &fx, project, "hello\n");
    right_panel.startFilePreviewEdit(&model);
    right_panel.applyFilePreviewEdit(&model, .{ .insert_text = "x" });

    var i: u32 = 1;
    while (i <= max_states) : (i += 1) {
        model.selected = i;
        take(&model);
        try std.testing.expect(hasFilesEditor(&model, i));
    }
    try std.testing.expect(hasFilesEditor(&model, 1));
    model.selected = @intCast(max_states + 1);
    take(&model);
    try std.testing.expect(!hasState(&model, 1));
    try std.testing.expect(!hasFilesEditor(&model, 1));
    try std.testing.expect(hasFilesEditor(&model, 2));
    try std.testing.expect(hasFilesEditor(&model, @intCast(max_states + 1)));
}

test "Background row round-trip across session switch; missing key is 0" {
    const palette_run = @import("palette_run.zig");
    const session_actions = @import("session_actions.zig");
    const environment_summary = @import("environment_summary.zig");
    var fx = main.Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    defer file_mention.clearCache(&model);
    defer freeStores(&model);

    const session_a = model.addSession("bg a", .fx);
    const session_b = model.addSession("bg b", .fx);
    if (model.sessionById(session_a)) |session| session.has_started = true;
    if (model.sessionById(session_b)) |session| session.has_started = true;
    model.selected = session_a;
    environment_summary.settle(&model, session_a, .completed);
    right_panel.selectBackground(&model, &fx, environment_summary.process_row_id);
    try std.testing.expectEqual(environment_summary.process_row_id, model.right_panel_background_row_id);
    try std.testing.expect(model.right_panel_open);
    try std.testing.expectEqual(right_panel.Tab.background, model.right_panel_tab);

    palette_run.applySessionSelection(&model, &fx, session_b);
    try std.testing.expectEqual(session_b, model.selected);
    try std.testing.expectEqual(@as(u32, 0), model.right_panel_background_row_id);
    try std.testing.expect(!hasState(&model, session_b));
    try std.testing.expect(!model.right_panel_open);

    palette_run.applySessionSelection(&model, &fx, session_a);
    try std.testing.expectEqual(session_a, model.selected);
    try std.testing.expectEqual(environment_summary.process_row_id, model.right_panel_background_row_id);
    try std.testing.expectEqual(right_panel.Tab.background, model.right_panel_tab);
    try std.testing.expect(model.right_panel_open);

    palette_run.applySessionSelection(&model, &fx, session_b);
    try std.testing.expectEqual(@as(u32, 0), model.right_panel_background_row_id);

    session_actions.handleNewSession(&model, &fx);
    try std.testing.expectEqual(@as(u32, 0), model.right_panel_background_row_id);

    palette_run.applySessionSelection(&model, &fx, session_a);
    try std.testing.expectEqual(environment_summary.process_row_id, model.right_panel_background_row_id);

    drop(&model, session_a);
    try std.testing.expect(!hasState(&model, session_a));
    restore(&model, &fx);
    try std.testing.expectEqual(@as(u32, 0), model.right_panel_background_row_id);
}

test "stale Background row id restores as 0" {
    const palette_run = @import("palette_run.zig");
    const environment_summary = @import("environment_summary.zig");
    var fx = main.Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    defer file_mention.clearCache(&model);
    defer freeStores(&model);

    const session_a = model.addSession("bg stale a", .fx);
    const session_b = model.addSession("bg stale b", .fx);
    model.selected = session_a;
    environment_summary.settle(&model, session_a, .completed);
    right_panel.selectBackground(&model, &fx, environment_summary.process_row_id);
    try std.testing.expectEqual(environment_summary.process_row_id, model.right_panel_background_row_id);

    palette_run.applySessionSelection(&model, &fx, session_b);
    try std.testing.expectEqual(@as(u32, 0), model.right_panel_background_row_id);
    environment_summary.clearSettled(&model);

    palette_run.applySessionSelection(&model, &fx, session_a);
    try std.testing.expectEqual(@as(u32, 0), model.right_panel_background_row_id);

    model.right_panel_background_row_id = 999;
    palette_run.applySessionSelection(&model, &fx, session_b);
    palette_run.applySessionSelection(&model, &fx, session_a);
    try std.testing.expectEqual(@as(u32, 0), model.right_panel_background_row_id);
}

fn writeNamedPreview(project: []const u8, name: []const u8, body: []const u8) !void {
    var abs_buf: [300]u8 = undefined;
    const abs = try std.fmt.bufPrint(&abs_buf, "{s}/{s}", .{ project, name });
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = abs, .data = body });
}

fn loadLetterPreviews(model: *Model, fx: *Effects, project: []const u8, n: u8) !void {
    var listing: [80]u8 = undefined;
    var list_len: usize = 0;
    var i: u8 = 0;
    while (i < n) : (i += 1) {
        var name_buf: [8]u8 = undefined;
        const name = try std.fmt.bufPrint(&name_buf, "{c}.txt", .{'a' + i});
        var body_buf: [8]u8 = undefined;
        const body = try std.fmt.bufPrint(&body_buf, "{c}\n", .{'a' + i});
        try writeNamedPreview(project, name, body);
        if (list_len != 0) {
            listing[list_len] = '\n';
            list_len += 1;
        }
        @memcpy(listing[list_len..][0..name.len], name);
        list_len += name.len;
    }
    listing[list_len] = '\n';
    list_len += 1;
    model.store_io = std.testing.io;
    model.setSelectedProjectPath(project);
    model.right_panel_open = true;
    file_mention.applyStdoutPaths(model, listing[0..list_len]);
    _ = fx;
}

fn dirtyLetter(model: *Model, fx: *Effects, id: u32, insert: []const u8) void {
    right_panel.selectCachedFile(model, fx, id);
    right_panel.startFilePreviewEdit(model);
    right_panel.applyFilePreviewEdit(model, .{ .insert_text = insert });
}

test "same-session switch-file stashes dirty editor without discard" {
    var fx = main.Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, "/tmp/faku-rps-switch-{s}", .{tmp.sub_path});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    defer file_mention.clearCache(&model);
    defer right_panel.clearFilePreview(&model);
    defer freeStores(&model);

    const session = model.addSession("switch stash", .fx);
    model.selected = session;
    try loadLetterPreviews(&model, &fx, project, 2);
    dirtyLetter(&model, &fx, 1, "x");
    try std.testing.expect(model.file_preview_dirty());

    right_panel.selectCachedFile(&model, &fx, 2);
    try std.testing.expect(!model.file_preview_discard_confirm());
    try std.testing.expect(right_panel.pendingDiscard(&model) == .none);
    try std.testing.expectEqualStrings("b.txt", model.file_preview_path());
    try std.testing.expect(!model.file_preview_dirty());
    try std.testing.expect(hasFilesEditorPath(&model, session, "a.txt"));
    try std.testing.expectEqual(@as(u32, 1), filesEditorCountFor(&model, session));
}

test "reopening a stashed path restores draft and editing" {
    var fx = main.Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, "/tmp/faku-rps-reopen-{s}", .{tmp.sub_path});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    defer file_mention.clearCache(&model);
    defer right_panel.clearFilePreview(&model);
    defer freeStores(&model);

    const session = model.addSession("reopen stash", .fx);
    model.selected = session;
    try loadLetterPreviews(&model, &fx, project, 2);
    dirtyLetter(&model, &fx, 1, "x");
    right_panel.selectCachedFile(&model, &fx, 2);
    dirtyLetter(&model, &fx, 2, "y");
    right_panel.selectCachedFile(&model, &fx, 1);
    try std.testing.expectEqualStrings("a.txt", model.file_preview_path());
    try std.testing.expect(model.right_panel_file_preview_editing);
    try std.testing.expect(model.file_preview_dirty());
    try std.testing.expectEqualStrings("a\nx", model.file_preview_draft());
    try std.testing.expectEqualStrings("a\n", model.file_preview_body());
    try std.testing.expect(hasFilesEditorPath(&model, session, "b.txt"));
}

test "file editor table evicts oldest other path at cap" {
    var fx = main.Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, "/tmp/faku-rps-editor-cap-{s}", .{tmp.sub_path});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    defer file_mention.clearCache(&model);
    defer right_panel.clearFilePreview(&model);
    defer freeStores(&model);

    const session = model.addSession("editor cap", .fx);
    model.selected = session;
    try loadLetterPreviews(&model, &fx, project, 5);
    try std.testing.expectEqual(@as(usize, 4), max_file_editors);

    dirtyLetter(&model, &fx, 1, "1");
    right_panel.selectCachedFile(&model, &fx, 2);
    dirtyLetter(&model, &fx, 2, "2");
    right_panel.selectCachedFile(&model, &fx, 3);
    dirtyLetter(&model, &fx, 3, "3");
    right_panel.selectCachedFile(&model, &fx, 4);
    dirtyLetter(&model, &fx, 4, "4");
    right_panel.selectCachedFile(&model, &fx, 5);
    try std.testing.expectEqual(@as(u32, 4), filesEditorCountFor(&model, session));
    try std.testing.expect(hasFilesEditorPath(&model, session, "a.txt"));
    try std.testing.expect(!hasFilesEditorPath(&model, session, "e.txt"));

    dirtyLetter(&model, &fx, 5, "5");
    right_panel.selectCachedFile(&model, &fx, 1);
    try std.testing.expectEqualStrings("a.txt", model.file_preview_path());
    try std.testing.expectEqualStrings("a\n1", model.file_preview_draft());
    try std.testing.expect(hasFilesEditorPath(&model, session, "a.txt"));
    try std.testing.expect(!hasFilesEditorPath(&model, session, "b.txt"));
    try std.testing.expect(hasFilesEditorPath(&model, session, "c.txt"));
    try std.testing.expect(hasFilesEditorPath(&model, session, "d.txt"));
    try std.testing.expect(hasFilesEditorPath(&model, session, "e.txt"));
    try std.testing.expectEqual(@as(u32, 4), filesEditorCountFor(&model, session));

    right_panel.selectCachedFile(&model, &fx, 2);
    try std.testing.expectEqualStrings("b.txt", model.file_preview_path());
    try std.testing.expect(!model.file_preview_dirty());
    try std.testing.expectEqualStrings("b\n", model.file_preview_body());
}

test "session take/restore copies multiple file editors" {
    const palette_run = @import("palette_run.zig");
    var fx = main.Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, "/tmp/faku-rps-multi-take-{s}", .{tmp.sub_path});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    defer file_mention.clearCache(&model);
    defer right_panel.clearFilePreview(&model);
    defer freeStores(&model);

    const session_a = model.addSession("multi a", .fx);
    const session_b = model.addSession("multi b", .fx);
    model.selected = session_a;
    try loadLetterPreviews(&model, &fx, project, 2);
    dirtyLetter(&model, &fx, 1, "x");
    right_panel.selectCachedFile(&model, &fx, 2);
    dirtyLetter(&model, &fx, 2, "y");
    try std.testing.expectEqual(@as(u32, 1), filesEditorCountFor(&model, session_a));
    try std.testing.expect(hasFilesEditorPath(&model, session_a, "a.txt"));
    try std.testing.expect(!hasFilesEditorPath(&model, session_a, "b.txt"));

    palette_run.applySessionSelection(&model, &fx, session_b);
    try std.testing.expectEqual(@as(u32, 2), filesEditorCountFor(&model, session_a));
    try std.testing.expect(hasFilesEditorPath(&model, session_a, "a.txt"));
    try std.testing.expect(hasFilesEditorPath(&model, session_a, "b.txt"));
    try std.testing.expectEqual(@as(u32, 0), filesEditorCountFor(&model, session_b));
    try std.testing.expect(!hasFilesEditor(&model, session_b));

    palette_run.applySessionSelection(&model, &fx, session_a);
    file_mention.applyStdoutPaths(&model, "a.txt\nb.txt\n");
    afterFilesIndexReady(&model, &fx);
    try std.testing.expectEqualStrings("b.txt", model.file_preview_path());
    try std.testing.expectEqualStrings("b\ny", model.file_preview_draft());
    right_panel.selectCachedFile(&model, &fx, 1);
    try std.testing.expectEqualStrings("a\nx", model.file_preview_draft());
}

test "close/hide discard drops active editor only" {
    var fx = main.Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, "/tmp/faku-rps-discard-active-{s}", .{tmp.sub_path});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    defer file_mention.clearCache(&model);
    defer right_panel.clearFilePreview(&model);
    defer freeStores(&model);

    const session = model.addSession("discard active", .fx);
    model.selected = session;
    try loadLetterPreviews(&model, &fx, project, 2);
    dirtyLetter(&model, &fx, 1, "x");
    right_panel.selectCachedFile(&model, &fx, 2);
    dirtyLetter(&model, &fx, 2, "y");
    try std.testing.expect(hasFilesEditorPath(&model, session, "a.txt"));

    right_panel.closeFilePreview(&model);
    try std.testing.expectEqual(right_panel.PendingDiscard.close_preview, right_panel.pendingDiscard(&model));
    try std.testing.expect(model.file_preview_dirty());
    const intent = right_panel.acceptPendingDiscard(&model);
    try std.testing.expectEqual(right_panel.PendingDiscard.close_preview, intent);
    try std.testing.expect(!hasFilesEditorPath(&model, session, "b.txt"));
    try std.testing.expect(hasFilesEditorPath(&model, session, "a.txt"));
    right_panel.closeFilePreview(&model);
    try std.testing.expect(!model.right_panel_file_preview_open());

    right_panel.selectCachedFile(&model, &fx, 1);
    try std.testing.expectEqualStrings("a\nx", model.file_preview_draft());
    try std.testing.expect(model.file_preview_dirty());

    model.hideRightPanel();
    try std.testing.expectEqual(right_panel.PendingDiscard.hide_panel, right_panel.pendingDiscard(&model));
    _ = right_panel.acceptPendingDiscard(&model);
    model.hideRightPanel();
    try std.testing.expect(!hasFilesEditorPath(&model, session, "a.txt"));
    try std.testing.expectEqual(@as(u32, 0), filesEditorCountFor(&model, session));
}

test "new session and missing key restore empty file editor table" {
    const session_actions = @import("session_actions.zig");
    const palette_run = @import("palette_run.zig");
    var fx = main.Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, "/tmp/faku-rps-editor-empty-{s}", .{tmp.sub_path});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    defer file_mention.clearCache(&model);
    defer right_panel.clearFilePreview(&model);
    defer freeStores(&model);

    const session_a = model.addSession("editor empty a", .fx);
    model.selected = session_a;
    try loadLetterPreviews(&model, &fx, project, 2);
    dirtyLetter(&model, &fx, 1, "x");
    right_panel.selectCachedFile(&model, &fx, 2);
    dirtyLetter(&model, &fx, 2, "y");

    session_actions.handleNewSession(&model, &fx);
    const session_new = model.selected;
    try std.testing.expect(session_new != session_a);
    try std.testing.expect(!hasState(&model, session_new));
    try std.testing.expectEqual(@as(u32, 0), filesEditorCountFor(&model, session_new));
    try std.testing.expect(hasFilesEditorPath(&model, session_a, "a.txt"));
    try std.testing.expect(hasFilesEditorPath(&model, session_a, "b.txt"));

    const session_c = model.addSession("editor empty c", .fx);
    palette_run.applySessionSelection(&model, &fx, session_c);
    try std.testing.expect(!hasState(&model, session_c));
    try std.testing.expectEqual(@as(u32, 0), filesEditorCountFor(&model, session_c));
    try std.testing.expect(!model.right_panel_file_preview_editing);
}

fn expectDefaultEmptyBrowser(model: *const Model) !void {
    try std.testing.expectEqual(@as(usize, 1), browser_pane.occupiedCount(model));
    try std.testing.expect(model.browser_slots[0].occupied);
    try std.testing.expect(!model.browser_slots[1].occupied);
    try std.testing.expect(!model.browser_slots[2].occupied);
    try std.testing.expect(!model.browser_slots[3].occupied);
    try std.testing.expectEqual(@as(u8, 0), model.browser_active);
    try std.testing.expectEqual(@as(usize, 0), model.browser_slots[0].history_count);
    try std.testing.expectEqualStrings("", browser_pane.committedUrlAt(model, 0));
}

fn expectFindReset(model: *const Model) !void {
    try std.testing.expect(!model.file_preview_find_active);
    try std.testing.expectEqual(@as(u32, 0), model.file_preview_find_match_count);
    try std.testing.expectEqual(@as(u32, 0), model.file_preview_find_match_index);
    try std.testing.expectEqual(@as(usize, 0), model.file_preview_find_query().len);
    try std.testing.expectEqual(@as(usize, 0), model.file_preview_find_replace().len);
    try std.testing.expect(!model.file_preview_find_replace_visible);
    try std.testing.expect(!model.file_preview_find_case_sensitive);
    try std.testing.expect(!model.file_preview_find_whole_word);
    try std.testing.expect(!model.file_preview_find_use_regex);
}

test "Browser slots and active round-trip across session switch" {
    const palette_run = @import("palette_run.zig");
    var fx = main.Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    defer file_mention.clearCache(&model);
    defer freeStores(&model);

    const session_a = model.addSession("browser a", .fx);
    const session_b = model.addSession("browser b", .fx);
    model.selected = session_a;
    model.showRightPanel();
    model.right_panel_tab = .browser;
    browser_pane.setDraft(&model, "https://a1.example");
    browser_pane.commitNavigation(&model);
    browser_pane.setDraft(&model, "https://a2.example");
    browser_pane.commitNavigation(&model);
    browser_pane.reload(&model);
    try std.testing.expect(model.browser_slots[0].reload_token != 0);
    browser_pane.newSession(&model);
    browser_pane.setDraft(&model, "https://b.example");
    browser_pane.commitNavigation(&model);
    try std.testing.expectEqual(@as(u8, 1), model.browser_active);
    try std.testing.expectEqual(@as(usize, 2), browser_pane.occupiedCount(&model));
    try std.testing.expectEqualStrings("https://a2.example", browser_pane.committedUrlAt(&model, 0));
    try std.testing.expectEqual(@as(usize, 2), model.browser_slots[0].history_count);
    try std.testing.expectEqual(@as(usize, 1), model.browser_slots[0].history_index);

    palette_run.applySessionSelection(&model, &fx, session_b);
    try std.testing.expectEqual(session_b, model.selected);
    try std.testing.expect(!hasState(&model, session_b));
    try expectDefaultEmptyBrowser(&model);
    try std.testing.expectEqual(@as(u64, 0), model.browser_slots[0].reload_token);
    {
        var panes: [browser_pane.max_sessions]browser_pane.WebViewPane = undefined;
        _ = browser_pane.webPanes(&model, &panes);
        try std.testing.expect(panes[0].anchor == null);
        try std.testing.expectEqualStrings(browser_pane.home_url, panes[0].url);
        try std.testing.expect(panes[1].anchor == null);
        try std.testing.expectEqualStrings(browser_pane.home_url, panes[1].url);
    }

    model.showRightPanel();
    model.right_panel_tab = .browser;
    browser_pane.setDraft(&model, "https://c.example");
    browser_pane.commitNavigation(&model);
    try std.testing.expectEqualStrings("https://c.example", browser_pane.currentUrl(&model));

    palette_run.applySessionSelection(&model, &fx, session_a);
    try std.testing.expectEqual(session_a, model.selected);
    try std.testing.expectEqual(@as(u8, 1), model.browser_active);
    try std.testing.expectEqual(@as(usize, 2), browser_pane.occupiedCount(&model));
    try std.testing.expect(model.browser_slots[0].occupied);
    try std.testing.expect(model.browser_slots[1].occupied);
    try std.testing.expect(!model.browser_slots[2].occupied);
    try std.testing.expectEqualStrings("https://a2.example", browser_pane.committedUrlAt(&model, 0));
    try std.testing.expectEqualStrings("https://b.example", browser_pane.currentUrl(&model));
    try std.testing.expectEqual(@as(usize, 2), model.browser_slots[0].history_count);
    try std.testing.expectEqual(@as(usize, 1), model.browser_slots[0].history_index);
    try std.testing.expectEqual(@as(u64, 0), model.browser_slots[0].reload_token);
    try std.testing.expectEqual(@as(u64, 0), model.browser_slots[1].reload_token);
    try std.testing.expect(model.right_panel_open);
    try std.testing.expectEqual(right_panel.Tab.browser, model.right_panel_tab);
    {
        var panes: [browser_pane.max_sessions]browser_pane.WebViewPane = undefined;
        _ = browser_pane.webPanes(&model, &panes);
        try std.testing.expect(panes[0].anchor == null);
        try std.testing.expectEqualStrings("https://a2.example", panes[0].url);
        try std.testing.expectEqualStrings(browser_pane.web_pane_anchor, panes[1].anchor orelse "");
        try std.testing.expectEqualStrings("https://b.example", panes[1].url);
        try std.testing.expect(panes[2].anchor == null);
        try std.testing.expectEqualStrings(browser_pane.home_url, panes[2].url);
    }

    palette_run.applySessionSelection(&model, &fx, session_b);
    try std.testing.expectEqualStrings("https://c.example", browser_pane.currentUrl(&model));
    try std.testing.expectEqual(@as(usize, 1), browser_pane.occupiedCount(&model));
    try std.testing.expectEqual(@as(u8, 0), model.browser_active);
}

test "missing Browser stash restores default empty slot 0" {
    const palette_run = @import("palette_run.zig");
    const session_actions = @import("session_actions.zig");
    var fx = main.Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    defer file_mention.clearCache(&model);
    defer freeStores(&model);

    const session_a = model.addSession("browser miss a", .fx);
    const session_b = model.addSession("browser miss b", .fx);
    if (model.sessionById(session_a)) |session| session.has_started = true;
    if (model.sessionById(session_b)) |session| session.has_started = true;
    model.selected = session_a;
    browser_pane.setDraft(&model, "https://keep.example");
    browser_pane.commitNavigation(&model);
    browser_pane.newSession(&model);
    browser_pane.setDraft(&model, "https://other.example");
    browser_pane.commitNavigation(&model);
    try std.testing.expectEqual(@as(usize, 2), browser_pane.occupiedCount(&model));

    palette_run.applySessionSelection(&model, &fx, session_b);
    try std.testing.expect(!hasState(&model, session_b));
    try expectDefaultEmptyBrowser(&model);
    try std.testing.expectEqualStrings("", browser_pane.committedUrlAt(&model, 0));
    try std.testing.expect(!std.mem.eql(u8, browser_pane.committedUrlAt(&model, 0), "https://keep.example"));

    session_actions.handleNewSession(&model, &fx);
    try expectDefaultEmptyBrowser(&model);

    palette_run.applySessionSelection(&model, &fx, session_a);
    try std.testing.expectEqual(@as(usize, 2), browser_pane.occupiedCount(&model));
    try std.testing.expectEqualStrings("https://other.example", browser_pane.currentUrl(&model));

    drop(&model, session_a);
    try std.testing.expect(!hasState(&model, session_a));
    restore(&model, &fx);
    try expectDefaultEmptyBrowser(&model);
}

test "Files preview find is inactive and empty after session restore" {
    const palette_run = @import("palette_run.zig");
    var fx = main.Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, "/tmp/faku-rps-find-reset-{s}", .{tmp.sub_path});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    defer file_mention.clearCache(&model);
    defer right_panel.clearFilePreview(&model);
    defer freeStores(&model);

    const session_a = model.addSession("find a", .fx);
    const session_b = model.addSession("find b", .fx);
    model.selected = session_a;
    try loadPreviewNote(&model, &fx, project, "foo bar foo\n");
    right_panel.openFilePreviewFind(&model, true);
    right_panel.applyFilePreviewFindEdit(&model, .{ .insert_text = "foo" });
    right_panel.applyFilePreviewFindReplaceEdit(&model, .{ .insert_text = "baz" });
    right_panel.toggleFilePreviewFindCase(&model);
    right_panel.toggleFilePreviewFindWholeWord(&model);
    try std.testing.expect(model.file_preview_find_active);
    try std.testing.expectEqual(@as(u32, 2), model.file_preview_find_match_count);
    try std.testing.expectEqualStrings("foo", model.file_preview_find_query());
    try std.testing.expectEqualStrings("baz", model.file_preview_find_replace());
    try std.testing.expect(model.file_preview_find_replace_visible);
    try std.testing.expect(model.file_preview_find_case_sensitive);

    palette_run.applySessionSelection(&model, &fx, session_b);
    try expectFindReset(&model);
    try std.testing.expect(!hasState(&model, session_b));

    palette_run.applySessionSelection(&model, &fx, session_a);
    try expectFindReset(&model);
    refillPreviewNote(&model, &fx, project);
    try expectFindReset(&model);
    try std.testing.expectEqualStrings("note.txt", model.file_preview_path());
}

fn occupyEnded(model: *Model, slots: *const [pty_terminal.max_sessions]bool, active: u8) void {
    for (0..pty_terminal.max_sessions) |i| {
        model.term_slots[i] = .{};
        if (slots[i]) model.term_slots[i].ended = true;
    }
    model.term_active = active;
}

fn expectCapturedTerminal(model: *const Model, slots: *const [pty_terminal.max_sessions]bool, active: u8) !void {
    var captured: [pty_terminal.max_sessions]bool = undefined;
    pty_terminal.capturePersisted(model, &captured);
    try std.testing.expectEqualSlices(bool, slots, &captured);
    if (model.term_restore_pending) {
        try std.testing.expectEqual(active, model.term_restore_active);
    }
    try std.testing.expectEqual(active, model.term_active);
}

fn expectEmptyTerminalPersist(model: *const Model) !void {
    try std.testing.expect(!model.term_restore_pending);
    try std.testing.expectEqual(@as(usize, 0), pty_terminal.visibleCount(model));
    var captured: [pty_terminal.max_sessions]bool = undefined;
    pty_terminal.capturePersisted(model, &captured);
    try std.testing.expect(!captured[0]);
    try std.testing.expect(!captured[1]);
    try std.testing.expect(!captured[2]);
    try std.testing.expect(!captured[3]);
}

test "Terminal slots and active round-trip across session switch" {
    const palette_run = @import("palette_run.zig");
    var fx = main.Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    defer file_mention.clearCache(&model);
    defer freeStores(&model);

    const session_a = model.addSession("term a", .fx);
    const session_b = model.addSession("term b", .fx);
    model.selected = session_a;
    model.showRightPanel();
    model.right_panel_tab = .terminal;
    occupyEnded(&model, &.{ true, false, true, false }, 2);
    model.term_slots[0].scrollback = 11;
    try std.testing.expectEqual(@as(u8, 2), model.term_active);
    try std.testing.expectEqual(@as(usize, 2), pty_terminal.visibleCount(&model));

    palette_run.applySessionSelection(&model, &fx, session_b);
    try std.testing.expectEqual(session_b, model.selected);
    try std.testing.expect(!hasState(&model, session_b));
    try expectEmptyTerminalPersist(&model);
    try std.testing.expectEqual(@as(u32, 0), model.term_slots[0].scrollback);
    try std.testing.expect(!model.term_slots[0].ended);
    try std.testing.expect(!model.term_slots[2].ended);

    occupyEnded(&model, &.{ true, false, false, false }, 0);

    palette_run.applySessionSelection(&model, &fx, session_a);
    try std.testing.expectEqual(session_a, model.selected);
    try expectCapturedTerminal(&model, &.{ true, false, true, false }, 2);
    try std.testing.expectEqual(@as(u32, 0), model.term_slots[0].scrollback);
    try std.testing.expect(model.right_panel_open);
    try std.testing.expectEqual(right_panel.Tab.terminal, model.right_panel_tab);
    try std.testing.expect(model.term_slots[0].live);
    try std.testing.expect(!model.term_slots[1].live);
    try std.testing.expect(model.term_slots[2].live);
    try std.testing.expect(!model.term_slots[3].live);
    try std.testing.expectEqual(@as(u8, 2), model.term_active);
    try std.testing.expectEqual(@as(usize, 2), fx.pendingPtyCount());

    palette_run.applySessionSelection(&model, &fx, session_b);
    try std.testing.expect(model.term_restore_pending);
    try expectCapturedTerminal(&model, &.{ true, false, false, false }, 0);
    try std.testing.expect(model.term_slots[0].closing);
    try std.testing.expect(fx.ptyKillRequested(pty_terminal.pty_shell_key));
    try std.testing.expect(fx.ptyKillRequested(pty_terminal.pty_shell_key + 2));
}

test "missing Terminal stash restores empty persist (today's lazy single)" {
    const palette_run = @import("palette_run.zig");
    const session_actions = @import("session_actions.zig");
    var fx = main.Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    defer file_mention.clearCache(&model);
    defer freeStores(&model);

    const session_a = model.addSession("term miss a", .fx);
    const session_b = model.addSession("term miss b", .fx);
    if (model.sessionById(session_a)) |session| session.has_started = true;
    if (model.sessionById(session_b)) |session| session.has_started = true;
    model.selected = session_a;
    occupyEnded(&model, &.{ true, true, false, false }, 1);
    try std.testing.expectEqual(@as(usize, 2), pty_terminal.visibleCount(&model));

    palette_run.applySessionSelection(&model, &fx, session_b);
    try std.testing.expect(!hasState(&model, session_b));
    try expectEmptyTerminalPersist(&model);

    session_actions.handleNewSession(&model, &fx);
    try expectEmptyTerminalPersist(&model);

    palette_run.applySessionSelection(&model, &fx, session_a);
    try std.testing.expect(model.term_restore_pending);
    try expectCapturedTerminal(&model, &.{ true, true, false, false }, 1);

    drop(&model, session_a);
    try std.testing.expect(!hasState(&model, session_a));
    restore(&model, &fx);
    try expectEmptyTerminalPersist(&model);
}

test "New Task restores empty Terminal occupancy; drop clears stash" {
    const session_actions = @import("session_actions.zig");
    const palette_run = @import("palette_run.zig");
    var fx = main.Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    defer file_mention.clearCache(&model);
    defer freeStores(&model);

    const session_a = model.addSession("term new a", .fx);
    model.selected = session_a;
    pty_terminal.spawnShell(&model, &fx);
    pty_terminal.newShell(&model, &fx);
    try std.testing.expect(model.term_slots[0].live);
    try std.testing.expect(model.term_slots[1].live);
    try std.testing.expectEqual(@as(u8, 1), model.term_active);

    session_actions.handleNewSession(&model, &fx);
    const session_new = model.selected;
    try std.testing.expect(session_new != session_a);
    try std.testing.expect(!hasState(&model, session_new));
    try expectEmptyTerminalPersist(&model);
    try std.testing.expect(model.term_slots[0].closing);
    try std.testing.expect(model.term_slots[1].closing);
    try std.testing.expect(fx.ptyKillRequested(pty_terminal.pty_shell_key));
    try std.testing.expect(fx.ptyKillRequested(pty_terminal.pty_shell_key + 1));
    try std.testing.expect(hasState(&model, session_a));

    palette_run.applySessionSelection(&model, &fx, session_a);
    try std.testing.expect(model.term_restore_pending);
    try expectCapturedTerminal(&model, &.{ true, true, false, false }, 1);

    drop(&model, session_a);
    try std.testing.expect(!hasState(&model, session_a));
    restore(&model, &fx);
    try expectEmptyTerminalPersist(&model);
    try std.testing.expect(model.term_slots[0].closing);
    try std.testing.expect(model.term_slots[1].closing);
}

