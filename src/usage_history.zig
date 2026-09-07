//! First-cut daemon `Command::LoadUsageHistory`.
//!
//! When Settings → Usage opens or Refresh is pressed and
//! `WAKU_DAEMON_ADDRESS` or persisted `last_daemon_address` is set,
//! Faku one-shots hello + `loadUsageHistory` (`window` +
//! `projectRoots` from unique local session `project_path` values,
//! cap 32). Daily / Projects share a runtime-only window selector
//! (Waku `WINDOW_CHOICES`: 7 / 30 / 90 trailing days, this month,
//! last month; default `{"trailingDays":30}`). Monthly always
//! requests `{"months":12}` and hides the selector. Ok payload
//! `usageHistory` paints a first-cut history section. A same-shape
//! snapshot (trailing vs months) stays painted while a replacement
//! scan is in flight; a months snapshot must not masquerade as
//! Daily / Projects and vice versa. Native 4 KiB stdin overflow /
//! sidecar failure / unusable parse keep today's local session
//! Context + Thread goal cards and must not toast-block Settings.
//! No daemon shows a muted connect hint. Daily first-cut paints
//! per-provider share bars (`costShare` / `tokenShare`, or computed
//! from totals) plus a runtime-only Cost | Tokens metric chip
//! (default Cost), a Daily-only Model | Days breakdown chip (Waku
//! `breakdown`; default Model), model share bars when Model is
//! selected (provider label + model name; Cost prefers wire
//! `costShare`, Tokens always computed from totals), and a first-cut
//! Native `<chart>` when Days is selected (oldest-first Claude / Codex
//! `kind="area"` series from a shared zero baseline for the active
//! Cost | Tokens metric, not stacked; NaN-pad when a day's
//! `byProvider` is missing; `y-max` pins to the max finite
//! single-provider-day sample when that peak is > 0). Nested
//! Claude/Codex Native `<progress>` rows still paint under each day
//! when a slot is non-zero for that metric; nested share is that
//! provider's cost or tokens divided by **that day's** total. Empty /
//! missing / short `byProvider` stays day-total-only. Empty `models`
//! paints no model rows. Provider share bars, Cost quality, notices, and the
//! scan footer stay on Daily regardless of the breakdown chip. A
//! first-cut five-tile Native metric strip (processed tokens /
//! cached input / uncached input / output / cache savings) paints
//! when history is painted on Daily, Monthly, and Projects (zeros
//! still paint).
//! Monthly
//! first-cut paints a Native `<chart>` of oldest-first Claude / Codex
//! `kind="area"` series from a shared zero baseline for the active
//! Cost | Tokens metric (not stacked; NaN-pad when a month's
//! `byProvider` is missing; `y-max` pins to the max finite
//! single-provider-month sample when that peak is > 0), the same Cost
//! | Tokens chip, and relative Native `<progress>` vs the max month in
//! the painted window (Cost → `costUsd`, Tokens → `totalTokens`);
//! zero-value months stay text-only. When a month has any non-zero
//! `byProvider` slot for that metric, two nested Native `<progress>`
//! rows (Claude Code / Codex) paint under it; nested share is that
//! provider's cost or tokens divided by **that month's** total. Empty /
//! missing / short `byProvider` stays month-total-only. Empty
//! `months[]` hides the chart (no fake samples). Projects
//! first-cut paints a Native `<chart>` of the **visible** filtered
//! set (Claude / Codex `kind="area"` series from a shared zero
//! baseline for the active Cost | Tokens metric, not stacked;
//! NaN-pad when a project's `byProvider` is missing; `y-max` pins
//! to the max finite single-provider-project sample among visible
//! rows when that peak is > 0; x-labels are path basename in painted
//! row order), the same chip, and relative Native `<progress>`
//! vs the max Cost / Tokens among **visible** filtered rows (Waku
//! `usage_project_filter` peak-of-visible; Cost → `costUsd`, Tokens
//! → `totalTokens`); zero-value rows stay text-only. Nested
//! Claude/Codex bars from `projects[].byProvider` follow the same
//! within-row share rule on **visible** filtered rows only. Empty
//! visible set / empty `projects[]` hides the chart (no fake
//! samples). A runtime-only
//! search filter (empty on boot; not `sessions.json`) case-insensitive
//! contains-matches project basename **or** full `path` (trim; empty
//! shows all, cap 16, no virtualization). Chip flip recomputes
//! Daily (including nested byProvider shares), Monthly (including
//! nested byProvider shares), and Projects
//! shares from the cached snapshot without re-fetching and respects
//! that filter (nested bars and chart samples only on visible rows). No-match empty
//! ("No matching projects") is distinct from no project usage.
//! Filter clears when leaving Settings Usage or switching away from
//! Projects. Daily, Monthly, and Projects paint a first-cut
//! five-tile Native metric strip from `totalTokens` / `totals` /
//! `quality.cacheSavingsUsd` (zeros still paint; Daily uses
//! active-day averages from `daily[]`; Monthly prefers active-month
//! averages from `months[]`; Projects uses history totals with
//! Daily's active-day wording when the snapshot shares that window)
//! and Daily paints a first-cut Cost quality panel from
//! `quality` (Provider reported / Model priced / Unpriced percents
//! plus Cache savings USD) and muted notices when `errors` are
//! non-empty or `pricing` is `unavailable`. A tiny scan-summary
//! footer uses `records` / `scannedFiles` / `skippedFiles` /
//! `scanDuration` when present. First-cut Daily Days, Monthly, and
//! Projects layered Native `<chart>` ship (Claude / Codex area
//! series from zero, not stacked; still not Waku GPUI / T3 canvas
//! polish). Projects nested byProvider bars stay Native `<progress>`. Daily Model rows
//! append a compact per-MTok hint when the Faku-side LiteLLM table
//! hits (unpriceable names stay unpriced). First-cut LiteLLM
//! rate-table fetch + 24h disk cache ships in `litellm_rates.zig`.
//! Still not Waku's GPUI / T3 canvas (smoothing, 12% fill opacity,
//! stroke width, paint-order by period total), not a local
//! transcript scan. Hello stays v4.

const std = @import("std");
const native_sdk = @import("native_sdk");
const main = @import("main.zig");
const daemon_proxy = @import("daemon_proxy.zig");
const protocol = @import("protocol.zig");
const store = @import("store.zig");
const goal = @import("goal.zig");
const session_mod = @import("session.zig");
const litellm_rates = @import("litellm_rates.zig");

const Model = main.Model;
const Effects = main.Effects;
const writeFixed = main.writeFixed;
const max_project_path = session_mod.max_project_path;

pub const View = enum { daily, monthly, projects };

/// Waku `WINDOW_CHOICES` for Daily / Projects. Monthly uses
/// `monthly_window` instead and does not offer these.
pub const WindowChoice = enum {
    trailing_7,
    trailing_30,
    trailing_90,
    this_month,
    last_month,

    pub fn toUsageWindow(self: WindowChoice) protocol.UsageWindow {
        return switch (self) {
            .trailing_7 => .{ .trailing_days = 7 },
            .trailing_30 => .{ .trailing_days = 30 },
            .trailing_90 => .{ .trailing_days = 90 },
            .this_month => .this_month,
            .last_month => .last_month,
        };
    }
};

pub const window_choices = [_]WindowChoice{
    .trailing_7,
    .trailing_30,
    .trailing_90,
    .this_month,
    .last_month,
};

pub const default_window_choice: WindowChoice = .trailing_30;
pub const monthly_window: protocol.UsageWindow = .{ .months = 12 };

/// Waku Daily / Monthly / Projects headline metric. Runtime-only; default Cost.
pub const ShareMetric = enum { cost, tokens };

pub const default_share_metric: ShareMetric = .cost;

/// Waku Daily `breakdown`: `model` | `day`. Runtime-only; default Model.
pub const Breakdown = enum { model, days };

pub const default_breakdown: Breakdown = .model;

pub const max_providers = protocol.max_parsed_usage_providers;
pub const max_models = protocol.max_parsed_usage_models;
pub const max_daily = protocol.max_parsed_usage_daily;
pub const max_months = protocol.max_parsed_usage_months;
pub const max_projects = protocol.max_parsed_usage_projects;
pub const max_errors = protocol.max_parsed_usage_errors;
pub const max_roots = protocol.max_usage_project_roots;
pub const max_metric_tiles: usize = 5;
pub const max_day_label = 32;
pub const max_model_name = 64;
pub const max_line = 160;
pub const rates_unavailable_notice = "Rates unavailable";

pub const Row = struct {
    id: u32,
    line: []const u8,
    /// Active Daily / Monthly / Projects share, 0..1.
    share: f32 = 0,
    /// `"80.0%"` for Daily provider / model / day / quality-share bars,
    /// Monthly bars, and Projects bars. Quality Cache savings and the
    /// Daily / Monthly / Projects metric-strip value reuse this for a
    /// USD / compact-token label.
    percent: []const u8 = "",
    /// Metric-strip muted detail (per-day / per-month average, cache
    /// share, writes, reasoning, raw-cost multiple). Empty on other
    /// rows.
    detail: []const u8 = "",
    /// True when Daily, Monthly, Projects, or Cost quality should
    /// paint a share bar (share > 0).
    has_share: bool = false,
    /// Daily Days / Monthly / Projects: nested Claude/Codex bars from
    /// `byProvider`. False when empty / missing / the row's
    /// active-metric total is 0.
    has_by_provider: bool = false,
    claude_line: []const u8 = "",
    claude_share: f32 = 0,
    claude_percent: []const u8 = "",
    claude_has_share: bool = false,
    codex_line: []const u8 = "",
    codex_share: f32 = 0,
    codex_percent: []const u8 = "",
    codex_has_share: bool = false,
};

pub const CachedNotice = struct {
    text_storage: [max_line]u8 = [_]u8{0} ** max_line,
    text_len: usize = 0,

    pub fn text(self: *const CachedNotice) []const u8 {
        return self.text_storage[0..self.text_len];
    }
};

pub const CachedProvider = struct {
    id_storage: [16]u8 = [_]u8{0} ** 16,
    id_len: usize = 0,
    total_tokens: u64 = 0,
    cost_usd: f64 = 0,
    /// 0..1. Wire `costShare` when present and > 0, else computed.
    cost_share: f64 = 0,
    /// 0..1. Wire `tokenShare` when present and > 0, else computed.
    token_share: f64 = 0,

    pub fn id(self: *const CachedProvider) []const u8 {
        return self.id_storage[0..self.id_len];
    }

    pub fn shareFor(self: *const CachedProvider, metric: ShareMetric) f64 {
        return switch (metric) {
            .cost => self.cost_share,
            .tokens => self.token_share,
        };
    }
};

pub const CachedModel = struct {
    provider_storage: [16]u8 = [_]u8{0} ** 16,
    provider_len: usize = 0,
    name_storage: [max_model_name]u8 = [_]u8{0} ** max_model_name,
    name_len: usize = 0,
    total_tokens: u64 = 0,
    cost_usd: f64 = 0,
    /// 0..1. Wire `costShare` when present and > 0, else computed.
    cost_share: f64 = 0,

    pub fn provider(self: *const CachedModel) []const u8 {
        return self.provider_storage[0..self.provider_len];
    }

    pub fn name(self: *const CachedModel) []const u8 {
        return self.name_storage[0..self.name_len];
    }

    /// Cost prefers resolved `cost_share`. Tokens always compute from
    /// `total_tokens` / history totals (ModelSlice has no `tokenShare`).
    pub fn shareFor(self: *const CachedModel, metric: ShareMetric, history_total_tokens: u64) f64 {
        return switch (metric) {
            .cost => self.cost_share,
            .tokens => resolveShare(0, tokensAsFloat(self.total_tokens), tokensAsFloat(history_total_tokens)),
        };
    }
};

pub const CachedDay = struct {
    day_storage: [max_day_label]u8 = [_]u8{0} ** max_day_label,
    day_len: usize = 0,
    total_tokens: u64 = 0,
    cost_usd: f64 = 0,
    by_provider: [protocol.max_parsed_usage_day_providers]protocol.ParsedProviderDay = [_]protocol.ParsedProviderDay{.{}} ** protocol.max_parsed_usage_day_providers,

    pub fn day(self: *const CachedDay) []const u8 {
        return self.day_storage[0..self.day_len];
    }

    /// Cost → `cost_usd`; Tokens → `total_tokens`. Used for Daily
    /// day-list shares. The Days Native chart paints provider series,
    /// not this combined total.
    pub fn valueFor(self: *const CachedDay, metric: ShareMetric) f64 {
        return switch (metric) {
            .cost => self.cost_usd,
            .tokens => tokensAsFloat(self.total_tokens),
        };
    }
};

pub const CachedMonth = struct {
    first_day_storage: [max_day_label]u8 = [_]u8{0} ** max_day_label,
    first_day_len: usize = 0,
    total_tokens: u64 = 0,
    cost_usd: f64 = 0,
    sessions: u64 = 0,
    by_provider: [protocol.max_parsed_usage_day_providers]protocol.ParsedProviderDay = [_]protocol.ParsedProviderDay{.{}} ** protocol.max_parsed_usage_day_providers,

    pub fn firstDay(self: *const CachedMonth) []const u8 {
        return self.first_day_storage[0..self.first_day_len];
    }

    /// Cost → `cost_usd`; Tokens → `total_tokens`. Used for Monthly
    /// month-list shares. The Monthly Native chart paints provider
    /// series, not this combined total.
    pub fn valueFor(self: *const CachedMonth, metric: ShareMetric) f64 {
        return switch (metric) {
            .cost => self.cost_usd,
            .tokens => tokensAsFloat(self.total_tokens),
        };
    }
};

pub const CachedProject = struct {
    path_storage: [max_project_path]u8 = [_]u8{0} ** max_project_path,
    path_len: usize = 0,
    total_tokens: u64 = 0,
    cost_usd: f64 = 0,
    sessions: u64 = 0,
    by_provider: [protocol.max_parsed_usage_day_providers]protocol.ParsedProviderDay = [_]protocol.ParsedProviderDay{.{}} ** protocol.max_parsed_usage_day_providers,

    pub fn path(self: *const CachedProject) []const u8 {
        return self.path_storage[0..self.path_len];
    }

    /// Cost → `cost_usd`; Tokens → `total_tokens`. Used for the
    /// first-cut Projects bar (share vs max among visible filtered
    /// rows). The Projects Native chart paints provider series, not
    /// this combined total.
    pub fn valueFor(self: *const CachedProject, metric: ShareMetric) f64 {
        return switch (metric) {
            .cost => self.cost_usd,
            .tokens => tokensAsFloat(self.total_tokens),
        };
    }
};

pub const Cache = struct {
    present: bool = false,
    /// Window the painted snapshot was requested with. Used to keep a
    /// same-shape history on screen while a replacement scan is in
    /// flight (trailing vs months).
    window: protocol.UsageWindow = .{ .trailing_days = 30 },
    /// Window of the in-flight sidecar, if any.
    pending_window: protocol.UsageWindow = .{ .trailing_days = 30 },
    since_storage: [max_day_label]u8 = [_]u8{0} ** max_day_label,
    since_len: usize = 0,
    until_storage: [max_day_label]u8 = [_]u8{0} ** max_day_label,
    until_len: usize = 0,
    total_tokens: u64 = 0,
    cost_usd: f64 = 0,
    sessions: u64 = 0,
    providers: [max_providers]CachedProvider = [_]CachedProvider{.{}} ** max_providers,
    provider_count: usize = 0,
    models: [max_models]CachedModel = [_]CachedModel{.{}} ** max_models,
    model_count: usize = 0,
    daily: [max_daily]CachedDay = [_]CachedDay{.{}} ** max_daily,
    daily_count: usize = 0,
    months: [max_months]CachedMonth = [_]CachedMonth{.{}} ** max_months,
    month_count: usize = 0,
    projects: [max_projects]CachedProject = [_]CachedProject{.{}} ** max_projects,
    project_count: usize = 0,
    totals: protocol.ParsedTokenTotals = .{},
    quality: protocol.ParsedCostQuality = .{},
    pricing: protocol.PricingStatus = .unknown,
    records: u64 = 0,
    scanned_files: u64 = 0,
    skipped_files: u64 = 0,
    scan_duration_secs: f64 = 0,
    errors: [max_errors]CachedNotice = [_]CachedNotice{.{}} ** max_errors,
    error_count: usize = 0,

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

pub fn effectiveWindow(view: View, choice: WindowChoice) protocol.UsageWindow {
    return switch (view) {
        .daily, .projects => choice.toUsageWindow(),
        .monthly => monthly_window,
    };
}

pub fn windowForView(model: *const Model) protocol.UsageWindow {
    return effectiveWindow(model.usage_view, model.usage_window);
}

fn windowsEqual(a: protocol.UsageWindow, b: protocol.UsageWindow) bool {
    return std.meta.eql(a, b);
}

fn isMonthsWindow(window: protocol.UsageWindow) bool {
    return switch (window) {
        .months => true,
        else => false,
    };
}

fn sameShape(a: protocol.UsageWindow, b: protocol.UsageWindow) bool {
    return isMonthsWindow(a) == isMonthsWindow(b);
}

/// True when the painted snapshot can stand in for the active view:
/// trailing-shaped history for Daily / Projects, months-shaped for
/// Monthly. Same-shape previous windows stay visible while a new
/// scan is in flight.
pub fn cacheShapeMatches(model: *const Model) bool {
    if (!model.usage_history.present) return false;
    return sameShape(model.usage_history.window, windowForView(model));
}

fn historyPainted(model: *const Model) bool {
    return model.settings_page == .usage and cacheShapeMatches(model);
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
/// cards and do not toast. Refresh is a forced re-request.
pub fn refresh(model: *Model, fx: *Effects) void {
    ensure(model, fx, true);
}

pub fn setView(model: *Model, fx: *Effects, view: View) void {
    if (model.usage_view == .projects and view != .projects) {
        clearProjectFilter(model);
    }
    const previous = windowForView(model);
    model.usage_view = view;
    const next = windowForView(model);
    if (windowsEqual(previous, next)) return;
    ensure(model, fx, false);
}

pub fn setWindow(model: *Model, fx: *Effects, choice: WindowChoice) void {
    if (model.usage_window == choice) return;
    model.usage_window = choice;
    if (model.usage_view == .monthly) return;
    ensure(model, fx, false);
}

/// Runtime-only Daily / Monthly / Projects Cost | Tokens chip. Does
/// not re-fetch history. Provider, model, daily, monthly, and project
/// bars (including nested byProvider shares) recompute from the cached
/// snapshot (Projects respects the filter).
pub fn setShareMetric(model: *Model, metric: ShareMetric) void {
    model.usage_share_metric = metric;
}

/// Runtime-only Daily Model | Days breakdown. Does not re-fetch.
pub fn setBreakdown(model: *Model, breakdown: Breakdown) void {
    model.usage_breakdown = breakdown;
}

/// Runtime-only Waku `usage_project_filter`. Not persisted.
pub fn projectFilter(model: *const Model) []const u8 {
    return std.mem.trim(u8, model.usage_project_filter_buffer.text(), " \t\r\n");
}

pub fn applyProjectFilter(model: *Model, edit: native_sdk.canvas.TextInputEvent) void {
    model.usage_project_filter_buffer.apply(edit);
}

pub fn clearProjectFilter(model: *Model) void {
    model.usage_project_filter_buffer.clear();
}

/// Drop the runtime Projects filter when leaving Settings Usage.
/// Does not cancel an in-flight sidecar or clear the history cache.
pub fn leaveUsage(model: *Model) void {
    clearProjectFilter(model);
}

/// Case-insensitive contains on full `path` or basename. Empty /
/// whitespace-only `query` matches every project (caller may trim).
pub fn projectFilterMatches(path: []const u8, query: []const u8) bool {
    const needle = std.mem.trim(u8, query, " \t\r\n");
    if (needle.len == 0) return true;
    if (main.asciiContainsIgnoreCase(path, needle)) return true;
    return main.asciiContainsIgnoreCase(projectBasename(path), needle);
}

fn cachedProjectMatches(project: CachedProject, query: []const u8) bool {
    return projectFilterMatches(project.path(), query);
}

fn ensure(model: *Model, fx: *Effects, force: bool) void {
    const window = windowForView(model);
    if (!force) {
        if (model.usage_history.present and windowsEqual(model.usage_history.window, window)) {
            if (model.daemon_usage_history_key != 0 and !windowsEqual(model.usage_history.pending_window, window)) {
                cancelInFlight(model, fx);
            }
            return;
        }
        if (model.daemon_usage_history_key != 0 and windowsEqual(model.usage_history.pending_window, window)) return;
    }
    cancelInFlight(model, fx);
    _ = trySpawn(model, fx, window);
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
    model.usage_history.pending_window = window;
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
    cache.window = cache.pending_window;
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
        cache.providers[i].cost_share = resolveShare(
            parsed.providers[i].cost_share,
            parsed.providers[i].cost_usd,
            parsed.cost_usd,
        );
        cache.providers[i].token_share = resolveShare(
            parsed.providers[i].token_share,
            tokensAsFloat(parsed.providers[i].total_tokens),
            tokensAsFloat(parsed.total_tokens),
        );
    }
    cache.model_count = parsed.model_count;
    i = 0;
    while (i < parsed.model_count) : (i += 1) {
        writeFixed(&cache.models[i].provider_storage, &cache.models[i].provider_len, parsed.models[i].provider);
        writeFixed(&cache.models[i].name_storage, &cache.models[i].name_len, parsed.models[i].model);
        cache.models[i].total_tokens = parsed.models[i].total_tokens;
        cache.models[i].cost_usd = parsed.models[i].cost_usd;
        cache.models[i].cost_share = resolveShare(
            parsed.models[i].cost_share,
            parsed.models[i].cost_usd,
            parsed.cost_usd,
        );
    }
    cache.daily_count = parsed.daily_count;
    i = 0;
    while (i < parsed.daily_count) : (i += 1) {
        writeFixed(&cache.daily[i].day_storage, &cache.daily[i].day_len, parsed.daily[i].day);
        cache.daily[i].total_tokens = parsed.daily[i].total_tokens;
        cache.daily[i].cost_usd = parsed.daily[i].cost_usd;
        cache.daily[i].by_provider = parsed.daily[i].by_provider;
    }
    cache.month_count = parsed.month_count;
    i = 0;
    while (i < parsed.month_count) : (i += 1) {
        writeFixed(&cache.months[i].first_day_storage, &cache.months[i].first_day_len, parsed.months[i].first_day);
        cache.months[i].total_tokens = parsed.months[i].total_tokens;
        cache.months[i].cost_usd = parsed.months[i].cost_usd;
        cache.months[i].sessions = parsed.months[i].sessions;
        cache.months[i].by_provider = parsed.months[i].by_provider;
    }
    cache.project_count = parsed.project_count;
    i = 0;
    while (i < parsed.project_count) : (i += 1) {
        writeFixed(&cache.projects[i].path_storage, &cache.projects[i].path_len, parsed.projects[i].path);
        cache.projects[i].total_tokens = parsed.projects[i].total_tokens;
        cache.projects[i].cost_usd = parsed.projects[i].cost_usd;
        cache.projects[i].sessions = parsed.projects[i].sessions;
        cache.projects[i].by_provider = parsed.projects[i].by_provider;
    }
    cache.totals = parsed.totals;
    cache.quality = parsed.quality;
    cache.pricing = parsed.pricing;
    cache.records = parsed.records;
    cache.scanned_files = parsed.scanned_files;
    cache.skipped_files = parsed.skipped_files;
    cache.scan_duration_secs = parsed.scan_duration_secs;
    cache.error_count = parsed.error_count;
    i = 0;
    while (i < parsed.error_count) : (i += 1) {
        writeFixed(&cache.errors[i].text_storage, &cache.errors[i].text_len, parsed.errors[i]);
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

fn tokensAsFloat(tokens: u64) f64 {
    return @floatFromInt(tokens);
}

/// Clamp a relative share to 0..1. Non-finite / negative → 0.
fn clampShare(value: f64) f64 {
    if (!std.math.isFinite(value) or !(value > 0)) return 0;
    if (value >= 1) return 1;
    return value;
}

/// Prefer a positive wire share; otherwise compute part/total when
/// totals exist (older daemons omit `costShare` / `tokenShare`).
fn resolveShare(wire: f64, part: f64, total: f64) f64 {
    const from_wire = clampShare(wire);
    if (from_wire > 0) return from_wire;
    if (!(total > 0)) return 0;
    return clampShare(part / total);
}

/// Max Cost / Tokens value among cached Daily rows. 0 when every
/// day is empty so shares stay text-only.
fn maxDayValue(days: []const CachedDay, metric: ShareMetric) f64 {
    var max: f64 = 0;
    for (days) |day| {
        const value = day.valueFor(metric);
        if (value > max) max = value;
    }
    return max;
}

/// Share vs the window's max day. 0 when the day (or the window) is
/// empty so Native skips the progress bar.
fn dayShare(day: CachedDay, max: f64, metric: ShareMetric) f64 {
    if (!(max > 0)) return 0;
    return clampShare(day.valueFor(metric) / max);
}

const day_provider_ids = [_][]const u8{ "claude", "codex" };

fn providerDayValue(slot: protocol.ParsedProviderDay, metric: ShareMetric) f64 {
    return switch (metric) {
        .cost => slot.cost_usd,
        .tokens => tokensAsFloat(slot.total_tokens),
    };
}

/// Nested Claude/Codex bars only when the row's active-metric total
/// is non-zero and at least one `byProvider` slot is non-zero for
/// that metric. Empty / missing / all-zero stays total-only.
fn rowHasByProvider(slots: [protocol.max_parsed_usage_day_providers]protocol.ParsedProviderDay, row_total: f64, metric: ShareMetric) bool {
    if (!(row_total > 0)) return false;
    for (slots) |slot| {
        if (providerDayValue(slot, metric) > 0) return true;
    }
    return false;
}

/// Share within the row (provider / that row's total), not vs the
/// window max. 0 when the row total is empty.
fn nestedProviderShare(slot: protocol.ParsedProviderDay, row_total: f64, metric: ShareMetric) f64 {
    if (!(row_total > 0)) return 0;
    return clampShare(providerDayValue(slot, metric) / row_total);
}

fn fillNestedByProvider(
    out: *Row,
    arena: std.mem.Allocator,
    slots: [protocol.max_parsed_usage_day_providers]protocol.ParsedProviderDay,
    row_total: f64,
    metric: ShareMetric,
) void {
    if (!rowHasByProvider(slots, row_total, metric)) return;
    const claude = slots[protocol.usage_day_provider_claude];
    const claude_share = nestedProviderShare(claude, row_total, metric);
    var claude_percent_buf: [16]u8 = undefined;
    out.has_by_provider = true;
    out.claude_line = joinLabelDetail(arena, providerLabel(day_provider_ids[protocol.usage_day_provider_claude]), claude.total_tokens, claude.cost_usd, null);
    out.claude_share = @floatCast(claude_share);
    out.claude_percent = if (formatPercent(&claude_percent_buf, claude_share)) |text|
        copyArena(arena, text)
    else
        "";
    out.claude_has_share = claude_share > 0;
    const codex = slots[protocol.usage_day_provider_codex];
    const codex_share = nestedProviderShare(codex, row_total, metric);
    var codex_percent_buf: [16]u8 = undefined;
    out.codex_line = joinLabelDetail(arena, providerLabel(day_provider_ids[protocol.usage_day_provider_codex]), codex.total_tokens, codex.cost_usd, null);
    out.codex_share = @floatCast(codex_share);
    out.codex_percent = if (formatPercent(&codex_percent_buf, codex_share)) |text|
        copyArena(arena, text)
    else
        "";
    out.codex_has_share = codex_share > 0;
}

/// Max Cost / Tokens value among cached Monthly rows. 0 when every
/// month is empty so shares stay text-only.
fn maxMonthValue(months: []const CachedMonth, metric: ShareMetric) f64 {
    var max: f64 = 0;
    for (months) |month| {
        const value = month.valueFor(metric);
        if (value > max) max = value;
    }
    return max;
}

/// Share vs the window's max month. 0 when the month (or the window)
/// is empty so Native skips the progress bar.
fn monthShare(month: CachedMonth, max: f64, metric: ShareMetric) f64 {
    if (!(max > 0)) return 0;
    return clampShare(month.valueFor(metric) / max);
}

/// Max Cost / Tokens among the given project slice (visible filtered
/// rows). 0 when every row is empty so shares stay text-only.
fn maxProjectValue(projects: []const CachedProject, metric: ShareMetric) f64 {
    var max: f64 = 0;
    for (projects) |project| {
        const value = project.valueFor(metric);
        if (value > max) max = value;
    }
    return max;
}

/// Share vs the peak of visible filtered rows. 0 when the project
/// (or that visible set) is empty so Native skips the progress bar.
fn projectShare(project: CachedProject, max: f64, metric: ShareMetric) f64 {
    if (!(max > 0)) return 0;
    return clampShare(project.valueFor(metric) / max);
}

fn formatPercent(buf: []u8, share: f64) ?[]const u8 {
    const clamped = clampShare(share);
    if (!(clamped > 0)) return null;
    return std.fmt.bufPrint(buf, "{d:.1}%", .{clamped * 100.0}) catch null;
}

/// Quality percents always paint, including 0.0%.
fn formatPercentLabel(buf: []u8, share: f64) []const u8 {
    const clamped = clampShare(share);
    return std.fmt.bufPrint(buf, "{d:.1}%", .{clamped * 100.0}) catch "0.0%";
}

fn formatUsd(buf: []u8, cost: f64) []const u8 {
    if (!std.math.isFinite(cost)) return "$0.00";
    if (cost >= 0) return std.fmt.bufPrint(buf, "${d:.2}", .{cost}) catch "$0.00";
    return std.fmt.bufPrint(buf, "-${d:.2}", .{-cost}) catch "$0.00";
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

fn appendRateHint(arena: std.mem.Allocator, line: []const u8, hint: []const u8) []const u8 {
    var buf: [max_line]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, "{s} · {s}", .{ line, hint }) catch return line;
    return copyArena(arena, text);
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
    if (!historyPainted(model) or model.usage_view != .daily) return &.{};
    const count = model.usage_history.provider_count;
    if (count == 0) return &.{};
    const out = arena.alloc(Row, count) catch return &.{};
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const row = model.usage_history.providers[i];
        const share = clampShare(row.shareFor(model.usage_share_metric));
        var percent_buf: [16]u8 = undefined;
        const percent = if (formatPercent(&percent_buf, share)) |text|
            copyArena(arena, text)
        else
            "";
        out[i] = .{
            .id = @intCast(i + 1),
            .line = joinLabelDetail(arena, providerLabel(row.id()), row.total_tokens, row.cost_usd, null),
            .share = @floatCast(share),
            .percent = percent,
            .has_share = share > 0,
        };
    }
    return out;
}

fn modelRowLabel(buf: []u8, provider_id: []const u8, model_name: []const u8) []const u8 {
    const provider = providerLabel(provider_id);
    const name = if (model_name.len > 0) model_name else "—";
    return std.fmt.bufPrint(buf, "{s} · {s}", .{ provider, name }) catch provider;
}

pub fn modelRows(model: *const Model, arena: std.mem.Allocator) []const Row {
    if (!historyPainted(model) or model.usage_view != .daily or model.usage_breakdown != .model) return &.{};
    const count = model.usage_history.model_count;
    if (count == 0) return &.{};
    const out = arena.alloc(Row, count) catch return &.{};
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const row = model.usage_history.models[i];
        const share = clampShare(row.shareFor(model.usage_share_metric, model.usage_history.total_tokens));
        var percent_buf: [16]u8 = undefined;
        const percent = if (formatPercent(&percent_buf, share)) |text|
            copyArena(arena, text)
        else
            "";
        var label_buf: [96]u8 = undefined;
        const label = modelRowLabel(&label_buf, row.provider(), row.name());
        var line = joinLabelDetail(arena, label, row.total_tokens, row.cost_usd, null);
        if (litellm_rates.lookup(&model.litellm_rates, row.name())) |rate| {
            var hint_buf: [32]u8 = undefined;
            if (litellm_rates.formatRateHint(&hint_buf, rate)) |hint| {
                line = appendRateHint(arena, line, hint);
            }
        }
        out[i] = .{
            .id = @intCast(i + 1),
            .line = line,
            .share = @floatCast(share),
            .percent = percent,
            .has_share = share > 0,
        };
    }
    return out;
}

pub fn dailyRows(model: *const Model, arena: std.mem.Allocator) []const Row {
    if (!historyPainted(model) or model.usage_view != .daily or model.usage_breakdown != .days) return &.{};
    const count = model.usage_history.daily_count;
    if (count == 0) return &.{};
    const days = model.usage_history.daily[0..count];
    const metric = model.usage_share_metric;
    const max = maxDayValue(days, metric);
    const out = arena.alloc(Row, count) catch return &.{};
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const row = days[i];
        const label = if (row.day().len > 0) row.day() else "—";
        const share = dayShare(row, max, metric);
        var percent_buf: [16]u8 = undefined;
        const percent = if (formatPercent(&percent_buf, share)) |text|
            copyArena(arena, text)
        else
            "";
        out[i] = .{
            .id = @intCast(i + 1),
            .line = joinLabelDetail(arena, label, row.total_tokens, row.cost_usd, null),
            .share = @floatCast(share),
            .percent = percent,
            .has_share = share > 0,
        };
        fillNestedByProvider(&out[i], arena, row.by_provider, row.valueFor(metric), metric);
    }
    return out;
}

/// True when Daily + Days is painted with at least one cached day.
/// Empty `daily[]` hides the Native chart (no fake samples).
pub fn hasDailyChart(model: *const Model) bool {
    return dailyChartDays(model).len > 0;
}

fn dailyChartDays(model: *const Model) []const CachedDay {
    if (!historyPainted(model) or model.usage_view != .daily or model.usage_breakdown != .days) return &.{};
    const count = model.usage_history.daily_count;
    if (count == 0) return &.{};
    return model.usage_history.daily[0..count];
}

/// Oldest-first indices so Native chart samples match `x-labels`
/// (label i names sample i). Day strings are ISO `YYYY-MM-DD`.
fn oldestFirstDayOrder(days: []const CachedDay, dest: []usize) usize {
    const n = @min(days.len, dest.len);
    var i: usize = 0;
    while (i < n) : (i += 1) dest[i] = i;
    i = 1;
    while (i < n) : (i += 1) {
        const idx = dest[i];
        const key = days[idx].day();
        var j: usize = i;
        while (j > 0 and std.mem.order(u8, key, days[dest[j - 1]].day()) == .lt) {
            dest[j] = dest[j - 1];
            j -= 1;
        }
        dest[j] = idx;
    }
    return n;
}

fn chartSample(value: f64) f32 {
    if (!std.math.isFinite(value) or value < 0) return 0;
    return @floatCast(value);
}

/// Any Claude/Codex slot with cost or tokens. Distinct from the
/// nested-bar gate: missing / empty `byProvider` NaN-pads the
/// provider series even when the period total is non-zero.
fn hasByProviderSamples(slots: [protocol.max_parsed_usage_day_providers]protocol.ParsedProviderDay) bool {
    for (slots) |slot| {
        if (slot.cost_usd > 0 or slot.total_tokens > 0) return true;
    }
    return false;
}

/// Active Cost | Tokens day totals, oldest-first. Empty when the
/// chart is hidden. Not painted (the Days chart is layered Claude /
/// Codex area series); kept so tests can contrast combined totals
/// against the single-provider y-max peak.
pub fn dailyChartValues(model: *const Model, arena: std.mem.Allocator) []const f32 {
    const days = dailyChartDays(model);
    if (days.len == 0) return &.{};
    var order: [max_daily]usize = undefined;
    const n = oldestFirstDayOrder(days, &order);
    const out = arena.alloc(f32, n) catch return &.{};
    const metric = model.usage_share_metric;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        out[i] = chartSample(days[order[i]].valueFor(metric));
    }
    return out;
}

fn dailyChartProviderValues(model: *const Model, arena: std.mem.Allocator, slot: usize) []const f32 {
    const days = dailyChartDays(model);
    if (days.len == 0) return &.{};
    var order: [max_daily]usize = undefined;
    const n = oldestFirstDayOrder(days, &order);
    const out = arena.alloc(f32, n) catch return &.{};
    const metric = model.usage_share_metric;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const day = days[order[i]];
        if (!hasByProviderSamples(day.by_provider)) {
            out[i] = std.math.nan(f32);
            continue;
        }
        out[i] = chartSample(providerDayValue(day.by_provider[slot], metric));
    }
    return out;
}

/// Claude `byProvider` totals for the active metric. NaN when that
/// day's `byProvider` is missing / empty.
pub fn dailyChartClaudeValues(model: *const Model, arena: std.mem.Allocator) []const f32 {
    return dailyChartProviderValues(model, arena, protocol.usage_day_provider_claude);
}

/// Codex `byProvider` totals for the active metric. NaN when that
/// day's `byProvider` is missing / empty.
pub fn dailyChartCodexValues(model: *const Model, arena: std.mem.Allocator) []const f32 {
    return dailyChartProviderValues(model, arena, protocol.usage_day_provider_codex);
}

/// Max finite Claude/Codex provider-day sample for the active Cost |
/// Tokens metric across the painted window (single-provider peak, not
/// the combined day total). Null when the chart is hidden, there are
/// no finite samples, or that peak is 0 — omit Native `y-max` and
/// leave the auto-domain rather than inventing height.
pub fn dailyChartYMax(model: *const Model) ?f32 {
    const days = dailyChartDays(model);
    if (days.len == 0) return null;
    const metric = model.usage_share_metric;
    var peak: f32 = 0;
    var any_finite = false;
    for (days) |day| {
        if (!hasByProviderSamples(day.by_provider)) continue;
        for (day.by_provider) |slot| {
            const sample = chartSample(providerDayValue(slot, metric));
            if (!std.math.isFinite(sample)) continue;
            any_finite = true;
            if (sample > peak) peak = sample;
        }
    }
    if (!any_finite or !(peak > 0)) return null;
    return peak;
}

pub fn hasDailyChartYMax(model: *const Model) bool {
    return dailyChartYMax(model) != null;
}

/// Scalar for Native `y-max="{usage_daily_chart_y_max}"`. 0 when the
/// pin is omitted (the markup `if` hides this binding).
pub fn dailyChartYMaxValue(model: *const Model) f32 {
    return dailyChartYMax(model) orelse 0;
}

/// Category labels oldest-first, one per chart sample.
pub fn dailyChartLabels(model: *const Model, arena: std.mem.Allocator) []const []const u8 {
    const days = dailyChartDays(model);
    if (days.len == 0) return &.{};
    var order: [max_daily]usize = undefined;
    const n = oldestFirstDayOrder(days, &order);
    const out = arena.alloc([]const u8, n) catch return &.{};
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const label = days[order[i]].day();
        out[i] = if (label.len > 0) copyArena(arena, label) else "";
    }
    return out;
}

/// True when Monthly is painted with at least one cached month.
/// Empty `months[]` hides the Native chart (no fake samples).
pub fn hasMonthlyChart(model: *const Model) bool {
    return monthlyChartMonths(model).len > 0;
}

fn monthlyChartMonths(model: *const Model) []const CachedMonth {
    if (!historyPainted(model) or model.usage_view != .monthly) return &.{};
    const count = model.usage_history.month_count;
    if (count == 0) return &.{};
    return model.usage_history.months[0..count];
}

/// Oldest-first indices so Native chart samples match `x-labels`
/// (label i names sample i). Month strings are opaque `firstDay`
/// labels (same honesty as Daily day strings).
fn oldestFirstMonthOrder(months: []const CachedMonth, dest: []usize) usize {
    const n = @min(months.len, dest.len);
    var i: usize = 0;
    while (i < n) : (i += 1) dest[i] = i;
    i = 1;
    while (i < n) : (i += 1) {
        const idx = dest[i];
        const key = months[idx].firstDay();
        var j: usize = i;
        while (j > 0 and std.mem.order(u8, key, months[dest[j - 1]].firstDay()) == .lt) {
            dest[j] = dest[j - 1];
            j -= 1;
        }
        dest[j] = idx;
    }
    return n;
}

/// Active Cost | Tokens month totals, oldest-first. Empty when the
/// chart is hidden. Not painted (the Monthly chart is layered Claude /
/// Codex area series); kept so tests can contrast combined totals
/// against the single-provider y-max peak.
pub fn monthlyChartValues(model: *const Model, arena: std.mem.Allocator) []const f32 {
    const months = monthlyChartMonths(model);
    if (months.len == 0) return &.{};
    var order: [max_months]usize = undefined;
    const n = oldestFirstMonthOrder(months, &order);
    const out = arena.alloc(f32, n) catch return &.{};
    const metric = model.usage_share_metric;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        out[i] = chartSample(months[order[i]].valueFor(metric));
    }
    return out;
}

fn monthlyChartProviderValues(model: *const Model, arena: std.mem.Allocator, slot: usize) []const f32 {
    const months = monthlyChartMonths(model);
    if (months.len == 0) return &.{};
    var order: [max_months]usize = undefined;
    const n = oldestFirstMonthOrder(months, &order);
    const out = arena.alloc(f32, n) catch return &.{};
    const metric = model.usage_share_metric;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const month = months[order[i]];
        if (!hasByProviderSamples(month.by_provider)) {
            out[i] = std.math.nan(f32);
            continue;
        }
        out[i] = chartSample(providerDayValue(month.by_provider[slot], metric));
    }
    return out;
}

/// Claude `byProvider` totals for the active metric. NaN when that
/// month's `byProvider` is missing / empty.
pub fn monthlyChartClaudeValues(model: *const Model, arena: std.mem.Allocator) []const f32 {
    return monthlyChartProviderValues(model, arena, protocol.usage_day_provider_claude);
}

/// Codex `byProvider` totals for the active metric. NaN when that
/// month's `byProvider` is missing / empty.
pub fn monthlyChartCodexValues(model: *const Model, arena: std.mem.Allocator) []const f32 {
    return monthlyChartProviderValues(model, arena, protocol.usage_day_provider_codex);
}

/// Max finite Claude/Codex provider-month sample for the active Cost |
/// Tokens metric across the painted window (single-provider peak, not
/// the combined month total). Null when the chart is hidden, there are
/// no finite samples, or that peak is 0 — omit Native `y-max` and
/// leave the auto-domain rather than inventing height.
pub fn monthlyChartYMax(model: *const Model) ?f32 {
    const months = monthlyChartMonths(model);
    if (months.len == 0) return null;
    const metric = model.usage_share_metric;
    var peak: f32 = 0;
    var any_finite = false;
    for (months) |month| {
        if (!hasByProviderSamples(month.by_provider)) continue;
        for (month.by_provider) |slot| {
            const sample = chartSample(providerDayValue(slot, metric));
            if (!std.math.isFinite(sample)) continue;
            any_finite = true;
            if (sample > peak) peak = sample;
        }
    }
    if (!any_finite or !(peak > 0)) return null;
    return peak;
}

pub fn hasMonthlyChartYMax(model: *const Model) bool {
    return monthlyChartYMax(model) != null;
}

/// Scalar for Native `y-max="{usage_monthly_chart_y_max}"`. 0 when the
/// pin is omitted (the markup `if` hides this binding).
pub fn monthlyChartYMaxValue(model: *const Model) f32 {
    return monthlyChartYMax(model) orelse 0;
}

/// Category labels oldest-first, one per chart sample. Opaque
/// `firstDay` strings, same honesty as Daily day labels.
pub fn monthlyChartLabels(model: *const Model, arena: std.mem.Allocator) []const []const u8 {
    const months = monthlyChartMonths(model);
    if (months.len == 0) return &.{};
    var order: [max_months]usize = undefined;
    const n = oldestFirstMonthOrder(months, &order);
    const out = arena.alloc([]const u8, n) catch return &.{};
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const label = months[order[i]].firstDay();
        out[i] = if (label.len > 0) copyArena(arena, label) else "";
    }
    return out;
}

pub fn monthRows(model: *const Model, arena: std.mem.Allocator) []const Row {
    if (!historyPainted(model) or model.usage_view != .monthly) return &.{};
    const count = model.usage_history.month_count;
    if (count == 0) return &.{};
    const months = model.usage_history.months[0..count];
    const max = maxMonthValue(months, model.usage_share_metric);
    const out = arena.alloc(Row, count) catch return &.{};
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const row = months[i];
        const label = if (row.firstDay().len > 0) row.firstDay() else "—";
        const share = monthShare(row, max, model.usage_share_metric);
        var percent_buf: [16]u8 = undefined;
        const percent = if (formatPercent(&percent_buf, share)) |text|
            copyArena(arena, text)
        else
            "";
        out[i] = .{
            .id = @intCast(i + 1),
            .line = joinLabelDetail(arena, label, row.total_tokens, row.cost_usd, row.sessions),
            .share = @floatCast(share),
            .percent = percent,
            .has_share = share > 0,
        };
        fillNestedByProvider(&out[i], arena, row.by_provider, row.valueFor(model.usage_share_metric), model.usage_share_metric);
    }
    return out;
}

pub fn projectsEmpty(model: *const Model) bool {
    return historyPainted(model) and model.usage_view == .projects and model.usage_history.project_count == 0;
}

/// Filter is non-empty and no cached project matches. Distinct from
/// `projectsEmpty` (history has no projects at all).
pub fn projectsNoMatch(model: *const Model) bool {
    if (!historyPainted(model) or model.usage_view != .projects) return false;
    const count = model.usage_history.project_count;
    if (count == 0) return false;
    const query = projectFilter(model);
    if (query.len == 0) return false;
    for (model.usage_history.projects[0..count]) |row| {
        if (cachedProjectMatches(row, query)) return false;
    }
    return true;
}

/// Visible filtered project indices in painted-row order (cache
/// order, not resorted). Empty when Projects is hidden, the cache
/// has no projects, or the filter matches nothing.
fn visibleProjectIndices(model: *const Model, dest: []usize) usize {
    if (!historyPainted(model) or model.usage_view != .projects) return 0;
    const count = model.usage_history.project_count;
    if (count == 0) return 0;
    const projects = model.usage_history.projects[0..count];
    const query = projectFilter(model);
    var n: usize = 0;
    var i: usize = 0;
    while (i < count and n < dest.len) : (i += 1) {
        if (!cachedProjectMatches(projects[i], query)) continue;
        dest[n] = i;
        n += 1;
    }
    return n;
}

/// True when Projects is painted with at least one visible filtered
/// row. Empty `projects[]` / no-match hide the Native chart (no fake
/// samples).
pub fn hasProjectsChart(model: *const Model) bool {
    var idx_buf: [max_projects]usize = undefined;
    return visibleProjectIndices(model, &idx_buf) > 0;
}

/// Active Cost | Tokens project totals in painted-row order. Empty
/// when the chart is hidden. Not painted (the Projects chart is
/// layered Claude / Codex area series); kept so tests can contrast
/// combined totals against the single-provider y-max peak.
pub fn projectsChartValues(model: *const Model, arena: std.mem.Allocator) []const f32 {
    var idx_buf: [max_projects]usize = undefined;
    const n = visibleProjectIndices(model, &idx_buf);
    if (n == 0) return &.{};
    const projects = model.usage_history.projects[0..model.usage_history.project_count];
    const out = arena.alloc(f32, n) catch return &.{};
    const metric = model.usage_share_metric;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        out[i] = chartSample(projects[idx_buf[i]].valueFor(metric));
    }
    return out;
}

fn projectsChartProviderValues(model: *const Model, arena: std.mem.Allocator, slot: usize) []const f32 {
    var idx_buf: [max_projects]usize = undefined;
    const n = visibleProjectIndices(model, &idx_buf);
    if (n == 0) return &.{};
    const projects = model.usage_history.projects[0..model.usage_history.project_count];
    const out = arena.alloc(f32, n) catch return &.{};
    const metric = model.usage_share_metric;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const project = projects[idx_buf[i]];
        if (!hasByProviderSamples(project.by_provider)) {
            out[i] = std.math.nan(f32);
            continue;
        }
        out[i] = chartSample(providerDayValue(project.by_provider[slot], metric));
    }
    return out;
}

/// Claude `byProvider` totals for the active metric. NaN when that
/// project's `byProvider` is missing / empty.
pub fn projectsChartClaudeValues(model: *const Model, arena: std.mem.Allocator) []const f32 {
    return projectsChartProviderValues(model, arena, protocol.usage_day_provider_claude);
}

/// Codex `byProvider` totals for the active metric. NaN when that
/// project's `byProvider` is missing / empty.
pub fn projectsChartCodexValues(model: *const Model, arena: std.mem.Allocator) []const f32 {
    return projectsChartProviderValues(model, arena, protocol.usage_day_provider_codex);
}

/// Max finite Claude/Codex provider-project sample for the active
/// Cost | Tokens metric among **visible** filtered rows
/// (single-provider peak, not the combined project total). Null when
/// the chart is hidden, there are no finite samples, or that peak is
/// 0 — omit Native `y-max` and leave the auto-domain rather than
/// inventing height.
pub fn projectsChartYMax(model: *const Model) ?f32 {
    var idx_buf: [max_projects]usize = undefined;
    const n = visibleProjectIndices(model, &idx_buf);
    if (n == 0) return null;
    const projects = model.usage_history.projects[0..model.usage_history.project_count];
    const metric = model.usage_share_metric;
    var peak: f32 = 0;
    var any_finite = false;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const project = projects[idx_buf[i]];
        if (!hasByProviderSamples(project.by_provider)) continue;
        for (project.by_provider) |slot| {
            const sample = chartSample(providerDayValue(slot, metric));
            if (!std.math.isFinite(sample)) continue;
            any_finite = true;
            if (sample > peak) peak = sample;
        }
    }
    if (!any_finite or !(peak > 0)) return null;
    return peak;
}

pub fn hasProjectsChartYMax(model: *const Model) bool {
    return projectsChartYMax(model) != null;
}

/// Scalar for Native `y-max="{usage_projects_chart_y_max}"`. 0 when
/// the pin is omitted (the markup `if` hides this binding).
pub fn projectsChartYMaxValue(model: *const Model) f32 {
    return projectsChartYMax(model) orelse 0;
}

/// Category labels in painted-row order, one per chart sample. Short
/// path basename via `projectBasename`.
pub fn projectsChartLabels(model: *const Model, arena: std.mem.Allocator) []const []const u8 {
    var idx_buf: [max_projects]usize = undefined;
    const n = visibleProjectIndices(model, &idx_buf);
    if (n == 0) return &.{};
    const projects = model.usage_history.projects[0..model.usage_history.project_count];
    const out = arena.alloc([]const u8, n) catch return &.{};
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const label = projectBasename(projects[idx_buf[i]].path());
        out[i] = if (label.len > 0) copyArena(arena, label) else "";
    }
    return out;
}

pub fn projectRows(model: *const Model, arena: std.mem.Allocator) []const Row {
    var idx_buf: [max_projects]usize = undefined;
    const visible_n = visibleProjectIndices(model, &idx_buf);
    if (visible_n == 0) return &.{};
    const projects = model.usage_history.projects[0..model.usage_history.project_count];
    var max: f64 = 0;
    var i: usize = 0;
    while (i < visible_n) : (i += 1) {
        const value = projects[idx_buf[i]].valueFor(model.usage_share_metric);
        if (value > max) max = value;
    }
    const out = arena.alloc(Row, visible_n) catch return &.{};
    i = 0;
    while (i < visible_n) : (i += 1) {
        const row = projects[idx_buf[i]];
        const share = projectShare(row, max, model.usage_share_metric);
        var percent_buf: [16]u8 = undefined;
        const percent = if (formatPercent(&percent_buf, share)) |text|
            copyArena(arena, text)
        else
            "";
        out[i] = .{
            .id = @intCast(i + 1),
            .line = joinLabelDetail(arena, projectBasename(row.path()), row.total_tokens, row.cost_usd, row.sessions),
            .share = @floatCast(share),
            .percent = percent,
            .has_share = share > 0,
        };
        fillNestedByProvider(&out[i], arena, row.by_provider, row.valueFor(model.usage_share_metric), model.usage_share_metric);
    }
    return out;
}

pub fn hasNotice(model: *const Model) bool {
    if (!historyPainted(model)) return false;
    return model.usage_history.error_count > 0 or model.usage_history.pricing == .unavailable;
}

pub fn hasQuality(model: *const Model) bool {
    return historyPainted(model) and model.usage_view == .daily;
}

/// Native metric strip when history is painted on Daily, Monthly, or
/// Projects. Always five tiles, including zeros. Cost quality stays
/// Daily-only.
pub fn hasMetricStrip(model: *const Model) bool {
    return historyPainted(model);
}

pub fn hasScanFooter(model: *const Model) bool {
    if (!historyPainted(model)) return false;
    return model.usage_history.scanned_files > 0 or model.usage_history.records > 0;
}

pub fn noticeRows(model: *const Model, arena: std.mem.Allocator) []const Row {
    if (!hasNotice(model)) return &.{};
    const cache = model.usage_history;
    const extra: usize = if (cache.pricing == .unavailable) 1 else 0;
    const count = cache.error_count + extra;
    const out = arena.alloc(Row, count) catch return &.{};
    var i: usize = 0;
    while (i < cache.error_count) : (i += 1) {
        out[i] = .{
            .id = @intCast(i + 1),
            .line = copyArena(arena, cache.errors[i].text()),
        };
    }
    if (extra == 1) {
        out[i] = .{
            .id = @intCast(i + 1),
            .line = rates_unavailable_notice,
        };
    }
    return out;
}

pub fn qualityRows(model: *const Model, arena: std.mem.Allocator) []const Row {
    if (!hasQuality(model)) return &.{};
    const q = model.usage_history.quality;
    const out = arena.alloc(Row, 4) catch return &.{};
    const labels = [_][]const u8{ "Provider reported", "Model priced", "Unpriced" };
    const shares = [_]f64{ q.provider_reported_share, q.model_priced_share, q.unpriced_share };
    var i: usize = 0;
    while (i < 3) : (i += 1) {
        const share = clampShare(shares[i]);
        var percent_buf: [16]u8 = undefined;
        out[i] = .{
            .id = @intCast(i + 1),
            .line = labels[i],
            .share = @floatCast(share),
            .percent = copyArena(arena, formatPercentLabel(&percent_buf, share)),
            .has_share = share > 0,
        };
    }
    var usd_buf: [24]u8 = undefined;
    out[3] = .{
        .id = 4,
        .line = "Cache savings",
        .share = 0,
        .percent = copyArena(arena, formatUsd(&usd_buf, q.cache_savings_usd)),
        .has_share = false,
    };
    return out;
}

fn compactTokenLabel(buf: []u8, tokens: u64) []const u8 {
    return goal.formatCompactTokens(buf, tokens) orelse "0";
}

/// Days in the painted window with `total_tokens > 0`.
fn activeDayCount(days: []const CachedDay) u64 {
    var n: u64 = 0;
    for (days) |day| {
        if (day.total_tokens > 0) n += 1;
    }
    return n;
}

/// `totalTokens / active_days`, or 0 when no active day.
fn tokensPerActiveDay(total_tokens: u64, days: []const CachedDay) u64 {
    const n = activeDayCount(days);
    if (n == 0) return 0;
    return total_tokens / n;
}

/// Months in the painted window with `total_tokens > 0`.
fn activeMonthCount(months: []const CachedMonth) u64 {
    var n: u64 = 0;
    for (months) |month| {
        if (month.total_tokens > 0) n += 1;
    }
    return n;
}

/// `totalTokens / active_months`, or 0 when no active month.
fn tokensPerActiveMonth(total_tokens: u64, months: []const CachedMonth) u64 {
    const n = activeMonthCount(months);
    if (n == 0) return 0;
    return total_tokens / n;
}

/// `cached / (uncached + cached)`, or 0 when observed input is empty.
fn cachedInputShare(totals: protocol.ParsedTokenTotals) f64 {
    const observed = tokensAsFloat(totals.uncached_input) + tokensAsFloat(totals.cached_input);
    if (!(observed > 0)) return 0;
    return clampShare(tokensAsFloat(totals.cached_input) / observed);
}

fn metricDetail(arena: std.mem.Allocator, buf: []u8, comptime fmt: []const u8, args: anytype) []const u8 {
    const text = std.fmt.bufPrint(buf, fmt, args) catch return "";
    return copyArena(arena, text);
}

/// Five tiles: processed tokens, cached input, uncached input,
/// output, cache savings. Empty when history is not painted.
/// Daily / Projects use active-day averages from `daily[]`; Monthly
/// prefers active-month averages from `months[]`.
pub fn metricRows(model: *const Model, arena: std.mem.Allocator) []const Row {
    if (!hasMetricStrip(model)) return &.{};
    const cache = model.usage_history;
    const totals = cache.totals;
    const days = cache.daily[0..cache.daily_count];
    const months = cache.months[0..cache.month_count];
    const out = arena.alloc(Row, max_metric_tiles) catch return &.{};

    var token_buf: [16]u8 = undefined;
    var detail_buf: [48]u8 = undefined;
    var percent_buf: [16]u8 = undefined;
    var usd_buf: [24]u8 = undefined;

    const processed = compactTokenLabel(&token_buf, cache.total_tokens);
    const per_unit_tokens = switch (model.usage_view) {
        .monthly => tokensPerActiveMonth(cache.total_tokens, months),
        .daily, .projects => tokensPerActiveDay(cache.total_tokens, days),
    };
    const per_unit = compactTokenLabel(&percent_buf, per_unit_tokens);
    const per_unit_label: []const u8 = switch (model.usage_view) {
        .monthly => "per active month",
        .daily, .projects => "per active day",
    };
    out[0] = .{
        .id = 1,
        .line = "Processed tokens",
        .percent = copyArena(arena, processed),
        .detail = metricDetail(arena, &detail_buf, "{s} {s}", .{ per_unit, per_unit_label }),
    };

    const cached = compactTokenLabel(&token_buf, totals.cached_input);
    const cached_share = formatPercentLabel(&percent_buf, cachedInputShare(totals));
    out[1] = .{
        .id = 2,
        .line = "Cached input",
        .percent = copyArena(arena, cached),
        .detail = metricDetail(arena, &detail_buf, "{s} of observed input", .{cached_share}),
    };

    const uncached = compactTokenLabel(&token_buf, totals.uncached_input);
    const writes = compactTokenLabel(&percent_buf, totals.cache_creation);
    out[2] = .{
        .id = 3,
        .line = "Uncached input",
        .percent = copyArena(arena, uncached),
        .detail = metricDetail(arena, &detail_buf, "{s} cache writes", .{writes}),
    };

    const output = compactTokenLabel(&token_buf, totals.output);
    const reasoning = compactTokenLabel(&percent_buf, totals.reasoning);
    out[3] = .{
        .id = 4,
        .line = "Output",
        .percent = copyArena(arena, output),
        .detail = metricDetail(arena, &detail_buf, "includes {s} reasoning", .{reasoning}),
    };

    const savings = copyArena(arena, formatUsd(&usd_buf, cache.quality.cache_savings_usd));
    const savings_detail = if (cache.cost_usd > 0)
        metricDetail(arena, &detail_buf, "{d:.1}x raw cost", .{cache.quality.cache_savings_usd / cache.cost_usd})
    else
        "vs full input rates";
    out[4] = .{
        .id = 5,
        .line = "Cache savings",
        .percent = savings,
        .detail = savings_detail,
    };
    return out;
}

pub fn scanFooter(model: *const Model, arena: std.mem.Allocator) []const u8 {
    if (!hasScanFooter(model)) return "";
    const cache = model.usage_history;
    var buf: [max_line]u8 = undefined;
    var pos: usize = 0;
    const files = std.fmt.bufPrint(buf[pos..], "{d} files", .{cache.scanned_files}) catch return "";
    pos += files.len;
    if (cache.skipped_files > 0) {
        const skipped = std.fmt.bufPrint(buf[pos..], " · {d} skipped", .{cache.skipped_files}) catch
            return copyArena(arena, buf[0..pos]);
        pos += skipped.len;
    }
    const rec = std.fmt.bufPrint(buf[pos..], " · {d} records", .{cache.records}) catch
        return copyArena(arena, buf[0..pos]);
    pos += rec.len;
    if (cache.scan_duration_secs > 0) {
        const dur = std.fmt.bufPrint(buf[pos..], " · {d:.1}s", .{cache.scan_duration_secs}) catch
            return copyArena(arena, buf[0..pos]);
        pos += dur.len;
    }
    return copyArena(arena, buf[0..pos]);
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
    try std.testing.expect(std.meta.eql(model.usage_history.window, protocol.UsageWindow{ .trailing_days = 30 }));
    try std.testing.expectEqual(@as(u64, 12345), model.usage_history.total_tokens);
    try std.testing.expectEqual(@as(u64, 4), model.usage_history.sessions);
    try std.testing.expectEqualStrings("claude", model.usage_history.providers[0].id());
    try std.testing.expectEqual(@as(usize, 0), model.usage_history.model_count);
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

fn expectWindowJson(stdin: []const u8, needle: []const u8) !void {
    try std.testing.expect(std.mem.indexOf(u8, stdin, needle) != null);
}

test "Monthly view requests months 12; Daily and Projects share the selected window" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    try std.testing.expectEqual(View.daily, model.usage_view);
    try std.testing.expectEqual(WindowChoice.trailing_30, model.usage_window);
    refresh(&model, &fx);
    const daily = pendingSpawnKey(&fx, model.daemon_usage_history_key) orelse return error.MissingDailyUsageWindow;
    try expectWindowJson(daily.stdin, "\"window\":{\"trailingDays\":30}");

    setView(&model, &fx, .projects);
    try std.testing.expectEqual(View.projects, model.usage_view);
    try std.testing.expectEqual(daily.key, model.daemon_usage_history_key);

    setView(&model, &fx, .monthly);
    try std.testing.expectEqual(View.monthly, model.usage_view);
    const monthly = pendingSpawnKey(&fx, model.daemon_usage_history_key) orelse return error.MissingMonthlyUsageWindow;
    try std.testing.expect(monthly.key != daily.key);
    try expectWindowJson(monthly.stdin, "\"window\":{\"months\":12}");
    try std.testing.expect(std.mem.indexOf(u8, monthly.stdin, "\"trailingDays\"") == null);
}

test "WINDOW_CHOICES emit window JSON; same-window select is a no-op; Monthly stays months 12" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    model.settings_page = .usage;
    try std.testing.expectEqual(default_window_choice, model.usage_window);
    try std.testing.expectEqual(@as(usize, 5), window_choices.len);
    try std.testing.expect(std.meta.eql(windowForView(&model), protocol.UsageWindow{ .trailing_days = 30 }));

    refresh(&model, &fx);
    var spawn = pendingSpawnKey(&fx, model.daemon_usage_history_key) orelse return error.MissingDefaultUsageWindow;
    try expectWindowJson(spawn.stdin, "\"window\":{\"trailingDays\":30}");
    const default_key = spawn.key;

    setWindow(&model, &fx, .trailing_30);
    try std.testing.expectEqual(default_key, model.daemon_usage_history_key);
    try std.testing.expectEqual(WindowChoice.trailing_30, model.usage_window);

    const cases = [_]struct { choice: WindowChoice, needle: []const u8 }{
        .{ .choice = .trailing_7, .needle = "\"window\":{\"trailingDays\":7}" },
        .{ .choice = .trailing_30, .needle = "\"window\":{\"trailingDays\":30}" },
        .{ .choice = .trailing_90, .needle = "\"window\":{\"trailingDays\":90}" },
        .{ .choice = .this_month, .needle = "\"window\":\"thisMonth\"" },
        .{ .choice = .last_month, .needle = "\"window\":\"lastMonth\"" },
    };
    for (cases) |case| {
        setWindow(&model, &fx, case.choice);
        spawn = pendingSpawnKey(&fx, model.daemon_usage_history_key) orelse return error.MissingWindowChoiceSpawn;
        try expectWindowJson(spawn.stdin, case.needle);
        const key = spawn.key;
        setWindow(&model, &fx, case.choice);
        try std.testing.expectEqual(key, model.daemon_usage_history_key);
        try std.testing.expectEqual(case.choice, model.usage_window);

        setView(&model, &fx, .projects);
        try std.testing.expectEqual(View.projects, model.usage_view);
        try std.testing.expectEqual(key, model.daemon_usage_history_key);

        setView(&model, &fx, .daily);
        try std.testing.expectEqual(key, model.daemon_usage_history_key);
    }

    setView(&model, &fx, .monthly);
    spawn = pendingSpawnKey(&fx, model.daemon_usage_history_key) orelse return error.MissingMonthlyUsageWindowChoice;
    try expectWindowJson(spawn.stdin, "\"window\":{\"months\":12}");
    const monthly_key = spawn.key;
    setWindow(&model, &fx, .trailing_7);
    try std.testing.expectEqual(WindowChoice.trailing_7, model.usage_window);
    try std.testing.expectEqual(monthly_key, model.daemon_usage_history_key);
    try std.testing.expect(std.meta.eql(windowForView(&model), monthly_window));
}

test "same-shape history stays painted while a new window scans; months does not masquerade" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    model.settings_page = .usage;
    setBreakdown(&model, .days);
    refresh(&model, &fx);
    const first = pendingSpawnKey(&fx, model.daemon_usage_history_key) orelse return error.MissingShapeScan;
    applyLine(&model, .{ .key = first.key, .line = usage_history_ok_line });
    handleExit(&model, .{ .key = first.key, .reason = .exited, .code = 0 });
    try std.testing.expect(cacheShapeMatches(&model));
    try std.testing.expectEqual(@as(usize, 1), dailyRows(&model, arena).len);

    setWindow(&model, &fx, .trailing_7);
    try std.testing.expect(cacheShapeMatches(&model));
    try std.testing.expectEqual(@as(usize, 1), dailyRows(&model, arena).len);
    try std.testing.expect(std.meta.eql(model.usage_history.window, protocol.UsageWindow{ .trailing_days = 30 }));
    const seven = pendingSpawnKey(&fx, model.daemon_usage_history_key) orelse return error.MissingSevenDayScan;
    try expectWindowJson(seven.stdin, "\"window\":{\"trailingDays\":7}");

    setView(&model, &fx, .monthly);
    try std.testing.expect(!cacheShapeMatches(&model));
    try std.testing.expectEqual(@as(usize, 0), monthRows(&model, arena).len);
    try std.testing.expect(model.usage_history.present);
    const monthly = pendingSpawnKey(&fx, model.daemon_usage_history_key) orelse return error.MissingMonthlyShapeScan;
    try expectWindowJson(monthly.stdin, "\"window\":{\"months\":12}");
    applyLine(&model, .{ .key = monthly.key, .line = usage_history_ok_line });
    try std.testing.expect(cacheShapeMatches(&model));
    try std.testing.expect(std.meta.eql(model.usage_history.window, monthly_window));
    try std.testing.expectEqual(@as(usize, 1), monthRows(&model, arena).len);
}

test "provider shares prefer wire costShare/tokenShare and compute when missing" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    model.settings_page = .usage;
    try std.testing.expectEqual(ShareMetric.cost, model.usage_share_metric);

    refresh(&model, &fx);
    const sidecar = pendingSpawnKey(&fx, model.daemon_usage_history_key) orelse return error.MissingShareParseSpawn;
    const wired =
        "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000015\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"usageHistory\",\"history\":{\"totalTokens\":12345,\"costUsd\":1.25,\"sessions\":4,\"providers\":[{\"provider\":\"claude\",\"totalTokens\":10000,\"costUsd\":1.0,\"costShare\":0.8,\"tokenShare\":0.81},{\"provider\":\"codex\",\"totalTokens\":2345,\"costUsd\":0.25}]}}}}";
    applyLine(&model, .{ .key = sidecar.key, .line = wired });
    try std.testing.expect(model.usage_history.present);
    try std.testing.expectApproxEqAbs(@as(f64, 0.8), model.usage_history.providers[0].cost_share, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.81), model.usage_history.providers[0].token_share, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.2), model.usage_history.providers[1].cost_share, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 2345.0 / 12345.0), model.usage_history.providers[1].token_share, 0.0001);

    const cost_rows = providerRows(&model, arena);
    try std.testing.expectEqual(@as(usize, 2), cost_rows.len);
    try std.testing.expect(cost_rows[0].has_share);
    try std.testing.expectApproxEqAbs(@as(f32, 0.8), cost_rows[0].share, 0.0001);
    try std.testing.expectEqualStrings("80.0%", cost_rows[0].percent);
    try std.testing.expectApproxEqAbs(@as(f32, 0.2), cost_rows[1].share, 0.0001);
    try std.testing.expectEqualStrings("20.0%", cost_rows[1].percent);

    setShareMetric(&model, .tokens);
    try std.testing.expectEqual(ShareMetric.tokens, model.usage_share_metric);
    const token_rows = providerRows(&model, arena);
    try std.testing.expectApproxEqAbs(@as(f32, 0.81), token_rows[0].share, 0.0001);
    try std.testing.expectEqualStrings("81.0%", token_rows[0].percent);
    try std.testing.expectApproxEqAbs(@as(f32, @floatCast(2345.0 / 12345.0)), token_rows[1].share, 0.0001);

    model.usage_view = .monthly;
    try std.testing.expectEqual(@as(usize, 0), providerRows(&model, arena).len);
}

test "zero totals keep shares at 0; empty providers paint no share rows" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    model.settings_page = .usage;
    refresh(&model, &fx);
    const sidecar = pendingSpawnKey(&fx, model.daemon_usage_history_key) orelse return error.MissingZeroShareSpawn;
    applyLine(&model, .{ .key = sidecar.key, .line = "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000015\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"usageHistory\",\"history\":{\"totalTokens\":0,\"costUsd\":0,\"providers\":[{\"provider\":\"claude\",\"totalTokens\":0,\"costUsd\":0}]}}}}" });
    try std.testing.expectApproxEqAbs(@as(f64, 0), model.usage_history.providers[0].cost_share, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 0), model.usage_history.providers[0].token_share, 0.0001);
    const rows = providerRows(&model, arena);
    try std.testing.expectEqual(@as(usize, 1), rows.len);
    try std.testing.expect(!rows[0].has_share);
    try std.testing.expectEqual(@as(f32, 0), rows[0].share);
    try std.testing.expectEqualStrings("", rows[0].percent);

    applyLine(&model, .{ .key = sidecar.key, .line = "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000015\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"usageHistory\",\"history\":{\"totalTokens\":100,\"costUsd\":1,\"providers\":[]}}}}" });
    try std.testing.expectEqual(@as(usize, 0), providerRows(&model, arena).len);
}

test "model rows prefer wire costShare, compute Tokens from totals, and flip with Model|Days" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    model.settings_page = .usage;
    try std.testing.expectEqual(Breakdown.model, model.usage_breakdown);
    try std.testing.expectEqual(ShareMetric.cost, model.usage_share_metric);

    refresh(&model, &fx);
    const sidecar = pendingSpawnKey(&fx, model.daemon_usage_history_key) orelse return error.MissingModelShareSpawn;
    const keyed = sidecar.key;
    applyLine(&model, .{ .key = keyed, .line = "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000015\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"usageHistory\",\"history\":{\"totalTokens\":12345,\"costUsd\":1.25,\"sessions\":4,\"providers\":[{\"provider\":\"claude\",\"totalTokens\":10000,\"costUsd\":1.0}],\"models\":[{\"provider\":\"claude\",\"model\":\"opus\",\"totalTokens\":10000,\"costUsd\":1.0,\"costShare\":0.8},{\"provider\":\"codex\",\"model\":\"gpt-5\",\"totalTokens\":2345,\"costUsd\":0.25}],\"daily\":[{\"day\":\"2026-09-06\",\"totalTokens\":400,\"costUsd\":0.5}]}}}}" });
    handleExit(&model, .{ .key = keyed, .reason = .exited, .code = 0 });
    try std.testing.expectEqual(@as(usize, 2), model.usage_history.model_count);
    try std.testing.expectEqualStrings("claude", model.usage_history.models[0].provider());
    try std.testing.expectEqualStrings("opus", model.usage_history.models[0].name());
    try std.testing.expectApproxEqAbs(@as(f64, 0.8), model.usage_history.models[0].cost_share, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.2), model.usage_history.models[1].cost_share, 0.0001);

    const cost_rows = modelRows(&model, arena);
    try std.testing.expectEqual(@as(usize, 2), cost_rows.len);
    try std.testing.expectEqualStrings("Claude Code · opus · 10k · $1.00", cost_rows[0].line);
    try std.testing.expect(cost_rows[0].has_share);
    try std.testing.expectApproxEqAbs(@as(f32, 0.8), cost_rows[0].share, 0.0001);
    try std.testing.expectEqualStrings("80.0%", cost_rows[0].percent);
    try std.testing.expectEqualStrings("Codex · gpt-5 · 2.3k · $0.25", cost_rows[1].line);
    try std.testing.expectApproxEqAbs(@as(f32, 0.2), cost_rows[1].share, 0.0001);
    try std.testing.expectEqualStrings("20.0%", cost_rows[1].percent);
    try std.testing.expectEqual(@as(usize, 0), dailyRows(&model, arena).len);
    try std.testing.expectEqual(@as(usize, 1), providerRows(&model, arena).len);

    const spawn_count = fx.pendingSpawnCount();
    setShareMetric(&model, .tokens);
    try std.testing.expectEqual(ShareMetric.tokens, model.usage_share_metric);
    try std.testing.expectEqual(@as(u64, 0), model.daemon_usage_history_key);
    try std.testing.expectEqual(spawn_count, fx.pendingSpawnCount());
    const token_rows = modelRows(&model, arena);
    try std.testing.expectApproxEqAbs(@as(f32, @floatCast(10000.0 / 12345.0)), token_rows[0].share, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, @floatCast(2345.0 / 12345.0)), token_rows[1].share, 0.0001);

    setBreakdown(&model, .days);
    try std.testing.expectEqual(Breakdown.days, model.usage_breakdown);
    try std.testing.expectEqual(@as(usize, 0), modelRows(&model, arena).len);
    try std.testing.expectEqual(@as(usize, 1), dailyRows(&model, arena).len);
    try std.testing.expectEqual(@as(usize, 1), providerRows(&model, arena).len);

    setBreakdown(&model, .model);
    try std.testing.expectEqual(@as(usize, 2), modelRows(&model, arena).len);
    try std.testing.expectEqual(@as(usize, 0), dailyRows(&model, arena).len);

    model.usage_view = .monthly;
    try std.testing.expectEqual(@as(usize, 0), modelRows(&model, arena).len);
}

test "model rows append a per-MTok hint on lookup hit and skip unpriceable names" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    model.settings_page = .usage;
    defer model.litellm_rates.deinit();

    refresh(&model, &fx);
    const sidecar = pendingSpawnKey(&fx, model.daemon_usage_history_key) orelse return error.MissingRateHintSpawn;
    applyLine(&model, .{ .key = sidecar.key, .line = "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000015\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"usageHistory\",\"history\":{\"totalTokens\":12345,\"costUsd\":1.25,\"models\":[{\"provider\":\"claude\",\"model\":\"opus\",\"totalTokens\":10000,\"costUsd\":1.0,\"costShare\":0.8},{\"provider\":\"codex\",\"model\":\"gpt-5\",\"totalTokens\":2345,\"costUsd\":0.25}]}}}}" });
    handleExit(&model, .{ .key = sidecar.key, .reason = .exited, .code = 0 });

    const fixture =
        \\{"gpt-5":{"input_cost_per_token":1e-6,"output_cost_per_token":2e-6},"opus":{"input_cost_per_token":3e-6,"output_cost_per_token":4e-6}}
    ;
    model.litellm_rates = litellm_rates.parseLiteLlmDocument(std.heap.page_allocator, fixture);
    model.litellm_rates.status = .cached;

    const rows = modelRows(&model, arena);
    try std.testing.expectEqual(@as(usize, 2), rows.len);
    try std.testing.expectEqualStrings("Claude Code · opus · 10k · $1.00", rows[0].line);
    try std.testing.expectEqualStrings("Codex · gpt-5 · 2.3k · $0.25 · $1.00/$2.00/MTok", rows[1].line);
}

test "missing models stay empty; empty models paint no model rows" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    model.settings_page = .usage;
    refresh(&model, &fx);
    const sidecar = pendingSpawnKey(&fx, model.daemon_usage_history_key) orelse return error.MissingEmptyModelSpawn;
    applyLine(&model, .{ .key = sidecar.key, .line = "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000015\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"usageHistory\",\"history\":{\"totalTokens\":100,\"costUsd\":1,\"models\":[{\"provider\":\"claude\",\"model\":\"opus\",\"totalTokens\":100,\"costUsd\":1,\"costShare\":1}]}}}}" });
    try std.testing.expectEqual(@as(usize, 1), model.usage_history.model_count);
    try std.testing.expectEqual(@as(usize, 1), modelRows(&model, arena).len);

    applyLine(&model, .{ .key = sidecar.key, .line = "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000015\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"usageHistory\",\"history\":{\"totalTokens\":100,\"costUsd\":1}}}}" });
    try std.testing.expectEqual(@as(usize, 0), model.usage_history.model_count);
    try std.testing.expectEqual(@as(usize, 0), modelRows(&model, arena).len);

    applyLine(&model, .{ .key = sidecar.key, .line = "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000015\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"usageHistory\",\"history\":{\"totalTokens\":100,\"costUsd\":1,\"models\":[]}}}}" });
    try std.testing.expectEqual(@as(usize, 0), modelRows(&model, arena).len);

    applyLine(&model, .{ .key = sidecar.key, .line = "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000015\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"usageHistory\",\"history\":{\"totalTokens\":100,\"costUsd\":1,\"models\":[{\"model\":\"ignored\"}]}}}}" });
    try std.testing.expectEqual(@as(usize, 0), modelRows(&model, arena).len);
}

test "daily shares are relative to the max day; Cost|Tokens chip flip updates without refetch" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    model.settings_page = .usage;
    try std.testing.expectEqual(ShareMetric.cost, model.usage_share_metric);
    try std.testing.expectEqual(Breakdown.model, model.usage_breakdown);

    refresh(&model, &fx);
    const sidecar = pendingSpawnKey(&fx, model.daemon_usage_history_key) orelse return error.MissingDailyShareSpawn;
    const keyed = sidecar.key;
    applyLine(&model, .{ .key = keyed, .line = "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000015\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"usageHistory\",\"history\":{\"totalTokens\":500,\"costUsd\":1.5,\"sessions\":3,\"daily\":[{\"day\":\"2026-09-05\",\"totalTokens\":100,\"costUsd\":1.0},{\"day\":\"2026-09-06\",\"totalTokens\":400,\"costUsd\":0.5},{\"day\":\"2026-09-04\",\"totalTokens\":0,\"costUsd\":0}]}}}}" });
    handleExit(&model, .{ .key = keyed, .reason = .exited, .code = 0 });
    try std.testing.expectEqual(@as(u64, 0), model.daemon_usage_history_key);
    try std.testing.expectEqual(@as(usize, 3), model.usage_history.daily_count);
    try std.testing.expectEqual(@as(usize, 0), dailyRows(&model, arena).len);

    setBreakdown(&model, .days);
    const cost_rows = dailyRows(&model, arena);
    try std.testing.expectEqual(@as(usize, 3), cost_rows.len);
    try std.testing.expect(cost_rows[0].has_share);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), cost_rows[0].share, 0.0001);
    try std.testing.expectEqualStrings("100.0%", cost_rows[0].percent);
    try std.testing.expect(cost_rows[1].has_share);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), cost_rows[1].share, 0.0001);
    try std.testing.expectEqualStrings("50.0%", cost_rows[1].percent);
    try std.testing.expect(!cost_rows[2].has_share);
    try std.testing.expectEqual(@as(f32, 0), cost_rows[2].share);
    try std.testing.expectEqualStrings("", cost_rows[2].percent);
    try std.testing.expect(!cost_rows[0].has_by_provider);
    try std.testing.expect(!cost_rows[1].has_by_provider);
    try std.testing.expect(!cost_rows[2].has_by_provider);

    const spawn_count = fx.pendingSpawnCount();
    setShareMetric(&model, .tokens);
    try std.testing.expectEqual(ShareMetric.tokens, model.usage_share_metric);
    try std.testing.expectEqual(@as(u64, 0), model.daemon_usage_history_key);
    try std.testing.expectEqual(spawn_count, fx.pendingSpawnCount());

    const token_rows = dailyRows(&model, arena);
    try std.testing.expectEqual(@as(usize, 3), token_rows.len);
    try std.testing.expect(token_rows[0].has_share);
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), token_rows[0].share, 0.0001);
    try std.testing.expectEqualStrings("25.0%", token_rows[0].percent);
    try std.testing.expect(token_rows[1].has_share);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), token_rows[1].share, 0.0001);
    try std.testing.expectEqualStrings("100.0%", token_rows[1].percent);
    try std.testing.expect(!token_rows[2].has_share);
    try std.testing.expectEqual(@as(f32, 0), token_rows[2].share);
    try std.testing.expectEqualStrings("", token_rows[2].percent);

    model.usage_view = .monthly;
    try std.testing.expectEqual(@as(usize, 0), dailyRows(&model, arena).len);
    model.usage_view = .projects;
    try std.testing.expectEqual(@as(usize, 0), dailyRows(&model, arena).len);
}

test "daily zero window keeps shares at 0; empty daily paints no rows" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    model.settings_page = .usage;
    setBreakdown(&model, .days);
    refresh(&model, &fx);
    const sidecar = pendingSpawnKey(&fx, model.daemon_usage_history_key) orelse return error.MissingZeroDailyShareSpawn;
    applyLine(&model, .{ .key = sidecar.key, .line = "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000015\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"usageHistory\",\"history\":{\"totalTokens\":0,\"costUsd\":0,\"daily\":[{\"day\":\"2026-09-06\",\"totalTokens\":0,\"costUsd\":0}]}}}}" });
    const zero_rows = dailyRows(&model, arena);
    try std.testing.expectEqual(@as(usize, 1), zero_rows.len);
    try std.testing.expect(!zero_rows[0].has_share);
    try std.testing.expectEqual(@as(f32, 0), zero_rows[0].share);
    try std.testing.expectEqualStrings("", zero_rows[0].percent);
    try std.testing.expect(!zero_rows[0].has_by_provider);

    applyLine(&model, .{ .key = sidecar.key, .line = "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000015\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"usageHistory\",\"history\":{\"totalTokens\":100,\"costUsd\":1,\"daily\":[]}}}}" });
    try std.testing.expectEqual(@as(usize, 0), dailyRows(&model, arena).len);
}

test "daily byProvider nested shares are within the day; Cost|Tokens chip flip updates without refetch" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    model.settings_page = .usage;
    setBreakdown(&model, .days);
    refresh(&model, &fx);
    const sidecar = pendingSpawnKey(&fx, model.daemon_usage_history_key) orelse return error.MissingDailyByProviderSpawn;
    const keyed = sidecar.key;
    applyLine(&model, .{ .key = keyed, .line = "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000015\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"usageHistory\",\"history\":{\"totalTokens\":500,\"costUsd\":1.5,\"sessions\":3,\"daily\":[{\"day\":\"2026-09-05\",\"totalTokens\":100,\"costUsd\":1.0,\"byProvider\":[{\"costUsd\":0.25,\"totalTokens\":40},{\"costUsd\":0.75,\"totalTokens\":60}]},{\"day\":\"2026-09-06\",\"totalTokens\":400,\"costUsd\":0.5,\"byProvider\":[{\"costUsd\":0.5,\"totalTokens\":400}]},{\"day\":\"2026-09-07\",\"totalTokens\":50,\"costUsd\":0.2,\"byProvider\":[]},{\"day\":\"2026-09-04\",\"totalTokens\":0,\"costUsd\":0,\"byProvider\":[{\"costUsd\":0.1,\"totalTokens\":10}]}]}}}}" });
    handleExit(&model, .{ .key = keyed, .reason = .exited, .code = 0 });
    try std.testing.expectEqual(@as(u64, 0), model.daemon_usage_history_key);
    try std.testing.expectEqual(@as(usize, 4), model.usage_history.daily_count);
    try std.testing.expectApproxEqAbs(@as(f64, 0.25), model.usage_history.daily[0].by_provider[0].cost_usd, 0.0001);
    try std.testing.expectEqual(@as(u64, 40), model.usage_history.daily[0].by_provider[0].total_tokens);
    try std.testing.expectApproxEqAbs(@as(f64, 0.75), model.usage_history.daily[0].by_provider[1].cost_usd, 0.0001);
    try std.testing.expectEqual(@as(u64, 400), model.usage_history.daily[1].by_provider[0].total_tokens);
    try std.testing.expectEqual(@as(u64, 0), model.usage_history.daily[1].by_provider[1].total_tokens);

    const cost_rows = dailyRows(&model, arena);
    try std.testing.expectEqual(@as(usize, 4), cost_rows.len);
    try std.testing.expect(cost_rows[0].has_by_provider);
    try std.testing.expectEqualStrings("Claude Code · 40 · $0.25", cost_rows[0].claude_line);
    try std.testing.expect(cost_rows[0].claude_has_share);
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), cost_rows[0].claude_share, 0.0001);
    try std.testing.expectEqualStrings("25.0%", cost_rows[0].claude_percent);
    try std.testing.expectEqualStrings("Codex · 60 · $0.75", cost_rows[0].codex_line);
    try std.testing.expect(cost_rows[0].codex_has_share);
    try std.testing.expectApproxEqAbs(@as(f32, 0.75), cost_rows[0].codex_share, 0.0001);
    try std.testing.expectEqualStrings("75.0%", cost_rows[0].codex_percent);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), cost_rows[0].share, 0.0001);

    try std.testing.expect(cost_rows[1].has_by_provider);
    try std.testing.expectEqualStrings("Claude Code · 400 · $0.50", cost_rows[1].claude_line);
    try std.testing.expect(cost_rows[1].claude_has_share);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), cost_rows[1].claude_share, 0.0001);
    try std.testing.expectEqualStrings("100.0%", cost_rows[1].claude_percent);
    try std.testing.expectEqualStrings("Codex · 0", cost_rows[1].codex_line);
    try std.testing.expect(!cost_rows[1].codex_has_share);
    try std.testing.expectEqual(@as(f32, 0), cost_rows[1].codex_share);
    try std.testing.expectEqualStrings("", cost_rows[1].codex_percent);

    try std.testing.expect(!cost_rows[2].has_by_provider);
    try std.testing.expectEqualStrings("", cost_rows[2].claude_line);
    try std.testing.expect(!cost_rows[3].has_by_provider);
    try std.testing.expect(!cost_rows[3].has_share);

    const spawn_count = fx.pendingSpawnCount();
    setShareMetric(&model, .tokens);
    try std.testing.expectEqual(ShareMetric.tokens, model.usage_share_metric);
    try std.testing.expectEqual(@as(u64, 0), model.daemon_usage_history_key);
    try std.testing.expectEqual(spawn_count, fx.pendingSpawnCount());

    const token_rows = dailyRows(&model, arena);
    try std.testing.expectEqual(@as(usize, 4), token_rows.len);
    try std.testing.expect(token_rows[0].has_by_provider);
    try std.testing.expectApproxEqAbs(@as(f32, 0.4), token_rows[0].claude_share, 0.0001);
    try std.testing.expectEqualStrings("40.0%", token_rows[0].claude_percent);
    try std.testing.expectApproxEqAbs(@as(f32, 0.6), token_rows[0].codex_share, 0.0001);
    try std.testing.expectEqualStrings("60.0%", token_rows[0].codex_percent);
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), token_rows[0].share, 0.0001);
    try std.testing.expect(token_rows[1].has_by_provider);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), token_rows[1].claude_share, 0.0001);
    try std.testing.expect(!token_rows[1].codex_has_share);
    try std.testing.expect(!token_rows[2].has_by_provider);
    try std.testing.expect(!token_rows[3].has_by_provider);

    model.usage_view = .monthly;
    try std.testing.expectEqual(@as(usize, 0), dailyRows(&model, arena).len);
}

test "daily chart series is oldest-first Cost|Tokens; empty window is empty; provider series NaN-pads; y-max is single-provider peak" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    model.settings_page = .usage;
    try std.testing.expect(!hasDailyChart(&model));
    try std.testing.expectEqual(@as(usize, 0), dailyChartValues(&model, arena).len);
    try std.testing.expect(dailyChartYMax(&model) == null);
    try std.testing.expect(!hasDailyChartYMax(&model));

    refresh(&model, &fx);
    const sidecar = pendingSpawnKey(&fx, model.daemon_usage_history_key) orelse return error.MissingDailyChartSpawn;
    const keyed = sidecar.key;
    applyLine(&model, .{ .key = keyed, .line = "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000015\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"usageHistory\",\"history\":{\"totalTokens\":500,\"costUsd\":1.5,\"sessions\":3,\"daily\":[{\"day\":\"2026-09-05\",\"totalTokens\":100,\"costUsd\":1.0,\"byProvider\":[{\"costUsd\":0.25,\"totalTokens\":40},{\"costUsd\":0.75,\"totalTokens\":60}]},{\"day\":\"2026-09-06\",\"totalTokens\":400,\"costUsd\":0.5,\"byProvider\":[]},{\"day\":\"2026-09-04\",\"totalTokens\":0,\"costUsd\":0}]}}}}" });
    handleExit(&model, .{ .key = keyed, .reason = .exited, .code = 0 });
    try std.testing.expect(!hasDailyChart(&model));
    try std.testing.expectEqual(@as(usize, 0), dailyChartValues(&model, arena).len);
    try std.testing.expect(dailyChartYMax(&model) == null);

    setBreakdown(&model, .days);
    try std.testing.expect(hasDailyChart(&model));
    const cost = dailyChartValues(&model, arena);
    try std.testing.expectEqual(@as(usize, 3), cost.len);
    try std.testing.expectApproxEqAbs(@as(f32, 0), cost[0], 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), cost[1], 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), cost[2], 0.0001);
    const cost_labels = dailyChartLabels(&model, arena);
    try std.testing.expectEqual(@as(usize, 3), cost_labels.len);
    try std.testing.expectEqualStrings("2026-09-04", cost_labels[0]);
    try std.testing.expectEqualStrings("2026-09-05", cost_labels[1]);
    try std.testing.expectEqualStrings("2026-09-06", cost_labels[2]);

    const claude_cost = dailyChartClaudeValues(&model, arena);
    const codex_cost = dailyChartCodexValues(&model, arena);
    try std.testing.expectEqual(@as(usize, 3), claude_cost.len);
    try std.testing.expectEqual(@as(usize, 3), codex_cost.len);
    try std.testing.expect(std.math.isNan(claude_cost[0]));
    try std.testing.expect(std.math.isNan(codex_cost[0]));
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), claude_cost[1], 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.75), codex_cost[1], 0.0001);
    try std.testing.expect(std.math.isNan(claude_cost[2]));
    try std.testing.expect(std.math.isNan(codex_cost[2]));
    // Combined day total is 1.0; y-max is Codex 0.75 (layered, not stacked).
    const cost_ymax = dailyChartYMax(&model) orelse return error.MissingCostChartYMax;
    try std.testing.expect(hasDailyChartYMax(&model));
    try std.testing.expectApproxEqAbs(@as(f32, 0.75), cost_ymax, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.75), dailyChartYMaxValue(&model), 0.0001);

    const saved_claude_cost = model.usage_history.daily[0].by_provider[0].cost_usd;
    const saved_codex_cost = model.usage_history.daily[0].by_provider[1].cost_usd;
    model.usage_history.daily[0].by_provider[0].cost_usd = 0;
    model.usage_history.daily[0].by_provider[1].cost_usd = 0;
    try std.testing.expect(dailyChartYMax(&model) == null);
    try std.testing.expect(!hasDailyChartYMax(&model));
    try std.testing.expectEqual(@as(f32, 0), dailyChartYMaxValue(&model));
    model.usage_history.daily[0].by_provider[0].cost_usd = saved_claude_cost;
    model.usage_history.daily[0].by_provider[1].cost_usd = saved_codex_cost;
    try std.testing.expectApproxEqAbs(@as(f32, 0.75), dailyChartYMaxValue(&model), 0.0001);

    const spawn_count = fx.pendingSpawnCount();
    setShareMetric(&model, .tokens);
    try std.testing.expectEqual(ShareMetric.tokens, model.usage_share_metric);
    try std.testing.expectEqual(@as(u64, 0), model.daemon_usage_history_key);
    try std.testing.expectEqual(spawn_count, fx.pendingSpawnCount());

    const tokens = dailyChartValues(&model, arena);
    try std.testing.expectEqual(@as(usize, 3), tokens.len);
    try std.testing.expectApproxEqAbs(@as(f32, 0), tokens[0], 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 100), tokens[1], 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 400), tokens[2], 0.0001);
    const claude_tokens = dailyChartClaudeValues(&model, arena);
    const codex_tokens = dailyChartCodexValues(&model, arena);
    try std.testing.expect(std.math.isNan(claude_tokens[0]));
    try std.testing.expectApproxEqAbs(@as(f32, 40), claude_tokens[1], 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 60), codex_tokens[1], 0.0001);
    try std.testing.expect(std.math.isNan(claude_tokens[2]));
    try std.testing.expect(std.math.isNan(codex_tokens[2]));
    // Day totals peak at 400 (empty byProvider); y-max is Codex 60.
    const token_ymax = dailyChartYMax(&model) orelse return error.MissingTokenChartYMax;
    try std.testing.expectApproxEqAbs(@as(f32, 60), token_ymax, 0.0001);

    setBreakdown(&model, .model);
    try std.testing.expect(!hasDailyChart(&model));
    try std.testing.expectEqual(@as(usize, 0), dailyChartValues(&model, arena).len);
    try std.testing.expectEqual(@as(usize, 0), dailyChartClaudeValues(&model, arena).len);
    try std.testing.expectEqual(@as(usize, 0), dailyChartLabels(&model, arena).len);
    try std.testing.expect(dailyChartYMax(&model) == null);
    try std.testing.expect(!hasDailyChartYMax(&model));

    setBreakdown(&model, .days);
    model.usage_view = .monthly;
    try std.testing.expect(!hasDailyChart(&model));
    try std.testing.expectEqual(@as(usize, 0), dailyChartValues(&model, arena).len);
    try std.testing.expect(dailyChartYMax(&model) == null);

    model.usage_view = .daily;
    model.usage_history.daily_count = 0;
    try std.testing.expect(!hasDailyChart(&model));
    try std.testing.expectEqual(@as(usize, 0), dailyChartValues(&model, arena).len);
    try std.testing.expectEqual(@as(usize, 0), dailyChartLabels(&model, arena).len);
    try std.testing.expect(dailyChartYMax(&model) == null);
    try std.testing.expectEqual(@as(f32, 0), dailyChartYMaxValue(&model));
}

test "monthly chart series is oldest-first Cost|Tokens; empty window is empty; provider series NaN-pads; y-max is single-provider peak" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    model.settings_page = .usage;
    model.usage_view = .monthly;
    try std.testing.expect(!hasMonthlyChart(&model));
    try std.testing.expectEqual(@as(usize, 0), monthlyChartValues(&model, arena).len);
    try std.testing.expect(monthlyChartYMax(&model) == null);
    try std.testing.expect(!hasMonthlyChartYMax(&model));

    refresh(&model, &fx);
    const sidecar = pendingSpawnKey(&fx, model.daemon_usage_history_key) orelse return error.MissingMonthlyChartSpawn;
    const keyed = sidecar.key;
    applyLine(&model, .{ .key = keyed, .line = "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000015\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"usageHistory\",\"history\":{\"totalTokens\":500,\"costUsd\":1.5,\"sessions\":6,\"months\":[{\"firstDay\":\"2026-09-01\",\"totalTokens\":100,\"costUsd\":1.0,\"sessions\":2,\"byProvider\":[{\"costUsd\":0.25,\"totalTokens\":40},{\"costUsd\":0.75,\"totalTokens\":60}]},{\"firstDay\":\"2026-08-01\",\"totalTokens\":400,\"costUsd\":0.5,\"sessions\":4,\"byProvider\":[]},{\"firstDay\":\"2026-07-01\",\"totalTokens\":0,\"costUsd\":0,\"sessions\":0}]}}}}" });
    handleExit(&model, .{ .key = keyed, .reason = .exited, .code = 0 });
    try std.testing.expect(hasMonthlyChart(&model));
    const cost = monthlyChartValues(&model, arena);
    try std.testing.expectEqual(@as(usize, 3), cost.len);
    try std.testing.expectApproxEqAbs(@as(f32, 0), cost[0], 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), cost[1], 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), cost[2], 0.0001);
    const cost_labels = monthlyChartLabels(&model, arena);
    try std.testing.expectEqual(@as(usize, 3), cost_labels.len);
    try std.testing.expectEqualStrings("2026-07-01", cost_labels[0]);
    try std.testing.expectEqualStrings("2026-08-01", cost_labels[1]);
    try std.testing.expectEqualStrings("2026-09-01", cost_labels[2]);

    const claude_cost = monthlyChartClaudeValues(&model, arena);
    const codex_cost = monthlyChartCodexValues(&model, arena);
    try std.testing.expectEqual(@as(usize, 3), claude_cost.len);
    try std.testing.expectEqual(@as(usize, 3), codex_cost.len);
    try std.testing.expect(std.math.isNan(claude_cost[0]));
    try std.testing.expect(std.math.isNan(codex_cost[0]));
    try std.testing.expect(std.math.isNan(claude_cost[1]));
    try std.testing.expect(std.math.isNan(codex_cost[1]));
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), claude_cost[2], 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.75), codex_cost[2], 0.0001);
    // Combined month total is 1.0; y-max is Codex 0.75 (layered, not stacked).
    const cost_ymax = monthlyChartYMax(&model) orelse return error.MissingCostChartYMax;
    try std.testing.expect(hasMonthlyChartYMax(&model));
    try std.testing.expectApproxEqAbs(@as(f32, 0.75), cost_ymax, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.75), monthlyChartYMaxValue(&model), 0.0001);

    const saved_claude_cost = model.usage_history.months[0].by_provider[0].cost_usd;
    const saved_codex_cost = model.usage_history.months[0].by_provider[1].cost_usd;
    model.usage_history.months[0].by_provider[0].cost_usd = 0;
    model.usage_history.months[0].by_provider[1].cost_usd = 0;
    try std.testing.expect(monthlyChartYMax(&model) == null);
    try std.testing.expect(!hasMonthlyChartYMax(&model));
    try std.testing.expectEqual(@as(f32, 0), monthlyChartYMaxValue(&model));
    model.usage_history.months[0].by_provider[0].cost_usd = saved_claude_cost;
    model.usage_history.months[0].by_provider[1].cost_usd = saved_codex_cost;
    try std.testing.expectApproxEqAbs(@as(f32, 0.75), monthlyChartYMaxValue(&model), 0.0001);

    const spawn_count = fx.pendingSpawnCount();
    setShareMetric(&model, .tokens);
    try std.testing.expectEqual(ShareMetric.tokens, model.usage_share_metric);
    try std.testing.expectEqual(@as(u64, 0), model.daemon_usage_history_key);
    try std.testing.expectEqual(spawn_count, fx.pendingSpawnCount());

    const tokens = monthlyChartValues(&model, arena);
    try std.testing.expectEqual(@as(usize, 3), tokens.len);
    try std.testing.expectApproxEqAbs(@as(f32, 0), tokens[0], 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 400), tokens[1], 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 100), tokens[2], 0.0001);
    const claude_tokens = monthlyChartClaudeValues(&model, arena);
    const codex_tokens = monthlyChartCodexValues(&model, arena);
    try std.testing.expect(std.math.isNan(claude_tokens[0]));
    try std.testing.expect(std.math.isNan(claude_tokens[1]));
    try std.testing.expect(std.math.isNan(codex_tokens[1]));
    try std.testing.expectApproxEqAbs(@as(f32, 40), claude_tokens[2], 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 60), codex_tokens[2], 0.0001);
    // Month totals peak at 400 (empty byProvider); y-max is Codex 60.
    const token_ymax = monthlyChartYMax(&model) orelse return error.MissingTokenChartYMax;
    try std.testing.expectApproxEqAbs(@as(f32, 60), token_ymax, 0.0001);

    model.usage_view = .daily;
    try std.testing.expect(!hasMonthlyChart(&model));
    try std.testing.expectEqual(@as(usize, 0), monthlyChartValues(&model, arena).len);
    try std.testing.expectEqual(@as(usize, 0), monthlyChartClaudeValues(&model, arena).len);
    try std.testing.expectEqual(@as(usize, 0), monthlyChartLabels(&model, arena).len);
    try std.testing.expect(monthlyChartYMax(&model) == null);
    try std.testing.expect(!hasMonthlyChartYMax(&model));

    model.usage_view = .projects;
    try std.testing.expect(!hasMonthlyChart(&model));
    try std.testing.expectEqual(@as(usize, 0), monthlyChartValues(&model, arena).len);
    try std.testing.expect(monthlyChartYMax(&model) == null);

    model.usage_view = .monthly;
    model.usage_history.month_count = 0;
    try std.testing.expect(!hasMonthlyChart(&model));
    try std.testing.expectEqual(@as(usize, 0), monthlyChartValues(&model, arena).len);
    try std.testing.expectEqual(@as(usize, 0), monthlyChartLabels(&model, arena).len);
    try std.testing.expect(monthlyChartYMax(&model) == null);
    try std.testing.expectEqual(@as(f32, 0), monthlyChartYMaxValue(&model));
}

test "monthly shares are relative to the max month; Cost|Tokens chip flip updates without refetch" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    model.settings_page = .usage;
    model.usage_view = .monthly;
    try std.testing.expectEqual(ShareMetric.cost, model.usage_share_metric);

    refresh(&model, &fx);
    const sidecar = pendingSpawnKey(&fx, model.daemon_usage_history_key) orelse return error.MissingMonthlyShareSpawn;
    try expectWindowJson(sidecar.stdin, "\"window\":{\"months\":12}");
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"trailingDays\"") == null);
    const keyed = sidecar.key;
    applyLine(&model, .{ .key = keyed, .line = "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000015\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"usageHistory\",\"history\":{\"totalTokens\":500,\"costUsd\":1.5,\"sessions\":6,\"months\":[{\"firstDay\":\"2026-08-01\",\"totalTokens\":100,\"costUsd\":1.0,\"sessions\":2},{\"firstDay\":\"2026-09-01\",\"totalTokens\":400,\"costUsd\":0.5,\"sessions\":4},{\"firstDay\":\"2026-07-01\",\"totalTokens\":0,\"costUsd\":0,\"sessions\":0}]}}}}" });
    handleExit(&model, .{ .key = keyed, .reason = .exited, .code = 0 });
    try std.testing.expectEqual(@as(u64, 0), model.daemon_usage_history_key);
    try std.testing.expectEqual(@as(usize, 3), model.usage_history.month_count);
    try std.testing.expect(std.meta.eql(model.usage_history.window, monthly_window));

    const cost_rows = monthRows(&model, arena);
    try std.testing.expectEqual(@as(usize, 3), cost_rows.len);
    try std.testing.expect(cost_rows[0].has_share);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), cost_rows[0].share, 0.0001);
    try std.testing.expectEqualStrings("100.0%", cost_rows[0].percent);
    try std.testing.expect(cost_rows[1].has_share);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), cost_rows[1].share, 0.0001);
    try std.testing.expectEqualStrings("50.0%", cost_rows[1].percent);
    try std.testing.expect(!cost_rows[2].has_share);
    try std.testing.expectEqual(@as(f32, 0), cost_rows[2].share);
    try std.testing.expectEqualStrings("", cost_rows[2].percent);
    try std.testing.expect(!cost_rows[0].has_by_provider);
    try std.testing.expect(!cost_rows[1].has_by_provider);
    try std.testing.expect(!cost_rows[2].has_by_provider);

    const spawn_count = fx.pendingSpawnCount();
    setShareMetric(&model, .tokens);
    try std.testing.expectEqual(ShareMetric.tokens, model.usage_share_metric);
    try std.testing.expectEqual(@as(u64, 0), model.daemon_usage_history_key);
    try std.testing.expectEqual(spawn_count, fx.pendingSpawnCount());

    const token_rows = monthRows(&model, arena);
    try std.testing.expectEqual(@as(usize, 3), token_rows.len);
    try std.testing.expect(token_rows[0].has_share);
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), token_rows[0].share, 0.0001);
    try std.testing.expectEqualStrings("25.0%", token_rows[0].percent);
    try std.testing.expect(token_rows[1].has_share);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), token_rows[1].share, 0.0001);
    try std.testing.expectEqualStrings("100.0%", token_rows[1].percent);
    try std.testing.expect(!token_rows[2].has_share);
    try std.testing.expectEqual(@as(f32, 0), token_rows[2].share);
    try std.testing.expectEqualStrings("", token_rows[2].percent);

    model.usage_view = .daily;
    try std.testing.expectEqual(@as(usize, 0), monthRows(&model, arena).len);
    model.usage_view = .projects;
    try std.testing.expectEqual(@as(usize, 0), monthRows(&model, arena).len);
}

test "monthly zero window keeps shares at 0; empty months paint no rows" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    model.settings_page = .usage;
    model.usage_view = .monthly;
    refresh(&model, &fx);
    const sidecar = pendingSpawnKey(&fx, model.daemon_usage_history_key) orelse return error.MissingZeroMonthlyShareSpawn;
    try expectWindowJson(sidecar.stdin, "\"window\":{\"months\":12}");
    applyLine(&model, .{ .key = sidecar.key, .line = "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000015\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"usageHistory\",\"history\":{\"totalTokens\":0,\"costUsd\":0,\"months\":[{\"firstDay\":\"2026-09-01\",\"totalTokens\":0,\"costUsd\":0,\"sessions\":0}]}}}}" });
    const zero_rows = monthRows(&model, arena);
    try std.testing.expectEqual(@as(usize, 1), zero_rows.len);
    try std.testing.expect(!zero_rows[0].has_share);
    try std.testing.expectEqual(@as(f32, 0), zero_rows[0].share);
    try std.testing.expectEqualStrings("", zero_rows[0].percent);
    try std.testing.expect(!zero_rows[0].has_by_provider);
    try std.testing.expect(hasMonthlyChart(&model));
    try std.testing.expectEqual(@as(usize, 1), monthlyChartValues(&model, arena).len);
    try std.testing.expect(std.math.isNan(monthlyChartClaudeValues(&model, arena)[0]));
    try std.testing.expect(monthlyChartYMax(&model) == null);

    applyLine(&model, .{ .key = sidecar.key, .line = "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000015\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"usageHistory\",\"history\":{\"totalTokens\":100,\"costUsd\":1,\"months\":[]}}}}" });
    try std.testing.expectEqual(@as(usize, 0), monthRows(&model, arena).len);
    try std.testing.expect(!hasMonthlyChart(&model));
    try std.testing.expectEqual(@as(usize, 0), monthlyChartValues(&model, arena).len);
    try std.testing.expectEqual(@as(usize, 0), monthlyChartClaudeValues(&model, arena).len);
    try std.testing.expectEqual(@as(usize, 0), monthlyChartLabels(&model, arena).len);
    try std.testing.expect(monthlyChartYMax(&model) == null);
}

test "monthly byProvider nested shares are within the month; Cost|Tokens chip flip updates without refetch" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    model.settings_page = .usage;
    model.usage_view = .monthly;
    refresh(&model, &fx);
    const sidecar = pendingSpawnKey(&fx, model.daemon_usage_history_key) orelse return error.MissingMonthlyByProviderSpawn;
    const keyed = sidecar.key;
    applyLine(&model, .{ .key = keyed, .line = "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000015\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"usageHistory\",\"history\":{\"totalTokens\":500,\"costUsd\":1.5,\"sessions\":6,\"months\":[{\"firstDay\":\"2026-09-01\",\"totalTokens\":100,\"costUsd\":1.0,\"sessions\":2,\"byProvider\":[{\"costUsd\":0.25,\"totalTokens\":40},{\"costUsd\":0.75,\"totalTokens\":60}]},{\"firstDay\":\"2026-08-01\",\"totalTokens\":400,\"costUsd\":0.5,\"sessions\":4,\"byProvider\":[{\"costUsd\":0.5,\"totalTokens\":400}]},{\"firstDay\":\"2026-07-01\",\"totalTokens\":50,\"costUsd\":0.2,\"sessions\":1,\"byProvider\":[]},{\"firstDay\":\"2026-06-01\",\"totalTokens\":0,\"costUsd\":0,\"sessions\":0,\"byProvider\":[{\"costUsd\":0.1,\"totalTokens\":10}]}]}}}}" });
    handleExit(&model, .{ .key = keyed, .reason = .exited, .code = 0 });
    try std.testing.expectEqual(@as(u64, 0), model.daemon_usage_history_key);
    try std.testing.expectEqual(@as(usize, 4), model.usage_history.month_count);
    try std.testing.expectApproxEqAbs(@as(f64, 0.25), model.usage_history.months[0].by_provider[0].cost_usd, 0.0001);
    try std.testing.expectEqual(@as(u64, 40), model.usage_history.months[0].by_provider[0].total_tokens);
    try std.testing.expectApproxEqAbs(@as(f64, 0.75), model.usage_history.months[0].by_provider[1].cost_usd, 0.0001);
    try std.testing.expectEqual(@as(u64, 400), model.usage_history.months[1].by_provider[0].total_tokens);
    try std.testing.expectEqual(@as(u64, 0), model.usage_history.months[1].by_provider[1].total_tokens);

    const cost_rows = monthRows(&model, arena);
    try std.testing.expectEqual(@as(usize, 4), cost_rows.len);
    try std.testing.expect(cost_rows[0].has_by_provider);
    try std.testing.expectEqualStrings("Claude Code · 40 · $0.25", cost_rows[0].claude_line);
    try std.testing.expect(cost_rows[0].claude_has_share);
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), cost_rows[0].claude_share, 0.0001);
    try std.testing.expectEqualStrings("25.0%", cost_rows[0].claude_percent);
    try std.testing.expectEqualStrings("Codex · 60 · $0.75", cost_rows[0].codex_line);
    try std.testing.expect(cost_rows[0].codex_has_share);
    try std.testing.expectApproxEqAbs(@as(f32, 0.75), cost_rows[0].codex_share, 0.0001);
    try std.testing.expectEqualStrings("75.0%", cost_rows[0].codex_percent);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), cost_rows[0].share, 0.0001);

    try std.testing.expect(cost_rows[1].has_by_provider);
    try std.testing.expectEqualStrings("Claude Code · 400 · $0.50", cost_rows[1].claude_line);
    try std.testing.expect(cost_rows[1].claude_has_share);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), cost_rows[1].claude_share, 0.0001);
    try std.testing.expectEqualStrings("100.0%", cost_rows[1].claude_percent);
    try std.testing.expectEqualStrings("Codex · 0", cost_rows[1].codex_line);
    try std.testing.expect(!cost_rows[1].codex_has_share);
    try std.testing.expectEqual(@as(f32, 0), cost_rows[1].codex_share);
    try std.testing.expectEqualStrings("", cost_rows[1].codex_percent);

    try std.testing.expect(!cost_rows[2].has_by_provider);
    try std.testing.expectEqualStrings("", cost_rows[2].claude_line);
    try std.testing.expect(!cost_rows[3].has_by_provider);
    try std.testing.expect(!cost_rows[3].has_share);

    const spawn_count = fx.pendingSpawnCount();
    setShareMetric(&model, .tokens);
    try std.testing.expectEqual(ShareMetric.tokens, model.usage_share_metric);
    try std.testing.expectEqual(@as(u64, 0), model.daemon_usage_history_key);
    try std.testing.expectEqual(spawn_count, fx.pendingSpawnCount());

    const token_rows = monthRows(&model, arena);
    try std.testing.expectEqual(@as(usize, 4), token_rows.len);
    try std.testing.expect(token_rows[0].has_by_provider);
    try std.testing.expectApproxEqAbs(@as(f32, 0.4), token_rows[0].claude_share, 0.0001);
    try std.testing.expectEqualStrings("40.0%", token_rows[0].claude_percent);
    try std.testing.expectApproxEqAbs(@as(f32, 0.6), token_rows[0].codex_share, 0.0001);
    try std.testing.expectEqualStrings("60.0%", token_rows[0].codex_percent);
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), token_rows[0].share, 0.0001);
    try std.testing.expect(token_rows[1].has_by_provider);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), token_rows[1].claude_share, 0.0001);
    try std.testing.expect(!token_rows[1].codex_has_share);
    try std.testing.expect(!token_rows[2].has_by_provider);
    try std.testing.expect(!token_rows[3].has_by_provider);

    model.usage_view = .daily;
    try std.testing.expectEqual(@as(usize, 0), monthRows(&model, arena).len);
}

test "project shares are relative to the max project; Cost|Tokens chip flip updates without refetch" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    model.settings_page = .usage;
    model.usage_view = .projects;
    try std.testing.expectEqual(ShareMetric.cost, model.usage_share_metric);

    refresh(&model, &fx);
    const sidecar = pendingSpawnKey(&fx, model.daemon_usage_history_key) orelse return error.MissingProjectShareSpawn;
    try expectWindowJson(sidecar.stdin, "\"window\":{\"trailingDays\":30}");
    const keyed = sidecar.key;
    applyLine(&model, .{ .key = keyed, .line = "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000015\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"usageHistory\",\"history\":{\"totalTokens\":500,\"costUsd\":1.5,\"sessions\":6,\"projects\":[{\"path\":\"/tmp/faku\",\"totalTokens\":100,\"costUsd\":1.0,\"sessions\":2},{\"path\":\"/tmp/other\",\"totalTokens\":400,\"costUsd\":0.5,\"sessions\":4},{\"path\":\"/tmp/empty\",\"totalTokens\":0,\"costUsd\":0,\"sessions\":0}]}}}}" });
    handleExit(&model, .{ .key = keyed, .reason = .exited, .code = 0 });
    try std.testing.expectEqual(@as(u64, 0), model.daemon_usage_history_key);
    try std.testing.expectEqual(@as(usize, 3), model.usage_history.project_count);

    const cost_rows = projectRows(&model, arena);
    try std.testing.expectEqual(@as(usize, 3), cost_rows.len);
    try std.testing.expect(cost_rows[0].has_share);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), cost_rows[0].share, 0.0001);
    try std.testing.expectEqualStrings("100.0%", cost_rows[0].percent);
    try std.testing.expect(cost_rows[1].has_share);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), cost_rows[1].share, 0.0001);
    try std.testing.expectEqualStrings("50.0%", cost_rows[1].percent);
    try std.testing.expect(!cost_rows[2].has_share);
    try std.testing.expectEqual(@as(f32, 0), cost_rows[2].share);
    try std.testing.expectEqualStrings("", cost_rows[2].percent);
    try std.testing.expect(!cost_rows[0].has_by_provider);
    try std.testing.expect(!cost_rows[1].has_by_provider);
    try std.testing.expect(!cost_rows[2].has_by_provider);

    const spawn_count = fx.pendingSpawnCount();
    setShareMetric(&model, .tokens);
    try std.testing.expectEqual(ShareMetric.tokens, model.usage_share_metric);
    try std.testing.expectEqual(@as(u64, 0), model.daemon_usage_history_key);
    try std.testing.expectEqual(spawn_count, fx.pendingSpawnCount());

    const token_rows = projectRows(&model, arena);
    try std.testing.expectEqual(@as(usize, 3), token_rows.len);
    try std.testing.expect(token_rows[0].has_share);
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), token_rows[0].share, 0.0001);
    try std.testing.expectEqualStrings("25.0%", token_rows[0].percent);
    try std.testing.expect(token_rows[1].has_share);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), token_rows[1].share, 0.0001);
    try std.testing.expectEqualStrings("100.0%", token_rows[1].percent);
    try std.testing.expect(!token_rows[2].has_share);
    try std.testing.expectEqual(@as(f32, 0), token_rows[2].share);
    try std.testing.expectEqualStrings("", token_rows[2].percent);

    model.usage_view = .daily;
    try std.testing.expectEqual(@as(usize, 0), projectRows(&model, arena).len);
    model.usage_view = .monthly;
    try std.testing.expectEqual(@as(usize, 0), projectRows(&model, arena).len);
}

test "project zero window keeps shares at 0; empty projects paint no rows" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    model.settings_page = .usage;
    model.usage_view = .projects;
    refresh(&model, &fx);
    const sidecar = pendingSpawnKey(&fx, model.daemon_usage_history_key) orelse return error.MissingZeroProjectShareSpawn;
    applyLine(&model, .{ .key = sidecar.key, .line = "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000015\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"usageHistory\",\"history\":{\"totalTokens\":0,\"costUsd\":0,\"projects\":[{\"path\":\"/tmp/faku\",\"totalTokens\":0,\"costUsd\":0,\"sessions\":0}]}}}}" });
    const zero_rows = projectRows(&model, arena);
    try std.testing.expectEqual(@as(usize, 1), zero_rows.len);
    try std.testing.expect(!zero_rows[0].has_share);
    try std.testing.expectEqual(@as(f32, 0), zero_rows[0].share);
    try std.testing.expectEqualStrings("", zero_rows[0].percent);
    try std.testing.expect(!zero_rows[0].has_by_provider);
    try std.testing.expect(hasProjectsChart(&model));
    try std.testing.expectEqual(@as(usize, 1), projectsChartValues(&model, arena).len);
    try std.testing.expect(std.math.isNan(projectsChartClaudeValues(&model, arena)[0]));
    try std.testing.expect(projectsChartYMax(&model) == null);

    applyLine(&model, .{ .key = sidecar.key, .line = "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000015\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"usageHistory\",\"history\":{\"totalTokens\":100,\"costUsd\":1,\"projects\":[]}}}}" });
    try std.testing.expectEqual(@as(usize, 0), projectRows(&model, arena).len);
    try std.testing.expect(!hasProjectsChart(&model));
    try std.testing.expectEqual(@as(usize, 0), projectsChartValues(&model, arena).len);
    try std.testing.expectEqual(@as(usize, 0), projectsChartClaudeValues(&model, arena).len);
    try std.testing.expectEqual(@as(usize, 0), projectsChartLabels(&model, arena).len);
    try std.testing.expect(projectsChartYMax(&model) == null);
}

test "projects chart series is visible-filtered Cost|Tokens; empty/no-match hide chart; provider series NaN-pads; y-max is single-provider peak" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    model.settings_page = .usage;
    model.usage_view = .projects;
    try std.testing.expect(!hasProjectsChart(&model));
    try std.testing.expectEqual(@as(usize, 0), projectsChartValues(&model, arena).len);
    try std.testing.expect(projectsChartYMax(&model) == null);
    try std.testing.expect(!hasProjectsChartYMax(&model));

    refresh(&model, &fx);
    const sidecar = pendingSpawnKey(&fx, model.daemon_usage_history_key) orelse return error.MissingProjectsChartSpawn;
    const keyed = sidecar.key;
    applyLine(&model, .{ .key = keyed, .line = "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000015\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"usageHistory\",\"history\":{\"totalTokens\":500,\"costUsd\":1.5,\"sessions\":6,\"projects\":[{\"path\":\"/tmp/faku\",\"totalTokens\":100,\"costUsd\":1.0,\"sessions\":2,\"byProvider\":[{\"costUsd\":0.25,\"totalTokens\":40},{\"costUsd\":0.75,\"totalTokens\":60}]},{\"path\":\"/tmp/other\",\"totalTokens\":400,\"costUsd\":0.5,\"sessions\":4,\"byProvider\":[]},{\"path\":\"/tmp/empty\",\"totalTokens\":0,\"costUsd\":0,\"sessions\":0}]}}}}" });
    handleExit(&model, .{ .key = keyed, .reason = .exited, .code = 0 });
    try std.testing.expect(hasProjectsChart(&model));
    const cost = projectsChartValues(&model, arena);
    try std.testing.expectEqual(@as(usize, 3), cost.len);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), cost[0], 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), cost[1], 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), cost[2], 0.0001);
    const cost_labels = projectsChartLabels(&model, arena);
    try std.testing.expectEqual(@as(usize, 3), cost_labels.len);
    try std.testing.expectEqualStrings("faku", cost_labels[0]);
    try std.testing.expectEqualStrings("other", cost_labels[1]);
    try std.testing.expectEqualStrings("empty", cost_labels[2]);
    const painted = projectRows(&model, arena);
    try std.testing.expectEqual(@as(usize, 3), painted.len);
    try std.testing.expect(std.mem.indexOf(u8, painted[0].line, "faku") != null);
    try std.testing.expect(std.mem.indexOf(u8, painted[1].line, "other") != null);
    try std.testing.expect(std.mem.indexOf(u8, painted[2].line, "empty") != null);

    const claude_cost = projectsChartClaudeValues(&model, arena);
    const codex_cost = projectsChartCodexValues(&model, arena);
    try std.testing.expectEqual(@as(usize, 3), claude_cost.len);
    try std.testing.expectEqual(@as(usize, 3), codex_cost.len);
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), claude_cost[0], 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.75), codex_cost[0], 0.0001);
    try std.testing.expect(std.math.isNan(claude_cost[1]));
    try std.testing.expect(std.math.isNan(codex_cost[1]));
    try std.testing.expect(std.math.isNan(claude_cost[2]));
    try std.testing.expect(std.math.isNan(codex_cost[2]));
    // Combined project total is 1.0; y-max is Codex 0.75 (layered, not stacked).
    const cost_ymax = projectsChartYMax(&model) orelse return error.MissingCostChartYMax;
    try std.testing.expect(hasProjectsChartYMax(&model));
    try std.testing.expectApproxEqAbs(@as(f32, 0.75), cost_ymax, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.75), projectsChartYMaxValue(&model), 0.0001);

    const saved_claude_cost = model.usage_history.projects[0].by_provider[0].cost_usd;
    const saved_codex_cost = model.usage_history.projects[0].by_provider[1].cost_usd;
    model.usage_history.projects[0].by_provider[0].cost_usd = 0;
    model.usage_history.projects[0].by_provider[1].cost_usd = 0;
    try std.testing.expect(projectsChartYMax(&model) == null);
    try std.testing.expect(!hasProjectsChartYMax(&model));
    try std.testing.expectEqual(@as(f32, 0), projectsChartYMaxValue(&model));
    model.usage_history.projects[0].by_provider[0].cost_usd = saved_claude_cost;
    model.usage_history.projects[0].by_provider[1].cost_usd = saved_codex_cost;
    try std.testing.expectApproxEqAbs(@as(f32, 0.75), projectsChartYMaxValue(&model), 0.0001);

    const spawn_count = fx.pendingSpawnCount();
    setShareMetric(&model, .tokens);
    try std.testing.expectEqual(ShareMetric.tokens, model.usage_share_metric);
    try std.testing.expectEqual(@as(u64, 0), model.daemon_usage_history_key);
    try std.testing.expectEqual(spawn_count, fx.pendingSpawnCount());

    const tokens = projectsChartValues(&model, arena);
    try std.testing.expectEqual(@as(usize, 3), tokens.len);
    try std.testing.expectApproxEqAbs(@as(f32, 100), tokens[0], 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 400), tokens[1], 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), tokens[2], 0.0001);
    const claude_tokens = projectsChartClaudeValues(&model, arena);
    const codex_tokens = projectsChartCodexValues(&model, arena);
    try std.testing.expectApproxEqAbs(@as(f32, 40), claude_tokens[0], 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 60), codex_tokens[0], 0.0001);
    try std.testing.expect(std.math.isNan(claude_tokens[1]));
    try std.testing.expect(std.math.isNan(codex_tokens[1]));
    try std.testing.expect(std.math.isNan(claude_tokens[2]));
    try std.testing.expect(std.math.isNan(codex_tokens[2]));
    // Project totals peak at 400 (empty byProvider); y-max is Codex 60.
    const token_ymax = projectsChartYMax(&model) orelse return error.MissingTokenChartYMax;
    try std.testing.expectApproxEqAbs(@as(f32, 60), token_ymax, 0.0001);

    setShareMetric(&model, .cost);
    applyProjectFilter(&model, .{ .insert_text = "other" });
    try std.testing.expectEqual(spawn_count, fx.pendingSpawnCount());
    try std.testing.expect(hasProjectsChart(&model));
    const filtered = projectsChartValues(&model, arena);
    try std.testing.expectEqual(@as(usize, 1), filtered.len);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), filtered[0], 0.0001);
    const filtered_labels = projectsChartLabels(&model, arena);
    try std.testing.expectEqual(@as(usize, 1), filtered_labels.len);
    try std.testing.expectEqualStrings("other", filtered_labels[0]);
    try std.testing.expect(std.math.isNan(projectsChartClaudeValues(&model, arena)[0]));
    try std.testing.expect(std.math.isNan(projectsChartCodexValues(&model, arena)[0]));
    try std.testing.expect(projectsChartYMax(&model) == null);
    try std.testing.expect(!hasProjectsChartYMax(&model));
    const filtered_rows = projectRows(&model, arena);
    try std.testing.expectEqual(@as(usize, 1), filtered_rows.len);
    try std.testing.expect(std.mem.indexOf(u8, filtered_rows[0].line, "other") != null);

    applyProjectFilter(&model, .clear);
    applyProjectFilter(&model, .{ .insert_text = "faku" });
    try std.testing.expectEqual(spawn_count, fx.pendingSpawnCount());
    const faku_labels = projectsChartLabels(&model, arena);
    try std.testing.expectEqual(@as(usize, 1), faku_labels.len);
    try std.testing.expectEqualStrings("faku", faku_labels[0]);
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), projectsChartClaudeValues(&model, arena)[0], 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.75), projectsChartCodexValues(&model, arena)[0], 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.75), projectsChartYMaxValue(&model), 0.0001);

    applyProjectFilter(&model, .clear);
    applyProjectFilter(&model, .{ .insert_text = "zzzz" });
    try std.testing.expect(projectsNoMatch(&model));
    try std.testing.expect(!hasProjectsChart(&model));
    try std.testing.expectEqual(@as(usize, 0), projectsChartValues(&model, arena).len);
    try std.testing.expectEqual(@as(usize, 0), projectsChartClaudeValues(&model, arena).len);
    try std.testing.expectEqual(@as(usize, 0), projectsChartLabels(&model, arena).len);
    try std.testing.expect(projectsChartYMax(&model) == null);
    try std.testing.expectEqual(@as(f32, 0), projectsChartYMaxValue(&model));

    applyProjectFilter(&model, .clear);
    model.usage_view = .daily;
    try std.testing.expect(!hasProjectsChart(&model));
    try std.testing.expectEqual(@as(usize, 0), projectsChartValues(&model, arena).len);
    try std.testing.expectEqual(@as(usize, 0), projectsChartClaudeValues(&model, arena).len);
    try std.testing.expectEqual(@as(usize, 0), projectsChartLabels(&model, arena).len);
    try std.testing.expect(projectsChartYMax(&model) == null);
    try std.testing.expect(!hasProjectsChartYMax(&model));

    model.usage_view = .monthly;
    try std.testing.expect(!hasProjectsChart(&model));
    try std.testing.expectEqual(@as(usize, 0), projectsChartValues(&model, arena).len);
    try std.testing.expect(projectsChartYMax(&model) == null);

    model.usage_view = .projects;
    model.usage_history.project_count = 0;
    try std.testing.expect(!hasProjectsChart(&model));
    try std.testing.expectEqual(@as(usize, 0), projectsChartValues(&model, arena).len);
    try std.testing.expectEqual(@as(usize, 0), projectsChartLabels(&model, arena).len);
    try std.testing.expect(projectsChartYMax(&model) == null);
    try std.testing.expectEqual(@as(f32, 0), projectsChartYMaxValue(&model));
}

test "project byProvider nested shares are within the project; Cost|Tokens chip flip updates without refetch; filter still peaks-of-visible" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    model.settings_page = .usage;
    model.usage_view = .projects;
    refresh(&model, &fx);
    const sidecar = pendingSpawnKey(&fx, model.daemon_usage_history_key) orelse return error.MissingProjectByProviderSpawn;
    const keyed = sidecar.key;
    applyLine(&model, .{ .key = keyed, .line = "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000015\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"usageHistory\",\"history\":{\"totalTokens\":500,\"costUsd\":1.5,\"sessions\":6,\"projects\":[{\"path\":\"/tmp/faku\",\"totalTokens\":100,\"costUsd\":1.0,\"sessions\":2,\"byProvider\":[{\"costUsd\":0.25,\"totalTokens\":40},{\"costUsd\":0.75,\"totalTokens\":60}]},{\"path\":\"/tmp/other\",\"totalTokens\":400,\"costUsd\":0.5,\"sessions\":4,\"byProvider\":[{\"costUsd\":0.5,\"totalTokens\":400}]},{\"path\":\"/tmp/empty-by\",\"totalTokens\":50,\"costUsd\":0.2,\"sessions\":1,\"byProvider\":[]},{\"path\":\"/tmp/zero\",\"totalTokens\":0,\"costUsd\":0,\"sessions\":0,\"byProvider\":[{\"costUsd\":0.1,\"totalTokens\":10}]}]}}}}" });
    handleExit(&model, .{ .key = keyed, .reason = .exited, .code = 0 });
    try std.testing.expectEqual(@as(u64, 0), model.daemon_usage_history_key);
    try std.testing.expectEqual(@as(usize, 4), model.usage_history.project_count);
    try std.testing.expectApproxEqAbs(@as(f64, 0.25), model.usage_history.projects[0].by_provider[0].cost_usd, 0.0001);
    try std.testing.expectEqual(@as(u64, 40), model.usage_history.projects[0].by_provider[0].total_tokens);
    try std.testing.expectApproxEqAbs(@as(f64, 0.75), model.usage_history.projects[0].by_provider[1].cost_usd, 0.0001);
    try std.testing.expectEqual(@as(u64, 400), model.usage_history.projects[1].by_provider[0].total_tokens);
    try std.testing.expectEqual(@as(u64, 0), model.usage_history.projects[1].by_provider[1].total_tokens);

    const cost_rows = projectRows(&model, arena);
    try std.testing.expectEqual(@as(usize, 4), cost_rows.len);
    try std.testing.expect(cost_rows[0].has_by_provider);
    try std.testing.expectEqualStrings("Claude Code · 40 · $0.25", cost_rows[0].claude_line);
    try std.testing.expect(cost_rows[0].claude_has_share);
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), cost_rows[0].claude_share, 0.0001);
    try std.testing.expectEqualStrings("25.0%", cost_rows[0].claude_percent);
    try std.testing.expectEqualStrings("Codex · 60 · $0.75", cost_rows[0].codex_line);
    try std.testing.expect(cost_rows[0].codex_has_share);
    try std.testing.expectApproxEqAbs(@as(f32, 0.75), cost_rows[0].codex_share, 0.0001);
    try std.testing.expectEqualStrings("75.0%", cost_rows[0].codex_percent);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), cost_rows[0].share, 0.0001);

    try std.testing.expect(cost_rows[1].has_by_provider);
    try std.testing.expectEqualStrings("Claude Code · 400 · $0.50", cost_rows[1].claude_line);
    try std.testing.expect(cost_rows[1].claude_has_share);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), cost_rows[1].claude_share, 0.0001);
    try std.testing.expectEqualStrings("100.0%", cost_rows[1].claude_percent);
    try std.testing.expectEqualStrings("Codex · 0", cost_rows[1].codex_line);
    try std.testing.expect(!cost_rows[1].codex_has_share);
    try std.testing.expectEqual(@as(f32, 0), cost_rows[1].codex_share);
    try std.testing.expectEqualStrings("", cost_rows[1].codex_percent);

    try std.testing.expect(!cost_rows[2].has_by_provider);
    try std.testing.expectEqualStrings("", cost_rows[2].claude_line);
    try std.testing.expect(!cost_rows[3].has_by_provider);
    try std.testing.expect(!cost_rows[3].has_share);

    const spawn_count = fx.pendingSpawnCount();
    setShareMetric(&model, .tokens);
    try std.testing.expectEqual(ShareMetric.tokens, model.usage_share_metric);
    try std.testing.expectEqual(@as(u64, 0), model.daemon_usage_history_key);
    try std.testing.expectEqual(spawn_count, fx.pendingSpawnCount());

    const token_rows = projectRows(&model, arena);
    try std.testing.expectEqual(@as(usize, 4), token_rows.len);
    try std.testing.expect(token_rows[0].has_by_provider);
    try std.testing.expectApproxEqAbs(@as(f32, 0.4), token_rows[0].claude_share, 0.0001);
    try std.testing.expectEqualStrings("40.0%", token_rows[0].claude_percent);
    try std.testing.expectApproxEqAbs(@as(f32, 0.6), token_rows[0].codex_share, 0.0001);
    try std.testing.expectEqualStrings("60.0%", token_rows[0].codex_percent);
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), token_rows[0].share, 0.0001);
    try std.testing.expect(token_rows[1].has_by_provider);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), token_rows[1].claude_share, 0.0001);
    try std.testing.expect(!token_rows[1].codex_has_share);
    try std.testing.expect(!token_rows[2].has_by_provider);
    try std.testing.expect(!token_rows[3].has_by_provider);

    setShareMetric(&model, .cost);
    applyProjectFilter(&model, .{ .insert_text = "other" });
    try std.testing.expectEqual(spawn_count, fx.pendingSpawnCount());
    const filtered = projectRows(&model, arena);
    try std.testing.expectEqual(@as(usize, 1), filtered.len);
    try std.testing.expect(filtered[0].has_share);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), filtered[0].share, 0.0001);
    try std.testing.expectEqualStrings("100.0%", filtered[0].percent);
    try std.testing.expect(filtered[0].has_by_provider);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), filtered[0].claude_share, 0.0001);
    try std.testing.expectEqualStrings("100.0%", filtered[0].claude_percent);
    try std.testing.expect(!filtered[0].codex_has_share);
    try std.testing.expect(std.mem.indexOf(u8, filtered[0].line, "other") != null);
    try std.testing.expect(std.mem.indexOf(u8, filtered[0].line, "faku") == null);

    applyProjectFilter(&model, .clear);
    applyProjectFilter(&model, .{ .insert_text = "faku" });
    const smaller = projectRows(&model, arena);
    try std.testing.expectEqual(@as(usize, 1), smaller.len);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), smaller[0].share, 0.0001);
    try std.testing.expect(smaller[0].has_by_provider);
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), smaller[0].claude_share, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.75), smaller[0].codex_share, 0.0001);
    try std.testing.expect(std.mem.indexOf(u8, smaller[0].line, "faku") != null);
    try std.testing.expectEqual(spawn_count, fx.pendingSpawnCount());

    model.usage_view = .daily;
    try std.testing.expectEqual(@as(usize, 0), projectRows(&model, arena).len);
}

fn seedFilteredProjects(model: *Model) void {
    model.settings_page = .usage;
    model.usage_view = .projects;
    model.usage_share_metric = .cost;
    model.usage_history.present = true;
    model.usage_history.window = .{ .trailing_days = 30 };
    model.usage_history.project_count = 2;
    writeFixed(&model.usage_history.projects[0].path_storage, &model.usage_history.projects[0].path_len, "/tmp/faku");
    model.usage_history.projects[0].total_tokens = 100;
    model.usage_history.projects[0].cost_usd = 1.0;
    model.usage_history.projects[0].sessions = 2;
    writeFixed(&model.usage_history.projects[1].path_storage, &model.usage_history.projects[1].path_len, "/home/me/other");
    model.usage_history.projects[1].total_tokens = 400;
    model.usage_history.projects[1].cost_usd = 0.5;
    model.usage_history.projects[1].sessions = 4;
}

test "project filter matches path and basename; empty query shows all" {
    try std.testing.expect(projectFilterMatches("/tmp/faku", ""));
    try std.testing.expect(projectFilterMatches("/tmp/faku", "  \t"));
    try std.testing.expect(projectFilterMatches("/tmp/faku", "FAKU"));
    try std.testing.expect(projectFilterMatches("/tmp/faku", "faku"));
    try std.testing.expect(projectFilterMatches("/tmp/faku", "tmp"));
    try std.testing.expect(projectFilterMatches("/tmp/faku", "/tmp/faku"));
    try std.testing.expect(!projectFilterMatches("/tmp/faku", "other"));
    try std.testing.expect(projectFilterMatches("/home/me/other", "OTHER"));
    try std.testing.expect(projectFilterMatches("/home/me/other", "me/other"));
    try std.testing.expect(!projectFilterMatches("/home/me/other", "faku"));
}

test "empty project filter paints all rows; no-match is distinct from no project usage" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var model = Model{};
    try std.testing.expectEqualStrings("", projectFilter(&model));
    seedFilteredProjects(&model);

    const all_rows = projectRows(&model, arena);
    try std.testing.expectEqual(@as(usize, 2), all_rows.len);
    try std.testing.expect(!projectsEmpty(&model));
    try std.testing.expect(!projectsNoMatch(&model));

    applyProjectFilter(&model, .{ .insert_text = "  OTHER  " });
    try std.testing.expectEqualStrings("  OTHER  ", model.usage_project_filter_buffer.text());
    try std.testing.expectEqualStrings("OTHER", projectFilter(&model));
    const matched = projectRows(&model, arena);
    try std.testing.expectEqual(@as(usize, 1), matched.len);
    try std.testing.expect(!projectsEmpty(&model));
    try std.testing.expect(!projectsNoMatch(&model));

    applyProjectFilter(&model, .clear);
    applyProjectFilter(&model, .{ .insert_text = "zzzz" });
    try std.testing.expectEqual(@as(usize, 0), projectRows(&model, arena).len);
    try std.testing.expect(!projectsEmpty(&model));
    try std.testing.expect(projectsNoMatch(&model));

    model.usage_history.project_count = 0;
    try std.testing.expectEqual(@as(usize, 0), projectRows(&model, arena).len);
    try std.testing.expect(projectsEmpty(&model));
    try std.testing.expect(!projectsNoMatch(&model));
}

test "project shares rescale to the peak of visible filtered rows; chip flip does not refetch" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    seedFilteredProjects(&model);

    const unfiltered = projectRows(&model, arena);
    try std.testing.expectEqual(@as(usize, 2), unfiltered.len);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), unfiltered[0].share, 0.0001);
    try std.testing.expectEqualStrings("100.0%", unfiltered[0].percent);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), unfiltered[1].share, 0.0001);
    try std.testing.expectEqualStrings("50.0%", unfiltered[1].percent);

    applyProjectFilter(&model, .{ .insert_text = "other" });
    const spawn_count = fx.pendingSpawnCount();
    const filtered = projectRows(&model, arena);
    try std.testing.expectEqual(@as(usize, 1), filtered.len);
    try std.testing.expect(filtered[0].has_share);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), filtered[0].share, 0.0001);
    try std.testing.expectEqualStrings("100.0%", filtered[0].percent);
    try std.testing.expect(std.mem.indexOf(u8, filtered[0].line, "other") != null);
    try std.testing.expectEqual(spawn_count, fx.pendingSpawnCount());

    setShareMetric(&model, .tokens);
    try std.testing.expectEqual(ShareMetric.tokens, model.usage_share_metric);
    try std.testing.expectEqual(spawn_count, fx.pendingSpawnCount());
    const token_filtered = projectRows(&model, arena);
    try std.testing.expectEqual(@as(usize, 1), token_filtered.len);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), token_filtered[0].share, 0.0001);
    try std.testing.expectEqualStrings("100.0%", token_filtered[0].percent);

    applyProjectFilter(&model, .clear);
    applyProjectFilter(&model, .{ .insert_text = "faku" });
    const smaller = projectRows(&model, arena);
    try std.testing.expectEqual(@as(usize, 1), smaller.len);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), smaller[0].share, 0.0001);
    try std.testing.expectEqualStrings("100.0%", smaller[0].percent);
    try std.testing.expect(std.mem.indexOf(u8, smaller[0].line, "faku") != null);
    try std.testing.expectEqual(spawn_count, fx.pendingSpawnCount());
}

test "project filter clears when leaving Projects or Settings Usage" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    seedFilteredProjects(&model);
    applyProjectFilter(&model, .{ .insert_text = "other" });
    try std.testing.expectEqualStrings("other", projectFilter(&model));

    setView(&model, &fx, .daily);
    try std.testing.expectEqual(View.daily, model.usage_view);
    try std.testing.expectEqualStrings("", projectFilter(&model));
    try std.testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());

    model.usage_view = .projects;
    applyProjectFilter(&model, .{ .insert_text = "faku" });
    try std.testing.expectEqualStrings("faku", projectFilter(&model));
    leaveUsage(&model);
    try std.testing.expectEqualStrings("", projectFilter(&model));
    try std.testing.expect(model.usage_history.present);
}

test "quality and pricing adopt from usageHistory; missing fields stay defaults" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    model.settings_page = .usage;
    refresh(&model, &fx);
    const sidecar = pendingSpawnKey(&fx, model.daemon_usage_history_key) orelse return error.MissingQualitySpawn;
    applyLine(&model, .{ .key = sidecar.key, .line = "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000015\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"usageHistory\",\"history\":{\"totalTokens\":100,\"costUsd\":1,\"quality\":{\"providerReportedShare\":0.5,\"modelPricedShare\":0.3,\"unpricedShare\":0.2,\"cacheSavingsUsd\":1.25},\"pricing\":\"unavailable\",\"records\":9,\"scannedFiles\":3,\"skippedFiles\":1,\"errors\":[\"scan failed\"],\"scanDuration\":{\"secs\":1,\"nanos\":0}}}}}" });
    try std.testing.expect(model.usage_history.present);
    try std.testing.expectEqual(protocol.PricingStatus.unavailable, model.usage_history.pricing);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), model.usage_history.quality.provider_reported_share, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.3), model.usage_history.quality.model_priced_share, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.2), model.usage_history.quality.unpriced_share, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 1.25), model.usage_history.quality.cache_savings_usd, 0.0001);
    try std.testing.expectEqual(@as(u64, 9), model.usage_history.records);
    try std.testing.expectEqual(@as(u64, 3), model.usage_history.scanned_files);
    try std.testing.expectEqual(@as(u64, 1), model.usage_history.skipped_files);
    try std.testing.expectEqual(@as(usize, 1), model.usage_history.error_count);
    try std.testing.expectEqualStrings("scan failed", model.usage_history.errors[0].text());
    try std.testing.expect(hasNotice(&model));
    try std.testing.expect(hasQuality(&model));
    try std.testing.expect(hasScanFooter(&model));

    const notices = noticeRows(&model, arena);
    try std.testing.expectEqual(@as(usize, 2), notices.len);
    try std.testing.expectEqualStrings("scan failed", notices[0].line);
    try std.testing.expectEqualStrings(rates_unavailable_notice, notices[1].line);

    const quality = qualityRows(&model, arena);
    try std.testing.expectEqual(@as(usize, 4), quality.len);
    try std.testing.expectEqualStrings("Provider reported", quality[0].line);
    try std.testing.expectEqualStrings("50.0%", quality[0].percent);
    try std.testing.expect(quality[0].has_share);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), quality[0].share, 0.0001);
    try std.testing.expectEqualStrings("Model priced", quality[1].line);
    try std.testing.expectEqualStrings("30.0%", quality[1].percent);
    try std.testing.expectEqualStrings("Unpriced", quality[2].line);
    try std.testing.expectEqualStrings("20.0%", quality[2].percent);
    try std.testing.expectEqualStrings("Cache savings", quality[3].line);
    try std.testing.expectEqualStrings("$1.25", quality[3].percent);
    try std.testing.expect(!quality[3].has_share);
    try std.testing.expectEqualStrings("3 files · 1 skipped · 9 records · 1.0s", scanFooter(&model, arena));

    model.usage_view = .monthly;
    try std.testing.expect(!hasQuality(&model));
    try std.testing.expectEqual(@as(usize, 0), qualityRows(&model, arena).len);
    try std.testing.expect(!hasNotice(&model));
    try std.testing.expectEqual(@as(usize, 0), noticeRows(&model, arena).len);

    applyLine(&model, .{ .key = sidecar.key, .line = "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000015\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"usageHistory\",\"history\":{\"quality\":{},\"pricing\":\"fresh\"}}}}" });
    model.usage_view = .daily;
    try std.testing.expectEqual(protocol.PricingStatus.fresh, model.usage_history.pricing);
    try std.testing.expect(!hasNotice(&model));
    try std.testing.expectEqual(@as(usize, 0), noticeRows(&model, arena).len);
    try std.testing.expectEqual(@as(usize, 0), model.usage_history.error_count);
    const zeros = qualityRows(&model, arena);
    try std.testing.expectEqual(@as(usize, 4), zeros.len);
    try std.testing.expectEqualStrings("0.0%", zeros[0].percent);
    try std.testing.expect(!zeros[0].has_share);
    try std.testing.expectEqualStrings("$0.00", zeros[3].percent);
    try std.testing.expect(!hasScanFooter(&model));
    try std.testing.expectEqualStrings("", scanFooter(&model, arena));

    applyLine(&model, .{ .key = sidecar.key, .line = "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000015\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"usageHistory\",\"history\":{}}}}" });
    try std.testing.expectEqual(protocol.PricingStatus.unknown, model.usage_history.pricing);
    try std.testing.expect(!hasNotice(&model));
    try std.testing.expectApproxEqAbs(@as(f64, 0), model.usage_history.quality.provider_reported_share, 0.0001);

    applyLine(&model, .{ .key = sidecar.key, .line = "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000015\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"usageHistory\",\"history\":{\"pricing\":\"cached\",\"errors\":[\"disk unreadable\"]}}}}" });
    try std.testing.expectEqual(protocol.PricingStatus.cached, model.usage_history.pricing);
    const disk = noticeRows(&model, arena);
    try std.testing.expectEqual(@as(usize, 1), disk.len);
    try std.testing.expectEqualStrings("disk unreadable", disk[0].line);
    try std.testing.expect(std.mem.indexOf(u8, disk[0].line, rates_unavailable_notice) == null);
}

test "metric strip paints five tiles on Daily, Monthly, and Projects; zeros still paint; leaving Usage clears" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    model.settings_page = .usage;
    refresh(&model, &fx);
    const sidecar = pendingSpawnKey(&fx, model.daemon_usage_history_key) orelse return error.MissingMetricStripSpawn;
    applyLine(&model, .{ .key = sidecar.key, .line = "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000015\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"usageHistory\",\"history\":{\"totalTokens\":12300,\"costUsd\":1.25,\"totals\":{\"uncachedInput\":2000,\"cachedInput\":8000,\"cacheCreation\":500,\"output\":1800,\"reasoning\":300,\"unknownTotalsField\":true},\"daily\":[{\"day\":\"2026-09-05\",\"totalTokens\":4100},{\"day\":\"2026-09-06\",\"totalTokens\":8200},{\"day\":\"2026-09-04\",\"totalTokens\":0}],\"quality\":{\"cacheSavingsUsd\":2.5}}}}}" });
    try std.testing.expect(model.usage_history.present);
    try std.testing.expectEqual(@as(u64, 2000), model.usage_history.totals.uncached_input);
    try std.testing.expectEqual(@as(u64, 8000), model.usage_history.totals.cached_input);
    try std.testing.expectEqual(@as(u64, 500), model.usage_history.totals.cache_creation);
    try std.testing.expectEqual(@as(u64, 1800), model.usage_history.totals.output);
    try std.testing.expectEqual(@as(u64, 300), model.usage_history.totals.reasoning);
    try std.testing.expect(hasMetricStrip(&model));

    const rows = metricRows(&model, arena);
    try std.testing.expectEqual(@as(usize, 5), rows.len);
    try std.testing.expectEqualStrings("Processed tokens", rows[0].line);
    try std.testing.expectEqualStrings("12.3k", rows[0].percent);
    try std.testing.expectEqualStrings("6.1k per active day", rows[0].detail);
    try std.testing.expectEqualStrings("Cached input", rows[1].line);
    try std.testing.expectEqualStrings("8k", rows[1].percent);
    try std.testing.expectEqualStrings("80.0% of observed input", rows[1].detail);
    try std.testing.expectEqualStrings("Uncached input", rows[2].line);
    try std.testing.expectEqualStrings("2k", rows[2].percent);
    try std.testing.expectEqualStrings("500 cache writes", rows[2].detail);
    try std.testing.expectEqualStrings("Output", rows[3].line);
    try std.testing.expectEqualStrings("1.8k", rows[3].percent);
    try std.testing.expectEqualStrings("includes 300 reasoning", rows[3].detail);
    try std.testing.expectEqualStrings("Cache savings", rows[4].line);
    try std.testing.expectEqualStrings("$2.50", rows[4].percent);
    try std.testing.expectEqualStrings("2.0x raw cost", rows[4].detail);

    model.usage_view = .projects;
    try std.testing.expect(hasMetricStrip(&model));
    const project_rows = metricRows(&model, arena);
    try std.testing.expectEqual(@as(usize, 5), project_rows.len);
    try std.testing.expectEqualStrings("Processed tokens", project_rows[0].line);
    try std.testing.expectEqualStrings("12.3k", project_rows[0].percent);
    try std.testing.expectEqualStrings("6.1k per active day", project_rows[0].detail);
    try std.testing.expectEqualStrings("8k", project_rows[1].percent);
    try std.testing.expectEqualStrings("80.0% of observed input", project_rows[1].detail);
    try std.testing.expectEqualStrings("$2.50", project_rows[4].percent);

    model.usage_view = .daily;
    applyLine(&model, .{ .key = sidecar.key, .line = "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000015\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"usageHistory\",\"history\":{}}}}" });
    try std.testing.expectEqual(@as(u64, 0), model.usage_history.totals.cached_input);
    const zeros = metricRows(&model, arena);
    try std.testing.expectEqual(@as(usize, 5), zeros.len);
    try std.testing.expectEqualStrings("0", zeros[0].percent);
    try std.testing.expectEqualStrings("0 per active day", zeros[0].detail);
    try std.testing.expectEqualStrings("0", zeros[1].percent);
    try std.testing.expectEqualStrings("0.0% of observed input", zeros[1].detail);
    try std.testing.expectEqualStrings("0 cache writes", zeros[2].detail);
    try std.testing.expectEqualStrings("includes 0 reasoning", zeros[3].detail);
    try std.testing.expectEqualStrings("$0.00", zeros[4].percent);
    try std.testing.expectEqualStrings("vs full input rates", zeros[4].detail);

    model.usage_view = .monthly;
    try std.testing.expect(!hasMetricStrip(&model));
    try std.testing.expectEqual(@as(usize, 0), metricRows(&model, arena).len);
    try std.testing.expect(!hasQuality(&model));

    refresh(&model, &fx);
    const monthly_sidecar = pendingSpawnKey(&fx, model.daemon_usage_history_key) orelse return error.MissingMonthlyMetricStripSpawn;
    applyLine(&model, .{ .key = monthly_sidecar.key, .line = "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000015\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"usageHistory\",\"history\":{\"totalTokens\":12300,\"costUsd\":1.25,\"totals\":{\"uncachedInput\":2000,\"cachedInput\":8000,\"cacheCreation\":500,\"output\":1800,\"reasoning\":300},\"months\":[{\"firstDay\":\"2026-08-01\",\"totalTokens\":4100},{\"firstDay\":\"2026-09-01\",\"totalTokens\":8200},{\"firstDay\":\"2026-07-01\",\"totalTokens\":0}],\"quality\":{\"cacheSavingsUsd\":2.5}}}}}" });
    try std.testing.expect(std.meta.eql(model.usage_history.window, monthly_window));
    try std.testing.expect(hasMetricStrip(&model));
    try std.testing.expect(!hasQuality(&model));
    const month_rows = metricRows(&model, arena);
    try std.testing.expectEqual(@as(usize, 5), month_rows.len);
    try std.testing.expectEqualStrings("Processed tokens", month_rows[0].line);
    try std.testing.expectEqualStrings("12.3k", month_rows[0].percent);
    try std.testing.expectEqualStrings("6.1k per active month", month_rows[0].detail);
    try std.testing.expectEqualStrings("Cached input", month_rows[1].line);
    try std.testing.expectEqualStrings("8k", month_rows[1].percent);
    try std.testing.expectEqualStrings("80.0% of observed input", month_rows[1].detail);
    try std.testing.expectEqualStrings("Uncached input", month_rows[2].line);
    try std.testing.expectEqualStrings("2k", month_rows[2].percent);
    try std.testing.expectEqualStrings("500 cache writes", month_rows[2].detail);
    try std.testing.expectEqualStrings("Output", month_rows[3].line);
    try std.testing.expectEqualStrings("1.8k", month_rows[3].percent);
    try std.testing.expectEqualStrings("includes 300 reasoning", month_rows[3].detail);
    try std.testing.expectEqualStrings("Cache savings", month_rows[4].line);
    try std.testing.expectEqualStrings("$2.50", month_rows[4].percent);
    try std.testing.expectEqualStrings("2.0x raw cost", month_rows[4].detail);

    applyLine(&model, .{ .key = monthly_sidecar.key, .line = "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000015\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"usageHistory\",\"history\":{}}}}" });
    try std.testing.expectEqual(@as(u64, 0), model.usage_history.totals.cached_input);
    const month_zeros = metricRows(&model, arena);
    try std.testing.expectEqual(@as(usize, 5), month_zeros.len);
    try std.testing.expectEqualStrings("0", month_zeros[0].percent);
    try std.testing.expectEqualStrings("0 per active month", month_zeros[0].detail);
    try std.testing.expectEqualStrings("0", month_zeros[1].percent);
    try std.testing.expectEqualStrings("0.0% of observed input", month_zeros[1].detail);
    try std.testing.expectEqualStrings("0 cache writes", month_zeros[2].detail);
    try std.testing.expectEqualStrings("includes 0 reasoning", month_zeros[3].detail);
    try std.testing.expectEqualStrings("$0.00", month_zeros[4].percent);
    try std.testing.expectEqualStrings("vs full input rates", month_zeros[4].detail);

    model.usage_view = .daily;
    try std.testing.expect(!hasMetricStrip(&model));
    try std.testing.expectEqual(@as(usize, 0), metricRows(&model, arena).len);

    model.usage_view = .monthly;
    model.settings_page = .general;
    try std.testing.expect(!hasMetricStrip(&model));
    try std.testing.expectEqual(@as(usize, 0), metricRows(&model, arena).len);

    model.settings_page = .usage;
    try std.testing.expect(hasMetricStrip(&model));
    model.usage_history.present = false;
    try std.testing.expect(!hasMetricStrip(&model));
    try std.testing.expectEqual(@as(usize, 0), metricRows(&model, arena).len);
}


