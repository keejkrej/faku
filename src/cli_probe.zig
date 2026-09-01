//! Settings Providers: non-fx CLI `--help` probes.
//!
//! Each non-fx `protocol.ProviderId` one-shots `{defaultBinary()} --help`
//! on PATH (no `~/.local/bin/<binary>` fallback this cut). fx stays on
//! `fx_probe.zig` (`~/.local/bin/fx` then PATH) and is never spawned
//! here. Same Native collect+on_exit pattern as `fx_probe`. Fake
//! executor queues the spawn; tests do not need a live CLI or daemon.
//!
//! Spawn key is `cli_probe_key_first + @intFromEnum(id)` so claude=601
//! … kimi=608. fx (enum 0) is unused on this band. Distinct from
//! fx_probe_key (3), fx_ask_key (2), daemon (4+), fx_spawn (64+),
//! skills (530+). Refresh cancels the same fixed key per id.

const std = @import("std");
const native_sdk = @import("native_sdk");
const main = @import("main.zig");
const protocol = @import("protocol.zig");

const Model = main.Model;
const Effects = main.Effects;

/// Fixed key per ProviderId. Distinct from fx_probe_key (3).
/// Skills scan is 530+ incrementing; this band is one fixed key per
/// ProviderId tag (fx's slot unused).
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
    if (id == .fx) return false;
    if (argv.len != 2) return false;
    if (!std.mem.eql(u8, argv[1], help_flag)) return false;
    return std.mem.eql(u8, argv[0], id.defaultBinary());
}

pub fn isAnyCliProbeArgv(argv: []const []const u8) bool {
    for (std.meta.tags(protocol.ProviderId)) |id| {
        if (isCliProbeArgv(argv, id)) return true;
    }
    return false;
}

/// Settings → Providers open. Skip ids already started. Does not
/// touch fx / `fx_probe_key`.
pub fn startCliProbes(model: *Model, fx: *Effects) void {
    for (std.meta.tags(protocol.ProviderId)) |id| {
        if (id == .fx) continue;
        const index = @intFromEnum(id);
        if (model.cli_probe_started[index]) continue;
        model.cli_probe_started[index] = true;
        fx.spawn(.{
            .key = probeKey(id),
            .argv = &.{ id.defaultBinary(), help_flag },
            .output = .collect,
            .on_exit = Effects.exitMsg(.cli_probe_exit),
        });
    }
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
    try std.testing.expect(probeKey(.claude) != main.fx_probe_key);
    try std.testing.expect(probeKey(.claude) != main.fx_ask_key);
    try std.testing.expect(probeKey(.claude) != main.daemon_proxy_key_first);
    try std.testing.expect(probeKey(.pi) != main.fx_probe_key);
    try std.testing.expect(probeKey(.kimi) != main.fx_probe_key);
    try std.testing.expectEqual(protocol.ProviderId.claude, fromProbeKey(601).?);
    try std.testing.expectEqual(protocol.ProviderId.pi, fromProbeKey(607).?);
    try std.testing.expectEqual(protocol.ProviderId.kimi, fromProbeKey(608).?);
    try std.testing.expect(fromProbeKey(main.fx_probe_key) == null);
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
}

test "startCliProbes queues PATH --help per non-fx id; skips fx; second start is a no-op" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    startCliProbes(&model, &fx);
    try testing.expectEqual(nonFxCount(), countPendingCliProbes(&fx));
    try testing.expect(findPending(&fx, main.fx_probe_key) == null);

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
    startCliProbes(&model, &fx);

    handleCliProbeExit(&model, .{ .key = probeKey(.claude), .reason = .exited, .code = 0 });
    try testing.expect(model.cli_available[@intFromEnum(protocol.ProviderId.claude)]);

    handleCliProbeExit(&model, .{ .key = probeKey(.codex), .reason = .exited, .code = 1 });
    try testing.expect(!model.cli_available[@intFromEnum(protocol.ProviderId.codex)]);

    handleCliProbeExit(&model, .{ .key = probeKey(.amp), .reason = .exited, .code = 127 });
    try testing.expect(!model.cli_available[@intFromEnum(protocol.ProviderId.amp)]);

    model.cli_available[@intFromEnum(protocol.ProviderId.grok)] = true;
    handleCliProbeExit(&model, .{ .key = probeKey(.grok), .reason = .rejected, .code = 0 });
    try testing.expect(model.cli_available[@intFromEnum(protocol.ProviderId.grok)]);

    handleCliProbeExit(&model, .{ .key = main.fx_probe_key, .reason = .exited, .code = 0 });
    try testing.expect(!model.cli_available[0]);
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
    try testing.expect(findPending(&fx, main.fx_probe_key) == null);
    try testing.expect(model.cli_probe_started[@intFromEnum(protocol.ProviderId.claude)]);
    const claude = findPending(&fx, probeKey(.claude)).?;
    try testing.expect(isCliProbeArgv(claude.argv, .claude));
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
