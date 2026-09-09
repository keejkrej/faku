//! Keyboard dispatch: `WidgetKeyboardEvent` → `Msg`.
//!
//! Chord matching and Cmd/Ctrl mappings live here. `Msg` stays in
//! `main.zig`. Behavior is unchanged from the former `main.onKey`.
//! Files preview find: Waku `secondary-alt-c` / `w` / `r` toggles and
//! `secondary-alt-enter` ReplaceAllMatches when Native exposes alt/option.
//! Enter in a find `search-field` is FindNext via Native `on-submit`
//! (not a global bind). Shift-Enter FindPrevious stays unbound
//! (`onKey` has no focus/model; composer Shift-Enter newline).
//! Prev remains the chevron / Cmd-Shift-G.
//! Browser first-cut: Cmd/Ctrl-R/L/[/] emit model-gated Msgs (`onKey`
//! has no focus). Escape stays `.stop`; handleStop restores the
//! address draft when that field is active (Waku BrowserAddressCancel).
//! Hard Reload / DevTools / loading Stop stay unbound.

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
        // Waku Browser `secondary-l` FocusBrowserAddress when the
        // Browser tab is showing. `onKey` has no model; update routes
        // to the address field or today's Focus composer.
        return .focus_browser_or_composer;
    }
    if (keyboard.modifiers.hasNavigationModifier() and std.ascii.eqlIgnoreCase(keyboard.key, "m")) {
        // Cmd/Ctrl-M stays Minimize. Shift-M is Maximize so the
        // chromeless zoom sidecar does not steal minimize.
        if (keyboard.modifiers.shift) return .maximize_window;
        return .minimize_window;
    }
    if (keyboard.modifiers.hasNavigationModifier() and std.ascii.eqlIgnoreCase(keyboard.key, "w")) {
        // Waku secondary-alt-w ToggleFindWholeWord. Cmd/Ctrl-W stays
        // close_window when alt is not held. Handler no-ops if find is inactive.
        if (hasAltModifier(keyboard.modifiers) and !keyboard.modifiers.shift) {
            return .toggle_file_preview_find_whole_word;
        }
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
        // Waku secondary-alt-c ToggleFindCaseSensitive. Cmd/Ctrl-C stays
        // copy_last_turn when alt is not held. Handler no-ops if find is inactive.
        if (hasAltModifier(keyboard.modifiers) and !keyboard.modifiers.shift) {
            return .toggle_file_preview_find_case;
        }
        return .copy_last_turn;
    }
    if (keyboard.modifiers.hasNavigationModifier() and std.ascii.eqlIgnoreCase(keyboard.key, "u")) {
        return .toggle_usage_meter;
    }
    if (keyboard.modifiers.hasNavigationModifier() and std.ascii.eqlIgnoreCase(keyboard.key, "r")) {
        // Waku secondary-alt-r ToggleFindRegex. Bare Cmd/Ctrl-R is
        // BrowserReload (handler no-ops unless the Browser tab is the
        // active right-panel surface). Cmd/Ctrl-Shift-R Hard Reload
        // stays unbound (Native `web_panes` has no hard-reload API).
        if (hasAltModifier(keyboard.modifiers) and !keyboard.modifiers.shift) {
            return .toggle_file_preview_find_regex;
        }
        if (!keyboard.modifiers.shift) return .browser_reload;
    }
    if (keyboard.modifiers.hasNavigationModifier() and std.ascii.eqlIgnoreCase(keyboard.key, "s")) {
        // Waku `cmd-s` SaveFile / Files preview Save.
        return .file_preview_save;
    }
    if (keyboard.modifiers.hasNavigationModifier() and std.mem.eql(u8, keyboard.key, ",")) {
        return .toggle_settings;
    }
    if (keyboard.modifiers.hasNavigationModifier() and std.mem.eql(u8, keyboard.key, "[")) {
        // Waku Browser `secondary-[` BrowserBack when the Browser tab
        // is showing; else today's palette/session history back.
        // Sidebar Back stays `history_back`.
        return .navigate_back;
    }
    if (keyboard.modifiers.hasNavigationModifier() and std.mem.eql(u8, keyboard.key, "]")) {
        return .navigate_forward;
    }
    if (keyboard.modifiers.hasNavigationModifier() and isEnterKey(keyboard.key)) {
        // Waku secondary-alt-enter ReplaceAllMatches. Cmd/Ctrl-Enter stays
        // steer when alt is not held. Enter in the find field is FindNext
        // via search-field `on-submit` in app.native, not this global bind.
        // Shift-Enter FindPrevious is unbound: onKey has no focus/model, so
        // Native cannot scope it to the find bar without stealing composer
        // Shift-Enter newline. Prev remains the chevron / Cmd-Shift-G.
        if (hasAltModifier(keyboard.modifiers) and !keyboard.modifiers.shift) {
            return .file_preview_find_replace_all;
        }
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
