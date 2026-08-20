//! Faku: Native SDK desktop for a Waku-protocol compatible coding-agent shell.
//!
//! First-party provider is Vercel `fx` (https://fx.sh). Send on an `.fx`
//! session runs `fx ask <prompt>` when the CLI is installed (streamed
//! stdout lines). Missing binary falls back to the demo timer so tests
//! stay green. ACP JSON-RPC helpers live in acp.zig; live `fx acp` waits
//! on a stdin-write effect and is not spawned.

const std = @import("std");
const runner = @import("runner");
const native_sdk = @import("native_sdk");
const protocol = @import("protocol.zig");
const acp = @import("acp.zig");

pub const panic = std.debug.FullPanic(native_sdk.debug.capturePanic);

const canvas = native_sdk.canvas;
const geometry = native_sdk.geometry;
const Color = canvas.Color;

const canvas_label = "main-canvas";
pub const window_width: f32 = 1380;
pub const window_height: f32 = 880;
pub const window_min_width: f32 = 980;
pub const window_min_height: f32 = 680;
const sidebar_default_width: f32 = 252;
const sidebar_min_width: f32 = 180;
const sidebar_max_width: f32 = 420;
const default_sidebar_split: f32 = sidebar_default_width / window_width;

const max_sessions = 16;
const max_turns = 128;
const max_title = 64;
const max_body = 4096;
const max_draft = 512;
const max_queue = 1024;
const max_fx_path = 256;
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
pub const stream_interval_ms: u64 = 90;
const stream_chunk_bytes: usize = 8;
const demo_ticks_complete: u32 = 12;
const demo_reply = "fx here (demo). The fx CLI was not found, so this is a local timer stream. Install fx and Send runs `fx ask`.";

pub const Mode = enum { demo, daemon };
pub const Role = enum { user, assistant, tool };
pub const Phase = enum { idle, streaming };
pub const ReplyPath = enum { demo, fx };

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
    is_user: bool,
    is_tool: bool,
};

pub const Msg = union(enum) {
    new_session,
    select: u32,
    draft_edit: canvas.TextInputEvent,
    send,
    stop,
    clear_queue,
    sidebar_resized: f32,
    transcript_scrolled: canvas.ScrollState,
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
    queued_storage: [max_queue]u8 = [_]u8{0} ** max_queue,
    queued_len: usize = 0,
    sidebar_split: f32 = default_sidebar_split,
    transcript_scroll: f32 = 0,
    fx_available: bool = false,
    fx_path_storage: [max_fx_path]u8 = [_]u8{0} ** max_fx_path,
    fx_path_len: usize = 0,
    fx_probe_started: bool = false,
    fx_probe_index: u32 = 0,
    home_storage: [max_fx_path]u8 = [_]u8{0} ** max_fx_path,
    home_len: usize = 0,
    reply_path: ReplyPath = .demo,

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
        "fx_available",
        "fx_path_storage",
        "fx_path_len",
        "fx_probe_started",
        "fx_probe_index",
        "home_storage",
        "home_len",
        "reply_path",
        "fxPath",
        "setFxPath",
        "setHome",
        "homeDir",
        "selected_title",
        "empty_hint",
        "has_turns",
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
                .title = sessionDisplayTitle(session),
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
                .is_user = turn.role == .user,
                .is_tool = turn.role == .tool,
            };
            i += 1;
        }
        return out[0..i];
    }

    pub fn selected_title(model: *const Model) []const u8 {
        if (model.activeSessionConst()) |session| return session.title();
        return "untitled";
    }

    pub fn header_title(model: *const Model) []const u8 {
        if (model.activeSessionConst()) |session| {
            if (session.untitled) return "New task";
            return session.title();
        }
        return "New task";
    }

    pub fn selected_provider(model: *const Model) []const u8 {
        if (model.activeSessionConst()) |session| return session.provider_label();
        return Provider.default.wireName();
    }

    pub fn status_line(model: *const Model, arena: std.mem.Allocator) []const u8 {
        const path = switch (model.reply_path) {
            .demo => "demo",
            .fx => "fx",
        };
        if (model.queued_len > 0) {
            return std.fmt.allocPrint(arena, "{d} sessions · {s} · {s} · queued", .{
                model.session_count,
                path,
                model.selected_provider(),
            }) catch "demo";
        }
        return std.fmt.allocPrint(arena, "{d} sessions · {s} · {s}", .{
            model.session_count,
            path,
            model.selected_provider(),
        }) catch "demo";
    }

    pub fn has_turns(model: *const Model) bool {
        for (model.turn_store[0..model.turn_count]) |turn| {
            if (turn.session_id == model.selected) return true;
        }
        return false;
    }

    pub fn has_queued(model: *const Model) bool {
        return model.queued_len > 0;
    }

    pub fn queued_text(model: *const Model) []const u8 {
        return model.queued_storage[0..model.queued_len];
    }

    pub fn composer_placeholder(_: *const Model) []const u8 {
        return "Do anything...";
    }

    pub fn empty_hint(_: *const Model) []const u8 {
        return "Send runs fx ask when the CLI is found. Demo replies until then.";
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

fn sessionDisplayTitle(session: *const Session) []const u8 {
    if (session.untitled or std.mem.eql(u8, session.title(), "untitled")) return "New task";
    return session.title();
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
        .clear_queue => model.queued_len = 0,
        .sidebar_resized => |fraction| model.sidebar_split = clampSidebarSplit(fraction),
        .transcript_scrolled => |scroll| model.transcript_scroll = scroll.offset_y,
        .tick => |timer| {
            if (timer.outcome != .fired) return;
            tickStream(model, fx);
        },
        .fx_line => |line| handleFxLine(model, line),
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
    if (session.provider == .fx and model.fx_available and model.fxPath().len > 0) {
        model.reply_path = .fx;
        startFxAsk(model, fx, text);
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

fn startFxAsk(model: *Model, fx: *Effects, prompt: []const u8) void {
    const path = model.fxPath();
    if (promptStartsLikeFlag(prompt)) {
        fx.spawn(.{
            .key = fx_ask_key,
            .argv = &.{ path, "ask", "--", prompt },
            .on_line = Effects.lineMsg(.fx_line),
            .on_exit = Effects.exitMsg(.fx_exit),
        });
        return;
    }
    fx.spawn(.{
        .key = fx_ask_key,
        .argv = &.{ path, "ask", prompt },
        .on_line = Effects.lineMsg(.fx_line),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
}

fn promptStartsLikeFlag(prompt: []const u8) bool {
    return prompt.len > 0 and prompt[0] == '-';
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
    fx.cancel(fx_ask_key);
}

fn handleFxLine(model: *Model, line: native_sdk.EffectLine) void {
    if (model.phase != .streaming) return;
    if (line.key != fx_ask_key) return;
    const keep = line.line[0..@min(line.line.len, max_line_keep)];
    if (model.turnById(model.stream_turn_id)) |turn| {
        if (turn.body_len > 0) model.appendToTurn(model.stream_turn_id, "\n");
    }
    model.appendToTurn(model.stream_turn_id, keep);
}

fn handleFxExit(model: *Model, fx: *Effects, exit: native_sdk.EffectExit) void {
    if (exit.key != fx_ask_key) return;
    if (model.phase != .streaming) return;
    finishStream(model, fx);
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
    if (keyboard.modifiers.hasNavigationModifier() and std.ascii.eqlIgnoreCase(keyboard.key, "n")) {
        return .new_session;
    }
    return null;
}

pub const AppUi = canvas.Ui(Msg);
pub const app_markup = @embedFile("app.native");

const FakuApp = native_sdk.UiApp(Model, Msg);

fn clampSidebarSplit(value: f32) f32 {
    const min_split = sidebar_min_width / window_width;
    const max_split = sidebar_max_width / window_width;
    return @max(min_split, @min(max_split, value));
}

/// Geist light register, with Waku 0.1.9 Theme::light hex mapped onto
/// Native token slots. Markup cannot take raw hex. Coral is brand/caret
/// only (focus ring); Native accent paints primary buttons, so that
/// slot is Waku inverse graphite.
fn themeTokens(_: *const Model) canvas.DesignTokens {
    return canvas.DesignTokens.themeWithOverrides(.{
        .pack = .geist,
        .color_scheme = .light,
    }, .{
        .colors = .{
            .background = Color.rgb8(0xF6, 0xF5, 0xF6),
            .surface = Color.rgb8(0xFF, 0xFF, 0xFF),
            .surface_subtle = Color.rgb8(0xF3, 0xF3, 0xF3),
            .text = Color.rgb8(0x24, 0x24, 0x24),
            .text_muted = Color.rgb8(0x66, 0x66, 0x66),
            .accent = Color.rgb8(0x20, 0x22, 0x27),
            .accent_text = Color.rgb8(0xF8, 0xF8, 0xF9),
            .border = Color.rgba8(0x1C, 0x1E, 0x22, 20),
            .focus_ring = Color.rgb8(0xC8, 0x5F, 0x44),
        },
    });
}

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
    return model;
}

pub fn main(init: std.process.Init) !void {
    _ = protocol.FX_ACP_ARGV;
    _ = acp.PROTOCOL_VERSION;
    const app_state = try FakuApp.create(std.heap.page_allocator, .{
        .name = "faku",
        .scene = shell_scene,
        .canvas_label = canvas_label,
        .update_fx = update,
        .init_fx = initFx,
        .on_key = onKey,
        .tokens_fn = themeTokens,
        .markup = .{ .source = app_markup, .watch_path = "src/app.native", .io = init.io },
    });
    defer app_state.destroy();
    app_state.model = initialModel();
    if (init.environ_map.get("HOME")) |home| app_state.model.setHome(home);

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
    _ = @import("acp.zig");
}
