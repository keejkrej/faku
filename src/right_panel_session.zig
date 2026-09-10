//! In-memory per-session Files + Diff directory expand restore.
//!
//! Waku keeps `expanded_paths` / `diff_expanded_paths` on
//! `RightPanelSessionState` and restores via `take_or_closed` (missing
//! key → empty/collapsed). Faku matches that on session switch / New
//! Task / remove: take the leaving session's live sets into a bounded
//! table keyed by session id, then restore the destination (or empty).
//! Not written to `sessions.json`. Cap `max_states` (last-N / LRU when
//! full) so Zig stays bounded — no HashMap growth.
//!
//! Live Files expand still lives on `right_panel_expanded_store` (heap
//! last-window; `file_mention.clearCache` frees it). Live Diff expand
//! still lives on `review_diff_expanded_store` (`review_diff.close`
//! zeroes the count). Stash copies the keys so refresh/close cannot
//! permanently wipe a session you are leaving or returning to. After
//! refresh on enter, restored keys are re-applied into those live
//! stores; unknown/stale keys are ignored by today's tree filter.

const std = @import("std");
const main = @import("main.zig");
const file_mention = @import("file_mention.zig");
const review_diff = @import("review_diff.zig");

const Model = main.Model;
const CachedPath = file_mention.CachedPath;

/// Matches `model.max_sessions`. Fixed table, not an unbounded map.
pub const max_states: usize = 16;

pub const State = struct {
    session_id: u32 = 0,
    stamp: u32 = 0,
    files_store: []CachedPath = &.{},
    files_count: u32 = 0,
    diff_store: []CachedPath = &.{},
    diff_count: u32 = 0,
};

/// Copy the live Files + Diff expand sets under `model.selected`.
/// No-op when nothing is selected. Evicts the least-recently-taken
/// slot when the table is full of other session ids.
pub fn take(model: *Model) void {
    const session_id = model.selected;
    if (session_id == 0) return;
    const slot = slotForTake(model, session_id) orelse return;
    slot.session_id = session_id;
    slot.stamp = bumpStamp(model);
    clonePaths(
        &slot.files_store,
        &slot.files_count,
        model.right_panel_expanded_store,
        model.right_panel_expanded_count,
        file_mention.max_file_mention_dirs,
    );
    clonePaths(
        &slot.diff_store,
        &slot.diff_count,
        &model.review_diff_expanded_store,
        model.review_diff_expanded_count,
        review_diff.max_review_diff_dirs,
    );
}

/// Restore Files + Diff expand for `model.selected`. Missing key is
/// Waku `take_or_closed`: empty/collapsed. Re-applies into the live
/// stores so `clearCache` / `review_diff.close` on the way in cannot
/// keep the leaving session's keys.
pub fn restore(model: *Model) void {
    const session_id = model.selected;
    if (session_id == 0) {
        applyLiveFiles(model, &.{}, 0);
        applyLiveDiff(model, &.{}, 0);
        return;
    }
    const slot = slotById(model, session_id) orelse {
        applyLiveFiles(model, &.{}, 0);
        applyLiveDiff(model, &.{}, 0);
        return;
    };
    applyLiveFiles(model, slot.files_store, slot.files_count);
    applyLiveDiff(model, slot.diff_store, slot.diff_count);
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
    freeSlice(&slot.diff_store);
    slot.diff_count = 0;
    slot.session_id = 0;
    slot.stamp = 0;
}

fn freeSlice(slot: *[]CachedPath) void {
    if (slot.len != 0) {
        std.heap.page_allocator.free(slot.*);
        slot.* = &.{};
    }
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
    const right_panel = @import("right_panel.zig");
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
    setLiveFiles(&model, &.{"src"});
    setLiveDiff(&model, &.{"src"});

    session_actions.handleNewSession(&model, &fx);
    const session_new = model.selected;
    try std.testing.expect(session_new != session_a);
    try std.testing.expectEqual(@as(u32, 0), model.right_panel_expanded_count);
    try std.testing.expectEqual(@as(u32, 0), model.review_diff_expanded_count);
    try std.testing.expect(hasState(&model, session_a));
    try std.testing.expect(!hasState(&model, session_new));

    palette_run.applySessionSelection(&model, &fx, session_a);
    try std.testing.expect(liveFilesHas(&model, "src"));
    try std.testing.expect(liveDiffHas(&model, "src"));
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
