//! One-shot OS maximize/zoom sidecar.
//!
//! Native still has no `fx.maximizeWindow`. Chromeless Maximize therefore
//! `fx.spawn`s a documented OS window zoom and exits. Spawn stdin is unused
//! (write-once then close). This is not an invented Native window effect
//! and not a fake in-app size change.
//!
//! Spawn/exit orchestration (`startMaximizeWindow` / missing-exit
//! fallback / `handleMaximizeWindowExit`) lives here too. Native still
//! has none.
//!
//!   macOS:  osascript System Events `zoomed` on the Faku-named window
//!           of the frontmost process, else window 1 of that process.
//!           Exact script is `osascript_script` below.
//!   Linux:  wmctrl -r :ACTIVE: -b toggle,maximized_vert,maximized_horz
//!           else xdotool getactivewindow windowstate --add
//!           MAXIMIZED_VERT MAXIMIZED_HORZ
//!   Windows: skipped (app.zon is macos/linux; no Windows spawn path)

const std = @import("std");
const builtin = @import("builtin");
const native_sdk = @import("native_sdk");
const main = @import("main.zig");

const Model = main.Model;
const Effects = main.Effects;

/// One-shot OS maximize sidecar (`osascript` / `wmctrl` / `xdotool`).
/// Distinct from fx ask / daemon / picker / clipboard keys. Native
/// still has no `fx.maximizeWindow`; this spawn is the workaround.
pub const maximize_window_key: u64 = 30;

pub const missing_exit: u8 = 2;

pub const linux_missing_status = "No OS maximize (install wmctrl or xdotool).";
pub const macos_missing_status = "No OS maximize (osascript missing).";
pub const windows_missing_status = "Maximize is not available on Windows.";

pub const osascript_bin = "osascript";
/// System Events zoom (green-button maximize), not fullscreen.
/// Prefer the window whose name contains "Faku"; else zoom window 1 of
/// the frontmost process (this app after the header / key chord).
///
///   tell application "System Events"
///     tell (first application process whose frontmost is true)
///       if exists (first window whose name contains "Faku") then
///         set zoomed of (first window whose name contains "Faku") to true
///       else if exists window 1 then
///         set zoomed of window 1 to true
///       end if
///     end tell
///   end tell
pub const osascript_script = "tell application \"System Events\" to tell (first application process whose frontmost is true) to if exists (first window whose name contains \"Faku\") then set zoomed of (first window whose name contains \"Faku\") to true else if exists window 1 then set zoomed of window 1 to true";
pub const wmctrl_bin = "wmctrl";
pub const wmctrl_window = ":ACTIVE:";
pub const wmctrl_toggle = "toggle,maximized_vert,maximized_horz";
pub const xdotool_bin = "xdotool";
pub const xdotool_getactive = "getactivewindow";
pub const xdotool_windowstate = "windowstate";
pub const xdotool_add = "--add";
pub const xdotool_vert = "MAXIMIZED_VERT";
pub const xdotool_horz = "MAXIMIZED_HORZ";

pub const Tool = enum { osascript, wmctrl, xdotool };
pub const Stage = enum { first, fallback };

const osascript_argv = [_][]const u8{ osascript_bin, "-e", osascript_script };
const wmctrl_argv = [_][]const u8{ wmctrl_bin, "-r", wmctrl_window, "-b", wmctrl_toggle };
const xdotool_argv = [_][]const u8{ xdotool_bin, xdotool_getactive, xdotool_windowstate, xdotool_add, xdotool_vert, xdotool_horz };

pub fn argvFor(tool: Tool) []const []const u8 {
    return switch (tool) {
        .osascript => &osascript_argv,
        .wmctrl => &wmctrl_argv,
        .xdotool => &xdotool_argv,
    };
}

pub fn hostTool(stage: Stage) ?Tool {
    return switch (builtin.os.tag) {
        .macos => if (stage == .first) .osascript else null,
        .linux => switch (stage) {
            .first => .wmctrl,
            .fallback => .xdotool,
        },
        else => null,
    };
}

pub fn hostArgv(stage: Stage) ?[]const []const u8 {
    return argvFor(hostTool(stage) orelse return null);
}

pub fn hostMissingStatus() []const u8 {
    return switch (builtin.os.tag) {
        .macos => macos_missing_status,
        .windows => windows_missing_status,
        else => linux_missing_status,
    };
}

pub fn startMaximizeWindow(model: *Model, fx: *Effects) void {
    if (model.maximize_window_live) return;
    const argv = hostArgv(.first) orelse {
        model.setWindowStatus(hostMissingStatus());
        return;
    };
    model.maximize_window_live = true;
    model.maximize_window_tried_fallback = false;
    model.clearWindowStatus();
    fx.spawn(.{
        .key = maximize_window_key,
        .argv = argv,
        .on_exit = Effects.exitMsg(.fx_exit),
    });
}

fn isMissingMaximizeExit(exit: native_sdk.EffectExit) bool {
    if (exit.reason != .exited) return true;
    return exit.code == 127 or exit.code == missing_exit;
}

pub fn handleMaximizeWindowExit(model: *Model, fx: *Effects, exit: native_sdk.EffectExit) void {
    if (isMissingMaximizeExit(exit)) {
        if (!model.maximize_window_tried_fallback) {
            if (hostArgv(.fallback)) |argv| {
                model.maximize_window_tried_fallback = true;
                fx.spawn(.{
                    .key = maximize_window_key,
                    .argv = argv,
                    .on_exit = Effects.exitMsg(.fx_exit),
                });
                return;
            }
        }
        model.maximize_window_live = false;
        if (!model.has_window_status()) {
            model.setWindowStatus(hostMissingStatus());
        }
        return;
    }
    model.maximize_window_live = false;
}

pub fn isMaximizeArgv(argv: []const []const u8) bool {
    if (argv.len == 0) return false;
    if (std.mem.eql(u8, argv[0], osascript_bin)) {
        return argvHas(argv, "System Events") or argvHas(argv, "zoomed");
    }
    if (std.mem.eql(u8, argv[0], wmctrl_bin)) {
        return argvHas(argv, wmctrl_window) and argvHas(argv, wmctrl_toggle);
    }
    if (std.mem.eql(u8, argv[0], xdotool_bin)) {
        return argvHas(argv, xdotool_getactive) and argvHas(argv, xdotool_vert);
    }
    return false;
}

fn argvHas(argv: []const []const u8, needle: []const u8) bool {
    for (argv) |arg| {
        if (std.mem.eql(u8, arg, needle) or std.mem.indexOf(u8, arg, needle) != null) return true;
    }
    return false;
}

test "macos maximize argv is osascript System Events zoomed" {
    const argv = argvFor(.osascript);
    try std.testing.expectEqualStrings(osascript_bin, argv[0]);
    try std.testing.expect(argvHas(argv, "-e"));
    try std.testing.expect(argvHas(argv, "System Events"));
    try std.testing.expect(argvHas(argv, "zoomed"));
    try std.testing.expect(argvHas(argv, "Faku"));
    try std.testing.expect(argvHas(argv, "frontmost"));
    try std.testing.expect(isMaximizeArgv(argv));
}

test "linux wmctrl argv toggles maximized vert and horz on the active window" {
    const argv = argvFor(.wmctrl);
    try std.testing.expectEqualStrings(wmctrl_bin, argv[0]);
    try std.testing.expect(argvHas(argv, "-r"));
    try std.testing.expect(argvHas(argv, wmctrl_window));
    try std.testing.expect(argvHas(argv, "-b"));
    try std.testing.expect(argvHas(argv, wmctrl_toggle));
    try std.testing.expect(isMaximizeArgv(argv));
}

test "linux xdotool argv adds MAXIMIZED_VERT and MAXIMIZED_HORZ" {
    const argv = argvFor(.xdotool);
    try std.testing.expectEqualStrings(xdotool_bin, argv[0]);
    try std.testing.expect(argvHas(argv, xdotool_getactive));
    try std.testing.expect(argvHas(argv, xdotool_windowstate));
    try std.testing.expect(argvHas(argv, xdotool_add));
    try std.testing.expect(argvHas(argv, xdotool_vert));
    try std.testing.expect(argvHas(argv, xdotool_horz));
    try std.testing.expect(isMaximizeArgv(argv));
}

test "host first argv is the platform maximize tool; Windows is skipped" {
    switch (builtin.os.tag) {
        .macos => {
            try std.testing.expectEqual(Tool.osascript, hostTool(.first).?);
            try std.testing.expect(hostTool(.fallback) == null);
        },
        .linux => {
            try std.testing.expectEqual(Tool.wmctrl, hostTool(.first).?);
            try std.testing.expectEqual(Tool.xdotool, hostTool(.fallback).?);
        },
        else => {
            try std.testing.expect(hostTool(.first) == null);
            try std.testing.expect(hostTool(.fallback) == null);
        },
    }
}
