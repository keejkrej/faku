//! Transcript markdown `<details>` expand/collapse (first-cut).
//!
//! Visible user / tool / reasoning / assistant `<markdown>` binds
//! caller-owned expansion flags via Native `details-expanded`
//! (`[]const bool` in details-block document order) and `on-details`
//! (bare Msg tag; payload is that index). Cap
//! `canvas.markdown.max_markdown_details_per_document`. Missing /
//! false flags stay collapsed. Runtime-only — not `sessions.json`
//! (Native `app_dirs` data, app name `faku`). Verified: Native markdown
//! `details-expanded` + `on-details`.
//!
//! Native `on-details` is a bare `usize` index and `details-expanded`
//! is one Model-owned iterable (a field, pub decl, or fn — the same
//! sources `for each` accepts). Every visible transcript `<markdown>`
//! document in one `visible_turns` for-each therefore shares these
//! 16 flags: expanding details N in any user / tool / reasoning /
//! assistant turn expands that index in every other visible transcript
//! document. Per-turn isolation would need a Native payload Native
//! does not document (`on-details` cannot interpolate `{t.id}`). Files
//! Preview `file_preview_details` is a separate flag array.

const std = @import("std");
const native_sdk = @import("native_sdk");
const main = @import("main.zig");

const canvas = native_sdk.canvas;

const Model = main.Model;
const Effects = main.Effects;

pub const max_details: usize = canvas.markdown.max_markdown_details_per_document;

/// Zero every expansion flag. Same drop moments as
/// `transcript_images.drop` (session switch, New Task, remove).
pub fn drop(model: *Model) void {
    model.transcript_details_expanded_flags = [_]bool{false} ** max_details;
}

/// Flip the flag at `index` when it is in range. Out-of-range is a
/// no-op (Native should not send past the cap).
pub fn toggle(model: *Model, index: usize) void {
    if (index >= model.transcript_details_expanded_flags.len) return;
    model.transcript_details_expanded_flags[index] = !model.transcript_details_expanded_flags[index];
}

/// Slice binding for `<markdown details-expanded="{transcript_details_expanded}">`.
pub fn expanded(model: *const Model) []const bool {
    return &model.transcript_details_expanded_flags;
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

    const before = model.transcript_details_expanded_flags;
    toggle(&model, max_details);
    toggle(&model, max_details + 8);
    try std.testing.expectEqual(before, model.transcript_details_expanded_flags);
}

test "transcript details flags stay independent of Files Preview details" {
    var model = Model{};
    const file_preview_details = @import("file_preview_details.zig");

    toggle(&model, 0);
    try std.testing.expect(expanded(&model)[0]);
    try std.testing.expect(!file_preview_details.expanded(&model)[0]);

    file_preview_details.toggle(&model, 1);
    try std.testing.expect(expanded(&model)[0]);
    try std.testing.expect(!expanded(&model)[1]);
    try std.testing.expect(!file_preview_details.expanded(&model)[0]);
    try std.testing.expect(file_preview_details.expanded(&model)[1]);

    drop(&model);
    try std.testing.expect(!expanded(&model)[0]);
    try std.testing.expect(file_preview_details.expanded(&model)[1]);
}

test "drop clears flags on session switch / New Task / remove" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    const first = model.addSession("tx details first", .fx);
    const second = model.addSession("tx details second", .fx);
    model.selected = first;
    _ = model.appendTurn(first, .assistant,
        \\<details>
        \\<summary>More</summary>
        \\
        \\Hidden
        \\
        \\</details>
        \\
    );

    main.update(&model, .{ .transcript_toggle_details = 0 }, &fx);
    try std.testing.expect(expanded(&model)[0]);
    try std.testing.expect(!expanded(&model)[1]);

    main.update(&model, .{ .select = second }, &fx);
    try std.testing.expectEqual(second, model.selected);
    try std.testing.expect(!expanded(&model)[0]);
    try std.testing.expect(!expanded(&model)[1]);

    main.update(&model, .{ .transcript_toggle_details = 0 }, &fx);
    try std.testing.expect(expanded(&model)[0]);

    main.update(&model, .new_session, &fx);
    try std.testing.expect(!expanded(&model)[0]);

    main.update(&model, .{ .transcript_toggle_details = 2 }, &fx);
    try std.testing.expect(expanded(&model)[2]);
    const keep = model.selected;
    main.update(&model, .{ .remove_session = keep }, &fx);
    try std.testing.expect(!expanded(&model)[2]);
}
