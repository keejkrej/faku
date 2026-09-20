//! Native shell window scene and chromeless + file-type app icon
//! registration.
//!
//! `shell_scene` is the single-window chromeless shell (`hidden_inset_tall`)
//! that `UiApp.create` receives. `registerIcons` installs one table:
//! minimize / maximize / stop / lock / globe / appearance / bot /
//! package / chart-column / cursor-spark, Settings Providers brand
//! marks (`app:provider-*`), plus the Material file-type subset so
//! markup `icon="app:minimize"` and bound `app:zig` / `app:rust` /
//! `app:ruby` / `app:provider-fx` / … resolve. Callers import this
//! module directly (`shell.shell_scene` / `shell.registerIcons` /
//! `shell.app_icons` / `shell.main_window_label` / `shell.window_width`).
//! Native `native check` still requires `pub const app_icons` on the
//! app root, so `main` keeps that one-line re-export for the model
//! contract.

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

/// Settings Appearance (Waku `icons/appearance.svg`). Native has no
/// built-in half-moon appearance glyph.
const appearance_icon = canvas.svg_icon.parseComptime(@embedFile("icons/appearance.svg"));

/// Settings Providers (Waku `icons/bot.svg`). Native has no built-in
/// bot glyph.
const bot_icon = canvas.svg_icon.parseComptime(@embedFile("icons/bot.svg"));

/// Settings Skills (Waku `icons/package.svg`). Native has no built-in
/// package glyph.
const package_icon = canvas.svg_icon.parseComptime(@embedFile("icons/package.svg"));

/// Settings Usage (Waku `icons/chart-column.svg`). Native has no
/// built-in chart-column glyph.
const chart_column_icon = canvas.svg_icon.parseComptime(@embedFile("icons/chart-column.svg"));

/// Settings Daemon (Waku `icons/server.svg`). Native has no built-in
/// server glyph. Stroke `#000` became `currentColor`.
const server_icon = canvas.svg_icon.parseComptime(@embedFile("icons/server.svg"));

/// Settings Computer Use (Waku `icons/cursor-spark.svg`). Native has
/// no built-in cursor-spark glyph.
const cursor_spark_icon = canvas.svg_icon.parseComptime(@embedFile("icons/cursor-spark.svg"));

fn parseProvider(comptime name: []const u8) canvas.svg_icon.Icon {
    return canvas.svg_icon.parseComptime(@embedFile("icons/provider-" ++ name ++ ".svg"));
}

/// Settings Providers row marks (Waku `icons/provider-*.svg`).
/// Codex uses the OpenAI mark (`provider-openai.svg`).
const provider_fx_icon = parseProvider("fx");
const provider_claude_icon = parseProvider("claude");
const provider_openai_icon = parseProvider("openai");
const provider_cursor_icon = parseProvider("cursor");
const provider_amp_icon = parseProvider("amp");
const provider_grok_icon = parseProvider("grok");
const provider_opencode_icon = parseProvider("opencode");
const provider_pi_icon = parseProvider("pi");
const provider_kimi_icon = parseProvider("kimi");
const provider_ohmypi_icon = parseProvider("ohmypi");
const provider_opencode2_icon = parseProvider("opencode2");
const provider_deepseek_icon = parseProvider("deepseek");

/// One table feeds boot registration and the model contract so chrome
/// `icon="app:minimize"` / `app:maximize` / `app:stop` / `app:lock` /
/// `app:globe` / `app:appearance` / `app:bot` / `app:package` /
/// `app:chart-column` / `app:server` / `app:cursor-spark`, Providers
/// `app:provider-fx` / `app:provider-claude` / `app:provider-openai` /
/// … and Files/Diff/`@` `app:zig` / `app:rust` / … are verified
/// against what `registerIcons` installs.
const chrome_icons = [_]canvas.icons.Entry{
    .{ .name = "minimize", .icon = &minimize_icon },
    .{ .name = "maximize", .icon = &maximize_icon },
    .{ .name = "stop", .icon = &stop_icon },
    .{ .name = "lock", .icon = &lock_icon },
    .{ .name = "globe", .icon = &globe_icon },
    .{ .name = "appearance", .icon = &appearance_icon },
    .{ .name = "bot", .icon = &bot_icon },
    .{ .name = "package", .icon = &package_icon },
    .{ .name = "chart-column", .icon = &chart_column_icon },
    .{ .name = "server", .icon = &server_icon },
    .{ .name = "cursor-spark", .icon = &cursor_spark_icon },
};
const providers_icons = [_]canvas.icons.Entry{
    .{ .name = "provider-fx", .icon = &provider_fx_icon },
    .{ .name = "provider-claude", .icon = &provider_claude_icon },
    .{ .name = "provider-openai", .icon = &provider_openai_icon },
    .{ .name = "provider-cursor", .icon = &provider_cursor_icon },
    .{ .name = "provider-amp", .icon = &provider_amp_icon },
    .{ .name = "provider-grok", .icon = &provider_grok_icon },
    .{ .name = "provider-opencode", .icon = &provider_opencode_icon },
    .{ .name = "provider-pi", .icon = &provider_pi_icon },
    .{ .name = "provider-kimi", .icon = &provider_kimi_icon },
    .{ .name = "provider-ohmypi", .icon = &provider_ohmypi_icon },
    .{ .name = "provider-opencode2", .icon = &provider_opencode2_icon },
    .{ .name = "provider-deepseek", .icon = &provider_deepseek_icon },
};
pub const app_icons = chrome_icons ++ providers_icons ++ file_type_icons.app_icons;

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
    try std.testing.expect(canvas.icons.resolve("app:ruby") != null);
    try std.testing.expect(canvas.icons.resolve("app:svg") != null);
    try std.testing.expect(canvas.icons.resolve("app:webassembly") != null);
    try std.testing.expect(canvas.icons.resolve("app:bun") != null);
    try std.testing.expect(canvas.icons.resolve("app:console") != null);
    try std.testing.expect(canvas.icons.resolve("app:webpack") != null);
    try std.testing.expect(canvas.icons.resolve("app:next") != null);
    try std.testing.expect(canvas.icons.resolve("app:stylelint") != null);
    try std.testing.expect(canvas.icons.resolve("app:zip") != null);
    try std.testing.expect(canvas.icons.resolve("app:audio") != null);
    try std.testing.expect(canvas.icons.resolve("app:video") != null);
    try std.testing.expect(canvas.icons.resolve("app:settings") != null);
    try std.testing.expect(canvas.icons.resolve("app:certificate") != null);
    try std.testing.expect(canvas.icons.resolve("app:lock") != null);
    try std.testing.expect(canvas.icons.resolve("app:appearance") != null);
    try std.testing.expect(canvas.icons.resolve("app:bot") != null);
    try std.testing.expect(canvas.icons.resolve("app:package") != null);
    try std.testing.expect(canvas.icons.resolve("app:chart-column") != null);
    try std.testing.expect(canvas.icons.resolve("app:server") != null);
    try std.testing.expect(canvas.icons.resolve("app:cursor-spark") != null);
    try std.testing.expect(canvas.icons.resolve("app:provider-fx") != null);
    try std.testing.expect(canvas.icons.resolve("app:provider-claude") != null);
    try std.testing.expect(canvas.icons.resolve("app:provider-openai") != null);
    try std.testing.expect(canvas.icons.resolve("app:provider-cursor") != null);
    try std.testing.expect(canvas.icons.resolve("app:provider-amp") != null);
    try std.testing.expect(canvas.icons.resolve("app:provider-grok") != null);
    try std.testing.expect(canvas.icons.resolve("app:provider-opencode") != null);
    try std.testing.expect(canvas.icons.resolve("app:provider-pi") != null);
    try std.testing.expect(canvas.icons.resolve("app:provider-kimi") != null);
    try std.testing.expect(canvas.icons.resolve("app:provider-ohmypi") != null);
    try std.testing.expect(canvas.icons.resolve("app:provider-opencode2") != null);
    try std.testing.expect(canvas.icons.resolve("app:provider-deepseek") != null);
    try std.testing.expect(canvas.icons.resolve("app:lockfile") != null);
    try std.testing.expect(canvas.icons.resolve("app:exe") != null);
    try std.testing.expect(canvas.icons.resolve("app:nginx") != null);
    try std.testing.expect(canvas.icons.resolve("app:cmake") != null);
    try std.testing.expect(canvas.icons.resolve("app:coffee") != null);
    try std.testing.expect(canvas.icons.resolve("app:gitlab") != null);
    try std.testing.expect(canvas.icons.resolve("app:gradle") != null);
    try std.testing.expect(canvas.icons.resolve("app:kubernetes") != null);
    try std.testing.expect(canvas.icons.resolve("app:tex") != null);
    try std.testing.expect(canvas.icons.resolve("app:crystal") != null);
    try std.testing.expect(canvas.icons.resolve("app:elm") != null);
    try std.testing.expect(canvas.icons.resolve("app:erlang") != null);
    try std.testing.expect(canvas.icons.resolve("app:haxe") != null);
    try std.testing.expect(canvas.icons.resolve("app:jinja") != null);
    try std.testing.expect(canvas.icons.resolve("app:xaml") != null);
    try std.testing.expect(canvas.icons.resolve("app:diff") != null);
    try std.testing.expect(canvas.icons.resolve("app:file") != null);
    try std.testing.expect(canvas.icons.resolve("app:julia") != null);
    try std.testing.expect(canvas.icons.resolve("app:prettier") != null);
    try std.testing.expect(canvas.icons.resolve("app:kotlin") != null);
    try std.testing.expect(canvas.icons.resolve("app:clojure") != null);
    try std.testing.expect(canvas.icons.resolve("app:helm") != null);
    try std.testing.expect(canvas.icons.resolve("app:editorconfig") != null);
    try std.testing.expect(canvas.icons.resolve("app:graphql") != null);
    try std.testing.expect(canvas.icons.resolve("app:nest") != null);
    try std.testing.expect(canvas.icons.resolve("app:pug") != null);
    try std.testing.expect(canvas.icons.find("app:zig") == null);
}

test "app_icons names and shell window" {
    try std.testing.expectEqual(@as(usize, chrome_icons.len + providers_icons.len + file_type_icons.app_icons.len), app_icons.len);
    try std.testing.expectEqual(@as(usize, 11), chrome_icons.len);
    try std.testing.expectEqual(@as(usize, 12), providers_icons.len);
    try std.testing.expectEqualStrings("minimize", app_icons[0].name);
    try std.testing.expectEqualStrings("maximize", app_icons[1].name);
    try std.testing.expectEqualStrings("stop", app_icons[2].name);
    try std.testing.expectEqualStrings("lock", app_icons[3].name);
    try std.testing.expectEqualStrings("globe", app_icons[4].name);
    try std.testing.expectEqualStrings("appearance", app_icons[5].name);
    try std.testing.expectEqualStrings("bot", app_icons[6].name);
    try std.testing.expectEqualStrings("package", app_icons[7].name);
    try std.testing.expectEqualStrings("chart-column", app_icons[8].name);
    try std.testing.expectEqualStrings("server", app_icons[9].name);
    try std.testing.expectEqualStrings("cursor-spark", app_icons[10].name);
    try std.testing.expectEqualStrings("provider-fx", app_icons[11].name);
    try std.testing.expectEqualStrings("provider-claude", app_icons[12].name);
    try std.testing.expectEqualStrings("provider-openai", app_icons[13].name);
    try std.testing.expectEqualStrings("provider-cursor", app_icons[14].name);
    try std.testing.expectEqualStrings("provider-amp", app_icons[15].name);
    try std.testing.expectEqualStrings("provider-grok", app_icons[16].name);
    try std.testing.expectEqualStrings("provider-opencode", app_icons[17].name);
    try std.testing.expectEqualStrings("provider-pi", app_icons[18].name);
    try std.testing.expectEqualStrings("provider-kimi", app_icons[19].name);
    try std.testing.expectEqualStrings("provider-ohmypi", app_icons[20].name);
    try std.testing.expectEqualStrings("provider-opencode2", app_icons[21].name);
    try std.testing.expectEqualStrings("provider-deepseek", app_icons[22].name);
    try std.testing.expectEqualStrings("zig", app_icons[23].name);
    try std.testing.expectEqualStrings("file", app_icons[app_icons.len - 1].name);
    for (providers_icons) |entry| {
        try std.testing.expect(entry.icon.shapes.len > 0);
    }
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

test "app_icons chrome and file-type names are unique" {
    var i: usize = 0;
    while (i < app_icons.len) : (i += 1) {
        var j: usize = i + 1;
        while (j < app_icons.len) : (j += 1) {
            try std.testing.expect(!std.mem.eql(u8, app_icons[i].name, app_icons[j].name));
        }
    }
}
