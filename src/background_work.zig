//! First-cut daemon `Command::RefreshBackgroundWork`.
//!
//! When the right-panel Background tab is selected or Environment
//! Summary opens, and `WAKU_DAEMON_ADDRESS` or persisted
//! `last_daemon_address` is set **and** the selected session has a
//! usable `runtimeId`, Faku one-shots hello + `refreshBackgroundWork`
//! (request-frame `sessionId` + `runtimeId`, same as cancel / steer /
//! goal). Ok is typically Ack; `backgroundWork` events on sidecar
//! stdout apply `reconcileProcesses` / `reconcileLive` / `upsert`
//! into daemon-sourced registry rows. Native 4 KiB stdin overflow /
//! sidecar failure / unusable parse / missing address / missing
//! runtimeId keep today's local Process / Monitor / Subagent
//! behavior. Not `StopBackgroundWork`. Not a long-lived Waku tick
//! loop. Not full BackgroundWorkRegistry / GPUI SharedString parity.
//! Local Faku-side Stop / Dismiss remains. Hello stays v4.

const std = @import("std");
const native_sdk = @import("native_sdk");
const main = @import("main.zig");
const daemon_proxy = @import("daemon_proxy.zig");
const protocol = @import("protocol.zig");
const store = @import("store.zig");
const environment_summary = @import("environment_summary.zig");

const Model = main.Model;
const Effects = main.Effects;

fn cancelInFlight(model: *Model, fx: *Effects) void {
    if (model.daemon_background_work_key == 0) return;
    fx.cancel(model.daemon_background_work_key);
    model.daemon_background_work_key = 0;
    model.daemon_background_work_session = 0;
}

/// Drop an in-flight refreshBackgroundWork sidecar. Safe when none
/// is live. Does not clear local or daemon-sourced registry rows.
pub fn cancel(model: *Model, fx: *Effects) void {
    cancelInFlight(model, fx);
}

/// Prefer hello + `refreshBackgroundWork` when a daemon address and
/// a usable session `runtimeId` are set. Missing address / runtimeId
/// / Native 4 KiB stdin overflow keep local Background rows.
pub fn refresh(model: *Model, fx: *Effects) void {
    cancelInFlight(model, fx);
    _ = trySpawn(model, fx);
}

fn trySpawn(model: *Model, fx: *Effects) bool {
    const address = store.resolveDaemonMirrorAddress(model);
    if (address.len == 0) return false;
    const session = model.sessionById(model.selected) orelse return false;
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

pub fn applyLine(model: *Model, line: native_sdk.EffectLine) void {
    if (line.key != model.daemon_background_work_key or model.daemon_background_work_key == 0) return;
    const session_id = model.daemon_background_work_session;
    if (session_id == 0) return;
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const parsed = protocol.parseBackgroundWorkEvent(arena_state.allocator(), line.line);
    if (!parsed.ok) return;
    environment_summary.applyDaemonBackgroundEvent(model, session_id, parsed);
}

pub fn handleExit(model: *Model, exit: native_sdk.EffectExit) void {
    if (exit.key != model.daemon_background_work_key or model.daemon_background_work_key == 0) return;
    model.daemon_background_work_key = 0;
    model.daemon_background_work_session = 0;
}

fn pendingSpawnKey(fx: *Effects, key: u64) ?@TypeOf(fx.pendingSpawnAt(0).?) {
    var i: usize = 0;
    while (fx.pendingSpawnAt(i)) |spawn| : (i += 1) {
        if (spawn.key == key) return spawn;
    }
    return null;
}

const usable_runtime_id = "00000000-0000-0000-0000-000000000003";

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
