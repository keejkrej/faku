//! One-shot OS image-picker sidecar.
//!
//! Native has no `fx.pickFile`. `Runtime.showOpenDialog` is a host-bridge
//! / WebView API, not an fx effect the TEA loop can call. Pick image
//! therefore `fx.spawn`s a documented OS file dialog that prints one
//! absolute path to stdout and exits. Spawn stdin is unused (write-once
//! then close). This is not a fake in-app picker and not an invented
//! Native file-open effect.
//!
//!   macOS:  osascript `choose file` of type public.image, POSIX path
//!   Linux:  zenity --file-selection (image filter), else kdialog
//!   Windows: powershell.exe -NoProfile -STA OpenFileDialog
//!            (System.Windows.Forms; PATH-resolved `.exe` like sibling
//!            `explorer.exe` / `wt.exe` / `cmd.exe`; each token its
//!            own argv slot). Cancel → empty stdout / cancel_exit.
//!            Missing PowerShell → missing_exit / typed-path fallback.

const std = @import("std");
const builtin = @import("builtin");

pub const SUBCOMMAND = "pick-image";
pub const cancel_exit: u8 = 1;
pub const missing_exit: u8 = 2;
pub const error_prefix = "error:";

pub const linux_missing_status = "No OS image picker (install zenity or kdialog). Type a path or drop a file.";
pub const macos_missing_status = "No OS image picker (osascript missing). Type a path or drop a file.";
pub const windows_missing_status = "No OS image picker (powershell.exe missing). Type a path or drop a file.";

pub const osascript_bin = "osascript";
pub const osascript_script = "POSIX path of (choose file of type {\"public.image\"} with prompt \"Choose an image\")";
pub const zenity_bin = "zenity";
pub const zenity_filter = "Images|*.png *.jpg *.jpeg *.gif *.webp *.bmp";
pub const kdialog_bin = "kdialog";
pub const kdialog_filter = "*.png *.jpg *.jpeg *.gif *.webp *.bmp";
/// PATH-resolved Windows PowerShell (desktop WinForms). Explicit `.exe`
/// suffix like sibling `explorer.exe` / `wt.exe` / `cmd.exe`.
pub const powershell_bin = "powershell.exe";
pub const powershell_noprofile = "-NoProfile";
pub const powershell_sta = "-STA";
pub const powershell_command = "-Command";
/// STA OpenFileDialog: OK prints one absolute path; Cancel exits 1
/// with no path; Add-Type / dialog failure exits missing_exit (2).
/// Filter matches zenity/kdialog image extensions. Distinct from
/// pick_folder FolderBrowserDialog.
pub const powershell_filter = "Images|*.png;*.jpg;*.jpeg;*.gif;*.webp;*.bmp";
pub const powershell_script =
    "$ErrorActionPreference = 'Stop'; try { Add-Type -AssemblyName System.Windows.Forms; $d = New-Object System.Windows.Forms.OpenFileDialog; $d.Filter = '" ++ powershell_filter ++ "'; $d.Title = 'Choose an image'; $d.Multiselect = $false; if ($d.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { exit 1 }; Write-Output $d.FileName } catch { exit 2 }";

pub const Picker = enum { osascript, zenity, kdialog, powershell };
pub const Stage = enum { first, fallback };

const osascript_argv = [_][]const u8{ osascript_bin, "-e", osascript_script };
const zenity_argv = [_][]const u8{ zenity_bin, "--file-selection", "--file-filter", zenity_filter };
const kdialog_argv = [_][]const u8{ kdialog_bin, "--getopenfilename", ".", kdialog_filter };
const powershell_argv = [_][]const u8{ powershell_bin, powershell_noprofile, powershell_sta, powershell_command, powershell_script };

pub fn argvFor(picker: Picker) []const []const u8 {
    return switch (picker) {
        .osascript => &osascript_argv,
        .zenity => &zenity_argv,
        .kdialog => &kdialog_argv,
        .powershell => &powershell_argv,
    };
}

pub fn hostPicker(stage: Stage) ?Picker {
    return switch (builtin.os.tag) {
        .macos => if (stage == .first) .osascript else null,
        .linux => switch (stage) {
            .first => .zenity,
            .fallback => .kdialog,
        },
        .windows => if (stage == .first) .powershell else null,
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
        return argvHas(argv, osascript_script) or argvHas(argv, "public.image");
    }
    if (std.mem.eql(u8, argv[0], zenity_bin)) {
        return argvHas(argv, "--file-selection") and !argvHas(argv, "--directory");
    }
    if (std.mem.eql(u8, argv[0], kdialog_bin)) {
        return argvHas(argv, "--getopenfilename");
    }
    if (std.mem.eql(u8, argv[0], powershell_bin)) {
        return argvHas(argv, powershell_sta) and argvHas(argv, "OpenFileDialog");
    }
    return argv.len >= 2 and std.mem.eql(u8, argv[1], SUBCOMMAND);
}

pub fn isSidecarArgv(args: []const []const u8) bool {
    return args.len >= 2 and std.mem.eql(u8, args[1], SUBCOMMAND);
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

fn argvHas(argv: []const []const u8, needle: []const u8) bool {
    for (argv) |arg| {
        if (std.mem.eql(u8, arg, needle) or std.mem.indexOf(u8, arg, needle) != null) return true;
    }
    return false;
}

test "macos picker argv is osascript choose file of type public.image" {
    const argv = argvFor(.osascript);
    try std.testing.expectEqualStrings(osascript_bin, argv[0]);
    try std.testing.expect(argvHas(argv, "-e"));
    try std.testing.expect(argvHas(argv, "choose file"));
    try std.testing.expect(argvHas(argv, "public.image"));
    try std.testing.expect(argvHas(argv, "POSIX path"));
    try std.testing.expect(isPickerArgv(argv));
}

test "linux zenity argv uses the documented image filter" {
    const argv = argvFor(.zenity);
    try std.testing.expectEqualStrings(zenity_bin, argv[0]);
    try std.testing.expect(argvHas(argv, "--file-selection"));
    try std.testing.expect(argvHas(argv, zenity_filter));
    try std.testing.expect(isPickerArgv(argv));
}

test "linux kdialog argv is getopenfilename" {
    const argv = argvFor(.kdialog);
    try std.testing.expectEqualStrings(kdialog_bin, argv[0]);
    try std.testing.expect(argvHas(argv, "--getopenfilename"));
    try std.testing.expect(isPickerArgv(argv));
}

test "windows picker argv is powershell STA OpenFileDialog" {
    const argv = argvFor(.powershell);
    try std.testing.expectEqualStrings(powershell_bin, argv[0]);
    try std.testing.expect(argvHas(argv, powershell_noprofile));
    try std.testing.expect(argvHas(argv, powershell_sta));
    try std.testing.expect(argvHas(argv, powershell_command));
    try std.testing.expect(argvHas(argv, "OpenFileDialog"));
    try std.testing.expect(argvHas(argv, "System.Windows.Forms"));
    try std.testing.expect(argvHas(argv, powershell_filter));
    try std.testing.expect(argvHas(argv, "*.png"));
    try std.testing.expect(argvHas(argv, "*.jpg"));
    try std.testing.expect(argvHas(argv, "*.jpeg"));
    try std.testing.expect(argvHas(argv, "*.gif"));
    try std.testing.expect(argvHas(argv, "*.webp"));
    try std.testing.expect(argvHas(argv, "*.bmp"));
    try std.testing.expect(argvHas(argv, "Choose an image"));
    try std.testing.expect(argvHas(argv, "Multiselect"));
    try std.testing.expect(argvHas(argv, "Write-Output"));
    try std.testing.expect(argvHas(argv, "FileName"));
    try std.testing.expect(argvHas(argv, "exit 1"));
    try std.testing.expect(argvHas(argv, "exit 2"));
    try std.testing.expect(!argvHas(argv, "FolderBrowserDialog"));
    try std.testing.expect(isPickerArgv(argv));
    try std.testing.expectEqual(@as(usize, 5), argv.len);
    try std.testing.expect(!isPickerArgv(&.{ powershell_bin, powershell_noprofile, powershell_sta, powershell_command, "Get-Date" }));
}

test "host first argv is the platform dialog" {
    switch (builtin.os.tag) {
        .macos => {
            try std.testing.expectEqual(Picker.osascript, hostPicker(.first).?);
            try std.testing.expect(hostPicker(.fallback) == null);
        },
        .linux => {
            try std.testing.expectEqual(Picker.zenity, hostPicker(.first).?);
            try std.testing.expectEqual(Picker.kdialog, hostPicker(.fallback).?);
        },
        .windows => {
            try std.testing.expectEqual(Picker.powershell, hostPicker(.first).?);
            try std.testing.expect(hostPicker(.fallback) == null);
        },
        else => {
            try std.testing.expect(hostPicker(.first) == null);
            try std.testing.expect(hostPicker(.fallback) == null);
        },
    }
}

test "image argv is not a folder picker argv" {
    const pick_folder = @import("pick_folder.zig");
    const open_terminal = @import("open_terminal.zig");
    const reveal_folder = @import("reveal_folder.zig");
    const open_editor = @import("open_editor.zig");
    var term_scratch: open_terminal.ArgvScratch = .{};
    var reveal_buf: [2][]const u8 = undefined;
    var editor_scratch: open_editor.ArgvScratch = .{};
    try std.testing.expect(!pick_folder.isPickerArgv(argvFor(.osascript)));
    try std.testing.expect(!pick_folder.isPickerArgv(argvFor(.zenity)));
    try std.testing.expect(!pick_folder.isPickerArgv(argvFor(.kdialog)));
    try std.testing.expect(!pick_folder.isPickerArgv(argvFor(.powershell)));
    try std.testing.expect(!isPickerArgv(pick_folder.argvFor(.osascript)));
    try std.testing.expect(!isPickerArgv(pick_folder.argvFor(.zenity)));
    try std.testing.expect(!isPickerArgv(pick_folder.argvFor(.kdialog)));
    try std.testing.expect(!isPickerArgv(pick_folder.argvFor(.powershell)));
    try std.testing.expect(!isPickerArgv(open_terminal.argvForTool(.windows_terminal, "/tmp/proj", &term_scratch)));
    try std.testing.expect(!isPickerArgv(open_terminal.argvForTool(.cmd_start, "/tmp/proj", &term_scratch)));
    try std.testing.expect(!isPickerArgv(reveal_folder.argvForTool(.explorer, "/tmp/proj", &reveal_buf)));
    try std.testing.expect(!isPickerArgv(open_editor.argvForTool(.windows_cursor, "/tmp/proj", &editor_scratch)));
    try std.testing.expect(!isPickerArgv(open_editor.argvForTool(.windows_code, "/tmp/proj", &editor_scratch)));
    try std.testing.expect(!open_terminal.isTerminalArgv(argvFor(.osascript)));
    try std.testing.expect(!open_terminal.isTerminalArgv(argvFor(.zenity)));
    try std.testing.expect(!open_terminal.isTerminalArgv(argvFor(.kdialog)));
    try std.testing.expect(!open_terminal.isTerminalArgv(argvFor(.powershell)));
    try std.testing.expect(!reveal_folder.isRevealArgv(argvFor(.powershell)));
    try std.testing.expect(!open_editor.isEditorArgv(argvFor(.powershell)));
}

test "firstStdoutPath trims and takes one line; error: prefix is not a path" {
    try std.testing.expectEqualStrings("/tmp/shot.png", firstStdoutPath("  /tmp/shot.png \n"));
    try std.testing.expectEqualStrings("/tmp/shot.png", firstStdoutPath("/tmp/shot.png\n/tmp/other.jpg\n"));
    try std.testing.expectEqualStrings("", firstStdoutPath("   \n"));
    try std.testing.expectEqualStrings("", firstStdoutPath(""));
    try std.testing.expectEqualStrings("install zenity", takeErrorMessage("error:install zenity").?);
    try std.testing.expect(takeErrorMessage("/tmp/shot.png") == null);
}

test "pick-image sidecar argv is the subcommand" {
    try std.testing.expect(isSidecarArgv(&.{ "faku", SUBCOMMAND }));
    try std.testing.expect(!isSidecarArgv(&.{ "faku", "acp-proxy" }));
    try std.testing.expect(isPickerArgv(&.{ "faku", SUBCOMMAND }));
}
