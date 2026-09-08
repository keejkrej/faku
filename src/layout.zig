//! Sidebar and right-panel layout chrome widths.
//!
//! Waku-measured pane clamps for the sidebar rail and the Files / Diff /
//! Browser / Terminal / Background right panel. Re-exported from `main.zig` so
//! `main.sidebar_*` / `main.right_panel_*` call sites keep working.
//! First-cut Files preview widen lives here as `file_editor_initial_width`
//! and `widenedPanelWidthForFileEditor` (Waku `FILE_EDITOR_INITIAL_WIDTH`
//! 500). Nested Files tree + preview uses `file_editor_min_width` 140
//! and `fittedFileTreeWidth` (Waku `fitted_file_tree_width`). Nested
//! Diff hunk + file list reuses those FILE_TREE clamps (no Waku
//! REVIEW_* list-width constant this cut). First-cut Diff / Review
//! open widen lives here as `review_initial_width` and
//! `widenedPanelWidthForReview` (Waku `REVIEW_INITIAL_WIDTH` 820).

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
/// Waku `DEFAULT_RIGHT_PANEL_WIDTH`. Browser / Terminal / Background
/// target when the pane is still file-tree-narrow (≤ `right_panel_max_width`).
/// Diff open uses `review_initial_width` instead. Not persisted as a
/// tab: switching back to Files without a preview reclamps to
/// `right_panel_max_width`.
pub const right_panel_diff_default_width: f32 = 460;
/// Waku `RIGHT_PANEL_MIN_WIDTH`. Diff / Browser / Terminal / Background
/// resize floor, and Files while an inline preview is open. Files
/// without a preview keeps `right_panel_min_width`.
pub const right_panel_diff_min_width: f32 = 280;
/// Waku `RIGHT_PANEL_MAX_WIDTH`. Diff / Browser / Terminal / Background
/// resize clamp, and Files while an inline preview is open. Open/target
/// width for Browser / Terminal / Background stays
/// `right_panel_diff_default_width`. Diff open uses `review_initial_width`.
/// Min is `right_panel_diff_min_width`.
pub const right_panel_diff_max_width: f32 = 1000;
/// Waku `FILE_EDITOR_INITIAL_WIDTH`. Extra pixels beyond the file tree
/// when the first Files preview opens.
pub const file_editor_initial_width: f32 = 500;
/// Waku `REVIEW_INITIAL_WIDTH`. Target when Diff / Review becomes the
/// active tab (not a no-op re-select).
pub const review_initial_width: f32 = 820;
/// Waku `FILE_EDITOR_MIN_WIDTH`. Preview/editor column floor in the
/// nested Files split (tree sits on the right).
pub const file_editor_min_width: f32 = 140;

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

/// Waku `widened_panel_width_for_review`: sanitize `panel_width` to
/// the wide RIGHT_PANEL range, then max with `REVIEW_INITIAL_WIDTH`
/// 820, clamp 280–1000.
pub fn widenedPanelWidthForReview(panel_width: f32) f32 {
    const panel = sanitizeRightPanelWidth(panel_width);
    return sanitizeRightPanelWidth(@max(panel, review_initial_width));
}

/// Waku `fitted_file_tree_width`: max is `FILE_TREE_MAX` min
/// `(panel - FILE_EDITOR_MIN)` then at least `FILE_TREE_MIN`. Sanitize
/// `file_tree_width` into `[FILE_TREE_MIN, max]`; non-positive uses
/// `DEFAULT_FILE_TREE_WIDTH` 184 then that clamp.
pub fn fittedFileTreeWidth(panel_width: f32, file_tree_width: f32) f32 {
    const max = @max(right_panel_min_width, @min(right_panel_max_width, panel_width - file_editor_min_width));
    const raw = if (file_tree_width > 0) file_tree_width else right_panel_default_width;
    return @max(right_panel_min_width, @min(max, raw));
}

/// Native nested-split left fraction for Files preview | tree: preview
/// is the left pane, tree the right at `fittedFileTreeWidth`.
pub fn fileTreeSplitFraction(panel_width: f32, file_tree_width: f32) f32 {
    const pane = @max(1, panel_width);
    const tree = fittedFileTreeWidth(pane, file_tree_width);
    return (pane - tree) / pane;
}

/// Nested Diff file-list width. Reuses FILE_TREE clamps (140 / 184 / 360
/// via `fittedFileTreeWidth`); there is no Waku REVIEW_* list-width
/// constant this cut.
pub const fittedDiffFileListWidth = fittedFileTreeWidth;

/// Native nested-split left fraction for Diff hunk | file list: hunk is
/// the left pane, file list the right at `fittedDiffFileListWidth`.
pub const diffFileListSplitFraction = fileTreeSplitFraction;

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
    try std.testing.expectEqual(@as(f32, 820), review_initial_width);
    try std.testing.expectEqual(@as(f32, 140), file_editor_min_width);
}

test "widenedPanelWidthForFileEditor matches Waku FILE_EDITOR_INITIAL_WIDTH 500" {
    try std.testing.expectEqual(@as(f32, 684), widenedPanelWidthForFileEditor(460, 184));
    try std.testing.expectEqual(@as(f32, 720), widenedPanelWidthForFileEditor(720, 184));
    try std.testing.expectEqual(@as(f32, 684), widenedPanelWidthForFileEditor(184, 184));
    try std.testing.expectEqual(@as(f32, 1000), widenedPanelWidthForFileEditor(1200, 184));
}

test "widenedPanelWidthForReview matches Waku REVIEW_INITIAL_WIDTH 820" {
    try std.testing.expectEqual(@as(f32, 820), widenedPanelWidthForReview(460));
    try std.testing.expectEqual(@as(f32, 920), widenedPanelWidthForReview(920));
    try std.testing.expectEqual(@as(f32, 820), widenedPanelWidthForReview(0));
    try std.testing.expectEqual(@as(f32, 820), widenedPanelWidthForReview(-1));
    try std.testing.expectEqual(@as(f32, 1000), widenedPanelWidthForReview(1200));
}

test "fittedFileTreeWidth matches Waku FILE_TREE 140…min(360, panel-140)" {
    try std.testing.expectEqual(@as(f32, 184), fittedFileTreeWidth(684, 184));
    try std.testing.expectEqual(@as(f32, 184), fittedFileTreeWidth(720, 184));
    try std.testing.expectEqual(@as(f32, 184), fittedFileTreeWidth(460, 184));
    try std.testing.expectEqual(@as(f32, 140), fittedFileTreeWidth(280, 184));
    try std.testing.expectEqual(@as(f32, 140), fittedFileTreeWidth(280, 0));
    try std.testing.expectEqual(@as(f32, 184), fittedFileTreeWidth(684, 0));
    try std.testing.expectEqual(@as(f32, 140), fittedFileTreeWidth(684, 100));
    try std.testing.expectEqual(@as(f32, 360), fittedFileTreeWidth(684, 500));
    try std.testing.expectEqual(@as(f32, 260), fittedFileTreeWidth(400, 300));
    try std.testing.expectEqual(@as(f32, 220), fittedFileTreeWidth(400, 220));
    try std.testing.expectEqual(@as(f32, 140), fittedFileTreeWidth(200, 184));
}

test "fileTreeSplitFraction is preview-left of fitted tree width" {
    try std.testing.expectEqual(@as(f32, 500.0 / 684.0), fileTreeSplitFraction(684, 184));
    try std.testing.expectEqual(@as(f32, 0.5), fileTreeSplitFraction(280, 184));
    try std.testing.expectEqual(@as(f32, (720.0 - 184.0) / 720.0), fileTreeSplitFraction(720, 184));
}

test "Diff file-list width reuses FILE_TREE fitted clamps and split fraction" {
    try std.testing.expectEqual(@as(f32, 184), fittedDiffFileListWidth(820, 184));
    try std.testing.expectEqual(@as(f32, 184), fittedDiffFileListWidth(820, 0));
    try std.testing.expectEqual(@as(f32, 140), fittedDiffFileListWidth(820, 100));
    try std.testing.expectEqual(@as(f32, 360), fittedDiffFileListWidth(820, 500));
    try std.testing.expectEqual(@as(f32, 140), fittedDiffFileListWidth(280, 184));
    try std.testing.expectEqual(@as(f32, 260), fittedDiffFileListWidth(400, 300));
    try std.testing.expectEqual(fittedFileTreeWidth(820, 220), fittedDiffFileListWidth(820, 220));
    try std.testing.expectEqual(@as(f32, (820.0 - 184.0) / 820.0), diffFileListSplitFraction(820, 184));
    try std.testing.expectEqual(fileTreeSplitFraction(820, 220), diffFileListSplitFraction(820, 220));
    try std.testing.expectEqual(@as(f32, 0.5), diffFileListSplitFraction(280, 184));
}
