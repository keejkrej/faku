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
//! Closing the panel leaves the runtime map. Refresh re-spawns the
//! selected provider immediately (cancel that slot's in-flight only).
//! First-cut Waku cadence ships as `maybeRefresh` on the existing
//! `now_ms` / update tick (Native has no dedicated timer): loop all
//! four plan-usage providers (Claude / Codex / OpenCode / Grok);
//! 300s idle, 600s Grok, 30s when that slot is stale (panel open /
//! turn settle), 90s after that slot's fetch error. Skip a provider
//! that already has an in-flight sidecar (`pending_key != 0`); unset
//! per-provider `checked_at` may fire once when eligible. Open marks
//! the selected slot stale then still fetches that provider
//! immediately. Hello stays v4. First-cut plan_usage map is four
//! runtime slots (not a HashMap); each slot owns its `pending_key`.
//! Switching session/provider shows that slot immediately and does
//! not clear the others. Waku also skips disabled providers unless
//! selected — Faku has no `provider_enabled` gate yet, so this cut
//! always considers all four. Still not a circular GPUI gauge, not
//! LiteLLM, not a T3 chart.

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

/// Waku `PLAN_USAGE_REFRESH`. Idle default for Claude / Codex / OpenCode.
pub const plan_usage_refresh_ms: i64 = 300_000;
/// Waku `PLAN_USAGE_REFRESH_GROK`. Grok idle; the probe is heavier.
pub const plan_usage_refresh_grok_ms: i64 = 600_000;
/// Waku `PLAN_USAGE_REFRESH_STALE`. After panel open / a settled turn.
pub const plan_usage_refresh_stale_ms: i64 = 30_000;
/// Waku `PLAN_USAGE_RETRY`. After that provider's fetch error.
pub const plan_usage_retry_ms: i64 = 90_000;

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

/// Waku `PLAN_USAGE_PROVIDERS`. Closed set; not a HashMap. Faku has
/// no `provider_enabled` gate yet, so `maybeRefresh` always walks
/// this list (Waku would skip disabled ids unless selected).
pub const plan_usage_providers = [_]ProviderId{ .claude, .codex, .opencode, .grok };

/// One provider's runtime snapshot plus Waku-shaped cadence fields.
pub const Slot = struct {
    cache: Cache = .{},
    /// Last settled `fetchPlanUsage` for this provider (`now_ms`).
    /// Null until the first applyLine / handleExit. Runtime-only.
    checked_at: ?i64 = null,
    /// This provider's path is stale (panel open or a settled turn
    /// moved rate-limit needles). Runtime-only; cleared when a fetch
    /// for this provider settles.
    stale: bool = false,
    /// In-flight `fetchPlanUsage` sidecar key for this provider.
    /// 0 means none. Slot-local so `maybeRefresh` can spawn other
    /// providers concurrently. Runtime-only; not sessions.json.
    pending_key: u64 = 0,
};

/// First-cut plan_usage map: four runtime slots for the closed
/// `isPlanUsageProvider` set. Not a HashMap — the set is Claude /
/// Codex / OpenCode / Grok. Adopt / error write the slot whose
/// `pending_key` matched the sidecar; view helpers read the selected
/// slot. Switching session/provider must not clear the other three.
/// Each slot's `pending_key` is the in-flight gate (the singular
/// Model `daemon_plan_usage_key` / `daemon_plan_usage_provider`
/// pair is retired).
pub const Map = struct {
    claude: Slot = .{ .cache = .{ .provider = .claude } },
    codex: Slot = .{ .cache = .{ .provider = .codex } },
    opencode: Slot = .{ .cache = .{ .provider = .opencode } },
    grok: Slot = .{ .cache = .{ .provider = .grok } },

    pub fn get(self: *Map, id: ProviderId) ?*Slot {
        return switch (id) {
            .claude => &self.claude,
            .codex => &self.codex,
            .opencode => &self.opencode,
            .grok => &self.grok,
            else => null,
        };
    }

    pub fn getConst(self: *const Map, id: ProviderId) ?*const Slot {
        return switch (id) {
            .claude => &self.claude,
            .codex => &self.codex,
            .opencode => &self.opencode,
            .grok => &self.grok,
            else => null,
        };
    }

    pub fn slotForPendingKey(self: *Map, key: u64) ?*Slot {
        if (key == 0) return null;
        if (self.claude.pending_key == key) return &self.claude;
        if (self.codex.pending_key == key) return &self.codex;
        if (self.opencode.pending_key == key) return &self.opencode;
        if (self.grok.pending_key == key) return &self.grok;
        return null;
    }

    pub fn slotConstForPendingKey(self: *const Map, key: u64) ?*const Slot {
        if (key == 0) return null;
        if (self.claude.pending_key == key) return &self.claude;
        if (self.codex.pending_key == key) return &self.codex;
        if (self.opencode.pending_key == key) return &self.opencode;
        if (self.grok.pending_key == key) return &self.grok;
        return null;
    }

    pub fn isPendingKey(self: *const Map, key: u64) bool {
        return self.slotConstForPendingKey(key) != null;
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

pub fn slot(model: *Model, id: ProviderId) ?*Slot {
    return model.plan_usage.get(id);
}

pub fn slotConst(model: *const Model, id: ProviderId) ?*const Slot {
    return model.plan_usage.getConst(id);
}

pub fn selectedSlot(model: *Model) ?*Slot {
    return slot(model, selectedProvider(model) orelse return null);
}

pub fn selectedSlotConst(model: *const Model) ?*const Slot {
    return slotConst(model, selectedProvider(model) orelse return null);
}

pub fn selectedCache(model: *const Model) ?*const Cache {
    const found = selectedSlotConst(model) orelse return null;
    return &found.cache;
}

pub fn selectedStale(model: *const Model) bool {
    const found = selectedSlotConst(model) orelse return false;
    return found.stale;
}

pub fn selectedCheckedAt(model: *const Model) ?i64 {
    const found = selectedSlotConst(model) orelse return null;
    return found.checked_at;
}

pub fn pendingKey(model: *const Model, id: ProviderId) u64 {
    const found = slotConst(model, id) orelse return 0;
    return found.pending_key;
}

pub fn selectedPendingKey(model: *const Model) u64 {
    const found = selectedSlotConst(model) orelse return 0;
    return found.pending_key;
}

pub fn isPendingKey(model: *const Model, key: u64) bool {
    return model.plan_usage.isPendingKey(key);
}

fn cacheMatches(model: *const Model) bool {
    const provider = selectedProvider(model) orelse return false;
    const found = slotConst(model, provider) orelse return false;
    return found.cache.provider == provider;
}

fn slotHasSnapshot(found: *const Slot) bool {
    return found.cache.present or found.cache.unconfigured or found.cache.errored;
}

fn cancelProvider(model: *Model, fx: *Effects, provider: ProviderId) void {
    const found = slot(model, provider) orelse return;
    if (found.pending_key == 0) return;
    fx.cancel(found.pending_key);
    found.pending_key = 0;
}

/// Cancel every in-flight `fetchPlanUsage` sidecar. Teardown only;
/// open / Refresh cancel the selected provider via `ensure`.
pub fn cancel(model: *Model, fx: *Effects) void {
    for (plan_usage_providers) |id| {
        cancelProvider(model, fx, id);
    }
}

pub fn close(model: *Model) void {
    model.usage_meter_open = false;
}

pub fn open(model: *Model, fx: *Effects) void {
    model.usage_meter_open = true;
    markSelectedStale(model);
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

/// Session / provider change: show the selected provider's slot
/// immediately when it already has a snapshot (or unconfigured /
/// errored). Else load when the panel is open. Other slots stay.
pub fn onSessionChange(model: *Model, fx: *Effects) void {
    if (!model.usage_meter_open) return;
    ensure(model, fx, false);
}

/// First-cut Waku `maybe_refresh_plan_usage`: loop Claude / Codex /
/// OpenCode / Grok. Skip a provider that already has `pending_key`.
/// Faku has no `provider_enabled` gate yet, so every id is eligible
/// (Waku would skip disabled unless selected). Interval is error →
/// 90s, else stale → 30s, else Grok → 600s, else 300s, all from that
/// provider's slot. Unset per-provider `checked_at` may fire once
/// when eligible. Does not cancel in-flight (open / Refresh stay the
/// selected-only force path). In-flight for A does not block B.
pub fn maybeRefresh(model: *Model, fx: *Effects) void {
    if (store.resolveDaemonMirrorAddress(model).len == 0) return;
    for (plan_usage_providers) |provider| {
        maybeRefreshProvider(model, fx, provider);
    }
}

fn maybeRefreshProvider(model: *Model, fx: *Effects, provider: ProviderId) void {
    const found = slotConst(model, provider) orelse return;
    if (found.pending_key != 0) return;
    if (found.checked_at) |last| {
        if (model.now_ms >= last and model.now_ms - last < refreshIntervalMs(found, provider)) {
            return;
        }
    }
    _ = trySpawn(model, fx, provider);
}

/// Waku `TurnFinished`: a settled turn moved rate-limit needles.
/// Marks that session's provider slot stale when the provider is
/// Claude / Codex / OpenCode / Grok. Next `maybeRefresh` on that
/// selected path uses 30s unless a fetch error still owns the 90s
/// retry. Other providers' slots stay.
pub fn markStaleForSession(model: *Model, session_id: u32) void {
    const session = model.sessionByIdConst(session_id) orelse return;
    if (!isPlanUsageProvider(session.provider)) return;
    const found = slot(model, session.provider) orelse return;
    found.stale = true;
}

fn markSelectedStale(model: *Model) void {
    const found = selectedSlot(model) orelse return;
    if (!isPlanUsageProvider(found.cache.provider)) return;
    found.stale = true;
}

fn refreshIntervalMs(found: *const Slot, provider: ProviderId) i64 {
    if (found.cache.errored) return plan_usage_retry_ms;
    if (found.stale) return plan_usage_refresh_stale_ms;
    if (provider == .grok) return plan_usage_refresh_grok_ms;
    return plan_usage_refresh_ms;
}

fn noteFetchSettled(model: *Model, provider: ProviderId) void {
    const found = slot(model, provider) orelse return;
    found.stale = false;
    found.checked_at = model.now_ms;
}

fn ensure(model: *Model, fx: *Effects, force: bool) void {
    const provider = selectedProvider(model) orelse return;
    if (!isPlanUsageProvider(provider)) return;
    const found = slot(model, provider) orelse return;
    if (!force) {
        if (found.pending_key != 0) return;
        if (slotHasSnapshot(found)) return;
    }
    cancelProvider(model, fx, provider);
    _ = trySpawn(model, fx, provider);
}

fn trySpawn(model: *Model, fx: *Effects, provider: ProviderId) bool {
    const address = store.resolveDaemonMirrorAddress(model);
    if (address.len == 0) return false;
    const found = slot(model, provider) orelse return false;
    if (found.pending_key != 0) return false;

    var stdin_buf: [4096]u8 = undefined;
    const stdin = daemon_proxy.writePlanUsageStdin(&stdin_buf, .{
        .token = model.daemonToken(),
        .provider = provider.daemonProviderKind(),
    }) catch return false;

    const key = model.next_daemon_key;
    model.next_daemon_key += 1;
    found.pending_key = key;
    found.cache.adopted_ok = false;
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
    const found = model.plan_usage.slotForPendingKey(line.key) orelse return;
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const parsed = protocol.parsePlanUsage(arena_state.allocator(), line.line);
    if (!parsed.ok) return;
    const pending = found.cache.provider;
    adopt(&found.cache, pending, parsed);
    noteFetchSettled(model, pending);
}

pub fn handleExit(model: *Model, exit: native_sdk.EffectExit) void {
    const found = model.plan_usage.slotForPendingKey(exit.key) orelse return;
    const pending = found.cache.provider;
    found.pending_key = 0;
    noteFetchSettled(model, pending);
    if (found.cache.adopted_ok) return;
    found.cache.errored = true;
    if (found.cache.present) return;
    found.cache.provider = pending;
    found.cache.unconfigured = false;
    found.cache.window_count = 0;
    found.cache.plan_label_len = 0;
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
    const cache = selectedCache(model) orelse return "Plan limits";
    if (!cacheMatches(model) or !cache.present) return "Plan limits";
    const label = cache.planLabel();
    if (label.len == 0) return "Plan limits";
    var buf: [max_line]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, "Plan limits · {s}", .{label}) catch return "Plan limits";
    return copyArena(arena, text);
}

pub fn planRows(model: *const Model, arena: std.mem.Allocator) []Row {
    const cache = selectedCache(model) orelse return &.{};
    if (!cacheMatches(model) or !cache.present) return &.{};
    const count = cache.window_count;
    if (count == 0) return &.{};
    const rows = arena.alloc(Row, count) catch return &.{};
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const window = cache.windows[i];
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
    const cache = selectedCache(model) orelse return "";
    if (pendingKey(model, provider) != 0) {
        if (!(cache.present or cache.unconfigured)) {
            return loading_hint;
        }
    }
    if (cache.unconfigured) return unconfigured_hint;
    if (cache.errored and !cache.present) return unavailable_hint;
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
const plan_usage_codex_line = "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000018\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"planUsage\",\"usage\":{\"planLabel\":\"Plus\",\"windows\":[{\"label\":\"5h\",\"percent\":10,\"resetsAt\":1750003600}]}}}}";
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
    try std.testing.expect(model.plan_usage.claude.stale);
    try std.testing.expectEqual(@as(u64, 0), selectedPendingKey(&model));
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
    try std.testing.expect(model.plan_usage.opencode.stale);
    const sidecar = pendingSpawnKey(&fx, selectedPendingKey(&model)) orelse return error.MissingDaemonFetchPlanUsage;
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
    try std.testing.expectEqual(sidecar.key, selectedPendingKey(&model));
    try std.testing.expectEqual(ProviderId.opencode, model.plan_usage.opencode.cache.provider);
    try std.testing.expectEqual(sidecar.key, pendingKey(&model, .opencode));
    try std.testing.expectEqual(@as(u64, 0), pendingKey(&model, .claude));
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
    try std.testing.expect(!selectedStale(&model));
    try std.testing.expectEqual(@as(u64, 0), selectedPendingKey(&model));
    try std.testing.expectEqual(@as(u64, 0), pendingKey(&model, .claude));
    try std.testing.expectEqual(@as(u64, 0), pendingKey(&model, .codex));
    try std.testing.expectEqual(@as(u64, 0), pendingKey(&model, .opencode));
    try std.testing.expectEqual(@as(u64, 0), pendingKey(&model, .grok));
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
    const sidecar = pendingSpawnKey(&fx, selectedPendingKey(&model)) orelse return error.MissingDaemonFetchPlanUsageFill;
    applyLine(&model, .{ .key = sidecar.key, .line = plan_usage_ack_line });
    try std.testing.expect(!model.plan_usage.claude.cache.present);
    applyLine(&model, .{ .key = sidecar.key, .line = plan_usage_ok_line });
    try std.testing.expect(model.plan_usage.claude.cache.present);
    try std.testing.expectEqual(ProviderId.claude, model.plan_usage.claude.cache.provider);
    try std.testing.expectEqualStrings("Max (5x)", model.plan_usage.claude.cache.planLabel());
    try std.testing.expectEqual(@as(usize, 2), model.plan_usage.claude.cache.window_count);
    try std.testing.expectEqualStrings("Session", model.plan_usage.claude.cache.windows[0].label());
    try std.testing.expectApproxEqAbs(@as(f64, 42), model.plan_usage.claude.cache.windows[0].percent, 0.0001);
    handleExit(&model, .{ .key = sidecar.key, .reason = .exited, .code = 0 });
    try std.testing.expectEqual(@as(u64, 0), selectedPendingKey(&model));
    try std.testing.expect(!model.plan_usage.claude.stale);
    try std.testing.expectEqual(@as(?i64, 1_750_000_000_000), model.plan_usage.claude.checked_at);
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
    const miss = pendingSpawnKey(&fx, selectedPendingKey(&model)) orelse return error.MissingDaemonFetchPlanUsageMiss;
    applyLine(&model, .{ .key = miss.key, .line = plan_usage_ack_line });
    handleExit(&model, .{ .key = miss.key, .reason = .exited, .code = 1 });
    try std.testing.expect(model.plan_usage.claude.cache.present);
    try std.testing.expect(model.plan_usage.claude.cache.errored);
    try std.testing.expect(!model.plan_usage.claude.stale);
    try std.testing.expectEqualStrings("Max (5x)", model.plan_usage.claude.cache.planLabel());
    try std.testing.expectEqual(@as(usize, 2), planRows(&model, arena).len);
    try std.testing.expectEqual(@as(usize, 0), model.window_status_len);

    refresh(&model, &fx);
    const nulled = pendingSpawnKey(&fx, selectedPendingKey(&model)) orelse return error.MissingDaemonFetchPlanUsageNull;
    applyLine(&model, .{ .key = nulled.key, .line = plan_usage_null_line });
    handleExit(&model, .{ .key = nulled.key, .reason = .exited, .code = 0 });
    try std.testing.expect(!model.plan_usage.claude.cache.present);
    try std.testing.expect(model.plan_usage.claude.cache.unconfigured);
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
    const sidecar = pendingSpawnKey(&fx, selectedPendingKey(&model)) orelse return error.MissingGrokFetchPlanUsage;
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"provider\":\"grok\"") != null);
    applyLine(&model, .{ .key = sidecar.key, .line = plan_usage_ack_line });
    handleExit(&model, .{ .key = sidecar.key, .reason = .exited, .code = 1 });
    try std.testing.expect(!model.plan_usage.grok.cache.present);
    try std.testing.expect(model.plan_usage.grok.cache.errored);
    try std.testing.expect(!model.plan_usage.grok.stale);
    try std.testing.expectEqual(@as(?i64, 0), model.plan_usage.grok.checked_at);
    try std.testing.expectEqual(ProviderId.grok, model.plan_usage.grok.cache.provider);
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
    const first = pendingSpawnKey(&fx, selectedPendingKey(&model)) orelse return error.MissingFirstPlanUsage;
    const first_key = first.key;
    refresh(&model, &fx);
    try std.testing.expect(selectedPendingKey(&model) != first_key);
    const second = pendingSpawnKey(&fx, selectedPendingKey(&model)) orelse return error.MissingReplacedPlanUsage;
    try std.testing.expect(std.mem.indexOf(u8, second.stdin, "\"provider\":\"codex\"") != null);
    try std.testing.expect(pendingSpawnKey(&fx, first_key) == null);
}

fn seedCadenceModel(provider: ProviderId) Model {
    var model = Model{};
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    model.now_ms = 10_000;
    const id = model.addSession("usage cadence", provider);
    model.selected = id;
    return model;
}

fn finishPlanUsageOk(model: *Model) void {
    const key = selectedPendingKey(model);
    applyLine(model, .{ .key = key, .line = plan_usage_ok_line });
    handleExit(model, .{ .key = key, .reason = .exited, .code = 0 });
}

fn finishPlanUsageLine(model: *Model, line: []const u8) void {
    const key = selectedPendingKey(model);
    applyLine(model, .{ .key = key, .line = line });
    handleExit(model, .{ .key = key, .reason = .exited, .code = 0 });
}

fn finishPlanUsageErr(model: *Model) void {
    const key = selectedPendingKey(model);
    applyLine(model, .{ .key = key, .line = plan_usage_ack_line });
    handleExit(model, .{ .key = key, .reason = .exited, .code = 1 });
}

test "maybeRefresh skips inside 300s; unset checked_at fires once" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = seedCadenceModel(.claude);
    try std.testing.expectEqual(@as(?i64, null), selectedCheckedAt(&model));
    maybeRefresh(&model, &fx);
    const first = pendingSpawnKey(&fx, selectedPendingKey(&model)) orelse return error.MissingUnsetCheckedAt;
    try std.testing.expect(std.mem.indexOf(u8, first.stdin, "\"type\":\"fetchPlanUsage\"") != null);
    finishPlanUsageOk(&model);
    try std.testing.expectEqual(@as(?i64, 10_000), selectedCheckedAt(&model));
    try std.testing.expect(!selectedStale(&model));

    maybeRefresh(&model, &fx);
    try std.testing.expectEqual(@as(u64, 0), selectedPendingKey(&model));

    model.now_ms = 10_000 + plan_usage_refresh_ms - 1;
    maybeRefresh(&model, &fx);
    try std.testing.expectEqual(@as(u64, 0), selectedPendingKey(&model));

    model.now_ms = 10_000 + plan_usage_refresh_ms;
    maybeRefresh(&model, &fx);
    const aged = pendingSpawnKey(&fx, selectedPendingKey(&model)) orelse return error.MissingClaudeIdleRefresh;
    try std.testing.expect(aged.key != first.key);
    try std.testing.expect(std.mem.indexOf(u8, aged.stdin, "\"provider\":\"claude\"") != null);
}

test "maybeRefresh uses 600s idle for Grok" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = seedCadenceModel(.grok);
    maybeRefresh(&model, &fx);
    _ = pendingSpawnKey(&fx, selectedPendingKey(&model)) orelse return error.MissingGrokCheckedAt;
    finishPlanUsageOk(&model);

    model.now_ms = 10_000 + plan_usage_refresh_ms;
    maybeRefresh(&model, &fx);
    try std.testing.expectEqual(@as(u64, 0), selectedPendingKey(&model));

    model.now_ms = 10_000 + plan_usage_refresh_grok_ms - 1;
    maybeRefresh(&model, &fx);
    try std.testing.expectEqual(@as(u64, 0), selectedPendingKey(&model));

    model.now_ms = 10_000 + plan_usage_refresh_grok_ms;
    maybeRefresh(&model, &fx);
    const aged = pendingSpawnKey(&fx, selectedPendingKey(&model)) orelse return error.MissingGrokIdleRefresh;
    try std.testing.expect(std.mem.indexOf(u8, aged.stdin, "\"provider\":\"grok\"") != null);
}

test "maybeRefresh uses 30s when stale" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = seedCadenceModel(.claude);
    maybeRefresh(&model, &fx);
    finishPlanUsageOk(&model);
    markStaleForSession(&model, model.selected);
    try std.testing.expect(selectedStale(&model));

    model.now_ms = 10_000 + plan_usage_refresh_stale_ms - 1;
    maybeRefresh(&model, &fx);
    try std.testing.expectEqual(@as(u64, 0), selectedPendingKey(&model));

    model.now_ms = 10_000 + plan_usage_refresh_stale_ms;
    maybeRefresh(&model, &fx);
    _ = pendingSpawnKey(&fx, selectedPendingKey(&model)) orelse return error.MissingStaleRefresh;
}

test "maybeRefresh uses 90s after a fetch error" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = seedCadenceModel(.claude);
    maybeRefresh(&model, &fx);
    finishPlanUsageErr(&model);
    try std.testing.expect(model.plan_usage.claude.cache.errored);
    try std.testing.expect(!selectedStale(&model));
    markStaleForSession(&model, model.selected);
    try std.testing.expect(selectedStale(&model));

    model.now_ms = 10_000 + plan_usage_refresh_stale_ms;
    maybeRefresh(&model, &fx);
    try std.testing.expectEqual(@as(u64, 0), selectedPendingKey(&model));

    model.now_ms = 10_000 + plan_usage_retry_ms - 1;
    maybeRefresh(&model, &fx);
    try std.testing.expectEqual(@as(u64, 0), selectedPendingKey(&model));

    model.now_ms = 10_000 + plan_usage_retry_ms;
    maybeRefresh(&model, &fx);
    _ = pendingSpawnKey(&fx, selectedPendingKey(&model)) orelse return error.MissingErrorRetry;
}

test "maybeRefresh skips while a plan-usage sidecar is in flight" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = seedCadenceModel(.claude);
    maybeRefresh(&model, &fx);
    const first = pendingSpawnKey(&fx, selectedPendingKey(&model)) orelse return error.MissingInFlightFirst;
    const first_key = first.key;
    model.now_ms = 10_000 + plan_usage_refresh_ms;
    maybeRefresh(&model, &fx);
    try std.testing.expectEqual(first_key, selectedPendingKey(&model));
    try std.testing.expect(pendingSpawnKey(&fx, first_key) != null);
}

test "open marks stale then still fetches immediately" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = seedCadenceModel(.claude);
    model.plan_usage.claude.checked_at = 10_000;
    open(&model, &fx);
    try std.testing.expect(selectedStale(&model));
    const sidecar = pendingSpawnKey(&fx, selectedPendingKey(&model)) orelse return error.MissingOpenForceFetch;
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"fetchPlanUsage\"") != null);
}

test "turn settle marks stale for plan-usage providers only" {
    var model = seedCadenceModel(.claude);
    try std.testing.expect(!selectedStale(&model));
    markStaleForSession(&model, model.selected);
    try std.testing.expect(selectedStale(&model));

    var fx_model = seedCadenceModel(.fx);
    markStaleForSession(&fx_model, fx_model.selected);
    try std.testing.expect(!selectedStale(&fx_model));
    try std.testing.expect(!fx_model.plan_usage.claude.stale);
    markStaleForSession(&fx_model, 0);
    try std.testing.expect(!selectedStale(&fx_model));
}

test "update tick path maybeRefresh after 300s; open path still immediate" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;
    var clock = native_sdk.TestClock{};
    clock.setWallMs(1_000);
    fx.clock = clock.clock();

    var model = Model{};
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    const id = model.addSession("usage update tick", .claude);
    model.selected = id;

    main.update(&model, .close_environment_summary, &fx);
    const open_key = selectedPendingKey(&model);
    try std.testing.expect(open_key != 0);
    finishPlanUsageOk(&model);
    try std.testing.expectEqual(@as(?i64, 1_000), selectedCheckedAt(&model));

    clock.setWallMs(1_000 + plan_usage_refresh_ms - 1);
    main.update(&model, .close_environment_summary, &fx);
    try std.testing.expectEqual(@as(u64, 0), selectedPendingKey(&model));

    clock.setWallMs(1_000 + plan_usage_refresh_ms);
    main.update(&model, .close_environment_summary, &fx);
    const tick = pendingSpawnKey(&fx, selectedPendingKey(&model)) orelse return error.MissingUpdateTickPlanUsage;
    try std.testing.expect(tick.key != open_key);
    try std.testing.expect(std.mem.indexOf(u8, tick.stdin, "\"type\":\"fetchPlanUsage\"") != null);
    try std.testing.expectEqual(@as(?i64, 1_000), selectedCheckedAt(&model));

    finishPlanUsageOk(&model);
    open(&model, &fx);
    const forced = pendingSpawnKey(&fx, selectedPendingKey(&model)) orelse return error.MissingOpenAfterTick;
    try std.testing.expect(forced.key != tick.key);
}

test "Claude cache survives switch to Codex and back without forced refetch when still fresh" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var model = seedCadenceModel(.claude);
    const claude_id = model.selected;
    const codex_id = model.addSession("usage cadence codex", .codex);

    open(&model, &fx);
    finishPlanUsageOk(&model);
    try std.testing.expect(model.plan_usage.claude.cache.present);
    try std.testing.expectEqualStrings("Max (5x)", model.plan_usage.claude.cache.planLabel());
    try std.testing.expectEqual(@as(?i64, 10_000), model.plan_usage.claude.checked_at);
    try std.testing.expect(!model.plan_usage.codex.cache.present);

    model.selected = codex_id;
    onSessionChange(&model, &fx);
    const codex_spawn = pendingSpawnKey(&fx, selectedPendingKey(&model)) orelse return error.MissingCodexFetchAfterSwitch;
    try std.testing.expect(std.mem.indexOf(u8, codex_spawn.stdin, "\"provider\":\"codex\"") != null);
    try std.testing.expect(model.plan_usage.claude.cache.present);
    try std.testing.expectEqualStrings("Max (5x)", model.plan_usage.claude.cache.planLabel());
    finishPlanUsageLine(&model, plan_usage_codex_line);
    try std.testing.expect(model.plan_usage.codex.cache.present);
    try std.testing.expectEqualStrings("Plus", model.plan_usage.codex.cache.planLabel());
    try std.testing.expectEqualStrings("5h", model.plan_usage.codex.cache.windows[0].label());
    try std.testing.expectEqualStrings("Plan limits · Plus", planHeader(&model, arena));
    try std.testing.expectEqual(@as(usize, 1), planRows(&model, arena).len);

    model.now_ms = 10_000 + 1_000;
    model.selected = claude_id;
    onSessionChange(&model, &fx);
    try std.testing.expectEqual(@as(u64, 0), selectedPendingKey(&model));
    try std.testing.expectEqualStrings("Plan limits · Max (5x)", planHeader(&model, arena));
    try std.testing.expectEqual(@as(usize, 2), planRows(&model, arena).len);
    try std.testing.expectEqualStrings("Session", planRows(&model, arena)[0].line);
    try std.testing.expect(model.plan_usage.codex.cache.present);
    try std.testing.expectEqualStrings("Plus", model.plan_usage.codex.cache.planLabel());

    maybeRefresh(&model, &fx);
    try std.testing.expectEqual(@as(u64, 0), selectedPendingKey(&model));
    try std.testing.expect(model.plan_usage.claude.cache.present);
    try std.testing.expectEqualStrings("Plan limits · Max (5x)", planHeader(&model, arena));
    try std.testing.expect(pendingKey(&model, .opencode) != 0);
    try std.testing.expect(pendingKey(&model, .grok) != 0);
}

test "per-provider stale and checked_at isolation" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = seedCadenceModel(.claude);
    const claude_id = model.selected;
    const grok_id = model.addSession("usage cadence grok", .grok);

    maybeRefresh(&model, &fx);
    finishPlanUsageOk(&model);
    markStaleForSession(&model, claude_id);
    try std.testing.expect(model.plan_usage.claude.stale);
    try std.testing.expectEqual(@as(?i64, 10_000), model.plan_usage.claude.checked_at);
    try std.testing.expect(!model.plan_usage.grok.stale);
    try std.testing.expectEqual(@as(?i64, null), model.plan_usage.grok.checked_at);

    model.selected = grok_id;
    maybeRefresh(&model, &fx);
    const grok_spawn = pendingSpawnKey(&fx, selectedPendingKey(&model)) orelse return error.MissingGrokFetchAfterSwitch;
    try std.testing.expect(std.mem.indexOf(u8, grok_spawn.stdin, "\"provider\":\"grok\"") != null);
    finishPlanUsageErr(&model);
    try std.testing.expect(model.plan_usage.grok.cache.errored);
    try std.testing.expect(!model.plan_usage.grok.cache.present);
    try std.testing.expectEqual(@as(?i64, 10_000), model.plan_usage.grok.checked_at);
    try std.testing.expect(model.plan_usage.claude.cache.present);
    try std.testing.expect(model.plan_usage.claude.stale);
    try std.testing.expectEqual(@as(?i64, 10_000), model.plan_usage.claude.checked_at);
    try std.testing.expectEqualStrings("Max (5x)", model.plan_usage.claude.cache.planLabel());

    model.now_ms = 10_000 + plan_usage_refresh_stale_ms;
    maybeRefresh(&model, &fx);
    try std.testing.expectEqual(@as(u64, 0), selectedPendingKey(&model));

    model.selected = claude_id;
    maybeRefresh(&model, &fx);
    const stale_claude = pendingSpawnKey(&fx, selectedPendingKey(&model)) orelse return error.MissingClaudeStaleAfterGrok;
    try std.testing.expect(std.mem.indexOf(u8, stale_claude.stdin, "\"provider\":\"claude\"") != null);
}

test "maybeRefresh starts fetches for two due providers concurrently" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = seedCadenceModel(.claude);
    maybeRefresh(&model, &fx);
    const claude_key = pendingKey(&model, .claude);
    const codex_key = pendingKey(&model, .codex);
    const opencode_key = pendingKey(&model, .opencode);
    const grok_key = pendingKey(&model, .grok);
    try std.testing.expect(claude_key != 0);
    try std.testing.expect(codex_key != 0);
    try std.testing.expect(opencode_key != 0);
    try std.testing.expect(grok_key != 0);
    try std.testing.expect(claude_key != codex_key);
    try std.testing.expect(claude_key != grok_key);
    try std.testing.expect(codex_key != opencode_key);
    const claude_spawn = pendingSpawnKey(&fx, claude_key) orelse return error.MissingClaudeConcurrent;
    const codex_spawn = pendingSpawnKey(&fx, codex_key) orelse return error.MissingCodexConcurrent;
    const grok_spawn = pendingSpawnKey(&fx, grok_key) orelse return error.MissingGrokConcurrent;
    try std.testing.expect(std.mem.indexOf(u8, claude_spawn.stdin, "\"provider\":\"claude\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, codex_spawn.stdin, "\"provider\":\"codex\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, grok_spawn.stdin, "\"provider\":\"grok\"") != null);
}

test "in-flight for provider A does not block refreshing due provider B" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = seedCadenceModel(.claude);
    model.plan_usage.codex.checked_at = 10_000;
    model.plan_usage.opencode.checked_at = 10_000;
    model.plan_usage.grok.checked_at = 10_000;
    maybeRefresh(&model, &fx);
    const claude_key = pendingKey(&model, .claude);
    try std.testing.expect(claude_key != 0);
    try std.testing.expectEqual(@as(u64, 0), pendingKey(&model, .codex));

    model.plan_usage.codex.checked_at = null;
    maybeRefresh(&model, &fx);
    try std.testing.expectEqual(claude_key, pendingKey(&model, .claude));
    try std.testing.expect(pendingSpawnKey(&fx, claude_key) != null);
    const codex_key = pendingKey(&model, .codex);
    try std.testing.expect(codex_key != 0);
    try std.testing.expect(codex_key != claude_key);
    const codex_spawn = pendingSpawnKey(&fx, codex_key) orelse return error.MissingCodexWhileClaudeInFlight;
    try std.testing.expect(std.mem.indexOf(u8, codex_spawn.stdin, "\"provider\":\"codex\"") != null);
    try std.testing.expectEqual(@as(u64, 0), pendingKey(&model, .opencode));
    try std.testing.expectEqual(@as(u64, 0), pendingKey(&model, .grok));
}

test "selected force open/refresh cancels only that provider's pending" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = seedCadenceModel(.claude);
    maybeRefresh(&model, &fx);
    const claude_first = pendingKey(&model, .claude);
    const codex_key = pendingKey(&model, .codex);
    const grok_key = pendingKey(&model, .grok);
    try std.testing.expect(claude_first != 0);
    try std.testing.expect(codex_key != 0);
    try std.testing.expect(grok_key != 0);

    open(&model, &fx);
    try std.testing.expect(selectedStale(&model));
    try std.testing.expect(selectedPendingKey(&model) != claude_first);
    try std.testing.expectEqual(codex_key, pendingKey(&model, .codex));
    try std.testing.expectEqual(grok_key, pendingKey(&model, .grok));
    try std.testing.expect(pendingSpawnKey(&fx, claude_first) == null);
    try std.testing.expect(pendingSpawnKey(&fx, codex_key) != null);
    try std.testing.expect(pendingSpawnKey(&fx, grok_key) != null);
    const replaced = pendingSpawnKey(&fx, selectedPendingKey(&model)) orelse return error.MissingClaudeForceReplace;
    try std.testing.expect(std.mem.indexOf(u8, replaced.stdin, "\"provider\":\"claude\"") != null);

    refresh(&model, &fx);
    try std.testing.expect(selectedPendingKey(&model) != replaced.key);
    try std.testing.expectEqual(codex_key, pendingKey(&model, .codex));
    try std.testing.expectEqual(grok_key, pendingKey(&model, .grok));
    try std.testing.expect(pendingSpawnKey(&fx, replaced.key) == null);
    try std.testing.expect(pendingSpawnKey(&fx, codex_key) != null);
}

test "applyLine and handleExit resolve provider from slot pending_key" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var model = seedCadenceModel(.claude);
    maybeRefresh(&model, &fx);
    const claude_key = pendingKey(&model, .claude);
    const codex_key = pendingKey(&model, .codex);
    try std.testing.expect(claude_key != 0);
    try std.testing.expect(codex_key != 0);

    applyLine(&model, .{ .key = claude_key, .line = plan_usage_ok_line });
    handleExit(&model, .{ .key = claude_key, .reason = .exited, .code = 0 });
    try std.testing.expectEqual(@as(u64, 0), pendingKey(&model, .claude));
    try std.testing.expectEqual(codex_key, pendingKey(&model, .codex));
    try std.testing.expect(model.plan_usage.claude.cache.present);
    try std.testing.expect(!model.plan_usage.codex.cache.present);

    applyLine(&model, .{ .key = codex_key, .line = plan_usage_codex_line });
    handleExit(&model, .{ .key = codex_key, .reason = .exited, .code = 0 });
    try std.testing.expectEqual(@as(u64, 0), pendingKey(&model, .codex));
    try std.testing.expect(model.plan_usage.codex.cache.present);
    try std.testing.expectEqualStrings("Plus", model.plan_usage.codex.cache.planLabel());
    try std.testing.expectEqualStrings("Max (5x)", model.plan_usage.claude.cache.planLabel());

    const codex_id = model.addSession("usage concurrent codex", .codex);
    model.selected = codex_id;
    try std.testing.expectEqualStrings("Plan limits · Plus", planHeader(&model, arena));
    try std.testing.expectEqual(@as(usize, 1), planRows(&model, arena).len);
}
