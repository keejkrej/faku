//! Session fork and rewind orchestration helpers.
//!
//! Header / per-turn Fork and Send-time Rewind live here. Git plumbing
//! (`captureHead` / `resetHard`) stays in `rewind.zig`. Worktree
//! snapshot plumbing (`captureWorktreeCommit`) stays in
//! `checkpoint.zig`. Msg routing and Model fields stay in
//! `main.zig`. Behavior is unchanged from the former `main` fork
//! and rewind helpers.

const std = @import("std");
const main = @import("main.zig");
const store = @import("store.zig");
const rewind = @import("rewind.zig");
const checkpoint = @import("checkpoint.zig");

const Model = main.Model;
const Effects = main.Effects;
const max_sessions = main.max_sessions;
const max_turns = main.max_turns;

pub fn recordRewindRefIfPossible(model: *Model, session_id: u32) void {
    const io = model.store_io orelse return;
    const session = model.sessionById(session_id) orelse return;
    var sha_buf: [rewind.max_sha]u8 = undefined;
    if (rewind.captureHead(std.heap.page_allocator, io, session.projectPath(), &sha_buf)) |captured| {
        session.appendRewindRef(captured.sha, rewind.recorded_ref, captured.recorded_at);
    }
    var snap_buf: [rewind.stored_sha_len]u8 = undefined;
    if (checkpoint.captureWorktreeCommit(std.heap.page_allocator, io, session.projectPath(), &snap_buf)) |sha| {
        session.setWorktreeSnapshotSha(sha);
    }
}

/// Header Fork: local catalog clone through the last turn.
pub fn forkSelectedSession(model: *Model, fx: *Effects) void {
    store.hydrateIfPossible(model, model.selected);
    const available = model.turnCount(model.selected);
    if (available == 0) return;
    forkSelectedThrough(model, fx, available - 1);
}

/// Per-turn Fork: clone turns `0..=index` of the selected session.
/// Unknown / other-session ids are a no-op.
pub fn forkSelectedThroughTurn(model: *Model, fx: *Effects, turn_id: u32) void {
    store.hydrateIfPossible(model, model.selected);
    const index = selectedTurnIndex(model, turn_id) orelse return;
    forkSelectedThrough(model, fx, index);
}

pub fn selectedTurnIndex(model: *const Model, turn_id: u32) ?u32 {
    var index: u32 = 0;
    for (model.turn_store[0..model.turn_count]) |turn| {
        if (turn.session_id != model.selected) continue;
        if (turn.id == turn_id) return index;
        index += 1;
    }
    return null;
}

/// Local catalog clone through `through_index` (inclusive). New id, empty
/// `fx_session_id` / `runtime_id` so the next Send uses `session/new`.
/// Not a provider session fork and not a daemon RPC. Empty / full / no
/// room / past-the-end cut is a no-op.
pub fn forkSelectedThrough(model: *Model, fx: *Effects, through_index: u32) void {
    const source_id = model.selected;
    store.hydrateIfPossible(model, source_id);
    const source = model.sessionById(source_id) orelse return;
    const available = model.turnCount(source_id);
    if (available == 0 or through_index >= available) return;
    const needed = through_index + 1;
    if (model.session_count >= max_sessions) return;
    if (model.turn_count + needed > max_turns) return;

    const fork_id = model.addSession(source.title(), source.provider);
    if (fork_id == 0) return;
    if (model.sessionById(source_id)) |from| {
        if (model.sessionById(fork_id)) |session| {
            session.setProjectPath(from.projectPath());
            session.setModel(from.model());
            session.setAccessMode(from.accessMode());
            session.setInteractionMode(from.interactionMode());
            session.setReasoningEffort(from.reasoningEffort());
            session.folder_id = from.folder_id;
            session.untitled = from.untitled;
            session.setFxSessionId("");
            session.setRuntimeId("");
            // Session-level refs: header fork keeps the whole prefix.
            // Mid-session cuts keep the same stored shas. Do not invent shas.
            for (from.rewindRefs()) |item| {
                session.appendRewindRef(item.sha(), item.refName(), item.recorded_at);
            }
            session.setWorktreeSnapshotSha(from.worktreeSnapshotSha());
        }
    }

    const original_turn_count = model.turn_count;
    var copied: u32 = 0;
    var i: usize = 0;
    while (i < original_turn_count) : (i += 1) {
        const turn = model.turn_store[i];
        if (turn.session_id != source_id) continue;
        if (copied > through_index) break;
        _ = model.appendTurn(fork_id, turn.role, turn.text());
        copied += 1;
    }

    model.pushSelectionHistory(fork_id);
    main.applySessionSelection(model, fx, fork_id);
    store.persistIfPossible(model, fork_id, fx);
}

/// Reset workspace files to the latest Send-time HEAD, consume that ref,
/// and drop the last prompt's turns. Does not change `fx_session_id`.
/// Failed git is a no-op (ref and transcript stay).
pub fn applyRewindIfPossible(model: *Model, fx: *Effects) void {
    const io = model.store_io orelse return;
    const session = model.sessionById(model.selected) orelse return;
    const sha = session.latestRewindSha() orelse return;
    if (!rewind.resetHard(std.heap.page_allocator, io, session.projectPath(), sha)) return;
    session.popLatestRewindRef();
    model.dropLastPromptTurns(session.id);
    store.persistIfPossible(model, session.id, fx);
}
