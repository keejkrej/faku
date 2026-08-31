//! Sidecar stdout / ACP / daemon line handlers and fx-exit routing.
//!
//! `handleFxLine` / `handleAcpLine` / `handlePiJsonLine` /
//! `handleClaudeJsonLine` / `handleDaemonLine`, ACP apply helpers,
//! daemon goalUpdated apply, and `handleFxExit` live here. Maximize
//! spawn/exit helpers live in `maximize_window.zig`. Probe helpers
//! live in `fx_probe.zig`. Stream finish still comes from
//! `stream.zig`. Behavior is unchanged from the former `main` line
//! handlers except Pi `--mode json` and Claude `--output-format
//! stream-json` stdout, which are parsed as JSON events instead of
//! appended as prose.

const std = @import("std");
const native_sdk = @import("native_sdk");
const main = @import("main.zig");
const protocol = @import("protocol.zig");
const acp = @import("acp.zig");
const store = @import("store.zig");
const daemon_proxy = @import("daemon_proxy.zig");
const attach_helpers = @import("attach.zig");
const turn_stream = @import("stream.zig");
const maximize_window = @import("maximize_window.zig");
const git_branch = @import("git_branch.zig");
const git_checkout = @import("git_checkout.zig");
const persist = @import("persist.zig");
const git_dirty = @import("git_dirty.zig");
const git_numstat = @import("git_numstat.zig");
const git_ahead_behind = @import("git_ahead_behind.zig");
const git_remotes = @import("git_remotes.zig");
const git_toplevel = @import("git_toplevel.zig");
const git_common_dir = @import("git_common_dir.zig");
const git_commit = @import("git_commit.zig");
const review_diff = @import("review_diff.zig");
const file_mention = @import("file_mention.zig");
const skills = @import("skills.zig");
const pick_folder = @import("pick_folder.zig");
const reveal_folder = @import("reveal_folder.zig");
const open_terminal = @import("open_terminal.zig");
const open_editor = @import("open_editor.zig");

const Model = main.Model;
const Effects = main.Effects;
const Turn = main.Turn;
const Session = main.Session;
const max_line_keep = main.max_line_keep;
const max_fx_session_id = main.max_fx_session_id;
const max_body = main.max_body;
const fx_ask_key = main.fx_ask_key;
const maximize_window_key = maximize_window.maximize_window_key;
const pick_image_key = main.pick_image_key;
const pick_folder_key = main.pick_folder_key;
const reveal_folder_key = main.reveal_folder_key;
const open_terminal_key = main.open_terminal_key;
const open_editor_key = main.open_editor_key;
const writeFixed = main.writeFixed;
const takeFxAskSessionId = main.takeFxAskSessionId;
const handleMaximizeWindowExit = maximize_window.handleMaximizeWindowExit;

pub fn handleFxLine(model: *Model, fx: *Effects, line: native_sdk.EffectLine) void {
    if (model.git_branch_key != 0 and line.key == model.git_branch_key) {
        git_branch.applyLine(model, line);
        return;
    }
    if (model.git_branch_list_key != 0 and line.key == model.git_branch_list_key) {
        git_checkout.applyListLine(model, line);
        return;
    }
    if (model.git_dirty_key != 0 and line.key == model.git_dirty_key) {
        git_dirty.applyLine(model, line);
        return;
    }
    if (model.git_numstat_key != 0 and line.key == model.git_numstat_key) {
        git_numstat.applyLine(model, line);
        return;
    }
    if (model.git_ahead_behind_key != 0 and line.key == model.git_ahead_behind_key) {
        git_ahead_behind.applyLine(model, line);
        return;
    }
    if (model.git_remotes_key != 0 and line.key == model.git_remotes_key) {
        git_remotes.applyLine(model, line);
        return;
    }
    if (model.git_toplevel_key != 0 and line.key == model.git_toplevel_key) {
        git_toplevel.applyLine(model, line);
        return;
    }
    if (model.git_common_dir_key != 0 and line.key == model.git_common_dir_key) {
        git_common_dir.applyLine(model, line);
        return;
    }
    if (model.review_diff_key != 0 and line.key == model.review_diff_key) {
        review_diff.applyLine(model, line);
        return;
    }
    if (model.review_diff_hunk_key != 0 and line.key == model.review_diff_hunk_key) {
        review_diff.applyHunkLine(model, line);
        return;
    }
    if (model.file_mention_key != 0 and line.key == model.file_mention_key) {
        file_mention.applyLine(model, line);
        return;
    }
    if (model.skill_key != 0 and line.key == model.skill_key) {
        skills.applyLine(model, line);
        return;
    }
    if (model.git_push_key != 0 and line.key == model.git_push_key) {
        git_checkout.applyPushLine(model, line);
        return;
    }
    if (model.git_commit_numstat_key != 0 and line.key == model.git_commit_numstat_key) {
        git_commit.applyNumstatLine(model, line);
        return;
    }
    if (model.git_commit_generate_key != 0 and line.key == model.git_commit_generate_key) {
        git_commit.applyGenerateLine(model, line);
        return;
    }
    if (model.git_commit_key != 0 and line.key == model.git_commit_key) {
        git_commit.applyLine(model, line);
        return;
    }
    if (model.git_worktree_base_key != 0 and line.key == model.git_worktree_base_key) {
        git_checkout.applyWorktreeBaseLine(model, line);
        return;
    }
    if (line.key == pick_image_key) {
        attach_helpers.applyPickImageLine(model, fx, line);
        return;
    }
    if (line.key == pick_folder_key) {
        pick_folder.applyPickFolderLine(model, fx, line);
        return;
    }
    applyDaemonGoalLine(model, fx, line.line);
    if (model.daemon_load_key != 0 and line.key == model.daemon_load_key) {
        store.applyDaemonCatalogLine(model, line.line);
        store.maybeHydrateDaemonSession(model, fx, model.selected);
        return;
    }
    if (model.daemon_hydrate_key != 0 and line.key == model.daemon_hydrate_key) {
        store.applyDaemonHydrateLine(model, line.line);
        return;
    }
    if (model.phase != .streaming) return;
    if (line.key == model.daemon_spawn_key and model.daemon_spawn_key != 0) {
        handleDaemonLine(model, fx, line);
        return;
    }
    if (model.fx_spawn_key != 0 and line.key != model.fx_spawn_key) return;
    if (model.fx_spawn_key == 0 and line.key != fx_ask_key) return;
    if (model.fx_spawn_acp) {
        handleAcpLine(model, fx, line);
        return;
    }
    if (model.fx_spawn_pi_json) {
        handlePiJsonLine(model, fx, line);
        return;
    }
    if (model.fx_spawn_claude_json) {
        handleClaudeJsonLine(model, fx, line);
        return;
    }
    const keep = line.line[0..@min(line.line.len, max_line_keep)];
    var id_buf: [max_fx_session_id]u8 = undefined;
    if (takeFxAskSessionId(keep, &id_buf)) |session_id| {
        if (model.sessionById(model.streaming_session)) |session| {
            session.setFxSessionId(session_id);
            store.persistIfPossible(model, session.id, fx);
        }
        return;
    }
    const text = stripFxDiagnostics(keep);
    if (text.len == 0) return;
    if (model.turnById(model.stream_turn_id)) |turn| {
        if (turn.body_len > 0) model.appendToTurn(model.stream_turn_id, "\n");
    }
    model.appendToTurn(model.stream_turn_id, text);
}

fn handleAcpLine(model: *Model, fx: *Effects, line: native_sdk.EffectLine) void {
    const keep = line.line[0..@min(line.line.len, max_line_keep)];
    const parsed = acp.parseLine(keep);
    const minted = acp.mintedSessionId(parsed);
    if (minted.len > 0) {
        if (model.sessionById(model.streaming_session)) |session| {
            session.setFxSessionId(minted);
            store.persistIfPossible(model, session.id, fx);
        }
    }
    if (acp.usageUpdate(parsed)) |usage| {
        if (model.sessionById(model.streaming_session)) |session| {
            session.setContextUsage(usage.used, usage.size);
            store.persistIfPossible(model, session.id, fx);
        }
        return;
    }
    if (acp.currentModeUpdate(parsed)) |access_mode| {
        applyAcpCurrentMode(model, fx, access_mode);
        return;
    }
    if (acp.configModelUpdate(&parsed)) |config_update| {
        applyAcpConfigModel(model, fx, config_update);
        return;
    }
    if (acp.availableCommandsUpdate(&parsed)) |commands| {
        applyAcpAvailableCommands(model, fx, commands);
        return;
    }
    if (acp.sessionInfoTitle(parsed)) |title| {
        applyAcpSessionInfoTitle(model, fx, title);
        return;
    }
    if (acp.toolUpdate(&parsed)) |tool| {
        applyAcpToolUpdate(model, fx, tool);
        return;
    }
    if (acp.isAgentThoughtText(parsed)) {
        applyAcpThoughtChunk(model, fx, parsed.text);
        return;
    }
    if (acp.isAgentMessageText(parsed)) {
        const text = stripFxDiagnostics(parsed.text);
        if (text.len == 0) return;
        model.appendToTurn(model.stream_turn_id, text);
        return;
    }
    if (acp.isPromptResult(parsed) or (parsed.has_error and parsed.id != null)) {
        const drain = acp.promptSucceeded(parsed);
        if (model.fx_spawn_key != 0) fx.cancel(model.fx_spawn_key);
        turn_stream.finishStream(model, fx, drain);
    }
}

const PiJsonKind = enum { ignore, session, text_delta, message_end };

const PiJsonParsed = struct {
    kind: PiJsonKind = .ignore,
    session_id: []const u8 = "",
    text: []const u8 = "",
};

/// Official Pi `--mode json` event line. Documented at
/// earendil-works/pi `packages/coding-agent/docs/json.md`. Unknown
/// types, malformed JSON, and non-objects are `.ignore` (never
/// assistant prose). `text_delta` is the live stream.
/// `message_end` carries the authoritative assistant message for
/// fallback when no deltas arrived. `session.id` reuses the existing
/// `fx_session_id` slot.
fn parsePiJsonLine(line: []const u8, allocator: std.mem.Allocator) PiJsonParsed {
    const trimmed = std.mem.trim(u8, line, " \t\r\n");
    if (trimmed.len < 2 or trimmed[0] != '{') return .{};
    const root = std.json.parseFromSliceLeaky(std.json.Value, allocator, trimmed, .{}) catch return .{};
    const obj = switch (root) {
        .object => |o| o,
        else => return .{},
    };
    const type_val = obj.get("type") orelse return .{};
    const type_str = switch (type_val) {
        .string => |s| s,
        else => return .{},
    };
    if (std.mem.eql(u8, type_str, "session")) {
        const id_val = obj.get("id") orelse return .{};
        const id = switch (id_val) {
            .string => |s| s,
            else => return .{},
        };
        if (id.len == 0) return .{};
        return .{ .kind = .session, .session_id = id };
    }
    if (std.mem.eql(u8, type_str, "message_update")) {
        const ev_val = obj.get("assistantMessageEvent") orelse return .{};
        const ev = switch (ev_val) {
            .object => |o| o,
            else => return .{},
        };
        const ev_type_val = ev.get("type") orelse return .{};
        const ev_type = switch (ev_type_val) {
            .string => |s| s,
            else => return .{},
        };
        if (!std.mem.eql(u8, ev_type, "text_delta")) return .{};
        const delta_val = ev.get("delta") orelse return .{};
        const delta = switch (delta_val) {
            .string => |s| s,
            else => return .{},
        };
        if (delta.len == 0) return .{};
        return .{ .kind = .text_delta, .text = delta };
    }
    if (std.mem.eql(u8, type_str, "message_end")) {
        const message = obj.get("message") orelse return .{};
        const text = extractPiAssistantText(message, allocator);
        if (text.len == 0) return .{};
        return .{ .kind = .message_end, .text = text };
    }
    return .{};
}

fn extractPiAssistantText(message: std.json.Value, allocator: std.mem.Allocator) []const u8 {
    const obj = switch (message) {
        .object => |o| o,
        else => return "",
    };
    if (obj.get("role")) |role_val| {
        const role = switch (role_val) {
            .string => |s| s,
            else => return "",
        };
        if (!std.mem.eql(u8, role, "assistant")) return "";
    }
    const content = obj.get("content") orelse return "";
    switch (content) {
        .string => |s| return s,
        .array => |arr| {
            var parts: [8][]const u8 = undefined;
            var n: usize = 0;
            var total: usize = 0;
            for (arr.items) |item| {
                const part = piTextContent(item);
                if (part.len == 0) continue;
                if (n >= parts.len) break;
                parts[n] = part;
                n += 1;
                total += part.len;
            }
            if (n == 0) return "";
            if (n == 1) return parts[0];
            const out = allocator.alloc(u8, total) catch return "";
            var i: usize = 0;
            for (parts[0..n]) |part| {
                @memcpy(out[i..][0..part.len], part);
                i += part.len;
            }
            return out;
        },
        else => return "",
    }
}

fn piTextContent(item: std.json.Value) []const u8 {
    const obj = switch (item) {
        .object => |o| o,
        else => return "",
    };
    const type_val = obj.get("type") orelse return "";
    const type_str = switch (type_val) {
        .string => |s| s,
        else => return "",
    };
    if (!std.mem.eql(u8, type_str, "text")) return "";
    const text_val = obj.get("text") orelse return "";
    return switch (text_val) {
        .string => |s| s,
        else => "",
    };
}

fn handlePiJsonLine(model: *Model, fx: *Effects, line: native_sdk.EffectLine) void {
    const keep = line.line[0..@min(line.line.len, max_line_keep)];
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const parsed = parsePiJsonLine(keep, arena_state.allocator());
    switch (parsed.kind) {
        .ignore => {},
        .session => {
            if (parsed.session_id.len == 0) return;
            if (model.sessionById(model.streaming_session)) |session| {
                session.setFxSessionId(parsed.session_id);
                store.persistIfPossible(model, session.id, fx);
            }
        },
        .text_delta => {
            if (parsed.text.len == 0) return;
            model.appendToTurn(model.stream_turn_id, parsed.text);
        },
        .message_end => {
            if (parsed.text.len == 0) return;
            if (model.turnById(model.stream_turn_id)) |turn| {
                if (turn.body_len > 0) return;
            }
            model.appendToTurn(model.stream_turn_id, parsed.text);
        },
    }
}

const ClaudeJsonKind = enum { ignore, session, text_delta, result };

const ClaudeJsonParsed = struct {
    kind: ClaudeJsonKind = .ignore,
    session_id: []const u8 = "",
    text: []const u8 = "",
};

fn jsonStringField(obj: anytype, key: []const u8) ?[]const u8 {
    const val = obj.get(key) orelse return null;
    return switch (val) {
        .string => |s| s,
        else => null,
    };
}

fn jsonObjectField(obj: anytype, key: []const u8) ?@TypeOf(obj) {
    const val = obj.get(key) orelse return null;
    return switch (val) {
        .object => |o| o,
        else => null,
    };
}

/// Official Claude `--output-format stream-json` NDJSON line.
/// Documented at code.claude.com/docs/en/headless (streaming recipe
/// plus jq filter
/// `select(.type == "stream_event" and .event.delta.type? == "text_delta") | .event.delta.text`).
/// Unknown types, malformed JSON, and non-objects are `.ignore`
/// (never assistant prose). `text_delta` is the live stream. `result`
/// carries the final response text for fallback when no deltas
/// arrived. `session_id` from a `result` or `system`/`init` event
/// reuses the existing `fx_session_id` slot when the field is present.
fn parseClaudeJsonLine(line: []const u8, allocator: std.mem.Allocator) ClaudeJsonParsed {
    const trimmed = std.mem.trim(u8, line, " \t\r\n");
    if (trimmed.len < 2 or trimmed[0] != '{') return .{};
    const root = std.json.parseFromSliceLeaky(std.json.Value, allocator, trimmed, .{}) catch return .{};
    const obj = switch (root) {
        .object => |o| o,
        else => return .{},
    };
    const type_str = jsonStringField(obj, "type") orelse return .{};
    if (std.mem.eql(u8, type_str, "stream_event")) {
        const event = jsonObjectField(obj, "event") orelse return .{};
        const delta = jsonObjectField(event, "delta") orelse return .{};
        const delta_type = jsonStringField(delta, "type") orelse return .{};
        if (!std.mem.eql(u8, delta_type, "text_delta")) return .{};
        const text = jsonStringField(delta, "text") orelse return .{};
        if (text.len == 0) return .{};
        return .{ .kind = .text_delta, .text = text };
    }
    if (std.mem.eql(u8, type_str, "system")) {
        const subtype = jsonStringField(obj, "subtype") orelse return .{};
        if (!std.mem.eql(u8, subtype, "init")) return .{};
        const session_id = jsonStringField(obj, "session_id") orelse return .{};
        if (session_id.len == 0) return .{};
        return .{ .kind = .session, .session_id = session_id };
    }
    if (std.mem.eql(u8, type_str, "result")) {
        const session_id = jsonStringField(obj, "session_id") orelse "";
        const text = jsonStringField(obj, "result") orelse "";
        if (session_id.len == 0 and text.len == 0) return .{};
        return .{ .kind = .result, .session_id = session_id, .text = text };
    }
    return .{};
}

fn handleClaudeJsonLine(model: *Model, fx: *Effects, line: native_sdk.EffectLine) void {
    const keep = line.line[0..@min(line.line.len, max_line_keep)];
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const parsed = parseClaudeJsonLine(keep, arena_state.allocator());
    if (parsed.session_id.len > 0) {
        if (model.sessionById(model.streaming_session)) |session| {
            session.setFxSessionId(parsed.session_id);
            store.persistIfPossible(model, session.id, fx);
        }
    }
    switch (parsed.kind) {
        .ignore, .session => {},
        .text_delta => {
            if (parsed.text.len == 0) return;
            model.appendToTurn(model.stream_turn_id, parsed.text);
        },
        .result => {
            if (parsed.text.len == 0) return;
            if (model.turnById(model.stream_turn_id)) |turn| {
                if (turn.body_len > 0) return;
            }
            model.appendToTurn(model.stream_turn_id, parsed.text);
        },
    }
}

/// Official ACP `current_mode_update`. Reverse map is the inverse of
/// `session/set_mode`: fx `ask` → `ask`, fx `code` → `fullAccess`.
fn applyAcpCurrentMode(model: *Model, fx: *Effects, access_mode: []const u8) void {
    const session = model.sessionById(model.streaming_session) orelse return;
    session.setAccessMode(access_mode);
    store.persistIfPossible(model, session.id, fx);
}

/// Official ACP `config_option_update` / `session/set_config_option`
/// result for `id: "model"`. Empty `currentValue` clears the session
/// model so the chip stays `FX_MODEL`. A present `options` array
/// replaces the stored catalog (empty clears).
fn applyAcpConfigModel(model: *Model, fx: *Effects, config_update: acp.ConfigModelUpdate) void {
    const session = model.sessionById(model.streaming_session) orelse return;
    if (config_update.value) |value| {
        session.setModel(value);
    }
    if (config_update.has_options) {
        session.replaceModelOptions(config_update.options);
    }
    store.persistIfPossible(model, session.id, fx);
}

/// Official ACP `available_commands_update`. Replaces the session list
/// (empty clears). Names and descriptions only; Composer Commands can
/// insert `/name ` into the draft. No execution.
fn applyAcpAvailableCommands(model: *Model, fx: *Effects, commands: []const acp.ParsedCommand) void {
    const session = model.sessionById(model.streaming_session) orelse return;
    session.replaceAvailableCommands(commands);
    if (session.id == model.selected and session.available_command_count == 0) {
        model.closeCommands();
    }
    store.persistIfPossible(model, session.id, fx);
}

/// Official ACP `session_info_update` `title`. Same merge-only catalog
/// write as mode / model / commands. Empty titles never reach here.
fn applyAcpSessionInfoTitle(model: *Model, fx: *Effects, title: []const u8) void {
    const session = model.sessionById(model.streaming_session) orelse return;
    session.setTitle(title);
    store.persistIfPossible(model, session.id, fx);
}

fn applyAcpToolUpdate(model: *Model, fx: *Effects, tool: acp.ToolUpdate) void {
    const session_id = model.streaming_session;
    if (session_id == 0) return;
    if (findToolTurn(model, session_id, tool.tool_call_id)) |turn| {
        if (tool.title.len > 0) writeFixed(&turn.tool_title_storage, &turn.tool_title_len, tool.title);
        if (tool.kind.len > 0) writeFixed(&turn.tool_kind_storage, &turn.tool_kind_len, tool.kind);
        if (tool.status.len > 0) writeFixed(&turn.tool_status_storage, &turn.tool_status_len, tool.status);
        if (tool.has_content) writeFixed(&turn.tool_content_storage, &turn.tool_content_len, tool.content);
        refreshToolTurnText(turn);
    } else {
        var text_buf: [max_body]u8 = undefined;
        const text = acp.toolTurnBody(&text_buf, tool.title, tool.kind, tool.status, if (tool.has_content) tool.content else "");
        const turn_id = model.appendTurn(session_id, .tool, text);
        const turn = model.turnById(turn_id) orelse return;
        writeFixed(&turn.tool_call_id_storage, &turn.tool_call_id_len, tool.tool_call_id);
        writeFixed(&turn.tool_title_storage, &turn.tool_title_len, tool.title);
        writeFixed(&turn.tool_kind_storage, &turn.tool_kind_len, tool.kind);
        writeFixed(&turn.tool_status_storage, &turn.tool_status_len, tool.status);
        if (tool.has_content) writeFixed(&turn.tool_content_storage, &turn.tool_content_len, tool.content);
        refreshToolTurnText(turn);
    }
    store.persistIfPossible(model, session_id, fx);
}

/// Thought text stays off the assistant markdown turn. First chunk in
/// this stream appends a reasoning row; later chunks append to that row.
fn applyAcpThoughtChunk(model: *Model, fx: *Effects, text: []const u8) void {
    const cleaned = stripFxDiagnostics(text);
    if (cleaned.len == 0) return;
    const session_id = model.streaming_session;
    if (session_id == 0) return;
    if (findLiveReasoningTurn(model, session_id)) |turn| {
        model.appendToTurn(turn.id, cleaned);
    } else {
        _ = model.appendTurn(session_id, .reasoning, cleaned);
    }
    store.persistIfPossible(model, session_id, fx);
}

/// fx prints skill-discovery warnings on stdout, sometimes glued to the
/// first reply (`…trace logHi! How can I help?`). Drop that prefix so
/// it never becomes turn text. A warning-only chunk is skipped entirely.
pub fn stripFxDiagnostics(text: []const u8) []const u8 {
    const prefix = "skill discovery warning:";
    const has_warning = std.mem.indexOf(u8, text, prefix) != null;
    const has_trace = std.mem.indexOf(u8, text, "relaunch with FX_TRACE=1") != null;
    if (!has_warning and !has_trace) return text;
    var rest = text;
    if (std.mem.indexOf(u8, rest, prefix)) |start| rest = rest[start..];
    const tail_mark = "write a trace log";
    if (std.mem.indexOf(u8, rest, tail_mark)) |idx| {
        return std.mem.trim(u8, rest[idx + tail_mark.len ..], " \t\r\n");
    }
    if (has_warning or has_trace) return "";
    return text;
}

/// Only the reasoning row created after this stream's assistant turn.
/// Earlier prompts keep their own thought text.
fn findLiveReasoningTurn(model: *Model, session_id: u32) ?*Turn {
    var found: ?*Turn = null;
    for (model.turn_store[0..model.turn_count]) |*turn| {
        if (turn.session_id != session_id or turn.role != .reasoning) continue;
        if (model.stream_turn_id != 0 and turn.id < model.stream_turn_id) continue;
        found = turn;
    }
    return found;
}

fn findToolTurn(model: *Model, session_id: u32, tool_call_id: []const u8) ?*Turn {
    if (tool_call_id.len == 0) return null;
    for (model.turn_store[0..model.turn_count]) |*turn| {
        if (turn.session_id != session_id or turn.role != .tool) continue;
        if (std.mem.eql(u8, turn.toolCallId(), tool_call_id)) return turn;
    }
    return null;
}

fn refreshToolTurnText(turn: *Turn) void {
    var text_buf: [max_body]u8 = undefined;
    const text = acp.toolTurnBody(&text_buf, turn.toolTitle(), turn.toolKind(), turn.toolStatus(), turn.toolContent());
    writeFixed(&turn.body_storage, &turn.body_len, text);
}

/// Apply a `goalUpdated` driver event from any daemon sidecar line.
/// One-shot may miss the event; last-known local fields stay. Parses
/// documented `tokenBudget` / `tokensUsed` / `timeUsedSeconds` only.
/// JSON null payload clears objective, status, and usage.
fn applyDaemonGoalLine(model: *Model, fx: *Effects, line: []const u8) void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const parsed = protocol.parseServerFrame(arena_state.allocator(), line);
    if (parsed.frame != .event) return;
    if (parsed.event_kind != .goal_updated) return;
    const session = goalSessionForEvent(model, parsed.session_id) orelse return;
    if (parsed.goal_cleared) {
        session.clearThreadGoal();
    } else {
        if (parsed.goal_has_objective) session.setThreadGoalObjective(parsed.goal_objective);
        if (parsed.goal_has_status) session.setThreadGoalStatus(parsed.goal_status);
        session.applyThreadGoalUsage(
            if (parsed.goal_has_token_budget and !parsed.goal_token_budget_null) parsed.goal_token_budget else null,
            parsed.goal_token_budget_null,
            parsed.goal_has_token_budget,
            if (parsed.goal_has_tokens_used) parsed.goal_tokens_used else null,
            if (parsed.goal_has_time_used_seconds) parsed.goal_time_used_seconds else null,
        );
    }
    store.persistIfPossible(model, session.id, fx);
}

fn goalSessionForEvent(model: *Model, wire_id: []const u8) ?*Session {
    if (daemon_proxy.localIdFromWire(wire_id)) |local_id| {
        if (model.sessionById(local_id)) |session| return session;
    }
    if (model.streaming_session != 0) {
        if (model.sessionById(model.streaming_session)) |session| return session;
    }
    return model.sessionById(model.selected);
}

fn handleDaemonLine(model: *Model, fx: *Effects, line: native_sdk.EffectLine) void {
    const keep = line.line[0..@min(line.line.len, max_line_keep)];
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const parsed = protocol.parseServerFrame(arena_state.allocator(), keep);
    switch (parsed.frame) {
        .event => {
            if (parsed.event_kind == .text_delta and parsed.text_delta.len > 0) {
                model.appendToTurn(model.stream_turn_id, parsed.text_delta);
            } else if (parsed.event_kind == .turn_finished) {
                turn_stream.finishStream(model, fx, parsed.turn_success);
            } else if (parsed.event_kind == .@"error") {
                turn_stream.finishStream(model, fx, false);
            }
        },
        .response => persistDaemonRuntimeId(model, fx, parsed),
        .rejected => turn_stream.finishStream(model, fx, false),
        else => {},
    }
}

fn persistDaemonRuntimeId(model: *Model, fx: *Effects, parsed: protocol.ParsedServer) void {
    if (!parsed.response_ok) return;
    const session = model.sessionById(model.streaming_session) orelse return;
    const is_runtime = std.mem.eql(u8, parsed.payload_type, "sessionRuntime");
    const is_started = std.mem.eql(u8, parsed.payload_type, "started");
    if (!is_runtime and !is_started) return;
    session.supports_steer = parsed.supports_steer;
    if (is_runtime and protocol.isUsableRuntimeId(parsed.runtime_id)) {
        session.setRuntimeId(parsed.runtime_id);
        store.persistIfPossible(model, session.id, fx);
    }
}

pub fn handleFxExit(model: *Model, fx: *Effects, exit: native_sdk.EffectExit) void {
    if (model.git_branch_key != 0 and exit.key == model.git_branch_key) {
        git_branch.handleExit(model, fx, exit);
        return;
    }
    if (model.git_branch_list_key != 0 and exit.key == model.git_branch_list_key) {
        git_checkout.handleListExit(model, exit);
        return;
    }
    if (model.git_checkout_key != 0 and exit.key == model.git_checkout_key) {
        git_checkout.handleCheckoutExit(model, fx, exit);
        return;
    }
    if (model.git_create_key != 0 and exit.key == model.git_create_key) {
        git_checkout.handleCreateExit(model, fx, exit);
        return;
    }
    if (model.git_delete_key != 0 and exit.key == model.git_delete_key) {
        git_checkout.handleDeleteExit(model, fx, exit);
        return;
    }
    if (model.git_fetch_key != 0 and exit.key == model.git_fetch_key) {
        git_checkout.handleFetchExit(model, fx, exit);
        return;
    }
    if (model.git_push_key != 0 and exit.key == model.git_push_key) {
        git_checkout.handlePushExit(model, fx, exit);
        return;
    }
    if (model.git_commit_numstat_key != 0 and exit.key == model.git_commit_numstat_key) {
        git_commit.handleNumstatExit(model, exit);
        return;
    }
    if (model.git_commit_generate_key != 0 and exit.key == model.git_commit_generate_key) {
        git_commit.handleGenerateExit(model, fx, exit);
        return;
    }
    if (model.git_commit_key != 0 and exit.key == model.git_commit_key) {
        git_commit.handleCommitExit(model, fx, exit);
        return;
    }
    if (model.git_worktree_base_key != 0 and exit.key == model.git_worktree_base_key) {
        git_checkout.handleWorktreeBaseExit(model, fx, exit);
        return;
    }
    if (model.git_worktree_add_key != 0 and exit.key == model.git_worktree_add_key) {
        if (git_checkout.handleWorktreeAddExit(model, fx, exit)) {
            persist.persistComposerProject(model, fx);
        }
        return;
    }
    if (model.git_dirty_key != 0 and exit.key == model.git_dirty_key) {
        git_dirty.handleExit(model, exit);
        return;
    }
    if (model.git_numstat_key != 0 and exit.key == model.git_numstat_key) {
        git_numstat.handleExit(model, exit);
        return;
    }
    if (model.git_ahead_behind_key != 0 and exit.key == model.git_ahead_behind_key) {
        git_ahead_behind.handleExit(model, exit);
        return;
    }
    if (model.git_remotes_key != 0 and exit.key == model.git_remotes_key) {
        git_remotes.handleExit(model, exit);
        return;
    }
    if (model.git_toplevel_key != 0 and exit.key == model.git_toplevel_key) {
        git_toplevel.handleExit(model, exit);
        return;
    }
    if (model.git_common_dir_key != 0 and exit.key == model.git_common_dir_key) {
        git_common_dir.handleExit(model, exit);
        return;
    }
    if (model.review_diff_key != 0 and exit.key == model.review_diff_key) {
        review_diff.handleExit(model, fx, exit);
        return;
    }
    if (model.review_diff_hunk_key != 0 and exit.key == model.review_diff_hunk_key) {
        review_diff.handleHunkExit(model, fx, exit);
        return;
    }
    if (model.file_mention_key != 0 and exit.key == model.file_mention_key) {
        file_mention.handleExit(model, fx, exit);
        return;
    }
    if (model.skill_key != 0 and exit.key == model.skill_key) {
        skills.handleExit(model, fx, exit);
        return;
    }
    if (exit.key == maximize_window_key) {
        handleMaximizeWindowExit(model, fx, exit);
        return;
    }
    if (exit.key == pick_image_key) {
        attach_helpers.handlePickImageExit(model, fx, exit);
        return;
    }
    if (exit.key == pick_folder_key) {
        pick_folder.handlePickFolderExit(model, fx, exit);
        return;
    }
    if (exit.key == reveal_folder_key) {
        reveal_folder.handleRevealFolderExit(model, exit);
        return;
    }
    if (exit.key == open_terminal_key) {
        open_terminal.handleOpenTerminalExit(model, fx, exit);
        return;
    }
    if (exit.key == open_editor_key) {
        open_editor.handleOpenEditorExit(model, fx, exit);
        return;
    }
    if (model.daemon_load_key != 0 and exit.key == model.daemon_load_key) {
        model.daemon_load_key = 0;
        model.pending_daemon_catalog = false;
        return;
    }
    if (model.daemon_hydrate_key != 0 and exit.key == model.daemon_hydrate_key) {
        model.daemon_hydrate_key = 0;
        model.daemon_hydrate_session = 0;
        return;
    }
    const daemon = model.daemon_spawn_key != 0 and exit.key == model.daemon_spawn_key;
    const fx_child = model.fx_spawn_key != 0 and exit.key == model.fx_spawn_key;
    if (exit.key != fx_ask_key and !daemon and !fx_child) return;
    if (fx_child or exit.key == fx_ask_key) {
        if (model.fx_spawn_key != 0 and exit.key != model.fx_spawn_key) return;
        model.fx_spawn_live = false;
        if (model.phase != .streaming) {
            if (exit.key == model.fx_spawn_key) model.fx_spawn_key = 0;
            return;
        }
        if (exit.key == model.fx_spawn_key) model.fx_spawn_key = 0;
    }
    if (model.phase != .streaming) return;
    const success = exit.reason == .exited and exit.code == 0;
    turn_stream.finishStream(model, fx, success);
}

fn piJsonTurnText(model: *Model, turn_id: u32) []const u8 {
    const turn = model.turnById(turn_id) orelse return "";
    return turn.text();
}

test "pi json parser: text_delta extracts; unknown and malformed ignored" {
    const testing = std.testing;
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const alloc = arena_state.allocator();

    const delta = parsePiJsonLine(
        "{\"type\":\"message_update\",\"usage\":{},\"assistantMessageEvent\":{\"type\":\"text_delta\",\"contentIndex\":0,\"delta\":\"Hello\"}}",
        alloc,
    );
    try testing.expectEqual(PiJsonKind.text_delta, delta.kind);
    try testing.expectEqualStrings("Hello", delta.text);

    const unknown = parsePiJsonLine("{\"type\":\"agent_start\"}", alloc);
    try testing.expectEqual(PiJsonKind.ignore, unknown.kind);
    try testing.expectEqualStrings("", unknown.text);

    const turn_start = parsePiJsonLine("{\"type\":\"turn_start\"}", alloc);
    try testing.expectEqual(PiJsonKind.ignore, turn_start.kind);

    const tool = parsePiJsonLine("{\"type\":\"tool_execution_start\",\"toolCallId\":\"1\",\"toolName\":\"bash\",\"args\":{}}", alloc);
    try testing.expectEqual(PiJsonKind.ignore, tool.kind);

    const thinking = parsePiJsonLine(
        "{\"type\":\"message_update\",\"assistantMessageEvent\":{\"type\":\"thinking_delta\",\"delta\":\"secret\"}}",
        alloc,
    );
    try testing.expectEqual(PiJsonKind.ignore, thinking.kind);

    const malformed = parsePiJsonLine("not json {", alloc);
    try testing.expectEqual(PiJsonKind.ignore, malformed.kind);

    const raw_object = parsePiJsonLine("{\"type\":\"agent_end\",\"messages\":[]}", alloc);
    try testing.expectEqual(PiJsonKind.ignore, raw_object.kind);
}

test "pi json parser: session id and message_end assistant text" {
    const testing = std.testing;
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const alloc = arena_state.allocator();

    const session = parsePiJsonLine(
        "{\"type\":\"session\",\"version\":3,\"id\":\"11111111-2222-3333-4444-555555555555\",\"timestamp\":\"t\",\"cwd\":\"/tmp\"}",
        alloc,
    );
    try testing.expectEqual(PiJsonKind.session, session.kind);
    try testing.expectEqualStrings("11111111-2222-3333-4444-555555555555", session.session_id);

    const empty_id = parsePiJsonLine("{\"type\":\"session\",\"id\":\"\"}", alloc);
    try testing.expectEqual(PiJsonKind.ignore, empty_id.kind);

    const ended = parsePiJsonLine(
        "{\"type\":\"message_end\",\"message\":{\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"final answer\"}]}}",
        alloc,
    );
    try testing.expectEqual(PiJsonKind.message_end, ended.kind);
    try testing.expectEqualStrings("final answer", ended.text);

    const user_end = parsePiJsonLine(
        "{\"type\":\"message_end\",\"message\":{\"role\":\"user\",\"content\":\"hello\"}}",
        alloc,
    );
    try testing.expectEqual(PiJsonKind.ignore, user_end.kind);
}

test "pi json apply: text_delta appends; raw JSON is not assistant prose" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    const sid = model.addSession("pi json", .pi);
    const turn_id = model.appendTurn(sid, .assistant, "");
    model.phase = .streaming;
    model.stream_turn_id = turn_id;
    model.streaming_session = sid;
    model.fx_spawn_pi_json = true;

    handleFxLine(&model, &fx, .{ .key = fx_ask_key, .line = "{\"type\":\"agent_start\"}" });
    try testing.expectEqualStrings("", piJsonTurnText(&model, turn_id));

    handleFxLine(&model, &fx, .{ .key = fx_ask_key, .line = "not json" });
    try testing.expectEqualStrings("", piJsonTurnText(&model, turn_id));

    handleFxLine(&model, &fx, .{
        .key = fx_ask_key,
        .line = "{\"type\":\"message_update\",\"assistantMessageEvent\":{\"type\":\"text_delta\",\"delta\":\"Hel\"}}",
    });
    try testing.expectEqualStrings("Hel", piJsonTurnText(&model, turn_id));

    handleFxLine(&model, &fx, .{
        .key = fx_ask_key,
        .line = "{\"type\":\"message_update\",\"assistantMessageEvent\":{\"type\":\"text_delta\",\"delta\":\"lo\"}}",
    });
    try testing.expectEqualStrings("Hello", piJsonTurnText(&model, turn_id));

    handleFxLine(&model, &fx, .{
        .key = fx_ask_key,
        .line = "{\"type\":\"message_end\",\"message\":{\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"Hello world\"}]}}",
    });
    try testing.expectEqualStrings("Hello", piJsonTurnText(&model, turn_id));

    handleFxLine(&model, &fx, .{
        .key = fx_ask_key,
        .line = "{\"type\":\"session\",\"id\":\"pi-sess-1\"}",
    });
    try testing.expectEqualStrings("pi-sess-1", model.sessionById(sid).?.fxSessionId());
}

test "pi json apply: message_end fallback only when no text_delta" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    const sid = model.addSession("pi fallback", .pi);
    const turn_id = model.appendTurn(sid, .assistant, "");
    model.phase = .streaming;
    model.stream_turn_id = turn_id;
    model.streaming_session = sid;
    model.fx_spawn_pi_json = true;

    handleFxLine(&model, &fx, .{
        .key = fx_ask_key,
        .line = "{\"type\":\"message_end\",\"message\":{\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"only end\"}]}}",
    });
    try testing.expectEqualStrings("only end", piJsonTurnText(&model, turn_id));
}

test "claude json parser: stream_event text_delta extracts; unknown and malformed ignored" {
    const testing = std.testing;
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const alloc = arena_state.allocator();

    const delta = parseClaudeJsonLine(
        "{\"type\":\"stream_event\",\"event\":{\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Hello\"}}}",
        alloc,
    );
    try testing.expectEqual(ClaudeJsonKind.text_delta, delta.kind);
    try testing.expectEqualStrings("Hello", delta.text);

    const thinking = parseClaudeJsonLine(
        "{\"type\":\"stream_event\",\"event\":{\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"thinking_delta\",\"thinking\":\"secret\"}}}",
        alloc,
    );
    try testing.expectEqual(ClaudeJsonKind.ignore, thinking.kind);

    const message_start = parseClaudeJsonLine(
        "{\"type\":\"stream_event\",\"event\":{\"type\":\"message_start\",\"message\":{\"role\":\"assistant\"}}}",
        alloc,
    );
    try testing.expectEqual(ClaudeJsonKind.ignore, message_start.kind);

    const assistant = parseClaudeJsonLine(
        "{\"type\":\"assistant\",\"message\":{\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"full\"}]}}",
        alloc,
    );
    try testing.expectEqual(ClaudeJsonKind.ignore, assistant.kind);
    try testing.expectEqualStrings("", assistant.text);

    const system_retry = parseClaudeJsonLine(
        "{\"type\":\"system\",\"subtype\":\"api_retry\",\"session_id\":\"retry-sess\",\"attempt\":1}",
        alloc,
    );
    try testing.expectEqual(ClaudeJsonKind.ignore, system_retry.kind);
    try testing.expectEqualStrings("", system_retry.session_id);

    const malformed = parseClaudeJsonLine("not json {", alloc);
    try testing.expectEqual(ClaudeJsonKind.ignore, malformed.kind);

    const array_line = parseClaudeJsonLine("[{\"type\":\"stream_event\"}]", alloc);
    try testing.expectEqual(ClaudeJsonKind.ignore, array_line.kind);

    const empty_delta = parseClaudeJsonLine(
        "{\"type\":\"stream_event\",\"event\":{\"delta\":{\"type\":\"text_delta\",\"text\":\"\"}}}",
        alloc,
    );
    try testing.expectEqual(ClaudeJsonKind.ignore, empty_delta.kind);
}

test "claude json parser: result fallback text and init/result session_id" {
    const testing = std.testing;
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const alloc = arena_state.allocator();

    const init = parseClaudeJsonLine(
        "{\"type\":\"system\",\"subtype\":\"init\",\"session_id\":\"claude-sess-1\",\"cwd\":\"/tmp\",\"model\":\"claude-sonnet\"}",
        alloc,
    );
    try testing.expectEqual(ClaudeJsonKind.session, init.kind);
    try testing.expectEqualStrings("claude-sess-1", init.session_id);

    const init_empty = parseClaudeJsonLine(
        "{\"type\":\"system\",\"subtype\":\"init\",\"session_id\":\"\"}",
        alloc,
    );
    try testing.expectEqual(ClaudeJsonKind.ignore, init_empty.kind);

    const init_no_id = parseClaudeJsonLine(
        "{\"type\":\"system\",\"subtype\":\"init\",\"cwd\":\"/tmp\"}",
        alloc,
    );
    try testing.expectEqual(ClaudeJsonKind.ignore, init_no_id.kind);

    const ended = parseClaudeJsonLine(
        "{\"type\":\"result\",\"subtype\":\"success\",\"result\":\"final answer\",\"session_id\":\"claude-sess-2\",\"total_cost_usd\":0.01}",
        alloc,
    );
    try testing.expectEqual(ClaudeJsonKind.result, ended.kind);
    try testing.expectEqualStrings("final answer", ended.text);
    try testing.expectEqualStrings("claude-sess-2", ended.session_id);

    const result_no_text = parseClaudeJsonLine(
        "{\"type\":\"result\",\"session_id\":\"claude-sess-3\"}",
        alloc,
    );
    try testing.expectEqual(ClaudeJsonKind.result, result_no_text.kind);
    try testing.expectEqualStrings("", result_no_text.text);
    try testing.expectEqualStrings("claude-sess-3", result_no_text.session_id);

    const result_empty = parseClaudeJsonLine("{\"type\":\"result\"}", alloc);
    try testing.expectEqual(ClaudeJsonKind.ignore, result_empty.kind);
}

test "claude json apply: text_delta appends; raw JSON is not assistant prose" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    const sid = model.addSession("claude json", .claude);
    const turn_id = model.appendTurn(sid, .assistant, "");
    model.phase = .streaming;
    model.stream_turn_id = turn_id;
    model.streaming_session = sid;
    model.fx_spawn_claude_json = true;

    handleFxLine(&model, &fx, .{
        .key = fx_ask_key,
        .line = "{\"type\":\"system\",\"subtype\":\"init\",\"session_id\":\"claude-init-1\"}",
    });
    try testing.expectEqualStrings("", piJsonTurnText(&model, turn_id));
    try testing.expectEqualStrings("claude-init-1", model.sessionById(sid).?.fxSessionId());

    handleFxLine(&model, &fx, .{ .key = fx_ask_key, .line = "{\"type\":\"assistant\",\"message\":{}}" });
    try testing.expectEqualStrings("", piJsonTurnText(&model, turn_id));

    handleFxLine(&model, &fx, .{ .key = fx_ask_key, .line = "not json" });
    try testing.expectEqualStrings("", piJsonTurnText(&model, turn_id));

    handleFxLine(&model, &fx, .{
        .key = fx_ask_key,
        .line = "{\"type\":\"stream_event\",\"event\":{\"delta\":{\"type\":\"text_delta\",\"text\":\"Hel\"}}}",
    });
    try testing.expectEqualStrings("Hel", piJsonTurnText(&model, turn_id));

    handleFxLine(&model, &fx, .{
        .key = fx_ask_key,
        .line = "{\"type\":\"stream_event\",\"event\":{\"delta\":{\"type\":\"text_delta\",\"text\":\"lo\"}}}",
    });
    try testing.expectEqualStrings("Hello", piJsonTurnText(&model, turn_id));

    handleFxLine(&model, &fx, .{
        .key = fx_ask_key,
        .line = "{\"type\":\"result\",\"result\":\"Hello world\",\"session_id\":\"claude-result-1\"}",
    });
    try testing.expectEqualStrings("Hello", piJsonTurnText(&model, turn_id));
    try testing.expectEqualStrings("claude-result-1", model.sessionById(sid).?.fxSessionId());
}

test "claude json apply: result fallback only when no text_delta" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    const sid = model.addSession("claude fallback", .claude);
    const turn_id = model.appendTurn(sid, .assistant, "");
    model.phase = .streaming;
    model.stream_turn_id = turn_id;
    model.streaming_session = sid;
    model.fx_spawn_claude_json = true;

    handleFxLine(&model, &fx, .{
        .key = fx_ask_key,
        .line = "{\"type\":\"result\",\"result\":\"only result\",\"session_id\":\"claude-fb-1\"}",
    });
    try testing.expectEqualStrings("only result", piJsonTurnText(&model, turn_id));
    try testing.expectEqualStrings("claude-fb-1", model.sessionById(sid).?.fxSessionId());
}
