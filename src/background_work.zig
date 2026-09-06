//! First-cut daemon `Command::RefreshBackgroundWork` and
//! `Command::StopBackgroundWork`.
//!
//! When the right-panel Background tab is selected or Environment
//! Summary opens, and `WAKU_DAEMON_ADDRESS` or persisted
//! `last_daemon_address` is set **and** the selected session has a
//! usable `runtimeId`, Faku one-shots hello + `refreshBackgroundWork`
//! (request-frame `sessionId` + `runtimeId`, same as cancel / steer /
//! goal). Ok is typically Ack; `backgroundWork` events on sidecar
//! stdout apply `reconcileProcesses` / `reconcileLive` / `upsert` /
//! `outputDelta` / `stopFailed` into daemon-sourced registry rows.
//! Native 4 KiB stdin overflow /
//! sidecar failure / unusable parse / missing address / missing
//! runtimeId keep today's local Process / Monitor / Subagent
//! behavior.
//!
//! First-cut Waku `BACKGROUND_WORK_REFRESH_INTERVAL` (5s) tick
//! ships as `maybeRefresh` on the existing update / stream tick
//! (same `now_ms` piggyback as the 100ms output cache; Native has
//! no dedicated timer). It reuses `trySpawn` (hello +
//! `refreshBackgroundWork`) for **one** session when a daemon
//! address and usable `runtimeId` are set (Waku
//! `maybe_refresh_background_work`: `selected == session ||
//! registry.has_live`). Prefer selected when it has a usable
//! `runtimeId` and the UI cares: Background tab showing,
//! Environment Summary open, or that selected session has live
//! Process / Monitor / Subagent / daemon-sourced rows. Else one
//! other session with live rows, a usable `runtimeId`, and a
//! daemon address (catalog fill order, lowest session id). One
//! in-flight sidecar (`daemon_background_work_key`); do not spawn
//! N concurrent refreshes. Throttled to 5s from
//! `last_background_work_refresh_ms` (runtime-only; stamped when
//! a spawn is actually attempted, open path and tick path; global
//! this cut, not a per-session map). Unset last fires immediately
//! on the first eligible tick. An in-flight refresh sidecar
//! skips quietly — the tick does not cancel/re-spawn. Open-path
//! `refresh` remains the immediate selected-session reconcile
//! (cancel in-flight then `trySpawn` selected). First-cut 1s
//! `BACKGROUND_WORK_TICK_INTERVAL` elapsed duration labels ship
//! in `environment_summary.maybeTickElapsed` (same `now_ms`
//! piggyback; Native has no dedicated timer). Not full
//! BackgroundWorkRegistry / GPUI SharedString parity. First-cut
//! `outputDelta` appends a bounded last-window onto an existing
//! daemon-sourced row; first-cut `stopFailed` restores a live
//! Stopping row. Local Faku-side Process / Monitor /
//! Subagent Stop / Dismiss remains. Hello stays v4.
//!
//! Background Stop on a daemon-sourced live row prefers hello +
//! `stopBackgroundWork` (`key` + `controlId`) on a distinct spawn
//! key when a daemon address, usable `runtimeId`, and usable
//! `controlId` are present. The row is marked Stopping /
//! non-stoppable locally (Waku StopRequested) and stays that way
//! until a later refresh upsert settles it. Miss / overflow / no
//! daemon / no controlId fall back to Faku-side dismiss.

const std = @import("std");
const native_sdk = @import("native_sdk");
const main = @import("main.zig");
const daemon_proxy = @import("daemon_proxy.zig");
const protocol = @import("protocol.zig");
const store = @import("store.zig");
const environment_summary = @import("environment_summary.zig");

const Model = main.Model;
const Effects = main.Effects;

/// Waku `BACKGROUND_WORK_REFRESH_INTERVAL`. First-cut 5s daemon
/// `refreshBackgroundWork` throttle, piggybacked off `model.now_ms`
/// / the update tick. Native has no dedicated timer this cut.
pub const background_work_refresh_interval_ms: i64 = 5000;

/// Waku `BACKGROUND_WORK_TICK_INTERVAL`. First-cut 1s elapsed
/// duration labels live in `environment_summary.maybeTickElapsed`.
pub const background_work_tick_interval_ms = environment_summary.background_work_tick_interval_ms;

fn cancelInFlight(model: *Model, fx: *Effects) void {
    if (model.daemon_background_work_key == 0) return;
    fx.cancel(model.daemon_background_work_key);
    model.daemon_background_work_key = 0;
    model.daemon_background_work_session = 0;
}

fn cancelStopInFlight(model: *Model, fx: *Effects) void {
    if (model.daemon_stop_background_work_key == 0) return;
    fx.cancel(model.daemon_stop_background_work_key);
    model.daemon_stop_background_work_key = 0;
    model.daemon_stop_background_work_session = 0;
    model.daemon_stop_background_id_len = 0;
}

/// Drop an in-flight refreshBackgroundWork sidecar. Safe when none
/// is live. Does not clear local or daemon-sourced registry rows.
pub fn cancel(model: *Model, fx: *Effects) void {
    cancelInFlight(model, fx);
}

/// Prefer hello + `refreshBackgroundWork` when a daemon address and
/// a usable session `runtimeId` are set. Missing address / runtimeId
/// / Native 4 KiB stdin overflow keep local Background rows.
/// Cancels an in-flight refresh sidecar so open/select is immediate.
/// Open-path always targets the selected session.
pub fn refresh(model: *Model, fx: *Effects) void {
    cancelInFlight(model, fx);
    _ = trySpawn(model, fx, model.selected);
}

/// First-cut Waku `BACKGROUND_WORK_REFRESH_INTERVAL` tick. Reuses
/// `trySpawn` (does not duplicate sidecar stdin). Skips when a
/// refresh sidecar is already in flight. Prefers selected when UI
/// care + usable `runtimeId`; else one other live session. Open-path
/// `refresh` stays the immediate selected reconcile.
pub fn maybeRefresh(model: *Model, fx: *Effects) void {
    if (model.daemon_background_work_key != 0) return;
    const session_id = refreshTargetSession(model) orelse return;
    if (model.last_background_work_refresh_ms) |last| {
        if (model.now_ms >= last and model.now_ms - last < background_work_refresh_interval_ms) {
            return;
        }
    }
    _ = trySpawn(model, fx, session_id);
}

fn uiWantsSelectedRefresh(model: *const Model) bool {
    if (model.right_panel_showing_background()) return true;
    if (model.environment_summary_open) return true;
    return sessionHasLiveBackground(model, model.selected);
}

fn sessionHasUsableRuntimeId(model: *const Model, session_id: u32) bool {
    const session = model.sessionByIdConst(session_id) orelse return false;
    return protocol.isUsableRuntimeId(session.runtimeId());
}

fn sessionHasLiveBackground(model: *const Model, session_id: u32) bool {
    if (session_id == 0) return false;
    if (model.is_streaming() and model.streaming_session == session_id) return true;
    var i: u32 = 0;
    while (i < model.background_monitor_count) : (i += 1) {
        const slot = &model.background_monitors[i];
        if (slot.settled == .none and slot.session_id == session_id) return true;
    }
    i = 0;
    while (i < model.background_subagent_count) : (i += 1) {
        const slot = &model.background_subagents[i];
        if (slot.settled == .none and slot.session_id == session_id) return true;
    }
    i = 0;
    while (i < model.background_daemon_count) : (i += 1) {
        const slot = &model.background_daemon[i];
        if (slot.settled == .none and slot.session_id == session_id) return true;
    }
    return false;
}

/// Waku `selected == session || registry.has_live`, one sidecar.
/// Prefer selected when it is a refresh candidate; else the lowest
/// other session id with live rows + usable `runtimeId`.
fn refreshTargetSession(model: *const Model) ?u32 {
    if (sessionHasUsableRuntimeId(model, model.selected) and uiWantsSelectedRefresh(model)) {
        return model.selected;
    }
    return firstLiveFanoutSession(model);
}

fn firstLiveFanoutSession(model: *const Model) ?u32 {
    var chosen: ?u32 = null;
    for (model.sessions()) |session| {
        if (session.id == 0 or session.id == model.selected) continue;
        if (!protocol.isUsableRuntimeId(session.runtimeId())) continue;
        if (!sessionHasLiveBackground(model, session.id)) continue;
        if (chosen == null or session.id < chosen.?) chosen = session.id;
    }
    return chosen;
}

fn trySpawn(model: *Model, fx: *Effects, session_id: u32) bool {
    const address = store.resolveDaemonMirrorAddress(model);
    if (address.len == 0) return false;
    const session = model.sessionById(session_id) orelse return false;
    if (!protocol.isUsableRuntimeId(session.runtimeId())) return false;

    var id_buf: [36]u8 = undefined;
    const wire_id = daemon_proxy.wireUuid(session.id, &id_buf);
    var stdin_buf: [4096]u8 = undefined;
    const stdin = daemon_proxy.writeRefreshBackgroundWorkStdin(&stdin_buf, .{
        .token = model.daemonToken(),
        .session_id = wire_id,
        .runtime_id = session.runtimeId(),
    }) catch return false;

    const key = model.next_daemon_key;
    model.next_daemon_key += 1;
    model.daemon_background_work_key = key;
    model.daemon_background_work_session = session.id;
    model.last_background_work_refresh_ms = model.now_ms;
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

/// Prefer hello + `stopBackgroundWork` for a live daemon-sourced
/// Background row. Requires a daemon address, usable session
/// `runtimeId`, and a non-empty `controlId`. Marks the row Stopping
/// on spawn. Missing pieces / Native 4 KiB overflow return false so
/// the caller can fall back to Faku-side dismiss. An already-Stopping
/// row returns true so Stop does not dismiss it.
pub fn tryStop(model: *Model, fx: *Effects, index: u32) bool {
    if (index >= model.background_daemon_count) return false;
    const slot = &model.background_daemon[index];
    if (slot.settled != .none) return false;
    if (slot.stop_requested) return true;
    if (slot.controlId().len == 0) return false;

    const address = store.resolveDaemonMirrorAddress(model);
    if (address.len == 0) return false;
    const session = model.sessionById(slot.session_id) orelse return false;
    if (!protocol.isUsableRuntimeId(session.runtimeId())) return false;

    const kind = slot.kind;
    const provider_id = slot.providerId();
    const control_id = slot.controlId();
    var id_buf: [36]u8 = undefined;
    const wire_id = daemon_proxy.wireUuid(session.id, &id_buf);
    var stdin_buf: [4096]u8 = undefined;
    const stdin = daemon_proxy.writeStopBackgroundWorkStdin(&stdin_buf, .{
        .token = model.daemonToken(),
        .session_id = wire_id,
        .runtime_id = session.runtimeId(),
        .key_kind = environment_summary.protocolKind(kind),
        .provider_id = provider_id,
        .control_id = control_id,
    }) catch return false;

    cancelStopInFlight(model, fx);

    const key = model.next_daemon_key;
    model.next_daemon_key += 1;
    model.daemon_stop_background_work_key = key;
    model.daemon_stop_background_work_session = session.id;
    model.daemon_stop_background_kind = kind;
    main.writeFixed(&model.daemon_stop_background_id_storage, &model.daemon_stop_background_id_len, provider_id);
    fx.spawn(.{
        .key = key,
        .argv = &.{ model.sidecarPath(), daemon_proxy.SUBCOMMAND, address },
        .stdin = stdin,
        .max_line_bytes = main.daemon_line_bytes,
        .on_line = Effects.lineMsg(.fx_line),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
    environment_summary.markDaemonStopping(model, session.id, kind, provider_id);
    return true;
}

fn lineSessionId(model: *const Model, key: u64) u32 {
    if (model.daemon_background_work_key != 0 and key == model.daemon_background_work_key)
        return model.daemon_background_work_session;
    if (model.daemon_stop_background_work_key != 0 and key == model.daemon_stop_background_work_key)
        return model.daemon_stop_background_work_session;
    return 0;
}

pub fn applyLine(model: *Model, line: native_sdk.EffectLine) void {
    const session_id = lineSessionId(model, line.key);
    if (session_id == 0) return;
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const parsed = protocol.parseBackgroundWorkEvent(arena_state.allocator(), line.line);
    if (!parsed.ok) return;
    environment_summary.applyDaemonBackgroundEvent(model, session_id, parsed);
}

pub fn handleExit(model: *Model, exit: native_sdk.EffectExit) void {
    if (model.daemon_background_work_key != 0 and exit.key == model.daemon_background_work_key) {
        model.daemon_background_work_key = 0;
        model.daemon_background_work_session = 0;
        return;
    }
    if (model.daemon_stop_background_work_key == 0 or exit.key != model.daemon_stop_background_work_key) return;
    const session_id = model.daemon_stop_background_work_session;
    const kind = model.daemon_stop_background_kind;
    const provider_id = model.daemon_stop_background_id_storage[0..model.daemon_stop_background_id_len];
    model.daemon_stop_background_work_key = 0;
    model.daemon_stop_background_work_session = 0;
    model.daemon_stop_background_id_len = 0;
    if (exit.reason == .exited and exit.code == 0) return;
    environment_summary.dismissDaemonKey(model, session_id, kind, provider_id);
}

fn pendingSpawnKey(fx: *Effects, key: u64) ?@TypeOf(fx.pendingSpawnAt(0).?) {
    var i: usize = 0;
    while (fx.pendingSpawnAt(i)) |spawn| : (i += 1) {
        if (spawn.key == key) return spawn;
    }
    return null;
}

const usable_runtime_id = "00000000-0000-0000-0000-000000000003";
const other_runtime_id = "00000000-0000-0000-0000-000000000004";
const third_runtime_id = "00000000-0000-0000-0000-000000000005";

const reconcile_line = "{\"type\":\"event\",\"sessionId\":\"00000000-0000-0000-0000-000000000001\",\"runtimeId\":\"00000000-0000-0000-0000-000000000003\",\"event\":{\"kind\":\"backgroundWork\",\"payload\":{\"type\":\"reconcileProcesses\",\"items\":[{\"key\":{\"kind\":\"process\",\"providerId\":\"proc-1\"},\"title\":\"npm run dev\",\"status\":\"running\",\"output\":\"ready\\n\"}]}}}";

const upsert_line = "{\"type\":\"event\",\"event\":{\"kind\":\"backgroundWork\",\"payload\":{\"type\":\"upsert\",\"key\":{\"kind\":\"monitor\",\"providerId\":\"toolu_d\"},\"title\":\"Watch\",\"status\":\"completed\",\"detail\":\"idle\"}}}";

const ack_line = "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000016\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"ack\"}}}";

test "refresh with a daemon address and usable runtimeId spawns refreshBackgroundWork sidecar" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    const id = model.addSession("bg daemon", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setRuntimeId(usable_runtime_id);

    refresh(&model, &fx);
    const sidecar = pendingSpawnKey(&fx, model.daemon_background_work_key) orelse return error.MissingDaemonRefreshBackgroundWork;
    try std.testing.expect(daemon_proxy.isSidecarArgv(sidecar.argv));
    try std.testing.expectEqualStrings("faku", sidecar.argv[0]);
    try std.testing.expectEqualStrings(daemon_proxy.SUBCOMMAND, sidecar.argv[1]);
    try std.testing.expectEqualStrings("127.0.0.1:8787", sidecar.argv[2]);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"hello\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"refreshBackgroundWork\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"runtimeId\":\"00000000-0000-0000-0000-000000000003\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"stopBackgroundWork\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"prompt\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"loadUsageHistory\"") == null);
    try std.testing.expectEqual(sidecar.key, model.daemon_background_work_key);
    try std.testing.expectEqual(id, model.daemon_background_work_session);
    try std.testing.expectEqual(@as(?i64, 0), model.last_background_work_refresh_ms);
}

test "refresh without a daemon address keeps local Background rows" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setSidecarPath("faku");
    const id = model.addSession("bg local", .claude);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setRuntimeId(usable_runtime_id);
    environment_summary.settle(&model, id, .completed);

    refresh(&model, &fx);
    try std.testing.expectEqual(@as(u64, 0), model.daemon_background_work_key);
    try std.testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
    try std.testing.expect(environment_summary.hasSettledBackground(&model));
}

test "refresh without a usable runtimeId does not spawn even with a daemon address" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    const id = model.addSession("bg no runtime", .fx);
    model.selected = id;
    environment_summary.settle(&model, id, .stopped);

    refresh(&model, &fx);
    try std.testing.expectEqual(@as(u64, 0), model.daemon_background_work_key);
    try std.testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
    try std.testing.expect(environment_summary.hasSettledBackground(&model));

    if (model.sessionById(id)) |session| session.setRuntimeId(protocol.NIL_UUID);
    refresh(&model, &fx);
    try std.testing.expectEqual(@as(u64, 0), model.daemon_background_work_key);
    try std.testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
}

test "refreshBackgroundWork sidecar applies reconcile and upsert without wiping local settled rows" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    const id = model.addSession("bg fill", .claude);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setRuntimeId(usable_runtime_id);
    environment_summary.settle(&model, id, .completed);
    environment_summary.noteLiveMonitor(&model, "toolu_local");
    model.background_monitors[0].settled = .completed;
    model.background_monitors[0].session_id = id;

    refresh(&model, &fx);
    const sidecar = pendingSpawnKey(&fx, model.daemon_background_work_key) orelse return error.MissingDaemonRefreshBackgroundWorkFill;
    applyLine(&model, .{ .key = sidecar.key, .line = "{\"type\":\"hello\"}" });
    try std.testing.expectEqual(@as(u32, 0), model.background_daemon_count);
    applyLine(&model, .{ .key = sidecar.key, .line = ack_line });
    try std.testing.expectEqual(@as(u32, 0), model.background_daemon_count);
    applyLine(&model, .{ .key = sidecar.key, .line = reconcile_line });
    try std.testing.expectEqual(@as(u32, 1), model.background_daemon_count);
    try std.testing.expectEqual(environment_summary.BackgroundKind.process, model.background_daemon[0].kind);
    try std.testing.expectEqualStrings("proc-1", model.background_daemon[0].providerId());
    try std.testing.expectEqualStrings("npm run dev", model.background_daemon[0].title());
    applyLine(&model, .{ .key = sidecar.key, .line = upsert_line });
    try std.testing.expectEqual(@as(u32, 2), model.background_daemon_count);
    try std.testing.expectEqual(environment_summary.BackgroundKind.monitor, model.background_daemon[1].kind);
    try std.testing.expectEqual(environment_summary.SettledStatus.completed, model.background_daemon[1].settled);
    try std.testing.expect(environment_summary.hasSettledBackground(&model));
    try std.testing.expectEqual(@as(u32, 1), model.background_monitor_count);
    try std.testing.expectEqualStrings("toolu_local", model.background_monitors[0].toolUseId());
    var buf: [environment_summary.max_background_rows]environment_summary.BackgroundRow = undefined;
    const rows = environment_summary.fillBackgroundRows(&model, &buf);
    try std.testing.expect(rows.len >= 3);

    handleExit(&model, .{ .key = sidecar.key, .reason = .exited, .code = 0 });
    try std.testing.expectEqual(@as(u64, 0), model.daemon_background_work_key);
    try std.testing.expectEqual(@as(u32, 2), model.background_daemon_count);

    refresh(&model, &fx);
    const miss = pendingSpawnKey(&fx, model.daemon_background_work_key) orelse return error.MissingDaemonRefreshBackgroundWorkMiss;
    applyLine(&model, .{ .key = miss.key, .line = ack_line });
    handleExit(&model, .{ .key = miss.key, .reason = .exited, .code = 1 });
    try std.testing.expectEqual(@as(u32, 2), model.background_daemon_count);
    try std.testing.expectEqual(@as(u32, 1), model.background_monitor_count);
    try std.testing.expect(environment_summary.hasSettledBackground(&model));
    try std.testing.expectEqual(@as(usize, 0), model.window_status_len);

    environment_summary.clearDaemonBackground(&model);
    environment_summary.clearLiveMonitors(&model);
    environment_summary.clearSettled(&model);
}

test "upsert skips a providerId that already has a local Monitor row" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    const id = model.addSession("bg skip local", .claude);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setRuntimeId(usable_runtime_id);
    environment_summary.noteLiveMonitor(&model, "toolu_local");
    model.background_monitors[0].settled = .completed;
    model.background_monitors[0].session_id = id;

    refresh(&model, &fx);
    const sidecar = pendingSpawnKey(&fx, model.daemon_background_work_key) orelse return error.MissingSkipLocal;
    applyLine(&model, .{
        .key = sidecar.key,
        .line = "{\"type\":\"event\",\"event\":{\"kind\":\"backgroundWork\",\"payload\":{\"type\":\"upsert\",\"key\":{\"kind\":\"monitor\",\"providerId\":\"toolu_local\"},\"title\":\"dup\",\"status\":\"running\"}}}",
    });
    try std.testing.expectEqual(@as(u32, 0), model.background_daemon_count);
    try std.testing.expectEqual(@as(u32, 1), model.background_monitor_count);
    try std.testing.expectEqualStrings("toolu_local", model.background_monitors[0].toolUseId());
    environment_summary.clearLiveMonitors(&model);
}

test "Background tab and Environment Summary open prefer refreshBackgroundWork" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    const id = model.addSession("bg tab", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setRuntimeId(usable_runtime_id);

    main.update(&model, .set_right_panel_tab_background, &fx);
    try std.testing.expect(model.right_panel_tab_background());
    const tab = pendingSpawnKey(&fx, model.daemon_background_work_key) orelse return error.MissingBackgroundTabRefresh;
    try std.testing.expect(std.mem.indexOf(u8, tab.stdin, "\"type\":\"refreshBackgroundWork\"") != null);

    main.update(&model, .toggle_environment_summary, &fx);
    try std.testing.expect(model.environment_summary_open);
    const summary = pendingSpawnKey(&fx, model.daemon_background_work_key) orelse return error.MissingEnvironmentSummaryRefresh;
    try std.testing.expect(summary.key != tab.key);
    try std.testing.expect(std.mem.indexOf(u8, summary.stdin, "\"type\":\"refreshBackgroundWork\"") != null);
    try std.testing.expect(model.last_background_work_refresh_ms != null);
}

test "Background tab without a daemon address does not spawn refreshBackgroundWork" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setSidecarPath("faku");
    const id = model.addSession("bg tab local", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setRuntimeId(usable_runtime_id);
    main.update(&model, .set_right_panel_tab_background, &fx);
    try std.testing.expect(model.right_panel_tab_background());
    try std.testing.expectEqual(@as(u64, 0), model.daemon_background_work_key);
    try std.testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
    main.update(&model, .toggle_environment_summary, &fx);
    try std.testing.expect(model.environment_summary_open);
    try std.testing.expectEqual(@as(u64, 0), model.daemon_background_work_key);
    try std.testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
}

const stoppable_upsert_line = "{\"type\":\"event\",\"event\":{\"kind\":\"backgroundWork\",\"payload\":{\"type\":\"upsert\",\"key\":{\"kind\":\"process\",\"providerId\":\"proc-1\"},\"title\":\"npm run dev\",\"status\":\"running\",\"canStop\":true,\"controlId\":\"c1\"}}}";

const settled_upsert_line = "{\"type\":\"event\",\"event\":{\"kind\":\"backgroundWork\",\"payload\":{\"type\":\"upsert\",\"key\":{\"kind\":\"monitor\",\"providerId\":\"toolu_s\"},\"title\":\"Watch\",\"status\":\"completed\",\"canStop\":false,\"controlId\":\"\"}}}";

const live_no_control_line = "{\"type\":\"event\",\"event\":{\"kind\":\"backgroundWork\",\"payload\":{\"type\":\"upsert\",\"key\":{\"kind\":\"process\",\"providerId\":\"proc-2\"},\"title\":\"sleep\",\"status\":\"running\",\"canStop\":true}}}";

fn applyDaemonLine(model: *Model, session_id: u32, line: []const u8) void {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const parsed = protocol.parseBackgroundWorkEvent(arena_state.allocator(), line);
    environment_summary.applyDaemonBackgroundEvent(model, session_id, parsed);
}

test "Stop with daemon runtimeId and controlId spawns stopBackgroundWork sidecar" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    const id = model.addSession("bg stop", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setRuntimeId(usable_runtime_id);
    applyDaemonLine(&model, id, stoppable_upsert_line);
    try std.testing.expectEqual(@as(u32, 1), model.background_daemon_count);
    try std.testing.expect(model.background_daemon[0].can_stop);
    try std.testing.expectEqualStrings("c1", model.background_daemon[0].controlId());

    var buf: [environment_summary.max_background_rows]environment_summary.BackgroundRow = undefined;
    const rows = environment_summary.fillBackgroundRows(&model, &buf);
    try std.testing.expectEqual(@as(usize, 1), rows.len);
    try std.testing.expect(rows[0].live);
    try std.testing.expect(rows[0].can_stop);
    try std.testing.expectEqualStrings(environment_summary.daemon_stop_label, rows[0].stop_label);
    try std.testing.expectEqual(environment_summary.daemon_row_id_first, rows[0].id);

    environment_summary.stopBackground(&model, &fx, environment_summary.daemon_row_id_first);
    const sidecar = pendingSpawnKey(&fx, model.daemon_stop_background_work_key) orelse return error.MissingDaemonStopBackgroundWork;
    try std.testing.expect(daemon_proxy.isSidecarArgv(sidecar.argv));
    try std.testing.expectEqualStrings("127.0.0.1:8787", sidecar.argv[2]);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"hello\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"stopBackgroundWork\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"key\":{\"kind\":\"process\",\"providerId\":\"proc-1\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"controlId\":\"c1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"refreshBackgroundWork\"") == null);
    try std.testing.expect(sidecar.key != model.daemon_background_work_key);
    try std.testing.expectEqual(id, model.daemon_stop_background_work_session);
    try std.testing.expect(model.background_daemon[0].stop_requested);
    try std.testing.expect(!model.background_daemon[0].can_stop);
    const after = environment_summary.fillBackgroundRows(&model, &buf);
    try std.testing.expectEqual(@as(usize, 1), after.len);
    try std.testing.expect(after[0].live);
    try std.testing.expect(!after[0].can_stop);
    try std.testing.expectEqualStrings(environment_summary.live_stopping_label, environment_summary.backgroundWorkStatus(after[0]));

    applyLine(&model, .{ .key = sidecar.key, .line = ack_line });
    handleExit(&model, .{ .key = sidecar.key, .reason = .exited, .code = 0 });
    try std.testing.expectEqual(@as(u64, 0), model.daemon_stop_background_work_key);
    try std.testing.expectEqual(@as(u32, 1), model.background_daemon_count);
    try std.testing.expect(model.background_daemon[0].stop_requested);
    try std.testing.expectEqual(environment_summary.SettledStatus.none, model.background_daemon[0].settled);
}

test "Stop without a daemon address or controlId does not spawn stop sidecar" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setSidecarPath("faku");
    const id = model.addSession("bg stop local", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setRuntimeId(usable_runtime_id);
    applyDaemonLine(&model, id, stoppable_upsert_line);
    try std.testing.expectEqual(@as(u32, 1), model.background_daemon_count);

    environment_summary.stopBackground(&model, &fx, environment_summary.daemon_row_id_first);
    try std.testing.expectEqual(@as(u64, 0), model.daemon_stop_background_work_key);
    try std.testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
    try std.testing.expectEqual(@as(u32, 0), model.background_daemon_count);

    model.setLastDaemonAddress("127.0.0.1:8787");
    applyDaemonLine(&model, id, live_no_control_line);
    try std.testing.expectEqual(@as(u32, 1), model.background_daemon_count);
    var buf: [environment_summary.max_background_rows]environment_summary.BackgroundRow = undefined;
    const rows = environment_summary.fillBackgroundRows(&model, &buf);
    try std.testing.expectEqual(@as(usize, 1), rows.len);
    try std.testing.expect(rows[0].live);
    try std.testing.expect(!rows[0].can_stop);
    try std.testing.expectEqualStrings("", rows[0].stop_label);

    environment_summary.stopBackground(&model, &fx, environment_summary.daemon_row_id_first);
    try std.testing.expectEqual(@as(u64, 0), model.daemon_stop_background_work_key);
    try std.testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
    try std.testing.expectEqual(@as(u32, 0), model.background_daemon_count);
}

test "settled daemon Dismiss stays Faku-side and does not spawn stopBackgroundWork" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    const id = model.addSession("bg dismiss", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setRuntimeId(usable_runtime_id);
    applyDaemonLine(&model, id, settled_upsert_line);
    try std.testing.expectEqual(@as(u32, 1), model.background_daemon_count);
    try std.testing.expectEqual(environment_summary.SettledStatus.completed, model.background_daemon[0].settled);

    var buf: [environment_summary.max_background_rows]environment_summary.BackgroundRow = undefined;
    const rows = environment_summary.fillBackgroundRows(&model, &buf);
    try std.testing.expectEqual(@as(usize, 1), rows.len);
    try std.testing.expect(!rows[0].live);
    try std.testing.expect(rows[0].can_stop);
    try std.testing.expectEqualStrings(environment_summary.daemon_dismiss_label, rows[0].stop_label);

    environment_summary.stopBackground(&model, &fx, environment_summary.daemon_row_id_first);
    try std.testing.expectEqual(@as(u64, 0), model.daemon_stop_background_work_key);
    try std.testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
    try std.testing.expectEqual(@as(u32, 0), model.background_daemon_count);
}

test "live Monitor Stop does not spawn stopBackgroundWork" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    const id = model.addSession("bg local stop", .claude);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setRuntimeId(usable_runtime_id);
    environment_summary.noteLiveMonitor(&model, "toolu_local");
    applyDaemonLine(&model, id, stoppable_upsert_line);

    environment_summary.stopBackground(&model, &fx, environment_summary.monitor_row_id_first);
    try std.testing.expectEqual(@as(u64, 0), model.daemon_stop_background_work_key);
    try std.testing.expectEqual(@as(u32, 0), model.background_monitor_count);
    try std.testing.expectEqual(@as(u32, 1), model.background_daemon_count);

    environment_summary.stopBackground(&model, &fx, environment_summary.daemon_row_id_first);
    const stop = pendingSpawnKey(&fx, model.daemon_stop_background_work_key) orelse return error.MissingStopAfterLocalDismiss;
    try std.testing.expect(std.mem.indexOf(u8, stop.stdin, "\"type\":\"stopBackgroundWork\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stop.stdin, "\"type\":\"refreshBackgroundWork\"") == null);
}

fn showBackgroundTab(model: *Model) void {
    model.right_panel_open = true;
    model.right_panel_tab = .background;
}

fn finishRefreshSidecar(model: *Model) void {
    const key = model.daemon_background_work_key;
    if (key == 0) return;
    handleExit(model, .{ .key = key, .reason = .exited, .code = 0 });
}

fn seedTickModel() Model {
    var model = Model{};
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    const id = model.addSession("bg tick", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setRuntimeId(usable_runtime_id);
    model.now_ms = 10_000;
    return model;
}

test "maybeRefresh eligible and aged past 5s spawns refreshBackgroundWork" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = seedTickModel();
    showBackgroundTab(&model);
    model.last_background_work_refresh_ms = model.now_ms - background_work_refresh_interval_ms;
    maybeRefresh(&model, &fx);
    const sidecar = pendingSpawnKey(&fx, model.daemon_background_work_key) orelse return error.MissingTickRefresh;
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"refreshBackgroundWork\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"hello\"") != null);
    try std.testing.expectEqual(@as(?i64, 10_000), model.last_background_work_refresh_ms);
}

test "maybeRefresh within 5s does not spawn" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = seedTickModel();
    showBackgroundTab(&model);
    model.last_background_work_refresh_ms = model.now_ms - (background_work_refresh_interval_ms - 1);
    maybeRefresh(&model, &fx);
    try std.testing.expectEqual(@as(u64, 0), model.daemon_background_work_key);
    try std.testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
    try std.testing.expectEqual(@as(?i64, 10_000 - (background_work_refresh_interval_ms - 1)), model.last_background_work_refresh_ms);
}

test "maybeRefresh skips while a refresh sidecar is in flight" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = seedTickModel();
    showBackgroundTab(&model);
    refresh(&model, &fx);
    const open_key = model.daemon_background_work_key;
    try std.testing.expect(open_key != 0);
    model.now_ms += background_work_refresh_interval_ms;
    maybeRefresh(&model, &fx);
    try std.testing.expectEqual(open_key, model.daemon_background_work_key);
    try std.testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());
}

test "maybeRefresh keeps quiet without daemon, runtimeId, or Background UI" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = seedTickModel();
    model.setLastDaemonAddress("");
    showBackgroundTab(&model);
    maybeRefresh(&model, &fx);
    try std.testing.expectEqual(@as(u64, 0), model.daemon_background_work_key);
    try std.testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
    try std.testing.expectEqual(@as(?i64, null), model.last_background_work_refresh_ms);

    model = seedTickModel();
    if (model.sessionById(model.selected)) |session| session.setRuntimeId("");
    showBackgroundTab(&model);
    maybeRefresh(&model, &fx);
    try std.testing.expectEqual(@as(u64, 0), model.daemon_background_work_key);
    try std.testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());

    model = seedTickModel();
    model.right_panel_open = true;
    model.right_panel_tab = .files;
    maybeRefresh(&model, &fx);
    try std.testing.expectEqual(@as(u64, 0), model.daemon_background_work_key);
    try std.testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
}

test "maybeRefresh unset last fires immediately; open path still refreshes" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = seedTickModel();
    showBackgroundTab(&model);
    try std.testing.expectEqual(@as(?i64, null), model.last_background_work_refresh_ms);
    maybeRefresh(&model, &fx);
    const first = pendingSpawnKey(&fx, model.daemon_background_work_key) orelse return error.MissingImmediateTick;
    try std.testing.expect(std.mem.indexOf(u8, first.stdin, "\"type\":\"refreshBackgroundWork\"") != null);
    try std.testing.expectEqual(@as(?i64, 10_000), model.last_background_work_refresh_ms);
    finishRefreshSidecar(&model);

    refresh(&model, &fx);
    const open = pendingSpawnKey(&fx, model.daemon_background_work_key) orelse return error.MissingOpenRefreshAfterTick;
    try std.testing.expect(open.key != first.key);
    try std.testing.expect(std.mem.indexOf(u8, open.stdin, "\"type\":\"refreshBackgroundWork\"") != null);
}

test "maybeRefresh live daemon rows fire without Background tab" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = seedTickModel();
    applyDaemonLine(&model, model.selected, stoppable_upsert_line);
    try std.testing.expectEqual(@as(u32, 1), model.background_daemon_count);
    try std.testing.expect(!model.right_panel_open);
    try std.testing.expect(!model.environment_summary_open);
    maybeRefresh(&model, &fx);
    const sidecar = pendingSpawnKey(&fx, model.daemon_background_work_key) orelse return error.MissingLiveDaemonTick;
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"refreshBackgroundWork\"") != null);
}

test "update tick path maybeRefresh after 5s; open path still immediate" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;
    var clock = native_sdk.TestClock{};
    clock.setWallMs(1_000);
    fx.clock = clock.clock();

    var model = Model{};
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    const id = model.addSession("bg update tick", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setRuntimeId(usable_runtime_id);

    main.update(&model, .set_right_panel_tab_background, &fx);
    try std.testing.expect(model.right_panel_showing_background());
    const open_key = model.daemon_background_work_key;
    try std.testing.expect(open_key != 0);
    try std.testing.expectEqual(@as(?i64, 1_000), model.last_background_work_refresh_ms);
    finishRefreshSidecar(&model);

    clock.setWallMs(1_000 + background_work_refresh_interval_ms - 1);
    main.update(&model, .close_environment_summary, &fx);
    try std.testing.expectEqual(@as(u64, 0), model.daemon_background_work_key);

    clock.setWallMs(1_000 + background_work_refresh_interval_ms);
    main.update(&model, .close_environment_summary, &fx);
    const tick = pendingSpawnKey(&fx, model.daemon_background_work_key) orelse return error.MissingUpdateTickRefresh;
    try std.testing.expect(tick.key != open_key);
    try std.testing.expect(std.mem.indexOf(u8, tick.stdin, "\"type\":\"refreshBackgroundWork\"") != null);
    try std.testing.expectEqual(@as(?i64, 1_000 + background_work_refresh_interval_ms), model.last_background_work_refresh_ms);
}

const FanoutSeed = struct {
    model: Model,
    selected_id: u32,
    other_id: u32,
};

fn seedFanoutModel() FanoutSeed {
    var model = Model{};
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    const other_id = model.addSession("bg other", .fx);
    const selected_id = model.addSession("bg selected", .fx);
    model.selected = selected_id;
    if (model.sessionById(selected_id)) |session| session.setRuntimeId(usable_runtime_id);
    if (model.sessionById(other_id)) |session| session.setRuntimeId(other_runtime_id);
    model.now_ms = 10_000;
    return .{ .model = model, .selected_id = selected_id, .other_id = other_id };
}

fn expectRefreshFor(sidecar: anytype, session_id: u32, runtime_id: []const u8) !void {
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"refreshBackgroundWork\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"hello\"") != null);
    var uuid_buf: [36]u8 = undefined;
    const wire = daemon_proxy.wireUuid(session_id, &uuid_buf);
    var session_buf: [80]u8 = undefined;
    const session_needle = std.fmt.bufPrint(&session_buf, "\"sessionId\":\"{s}\"", .{wire}) catch return error.SessionNeedle;
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, session_needle) != null);
    var runtime_buf: [80]u8 = undefined;
    const runtime_needle = std.fmt.bufPrint(&runtime_buf, "\"runtimeId\":\"{s}\"", .{runtime_id}) catch return error.RuntimeNeedle;
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, runtime_needle) != null);
}

test "maybeRefresh still prefers selected when UI cares even if another session is live" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var seed = seedFanoutModel();
    showBackgroundTab(&seed.model);
    applyDaemonLine(&seed.model, seed.other_id, stoppable_upsert_line);
    maybeRefresh(&seed.model, &fx);
    const sidecar = pendingSpawnKey(&fx, seed.model.daemon_background_work_key) orelse return error.MissingSelectedPreferRefresh;
    try expectRefreshFor(sidecar, seed.selected_id, usable_runtime_id);
    try std.testing.expectEqual(seed.selected_id, seed.model.daemon_background_work_session);
}

test "maybeRefresh still prefers selected live over another live session" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var seed = seedFanoutModel();
    applyDaemonLine(&seed.model, seed.selected_id, stoppable_upsert_line);
    applyDaemonLine(&seed.model, seed.other_id, live_no_control_line);
    try std.testing.expect(!seed.model.right_panel_open);
    maybeRefresh(&seed.model, &fx);
    const sidecar = pendingSpawnKey(&fx, seed.model.daemon_background_work_key) orelse return error.MissingSelectedLivePreferRefresh;
    try expectRefreshFor(sidecar, seed.selected_id, usable_runtime_id);
    try std.testing.expectEqual(seed.selected_id, seed.model.daemon_background_work_session);
}

test "maybeRefresh fans out to another live session when selected has no live" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var seed = seedFanoutModel();
    applyDaemonLine(&seed.model, seed.other_id, stoppable_upsert_line);
    try std.testing.expectEqual(seed.other_id, seed.model.background_daemon[0].session_id);
    try std.testing.expectEqual(environment_summary.SettledStatus.none, seed.model.background_daemon[0].settled);
    try std.testing.expect(!seed.model.right_panel_open);
    try std.testing.expect(!seed.model.environment_summary_open);
    maybeRefresh(&seed.model, &fx);
    const sidecar = pendingSpawnKey(&fx, seed.model.daemon_background_work_key) orelse return error.MissingFanoutRefresh;
    try expectRefreshFor(sidecar, seed.other_id, other_runtime_id);
    try std.testing.expectEqual(seed.other_id, seed.model.daemon_background_work_session);
    try std.testing.expectEqual(@as(?i64, 10_000), seed.model.last_background_work_refresh_ms);
}

test "maybeRefresh fans out when selected has no usable runtimeId" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var seed = seedFanoutModel();
    if (seed.model.sessionById(seed.selected_id)) |session| session.setRuntimeId("");
    showBackgroundTab(&seed.model);
    applyDaemonLine(&seed.model, seed.other_id, stoppable_upsert_line);
    maybeRefresh(&seed.model, &fx);
    const sidecar = pendingSpawnKey(&fx, seed.model.daemon_background_work_key) orelse return error.MissingFanoutNoSelectedRuntime;
    try expectRefreshFor(sidecar, seed.other_id, other_runtime_id);
    try std.testing.expectEqual(seed.other_id, seed.model.daemon_background_work_session);
}

test "maybeRefresh fan-out skips while a refresh sidecar is in flight" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var seed = seedFanoutModel();
    showBackgroundTab(&seed.model);
    refresh(&seed.model, &fx);
    const open_key = seed.model.daemon_background_work_key;
    try std.testing.expect(open_key != 0);
    try std.testing.expectEqual(seed.selected_id, seed.model.daemon_background_work_session);
    applyDaemonLine(&seed.model, seed.other_id, stoppable_upsert_line);
    seed.model.now_ms += background_work_refresh_interval_ms;
    maybeRefresh(&seed.model, &fx);
    try std.testing.expectEqual(open_key, seed.model.daemon_background_work_key);
    try std.testing.expectEqual(seed.selected_id, seed.model.daemon_background_work_session);
    try std.testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());
}

test "maybeRefresh fan-out within 5s does not spawn" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var seed = seedFanoutModel();
    seed.model.last_background_work_refresh_ms = seed.model.now_ms - (background_work_refresh_interval_ms - 1);
    applyDaemonLine(&seed.model, seed.other_id, stoppable_upsert_line);
    maybeRefresh(&seed.model, &fx);
    try std.testing.expectEqual(@as(u64, 0), seed.model.daemon_background_work_key);
    try std.testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
}

test "open-path refresh still targets selected immediately when another session is live" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var seed = seedFanoutModel();
    applyDaemonLine(&seed.model, seed.other_id, stoppable_upsert_line);
    seed.model.last_background_work_refresh_ms = seed.model.now_ms;
    refresh(&seed.model, &fx);
    const sidecar = pendingSpawnKey(&fx, seed.model.daemon_background_work_key) orelse return error.MissingOpenPathSelected;
    try expectRefreshFor(sidecar, seed.selected_id, usable_runtime_id);
    try std.testing.expectEqual(seed.selected_id, seed.model.daemon_background_work_session);

    finishRefreshSidecar(&seed.model);
    if (seed.model.sessionById(seed.selected_id)) |session| session.setRuntimeId("");
    refresh(&seed.model, &fx);
    try std.testing.expectEqual(@as(u64, 0), seed.model.daemon_background_work_key);
    try std.testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());
}

test "maybeRefresh fan-out keeps quiet without daemon address or usable other runtimeId" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var seed = seedFanoutModel();
    seed.model.setLastDaemonAddress("");
    applyDaemonLine(&seed.model, seed.other_id, stoppable_upsert_line);
    maybeRefresh(&seed.model, &fx);
    try std.testing.expectEqual(@as(u64, 0), seed.model.daemon_background_work_key);
    try std.testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
    try std.testing.expectEqual(@as(?i64, null), seed.model.last_background_work_refresh_ms);

    seed = seedFanoutModel();
    if (seed.model.sessionById(seed.other_id)) |session| session.setRuntimeId("");
    applyDaemonLine(&seed.model, seed.other_id, stoppable_upsert_line);
    maybeRefresh(&seed.model, &fx);
    try std.testing.expectEqual(@as(u64, 0), seed.model.daemon_background_work_key);
    try std.testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
}

test "maybeRefresh does not fan out to settled other-session rows" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var seed = seedFanoutModel();
    applyDaemonLine(&seed.model, seed.other_id, settled_upsert_line);
    try std.testing.expectEqual(environment_summary.SettledStatus.completed, seed.model.background_daemon[0].settled);
    maybeRefresh(&seed.model, &fx);
    try std.testing.expectEqual(@as(u64, 0), seed.model.daemon_background_work_key);
    try std.testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
}

test "maybeRefresh fan-out picks the lowest other session id among live sessions" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var seed = seedFanoutModel();
    const third_id = seed.model.addSession("bg third", .fx);
    if (seed.model.sessionById(third_id)) |session| session.setRuntimeId(third_runtime_id);
    applyDaemonLine(&seed.model, seed.other_id, stoppable_upsert_line);
    applyDaemonLine(&seed.model, third_id, live_no_control_line);
    try std.testing.expect(seed.other_id < third_id);
    maybeRefresh(&seed.model, &fx);
    const sidecar = pendingSpawnKey(&fx, seed.model.daemon_background_work_key) orelse return error.MissingLowestIdFanout;
    try expectRefreshFor(sidecar, seed.other_id, other_runtime_id);
    try std.testing.expectEqual(seed.other_id, seed.model.daemon_background_work_session);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, third_runtime_id) == null);
}
