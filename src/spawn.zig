//! Prompt-start and provider-spawn helpers.
//!
//! `startPrompt` path selection (daemon / fx acp / fx ask / probed
//! ACP `acp` via acp-proxy / demo), StartOptions mapping, and
//! `takeFxAskSessionId` live here. Stream lifecycle lives in
//! `stream.zig`. Line handlers live in `lines.zig`.
//!
//! Non-fx live Send this cut: `ProviderId.speaksBareAcp` (cursor,
//! opencode) when `providers.isAvailable`. Same one-shot `faku acp-proxy
//! -- {binary} acp` as fx. `reply_path` stays `.fx` so ACP stream
//! parsing (`fx_spawn_acp` / `fx_line` / `fx_exit`) is unchanged.
//! Image attach on non-fx stays demo. Claude/Codex/Amp/Pi/Grok stay
//! demo.

const std = @import("std");
const main = @import("main.zig");
const protocol = @import("protocol.zig");
const acp = @import("acp.zig");
const store = @import("store.zig");
const daemon_proxy = @import("daemon_proxy.zig");
const acp_proxy = @import("acp_proxy.zig");
const composer = @import("composer.zig");
const session_fork = @import("fork.zig");
const providers = @import("providers.zig");

const Model = main.Model;
const Effects = main.Effects;
const Session = main.Session;
const writeFixed = main.writeFixed;
const fxPermissionMode = composer.fxPermissionMode;
const stream_timer_key = main.stream_timer_key;
const stream_interval_ms = main.stream_interval_ms;
const fx_ask_key = main.fx_ask_key;
const daemon_line_bytes = main.daemon_line_bytes;
const max_fx_model = main.max_fx_model;
const max_access_mode = main.max_access_mode;
const default_access_mode = main.default_access_mode;
const default_interaction_mode = main.default_interaction_mode;
const fx_env_bin = main.fx_env_bin;
const fx_ask_chdir_script = main.fx_ask_chdir_script;

pub fn startPrompt(model: *Model, fx: *Effects, session_id: u32, text: []const u8) void {
    const session = model.sessionById(session_id) orelse return;
    session_fork.recordRewindRefIfPossible(model, session.id);
    const titled = session.untitled;
    if (session.untitled) {
        writeFixed(&session.title_storage, &session.title_len, text);
        session.untitled = false;
    }
    _ = model.appendTurn(session.id, .user, text);
    const assistant_id = model.appendTurn(session.id, .assistant, "");
    if (titled) store.persistIfPossible(model, session.id, fx);
    session.busy = true;
    model.phase = .streaming;
    model.stream_cursor = 0;
    model.stream_turn_id = assistant_id;
    model.streaming_session = session.id;
    if (model.daemonAddress().len > 0) {
        model.reply_path = .daemon;
        startDaemonProxy(model, fx, session, text);
        return;
    }
    if (session.provider == .fx and model.fx_available and model.fxPath().len > 0) {
        model.reply_path = .fx;
        const image_path = model.resolveSpawnImage();
        if (image_path.len > 0) {
            startFxAsk(model, fx, session, text);
            return;
        }
        if (!startFxAcp(model, fx, session, text)) {
            startFxAsk(model, fx, session, text);
        }
        return;
    }
    if (session.provider.speaksBareAcp() and providers.isAvailable(model, session.provider)) {
        // ACP has no image blocks this cut; non-fx image attach stays demo.
        if (model.resolveSpawnImage().len == 0) {
            const binary = providers.binaryFor(model, session.provider);
            // Reuse fx spawn keys / fx_line / fx_exit / reply_path=.fx
            // so handleAcpLine keeps working. Not a new ReplyPath alias.
            model.reply_path = .fx;
            if (startAcpProxy(model, fx, session, binary, text)) return;
        }
    }
    model.reply_path = .demo;
    startDemoTimer(fx);
}

pub fn startDemoTimer(fx: *Effects) void {
    fx.startTimer(.{
        .key = stream_timer_key,
        .interval_ms = stream_interval_ms,
        .mode = .repeating,
        .on_fire = Effects.timerMsg(.tick),
    });
}

/// Map stored session fields onto verified `StartOptions`. Empty
/// `project_path` becomes `"."`. Empty model is omitted on the wire.
/// `computer_use_enabled` is not stored here and stays false.
pub fn startOptionsFromSession(session: *const Session) protocol.StartOptions {
    return .{
        .provider = session.provider.wireName(),
        .binary = session.provider.defaultBinary(),
        .cwd = if (session.projectPath().len > 0) session.projectPath() else ".",
        .mode = if (session.accessMode().len > 0) session.accessMode() else default_access_mode,
        .interaction_mode = if (session.interactionMode().len > 0) session.interactionMode() else default_interaction_mode,
        .model = if (session.model().len > 0) session.model() else null,
        .reasoning_effort = if (session.reasoningEffort().len > 0) session.reasoningEffort() else null,
        .computer_use_enabled = false,
    };
}

pub fn startDaemonProxy(model: *Model, fx: *Effects, session: *const Session, prompt: []const u8) void {
    var id_buf: [36]u8 = undefined;
    const session_id = daemon_proxy.wireUuid(session.id, &id_buf);
    const has_runtime = protocol.isUsableRuntimeId(session.runtimeId());
    const runtime_id = if (has_runtime) session.runtimeId() else protocol.NIL_UUID;
    const start = if (has_runtime) null else startOptionsFromSession(session);
    var stdin_buf: [4096]u8 = undefined;
    const stdin = daemon_proxy.writeTurnStdin(&stdin_buf, .{
        .token = model.daemonToken(),
        .session_id = session_id,
        .runtime_id = runtime_id,
        .prompt = prompt,
        .start = start,
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

pub fn allocateFxSpawnKey(model: *Model) u64 {
    const key = if (model.fx_spawn_live) blk: {
        const k = model.next_fx_key;
        model.next_fx_key = k + 1;
        break :blk k;
    } else fx_ask_key;
    model.fx_spawn_key = key;
    model.fx_spawn_live = true;
    return key;
}

pub fn startFxAcp(model: *Model, fx: *Effects, session: *const Session, prompt: []const u8) bool {
    return startAcpProxy(model, fx, session, model.fxPath(), prompt);
}

/// One-shot `faku acp-proxy -- {binary} acp` with the existing ACP
/// stdin batch. fx still prefixes `FX_MODEL` / `FX_PERMISSION_MODE`
/// via `/usr/bin/env` (same as before). Permission also rides
/// `session/set_mode` in the batch. Empty binary is a no-op.
pub fn startAcpProxy(model: *Model, fx: *Effects, session: *const Session, binary: []const u8, prompt: []const u8) bool {
    if (binary.len == 0) return false;
    const cwd = model.resolveAcpCwd(session);
    const resume_id = session.fxSessionId();
    const model_id = session.model();
    const permission_mode = fxPermissionMode(session.accessMode());
    model.setLastSpawnCwd(cwd);
    model.setLastSpawnFxModel(model_id);
    model.setLastSpawnFxPermissionMode(permission_mode);
    model.setLastSpawnImagePath("");

    var stdin_buf: [8192]u8 = undefined;
    const stdin = acp.writeTurnStdin(&stdin_buf, .{
        .cwd = cwd,
        .resume_id = resume_id,
        .prompt = prompt,
        .model = model_id,
        .access_mode = session.accessMode(),
    }) catch return false;

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

    var argv_buf: [16][]const u8 = undefined;
    var n: usize = 0;
    argv_buf[n] = model.sidecarPath();
    n += 1;
    argv_buf[n] = acp_proxy.SUBCOMMAND;
    n += 1;
    argv_buf[n] = "--";
    n += 1;
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
    argv_buf[n] = binary;
    n += 1;
    argv_buf[n] = "acp";
    n += 1;

    model.fx_spawn_acp = true;
    fx.spawn(.{
        .key = allocateFxSpawnKey(model),
        .argv = argv_buf[0..n],
        .stdin = stdin,
        .on_line = Effects.lineMsg(.fx_line),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
    return true;
}

pub fn startFxAsk(model: *Model, fx: *Effects, session: *const Session, prompt: []const u8) void {
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

    model.fx_spawn_acp = false;
    fx.spawn(.{
        .key = allocateFxSpawnKey(model),
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

fn testArgvHas(argv: []const []const u8, needle: []const u8) bool {
    for (argv) |arg| {
        if (std.mem.eql(u8, arg, needle)) return true;
    }
    return false;
}

fn testArgvIndex(argv: []const []const u8, needle: []const u8) ?usize {
    for (argv, 0..) |arg, i| {
        if (std.mem.eql(u8, arg, needle)) return i;
    }
    return null;
}

test "cursor + cli_available selects acp-proxy cursor-agent acp" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setSidecarPath("faku");
    const id = model.addSession("cursor thread", .cursor);
    model.cli_available[@intFromEnum(protocol.ProviderId.cursor)] = true;

    startPrompt(&model, &fx, id, "hello cursor");
    try testing.expectEqual(main.ReplyPath.fx, model.reply_path);
    try testing.expect(model.fx_spawn_acp);
    try testing.expectEqual(@as(usize, 0), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());

    const request = fx.pendingSpawnAt(0).?;
    try testing.expectEqual(main.fx_ask_key, request.key);
    try testing.expect(testArgvHas(request.argv, acp_proxy.SUBCOMMAND));
    try testing.expect(testArgvHas(request.argv, "--"));
    try testing.expect(testArgvHas(request.argv, "cursor-agent"));
    try testing.expect(testArgvHas(request.argv, "acp"));
    try testing.expect(!testArgvHas(request.argv, "ask"));
    try testing.expect(!testArgvHas(request.argv, "fx"));
    try testing.expect(!testArgvHas(request.argv, daemon_proxy.SUBCOMMAND));
    const dash = testArgvIndex(request.argv, "--") orelse return error.MissingDash;
    const binary_at = testArgvIndex(request.argv, "cursor-agent") orelse return error.MissingBinary;
    const acp_at = testArgvIndex(request.argv, "acp") orelse return error.MissingAcp;
    try testing.expect(dash < binary_at);
    try testing.expectEqual(binary_at + 1, acp_at);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"method\":\"initialize\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"method\":\"session/new\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"method\":\"session/set_mode\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"method\":\"session/prompt\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "hello cursor") != null);
}

test "opencode + cli_available selects acp-proxy opencode acp" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setSidecarPath("faku");
    const id = model.addSession("opencode thread", .opencode);
    model.cli_available[@intFromEnum(protocol.ProviderId.opencode)] = true;

    startPrompt(&model, &fx, id, "hello opencode");
    try testing.expectEqual(main.ReplyPath.fx, model.reply_path);
    try testing.expect(model.fx_spawn_acp);
    try testing.expectEqual(@as(usize, 0), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());

    const request = fx.pendingSpawnAt(0).?;
    try testing.expectEqual(main.fx_ask_key, request.key);
    try testing.expect(testArgvHas(request.argv, acp_proxy.SUBCOMMAND));
    try testing.expect(testArgvHas(request.argv, "--"));
    try testing.expect(testArgvHas(request.argv, "opencode"));
    try testing.expect(testArgvHas(request.argv, "acp"));
    try testing.expect(!testArgvHas(request.argv, "ask"));
    try testing.expect(!testArgvHas(request.argv, "fx"));
    try testing.expect(!testArgvHas(request.argv, "cursor-agent"));
    try testing.expect(!testArgvHas(request.argv, daemon_proxy.SUBCOMMAND));
    const dash = testArgvIndex(request.argv, "--") orelse return error.MissingDash;
    const binary_at = testArgvIndex(request.argv, "opencode") orelse return error.MissingBinary;
    const acp_at = testArgvIndex(request.argv, "acp") orelse return error.MissingAcp;
    try testing.expect(dash < binary_at);
    try testing.expectEqual(binary_at + 1, acp_at);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"method\":\"initialize\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"method\":\"session/new\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"method\":\"session/set_mode\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"method\":\"session/prompt\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "hello opencode") != null);
}

test "opencode unavailable stays demo" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;
    var model = Model{};
    const id = model.addSession("opencode missing", .opencode);
    startPrompt(&model, &fx, id, "no opencode");
    try testing.expectEqual(main.ReplyPath.demo, model.reply_path);
    try testing.expect(!model.fx_spawn_acp);
    try testing.expectEqual(@as(usize, 1), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
}

test "speaksBareAcp is true for cursor and opencode; false for claude grok and others" {
    const testing = std.testing;
    try testing.expect(protocol.ProviderId.cursor.speaksBareAcp());
    try testing.expect(protocol.ProviderId.opencode.speaksBareAcp());
    try testing.expect(!protocol.ProviderId.fx.speaksBareAcp());
    try testing.expect(!protocol.ProviderId.claude.speaksBareAcp());
    try testing.expect(!protocol.ProviderId.codex.speaksBareAcp());
    try testing.expect(!protocol.ProviderId.amp.speaksBareAcp());
    try testing.expect(!protocol.ProviderId.grok.speaksBareAcp());
    try testing.expect(!protocol.ProviderId.pi.speaksBareAcp());
}

test "cursor unavailable or non-ACP provider stays demo" {
    const testing = std.testing;

    {
        var fx = Effects.init(testing.allocator);
        defer fx.deinit();
        fx.executor = .fake;
        var model = Model{};
        const cursor_id = model.addSession("cursor missing", .cursor);
        startPrompt(&model, &fx, cursor_id, "no cursor-agent");
        try testing.expectEqual(main.ReplyPath.demo, model.reply_path);
        try testing.expect(!model.fx_spawn_acp);
        try testing.expectEqual(@as(usize, 1), fx.pendingTimerCount());
        try testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
    }

    {
        var fx = Effects.init(testing.allocator);
        defer fx.deinit();
        fx.executor = .fake;
        var model = Model{};
        model.cli_available[@intFromEnum(protocol.ProviderId.claude)] = true;
        const claude_id = model.addSession("claude demo", .claude);
        startPrompt(&model, &fx, claude_id, "stay demo");
        try testing.expectEqual(main.ReplyPath.demo, model.reply_path);
        try testing.expectEqual(@as(usize, 1), fx.pendingTimerCount());
        try testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
    }

    {
        var fx = Effects.init(testing.allocator);
        defer fx.deinit();
        fx.executor = .fake;
        var model = Model{};
        model.cli_available[@intFromEnum(protocol.ProviderId.grok)] = true;
        const grok_id = model.addSession("grok demo", .grok);
        startPrompt(&model, &fx, grok_id, "no grok driver");
        try testing.expectEqual(main.ReplyPath.demo, model.reply_path);
        try testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
    }
}

test "fx path stays preferred when provider is fx even if cursor is available" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.fx_available = true;
    model.fx_probe_started = true;
    model.setFxPath("fx");
    model.setSidecarPath("faku");
    model.cli_available[@intFromEnum(protocol.ProviderId.cursor)] = true;
    const id = model.addSession("fx first", .fx);

    startPrompt(&model, &fx, id, "keep fx");
    try testing.expectEqual(main.ReplyPath.fx, model.reply_path);
    try testing.expect(model.fx_spawn_acp);
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());
    const request = fx.pendingSpawnAt(0).?;
    try testing.expect(testArgvHas(request.argv, acp_proxy.SUBCOMMAND));
    try testing.expect(testArgvHas(request.argv, "fx"));
    try testing.expect(testArgvHas(request.argv, "acp"));
    try testing.expect(!testArgvHas(request.argv, "cursor-agent"));
    try testing.expect(!testArgvHas(request.argv, "ask"));
}

test "cursor image attach stays demo" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var image_buf: [256]u8 = undefined;
    const image = try std.fmt.bufPrint(&image_buf, ".zig-cache/tmp/{s}/shot.png", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().writeFile(testing.io, .{ .sub_path = image, .data = "png" });

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = testing.io;
    model.setSidecarPath("faku");
    model.cli_available[@intFromEnum(protocol.ProviderId.cursor)] = true;
    const id = model.addSession("cursor image", .cursor);
    model.selected = id;
    model.setDraftImagePath(image);

    startPrompt(&model, &fx, id, "describe this");
    try testing.expectEqual(main.ReplyPath.demo, model.reply_path);
    try testing.expect(!model.fx_spawn_acp);
    try testing.expectEqual(@as(usize, 1), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
}
