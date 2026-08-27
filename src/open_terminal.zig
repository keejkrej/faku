//! One-shot OS terminal-open sidecar.
//!
//! Native has no typed open-terminal effect. Open in Terminal therefore
//! `fx.spawn`s a documented host terminal at the selected session
//! `project_path`:
//!
//!   macOS:  `open -a Terminal PATH` (Terminal.app at that folder)
//!   Linux:  `x-terminal-emulator --working-directory=PATH`, else
//!           `gnome-terminal --working-directory=PATH`
//!   Windows: skipped (app.zon is macos/linux; no Windows spawn path)
//!
//! This is the second honest cut of Waku 0.1.11 "Open in.." — Terminal
//! only, not a full app picker, not a persisted `open_in_app`, and not
//! Waku's embedded right-panel terminal. Spawn stdin is unused
//! (write-once then close).

const std = @import("std");
const builtin = @import("builtin");
const native_sdk = @import("native_sdk");
const main = @import("main.zig");
const reveal_folder = @import("reveal_folder.zig");

const Model = main.Model;
const Effects = main.Effects;

/// Distinct from reveal_folder (28), pick_folder (29), maximize (30),
/// pick_image (31), copy_turn (32), attach_preview 33–63, fx_probe (3),
/// fx_spawn 64+, git_branch 200+. 27 sits in that gap and is unused by
/// those tables.
pub const open_terminal_key: u64 = 27;

pub const missing_exit: u8 = 2;

pub const linux_missing_status = "No OS terminal (install x-terminal-emulator).";
pub const macos_missing_status = "Terminal.app / open missing";
pub const windows_missing_status = "Open in Terminal is not available on Windows.";
pub const no_project_status = "No project folder for Terminal.";

pub const macos_bin = "open";
pub const macos_app_flag = "-a";
pub const macos_app = "Terminal";
pub const linux_first_bin = "x-terminal-emulator";
pub const linux_fallback_bin = "gnome-terminal";
pub const working_directory_prefix = "--working-directory=";

pub const Tool = enum { open_terminal, x_terminal_emulator, gnome_terminal };
pub const Stage = enum { first, fallback };

const argv_cap: usize = 4;
pub const wd_arg_len: usize = working_directory_prefix.len + main.max_project_path;

pub const ArgvScratch = struct {
    slots: [argv_cap][]const u8 = .{ "", "", "", "" },
    wd: [wd_arg_len]u8 = [_]u8{0} ** wd_arg_len,
};

pub fn hostTool(stage: Stage) ?Tool {
    return switch (builtin.os.tag) {
        .macos => if (stage == .first) .open_terminal else null,
        .linux => switch (stage) {
            .first => .x_terminal_emulator,
            .fallback => .gnome_terminal,
        },
        else => null,
    };
}

pub fn hostBin(stage: Stage) ?[]const u8 {
    return binFor(hostTool(stage) orelse return null);
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
        .open_terminal => macos_bin,
        .x_terminal_emulator => linux_first_bin,
        .gnome_terminal => linux_fallback_bin,
    };
}

pub fn argvForTool(tool: Tool, path: []const u8, scratch: *ArgvScratch) []const []const u8 {
    return switch (tool) {
        .open_terminal => {
            scratch.slots = .{ macos_bin, macos_app_flag, macos_app, path };
            return scratch.slots[0..4];
        },
        .x_terminal_emulator, .gnome_terminal => {
            const wd = writeWorkingDirectoryArg(path, &scratch.wd) orelse working_directory_prefix;
            scratch.slots[0] = binFor(tool);
            scratch.slots[1] = wd;
            return scratch.slots[0..2];
        },
    };
}

pub fn argvFor(stage: Stage, path: []const u8, scratch: *ArgvScratch) ?[]const []const u8 {
    return argvForTool(hostTool(stage) orelse return null, path, scratch);
}

pub fn writeWorkingDirectoryArg(path: []const u8, dest: *[wd_arg_len]u8) ?[]const u8 {
    return std.fmt.bufPrint(dest, "{s}{s}", .{ working_directory_prefix, path }) catch null;
}

pub fn isTerminalArgv(argv: []const []const u8) bool {
    if (argv.len == 4) {
        return std.mem.eql(u8, argv[0], macos_bin) and
            std.mem.eql(u8, argv[1], macos_app_flag) and
            std.mem.eql(u8, argv[2], macos_app);
    }
    if (argv.len == 2) {
        const bin_ok = std.mem.eql(u8, argv[0], linux_first_bin) or
            std.mem.eql(u8, argv[0], linux_fallback_bin);
        return bin_ok and std.mem.startsWith(u8, argv[1], working_directory_prefix);
    }
    return false;
}

/// Absolute existing selected-session directory. Hidden for Local /
/// empty / missing / relative / file paths. Reuses Reveal's resolver
/// so the spawn gate stays the same "openable path" cut.
pub fn canOpenTerminal(model: *const Model) bool {
    return reveal_folder.resolveRevealPath(model) != null;
}

pub fn resolveOpenPath(model: *const Model) ?[]const u8 {
    return reveal_folder.resolveRevealPath(model);
}

pub fn startOpenTerminal(model: *Model, fx: *Effects) void {
    if (model.open_terminal_live) return;
    const path = resolveOpenPath(model) orelse {
        model.setWindowStatus(no_project_status);
        return;
    };
    const tool = hostTool(.first) orelse {
        model.setWindowStatus(hostMissingStatus());
        return;
    };
    model.open_terminal_live = true;
    model.open_terminal_tried_fallback = false;
    model.clearWindowStatus();
    spawnTerminal(model, fx, tool, path);
}

fn spawnTerminal(model: *Model, fx: *Effects, tool: Tool, path: []const u8) void {
    var scratch: ArgvScratch = .{};
    const argv = switch (tool) {
        .open_terminal => argvForTool(tool, path, &scratch),
        .x_terminal_emulator, .gnome_terminal => blk: {
            const wd = writeWorkingDirectoryArg(path, &model.open_terminal_wd_storage) orelse {
                model.open_terminal_live = false;
                model.setWindowStatus(no_project_status);
                return;
            };
            model.open_terminal_wd_len = wd.len;
            scratch.slots[0] = binFor(tool);
            scratch.slots[1] = model.open_terminal_wd_storage[0..model.open_terminal_wd_len];
            break :blk scratch.slots[0..2];
        },
    };
    fx.spawn(.{
        .key = open_terminal_key,
        .argv = argv,
        .on_exit = Effects.exitMsg(.fx_exit),
    });
}

fn isMissingTerminalExit(exit: native_sdk.EffectExit) bool {
    if (exit.reason != .exited) return true;
    return exit.code == 127 or exit.code == missing_exit;
}

pub fn handleOpenTerminalExit(model: *Model, fx: *Effects, exit: native_sdk.EffectExit) void {
    if (isMissingTerminalExit(exit)) {
        if (!model.open_terminal_tried_fallback) {
            if (resolveOpenPath(model)) |path| {
                if (hostTool(.fallback)) |tool| {
                    model.open_terminal_tried_fallback = true;
                    spawnTerminal(model, fx, tool, path);
                    return;
                }
            }
        }
        if (!model.has_window_status()) {
            model.setWindowStatus(hostMissingStatus());
        }
    }
    model.open_terminal_live = false;
}

test "macos argv is open -a Terminal PATH" {
    var scratch: ArgvScratch = .{};
    const argv = argvForTool(.open_terminal, "/tmp/proj", &scratch);
    try std.testing.expectEqual(@as(usize, 4), argv.len);
    try std.testing.expectEqualStrings(macos_bin, argv[0]);
    try std.testing.expectEqualStrings(macos_app_flag, argv[1]);
    try std.testing.expectEqualStrings(macos_app, argv[2]);
    try std.testing.expectEqualStrings("/tmp/proj", argv[3]);
    try std.testing.expect(isTerminalArgv(argv));
}

test "linux first argv is x-terminal-emulator --working-directory=PATH" {
    var scratch: ArgvScratch = .{};
    const argv = argvForTool(.x_terminal_emulator, "/tmp/proj", &scratch);
    try std.testing.expectEqual(@as(usize, 2), argv.len);
    try std.testing.expectEqualStrings(linux_first_bin, argv[0]);
    try std.testing.expectEqualStrings("--working-directory=/tmp/proj", argv[1]);
    try std.testing.expect(isTerminalArgv(argv));
}

test "linux fallback argv is gnome-terminal --working-directory=PATH" {
    var scratch: ArgvScratch = .{};
    const argv = argvForTool(.gnome_terminal, "/tmp/proj", &scratch);
    try std.testing.expectEqual(@as(usize, 2), argv.len);
    try std.testing.expectEqualStrings(linux_fallback_bin, argv[0]);
    try std.testing.expectEqualStrings("--working-directory=/tmp/proj", argv[1]);
    try std.testing.expect(isTerminalArgv(argv));
}

test "host first argv is the platform terminal; Windows is skipped" {
    switch (builtin.os.tag) {
        .macos => {
            try std.testing.expectEqual(Tool.open_terminal, hostTool(.first).?);
            try std.testing.expect(hostTool(.fallback) == null);
            try std.testing.expectEqualStrings(macos_bin, hostBin(.first).?);
        },
        .linux => {
            try std.testing.expectEqual(Tool.x_terminal_emulator, hostTool(.first).?);
            try std.testing.expectEqual(Tool.gnome_terminal, hostTool(.fallback).?);
            try std.testing.expectEqualStrings(linux_first_bin, hostBin(.first).?);
            try std.testing.expectEqualStrings(linux_fallback_bin, hostBin(.fallback).?);
        },
        else => {
            try std.testing.expect(hostTool(.first) == null);
            try std.testing.expect(hostTool(.fallback) == null);
        },
    }
}

test "terminal argv is not reveal or folder-picker argv" {
    const pick_folder = @import("pick_folder.zig");
    var scratch: ArgvScratch = .{};
    var reveal_buf: [2][]const u8 = undefined;
    try std.testing.expect(!reveal_folder.isRevealArgv(argvForTool(.open_terminal, "/tmp/proj", &scratch)));
    try std.testing.expect(!reveal_folder.isRevealArgv(argvForTool(.x_terminal_emulator, "/tmp/proj", &scratch)));
    try std.testing.expect(!reveal_folder.isRevealArgv(argvForTool(.gnome_terminal, "/tmp/proj", &scratch)));
    try std.testing.expect(!pick_folder.isPickerArgv(argvForTool(.open_terminal, "/tmp/proj", &scratch)));
    try std.testing.expect(!pick_folder.isPickerArgv(argvForTool(.x_terminal_emulator, "/tmp/proj", &scratch)));
    try std.testing.expect(!pick_folder.isPickerArgv(argvForTool(.gnome_terminal, "/tmp/proj", &scratch)));
    try std.testing.expect(!isTerminalArgv(reveal_folder.argvFor("/tmp/proj", &reveal_buf)));
    try std.testing.expect(!isTerminalArgv(pick_folder.argvFor(.osascript)));
    try std.testing.expect(!isTerminalArgv(pick_folder.argvFor(.zenity)));
    try std.testing.expect(!isTerminalArgv(pick_folder.argvFor(.kdialog)));
}

test "open_terminal_key is 27 and distinct from reveal/pick neighbors" {
    const pick_folder = @import("pick_folder.zig");
    const attach = @import("attach.zig");
    const maximize_window = @import("maximize_window.zig");
    const copy = @import("copy.zig");
    try std.testing.expectEqual(@as(u64, 27), open_terminal_key);
    try std.testing.expect(open_terminal_key != reveal_folder.reveal_folder_key);
    try std.testing.expect(open_terminal_key != pick_folder.pick_folder_key);
    try std.testing.expect(open_terminal_key != attach.pick_image_key);
    try std.testing.expect(open_terminal_key != maximize_window.maximize_window_key);
    try std.testing.expect(open_terminal_key != copy.copy_turn_key);
    try std.testing.expect(open_terminal_key != 3);
    try std.testing.expect(open_terminal_key < 64);
}
