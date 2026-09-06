//! First-cut daemon `Command::LoadUsageHistory`.
//!
//! When Settings → Usage opens or Refresh is pressed and
//! `WAKU_DAEMON_ADDRESS` or persisted `last_daemon_address` is set,
//! Faku one-shots hello + `loadUsageHistory` (`window` +
//! `projectRoots` from unique local session `project_path` values,
//! cap 32). Default window is `{"trailingDays":30}` for Daily /
//! Projects; Monthly requests `{"months":12}`. Ok payload
//! `usageHistory` paints a first-cut history section. Native 4 KiB
//! stdin overflow / sidecar failure / unusable parse keep today's
//! local session Context + Thread goal cards and must not toast-block
//! Settings. No daemon shows a muted connect hint. Not a T3 chart,
//! not quality / rate-table / window selector. Hello stays v4.

const std = @import("std");
const native_sdk = @import("native_sdk");
const main = @import("main.zig");
const daemon_proxy = @import("daemon_proxy.zig");
const protocol = @import("protocol.zig");
const store = @import("store.zig");
const goal = @import("goal.zig");
const session_mod = @import("session.zig");

const Model = main.Model;
const Effects = main.Effects;
const writeFixed = main.writeFixed;
const max_project_path = session_mod.max_project_path;

pub const View = enum { daily, monthly, projects };

pub const max_providers = protocol.max_parsed_usage_providers;
pub const max_daily = protocol.max_parsed_usage_daily;
pub const max_months = protocol.max_parsed_usage_months;
pub const max_projects = protocol.max_parsed_usage_projects;
pub const max_roots = protocol.max_usage_project_roots;
pub const max_day_label = 32;
pub const max_line = 160;

pub const Row = struct {
    id: u32,
    line: []const u8,
};

pub const CachedProvider = struct {
    id_storage: [16]u8 = [_]u8{0} ** 16,
    id_len: usize = 0,
    total_tokens: u64 = 0,
    cost_usd: f64 = 0,

    pub fn id(self: *const CachedProvider) []const u8 {
        return self.id_storage[0..self.id_len];
    }
};

pub const CachedDay = struct {
    day_storage: [max_day_label]u8 = [_]u8{0} ** max_day_label,
    day_len: usize = 0,
    total_tokens: u64 = 0,
    cost_usd: f64 = 0,

    pub fn day(self: *const CachedDay) []const u8 {
        return self.day_storage[0..self.day_len];
    }
};

pub const CachedMonth = struct {
    first_day_storage: [max_day_label]u8 = [_]u8{0} ** max_day_label,
    first_day_len: usize = 0,
    total_tokens: u64 = 0,
    cost_usd: f64 = 0,
    sessions: u64 = 0,

    pub fn firstDay(self: *const CachedMonth) []const u8 {
        return self.first_day_storage[0..self.first_day_len];
    }
};

pub const CachedProject = struct {
    path_storage: [max_project_path]u8 = [_]u8{0} ** max_project_path,
    path_len: usize = 0,
    total_tokens: u64 = 0,
    cost_usd: f64 = 0,
    sessions: u64 = 0,

    pub fn path(self: *const CachedProject) []const u8 {
        return self.path_storage[0..self.path_len];
    }
};

pub const Cache = struct {
    present: bool = false,
    since_storage: [max_day_label]u8 = [_]u8{0} ** max_day_label,
    since_len: usize = 0,
    until_storage: [max_day_label]u8 = [_]u8{0} ** max_day_label,
    until_len: usize = 0,
    total_tokens: u64 = 0,
    cost_usd: f64 = 0,
    sessions: u64 = 0,
    providers: [max_providers]CachedProvider = [_]CachedProvider{.{}} ** max_providers,
    provider_count: usize = 0,
    daily: [max_daily]CachedDay = [_]CachedDay{.{}} ** max_daily,
    daily_count: usize = 0,
    months: [max_months]CachedMonth = [_]CachedMonth{.{}} ** max_months,
    month_count: usize = 0,
    projects: [max_projects]CachedProject = [_]CachedProject{.{}} ** max_projects,
    project_count: usize = 0,

    pub fn sinceDay(self: *const Cache) []const u8 {
        return self.since_storage[0..self.since_len];
    }

    pub fn untilDay(self: *const Cache) []const u8 {
        return self.until_storage[0..self.until_len];
    }
};

fn cancelInFlight(model: *Model, fx: *Effects) void {
    if (model.daemon_usage_history_key == 0) return;
    fx.cancel(model.daemon_usage_history_key);
    model.daemon_usage_history_key = 0;
}

/// Drop an in-flight LoadUsageHistory sidecar. Safe when none is live.
/// Does not clear a painted history cache or session context cards.
pub fn cancel(model: *Model, fx: *Effects) void {
    cancelInFlight(model, fx);
}

pub fn windowForView(view: View) protocol.UsageWindow {
    return switch (view) {
        .daily, .projects => .{ .trailing_days = 30 },
        .monthly => .{ .months = 12 },
    };
}

fn windowsEqual(a: protocol.UsageWindow, b: protocol.UsageWindow) bool {
    return std.meta.eql(a, b);
}

fn collectProjectRoots(model: *const Model, dest: *[max_roots][]const u8) usize {
    var n: usize = 0;
    for (model.session_store[0..model.session_count]) |*session| {
        const path = std.mem.trim(u8, session.projectPath(), " \t\r\n");
        if (path.len == 0) continue;
        var seen = false;
        for (dest[0..n]) |existing| {
            if (std.mem.eql(u8, existing, path)) {
                seen = true;
                break;
            }
        }
        if (seen) continue;
        dest[n] = path;
        n += 1;
        if (n == dest.len) break;
    }
    return n;
}

/// Prefer hello + `loadUsageHistory` when a daemon address is set.
/// Missing address / Native 4 KiB stdin overflow keep local session
/// cards and do not toast.
pub fn refresh(model: *Model, fx: *Effects) void {
    cancelInFlight(model, fx);
    _ = trySpawn(model, fx, windowForView(model.usage_view));
}

pub fn setView(model: *Model, fx: *Effects, view: View) void {
    const previous = windowForView(model.usage_view);
    model.usage_view = view;
    const next = windowForView(view);
    if (windowsEqual(previous, next)) return;
    refresh(model, fx);
}

fn trySpawn(model: *Model, fx: *Effects, window: protocol.UsageWindow) bool {
    const address = store.resolveDaemonMirrorAddress(model);
    if (address.len == 0) return false;

    var roots_buf: [max_roots][]const u8 = undefined;
    const root_count = collectProjectRoots(model, &roots_buf);

    var stdin_buf: [4096]u8 = undefined;
    const stdin = daemon_proxy.writeUsageHistoryStdin(&stdin_buf, .{
        .token = model.daemonToken(),
        .window = window,
        .project_roots = roots_buf[0..root_count],
    }) catch return false;

    const key = model.next_daemon_key;
    model.next_daemon_key += 1;
    model.daemon_usage_history_key = key;
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

fn adopt(cache: *Cache, parsed: protocol.ParsedUsageHistory) void {
    cache.present = true;
    writeFixed(&cache.since_storage, &cache.since_len, parsed.since_day);
    writeFixed(&cache.until_storage, &cache.until_len, parsed.until_day);
    cache.total_tokens = parsed.total_tokens;
    cache.cost_usd = parsed.cost_usd;
    cache.sessions = parsed.sessions;
    cache.provider_count = parsed.provider_count;
    var i: usize = 0;
    while (i < parsed.provider_count) : (i += 1) {
        writeFixed(&cache.providers[i].id_storage, &cache.providers[i].id_len, parsed.providers[i].provider);
        cache.providers[i].total_tokens = parsed.providers[i].total_tokens;
        cache.providers[i].cost_usd = parsed.providers[i].cost_usd;
    }
    cache.daily_count = parsed.daily_count;
    i = 0;
    while (i < parsed.daily_count) : (i += 1) {
        writeFixed(&cache.daily[i].day_storage, &cache.daily[i].day_len, parsed.daily[i].day);
        cache.daily[i].total_tokens = parsed.daily[i].total_tokens;
        cache.daily[i].cost_usd = parsed.daily[i].cost_usd;
    }
    cache.month_count = parsed.month_count;
    i = 0;
    while (i < parsed.month_count) : (i += 1) {
        writeFixed(&cache.months[i].first_day_storage, &cache.months[i].first_day_len, parsed.months[i].first_day);
        cache.months[i].total_tokens = parsed.months[i].total_tokens;
        cache.months[i].cost_usd = parsed.months[i].cost_usd;
        cache.months[i].sessions = parsed.months[i].sessions;
    }
    cache.project_count = parsed.project_count;
    i = 0;
    while (i < parsed.project_count) : (i += 1) {
        writeFixed(&cache.projects[i].path_storage, &cache.projects[i].path_len, parsed.projects[i].path);
        cache.projects[i].total_tokens = parsed.projects[i].total_tokens;
        cache.projects[i].cost_usd = parsed.projects[i].cost_usd;
        cache.projects[i].sessions = parsed.projects[i].sessions;
    }
}

pub fn applyLine(model: *Model, line: native_sdk.EffectLine) void {
    if (line.key != model.daemon_usage_history_key or model.daemon_usage_history_key == 0) return;
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const parsed = protocol.parseUsageHistory(arena_state.allocator(), line.line);
    if (!parsed.ok) return;
    adopt(&model.usage_history, parsed);
}

pub fn handleExit(model: *Model, exit: native_sdk.EffectExit) void {
    if (exit.key != model.daemon_usage_history_key or model.daemon_usage_history_key == 0) return;
    model.daemon_usage_history_key = 0;
}

pub fn providerLabel(id: []const u8) []const u8 {
    if (std.mem.eql(u8, id, "claude")) return "Claude Code";
    if (std.mem.eql(u8, id, "codex")) return "Codex";
    return id;
}

pub fn projectBasename(path: []const u8) []const u8 {
    const name = std.fs.path.basename(path);
    return if (name.len > 0) name else path;
}

fn formatCost(buf: []u8, cost: f64) ?[]const u8 {
    if (!(cost > 0)) return null;
    return std.fmt.bufPrint(buf, "${d:.2}", .{cost}) catch null;
}

fn appendTokensCost(buf: []u8, used: usize, tokens: u64, cost: f64) usize {
    var token_buf: [16]u8 = undefined;
    const token_s = goal.formatCompactTokens(&token_buf, tokens) orelse return used;
    var cost_buf: [24]u8 = undefined;
    const rest = if (formatCost(&cost_buf, cost)) |cost_s|
        std.fmt.bufPrint(buf[used..], " · {s} · {s}", .{ token_s, cost_s }) catch return used
    else
        std.fmt.bufPrint(buf[used..], " · {s}", .{token_s}) catch return used;
    return used + rest.len;
}

fn appendSessions(buf: []u8, used: usize, sessions: u64) usize {
    const piece = std.fmt.bufPrint(buf[used..], " · {d} sessions", .{sessions}) catch return used;
    return used + piece.len;
}

fn copyArena(arena: std.mem.Allocator, text: []const u8) []const u8 {
    if (text.len == 0) return "";
    const out = arena.alloc(u8, text.len) catch return "";
    @memcpy(out, text);
    return out;
}

pub fn rangeCaption(model: *const Model, arena: std.mem.Allocator) []const u8 {
    const cache = model.usage_history;
    const since_day = cache.sinceDay();
    const until_day = cache.untilDay();
    if (since_day.len == 0 and until_day.len == 0) return "";
    if (since_day.len == 0) return copyArena(arena, until_day);
    if (until_day.len == 0) return copyArena(arena, since_day);
    var buf: [80]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, "{s}–{s}", .{ since_day, until_day }) catch return "";
    return copyArena(arena, text);
}

pub fn headline(model: *const Model, arena: std.mem.Allocator) []const u8 {
    var buf: [64]u8 = undefined;
    var token_buf: [16]u8 = undefined;
    const token_s = goal.formatCompactTokens(&token_buf, model.usage_history.total_tokens) orelse "0";
    var cost_buf: [24]u8 = undefined;
    const text = if (formatCost(&cost_buf, model.usage_history.cost_usd)) |cost_s|
        std.fmt.bufPrint(&buf, "{s} · {s}", .{ token_s, cost_s }) catch token_s
    else
        token_s;
    return copyArena(arena, text);
}

pub fn sessionsLabel(model: *const Model, arena: std.mem.Allocator) []const u8 {
    var buf: [32]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, "{d} sessions", .{model.usage_history.sessions}) catch return "";
    return copyArena(arena, text);
}

fn joinLabelDetail(arena: std.mem.Allocator, label: []const u8, tokens: u64, cost: f64, sessions: ?u64) []const u8 {
    var buf: [max_line]u8 = undefined;
    const prefix_len = @min(label.len, buf.len);
    @memcpy(buf[0..prefix_len], label[0..prefix_len]);
    var pos = appendTokensCost(&buf, prefix_len, tokens, cost);
    if (sessions) |count| pos = appendSessions(&buf, pos, count);
    return copyArena(arena, buf[0..pos]);
}

pub fn providerRows(model: *const Model, arena: std.mem.Allocator) []const Row {
    if (model.settings_page != .usage or model.usage_view != .daily or !model.usage_history.present) return &.{};
    const count = model.usage_history.provider_count;
    if (count == 0) return &.{};
    const out = arena.alloc(Row, count) catch return &.{};
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const row = model.usage_history.providers[i];
        out[i] = .{
            .id = @intCast(i + 1),
            .line = joinLabelDetail(arena, providerLabel(row.id()), row.total_tokens, row.cost_usd, null),
        };
    }
    return out;
}

pub fn dailyRows(model: *const Model, arena: std.mem.Allocator) []const Row {
    if (model.settings_page != .usage or model.usage_view != .daily or !model.usage_history.present) return &.{};
    const count = model.usage_history.daily_count;
    if (count == 0) return &.{};
    const out = arena.alloc(Row, count) catch return &.{};
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const row = model.usage_history.daily[i];
        const label = if (row.day().len > 0) row.day() else "—";
        out[i] = .{
            .id = @intCast(i + 1),
            .line = joinLabelDetail(arena, label, row.total_tokens, row.cost_usd, null),
        };
    }
    return out;
}

pub fn monthRows(model: *const Model, arena: std.mem.Allocator) []const Row {
    if (model.settings_page != .usage or model.usage_view != .monthly or !model.usage_history.present) return &.{};
    const count = model.usage_history.month_count;
    if (count == 0) return &.{};
    const out = arena.alloc(Row, count) catch return &.{};
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const row = model.usage_history.months[i];
        const label = if (row.firstDay().len > 0) row.firstDay() else "—";
        out[i] = .{
            .id = @intCast(i + 1),
            .line = joinLabelDetail(arena, label, row.total_tokens, row.cost_usd, row.sessions),
        };
    }
    return out;
}

pub fn projectRows(model: *const Model, arena: std.mem.Allocator) []const Row {
    if (model.settings_page != .usage or model.usage_view != .projects or !model.usage_history.present) return &.{};
    const count = model.usage_history.project_count;
    if (count == 0) return &.{};
    const out = arena.alloc(Row, count) catch return &.{};
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const row = model.usage_history.projects[i];
        out[i] = .{
            .id = @intCast(i + 1),
            .line = joinLabelDetail(arena, projectBasename(row.path()), row.total_tokens, row.cost_usd, row.sessions),
        };
    }
    return out;
}

pub fn historyHint(model: *const Model) []const u8 {
    if (model.usage_history.present) return "";
    if (store.resolveDaemonMirrorAddress(model).len == 0) return "Connect a daemon for usage history";
    return "";
}

fn pendingSpawnKey(fx: *Effects, key: u64) ?@TypeOf(fx.pendingSpawnAt(0).?) {
    var i: usize = 0;
    while (fx.pendingSpawnAt(i)) |spawn| : (i += 1) {
        if (spawn.key == key) return spawn;
    }
    return null;
}

const usage_history_ok_line = "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000015\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"usageHistory\",\"history\":{\"window\":{\"trailingDays\":30},\"sinceDay\":\"2026-08-08\",\"untilDay\":\"2026-09-06\",\"totalTokens\":12345,\"costUsd\":1.25,\"sessions\":4,\"providers\":[{\"provider\":\"claude\",\"totalTokens\":10000,\"costUsd\":1.0}],\"daily\":[{\"day\":\"2026-09-06\",\"totalTokens\":500,\"costUsd\":0.1}],\"months\":[{\"firstDay\":\"2026-09-01\",\"totalTokens\":12345,\"costUsd\":1.25,\"sessions\":4}],\"projects\":[{\"path\":\"/tmp/faku\",\"totalTokens\":12345,\"costUsd\":1.25,\"sessions\":4}]}}}}";

const usage_history_ack_line = "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000015\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"ack\"}}}";

test "refresh with a daemon address spawns loadUsageHistory sidecar" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    const id = model.addSession("usage daemon", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath("/tmp/faku");
    const other = model.addSession("other", .claude);
    if (model.sessionById(other)) |session| session.setProjectPath("/tmp/faku");
    const third = model.addSession("third", .codex);
    if (model.sessionById(third)) |session| session.setProjectPath("/tmp/other");

    refresh(&model, &fx);
    const sidecar = pendingSpawnKey(&fx, model.daemon_usage_history_key) orelse return error.MissingDaemonLoadUsageHistory;
    try std.testing.expect(daemon_proxy.isSidecarArgv(sidecar.argv));
    try std.testing.expectEqualStrings("faku", sidecar.argv[0]);
    try std.testing.expectEqualStrings(daemon_proxy.SUBCOMMAND, sidecar.argv[1]);
    try std.testing.expectEqualStrings("127.0.0.1:8787", sidecar.argv[2]);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"hello\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"loadUsageHistory\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"window\":{\"trailingDays\":30}") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"projectRoots\":[\"/tmp/faku\",\"/tmp/other\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"workspace\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"prompt\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"loadTaskState\"") == null);
    try std.testing.expectEqual(sidecar.key, model.daemon_usage_history_key);
}

test "refresh without a daemon address keeps local session Usage" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setSidecarPath("faku");
    const id = model.addSession("usage local", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| {
        session.setProjectPath("/tmp/faku");
        session.setContextUsage(12_400, 200_000);
    }

    refresh(&model, &fx);
    try std.testing.expectEqual(@as(u64, 0), model.daemon_usage_history_key);
    try std.testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
    try std.testing.expect(!model.usage_history.present);
    try std.testing.expectEqual(@as(u64, 12_400), model.sessionById(id).?.context_used);
    try std.testing.expectEqualStrings("Connect a daemon for usage history", historyHint(&model));
}

test "LoadUsageHistory sidecar paints cache from usageHistory and miss keeps context cards" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    model.settings_page = .usage;
    const id = model.addSession("usage fill", .claude);
    model.selected = id;
    if (model.sessionById(id)) |session| {
        session.setProjectPath("/tmp/faku");
        session.setContextUsage(53_000, 200_000);
        session.setThreadGoalUsage(100_000, 12_000, 180);
    }

    refresh(&model, &fx);
    const sidecar = pendingSpawnKey(&fx, model.daemon_usage_history_key) orelse return error.MissingDaemonLoadUsageHistoryFill;
    applyLine(&model, .{ .key = sidecar.key, .line = "{\"type\":\"hello\"}" });
    try std.testing.expect(!model.usage_history.present);
    applyLine(&model, .{ .key = sidecar.key, .line = usage_history_ack_line });
    try std.testing.expect(!model.usage_history.present);
    applyLine(&model, .{ .key = sidecar.key, .line = usage_history_ok_line });
    try std.testing.expect(model.usage_history.present);
    try std.testing.expectEqual(@as(u64, 12345), model.usage_history.total_tokens);
    try std.testing.expectEqual(@as(u64, 4), model.usage_history.sessions);
    try std.testing.expectEqualStrings("claude", model.usage_history.providers[0].id());
    try std.testing.expectEqualStrings("2026-09-06", model.usage_history.daily[0].day());
    try std.testing.expectEqualStrings("/tmp/faku", model.usage_history.projects[0].path());
    try std.testing.expectEqual(@as(u64, 53_000), model.sessionById(id).?.context_used);
    try std.testing.expectEqualStrings("12k/100k · 3m", model.sessionById(id).?.threadGoalUsageLabel());
    handleExit(&model, .{ .key = sidecar.key, .reason = .exited, .code = 0 });
    try std.testing.expectEqual(@as(u64, 0), model.daemon_usage_history_key);
    try std.testing.expect(model.usage_history.present);
    try std.testing.expectEqual(@as(usize, 0), model.window_status_len);

    refresh(&model, &fx);
    const miss = pendingSpawnKey(&fx, model.daemon_usage_history_key) orelse return error.MissingDaemonLoadUsageHistoryMiss;
    applyLine(&model, .{ .key = miss.key, .line = usage_history_ack_line });
    handleExit(&model, .{ .key = miss.key, .reason = .exited, .code = 1 });
    try std.testing.expect(model.usage_history.present);
    try std.testing.expectEqual(@as(u64, 12345), model.usage_history.total_tokens);
    try std.testing.expectEqual(@as(u64, 53_000), model.sessionById(id).?.context_used);
    try std.testing.expectEqual(@as(usize, 0), model.window_status_len);

    var tiny: [32]u8 = undefined;
    try std.testing.expectError(error.NoSpaceLeft, daemon_proxy.writeUsageHistoryStdin(&tiny, .{
        .window = .{ .trailing_days = 30 },
        .project_roots = &.{"/tmp/faku"},
    }));
}

test "Monthly view requests months 12; Daily and Projects share trailingDays 30" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    try std.testing.expectEqual(View.daily, model.usage_view);
    refresh(&model, &fx);
    const daily = pendingSpawnKey(&fx, model.daemon_usage_history_key) orelse return error.MissingDailyUsageWindow;
    try std.testing.expect(std.mem.indexOf(u8, daily.stdin, "\"window\":{\"trailingDays\":30}") != null);

    setView(&model, &fx, .projects);
    try std.testing.expectEqual(View.projects, model.usage_view);
    try std.testing.expectEqual(daily.key, model.daemon_usage_history_key);

    setView(&model, &fx, .monthly);
    try std.testing.expectEqual(View.monthly, model.usage_view);
    const monthly = pendingSpawnKey(&fx, model.daemon_usage_history_key) orelse return error.MissingMonthlyUsageWindow;
    try std.testing.expect(monthly.key != daily.key);
    try std.testing.expect(std.mem.indexOf(u8, monthly.stdin, "\"window\":{\"months\":12}") != null);
    try std.testing.expect(std.mem.indexOf(u8, monthly.stdin, "\"trailingDays\"") == null);
}
