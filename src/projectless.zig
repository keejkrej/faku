//! First-cut daemon `WorkspaceOperation::CreateProjectlessWorkspace`
//! and `WorkspaceOperation::MigrateProjectlessWorkspace`.
//!
//! When New Task has no usable ordinary project — empty
//! `last_project_path`, or the selected session's `project_path` is
//! already a projectless path under `~/.waku/projects` (and
//! legacy `~/.waku/<YYYY-MM-DD>/…` / bare `~/.waku`) — Faku prefers
//! hello + `createProjectlessWorkspace` `{ prompt: null }` when
//! `WAKU_DAEMON_ADDRESS` or persisted `last_daemon_address` is set.
//! Ok nested `projectlessWorkspace.cwd` becomes the new session
//! cwd and `last_project_path`. Native 4 KiB stdin overflow /
//! sidecar failure / non-ok / unusable parse / empty cwd fall back
//! locally (mkdir under `~/.waku/projects/<YYYY-MM-DD>/<slug>`;
//! null prompt → `new-chat`, numbered candidates if taken). Missing
//! home / mkdir failure keeps today's empty-or-copied
//! `last_project_path` rather than blocking New Task. Ordinary New
//! Task with a real project path still copies `last_project_path`.
//!
//! When a selected session's `project_path` still needs migration
//! (projectless but not under `~/.waku/projects` — dated legacy
//! `~/.waku/<date>/<slug>` or bare `~/.waku`) — Faku prefers hello +
//! `migrateProjectlessWorkspace` `{ path }` on session select / boot
//! when a daemon address is set. Ok nested
//! `projectlessWorkspace.cwd` paints that session's `project_path`
//! and `last_project_path`. Native 4 KiB stdin overflow / sidecar
//! failure / non-ok / unusable parse / empty cwd fall back locally
//! (rename dated legacy into `~/.waku/projects/<date>/<slug>` with
//! numbered `-2`… if taken; bare `~/.waku` allocates a fresh mkdir
//! like Create; already-under-projects is a no-op). Missing home /
//! failure must not toast-block session select. Ordinary real
//! project paths do not spawn migrate. Own `next_daemon_key` band,
//! distinct from Create. Cancel in-flight zeros the key so a
//! cancelled sidecar cannot paint a later session. Local
//! `sessions.json` stays canonical. Best-effort sidecar only.
//! Leftover: reusing an unstarted projectless draft (Waku
//! `create_projectless_session` selects the draft) is skipped this
//! cut so New Task still always creates a row. Amend/force and
//! remote `--track` stay local.

const std = @import("std");
const native_sdk = @import("native_sdk");
const main = @import("main.zig");
const daemon_proxy = @import("daemon_proxy.zig");
const protocol = @import("protocol.zig");
const store = @import("store.zig");
const persist = @import("persist.zig");

const Model = main.Model;
const Effects = main.Effects;
const writeFixed = main.writeFixed;

const default_slug = "new-chat";
const max_numbered_candidates: u32 = 100;
const ms_per_day: i64 = 86_400_000;

fn cancelInFlight(model: *Model, fx: *Effects) void {
    if (model.daemon_projectless_key == 0) return;
    fx.cancel(model.daemon_projectless_key);
    clearInFlight(model);
}

fn clearInFlight(model: *Model) void {
    model.daemon_projectless_key = 0;
    model.daemon_projectless_session = 0;
    model.daemon_projectless_ok = false;
}

fn cancelMigrateInFlight(model: *Model, fx: *Effects) void {
    if (model.daemon_migrate_projectless_key == 0) return;
    fx.cancel(model.daemon_migrate_projectless_key);
    clearMigrateInFlight(model);
}

fn clearMigrateInFlight(model: *Model) void {
    model.daemon_migrate_projectless_key = 0;
    model.daemon_migrate_projectless_session = 0;
    model.daemon_migrate_projectless_ok = false;
}

/// Drop an in-flight CreateProjectlessWorkspace sidecar. Safe when
/// none is live. Does not change `project_path`.
pub fn cancel(model: *Model, fx: *Effects) void {
    cancelInFlight(model, fx);
}

/// Drop an in-flight MigrateProjectlessWorkspace sidecar. Safe when
/// none is live. Does not change `project_path`.
pub fn cancelMigrate(model: *Model, fx: *Effects) void {
    cancelMigrateInFlight(model, fx);
}

/// True when `path` is a Waku projectless workspace: under
/// `{home}/.waku/projects`, a legacy dated `{home}/.waku/<date>/…`,
/// or bare `{home}/.waku`. `{home}/.waku/worktrees` is not.
pub fn isProjectlessPath(home: []const u8, path: []const u8) bool {
    if (home.len == 0 or path.len == 0) return false;
    const trimmed = trimTrailingSlash(path);
    if (trimmed.len == 0) return false;
    var root_buf: [main.max_project_path]u8 = undefined;
    const projects = joinHomeSuffix(home, "/.waku/projects", &root_buf) orelse return false;
    if (pathEqualsOrUnder(trimmed, projects)) return true;
    var legacy_buf: [main.max_project_path]u8 = undefined;
    const legacy = joinHomeSuffix(home, "/.waku", &legacy_buf) orelse return false;
    if (std.mem.eql(u8, trimmed, legacy)) return true;
    if (!pathEqualsOrUnder(trimmed, legacy)) return false;
    const rest = trimmed[legacy.len + 1 ..];
    const slash = std.mem.indexOfScalar(u8, rest, '/') orelse rest.len;
    return isDateComponent(rest[0..slash]);
}

/// True when `path` is projectless but not under `{home}/.waku/projects`
/// (dated legacy `{home}/.waku/<date>/<slug>` or bare `{home}/.waku`).
pub fn needsMigration(home: []const u8, path: []const u8) bool {
    if (!isProjectlessPath(home, path)) return false;
    var root_buf: [main.max_project_path]u8 = undefined;
    const projects = joinHomeSuffix(home, "/.waku/projects", &root_buf) orelse return false;
    return !pathEqualsOrUnder(trimTrailingSlash(path), projects);
}

/// After `addSession` + select: prefer hello + CreateProjectlessWorkspace
/// when a daemon address is set and this New Task should be
/// projectless. Overflow / no address uses local mkdir. `prior_project_path`
/// is the previously selected session cwd (captured before addSession).
pub fn beginForNewSession(model: *Model, fx: *Effects, prior_project_path: []const u8) void {
    cancelInFlight(model, fx);
    if (!wantsProjectlessWorkspace(model, prior_project_path)) return;
    const session = model.sessionById(model.selected) orelse return;
    if (trySpawn(model, fx, session.id)) return;
    applyLocalFallback(model, fx, session.id, false);
}

/// On session select / boot: prefer hello + MigrateProjectlessWorkspace
/// when a daemon address is set and the selected session cwd still
/// needs migration. Overflow / no address uses local rename / fresh
/// mkdir. Ordinary real project paths and already-under-projects
/// paths are a no-op.
pub fn beginMigrateForSelected(model: *Model, fx: *Effects) void {
    cancelMigrateInFlight(model, fx);
    const session = model.sessionById(model.selected) orelse return;
    const path = session.projectPath();
    if (!needsMigration(model.homeDir(), path)) return;
    if (trySpawnMigrate(model, fx, session.id, path)) return;
    applyMigrateLocalFallback(model, fx, session.id, path);
}

fn wantsProjectlessWorkspace(model: *const Model, prior_project_path: []const u8) bool {
    const home = model.homeDir();
    const last = model.lastProjectPath();
    if (isProjectlessPath(home, prior_project_path)) return true;
    if (isProjectlessPath(home, last)) return true;
    return last.len == 0;
}

fn trySpawn(model: *Model, fx: *Effects, session_id: u32) bool {
    const address = store.resolveDaemonMirrorAddress(model);
    if (address.len == 0) return false;

    var stdin_buf: [4096]u8 = undefined;
    const stdin = daemon_proxy.writeWorkspaceStdin(&stdin_buf, .{
        .token = model.daemonToken(),
        .operation = .{ .create_projectless_workspace = .{} },
    }) catch return false;

    const key = model.next_daemon_key;
    model.next_daemon_key += 1;
    model.daemon_projectless_key = key;
    model.daemon_projectless_session = session_id;
    model.daemon_projectless_ok = false;
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
    if (line.key != model.daemon_projectless_key or model.daemon_projectless_key == 0) return;
    const session_id = model.daemon_projectless_session;
    if (session_id == 0) return;
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const parsed = protocol.parseProjectlessWorkspace(arena_state.allocator(), line.line);
    if (!parsed.ok) return;
    model.daemon_projectless_ok = true;
    adoptCwd(model, fx, session_id, parsed.cwd, true);
}

pub fn handleExit(model: *Model, fx: *Effects, exit: native_sdk.EffectExit) void {
    if (exit.key != model.daemon_projectless_key or model.daemon_projectless_key == 0) return;
    const session_id = model.daemon_projectless_session;
    const ok = model.daemon_projectless_ok;
    clearInFlight(model);
    if (ok) return;
    applyLocalFallback(model, fx, session_id, true);
}

fn trySpawnMigrate(model: *Model, fx: *Effects, session_id: u32, path: []const u8) bool {
    const address = store.resolveDaemonMirrorAddress(model);
    if (address.len == 0) return false;

    var stdin_buf: [4096]u8 = undefined;
    const stdin = daemon_proxy.writeWorkspaceStdin(&stdin_buf, .{
        .token = model.daemonToken(),
        .operation = .{ .migrate_projectless_workspace = .{ .path = path } },
    }) catch return false;

    const key = model.next_daemon_key;
    model.next_daemon_key += 1;
    model.daemon_migrate_projectless_key = key;
    model.daemon_migrate_projectless_session = session_id;
    model.daemon_migrate_projectless_ok = false;
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

pub fn applyMigrateLine(model: *Model, fx: *Effects, line: native_sdk.EffectLine) void {
    if (line.key != model.daemon_migrate_projectless_key or model.daemon_migrate_projectless_key == 0) return;
    const session_id = model.daemon_migrate_projectless_session;
    if (session_id == 0) return;
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const parsed = protocol.parseProjectlessWorkspace(arena_state.allocator(), line.line);
    if (!parsed.ok) return;
    model.daemon_migrate_projectless_ok = true;
    adoptCwd(model, fx, session_id, parsed.cwd, true);
}

pub fn handleMigrateExit(model: *Model, fx: *Effects, exit: native_sdk.EffectExit) void {
    if (exit.key != model.daemon_migrate_projectless_key or model.daemon_migrate_projectless_key == 0) return;
    const session_id = model.daemon_migrate_projectless_session;
    const ok = model.daemon_migrate_projectless_ok;
    clearMigrateInFlight(model);
    if (ok) return;
    const session = model.sessionById(session_id) orelse return;
    applyMigrateLocalFallback(model, fx, session_id, session.projectPath());
}

fn applyMigrateLocalFallback(model: *Model, fx: *Effects, session_id: u32, path: []const u8) void {
    var cwd_buf: [main.max_project_path]u8 = undefined;
    const cwd = migrateLocalWorkspace(model, path, &cwd_buf) orelse return;
    adoptCwd(model, fx, session_id, cwd, true);
}

fn applyLocalFallback(model: *Model, fx: *Effects, session_id: u32, refresh: bool) void {
    var cwd_buf: [main.max_project_path]u8 = undefined;
    const cwd = createLocalWorkspace(model, &cwd_buf) orelse return;
    adoptCwd(model, fx, session_id, cwd, refresh);
}

fn adoptCwd(model: *Model, fx: *Effects, session_id: u32, cwd: []const u8, refresh: bool) void {
    const session = model.sessionById(session_id) orelse return;
    session.setProjectPath(cwd);
    if (model.selected != session_id) return;
    model.setLastProjectPath(cwd);
    if (refresh) {
        persist.persistComposerProject(model, fx);
    } else {
        store.persistSettingsIfPossible(model);
    }
}

fn createLocalWorkspace(model: *const Model, dest: []u8) ?[]const u8 {
    const io = model.store_io orelse return null;
    const home = model.homeDir();
    if (home.len == 0) return null;
    var root_buf: [main.max_project_path]u8 = undefined;
    const root = joinHomeSuffix(home, "/.waku/projects", &root_buf) orelse return null;
    std.Io.Dir.cwd().createDirPath(io, root) catch return null;
    if (!main.directoryExists(io, root)) return null;

    if (model.now_ms <= 0) return null;
    var date_buf: [10]u8 = undefined;
    const date = formatUtcDate(model.now_ms, &date_buf) orelse return null;
    var date_dir_buf: [main.max_project_path]u8 = undefined;
    const date_dir = joinPath(root, date, &date_dir_buf) orelse return null;
    std.Io.Dir.cwd().createDirPath(io, date_dir) catch return null;
    if (!main.directoryExists(io, date_dir)) return null;

    var index: u32 = 0;
    while (index < max_numbered_candidates) : (index += 1) {
        var name_buf: [32]u8 = undefined;
        const name = candidateName(index, &name_buf) orelse continue;
        var dest_buf: [main.max_project_path]u8 = undefined;
        const cwd = joinPath(date_dir, name, &dest_buf) orelse continue;
        if (main.directoryExists(io, cwd)) continue;
        std.Io.Dir.cwd().createDirPath(io, cwd) catch continue;
        if (!main.directoryExists(io, cwd)) continue;
        if (cwd.len > dest.len) return null;
        @memcpy(dest[0..cwd.len], cwd);
        return dest[0..cwd.len];
    }
    return null;
}

fn candidateName(index: u32, buf: []u8) ?[]const u8 {
    if (index == 0) return default_slug;
    return std.fmt.bufPrint(buf, "{s}-{d}", .{ default_slug, index + 1 }) catch null;
}

fn migrateLocalWorkspace(model: *const Model, path: []const u8, dest: []u8) ?[]const u8 {
    const io = model.store_io orelse return null;
    const home = model.homeDir();
    if (home.len == 0 or path.len == 0) return null;
    const trimmed = trimTrailingSlash(path);
    var root_buf: [main.max_project_path]u8 = undefined;
    const root = joinHomeSuffix(home, "/.waku/projects", &root_buf) orelse return null;
    if (pathEqualsOrUnder(trimmed, root)) {
        if (trimmed.len > dest.len) return null;
        @memcpy(dest[0..trimmed.len], trimmed);
        return dest[0..trimmed.len];
    }
    if (isBareLegacyRoot(home, trimmed)) {
        return createLocalWorkspace(model, dest);
    }
    const parts = legacyDatedParts(home, trimmed) orelse return null;
    if (!main.directoryExists(io, trimmed)) return null;

    std.Io.Dir.cwd().createDirPath(io, root) catch return null;
    if (!main.directoryExists(io, root)) return null;
    var date_dir_buf: [main.max_project_path]u8 = undefined;
    const date_dir = joinPath(root, parts.date, &date_dir_buf) orelse return null;
    std.Io.Dir.cwd().createDirPath(io, date_dir) catch return null;
    if (!main.directoryExists(io, date_dir)) return null;

    var index: u32 = 0;
    while (index < max_numbered_candidates) : (index += 1) {
        var name_buf: [main.max_project_path]u8 = undefined;
        const name = numberedName(parts.slug, index, &name_buf) orelse continue;
        var dest_buf: [main.max_project_path]u8 = undefined;
        const cwd = joinPath(date_dir, name, &dest_buf) orelse continue;
        if (main.directoryExists(io, cwd)) continue;
        if (!renamePath(io, trimmed, cwd)) continue;
        if (!main.directoryExists(io, cwd)) continue;
        if (cwd.len > dest.len) return null;
        @memcpy(dest[0..cwd.len], cwd);
        return dest[0..cwd.len];
    }
    return null;
}

fn numberedName(slug: []const u8, index: u32, buf: []u8) ?[]const u8 {
    if (slug.len == 0) return null;
    if (index == 0) return slug;
    return std.fmt.bufPrint(buf, "{s}-{d}", .{ slug, index + 1 }) catch null;
}

fn isBareLegacyRoot(home: []const u8, path: []const u8) bool {
    var legacy_buf: [main.max_project_path]u8 = undefined;
    const legacy = joinHomeSuffix(home, "/.waku", &legacy_buf) orelse return false;
    return std.mem.eql(u8, trimTrailingSlash(path), legacy);
}

const LegacyDatedParts = struct { date: []const u8, slug: []const u8 };

fn legacyDatedParts(home: []const u8, path: []const u8) ?LegacyDatedParts {
    var legacy_buf: [main.max_project_path]u8 = undefined;
    const legacy = joinHomeSuffix(home, "/.waku", &legacy_buf) orelse return null;
    const trimmed = trimTrailingSlash(path);
    if (!pathEqualsOrUnder(trimmed, legacy) or std.mem.eql(u8, trimmed, legacy)) return null;
    const rest = trimmed[legacy.len + 1 ..];
    const slash = std.mem.indexOfScalar(u8, rest, '/') orelse return null;
    if (std.mem.indexOfScalar(u8, rest[slash + 1 ..], '/') != null) return null;
    const date = rest[0..slash];
    const slug = rest[slash + 1 ..];
    if (!isDateComponent(date) or slug.len == 0) return null;
    return .{ .date = date, .slug = slug };
}

fn renamePath(io: std.Io, from: []const u8, to: []const u8) bool {
    const dir = std.Io.Dir.cwd();
    dir.rename(from, dir, to, io) catch return false;
    return true;
}

fn joinHomeSuffix(home: []const u8, suffix: []const u8, buf: []u8) ?[]const u8 {
    if (home.len == 0) return null;
    if (home.len + suffix.len > buf.len) return null;
    @memcpy(buf[0..home.len], home);
    @memcpy(buf[home.len..][0..suffix.len], suffix);
    return buf[0 .. home.len + suffix.len];
}

fn joinPath(parent: []const u8, name: []const u8, buf: []u8) ?[]const u8 {
    if (parent.len == 0 or name.len == 0) return null;
    if (parent.len + 1 + name.len > buf.len) return null;
    @memcpy(buf[0..parent.len], parent);
    buf[parent.len] = '/';
    @memcpy(buf[parent.len + 1 ..][0..name.len], name);
    return buf[0 .. parent.len + 1 + name.len];
}

fn trimTrailingSlash(path: []const u8) []const u8 {
    var end = path.len;
    while (end > 1 and path[end - 1] == '/') end -= 1;
    return path[0..end];
}

fn pathEqualsOrUnder(path: []const u8, root: []const u8) bool {
    if (std.mem.eql(u8, path, root)) return true;
    if (path.len <= root.len) return false;
    if (!std.mem.startsWith(u8, path, root)) return false;
    return path[root.len] == '/';
}

fn isDateComponent(value: []const u8) bool {
    if (value.len != 10) return false;
    if (value[4] != '-' or value[7] != '-') return false;
    for (value, 0..) |byte, i| {
        if (i == 4 or i == 7) continue;
        if (!std.ascii.isDigit(byte)) return false;
    }
    return true;
}

const CivilDate = struct { year: i64, month: u8, day: u8 };

fn utcYmd(ms: i64) ?CivilDate {
    const z0 = @divFloor(ms, ms_per_day);
    const z = z0 + 719468;
    const era = @divFloor(z, 146097);
    const doe = z - era * 146097;
    const yoe = @divFloor(doe - @divFloor(doe, 1460) + @divFloor(doe, 36524) - @divFloor(doe, 146096), 365);
    var year = yoe + era * 400;
    const doy = doe - (365 * yoe + @divFloor(yoe, 4) - @divFloor(yoe, 100));
    const mp = @divFloor(5 * doy + 2, 153);
    const day_i = doy - @divFloor(153 * mp + 2, 5) + 1;
    const month_i = if (mp < 10) mp + 3 else mp - 9;
    if (month_i <= 2) year += 1;
    if (day_i < 1 or day_i > 31) return null;
    if (month_i < 1 or month_i > 12) return null;
    return .{
        .year = year,
        .month = @intCast(month_i),
        .day = @intCast(day_i),
    };
}

fn formatUtcDate(ms: i64, buf: []u8) ?[]const u8 {
    const ymd = utcYmd(ms) orelse return null;
    if (ymd.year < 0 or ymd.year > 9999) return null;
    const year: u16 = @intCast(ymd.year);
    return std.fmt.bufPrint(buf, "{d:0>4}-{d:0>2}-{d:0>2}", .{ year, ymd.month, ymd.day }) catch null;
}

fn pendingSpawnKey(fx: *Effects, key: u64) ?@TypeOf(fx.pendingSpawnAt(0).?) {
    var i: usize = 0;
    while (fx.pendingSpawnAt(i)) |spawn| : (i += 1) {
        if (spawn.key == key) return spawn;
    }
    return null;
}

const projectless_ok_line = "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000014\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"workspace\",\"result\":{\"type\":\"projectlessWorkspace\",\"cwd\":\"/tmp/from-daemon/.waku/projects/2026-09-06/new-chat\"}}}}";

const workspace_ack_line = "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000014\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"workspace\",\"result\":{\"type\":\"ack\"}}}}";

test "isProjectlessPath recognizes ~/.waku/projects, legacy dated, and bare ~/.waku" {
    const home = "/home/me";
    try std.testing.expect(isProjectlessPath(home, "/home/me/.waku/projects/2026-09-06/new-chat"));
    try std.testing.expect(isProjectlessPath(home, "/home/me/.waku/projects"));
    try std.testing.expect(isProjectlessPath(home, "/home/me/.waku/2026-09-06/new-chat"));
    try std.testing.expect(isProjectlessPath(home, "/home/me/.waku"));
    try std.testing.expect(!isProjectlessPath(home, "/home/me/.waku/worktrees/abc/slug"));
    try std.testing.expect(!isProjectlessPath(home, "/tmp/faku"));
    try std.testing.expect(!isProjectlessPath(home, ""));
    try std.testing.expect(!isProjectlessPath("", "/home/me/.waku/projects/2026-09-06/new-chat"));
    try std.testing.expect(!needsMigration(home, "/home/me/.waku/projects/2026-09-06/new-chat"));
    try std.testing.expect(!needsMigration(home, "/home/me/.waku/projects"));
    try std.testing.expect(needsMigration(home, "/home/me/.waku/2026-09-06/new-chat"));
    try std.testing.expect(needsMigration(home, "/home/me/.waku"));
    try std.testing.expect(!needsMigration(home, "/home/me/.waku/worktrees/abc/slug"));
    try std.testing.expect(!needsMigration(home, "/tmp/faku"));
    try std.testing.expect(!needsMigration(home, ""));
}

test "New Task with a daemon address spawns createProjectlessWorkspace" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = std.testing.io;
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    const id = model.addSession("untitled", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.untitled = true;

    beginForNewSession(&model, &fx, "");
    const sidecar = pendingSpawnKey(&fx, model.daemon_projectless_key) orelse return error.MissingDaemonCreateProjectless;
    try std.testing.expect(daemon_proxy.isSidecarArgv(sidecar.argv));
    try std.testing.expectEqualStrings("faku", sidecar.argv[0]);
    try std.testing.expectEqualStrings(daemon_proxy.SUBCOMMAND, sidecar.argv[1]);
    try std.testing.expectEqualStrings("127.0.0.1:8787", sidecar.argv[2]);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"hello\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"workspace\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"createProjectlessWorkspace\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"prompt\":null") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"sessionId\":\"" ++ protocol.NIL_UUID ++ "\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"runtimeId\":\"" ++ protocol.NIL_UUID ++ "\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"prompt\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"attachSession\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "amend") == null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "force") == null);
    try std.testing.expectEqual(sidecar.key, model.daemon_projectless_key);
    try std.testing.expectEqual(id, model.daemon_projectless_session);
}

test "CreateProjectlessWorkspace sidecar paints cwd from projectlessWorkspace" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = std.testing.io;
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    const id = model.addSession("untitled", .fx);
    model.selected = id;

    beginForNewSession(&model, &fx, "");
    const sidecar = pendingSpawnKey(&fx, model.daemon_projectless_key) orelse return error.MissingDaemonCreateProjectlessFill;
    applyLine(&model, &fx, .{ .key = sidecar.key, .line = "{\"type\":\"hello\"}" });
    try std.testing.expectEqual(@as(usize, 0), model.sessionById(id).?.projectPath().len);
    applyLine(&model, &fx, .{ .key = sidecar.key, .line = workspace_ack_line });
    try std.testing.expectEqual(@as(usize, 0), model.sessionById(id).?.projectPath().len);
    try std.testing.expect(!model.daemon_projectless_ok);
    applyLine(&model, &fx, .{ .key = sidecar.key, .line = projectless_ok_line });
    try std.testing.expect(model.daemon_projectless_ok);
    try std.testing.expectEqualStrings("/tmp/from-daemon/.waku/projects/2026-09-06/new-chat", model.sessionById(id).?.projectPath());
    try std.testing.expectEqualStrings("/tmp/from-daemon/.waku/projects/2026-09-06/new-chat", model.lastProjectPath());
    handleExit(&model, &fx, .{ .key = sidecar.key, .reason = .exited, .code = 0 });
    try std.testing.expectEqual(@as(u64, 0), model.daemon_projectless_key);
    try std.testing.expectEqualStrings("/tmp/from-daemon/.waku/projects/2026-09-06/new-chat", model.sessionById(id).?.projectPath());
}

test "CreateProjectlessWorkspace sidecar miss falls back locally without clearing a good project_path" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var home_buf: [256]u8 = undefined;
    const home = try std.fmt.bufPrint(&home_buf, ".zig-cache/tmp/{s}/projectless-miss-home", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, home);

    var model = Model{};
    model.store_io = std.testing.io;
    model.setHome(home);
    model.now_ms = 1_757_116_800_000;
    model.setDaemonAddress("10.0.0.2:9");
    model.setSidecarPath("faku");
    const id = model.addSession("untitled", .fx);
    model.selected = id;

    beginForNewSession(&model, &fx, "");
    const sidecar = pendingSpawnKey(&fx, model.daemon_projectless_key) orelse return error.MissingDaemonCreateProjectlessMiss;
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"createProjectlessWorkspace\"") != null);
    applyLine(&model, &fx, .{ .key = sidecar.key, .line = workspace_ack_line });
    try std.testing.expectEqual(@as(usize, 0), model.sessionById(id).?.projectPath().len);
    handleExit(&model, &fx, .{ .key = sidecar.key, .reason = .exited, .code = 1 });
    try std.testing.expectEqual(@as(u64, 0), model.daemon_projectless_key);

    var date_buf: [10]u8 = undefined;
    const date = formatUtcDate(model.now_ms, &date_buf).?;
    var expected_buf: [main.max_project_path]u8 = undefined;
    const expected = try std.fmt.bufPrint(&expected_buf, "{s}/.waku/projects/{s}/new-chat", .{ home, date });
    try std.testing.expectEqualStrings(expected, model.sessionById(id).?.projectPath());
    try std.testing.expectEqualStrings(expected, model.lastProjectPath());
    try std.testing.expect(main.directoryExists(std.testing.io, expected));
}

test "New Task without a daemon address mkdirs ~/.waku/projects/<date>/new-chat" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var home_buf: [256]u8 = undefined;
    const home = try std.fmt.bufPrint(&home_buf, ".zig-cache/tmp/{s}/projectless-local-home", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, home);

    var model = Model{};
    model.store_io = std.testing.io;
    model.setHome(home);
    model.now_ms = 1_757_116_800_000;
    model.setSidecarPath("faku");
    const id = model.addSession("untitled", .fx);
    model.selected = id;

    beginForNewSession(&model, &fx, "");
    try std.testing.expectEqual(@as(u64, 0), model.daemon_projectless_key);
    try std.testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());

    var date_buf: [10]u8 = undefined;
    const date = formatUtcDate(model.now_ms, &date_buf).?;
    var expected_buf: [main.max_project_path]u8 = undefined;
    const expected = try std.fmt.bufPrint(&expected_buf, "{s}/.waku/projects/{s}/new-chat", .{ home, date });
    try std.testing.expectEqualStrings(expected, model.sessionById(id).?.projectPath());
    try std.testing.expect(main.directoryExists(std.testing.io, expected));

    const second = model.addSession("untitled 2", .fx);
    model.selected = second;
    beginForNewSession(&model, &fx, expected);
    var expected2_buf: [main.max_project_path]u8 = undefined;
    const expected2 = try std.fmt.bufPrint(&expected2_buf, "{s}/.waku/projects/{s}/new-chat-2", .{ home, date });
    try std.testing.expectEqualStrings(expected2, model.sessionById(second).?.projectPath());
    try std.testing.expect(main.directoryExists(std.testing.io, expected2));
}

test "New Task with a real project path does not spawn createProjectlessWorkspace" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/ordinary-project", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    model.setLastProjectPath(project);
    const id = model.addSession("untitled", .fx);
    model.selected = id;

    beginForNewSession(&model, &fx, project);
    try std.testing.expectEqual(@as(u64, 0), model.daemon_projectless_key);
    try std.testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
    try std.testing.expectEqualStrings(project, model.sessionById(id).?.projectPath());
    try std.testing.expectEqualStrings(project, model.lastProjectPath());
}

test "New Task while already on a projectless session still prefers createProjectlessWorkspace" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = std.testing.io;
    model.setHome("/home/me");
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    model.setLastProjectPath("/home/me/.waku/projects/2026-09-06/new-chat");
    const id = model.addSession("untitled", .fx);
    model.selected = id;

    beginForNewSession(&model, &fx, "/home/me/.waku/projects/2026-09-06/new-chat");
    const sidecar = pendingSpawnKey(&fx, model.daemon_projectless_key) orelse return error.MissingDaemonCreateProjectlessAlready;
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"createProjectlessWorkspace\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"prompt\":null") != null);
}

test "New Task without home or store_io keeps today's empty last_project_path" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setSidecarPath("faku");
    const id = model.addSession("untitled", .fx);
    model.selected = id;

    beginForNewSession(&model, &fx, "");
    try std.testing.expectEqual(@as(u64, 0), model.daemon_projectless_key);
    try std.testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
    try std.testing.expectEqual(@as(usize, 0), model.sessionById(id).?.projectPath().len);
    try std.testing.expectEqual(@as(usize, 0), model.lastProjectPath().len);
}

const migrate_ok_line = "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000014\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"workspace\",\"result\":{\"type\":\"projectlessWorkspace\",\"cwd\":\"/tmp/from-daemon/.waku/projects/2026-09-06/legacy-chat\"}}}}";

test "session select with a daemon address and legacy path spawns migrateProjectlessWorkspace" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = std.testing.io;
    model.setHome("/home/me");
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    model.setLastProjectPath("/home/me/.waku/2026-09-06/legacy-chat");
    const id = model.addSession("legacy", .fx);
    model.selected = id;

    beginMigrateForSelected(&model, &fx);
    const sidecar = pendingSpawnKey(&fx, model.daemon_migrate_projectless_key) orelse return error.MissingDaemonMigrateProjectless;
    try std.testing.expect(daemon_proxy.isSidecarArgv(sidecar.argv));
    try std.testing.expectEqualStrings("faku", sidecar.argv[0]);
    try std.testing.expectEqualStrings(daemon_proxy.SUBCOMMAND, sidecar.argv[1]);
    try std.testing.expectEqualStrings("127.0.0.1:8787", sidecar.argv[2]);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"hello\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"workspace\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"migrateProjectlessWorkspace\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"path\":\"/home/me/.waku/2026-09-06/legacy-chat\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"createProjectlessWorkspace\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"prompt\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"sessionId\":\"" ++ protocol.NIL_UUID ++ "\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"runtimeId\":\"" ++ protocol.NIL_UUID ++ "\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"prompt\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"attachSession\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "amend") == null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "force") == null);
    try std.testing.expectEqual(sidecar.key, model.daemon_migrate_projectless_key);
    try std.testing.expectEqual(id, model.daemon_migrate_projectless_session);
    try std.testing.expect(sidecar.key != model.daemon_projectless_key);
}

test "MigrateProjectlessWorkspace sidecar paints cwd from projectlessWorkspace" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = std.testing.io;
    model.setHome("/home/me");
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    model.setLastProjectPath("/home/me/.waku/2026-09-06/legacy-chat");
    const id = model.addSession("legacy", .fx);
    model.selected = id;

    beginMigrateForSelected(&model, &fx);
    const sidecar = pendingSpawnKey(&fx, model.daemon_migrate_projectless_key) orelse return error.MissingDaemonMigrateProjectlessFill;
    applyMigrateLine(&model, &fx, .{ .key = sidecar.key, .line = "{\"type\":\"hello\"}" });
    try std.testing.expectEqualStrings("/home/me/.waku/2026-09-06/legacy-chat", model.sessionById(id).?.projectPath());
    applyMigrateLine(&model, &fx, .{ .key = sidecar.key, .line = workspace_ack_line });
    try std.testing.expectEqualStrings("/home/me/.waku/2026-09-06/legacy-chat", model.sessionById(id).?.projectPath());
    try std.testing.expect(!model.daemon_migrate_projectless_ok);
    applyMigrateLine(&model, &fx, .{ .key = sidecar.key, .line = migrate_ok_line });
    try std.testing.expect(model.daemon_migrate_projectless_ok);
    try std.testing.expectEqualStrings("/tmp/from-daemon/.waku/projects/2026-09-06/legacy-chat", model.sessionById(id).?.projectPath());
    try std.testing.expectEqualStrings("/tmp/from-daemon/.waku/projects/2026-09-06/legacy-chat", model.lastProjectPath());
    handleMigrateExit(&model, &fx, .{ .key = sidecar.key, .reason = .exited, .code = 0 });
    try std.testing.expectEqual(@as(u64, 0), model.daemon_migrate_projectless_key);
    try std.testing.expectEqualStrings("/tmp/from-daemon/.waku/projects/2026-09-06/legacy-chat", model.sessionById(id).?.projectPath());
}

test "MigrateProjectlessWorkspace sidecar miss falls back to local rename" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var home_buf: [256]u8 = undefined;
    const home = try std.fmt.bufPrint(&home_buf, ".zig-cache/tmp/{s}/migrate-miss-home", .{tmp.sub_path[0..]});
    var legacy_buf: [main.max_project_path]u8 = undefined;
    const legacy = try std.fmt.bufPrint(&legacy_buf, "{s}/.waku/2026-09-06/legacy-chat", .{home});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, legacy);
    var notes_buf: [main.max_project_path]u8 = undefined;
    const notes = try std.fmt.bufPrint(&notes_buf, "{s}/notes.txt", .{legacy});
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = notes, .data = "kept\n" });

    var model = Model{};
    model.store_io = std.testing.io;
    model.setHome(home);
    model.now_ms = 1_757_116_800_000;
    model.setDaemonAddress("10.0.0.2:9");
    model.setSidecarPath("faku");
    model.setLastProjectPath(legacy);
    const id = model.addSession("legacy", .fx);
    model.selected = id;

    beginMigrateForSelected(&model, &fx);
    const sidecar = pendingSpawnKey(&fx, model.daemon_migrate_projectless_key) orelse return error.MissingDaemonMigrateProjectlessMiss;
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"migrateProjectlessWorkspace\"") != null);
    applyMigrateLine(&model, &fx, .{ .key = sidecar.key, .line = workspace_ack_line });
    try std.testing.expectEqualStrings(legacy, model.sessionById(id).?.projectPath());
    handleMigrateExit(&model, &fx, .{ .key = sidecar.key, .reason = .exited, .code = 1 });
    try std.testing.expectEqual(@as(u64, 0), model.daemon_migrate_projectless_key);

    var expected_buf: [main.max_project_path]u8 = undefined;
    const expected = try std.fmt.bufPrint(&expected_buf, "{s}/.waku/projects/2026-09-06/legacy-chat", .{home});
    try std.testing.expectEqualStrings(expected, model.sessionById(id).?.projectPath());
    try std.testing.expectEqualStrings(expected, model.lastProjectPath());
    try std.testing.expect(main.directoryExists(std.testing.io, expected));
    try std.testing.expect(!main.directoryExists(std.testing.io, legacy));
    var moved_notes_buf: [main.max_project_path]u8 = undefined;
    const moved_notes = try std.fmt.bufPrint(&moved_notes_buf, "{s}/notes.txt", .{expected});
    const moved = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, moved_notes, std.testing.allocator, .limited(64));
    defer std.testing.allocator.free(moved);
    try std.testing.expectEqualStrings("kept\n", moved);
}

test "MigrateProjectlessWorkspace without a daemon address renames dated legacy locally" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var home_buf: [256]u8 = undefined;
    const home = try std.fmt.bufPrint(&home_buf, ".zig-cache/tmp/{s}/migrate-local-home", .{tmp.sub_path[0..]});
    var legacy_buf: [main.max_project_path]u8 = undefined;
    const legacy = try std.fmt.bufPrint(&legacy_buf, "{s}/.waku/2026-09-06/legacy-chat", .{home});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, legacy);

    var model = Model{};
    model.store_io = std.testing.io;
    model.setHome(home);
    model.setSidecarPath("faku");
    model.setLastProjectPath(legacy);
    const id = model.addSession("legacy", .fx);
    model.selected = id;

    beginMigrateForSelected(&model, &fx);
    try std.testing.expectEqual(@as(u64, 0), model.daemon_migrate_projectless_key);
    var i: usize = 0;
    while (fx.pendingSpawnAt(i)) |spawn| : (i += 1) {
        try std.testing.expect(std.mem.indexOf(u8, spawn.stdin, "\"type\":\"migrateProjectlessWorkspace\"") == null);
    }

    var expected_buf: [main.max_project_path]u8 = undefined;
    const expected = try std.fmt.bufPrint(&expected_buf, "{s}/.waku/projects/2026-09-06/legacy-chat", .{home});
    try std.testing.expectEqualStrings(expected, model.sessionById(id).?.projectPath());
    try std.testing.expect(main.directoryExists(std.testing.io, expected));
    try std.testing.expect(!main.directoryExists(std.testing.io, legacy));
}

test "local migrate uses numbered -2 when the destination is taken" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var home_buf: [256]u8 = undefined;
    const home = try std.fmt.bufPrint(&home_buf, ".zig-cache/tmp/{s}/migrate-numbered-home", .{tmp.sub_path[0..]});
    var legacy_buf: [main.max_project_path]u8 = undefined;
    const legacy = try std.fmt.bufPrint(&legacy_buf, "{s}/.waku/2026-09-06/legacy-chat", .{home});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, legacy);
    var taken_buf: [main.max_project_path]u8 = undefined;
    const taken = try std.fmt.bufPrint(&taken_buf, "{s}/.waku/projects/2026-09-06/legacy-chat", .{home});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, taken);

    var model = Model{};
    model.store_io = std.testing.io;
    model.setHome(home);
    model.setSidecarPath("faku");
    model.setLastProjectPath(legacy);
    const id = model.addSession("legacy", .fx);
    model.selected = id;

    beginMigrateForSelected(&model, &fx);
    var expected_buf: [main.max_project_path]u8 = undefined;
    const expected = try std.fmt.bufPrint(&expected_buf, "{s}/.waku/projects/2026-09-06/legacy-chat-2", .{home});
    try std.testing.expectEqualStrings(expected, model.sessionById(id).?.projectPath());
    try std.testing.expect(main.directoryExists(std.testing.io, expected));
    try std.testing.expect(main.directoryExists(std.testing.io, taken));
}

test "bare ~/.waku migrate fallback mkdirs a fresh projects workspace" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var home_buf: [256]u8 = undefined;
    const home = try std.fmt.bufPrint(&home_buf, ".zig-cache/tmp/{s}/migrate-bare-home", .{tmp.sub_path[0..]});
    var legacy_buf: [main.max_project_path]u8 = undefined;
    const legacy = try std.fmt.bufPrint(&legacy_buf, "{s}/.waku", .{home});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, legacy);

    var model = Model{};
    model.store_io = std.testing.io;
    model.setHome(home);
    model.now_ms = 1_757_116_800_000;
    model.setSidecarPath("faku");
    model.setLastProjectPath(legacy);
    const id = model.addSession("legacy", .fx);
    model.selected = id;

    beginMigrateForSelected(&model, &fx);
    try std.testing.expectEqual(@as(u64, 0), model.daemon_migrate_projectless_key);
    var date_buf: [10]u8 = undefined;
    const date = formatUtcDate(model.now_ms, &date_buf).?;
    var expected_buf: [main.max_project_path]u8 = undefined;
    const expected = try std.fmt.bufPrint(&expected_buf, "{s}/.waku/projects/{s}/new-chat", .{ home, date });
    try std.testing.expectEqualStrings(expected, model.sessionById(id).?.projectPath());
    try std.testing.expect(main.directoryExists(std.testing.io, expected));
    try std.testing.expect(main.directoryExists(std.testing.io, legacy));
}

test "real project path and already-under-projects do not spawn migrateProjectlessWorkspace" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/ordinary-migrate-project", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    model.setHome("/home/me");
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    model.setLastProjectPath(project);
    const id = model.addSession("ordinary", .fx);
    model.selected = id;

    beginMigrateForSelected(&model, &fx);
    try std.testing.expectEqual(@as(u64, 0), model.daemon_migrate_projectless_key);
    try std.testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
    try std.testing.expectEqualStrings(project, model.sessionById(id).?.projectPath());

    if (model.sessionById(id)) |session| session.setProjectPath("/home/me/.waku/projects/2026-09-06/new-chat");
    model.setLastProjectPath("/home/me/.waku/projects/2026-09-06/new-chat");
    beginMigrateForSelected(&model, &fx);
    try std.testing.expectEqual(@as(u64, 0), model.daemon_migrate_projectless_key);
    try std.testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
    try std.testing.expectEqualStrings("/home/me/.waku/projects/2026-09-06/new-chat", model.sessionById(id).?.projectPath());
}

test "cancelled MigrateProjectlessWorkspace sidecar cannot paint a later session" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = std.testing.io;
    model.setHome("/home/me");
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    model.setLastProjectPath("/home/me/.waku/2026-09-06/legacy-chat");
    const id = model.addSession("legacy", .fx);
    model.selected = id;

    beginMigrateForSelected(&model, &fx);
    const sidecar = pendingSpawnKey(&fx, model.daemon_migrate_projectless_key) orelse return error.MissingDaemonMigrateProjectlessCancel;
    const key = sidecar.key;
    cancelMigrate(&model, &fx);
    try std.testing.expectEqual(@as(u64, 0), model.daemon_migrate_projectless_key);
    applyMigrateLine(&model, &fx, .{ .key = key, .line = migrate_ok_line });
    try std.testing.expectEqualStrings("/home/me/.waku/2026-09-06/legacy-chat", model.sessionById(id).?.projectPath());
    handleMigrateExit(&model, &fx, .{ .key = key, .reason = .exited, .code = 0 });
    try std.testing.expectEqualStrings("/home/me/.waku/2026-09-06/legacy-chat", model.sessionById(id).?.projectPath());
}

test "MigrateProjectlessWorkspace without home or store_io keeps today's legacy path" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setSidecarPath("faku");
    model.setLastProjectPath("/home/me/.waku/2026-09-06/legacy-chat");
    const id = model.addSession("legacy", .fx);
    model.selected = id;

    beginMigrateForSelected(&model, &fx);
    try std.testing.expectEqual(@as(u64, 0), model.daemon_migrate_projectless_key);
    try std.testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
    try std.testing.expectEqualStrings("/home/me/.waku/2026-09-06/legacy-chat", model.sessionById(id).?.projectPath());
}
