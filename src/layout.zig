//! Sidebar and right-panel layout chrome widths.
//!
//! Waku-measured pane clamps for the sidebar rail and the Files / Diff /
//! Background right panel. Re-exported from `main.zig` so
//! `main.sidebar_*` / `main.right_panel_*` call sites keep working.
//! Behavior is unchanged from the former `main` constants.

const std = @import("std");

pub const sidebar_default_width: f32 = 252;
pub const sidebar_min_width: f32 = 180;
pub const sidebar_max_width: f32 = 420;
pub const sidebar_rail_width: f32 = 48;
/// Waku `DEFAULT_FILE_TREE_WIDTH`. Files tab default (not the 460px panel).
pub const right_panel_default_width: f32 = 184;
/// Waku `FILE_TREE_MIN_WIDTH`. Shared min for Files, Diff, and Background.
pub const right_panel_min_width: f32 = 140;
/// Waku `FILE_TREE_MAX_WIDTH`. Files tab clamp. Diff and Background use `right_panel_diff_max_width`.
pub const right_panel_max_width: f32 = 360;
/// Waku `DEFAULT_RIGHT_PANEL_WIDTH`. Diff and Background target when the pane
/// is still file-tree-narrow (≤ `right_panel_max_width`). Not persisted as a
/// tab: switching back to Files reclamps to `right_panel_max_width`.
pub const right_panel_diff_default_width: f32 = 460;
/// First-cut Diff / Background tab max: Waku `DEFAULT_RIGHT_PANEL_WIDTH` 460
/// (full Waku `RIGHT_PANEL_MAX_WIDTH` is 1000; `RIGHT_PANEL_MIN_WIDTH` is 280).
pub const right_panel_diff_max_width: f32 = 460;

test "layout chrome widths match Waku-aligned numbers" {
    try std.testing.expectEqual(@as(f32, 252), sidebar_default_width);
    try std.testing.expectEqual(@as(f32, 180), sidebar_min_width);
    try std.testing.expectEqual(@as(f32, 420), sidebar_max_width);
    try std.testing.expectEqual(@as(f32, 48), sidebar_rail_width);
    try std.testing.expectEqual(@as(f32, 184), right_panel_default_width);
    try std.testing.expectEqual(@as(f32, 140), right_panel_min_width);
    try std.testing.expectEqual(@as(f32, 360), right_panel_max_width);
    try std.testing.expectEqual(@as(f32, 460), right_panel_diff_default_width);
    try std.testing.expectEqual(@as(f32, 460), right_panel_diff_max_width);
}
