//! Seed Model and appearance / theme boot helpers.
//!
//! `initialModel` is the first-run demo catalog (port + auth).
//! `onAppearance` / `resolvedColorScheme` / `designTokens` keep Geist
//! tokens in lockstep with OS appearance, Settings theme preference,
//! Settings UI font size, and Settings code font size. Callers import
//! this module directly
//! (`boot.initialModel` / `boot.onAppearance` / `boot.resolvedColorScheme` /
//! `boot.designTokens`). Not re-exported from `main`.
//! Behavior is unchanged from the former `main` functions.

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

/// Scale house typography rungs from pack defaults. `code_font_size`
/// scales `body_size` only (messages, code, diffs, terminal — Native
/// couples these to body_size). `ui_font_size` scales label / title /
/// button / heading / display only (chrome/controls). Default both 14
/// is identity (current look). Uses documented
/// `DesignTokenOverrides.typography` size fields only. No separate mono
/// size token.
pub fn typographyOverrides(ui_font_size: u8, code_font_size: u8, pack: anytype) canvas.TypographyTokenOverrides {
    const ui_size = model_mod.sanitizeUiFontSize(ui_font_size);
    const code_size = model_mod.sanitizeCodeFontSize(code_font_size);
    const ui_scale = @as(f32, @floatFromInt(ui_size)) / @as(f32, @floatFromInt(model_mod.default_ui_font_size));
    const code_scale = @as(f32, @floatFromInt(code_size)) / @as(f32, @floatFromInt(model_mod.default_code_font_size));
    return .{
        .body_size = pack.body_size * code_scale,
        .label_size = pack.label_size * ui_scale,
        .title_size = pack.title_size * ui_scale,
        .button_size = pack.button_size * ui_scale,
        .heading_size = pack.heading_size * ui_scale,
        .display_size = pack.display_size * ui_scale,
    };
}

pub fn designTokens(model: *const Model) canvas.DesignTokens {
    const contrast: canvas.ColorContrast = if (model.appearance.high_contrast) .high else .standard;
    const scheme = resolvedColorScheme(model);
    const pack = canvas.DesignTokens.theme(.{
        .pack = .house,
        .color_scheme = scheme,
        .contrast = contrast,
        .reduce_motion = model.appearance.reduce_motion,
    });
    return canvas.DesignTokens.themeWithOverrides(.{
        .pack = .house,
        .color_scheme = scheme,
        .contrast = contrast,
        .reduce_motion = model.appearance.reduce_motion,
    }, .{
        .pixel_snap = .{ .geometry = false },
        .typography = typographyOverrides(model.ui_font_size, model.code_font_size, pack.typography),
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

test "designTokens typography: body tracks code_font; label tracks ui_font; default 14 matches pack" {
    var model = Model{};
    try std.testing.expectEqual(model_mod.default_ui_font_size, model.ui_font_size);
    try std.testing.expectEqual(model_mod.default_code_font_size, model.code_font_size);

    const contrast: canvas.ColorContrast = .standard;
    const scheme = resolvedColorScheme(&model);
    const pack = canvas.DesignTokens.theme(.{
        .pack = .house,
        .color_scheme = scheme,
        .contrast = contrast,
        .reduce_motion = false,
    });
    const default_tokens = designTokens(&model);
    try std.testing.expect(!default_tokens.pixel_snap.geometry);
    try std.testing.expectEqual(pack.typography.body_size, default_tokens.typography.body_size);
    try std.testing.expectEqual(pack.typography.label_size, default_tokens.typography.label_size);
    try std.testing.expectEqual(pack.typography.title_size, default_tokens.typography.title_size);
    try std.testing.expectEqual(pack.typography.button_size, default_tokens.typography.button_size);
    try std.testing.expectEqual(pack.typography.heading_size, default_tokens.typography.heading_size);
    try std.testing.expectEqual(pack.typography.display_size, default_tokens.typography.display_size);

    model.setUiFontSize(20);
    const large_ui = designTokens(&model);
    const ui_scale = 20.0 / 14.0;
    try std.testing.expectEqual(pack.typography.body_size, large_ui.typography.body_size);
    try std.testing.expectApproxEqAbs(pack.typography.label_size * ui_scale, large_ui.typography.label_size, 0.001);
    try std.testing.expectApproxEqAbs(pack.typography.title_size * ui_scale, large_ui.typography.title_size, 0.001);
    try std.testing.expectApproxEqAbs(pack.typography.button_size * ui_scale, large_ui.typography.button_size, 0.001);
    try std.testing.expectApproxEqAbs(pack.typography.heading_size * ui_scale, large_ui.typography.heading_size, 0.001);
    try std.testing.expectApproxEqAbs(pack.typography.display_size * ui_scale, large_ui.typography.display_size, 0.001);
    try std.testing.expect(large_ui.typography.label_size > default_tokens.typography.label_size);
    try std.testing.expect(!large_ui.pixel_snap.geometry);

    model.setCodeFontSize(20);
    const large_code = designTokens(&model);
    const code_scale = 20.0 / 14.0;
    try std.testing.expectApproxEqAbs(pack.typography.body_size * code_scale, large_code.typography.body_size, 0.001);
    try std.testing.expectApproxEqAbs(pack.typography.label_size * ui_scale, large_code.typography.label_size, 0.001);
    try std.testing.expect(large_code.typography.body_size > default_tokens.typography.body_size);

    model.setUiFontSize(11);
    model.setCodeFontSize(16);
    const split = designTokens(&model);
    try std.testing.expectApproxEqAbs(pack.typography.body_size * (16.0 / 14.0), split.typography.body_size, 0.001);
    try std.testing.expectApproxEqAbs(pack.typography.label_size * (11.0 / 14.0), split.typography.label_size, 0.001);
    try std.testing.expect(split.typography.body_size > default_tokens.typography.body_size);
    try std.testing.expect(split.typography.label_size < default_tokens.typography.label_size);

    model.setUiFontSize(11);
    model.setCodeFontSize(11);
    const small = designTokens(&model);
    try std.testing.expect(small.typography.body_size < default_tokens.typography.body_size);
    try std.testing.expect(small.typography.label_size < default_tokens.typography.label_size);

    model.setUiFontSize(17);
    model.setCodeFontSize(24);
    try std.testing.expectEqual(model_mod.default_ui_font_size, model.ui_font_size);
    try std.testing.expectEqual(model_mod.default_code_font_size, model.code_font_size);
    try std.testing.expectEqual(model_mod.default_ui_font_size, model_mod.sanitizeUiFontSize(0));
    try std.testing.expectEqual(model_mod.default_ui_font_size, model_mod.sanitizeUiFontSize(9));
    try std.testing.expectEqual(model_mod.default_ui_font_size, model_mod.sanitizeUiFontSize(24));
    try std.testing.expectEqual(@as(u8, 16), model_mod.sanitizeUiFontSize(16));
    try std.testing.expectEqual(model_mod.default_code_font_size, model_mod.sanitizeCodeFontSize(0));
    try std.testing.expectEqual(model_mod.default_code_font_size, model_mod.sanitizeCodeFontSize(9));
    try std.testing.expectEqual(model_mod.default_code_font_size, model_mod.sanitizeCodeFontSize(24));
    try std.testing.expectEqual(@as(u8, 16), model_mod.sanitizeCodeFontSize(16));
}
