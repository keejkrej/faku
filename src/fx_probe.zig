//! Boot fx-probe spawn/exit helpers.
//!
//! `startFxProbe` / `restartFxProbe` / `spawnFxProbe` /
//! `handleFxProbeExit` / `fxProbePath` live here. Boot still starts
//! from `initFx` in `update.zig`. Probe order is `$HOME/.fx/bin/fx`
//! `--help` (keejkrej/fx default), leftover `~/.local/bin/fx --help`
//! (not advertised), then `fx --help` (PATH). Settings → Providers
//! Refresh calls `restartFxProbe`.

const std = @import("std");
const native_sdk = @import("native_sdk");
const main = @import("main.zig");

const Model = main.Model;
const Effects = main.Effects;
const max_fx_path = main.max_fx_path;

/// Distinct from fx ask / daemon / maximize / picker keys.
pub const fx_probe_key: u64 = 3;

pub fn startFxProbe(model: *Model, fx: *Effects) void {
    if (model.fx_probe_started) return;
    model.fx_probe_started = true;
    model.fx_probe_index = 0;
    spawnFxProbe(model, fx);
}

/// Settings → Providers Refresh. Cancel any in-flight `--help` probe
/// (same fixed key) and start from index 0. Fake executor queues the
/// spawn; tests do not need a live fx binary.
pub fn restartFxProbe(model: *Model, fx: *Effects) void {
    fx.cancel(fx_probe_key);
    model.fx_probe_started = false;
    startFxProbe(model, fx);
}

pub fn isFxProbeArgv(argv: []const []const u8) bool {
    if (argv.len != 2) return false;
    if (!std.mem.eql(u8, argv[1], "--help")) return false;
    const bin = argv[0];
    return std.mem.eql(u8, bin, "fx") or std.mem.endsWith(u8, bin, "/fx");
}

/// Must match `protocol.FX_PROBE_PATHS` length: ~/.fx/bin/fx,
/// leftover ~/.local/bin/fx, PATH fx.
const probe_path_count: u32 = 3;

fn spawnFxProbe(model: *Model, fx: *Effects) void {
    while (model.fx_probe_index < probe_path_count) {
        var path_buf: [max_fx_path]u8 = undefined;
        if (fxProbePath(model, model.fx_probe_index, &path_buf)) |path| {
            model.setFxPath(path);
            fx.spawn(.{
                .key = fx_probe_key,
                .argv = &.{ model.fxPath(), "--help" },
                .output = .collect,
                .on_exit = Effects.exitMsg(.fx_probe_exit),
            });
            return;
        }
        model.fx_probe_index += 1;
    }
    model.fx_available = false;
    model.fx_path_len = 0;
}

pub fn handleFxProbeExit(model: *Model, fx: *Effects, exit: native_sdk.EffectExit) void {
    if (exit.key != fx_probe_key) return;
    // Cancel (Providers Refresh) must not chain to the PATH probe.
    if (exit.reason != .exited) return;
    if (exit.code == 0) {
        model.fx_available = true;
        return;
    }
    model.fx_available = false;
    model.fx_path_len = 0;
    model.fx_probe_index += 1;
    spawnFxProbe(model, fx);
}

fn joinHomeSuffix(home: []const u8, suffix: []const u8, buf: *[max_fx_path]u8) ?[]const u8 {
    if (home.len == 0) return null;
    if (home.len + suffix.len > buf.len) return null;
    @memcpy(buf[0..home.len], home);
    @memcpy(buf[home.len..][0..suffix.len], suffix);
    return buf[0 .. home.len + suffix.len];
}

pub fn fxProbePath(model: *const Model, index: u32, buf: *[max_fx_path]u8) ?[]const u8 {
    switch (index) {
        0 => return joinHomeSuffix(model.homeDir(), "/.fx/bin/fx", buf),
        1 => return joinHomeSuffix(model.homeDir(), "/.local/bin/fx", buf),
        2 => {
            const name = "fx";
            @memcpy(buf[0..name.len], name);
            return buf[0..name.len];
        },
        else => return null,
    }
}

test "fxProbePath prefers ~/.fx/bin/fx, then leftover ~/.local/bin/fx, then PATH fx" {
    var model = Model{};
    model.setHome("/home/probe");
    var buf: [max_fx_path]u8 = undefined;
    try std.testing.expectEqualStrings("/home/probe/.fx/bin/fx", fxProbePath(&model, 0, &buf).?);
    try std.testing.expectEqualStrings("/home/probe/.local/bin/fx", fxProbePath(&model, 1, &buf).?);
    try std.testing.expectEqualStrings("fx", fxProbePath(&model, 2, &buf).?);
    try std.testing.expect(fxProbePath(&model, 3, &buf) == null);
}

test "fxProbePath home slots are null when home is empty; PATH fx remains" {
    const model = Model{};
    var buf: [max_fx_path]u8 = undefined;
    try std.testing.expect(fxProbePath(&model, 0, &buf) == null);
    try std.testing.expect(fxProbePath(&model, 1, &buf) == null);
    try std.testing.expectEqualStrings("fx", fxProbePath(&model, 2, &buf).?);
}

test "isFxProbeArgv matches --help on fx path" {
    try std.testing.expect(isFxProbeArgv(&.{ "fx", "--help" }));
    try std.testing.expect(isFxProbeArgv(&.{ "/home/probe/.fx/bin/fx", "--help" }));
    try std.testing.expect(isFxProbeArgv(&.{ "/home/probe/.local/bin/fx", "--help" }));
    try std.testing.expect(!isFxProbeArgv(&.{ "fx", "acp" }));
    try std.testing.expect(!isFxProbeArgv(&.{"fx"}));
}

test "restartFxProbe resets started and queues --help" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.fx_probe_started = true;
    model.fx_available = true;
    model.setFxPath("/tmp/already-probed");
    restartFxProbe(&model, &fx);
    try testing.expect(model.fx_probe_started);
    const spawn = fx.pendingSpawnAt(0).?;
    try testing.expectEqual(fx_probe_key, spawn.key);
    try testing.expect(isFxProbeArgv(spawn.argv));
}
