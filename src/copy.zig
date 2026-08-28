//! Clipboard copy and turn-complete desktop notification helpers.
//!
//! Transcript / session / project-path clipboard writes and
//! successful-stream notify title/body live here. Msg routing and
//! Model fields stay in `main.zig`. Behavior is unchanged from the
//! former `main` copy and notify helpers, plus composer Copy path.

const std = @import("std");
const main = @import("main.zig");
const reveal_folder = @import("reveal_folder.zig");

const Model = main.Model;
const Effects = main.Effects;

/// Caller-chosen identity for `fx.writeClipboard` on a transcript
/// turn, a joined session, or the selected workspace path. Shares the
/// effects key space with spawn / fetch / file; sits in the gap
/// between daemon keys and `fx_spawn_overlap`. Verified: Native
/// Effects `WriteClipboardOptions` + notes example.
pub const copy_turn_key: u64 = 32;
/// Worst-case join of every in-memory turn with a blank line between.
const max_copy_session = main.max_turns * main.max_body + (main.max_turns - 1) * 2;
/// Scratch for `copySession`. `writeClipboard` copies `.text` during
/// the call; this outlives the join so the slice stays valid.
var copy_session_buf: [max_copy_session]u8 = undefined;
/// Decimal local session id (`u32` ≤ 10 digits). Same clipboard key
/// as copy turn / copy session — Native has one writeClipboard effect.
var copy_session_id_buf: [16]u8 = undefined;
/// Empty `fx_session_id` / ACP sessionId: do not writeClipboard.
pub const no_provider_session_id_status = "No provider session id";
/// Desktop notification title when the session has no stored title.
pub const notify_fallback_title = "Faku";
/// Desktop notification body when the last assistant turn is empty.
pub const notify_fallback_body = "Reply ready";
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

fn turnCompleteBody(model: *const Model, session_id: u32) []const u8 {
    const text = std.mem.trim(u8, lastAssistantText(model, session_id), " \t\r\n");
    if (text.len == 0) return notify_fallback_body;
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

/// Copy visible transcript text through Native `fx.writeClipboard`.
/// Empty text is a no-op — no fake clipboard, no `pbcopy` spawn.
fn writeVisibleClipboard(fx: *Effects, text: []const u8) void {
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
    writeVisibleClipboard(fx, turn.text());
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
    writeVisibleClipboard(fx, text);
}

/// Selected session's local `u32` id as decimal text. No invented UUID.
pub fn copySessionId(model: *Model, fx: *Effects) void {
    if (model.sessionByIdConst(model.selected) == null) return;
    const text = std.fmt.bufPrint(&copy_session_id_buf, "{d}", .{model.selected}) catch return;
    writeVisibleClipboard(fx, text);
}

/// Selected session `fx_session_id` (fx ask --json / ACP sessionId).
/// Empty does not writeClipboard — short status instead.
pub fn copyFxSessionId(model: *Model, fx: *Effects) void {
    const session = model.sessionByIdConst(model.selected) orelse return;
    const text = session.fxSessionId();
    if (text.len == 0) {
        model.setWindowStatus(no_provider_session_id_status);
        return;
    }
    writeVisibleClipboard(fx, text);
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
    writeVisibleClipboard(fx, path);
}
