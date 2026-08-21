const std = @import("std");
const native_sdk = @import("native_sdk");
const main = @import("main.zig");
const protocol = @import("protocol.zig");
const store = @import("store.zig");
const daemon_proxy = @import("daemon_proxy.zig");
const rewind = @import("rewind.zig");
const acp = @import("acp.zig");

const canvas = native_sdk.canvas;
const testing = std.testing;

const AppUi = main.AppUi;
const Model = main.Model;
const Msg = main.Msg;
const Effects = main.Effects;

const AppMarkup = canvas.MarkupView(Model, Msg);

fn buildTree(arena: std.mem.Allocator, model: *const Model) !AppUi.Tree {
    var view = try AppMarkup.init(arena, main.app_markup);
    var ui = AppUi.init(arena);
    const node = view.build(&ui, model) catch |err| {
        if (err == error.MarkupBuild) {
            std.debug.print("app.native:{d}:{d}: {s}\n", .{ view.diagnostic.line, view.diagnostic.column, view.diagnostic.message });
        }
        return err;
    };
    return ui.finalize(node);
}

fn findByText(widget: canvas.Widget, kind: canvas.WidgetKind, text: []const u8) ?canvas.Widget {
    if (widget.kind == kind and std.mem.eql(u8, widget.text, text)) return widget;
    for (widget.children) |child| {
        if (findByText(child, kind, text)) |found| return found;
    }
    return null;
}

fn expectByText(widget: canvas.Widget, kind: canvas.WidgetKind, text: []const u8) !canvas.Widget {
    return findByText(widget, kind, text) orelse {
        std.debug.print("no {t} with text \"{s}\" in the view\n", .{ kind, text });
        dumpTexts(widget, 0);
        return error.WidgetNotFound;
    };
}

fn dumpTexts(widget: canvas.Widget, depth: usize) void {
    if (widget.text.len > 0) {
        std.debug.print("{d} {t} [{s}]\n", .{ depth, widget.kind, widget.text });
    }
    for (widget.children) |child| dumpTexts(child, depth + 1);
}

fn findButtonContaining(widget: canvas.Widget, text: []const u8) ?canvas.Widget {
    if (widget.kind == .button) {
        if (std.mem.eql(u8, widget.text, text)) return widget;
        if (findByText(widget, .text, text) != null) return widget;
    }
    for (widget.children) |child| {
        if (findButtonContaining(child, text)) |found| return found;
    }
    return null;
}

fn expectButton(widget: canvas.Widget, text: []const u8) !canvas.Widget {
    return findButtonContaining(widget, text) orelse {
        std.debug.print("no button containing \"{s}\"\n", .{text});
        dumpTexts(widget, 0);
        return error.WidgetNotFound;
    };
}

fn countRole(model: *const Model, role: main.Role) usize {
    var n: usize = 0;
    for (model.turn_store[0..model.turn_count]) |turn| {
        if (turn.session_id == model.selected and turn.role == role) n += 1;
    }
    return n;
}

fn lastAssistant(model: *const Model) []const u8 {
    var i = model.turn_count;
    while (i > 0) {
        i -= 1;
        const turn = &model.turn_store[i];
        if (turn.session_id == model.selected and turn.role == .assistant) return turn.text();
    }
    return "";
}

test "boot is fx-first and New / send / ticks / stop drive the demo" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = main.initialModel();
    try testing.expectEqual(@as(u32, 2), model.session_count);
    try testing.expectEqualStrings("port waku to zig", model.selected_title());
    try testing.expectEqualStrings("fx", model.selected_provider());
    try testing.expect(!model.is_streaming());
    try testing.expectEqual(main.Provider.fx, model.session_store[0].provider);

    var tree = try buildTree(arena, &model);
    _ = try expectByText(tree.root, .text, "Faku");
    _ = try expectByText(tree.root, .button, "New");
    _ = try expectButton(tree.root, "port waku to zig");
    _ = try expectButton(tree.root, "fix auth listener");
    _ = try expectByText(tree.root, .button, "Send");
    _ = try expectByText(tree.root, .status_bar, "2 sessions \u{b7} demo \u{b7} fx");
    _ = try expectByText(tree.root, .text, "fx");

    const new_btn = try expectByText(tree.root, .button, "New");
    main.update(&model, tree.msgForPointer(new_btn.id, .up).?, &fx);
    try testing.expectEqual(@as(u32, 3), model.session_count);
    try testing.expectEqualStrings("untitled", model.selected_title());
    try testing.expectEqualStrings("fx", model.selected_provider());
    try testing.expectEqual(main.Provider.fx, model.session_store[2].provider);

    main.update(&model, .{ .draft_edit = .{ .insert_text = "port the sidebar" } }, &fx);
    try testing.expectEqualStrings("port the sidebar", model.draft());

    tree = try buildTree(arena, &model);
    const send = try expectByText(tree.root, .button, "Send");
    main.update(&model, tree.msgForPointer(send.id, .up).?, &fx);
    try testing.expect(model.is_streaming());
    try testing.expectEqual(@as(usize, 1), countRole(&model, .user));
    try testing.expectEqual(@as(usize, 1), countRole(&model, .assistant));
    try testing.expectEqual(@as(usize, 1), fx.pendingTimerCount());
    try testing.expectEqual(main.stream_timer_key, fx.pendingTimerAt(0).?.key);
    try testing.expectEqual(@as(u64, 90), fx.pendingTimerAt(0).?.interval_ms);

    var n: u32 = 0;
    while (n < 4) : (n += 1) {
        main.update(&model, .{ .tick = .{ .key = main.stream_timer_key } }, &fx);
    }
    try testing.expect(model.is_streaming());
    try testing.expect(lastAssistant(&model).len > 0);
    try testing.expect(std.mem.indexOf(u8, lastAssistant(&model), "fx") != null);

    tree = try buildTree(arena, &model);
    const stop = try expectByText(tree.root, .button, "Stop");
    main.update(&model, tree.msgForPointer(stop.id, .up).?, &fx);
    try testing.expect(!model.is_streaming());
    try testing.expectEqual(@as(usize, 0), fx.pendingTimerCount());
}

test "selecting the claude session shows its transcript" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = main.initialModel();
    var tree = try buildTree(arena, &model);
    const auth = try expectButton(tree.root, "fix auth listener");
    main.update(&model, tree.msgForPointer(auth.id, .up).?, &fx);
    try testing.expectEqualStrings("fix auth listener", model.selected_title());
    try testing.expectEqualStrings("claude", model.selected_provider());
    try testing.expectEqual(@as(usize, 1), countRole(&model, .user));
    try testing.expectEqual(@as(usize, 2), countRole(&model, .assistant));
    try testing.expectEqual(@as(usize, 1), countRole(&model, .tool));

    tree = try buildTree(arena, &model);
    _ = try expectByText(tree.root, .text, "You");
    _ = try expectByText(tree.root, .text, "Tool");
    _ = try expectByText(tree.root, .status_bar, "2 sessions \u{b7} demo \u{b7} claude");
}

test "escape stops a live demo stream" {
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = main.initialModel();
    main.update(&model, .{ .draft_edit = .{ .insert_text = "hello" } }, &fx);
    main.update(&model, .send, &fx);
    try testing.expect(model.is_streaming());
    main.update(&model, .stop, &fx);
    try testing.expect(!model.is_streaming());
    try testing.expectEqual(@as(usize, 0), fx.pendingTimerCount());
}

test "protocol stubs speak camelCase v3 and default to fx" {
    try testing.expectEqual(@as(u32, 3), protocol.PROTOCOL_VERSION);
    try testing.expectEqualStrings("fx", protocol.ProviderId.default.wireName());
    try testing.expectEqualStrings("fx", protocol.FX_ACP_ARGV[0]);
    try testing.expectEqualStrings("acp", protocol.FX_ACP_ARGV[1]);
    var buf: [512]u8 = undefined;
    const hello = try protocol.writeHello(&buf, .{ .token = "t", .client_id = "c" });
    try testing.expect(std.mem.indexOf(u8, hello, "protocolVersion") != null);
    const start = try protocol.writeStart(&buf, protocol.NIL_UUID, protocol.NIL_UUID, protocol.NIL_UUID, protocol.defaultStartOptions());
    try testing.expect(std.mem.indexOf(u8, start, "\"provider\":\"fx\"") != null);
}

test "send without fx still starts the demo timer" {
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = main.initialModel();
    try testing.expect(!model.fx_available);
    main.update(&model, .{ .draft_edit = .{ .insert_text = "hello without fx" } }, &fx);
    main.update(&model, .send, &fx);
    try testing.expect(model.is_streaming());
    try testing.expectEqual(main.ReplyPath.demo, model.reply_path);
    try testing.expectEqual(@as(usize, 1), fx.pendingTimerCount());
    try testing.expectEqual(main.stream_timer_key, fx.pendingTimerAt(0).?.key);
    try testing.expectEqual(@as(u64, 90), fx.pendingTimerAt(0).?.interval_ms);
}

test "send with fx_available spawns one-shot fx acp and streams session/update text" {
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = main.initialModel();
    model.fx_available = true;
    model.fx_probe_started = true;
    model.setFxPath("fx");

    main.update(&model, .{ .draft_edit = .{ .insert_text = "what does this repo do" } }, &fx);
    main.update(&model, .send, &fx);
    try testing.expect(model.is_streaming());
    try testing.expectEqual(main.ReplyPath.fx, model.reply_path);
    try testing.expect(model.fx_spawn_acp);
    try testing.expectEqual(@as(usize, 0), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());

    const request = fx.pendingSpawnAt(0).?;
    try testing.expectEqual(main.fx_ask_key, request.key);
    try testing.expect(argvHas(request.argv, "acp"));
    try testing.expect(argvHas(request.argv, "fx"));
    try testing.expect(!argvHas(request.argv, "ask"));
    try testing.expect(!argvHas(request.argv, "--model"));
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"method\":\"initialize\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"method\":\"session/new\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"method\":\"session/set_mode\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"modeId\":\"code\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "session/set_config_option") == null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"method\":\"session/prompt\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "session/resume") == null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "what does this repo do") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"cwd\":\".\"") != null);

    const before_len = lastAssistant(&model).len;
    try fx.feedLine(main.fx_ask_key, "{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"sessionId\":\"s1\",\"update\":{\"sessionUpdate\":\"agent_message_chunk\",\"content\":{\"type\":\"text\",\"text\":\"hello from fx acp\"}}}}");
    drainEffects(&model, &fx);
    try testing.expect(lastAssistant(&model).len > before_len);
    try testing.expect(std.mem.indexOf(u8, lastAssistant(&model), "hello from fx acp") != null);

    try fx.feedLine(main.fx_ask_key, "{\"jsonrpc\":\"2.0\",\"id\":3,\"result\":{\"stopReason\":\"end_turn\"}}");
    drainEffects(&model, &fx);
    try testing.expect(!model.is_streaming());
}

test "fx acp session/new cwd is session project_path when it exists" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/project", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(testing.io, project);

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.fx_available = true;
    model.fx_probe_started = true;
    model.setFxPath("fx");
    model.store_io = testing.io;
    const id = model.addSession("cwd spawn", .fx);
    if (model.sessionById(id)) |session| session.setProjectPath(project);
    model.selected = id;

    main.update(&model, .{ .draft_edit = .{ .insert_text = "what is the cwd" } }, &fx);
    main.update(&model, .send, &fx);
    try testing.expect(model.is_streaming());
    try testing.expectEqual(main.ReplyPath.fx, model.reply_path);
    try testing.expect(model.fx_spawn_acp);
    try testing.expectEqualStrings(project, model.lastSpawnCwd());
    try testing.expectEqualStrings(project, model.resolveAcpCwd(model.sessionByIdConst(id).?));
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());

    const request = fx.pendingSpawnAt(0).?;
    try testing.expectEqual(main.fx_ask_key, request.key);
    try testing.expect(argvHas(request.argv, "acp"));
    try testing.expect(!argvHas(request.argv, "ask"));
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"method\":\"session/new\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, project) != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "what is the cwd") != null);
}

test "fx acp session/new persists fx_session_id and later send uses session/resume" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-fx-id", .{tmp.sub_path[0..]});

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.task_state_loaded = true;
    model.setStoreDir(dir);
    model.store_io = testing.io;
    model.fx_available = true;
    model.fx_probe_started = true;
    model.setFxPath("fx");
    const id = model.addSession("resume thread", .fx);
    model.selected = id;

    main.update(&model, .{ .draft_edit = .{ .insert_text = "first turn" } }, &fx);
    main.update(&model, .send, &fx);
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());
    const first = fx.pendingSpawnAt(0).?;
    try testing.expect(argvHas(first.argv, "fx"));
    try testing.expect(argvHas(first.argv, "acp"));
    try testing.expect(!argvHas(first.argv, "ask"));
    try testing.expect(std.mem.indexOf(u8, first.stdin, "\"method\":\"initialize\"") != null);
    try testing.expect(std.mem.indexOf(u8, first.stdin, "\"method\":\"session/new\"") != null);
    try testing.expect(std.mem.indexOf(u8, first.stdin, "\"method\":\"session/prompt\"") != null);
    try testing.expect(std.mem.indexOf(u8, first.stdin, "session/resume") == null);

    try fx.feedLine(main.fx_ask_key, "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"sessionId\":\"fx-test-1\"}}");
    drainEffects(&model, &fx);
    try testing.expectEqualStrings("fx-test-1", model.sessionById(id).?.fxSessionId());
    try testing.expectEqual(@as(usize, 0), lastAssistant(&model).len);

    try fx.feedLine(main.fx_ask_key, "{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"sessionId\":\"fx-test-1\",\"update\":{\"sessionUpdate\":\"agent_message_chunk\",\"content\":{\"type\":\"text\",\"text\":\"plain reply\"}}}}");
    drainEffects(&model, &fx);
    try testing.expect(std.mem.indexOf(u8, lastAssistant(&model), "plain reply") != null);
    try testing.expect(std.mem.indexOf(u8, lastAssistant(&model), "session_id") == null);
    try testing.expect(std.mem.indexOf(u8, lastAssistant(&model), "sessionId") == null);

    try fx.feedLine(main.fx_ask_key, "{\"jsonrpc\":\"2.0\",\"id\":3,\"result\":{\"stopReason\":\"end_turn\"}}");
    drainEffects(&model, &fx);
    try testing.expect(!model.is_streaming());

    var loaded = Model{};
    loaded.setStoreDir(dir);
    try testing.expectEqual(store.LoadKind.loaded, store.loadCatalog(&loaded, testing.allocator, testing.io));
    try testing.expectEqualStrings("fx-test-1", loaded.session_store[0].fxSessionId());

    main.update(&model, .{ .draft_edit = .{ .insert_text = "second turn" } }, &fx);
    main.update(&model, .send, &fx);
    var found_resume = false;
    var i: usize = 0;
    while (fx.pendingSpawnAt(i)) |spawn| : (i += 1) {
        if (std.mem.indexOf(u8, spawn.stdin, "session/resume") == null) continue;
        try testing.expect(argvHas(spawn.argv, "acp"));
        try testing.expect(std.mem.indexOf(u8, spawn.stdin, "\"method\":\"initialize\"") != null);
        try testing.expect(std.mem.indexOf(u8, spawn.stdin, "\"sessionId\":\"fx-test-1\"") != null);
        try testing.expect(std.mem.indexOf(u8, spawn.stdin, "session/new") == null);
        try testing.expect(std.mem.indexOf(u8, spawn.stdin, "session/load") == null);
        try testing.expect(std.mem.indexOf(u8, spawn.stdin, "second turn") != null);
        found_resume = true;
    }
    try testing.expect(found_resume);
}

test "fx acp session/prompt stopReason settles and drains the success-only queue" {
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.fx_available = true;
    model.fx_probe_started = true;
    model.setFxPath("fx");
    const id = model.addSession("acp drain", .fx);
    model.selected = id;
    main.update(&model, .{ .draft_edit = .{ .insert_text = "first prompt" } }, &fx);
    main.update(&model, .send, &fx);
    try testing.expect(model.fx_spawn_acp);
    const key = model.fx_spawn_key;

    main.update(&model, .{ .draft_edit = .{ .insert_text = "queued follow-up" } }, &fx);
    main.update(&model, .send, &fx);
    try testing.expectEqual(@as(u32, 1), model.queuedCount(id));

    try fx.feedLine(key, "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"sessionId\":\"acp-1\"}}");
    drainEffects(&model, &fx);
    try fx.feedLine(key, "{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"update\":{\"sessionUpdate\":\"agent_message_chunk\",\"content\":{\"type\":\"text\",\"text\":\"chunk\"}}}}");
    drainEffects(&model, &fx);
    try fx.feedLine(key, "{\"jsonrpc\":\"2.0\",\"id\":3,\"result\":{\"stopReason\":\"end_turn\"}}");
    drainEffects(&model, &fx);
    try testing.expectEqual(@as(u32, 0), model.queuedCount(id));
    try testing.expect(model.is_streaming());
    try testing.expectEqual(@as(usize, 2), countRole(&model, .user));
    try testing.expectEqualStrings("acp-1", model.sessionById(id).?.fxSessionId());

    var found_follow_up = false;
    var i: usize = 0;
    while (fx.pendingSpawnAt(i)) |spawn| : (i += 1) {
        if (std.mem.indexOf(u8, spawn.stdin, "queued follow-up") == null) continue;
        try testing.expect(std.mem.indexOf(u8, spawn.stdin, "session/resume") != null);
        try testing.expect(std.mem.indexOf(u8, spawn.stdin, "\"sessionId\":\"acp-1\"") != null);
        found_follow_up = true;
    }
    try testing.expect(found_follow_up);
}

test "fx ask spawn records FX_MODEL and FX_PERMISSION_MODE" {
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.fx_available = true;
    model.fx_probe_started = true;
    model.setFxPath("fx");
    const id = model.addSession("env spawn", .fx);
    if (model.sessionById(id)) |session| {
        session.setModel("openai/gpt-5.4");
        session.setAccessMode("fullAccess");
    }
    model.selected = id;

    main.update(&model, .{ .draft_edit = .{ .insert_text = "with env" } }, &fx);
    main.update(&model, .send, &fx);
    try testing.expectEqualStrings("openai/gpt-5.4", model.lastSpawnFxModel());
    try testing.expectEqualStrings("yolo", model.lastSpawnFxPermissionMode());
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());

    const request = fx.pendingSpawnAt(0).?;
    try testing.expectEqualStrings(main.fx_env_bin, request.argv[0]);
    try testing.expect(argvHas(request.argv, "FX_MODEL=openai/gpt-5.4"));
    try testing.expect(argvHas(request.argv, "FX_PERMISSION_MODE=yolo"));
    try testing.expect(argvHas(request.argv, "fx"));
    try testing.expect(argvHas(request.argv, "acp"));
    try testing.expect(!argvHas(request.argv, "ask"));
    try testing.expect(!argvHas(request.argv, "--model"));
    try testing.expect(std.mem.indexOf(u8, request.stdin, "with env") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"method\":\"initialize\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"method\":\"session/new\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"method\":\"session/set_mode\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"modeId\":\"code\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"method\":\"session/set_config_option\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"configId\":\"model\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"value\":\"openai/gpt-5.4\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"method\":\"session/prompt\"") != null);
    try testing.expect(methodBefore(request.stdin, "session/new", "session/set_mode"));
    try testing.expect(methodBefore(request.stdin, "session/set_mode", "session/set_config_option"));
    try testing.expect(methodBefore(request.stdin, "session/set_config_option", "session/prompt"));
    try testing.expect(std.mem.indexOf(u8, request.stdin, "fullAccess") == null);
}

test "fx acp stdin omits model config when model is empty" {
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.fx_available = true;
    model.fx_probe_started = true;
    model.setFxPath("fx");
    const id = model.addSession("empty model", .fx);
    if (model.sessionById(id)) |session| {
        session.setModel("");
        session.setAccessMode("ask");
    }
    model.selected = id;

    main.update(&model, .{ .draft_edit = .{ .insert_text = "no model set" } }, &fx);
    main.update(&model, .send, &fx);
    try testing.expectEqual(@as(usize, 0), model.lastSpawnFxModel().len);
    try testing.expectEqualStrings("ask", model.lastSpawnFxPermissionMode());
    const request = fx.pendingSpawnAt(0).?;
    try testing.expect(argvHas(request.argv, "acp"));
    try testing.expect(argvHas(request.argv, "FX_PERMISSION_MODE=ask"));
    try testing.expect(!argvHas(request.argv, "FX_MODEL="));
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"method\":\"initialize\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"method\":\"session/new\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"method\":\"session/set_mode\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"modeId\":\"ask\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "session/set_config_option") == null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"configId\":\"model\"") == null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"method\":\"session/prompt\"") != null);
    try testing.expect(methodBefore(request.stdin, "session/new", "session/set_mode"));
    try testing.expect(methodBefore(request.stdin, "session/set_mode", "session/prompt"));
}

test "newSession draft loads on New Task and is discarded after first send" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-drafts", .{tmp.sub_path[0..]});

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.task_state_loaded = true;
    model.setStoreDir(dir);
    model.store_io = testing.io;
    main.update(&model, .new_session, &fx);
    const first = model.selected;
    try testing.expect(model.sessionById(first).?.untitled);
    var key_buf: [store.max_draft_key]u8 = undefined;
    try testing.expectEqualStrings("newSession", store.draftKey(model.sessionById(first).?, &key_buf).?);

    main.update(&model, .{ .draft_edit = .{ .insert_text = "first prompt draft" } }, &fx);
    model.setDraftImagePath("/tmp/will-be-discarded.png");
    store.persistDraftIfPossible(&model);
    try testing.expectEqualStrings("first prompt draft", model.draft());
    try testing.expectEqualStrings("/tmp/will-be-discarded.png", model.draftImagePath());

    var peek = Model{};
    peek.setStoreDir(dir);
    peek.store_io = testing.io;
    const peek_id = peek.addSession("untitled", .fx);
    if (peek.sessionById(peek_id)) |session| session.untitled = true;
    peek.selected = peek_id;
    store.loadDraftIfPossible(&peek);
    try testing.expectEqualStrings("first prompt draft", peek.draft());

    main.update(&model, .send, &fx);
    try testing.expect(model.is_streaming());
    try testing.expectEqual(@as(usize, 0), model.draft().len);
    var n: u32 = 0;
    while (n < 16 and model.is_streaming()) : (n += 1) {
        main.update(&model, .{ .tick = .{ .key = main.stream_timer_key } }, &fx);
    }

    var after = Model{};
    after.task_state_loaded = true;
    after.setStoreDir(dir);
    after.store_io = testing.io;
    const next = after.addSession("untitled", .fx);
    if (after.sessionById(next)) |session| session.untitled = true;
    after.selected = next;
    store.loadDraftIfPossible(&after);
    try testing.expectEqual(@as(usize, 0), after.draft().len);
    try testing.expectEqual(@as(usize, 0), after.draftImagePath().len);
}

test "fx ask --image when draft image_path exists" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var image_buf: [256]u8 = undefined;
    const image = try std.fmt.bufPrint(&image_buf, ".zig-cache/tmp/{s}/shot.png", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().writeFile(testing.io, .{ .sub_path = image, .data = "png" });

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.fx_available = true;
    model.fx_probe_started = true;
    model.setFxPath("fx");
    model.store_io = testing.io;
    const id = model.addSession("image send", .fx);
    model.selected = id;
    model.setDraftImagePath(image);

    main.update(&model, .{ .draft_edit = .{ .insert_text = "describe this" } }, &fx);
    main.update(&model, .send, &fx);
    try testing.expectEqualStrings(image, model.lastSpawnImagePath());
    try testing.expectEqual(@as(usize, 0), model.draftImagePath().len);
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());

    const request = fx.pendingSpawnAt(0).?;
    try testing.expect(argvHas(request.argv, "ask"));
    try testing.expect(!argvHas(request.argv, "acp"));
    try testing.expect(argvHas(request.argv, "--image"));
    const image_at = argvIndex(request.argv, "--image") orelse return error.MissingImage;
    try testing.expectEqualStrings(image, request.argv[image_at + 1]);
    const dash_at = argvIndex(request.argv, "--") orelse return error.MissingDash;
    try testing.expect(image_at < dash_at);
    try testing.expect(!argvHas(request.argv, "--file"));
    try testing.expectEqualStrings("describe this", request.argv[request.argv.len - 1]);
}

test "fx ask omits --image when the draft file is missing" {
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.fx_available = true;
    model.fx_probe_started = true;
    model.setFxPath("fx");
    model.store_io = testing.io;
    const id = model.addSession("missing image", .fx);
    model.selected = id;
    model.setDraftImagePath(".zig-cache/tmp/faku-no-such-image.png");

    main.update(&model, .{ .draft_edit = .{ .insert_text = "no image" } }, &fx);
    main.update(&model, .send, &fx);
    try testing.expectEqual(@as(usize, 0), model.lastSpawnImagePath().len);
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());
    const request = fx.pendingSpawnAt(0).?;
    try testing.expect(argvHas(request.argv, "acp"));
    try testing.expect(!argvHas(request.argv, "ask"));
    try testing.expect(!argvHas(request.argv, "--image"));
    try testing.expect(std.mem.indexOf(u8, request.stdin, "no image") != null);
}

test "Waku access_mode maps to verified FX_PERMISSION_MODE values" {
    try testing.expectEqualStrings("ask", main.fxPermissionMode("ask"));
    try testing.expectEqualStrings("auto", main.fxPermissionMode("auto"));
    try testing.expectEqualStrings("auto", main.fxPermissionMode("autoAcceptEdits"));
    try testing.expectEqualStrings("yolo", main.fxPermissionMode("fullAccess"));
    try testing.expectEqualStrings("yolo", main.fxPermissionMode("yolo"));
    try testing.expectEqualStrings("", main.fxPermissionMode("nope"));
    try testing.expectEqualStrings("", main.fxPermissionMode(""));
}

test "Waku access_mode maps to fx ACP ask|code, not fullAccess" {
    try testing.expectEqualStrings("ask", acp.sessionMode("ask"));
    try testing.expectEqualStrings("code", acp.sessionMode("code"));
    try testing.expectEqualStrings("code", acp.sessionMode("auto"));
    try testing.expectEqualStrings("code", acp.sessionMode("autoAcceptEdits"));
    try testing.expectEqualStrings("code", acp.sessionMode("fullAccess"));
    try testing.expectEqualStrings("code", acp.sessionMode("yolo"));
    try testing.expectEqualStrings("", acp.sessionMode(""));
    try testing.expectEqualStrings("", acp.sessionMode("nope"));
}

fn drainEffects(model: *Model, fx: *Effects) void {
    while (fx.takeMsg()) |msg| main.update(model, msg, fx);
}

fn argvHas(argv: []const []const u8, needle: []const u8) bool {
    return argvIndex(argv, needle) != null;
}

fn argvIndex(argv: []const []const u8, needle: []const u8) ?usize {
    for (argv, 0..) |arg, i| {
        if (std.mem.eql(u8, arg, needle)) return i;
    }
    return null;
}

fn methodBefore(stdin: []const u8, earlier: []const u8, later: []const u8) bool {
    const a = std.mem.indexOf(u8, stdin, earlier) orelse return false;
    const b = std.mem.indexOf(u8, stdin, later) orelse return false;
    return a < b;
}

test "send + stream finish persists the selected session for a later load" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-update", .{tmp.sub_path[0..]});

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.task_state_loaded = true;
    model.setStoreDir(dir);
    model.store_io = testing.io;
    const id = model.addSession("untitled", .fx);
    if (model.sessionById(id)) |session| session.untitled = true;
    model.selected = id;

    main.update(&model, .{ .draft_edit = .{ .insert_text = "persist this turn" } }, &fx);
    main.update(&model, .send, &fx);
    try testing.expect(model.is_streaming());
    var n: u32 = 0;
    while (n < 16 and model.is_streaming()) : (n += 1) {
        main.update(&model, .{ .tick = .{ .key = main.stream_timer_key } }, &fx);
    }
    try testing.expect(!model.is_streaming());

    var loaded = Model{};
    loaded.setStoreDir(dir);
    try testing.expectEqual(store.LoadKind.loaded, store.loadCatalog(&loaded, testing.allocator, testing.io));
    try testing.expectEqual(@as(u32, 1), loaded.session_count);
    try testing.expectEqual(id, loaded.session_store[0].id);
    try testing.expectEqualStrings("persist this turn", loaded.session_store[0].title());
    store.hydrateSession(&loaded, id, testing.allocator, testing.io);
    try testing.expectEqual(@as(u32, 2), loaded.turn_count);
    try testing.expectEqualStrings("persist this turn", loaded.turn_store[0].text());
    try testing.expect(loaded.turn_store[1].text().len > 0);
}

test "successful finish drains the next queued follow-up" {
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    const id = model.addSession("queue drain", .fx);
    model.selected = id;
    main.update(&model, .{ .draft_edit = .{ .insert_text = "first prompt" } }, &fx);
    main.update(&model, .send, &fx);
    try testing.expect(model.is_streaming());

    main.update(&model, .{ .draft_edit = .{ .insert_text = "queued follow-up" } }, &fx);
    main.update(&model, .send, &fx);
    try testing.expectEqual(@as(u32, 1), model.queuedCount(id));
    try testing.expectEqualStrings("queued follow-up", model.firstQueuedText(id));
    try testing.expectEqual(@as(usize, 1), countRole(&model, .user));

    var n: u32 = 0;
    while (n < 16 and model.queuedCount(id) > 0) : (n += 1) {
        main.update(&model, .{ .tick = .{ .key = main.stream_timer_key } }, &fx);
    }
    try testing.expect(model.is_streaming());
    try testing.expectEqual(@as(u32, 0), model.queuedCount(id));
    try testing.expectEqual(@as(usize, 2), countRole(&model, .user));
    try testing.expectEqual(id, model.streaming_session);
}

test "stop does not drain the per-session queue" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-queue", .{tmp.sub_path[0..]});

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.task_state_loaded = true;
    model.setStoreDir(dir);
    model.store_io = testing.io;
    const id = model.addSession("keep queue", .fx);
    model.selected = id;
    main.update(&model, .{ .draft_edit = .{ .insert_text = "first prompt" } }, &fx);
    main.update(&model, .send, &fx);
    main.update(&model, .{ .draft_edit = .{ .insert_text = "stay queued" } }, &fx);
    main.update(&model, .send, &fx);
    try testing.expectEqual(@as(u32, 1), model.queuedCount(id));

    main.update(&model, .stop, &fx);
    try testing.expect(!model.is_streaming());
    try testing.expectEqual(@as(u32, 1), model.queuedCount(id));
    try testing.expectEqualStrings("stay queued", model.firstQueuedText(id));
    try testing.expectEqual(@as(usize, 1), countRole(&model, .user));

    var loaded = Model{};
    loaded.setStoreDir(dir);
    try testing.expectEqual(store.LoadKind.loaded, store.loadCatalog(&loaded, testing.allocator, testing.io));
    store.hydrateSession(&loaded, id, testing.allocator, testing.io);
    try testing.expectEqual(@as(u32, 1), loaded.queuedCount(id));
    try testing.expectEqualStrings("stay queued", loaded.firstQueuedText(id));
}

test "non-zero fx ask exit does not drain the queue" {
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.fx_available = true;
    model.fx_probe_started = true;
    model.setFxPath("fx");
    const id = model.addSession("fx fail", .fx);
    model.selected = id;
    main.update(&model, .{ .draft_edit = .{ .insert_text = "ask now" } }, &fx);
    main.update(&model, .send, &fx);
    main.update(&model, .{ .draft_edit = .{ .insert_text = "after failure" } }, &fx);
    main.update(&model, .send, &fx);
    try testing.expectEqual(@as(u32, 1), model.queuedCount(id));

    try fx.feedExit(main.fx_ask_key, 1);
    drainEffects(&model, &fx);
    try testing.expect(!model.is_streaming());
    try testing.expectEqual(@as(u32, 1), model.queuedCount(id));
    try testing.expectEqualStrings("after failure", model.firstQueuedText(id));
}

test "daemon address send puts hello loadTaskState and prompt on spawn stdin" {
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.fx_probe_started = true;
    model.setDaemonAddress("127.0.0.1:8787");
    model.setDaemonToken("secret");
    model.setSidecarPath("faku");
    const id = model.addSession("daemon session", .fx);
    _ = model.appendTurn(id, .user, "already started");
    model.selected = id;

    main.update(&model, .{ .draft_edit = .{ .insert_text = "trace the listener" } }, &fx);
    main.update(&model, .send, &fx);
    try testing.expect(model.is_streaming());
    try testing.expectEqual(main.ReplyPath.daemon, model.reply_path);
    try testing.expectEqual(@as(usize, 0), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());

    const request = fx.pendingSpawnAt(0).?;
    try testing.expectEqual(model.daemon_spawn_key, request.key);
    try testing.expect(argvHas(request.argv, daemon_proxy.SUBCOMMAND));
    try testing.expect(argvHas(request.argv, "127.0.0.1:8787"));
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"type\":\"hello\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"token\":\"secret\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"type\":\"loadTaskState\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"type\":\"prompt\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "trace the listener") != null);
    try testing.expectEqualStrings("127.0.0.1:8787", model.lastDaemonAddress());
}

fn isSaveOnlyStdin(stdin: []const u8) bool {
    return std.mem.indexOf(u8, stdin, "\"type\":\"saveTaskState\"") != null and
        std.mem.indexOf(u8, stdin, "\"type\":\"prompt\"") == null;
}

fn findSaveOnlySpawn(fx: *Effects) ?@TypeOf(fx.pendingSpawnAt(0).?) {
    var i: usize = 0;
    while (fx.pendingSpawnAt(i)) |spawn| : (i += 1) {
        if (isSaveOnlyStdin(spawn.stdin)) return spawn;
    }
    return null;
}

test "persist with a daemon address records hello and saveTaskState on spawn stdin" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-save-mirror", .{tmp.sub_path[0..]});

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.task_state_loaded = true;
    model.setStoreDir(dir);
    model.store_io = testing.io;
    model.setDaemonAddress("127.0.0.1:8787");
    model.setDaemonToken("secret");
    model.setSidecarPath("faku");
    const id = model.addSession("mirror me", .fx);
    if (model.sessionById(id)) |session| session.setProjectPath("/tmp/faku");
    _ = model.appendTurn(id, .user, "started");

    store.persistIfPossible(&model, id, &fx);
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());
    const spawn = fx.pendingSpawnAt(0).?;
    try testing.expect(argvHas(spawn.argv, daemon_proxy.SUBCOMMAND));
    try testing.expect(argvHas(spawn.argv, "127.0.0.1:8787"));
    try testing.expect(std.mem.indexOf(u8, spawn.stdin, "\"type\":\"hello\"") != null);
    try testing.expect(std.mem.indexOf(u8, spawn.stdin, "\"token\":\"secret\"") != null);
    try testing.expect(std.mem.indexOf(u8, spawn.stdin, "\"type\":\"saveTaskState\"") != null);
    try testing.expect(std.mem.indexOf(u8, spawn.stdin, "\"liveSessionIds\"") != null);
    try testing.expect(std.mem.indexOf(u8, spawn.stdin, "mirror me") != null);
    try testing.expect(std.mem.indexOf(u8, spawn.stdin, "/tmp/faku") != null);
    try testing.expect(std.mem.indexOf(u8, spawn.stdin, "\"has_started\":true") != null);
    try testing.expect(std.mem.indexOf(u8, spawn.stdin, "\"type\":\"prompt\"") == null);
    try testing.expect(spawn.key != model.daemon_spawn_key);
}

test "persist with last_daemon_address and no live env still mirrors" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-save-last", .{tmp.sub_path[0..]});

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.task_state_loaded = true;
    model.setStoreDir(dir);
    model.store_io = testing.io;
    model.setLastDaemonAddress("10.0.0.2:9");
    model.setSidecarPath("faku");
    const id = model.addSession("last addr", .fx);
    _ = model.appendTurn(id, .user, "started");
    try testing.expectEqual(@as(usize, 0), model.daemonAddress().len);

    store.persistIfPossible(&model, id, &fx);
    const spawn = findSaveOnlySpawn(&fx) orelse return error.SaveSpawnMissing;
    try testing.expect(argvHas(spawn.argv, "10.0.0.2:9"));
    try testing.expect(std.mem.indexOf(u8, spawn.stdin, "\"type\":\"hello\"") != null);
    try testing.expect(std.mem.indexOf(u8, spawn.stdin, "\"type\":\"saveTaskState\"") != null);
}

test "persist without a daemon address does not spawn a sidecar" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-save-local", .{tmp.sub_path[0..]});

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.task_state_loaded = true;
    model.setStoreDir(dir);
    model.store_io = testing.io;
    const id = model.addSession("local only", .fx);
    _ = model.appendTurn(id, .user, "started");

    store.persistIfPossible(&model, id, &fx);
    try testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());

    var loaded = Model{};
    loaded.setStoreDir(dir);
    try testing.expectEqual(store.LoadKind.loaded, store.loadCatalog(&loaded, testing.allocator, testing.io));
    try testing.expectEqual(@as(u32, 1), loaded.session_count);
    try testing.expectEqualStrings("local only", loaded.session_store[0].title());
}

test "saveTaskState sidecar failure leaves the local catalog intact" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-save-fail", .{tmp.sub_path[0..]});

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.task_state_loaded = true;
    model.setStoreDir(dir);
    model.store_io = testing.io;
    model.setDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    const id = model.addSession("keep me", .fx);
    _ = model.appendTurn(id, .user, "started");

    store.persistIfPossible(&model, id, &fx);
    const spawn = findSaveOnlySpawn(&fx) orelse return error.SaveSpawnMissing;
    try fx.feedExit(spawn.key, 1);
    drainEffects(&model, &fx);

    var loaded = Model{};
    loaded.setStoreDir(dir);
    try testing.expectEqual(store.LoadKind.loaded, store.loadCatalog(&loaded, testing.allocator, testing.io));
    try testing.expectEqual(@as(u32, 1), loaded.session_count);
    try testing.expectEqual(id, loaded.session_store[0].id);
    try testing.expectEqualStrings("keep me", loaded.session_store[0].title());
    store.hydrateSession(&loaded, id, testing.allocator, testing.io);
    try testing.expectEqualStrings("started", loaded.turn_store[0].text());
}

test "daemon textDelta hydrates the turn and turnFinished settles plus drains" {
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.fx_probe_started = true;
    model.setDaemonAddress("127.0.0.1:8787");
    const id = model.addSession("daemon settle", .fx);
    model.selected = id;
    main.update(&model, .{ .draft_edit = .{ .insert_text = "first prompt" } }, &fx);
    main.update(&model, .send, &fx);
    try testing.expectEqual(main.ReplyPath.daemon, model.reply_path);
    const key = model.daemon_spawn_key;

    main.update(&model, .{ .draft_edit = .{ .insert_text = "queued follow-up" } }, &fx);
    main.update(&model, .send, &fx);
    try testing.expectEqual(@as(u32, 1), model.queuedCount(id));

    try fx.feedLine(key, "{\"type\":\"event\",\"event\":{\"kind\":\"textDelta\",\"payload\":\"hello from sidecar\"}}");
    drainEffects(&model, &fx);
    try testing.expect(std.mem.indexOf(u8, lastAssistant(&model), "hello from sidecar") != null);
    try testing.expect(model.is_streaming());

    try fx.feedLine(key, "{\"type\":\"event\",\"event\":{\"kind\":\"turnFinished\",\"payload\":{\"success\":true}}}");
    drainEffects(&model, &fx);
    try testing.expectEqual(@as(u32, 0), model.queuedCount(id));
    try testing.expect(model.is_streaming());
    try testing.expectEqual(main.ReplyPath.daemon, model.reply_path);
    try testing.expectEqual(@as(usize, 2), countRole(&model, .user));
    var found_follow_up = false;
    var i: usize = 0;
    while (fx.pendingSpawnAt(i)) |spawn| : (i += 1) {
        if (spawn.key == key) continue;
        if (isSaveOnlyStdin(spawn.stdin)) continue;
        try testing.expect(std.mem.indexOf(u8, spawn.stdin, "queued follow-up") != null);
        try testing.expect(std.mem.indexOf(u8, spawn.stdin, "loadTaskState") != null);
        found_follow_up = true;
    }
    try testing.expect(found_follow_up);
}

test "missing daemon address still uses fx ask when the CLI is present" {
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = main.initialModel();
    model.fx_available = true;
    model.fx_probe_started = true;
    model.setFxPath("fx");
    try testing.expectEqual(@as(usize, 0), model.daemonAddress().len);

    main.update(&model, .{ .draft_edit = .{ .insert_text = "keep fx ask" } }, &fx);
    main.update(&model, .send, &fx);
    try testing.expectEqual(main.ReplyPath.fx, model.reply_path);
    const request = fx.pendingSpawnAt(0).?;
    try testing.expectEqual(main.fx_ask_key, request.key);
    try testing.expect(argvHas(request.argv, "acp"));
    try testing.expect(!argvHas(request.argv, "ask"));
    try testing.expect(!argvHas(request.argv, daemon_proxy.SUBCOMMAND));
}

test "successful fx ask exit records HEAD when project_path is a git work tree" {
    const allocator = testing.allocator;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/rewind-git", .{tmp.sub_path[0..]});
    const expected = try initTestGitRepo(allocator, testing.io, project);
    defer allocator.free(expected);
    var dir_buf: [256]u8 = undefined;
    const dir = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-rewind", .{tmp.sub_path[0..]});

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.task_state_loaded = true;
    model.setStoreDir(dir);
    model.store_io = testing.io;
    model.fx_available = true;
    model.fx_probe_started = true;
    model.setFxPath("fx");
    const id = model.addSession("rewind git", .fx);
    if (model.sessionById(id)) |session| session.setProjectPath(project);
    model.selected = id;

    main.update(&model, .{ .draft_edit = .{ .insert_text = "record this head" } }, &fx);
    main.update(&model, .send, &fx);
    try testing.expect(model.is_streaming());
    try fx.feedExit(main.fx_ask_key, 0);
    drainEffects(&model, &fx);
    try testing.expect(!model.is_streaming());

    const live = model.sessionById(id).?;
    try testing.expectEqual(@as(usize, 1), live.rewind_ref_count);
    try testing.expectEqualStrings(expected, live.rewindRefs()[0].sha());
    try testing.expectEqualStrings(rewind.recorded_ref, live.rewindRefs()[0].refName());
    try testing.expect(live.rewindRefs()[0].recorded_at > 0);

    var loaded = Model{};
    loaded.setStoreDir(dir);
    try testing.expectEqual(store.LoadKind.loaded, store.loadCatalog(&loaded, allocator, testing.io));
    try testing.expectEqualStrings(expected, loaded.session_store[0].rewindRefs()[0].sha());
    store.hydrateSession(&loaded, id, allocator, testing.io);
    try testing.expectEqualStrings(expected, loaded.session_store[0].rewindRefs()[0].sha());
}

test "non-git project_path records no rewind ref after a successful exit" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/plain", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(testing.io, project);

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = testing.io;
    model.fx_available = true;
    model.fx_probe_started = true;
    model.setFxPath("fx");
    const id = model.addSession("no git", .fx);
    if (model.sessionById(id)) |session| session.setProjectPath(project);
    model.selected = id;

    main.update(&model, .{ .draft_edit = .{ .insert_text = "no snapshot" } }, &fx);
    main.update(&model, .send, &fx);
    try fx.feedExit(main.fx_ask_key, 0);
    drainEffects(&model, &fx);
    try testing.expect(!model.is_streaming());
    try testing.expectEqual(@as(usize, 0), model.sessionById(id).?.rewind_ref_count);
}

test "failed or cancelled turns do not record a rewind ref" {
    const allocator = testing.allocator;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/rewind-fail", .{tmp.sub_path[0..]});
    const expected = try initTestGitRepo(allocator, testing.io, project);
    defer allocator.free(expected);

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = testing.io;
    model.fx_available = true;
    model.fx_probe_started = true;
    model.setFxPath("fx");
    const id = model.addSession("rewind fail", .fx);
    if (model.sessionById(id)) |session| session.setProjectPath(project);
    model.selected = id;

    main.update(&model, .{ .draft_edit = .{ .insert_text = "this will fail" } }, &fx);
    main.update(&model, .send, &fx);
    try fx.feedExit(main.fx_ask_key, 1);
    drainEffects(&model, &fx);
    try testing.expect(!model.is_streaming());
    try testing.expectEqual(@as(usize, 0), model.sessionById(id).?.rewind_ref_count);

    main.update(&model, .{ .draft_edit = .{ .insert_text = "this will stop" } }, &fx);
    main.update(&model, .send, &fx);
    try testing.expect(model.is_streaming());
    main.update(&model, .stop, &fx);
    try testing.expect(!model.is_streaming());
    try testing.expectEqual(@as(usize, 0), model.sessionById(id).?.rewind_ref_count);
}

fn initTestGitRepo(allocator: std.mem.Allocator, io: std.Io, path: []const u8) ![]u8 {
    try std.Io.Dir.cwd().createDirPath(io, path);
    try runGit(allocator, io, &.{ "git", "-C", path, "init" });
    var readme_buf: [std.fs.max_path_bytes]u8 = undefined;
    const readme = try std.fmt.bufPrint(&readme_buf, "{s}{s}README", .{ path, std.fs.path.sep_str });
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = readme, .data = "rewind\n" });
    try runGit(allocator, io, &.{ "git", "-C", path, "add", "README" });
    try runGit(allocator, io, &.{
        "git",
        "-C",
        path,
        "-c",
        "user.email=rewind@test",
        "-c",
        "user.name=Rewind",
        "-c",
        "commit.gpgsign=false",
        "commit",
        "-m",
        "init",
    });
    var sha_buf: [rewind.max_sha]u8 = undefined;
    const sha = rewind.revParseHead(allocator, io, path, &sha_buf) orelse return error.GitHead;
    return allocator.dupe(u8, sha);
}

fn runGit(allocator: std.mem.Allocator, io: std.Io, argv: []const []const u8) !void {
    const result = try std.process.run(allocator, io, .{
        .argv = argv,
        .stdout_limit = .limited(1024),
        .stderr_limit = .limited(4096),
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    if (result.term != .exited or result.term.exited != 0) return error.GitFailed;
}

fn isLoadOnlyStdin(stdin: []const u8) bool {
    return std.mem.indexOf(u8, stdin, "\"type\":\"loadTaskState\"") != null and
        std.mem.indexOf(u8, stdin, "\"type\":\"prompt\"") == null and
        std.mem.indexOf(u8, stdin, "\"type\":\"saveTaskState\"") == null;
}

fn findLoadOnlySpawn(fx: *Effects) ?@TypeOf(fx.pendingSpawnAt(0).?) {
    var i: usize = 0;
    while (fx.pendingSpawnAt(i)) |spawn| : (i += 1) {
        if (isLoadOnlyStdin(spawn.stdin)) return spawn;
    }
    return null;
}

fn isHydrateOnlyStdin(stdin: []const u8) bool {
    return std.mem.indexOf(u8, stdin, "\"type\":\"hydrateSession\"") != null and
        std.mem.indexOf(u8, stdin, "\"type\":\"prompt\"") == null and
        std.mem.indexOf(u8, stdin, "\"type\":\"saveTaskState\"") == null;
}

fn findHydrateOnlySpawn(fx: *Effects) ?@TypeOf(fx.pendingSpawnAt(0).?) {
    var i: usize = 0;
    while (fx.pendingSpawnAt(i)) |spawn| : (i += 1) {
        if (isHydrateOnlyStdin(spawn.stdin)) return spawn;
    }
    return null;
}

const fake_hydrate_line =
    \\{"type":"response","requestId":"00000000-0000-0000-0000-000000000011","outcome":{"status":"ok","payload":{"type":"session","session":{"id":"00000000-0000-0000-0000-000000000007","title":"from daemon","messages":[{"id":"00000000-0000-0000-0000-000000000001","role":"user","content":"trace the listener"},{"id":"00000000-0000-0000-0000-000000000002","role":"assistant","content":"looking at reconnect"}],"turns":[{"id":"00000000-0000-0000-0000-000000000003","turn_count":1,"status":"completed","started_at":0}],"queued_messages":[{"id":"00000000-0000-0000-0000-000000000004","content":"then the composer","created_at":0}]}}}}
;

const fake_task_state_line =
    \\{"type":"response","requestId":"00000000-0000-0000-0000-000000000010","outcome":{"status":"ok","payload":{"type":"taskState","projects":[{"id":"00000000-0000-0000-0000-000000000007","name":"faku","path":"/tmp/from-daemon","created_at":0}],"sessions":[{"id":"00000000-0000-0000-0000-000000000007","title":"from daemon","project_id":"00000000-0000-0000-0000-000000000007","provider":"fx","runtime_mode":"fullAccess","status":"idle","created_at":0,"updated_at":0,"has_started":true}],"defaultCwd":"/tmp","projectlessRoot":null}}}
;

test "missing catalog plus daemon address records hello and loadTaskState on spawn stdin" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-load-missing", .{tmp.sub_path[0..]});

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = main.initialModel();
    model.setStoreDir(dir);
    model.store_io = testing.io;
    model.setDaemonAddress("127.0.0.1:8787");
    model.setDaemonToken("secret");
    model.setSidecarPath("faku");
    try testing.expectEqual(store.LoadKind.missing, store.boot(&model, testing.allocator, testing.io));
    try testing.expectEqual(@as(u32, 2), model.session_count);
    try testing.expectEqualStrings("port waku to zig", model.selected_title());

    store.maybeLoadDaemonCatalog(&model, &fx);
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());
    const spawn = findLoadOnlySpawn(&fx) orelse return error.LoadSpawnMissing;
    try testing.expect(argvHas(spawn.argv, daemon_proxy.SUBCOMMAND));
    try testing.expect(argvHas(spawn.argv, "127.0.0.1:8787"));
    try testing.expect(std.mem.indexOf(u8, spawn.stdin, "\"type\":\"hello\"") != null);
    try testing.expect(std.mem.indexOf(u8, spawn.stdin, "\"token\":\"secret\"") != null);
    try testing.expect(std.mem.indexOf(u8, spawn.stdin, "\"type\":\"loadTaskState\"") != null);
    try testing.expect(std.mem.indexOf(u8, spawn.stdin, daemon_proxy.LOAD_REQUEST_ID) != null);
    try testing.expect(std.mem.indexOf(u8, spawn.stdin, "\"type\":\"prompt\"") == null);
    try testing.expect(spawn.key != model.daemon_spawn_key);
    try testing.expectEqual(spawn.key, model.daemon_load_key);
}

test "last_daemon_address with a missing catalog still records loadTaskState" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-load-last", .{tmp.sub_path[0..]});

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = main.initialModel();
    model.setStoreDir(dir);
    model.store_io = testing.io;
    model.setLastDaemonAddress("10.0.0.2:9");
    model.setSidecarPath("faku");
    try testing.expectEqual(@as(usize, 0), model.daemonAddress().len);
    try testing.expectEqual(store.LoadKind.missing, store.boot(&model, testing.allocator, testing.io));
    store.maybeLoadDaemonCatalog(&model, &fx);
    const spawn = findLoadOnlySpawn(&fx) orelse return error.LoadSpawnMissing;
    try testing.expect(argvHas(spawn.argv, "10.0.0.2:9"));
    try testing.expect(std.mem.indexOf(u8, spawn.stdin, "\"type\":\"loadTaskState\"") != null);
}

test "fake loadTaskState response installs daemon skeletons and not demos" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-load-apply", .{tmp.sub_path[0..]});

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = main.initialModel();
    model.setStoreDir(dir);
    model.store_io = testing.io;
    model.setDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    try testing.expectEqual(store.LoadKind.missing, store.boot(&model, testing.allocator, testing.io));
    store.maybeLoadDaemonCatalog(&model, &fx);
    const spawn = findLoadOnlySpawn(&fx) orelse return error.LoadSpawnMissing;

    try fx.feedLine(spawn.key, fake_task_state_line);
    drainEffects(&model, &fx);
    try testing.expectEqual(@as(u32, 1), model.session_count);
    try testing.expectEqual(@as(u32, 7), model.session_store[0].id);
    try testing.expectEqualStrings("from daemon", model.session_store[0].title());
    try testing.expectEqual(main.Provider.fx, model.session_store[0].provider);
    try testing.expectEqualStrings("/tmp/from-daemon", model.session_store[0].projectPath());
    try testing.expect(model.session_store[0].hasStarted());
    try testing.expect(!model.session_store[0].detail_loaded);
    try testing.expectEqual(@as(u32, 0), model.turn_count);
    try testing.expect(model.task_state_loaded);
    try testing.expect(!model.pending_daemon_catalog);
}

test "missing catalog without a daemon address still uses demos" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-load-demos", .{tmp.sub_path[0..]});

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = main.initialModel();
    model.setStoreDir(dir);
    model.store_io = testing.io;
    try testing.expectEqual(@as(usize, 0), model.daemonAddress().len);
    try testing.expectEqual(@as(usize, 0), model.lastDaemonAddress().len);
    try testing.expectEqual(store.LoadKind.missing, store.boot(&model, testing.allocator, testing.io));
    store.maybeLoadDaemonCatalog(&model, &fx);
    try testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
    try testing.expectEqual(@as(u32, 2), model.session_count);
    try testing.expectEqualStrings("port waku to zig", model.selected_title());
    try testing.expect(model.task_state_loaded);
}

test "failed loadTaskState sidecar keeps the demo sessions" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-load-fail", .{tmp.sub_path[0..]});

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = main.initialModel();
    model.setStoreDir(dir);
    model.store_io = testing.io;
    model.setDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    try testing.expectEqual(store.LoadKind.missing, store.boot(&model, testing.allocator, testing.io));
    store.maybeLoadDaemonCatalog(&model, &fx);
    const spawn = findLoadOnlySpawn(&fx) orelse return error.LoadSpawnMissing;
    try fx.feedExit(spawn.key, 1);
    drainEffects(&model, &fx);
    try testing.expectEqual(@as(u32, 2), model.session_count);
    try testing.expectEqualStrings("port waku to zig", model.selected_title());
    try testing.expect(model.task_state_loaded);
    try testing.expect(!model.pending_daemon_catalog);
}

test "existing local catalog is not replaced by a daemon load" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-load-local", .{tmp.sub_path[0..]});

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var source = Model{};
    source.task_state_loaded = true;
    source.setStoreDir(dir);
    source.store_io = testing.io;
    const id = source.addSession("local catalog", .fx);
    _ = source.appendTurn(id, .user, "already persisted");
    try store.saveSession(&source, id, testing.allocator, testing.io);

    var model = main.initialModel();
    model.setStoreDir(dir);
    model.store_io = testing.io;
    model.setDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    try testing.expectEqual(store.LoadKind.loaded, store.boot(&model, testing.allocator, testing.io));
    store.maybeLoadDaemonCatalog(&model, &fx);
    try testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
    try testing.expectEqual(@as(u32, 1), model.session_count);
    try testing.expectEqualStrings("local catalog", model.session_store[0].title());

    store.applyDaemonCatalogLine(&model, fake_task_state_line);
    try testing.expectEqual(@as(u32, 1), model.session_count);
    try testing.expectEqualStrings("local catalog", model.session_store[0].title());
}

test "corrupt catalog plus a daemon address still refuses overwrite" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-load-corrupt", .{tmp.sub_path[0..]});

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    try std.Io.Dir.cwd().createDirPath(testing.io, dir);
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = store.catalogPath(dir, &path_buf).?;
    try std.Io.Dir.cwd().writeFile(testing.io, .{ .sub_path = path, .data = "{not json" });

    var model = main.initialModel();
    model.setStoreDir(dir);
    model.store_io = testing.io;
    model.setDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    try testing.expectEqual(store.LoadKind.failed, store.boot(&model, testing.allocator, testing.io));
    store.maybeLoadDaemonCatalog(&model, &fx);
    try testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
    try testing.expect(!model.task_state_loaded);
    try testing.expectEqual(@as(u32, 2), model.session_count);
    try testing.expectEqualStrings("port waku to zig", model.selected_title());

    store.applyDaemonCatalogLine(&model, fake_task_state_line);
    try testing.expectEqual(@as(u32, 2), model.session_count);
    try testing.expectEqualStrings("port waku to zig", model.selected_title());
    try testing.expect(!model.task_state_loaded);
    try testing.expectError(error.TaskStateNotLoaded, store.saveSession(&model, model.selected, testing.allocator, testing.io));
}

test "select empty session plus daemon address records hello and hydrateSession" {
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.fx_probe_started = true;
    model.setDaemonAddress("127.0.0.1:8787");
    model.setDaemonToken("secret");
    model.setSidecarPath("faku");
    const filled = model.addSession("has local turns", .fx);
    _ = model.appendTurn(filled, .user, "already here");
    const empty = model.addSession("empty transcript", .fx);
    model.selected = filled;

    main.update(&model, .{ .select = empty }, &fx);
    const spawn = findHydrateOnlySpawn(&fx) orelse return error.HydrateSpawnMissing;
    try testing.expect(argvHas(spawn.argv, daemon_proxy.SUBCOMMAND));
    try testing.expect(argvHas(spawn.argv, "127.0.0.1:8787"));
    try testing.expect(std.mem.indexOf(u8, spawn.stdin, "\"type\":\"hello\"") != null);
    try testing.expect(std.mem.indexOf(u8, spawn.stdin, "\"token\":\"secret\"") != null);
    try testing.expect(std.mem.indexOf(u8, spawn.stdin, "\"type\":\"hydrateSession\"") != null);
    try testing.expect(std.mem.indexOf(u8, spawn.stdin, daemon_proxy.HYDRATE_REQUEST_ID) != null);
    try testing.expect(std.mem.indexOf(u8, spawn.stdin, "\"type\":\"prompt\"") == null);
    try testing.expectEqual(spawn.key, model.daemon_hydrate_key);
    try testing.expect(spawn.key != model.daemon_spawn_key);
    try testing.expectEqual(empty, model.daemon_hydrate_session);
}

test "first view of a catalog session with empty local turns records hydrateSession" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-hydrate-first", .{tmp.sub_path[0..]});

    var source = Model{};
    source.task_state_loaded = true;
    source.setStoreDir(dir);
    source.store_io = testing.io;
    const id = source.addSession("skeleton only", .fx);
    if (source.sessionById(id)) |session| session.has_started = true;
    try store.saveSession(&source, id, testing.allocator, testing.io);

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = main.initialModel();
    model.setStoreDir(dir);
    model.store_io = testing.io;
    model.setDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    try testing.expectEqual(store.LoadKind.loaded, store.boot(&model, testing.allocator, testing.io));
    try testing.expectEqual(@as(u32, 0), model.turnCount(id));
    store.maybeHydrateDaemonSession(&model, &fx, model.selected);
    const spawn = findHydrateOnlySpawn(&fx) orelse return error.HydrateSpawnMissing;
    try testing.expect(std.mem.indexOf(u8, spawn.stdin, "\"type\":\"hydrateSession\"") != null);
}

test "last_daemon_address with an empty selected session still records hydrateSession" {
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.fx_probe_started = true;
    model.setLastDaemonAddress("10.0.0.2:9");
    model.setSidecarPath("faku");
    const empty = model.addSession("empty last addr", .fx);
    try testing.expectEqual(@as(usize, 0), model.daemonAddress().len);
    main.update(&model, .{ .select = empty }, &fx);
    const spawn = findHydrateOnlySpawn(&fx) orelse return error.HydrateSpawnMissing;
    try testing.expect(argvHas(spawn.argv, "10.0.0.2:9"));
    try testing.expect(std.mem.indexOf(u8, spawn.stdin, "\"type\":\"hydrateSession\"") != null);
}

test "fake hydrateSession response installs turns into an empty session" {
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.fx_probe_started = true;
    model.setDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    const empty = model.addSession("empty hydrate", .fx);
    main.update(&model, .{ .select = empty }, &fx);
    const spawn = findHydrateOnlySpawn(&fx) orelse return error.HydrateSpawnMissing;

    try fx.feedLine(spawn.key, fake_hydrate_line);
    drainEffects(&model, &fx);
    try testing.expectEqual(@as(u32, 2), model.turnCount(empty));
    try testing.expectEqual(main.Role.user, model.turn_store[0].role);
    try testing.expectEqualStrings("trace the listener", model.turn_store[0].text());
    try testing.expectEqual(main.Role.assistant, model.turn_store[1].role);
    try testing.expectEqualStrings("looking at reconnect", model.turn_store[1].text());
    try testing.expectEqual(@as(u32, 1), model.queuedCount(empty));
    try testing.expectEqualStrings("then the composer", model.firstQueuedText(empty));
    try testing.expect(model.sessionById(empty).?.detail_loaded);
}

test "select with local turns already present does not spawn hydrateSession" {
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.fx_probe_started = true;
    model.setDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    const filled = model.addSession("local wins", .fx);
    _ = model.appendTurn(filled, .user, "keep me");
    _ = model.appendTurn(filled, .assistant, "already hydrated");
    main.update(&model, .{ .select = filled }, &fx);
    try testing.expect(findHydrateOnlySpawn(&fx) == null);
    try testing.expectEqual(@as(u32, 0), model.daemon_hydrate_key);
    try testing.expectEqual(@as(u32, 2), model.turnCount(filled));
    try testing.expectEqualStrings("keep me", model.turn_store[0].text());
}

test "failed hydrate sidecar leaves turns empty and keeps the catalog" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-hydrate-fail", .{tmp.sub_path[0..]});

    var source = Model{};
    source.task_state_loaded = true;
    source.setStoreDir(dir);
    source.store_io = testing.io;
    const kept = source.addSession("local catalog", .fx);
    _ = source.appendTurn(kept, .user, "already persisted");
    try store.saveSession(&source, kept, testing.allocator, testing.io);

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.task_state_loaded = true;
    model.setStoreDir(dir);
    model.store_io = testing.io;
    model.fx_probe_started = true;
    model.setDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    try testing.expectEqual(store.LoadKind.loaded, store.loadCatalog(&model, testing.allocator, testing.io));
    const empty = model.addSession("empty fail", .fx);
    main.update(&model, .{ .select = empty }, &fx);
    const spawn = findHydrateOnlySpawn(&fx) orelse return error.HydrateSpawnMissing;
    try fx.feedExit(spawn.key, 1);
    drainEffects(&model, &fx);
    try testing.expectEqual(@as(u32, 0), model.turnCount(empty));
    try testing.expectEqual(@as(u32, 2), model.session_count);
    try testing.expectEqualStrings("local catalog", model.session_store[0].title());
    try testing.expectEqual(kept, model.session_store[0].id);

    var reread = Model{};
    reread.setStoreDir(dir);
    try testing.expectEqual(store.LoadKind.loaded, store.loadCatalog(&reread, testing.allocator, testing.io));
    try testing.expectEqual(@as(u32, 1), reread.session_count);
    try testing.expectEqualStrings("local catalog", reread.session_store[0].title());
}

test "the view lays out through the canvas engine" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();

    var model = main.initialModel();
    const tree = try buildTree(arena_state.allocator(), &model);

    var nodes: [128]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(tree.root, native_sdk.geometry.RectF.init(0, 0, 1200, 800), &nodes);
    try testing.expect(layout.nodes.len > 0);

    const send = try expectByText(tree.root, .button, "Send");
    var saw_send = false;
    for (layout.nodes) |node| {
        if (node.widget.id == send.id) saw_send = true;
    }
    try testing.expect(saw_send);
}
