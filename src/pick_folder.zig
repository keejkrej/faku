//! One-shot directory picker: daemon BrowseDirectory, else OS dialog.
//!
//! Native has no `fx.pickFile`. `Runtime.showOpenDialog` is a host-bridge
//! / WebView API, not an fx effect the TEA loop can call. Pick folder
//! prefers hello + daemon `WorkspaceOperation::BrowseDirectory` when
//! `WAKU_DAEMON_ADDRESS` or persisted `last_daemon_address` is set
//! (in-app directory browser; initial probe `path: null` ⇒ daemon
//! home). Local OS `osascript` / `zenity` / `kdialog` / PowerShell
//! FolderBrowserDialog stays the fallback and remains the path when
//! there is no daemon address. Native 4 KiB stdin overflow / spawn
//! failure / non-ok / unusable parse fall back to that OS argv path.
//! Own daemon spawn key (`next_daemon_key`) so OS fallback can still
//! use `pick_folder_key` 29 after a daemon miss. This is not Waku's
//! DaemonFilePicker (no Virtuoso / filter / history stack) and not an
//! invented Native file-open effect.
//!
//!   macOS:  osascript `choose folder`, POSIX path
//!   Linux:  zenity --file-selection --directory, else kdialog
//!           --getexistingdirectory
//!   Windows: powershell.exe -NoProfile -STA FolderBrowserDialog
//!            (System.Windows.Forms; PATH-resolved `.exe` like sibling
//!            `explorer.exe` / `wt.exe` / `cmd.exe`; each token its
//!            own argv slot). Cancel → empty stdout / cancel_exit.
//!            Missing PowerShell → missing_exit / typed-path fallback.

const std = @import("std");
const builtin = @import("builtin");
const native_sdk = @import("native_sdk");
const main = @import("main.zig");
const persist = @import("persist.zig");
const daemon_proxy = @import("daemon_proxy.zig");
const protocol = @import("protocol.zig");
const store = @import("store.zig");

const Model = main.Model;
const Effects = main.Effects;
const writeFixed = main.writeFixed;

/// Distinct from pick_image (31), maximize (30), copy_turn (32),
/// attach_preview 33–63, fx_probe (3), fx_spawn 64+, git_branch 200+.
/// 29 sits in that gap and is unused by those tables.
pub const pick_folder_key: u64 = 29;

pub const max_dir_entries: usize = protocol.max_parsed_tree_entries;
pub const max_dir_entry_name: usize = 255;

pub const CachedDirEntry = struct {
    name_storage: [max_dir_entry_name]u8 = [_]u8{0} ** max_dir_entry_name,
    name_len: usize = 0,
    abs_storage: [main.max_project_path]u8 = [_]u8{0} ** main.max_project_path,
    abs_len: usize = 0,
    is_dir: bool = false,

    pub fn name(self: *const CachedDirEntry) []const u8 {
        return self.name_storage[0..self.name_len];
    }

    pub fn absolutePath(self: *const CachedDirEntry) []const u8 {
        return self.abs_storage[0..self.abs_len];
    }

    pub fn set(self: *CachedDirEntry, entry_name: []const u8, abs: []const u8, is_dir: bool) void {
        writeFixed(&self.name_storage, &self.name_len, entry_name);
        writeFixed(&self.abs_storage, &self.abs_len, abs);
        self.is_dir = is_dir;
    }
};

pub const cancel_exit: u8 = 1;
pub const missing_exit: u8 = 2;
pub const error_prefix = "error:";

pub const linux_missing_status = "No OS folder picker (install zenity or kdialog). Type a path.";
pub const macos_missing_status = "No OS folder picker (osascript missing). Type a path.";
pub const windows_missing_status = "No OS folder picker (powershell.exe missing). Type a path.";

pub const osascript_bin = "osascript";
pub const osascript_script = "POSIX path of (choose folder with prompt \"Choose a project\")";
pub const zenity_bin = "zenity";
pub const kdialog_bin = "kdialog";
/// PATH-resolved Windows PowerShell (desktop WinForms). Explicit `.exe`
/// suffix like sibling `explorer.exe` / `wt.exe` / `cmd.exe`.
pub const powershell_bin = "powershell.exe";
pub const powershell_noprofile = "-NoProfile";
pub const powershell_sta = "-STA";
pub const powershell_command = "-Command";
/// STA FolderBrowserDialog: OK prints one absolute path; Cancel exits 1
/// with no path; Add-Type / dialog failure exits missing_exit (2).
pub const powershell_script =
    "$ErrorActionPreference = 'Stop'; try { Add-Type -AssemblyName System.Windows.Forms; $d = New-Object System.Windows.Forms.FolderBrowserDialog; $d.Description = 'Choose a project'; if ($d.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { exit 1 }; Write-Output $d.SelectedPath } catch { exit 2 }";

pub const Picker = enum { osascript, zenity, kdialog, powershell };
pub const Stage = enum { first, fallback };

const osascript_argv = [_][]const u8{ osascript_bin, "-e", osascript_script };
const zenity_argv = [_][]const u8{ zenity_bin, "--file-selection", "--directory" };
const kdialog_argv = [_][]const u8{ kdialog_bin, "--getexistingdirectory", "." };
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
        return argvHas(argv, "choose folder") and argvHas(argv, "POSIX path");
    }
    if (std.mem.eql(u8, argv[0], zenity_bin)) {
        return argvHas(argv, "--file-selection") and argvHas(argv, "--directory");
    }
    if (std.mem.eql(u8, argv[0], kdialog_bin)) {
        return argvHas(argv, "--getexistingdirectory");
    }
    if (std.mem.eql(u8, argv[0], powershell_bin)) {
        return argvHas(argv, powershell_sta) and argvHas(argv, "FolderBrowserDialog");
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
    if (model.pick_folder_live or model.daemon_dir_browser_open) return;
    if (trySpawnDaemonBrowseDirectory(model, fx, null)) return;
    startOsPickFolder(model, fx);
}

fn startOsPickFolder(model: *Model, fx: *Effects) void {
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

/// Best-effort hello + `WorkspaceOperation::BrowseDirectory`. Own
/// daemon spawn key so OS fallback can use `pick_folder_key` 29
/// after a miss. Missing address or Native 4 KiB stdin overflow
/// returns false. `path` null is the initial home probe.
fn trySpawnDaemonBrowseDirectory(model: *Model, fx: *Effects, path: ?[]const u8) bool {
    const address = store.resolveDaemonMirrorAddress(model);
    if (address.len == 0) return false;
    var stdin_buf: [4096]u8 = undefined;
    const stdin = daemon_proxy.writeWorkspaceStdin(&stdin_buf, .{
        .token = model.daemonToken(),
        .operation = .{ .browse_directory = .{ .path = path } },
    }) catch return false;

    cancelDaemonBrowseSpawn(model, fx);
    const key = model.next_daemon_key;
    model.next_daemon_key += 1;
    model.daemon_dir_browser_key = key;
    model.daemon_dir_browser_open = true;
    model.daemon_dir_browser_ok = false;
    model.daemon_dir_browser_count = 0;
    model.clearWindowStatus();
    fx.spawn(.{
        .key = key,
        .argv = &.{ model.sidecarPath(), daemon_proxy.SUBCOMMAND, address },
        .stdin = stdin,
        .max_line_bytes = main.daemon_line_bytes,
        .on_line = Effects.lineMsg(.fx_line),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
    return true;
}

fn cancelDaemonBrowseSpawn(model: *Model, fx: *Effects) void {
    if (model.daemon_dir_browser_key == 0) return;
    fx.cancel(model.daemon_dir_browser_key);
    model.daemon_dir_browser_key = 0;
}

fn clearDaemonBrowserPaint(model: *Model) void {
    model.daemon_dir_browser_path_len = 0;
    model.daemon_dir_browser_parent_len = 0;
    model.daemon_dir_browser_home_len = 0;
    model.daemon_dir_browser_root_len = 0;
    model.daemon_dir_browser_count = 0;
}

pub fn closeDaemonBrowser(model: *Model, fx: *Effects) void {
    cancelDaemonBrowseSpawn(model, fx);
    model.daemon_dir_browser_open = false;
    model.daemon_dir_browser_ok = false;
    clearDaemonBrowserPaint(model);
}

pub fn dropDaemonBrowser(model: *Model) void {
    model.daemon_dir_browser_open = false;
    model.daemon_dir_browser_ok = false;
    clearDaemonBrowserPaint(model);
}

pub fn confirmDaemonBrowser(model: *Model, fx: *Effects) void {
    if (!model.daemon_dir_browser_open or !model.daemon_dir_browser_ok) return;
    const path = model.daemon_dir_browser_path_storage[0..model.daemon_dir_browser_path_len];
    if (path.len == 0) return;
    model.setSelectedProjectPath(path);
    model.clearWindowStatus();
    persist.persistComposerProject(model, fx);
    closeDaemonBrowser(model, fx);
}

pub fn navigateDaemonBrowserUp(model: *Model, fx: *Effects) void {
    if (!model.daemon_dir_browser_open) return;
    const parent = model.daemon_dir_browser_parent_storage[0..model.daemon_dir_browser_parent_len];
    if (parent.len == 0) return;
    if (!trySpawnDaemonBrowseDirectory(model, fx, parent)) {
        fallbackOsAfterDaemonMiss(model, fx);
    }
}

pub fn navigateDaemonBrowserHome(model: *Model, fx: *Effects) void {
    if (!model.daemon_dir_browser_open) return;
    const home = model.daemon_dir_browser_home_storage[0..model.daemon_dir_browser_home_len];
    const path: ?[]const u8 = if (home.len > 0) home else null;
    if (!trySpawnDaemonBrowseDirectory(model, fx, path)) {
        fallbackOsAfterDaemonMiss(model, fx);
    }
}

pub fn navigateDaemonBrowserEntry(model: *Model, fx: *Effects, row_id: u32) void {
    if (!model.daemon_dir_browser_open or row_id == 0) return;
    const index = row_id - 1;
    if (index >= model.daemon_dir_browser_count) return;
    const entry = model.daemon_dir_browser_store[index];
    if (!entry.is_dir) return;
    const abs = entry.absolutePath();
    if (abs.len == 0) return;
    if (!trySpawnDaemonBrowseDirectory(model, fx, abs)) {
        fallbackOsAfterDaemonMiss(model, fx);
    }
}

fn fallbackOsAfterDaemonMiss(model: *Model, fx: *Effects) void {
    closeDaemonBrowser(model, fx);
    startOsPickFolder(model, fx);
}

pub fn applyDaemonLine(model: *Model, line: native_sdk.EffectLine) void {
    if (line.key != model.daemon_dir_browser_key or model.daemon_dir_browser_key == 0) return;
    if (!model.daemon_dir_browser_open) return;
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const parsed = protocol.parseDirectory(arena_state.allocator(), line.line);
    if (!parsed.ok) return;
    writeFixed(&model.daemon_dir_browser_path_storage, &model.daemon_dir_browser_path_len, parsed.path);
    writeFixed(&model.daemon_dir_browser_parent_storage, &model.daemon_dir_browser_parent_len, parsed.parent);
    writeFixed(&model.daemon_dir_browser_home_storage, &model.daemon_dir_browser_home_len, parsed.home);
    writeFixed(&model.daemon_dir_browser_root_storage, &model.daemon_dir_browser_root_len, parsed.filesystem_root);
    model.daemon_dir_browser_count = 0;
    var i: usize = 0;
    while (i < parsed.entry_count) : (i += 1) {
        if (model.daemon_dir_browser_count >= max_dir_entries) break;
        const entry = parsed.entries[i];
        model.daemon_dir_browser_store[model.daemon_dir_browser_count].set(entry.name, entry.absolute_path, entry.is_dir);
        model.daemon_dir_browser_count += 1;
    }
    model.daemon_dir_browser_ok = true;
}

pub fn handleDaemonExit(model: *Model, fx: *Effects, exit: native_sdk.EffectExit) void {
    if (exit.key != model.daemon_dir_browser_key or model.daemon_dir_browser_key == 0) return;
    const open = model.daemon_dir_browser_open;
    const ok = model.daemon_dir_browser_ok;
    model.daemon_dir_browser_key = 0;
    if (!open) return;
    if (ok) return;
    fallbackOsAfterDaemonMiss(model, fx);
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

test "windows picker argv is powershell STA FolderBrowserDialog" {
    const argv = argvFor(.powershell);
    try std.testing.expectEqualStrings(powershell_bin, argv[0]);
    try std.testing.expect(argvHas(argv, powershell_noprofile));
    try std.testing.expect(argvHas(argv, powershell_sta));
    try std.testing.expect(argvHas(argv, powershell_command));
    try std.testing.expect(argvHas(argv, "FolderBrowserDialog"));
    try std.testing.expect(argvHas(argv, "System.Windows.Forms"));
    try std.testing.expect(isPickerArgv(argv));
    try std.testing.expectEqual(@as(usize, 5), argv.len);
    try std.testing.expect(!isPickerArgv(&.{ powershell_bin, powershell_noprofile, powershell_sta, powershell_command, "Get-Date" }));
}

test "host first argv is the platform folder dialog" {
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

test "folder argv is not an image picker argv" {
    const pick_image = @import("pick_image.zig");
    const open_terminal = @import("open_terminal.zig");
    const reveal_folder = @import("reveal_folder.zig");
    const open_editor = @import("open_editor.zig");
    var term_scratch: open_terminal.ArgvScratch = .{};
    var reveal_buf: [2][]const u8 = undefined;
    var editor_scratch: open_editor.ArgvScratch = .{};
    try std.testing.expect(!pick_image.isPickerArgv(argvFor(.osascript)));
    try std.testing.expect(!pick_image.isPickerArgv(argvFor(.zenity)));
    try std.testing.expect(!pick_image.isPickerArgv(argvFor(.kdialog)));
    try std.testing.expect(!pick_image.isPickerArgv(argvFor(.powershell)));
    try std.testing.expect(!isPickerArgv(pick_image.argvFor(.osascript)));
    try std.testing.expect(!isPickerArgv(pick_image.argvFor(.zenity)));
    try std.testing.expect(!isPickerArgv(pick_image.argvFor(.kdialog)));
    try std.testing.expect(!isPickerArgv(pick_image.argvFor(.powershell)));
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

fn pendingSpawnKey(fx: *Effects, key: u64) ?@TypeOf(fx.pendingSpawnAt(0).?) {
    var i: usize = 0;
    while (fx.pendingSpawnAt(i)) |spawn| : (i += 1) {
        if (spawn.key == key) return spawn;
    }
    return null;
}

const directory_ok_line = "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000014\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"workspace\",\"result\":{\"type\":\"directory\",\"path\":\"/home/me\",\"parent\":null,\"home\":\"/home/me\",\"filesystemRoot\":\"/\",\"entries\":[{\"relativePath\":\"src\",\"absolutePath\":\"/home/me/src\",\"name\":\"src\",\"isDir\":true,\"expanded\":false,\"depth\":0},{\"relativePath\":\"README.md\",\"absolutePath\":\"/home/me/README.md\",\"name\":\"README.md\",\"isDir\":false,\"expanded\":false,\"depth\":0}]}}}}";

const directory_nested_line = "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000014\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"workspace\",\"result\":{\"type\":\"directory\",\"path\":\"/home/me/src\",\"parent\":\"/home/me\",\"home\":\"/home/me\",\"filesystemRoot\":\"/\",\"entries\":[{\"relativePath\":\"main.zig\",\"absolutePath\":\"/home/me/src/main.zig\",\"name\":\"main.zig\",\"isDir\":false,\"expanded\":false,\"depth\":0}]}}}}";

test "pick folder with a daemon address spawns BrowseDirectory sidecar" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    startPickFolder(&model, &fx);
    try std.testing.expect(model.daemon_dir_browser_open);
    try std.testing.expect(!model.pick_folder_live);
    const sidecar = pendingSpawnKey(&fx, model.daemon_dir_browser_key) orelse return error.MissingDaemonBrowseDirectory;
    try std.testing.expect(daemon_proxy.isSidecarArgv(sidecar.argv));
    try std.testing.expectEqualStrings("faku", sidecar.argv[0]);
    try std.testing.expectEqualStrings(daemon_proxy.SUBCOMMAND, sidecar.argv[1]);
    try std.testing.expectEqualStrings("127.0.0.1:8787", sidecar.argv[2]);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"hello\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"workspace\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"browseDirectory\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"path\":null") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"prompt\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"listTree\"") == null);
    try std.testing.expect(sidecar.key != pick_folder_key);
    try std.testing.expectEqual(sidecar.key, model.daemon_dir_browser_key);
}

test "pick folder without a daemon address still uses OS argv helpers" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setSidecarPath("faku");
    try std.testing.expectEqual(@as(usize, 0), store.resolveDaemonMirrorAddress(&model).len);
    startPickFolder(&model, &fx);
    try std.testing.expect(!model.daemon_dir_browser_open);
    if (hostArgv(.first) == null) {
        try std.testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
        try std.testing.expect(model.has_window_status());
        return;
    }
    try std.testing.expect(model.pick_folder_live);
    const spawn = pendingSpawnKey(&fx, pick_folder_key) orelse return error.MissingOsFolderPicker;
    try std.testing.expect(isPickerArgv(spawn.argv));
    try std.testing.expect(!daemon_proxy.isSidecarArgv(spawn.argv));
    try std.testing.expectEqualStrings("", spawn.stdin);
    try std.testing.expectEqual(pick_folder_key, spawn.key);
}

test "BrowseDirectory sidecar paints the in-app browser and Choose sets project_path" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var store_buf: [256]u8 = undefined;
    const store_dir = try std.fmt.bufPrint(&store_buf, ".zig-cache/tmp/{s}/browse-choose", .{tmp.sub_path[0..]});

    var model = Model{};
    model.task_state_loaded = true;
    model.setStoreDir(store_dir);
    model.store_io = std.testing.io;
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    const id = model.addSession("browse choose", .fx);
    model.selected = id;

    startPickFolder(&model, &fx);
    const sidecar = pendingSpawnKey(&fx, model.daemon_dir_browser_key) orelse return error.MissingDaemonBrowseDirectoryFill;
    applyDaemonLine(&model, .{ .key = sidecar.key, .line = directory_ok_line });
    try std.testing.expect(model.daemon_dir_browser_ok);
    try std.testing.expectEqualStrings("/home/me", model.daemon_dir_browser_path_storage[0..model.daemon_dir_browser_path_len]);
    try std.testing.expectEqual(@as(u32, 2), model.daemon_dir_browser_count);
    try std.testing.expect(model.daemon_dir_browser_store[0].is_dir);
    try std.testing.expectEqualStrings("src", model.daemon_dir_browser_store[0].name());
    try std.testing.expect(!model.daemon_dir_browser_store[1].is_dir);
    var row_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer row_arena.deinit();
    const rows = model.daemon_dir_browser_rows(row_arena.allocator());
    try std.testing.expectEqual(@as(usize, 2), rows.len);
    try std.testing.expectEqualStrings("src", rows[0].label);
    try std.testing.expect(rows[0].is_dir);
    try std.testing.expectEqualStrings("README.md", rows[1].label);
    try std.testing.expect(!rows[1].is_dir);
    handleDaemonExit(&model, &fx, .{ .key = sidecar.key, .reason = .exited, .code = 0 });
    try std.testing.expect(model.daemon_dir_browser_open);
    try std.testing.expectEqual(@as(u64, 0), model.daemon_dir_browser_key);

    confirmDaemonBrowser(&model, &fx);
    try std.testing.expectEqualStrings("/home/me", model.selectedProjectPath());
    try std.testing.expect(!model.daemon_dir_browser_open);
    try std.testing.expect(!model.pick_folder_live);
}

test "BrowseDirectory non-ok falls back to OS pick_folder argv" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setDaemonAddress("10.0.0.2:9");
    model.setSidecarPath("faku");
    startPickFolder(&model, &fx);
    const sidecar = pendingSpawnKey(&fx, model.daemon_dir_browser_key) orelse return error.MissingDaemonBrowseDirectoryFallback;
    applyDaemonLine(&model, .{
        .key = sidecar.key,
        .line = "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000014\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"workspace\",\"result\":{\"type\":\"ack\"}}}}",
    });
    try std.testing.expect(!model.daemon_dir_browser_ok);
    handleDaemonExit(&model, &fx, .{ .key = sidecar.key, .reason = .exited, .code = 1 });
    try std.testing.expect(!model.daemon_dir_browser_open);
    if (hostArgv(.first) == null) {
        try std.testing.expect(model.has_window_status());
        return;
    }
    try std.testing.expect(model.pick_folder_live);
    const os_spawn = pendingSpawnKey(&fx, pick_folder_key) orelse return error.MissingOsFallbackAfterDaemonMiss;
    try std.testing.expect(isPickerArgv(os_spawn.argv));
    try std.testing.expectEqual(pick_folder_key, os_spawn.key);
    try std.testing.expect(os_spawn.key != sidecar.key);
}

test "BrowseDirectory navigate into a dir re-spawns with absolutePath" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    startPickFolder(&model, &fx);
    const first = pendingSpawnKey(&fx, model.daemon_dir_browser_key) orelse return error.MissingDaemonBrowseDirectoryNav;
    applyDaemonLine(&model, .{ .key = first.key, .line = directory_ok_line });
    handleDaemonExit(&model, &fx, .{ .key = first.key, .reason = .exited, .code = 0 });

    navigateDaemonBrowserEntry(&model, &fx, 1);
    const second = pendingSpawnKey(&fx, model.daemon_dir_browser_key) orelse return error.MissingDaemonBrowseDirectoryChild;
    try std.testing.expect(second.key != first.key);
    try std.testing.expect(std.mem.indexOf(u8, second.stdin, "\"type\":\"browseDirectory\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, second.stdin, "\"path\":\"/home/me/src\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, second.stdin, "\"path\":null") == null);
    applyDaemonLine(&model, .{ .key = second.key, .line = directory_nested_line });
    try std.testing.expectEqualStrings("/home/me/src", model.daemon_dir_browser_path_storage[0..model.daemon_dir_browser_path_len]);
    try std.testing.expectEqualStrings("/home/me", model.daemon_dir_browser_parent_storage[0..model.daemon_dir_browser_parent_len]);
}

test "BrowseDirectory cancel closes without changing project" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    const id = model.addSession("browse cancel", .fx);
    model.selected = id;
    startPickFolder(&model, &fx);
    const sidecar = pendingSpawnKey(&fx, model.daemon_dir_browser_key) orelse return error.MissingDaemonBrowseDirectoryCancel;
    applyDaemonLine(&model, .{ .key = sidecar.key, .line = directory_ok_line });
    closeDaemonBrowser(&model, &fx);
    try std.testing.expect(!model.daemon_dir_browser_open);
    try std.testing.expectEqualStrings("", model.selectedProjectPath());
    try std.testing.expect(!model.pick_folder_live);
}
