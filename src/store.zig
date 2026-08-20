//! Local session catalog + turns. This is not the Waku daemon.
//!
//! Files live in Native's per-app data directory (`native_sdk.app_dirs` `.data`),
//! not a daemon socket and not `~/.waku`:
//!   Linux:  $XDG_DATA_HOME/faku or ~/.local/share/faku
//!   macOS:  ~/Library/Application Support/faku
//!
//! One JSON document `sessions.json`. Catalog load copies only session
//! skeletons (id, title, provider, untitled, has_started) — no transcripts.
//! Selecting a session hydrates its turns. Save is merge-only (never deletes).
//! `removeSession` is the only delete. Refuses to write until a successful
//! load (`task_state_loaded`), same guard as waku-client.

const std = @import("std");
const native_sdk = @import("native_sdk");
const main = @import("main.zig");
const protocol = @import("protocol.zig");

const Model = main.Model;
const Role = main.Role;
const Provider = main.Provider;

pub const catalog_name = "sessions.json";
pub const app_store_name = "faku";
pub const format_version: u32 = 1;
pub const max_document_bytes: usize = 16 * 1024 * 1024;

pub const LoadKind = enum { loaded, missing, failed };

pub const SaveError = error{
    TaskStateNotLoaded,
    NoStoreDir,
    NoSpaceLeft,
    OutOfMemory,
    Corrupt,
} || std.Io.Dir.ReadError || std.Io.Dir.WriteError || std.Io.Dir.StatError || std.Io.Dir.CreateError;

pub fn resolveDefaultDir(home: []const u8, xdg_data_home: ?[]const u8, buf: []u8) ?[]const u8 {
    return native_sdk.app_dirs.resolveOne(
        .{ .name = app_store_name },
        native_sdk.app_dirs.currentPlatform(),
        .{ .home = home, .xdg_data_home = xdg_data_home },
        .data,
        buf,
    ) catch null;
}

pub fn catalogPath(dir: []const u8, buf: []u8) ?[]const u8 {
    if (dir.len == 0) return null;
    return std.fmt.bufPrint(buf, "{s}{s}{s}", .{ dir, std.fs.path.sep_str, catalog_name }) catch null;
}

/// Bind Native's user-data dir and attempt a catalog load. Missing file keeps
/// the demo rows and still marks the catalog loaded (first-run may create the
/// store). Corrupt/unreadable files keep the demos and refuse later saves.
pub fn boot(model: *Model, allocator: std.mem.Allocator, io: std.Io) LoadKind {
    model.store_io = io;
    return switch (loadCatalog(model, allocator, io)) {
        .loaded => {
            hydrateSession(model, model.selected, allocator, io);
            return .loaded;
        },
        .missing => {
            model.task_state_loaded = true;
            return .missing;
        },
        .failed => {
            model.task_state_loaded = false;
            return .failed;
        },
    };
}

pub fn bindDefaultDir(model: *Model, home: []const u8, xdg_data_home: ?[]const u8) void {
    var buf: [main.max_store_dir]u8 = undefined;
    if (resolveDefaultDir(home, xdg_data_home, &buf)) |dir| {
        model.setStoreDir(dir);
    }
}

pub fn loadCatalog(model: *Model, allocator: std.mem.Allocator, io: std.Io) LoadKind {
    const dir = model.storeDir();
    if (dir.len == 0) return .missing;

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = catalogPath(dir, &path_buf) orelse return .failed;
    const bytes = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(max_document_bytes)) catch |err| {
        return if (err == error.FileNotFound) .missing else .failed;
    };
    defer allocator.free(bytes);

    applyCatalog(model, allocator, bytes) catch return .failed;
    model.task_state_loaded = true;
    return .loaded;
}

pub fn hydrateSession(model: *Model, session_id: u32, allocator: std.mem.Allocator, io: std.Io) void {
    const session = model.sessionById(session_id) orelse return;
    if (session.detail_loaded) return;

    const dir = model.storeDir();
    if (dir.len == 0) {
        session.detail_loaded = true;
        return;
    }

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = catalogPath(dir, &path_buf) orelse return;
    const bytes = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(max_document_bytes)) catch return;
    defer allocator.free(bytes);

    applyTurns(model, allocator, bytes, session_id) catch return;
    if (model.sessionById(session_id)) |loaded| loaded.detail_loaded = true;
}

pub fn saveSession(model: *const Model, session_id: u32, allocator: std.mem.Allocator, io: std.Io) SaveError!void {
    if (!model.task_state_loaded) return error.TaskStateNotLoaded;
    const dir = model.storeDir();
    if (dir.len == 0) return error.NoStoreDir;
    const session = model.sessionByIdConst(session_id) orelse return;
    if (!session.hasStarted()) return;

    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var document = readDocument(arena, io, dir) catch |err| switch (err) {
        error.FileNotFound => Document.empty(model),
        else => return error.Corrupt,
    };
    upsertSession(&document, arena, model, session_id) catch return error.OutOfMemory;
    document.selected = model.selected;
    document.next_id = model.next_id;
    document.next_turn_id = model.next_turn_id;
    try writeDocument(allocator, io, dir, document);
}

/// Merge-only save of every started session. Used by tests and first persist
/// of a selected session after a successful load.
pub fn saveStartedSessions(model: *const Model, allocator: std.mem.Allocator, io: std.Io) SaveError!void {
    if (!model.task_state_loaded) return error.TaskStateNotLoaded;
    for (model.sessions()) |session| {
        if (session.hasStarted()) try saveSession(model, session.id, allocator, io);
    }
}

pub fn removeSession(model: *Model, session_id: u32, allocator: std.mem.Allocator, io: std.Io) SaveError!void {
    if (!model.task_state_loaded) return error.TaskStateNotLoaded;
    const dir = model.storeDir();
    if (dir.len == 0) return error.NoStoreDir;

    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var document = readDocument(arena, io, dir) catch |err| switch (err) {
        error.FileNotFound => Document.empty(model),
        else => return error.Corrupt,
    };
    dropStoredSession(&document, session_id);
    if (document.selected == session_id) {
        document.selected = if (document.sessions.len > 0) document.sessions[0].id else 0;
    }
    try writeDocument(allocator, io, dir, document);
    model.dropSession(session_id);
}

pub fn persistIfPossible(model: *Model, session_id: u32) void {
    const io = model.store_io orelse return;
    saveSession(model, session_id, std.heap.page_allocator, io) catch {};
}

pub fn hydrateIfPossible(model: *Model, session_id: u32) void {
    const io = model.store_io orelse return;
    hydrateSession(model, session_id, std.heap.page_allocator, io);
}

const StoredTurn = struct {
    id: u32,
    role: Role,
    body: []const u8,
};

const StoredSession = struct {
    id: u32,
    title: []const u8,
    provider: Provider,
    untitled: bool,
    has_started: bool,
    turns: []StoredTurn,
};

const Document = struct {
    version: u32 = format_version,
    selected: u32 = 0,
    next_id: u32 = 1,
    next_turn_id: u32 = 1,
    sessions: []StoredSession = &.{},

    fn empty(model: *const Model) Document {
        return .{
            .selected = model.selected,
            .next_id = model.next_id,
            .next_turn_id = model.next_turn_id,
            .sessions = &.{},
        };
    }
};

fn applyCatalog(model: *Model, allocator: std.mem.Allocator, bytes: []const u8) !void {
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const document = try parseDocument(arena_state.allocator(), bytes);

    model.clearSessions();
    model.next_id = document.next_id;
    model.next_turn_id = document.next_turn_id;
    for (document.sessions) |stored| {
        model.restoreSession(stored.id, stored.title, stored.provider, stored.untitled, stored.has_started);
    }
    if (model.sessionById(document.selected) != null) {
        model.selected = document.selected;
    } else if (model.session_count > 0) {
        model.selected = model.session_store[0].id;
    }
}

fn applyTurns(model: *Model, allocator: std.mem.Allocator, bytes: []const u8, session_id: u32) !void {
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const document = try parseDocument(arena_state.allocator(), bytes);
    const stored = findStored(document, session_id) orelse return;
    model.dropTurnsForSession(session_id);
    for (stored.turns) |turn| {
        model.restoreTurn(turn.id, session_id, turn.role, turn.body);
    }
}

fn findStored(document: Document, id: u32) ?*StoredSession {
    for (document.sessions) |*session| {
        if (session.id == id) return session;
    }
    return null;
}

fn upsertSession(document: *Document, arena: std.mem.Allocator, model: *const Model, session_id: u32) !void {
    const live = model.sessionByIdConst(session_id) orelse return;
    const incoming = try snapshotSession(arena, model, live);
    if (findStored(document.*, session_id)) |existing| {
        existing.title = incoming.title;
        existing.provider = incoming.provider;
        existing.untitled = incoming.untitled;
        existing.has_started = incoming.has_started;
        if (live.detail_loaded) existing.turns = incoming.turns;
        return;
    }
    const next = try arena.alloc(StoredSession, document.sessions.len + 1);
    @memcpy(next[0..document.sessions.len], document.sessions);
    next[document.sessions.len] = incoming;
    document.sessions = next;
}

fn dropStoredSession(document: *Document, session_id: u32) void {
    var kept: usize = 0;
    for (document.sessions) |session| {
        if (session.id == session_id) continue;
        document.sessions[kept] = session;
        kept += 1;
    }
    document.sessions = document.sessions[0..kept];
}

fn snapshotSession(arena: std.mem.Allocator, model: *const Model, session: *const main.Session) !StoredSession {
    var turns: std.ArrayList(StoredTurn) = .empty;
    if (session.detail_loaded) {
        for (model.turn_store[0..model.turn_count]) |turn| {
            if (turn.session_id != session.id) continue;
            try turns.append(arena, .{
                .id = turn.id,
                .role = turn.role,
                .body = try arena.dupe(u8, turn.text()),
            });
        }
    }
    return .{
        .id = session.id,
        .title = try arena.dupe(u8, session.title()),
        .provider = session.provider,
        .untitled = session.untitled,
        .has_started = session.hasStarted(),
        .turns = try turns.toOwnedSlice(arena),
    };
}

fn readDocument(arena: std.mem.Allocator, io: std.Io, dir: []const u8) !Document {
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = catalogPath(dir, &path_buf) orelse return error.NoSpaceLeft;
    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, path, arena, .limited(max_document_bytes));
    return parseDocument(arena, bytes);
}

fn parseDocument(arena: std.mem.Allocator, bytes: []const u8) !Document {
    const root = std.json.parseFromSliceLeaky(std.json.Value, arena, bytes, .{}) catch return error.Corrupt;
    const obj = switch (root) {
        .object => |o| o,
        else => return error.Corrupt,
    };
    const version = jsonUint(obj.get("version")) orelse return error.Corrupt;
    if (version != format_version) return error.Corrupt;

    const sessions_val = obj.get("sessions") orelse return error.Corrupt;
    const sessions_arr = switch (sessions_val) {
        .array => |a| a,
        else => return error.Corrupt,
    };

    var sessions: std.ArrayList(StoredSession) = .empty;
    for (sessions_arr.items) |item| {
        try sessions.append(arena, try parseSession(arena, item));
    }

    return .{
        .version = version,
        .selected = jsonUint(obj.get("selected")) orelse 0,
        .next_id = jsonUint(obj.get("next_id")) orelse 1,
        .next_turn_id = jsonUint(obj.get("next_turn_id")) orelse 1,
        .sessions = try sessions.toOwnedSlice(arena),
    };
}

fn parseSession(arena: std.mem.Allocator, value: std.json.Value) !StoredSession {
    const obj = switch (value) {
        .object => |o| o,
        else => return error.Corrupt,
    };
    const id = jsonUint(obj.get("id")) orelse return error.Corrupt;
    const title = jsonString(obj.get("title")) orelse return error.Corrupt;
    const provider_name = jsonString(obj.get("provider")) orelse return error.Corrupt;
    const provider = protocol.ProviderId.fromWire(provider_name) orelse return error.Corrupt;
    const untitled = jsonBool(obj.get("untitled")) orelse false;
    const has_started = jsonBool(obj.get("has_started")) orelse false;

    var turns: std.ArrayList(StoredTurn) = .empty;
    if (obj.get("turns")) |turns_val| {
        const turns_arr = switch (turns_val) {
            .array => |a| a,
            else => return error.Corrupt,
        };
        for (turns_arr.items) |item| {
            try turns.append(arena, try parseTurn(item));
        }
    }

    return .{
        .id = id,
        .title = title,
        .provider = provider,
        .untitled = untitled,
        .has_started = has_started,
        .turns = try turns.toOwnedSlice(arena),
    };
}

fn parseTurn(value: std.json.Value) !StoredTurn {
    const obj = switch (value) {
        .object => |o| o,
        else => return error.Corrupt,
    };
    const id = jsonUint(obj.get("id")) orelse return error.Corrupt;
    const role_name = jsonString(obj.get("role")) orelse return error.Corrupt;
    const role = roleFromWire(role_name) orelse return error.Corrupt;
    const body = jsonString(obj.get("body")) orelse return error.Corrupt;
    return .{ .id = id, .role = role, .body = body };
}

fn jsonUint(value: ?std.json.Value) ?u32 {
    const item = value orelse return null;
    return switch (item) {
        .integer => |n| if (n >= 0 and n <= std.math.maxInt(u32)) @intCast(n) else null,
        else => null,
    };
}

fn jsonString(value: ?std.json.Value) ?[]const u8 {
    const item = value orelse return null;
    return switch (item) {
        .string => |s| s,
        else => null,
    };
}

fn jsonBool(value: ?std.json.Value) ?bool {
    const item = value orelse return null;
    return switch (item) {
        .bool => |b| b,
        else => null,
    };
}

fn roleFromWire(name: []const u8) ?Role {
    if (std.mem.eql(u8, name, "user")) return .user;
    if (std.mem.eql(u8, name, "assistant")) return .assistant;
    if (std.mem.eql(u8, name, "tool")) return .tool;
    return null;
}

fn roleWire(role: Role) []const u8 {
    return switch (role) {
        .user => "user",
        .assistant => "assistant",
        .tool => "tool",
    };
}

fn writeDocument(allocator: std.mem.Allocator, io: std.Io, dir: []const u8, document: Document) !void {
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = catalogPath(dir, &path_buf) orelse return error.NoSpaceLeft;
    const bytes = try encodeDocument(allocator, document);
    defer allocator.free(bytes);
    try atomicWrite(io, path, bytes);
}

fn encodeDocument(allocator: std.mem.Allocator, document: Document) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    try out.appendSlice(allocator, "{\"version\":");
    try appendUint(&out, allocator, document.version);
    try out.appendSlice(allocator, ",\"selected\":");
    try appendUint(&out, allocator, document.selected);
    try out.appendSlice(allocator, ",\"next_id\":");
    try appendUint(&out, allocator, document.next_id);
    try out.appendSlice(allocator, ",\"next_turn_id\":");
    try appendUint(&out, allocator, document.next_turn_id);
    try out.appendSlice(allocator, ",\"sessions\":[");
    for (document.sessions, 0..) |session, i| {
        if (i != 0) try out.append(allocator, ',');
        try appendSession(&out, allocator, session);
    }
    try out.appendSlice(allocator, "]}");
    return out.toOwnedSlice(allocator);
}

fn appendSession(out: *std.ArrayList(u8), allocator: std.mem.Allocator, session: StoredSession) !void {
    try out.appendSlice(allocator, "{\"id\":");
    try appendUint(out, allocator, session.id);
    try out.appendSlice(allocator, ",\"title\":");
    try appendJsonString(out, allocator, session.title);
    try out.appendSlice(allocator, ",\"provider\":");
    try appendJsonString(out, allocator, session.provider.wireName());
    try out.appendSlice(allocator, ",\"untitled\":");
    try out.appendSlice(allocator, if (session.untitled) "true" else "false");
    try out.appendSlice(allocator, ",\"has_started\":");
    try out.appendSlice(allocator, if (session.has_started) "true" else "false");
    try out.appendSlice(allocator, ",\"turns\":[");
    for (session.turns, 0..) |turn, i| {
        if (i != 0) try out.append(allocator, ',');
        try out.appendSlice(allocator, "{\"id\":");
        try appendUint(out, allocator, turn.id);
        try out.appendSlice(allocator, ",\"role\":");
        try appendJsonString(out, allocator, roleWire(turn.role));
        try out.appendSlice(allocator, ",\"body\":");
        try appendJsonString(out, allocator, turn.body);
        try out.append(allocator, '}');
    }
    try out.appendSlice(allocator, "]}");
}

fn appendUint(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: u32) !void {
    var num: [10]u8 = undefined;
    const piece = std.fmt.bufPrint(&num, "{d}", .{value}) catch return error.NoSpaceLeft;
    try out.appendSlice(allocator, piece);
}

fn appendJsonString(out: *std.ArrayList(u8), allocator: std.mem.Allocator, text: []const u8) !void {
    try out.append(allocator, '"');
    for (text) |c| {
        switch (c) {
            '"' => try out.appendSlice(allocator, "\\\""),
            '\\' => try out.appendSlice(allocator, "\\\\"),
            '\n' => try out.appendSlice(allocator, "\\n"),
            '\r' => try out.appendSlice(allocator, "\\r"),
            '\t' => try out.appendSlice(allocator, "\\t"),
            else => {
                if (c < 0x20) {
                    var hex: [6]u8 = undefined;
                    const piece = std.fmt.bufPrint(&hex, "\\u{x:0>4}", .{c}) catch return error.NoSpaceLeft;
                    try out.appendSlice(allocator, piece);
                } else {
                    try out.append(allocator, c);
                }
            },
        }
    }
    try out.append(allocator, '"');
}

fn atomicWrite(io: std.Io, path: []const u8, bytes: []const u8) !void {
    const cwd = std.Io.Dir.cwd();
    var atomic = try cwd.createFileAtomic(io, path, .{ .make_path = true, .replace = true });
    defer atomic.deinit(io);
    try atomic.file.writePositionalAll(io, bytes, 0);
    try atomic.file.sync(io);
    try atomic.replace(io);
}

fn testStoreDir(tmp: *const std.testing.TmpDir, buffer: []u8) ![]const u8 {
    return std.fmt.bufPrint(buffer, ".zig-cache/tmp/{s}/faku-store", .{tmp.sub_path[0..]});
}

fn writeRaw(io: std.Io, dir: []const u8, bytes: []const u8) !void {
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = catalogPath(dir, &path_buf) orelse return error.NoSpaceLeft;
    const cwd = std.Io.Dir.cwd();
    cwd.createDirPath(io, dir) catch {};
    try cwd.writeFile(io, .{ .sub_path = path, .data = bytes });
}

fn seedTwoSessions(model: *Model) struct { a: u32, b: u32 } {
    const a = model.addSession("port waku to zig", .fx);
    _ = model.appendTurn(a, .user, "replace the GPUI desktop");
    _ = model.appendTurn(a, .assistant, "fx-first demo shell");
    const b = model.addSession("fix auth listener", .claude);
    _ = model.appendTurn(b, .user, "the auth listener drops the first event");
    _ = model.appendTurn(b, .assistant, "inspect the reconnect path");
    _ = model.appendTurn(b, .tool, "read src/auth/listener.ts");
    model.selected = a;
    return .{ .a = a, .b = b };
}

test "default store path is Native app_dirs data, not the Waku daemon" {
    var buf: [256]u8 = undefined;
    const linux = try native_sdk.app_dirs.resolveOne(
        .{ .name = app_store_name },
        .linux,
        .{ .home = "/home/alice" },
        .data,
        &buf,
    );
    try std.testing.expectEqualStrings("/home/alice/.local/share/faku", linux);
    try std.testing.expect(std.mem.indexOf(u8, linux, ".waku") == null);

    const macos = try native_sdk.app_dirs.resolveOne(
        .{ .name = app_store_name },
        .macos,
        .{ .home = "/Users/alice" },
        .data,
        &buf,
    );
    try std.testing.expectEqualStrings("/Users/alice/Library/Application Support/faku", macos);
}

test "save + load round-trips two sessions and hydrate restores turns" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try testStoreDir(&tmp, &dir_buf);
    const io = testing.io;
    const allocator = testing.allocator;

    var source = Model{};
    source.task_state_loaded = true;
    source.setStoreDir(dir);
    source.store_io = io;
    const ids = seedTwoSessions(&source);
    try saveSession(&source, ids.a, allocator, io);
    try saveSession(&source, ids.b, allocator, io);

    var loaded = Model{};
    loaded.setStoreDir(dir);
    loaded.store_io = io;
    try testing.expectEqual(LoadKind.loaded, loadCatalog(&loaded, allocator, io));
    try testing.expectEqual(@as(u32, 2), loaded.session_count);
    try testing.expectEqual(ids.a, loaded.session_store[0].id);
    try testing.expectEqual(ids.b, loaded.session_store[1].id);
    try testing.expectEqualStrings("port waku to zig", loaded.session_store[0].title());
    try testing.expectEqualStrings("fix auth listener", loaded.session_store[1].title());
    try testing.expectEqual(Provider.fx, loaded.session_store[0].provider);
    try testing.expectEqual(Provider.claude, loaded.session_store[1].provider);
    try testing.expectEqual(@as(u32, 0), loaded.turn_count);
    try testing.expect(!loaded.session_store[0].detail_loaded);
    try testing.expect(!loaded.session_store[1].detail_loaded);

    hydrateSession(&loaded, ids.a, allocator, io);
    try testing.expect(loaded.session_store[0].detail_loaded);
    try testing.expectEqual(@as(u32, 2), loaded.turn_count);
    try testing.expectEqualStrings("replace the GPUI desktop", loaded.turn_store[0].text());
    try testing.expectEqualStrings("fx-first demo shell", loaded.turn_store[1].text());

    hydrateSession(&loaded, ids.b, allocator, io);
    try testing.expect(loaded.session_store[1].detail_loaded);
    try testing.expectEqual(@as(u32, 5), loaded.turn_count);
    try testing.expectEqualStrings("the auth listener drops the first event", loaded.turn_store[2].text());
    try testing.expectEqual(Role.tool, loaded.turn_store[4].role);
    try testing.expectEqualStrings("read src/auth/listener.ts", loaded.turn_store[4].text());
}

test "missing store keeps demos; corrupt store is not overwritten" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try testStoreDir(&tmp, &dir_buf);
    const io = testing.io;
    const allocator = testing.allocator;

    var missing = main.initialModel();
    missing.setStoreDir(dir);
    missing.store_io = io;
    try testing.expectEqual(LoadKind.missing, boot(&missing, allocator, io));
    try testing.expectEqual(@as(u32, 2), missing.session_count);
    try testing.expectEqualStrings("port waku to zig", missing.selected_title());
    try testing.expect(missing.task_state_loaded);

    try writeRaw(io, dir, "{not json");
    var corrupt = main.initialModel();
    corrupt.setStoreDir(dir);
    corrupt.store_io = io;
    try testing.expectEqual(LoadKind.failed, boot(&corrupt, allocator, io));
    try testing.expectEqual(@as(u32, 2), corrupt.session_count);
    try testing.expect(!corrupt.task_state_loaded);
    try testing.expectError(error.TaskStateNotLoaded, saveSession(&corrupt, corrupt.selected, allocator, io));

    var path_buf: [256]u8 = undefined;
    const leftover = try std.Io.Dir.cwd().readFileAlloc(io, catalogPath(dir, &path_buf).?, allocator, .limited(64));
    defer allocator.free(leftover);
    try testing.expectEqualStrings("{not json", leftover);
}

test "new session is skipped until first content; save is merge-only" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try testStoreDir(&tmp, &dir_buf);
    const io = testing.io;
    const allocator = testing.allocator;

    var model = Model{};
    model.task_state_loaded = true;
    model.setStoreDir(dir);
    const first = model.addSession("kept", .fx);
    _ = model.appendTurn(first, .user, "hello");
    try saveSession(&model, first, allocator, io);

    const untitled = model.addSession("untitled", .fx);
    if (model.sessionById(untitled)) |session| session.untitled = true;
    try saveSession(&model, untitled, allocator, io);

    var loaded = Model{};
    loaded.setStoreDir(dir);
    try testing.expectEqual(LoadKind.loaded, loadCatalog(&loaded, allocator, io));
    try testing.expectEqual(@as(u32, 1), loaded.session_count);
    try testing.expectEqual(first, loaded.session_store[0].id);

    if (model.sessionById(untitled)) |session| {
        writeTitle(session, "after first send");
        session.untitled = false;
    }
    _ = model.appendTurn(untitled, .user, "real content");
    try saveSession(&model, untitled, allocator, io);

    var merged = Model{};
    merged.setStoreDir(dir);
    try testing.expectEqual(LoadKind.loaded, loadCatalog(&merged, allocator, io));
    try testing.expectEqual(@as(u32, 2), merged.session_count);
    try testing.expectEqual(first, merged.session_store[0].id);
    try testing.expectEqual(untitled, merged.session_store[1].id);
}

fn writeTitle(session: *main.Session, title: []const u8) void {
    const take = @min(session.title_storage.len, title.len);
    @memcpy(session.title_storage[0..take], title[0..take]);
    session.title_len = take;
}
