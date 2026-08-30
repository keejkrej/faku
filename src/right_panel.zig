//! First-cut Waku right panel: Files surface only.
//!
//! Toggleable pane to the right of the conversation column. Lists the
//! selected session's project files from the existing `file_mention`
//! cache (`git ls-files --cached --others --exclude-standard`, then
//! the bounded find walk) plus derived parent directories collected
//! there. Not Browser, Terminal (Native has no PTY), Diff, compact
//! File editor, or BackgroundWork tabs. Not daemon
//! `WorkspaceOperation::listTree` / browseDirectory / readTextFile.
//! Not Waku's 50k-file index (cap 256). Windows stays empty this cut
//! (`file_mention` already skips Windows).
//!
//! Default closed: Waku `RightPanelSessionState::take_or_closed` uses
//! `empty(false)` and persistence `default_right_panel_visibility` is
//! false. Widths are Waku `DEFAULT_FILE_TREE_WIDTH` (184) /
//! `FILE_TREE_MIN_WIDTH` (140) / `FILE_TREE_MAX_WIDTH` (360) because
//! this cut is the Files tree, not the full 460px right panel that
//! also hosts Browser / Terminal / Diff / editor.

const std = @import("std");
const main = @import("main.zig");
const file_mention = @import("file_mention.zig");
const composer = @import("composer.zig");
const open_editor = @import("open_editor.zig");

const Model = main.Model;
const Effects = main.Effects;
const RightPanelFileRow = main.RightPanelFileRow;

pub fn clampWidth(width: f32) f32 {
    const raw = if (width > 0) width else main.right_panel_default_width;
    return @max(main.right_panel_min_width, @min(main.right_panel_max_width, raw));
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
    const files = clampWidth(width);
    const conversation = @max(0, rest - files);
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

pub fn rows(model: *const Model, arena: std.mem.Allocator) []const RightPanelFileRow {
    if (!model.right_panel_open) return &.{};
    if (!hasProject(model)) return &.{};
    if (model.file_mention_count == 0) return &.{};

    var parents: [file_mention.max_file_mention_dirs][]const u8 = undefined;
    const dir_n = file_mention.derivedDirParents(model, &parents);
    const file_n = model.file_mention_count;
    const count = dir_n + file_n;
    const out = arena.alloc(RightPanelFileRow, count) catch return &.{};
    var i: usize = 0;
    for (parents[0..dir_n], 0..) |parent, dir_index| {
        const path = std.fmt.allocPrint(arena, "{s}/", .{parent}) catch continue;
        const name = composer.fileMentionBasename(path);
        const dir_parent = composer.fileMentionParent(path);
        out[i] = .{
            .id = file_mention.dirMentionId(dir_index),
            .path = path,
            .name = name,
            .parent = dir_parent,
            .has_parent = dir_parent.len > 0,
            .is_file = false,
        };
        i += 1;
    }
    var file_i: usize = 0;
    while (file_i < file_n) : (file_i += 1) {
        const path = file_mention.cachedPath(model, file_i);
        const name = composer.fileMentionBasename(path);
        const parent = composer.fileMentionParent(path);
        out[i] = .{
            .id = file_mention.fileMentionId(file_i),
            .path = path,
            .name = name,
            .parent = parent,
            .has_parent = parent.len > 0,
            .is_file = true,
        };
        i += 1;
    }
    return out[0..i];
}

pub fn openCachedFile(model: *Model, fx: *Effects, id: u32) void {
    if (id == 0 or id >= file_mention.file_mention_dir_id_base) return;
    var rel_buf: [file_mention.max_file_mention_path + 1]u8 = undefined;
    const rel = file_mention.mentionRelpath(model, id, &rel_buf) orelse return;
    const project = model.selectedProjectPath();
    var abs_buf: [open_editor.max_open_path]u8 = undefined;
    const abs = joinProjectRelpath(project, rel, &abs_buf) orelse return;
    open_editor.startOpenEditorAt(model, fx, abs);
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

test "joinProjectRelpath joins root and relpath; empty sides miss" {
    var buf: [64]u8 = undefined;
    try std.testing.expectEqualStrings("/tmp/proj/src/main.zig", joinProjectRelpath("/tmp/proj", "src/main.zig", &buf).?);
    try std.testing.expectEqualStrings("/tmp/proj/src/main.zig", joinProjectRelpath("/tmp/proj/", "/src/main.zig", &buf).?);
    try std.testing.expect(joinProjectRelpath("", "src/main.zig", &buf) == null);
    try std.testing.expect(joinProjectRelpath("/tmp/proj", "", &buf) == null);
}

test "rows are empty when closed or without a cache" {
    var model = Model{};
    try std.testing.expect(!model.right_panel_open);
    try std.testing.expectEqual(@as(usize, 0), rows(&model, std.testing.allocator).len);

    model.right_panel_open = true;
    try std.testing.expectEqual(@as(usize, 0), rows(&model, std.testing.allocator).len);
}
