//! waku-protocol v4: client JSON builders plus a server-frame parser.
//!
//! Daemon transport is JSON text frames over WebSocket `ws://{addr}/v1`.
//! Native has no first-party WebSocket effect. Live daemon talk is a
//! one-shot sidecar (`daemon_proxy.zig`) spawned with `fx.spawn`; the
//! update loop never holds a bidirectional socket. Missing
//! `WAKU_DAEMON_ADDRESS` keeps `fx ask` / the demo timer.
//!
//! First-party provider (this port's differentiator; Waku does not ship
//! it): Vercel `fx` (https://fx.sh). Live first path is one-shot
//! `fx acp` (see main.zig / acp.zig). Probed ACP stdio providers
//! (cursor / opencode `acp`, grok `agent stdio`) reuse that sidecar.
//! Native stdin is one buffer at spawn time; this is not a long-lived
//! ACP loop. `fx ask --image` stays the fx image path (fx ACP rejects
//! image blocks). Probed ACP stdio (cursor / opencode / grok) may
//! attach official ACP v1 image content blocks on `session/prompt`.
//! Probe
//! `~/.local/bin/fx` then PATH. Missing binary keeps the demo timer.
//!
//! Catalog is `loadTaskState`. There is no `listSessions` / `createSession`
//! RPC. A new session is a client-built AgentSession persisted with
//! `saveTaskState`. After `turnFinished`, dequeue local `queuedMessages`
//! and send the next `prompt`.
//!
//! `loadTaskState` is a bare command. Verified against egoist/waku
//! `crates/waku-protocol/src/protocol.rs` (`ResponsePayload::TaskState`)
//! and `apps/web/src/lib/daemon-api.ts` (`expectResponse(..., 'taskState')`):
//! a non-nil `requestId` is required (nil is a notify and the daemon sends
//! no response). An ok outcome carries
//! `{ type: "taskState", projects, sessions, defaultCwd, projectlessRoot }`.
//! AgentSession / Project keys stay snake_case (`id`, `title`, `provider`,
//! `project_id`, `path`). `has_started` and `project_path` are Faku extras
//! on the session object (same extras `saveTaskState` sends); they are
//! parsed when present. Local `sessions.json` stays canonical; a daemon
//! load is only a first-run fill when that file is missing.
//!
//! `saveTaskState` is not a bare command. Verified against egoist/waku
//! `crates/waku-protocol/src/protocol.rs` and `persistSession` in
//! `apps/web/src/lib/daemon-api.ts`: `{ type, projects, liveSessionIds,
//! sessions }`. Local `sessions.json` stays canonical; this payload is
//! a best-effort daemon mirror of one started-session skeleton.
//!
//! `hydrateSession` is not a bare command. Verified against egoist/waku
//! `Command::HydrateSession { session_id }` (camelCase `sessionId` on the
//! command), `apps/web/src/lib/daemon-api.ts` (`request({ type:
//! 'hydrateSession', sessionId })` + `expectResponse(..., 'session')`),
//! and `crates/waku-core/src/server.rs` (request-frame `sessionId` may be
//! nil; the target lives on the command). A non-nil `requestId` is
//! required. An ok outcome carries `{ type: "session", session }` where
//! `session` is an AgentSession or null. Transcript text is
//! `session.messages[]` (`role`, `content`); `session.turns[]` is
//! metadata (no body). `queued_messages[].content` is the follow-up
//! queue. AgentSession keys stay snake_case. Local turns win; a daemon
//! hydrate runs only when that session's local transcript is empty.
//!
//! `closeSession` is a bare command. Verified against egoist/waku
//! `Command::CloseSession` (unit variant, no payload field),
//! `apps/web/src/lib/runtime-context.tsx`
//! (`request({ type: 'closeSession' }, sessionId, runtimeId)`), and
//! `crates/waku-core/src/daemon.rs` (request-frame `sessionId` /
//! `runtimeId`; outcome `ack`). It is not `removeSession` and does not
//! take `sessionId` on the command. Local `removeSession` stays the
//! catalog delete; `closeSession` is a best-effort sidecar after that
//! persist. No `attachSession` first.
//!
//! `cancel` is a bare command. Verified against egoist/waku
//! `Command::Cancel` (unit variant, no payload field),
//! `apps/web/src/lib/runtime-context.tsx`
//! (`request({ type: 'cancel' }, sessionId, runtime.runtimeId)`),
//! `crates/waku-protocol/src/protocol.rs` (request-frame `sessionId` /
//! `runtimeId`), and `crates/waku-core/src/daemon.rs` (`Command::Cancel`
//! → `driver.cancel()` after lookup by those request-frame ids). It is
//! not `session/cancel` and does not take a prompt. Native cannot write
//! into the running prompt sidecar; Stop / Esc `fx.cancel`s that spawn
//! and, when a daemon address is set and the live turn was a daemon
//! spawn, one-shots hello + `cancel` on a distinct key. Sidecar
//! failure must not resurrect the turn. No `attachSession` first.
//!
//! `steer` is `Command::Steer { prompt }` (same payload field name as
//! `Prompt`). Verified against egoist/waku
//! `crates/waku-protocol/src/protocol.rs` (`Steer { prompt: String }`,
//! `rename_all_fields = "camelCase"`), `src/app/runtime.rs`
//! (`session_can_steer` requires a live runtime with
//! `supports_steer()`; otherwise the follow-up is queued), and
//! `apps/web/src/lib/runtime-context.tsx`
//! (`request({ type: 'steer', prompt }, sessionId, runtime.runtimeId)`).
//! Request-frame `sessionId` / `runtimeId` name the live turn. Events
//! are `steerAccepted` / `steerRejected`. Native cannot write into the
//! running prompt sidecar; a live daemon turn one-shots hello + `steer`
//! on a distinct key. Waku does not steer when attach `supportsSteer`
//! is false or unknown — those follow-ups queue. No `attachSession`
//! first.
//!
//! `goal` is `Command::Goal { operation }` (`GoalOperation` tagged
//! `kind`). Verified against egoist/waku `crates/waku-protocol/src/protocol.rs`
//! (`Goal { operation: GoalOperation }`, command enum camelCase) and
//! `crates/waku-protocol/src/model.rs` (`#[serde(tag = "kind",
//! rename_all = "camelCase", rename_all_fields = "camelCase")]`):
//! `{ "kind": "refresh" }`, `{ "kind": "set", "objective": string|null,
//! "status": ThreadGoalStatus|null, "replace": bool }`, `{ "kind": "clear" }`.
//! `ThreadGoalStatus` is Codex camelCase: `active` | `paused` | `blocked`
//! | `usageLimited` | `budgetLimited` | `complete`. Outcome is an async
//! `goalUpdated` driver event (payload is `ThreadGoal` or JSON null when
//! cleared), or `error`. Documented `ThreadGoal` fields only: `objective`,
//! `status`, optional nullable `tokenBudget`, `tokensUsed`,
//! `timeUsedSeconds` (camelCase on the wire). This port does not invent
//! other goal fields. A one-shot sidecar may only see stdout during the
//! short spawn — still emit the command; parse `goalUpdated` if it
//! arrives, otherwise keep last-known local objective/status/usage.
//! Goal is a Waku-daemon Command for live Codex provider runtimes.
//! fx ask / fx acp / demo do not get Goal.
//!
//! `attachSession` is a bare command. Verified against egoist/waku
//! `Command::AttachSession` (unit variant, no payload field),
//! `src/app/runtime.rs` (`request(session_id, Uuid::nil(), AttachSession)`),
//! `crates/waku-core/src/daemon.rs` (lookup by request-frame `sessionId`;
//! observes the provider process), and `ResponsePayload::SessionRuntime`
//! `{ runtime_id: Option<Uuid>, supports_steer }`. An ok outcome carries
//! `{ type: "sessionRuntime", runtimeId, supportsSteer }`. `runtimeId`
//! may be JSON null when no runtime is live. A non-nil `requestId` is
//! required (nil is a notify and the daemon sends no response). Prompt
//! and start target that runtime id when one exists; this port cannot
//! wait for attach before the one-shot prompt, so a later send reuses
//! a persisted id.
//!
//! `start` is `Command::Start { options }` (`WireDriverStartOptions`).
//! Verified against egoist/waku `apps/web/src/lib/runtime-context.tsx`
//! `sendPrompt`: attach first when no local runtime entry; if attach
//! still leaves no runtime, `client.request({ type: 'start', options })`
//! then `{ type: 'prompt' }`. Native `src/app/runtime.rs` attach is
//! observe-only (`Command::AttachSession`); a missing runtime starts
//! the provider through `driver::start_remote` / daemon `Command::Start`.
//! `crates/waku-core/src/daemon.rs` stores the request-frame
//! `runtimeId` with the new driver and replies `{ type: "started",
//! supportsSteer }`. Mapped options this port already stores:
//! `provider`, `binary` (provider default), `cwd` (`project_path` or
//! `"."`), `mode` (`access_mode`), `interactionMode`, `model` when
//! non-empty, `reasoningEffort` when non-empty, `computerUseEnabled`
//! false. Other Waku start fields (`serviceTier`, `contextWindow`,
//! `agentPreset`, `providerCursor`) are not stored here and are not
//! invented. The
//! one-shot first send (empty persisted runtime id) is hello +
//! attachSession + start + prompt. A later send with a stored runtime
//! id stays hello + attachSession + prompt.

const std = @import("std");

pub const PROTOCOL_VERSION: u32 = 4;
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
/// Bare `acp` after the binary — fx, cursor-agent, opencode.
pub const BARE_ACP_TRANSPORT = [_][]const u8{FX_TRANSPORT};
/// Official Grok ACP stdio. Not `grok acp`. Permission mode rides
/// `session/set_mode` / `FX_PERMISSION_MODE` like the other ACP
/// ids; this cut does not pass `--always-approve`.
pub const GROK_ACP_TRANSPORT = [_][]const u8{ "agent", "stdio" };
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

    /// True when this id speaks ACP stdio with a bare `acp` subcommand
    /// (`cursor-agent acp`, official `opencode acp`). fx stays on the
    /// first-party branch. Not Claude print-mode stream-json (that is a
    /// separate one-shot `-p --output-format stream-json` spawn, not
    /// ACP). Not Codex
    /// exec (that is a separate one-shot `codex exec {prompt}` spawn,
    /// not ACP). Not Amp execute-mode (that is a separate one-shot
    /// `amp -x {prompt}` spawn, documented `@{path}` in the `-x`
    /// prompt when attached, not ACP). Not Pi json-mode (that is
    /// a separate one-shot `pi --mode json {prompt}` spawn, documented
    /// `@{path}` after json when attached, not ACP). Not
    /// Grok `agent stdio`. Kimi is not in this enum. Easy to extend
    /// later.
    pub fn speaksBareAcp(id: ProviderId) bool {
        return switch (id) {
            .cursor, .opencode => true,
            else => false,
        };
    }

    /// True when Faku can spawn one-shot ACP stdio for this id after
    /// the daemon/fx branches. Bare `acp` (cursor, opencode) plus Grok
    /// `agent stdio`. fx stays on the first-party branch.
    pub fn speaksAcpStdio(id: ProviderId) bool {
        return id.speaksBareAcp() or id == .grok;
    }

    /// Transport argv after the binary. Bare-acp ids and fx get
    /// `acp`; grok gets `agent stdio`. Empty for ids that do not
    /// speak ACP stdio this cut.
    pub fn acpTransportArgv(id: ProviderId) []const []const u8 {
        return switch (id) {
            .fx, .cursor, .opencode => &BARE_ACP_TRANSPORT,
            .grok => &GROK_ACP_TRANSPORT,
            else => &.{},
        };
    }

    pub fn fromWire(name: []const u8) ?ProviderId {
        inline for (std.meta.tags(ProviderId)) |id| {
            if (std.mem.eql(u8, id.wireName(), name)) return id;
        }
        return null;
    }
};

/// Tag count for `ProviderId`. Model probe slots are this long;
/// index is `@intFromEnum` (slot 0 is fx and unused by non-fx probes).
pub const provider_id_count = std.meta.tags(ProviderId).len;

/// Start options on `command: { type: "start", options }`.
/// `mode`: ask | autoAcceptEdits | auto | fullAccess
/// `interaction_mode`: build | plan
/// `reasoning_effort`: fx documented effort, omitted when empty
pub const StartOptions = struct {
    provider: []const u8 = FX_PROVIDER_ID,
    binary: []const u8 = FX_BINARY,
    cwd: []const u8 = ".",
    mode: []const u8 = "ask",
    interaction_mode: []const u8 = "build",
    model: ?[]const u8 = null,
    reasoning_effort: ?[]const u8 = null,
    computer_use_enabled: bool = false,
};

pub fn defaultStartOptions() StartOptions {
    return .{};
}

/// First-cut commands. Full daemon surface is larger; this port only
/// names the ones a desktop needs to boot a transcript. There is no
/// `fork` command on this wire — session fork is a local catalog clone.
/// `goal` is the Codex `/goal` first cut (set/clear/refresh over the
/// daemon sidecar). It is not an fx / ACP method.
pub const CommandTag = enum {
    load_task_state,
    hydrate_session,
    save_task_state,
    attach_session,
    start,
    prompt,
    steer,
    cancel,
    goal,
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
            .goal => "goal",
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
    goal_updated,
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
            .goal_updated => "goalUpdated",
            .turn_finished => "turnFinished",
            .@"error" => "error",
            .process_exited => "processExited",
        };
    }

    pub fn fromWire(name: []const u8) ?EventKind {
        inline for (std.meta.tags(EventKind)) |kind| {
            if (std.mem.eql(u8, kind.wireName(), name)) return kind;
        }
        return null;
    }
};

pub const ClientFrame = enum { hello, request, shutdown };
pub const ServerFrame = enum { hello, rejected, response, event, task_state_changed, shutting_down, invalid };

/// Parsed server JSON. Slices alias `line` (or the leaky JSON arena).
pub const ParsedServer = struct {
    frame: ServerFrame = .invalid,
    protocol_version: u32 = 0,
    daemon_version: []const u8 = "",
    message: []const u8 = "",
    request_id: []const u8 = "",
    response_ok: bool = false,
    session_id: []const u8 = "",
    runtime_id: []const u8 = "",
    event_kind: ?EventKind = null,
    event_kind_name: []const u8 = "",
    /// `textDelta` payload (JSON string on the wire).
    text_delta: []const u8 = "",
    /// `turnFinished` payload. Missing `success` defaults to true.
    turn_success: bool = true,
    /// `outcome.payload.type` on a response (`taskState`, `sessionRuntime`, `ack`, …).
    payload_type: []const u8 = "",
    /// `sessionRuntime.supportsSteer` when the payload includes it.
    supports_steer: bool = false,
    /// `goalUpdated` payload `objective` when present.
    goal_objective: []const u8 = "",
    /// `goalUpdated` payload `status` when present (Codex camelCase).
    goal_status: []const u8 = "",
    /// `goalUpdated` payload `tokenBudget` when present and numeric.
    goal_token_budget: u64 = 0,
    /// `goalUpdated` payload `tokensUsed` when present and numeric.
    goal_tokens_used: u64 = 0,
    /// `goalUpdated` payload `timeUsedSeconds` when present and numeric.
    goal_time_used_seconds: u64 = 0,
    /// True when `goalUpdated` payload is JSON null (provider cleared).
    goal_cleared: bool = false,
    /// True when the `goalUpdated` object included `objective`.
    goal_has_objective: bool = false,
    /// True when the `goalUpdated` object included `status`.
    goal_has_status: bool = false,
    /// True when the `goalUpdated` object included `tokenBudget`.
    goal_has_token_budget: bool = false,
    /// True when `tokenBudget` was JSON null (no budget).
    goal_token_budget_null: bool = false,
    /// True when the `goalUpdated` object included numeric `tokensUsed`.
    goal_has_tokens_used: bool = false,
    /// True when the `goalUpdated` object included numeric `timeUsedSeconds`.
    goal_has_time_used_seconds: bool = false,
};

/// Codex / Waku `ThreadGoalStatus`. Wire names are camelCase.
pub const ThreadGoalStatus = enum {
    active,
    paused,
    blocked,
    usage_limited,
    budget_limited,
    complete,

    pub fn wireName(status: ThreadGoalStatus) []const u8 {
        return switch (status) {
            .active => "active",
            .paused => "paused",
            .blocked => "blocked",
            .usage_limited => "usageLimited",
            .budget_limited => "budgetLimited",
            .complete => "complete",
        };
    }

    pub fn fromWire(name: []const u8) ?ThreadGoalStatus {
        inline for (std.meta.tags(ThreadGoalStatus)) |status| {
            if (std.mem.eql(u8, status.wireName(), name)) return status;
        }
        return null;
    }
};

/// `GoalOperation` tagged `kind` (Waku serde camelCase).
pub const GoalKind = enum { refresh, set, clear };

pub const GoalSet = struct {
    objective: ?[]const u8 = null,
    status: ?[]const u8 = null,
    replace: bool = false,
};

pub const GoalOperation = union(GoalKind) {
    refresh,
    set: GoalSet,
    clear,
};

/// Runtime id taken from a verified `sessionRuntime` response payload.
/// Slices alias the JSON arena used to parse the line.
pub const ParsedSessionRuntime = struct {
    ok: bool = false,
    runtime_id: []const u8 = "",
    supports_steer: bool = false,
};

pub const max_task_state_sessions: usize = 16;
pub const max_hydrate_messages: usize = 128;
pub const max_hydrate_queued: usize = 16;

/// Session skeletons taken from a verified `taskState` response payload.
/// Slices alias the JSON arena used to parse the line.
pub const ParsedTaskState = struct {
    sessions: [max_task_state_sessions]TaskStateSkeleton = [_]TaskStateSkeleton{.{
        .session_id = "",
        .title = "",
        .provider = "",
    }} ** max_task_state_sessions,
    session_count: usize = 0,
};

/// One `messages[]` row from a verified `session` hydrate payload.
pub const HydratedMessage = struct {
    role: []const u8 = "",
    content: []const u8 = "",
};

/// One `queued_messages[]` row. Waku field is `content`, not `text`.
pub const HydratedQueued = struct {
    content: []const u8 = "",
};

/// Transcript taken from a verified `session` response payload.
/// Slices alias the JSON arena used to parse the line.
pub const ParsedHydrate = struct {
    ok: bool = false,
    messages: [max_hydrate_messages]HydratedMessage = [_]HydratedMessage{.{}} ** max_hydrate_messages,
    message_count: usize = 0,
    queued: [max_hydrate_queued]HydratedQueued = [_]HydratedQueued{.{}} ** max_hydrate_queued,
    queued_count: usize = 0,
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

/// Request frame wrapping verified `command: { type: "steer", prompt }`.
/// Same request-frame `sessionId` / `runtimeId` as prompt / cancel.
/// Nil UUID requestId = notify (no response). Timeout 120s.
pub fn writeSteer(
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
    try cur.write(",\"command\":{\"type\":\"steer\",\"prompt\":");
    try writeJsonString(&cur, prompt);
    try cur.write("}}");
    return cur.slice();
}

/// Request frame wrapping verified `command: { type: "goal", operation }`.
/// Same request-frame `sessionId` / `runtimeId` as prompt / steer / cancel.
/// `operation` is `GoalOperation` tagged `kind`. Nil UUID requestId =
/// notify (no response). Timeout 120s.
pub fn writeGoal(
    buf: []u8,
    request_id: []const u8,
    session_id: []const u8,
    runtime_id: []const u8,
    operation: GoalOperation,
) WriteError![]const u8 {
    var cur = Cursor{ .buf = buf };
    try cur.write("{\"type\":\"request\",\"requestId\":");
    try writeJsonString(&cur, request_id);
    try cur.write(",\"sessionId\":");
    try writeJsonString(&cur, session_id);
    try cur.write(",\"runtimeId\":");
    try writeJsonString(&cur, runtime_id);
    try cur.write(",\"command\":{\"type\":\"goal\",\"operation\":");
    try writeGoalOperation(&cur, operation);
    try cur.write("}}");
    return cur.slice();
}

fn writeGoalOperation(cur: *Cursor, operation: GoalOperation) WriteError!void {
    switch (operation) {
        .refresh => try cur.write("{\"kind\":\"refresh\"}"),
        .clear => try cur.write("{\"kind\":\"clear\"}"),
        .set => |args| {
            try cur.write("{\"kind\":\"set\",\"objective\":");
            if (args.objective) |objective| {
                try writeJsonString(cur, objective);
            } else {
                try cur.write("null");
            }
            try cur.write(",\"status\":");
            if (args.status) |status| {
                try writeJsonString(cur, status);
            } else {
                try cur.write("null");
            }
            try cur.write(",\"replace\":");
            try writeBool(cur, args.replace);
            try cur.write("}");
        },
    }
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
    if (options.reasoning_effort) |effort| {
        if (effort.len > 0) {
            try cur.write(",\"reasoningEffort\":");
            try writeJsonString(&cur, effort);
        }
    }
    try cur.write(",\"computerUseEnabled\":");
    try writeBool(&cur, options.computer_use_enabled);
    try cur.write("}}}");
    return cur.slice();
}

/// One started-session skeleton for `saveTaskState`.
///
/// Verified Waku command fields are `projects`, `liveSessionIds`, and
/// `sessions`. AgentSession/Project keep snake_case keys (`project_id`,
/// `runtime_mode`, `created_at`). `has_started` and `project_path` are
/// Faku extras on the session object so the daemon can remember the
/// same skeleton the local catalog stores; Waku serde ignores unknown
/// fields. `has_started` is also implied: this builder is only emitted
/// after a started-session persist.
pub const TaskStateSkeleton = struct {
    session_id: []const u8,
    title: []const u8,
    provider: []const u8,
    project_path: []const u8 = "",
    has_started: bool = true,
    runtime_mode: []const u8 = "fullAccess",
};

fn projectName(path: []const u8) []const u8 {
    if (path.len == 0) return "No project";
    var i = path.len;
    while (i > 0) {
        i -= 1;
        if (path[i] == '/' or path[i] == '\\') {
            if (i + 1 < path.len) return path[i + 1 ..];
            return "Project";
        }
    }
    return path;
}

/// Request wrapping verified `saveTaskState` `{ projects, liveSessionIds, sessions }`.
/// Enough for the daemon to remember one session skeleton (id, title,
/// provider, project_path, has_started). Not a replacement for the local store.
pub fn writeSaveTaskState(
    buf: []u8,
    request_id: []const u8,
    runtime_id: []const u8,
    skeleton: TaskStateSkeleton,
) WriteError![]const u8 {
    var cur = Cursor{ .buf = buf };
    try cur.write("{\"type\":\"request\",\"requestId\":");
    try writeJsonString(&cur, request_id);
    try cur.write(",\"sessionId\":");
    try writeJsonString(&cur, skeleton.session_id);
    try cur.write(",\"runtimeId\":");
    try writeJsonString(&cur, runtime_id);
    try cur.write(",\"command\":{\"type\":\"saveTaskState\",\"projects\":[");
    if (skeleton.project_path.len > 0) {
        try cur.write("{\"id\":");
        try writeJsonString(&cur, skeleton.session_id);
        try cur.write(",\"name\":");
        try writeJsonString(&cur, projectName(skeleton.project_path));
        try cur.write(",\"path\":");
        try writeJsonString(&cur, skeleton.project_path);
        try cur.write(",\"created_at\":0}");
    }
    try cur.write("],\"liveSessionIds\":[");
    try writeJsonString(&cur, skeleton.session_id);
    try cur.write("],\"sessions\":[{\"id\":");
    try writeJsonString(&cur, skeleton.session_id);
    try cur.write(",\"title\":");
    try writeJsonString(&cur, skeleton.title);
    try cur.write(",\"project_id\":");
    try writeJsonString(&cur, if (skeleton.project_path.len > 0) skeleton.session_id else NIL_UUID);
    try cur.write(",\"provider\":");
    try writeJsonString(&cur, skeleton.provider);
    try cur.write(",\"runtime_mode\":");
    try writeJsonString(&cur, skeleton.runtime_mode);
    try cur.write(",\"status\":\"idle\",\"created_at\":0,\"updated_at\":0,\"project_path\":");
    try writeJsonString(&cur, skeleton.project_path);
    try cur.write(",\"has_started\":");
    try writeBool(&cur, skeleton.has_started);
    try cur.write("}]}}");
    return cur.slice();
}

/// Bare verified `attachSession`. Request-frame `sessionId` is the
/// target; `runtimeId` on the request is nil in Waku's attach client.
/// Non-nil `requestId` so the daemon replies with `sessionRuntime`.
pub fn writeAttachSession(
    buf: []u8,
    request_id: []const u8,
    session_id: []const u8,
) WriteError![]const u8 {
    return writeBareCommand(buf, request_id, session_id, NIL_UUID, .attach_session);
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

/// Request wrapping verified `hydrateSession` `{ type, sessionId }`.
/// Request-frame `sessionId` is nil (Waku server test); the target is
/// `command.sessionId`. Non-nil `requestId` so the daemon replies.
pub fn writeHydrateSession(
    buf: []u8,
    request_id: []const u8,
    session_id: []const u8,
) WriteError![]const u8 {
    var cur = Cursor{ .buf = buf };
    try cur.write("{\"type\":\"request\",\"requestId\":");
    try writeJsonString(&cur, request_id);
    try cur.write(",\"sessionId\":");
    try writeJsonString(&cur, NIL_UUID);
    try cur.write(",\"runtimeId\":");
    try writeJsonString(&cur, NIL_UUID);
    try cur.write(",\"command\":{\"type\":\"hydrateSession\",\"sessionId\":");
    try writeJsonString(&cur, session_id);
    try cur.write("}}");
    return cur.slice();
}

fn jsonObject(value: std.json.Value) ?std.json.ObjectMap {
    return switch (value) {
        .object => |o| o,
        else => null,
    };
}

fn jsonStringValue(value: ?std.json.Value) ?[]const u8 {
    const item = value orelse return null;
    return switch (item) {
        .string => |s| s,
        else => null,
    };
}

fn jsonUintValue(value: ?std.json.Value) ?u32 {
    const item = value orelse return null;
    return switch (item) {
        .integer => |n| if (n >= 0 and n <= std.math.maxInt(u32)) @intCast(n) else null,
        else => null,
    };
}

fn jsonU64Value(value: ?std.json.Value) ?u64 {
    const item = value orelse return null;
    return switch (item) {
        .integer => |n| if (n >= 0) @intCast(n) else null,
        else => null,
    };
}

fn jsonBoolValue(value: ?std.json.Value) ?bool {
    const item = value orelse return null;
    return switch (item) {
        .bool => |b| b,
        else => null,
    };
}

fn parseOutcome(obj: std.json.ObjectMap, parsed: *ParsedServer) void {
    const outcome_val = obj.get("outcome") orelse return;
    const outcome = jsonObject(outcome_val) orelse return;
    const status = jsonStringValue(outcome.get("status")) orelse return;
    if (std.mem.eql(u8, status, "ok")) {
        parsed.response_ok = true;
        if (outcome.get("payload")) |payload_val| {
            if (jsonObject(payload_val)) |payload| {
                parsed.payload_type = jsonStringValue(payload.get("type")) orelse "";
                if (std.mem.eql(u8, parsed.payload_type, "sessionRuntime")) {
                    parsed.runtime_id = jsonStringValue(payload.get("runtimeId")) orelse "";
                    parsed.supports_steer = jsonBoolValue(payload.get("supportsSteer")) orelse false;
                } else if (std.mem.eql(u8, parsed.payload_type, "started")) {
                    parsed.supports_steer = jsonBoolValue(payload.get("supportsSteer")) orelse false;
                }
            }
        }
        return;
    }
    if (std.mem.eql(u8, status, "error")) {
        parsed.response_ok = false;
        if (outcome.get("error")) |err_val| {
            if (jsonObject(err_val)) |err_obj| {
                parsed.message = jsonStringValue(err_obj.get("message")) orelse "";
            }
        }
    }
}

fn projectPathFor(projects: []const std.json.Value, project_id: []const u8) []const u8 {
    if (project_id.len == 0) return "";
    for (projects) |item| {
        const obj = jsonObject(item) orelse continue;
        const id = jsonStringValue(obj.get("id")) orelse continue;
        if (!std.mem.eql(u8, id, project_id)) continue;
        return jsonStringValue(obj.get("path")) orelse "";
    }
    return "";
}

/// Extract session skeletons from a `taskState` response. Empty on any
/// other frame, a failed outcome, or a payload that is not `taskState`.
/// Parses confirmed AgentSession keys plus Faku extras `project_path` /
/// `has_started` when present. Missing `has_started` defaults to true
/// (daemon catalog rows are stored started sessions). Missing
/// `project_path` falls back to `projects[].path` via `project_id`.
pub fn parseTaskStateSkeletons(allocator: std.mem.Allocator, line: []const u8) ParsedTaskState {
    var parsed = ParsedTaskState{};
    const trimmed = std.mem.trim(u8, line, " \t\r\n");
    if (trimmed.len < 2 or trimmed[0] != '{') return parsed;

    const root = std.json.parseFromSliceLeaky(std.json.Value, allocator, trimmed, .{}) catch return parsed;
    const obj = jsonObject(root) orelse return parsed;
    if (!std.mem.eql(u8, jsonStringValue(obj.get("type")) orelse "", "response")) return parsed;
    const outcome = jsonObject(obj.get("outcome") orelse return parsed) orelse return parsed;
    if (!std.mem.eql(u8, jsonStringValue(outcome.get("status")) orelse "", "ok")) return parsed;
    const payload = jsonObject(outcome.get("payload") orelse return parsed) orelse return parsed;
    if (!std.mem.eql(u8, jsonStringValue(payload.get("type")) orelse "", "taskState")) return parsed;

    const projects: []const std.json.Value = blk: {
        const projects_val = payload.get("projects") orelse break :blk &.{};
        break :blk switch (projects_val) {
            .array => |arr| arr.items,
            else => &.{},
        };
    };

    const sessions_val = payload.get("sessions") orelse return parsed;
    const sessions = switch (sessions_val) {
        .array => |arr| arr.items,
        else => return parsed,
    };

    for (sessions) |item| {
        if (parsed.session_count >= max_task_state_sessions) break;
        const session = jsonObject(item) orelse continue;
        const session_id = jsonStringValue(session.get("id")) orelse continue;
        const title = jsonStringValue(session.get("title")) orelse continue;
        const provider = jsonStringValue(session.get("provider")) orelse continue;
        if (session_id.len == 0) continue;
        var project_path = jsonStringValue(session.get("project_path")) orelse "";
        if (project_path.len == 0) {
            const project_id = jsonStringValue(session.get("project_id")) orelse "";
            project_path = projectPathFor(projects, project_id);
        }
        parsed.sessions[parsed.session_count] = .{
            .session_id = session_id,
            .title = title,
            .provider = provider,
            .project_path = project_path,
            .has_started = jsonBoolValue(session.get("has_started")) orelse true,
        };
        parsed.session_count += 1;
    }
    return parsed;
}

/// Extract transcript messages from a `session` hydrate response. Empty
/// on any other frame, a failed outcome, a payload that is not
/// `session`, or `session: null`. Parses confirmed AgentSession keys
/// `messages` (`role`, `content`) and `queued_messages` (`content`).
pub fn parseHydratedSession(allocator: std.mem.Allocator, line: []const u8) ParsedHydrate {
    var parsed = ParsedHydrate{};
    const trimmed = std.mem.trim(u8, line, " \t\r\n");
    if (trimmed.len < 2 or trimmed[0] != '{') return parsed;

    const root = std.json.parseFromSliceLeaky(std.json.Value, allocator, trimmed, .{}) catch return parsed;
    const obj = jsonObject(root) orelse return parsed;
    if (!std.mem.eql(u8, jsonStringValue(obj.get("type")) orelse "", "response")) return parsed;
    const outcome = jsonObject(obj.get("outcome") orelse return parsed) orelse return parsed;
    if (!std.mem.eql(u8, jsonStringValue(outcome.get("status")) orelse "", "ok")) return parsed;
    const payload = jsonObject(outcome.get("payload") orelse return parsed) orelse return parsed;
    if (!std.mem.eql(u8, jsonStringValue(payload.get("type")) orelse "", "session")) return parsed;
    const session = jsonObject(payload.get("session") orelse return parsed) orelse return parsed;
    parsed.ok = true;

    if (session.get("messages")) |messages_val| {
        const messages = switch (messages_val) {
            .array => |arr| arr.items,
            else => &.{},
        };
        for (messages) |item| {
            if (parsed.message_count >= max_hydrate_messages) break;
            const message = jsonObject(item) orelse continue;
            const role = jsonStringValue(message.get("role")) orelse continue;
            const content = jsonStringValue(message.get("content")) orelse continue;
            parsed.messages[parsed.message_count] = .{ .role = role, .content = content };
            parsed.message_count += 1;
        }
    }

    if (session.get("queued_messages")) |queued_val| {
        const queued = switch (queued_val) {
            .array => |arr| arr.items,
            else => &.{},
        };
        for (queued) |item| {
            if (parsed.queued_count >= max_hydrate_queued) break;
            const row = jsonObject(item) orelse continue;
            const content = jsonStringValue(row.get("content")) orelse continue;
            parsed.queued[parsed.queued_count] = .{ .content = content };
            parsed.queued_count += 1;
        }
    }
    return parsed;
}

/// Extract `runtimeId` from a `sessionRuntime` response. Empty on any
/// other frame, a failed outcome, a payload that is not
/// `sessionRuntime`, or `runtimeId: null`. Does not invent an id.
pub fn parseSessionRuntime(allocator: std.mem.Allocator, line: []const u8) ParsedSessionRuntime {
    var parsed = ParsedSessionRuntime{};
    const trimmed = std.mem.trim(u8, line, " \t\r\n");
    if (trimmed.len < 2 or trimmed[0] != '{') return parsed;

    const root = std.json.parseFromSliceLeaky(std.json.Value, allocator, trimmed, .{}) catch return parsed;
    const obj = jsonObject(root) orelse return parsed;
    if (!std.mem.eql(u8, jsonStringValue(obj.get("type")) orelse "", "response")) return parsed;
    const outcome = jsonObject(obj.get("outcome") orelse return parsed) orelse return parsed;
    if (!std.mem.eql(u8, jsonStringValue(outcome.get("status")) orelse "", "ok")) return parsed;
    const payload = jsonObject(outcome.get("payload") orelse return parsed) orelse return parsed;
    if (!std.mem.eql(u8, jsonStringValue(payload.get("type")) orelse "", "sessionRuntime")) return parsed;
    parsed.ok = true;
    parsed.runtime_id = jsonStringValue(payload.get("runtimeId")) orelse "";
    parsed.supports_steer = jsonBoolValue(payload.get("supportsSteer")) orelse false;
    return parsed;
}

/// A daemon-issued runtime UUID, not empty and not the nil notify id.
pub fn isUsableRuntimeId(id: []const u8) bool {
    return id.len > 0 and !std.mem.eql(u8, id, NIL_UUID);
}

fn parseEvent(obj: std.json.ObjectMap, parsed: *ParsedServer) void {
    parsed.session_id = jsonStringValue(obj.get("sessionId")) orelse "";
    parsed.runtime_id = jsonStringValue(obj.get("runtimeId")) orelse "";
    const event_val = obj.get("event") orelse return;
    const event_obj = jsonObject(event_val) orelse return;
    const kind_name = jsonStringValue(event_obj.get("kind")) orelse return;
    parsed.event_kind_name = kind_name;
    parsed.event_kind = EventKind.fromWire(kind_name);
    const payload = event_obj.get("payload") orelse return;
    switch (payload) {
        .string => |s| {
            parsed.text_delta = s;
            if (parsed.event_kind == .@"error") parsed.message = s;
        },
        .null => {
            if (parsed.event_kind == .goal_updated) parsed.goal_cleared = true;
        },
        .object => |o| {
            if (jsonBoolValue(o.get("success"))) |ok| parsed.turn_success = ok;
            if (jsonStringValue(o.get("summary"))) |summary| parsed.message = summary;
            if (jsonStringValue(o.get("text"))) |text| parsed.text_delta = text;
            if (o.get("objective")) |objective_val| {
                parsed.goal_has_objective = true;
                parsed.goal_objective = jsonStringValue(objective_val) orelse "";
            }
            if (o.get("status")) |status_val| {
                parsed.goal_has_status = true;
                parsed.goal_status = jsonStringValue(status_val) orelse "";
            }
            if (o.get("tokenBudget")) |budget_val| {
                parsed.goal_has_token_budget = true;
                switch (budget_val) {
                    .null => parsed.goal_token_budget_null = true,
                    else => {
                        if (jsonU64Value(budget_val)) |n| parsed.goal_token_budget = n;
                    },
                }
            }
            if (jsonU64Value(o.get("tokensUsed"))) |n| {
                parsed.goal_has_tokens_used = true;
                parsed.goal_tokens_used = n;
            }
            if (jsonU64Value(o.get("timeUsedSeconds"))) |n| {
                parsed.goal_has_time_used_seconds = true;
                parsed.goal_time_used_seconds = n;
            }
        },
        else => {},
    }
}

/// Classify one daemon stdout / WebSocket text frame. Unknown objects
/// come back as `.invalid` rather than error so a sidecar can skip them.
pub fn parseServerFrame(allocator: std.mem.Allocator, line: []const u8) ParsedServer {
    var parsed = ParsedServer{};
    const trimmed = std.mem.trim(u8, line, " \t\r\n");
    if (trimmed.len < 2 or trimmed[0] != '{') return parsed;

    const root = std.json.parseFromSliceLeaky(std.json.Value, allocator, trimmed, .{}) catch return parsed;
    const obj = jsonObject(root) orelse return parsed;
    const type_name = jsonStringValue(obj.get("type")) orelse return parsed;

    if (std.mem.eql(u8, type_name, "hello")) {
        parsed.frame = .hello;
        parsed.protocol_version = jsonUintValue(obj.get("protocolVersion")) orelse 0;
        parsed.daemon_version = jsonStringValue(obj.get("daemonVersion")) orelse "";
    } else if (std.mem.eql(u8, type_name, "rejected")) {
        parsed.frame = .rejected;
        parsed.message = jsonStringValue(obj.get("message")) orelse "";
    } else if (std.mem.eql(u8, type_name, "response")) {
        parsed.frame = .response;
        parsed.request_id = jsonStringValue(obj.get("requestId")) orelse "";
        parseOutcome(obj, &parsed);
    } else if (std.mem.eql(u8, type_name, "event")) {
        parsed.frame = .event;
        parseEvent(obj, &parsed);
    } else if (std.mem.eql(u8, type_name, "taskStateChanged")) {
        parsed.frame = .task_state_changed;
    } else if (std.mem.eql(u8, type_name, "shuttingDown")) {
        parsed.frame = .shutting_down;
    }
    return parsed;
}

/// Sidecar / desktop: stop the one-shot after these frames.
pub fn isTerminalServerFrame(parsed: ParsedServer) bool {
    return switch (parsed.frame) {
        .rejected => true,
        .event => parsed.event_kind == .turn_finished or parsed.event_kind == .@"error",
        else => false,
    };
}

test "client hello is camelCase protocol v4" {
    var buf: [256]u8 = undefined;
    const json = try writeClientHello(&buf, "secret", "00000000-0000-0000-0000-000000000002", &.{});
    try std.testing.expect(std.mem.indexOf(u8, json, "\"type\":\"hello\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"protocolVersion\":4") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"token\":\"secret\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "protocol_version") == null);
    try std.testing.expectEqual(@as(u32, 4), PROTOCOL_VERSION);
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

test "steer request wraps a camelCase command with prompt payload" {
    var buf: [256]u8 = undefined;
    const json = try writeSteer(
        &buf,
        NIL_UUID,
        "00000000-0000-0000-0000-000000000001",
        "00000000-0000-0000-0000-000000000003",
        "keep going on the listener",
    );
    try std.testing.expect(std.mem.indexOf(u8, json, "\"type\":\"request\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"sessionId\":\"00000000-0000-0000-0000-000000000001\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"runtimeId\":\"00000000-0000-0000-0000-000000000003\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"command\":{\"type\":\"steer\",\"prompt\":\"keep going on the listener\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"type\":\"prompt\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"type\":\"cancel\"") == null);
}

test "goal request wraps camelCase operation refresh set and clear" {
    var buf: [512]u8 = undefined;
    const refresh = try writeGoal(
        &buf,
        NIL_UUID,
        "00000000-0000-0000-0000-000000000001",
        "00000000-0000-0000-0000-000000000003",
        .refresh,
    );
    try std.testing.expect(std.mem.indexOf(u8, refresh, "\"type\":\"request\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, refresh, "\"sessionId\":\"00000000-0000-0000-0000-000000000001\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, refresh, "\"runtimeId\":\"00000000-0000-0000-0000-000000000003\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, refresh, "\"command\":{\"type\":\"goal\",\"operation\":{\"kind\":\"refresh\"}}") != null);
    try std.testing.expect(std.mem.indexOf(u8, refresh, "\"type\":\"prompt\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, refresh, "\"type\":\"steer\"") == null);

    const set = try writeGoal(&buf, NIL_UUID, NIL_UUID, NIL_UUID, .{
        .set = .{
            .objective = "Ship the feature",
            .status = ThreadGoalStatus.active.wireName(),
            .replace = false,
        },
    });
    try std.testing.expect(std.mem.indexOf(u8, set, "\"command\":{\"type\":\"goal\",\"operation\":{\"kind\":\"set\",\"objective\":\"Ship the feature\",\"status\":\"active\",\"replace\":false}}") != null);

    const nulls = try writeGoal(&buf, NIL_UUID, NIL_UUID, NIL_UUID, .{
        .set = .{ .objective = null, .status = null, .replace = true },
    });
    try std.testing.expect(std.mem.indexOf(u8, nulls, "\"kind\":\"set\",\"objective\":null,\"status\":null,\"replace\":true") != null);

    const clear = try writeGoal(&buf, NIL_UUID, NIL_UUID, NIL_UUID, .clear);
    try std.testing.expect(std.mem.indexOf(u8, clear, "\"command\":{\"type\":\"goal\",\"operation\":{\"kind\":\"clear\"}}") != null);
    try std.testing.expectEqualStrings("active", ThreadGoalStatus.active.wireName());
    try std.testing.expectEqualStrings("usageLimited", ThreadGoalStatus.usage_limited.wireName());
    try std.testing.expectEqualStrings("budgetLimited", ThreadGoalStatus.budget_limited.wireName());
    try std.testing.expectEqual(ThreadGoalStatus.complete, ThreadGoalStatus.fromWire("complete").?);
    try std.testing.expect(ThreadGoalStatus.fromWire("unknown") == null);
}

test "start defaults to first-party fx over acp" {
    var buf: [512]u8 = undefined;
    const json = try writeStart(&buf, NIL_UUID, NIL_UUID, NIL_UUID, defaultStartOptions());
    try std.testing.expect(std.mem.indexOf(u8, json, "\"provider\":\"fx\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"binary\":\"fx\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "reasoningEffort") == null);
    try std.testing.expectEqualStrings("fx", ProviderId.default.wireName());
    try std.testing.expectEqual(ProviderId.fx, ProviderId.fromWire("fx").?);
    try std.testing.expectEqual(ProviderId.claude, ProviderId.fromWire("claude").?);
    try std.testing.expectEqualStrings("fx", FX_ACP_ARGV[0]);
    try std.testing.expectEqualStrings("acp", FX_ACP_ARGV[1]);
    try std.testing.expectEqualStrings("acp", FX_TRANSPORT);
    try std.testing.expect(ProviderId.cursor.speaksBareAcp());
    try std.testing.expect(ProviderId.opencode.speaksBareAcp());
    try std.testing.expect(!ProviderId.fx.speaksBareAcp());
    try std.testing.expect(!ProviderId.claude.speaksBareAcp());
    try std.testing.expect(!ProviderId.codex.speaksBareAcp());
    try std.testing.expect(!ProviderId.amp.speaksBareAcp());
    try std.testing.expect(!ProviderId.grok.speaksBareAcp());
    try std.testing.expect(!ProviderId.pi.speaksBareAcp());
    try std.testing.expect(ProviderId.cursor.speaksAcpStdio());
    try std.testing.expect(ProviderId.opencode.speaksAcpStdio());
    try std.testing.expect(ProviderId.grok.speaksAcpStdio());
    try std.testing.expect(!ProviderId.fx.speaksAcpStdio());
    try std.testing.expect(!ProviderId.claude.speaksAcpStdio());
    try std.testing.expect(!ProviderId.codex.speaksAcpStdio());
    try std.testing.expect(!ProviderId.amp.speaksAcpStdio());
    try std.testing.expectEqualStrings("acp", ProviderId.cursor.acpTransportArgv()[0]);
    try std.testing.expectEqual(@as(usize, 1), ProviderId.cursor.acpTransportArgv().len);
    try std.testing.expectEqualStrings("acp", ProviderId.opencode.acpTransportArgv()[0]);
    try std.testing.expectEqualStrings("acp", ProviderId.fx.acpTransportArgv()[0]);
    try std.testing.expectEqual(@as(usize, 2), ProviderId.grok.acpTransportArgv().len);
    try std.testing.expectEqualStrings("agent", ProviderId.grok.acpTransportArgv()[0]);
    try std.testing.expectEqualStrings("stdio", ProviderId.grok.acpTransportArgv()[1]);
    try std.testing.expectEqual(@as(usize, 0), ProviderId.claude.acpTransportArgv().len);
    try std.testing.expectEqual(@as(usize, 0), ProviderId.codex.acpTransportArgv().len);
    try std.testing.expectEqual(@as(usize, 0), ProviderId.amp.acpTransportArgv().len);
    try std.testing.expectEqualStrings("agent", GROK_ACP_TRANSPORT[0]);
    try std.testing.expectEqualStrings("stdio", GROK_ACP_TRANSPORT[1]);
}

test "writeStart includes reasoningEffort when set and omits when empty" {
    var buf: [512]u8 = undefined;
    const with_effort = try writeStart(&buf, NIL_UUID, NIL_UUID, NIL_UUID, .{
        .reasoning_effort = "high",
    });
    try std.testing.expect(std.mem.indexOf(u8, with_effort, "\"reasoningEffort\":\"high\"") != null);

    const empty_effort = try writeStart(&buf, NIL_UUID, NIL_UUID, NIL_UUID, .{
        .reasoning_effort = "",
    });
    try std.testing.expect(std.mem.indexOf(u8, empty_effort, "reasoningEffort") == null);

    const omitted = try writeStart(&buf, NIL_UUID, NIL_UUID, NIL_UUID, defaultStartOptions());
    try std.testing.expect(std.mem.indexOf(u8, omitted, "reasoningEffort") == null);
}

test "first-cut command tags stay camelCase on the wire" {
    try std.testing.expectEqualStrings("loadTaskState", CommandTag.load_task_state.wireName());
    try std.testing.expectEqualStrings("hydrateSession", CommandTag.hydrate_session.wireName());
    try std.testing.expectEqualStrings("saveTaskState", CommandTag.save_task_state.wireName());
    try std.testing.expectEqualStrings("closeSession", CommandTag.close_session.wireName());
    try std.testing.expectEqualStrings("attachSession", CommandTag.attach_session.wireName());
    try std.testing.expectEqualStrings("cancel", CommandTag.cancel.wireName());
    try std.testing.expectEqualStrings("steer", CommandTag.steer.wireName());
    try std.testing.expectEqualStrings("goal", CommandTag.goal.wireName());
    try std.testing.expectEqualStrings("steerAccepted", EventKind.steer_accepted.wireName());
    try std.testing.expectEqualStrings("steerRejected", EventKind.steer_rejected.wireName());
    try std.testing.expectEqualStrings("goalUpdated", EventKind.goal_updated.wireName());
    try std.testing.expectEqualStrings("turnFinished", EventKind.turn_finished.wireName());
    try std.testing.expectEqualStrings("textDelta", EventKind.text_delta.wireName());
}

test "saveTaskState carries verified projects liveSessionIds and a session skeleton" {
    var buf: [1024]u8 = undefined;
    const json = try writeSaveTaskState(&buf, NIL_UUID, NIL_UUID, .{
        .session_id = "00000000-0000-0000-0000-000000000001",
        .title = "port waku to zig",
        .provider = "fx",
        .project_path = "/tmp/faku",
        .has_started = true,
    });
    try std.testing.expect(std.mem.indexOf(u8, json, "\"type\":\"request\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"type\":\"saveTaskState\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"liveSessionIds\":[\"00000000-0000-0000-0000-000000000001\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"projects\":[{\"id\":\"00000000-0000-0000-0000-000000000001\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"path\":\"/tmp/faku\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"name\":\"faku\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"title\":\"port waku to zig\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"provider\":\"fx\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"project_path\":\"/tmp/faku\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"has_started\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"type\":\"prompt\"") == null);

    const empty = try writeSaveTaskState(&buf, NIL_UUID, NIL_UUID, .{
        .session_id = NIL_UUID,
        .title = "untitled",
        .provider = "claude",
    });
    try std.testing.expect(std.mem.indexOf(u8, empty, "\"projects\":[]") != null);
    try std.testing.expect(std.mem.indexOf(u8, empty, "\"project_id\":\"00000000-0000-0000-0000-000000000000\"") != null);
}

test "server-frame parser round-trips hello rejected response and events" {
    const allocator = std.testing.allocator;
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const hello = parseServerFrame(arena, "{\"type\":\"hello\",\"protocolVersion\":4,\"daemonVersion\":\"0.1.9\"}");
    try std.testing.expectEqual(ServerFrame.hello, hello.frame);
    try std.testing.expectEqual(@as(u32, 4), hello.protocol_version);
    try std.testing.expectEqualStrings("0.1.9", hello.daemon_version);

    const rejected = parseServerFrame(arena, "{\"type\":\"rejected\",\"message\":\"bad token\"}");
    try std.testing.expectEqual(ServerFrame.rejected, rejected.frame);
    try std.testing.expectEqualStrings("bad token", rejected.message);
    try std.testing.expect(isTerminalServerFrame(rejected));

    const ok = parseServerFrame(arena, "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000001\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"ack\"}}}");
    try std.testing.expectEqual(ServerFrame.response, ok.frame);
    try std.testing.expect(ok.response_ok);
    try std.testing.expectEqualStrings("ack", ok.payload_type);
    try std.testing.expect(!isTerminalServerFrame(ok));

    const err = parseServerFrame(arena, "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000001\",\"outcome\":{\"status\":\"error\",\"error\":{\"message\":\"nope\"}}}");
    try std.testing.expectEqual(ServerFrame.response, err.frame);
    try std.testing.expect(!err.response_ok);
    try std.testing.expectEqualStrings("nope", err.message);

    const delta = parseServerFrame(arena, "{\"type\":\"event\",\"sessionId\":\"00000000-0000-0000-0000-000000000001\",\"runtimeId\":\"00000000-0000-0000-0000-000000000003\",\"epoch\":\"00000000-0000-0000-0000-000000000004\",\"sequence\":1,\"event\":{\"kind\":\"textDelta\",\"payload\":\"hello from daemon\"}}");
    try std.testing.expectEqual(ServerFrame.event, delta.frame);
    try std.testing.expectEqual(EventKind.text_delta, delta.event_kind.?);
    try std.testing.expectEqualStrings("textDelta", delta.event_kind_name);
    try std.testing.expectEqualStrings("hello from daemon", delta.text_delta);
    try std.testing.expect(!isTerminalServerFrame(delta));

    const finished = parseServerFrame(arena, "{\"type\":\"event\",\"sessionId\":\"00000000-0000-0000-0000-000000000001\",\"runtimeId\":\"00000000-0000-0000-0000-000000000003\",\"epoch\":\"00000000-0000-0000-0000-000000000004\",\"sequence\":2,\"event\":{\"kind\":\"turnFinished\",\"payload\":{\"success\":true,\"summary\":\"done\"}}}");
    try std.testing.expectEqual(EventKind.turn_finished, finished.event_kind.?);
    try std.testing.expect(finished.turn_success);
    try std.testing.expect(isTerminalServerFrame(finished));

    const failed = parseServerFrame(arena, "{\"type\":\"event\",\"event\":{\"kind\":\"turnFinished\",\"payload\":{\"success\":false}}}");
    try std.testing.expect(isTerminalServerFrame(failed));
    try std.testing.expect(!failed.turn_success);

    const boom = parseServerFrame(arena, "{\"type\":\"event\",\"event\":{\"kind\":\"error\",\"payload\":\"provider died\"}}");
    try std.testing.expectEqual(EventKind.@"error", boom.event_kind.?);
    try std.testing.expect(isTerminalServerFrame(boom));
    try std.testing.expectEqualStrings("provider died", boom.message);
}

test "goalUpdated event yields objective and status or a clear" {
    const allocator = std.testing.allocator;
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const updated = parseServerFrame(arena, "{\"type\":\"event\",\"sessionId\":\"00000000-0000-0000-0000-000000000001\",\"runtimeId\":\"00000000-0000-0000-0000-000000000003\",\"event\":{\"kind\":\"goalUpdated\",\"payload\":{\"objective\":\"Ship the feature\",\"status\":\"usageLimited\"}}}");
    try std.testing.expectEqual(ServerFrame.event, updated.frame);
    try std.testing.expectEqual(EventKind.goal_updated, updated.event_kind.?);
    try std.testing.expectEqualStrings("goalUpdated", updated.event_kind_name);
    try std.testing.expect(updated.goal_has_objective);
    try std.testing.expect(updated.goal_has_status);
    try std.testing.expect(!updated.goal_cleared);
    try std.testing.expectEqualStrings("Ship the feature", updated.goal_objective);
    try std.testing.expectEqualStrings("usageLimited", updated.goal_status);
    try std.testing.expect(!updated.goal_has_token_budget);
    try std.testing.expect(!updated.goal_token_budget_null);
    try std.testing.expect(!updated.goal_has_tokens_used);
    try std.testing.expect(!updated.goal_has_time_used_seconds);
    try std.testing.expect(!isTerminalServerFrame(updated));

    const with_budget = parseServerFrame(arena, "{\"type\":\"event\",\"event\":{\"kind\":\"goalUpdated\",\"payload\":{\"objective\":\"Ship the feature\",\"status\":\"active\",\"tokenBudget\":100000,\"tokensUsed\":12000,\"timeUsedSeconds\":180}}}");
    try std.testing.expect(with_budget.goal_has_token_budget);
    try std.testing.expect(!with_budget.goal_token_budget_null);
    try std.testing.expectEqual(@as(u64, 100000), with_budget.goal_token_budget);
    try std.testing.expect(with_budget.goal_has_tokens_used);
    try std.testing.expectEqual(@as(u64, 12000), with_budget.goal_tokens_used);
    try std.testing.expect(with_budget.goal_has_time_used_seconds);
    try std.testing.expectEqual(@as(u64, 180), with_budget.goal_time_used_seconds);

    const used_only = parseServerFrame(arena, "{\"type\":\"event\",\"event\":{\"kind\":\"goalUpdated\",\"payload\":{\"tokensUsed\":12000}}}");
    try std.testing.expect(!used_only.goal_has_token_budget);
    try std.testing.expect(!used_only.goal_token_budget_null);
    try std.testing.expect(used_only.goal_has_tokens_used);
    try std.testing.expectEqual(@as(u64, 12000), used_only.goal_tokens_used);
    try std.testing.expect(!used_only.goal_has_time_used_seconds);

    const budget_null = parseServerFrame(arena, "{\"type\":\"event\",\"event\":{\"kind\":\"goalUpdated\",\"payload\":{\"tokenBudget\":null,\"tokensUsed\":500,\"timeUsedSeconds\":45}}}");
    try std.testing.expect(budget_null.goal_has_token_budget);
    try std.testing.expect(budget_null.goal_token_budget_null);
    try std.testing.expectEqual(@as(u64, 0), budget_null.goal_token_budget);
    try std.testing.expect(budget_null.goal_has_tokens_used);
    try std.testing.expectEqual(@as(u64, 500), budget_null.goal_tokens_used);
    try std.testing.expect(budget_null.goal_has_time_used_seconds);
    try std.testing.expectEqual(@as(u64, 45), budget_null.goal_time_used_seconds);

    const cleared = parseServerFrame(arena, "{\"type\":\"event\",\"event\":{\"kind\":\"goalUpdated\",\"payload\":null}}");
    try std.testing.expectEqual(EventKind.goal_updated, cleared.event_kind.?);
    try std.testing.expect(cleared.goal_cleared);
    try std.testing.expectEqual(@as(usize, 0), cleared.goal_objective.len);
    try std.testing.expect(!cleared.goal_has_objective);
    try std.testing.expect(!cleared.goal_has_token_budget);
    try std.testing.expect(!cleared.goal_has_tokens_used);
    try std.testing.expect(!cleared.goal_has_time_used_seconds);
}

test "taskState response yields session skeletons and project path fallback" {
    const allocator = std.testing.allocator;
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const line =
        \\{"type":"response","requestId":"00000000-0000-0000-0000-000000000010","outcome":{"status":"ok","payload":{"type":"taskState","projects":[{"id":"00000000-0000-0000-0000-000000000007","name":"faku","path":"/tmp/from-project","created_at":0}],"sessions":[{"id":"00000000-0000-0000-0000-000000000007","title":"from daemon","project_id":"00000000-0000-0000-0000-000000000007","provider":"fx","runtime_mode":"fullAccess","status":"idle","created_at":0,"updated_at":0,"has_started":true},{"id":"00000000-0000-0000-0000-000000000008","title":"extra path","provider":"claude","project_path":"/tmp/extra","has_started":false}],"defaultCwd":"/tmp","projectlessRoot":null}}}
    ;
    const parsed = parseTaskStateSkeletons(arena, line);
    try std.testing.expectEqual(@as(usize, 2), parsed.session_count);
    try std.testing.expectEqualStrings("00000000-0000-0000-0000-000000000007", parsed.sessions[0].session_id);
    try std.testing.expectEqualStrings("from daemon", parsed.sessions[0].title);
    try std.testing.expectEqualStrings("fx", parsed.sessions[0].provider);
    try std.testing.expectEqualStrings("/tmp/from-project", parsed.sessions[0].project_path);
    try std.testing.expect(parsed.sessions[0].has_started);
    try std.testing.expectEqualStrings("extra path", parsed.sessions[1].title);
    try std.testing.expectEqualStrings("claude", parsed.sessions[1].provider);
    try std.testing.expectEqualStrings("/tmp/extra", parsed.sessions[1].project_path);
    try std.testing.expect(!parsed.sessions[1].has_started);

    const empty = parseTaskStateSkeletons(arena, "{\"type\":\"response\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"ack\"}}}");
    try std.testing.expectEqual(@as(usize, 0), empty.session_count);

    const failed = parseTaskStateSkeletons(arena, "{\"type\":\"response\",\"outcome\":{\"status\":\"error\",\"error\":{\"message\":\"nope\"}}}");
    try std.testing.expectEqual(@as(usize, 0), failed.session_count);
}

test "attachSession is a bare command with sessionId on the request frame" {
    var buf: [512]u8 = undefined;
    const json = try writeAttachSession(
        &buf,
        "00000000-0000-0000-0000-000000000012",
        "00000000-0000-0000-0000-000000000007",
    );
    try std.testing.expect(std.mem.indexOf(u8, json, "\"type\":\"request\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"requestId\":\"00000000-0000-0000-0000-000000000012\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"sessionId\":\"00000000-0000-0000-0000-000000000007\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"runtimeId\":\"" ++ NIL_UUID ++ "\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"command\":{\"type\":\"attachSession\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"type\":\"start\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"type\":\"loadTaskState\"") == null);
}

test "sessionRuntime response yields runtimeId and ignores null" {
    const allocator = std.testing.allocator;
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const line =
        \\{"type":"response","requestId":"00000000-0000-0000-0000-000000000012","outcome":{"status":"ok","payload":{"type":"sessionRuntime","runtimeId":"00000000-0000-0000-0000-000000000003","supportsSteer":true}}}
    ;
    const parsed = parseSessionRuntime(arena, line);
    try std.testing.expect(parsed.ok);
    try std.testing.expectEqualStrings("00000000-0000-0000-0000-000000000003", parsed.runtime_id);
    try std.testing.expect(parsed.supports_steer);
    try std.testing.expect(isUsableRuntimeId(parsed.runtime_id));

    const frame = parseServerFrame(arena, line);
    try std.testing.expectEqual(ServerFrame.response, frame.frame);
    try std.testing.expect(frame.response_ok);
    try std.testing.expectEqualStrings("sessionRuntime", frame.payload_type);
    try std.testing.expectEqualStrings("00000000-0000-0000-0000-000000000003", frame.runtime_id);
    try std.testing.expect(frame.supports_steer);

    const started = parseServerFrame(arena, "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000013\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"started\",\"supportsSteer\":true}}}");
    try std.testing.expectEqual(ServerFrame.response, started.frame);
    try std.testing.expect(started.response_ok);
    try std.testing.expectEqualStrings("started", started.payload_type);
    try std.testing.expect(started.supports_steer);

    const missing = parseSessionRuntime(arena, "{\"type\":\"response\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"sessionRuntime\",\"runtimeId\":null,\"supportsSteer\":false}}}");
    try std.testing.expect(missing.ok);
    try std.testing.expectEqual(@as(usize, 0), missing.runtime_id.len);
    try std.testing.expect(!isUsableRuntimeId(missing.runtime_id));

    const other = parseSessionRuntime(arena, "{\"type\":\"response\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"ack\"}}}");
    try std.testing.expect(!other.ok);
    try std.testing.expectEqual(@as(usize, 0), other.runtime_id.len);
    try std.testing.expect(!isUsableRuntimeId(NIL_UUID));
    try std.testing.expect(!isUsableRuntimeId(""));
}

test "cancel is a bare command with sessionId and runtimeId on the request frame" {
    var buf: [512]u8 = undefined;
    const json = try writeBareCommand(
        &buf,
        NIL_UUID,
        "00000000-0000-0000-0000-000000000007",
        "00000000-0000-0000-0000-000000000003",
        .cancel,
    );
    try std.testing.expect(std.mem.indexOf(u8, json, "\"type\":\"request\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"sessionId\":\"00000000-0000-0000-0000-000000000007\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"runtimeId\":\"00000000-0000-0000-0000-000000000003\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"command\":{\"type\":\"cancel\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"prompt\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"type\":\"steer\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"type\":\"attachSession\"") == null);
}

test "closeSession is a bare command with sessionId on the request frame" {
    var buf: [512]u8 = undefined;
    const json = try writeBareCommand(
        &buf,
        NIL_UUID,
        "00000000-0000-0000-0000-000000000007",
        NIL_UUID,
        .close_session,
    );
    try std.testing.expect(std.mem.indexOf(u8, json, "\"type\":\"request\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"sessionId\":\"00000000-0000-0000-0000-000000000007\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"command\":{\"type\":\"closeSession\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"type\":\"removeSession\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"type\":\"attachSession\"") == null);
}

test "hydrateSession command carries sessionId on the command not as a bare type" {
    var buf: [512]u8 = undefined;
    const json = try writeHydrateSession(&buf, "00000000-0000-0000-0000-000000000011", "00000000-0000-0000-0000-000000000007");
    try std.testing.expect(std.mem.indexOf(u8, json, "\"type\":\"request\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"command\":{\"type\":\"hydrateSession\",\"sessionId\":\"00000000-0000-0000-0000-000000000007\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"requestId\":\"00000000-0000-0000-0000-000000000011\"") != null);
}

test "session hydrate response yields messages and queued_messages content" {
    const allocator = std.testing.allocator;
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const line =
        \\{"type":"response","requestId":"00000000-0000-0000-0000-000000000011","outcome":{"status":"ok","payload":{"type":"session","session":{"id":"00000000-0000-0000-0000-000000000007","title":"from daemon","messages":[{"id":"00000000-0000-0000-0000-000000000001","role":"user","content":"trace the listener"},{"id":"00000000-0000-0000-0000-000000000002","role":"assistant","content":"looking"}],"turns":[{"id":"00000000-0000-0000-0000-000000000003","turn_count":1,"status":"completed","started_at":0}],"queued_messages":[{"id":"00000000-0000-0000-0000-000000000004","content":"then the composer","created_at":0}]}}}}
    ;
    const parsed = parseHydratedSession(arena, line);
    try std.testing.expect(parsed.ok);
    try std.testing.expectEqual(@as(usize, 2), parsed.message_count);
    try std.testing.expectEqualStrings("user", parsed.messages[0].role);
    try std.testing.expectEqualStrings("trace the listener", parsed.messages[0].content);
    try std.testing.expectEqualStrings("assistant", parsed.messages[1].role);
    try std.testing.expectEqualStrings("looking", parsed.messages[1].content);
    try std.testing.expectEqual(@as(usize, 1), parsed.queued_count);
    try std.testing.expectEqualStrings("then the composer", parsed.queued[0].content);

    const missing = parseHydratedSession(arena, "{\"type\":\"response\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"session\",\"session\":null}}}");
    try std.testing.expect(!missing.ok);
    try std.testing.expectEqual(@as(usize, 0), missing.message_count);

    const other = parseHydratedSession(arena, "{\"type\":\"response\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"taskState\",\"sessions\":[]}}}");
    try std.testing.expect(!other.ok);
}
