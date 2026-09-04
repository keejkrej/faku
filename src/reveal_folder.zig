//! One-shot OS file-manager reveal sidecar.
//!
//! Native documents `Cmd.revealPath` / `runtime.revealPath` (fire-and-forget,
//! fail closed). This SDK revision has no typed `fx.revealPath` on Effects.
//! `fx.hostSend("native-sdk.os.revealPath", path)` exists but the fake
//! executor drops native host-sends, so tests cannot assert it. Reveal
//! folder therefore `fx.spawn`s a documented OS file-manager open:
//!
//!   macOS:  `open` on the directory (Finder)
//!   Linux:  `xdg-open` on the directory (Files / Nautilus / xdg)
//!   Windows: `explorer.exe PATH` (Explorer on the directory; PATH-resolved
//!            like sibling `wt.exe` / `cmd.exe`; each token its own argv slot)
//!
//! This is not Waku's Open-in app picker and not an invented Native
//! effect. Spawn stdin is unused (write-once then close).

const std = @import("std");
const builtin = @import("builtin");
const native_sdk = @import("native_sdk");
const main = @import("main.zig");

const Model = main.Model;
const Effects = main.Effects;

/// Distinct from pick_folder (29), maximize (30), pick_image (31),
/// copy_turn (32), attach_preview 33–63, fx_probe (3), fx_spawn 64+,
/// git_branch 200+. 28 sits in that gap and is unused by those tables.
pub const reveal_folder_key: u64 = 28;

pub const missing_exit: u8 = 2;

pub const linux_missing_status = "No OS folder reveal (install xdg-open).";
pub const macos_missing_status = "No OS folder reveal (open missing).";
pub const windows_missing_status = "No OS folder reveal (explorer.exe missing).";
pub const no_project_status = "No project folder to reveal.";

pub const macos_bin = "open";
pub const linux_bin = "xdg-open";
pub const windows_bin = "explorer.exe";

pub const Tool = enum { open, xdg_open, explorer };

const argv_len: usize = 2;

pub fn hostTool() ?Tool {
    return switch (builtin.os.tag) {
        .macos => .open,
        .linux => .xdg_open,
        .windows => .explorer,
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
        .explorer => windows_bin,
    };
}

pub fn argvForTool(tool: Tool, path: []const u8, buf: *[argv_len][]const u8) []const []const u8 {
    buf.* = .{ binFor(tool), path };
    return buf;
}

pub fn argvFor(path: []const u8, buf: *[argv_len][]const u8) []const []const u8 {
    return argvForTool(hostTool() orelse .xdg_open, path, buf);
}

pub fn isRevealArgv(argv: []const []const u8) bool {
    if (argv.len != argv_len) return false;
    const bin_ok = std.mem.eql(u8, argv[0], macos_bin) or
        std.mem.eql(u8, argv[0], linux_bin) or
        std.mem.eql(u8, argv[0], windows_bin);
    if (!bin_ok) return false;
    // URL opens are `open_url` (`http://` / `https://`), not folder reveal.
    // Windows URL opens are `cmd.exe /c start "" <url>` (len 5), not explorer.
    return !looksLikeHttpUrl(argv[1]);
}

fn looksLikeHttpUrl(s: []const u8) bool {
    if (s.len >= 8 and std.ascii.eqlIgnoreCase(s[0..8], "https://")) return true;
    if (s.len >= 7 and std.ascii.eqlIgnoreCase(s[0..7], "http://")) return true;
    return false;
}

/// Existing selected-session directory. Relative paths count so the
/// control can show; `resolveRevealPath` still requires absolute.
pub fn canReveal(model: *const Model) bool {
    return existingProjectDir(model) != null;
}

/// Absolute existing directory, or null (empty / relative / missing /
/// not-a-dir / no store_io).
pub fn resolveRevealPath(model: *const Model) ?[]const u8 {
    const path = existingProjectDir(model) orelse return null;
    if (!std.fs.path.isAbsolute(path)) return null;
    return path;
}

fn existingProjectDir(model: *const Model) ?[]const u8 {
    const path = std.mem.trim(u8, model.selectedProjectPath(), " \t\r\n");
    if (path.len == 0) return null;
    const io = model.store_io orelse return null;
    if (!main.directoryExists(io, path)) return null;
    return path;
}

pub fn startRevealFolder(model: *Model, fx: *Effects) void {
    if (model.reveal_folder_live) return;
    const path = resolveRevealPath(model) orelse {
        model.setWindowStatus(no_project_status);
        return;
    };
    if (hostBin() == null) {
        model.setWindowStatus(hostMissingStatus());
        return;
    }
    model.reveal_folder_live = true;
    model.clearWindowStatus();
    var argv_buf: [argv_len][]const u8 = undefined;
    fx.spawn(.{
        .key = reveal_folder_key,
        .argv = argvFor(path, &argv_buf),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
}

fn isMissingRevealExit(exit: native_sdk.EffectExit) bool {
    if (exit.reason != .exited) return true;
    return exit.code == 127 or exit.code == missing_exit;
}

pub fn handleRevealFolderExit(model: *Model, exit: native_sdk.EffectExit) void {
    if (isMissingRevealExit(exit) and !model.has_window_status()) {
        model.setWindowStatus(hostMissingStatus());
    }
    model.reveal_folder_live = false;
}

test "macos argv is open on the directory" {
    var buf: [argv_len][]const u8 = undefined;
    const argv = argvForTool(.open, "/tmp/proj", &buf);
    try std.testing.expectEqual(@as(usize, 2), argv.len);
    try std.testing.expectEqualStrings(macos_bin, argv[0]);
    try std.testing.expectEqualStrings("/tmp/proj", argv[1]);
    try std.testing.expect(isRevealArgv(argv));
}

test "linux argv is xdg-open on the directory" {
    var buf: [argv_len][]const u8 = undefined;
    const argv = argvForTool(.xdg_open, "/tmp/proj", &buf);
    try std.testing.expectEqual(@as(usize, 2), argv.len);
    try std.testing.expectEqualStrings(linux_bin, argv[0]);
    try std.testing.expectEqualStrings("/tmp/proj", argv[1]);
    try std.testing.expect(isRevealArgv(argv));
}

test "windows argv is explorer.exe on the directory" {
    var buf: [argv_len][]const u8 = undefined;
    const argv = argvForTool(.explorer, "/tmp/proj", &buf);
    try std.testing.expectEqual(@as(usize, 2), argv.len);
    try std.testing.expectEqualStrings(windows_bin, argv[0]);
    try std.testing.expectEqualStrings("/tmp/proj", argv[1]);
    try std.testing.expect(isRevealArgv(argv));
}

test "host tool is the platform file manager" {
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
            try std.testing.expectEqual(Tool.explorer, hostTool().?);
            try std.testing.expectEqualStrings(windows_bin, hostBin().?);
        },
        else => {
            try std.testing.expect(hostTool() == null);
            try std.testing.expect(hostBin() == null);
        },
    }
}

test "reveal argv is not url terminal editor or folder-picker argv" {
    const pick_folder = @import("pick_folder.zig");
    const open_terminal = @import("open_terminal.zig");
    const open_url = @import("open_url.zig");
    const open_editor = @import("open_editor.zig");
    var buf: [argv_len][]const u8 = undefined;
    var url_buf: [5][]const u8 = undefined;
    var term_scratch: open_terminal.ArgvScratch = .{};
    var editor_scratch: open_editor.ArgvScratch = .{};

    const explorer = argvForTool(.explorer, "/tmp/proj", &buf);
    try std.testing.expect(isRevealArgv(explorer));
    try std.testing.expect(!pick_folder.isPickerArgv(explorer));
    try std.testing.expect(!open_terminal.isTerminalArgv(explorer));
    try std.testing.expect(!open_url.isUrlArgv(explorer));
    try std.testing.expect(!open_editor.isEditorArgv(explorer));

    try std.testing.expect(!pick_folder.isPickerArgv(argvFor("/tmp/proj", &buf)));
    try std.testing.expect(!isRevealArgv(pick_folder.argvFor(.osascript)));
    try std.testing.expect(!isRevealArgv(pick_folder.argvFor(.zenity)));
    try std.testing.expect(!isRevealArgv(pick_folder.argvFor(.kdialog)));
    try std.testing.expect(!isRevealArgv(pick_folder.argvFor(.powershell)));
    try std.testing.expect(!isRevealArgv(open_terminal.argvForTool(.open_terminal, "/tmp/proj", &term_scratch)));
    try std.testing.expect(!isRevealArgv(open_terminal.argvForTool(.windows_terminal, "/tmp/proj", &term_scratch)));
    try std.testing.expect(!isRevealArgv(open_terminal.argvForTool(.cmd_start, "/tmp/proj", &term_scratch)));
    try std.testing.expect(!open_terminal.isTerminalArgv(argvFor("/tmp/proj", &buf)));
    try std.testing.expect(!open_terminal.isTerminalArgv(explorer));
    try std.testing.expect(!isRevealArgv(open_url.argvForTool(.open, "https://example.com", &url_buf)));
    try std.testing.expect(!isRevealArgv(open_url.argvForTool(.xdg_open, "https://example.com", &url_buf)));
    try std.testing.expect(!isRevealArgv(open_url.argvForTool(.cmd_start, "https://example.com", &url_buf)));
    try std.testing.expect(!isRevealArgv(open_editor.argvForTool(.cursor, "/tmp/proj", &editor_scratch)));
    try std.testing.expect(!isRevealArgv(open_editor.argvForTool(.code, "/tmp/proj", &editor_scratch)));
    try std.testing.expect(!isRevealArgv(open_editor.argvForTool(.open_cursor, "/tmp/proj", &editor_scratch)));
    try std.testing.expect(!isRevealArgv(open_editor.argvForTool(.open_vscode, "/tmp/proj", &editor_scratch)));
    try std.testing.expect(!isRevealArgv(open_editor.argvForTool(.windows_cursor, "/tmp/proj", &editor_scratch)));
    try std.testing.expect(!isRevealArgv(open_editor.argvForTool(.windows_code, "/tmp/proj", &editor_scratch)));
}

test "reveal_folder_key is distinct from pick_folder and neighbors" {
    const pick_folder = @import("pick_folder.zig");
    const attach = @import("attach.zig");
    const maximize_window = @import("maximize_window.zig");
    const copy = @import("copy.zig");
    try std.testing.expect(reveal_folder_key != pick_folder.pick_folder_key);
    try std.testing.expect(reveal_folder_key != attach.pick_image_key);
    try std.testing.expect(reveal_folder_key != maximize_window.maximize_window_key);
    try std.testing.expect(reveal_folder_key != copy.copy_turn_key);
    try std.testing.expect(reveal_folder_key != 3);
    try std.testing.expect(reveal_folder_key < 64);
}
