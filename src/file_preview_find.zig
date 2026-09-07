//! First-cut Files preview find/replace: plain substring, optional ASCII
//! case-sensitivity. No regex crate, no whole-word, no GPUI washes.
//!
//! Match lists are capped at `max_matches` (Native-friendly; Waku's
//! FileSearch cap is 20_000). Replace All rescans without that cap so
//! a limited highlight list cannot skip the tail of the buffer.

const std = @import("std");

/// Navigable / counted matches. Smaller than Waku's 20k because Native
/// has no match-wash ranges this cut.
pub const max_matches: usize = 2048;

pub const Scan = struct {
    count: u32 = 0,
    limited: bool = false,
};

pub fn collect(
    haystack: []const u8,
    query: []const u8,
    case_sensitive: bool,
    starts: []u32,
) Scan {
    var scan: Scan = .{};
    if (query.len == 0 or starts.len == 0) return scan;
    var i: usize = 0;
    while (i + query.len <= haystack.len) {
        if (!eqlSlice(haystack[i .. i + query.len], query, case_sensitive)) {
            i += 1;
            continue;
        }
        if (scan.count >= starts.len) {
            scan.limited = true;
            break;
        }
        starts[scan.count] = @intCast(i);
        scan.count += 1;
        i += query.len;
    }
    return scan;
}

/// First match starting at or after `offset`, wrapping to 0.
pub fn matchAtOrAfter(starts: []const u32, count: u32, offset: u32) u32 {
    if (count == 0) return 0;
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        if (starts[i] >= offset) return i;
    }
    return 0;
}

pub fn stepIndex(count: u32, current: u32, backward: bool) u32 {
    if (count == 0) return 0;
    var cur = current;
    if (cur >= count) cur = 0;
    if (backward) {
        return if (cur == 0) count - 1 else cur - 1;
    }
    return if (cur + 1 >= count) 0 else cur + 1;
}

/// 1-based line of `offset` (newline is a terminator). `offset` past
/// the end still reports the last line.
pub fn lineNumberAt(haystack: []const u8, offset: usize) u32 {
    var line: u32 = 1;
    const end = @min(offset, haystack.len);
    var i: usize = 0;
    while (i < end) : (i += 1) {
        if (haystack[i] == '\n') line += 1;
    }
    return line;
}

/// Splice `replacement` over `[start, start + match_len)`. Null when
/// the result would not fit in `dest`.
pub fn replaceOne(
    haystack: []const u8,
    start: usize,
    match_len: usize,
    replacement: []const u8,
    dest: []u8,
) ?[]u8 {
    if (start > haystack.len) return null;
    const end = start + match_len;
    if (end > haystack.len) return null;
    const out_len = haystack.len - match_len + replacement.len;
    if (out_len > dest.len) return null;
    @memcpy(dest[0..start], haystack[0..start]);
    @memcpy(dest[start .. start + replacement.len], replacement);
    @memcpy(dest[start + replacement.len .. out_len], haystack[end..]);
    return dest[0..out_len];
}

/// Replace every non-overlapping match, uncapped. Null when `dest` is
/// too small. Empty query is a no-op copy when it fits.
pub fn replaceAll(
    haystack: []const u8,
    query: []const u8,
    replacement: []const u8,
    case_sensitive: bool,
    dest: []u8,
) ?[]u8 {
    if (query.len == 0) {
        if (haystack.len > dest.len) return null;
        @memcpy(dest[0..haystack.len], haystack);
        return dest[0..haystack.len];
    }
    var out: usize = 0;
    var i: usize = 0;
    while (i < haystack.len) {
        if (i + query.len <= haystack.len and eqlSlice(haystack[i .. i + query.len], query, case_sensitive)) {
            if (out + replacement.len > dest.len) return null;
            @memcpy(dest[out .. out + replacement.len], replacement);
            out += replacement.len;
            i += query.len;
            continue;
        }
        if (out + 1 > dest.len) return null;
        dest[out] = haystack[i];
        out += 1;
        i += 1;
    }
    return dest[0..out];
}

fn eqlSlice(left: []const u8, right: []const u8, case_sensitive: bool) bool {
    if (left.len != right.len) return false;
    if (case_sensitive) return std.mem.eql(u8, left, right);
    for (left, right) |a, b| {
        if (std.ascii.toLower(a) != std.ascii.toLower(b)) return false;
    }
    return true;
}

test "collect is case-sensitive substring and caps" {
    var starts: [max_matches]u32 = undefined;
    const hay = "Aaa aa AA aa";
    const sensitive = collect(hay, "aa", true, starts[0..]);
    try std.testing.expectEqual(@as(u32, 2), sensitive.count);
    try std.testing.expect(!sensitive.limited);
    try std.testing.expectEqual(@as(u32, 4), starts[0]);
    try std.testing.expectEqual(@as(u32, 10), starts[1]);

    const insensitive = collect(hay, "aa", false, starts[0..]);
    try std.testing.expectEqual(@as(u32, 4), insensitive.count);
    try std.testing.expectEqual(@as(u32, 0), starts[0]);
    try std.testing.expectEqual(@as(u32, 4), starts[1]);
    try std.testing.expectEqual(@as(u32, 7), starts[2]);
    try std.testing.expectEqual(@as(u32, 10), starts[3]);

    const empty = collect(hay, "", true, starts[0..]);
    try std.testing.expectEqual(@as(u32, 0), empty.count);

    var tiny: [2]u32 = undefined;
    const capped = collect("aa aa aa aa", "aa", true, tiny[0..]);
    try std.testing.expectEqual(@as(u32, 2), capped.count);
    try std.testing.expect(capped.limited);
}

test "stepIndex wraps; matchAtOrAfter re-anchors" {
    try std.testing.expectEqual(@as(u32, 0), stepIndex(0, 0, false));
    try std.testing.expectEqual(@as(u32, 1), stepIndex(3, 0, false));
    try std.testing.expectEqual(@as(u32, 0), stepIndex(3, 2, false));
    try std.testing.expectEqual(@as(u32, 2), stepIndex(3, 0, true));
    try std.testing.expectEqual(@as(u32, 1), stepIndex(3, 2, true));

    const starts = [_]u32{ 2, 8, 20 };
    try std.testing.expectEqual(@as(u32, 0), matchAtOrAfter(&starts, 3, 0));
    try std.testing.expectEqual(@as(u32, 1), matchAtOrAfter(&starts, 3, 8));
    try std.testing.expectEqual(@as(u32, 2), matchAtOrAfter(&starts, 3, 9));
    try std.testing.expectEqual(@as(u32, 0), matchAtOrAfter(&starts, 3, 21));
}

test "replace one and replace all on a buffer" {
    var dest: [64]u8 = undefined;
    const one = replaceOne("keep foo keep foo", 5, 3, "bar", dest[0..]).?;
    try std.testing.expectEqualStrings("keep bar keep foo", one);

    const all = replaceAll("keep foo keep foo", "foo", "bar", true, dest[0..]).?;
    try std.testing.expectEqualStrings("keep bar keep bar", all);

    const deleted = replaceAll("aa-aa", "aa", "", true, dest[0..]).?;
    try std.testing.expectEqualStrings("-", deleted);

    const insensitive = replaceAll("Foo foo FOO", "foo", "x", false, dest[0..]).?;
    try std.testing.expectEqualStrings("x x x", insensitive);

    var tiny: [4]u8 = undefined;
    try std.testing.expect(replaceAll("aaaa", "a", "bb", true, tiny[0..]) == null);
}

test "lineNumberAt is 1-based" {
    const body = "one\ntwo\nthree";
    try std.testing.expectEqual(@as(u32, 1), lineNumberAt(body, 0));
    try std.testing.expectEqual(@as(u32, 1), lineNumberAt(body, 3));
    try std.testing.expectEqual(@as(u32, 2), lineNumberAt(body, 4));
    try std.testing.expectEqual(@as(u32, 3), lineNumberAt(body, 8));
    try std.testing.expectEqual(@as(u32, 3), lineNumberAt(body, body.len));
}
