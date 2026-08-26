//! Keyboard dispatch: `WidgetKeyboardEvent` → `Msg`.
//!
//! Chord matching and Cmd/Ctrl mappings live here. `Msg` stays in
//! `main.zig`. Behavior is unchanged from the former `main.onKey`.

const std = @import("std");
const native_sdk = @import("native_sdk");
const main = @import("main.zig");

const canvas = native_sdk.canvas;
const Msg = main.Msg;

pub fn onKey(keyboard: canvas.WidgetKeyboardEvent) ?Msg {
    if (std.ascii.eqlIgnoreCase(keyboard.key, "escape")) return .stop;
    // Control-Tab is the session switcher on every platform. Cmd-Tab
    // stays with the OS app switcher — do not use hasNavigationModifier.
    if (std.ascii.eqlIgnoreCase(keyboard.key, "tab")) {
        if (keyboard.modifiers.control and !keyboard.modifiers.super) {
            return if (keyboard.modifiers.shift) .switcher_backward else .switcher_forward;
        }
        return null;
    }
    if (keyboard.modifiers.hasNavigationModifier() and std.ascii.eqlIgnoreCase(keyboard.key, "n")) {
        return .new_session;
    }
    if (keyboard.modifiers.hasNavigationModifier() and std.ascii.eqlIgnoreCase(keyboard.key, "k")) {
        return .start_search;
    }
    if (keyboard.modifiers.hasNavigationModifier() and isSlashKey(keyboard.key)) {
        return .toggle_model_picker;
    }
    if (keyboard.modifiers.hasNavigationModifier() and std.ascii.eqlIgnoreCase(keyboard.key, "f")) {
        return .open_find;
    }
    if (keyboard.modifiers.hasNavigationModifier() and std.ascii.eqlIgnoreCase(keyboard.key, "l")) {
        return .focus_composer;
    }
    if (keyboard.modifiers.hasNavigationModifier() and std.ascii.eqlIgnoreCase(keyboard.key, "m")) {
        // Cmd/Ctrl-M stays Minimize. Shift-M is Maximize so the
        // chromeless zoom sidecar does not steal minimize.
        if (keyboard.modifiers.shift) return .maximize_window;
        return .minimize_window;
    }
    if (keyboard.modifiers.hasNavigationModifier() and std.ascii.eqlIgnoreCase(keyboard.key, "w")) {
        return .close_window;
    }
    if (keyboard.modifiers.hasNavigationModifier() and std.ascii.eqlIgnoreCase(keyboard.key, "q")) {
        return .quit_app;
    }
    if (keyboard.modifiers.hasNavigationModifier() and std.ascii.eqlIgnoreCase(keyboard.key, "b")) {
        return .toggle_sidebar;
    }
    if (keyboard.modifiers.hasNavigationModifier() and std.ascii.eqlIgnoreCase(keyboard.key, "c")) {
        return .copy_last_turn;
    }
    if (keyboard.modifiers.hasNavigationModifier() and std.mem.eql(u8, keyboard.key, ",")) {
        return .toggle_settings;
    }
    if (keyboard.modifiers.hasNavigationModifier() and std.mem.eql(u8, keyboard.key, "[")) {
        return .history_back;
    }
    if (keyboard.modifiers.hasNavigationModifier() and std.mem.eql(u8, keyboard.key, "]")) {
        return .history_forward;
    }
    if (keyboard.modifiers.hasNavigationModifier() and isEnterKey(keyboard.key)) {
        return .steer;
    }
    return null;
}

fn isEnterKey(key: []const u8) bool {
    return std.ascii.eqlIgnoreCase(key, "enter") or std.ascii.eqlIgnoreCase(key, "return");
}

fn isSlashKey(key: []const u8) bool {
    return std.mem.eql(u8, key, "/") or std.ascii.eqlIgnoreCase(key, "slash");
}
