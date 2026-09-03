//! First-cut Waku right panel: Files tree, Diff tab, and Background.
//!
//! Toggleable pane to the right of the conversation column. Files
//! lists the selected session's project files from the existing
//! `file_mention` cache (`git ls-files --cached --others
//! --exclude-standard`, then the bounded find walk) plus derived
//! parent directories collected there. Diff shows the existing
//! Environment Compare / Review body inline (source chips + status +
//! file list + hunk text) via `review_diff` — not a second git probe
//! stack. Background is a runtime-only surface for the Environment
//! Summary Process / Monitor / Subagent row that was clicked (kind,
//! title, live-or-settled status, Monitor / Subagent 512KB last-window log
//! with newlines kept and CSI/ANSI stripped for display;
//! Environment Summary stays a one-line preview; Stop when the
//! selected row is a live Process, live Monitor, or live Subagent;
//! Dismiss when the selected row is a settled Monitor or Subagent). Tab
//! click with no selected row, or a selected row that is gone, shows
//! "No background work". Not Browser, Terminal (Native has no PTY),
//! Claude CLI TaskStop (Faku-side Monitor and
//! Subagent Stop on one-shot `claude -p` ships; live Stop dismisses
//! that live row and does not invoke TaskStop mid-turn; settled
//! rows offer Dismiss), daemon
//! `refreshBackgroundWork`, GPUI SharedString, or full
//! BackgroundWorkRegistry event/reconcile parity. This cut ships a
//! 100ms CSI-stripped last-window render cache on Monitor / Subagent
//! (piggybacks `now_ms` / the stream tick; Native has no dedicated
//! 100ms timer). First-cut
//! settled Monitor / Subagent stay in the runtime registry after the
//! turn (status from Process settle; Monitor / Subagent last-window kept;
//! Faku-side Dismiss, not Claude TaskStop / daemon
//! `refreshBackgroundWork`; not live after `-p` exits). Not daemon
//! `WorkspaceOperation::listTree` / browseDirectory / readTextFile.
//! Not Waku's 50k-file index (cap 256). Windows stays empty this cut
//! (`file_mention` already skips Windows).
//!
//! Files tab ships a read-only bounded inline file preview (Faku-side
//! `readFileAlloc`, 256KB cap, truncated label when larger, binary /
//! non-UTF-8 honest empty state, unreadable one-line error, newlines
//! kept, runtime-only, cleared on session switch / remove / panel hide;
//! Open in editor still available). Not editing, save, syntax
//! highlighting, live reload, Browser, Terminal (Native has no PTY).
//!
//! Default closed: Waku `RightPanelSessionState::take_or_closed` uses
//! `empty(false)` and persistence `default_right_panel_visibility` is
//! false. Files tab widths are Waku `DEFAULT_FILE_TREE_WIDTH` (184) /
//! `FILE_TREE_MIN_WIDTH` (140) / `FILE_TREE_MAX_WIDTH` (360). Diff and
//! Background bump toward Waku `DEFAULT_RIGHT_PANEL_WIDTH` (460) when
//! the pane is still file-tree-narrow; first-cut max is 460 (Waku
//! `RIGHT_PANEL_MAX_WIDTH` is 1000). Tab, selected Background row, and
//! output are runtime-only (default `files` when the panel opens);
//! not persisted this cut.
//!
//! Directory expand/collapse is a runtime-only set of relative dir
//! paths matching `file_mention.derivedDirParents` (no trailing
//! slash), cap `max_file_mention_dirs`. Empty set = collapsed tree
//! (Waku empty `expanded_paths` HashSet): only depth-0 files and
//! top-level dirs. Not persisted to `sessions.json` this cut (Waku
//! keeps `expanded_paths` on in-memory per-session
//! `RightPanelSessionState`).

const std = @import("std");
const main = @import("main.zig");
const file_mention = @import("file_mention.zig");
const composer = @import("composer.zig");
const open_editor = @import("open_editor.zig");
const review_diff = @import("review_diff.zig");

const Model = main.Model;
const Effects = main.Effects;
const RightPanelFileRow = main.RightPanelFileRow;

/// Runtime-only Files | Diff | Background surface. Default `files`
/// when the panel opens. Background is not persisted.
pub const Tab = enum { files, diff, background };

/// Mild tree indent per `fileMentionDepth`. Sidebar grouped rows use 15px.
pub const indent_step: f32 = 12;

/// Files-tab inline preview read cap (256KB). Truncation is labeled.
pub const max_file_preview_bytes: usize = 256 * 1024;

pub const binary_file_label = "Binary file — not shown";
pub const truncated_file_label = "Truncated — showing first 256 KB";
pub const unreadable_file_label = "Cannot read file";
pub const missing_file_label = "File not found";

/// Files-tree clamp (Waku 184/140/360). Kept for tests and hide/Files.
pub fn clampWidth(width: f32) f32 {
    return clampWidthTab(width, .files);
}

pub fn defaultWidth(tab: Tab) f32 {
    return switch (tab) {
        .files => main.right_panel_default_width,
        .diff, .background => main.right_panel_diff_default_width,
    };
}

pub fn maxWidth(tab: Tab) f32 {
    return switch (tab) {
        .files => main.right_panel_max_width,
        .diff, .background => main.right_panel_diff_max_width,
    };
}

pub fn clampWidthTab(width: f32, tab: Tab) f32 {
    const raw = if (width > 0) width else defaultWidth(tab);
    return @max(main.right_panel_min_width, @min(maxWidth(tab), raw));
}

pub fn restWidth(model: *const Model) f32 {
    const sidebar = if (model.sidebar_collapsed)
        main.sidebar_rail_width
    else if (model.sidebar_last_width > 0)
        model.sidebar_last_width
    else
        main.sidebar_default_width;
    return @max(1, main.window_width - sidebar);
}

pub fn splitForWidth(model: *const Model, width: f32) f32 {
    const rest = restWidth(model);
    const pane = clampWidthTab(width, model.right_panel_tab);
    const conversation = @max(0, rest - pane);
    return conversation / rest;
}

pub fn closedSplit() f32 {
    return 1.0;
}

/// Absolute `project_path` + cached relpath. Empty project or relpath
/// is a miss. Does not invent a file that is not in the cache.
pub fn joinProjectRelpath(project: []const u8, relpath: []const u8, buf: []u8) ?[]const u8 {
    const root = std.mem.trimEnd(u8, project, "/");
    const rel = std.mem.trimStart(u8, relpath, "/");
    if (root.len == 0 or rel.len == 0) return null;
    return std.fmt.bufPrint(buf, "{s}/{s}", .{ root, rel }) catch null;
}

pub fn hasProject(model: *const Model) bool {
    return file_mention.probePath(model).len > 0;
}

pub fn isLoading(model: *const Model) bool {
    return hasProject(model) and model.file_mention_key != 0 and model.file_mention_count == 0;
}

/// `derivedDirParents` spelling: no trailing slash. `src/` → `src`.
pub fn dirKey(path: []const u8) []const u8 {
    return std.mem.trimEnd(u8, path, "/");
}

/// True when every ancestor directory of `path` is in `expanded`.
/// Root files and top-level dirs (parent `""`) are always visible.
/// Unknown expanded keys are ignored.
pub fn ancestorsExpanded(path: []const u8, expanded: []const []const u8) bool {
    var parent = composer.fileMentionParent(path);
    while (parent.len > 0) {
        if (!containsKey(expanded, parent)) return false;
        parent = composer.fileMentionParent(parent);
    }
    return true;
}

fn containsKey(keys: []const []const u8, needle: []const u8) bool {
    for (keys) |item| {
        if (std.mem.eql(u8, item, needle)) return true;
    }
    return false;
}

pub fn expandedKeys(model: *const Model, buf: [][]const u8) []const []const u8 {
    const n = @min(model.right_panel_expanded_count, buf.len);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        buf[i] = model.right_panel_expanded_store[i].text();
    }
    return buf[0..n];
}

pub fn isDirExpanded(model: *const Model, path: []const u8) bool {
    const key = dirKey(path);
    if (key.len == 0) return false;
    var buf: [file_mention.max_file_mention_dirs][]const u8 = undefined;
    return containsKey(expandedKeys(model, &buf), key);
}

pub fn rows(model: *const Model, arena: std.mem.Allocator) []const RightPanelFileRow {
    if (!model.right_panel_open) return &.{};
    if (model.right_panel_tab != .files) return &.{};
    if (!hasProject(model)) return &.{};
    if (model.file_mention_count == 0) return &.{};

    var key_buf: [file_mention.max_file_mention_dirs][]const u8 = undefined;
    const expanded = expandedKeys(model, &key_buf);

    var parents: [file_mention.max_file_mention_dirs][]const u8 = undefined;
    const dir_n = file_mention.derivedDirParents(model, &parents);
    const file_n = model.file_mention_count;
    const cap = dir_n + file_n;
    const out = arena.alloc(RightPanelFileRow, cap) catch return &.{};
    var n: usize = 0;
    for (parents[0..dir_n], 0..) |parent, dir_index| {
        const path = std.fmt.allocPrint(arena, "{s}/", .{parent}) catch continue;
        if (!ancestorsExpanded(path, expanded)) continue;
        out[n] = makeRow(path, file_mention.dirMentionId(dir_index), false, containsKey(expanded, parent), false);
        n += 1;
    }
    var file_i: usize = 0;
    while (file_i < file_n) : (file_i += 1) {
        const path = file_mention.cachedPath(model, file_i);
        if (!ancestorsExpanded(path, expanded)) continue;
        const file_id = file_mention.fileMentionId(file_i);
        out[n] = makeRow(path, file_id, true, false, model.right_panel_file_preview_id == file_id);
        n += 1;
    }
    const lessThan = struct {
        fn lessThan(_: void, a: RightPanelFileRow, b: RightPanelFileRow) bool {
            const order = std.mem.order(u8, a.path, b.path);
            if (order != .eq) return order == .lt;
            return a.id < b.id;
        }
    }.lessThan;
    std.mem.sort(RightPanelFileRow, out[0..n], {}, lessThan);
    return out[0..n];
}

fn makeRow(path: []const u8, id: u32, is_file: bool, expanded: bool, selected: bool) RightPanelFileRow {
    const name = composer.fileMentionBasename(path);
    const parent = composer.fileMentionParent(path);
    const depth = composer.fileMentionDepth(path);
    return .{
        .id = id,
        .path = path,
        .name = name,
        .parent = parent,
        .has_parent = parent.len > 0,
        .is_file = is_file,
        .expanded = expanded,
        .depth = depth,
        .has_indent = depth > 0,
        .indent = @as(f32, @floatFromInt(depth)) * indent_step,
        .selected = selected,
    };
}

/// Toggle a derived-dir id in the runtime expanded set. File ids and
/// missing dir ids are no-ops. Cap is `max_file_mention_dirs`.
pub fn toggleDir(model: *Model, id: u32) void {
    if (id < file_mention.file_mention_dir_id_base) return;
    var rel_buf: [file_mention.max_file_mention_path + 1]u8 = undefined;
    const rel = file_mention.mentionRelpath(model, id, &rel_buf) orelse return;
    const key = dirKey(rel);
    if (key.len == 0) return;
    if (indexOfExpanded(model, key)) |index| {
        removeExpandedAt(model, index);
        return;
    }
    if (model.right_panel_expanded_count >= file_mention.max_file_mention_dirs) return;
    model.right_panel_expanded_store[model.right_panel_expanded_count].set(key);
    model.right_panel_expanded_count += 1;
}

fn indexOfExpanded(model: *const Model, key: []const u8) ?usize {
    var i: usize = 0;
    while (i < model.right_panel_expanded_count) : (i += 1) {
        if (std.mem.eql(u8, model.right_panel_expanded_store[i].text(), key)) return i;
    }
    return null;
}

fn removeExpandedAt(model: *Model, index: usize) void {
    if (index >= model.right_panel_expanded_count) return;
    var i = index;
    while (i + 1 < model.right_panel_expanded_count) : (i += 1) {
        model.right_panel_expanded_store[i] = model.right_panel_expanded_store[i + 1];
    }
    model.right_panel_expanded_count -= 1;
}

/// Files tab. Opens the pane if closed. Clamps width to the file-tree max.
pub fn selectFiles(model: *Model, fx: *Effects) void {
    const was_open = model.right_panel_open;
    model.right_panel_open = true;
    model.right_panel_tab = .files;
    model.right_panel_width = clampWidthTab(model.right_panel_width, .files);
    model.syncRightPanelSplit();
    if (!was_open) file_mention.refresh(model, fx);
}

/// Diff tab. Opens the pane if closed, selects Diff, bumps width toward
/// 460 when still file-tree-narrow, and starts/refreshes Compare
/// (Uncommitted when none is active; keeps the current source otherwise).
pub fn selectDiff(model: *Model, fx: *Effects) void {
    const was_open = model.right_panel_open;
    model.right_panel_open = true;
    bumpWideTabWidth(model);
    model.right_panel_tab = .diff;
    model.right_panel_width = clampWidthTab(model.right_panel_width, .diff);
    model.syncRightPanelSplit();
    if (!was_open) file_mention.refresh(model, fx);
    review_diff.ensureDiff(model, fx);
}

/// Background tab. Opens the pane if closed, selects Background, and
/// bumps width toward 460 when still file-tree-narrow (same clamp as
/// Diff). Non-zero `row_id` stores the selected Environment Summary
/// row; `0` is the tab click (keep the current selection, empty
/// state when none / gone). Does not persist the tab or row.
pub fn selectBackground(model: *Model, fx: *Effects, row_id: u32) void {
    const was_open = model.right_panel_open;
    model.right_panel_open = true;
    if (row_id != 0) model.right_panel_background_row_id = row_id;
    bumpWideTabWidth(model);
    model.right_panel_tab = .background;
    model.right_panel_width = clampWidthTab(model.right_panel_width, .background);
    model.syncRightPanelSplit();
    if (!was_open) file_mention.refresh(model, fx);
}

fn bumpWideTabWidth(model: *Model) void {
    if (model.right_panel_width <= main.right_panel_max_width) {
        model.right_panel_width = main.right_panel_diff_default_width;
    }
}

pub fn clearFilePreview(model: *Model) void {
    if (model.right_panel_file_preview_storage.len != 0) {
        std.heap.page_allocator.free(model.right_panel_file_preview_storage);
    }
    model.right_panel_file_preview_storage = &.{};
    model.right_panel_file_preview_len = 0;
    model.right_panel_file_preview_id = 0;
    model.right_panel_file_preview_relpath_len = 0;
    model.right_panel_file_preview_abs_len = 0;
    model.right_panel_file_preview_truncated = false;
    model.right_panel_file_preview_binary = false;
    model.right_panel_file_preview_error_len = 0;
}

fn setPreviewError(model: *Model, message: []const u8) void {
    main.writeFixed(
        &model.right_panel_file_preview_error_storage,
        &model.right_panel_file_preview_error_len,
        message,
    );
}

fn previewReadError(err: anyerror) []const u8 {
    return switch (err) {
        error.FileNotFound => missing_file_label,
        else => unreadable_file_label,
    };
}

const PreviewWindow = struct {
    bytes: []u8,
    truncated: bool,
};

/// `readFileAlloc` + `.limited` errors with `StreamTooLong` when the file
/// size reaches the cap. That path then reads the first 256KB via
/// `File.Reader` and labels truncation from `stat`.
fn readPreviewWindow(io: std.Io, abs: []const u8) !PreviewWindow {
    const bytes = std.Io.Dir.cwd().readFileAlloc(
        io,
        abs,
        std.heap.page_allocator,
        .limited(max_file_preview_bytes),
    ) catch |err| {
        if (err != error.StreamTooLong) return err;
        return readCappedHead(io, abs);
    };
    return .{ .bytes = bytes, .truncated = false };
}

fn readCappedHead(io: std.Io, abs: []const u8) !PreviewWindow {
    var file = try std.Io.Dir.cwd().openFile(io, abs, .{});
    defer file.close(io);
    const size = (try file.stat(io)).size;
    const take: usize = @intCast(@min(size, max_file_preview_bytes));
    const truncated = size > max_file_preview_bytes;
    const buf = try std.heap.page_allocator.alloc(u8, take);
    errdefer std.heap.page_allocator.free(buf);
    if (take > 0) {
        var file_reader = file.reader(io, &.{});
        file_reader.interface.readSliceAll(buf) catch return error.Unexpected;
    }
    return .{ .bytes = buf, .truncated = truncated };
}

/// Longest valid UTF-8 prefix. `null` when a complete sequence is invalid
/// (including a NUL byte). Incomplete tail after a cap is dropped.
fn utf8PreviewPrefix(bytes: []const u8) ?[]const u8 {
    if (std.mem.indexOfScalar(u8, bytes, 0) != null) return null;
    var i: usize = 0;
    while (i < bytes.len) {
        const len = std.unicode.utf8ByteSequenceLength(bytes[i]) catch return null;
        if (i + len > bytes.len) return bytes[0..i];
        _ = std.unicode.utf8Decode(bytes[i..][0..len]) catch return null;
        i += len;
    }
    return bytes;
}

fn loadFilePreviewBody(model: *Model) void {
    const abs = model.right_panel_file_preview_abs_storage[0..model.right_panel_file_preview_abs_len];
    const io = model.store_io;
    if (io == null or abs.len == 0) {
        setPreviewError(model, unreadable_file_label);
        return;
    }
    const read = readPreviewWindow(io.?, abs) catch |err| {
        setPreviewError(model, previewReadError(err));
        return;
    };
    defer std.heap.page_allocator.free(read.bytes);

    const raw = if (read.truncated)
        read.bytes[0..@min(read.bytes.len, max_file_preview_bytes)]
    else
        read.bytes;
    const window = utf8PreviewPrefix(raw) orelse {
        model.right_panel_file_preview_binary = true;
        return;
    };

    const buf = std.heap.page_allocator.alloc(u8, window.len) catch {
        setPreviewError(model, unreadable_file_label);
        return;
    };
    @memcpy(buf, window);
    model.right_panel_file_preview_storage = buf;
    model.right_panel_file_preview_len = window.len;
    model.right_panel_file_preview_truncated = read.truncated;
}

/// Files-pane file click: select the row and load a bounded read-only
/// inline preview. Does not open an external editor.
pub fn selectCachedFile(model: *Model, id: u32) void {
    if (id == 0 or id >= file_mention.file_mention_dir_id_base) return;
    var rel_buf: [file_mention.max_file_mention_path + 1]u8 = undefined;
    const rel = file_mention.mentionRelpath(model, id, &rel_buf) orelse return;
    const project = model.selectedProjectPath();
    var abs_buf: [open_editor.max_open_path]u8 = undefined;
    const abs = joinProjectRelpath(project, rel, &abs_buf) orelse return;

    clearFilePreview(model);
    model.right_panel_file_preview_id = id;
    main.writeFixed(
        &model.right_panel_file_preview_relpath_storage,
        &model.right_panel_file_preview_relpath_len,
        rel,
    );
    main.writeFixed(
        &model.right_panel_file_preview_abs_storage,
        &model.right_panel_file_preview_abs_len,
        abs,
    );
    loadFilePreviewBody(model);
}

/// Files-pane preview header: Open in editor at the stored absolute path.
pub fn openPreviewInEditor(model: *Model, fx: *Effects) void {
    if (model.right_panel_file_preview_id == 0) return;
    const abs = model.right_panel_file_preview_abs_storage[0..model.right_panel_file_preview_abs_len];
    if (abs.len == 0) return;
    open_editor.startOpenEditorAt(model, fx, abs);
}

pub fn openCachedFile(model: *Model, fx: *Effects, id: u32) void {
    selectCachedFile(model, id);
    _ = fx;
}

test "file-tree widths match Waku DEFAULT_FILE_TREE / FILE_TREE_MIN / MAX" {
    try std.testing.expectEqual(@as(f32, 184), main.right_panel_default_width);
    try std.testing.expectEqual(@as(f32, 140), main.right_panel_min_width);
    try std.testing.expectEqual(@as(f32, 360), main.right_panel_max_width);
    try std.testing.expectEqual(@as(f32, 184), clampWidth(0));
    try std.testing.expectEqual(@as(f32, 140), clampWidth(100));
    try std.testing.expectEqual(@as(f32, 360), clampWidth(500));
    try std.testing.expectEqual(@as(f32, 200), clampWidth(200));
}

test "Diff tab default 460 / max 460; Background shares Diff clamp; Files clamp stays 360" {
    try std.testing.expectEqual(@as(f32, 460), main.right_panel_diff_default_width);
    try std.testing.expectEqual(@as(f32, 460), main.right_panel_diff_max_width);
    try std.testing.expectEqual(@as(f32, 460), clampWidthTab(0, .diff));
    try std.testing.expectEqual(@as(f32, 140), clampWidthTab(100, .diff));
    try std.testing.expectEqual(@as(f32, 460), clampWidthTab(500, .diff));
    try std.testing.expectEqual(@as(f32, 400), clampWidthTab(400, .diff));
    try std.testing.expectEqual(@as(f32, 460), clampWidthTab(0, .background));
    try std.testing.expectEqual(@as(f32, 140), clampWidthTab(100, .background));
    try std.testing.expectEqual(@as(f32, 460), clampWidthTab(500, .background));
    try std.testing.expectEqual(@as(f32, 400), clampWidthTab(400, .background));
    try std.testing.expectEqual(@as(f32, 360), clampWidthTab(400, .files));
    try std.testing.expectEqual(@as(f32, 360), clampWidthTab(460, .files));
}

test "tab defaults to files; Diff and Background open the panel; Files↔Diff↔Background clamps width" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    try std.testing.expect(!model.right_panel_open);
    try std.testing.expectEqual(Tab.files, model.right_panel_tab);
    try std.testing.expectEqual(@as(f32, 184), model.right_panel_width);

    selectDiff(&model, &fx);
    try std.testing.expect(model.right_panel_open);
    try std.testing.expectEqual(Tab.diff, model.right_panel_tab);
    try std.testing.expectEqual(@as(f32, 460), model.right_panel_width);
    try std.testing.expect(model.right_panel_split < 1.0);

    selectFiles(&model, &fx);
    try std.testing.expect(model.right_panel_open);
    try std.testing.expectEqual(Tab.files, model.right_panel_tab);
    try std.testing.expectEqual(@as(f32, 360), model.right_panel_width);

    selectDiff(&model, &fx);
    try std.testing.expectEqual(Tab.diff, model.right_panel_tab);
    try std.testing.expectEqual(@as(f32, 460), model.right_panel_width);

    model.right_panel_width = 400;
    selectFiles(&model, &fx);
    try std.testing.expectEqual(@as(f32, 360), model.right_panel_width);

    selectBackground(&model, &fx, 0);
    try std.testing.expect(model.right_panel_open);
    try std.testing.expectEqual(Tab.background, model.right_panel_tab);
    try std.testing.expectEqual(@as(f32, 460), model.right_panel_width);
    try std.testing.expectEqual(@as(u32, 0), model.right_panel_background_row_id);

    selectBackground(&model, &fx, 1);
    try std.testing.expectEqual(Tab.background, model.right_panel_tab);
    try std.testing.expectEqual(@as(u32, 1), model.right_panel_background_row_id);
    try std.testing.expectEqual(@as(f32, 460), model.right_panel_width);

    selectBackground(&model, &fx, 0);
    try std.testing.expectEqual(@as(u32, 1), model.right_panel_background_row_id);

    selectFiles(&model, &fx);
    try std.testing.expectEqual(Tab.files, model.right_panel_tab);
    try std.testing.expectEqual(@as(f32, 360), model.right_panel_width);
    try std.testing.expectEqual(@as(u32, 1), model.right_panel_background_row_id);

    selectDiff(&model, &fx);
    try std.testing.expectEqual(Tab.diff, model.right_panel_tab);

    model.hideRightPanel();
    try std.testing.expect(!model.right_panel_open);
    try std.testing.expectEqual(Tab.files, model.right_panel_tab);
    try std.testing.expectEqual(@as(f32, 360), model.right_panel_width);
}

test "Diff keeps an active Compare source; Uncommitted is the empty default" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, "/tmp/faku-diff-tab-{s}", .{tmp.sub_path});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("diff tab", .fx);
    model.selected = id;
    model.setSelectedProjectPath(project);

    selectDiff(&model, &fx);
    try std.testing.expect(model.review_diff_active);
    try std.testing.expectEqual(review_diff.Source.uncommitted, model.review_diff_source);
    try std.testing.expect(model.review_diff_key >= review_diff.review_diff_key_first);
    const first_key = model.review_diff_key;

    review_diff.setSource(&model, &fx, .branch);
    try std.testing.expectEqual(review_diff.Source.branch, model.review_diff_source);
    try std.testing.expect(model.review_diff_key != first_key);

    selectFiles(&model, &fx);
    try std.testing.expectEqual(Tab.files, model.right_panel_tab);
    try std.testing.expect(model.review_diff_active);
    try std.testing.expectEqual(review_diff.Source.branch, model.review_diff_source);

    const branch_key = model.review_diff_key;
    selectDiff(&model, &fx);
    try std.testing.expectEqual(Tab.diff, model.right_panel_tab);
    try std.testing.expectEqual(review_diff.Source.branch, model.review_diff_source);
    try std.testing.expect(model.review_diff_key != branch_key);
}

test "joinProjectRelpath joins root and relpath; empty sides miss" {
    var buf: [64]u8 = undefined;
    try std.testing.expectEqualStrings("/tmp/proj/src/main.zig", joinProjectRelpath("/tmp/proj", "src/main.zig", &buf).?);
    try std.testing.expectEqualStrings("/tmp/proj/src/main.zig", joinProjectRelpath("/tmp/proj/", "/src/main.zig", &buf).?);
    try std.testing.expect(joinProjectRelpath("", "src/main.zig", &buf) == null);
    try std.testing.expect(joinProjectRelpath("/tmp/proj", "", &buf) == null);
}

test "dirKey strips a trailing slash; ancestorsExpanded is collapsed by default" {
    try std.testing.expectEqualStrings("src", dirKey("src/"));
    try std.testing.expectEqualStrings("src/lib", dirKey("src/lib/"));
    try std.testing.expectEqualStrings("src/main.zig", dirKey("src/main.zig"));
    const none = [_][]const u8{};
    try std.testing.expect(ancestorsExpanded("README.md", &none));
    try std.testing.expect(ancestorsExpanded("src/", &none));
    try std.testing.expect(!ancestorsExpanded("src/main.zig", &none));
    try std.testing.expect(!ancestorsExpanded("src/lib/", &none));
    try std.testing.expect(!ancestorsExpanded("src/lib/a.zig", &none));
    const src_only = [_][]const u8{"src"};
    try std.testing.expect(ancestorsExpanded("src/main.zig", &src_only));
    try std.testing.expect(ancestorsExpanded("src/lib/", &src_only));
    try std.testing.expect(!ancestorsExpanded("src/lib/a.zig", &src_only));
    const nested = [_][]const u8{ "src", "src/lib" };
    try std.testing.expect(ancestorsExpanded("src/lib/a.zig", &nested));
    const stale = [_][]const u8{"src/lib"};
    try std.testing.expect(!ancestorsExpanded("src/lib/a.zig", &stale));
}

test "rows are empty when closed or without a cache" {
    var model = Model{};
    try std.testing.expect(!model.right_panel_open);
    try std.testing.expectEqual(@as(usize, 0), rows(&model, std.testing.allocator).len);

    model.right_panel_open = true;
    try std.testing.expectEqual(@as(usize, 0), rows(&model, std.testing.allocator).len);
}

test "collapsed default, expand shows children, collapse hides descendants" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, "/tmp/faku-files-tree-{s}", .{tmp.sub_path});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("tree", .fx);
    model.selected = id;
    model.setSelectedProjectPath(project);
    model.right_panel_open = true;
    file_mention.applyStdoutPaths(&model,
        \\src/lib/a.zig
        \\src/main.zig
        \\README.md
    );

    var parents: [file_mention.max_file_mention_dirs][]const u8 = undefined;
    const dir_n = file_mention.derivedDirParents(&model, &parents);
    try std.testing.expectEqual(@as(usize, 2), dir_n);
    try std.testing.expectEqualStrings("src/lib", parents[0]);
    try std.testing.expectEqualStrings("src", parents[1]);
    const src_lib_id = file_mention.dirMentionId(0);
    const src_id = file_mention.dirMentionId(1);

    {
        const visible = rows(&model, arena);
        try std.testing.expectEqual(@as(usize, 2), visible.len);
        try std.testing.expectEqualStrings("README.md", visible[0].path);
        try std.testing.expect(visible[0].is_file);
        try std.testing.expectEqual(@as(u32, 0), visible[0].depth);
        try std.testing.expectEqualStrings("src/", visible[1].path);
        try std.testing.expect(!visible[1].is_file);
        try std.testing.expect(!visible[1].expanded);
        try std.testing.expectEqual(src_id, visible[1].id);
        try std.testing.expectEqual(@as(u32, 0), visible[1].depth);
    }

    toggleDir(&model, src_id);
    try std.testing.expect(isDirExpanded(&model, "src/"));
    {
        const visible = rows(&model, arena);
        try std.testing.expectEqual(@as(usize, 4), visible.len);
        try std.testing.expectEqualStrings("README.md", visible[0].path);
        try std.testing.expectEqualStrings("src/", visible[1].path);
        try std.testing.expect(visible[1].expanded);
        try std.testing.expectEqualStrings("src/lib/", visible[2].path);
        try std.testing.expect(!visible[2].expanded);
        try std.testing.expectEqual(src_lib_id, visible[2].id);
        try std.testing.expectEqual(@as(u32, 1), visible[2].depth);
        try std.testing.expect(visible[2].has_indent);
        try std.testing.expectEqual(indent_step, visible[2].indent);
        try std.testing.expectEqualStrings("src/main.zig", visible[3].path);
        try std.testing.expect(visible[3].is_file);
        try std.testing.expect(!visible[3].expanded);
    }

    toggleDir(&model, src_lib_id);
    {
        const visible = rows(&model, arena);
        try std.testing.expectEqual(@as(usize, 5), visible.len);
        try std.testing.expectEqualStrings("src/lib/a.zig", visible[3].path);
        try std.testing.expectEqual(@as(u32, 2), visible[3].depth);
        try std.testing.expectEqualStrings("src/main.zig", visible[4].path);
    }

    toggleDir(&model, src_id);
    try std.testing.expect(!isDirExpanded(&model, "src/"));
    {
        const visible = rows(&model, arena);
        try std.testing.expectEqual(@as(usize, 2), visible.len);
        try std.testing.expectEqualStrings("README.md", visible[0].path);
        try std.testing.expectEqualStrings("src/", visible[1].path);
        try std.testing.expect(isDirExpanded(&model, "src/lib/"));
    }

    toggleDir(&model, 0);
    toggleDir(&model, 1);
    toggleDir(&model, file_mention.dirMentionId(99));
    try std.testing.expectEqual(@as(u32, 1), model.right_panel_expanded_count);

    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;
    openCachedFile(&model, &fx, src_id);
    try std.testing.expect(fx.pendingSpawnAt(0) == null);
    openCachedFile(&model, &fx, 1);
    try std.testing.expect(fx.pendingSpawnAt(0) == null);
    try std.testing.expectEqual(@as(u32, 1), model.right_panel_file_preview_id);
    openPreviewInEditor(&model, &fx);
    try std.testing.expect(fx.pendingSpawnAt(0) != null);

    model.hideRightPanel();
    try std.testing.expectEqual(@as(u32, 0), model.right_panel_expanded_count);
    model.showRightPanel();
    try std.testing.expectEqual(@as(usize, 2), rows(&model, arena).len);

    toggleDir(&model, src_id);
    try std.testing.expectEqual(@as(u32, 1), model.right_panel_expanded_count);
    file_mention.clearCache(&model);
    try std.testing.expectEqual(@as(u32, 0), model.right_panel_expanded_count);
}

fn writePreviewFile(io: std.Io, abs: []const u8, data: []const u8) !void {
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = abs, .data = data });
}

test "inline preview caps at 256KB and labels truncation" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, "/tmp/faku-preview-cap-{s}", .{tmp.sub_path});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var path_buf: [300]u8 = undefined;
    const abs = try std.fmt.bufPrint(&path_buf, "{s}/big.txt", .{project});
    const over = max_file_preview_bytes + 8;
    const blob = try std.testing.allocator.alloc(u8, over);
    defer std.testing.allocator.free(blob);
    @memset(blob, 'a');
    try writePreviewFile(std.testing.io, abs, blob);

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("preview cap", .fx);
    model.selected = id;
    model.setSelectedProjectPath(project);
    model.right_panel_open = true;
    file_mention.applyStdoutPaths(&model, "big.txt\n");
    defer clearFilePreview(&model);

    selectCachedFile(&model, 1);
    try std.testing.expectEqual(@as(u32, 1), model.right_panel_file_preview_id);
    try std.testing.expect(model.file_preview_truncated());
    try std.testing.expectEqual(max_file_preview_bytes, model.right_panel_file_preview_len);
    try std.testing.expect(!model.file_preview_binary());
    try std.testing.expectEqualStrings("big.txt", model.file_preview_path());
}

test "inline preview rejects NUL and invalid UTF-8" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, "/tmp/faku-preview-bin-{s}", .{tmp.sub_path});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var nul_buf: [300]u8 = undefined;
    const nul_abs = try std.fmt.bufPrint(&nul_buf, "{s}/nul.bin", .{project});
    try writePreviewFile(std.testing.io, nul_abs, "ok\x00still");

    var bad_buf: [300]u8 = undefined;
    const bad_abs = try std.fmt.bufPrint(&bad_buf, "{s}/bad.txt", .{project});
    try writePreviewFile(std.testing.io, bad_abs, "ok\xff");

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("preview bin", .fx);
    model.selected = id;
    model.setSelectedProjectPath(project);
    model.right_panel_open = true;
    file_mention.applyStdoutPaths(&model, "nul.bin\nbad.txt\n");
    defer clearFilePreview(&model);

    selectCachedFile(&model, 1);
    try std.testing.expect(model.file_preview_binary());
    try std.testing.expectEqual(@as(usize, 0), model.right_panel_file_preview_len);
    try std.testing.expectEqualStrings(binary_file_label, binary_file_label);

    selectCachedFile(&model, 2);
    try std.testing.expect(model.file_preview_binary());
    try std.testing.expectEqual(@as(usize, 0), model.right_panel_file_preview_len);
}

test "inline preview missing path is a one-line error" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, "/tmp/faku-preview-miss-{s}", .{tmp.sub_path});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("preview miss", .fx);
    model.selected = id;
    model.setSelectedProjectPath(project);
    model.right_panel_open = true;
    file_mention.applyStdoutPaths(&model, "gone.txt\n");
    defer clearFilePreview(&model);

    selectCachedFile(&model, 1);
    try std.testing.expect(model.file_preview_has_error());
    try std.testing.expectEqualStrings(missing_file_label, model.file_preview_error());
    try std.testing.expectEqual(@as(usize, 0), model.right_panel_file_preview_len);
    try std.testing.expect(!model.file_preview_binary());
}

test "inline preview close, hide, and session switch free the heap buffer" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, "/tmp/faku-preview-free-{s}", .{tmp.sub_path});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);
    var path_buf: [300]u8 = undefined;
    const abs = try std.fmt.bufPrint(&path_buf, "{s}/note.txt", .{project});
    try writePreviewFile(std.testing.io, abs, "hello\nworld\n");

    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = std.testing.io;
    const first = model.addSession("preview free", .fx);
    const second = model.addSession("other", .fx);
    model.selected = first;
    model.setSelectedProjectPath(project);
    model.right_panel_open = true;
    file_mention.applyStdoutPaths(&model, "note.txt\n");

    selectCachedFile(&model, 1);
    try std.testing.expect(model.file_preview_has_body());
    try std.testing.expectEqualStrings("hello\nworld\n", model.file_preview_body());
    try std.testing.expect(model.right_panel_file_preview_storage.len != 0);

    clearFilePreview(&model);
    try std.testing.expectEqual(@as(u32, 0), model.right_panel_file_preview_id);
    try std.testing.expectEqual(@as(usize, 0), model.right_panel_file_preview_storage.len);

    selectCachedFile(&model, 1);
    try std.testing.expect(model.right_panel_file_preview_storage.len != 0);
    model.hideRightPanel();
    try std.testing.expectEqual(@as(u32, 0), model.right_panel_file_preview_id);
    try std.testing.expectEqual(@as(usize, 0), model.right_panel_file_preview_storage.len);

    model.showRightPanel();
    selectCachedFile(&model, 1);
    try std.testing.expect(model.right_panel_file_preview_storage.len != 0);
    const palette_run = @import("palette_run.zig");
    palette_run.applySessionSelection(&model, &fx, second);
    try std.testing.expectEqual(@as(u32, 0), model.right_panel_file_preview_id);
    try std.testing.expectEqual(@as(usize, 0), model.right_panel_file_preview_storage.len);

    model.selected = first;
    model.setSelectedProjectPath(project);
    file_mention.applyStdoutPaths(&model, "note.txt\n");
    selectCachedFile(&model, 1);
    var editor_fx = Effects.init(std.testing.allocator);
    defer editor_fx.deinit();
    editor_fx.executor = .fake;
    openPreviewInEditor(&model, &editor_fx);
    const spawn = editor_fx.pendingSpawnAt(0) orelse return error.MissingOpenEditorSpawn;
    try std.testing.expect(open_editor.isEditorArgv(spawn.argv));
    try std.testing.expectEqualStrings(abs, spawn.argv[1]);
    clearFilePreview(&model);
}
