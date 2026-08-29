//! One-shot `git rev-parse --git-common-dir` for New worktree… nest
//! identity.
//!
//! Native has no git/workspace effect. When the selected session has a
//! non-empty `project_path` that exists, Faku `fx.spawn`s
//! `git rev-parse --git-common-dir` through the same `/bin/sh -c`
//! chdir workaround `fx ask` uses (`fx_ask_chdir_script`). Every
//! flag and operand is its own argv slot — never interpolated into
//! the `-c` script. Reuses `git_checkout.git_bin` / `sh_bin`. Git
//! often prints a relative path such as `.git`; that is resolved to
//! an absolute path against the ready `--show-toplevel` root when
//! that probe finished, else the probe cwd, before it is stored. A
//! ready bit plus that absolute path let New worktree… nest under a
//! shared FNV so linked worktrees of the same repo share
//! `~/.faku/worktrees/<nest>/`. Occupancy stays on
//! `git_toplevel.zig` (`worktreepath` equal to ready show-toplevel).
//! Failed / empty / cancel leave ready false and the path empty so
//! nest falls back to ready show-toplevel, then today's
//! `project_path` heuristic. Distinct spawn-key band (500+); does
//! not share toplevel (490+). Runtime-only (not `sessions.json`).
//! Not a live watch, not an invented Native git effect, and not
//! occupancy.
//!
//! Spawn/line/exit orchestration lives here. Windows is skipped
//! (app.zon is macos/linux; no Windows spawn path).

const std = @import("std");
const builtin = @import("builtin");
const native_sdk = @import("native_sdk");
const main = @import("main.zig");
const git_checkout = @import("git_checkout.zig");
const git_toplevel = @import("git_toplevel.zig");

const Model = main.Model;
const Effects = main.Effects;
const writeFixed = main.writeFixed;

/// One-shot `git rev-parse --git-common-dir`. Distinct from
/// git_toplevel (490+), git_remotes (480+), and the rest of the
/// git probe bands. Band is 500+. Incremented per refresh so a
/// cancelled spawn cannot paint a later session.
pub const git_common_dir_key_first: u64 = 500;

pub const git_common_dir_flag = "--git-common-dir";
pub const argv_len: usize = 8;

pub fn argvFor(cwd: []const u8, buf: *[argv_len][]const u8) []const []const u8 {
    buf.* = .{
        git_checkout.sh_bin,
        "-c",
        main.fx_ask_chdir_script,
        "sh",
        cwd,
        git_checkout.git_bin,
        git_checkout.git_rev_parse_cmd,
        git_common_dir_flag,
    };
    return buf;
}

pub fn isGitCommonDirArgv(argv: []const []const u8) bool {
    if (argv.len != argv_len) return false;
    if (!std.mem.eql(u8, argv[0], git_checkout.sh_bin)) return false;
    if (!std.mem.eql(u8, argv[1], "-c")) return false;
    if (!std.mem.eql(u8, argv[2], main.fx_ask_chdir_script)) return false;
    if (!std.mem.eql(u8, argv[5], git_checkout.git_bin)) return false;
    if (!std.mem.eql(u8, argv[6], git_checkout.git_rev_parse_cmd)) return false;
    return std.mem.eql(u8, argv[7], git_common_dir_flag);
}

/// First stdout line, trimmed. Empty / whitespace is not a path.
pub fn firstStdoutLine(raw: []const u8) []const u8 {
    const trimmed = std.mem.trim(u8, raw, " \t\r\n");
    if (trimmed.len == 0) return "";
    const end = std.mem.indexOfAny(u8, trimmed, "\r\n") orelse trimmed.len;
    return std.mem.trim(u8, trimmed[0..end], " \t");
}

/// Accept a git-common-dir path fragment. Reject empty / `..` / NUL /
/// overflow of `session.max_project_path` so a truncated root is
/// never stored. Relative prints such as `.git` are allowed here;
/// `resolveCommonDir` makes them absolute before storage.
pub fn parseCommonDirLine(raw: []const u8) []const u8 {
    const line = firstStdoutLine(raw);
    if (line.len == 0 or line.len > main.max_project_path) return "";
    if (std.mem.indexOf(u8, line, "..") != null) return "";
    if (std.mem.indexOfScalar(u8, line, 0) != null) return "";
    return line;
}

/// Resolve a parsed common-dir print to an absolute path. Absolute
/// prints are kept. Relative prints join `base` (ready toplevel or
/// probe cwd). Empty / `..` / NUL / missing absolute base /
/// overflow → empty.
pub fn resolveCommonDir(raw: []const u8, base: []const u8, buf: []u8) []const u8 {
    const line = parseCommonDirLine(raw);
    if (line.len == 0) return "";
    if (line[0] == '/') {
        if (line.len > buf.len) return "";
        @memcpy(buf[0..line.len], line);
        return buf[0..line.len];
    }
    const root = std.mem.trim(u8, base, " \t\r\n");
    if (root.len == 0 or root[0] != '/') return "";
    if (std.mem.indexOf(u8, root, "..") != null) return "";
    if (std.mem.indexOfScalar(u8, root, 0) != null) return "";
    const sep: []const u8 = if (root[root.len - 1] == '/') "" else "/";
    const needed = root.len + sep.len + line.len;
    if (needed > buf.len or needed > main.max_project_path) return "";
    @memcpy(buf[0..root.len], root);
    if (sep.len == 1) buf[root.len] = '/';
    @memcpy(buf[root.len + sep.len ..][0..line.len], line);
    return buf[0..needed];
}

pub fn gitCommonDirPath(model: *const Model) []const u8 {
    return model.git_common_dir_path_storage[0..model.git_common_dir_path_len];
}

/// Ready absolute common-dir, or empty when the probe is in flight /
/// failed / never finished (consumers fall back).
pub fn readyPath(model: *const Model) []const u8 {
    if (model.git_common_dir_key != 0) return "";
    if (!model.git_common_dir_ready) return "";
    return gitCommonDirPath(model);
}

pub fn clearGitCommonDir(model: *Model) void {
    model.git_common_dir_ready = false;
    model.git_common_dir_path_len = 0;
}

fn cancelInFlight(model: *Model, fx: *Effects) void {
    if (model.git_common_dir_key == 0) return;
    fx.cancel(model.git_common_dir_key);
    model.git_common_dir_key = 0;
}

fn probePath(model: *const Model) []const u8 {
    const path = model.selectedProjectPath();
    if (path.len == 0) return "";
    const io = model.store_io orelse return "";
    if (!main.directoryExists(io, path)) return "";
    return path;
}

fn resolveBase(model: *const Model) []const u8 {
    const top = git_toplevel.readyPath(model);
    if (top.len > 0) return top;
    return model.git_common_dir_probe_path_storage[0..model.git_common_dir_probe_path_len];
}

fn storeResolved(model: *Model, raw: []const u8) void {
    var resolved_buf: [main.max_project_path]u8 = undefined;
    const resolved = resolveCommonDir(raw, resolveBase(model), resolved_buf[0..]);
    if (resolved.len == 0) return;
    writeFixed(&model.git_common_dir_path_storage, &model.git_common_dir_path_len, resolved);
}

/// Cancel any in-flight probe, drop ready/path, and spawn again when
/// the selected session has an existing `project_path`. Empty /
/// missing / Windows skips the spawn so consumers keep the fallback.
pub fn refresh(model: *Model, fx: *Effects) void {
    cancelInFlight(model, fx);
    clearGitCommonDir(model);
    if (builtin.os.tag == .windows) return;
    const cwd = probePath(model);
    if (cwd.len == 0) return;

    const key = model.next_git_common_dir_key;
    model.next_git_common_dir_key = key + 1;
    model.git_common_dir_key = key;
    model.git_common_dir_probe_session = model.selected;
    writeFixed(&model.git_common_dir_probe_path_storage, &model.git_common_dir_probe_path_len, cwd);

    var argv_buf: [argv_len][]const u8 = undefined;
    fx.spawn(.{
        .key = key,
        .argv = argvFor(cwd, &argv_buf),
        .on_line = Effects.lineMsg(.fx_line),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
}

fn probeStillCurrent(model: *const Model) bool {
    if (model.git_common_dir_key == 0) return false;
    if (model.git_common_dir_probe_session != model.selected) return false;
    const path = model.selectedProjectPath();
    const probed = model.git_common_dir_probe_path_storage[0..model.git_common_dir_probe_path_len];
    return std.mem.eql(u8, path, probed);
}

pub fn applyLine(model: *Model, line: native_sdk.EffectLine) void {
    if (line.key != model.git_common_dir_key or model.git_common_dir_key == 0) return;
    if (!probeStillCurrent(model)) return;
    storeResolved(model, line.line);
}

pub fn handleExit(model: *Model, exit: native_sdk.EffectExit) void {
    if (exit.key != model.git_common_dir_key or model.git_common_dir_key == 0) return;
    const current = probeStillCurrent(model);
    model.git_common_dir_key = 0;
    if (!current or exit.reason != .exited or exit.code != 0) {
        clearGitCommonDir(model);
        return;
    }
    const stored = gitCommonDirPath(model);
    if (parseCommonDirLine(stored).len == 0 or stored[0] != '/') {
        clearGitCommonDir(model);
        return;
    }
    model.git_common_dir_ready = true;
}

test "argv is chdir script plus git rev-parse --git-common-dir as own slots" {
    const git_remotes = @import("git_remotes.zig");
    var buf: [argv_len][]const u8 = undefined;
    const argv = argvFor("/tmp/faku-common-dir", &buf);
    try std.testing.expectEqual(@as(usize, 8), argv.len);
    try std.testing.expectEqualStrings(git_checkout.sh_bin, argv[0]);
    try std.testing.expectEqualStrings("-c", argv[1]);
    try std.testing.expectEqualStrings(main.fx_ask_chdir_script, argv[2]);
    try std.testing.expectEqualStrings("sh", argv[3]);
    try std.testing.expectEqualStrings("/tmp/faku-common-dir", argv[4]);
    try std.testing.expectEqualStrings(git_checkout.git_bin, argv[5]);
    try std.testing.expectEqualStrings(git_checkout.git_rev_parse_cmd, argv[6]);
    try std.testing.expectEqualStrings(git_common_dir_flag, argv[7]);
    try std.testing.expect(isGitCommonDirArgv(argv));
    try std.testing.expect(std.mem.indexOf(u8, argv[2], git_checkout.git_rev_parse_cmd) == null);
    try std.testing.expect(std.mem.indexOf(u8, argv[2], git_common_dir_flag) == null);
    try std.testing.expect(!isGitCommonDirArgv(&.{ git_checkout.git_bin, git_checkout.git_rev_parse_cmd, git_common_dir_flag }));
    var remotes_buf: [git_remotes.argv_len][]const u8 = undefined;
    const remotes = git_remotes.argvFor("/tmp/faku-common-dir", &remotes_buf);
    try std.testing.expect(!isGitCommonDirArgv(remotes));
    try std.testing.expect(!git_remotes.isGitRemotesArgv(argv));
    var top_buf: [git_toplevel.argv_len][]const u8 = undefined;
    const top = git_toplevel.argvFor("/tmp/faku-common-dir", &top_buf);
    try std.testing.expect(!isGitCommonDirArgv(top));
    try std.testing.expect(!git_toplevel.isGitToplevelArgv(argv));
    try std.testing.expect(git_common_dir_key_first >= 500);
    try std.testing.expect(git_common_dir_key_first > git_toplevel.git_toplevel_key_first);
    try std.testing.expect(git_toplevel.git_toplevel_key_first >= 490);
}

test "resolveCommonDir keeps absolute and joins relative against base" {
    var buf: [main.max_project_path]u8 = undefined;
    try std.testing.expectEqualStrings(
        "/tmp/repo/.git",
        resolveCommonDir("  /tmp/repo/.git  \n", "/tmp/other", buf[0..]),
    );
    try std.testing.expectEqualStrings(
        "/tmp/proj/.git",
        resolveCommonDir(".git\n", "/tmp/proj", buf[0..]),
    );
    try std.testing.expectEqualStrings(
        "/tmp/proj/.git",
        resolveCommonDir(".git", "/tmp/proj/", buf[0..]),
    );
    try std.testing.expectEqualStrings(
        "/tmp/canonical/.git",
        resolveCommonDir(".git", "/tmp/canonical", buf[0..]),
    );
    try std.testing.expectEqualStrings("", resolveCommonDir("", "/tmp/proj", buf[0..]));
    try std.testing.expectEqualStrings("", resolveCommonDir("..\n", "/tmp/proj", buf[0..]));
    try std.testing.expectEqualStrings("", resolveCommonDir("../.git\n", "/tmp/proj", buf[0..]));
    try std.testing.expectEqualStrings("", resolveCommonDir(".git", "relative", buf[0..]));
    try std.testing.expectEqualStrings("", resolveCommonDir(".git", "", buf[0..]));
    const with_nul = ".git\x00x";
    try std.testing.expectEqualStrings("", resolveCommonDir(with_nul, "/tmp/proj", buf[0..]));
}

test "refresh one-shots git-common-dir on a distinct key; empty fail and success" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/git-common-dir", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("common-dir probe", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);

    refresh(&model, &fx);
    try std.testing.expectEqual(git_common_dir_key_first, model.git_common_dir_key);
    try std.testing.expect(!model.git_common_dir_ready);
    try std.testing.expectEqual(@as(usize, 0), model.git_common_dir_path_len);
    try std.testing.expectEqualStrings("", readyPath(&model));
    try std.testing.expect(!git_checkout.gitMutationInFlight(&model));

    var found: ?@TypeOf(fx.pendingSpawnAt(0).?) = null;
    var i: usize = 0;
    while (i < fx.pendingSpawnCount()) : (i += 1) {
        const spawn = fx.pendingSpawnAt(i).?;
        if (spawn.key == model.git_common_dir_key and isGitCommonDirArgv(spawn.argv)) {
            found = spawn;
            break;
        }
    }
    const spawn = found orelse return error.MissingGitCommonDirSpawn;
    try std.testing.expect(spawn.key >= git_common_dir_key_first);
    try std.testing.expect(spawn.key != git_checkout.git_push_key_first);
    try std.testing.expect(spawn.key != git_toplevel.git_toplevel_key_first);
    try std.testing.expectEqualStrings(project, spawn.argv[4]);
    try std.testing.expectEqualStrings(git_common_dir_flag, spawn.argv[7]);
    try std.testing.expect(std.mem.indexOf(u8, spawn.argv[2], git_common_dir_flag) == null);

    applyLine(&model, .{ .key = spawn.key, .line = "  /tmp/shared.git  \n" });
    try std.testing.expectEqualStrings("/tmp/shared.git", gitCommonDirPath(&model));
    try std.testing.expect(!model.git_common_dir_ready);
    handleExit(&model, .{ .key = spawn.key, .reason = .exited, .code = 0 });
    try std.testing.expectEqual(@as(u64, 0), model.git_common_dir_key);
    try std.testing.expect(model.git_common_dir_ready);
    try std.testing.expectEqualStrings("/tmp/shared.git", readyPath(&model));

    refresh(&model, &fx);
    const key2 = model.git_common_dir_key;
    try std.testing.expect(key2 != spawn.key);
    try std.testing.expect(!model.git_common_dir_ready);
    try std.testing.expectEqualStrings("", readyPath(&model));
    handleExit(&model, .{ .key = key2, .reason = .exited, .code = 0 });
    try std.testing.expect(!model.git_common_dir_ready);
    try std.testing.expectEqualStrings("", readyPath(&model));

    refresh(&model, &fx);
    const key3 = model.git_common_dir_key;
    applyLine(&model, .{ .key = key3, .line = "/tmp/should-clear\n" });
    handleExit(&model, .{ .key = key3, .reason = .exited, .code = 1 });
    try std.testing.expect(!model.git_common_dir_ready);
    try std.testing.expectEqualStrings("", readyPath(&model));

    refresh(&model, &fx);
    const key4 = model.git_common_dir_key;
    applyLine(&model, .{ .key = key4, .line = "..\n" });
    handleExit(&model, .{ .key = key4, .reason = .exited, .code = 0 });
    try std.testing.expect(!model.git_common_dir_ready);
    try std.testing.expectEqualStrings("", readyPath(&model));
}

test "relative git-common-dir resolves against probe cwd or ready toplevel" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, "/tmp/faku-gcd-rel-{s}", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("common-dir relative", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);
    refresh(&model, &fx);
    const key = model.git_common_dir_key;
    applyLine(&model, .{ .key = key, .line = ".git\n" });
    handleExit(&model, .{ .key = key, .reason = .exited, .code = 0 });
    var expect_cwd: [main.max_project_path]u8 = undefined;
    const from_cwd = resolveCommonDir(".git", project, expect_cwd[0..]);
    try std.testing.expect(from_cwd.len > 0);
    try std.testing.expectEqualStrings(from_cwd, readyPath(&model));
    try std.testing.expect(std.mem.endsWith(u8, readyPath(&model), "/.git"));

    refresh(&model, &fx);
    const key2 = model.git_common_dir_key;
    writeFixed(&model.git_toplevel_path_storage, &model.git_toplevel_path_len, "/tmp/canonical");
    model.git_toplevel_ready = true;
    applyLine(&model, .{ .key = key2, .line = ".git\n" });
    handleExit(&model, .{ .key = key2, .reason = .exited, .code = 0 });
    try std.testing.expectEqualStrings("/tmp/canonical/.git", readyPath(&model));
}

test "session change drops an in-flight common-dir probe" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var a_buf: [256]u8 = undefined;
    var b_buf: [256]u8 = undefined;
    const project_a = try std.fmt.bufPrint(&a_buf, ".zig-cache/tmp/{s}/git-common-a", .{tmp.sub_path[0..]});
    const project_b = try std.fmt.bufPrint(&b_buf, ".zig-cache/tmp/{s}/git-common-b", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project_a);
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project_b);

    var model = Model{};
    model.store_io = std.testing.io;
    const first = model.addSession("common a", .fx);
    const second = model.addSession("common b", .fx);
    model.selected = first;
    if (model.sessionById(first)) |session| session.setProjectPath(project_a);
    if (model.sessionById(second)) |session| session.setProjectPath(project_b);

    refresh(&model, &fx);
    const first_key = model.git_common_dir_key;
    applyLine(&model, .{ .key = first_key, .line = "/tmp/first.git\n" });
    try std.testing.expectEqualStrings("/tmp/first.git", gitCommonDirPath(&model));

    model.selected = second;
    refresh(&model, &fx);
    try std.testing.expect(model.git_common_dir_key != first_key);
    try std.testing.expectEqualStrings("", gitCommonDirPath(&model));
    applyLine(&model, .{ .key = first_key, .line = "/tmp/stale.git\n" });
    handleExit(&model, .{ .key = first_key, .reason = .exited, .code = 0 });
    try std.testing.expect(!model.git_common_dir_ready);
    try std.testing.expectEqualStrings("", readyPath(&model));
}

test "nest key prefers ready common-dir; occupancy stays on toplevel" {
    var model = Model{};
    const id = model.addSession("common-dir nest", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath("/tmp/proj/src");

    var nest_raw_buf: [git_checkout.worktree_nest_key_len]u8 = undefined;
    var nest_top_buf: [git_checkout.worktree_nest_key_len]u8 = undefined;
    var nest_common_buf: [git_checkout.worktree_nest_key_len]u8 = undefined;
    var nest_model_buf: [git_checkout.worktree_nest_key_len]u8 = undefined;
    const nest_raw = git_checkout.worktreeNestKey("/tmp/proj/src", nest_raw_buf[0..]).?;
    const nest_top = git_checkout.worktreeNestKey("/tmp/proj", nest_top_buf[0..]).?;
    const nest_common = git_checkout.worktreeNestKey("/tmp/shared.git", nest_common_buf[0..]).?;
    try std.testing.expect(!std.mem.eql(u8, nest_raw, nest_top));
    try std.testing.expect(!std.mem.eql(u8, nest_top, nest_common));
    try std.testing.expectEqualStrings(nest_raw, git_checkout.worktreeNestKeyFor("/tmp/proj/src", nest_model_buf[0..], &model).?);

    writeFixed(&model.git_toplevel_path_storage, &model.git_toplevel_path_len, "/tmp/proj");
    model.git_toplevel_ready = true;
    try std.testing.expectEqualStrings("/tmp/proj", git_toplevel.readyPath(&model));
    try std.testing.expectEqualStrings(nest_top, git_checkout.worktreeNestKeyFor("/tmp/proj/src", nest_model_buf[0..], &model).?);
    try std.testing.expect(git_checkout.isThisWorktreePathFor("/tmp/proj", "/tmp/proj/src", &model));
    try std.testing.expect(!git_checkout.isThisWorktreePathFor("/tmp/other-worktree", "/tmp/proj/src", &model));

    writeFixed(&model.git_common_dir_path_storage, &model.git_common_dir_path_len, "/tmp/shared.git");
    model.git_common_dir_ready = true;
    try std.testing.expectEqualStrings("/tmp/shared.git", readyPath(&model));
    try std.testing.expectEqualStrings(nest_common, git_checkout.worktreeNestKeyFor("/tmp/proj/src", nest_model_buf[0..], &model).?);
    try std.testing.expect(git_checkout.isThisWorktreePathFor("/tmp/proj", "/tmp/proj/src", &model));
    try std.testing.expect(!git_checkout.isThisWorktreePathFor("/tmp/other-worktree", "/tmp/proj/src", &model));
    try std.testing.expect(!git_checkout.localHeadOccupiedFor(false, "/tmp/proj", "/tmp/proj/src", &model));
    try std.testing.expect(git_checkout.localHeadOccupiedFor(false, "/tmp/other-worktree", "/tmp/proj/src", &model));

    model.git_common_dir_key = git_common_dir_key_first;
    try std.testing.expectEqualStrings("", readyPath(&model));
    try std.testing.expectEqualStrings(nest_top, git_checkout.worktreeNestKeyFor("/tmp/proj/src", nest_model_buf[0..], &model).?);
}
