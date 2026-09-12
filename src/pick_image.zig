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
const i18n = @import("i18n.zig");

pub const SUBCOMMAND = "pick-image";
pub const cancel_exit: u8 = 1;
pub const missing_exit: u8 = 2;
pub const error_prefix = "error:";

pub const linux_missing_status = i18n.osImageDialogChromeFor(.english, "").linux_missing;
pub const macos_missing_status = i18n.osImageDialogChromeFor(.english, "").macos_missing;
pub const windows_missing_status = i18n.osImageDialogChromeFor(.english, "").windows_missing;

pub const osascript_bin = "osascript";
pub const zenity_bin = "zenity";
pub const zenity_filter = "Images|*.png *.jpg *.jpeg *.gif *.webp *.bmp";
pub const kdialog_bin = "kdialog";
pub const kdialog_filter = "*.png *.jpg *.jpeg *.gif *.webp *.bmp";
pub const title_flag = "--title";
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

fn osascriptScript(comptime prompt: []const u8) []const u8 {
    return "POSIX path of (choose file of type {\"public.image\"} with prompt \"" ++ prompt ++ "\")";
}

fn powershellScript(comptime prompt: []const u8) []const u8 {
    return "$ErrorActionPreference = 'Stop'; try { Add-Type -AssemblyName System.Windows.Forms; $d = New-Object System.Windows.Forms.OpenFileDialog; $d.Filter = '" ++ powershell_filter ++ "'; $d.Title = '" ++ prompt ++ "'; $d.Multiselect = $false; if ($d.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { exit 1 }; Write-Output $d.FileName } catch { exit 2 }";
}

const prompt_en = i18n.osImageDialogChromeFor(.english, "").prompt;
const prompt_zh_cn = i18n.osImageDialogChromeFor(.simplified_chinese, "").prompt;
const prompt_ja = i18n.osImageDialogChromeFor(.japanese, "").prompt;

/// English osascript `choose file` script. Localized spawn uses
/// `argvForLang`.
pub const osascript_script = osascriptScript(prompt_en);
/// English STA OpenFileDialog. Localized spawn uses `argvForLang`.
pub const powershell_script = powershellScript(prompt_en);

pub const Picker = enum { osascript, zenity, kdialog, powershell };
pub const Stage = enum { first, fallback };

const osascript_argv_en = [_][]const u8{ osascript_bin, "-e", osascriptScript(prompt_en) };
const osascript_argv_zh_cn = [_][]const u8{ osascript_bin, "-e", osascriptScript(prompt_zh_cn) };
const osascript_argv_ja = [_][]const u8{ osascript_bin, "-e", osascriptScript(prompt_ja) };

const zenity_argv_en = [_][]const u8{ zenity_bin, "--file-selection", "--file-filter", zenity_filter, title_flag, prompt_en };
const zenity_argv_zh_cn = [_][]const u8{ zenity_bin, "--file-selection", "--file-filter", zenity_filter, title_flag, prompt_zh_cn };
const zenity_argv_ja = [_][]const u8{ zenity_bin, "--file-selection", "--file-filter", zenity_filter, title_flag, prompt_ja };

const kdialog_argv_en = [_][]const u8{ kdialog_bin, title_flag, prompt_en, "--getopenfilename", ".", kdialog_filter };
const kdialog_argv_zh_cn = [_][]const u8{ kdialog_bin, title_flag, prompt_zh_cn, "--getopenfilename", ".", kdialog_filter };
const kdialog_argv_ja = [_][]const u8{ kdialog_bin, title_flag, prompt_ja, "--getopenfilename", ".", kdialog_filter };

const powershell_argv_en = [_][]const u8{ powershell_bin, powershell_noprofile, powershell_sta, powershell_command, powershellScript(prompt_en) };
const powershell_argv_zh_cn = [_][]const u8{ powershell_bin, powershell_noprofile, powershell_sta, powershell_command, powershellScript(prompt_zh_cn) };
const powershell_argv_ja = [_][]const u8{ powershell_bin, powershell_noprofile, powershell_sta, powershell_command, powershellScript(prompt_ja) };

/// English argv (identification tests / callers that do not pass locale).
pub fn argvFor(picker: Picker) []const []const u8 {
    return argvForLang(picker, .english);
}

/// Image-dialog argv for a resolved chrome locale (never `.system`).
pub fn argvForLang(picker: Picker, resolved: i18n.LanguagePreference) []const []const u8 {
    return switch (picker) {
        .osascript => switch (resolved) {
            .simplified_chinese => &osascript_argv_zh_cn,
            .japanese => &osascript_argv_ja,
            .system, .english => &osascript_argv_en,
        },
        .zenity => switch (resolved) {
            .simplified_chinese => &zenity_argv_zh_cn,
            .japanese => &zenity_argv_ja,
            .system, .english => &zenity_argv_en,
        },
        .kdialog => switch (resolved) {
            .simplified_chinese => &kdialog_argv_zh_cn,
            .japanese => &kdialog_argv_ja,
            .system, .english => &kdialog_argv_en,
        },
        .powershell => switch (resolved) {
            .simplified_chinese => &powershell_argv_zh_cn,
            .japanese => &powershell_argv_ja,
            .system, .english => &powershell_argv_en,
        },
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
    return hostArgvFor(stage, .english, "");
}

pub fn hostArgvFor(stage: Stage, preference: i18n.LanguagePreference, system_locale_id: []const u8) ?[]const []const u8 {
    return argvForLang(hostPicker(stage) orelse return null, i18n.resolve(preference, system_locale_id));
}

pub fn hostMissingStatus() []const u8 {
    return hostMissingStatusFor(.english, "");
}

pub fn hostMissingStatusFor(preference: i18n.LanguagePreference, system_locale_id: []const u8) []const u8 {
    const chrome = i18n.osImageDialogChromeFor(preference, system_locale_id);
    return switch (builtin.os.tag) {
        .macos => chrome.macos_missing,
        .windows => chrome.windows_missing,
        else => chrome.linux_missing,
    };
}

pub fn isPickerArgv(argv: []const []const u8) bool {
    if (argv.len == 0) return false;
    if (std.mem.eql(u8, argv[0], osascript_bin)) {
        return argvHas(argv, "choose file") and argvHas(argv, "public.image");
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
    try std.testing.expect(argvHas(argv, prompt_en));
    try std.testing.expect(isPickerArgv(argv));
}

test "linux zenity argv uses the documented image filter" {
    const argv = argvFor(.zenity);
    try std.testing.expectEqualStrings(zenity_bin, argv[0]);
    try std.testing.expect(argvHas(argv, "--file-selection"));
    try std.testing.expect(argvHas(argv, zenity_filter));
    try std.testing.expect(argvHas(argv, title_flag));
    try std.testing.expect(argvHas(argv, prompt_en));
    try std.testing.expect(isPickerArgv(argv));
}

test "linux kdialog argv is getopenfilename" {
    const argv = argvFor(.kdialog);
    try std.testing.expectEqualStrings(kdialog_bin, argv[0]);
    try std.testing.expect(argvHas(argv, "--getopenfilename"));
    try std.testing.expect(argvHas(argv, title_flag));
    try std.testing.expect(argvHas(argv, prompt_en));
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
    try std.testing.expect(argvHas(argv, prompt_en));
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

test "image picker argv and missing status follow resolved locale" {
    const pick_folder = @import("pick_folder.zig");
    const zh = i18n.osImageDialogChromeFor(.simplified_chinese, "");
    const ja = i18n.osImageDialogChromeFor(.japanese, "");
    const en = i18n.osImageDialogChromeFor(.english, "");

    try std.testing.expectEqualStrings(en.linux_missing, linux_missing_status);
    try std.testing.expectEqualStrings(en.macos_missing, macos_missing_status);
    try std.testing.expectEqualStrings(en.windows_missing, windows_missing_status);
    try std.testing.expectEqualStrings(hostMissingStatusFor(.english, ""), hostMissingStatus());
    try std.testing.expectEqualStrings(hostMissingStatusFor(.english, ""), hostMissingStatusFor(.english, "ja_JP.UTF-8"));
    try std.testing.expectEqualStrings(hostMissingStatusFor(.simplified_chinese, ""), hostMissingStatusFor(.system, "zh_CN.UTF-8"));
    try std.testing.expectEqualStrings(hostMissingStatusFor(.japanese, ""), hostMissingStatusFor(.system, "ja_JP.UTF-8"));
    switch (builtin.os.tag) {
        .macos => {
            try std.testing.expectEqualStrings(en.macos_missing, hostMissingStatus());
            try std.testing.expectEqualStrings(zh.macos_missing, hostMissingStatusFor(.simplified_chinese, ""));
            try std.testing.expectEqualStrings(ja.macos_missing, hostMissingStatusFor(.japanese, ""));
        },
        .windows => {
            try std.testing.expectEqualStrings(en.windows_missing, hostMissingStatus());
            try std.testing.expectEqualStrings(zh.windows_missing, hostMissingStatusFor(.simplified_chinese, ""));
            try std.testing.expectEqualStrings(ja.windows_missing, hostMissingStatusFor(.japanese, ""));
        },
        else => {
            try std.testing.expectEqualStrings(en.linux_missing, hostMissingStatus());
            try std.testing.expectEqualStrings(zh.linux_missing, hostMissingStatusFor(.simplified_chinese, ""));
            try std.testing.expectEqualStrings(ja.linux_missing, hostMissingStatusFor(.japanese, ""));
        },
    }

    const pickers = [_]Picker{ .osascript, .zenity, .kdialog, .powershell };
    for (pickers) |picker| {
        const en_argv = argvForLang(picker, .english);
        const zh_argv = argvForLang(picker, .simplified_chinese);
        const ja_argv = argvForLang(picker, .japanese);
        try std.testing.expect(isPickerArgv(en_argv));
        try std.testing.expect(isPickerArgv(zh_argv));
        try std.testing.expect(isPickerArgv(ja_argv));
        try std.testing.expect(!pick_folder.isPickerArgv(zh_argv));
        try std.testing.expect(!pick_folder.isPickerArgv(ja_argv));
        try std.testing.expect(argvHas(en_argv, en.prompt));
        try std.testing.expect(argvHas(zh_argv, zh.prompt));
        try std.testing.expect(argvHas(ja_argv, ja.prompt));
        try std.testing.expect(!argvHas(zh_argv, en.prompt));
        try std.testing.expect(!argvHas(ja_argv, en.prompt));
        try std.testing.expect(!argvHas(en_argv, zh.prompt));
        try std.testing.expect(!argvHas(en_argv, ja.prompt));
    }

    try std.testing.expect(argvHas(argvForLang(.osascript, .japanese), "choose file"));
    try std.testing.expect(argvHas(argvForLang(.osascript, .simplified_chinese), "public.image"));
    try std.testing.expect(argvHas(argvForLang(.osascript, .japanese), "POSIX path"));
    try std.testing.expect(argvHas(argvForLang(.powershell, .japanese), "OpenFileDialog"));
    try std.testing.expect(argvHas(argvForLang(.zenity, .japanese), title_flag));
    try std.testing.expect(argvHas(argvForLang(.kdialog, .simplified_chinese), "--getopenfilename"));
    try std.testing.expectEqualStrings(argvFor(.osascript)[0], argvForLang(.osascript, .english)[0]);
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
