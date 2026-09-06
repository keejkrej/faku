//! First-cut daemon `WorkspaceOperation::DiscoverSlashCommands`.
//!
//! When `WAKU_DAEMON_ADDRESS` or persisted `last_daemon_address` is
//! set and the selected session has a usable non-empty `project_path`,
//! Faku prefers hello + `discoverSlashCommands` to seed the composer
//! `/` slash-prefix card (`session.available_commands`, same list ACP
//! `available_commands_update` paints). Native 4 KiB stdin overflow /
//! sidecar failure / non-ok / unusable parse / empty `commands` fall
//! back quietly to today's ACP-only catalog — a miss must not clear a
//! good ACP list. Local `sessions.json` stays canonical. Best-effort
//! sidecar only. Fx / Cursor / Grok / Kimi daemon probes often miss
//! (session-scoped ACP); those stay quiet on the ACP fallback.
//!
//! `provider` is Waku `ProviderKind` camelCase (`openCode`, not Faku
//! `wireName()` `"opencode"`). `binary_override` is the probed binary
//! when Available and distinct from `defaultBinary`, else omitted.
//! Nil request-frame `sessionId` / `runtimeId`. Own `next_daemon_key`
//! band. Cancel in-flight zeros the key so a cancelled sidecar cannot
//! paint a later session. Later live ACP `available_commands_update`
//! still replace/wins.

const std = @import("std");
const native_sdk = @import("native_sdk");
const main = @import("main.zig");
const daemon_proxy = @import("daemon_proxy.zig");
const protocol = @import("protocol.zig");
const store = @import("store.zig");
const providers = @import("providers.zig");
const composer = @import("composer.zig");

const Model = main.Model;
const Effects = main.Effects;
const writeFixed = main.writeFixed;

fn cancelInFlight(model: *Model, fx: *Effects) void {
    if (model.daemon_slash_commands_key == 0) return;
    fx.cancel(model.daemon_slash_commands_key);
    clearInFlight(model);
}

fn clearInFlight(model: *Model) void {
    model.daemon_slash_commands_key = 0;
    model.daemon_slash_commands_session = 0;
    model.daemon_slash_commands_ok = false;
}

fn probePath(model: *const Model) []const u8 {
    const path = model.selectedProjectPath();
    if (path.len == 0) return "";
    const io = model.store_io orelse return "";
    if (!main.directoryExists(io, path)) return "";
    return path;
}

fn binaryOverride(model: *const Model, id: protocol.ProviderId) ?[]const u8 {
    if (!providers.isAvailable(model, id)) return null;
    const binary = providers.binaryFor(model, id);
    if (binary.len == 0) return null;
    if (std.mem.eql(u8, binary, id.defaultBinary())) return null;
    return binary;
}

fn alreadyProbedCurrent(model: *const Model) bool {
    const session = model.sessionByIdConst(model.selected) orelse return false;
    if (model.daemon_slash_commands_probe_session != session.id) return false;
    if (model.daemon_slash_commands_probe_provider != session.provider) return false;
    const path = probePath(model);
    const probed = model.daemon_slash_commands_probe_path_storage[0..model.daemon_slash_commands_probe_path_len];
    return std.mem.eql(u8, probed, path);
}

fn rememberProbe(model: *Model, session_id: u32, provider: protocol.ProviderId, path: []const u8) void {
    model.daemon_slash_commands_probe_session = session_id;
    model.daemon_slash_commands_probe_provider = provider;
    writeFixed(&model.daemon_slash_commands_probe_path_storage, &model.daemon_slash_commands_probe_path_len, path);
}

fn probeStillCurrent(model: *const Model) bool {
    if (model.daemon_slash_commands_session == 0) return false;
    if (model.daemon_slash_commands_session != model.selected) return false;
    const session = model.sessionByIdConst(model.selected) orelse return false;
    return session.id == model.daemon_slash_commands_session;
}

/// Drop an in-flight DiscoverSlashCommands sidecar. Safe when none is
/// live. Does not clear `available_commands`.
pub fn cancel(model: *Model, fx: *Effects) void {
    cancelInFlight(model, fx);
}

/// Prefer hello + `WorkspaceOperation::DiscoverSlashCommands` when a
/// daemon address is set and the selected session has a usable
/// `project_path`. Does not clear an existing ACP list. Missing
/// address / empty path / Native 4 KiB stdin overflow keep today's
/// ACP-only catalog.
pub fn refresh(model: *Model, fx: *Effects) void {
    cancelInFlight(model, fx);
    const session = model.sessionById(model.selected) orelse return;
    const cwd = probePath(model);
    if (cwd.len == 0) return;
    if (trySpawn(model, fx, session, cwd)) {
        rememberProbe(model, session.id, session.provider, cwd);
    }
}

/// One-shot when the composer `/` slash-prefix becomes active.
/// Skips when already in-flight, already probed for this
/// session/provider/path, or no daemon address is set.
pub fn maybeRefresh(model: *Model, fx: *Effects) void {
    if (composer.slashCommandPrefix(model.draft()) == null) return;
    if (store.resolveDaemonMirrorAddress(model).len == 0) return;
    if (model.daemon_slash_commands_key != 0 and model.daemon_slash_commands_session == model.selected) return;
    if (alreadyProbedCurrent(model)) return;
    refresh(model, fx);
}

fn trySpawn(model: *Model, fx: *Effects, session: *main.Session, cwd: []const u8) bool {
    const address = store.resolveDaemonMirrorAddress(model);
    if (address.len == 0) return false;

    var stdin_buf: [4096]u8 = undefined;
    const stdin = daemon_proxy.writeWorkspaceStdin(&stdin_buf, .{
        .token = model.daemonToken(),
        .operation = .{
            .discover_slash_commands = .{
                .provider = session.provider.daemonProviderKind(),
                .project_root = cwd,
                .binary_override = binaryOverride(model, session.provider),
            },
        },
    }) catch {
        rememberProbe(model, session.id, session.provider, cwd);
        return false;
    };

    const key = model.next_daemon_key;
    model.next_daemon_key += 1;
    model.daemon_slash_commands_key = key;
    model.daemon_slash_commands_session = session.id;
    model.daemon_slash_commands_ok = false;
    fx.spawn(.{
        .key = key,
        .argv = &.{ model.sidecarPath(), daemon_proxy.SUBCOMMAND, address },
        .stdin = stdin,
        .max_line_bytes = main.daemon_line_bytes,
        .on_line = Effects.lineMsg(.fx_line),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
    return true;
}

pub fn applyLine(model: *Model, fx: *Effects, line: native_sdk.EffectLine) void {
    if (line.key != model.daemon_slash_commands_key or model.daemon_slash_commands_key == 0) return;
    if (!probeStillCurrent(model)) return;
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const parsed = protocol.parseSlashCommands(arena_state.allocator(), line.line);
    if (!parsed.ok) return;
    model.daemon_slash_commands_ok = true;
    if (parsed.command_count == 0) return;
    const session = model.sessionById(model.daemon_slash_commands_session) orelse return;
    session.clearAvailableCommands();
    var i: usize = 0;
    while (i < parsed.command_count) : (i += 1) {
        const cmd = parsed.commands[i];
        session.appendAvailableCommand(cmd.name, cmd.description);
    }
    store.persistIfPossible(model, session.id, fx);
}

pub fn handleExit(model: *Model, fx: *Effects, exit: native_sdk.EffectExit) void {
    if (exit.key != model.daemon_slash_commands_key or model.daemon_slash_commands_key == 0) return;
    clearInFlight(model);
    _ = fx;
}

fn pendingSpawnKey(fx: *Effects, key: u64) ?@TypeOf(fx.pendingSpawnAt(0).?) {
    var i: usize = 0;
    while (fx.pendingSpawnAt(i)) |spawn| : (i += 1) {
        if (spawn.key == key) return spawn;
    }
    return null;
}

const slash_commands_ok_line = "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000014\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"workspace\",\"result\":{\"type\":\"slashCommands\",\"commands\":[{\"name\":\"commit\",\"description\":\"Create a commit\",\"scope\":\"Project\",\"argument_hint\":\"message\",\"template\":null},{\"name\":\"compact\",\"description\":\"Compact the conversation\",\"scope\":\"Builtin\",\"argument_hint\":null,\"template\":null}]}}}}";

const slash_commands_empty_line = "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000014\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"workspace\",\"result\":{\"type\":\"slashCommands\",\"commands\":[]}}}}";

const workspace_ack_line = "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000014\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"workspace\",\"result\":{\"type\":\"ack\"}}}}";

test "refresh with a daemon address spawns discoverSlashCommands sidecar" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/slash-discover-daemon", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    const id = model.addSession("slash daemon", .opencode);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);

    refresh(&model, &fx);
    const sidecar = pendingSpawnKey(&fx, model.daemon_slash_commands_key) orelse return error.MissingDaemonDiscoverSlashCommands;
    try std.testing.expect(daemon_proxy.isSidecarArgv(sidecar.argv));
    try std.testing.expectEqualStrings("faku", sidecar.argv[0]);
    try std.testing.expectEqualStrings(daemon_proxy.SUBCOMMAND, sidecar.argv[1]);
    try std.testing.expectEqualStrings("127.0.0.1:8787", sidecar.argv[2]);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"hello\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"workspace\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"discoverSlashCommands\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"provider\":\"openCode\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"provider\":\"opencode\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"project_root\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, project) != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "binary_override") == null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"sessionId\":\"" ++ protocol.NIL_UUID ++ "\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"runtimeId\":\"" ++ protocol.NIL_UUID ++ "\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"prompt\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"attachSession\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "amend") == null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "force") == null);
    try std.testing.expectEqual(sidecar.key, model.daemon_slash_commands_key);
    try std.testing.expectEqual(id, model.daemon_slash_commands_session);
}

test "refresh without a daemon address keeps ACP-only path" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/slash-discover-local", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    model.setSidecarPath("faku");
    const id = model.addSession("slash local", .claude);
    model.selected = id;
    if (model.sessionById(id)) |session| {
        session.setProjectPath(project);
        session.appendAvailableCommand("web", "Search the web");
    }
    try std.testing.expectEqual(@as(usize, 0), store.resolveDaemonMirrorAddress(&model).len);

    refresh(&model, &fx);
    try std.testing.expectEqual(@as(u64, 0), model.daemon_slash_commands_key);
    try std.testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
    try std.testing.expectEqual(@as(usize, 1), model.sessionById(id).?.availableCommands().len);
    try std.testing.expectEqualStrings("web", model.sessionById(id).?.availableCommands()[0].name());
}

test "DiscoverSlashCommands sidecar paints available_commands from slashCommands" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/slash-discover-fill", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    const id = model.addSession("slash fill", .claude);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);

    refresh(&model, &fx);
    const sidecar = pendingSpawnKey(&fx, model.daemon_slash_commands_key) orelse return error.MissingDaemonDiscoverSlashCommandsFill;
    applyLine(&model, &fx, .{ .key = sidecar.key, .line = "{\"type\":\"hello\"}" });
    try std.testing.expectEqual(@as(usize, 0), model.sessionById(id).?.availableCommands().len);
    applyLine(&model, &fx, .{ .key = sidecar.key, .line = workspace_ack_line });
    try std.testing.expectEqual(@as(usize, 0), model.sessionById(id).?.availableCommands().len);
    try std.testing.expect(!model.daemon_slash_commands_ok);
    applyLine(&model, &fx, .{ .key = sidecar.key, .line = slash_commands_ok_line });
    try std.testing.expect(model.daemon_slash_commands_ok);
    try std.testing.expectEqual(@as(usize, 2), model.sessionById(id).?.availableCommands().len);
    try std.testing.expectEqualStrings("commit", model.sessionById(id).?.availableCommands()[0].name());
    try std.testing.expectEqualStrings("Create a commit", model.sessionById(id).?.availableCommands()[0].description());
    try std.testing.expectEqualStrings("compact", model.sessionById(id).?.availableCommands()[1].name());
    handleExit(&model, &fx, .{ .key = sidecar.key, .reason = .exited, .code = 0 });
    try std.testing.expectEqual(@as(u64, 0), model.daemon_slash_commands_key);
    try std.testing.expectEqual(@as(usize, 2), model.sessionById(id).?.availableCommands().len);
}

test "DiscoverSlashCommands sidecar miss/overflow falls back without clearing a good ACP list" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/slash-discover-miss", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    model.setDaemonAddress("10.0.0.2:9");
    model.setSidecarPath("faku");
    const id = model.addSession("slash miss", .claude);
    model.selected = id;
    if (model.sessionById(id)) |session| {
        session.setProjectPath(project);
        session.appendAvailableCommand("web", "Search the web");
        session.appendAvailableCommand("compact", "Compact the conversation");
    }

    refresh(&model, &fx);
    const first = pendingSpawnKey(&fx, model.daemon_slash_commands_key) orelse return error.MissingDaemonDiscoverSlashCommandsMiss;
    try std.testing.expect(std.mem.indexOf(u8, first.stdin, "\"type\":\"discoverSlashCommands\"") != null);
    applyLine(&model, &fx, .{ .key = first.key, .line = workspace_ack_line });
    try std.testing.expectEqual(@as(usize, 2), model.sessionById(id).?.availableCommands().len);
    try std.testing.expectEqualStrings("web", model.sessionById(id).?.availableCommands()[0].name());
    handleExit(&model, &fx, .{ .key = first.key, .reason = .exited, .code = 1 });
    try std.testing.expectEqual(@as(u64, 0), model.daemon_slash_commands_key);
    try std.testing.expectEqual(@as(usize, 2), model.sessionById(id).?.availableCommands().len);
    try std.testing.expectEqualStrings("web", model.sessionById(id).?.availableCommands()[0].name());
    try std.testing.expectEqualStrings("compact", model.sessionById(id).?.availableCommands()[1].name());

    var tiny: [32]u8 = undefined;
    try std.testing.expectError(error.NoSpaceLeft, daemon_proxy.writeWorkspaceStdin(&tiny, .{
        .operation = .{
            .discover_slash_commands = .{
                .provider = "claude",
                .project_root = "/tmp/faku",
            },
        },
    }));
}

test "Fx provider DiscoverSlashCommands miss stays quiet and keeps ACP list" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/slash-discover-fx", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    const id = model.addSession("slash fx", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| {
        session.setProjectPath(project);
        session.appendAvailableCommand("plan", "Create a plan");
    }

    refresh(&model, &fx);
    const sidecar = pendingSpawnKey(&fx, model.daemon_slash_commands_key) orelse return error.MissingDaemonDiscoverSlashCommandsFx;
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"provider\":\"fx\"") != null);
    applyLine(&model, &fx, .{ .key = sidecar.key, .line = slash_commands_empty_line });
    try std.testing.expect(model.daemon_slash_commands_ok);
    try std.testing.expectEqual(@as(usize, 1), model.sessionById(id).?.availableCommands().len);
    try std.testing.expectEqualStrings("plan", model.sessionById(id).?.availableCommands()[0].name());
    handleExit(&model, &fx, .{ .key = sidecar.key, .reason = .exited, .code = 0 });
    try std.testing.expectEqual(@as(u64, 0), model.daemon_slash_commands_key);
    try std.testing.expectEqual(@as(usize, 1), model.sessionById(id).?.availableCommands().len);
    try std.testing.expectEqualStrings("plan", model.sessionById(id).?.availableCommands()[0].name());
    try std.testing.expectEqual(@as(usize, 0), model.window_status_len);
}

test "maybeRefresh on slash prefix spawns once; cancel zeros the key so a cancelled sidecar cannot paint" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/slash-discover-maybe", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    const id = model.addSession("slash maybe", .pi);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);
    model.draft_buffer.set("/");

    maybeRefresh(&model, &fx);
    const first = pendingSpawnKey(&fx, model.daemon_slash_commands_key) orelse return error.MissingDaemonDiscoverSlashCommandsMaybe;
    try std.testing.expect(std.mem.indexOf(u8, first.stdin, "\"provider\":\"pi\"") != null);
    const key = first.key;
    maybeRefresh(&model, &fx);
    try std.testing.expectEqual(key, model.daemon_slash_commands_key);

    cancel(&model, &fx);
    try std.testing.expectEqual(@as(u64, 0), model.daemon_slash_commands_key);
    applyLine(&model, &fx, .{ .key = key, .line = slash_commands_ok_line });
    try std.testing.expectEqual(@as(usize, 0), model.sessionById(id).?.availableCommands().len);
}

test "fx Available distinct binary_override is included; defaultBinary is omitted" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/slash-discover-override", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    model.fx_available = true;
    model.setFxPath("/home/user/.fx/bin/fx");
    const id = model.addSession("slash override", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);

    refresh(&model, &fx);
    const sidecar = pendingSpawnKey(&fx, model.daemon_slash_commands_key) orelse return error.MissingDaemonDiscoverSlashCommandsOverride;
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"binary_override\":\"/home/user/.fx/bin/fx\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"provider\":\"fx\"") != null);
}
