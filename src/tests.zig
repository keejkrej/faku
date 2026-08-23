const std = @import("std");
const native_sdk = @import("native_sdk");
const main = @import("main.zig");
const protocol = @import("protocol.zig");
const store = @import("store.zig");
const daemon_proxy = @import("daemon_proxy.zig");
const acp_proxy = @import("acp_proxy.zig");
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

fn findBoldSpanText(widget: canvas.Widget, text: []const u8) ?canvas.Widget {
    if (widget.kind == .text) {
        for (widget.spans) |span| {
            if (span.weight == .bold and std.mem.eql(u8, span.text, text)) return widget;
        }
    }
    for (widget.children) |child| {
        if (findBoldSpanText(child, text)) |found| return found;
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

fn lastUser(model: *const Model) []const u8 {
    var i = model.turn_count;
    while (i > 0) {
        i -= 1;
        const turn = &model.turn_store[i];
        if (turn.session_id == model.selected and turn.role == .user) return turn.text();
    }
    return "";
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

fn lastTool(model: *const Model) []const u8 {
    var i = model.turn_count;
    while (i > 0) {
        i -= 1;
        const turn = &model.turn_store[i];
        if (turn.session_id == model.selected and turn.role == .tool) return turn.text();
    }
    return "";
}

fn sessionTurnText(model: *const Model, session_id: u32, index: usize) []const u8 {
    var n: usize = 0;
    for (model.turn_store[0..model.turn_count]) |*turn| {
        if (turn.session_id != session_id) continue;
        if (n == index) return turn.text();
        n += 1;
    }
    return "";
}

fn findAnyText(widget: canvas.Widget, text: []const u8) bool {
    if (std.mem.eql(u8, widget.text, text)) return true;
    if (std.mem.eql(u8, widgetName(widget), text)) return true;
    for (widget.spans) |span| {
        if (std.mem.eql(u8, span.text, text)) return true;
    }
    for (widget.children) |child| {
        if (findAnyText(child, text)) return true;
    }
    return false;
}

fn lastReasoning(model: *const Model) []const u8 {
    var i = model.turn_count;
    while (i > 0) {
        i -= 1;
        const turn = &model.turn_store[i];
        if (turn.session_id == model.selected and turn.role == .reasoning) return turn.text();
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
    _ = try expectButton(tree.root, "Remove session");
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

test "appending a turn renders last and pins the transcript value" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    const id = model.addSession("pin transcript", .fx);
    model.selected = id;
    model.pinTranscriptToLatest();

    _ = model.appendTurn(id, .user, "first user turn");
    _ = model.appendTurn(id, .assistant, "first assistant turn");
    _ = model.appendTurn(id, .tool, "read src/pin.ts");
    _ = model.appendTurn(id, .reasoning, "newest thought stays last");

    try testing.expectEqual(@as(u32, 4), model.turnCount(id));
    try testing.expectEqualStrings("newest thought stays last", model.turn_store[model.turn_count - 1].text());
    try testing.expectEqual(main.transcript_pin_offset, model.transcript_scroll);
    try testing.expect(model.transcript_pinned);
    try testing.expect(!model.show_jump_latest());

    var tree = try buildTree(arena, &model);
    try testing.expect(findAnyText(tree.root, "first user turn"));
    try testing.expect(findAnyText(tree.root, "first assistant turn"));
    _ = try expectByText(tree.root, .text, "read src/pin.ts");
    _ = try expectByText(tree.root, .text, "newest thought stays last");
    _ = try expectByText(tree.root, .scroll_view, "Transcript");
    try testing.expect(findByText(tree.root, .button, "Jump to latest") == null);
    _ = try expectButton(tree.root, "Attach image");
    _ = try expectButton(tree.root, "Copy");
    try testing.expect(findByText(tree.root, .button, "Commands") == null);

    const away = canvas.ScrollState{
        .offset_y = 120,
        .viewport_extent_y = 400,
        .content_extent_y = 1600,
    };
    try testing.expect(!Model.transcriptAtEnd(away));
    main.update(&model, .{ .transcript_scrolled = away }, &fx);
    try testing.expectEqual(@as(f32, 120), model.transcript_scroll);
    try testing.expect(!model.transcript_pinned);
    try testing.expect(model.show_jump_latest());

    _ = model.appendTurn(id, .assistant, "off-screen newest reply");
    try testing.expectEqual(@as(f32, 120), model.transcript_scroll);
    try testing.expect(!model.transcript_pinned);

    tree = try buildTree(arena, &model);
    try testing.expect(findAnyText(tree.root, "off-screen newest reply"));
    const jump = try expectButton(tree.root, "Jump to latest");
    try testing.expectEqual(Msg.jump_latest, tree.msgForPointer(jump.id, .up).?);

    main.update(&model, tree.msgForPointer(jump.id, .up).?, &fx);
    try testing.expectEqual(main.transcript_pin_offset, model.transcript_scroll);
    try testing.expect(model.transcript_pinned);
    try testing.expect(!model.show_jump_latest());

    tree = try buildTree(arena, &model);
    try testing.expect(findByText(tree.root, .button, "Jump to latest") == null);
    try testing.expect(findAnyText(tree.root, "off-screen newest reply"));
    _ = try expectButton(tree.root, "Attach image");
    _ = try expectButton(tree.root, "Copy");

    const at_end = canvas.ScrollState{
        .offset_y = 1200,
        .viewport_extent_y = 400,
        .content_extent_y = 1600,
    };
    try testing.expect(Model.transcriptAtEnd(at_end));
    main.update(&model, .{ .transcript_scrolled = at_end }, &fx);
    try testing.expect(model.transcript_pinned);
    _ = model.appendTurn(id, .user, "follow-up at the bottom");
    try testing.expectEqual(main.transcript_pin_offset, model.transcript_scroll);
    try testing.expect(model.transcript_pinned);

    tree = try buildTree(arena, &model);
    try testing.expect(findAnyText(tree.root, "follow-up at the bottom"));
    try testing.expect(findByText(tree.root, .button, "Jump to latest") == null);
}

test "copy of a fixture turn writes fx.writeClipboard; empty is a no-op" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    const id = model.addSession("copy turn", .fx);
    model.selected = id;

    const user_id = model.appendTurn(id, .user, "fixture user markdown source");
    _ = model.appendTurn(id, .assistant, "fixture assistant reply");
    _ = model.appendTurn(id, .tool, "read src/copy.ts");
    _ = model.appendTurn(id, .reasoning, "fixture thought");
    const empty_id = model.appendTurn(id, .assistant, "");

    var tree = try buildTree(arena, &model);
    try testing.expect(findAnyText(tree.root, "fixture user markdown source"));
    try testing.expect(findAnyText(tree.root, "fixture assistant reply"));
    _ = try expectByText(tree.root, .text, "read src/copy.ts");
    _ = try expectByText(tree.root, .text, "fixture thought");
    const copy = try expectButton(tree.root, "Copy");
    try testing.expectEqual(Msg{ .copy_turn = user_id }, tree.msgForPointer(copy.id, .up).?);
    _ = try expectButton(tree.root, "Attach image");
    _ = try expectByText(tree.root, .scroll_view, "Transcript");
    try testing.expect(findByText(tree.root, .button, "Commands") == null);

    try testing.expectEqual(@as(usize, 0), fx.pendingClipboardCount());
    main.update(&model, .{ .copy_turn = empty_id }, &fx);
    try testing.expectEqual(@as(usize, 0), fx.pendingClipboardCount());
    try testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
    try testing.expectEqual(@as(usize, 0), fx.pendingTimerCount());

    main.update(&model, .{ .copy_turn = 0 }, &fx);
    try testing.expectEqual(@as(usize, 0), fx.pendingClipboardCount());

    main.update(&model, tree.msgForPointer(copy.id, .up).?, &fx);
    try testing.expectEqual(@as(usize, 1), fx.pendingClipboardCount());
    const first = fx.pendingClipboardAt(0).?;
    try testing.expectEqual(main.copy_turn_key, first.key);
    try testing.expectEqual(native_sdk.EffectClipboardOp.write, first.op);
    try testing.expectEqualStrings("fixture user markdown source", first.text);
}

test "copy session of a fixture multi-turn writes joined text once; empty is a no-op" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    const other = model.addSession("other session", .fx);
    const id = model.addSession("copy session", .fx);
    model.selected = id;
    _ = model.appendTurn(other, .assistant, "not this session");

    var tree = try buildTree(arena, &model);
    const toolbar = try expectByText(tree.root, .row, "Toolbar");
    const copy_session = try expectByText(toolbar, .button, "Copy session");
    try testing.expectEqual(Msg.copy_session, tree.msgForPointer(copy_session.id, .up).?);
    try testing.expect(findByText(tree.root, .button, "Rewind") == null);
    _ = try expectButton(tree.root, "Attach image");

    try testing.expectEqual(@as(usize, 0), fx.pendingClipboardCount());
    main.update(&model, .copy_session, &fx);
    try testing.expectEqual(@as(usize, 0), fx.pendingClipboardCount());
    try testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
    try testing.expectEqual(@as(usize, 0), fx.pendingTimerCount());

    _ = model.appendTurn(id, .user, "");
    _ = model.appendTurn(id, .assistant, "");
    main.update(&model, .copy_session, &fx);
    try testing.expectEqual(@as(usize, 0), fx.pendingClipboardCount());

    _ = model.appendTurn(id, .user, "fixture user markdown source");
    _ = model.appendTurn(id, .assistant, "");
    _ = model.appendTurn(id, .assistant, "fixture assistant reply");
    _ = model.appendTurn(id, .tool, "read src/copy.ts");
    _ = model.appendTurn(id, .reasoning, "fixture thought");

    tree = try buildTree(arena, &model);
    try testing.expect(findAnyText(tree.root, "fixture user markdown source"));
    try testing.expect(findAnyText(tree.root, "fixture assistant reply"));
    _ = try expectByText(tree.root, .text, "read src/copy.ts");
    _ = try expectByText(tree.root, .text, "fixture thought");
    const header_copy = try expectByText(
        try expectByText(tree.root, .row, "Toolbar"),
        .button,
        "Copy session",
    );
    try testing.expectEqual(Msg.copy_session, tree.msgForPointer(header_copy.id, .up).?);
    _ = try expectButton(tree.root, "Copy");
    _ = try expectButton(tree.root, "Attach image");
    try testing.expect(findByText(tree.root, .button, "Rewind") == null);
    try testing.expect(findByText(tree.root, .image, "Attached image") == null);

    main.update(&model, tree.msgForPointer(header_copy.id, .up).?, &fx);
    try testing.expectEqual(@as(usize, 1), fx.pendingClipboardCount());
    const first = fx.pendingClipboardAt(0).?;
    try testing.expectEqual(main.copy_turn_key, first.key);
    try testing.expectEqual(native_sdk.EffectClipboardOp.write, first.op);
    try testing.expectEqualStrings(
        "fixture user markdown source\n\nfixture assistant reply\n\nread src/copy.ts\n\nfixture thought",
        first.text,
    );

    main.update(&model, .copy_session, &fx);
    try testing.expectEqual(@as(usize, 1), fx.pendingClipboardCount());
    try testing.expectEqualStrings(
        "fixture user markdown source\n\nfixture assistant reply\n\nread src/copy.ts\n\nfixture thought",
        fx.pendingClipboardAt(0).?.text,
    );
}

test "fork copies turns and project_path; new id; empty fx_session_id; source unchanged; empty is a no-op" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-fork", .{tmp.sub_path[0..]});

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.task_state_loaded = true;
    model.setStoreDir(dir);
    model.store_io = testing.io;

    const empty = model.addSession("empty fork", .fx);
    model.selected = empty;
    try testing.expect(!model.can_fork());
    var tree = try buildTree(arena, &model);
    try testing.expect(findByText(tree.root, .button, "Fork") == null);
    main.update(&model, .fork, &fx);
    try testing.expectEqual(@as(u32, 1), model.session_count);
    try testing.expectEqual(empty, model.selected);
    try testing.expectEqual(@as(u32, 0), model.turnCount(empty));
    try testing.expect(!model.composer_active);

    const id = model.addSession("source thread", .fx);
    if (model.sessionById(id)) |session| {
        session.setProjectPath("/tmp/faku-fork-project");
        session.setFxSessionId("fx-sess-source");
        session.setRuntimeId("00000000-0000-0000-0000-000000000003");
        session.setModel("openai/gpt-5.4");
        session.setAccessMode("ask");
        session.setInteractionMode("plan");
        session.folder_id = 7;
        session.appendRewindRef("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", rewind.recorded_ref, 1_700_000_000);
    }
    model.selected = id;
    _ = model.appendTurn(id, .user, "first prompt");
    _ = model.appendTurn(id, .assistant, "first reply");
    _ = model.appendTurn(id, .tool, "read src/fork.ts");
    try store.saveSession(&model, id, testing.allocator, testing.io);

    try testing.expect(model.can_fork());
    tree = try buildTree(arena, &model);
    const toolbar = try expectByText(tree.root, .row, "Toolbar");
    const fork_btn = try expectByText(toolbar, .button, "Fork");
    try testing.expectEqual(Msg.fork, tree.msgForPointer(fork_btn.id, .up).?);

    main.update(&model, tree.msgForPointer(fork_btn.id, .up).?, &fx);
    try testing.expectEqual(@as(u32, 3), model.session_count);
    const fork_id = model.selected;
    try testing.expect(fork_id != id);
    try testing.expect(fork_id != empty);
    try testing.expect(model.composer_active);

    const forked = model.sessionById(fork_id).?;
    try testing.expectEqualStrings("source thread", forked.title());
    try testing.expectEqualStrings("/tmp/faku-fork-project", forked.projectPath());
    try testing.expectEqualStrings("openai/gpt-5.4", forked.model());
    try testing.expectEqualStrings("ask", forked.accessMode());
    try testing.expectEqualStrings("plan", forked.interactionMode());
    try testing.expectEqual(@as(u32, 7), forked.folder_id);
    try testing.expectEqual(@as(usize, 0), forked.fxSessionId().len);
    try testing.expectEqual(@as(usize, 0), forked.runtimeId().len);
    try testing.expectEqual(@as(u32, 3), model.turnCount(fork_id));
    try testing.expectEqualStrings("first prompt", sessionTurnText(&model, fork_id, 0));
    try testing.expectEqualStrings("first reply", sessionTurnText(&model, fork_id, 1));
    try testing.expectEqualStrings("read src/fork.ts", sessionTurnText(&model, fork_id, 2));
    try testing.expectEqual(@as(usize, 1), forked.rewind_ref_count);
    try testing.expectEqualStrings("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", forked.rewindRefs()[0].sha());

    const source = model.sessionById(id).?;
    try testing.expectEqualStrings("fx-sess-source", source.fxSessionId());
    try testing.expectEqualStrings("00000000-0000-0000-0000-000000000003", source.runtimeId());
    try testing.expectEqualStrings("/tmp/faku-fork-project", source.projectPath());
    try testing.expectEqual(@as(u32, 3), model.turnCount(id));
    try testing.expectEqualStrings("first prompt", sessionTurnText(&model, id, 0));
    try testing.expectEqualStrings("first reply", sessionTurnText(&model, id, 1));
    try testing.expectEqualStrings("read src/fork.ts", sessionTurnText(&model, id, 2));
    try testing.expectEqual(@as(usize, 1), source.rewind_ref_count);
    try testing.expectEqualStrings("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", source.rewindRefs()[0].sha());

    var loaded = Model{};
    loaded.setStoreDir(dir);
    try testing.expectEqual(store.LoadKind.loaded, store.loadCatalog(&loaded, testing.allocator, testing.io));
    try testing.expectEqual(@as(u32, 2), loaded.session_count);
    const loaded_source = loaded.sessionById(id).?;
    const loaded_fork = loaded.sessionById(fork_id).?;
    try testing.expectEqualStrings("fx-sess-source", loaded_source.fxSessionId());
    try testing.expectEqual(@as(usize, 0), loaded_fork.fxSessionId().len);
    try testing.expectEqual(@as(usize, 0), loaded_fork.runtimeId().len);
    try testing.expectEqualStrings("/tmp/faku-fork-project", loaded_fork.projectPath());
    store.hydrateSession(&loaded, fork_id, testing.allocator, testing.io);
    try testing.expectEqual(@as(u32, 3), loaded.turnCount(fork_id));
    try testing.expectEqualStrings("first prompt", sessionTurnText(&loaded, fork_id, 0));
    store.hydrateSession(&loaded, id, testing.allocator, testing.io);
    try testing.expectEqual(@as(u32, 3), loaded.turnCount(id));
    try testing.expectEqualStrings("first prompt", sessionTurnText(&loaded, id, 0));
}

test "user and assistant **bold** bind to markdown source" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var model = Model{};
    const id = model.addSession("markdown turn", .fx);
    model.selected = id;
    _ = model.appendTurn(id, .user, "**bold**");
    _ = model.appendTurn(id, .assistant, "**also**");

    const tree = try buildTree(arena, &model);
    try testing.expect(findByText(tree.root, .text, "**bold**") == null);
    try testing.expect(findByText(tree.root, .text, "**also**") == null);
    const user_rendered = findBoldSpanText(tree.root, "bold") orelse {
        std.debug.print("no bold markdown span for user \"bold\"\n", .{});
        dumpTexts(tree.root, 0);
        return error.WidgetNotFound;
    };
    try testing.expectEqual(canvas.WidgetKind.text, user_rendered.kind);
    try testing.expectEqualStrings("bold", user_rendered.text);
    const assistant_rendered = findBoldSpanText(tree.root, "also") orelse {
        std.debug.print("no bold markdown span for assistant \"also\"\n", .{});
        dumpTexts(tree.root, 0);
        return error.WidgetNotFound;
    };
    try testing.expectEqual(canvas.WidgetKind.text, assistant_rendered.kind);
    try testing.expectEqualStrings("also", assistant_rendered.text);
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
    try testing.expect(argvHas(request.argv, acp_proxy.SUBCOMMAND));
    try testing.expect(argvHas(request.argv, "--"));
    try testing.expect(argvHas(request.argv, "acp"));
    try testing.expect(argvHas(request.argv, "fx"));
    try testing.expect(!argvHas(request.argv, "ask"));
    try testing.expect(!argvHas(request.argv, "--model"));
    try testing.expect(!argvHas(request.argv, daemon_proxy.SUBCOMMAND));
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

    try fx.feedLine(main.fx_ask_key, "{\"jsonrpc\":\"2.0\",\"method\":\"session/request_permission\",\"id\":5,\"params\":{\"sessionId\":\"s1\",\"toolCall\":{\"toolCallId\":\"call_001\"},\"options\":[{\"optionId\":\"allow_once\",\"name\":\"Allow once\",\"kind\":\"allow_once\"},{\"optionId\":\"reject_once\",\"name\":\"Reject\",\"kind\":\"reject_once\"}]}}");
    drainEffects(&model, &fx);
    try testing.expect(model.is_streaming());
    try testing.expect(std.mem.indexOf(u8, lastAssistant(&model), "allow_once") == null);

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

test "ACP session/update tool_call adds a tool turn; tool_call_update changes status" {
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.fx_available = true;
    model.fx_probe_started = true;
    model.setFxPath("fx");
    const id = model.addSession("acp tool", .fx);
    model.selected = id;
    main.update(&model, .{ .draft_edit = .{ .insert_text = "read the file" } }, &fx);
    main.update(&model, .send, &fx);
    try testing.expect(model.fx_spawn_acp);
    const key = model.fx_spawn_key;

    try fx.feedLine(key, "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"sessionId\":\"acp-tool-1\"}}");
    drainEffects(&model, &fx);
    try testing.expectEqual(@as(usize, 0), countRole(&model, .tool));

    try fx.feedLine(key, "{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"sessionId\":\"acp-tool-1\",\"update\":{\"sessionUpdate\":\"tool_call\",\"toolCallId\":\"call_001\",\"title\":\"Reading file\",\"kind\":\"read\",\"status\":\"pending\"}}}");
    drainEffects(&model, &fx);
    try testing.expectEqual(@as(usize, 1), countRole(&model, .tool));
    try testing.expectEqualStrings("Reading file · read · pending", lastTool(&model));
    try testing.expectEqual(@as(usize, 0), lastAssistant(&model).len);

    try fx.feedLine(key, "{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"sessionId\":\"acp-tool-1\",\"update\":{\"sessionUpdate\":\"tool_call_update\",\"toolCallId\":\"call_001\",\"status\":\"completed\"}}}");
    drainEffects(&model, &fx);
    try testing.expectEqual(@as(usize, 1), countRole(&model, .tool));
    try testing.expectEqualStrings("Reading file · read · completed", lastTool(&model));
    try testing.expect(std.mem.indexOf(u8, lastTool(&model), "pending") == null);

    try fx.feedLine(key, "{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"sessionId\":\"acp-tool-1\",\"update\":{\"sessionUpdate\":\"agent_message_chunk\",\"content\":{\"type\":\"text\",\"text\":\"done\"}}}}");
    drainEffects(&model, &fx);
    try testing.expectEqualStrings("done", lastAssistant(&model));
    try testing.expectEqualStrings("Reading file · read · completed", lastTool(&model));

    try fx.feedLine(key, "{\"jsonrpc\":\"2.0\",\"id\":3,\"result\":{\"stopReason\":\"end_turn\"}}");
    drainEffects(&model, &fx);
    try testing.expect(!model.is_streaming());
    try testing.expectEqual(@as(usize, 1), countRole(&model, .tool));
    try testing.expectEqual(@as(u32, 0), model.queuedCount(id));
}

test "ACP tool_call content shows text and diff; update replaces; unknown kinds ignored" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.fx_available = true;
    model.fx_probe_started = true;
    model.setFxPath("fx");
    const id = model.addSession("acp tool content", .fx);
    model.selected = id;
    main.update(&model, .{ .draft_edit = .{ .insert_text = "edit the file" } }, &fx);
    main.update(&model, .send, &fx);
    try testing.expect(model.fx_spawn_acp);
    const key = model.fx_spawn_key;

    try fx.feedLine(key, "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"sessionId\":\"acp-tool-content-1\"}}");
    drainEffects(&model, &fx);

    try fx.feedLine(key, "{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"sessionId\":\"acp-tool-content-1\",\"update\":{\"sessionUpdate\":\"tool_call\",\"toolCallId\":\"call_content\",\"title\":\"Editing file\",\"kind\":\"edit\",\"status\":\"pending\",\"content\":[{\"type\":\"content\",\"content\":{\"type\":\"text\",\"text\":\"Found 3 files\"}},{\"type\":\"diff\",\"path\":\"src/config.json\",\"oldText\":\"debug: false\",\"newText\":\"debug: true\"},{\"type\":\"content\",\"content\":{\"type\":\"image\",\"mimeType\":\"image/png\",\"data\":\"aaaa\"}},{\"type\":\"terminal\",\"terminalId\":\"term_1\"},{\"type\":\"not_a_real_block\",\"text\":\"ignore me\"}]}}}");
    drainEffects(&model, &fx);
    try testing.expectEqual(@as(usize, 1), countRole(&model, .tool));
    try testing.expectEqualStrings(
        "Editing file · edit · pending\nFound 3 files\n\nsrc/config.json\n---\ndebug: false\n+++\ndebug: true",
        lastTool(&model),
    );
    try testing.expect(std.mem.indexOf(u8, lastTool(&model), "aaaa") == null);
    try testing.expect(std.mem.indexOf(u8, lastTool(&model), "term_1") == null);
    try testing.expect(std.mem.indexOf(u8, lastTool(&model), "ignore me") == null);

    const tree = try buildTree(arena, &model);
    try testing.expect(findAnyText(tree.root, lastTool(&model)));

    try fx.feedLine(key, "{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"update\":{\"sessionUpdate\":\"tool_call_update\",\"toolCallId\":\"call_content\",\"status\":\"completed\",\"content\":[{\"type\":\"content\",\"content\":{\"type\":\"text\",\"text\":\"File written successfully\"}}]}}}");
    drainEffects(&model, &fx);
    try testing.expectEqual(@as(usize, 1), countRole(&model, .tool));
    try testing.expectEqualStrings(
        "Editing file · edit · completed\nFile written successfully",
        lastTool(&model),
    );
    try testing.expect(std.mem.indexOf(u8, lastTool(&model), "Found 3 files") == null);
    try testing.expect(std.mem.indexOf(u8, lastTool(&model), "debug: false") == null);
    try testing.expect(std.mem.indexOf(u8, lastTool(&model), "pending") == null);

    try fx.feedLine(key, "{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"update\":{\"sessionUpdate\":\"tool_call_update\",\"toolCallId\":\"call_content\",\"status\":\"in_progress\"}}}");
    drainEffects(&model, &fx);
    try testing.expectEqualStrings(
        "Editing file · edit · in_progress\nFile written successfully",
        lastTool(&model),
    );

    try fx.feedLine(key, "{\"jsonrpc\":\"2.0\",\"id\":3,\"result\":{\"stopReason\":\"end_turn\"}}");
    drainEffects(&model, &fx);
    try testing.expect(!model.is_streaming());
    try testing.expectEqual(@as(usize, 1), countRole(&model, .tool));
}

test "ACP session/update agent_thought_chunk adds a reasoning row; later chunk appends" {
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.fx_available = true;
    model.fx_probe_started = true;
    model.setFxPath("fx");
    const id = model.addSession("acp thought", .fx);
    model.selected = id;
    main.update(&model, .{ .draft_edit = .{ .insert_text = "think then reply" } }, &fx);
    main.update(&model, .send, &fx);
    try testing.expect(model.fx_spawn_acp);
    const key = model.fx_spawn_key;

    try fx.feedLine(key, "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"sessionId\":\"acp-thought-1\"}}");
    drainEffects(&model, &fx);
    try testing.expectEqual(@as(usize, 0), countRole(&model, .reasoning));
    try testing.expectEqual(@as(usize, 0), lastAssistant(&model).len);

    try fx.feedLine(key, "{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"sessionId\":\"acp-thought-1\",\"update\":{\"sessionUpdate\":\"agent_thought_chunk\",\"content\":{\"type\":\"text\",\"text\":\"need to inspect the loop\"}}}}");
    drainEffects(&model, &fx);
    try testing.expectEqual(@as(usize, 1), countRole(&model, .reasoning));
    try testing.expectEqualStrings("need to inspect the loop", lastReasoning(&model));
    try testing.expectEqual(@as(usize, 0), lastAssistant(&model).len);
    try testing.expectEqual(@as(usize, 0), countRole(&model, .tool));

    try fx.feedLine(key, "{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"sessionId\":\"acp-thought-1\",\"update\":{\"sessionUpdate\":\"agent_thought_chunk\",\"content\":{\"type\":\"text\",\"text\":\" before suggesting a fix\"}}}}");
    drainEffects(&model, &fx);
    try testing.expectEqual(@as(usize, 1), countRole(&model, .reasoning));
    try testing.expectEqualStrings("need to inspect the loop before suggesting a fix", lastReasoning(&model));
    try testing.expectEqual(@as(usize, 0), lastAssistant(&model).len);

    try fx.feedLine(key, "{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"sessionId\":\"acp-thought-1\",\"update\":{\"sessionUpdate\":\"agent_message_chunk\",\"content\":{\"type\":\"text\",\"text\":\"here is the fix\"}}}}");
    drainEffects(&model, &fx);
    try testing.expectEqualStrings("here is the fix", lastAssistant(&model));
    try testing.expectEqualStrings("need to inspect the loop before suggesting a fix", lastReasoning(&model));
    try testing.expect(std.mem.indexOf(u8, lastAssistant(&model), "inspect the loop") == null);

    try fx.feedLine(key, "{\"jsonrpc\":\"2.0\",\"id\":3,\"result\":{\"stopReason\":\"end_turn\"}}");
    drainEffects(&model, &fx);
    try testing.expect(!model.is_streaming());
    try testing.expectEqual(@as(usize, 1), countRole(&model, .reasoning));
    try testing.expectEqual(@as(usize, 1), countRole(&model, .assistant));
    try testing.expectEqual(@as(u32, 0), model.queuedCount(id));
}

test "ACP current_mode_update ask then code updates access chip and persists; unknown is ignored" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-current-mode", .{tmp.sub_path[0..]});

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
    const id = model.addSession("mode chip", .fx);
    model.selected = id;
    try store.saveSession(&model, id, testing.allocator, testing.io);
    try testing.expectEqualStrings("fullAccess", model.sessionById(id).?.accessMode());
    try testing.expectEqualStrings("Full access", model.access_label());

    var tree = try buildTree(arena, &model);
    _ = try expectByText(tree.root, .button, "Full access");
    _ = try expectByText(tree.root, .button, "Build");

    main.update(&model, .{ .draft_edit = .{ .insert_text = "switch modes" } }, &fx);
    main.update(&model, .send, &fx);
    try testing.expect(model.fx_spawn_acp);
    const key = model.fx_spawn_key;

    try fx.feedLine(key, "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"sessionId\":\"acp-mode-1\"}}");
    drainEffects(&model, &fx);

    try fx.feedLine(key, "{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"sessionId\":\"acp-mode-1\",\"update\":{\"sessionUpdate\":\"current_mode_update\",\"currentModeId\":\"architect\"}}}");
    drainEffects(&model, &fx);
    try testing.expectEqualStrings("fullAccess", model.sessionById(id).?.accessMode());
    try testing.expectEqualStrings("Full access", model.access_label());
    try testing.expectEqual(@as(usize, 0), lastAssistant(&model).len);

    try fx.feedLine(key, "{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"sessionId\":\"acp-mode-1\",\"update\":{\"sessionUpdate\":\"current_mode_update\",\"currentModeId\":\"ask\"}}}");
    drainEffects(&model, &fx);
    try testing.expectEqualStrings("ask", model.sessionById(id).?.accessMode());
    try testing.expectEqualStrings("ask", model.lastAccessMode());
    try testing.expectEqualStrings("Ask", model.access_label());
    tree = try buildTree(arena, &model);
    _ = try expectByText(tree.root, .button, "Ask");
    try testing.expect(findByText(tree.root, .button, "Full access") == null);

    try fx.feedLine(key, "{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"sessionId\":\"acp-mode-1\",\"update\":{\"sessionUpdate\":\"agent_thought_chunk\",\"content\":{\"type\":\"text\",\"text\":\"stay on the reasoning row\"}}}}");
    drainEffects(&model, &fx);
    try testing.expectEqualStrings("stay on the reasoning row", lastReasoning(&model));
    try testing.expectEqualStrings("ask", model.sessionById(id).?.accessMode());

    try fx.feedLine(key, "{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"sessionId\":\"acp-mode-1\",\"update\":{\"sessionUpdate\":\"tool_call\",\"toolCallId\":\"call_mode\",\"title\":\"Reading file\",\"kind\":\"read\",\"status\":\"pending\"}}}");
    drainEffects(&model, &fx);
    try testing.expectEqualStrings("Reading file · read · pending", lastTool(&model));

    try fx.feedLine(key, "{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"sessionId\":\"acp-mode-1\",\"update\":{\"sessionUpdate\":\"current_mode_update\",\"currentModeId\":\"code\"}}}");
    drainEffects(&model, &fx);
    try testing.expectEqualStrings("fullAccess", model.sessionById(id).?.accessMode());
    try testing.expectEqualStrings("fullAccess", model.lastAccessMode());
    try testing.expectEqualStrings("Full access", model.access_label());
    try testing.expectEqualStrings("stay on the reasoning row", lastReasoning(&model));
    try testing.expectEqualStrings("Reading file · read · pending", lastTool(&model));
    tree = try buildTree(arena, &model);
    _ = try expectByText(tree.root, .button, "Full access");
    try testing.expect(findByText(tree.root, .button, "Ask") == null);

    try fx.feedLine(key, "{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"sessionId\":\"acp-mode-1\",\"update\":{\"sessionUpdate\":\"agent_message_chunk\",\"content\":{\"type\":\"text\",\"text\":\"mode switched\"}}}}");
    drainEffects(&model, &fx);
    try testing.expectEqualStrings("mode switched", lastAssistant(&model));
    try testing.expect(std.mem.indexOf(u8, lastAssistant(&model), "current_mode_update") == null);
    try testing.expect(std.mem.indexOf(u8, lastAssistant(&model), "fullAccess") == null);

    try fx.feedLine(key, "{\"jsonrpc\":\"2.0\",\"id\":3,\"result\":{\"stopReason\":\"end_turn\"}}");
    drainEffects(&model, &fx);
    try testing.expect(!model.is_streaming());
    try testing.expectEqual(@as(usize, 1), countRole(&model, .reasoning));
    try testing.expectEqual(@as(usize, 1), countRole(&model, .tool));
    try testing.expectEqual(@as(usize, 1), countRole(&model, .assistant));

    var loaded = Model{};
    loaded.setStoreDir(dir);
    loaded.store_io = testing.io;
    try testing.expectEqual(store.LoadKind.loaded, store.loadCatalog(&loaded, testing.allocator, testing.io));
    try testing.expectEqualStrings("fullAccess", loaded.session_store[0].accessMode());
    try testing.expectEqualStrings("fullAccess", loaded.lastAccessMode());
    try testing.expectEqualStrings("Full access", loaded.access_label());
    tree = try buildTree(arena, &loaded);
    _ = try expectByText(tree.root, .button, "Full access");
    _ = try expectByText(tree.root, .button, "Build");
}

test "ACP config_option_update sets model chip and persists; unknown is ignored" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-config-model", .{tmp.sub_path[0..]});

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
    const id = model.addSession("model chip", .fx);
    model.selected = id;
    try store.saveSession(&model, id, testing.allocator, testing.io);
    try testing.expectEqual(@as(usize, 0), model.sessionById(id).?.model().len);
    try testing.expectEqualStrings("FX_MODEL", model.model_label());

    var tree = try buildTree(arena, &model);
    _ = try expectByText(tree.root, .button, "FX_MODEL");
    _ = try expectByText(tree.root, .button, "Full access");
    _ = try expectByText(tree.root, .button, "Build");

    main.update(&model, .{ .draft_edit = .{ .insert_text = "switch models" } }, &fx);
    main.update(&model, .send, &fx);
    try testing.expect(model.fx_spawn_acp);
    const key = model.fx_spawn_key;

    try fx.feedLine(key, "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"sessionId\":\"acp-model-1\"}}");
    drainEffects(&model, &fx);

    try fx.feedLine(key, "{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"sessionId\":\"acp-model-1\",\"update\":{\"sessionUpdate\":\"config_option_update\",\"configOptions\":[{\"id\":\"mode\",\"name\":\"Session Mode\",\"type\":\"select\",\"currentValue\":\"ask\",\"options\":[]}]}}}");
    drainEffects(&model, &fx);
    try testing.expectEqual(@as(usize, 0), model.sessionById(id).?.model().len);
    try testing.expectEqualStrings("FX_MODEL", model.model_label());
    try testing.expectEqualStrings("fullAccess", model.sessionById(id).?.accessMode());
    try testing.expectEqual(@as(usize, 0), lastAssistant(&model).len);

    try fx.feedLine(key, "{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"sessionId\":\"acp-model-1\",\"update\":{\"sessionUpdate\":\"session_info_update\",\"title\":\"not a model\"}}}");
    drainEffects(&model, &fx);
    try testing.expectEqualStrings("FX_MODEL", model.model_label());

    try fx.feedLine(key, "{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"sessionId\":\"acp-model-1\",\"update\":{\"sessionUpdate\":\"config_option_update\",\"configOptions\":[{\"id\":\"mode\",\"name\":\"Session Mode\",\"type\":\"select\",\"currentValue\":\"code\",\"options\":[]},{\"id\":\"model\",\"name\":\"Model\",\"type\":\"select\",\"currentValue\":\"openai/gpt-5.4\",\"options\":[{\"value\":\"openai/gpt-5.4\",\"name\":\"GPT\"},{\"value\":\"anthropic/claude-sonnet-4\",\"name\":\"Claude\"}]}]}}}");
    drainEffects(&model, &fx);
    try testing.expectEqualStrings("openai/gpt-5.4", model.sessionById(id).?.model());
    try testing.expectEqualStrings("openai/gpt-5.4", model.lastModel());
    try testing.expectEqualStrings("openai/gpt-5.4", model.model_label());
    try testing.expectEqualStrings("fullAccess", model.sessionById(id).?.accessMode());
    tree = try buildTree(arena, &model);
    _ = try expectByText(tree.root, .button, "openai/gpt-5.4");
    try testing.expect(findByText(tree.root, .button, "FX_MODEL") == null);
    try testing.expect(findByText(tree.root, .button, "anthropic/claude-sonnet-4") == null);

    try fx.feedLine(key, "{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"sessionId\":\"acp-model-1\",\"update\":{\"sessionUpdate\":\"current_mode_update\",\"currentModeId\":\"ask\"}}}");
    drainEffects(&model, &fx);
    try testing.expectEqualStrings("ask", model.sessionById(id).?.accessMode());
    try testing.expectEqualStrings("openai/gpt-5.4", model.sessionById(id).?.model());

    try fx.feedLine(key, "{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"sessionId\":\"acp-model-1\",\"update\":{\"sessionUpdate\":\"agent_thought_chunk\",\"content\":{\"type\":\"text\",\"text\":\"stay on the reasoning row\"}}}}");
    drainEffects(&model, &fx);
    try testing.expectEqualStrings("stay on the reasoning row", lastReasoning(&model));
    try testing.expectEqualStrings("openai/gpt-5.4", model.sessionById(id).?.model());

    try fx.feedLine(key, "{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"sessionId\":\"acp-model-1\",\"update\":{\"sessionUpdate\":\"tool_call\",\"toolCallId\":\"call_model\",\"title\":\"Reading file\",\"kind\":\"read\",\"status\":\"pending\"}}}");
    drainEffects(&model, &fx);
    try testing.expectEqualStrings("Reading file · read · pending", lastTool(&model));

    try fx.feedLine(key, "{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"sessionId\":\"acp-model-1\",\"update\":{\"sessionUpdate\":\"config_option_update\",\"configOptions\":[{\"id\":\"model\",\"name\":\"Model\",\"type\":\"select\",\"currentValue\":\"\",\"options\":[]}]}}}");
    drainEffects(&model, &fx);
    try testing.expectEqual(@as(usize, 0), model.sessionById(id).?.model().len);
    try testing.expectEqualStrings("openai/gpt-5.4", model.lastModel());
    try testing.expectEqualStrings("FX_MODEL", model.model_label());
    try testing.expectEqualStrings("stay on the reasoning row", lastReasoning(&model));
    try testing.expectEqualStrings("Reading file · read · pending", lastTool(&model));
    tree = try buildTree(arena, &model);
    _ = try expectByText(tree.root, .button, "FX_MODEL");
    try testing.expect(findByText(tree.root, .button, "openai/gpt-5.4") == null);

    try fx.feedLine(key, "{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"sessionId\":\"acp-model-1\",\"update\":{\"sessionUpdate\":\"agent_message_chunk\",\"content\":{\"type\":\"text\",\"text\":\"model switched\"}}}}");
    drainEffects(&model, &fx);
    try testing.expectEqualStrings("model switched", lastAssistant(&model));
    try testing.expect(std.mem.indexOf(u8, lastAssistant(&model), "config_option_update") == null);
    try testing.expect(std.mem.indexOf(u8, lastAssistant(&model), "openai/gpt-5.4") == null);

    try fx.feedLine(key, "{\"jsonrpc\":\"2.0\",\"id\":3,\"result\":{\"stopReason\":\"end_turn\"}}");
    drainEffects(&model, &fx);
    try testing.expect(!model.is_streaming());
    try testing.expectEqual(@as(usize, 1), countRole(&model, .reasoning));
    try testing.expectEqual(@as(usize, 1), countRole(&model, .tool));
    try testing.expectEqual(@as(usize, 1), countRole(&model, .assistant));

    var loaded = Model{};
    loaded.setStoreDir(dir);
    loaded.store_io = testing.io;
    try testing.expectEqual(store.LoadKind.loaded, store.loadCatalog(&loaded, testing.allocator, testing.io));
    try testing.expectEqual(@as(usize, 0), loaded.session_store[0].model().len);
    try testing.expectEqualStrings("openai/gpt-5.4", loaded.lastModel());
    try testing.expectEqualStrings("FX_MODEL", loaded.model_label());
    try testing.expectEqualStrings("ask", loaded.session_store[0].accessMode());
    tree = try buildTree(arena, &loaded);
    _ = try expectByText(tree.root, .button, "FX_MODEL");
    _ = try expectByText(tree.root, .button, "Ask");
    _ = try expectByText(tree.root, .button, "Build");
}

test "ACP available_commands_update stores names; empty clears; unknown is ignored" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-available-commands", .{tmp.sub_path[0..]});

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
    const id = model.addSession("commands store", .fx);
    model.selected = id;
    try store.saveSession(&model, id, testing.allocator, testing.io);
    try testing.expectEqual(@as(usize, 0), model.sessionById(id).?.availableCommands().len);

    var tree = try buildTree(arena, &model);
    _ = try expectByText(tree.root, .button, "FX_MODEL");
    _ = try expectByText(tree.root, .button, "Full access");
    _ = try expectByText(tree.root, .button, "Build");

    main.update(&model, .{ .draft_edit = .{ .insert_text = "list commands" } }, &fx);
    main.update(&model, .send, &fx);
    try testing.expect(model.fx_spawn_acp);
    const key = model.fx_spawn_key;

    try fx.feedLine(key, "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"sessionId\":\"acp-cmd-1\"}}");
    drainEffects(&model, &fx);

    try fx.feedLine(key, "{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"sessionId\":\"acp-cmd-1\",\"update\":{\"sessionUpdate\":\"session_info_update\",\"title\":\"not commands\"}}}");
    drainEffects(&model, &fx);
    try testing.expectEqual(@as(usize, 0), model.sessionById(id).?.availableCommands().len);
    try testing.expectEqual(@as(usize, 0), lastAssistant(&model).len);

    try fx.feedLine(key, "{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"sessionId\":\"acp-cmd-1\",\"update\":{\"sessionUpdate\":\"available_commands_update\"}}}");
    drainEffects(&model, &fx);
    try testing.expectEqual(@as(usize, 0), model.sessionById(id).?.availableCommands().len);

    try fx.feedLine(key, "{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"sessionId\":\"acp-cmd-1\",\"update\":{\"sessionUpdate\":\"available_commands_update\",\"availableCommands\":[{\"name\":\"web\",\"description\":\"Search the web for information\",\"input\":{\"hint\":\"query to search for\"}},{\"name\":\"test\",\"description\":\"Run tests for the current project\"},{\"name\":\"compact\"}]}}}");
    drainEffects(&model, &fx);
    try testing.expectEqual(@as(usize, 3), model.sessionById(id).?.availableCommands().len);
    try testing.expectEqualStrings("web", model.sessionById(id).?.availableCommands()[0].name());
    try testing.expectEqualStrings("Search the web for information", model.sessionById(id).?.availableCommands()[0].description());
    try testing.expectEqualStrings("test", model.sessionById(id).?.availableCommands()[1].name());
    try testing.expectEqualStrings("Run tests for the current project", model.sessionById(id).?.availableCommands()[1].description());
    try testing.expectEqualStrings("compact", model.sessionById(id).?.availableCommands()[2].name());
    try testing.expectEqualStrings("", model.sessionById(id).?.availableCommands()[2].description());
    try testing.expectEqualStrings("fullAccess", model.sessionById(id).?.accessMode());
    tree = try buildTree(arena, &model);
    _ = try expectButton(tree.root, "Commands");
    try testing.expect(findByText(tree.root, .button, "web") == null);
    try testing.expect(findByText(tree.root, .button, "compact") == null);
    try testing.expect(findByText(tree.root, .text, "/web") == null);
    try testing.expect(findByText(tree.root, .text, "Search the web for information") == null);

    try fx.feedLine(key, "{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"sessionId\":\"acp-cmd-1\",\"update\":{\"sessionUpdate\":\"available_commands_update\",\"availableCommands\":[{\"name\":\"plan\",\"description\":\"Create a detailed implementation plan\"}]}}}");
    drainEffects(&model, &fx);
    try testing.expectEqual(@as(usize, 1), model.sessionById(id).?.availableCommands().len);
    try testing.expectEqualStrings("plan", model.sessionById(id).?.availableCommands()[0].name());
    try testing.expectEqualStrings("Create a detailed implementation plan", model.sessionById(id).?.availableCommands()[0].description());

    try fx.feedLine(key, "{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"sessionId\":\"acp-cmd-1\",\"update\":{\"sessionUpdate\":\"current_mode_update\",\"currentModeId\":\"ask\"}}}");
    drainEffects(&model, &fx);
    try testing.expectEqualStrings("ask", model.sessionById(id).?.accessMode());
    try testing.expectEqualStrings("plan", model.sessionById(id).?.availableCommands()[0].name());

    try fx.feedLine(key, "{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"sessionId\":\"acp-cmd-1\",\"update\":{\"sessionUpdate\":\"agent_thought_chunk\",\"content\":{\"type\":\"text\",\"text\":\"stay on the reasoning row\"}}}}");
    drainEffects(&model, &fx);
    try testing.expectEqualStrings("stay on the reasoning row", lastReasoning(&model));
    try testing.expectEqualStrings("plan", model.sessionById(id).?.availableCommands()[0].name());

    try fx.feedLine(key, "{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"sessionId\":\"acp-cmd-1\",\"update\":{\"sessionUpdate\":\"tool_call\",\"toolCallId\":\"call_cmd\",\"title\":\"Reading file\",\"kind\":\"read\",\"status\":\"pending\"}}}");
    drainEffects(&model, &fx);
    try testing.expectEqualStrings("Reading file · read · pending", lastTool(&model));

    try fx.feedLine(key, "{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"sessionId\":\"acp-cmd-1\",\"update\":{\"sessionUpdate\":\"available_commands_update\",\"availableCommands\":[]}}}");
    drainEffects(&model, &fx);
    try testing.expectEqual(@as(usize, 0), model.sessionById(id).?.availableCommands().len);
    try testing.expect(!model.has_commands());
    try testing.expect(!model.commands_open);
    tree = try buildTree(arena, &model);
    try testing.expect(findByText(tree.root, .button, "Commands") == null);
    try testing.expectEqualStrings("stay on the reasoning row", lastReasoning(&model));
    try testing.expectEqualStrings("Reading file · read · pending", lastTool(&model));
    try testing.expectEqualStrings("ask", model.sessionById(id).?.accessMode());

    try fx.feedLine(key, "{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"sessionId\":\"acp-cmd-1\",\"update\":{\"sessionUpdate\":\"agent_message_chunk\",\"content\":{\"type\":\"text\",\"text\":\"commands stored\"}}}}");
    drainEffects(&model, &fx);
    try testing.expectEqualStrings("commands stored", lastAssistant(&model));
    try testing.expect(std.mem.indexOf(u8, lastAssistant(&model), "available_commands_update") == null);
    try testing.expect(std.mem.indexOf(u8, lastAssistant(&model), "compact") == null);

    try fx.feedLine(key, "{\"jsonrpc\":\"2.0\",\"id\":3,\"result\":{\"stopReason\":\"end_turn\"}}");
    drainEffects(&model, &fx);
    try testing.expect(!model.is_streaming());
    try testing.expectEqual(@as(usize, 1), countRole(&model, .reasoning));
    try testing.expectEqual(@as(usize, 1), countRole(&model, .tool));
    try testing.expectEqual(@as(usize, 1), countRole(&model, .assistant));

    var loaded = Model{};
    loaded.setStoreDir(dir);
    loaded.store_io = testing.io;
    try testing.expectEqual(store.LoadKind.loaded, store.loadCatalog(&loaded, testing.allocator, testing.io));
    try testing.expectEqual(@as(usize, 0), loaded.session_store[0].availableCommands().len);
    try testing.expectEqualStrings("ask", loaded.session_store[0].accessMode());
    tree = try buildTree(arena, &loaded);
    _ = try expectByText(tree.root, .button, "FX_MODEL");
    _ = try expectByText(tree.root, .button, "Ask");
    _ = try expectByText(tree.root, .button, "Build");
    try testing.expect(findByText(tree.root, .button, "plan") == null);
    try testing.expect(findByText(tree.root, .button, "Commands") == null);
}

test "ACP session_info_update sets title and persists; empty cwd unknown ignored" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-session-info", .{tmp.sub_path[0..]});

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
    const id = model.addSession("info title", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath("/tmp/faku-session-info");
    try store.saveSession(&model, id, testing.allocator, testing.io);
    try testing.expectEqualStrings("info title", model.sessionById(id).?.title());
    try testing.expectEqualStrings("info title", model.header_title());
    try testing.expectEqualStrings("/tmp/faku-session-info", model.sessionById(id).?.projectPath());

    var tree = try buildTree(arena, &model);
    _ = try expectByText(tree.root, .text, "info title");
    _ = try expectByText(tree.root, .button, "FX_MODEL");
    _ = try expectByText(tree.root, .button, "Full access");
    _ = try expectByText(tree.root, .button, "Build");

    main.update(&model, .{ .draft_edit = .{ .insert_text = "name the session" } }, &fx);
    main.update(&model, .send, &fx);
    try testing.expect(model.fx_spawn_acp);
    const key = model.fx_spawn_key;

    try fx.feedLine(key, "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"sessionId\":\"acp-info-1\"}}");
    drainEffects(&model, &fx);

    try fx.feedLine(key, "{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"sessionId\":\"acp-info-1\",\"update\":{\"sessionUpdate\":\"session_info_update\",\"title\":\"\",\"cwd\":\"/tmp/should-not-apply\"}}}");
    drainEffects(&model, &fx);
    try testing.expectEqualStrings("info title", model.sessionById(id).?.title());
    try testing.expectEqualStrings("/tmp/faku-session-info", model.sessionById(id).?.projectPath());
    try testing.expectEqual(@as(usize, 0), lastAssistant(&model).len);

    try fx.feedLine(key, "{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"sessionId\":\"acp-info-1\",\"update\":{\"sessionUpdate\":\"session_info_update\",\"updatedAt\":\"2025-10-29T14:22:15Z\"}}}");
    drainEffects(&model, &fx);
    try testing.expectEqualStrings("info title", model.sessionById(id).?.title());

    try fx.feedLine(key, "{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"sessionId\":\"acp-info-1\",\"update\":{\"sessionUpdate\":\"session_info_update\",\"_meta\":{\"fx\":{\"modelResponseRecovery\":null}}}}}");
    drainEffects(&model, &fx);
    try testing.expectEqualStrings("info title", model.sessionById(id).?.title());
    try testing.expectEqualStrings("/tmp/faku-session-info", model.sessionById(id).?.projectPath());

    try fx.feedLine(key, "{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"sessionId\":\"acp-info-1\",\"update\":{\"sessionUpdate\":\"session_info_update\",\"title\":\"Implement user authentication\",\"cwd\":\"/tmp/should-not-apply\",\"updatedAt\":\"2025-10-29T14:22:15Z\"}}}");
    drainEffects(&model, &fx);
    try testing.expectEqualStrings("Implement user authentication", model.sessionById(id).?.title());
    try testing.expectEqualStrings("Implement user authentication", model.header_title());
    try testing.expectEqualStrings("Implement user authentication", model.selected_title());
    try testing.expect(!model.sessionById(id).?.untitled);
    try testing.expectEqualStrings("/tmp/faku-session-info", model.sessionById(id).?.projectPath());
    try expectSidebarTitles(model.sidebar_rows(arena), &.{"Implement user authentication"});
    tree = try buildTree(arena, &model);
    _ = try expectByText(tree.root, .text, "Implement user authentication");
    try testing.expect(findByText(tree.root, .text, "info title") == null);

    try fx.feedLine(key, "{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"sessionId\":\"acp-info-1\",\"update\":{\"sessionUpdate\":\"current_mode_update\",\"currentModeId\":\"ask\"}}}");
    drainEffects(&model, &fx);
    try testing.expectEqualStrings("ask", model.sessionById(id).?.accessMode());
    try testing.expectEqualStrings("Implement user authentication", model.sessionById(id).?.title());

    try fx.feedLine(key, "{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"sessionId\":\"acp-info-1\",\"update\":{\"sessionUpdate\":\"config_option_update\",\"configOptions\":[{\"id\":\"model\",\"name\":\"Model\",\"type\":\"select\",\"currentValue\":\"openai/gpt-5.4\",\"options\":[]}]}}}");
    drainEffects(&model, &fx);
    try testing.expectEqualStrings("openai/gpt-5.4", model.sessionById(id).?.model());
    try testing.expectEqualStrings("Implement user authentication", model.sessionById(id).?.title());

    try fx.feedLine(key, "{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"sessionId\":\"acp-info-1\",\"update\":{\"sessionUpdate\":\"available_commands_update\",\"availableCommands\":[{\"name\":\"compact\"}]}}}");
    drainEffects(&model, &fx);
    try testing.expectEqual(@as(usize, 1), model.sessionById(id).?.availableCommands().len);
    try testing.expectEqualStrings("compact", model.sessionById(id).?.availableCommands()[0].name());

    try fx.feedLine(key, "{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"sessionId\":\"acp-info-1\",\"update\":{\"sessionUpdate\":\"agent_thought_chunk\",\"content\":{\"type\":\"text\",\"text\":\"stay on the reasoning row\"}}}}");
    drainEffects(&model, &fx);
    try testing.expectEqualStrings("stay on the reasoning row", lastReasoning(&model));
    try testing.expectEqualStrings("Implement user authentication", model.sessionById(id).?.title());

    try fx.feedLine(key, "{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"sessionId\":\"acp-info-1\",\"update\":{\"sessionUpdate\":\"tool_call\",\"toolCallId\":\"call_info\",\"title\":\"Reading file\",\"kind\":\"read\",\"status\":\"pending\"}}}");
    drainEffects(&model, &fx);
    try testing.expectEqualStrings("Reading file · read · pending", lastTool(&model));
    try testing.expectEqualStrings("Implement user authentication", model.sessionById(id).?.title());

    try fx.feedLine(key, "{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"sessionId\":\"acp-info-1\",\"update\":{\"sessionUpdate\":\"agent_message_chunk\",\"content\":{\"type\":\"text\",\"text\":\"title updated\"}}}}");
    drainEffects(&model, &fx);
    try testing.expectEqualStrings("title updated", lastAssistant(&model));
    try testing.expect(std.mem.indexOf(u8, lastAssistant(&model), "session_info_update") == null);
    try testing.expect(std.mem.indexOf(u8, lastAssistant(&model), "Implement user authentication") == null);

    try fx.feedLine(key, "{\"jsonrpc\":\"2.0\",\"id\":3,\"result\":{\"stopReason\":\"end_turn\"}}");
    drainEffects(&model, &fx);
    try testing.expect(!model.is_streaming());
    try testing.expectEqual(@as(usize, 1), countRole(&model, .reasoning));
    try testing.expectEqual(@as(usize, 1), countRole(&model, .tool));
    try testing.expectEqual(@as(usize, 1), countRole(&model, .assistant));
    try testing.expectEqualStrings("Implement user authentication", model.sessionById(id).?.title());
    try testing.expectEqualStrings("/tmp/faku-session-info", model.sessionById(id).?.projectPath());

    var loaded = Model{};
    loaded.setStoreDir(dir);
    loaded.store_io = testing.io;
    try testing.expectEqual(store.LoadKind.loaded, store.loadCatalog(&loaded, testing.allocator, testing.io));
    try testing.expectEqualStrings("Implement user authentication", loaded.session_store[0].title());
    try testing.expect(!loaded.session_store[0].untitled);
    try testing.expectEqualStrings("/tmp/faku-session-info", loaded.session_store[0].projectPath());
    try testing.expectEqualStrings("ask", loaded.session_store[0].accessMode());
    try testing.expectEqualStrings("openai/gpt-5.4", loaded.session_store[0].model());
    try testing.expectEqual(@as(usize, 1), loaded.session_store[0].availableCommands().len);
    try expectSidebarTitles(loaded.sidebar_rows(arena), &.{"Implement user authentication"});
    tree = try buildTree(arena, &loaded);
    _ = try expectByText(tree.root, .text, "Implement user authentication");
    _ = try expectByText(tree.root, .button, "openai/gpt-5.4");
    _ = try expectByText(tree.root, .button, "Ask");
    _ = try expectByText(tree.root, .button, "Build");
}

test "composer Commands lists stored names; empty hides; pick inserts /name and persists; no spawn" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-command-insert", .{tmp.sub_path[0..]});

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
    const id = model.addSession("command insert", .fx);
    _ = model.appendTurn(id, .user, "already started");
    model.selected = id;
    try store.saveSession(&model, id, testing.allocator, testing.io);

    var tree = try buildTree(arena, &model);
    try testing.expect(findByText(tree.root, .button, "Commands") == null);
    try testing.expect(findByText(tree.root, .text, "/web") == null);

    if (model.sessionById(id)) |session| {
        session.appendAvailableCommand("web", "Search the web for information");
        session.appendAvailableCommand("compact", "");
    }
    try store.saveSession(&model, id, testing.allocator, testing.io);
    try testing.expect(model.has_commands());
    try testing.expect(!model.commands_list_open());

    tree = try buildTree(arena, &model);
    const commands = try expectButton(tree.root, "Commands");
    try testing.expect(findByText(tree.root, .text, "/web") == null);
    try testing.expect(findByText(tree.root, .text, "Search the web for information") == null);
    try testing.expect(findByText(tree.root, .text, "/compact") == null);

    main.update(&model, tree.msgForPointer(commands.id, .up).?, &fx);
    try testing.expect(model.commands_open);
    try testing.expect(model.commands_list_open());
    try testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());

    tree = try buildTree(arena, &model);
    _ = try expectByText(tree.root, .text, "/web");
    _ = try expectByText(tree.root, .text, "Search the web for information");
    _ = try expectByText(tree.root, .text, "/compact");
    const web = try expectButton(tree.root, "/web");

    main.update(&model, tree.msgForPointer(web.id, .up).?, &fx);
    try testing.expectEqualStrings("/web ", model.draft());
    try testing.expect(!model.commands_open);
    try testing.expect(!model.commands_list_open());
    try testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
    try testing.expect(!model.fx_spawn_live);
    try testing.expect(!model.is_streaming());

    tree = try buildTree(arena, &model);
    try testing.expect(findByText(tree.root, .text, "/web") == null);
    try testing.expect(findByText(tree.root, .text, "Search the web for information") == null);
    _ = try expectButton(tree.root, "Commands");
    if (findByKind(tree.root, .textarea)) |composer| {
        try testing.expectEqualStrings("/web ", composer.text);
    }

    const escape = canvas.WidgetKeyboardEvent{ .phase = .key_down, .key = "escape" };
    main.update(&model, .toggle_commands, &fx);
    try testing.expect(model.commands_open);
    try testing.expectEqual(Msg.stop, main.onKey(escape).?);
    main.update(&model, main.onKey(escape).?, &fx);
    try testing.expect(!model.commands_open);
    try testing.expectEqualStrings("/web ", model.draft());
    try testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());

    var loaded = Model{};
    loaded.setStoreDir(dir);
    loaded.store_io = testing.io;
    try testing.expectEqual(store.LoadKind.loaded, store.loadCatalog(&loaded, testing.allocator, testing.io));
    try testing.expectEqual(id, loaded.selected);
    try testing.expectEqualStrings("/web ", loaded.draft());
    try testing.expectEqual(@as(usize, 2), loaded.session_store[0].availableCommands().len);
    try testing.expectEqualStrings("web", loaded.session_store[0].availableCommands()[0].name());
    try testing.expect(loaded.has_commands());
    try testing.expect(!loaded.commands_open);

    tree = try buildTree(arena, &loaded);
    _ = try expectButton(tree.root, "Commands");
    try testing.expect(findByText(tree.root, .text, "/web") == null);
    if (findByKind(tree.root, .textarea)) |composer| {
        try testing.expectEqualStrings("/web ", composer.text);
    }

    if (loaded.sessionById(id)) |session| session.clearAvailableCommands();
    try testing.expect(!loaded.has_commands());
    tree = try buildTree(arena, &loaded);
    try testing.expect(findByText(tree.root, .button, "Commands") == null);
    try testing.expect(findByText(tree.root, .text, "/compact") == null);
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
    try testing.expect(argvHas(request.argv, acp_proxy.SUBCOMMAND));
    try testing.expect(argvHas(request.argv, "--"));
    try testing.expect(argvHas(request.argv, main.fx_env_bin));
    const dash_at = argvIndex(request.argv, "--") orelse return error.MissingDash;
    const env_at = argvIndex(request.argv, main.fx_env_bin) orelse return error.MissingEnv;
    try testing.expect(dash_at < env_at);
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

    try fx.feedLine(request.key, "{\"output\":\"Assistant Markdown\",\"exit_code\":0,\"model\":\"provider/model-id\",\"session_id\":\"fx-ask-1\",\"steps\":1,\"tool_calls\":[]}");
    drainEffects(&model, &fx);
    try testing.expectEqualStrings("fx-ask-1", model.sessionById(id).?.fxSessionId());
    try testing.expectEqual(@as(u64, 0), model.sessionById(id).?.context_used);
    try testing.expectEqual(@as(u64, 0), model.sessionById(id).?.context_size);
    try testing.expectEqual(@as(f32, 0), model.context_usage());
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

test "composer attach pastes image_path, persists, and clears" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-image-attach", .{tmp.sub_path[0..]});
    var image_buf: [256]u8 = undefined;
    const image = try std.fmt.bufPrint(&image_buf, ".zig-cache/tmp/{s}/shot.png", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().writeFile(testing.io, .{ .sub_path = image, .data = "png" });

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.task_state_loaded = true;
    model.setStoreDir(dir);
    model.store_io = testing.io;
    const id = model.addSession("attach session", .fx);
    _ = model.appendTurn(id, .user, "already started");
    model.selected = id;
    try store.saveSession(&model, id, testing.allocator, testing.io);

    var tree = try buildTree(arena, &model);
    const attach = try expectButton(tree.root, "Attach image");
    try testing.expect(findByPlaceholder(tree.root, .text_field, "Image path") == null);
    try testing.expect(findByText(tree.root, .button, "shot.png") == null);

    main.update(&model, tree.msgForPointer(attach.id, .up).?, &fx);
    try testing.expect(model.image_attach_active);

    tree = try buildTree(arena, &model);
    try testing.expect(findByPlaceholder(tree.root, .text_field, "Image path") != null);

    main.update(&model, .{ .image_path_edit = .{ .insert_text = image } }, &fx);
    try testing.expectEqualStrings(image, model.draftImagePath());
    try testing.expectEqualStrings("shot.png", model.image_chip_label());
    try testing.expect(model.has_image_attach());

    tree = try buildTree(arena, &model);
    _ = try expectByText(tree.root, .button, "shot.png");
    _ = try expectButton(tree.root, "Clear image");

    const escape = canvas.WidgetKeyboardEvent{ .phase = .key_down, .key = "escape" };
    try testing.expectEqual(Msg.stop, main.onKey(escape).?);
    main.update(&model, main.onKey(escape).?, &fx);
    try testing.expect(!model.image_attach_active);
    try testing.expectEqualStrings(image, model.draftImagePath());

    var loaded = Model{};
    loaded.setStoreDir(dir);
    loaded.store_io = testing.io;
    try testing.expectEqual(store.LoadKind.loaded, store.loadCatalog(&loaded, testing.allocator, testing.io));
    try testing.expectEqual(id, loaded.selected);
    try testing.expectEqualStrings(image, loaded.draftImagePath());
    try testing.expectEqualStrings("shot.png", loaded.image_chip_label());

    tree = try buildTree(arena, &loaded);
    _ = try expectByText(tree.root, .button, "shot.png");
    const clear = try expectButton(tree.root, "Clear image");
    main.update(&loaded, tree.msgForPointer(clear.id, .up).?, &fx);
    try testing.expectEqual(@as(usize, 0), loaded.draftImagePath().len);
    try testing.expect(!loaded.has_image_attach());
    try testing.expect(!loaded.image_attach_active);

    tree = try buildTree(arena, &loaded);
    try testing.expect(findByText(tree.root, .button, "shot.png") == null);
    try testing.expect(findByText(tree.root, .button, "Clear image") == null);
    _ = try expectButton(tree.root, "Attach image");

    var cleared = Model{};
    cleared.setStoreDir(dir);
    cleared.store_io = testing.io;
    try testing.expectEqual(store.LoadKind.loaded, store.loadCatalog(&cleared, testing.allocator, testing.io));
    try testing.expectEqual(@as(usize, 0), cleared.draftImagePath().len);
}

test "composer attach path uses fx ask --image; ACP spawn has no image blocks" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var image_buf: [256]u8 = undefined;
    const image = try std.fmt.bufPrint(&image_buf, ".zig-cache/tmp/{s}/chip.png", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().writeFile(testing.io, .{ .sub_path = image, .data = "png" });

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.fx_available = true;
    model.fx_probe_started = true;
    model.setFxPath("fx");
    model.store_io = testing.io;
    const id = model.addSession("attach send", .fx);
    model.selected = id;

    main.update(&model, .start_image_attach, &fx);
    main.update(&model, .{ .image_path_edit = .{ .insert_text = image } }, &fx);
    main.update(&model, .{ .draft_edit = .{ .insert_text = "look at this" } }, &fx);
    main.update(&model, .send, &fx);
    try testing.expectEqualStrings(image, model.lastSpawnImagePath());
    try testing.expectEqual(@as(usize, 0), model.draftImagePath().len);
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());

    const ask = fx.pendingSpawnAt(0).?;
    try testing.expect(argvHas(ask.argv, "ask"));
    try testing.expect(!argvHas(ask.argv, "acp"));
    try testing.expect(argvHas(ask.argv, "--image"));
    const image_at = argvIndex(ask.argv, "--image") orelse return error.MissingImage;
    try testing.expectEqualStrings(image, ask.argv[image_at + 1]);
    try testing.expect(std.mem.indexOf(u8, ask.stdin, "\"type\":\"image\"") == null);

    try fx.feedExit(ask.key, 0);
    drainEffects(&model, &fx);
    try testing.expect(!model.is_streaming());

    main.update(&model, .start_image_attach, &fx);
    main.update(&model, .{ .image_path_edit = .{ .insert_text = image } }, &fx);
    main.update(&model, .clear_image_attach, &fx);
    try testing.expectEqual(@as(usize, 0), model.draftImagePath().len);

    main.update(&model, .{ .draft_edit = .{ .insert_text = "text only" } }, &fx);
    main.update(&model, .send, &fx);
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());
    const acp_spawn = fx.pendingSpawnAt(0).?;
    try testing.expect(argvHas(acp_spawn.argv, "acp"));
    try testing.expect(!argvHas(acp_spawn.argv, "ask"));
    try testing.expect(!argvHas(acp_spawn.argv, "--image"));
    try testing.expect(std.mem.indexOf(u8, acp_spawn.stdin, "\"type\":\"text\"") != null);
    try testing.expect(std.mem.indexOf(u8, acp_spawn.stdin, "\"type\":\"image\"") == null);
    try testing.expect(std.mem.indexOf(u8, acp_spawn.stdin, "text only") != null);
}

test "composer attach preview binds when the file exists; missing and clear do not" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var image_buf: [256]u8 = undefined;
    const image = try std.fmt.bufPrint(&image_buf, ".zig-cache/tmp/{s}/preview.png", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().writeFile(testing.io, .{ .sub_path = image, .data = "png" });

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = testing.io;
    const id = model.addSession("preview attach", .fx);
    model.selected = id;

    var tree = try buildTree(arena, &model);
    try testing.expect(findByText(tree.root, .image, "Attached image") == null);

    main.update(&model, .start_image_attach, &fx);
    main.update(&model, .{ .image_path_edit = .{ .insert_text = image } }, &fx);
    try testing.expect(model.has_image_attach());
    try testing.expect(model.has_image_preview());
    try testing.expectEqualStrings(image, model.resolveSpawnImage());
    try testing.expectEqual(@as(usize, 1), fx.pendingImageLoadCount());
    const load = fx.pendingImageLoadAt(0) orelse return error.MissingImageLoad;
    try testing.expectEqualStrings(image, load.path);
    try testing.expect(load.id >= main.attach_preview_id_first);
    try testing.expect(load.id <= main.attach_preview_id_last);

    tree = try buildTree(arena, &model);
    const preview = try expectByText(tree.root, .image, "Attached image");
    try testing.expectEqual(canvas.WidgetKind.image, preview.kind);
    try testing.expectEqual(@as(canvas.ImageId, 0), preview.image_id);
    _ = try expectByText(tree.root, .button, "preview.png");

    try fx.feedImageResult(load.id, .loaded, 8, 8, 0, "");
    drainEffects(&model, &fx);
    try testing.expectEqual(load.id, model.attach_preview);

    tree = try buildTree(arena, &model);
    const loaded_preview = try expectByText(tree.root, .image, "Attached image");
    try testing.expectEqual(load.id, loaded_preview.image_id);

    main.update(&model, .{ .image_path_edit = .clear }, &fx);
    main.update(&model, .{ .image_path_edit = .{ .insert_text = ".zig-cache/tmp/faku-no-such-preview.png" } }, &fx);
    try testing.expect(model.has_image_attach());
    try testing.expect(!model.has_image_preview());
    try testing.expectEqual(@as(canvas.ImageId, 0), model.attach_preview);
    tree = try buildTree(arena, &model);
    try testing.expect(findByText(tree.root, .image, "Attached image") == null);
    _ = try expectByText(tree.root, .button, "faku-no-such-preview.png");
    _ = try expectButton(tree.root, "Clear image");

    main.update(&model, .clear_image_attach, &fx);
    try testing.expect(!model.has_image_attach());
    try testing.expect(!model.has_image_preview());
    try testing.expectEqual(@as(canvas.ImageId, 0), model.attach_preview);
    try testing.expectEqual(@as(usize, 0), model.draftImagePath().len);
    tree = try buildTree(arena, &model);
    try testing.expect(findByText(tree.root, .image, "Attached image") == null);
    try testing.expect(findByText(tree.root, .button, "Clear image") == null);
    _ = try expectButton(tree.root, "Attach image");
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

test "daemon address send puts hello attachSession start and prompt on spawn stdin" {
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
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"type\":\"start\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"provider\":\"fx\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"binary\":\"fx\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"cwd\":\".\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"mode\":\"fullAccess\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"interactionMode\":\"build\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"computerUseEnabled\":false") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"type\":\"prompt\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "trace the listener") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"type\":\"loadTaskState\"") == null);
    const attach_at = std.mem.indexOf(u8, request.stdin, "\"type\":\"attachSession\"").?;
    const start_at = std.mem.indexOf(u8, request.stdin, "\"type\":\"start\"").?;
    const prompt_at = std.mem.indexOf(u8, request.stdin, "\"type\":\"prompt\"").?;
    try testing.expect(attach_at < start_at);
    try testing.expect(start_at < prompt_at);
    try testing.expectEqualStrings("127.0.0.1:8787", model.lastDaemonAddress());
    try testing.expectEqual(@as(usize, 0), model.sessionById(id).?.runtimeId().len);
}

test "first daemon send maps stored start options when runtime id is empty" {
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.fx_probe_started = true;
    model.setDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    const id = model.addSession("start mapped", .fx);
    if (model.sessionById(id)) |session| {
        session.setProjectPath("/tmp/faku-start");
        session.setAccessMode("ask");
        session.setInteractionMode("plan");
        session.setModel("openai/gpt-5.4");
    }
    model.selected = id;

    main.update(&model, .{ .draft_edit = .{ .insert_text = "boot the provider" } }, &fx);
    main.update(&model, .send, &fx);
    try testing.expectEqual(main.ReplyPath.daemon, model.reply_path);
    const request = fx.pendingSpawnAt(0).?;
    try testing.expect(argvHas(request.argv, daemon_proxy.SUBCOMMAND));
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"type\":\"hello\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"type\":\"attachSession\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"type\":\"start\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"cwd\":\"/tmp/faku-start\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"mode\":\"ask\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"interactionMode\":\"plan\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"model\":\"openai/gpt-5.4\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"type\":\"prompt\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "boot the provider") != null);
    const attach_at = std.mem.indexOf(u8, request.stdin, "\"type\":\"attachSession\"").?;
    const start_at = std.mem.indexOf(u8, request.stdin, "\"type\":\"start\"").?;
    const prompt_at = std.mem.indexOf(u8, request.stdin, "\"type\":\"prompt\"").?;
    try testing.expect(attach_at < start_at);
    try testing.expect(start_at < prompt_at);
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
    try testing.expect(!model.sessionById(id).?.supports_steer);

    try fx.feedLine(key, "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000012\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"ack\"}}}");
    drainEffects(&model, &fx);
    try testing.expectEqual(@as(usize, 0), model.sessionById(id).?.runtimeId().len);

    try fx.feedLine(key, "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000012\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"sessionRuntime\",\"runtimeId\":\"00000000-0000-0000-0000-000000000003\",\"supportsSteer\":true}}}");
    drainEffects(&model, &fx);
    try testing.expectEqualStrings("00000000-0000-0000-0000-000000000003", model.sessionById(id).?.runtimeId());
    try testing.expect(model.sessionById(id).?.supports_steer);
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
        try testing.expect(std.mem.indexOf(u8, spawn.stdin, "\"type\":\"start\"") == null);
        try testing.expect(std.mem.indexOf(u8, spawn.stdin, "\"runtimeId\":\"00000000-0000-0000-0000-000000000003\"") != null);
        found_second = true;
    }
    try testing.expect(found_second);
}

fn isSaveOnlyStdin(stdin: []const u8) bool {
    return std.mem.indexOf(u8, stdin, "\"type\":\"saveTaskState\"") != null and
        std.mem.indexOf(u8, stdin, "\"type\":\"prompt\"") == null;
}

fn isCancelOnlyStdin(stdin: []const u8) bool {
    return std.mem.indexOf(u8, stdin, "\"command\":{\"type\":\"cancel\"}") != null and
        std.mem.indexOf(u8, stdin, "\"type\":\"prompt\"") == null and
        std.mem.indexOf(u8, stdin, "\"type\":\"attachSession\"") == null;
}

fn findCancelOnlySpawn(fx: *Effects) ?@TypeOf(fx.pendingSpawnAt(0).?) {
    var i: usize = 0;
    while (fx.pendingSpawnAt(i)) |spawn| : (i += 1) {
        if (isCancelOnlyStdin(spawn.stdin)) return spawn;
    }
    return null;
}

fn isSteerOnlyStdin(stdin: []const u8) bool {
    return std.mem.indexOf(u8, stdin, "\"command\":{\"type\":\"steer\"") != null and
        std.mem.indexOf(u8, stdin, "\"type\":\"prompt\"") == null and
        std.mem.indexOf(u8, stdin, "\"type\":\"attachSession\"") == null;
}

fn findSteerOnlySpawn(fx: *Effects) ?@TypeOf(fx.pendingSpawnAt(0).?) {
    var i: usize = 0;
    while (fx.pendingSpawnAt(i)) |spawn| : (i += 1) {
        if (isSteerOnlyStdin(spawn.stdin)) return spawn;
    }
    return null;
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

test "daemon Stop records hello and cancel on a distinct sidecar" {
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.fx_probe_started = true;
    model.setDaemonAddress("127.0.0.1:8787");
    model.setDaemonToken("secret");
    model.setSidecarPath("faku");
    const id = model.addSession("daemon stop", .fx);
    model.selected = id;
    main.update(&model, .{ .draft_edit = .{ .insert_text = "trace the listener" } }, &fx);
    main.update(&model, .send, &fx);
    try testing.expectEqual(main.ReplyPath.daemon, model.reply_path);
    const prompt_key = model.daemon_spawn_key;
    try testing.expect(prompt_key != 0);

    try fx.feedLine(prompt_key, "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000012\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"sessionRuntime\",\"runtimeId\":\"00000000-0000-0000-0000-000000000003\",\"supportsSteer\":true}}}");
    drainEffects(&model, &fx);
    try fx.feedLine(prompt_key, "{\"type\":\"event\",\"event\":{\"kind\":\"textDelta\",\"payload\":\"partial from sidecar\"}}");
    drainEffects(&model, &fx);
    try testing.expect(std.mem.indexOf(u8, lastAssistant(&model), "partial from sidecar") != null);
    try testing.expect(model.is_streaming());

    main.update(&model, .stop, &fx);
    try testing.expect(!model.is_streaming());
    try testing.expectEqual(@as(usize, 1), countRole(&model, .user));
    try testing.expectEqual(@as(usize, 1), countRole(&model, .assistant));
    try testing.expect(std.mem.indexOf(u8, lastAssistant(&model), "partial from sidecar") != null);

    const spawn = findCancelOnlySpawn(&fx) orelse return error.CancelSpawnMissing;
    try testing.expect(argvHas(spawn.argv, daemon_proxy.SUBCOMMAND));
    try testing.expect(argvHas(spawn.argv, "127.0.0.1:8787"));
    try testing.expect(std.mem.indexOf(u8, spawn.stdin, "\"type\":\"hello\"") != null);
    try testing.expect(std.mem.indexOf(u8, spawn.stdin, "\"token\":\"secret\"") != null);
    try testing.expect(std.mem.indexOf(u8, spawn.stdin, "\"type\":\"cancel\"") != null);
    try testing.expect(std.mem.indexOf(u8, spawn.stdin, "\"command\":{\"type\":\"cancel\"}") != null);
    var id_buf: [36]u8 = undefined;
    try testing.expect(std.mem.indexOf(u8, spawn.stdin, daemon_proxy.wireUuid(id, &id_buf)) != null);
    try testing.expect(std.mem.indexOf(u8, spawn.stdin, "\"runtimeId\":\"00000000-0000-0000-0000-000000000003\"") != null);
    try testing.expect(std.mem.indexOf(u8, spawn.stdin, "\"type\":\"prompt\"") == null);
    try testing.expect(std.mem.indexOf(u8, spawn.stdin, "\"type\":\"attachSession\"") == null);
    try testing.expect(std.mem.indexOf(u8, spawn.stdin, "\"type\":\"steer\"") == null);
    try testing.expect(std.mem.indexOf(u8, spawn.stdin, "\"type\":\"start\"") == null);
    try testing.expect(spawn.key != prompt_key);
    try testing.expect(spawn.key != model.daemon_spawn_key);
}

test "fx ask Stop does not spawn a cancel sidecar" {
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = main.initialModel();
    model.fx_available = true;
    model.fx_probe_started = true;
    model.setFxPath("fx");
    model.setSidecarPath("faku");
    try testing.expectEqual(@as(usize, 0), model.daemonAddress().len);

    main.update(&model, .{ .draft_edit = .{ .insert_text = "keep fx ask" } }, &fx);
    main.update(&model, .send, &fx);
    try testing.expectEqual(main.ReplyPath.fx, model.reply_path);
    try testing.expect(model.is_streaming());
    main.update(&model, .stop, &fx);
    try testing.expect(!model.is_streaming());
    try testing.expect(findCancelOnlySpawn(&fx) == null);
    var i: usize = 0;
    while (fx.pendingSpawnAt(i)) |spawn| : (i += 1) {
        try testing.expect(!argvHas(spawn.argv, daemon_proxy.SUBCOMMAND));
        try testing.expect(std.mem.indexOf(u8, spawn.stdin, "\"type\":\"cancel\"") == null);
    }
}

test "missing daemon address does not spawn cancel even with last_daemon_address" {
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = main.initialModel();
    model.fx_available = true;
    model.fx_probe_started = true;
    model.setFxPath("fx");
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    try testing.expectEqual(@as(usize, 0), model.daemonAddress().len);

    main.update(&model, .{ .draft_edit = .{ .insert_text = "no cancel" } }, &fx);
    main.update(&model, .send, &fx);
    try testing.expectEqual(main.ReplyPath.fx, model.reply_path);
    main.update(&model, .stop, &fx);
    try testing.expect(!model.is_streaming());
    try testing.expect(findCancelOnlySpawn(&fx) == null);
}

test "cancel sidecar failure leaves the turn settled and the transcript intact" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-cancel-fail", .{tmp.sub_path[0..]});

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
    const id = model.addSession("cancel fail", .fx);
    model.selected = id;
    main.update(&model, .{ .draft_edit = .{ .insert_text = "first prompt" } }, &fx);
    main.update(&model, .send, &fx);
    const prompt_key = model.daemon_spawn_key;
    try fx.feedLine(prompt_key, "{\"type\":\"event\",\"event\":{\"kind\":\"textDelta\",\"payload\":\"keep this partial\"}}");
    drainEffects(&model, &fx);
    main.update(&model, .{ .draft_edit = .{ .insert_text = "stay queued" } }, &fx);
    main.update(&model, .send, &fx);
    try testing.expectEqual(@as(u32, 1), model.queuedCount(id));

    main.update(&model, .stop, &fx);
    try testing.expect(!model.is_streaming());
    const spawn = findCancelOnlySpawn(&fx) orelse return error.CancelSpawnMissing;
    try testing.expect(spawn.key != prompt_key);
    try fx.feedExit(spawn.key, 1);
    drainEffects(&model, &fx);

    try testing.expect(!model.is_streaming());
    try testing.expectEqual(main.ReplyPath.daemon, model.reply_path);
    try testing.expectEqual(@as(u32, 1), model.queuedCount(id));
    try testing.expectEqualStrings("stay queued", model.firstQueuedText(id));
    try testing.expectEqual(@as(usize, 1), countRole(&model, .user));
    try testing.expectEqual(@as(usize, 1), countRole(&model, .assistant));
    try testing.expect(std.mem.indexOf(u8, lastAssistant(&model), "keep this partial") != null);

    var loaded = Model{};
    loaded.setStoreDir(dir);
    try testing.expectEqual(store.LoadKind.loaded, store.loadCatalog(&loaded, testing.allocator, testing.io));
    store.hydrateSession(&loaded, id, testing.allocator, testing.io);
    try testing.expectEqual(@as(usize, 2), loaded.turn_count);
    try testing.expectEqualStrings("first prompt", loaded.turn_store[0].text());
    try testing.expect(std.mem.indexOf(u8, loaded.turn_store[1].text(), "keep this partial") != null);
    try testing.expectEqual(@as(u32, 1), loaded.queuedCount(id));
}

test "daemon live turn plus steer records hello and steer on a distinct sidecar" {
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.fx_probe_started = true;
    model.setDaemonAddress("127.0.0.1:8787");
    model.setDaemonToken("secret");
    model.setSidecarPath("faku");
    const id = model.addSession("daemon steer", .fx);
    model.selected = id;
    main.update(&model, .{ .draft_edit = .{ .insert_text = "trace the listener" } }, &fx);
    main.update(&model, .send, &fx);
    try testing.expectEqual(main.ReplyPath.daemon, model.reply_path);
    const prompt_key = model.daemon_spawn_key;
    try testing.expect(prompt_key != 0);

    try fx.feedLine(prompt_key, "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000012\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"sessionRuntime\",\"runtimeId\":\"00000000-0000-0000-0000-000000000003\",\"supportsSteer\":true}}}");
    drainEffects(&model, &fx);
    try fx.feedLine(prompt_key, "{\"type\":\"event\",\"event\":{\"kind\":\"textDelta\",\"payload\":\"partial from sidecar\"}}");
    drainEffects(&model, &fx);
    try testing.expect(model.is_streaming());
    try testing.expect(model.sessionById(id).?.supports_steer);

    main.update(&model, .{ .draft_edit = .{ .insert_text = "keep going on the listener" } }, &fx);
    main.update(&model, .steer, &fx);
    try testing.expect(model.is_streaming());
    try testing.expectEqual(@as(u32, 0), model.queuedCount(id));
    try testing.expectEqualStrings("", model.draft());
    try testing.expectEqual(@as(usize, 1), countRole(&model, .user));

    const spawn = findSteerOnlySpawn(&fx) orelse return error.SteerSpawnMissing;
    try testing.expect(argvHas(spawn.argv, daemon_proxy.SUBCOMMAND));
    try testing.expect(argvHas(spawn.argv, "127.0.0.1:8787"));
    try testing.expect(std.mem.indexOf(u8, spawn.stdin, "\"type\":\"hello\"") != null);
    try testing.expect(std.mem.indexOf(u8, spawn.stdin, "\"token\":\"secret\"") != null);
    try testing.expect(std.mem.indexOf(u8, spawn.stdin, "\"command\":{\"type\":\"steer\",\"prompt\":\"keep going on the listener\"}") != null);
    var id_buf: [36]u8 = undefined;
    try testing.expect(std.mem.indexOf(u8, spawn.stdin, daemon_proxy.wireUuid(id, &id_buf)) != null);
    try testing.expect(std.mem.indexOf(u8, spawn.stdin, "\"runtimeId\":\"00000000-0000-0000-0000-000000000003\"") != null);
    try testing.expect(std.mem.indexOf(u8, spawn.stdin, "\"type\":\"prompt\"") == null);
    try testing.expect(std.mem.indexOf(u8, spawn.stdin, "\"type\":\"attachSession\"") == null);
    try testing.expect(std.mem.indexOf(u8, spawn.stdin, "\"type\":\"cancel\"") == null);
    try testing.expect(spawn.key != prompt_key);
    try testing.expect(spawn.key != model.daemon_spawn_key);
}

test "Send while a daemon turn is live still queues and does not steer" {
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.fx_probe_started = true;
    model.setDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    const id = model.addSession("daemon queue send", .fx);
    model.selected = id;
    main.update(&model, .{ .draft_edit = .{ .insert_text = "first prompt" } }, &fx);
    main.update(&model, .send, &fx);
    const prompt_key = model.daemon_spawn_key;
    try fx.feedLine(prompt_key, "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000012\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"sessionRuntime\",\"runtimeId\":\"00000000-0000-0000-0000-000000000003\",\"supportsSteer\":true}}}");
    drainEffects(&model, &fx);

    main.update(&model, .{ .draft_edit = .{ .insert_text = "follow up later" } }, &fx);
    main.update(&model, .send, &fx);
    try testing.expectEqual(@as(u32, 1), model.queuedCount(id));
    try testing.expectEqualStrings("follow up later", model.firstQueuedText(id));
    try testing.expectEqualStrings("", model.draft());
    try testing.expect(findSteerOnlySpawn(&fx) == null);
    try testing.expect(model.is_streaming());
}

test "fx ask busy send still queues and does not steer" {
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = main.initialModel();
    model.fx_available = true;
    model.fx_probe_started = true;
    model.setFxPath("fx");
    model.setSidecarPath("faku");
    try testing.expectEqual(@as(usize, 0), model.daemonAddress().len);

    main.update(&model, .{ .draft_edit = .{ .insert_text = "keep fx ask" } }, &fx);
    main.update(&model, .send, &fx);
    try testing.expectEqual(main.ReplyPath.fx, model.reply_path);
    try testing.expect(model.is_streaming());

    main.update(&model, .{ .draft_edit = .{ .insert_text = "queued follow-up" } }, &fx);
    main.update(&model, .send, &fx);
    try testing.expectEqual(@as(u32, 1), model.queuedCount(model.selected));
    try testing.expect(findSteerOnlySpawn(&fx) == null);

    main.update(&model, .{ .draft_edit = .{ .insert_text = "would be a steer" } }, &fx);
    main.update(&model, .steer, &fx);
    try testing.expectEqual(@as(u32, 2), model.queuedCount(model.selected));
    try testing.expect(findSteerOnlySpawn(&fx) == null);
    var i: usize = 0;
    while (fx.pendingSpawnAt(i)) |spawn| : (i += 1) {
        try testing.expect(std.mem.indexOf(u8, spawn.stdin, "\"type\":\"steer\"") == null);
    }
}

test "missing daemon address does not steer even with last_daemon_address" {
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = main.initialModel();
    model.fx_available = true;
    model.fx_probe_started = true;
    model.setFxPath("fx");
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    try testing.expectEqual(@as(usize, 0), model.daemonAddress().len);

    main.update(&model, .{ .draft_edit = .{ .insert_text = "no steer" } }, &fx);
    main.update(&model, .send, &fx);
    try testing.expectEqual(main.ReplyPath.fx, model.reply_path);
    main.update(&model, .{ .draft_edit = .{ .insert_text = "would be a steer" } }, &fx);
    main.update(&model, .steer, &fx);
    try testing.expectEqual(@as(u32, 1), model.queuedCount(model.selected));
    try testing.expect(findSteerOnlySpawn(&fx) == null);
}

test "attach supportsSteer false or unknown queues instead of steering" {
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.fx_probe_started = true;
    model.setDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    const id = model.addSession("no steer flag", .fx);
    model.selected = id;
    main.update(&model, .{ .draft_edit = .{ .insert_text = "first prompt" } }, &fx);
    main.update(&model, .send, &fx);
    try testing.expect(model.is_streaming());
    try testing.expect(!model.sessionById(id).?.supports_steer);

    main.update(&model, .{ .draft_edit = .{ .insert_text = "unknown queues" } }, &fx);
    main.update(&model, .steer, &fx);
    try testing.expectEqual(@as(u32, 1), model.queuedCount(id));
    try testing.expect(findSteerOnlySpawn(&fx) == null);

    try fx.feedLine(model.daemon_spawn_key, "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000012\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"sessionRuntime\",\"runtimeId\":\"00000000-0000-0000-0000-000000000003\",\"supportsSteer\":false}}}");
    drainEffects(&model, &fx);
    try testing.expect(!model.sessionById(id).?.supports_steer);

    main.update(&model, .{ .draft_edit = .{ .insert_text = "false queues" } }, &fx);
    main.update(&model, .steer, &fx);
    try testing.expectEqual(@as(u32, 2), model.queuedCount(id));
    try testing.expect(findSteerOnlySpawn(&fx) == null);
}

test "steer sidecar failure leaves the draft queued path untouched and the turn live" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-steer-fail", .{tmp.sub_path[0..]});

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
    const id = model.addSession("steer fail", .fx);
    model.selected = id;
    main.update(&model, .{ .draft_edit = .{ .insert_text = "first prompt" } }, &fx);
    main.update(&model, .send, &fx);
    const prompt_key = model.daemon_spawn_key;
    try fx.feedLine(prompt_key, "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000012\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"sessionRuntime\",\"runtimeId\":\"00000000-0000-0000-0000-000000000003\",\"supportsSteer\":true}}}");
    drainEffects(&model, &fx);
    try fx.feedLine(prompt_key, "{\"type\":\"event\",\"event\":{\"kind\":\"textDelta\",\"payload\":\"keep this partial\"}}");
    drainEffects(&model, &fx);

    main.update(&model, .{ .draft_edit = .{ .insert_text = "stay queued" } }, &fx);
    main.update(&model, .send, &fx);
    try testing.expectEqual(@as(u32, 1), model.queuedCount(id));

    main.update(&model, .{ .draft_edit = .{ .insert_text = "inject this" } }, &fx);
    main.update(&model, .steer, &fx);
    const spawn = findSteerOnlySpawn(&fx) orelse return error.SteerSpawnMissing;
    try testing.expectEqualStrings("", model.draft());
    try testing.expectEqual(@as(u32, 1), model.queuedCount(id));
    try fx.feedExit(spawn.key, 1);
    drainEffects(&model, &fx);

    try testing.expect(model.is_streaming());
    try testing.expectEqual(main.ReplyPath.daemon, model.reply_path);
    try testing.expectEqual(@as(u32, 1), model.queuedCount(id));
    try testing.expectEqualStrings("stay queued", model.firstQueuedText(id));
    try testing.expect(std.mem.indexOf(u8, lastAssistant(&model), "keep this partial") != null);
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
    try testing.expect(argvHas(request.argv, acp_proxy.SUBCOMMAND));
    try testing.expect(!argvHas(request.argv, "ask"));
    try testing.expect(!argvHas(request.argv, daemon_proxy.SUBCOMMAND));
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"type\":\"attachSession\"") == null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"type\":\"start\"") == null);
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
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"type\":\"start\"") == null);
    try testing.expectEqual(@as(usize, 0), model.session_store[0].runtimeId().len);
}

test "dropLastPromptTurns keeps earlier prompts and other sessions" {
    var model = Model{};
    const other = model.addSession("other", .fx);
    const id = model.addSession("me", .fx);
    model.selected = id;
    _ = model.appendTurn(other, .user, "other user");
    _ = model.appendTurn(id, .user, "keep");
    _ = model.appendTurn(id, .assistant, "keep reply");
    _ = model.appendTurn(id, .user, "drop");
    _ = model.appendTurn(id, .assistant, "drop reply");
    _ = model.appendTurn(id, .tool, "drop tool");
    _ = model.appendTurn(id, .reasoning, "drop thought");
    _ = model.appendTurn(other, .assistant, "other asst");
    model.dropLastPromptTurns(id);
    try testing.expectEqual(@as(u32, 2), model.turnCount(id));
    try testing.expectEqual(@as(u32, 2), model.turnCount(other));
    try testing.expectEqualStrings("keep", lastUser(&model));
    model.dropLastPromptTurns(id);
    try testing.expectEqual(@as(u32, 0), model.turnCount(id));
    try testing.expectEqual(@as(u32, 2), model.turnCount(other));
    model.dropLastPromptTurns(id);
    try testing.expectEqual(@as(u32, 0), model.turnCount(id));
}

test "Send records the pre-commit HEAD; a later commit stays off the rewind target" {
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
    const at_send = model.sessionById(id).?;
    try testing.expectEqual(@as(usize, 1), at_send.rewind_ref_count);
    try testing.expectEqualStrings(expected, at_send.rewindRefs()[0].sha());
    try testing.expectEqualStrings(rewind.recorded_ref, at_send.rewindRefs()[0].refName());
    try testing.expect(at_send.rewindRefs()[0].recorded_at > 0);

    try dirtyAndAdvanceRepo(allocator, testing.io, project, "agent commit\n");
    var after_buf: [rewind.max_sha]u8 = undefined;
    const after = rewind.revParseHead(allocator, testing.io, project, &after_buf) orelse return error.GitHead;
    try testing.expect(!std.mem.eql(u8, expected, after));

    try fx.feedExit(main.fx_ask_key, 0);
    drainEffects(&model, &fx);
    try testing.expect(!model.is_streaming());

    const live = model.sessionById(id).?;
    try testing.expectEqual(@as(usize, 1), live.rewind_ref_count);
    try testing.expectEqualStrings(expected, live.rewindRefs()[0].sha());
    try testing.expectEqualStrings(rewind.recorded_ref, live.rewindRefs()[0].refName());

    var loaded = Model{};
    loaded.setStoreDir(dir);
    try testing.expectEqual(store.LoadKind.loaded, store.loadCatalog(&loaded, allocator, testing.io));
    try testing.expectEqualStrings(expected, loaded.session_store[0].rewindRefs()[0].sha());
    store.hydrateSession(&loaded, id, allocator, testing.io);
    try testing.expectEqualStrings(expected, loaded.session_store[0].rewindRefs()[0].sha());
}

test "non-git project_path records no rewind ref" {
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
    try testing.expectEqual(@as(usize, 0), model.sessionById(id).?.rewind_ref_count);
    try fx.feedExit(main.fx_ask_key, 0);
    drainEffects(&model, &fx);
    try testing.expect(!model.is_streaming());
    try testing.expectEqual(@as(usize, 0), model.sessionById(id).?.rewind_ref_count);
}

test "failed or cancelled turns keep the send-time rewind ref" {
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
    try testing.expectEqual(@as(usize, 1), model.sessionById(id).?.rewind_ref_count);
    try testing.expectEqualStrings(expected, model.sessionById(id).?.rewindRefs()[0].sha());
    try fx.feedExit(main.fx_ask_key, 1);
    drainEffects(&model, &fx);
    try testing.expect(!model.is_streaming());
    try testing.expectEqual(@as(usize, 1), model.sessionById(id).?.rewind_ref_count);

    main.update(&model, .{ .draft_edit = .{ .insert_text = "this will stop" } }, &fx);
    main.update(&model, .send, &fx);
    try testing.expect(model.is_streaming());
    try testing.expectEqual(@as(usize, 2), model.sessionById(id).?.rewind_ref_count);
    main.update(&model, .stop, &fx);
    try testing.expect(!model.is_streaming());
    try testing.expectEqual(@as(usize, 2), model.sessionById(id).?.rewind_ref_count);
}

test "Rewind restores Send-time files, pops that ref, and truncates the last prompt" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const allocator = testing.allocator;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/rewind-apply", .{tmp.sub_path[0..]});
    const first_sha = try initTestGitRepo(allocator, testing.io, project);
    defer allocator.free(first_sha);
    var dir_buf: [256]u8 = undefined;
    const dir = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-rewind-apply", .{tmp.sub_path[0..]});

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
    const id = model.addSession("rewind apply", .fx);
    if (model.sessionById(id)) |session| {
        session.setProjectPath(project);
        session.setFxSessionId("fx-sess-rewind");
    }
    model.selected = id;

    main.update(&model, .{ .draft_edit = .{ .insert_text = "first prompt" } }, &fx);
    main.update(&model, .send, &fx);
    try fx.feedExit(main.fx_ask_key, 0);
    drainEffects(&model, &fx);
    try testing.expect(!model.is_streaming());
    try testing.expectEqualStrings(first_sha, model.sessionById(id).?.rewindRefs()[0].sha());

    try dirtyAndAdvanceRepo(allocator, testing.io, project, "after first\n");
    var second_buf: [rewind.max_sha]u8 = undefined;
    const second_sha = rewind.revParseHead(allocator, testing.io, project, &second_buf) orelse return error.GitHead;
    try testing.expect(!std.mem.eql(u8, first_sha, second_sha));

    main.update(&model, .{ .draft_edit = .{ .insert_text = "second prompt" } }, &fx);
    main.update(&model, .send, &fx);
    try testing.expectEqual(@as(usize, 2), model.sessionById(id).?.rewind_ref_count);
    try testing.expectEqualStrings(second_sha, model.sessionById(id).?.rewindRefs()[1].sha());
    try fx.feedExit(main.fx_ask_key, 0);
    drainEffects(&model, &fx);
    try testing.expect(!model.is_streaming());
    try testing.expectEqual(@as(u32, 4), model.turnCount(id));
    _ = model.appendTurn(id, .tool, "write README");
    _ = model.appendTurn(id, .reasoning, "thinking");
    try testing.expectEqual(@as(u32, 6), model.turnCount(id));
    try testing.expectEqualStrings("fx-sess-rewind", model.sessionById(id).?.fxSessionId());

    try dirtyAndAdvanceRepo(allocator, testing.io, project, "after second\n");
    var third_buf: [rewind.max_sha]u8 = undefined;
    const third_sha = rewind.revParseHead(allocator, testing.io, project, &third_buf) orelse return error.GitHead;
    try testing.expect(!std.mem.eql(u8, second_sha, third_sha));

    var tree = try buildTree(arena, &model);
    const rewind_btn = try expectByText(tree.root, .button, "Rewind");
    try testing.expect(model.can_rewind());

    main.update(&model, tree.msgForPointer(rewind_btn.id, .up).?, &fx);
    try expectHead(allocator, testing.io, project, second_sha);
    const after_first_rewind = try readRepoReadme(allocator, testing.io, project);
    defer allocator.free(after_first_rewind);
    try testing.expectEqualStrings("after first\n", after_first_rewind);

    const after_one = model.sessionById(id).?;
    try testing.expectEqualStrings("fx-sess-rewind", after_one.fxSessionId());
    try testing.expectEqual(@as(usize, 1), after_one.rewind_ref_count);
    try testing.expectEqualStrings(first_sha, after_one.rewindRefs()[0].sha());
    try testing.expectEqual(@as(u32, 2), model.turnCount(id));
    try testing.expectEqual(@as(usize, 1), countRole(&model, .user));
    try testing.expectEqualStrings("first prompt", lastUser(&model));
    try testing.expectEqualStrings("", lastTool(&model));

    main.update(&model, .rewind, &fx);
    try expectHead(allocator, testing.io, project, first_sha);
    const after_second_rewind = try readRepoReadme(allocator, testing.io, project);
    defer allocator.free(after_second_rewind);
    try testing.expectEqualStrings("rewind\n", after_second_rewind);

    const after_two = model.sessionById(id).?;
    try testing.expectEqualStrings("fx-sess-rewind", after_two.fxSessionId());
    try testing.expectEqual(@as(usize, 0), after_two.rewind_ref_count);
    try testing.expectEqual(@as(u32, 0), model.turnCount(id));
    try testing.expect(!model.can_rewind());

    var loaded = Model{};
    loaded.setStoreDir(dir);
    loaded.store_io = testing.io;
    try testing.expectEqual(store.LoadKind.loaded, store.loadCatalog(&loaded, allocator, testing.io));
    try testing.expectEqual(@as(usize, 0), loaded.session_store[0].rewind_ref_count);
    store.hydrateSession(&loaded, id, allocator, testing.io);
    try testing.expectEqual(@as(u32, 0), loaded.turnCount(id));
    try testing.expectEqualStrings("fx-sess-rewind", loaded.session_store[0].fxSessionId());
}

test "Rewind is a no-op when git, path, or stored sha is missing" {
    const allocator = testing.allocator;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-rewind-noop", .{tmp.sub_path[0..]});
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/rewind-noop", .{tmp.sub_path[0..]});
    const expected = try initTestGitRepo(allocator, testing.io, project);
    defer allocator.free(expected);

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.task_state_loaded = true;
    model.setStoreDir(dir);
    model.store_io = testing.io;
    const id = model.addSession("rewind noop", .fx);
    if (model.sessionById(id)) |session| {
        session.setProjectPath(project);
        session.setFxSessionId("fx-sess-noop");
    }
    model.selected = id;
    _ = model.appendTurn(id, .user, "stay put");
    try store.saveSession(&model, id, allocator, testing.io);
    const before = try readCatalog(allocator, testing.io, dir);
    defer allocator.free(before);

    main.update(&model, .rewind, &fx);
    try testing.expectEqual(@as(usize, 0), model.sessionById(id).?.rewind_ref_count);
    try expectHead(allocator, testing.io, project, expected);
    try expectCatalogUnchanged(allocator, testing.io, dir, before);

    if (model.sessionById(id)) |session| session.appendRewindRef("not-a-sha", rewind.recorded_ref, 1);
    main.update(&model, .rewind, &fx);
    try expectHead(allocator, testing.io, project, expected);
    try testing.expectEqual(@as(usize, 1), model.sessionById(id).?.rewind_ref_count);
    try expectCatalogUnchanged(allocator, testing.io, dir, before);

    if (model.sessionById(id)) |session| {
        session.clearRewindRefs();
        session.appendRewindRef("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", rewind.recorded_ref, 2);
    }
    main.update(&model, .rewind, &fx);
    try expectHead(allocator, testing.io, project, expected);
    try testing.expectEqualStrings("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", model.sessionById(id).?.rewindRefs()[0].sha());
    try expectCatalogUnchanged(allocator, testing.io, dir, before);

    var plain_buf: [256]u8 = undefined;
    const plain = try std.fmt.bufPrint(&plain_buf, ".zig-cache/tmp/{s}/plain", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(testing.io, plain);
    if (model.sessionById(id)) |session| session.setProjectPath(plain);
    main.update(&model, .rewind, &fx);
    try expectHead(allocator, testing.io, project, expected);
    try expectCatalogUnchanged(allocator, testing.io, dir, before);

    if (model.sessionById(id)) |session| session.setProjectPath(".zig-cache/tmp/faku-rewind-missing-path");
    main.update(&model, .rewind, &fx);
    try expectHead(allocator, testing.io, project, expected);
    try expectCatalogUnchanged(allocator, testing.io, dir, before);
    try testing.expectEqualStrings("fx-sess-noop", model.sessionById(id).?.fxSessionId());
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

fn dirtyAndAdvanceRepo(allocator: std.mem.Allocator, io: std.Io, path: []const u8, contents: []const u8) !void {
    var readme_buf: [std.fs.max_path_bytes]u8 = undefined;
    const readme = try std.fmt.bufPrint(&readme_buf, "{s}{s}README", .{ path, std.fs.path.sep_str });
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = readme, .data = "dirty\n" });
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = readme, .data = contents });
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
        "advance",
    });
}

fn readRepoReadme(allocator: std.mem.Allocator, io: std.Io, path: []const u8) ![]u8 {
    var readme_buf: [std.fs.max_path_bytes]u8 = undefined;
    const readme = try std.fmt.bufPrint(&readme_buf, "{s}{s}README", .{ path, std.fs.path.sep_str });
    return std.Io.Dir.cwd().readFileAlloc(io, readme, allocator, .limited(64));
}

fn expectHead(allocator: std.mem.Allocator, io: std.Io, path: []const u8, expected: []const u8) !void {
    var sha_buf: [rewind.max_sha]u8 = undefined;
    const sha = rewind.revParseHead(allocator, io, path, &sha_buf) orelse return error.GitHead;
    try testing.expectEqualStrings(expected, sha);
}

fn readCatalog(allocator: std.mem.Allocator, io: std.Io, dir: []const u8) ![]u8 {
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    return std.Io.Dir.cwd().readFileAlloc(io, store.catalogPath(dir, &path_buf).?, allocator, .limited(store.max_document_bytes));
}

fn expectCatalogUnchanged(allocator: std.mem.Allocator, io: std.Io, dir: []const u8, before: []const u8) !void {
    const after = try readCatalog(allocator, io, dir);
    defer allocator.free(after);
    try testing.expectEqualStrings(before, after);
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
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = main.initialModel();
    try testing.expectEqual(@as(u32, 2), model.session_count);

    // Composer typing: plain n is draft text, not New Task.
    main.update(&model, .{ .draft_edit = .{ .insert_text = "n" } }, &fx);
    try testing.expectEqualStrings("n", model.draft());
    try testing.expectEqual(@as(u32, 2), model.session_count);

    const plain_n = canvas.WidgetKeyboardEvent{ .phase = .key_down, .key = "n" };
    try testing.expectEqual(@as(?Msg, null), main.onKey(plain_n));
    try testing.expectEqual(@as(u32, 2), model.session_count);
    try testing.expectEqualStrings("n", model.draft());

    var tree = try buildTree(arena, &model);
    const new_btn = try expectButton(tree.root, "New Task");
    try testing.expectEqual(Msg.new_session, tree.msgForPointer(new_btn.id, .up).?);

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

    tree = try buildTree(arena, &model);
    _ = try expectByText(tree.root, .text, "New task");
    _ = try expectByText(tree.root, .text, "What should we build?");
    _ = try expectButton(tree.root, "New task");

    const ctrl_n = canvas.WidgetKeyboardEvent{
        .phase = .key_down,
        .key = "N",
        .modifiers = .{ .control = true },
    };
    try testing.expectEqual(Msg.new_session, main.onKey(ctrl_n).?);
    main.update(&model, main.onKey(ctrl_n).?, &fx);
    try testing.expectEqual(@as(u32, 4), model.session_count);
    try testing.expectEqualStrings("fx", model.selected_provider());

    const escape = canvas.WidgetKeyboardEvent{ .phase = .key_down, .key = "escape" };
    try testing.expectEqual(Msg.stop, main.onKey(escape).?);

    const plain_enter = canvas.WidgetKeyboardEvent{ .phase = .key_down, .key = "enter" };
    try testing.expectEqual(@as(?Msg, null), main.onKey(plain_enter));

    const cmd_enter = canvas.WidgetKeyboardEvent{
        .phase = .key_down,
        .key = "enter",
        .modifiers = .{ .super = true },
    };
    try testing.expectEqual(Msg.steer, main.onKey(cmd_enter).?);

    const ctrl_enter = canvas.WidgetKeyboardEvent{
        .phase = .key_down,
        .key = "Enter",
        .modifiers = .{ .control = true },
    };
    try testing.expectEqual(Msg.steer, main.onKey(ctrl_enter).?);
}

test "new task and cmd-n focus the composer via the same autofocus edge" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = main.initialModel();
    try testing.expectEqual(@as(u32, 2), model.session_count);
    try testing.expect(!model.composer_active);
    try testing.expect(!model.search_active);

    var tree = try buildTree(arena, &model);
    const new_btn = try expectButton(tree.root, "New Task");
    try testing.expectEqual(Msg.new_session, tree.msgForPointer(new_btn.id, .up).?);
    if (findByKind(tree.root, .textarea)) |composer| {
        try testing.expectEqualStrings("Do anything...", composer.placeholder);
        try testing.expect(!composer.autofocus);
    } else return error.WidgetNotFound;
    _ = try expectByText(tree.root, .button, "Copy session");

    main.update(&model, tree.msgForPointer(new_btn.id, .up).?, &fx);
    try testing.expectEqual(@as(u32, 3), model.session_count);
    try testing.expect(model.sessionById(model.selected).?.untitled);
    try testing.expectEqualStrings("untitled", model.selected_title());
    try testing.expect(model.composer_active);

    tree = try buildTree(arena, &model);
    if (findByKind(tree.root, .textarea)) |composer| {
        try testing.expect(composer.autofocus);
    } else return error.WidgetNotFound;
    _ = try expectByText(tree.root, .button, "Copy session");

    main.update(&model, .start_search, &fx);
    try testing.expect(model.search_active);
    try testing.expect(!model.composer_active);

    tree = try buildTree(arena, &model);
    if (findByKind(tree.root, .search_field)) |field| {
        try testing.expectEqualStrings("Search", field.placeholder);
        try testing.expect(field.autofocus);
    } else return error.WidgetNotFound;
    if (findByKind(tree.root, .textarea)) |composer| {
        try testing.expect(!composer.autofocus);
    } else return error.WidgetNotFound;

    const cmd_n = canvas.WidgetKeyboardEvent{
        .phase = .key_down,
        .key = "n",
        .modifiers = .{ .super = true },
    };
    try testing.expectEqual(Msg.new_session, main.onKey(cmd_n).?);
    main.update(&model, main.onKey(cmd_n).?, &fx);
    try testing.expectEqual(@as(u32, 4), model.session_count);
    try testing.expect(model.sessionById(model.selected).?.untitled);
    try testing.expect(model.composer_active);
    try testing.expect(model.search_active);

    tree = try buildTree(arena, &model);
    if (findByKind(tree.root, .textarea)) |composer| {
        try testing.expect(composer.autofocus);
    } else return error.WidgetNotFound;
    _ = try expectByText(tree.root, .button, "Copy session");

    const cmd_l = canvas.WidgetKeyboardEvent{
        .phase = .key_down,
        .key = "l",
        .modifiers = .{ .super = true },
    };
    try testing.expectEqual(Msg.focus_composer, main.onKey(cmd_l).?);
}

test "selecting a session focuses the composer; rename and search do not" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = main.initialModel();
    const port_id = model.session_store[0].id;
    const auth_id = model.session_store[1].id;
    try testing.expectEqual(port_id, model.selected);
    try testing.expect(!model.composer_active);
    try testing.expect(!model.search_active);
    try testing.expectEqual(@as(u32, 0), model.editing_session_id);
    try testing.expectEqual(@as(u32, 0), model.editing_folder_id);

    var tree = try buildTree(arena, &model);
    const auth_row = try expectButton(tree.root, "fix auth listener");
    try testing.expectEqual(Msg{ .select = auth_id }, tree.msgForPointer(auth_row.id, .up).?);
    if (findByKind(tree.root, .textarea)) |composer| {
        try testing.expectEqualStrings("Do anything...", composer.placeholder);
        try testing.expect(!composer.autofocus);
    } else return error.WidgetNotFound;
    _ = try expectByText(tree.root, .button, "Copy session");

    main.update(&model, tree.msgForPointer(auth_row.id, .up).?, &fx);
    try testing.expectEqual(auth_id, model.selected);
    try testing.expectEqualStrings("fix auth listener", model.selected_title());
    try testing.expect(model.composer_active);
    try testing.expectEqual(@as(u32, 0), model.editing_session_id);

    tree = try buildTree(arena, &model);
    if (findByKind(tree.root, .textarea)) |composer| {
        try testing.expect(composer.autofocus);
    } else return error.WidgetNotFound;
    _ = try expectByText(tree.root, .button, "Copy session");

    // Second click on the selected row starts rename and must not steal
    // into the composer.
    const auth_again = try expectButton(tree.root, "fix auth listener");
    try testing.expectEqual(Msg{ .select = auth_id }, tree.msgForPointer(auth_again.id, .up).?);
    main.update(&model, tree.msgForPointer(auth_again.id, .up).?, &fx);
    try testing.expectEqual(auth_id, model.selected);
    try testing.expectEqual(auth_id, model.editing_session_id);
    try testing.expect(!model.composer_active);

    tree = try buildTree(arena, &model);
    if (findByPlaceholder(tree.root, .text_field, "untitled")) |field| {
        try testing.expect(field.autofocus);
    } else return error.WidgetNotFound;
    if (findByKind(tree.root, .textarea)) |composer| {
        try testing.expect(!composer.autofocus);
    } else return error.WidgetNotFound;

    main.update(&model, .stop, &fx);
    try testing.expectEqual(@as(u32, 0), model.editing_session_id);
    try testing.expectEqual(auth_id, model.selected);

    main.update(&model, .start_search, &fx);
    try testing.expect(model.search_active);
    try testing.expect(!model.composer_active);
    main.update(&model, .{ .search_edit = .{ .insert_text = "auth" } }, &fx);
    try testing.expect(model.search_active);
    try testing.expect(!model.composer_active);
    try testing.expectEqual(auth_id, model.selected);

    tree = try buildTree(arena, &model);
    if (findByKind(tree.root, .search_field)) |field| {
        try testing.expectEqualStrings("Search", field.placeholder);
        try testing.expect(field.autofocus);
    } else return error.WidgetNotFound;
    if (findByKind(tree.root, .textarea)) |composer| {
        try testing.expect(!composer.autofocus);
    } else return error.WidgetNotFound;

    main.update(&model, .stop, &fx);
    try testing.expect(!model.search_active);
    try testing.expectEqual(auth_id, model.selected);

    main.update(&model, .new_folder, &fx);
    const folder_id = model.folder_store[0].id;
    main.update(&model, .{ .assign_selected = folder_id }, &fx);
    try testing.expectEqual(folder_id, model.sessionById(auth_id).?.folder_id);
    try testing.expectEqual(@as(u32, 0), model.editing_folder_id);
    try testing.expectEqual(auth_id, model.selected);

    main.update(&model, .{ .assign_selected = folder_id }, &fx);
    try testing.expectEqual(folder_id, model.editing_folder_id);
    try testing.expectEqual(auth_id, model.selected);
    try testing.expect(!model.composer_active);

    tree = try buildTree(arena, &model);
    if (findByPlaceholder(tree.root, .text_field, "New folder")) |field| {
        try testing.expect(field.autofocus);
    } else return error.WidgetNotFound;
    if (findByKind(tree.root, .textarea)) |composer| {
        try testing.expect(!composer.autofocus);
    } else return error.WidgetNotFound;

    main.update(&model, .stop, &fx);
    try testing.expectEqual(@as(u32, 0), model.editing_folder_id);

    // History back is a normal select, so it uses the same autofocus edge.
    try testing.expect(model.can_go_back());
    main.update(&model, .history_back, &fx);
    try testing.expectEqual(port_id, model.selected);
    try testing.expectEqualStrings("port waku to zig", model.selected_title());
    try testing.expect(model.composer_active);
    try testing.expectEqual(@as(u32, 0), model.editing_session_id);
    try testing.expectEqual(@as(u32, 0), model.editing_folder_id);

    tree = try buildTree(arena, &model);
    if (findByKind(tree.root, .textarea)) |composer| {
        try testing.expect(composer.autofocus);
    } else return error.WidgetNotFound;
    _ = try expectByText(tree.root, .button, "Copy session");
}

test "cmd-[ / cmd-] and ctrl-[ / ctrl-] walk session history via onKey" {
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = main.initialModel();
    try testing.expectEqualStrings("port waku to zig", model.selected_title());
    try testing.expect(!model.can_go_back());
    try testing.expect(!model.can_go_forward());

    main.update(&model, .{ .select = model.session_store[1].id }, &fx);
    try testing.expectEqualStrings("fix auth listener", model.selected_title());
    try testing.expect(model.can_go_back());
    try testing.expect(!model.can_go_forward());

    // Composer typing: plain [ / ] stay draft text, not history.
    main.update(&model, .{ .draft_edit = .{ .insert_text = "[" } }, &fx);
    try testing.expectEqualStrings("[", model.draft());
    const plain_back = canvas.WidgetKeyboardEvent{ .phase = .key_down, .key = "[" };
    try testing.expectEqual(@as(?Msg, null), main.onKey(plain_back));
    try testing.expectEqualStrings("fix auth listener", model.selected_title());
    try testing.expectEqualStrings("[", model.draft());

    const plain_forward = canvas.WidgetKeyboardEvent{ .phase = .key_down, .key = "]" };
    try testing.expectEqual(@as(?Msg, null), main.onKey(plain_forward));
    try testing.expectEqualStrings("fix auth listener", model.selected_title());

    const cmd_back = canvas.WidgetKeyboardEvent{
        .phase = .key_down,
        .key = "[",
        .modifiers = .{ .super = true },
    };
    try testing.expectEqual(Msg.history_back, main.onKey(cmd_back).?);
    main.update(&model, main.onKey(cmd_back).?, &fx);
    try testing.expectEqualStrings("port waku to zig", model.selected_title());
    try testing.expect(!model.can_go_back());
    try testing.expect(model.can_go_forward());

    main.update(&model, main.onKey(cmd_back).?, &fx);
    try testing.expectEqualStrings("port waku to zig", model.selected_title());
    try testing.expect(!model.can_go_back());

    const cmd_forward = canvas.WidgetKeyboardEvent{
        .phase = .key_down,
        .key = "]",
        .modifiers = .{ .super = true },
    };
    try testing.expectEqual(Msg.history_forward, main.onKey(cmd_forward).?);
    main.update(&model, main.onKey(cmd_forward).?, &fx);
    try testing.expectEqualStrings("fix auth listener", model.selected_title());
    try testing.expect(model.can_go_back());
    try testing.expect(!model.can_go_forward());

    main.update(&model, main.onKey(cmd_forward).?, &fx);
    try testing.expectEqualStrings("fix auth listener", model.selected_title());
    try testing.expect(!model.can_go_forward());

    const ctrl_back = canvas.WidgetKeyboardEvent{
        .phase = .key_down,
        .key = "[",
        .modifiers = .{ .control = true },
    };
    try testing.expectEqual(Msg.history_back, main.onKey(ctrl_back).?);
    main.update(&model, main.onKey(ctrl_back).?, &fx);
    try testing.expectEqualStrings("port waku to zig", model.selected_title());

    const ctrl_forward = canvas.WidgetKeyboardEvent{
        .phase = .key_down,
        .key = "]",
        .modifiers = .{ .control = true },
    };
    try testing.expectEqual(Msg.history_forward, main.onKey(ctrl_forward).?);
    main.update(&model, main.onKey(ctrl_forward).?, &fx);
    try testing.expectEqualStrings("fix auth listener", model.selected_title());

    const escape = canvas.WidgetKeyboardEvent{ .phase = .key_down, .key = "escape" };
    try testing.expectEqual(Msg.stop, main.onKey(escape).?);
}

test "cmd-b and ctrl-b toggle sidebar collapse via onKey" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = main.initialModel();
    try testing.expect(!model.sidebar_collapsed);
    try testing.expect(model.sidebar_expanded());

    // Composer typing: plain b is draft text, not collapse.
    main.update(&model, .{ .draft_edit = .{ .insert_text = "b" } }, &fx);
    try testing.expectEqualStrings("b", model.draft());
    const plain_b = canvas.WidgetKeyboardEvent{ .phase = .key_down, .key = "b" };
    try testing.expectEqual(@as(?Msg, null), main.onKey(plain_b));
    try testing.expect(!model.sidebar_collapsed);
    try testing.expectEqualStrings("b", model.draft());

    var tree = try buildTree(arena, &model);
    const collapse = try expectButton(tree.root, "Collapse sidebar");
    try testing.expectEqual(Msg.toggle_sidebar, tree.msgForPointer(collapse.id, .up).?);

    const cmd_b = canvas.WidgetKeyboardEvent{
        .phase = .key_down,
        .key = "b",
        .modifiers = .{ .super = true },
    };
    try testing.expectEqual(Msg.toggle_sidebar, main.onKey(cmd_b).?);
    main.update(&model, main.onKey(cmd_b).?, &fx);
    try testing.expect(model.sidebar_collapsed);
    try testing.expect(!model.sidebar_expanded());
    try testing.expectEqual(main.sidebar_rail_width / main.window_width, model.sidebar_split);
    try testing.expectEqual(main.sidebar_rail_width, model.sidebar_pane_min());

    tree = try buildTree(arena, &model);
    try testing.expect(findByText(tree.root, .text, "Today") == null);
    try testing.expect(findPressableContaining(tree.root, "Search") == null);
    try testing.expect(findPressableContaining(tree.root, "New Task") == null);
    _ = try expectButton(tree.root, "Expand sidebar");

    main.update(&model, main.onKey(cmd_b).?, &fx);
    try testing.expect(!model.sidebar_collapsed);
    try testing.expectEqual(main.sidebar_default_width / main.window_width, model.sidebar_split);

    tree = try buildTree(arena, &model);
    _ = try expectByText(tree.root, .text, "Today");
    _ = try expectButton(tree.root, "Search");
    _ = try expectButton(tree.root, "New Task");
    _ = try expectButton(tree.root, "Collapse sidebar");

    const ctrl_b = canvas.WidgetKeyboardEvent{
        .phase = .key_down,
        .key = "B",
        .modifiers = .{ .control = true },
    };
    try testing.expectEqual(Msg.toggle_sidebar, main.onKey(ctrl_b).?);
    main.update(&model, main.onKey(ctrl_b).?, &fx);
    try testing.expect(model.sidebar_collapsed);

    const cmd_n = canvas.WidgetKeyboardEvent{
        .phase = .key_down,
        .key = "n",
        .modifiers = .{ .super = true },
    };
    try testing.expectEqual(Msg.new_session, main.onKey(cmd_n).?);
    const cmd_back = canvas.WidgetKeyboardEvent{
        .phase = .key_down,
        .key = "[",
        .modifiers = .{ .super = true },
    };
    try testing.expectEqual(Msg.history_back, main.onKey(cmd_back).?);
}

test "cmd-b persist extras stay merge-only" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-sidebar-cmd-b", .{tmp.sub_path[0..]});

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    const cmd_b = canvas.WidgetKeyboardEvent{
        .phase = .key_down,
        .key = "b",
        .modifiers = .{ .super = true },
    };
    try testing.expectEqual(Msg.toggle_sidebar, main.onKey(cmd_b).?);

    var missing = main.initialModel();
    missing.task_state_loaded = true;
    missing.setStoreDir(dir);
    missing.store_io = testing.io;
    main.update(&missing, main.onKey(cmd_b).?, &fx);
    try testing.expect(missing.sidebar_collapsed);
    var missing_path: [std.fs.max_path_bytes]u8 = undefined;
    try testing.expectError(error.FileNotFound, std.Io.Dir.cwd().readFileAlloc(testing.io, store.catalogPath(dir, &missing_path).?, testing.allocator, .limited(64)));

    var source = main.initialModel();
    source.task_state_loaded = true;
    source.setStoreDir(dir);
    source.store_io = testing.io;
    try store.saveSession(&source, source.session_store[0].id, testing.allocator, testing.io);
    try store.saveSession(&source, source.session_store[1].id, testing.allocator, testing.io);
    source.sidebar_last_width = 320;
    source.sidebar_split = 320 / main.window_width;
    main.update(&source, main.onKey(cmd_b).?, &fx);
    try testing.expect(source.sidebar_collapsed);

    var loaded = Model{};
    loaded.setStoreDir(dir);
    loaded.store_io = testing.io;
    try testing.expectEqual(store.LoadKind.loaded, store.loadCatalog(&loaded, testing.allocator, testing.io));
    try testing.expect(loaded.sidebar_collapsed);
    try testing.expectEqual(@as(u32, 2), loaded.session_count);
    try testing.expectEqual(source.session_store[0].id, loaded.session_store[0].id);
    try testing.expectEqual(source.session_store[1].id, loaded.session_store[1].id);
    try testing.expectEqual(@as(u32, 320), loaded.sidebarWidthPixels());
    try testing.expectEqual(main.sidebar_rail_width / main.window_width, loaded.sidebar_split);

    main.update(&loaded, main.onKey(cmd_b).?, &fx);
    try testing.expect(!loaded.sidebar_collapsed);

    var restored = Model{};
    restored.setStoreDir(dir);
    try testing.expectEqual(store.LoadKind.loaded, store.loadCatalog(&restored, testing.allocator, testing.io));
    try testing.expect(!restored.sidebar_collapsed);
    try testing.expectEqual(@as(u32, 2), restored.session_count);
    try testing.expectEqual(source.session_store[0].id, restored.session_store[0].id);
    try testing.expectEqual(source.session_store[1].id, restored.session_store[1].id);
    try testing.expectEqual(@as(u32, 320), restored.sidebarWidthPixels());
}

test "cmd-c and ctrl-c copy the last non-empty turn via writeClipboard" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    const other = model.addSession("other session", .fx);
    const id = model.addSession("copy last", .fx);
    model.selected = id;
    _ = model.appendTurn(other, .assistant, "not this session");

    const cmd_c = canvas.WidgetKeyboardEvent{
        .phase = .key_down,
        .key = "c",
        .modifiers = .{ .super = true },
    };
    const ctrl_c = canvas.WidgetKeyboardEvent{
        .phase = .key_down,
        .key = "C",
        .modifiers = .{ .control = true },
    };
    const plain_c = canvas.WidgetKeyboardEvent{ .phase = .key_down, .key = "c" };

    try testing.expectEqual(@as(?Msg, null), main.onKey(plain_c));
    try testing.expectEqual(Msg.copy_last_turn, main.onKey(cmd_c).?);
    try testing.expectEqual(Msg.copy_last_turn, main.onKey(ctrl_c).?);

    try testing.expectEqual(@as(usize, 0), fx.pendingClipboardCount());
    main.update(&model, main.onKey(cmd_c).?, &fx);
    try testing.expectEqual(@as(usize, 0), fx.pendingClipboardCount());
    try testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());

    _ = model.appendTurn(id, .user, "");
    _ = model.appendTurn(id, .assistant, "");
    main.update(&model, .copy_last_turn, &fx);
    try testing.expectEqual(@as(usize, 0), fx.pendingClipboardCount());

    _ = model.appendTurn(id, .user, "first visible");
    _ = model.appendTurn(id, .assistant, "last non-empty body");
    _ = model.appendTurn(id, .tool, "");
    const tree = try buildTree(arena, &model);
    _ = try expectButton(tree.root, "Copy");
    try testing.expect(findByText(tree.root, .button, "Rewind") == null);

    main.update(&model, main.onKey(cmd_c).?, &fx);
    try testing.expectEqual(@as(usize, 1), fx.pendingClipboardCount());
    const first = fx.pendingClipboardAt(0).?;
    try testing.expectEqual(main.copy_turn_key, first.key);
    try testing.expectEqual(native_sdk.EffectClipboardOp.write, first.op);
    try testing.expectEqualStrings("last non-empty body", first.text);

    main.update(&model, main.onKey(ctrl_c).?, &fx);
    try testing.expectEqual(@as(usize, 1), fx.pendingClipboardCount());
    try testing.expectEqual(main.copy_turn_key, fx.pendingClipboardAt(0).?.key);
    try testing.expectEqualStrings("last non-empty body", fx.pendingClipboardAt(0).?.text);

    const cmd_b = canvas.WidgetKeyboardEvent{
        .phase = .key_down,
        .key = "b",
        .modifiers = .{ .super = true },
    };
    try testing.expectEqual(Msg.toggle_sidebar, main.onKey(cmd_b).?);
    const cmd_back = canvas.WidgetKeyboardEvent{
        .phase = .key_down,
        .key = "[",
        .modifiers = .{ .super = true },
    };
    try testing.expectEqual(Msg.history_back, main.onKey(cmd_back).?);
    const cmd_forward = canvas.WidgetKeyboardEvent{
        .phase = .key_down,
        .key = "]",
        .modifiers = .{ .super = true },
    };
    try testing.expectEqual(Msg.history_forward, main.onKey(cmd_forward).?);
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

test "cmd-k and ctrl-k focus sidebar search via onKey" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = main.initialModel();
    try testing.expect(!model.search_active);
    try testing.expectEqualStrings("", model.search_query());

    const plain_k = canvas.WidgetKeyboardEvent{ .phase = .key_down, .key = "k" };
    try testing.expectEqual(@as(?Msg, null), main.onKey(plain_k));

    const cmd_k = canvas.WidgetKeyboardEvent{
        .phase = .key_down,
        .key = "k",
        .modifiers = .{ .super = true },
    };
    try testing.expectEqual(Msg.start_search, main.onKey(cmd_k).?);
    main.update(&model, main.onKey(cmd_k).?, &fx);
    try testing.expect(model.search_active);
    try testing.expectEqualStrings("", model.search_query());

    var tree = try buildTree(arena, &model);
    try testing.expect(findPressableContaining(tree.root, "Search") == null);
    if (findByKind(tree.root, .search_field)) |field| {
        try testing.expectEqualStrings("Search", field.placeholder);
        try expectLaidOutHeight(tree.root, field.id, 32);
    } else return error.WidgetNotFound;

    main.update(&model, .stop, &fx);
    try testing.expect(!model.search_active);

    const ctrl_k = canvas.WidgetKeyboardEvent{
        .phase = .key_down,
        .key = "K",
        .modifiers = .{ .control = true },
    };
    try testing.expectEqual(Msg.start_search, main.onKey(ctrl_k).?);
    main.update(&model, main.onKey(ctrl_k).?, &fx);
    try testing.expect(model.search_active);

    tree = try buildTree(arena, &model);
    if (findByKind(tree.root, .search_field)) |field| {
        try testing.expectEqualStrings("Search", field.placeholder);
    } else return error.WidgetNotFound;

    main.update(&model, .{ .search_edit = .{ .insert_text = "auth" } }, &fx);
    try expectRowTitles(model.session_rows(arena), &.{"fix auth listener"});
    const escape = canvas.WidgetKeyboardEvent{ .phase = .key_down, .key = "escape" };
    try testing.expectEqual(Msg.stop, main.onKey(escape).?);
    main.update(&model, main.onKey(escape).?, &fx);
    try testing.expectEqualStrings("", model.search_query());
    try testing.expect(!model.search_active);
    try expectRowTitles(model.session_rows(arena), &.{ "port waku to zig", "fix auth listener" });

    tree = try buildTree(arena, &model);
    _ = try expectButton(tree.root, "Search");
}

test "cmd-l and ctrl-l focus the composer via onKey" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = main.initialModel();
    try testing.expect(!model.composer_active);
    try testing.expect(!model.search_active);

    var tree = try buildTree(arena, &model);
    if (findByKind(tree.root, .textarea)) |composer| {
        try testing.expectEqualStrings("Do anything...", composer.placeholder);
        try testing.expect(!composer.autofocus);
    } else return error.WidgetNotFound;
    _ = try expectByText(tree.root, .button, "Copy session");
    _ = try expectButton(tree.root, "Attach image");
    try testing.expect(findByText(tree.root, .image, "Attached image") == null);

    const plain_l = canvas.WidgetKeyboardEvent{ .phase = .key_down, .key = "l" };
    try testing.expectEqual(@as(?Msg, null), main.onKey(plain_l));
    try testing.expect(!model.composer_active);

    const cmd_l = canvas.WidgetKeyboardEvent{
        .phase = .key_down,
        .key = "l",
        .modifiers = .{ .super = true },
    };
    try testing.expectEqual(Msg.focus_composer, main.onKey(cmd_l).?);
    main.update(&model, main.onKey(cmd_l).?, &fx);
    try testing.expect(model.composer_active);
    try testing.expectEqualStrings("", model.draft());

    tree = try buildTree(arena, &model);
    if (findByKind(tree.root, .textarea)) |composer| {
        try testing.expectEqualStrings("Do anything...", composer.placeholder);
        try testing.expect(composer.autofocus);
    } else return error.WidgetNotFound;
    _ = try expectByText(tree.root, .button, "Copy session");
    _ = try expectButton(tree.root, "Attach image");

    main.update(&model, .{ .draft_edit = .{ .insert_text = "plain l still types" } }, &fx);
    try testing.expectEqualStrings("plain l still types", model.draft());

    main.update(&model, .start_search, &fx);
    try testing.expect(model.search_active);
    try testing.expect(!model.composer_active);

    tree = try buildTree(arena, &model);
    if (findByKind(tree.root, .search_field)) |field| {
        try testing.expectEqualStrings("Search", field.placeholder);
        try testing.expect(field.autofocus);
    } else return error.WidgetNotFound;
    if (findByKind(tree.root, .textarea)) |composer| {
        try testing.expect(!composer.autofocus);
        try testing.expectEqualStrings("plain l still types", composer.text);
    } else return error.WidgetNotFound;

    const ctrl_l = canvas.WidgetKeyboardEvent{
        .phase = .key_down,
        .key = "L",
        .modifiers = .{ .control = true },
    };
    try testing.expectEqual(Msg.focus_composer, main.onKey(ctrl_l).?);
    main.update(&model, main.onKey(ctrl_l).?, &fx);
    try testing.expect(model.composer_active);
    try testing.expect(model.search_active);

    tree = try buildTree(arena, &model);
    if (findByKind(tree.root, .textarea)) |composer| {
        try testing.expect(composer.autofocus);
        try testing.expectEqualStrings("plain l still types", composer.text);
    } else return error.WidgetNotFound;
    _ = try expectByText(tree.root, .button, "Copy session");
    _ = try expectButton(tree.root, "Attach image");
    try testing.expect(findByText(tree.root, .image, "Attached image") == null);

    const cmd_k = canvas.WidgetKeyboardEvent{
        .phase = .key_down,
        .key = "k",
        .modifiers = .{ .super = true },
    };
    try testing.expectEqual(Msg.start_search, main.onKey(cmd_k).?);
    const cmd_c = canvas.WidgetKeyboardEvent{
        .phase = .key_down,
        .key = "c",
        .modifiers = .{ .super = true },
    };
    try testing.expectEqual(Msg.copy_last_turn, main.onKey(cmd_c).?);
}

test "cmd-comma and ctrl-comma open settings via onKey" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = main.initialModel();
    try testing.expect(!model.settings_open);
    try testing.expect(!model.search_active);

    const plain_comma = canvas.WidgetKeyboardEvent{ .phase = .key_down, .key = "," };
    try testing.expectEqual(@as(?Msg, null), main.onKey(plain_comma));

    const cmd_comma = canvas.WidgetKeyboardEvent{
        .phase = .key_down,
        .key = ",",
        .modifiers = .{ .super = true },
    };
    try testing.expectEqual(Msg.toggle_settings, main.onKey(cmd_comma).?);
    main.update(&model, main.onKey(cmd_comma).?, &fx);
    try testing.expect(model.settings_open);

    var tree = try buildTree(arena, &model);
    _ = try expectByText(tree.root, .text, "Settings");
    _ = try expectByText(tree.root, .text, "Default model");
    try testing.expect(findByPlaceholder(tree.root, .text_field, "FX_MODEL") != null);
    try testing.expect(findByText(tree.root, .button, "Send") == null);

    main.update(&model, main.onKey(cmd_comma).?, &fx);
    try testing.expect(!model.settings_open);

    const ctrl_comma = canvas.WidgetKeyboardEvent{
        .phase = .key_down,
        .key = ",",
        .modifiers = .{ .control = true },
    };
    try testing.expectEqual(Msg.toggle_settings, main.onKey(ctrl_comma).?);
    main.update(&model, main.onKey(ctrl_comma).?, &fx);
    try testing.expect(model.settings_open);

    tree = try buildTree(arena, &model);
    _ = try expectByText(tree.root, .text, "Default model");

    const escape = canvas.WidgetKeyboardEvent{ .phase = .key_down, .key = "escape" };
    try testing.expectEqual(Msg.stop, main.onKey(escape).?);
    main.update(&model, main.onKey(escape).?, &fx);
    try testing.expect(!model.settings_open);

    tree = try buildTree(arena, &model);
    _ = try expectByText(tree.root, .button, "Send");
    try testing.expect(findByText(tree.root, .text, "Default model") == null);

    const cmd_k = canvas.WidgetKeyboardEvent{
        .phase = .key_down,
        .key = "k",
        .modifiers = .{ .super = true },
    };
    try testing.expectEqual(Msg.start_search, main.onKey(cmd_k).?);
    main.update(&model, main.onKey(cmd_k).?, &fx);
    try testing.expect(model.search_active);
    try testing.expect(!model.settings_open);

    tree = try buildTree(arena, &model);
    if (findByKind(tree.root, .search_field)) |field| {
        try testing.expectEqualStrings("Search", field.placeholder);
    } else return error.WidgetNotFound;
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

test "remove drops the session id from selection history" {
    var model = Model{};
    const first = model.addSession("first", .fx);
    const second = model.addSession("second", .fx);
    const third = model.addSession("third", .fx);
    model.selected = first;
    model.pushSelectionHistory(first);
    model.pushSelectionHistory(second);
    model.pushSelectionHistory(third);
    try testing.expectEqual(@as(u32, 3), model.history_count);
    try testing.expectEqual(third, model.history_store[model.history_index]);

    model.dropSession(second);
    try testing.expectEqual(@as(u32, 2), model.history_count);
    try testing.expectEqual(first, model.history_store[0]);
    try testing.expectEqual(third, model.history_store[1]);
    try testing.expectEqual(@as(u32, 1), model.history_index);
    try testing.expect(model.can_go_back());
    try testing.expect(!model.can_go_forward());

    model.dropSession(third);
    try testing.expectEqual(@as(u32, 1), model.history_count);
    try testing.expectEqual(first, model.history_store[0]);
    try testing.expectEqual(@as(u32, 0), model.history_index);
    try testing.expectEqual(first, model.selected);
    try testing.expect(!model.can_go_back());

    model.dropSession(first);
    try testing.expectEqual(@as(u32, 0), model.history_count);
    try testing.expectEqual(@as(u32, 0), model.selected);
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

    const tree = try buildTree(arena, &model);
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

test "clicking a folder header assigns the selected session; Today unassigns" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-folder-click-assign", .{tmp.sub_path[0..]});

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = main.initialModel();
    model.task_state_loaded = true;
    model.setStoreDir(dir);
    model.store_io = testing.io;
    try store.saveSession(&model, model.selected, testing.allocator, testing.io);
    try store.saveSession(&model, model.session_store[1].id, testing.allocator, testing.io);

    var tree = try buildTree(arena, &model);
    main.update(&model, tree.msgForPointer((try expectButton(tree.root, "New folder")).id, .up).?, &fx);
    const folder_id = model.folder_store[0].id;
    const auth_id = model.session_store[1].id;
    try testing.expectEqual(@as(u32, 0), model.session_store[1].folder_id);

    tree = try buildTree(arena, &model);
    const auth = try expectButton(tree.root, "fix auth listener");
    main.update(&model, tree.msgForPointer(auth.id, .up).?, &fx);
    try testing.expectEqual(auth_id, model.selected);

    const header = try expectByText(tree.root, .list_item, "New folder");
    main.update(&model, tree.msgForPointer(header.id, .up).?, &fx);
    try testing.expectEqual(folder_id, model.session_store[1].folder_id);
    try testing.expectEqual(@as(u32, 0), model.session_store[0].folder_id);
    try expectSidebarTitles(model.sidebar_rows(arena), &.{
        "port waku to zig",
        "New folder",
        "fix auth listener",
    });
    try expectRowTitles(model.session_rows(arena), &.{ "port waku to zig", "fix auth listener" });

    tree = try buildTree(arena, &model);
    _ = try expectByText(tree.root, .text, "Today");
    _ = try expectButton(tree.root, "port waku to zig");
    _ = try expectButton(tree.root, "fix auth listener");
    _ = try expectButton(tree.root, "Collapse folder");
    try testing.expect(findPressableContaining(tree.root, "fix auth listener") != null);

    var loaded = Model{};
    loaded.setStoreDir(dir);
    loaded.store_io = testing.io;
    try testing.expectEqual(store.LoadKind.loaded, store.loadCatalog(&loaded, testing.allocator, testing.io));
    try testing.expectEqual(folder_id, loaded.session_store[1].folder_id);
    try expectSidebarTitles(loaded.sidebar_rows(arena), &.{
        "port waku to zig",
        "New folder",
        "fix auth listener",
    });

    tree = try buildTree(arena, &model);
    const today = try expectByText(tree.root, .list_item, "Today");
    main.update(&model, tree.msgForPointer(today.id, .up).?, &fx);
    try testing.expectEqual(@as(u32, 0), model.session_store[1].folder_id);
    try expectSidebarTitles(model.sidebar_rows(arena), &.{
        "port waku to zig",
        "fix auth listener",
        "New folder",
    });

    var unassigned = Model{};
    unassigned.setStoreDir(dir);
    unassigned.store_io = testing.io;
    try testing.expectEqual(store.LoadKind.loaded, store.loadCatalog(&unassigned, testing.allocator, testing.io));
    try testing.expectEqual(@as(u32, 0), unassigned.session_store[1].folder_id);
    try expectSidebarTitles(unassigned.sidebar_rows(arena), &.{
        "port waku to zig",
        "fix auth listener",
        "New folder",
    });

    tree = try buildTree(arena, &model);
    main.update(&model, tree.msgForPointer((try expectByText(tree.root, .list_item, "New folder")).id, .up).?, &fx);
    try testing.expectEqual(folder_id, model.session_store[1].folder_id);

    tree = try buildTree(arena, &model);
    const collapse = try expectButton(tree.root, "Collapse folder");
    main.update(&model, tree.msgForPointer(collapse.id, .up).?, &fx);
    try testing.expect(model.folder_store[0].collapsed);
    try expectSidebarTitles(model.sidebar_rows(arena), &.{
        "port waku to zig",
        "New folder",
    });
    tree = try buildTree(arena, &model);
    try testing.expect(findPressableContaining(tree.root, "fix auth listener") == null);
    _ = try expectByText(tree.root, .list_item, "New folder");
    _ = try expectButton(tree.root, "Collapse folder");
    _ = try expectButton(tree.root, "Search");
}

test "second click on a folder title edits it; empty name becomes New folder" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-folder-rename", .{tmp.sub_path[0..]});

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = main.initialModel();
    model.task_state_loaded = true;
    model.setStoreDir(dir);
    model.store_io = testing.io;
    try store.saveSession(&model, model.selected, testing.allocator, testing.io);
    try store.saveSession(&model, model.session_store[1].id, testing.allocator, testing.io);

    var tree = try buildTree(arena, &model);
    main.update(&model, tree.msgForPointer((try expectButton(tree.root, "New folder")).id, .up).?, &fx);
    const folder_id = model.folder_store[0].id;
    const auth_id = model.session_store[1].id;

    tree = try buildTree(arena, &model);
    main.update(&model, tree.msgForPointer((try expectButton(tree.root, "fix auth listener")).id, .up).?, &fx);
    try testing.expectEqual(auth_id, model.selected);

    tree = try buildTree(arena, &model);
    const header = try expectByText(tree.root, .list_item, "New folder");
    main.update(&model, tree.msgForPointer(header.id, .up).?, &fx);
    try testing.expectEqual(folder_id, model.session_store[1].folder_id);
    try testing.expectEqual(@as(u32, 0), model.editing_folder_id);
    try testing.expect(findByPlaceholder(tree.root, .text_field, "New folder") == null);

    tree = try buildTree(arena, &model);
    main.update(&model, tree.msgForPointer((try expectByText(tree.root, .list_item, "New folder")).id, .up).?, &fx);
    try testing.expectEqual(folder_id, model.editing_folder_id);
    try testing.expectEqual(folder_id, model.session_store[1].folder_id);

    tree = try buildTree(arena, &model);
    try testing.expect(findByPlaceholder(tree.root, .text_field, "New folder") != null);
    _ = try expectButton(tree.root, "Collapse folder");

    main.update(&model, .{ .folder_title_edit = .clear }, &fx);
    main.update(&model, .{ .folder_title_edit = .{ .insert_text = "Work" } }, &fx);
    try testing.expectEqualStrings("Work", model.folder_store[0].title());
    try expectSidebarTitles(model.sidebar_rows(arena), &.{
        "port waku to zig",
        "Work",
        "fix auth listener",
    });

    tree = try buildTree(arena, &model);
    _ = try expectByText(tree.root, .list_item, "Work");
    try testing.expect(findByPlaceholder(tree.root, .text_field, "New folder") != null);

    var loaded = Model{};
    loaded.setStoreDir(dir);
    loaded.store_io = testing.io;
    try testing.expectEqual(store.LoadKind.loaded, store.loadCatalog(&loaded, testing.allocator, testing.io));
    try testing.expectEqualStrings("Work", loaded.folder_store[0].title());
    try testing.expectEqual(folder_id, loaded.session_store[1].folder_id);
    try expectSidebarTitles(loaded.sidebar_rows(arena), &.{
        "port waku to zig",
        "Work",
        "fix auth listener",
    });

    main.update(&model, .{ .folder_title_edit = .clear }, &fx);
    try testing.expectEqualStrings("New folder", model.folder_store[0].title());
    try testing.expectEqual(@as(usize, 0), model.folder_title_draft().len);

    var empty = Model{};
    empty.setStoreDir(dir);
    empty.store_io = testing.io;
    try testing.expectEqual(store.LoadKind.loaded, store.loadCatalog(&empty, testing.allocator, testing.io));
    try testing.expectEqualStrings("New folder", empty.folder_store[0].title());

    const escape = canvas.WidgetKeyboardEvent{ .phase = .key_down, .key = "escape" };
    try testing.expectEqual(Msg.stop, main.onKey(escape).?);
    main.update(&model, main.onKey(escape).?, &fx);
    try testing.expectEqual(@as(u32, 0), model.editing_folder_id);

    tree = try buildTree(arena, &model);
    try testing.expect(findByPlaceholder(tree.root, .text_field, "New folder") == null);
    _ = try expectByText(tree.root, .list_item, "New folder");

    main.update(&model, tree.msgForPointer((try expectButton(tree.root, "port waku to zig")).id, .up).?, &fx);
    try testing.expectEqual(model.session_store[0].id, model.selected);
    try testing.expectEqual(@as(u32, 0), model.session_store[0].folder_id);

    tree = try buildTree(arena, &model);
    main.update(&model, tree.msgForPointer((try expectByText(tree.root, .list_item, "New folder")).id, .up).?, &fx);
    try testing.expectEqual(folder_id, model.session_store[0].folder_id);
    try testing.expectEqual(@as(u32, 0), model.editing_folder_id);
    try expectSidebarTitles(model.sidebar_rows(arena), &.{
        "New folder",
        "port waku to zig",
        "fix auth listener",
    });

    tree = try buildTree(arena, &model);
    const collapse = try expectButton(tree.root, "Collapse folder");
    main.update(&model, tree.msgForPointer(collapse.id, .up).?, &fx);
    try testing.expect(model.folder_store[0].collapsed);
    try expectSidebarTitles(model.sidebar_rows(arena), &.{
        "New folder",
    });
    tree = try buildTree(arena, &model);
    try testing.expect(findPressableContaining(tree.root, "port waku to zig") == null);
    try testing.expect(findPressableContaining(tree.root, "fix auth listener") == null);
    _ = try expectByText(tree.root, .list_item, "New folder");
    _ = try expectButton(tree.root, "Collapse folder");
}

test "deleting a folder unassigns its sessions; they stay in Today" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-folder-delete", .{tmp.sub_path[0..]});

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = main.initialModel();
    model.task_state_loaded = true;
    model.setStoreDir(dir);
    model.store_io = testing.io;
    try store.saveSession(&model, model.selected, testing.allocator, testing.io);
    try store.saveSession(&model, model.session_store[1].id, testing.allocator, testing.io);

    var tree = try buildTree(arena, &model);
    main.update(&model, tree.msgForPointer((try expectButton(tree.root, "New folder")).id, .up).?, &fx);
    const folder_id = model.folder_store[0].id;
    const auth_id = model.session_store[1].id;
    const port_id = model.session_store[0].id;

    tree = try buildTree(arena, &model);
    main.update(&model, tree.msgForPointer((try expectButton(tree.root, "fix auth listener")).id, .up).?, &fx);
    try testing.expectEqual(auth_id, model.selected);

    tree = try buildTree(arena, &model);
    main.update(&model, tree.msgForPointer((try expectByText(tree.root, .list_item, "New folder")).id, .up).?, &fx);
    try testing.expectEqual(folder_id, model.session_store[1].folder_id);
    try testing.expectEqual(@as(u32, 0), model.session_store[0].folder_id);

    tree = try buildTree(arena, &model);
    _ = try expectButton(tree.root, "Collapse folder");
    const trash = try expectButton(tree.root, "Delete folder");
    const remove_session = try expectButton(tree.root, "Remove session");
    try testing.expect(trash.id != (try expectByText(tree.root, .list_item, "New folder")).id);
    try testing.expect(trash.id != (try expectButton(tree.root, "Collapse folder")).id);
    try testing.expect(trash.id != remove_session.id);
    main.update(&model, tree.msgForPointer(trash.id, .up).?, &fx);

    try testing.expectEqual(@as(u32, 0), model.folder_count);
    try testing.expectEqual(@as(u32, 0), model.session_store[1].folder_id);
    try testing.expectEqual(@as(u32, 2), model.session_count);
    try testing.expectEqual(auth_id, model.session_store[1].id);
    try testing.expectEqual(port_id, model.session_store[0].id);
    try testing.expectEqual(auth_id, model.selected);
    try expectSidebarTitles(model.sidebar_rows(arena), &.{
        "port waku to zig",
        "fix auth listener",
    });
    try expectRowTitles(model.session_rows(arena), &.{ "port waku to zig", "fix auth listener" });

    tree = try buildTree(arena, &model);
    try testing.expect(findByText(tree.root, .list_item, "New folder") == null);
    try testing.expect(findPressableContaining(tree.root, "Delete folder") == null);
    try testing.expect(findPressableContaining(tree.root, "Collapse folder") == null);
    _ = try expectButton(tree.root, "port waku to zig");
    _ = try expectButton(tree.root, "fix auth listener");
    _ = try expectButton(tree.root, "Remove session");
    _ = try expectByText(tree.root, .text, "Today");
    _ = try expectButton(tree.root, "New folder");
    _ = try expectButton(tree.root, "Close");

    var loaded = Model{};
    loaded.setStoreDir(dir);
    loaded.store_io = testing.io;
    try testing.expectEqual(store.LoadKind.loaded, store.loadCatalog(&loaded, testing.allocator, testing.io));
    try testing.expectEqual(@as(u32, 0), loaded.folder_count);
    try testing.expectEqual(@as(u32, 2), loaded.session_count);
    try testing.expectEqual(@as(u32, 0), loaded.session_store[0].folder_id);
    try testing.expectEqual(@as(u32, 0), loaded.session_store[1].folder_id);
    try expectSidebarTitles(loaded.sidebar_rows(arena), &.{
        "port waku to zig",
        "fix auth listener",
    });

    tree = try buildTree(arena, &model);
    main.update(&model, tree.msgForPointer((try expectButton(tree.root, "New folder")).id, .up).?, &fx);
    const next_id = model.folder_store[0].id;
    try testing.expect(next_id != folder_id);
    try testing.expectEqual(@as(u32, 1), model.folder_count);

    tree = try buildTree(arena, &model);
    main.update(&model, tree.msgForPointer((try expectByText(tree.root, .list_item, "New folder")).id, .up).?, &fx);
    try testing.expectEqual(next_id, model.session_store[1].folder_id);
    try testing.expectEqual(@as(u32, 0), model.editing_folder_id);

    tree = try buildTree(arena, &model);
    main.update(&model, tree.msgForPointer((try expectByText(tree.root, .list_item, "New folder")).id, .up).?, &fx);
    try testing.expectEqual(next_id, model.editing_folder_id);
    main.update(&model, .{ .folder_title_edit = .clear }, &fx);
    main.update(&model, .{ .folder_title_edit = .{ .insert_text = "Work" } }, &fx);
    try testing.expectEqualStrings("Work", model.folder_store[0].title());
    main.update(&model, .stop, &fx);
    try testing.expectEqual(@as(u32, 0), model.editing_folder_id);

    tree = try buildTree(arena, &model);
    const collapse = try expectButton(tree.root, "Collapse folder");
    _ = try expectButton(tree.root, "Delete folder");
    main.update(&model, tree.msgForPointer(collapse.id, .up).?, &fx);
    try testing.expect(model.folder_store[0].collapsed);
    try expectSidebarTitles(model.sidebar_rows(arena), &.{
        "port waku to zig",
        "Work",
    });
    tree = try buildTree(arena, &model);
    try testing.expect(findPressableContaining(tree.root, "fix auth listener") == null);
    _ = try expectByText(tree.root, .list_item, "Work");
    _ = try expectButton(tree.root, "Collapse folder");
    _ = try expectButton(tree.root, "Delete folder");
    _ = try expectButton(tree.root, "Close");
}

test "sidebar trash removes a session and it stays gone after reload" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-session-remove", .{tmp.sub_path[0..]});

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = main.initialModel();
    model.task_state_loaded = true;
    model.setStoreDir(dir);
    model.store_io = testing.io;
    const port_id = model.session_store[0].id;
    const auth_id = model.session_store[1].id;
    try store.saveSession(&model, port_id, testing.allocator, testing.io);
    try store.saveSession(&model, auth_id, testing.allocator, testing.io);
    model.pushSelectionHistory(auth_id);
    model.selected = auth_id;

    var tree = try buildTree(arena, &model);
    main.update(&model, tree.msgForPointer((try expectButton(tree.root, "New folder")).id, .up).?, &fx);
    const folder_id = model.folder_store[0].id;

    tree = try buildTree(arena, &model);
    const folder_trash = try expectButton(tree.root, "Delete folder");
    const auth_row = try expectByText(tree.root, .list_item, "fix auth listener");
    const remove = try expectButton(auth_row, "Remove session");
    try testing.expect(remove.id != folder_trash.id);
    try testing.expect(remove.id != auth_row.id);
    try testing.expect(remove.id != (try expectButton(tree.root, "Collapse folder")).id);
    try testing.expectEqual(Msg{ .remove_session = auth_id }, tree.msgForPointer(remove.id, .up).?);

    main.update(&model, tree.msgForPointer(remove.id, .up).?, &fx);
    try testing.expect(model.sessionById(auth_id) == null);
    try testing.expectEqual(@as(u32, 1), model.session_count);
    try testing.expectEqual(@as(u32, 1), model.folder_count);
    try testing.expectEqual(folder_id, model.folder_store[0].id);
    try testing.expectEqual(port_id, model.selected);
    try testing.expectEqual(port_id, model.session_store[0].id);
    try expectSidebarTitles(model.sidebar_rows(arena), &.{ "port waku to zig", "New folder" });
    try expectRowTitles(model.session_rows(arena), &.{"port waku to zig"});
    var hist_i: u32 = 0;
    while (hist_i < model.history_count) : (hist_i += 1) {
        try testing.expect(model.history_store[hist_i] != auth_id);
    }

    tree = try buildTree(arena, &model);
    try testing.expect(findByText(tree.root, .list_item, "fix auth listener") == null);
    try testing.expect(findPressableContaining(tree.root, "fix auth listener") == null);
    _ = try expectButton(tree.root, "port waku to zig");
    _ = try expectButton(tree.root, "Remove session");
    _ = try expectButton(tree.root, "New folder");
    _ = try expectButton(tree.root, "Delete folder");
    _ = try expectButton(tree.root, "Close");

    var loaded = Model{};
    loaded.setStoreDir(dir);
    loaded.store_io = testing.io;
    try testing.expectEqual(store.LoadKind.loaded, store.loadCatalog(&loaded, testing.allocator, testing.io));
    try testing.expectEqual(@as(u32, 1), loaded.session_count);
    try testing.expectEqual(@as(u32, 1), loaded.folder_count);
    try testing.expectEqual(port_id, loaded.session_store[0].id);
    try testing.expectEqualStrings("port waku to zig", loaded.session_store[0].title());
    try testing.expect(loaded.sessionById(auth_id) == null);
    try expectSidebarTitles(loaded.sidebar_rows(arena), &.{ "port waku to zig", "New folder" });

    tree = try buildTree(arena, &loaded);
    const last_row = try expectByText(tree.root, .list_item, "port waku to zig");
    const last_remove = try expectButton(last_row, "Remove session");
    main.update(&loaded, tree.msgForPointer(last_remove.id, .up).?, &fx);
    try testing.expectEqual(@as(u32, 0), loaded.session_count);
    try testing.expectEqual(@as(u32, 1), loaded.folder_count);
    try testing.expectEqual(@as(u32, 0), loaded.selected);
    try testing.expectEqualStrings("New task", loaded.header_title());
    try expectSidebarTitles(loaded.sidebar_rows(arena), &.{"New folder"});

    tree = try buildTree(arena, &loaded);
    try testing.expect(findPressableContaining(tree.root, "port waku to zig") == null);
    try testing.expect(findPressableContaining(tree.root, "Remove session") == null);
    _ = try expectButton(tree.root, "New Task");
    _ = try expectByText(tree.root, .text, "What should we build?");

    var reread = Model{};
    reread.setStoreDir(dir);
    reread.store_io = testing.io;
    try testing.expectEqual(store.LoadKind.loaded, store.loadCatalog(&reread, testing.allocator, testing.io));
    try testing.expectEqual(@as(u32, 0), reread.session_count);
}

test "sidebar Remove session with a daemon address records closeSession" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-session-remove-close", .{tmp.sub_path[0..]});

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.task_state_loaded = true;
    model.setStoreDir(dir);
    model.store_io = testing.io;
    model.setDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    const kept = model.addSession("keep me", .fx);
    _ = model.appendTurn(kept, .user, "stays");
    try store.saveSession(&model, kept, testing.allocator, testing.io);
    const gone = model.addSession("remove me", .fx);
    _ = model.appendTurn(gone, .user, "bye");
    try store.saveSession(&model, gone, testing.allocator, testing.io);
    model.selected = gone;

    var tree = try buildTree(arena, &model);
    const gone_row = try expectByText(tree.root, .list_item, "remove me");
    const remove = try expectButton(gone_row, "Remove session");
    try testing.expectEqual(Msg{ .remove_session = gone }, tree.msgForPointer(remove.id, .up).?);
    main.update(&model, tree.msgForPointer(remove.id, .up).?, &fx);

    const spawn = findCloseOnlySpawn(&fx) orelse return error.CloseSpawnMissing;
    try testing.expect(argvHas(spawn.argv, daemon_proxy.SUBCOMMAND));
    try testing.expect(argvHas(spawn.argv, "127.0.0.1:8787"));
    try testing.expect(std.mem.indexOf(u8, spawn.stdin, "\"type\":\"hello\"") != null);
    try testing.expect(std.mem.indexOf(u8, spawn.stdin, "\"type\":\"closeSession\"") != null);
    try testing.expect(std.mem.indexOf(u8, spawn.stdin, "\"command\":{\"type\":\"closeSession\"}") != null);
    var gone_id_buf: [36]u8 = undefined;
    try testing.expect(std.mem.indexOf(u8, spawn.stdin, daemon_proxy.wireUuid(gone, &gone_id_buf)) != null);
    try testing.expect(std.mem.indexOf(u8, spawn.stdin, "\"type\":\"removeSession\"") == null);
    try testing.expect(model.sessionById(gone) == null);
    try testing.expectEqual(@as(u32, 1), model.session_count);
    try testing.expectEqual(kept, model.selected);
}

test "click the selected session title edits it; empty name becomes untitled" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-session-rename", .{tmp.sub_path[0..]});

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = main.initialModel();
    model.task_state_loaded = true;
    model.setStoreDir(dir);
    model.store_io = testing.io;
    const port_id = model.session_store[0].id;
    const auth_id = model.session_store[1].id;
    try store.saveSession(&model, port_id, testing.allocator, testing.io);
    try store.saveSession(&model, auth_id, testing.allocator, testing.io);

    var tree = try buildTree(arena, &model);
    const toolbar = try expectByText(tree.root, .row, "Toolbar");
    const header = try expectByText(toolbar, .text, "port waku to zig");
    try testing.expectEqual(Msg.edit_session_title, tree.msgForPointer(header.id, .up).?);
    try testing.expectEqual(@as(u32, 0), model.editing_session_id);
    try testing.expect(findByPlaceholder(tree.root, .text_field, "untitled") == null);

    main.update(&model, tree.msgForPointer(header.id, .up).?, &fx);
    try testing.expectEqual(port_id, model.editing_session_id);
    try testing.expectEqual(port_id, model.selected);

    tree = try buildTree(arena, &model);
    try testing.expect(findByPlaceholder(tree.root, .text_field, "untitled") != null);
    _ = try expectButton(tree.root, "Close");

    main.update(&model, .{ .session_title_edit = .clear }, &fx);
    main.update(&model, .{ .session_title_edit = .{ .insert_text = "Review auth" } }, &fx);
    try testing.expectEqualStrings("Review auth", model.session_store[0].title());
    try testing.expectEqualStrings("Review auth", model.header_title());
    try testing.expectEqualStrings("Review auth", model.selected_title());
    try expectSidebarTitles(model.sidebar_rows(arena), &.{
        "Review auth",
        "fix auth listener",
    });

    tree = try buildTree(arena, &model);
    _ = try expectByText(tree.root, .list_item, "Review auth");
    try testing.expect(findByPlaceholder(tree.root, .text_field, "untitled") != null);

    var loaded = Model{};
    loaded.setStoreDir(dir);
    loaded.store_io = testing.io;
    try testing.expectEqual(store.LoadKind.loaded, store.loadCatalog(&loaded, testing.allocator, testing.io));
    try testing.expectEqualStrings("Review auth", loaded.session_store[0].title());
    try testing.expect(!loaded.session_store[0].untitled);
    try expectSidebarTitles(loaded.sidebar_rows(arena), &.{
        "Review auth",
        "fix auth listener",
    });

    main.update(&model, .{ .session_title_edit = .clear }, &fx);
    try testing.expectEqualStrings("untitled", model.session_store[0].title());
    try testing.expectEqualStrings("untitled", model.header_title());
    try testing.expectEqual(@as(usize, 0), model.session_title_draft().len);

    var empty = Model{};
    empty.setStoreDir(dir);
    empty.store_io = testing.io;
    try testing.expectEqual(store.LoadKind.loaded, store.loadCatalog(&empty, testing.allocator, testing.io));
    try testing.expectEqualStrings("untitled", empty.session_store[0].title());
    try testing.expect(!empty.session_store[0].untitled);

    const escape = canvas.WidgetKeyboardEvent{ .phase = .key_down, .key = "escape" };
    try testing.expectEqual(Msg.stop, main.onKey(escape).?);
    main.update(&model, main.onKey(escape).?, &fx);
    try testing.expectEqual(@as(u32, 0), model.editing_session_id);

    tree = try buildTree(arena, &model);
    try testing.expect(findByPlaceholder(tree.root, .text_field, "untitled") == null);
    const empty_toolbar = try expectByText(tree.root, .row, "Toolbar");
    _ = try expectByText(empty_toolbar, .text, "untitled");
    _ = try expectButton(tree.root, "New task");
    _ = try expectButton(tree.root, "Close");

    tree = try buildTree(arena, &model);
    main.update(&model, tree.msgForPointer((try expectButton(tree.root, "fix auth listener")).id, .up).?, &fx);
    try testing.expectEqual(auth_id, model.selected);
    try testing.expectEqual(@as(u32, 0), model.editing_session_id);

    tree = try buildTree(arena, &model);
    main.update(&model, tree.msgForPointer((try expectButton(tree.root, "fix auth listener")).id, .up).?, &fx);
    try testing.expectEqual(auth_id, model.editing_session_id);
    try testing.expectEqual(auth_id, model.selected);

    tree = try buildTree(arena, &model);
    try testing.expect(findByPlaceholder(tree.root, .text_field, "untitled") != null);

    main.update(&model, .new_session, &fx);
    try testing.expectEqual(@as(u32, 0), model.editing_session_id);
    try testing.expect(model.sessionById(model.selected).?.untitled);
    try testing.expectEqualStrings("untitled", model.selected_title());
    try testing.expectEqualStrings("New task", model.header_title());

    main.update(&model, .{ .draft_edit = .{ .insert_text = "first send titles me" } }, &fx);
    main.update(&model, .send, &fx);
    try testing.expect(model.is_streaming());
    try testing.expect(!model.sessionById(model.selected).?.untitled);
    try testing.expectEqualStrings("first send titles me", model.selected_title());
    try testing.expectEqualStrings("first send titles me", model.header_title());

    tree = try buildTree(arena, &model);
    const close = try expectButton(tree.root, "Close");
    try testing.expectEqual(Msg.close_window, tree.msgForPointer(close.id, .up).?);

    tree = try buildTree(arena, &model);
    main.update(&model, tree.msgForPointer((try expectButton(tree.root, "New folder")).id, .up).?, &fx);
    const folder_id = model.folder_store[0].id;
    tree = try buildTree(arena, &model);
    main.update(&model, tree.msgForPointer((try expectByText(tree.root, .list_item, "New folder")).id, .up).?, &fx);
    try testing.expectEqual(folder_id, model.sessionById(model.selected).?.folder_id);
    try testing.expectEqual(@as(u32, 0), model.editing_folder_id);
    tree = try buildTree(arena, &model);
    main.update(&model, tree.msgForPointer((try expectByText(tree.root, .list_item, "New folder")).id, .up).?, &fx);
    try testing.expectEqual(folder_id, model.editing_folder_id);
    try testing.expectEqual(@as(u32, 0), model.editing_session_id);
}

test "header Close requests the real window close; Esc stays with settings" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = main.initialModel();
    try testing.expect(main.shell_scene.windows[0].titlebar == .chromeless);
    try testing.expectEqualStrings(main.main_window_label, main.shell_scene.windows[0].label);

    var tree = try buildTree(arena, &model);
    _ = try expectButton(tree.root, "New folder");
    _ = try expectByText(tree.root, .text, "Today");
    const close = try expectButton(tree.root, "Close");
    try testing.expectEqual(Msg.close_window, tree.msgForPointer(close.id, .up).?);

    var actions = fx.windowActionState();
    try testing.expectEqual(@as(u32, 0), actions.close_count);
    try testing.expectEqual(@as(u32, 0), actions.quit_count);

    main.update(&model, tree.msgForPointer(close.id, .up).?, &fx);
    actions = fx.windowActionState();
    try testing.expectEqual(@as(u32, 1), actions.close_count);
    try testing.expectEqual(@as(u32, 0), actions.quit_count);
    try testing.expectEqualStrings(main.main_window_label, actions.lastLabel());
    try testing.expect(main.shell_scene.windows[0].titlebar == .chromeless);

    tree = try buildTree(arena, &model);
    _ = try expectButton(tree.root, "New folder");
    const gear = try expectButton(tree.root, "Settings");
    main.update(&model, tree.msgForPointer(gear.id, .up).?, &fx);
    try testing.expect(model.settings_open);

    const escape = canvas.WidgetKeyboardEvent{ .phase = .key_down, .key = "escape" };
    try testing.expectEqual(Msg.stop, main.onKey(escape).?);
    main.update(&model, main.onKey(escape).?, &fx);
    try testing.expect(!model.settings_open);
    actions = fx.windowActionState();
    try testing.expectEqual(@as(u32, 1), actions.close_count);
    try testing.expectEqual(@as(u32, 0), actions.quit_count);

    tree = try buildTree(arena, &model);
    _ = try expectByText(tree.root, .button, "Send");
    _ = try expectButton(tree.root, "Close");
    _ = try expectButton(tree.root, "New folder");
}

test "composer project row sets selected session project_path and reloads" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-project-row", .{tmp.sub_path[0..]});

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = main.initialModel();
    model.task_state_loaded = true;
    model.setStoreDir(dir);
    model.store_io = testing.io;
    try store.saveSession(&model, model.selected, testing.allocator, testing.io);

    var tree = try buildTree(arena, &model);
    _ = try expectByText(tree.root, .button, "choose a project");
    _ = try expectByText(tree.root, .button, "Local");
    _ = try expectByText(tree.root, .button, "Full access");
    _ = try expectByText(tree.root, .button, "Build");
    _ = try expectButton(tree.root, "Search");
    _ = try expectButton(tree.root, "New folder");
    try testing.expect(findByPlaceholder(tree.root, .text_field, "Workspace path") == null);

    const choose = try expectButton(tree.root, "choose a project");
    main.update(&model, tree.msgForPointer(choose.id, .up).?, &fx);
    try testing.expect(model.project_edit_active);

    tree = try buildTree(arena, &model);
    try testing.expect(findByPlaceholder(tree.root, .text_field, "Workspace path") != null);
    try testing.expect(findByText(tree.root, .button, "Local") == null);
    try testing.expect(findByText(tree.root, .button, "choose a project") == null);

    main.update(&model, .{ .project_path_edit = .{ .insert_text = "/tmp/faku-project" } }, &fx);
    try testing.expectEqualStrings("/tmp/faku-project", model.session_store[0].projectPath());
    try testing.expectEqualStrings("/tmp/faku-project", model.lastProjectPath());
    try testing.expectEqualStrings("/tmp/faku-project", model.project_label());
    try testing.expect(!model.project_is_local());

    const escape = canvas.WidgetKeyboardEvent{ .phase = .key_down, .key = "escape" };
    try testing.expectEqual(Msg.stop, main.onKey(escape).?);
    main.update(&model, main.onKey(escape).?, &fx);
    try testing.expect(!model.project_edit_active);

    tree = try buildTree(arena, &model);
    _ = try expectByText(tree.root, .button, "/tmp/faku-project");
    try testing.expect(findByText(tree.root, .button, "Local") == null);
    try testing.expect(findByText(tree.root, .button, "choose a project") == null);
    _ = try expectByText(tree.root, .button, "Full access");
    _ = try expectByText(tree.root, .button, "Medium");

    var loaded = Model{};
    loaded.setStoreDir(dir);
    loaded.store_io = testing.io;
    try testing.expectEqual(store.LoadKind.loaded, store.loadCatalog(&loaded, testing.allocator, testing.io));
    try testing.expectEqualStrings("/tmp/faku-project", loaded.session_store[0].projectPath());
    try testing.expectEqualStrings("/tmp/faku-project", loaded.lastProjectPath());
    try testing.expectEqualStrings("/tmp/faku-project", loaded.project_label());
    try testing.expect(!loaded.project_is_local());

    tree = try buildTree(arena, &loaded);
    const path_btn = try expectButton(tree.root, "/tmp/faku-project");
    try testing.expect(findByText(tree.root, .button, "Local") == null);
    main.update(&loaded, tree.msgForPointer(path_btn.id, .up).?, &fx);
    try testing.expect(loaded.project_edit_active);
    try testing.expectEqualStrings("/tmp/faku-project", loaded.project_edit());

    main.update(&loaded, .{ .project_path_edit = .clear }, &fx);
    try testing.expectEqual(@as(usize, 0), loaded.session_store[0].projectPath().len);
    try testing.expectEqual(@as(usize, 0), loaded.lastProjectPath().len);
    try testing.expect(loaded.project_is_local());
    try testing.expectEqualStrings("choose a project", loaded.project_label());

    main.update(&loaded, .stop, &fx);
    try testing.expect(!loaded.project_edit_active);

    tree = try buildTree(arena, &loaded);
    _ = try expectByText(tree.root, .button, "choose a project");
    _ = try expectByText(tree.root, .button, "Local");
    try testing.expect(findByText(tree.root, .button, "/tmp/faku-project") == null);

    var cleared = Model{};
    cleared.setStoreDir(dir);
    cleared.store_io = testing.io;
    try testing.expectEqual(store.LoadKind.loaded, store.loadCatalog(&cleared, testing.allocator, testing.io));
    try testing.expectEqual(@as(usize, 0), cleared.session_store[0].projectPath().len);
    try testing.expectEqual(@as(usize, 0), cleared.lastProjectPath().len);
    try testing.expect(cleared.project_is_local());

    const inherited = cleared.addSession("untitled next", .fx);
    try testing.expectEqual(@as(usize, 0), cleared.sessionById(inherited).?.projectPath().len);
}

fn expectContextProgress(widget: canvas.Widget, expected: f32) !canvas.Widget {
    const progress = findByText(widget, .progress, "Context usage") orelse {
        std.debug.print("no progress labeled Context usage\n", .{});
        dumpTexts(widget, 0);
        return error.WidgetNotFound;
    };
    try testing.expectApproxEqAbs(expected, progress.value, 0.0001);
    return progress;
}

test "ACP usage_update fills the composer progress; missing usage stays empty" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-context-usage", .{tmp.sub_path[0..]});

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
    const id = model.addSession("usage circle", .fx);
    model.selected = id;
    try store.saveSession(&model, id, testing.allocator, testing.io);

    var tree = try buildTree(arena, &model);
    _ = try expectContextProgress(tree.root, 0);
    _ = try expectByText(tree.root, .button, "choose a project");
    _ = try expectByText(tree.root, .button, "Full access");
    _ = try expectByText(tree.root, .button, "Build");
    _ = try expectButton(tree.root, "New folder");

    main.update(&model, .{ .draft_edit = .{ .insert_text = "first turn" } }, &fx);
    main.update(&model, .send, &fx);
    try testing.expect(model.fx_spawn_acp);
    const key = model.fx_spawn_key;

    try fx.feedLine(key, "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"sessionId\":\"fx-usage-1\"}}");
    drainEffects(&model, &fx);
    try fx.feedLine(key, "{\"output\":\"Assistant Markdown\",\"exit_code\":0,\"model\":\"provider/model-id\",\"session_id\":\"fx-usage-1\",\"steps\":1,\"tool_calls\":[]}");
    drainEffects(&model, &fx);
    try testing.expectEqual(@as(u64, 0), model.sessionById(id).?.context_used);
    try testing.expectEqual(@as(u64, 0), model.sessionById(id).?.context_size);
    try testing.expectEqual(@as(f32, 0), model.context_usage());
    tree = try buildTree(arena, &model);
    _ = try expectContextProgress(tree.root, 0);

    try fx.feedLine(key, "{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"sessionId\":\"fx-usage-1\",\"update\":{\"sessionUpdate\":\"agent_message_chunk\",\"content\":{\"type\":\"text\",\"text\":\"plain reply\"}}}}");
    drainEffects(&model, &fx);
    try testing.expectEqual(@as(f32, 0), model.context_usage());
    try testing.expect(std.mem.indexOf(u8, lastAssistant(&model), "plain reply") != null);
    try testing.expect(std.mem.indexOf(u8, lastAssistant(&model), "usage_update") == null);

    try fx.feedLine(key, "{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"sessionId\":\"fx-usage-1\",\"update\":{\"sessionUpdate\":\"usage_update\",\"used\":53000,\"size\":200000}}}");
    drainEffects(&model, &fx);
    try testing.expectEqual(@as(u64, 53000), model.sessionById(id).?.context_used);
    try testing.expectEqual(@as(u64, 200000), model.sessionById(id).?.context_size);
    try testing.expectApproxEqAbs(@as(f32, 0.265), model.context_usage(), 0.0001);
    try testing.expect(std.mem.indexOf(u8, lastAssistant(&model), "53000") == null);

    tree = try buildTree(arena, &model);
    _ = try expectContextProgress(tree.root, 0.265);
    _ = try expectByText(tree.root, .button, "choose a project");
    _ = try expectByText(tree.root, .button, "Full access");

    try fx.feedLine(key, "{\"jsonrpc\":\"2.0\",\"id\":3,\"result\":{\"stopReason\":\"end_turn\"}}");
    drainEffects(&model, &fx);
    try testing.expect(!model.is_streaming());

    var loaded = Model{};
    loaded.setStoreDir(dir);
    loaded.store_io = testing.io;
    try testing.expectEqual(store.LoadKind.loaded, store.loadCatalog(&loaded, testing.allocator, testing.io));
    try testing.expectEqual(@as(u64, 53000), loaded.session_store[0].context_used);
    try testing.expectEqual(@as(u64, 200000), loaded.session_store[0].context_size);
    try testing.expectApproxEqAbs(@as(f32, 0.265), loaded.context_usage(), 0.0001);
    store.hydrateSession(&loaded, loaded.session_store[0].id, testing.allocator, testing.io);
    try testing.expectEqual(@as(u64, 53000), loaded.session_store[0].context_used);
    try testing.expectApproxEqAbs(@as(f32, 0.265), loaded.context_usage(), 0.0001);

    tree = try buildTree(arena, &loaded);
    _ = try expectContextProgress(tree.root, 0.265);
    _ = try expectByText(tree.root, .button, "choose a project");
    _ = try expectByText(tree.root, .button, "Build");
}
