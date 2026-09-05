//! Session fork and rewind orchestration helpers.
//!
//! Header / per-turn Fork and Send-time Rewind live here. Git plumbing
//! (`captureHead` / `resetHard`) stays in `rewind.zig`. Worktree
//! snapshot plumbing (`captureTurnStartCommit` /
//! `captureWorktreeCommit` / `captureTurnStart` /
//! `captureTurnEnd` / `prepareTurnDiffBase` /
//! `updateFakuRef` / `restoreRef`) stays in
//! `checkpoint.zig`. Msg routing and Model fields stay in
//! `main.zig`. First-cut daemon `WorkspaceOperation::CaptureTurnStart`
//! is a best-effort sidecar after local Send capture when
//! `WAKU_DAEMON_ADDRESS` or persisted `last_daemon_address` is set
//! (hello + `{ "type": "captureTurnStart", "cwd", "sessionId",
//! "turnCount" }`; ok is workspace Ack). Local
//! `captureTurnStartCommit` / `refs/faku/...` stay canonical for
//! `worktree_snapshot_sha`. First-cut daemon
//! `WorkspaceOperation::CaptureTurn` is a best-effort sidecar after
//! successful local finish-time capture when a daemon address is
//! set (hello + `{ "type": "captureTurn", "cwd", "sessionId",
//! "turnCount" }`; ok is nested `WorkspaceResult::Checkpoint`).
//! Local `worktree_turn_end_sha` / `worktree_turn_diff_sha` /
//! `refs/faku/...` stay canonical; the Checkpoint payload must not
//! replace them. First-cut daemon
//! `WorkspaceOperation::CopySessionRefs` is a best-effort sidecar
//! after a local `sessions.json` fork succeeds when a daemon
//! address is set (hello + `{ "type": "copySessionRefs", "cwd",
//! "source_session_id", "target_session_id", "through_turn_count" }`;
//! snake_case session/turn fields — WorkspaceOperation serde
//! `rename_all` is the camelCase `type` tag only; live Waku
//! CaptureTurnStart / SessionTurnRefs send `session_id` /
//! `turn_count`. Ok is workspace Ack). Local fork stays canonical;
//! Faku refs stay `refs/faku/...`. Missing address / Native 4 KiB
//! stdin overflow / sidecar failure must not break Send or finish
//! or the local fork or clear the local shas. First-cut daemon
//! `WorkspaceOperation::DeleteSessionRefs` lives in `store` (best-effort
//! sidecar after a local `sessions.json` remove; Ack; local remove
//! stays canonical; not a replacement for `closeSession`). First-cut
//! daemon `WorkspaceOperation::HasRef` prefers hello + hasRef on Send
//! for the baseline check that otherwise calls local
//! `checkpoint.hasFakuRef` when a daemon address is set and cwd is a
//! git worktree (hello + `{ "type": "hasRef", "cwd", "git_ref" }`;
//! snake_case `git_ref`; ok is nested `WorkspaceResult::Bool`). Local
//! `hasFakuRef` (`show-ref --verify`) stays the offline / overflow /
//! miss / non-bool / error fallback and remains correct without a
//! daemon. Leftovers:
//! CaptureRef / RestoreRef / DeleteRef / DeleteTurnRefsAfter /
//! SessionTurnRefs, amend/force over daemon, remote `--track` over
//! daemon, etc.

const std = @import("std");
const native_sdk = @import("native_sdk");
const main = @import("main.zig");
const store = @import("store.zig");
const rewind = @import("rewind.zig");
const checkpoint = @import("checkpoint.zig");
const daemon_proxy = @import("daemon_proxy.zig");
const protocol = @import("protocol.zig");

const Model = main.Model;
const Effects = main.Effects;
const max_sessions = main.max_sessions;
const max_turns = main.max_turns;
const writeFixed = main.writeFixed;

pub fn recordRewindRefIfPossible(model: *Model, fx: *Effects, session_id: u32) void {
    const session = model.sessionById(session_id) orelse return;
    var seed_sha_buf: [rewind.stored_sha_len]u8 = undefined;
    var seed_sha_len: usize = 0;
    if (model.store_io) |io| {
        var sha_buf: [rewind.max_sha]u8 = undefined;
        if (rewind.captureHead(std.heap.page_allocator, io, session.projectPath(), &sha_buf)) |captured| {
            session.appendRewindRef(captured.sha, rewind.recorded_ref, captured.recorded_at);
        }
        var snap_buf: [rewind.stored_sha_len]u8 = undefined;
        if (checkpoint.captureTurnStartCommit(std.heap.page_allocator, io, session.projectPath(), &snap_buf)) |sha| {
            session.setWorktreeSnapshotSha(sha);
            // New start snapshot: this turn has no finish-time
            // end or turn-diff base yet. LastTurn falls back to
            // two-dot until recordTurnEndIfPossible stores them.
            session.clearWorktreeTurnEndSha();
            session.clearWorktreeTurnDiffSha();
            // turn-start-N is this Send's 1-based prompt ordinal
            // (turnCount/2+1 before the user+assistant pair is
            // appended). Seeds turn-{N-1} when that baseline is
            // missing unless a daemon HasRef sidecar is preferred.
            // Does not write turn-N (that is finish-time
            // captureTurnEnd). Failed update-ref must not clear
            // the sha already stored.
            const turn_n = checkpoint.fakuSendTurn(model.turnCount(session_id));
            var start_buf: [checkpoint.max_faku_ref_name]u8 = undefined;
            if (checkpoint.formatFakuSessionTurnStartRef(&start_buf, session.id, turn_n)) |start_ref| {
                _ = checkpoint.updateFakuRef(
                    std.heap.page_allocator,
                    io,
                    session.projectPath(),
                    start_ref,
                    sha,
                );
            }
            @memcpy(seed_sha_buf[0..sha.len], sha);
            seed_sha_len = sha.len;
        }
    }
    const seed_sha = seed_sha_buf[0..seed_sha_len];
    if (!trySpawnDaemonHasRef(model, fx, session, seed_sha)) {
        if (seed_sha.len > 0) {
            if (model.store_io) |io| {
                checkpoint.seedBaselineIfMissing(
                    std.heap.page_allocator,
                    io,
                    session.projectPath(),
                    session.id,
                    checkpoint.fakuSendTurn(model.turnCount(session_id)),
                    seed_sha,
                );
            }
        }
    }
    _ = trySpawnDaemonCaptureTurnStart(model, fx, session);
}

/// Best-effort hello + `WorkspaceOperation::CaptureTurnStart` after
/// local Send capture. Own daemon spawn key on
/// `daemon_capture_turn_start_key`. Missing address, empty cwd, or
/// Native 4 KiB stdin overflow returns false and leaves local
/// capture alone. Does not replace local sync capture.
fn trySpawnDaemonCaptureTurnStart(model: *Model, fx: *Effects, session: *main.Session) bool {
    const address = store.resolveDaemonMirrorAddress(model);
    if (address.len == 0) return false;
    const cwd = session.projectPath();
    if (cwd.len == 0) return false;

    var id_buf: [36]u8 = undefined;
    const wire_id = daemon_proxy.wireUuid(session.id, &id_buf);
    const turn_count = checkpoint.fakuSendTurn(model.turnCount(session.id));
    var stdin_buf: [4096]u8 = undefined;
    const stdin = daemon_proxy.writeWorkspaceStdin(&stdin_buf, .{
        .token = model.daemonToken(),
        .operation = .{
            .capture_turn_start = .{
                .cwd = cwd,
                .session_id = wire_id,
                .turn_count = turn_count,
            },
        },
    }) catch return false;

    if (model.daemon_capture_turn_start_key != 0) {
        fx.cancel(model.daemon_capture_turn_start_key);
        model.daemon_capture_turn_start_key = 0;
        model.daemon_capture_turn_start_session = 0;
    }

    const key = model.next_daemon_key;
    model.next_daemon_key += 1;
    model.daemon_capture_turn_start_key = key;
    model.daemon_capture_turn_start_session = session.id;
    fx.spawn(.{
        .key = key,
        .argv = &.{ model.sidecarPath(), daemon_proxy.SUBCOMMAND, address },
        .stdin = stdin,
        .max_line_bytes = main.daemon_line_bytes,
        .on_line = Effects.lineMsg(.fx_line),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
    return true;
}

/// Drop an in-flight CaptureTurnStart sidecar. Safe when none is live.
pub fn cancelDaemonCaptureTurnStart(model: *Model, fx: *Effects) void {
    if (model.daemon_capture_turn_start_key == 0) return;
    fx.cancel(model.daemon_capture_turn_start_key);
    model.daemon_capture_turn_start_key = 0;
    model.daemon_capture_turn_start_session = 0;
}

/// Drop an in-flight CaptureTurn sidecar. Safe when none is live.
pub fn cancelDaemonCaptureTurn(model: *Model, fx: *Effects) void {
    if (model.daemon_capture_turn_key == 0) return;
    fx.cancel(model.daemon_capture_turn_key);
    model.daemon_capture_turn_key = 0;
    model.daemon_capture_turn_session = 0;
}

/// Drop an in-flight CopySessionRefs sidecar. Safe when none is live.
pub fn cancelDaemonCopySessionRefs(model: *Model, fx: *Effects) void {
    if (model.daemon_copy_session_refs_key == 0) return;
    fx.cancel(model.daemon_copy_session_refs_key);
    model.daemon_copy_session_refs_key = 0;
    model.daemon_copy_session_refs_session = 0;
}

/// Drop an in-flight HasRef sidecar. Safe when none is live. A still
/// unresolved probe falls back to local `hasFakuRef` so a session
/// switch cannot leave the baseline unseeded.
pub fn cancelDaemonHasRef(model: *Model, fx: *Effects) void {
    if (model.daemon_has_ref_key == 0) return;
    fx.cancel(model.daemon_has_ref_key);
    fallbackLocalHasRefIfNeeded(model);
    clearDaemonHasRef(model);
}

fn clearDaemonHasRef(model: *Model) void {
    model.daemon_has_ref_key = 0;
    model.daemon_has_ref_session = 0;
    model.daemon_has_ref_ok = false;
    model.daemon_has_ref_git_ref_len = 0;
    model.daemon_has_ref_cwd_len = 0;
    model.daemon_has_ref_sha_len = 0;
    model.daemon_has_ref_turn = 0;
}

/// Prefer hello + `WorkspaceOperation::HasRef` for the Send-time
/// baseline check that otherwise calls local `hasFakuRef`. Own
/// daemon spawn key on `daemon_has_ref_key`. Missing address,
/// empty cwd, non-git cwd, unformattable ref, or Native 4 KiB
/// stdin overflow returns false and leaves local `hasFakuRef`.
fn trySpawnDaemonHasRef(
    model: *Model,
    fx: *Effects,
    session: *main.Session,
    seed_sha: []const u8,
) bool {
    const address = store.resolveDaemonMirrorAddress(model);
    if (address.len == 0) return false;
    const cwd = session.projectPath();
    if (cwd.len == 0) return false;
    const io = model.store_io orelse return false;
    if (!rewind.isGitWorkTree(io, cwd)) return false;

    const turn_n = checkpoint.fakuSendTurn(model.turnCount(session.id));
    const baseline_n: u32 = if (turn_n >= 1) turn_n - 1 else 0;
    var ref_buf: [checkpoint.max_faku_ref_name]u8 = undefined;
    const git_ref = checkpoint.formatFakuSessionTurnRef(&ref_buf, session.id, baseline_n) orelse return false;

    var stdin_buf: [4096]u8 = undefined;
    const stdin = daemon_proxy.writeWorkspaceStdin(&stdin_buf, .{
        .token = model.daemonToken(),
        .operation = .{
            .has_ref = .{
                .cwd = cwd,
                .git_ref = git_ref,
            },
        },
    }) catch return false;

    if (model.daemon_has_ref_key != 0) {
        fx.cancel(model.daemon_has_ref_key);
        fallbackLocalHasRefIfNeeded(model);
        clearDaemonHasRef(model);
    }

    const key = model.next_daemon_key;
    model.next_daemon_key += 1;
    model.daemon_has_ref_key = key;
    model.daemon_has_ref_session = session.id;
    model.daemon_has_ref_ok = false;
    model.daemon_has_ref_turn = turn_n;
    writeFixed(&model.daemon_has_ref_git_ref_storage, &model.daemon_has_ref_git_ref_len, git_ref);
    writeFixed(&model.daemon_has_ref_cwd_storage, &model.daemon_has_ref_cwd_len, cwd);
    writeFixed(&model.daemon_has_ref_sha_storage, &model.daemon_has_ref_sha_len, seed_sha);
    fx.spawn(.{
        .key = key,
        .argv = &.{ model.sidecarPath(), daemon_proxy.SUBCOMMAND, address },
        .stdin = stdin,
        .max_line_bytes = main.daemon_line_bytes,
        .on_line = Effects.lineMsg(.fx_line),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
    return true;
}

pub fn applyDaemonHasRefLine(model: *Model, line: native_sdk.EffectLine) void {
    if (line.key != model.daemon_has_ref_key or model.daemon_has_ref_key == 0) return;
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const parsed = protocol.parseWorkspaceBool(arena_state.allocator(), line.line);
    if (!parsed.ok) return;
    model.daemon_has_ref_ok = true;
    if (!parsed.value) seedStoredBaseline(model);
}

pub fn handleDaemonHasRefExit(model: *Model, fx: *Effects, exit: native_sdk.EffectExit) void {
    if (exit.key != model.daemon_has_ref_key or model.daemon_has_ref_key == 0) return;
    const ok = model.daemon_has_ref_ok;
    if (!ok) fallbackLocalHasRefIfNeeded(model);
    clearDaemonHasRef(model);
    _ = fx;
}

fn fallbackLocalHasRefIfNeeded(model: *Model) void {
    if (model.daemon_has_ref_ok) return;
    seedStoredBaseline(model);
}

fn seedStoredBaseline(model: *Model) void {
    const io = model.store_io orelse return;
    const cwd = model.daemon_has_ref_cwd_storage[0..model.daemon_has_ref_cwd_len];
    const sha = model.daemon_has_ref_sha_storage[0..model.daemon_has_ref_sha_len];
    if (cwd.len == 0 or sha.len == 0) return;
    const session_id = model.daemon_has_ref_session;
    const turn_n = model.daemon_has_ref_turn;
    if (session_id == 0) return;
    checkpoint.seedBaselineIfMissing(
        std.heap.page_allocator,
        io,
        cwd,
        session_id,
        turn_n,
        sha,
    );
}

/// Successful finish: capture a NEW isolated worktree snapshot
/// and name it `turn-{n}`. `{n}` is `turnCount/2` after the
/// user+assistant pair is already appended (same ordinal as
/// Send's `turnCount/2+1` before append). Stores the finish
/// sha as `worktree_turn_end_sha` (same 40-hex rules as
/// start). Then `prepareTurnDiffBase` names `turn-diff-{n}`
/// and stores that 40-hex as `worktree_turn_diff_sha`. Does
/// not write `worktree_snapshot_sha` (LastTurn / Header
/// Rewind keep the send-time sha). Failed capture is quiet.
/// Failed update-ref does not clear the stored shas. Not
/// called on stop/cancel. After a successful local sha
/// capture, also best-effort hello +
/// `WorkspaceOperation::CaptureTurn` when a daemon address is
/// set. No sha / no address / stdin overflow leave local
/// capture alone. Daemon Checkpoint must not replace the
/// stored end / turn-diff shas.
pub fn recordTurnEndIfPossible(model: *Model, fx: *Effects, session_id: u32) void {
    const io = model.store_io orelse return;
    const session = model.sessionById(session_id) orelse return;
    var snap_buf: [rewind.stored_sha_len]u8 = undefined;
    const sha = checkpoint.captureWorktreeCommit(
        std.heap.page_allocator,
        io,
        session.projectPath(),
        &snap_buf,
    ) orelse return;
    session.setWorktreeTurnEndSha(sha);
    const turn_n = checkpoint.fakuFinishTurn(model.turnCount(session_id));
    _ = checkpoint.captureTurnEnd(
        std.heap.page_allocator,
        io,
        session.projectPath(),
        session.id,
        turn_n,
        sha,
    );
    var diff_buf: [rewind.stored_sha_len]u8 = undefined;
    if (checkpoint.prepareTurnDiffBase(
        std.heap.page_allocator,
        io,
        session.projectPath(),
        session.id,
        turn_n,
        &diff_buf,
    )) |diff_sha| {
        session.setWorktreeTurnDiffSha(diff_sha);
    }
    _ = trySpawnDaemonCaptureTurn(model, fx, session, turn_n);
}

/// Best-effort hello + `WorkspaceOperation::CaptureTurn` after
/// local finish capture. Own daemon spawn key on
/// `daemon_capture_turn_key`. Missing address, empty cwd, or
/// Native 4 KiB stdin overflow returns false and leaves local
/// capture alone. Does not replace local sync capture. `turn_count`
/// is the same `fakuFinishTurn` ordinal local end already used.
fn trySpawnDaemonCaptureTurn(model: *Model, fx: *Effects, session: *main.Session, turn_count: u32) bool {
    const address = store.resolveDaemonMirrorAddress(model);
    if (address.len == 0) return false;
    const cwd = session.projectPath();
    if (cwd.len == 0) return false;

    var id_buf: [36]u8 = undefined;
    const wire_id = daemon_proxy.wireUuid(session.id, &id_buf);
    var stdin_buf: [4096]u8 = undefined;
    const stdin = daemon_proxy.writeWorkspaceStdin(&stdin_buf, .{
        .token = model.daemonToken(),
        .operation = .{
            .capture_turn = .{
                .cwd = cwd,
                .session_id = wire_id,
                .turn_count = turn_count,
            },
        },
    }) catch return false;

    if (model.daemon_capture_turn_key != 0) {
        fx.cancel(model.daemon_capture_turn_key);
        model.daemon_capture_turn_key = 0;
        model.daemon_capture_turn_session = 0;
    }

    const key = model.next_daemon_key;
    model.next_daemon_key += 1;
    model.daemon_capture_turn_key = key;
    model.daemon_capture_turn_session = session.id;
    fx.spawn(.{
        .key = key,
        .argv = &.{ model.sidecarPath(), daemon_proxy.SUBCOMMAND, address },
        .stdin = stdin,
        .max_line_bytes = main.daemon_line_bytes,
        .on_line = Effects.lineMsg(.fx_line),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
    return true;
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
            // Fork copies the ordinary cwd (including a materialized
            // worktree dest) and resets kind to `local`. It does not
            // spawn a second worktree or copy `newWorktree` /
            // `baseBranch`.
            session.setWorkspaceLocal();
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
            session.setWorktreeTurnEndSha(from.worktreeTurnEndSha());
            session.setWorktreeTurnDiffSha(from.worktreeTurnDiffSha());
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
    _ = trySpawnDaemonCopySessionRefs(model, fx, source_id, fork_id, through_index);
}

/// Best-effort hello + `WorkspaceOperation::CopySessionRefs` after
/// a local catalog fork. Own daemon spawn key on
/// `daemon_copy_session_refs_key`. Missing address, empty cwd,
/// non-git cwd, or Native 4 KiB stdin overflow returns false and
/// leaves the local fork alone. `through_turn_count` is the same
/// 1-based prompt ordinal CaptureTurnStart uses (`fakuSendTurn` of
/// the last included turn index). Waku copies `0..=through_turn_count`.
fn trySpawnDaemonCopySessionRefs(
    model: *Model,
    fx: *Effects,
    source_id: u32,
    fork_id: u32,
    through_index: u32,
) bool {
    const address = store.resolveDaemonMirrorAddress(model);
    if (address.len == 0) return false;
    const session = model.sessionById(fork_id) orelse return false;
    const cwd = session.projectPath();
    if (cwd.len == 0) return false;
    const io = model.store_io orelse return false;
    if (!rewind.isGitWorkTree(io, cwd)) return false;

    var source_buf: [36]u8 = undefined;
    var target_buf: [36]u8 = undefined;
    const source_wire = daemon_proxy.wireUuid(source_id, &source_buf);
    const target_wire = daemon_proxy.wireUuid(fork_id, &target_buf);
    const through_turn_count = checkpoint.fakuSendTurn(through_index);
    var stdin_buf: [4096]u8 = undefined;
    const stdin = daemon_proxy.writeWorkspaceStdin(&stdin_buf, .{
        .token = model.daemonToken(),
        .operation = .{
            .copy_session_refs = .{
                .cwd = cwd,
                .source_session_id = source_wire,
                .target_session_id = target_wire,
                .through_turn_count = through_turn_count,
            },
        },
    }) catch return false;

    if (model.daemon_copy_session_refs_key != 0) {
        fx.cancel(model.daemon_copy_session_refs_key);
        model.daemon_copy_session_refs_key = 0;
        model.daemon_copy_session_refs_session = 0;
    }

    const key = model.next_daemon_key;
    model.next_daemon_key += 1;
    model.daemon_copy_session_refs_key = key;
    model.daemon_copy_session_refs_session = fork_id;
    fx.spawn(.{
        .key = key,
        .argv = &.{ model.sidecarPath(), daemon_proxy.SUBCOMMAND, address },
        .stdin = stdin,
        .max_line_bytes = main.daemon_line_bytes,
        .on_line = Effects.lineMsg(.fx_line),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
    return true;
}

/// Restore the last Send-time workspace and drop that prompt's
/// turns. Prefers `restoreRef(worktree_snapshot_sha)` when a
/// snapshot is stored (does not `reset --hard`; HEAD stays).
/// On snapshot success, clear the start, turn-end, and
/// turn-diff slots so a second Rewind does not replay the
/// same tree. When no snapshot is stored, `reset --hard`
/// the latest Send-time HEAD. Failed git is a no-op (ref,
/// snapshot, and transcript stay). Does not change
/// `fx_session_id`.
pub fn applyRewindIfPossible(model: *Model, fx: *Effects) void {
    const io = model.store_io orelse return;
    const session = model.sessionById(model.selected) orelse return;
    const sha = session.latestRewindSha() orelse return;
    const snapshot = session.worktreeSnapshotSha();
    if (rewind.isStoredSha(snapshot)) {
        if (!checkpoint.restoreRef(std.heap.page_allocator, io, session.projectPath(), snapshot)) return;
        session.clearWorktreeSnapshotSha();
        session.clearWorktreeTurnEndSha();
        session.clearWorktreeTurnDiffSha();
    } else if (!rewind.resetHard(std.heap.page_allocator, io, session.projectPath(), sha)) {
        return;
    }
    session.popLatestRewindRef();
    model.dropLastPromptTurns(session.id);
    store.persistIfPossible(model, session.id, fx);
}

fn findCaptureTurnStartSpawn(fx: *Effects, key: u64) ?@TypeOf(fx.pendingSpawnAt(0).?) {
    var i: usize = 0;
    while (fx.pendingSpawnAt(i)) |spawn| : (i += 1) {
        if (spawn.key != key) continue;
        if (!daemon_proxy.isSidecarArgv(spawn.argv)) continue;
        if (std.mem.indexOf(u8, spawn.stdin, "\"type\":\"captureTurnStart\"") == null) continue;
        return spawn;
    }
    return null;
}

fn anyCaptureTurnStartSpawn(fx: *Effects) bool {
    var i: usize = 0;
    while (fx.pendingSpawnAt(i)) |spawn| : (i += 1) {
        if (daemon_proxy.isSidecarArgv(spawn.argv) and
            std.mem.indexOf(u8, spawn.stdin, "\"type\":\"captureTurnStart\"") != null) return true;
    }
    return false;
}

fn findHasRefSpawn(fx: *Effects, key: u64) ?@TypeOf(fx.pendingSpawnAt(0).?) {
    var i: usize = 0;
    while (fx.pendingSpawnAt(i)) |spawn| : (i += 1) {
        if (spawn.key != key) continue;
        if (!daemon_proxy.isSidecarArgv(spawn.argv)) continue;
        if (std.mem.indexOf(u8, spawn.stdin, "\"type\":\"hasRef\"") == null) continue;
        return spawn;
    }
    return null;
}

fn anyHasRefSpawn(fx: *Effects) bool {
    var i: usize = 0;
    while (fx.pendingSpawnAt(i)) |spawn| : (i += 1) {
        if (daemon_proxy.isSidecarArgv(spawn.argv) and
            std.mem.indexOf(u8, spawn.stdin, "\"type\":\"hasRef\"") != null) return true;
    }
    return false;
}

fn makeGitCwd(io: std.Io, path: []const u8) !void {
    try std.Io.Dir.cwd().createDirPath(io, path);
    var git_buf: [256]u8 = undefined;
    const git = try std.fmt.bufPrint(&git_buf, "{s}{s}.git", .{ path, std.fs.path.sep_str });
    try std.Io.Dir.cwd().createDirPath(io, git);
}

fn findCaptureTurnSpawn(fx: *Effects, key: u64) ?@TypeOf(fx.pendingSpawnAt(0).?) {
    var i: usize = 0;
    while (fx.pendingSpawnAt(i)) |spawn| : (i += 1) {
        if (spawn.key != key) continue;
        if (!daemon_proxy.isSidecarArgv(spawn.argv)) continue;
        if (std.mem.indexOf(u8, spawn.stdin, "\"type\":\"captureTurn\"") == null) continue;
        if (std.mem.indexOf(u8, spawn.stdin, "\"type\":\"captureTurnStart\"") != null) continue;
        return spawn;
    }
    return null;
}

fn anyCaptureTurnSpawn(fx: *Effects) bool {
    var i: usize = 0;
    while (fx.pendingSpawnAt(i)) |spawn| : (i += 1) {
        if (daemon_proxy.isSidecarArgv(spawn.argv) and
            std.mem.indexOf(u8, spawn.stdin, "\"type\":\"captureTurn\"") != null and
            std.mem.indexOf(u8, spawn.stdin, "\"type\":\"captureTurnStart\"") == null) return true;
    }
    return false;
}

fn findCopySessionRefsSpawn(fx: *Effects, key: u64) ?@TypeOf(fx.pendingSpawnAt(0).?) {
    var i: usize = 0;
    while (fx.pendingSpawnAt(i)) |spawn| : (i += 1) {
        if (spawn.key != key) continue;
        if (!daemon_proxy.isSidecarArgv(spawn.argv)) continue;
        if (std.mem.indexOf(u8, spawn.stdin, "\"type\":\"copySessionRefs\"") == null) continue;
        return spawn;
    }
    return null;
}

fn anyCopySessionRefsSpawn(fx: *Effects) bool {
    var i: usize = 0;
    while (fx.pendingSpawnAt(i)) |spawn| : (i += 1) {
        if (daemon_proxy.isSidecarArgv(spawn.argv) and
            std.mem.indexOf(u8, spawn.stdin, "\"type\":\"copySessionRefs\"") != null) return true;
    }
    return false;
}

fn initFinishRepo(allocator: std.mem.Allocator, io: std.Io, path: []const u8) !void {
    try std.Io.Dir.cwd().createDirPath(io, path);
    try runFinishGit(allocator, io, &.{ "git", "-C", path, "init" });
    var readme_buf: [std.fs.max_path_bytes]u8 = undefined;
    const readme = try std.fmt.bufPrint(&readme_buf, "{s}{s}README", .{ path, std.fs.path.sep_str });
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = readme, .data = "finish\n" });
    try runFinishGit(allocator, io, &.{ "git", "-C", path, "add", "README" });
    try runFinishGit(allocator, io, &.{
        "git",
        "-C",
        path,
        "-c",
        "user.email=capture-turn@test",
        "-c",
        "user.name=CaptureTurn",
        "-c",
        checkpoint.commit_gpgsign,
        "commit",
        "-m",
        "init",
    });
}

fn runFinishGit(allocator: std.mem.Allocator, io: std.Io, argv: []const []const u8) !void {
    const result = try std.process.run(allocator, io, .{
        .argv = argv,
        .stdout_limit = .limited(1024),
        .stderr_limit = .limited(4096),
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    if (result.term != .exited or result.term.exited != 0) return error.GitFailed;
}

test "recordRewindRefIfPossible with a daemon address spawns CaptureTurnStart sidecar" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/capture-turn-start-daemon", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = std.testing.io;
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    const id = model.addSession("capture turn start", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);

    recordRewindRefIfPossible(&model, &fx, id);
    try std.testing.expect(model.daemon_capture_turn_start_key != 0);
    try std.testing.expectEqual(id, model.daemon_capture_turn_start_session);
    const sidecar = findCaptureTurnStartSpawn(&fx, model.daemon_capture_turn_start_key) orelse return error.MissingDaemonCaptureTurnStart;
    try std.testing.expectEqualStrings("faku", sidecar.argv[0]);
    try std.testing.expectEqualStrings(daemon_proxy.SUBCOMMAND, sidecar.argv[1]);
    try std.testing.expectEqualStrings("127.0.0.1:8787", sidecar.argv[2]);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"hello\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"workspace\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"captureTurnStart\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, project) != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"sessionId\":\"" ++ protocol.NIL_UUID ++ "\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"runtimeId\":\"" ++ protocol.NIL_UUID ++ "\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"prompt\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"attachSession\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"captureTurn\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"inspectCommit\"") == null);
    var id_buf: [36]u8 = undefined;
    const wire_id = daemon_proxy.wireUuid(id, &id_buf);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, wire_id) != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"turnCount\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "session_id") == null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "turn_count") == null);
}

test "recordRewindRefIfPossible without a daemon address does not spawn CaptureTurnStart" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/capture-turn-start-local", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = std.testing.io;
    model.setSidecarPath("faku");
    const id = model.addSession("capture turn start local", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);
    try std.testing.expectEqual(@as(usize, 0), store.resolveDaemonMirrorAddress(&model).len);

    recordRewindRefIfPossible(&model, &fx, id);
    try std.testing.expectEqual(@as(u64, 0), model.daemon_capture_turn_start_key);
    try std.testing.expect(!anyCaptureTurnStartSpawn(&fx));
}

test "CaptureTurnStart sidecar failure does not clear a stored worktree snapshot sha" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/capture-turn-start-keep-sha", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = std.testing.io;
    model.fx_probe_started = true;
    model.setLastDaemonAddress("10.0.0.2:9");
    model.setSidecarPath("faku");
    const id = model.addSession("keep sha", .fx);
    model.selected = id;
    const stored_sha = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    if (model.sessionById(id)) |session| {
        session.setProjectPath(project);
        session.setWorktreeSnapshotSha(stored_sha);
    }

    recordRewindRefIfPossible(&model, &fx, id);
    try std.testing.expectEqualStrings(stored_sha, model.sessionByIdConst(id).?.worktreeSnapshotSha());
    const sidecar = findCaptureTurnStartSpawn(&fx, model.daemon_capture_turn_start_key) orelse return error.MissingDaemonCaptureTurnStartFail;
    const key = sidecar.key;
    try fx.feedLine(key, "{\"type\":\"rejected\",\"message\":\"nope\"}");
    while (fx.takeMsg()) |msg| main.update(&model, msg, &fx);
    try fx.feedExit(key, 1);
    while (fx.takeMsg()) |msg| main.update(&model, msg, &fx);

    try std.testing.expectEqual(@as(u64, 0), model.daemon_capture_turn_start_key);
    try std.testing.expectEqualStrings(stored_sha, model.sessionByIdConst(id).?.worktreeSnapshotSha());
    try std.testing.expect(!model.is_streaming());
}

test "recordRewindRefIfPossible with a daemon address and git cwd spawns HasRef sidecar" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/has-ref-daemon", .{tmp.sub_path[0..]});
    try makeGitCwd(std.testing.io, project);

    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = std.testing.io;
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setDaemonToken("secret");
    model.setSidecarPath("faku");
    const id = model.addSession("has ref", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);

    recordRewindRefIfPossible(&model, &fx, id);
    try std.testing.expect(model.daemon_has_ref_key != 0);
    try std.testing.expectEqual(id, model.daemon_has_ref_session);
    const sidecar = findHasRefSpawn(&fx, model.daemon_has_ref_key) orelse return error.MissingDaemonHasRef;
    try std.testing.expectEqualStrings("faku", sidecar.argv[0]);
    try std.testing.expectEqualStrings(daemon_proxy.SUBCOMMAND, sidecar.argv[1]);
    try std.testing.expectEqualStrings("127.0.0.1:8787", sidecar.argv[2]);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"hello\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"token\":\"secret\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"workspace\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"hasRef\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, project) != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"git_ref\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"gitRef\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"sessionId\":\"" ++ protocol.NIL_UUID ++ "\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"runtimeId\":\"" ++ protocol.NIL_UUID ++ "\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "refs/faku/session-") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"prompt\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"attachSession\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"captureTurnStart\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"deleteSessionRefs\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "amend") == null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "force") == null);
    try std.testing.expect(sidecar.key != model.daemon_spawn_key);
    try std.testing.expect(sidecar.key != model.daemon_capture_turn_start_key);
}

test "recordRewindRefIfPossible without a daemon address does not spawn HasRef" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/has-ref-local", .{tmp.sub_path[0..]});
    try makeGitCwd(std.testing.io, project);

    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = std.testing.io;
    model.setSidecarPath("faku");
    const id = model.addSession("has ref local", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);
    try std.testing.expectEqual(@as(usize, 0), store.resolveDaemonMirrorAddress(&model).len);

    recordRewindRefIfPossible(&model, &fx, id);
    try std.testing.expectEqual(@as(u64, 0), model.daemon_has_ref_key);
    try std.testing.expect(!anyHasRefSpawn(&fx));
}

test "recordRewindRefIfPossible with a daemon address and non-git cwd does not spawn HasRef" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/has-ref-nongit", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = std.testing.io;
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    const id = model.addSession("has ref nongit", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);

    recordRewindRefIfPossible(&model, &fx, id);
    try std.testing.expectEqual(@as(u64, 0), model.daemon_has_ref_key);
    try std.testing.expect(!anyHasRefSpawn(&fx));
}

test "HasRef sidecar miss falls back to local hasFakuRef behavior" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/has-ref-fallback", .{tmp.sub_path[0..]});
    try initFinishRepo(std.testing.allocator, std.testing.io, project);

    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = std.testing.io;
    model.fx_probe_started = true;
    model.setLastDaemonAddress("10.0.0.2:9");
    model.setSidecarPath("faku");
    const id = model.addSession("has ref fallback", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);

    recordRewindRefIfPossible(&model, &fx, id);
    const sha = model.sessionByIdConst(id).?.worktreeSnapshotSha();
    try std.testing.expect(rewind.isStoredSha(sha));
    var baseline_buf: [checkpoint.max_faku_ref_name]u8 = undefined;
    const baseline = checkpoint.formatFakuSessionTurnRef(&baseline_buf, id, 0) orelse return error.MissingBaseline;
    try std.testing.expect(!checkpoint.hasFakuRef(std.testing.allocator, std.testing.io, project, baseline));

    const sidecar = findHasRefSpawn(&fx, model.daemon_has_ref_key) orelse return error.MissingDaemonHasRefFail;
    const key = sidecar.key;
    try fx.feedLine(key, "{\"type\":\"rejected\",\"message\":\"nope\"}");
    while (fx.takeMsg()) |msg| main.update(&model, msg, &fx);
    try fx.feedExit(key, 1);
    while (fx.takeMsg()) |msg| main.update(&model, msg, &fx);

    try std.testing.expectEqual(@as(u64, 0), model.daemon_has_ref_key);
    try std.testing.expect(checkpoint.hasFakuRef(std.testing.allocator, std.testing.io, project, baseline));
    try std.testing.expect(rewind.isStoredSha(model.sessionByIdConst(id).?.worktreeSnapshotSha()));
    try std.testing.expect(!model.is_streaming());
}

test "HasRef sidecar non-bool falls back to local hasFakuRef behavior" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/has-ref-nonbool", .{tmp.sub_path[0..]});
    try initFinishRepo(std.testing.allocator, std.testing.io, project);

    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = std.testing.io;
    model.fx_probe_started = true;
    model.setLastDaemonAddress("10.0.0.2:9");
    model.setSidecarPath("faku");
    const id = model.addSession("has ref nonbool", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);

    recordRewindRefIfPossible(&model, &fx, id);
    var baseline_buf: [checkpoint.max_faku_ref_name]u8 = undefined;
    const baseline = checkpoint.formatFakuSessionTurnRef(&baseline_buf, id, 0) orelse return error.MissingBaseline;
    try std.testing.expect(!checkpoint.hasFakuRef(std.testing.allocator, std.testing.io, project, baseline));

    const sidecar = findHasRefSpawn(&fx, model.daemon_has_ref_key) orelse return error.MissingDaemonHasRefAck;
    const key = sidecar.key;
    try fx.feedLine(key, "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000014\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"workspace\",\"result\":{\"type\":\"ack\"}}}}");
    while (fx.takeMsg()) |msg| main.update(&model, msg, &fx);
    try fx.feedExit(key, 0);
    while (fx.takeMsg()) |msg| main.update(&model, msg, &fx);

    try std.testing.expectEqual(@as(u64, 0), model.daemon_has_ref_key);
    try std.testing.expect(checkpoint.hasFakuRef(std.testing.allocator, std.testing.io, project, baseline));
}

test "HasRef Bool true skips local baseline seed" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/has-ref-true", .{tmp.sub_path[0..]});
    try initFinishRepo(std.testing.allocator, std.testing.io, project);

    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = std.testing.io;
    model.fx_probe_started = true;
    model.setLastDaemonAddress("10.0.0.2:9");
    model.setSidecarPath("faku");
    const id = model.addSession("has ref true", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);

    recordRewindRefIfPossible(&model, &fx, id);
    var baseline_buf: [checkpoint.max_faku_ref_name]u8 = undefined;
    const baseline = checkpoint.formatFakuSessionTurnRef(&baseline_buf, id, 0) orelse return error.MissingBaseline;
    try std.testing.expect(!checkpoint.hasFakuRef(std.testing.allocator, std.testing.io, project, baseline));

    const sidecar = findHasRefSpawn(&fx, model.daemon_has_ref_key) orelse return error.MissingDaemonHasRefTrue;
    const key = sidecar.key;
    try fx.feedLine(key, "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000014\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"workspace\",\"result\":{\"type\":\"bool\",\"value\":true}}}}");
    while (fx.takeMsg()) |msg| main.update(&model, msg, &fx);
    try fx.feedExit(key, 0);
    while (fx.takeMsg()) |msg| main.update(&model, msg, &fx);

    try std.testing.expectEqual(@as(u64, 0), model.daemon_has_ref_key);
    try std.testing.expect(!checkpoint.hasFakuRef(std.testing.allocator, std.testing.io, project, baseline));
}

test "recordTurnEndIfPossible with a daemon address spawns CaptureTurn sidecar after local end" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/capture-turn-daemon", .{tmp.sub_path[0..]});
    try initFinishRepo(std.testing.allocator, std.testing.io, project);

    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = std.testing.io;
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    const id = model.addSession("capture turn end", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);
    _ = model.appendTurn(id, .user, "ship the capture cut");
    _ = model.appendTurn(id, .assistant, "done");

    recordTurnEndIfPossible(&model, &fx, id);
    try std.testing.expect(model.sessionByIdConst(id).?.worktreeTurnEndSha().len == rewind.stored_sha_len);
    try std.testing.expect(model.daemon_capture_turn_key != 0);
    try std.testing.expectEqual(id, model.daemon_capture_turn_session);
    try std.testing.expectEqual(@as(u64, 0), model.daemon_capture_turn_start_key);
    const sidecar = findCaptureTurnSpawn(&fx, model.daemon_capture_turn_key) orelse return error.MissingDaemonCaptureTurn;
    try std.testing.expectEqualStrings("faku", sidecar.argv[0]);
    try std.testing.expectEqualStrings(daemon_proxy.SUBCOMMAND, sidecar.argv[1]);
    try std.testing.expectEqualStrings("127.0.0.1:8787", sidecar.argv[2]);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"hello\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"workspace\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"captureTurn\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"captureTurnStart\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, project) != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"sessionId\":\"" ++ protocol.NIL_UUID ++ "\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"runtimeId\":\"" ++ protocol.NIL_UUID ++ "\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"prompt\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"attachSession\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"inspectCommit\"") == null);
    var id_buf: [36]u8 = undefined;
    const wire_id = daemon_proxy.wireUuid(id, &id_buf);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, wire_id) != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"turnCount\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "session_id") == null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "turn_count") == null);
}

test "recordTurnEndIfPossible without a daemon address does not spawn CaptureTurn" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/capture-turn-local", .{tmp.sub_path[0..]});
    try initFinishRepo(std.testing.allocator, std.testing.io, project);

    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = std.testing.io;
    model.setSidecarPath("faku");
    const id = model.addSession("capture turn end local", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);
    _ = model.appendTurn(id, .user, "no daemon capture");
    _ = model.appendTurn(id, .assistant, "ok");
    try std.testing.expectEqual(@as(usize, 0), store.resolveDaemonMirrorAddress(&model).len);

    recordTurnEndIfPossible(&model, &fx, id);
    try std.testing.expect(model.sessionByIdConst(id).?.worktreeTurnEndSha().len == rewind.stored_sha_len);
    try std.testing.expectEqual(@as(u64, 0), model.daemon_capture_turn_key);
    try std.testing.expect(!anyCaptureTurnSpawn(&fx));
}

test "recordTurnEndIfPossible without a local end sha does not spawn CaptureTurn" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/capture-turn-nongit", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = std.testing.io;
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    const id = model.addSession("capture turn no sha", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);
    _ = model.appendTurn(id, .user, "no git");
    _ = model.appendTurn(id, .assistant, "ok");

    recordTurnEndIfPossible(&model, &fx, id);
    try std.testing.expectEqual(@as(usize, 0), model.sessionByIdConst(id).?.worktreeTurnEndSha().len);
    try std.testing.expectEqual(@as(u64, 0), model.daemon_capture_turn_key);
    try std.testing.expect(!anyCaptureTurnSpawn(&fx));
}

test "CaptureTurn sidecar checkpoint does not replace stored turn-end shas" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/capture-turn-keep-sha", .{tmp.sub_path[0..]});
    try initFinishRepo(std.testing.allocator, std.testing.io, project);

    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = std.testing.io;
    model.fx_probe_started = true;
    model.setLastDaemonAddress("10.0.0.2:9");
    model.setSidecarPath("faku");
    const id = model.addSession("keep end sha", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);
    _ = model.appendTurn(id, .user, "keep sha");
    _ = model.appendTurn(id, .assistant, "ok");

    recordTurnEndIfPossible(&model, &fx, id);
    const end_sha = model.sessionByIdConst(id).?.worktreeTurnEndSha();
    try std.testing.expect(end_sha.len == rewind.stored_sha_len);
    var end_copy: [rewind.stored_sha_len]u8 = undefined;
    @memcpy(&end_copy, end_sha);
    const diff_sha = model.sessionByIdConst(id).?.worktreeTurnDiffSha();
    var diff_copy: [rewind.stored_sha_len]u8 = undefined;
    const diff_len = diff_sha.len;
    if (diff_len != 0) @memcpy(diff_copy[0..diff_len], diff_sha);

    const sidecar = findCaptureTurnSpawn(&fx, model.daemon_capture_turn_key) orelse return error.MissingDaemonCaptureTurnFail;
    const key = sidecar.key;
    try fx.feedLine(key, "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000014\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"workspace\",\"result\":{\"type\":\"checkpoint\",\"checkpoint\":{\"turn_count\":99,\"git_ref\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"status\":\"Ready\",\"files\":[],\"additions\":4,\"deletions\":1,\"created_at\":\"2026-09-05T00:00:00Z\"}}}}}");
    while (fx.takeMsg()) |msg| main.update(&model, msg, &fx);
    try fx.feedExit(key, 0);
    while (fx.takeMsg()) |msg| main.update(&model, msg, &fx);

    try std.testing.expectEqual(@as(u64, 0), model.daemon_capture_turn_key);
    try std.testing.expectEqualStrings(&end_copy, model.sessionByIdConst(id).?.worktreeTurnEndSha());
    try std.testing.expectEqualStrings(diff_copy[0..diff_len], model.sessionByIdConst(id).?.worktreeTurnDiffSha());
    try std.testing.expect(!model.is_streaming());
}

test "forkSelectedThrough with a daemon address spawns CopySessionRefs sidecar" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/copy-session-refs-daemon", .{tmp.sub_path[0..]});
    try initFinishRepo(std.testing.allocator, std.testing.io, project);

    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = std.testing.io;
    model.task_state_loaded = true;
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    const id = model.addSession("copy session refs", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);
    _ = model.appendTurn(id, .user, "fork me");
    _ = model.appendTurn(id, .assistant, "ok");

    forkSelectedThrough(&model, &fx, 1);
    const fork_id = model.selected;
    try std.testing.expect(fork_id != id);
    try std.testing.expectEqual(@as(u32, 2), model.turnCount(fork_id));
    try std.testing.expect(model.daemon_copy_session_refs_key != 0);
    try std.testing.expectEqual(fork_id, model.daemon_copy_session_refs_session);
    const sidecar = findCopySessionRefsSpawn(&fx, model.daemon_copy_session_refs_key) orelse return error.MissingDaemonCopySessionRefs;
    try std.testing.expectEqualStrings("faku", sidecar.argv[0]);
    try std.testing.expectEqualStrings(daemon_proxy.SUBCOMMAND, sidecar.argv[1]);
    try std.testing.expectEqualStrings("127.0.0.1:8787", sidecar.argv[2]);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"hello\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"workspace\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"copySessionRefs\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, project) != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"sessionId\":\"" ++ protocol.NIL_UUID ++ "\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"runtimeId\":\"" ++ protocol.NIL_UUID ++ "\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"prompt\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"attachSession\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"captureTurnStart\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"captureTurn\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"deleteSessionRefs\"") == null);
    var source_buf: [36]u8 = undefined;
    var target_buf: [36]u8 = undefined;
    const source_wire = daemon_proxy.wireUuid(id, &source_buf);
    const target_wire = daemon_proxy.wireUuid(fork_id, &target_buf);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, source_wire) != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, target_wire) != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"source_session_id\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"target_session_id\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"through_turn_count\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "sourceSessionId") == null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "targetSessionId") == null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "throughTurnCount") == null);
}

test "forkSelectedThrough without a daemon address does not spawn CopySessionRefs" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/copy-session-refs-local", .{tmp.sub_path[0..]});
    try initFinishRepo(std.testing.allocator, std.testing.io, project);

    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = std.testing.io;
    model.task_state_loaded = true;
    model.setSidecarPath("faku");
    const id = model.addSession("copy session refs local", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);
    _ = model.appendTurn(id, .user, "no daemon copy");
    _ = model.appendTurn(id, .assistant, "ok");
    try std.testing.expectEqual(@as(usize, 0), store.resolveDaemonMirrorAddress(&model).len);

    forkSelectedThrough(&model, &fx, 1);
    const fork_id = model.selected;
    try std.testing.expect(fork_id != id);
    try std.testing.expectEqual(@as(u32, 2), model.turnCount(fork_id));
    try std.testing.expectEqual(@as(u64, 0), model.daemon_copy_session_refs_key);
    try std.testing.expect(!anyCopySessionRefsSpawn(&fx));
}

test "CopySessionRefs sidecar failure does not break the local fork" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/copy-session-refs-keep", .{tmp.sub_path[0..]});
    try initFinishRepo(std.testing.allocator, std.testing.io, project);

    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = std.testing.io;
    model.task_state_loaded = true;
    model.fx_probe_started = true;
    model.setLastDaemonAddress("10.0.0.2:9");
    model.setSidecarPath("faku");
    const id = model.addSession("keep fork", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);
    _ = model.appendTurn(id, .user, "keep fork");
    _ = model.appendTurn(id, .assistant, "ok");

    forkSelectedThrough(&model, &fx, 1);
    const fork_id = model.selected;
    try std.testing.expect(fork_id != id);
    try std.testing.expectEqual(@as(u32, 2), model.turnCount(fork_id));
    const sidecar = findCopySessionRefsSpawn(&fx, model.daemon_copy_session_refs_key) orelse return error.MissingDaemonCopySessionRefsFail;
    const key = sidecar.key;
    try fx.feedLine(key, "{\"type\":\"rejected\",\"message\":\"nope\"}");
    while (fx.takeMsg()) |msg| main.update(&model, msg, &fx);
    try fx.feedExit(key, 1);
    while (fx.takeMsg()) |msg| main.update(&model, msg, &fx);

    try std.testing.expectEqual(@as(u64, 0), model.daemon_copy_session_refs_key);
    try std.testing.expectEqual(fork_id, model.selected);
    try std.testing.expectEqual(@as(u32, 2), model.turnCount(fork_id));
    try std.testing.expectEqual(@as(u32, 2), model.turnCount(id));
    try std.testing.expect(!model.is_streaming());
}

test "forkSelectedThrough with a daemon address and non-git cwd does not spawn CopySessionRefs" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/copy-session-refs-nongit", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = std.testing.io;
    model.task_state_loaded = true;
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    const id = model.addSession("copy session refs nongit", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);
    _ = model.appendTurn(id, .user, "no git");
    _ = model.appendTurn(id, .assistant, "ok");

    forkSelectedThrough(&model, &fx, 1);
    const fork_id = model.selected;
    try std.testing.expect(fork_id != id);
    try std.testing.expectEqual(@as(u32, 2), model.turnCount(fork_id));
    try std.testing.expectEqual(@as(u64, 0), model.daemon_copy_session_refs_key);
    try std.testing.expect(!anyCopySessionRefsSpawn(&fx));
}
