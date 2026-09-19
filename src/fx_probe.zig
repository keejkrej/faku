//! Boot fx-probe spawn/exit helpers.
//!
//! `startFxProbe` / `restartFxProbe` / `spawnFxProbe` /
//! `handleFxProbeExit` / `fxProbePath` live here. Callers import this
//! module directly (`fx_probe.fx_probe_key` / `fx_probe.startFxProbe`).
//! Not re-exported from `main`. Boot still starts from `initFx` in
//! `update.zig`. Probe order is `$HOME/.fx/bin/fx`
//! `--help` (keejkrej/fx default), leftover `~/.local/bin/fx --help`
//! (not advertised), then `fx --help` (PATH). Settings → Providers
//! Refresh calls `restartFxProbe`. Handled `--help` exits stamp
//! `provider_detection_checked_at_ms` (`now_ms`; last exit wins).
//! Cancelled exits do not stamp.

const std = @import("std");
const native_sdk = @import("native_sdk");
const main = @import("main.zig");
const model_exports = @import("model_exports.zig");

const Model = model_exports.Model;
const Effects = main.Effects;
const max_fx_path = model_exports.max_fx_path;
const cli_version = @import("cli_version.zig");

/// Distinct from fx ask / daemon / maximize / picker keys.
pub const fx_probe_key: u64 = 3;

pub fn startFxProbe(model: *Model, fx: *Effects) void {
    if (model.fx_probe_started) return;
    model.fx_probe_started = true;
    model.fx_probe_index = 0;
    spawnFxProbe(model, fx);
}

/// Settings → Providers Refresh. Cancel any in-flight `--help` probe
/// (same fixed key) and start from index 0. Also cancel the fx
/// `--version` probe and clear its stored token so Refresh re-probes
/// version only after the new `--help` marks Available. Fake executor
/// queues the spawn; tests do not need a live fx binary.
pub fn restartFxProbe(model: *Model, fx: *Effects) void {
    cli_version.cancelVersionProbe(model, fx, .fx);
    fx.cancel(fx_probe_key);
    model.fx_probe_started = false;
    startFxProbe(model, fx);
}

pub fn isFxProbeArgv(argv: []const []const u8) bool {
    if (argv.len != 2) return false;
    if (!std.mem.eql(u8, argv[1], "--help")) return false;
    const bin = argv[0];
    if (bin.len == 0) return false;
    if (std.mem.eql(u8, bin, "fx") or std.mem.endsWith(u8, bin, "/fx") or std.mem.endsWith(u8, bin, "\\fx")) {
        return true;
    }
    const protocol = @import("protocol.zig");
    for (std.meta.tags(protocol.ProviderId)) |id| {
        if (id == .fx) continue;
        if (std.mem.eql(u8, bin, id.defaultBinary())) return false;
    }
    return true;
}

/// Must match `protocol.FX_PROBE_PATHS` length: ~/.fx/bin/fx,
/// leftover ~/.local/bin/fx, PATH fx.
const probe_path_count: u32 = 3;

fn spawnFxProbe(model: *Model, fx: *Effects) void {
    const override = model.providerBinaryOverride(.fx);
    if (override.len > 0) {
        model.setFxPath(override);
        fx.spawn(.{
            .key = fx_probe_key,
            .argv = &.{ model.fxPath(), "--help" },
            .output = .collect,
            .on_exit = Effects.exitMsg(.fx_probe_exit),
        });
        return;
    }
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
    cli_version.clearVersion(model, .fx);
}

pub fn handleFxProbeExit(model: *Model, fx: *Effects, exit: native_sdk.EffectExit) void {
    if (exit.key != fx_probe_key) return;
    // Cancel (Providers Refresh) must not chain to the PATH probe.
    if (exit.reason != .exited) return;
    model.provider_detection_checked_at_ms = model.now_ms;
    if (exit.code == 0) {
        model.fx_available = true;
        cli_version.startVersionProbe(model, fx, .fx);
        return;
    }
    model.fx_available = false;
    cli_version.cancelVersionProbe(model, fx, .fx);
    if (model.providerBinaryOverride(.fx).len > 0) {
        return;
    }
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
    try std.testing.expect(isFxProbeArgv(&.{ "/opt/custom-fx", "--help" }));
    try std.testing.expect(!isFxProbeArgv(&.{ "fx", "acp" }));
    try std.testing.expect(!isFxProbeArgv(&.{"fx"}));
    try std.testing.expect(!isFxProbeArgv(&.{ "", "--help" }));
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

test "fx override skips home/PATH cascade; argv[0] is the override; fail does not cascade" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setHome("/home/probe");
    model.setProviderBinaryOverride(.fx, "/opt/custom-fx");
    startFxProbe(&model, &fx);
    try testing.expect(model.fx_probe_started);
    const spawn = fx.pendingSpawnAt(0).?;
    try testing.expectEqual(fx_probe_key, spawn.key);
    try testing.expect(isFxProbeArgv(spawn.argv));
    try testing.expectEqualStrings("/opt/custom-fx", spawn.argv[0]);
    try testing.expectEqualStrings("--help", spawn.argv[1]);
    try testing.expectEqualStrings("/opt/custom-fx", model.fxPath());

    handleFxProbeExit(&model, &fx, .{ .key = fx_probe_key, .reason = .exited, .code = 127 });
    try testing.expect(!model.fx_available);
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());
    try testing.expectEqualStrings("/opt/custom-fx", model.fxPath());
    try testing.expectEqualStrings("", cli_version.providerVersion(&model, .fx));
}

test "handleFxProbeExit stamps now_ms; cancel is ignored" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.now_ms = 99_000;
    model.setFxPath("/tmp/faku-fx");
    handleFxProbeExit(&model, &fx, .{ .key = fx_probe_key, .reason = .exited, .code = 0 });
    try testing.expect(model.fx_available);
    try testing.expectEqual(@as(i64, 99_000), model.provider_detection_checked_at_ms);
    const version = fx.pendingSpawnAt(0) orelse return error.MissingFxVersion;
    try testing.expectEqual(cli_version.versionKey(.fx), version.key);
    try testing.expect(cli_version.isCliVersionArgv(version.argv, "/tmp/faku-fx"));

    model.now_ms = 100_000;
    handleFxProbeExit(&model, &fx, .{ .key = fx_probe_key, .reason = .rejected, .code = 0 });
    try testing.expectEqual(@as(i64, 99_000), model.provider_detection_checked_at_ms);

    handleFxProbeExit(&model, &fx, .{ .key = 601, .reason = .exited, .code = 0 });
    try testing.expectEqual(@as(i64, 99_000), model.provider_detection_checked_at_ms);
}
