//! One-shot `git remote` probe for Waku first-push remotes.
//!
//! Native has no git/workspace effect. When the selected session has a
//! non-empty `project_path` that exists, Faku `fx.spawn`s `git remote`
//! through the same `/bin/sh -c` chdir workaround `fx ask` uses
//! (`fx_ask_chdir_script`). Reuses `git_checkout.remoteArgvFor` /
//! `isGitRemoteArgv` (`remote` its own argv slot — never interpolated
//! into the `-c` script). Prefer `origin` if listed, else the first
//! plausible name — same as Push `applyRemoteCandidate` /
//! `pickRemoteName`. A ready bit plus `has_remote` gate composer
//! Push… and Commit and Push on the no-upstream path. Failed / empty
//! does not invent remotes. In-flight and never-finished stay hidden
//! so the row does not flash. Distinct spawn-key band (480+); does
//! not share `git_push_key`'s remotes phase. Runtime-only (not
//! `sessions.json`). Not a live remotes watch, not an invented Native
//! git effect. Canonicalize of `project_path` is `git_toplevel.zig`.
//!
//! Spawn/line/exit orchestration lives here. Windows is skipped
//! (app.zon is macos/linux; no Windows spawn path).

const std = @import("std");
const builtin = @import("builtin");
const native_sdk = @import("native_sdk");
const main = @import("main.zig");
const git_checkout = @import("git_checkout.zig");

const Model = main.Model;
const Effects = main.Effects;
const writeFixed = main.writeFixed;

/// One-shot `git remote` probe for first-push remotes. Distinct from
/// git_commit_generate (470+), git_commit_numstat (460+), add/commit
/// (450+), file_mention (400+), and git_push remotes (360+). Band is
/// 480+. Incremented per refresh so a cancelled spawn cannot paint a
/// later session.
pub const git_remotes_key_first: u64 = 480;

pub const argv_len = git_checkout.remote_argv_len;

pub fn argvFor(cwd: []const u8, buf: *[argv_len][]const u8) []const []const u8 {
    return git_checkout.remoteArgvFor(cwd, buf);
}

pub fn isGitRemotesArgv(argv: []const []const u8) bool {
    return git_checkout.isGitRemoteArgv(argv);
}

pub fn hasGitRemote(model: *const Model) bool {
    return model.git_has_remote;
}

/// Remotes probe finished with at least one plausible name.
/// Hide while in-flight or never-finished (no flash).
pub fn remotesReadyForFirstPush(model: *const Model) bool {
    if (model.git_remotes_key != 0) return false;
    if (!model.git_remotes_ready) return false;
    return model.git_has_remote;
}

/// Commit-and-Push remotes gate: known upstream is enough (post-commit
/// push can work even when ahead was 0). No-upstream / unknown
/// requires remotes ready and at least one remote. Hide while the
/// remotes probe is still needed or in-flight on that path.
pub fn firstPushRemotesOk(model: *const Model) bool {
    if (model.git_ahead_behind_key == 0 and model.git_ahead_behind_ready and model.git_ahead_behind_has_upstream) {
        return true;
    }
    return remotesReadyForFirstPush(model);
}

pub fn clearGitRemotes(model: *Model) void {
    model.git_has_remote = false;
    model.git_remotes_ready = false;
}

fn cancelInFlight(model: *Model, fx: *Effects) void {
    if (model.git_remotes_key == 0) return;
    fx.cancel(model.git_remotes_key);
    model.git_remotes_key = 0;
}

fn probePath(model: *const Model) []const u8 {
    const path = model.selectedProjectPath();
    if (path.len == 0) return "";
    const io = model.store_io orelse return "";
    if (!main.directoryExists(io, path)) return "";
    return path;
}

/// Cancel any in-flight probe, drop has_remote, and spawn again when
/// the selected session has an existing `project_path`. Empty /
/// missing / Windows skips the spawn so first-push stays hidden.
pub fn refresh(model: *Model, fx: *Effects) void {
    cancelInFlight(model, fx);
    clearGitRemotes(model);
    if (builtin.os.tag == .windows) return;
    const cwd = probePath(model);
    if (cwd.len == 0) return;

    const key = model.next_git_remotes_key;
    model.next_git_remotes_key = key + 1;
    model.git_remotes_key = key;
    model.git_remotes_probe_session = model.selected;
    writeFixed(&model.git_remotes_probe_path_storage, &model.git_remotes_probe_path_len, cwd);

    var argv_buf: [argv_len][]const u8 = undefined;
    fx.spawn(.{
        .key = key,
        .argv = argvFor(cwd, &argv_buf),
        .on_line = Effects.lineMsg(.fx_line),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
}

fn probeStillCurrent(model: *const Model) bool {
    if (model.git_remotes_key == 0) return false;
    if (model.git_remotes_probe_session != model.selected) return false;
    const path = model.selectedProjectPath();
    const probed = model.git_remotes_probe_path_storage[0..model.git_remotes_probe_path_len];
    return std.mem.eql(u8, path, probed);
}

pub fn applyLine(model: *Model, line: native_sdk.EffectLine) void {
    if (line.key != model.git_remotes_key or model.git_remotes_key == 0) return;
    if (!probeStillCurrent(model)) return;
    if (git_checkout.pickRemoteName(line.line).len > 0) {
        model.git_has_remote = true;
    }
}

pub fn handleExit(model: *Model, exit: native_sdk.EffectExit) void {
    if (exit.key != model.git_remotes_key or model.git_remotes_key == 0) return;
    const current = probeStillCurrent(model);
    model.git_remotes_key = 0;
    if (!current or exit.reason != .exited) {
        clearGitRemotes(model);
        return;
    }
    if (exit.code != 0) {
        model.git_has_remote = false;
        model.git_remotes_ready = true;
        return;
    }
    model.git_remotes_ready = true;
}

test "argv is chdir script plus git remote as its own slot" {
    const git_ahead_behind = @import("git_ahead_behind.zig");
    var buf: [argv_len][]const u8 = undefined;
    const argv = argvFor("/tmp/faku-remotes", &buf);
    try std.testing.expectEqual(@as(usize, 7), argv.len);
    try std.testing.expectEqualStrings(git_checkout.sh_bin, argv[0]);
    try std.testing.expectEqualStrings("-c", argv[1]);
    try std.testing.expectEqualStrings(main.fx_ask_chdir_script, argv[2]);
    try std.testing.expectEqualStrings("sh", argv[3]);
    try std.testing.expectEqualStrings("/tmp/faku-remotes", argv[4]);
    try std.testing.expectEqualStrings(git_checkout.git_bin, argv[5]);
    try std.testing.expectEqualStrings(git_checkout.git_remote_cmd, argv[6]);
    try std.testing.expect(isGitRemotesArgv(argv));
    try std.testing.expect(git_checkout.isGitRemoteArgv(argv));
    try std.testing.expect(std.mem.indexOf(u8, argv[2], git_checkout.git_remote_cmd) == null);
    try std.testing.expect(!isGitRemotesArgv(&.{ git_checkout.git_bin, git_checkout.git_remote_cmd }));
    var ahead_buf: [git_ahead_behind.argv_len][]const u8 = undefined;
    const ahead = git_ahead_behind.argvFor("/tmp/faku-remotes", &ahead_buf);
    try std.testing.expect(!isGitRemotesArgv(ahead));
    try std.testing.expect(!git_ahead_behind.isGitAheadBehindArgv(argv));
    try std.testing.expect(git_remotes_key_first >= 480);
    try std.testing.expect(git_remotes_key_first > 470);
    try std.testing.expect(git_remotes_key_first > git_checkout.git_push_key_first);
}

test "refresh one-shots git remote on a distinct key; empty fail and origin" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/git-remotes", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("remotes probe", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);

    refresh(&model, &fx);
    try std.testing.expectEqual(git_remotes_key_first, model.git_remotes_key);
    try std.testing.expect(!model.git_remotes_ready);
    try std.testing.expect(!model.git_has_remote);
    try std.testing.expect(!remotesReadyForFirstPush(&model));
    try std.testing.expect(!git_checkout.gitMutationInFlight(&model));

    var found: ?@TypeOf(fx.pendingSpawnAt(0).?) = null;
    var i: usize = 0;
    while (i < fx.pendingSpawnCount()) : (i += 1) {
        const spawn = fx.pendingSpawnAt(i).?;
        if (spawn.key == model.git_remotes_key and isGitRemotesArgv(spawn.argv)) {
            found = spawn;
            break;
        }
    }
    const spawn = found orelse return error.MissingGitRemotesSpawn;
    try std.testing.expect(spawn.key >= git_remotes_key_first);
    try std.testing.expect(spawn.key != git_checkout.git_push_key_first);
    try std.testing.expectEqualStrings(project, spawn.argv[4]);
    try std.testing.expectEqualStrings(git_checkout.git_remote_cmd, spawn.argv[6]);
    try std.testing.expect(std.mem.indexOf(u8, spawn.argv[2], git_checkout.git_remote_cmd) == null);

    applyLine(&model, .{ .key = spawn.key, .line = "upstream\norigin\n" });
    try std.testing.expect(model.git_has_remote);
    handleExit(&model, .{ .key = spawn.key, .reason = .exited, .code = 0 });
    try std.testing.expectEqual(@as(u64, 0), model.git_remotes_key);
    try std.testing.expect(model.git_remotes_ready);
    try std.testing.expect(remotesReadyForFirstPush(&model));

    refresh(&model, &fx);
    const key2 = model.git_remotes_key;
    try std.testing.expect(key2 != spawn.key);
    try std.testing.expect(!model.git_has_remote);
    handleExit(&model, .{ .key = key2, .reason = .exited, .code = 0 });
    try std.testing.expect(model.git_remotes_ready);
    try std.testing.expect(!model.git_has_remote);
    try std.testing.expect(!remotesReadyForFirstPush(&model));

    refresh(&model, &fx);
    const key3 = model.git_remotes_key;
    applyLine(&model, .{ .key = key3, .line = "origin\n" });
    handleExit(&model, .{ .key = key3, .reason = .exited, .code = 1 });
    try std.testing.expect(model.git_remotes_ready);
    try std.testing.expect(!model.git_has_remote);
    try std.testing.expect(!remotesReadyForFirstPush(&model));
}

test "session change drops an in-flight remotes probe" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var a_buf: [256]u8 = undefined;
    var b_buf: [256]u8 = undefined;
    const project_a = try std.fmt.bufPrint(&a_buf, ".zig-cache/tmp/{s}/git-remotes-a", .{tmp.sub_path[0..]});
    const project_b = try std.fmt.bufPrint(&b_buf, ".zig-cache/tmp/{s}/git-remotes-b", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project_a);
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project_b);

    var model = Model{};
    model.store_io = std.testing.io;
    const first = model.addSession("remotes a", .fx);
    const second = model.addSession("remotes b", .fx);
    model.selected = first;
    if (model.sessionById(first)) |session| session.setProjectPath(project_a);
    if (model.sessionById(second)) |session| session.setProjectPath(project_b);

    refresh(&model, &fx);
    const first_key = model.git_remotes_key;
    applyLine(&model, .{ .key = first_key, .line = "origin\n" });
    try std.testing.expect(model.git_has_remote);

    model.selected = second;
    refresh(&model, &fx);
    try std.testing.expect(model.git_remotes_key != first_key);
    try std.testing.expect(!model.git_has_remote);
    applyLine(&model, .{ .key = first_key, .line = "upstream\n" });
    handleExit(&model, .{ .key = first_key, .reason = .exited, .code = 0 });
    try std.testing.expect(!model.git_has_remote);
    try std.testing.expect(!model.git_remotes_ready);
}
