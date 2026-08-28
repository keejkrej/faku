//! Composer chip, access, effort, slash-prefix, file-mention, and attach helpers.
//!
//! Access / effort labels, chip option tables, slash command prefix,
//! caret-at-end `@` mention parse/insert, mention path score / labels,
//! and image-drop path checks live here. Model chip cycling and persist
//! stay in `main.zig`.

const std = @import("std");

pub const access_chip_options = [_]struct { id: []const u8, label: []const u8 }{
    .{ .id = "ask", .label = "Ask" },
    .{ .id = "auto", .label = "Auto" },
    .{ .id = "fullAccess", .label = "Full access" },
};

pub const effort_chip_options = [_]struct { id: []const u8, label: []const u8 }{
    .{ .id = "auto", .label = "Auto" },
    .{ .id = "none", .label = "None" },
    .{ .id = "minimal", .label = "Minimal" },
    .{ .id = "low", .label = "Low" },
    .{ .id = "medium", .label = "Medium" },
    .{ .id = "high", .label = "High" },
    .{ .id = "xhigh", .label = "Extra high" },
    .{ .id = "max", .label = "Max" },
};

/// Waku `runtime_mode` → verified `FX_PERMISSION_MODE` (`ask`/`auto`/`yolo`).
/// Unknown strings persist but do not set the env.
pub fn fxPermissionMode(access_mode: []const u8) []const u8 {
    if (std.mem.eql(u8, access_mode, "ask")) return "ask";
    if (std.mem.eql(u8, access_mode, "autoAcceptEdits")) return "auto";
    if (std.mem.eql(u8, access_mode, "auto")) return "auto";
    if (std.mem.eql(u8, access_mode, "fullAccess")) return "yolo";
    if (std.mem.eql(u8, access_mode, "yolo")) return "yolo";
    return "";
}

/// ask → auto → fullAccess. `autoAcceptEdits` counts as auto; `yolo` / empty
/// count as fullAccess. Unknown strings restart at ask.
pub fn nextAccessMode(access_mode: []const u8) []const u8 {
    if (std.mem.eql(u8, access_mode, "ask")) return "auto";
    if (std.mem.eql(u8, access_mode, "auto") or std.mem.eql(u8, access_mode, "autoAcceptEdits")) return "fullAccess";
    return "ask";
}

pub fn accessLabel(access_mode: []const u8) []const u8 {
    if (std.mem.eql(u8, access_mode, "ask")) return "Ask";
    if (std.mem.eql(u8, access_mode, "auto") or std.mem.eql(u8, access_mode, "autoAcceptEdits")) return "Auto";
    return "Full access";
}

/// auto → none → minimal → low → medium → high → xhigh → max → auto.
/// Empty and unknown strings restart at none (same as starting from auto).
pub fn nextReasoningEffort(effort: []const u8) []const u8 {
    if (std.mem.eql(u8, effort, "auto") or effort.len == 0) return "none";
    if (std.mem.eql(u8, effort, "none")) return "minimal";
    if (std.mem.eql(u8, effort, "minimal")) return "low";
    if (std.mem.eql(u8, effort, "low")) return "medium";
    if (std.mem.eql(u8, effort, "medium")) return "high";
    if (std.mem.eql(u8, effort, "high")) return "xhigh";
    if (std.mem.eql(u8, effort, "xhigh")) return "max";
    return "auto";
}

pub fn effortLabel(effort: []const u8) []const u8 {
    if (std.mem.eql(u8, effort, "none")) return "None";
    if (std.mem.eql(u8, effort, "minimal")) return "Minimal";
    if (std.mem.eql(u8, effort, "low")) return "Low";
    if (std.mem.eql(u8, effort, "medium")) return "Medium";
    if (std.mem.eql(u8, effort, "high")) return "High";
    if (std.mem.eql(u8, effort, "xhigh")) return "Extra high";
    if (std.mem.eql(u8, effort, "max")) return "Max";
    return "Auto";
}

pub fn isDocumentedReasoningEffort(effort: []const u8) bool {
    return std.mem.eql(u8, effort, "auto") or
        std.mem.eql(u8, effort, "none") or
        std.mem.eql(u8, effort, "minimal") or
        std.mem.eql(u8, effort, "low") or
        std.mem.eql(u8, effort, "medium") or
        std.mem.eql(u8, effort, "high") or
        std.mem.eql(u8, effort, "xhigh") or
        std.mem.eql(u8, effort, "max");
}

/// Active slash prefix: draft starts with `/` and the first token has
/// no whitespace yet. Returns the name after `/` (`""` for `/` alone).
/// `/commit ` or later text is a completed command — not a prefix.
pub fn slashCommandPrefix(draft: []const u8) ?[]const u8 {
    if (draft.len == 0 or draft[0] != '/') return null;
    const rest = draft[1..];
    for (rest) |c| {
        if (std.ascii.isWhitespace(c)) return null;
    }
    return rest;
}

/// Active `@` mention assuming the caret is at the end (Native has no
/// caret API). Last whitespace-separated token must start with `@`.
/// `see @src` → `src`; `@` alone → `""`; `user@host` does not trigger.
/// Mid-prompt `@foo` with more text after it is not a mention — this
/// cut does not fake a caret. Slash prefix stays authoritative.
pub fn fileMentionQuery(draft: []const u8) ?[]const u8 {
    if (slashCommandPrefix(draft) != null) return null;
    if (draft.len == 0) return null;
    var start = draft.len;
    while (start > 0 and !std.ascii.isWhitespace(draft[start - 1])) {
        start -= 1;
    }
    const token = draft[start..];
    if (token.len == 0 or token[0] != '@') return null;
    return token[1..];
}

/// Replace only the last `@query` token with `@relpath` plus a trailing
/// space. Keeps the rest of the draft. `null` when there is no active
/// mention, `relpath` is empty, or the result does not fit `out`.
pub fn replaceMentionToken(draft: []const u8, relpath: []const u8, out: []u8) ?[]const u8 {
    const query = fileMentionQuery(draft) orelse return null;
    if (relpath.len == 0) return null;
    const token_start = draft.len - query.len - 1;
    return std.fmt.bufPrint(out, "{s}@{s} ", .{ draft[0..token_start], relpath }) catch null;
}

/// Basename of a repo-relative mention path (`/` separators). A trailing
/// slash is a derived directory: `src/` → `src`, `src/lib/` → `lib`.
/// File paths keep today's labels (`src/main.zig` → `main.zig`).
pub fn fileMentionBasename(path: []const u8) []const u8 {
    const trimmed = withoutTrailingSlash(path);
    if (trimmed.len == 0) return "";
    if (std.mem.lastIndexOfScalar(u8, trimmed, '/')) |slash| {
        if (slash + 1 < trimmed.len) return trimmed[slash + 1 ..];
        return "";
    }
    return trimmed;
}

/// Parent directory of a repo-relative mention path, or `""` at the repo
/// root. Trailing-slash dirs drop the last segment (`src/lib/` → `src`;
/// `src/` → `""`). File paths keep today's labels.
pub fn fileMentionParent(path: []const u8) []const u8 {
    const trimmed = withoutTrailingSlash(path);
    if (std.mem.lastIndexOfScalar(u8, trimmed, '/')) |slash| {
        return trimmed[0..slash];
    }
    return "";
}

fn withoutTrailingSlash(path: []const u8) []const u8 {
    var end = path.len;
    while (end > 0 and path[end - 1] == '/') end -= 1;
    return path[0..end];
}

/// Waku-style mention depth: slash count, minus one for a trailing-slash
/// directory so `src/` and `README.md` are both top-level.
pub fn fileMentionDepth(path: []const u8) u32 {
    var slashes: u32 = 0;
    for (path) |c| {
        if (c == '/') slashes += 1;
    }
    if (slashes > 0 and path.len > 0 and path[path.len - 1] == '/') {
        return slashes - 1;
    }
    return slashes;
}

/// Score a tracked relative path against the active `@` mention query.
/// `0` means exclude (same match family as `asciiContainsIgnoreCase`).
/// Empty query: every path scores equally so callers can tie-break by
/// Waku depth, then path, then id. Non-empty tiers, highest first:
/// basename prefix, basename contains / path-segment prefix, then
/// full-path ascii-contains. Small earlier-match / shorter-name
/// bonuses stay inside a tier. Not Waku's fuzzy rank or a 50k index.
/// A trailing-slash dir uses the same basename as its label, so
/// query `src` ranks `src/` as a basename prefix above `src/main.zig`.
pub fn fileMentionScore(path: []const u8, query: []const u8) u32 {
    if (query.len == 0) return mention_score_empty;
    const name = fileMentionBasename(path);
    if (asciiStartsWithIgnoreCase(name, query)) {
        return mention_score_basename_prefix + mentionScoreBonus(0, name.len);
    }
    if (asciiIndexOfIgnoreCase(name, query)) |idx| {
        return mention_score_basename_contains + mentionScoreBonus(idx, name.len);
    }
    if (pathSegmentHasPrefix(path, query)) |seg_start| {
        return mention_score_segment_prefix + mentionScoreBonus(seg_start, path.len);
    }
    if (asciiIndexOfIgnoreCase(path, query)) |idx| {
        return mention_score_path_contains + mentionScoreBonus(idx, path.len);
    }
    return 0;
}

const mention_score_empty: u32 = 1;
const mention_score_path_contains: u32 = 100;
const mention_score_segment_prefix: u32 = 300;
const mention_score_basename_contains: u32 = 320;
const mention_score_basename_prefix: u32 = 400;

fn mentionScoreBonus(match_index: usize, haystack_len: usize) u32 {
    const index_part: u32 = if (match_index < 48) @intCast(48 - match_index) else 0;
    const len_part: u32 = if (haystack_len < 24) @intCast(24 - haystack_len) else 0;
    return index_part + len_part;
}

fn asciiEqlIgnoreCase(left: []const u8, right: []const u8) bool {
    if (left.len != right.len) return false;
    for (left, right) |a, b| {
        if (std.ascii.toLower(a) != std.ascii.toLower(b)) return false;
    }
    return true;
}

fn asciiStartsWithIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (needle.len > haystack.len) return false;
    return asciiEqlIgnoreCase(haystack[0..needle.len], needle);
}

fn asciiIndexOfIgnoreCase(haystack: []const u8, needle: []const u8) ?usize {
    if (needle.len == 0) return 0;
    if (needle.len > haystack.len) return null;
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        if (asciiEqlIgnoreCase(haystack[i .. i + needle.len], needle)) return i;
    }
    return null;
}

/// First path-segment start that the query prefixes, or `null`.
fn pathSegmentHasPrefix(path: []const u8, query: []const u8) ?usize {
    var start: usize = 0;
    var i: usize = 0;
    while (i <= path.len) : (i += 1) {
        if (i == path.len or path[i] == '/') {
            if (asciiStartsWithIgnoreCase(path[start..i], query)) return start;
            start = i + 1;
        }
    }
    return null;
}

/// First dropped path that is a local image Faku already understands
/// for `fx ask --image` / attach preview. Existing extensions only:
/// png, jpg, jpeg, webp, gif. Directories (trailing separator) and
/// empty lists are ignored.
pub fn imagePathFromDrop(paths: []const []const u8) ?[]const u8 {
    for (paths) |raw| {
        const path = std.mem.trim(u8, raw, " \t\r\n");
        if (!isAttachImagePath(path)) continue;
        return path;
    }
    return null;
}

pub fn isAttachImagePath(path: []const u8) bool {
    if (path.len == 0) return false;
    const last = path[path.len - 1];
    if (last == '/' or last == '\\') return false;
    const ext = std.fs.path.extension(path);
    return std.ascii.eqlIgnoreCase(ext, ".png") or
        std.ascii.eqlIgnoreCase(ext, ".jpg") or
        std.ascii.eqlIgnoreCase(ext, ".jpeg") or
        std.ascii.eqlIgnoreCase(ext, ".webp") or
        std.ascii.eqlIgnoreCase(ext, ".gif");
}

test "fileMentionQuery is caret-at-end; slash prefix wins" {
    try std.testing.expectEqualStrings("src", fileMentionQuery("see @src").?);
    try std.testing.expectEqualStrings("", fileMentionQuery("@").?);
    try std.testing.expectEqualStrings("", fileMentionQuery("see @").?);
    try std.testing.expectEqualStrings("src/foo", fileMentionQuery("look @src/foo").?);
    try std.testing.expect(fileMentionQuery("user@host") == null);
    try std.testing.expect(fileMentionQuery("see @src more") == null);
    try std.testing.expect(fileMentionQuery("see @src ") == null);
    try std.testing.expect(fileMentionQuery("") == null);
    try std.testing.expect(fileMentionQuery("/commit") == null);
    try std.testing.expect(fileMentionQuery("/") == null);
    try std.testing.expect(fileMentionQuery("/@src") == null);
}

test "replaceMentionToken rewrites only the last @query token and appends a space" {
    var buf: [64]u8 = undefined;
    try std.testing.expectEqualStrings("see @src/main.zig ", replaceMentionToken("see @src", "src/main.zig", &buf).?);
    try std.testing.expectEqualStrings("see @src/ ", replaceMentionToken("see @src", "src/", &buf).?);
    try std.testing.expectEqualStrings("@src/composer.zig ", replaceMentionToken("@", "src/composer.zig", &buf).?);
    try std.testing.expectEqualStrings("look @src/foo.zig ", replaceMentionToken("look @src", "src/foo.zig", &buf).?);
    try std.testing.expect(replaceMentionToken("user@host", "src/main.zig", &buf) == null);
    try std.testing.expect(replaceMentionToken("see @src more", "src/main.zig", &buf) == null);
    try std.testing.expect(replaceMentionToken("/commit", "src/main.zig", &buf) == null);
    try std.testing.expect(replaceMentionToken("@src", "", &buf) == null);
}

test "fileMentionScore prefers basename prefix over contains" {
    try std.testing.expect(fileMentionScore("src/main.zig", "mai") > fileMentionScore("notes/email.md", "mai"));
    try std.testing.expect(fileMentionScore("src/main.zig", "MAI") > fileMentionScore("notes/email.md", "mai"));
    try std.testing.expect(fileMentionScore("main.zig", "mai") > fileMentionScore("lib/email.md", "mai"));
    try std.testing.expect(fileMentionScore("src/lib/util.zig", "lib") > fileMentionScore("vendor/jslib/index.js", "lib"));
    try std.testing.expectEqual(fileMentionScore("src/main.zig", ""), fileMentionScore("notes/email.md", ""));
    try std.testing.expect(fileMentionScore("src/main.zig", "") > 0);
    try std.testing.expectEqual(@as(u32, 0), fileMentionScore("src/foo.zig", "bar"));
    try std.testing.expectEqual(@as(u32, 0), fileMentionScore("README.md", "mai"));
    try std.testing.expectEqualStrings("main.zig", fileMentionBasename("src/main.zig"));
    try std.testing.expectEqualStrings("src", fileMentionParent("src/main.zig"));
    try std.testing.expectEqualStrings("README.md", fileMentionBasename("README.md"));
    try std.testing.expectEqualStrings("", fileMentionParent("README.md"));
    try std.testing.expectEqualStrings("src", fileMentionBasename("src/"));
    try std.testing.expectEqualStrings("", fileMentionParent("src/"));
    try std.testing.expectEqualStrings("lib", fileMentionBasename("src/lib/"));
    try std.testing.expectEqualStrings("src", fileMentionParent("src/lib/"));
    try std.testing.expect(fileMentionScore("src/", "src") > fileMentionScore("src/main.zig", "src"));
    try std.testing.expectEqual(@as(u32, 0), fileMentionDepth("README.md"));
    try std.testing.expectEqual(@as(u32, 0), fileMentionDepth("src/"));
    try std.testing.expectEqual(@as(u32, 1), fileMentionDepth("src/main.zig"));
    try std.testing.expectEqual(@as(u32, 1), fileMentionDepth("src/lib/"));
    try std.testing.expectEqual(@as(u32, 2), fileMentionDepth("src/lib/util.zig"));
}
