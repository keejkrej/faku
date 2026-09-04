//! One-shot OS browser-open sidecar.
//!
//! Native has no documented webview effect. The right-panel Browser
//! tab therefore `fx.spawn`s a documented host URL open:
//!
//!   macOS:  `open` + URL
//!   Linux:  `xdg-open` + URL
//!   Windows: skipped (honest status; no Windows spawn path this cut)
//!
//! This is not Waku's embedded `RightPanelSurface::Browser` / BrowserView.
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
pub const windows_missing_status = "Open in browser is not available on Windows.";
pub const empty_url_status = "Enter a URL to open.";

pub const macos_bin = "open";
pub const linux_bin = "xdg-open";
pub const https_prefix = "https://";

/// Browser tab draft. Persisted raw on sessions.json extras
/// (`browser_url`); cap is this max. Missing / empty / overflow → empty.
pub const max_url: usize = 2048;
/// Draft plus `https://` when a bare host is prefixed.
pub const max_spawn_url: usize = max_url + https_prefix.len;

pub const Tool = enum { open, xdg_open };

const argv_len: usize = 2;

pub fn hostTool() ?Tool {
    return switch (builtin.os.tag) {
        .macos => .open,
        .linux => .xdg_open,
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
    };
}

pub fn argvForTool(tool: Tool, url: []const u8, buf: *[argv_len][]const u8) []const []const u8 {
    buf.* = .{ binFor(tool), url };
    return buf;
}

pub fn argvFor(url: []const u8, buf: *[argv_len][]const u8) []const []const u8 {
    return argvForTool(hostTool() orelse .xdg_open, url, buf);
}

pub fn isHttpUrl(text: []const u8) bool {
    if (text.len >= 8 and std.ascii.eqlIgnoreCase(text[0..8], "https://")) return true;
    if (text.len >= 7 and std.ascii.eqlIgnoreCase(text[0..7], "http://")) return true;
    return false;
}

pub fn isUrlArgv(argv: []const []const u8) bool {
    if (argv.len != argv_len) return false;
    const bin_ok = std.mem.eql(u8, argv[0], macos_bin) or std.mem.eql(u8, argv[0], linux_bin);
    return bin_ok and isHttpUrl(argv[1]);
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
    if (model.open_url_live) return;
    const written = normalizeUrl(model.browser_url(), &model.open_url_storage) orelse {
        model.setWindowStatus(empty_url_status);
        return;
    };
    model.open_url_len = written.len;
    if (hostBin() == null) {
        model.setWindowStatus(hostMissingStatus());
        return;
    }
    model.open_url_live = true;
    model.clearWindowStatus();
    var argv_buf: [argv_len][]const u8 = undefined;
    fx.spawn(.{
        .key = open_url_key,
        .argv = argvFor(model.open_url_storage[0..model.open_url_len], &argv_buf),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
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

test "host tool is the platform URL opener; Windows is skipped" {
    switch (builtin.os.tag) {
        .macos => {
            try std.testing.expectEqual(Tool.open, hostTool().?);
            try std.testing.expectEqualStrings(macos_bin, hostBin().?);
        },
        .linux => {
            try std.testing.expectEqual(Tool.xdg_open, hostTool().?);
            try std.testing.expectEqualStrings(linux_bin, hostBin().?);
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

test "url argv is not reveal terminal or folder-picker argv" {
    var buf: [argv_len][]const u8 = undefined;
    var reveal_buf: [2][]const u8 = undefined;
    var term_scratch: open_terminal.ArgvScratch = .{};
    const url_argv = argvForTool(.open, "https://example.com", &buf);
    try std.testing.expect(!reveal_folder.isRevealArgv(url_argv));
    try std.testing.expect(!open_terminal.isTerminalArgv(url_argv));
    try std.testing.expect(!pick_folder.isPickerArgv(url_argv));
    try std.testing.expect(!isUrlArgv(reveal_folder.argvFor("/tmp/proj", &reveal_buf)));
    try std.testing.expect(!isUrlArgv(open_terminal.argvForTool(.open_terminal, "/tmp/proj", &term_scratch)));
    try std.testing.expect(!isUrlArgv(open_terminal.argvForTool(.x_terminal_emulator, "/tmp/proj", &term_scratch)));
    try std.testing.expect(!isUrlArgv(pick_folder.argvFor(.osascript)));
    try std.testing.expect(!isUrlArgv(pick_folder.argvFor(.zenity)));
    try std.testing.expect(!isUrlArgv(pick_folder.argvFor(.kdialog)));
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
