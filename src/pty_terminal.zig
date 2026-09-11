//! First-cut embedded right-panel Terminal: Native `fx.ptySpawn` plus
//! a bound `<terminal>` element (workbench pattern).
//!
//! Native PTY exists (`docs/src/app/docs/terminal/page.mdx`). The
//! runtime owns the emulator behind each pty key; this module picks
//! argv, names the dedicated effect-key band, and accounts for spawn /
//! exit / Restart / New / Close. First-cut multi-session: up to four
//! shells on keys `700..703` inside the existing Terminal tab (chips +
//! New + Close). Occupied slots and the active index persist on
//! `sessions.json` extras (`terminal_slots` / `terminal_active`) as
//! last-live cold-start; session switch / New Task / remove restore
//! occupancy + active from the in-memory `right_panel_session` stash
//! (`capturePersisted` / `restoreFromPersist`; missing / empty →
//! today's lazy single spawn, no pending). First-cut session switch
//! `ptyKill`s the leaving session's live shells (keys 700..703 cannot
//! hold 4×N processes) and re-spawns fresh shells like cold restore;
//! scrollback, status, and live PTY process state stay runtime-only.
//! Not Waku right-panel surface UUID tabs. Open in Terminal
//! (`open_terminal.zig`, key 27) stays the OS-host fallback.
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

/// Dedicated pty occupancy band. Outside stream (1), fx_ask (2), probe (3),
/// daemon 4+, OS sidecars 25–32, attach preview 33–63, overlap 64+,
/// git / mention / skills / cli_probe 200–608, litellm 650,
/// Files markdown Preview images 800–815, transcript
/// markdown images 816–831.
pub const pty_shell_key: u64 = 700;
pub const max_sessions: usize = 4;
pub const pty_shell_key_last: u64 = pty_shell_key + max_sessions - 1;

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

pub const slot_labels = [_][]const u8{ "1", "2", "3", "4" };

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

/// Per-slot occupancy. Live PTYs keep running when another slot is
/// bound; Close `ptyKill`s a live slot and waits for the cancelled
/// exit before the key may be reused. Ended slots stay until Close or
/// Restart. Occupied (`live` or `ended`, not `closing`-only empty) plus
/// the active index persist; scrollback / status / the child process
/// do not.
pub const Slot = struct {
    live: bool = false,
    ended: bool = false,
    closing: bool = false,
    scrollback: u32 = 0,
    status_storage: [main.max_attach_status]u8 = [_]u8{0} ** main.max_attach_status,
    status_len: usize = 0,
    windows_cd_storage: [windows_cd_arg_len]u8 = [_]u8{0} ** windows_cd_arg_len,
    windows_cd_len: usize = 0,
};

pub const TermSessionRow = struct {
    id: u32,
    label: []const u8,
    selected: bool,
};

pub fn shellKeyAt(index: usize) u64 {
    return pty_shell_key + index;
}

pub fn slotIndexForKey(key: u64) ?usize {
    if (key < pty_shell_key or key > pty_shell_key_last) return null;
    return @intCast(key - pty_shell_key);
}

pub fn slotIndexForId(id: u32) ?usize {
    if (id == 0 or id > max_sessions) return null;
    return id - 1;
}

fn slotId(index: usize) u32 {
    return @intCast(index + 1);
}

pub fn activeIndex(model: *const Model) usize {
    if (model.term_active >= max_sessions) return 0;
    return model.term_active;
}

fn slotConst(model: *const Model, index: usize) *const Slot {
    return &model.term_slots[index];
}

fn slotPtr(model: *Model, index: usize) *Slot {
    return &model.term_slots[index];
}

fn activeSlotConst(model: *const Model) *const Slot {
    return slotConst(model, activeIndex(model));
}

fn activeSlot(model: *Model) *Slot {
    return slotPtr(model, activeIndex(model));
}

fn isVisible(slot: *const Slot) bool {
    return (slot.live or slot.ended) and !slot.closing;
}

fn isReserved(slot: *const Slot) bool {
    return slot.live or slot.ended or slot.closing;
}

pub fn reservedCount(model: *const Model) usize {
    var n: usize = 0;
    for (&model.term_slots) |*slot| {
        if (isReserved(slot)) n += 1;
    }
    return n;
}

pub fn visibleCount(model: *const Model) usize {
    var n: usize = 0;
    for (&model.term_slots) |*slot| {
        if (isVisible(slot)) n += 1;
    }
    return n;
}

pub fn anyLive(model: *const Model) bool {
    for (&model.term_slots) |*slot| {
        if (slot.live and !slot.closing) return true;
    }
    return false;
}

fn findFreeIndex(model: *const Model) ?usize {
    for (model.term_slots, 0..) |slot, i| {
        if (!isReserved(&slot)) return i;
    }
    return null;
}

pub fn shell_key(model: *const Model) u64 {
    return shellKeyAt(activeIndex(model));
}

pub fn term_session_live(model: *const Model) bool {
    const slot = activeSlotConst(model);
    return slot.live and !slot.closing;
}

pub fn can_restart_terminal(model: *const Model) bool {
    const slot = activeSlotConst(model);
    return slot.ended and !slot.live and !slot.closing;
}

pub fn can_new_terminal(model: *const Model) bool {
    return reservedCount(model) < max_sessions;
}

pub fn can_close_terminal(model: *const Model) bool {
    return isVisible(activeSlotConst(model));
}

pub fn has_term_status(model: *const Model) bool {
    return activeSlotConst(model).status_len > 0;
}

pub fn term_status(model: *const Model) []const u8 {
    const slot = activeSlotConst(model);
    return slot.status_storage[0..slot.status_len];
}

pub fn term_scrollback(model: *const Model) u32 {
    return activeSlotConst(model).scrollback;
}

fn setSlotStatus(slot: *Slot, text: []const u8) void {
    main.writeFixed(&slot.status_storage, &slot.status_len, std.mem.trim(u8, text, " \t\r\n"));
}

fn clearSlotStatus(slot: *Slot) void {
    slot.status_len = 0;
}

/// Occupancy-order chips (`1`..`n`) with stable 1-based slot ids.
pub fn sessionRows(model: *const Model, arena: std.mem.Allocator) []const TermSessionRow {
    const count = visibleCount(model);
    if (count == 0) return &.{};
    const out = arena.alloc(TermSessionRow, count) catch return &.{};
    var n: usize = 0;
    const active = activeIndex(model);
    for (model.term_slots, 0..) |slot, i| {
        if (!isVisible(&slot)) continue;
        out[n] = .{
            .id = slotId(i),
            .label = slot_labels[n],
            .selected = i == active,
        };
        n += 1;
    }
    return out[0..n];
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

fn spawnAt(model: *Model, fx: *Effects, index: usize) void {
    const slot = slotPtr(model, index);
    if (slot.live) return;
    const cwd = resolvePtyCwd(model);
    var windows_cd: []const u8 = "";
    if (builtin.os.tag == .windows and cwd.len > 0) {
        windows_cd = writeWindowsCdArg(cwd, &slot.windows_cd_storage) orelse "";
        slot.windows_cd_len = windows_cd.len;
    } else {
        slot.windows_cd_len = 0;
    }
    var scratch: ArgvScratch = .{};
    const argv = argvFor(cwd, windows_cd, &scratch);
    slot.live = true;
    slot.ended = false;
    slot.closing = false;
    slot.scrollback = 0;
    clearSlotStatus(slot);
    model.term_active = @intCast(index);
    fx.ptySpawn(.{
        .key = shellKeyAt(index),
        .argv = argv,
        .cols = default_cols,
        .rows = default_rows,
        .on_event = Effects.ptyMsg(.term_pty),
    });
}

fn selectNeighbor(model: *Model, closed_index: usize) void {
    var i = closed_index;
    while (i > 0) {
        i -= 1;
        if (isVisible(slotConst(model, i))) {
            model.term_active = @intCast(i);
            return;
        }
    }
    i = closed_index + 1;
    while (i < max_sessions) : (i += 1) {
        if (isVisible(slotConst(model, i))) {
            model.term_active = @intCast(i);
            return;
        }
    }
    model.term_active = 0;
}

/// Occupied-slot persist row. Index-aligned booleans, cap 4.
/// `true` when that slot was visible (`live` or `ended`, not
/// `closing`-only empty).
pub fn capturePersisted(model: *const Model, out: *[max_sessions]bool) void {
    for (0..max_sessions) |i| {
        out[i] = if (model.term_restore_pending)
            model.term_restore_slots[i]
        else
            isVisible(slotConst(model, i));
    }
}

/// Remember wanted occupancy + active index. Does not spawn (no
/// Effects during JSON apply). Missing callers skip this so
/// `spawnShell` keeps today's lazy single spawn. Empty / all-false
/// occupancy does not arm restore.
pub fn restoreFromPersist(model: *Model, slots: []const bool, active: u8) void {
    model.term_restore_slots = [_]bool{false} ** max_sessions;
    model.term_restore_pending = false;
    model.term_restore_active = 0;
    const n = @min(slots.len, max_sessions);
    var any = false;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (!slots[i]) continue;
        model.term_restore_slots[i] = true;
        any = true;
    }
    if (!any) return;
    model.term_restore_pending = true;
    model.term_restore_active = clampPersistedActive(&model.term_restore_slots, active);
    model.term_active = model.term_restore_active;
}

fn clampPersistedActive(slots: *const [max_sessions]bool, active: u8) u8 {
    if (active < max_sessions and slots[active]) return active;
    var i: u8 = 0;
    while (i < max_sessions) : (i += 1) {
        if (slots[i]) return i;
    }
    return 0;
}

fn snapActiveToOccupied(model: *Model, wanted: u8) void {
    if (wanted < max_sessions and isVisible(slotConst(model, wanted))) {
        model.term_active = wanted;
        return;
    }
    model.term_active = 0;
    for (model.term_slots, 0..) |slot, idx| {
        if (!isVisible(&slot)) continue;
        model.term_active = @intCast(idx);
        return;
    }
}

fn applyPendingRestore(model: *Model, fx: *Effects) bool {
    if (!model.term_restore_pending) return false;
    const wanted_active = model.term_restore_active;
    const wanted = model.term_restore_slots;
    model.term_restore_pending = false;
    model.term_restore_slots = [_]bool{false} ** max_sessions;
    var any = false;
    for (wanted, 0..) |occupy, i| {
        if (!occupy) continue;
        spawnAt(model, fx, i);
        any = true;
    }
    if (!any) return false;
    snapActiveToOccupied(model, wanted_active);
    return true;
}

/// True when a persist restore can spawn: wanted keys are not still
/// reserved from a Close or session-switch `ptyKill` (cancelled exit
/// has not landed yet). Missing / empty persist does not arm pending.
fn pendingRestoreReady(model: *const Model) bool {
    if (!model.term_restore_pending) return true;
    for (0..max_sessions) |i| {
        if (!model.term_restore_slots[i]) continue;
        if (isReserved(slotConst(model, i))) return false;
    }
    return true;
}

/// Tear down live shells so keys 700..703 can be reused for a
/// destination restore. Close waits for cancelled before New; session
/// switch first-cut `ptyKill`s every live slot the same way, keeps the
/// key reserved (`closing`) until that exit, and zeros ended /
/// scrollback immediately so occupancy is not claimed across chat
/// sessions. `restoreFromPersist` then arms occupancy; `spawnShell`
/// waits until wanted keys are free, then re-spawns like cold restore.
pub fn releaseLive(model: *Model, fx: *Effects) void {
    for (0..max_sessions) |i| {
        const slot = slotPtr(model, i);
        if (slot.live) {
            slot.closing = true;
            slot.live = false;
            slot.ended = false;
            slot.scrollback = 0;
            clearSlotStatus(slot);
            fx.ptyKill(shellKeyAt(i));
            continue;
        }
        if (slot.closing) {
            slot.ended = false;
            slot.scrollback = 0;
            clearSlotStatus(slot);
            continue;
        }
        slot.* = .{};
    }
}

/// After a cancelled PTY exit, finish a pending persist restore when
/// the Terminal tab is showing. Does not Restart an ended shell or
/// lazy-spawn slot 0 (those stay `spawnShell` / tab-open). No-op while
/// wanted keys are still reserved, when persist is not pending, or
/// when Terminal is hidden (pending stays until `selectTerminal`).
pub fn maybeFinishRestore(model: *Model, fx: *Effects) void {
    if (!model.term_restore_pending) return;
    if (!model.right_panel_open or model.right_panel_tab != .terminal) return;
    if (anyLive(model)) return;
    if (!pendingRestoreReady(model)) return;
    _ = applyPendingRestore(model, fx);
}

/// Lazy spawn for Terminal tab open: no-op while any slot is live.
/// When a persist restore is pending and wanted keys are still
/// reserved (`closing` after Close or session-switch `ptyKill`),
/// wait. When pending and keys are free, spawn one fresh shell per
/// persisted occupied slot (stable indices) and select
/// `terminal_active` (or the nearest occupied). Otherwise Restart the
/// active ended slot (today's re-select) or allocate slot 0 when
/// nothing is occupied. Missing / empty persist does not arm restore,
/// so this stays today's lazy single spawn.
pub fn spawnShell(model: *Model, fx: *Effects) void {
    if (anyLive(model)) return;
    if (!pendingRestoreReady(model)) return;
    if (applyPendingRestore(model, fx)) return;
    const active = activeIndex(model);
    const slot = slotConst(model, active);
    if (slot.ended and !slot.closing) {
        spawnAt(model, fx, active);
        return;
    }
    const index = findFreeIndex(model) orelse return;
    spawnAt(model, fx, index);
}

pub fn restartShell(model: *Model, fx: *Effects) void {
    if (!can_restart_terminal(model)) return;
    spawnAt(model, fx, activeIndex(model));
}

pub fn newShell(model: *Model, fx: *Effects) void {
    const index = findFreeIndex(model) orelse return;
    spawnAt(model, fx, index);
}

pub fn selectSession(model: *Model, id: u32) void {
    const index = slotIndexForId(id) orelse return;
    if (!isVisible(slotConst(model, index))) return;
    model.term_active = @intCast(index);
}

/// Close the active slot. Live shells use documented `ptyKill` (exit
/// reports `.cancelled`); the key stays reserved until that exit so
/// New cannot collide. Ended slots free immediately. Active moves to
/// the previous visible neighbor, else the next, else slot 0 empty.
pub fn closeActive(model: *Model, fx: *Effects) void {
    if (!can_close_terminal(model)) return;
    const index = activeIndex(model);
    const slot = slotPtr(model, index);
    if (slot.live) {
        slot.closing = true;
        slot.live = false;
        fx.ptyKill(shellKeyAt(index));
    } else {
        slot.* = .{};
    }
    selectNeighbor(model, index);
}

pub fn handlePtyEvent(model: *Model, event: native_sdk.EffectPtyEvent) void {
    const index = slotIndexForKey(event.key) orelse return;
    const slot = slotPtr(model, index);
    switch (event.kind) {
        .output => {},
        .exit => {
            if (slot.closing or (!slot.live and !slot.ended)) {
                slot.* = .{};
                return;
            }
            if (!slot.live) return;
            slot.live = false;
            slot.ended = true;
            if (event.reason == .exited) {
                setSlotStatus(slot, ended_status);
            } else {
                setSlotStatus(slot, failed_status);
            }
        },
        .write => unreachable,
    }
}

pub fn applyTermState(model: *Model, state: native_sdk.canvas.TerminalState) void {
    activeSlot(model).scrollback = state.scrollback;
}

test "terminal_sessions_enabled is opted in by this ejected build" {
    try std.testing.expect(native_sdk.runtime.terminal_sessions_enabled);
}

test "pty_shell_key band is 700..703 and outside occupied bands" {
    const litellm_rates = @import("litellm_rates.zig");
    const cli_probe = @import("cli_probe.zig");
    try std.testing.expectEqual(@as(u64, 700), pty_shell_key);
    try std.testing.expectEqual(@as(usize, 4), max_sessions);
    try std.testing.expectEqual(@as(u64, 703), pty_shell_key_last);
    try std.testing.expectEqual(pty_shell_key, shellKeyAt(0));
    try std.testing.expectEqual(pty_shell_key + 3, shellKeyAt(3));
    try std.testing.expect(pty_shell_key != main.stream_timer_key);
    try std.testing.expect(pty_shell_key != main.fx_ask_key);
    try std.testing.expect(pty_shell_key != main.fx_probe_key);
    try std.testing.expect(pty_shell_key != main.daemon_proxy_key_first);
    try std.testing.expect(pty_shell_key != open_terminal.open_terminal_key);
    try std.testing.expect(pty_shell_key != main.fx_spawn_overlap_key_first);
    try std.testing.expect(pty_shell_key != cli_probe.cli_probe_key_first);
    try std.testing.expect(pty_shell_key != litellm_rates.litellm_rates_key);
    try std.testing.expect(pty_shell_key > litellm_rates.litellm_rates_key);
    try std.testing.expect(pty_shell_key_last != cli_probe.probeKey(.kimi));
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
    model.term_slots[0].live = true;
    handlePtyEvent(&model, .{
        .key = pty_shell_key,
        .kind = .exit,
        .reason = .exited,
        .code = 0,
    });
    try std.testing.expect(!model.term_slots[0].live);
    try std.testing.expect(model.term_slots[0].ended);
    try std.testing.expectEqualStrings(ended_status, term_status(&model));
    try std.testing.expect(can_restart_terminal(&model));

    model.term_slots[0].live = true;
    handlePtyEvent(&model, .{
        .key = pty_shell_key,
        .kind = .exit,
        .reason = .spawn_failed,
        .code = -1,
    });
    try std.testing.expectEqualStrings(failed_status, term_status(&model));
}

test "applyTermState echoes scrollback onto the active slot" {
    var model = Model{};
    applyTermState(&model, .{ .scrollback = 12, .history = 400, .cols = 80, .rows = 24 });
    try std.testing.expectEqual(@as(u32, 12), term_scrollback(&model));
    try std.testing.expectEqual(@as(u32, 12), model.term_slots[0].scrollback);
}

test "spawnShell on fake executor occupies the bound key" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;
    var model = Model{};
    spawnShell(&model, &fx);
    try std.testing.expect(model.term_slots[0].live);
    try std.testing.expectEqual(@as(u8, 0), model.term_active);
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
    try std.testing.expect(model.term_slots[0].live);
    try std.testing.expectEqual(@as(usize, 1), fx.pendingPtyCount());
    try std.testing.expectEqual(pty_shell_key, fx.pendingPtyAt(0).?.key);
}

test "newShell allocates the next free slot up to the cap of 4" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;
    var model = Model{};
    spawnShell(&model, &fx);
    newShell(&model, &fx);
    newShell(&model, &fx);
    newShell(&model, &fx);
    try std.testing.expectEqual(@as(usize, 4), fx.pendingPtyCount());
    try std.testing.expectEqual(@as(u8, 3), model.term_active);
    try std.testing.expect(model.term_slots[1].live);
    try std.testing.expect(model.term_slots[2].live);
    try std.testing.expect(model.term_slots[3].live);
    try std.testing.expectEqual(pty_shell_key + 1, shellKeyAt(1));
    try std.testing.expectEqual(pty_shell_key + 3, shell_key(&model));
    try std.testing.expect(!can_new_terminal(&model));
    newShell(&model, &fx);
    try std.testing.expectEqual(@as(usize, 4), fx.pendingPtyCount());
    try std.testing.expectEqual(@as(u8, 3), model.term_active);
}

test "selectSession switches the bound key while inactive PTYs stay live" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;
    var model = Model{};
    spawnShell(&model, &fx);
    newShell(&model, &fx);
    try std.testing.expectEqual(pty_shell_key + 1, shell_key(&model));
    applyTermState(&model, .{ .scrollback = 4, .history = 400, .cols = 80, .rows = 24 });
    selectSession(&model, 1);
    try std.testing.expectEqual(@as(u8, 0), model.term_active);
    try std.testing.expectEqual(pty_shell_key, shell_key(&model));
    try std.testing.expectEqual(@as(u32, 0), term_scrollback(&model));
    try std.testing.expectEqual(@as(u32, 4), model.term_slots[1].scrollback);
    try std.testing.expect(model.term_slots[0].live);
    try std.testing.expect(model.term_slots[1].live);
    try std.testing.expectEqual(@as(usize, 2), fx.pendingPtyCount());
    selectSession(&model, 0);
    try std.testing.expectEqual(@as(u8, 0), model.term_active);
    selectSession(&model, 9);
    try std.testing.expectEqual(@as(u8, 0), model.term_active);
}

test "closeActive ptyKills the live slot and selects a neighbor" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;
    var model = Model{};
    spawnShell(&model, &fx);
    newShell(&model, &fx);
    newShell(&model, &fx);
    try std.testing.expectEqual(@as(u8, 2), model.term_active);
    closeActive(&model, &fx);
    try std.testing.expect(model.term_slots[2].closing);
    try std.testing.expect(!model.term_slots[2].live);
    try std.testing.expect(fx.ptyKillRequested(pty_shell_key + 2));
    try std.testing.expectEqual(@as(u8, 1), model.term_active);
    try std.testing.expectEqual(pty_shell_key + 1, shell_key(&model));
    try std.testing.expectEqual(@as(usize, 3), reservedCount(&model));
    try fx.feedPtyExit(pty_shell_key + 2, 0, 0, .cancelled, 0);
    handlePtyEvent(&model, .{
        .key = pty_shell_key + 2,
        .kind = .exit,
        .reason = .cancelled,
        .code = -1,
    });
    _ = fx.takeMsg();
    try std.testing.expect(!model.term_slots[2].closing);
    try std.testing.expect(!model.term_slots[2].live);
    try std.testing.expect(!model.term_slots[2].ended);
    try std.testing.expectEqual(@as(usize, 2), reservedCount(&model));
    try std.testing.expect(can_new_terminal(&model));
}

test "close compaction reuses the freed slot and prefers the previous neighbor" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;
    var model = Model{};
    spawnShell(&model, &fx);
    newShell(&model, &fx);
    newShell(&model, &fx);
    selectSession(&model, 2);
    try std.testing.expectEqual(@as(u8, 1), model.term_active);
    closeActive(&model, &fx);
    try std.testing.expectEqual(@as(u8, 0), model.term_active);
    try fx.feedPtyExit(pty_shell_key + 1, 0, 0, .cancelled, 0);
    handlePtyEvent(&model, .{
        .key = pty_shell_key + 1,
        .kind = .exit,
        .reason = .cancelled,
        .code = -1,
    });
    _ = fx.takeMsg();
    const rows = sessionRows(&model, arena);
    try std.testing.expectEqual(@as(usize, 2), rows.len);
    try std.testing.expectEqual(@as(u32, 1), rows[0].id);
    try std.testing.expectEqualStrings("1", rows[0].label);
    try std.testing.expect(rows[0].selected);
    try std.testing.expectEqual(@as(u32, 3), rows[1].id);
    try std.testing.expectEqualStrings("2", rows[1].label);
    newShell(&model, &fx);
    try std.testing.expectEqual(@as(u8, 1), model.term_active);
    try std.testing.expect(model.term_slots[1].live);
    try std.testing.expectEqual(pty_shell_key + 1, shell_key(&model));
}

test "close of the last slot leaves an empty pane until New" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;
    var model = Model{};
    spawnShell(&model, &fx);
    closeActive(&model, &fx);
    try std.testing.expect(!can_close_terminal(&model));
    try std.testing.expect(!term_session_live(&model));
    try fx.feedPtyExit(pty_shell_key, 0, 0, .cancelled, 0);
    handlePtyEvent(&model, .{
        .key = pty_shell_key,
        .kind = .exit,
        .reason = .cancelled,
        .code = -1,
    });
    _ = fx.takeMsg();
    try std.testing.expectEqual(@as(usize, 0), reservedCount(&model));
    try std.testing.expect(can_new_terminal(&model));
    newShell(&model, &fx);
    try std.testing.expect(model.term_slots[0].live);
    try std.testing.expectEqual(pty_shell_key, shell_key(&model));
}

test "capturePersisted / restoreFromPersist round-trip occupancy and active" {
    var model = Model{};
    model.term_slots[0].live = true;
    model.term_slots[2].ended = true;
    model.term_slots[3].closing = true;
    model.term_active = 2;
    var persisted: [max_sessions]bool = undefined;
    capturePersisted(&model, &persisted);
    try std.testing.expect(persisted[0]);
    try std.testing.expect(!persisted[1]);
    try std.testing.expect(persisted[2]);
    try std.testing.expect(!persisted[3]);

    var restored = Model{};
    restoreFromPersist(&restored, &persisted, 2);
    try std.testing.expect(restored.term_restore_pending);
    try std.testing.expect(restored.term_restore_slots[0]);
    try std.testing.expect(!restored.term_restore_slots[1]);
    try std.testing.expect(restored.term_restore_slots[2]);
    try std.testing.expect(!restored.term_restore_slots[3]);
    try std.testing.expectEqual(@as(u8, 2), restored.term_restore_active);
    try std.testing.expectEqual(@as(u8, 2), restored.term_active);
    try std.testing.expect(!restored.term_slots[0].live);
    try std.testing.expectEqual(@as(usize, 0), visibleCount(&restored));

    var again: [max_sessions]bool = undefined;
    capturePersisted(&restored, &again);
    try std.testing.expectEqualSlices(bool, &persisted, &again);
}

test "missing terminal_slots restore leaves spawnShell as today's lazy single" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;
    var model = Model{};
    restoreFromPersist(&model, &.{}, 3);
    try std.testing.expect(!model.term_restore_pending);
    spawnShell(&model, &fx);
    try std.testing.expect(model.term_slots[0].live);
    try std.testing.expect(!model.term_slots[1].live);
    try std.testing.expect(!model.term_slots[2].live);
    try std.testing.expect(!model.term_slots[3].live);
    try std.testing.expectEqual(@as(u8, 0), model.term_active);
    try std.testing.expectEqual(@as(usize, 1), fx.pendingPtyCount());
}

test "spawnShell restores three occupied persist slots at stable indices" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;
    var model = Model{};
    const slots = [_]bool{ true, true, true, false };
    restoreFromPersist(&model, &slots, 1);
    spawnShell(&model, &fx);
    try std.testing.expect(!model.term_restore_pending);
    try std.testing.expect(model.term_slots[0].live);
    try std.testing.expect(model.term_slots[1].live);
    try std.testing.expect(model.term_slots[2].live);
    try std.testing.expect(!model.term_slots[3].live);
    try std.testing.expectEqual(@as(u8, 1), model.term_active);
    try std.testing.expectEqual(@as(usize, 3), fx.pendingPtyCount());
    try std.testing.expectEqual(pty_shell_key, fx.pendingPtyAt(0).?.key);
    try std.testing.expectEqual(pty_shell_key + 1, fx.pendingPtyAt(1).?.key);
    try std.testing.expectEqual(pty_shell_key + 2, fx.pendingPtyAt(2).?.key);
    spawnShell(&model, &fx);
    try std.testing.expectEqual(@as(usize, 3), fx.pendingPtyCount());
}

test "restoreFromPersist clamps active when persisted index is empty" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;
    var model = Model{};
    const slots = [_]bool{ true, false, true, false };
    restoreFromPersist(&model, &slots, 1);
    try std.testing.expectEqual(@as(u8, 0), model.term_restore_active);
    spawnShell(&model, &fx);
    try std.testing.expect(model.term_slots[0].live);
    try std.testing.expect(!model.term_slots[1].live);
    try std.testing.expect(model.term_slots[2].live);
    try std.testing.expectEqual(@as(u8, 0), model.term_active);

    var other = Model{};
    restoreFromPersist(&other, &slots, 3);
    spawnShell(&other, &fx);
    try std.testing.expectEqual(@as(u8, 0), other.term_active);

    var third = Model{};
    restoreFromPersist(&third, &slots, 2);
    spawnShell(&third, &fx);
    try std.testing.expectEqual(@as(u8, 2), third.term_active);
}

test "CONTEXT describes occupied Terminal slots persist, not Waku UUID tabs" {
    const context = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "CONTEXT.md", std.testing.allocator, .limited(512 * 1024));
    defer std.testing.allocator.free(context);
    try std.testing.expect(std.mem.indexOf(u8, context, "First-cut multi-session inside the Terminal tab") != null or
        std.mem.indexOf(u8, context, "first-cut multi-session inside that tab") != null);
    try std.testing.expect(std.mem.indexOf(u8, context, "occupied slots and the active index persist") != null);
    try std.testing.expect(std.mem.indexOf(u8, context, "scrollback/status/live process state stay runtime-only") != null);
    try std.testing.expect(std.mem.indexOf(u8, context, "sessions do not persist across") == null);
    try std.testing.expect(std.mem.indexOf(u8, context, "runtime-only chips + New + Close; not Waku surface UUID tabs / persist") == null);
}

test "releaseLive ptyKills live slots and zeros ended occupancy" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;
    var model = Model{};
    spawnShell(&model, &fx);
    newShell(&model, &fx);
    model.term_slots[2].ended = true;
    model.term_slots[2].scrollback = 9;
    model.term_slots[0].scrollback = 4;
    releaseLive(&model, &fx);
    try std.testing.expect(model.term_slots[0].closing);
    try std.testing.expect(!model.term_slots[0].live);
    try std.testing.expectEqual(@as(u32, 0), model.term_slots[0].scrollback);
    try std.testing.expect(model.term_slots[1].closing);
    try std.testing.expect(!model.term_slots[2].ended);
    try std.testing.expectEqual(@as(u32, 0), model.term_slots[2].scrollback);
    try std.testing.expect(fx.ptyKillRequested(pty_shell_key));
    try std.testing.expect(fx.ptyKillRequested(pty_shell_key + 1));
    try std.testing.expectEqual(@as(usize, 2), reservedCount(&model));

    const slots = [_]bool{ true, false, true, false };
    restoreFromPersist(&model, &slots, 2);
    spawnShell(&model, &fx);
    try std.testing.expect(model.term_restore_pending);
    try std.testing.expect(!model.term_slots[0].live);
    try std.testing.expect(!model.term_slots[2].live);

    try fx.feedPtyExit(pty_shell_key, 0, 0, .cancelled, 0);
    handlePtyEvent(&model, .{
        .key = pty_shell_key,
        .kind = .exit,
        .reason = .cancelled,
        .code = -1,
    });
    _ = fx.takeMsg();
    try std.testing.expect(model.term_restore_pending);
    try fx.feedPtyExit(pty_shell_key + 1, 0, 0, .cancelled, 0);
    handlePtyEvent(&model, .{
        .key = pty_shell_key + 1,
        .kind = .exit,
        .reason = .cancelled,
        .code = -1,
    });
    _ = fx.takeMsg();
    model.right_panel_open = true;
    model.right_panel_tab = .terminal;
    maybeFinishRestore(&model, &fx);
    try std.testing.expect(!model.term_restore_pending);
    try std.testing.expect(model.term_slots[0].live);
    try std.testing.expect(!model.term_slots[1].live);
    try std.testing.expect(model.term_slots[2].live);
    try std.testing.expectEqual(@as(u8, 2), model.term_active);
}
