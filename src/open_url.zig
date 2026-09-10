//! One-shot OS browser-open sidecar.
//!
//! The right-panel Browser tab embeds a Native canvas webview
//! (`browser_pane.zig` / `web_panes`). This module is the OS-host
//! fallback: `fx.spawn`s a documented host URL open:
//!
//!   macOS:  `open` + URL
//!   Linux:  `xdg-open` + URL
//!   Windows: `cmd.exe /c start "" <url>` (empty title so `start`
//!            does not eat the URL; each token is its own argv slot)
//!
//! This is not Waku's embedded `RightPanelSurface::Browser` UUID tabs.
//! Spawn stdin is unused (write-once then close).
//!
//! URL gate (light): trim whitespace; reject empty. Accept `http://` or
//! `https://` as-is (scheme match is ASCII case-insensitive). Bare hosts
//! and other text get an `https://` prefix. Overflow of the spawn buffer
//! is a miss (same one-line empty status).

const std = @import("std");
const builtin = @import("builtin");
const native_sdk = @import("native_sdk");
const main = @import("main.zig");
const reveal_folder = @import("reveal_folder.zig");
const open_terminal = @import("open_terminal.zig");
const pick_folder = @import("pick_folder.zig");

const Model = main.Model;
const Effects = main.Effects;

/// Distinct from open_editor (26), open_terminal (27), reveal_folder (28),
/// pick_folder (29), maximize (30), pick_image (31), copy_turn (32),
/// attach_preview 33–63, fx_probe (3), fx_spawn 64+, git_branch 200+.
/// 25 sits in that gap and is unused by those tables.
pub const open_url_key: u64 = 25;

pub const missing_exit: u8 = 2;

pub const linux_missing_status = "No OS browser (install xdg-open).";
pub const macos_missing_status = "No OS browser (open missing).";
pub const windows_missing_status = "No OS browser (cmd.exe missing).";
pub const empty_url_status = "Enter a URL to open.";
pub const relative_link_status = "Can't open that link.";

pub const macos_bin = "open";
pub const linux_bin = "xdg-open";
pub const windows_bin = "cmd.exe";
pub const windows_c_flag = "/c";
pub const windows_start = "start";
/// Empty `start` window title. Required so `start` does not treat the
/// URL as a title. Own argv slot — not interpolated into `/c`.
pub const windows_empty_title = "";
pub const https_prefix = "https://";

/// Browser tab draft. Persisted raw on sessions.json extras
/// (`browser_url`); cap is this max. Missing / empty / overflow → empty.
pub const max_url: usize = 2048;
/// Draft plus `https://` when a bare host is prefixed.
pub const max_spawn_url: usize = max_url + https_prefix.len;

pub const Tool = enum { open, xdg_open, cmd_start };

const argv_len: usize = 5;

pub fn hostTool() ?Tool {
    return switch (builtin.os.tag) {
        .macos => .open,
        .linux => .xdg_open,
        .windows => .cmd_start,
        else => null,
    };
}

pub fn hostBin() ?[]const u8 {
    return binFor(hostTool() orelse return null);
}

pub fn hostMissingStatus() []const u8 {
    return switch (builtin.os.tag) {
        .macos => macos_missing_status,
        .windows => windows_missing_status,
        else => linux_missing_status,
    };
}

pub fn binFor(tool: Tool) []const u8 {
    return switch (tool) {
        .open => macos_bin,
        .xdg_open => linux_bin,
        .cmd_start => windows_bin,
    };
}

pub fn argvForTool(tool: Tool, url: []const u8, buf: *[argv_len][]const u8) []const []const u8 {
    switch (tool) {
        .open, .xdg_open => {
            buf[0] = binFor(tool);
            buf[1] = url;
            return buf[0..2];
        },
        .cmd_start => {
            buf[0] = windows_bin;
            buf[1] = windows_c_flag;
            buf[2] = windows_start;
            buf[3] = windows_empty_title;
            buf[4] = url;
            return buf[0..5];
        },
    }
}

pub fn argvFor(url: []const u8, buf: *[argv_len][]const u8) []const []const u8 {
    return argvForTool(hostTool() orelse .xdg_open, url, buf);
}

pub fn isHttpUrl(text: []const u8) bool {
    if (text.len >= 8 and std.ascii.eqlIgnoreCase(text[0..8], "https://")) return true;
    if (text.len >= 7 and std.ascii.eqlIgnoreCase(text[0..7], "http://")) return true;
    return false;
}

/// Path cap for markdown file-link routing (project + mention relpath).
pub const max_file_link_path = main.max_project_path + 256;

/// Relative, `file:`, fragments, and other non-browser targets. Markdown
/// Preview routes these through Files / `reveal_folder` (not `open_url`).
pub fn isRelativeOrFileUrl(raw: []const u8) bool {
    const trimmed = std.mem.trim(u8, raw, " \t\r\n");
    if (trimmed.len == 0) return true;
    if (isHttpUrl(trimmed)) return false;
    if (std.mem.indexOf(u8, trimmed, "://") != null) return true;
    if (std.ascii.startsWithIgnoreCase(trimmed, "mailto:")) return true;
    if (std.ascii.startsWithIgnoreCase(trimmed, "file:")) return true;
    const first = trimmed[0];
    if (first == '#' or first == '/' or first == '.' or first == '\\') return true;
    if (trimmed.len >= 2 and std.ascii.isAlphabetic(trimmed[0]) and trimmed[1] == ':') return true;
    const sep = std.mem.indexOfAny(u8, trimmed, "/\\") orelse return looksLikeFileName(trimmed);
    return std.mem.indexOfScalar(u8, trimmed[0..sep], '.') == null;
}

fn looksLikeFileName(name: []const u8) bool {
    const dot = std.mem.lastIndexOfScalar(u8, name, '.') orelse return false;
    if (dot == 0 or dot + 1 >= name.len) return false;
    const ext = name[dot + 1 ..];
    const files = [_][]const u8{
        "md", "markdown", "txt", "png", "jpg", "jpeg", "gif", "webp", "svg",
        "html", "htm", "zig", "json", "yaml", "yml", "ts", "js", "rs", "go",
        "css", "c", "h", "py",
    };
    for (files) |known| {
        if (std.ascii.eqlIgnoreCase(ext, known)) return true;
    }
    return false;
}

fn positiveNumber(value: []const u8) bool {
    if (value.len == 0) return false;
    for (value) |byte| {
        if (!std.ascii.isDigit(byte)) return false;
    }
    const parsed = std.fmt.parseInt(u32, value, 10) catch return false;
    return parsed > 0;
}

fn lineFragment(fragment: []const u8) bool {
    if (fragment.len < 2 or fragment[0] != 'L') return false;
    const location = fragment[1..];
    if (std.mem.indexOfScalar(u8, location, 'C')) |c_idx| {
        return positiveNumber(location[0..c_idx]) and positiveNumber(location[c_idx + 1 ..]);
    }
    return positiveNumber(location);
}

/// Waku `strip_file_location`: drop `#L12` / `#L12C4` and trailing
/// `:12` / `:12:4` editor fragments so they are not part of the path.
pub fn stripFileLocation(target: []const u8) []const u8 {
    if (std.mem.lastIndexOfScalar(u8, target, '#')) |hash| {
        if (lineFragment(target[hash + 1 ..])) return target[0..hash];
    }
    const last_colon = std.mem.lastIndexOfScalar(u8, target, ':') orelse return target;
    const last = target[last_colon + 1 ..];
    if (!positiveNumber(last)) return target;
    const before_last = target[0..last_colon];
    if (std.mem.lastIndexOfScalar(u8, before_last, ':')) |line_colon| {
        const line = before_last[line_colon + 1 ..];
        if (positiveNumber(line)) return before_last[0..line_colon];
    }
    return before_last;
}

fn hexValue(byte: u8) ?u8 {
    return switch (byte) {
        '0'...'9' => byte - '0',
        'a'...'f' => byte - 'a' + 10,
        'A'...'F' => byte - 'A' + 10,
        else => null,
    };
}

fn validUtf8(bytes: []const u8) bool {
    var i: usize = 0;
    while (i < bytes.len) {
        const len = std.unicode.utf8ByteSequenceLength(bytes[i]) catch return false;
        if (i + len > bytes.len) return false;
        _ = std.unicode.utf8Decode(bytes[i..][0..len]) catch return false;
        i += len;
    }
    return true;
}

/// Waku `percent_decode_file_path`. Invalid UTF-8 keeps `path`.
pub fn percentDecodeFilePath(path: []const u8, dest: []u8) []const u8 {
    if (dest.len < path.len) return path;
    var out: usize = 0;
    var index: usize = 0;
    while (index < path.len) {
        if (path[index] == '%' and index + 2 < path.len) {
            if (hexValue(path[index + 1])) |high| {
                if (hexValue(path[index + 2])) |low| {
                    dest[out] = (high << 4) | low;
                    out += 1;
                    index += 3;
                    continue;
                }
            }
        }
        dest[out] = path[index];
        out += 1;
        index += 1;
    }
    const decoded = dest[0..out];
    if (validUtf8(decoded)) return decoded;
    @memcpy(dest[0..path.len], path);
    return dest[0..path.len];
}

fn isFilesystemAbsolute(path: []const u8) bool {
    if (path.len == 0) return false;
    if (path[0] == '/' or path[0] == '\\') return true;
    return path.len >= 2 and std.ascii.isAlphabetic(path[0]) and path[1] == ':';
}

fn schemeIsNonFile(target: []const u8) bool {
    if (std.ascii.startsWithIgnoreCase(target, "file:")) return false;
    if (std.mem.indexOf(u8, target, "://") != null) return true;
    const colon = std.mem.indexOfScalar(u8, target, ':') orelse return false;
    if (colon == 1 and std.ascii.isAlphabetic(target[0])) return false;
    const scheme = target[0..colon];
    if (scheme.len == 0) return false;
    for (scheme) |c| {
        if (!std.ascii.isAlphabetic(c)) return false;
    }
    return true;
}

/// Anchors-only, `mailto:`, and other non-file schemes.
pub fn isNonFileLinkTarget(raw: []const u8) bool {
    const trimmed = std.mem.trim(u8, raw, " \t\r\n");
    if (trimmed.len == 0) return true;
    if (trimmed[0] == '#') return true;
    if (std.ascii.startsWithIgnoreCase(trimmed, "mailto:")) return true;
    return schemeIsNonFile(trimmed);
}

/// Waku `markdown_file_link_path`: absolute `/…` or `file:` only.
pub fn markdownFileLinkPath(target: []const u8, dest: []u8) ?[]const u8 {
    const stripped = stripFileLocation(std.mem.trim(u8, target, " \t\r\n"));
    const extracted = extractMarkdownFilePath(stripped) orelse return null;
    const decoded = percentDecodeFilePath(extracted, dest);
    if (!isFilesystemAbsolute(decoded)) return null;
    return decoded;
}

fn extractMarkdownFilePath(target: []const u8) ?[]const u8 {
    if (target.len > 0 and target[0] == '/') return target;
    if (std.mem.startsWith(u8, target, "file://")) {
        const rest = target["file://".len..];
        if (rest.len > 0 and rest[0] == '/') return rest;
        if (std.mem.startsWith(u8, rest, "localhost")) {
            const after = rest["localhost".len..];
            if (after.len > 0 and after[0] == '/') return after;
        }
        return null;
    }
    if (std.mem.startsWith(u8, target, "file:")) {
        const rest = target["file:".len..];
        if (rest.len > 0 and rest[0] == '/') return rest;
    }
    return null;
}

/// Lexically collapse `.` / `..`. No disk probe. `/` separators.
pub fn lexicallyNormalize(path: []const u8, dest: []u8) ?[]const u8 {
    if (path.len == 0 or dest.len == 0) return null;

    var prefix_len: usize = 0;
    var rest = path;
    if (path.len >= 2 and std.ascii.isAlphabetic(path[0]) and path[1] == ':') {
        if (dest.len < 2) return null;
        dest[0] = path[0];
        dest[1] = ':';
        prefix_len = 2;
        rest = path[2..];
    }

    const rooted = rest.len > 0 and (rest[0] == '/' or rest[0] == '\\');
    var out_len = prefix_len;
    if (rooted) {
        if (out_len >= dest.len) return null;
        dest[out_len] = '/';
        out_len += 1;
        rest = rest[1..];
    }
    const min_len = out_len;

    var iter: usize = 0;
    while (iter <= rest.len) {
        const slice = rest[iter..];
        const sep = std.mem.indexOfAny(u8, slice, "/\\");
        const part = if (sep) |s| slice[0..s] else slice;
        const last = sep == null;
        if (part.len == 0) {
            if (last) break;
            iter += 1;
            continue;
        }
        if (std.mem.eql(u8, part, ".")) {
            if (last) break;
            iter += part.len + 1;
            continue;
        }
        if (std.mem.eql(u8, part, "..")) {
            if (out_len > min_len) {
                var n = out_len;
                while (n > min_len) {
                    n -= 1;
                    if (dest[n] == '/') {
                        out_len = n;
                        break;
                    }
                } else {
                    out_len = min_len;
                }
            }
            if (last) break;
            iter += part.len + 1;
            continue;
        }
        if (out_len > 0 and dest[out_len - 1] != '/') {
            if (out_len >= dest.len) return null;
            dest[out_len] = '/';
            out_len += 1;
        }
        if (out_len + part.len > dest.len) return null;
        @memcpy(dest[out_len..][0..part.len], part);
        out_len += part.len;
        if (last) break;
        iter += part.len + 1;
    }

    if (out_len == 0) {
        dest[0] = '.';
        return dest[0..1];
    }
    return dest[0..out_len];
}

/// Directory containing `path`, or empty when there is no parent.
pub fn parentDirectory(path: []const u8) []const u8 {
    const trimmed = std.mem.trimEnd(u8, path, "/\\");
    if (trimmed.len == 0) return "";
    if (std.mem.lastIndexOfAny(u8, trimmed, "/\\")) |idx| {
        if (idx == 0) return trimmed[0..1];
        return trimmed[0..idx];
    }
    return "";
}

/// Join `rel` onto the directory of `preview_abs`. Relative only.
pub fn resolvePreviewRelative(preview_abs: []const u8, rel: []const u8, dest: []u8) ?[]const u8 {
    if (rel.len == 0 or isFilesystemAbsolute(rel)) return null;
    const dir = parentDirectory(preview_abs);
    if (dir.len == 0) return null;
    const base = std.mem.trimEnd(u8, dir, "/\\");
    if (base.len == 0) return null;
    return std.fmt.bufPrint(dest, "{s}/{s}", .{ base, rel }) catch null;
}

/// Waku `workspace_relative_file_path` (lexical; no canonicalize).
pub fn workspaceRelativeFilePath(workspace: []const u8, target: []const u8, dest: []u8) ?[]const u8 {
    var ws_buf: [max_file_link_path]u8 = undefined;
    var tgt_buf: [max_file_link_path]u8 = undefined;
    const ws_raw = std.mem.trim(u8, workspace, " \t\r\n");
    if (ws_raw.len == 0) return null;
    const ws = lexicallyNormalize(ws_raw, &ws_buf) orelse return null;
    const tgt = lexicallyNormalize(target, &tgt_buf) orelse return null;
    const root = std.mem.trimEnd(u8, ws, "/");
    if (root.len == 0) return null;
    if (!std.mem.startsWith(u8, tgt, root)) return null;
    if (tgt.len == root.len) return null;
    if (tgt[root.len] != '/') return null;
    const rel = tgt[root.len + 1 ..];
    if (rel.len == 0) return null;
    if (rel.len > dest.len) return null;
    @memcpy(dest[0..rel.len], rel);
    return dest[0..rel.len];
}

/// Absolute / `file:` via Waku helper; else preview-relative.
pub fn resolveMarkdownFilePath(
    target: []const u8,
    preview_abs: []const u8,
    dest: []u8,
) ?[]const u8 {
    const stripped = stripFileLocation(std.mem.trim(u8, target, " \t\r\n"));
    if (stripped.len == 0 or isNonFileLinkTarget(stripped)) return null;
    var extracted_buf: [max_file_link_path]u8 = undefined;
    const extracted = markdownFileLinkPath(stripped, &extracted_buf) orelse blk: {
        if (isFilesystemAbsolute(stripped)) {
            break :blk percentDecodeFilePath(stripped, &extracted_buf);
        }
        var join_buf: [max_file_link_path]u8 = undefined;
        const joined = resolvePreviewRelative(preview_abs, stripped, &join_buf) orelse return null;
        break :blk percentDecodeFilePath(joined, &extracted_buf);
    };
    return lexicallyNormalize(extracted, dest);
}

pub fn isUrlArgv(argv: []const []const u8) bool {
    if (argv.len == 2) {
        const bin_ok = std.mem.eql(u8, argv[0], macos_bin) or std.mem.eql(u8, argv[0], linux_bin);
        return bin_ok and isHttpUrl(argv[1]);
    }
    if (argv.len == 5) {
        return std.mem.eql(u8, argv[0], windows_bin) and
            std.mem.eql(u8, argv[1], windows_c_flag) and
            std.mem.eql(u8, argv[2], windows_start) and
            argv[3].len == 0 and
            isHttpUrl(argv[4]);
    }
    return false;
}

/// Trim, reject empty / whitespace-only, keep `http://` / `https://`,
/// else prefix `https://`. `null` when empty or the dest is too small.
pub fn normalizeUrl(raw: []const u8, dest: []u8) ?[]const u8 {
    const trimmed = std.mem.trim(u8, raw, " \t\r\n");
    if (trimmed.len == 0) return null;
    if (isHttpUrl(trimmed)) {
        if (trimmed.len > dest.len) return null;
        @memcpy(dest[0..trimmed.len], trimmed);
        return dest[0..trimmed.len];
    }
    return std.fmt.bufPrint(dest, "{s}{s}", .{ https_prefix, trimmed }) catch null;
}

pub fn startOpenUrl(model: *Model, fx: *Effects) void {
    switch (startOpenUrlText(model, fx, model.browser_url())) {
        .spawned, .live => {},
        .empty, .overflow => model.setWindowStatus(empty_url_status),
        .missing_bin => model.setWindowStatus(hostMissingStatus()),
    }
}

pub const OpenUrlOutcome = enum { spawned, empty, live, missing_bin, overflow };

/// One-shot OS browser spawn from an arbitrary URL string. Copies into
/// `open_url_storage` (Native on-link payloads are drain-scratch).
pub fn startOpenUrlText(model: *Model, fx: *Effects, raw: []const u8) OpenUrlOutcome {
    if (model.open_url_live) return .live;
    const written = normalizeUrl(raw, &model.open_url_storage) orelse {
        const trimmed = std.mem.trim(u8, raw, " \t\r\n");
        return if (trimmed.len == 0) .empty else .overflow;
    };
    if (hostBin() == null) {
        model.open_url_len = 0;
        return .missing_bin;
    }
    model.open_url_len = written.len;
    model.open_url_live = true;
    model.clearWindowStatus();
    var argv_buf: [argv_len][]const u8 = undefined;
    fx.spawn(.{
        .key = open_url_key,
        .argv = argvFor(model.open_url_storage[0..model.open_url_len], &argv_buf),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
    return .spawned;
}

fn isMissingUrlExit(exit: native_sdk.EffectExit) bool {
    if (exit.reason != .exited) return true;
    return exit.code == 127 or exit.code == missing_exit;
}

pub fn handleOpenUrlExit(model: *Model, exit: native_sdk.EffectExit) void {
    if (isMissingUrlExit(exit) and !model.has_window_status()) {
        model.setWindowStatus(hostMissingStatus());
    }
    model.open_url_live = false;
}

test "macos argv is open on the URL" {
    var buf: [argv_len][]const u8 = undefined;
    const argv = argvForTool(.open, "https://example.com", &buf);
    try std.testing.expectEqual(@as(usize, 2), argv.len);
    try std.testing.expectEqualStrings(macos_bin, argv[0]);
    try std.testing.expectEqualStrings("https://example.com", argv[1]);
    try std.testing.expect(isUrlArgv(argv));
}

test "linux argv is xdg-open on the URL" {
    var buf: [argv_len][]const u8 = undefined;
    const argv = argvForTool(.xdg_open, "https://example.com", &buf);
    try std.testing.expectEqual(@as(usize, 2), argv.len);
    try std.testing.expectEqualStrings(linux_bin, argv[0]);
    try std.testing.expectEqualStrings("https://example.com", argv[1]);
    try std.testing.expect(isUrlArgv(argv));
}

test "windows argv is cmd.exe /c start empty-title URL" {
    var buf: [argv_len][]const u8 = undefined;
    const argv = argvForTool(.cmd_start, "https://example.com", &buf);
    try std.testing.expectEqual(@as(usize, 5), argv.len);
    try std.testing.expectEqualStrings(windows_bin, argv[0]);
    try std.testing.expectEqualStrings(windows_c_flag, argv[1]);
    try std.testing.expectEqualStrings(windows_start, argv[2]);
    try std.testing.expectEqualStrings(windows_empty_title, argv[3]);
    try std.testing.expectEqual(@as(usize, 0), argv[3].len);
    try std.testing.expectEqualStrings("https://example.com", argv[4]);
    try std.testing.expect(isUrlArgv(argv));
}

test "host tool is the platform URL opener" {
    switch (builtin.os.tag) {
        .macos => {
            try std.testing.expectEqual(Tool.open, hostTool().?);
            try std.testing.expectEqualStrings(macos_bin, hostBin().?);
        },
        .linux => {
            try std.testing.expectEqual(Tool.xdg_open, hostTool().?);
            try std.testing.expectEqualStrings(linux_bin, hostBin().?);
        },
        .windows => {
            try std.testing.expectEqual(Tool.cmd_start, hostTool().?);
            try std.testing.expectEqualStrings(windows_bin, hostBin().?);
        },
        else => {
            try std.testing.expect(hostTool() == null);
            try std.testing.expect(hostBin() == null);
        },
    }
}

test "normalizeUrl rejects empty, keeps http(s), prefixes bare hosts" {
    var dest: [max_spawn_url]u8 = undefined;
    try std.testing.expect(normalizeUrl("", &dest) == null);
    try std.testing.expect(normalizeUrl("   \t\n", &dest) == null);
    try std.testing.expectEqualStrings("https://example.com", normalizeUrl("example.com", &dest).?);
    try std.testing.expectEqualStrings("https://example.com", normalizeUrl("  example.com  ", &dest).?);
    try std.testing.expectEqualStrings("https://example.com/path?q=1", normalizeUrl("example.com/path?q=1", &dest).?);
    try std.testing.expectEqualStrings("http://localhost:3000", normalizeUrl("http://localhost:3000", &dest).?);
    try std.testing.expectEqualStrings("https://example.com", normalizeUrl("https://example.com", &dest).?);
    try std.testing.expectEqualStrings("HTTP://Example.COM", normalizeUrl("HTTP://Example.COM", &dest).?);
    try std.testing.expectEqualStrings("HTTPS://Example.COM/a", normalizeUrl("HTTPS://Example.COM/a", &dest).?);
}

test "isRelativeOrFileUrl rejects files and relative paths; keeps http(s) and hosts" {
    try std.testing.expect(isRelativeOrFileUrl(""));
    try std.testing.expect(isRelativeOrFileUrl("   "));
    try std.testing.expect(isRelativeOrFileUrl("./guide.md"));
    try std.testing.expect(isRelativeOrFileUrl("../LICENSE"));
    try std.testing.expect(isRelativeOrFileUrl("/tmp/notes.md"));
    try std.testing.expect(isRelativeOrFileUrl("#anchor"));
    try std.testing.expect(isRelativeOrFileUrl("file:///tmp/a.md"));
    try std.testing.expect(isRelativeOrFileUrl("mailto:hi@example.com"));
    try std.testing.expect(isRelativeOrFileUrl("docs/guide.md"));
    try std.testing.expect(isRelativeOrFileUrl("README.md"));
    try std.testing.expect(!isRelativeOrFileUrl("https://example.com"));
    try std.testing.expect(!isRelativeOrFileUrl("http://localhost:3000"));
    try std.testing.expect(!isRelativeOrFileUrl("example.com"));
    try std.testing.expect(!isRelativeOrFileUrl("github.com/owner/repo"));
}

test "url argv is not reveal terminal or folder-picker argv" {
    var buf: [argv_len][]const u8 = undefined;
    var reveal_buf: [2][]const u8 = undefined;
    var term_scratch: open_terminal.ArgvScratch = .{};
    const url_argv = argvForTool(.open, "https://example.com", &buf);
    try std.testing.expect(!reveal_folder.isRevealArgv(url_argv));
    try std.testing.expect(!open_terminal.isTerminalArgv(url_argv));
    try std.testing.expect(!pick_folder.isPickerArgv(url_argv));
    const windows_argv = argvForTool(.cmd_start, "https://example.com", &buf);
    try std.testing.expect(!reveal_folder.isRevealArgv(windows_argv));
    try std.testing.expect(!open_terminal.isTerminalArgv(windows_argv));
    try std.testing.expect(!pick_folder.isPickerArgv(windows_argv));
    try std.testing.expect(!isUrlArgv(reveal_folder.argvFor("/tmp/proj", &reveal_buf)));
    try std.testing.expect(!isUrlArgv(reveal_folder.argvForTool(.explorer, "/tmp/proj", &reveal_buf)));
    try std.testing.expect(!isUrlArgv(open_terminal.argvForTool(.open_terminal, "/tmp/proj", &term_scratch)));
    try std.testing.expect(!isUrlArgv(open_terminal.argvForTool(.x_terminal_emulator, "/tmp/proj", &term_scratch)));
    try std.testing.expect(!isUrlArgv(open_terminal.argvForTool(.windows_terminal, "/tmp/proj", &term_scratch)));
    try std.testing.expect(!isUrlArgv(open_terminal.argvForTool(.cmd_start, "/tmp/proj", &term_scratch)));
    try std.testing.expect(open_terminal.isTerminalArgv(open_terminal.argvForTool(.windows_terminal, "/tmp/proj", &term_scratch)));
    try std.testing.expect(open_terminal.isTerminalArgv(open_terminal.argvForTool(.cmd_start, "/tmp/proj", &term_scratch)));
    try std.testing.expect(!isUrlArgv(pick_folder.argvFor(.osascript)));
    try std.testing.expect(!isUrlArgv(pick_folder.argvFor(.zenity)));
    try std.testing.expect(!isUrlArgv(pick_folder.argvFor(.kdialog)));
    try std.testing.expect(!isUrlArgv(pick_folder.argvFor(.powershell)));
}

test "open_url_key is 25 and distinct from editor/terminal/reveal neighbors" {
    const open_editor = @import("open_editor.zig");
    const attach = @import("attach.zig");
    const maximize_window = @import("maximize_window.zig");
    const copy = @import("copy.zig");
    try std.testing.expectEqual(@as(u64, 25), open_url_key);
    try std.testing.expect(open_url_key != open_editor.open_editor_key);
    try std.testing.expect(open_url_key != open_terminal.open_terminal_key);
    try std.testing.expect(open_url_key != reveal_folder.reveal_folder_key);
    try std.testing.expect(open_url_key != pick_folder.pick_folder_key);
    try std.testing.expect(open_url_key != attach.pick_image_key);
    try std.testing.expect(open_url_key != maximize_window.maximize_window_key);
    try std.testing.expect(open_url_key != copy.copy_turn_key);
    try std.testing.expect(open_url_key != 3);
    try std.testing.expect(open_url_key < 64);
}

test "stripFileLocation drops editor fragments and keeps ordinary hashes" {
    try std.testing.expectEqualStrings("/tmp/a.md", stripFileLocation("/tmp/a.md#L12"));
    try std.testing.expectEqualStrings("/tmp/a.md", stripFileLocation("/tmp/a.md#L12C4"));
    try std.testing.expectEqualStrings("/tmp/a.md", stripFileLocation("/tmp/a.md:12"));
    try std.testing.expectEqualStrings("/tmp/a.md", stripFileLocation("/tmp/a.md:12:4"));
    try std.testing.expectEqualStrings("./other.md", stripFileLocation("./other.md:12"));
    try std.testing.expectEqualStrings("/tmp/a.md#section", stripFileLocation("/tmp/a.md#section"));
    try std.testing.expectEqualStrings("/tmp/a.md", stripFileLocation("/tmp/a.md"));
}

test "percentDecodeFilePath decodes hex and keeps invalid percent" {
    var dest: [max_file_link_path]u8 = undefined;
    try std.testing.expectEqualStrings("/tmp/foo bar.md", percentDecodeFilePath("/tmp/foo%20bar.md", &dest));
    try std.testing.expectEqualStrings("/tmp/café", percentDecodeFilePath("/tmp/caf%C3%A9", &dest));
    try std.testing.expectEqualStrings("/tmp/%zz", percentDecodeFilePath("/tmp/%zz", &dest));
}

test "markdownFileLinkPath accepts absolute and file; rejects relative" {
    var dest: [max_file_link_path]u8 = undefined;
    try std.testing.expectEqualStrings("/tmp/a.md", markdownFileLinkPath("/tmp/a.md#L12", &dest).?);
    try std.testing.expectEqualStrings("/tmp/a.md", markdownFileLinkPath("file:///tmp/a.md", &dest).?);
    try std.testing.expectEqualStrings("/tmp/a.md", markdownFileLinkPath("file://localhost/tmp/a.md", &dest).?);
    try std.testing.expectEqualStrings("/tmp/a.md", markdownFileLinkPath("file:/tmp/a.md", &dest).?);
    try std.testing.expectEqualStrings("/tmp/foo bar.md", markdownFileLinkPath("file:///tmp/foo%20bar.md", &dest).?);
    try std.testing.expect(markdownFileLinkPath("./other.md", &dest) == null);
    try std.testing.expect(markdownFileLinkPath("docs/x.md", &dest) == null);
}

test "lexicallyNormalize collapses dots; workspaceRelative is prefix-safe" {
    var dest: [max_file_link_path]u8 = undefined;
    try std.testing.expectEqualStrings("/tmp/proj/README.md", lexicallyNormalize("/tmp/proj/./docs/../README.md", &dest).?);
    try std.testing.expectEqualStrings("/etc/passwd", lexicallyNormalize("/tmp/proj/../../etc/passwd", &dest).?);
    try std.testing.expectEqualStrings("foo/baz", lexicallyNormalize("foo/bar/../baz", &dest).?);
    try std.testing.expectEqualStrings("/tmp/proj/docs/other.md", lexicallyNormalize("/tmp/proj/docs/./other.md", &dest).?);

    var rel: [max_file_link_path]u8 = undefined;
    try std.testing.expectEqualStrings("docs/other.md", workspaceRelativeFilePath("/tmp/proj", "/tmp/proj/docs/other.md", &rel).?);
    try std.testing.expectEqualStrings("NOTES.md", workspaceRelativeFilePath("/tmp/proj/", "/tmp/proj/NOTES.md", &rel).?);
    try std.testing.expect(workspaceRelativeFilePath("/tmp/proj", "/tmp/proj", &rel) == null);
    try std.testing.expect(workspaceRelativeFilePath("/tmp/proj", "/tmp/proj-other/x.md", &rel) == null);
    try std.testing.expect(workspaceRelativeFilePath("", "/tmp/proj/x.md", &rel) == null);
    try std.testing.expect(workspaceRelativeFilePath("/tmp/proj", "/etc/passwd", &rel) == null);
}

test "resolvePreviewRelative joins the preview directory; non-file targets stay out" {
    var dest: [max_file_link_path]u8 = undefined;
    try std.testing.expectEqualStrings(
        "/tmp/proj/docs/./other.md",
        resolvePreviewRelative("/tmp/proj/docs/README.md", "./other.md", &dest).?,
    );
    try std.testing.expectEqualStrings(
        "/tmp/proj/docs/../NOTES.md",
        resolvePreviewRelative("/tmp/proj/docs/README.md", "../NOTES.md", &dest).?,
    );
    try std.testing.expect(resolvePreviewRelative("/tmp/proj/docs/README.md", "/tmp/x.md", &dest) == null);
    try std.testing.expect(isNonFileLinkTarget("#section"));
    try std.testing.expect(isNonFileLinkTarget("mailto:hi@example.com"));
    try std.testing.expect(isNonFileLinkTarget("javascript:alert(1)"));
    try std.testing.expect(!isNonFileLinkTarget("./other.md"));
    try std.testing.expect(!isNonFileLinkTarget("file:///tmp/a.md"));
    try std.testing.expect(!isNonFileLinkTarget("/tmp/a.md"));

    try std.testing.expectEqualStrings(
        "/tmp/proj/docs/other.md",
        resolveMarkdownFilePath("./other.md", "/tmp/proj/docs/README.md", &dest).?,
    );
    try std.testing.expectEqualStrings(
        "/tmp/proj/NOTES.md",
        resolveMarkdownFilePath("../NOTES.md", "/tmp/proj/docs/README.md", &dest).?,
    );
    try std.testing.expectEqualStrings(
        "/tmp/proj/docs/other.md",
        resolveMarkdownFilePath("file:///tmp/proj/docs/other.md#L12", "/tmp/proj/docs/README.md", &dest).?,
    );
    try std.testing.expect(resolveMarkdownFilePath("#section", "/tmp/proj/docs/README.md", &dest) == null);
    try std.testing.expect(resolveMarkdownFilePath("mailto:hi@example.com", "/tmp/proj/docs/README.md", &dest) == null);
}
