//! Clipboard copy and turn-complete desktop notification helpers.
//!
//! Transcript / session / project-path clipboard writes,
//! Settings Providers fx install/login command copy, and
//! successful-stream notify title/body live here. Msg routing and
//! Model fields stay in `main.zig`. Behavior is unchanged from the
//! former `main` copy and notify helpers, plus composer Copy path.
//! Notify fallback body and Copy provider session id empty-status
//! follow the resolved locale this cut (same `i18n.NotifyCopyChrome`
//! strings; product/notify title `Faku` stays Latin; session titles,
//! assistant turn body text, and clipboard contents stay data).

const std = @import("std");
const main = @import("main.zig");
const model_exports = @import("model_exports.zig");
const reveal_folder = @import("reveal_folder.zig");
const i18n = @import("i18n.zig");

const Model = model_exports.Model;
const Effects = main.Effects;

/// Caller-chosen identity for `fx.writeClipboard` on a transcript
/// turn, a joined session, the selected workspace path, or Settings
/// Providers fx install/login command copy. Shares the effects key
/// space with spawn / fetch / file; sits in the gap between daemon
/// keys and `fx_spawn_overlap`. Verified: Native Effects
/// `WriteClipboardOptions` + notes example.
pub const copy_turn_key: u64 = 32;
/// Worst-case join of every in-memory turn with a blank line between.
const max_copy_session = model_exports.max_turns * model_exports.max_body + (model_exports.max_turns - 1) * 2;
/// Scratch for `copySession`. `writeClipboard` copies `.text` during
/// the call; this outlives the join so the slice stays valid.
var copy_session_buf: [max_copy_session]u8 = undefined;
/// Decimal local session id (`u32` ≤ 10 digits). Same clipboard key
/// as copy turn / copy session — Native has one writeClipboard effect.
var copy_session_id_buf: [16]u8 = undefined;
/// Empty `fx_session_id` / ACP sessionId: do not writeClipboard.
/// English alias for tests; paint/notify uses `noProviderSessionIdStatusFor`.
pub const no_provider_session_id_status = i18n.notifyCopyChromeFor(.english, "").no_provider_session_id;
/// Desktop notification title when the session has no stored title.
/// Product name stays Latin in every locale (same rule as FX_MODEL).
pub const notify_fallback_title = "Faku";
/// Desktop notification body when the last assistant turn is empty.
/// English alias for tests; notify uses `notifyFallbackBodyFor`.
pub const notify_fallback_body = i18n.notifyCopyChromeFor(.english, "").notify_fallback_body;
/// Short body cap. Native allows 1024; keep the toast readable.
pub const notify_body_max: usize = 120;

fn lastAssistantText(model: *const Model, session_id: u32) []const u8 {
    var i = model.turn_count;
    while (i > 0) {
        i -= 1;
        const turn = &model.turn_store[i];
        if (turn.session_id == session_id and turn.role == .assistant) return turn.text();
    }
    return "";
}

fn truncateNotifyBody(text: []const u8) []const u8 {
    if (text.len <= notify_body_max) return text;
    var end = notify_body_max;
    while (end > 0 and (text[end] & 0xC0) == 0x80) end -= 1;
    return text[0..end];
}

fn turnCompleteTitle(model: *const Model, session_id: u32) []const u8 {
    const session = model.sessionByIdConst(session_id) orelse return notify_fallback_title;
    if (session.title().len == 0) return notify_fallback_title;
    return session.title();
}

pub fn notifyFallbackBodyFor(preference: i18n.LanguagePreference, system_locale_id: []const u8) []const u8 {
    return i18n.notifyCopyChromeFor(preference, system_locale_id).notify_fallback_body;
}

pub fn noProviderSessionIdStatusFor(preference: i18n.LanguagePreference, system_locale_id: []const u8) []const u8 {
    return i18n.notifyCopyChromeFor(preference, system_locale_id).no_provider_session_id;
}

fn turnCompleteBody(model: *const Model, session_id: u32) []const u8 {
    const text = std.mem.trim(u8, lastAssistantText(model, session_id), " \t\r\n");
    if (text.len == 0) return notifyFallbackBodyFor(model.language_preference, model.systemLocaleId());
    return truncateNotifyBody(text);
}

/// Successful stream settle only. Native has no focus observation, so
/// this always fires — not Waku's unfocused-only gate.
pub fn notifyTurnComplete(model: *const Model, fx: *Effects, session_id: u32) void {
    fx.showNotification(.{
        .title = turnCompleteTitle(model, session_id),
        .body = turnCompleteBody(model, session_id),
    });
}

/// Copy visible text through Native `fx.writeClipboard`. Empty
/// text is a no-op — no fake clipboard, no `pbcopy` spawn, no
/// shell that runs a remote install script.
pub fn copyText(fx: *Effects, text: []const u8) void {
    if (text.len == 0) return;
    fx.writeClipboard(.{
        .key = copy_turn_key,
        .text = text,
        .on_result = Effects.clipboardMsg(.clipboard_done),
    });
}

/// Copy a turn's visible text (markdown source / tool / thought body)
/// through Native `fx.writeClipboard`. Empty text is a no-op.
pub fn copyTurn(model: *Model, fx: *Effects, id: u32) void {
    const turn = model.turnById(id) orelse return;
    copyText(fx, turn.text());
}

/// Selected session, store order. Skip empty turns. Join remaining
/// user / assistant / tool / thought bodies with a blank line.
/// Returns null when nothing remains so the clipboard is not requested.
fn joinSelectedSessionText(model: *const Model) ?[]const u8 {
    var n: usize = 0;
    var any = false;
    for (model.turn_store[0..model.turn_count]) |*turn| {
        if (turn.session_id != model.selected) continue;
        const text = turn.text();
        if (text.len == 0) continue;
        if (any) {
            copy_session_buf[n] = '\n';
            copy_session_buf[n + 1] = '\n';
            n += 2;
        }
        @memcpy(copy_session_buf[n..][0..text.len], text);
        n += text.len;
        any = true;
    }
    if (!any) return null;
    return copy_session_buf[0..n];
}

pub fn copySession(model: *Model, fx: *Effects) void {
    const text = joinSelectedSessionText(model) orelse return;
    copyText(fx, text);
}

/// Selected session's local `u32` id as decimal text. No invented UUID.
pub fn copySessionId(model: *Model, fx: *Effects) void {
    if (model.sessionByIdConst(model.selected) == null) return;
    const text = std.fmt.bufPrint(&copy_session_id_buf, "{d}", .{model.selected}) catch return;
    copyText(fx, text);
}

/// Selected session `fx_session_id` (fx ask --json / ACP sessionId).
/// Empty does not writeClipboard — short status instead.
pub fn copyFxSessionId(model: *Model, fx: *Effects) void {
    const session = model.sessionByIdConst(model.selected) orelse return;
    const text = session.fxSessionId();
    if (text.len == 0) {
        model.setWindowStatus(noProviderSessionIdStatusFor(model.language_preference, model.systemLocaleId()));
        return;
    }
    copyText(fx, text);
}

/// Selected session, newest first. Empty text is skipped so a trailing
/// blank assistant/tool/thought turn does not hide the last real copy.
fn latestNonEmptyTurnId(model: *const Model) ?u32 {
    var i: usize = model.turn_count;
    while (i > 0) {
        i -= 1;
        const turn = model.turn_store[i];
        if (turn.session_id != model.selected) continue;
        if (turn.text().len == 0) continue;
        return turn.id;
    }
    return null;
}

pub fn copyLastTurn(model: *Model, fx: *Effects) void {
    const id = latestNonEmptyTurnId(model) orelse return;
    copyTurn(model, fx, id);
}

/// Absolute existing selected-session directory. Hidden for Local /
/// empty / missing / relative / file paths. Same `resolveRevealPath`
/// gate as Open in Terminal / Open in Editor.
pub fn canCopyProjectPath(model: *const Model) bool {
    return reveal_folder.resolveRevealPath(model) != null;
}

/// Selected session workspace path through Native `fx.writeClipboard`.
/// Empty / relative / missing is a no-op — does not overwrite the
/// clipboard. Reuses `copy_turn_key` (Native has one writeClipboard
/// effect). Not Waku's Open-in app picker.
pub fn copyProjectPath(model: *Model, fx: *Effects) void {
    const path = reveal_folder.resolveRevealPath(model) orelse return;
    copyText(fx, path);
}

test "notify and copy chrome follows resolved locale" {
    const zh = i18n.notifyCopyChromeFor(.simplified_chinese, "");
    const ja = i18n.notifyCopyChromeFor(.japanese, "");
    const en = i18n.notifyCopyChromeFor(.english, "");

    try std.testing.expectEqualStrings(en.notify_fallback_body, notify_fallback_body);
    try std.testing.expectEqualStrings(en.no_provider_session_id, no_provider_session_id_status);
    try std.testing.expectEqualStrings("Reply ready", notify_fallback_body);
    try std.testing.expectEqualStrings("No provider session id", no_provider_session_id_status);
    try std.testing.expectEqualStrings("Faku", notify_fallback_title);

    try std.testing.expectEqualStrings(en.notify_fallback_body, notifyFallbackBodyFor(.english, ""));
    try std.testing.expectEqualStrings(en.notify_fallback_body, notifyFallbackBodyFor(.english, "ja_JP.UTF-8"));
    try std.testing.expectEqualStrings(zh.notify_fallback_body, notifyFallbackBodyFor(.simplified_chinese, ""));
    try std.testing.expectEqualStrings(ja.notify_fallback_body, notifyFallbackBodyFor(.japanese, ""));
    try std.testing.expectEqualStrings(zh.notify_fallback_body, notifyFallbackBodyFor(.system, "zh_CN.UTF-8"));
    try std.testing.expectEqualStrings(ja.notify_fallback_body, notifyFallbackBodyFor(.system, "ja_JP.UTF-8"));

    try std.testing.expectEqualStrings(en.no_provider_session_id, noProviderSessionIdStatusFor(.english, ""));
    try std.testing.expectEqualStrings(en.no_provider_session_id, noProviderSessionIdStatusFor(.english, "zh_CN.UTF-8"));
    try std.testing.expectEqualStrings(zh.no_provider_session_id, noProviderSessionIdStatusFor(.simplified_chinese, ""));
    try std.testing.expectEqualStrings(ja.no_provider_session_id, noProviderSessionIdStatusFor(.japanese, ""));
    try std.testing.expectEqualStrings(zh.no_provider_session_id, noProviderSessionIdStatusFor(.system, "zh_CN.UTF-8"));
    try std.testing.expectEqualStrings(ja.no_provider_session_id, noProviderSessionIdStatusFor(.system, "ja_JP.UTF-8"));
}

test "copyFxSessionId empty status follows resolved locale" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    const id = model.addSession("copy fx", .fx);
    model.selected = id;

    copyFxSessionId(&model, &fx);
    try std.testing.expectEqual(@as(usize, 0), fx.pendingClipboardCount());
    try std.testing.expectEqualStrings(no_provider_session_id_status, model.window_status());

    model.language_preference = .simplified_chinese;
    copyFxSessionId(&model, &fx);
    try std.testing.expectEqualStrings(noProviderSessionIdStatusFor(.simplified_chinese, ""), model.window_status());

    model.language_preference = .japanese;
    copyFxSessionId(&model, &fx);
    try std.testing.expectEqualStrings(noProviderSessionIdStatusFor(.japanese, ""), model.window_status());
}

test "notifyTurnComplete empty body follows resolved locale; title stays Faku or session title" {
    const native_sdk = @import("native_sdk");
    const NotifySink = struct {
        platform: native_sdk.NullPlatform = undefined,
        host: native_sdk.platform.Platform = undefined,
    };
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    var sink: NotifySink = undefined;
    sink.platform = native_sdk.NullPlatform.init(.{});
    sink.host = sink.platform.platform();
    fx.bindServices(&sink.host.services);

    var model = Model{};
    const id = model.addSession("quiet", .fx);
    model.selected = id;
    _ = model.appendTurn(id, .assistant, "   ");
    notifyTurnComplete(&model, &fx, id);
    try std.testing.expectEqual(@as(usize, 1), sink.platform.notificationCount());
    try std.testing.expectEqualStrings("quiet", sink.platform.lastNotificationTitle());
    try std.testing.expectEqualStrings(notify_fallback_body, sink.platform.lastNotificationBody());

    model.language_preference = .simplified_chinese;
    notifyTurnComplete(&model, &fx, id);
    try std.testing.expectEqualStrings("quiet", sink.platform.lastNotificationTitle());
    try std.testing.expectEqualStrings(notifyFallbackBodyFor(.simplified_chinese, ""), sink.platform.lastNotificationBody());

    model.language_preference = .japanese;
    notifyTurnComplete(&model, &fx, id);
    try std.testing.expectEqualStrings("quiet", sink.platform.lastNotificationTitle());
    try std.testing.expectEqualStrings(notifyFallbackBodyFor(.japanese, ""), sink.platform.lastNotificationBody());

    var untitled = Model{};
    untitled.language_preference = .simplified_chinese;
    const untitled_id = untitled.addSession("", .fx);
    untitled.selected = untitled_id;
    notifyTurnComplete(&untitled, &fx, untitled_id);
    try std.testing.expectEqualStrings(notify_fallback_title, sink.platform.lastNotificationTitle());
    try std.testing.expectEqualStrings("Faku", sink.platform.lastNotificationTitle());
    try std.testing.expectEqualStrings(notifyFallbackBodyFor(.simplified_chinese, ""), sink.platform.lastNotificationBody());
}
