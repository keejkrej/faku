//! Faku: Native SDK desktop for a Waku-protocol compatible coding-agent shell.
//!
//! First-party provider is Vercel `fx` (https://fx.sh). Send on an `.fx`
//! session runs `fx ask --json -- <prompt>` when the CLI is installed
//! (streamed stdout lines; `--resume <id>` after a minted session_id).
//! When `WAKU_DAEMON_ADDRESS` is set, Send instead spawns a one-shot
//! `daemon-proxy` sidecar (hello → loadTaskState → prompt over
//! `ws://{addr}/v1`). Missing address keeps `fx ask` / the demo timer.
//! ACP JSON-RPC helpers live in acp.zig; live `fx acp` waits on a
//! stdin-write effect and is not spawned.

const std = @import("std");
const runner = @import("runner");
const native_sdk = @import("native_sdk");
const protocol = @import("protocol.zig");
const acp = @import("acp.zig");
const store = @import("store.zig");
const daemon_proxy = @import("daemon_proxy.zig");

pub const panic = std.debug.FullPanic(native_sdk.debug.capturePanic);

const canvas = native_sdk.canvas;
const geometry = native_sdk.geometry;

const canvas_label = "main-canvas";
pub const window_width: f32 = 1200;
pub const window_height: f32 = 800;
pub const window_min_width: f32 = 800;
pub const window_min_height: f32 = 560;

const max_sessions = 16;
const max_turns = 128;
const max_title = 64;
const max_body = 4096;
pub const max_draft = 512;
pub const max_queued = 16;
pub const max_queued_text = 1024;
const max_fx_path = 256;
pub const max_store_dir = 512;
pub const max_project_path = 512;
pub const max_fx_session_id = 128;
pub const max_fx_model = 128;
pub const max_access_mode = 32;
/// Waku `runtime_mode` default. Maps to fx `FX_PERMISSION_MODE=yolo`.
pub const default_access_mode = "fullAccess";
pub const fx_env_bin = "/usr/bin/env";
const max_line_keep = 4096;

const app_permissions = [_][]const u8{ native_sdk.security.permission_command, native_sdk.security.permission_view };
const shell_views = [_]native_sdk.ShellView{
    .{ .label = canvas_label, .kind = .gpu_surface, .fill = true, .role = "Faku canvas", .accessibility_label = "Faku", .gpu_backend = .metal, .gpu_pixel_format = .bgra8_unorm, .gpu_present_mode = .timer, .gpu_alpha_mode = .@"opaque", .gpu_color_space = .srgb, .gpu_vsync = true },
};
const shell_windows = [_]native_sdk.ShellWindow{.{
    .label = "main",
    .title = "Faku",
    .width = window_width,
    .height = window_height,
    .min_width = window_min_width,
    .min_height = window_min_height,
    .titlebar = .hidden_inset_tall,
    .views = &shell_views,
}};
const shell_scene: native_sdk.ShellConfig = .{ .windows = &shell_windows };

pub const stream_timer_key: u64 = 1;
pub const fx_ask_key: u64 = 2;
pub const fx_probe_key: u64 = 3;
pub const daemon_proxy_key_first: u64 = 4;
pub const max_daemon_address = 128;
pub const max_daemon_token = 256;
pub const max_sidecar_path = 512;
pub const daemon_line_bytes: usize = 64 * 1024;
pub const stream_interval_ms: u64 = 90;
const stream_chunk_bytes: usize = 8;
const demo_ticks_complete: u32 = 12;
const demo_reply = "fx here (demo). The fx CLI was not found, so this is a local timer stream. Install fx and Send runs `fx ask`.";

pub const Mode = enum { demo, daemon };
pub const Role = enum { user, assistant, tool };
pub const Phase = enum { idle, streaming };
pub const ReplyPath = enum { demo, fx, daemon };

pub const Provider = protocol.ProviderId;

pub const Session = struct {
    id: u32 = 0,
    title_storage: [max_title]u8 = [_]u8{0} ** max_title,
    title_len: usize = 0,
    provider: Provider = .fx,
    busy: bool = false,
    untitled: bool = false,
    has_started: bool = false,
    /// Process-local. Catalog load leaves this false; hydrate sets it.
    detail_loaded: bool = true,
    /// Workspace path for `fx ask`. Empty means inherit the host process cwd.
    project_path_storage: [max_project_path]u8 = [_]u8{0} ** max_project_path,
    project_path_len: usize = 0,
    /// fx CLI session id from `fx ask --json`. Empty until the first mint.
    fx_session_id_storage: [max_fx_session_id]u8 = [_]u8{0} ** max_fx_session_id,
    fx_session_id_len: usize = 0,
    /// Gateway model id for `FX_MODEL`. Empty inherits fx's own default.
    model_storage: [max_fx_model]u8 = [_]u8{0} ** max_fx_model,
    model_len: usize = 0,
    /// Waku `runtime_mode` (ask | autoAcceptEdits | auto | fullAccess).
    access_mode_storage: [max_access_mode]u8 = [_]u8{0} ** max_access_mode,
    access_mode_len: usize = 0,

    pub fn title(self: *const Session) []const u8 {
        return self.title_storage[0..self.title_len];
    }

    pub fn projectPath(self: *const Session) []const u8 {
        return self.project_path_storage[0..self.project_path_len];
    }

    pub fn setProjectPath(self: *Session, path: []const u8) void {
        writeFixed(&self.project_path_storage, &self.project_path_len, path);
    }

    pub fn fxSessionId(self: *const Session) []const u8 {
        return self.fx_session_id_storage[0..self.fx_session_id_len];
    }

    pub fn setFxSessionId(self: *Session, id: []const u8) void {
        writeFixed(&self.fx_session_id_storage, &self.fx_session_id_len, id);
    }

    pub fn model(self: *const Session) []const u8 {
        return self.model_storage[0..self.model_len];
    }

    pub fn setModel(self: *Session, value: []const u8) void {
        writeFixed(&self.model_storage, &self.model_len, value);
    }

    pub fn accessMode(self: *const Session) []const u8 {
        return self.access_mode_storage[0..self.access_mode_len];
    }

    pub fn setAccessMode(self: *Session, value: []const u8) void {
        writeFixed(&self.access_mode_storage, &self.access_mode_len, value);
    }

    pub fn provider_label(self: *const Session) []const u8 {
        return self.provider.wireName();
    }

    /// A skeleton came from a stored row, so it has started even without turns.
    pub fn hasStarted(self: *const Session) bool {
        return !self.detail_loaded or self.has_started;
    }
};

pub const Turn = struct {
    id: u32 = 0,
    session_id: u32 = 0,
    role: Role = .user,
    body_storage: [max_body]u8 = [_]u8{0} ** max_body,
    body_len: usize = 0,

    pub fn text(self: *const Turn) []const u8 {
        return self.body_storage[0..self.body_len];
    }

    pub fn role_label(self: *const Turn) []const u8 {
        return switch (self.role) {
            .user => "You",
            .assistant => "Assistant",
            .tool => "Tool",
        };
    }
};

pub const SessionRow = struct {
    id: u32,
    title: []const u8,
    provider: []const u8,
    selected: bool,
};

pub const TurnRow = struct {
    id: u32,
    role_label: []const u8,
    text: []const u8,
};

/// Follow-up queued while that session is busy. Becomes its own turn after a
/// successful finish — not after Stop/Esc or a non-zero `fx ask` exit.
pub const QueuedMessage = struct {
    id: u32 = 0,
    session_id: u32 = 0,
    text_storage: [max_queued_text]u8 = [_]u8{0} ** max_queued_text,
    text_len: usize = 0,

    pub fn text(self: *const QueuedMessage) []const u8 {
        return self.text_storage[0..self.text_len];
    }
};

pub const Msg = union(enum) {
    new_session,
    select: u32,
    draft_edit: canvas.TextInputEvent,
    send,
    stop,
    tick: native_sdk.EffectTimer,
    fx_line: native_sdk.EffectLine,
    fx_exit: native_sdk.EffectExit,
    fx_probe_exit: native_sdk.EffectExit,

    pub const view_unbound = .{ "tick", "stop", "fx_line", "fx_exit", "fx_probe_exit" };
};

pub const Model = struct {
    session_store: [max_sessions]Session = [_]Session{.{}} ** max_sessions,
    session_count: u32 = 0,
    selected: u32 = 0,
    next_id: u32 = 1,
    turn_store: [max_turns]Turn = [_]Turn{.{}} ** max_turns,
    turn_count: u32 = 0,
    next_turn_id: u32 = 1,
    draft_buffer: canvas.TextBuffer(max_draft) = .{},
    mode: Mode = .demo,
    phase: Phase = .idle,
    stream_cursor: u32 = 0,
    stream_turn_id: u32 = 0,
    streaming_session: u32 = 0,
    queued_store: [max_queued]QueuedMessage = [_]QueuedMessage{.{}} ** max_queued,
    queued_count: u32 = 0,
    next_queued_id: u32 = 1,
    fx_available: bool = false,
    fx_path_storage: [max_fx_path]u8 = [_]u8{0} ** max_fx_path,
    fx_path_len: usize = 0,
    fx_probe_started: bool = false,
    fx_probe_index: u32 = 0,
    home_storage: [max_fx_path]u8 = [_]u8{0} ** max_fx_path,
    home_len: usize = 0,
    reply_path: ReplyPath = .demo,
    store_dir_storage: [max_store_dir]u8 = [_]u8{0} ** max_store_dir,
    store_dir_len: usize = 0,
    /// Same guard as waku-client: refuse catalog writes until a successful load.
    task_state_loaded: bool = false,
    store_io: ?std.Io = null,
    last_project_path_storage: [max_project_path]u8 = [_]u8{0} ** max_project_path,
    last_project_path_len: usize = 0,
    last_spawn_cwd_storage: [max_project_path]u8 = [_]u8{0} ** max_project_path,
    last_spawn_cwd_len: usize = 0,
    last_model_storage: [max_fx_model]u8 = [_]u8{0} ** max_fx_model,
    last_model_len: usize = 0,
    last_access_mode_storage: [max_access_mode]u8 = [_]u8{0} ** max_access_mode,
    last_access_mode_len: usize = 0,
    last_spawn_fx_model_storage: [max_fx_model]u8 = [_]u8{0} ** max_fx_model,
    last_spawn_fx_model_len: usize = 0,
    last_spawn_fx_permission_mode_storage: [max_access_mode]u8 = [_]u8{0} ** max_access_mode,
    last_spawn_fx_permission_mode_len: usize = 0,
    draft_image_path_storage: [max_project_path]u8 = [_]u8{0} ** max_project_path,
    draft_image_path_len: usize = 0,
    last_spawn_image_path_storage: [max_project_path]u8 = [_]u8{0} ** max_project_path,
    last_spawn_image_path_len: usize = 0,
    daemon_address_storage: [max_daemon_address]u8 = [_]u8{0} ** max_daemon_address,
    daemon_address_len: usize = 0,
    last_daemon_address_storage: [max_daemon_address]u8 = [_]u8{0} ** max_daemon_address,
    last_daemon_address_len: usize = 0,
    daemon_token_storage: [max_daemon_token]u8 = [_]u8{0} ** max_daemon_token,
    daemon_token_len: usize = 0,
    sidecar_path_storage: [max_sidecar_path]u8 = [_]u8{0} ** max_sidecar_path,
    sidecar_path_len: usize = 0,
    daemon_spawn_key: u64 = 0,
    next_daemon_key: u64 = daemon_proxy_key_first,

    pub const view_unbound = .{
        "session_store",
        "sessions",
        "session_count",
        "selected",
        "next_id",
        "turn_store",
        "turn_count",
        "next_turn_id",
        "draft_buffer",
        "mode",
        "phase",
        "stream_cursor",
        "stream_turn_id",
        "streaming_session",
        "queued_store",
        "queued_count",
        "next_queued_id",
        "is_streaming",
        "fx_available",
        "fx_path_storage",
        "fx_path_len",
        "fx_probe_started",
        "fx_probe_index",
        "home_storage",
        "home_len",
        "reply_path",
        "store_dir_storage",
        "store_dir_len",
        "task_state_loaded",
        "store_io",
        "last_project_path_storage",
        "last_project_path_len",
        "last_spawn_cwd_storage",
        "last_spawn_cwd_len",
        "last_model_storage",
        "last_model_len",
        "last_access_mode_storage",
        "last_access_mode_len",
        "last_spawn_fx_model_storage",
        "last_spawn_fx_model_len",
        "last_spawn_fx_permission_mode_storage",
        "last_spawn_fx_permission_mode_len",
        "draft_image_path_storage",
        "draft_image_path_len",
        "last_spawn_image_path_storage",
        "last_spawn_image_path_len",
        "lastProjectPath",
        "setLastProjectPath",
        "lastModel",
        "setLastModel",
        "lastAccessMode",
        "setLastAccessMode",
        "lastSpawnCwd",
        "setLastSpawnCwd",
        "lastSpawnFxModel",
        "setLastSpawnFxModel",
        "lastSpawnFxPermissionMode",
        "setLastSpawnFxPermissionMode",
        "draftImagePath",
        "setDraftImagePath",
        "lastSpawnImagePath",
        "setLastSpawnImagePath",
        "daemon_address_storage",
        "daemon_address_len",
        "last_daemon_address_storage",
        "last_daemon_address_len",
        "daemon_token_storage",
        "daemon_token_len",
        "sidecar_path_storage",
        "sidecar_path_len",
        "daemon_spawn_key",
        "next_daemon_key",
        "daemonAddress",
        "setDaemonAddress",
        "lastDaemonAddress",
        "setLastDaemonAddress",
        "daemonToken",
        "setDaemonToken",
        "sidecarPath",
        "setSidecarPath",
        "resolveSpawnImage",
        "resolveSpawnCwd",
        "fxPath",
        "setFxPath",
        "setHome",
        "homeDir",
        "storeDir",
        "setStoreDir",
    };

    pub fn draft(model: *const Model) []const u8 {
        return model.draft_buffer.text();
    }

    pub fn is_streaming(model: *const Model) bool {
        return model.phase == .streaming;
    }

    pub fn sessions(model: *const Model) []const Session {
        return model.session_store[0..model.session_count];
    }

    pub fn session_rows(model: *const Model, arena: std.mem.Allocator) []const SessionRow {
        const out = arena.alloc(SessionRow, model.session_count) catch return &.{};
        for (model.session_store[0..model.session_count], 0..) |*session, i| {
            out[i] = .{
                .id = session.id,
                .title = session.title(),
                .provider = session.provider_label(),
                .selected = session.id == model.selected,
            };
        }
        return out;
    }

    pub fn visible_turns(model: *const Model, arena: std.mem.Allocator) []const TurnRow {
        var count: usize = 0;
        for (model.turn_store[0..model.turn_count]) |turn| {
            if (turn.session_id == model.selected) count += 1;
        }
        const out = arena.alloc(TurnRow, count) catch return &.{};
        var i: usize = 0;
        for (model.turn_store[0..model.turn_count]) |*turn| {
            if (turn.session_id != model.selected) continue;
            out[i] = .{
                .id = turn.id,
                .role_label = turn.role_label(),
                .text = turn.text(),
            };
            i += 1;
        }
        return out[0..i];
    }

    pub fn selected_title(model: *const Model) []const u8 {
        if (model.activeSessionConst()) |session| return session.title();
        return "untitled";
    }

    pub fn selected_provider(model: *const Model) []const u8 {
        if (model.activeSessionConst()) |session| return session.provider_label();
        return Provider.default.wireName();
    }

    pub fn status_line(model: *const Model, arena: std.mem.Allocator) []const u8 {
        const path = switch (model.reply_path) {
            .demo => "demo",
            .fx => "fx",
            .daemon => "daemon",
        };
        return std.fmt.allocPrint(arena, "{d} sessions · {s} · {s}", .{
            model.session_count,
            path,
            model.selected_provider(),
        }) catch "demo";
    }

    pub fn empty_hint(model: *const Model) []const u8 {
        if (model.daemonAddress().len > 0) {
            return "Message the daemon sidecar. Send is one-shot hello/load/prompt over ws://{addr}/v1; missing address keeps `fx ask` / demo.";
        }
        if (model.fx_available) {
            return "Message fx. Send runs live `fx ask` and streams stdout. `fx acp` is stubbed.";
        }
        return "Message fx. Demo replies locally until the fx CLI is found; then Send runs live `fx ask`. `fx acp` is not wired.";
    }

    pub fn send_label(model: *const Model) []const u8 {
        return if (model.is_streaming()) "Stop" else "Send";
    }

    pub fn fxPath(model: *const Model) []const u8 {
        return model.fx_path_storage[0..model.fx_path_len];
    }

    pub fn setFxPath(model: *Model, path: []const u8) void {
        writeFixed(&model.fx_path_storage, &model.fx_path_len, path);
    }

    pub fn setHome(model: *Model, home: []const u8) void {
        writeFixed(&model.home_storage, &model.home_len, home);
    }

    pub fn homeDir(model: *const Model) []const u8 {
        return model.home_storage[0..model.home_len];
    }

    pub fn storeDir(model: *const Model) []const u8 {
        return model.store_dir_storage[0..model.store_dir_len];
    }

    pub fn setStoreDir(model: *Model, dir: []const u8) void {
        writeFixed(&model.store_dir_storage, &model.store_dir_len, dir);
    }

    pub fn lastProjectPath(model: *const Model) []const u8 {
        return model.last_project_path_storage[0..model.last_project_path_len];
    }

    pub fn setLastProjectPath(model: *Model, path: []const u8) void {
        writeFixed(&model.last_project_path_storage, &model.last_project_path_len, path);
    }

    pub fn lastSpawnCwd(model: *const Model) []const u8 {
        return model.last_spawn_cwd_storage[0..model.last_spawn_cwd_len];
    }

    pub fn setLastSpawnCwd(model: *Model, path: []const u8) void {
        writeFixed(&model.last_spawn_cwd_storage, &model.last_spawn_cwd_len, path);
    }

    pub fn lastModel(model: *const Model) []const u8 {
        return model.last_model_storage[0..model.last_model_len];
    }

    pub fn setLastModel(model: *Model, value: []const u8) void {
        writeFixed(&model.last_model_storage, &model.last_model_len, value);
    }

    pub fn lastAccessMode(model: *const Model) []const u8 {
        return model.last_access_mode_storage[0..model.last_access_mode_len];
    }

    pub fn setLastAccessMode(model: *Model, value: []const u8) void {
        writeFixed(&model.last_access_mode_storage, &model.last_access_mode_len, value);
    }

    pub fn lastSpawnFxModel(model: *const Model) []const u8 {
        return model.last_spawn_fx_model_storage[0..model.last_spawn_fx_model_len];
    }

    pub fn setLastSpawnFxModel(model: *Model, value: []const u8) void {
        writeFixed(&model.last_spawn_fx_model_storage, &model.last_spawn_fx_model_len, value);
    }

    pub fn lastSpawnFxPermissionMode(model: *const Model) []const u8 {
        return model.last_spawn_fx_permission_mode_storage[0..model.last_spawn_fx_permission_mode_len];
    }

    pub fn setLastSpawnFxPermissionMode(model: *Model, value: []const u8) void {
        writeFixed(&model.last_spawn_fx_permission_mode_storage, &model.last_spawn_fx_permission_mode_len, value);
    }

    pub fn draftImagePath(model: *const Model) []const u8 {
        return model.draft_image_path_storage[0..model.draft_image_path_len];
    }

    pub fn setDraftImagePath(model: *Model, path: []const u8) void {
        writeFixed(&model.draft_image_path_storage, &model.draft_image_path_len, path);
    }

    pub fn lastSpawnImagePath(model: *const Model) []const u8 {
        return model.last_spawn_image_path_storage[0..model.last_spawn_image_path_len];
    }

    pub fn setLastSpawnImagePath(model: *Model, path: []const u8) void {
        writeFixed(&model.last_spawn_image_path_storage, &model.last_spawn_image_path_len, path);
    }

    pub fn daemonAddress(model: *const Model) []const u8 {
        return model.daemon_address_storage[0..model.daemon_address_len];
    }

    pub fn setDaemonAddress(model: *Model, addr: []const u8) void {
        writeFixed(&model.daemon_address_storage, &model.daemon_address_len, addr);
        if (addr.len > 0) model.setLastDaemonAddress(addr);
    }

    pub fn lastDaemonAddress(model: *const Model) []const u8 {
        return model.last_daemon_address_storage[0..model.last_daemon_address_len];
    }

    pub fn setLastDaemonAddress(model: *Model, addr: []const u8) void {
        writeFixed(&model.last_daemon_address_storage, &model.last_daemon_address_len, addr);
    }

    pub fn daemonToken(model: *const Model) []const u8 {
        return model.daemon_token_storage[0..model.daemon_token_len];
    }

    pub fn setDaemonToken(model: *Model, token: []const u8) void {
        writeFixed(&model.daemon_token_storage, &model.daemon_token_len, token);
    }

    pub fn sidecarPath(model: *const Model) []const u8 {
        if (model.sidecar_path_len == 0) return "faku";
        return model.sidecar_path_storage[0..model.sidecar_path_len];
    }

    pub fn setSidecarPath(model: *Model, path: []const u8) void {
        writeFixed(&model.sidecar_path_storage, &model.sidecar_path_len, path);
    }

    /// `fx ask --image` path when the draft has a non-empty path that exists.
    /// Missing files omit the flag; Native spawn has no attachment/blob API.
    pub fn resolveSpawnImage(model: *const Model) []const u8 {
        const path = model.draftImagePath();
        if (path.len == 0) return "";
        const io = model.store_io orelse return "";
        if (!fileExists(io, path)) return "";
        return path;
    }

    /// Child cwd for `fx ask`: session project_path when it is non-empty and
    /// a real directory. Otherwise empty — Native spawn has no cwd field
    /// (0.9.3 SpawnOptions), so an empty result leaves the host process cwd.
    pub fn resolveSpawnCwd(model: *const Model, session: *const Session) []const u8 {
        const path = session.projectPath();
        if (path.len == 0) return "";
        const io = model.store_io orelse return "";
        if (!directoryExists(io, path)) return "";
        return path;
    }

    fn activeSession(model: *Model) ?*Session {
        return model.sessionById(model.selected);
    }

    fn activeSessionConst(model: *const Model) ?*const Session {
        for (model.session_store[0..model.session_count]) |*session| {
            if (session.id == model.selected) return session;
        }
        return null;
    }

    pub fn sessionById(model: *Model, id: u32) ?*Session {
        for (model.session_store[0..model.session_count]) |*session| {
            if (session.id == id) return session;
        }
        return null;
    }

    pub fn sessionByIdConst(model: *const Model, id: u32) ?*const Session {
        for (model.session_store[0..model.session_count]) |*session| {
            if (session.id == id) return session;
        }
        return null;
    }

    fn turnById(model: *Model, id: u32) ?*Turn {
        for (model.turn_store[0..model.turn_count]) |*turn| {
            if (turn.id == id) return turn;
        }
        return null;
    }

    pub fn addSession(model: *Model, title_text: []const u8, provider: Provider) u32 {
        if (model.session_count >= max_sessions) return 0;
        var session = Session{ .id = model.next_id, .provider = provider };
        writeFixed(&session.title_storage, &session.title_len, title_text);
        writeFixed(&session.project_path_storage, &session.project_path_len, model.lastProjectPath());
        writeFixed(&session.model_storage, &session.model_len, model.lastModel());
        const access = if (model.lastAccessMode().len > 0) model.lastAccessMode() else default_access_mode;
        writeFixed(&session.access_mode_storage, &session.access_mode_len, access);
        model.session_store[model.session_count] = session;
        model.session_count += 1;
        model.next_id += 1;
        return session.id;
    }

    pub fn appendTurn(model: *Model, session_id: u32, role: Role, body: []const u8) u32 {
        if (model.turn_count >= max_turns) return 0;
        var turn = Turn{ .id = model.next_turn_id, .session_id = session_id, .role = role };
        writeFixed(&turn.body_storage, &turn.body_len, body);
        model.turn_store[model.turn_count] = turn;
        model.turn_count += 1;
        model.next_turn_id += 1;
        if (model.sessionById(session_id)) |session| session.has_started = true;
        return turn.id;
    }

    pub fn clearSessions(model: *Model) void {
        model.session_count = 0;
        model.turn_count = 0;
        model.queued_count = 0;
        model.selected = 0;
        model.next_id = 1;
        model.next_turn_id = 1;
        model.next_queued_id = 1;
    }

    pub fn enqueue(model: *Model, session_id: u32, text: []const u8) u32 {
        if (model.sessionById(session_id) == null) return 0;
        if (model.queued_count >= max_queued) return 0;
        var item = QueuedMessage{ .id = model.next_queued_id, .session_id = session_id };
        writeFixed(&item.text_storage, &item.text_len, text);
        model.queued_store[model.queued_count] = item;
        model.queued_count += 1;
        model.next_queued_id += 1;
        return item.id;
    }

    pub fn queuedCount(model: *const Model, session_id: u32) u32 {
        var n: u32 = 0;
        for (model.queued_store[0..model.queued_count]) |item| {
            if (item.session_id == session_id) n += 1;
        }
        return n;
    }

    pub fn firstQueuedText(model: *const Model, session_id: u32) []const u8 {
        for (model.queued_store[0..model.queued_count]) |*item| {
            if (item.session_id == session_id) return item.text();
        }
        return "";
    }

    pub fn takeNextQueued(model: *Model, session_id: u32, dest: []u8) ?usize {
        var i: usize = 0;
        while (i < model.queued_count) : (i += 1) {
            if (model.queued_store[i].session_id != session_id) continue;
            const n = @min(dest.len, model.queued_store[i].text_len);
            @memcpy(dest[0..n], model.queued_store[i].text_storage[0..n]);
            var j = i;
            while (j + 1 < model.queued_count) : (j += 1) {
                model.queued_store[j] = model.queued_store[j + 1];
            }
            model.queued_count -= 1;
            return n;
        }
        return null;
    }

    pub fn restoreQueued(model: *Model, id: u32, session_id: u32, text: []const u8) void {
        if (model.queued_count >= max_queued) return;
        var item = QueuedMessage{ .id = id, .session_id = session_id };
        writeFixed(&item.text_storage, &item.text_len, text);
        model.queued_store[model.queued_count] = item;
        model.queued_count += 1;
        if (id >= model.next_queued_id) model.next_queued_id = id + 1;
    }

    pub fn dropQueuedForSession(model: *Model, session_id: u32) void {
        var kept: u32 = 0;
        for (model.queued_store[0..model.queued_count]) |item| {
            if (item.session_id == session_id) continue;
            model.queued_store[kept] = item;
            kept += 1;
        }
        model.queued_count = kept;
    }

    pub fn restoreSession(
        model: *Model,
        id: u32,
        title_text: []const u8,
        provider: Provider,
        untitled: bool,
        has_started: bool,
        project_path: []const u8,
        fx_session_id: []const u8,
        model_id: []const u8,
        access_mode: []const u8,
    ) void {
        if (model.session_count >= max_sessions) return;
        var session = Session{
            .id = id,
            .provider = provider,
            .untitled = untitled,
            .has_started = has_started,
            .detail_loaded = false,
        };
        writeFixed(&session.title_storage, &session.title_len, title_text);
        writeFixed(&session.project_path_storage, &session.project_path_len, project_path);
        writeFixed(&session.fx_session_id_storage, &session.fx_session_id_len, fx_session_id);
        writeFixed(&session.model_storage, &session.model_len, model_id);
        writeFixed(&session.access_mode_storage, &session.access_mode_len, access_mode);
        model.session_store[model.session_count] = session;
        model.session_count += 1;
        if (id >= model.next_id) model.next_id = id + 1;
    }

    pub fn restoreTurn(model: *Model, id: u32, session_id: u32, role: Role, body: []const u8) void {
        if (model.turn_count >= max_turns) return;
        var turn = Turn{ .id = id, .session_id = session_id, .role = role };
        writeFixed(&turn.body_storage, &turn.body_len, body);
        model.turn_store[model.turn_count] = turn;
        model.turn_count += 1;
        if (id >= model.next_turn_id) model.next_turn_id = id + 1;
    }

    pub fn dropTurnsForSession(model: *Model, session_id: u32) void {
        var kept: u32 = 0;
        for (model.turn_store[0..model.turn_count]) |turn| {
            if (turn.session_id == session_id) continue;
            model.turn_store[kept] = turn;
            kept += 1;
        }
        model.turn_count = kept;
    }

    pub fn dropSession(model: *Model, session_id: u32) void {
        model.dropTurnsForSession(session_id);
        model.dropQueuedForSession(session_id);
        var kept: u32 = 0;
        for (model.session_store[0..model.session_count]) |session| {
            if (session.id == session_id) continue;
            model.session_store[kept] = session;
            kept += 1;
        }
        model.session_count = kept;
        if (model.selected == session_id) {
            model.selected = if (model.session_count > 0) model.session_store[0].id else 0;
        }
    }

    fn appendToTurn(model: *Model, turn_id: u32, extra: []const u8) void {
        const turn = model.turnById(turn_id) orelse return;
        const room = turn.body_storage.len - turn.body_len;
        const take = @min(room, extra.len);
        if (take == 0) return;
        @memcpy(turn.body_storage[turn.body_len..][0..take], extra[0..take]);
        turn.body_len += take;
    }
};

fn writeFixed(storage: []u8, len: *usize, text: []const u8) void {
    const take = @min(storage.len, text.len);
    @memcpy(storage[0..take], text[0..take]);
    len.* = take;
}

fn directoryExists(io: std.Io, path: []const u8) bool {
    var dir = std.Io.Dir.cwd().openDir(io, path, .{}) catch return false;
    dir.close(io);
    return true;
}

fn fileExists(io: std.Io, path: []const u8) bool {
    var file = std.Io.Dir.cwd().openFile(io, path, .{}) catch return false;
    file.close(io);
    return true;
}

/// Native `SpawnOptions` (0.9.3) has no `cwd`. `std.process.spawn` does, but
/// Effects does not expose it. `cd` + `exec` is a real child cwd, not `PWD`.
pub const fx_ask_chdir_script = "cd -- \"$1\" && shift && exec \"$@\"";

pub const Effects = native_sdk.Effects(Msg);

pub fn update(model: *Model, msg: Msg, fx: *Effects) void {
    switch (msg) {
        .new_session => {
            store.persistDraftIfPossible(model);
            const id = model.addSession("untitled", .fx);
            if (id == 0) return;
            if (model.sessionById(id)) |session| session.untitled = true;
            model.selected = id;
            // Client-built; persist is a no-op until first real content.
            store.persistIfPossible(model, id);
            store.loadDraftIfPossible(model);
        },
        .select => |id| {
            if (model.sessionById(id) != null) {
                store.persistDraftIfPossible(model);
                model.selected = id;
                store.hydrateIfPossible(model, id);
                store.loadDraftIfPossible(model);
            }
        },
        .draft_edit => |edit| {
            model.draft_buffer.apply(edit);
            store.persistDraftIfPossible(model);
        },
        .send => handleSend(model, fx),
        .stop => stopStream(model, fx),
        .tick => |timer| {
            if (timer.outcome != .fired) return;
            tickStream(model, fx);
        },
        .fx_line => |line| handleFxLine(model, fx, line),
        .fx_exit => |exit| handleFxExit(model, fx, exit),
        .fx_probe_exit => |exit| handleFxProbeExit(model, fx, exit),
    }
}

/// Boot probe: `~/.local/bin/fx --help` then `fx --help` (PATH). Wired
/// through `.init_fx` so the first paint already has the spawn in flight.
pub fn initFx(model: *Model, fx: *Effects) void {
    startFxProbe(model, fx);
}

fn handleSend(model: *Model, fx: *Effects) void {
    if (!model.fx_probe_started) startFxProbe(model, fx);
    const text = std.mem.trim(u8, model.draft(), " \t\r\n");
    var key_buf: [store.max_draft_key]u8 = undefined;
    const draft_key = if (model.sessionById(model.selected)) |session|
        store.draftKey(session, &key_buf)
    else
        null;
    if (model.is_streaming()) {
        if (text.len == 0) {
            stopStream(model, fx);
            return;
        }
        if (model.enqueue(model.selected, text) != 0) {
            store.persistIfPossible(model, model.selected);
        }
        model.draft_buffer.clear();
        if (draft_key) |key| store.discardDraftIfPossible(model, key);
        model.setDraftImagePath("");
        return;
    }
    if (text.len == 0) return;
    startPrompt(model, fx, model.selected, text);
    model.draft_buffer.clear();
    if (draft_key) |key| store.discardDraftIfPossible(model, key);
    model.setDraftImagePath("");
}

fn startPrompt(model: *Model, fx: *Effects, session_id: u32, text: []const u8) void {
    const session = model.sessionById(session_id) orelse return;
    const hydrate = session.hasStarted();
    const titled = session.untitled;
    if (session.untitled) {
        writeFixed(&session.title_storage, &session.title_len, text);
        session.untitled = false;
    }
    _ = model.appendTurn(session.id, .user, text);
    const assistant_id = model.appendTurn(session.id, .assistant, "");
    if (titled) store.persistIfPossible(model, session.id);
    session.busy = true;
    model.phase = .streaming;
    model.stream_cursor = 0;
    model.stream_turn_id = assistant_id;
    model.streaming_session = session.id;
    if (model.daemonAddress().len > 0) {
        model.reply_path = .daemon;
        startDaemonProxy(model, fx, session, text, hydrate);
        return;
    }
    if (session.provider == .fx and model.fx_available and model.fxPath().len > 0) {
        model.reply_path = .fx;
        startFxAsk(model, fx, session, text);
        return;
    }
    model.reply_path = .demo;
    startDemoTimer(fx);
}

fn startDemoTimer(fx: *Effects) void {
    fx.startTimer(.{
        .key = stream_timer_key,
        .interval_ms = stream_interval_ms,
        .mode = .repeating,
        .on_fire = Effects.timerMsg(.tick),
    });
}

/// Waku `runtime_mode` → verified `FX_PERMISSION_MODE` (`ask`/`auto`/`yolo`).
/// Unknown strings persist but do not set the env.
pub fn fxPermissionMode(access_mode: []const u8) []const u8 {
    if (std.mem.eql(u8, access_mode, "ask")) return "ask";
    if (std.mem.eql(u8, access_mode, "autoAcceptEdits")) return "auto";
    if (std.mem.eql(u8, access_mode, "auto")) return "auto";
    if (std.mem.eql(u8, access_mode, "fullAccess")) return "yolo";
    if (std.mem.eql(u8, access_mode, "yolo")) return "yolo";
    return "";
}

fn startDaemonProxy(model: *Model, fx: *Effects, session: *const Session, prompt: []const u8, hydrate: bool) void {
    var id_buf: [36]u8 = undefined;
    const session_id = daemon_proxy.wireUuid(session.id, &id_buf);
    var stdin_buf: [4096]u8 = undefined;
    const stdin = daemon_proxy.writeTurnStdin(&stdin_buf, .{
        .token = model.daemonToken(),
        .session_id = session_id,
        .prompt = prompt,
        .load_task_state = hydrate,
    }) catch {
        model.reply_path = .demo;
        startDemoTimer(fx);
        return;
    };

    model.setLastDaemonAddress(model.daemonAddress());
    model.daemon_spawn_key = model.next_daemon_key;
    model.next_daemon_key += 1;

    fx.spawn(.{
        .key = model.daemon_spawn_key,
        .argv = &.{ model.sidecarPath(), daemon_proxy.SUBCOMMAND, model.daemonAddress() },
        .stdin = stdin,
        .max_line_bytes = daemon_line_bytes,
        .on_line = Effects.lineMsg(.fx_line),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
}

fn startFxAsk(model: *Model, fx: *Effects, session: *const Session, prompt: []const u8) void {
    const path = model.fxPath();
    const cwd = model.resolveSpawnCwd(session);
    const resume_id = session.fxSessionId();
    const model_id = session.model();
    const permission_mode = fxPermissionMode(session.accessMode());
    const image_path = model.resolveSpawnImage();
    model.setLastSpawnCwd(cwd);
    model.setLastSpawnFxModel(model_id);
    model.setLastSpawnFxPermissionMode(permission_mode);
    model.setLastSpawnImagePath(image_path);

    // Native SpawnOptions has no `env`. `/usr/bin/env KEY=val` sets the
    // child only — do not export on the Faku process.
    var model_assign: [max_fx_model + 16]u8 = undefined;
    var perm_assign: [max_access_mode + 24]u8 = undefined;
    const model_arg = if (model_id.len > 0)
        std.fmt.bufPrint(&model_assign, "FX_MODEL={s}", .{model_id}) catch ""
    else
        "";
    const perm_arg = if (permission_mode.len > 0)
        std.fmt.bufPrint(&perm_assign, "FX_PERMISSION_MODE={s}", .{permission_mode}) catch ""
    else
        "";

    var argv_buf: [20][]const u8 = undefined;
    var n: usize = 0;
    if (cwd.len > 0) {
        argv_buf[n] = "/bin/sh";
        n += 1;
        argv_buf[n] = "-c";
        n += 1;
        argv_buf[n] = fx_ask_chdir_script;
        n += 1;
        argv_buf[n] = "sh";
        n += 1;
        argv_buf[n] = cwd;
        n += 1;
    }
    if (model_arg.len > 0 or perm_arg.len > 0) {
        argv_buf[n] = fx_env_bin;
        n += 1;
        if (model_arg.len > 0) {
            argv_buf[n] = model_arg;
            n += 1;
        }
        if (perm_arg.len > 0) {
            argv_buf[n] = perm_arg;
            n += 1;
        }
    }
    argv_buf[n] = path;
    n += 1;
    argv_buf[n] = "ask";
    n += 1;
    argv_buf[n] = "--json";
    n += 1;
    if (resume_id.len > 0) {
        argv_buf[n] = "--resume";
        n += 1;
        argv_buf[n] = resume_id;
        n += 1;
    }
    if (image_path.len > 0) {
        argv_buf[n] = "--image";
        n += 1;
        argv_buf[n] = image_path;
        n += 1;
    }
    argv_buf[n] = "--";
    n += 1;
    argv_buf[n] = prompt;
    n += 1;

    fx.spawn(.{
        .key = fx_ask_key,
        .argv = argv_buf[0..n],
        .on_line = Effects.lineMsg(.fx_line),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
}

/// A stdout line that is a JSON object with a non-empty `session_id`.
/// Copies the id into `dest` and returns the copied slice.
pub fn takeFxAskSessionId(line: []const u8, dest: []u8) ?[]const u8 {
    const trimmed = std.mem.trim(u8, line, " \t\r\n");
    if (trimmed.len < 2 or trimmed[0] != '{') return null;
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const root = std.json.parseFromSliceLeaky(std.json.Value, arena_state.allocator(), trimmed, .{}) catch return null;
    const obj = switch (root) {
        .object => |o| o,
        else => return null,
    };
    const raw = obj.get("session_id") orelse return null;
    const id = switch (raw) {
        .string => |s| s,
        else => return null,
    };
    if (id.len == 0) return null;
    const take = @min(dest.len, id.len);
    @memcpy(dest[0..take], id[0..take]);
    return dest[0..take];
}

fn tickStream(model: *Model, fx: *Effects) void {
    if (model.phase != .streaming) return;
    model.stream_cursor += 1;
    const start = @min(demo_reply.len, (model.stream_cursor - 1) * stream_chunk_bytes);
    const end = @min(demo_reply.len, start + stream_chunk_bytes);
    if (end > start) model.appendToTurn(model.stream_turn_id, demo_reply[start..end]);
    if (model.stream_cursor >= demo_ticks_complete or end >= demo_reply.len) {
        finishStream(model, fx, true);
    }
}

fn finishStream(model: *Model, fx: *Effects, drain: bool) void {
    const finished_id = model.streaming_session;
    if (model.sessionById(finished_id)) |session| session.busy = false;
    model.phase = .idle;
    model.stream_cursor = 0;
    model.stream_turn_id = 0;
    model.streaming_session = 0;
    fx.cancelTimer(stream_timer_key);
    if (drain) {
        var copy: [max_queued_text]u8 = undefined;
        if (model.takeNextQueued(finished_id, &copy)) |n| {
            store.persistIfPossible(model, finished_id);
            startPrompt(model, fx, finished_id, copy[0..n]);
            return;
        }
    }
    store.persistIfPossible(model, finished_id);
}

fn stopStream(model: *Model, fx: *Effects) void {
    if (!model.is_streaming()) return;
    const finished_id = model.streaming_session;
    if (model.sessionById(finished_id)) |session| session.busy = false;
    model.phase = .idle;
    model.stream_cursor = 0;
    model.stream_turn_id = 0;
    model.streaming_session = 0;
    fx.cancelTimer(stream_timer_key);
    fx.cancel(fx_ask_key);
    if (model.daemon_spawn_key != 0) fx.cancel(model.daemon_spawn_key);
    store.persistIfPossible(model, finished_id);
}

fn handleFxLine(model: *Model, fx: *Effects, line: native_sdk.EffectLine) void {
    if (model.phase != .streaming) return;
    if (line.key == model.daemon_spawn_key and model.daemon_spawn_key != 0) {
        handleDaemonLine(model, fx, line);
        return;
    }
    if (line.key != fx_ask_key) return;
    const keep = line.line[0..@min(line.line.len, max_line_keep)];
    var id_buf: [max_fx_session_id]u8 = undefined;
    if (takeFxAskSessionId(keep, &id_buf)) |session_id| {
        if (model.sessionById(model.streaming_session)) |session| {
            session.setFxSessionId(session_id);
            store.persistIfPossible(model, session.id);
        }
        return;
    }
    if (model.turnById(model.stream_turn_id)) |turn| {
        if (turn.body_len > 0) model.appendToTurn(model.stream_turn_id, "\n");
    }
    model.appendToTurn(model.stream_turn_id, keep);
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
                finishStream(model, fx, parsed.turn_success);
            } else if (parsed.event_kind == .@"error") {
                finishStream(model, fx, false);
            }
        },
        .rejected => finishStream(model, fx, false),
        else => {},
    }
}

fn handleFxExit(model: *Model, fx: *Effects, exit: native_sdk.EffectExit) void {
    const daemon = model.daemon_spawn_key != 0 and exit.key == model.daemon_spawn_key;
    if (exit.key != fx_ask_key and !daemon) return;
    if (model.phase != .streaming) return;
    const success = exit.reason == .exited and exit.code == 0;
    finishStream(model, fx, success);
}

fn startFxProbe(model: *Model, fx: *Effects) void {
    if (model.fx_probe_started) return;
    model.fx_probe_started = true;
    model.fx_probe_index = 0;
    spawnFxProbe(model, fx);
}

fn spawnFxProbe(model: *Model, fx: *Effects) void {
    while (model.fx_probe_index < 2) {
        var path_buf: [max_fx_path]u8 = undefined;
        if (fxProbePath(model, model.fx_probe_index, &path_buf)) |path| {
            model.setFxPath(path);
            fx.spawn(.{
                .key = fx_probe_key,
                .argv = &.{ model.fxPath(), "--help" },
                .output = .collect,
                .on_exit = Effects.exitMsg(.fx_probe_exit),
            });
            return;
        }
        model.fx_probe_index += 1;
    }
    model.fx_available = false;
    model.fx_path_len = 0;
}

fn handleFxProbeExit(model: *Model, fx: *Effects, exit: native_sdk.EffectExit) void {
    if (exit.key != fx_probe_key) return;
    if (exit.reason == .exited and exit.code == 0) {
        model.fx_available = true;
        return;
    }
    model.fx_available = false;
    model.fx_path_len = 0;
    model.fx_probe_index += 1;
    spawnFxProbe(model, fx);
}

fn fxProbePath(model: *const Model, index: u32, buf: *[max_fx_path]u8) ?[]const u8 {
    switch (index) {
        0 => {
            const home = model.homeDir();
            if (home.len == 0) return null;
            const suffix = "/.local/bin/fx";
            if (home.len + suffix.len > buf.len) return null;
            @memcpy(buf[0..home.len], home);
            @memcpy(buf[home.len..][0..suffix.len], suffix);
            return buf[0 .. home.len + suffix.len];
        },
        1 => {
            const name = "fx";
            @memcpy(buf[0..name.len], name);
            return buf[0..name.len];
        },
        else => return null,
    }
}

pub fn onKey(keyboard: canvas.WidgetKeyboardEvent) ?Msg {
    if (std.ascii.eqlIgnoreCase(keyboard.key, "escape")) return .stop;
    return null;
}

pub const AppUi = canvas.Ui(Msg);
pub const app_markup = @embedFile("app.native");

const FakuApp = native_sdk.UiApp(Model, Msg);

pub fn initialModel() Model {
    var model = Model{};
    const port = model.addSession("port waku to zig", .fx);
    _ = model.appendTurn(port, .user, "replace the GPUI desktop with a Native SDK Zig shell");
    _ = model.appendTurn(port, .assistant, "fx-first demo: sidebar, transcript, composer. Send runs `fx ask` when the CLI is installed.");

    const auth = model.addSession("fix auth listener", .claude);
    _ = model.appendTurn(auth, .user, "the auth listener drops the first event after reconnect");
    _ = model.appendTurn(auth, .assistant, "I will inspect the reconnect path and replay the last event.");
    _ = model.appendTurn(auth, .tool, "read src/auth/listener.ts");
    _ = model.appendTurn(auth, .assistant, "The handler unsubscribes before the replay buffer is flushed.");

    model.selected = port;
    if (model.sessionById(port)) |session| {
        session.has_started = true;
        session.detail_loaded = true;
    }
    if (model.sessionById(auth)) |session| {
        session.has_started = true;
        session.detail_loaded = true;
    }
    return model;
}

pub fn main(init: std.process.Init) !void {
    if (try daemon_proxy.maybeRun(init)) return;
    _ = protocol.FX_ACP_ARGV;
    _ = acp.PROTOCOL_VERSION;
    const app_state = try FakuApp.create(std.heap.page_allocator, .{
        .name = "faku",
        .scene = shell_scene,
        .canvas_label = canvas_label,
        .update_fx = update,
        .init_fx = initFx,
        .on_key = onKey,
        .markup = .{ .source = app_markup, .watch_path = "src/app.native", .io = init.io },
    });
    defer app_state.destroy();
    app_state.model = initialModel();
    if (init.environ_map.get("HOME")) |home| {
        app_state.model.setHome(home);
        store.bindDefaultDir(&app_state.model, home, init.environ_map.get("XDG_DATA_HOME"));
    }
    bindDaemonEnv(&app_state.model, init);
    _ = store.boot(&app_state.model, std.heap.page_allocator, init.io);
    if (init.environ_map.get(protocol.DAEMON_ADDRESS_ENV)) |addr| {
        app_state.model.setDaemonAddress(addr);
    }

    try runner.runWithOptions(app_state.app(), .{
        .app_name = "faku",
        .window_title = "Faku",
        .bundle_id = "com.faku.app",
        .icon_path = "assets/icon.png",
        .default_frame = geometry.RectF.init(0, 0, window_width, window_height),
        .js_window_api = false,
        .security = .{
            .permissions = &app_permissions,
            .navigation = .{ .allowed_origins = &.{ "zero://inline", "zero://app" } },
        },
    }, init);
}

fn bindDaemonEnv(model: *Model, init: std.process.Init) void {
    if (init.environ_map.get(protocol.DAEMON_ADDRESS_ENV)) |addr| {
        model.setDaemonAddress(addr);
    }
    if (init.environ_map.get(protocol.DAEMON_TOKEN_ENV)) |token| {
        model.setDaemonToken(token);
    }
    const args = init.minimal.args.toSlice(init.arena.allocator()) catch return;
    if (args.len > 0 and args[0].len > 0) model.setSidecarPath(args[0]);
}

test {
    _ = @import("tests.zig");
    _ = @import("protocol.zig");
    _ = @import("acp.zig");
    _ = @import("store.zig");
    _ = @import("daemon_proxy.zig");
}
