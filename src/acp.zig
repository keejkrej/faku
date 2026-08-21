//! Agent Client Protocol (ACP) JSON-RPC 2.0 helpers for one-shot `fx acp`.
//!
//! Official methods (https://fx.sh/docs/using-fx/acp): initialize,
//! session/new, session/load, session/resume, session/close, session/list,
//! session/prompt, session/cancel, session/set_config_option, session/set_mode.
//! fx reports protocol version 1. Each connection has one active session
//! and one active prompt.
//!
//! Native `fx.spawn` writes one stdin buffer and closes it, so Send
//! spawns `faku acp-proxy -- … fx acp`. The sidecar writes that same
//! NDJSON batch (initialize, session/new or session/resume, then
//! session/set_mode and/or session/set_config_option, then
//! session/prompt) and keeps fx stdin open. Official ACP v1
//! `session/request_permission` is auto-answered from the access mode
//! already on that run (FX_PERMISSION_MODE / session/set_mode), not a
//! window dialog. Mid-turn `session/cancel` still cannot be written
//! from the window — Stop/Esc uses `fx.cancel`. This is not a
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
/// Official ACP v1 client method (agent → client).
/// https://agentclientprotocol.com/protocol/v1/tool-calls#requesting-permission
/// vercel-labs/fx `src/acp/prompt.zig` `writePermissionOption`.
pub const METHOD_SESSION_REQUEST_PERMISSION = "session/request_permission";

/// Official ACP v1 `PermissionOptionKind`. optionId is a free string;
/// fx uses these same spellings as optionId. Docs examples use hyphens
/// (`allow-once`). Always read optionId from the request.
pub const KIND_ALLOW_ONCE = "allow_once";
pub const KIND_ALLOW_ALWAYS = "allow_always";
pub const KIND_REJECT_ONCE = "reject_once";
pub const KIND_REJECT_ALWAYS = "reject_always";
pub const OUTCOME_SELECTED = "selected";
pub const OUTCOME_CANCELLED = "cancelled";
/// Cap matches fx (3 options) plus the docs pair. Extra items drop.
pub const max_permission_options: usize = 8;

/// fx ACP config option ids (https://fx.sh/docs/using-fx/acp + fx e2e).
pub const CONFIG_ID_MODEL = "model";
pub const CONFIG_ID_MODE = "mode";

/// fx ACP session modes (https://fx.sh/docs/using-fx/acp). Not Waku
/// `fullAccess` / `yolo` / `auto` — those are FX_PERMISSION_MODE values.
pub const MODE_ASK = "ask";
pub const MODE_CODE = "code";

pub const SESSION_UPDATE_AGENT_MESSAGE = "agent_message_chunk";
/// Official ACP v1 `session/update` reasoning chunk
/// (https://agentclientprotocol.com/protocol/v1/schema `agent_thought_chunk`,
/// same content block as `agent_message_chunk`). Not a `delta` field.
/// vercel-labs/fx `src/acp/types.zig` has `writeAgentMessageChunk` but no
/// thought writer today.
pub const SESSION_UPDATE_AGENT_THOUGHT = "agent_thought_chunk";
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
/// Official ACP v1 `session/update` when the agent changes mode
/// (https://agentclientprotocol.com/protocol/v1/schema `CurrentModeUpdate`,
/// https://agentclientprotocol.com/protocol/v1/session-modes).
/// Wire field is `currentModeId` (schema required). The session-modes
/// docs example also shows `modeId` (same key as `session/set_mode`);
/// the parser accepts either. vercel-labs/fx `src/acp/types.zig` and
/// fx.sh ACP docs do not emit this today.
pub const SESSION_UPDATE_CURRENT_MODE = "current_mode_update";
/// Official ACP v1 `session/update` when session config options change
/// (https://agentclientprotocol.com/protocol/v1/schema `ConfigOptionUpdate`,
/// https://agentclientprotocol.com/protocol/v1/session-config-options).
/// Wire field is `configOptions` (array of `SessionConfigOption`). The
/// model chip reads the option whose `id` is `model` (same id we send
/// on `session/set_config_option`) and applies `currentValue`. The
/// `options` catalog is not stored. vercel-labs/fx `src/acp/types.zig`
/// and fx.sh ACP docs do not emit this today.
pub const SESSION_UPDATE_CONFIG_OPTION = "config_option_update";
/// Official ACP v1 `session/update` when slash commands change
/// (https://agentclientprotocol.com/protocol/v1/schema `AvailableCommandsUpdate`,
/// https://agentclientprotocol.com/protocol/v1/slash-commands).
/// Wire field is `availableCommands` (array of `AvailableCommand`:
/// required `name`, usually `description`, optional `input`/`hint`).
/// This cut stores name + description on the session (replace, not
/// append). `input` is ignored. No palette and no slash execution.
/// vercel-labs/fx `writeAvailableCommandsUpdate` emits this after
/// `session/new` (e2e expects `compact`).
pub const SESSION_UPDATE_AVAILABLE_COMMANDS = "available_commands_update";
/// Official ACP v1 `session/update` when session metadata changes
/// (https://agentclientprotocol.com/protocol/v1/schema `SessionInfoUpdate`,
/// https://agentclientprotocol.com/protocol/v1/session-list#updating-session-metadata).
/// Wire fields are optional `title`, `updatedAt`, `_meta`. `sessionId` is
/// on the notification `params`, not the update. Official docs: `cwd`
/// is immutable after setup and is **not** in this notification.
/// Faku only has a session `title` for this type — apply a non-empty
/// string `title`; empty / missing / null is ignore. `updatedAt` and
/// `_meta` have no session field. vercel-labs/fx
/// `writeModelRecoveryInfoUpdate` emits this with `_meta` only (no title).
pub const SESSION_UPDATE_SESSION_INFO = "session_info_update";
/// Cap matches the session store. Extra wire items are dropped.
pub const max_available_commands: usize = 32;
/// Renderable ACP `ToolCallContent` text (joined). Matches the turn body cap.
pub const max_tool_content: usize = 4096;
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
    session_request_permission,
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
            .session_request_permission => METHOD_SESSION_REQUEST_PERMISSION,
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
        if (std.mem.eql(u8, name, METHOD_SESSION_REQUEST_PERMISSION)) return .session_request_permission;
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
    /// True when `config_option_update` carried a string `currentValue`
    /// on the `id: "model"` option (empty string is still a value).
    has_config_model: bool = false,
    /// True when `available_commands_update` carried an `availableCommands`
    /// array (empty is a real replace/clear). Missing or non-array is ignore.
    has_available_commands: bool = false,
    available_commands: [max_available_commands]ParsedCommand = [_]ParsedCommand{.{}} ** max_available_commands,
    available_command_count: usize = 0,
    /// True when `tool_call` / `tool_call_update` carried a `content` array
    /// (empty is a real replace/clear). Missing / null / non-array is ignore.
    has_tool_content: bool = false,
    tool_content_storage: [max_tool_content]u8 = [_]u8{0} ** max_tool_content,
    tool_content_len: usize = 0,
    /// ACP `usage_update` token counts. Null unless that key is a number.
    used: ?u64 = null,
    size: ?u64 = null,
    has_error: bool = false,
    has_result: bool = false,
};

/// One ACP `AvailableCommand`. Slices alias the parsed line.
pub const ParsedCommand = struct {
    name: []const u8 = "",
    description: []const u8 = "",
};

/// Confirmed ACP `usage_update` fields (`used` + `size`). Both required.
pub const UsageUpdate = struct {
    used: u64,
    size: u64,
};

/// Confirmed ACP/fx tool-call fields. `toolCallId` is required; the
/// others are optional on `tool_call_update`. `content` aliases
/// `Parsed.tool_content_storage` when `has_content` is set.
pub const ToolUpdate = struct {
    tool_call_id: []const u8,
    title: []const u8 = "",
    kind: []const u8 = "",
    status: []const u8 = "",
    content: []const u8 = "",
    has_content: bool = false,
};

pub const TurnStdin = struct {
    cwd: []const u8,
    resume_id: []const u8 = "",
    prompt: []const u8,
    model: []const u8 = "",
    access_mode: []const u8 = "",
};

/// One ACP `PermissionOption`. Slices alias the parsed line.
/// `optionId` is what the reply must echo; `kind` is the official hint.
pub const PermissionOption = struct {
    option_id: []const u8 = "",
    kind: []const u8 = "",
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

/// Inverse of `sessionMode` for the fx ACP ids we already send.
/// `ask` → `ask`. `code` → `fullAccess` (the default Waku access;
/// `auto` / `yolo` also map forward to `code`, but there is no
/// third ACP id, so the reverse pick is `fullAccess`). Unknown
/// ids stay unmapped — do not invent `architect` or others.
pub fn accessModeFromSessionMode(mode_id: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, mode_id, MODE_ASK)) return "ask";
    if (std.mem.eql(u8, mode_id, MODE_CODE)) return "fullAccess";
    return null;
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

/// Official ACP v1 `RequestPermissionResponse`.
/// `{ outcome: { outcome: "selected", optionId } }` or `{ outcome: { outcome: "cancelled" } }`.
/// `id_json` is the raw JSON id token from the request (number or string).
pub fn writePermissionResponse(buf: []u8, id_json: []const u8, option_id: ?[]const u8) WriteError![]const u8 {
    var cur = Cursor{ .buf = buf };
    try cur.write("{\"jsonrpc\":\"");
    try cur.write(JSONRPC_VERSION);
    try cur.write("\",\"id\":");
    try cur.write(id_json);
    try cur.write(",\"result\":{\"outcome\":{\"outcome\":");
    if (option_id) |id| {
        try writeJsonString(&cur, OUTCOME_SELECTED);
        try cur.write(",\"optionId\":");
        try writeJsonString(&cur, id);
        try cur.write("}}}\n");
    } else {
        try writeJsonString(&cur, OUTCOME_CANCELLED);
        try cur.write("}}}\n");
    }
    return cur.slice();
}

/// JSON-RPC 2.0 method-not-found so an unknown agent request does not hang.
pub fn writeMethodNotFound(buf: []u8, id_json: []const u8) WriteError![]const u8 {
    var cur = Cursor{ .buf = buf };
    try cur.write("{\"jsonrpc\":\"");
    try cur.write(JSONRPC_VERSION);
    try cur.write("\",\"id\":");
    try cur.write(id_json);
    try cur.write(",\"error\":{\"code\":-32601,\"message\":\"Method not found\"}}\n");
    return cur.slice();
}

/// Sidecar stdin write for one agent stdout line, or null to only forward.
/// `session/request_permission` is answered from `access_mode`. Other
/// requests with an id are rejected. Notifications / responses / missing
/// id do not block.
pub fn replyForAgentRequest(line: []const u8, access_mode: []const u8, buf: []u8) ?[]const u8 {
    const parsed = parseLine(line);
    if (parsed.has_result or parsed.has_error) return null;
    const id_json = rawIdJson(line);
    if (id_json.len == 0) return null;
    if (parsed.method == .session_request_permission) {
        var options: [max_permission_options]PermissionOption = [_]PermissionOption{.{}} ** max_permission_options;
        const count = scanPermissionOptions(line, options[0..]) orelse 0;
        const option_id = pickPermissionOptionId(access_mode, options[0..count]);
        return writePermissionResponse(buf, id_json, option_id) catch null;
    }
    // Unknown agent→client methods still have an id; reject so fx does not hang.
    if (parsed.method == .unknown and parsed.method_name.len > 0) {
        return writeMethodNotFound(buf, id_json) catch null;
    }
    return null;
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

/// ACP v1 / official prompt-turn `agent_thought_chunk`. Same
/// `content: { type: "text", text }` block as `agent_message_chunk`.
pub fn isAgentThoughtText(parsed: Parsed) bool {
    return parsed.method == .session_update and
        std.mem.eql(u8, parsed.session_update, SESSION_UPDATE_AGENT_THOUGHT) and
        parsed.text.len > 0;
}

/// ACP v1 / fx `tool_call` and `tool_call_update`. `toolCallId` is required.
/// Title, kind, and status are whatever the frame carried (updates omit
/// unchanged fields). `content` is a replace when the frame carried an
/// array (fx writes text blocks on updates). Missing `content` keeps
/// the previous body.
pub fn toolUpdate(parsed: *const Parsed) ?ToolUpdate {
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
        .content = parsed.tool_content_storage[0..parsed.tool_content_len],
        .has_content = parsed.has_tool_content,
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

/// Header plus renderable ACP content. Empty content keeps today's
/// `title · kind · status` string so status-only updates stay stable.
pub fn toolTurnBody(
    buf: []u8,
    title: []const u8,
    kind: []const u8,
    status: []const u8,
    content: []const u8,
) []const u8 {
    const header = toolTurnText(buf, title, kind, status);
    if (content.len == 0) return header;
    var cur = header.len;
    if (cur > 0) {
        if (cur >= buf.len) return header;
        buf[cur] = '\n';
        cur += 1;
    }
    const take = @min(buf.len - cur, content.len);
    @memcpy(buf[cur..][0..take], content[0..take]);
    return buf[0 .. cur + take];
}

/// Official ACP v1 `current_mode_update`. `currentModeId` (or docs
/// `modeId`) must be a known fx id (`ask` | `code`). Unknown ids are
/// ignored so the access chip does not invent modes.
pub fn currentModeUpdate(parsed: Parsed) ?[]const u8 {
    if (parsed.method != .session_update) return null;
    if (!std.mem.eql(u8, parsed.session_update, SESSION_UPDATE_CURRENT_MODE)) return null;
    return accessModeFromSessionMode(parsed.mode_id);
}

/// Official ACP v1 `config_option_update`. Returns `currentValue` from
/// the `id: "model"` option. Missing option, non-string value, or a
/// different `sessionUpdate` is ignored. Empty `currentValue` is a
/// real update (chip stays the fx default label).
pub fn configOptionModel(parsed: Parsed) ?[]const u8 {
    if (parsed.method != .session_update) return null;
    if (!std.mem.eql(u8, parsed.session_update, SESSION_UPDATE_CONFIG_OPTION)) return null;
    if (!parsed.has_config_model) return null;
    return parsed.config_value;
}

/// Official ACP v1 `available_commands_update`. Empty array is a
/// clear. Missing / non-array `availableCommands` is ignored.
/// Nameless items are skipped (`x-deserialize-skip-invalid-items`).
pub fn availableCommandsUpdate(parsed: *const Parsed) ?[]const ParsedCommand {
    if (parsed.method != .session_update) return null;
    if (!std.mem.eql(u8, parsed.session_update, SESSION_UPDATE_AVAILABLE_COMMANDS)) return null;
    if (!parsed.has_available_commands) return null;
    return parsed.available_commands[0..parsed.available_command_count];
}

/// Official ACP v1 `session_info_update` `title`. Empty / missing /
/// null (and whitespace-only) is ignore so we do not wipe a name.
/// `cwd` is not a field on this update.
pub fn sessionInfoTitle(parsed: Parsed) ?[]const u8 {
    if (parsed.method != .session_update) return null;
    if (!std.mem.eql(u8, parsed.session_update, SESSION_UPDATE_SESSION_INFO)) return null;
    const title = std.mem.trim(u8, parsed.title, " \t\r\n");
    if (title.len == 0) return null;
    return title;
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

/// Official ACP v1 `session/request_permission` (agent → client).
pub fn isRequestPermission(parsed: Parsed) bool {
    return parsed.method == .session_request_permission and parsed.kind == .request;
}

/// `ask` is restrict. `auto` / `fullAccess` / `yolo` / `code` allow.
/// Unknown / empty stay restrict so a missing mode does not auto-allow.
pub fn permissionAllows(access_mode: []const u8) bool {
    if (std.mem.eql(u8, access_mode, "auto")) return true;
    if (std.mem.eql(u8, access_mode, "autoAcceptEdits")) return true;
    if (std.mem.eql(u8, access_mode, "fullAccess")) return true;
    if (std.mem.eql(u8, access_mode, "yolo")) return true;
    if (std.mem.eql(u8, access_mode, MODE_CODE)) return true;
    return false;
}

/// Pick an optionId the request actually listed. Allow modes prefer
/// `allow_once` then `allow_always`. Ask / unknown prefer `reject_always`
/// then `reject_once`. Null means official `cancelled` (no invented id).
pub fn pickPermissionOptionId(access_mode: []const u8, options: []const PermissionOption) ?[]const u8 {
    if (permissionAllows(access_mode)) {
        if (findOptionId(options, KIND_ALLOW_ONCE)) |id| return id;
        if (findOptionId(options, KIND_ALLOW_ALWAYS)) |id| return id;
        return null;
    }
    if (findOptionId(options, KIND_REJECT_ALWAYS)) |id| return id;
    if (findOptionId(options, KIND_REJECT_ONCE)) |id| return id;
    return null;
}

/// Access mode already on this sidecar run: `FX_PERMISSION_MODE=` in
/// the child argv, else `session/set_mode` `modeId` in the stdin batch.
/// `ask` on either side wins (more restrictive).
pub fn accessModeFromSidecarRun(argv: []const []const u8, stdin: []const u8) []const u8 {
    const env_mode = permissionModeFromArgv(argv);
    const set_mode = sessionModeFromStdin(stdin);
    if (isAskMode(env_mode) or isAskMode(set_mode)) return "ask";
    if (env_mode.len > 0) return env_mode;
    if (set_mode.len > 0) return set_mode;
    return "";
}

fn isAskMode(mode: []const u8) bool {
    return std.mem.eql(u8, mode, "ask") or std.mem.eql(u8, mode, MODE_ASK);
}

fn permissionModeFromArgv(argv: []const []const u8) []const u8 {
    const prefix = "FX_PERMISSION_MODE=";
    for (argv) |arg| {
        if (std.mem.startsWith(u8, arg, prefix)) return arg[prefix.len..];
    }
    return "";
}

fn sessionModeFromStdin(stdin: []const u8) []const u8 {
    var line_start: usize = 0;
    var found: []const u8 = "";
    while (line_start < stdin.len) {
        const nl = std.mem.indexOfScalarPos(u8, stdin, line_start, '\n') orelse stdin.len;
        const parsed = parseLine(stdin[line_start..nl]);
        line_start = if (nl < stdin.len) nl + 1 else stdin.len;
        if (parsed.method == .session_set_mode and parsed.mode_id.len > 0) {
            found = parsed.mode_id;
        }
    }
    return found;
}

fn findOptionId(options: []const PermissionOption, kind: []const u8) ?[]const u8 {
    for (options) |opt| {
        if (opt.option_id.len == 0) continue;
        if (kindMatches(opt.kind, kind) or kindMatches(opt.option_id, kind)) return opt.option_id;
    }
    return null;
}

/// Official kinds use underscores. Docs optionIds use hyphens.
fn kindMatches(got: []const u8, kind: []const u8) bool {
    if (std.mem.eql(u8, got, kind)) return true;
    if (got.len != kind.len) return false;
    for (got, kind) |g, k| {
        const gn: u8 = if (g == '-') '_' else g;
        if (gn != k) return false;
    }
    return true;
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

fn skipJsonString(text: []const u8, start: usize) usize {
    if (start >= text.len or text[start] != '"') return start;
    var i = start + 1;
    while (i < text.len) : (i += 1) {
        if (text[i] == '\\') {
            i += 1;
            continue;
        }
        if (text[i] == '"') return i + 1;
    }
    return text.len;
}

fn skipJsonValue(text: []const u8, start: usize) usize {
    const i = skipWs(text, start);
    if (i >= text.len) return i;
    return switch (text[i]) {
        '"' => skipJsonString(text, i),
        '{', '[' => skipJsonContainer(text, i),
        else => skipJsonAtom(text, i),
    };
}

fn skipJsonAtom(text: []const u8, start: usize) usize {
    var i = start;
    while (i < text.len) : (i += 1) {
        switch (text[i]) {
            ',', '}', ']', ' ', '\t', '\r', '\n' => return i,
            else => {},
        }
    }
    return i;
}

fn skipJsonContainer(text: []const u8, start: usize) usize {
    if (start >= text.len) return start;
    const open = text[start];
    const close: u8 = if (open == '{') '}' else if (open == '[') ']' else return start;
    var depth: usize = 0;
    var i = start;
    var in_string = false;
    var escape = false;
    while (i < text.len) : (i += 1) {
        const c = text[i];
        if (in_string) {
            if (escape) {
                escape = false;
            } else if (c == '\\') {
                escape = true;
            } else if (c == '"') {
                in_string = false;
            }
            continue;
        }
        switch (c) {
            '"' => in_string = true,
            '{', '[' => {
                if (c == open) depth += 1;
            },
            '}', ']' => {
                if (c == close) {
                    depth -= 1;
                    if (depth == 0) return i + 1;
                }
            },
            else => {},
        }
    }
    return text.len;
}

/// Immediate object field of one JSON object. Returns the `{` index.
fn objectObjectField(text: []const u8, start: usize, end: usize, key: []const u8) ?usize {
    if (start >= end or text[start] != '{') return null;
    var i = start + 1;
    while (i < end) {
        i = skipWs(text, i);
        if (i >= end or text[i] == '}') break;
        if (text[i] != '"') {
            i = skipJsonValue(text, i);
            continue;
        }
        const key_start = i + 1;
        const after_key = skipJsonString(text, i);
        if (after_key <= key_start) break;
        const key_slice = text[key_start .. after_key - 1];
        i = skipWs(text, after_key);
        if (i >= end or text[i] != ':') break;
        i = skipWs(text, i + 1);
        if (std.mem.eql(u8, key_slice, key)) {
            if (i < end and text[i] == '{') return i;
            return null;
        }
        i = skipJsonValue(text, i);
        i = skipWs(text, i);
        if (i < end and text[i] == ',') i += 1;
    }
    return null;
}

/// Immediate array field of one JSON object. Returns the `[` index.
fn objectArrayField(text: []const u8, start: usize, end: usize, key: []const u8) ?usize {
    if (start >= end or text[start] != '{') return null;
    var i = start + 1;
    while (i < end) {
        i = skipWs(text, i);
        if (i >= end or text[i] == '}') break;
        if (text[i] != '"') {
            i = skipJsonValue(text, i);
            continue;
        }
        const key_start = i + 1;
        const after_key = skipJsonString(text, i);
        if (after_key <= key_start) break;
        const key_slice = text[key_start .. after_key - 1];
        i = skipWs(text, after_key);
        if (i >= end or text[i] != ':') break;
        i = skipWs(text, i + 1);
        if (std.mem.eql(u8, key_slice, key)) {
            if (i < end and text[i] == '[') return i;
            return null;
        }
        i = skipJsonValue(text, i);
        i = skipWs(text, i);
        if (i < end and text[i] == ',') i += 1;
    }
    return null;
}

/// Immediate string field of one JSON object. Nested objects/arrays are
/// skipped so `options[].value` cannot shadow `currentValue`.
fn objectStringField(text: []const u8, start: usize, end: usize, key: []const u8) ?[]const u8 {
    if (start >= end or text[start] != '{') return null;
    var i = start + 1;
    while (i < end) {
        i = skipWs(text, i);
        if (i >= end or text[i] == '}') break;
        if (text[i] != '"') {
            i = skipJsonValue(text, i);
            continue;
        }
        const key_start = i + 1;
        const after_key = skipJsonString(text, i);
        if (after_key <= key_start) break;
        const key_slice = text[key_start .. after_key - 1];
        i = skipWs(text, after_key);
        if (i >= end or text[i] != ':') break;
        i = skipWs(text, i + 1);
        if (std.mem.eql(u8, key_slice, key)) {
            if (i < end and text[i] == '"') return parseJsonStringAt(text, i);
            return null;
        }
        i = skipJsonValue(text, i);
        i = skipWs(text, i);
        if (i < end and text[i] == ',') i += 1;
    }
    return null;
}

/// `availableCommands` array. Missing key or non-array is ignore.
/// Items without a string `name` are skipped. `description` is optional.
/// Nested `input.hint` is not stored.
fn scanAvailableCommands(text: []const u8, dest: []ParsedCommand) ?usize {
    const at = findKey(text, "availableCommands") orelse return null;
    var i = skipWs(text, at);
    if (i >= text.len or text[i] != '[') return null;
    i += 1;
    var count: usize = 0;
    while (i < text.len) {
        i = skipWs(text, i);
        if (i >= text.len or text[i] == ']') break;
        if (text[i] == ',') {
            i += 1;
            continue;
        }
        if (text[i] != '{') {
            i = skipJsonValue(text, i);
            continue;
        }
        const obj_end = skipJsonValue(text, i);
        const close = if (obj_end > i) obj_end - 1 else obj_end;
        const name = objectStringField(text, i, close, "name") orelse {
            i = obj_end;
            continue;
        };
        if (name.len == 0) {
            i = obj_end;
            continue;
        }
        if (count < dest.len) {
            dest[count] = .{
                .name = name,
                .description = objectStringField(text, i, close, "description") orelse "",
            };
            count += 1;
        }
        i = obj_end;
    }
    return count;
}

/// `params.options` on `session/request_permission`. Missing / non-array
/// is empty. Items without a string `optionId` are skipped. Nested
/// `toolCall.rawInput.options` is not this array.
fn scanPermissionOptions(text: []const u8, dest: []PermissionOption) ?usize {
    const params_at = findKey(text, "params") orelse return null;
    const at = skipWs(text, params_at);
    if (at >= text.len or text[at] != '{') return null;
    const params_end = skipJsonValue(text, at);
    const options_at = objectArrayField(text, at, params_end, "options") orelse return null;
    var i = skipWs(text, options_at);
    if (i >= text.len or text[i] != '[') return null;
    i += 1;
    var count: usize = 0;
    while (i < text.len) {
        i = skipWs(text, i);
        if (i >= text.len or text[i] == ']') break;
        if (text[i] == ',') {
            i += 1;
            continue;
        }
        if (text[i] != '{') {
            i = skipJsonValue(text, i);
            continue;
        }
        const obj_end = skipJsonValue(text, i);
        const close = if (obj_end > i) obj_end - 1 else obj_end;
        const option_id = objectStringField(text, i, close, "optionId") orelse {
            i = obj_end;
            continue;
        };
        if (option_id.len == 0) {
            i = obj_end;
            continue;
        }
        if (count < dest.len) {
            dest[count] = .{
                .option_id = option_id,
                .kind = objectStringField(text, i, close, "kind") orelse "",
            };
            count += 1;
        }
        i = obj_end;
    }
    return count;
}

/// Raw JSON-RPC `id` token so the reply can echo a number or a string.
fn rawIdJson(text: []const u8) []const u8 {
    const at = findKey(text, "id") orelse return "";
    const start = skipWs(text, at);
    if (start >= text.len) return "";
    const end = skipJsonValue(text, start);
    if (end <= start) return "";
    return text[start..end];
}

/// `configOptions` entry whose `id` is `model` and whose `currentValue`
/// is a string. Other options, boolean values, and missing fields drop.
fn scanConfigOptionModel(text: []const u8) ?[]const u8 {
    const at = findKey(text, "configOptions") orelse return null;
    var i = skipWs(text, at);
    if (i >= text.len or text[i] != '[') return null;
    i += 1;
    while (i < text.len) {
        i = skipWs(text, i);
        if (i >= text.len or text[i] == ']') break;
        if (text[i] == ',') {
            i += 1;
            continue;
        }
        if (text[i] != '{') {
            i = skipJsonValue(text, i);
            continue;
        }
        const obj_end = skipJsonValue(text, i);
        const close = if (obj_end > i) obj_end - 1 else obj_end;
        const id = objectStringField(text, i, close, "id") orelse {
            i = obj_end;
            continue;
        };
        if (std.mem.eql(u8, id, CONFIG_ID_MODEL)) {
            return objectStringField(text, i, close, "currentValue");
        }
        i = obj_end;
    }
    return null;
}

fn updateObjectRange(text: []const u8) ?struct { start: usize, close: usize } {
    const at = findKey(text, "update") orelse return null;
    const start = skipWs(text, at);
    if (start >= text.len or text[start] != '{') return null;
    const end = skipJsonValue(text, start);
    const close = if (end > start) end - 1 else end;
    return .{ .start = start, .close = close };
}

fn appendRaw(dest: []u8, cur: usize, bytes: []const u8) usize {
    const take = @min(dest.len -| cur, bytes.len);
    if (take == 0) return cur;
    @memcpy(dest[cur..][0..take], bytes[0..take]);
    return cur + take;
}

/// Copy a JSON string body, turning `\\n` / `\\t` / quotes into bytes.
fn appendUnescapedJson(dest: []u8, cur: usize, raw: []const u8) usize {
    var i: usize = 0;
    var o = cur;
    while (i < raw.len and o < dest.len) {
        if (raw[i] == '\\' and i + 1 < raw.len) {
            i += 1;
            dest[o] = switch (raw[i]) {
                'n' => '\n',
                'r' => '\r',
                't' => '\t',
                '"' => '"',
                '\\' => '\\',
                '/' => '/',
                else => raw[i],
            };
            o += 1;
            i += 1;
            continue;
        }
        dest[o] = raw[i];
        o += 1;
        i += 1;
    }
    return o;
}

fn appendSeparatedUnescaped(dest: []u8, cur: usize, raw: []const u8) usize {
    if (raw.len == 0) return cur;
    var next = cur;
    if (next > 0) next = appendRaw(dest, next, "\n\n");
    return appendUnescapedJson(dest, next, raw);
}

/// Official `ContentBlock` inside `ToolCallContent` `{ type: "content" }`.
/// Text and embedded text resources are shown. Image / audio / blob skip.
fn appendNestedContentBlock(text: []const u8, start: usize, close: usize, dest: []u8, cur: usize) usize {
    const nested_at = objectObjectField(text, start, close, "content") orelse return cur;
    const nested_end = skipJsonValue(text, nested_at);
    const nested_close = if (nested_end > nested_at) nested_end - 1 else nested_end;
    const nested_type = objectStringField(text, nested_at, nested_close, "type") orelse return cur;
    if (std.mem.eql(u8, nested_type, "text")) {
        const raw = objectStringField(text, nested_at, nested_close, "text") orelse return cur;
        return appendSeparatedUnescaped(dest, cur, raw);
    }
    if (std.mem.eql(u8, nested_type, "resource")) {
        const res_at = objectObjectField(text, nested_at, nested_close, "resource") orelse return cur;
        const res_end = skipJsonValue(text, res_at);
        const res_close = if (res_end > res_at) res_end - 1 else res_end;
        if (objectStringField(text, res_at, res_close, "blob") != null) return cur;
        const raw = objectStringField(text, res_at, res_close, "text") orelse return cur;
        return appendSeparatedUnescaped(dest, cur, raw);
    }
    if (std.mem.eql(u8, nested_type, "resource_link")) {
        const label = objectStringField(text, nested_at, nested_close, "title") orelse
            objectStringField(text, nested_at, nested_close, "name") orelse "";
        const uri = objectStringField(text, nested_at, nested_close, "uri") orelse "";
        if (label.len == 0 and uri.len == 0) return cur;
        var next = cur;
        if (next > 0) next = appendRaw(dest, next, "\n\n");
        if (label.len > 0) next = appendUnescapedJson(dest, next, label);
        if (uri.len > 0) {
            if (label.len > 0) next = appendRaw(dest, next, "\n");
            next = appendUnescapedJson(dest, next, uri);
        }
        return next;
    }
    return cur;
}

/// Official `ToolCallContent` `{ type: "diff" }`. Native has no diff
/// widget — path + old/new text as markdown/plain patch source.
fn appendDiffBlock(text: []const u8, start: usize, close: usize, dest: []u8, cur: usize) usize {
    const path = objectStringField(text, start, close, "path") orelse "";
    const old_text = objectStringField(text, start, close, "oldText");
    const new_text = objectStringField(text, start, close, "newText");
    if (path.len == 0 and old_text == null and new_text == null) return cur;
    var next = cur;
    if (next > 0) next = appendRaw(dest, next, "\n\n");
    if (path.len > 0) {
        next = appendUnescapedJson(dest, next, path);
        if (old_text != null or new_text != null) next = appendRaw(dest, next, "\n");
    }
    if (old_text) |old| {
        next = appendRaw(dest, next, "---\n");
        next = appendUnescapedJson(dest, next, old);
        if (new_text != null) next = appendRaw(dest, next, "\n");
    }
    if (new_text) |new| {
        next = appendRaw(dest, next, "+++\n");
        next = appendUnescapedJson(dest, next, new);
    }
    return next;
}

fn appendToolContentItem(text: []const u8, start: usize, close: usize, dest: []u8, cur: usize) usize {
    const typ = objectStringField(text, start, close, "type") orelse return cur;
    if (std.mem.eql(u8, typ, "content")) return appendNestedContentBlock(text, start, close, dest, cur);
    if (std.mem.eql(u8, typ, "diff")) return appendDiffBlock(text, start, close, dest, cur);
    return cur;
}

/// Official ACP v1 `ToolCallContent[]` on the `update` object.
/// Schema kinds: `content`, `diff`, `terminal`. Missing / null /
/// non-array is ignore. Empty array is a replace/clear.
fn scanToolCallContent(text: []const u8, dest: []u8) ?usize {
    const range = updateObjectRange(text) orelse return null;
    const arr_at = objectArrayField(text, range.start, range.close, "content") orelse return null;
    var i = arr_at + 1;
    var cur: usize = 0;
    while (i < text.len) {
        i = skipWs(text, i);
        if (i >= text.len or text[i] == ']') break;
        if (text[i] == ',') {
            i += 1;
            continue;
        }
        if (text[i] != '{') {
            i = skipJsonValue(text, i);
            continue;
        }
        const obj_end = skipJsonValue(text, i);
        const close = if (obj_end > i) obj_end - 1 else obj_end;
        cur = appendToolContentItem(text, i, close, dest, cur);
        i = obj_end;
    }
    return cur;
}

fn applyToolCallWireFields(text: []const u8, parsed: *Parsed) void {
    if (updateObjectRange(text)) |range| {
        if (objectStringField(text, range.start, range.close, "toolCallId")) |id| {
            parsed.tool_call_id = id;
        }
        // Immediate update fields only — nested content `title` / `kind`
        // must not shadow a missing tool-call title on updates.
        parsed.title = objectStringField(text, range.start, range.close, "title") orelse "";
        parsed.tool_kind = objectStringField(text, range.start, range.close, "kind") orelse "";
        parsed.status = objectStringField(text, range.start, range.close, "status") orelse "";
    }
    if (scanToolCallContent(text, parsed.tool_content_storage[0..])) |n| {
        parsed.has_tool_content = true;
        parsed.tool_content_len = n;
    }
}

/// Parse one NDJSON JSON-RPC line. Slices alias `line` and die with it.
/// Field scanner — classifies the methods above and pulls `id`,
/// `sessionId`, `sessionUpdate`, `text`, `toolCallId`, `title`, `kind`,
/// `status`, `stopReason`, `currentModeId` / `modeId`,
/// `config_option_update` `configOptions` `id: "model"` `currentValue`,
/// `available_commands_update` `availableCommands` name/description,
/// `session_info_update` `title`, and tool-call `content` blocks
/// (text / diff as markdown/plain; image, audio, terminal skipped).
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

    // Official CurrentModeUpdate field is `currentModeId`. `modeId` is
    // `session/set_mode` and the session-modes docs example.
    if (findKey(trimmed, "currentModeId")) |at| {
        parsed.mode_id = parseJsonStringAt(trimmed, at);
    } else if (findKey(trimmed, "modeId")) |at| {
        parsed.mode_id = parseJsonStringAt(trimmed, at);
    }

    if (findKey(trimmed, "configId")) |at| {
        parsed.config_id = parseJsonStringAt(trimmed, at);
    }

    if (findKey(trimmed, "value")) |at| {
        parsed.config_value = parseJsonStringAt(trimmed, at);
    }

    if (std.mem.eql(u8, parsed.session_update, SESSION_UPDATE_CONFIG_OPTION)) {
        if (scanConfigOptionModel(trimmed)) |value| {
            parsed.config_id = CONFIG_ID_MODEL;
            parsed.config_value = value;
            parsed.has_config_model = true;
        }
    }

    if (std.mem.eql(u8, parsed.session_update, SESSION_UPDATE_AVAILABLE_COMMANDS)) {
        if (scanAvailableCommands(trimmed, parsed.available_commands[0..])) |count| {
            parsed.has_available_commands = true;
            parsed.available_command_count = count;
        }
    }

    if (std.mem.eql(u8, parsed.session_update, SESSION_UPDATE_TOOL_CALL) or
        std.mem.eql(u8, parsed.session_update, SESSION_UPDATE_TOOL_CALL_UPDATE))
    {
        applyToolCallWireFields(trimmed, &parsed);
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

test "fx ACP ask|code reverse-map to Waku access_mode; unknown ids stay unmapped" {
    try std.testing.expectEqualStrings("ask", accessModeFromSessionMode(MODE_ASK).?);
    try std.testing.expectEqualStrings("fullAccess", accessModeFromSessionMode(MODE_CODE).?);
    try std.testing.expect(accessModeFromSessionMode("architect") == null);
    try std.testing.expect(accessModeFromSessionMode("auto") == null);
    try std.testing.expect(accessModeFromSessionMode("yolo") == null);
    try std.testing.expect(accessModeFromSessionMode("") == null);
    try std.testing.expectEqualStrings(MODE_ASK, sessionMode(accessModeFromSessionMode(MODE_ASK).?));
    try std.testing.expectEqualStrings(MODE_CODE, sessionMode(accessModeFromSessionMode(MODE_CODE).?));
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
    try std.testing.expect(!isAgentThoughtText(parsed_update));
    try std.testing.expectEqualStrings("hello acp", parsed_update.text);

    const thought = parseLine("{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"sessionId\":\"sess-1\",\"update\":{\"sessionUpdate\":\"agent_thought_chunk\",\"content\":{\"type\":\"text\",\"text\":\"need to inspect the loop\"}}}}");
    try std.testing.expectEqual(Method.session_update, thought.method);
    try std.testing.expectEqualStrings(SESSION_UPDATE_AGENT_THOUGHT, thought.session_update);
    try std.testing.expect(isAgentThoughtText(thought));
    try std.testing.expect(!isAgentMessageText(thought));
    try std.testing.expectEqualStrings("need to inspect the loop", thought.text);
    try std.testing.expect(toolUpdate(&thought) == null);
    try std.testing.expect(usageUpdate(thought) == null);
    try std.testing.expect(currentModeUpdate(thought) == null);
    try std.testing.expect(configOptionModel(thought) == null);
    try std.testing.expect(availableCommandsUpdate(&thought) == null);
    try std.testing.expect(sessionInfoTitle(thought) == null);

    const mode_ask = parseLine("{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"sessionId\":\"sess-1\",\"update\":{\"sessionUpdate\":\"current_mode_update\",\"currentModeId\":\"ask\"}}}");
    try std.testing.expectEqual(Method.session_update, mode_ask.method);
    try std.testing.expectEqualStrings(SESSION_UPDATE_CURRENT_MODE, mode_ask.session_update);
    try std.testing.expectEqualStrings(MODE_ASK, mode_ask.mode_id);
    try std.testing.expectEqualStrings("ask", currentModeUpdate(mode_ask).?);
    try std.testing.expect(!isAgentMessageText(mode_ask));
    try std.testing.expect(!isAgentThoughtText(mode_ask));
    try std.testing.expect(toolUpdate(&mode_ask) == null);
    try std.testing.expect(usageUpdate(mode_ask) == null);

    const mode_code = parseLine("{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"update\":{\"sessionUpdate\":\"current_mode_update\",\"currentModeId\":\"code\"}}}");
    try std.testing.expectEqualStrings("fullAccess", currentModeUpdate(mode_code).?);

    const mode_docs_mode_id = parseLine("{\"method\":\"session/update\",\"params\":{\"update\":{\"sessionUpdate\":\"current_mode_update\",\"modeId\":\"ask\"}}}");
    try std.testing.expectEqualStrings("ask", currentModeUpdate(mode_docs_mode_id).?);

    const mode_unknown = parseLine("{\"method\":\"session/update\",\"params\":{\"update\":{\"sessionUpdate\":\"current_mode_update\",\"currentModeId\":\"architect\"}}}");
    try std.testing.expectEqualStrings(SESSION_UPDATE_CURRENT_MODE, mode_unknown.session_update);
    try std.testing.expectEqualStrings("architect", mode_unknown.mode_id);
    try std.testing.expect(currentModeUpdate(mode_unknown) == null);
    try std.testing.expect(configOptionModel(mode_unknown) == null);
    try std.testing.expect(sessionInfoTitle(mode_unknown) == null);

    const mode_missing_id = parseLine("{\"method\":\"session/update\",\"params\":{\"update\":{\"sessionUpdate\":\"current_mode_update\"}}}");
    try std.testing.expect(currentModeUpdate(mode_missing_id) == null);

    const config_model = parseLine("{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"sessionId\":\"sess-1\",\"update\":{\"sessionUpdate\":\"config_option_update\",\"configOptions\":[{\"id\":\"mode\",\"name\":\"Session Mode\",\"type\":\"select\",\"currentValue\":\"code\",\"options\":[{\"value\":\"ask\",\"name\":\"Ask\"}]},{\"id\":\"model\",\"name\":\"Model\",\"type\":\"select\",\"currentValue\":\"openai/gpt-5.4\",\"options\":[{\"value\":\"openai/gpt-5.4\",\"name\":\"GPT\"}]}]}}}");
    try std.testing.expectEqual(Method.session_update, config_model.method);
    try std.testing.expectEqualStrings(SESSION_UPDATE_CONFIG_OPTION, config_model.session_update);
    try std.testing.expectEqualStrings(CONFIG_ID_MODEL, config_model.config_id);
    try std.testing.expectEqualStrings("openai/gpt-5.4", configOptionModel(config_model).?);
    try std.testing.expect(!isAgentMessageText(config_model));
    try std.testing.expect(!isAgentThoughtText(config_model));
    try std.testing.expect(currentModeUpdate(config_model) == null);
    try std.testing.expect(toolUpdate(&config_model) == null);
    try std.testing.expect(usageUpdate(config_model) == null);
    try std.testing.expect(availableCommandsUpdate(&config_model) == null);
    try std.testing.expect(sessionInfoTitle(config_model) == null);

    const config_empty = parseLine("{\"method\":\"session/update\",\"params\":{\"update\":{\"sessionUpdate\":\"config_option_update\",\"configOptions\":[{\"id\":\"model\",\"name\":\"Model\",\"type\":\"select\",\"currentValue\":\"\",\"options\":[]}]}}}");
    try std.testing.expectEqualStrings("", configOptionModel(config_empty).?);

    const config_mode_only = parseLine("{\"method\":\"session/update\",\"params\":{\"update\":{\"sessionUpdate\":\"config_option_update\",\"configOptions\":[{\"id\":\"mode\",\"name\":\"Session Mode\",\"type\":\"select\",\"currentValue\":\"ask\",\"options\":[]}]}}}");
    try std.testing.expectEqualStrings(SESSION_UPDATE_CONFIG_OPTION, config_mode_only.session_update);
    try std.testing.expect(configOptionModel(config_mode_only) == null);

    const config_missing_value = parseLine("{\"method\":\"session/update\",\"params\":{\"update\":{\"sessionUpdate\":\"config_option_update\",\"configOptions\":[{\"id\":\"model\",\"name\":\"Model\",\"type\":\"select\",\"options\":[]}]}}}");
    try std.testing.expect(configOptionModel(config_missing_value) == null);

    const config_boolean = parseLine("{\"method\":\"session/update\",\"params\":{\"update\":{\"sessionUpdate\":\"config_option_update\",\"configOptions\":[{\"id\":\"model\",\"name\":\"Model\",\"type\":\"boolean\",\"currentValue\":true}]}}}");
    try std.testing.expect(configOptionModel(config_boolean) == null);

    const config_missing_options = parseLine("{\"method\":\"session/update\",\"params\":{\"update\":{\"sessionUpdate\":\"config_option_update\"}}}");
    try std.testing.expect(configOptionModel(config_missing_options) == null);

    const commands = parseLine("{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"sessionId\":\"sess-1\",\"update\":{\"sessionUpdate\":\"available_commands_update\",\"availableCommands\":[{\"name\":\"web\",\"description\":\"Search the web for information\",\"input\":{\"hint\":\"query to search for\"}},{\"name\":\"test\",\"description\":\"Run tests for the current project\"},{\"name\":\"compact\"},{\"description\":\"nameless is skipped\"}]}}}");
    try std.testing.expectEqual(Method.session_update, commands.method);
    try std.testing.expectEqualStrings(SESSION_UPDATE_AVAILABLE_COMMANDS, commands.session_update);
    const command_list = availableCommandsUpdate(&commands) orelse return error.MissingCommands;
    try std.testing.expectEqual(@as(usize, 3), command_list.len);
    try std.testing.expectEqualStrings("web", command_list[0].name);
    try std.testing.expectEqualStrings("Search the web for information", command_list[0].description);
    try std.testing.expectEqualStrings("test", command_list[1].name);
    try std.testing.expectEqualStrings("Run tests for the current project", command_list[1].description);
    try std.testing.expectEqualStrings("compact", command_list[2].name);
    try std.testing.expectEqualStrings("", command_list[2].description);
    try std.testing.expect(!isAgentMessageText(commands));
    try std.testing.expect(!isAgentThoughtText(commands));
    try std.testing.expect(currentModeUpdate(commands) == null);
    try std.testing.expect(configOptionModel(commands) == null);
    try std.testing.expect(toolUpdate(&commands) == null);
    try std.testing.expect(usageUpdate(commands) == null);
    try std.testing.expect(sessionInfoTitle(commands) == null);

    const commands_empty = parseLine("{\"method\":\"session/update\",\"params\":{\"update\":{\"sessionUpdate\":\"available_commands_update\",\"availableCommands\":[]}}}");
    const empty_list = availableCommandsUpdate(&commands_empty) orelse return error.MissingEmptyCommands;
    try std.testing.expectEqual(@as(usize, 0), empty_list.len);

    const commands_missing = parseLine("{\"method\":\"session/update\",\"params\":{\"update\":{\"sessionUpdate\":\"available_commands_update\"}}}");
    try std.testing.expectEqualStrings(SESSION_UPDATE_AVAILABLE_COMMANDS, commands_missing.session_update);
    try std.testing.expect(availableCommandsUpdate(&commands_missing) == null);

    const commands_object = parseLine("{\"method\":\"session/update\",\"params\":{\"update\":{\"sessionUpdate\":\"available_commands_update\",\"availableCommands\":{\"name\":\"web\"}}}}");
    try std.testing.expect(availableCommandsUpdate(&commands_object) == null);

    const user = parseLine("{\"method\":\"session/update\",\"params\":{\"update\":{\"sessionUpdate\":\"user_message_chunk\",\"content\":{\"type\":\"text\",\"text\":\"ignore\"}}}}");
    try std.testing.expect(!isAgentMessageText(user));
    try std.testing.expect(!isAgentThoughtText(user));
    try std.testing.expect(usageUpdate(user) == null);
    try std.testing.expect(sessionInfoTitle(user) == null);

    const info_title = parseLine("{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"sessionId\":\"sess-1\",\"update\":{\"sessionUpdate\":\"session_info_update\",\"title\":\"Implement user authentication\",\"updatedAt\":\"2025-10-29T14:22:15Z\",\"_meta\":{\"tags\":[\"feature\"]}}}}");
    try std.testing.expectEqual(Method.session_update, info_title.method);
    try std.testing.expectEqualStrings(SESSION_UPDATE_SESSION_INFO, info_title.session_update);
    try std.testing.expectEqualStrings("Implement user authentication", sessionInfoTitle(info_title).?);
    try std.testing.expectEqualStrings("sess-1", info_title.session_id);
    try std.testing.expect(!isAgentMessageText(info_title));
    try std.testing.expect(!isAgentThoughtText(info_title));
    try std.testing.expect(currentModeUpdate(info_title) == null);
    try std.testing.expect(configOptionModel(info_title) == null);
    try std.testing.expect(availableCommandsUpdate(&info_title) == null);
    try std.testing.expect(toolUpdate(&info_title) == null);
    try std.testing.expect(usageUpdate(info_title) == null);

    const info_empty = parseLine("{\"method\":\"session/update\",\"params\":{\"update\":{\"sessionUpdate\":\"session_info_update\",\"title\":\"\"}}}");
    try std.testing.expectEqualStrings(SESSION_UPDATE_SESSION_INFO, info_empty.session_update);
    try std.testing.expect(sessionInfoTitle(info_empty) == null);

    const info_null = parseLine("{\"method\":\"session/update\",\"params\":{\"update\":{\"sessionUpdate\":\"session_info_update\",\"title\":null}}}");
    try std.testing.expect(sessionInfoTitle(info_null) == null);

    const info_missing = parseLine("{\"method\":\"session/update\",\"params\":{\"update\":{\"sessionUpdate\":\"session_info_update\",\"updatedAt\":\"2025-10-29T14:22:15Z\"}}}");
    try std.testing.expectEqualStrings(SESSION_UPDATE_SESSION_INFO, info_missing.session_update);
    try std.testing.expect(sessionInfoTitle(info_missing) == null);

    const info_fx_meta = parseLine("{\"method\":\"session/update\",\"params\":{\"update\":{\"sessionUpdate\":\"session_info_update\",\"_meta\":{\"fx\":{\"modelResponseRecovery\":null}}}}}");
    try std.testing.expect(sessionInfoTitle(info_fx_meta) == null);

    const info_cwd_only = parseLine("{\"method\":\"session/update\",\"params\":{\"update\":{\"sessionUpdate\":\"session_info_update\",\"cwd\":\"/tmp/project\"}}}");
    try std.testing.expect(sessionInfoTitle(info_cwd_only) == null);

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
    const tool_fields = toolUpdate(&tool_call) orelse return error.MissingTool;
    try std.testing.expectEqualStrings("call_001", tool_fields.tool_call_id);
    try std.testing.expectEqualStrings("Reading file", tool_fields.title);
    try std.testing.expectEqualStrings("read", tool_fields.kind);
    try std.testing.expectEqualStrings("pending", tool_fields.status);
    try std.testing.expect(!tool_fields.has_content);
    try std.testing.expectEqualStrings("", tool_fields.content);
    try std.testing.expect(!isAgentMessageText(tool_call));
    try std.testing.expect(usageUpdate(tool_call) == null);
    try std.testing.expect(sessionInfoTitle(tool_call) == null);
    var tool_text_buf: [64]u8 = undefined;
    try std.testing.expectEqualStrings(
        "Reading file · read · pending",
        toolTurnText(&tool_text_buf, tool_fields.title, tool_fields.kind, tool_fields.status),
    );

    const tool_progress = parseLine("{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"update\":{\"sessionUpdate\":\"tool_call_update\",\"toolCallId\":\"call_001\",\"status\":\"in_progress\"}}}");
    const progress_fields = toolUpdate(&tool_progress) orelse return error.MissingToolUpdate;
    try std.testing.expectEqualStrings(SESSION_UPDATE_TOOL_CALL_UPDATE, tool_progress.session_update);
    try std.testing.expectEqualStrings("call_001", progress_fields.tool_call_id);
    try std.testing.expectEqualStrings("", progress_fields.title);
    try std.testing.expectEqualStrings("", progress_fields.kind);
    try std.testing.expectEqualStrings("in_progress", progress_fields.status);
    try std.testing.expect(!progress_fields.has_content);

    const tool_text_content = parseLine("{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"update\":{\"sessionUpdate\":\"tool_call\",\"toolCallId\":\"call_002\",\"title\":\"Reading file\",\"kind\":\"read\",\"status\":\"pending\",\"content\":[{\"type\":\"content\",\"content\":{\"type\":\"text\",\"text\":\"Found 3 files\"}},{\"type\":\"diff\",\"path\":\"src/config.json\",\"oldText\":\"{\\n  \\\"debug\\\": false\\n}\",\"newText\":\"{\\n  \\\"debug\\\": true\\n}\"},{\"type\":\"content\",\"content\":{\"type\":\"image\",\"mimeType\":\"image/png\",\"data\":\"aaaa\"}},{\"type\":\"terminal\",\"terminalId\":\"term_1\"},{\"type\":\"not_a_real_block\",\"text\":\"ignore\"}]}}}");
    const text_content_fields = toolUpdate(&tool_text_content) orelse return error.MissingToolContent;
    try std.testing.expect(text_content_fields.has_content);
    try std.testing.expectEqualStrings(
        "Found 3 files\n\nsrc/config.json\n---\n{\n  \"debug\": false\n}\n+++\n{\n  \"debug\": true\n}",
        text_content_fields.content,
    );
    try std.testing.expectEqualStrings("Reading file", text_content_fields.title);
    try std.testing.expectEqualStrings("pending", text_content_fields.status);
    try std.testing.expect(std.mem.indexOf(u8, text_content_fields.content, "aaaa") == null);
    try std.testing.expect(std.mem.indexOf(u8, text_content_fields.content, "term_1") == null);
    try std.testing.expect(std.mem.indexOf(u8, text_content_fields.content, "ignore") == null);
    var tool_body_buf: [256]u8 = undefined;
    try std.testing.expectEqualStrings(
        "Reading file · read · pending\nFound 3 files\n\nsrc/config.json\n---\n{\n  \"debug\": false\n}\n+++\n{\n  \"debug\": true\n}",
        toolTurnBody(&tool_body_buf, text_content_fields.title, text_content_fields.kind, text_content_fields.status, text_content_fields.content),
    );

    const tool_replace = parseLine("{\"method\":\"session/update\",\"params\":{\"update\":{\"sessionUpdate\":\"tool_call_update\",\"toolCallId\":\"call_002\",\"status\":\"completed\",\"content\":[{\"type\":\"content\",\"content\":{\"type\":\"text\",\"text\":\"done now\"}}]}}}");
    const replace_fields = toolUpdate(&tool_replace) orelse return error.MissingToolReplace;
    try std.testing.expect(replace_fields.has_content);
    try std.testing.expectEqualStrings("done now", replace_fields.content);
    try std.testing.expectEqualStrings("completed", replace_fields.status);
    try std.testing.expectEqualStrings("", replace_fields.title);

    const tool_empty_content = parseLine("{\"method\":\"session/update\",\"params\":{\"update\":{\"sessionUpdate\":\"tool_call_update\",\"toolCallId\":\"call_002\",\"content\":[]}}}");
    const empty_content_fields = toolUpdate(&tool_empty_content) orelse return error.MissingEmptyContent;
    try std.testing.expect(empty_content_fields.has_content);
    try std.testing.expectEqualStrings("", empty_content_fields.content);

    const tool_null_content = parseLine("{\"method\":\"session/update\",\"params\":{\"update\":{\"sessionUpdate\":\"tool_call_update\",\"toolCallId\":\"call_002\",\"content\":null}}}");
    const null_content_fields = toolUpdate(&tool_null_content) orelse return error.MissingNullContent;
    try std.testing.expect(!null_content_fields.has_content);

    const tool_missing_id = parseLine("{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"update\":{\"sessionUpdate\":\"tool_call\",\"title\":\"Reading file\",\"kind\":\"read\",\"status\":\"pending\"}}}");
    try std.testing.expect(toolUpdate(&tool_missing_id) == null);

    const settled = parseLine("{\"jsonrpc\":\"2.0\",\"id\":3,\"result\":{\"stopReason\":\"end_turn\"}}");
    try std.testing.expect(isPromptResult(settled));
    try std.testing.expect(promptSucceeded(settled));
    try std.testing.expectEqualStrings(STOP_END_TURN, settled.stop_reason);

    const cancelled = parseLine("{\"jsonrpc\":\"2.0\",\"id\":3,\"result\":{\"stopReason\":\"cancelled\"}}");
    try std.testing.expect(isPromptResult(cancelled));
    try std.testing.expect(!promptSucceeded(cancelled));
}

/// vercel-labs/fx `src/acp/prompt.zig` `writePermissionOption` + e2e.
const fx_request_permission =
    "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"session/request_permission\",\"params\":{\"sessionId\":\"sess_abc123def456\",\"toolCall\":{\"toolCallId\":\"call_001\",\"title\":\"Run command\",\"kind\":\"execute\",\"status\":\"pending\"},\"options\":[{\"optionId\":\"allow_once\",\"name\":\"Allow once\",\"kind\":\"allow_once\"},{\"optionId\":\"allow_always\",\"name\":\"Allow for this session\",\"kind\":\"allow_always\"},{\"optionId\":\"reject_once\",\"name\":\"Reject\",\"kind\":\"reject_once\"}]}}";

/// Official ACP v1 docs example (hyphenated optionIds, kinds underscored).
const docs_request_permission =
    "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"session/request_permission\",\"params\":{\"sessionId\":\"sess_abc123def456\",\"toolCall\":{\"toolCallId\":\"call_001\"},\"options\":[{\"optionId\":\"allow-once\",\"name\":\"Allow once\",\"kind\":\"allow_once\"},{\"optionId\":\"reject-once\",\"name\":\"Reject\",\"kind\":\"reject_once\"}]}}";

test "permission picker reads fx option ids; ask vs auto/fullAccess differ" {
    var options: [max_permission_options]PermissionOption = [_]PermissionOption{.{}} ** max_permission_options;
    const count = scanPermissionOptions(fx_request_permission, options[0..]) orelse return error.MissingOptions;
    try std.testing.expectEqual(@as(usize, 3), count);
    try std.testing.expectEqualStrings("allow_once", options[0].option_id);
    try std.testing.expectEqualStrings(KIND_ALLOW_ONCE, options[0].kind);
    try std.testing.expectEqualStrings("allow_always", options[1].option_id);
    try std.testing.expectEqualStrings(KIND_ALLOW_ALWAYS, options[1].kind);
    try std.testing.expectEqualStrings("reject_once", options[2].option_id);
    try std.testing.expectEqualStrings(KIND_REJECT_ONCE, options[2].kind);

    try std.testing.expectEqualStrings("reject_once", pickPermissionOptionId("ask", options[0..count]).?);
    try std.testing.expectEqualStrings("allow_once", pickPermissionOptionId("auto", options[0..count]).?);
    try std.testing.expectEqualStrings("allow_once", pickPermissionOptionId("fullAccess", options[0..count]).?);
    try std.testing.expectEqualStrings("allow_once", pickPermissionOptionId("yolo", options[0..count]).?);
    try std.testing.expectEqualStrings("allow_once", pickPermissionOptionId(MODE_CODE, options[0..count]).?);
    try std.testing.expect(pickPermissionOptionId("", options[0..count]) != null);
    try std.testing.expectEqualStrings("reject_once", pickPermissionOptionId("", options[0..count]).?);
    try std.testing.expectEqualStrings("reject_once", pickPermissionOptionId("nope", options[0..count]).?);

    try std.testing.expect(!permissionAllows("ask"));
    try std.testing.expect(permissionAllows("auto"));
    try std.testing.expect(permissionAllows("fullAccess"));
    try std.testing.expect(permissionAllows(MODE_CODE));
    try std.testing.expect(!permissionAllows(""));

    var buf: [256]u8 = undefined;
    const ask_reply = replyForAgentRequest(fx_request_permission, "ask", &buf) orelse return error.MissingAskReply;
    try std.testing.expect(std.mem.indexOf(u8, ask_reply, "\"id\":5") != null);
    try std.testing.expect(std.mem.indexOf(u8, ask_reply, "\"outcome\":\"selected\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, ask_reply, "\"optionId\":\"reject_once\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, ask_reply, "allow_once") == null);

    const auto_reply = replyForAgentRequest(fx_request_permission, "auto", &buf) orelse return error.MissingAutoReply;
    try std.testing.expect(std.mem.indexOf(u8, auto_reply, "\"optionId\":\"allow_once\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, auto_reply, "reject_once") == null);

    const full_reply = replyForAgentRequest(fx_request_permission, "fullAccess", &buf) orelse return error.MissingFullReply;
    try std.testing.expect(std.mem.indexOf(u8, full_reply, "\"optionId\":\"allow_once\"") != null);

    const parsed_req = parseLine(fx_request_permission);
    try std.testing.expect(isRequestPermission(parsed_req));
    try std.testing.expectEqual(Method.session_request_permission, parsed_req.method);
    try std.testing.expectEqual(FrameKind.request, parsed_req.kind);
    try std.testing.expectEqual(@as(?u64, 5), parsed_req.id);
}

test "permission picker uses docs optionIds, not invented allow" {
    var options: [max_permission_options]PermissionOption = [_]PermissionOption{.{}} ** max_permission_options;
    const count = scanPermissionOptions(docs_request_permission, options[0..]) orelse return error.MissingDocsOptions;
    try std.testing.expectEqual(@as(usize, 2), count);
    try std.testing.expectEqualStrings("allow-once", options[0].option_id);
    try std.testing.expectEqualStrings("reject-once", options[1].option_id);

    try std.testing.expectEqualStrings("allow-once", pickPermissionOptionId("auto", options[0..count]).?);
    try std.testing.expectEqualStrings("reject-once", pickPermissionOptionId("ask", options[0..count]).?);

    var buf: [256]u8 = undefined;
    const auto_reply = replyForAgentRequest(docs_request_permission, "code", &buf) orelse return error.MissingDocsReply;
    try std.testing.expect(std.mem.indexOf(u8, auto_reply, "\"optionId\":\"allow-once\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, auto_reply, "\"optionId\":\"allow\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, auto_reply, "allow_once") == null);
}

test "malformed request_permission does not hang; unknown requests reject" {
    var buf: [256]u8 = undefined;

    const no_options = "{\"jsonrpc\":\"2.0\",\"id\":9,\"method\":\"session/request_permission\",\"params\":{\"sessionId\":\"s\",\"toolCall\":{\"toolCallId\":\"c\"}}}";
    const cancelled = replyForAgentRequest(no_options, "auto", &buf) orelse return error.MissingCancel;
    try std.testing.expect(std.mem.indexOf(u8, cancelled, "\"id\":9") != null);
    try std.testing.expect(std.mem.indexOf(u8, cancelled, "\"outcome\":\"cancelled\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, cancelled, "optionId") == null);

    const empty_options = "{\"jsonrpc\":\"2.0\",\"id\":9,\"method\":\"session/request_permission\",\"params\":{\"options\":[]}}";
    const empty_reply = replyForAgentRequest(empty_options, "fullAccess", &buf) orelse return error.MissingEmptyCancel;
    try std.testing.expect(std.mem.indexOf(u8, empty_reply, "\"outcome\":\"cancelled\"") != null);

    const no_id = "{\"jsonrpc\":\"2.0\",\"method\":\"session/request_permission\",\"params\":{\"options\":[{\"optionId\":\"allow_once\",\"kind\":\"allow_once\"}]}}";
    try std.testing.expect(replyForAgentRequest(no_id, "auto", &buf) == null);

    const not_json = "not-json";
    try std.testing.expect(replyForAgentRequest(not_json, "auto", &buf) == null);

    const update = "{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"update\":{\"sessionUpdate\":\"agent_message_chunk\",\"content\":{\"type\":\"text\",\"text\":\"x\"}}}}";
    try std.testing.expect(replyForAgentRequest(update, "auto", &buf) == null);

    const unknown = "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"fs/read_text_file\",\"params\":{\"path\":\"/tmp/x\"}}";
    const rejected = replyForAgentRequest(unknown, "auto", &buf) orelse return error.MissingReject;
    try std.testing.expect(std.mem.indexOf(u8, rejected, "\"id\":4") != null);
    try std.testing.expect(std.mem.indexOf(u8, rejected, "\"code\":-32601") != null);
    try std.testing.expect(std.mem.indexOf(u8, rejected, "Method not found") != null);
}

test "sidecar access mode comes from env or set_mode; ask wins" {
    const argv_ask = [_][]const u8{ "env", "FX_PERMISSION_MODE=ask", "fx", "acp" };
    const argv_yolo = [_][]const u8{ "env", "FX_PERMISSION_MODE=yolo", "fx", "acp" };
    const argv_auto = [_][]const u8{ "env", "FX_PERMISSION_MODE=auto", "fx", "acp" };
    const stdin_ask = "{\"method\":\"session/set_mode\",\"params\":{\"modeId\":\"ask\"}}\n";
    const stdin_code = "{\"method\":\"session/set_mode\",\"params\":{\"modeId\":\"code\"}}\n";

    try std.testing.expectEqualStrings("ask", accessModeFromSidecarRun(&argv_ask, stdin_code));
    try std.testing.expectEqualStrings("ask", accessModeFromSidecarRun(&argv_yolo, stdin_ask));
    try std.testing.expectEqualStrings("yolo", accessModeFromSidecarRun(&argv_yolo, stdin_code));
    try std.testing.expectEqualStrings("auto", accessModeFromSidecarRun(&argv_auto, ""));
    try std.testing.expectEqualStrings("code", accessModeFromSidecarRun(&.{}, stdin_code));
    try std.testing.expectEqualStrings("ask", accessModeFromSidecarRun(&.{}, stdin_ask));
    try std.testing.expectEqualStrings("", accessModeFromSidecarRun(&.{}, ""));
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
