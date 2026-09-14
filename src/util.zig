//! Leftover util helpers and daemon-env bind.
//!
//! `sessionDisplayTitle` (untitled chrome via `i18n.HeaderUntitledChrome`) /
//! `stampSessionActivity` /
//! `asciiContainsIgnoreCase` / `directoryExists` / `fileExists` /
//! `fx_ask_chdir_script` / `bindDaemonEnv` live here.
//! `update` / `initFx` live in `update.zig`. `initialModel` lives in
//! `boot.zig`. Shell scene / app icons live in `shell.zig`.
//! Layout chrome widths live in `layout.zig`.
//! Spawn / stream effect keys live in `effect_keys.zig`.
//! `main()` stays in `main.zig`.
//! Behavior is unchanged from the former `main` util helpers.

const std = @import("std");
const protocol = @import("protocol.zig");
const session_mod = @import("session.zig");
const model_mod = @import("model.zig");
const i18n = @import("i18n.zig");

const Session = session_mod.Session;
const Model = model_mod.Model;

/// Untitled / catalog-`untitled` display title. Locale from
/// `i18n.HeaderUntitledChrome` (sentence-case EN `New task`, distinct
/// from `Sidebar.new_task`). Real titles stay session data.
pub fn sessionDisplayTitle(session: *const Session, chrome: i18n.HeaderUntitledChrome) []const u8 {
    if (session.untitled or std.mem.eql(u8, session.title(), "untitled")) return chrome.new_task;
    return session.title();
}

pub fn stampSessionActivity(session: *Session, now_ms: i64) void {
    if (now_ms <= 0) return;
    session.updated_at = now_ms;
}

pub fn asciiContainsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (needle.len > haystack.len) return false;
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        if (asciiEqlIgnoreCase(haystack[i .. i + needle.len], needle)) return true;
    }
    return false;
}

fn asciiEqlIgnoreCase(left: []const u8, right: []const u8) bool {
    if (left.len != right.len) return false;
    for (left, right) |a, b| {
        if (std.ascii.toLower(a) != std.ascii.toLower(b)) return false;
    }
    return true;
}

pub fn directoryExists(io: std.Io, path: []const u8) bool {
    var dir = std.Io.Dir.cwd().openDir(io, path, .{}) catch return false;
    dir.close(io);
    return true;
}

pub fn fileExists(io: std.Io, path: []const u8) bool {
    var file = std.Io.Dir.cwd().openFile(io, path, .{}) catch return false;
    file.close(io);
    return true;
}

/// Native `SpawnOptions` (0.9.3) has no `cwd`. `std.process.spawn` does, but
/// Effects does not expose it. `cd` + `exec` is a real child cwd, not `PWD`.
pub const fx_ask_chdir_script = "cd -- \"$1\" && shift && exec \"$@\"";

pub fn bindDaemonEnv(model: *Model, init: std.process.Init) void {
    if (init.environ_map.get(protocol.DAEMON_ADDRESS_ENV)) |addr| {
        model.setDaemonAddress(addr);
    }
    if (init.environ_map.get(protocol.DAEMON_TOKEN_ENV)) |token| {
        model.setDaemonToken(token);
    }
    const args = init.minimal.args.toSlice(init.arena.allocator()) catch return;
    if (args.len > 0 and args[0].len > 0) model.setSidecarPath(args[0]);
}

test "sessionDisplayTitle uses HeaderUntitledChrome for untitled; real titles stay data" {
    const testing = std.testing;
    const chrome_en = i18n.headerUntitledChromeFor(.english, "");
    const chrome_zh = i18n.headerUntitledChromeFor(.simplified_chinese, "");
    const chrome_ja = i18n.headerUntitledChromeFor(.japanese, "");

    var flagged = Session{ .untitled = true };
    try testing.expectEqualStrings("New task", sessionDisplayTitle(&flagged, chrome_en));
    try testing.expectEqualStrings("新建任务", sessionDisplayTitle(&flagged, chrome_zh));
    try testing.expectEqualStrings("新しいタスク", sessionDisplayTitle(&flagged, chrome_ja));

    var catalog = Session{};
    catalog.setTitle("untitled");
    try testing.expect(!catalog.untitled);
    try testing.expectEqualStrings("untitled", catalog.title());
    try testing.expectEqualStrings("New task", sessionDisplayTitle(&catalog, chrome_en));
    try testing.expectEqualStrings("新建任务", sessionDisplayTitle(&catalog, chrome_zh));
    try testing.expectEqualStrings("新しいタスク", sessionDisplayTitle(&catalog, chrome_ja));

    var named = Session{};
    named.setTitle("Review auth");
    try testing.expectEqualStrings("Review auth", sessionDisplayTitle(&named, chrome_en));
    try testing.expectEqualStrings("Review auth", sessionDisplayTitle(&named, chrome_zh));
    try testing.expectEqualStrings("Review auth", sessionDisplayTitle(&named, chrome_ja));
}
