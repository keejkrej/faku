//! First-cut Files preview find/replace: plain substring or regex, with
//! optional ASCII case-sensitivity and whole-word. No GPUI washes.
//!
//! Default path (regex off) is today's substring collect/replaceAll.
//! Regex on uses a self-contained Zig subset (`file_preview_regex.zig`)
//! matching Waku `compile_search` wrapping: case fold when Aa is off,
//! whole-word as `\b(?:pattern)\b`, empty query → zero matches, invalid
//! pattern → `Scan.invalid` rather than a silent fallback. Zero-width
//! hits are skipped. Navigable matches stay capped at `max_matches`;
//! Replace All rescans without that cap so the tail is not skipped.
//!
//! Whole-word in plain mode is ASCII `[A-Za-z0-9_]` boundaries, same as
//! the Ab chip. Case, whole-word, and regex compose independently.

const std = @import("std");
const regex = @import("file_preview_regex.zig");

/// Navigable / counted matches. Matches Waku FileSearch's 20k.
/// Native still has no match-wash ranges this cut.
pub const max_matches: usize = 20_000;

pub const Scan = struct {
    count: u32 = 0,
    limited: bool = false,
    invalid: bool = false,
};

pub fn collect(
    haystack: []const u8,
    query: []const u8,
    case_sensitive: bool,
    whole_word: bool,
    use_regex: bool,
    starts: []u32,
    ends: []u32,
) Scan {
    var scan: Scan = .{};
    const cap = @min(starts.len, ends.len);
    if (query.len == 0 or cap == 0) return scan;
    if (use_regex) return collectRegex(haystack, query, case_sensitive, whole_word, starts[0..cap], ends[0..cap]);
    var i: usize = 0;
    while (i + query.len <= haystack.len) {
        if (!matchAt(haystack, i, query, case_sensitive, whole_word)) {
            i += 1;
            continue;
        }
        if (scan.count >= cap) {
            scan.limited = true;
            break;
        }
        starts[scan.count] = @intCast(i);
        ends[scan.count] = @intCast(i + query.len);
        scan.count += 1;
        i += query.len;
    }
    return scan;
}

fn collectRegex(
    haystack: []const u8,
    query: []const u8,
    case_sensitive: bool,
    whole_word: bool,
    starts: []u32,
    ends: []u32,
) Scan {
    const prog = regex.compile(query, case_sensitive, whole_word) orelse return .{ .invalid = true };
    var scan: Scan = .{};
    var from: usize = 0;
    while (regex.find(&prog, haystack, from)) |hit| {
        if (scan.count >= starts.len) {
            scan.limited = true;
            break;
        }
        starts[scan.count] = @intCast(hit.start);
        ends[scan.count] = @intCast(hit.end);
        scan.count += 1;
        from = hit.end;
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
    whole_word: bool,
    use_regex: bool,
    dest: []u8,
) ?[]u8 {
    if (query.len == 0) {
        if (haystack.len > dest.len) return null;
        @memcpy(dest[0..haystack.len], haystack);
        return dest[0..haystack.len];
    }
    if (use_regex) return replaceAllRegex(haystack, query, replacement, case_sensitive, whole_word, dest);
    var out: usize = 0;
    var i: usize = 0;
    while (i < haystack.len) {
        if (matchAt(haystack, i, query, case_sensitive, whole_word)) {
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

fn replaceAllRegex(
    haystack: []const u8,
    query: []const u8,
    replacement: []const u8,
    case_sensitive: bool,
    whole_word: bool,
    dest: []u8,
) ?[]u8 {
    const prog = regex.compile(query, case_sensitive, whole_word) orelse {
        if (haystack.len > dest.len) return null;
        @memcpy(dest[0..haystack.len], haystack);
        return dest[0..haystack.len];
    };
    var out: usize = 0;
    var i: usize = 0;
    while (regex.find(&prog, haystack, i)) |hit| {
        const gap = hit.start - i;
        if (out + gap > dest.len) return null;
        @memcpy(dest[out .. out + gap], haystack[i..hit.start]);
        out += gap;
        const piece = regex.expand(replacement, haystack, hit, dest[out..]) orelse return null;
        out += piece.len;
        i = hit.end;
    }
    const tail = haystack.len - i;
    if (out + tail > dest.len) return null;
    @memcpy(dest[out .. out + tail], haystack[i..]);
    return dest[0..out + tail];
}

/// Expand `$n` / `${n}` / `$$` when `use_regex` is on. Plain mode copies
/// `template` verbatim (a literal `$` stays `$`).
pub fn expandReplacement(
    haystack: []const u8,
    query: []const u8,
    match_start: usize,
    match_end: usize,
    template: []const u8,
    case_sensitive: bool,
    whole_word: bool,
    use_regex: bool,
    dest: []u8,
) ?[]u8 {
    if (!use_regex) {
        if (template.len > dest.len) return null;
        @memcpy(dest[0..template.len], template);
        return dest[0..template.len];
    }
    const prog = regex.compile(query, case_sensitive, whole_word) orelse {
        if (template.len > dest.len) return null;
        @memcpy(dest[0..template.len], template);
        return dest[0..template.len];
    };
    const hit = regex.exec(&prog, haystack, match_start) orelse {
        if (template.len > dest.len) return null;
        @memcpy(dest[0..template.len], template);
        return dest[0..template.len];
    };
    if (hit.start != match_start or hit.end != match_end) {
        if (template.len > dest.len) return null;
        @memcpy(dest[0..template.len], template);
        return dest[0..template.len];
    }
    return regex.expand(template, haystack, hit, dest);
}

fn isAsciiWordChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
}

fn isWholeWordAt(haystack: []const u8, start: usize, match_len: usize) bool {
    if (start > 0 and isAsciiWordChar(haystack[start - 1])) return false;
    const after = start + match_len;
    if (after < haystack.len and isAsciiWordChar(haystack[after])) return false;
    return true;
}

fn matchAt(
    haystack: []const u8,
    i: usize,
    query: []const u8,
    case_sensitive: bool,
    whole_word: bool,
) bool {
    if (i + query.len > haystack.len) return false;
    if (!eqlSlice(haystack[i .. i + query.len], query, case_sensitive)) return false;
    if (!whole_word) return true;
    return isWholeWordAt(haystack, i, query.len);
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
    var starts: [16]u32 = undefined;
    var ends: [16]u32 = undefined;
    // "Aa" / "AA" match insensitive "aa" only. "Aaa aa" would also
    // match sensitive "aa" at the tail of "Aaa".
    const hay = "Aa aa AA aa";
    const sensitive = collect(hay, "aa", true, false, false, starts[0..], ends[0..]);
    try std.testing.expectEqual(@as(u32, 2), sensitive.count);
    try std.testing.expect(!sensitive.limited);
    try std.testing.expect(!sensitive.invalid);
    try std.testing.expectEqual(@as(u32, 3), starts[0]);
    try std.testing.expectEqual(@as(u32, 9), starts[1]);
    try std.testing.expectEqual(@as(u32, 5), ends[0]);
    try std.testing.expectEqual(@as(u32, 11), ends[1]);

    const insensitive = collect(hay, "aa", false, false, false, starts[0..], ends[0..]);
    try std.testing.expectEqual(@as(u32, 4), insensitive.count);
    try std.testing.expectEqual(@as(u32, 0), starts[0]);
    try std.testing.expectEqual(@as(u32, 3), starts[1]);
    try std.testing.expectEqual(@as(u32, 6), starts[2]);
    try std.testing.expectEqual(@as(u32, 9), starts[3]);

    const empty = collect(hay, "", true, false, false, starts[0..], ends[0..]);
    try std.testing.expectEqual(@as(u32, 0), empty.count);

    var tiny_s: [2]u32 = undefined;
    var tiny_e: [2]u32 = undefined;
    const capped = collect("aa aa aa aa", "aa", true, false, false, tiny_s[0..], tiny_e[0..]);
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

    const all = replaceAll("keep foo keep foo", "foo", "bar", true, false, false, dest[0..]).?;
    try std.testing.expectEqualStrings("keep bar keep bar", all);

    const deleted = replaceAll("aa-aa", "aa", "", true, false, false, dest[0..]).?;
    try std.testing.expectEqualStrings("-", deleted);

    const insensitive = replaceAll("Foo foo FOO", "foo", "x", false, false, false, dest[0..]).?;
    try std.testing.expectEqualStrings("x x x", insensitive);

    var tiny: [4]u8 = undefined;
    try std.testing.expect(replaceAll("aaaa", "a", "bb", true, false, false, tiny[0..]) == null);
}

test "collect and replaceAll respect whole-word ASCII boundaries" {
    var starts: [16]u32 = undefined;
    var ends: [16]u32 = undefined;
    const hay = "foo foobar foo_bar foo";

    const all = collect(hay, "foo", true, false, false, starts[0..], ends[0..]);
    try std.testing.expectEqual(@as(u32, 4), all.count);
    try std.testing.expectEqual(@as(u32, 0), starts[0]);
    try std.testing.expectEqual(@as(u32, 4), starts[1]);
    try std.testing.expectEqual(@as(u32, 11), starts[2]);
    try std.testing.expectEqual(@as(u32, 19), starts[3]);

    const words = collect(hay, "foo", true, true, false, starts[0..], ends[0..]);
    try std.testing.expectEqual(@as(u32, 2), words.count);
    try std.testing.expectEqual(@as(u32, 0), starts[0]);
    try std.testing.expectEqual(@as(u32, 19), starts[1]);

    const mixed = "Foo foobar FOO_BAR foo";
    const insensitive_words = collect(mixed, "foo", false, true, false, starts[0..], ends[0..]);
    try std.testing.expectEqual(@as(u32, 2), insensitive_words.count);
    try std.testing.expectEqual(@as(u32, 0), starts[0]);
    try std.testing.expectEqual(@as(u32, 19), starts[1]);

    const sensitive_words = collect(mixed, "foo", true, true, false, starts[0..], ends[0..]);
    try std.testing.expectEqual(@as(u32, 1), sensitive_words.count);
    try std.testing.expectEqual(@as(u32, 19), starts[0]);

    var dest: [64]u8 = undefined;
    const replaced = replaceAll(hay, "foo", "bar", true, true, false, dest[0..]).?;
    try std.testing.expectEqualStrings("bar foobar foo_bar bar", replaced);

    const empty = collect(hay, "", true, true, false, starts[0..], ends[0..]);
    try std.testing.expectEqual(@as(u32, 0), empty.count);
}

test "regex collect matches patterns, flags invalid, skips zero-width" {
    var starts: [16]u32 = undefined;
    var ends: [16]u32 = undefined;
    const hay = "id: 12, id: 345";
    const digits = collect(hay, "\\d+", false, false, true, starts[0..], ends[0..]);
    try std.testing.expectEqual(@as(u32, 2), digits.count);
    try std.testing.expect(!digits.invalid);
    try std.testing.expectEqual(@as(u32, 4), starts[0]);
    try std.testing.expectEqual(@as(u32, 6), ends[0]);
    try std.testing.expectEqual(@as(u32, 12), starts[1]);
    try std.testing.expectEqual(@as(u32, 15), ends[1]);

    const bad = collect("(unclosed", "(unclosed", false, false, true, starts[0..], ends[0..]);
    try std.testing.expect(bad.invalid);
    try std.testing.expectEqual(@as(u32, 0), bad.count);

    const as_lit = collect("(unclosed", "(unclosed", false, false, false, starts[0..], ends[0..]);
    try std.testing.expect(!as_lit.invalid);
    try std.testing.expectEqual(@as(u32, 1), as_lit.count);
    try std.testing.expectEqual(@as(u32, 0), starts[0]);
    try std.testing.expectEqual(@as(u32, 9), ends[0]);

    const empty = collect(hay, "", false, false, true, starts[0..], ends[0..]);
    try std.testing.expectEqual(@as(u32, 0), empty.count);
    try std.testing.expect(!empty.invalid);

    const zw = collect("aab", "a*", false, false, true, starts[0..], ends[0..]);
    try std.testing.expectEqual(@as(u32, 1), zw.count);
    try std.testing.expectEqual(@as(u32, 0), starts[0]);
    try std.testing.expectEqual(@as(u32, 2), ends[0]);

    var tiny_s: [2]u32 = undefined;
    var tiny_e: [2]u32 = undefined;
    const capped = collect("x x x x", "x", false, false, true, tiny_s[0..], tiny_e[0..]);
    try std.testing.expectEqual(@as(u32, 2), capped.count);
    try std.testing.expect(capped.limited);
}

test "regex composes with case and whole-word" {
    var starts: [16]u32 = undefined;
    var ends: [16]u32 = undefined;
    const hay = "Foo foo FOO foobar";
    const insensitive = collect(hay, "foo", false, false, true, starts[0..], ends[0..]);
    try std.testing.expectEqual(@as(u32, 4), insensitive.count);
    try std.testing.expectEqual(@as(u32, 0), starts[0]);
    try std.testing.expectEqual(@as(u32, 4), starts[1]);
    try std.testing.expectEqual(@as(u32, 8), starts[2]);
    try std.testing.expectEqual(@as(u32, 12), starts[3]);

    const sensitive = collect(hay, "foo", true, false, true, starts[0..], ends[0..]);
    try std.testing.expectEqual(@as(u32, 2), sensitive.count);
    try std.testing.expectEqual(@as(u32, 4), starts[0]);
    try std.testing.expectEqual(@as(u32, 12), starts[1]);

    const words = "cat catalog concat cat";
    const whole = collect(words, "cat", false, true, true, starts[0..], ends[0..]);
    try std.testing.expectEqual(@as(u32, 2), whole.count);
    try std.testing.expectEqual(@as(u32, 0), starts[0]);
    try std.testing.expectEqual(@as(u32, 3), ends[0]);
    try std.testing.expectEqual(@as(u32, 19), starts[1]);
    try std.testing.expectEqual(@as(u32, 22), ends[1]);

    const alt = collect(words, "cat|dog", false, true, true, starts[0..], ends[0..]);
    try std.testing.expectEqual(@as(u32, 2), alt.count);
    try std.testing.expectEqual(@as(u32, 0), starts[0]);
    try std.testing.expectEqual(@as(u32, 19), starts[1]);
}

test "regex replace expands captures; plain keeps dollar" {
    var dest: [64]u8 = undefined;
    const hay = "let alpha = 1;";
    const swapped = replaceAll(hay, "(\\w+) = (\\d+)", "$2 = $1", false, false, true, dest[0..]).?;
    try std.testing.expectEqualStrings("let 1 = alpha;", swapped);

    const literal_dollar = expandReplacement(hay, "alpha", 4, 9, "$1", false, false, false, dest[0..]).?;
    try std.testing.expectEqualStrings("$1", literal_dollar);

    const expanded = expandReplacement(hay, "(\\w+) = (\\d+)", 4, 13, "$2 = $1", false, false, true, dest[0..]).?;
    try std.testing.expectEqualStrings("1 = alpha", expanded);

    const doubled = replaceAll("aa ba aa", "a+", "X", true, false, true, dest[0..]).?;
    try std.testing.expectEqualStrings("X bX X", doubled);

    const escaped_dollar = replaceAll("ab", "(a)(b)", "$$1$2", false, false, true, dest[0..]).?;
    try std.testing.expectEqualStrings("$1b", escaped_dollar);
}

test "collect limited when starts/ends fill max_matches" {
    try std.testing.expectEqual(@as(usize, 20_000), max_matches);
    const allocator = std.testing.allocator;
    const starts = try allocator.alloc(u32, max_matches);
    defer allocator.free(starts);
    const ends = try allocator.alloc(u32, max_matches);
    defer allocator.free(ends);

    const extra: usize = 3;
    const hay = try allocator.alloc(u8, max_matches + extra);
    defer allocator.free(hay);
    @memset(hay, 'a');

    const scan = collect(hay, "a", true, false, false, starts, ends);
    try std.testing.expectEqual(@as(u32, @intCast(max_matches)), scan.count);
    try std.testing.expect(scan.limited);
    try std.testing.expect(!scan.invalid);
    try std.testing.expectEqual(@as(u32, 0), starts[0]);
    try std.testing.expectEqual(@as(u32, 1), ends[0]);
    try std.testing.expectEqual(@as(u32, @intCast(max_matches - 1)), starts[max_matches - 1]);
}

test "lineNumberAt is 1-based" {
    const body = "one\ntwo\nthree";
    try std.testing.expectEqual(@as(u32, 1), lineNumberAt(body, 0));
    try std.testing.expectEqual(@as(u32, 1), lineNumberAt(body, 3));
    try std.testing.expectEqual(@as(u32, 2), lineNumberAt(body, 4));
    try std.testing.expectEqual(@as(u32, 3), lineNumberAt(body, 8));
    try std.testing.expectEqual(@as(u32, 3), lineNumberAt(body, body.len));
}
