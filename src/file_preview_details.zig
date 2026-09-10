//! Files Preview markdown `<details>` expand/collapse (first-cut).
//!
//! Rendered Files `<markdown>` binds caller-owned expansion flags via
//! Native `details-expanded` (`[]const bool` in details-block document
//! order) and `on-details` (bare Msg tag; payload is that index). Cap
//! `canvas.markdown.max_markdown_details_per_document`. Missing /
//! false flags stay collapsed. Runtime-only for the current preview
//! body — not sessions.json. Verified: Native markdown `details-expanded`
//! + `on-details`.

const std = @import("std");
const native_sdk = @import("native_sdk");
const main = @import("main.zig");

const canvas = native_sdk.canvas;

const Model = main.Model;
const Effects = main.Effects;

pub const max_details: usize = canvas.markdown.max_markdown_details_per_document;

/// Zero every expansion flag. Same drop moments as
/// `file_preview_images.drop` (close, file switch, session
/// switch/remove, Preview→Source, Edit, body reload).
pub fn drop(model: *Model) void {
    model.file_preview_details_expanded_flags = [_]bool{false} ** max_details;
}

/// Flip the flag at `index` when it is in range. Out-of-range is a
/// no-op (Native should not send past the cap).
pub fn toggle(model: *Model, index: usize) void {
    if (index >= model.file_preview_details_expanded_flags.len) return;
    model.file_preview_details_expanded_flags[index] = !model.file_preview_details_expanded_flags[index];
}

/// Slice binding for `<markdown details-expanded="{file_preview_details_expanded}">`.
pub fn expanded(model: *const Model) []const bool {
    return &model.file_preview_details_expanded_flags;
}

test "cap matches Native max_markdown_details_per_document" {
    try std.testing.expectEqual(@as(usize, 16), max_details);
    try std.testing.expectEqual(canvas.markdown.max_markdown_details_per_document, max_details);
}

test "toggle flips the flag at the given index; OOB is a no-op" {
    var model = Model{};
    try std.testing.expectEqual(@as(usize, max_details), expanded(&model).len);
    try std.testing.expect(!expanded(&model)[0]);
    try std.testing.expect(!expanded(&model)[1]);

    toggle(&model, 0);
    try std.testing.expect(expanded(&model)[0]);
    try std.testing.expect(!expanded(&model)[1]);

    toggle(&model, 0);
    try std.testing.expect(!expanded(&model)[0]);

    toggle(&model, 3);
    try std.testing.expect(expanded(&model)[3]);

    const before = model.file_preview_details_expanded_flags;
    toggle(&model, max_details);
    toggle(&model, max_details + 8);
    try std.testing.expectEqual(before, model.file_preview_details_expanded_flags);
}

test "drop clears all flags on close / Source chip / file switch" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, "/tmp/faku-md-details-{s}", .{tmp.sub_path});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);
    var readme_buf: [300]u8 = undefined;
    const readme = try std.fmt.bufPrint(&readme_buf, "{s}/README.md", .{project});
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{
        .sub_path = readme,
        .data = "# Hello\n\n<details>\n<summary>More</summary>\n\nHidden\n</details>\n",
    });
    var other_buf: [300]u8 = undefined;
    const other = try std.fmt.bufPrint(&other_buf, "{s}/other.md", .{project});
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{
        .sub_path = other,
        .data = "# Other\n",
    });

    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("md details", .fx);
    model.selected = id;
    model.setSelectedProjectPath(project);
    const file_mention = @import("file_mention.zig");
    const right_panel = @import("right_panel.zig");
    file_mention.applyStdoutPaths(&model, "README.md\nother.md\n");
    defer right_panel.clearFilePreview(&model);
    defer file_mention.clearCache(&model);

    right_panel.selectCachedFile(&model, &fx, 1);
    try std.testing.expect(model.file_preview_shows_rendered_markdown());
    main.update(&model, .{ .file_preview_toggle_details = 0 }, &fx);
    try std.testing.expect(expanded(&model)[0]);

    main.update(&model, .set_file_preview_markdown_source, &fx);
    try std.testing.expect(!model.file_preview_shows_rendered_markdown());
    try std.testing.expect(!expanded(&model)[0]);

    main.update(&model, .set_file_preview_markdown_preview, &fx);
    try std.testing.expect(model.file_preview_shows_rendered_markdown());
    main.update(&model, .{ .file_preview_toggle_details = 0 }, &fx);
    try std.testing.expect(expanded(&model)[0]);

    right_panel.selectCachedFile(&model, &fx, 2);
    try std.testing.expect(!expanded(&model)[0]);

    right_panel.selectCachedFile(&model, &fx, 1);
    main.update(&model, .{ .file_preview_toggle_details = 0 }, &fx);
    try std.testing.expect(expanded(&model)[0]);
    main.update(&model, .close_right_panel_file_preview, &fx);
    try std.testing.expect(!expanded(&model)[0]);
}
