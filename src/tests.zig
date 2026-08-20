const std = @import("std");
const native_sdk = @import("native_sdk");
const main = @import("main.zig");
const protocol = @import("protocol.zig");
const store = @import("store.zig");

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

test "send with fx_available spawns fx ask and streams a synthetic line" {
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
    try testing.expectEqual(@as(usize, 0), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());

    const request = fx.pendingSpawnAt(0).?;
    try testing.expectEqual(main.fx_ask_key, request.key);
    try testing.expect(argvHas(request.argv, "ask"));
    try testing.expect(argvHas(request.argv, "fx"));
    try testing.expectEqualStrings("what does this repo do", request.argv[request.argv.len - 1]);

    const before_len = lastAssistant(&model).len;
    try fx.feedLine(main.fx_ask_key, "hello from fx ask");
    drainEffects(&model, &fx);
    try testing.expect(lastAssistant(&model).len > before_len);
    try testing.expect(std.mem.indexOf(u8, lastAssistant(&model), "hello from fx ask") != null);

    try fx.feedExit(main.fx_ask_key, 0);
    drainEffects(&model, &fx);
    try testing.expect(!model.is_streaming());
}

test "fx ask spawn records session project_path as cwd" {
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
    try testing.expectEqualStrings(project, model.lastSpawnCwd());
    try testing.expectEqualStrings(project, model.resolveSpawnCwd(model.sessionByIdConst(id).?));
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());

    const request = fx.pendingSpawnAt(0).?;
    try testing.expectEqual(main.fx_ask_key, request.key);
    try testing.expectEqualStrings("/bin/sh", request.argv[0]);
    try testing.expectEqualStrings("-c", request.argv[1]);
    try testing.expectEqualStrings(main.fx_ask_chdir_script, request.argv[2]);
    try testing.expectEqualStrings(project, request.argv[4]);
    try testing.expect(argvHas(request.argv, "ask"));
    try testing.expectEqualStrings("what is the cwd", request.argv[request.argv.len - 1]);
}

test "fx ask --json mints session_id and later send resumes" {
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
    try testing.expect(argvHas(first.argv, "ask"));
    try testing.expect(argvHas(first.argv, "--json"));
    try testing.expect(argvHas(first.argv, "--"));
    try testing.expect(!argvHas(first.argv, "--resume"));
    try testing.expectEqualStrings("first turn", first.argv[first.argv.len - 1]);

    try fx.feedLine(main.fx_ask_key, "{\"session_id\":\"fx-test-1\"}");
    drainEffects(&model, &fx);
    try testing.expectEqualStrings("fx-test-1", model.sessionById(id).?.fxSessionId());
    try testing.expectEqual(@as(usize, 0), lastAssistant(&model).len);

    try fx.feedLine(main.fx_ask_key, "plain reply");
    drainEffects(&model, &fx);
    try testing.expect(std.mem.indexOf(u8, lastAssistant(&model), "plain reply") != null);
    try testing.expect(std.mem.indexOf(u8, lastAssistant(&model), "session_id") == null);

    try fx.feedExit(main.fx_ask_key, 0);
    drainEffects(&model, &fx);
    try testing.expect(!model.is_streaming());

    var loaded = Model{};
    loaded.setStoreDir(dir);
    try testing.expectEqual(store.LoadKind.loaded, store.loadCatalog(&loaded, testing.allocator, testing.io));
    try testing.expectEqualStrings("fx-test-1", loaded.session_store[0].fxSessionId());

    main.update(&model, .{ .draft_edit = .{ .insert_text = "second turn" } }, &fx);
    main.update(&model, .send, &fx);
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());
    const second = fx.pendingSpawnAt(0).?;
    try testing.expect(argvHas(second.argv, "--json"));
    try testing.expect(argvHas(second.argv, "--resume"));
    try testing.expect(argvHas(second.argv, "fx-test-1"));
    try testing.expectEqualStrings("second turn", second.argv[second.argv.len - 1]);
    const resume_at = argvIndex(second.argv, "--resume") orelse return error.MissingResume;
    try testing.expectEqualStrings("fx-test-1", second.argv[resume_at + 1]);
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
    try testing.expect(argvHas(request.argv, "ask"));
    try testing.expect(!argvHas(request.argv, "--model"));
    try testing.expectEqualStrings("with env", request.argv[request.argv.len - 1]);
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
