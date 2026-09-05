//! Live-turn send / stream lifecycle / daemon steer-cancel helpers.
//!
//! `handleSend` / `handleSteer`, demo `tickStream`, finish drain +
//! queued restart, `stopStream` cancels, and daemon steer/cancel
//! one-shots live here. Successful `finishStream` (`drain == true`)
//! captures turn-end `refs/faku/session-{id}-turn-{n}` via
//! `fork.recordTurnEndIfPossible` (stores
//! `worktree_turn_end_sha` and `worktree_turn_diff_sha`; does
//! not overwrite `worktree_snapshot_sha`) after streaming state is
//! cleared and before persist / queued restart. That same success
//! records Environment Summary last-turn Completed unless a queued
//! follow-up immediately restarts (stay on the Process row). Live
//! Monitor / Subagent rows convert to settled (status from that
//! Process settle; Monitor / Subagent 512KB last-window kept; Faku-side
//! Dismiss, not live Stop)
//! on finish / stop instead of being wiped. `startPrompt` /
//! a queued restart does not free those settled rows.
//! `stopStream` records Stopped. `drain == false` records Failed.
//! Cancel / `stopStream` does not snapshot. Prompt spawn stays in
//! `spawn.zig`. Line handlers live in `lines.zig`. Behavior is
//! unchanged from the former `main` stream helpers except the
//! Background settle hooks.

const std = @import("std");
const main = @import("main.zig");
const protocol = @import("protocol.zig");
const store = @import("store.zig");
const daemon_proxy = @import("daemon_proxy.zig");
const prompt_spawn = @import("spawn.zig");
const session_fork = @import("fork.zig");
const copy_helpers = @import("copy.zig");
const attach_helpers = @import("attach.zig");
const environment_summary = @import("environment_summary.zig");
const session_workspace = @import("session_workspace.zig");

const Model = main.Model;
const Effects = main.Effects;
const stream_timer_key = main.stream_timer_key;
const fx_ask_key = main.fx_ask_key;
const daemon_line_bytes = main.daemon_line_bytes;
const stream_chunk_bytes = main.stream_chunk_bytes;
const demo_ticks_complete = main.demo_ticks_complete;
const demo_reply = main.demo_reply;
const max_queued_text = main.max_queued_text;

pub fn handleSend(model: *Model, fx: *Effects) void {
    if (!model.fx_probe_started) main.startFxProbe(model, fx);
    const text = std.mem.trim(u8, model.draft(), " \t\r\n");
    var key_buf: [store.max_draft_key]u8 = undefined;
    const draft_key = if (model.sessionById(model.selected)) |session|
        store.draftKey(session, &key_buf)
    else
        null;
    if (model.is_streaming()) {
        if (text.len == 0) {
            stopStream(model, fx);
            return;
        }
        if (model.enqueue(model.selected, text) != 0) {
            if (model.sessionById(model.selected)) |session| main.stampSessionActivity(session, model.now_ms);
            store.persistIfPossible(model, model.selected, fx);
        }
        model.draft_buffer.clear();
        if (draft_key) |key| store.discardDraftIfPossible(model, key);
        model.clearImageAttach();
        attach_helpers.refreshAttachPreview(model, fx);
        return;
    }
    if (text.len == 0) return;
    if (session_workspace.shouldPrepOnSend(model)) {
        if (session_workspace.beginPrep(model, fx, text)) {
            model.draft_buffer.clear();
            if (draft_key) |key| store.discardDraftIfPossible(model, key);
            model.clearImageAttach();
            attach_helpers.refreshAttachPreview(model, fx);
        }
        return;
    }
    prompt_spawn.startPrompt(model, fx, model.selected, text);
    model.draft_buffer.clear();
    if (draft_key) |key| store.discardDraftIfPossible(model, key);
    model.clearImageAttach();
    attach_helpers.refreshAttachPreview(model, fx);
}

/// Waku ⌘Enter: inject into a live daemon turn when attach reported
/// `supportsSteer`. Otherwise the same as Send (queue while busy).
pub fn handleSteer(model: *Model, fx: *Effects) void {
    if (!model.fx_probe_started) main.startFxProbe(model, fx);
    const text = std.mem.trim(u8, model.draft(), " \t\r\n");
    if (text.len == 0) return;
    if (maybeSteerDaemonTurn(model, fx, text)) {
        var key_buf: [store.max_draft_key]u8 = undefined;
        const draft_key = if (model.sessionById(model.selected)) |session|
            store.draftKey(session, &key_buf)
        else
            null;
        model.draft_buffer.clear();
        if (draft_key) |key| store.discardDraftIfPossible(model, key);
        model.clearImageAttach();
        attach_helpers.refreshAttachPreview(model, fx);
        return;
    }
    handleSend(model, fx);
}

pub fn tickStream(model: *Model, fx: *Effects) void {
    if (model.phase != .streaming) return;
    model.stream_cursor += 1;
    const start = @min(demo_reply.len, (model.stream_cursor - 1) * stream_chunk_bytes);
    const end = @min(demo_reply.len, start + stream_chunk_bytes);
    if (end > start) model.appendToTurn(model.stream_turn_id, demo_reply[start..end]);
    if (model.stream_cursor >= demo_ticks_complete or end >= demo_reply.len) {
        finishStream(model, fx, true);
    }
}

pub fn finishStream(model: *Model, fx: *Effects, drain: bool) void {
    const finished_id = model.streaming_session;
    if (model.sessionById(finished_id)) |session| session.busy = false;
    model.phase = .idle;
    model.stream_cursor = 0;
    model.stream_turn_id = 0;
    model.streaming_session = 0;
    fx.cancelTimer(stream_timer_key);
    const settle_status: environment_summary.SettledStatus = if (drain) .completed else .failed;
    environment_summary.settleLiveBackgroundSignals(model, finished_id, settle_status);
    if (drain) {
        session_fork.recordTurnEndIfPossible(model, finished_id);
        copy_helpers.notifyTurnComplete(model, fx, finished_id);
        var copy: [max_queued_text]u8 = undefined;
        if (model.takeNextQueued(finished_id, &copy)) |n| {
            store.persistIfPossible(model, finished_id, fx);
            prompt_spawn.startPrompt(model, fx, finished_id, copy[0..n]);
            return;
        }
        environment_summary.settle(model, finished_id, .completed);
    } else {
        environment_summary.settle(model, finished_id, .failed);
    }
    store.persistIfPossible(model, finished_id, fx);
}

pub fn stopStream(model: *Model, fx: *Effects) void {
    if (!model.is_streaming()) return;
    const finished_id = model.streaming_session;
    const was_daemon = model.daemon_spawn_key != 0;
    if (model.sessionById(finished_id)) |session| session.busy = false;
    model.phase = .idle;
    model.stream_cursor = 0;
    model.stream_turn_id = 0;
    model.streaming_session = 0;
    fx.cancelTimer(stream_timer_key);
    fx.cancel(fx_ask_key);
    if (model.fx_spawn_key != 0) fx.cancel(model.fx_spawn_key);
    if (model.daemon_spawn_key != 0) fx.cancel(model.daemon_spawn_key);
    model.fx_spawn_live = false;
    if (was_daemon) maybeCancelDaemonTurn(model, fx, finished_id);
    environment_summary.settleLiveBackgroundSignals(model, finished_id, .stopped);
    environment_summary.settle(model, finished_id, .stopped);
    store.persistIfPossible(model, finished_id, fx);
}

/// Live daemon turn that Waku would steer: address set, prompt sidecar
/// still running, and attach/start reported `supportsSteer`. Unknown
/// or false queues instead (same as Waku `session_can_steer`).
fn canSteerLiveDaemonTurn(model: *const Model) bool {
    if (model.daemonAddress().len == 0) return false;
    if (model.daemon_spawn_key == 0 or !model.is_streaming()) return false;
    const session = model.sessionByIdConst(model.streaming_session) orelse return false;
    return session.supports_steer;
}

/// Best-effort one-shot hello + `steer` into a live daemon turn. Own
/// spawn key — Native cannot write into the running prompt sidecar.
/// Returns true only after a spawn is recorded so the caller can clear
/// the draft. Write failure leaves the draft and does not enqueue.
fn maybeSteerDaemonTurn(model: *Model, fx: *Effects, prompt: []const u8) bool {
    if (!canSteerLiveDaemonTurn(model)) return false;
    const session = model.sessionById(model.streaming_session) orelse return false;
    var id_buf: [36]u8 = undefined;
    const wire_id = daemon_proxy.wireUuid(session.id, &id_buf);
    const runtime_id = if (protocol.isUsableRuntimeId(session.runtimeId()))
        session.runtimeId()
    else
        protocol.NIL_UUID;
    var stdin_buf: [4096]u8 = undefined;
    const stdin = daemon_proxy.writeSteerStdin(&stdin_buf, .{
        .token = model.daemonToken(),
        .session_id = wire_id,
        .runtime_id = runtime_id,
        .prompt = prompt,
    }) catch return false;

    const key = model.next_daemon_key;
    model.next_daemon_key += 1;
    fx.spawn(.{
        .key = key,
        .argv = &.{ model.sidecarPath(), daemon_proxy.SUBCOMMAND, model.daemonAddress() },
        .stdin = stdin,
        .max_line_bytes = daemon_line_bytes,
        .on_line = Effects.lineMsg(.fx_line),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
    return true;
}

/// Best-effort one-shot hello + bare `cancel` after Stop / Esc of a
/// daemon turn. Own spawn key — Native cannot write into the running
/// prompt sidecar. Missing live address is a no-op (fx ask / fx acp /
/// demo stay cancel-the-spawn only). Sidecar failure must not
/// resurrect the turn already settled above.
fn maybeCancelDaemonTurn(model: *Model, fx: *Effects, session_id: u32) void {
    if (model.daemonAddress().len == 0) return;
    const session = model.sessionById(session_id) orelse return;
    var id_buf: [36]u8 = undefined;
    const wire_id = daemon_proxy.wireUuid(session.id, &id_buf);
    const runtime_id = if (protocol.isUsableRuntimeId(session.runtimeId()))
        session.runtimeId()
    else
        protocol.NIL_UUID;
    var stdin_buf: [4096]u8 = undefined;
    const stdin = daemon_proxy.writeCancelStdin(&stdin_buf, .{
        .token = model.daemonToken(),
        .session_id = wire_id,
        .runtime_id = runtime_id,
    }) catch return;

    const key = model.next_daemon_key;
    model.next_daemon_key += 1;
    fx.spawn(.{
        .key = key,
        .argv = &.{ model.sidecarPath(), daemon_proxy.SUBCOMMAND, model.daemonAddress() },
        .stdin = stdin,
        .max_line_bytes = daemon_line_bytes,
        .on_line = Effects.lineMsg(.fx_line),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
}
