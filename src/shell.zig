//! Native shell window scene and chromeless + file-type app icon
//! registration.
//!
//! `shell_scene` is the single-window chromeless shell (`hidden_inset_tall`)
//! that `UiApp.create` receives. `registerIcons` installs one table:
//! minimize / maximize / stop / lock / globe plus the first-cut
//! Material file-type subset so markup `icon="app:minimize"` and bound
//! `app:zig` / `app:rust` / … resolve. Re-exported from `main.zig` so
//! `UiApp` and tests keep `main.shell_scene` / `main.registerIcons` /
//! `main.app_icons` / `main.main_window_label` / `main.window_width`.

const std = @import("std");
const native_sdk = @import("native_sdk");

const canvas = native_sdk.canvas;
const file_type_icons = @import("file_type_icons.zig");

/// Canvas view label for `UiApp.create`. Same spelling as `app.zon`
/// and `shell_views`. Not re-exported from `main`.
pub const canvas_label = "main-canvas";
/// Declared shell-window label. Chromeless close/minimize ride
/// `fx.closeWindow` / `fx.minimizeWindow` against this spelling —
/// same address as `app.zon` / the scene. Unknown label is a no-op.
/// Maximize is an OS sidecar (`maximize_window.zig`); Native still
/// has no `fx.maximizeWindow`.
pub const main_window_label = "main";
pub const window_width: f32 = 1380;
pub const window_height: f32 = 880;
pub const window_min_width: f32 = 560;
pub const window_min_height: f32 = 480;

const shell_views = [_]native_sdk.ShellView{
    .{ .label = canvas_label, .kind = .gpu_surface, .fill = true, .role = "Faku canvas", .accessibility_label = "Faku", .gpu_backend = .metal, .gpu_pixel_format = .bgra8_unorm, .gpu_present_mode = .timer, .gpu_alpha_mode = .@"opaque", .gpu_color_space = .srgb, .gpu_vsync = true },
    // Embedded Browser tab. `web_panes` snaps the **active** scene
    // webview to the markup `browser-pane` anchor (workbench pattern).
    // Four static views match Native `max_web_panes` (064ca989). Tiny
    // 1×1 frames are placeholders; unused / inactive / hidden / empty-history
    // slots park at 1×1 with no anchor.
    .{ .label = "browser-web-0", .kind = .webview, .parent = canvas_label, .url = "https://example.com", .x = 0, .y = 0, .width = 1, .height = 1, .layer = 20 },
    .{ .label = "browser-web-1", .kind = .webview, .parent = canvas_label, .url = "https://example.com", .x = 0, .y = 0, .width = 1, .height = 1, .layer = 20 },
    .{ .label = "browser-web-2", .kind = .webview, .parent = canvas_label, .url = "https://example.com", .x = 0, .y = 0, .width = 1, .height = 1, .layer = 20 },
    .{ .label = "browser-web-3", .kind = .webview, .parent = canvas_label, .url = "https://example.com", .x = 0, .y = 0, .width = 1, .height = 1, .layer = 20 },
};
const shell_windows = [_]native_sdk.ShellWindow{.{
    .label = main_window_label,
    .title = "Faku",
    .width = window_width,
    .height = window_height,
    .min_width = window_min_width,
    .min_height = window_min_height,
    .titlebar = .hidden_inset_tall,
    .views = &shell_views,
}};
pub const shell_scene: native_sdk.ShellConfig = .{ .windows = &shell_windows };

/// Chromeless Minimize bar. The built-in icon set has no minus
/// (`examples/deck`); Native check rejects an invented `icon="minus"`.
const minimize_icon = canvas.svg_icon.parseComptime(@embedFile("icons/minimize.svg"));

/// Chromeless Maximize square. Native has no `fx.maximizeWindow`
/// and no built-in maximize glyph.
const maximize_icon = canvas.svg_icon.parseComptime(@embedFile("icons/maximize.svg"));

/// Composer Stop square. Native has no built-in stop/square
/// (https://native-sdk.dev/components/icon).
const stop_icon = canvas.svg_icon.parseComptime(@embedFile("icons/stop.svg"));

/// Browser address lock. Native's curated set has no `lock`
/// (https://native-sdk.dev/docs/components/icon); `native check`
/// rejects a bare `icon name="lock"`.
const lock_icon = canvas.svg_icon.parseComptime(@embedFile("icons/lock.svg"));

/// Browser address globe (insecure / non-https). Same registry gap
/// as lock.
const globe_icon = canvas.svg_icon.parseComptime(@embedFile("icons/globe.svg"));

/// One table feeds boot registration and the model contract so chrome
/// `icon="app:minimize"` / `app:maximize` / `app:stop` / `app:lock` /
/// `app:globe` and Files/Diff/`@` `app:zig` / `app:rust` / … are
/// verified against what `registerIcons` installs.
const chrome_icons = [_]canvas.icons.Entry{
    .{ .name = "minimize", .icon = &minimize_icon },
    .{ .name = "maximize", .icon = &maximize_icon },
    .{ .name = "stop", .icon = &stop_icon },
    .{ .name = "lock", .icon = &lock_icon },
    .{ .name = "globe", .icon = &globe_icon },
};
pub const app_icons = chrome_icons ++ file_type_icons.app_icons;

/// Install the app icon table once, before views build.
pub fn registerIcons() void {
    canvas.icons.registerAppIcons(&app_icons);
}

test "registerIcons resolves chrome and file-type app names" {
    registerIcons();
    try std.testing.expect(canvas.icons.resolve("app:minimize") != null);
    try std.testing.expect(canvas.icons.resolve("app:zig") != null);
    try std.testing.expect(canvas.icons.resolve("app:rust") != null);
    try std.testing.expect(canvas.icons.resolve("app:react") != null);
    try std.testing.expect(canvas.icons.resolve("app:git") != null);
    try std.testing.expect(canvas.icons.find("app:zig") == null);
}

test "app_icons names and shell window" {
    try std.testing.expectEqual(@as(usize, chrome_icons.len + file_type_icons.app_icons.len), app_icons.len);
    try std.testing.expectEqual(@as(usize, 5), chrome_icons.len);
    try std.testing.expectEqualStrings("minimize", app_icons[0].name);
    try std.testing.expectEqualStrings("maximize", app_icons[1].name);
    try std.testing.expectEqualStrings("stop", app_icons[2].name);
    try std.testing.expectEqualStrings("lock", app_icons[3].name);
    try std.testing.expectEqualStrings("globe", app_icons[4].name);
    try std.testing.expectEqualStrings("zig", app_icons[5].name);
    try std.testing.expectEqualStrings("git", app_icons[app_icons.len - 1].name);
    try std.testing.expectEqual(@as(usize, 1), shell_scene.windows.len);
    try std.testing.expectEqualStrings(main_window_label, shell_scene.windows[0].label);
    try std.testing.expectEqual(@as(usize, 5), shell_scene.windows[0].views.len);
    try std.testing.expectEqualStrings(canvas_label, shell_scene.windows[0].views[0].label);
    try std.testing.expectEqualStrings("browser-web-0", shell_scene.windows[0].views[1].label);
    try std.testing.expect(shell_scene.windows[0].views[1].kind == .webview);
    try std.testing.expectEqualStrings(canvas_label, shell_scene.windows[0].views[1].parent.?);
    try std.testing.expectEqualStrings("browser-web-3", shell_scene.windows[0].views[4].label);
    try std.testing.expect(shell_scene.windows[0].views[4].kind == .webview);
}
