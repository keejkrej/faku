//! Non-fx CLI `--help` probes (boot + Settings Providers).
//!
//! Each non-fx `protocol.ProviderId` one-shots `{probeBinary()} --help`
//! (`providerBinaryOverride` when set, else PATH `defaultBinary()`; no
//! `~/.local/bin/<binary>` fallback this cut). Empty override is PATH
//! detect. Empty probe binary fail-closes (marks Not found, no spawn).
//! fx stays on
//! `fx_probe.zig` (`$HOME/.fx/bin/fx`, leftover `~/.local/bin/fx`, then
//! PATH) and is never spawned here. Boot (`initFx`) starts these
//! alongside the fx probe so `providerEnabled` can AND probe-installed
//! without starving plan-usage `maybeRefresh` until Settings opens.
//! Settings → Providers open calls `startCliProbes` (no-op when already
//! started). Same Native collect+on_exit pattern as `fx_probe`. Fake
//! executor queues the spawn; tests do not need a live CLI or daemon.
//!
//! Spawn key is `cli_probe_key_first + @intFromEnum(id)` so claude=601
//! … kimi=608. fx (enum 0) is unused on this band. Distinct from
//! fx_probe_key (3), fx_ask_key (2), daemon (4+), fx_spawn (64+),
//! skills scan (530+) / rename (580+). Refresh cancels the same fixed
//! key per id. Handled `--help` exits stamp
//! `provider_detection_checked_at_ms` (`now_ms`; last exit wins).
//! Cancelled exits do not stamp.

const std = @import("std");
const native_sdk = @import("native_sdk");
const main = @import("main.zig");
const fx_probe = @import("fx_probe.zig");
const model_exports = @import("model_exports.zig");
const effect_keys = @import("effect_keys.zig");
const protocol = @import("protocol.zig");

const Model = model_exports.Model;
const Effects = main.Effects;

/// Fixed key per ProviderId. Distinct from fx_probe_key (3).
/// Skills scan is 530+ incrementing; skills rename is 580+; this band
/// is one fixed key per ProviderId tag (fx's slot unused).
pub const cli_probe_key_first: u64 = 600;

pub const help_flag = "--help";

pub fn probeKey(id: protocol.ProviderId) u64 {
    return cli_probe_key_first + @intFromEnum(id);
}

pub fn fromProbeKey(key: u64) ?protocol.ProviderId {
    if (key < cli_probe_key_first) return null;
    const index = key - cli_probe_key_first;
    const tags = std.meta.tags(protocol.ProviderId);
    if (index >= tags.len) return null;
    const id = tags[index];
    if (id == .fx) return null;
    return id;
}

pub fn nonFxCount() usize {
    return protocol.provider_id_count - 1;
}

pub fn isCliProbeArgv(argv: []const []const u8, id: protocol.ProviderId) bool {
    return isCliProbeArgvWith(argv, id, id.defaultBinary());
}

pub fn isCliProbeArgvWith(argv: []const []const u8, id: protocol.ProviderId, binary: []const u8) bool {
    if (id == .fx) return false;
    if (argv.len != 2) return false;
    if (!std.mem.eql(u8, argv[1], help_flag)) return false;
    if (binary.len == 0) return false;
    return std.mem.eql(u8, argv[0], binary);
}

pub fn probeBinary(model: *const Model, id: protocol.ProviderId) []const u8 {
    if (id == .fx) return "";
    const override = model.providerBinaryOverride(id);
    if (override.len > 0) return override;
    return id.defaultBinary();
}

pub fn isAnyCliProbeArgv(argv: []const []const u8) bool {
    for (std.meta.tags(protocol.ProviderId)) |id| {
        if (isCliProbeArgv(argv, id)) return true;
    }
    return false;
}

/// Boot (`initFx`) and Settings → Providers open. Skip ids already
/// started (open is a no-op after boot). Does not touch fx /
/// `fx_probe_key`.
pub fn startCliProbes(model: *Model, fx: *Effects) void {
    for (std.meta.tags(protocol.ProviderId)) |id| {
        if (id == .fx) continue;
        const index = @intFromEnum(id);
        if (model.cli_probe_started[index]) continue;
        startOneCliProbe(model, fx, id);
    }
}

fn startOneCliProbe(model: *Model, fx: *Effects, id: protocol.ProviderId) void {
    if (id == .fx) return;
    const index = @intFromEnum(id);
    model.cli_probe_started[index] = true;
    const binary = probeBinary(model, id);
    if (binary.len == 0) {
        model.cli_available[index] = false;
        return;
    }
    fx.spawn(.{
        .key = probeKey(id),
        .argv = &.{ binary, help_flag },
        .output = .collect,
        .on_exit = Effects.exitMsg(.cli_probe_exit),
    });
}

/// Re-run one non-fx `--help` probe (Settings override apply / Reset).
/// Cancel in-flight first. Does not reset availability until the new
/// exit lands — same as `restartCliProbes`.
pub fn restartCliProbe(model: *Model, fx: *Effects, id: protocol.ProviderId) void {
    if (id == .fx) return;
    fx.cancel(probeKey(id));
    model.cli_probe_started[@intFromEnum(id)] = false;
    startOneCliProbe(model, fx, id);
}

/// Settings → Providers Refresh. Cancel in-flight `--help` probes
/// (same fixed keys) and start again. Does not reset availability
/// until the new exit lands — same as `restartFxProbe`.
pub fn restartCliProbes(model: *Model, fx: *Effects) void {
    for (std.meta.tags(protocol.ProviderId)) |id| {
        if (id == .fx) continue;
        fx.cancel(probeKey(id));
        model.cli_probe_started[@intFromEnum(id)] = false;
    }
    startCliProbes(model, fx);
}

pub fn handleCliProbeExit(model: *Model, exit: native_sdk.EffectExit) void {
    const id = fromProbeKey(exit.key) orelse return;
    const index = @intFromEnum(id);
    // Cancel (Providers Refresh) must not paint a cancelled spawn.
    if (exit.reason != .exited) return;
    model.provider_detection_checked_at_ms = model.now_ms;
    model.cli_available[index] = exit.code == 0;
}

test "probeKey is per-id and skips fx_probe_key / ask / daemon" {
    try std.testing.expectEqual(@as(u64, 601), probeKey(.claude));
    try std.testing.expectEqual(@as(u64, 602), probeKey(.codex));
    try std.testing.expectEqual(@as(u64, 603), probeKey(.amp));
    try std.testing.expectEqual(@as(u64, 604), probeKey(.grok));
    try std.testing.expectEqual(@as(u64, 605), probeKey(.opencode));
    try std.testing.expectEqual(@as(u64, 606), probeKey(.cursor));
    try std.testing.expectEqual(@as(u64, 607), probeKey(.pi));
    try std.testing.expectEqual(@as(u64, 608), probeKey(.kimi));
    try std.testing.expect(probeKey(.claude) != fx_probe.fx_probe_key);
    try std.testing.expect(probeKey(.claude) != effect_keys.fx_ask_key);
    try std.testing.expect(probeKey(.claude) != effect_keys.daemon_proxy_key_first);
    try std.testing.expect(probeKey(.pi) != fx_probe.fx_probe_key);
    try std.testing.expect(probeKey(.kimi) != fx_probe.fx_probe_key);
    try std.testing.expectEqual(protocol.ProviderId.claude, fromProbeKey(601).?);
    try std.testing.expectEqual(protocol.ProviderId.pi, fromProbeKey(607).?);
    try std.testing.expectEqual(protocol.ProviderId.kimi, fromProbeKey(608).?);
    try std.testing.expect(fromProbeKey(fx_probe.fx_probe_key) == null);
    try std.testing.expect(fromProbeKey(cli_probe_key_first) == null);
    try std.testing.expect(fromProbeKey(609) == null);
    try std.testing.expectEqual(@as(usize, 8), nonFxCount());
}

test "isCliProbeArgv matches PATH defaultBinary --help only" {
    try std.testing.expect(isCliProbeArgv(&.{ "claude", "--help" }, .claude));
    try std.testing.expect(isCliProbeArgv(&.{ "cursor-agent", "--help" }, .cursor));
    try std.testing.expect(isCliProbeArgv(&.{ "kimi", "--help" }, .kimi));
    try std.testing.expect(!isCliProbeArgv(&.{ "fx", "--help" }, .fx));
    try std.testing.expect(!isCliProbeArgv(&.{ "claude", "--help" }, .codex));
    try std.testing.expect(!isCliProbeArgv(&.{ "claude", "acp" }, .claude));
    try std.testing.expect(!isCliProbeArgv(&.{"claude"}, .claude));
    try std.testing.expect(!isAnyCliProbeArgv(&.{ "fx", "--help" }));
    try std.testing.expect(isAnyCliProbeArgv(&.{ "pi", "--help" }));
    try std.testing.expect(isCliProbeArgvWith(&.{ "/opt/claude", "--help" }, .claude, "/opt/claude"));
    try std.testing.expect(!isCliProbeArgvWith(&.{ "/opt/claude", "--help" }, .claude, "claude"));
    try std.testing.expect(!isCliProbeArgvWith(&.{ "/opt/claude", "--help" }, .fx, "/opt/claude"));
}

test "startCliProbes queues PATH --help per non-fx id; skips fx; second start is a no-op" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    startCliProbes(&model, &fx);
    try testing.expectEqual(nonFxCount(), countPendingCliProbes(&fx));
    try testing.expect(findPending(&fx, fx_probe.fx_probe_key) == null);

    for (std.meta.tags(protocol.ProviderId)) |id| {
        if (id == .fx) {
            try testing.expect(!model.cli_probe_started[0]);
            continue;
        }
        try testing.expect(model.cli_probe_started[@intFromEnum(id)]);
        const spawn = findPending(&fx, probeKey(id)) orelse return error.MissingCliProbe;
        try testing.expect(isCliProbeArgv(spawn.argv, id));
        try testing.expectEqualStrings(id.defaultBinary(), spawn.argv[0]);
        try testing.expectEqualStrings(help_flag, spawn.argv[1]);
    }

    const after_first = fx.pendingSpawnCount();
    startCliProbes(&model, &fx);
    try testing.expectEqual(after_first, fx.pendingSpawnCount());
}

test "success exit is Available; non-zero and missing are Not found; cancel is ignored" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.now_ms = 42_000;
    startCliProbes(&model, &fx);

    handleCliProbeExit(&model, .{ .key = probeKey(.claude), .reason = .exited, .code = 0 });
    try testing.expect(model.cli_available[@intFromEnum(protocol.ProviderId.claude)]);
    try testing.expectEqual(@as(i64, 42_000), model.provider_detection_checked_at_ms);

    handleCliProbeExit(&model, .{ .key = probeKey(.codex), .reason = .exited, .code = 1 });
    try testing.expect(!model.cli_available[@intFromEnum(protocol.ProviderId.codex)]);
    try testing.expectEqual(@as(i64, 42_000), model.provider_detection_checked_at_ms);

    handleCliProbeExit(&model, .{ .key = probeKey(.amp), .reason = .exited, .code = 127 });
    try testing.expect(!model.cli_available[@intFromEnum(protocol.ProviderId.amp)]);
    try testing.expectEqual(@as(i64, 42_000), model.provider_detection_checked_at_ms);

    model.cli_available[@intFromEnum(protocol.ProviderId.grok)] = true;
    model.provider_detection_checked_at_ms = 42_000;
    handleCliProbeExit(&model, .{ .key = probeKey(.grok), .reason = .rejected, .code = 0 });
    try testing.expect(model.cli_available[@intFromEnum(protocol.ProviderId.grok)]);
    try testing.expectEqual(@as(i64, 42_000), model.provider_detection_checked_at_ms);

    handleCliProbeExit(&model, .{ .key = fx_probe.fx_probe_key, .reason = .exited, .code = 0 });
    try testing.expect(!model.cli_available[0]);
    try testing.expectEqual(@as(i64, 42_000), model.provider_detection_checked_at_ms);
}

test "restartCliProbes requeues every non-fx probe and leaves fx_probe_key unused" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.cli_probe_started[@intFromEnum(protocol.ProviderId.claude)] = true;
    model.cli_available[@intFromEnum(protocol.ProviderId.claude)] = true;
    restartCliProbes(&model, &fx);
    try testing.expectEqual(nonFxCount(), countPendingCliProbes(&fx));
    try testing.expect(findPending(&fx, fx_probe.fx_probe_key) == null);
    try testing.expect(model.cli_probe_started[@intFromEnum(protocol.ProviderId.claude)]);
    const claude = findPending(&fx, probeKey(.claude)).?;
    try testing.expect(isCliProbeArgv(claude.argv, .claude));
}

test "startCliProbes argv[0] uses persisted override; empty override stays defaultBinary" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setProviderBinaryOverride(.claude, "/opt/custom-claude");
    startCliProbes(&model, &fx);
    const claude = findPending(&fx, probeKey(.claude)) orelse return error.MissingCliProbe;
    try testing.expect(isCliProbeArgvWith(claude.argv, .claude, "/opt/custom-claude"));
    try testing.expectEqualStrings("/opt/custom-claude", claude.argv[0]);
    try testing.expectEqualStrings(help_flag, claude.argv[1]);
    try testing.expect(!isCliProbeArgv(claude.argv, .claude));
    const codex = findPending(&fx, probeKey(.codex)) orelse return error.MissingCliProbe;
    try testing.expect(isCliProbeArgv(codex.argv, .codex));
    try testing.expectEqualStrings("codex", codex.argv[0]);

    fx.cancel(probeKey(.claude));
    model.cli_probe_started[@intFromEnum(protocol.ProviderId.claude)] = false;
    model.setProviderBinaryOverride(.claude, "");
    startOneCliProbe(&model, &fx, .claude);
    const cleared = findPending(&fx, probeKey(.claude)) orelse return error.MissingClearedCliProbe;
    try testing.expect(isCliProbeArgv(cleared.argv, .claude));
    try testing.expectEqualStrings("claude", cleared.argv[0]);
}

fn findPending(fx: *Effects, key: u64) ?@TypeOf(fx.pendingSpawnAt(0).?) {
    var i: usize = 0;
    while (fx.pendingSpawnAt(i)) |item| : (i += 1) {
        if (item.key == key) return item;
    }
    return null;
}

fn countPendingCliProbes(fx: *Effects) usize {
    var n: usize = 0;
    var i: usize = 0;
    while (fx.pendingSpawnAt(i)) |item| : (i += 1) {
        if (fromProbeKey(item.key) != null) n += 1;
    }
    return n;
}
