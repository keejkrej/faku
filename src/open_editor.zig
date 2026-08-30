//! One-shot OS editor-open sidecar.
//!
//! Native has no typed open-editor effect. Open in Editor therefore
//! `fx.spawn`s a documented host editor at the selected session
//! `project_path`:
//!
//!   Prefer `cursor` on PATH with the directory as the sole arg.
//!   Else prefer `code` on PATH with the directory as the sole arg.
//!   macOS fallbacks if those bins are missing:
//!     `open -a Cursor PATH`, then `open -a "Visual Studio Code" PATH`.
//!   Linux: only `cursor` then `code` (no flatpak/snap URLs).
//!   Windows: skipped (app.zon is macos/linux; no Windows spawn path)
//!
//! This is the third honest cut of Waku 0.1.11 "Open in.." — Cursor /
//! VS Code only, not a full app picker, not a persisted `open_in_app`,
//! and not an embedded editor panel. Spawn stdin is unused
//! (write-once then close).

const std = @import("std");
const builtin = @import("builtin");
const native_sdk = @import("native_sdk");
const main = @import("main.zig");
const reveal_folder = @import("reveal_folder.zig");
const open_terminal = @import("open_terminal.zig");

const Model = main.Model;
const Effects = main.Effects;

/// Distinct from open_terminal (27), reveal_folder (28), pick_folder (29),
/// maximize (30), pick_image (31), copy_turn (32), attach_preview 33–63,
/// fx_probe (3), fx_spawn 64+, git_branch 200+. 26 sits in that gap and
/// is unused by those tables.
pub const open_editor_key: u64 = 26;
/// Absolute editor target: session `project_path`, or that directory
/// plus a Files-pane relpath. Fits `max_project_path` + 255 + `/`.
pub const max_open_path = main.max_project_path + 256;

pub const missing_exit: u8 = 2;

pub const linux_missing_status = "No OS editor (install cursor or code).";
pub const macos_missing_status = "Cursor / VS Code / open missing";
pub const windows_missing_status = "Open in Editor is not available on Windows.";
pub const no_project_status = "No project folder for Editor.";

pub const cursor_bin = "cursor";
pub const code_bin = "code";
pub const macos_bin = "open";
pub const macos_app_flag = "-a";
pub const macos_cursor_app = "Cursor";
pub const macos_vscode_app = "Visual Studio Code";

pub const Tool = enum { cursor, code, open_cursor, open_vscode };
pub const Stage = enum { first, fallback, macos_cursor_app, macos_vscode_app };

const argv_cap: usize = 4;

pub const ArgvScratch = struct {
    slots: [argv_cap][]const u8 = .{ "", "", "", "" },
};

pub fn hostTool(stage: Stage) ?Tool {
    return switch (builtin.os.tag) {
        .macos => switch (stage) {
            .first => .cursor,
            .fallback => .code,
            .macos_cursor_app => .open_cursor,
            .macos_vscode_app => .open_vscode,
        },
        .linux => switch (stage) {
            .first => .cursor,
            .fallback => .code,
            .macos_cursor_app, .macos_vscode_app => null,
        },
        else => null,
    };
}

pub fn hostBin(stage: Stage) ?[]const u8 {
    return binFor(hostTool(stage) orelse return null);
}

pub fn nextStage(stage: Stage) ?Stage {
    const candidate: Stage = switch (stage) {
        .first => .fallback,
        .fallback => .macos_cursor_app,
        .macos_cursor_app => .macos_vscode_app,
        .macos_vscode_app => return null,
    };
    if (hostTool(candidate) == null) return null;
    return candidate;
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
        .cursor => cursor_bin,
        .code => code_bin,
        .open_cursor, .open_vscode => macos_bin,
    };
}

pub fn appFor(tool: Tool) ?[]const u8 {
    return switch (tool) {
        .open_cursor => macos_cursor_app,
        .open_vscode => macos_vscode_app,
        .cursor, .code => null,
    };
}

pub fn argvForTool(tool: Tool, path: []const u8, scratch: *ArgvScratch) []const []const u8 {
    return switch (tool) {
        .cursor, .code => {
            scratch.slots = .{ binFor(tool), path, "", "" };
            return scratch.slots[0..2];
        },
        .open_cursor, .open_vscode => {
            scratch.slots = .{ macos_bin, macos_app_flag, appFor(tool).?, path };
            return scratch.slots[0..4];
        },
    };
}

pub fn argvFor(stage: Stage, path: []const u8, scratch: *ArgvScratch) ?[]const []const u8 {
    return argvForTool(hostTool(stage) orelse return null, path, scratch);
}

pub fn isEditorArgv(argv: []const []const u8) bool {
    if (argv.len == 2) {
        return std.mem.eql(u8, argv[0], cursor_bin) or std.mem.eql(u8, argv[0], code_bin);
    }
    if (argv.len == 4) {
        if (!std.mem.eql(u8, argv[0], macos_bin) or !std.mem.eql(u8, argv[1], macos_app_flag)) return false;
        return std.mem.eql(u8, argv[2], macos_cursor_app) or std.mem.eql(u8, argv[2], macos_vscode_app);
    }
    return false;
}

/// Absolute existing selected-session directory. Hidden for Local /
/// empty / missing / relative / file paths. Reuses Reveal's resolver
/// so the spawn gate stays the same "openable path" cut as Terminal.
pub fn canOpenEditor(model: *const Model) bool {
    return reveal_folder.resolveRevealPath(model) != null;
}

pub fn resolveOpenPath(model: *const Model) ?[]const u8 {
    return reveal_folder.resolveRevealPath(model);
}

pub fn startOpenEditor(model: *Model, fx: *Effects) void {
    if (model.open_editor_live) return;
    const path = resolveOpenPath(model) orelse {
        model.setWindowStatus(no_project_status);
        return;
    };
    startOpenEditorAt(model, fx, path);
}

/// Same `cursor` / `code` / `open -a` argv as directory Open in Editor,
/// with `path` as the sole path argument. Files-pane clicks pass an
/// absolute file path; the directory button still passes `project_path`.
pub fn startOpenEditorAt(model: *Model, fx: *Effects, path: []const u8) void {
    if (model.open_editor_live) return;
    if (path.len == 0) {
        model.setWindowStatus(no_project_status);
        return;
    }
    const tool = hostTool(.first) orelse {
        model.setWindowStatus(hostMissingStatus());
        return;
    };
    main.writeFixed(&model.open_editor_path_storage, &model.open_editor_path_len, path);
    model.open_editor_live = true;
    model.open_editor_stage = .first;
    model.clearWindowStatus();
    spawnEditor(fx, tool, model.openEditorPath());
}

fn spawnEditor(fx: *Effects, tool: Tool, path: []const u8) void {
    var scratch: ArgvScratch = .{};
    fx.spawn(.{
        .key = open_editor_key,
        .argv = argvForTool(tool, path, &scratch),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
}

fn isMissingEditorExit(exit: native_sdk.EffectExit) bool {
    if (exit.reason != .exited) return true;
    return exit.code == 127 or exit.code == missing_exit;
}

pub fn handleOpenEditorExit(model: *Model, fx: *Effects, exit: native_sdk.EffectExit) void {
    if (isMissingEditorExit(exit)) {
        if (nextStage(model.open_editor_stage)) |stage| {
            const path = model.openEditorPath();
            if (path.len > 0) {
                if (hostTool(stage)) |tool| {
                    model.open_editor_stage = stage;
                    spawnEditor(fx, tool, path);
                    return;
                }
            }
        }
        if (!model.has_window_status()) {
            model.setWindowStatus(hostMissingStatus());
        }
    }
    model.open_editor_live = false;
}

test "cursor argv is cursor PATH" {
    var scratch: ArgvScratch = .{};
    const argv = argvForTool(.cursor, "/tmp/proj", &scratch);
    try std.testing.expectEqual(@as(usize, 2), argv.len);
    try std.testing.expectEqualStrings(cursor_bin, argv[0]);
    try std.testing.expectEqualStrings("/tmp/proj", argv[1]);
    try std.testing.expect(isEditorArgv(argv));
}

test "cursor argv with a file path stays bin PATH" {
    var scratch: ArgvScratch = .{};
    const argv = argvForTool(.cursor, "/tmp/proj/src/main.zig", &scratch);
    try std.testing.expectEqual(@as(usize, 2), argv.len);
    try std.testing.expectEqualStrings(cursor_bin, argv[0]);
    try std.testing.expectEqualStrings("/tmp/proj/src/main.zig", argv[1]);
    try std.testing.expect(isEditorArgv(argv));
}

test "code argv is code PATH" {
    var scratch: ArgvScratch = .{};
    const argv = argvForTool(.code, "/tmp/proj", &scratch);
    try std.testing.expectEqual(@as(usize, 2), argv.len);
    try std.testing.expectEqualStrings(code_bin, argv[0]);
    try std.testing.expectEqualStrings("/tmp/proj", argv[1]);
    try std.testing.expect(isEditorArgv(argv));
}

test "macos Cursor app argv is open -a Cursor PATH" {
    var scratch: ArgvScratch = .{};
    const argv = argvForTool(.open_cursor, "/tmp/proj", &scratch);
    try std.testing.expectEqual(@as(usize, 4), argv.len);
    try std.testing.expectEqualStrings(macos_bin, argv[0]);
    try std.testing.expectEqualStrings(macos_app_flag, argv[1]);
    try std.testing.expectEqualStrings(macos_cursor_app, argv[2]);
    try std.testing.expectEqualStrings("/tmp/proj", argv[3]);
    try std.testing.expect(isEditorArgv(argv));
}

test "macos VS Code app argv is open -a Visual Studio Code PATH" {
    var scratch: ArgvScratch = .{};
    const argv = argvForTool(.open_vscode, "/tmp/proj", &scratch);
    try std.testing.expectEqual(@as(usize, 4), argv.len);
    try std.testing.expectEqualStrings(macos_bin, argv[0]);
    try std.testing.expectEqualStrings(macos_app_flag, argv[1]);
    try std.testing.expectEqualStrings(macos_vscode_app, argv[2]);
    try std.testing.expectEqualStrings("/tmp/proj", argv[3]);
    try std.testing.expect(isEditorArgv(argv));
}

test "host first argv is cursor then code; macOS has app fallbacks; Windows is skipped" {
    switch (builtin.os.tag) {
        .macos => {
            try std.testing.expectEqual(Tool.cursor, hostTool(.first).?);
            try std.testing.expectEqual(Tool.code, hostTool(.fallback).?);
            try std.testing.expectEqual(Tool.open_cursor, hostTool(.macos_cursor_app).?);
            try std.testing.expectEqual(Tool.open_vscode, hostTool(.macos_vscode_app).?);
            try std.testing.expectEqualStrings(cursor_bin, hostBin(.first).?);
            try std.testing.expectEqualStrings(code_bin, hostBin(.fallback).?);
            try std.testing.expectEqual(Stage.fallback, nextStage(.first).?);
            try std.testing.expectEqual(Stage.macos_cursor_app, nextStage(.fallback).?);
            try std.testing.expectEqual(Stage.macos_vscode_app, nextStage(.macos_cursor_app).?);
            try std.testing.expect(nextStage(.macos_vscode_app) == null);
        },
        .linux => {
            try std.testing.expectEqual(Tool.cursor, hostTool(.first).?);
            try std.testing.expectEqual(Tool.code, hostTool(.fallback).?);
            try std.testing.expect(hostTool(.macos_cursor_app) == null);
            try std.testing.expect(hostTool(.macos_vscode_app) == null);
            try std.testing.expectEqualStrings(cursor_bin, hostBin(.first).?);
            try std.testing.expectEqualStrings(code_bin, hostBin(.fallback).?);
            try std.testing.expectEqual(Stage.fallback, nextStage(.first).?);
            try std.testing.expect(nextStage(.fallback) == null);
        },
        else => {
            try std.testing.expect(hostTool(.first) == null);
            try std.testing.expect(hostTool(.fallback) == null);
            try std.testing.expect(nextStage(.first) == null);
        },
    }
}

test "editor argv is not reveal terminal or folder-picker argv" {
    const pick_folder = @import("pick_folder.zig");
    var scratch: ArgvScratch = .{};
    var reveal_buf: [2][]const u8 = undefined;
    var term_scratch: open_terminal.ArgvScratch = .{};
    try std.testing.expect(!reveal_folder.isRevealArgv(argvForTool(.cursor, "/tmp/proj", &scratch)));
    try std.testing.expect(!reveal_folder.isRevealArgv(argvForTool(.code, "/tmp/proj", &scratch)));
    try std.testing.expect(!reveal_folder.isRevealArgv(argvForTool(.open_cursor, "/tmp/proj", &scratch)));
    try std.testing.expect(!reveal_folder.isRevealArgv(argvForTool(.open_vscode, "/tmp/proj", &scratch)));
    try std.testing.expect(!open_terminal.isTerminalArgv(argvForTool(.cursor, "/tmp/proj", &scratch)));
    try std.testing.expect(!open_terminal.isTerminalArgv(argvForTool(.code, "/tmp/proj", &scratch)));
    try std.testing.expect(!open_terminal.isTerminalArgv(argvForTool(.open_cursor, "/tmp/proj", &scratch)));
    try std.testing.expect(!open_terminal.isTerminalArgv(argvForTool(.open_vscode, "/tmp/proj", &scratch)));
    try std.testing.expect(!pick_folder.isPickerArgv(argvForTool(.cursor, "/tmp/proj", &scratch)));
    try std.testing.expect(!pick_folder.isPickerArgv(argvForTool(.open_cursor, "/tmp/proj", &scratch)));
    try std.testing.expect(!isEditorArgv(reveal_folder.argvFor("/tmp/proj", &reveal_buf)));
    try std.testing.expect(!isEditorArgv(open_terminal.argvForTool(.open_terminal, "/tmp/proj", &term_scratch)));
    try std.testing.expect(!isEditorArgv(open_terminal.argvForTool(.x_terminal_emulator, "/tmp/proj", &term_scratch)));
    try std.testing.expect(!isEditorArgv(pick_folder.argvFor(.osascript)));
    try std.testing.expect(!isEditorArgv(pick_folder.argvFor(.zenity)));
    try std.testing.expect(!isEditorArgv(pick_folder.argvFor(.kdialog)));
}

test "open_editor_key is 26 and distinct from terminal/reveal/pick neighbors" {
    const pick_folder = @import("pick_folder.zig");
    const attach = @import("attach.zig");
    const maximize_window = @import("maximize_window.zig");
    const copy = @import("copy.zig");
    try std.testing.expectEqual(@as(u64, 26), open_editor_key);
    try std.testing.expect(open_editor_key != open_terminal.open_terminal_key);
    try std.testing.expect(open_editor_key != reveal_folder.reveal_folder_key);
    try std.testing.expect(open_editor_key != pick_folder.pick_folder_key);
    try std.testing.expect(open_editor_key != attach.pick_image_key);
    try std.testing.expect(open_editor_key != maximize_window.maximize_window_key);
    try std.testing.expect(open_editor_key != copy.copy_turn_key);
    try std.testing.expect(open_editor_key != 3);
    try std.testing.expect(open_editor_key < 64);
}
