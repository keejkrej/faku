//! First-cut embedded right-panel Browser: Native canvas `web_panes`.
//!
//! Canvas-first apps declare a scene `.webview` parented to the gpu_surface
//! and drive it with `UiApp.Options.web_panes` (workbench / canvas-preview
//! at vercel-labs/native @ 064ca989). This is not a markup `<webview>`
//! tag and not Waku BrowserView (tabs, DevTools, multi-session, UA spoof).
//!
//! Pane URL is the committed history entry, never the address-bar draft.
//! `sessions.json` extras still persist that draft (`browser_url`); history,
//! back/forward, and `reload_token` are runtime-only. Empty history uses
//! the scene placeholder `https://example.com` until Navigate/Enter.
//!
//! Native `applyWebPane` keeps the last frame when the anchor is missing
//! or width/height < 1 (`ui_app.zig`). Public `WebViewPane` has no
//! `visible` field. When the Browser tab is hidden, this module still
//! returns one pane with `anchor = null` and a 1×1 frame at (0,0) so the
//! webview parks off the Files/Diff/Terminal content.

const std = @import("std");
const native_sdk = @import("native_sdk");
const model_mod = @import("model.zig");
const open_url = @import("open_url.zig");

const canvas = native_sdk.canvas;
const geometry = native_sdk.geometry;

const Model = model_mod.Model;
const Msg = model_mod.Msg;

const FakuApp = native_sdk.UiApp(Model, Msg);
pub const WebViewPane = FakuApp.WebViewPane;

/// Scene `.webview` label. Same spelling as `app.zon` / `app.json` /
/// `shell.zig`.
pub const web_view_label = "browser-web";
/// Markup semantics label the pane snaps to (`<column label="browser-pane">`).
pub const web_pane_anchor = "browser-pane";
/// Scene placeholder and empty-history pane URL.
pub const home_url = "https://example.com";
/// Workbench `max_history` ring. Runtime-only.
pub const max_history = 32;
/// Parking frame: positive size so `applyWebPane` does not keep the last
/// content-sized snapshot when the Browser tab is hidden.
pub const parked_frame = geometry.RectF.init(0, 0, 1, 1);

pub fn currentUrl(model: *const Model) []const u8 {
    if (model.browser_history_count == 0) return home_url;
    return model.browser_history[model.browser_history_index].text();
}

pub fn backDisabled(model: *const Model) bool {
    return model.browser_history_index == 0;
}

pub fn forwardDisabled(model: *const Model) bool {
    return model.browser_history_count == 0 or model.browser_history_index + 1 >= model.browser_history_count;
}

/// Commit the address-bar draft: normalize (bare host → `https://`),
/// drop the forward tail, append, and point the pane at it. Empty /
/// overflow is a no-op (history unchanged).
pub fn commitNavigation(model: *Model) void {
    var normalized: [open_url.max_spawn_url]u8 = undefined;
    const url = open_url.normalizeUrl(model.browser_url(), &normalized) orelse return;
    if (model.browser_history_count > 0) {
        model.browser_history_index += 1;
    }
    if (model.browser_history_index >= max_history) {
        std.mem.copyForwards(
            canvas.TextBuffer(open_url.max_spawn_url),
            model.browser_history[0 .. max_history - 1],
            model.browser_history[1..max_history],
        );
        model.browser_history_index = max_history - 1;
    }
    model.browser_history[model.browser_history_index].set(url);
    model.browser_history_count = model.browser_history_index + 1;
    model.browser_url_buffer.set(url);
}

pub fn goBack(model: *Model) void {
    if (model.browser_history_index == 0) return;
    model.browser_history_index -= 1;
    model.browser_url_buffer.set(model.browser_history[model.browser_history_index].text());
}

pub fn goForward(model: *Model) void {
    if (model.browser_history_count == 0 or model.browser_history_index + 1 >= model.browser_history_count) return;
    model.browser_history_index += 1;
    model.browser_url_buffer.set(model.browser_history[model.browser_history_index].text());
}

pub fn reload(model: *Model) void {
    model.browser_reload_token +%= 1;
}

/// Model-derived webview panes. Always one pane (the scene webview).
/// Hidden Browser parks at 1×1 with no anchor so Native does not keep
/// the last content frame over Files/Diff/Terminal.
pub fn webPanes(model: *const Model, out: []WebViewPane) usize {
    const showing = model.right_panel_showing_browser();
    out[0] = .{
        .label = web_view_label,
        .anchor = if (showing) web_pane_anchor else null,
        .frame = if (showing) geometry.RectF.init(0, 0, 0, 0) else parked_frame,
        .url = currentUrl(model),
        .reload_token = model.browser_reload_token,
    };
    return 1;
}

test "web_panes label and anchor constants match the scene placeholder" {
    try std.testing.expectEqualStrings("browser-web", web_view_label);
    try std.testing.expectEqualStrings("browser-pane", web_pane_anchor);
    try std.testing.expectEqualStrings("https://example.com", home_url);
    try std.testing.expectEqual(@as(usize, 32), max_history);
    try std.testing.expectEqual(max_history, @typeInfo(@FieldType(Model, "browser_history")).array.len);
    try std.testing.expectEqualStrings(web_view_label, @import("shell.zig").shell_scene.windows[0].views[1].label);
    try std.testing.expectEqualStrings(home_url, @import("shell.zig").shell_scene.windows[0].views[1].url.?);
    try std.testing.expectEqual(@as(f32, 1), parked_frame.width);
    try std.testing.expectEqual(@as(f32, 1), parked_frame.height);
    try std.testing.expectEqual(@as(f32, 0), parked_frame.x);
    try std.testing.expectEqual(@as(f32, 0), parked_frame.y);
}

test "hidden Browser parks a 1x1 pane with no anchor; showing snaps to browser-pane" {
    var model: Model = .{};
    var panes: [1]WebViewPane = undefined;

    try std.testing.expect(!model.right_panel_showing_browser());
    try std.testing.expectEqual(@as(usize, 1), webPanes(&model, &panes));
    try std.testing.expectEqualStrings(web_view_label, panes[0].label);
    try std.testing.expect(panes[0].anchor == null);
    try std.testing.expectEqual(@as(f32, 0), panes[0].frame.x);
    try std.testing.expectEqual(@as(f32, 0), panes[0].frame.y);
    try std.testing.expectEqual(@as(f32, 1), panes[0].frame.width);
    try std.testing.expectEqual(@as(f32, 1), panes[0].frame.height);
    try std.testing.expectEqualStrings(home_url, panes[0].url);
    try std.testing.expectEqual(@as(u64, 0), panes[0].reload_token);

    model.right_panel_open = true;
    model.right_panel_tab = .files;
    _ = webPanes(&model, &panes);
    try std.testing.expect(panes[0].anchor == null);
    try std.testing.expectEqual(@as(f32, 1), panes[0].frame.width);

    model.right_panel_tab = .browser;
    try std.testing.expect(model.right_panel_showing_browser());
    _ = webPanes(&model, &panes);
    try std.testing.expectEqualStrings(web_pane_anchor, panes[0].anchor orelse "");
    try std.testing.expectEqualStrings(home_url, panes[0].url);
}

test "address keystrokes do not navigate; Enter/Navigate commits a normalized URL" {
    var model: Model = .{};
    var panes: [1]WebViewPane = undefined;

    model.browser_url_buffer.set("  example.com/path  ");
    _ = webPanes(&model, &panes);
    try std.testing.expectEqualStrings(home_url, panes[0].url);
    try std.testing.expectEqualStrings("  example.com/path  ", model.browser_url());

    commitNavigation(&model);
    _ = webPanes(&model, &panes);
    try std.testing.expectEqualStrings("https://example.com/path", panes[0].url);
    try std.testing.expectEqualStrings("https://example.com/path", model.browser_url());
    try std.testing.expectEqualStrings("https://example.com/path", currentUrl(&model));
    try std.testing.expect(backDisabled(&model));
    try std.testing.expect(forwardDisabled(&model));

    model.browser_url_buffer.set("http://localhost:3000");
    commitNavigation(&model);
    _ = webPanes(&model, &panes);
    try std.testing.expectEqualStrings("http://localhost:3000", panes[0].url);
    try std.testing.expect(!backDisabled(&model));
    try std.testing.expect(forwardDisabled(&model));
}

test "empty navigate is a no-op; overflow-normalize is a no-op" {
    var model: Model = .{};
    commitNavigation(&model);
    try std.testing.expectEqual(@as(usize, 0), model.browser_history_count);
    try std.testing.expectEqualStrings(home_url, currentUrl(&model));

    model.browser_url_buffer.set("   \t  ");
    commitNavigation(&model);
    try std.testing.expectEqual(@as(usize, 0), model.browser_history_count);
}

test "back and forward walk the app-owned history; a new navigation drops the tail" {
    var model: Model = .{};

    model.browser_url_buffer.set("https://a.example");
    commitNavigation(&model);
    model.browser_url_buffer.set("https://b.example");
    commitNavigation(&model);
    try std.testing.expectEqual(@as(usize, 2), model.browser_history_count);

    goBack(&model);
    try std.testing.expectEqualStrings("https://a.example", currentUrl(&model));
    try std.testing.expectEqualStrings("https://a.example", model.browser_url());
    try std.testing.expect(!forwardDisabled(&model));

    goForward(&model);
    try std.testing.expectEqualStrings("https://b.example", currentUrl(&model));
    try std.testing.expect(forwardDisabled(&model));

    goBack(&model);
    model.browser_url_buffer.set("https://c.example");
    commitNavigation(&model);
    try std.testing.expectEqual(@as(usize, 2), model.browser_history_count);
    try std.testing.expectEqualStrings("https://c.example", currentUrl(&model));
    try std.testing.expect(forwardDisabled(&model));

    goForward(&model);
    try std.testing.expectEqualStrings("https://c.example", currentUrl(&model));
    goBack(&model);
    goBack(&model);
    try std.testing.expectEqualStrings("https://a.example", currentUrl(&model));
}

test "reload bumps the pane token without changing the URL" {
    var model: Model = .{};
    var panes: [1]WebViewPane = undefined;
    model.browser_url_buffer.set("https://example.com/ok");
    commitNavigation(&model);
    _ = webPanes(&model, &panes);
    const before = panes[0].reload_token;
    reload(&model);
    _ = webPanes(&model, &panes);
    try std.testing.expect(panes[0].reload_token != before);
    try std.testing.expectEqualStrings("https://example.com/ok", panes[0].url);
}

test "history ring shifts the oldest entry once full" {
    var model: Model = .{};
    var i: usize = 0;
    while (i < max_history + 2) : (i += 1) {
        var buf: [64]u8 = undefined;
        const url = std.fmt.bufPrint(&buf, "https://n{d}.example", .{i}) catch unreachable;
        model.browser_url_buffer.set(url);
        commitNavigation(&model);
    }
    try std.testing.expectEqual(max_history, model.browser_history_count);
    try std.testing.expectEqual(max_history - 1, model.browser_history_index);
    try std.testing.expectEqualStrings("https://n33.example", currentUrl(&model));
    goBack(&model);
    try std.testing.expectEqualStrings("https://n32.example", currentUrl(&model));
}
