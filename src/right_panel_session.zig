//! In-memory per-session right-panel restore (expand + tab +
//! open/closed + nested Files/Diff list widths + Files/Diff
//! selection + one Files preview editor).
//!
//! Waku keeps `expanded_paths` / `diff_expanded_paths`,
//! `active_surface`, `files_selected_path`, `diff_source`,
//! `diff_selected_file`, `file_editors`, and `file_tree_width` on
//! `RightPanelSessionState` and restores via `take_or_closed`
//! (missing key → empty/collapsed/closed + `DEFAULT_FILE_TREE_WIDTH`
//! 184). Faku matches that on session switch / New Task / remove:
//! take the leaving session's live sets into a bounded table keyed
//! by session id, then restore the destination (or empty). Not
//! written to `sessions.json`. Cap `max_states` (last-N / LRU when
//! full) so Zig stays bounded — no HashMap growth. Faku's single
//! Files preview stashes at most one dirty/editing editor per slot
//! (relpath + draft + disk baseline), capped at the Files preview
//! read window. Nested `file_tree_width` (Waku) and Diff file-list
//! width (Faku parallel, same FILE_TREE clamps) restore from this
//! stash; missing / empty is `DEFAULT_FILE_TREE_WIDTH` 184. Outer
//! `right_panel_width` stays global. `sessions.json` extras remain
//! the last-live global fallback for cold start — not per-session
//! nested widths.
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
//! next fill lands. A stashed dirty/editing Files preview is re-applied
//! after that path reopens. Stale / missing path → closed / no
//! selection (Waku missing-key empty). Diff snapshot bodies stay today's
//! re-fetch; only selection is re-applied.

const std = @import("std");
const main = @import("main.zig");
const file_mention = @import("file_mention.zig");
const review_diff = @import("review_diff.zig");
const right_panel = @import("right_panel.zig");

const Model = main.Model;
const Effects = main.Effects;
const CachedPath = file_mention.CachedPath;

/// Matches `model.max_sessions`. Fixed table, not an unbounded map.
pub const max_states: usize = 16;

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
    /// Dirty/editing Files preview editor (Waku `file_editors`, one
    /// buffer in Faku). Heap last-window, cap
    /// `right_panel.max_file_preview_bytes`. Not sessions.json.
    files_editor: bool = false,
    files_editor_has_disk: bool = false,
    files_editor_draft: []u8 = &.{},
    files_editor_disk: []u8 = &.{},
    /// Nested Files-tree width (Waku `file_tree_width`). Default
    /// `DEFAULT_FILE_TREE_WIDTH` 184. Missing / cleared slot is 184.
    file_tree_width: f32 = main.right_panel_default_width,
    /// Nested Diff file-list width (Faku parallel; same FILE_TREE
    /// clamps). Default 184. Missing / cleared slot is 184.
    diff_file_list_width: f32 = main.right_panel_default_width,
};

/// Copy the live Files + Diff expand sets, tab, panel open/closed,
/// nested Files-tree / Diff list widths, Files preview path, Diff
/// selection, and dirty/editing Files preview editor under
/// `model.selected`. No-op when nothing is selected. Evicts the
/// least-recently-taken slot when the table is full of other session
/// ids.
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
}

/// Restore panel open/closed, nested Files-tree / Diff list widths,
/// tab, Files + Diff expand, Files preview path, Diff selection, and
/// dirty/editing Files preview editor for `model.selected`. Missing
/// key is Waku `take_or_closed`: closed panel, Files tab, collapsed
/// trees, closed preview, no Diff selection, nested widths 184.
/// Re-applies expand into the live stores so `clearCache` /
/// `review_diff.close` on the way in cannot keep the leaving session's
/// keys. Visibility is applied first via `setOpen` so an open
/// restore paints through the existing select helpers. Nested
/// widths land before `applyTab` so Files preview / Diff hunk layouts
/// use this session's splits.
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
        right_panel.clearFilePreview(model);
        clearFilesEditorForSelected(model);
        return;
    };
    right_panel.clearFilePreview(model);
    copyPath(&model.right_panel_session_pending_files, path);
    right_panel.selectCachedFile(model, fx, id);
    if (model.right_panel_file_preview_id != id) {
        model.right_panel_session_pending_files = .{};
        return;
    }
    applyStashedFilesEditor(model);
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
    clearFilesEditor(slot);
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

fn takeFilesEditor(slot: *State, model: *const Model) void {
    clearFilesEditor(slot);
    if (!right_panel.previewEditorStashable(model)) return;
    if (!cloneBytes(&slot.files_editor_draft, model.file_preview_draft())) return;
    slot.files_editor_has_disk = cloneBytes(&slot.files_editor_disk, model.file_preview_body());
    slot.files_editor = true;
}

fn applyStashedFilesEditor(model: *Model) void {
    const slot = slotById(model, model.selected) orelse return;
    if (!slot.files_editor) return;
    const opened = model.file_preview_path();
    const remembered = slot.files_selected.text();
    if (opened.len == 0 or !std.mem.eql(u8, opened, remembered)) return;
    const disk: ?[]const u8 = if (slot.files_editor_has_disk) slot.files_editor_disk else null;
    right_panel.applyRestoredPreviewEditor(model, slot.files_editor_draft, disk);
}

fn clearFilesEditorForSelected(model: *Model) void {
    const slot = slotById(model, model.selected) orelse return;
    clearFilesEditor(slot);
}

fn clearFilesEditor(slot: *State) void {
    freeBytes(&slot.files_editor_draft);
    freeBytes(&slot.files_editor_disk);
    slot.files_editor = false;
    slot.files_editor_has_disk = false;
}

fn hasFilesEditor(model: *const Model, session_id: u32) bool {
    const slot = slotByIdConst(model, session_id) orelse return false;
    return slot.files_editor;
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
/// effects match a tab click.
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
        .background => right_panel.selectBackground(model, fx, 0),
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

    session_actions.handleNewSession(&model, &fx);
    const session_new = model.selected;
    try std.testing.expect(session_new != session_a);
    try std.testing.expectEqual(@as(u32, 0), model.right_panel_expanded_count);
    try std.testing.expectEqual(@as(u32, 0), model.review_diff_expanded_count);
    try std.testing.expectEqual(right_panel.Tab.files, model.right_panel_tab);
    try std.testing.expect(!model.right_panel_open);
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

