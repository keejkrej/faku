//! One-shot OS directory-picker sidecar.
//!
//! Native has no `fx.pickFile`. `Runtime.showOpenDialog` is a host-bridge
//! / WebView API, not an fx effect the TEA loop can call. Pick folder
//! therefore `fx.spawn`s a documented OS folder dialog that prints one
//! absolute directory path to stdout and exits. Spawn stdin is unused
//! (write-once then close). This is not Waku's daemon project catalog
//! and not an invented Native file-open effect.
//!
//!   macOS:  osascript `choose folder`, POSIX path
//!   Linux:  zenity --file-selection --directory, else kdialog
//!           --getexistingdirectory
//!   Windows: skipped (app.zon is macos/linux; no Windows spawn path)

const std = @import("std");
const builtin = @import("builtin");
const native_sdk = @import("native_sdk");
const main = @import("main.zig");
const persist = @import("persist.zig");

const Model = main.Model;
const Effects = main.Effects;

/// Distinct from pick_image (31), maximize (30), copy_turn (32),
/// attach_preview 33–63, fx_probe (3), fx_spawn 64+, git_branch 200+.
/// 29 sits in that gap and is unused by those tables.
pub const pick_folder_key: u64 = 29;

pub const cancel_exit: u8 = 1;
pub const missing_exit: u8 = 2;
pub const error_prefix = "error:";

pub const linux_missing_status = "No OS folder picker (install zenity or kdialog). Type a path.";
pub const macos_missing_status = "No OS folder picker (osascript missing). Type a path.";
pub const windows_missing_status = "Folder picker is not available on Windows. Type a path.";

pub const osascript_bin = "osascript";
pub const osascript_script = "POSIX path of (choose folder with prompt \"Choose a project\")";
pub const zenity_bin = "zenity";
pub const kdialog_bin = "kdialog";

pub const Picker = enum { osascript, zenity, kdialog };
pub const Stage = enum { first, fallback };

const osascript_argv = [_][]const u8{ osascript_bin, "-e", osascript_script };
const zenity_argv = [_][]const u8{ zenity_bin, "--file-selection", "--directory" };
const kdialog_argv = [_][]const u8{ kdialog_bin, "--getexistingdirectory", "." };

pub fn argvFor(picker: Picker) []const []const u8 {
    return switch (picker) {
        .osascript => &osascript_argv,
        .zenity => &zenity_argv,
        .kdialog => &kdialog_argv,
    };
}

pub fn hostPicker(stage: Stage) ?Picker {
    return switch (builtin.os.tag) {
        .macos => if (stage == .first) .osascript else null,
        .linux => switch (stage) {
            .first => .zenity,
            .fallback => .kdialog,
        },
        else => null,
    };
}

pub fn hostArgv(stage: Stage) ?[]const []const u8 {
    return argvFor(hostPicker(stage) orelse return null);
}

pub fn hostMissingStatus() []const u8 {
    return switch (builtin.os.tag) {
        .macos => macos_missing_status,
        .windows => windows_missing_status,
        else => linux_missing_status,
    };
}

pub fn isPickerArgv(argv: []const []const u8) bool {
    if (argv.len == 0) return false;
    if (std.mem.eql(u8, argv[0], osascript_bin)) {
        return argvHas(argv, "choose folder") and argvHas(argv, "POSIX path");
    }
    if (std.mem.eql(u8, argv[0], zenity_bin)) {
        return argvHas(argv, "--file-selection") and argvHas(argv, "--directory");
    }
    if (std.mem.eql(u8, argv[0], kdialog_bin)) {
        return argvHas(argv, "--getexistingdirectory");
    }
    return false;
}

/// First stdout line, trimmed. Empty / whitespace is cancel.
pub fn firstStdoutPath(raw: []const u8) []const u8 {
    const trimmed = std.mem.trim(u8, raw, " \t\r\n");
    if (trimmed.len == 0) return "";
    const end = std.mem.indexOfAny(u8, trimmed, "\r\n") orelse trimmed.len;
    return std.mem.trim(u8, trimmed[0..end], " \t");
}

pub fn takeErrorMessage(line: []const u8) ?[]const u8 {
    if (!std.mem.startsWith(u8, line, error_prefix)) return null;
    const msg = std.mem.trim(u8, line[error_prefix.len..], " \t\r\n");
    return if (msg.len == 0) null else msg;
}

pub fn startPickFolder(model: *Model, fx: *Effects) void {
    if (model.pick_folder_live) return;
    const argv = hostArgv(.first) orelse {
        model.setWindowStatus(hostMissingStatus());
        model.startProjectEdit();
        return;
    };
    model.pick_folder_live = true;
    model.pick_folder_got_path = false;
    model.pick_folder_tried_fallback = false;
    model.clearWindowStatus();
    fx.spawn(.{
        .key = pick_folder_key,
        .argv = argv,
        .on_line = Effects.lineMsg(.fx_line),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
}

pub fn applyPickFolderLine(model: *Model, fx: *Effects, line: native_sdk.EffectLine) void {
    const raw = firstStdoutPath(line.line);
    if (takeErrorMessage(raw)) |msg| {
        model.setWindowStatus(msg);
        return;
    }
    if (raw.len == 0) return;
    if (model.store_io) |io| {
        if (!main.directoryExists(io, raw)) return;
    }
    model.setSelectedProjectPath(raw);
    model.clearWindowStatus();
    persist.persistComposerProject(model, fx);
    model.pick_folder_got_path = true;
}

fn isMissingPickerExit(exit: native_sdk.EffectExit) bool {
    if (exit.reason != .exited) return true;
    return exit.code == 127 or exit.code == missing_exit;
}

pub fn handlePickFolderExit(model: *Model, fx: *Effects, exit: native_sdk.EffectExit) void {
    if (model.pick_folder_got_path) {
        model.pick_folder_live = false;
        return;
    }
    if (isMissingPickerExit(exit)) {
        if (!model.pick_folder_tried_fallback) {
            if (hostArgv(.fallback)) |argv| {
                model.pick_folder_tried_fallback = true;
                fx.spawn(.{
                    .key = pick_folder_key,
                    .argv = argv,
                    .on_line = Effects.lineMsg(.fx_line),
                    .on_exit = Effects.exitMsg(.fx_exit),
                });
                return;
            }
        }
        model.pick_folder_live = false;
        if (!model.has_window_status()) {
            model.setWindowStatus(hostMissingStatus());
        }
        model.startProjectEdit();
        return;
    }
    model.pick_folder_live = false;
}

fn argvHas(argv: []const []const u8, needle: []const u8) bool {
    for (argv) |arg| {
        if (std.mem.eql(u8, arg, needle) or std.mem.indexOf(u8, arg, needle) != null) return true;
    }
    return false;
}

test "macos picker argv is osascript choose folder POSIX path" {
    const argv = argvFor(.osascript);
    try std.testing.expectEqualStrings(osascript_bin, argv[0]);
    try std.testing.expect(argvHas(argv, "-e"));
    try std.testing.expect(argvHas(argv, "choose folder"));
    try std.testing.expect(argvHas(argv, "POSIX path"));
    try std.testing.expect(isPickerArgv(argv));
}

test "linux zenity argv is file-selection directory" {
    const argv = argvFor(.zenity);
    try std.testing.expectEqualStrings(zenity_bin, argv[0]);
    try std.testing.expect(argvHas(argv, "--file-selection"));
    try std.testing.expect(argvHas(argv, "--directory"));
    try std.testing.expect(isPickerArgv(argv));
}

test "linux kdialog argv is getexistingdirectory" {
    const argv = argvFor(.kdialog);
    try std.testing.expectEqualStrings(kdialog_bin, argv[0]);
    try std.testing.expect(argvHas(argv, "--getexistingdirectory"));
    try std.testing.expect(isPickerArgv(argv));
}

test "host first argv is the platform folder dialog; Windows is skipped" {
    switch (builtin.os.tag) {
        .macos => {
            try std.testing.expectEqual(Picker.osascript, hostPicker(.first).?);
            try std.testing.expect(hostPicker(.fallback) == null);
        },
        .linux => {
            try std.testing.expectEqual(Picker.zenity, hostPicker(.first).?);
            try std.testing.expectEqual(Picker.kdialog, hostPicker(.fallback).?);
        },
        else => {
            try std.testing.expect(hostPicker(.first) == null);
            try std.testing.expect(hostPicker(.fallback) == null);
        },
    }
}

test "folder argv is not an image picker argv" {
    const pick_image = @import("pick_image.zig");
    const open_terminal = @import("open_terminal.zig");
    var term_scratch: open_terminal.ArgvScratch = .{};
    try std.testing.expect(!pick_image.isPickerArgv(argvFor(.osascript)));
    try std.testing.expect(!pick_image.isPickerArgv(argvFor(.zenity)));
    try std.testing.expect(!pick_image.isPickerArgv(argvFor(.kdialog)));
    try std.testing.expect(!isPickerArgv(pick_image.argvFor(.osascript)));
    try std.testing.expect(!isPickerArgv(pick_image.argvFor(.zenity)));
    try std.testing.expect(!isPickerArgv(pick_image.argvFor(.kdialog)));
    try std.testing.expect(!isPickerArgv(open_terminal.argvForTool(.windows_terminal, "/tmp/proj", &term_scratch)));
    try std.testing.expect(!isPickerArgv(open_terminal.argvForTool(.cmd_start, "/tmp/proj", &term_scratch)));
    try std.testing.expect(!open_terminal.isTerminalArgv(argvFor(.osascript)));
    try std.testing.expect(!open_terminal.isTerminalArgv(argvFor(.zenity)));
    try std.testing.expect(!open_terminal.isTerminalArgv(argvFor(.kdialog)));
}

test "firstStdoutPath trims and takes one line; error: prefix is not a path" {
    try std.testing.expectEqualStrings("/tmp/proj", firstStdoutPath("  /tmp/proj \n"));
    try std.testing.expectEqualStrings("/tmp/proj", firstStdoutPath("/tmp/proj\n/tmp/other\n"));
    try std.testing.expectEqualStrings("", firstStdoutPath("   \n"));
    try std.testing.expectEqualStrings("", firstStdoutPath(""));
    try std.testing.expectEqualStrings("install zenity", takeErrorMessage("error:install zenity").?);
    try std.testing.expect(takeErrorMessage("/tmp/proj") == null);
}

test "pick_folder_key is distinct from pick_image and neighbors" {
    const attach = @import("attach.zig");
    const maximize_window = @import("maximize_window.zig");
    const copy = @import("copy.zig");
    try std.testing.expect(pick_folder_key != attach.pick_image_key);
    try std.testing.expect(pick_folder_key != maximize_window.maximize_window_key);
    try std.testing.expect(pick_folder_key != copy.copy_turn_key);
    try std.testing.expect(pick_folder_key != 3);
    try std.testing.expect(pick_folder_key < 64);
}
