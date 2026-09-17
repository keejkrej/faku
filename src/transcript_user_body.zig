//! First-cut user-message height cap (Waku `USER_MESSAGE_MAX_HEIGHT`).
//!
//! Native UI documents definite `height` / `max-width` / `min-width`
//! but **no element `max-height`**, and no GPUI edge-fade widget.
//! Tall **user** transcript bubbles therefore wrap markdown in a
//! documented inner `<scroll height="384" overscroll="none">` when a
//! cheap model-facts estimate exceeds Waku's 400px cap. Short user
//! bubbles stay today's uncapped `<bubble><markdown>`. Assistant /
//! tool / reasoning stay uncapped this cut.
//!
//! The estimate is pure: newline count and wrap-bytes × a conservative
//! 20px line height, plus a small markdown chrome pad. Not a layout
//! measurement. `overscroll="none"` pins the nested region so the
//! outer transcript scroll still works (no invented contain API).

const std = @import("std");

/// Waku `USER_MESSAGE_MAX_HEIGHT`. Cap when `estimatedHeight` exceeds
/// this. Native has no element `max-height`.
pub const max_height: u32 = 400;
/// Waku inner scroll viewport when the user body is capped. Native
/// `<scroll height="384">`.
pub const scroll_height: u32 = 384;
/// Conservative line height for the estimate. Not a layout measure.
pub const line_height: u32 = 20;
/// Small pad for markdown / bubble chrome (matches 400 − 384).
pub const chrome_pad: u32 = 16;
/// Conservative wrap width in bytes (narrow-ish user bubble). A long
/// paste without newlines still caps.
pub const wrap_bytes: u32 = 48;

/// Cheap height from model facts only: each `\n` starts a line, and
/// every `wrap_bytes` of a logical line wraps. Empty text is one line.
pub fn estimatedHeight(text: []const u8) u32 {
    var lines: u32 = 1;
    var col: u32 = 0;
    for (text) |c| {
        if (c == '\n') {
            lines += 1;
            col = 0;
            continue;
        }
        col += 1;
        if (col >= wrap_bytes) {
            lines += 1;
            col = 0;
        }
    }
    return lines * line_height + chrome_pad;
}

/// True when the estimate exceeds Waku `USER_MESSAGE_MAX_HEIGHT` 400.
pub fn capped(text: []const u8) bool {
    return estimatedHeight(text) > max_height;
}

test "Waku 400/384 numbers and conservative estimate constants" {
    try std.testing.expectEqual(@as(u32, 400), max_height);
    try std.testing.expectEqual(@as(u32, 384), scroll_height);
    try std.testing.expectEqual(@as(u32, 20), line_height);
    try std.testing.expectEqual(@as(u32, 16), chrome_pad);
    try std.testing.expectEqual(@as(u32, 48), wrap_bytes);
    try std.testing.expectEqual(max_height - scroll_height, chrome_pad);
}

test "short user bodies stay under the 400 cap" {
    try std.testing.expectEqual(@as(u32, line_height + chrome_pad), estimatedHeight(""));
    try std.testing.expect(!capped(""));
    try std.testing.expect(!capped("hello"));
    try std.testing.expect(!capped("a short paste"));
    try std.testing.expect(!capped("one\ntwo\nthree"));
}

test "many newlines cap; nineteen visual lines stay under" {
    const under = "x\n" ** 18;
    try std.testing.expectEqual(@as(u32, 19 * line_height + chrome_pad), estimatedHeight(under));
    try std.testing.expect(!capped(under));
    try std.testing.expect(estimatedHeight(under) <= max_height);

    const over = "x\n" ** 19;
    try std.testing.expectEqual(@as(u32, 20 * line_height + chrome_pad), estimatedHeight(over));
    try std.testing.expect(capped(over));
    try std.testing.expect(estimatedHeight(over) > max_height);

    const tall = "paste\n" ** 30;
    try std.testing.expect(capped(tall));
}

test "long byte-length paste without newlines caps via wrap" {
    const under = "." ** (wrap_bytes * 18);
    try std.testing.expectEqual(@as(u32, 19 * line_height + chrome_pad), estimatedHeight(under));
    try std.testing.expect(!capped(under));

    const over = "." ** (wrap_bytes * 19);
    try std.testing.expectEqual(@as(u32, 20 * line_height + chrome_pad), estimatedHeight(over));
    try std.testing.expect(capped(over));
}
