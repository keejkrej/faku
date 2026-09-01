//! Seed Model and appearance / theme boot helpers.
//!
//! `initialModel` is the first-run demo catalog (port + auth).
//! `onAppearance` / `resolvedColorScheme` / `designTokens` keep Geist
//! tokens in lockstep with OS appearance and Settings theme preference.
//! Re-exported from `main.zig` so `UiApp` and tests keep
//! `main.initialModel` / `main.onAppearance` / `main.resolvedColorScheme`
//! / `main.designTokens`. Behavior is unchanged from the former `main`
//! functions.

const std = @import("std");
const native_sdk = @import("native_sdk");
const model_mod = @import("model.zig");

const canvas = native_sdk.canvas;
const Model = model_mod.Model;
const Msg = model_mod.Msg;

/// Keep custom Geist tokens in lockstep with the OS light/dark flip.
pub fn onAppearance(appearance: native_sdk.platform.Appearance) ?Msg {
    return .{ .appearance_changed = appearance };
}

/// Geist pack with anti-aliased edges. Geometry pixel-snap makes 1x
/// rounded rects and the send circle stair-step; signed-distance
/// coverage stays on when snapping is off. Slightly larger radii match
/// Waku's 13px composer card.
///
/// Color scheme: System follows `model.appearance.color_scheme` from
/// `on_appearance`. Light / Dark force that scheme. High contrast and
/// reduce motion always follow the OS appearance.
pub fn resolvedColorScheme(model: *const Model) canvas.ColorScheme {
    return switch (model.theme_preference) {
        .light => .light,
        .dark => .dark,
        .system => switch (model.appearance.color_scheme) {
            .light => .light,
            .dark => .dark,
        },
    };
}

pub fn designTokens(model: *const Model) canvas.DesignTokens {
    const contrast: canvas.ColorContrast = if (model.appearance.high_contrast) .high else .standard;
    const scheme = resolvedColorScheme(model);
    return canvas.DesignTokens.themeWithOverrides(.{
        .pack = .house,
        .color_scheme = scheme,
        .contrast = contrast,
        .reduce_motion = model.appearance.reduce_motion,
    }, .{
        .pixel_snap = .{ .geometry = false },
    });
}

pub fn initialModel() Model {
    var model = Model{};
    const port = model.addSession("port waku to zig", .fx);
    _ = model.appendTurn(port, .user, "replace the GPUI desktop with a Native SDK Zig shell");
    _ = model.appendTurn(port, .assistant, "fx-first demo: sidebar, transcript, composer. Send runs `fx ask` when the CLI is installed.");

    const auth = model.addSession("fix auth listener", .claude);
    _ = model.appendTurn(auth, .user, "the auth listener drops the first event after reconnect");
    _ = model.appendTurn(auth, .assistant, "I will inspect the reconnect path and replay the last event.");
    _ = model.appendTurn(auth, .tool, "read src/auth/listener.ts");
    _ = model.appendTurn(auth, .assistant, "The handler unsubscribes before the replay buffer is flushed.");

    model.selected = port;
    model.pushSelectionHistory(port);
    model.pinTranscriptToLatest();
    if (model.sessionById(port)) |session| {
        session.has_started = true;
        session.detail_loaded = true;
    }
    if (model.sessionById(auth)) |session| {
        session.has_started = true;
        session.detail_loaded = true;
    }
    return model;
}

test "initialModel seeds the two demo sessions" {
    const model = initialModel();
    try std.testing.expectEqual(@as(u32, 2), model.session_count);

    const port = &model.session_store[0];
    try std.testing.expectEqualStrings("port waku to zig", port.title());
    try std.testing.expectEqual(.fx, port.provider);
    try std.testing.expectEqual(@as(u32, 2), model.turnCount(port.id));

    const auth = &model.session_store[1];
    try std.testing.expectEqualStrings("fix auth listener", auth.title());
    try std.testing.expectEqual(.claude, auth.provider);
    try std.testing.expectEqual(@as(u32, 4), model.turnCount(auth.id));
}
