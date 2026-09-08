//! First-cut embedded right-panel Terminal: Native `fx.ptySpawn` plus
//! a bound `<terminal>` element (workbench pattern).
//!
//! Native PTY exists (`docs/src/app/docs/terminal/page.mdx`). The
//! runtime owns the emulator behind the pty key; this module only
//! picks argv, names the dedicated effect key, and accounts for
//! spawn / exit / Restart. Not Waku terminal chrome (tabs, multiple
//! sessions, persist). Open in Terminal (`open_terminal.zig`, key 27)
//! stays the OS-host fallback.
//!
//! `ptySpawn` has no documented cwd field; the child inherits the host
//! environment plus `TERM`. When the selected session's `project_path`
//! is a usable directory, Unix argv reuses `fx_ask_chdir_script`
//! (`cd -- "$1" && shift && exec "$@"`) so the interactive shell
//! starts there. Windows uses documented `cmd.exe /K` + `cd /d PATH`
//! as argv slots, skipping cwd when the path carries cmd-special
//! bytes Native's ConPTY notes refuse for batch grammar. Otherwise
//! the shell starts at the host cwd.

const std = @import("std");
const builtin = @import("builtin");
const native_sdk = @import("native_sdk");
const main = @import("main.zig");
const util = @import("util.zig");
const open_terminal = @import("open_terminal.zig");

const Model = main.Model;
const Effects = main.Effects;

/// Dedicated pty occupancy. Outside stream (1), fx_ask (2), probe (3),
/// daemon 4+, OS sidecars 25–32, attach preview 33–63, overlap 64+,
/// git / mention / skills / cli_probe 200–608, litellm 650.
pub const pty_shell_key: u64 = 700;

pub const default_cols: u16 = 80;
pub const default_rows: u16 = 24;

pub const ended_status = "Shell ended.";
pub const failed_status = "Shell failed.";

pub const macos_shell = "/bin/zsh";
pub const unix_shell = "/bin/sh";
pub const windows_shell = "cmd.exe";
pub const interactive_flag = "-i";
pub const login_flag = "-l";
pub const windows_k_flag = "/K";
pub const windows_cd_prefix = "cd /d ";

/// Interactive login shell argv (workbench's deterministic pick, with
/// documented `-l` so profile scripts run). Replay-stable: no `$SHELL`.
pub const default_shell_argv: []const []const u8 = if (builtin.os.tag == .macos)
    &.{ macos_shell, interactive_flag, login_flag }
else if (builtin.os.tag == .windows)
    &.{windows_shell}
else
    &.{ unix_shell, interactive_flag, login_flag };

const argv_cap: usize = 8;
pub const windows_cd_arg_len: usize = windows_cd_prefix.len + main.max_project_path;

pub const ArgvScratch = struct {
    slots: [argv_cap][]const u8 = [_][]const u8{""} ** argv_cap,
};

pub fn shell_key(model: *const Model) u64 {
    _ = model;
    return pty_shell_key;
}

pub fn term_session_live(model: *const Model) bool {
    return model.term_pty_live;
}

pub fn can_restart_terminal(model: *const Model) bool {
    return model.term_ended and !model.term_pty_live;
}

pub fn has_term_status(model: *const Model) bool {
    return model.term_status_len > 0;
}

pub fn term_status(model: *const Model) []const u8 {
    return model.term_status_storage[0..model.term_status_len];
}

pub fn setTermStatus(model: *Model, text: []const u8) void {
    main.writeFixed(&model.term_status_storage, &model.term_status_len, std.mem.trim(u8, text, " \t\r\n"));
}

pub fn clearTermStatus(model: *Model) void {
    model.term_status_len = 0;
}

/// Bytes cmd.exe's reparse could reinterpret. Native ConPTY docs refuse
/// those for batch targets; skip cwd rather than invent quoting.
pub fn windowsCwdUnsafe(path: []const u8) bool {
    for (path) |byte| {
        switch (byte) {
            '&', '|', '<', '>', '^', '%', '!', '"', '\n', '\r' => return true,
            else => {},
        }
    }
    return false;
}

pub fn writeWindowsCdArg(path: []const u8, dest: *[windows_cd_arg_len]u8) ?[]const u8 {
    if (windowsCwdUnsafe(path)) return null;
    return std.fmt.bufPrint(dest, "{s}{s}", .{ windows_cd_prefix, path }) catch null;
}

/// Fill `scratch` with the spawn argv. `cwd` is the selected project's
/// usable directory, or empty for host cwd.
pub fn argvFor(cwd: []const u8, windows_cd: []const u8, scratch: *ArgvScratch) []const []const u8 {
    if (builtin.os.tag == .windows) {
        if (cwd.len > 0 and windows_cd.len > 0) {
            scratch.slots[0] = windows_shell;
            scratch.slots[1] = windows_k_flag;
            scratch.slots[2] = windows_cd;
            return scratch.slots[0..3];
        }
        scratch.slots[0] = windows_shell;
        return scratch.slots[0..1];
    }
    if (cwd.len > 0) {
        scratch.slots[0] = unix_shell;
        scratch.slots[1] = "-c";
        scratch.slots[2] = util.fx_ask_chdir_script;
        scratch.slots[3] = "sh";
        scratch.slots[4] = cwd;
        const inner = default_shell_argv;
        var i: usize = 0;
        while (i < inner.len) : (i += 1) {
            scratch.slots[5 + i] = inner[i];
        }
        return scratch.slots[0 .. 5 + inner.len];
    }
    const inner = default_shell_argv;
    var i: usize = 0;
    while (i < inner.len) : (i += 1) {
        scratch.slots[i] = inner[i];
    }
    return scratch.slots[0..inner.len];
}

pub fn isPtyShellArgv(argv: []const []const u8) bool {
    if (argv.len == 0) return false;
    if (builtin.os.tag == .windows) {
        if (!std.mem.eql(u8, argv[0], windows_shell)) return false;
        if (argv.len == 1) return true;
        return argv.len == 3 and std.mem.eql(u8, argv[1], windows_k_flag) and
            std.mem.startsWith(u8, argv[2], windows_cd_prefix);
    }
    if (argv.len >= 5 and std.mem.eql(u8, argv[0], unix_shell) and
        std.mem.eql(u8, argv[1], "-c") and
        std.mem.eql(u8, argv[2], util.fx_ask_chdir_script))
    {
        return true;
    }
    if (argv.len != default_shell_argv.len) return false;
    for (argv, default_shell_argv) |got, want| {
        if (!std.mem.eql(u8, got, want)) return false;
    }
    return true;
}

fn resolvePtyCwd(model: *const Model) []const u8 {
    const session = model.sessionByIdConst(model.selected) orelse return "";
    return model.resolveSpawnCwd(session);
}

pub fn spawnShell(model: *Model, fx: *Effects) void {
    if (model.term_pty_live) return;
    const cwd = resolvePtyCwd(model);
    var windows_cd: []const u8 = "";
    if (builtin.os.tag == .windows and cwd.len > 0) {
        windows_cd = writeWindowsCdArg(cwd, &model.term_windows_cd_storage) orelse "";
        model.term_windows_cd_len = windows_cd.len;
    } else {
        model.term_windows_cd_len = 0;
    }
    var scratch: ArgvScratch = .{};
    const argv = argvFor(cwd, windows_cd, &scratch);
    model.term_pty_live = true;
    model.term_ended = false;
    model.term_scrollback = 0;
    clearTermStatus(model);
    fx.ptySpawn(.{
        .key = pty_shell_key,
        .argv = argv,
        .cols = default_cols,
        .rows = default_rows,
        .on_event = Effects.ptyMsg(.term_pty),
    });
}

pub fn restartShell(model: *Model, fx: *Effects) void {
    if (model.term_pty_live) return;
    spawnShell(model, fx);
}

pub fn handlePtyEvent(model: *Model, event: native_sdk.EffectPtyEvent) void {
    if (event.key != pty_shell_key) return;
    switch (event.kind) {
        .output => {},
        .exit => {
            model.term_pty_live = false;
            model.term_ended = true;
            if (event.reason == .exited) {
                setTermStatus(ended_status);
            } else {
                setTermStatus(failed_status);
            }
        },
        .write => unreachable,
    }
}

pub fn applyTermState(model: *Model, state: native_sdk.canvas.TerminalState) void {
    model.term_scrollback = state.scrollback;
}

test "terminal_sessions_enabled is opted in by this ejected build" {
    try std.testing.expect(native_sdk.runtime.terminal_sessions_enabled);
}

test "pty_shell_key is 700 and outside occupied bands" {
    const litellm_rates = @import("litellm_rates.zig");
    const cli_probe = @import("cli_probe.zig");
    try std.testing.expectEqual(@as(u64, 700), pty_shell_key);
    try std.testing.expect(pty_shell_key != main.stream_timer_key);
    try std.testing.expect(pty_shell_key != main.fx_ask_key);
    try std.testing.expect(pty_shell_key != main.fx_probe_key);
    try std.testing.expect(pty_shell_key != main.daemon_proxy_key_first);
    try std.testing.expect(pty_shell_key != open_terminal.open_terminal_key);
    try std.testing.expect(pty_shell_key != main.fx_spawn_overlap_key_first);
    try std.testing.expect(pty_shell_key != cli_probe.cli_probe_key_first);
    try std.testing.expect(pty_shell_key != litellm_rates.litellm_rates_key);
    try std.testing.expect(pty_shell_key > litellm_rates.litellm_rates_key);
}

test "default shell argv is the documented interactive login pick" {
    if (builtin.os.tag == .windows) {
        try std.testing.expectEqual(@as(usize, 1), default_shell_argv.len);
        try std.testing.expectEqualStrings(windows_shell, default_shell_argv[0]);
        return;
    }
    try std.testing.expectEqual(@as(usize, 3), default_shell_argv.len);
    try std.testing.expectEqualStrings(interactive_flag, default_shell_argv[1]);
    try std.testing.expectEqualStrings(login_flag, default_shell_argv[2]);
    if (builtin.os.tag == .macos) {
        try std.testing.expectEqualStrings(macos_shell, default_shell_argv[0]);
    } else {
        try std.testing.expectEqualStrings(unix_shell, default_shell_argv[0]);
    }
}

test "argvFor wraps chdir when cwd is usable and is not Open in Terminal argv" {
    var scratch: ArgvScratch = .{};
    const host = argvFor("", "", &scratch);
    try std.testing.expect(isPtyShellArgv(host));
    try std.testing.expect(!open_terminal.isTerminalArgv(host));

    if (builtin.os.tag == .windows) {
        var cd_buf: [windows_cd_arg_len]u8 = undefined;
        const cd = writeWindowsCdArg("C:\\tmp\\proj", &cd_buf).?;
        const wrapped = argvFor("C:\\tmp\\proj", cd, &scratch);
        try std.testing.expectEqual(@as(usize, 3), wrapped.len);
        try std.testing.expectEqualStrings(windows_shell, wrapped[0]);
        try std.testing.expectEqualStrings(windows_k_flag, wrapped[1]);
        try std.testing.expectEqualStrings("cd /d C:\\tmp\\proj", wrapped[2]);
        try std.testing.expect(isPtyShellArgv(wrapped));
        try std.testing.expect(!open_terminal.isTerminalArgv(wrapped));
        try std.testing.expect(windowsCwdUnsafe("C:\\tmp\\a&b"));
        try std.testing.expect(writeWindowsCdArg("C:\\tmp\\a&b", &cd_buf) == null);
        return;
    }

    const wrapped = argvFor("/tmp/proj", "", &scratch);
    try std.testing.expect(wrapped.len >= 6);
    try std.testing.expectEqualStrings(unix_shell, wrapped[0]);
    try std.testing.expectEqualStrings("-c", wrapped[1]);
    try std.testing.expectEqualStrings(util.fx_ask_chdir_script, wrapped[2]);
    try std.testing.expectEqualStrings("sh", wrapped[3]);
    try std.testing.expectEqualStrings("/tmp/proj", wrapped[4]);
    try std.testing.expectEqualStrings(default_shell_argv[0], wrapped[5]);
    try std.testing.expect(isPtyShellArgv(wrapped));
    try std.testing.expect(!open_terminal.isTerminalArgv(wrapped));
}

test "handlePtyEvent exit sets muted ended or failed status" {
    var model = Model{};
    model.term_pty_live = true;
    handlePtyEvent(&model, .{
        .key = pty_shell_key,
        .kind = .exit,
        .reason = .exited,
        .code = 0,
    });
    try std.testing.expect(!model.term_pty_live);
    try std.testing.expect(model.term_ended);
    try std.testing.expectEqualStrings(ended_status, term_status(&model));
    try std.testing.expect(can_restart_terminal(&model));

    model.term_pty_live = true;
    handlePtyEvent(&model, .{
        .key = pty_shell_key,
        .kind = .exit,
        .reason = .spawn_failed,
        .code = -1,
    });
    try std.testing.expectEqualStrings(failed_status, term_status(&model));
}

test "applyTermState echoes scrollback" {
    var model = Model{};
    applyTermState(&model, .{ .scrollback = 12, .history = 400, .cols = 80, .rows = 24 });
    try std.testing.expectEqual(@as(u32, 12), model.term_scrollback);
}

test "spawnShell on fake executor occupies the bound key" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;
    var model = Model{};
    spawnShell(&model, &fx);
    try std.testing.expect(model.term_pty_live);
    try std.testing.expectEqual(@as(usize, 1), fx.pendingPtyCount());
    const request = fx.pendingPtyAt(0) orelse return error.MissingPtySpawn;
    try std.testing.expectEqual(pty_shell_key, request.key);
    try std.testing.expect(isPtyShellArgv(request.argv));
    try std.testing.expectEqual(default_cols, request.cols);
    try std.testing.expectEqual(default_rows, request.rows);
    spawnShell(&model, &fx);
    try std.testing.expectEqual(@as(usize, 1), fx.pendingPtyCount());
}

test "restartShell re-spawns after fake pty exit" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;
    var model = Model{};
    spawnShell(&model, &fx);
    try fx.feedPtyExit(pty_shell_key, 0, 0, .exited, 0);
    handlePtyEvent(&model, .{
        .key = pty_shell_key,
        .kind = .exit,
        .reason = .exited,
        .code = 0,
    });
    _ = fx.takeMsg();
    try std.testing.expect(can_restart_terminal(&model));
    restartShell(&model, &fx);
    try std.testing.expect(model.term_pty_live);
    try std.testing.expectEqual(@as(usize, 1), fx.pendingPtyCount());
    try std.testing.expectEqual(pty_shell_key, fx.pendingPtyAt(0).?.key);
}
