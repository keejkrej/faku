//! Agent Client Protocol (ACP) JSON-RPC 2.0 helpers for one-shot `fx acp`.
//!
//! Official methods (https://fx.sh/docs/using-fx/acp): initialize,
//! session/new, session/load, session/resume, session/close, session/list,
//! session/prompt, session/cancel, session/set_config_option, session/set_mode.
//! fx reports protocol version 1. Each connection has one active session
//! and one active prompt.
//!
//! This cut writes one NDJSON stdin buffer at spawn (initialize, then
//! session/new or session/resume, then session/set_mode and/or
//! session/set_config_option, then session/prompt) and closes stdin.
//! Native `fx.spawn` has no write-to-running-child, so `session/cancel`
//! cannot be sent after spawn — Stop/Esc uses `fx.cancel`. This is not a
//! long-lived ACP loop. `session/load` is not used (resume, not replay).
//!
//! Frames are one JSON object per line. This file never execs a binary.

const std = @import("std");

/// ACP version fx advertises (`initialize` response `protocolVersion`).
pub const PROTOCOL_VERSION: u32 = 1;
pub const JSONRPC_VERSION = "2.0";

pub const CLIENT_NAME = "faku";
pub const CLIENT_VERSION = "0.1.0";

pub const ID_INITIALIZE: u64 = 1;
pub const ID_SESSION: u64 = 2;
pub const ID_PROMPT: u64 = 3;
pub const ID_SET_MODE: u64 = 4;
pub const ID_SET_CONFIG: u64 = 5;

pub const METHOD_INITIALIZE = "initialize";
pub const METHOD_SESSION_NEW = "session/new";
pub const METHOD_SESSION_RESUME = "session/resume";
pub const METHOD_SESSION_PROMPT = "session/prompt";
pub const METHOD_SESSION_CANCEL = "session/cancel";
pub const METHOD_SESSION_UPDATE = "session/update";
pub const METHOD_SESSION_SET_MODE = "session/set_mode";
pub const METHOD_SESSION_SET_CONFIG = "session/set_config_option";

/// fx ACP config option ids (https://fx.sh/docs/using-fx/acp + fx e2e).
pub const CONFIG_ID_MODEL = "model";
pub const CONFIG_ID_MODE = "mode";

/// fx ACP session modes (https://fx.sh/docs/using-fx/acp). Not Waku
/// `fullAccess` / `yolo` / `auto` — those are FX_PERMISSION_MODE values.
pub const MODE_ASK = "ask";
pub const MODE_CODE = "code";

pub const SESSION_UPDATE_AGENT_MESSAGE = "agent_message_chunk";
/// Stabilized ACP v1 `session/update` variant
/// (https://agentclientprotocol.com/protocol/v1/prompt-turn#session-usage-updates).
/// fx.sh ACP docs and vercel-labs/fx do not emit this today.
pub const SESSION_UPDATE_USAGE = "usage_update";
/// Official ACP + fx `session/update` tool frames
/// (https://agentclientprotocol.com/protocol/v1/prompt-turn,
/// vercel-labs/fx `src/acp/types.zig` `writeToolCall` /
/// `writeToolCallUpdate`).
pub const SESSION_UPDATE_TOOL_CALL = "tool_call";
pub const SESSION_UPDATE_TOOL_CALL_UPDATE = "tool_call_update";
pub const STOP_END_TURN = "end_turn";
pub const STOP_CANCELLED = "cancelled";
pub const STOP_REFUSAL = "refusal";

pub const Method = enum {
    initialize,
    session_new,
    session_resume,
    session_prompt,
    session_cancel,
    session_update,
    session_set_mode,
    session_set_config_option,
    unknown,

    pub fn wireName(method: Method) []const u8 {
        return switch (method) {
            .initialize => METHOD_INITIALIZE,
            .session_new => METHOD_SESSION_NEW,
            .session_resume => METHOD_SESSION_RESUME,
            .session_prompt => METHOD_SESSION_PROMPT,
            .session_cancel => METHOD_SESSION_CANCEL,
            .session_update => METHOD_SESSION_UPDATE,
            .session_set_mode => METHOD_SESSION_SET_MODE,
            .session_set_config_option => METHOD_SESSION_SET_CONFIG,
            .unknown => "",
        };
    }

    pub fn fromWire(name: []const u8) Method {
        if (std.mem.eql(u8, name, METHOD_INITIALIZE)) return .initialize;
        if (std.mem.eql(u8, name, METHOD_SESSION_NEW)) return .session_new;
        if (std.mem.eql(u8, name, METHOD_SESSION_RESUME)) return .session_resume;
        if (std.mem.eql(u8, name, METHOD_SESSION_PROMPT)) return .session_prompt;
        if (std.mem.eql(u8, name, METHOD_SESSION_CANCEL)) return .session_cancel;
        if (std.mem.eql(u8, name, METHOD_SESSION_UPDATE)) return .session_update;
        if (std.mem.eql(u8, name, METHOD_SESSION_SET_MODE)) return .session_set_mode;
        if (std.mem.eql(u8, name, METHOD_SESSION_SET_CONFIG)) return .session_set_config_option;
        return .unknown;
    }
};

pub const FrameKind = enum { request, notification, response, error_response, invalid };

pub const Parsed = struct {
    kind: FrameKind = .invalid,
    jsonrpc_ok: bool = false,
    method: Method = .unknown,
    method_name: []const u8 = "",
    id: ?u64 = null,
    session_id: []const u8 = "",
    session_update: []const u8 = "",
    text: []const u8 = "",
    tool_call_id: []const u8 = "",
    title: []const u8 = "",
    tool_kind: []const u8 = "",
    status: []const u8 = "",
    stop_reason: []const u8 = "",
    mode_id: []const u8 = "",
    config_id: []const u8 = "",
    config_value: []const u8 = "",
    /// ACP `usage_update` token counts. Null unless that key is a number.
    used: ?u64 = null,
    size: ?u64 = null,
    has_error: bool = false,
    has_result: bool = false,
};

/// Confirmed ACP `usage_update` fields (`used` + `size`). Both required.
pub const UsageUpdate = struct {
    used: u64,
    size: u64,
};

/// Confirmed ACP/fx tool-call fields. `toolCallId` is required; the
/// others are optional on `tool_call_update`.
pub const ToolUpdate = struct {
    tool_call_id: []const u8,
    title: []const u8 = "",
    kind: []const u8 = "",
    status: []const u8 = "",
};

pub const TurnStdin = struct {
    cwd: []const u8,
    resume_id: []const u8 = "",
    prompt: []const u8,
    model: []const u8 = "",
    access_mode: []const u8 = "",
};

const WriteError = error{NoSpaceLeft};

const Cursor = struct {
    buf: []u8,
    pos: usize = 0,

    fn remaining(self: *Cursor) []u8 {
        return self.buf[self.pos..];
    }

    fn write(self: *Cursor, bytes: []const u8) WriteError!void {
        if (self.pos + bytes.len > self.buf.len) return error.NoSpaceLeft;
        @memcpy(self.buf[self.pos..][0..bytes.len], bytes);
        self.pos += bytes.len;
    }

    fn slice(self: *const Cursor) []const u8 {
        return self.buf[0..self.pos];
    }
};

fn writeJsonString(cur: *Cursor, text: []const u8) WriteError!void {
    try cur.write("\"");
    for (text) |c| {
        switch (c) {
            '"' => try cur.write("\\\""),
            '\\' => try cur.write("\\\\"),
            '\n' => try cur.write("\\n"),
            '\r' => try cur.write("\\r"),
            '\t' => try cur.write("\\t"),
            else => {
                if (c < 0x20) {
                    var hex: [6]u8 = undefined;
                    const piece = std.fmt.bufPrint(&hex, "\\u{x:0>4}", .{c}) catch return error.NoSpaceLeft;
                    try cur.write(piece);
                } else {
                    try cur.write(&.{c});
                }
            },
        }
    }
    try cur.write("\"");
}

fn writeUint(cur: *Cursor, value: u64) WriteError!void {
    var num: [20]u8 = undefined;
    const piece = std.fmt.bufPrint(&num, "{d}", .{value}) catch return error.NoSpaceLeft;
    try cur.write(piece);
}

fn writeRequestHead(cur: *Cursor, id: u64, method: []const u8) WriteError!void {
    try cur.write("{\"jsonrpc\":\"");
    try cur.write(JSONRPC_VERSION);
    try cur.write("\",\"id\":");
    try writeUint(cur, id);
    try cur.write(",\"method\":");
    try writeJsonString(cur, method);
    try cur.write(",\"params\":");
}

/// `initialize` request (ACP v1 / fx). Client info is optional in the
/// schema today and required later; we always send it.
pub fn writeInitialize(
    buf: []u8,
    id: u64,
    client_name: []const u8,
    client_version: []const u8,
) WriteError![]const u8 {
    var cur = Cursor{ .buf = buf };
    try writeRequestHead(&cur, id, METHOD_INITIALIZE);
    try cur.write("{\"protocolVersion\":");
    try writeUint(&cur, PROTOCOL_VERSION);
    try cur.write(",\"clientCapabilities\":{},\"clientInfo\":{\"name\":");
    try writeJsonString(&cur, client_name);
    try cur.write(",\"version\":");
    try writeJsonString(&cur, client_version);
    try cur.write("}}}\n");
    return cur.slice();
}

/// `session/new` — cwd is the primary workspace; MCP servers are empty
/// (one-shot client; ACP sessions do not inherit `~/.fx/mcp.json`).
pub fn writeSessionNew(buf: []u8, id: u64, cwd: []const u8) WriteError![]const u8 {
    var cur = Cursor{ .buf = buf };
    try writeRequestHead(&cur, id, METHOD_SESSION_NEW);
    try cur.write("{\"cwd\":");
    try writeJsonString(&cur, cwd);
    try cur.write(",\"mcpServers\":[]}}\n");
    return cur.slice();
}

/// `session/resume` — reconnect to a saved session without replaying history.
/// cwd + mcpServers match the official ACP v1 resume params.
pub fn writeSessionResume(
    buf: []u8,
    id: u64,
    session_id: []const u8,
    cwd: []const u8,
) WriteError![]const u8 {
    var cur = Cursor{ .buf = buf };
    try writeRequestHead(&cur, id, METHOD_SESSION_RESUME);
    try cur.write("{\"sessionId\":");
    try writeJsonString(&cur, session_id);
    try cur.write(",\"cwd\":");
    try writeJsonString(&cur, cwd);
    try cur.write(",\"mcpServers\":[]}}\n");
    return cur.slice();
}

/// `session/prompt` with one text content block.
pub fn writeSessionPrompt(
    buf: []u8,
    id: u64,
    session_id: []const u8,
    text: []const u8,
) WriteError![]const u8 {
    var cur = Cursor{ .buf = buf };
    try writeRequestHead(&cur, id, METHOD_SESSION_PROMPT);
    try cur.write("{\"sessionId\":");
    try writeJsonString(&cur, session_id);
    try cur.write(",\"prompt\":[{\"type\":\"text\",\"text\":");
    try writeJsonString(&cur, text);
    try cur.write("}]}}\n");
    return cur.slice();
}

/// Waku `access_mode` → fx ACP mode id (`ask` | `code`).
/// Verified against https://fx.sh/docs/using-fx/acp (modes table) and
/// fx e2e (`mode` options are `code` and `ask`). `fullAccess` / `yolo`
/// / `auto` are not ACP mode strings — they stay on FX_PERMISSION_MODE.
pub fn sessionMode(access_mode: []const u8) []const u8 {
    if (std.mem.eql(u8, access_mode, "ask")) return MODE_ASK;
    if (std.mem.eql(u8, access_mode, MODE_CODE)) return MODE_CODE;
    if (std.mem.eql(u8, access_mode, "autoAcceptEdits")) return MODE_CODE;
    if (std.mem.eql(u8, access_mode, "auto")) return MODE_CODE;
    if (std.mem.eql(u8, access_mode, "fullAccess")) return MODE_CODE;
    if (std.mem.eql(u8, access_mode, "yolo")) return MODE_CODE;
    return "";
}

/// `session/set_mode` — ACP v1 `{ sessionId, modeId }`. fx applies
/// `modeId` to the active session (`ask` | `code`).
pub fn writeSessionSetMode(
    buf: []u8,
    id: u64,
    session_id: []const u8,
    mode_id: []const u8,
) WriteError![]const u8 {
    var cur = Cursor{ .buf = buf };
    try writeRequestHead(&cur, id, METHOD_SESSION_SET_MODE);
    try cur.write("{\"sessionId\":");
    try writeJsonString(&cur, session_id);
    try cur.write(",\"modeId\":");
    try writeJsonString(&cur, mode_id);
    try cur.write("}}\n");
    return cur.slice();
}

/// `session/set_config_option` — ACP v1 `{ sessionId, configId, value }`.
/// fx config ids include `model` and `mode`.
pub fn writeSessionSetConfigOption(
    buf: []u8,
    id: u64,
    session_id: []const u8,
    config_id: []const u8,
    value: []const u8,
) WriteError![]const u8 {
    var cur = Cursor{ .buf = buf };
    try writeRequestHead(&cur, id, METHOD_SESSION_SET_CONFIG);
    try cur.write("{\"sessionId\":");
    try writeJsonString(&cur, session_id);
    try cur.write(",\"configId\":");
    try writeJsonString(&cur, config_id);
    try cur.write(",\"value\":");
    try writeJsonString(&cur, value);
    try cur.write("}}\n");
    return cur.slice();
}

/// `session/cancel` notification (no `id`; no response expected).
/// Built for the stub/tests; one-shot spawn cannot write this after start.
pub fn writeSessionCancel(buf: []u8, session_id: []const u8) WriteError![]const u8 {
    var cur = Cursor{ .buf = buf };
    try cur.write("{\"jsonrpc\":\"");
    try cur.write(JSONRPC_VERSION);
    try cur.write("\",\"method\":");
    try writeJsonString(&cur, METHOD_SESSION_CANCEL);
    try cur.write(",\"params\":{\"sessionId\":");
    try writeJsonString(&cur, session_id);
    try cur.write("}}\n");
    return cur.slice();
}

/// One Native spawn stdin: initialize, session/new or session/resume,
/// then session/set_mode and/or session/set_config_option, then
/// session/prompt. First-turn prompt / set_* use an empty sessionId
/// because the id is minted in the `session/new` result on stdout —
/// there is no write-after-spawn. Follow-ups pass the stored id.
/// Empty `model` omits the model config. Unmapped `access_mode` omits
/// `session/set_mode`.
pub fn writeTurnStdin(buf: []u8, args: TurnStdin) WriteError![]const u8 {
    var cur = Cursor{ .buf = buf };
    const init = try writeInitialize(cur.remaining(), ID_INITIALIZE, CLIENT_NAME, CLIENT_VERSION);
    cur.pos += init.len;
    if (args.resume_id.len > 0) {
        const resumed = try writeSessionResume(cur.remaining(), ID_SESSION, args.resume_id, args.cwd);
        cur.pos += resumed.len;
    } else {
        const created = try writeSessionNew(cur.remaining(), ID_SESSION, args.cwd);
        cur.pos += created.len;
    }
    const mode_id = sessionMode(args.access_mode);
    if (mode_id.len > 0) {
        const mode = try writeSessionSetMode(cur.remaining(), ID_SET_MODE, args.resume_id, mode_id);
        cur.pos += mode.len;
    }
    if (args.model.len > 0) {
        const config = try writeSessionSetConfigOption(
            cur.remaining(),
            ID_SET_CONFIG,
            args.resume_id,
            CONFIG_ID_MODEL,
            args.model,
        );
        cur.pos += config.len;
    }
    const prompt = try writeSessionPrompt(cur.remaining(), ID_PROMPT, args.resume_id, args.prompt);
    cur.pos += prompt.len;
    return cur.slice();
}

/// `session/new` result `{ sessionId }` — the same saved fx session id
/// (`fx_session_id`). Resume result is `{}` and has no id.
pub fn mintedSessionId(parsed: Parsed) []const u8 {
    if (parsed.kind != .response or parsed.has_error) return "";
    if (parsed.id != ID_SESSION) return "";
    return parsed.session_id;
}

pub fn isAgentMessageText(parsed: Parsed) bool {
    return parsed.method == .session_update and
        std.mem.eql(u8, parsed.session_update, SESSION_UPDATE_AGENT_MESSAGE) and
        parsed.text.len > 0;
}

/// ACP v1 / fx `tool_call` and `tool_call_update`. `toolCallId` is required.
/// Title, kind, and status are whatever the frame carried (updates omit
/// unchanged fields).
pub fn toolUpdate(parsed: Parsed) ?ToolUpdate {
    if (parsed.method != .session_update) return null;
    const is_call = std.mem.eql(u8, parsed.session_update, SESSION_UPDATE_TOOL_CALL);
    const is_update = std.mem.eql(u8, parsed.session_update, SESSION_UPDATE_TOOL_CALL_UPDATE);
    if (!is_call and !is_update) return null;
    if (parsed.tool_call_id.len == 0) return null;
    return .{
        .tool_call_id = parsed.tool_call_id,
        .title = parsed.title,
        .kind = parsed.tool_kind,
        .status = parsed.status,
    };
}

/// Join confirmed tool fields for a muted tool-turn body. Empty parts drop.
pub fn toolTurnText(buf: []u8, title: []const u8, kind: []const u8, status: []const u8) []const u8 {
    var cur: usize = 0;
    const parts = [_][]const u8{ title, kind, status };
    for (parts) |part| {
        if (part.len == 0) continue;
        if (cur > 0) {
            const sep = " · ";
            if (cur + sep.len > buf.len) break;
            @memcpy(buf[cur..][0..sep.len], sep);
            cur += sep.len;
        }
        const take = @min(buf.len - cur, part.len);
        @memcpy(buf[cur..][0..take], part[0..take]);
        cur += take;
    }
    return buf[0..cur];
}

/// ACP v1 `usage_update`: `used` and `size` are required token counts.
/// Missing either, or `size == 0`, is not a usable update.
pub fn usageUpdate(parsed: Parsed) ?UsageUpdate {
    if (parsed.method != .session_update) return null;
    if (!std.mem.eql(u8, parsed.session_update, SESSION_UPDATE_USAGE)) return null;
    const used = parsed.used orelse return null;
    const size = parsed.size orelse return null;
    if (size == 0) return null;
    return .{ .used = used, .size = size };
}

/// ACP v1: the `session/prompt` response carries `stopReason` and ends the turn.
pub fn isPromptResult(parsed: Parsed) bool {
    if (parsed.id != ID_PROMPT) return false;
    return parsed.kind == .response or parsed.kind == .error_response;
}

/// Drain the success-only queue unless the prompt was cancelled, refused,
/// or returned a JSON-RPC error.
pub fn promptSucceeded(parsed: Parsed) bool {
    if (parsed.kind == .error_response or parsed.has_error) return false;
    if (std.mem.eql(u8, parsed.stop_reason, STOP_CANCELLED)) return false;
    if (std.mem.eql(u8, parsed.stop_reason, STOP_REFUSAL)) return false;
    return parsed.has_result;
}

fn skipWs(text: []const u8, start: usize) usize {
    var i = start;
    while (i < text.len and std.ascii.isWhitespace(text[i])) i += 1;
    return i;
}

fn matchKey(text: []const u8, start: usize, key: []const u8) ?usize {
    const i = skipWs(text, start);
    if (i >= text.len or text[i] != '"') return null;
    if (i + 1 + key.len + 1 >= text.len) return null;
    if (!std.mem.eql(u8, text[i + 1 .. i + 1 + key.len], key)) return null;
    if (text[i + 1 + key.len] != '"') return null;
    const j = skipWs(text, i + 1 + key.len + 1);
    if (j >= text.len or text[j] != ':') return null;
    return skipWs(text, j + 1);
}

fn findKey(text: []const u8, key: []const u8) ?usize {
    var i: usize = 0;
    while (i < text.len) : (i += 1) {
        if (matchKey(text, i, key)) |value_at| return value_at;
    }
    return null;
}

fn parseJsonStringAt(text: []const u8, start: usize) []const u8 {
    if (start >= text.len or text[start] != '"') return "";
    var i = start + 1;
    while (i < text.len) : (i += 1) {
        if (text[i] == '\\') {
            i += 1;
            continue;
        }
        if (text[i] == '"') return text[start + 1 .. i];
    }
    return "";
}

fn parseUintAt(text: []const u8, start: usize) ?u64 {
    if (start >= text.len or !std.ascii.isDigit(text[start])) return null;
    var value: u64 = 0;
    var i = start;
    while (i < text.len and std.ascii.isDigit(text[i])) : (i += 1) {
        value = value * 10 + (text[i] - '0');
    }
    return value;
}

/// Parse one NDJSON JSON-RPC line. Slices alias `line` and die with it.
/// Field scanner — classifies the methods above and pulls `id`,
/// `sessionId`, `sessionUpdate`, `text`, `toolCallId`, `title`, `kind`,
/// `status`, and `stopReason`.
pub fn parseLine(line: []const u8) Parsed {
    var parsed = Parsed{};
    const trimmed = std.mem.trim(u8, line, " \t\r\n");
    if (trimmed.len == 0) return parsed;

    if (findKey(trimmed, "jsonrpc")) |at| {
        parsed.jsonrpc_ok = std.mem.eql(u8, parseJsonStringAt(trimmed, at), JSONRPC_VERSION);
    }

    if (findKey(trimmed, "id")) |at| {
        parsed.id = parseUintAt(trimmed, at);
    }

    if (findKey(trimmed, "method")) |at| {
        parsed.method_name = parseJsonStringAt(trimmed, at);
        parsed.method = Method.fromWire(parsed.method_name);
    }

    if (findKey(trimmed, "sessionId")) |at| {
        parsed.session_id = parseJsonStringAt(trimmed, at);
    }

    if (findKey(trimmed, "sessionUpdate")) |at| {
        parsed.session_update = parseJsonStringAt(trimmed, at);
    }

    if (findKey(trimmed, "text")) |at| {
        parsed.text = parseJsonStringAt(trimmed, at);
    }

    if (findKey(trimmed, "toolCallId")) |at| {
        parsed.tool_call_id = parseJsonStringAt(trimmed, at);
    }

    if (findKey(trimmed, "title")) |at| {
        parsed.title = parseJsonStringAt(trimmed, at);
    }

    if (findKey(trimmed, "kind")) |at| {
        parsed.tool_kind = parseJsonStringAt(trimmed, at);
    }

    if (findKey(trimmed, "status")) |at| {
        parsed.status = parseJsonStringAt(trimmed, at);
    }

    if (findKey(trimmed, "stopReason")) |at| {
        parsed.stop_reason = parseJsonStringAt(trimmed, at);
    }

    if (findKey(trimmed, "modeId")) |at| {
        parsed.mode_id = parseJsonStringAt(trimmed, at);
    }

    if (findKey(trimmed, "configId")) |at| {
        parsed.config_id = parseJsonStringAt(trimmed, at);
    }

    if (findKey(trimmed, "value")) |at| {
        parsed.config_value = parseJsonStringAt(trimmed, at);
    }

    if (findKey(trimmed, "used")) |at| {
        parsed.used = parseUintAt(trimmed, at);
    }

    if (findKey(trimmed, "size")) |at| {
        parsed.size = parseUintAt(trimmed, at);
    }

    parsed.has_error = findKey(trimmed, "error") != null;
    parsed.has_result = findKey(trimmed, "result") != null;

    if (parsed.has_error) {
        parsed.kind = .error_response;
    } else if (parsed.has_result) {
        parsed.kind = .response;
    } else if (parsed.method != .unknown and parsed.id == null) {
        parsed.kind = .notification;
    } else if (parsed.method != .unknown) {
        parsed.kind = .request;
    }
    return parsed;
}

test "ACP builders are newline-delimited JSON-RPC 2.0" {
    var buf: [512]u8 = undefined;
    const init = try writeInitialize(&buf, 1, "faku", "0.1.0");
    try std.testing.expect(std.mem.endsWith(u8, init, "\n"));
    try std.testing.expect(std.mem.indexOf(u8, init, "\"jsonrpc\":\"2.0\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, init, "\"method\":\"initialize\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, init, "\"protocolVersion\":1") != null);

    const parsed_init = parseLine(init);
    try std.testing.expect(parsed_init.jsonrpc_ok);
    try std.testing.expectEqual(FrameKind.request, parsed_init.kind);
    try std.testing.expectEqual(Method.initialize, parsed_init.method);
    try std.testing.expectEqual(@as(?u64, 1), parsed_init.id);

    const created = try writeSessionNew(&buf, 2, "/tmp/project");
    const parsed_new = parseLine(created);
    try std.testing.expectEqual(Method.session_new, parsed_new.method);
    try std.testing.expect(std.mem.indexOf(u8, created, "\"mcpServers\":[]") != null);

    const resumed = try writeSessionResume(&buf, 2, "sess-1", "/tmp/project");
    const parsed_resume = parseLine(resumed);
    try std.testing.expectEqual(Method.session_resume, parsed_resume.method);
    try std.testing.expectEqualStrings("sess-1", parsed_resume.session_id);
    try std.testing.expect(std.mem.indexOf(u8, resumed, "\"cwd\":\"/tmp/project\"") != null);

    const prompt = try writeSessionPrompt(&buf, 3, "sess-1", "trace the listener");
    const parsed_prompt = parseLine(prompt);
    try std.testing.expectEqual(Method.session_prompt, parsed_prompt.method);
    try std.testing.expectEqualStrings("sess-1", parsed_prompt.session_id);
    try std.testing.expect(std.mem.indexOf(u8, prompt, "\"type\":\"text\"") != null);

    const cancel = try writeSessionCancel(&buf, "sess-1");
    const parsed_cancel = parseLine(cancel);
    try std.testing.expectEqual(Method.session_cancel, parsed_cancel.method);
    try std.testing.expectEqual(FrameKind.notification, parsed_cancel.kind);
    try std.testing.expectEqual(@as(?u64, null), parsed_cancel.id);

    const set_mode = try writeSessionSetMode(&buf, 4, "sess-1", MODE_CODE);
    const parsed_mode = parseLine(set_mode);
    try std.testing.expectEqual(Method.session_set_mode, parsed_mode.method);
    try std.testing.expectEqual(FrameKind.request, parsed_mode.kind);
    try std.testing.expectEqualStrings("sess-1", parsed_mode.session_id);
    try std.testing.expectEqualStrings(MODE_CODE, parsed_mode.mode_id);

    const set_config = try writeSessionSetConfigOption(&buf, 5, "sess-1", CONFIG_ID_MODEL, "openai/gpt-5.4");
    const parsed_config = parseLine(set_config);
    try std.testing.expectEqual(Method.session_set_config_option, parsed_config.method);
    try std.testing.expectEqualStrings(CONFIG_ID_MODEL, parsed_config.config_id);
    try std.testing.expectEqualStrings("openai/gpt-5.4", parsed_config.config_value);
}

test "Waku access_mode maps to fx ACP ask|code, not fullAccess" {
    try std.testing.expectEqualStrings(MODE_ASK, sessionMode("ask"));
    try std.testing.expectEqualStrings(MODE_CODE, sessionMode("code"));
    try std.testing.expectEqualStrings(MODE_CODE, sessionMode("auto"));
    try std.testing.expectEqualStrings(MODE_CODE, sessionMode("autoAcceptEdits"));
    try std.testing.expectEqualStrings(MODE_CODE, sessionMode("fullAccess"));
    try std.testing.expectEqualStrings(MODE_CODE, sessionMode("yolo"));
    try std.testing.expectEqualStrings("", sessionMode(""));
    try std.testing.expectEqualStrings("", sessionMode("nope"));
}

test "one-shot stdin is initialize plus new or resume then prompt" {
    var buf: [1024]u8 = undefined;
    const first = try writeTurnStdin(&buf, .{ .cwd = "/tmp/project", .prompt = "first turn" });
    try std.testing.expect(std.mem.indexOf(u8, first, "\"method\":\"initialize\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, first, "\"method\":\"session/new\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, first, "\"cwd\":\"/tmp/project\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, first, "\"method\":\"session/prompt\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, first, "session/resume") == null);
    try std.testing.expect(std.mem.indexOf(u8, first, "session/load") == null);
    try std.testing.expect(std.mem.indexOf(u8, first, "first turn") != null);

    const later = try writeTurnStdin(&buf, .{
        .cwd = ".",
        .resume_id = "fx-sess-1",
        .prompt = "second turn",
    });
    try std.testing.expect(std.mem.indexOf(u8, later, "\"method\":\"initialize\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, later, "\"method\":\"session/resume\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, later, "\"sessionId\":\"fx-sess-1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, later, "session/new") == null);
    try std.testing.expect(std.mem.indexOf(u8, later, "second turn") != null);
    try std.testing.expect(std.mem.indexOf(u8, first, "session/set_mode") == null);
    try std.testing.expect(std.mem.indexOf(u8, first, "session/set_config_option") == null);
}

test "one-shot stdin inserts set_mode and model config after new|resume before prompt" {
    var buf: [2048]u8 = undefined;
    const first = try writeTurnStdin(&buf, .{
        .cwd = "/tmp/project",
        .prompt = "first turn",
        .model = "openai/gpt-5.4",
        .access_mode = "fullAccess",
    });
    try expectMethodsInOrder(first, &.{
        .initialize,
        .session_new,
        .session_set_mode,
        .session_set_config_option,
        .session_prompt,
    });
    try std.testing.expect(std.mem.indexOf(u8, first, "\"modeId\":\"code\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, first, "\"configId\":\"model\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, first, "\"value\":\"openai/gpt-5.4\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, first, "fullAccess") == null);
    try std.testing.expect(std.mem.indexOf(u8, first, "yolo") == null);

    const later = try writeTurnStdin(&buf, .{
        .cwd = ".",
        .resume_id = "fx-sess-1",
        .prompt = "second turn",
        .model = "openai/gpt-5.4",
        .access_mode = "ask",
    });
    try expectMethodsInOrder(later, &.{
        .initialize,
        .session_resume,
        .session_set_mode,
        .session_set_config_option,
        .session_prompt,
    });
    try std.testing.expect(std.mem.indexOf(u8, later, "\"modeId\":\"ask\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, later, "\"sessionId\":\"fx-sess-1\"") != null);

    const no_model = try writeTurnStdin(&buf, .{
        .cwd = ".",
        .prompt = "no model",
        .access_mode = "ask",
    });
    try expectMethodsInOrder(no_model, &.{
        .initialize,
        .session_new,
        .session_set_mode,
        .session_prompt,
    });
    try std.testing.expect(std.mem.indexOf(u8, no_model, "session/set_config_option") == null);
    try std.testing.expect(std.mem.indexOf(u8, no_model, "\"configId\":\"model\"") == null);
}

test "ACP parser classifies result, error, update, and stopReason" {
    const ok = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"protocolVersion\":1}}";
    const parsed_ok = parseLine(ok);
    try std.testing.expectEqual(FrameKind.response, parsed_ok.kind);
    try std.testing.expect(parsed_ok.has_result);

    const minted = parseLine("{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"sessionId\":\"sess-9\"}}");
    try std.testing.expectEqualStrings("sess-9", mintedSessionId(minted));

    const err = "{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":-32600,\"message\":\"invalid\"}}";
    const parsed_err = parseLine(err);
    try std.testing.expectEqual(FrameKind.error_response, parsed_err.kind);
    try std.testing.expect(parsed_err.has_error);

    const update = "{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"sessionId\":\"sess-1\",\"update\":{\"sessionUpdate\":\"agent_message_chunk\",\"content\":{\"type\":\"text\",\"text\":\"hello acp\"}}}}";
    const parsed_update = parseLine(update);
    try std.testing.expectEqual(Method.session_update, parsed_update.method);
    try std.testing.expectEqual(FrameKind.notification, parsed_update.kind);
    try std.testing.expect(isAgentMessageText(parsed_update));
    try std.testing.expectEqualStrings("hello acp", parsed_update.text);

    const user = parseLine("{\"method\":\"session/update\",\"params\":{\"update\":{\"sessionUpdate\":\"user_message_chunk\",\"content\":{\"type\":\"text\",\"text\":\"ignore\"}}}}");
    try std.testing.expect(!isAgentMessageText(user));
    try std.testing.expect(usageUpdate(user) == null);

    const usage = parseLine("{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"sessionId\":\"sess-1\",\"update\":{\"sessionUpdate\":\"usage_update\",\"used\":53000,\"size\":200000}}}");
    try std.testing.expectEqual(Method.session_update, usage.method);
    try std.testing.expectEqualStrings(SESSION_UPDATE_USAGE, usage.session_update);
    const usage_fields = usageUpdate(usage) orelse return error.MissingUsage;
    try std.testing.expectEqual(@as(u64, 53000), usage_fields.used);
    try std.testing.expectEqual(@as(u64, 200000), usage_fields.size);
    try std.testing.expect(!isAgentMessageText(usage));

    const usage_missing_size = parseLine("{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"update\":{\"sessionUpdate\":\"usage_update\",\"used\":12}}}");
    try std.testing.expect(usageUpdate(usage_missing_size) == null);

    const usage_zero_size = parseLine("{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"update\":{\"sessionUpdate\":\"usage_update\",\"used\":12,\"size\":0}}}");
    try std.testing.expect(usageUpdate(usage_zero_size) == null);

    const tool_call = parseLine("{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"sessionId\":\"sess-1\",\"update\":{\"sessionUpdate\":\"tool_call\",\"toolCallId\":\"call_001\",\"title\":\"Reading file\",\"kind\":\"read\",\"status\":\"pending\"}}}");
    try std.testing.expectEqual(Method.session_update, tool_call.method);
    try std.testing.expectEqualStrings(SESSION_UPDATE_TOOL_CALL, tool_call.session_update);
    const tool_fields = toolUpdate(tool_call) orelse return error.MissingTool;
    try std.testing.expectEqualStrings("call_001", tool_fields.tool_call_id);
    try std.testing.expectEqualStrings("Reading file", tool_fields.title);
    try std.testing.expectEqualStrings("read", tool_fields.kind);
    try std.testing.expectEqualStrings("pending", tool_fields.status);
    try std.testing.expect(!isAgentMessageText(tool_call));
    try std.testing.expect(usageUpdate(tool_call) == null);
    var tool_text_buf: [64]u8 = undefined;
    try std.testing.expectEqualStrings(
        "Reading file · read · pending",
        toolTurnText(&tool_text_buf, tool_fields.title, tool_fields.kind, tool_fields.status),
    );

    const tool_progress = parseLine("{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"update\":{\"sessionUpdate\":\"tool_call_update\",\"toolCallId\":\"call_001\",\"status\":\"in_progress\"}}}");
    const progress_fields = toolUpdate(tool_progress) orelse return error.MissingToolUpdate;
    try std.testing.expectEqualStrings(SESSION_UPDATE_TOOL_CALL_UPDATE, tool_progress.session_update);
    try std.testing.expectEqualStrings("call_001", progress_fields.tool_call_id);
    try std.testing.expectEqualStrings("", progress_fields.title);
    try std.testing.expectEqualStrings("", progress_fields.kind);
    try std.testing.expectEqualStrings("in_progress", progress_fields.status);

    const tool_missing_id = parseLine("{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"update\":{\"sessionUpdate\":\"tool_call\",\"title\":\"Reading file\",\"kind\":\"read\",\"status\":\"pending\"}}}");
    try std.testing.expect(toolUpdate(tool_missing_id) == null);

    const settled = parseLine("{\"jsonrpc\":\"2.0\",\"id\":3,\"result\":{\"stopReason\":\"end_turn\"}}");
    try std.testing.expect(isPromptResult(settled));
    try std.testing.expect(promptSucceeded(settled));
    try std.testing.expectEqualStrings(STOP_END_TURN, settled.stop_reason);

    const cancelled = parseLine("{\"jsonrpc\":\"2.0\",\"id\":3,\"result\":{\"stopReason\":\"cancelled\"}}");
    try std.testing.expect(isPromptResult(cancelled));
    try std.testing.expect(!promptSucceeded(cancelled));
}

fn expectMethodsInOrder(stdin: []const u8, expected: []const Method) !void {
    var i: usize = 0;
    var line_start: usize = 0;
    while (line_start < stdin.len) {
        const nl = std.mem.indexOfScalarPos(u8, stdin, line_start, '\n') orelse stdin.len;
        const parsed = parseLine(stdin[line_start..nl]);
        line_start = if (nl < stdin.len) nl + 1 else stdin.len;
        if (parsed.method == .unknown) continue;
        try std.testing.expect(i < expected.len);
        try std.testing.expectEqual(expected[i], parsed.method);
        i += 1;
    }
    try std.testing.expectEqual(expected.len, i);
}
