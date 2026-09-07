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
    if (keyboard.modifiers.hasNavigationModifier() and std.ascii.eqlIgnoreCase(keyboard.key, "o")) {
        // Cmd/Ctrl-O: selected-session pick_folder (Waku cmd-o NewProject
        // first-cut). Sets project_path via existing Pick folder.
        // Cmd/Ctrl-N stays New Task.
        return .pick_folder;
    }
    if (keyboard.modifiers.hasNavigationModifier() and std.ascii.eqlIgnoreCase(keyboard.key, "k")) {
        return .start_search;
    }
    if (keyboard.modifiers.hasNavigationModifier() and isSlashKey(keyboard.key)) {
        return .toggle_model_picker;
    }
    if (keyboard.modifiers.hasNavigationModifier() and std.ascii.eqlIgnoreCase(keyboard.key, "f")) {
        // Waku cmd-alt-f OpenFindReplace when Native exposes alt/option.
        // Missing alt field: the find-bar chevron still shows Replace.
        if (hasAltModifier(keyboard.modifiers) and !keyboard.modifiers.shift) {
            return .open_file_preview_find_replace;
        }
        return .open_find;
    }
    if (keyboard.modifiers.hasNavigationModifier() and std.ascii.eqlIgnoreCase(keyboard.key, "g")) {
        return if (keyboard.modifiers.shift) .find_prev else .find_next;
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
        // Cmd/Ctrl-B stays Toggle sidebar. Shift-B is Toggle right panel
        // (Waku secondary-b vs secondary-shift-b).
        if (keyboard.modifiers.shift) return .toggle_right_panel;
        return .toggle_sidebar;
    }
    if (keyboard.modifiers.hasNavigationModifier() and std.ascii.eqlIgnoreCase(keyboard.key, "c")) {
        return .copy_last_turn;
    }
    if (keyboard.modifiers.hasNavigationModifier() and std.ascii.eqlIgnoreCase(keyboard.key, "u")) {
        return .toggle_usage_meter;
    }
    if (keyboard.modifiers.hasNavigationModifier() and std.ascii.eqlIgnoreCase(keyboard.key, "s")) {
        // Waku `cmd-s` SaveFile / Files preview Save.
        return .file_preview_save;
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

/// Native `KeyboardModifiers` documents `alt` on some SDK cuts and
/// `option` on others. Comptime so a missing field is not invented.
fn hasAltModifier(modifiers: anytype) bool {
    const Mods = @TypeOf(modifiers);
    if (comptime @hasField(Mods, "alt")) {
        if (modifiers.alt) return true;
    }
    if (comptime @hasField(Mods, "option")) {
        if (modifiers.option) return true;
    }
    if (comptime @hasField(Mods, "alternate")) {
        if (modifiers.alternate) return true;
    }
    return false;
}
