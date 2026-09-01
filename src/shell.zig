//! Native shell window scene and chromeless app icon registration.
//!
//! `shell_scene` is the single-window chromeless shell (`hidden_inset_tall`)
//! that `UiApp.create` receives. `registerIcons` installs the minimize /
//! maximize / stop SVG table so markup `icon="app:minimize"` (and siblings)
//! resolve. Re-exported from `main.zig` so `UiApp` and tests keep
//! `main.shell_scene` / `main.registerIcons` / `main.app_icons` /
//! `main.main_window_label` / `main.window_width`. Behavior is unchanged
//! from the former `main` scene and icons.

const std = @import("std");
const native_sdk = @import("native_sdk");

const canvas = native_sdk.canvas;

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

/// One table feeds boot registration and the model contract so
/// `icon="app:minimize"` / `icon="app:maximize"` / `icon="app:stop"`
/// are verified against what `registerIcons` installs.
pub const app_icons = [_]canvas.icons.Entry{
    .{ .name = "minimize", .icon = &minimize_icon },
    .{ .name = "maximize", .icon = &maximize_icon },
    .{ .name = "stop", .icon = &stop_icon },
};

/// Install the app icon table once, before views build.
pub fn registerIcons() void {
    canvas.icons.registerAppIcons(&app_icons);
}

test "app_icons names and shell window" {
    try std.testing.expectEqual(@as(usize, 3), app_icons.len);
    try std.testing.expectEqualStrings("minimize", app_icons[0].name);
    try std.testing.expectEqualStrings("maximize", app_icons[1].name);
    try std.testing.expectEqualStrings("stop", app_icons[2].name);
    try std.testing.expectEqual(@as(usize, 1), shell_scene.windows.len);
    try std.testing.expectEqualStrings(main_window_label, shell_scene.windows[0].label);
}
