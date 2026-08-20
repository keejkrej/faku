//! Agent Client Protocol (ACP) JSON-RPC 2.0 helpers — stub only.
//!
//! These builders/parsers produce and read newline-delimited JSON-RPC
//! frames for the methods `fx acp` actually implements (see
//! https://fx.sh/docs/using-fx/acp):
//!
//!   initialize
//!   session/new
//!   session/prompt
//!   session/cancel
//!
//! Live `fx acp` is **not** wired. Native `fx.spawn` / `Cmd.spawn`
//! accepts stdin only at spawn time (one buffer, then stdin closes).
//! There is no documented write-to-running-child effect, and ACP
//! JSON-RPC needs ongoing stdin writes after `initialize`. Do not
//! treat this module as a working ACP loop. The next cut waits on a
//! stdin-write effect before spawning `&.{ fx_path, "acp" }`.
//!
//! fx reports ACP protocol version 1. Frames are one JSON object per
//! line; this file never execs a binary.

const std = @import("std");

/// ACP version fx advertises (`initialize` response `protocolVersion`).
pub const PROTOCOL_VERSION: u32 = 1;
pub const JSONRPC_VERSION = "2.0";

pub const METHOD_INITIALIZE = "initialize";
pub const METHOD_SESSION_NEW = "session/new";
pub const METHOD_SESSION_PROMPT = "session/prompt";
pub const METHOD_SESSION_CANCEL = "session/cancel";

pub const Method = enum {
    initialize,
    session_new,
    session_prompt,
    session_cancel,
    unknown,

    pub fn wireName(method: Method) []const u8 {
        return switch (method) {
            .initialize => METHOD_INITIALIZE,
            .session_new => METHOD_SESSION_NEW,
            .session_prompt => METHOD_SESSION_PROMPT,
            .session_cancel => METHOD_SESSION_CANCEL,
            .unknown => "",
        };
    }

    pub fn fromWire(name: []const u8) Method {
        if (std.mem.eql(u8, name, METHOD_INITIALIZE)) return .initialize;
        if (std.mem.eql(u8, name, METHOD_SESSION_NEW)) return .session_new;
        if (std.mem.eql(u8, name, METHOD_SESSION_PROMPT)) return .session_prompt;
        if (std.mem.eql(u8, name, METHOD_SESSION_CANCEL)) return .session_cancel;
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
    has_error: bool = false,
    has_result: bool = false,
};

const WriteError = error{NoSpaceLeft};

const Cursor = struct {
    buf: []u8,
    pos: usize = 0,

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
/// because this stub is not a live client.
pub fn writeSessionNew(buf: []u8, id: u64, cwd: []const u8) WriteError![]const u8 {
    var cur = Cursor{ .buf = buf };
    try writeRequestHead(&cur, id, METHOD_SESSION_NEW);
    try cur.write("{\"cwd\":");
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

/// `session/cancel` notification (no `id`; no response expected).
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
    var j = skipWs(text, i + 1 + key.len + 1);
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
/// This is a field scanner, not a full JSON parser — good enough to
/// classify the four methods above and pull `id` / `sessionId`.
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
}

test "ACP parser classifies result and error frames" {
    const ok = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"protocolVersion\":1}}";
    const parsed_ok = parseLine(ok);
    try std.testing.expectEqual(FrameKind.response, parsed_ok.kind);
    try std.testing.expect(parsed_ok.has_result);

    const err = "{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":-32600,\"message\":\"invalid\"}}";
    const parsed_err = parseLine(err);
    try std.testing.expectEqual(FrameKind.error_response, parsed_err.kind);
    try std.testing.expect(parsed_err.has_error);
}
