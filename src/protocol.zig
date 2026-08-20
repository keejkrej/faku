//! waku-protocol v3 stubs: types and JSON builders, not a live socket.
//!
//! Daemon transport is JSON text frames over WebSocket `ws://{addr}/v1`.
//! Native has no WebSocket client; daemon talk will be `fx.spawn` of a
//! sidecar or the daemon's stdio later.
//!
//! First-party provider (this port's differentiator; Waku does not ship
//! it): Vercel `fx` (https://fx.sh). Live first path is headless
//! `fx ask <prompt>` (see main.zig). ACP JSON-RPC builders live in
//! acp.zig; live `fx acp` is not spawned — Native stdin is one buffer
//! at spawn time, and ACP needs ongoing writes. Probe `~/.local/bin/fx`
//! then PATH. Missing binary keeps the demo timer.
//!
//! Catalog is `loadTaskState`. There is no `listSessions` / `createSession`
//! RPC. A new session is a client-built AgentSession persisted with
//! `saveTaskState`. After `turnFinished`, dequeue local `queuedMessages`
//! and send the next `prompt`.

const std = @import("std");

pub const PROTOCOL_VERSION: u32 = 3;
pub const REQUEST_TIMEOUT_S: u32 = 120;
pub const MAX_WIRE_MESSAGE_BYTES: usize = 48 * 1024 * 1024;

pub const DAEMON_TOKEN_ENV = "WAKU_DAEMON_TOKEN";
pub const DAEMON_ADDRESS_ENV = "WAKU_DAEMON_ADDRESS";
pub const APP_EXECUTABLE_ENV = "WAKU_APP_EXECUTABLE";

/// All-zero UUID: a requestId of this value is a notify (no response).
pub const NIL_UUID = "00000000-0000-0000-0000-000000000000";

/// Wire id and binary name for the first-party harness.
pub const FX_PROVIDER_ID = "fx";
pub const FX_BINARY = "fx";
/// ACP stdio surface — the right embed path (same family as cursor-agent / grok).
pub const FX_TRANSPORT = "acp";
pub const FX_ACP_ARGV = [_][]const u8{ "fx", "acp" };
pub const FX_ASK_ARGV_HEAD = [_][]const u8{ "fx", "ask" };
/// Install: `curl -fsSL https://fx.sh/setup.sh | bash` → ~/.local/bin/fx
pub const FX_PROBE_PATHS = [_][]const u8{ "~/.local/bin/fx", "fx" };

/// First line of daemon stdout after spawn, before the WebSocket is up.
pub const DaemonReady = struct {
    address: []const u8,
    protocol_version: u32,
    pid: u32,
};

/// Replay cursor carried in Client Hello `resumeFrom`.
pub const ReplayCursor = struct {
    session_id: []const u8,
    runtime_id: []const u8,
    epoch: []const u8,
    sequence: u64,
};

pub const ProviderId = enum {
    fx,
    claude,
    codex,
    amp,
    grok,
    opencode,
    cursor,
    pi,

    pub const default = ProviderId.fx;

    pub fn wireName(id: ProviderId) []const u8 {
        return switch (id) {
            .fx => "fx",
            .claude => "claude",
            .codex => "codex",
            .amp => "amp",
            .grok => "grok",
            .opencode => "opencode",
            .cursor => "cursor",
            .pi => "pi",
        };
    }

    pub fn defaultBinary(id: ProviderId) []const u8 {
        return switch (id) {
            .fx => FX_BINARY,
            .claude => "claude",
            .codex => "codex",
            .amp => "amp",
            .grok => "grok",
            .opencode => "opencode",
            .cursor => "cursor-agent",
            .pi => "pi",
        };
    }

    pub fn fromWire(name: []const u8) ?ProviderId {
        inline for (std.meta.tags(ProviderId)) |id| {
            if (std.mem.eql(u8, id.wireName(), name)) return id;
        }
        return null;
    }
};

/// Start options on `command: { type: "start", options }`.
/// `mode`: ask | autoAcceptEdits | auto | fullAccess
/// `interaction_mode`: build | plan
pub const StartOptions = struct {
    provider: []const u8 = FX_PROVIDER_ID,
    binary: []const u8 = FX_BINARY,
    cwd: []const u8 = ".",
    mode: []const u8 = "ask",
    interaction_mode: []const u8 = "build",
    model: ?[]const u8 = null,
    computer_use_enabled: bool = false,
};

pub fn defaultStartOptions() StartOptions {
    return .{};
}

/// First-cut commands. Full daemon surface is larger; this port only
/// names the ones a desktop needs to boot a transcript.
pub const CommandTag = enum {
    load_task_state,
    hydrate_session,
    save_task_state,
    attach_session,
    start,
    prompt,
    steer,
    cancel,
    close_session,

    pub fn wireName(tag: CommandTag) []const u8 {
        return switch (tag) {
            .load_task_state => "loadTaskState",
            .hydrate_session => "hydrateSession",
            .save_task_state => "saveTaskState",
            .attach_session => "attachSession",
            .start => "start",
            .prompt => "prompt",
            .steer => "steer",
            .cancel => "cancel",
            .close_session => "closeSession",
        };
    }
};

/// `event.kind` values the demo will eventually render.
pub const EventKind = enum {
    connected,
    turn_started,
    text_delta,
    reasoning_delta,
    rich_activity,
    permission,
    steer_accepted,
    steer_rejected,
    turn_finished,
    @"error",
    process_exited,

    pub fn wireName(kind: EventKind) []const u8 {
        return switch (kind) {
            .connected => "connected",
            .turn_started => "turnStarted",
            .text_delta => "textDelta",
            .reasoning_delta => "reasoningDelta",
            .rich_activity => "richActivity",
            .permission => "permission",
            .steer_accepted => "steerAccepted",
            .steer_rejected => "steerRejected",
            .turn_finished => "turnFinished",
            .@"error" => "error",
            .process_exited => "processExited",
        };
    }
};

pub const ClientFrame = enum { hello, request, shutdown };
pub const ServerFrame = enum { hello, rejected, response, event, task_state_changed, shutting_down };

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

fn writeBool(cur: *Cursor, value: bool) WriteError!void {
    try cur.write(if (value) "true" else "false");
}

/// Client Hello:
/// `{ type, protocolVersion, token, clientId, resumeFrom: [{ sessionId, runtimeId, epoch, sequence }] }`
pub fn writeClientHello(
    buf: []u8,
    token: []const u8,
    client_id: []const u8,
    resume_from: []const ReplayCursor,
) WriteError![]const u8 {
    var cur = Cursor{ .buf = buf };
    try cur.write("{\"type\":\"hello\",\"protocolVersion\":");
    try writeUint(&cur, PROTOCOL_VERSION);
    try cur.write(",\"token\":");
    try writeJsonString(&cur, token);
    try cur.write(",\"clientId\":");
    try writeJsonString(&cur, client_id);
    try cur.write(",\"resumeFrom\":[");
    for (resume_from, 0..) |cursor, i| {
        if (i != 0) try cur.write(",");
        try cur.write("{\"sessionId\":");
        try writeJsonString(&cur, cursor.session_id);
        try cur.write(",\"runtimeId\":");
        try writeJsonString(&cur, cursor.runtime_id);
        try cur.write(",\"epoch\":");
        try writeJsonString(&cur, cursor.epoch);
        try cur.write(",\"sequence\":");
        try writeUint(&cur, cursor.sequence);
        try cur.write("}");
    }
    try cur.write("]}");
    return cur.slice();
}

/// Compatibility alias used by tests.
pub fn writeHello(buf: []u8, args: struct { token: []const u8, client_id: []const u8 }) WriteError![]const u8 {
    return writeClientHello(buf, args.token, args.client_id, &.{});
}

/// Request frame wrapping `command: { type: "prompt", prompt }`.
/// Nil UUID requestId = notify (no response). Timeout 120s.
pub fn writePrompt(
    buf: []u8,
    request_id: []const u8,
    session_id: []const u8,
    runtime_id: []const u8,
    prompt: []const u8,
) WriteError![]const u8 {
    var cur = Cursor{ .buf = buf };
    try cur.write("{\"type\":\"request\",\"requestId\":");
    try writeJsonString(&cur, request_id);
    try cur.write(",\"sessionId\":");
    try writeJsonString(&cur, session_id);
    try cur.write(",\"runtimeId\":");
    try writeJsonString(&cur, runtime_id);
    try cur.write(",\"command\":{\"type\":\"prompt\",\"prompt\":");
    try writeJsonString(&cur, prompt);
    try cur.write("}}");
    return cur.slice();
}

/// Start command. Defaults to first-party `fx` / binary `fx`.
pub fn writeStart(
    buf: []u8,
    request_id: []const u8,
    session_id: []const u8,
    runtime_id: []const u8,
    options: StartOptions,
) WriteError![]const u8 {
    var cur = Cursor{ .buf = buf };
    try cur.write("{\"type\":\"request\",\"requestId\":");
    try writeJsonString(&cur, request_id);
    try cur.write(",\"sessionId\":");
    try writeJsonString(&cur, session_id);
    try cur.write(",\"runtimeId\":");
    try writeJsonString(&cur, runtime_id);
    try cur.write(",\"command\":{\"type\":\"start\",\"options\":{\"provider\":");
    try writeJsonString(&cur, options.provider);
    try cur.write(",\"binary\":");
    try writeJsonString(&cur, options.binary);
    try cur.write(",\"cwd\":");
    try writeJsonString(&cur, options.cwd);
    try cur.write(",\"mode\":");
    try writeJsonString(&cur, options.mode);
    try cur.write(",\"interactionMode\":");
    try writeJsonString(&cur, options.interaction_mode);
    if (options.model) |model| {
        try cur.write(",\"model\":");
        try writeJsonString(&cur, model);
    }
    try cur.write(",\"computerUseEnabled\":");
    try writeBool(&cur, options.computer_use_enabled);
    try cur.write("}}}");
    return cur.slice();
}

/// Bare first-cut command (attachSession, cancel, loadTaskState, closeSession, …).
pub fn writeBareCommand(
    buf: []u8,
    request_id: []const u8,
    session_id: []const u8,
    runtime_id: []const u8,
    tag: CommandTag,
) WriteError![]const u8 {
    var cur = Cursor{ .buf = buf };
    try cur.write("{\"type\":\"request\",\"requestId\":");
    try writeJsonString(&cur, request_id);
    try cur.write(",\"sessionId\":");
    try writeJsonString(&cur, session_id);
    try cur.write(",\"runtimeId\":");
    try writeJsonString(&cur, runtime_id);
    try cur.write(",\"command\":{\"type\":");
    try writeJsonString(&cur, tag.wireName());
    try cur.write("}}");
    return cur.slice();
}

test "client hello is camelCase protocol v3" {
    var buf: [256]u8 = undefined;
    const json = try writeClientHello(&buf, "secret", "00000000-0000-0000-0000-000000000002", &.{});
    try std.testing.expect(std.mem.indexOf(u8, json, "\"type\":\"hello\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"protocolVersion\":3") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"token\":\"secret\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "protocol_version") == null);
    try std.testing.expectEqual(@as(u32, 3), PROTOCOL_VERSION);
}

test "prompt request wraps a camelCase command" {
    var buf: [256]u8 = undefined;
    const json = try writePrompt(
        &buf,
        NIL_UUID,
        "00000000-0000-0000-0000-000000000001",
        "00000000-0000-0000-0000-000000000003",
        "trace the listener",
    );
    try std.testing.expect(std.mem.indexOf(u8, json, "\"type\":\"request\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"command\":{\"type\":\"prompt\",\"prompt\":\"trace the listener\"}") != null);
}

test "start defaults to first-party fx over acp" {
    var buf: [512]u8 = undefined;
    const json = try writeStart(&buf, NIL_UUID, NIL_UUID, NIL_UUID, defaultStartOptions());
    try std.testing.expect(std.mem.indexOf(u8, json, "\"provider\":\"fx\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"binary\":\"fx\"") != null);
    try std.testing.expectEqualStrings("fx", ProviderId.default.wireName());
    try std.testing.expectEqual(ProviderId.fx, ProviderId.fromWire("fx").?);
    try std.testing.expectEqual(ProviderId.claude, ProviderId.fromWire("claude").?);
    try std.testing.expectEqualStrings("fx", FX_ACP_ARGV[0]);
    try std.testing.expectEqualStrings("acp", FX_ACP_ARGV[1]);
    try std.testing.expectEqualStrings("acp", FX_TRANSPORT);
}

test "first-cut command tags stay camelCase on the wire" {
    try std.testing.expectEqualStrings("loadTaskState", CommandTag.load_task_state.wireName());
    try std.testing.expectEqualStrings("hydrateSession", CommandTag.hydrate_session.wireName());
    try std.testing.expectEqualStrings("turnFinished", EventKind.turn_finished.wireName());
    try std.testing.expectEqualStrings("textDelta", EventKind.text_delta.wireName());
}
