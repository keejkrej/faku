//! Codex `/goal` handlers and usage formatting.
//!
//! Composer set / clear / refresh / status and the compact usage
//! meter live here. Session goal fields and Model `goal_label` /
//! `goal_status_label` stay in `main.zig`. Behavior is unchanged
//! from the former `main` goal helpers.

const std = @import("std");
const main = @import("main.zig");
const protocol = @import("protocol.zig");
const store = @import("store.zig");
const daemon_proxy = @import("daemon_proxy.zig");

const Model = main.Model;
const Effects = main.Effects;

/// Compact Codex goal meter: `12k/100k · 3m`, or `tokensUsed` when there
/// is no budget. Missing fields stay omitted. Not a live ticker.
pub fn formatThreadGoalUsage(
    buf: []u8,
    token_budget: ?u64,
    tokens_used: ?u64,
    time_used_seconds: ?u64,
) ?[]const u8 {
    var token_buf: [24]u8 = undefined;
    const token_part: ?[]const u8 = if (tokens_used) |used| blk: {
        if (token_budget) |budget| {
            var used_buf: [16]u8 = undefined;
            var budget_buf: [16]u8 = undefined;
            const used_s = formatCompactTokens(&used_buf, used) orelse break :blk null;
            const budget_s = formatCompactTokens(&budget_buf, budget) orelse break :blk null;
            break :blk std.fmt.bufPrint(&token_buf, "{s}/{s}", .{ used_s, budget_s }) catch null;
        }
        break :blk formatCompactTokens(&token_buf, used);
    } else if (token_budget) |budget|
        formatCompactTokens(&token_buf, budget)
    else
        null;

    var time_buf: [16]u8 = undefined;
    const time_part: ?[]const u8 = if (time_used_seconds) |secs|
        formatGoalTime(&time_buf, secs)
    else
        null;

    if (token_part) |tokens| {
        if (time_part) |time| {
            return std.fmt.bufPrint(buf, "{s} · {s}", .{ tokens, time }) catch null;
        }
        return std.fmt.bufPrint(buf, "{s}", .{tokens}) catch null;
    }
    if (time_part) |time| {
        return std.fmt.bufPrint(buf, "{s}", .{time}) catch null;
    }
    return null;
}

/// Context window meter: `12.4k / 200k`. `size == 0` is unknown — omit.
pub fn formatContextUsage(buf: []u8, used: u64, size: u64) ?[]const u8 {
    if (size == 0) return null;
    var used_buf: [16]u8 = undefined;
    var size_buf: [16]u8 = undefined;
    const used_s = formatCompactTokens(&used_buf, used) orelse return null;
    const size_s = formatCompactTokens(&size_buf, size) orelse return null;
    return std.fmt.bufPrint(buf, "{s} / {s}", .{ used_s, size_s }) catch null;
}

/// Compact token counts for Settings Usage / composer meters: `12.4k`,
/// `200k`, `1.2M`. Callers join with ` / ` or `/` as needed.
pub fn formatCompactTokens(buf: []u8, value: u64) ?[]const u8 {
    if (value >= 1_000_000) {
        const m = value / 1_000_000;
        const rem = value % 1_000_000;
        if (rem == 0) return std.fmt.bufPrint(buf, "{d}M", .{m}) catch null;
        return std.fmt.bufPrint(buf, "{d}.{d}M", .{ m, rem / 100_000 }) catch null;
    }
    if (value >= 1_000) {
        const k = value / 1_000;
        const rem = value % 1_000;
        if (rem == 0) return std.fmt.bufPrint(buf, "{d}k", .{k}) catch null;
        return std.fmt.bufPrint(buf, "{d}.{d}k", .{ k, rem / 100 }) catch null;
    }
    return std.fmt.bufPrint(buf, "{d}", .{value}) catch null;
}

fn formatGoalTime(buf: []u8, seconds: u64) ?[]const u8 {
    if (seconds < 60) return std.fmt.bufPrint(buf, "{d}s", .{seconds}) catch null;
    const minutes = seconds / 60;
    if (minutes < 60) return std.fmt.bufPrint(buf, "{d}m", .{minutes}) catch null;
    const hours = minutes / 60;
    const rem_m = minutes % 60;
    if (rem_m == 0) return std.fmt.bufPrint(buf, "{d}h", .{hours}) catch null;
    return std.fmt.bufPrint(buf, "{d}h {d}m", .{ hours, rem_m }) catch null;
}

pub fn handleGoalSet(model: *Model, fx: *Effects) void {
    if (store.resolveDaemonMirrorAddress(model).len == 0) return;
    const text = std.mem.trim(u8, model.draft(), " \t\r\n");
    if (text.len == 0) return;
    const session = model.sessionById(model.selected) orelse return;
    session.setThreadGoal(text, protocol.ThreadGoalStatus.active.wireName());
    store.persistIfPossible(model, session.id, fx);
    _ = maybeSendGoal(model, fx, session.id, .{
        .set = .{
            .objective = session.threadGoalObjective(),
            .status = session.threadGoalStatus(),
            .replace = false,
        },
    });
    var key_buf: [store.max_draft_key]u8 = undefined;
    const draft_key = store.draftKey(session, &key_buf);
    model.draft_buffer.clear();
    if (draft_key) |key| store.discardDraftIfPossible(model, key);
}

pub fn handleGoalClear(model: *Model, fx: *Effects) void {
    if (store.resolveDaemonMirrorAddress(model).len == 0) return;
    const session = model.sessionById(model.selected) orelse return;
    session.clearThreadGoal();
    store.persistIfPossible(model, session.id, fx);
    _ = maybeSendGoal(model, fx, session.id, .clear);
}

pub fn handleGoalRefresh(model: *Model, fx: *Effects) void {
    _ = maybeSendGoal(model, fx, model.selected, .refresh);
}

/// Composer `/goal` status chip. Keep the provider objective (`objective: null`)
/// and write the chosen Codex `ThreadGoalStatus`. No-op without a daemon.
pub fn handleGoalSetStatus(model: *Model, fx: *Effects, status: []const u8) void {
    model.closeGoalStatusPicker();
    if (store.resolveDaemonMirrorAddress(model).len == 0) return;
    const parsed = protocol.ThreadGoalStatus.fromWire(status) orelse return;
    const session = model.sessionById(model.selected) orelse return;
    session.setThreadGoalStatus(parsed.wireName());
    store.persistIfPossible(model, session.id, fx);
    _ = maybeSendGoal(model, fx, session.id, .{
        .set = .{
            .objective = null,
            .status = session.threadGoalStatus(),
            .replace = false,
        },
    });
}

/// Best-effort one-shot hello + `goal`. Live `WAKU_DAEMON_ADDRESS` or
/// persisted `last_daemon_address`. Missing address is a no-op — fx ask /
/// fx acp / demo do not fake Goal. Own spawn key.
pub fn maybeSendGoal(model: *Model, fx: *Effects, session_id: u32, operation: protocol.GoalOperation) bool {
    const address = store.resolveDaemonMirrorAddress(model);
    if (address.len == 0) return false;
    const session = model.sessionById(session_id) orelse return false;
    var id_buf: [36]u8 = undefined;
    const wire_id = daemon_proxy.wireUuid(session.id, &id_buf);
    const runtime_id = if (protocol.isUsableRuntimeId(session.runtimeId()))
        session.runtimeId()
    else
        protocol.NIL_UUID;
    var stdin_buf: [4096]u8 = undefined;
    const stdin = daemon_proxy.writeGoalStdin(&stdin_buf, .{
        .token = model.daemonToken(),
        .session_id = wire_id,
        .runtime_id = runtime_id,
        .operation = operation,
    }) catch return false;

    const key = model.next_daemon_key;
    model.next_daemon_key += 1;
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
