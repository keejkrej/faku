//! Faku: Native SDK desktop for a Waku-protocol compatible coding-agent shell.
//!
//! Demo mode works without a daemon: mock sessions, a streamed fake
//! reply, and the Geist-themed window. First-party provider is Vercel
//! `fx` (https://fx.sh) — Waku does not ship this. Daemon / ACP types
//! live in protocol.zig; the live socket and `fx acp` spawn are not
//! wired yet.

const std = @import("std");
const runner = @import("runner");
const native_sdk = @import("native_sdk");
const protocol = @import("protocol.zig");

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
const max_body = 512;
const max_draft = 512;
const max_queue = 1024;

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
pub const stream_interval_ms: u64 = 90;
const stream_chunk_bytes: usize = 8;
const demo_ticks_complete: u32 = 12;
const demo_reply = "fx here (demo). No daemon and no `fx acp` spawn yet — this is a local timer stream. I would take the prompt over ACP stdio next.";

pub const Mode = enum { demo, daemon };
pub const Role = enum { user, assistant, tool };
pub const Phase = enum { idle, streaming };

pub const Provider = protocol.ProviderId;

pub const Session = struct {
    id: u32 = 0,
    title_storage: [max_title]u8 = [_]u8{0} ** max_title,
    title_len: usize = 0,
    provider: Provider = .fx,
    busy: bool = false,
    untitled: bool = false,

    pub fn title(self: *const Session) []const u8 {
        return self.title_storage[0..self.title_len];
    }

    pub fn provider_label(self: *const Session) []const u8 {
        return self.provider.wireName();
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

pub const Msg = union(enum) {
    new_session,
    select: u32,
    draft_edit: canvas.TextInputEvent,
    send,
    stop,
    tick: native_sdk.EffectTimer,

    pub const view_unbound = .{ "tick", "stop" };
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
    queued_storage: [max_queue]u8 = [_]u8{0} ** max_queue,
    queued_len: usize = 0,

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
        "queued_storage",
        "queued_len",
        "is_streaming",
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
        const mode = switch (model.mode) {
            .demo => "demo",
            .daemon => "daemon",
        };
        return std.fmt.allocPrint(arena, "{d} sessions · {s} · {s}", .{
            model.session_count,
            mode,
            model.selected_provider(),
        }) catch "demo";
    }

    pub fn send_label(model: *const Model) []const u8 {
        return if (model.is_streaming()) "Stop" else "Send";
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

    fn sessionById(model: *Model, id: u32) ?*Session {
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
        return turn.id;
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

pub const Effects = native_sdk.Effects(Msg);

pub fn update(model: *Model, msg: Msg, fx: *Effects) void {
    switch (msg) {
        .new_session => {
            const id = model.addSession("untitled", .fx);
            if (id == 0) return;
            if (model.sessionById(id)) |session| session.untitled = true;
            model.selected = id;
        },
        .select => |id| {
            if (model.sessionById(id) != null) model.selected = id;
        },
        .draft_edit => |edit| model.draft_buffer.apply(edit),
        .send => handleSend(model, fx),
        .stop => stopStream(model, fx),
        .tick => |timer| {
            if (timer.outcome != .fired) return;
            tickStream(model, fx);
        },
    }
}

fn handleSend(model: *Model, fx: *Effects) void {
    const text = std.mem.trim(u8, model.draft(), " \t\r\n");
    if (model.is_streaming()) {
        if (text.len == 0) {
            stopStream(model, fx);
            return;
        }
        writeFixed(&model.queued_storage, &model.queued_len, text);
        model.draft_buffer.clear();
        return;
    }
    if (text.len == 0) return;
    startPrompt(model, fx, text);
    model.draft_buffer.clear();
}

fn startPrompt(model: *Model, fx: *Effects, text: []const u8) void {
    const session = model.activeSession() orelse return;
    if (session.untitled) {
        writeFixed(&session.title_storage, &session.title_len, text);
        session.untitled = false;
    }
    _ = model.appendTurn(session.id, .user, text);
    const assistant_id = model.appendTurn(session.id, .assistant, "");
    session.busy = true;
    model.phase = .streaming;
    model.stream_cursor = 0;
    model.stream_turn_id = assistant_id;
    model.streaming_session = session.id;
    fx.startTimer(.{
        .key = stream_timer_key,
        .interval_ms = stream_interval_ms,
        .mode = .repeating,
        .on_fire = Effects.timerMsg(.tick),
    });
}

fn tickStream(model: *Model, fx: *Effects) void {
    if (model.phase != .streaming) return;
    model.stream_cursor += 1;
    const start = @min(demo_reply.len, (model.stream_cursor - 1) * stream_chunk_bytes);
    const end = @min(demo_reply.len, start + stream_chunk_bytes);
    if (end > start) model.appendToTurn(model.stream_turn_id, demo_reply[start..end]);
    if (model.stream_cursor >= demo_ticks_complete or end >= demo_reply.len) {
        finishStream(model, fx);
    }
}

fn finishStream(model: *Model, fx: *Effects) void {
    if (model.sessionById(model.streaming_session)) |session| session.busy = false;
    model.phase = .idle;
    model.stream_cursor = 0;
    model.stream_turn_id = 0;
    model.streaming_session = 0;
    fx.cancelTimer(stream_timer_key);
    if (model.queued_len == 0) return;
    const queued = model.queued_storage[0..model.queued_len];
    var copy: [max_queue]u8 = undefined;
    @memcpy(copy[0..queued.len], queued);
    const n = queued.len;
    model.queued_len = 0;
    startPrompt(model, fx, copy[0..n]);
}

fn stopStream(model: *Model, fx: *Effects) void {
    if (!model.is_streaming()) return;
    if (model.sessionById(model.streaming_session)) |session| session.busy = false;
    model.phase = .idle;
    model.stream_cursor = 0;
    model.stream_turn_id = 0;
    model.streaming_session = 0;
    fx.cancelTimer(stream_timer_key);
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
    _ = model.appendTurn(port, .assistant, "fx-first demo: sidebar, transcript, composer. Live `fx acp` comes later.");

    const auth = model.addSession("fix auth listener", .claude);
    _ = model.appendTurn(auth, .user, "the auth listener drops the first event after reconnect");
    _ = model.appendTurn(auth, .assistant, "I will inspect the reconnect path and replay the last event.");
    _ = model.appendTurn(auth, .tool, "read src/auth/listener.ts");
    _ = model.appendTurn(auth, .assistant, "The handler unsubscribes before the replay buffer is flushed.");

    model.selected = port;
    return model;
}

pub fn main(init: std.process.Init) !void {
    _ = protocol.FX_ACP_ARGV;
    const app_state = try FakuApp.create(std.heap.page_allocator, .{
        .name = "faku",
        .scene = shell_scene,
        .canvas_label = canvas_label,
        .update_fx = update,
        .on_key = onKey,
        .markup = .{ .source = app_markup, .watch_path = "src/app.native", .io = init.io },
    });
    defer app_state.destroy();
    app_state.model = initialModel();

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

test {
    _ = @import("tests.zig");
    _ = @import("protocol.zig");
}
