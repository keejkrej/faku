//! First-cut composer usage meter + daemon `Command::FetchPlanUsage`.
//!
//! With a session selected, Faku paints a Native `<progress>` meter
//! under the composer (honest substitute for Waku's circular gauge).
//! Opening the panel shows local context occupancy and, when the
//! selected provider is Claude / Codex / OpenCode / Grok, plan
//! rate-limit lanes from a best-effort one-shot hello +
//! `fetchPlanUsage`. `WAKU_DAEMON_ADDRESS` or persisted
//! `last_daemon_address` is required for the sidecar; missing address
//! keeps local context and a muted connect hint. JSON-null `usage` is
//! unconfigured. Unknown-command / parse miss keep a prior snapshot
//! or a muted error. Native 4 KiB stdin overflow does not toast.
//! Closing the panel leaves the runtime cache. Refresh re-spawns.
//! Hello stays v4. Still not a circular GPUI gauge, not Waku's
//! 300s/600s/stale/retry cadence, not LiteLLM.

const std = @import("std");
const native_sdk = @import("native_sdk");
const main = @import("main.zig");
const daemon_proxy = @import("daemon_proxy.zig");
const protocol = @import("protocol.zig");
const store = @import("store.zig");

const Model = main.Model;
const Effects = main.Effects;
const writeFixed = main.writeFixed;
const ProviderId = protocol.ProviderId;

pub const max_windows = protocol.max_parsed_plan_windows;
pub const max_label = 64;
pub const max_line = 160;

pub const connect_hint = "Connect a daemon for plan usage";
pub const loading_hint = "Loading plan usage…";
pub const unconfigured_hint = "Plan usage unconfigured";
pub const unavailable_hint = "Plan usage unavailable";
pub const nothing_measured = "Nothing measured yet";

pub const Row = struct {
    id: u32,
    line: []const u8,
    share: f32 = 0,
    percent: []const u8 = "",
    resets: []const u8 = "",
    has_resets: bool = false,
};

pub const CachedWindow = struct {
    label_storage: [max_label]u8 = [_]u8{0} ** max_label,
    label_len: usize = 0,
    percent: f64 = 0,
    resets_at: ?i64 = null,

    pub fn label(self: *const CachedWindow) []const u8 {
        return self.label_storage[0..self.label_len];
    }
};

pub const Cache = struct {
    provider: ProviderId = .claude,
    present: bool = false,
    unconfigured: bool = false,
    errored: bool = false,
    adopted_ok: bool = false,
    plan_label_storage: [max_label]u8 = [_]u8{0} ** max_label,
    plan_label_len: usize = 0,
    windows: [max_windows]CachedWindow = [_]CachedWindow{.{}} ** max_windows,
    window_count: usize = 0,

    pub fn planLabel(self: *const Cache) []const u8 {
        return self.plan_label_storage[0..self.plan_label_len];
    }
};

pub fn isPlanUsageProvider(id: ProviderId) bool {
    return switch (id) {
        .claude, .codex, .opencode, .grok => true,
        else => false,
    };
}

pub fn available(model: *const Model) bool {
    return model.sessionByIdConst(model.selected) != null;
}

pub fn selectedProvider(model: *const Model) ?ProviderId {
    const session = model.sessionByIdConst(model.selected) orelse return null;
    return session.provider;
}

fn cacheMatches(model: *const Model) bool {
    const provider = selectedProvider(model) orelse return false;
    return model.plan_usage.provider == provider;
}

fn cancelInFlight(model: *Model, fx: *Effects) void {
    if (model.daemon_plan_usage_key == 0) return;
    fx.cancel(model.daemon_plan_usage_key);
    model.daemon_plan_usage_key = 0;
}

pub fn cancel(model: *Model, fx: *Effects) void {
    cancelInFlight(model, fx);
}

pub fn close(model: *Model) void {
    model.usage_meter_open = false;
}

pub fn open(model: *Model, fx: *Effects) void {
    model.usage_meter_open = true;
    ensure(model, fx, true);
}

pub fn toggle(model: *Model, fx: *Effects) void {
    if (model.usage_meter_open) {
        close(model);
        return;
    }
    open(model, fx);
}

pub fn refresh(model: *Model, fx: *Effects) void {
    if (!model.usage_meter_open) return;
    ensure(model, fx, true);
}

/// Session / provider change: keep a matching cache, else load when
/// the panel is open.
pub fn onSessionChange(model: *Model, fx: *Effects) void {
    if (!model.usage_meter_open) return;
    ensure(model, fx, false);
}

fn ensure(model: *Model, fx: *Effects, force: bool) void {
    const provider = selectedProvider(model) orelse return;
    if (!isPlanUsageProvider(provider)) {
        if (model.daemon_plan_usage_key != 0) cancelInFlight(model, fx);
        return;
    }
    if (!force) {
        if (model.daemon_plan_usage_key != 0 and model.daemon_plan_usage_provider == provider) return;
        if (cacheMatches(model) and (model.plan_usage.present or model.plan_usage.unconfigured)) {
            if (model.daemon_plan_usage_key != 0 and model.daemon_plan_usage_provider != provider) {
                cancelInFlight(model, fx);
            }
            return;
        }
    }
    cancelInFlight(model, fx);
    _ = trySpawn(model, fx, provider);
}

fn trySpawn(model: *Model, fx: *Effects, provider: ProviderId) bool {
    const address = store.resolveDaemonMirrorAddress(model);
    if (address.len == 0) return false;

    var stdin_buf: [4096]u8 = undefined;
    const stdin = daemon_proxy.writePlanUsageStdin(&stdin_buf, .{
        .token = model.daemonToken(),
        .provider = provider.daemonProviderKind(),
    }) catch return false;

    const key = model.next_daemon_key;
    model.next_daemon_key += 1;
    model.daemon_plan_usage_key = key;
    model.daemon_plan_usage_provider = provider;
    model.plan_usage.adopted_ok = false;
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

fn adopt(cache: *Cache, provider: ProviderId, parsed: protocol.ParsedPlanUsage) void {
    cache.provider = provider;
    cache.adopted_ok = true;
    cache.errored = false;
    if (!parsed.usage_present) {
        cache.present = false;
        cache.unconfigured = true;
        cache.plan_label_len = 0;
        cache.window_count = 0;
        return;
    }
    cache.present = true;
    cache.unconfigured = false;
    writeFixed(&cache.plan_label_storage, &cache.plan_label_len, parsed.plan_label);
    cache.window_count = parsed.window_count;
    var i: usize = 0;
    while (i < parsed.window_count) : (i += 1) {
        writeFixed(&cache.windows[i].label_storage, &cache.windows[i].label_len, parsed.windows[i].label);
        cache.windows[i].percent = parsed.windows[i].percent;
        cache.windows[i].resets_at = parsed.windows[i].resets_at;
    }
}

pub fn applyLine(model: *Model, line: native_sdk.EffectLine) void {
    if (line.key != model.daemon_plan_usage_key or model.daemon_plan_usage_key == 0) return;
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const parsed = protocol.parsePlanUsage(arena_state.allocator(), line.line);
    if (!parsed.ok) return;
    adopt(&model.plan_usage, model.daemon_plan_usage_provider, parsed);
}

pub fn handleExit(model: *Model, exit: native_sdk.EffectExit) void {
    if (exit.key != model.daemon_plan_usage_key or model.daemon_plan_usage_key == 0) return;
    const pending = model.daemon_plan_usage_provider;
    model.daemon_plan_usage_key = 0;
    if (model.plan_usage.adopted_ok) return;
    if (model.plan_usage.present and model.plan_usage.provider == pending) return;
    model.plan_usage.provider = pending;
    model.plan_usage.present = false;
    model.plan_usage.unconfigured = false;
    model.plan_usage.errored = true;
    model.plan_usage.window_count = 0;
    model.plan_usage.plan_label_len = 0;
}

fn copyArena(arena: std.mem.Allocator, text: []const u8) []const u8 {
    if (text.len == 0) return "";
    const out = arena.alloc(u8, text.len) catch return "";
    @memcpy(out, text);
    return out;
}

fn clampShare(value: f64) f32 {
    if (!std.math.isFinite(value) or !(value > 0)) return 0;
    const fraction = value / 100.0;
    if (fraction >= 1) return 1;
    return @floatCast(fraction);
}

fn resetLabel(buf: []u8, resets_at: i64, now_ms: i64) []const u8 {
    const now_s: i64 = @divTrunc(now_ms, 1000);
    const delta = resets_at - now_s;
    if (delta <= 0) return "Resets soon";
    const minutes = @divTrunc(delta + 59, 60);
    if (minutes < 60) {
        return std.fmt.bufPrint(buf, "Resets in {d}m", .{minutes}) catch "Resets soon";
    }
    if (minutes < 24 * 60) {
        const hours = @divTrunc(minutes, 60);
        return std.fmt.bufPrint(buf, "Resets in {d}h", .{hours}) catch "Resets soon";
    }
    const days = @divTrunc(minutes, 24 * 60);
    return std.fmt.bufPrint(buf, "Resets in {d}d", .{days}) catch "Resets soon";
}

pub fn contextLabel(model: *const Model, arena: std.mem.Allocator) []const u8 {
    const session = model.sessionByIdConst(model.selected) orelse return "";
    if (session.context_size == 0) return nothing_measured;
    var buf: [48]u8 = undefined;
    const label = session.contextUsageLabel(&buf);
    if (label.len == 0) return nothing_measured;
    return copyArena(arena, label);
}

pub fn planHeader(model: *const Model, arena: std.mem.Allocator) []const u8 {
    if (!cacheMatches(model) or !model.plan_usage.present) return "Plan limits";
    const label = model.plan_usage.planLabel();
    if (label.len == 0) return "Plan limits";
    var buf: [max_line]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, "Plan limits · {s}", .{label}) catch return "Plan limits";
    return copyArena(arena, text);
}

pub fn planRows(model: *const Model, arena: std.mem.Allocator) []Row {
    if (!cacheMatches(model) or !model.plan_usage.present) return &.{};
    const count = model.plan_usage.window_count;
    if (count == 0) return &.{};
    const rows = arena.alloc(Row, count) catch return &.{};
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const window = model.plan_usage.windows[i];
        const share = clampShare(window.percent);
        var percent_buf: [16]u8 = undefined;
        const percent = std.fmt.bufPrint(&percent_buf, "{d:.0}%", .{window.percent}) catch "";
        var reset_buf: [32]u8 = undefined;
        const resets = if (window.resets_at) |at| resetLabel(&reset_buf, at, model.now_ms) else "";
        rows[i] = .{
            .id = @intCast(i + 1),
            .line = copyArena(arena, window.label()),
            .share = share,
            .percent = copyArena(arena, percent),
            .resets = copyArena(arena, resets),
            .has_resets = resets.len > 0,
        };
    }
    return rows;
}

pub fn hint(model: *const Model) []const u8 {
    const provider = selectedProvider(model) orelse return "";
    if (!isPlanUsageProvider(provider)) return "";
    if (store.resolveDaemonMirrorAddress(model).len == 0) return connect_hint;
    if (model.daemon_plan_usage_key != 0 and model.daemon_plan_usage_provider == provider) {
        if (!(cacheMatches(model) and (model.plan_usage.present or model.plan_usage.unconfigured))) {
            return loading_hint;
        }
    }
    if (cacheMatches(model) and model.plan_usage.unconfigured) return unconfigured_hint;
    if (cacheMatches(model) and model.plan_usage.errored and !model.plan_usage.present) {
        return unavailable_hint;
    }
    if (model.daemon_plan_usage_key == 0 and !cacheMatches(model)) return "";
    return "";
}

fn pendingSpawnKey(fx: *Effects, key: u64) ?@TypeOf(fx.pendingSpawnAt(0).?) {
    var i: usize = 0;
    while (fx.pendingSpawnAt(i)) |spawn| : (i += 1) {
        if (spawn.key == key) return spawn;
    }
    return null;
}

const plan_usage_ok_line = "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000018\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"planUsage\",\"usage\":{\"planLabel\":\"Max (5x)\",\"windows\":[{\"label\":\"Session\",\"percent\":42,\"resetsAt\":1750003600},{\"label\":\"Weekly\",\"percent\":80,\"resetsAt\":1750086400}]}}}}";
const plan_usage_null_line = "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000018\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"planUsage\",\"usage\":null}}}";
const plan_usage_ack_line = "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000018\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"ack\"}}}";

test "meter is available with a selected session and hidden without one" {
    var model = Model{};
    try std.testing.expect(!available(&model));
    const id = model.addSession("usage meter", .claude);
    model.selected = id;
    try std.testing.expect(available(&model));
    try std.testing.expect(isPlanUsageProvider(.claude));
    try std.testing.expect(isPlanUsageProvider(.opencode));
    try std.testing.expect(!isPlanUsageProvider(.fx));
}

test "panel open without a daemon keeps local context and a muted connect hint" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var model = Model{};
    model.setSidecarPath("faku");
    const id = model.addSession("usage local", .claude);
    model.selected = id;
    open(&model, &fx);
    try std.testing.expect(model.usage_meter_open);
    try std.testing.expectEqual(@as(u64, 0), model.daemon_plan_usage_key);
    try std.testing.expectEqualStrings(connect_hint, hint(&model));
    try std.testing.expectEqualStrings(nothing_measured, contextLabel(&model, arena));
    try std.testing.expectEqual(@as(usize, 0), planRows(&model, arena).len);

    if (model.sessionById(id)) |session| session.setContextUsage(12_400, 200_000);
    try std.testing.expectEqualStrings("12.4k / 200k", contextLabel(&model, arena));
    try std.testing.expectEqual(@as(usize, 0), model.window_status_len);
}

test "panel open with a daemon address spawns fetchPlanUsage sidecar" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    const id = model.addSession("usage daemon", .opencode);
    model.selected = id;

    open(&model, &fx);
    const sidecar = pendingSpawnKey(&fx, model.daemon_plan_usage_key) orelse return error.MissingDaemonFetchPlanUsage;
    try std.testing.expect(daemon_proxy.isSidecarArgv(sidecar.argv));
    try std.testing.expectEqualStrings("faku", sidecar.argv[0]);
    try std.testing.expectEqualStrings(daemon_proxy.SUBCOMMAND, sidecar.argv[1]);
    try std.testing.expectEqualStrings("127.0.0.1:8787", sidecar.argv[2]);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"hello\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"fetchPlanUsage\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"provider\":\"openCode\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"binaryOverride\":null") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"cliVersion\":null") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"loadUsageHistory\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"prompt\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"workspace\"") == null);
    try std.testing.expectEqual(sidecar.key, model.daemon_plan_usage_key);
    try std.testing.expectEqual(ProviderId.opencode, model.daemon_plan_usage_provider);
    try std.testing.expectEqualStrings(loading_hint, hint(&model));
}

test "fx session does not spawn fetchPlanUsage" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    const id = model.addSession("usage fx", .fx);
    model.selected = id;
    open(&model, &fx);
    try std.testing.expect(model.usage_meter_open);
    try std.testing.expectEqual(@as(u64, 0), model.daemon_plan_usage_key);
    try std.testing.expectEqualStrings("", hint(&model));
}

test "FetchPlanUsage sidecar paints lanes; null usage is unconfigured; miss keeps prior" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var model = Model{};
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    model.now_ms = 1_750_000_000_000;
    const id = model.addSession("usage paint", .claude);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setContextUsage(12_400, 200_000);

    open(&model, &fx);
    const sidecar = pendingSpawnKey(&fx, model.daemon_plan_usage_key) orelse return error.MissingDaemonFetchPlanUsageFill;
    applyLine(&model, .{ .key = sidecar.key, .line = plan_usage_ack_line });
    try std.testing.expect(!model.plan_usage.present);
    applyLine(&model, .{ .key = sidecar.key, .line = plan_usage_ok_line });
    try std.testing.expect(model.plan_usage.present);
    try std.testing.expectEqual(ProviderId.claude, model.plan_usage.provider);
    try std.testing.expectEqualStrings("Max (5x)", model.plan_usage.planLabel());
    try std.testing.expectEqual(@as(usize, 2), model.plan_usage.window_count);
    try std.testing.expectEqualStrings("Session", model.plan_usage.windows[0].label());
    try std.testing.expectApproxEqAbs(@as(f64, 42), model.plan_usage.windows[0].percent, 0.0001);
    handleExit(&model, .{ .key = sidecar.key, .reason = .exited, .code = 0 });
    try std.testing.expectEqual(@as(u64, 0), model.daemon_plan_usage_key);
    try std.testing.expectEqualStrings("Plan limits · Max (5x)", planHeader(&model, arena));
    const rows = planRows(&model, arena);
    try std.testing.expectEqual(@as(usize, 2), rows.len);
    try std.testing.expectEqualStrings("Session", rows[0].line);
    try std.testing.expectEqualStrings("42%", rows[0].percent);
    try std.testing.expect(rows[0].has_resets);
    try std.testing.expectEqualStrings("Weekly", rows[1].line);
    try std.testing.expectEqualStrings("80%", rows[1].percent);
    try std.testing.expectApproxEqAbs(@as(f32, 0.42), rows[0].share, 0.0001);
    try std.testing.expectEqualStrings("", hint(&model));
    try std.testing.expectEqualStrings("12.4k / 200k", contextLabel(&model, arena));

    refresh(&model, &fx);
    const miss = pendingSpawnKey(&fx, model.daemon_plan_usage_key) orelse return error.MissingDaemonFetchPlanUsageMiss;
    applyLine(&model, .{ .key = miss.key, .line = plan_usage_ack_line });
    handleExit(&model, .{ .key = miss.key, .reason = .exited, .code = 1 });
    try std.testing.expect(model.plan_usage.present);
    try std.testing.expectEqualStrings("Max (5x)", model.plan_usage.planLabel());
    try std.testing.expectEqual(@as(usize, 2), planRows(&model, arena).len);
    try std.testing.expectEqual(@as(usize, 0), model.window_status_len);

    refresh(&model, &fx);
    const nulled = pendingSpawnKey(&fx, model.daemon_plan_usage_key) orelse return error.MissingDaemonFetchPlanUsageNull;
    applyLine(&model, .{ .key = nulled.key, .line = plan_usage_null_line });
    handleExit(&model, .{ .key = nulled.key, .reason = .exited, .code = 0 });
    try std.testing.expect(!model.plan_usage.present);
    try std.testing.expect(model.plan_usage.unconfigured);
    try std.testing.expectEqual(@as(usize, 0), planRows(&model, arena).len);
    try std.testing.expectEqualStrings(unconfigured_hint, hint(&model));
}

test "miss without a prior snapshot shows a muted error; overflow keeps context" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    const id = model.addSession("usage miss", .grok);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setContextUsage(100, 200_000);

    open(&model, &fx);
    const sidecar = pendingSpawnKey(&fx, model.daemon_plan_usage_key) orelse return error.MissingGrokFetchPlanUsage;
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"provider\":\"grok\"") != null);
    applyLine(&model, .{ .key = sidecar.key, .line = plan_usage_ack_line });
    handleExit(&model, .{ .key = sidecar.key, .reason = .exited, .code = 1 });
    try std.testing.expect(!model.plan_usage.present);
    try std.testing.expect(model.plan_usage.errored);
    try std.testing.expectEqual(ProviderId.grok, model.plan_usage.provider);
    try std.testing.expectEqualStrings(unavailable_hint, hint(&model));
    try std.testing.expectEqual(@as(u64, 100), model.sessionById(id).?.context_used);

    var tiny: [32]u8 = undefined;
    try std.testing.expectError(error.NoSpaceLeft, daemon_proxy.writePlanUsageStdin(&tiny, .{
        .provider = "claude",
    }));
}

test "opening again cancels an in-flight sidecar for the same provider" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    const id = model.addSession("usage replace", .codex);
    model.selected = id;
    open(&model, &fx);
    const first = pendingSpawnKey(&fx, model.daemon_plan_usage_key) orelse return error.MissingFirstPlanUsage;
    const first_key = first.key;
    refresh(&model, &fx);
    try std.testing.expect(model.daemon_plan_usage_key != first_key);
    const second = pendingSpawnKey(&fx, model.daemon_plan_usage_key) orelse return error.MissingReplacedPlanUsage;
    try std.testing.expect(std.mem.indexOf(u8, second.stdin, "\"provider\":\"codex\"") != null);
    try std.testing.expect(pendingSpawnKey(&fx, first_key) == null);
}
