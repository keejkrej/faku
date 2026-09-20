//! Settings Providers `{binary} --version` probes (runtime badge).
//!
//! After a `--help` probe marks a provider Available (`fx_available` /
//! `cli_available`), Faku one-shots `{binaryFor} --version` with the
//! same Native collect+on_exit pattern as `cli_probe` / `fx_probe`.
//! Override path when set, else the same binary the help-probe used.
//! No daemon, no live CLI required in tests (fake executor /
//! `feedOutput` / `feedStderr` / `feedExit`).
//!
//! Parse matches Waku `parse_cli_version` (`crates/waku-protocol/src/model.rs`):
//! first non-empty line of combined stdout+stderr (`output` + `"\n"` +
//! `stderr_tail`); split whitespace; each token trims leading `v` then
//! trims chars that are not ASCII alphanumeric / `.` / `-`; keep the
//! first token whose first `.`-part is all digits AND whose second
//! `.`-part starts with a digit. Storage is the normalized token
//! (no extra `v`); `rowFor` / markup paint `v{version}`.
//!
//! Fail closed: non-zero / cancelled / spawn_failed / rejected /
//! signaled / parse miss → clear that provider's version (no badge).
//! Refresh / override apply cancel in-flight version probes, clear
//! stored versions, and restart `--version` only after the new help
//! probe marks Available again. Not-found / unavailable rows never
//! show a badge.
//!
//! Spawn key is `cli_version_key_first + @intFromEnum(id)` so fx=610
//! … ohmypi=619. Distinct from `fx_probe_key` (3), `cli_probe_key_first`
//! 600 + ProviderId (claude=601 … ohmypi=609; fx slot unused), skills
//! scan (530+) / rename (580+) / remove (590+), litellm (650),
//! Browser `page_title` (660–699), pty (700..703), daemon (4+),
//! fx spawn (64+). Refresh cancels the same fixed key per id.

const std = @import("std");
const native_sdk = @import("native_sdk");
const main = @import("main.zig");
const model_exports = @import("model_exports.zig");
const effect_keys = @import("effect_keys.zig");
const protocol = @import("protocol.zig");

const Model = model_exports.Model;
const Effects = main.Effects;
const writeFixed = model_exports.writeFixed;

/// Fixed key per ProviderId, including fx (help stays on
/// `fx_probe_key` 3). Distinct from `cli_probe_key_first` 600.
pub const cli_version_key_first: u64 = 610;

pub const version_flag = "--version";

pub const max_cli_version = model_exports.max_cli_version;

pub fn versionKey(id: protocol.ProviderId) u64 {
    return cli_version_key_first + @intFromEnum(id);
}

pub fn fromVersionKey(key: u64) ?protocol.ProviderId {
    if (key < cli_version_key_first) return null;
    const index = key - cli_version_key_first;
    const tags = std.meta.tags(protocol.ProviderId);
    if (index >= tags.len) return null;
    return tags[index];
}

pub fn isCliVersionArgv(argv: []const []const u8, binary: []const u8) bool {
    if (argv.len != 2) return false;
    if (!std.mem.eql(u8, argv[1], version_flag)) return false;
    if (binary.len == 0) return false;
    return std.mem.eql(u8, argv[0], binary);
}

/// Override path when set, else the same binary the help-probe used
/// (`fxPath()` after a successful fx probe, else PATH `defaultBinary`).
pub fn versionBinary(model: *const Model, id: protocol.ProviderId) []const u8 {
    const override = model.providerBinaryOverride(id);
    if (override.len > 0) return override;
    if (id == .fx) {
        const path = model.fxPath();
        if (path.len > 0) return path;
    }
    return id.defaultBinary();
}

pub fn providerVersion(model: *const Model, id: protocol.ProviderId) []const u8 {
    const index = @intFromEnum(id);
    return model.cli_version_storage[index][0..model.cli_version_len[index]];
}

pub fn clearVersion(model: *Model, id: protocol.ProviderId) void {
    model.cli_version_len[@intFromEnum(id)] = 0;
}

pub fn clearAllVersions(model: *Model) void {
    for (std.meta.tags(protocol.ProviderId)) |id| {
        clearVersion(model, id);
    }
}

fn setVersion(model: *Model, id: protocol.ProviderId, token: []const u8) void {
    const index = @intFromEnum(id);
    writeFixed(&model.cli_version_storage[index], &model.cli_version_len[index], token);
}

pub fn cancelVersionProbe(model: *Model, fx: *Effects, id: protocol.ProviderId) void {
    fx.cancel(versionKey(id));
    clearVersion(model, id);
}

pub fn cancelAllVersionProbes(model: *Model, fx: *Effects) void {
    for (std.meta.tags(protocol.ProviderId)) |id| {
        cancelVersionProbe(model, fx, id);
    }
}

/// Start `{binary} --version`. Cancels any in-flight probe for this id
/// and clears the stored token first so a stale badge cannot linger.
/// Empty binary fail-closes (no spawn).
pub fn startVersionProbe(model: *Model, fx: *Effects, id: protocol.ProviderId) void {
    fx.cancel(versionKey(id));
    clearVersion(model, id);
    const binary = versionBinary(model, id);
    if (binary.len == 0) return;
    fx.spawn(.{
        .key = versionKey(id),
        .argv = &.{ binary, version_flag },
        .output = .collect,
        .on_exit = Effects.exitMsg(.cli_version_exit),
    });
}

pub fn handleCliVersionExit(model: *Model, exit: native_sdk.EffectExit) void {
    const id = fromVersionKey(exit.key) orelse return;
    if (exit.reason != .exited) {
        clearVersion(model, id);
        return;
    }
    if (exit.code != 0) {
        clearVersion(model, id);
        return;
    }
    if (parseCliVersionCombined(exit.output, exit.stderr_tail)) |token| {
        setVersion(model, id, token);
    } else {
        clearVersion(model, id);
    }
}

fn parseCliVersionCombined(output: []const u8, stderr_tail: []const u8) ?[]const u8 {
    if (firstNonEmptyLine(output)) |line| return parseCliVersionLine(line);
    if (firstNonEmptyLine(stderr_tail)) |line| return parseCliVersionLine(line);
    return null;
}

/// Waku `parse_cli_version` over a combined stdout+stderr blob.
pub fn parseCliVersion(output: []const u8) ?[]const u8 {
    const line = firstNonEmptyLine(output) orelse return null;
    return parseCliVersionLine(line);
}

fn firstNonEmptyLine(text: []const u8) ?[]const u8 {
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw| {
        const trimmed = std.mem.trim(u8, raw, " \t\r");
        if (trimmed.len > 0) return trimmed;
    }
    return null;
}

fn parseCliVersionLine(line: []const u8) ?[]const u8 {
    var tokens = std.mem.tokenizeAny(u8, line, " \t");
    while (tokens.next()) |token| {
        const stripped = trimLeadingV(token);
        const cleaned = trimVersionPunct(stripped);
        if (isVersionToken(cleaned)) return cleaned;
    }
    return null;
}

fn trimLeadingV(token: []const u8) []const u8 {
    var i: usize = 0;
    while (i < token.len and token[i] == 'v') i += 1;
    return token[i..];
}

fn isVersionChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '.' or c == '-';
}

fn trimVersionPunct(token: []const u8) []const u8 {
    var start: usize = 0;
    var end: usize = token.len;
    while (start < end and !isVersionChar(token[start])) start += 1;
    while (end > start and !isVersionChar(token[end - 1])) end -= 1;
    return token[start..end];
}

fn isAsciiDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

fn isAllAsciiDigits(part: []const u8) bool {
    if (part.len == 0) return false;
    for (part) |c| {
        if (!isAsciiDigit(c)) return false;
    }
    return true;
}

fn isVersionToken(token: []const u8) bool {
    var parts = std.mem.splitScalar(u8, token, '.');
    const first = parts.next() orelse return false;
    if (!isAllAsciiDigits(first)) return false;
    const second = parts.next() orelse return false;
    return second.len > 0 and isAsciiDigit(second[0]);
}

test "versionKey is per-id including fx and skips cli_probe / fx_probe / litellm" {
    try std.testing.expectEqual(@as(u64, 610), versionKey(.fx));
    try std.testing.expectEqual(@as(u64, 611), versionKey(.claude));
    try std.testing.expectEqual(@as(u64, 612), versionKey(.codex));
    try std.testing.expectEqual(@as(u64, 613), versionKey(.amp));
    try std.testing.expectEqual(@as(u64, 614), versionKey(.grok));
    try std.testing.expectEqual(@as(u64, 615), versionKey(.opencode));
    try std.testing.expectEqual(@as(u64, 616), versionKey(.cursor));
    try std.testing.expectEqual(@as(u64, 617), versionKey(.pi));
    try std.testing.expectEqual(@as(u64, 618), versionKey(.kimi));
    try std.testing.expectEqual(@as(u64, 619), versionKey(.ohmypi));
    try std.testing.expect(versionKey(.fx) != @as(u64, 3));
    try std.testing.expect(versionKey(.claude) != @as(u64, 601));
    try std.testing.expect(versionKey(.kimi) != @as(u64, 608));
    try std.testing.expect(versionKey(.ohmypi) != @as(u64, 609));
    try std.testing.expect(versionKey(.fx) != effect_keys.fx_ask_key);
    try std.testing.expect(versionKey(.fx) != effect_keys.daemon_proxy_key_first);
    try std.testing.expectEqual(protocol.ProviderId.fx, fromVersionKey(610).?);
    try std.testing.expectEqual(protocol.ProviderId.claude, fromVersionKey(611).?);
    try std.testing.expectEqual(protocol.ProviderId.kimi, fromVersionKey(618).?);
    try std.testing.expectEqual(protocol.ProviderId.ohmypi, fromVersionKey(619).?);
    try std.testing.expect(fromVersionKey(600) == null);
    try std.testing.expect(fromVersionKey(601) == null);
    try std.testing.expect(fromVersionKey(3) == null);
    try std.testing.expect(fromVersionKey(609) == null);
    try std.testing.expect(fromVersionKey(620) == null);
    try std.testing.expect(versionKey(.ohmypi) < @as(u64, 650));
}

test "parseCliVersion matches Waku version_tests banners" {
    try std.testing.expectEqualStrings("0.45.0", parseCliVersion("codex-cli 0.45.0\n").?);
    try std.testing.expectEqualStrings("2.1.24", parseCliVersion("2.1.24 (Claude Code)\n").?);
    try std.testing.expectEqualStrings("1.3.0-beta.2", parseCliVersion("v1.3.0-beta.2").?);
    try std.testing.expectEqualStrings("0.9.12", parseCliVersion("\nAmp CLI version 0.9.12\n").?);
    try std.testing.expect(parseCliVersion("not a version") == null);
    try std.testing.expect(parseCliVersion("") == null);
    try std.testing.expect(parseCliVersion("build 2024 f3a9c1") == null);
    try std.testing.expectEqualStrings("2025.09.12-4f8d8e2", parseCliVersion("cursor-agent 2025.09.12-4f8d8e2").?);
}

test "parseCliVersionCombined prefers first non-empty stdout line then stderr" {
    try std.testing.expectEqualStrings(
        "0.45.0",
        parseCliVersionCombined("codex-cli 0.45.0\n", "ignored 9.9.9").?,
    );
    try std.testing.expectEqualStrings(
        "2.1.24",
        parseCliVersionCombined("", "2.1.24 (Claude Code)\n").?,
    );
    try std.testing.expectEqualStrings(
        "1.3.0-beta.2",
        parseCliVersionCombined("   \n", "v1.3.0-beta.2").?,
    );
    try std.testing.expect(parseCliVersionCombined("not a version", "0.45.0") == null);
    try std.testing.expect(parseCliVersionCombined("", "") == null);
}

test "startVersionProbe argv is {binary} --version; override wins" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    startVersionProbe(&model, &fx, .claude);
    const claude = findPending(&fx, versionKey(.claude)) orelse return error.MissingClaudeVersion;
    try testing.expect(isCliVersionArgv(claude.argv, "claude"));
    try testing.expectEqualStrings("claude", claude.argv[0]);
    try testing.expectEqualStrings(version_flag, claude.argv[1]);
    try testing.expect(findPending(&fx, @as(u64, 601)) == null);

    model.setProviderBinaryOverride(.claude, "/opt/custom-claude");
    startVersionProbe(&model, &fx, .claude);
    const override = findPending(&fx, versionKey(.claude)) orelse return error.MissingOverrideVersion;
    try testing.expect(isCliVersionArgv(override.argv, "/opt/custom-claude"));

    model.setFxPath("/home/probe/.fx/bin/fx");
    startVersionProbe(&model, &fx, .fx);
    const fx_spawn = findPending(&fx, versionKey(.fx)) orelse return error.MissingFxVersion;
    try testing.expect(isCliVersionArgv(fx_spawn.argv, "/home/probe/.fx/bin/fx"));
    try testing.expect(fx_spawn.key != @as(u64, 3));
}

test "Available help exit is not this module; version exit parse success stores token without extra v" {
    const testing = std.testing;
    var model = Model{};
    handleCliVersionExit(&model, .{
        .key = versionKey(.codex),
        .reason = .exited,
        .code = 0,
        .output = "codex-cli 0.45.0\n",
    });
    try testing.expectEqualStrings("0.45.0", providerVersion(&model, .codex));
    try testing.expect(!std.mem.startsWith(u8, providerVersion(&model, .codex), "v"));

    handleCliVersionExit(&model, .{
        .key = versionKey(.amp),
        .reason = .exited,
        .code = 0,
        .output = "",
        .stderr_tail = "Amp CLI version 0.9.12\n",
    });
    try testing.expectEqualStrings("0.9.12", providerVersion(&model, .amp));
}

test "version exit fail / cancel / spawn_failed / parse miss clears" {
    const testing = std.testing;
    var model = Model{};
    handleCliVersionExit(&model, .{
        .key = versionKey(.claude),
        .reason = .exited,
        .code = 0,
        .output = "2.1.24 (Claude Code)\n",
    });
    try testing.expectEqualStrings("2.1.24", providerVersion(&model, .claude));

    handleCliVersionExit(&model, .{
        .key = versionKey(.claude),
        .reason = .exited,
        .code = 1,
        .output = "2.1.24 (Claude Code)\n",
    });
    try testing.expectEqualStrings("", providerVersion(&model, .claude));

    handleCliVersionExit(&model, .{
        .key = versionKey(.claude),
        .reason = .exited,
        .code = 0,
        .output = "2.1.24 (Claude Code)\n",
    });
    handleCliVersionExit(&model, .{
        .key = versionKey(.claude),
        .reason = .cancelled,
        .code = 0,
    });
    try testing.expectEqualStrings("", providerVersion(&model, .claude));

    handleCliVersionExit(&model, .{
        .key = versionKey(.claude),
        .reason = .exited,
        .code = 0,
        .output = "2.1.24 (Claude Code)\n",
    });
    handleCliVersionExit(&model, .{
        .key = versionKey(.claude),
        .reason = .spawn_failed,
        .code = 0,
    });
    try testing.expectEqualStrings("", providerVersion(&model, .claude));

    handleCliVersionExit(&model, .{
        .key = versionKey(.claude),
        .reason = .exited,
        .code = 0,
        .output = "not a version",
    });
    try testing.expectEqualStrings("", providerVersion(&model, .claude));
}

test "cancelAllVersionProbes clears stored tokens and drops in-flight --version" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    startVersionProbe(&model, &fx, .claude);
    handleCliVersionExit(&model, .{
        .key = versionKey(.codex),
        .reason = .exited,
        .code = 0,
        .output = "codex-cli 0.45.0\n",
    });
    try testing.expectEqualStrings("0.45.0", providerVersion(&model, .codex));
    try testing.expect(findPending(&fx, versionKey(.claude)) != null);

    cancelAllVersionProbes(&model, &fx);
    try testing.expectEqualStrings("", providerVersion(&model, .codex));
    try testing.expectEqualStrings("", providerVersion(&model, .claude));
    try testing.expect(findPending(&fx, versionKey(.claude)) == null);
}

fn findPending(fx: *Effects, key: u64) ?@TypeOf(fx.pendingSpawnAt(0).?) {
    var i: usize = 0;
    while (fx.pendingSpawnAt(i)) |item| : (i += 1) {
        if (item.key == key) return item;
    }
    return null;
}
