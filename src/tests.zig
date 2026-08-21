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

fn widgetName(widget: canvas.Widget) []const u8 {
    if (widget.semantics.label.len > 0) return widget.semantics.label;
    return widget.text;
}

fn findByText(widget: canvas.Widget, kind: canvas.WidgetKind, text: []const u8) ?canvas.Widget {
    if (widget.kind == kind and std.mem.eql(u8, widgetName(widget), text)) return widget;
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
    const name = widgetName(widget);
    if (name.len > 0) {
        std.debug.print("{d} {t} [{s}]\n", .{ depth, widget.kind, name });
    }
    for (widget.children) |child| dumpTexts(child, depth + 1);
}

fn isPressable(kind: canvas.WidgetKind) bool {
    return kind == .button or kind == .list_item;
}

fn findPressableContaining(widget: canvas.Widget, text: []const u8) ?canvas.Widget {
    if (isPressable(widget.kind)) {
        if (std.mem.eql(u8, widgetName(widget), text)) return widget;
        if (findByText(widget, .text, text) != null) return widget;
    }
    for (widget.children) |child| {
        if (findPressableContaining(child, text)) |found| return found;
    }
    return null;
}

fn expectButton(widget: canvas.Widget, text: []const u8) !canvas.Widget {
    return findPressableContaining(widget, text) orelse {
        std.debug.print("no pressable containing \"{s}\"\n", .{text});
        dumpTexts(widget, 0);
        return error.WidgetNotFound;
    };
}

fn findByKind(widget: canvas.Widget, kind: canvas.WidgetKind) ?canvas.Widget {
    if (widget.kind == kind) return widget;
    for (widget.children) |child| {
        if (findByKind(child, kind)) |found| return found;
    }
    return null;
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
    _ = try expectByText(tree.root, .text, "Today");
    _ = try expectButton(tree.root, "New Task");
    _ = try expectButton(tree.root, "Search");
    _ = try expectButton(tree.root, "port waku to zig");
    _ = try expectButton(tree.root, "fix auth listener");
    _ = try expectByText(tree.root, .button, "Send");
    _ = try expectByText(tree.root, .text, "fx");
    _ = try expectByText(tree.root, .button, "Full access");
    _ = try expectByText(tree.root, .button, "Build");
    _ = try expectByText(tree.root, .button, "Local");
    try testing.expect(findByKind(tree.root, .status_bar) == null);
    if (findByKind(tree.root, .textarea)) |composer| {
        try testing.expectEqualStrings("Do anything...", composer.placeholder);
    }

    const new_btn = try expectButton(tree.root, "New Task");
    main.update(&model, tree.msgForPointer(new_btn.id, .up).?, &fx);
    try testing.expectEqual(@as(u32, 3), model.session_count);
    try testing.expectEqualStrings("untitled", model.selected_title());
    try testing.expectEqualStrings("New task", model.header_title());
    try testing.expectEqualStrings("fx", model.selected_provider());
    try testing.expectEqual(main.Provider.fx, model.session_store[2].provider);

    tree = try buildTree(arena, &model);
    _ = try expectByText(tree.root, .text, "New task");
    _ = try expectByText(tree.root, .text, "What should we build?");
    _ = try expectButton(tree.root, "New task");
    try testing.expect(findByText(tree.root, .text, "untitled") == null);
    try testing.expect(findByText(tree.root, .text, "Faku") == null);

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
    try testing.expect(findByKind(tree.root, .status_bar) == null);
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

test "daemon address send puts hello attachSession and prompt on spawn stdin" {
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
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"type\":\"attachSession\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, daemon_proxy.ATTACH_REQUEST_ID) != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"type\":\"prompt\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "trace the listener") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"type\":\"loadTaskState\"") == null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"type\":\"start\"") == null);
    const attach_at = std.mem.indexOf(u8, request.stdin, "\"type\":\"attachSession\"").?;
    const prompt_at = std.mem.indexOf(u8, request.stdin, "\"type\":\"prompt\"").?;
    try testing.expect(attach_at < prompt_at);
    try testing.expectEqualStrings("127.0.0.1:8787", model.lastDaemonAddress());
    try testing.expectEqual(@as(usize, 0), model.sessionById(id).?.runtimeId().len);
}

test "fake sessionRuntime persists a runtime id on the session" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-runtime", .{tmp.sub_path[0..]});

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
    const id = model.addSession("runtime persist", .fx);
    model.selected = id;
    main.update(&model, .{ .draft_edit = .{ .insert_text = "first prompt" } }, &fx);
    main.update(&model, .send, &fx);
    const key = model.daemon_spawn_key;
    try testing.expectEqual(@as(usize, 0), model.sessionById(id).?.runtimeId().len);

    try fx.feedLine(key, "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000012\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"sessionRuntime\",\"runtimeId\":null,\"supportsSteer\":false}}}");
    drainEffects(&model, &fx);
    try testing.expectEqual(@as(usize, 0), model.sessionById(id).?.runtimeId().len);

    try fx.feedLine(key, "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000012\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"ack\"}}}");
    drainEffects(&model, &fx);
    try testing.expectEqual(@as(usize, 0), model.sessionById(id).?.runtimeId().len);

    try fx.feedLine(key, "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000012\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"sessionRuntime\",\"runtimeId\":\"00000000-0000-0000-0000-000000000003\",\"supportsSteer\":true}}}");
    drainEffects(&model, &fx);
    try testing.expectEqualStrings("00000000-0000-0000-0000-000000000003", model.sessionById(id).?.runtimeId());
    try testing.expect(model.is_streaming());

    try fx.feedLine(key, "{\"type\":\"event\",\"event\":{\"kind\":\"turnFinished\",\"payload\":{\"success\":true}}}");
    drainEffects(&model, &fx);
    try testing.expect(!model.is_streaming());

    var loaded = Model{};
    loaded.setStoreDir(dir);
    try testing.expectEqual(store.LoadKind.loaded, store.loadCatalog(&loaded, testing.allocator, testing.io));
    try testing.expectEqualStrings("00000000-0000-0000-0000-000000000003", loaded.session_store[0].runtimeId());

    main.update(&model, .{ .draft_edit = .{ .insert_text = "second prompt" } }, &fx);
    main.update(&model, .send, &fx);
    var found_second = false;
    var i: usize = 0;
    while (fx.pendingSpawnAt(i)) |spawn| : (i += 1) {
        if (isSaveOnlyStdin(spawn.stdin)) continue;
        if (std.mem.indexOf(u8, spawn.stdin, "second prompt") == null) continue;
        try testing.expect(std.mem.indexOf(u8, spawn.stdin, "\"type\":\"attachSession\"") != null);
        try testing.expect(std.mem.indexOf(u8, spawn.stdin, "\"type\":\"prompt\"") != null);
        try testing.expect(std.mem.indexOf(u8, spawn.stdin, "\"runtimeId\":\"00000000-0000-0000-0000-000000000003\"") != null);
        found_second = true;
    }
    try testing.expect(found_second);
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
        try testing.expect(std.mem.indexOf(u8, spawn.stdin, "\"type\":\"attachSession\"") != null);
        try testing.expect(std.mem.indexOf(u8, spawn.stdin, "\"type\":\"prompt\"") != null);
        try testing.expect(std.mem.indexOf(u8, spawn.stdin, "\"type\":\"loadTaskState\"") == null);
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
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"type\":\"attachSession\"") == null);
}

test "missing daemon address does not attach even when last_daemon_address is set" {
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = main.initialModel();
    model.fx_available = true;
    model.fx_probe_started = true;
    model.setFxPath("fx");
    model.setLastDaemonAddress("127.0.0.1:8787");
    try testing.expectEqual(@as(usize, 0), model.daemonAddress().len);

    main.update(&model, .{ .draft_edit = .{ .insert_text = "do not attach" } }, &fx);
    main.update(&model, .send, &fx);
    try testing.expectEqual(main.ReplyPath.fx, model.reply_path);
    const request = fx.pendingSpawnAt(0).?;
    try testing.expect(!argvHas(request.argv, daemon_proxy.SUBCOMMAND));
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"type\":\"attachSession\"") == null);
    try testing.expectEqual(@as(usize, 0), model.session_store[0].runtimeId().len);
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

fn isCloseOnlyStdin(stdin: []const u8) bool {
    return std.mem.indexOf(u8, stdin, "\"type\":\"closeSession\"") != null and
        std.mem.indexOf(u8, stdin, "\"type\":\"prompt\"") == null and
        std.mem.indexOf(u8, stdin, "\"type\":\"attachSession\"") == null;
}

fn findCloseOnlySpawn(fx: *Effects) ?@TypeOf(fx.pendingSpawnAt(0).?) {
    var i: usize = 0;
    while (fx.pendingSpawnAt(i)) |spawn| : (i += 1) {
        if (isCloseOnlyStdin(spawn.stdin)) return spawn;
    }
    return null;
}

test "remove plus daemon address records hello and closeSession" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-close-addr", .{tmp.sub_path[0..]});

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
    const kept = model.addSession("keep me", .fx);
    _ = model.appendTurn(kept, .user, "stays");
    try store.saveSession(&model, kept, testing.allocator, testing.io);
    const gone = model.addSession("remove me", .fx);
    _ = model.appendTurn(gone, .user, "bye");
    try store.saveSession(&model, gone, testing.allocator, testing.io);

    main.update(&model, .{ .remove_session = gone }, &fx);
    const spawn = findCloseOnlySpawn(&fx) orelse return error.CloseSpawnMissing;
    try testing.expect(argvHas(spawn.argv, daemon_proxy.SUBCOMMAND));
    try testing.expect(argvHas(spawn.argv, "127.0.0.1:8787"));
    try testing.expect(std.mem.indexOf(u8, spawn.stdin, "\"type\":\"hello\"") != null);
    try testing.expect(std.mem.indexOf(u8, spawn.stdin, "\"token\":\"secret\"") != null);
    try testing.expect(std.mem.indexOf(u8, spawn.stdin, "\"type\":\"closeSession\"") != null);
    try testing.expect(std.mem.indexOf(u8, spawn.stdin, "\"command\":{\"type\":\"closeSession\"}") != null);
    var gone_id_buf: [36]u8 = undefined;
    try testing.expect(std.mem.indexOf(u8, spawn.stdin, daemon_proxy.wireUuid(gone, &gone_id_buf)) != null);
    try testing.expect(std.mem.indexOf(u8, spawn.stdin, "\"type\":\"prompt\"") == null);
    try testing.expect(std.mem.indexOf(u8, spawn.stdin, "\"type\":\"attachSession\"") == null);
    try testing.expect(std.mem.indexOf(u8, spawn.stdin, "\"type\":\"removeSession\"") == null);
    try testing.expect(spawn.key != model.daemon_spawn_key);
    try testing.expect(model.sessionById(gone) == null);
    try testing.expectEqual(@as(u32, 1), model.session_count);
    try testing.expectEqual(kept, model.session_store[0].id);
}

test "last_daemon_address with a local remove still records closeSession" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-close-last", .{tmp.sub_path[0..]});

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.task_state_loaded = true;
    model.setStoreDir(dir);
    model.store_io = testing.io;
    model.setLastDaemonAddress("10.0.0.2:9");
    model.setSidecarPath("faku");
    const id = model.addSession("last addr close", .fx);
    _ = model.appendTurn(id, .user, "started");
    try store.saveSession(&model, id, testing.allocator, testing.io);
    try testing.expectEqual(@as(usize, 0), model.daemonAddress().len);

    main.update(&model, .{ .remove_session = id }, &fx);
    const spawn = findCloseOnlySpawn(&fx) orelse return error.CloseSpawnMissing;
    try testing.expect(argvHas(spawn.argv, "10.0.0.2:9"));
    try testing.expect(std.mem.indexOf(u8, spawn.stdin, "\"type\":\"hello\"") != null);
    try testing.expect(std.mem.indexOf(u8, spawn.stdin, "\"type\":\"closeSession\"") != null);
    try testing.expect(model.sessionById(id) == null);
}

test "remove without a daemon address does not spawn closeSession" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-close-local", .{tmp.sub_path[0..]});

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.task_state_loaded = true;
    model.setStoreDir(dir);
    model.store_io = testing.io;
    const kept = model.addSession("stays local", .fx);
    _ = model.appendTurn(kept, .user, "keep");
    try store.saveSession(&model, kept, testing.allocator, testing.io);
    const gone = model.addSession("drop local", .fx);
    _ = model.appendTurn(gone, .user, "gone");
    try store.saveSession(&model, gone, testing.allocator, testing.io);

    main.update(&model, .{ .remove_session = gone }, &fx);
    try testing.expect(findCloseOnlySpawn(&fx) == null);
    try testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
    try testing.expect(model.sessionById(gone) == null);

    var loaded = Model{};
    loaded.setStoreDir(dir);
    try testing.expectEqual(store.LoadKind.loaded, store.loadCatalog(&loaded, testing.allocator, testing.io));
    try testing.expectEqual(@as(u32, 1), loaded.session_count);
    try testing.expectEqual(kept, loaded.session_store[0].id);
    try testing.expectEqualStrings("stays local", loaded.session_store[0].title());
}

test "closeSession sidecar failure leaves the local row gone" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-close-fail", .{tmp.sub_path[0..]});

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.task_state_loaded = true;
    model.setStoreDir(dir);
    model.store_io = testing.io;
    model.setDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    const kept = model.addSession("catalog stays", .fx);
    _ = model.appendTurn(kept, .user, "already persisted");
    try store.saveSession(&model, kept, testing.allocator, testing.io);
    const gone = model.addSession("sidecar fails", .fx);
    _ = model.appendTurn(gone, .user, "drop me");
    try store.saveSession(&model, gone, testing.allocator, testing.io);

    main.update(&model, .{ .remove_session = gone }, &fx);
    const spawn = findCloseOnlySpawn(&fx) orelse return error.CloseSpawnMissing;
    try fx.feedExit(spawn.key, 1);
    drainEffects(&model, &fx);
    try testing.expect(model.sessionById(gone) == null);
    try testing.expectEqual(@as(u32, 1), model.session_count);
    try testing.expectEqual(kept, model.session_store[0].id);

    var reread = Model{};
    reread.setStoreDir(dir);
    try testing.expectEqual(store.LoadKind.loaded, store.loadCatalog(&reread, testing.allocator, testing.io));
    try testing.expectEqual(@as(u32, 1), reread.session_count);
    try testing.expectEqual(kept, reread.session_store[0].id);
    try testing.expectEqualStrings("catalog stays", reread.session_store[0].title());
    try testing.expect(reread.sessionById(gone) == null);
}

test "stop and select do not spawn closeSession" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-close-not-stop", .{tmp.sub_path[0..]});

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
    const first = model.addSession("first", .fx);
    _ = model.appendTurn(first, .user, "already here");
    try store.saveSession(&model, first, testing.allocator, testing.io);
    const second = model.addSession("second", .fx);
    _ = model.appendTurn(second, .user, "also here");
    try store.saveSession(&model, second, testing.allocator, testing.io);
    model.selected = first;

    main.update(&model, .{ .select = second }, &fx);
    try testing.expect(findCloseOnlySpawn(&fx) == null);

    model.phase = .streaming;
    model.streaming_session = second;
    if (model.sessionById(second)) |session| session.busy = true;
    main.update(&model, .stop, &fx);
    try testing.expect(findCloseOnlySpawn(&fx) == null);
    try testing.expectEqual(@as(u32, 2), model.session_count);
    try testing.expect(model.sessionById(first) != null);
    try testing.expect(model.sessionById(second) != null);
}

test "the view lays out through the canvas engine" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();

    var model = main.initialModel();
    const tree = try buildTree(arena_state.allocator(), &model);

    var nodes: [256]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(
        tree.root,
        native_sdk.geometry.RectF.init(0, 0, main.window_width, main.window_height),
        &nodes,
    );
    try testing.expect(layout.nodes.len > 0);

    const send = try expectByText(tree.root, .button, "Send");
    var saw_send = false;
    for (layout.nodes) |node| {
        if (node.widget.id == send.id) saw_send = true;
    }
    try testing.expect(saw_send);
}

test "cmd-n and ctrl-n create a session via onKey" {
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = main.initialModel();
    try testing.expectEqual(@as(u32, 2), model.session_count);

    const plain_n = canvas.WidgetKeyboardEvent{ .phase = .key_down, .key = "n" };
    try testing.expectEqual(@as(?Msg, null), main.onKey(plain_n));

    const cmd_n = canvas.WidgetKeyboardEvent{
        .phase = .key_down,
        .key = "n",
        .modifiers = .{ .super = true },
    };
    try testing.expectEqual(Msg.new_session, main.onKey(cmd_n).?);
    main.update(&model, main.onKey(cmd_n).?, &fx);
    try testing.expectEqual(@as(u32, 3), model.session_count);
    try testing.expectEqualStrings("untitled", model.selected_title());
    try testing.expectEqualStrings("New task", model.header_title());
    try testing.expectEqual(main.Provider.fx, model.session_store[2].provider);

    const ctrl_n = canvas.WidgetKeyboardEvent{
        .phase = .key_down,
        .key = "n",
        .modifiers = .{ .control = true },
    };
    main.update(&model, main.onKey(ctrl_n).?, &fx);
    try testing.expectEqual(@as(u32, 4), model.session_count);
    try testing.expectEqualStrings("fx", model.selected_provider());

    const escape = canvas.WidgetKeyboardEvent{ .phase = .key_down, .key = "escape" };
    try testing.expectEqual(Msg.stop, main.onKey(escape).?);
}

fn expectLaidOutHeight(root: canvas.Widget, id: canvas.ObjectId, height: f32) !void {
    var nodes: [256]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(
        root,
        native_sdk.geometry.RectF.init(0, 0, main.window_width, main.window_height),
        &nodes,
    );
    for (layout.nodes) |node| {
        if (node.widget.id == id) {
            try testing.expectEqual(height, node.frame.height);
            return;
        }
    }
    return error.WidgetNotFound;
}

fn expectRowTitles(rows: []const main.SessionRow, expected: []const []const u8) !void {
    try testing.expectEqual(expected.len, rows.len);
    for (rows, expected) |row, title| {
        try testing.expectEqualStrings(title, row.title);
    }
}

fn expectSidebarTitles(rows: []const main.SidebarRow, expected: []const []const u8) !void {
    try testing.expectEqual(expected.len, rows.len);
    for (rows, expected) |row, title| {
        try testing.expectEqualStrings(title, row.title);
    }
}

test "sidebar search filters the local catalog by title substring" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = main.initialModel();
    try testing.expectEqual(@as(u32, 2), model.session_count);
    try testing.expectEqualStrings("", model.search_query());
    try testing.expect(!model.search_active);

    var rows = model.session_rows(arena);
    try expectRowTitles(rows, &.{ "port waku to zig", "fix auth listener" });

    var tree = try buildTree(arena, &model);
    _ = try expectByText(tree.root, .text, "Today");
    const search_btn = try expectButton(tree.root, "Search");
    try expectLaidOutHeight(tree.root, search_btn.id, 32);

    main.update(&model, tree.msgForPointer(search_btn.id, .up).?, &fx);
    try testing.expect(model.search_active);
    try testing.expectEqualStrings("", model.search_query());
    rows = model.session_rows(arena);
    try expectRowTitles(rows, &.{ "port waku to zig", "fix auth listener" });

    tree = try buildTree(arena, &model);
    _ = try expectByText(tree.root, .text, "Today");
    try testing.expect(findPressableContaining(tree.root, "Search") == null);
    if (findByKind(tree.root, .search_field)) |field| {
        try testing.expectEqualStrings("Search", field.placeholder);
        try expectLaidOutHeight(tree.root, field.id, 32);
    } else return error.WidgetNotFound;

    main.update(&model, .{ .search_edit = .{ .insert_text = "WAKU" } }, &fx);
    try testing.expectEqualStrings("WAKU", model.search_query());
    rows = model.session_rows(arena);
    try expectRowTitles(rows, &.{"port waku to zig"});

    tree = try buildTree(arena, &model);
    _ = try expectButton(tree.root, "port waku to zig");
    try testing.expect(findPressableContaining(tree.root, "fix auth listener") == null);
    _ = try expectByText(tree.root, .text, "Today");

    main.update(&model, .{ .search_edit = .clear }, &fx);
    try testing.expectEqualStrings("", model.search_query());
    try testing.expect(!model.search_active);
    rows = model.session_rows(arena);
    try expectRowTitles(rows, &.{ "port waku to zig", "fix auth listener" });

    main.update(&model, .{ .search_edit = .{ .insert_text = "auth" } }, &fx);
    rows = model.session_rows(arena);
    try expectRowTitles(rows, &.{"fix auth listener"});

    tree = try buildTree(arena, &model);
    const auth = try expectButton(tree.root, "fix auth listener");
    main.update(&model, tree.msgForPointer(auth.id, .up).?, &fx);
    try testing.expectEqualStrings("fix auth listener", model.selected_title());
    try testing.expectEqualStrings("claude", model.selected_provider());
    try testing.expectEqual(@as(usize, 1), countRole(&model, .user));
    try testing.expectEqual(@as(usize, 2), countRole(&model, .assistant));

    main.update(&model, .stop, &fx);
    try testing.expectEqualStrings("", model.search_query());
    try testing.expect(!model.search_active);
    rows = model.session_rows(arena);
    try expectRowTitles(rows, &.{ "port waku to zig", "fix auth listener" });

    tree = try buildTree(arena, &model);
    _ = try expectButton(tree.root, "Search");
    _ = try expectButton(tree.root, "port waku to zig");
    _ = try expectButton(tree.root, "fix auth listener");
}

test "sidebar collapse hides the session list and expand restores it" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = main.initialModel();
    try testing.expect(!model.sidebar_collapsed);
    try testing.expect(model.sidebar_expanded());

    var tree = try buildTree(arena, &model);
    _ = try expectByText(tree.root, .text, "Today");
    _ = try expectButton(tree.root, "Search");
    _ = try expectButton(tree.root, "New Task");
    _ = try expectButton(tree.root, "port waku to zig");
    _ = try expectButton(tree.root, "fix auth listener");
    const collapse = try expectButton(tree.root, "Collapse sidebar");
    main.update(&model, tree.msgForPointer(collapse.id, .up).?, &fx);

    try testing.expect(model.sidebar_collapsed);
    try testing.expect(!model.sidebar_expanded());
    try testing.expectEqual(main.sidebar_rail_width / main.window_width, model.sidebar_split);
    try testing.expectEqual(main.sidebar_rail_width, model.sidebar_pane_min());

    tree = try buildTree(arena, &model);
    try testing.expect(findByText(tree.root, .text, "Today") == null);
    try testing.expect(findPressableContaining(tree.root, "Search") == null);
    try testing.expect(findPressableContaining(tree.root, "New Task") == null);
    try testing.expect(findPressableContaining(tree.root, "port waku to zig") == null);
    try testing.expect(findPressableContaining(tree.root, "fix auth listener") == null);
    _ = try expectByText(tree.root, .text, "port waku to zig");
    const expand = try expectButton(tree.root, "Expand sidebar");
    main.update(&model, tree.msgForPointer(expand.id, .up).?, &fx);

    try testing.expect(!model.sidebar_collapsed);
    try testing.expectEqual(main.sidebar_default_width / main.window_width, model.sidebar_split);

    tree = try buildTree(arena, &model);
    _ = try expectByText(tree.root, .text, "Today");
    _ = try expectButton(tree.root, "Search");
    _ = try expectButton(tree.root, "New Task");
    _ = try expectButton(tree.root, "port waku to zig");
    _ = try expectButton(tree.root, "fix auth listener");
    _ = try expectButton(tree.root, "Collapse sidebar");
}

test "sidebar collapsed flag reloads and hides the session list" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-sidebar-collapse", .{tmp.sub_path[0..]});

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var source = main.initialModel();
    source.task_state_loaded = true;
    source.setStoreDir(dir);
    source.store_io = testing.io;
    try store.saveSession(&source, source.selected, testing.allocator, testing.io);
    source.sidebar_last_width = 320;
    source.sidebar_split = 320 / main.window_width;
    main.update(&source, .toggle_sidebar, &fx);
    try testing.expect(source.sidebar_collapsed);

    var loaded = Model{};
    loaded.setStoreDir(dir);
    loaded.store_io = testing.io;
    try testing.expectEqual(store.LoadKind.loaded, store.loadCatalog(&loaded, testing.allocator, testing.io));
    try testing.expect(loaded.sidebar_collapsed);
    try testing.expectEqual(@as(u32, 320), loaded.sidebarWidthPixels());
    try testing.expectEqual(main.sidebar_rail_width / main.window_width, loaded.sidebar_split);

    const tree = try buildTree(arena, &loaded);
    try testing.expect(findByText(tree.root, .text, "Today") == null);
    try testing.expect(findPressableContaining(tree.root, "Search") == null);
    try testing.expect(findPressableContaining(tree.root, "port waku to zig") == null);
    _ = try expectButton(tree.root, "Expand sidebar");
    _ = try expectByText(tree.root, .text, "port waku to zig");
}

test "sidebar search also matches provider and Esc exits" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = main.initialModel();
    main.update(&model, .{ .search_edit = .{ .insert_text = "claude" } }, &fx);
    try expectRowTitles(model.session_rows(arena), &.{"fix auth listener"});

    const escape = canvas.WidgetKeyboardEvent{ .phase = .key_down, .key = "escape" };
    try testing.expectEqual(Msg.stop, main.onKey(escape).?);
    main.update(&model, main.onKey(escape).?, &fx);
    try testing.expectEqualStrings("", model.search_query());
    try testing.expect(!model.search_active);
    try expectRowTitles(model.session_rows(arena), &.{ "port waku to zig", "fix auth listener" });
}

test "send while busy shows a queued card that dismiss clears" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = main.initialModel();
    const session_id = model.selected;
    main.update(&model, .{ .draft_edit = .{ .insert_text = "first prompt" } }, &fx);
    main.update(&model, .send, &fx);
    try testing.expect(model.is_streaming());

    var tree = try buildTree(arena, &model);
    try testing.expect(findByText(tree.root, .text, "Queued") == null);
    _ = try expectButton(tree.root, "port waku to zig");
    _ = try expectButton(tree.root, "fix auth listener");

    main.update(&model, .{ .draft_edit = .{ .insert_text = "follow up later" } }, &fx);
    main.update(&model, .send, &fx);
    try testing.expect(model.has_queued());
    try testing.expectEqual(@as(u32, 1), model.queuedCount(session_id));
    try testing.expectEqualStrings("follow up later", model.queued_text());

    tree = try buildTree(arena, &model);
    _ = try expectByText(tree.root, .text, "Queued");
    _ = try expectByText(tree.root, .text, "follow up later");
    _ = try expectButton(tree.root, "port waku to zig");
    _ = try expectButton(tree.root, "fix auth listener");

    const dismiss = try expectByText(tree.root, .button, "Dismiss");
    main.update(&model, tree.msgForPointer(dismiss.id, .up).?, &fx);
    try testing.expect(!model.has_queued());
    try testing.expectEqual(@as(u32, 0), model.queuedCount(session_id));
    try testing.expect(model.is_streaming());

    tree = try buildTree(arena, &model);
    try testing.expect(findByText(tree.root, .text, "Queued") == null);
}

fn findByPlaceholder(widget: canvas.Widget, kind: canvas.WidgetKind, placeholder: []const u8) ?canvas.Widget {
    if (widget.kind == kind and std.mem.eql(u8, widget.placeholder, placeholder)) return widget;
    for (widget.children) |child| {
        if (findByPlaceholder(child, kind, placeholder)) |found| return found;
    }
    return null;
}

test "settings gear opens the panel; Esc and gear return to the session" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = main.initialModel();
    try testing.expect(!model.settings_open);

    var tree = try buildTree(arena, &model);
    _ = try expectByText(tree.root, .text, "Today");
    _ = try expectButton(tree.root, "Search");
    _ = try expectByText(tree.root, .button, "Send");
    try testing.expect(findByText(tree.root, .text, "Default model") == null);
    const gear = try expectButton(tree.root, "Settings");
    main.update(&model, tree.msgForPointer(gear.id, .up).?, &fx);
    try testing.expect(model.settings_open);

    tree = try buildTree(arena, &model);
    _ = try expectByText(tree.root, .text, "Today");
    _ = try expectButton(tree.root, "Search");
    _ = try expectByText(tree.root, .text, "Settings");
    _ = try expectByText(tree.root, .text, "Default model");
    _ = try expectByText(tree.root, .text, "Access mode");
    _ = try expectByText(tree.root, .text, "Last project path");
    _ = try expectByText(tree.root, .text, "Daemon address");
    _ = try expectButton(tree.root, "Ask");
    _ = try expectButton(tree.root, "Auto");
    _ = try expectButton(tree.root, "Full access");
    try testing.expect(findByPlaceholder(tree.root, .text_field, "FX_MODEL") != null);
    try testing.expect(findByPlaceholder(tree.root, .text_field, "Workspace path") != null);
    try testing.expect(findByPlaceholder(tree.root, .text_field, "host:port") != null);
    try testing.expect(findByKind(tree.root, .textarea) == null);
    try testing.expect(findByText(tree.root, .button, "Send") == null);

    const escape = canvas.WidgetKeyboardEvent{ .phase = .key_down, .key = "escape" };
    try testing.expectEqual(Msg.stop, main.onKey(escape).?);
    main.update(&model, main.onKey(escape).?, &fx);
    try testing.expect(!model.settings_open);

    tree = try buildTree(arena, &model);
    _ = try expectByText(tree.root, .button, "Send");
    _ = try expectByText(tree.root, .text, "Today");
    try testing.expect(findByText(tree.root, .text, "Default model") == null);

    const gear_again = try expectButton(tree.root, "Settings");
    main.update(&model, tree.msgForPointer(gear_again.id, .up).?, &fx);
    try testing.expect(model.settings_open);
    tree = try buildTree(arena, &model);
    const gear_close = try expectButton(tree.root, "Settings");
    main.update(&model, tree.msgForPointer(gear_close.id, .up).?, &fx);
    try testing.expect(!model.settings_open);

    tree = try buildTree(arena, &model);
    _ = try expectByText(tree.root, .button, "Send");
    _ = try expectByText(tree.root, .text, "Today");
    try testing.expect(findByText(tree.root, .text, "Default model") == null);
}

test "settings edits persist model access and daemon address and reload" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-settings", .{tmp.sub_path[0..]});

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = main.initialModel();
    model.task_state_loaded = true;
    model.setStoreDir(dir);
    model.store_io = testing.io;
    try store.saveSession(&model, model.selected, testing.allocator, testing.io);

    var tree = try buildTree(arena, &model);
    const gear = try expectButton(tree.root, "Settings");
    main.update(&model, tree.msgForPointer(gear.id, .up).?, &fx);
    try testing.expect(model.settings_open);

    tree = try buildTree(arena, &model);
    _ = try expectByText(tree.root, .text, "Default model");
    main.update(&model, .{ .settings_model_edit = .{ .insert_text = "openai/gpt-5.4" } }, &fx);
    try testing.expectEqualStrings("openai/gpt-5.4", model.lastModel());
    try testing.expectEqualStrings("openai/gpt-5.4", model.settings_model());

    const auto = try expectButton(tree.root, "Auto");
    main.update(&model, tree.msgForPointer(auto.id, .up).?, &fx);
    try testing.expectEqualStrings("auto", model.lastAccessMode());
    try testing.expect(model.access_auto());
    try testing.expect(!model.access_ask());
    try testing.expect(!model.access_full());

    main.update(&model, .{ .settings_project_edit = .{ .insert_text = "/tmp/faku-settings" } }, &fx);
    try testing.expectEqualStrings("/tmp/faku-settings", model.lastProjectPath());

    main.update(&model, .{ .settings_daemon_edit = .{ .insert_text = "127.0.0.1:8787" } }, &fx);
    try testing.expectEqualStrings("127.0.0.1:8787", model.lastDaemonAddress());
    try testing.expectEqual(@as(usize, 0), model.daemonAddress().len);

    var loaded = Model{};
    loaded.setStoreDir(dir);
    loaded.store_io = testing.io;
    try testing.expectEqual(store.LoadKind.loaded, store.loadCatalog(&loaded, testing.allocator, testing.io));
    try testing.expectEqualStrings("openai/gpt-5.4", loaded.lastModel());
    try testing.expectEqualStrings("auto", loaded.lastAccessMode());
    try testing.expectEqualStrings("/tmp/faku-settings", loaded.lastProjectPath());
    try testing.expectEqualStrings("127.0.0.1:8787", loaded.lastDaemonAddress());
    try testing.expectEqual(@as(usize, 0), loaded.daemonAddress().len);

    const inherited = loaded.addSession("untitled next", .fx);
    try testing.expectEqualStrings("openai/gpt-5.4", loaded.sessionById(inherited).?.model());
    try testing.expectEqualStrings("auto", loaded.sessionById(inherited).?.accessMode());
    try testing.expectEqualStrings("/tmp/faku-settings", loaded.sessionById(inherited).?.projectPath());

    loaded.openSettings();
    main.update(&loaded, .{ .settings_daemon_edit = .clear }, &fx);
    try testing.expectEqual(@as(usize, 0), loaded.lastDaemonAddress().len);

    var cleared = Model{};
    cleared.setStoreDir(dir);
    try testing.expectEqual(store.LoadKind.loaded, store.loadCatalog(&cleared, testing.allocator, testing.io));
    try testing.expectEqual(@as(usize, 0), cleared.lastDaemonAddress().len);
    try testing.expectEqualStrings("openai/gpt-5.4", cleared.lastModel());
    try testing.expectEqualStrings("auto", cleared.lastAccessMode());
}

test "composer access chip cycles ask auto fullAccess; Build cycles plan" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = main.initialModel();
    try testing.expectEqualStrings("fullAccess", model.session_store[0].accessMode());
    try testing.expectEqualStrings("build", model.session_store[0].interactionMode());
    try testing.expectEqualStrings("Full access", model.access_label());
    try testing.expectEqualStrings("Build", model.interaction_label());

    var tree = try buildTree(arena, &model);
    _ = try expectByText(tree.root, .button, "Medium");
    const access = try expectByText(tree.root, .button, "Full access");
    main.update(&model, tree.msgForPointer(access.id, .up).?, &fx);
    try testing.expectEqualStrings("ask", model.session_store[0].accessMode());
    try testing.expectEqualStrings("ask", model.lastAccessMode());
    try testing.expectEqualStrings("Ask", model.access_label());

    tree = try buildTree(arena, &model);
    const ask = try expectByText(tree.root, .button, "Ask");
    main.update(&model, tree.msgForPointer(ask.id, .up).?, &fx);
    try testing.expectEqualStrings("auto", model.session_store[0].accessMode());
    try testing.expectEqualStrings("auto", model.lastAccessMode());
    try testing.expectEqualStrings("Auto", model.access_label());

    tree = try buildTree(arena, &model);
    const auto = try expectByText(tree.root, .button, "Auto");
    main.update(&model, tree.msgForPointer(auto.id, .up).?, &fx);
    try testing.expectEqualStrings("fullAccess", model.session_store[0].accessMode());
    try testing.expectEqualStrings("fullAccess", model.lastAccessMode());
    try testing.expectEqualStrings("Full access", model.access_label());

    tree = try buildTree(arena, &model);
    const build = try expectByText(tree.root, .button, "Build");
    main.update(&model, tree.msgForPointer(build.id, .up).?, &fx);
    try testing.expectEqualStrings("plan", model.session_store[0].interactionMode());
    try testing.expectEqualStrings("plan", model.lastInteractionMode());
    try testing.expectEqualStrings("Plan", model.interaction_label());

    tree = try buildTree(arena, &model);
    const plan = try expectByText(tree.root, .button, "Plan");
    main.update(&model, tree.msgForPointer(plan.id, .up).?, &fx);
    try testing.expectEqualStrings("build", model.session_store[0].interactionMode());
    try testing.expectEqualStrings("build", model.lastInteractionMode());
    try testing.expectEqualStrings("Build", model.interaction_label());

    tree = try buildTree(arena, &model);
    _ = try expectByText(tree.root, .button, "Full access");
    _ = try expectByText(tree.root, .button, "Build");
    _ = try expectByText(tree.root, .button, "Medium");
}

test "composer chips persist access interaction and last-used model and reload" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-chips", .{tmp.sub_path[0..]});

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = main.initialModel();
    model.task_state_loaded = true;
    model.setStoreDir(dir);
    model.store_io = testing.io;
    if (model.sessionById(model.selected)) |session| {
        session.setModel("openai/gpt-5.4");
    }
    model.setLastModel("openai/gpt-5.4");
    try store.saveSession(&model, model.selected, testing.allocator, testing.io);

    var tree = try buildTree(arena, &model);
    try testing.expectEqualStrings("openai/gpt-5.4", model.model_label());
    const model_chip = try expectByText(tree.root, .button, "openai/gpt-5.4");
    main.update(&model, tree.msgForPointer(model_chip.id, .up).?, &fx);
    try testing.expectEqual(@as(usize, 0), model.session_store[0].model().len);
    try testing.expectEqualStrings("openai/gpt-5.4", model.lastModel());
    try testing.expectEqualStrings("FX_MODEL", model.model_label());

    tree = try buildTree(arena, &model);
    const empty_model = try expectByText(tree.root, .button, "FX_MODEL");
    main.update(&model, tree.msgForPointer(empty_model.id, .up).?, &fx);
    try testing.expectEqualStrings("openai/gpt-5.4", model.session_store[0].model());
    try testing.expectEqualStrings("openai/gpt-5.4", model.model_label());

    tree = try buildTree(arena, &model);
    const access = try expectByText(tree.root, .button, "Full access");
    main.update(&model, tree.msgForPointer(access.id, .up).?, &fx);
    try testing.expectEqualStrings("ask", model.session_store[0].accessMode());

    tree = try buildTree(arena, &model);
    const ask = try expectByText(tree.root, .button, "Ask");
    main.update(&model, tree.msgForPointer(ask.id, .up).?, &fx);
    try testing.expectEqualStrings("auto", model.session_store[0].accessMode());

    tree = try buildTree(arena, &model);
    const build = try expectByText(tree.root, .button, "Build");
    main.update(&model, tree.msgForPointer(build.id, .up).?, &fx);
    try testing.expectEqualStrings("plan", model.session_store[0].interactionMode());
    try testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());

    var loaded = Model{};
    loaded.setStoreDir(dir);
    loaded.store_io = testing.io;
    try testing.expectEqual(store.LoadKind.loaded, store.loadCatalog(&loaded, testing.allocator, testing.io));
    try testing.expectEqualStrings("openai/gpt-5.4", loaded.session_store[0].model());
    try testing.expectEqualStrings("auto", loaded.session_store[0].accessMode());
    try testing.expectEqualStrings("plan", loaded.session_store[0].interactionMode());
    try testing.expectEqualStrings("openai/gpt-5.4", loaded.lastModel());
    try testing.expectEqualStrings("auto", loaded.lastAccessMode());
    try testing.expectEqualStrings("plan", loaded.lastInteractionMode());

    const inherited = loaded.addSession("untitled next", .fx);
    try testing.expectEqualStrings("openai/gpt-5.4", loaded.sessionById(inherited).?.model());
    try testing.expectEqualStrings("auto", loaded.sessionById(inherited).?.accessMode());
    try testing.expectEqualStrings("plan", loaded.sessionById(inherited).?.interactionMode());

    tree = try buildTree(arena, &loaded);
    _ = try expectByText(tree.root, .button, "openai/gpt-5.4");
    _ = try expectByText(tree.root, .button, "Auto");
    _ = try expectByText(tree.root, .button, "Plan");
    _ = try expectByText(tree.root, .button, "Medium");
}

test "sidebar back and forward walk session selection history" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = main.initialModel();
    try testing.expect(!model.can_go_back());
    try testing.expect(!model.can_go_forward());
    try testing.expectEqualStrings("port waku to zig", model.selected_title());

    var tree = try buildTree(arena, &model);
    _ = try expectButton(tree.root, "Search");
    _ = try expectButton(tree.root, "Settings");
    _ = try expectByText(tree.root, .button, "Full access");
    _ = try expectByText(tree.root, .button, "Build");
    _ = try expectByText(tree.root, .button, "Medium");
    const back_start = try expectButton(tree.root, "Back");
    const forward_start = try expectButton(tree.root, "Forward");
    main.update(&model, tree.msgForPointer(back_start.id, .up).?, &fx);
    try testing.expectEqualStrings("port waku to zig", model.selected_title());
    try testing.expect(!model.can_go_back());
    main.update(&model, tree.msgForPointer(forward_start.id, .up).?, &fx);
    try testing.expectEqualStrings("port waku to zig", model.selected_title());
    try testing.expect(!model.can_go_forward());

    const auth = try expectButton(tree.root, "fix auth listener");
    main.update(&model, tree.msgForPointer(auth.id, .up).?, &fx);
    try testing.expectEqualStrings("fix auth listener", model.selected_title());
    try testing.expectEqual(@as(usize, 1), countRole(&model, .user));
    try testing.expectEqual(@as(usize, 2), countRole(&model, .assistant));
    try testing.expectEqual(@as(usize, 1), countRole(&model, .tool));
    try testing.expect(model.can_go_back());
    try testing.expect(!model.can_go_forward());

    main.update(&model, .{ .select = model.session_store[1].id }, &fx);
    try testing.expectEqual(@as(u32, 2), model.history_count);
    try testing.expect(!model.can_go_forward());

    const third = model.addSession("third", .fx);
    _ = model.appendTurn(third, .user, "third user");
    _ = model.appendTurn(third, .assistant, "third assistant");
    if (model.sessionById(third)) |session| {
        session.has_started = true;
        session.detail_loaded = true;
    }
    main.update(&model, .{ .select = third }, &fx);
    try testing.expectEqualStrings("third", model.selected_title());
    try testing.expectEqual(@as(usize, 1), countRole(&model, .user));
    try testing.expectEqual(@as(usize, 1), countRole(&model, .assistant));

    tree = try buildTree(arena, &model);
    const back_to_b = try expectButton(tree.root, "Back");
    main.update(&model, tree.msgForPointer(back_to_b.id, .up).?, &fx);
    try testing.expectEqualStrings("fix auth listener", model.selected_title());
    try testing.expectEqual(@as(usize, 1), countRole(&model, .user));
    try testing.expectEqual(@as(usize, 2), countRole(&model, .assistant));
    try testing.expectEqual(@as(usize, 1), countRole(&model, .tool));
    try testing.expect(model.can_go_back());
    try testing.expect(model.can_go_forward());

    tree = try buildTree(arena, &model);
    const forward_to_c = try expectButton(tree.root, "Forward");
    main.update(&model, tree.msgForPointer(forward_to_c.id, .up).?, &fx);
    try testing.expectEqualStrings("third", model.selected_title());
    try testing.expectEqual(@as(usize, 1), countRole(&model, .assistant));
    try testing.expect(model.can_go_back());
    try testing.expect(!model.can_go_forward());

    tree = try buildTree(arena, &model);
    main.update(&model, tree.msgForPointer((try expectButton(tree.root, "Back")).id, .up).?, &fx);
    try testing.expectEqualStrings("fix auth listener", model.selected_title());

    const fourth = model.addSession("fourth", .fx);
    _ = model.appendTurn(fourth, .user, "fourth user");
    if (model.sessionById(fourth)) |session| {
        session.has_started = true;
        session.detail_loaded = true;
    }
    main.update(&model, .{ .select = fourth }, &fx);
    try testing.expectEqualStrings("fourth", model.selected_title());
    try testing.expect(!model.can_go_forward());

    tree = try buildTree(arena, &model);
    main.update(&model, tree.msgForPointer((try expectButton(tree.root, "Forward")).id, .up).?, &fx);
    try testing.expectEqualStrings("fourth", model.selected_title());

    tree = try buildTree(arena, &model);
    main.update(&model, tree.msgForPointer((try expectButton(tree.root, "Back")).id, .up).?, &fx);
    try testing.expectEqualStrings("fix auth listener", model.selected_title());
    tree = try buildTree(arena, &model);
    main.update(&model, tree.msgForPointer((try expectButton(tree.root, "Back")).id, .up).?, &fx);
    try testing.expectEqualStrings("port waku to zig", model.selected_title());
    try testing.expectEqual(@as(usize, 1), countRole(&model, .user));
    try testing.expectEqual(@as(usize, 1), countRole(&model, .assistant));
    try testing.expectEqual(@as(usize, 0), countRole(&model, .tool));
    try testing.expect(!model.can_go_back());
    try testing.expect(model.can_go_forward());

    tree = try buildTree(arena, &model);
    main.update(&model, tree.msgForPointer((try expectButton(tree.root, "Back")).id, .up).?, &fx);
    try testing.expectEqualStrings("port waku to zig", model.selected_title());
    try testing.expect(!model.can_go_back());

    tree = try buildTree(arena, &model);
    _ = try expectButton(tree.root, "Search");
    _ = try expectButton(tree.root, "Collapse sidebar");
    _ = try expectButton(tree.root, "Settings");
    _ = try expectByText(tree.root, .button, "Full access");
    _ = try expectByText(tree.root, .button, "Medium");
}

test "sidebar back hydrates an empty session the same way select does" {
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.fx_probe_started = true;
    const filled = model.addSession("has local turns", .fx);
    _ = model.appendTurn(filled, .user, "already here");
    const empty = model.addSession("empty transcript", .fx);
    const later = model.addSession("later filled", .fx);
    _ = model.appendTurn(later, .user, "later user");
    model.selected = filled;
    model.pushSelectionHistory(filled);

    main.update(&model, .{ .select = empty }, &fx);
    main.update(&model, .{ .select = later }, &fx);
    try testing.expect(findHydrateOnlySpawn(&fx) == null);

    model.setDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    main.update(&model, .history_back, &fx);
    try testing.expectEqual(empty, model.selected);
    const spawn = findHydrateOnlySpawn(&fx) orelse return error.HydrateSpawnMissing;
    try testing.expect(std.mem.indexOf(u8, spawn.stdin, "\"type\":\"hydrateSession\"") != null);
    try testing.expectEqual(empty, model.daemon_hydrate_session);

    main.update(&model, .history_back, &fx);
    try testing.expectEqual(filled, model.selected);
    try testing.expectEqual(@as(u32, 1), model.turnCount(filled));
    try testing.expectEqual(spawn.key, model.daemon_hydrate_key);
}

test "selection history cap drops the oldest entry" {
    var model = Model{};
    const first: u32 = 1;
    model.selected = first;
    model.pushSelectionHistory(first);

    var id: u32 = 2;
    while (id <= main.selection_history_cap + 1) : (id += 1) {
        model.pushSelectionHistory(id);
        model.selected = id;
    }

    try testing.expectEqual(main.selection_history_cap, model.history_count);
    try testing.expect(model.history_store[0] != first);
    try testing.expectEqual(main.selection_history_cap + 1, model.history_store[model.history_count - 1]);
    try testing.expect(model.can_go_back());
    try testing.expect(!model.can_go_forward());
}

test "sidebar New folder creates a persisted catalog folder" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-folders", .{tmp.sub_path[0..]});

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var missing = main.initialModel();
    missing.task_state_loaded = true;
    missing.setStoreDir(dir);
    missing.store_io = testing.io;
    var tree = try buildTree(arena, &missing);
    const new_folder = try expectButton(tree.root, "New folder");
    main.update(&missing, tree.msgForPointer(new_folder.id, .up).?, &fx);
    try testing.expectEqual(@as(u32, 1), missing.folder_count);
    try testing.expectEqualStrings("New folder", missing.folder_store[0].title());
    var missing_path: [std.fs.max_path_bytes]u8 = undefined;
    try testing.expectError(error.FileNotFound, std.Io.Dir.cwd().readFileAlloc(testing.io, store.catalogPath(dir, &missing_path).?, testing.allocator, .limited(64)));

    var model = main.initialModel();
    model.task_state_loaded = true;
    model.setStoreDir(dir);
    model.store_io = testing.io;
    try store.saveSession(&model, model.selected, testing.allocator, testing.io);

    tree = try buildTree(arena, &model);
    _ = try expectByText(tree.root, .text, "Today");
    _ = try expectButton(tree.root, "Search");
    _ = try expectButton(tree.root, "Collapse sidebar");
    _ = try expectButton(tree.root, "Settings");
    _ = try expectByText(tree.root, .button, "Full access");
    main.update(&model, tree.msgForPointer((try expectButton(tree.root, "New folder")).id, .up).?, &fx);
    try testing.expectEqual(@as(u32, 1), model.folder_count);
    try testing.expectEqualStrings("New folder", model.folder_store[0].title());
    main.update(&model, .new_folder, &fx);
    try testing.expectEqual(@as(u32, 2), model.folder_count);
    try testing.expectEqualStrings("New folder 2", model.folder_store[1].title());

    try expectSidebarTitles(model.sidebar_rows(arena), &.{
        "port waku to zig",
        "fix auth listener",
        "New folder",
        "New folder 2",
    });
    try expectRowTitles(model.session_rows(arena), &.{ "port waku to zig", "fix auth listener" });

    tree = try buildTree(arena, &model);
    _ = try expectByText(tree.root, .text, "Today");
    _ = try expectByText(tree.root, .list_item, "New folder");
    _ = try expectByText(tree.root, .list_item, "New folder 2");
    _ = try expectButton(tree.root, "port waku to zig");
    _ = try expectButton(tree.root, "Search");

    var loaded = Model{};
    loaded.setStoreDir(dir);
    loaded.store_io = testing.io;
    try testing.expectEqual(store.LoadKind.loaded, store.loadCatalog(&loaded, testing.allocator, testing.io));
    try testing.expectEqual(@as(u32, 2), loaded.folder_count);
    try testing.expectEqualStrings("New folder", loaded.folder_store[0].title());
    try testing.expectEqualStrings("New folder 2", loaded.folder_store[1].title());
}

test "session with folder_id appears under that folder not Today" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-folder-assign", .{tmp.sub_path[0..]});

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = main.initialModel();
    model.task_state_loaded = true;
    model.setStoreDir(dir);
    model.store_io = testing.io;
    try store.saveSession(&model, model.selected, testing.allocator, testing.io);

    main.update(&model, .new_folder, &fx);
    const folder_id = model.folder_store[0].id;
    const auth_id = model.session_store[1].id;
    main.update(&model, .{ .assign_folder = .{ .session_id = auth_id, .folder_id = folder_id } }, &fx);
    try testing.expectEqual(folder_id, model.session_store[1].folder_id);

    try expectSidebarTitles(model.sidebar_rows(arena), &.{
        "port waku to zig",
        "New folder",
        "fix auth listener",
    });
    try testing.expect(model.sidebar_rows(arena)[1].is_header);
    try testing.expectEqual(folder_id, model.sidebar_rows(arena)[1].folder_id);
    try expectRowTitles(model.session_rows(arena), &.{ "port waku to zig", "fix auth listener" });

    var tree = try buildTree(arena, &model);
    _ = try expectByText(tree.root, .text, "Today");
    _ = try expectByText(tree.root, .list_item, "New folder");
    _ = try expectButton(tree.root, "port waku to zig");
    _ = try expectButton(tree.root, "fix auth listener");
    _ = try expectButton(tree.root, "Search");
    _ = try expectButton(tree.root, "Back");
    _ = try expectButton(tree.root, "Settings");

    main.update(&model, .{ .toggle_folder = folder_id }, &fx);
    try testing.expect(model.folder_store[0].collapsed);
    try expectSidebarTitles(model.sidebar_rows(arena), &.{
        "port waku to zig",
        "New folder",
    });
    tree = try buildTree(arena, &model);
    try testing.expect(findPressableContaining(tree.root, "fix auth listener") == null);
    _ = try expectByText(tree.root, .list_item, "New folder");

    var loaded = Model{};
    loaded.setStoreDir(dir);
    loaded.store_io = testing.io;
    try testing.expectEqual(store.LoadKind.loaded, store.loadCatalog(&loaded, testing.allocator, testing.io));
    try testing.expectEqual(folder_id, loaded.session_store[1].folder_id);
    try testing.expect(loaded.folder_store[0].collapsed);
    try expectSidebarTitles(loaded.sidebar_rows(arena), &.{
        "port waku to zig",
        "New folder",
    });
}

test "sidebar search still matches session titles across folders" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = main.initialModel();
    main.update(&model, .new_folder, &fx);
    const folder_id = model.folder_store[0].id;
    main.update(&model, .{ .assign_folder = .{
        .session_id = model.session_store[0].id,
        .folder_id = folder_id,
    } }, &fx);

    try expectRowTitles(model.session_rows(arena), &.{ "port waku to zig", "fix auth listener" });
    try expectSidebarTitles(model.sidebar_rows(arena), &.{
        "fix auth listener",
        "New folder",
        "port waku to zig",
    });

    main.update(&model, .{ .search_edit = .{ .insert_text = "WAKU" } }, &fx);
    try expectRowTitles(model.session_rows(arena), &.{"port waku to zig"});
    try expectSidebarTitles(model.sidebar_rows(arena), &.{
        "New folder",
        "port waku to zig",
    });

    var tree = try buildTree(arena, &model);
    _ = try expectButton(tree.root, "port waku to zig");
    try testing.expect(findPressableContaining(tree.root, "fix auth listener") == null);
    _ = try expectByText(tree.root, .text, "Today");
    _ = try expectByText(tree.root, .list_item, "New folder");

    main.update(&model, .{ .toggle_folder = folder_id }, &fx);
    try expectSidebarTitles(model.sidebar_rows(arena), &.{
        "New folder",
        "port waku to zig",
    });

    main.update(&model, .stop, &fx);
    try expectRowTitles(model.session_rows(arena), &.{ "port waku to zig", "fix auth listener" });
    try expectSidebarTitles(model.sidebar_rows(arena), &.{
        "fix auth listener",
        "New folder",
    });
}
