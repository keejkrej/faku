//! Sidebar and right-panel layout chrome widths.
//!
//! Waku-measured pane clamps for the sidebar rail and the Files / Diff /
//! Browser / Terminal / Background right panel. Re-exported from `main.zig` so
//! `main.sidebar_*` / `main.right_panel_*` call sites keep working.
//! First-cut Files preview widen lives here as `file_editor_initial_width`
//! and `widenedPanelWidthForFileEditor` (Waku `FILE_EDITOR_INITIAL_WIDTH`
//! 500).

const std = @import("std");

pub const sidebar_default_width: f32 = 252;
pub const sidebar_min_width: f32 = 180;
pub const sidebar_max_width: f32 = 420;
pub const sidebar_rail_width: f32 = 48;
/// Waku `DEFAULT_FILE_TREE_WIDTH`. Files tab default (not the 460px panel).
pub const right_panel_default_width: f32 = 184;
/// Waku `FILE_TREE_MIN_WIDTH`. Files / file-tree min when no preview is
/// open. Diff / Browser / Terminal / Background — and Files while a
/// preview is open — use `right_panel_diff_min_width`.
pub const right_panel_min_width: f32 = 140;
/// Waku `FILE_TREE_MAX_WIDTH`. Files tab clamp when no inline preview is
/// open. Diff / Browser / Terminal / Background — and Files while a
/// preview is open — use `right_panel_diff_max_width`.
pub const right_panel_max_width: f32 = 360;
/// Waku `DEFAULT_RIGHT_PANEL_WIDTH`. Diff / Browser / Terminal / Background
/// target when the pane is still file-tree-narrow (≤ `right_panel_max_width`).
/// Not persisted as a tab: switching back to Files without a preview
/// reclamps to `right_panel_max_width`.
pub const right_panel_diff_default_width: f32 = 460;
/// Waku `RIGHT_PANEL_MIN_WIDTH`. Diff / Browser / Terminal / Background
/// resize floor, and Files while an inline preview is open. Files
/// without a preview keeps `right_panel_min_width`.
pub const right_panel_diff_min_width: f32 = 280;
/// Waku `RIGHT_PANEL_MAX_WIDTH`. Diff / Browser / Terminal / Background
/// resize clamp, and Files while an inline preview is open. Open/target
/// width for those wide tabs stays `right_panel_diff_default_width`.
/// Min is `right_panel_diff_min_width`.
pub const right_panel_diff_max_width: f32 = 1000;
/// Waku `FILE_EDITOR_INITIAL_WIDTH`. Extra pixels beyond the file tree
/// when the first Files preview opens.
pub const file_editor_initial_width: f32 = 500;

/// Waku RIGHT_PANEL sanitize: non-positive → default 460, then clamp
/// 280–1000.
fn sanitizeRightPanelWidth(width: f32) f32 {
    const raw = if (width > 0) width else right_panel_diff_default_width;
    return @max(right_panel_diff_min_width, @min(right_panel_diff_max_width, raw));
}

/// Waku `widened_panel_width_for_file_editor`: sanitize `panel_width` to
/// the wide RIGHT_PANEL range, then max with `file_tree_width` +
/// `FILE_EDITOR_INITIAL_WIDTH` 500, clamp 280–1000.
pub fn widenedPanelWidthForFileEditor(panel_width: f32, file_tree_width: f32) f32 {
    const panel = sanitizeRightPanelWidth(panel_width);
    return sanitizeRightPanelWidth(@max(panel, file_tree_width + file_editor_initial_width));
}

test "layout chrome widths match Waku-aligned numbers" {
    try std.testing.expectEqual(@as(f32, 252), sidebar_default_width);
    try std.testing.expectEqual(@as(f32, 180), sidebar_min_width);
    try std.testing.expectEqual(@as(f32, 420), sidebar_max_width);
    try std.testing.expectEqual(@as(f32, 48), sidebar_rail_width);
    try std.testing.expectEqual(@as(f32, 184), right_panel_default_width);
    try std.testing.expectEqual(@as(f32, 140), right_panel_min_width);
    try std.testing.expectEqual(@as(f32, 360), right_panel_max_width);
    try std.testing.expectEqual(@as(f32, 460), right_panel_diff_default_width);
    try std.testing.expectEqual(@as(f32, 280), right_panel_diff_min_width);
    try std.testing.expectEqual(@as(f32, 1000), right_panel_diff_max_width);
    try std.testing.expectEqual(@as(f32, 500), file_editor_initial_width);
}

test "widenedPanelWidthForFileEditor matches Waku FILE_EDITOR_INITIAL_WIDTH 500" {
    try std.testing.expectEqual(@as(f32, 684), widenedPanelWidthForFileEditor(460, 184));
    try std.testing.expectEqual(@as(f32, 720), widenedPanelWidthForFileEditor(720, 184));
    try std.testing.expectEqual(@as(f32, 684), widenedPanelWidthForFileEditor(184, 184));
    try std.testing.expectEqual(@as(f32, 1000), widenedPanelWidthForFileEditor(1200, 184));
}
