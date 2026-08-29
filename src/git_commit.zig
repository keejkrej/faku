//! First-cut include-unstaged Commit… for the composer project row.
//!
//! Native has no git effect. Confirm one-shots `git add -A -- .` then
//! `git commit -m <message>` through the same `/bin/sh -c` chdir
//! workaround `fx ask` uses (`fx_ask_chdir_script`). Every flag and
//! operand is its own argv slot — never interpolated into the `-c`
//! script. Message is trimmed, taken as a single line, and capped at
//! 200 chars (Waku `chars().take(200)`). Empty / whitespace does not
//! spawn. Not Waku InspectCommit, not Commit and Push, not
//! staged-only, not AI `generate_message`, not
//! `git diff --cached --quiet` preflight, not
//! canonicalize(`git rev-parse --show-toplevel`), not
//! remotes-required-for-first-push, not git-common-dir nest identity,
//! not force / amend, and not daemon `WorkspaceOperation`.
//!
//! Spawn/line/exit orchestration lives here. Windows is skipped
//! (app.zon is macos/linux; no Windows spawn path).

const std = @import("std");
const builtin = @import("builtin");
const native_sdk = @import("native_sdk");
const main = @import("main.zig");
const git_branch = @import("git_branch.zig");
const git_checkout = @import("git_checkout.zig");
const git_dirty = @import("git_dirty.zig");
const file_mention = @import("file_mention.zig");

const Model = main.Model;
const Effects = main.Effects;
const writeFixed = main.writeFixed;

/// One-shot `git add -A -- .` then `git commit -m` on one spawn-key
/// band. Distinct from file_mention (400+); sits after that band with
/// headroom so it does not occupy 400–409. Incremented per spawn so
/// a cancelled add cannot paint a later session's commit.
pub const git_commit_key_first: u64 = 450;

/// Waku `chars().take(200)` plus a byte cap on the runtime TextBuffer.
pub const max_commit_message: usize = 200;

pub const empty_message_status = "Enter a commit message.";
pub const commit_failed_status = "Could not commit.";

/// Add… / commit stages that share `git_commit_key` (450+).
pub const GitCommitPhase = enum(u8) {
    idle,
    add,
    commit,
};

pub const git_bin = git_branch.git_bin;
pub const git_add_cmd = "add";
pub const git_add_all_flag = "-A";
pub const git_pathspec_dash = "--";
pub const git_pathspec_dot = ".";
pub const git_commit_cmd = "commit";
pub const git_message_flag = "-m";
pub const sh_bin = git_branch.sh_bin;

pub const add_argv_len: usize = 10;
pub const commit_argv_len: usize = 9;

fn probeSupported() bool {
    return builtin.os.tag != .windows;
}

fn probePath(model: *const Model) []const u8 {
    const path = model.selectedProjectPath();
    if (path.len == 0) return "";
    const io = model.store_io orelse return "";
    if (!main.directoryExists(io, path)) return "";
    return path;
}

fn commitCwd(model: *const Model) []const u8 {
    const probed = model.git_commit_probe_path_storage[0..model.git_commit_probe_path_len];
    if (probed.len > 0) return probed;
    return probePath(model);
}

fn commitStillCurrent(model: *const Model) bool {
    if (model.git_commit_key == 0) return false;
    if (model.git_commit_probe_session != model.selected) return false;
    const path = model.selectedProjectPath();
    const probed = model.git_commit_probe_path_storage[0..model.git_commit_probe_path_len];
    return std.mem.eql(u8, path, probed);
}

fn resetCommitState(model: *Model) void {
    model.git_commit_phase = .idle;
    model.git_commit_message_len = 0;
}

fn failCommit(model: *Model) void {
    model.git_commit_key = 0;
    resetCommitState(model);
    model.setAttachStatus(commit_failed_status);
}

/// Hide while the dirty probe is in flight; show only when porcelain
/// dirty count is > 0 (staged + unstaged + untracked). Honest stand-in
/// for Waku `can_commit` with `include_unstaged=true`.
pub fn canCommitGit(model: *const Model) bool {
    if (model.git_dirty_key != 0) return false;
    return git_dirty.hasGitDirty(model);
}

/// Trim ends, take the first line, then at most 200 UTF-8 scalars
/// (Waku `chars().take(200)`). Null when the result is empty.
pub fn normalizeMessage(raw: []const u8, out: *[max_commit_message]u8) ?[]const u8 {
    const trimmed = std.mem.trim(u8, raw, " \t\r\n");
    if (trimmed.len == 0) return null;
    const line_end = std.mem.indexOfAny(u8, trimmed, "\r\n") orelse trimmed.len;
    const line = std.mem.trim(u8, trimmed[0..line_end], " \t\r\n");
    if (line.len == 0) return null;
    var n: usize = 0;
    var chars: usize = 0;
    while (n < line.len and chars < max_commit_message) {
        const taken = std.unicode.utf8ByteSequenceLength(line[n]) catch break;
        if (n + taken > line.len) break;
        if (n + taken > out.len) break;
        @memcpy(out[n .. n + taken], line[n .. n + taken]);
        n += taken;
        chars += 1;
    }
    if (n == 0) return null;
    return out[0..n];
}

pub fn addArgvFor(cwd: []const u8, buf: *[add_argv_len][]const u8) []const []const u8 {
    buf.* = .{
        sh_bin,
        "-c",
        main.fx_ask_chdir_script,
        "sh",
        cwd,
        git_bin,
        git_add_cmd,
        git_add_all_flag,
        git_pathspec_dash,
        git_pathspec_dot,
    };
    return buf;
}

pub fn isGitCommitAddArgv(argv: []const []const u8) bool {
    if (argv.len != add_argv_len) return false;
    if (!std.mem.eql(u8, argv[0], sh_bin)) return false;
    if (!std.mem.eql(u8, argv[1], "-c")) return false;
    if (!std.mem.eql(u8, argv[2], main.fx_ask_chdir_script)) return false;
    if (!std.mem.eql(u8, argv[5], git_bin)) return false;
    if (!std.mem.eql(u8, argv[6], git_add_cmd)) return false;
    if (!std.mem.eql(u8, argv[7], git_add_all_flag)) return false;
    if (!std.mem.eql(u8, argv[8], git_pathspec_dash)) return false;
    return std.mem.eql(u8, argv[9], git_pathspec_dot);
}

pub fn commitArgvFor(cwd: []const u8, message: []const u8, buf: *[commit_argv_len][]const u8) []const []const u8 {
    buf.* = .{
        sh_bin,
        "-c",
        main.fx_ask_chdir_script,
        "sh",
        cwd,
        git_bin,
        git_commit_cmd,
        git_message_flag,
        message,
    };
    return buf;
}

pub fn isGitCommitArgv(argv: []const []const u8) bool {
    if (argv.len != commit_argv_len) return false;
    if (!std.mem.eql(u8, argv[0], sh_bin)) return false;
    if (!std.mem.eql(u8, argv[1], "-c")) return false;
    if (!std.mem.eql(u8, argv[2], main.fx_ask_chdir_script)) return false;
    if (!std.mem.eql(u8, argv[5], git_bin)) return false;
    if (!std.mem.eql(u8, argv[6], git_commit_cmd)) return false;
    return std.mem.eql(u8, argv[7], git_message_flag);
}

pub fn closeCommit(model: *Model) void {
    model.git_commit_active = false;
    model.git_commit_buffer.clear();
}

fn cancelCommit(model: *Model, fx: *Effects) void {
    if (model.git_commit_key == 0) return;
    fx.cancel(model.git_commit_key);
    model.git_commit_key = 0;
    resetCommitState(model);
}

/// Drop an in-flight add/commit (session / project refresh) so a late
/// exit cannot paint a later card. Sets `Could not commit.`
pub fn cancelInFlight(model: *Model, fx: *Effects) void {
    if (model.git_commit_key == 0) return;
    cancelCommit(model, fx);
    model.setAttachStatus(commit_failed_status);
}

/// Esc / Cancel: close the card and drop an in-flight add/commit so a
/// late exit cannot spawn the next phase. Sets `Could not commit.`
/// when a spawn was live.
pub fn dismissCommit(model: *Model, fx: *Effects) void {
    const in_flight = model.git_commit_key != 0;
    cancelCommit(model, fx);
    closeCommit(model);
    if (in_flight) model.setAttachStatus(commit_failed_status);
}

/// Dismiss the select list and other git cards, then open the
/// runtime-only Commit… card. Draft message is not persisted.
/// No-op when gated, a git mutation is in flight, the session is
/// streaming, or cwd is missing.
pub fn startCommit(model: *Model) void {
    git_checkout.closePicker(model);
    git_checkout.closeCreate(model);
    git_checkout.closeWorktreeCreate(model);
    git_checkout.closeDelete(model);
    closeCommit(model);
    model.closeProjectEdit();
    if (!canCommitGit(model)) return;
    if (git_checkout.gitMutationInFlight(model)) return;
    if (model.is_streaming()) return;
    if (!probeSupported()) return;
    if (probePath(model).len == 0) return;
    model.git_commit_active = true;
}

fn spawnCommitCmd(model: *Model, fx: *Effects, cwd: []const u8, argv: []const []const u8, phase: GitCommitPhase) void {
    const key = model.next_git_commit_key;
    model.next_git_commit_key = key + 1;
    model.git_commit_key = key;
    model.git_commit_phase = phase;
    model.git_commit_probe_session = model.selected;
    const probed = model.git_commit_probe_path_storage[0..model.git_commit_probe_path_len];
    if (cwd.ptr != probed.ptr) {
        writeFixed(&model.git_commit_probe_path_storage, &model.git_commit_probe_path_len, cwd);
    }
    fx.spawn(.{
        .key = key,
        .argv = argv,
        .on_line = Effects.lineMsg(.fx_line),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
}

fn spawnAdd(model: *Model, fx: *Effects) void {
    const cwd = commitCwd(model);
    if (cwd.len == 0) {
        failCommit(model);
        return;
    }
    var argv_buf: [add_argv_len][]const u8 = undefined;
    spawnCommitCmd(model, fx, cwd, addArgvFor(cwd, &argv_buf), .add);
}

fn spawnCommit(model: *Model, fx: *Effects) void {
    const cwd = commitCwd(model);
    const message = model.git_commit_message_storage[0..model.git_commit_message_len];
    if (cwd.len == 0 or message.len == 0) {
        failCommit(model);
        return;
    }
    var argv_buf: [commit_argv_len][]const u8 = undefined;
    spawnCommitCmd(model, fx, cwd, commitArgvFor(cwd, message, &argv_buf), .commit);
}

/// Confirm the Commit… card: a non-empty normalized message one-shots
/// `git add -A -- .` then `git commit -m`. Empty / whitespace sets
/// `Enter a commit message.` and does not spawn. Gated / busy /
/// in-flight / missing cwd is a no-op.
pub fn confirmCommit(model: *Model, fx: *Effects) void {
    if (!canCommitGit(model)) return;
    if (git_checkout.gitMutationInFlight(model)) return;
    if (model.is_streaming()) return;
    if (!probeSupported()) return;
    const cwd = probePath(model);
    if (cwd.len == 0) return;

    var msg_buf: [max_commit_message]u8 = undefined;
    const message = normalizeMessage(model.git_commit_buffer.text(), &msg_buf) orelse {
        model.setAttachStatus(empty_message_status);
        return;
    };
    writeFixed(&model.git_commit_message_storage, &model.git_commit_message_len, message);
    writeFixed(&model.git_commit_probe_path_storage, &model.git_commit_probe_path_len, cwd);
    spawnAdd(model, fx);
}

pub fn applyLine(model: *Model, line: native_sdk.EffectLine) void {
    if (line.key != model.git_commit_key or model.git_commit_key == 0) return;
    _ = commitStillCurrent(model);
}

pub fn handleCommitExit(model: *Model, fx: *Effects, exit: native_sdk.EffectExit) void {
    if (exit.key != model.git_commit_key or model.git_commit_key == 0) return;
    const current = commitStillCurrent(model);
    const phase = model.git_commit_phase;
    model.git_commit_key = 0;
    if (!current) {
        resetCommitState(model);
        model.setAttachStatus(commit_failed_status);
        return;
    }
    switch (phase) {
        .idle => resetCommitState(model),
        .add => {
            if (exit.reason == .exited and exit.code == 0) {
                spawnCommit(model, fx);
                return;
            }
            failCommit(model);
        },
        .commit => {
            resetCommitState(model);
            if (exit.reason == .exited and exit.code == 0) {
                closeCommit(model);
                git_checkout.refreshWorkspaceProbes(model, fx);
                return;
            }
            model.setAttachStatus(commit_failed_status);
        },
    }
}

test "add argv is chdir script plus git add -A -- ." {
    var buf: [add_argv_len][]const u8 = undefined;
    const argv = addArgvFor("/tmp/faku-commit", &buf);
    try std.testing.expectEqual(@as(usize, 10), argv.len);
    try std.testing.expectEqualStrings(sh_bin, argv[0]);
    try std.testing.expectEqualStrings("-c", argv[1]);
    try std.testing.expectEqualStrings(main.fx_ask_chdir_script, argv[2]);
    try std.testing.expectEqualStrings("sh", argv[3]);
    try std.testing.expectEqualStrings("/tmp/faku-commit", argv[4]);
    try std.testing.expectEqualStrings(git_bin, argv[5]);
    try std.testing.expectEqualStrings(git_add_cmd, argv[6]);
    try std.testing.expectEqualStrings(git_add_all_flag, argv[7]);
    try std.testing.expectEqualStrings(git_pathspec_dash, argv[8]);
    try std.testing.expectEqualStrings(git_pathspec_dot, argv[9]);
    try std.testing.expect(isGitCommitAddArgv(argv));
    try std.testing.expect(!isGitCommitArgv(argv));
    try std.testing.expect(!git_checkout.isGitPushArgv(argv));
    try std.testing.expect(!git_checkout.isGitFetchArgv(argv));
    try std.testing.expect(std.mem.indexOf(u8, argv[2], git_add_cmd) == null);
    try std.testing.expect(std.mem.indexOf(u8, argv[2], git_add_all_flag) == null);
    try std.testing.expect(std.mem.indexOf(u8, argv[2], git_pathspec_dot) == null);
    try std.testing.expect(git_commit_key_first >= 450);
    try std.testing.expect(git_commit_key_first > file_mention.file_mention_key_first);
    try std.testing.expect(git_commit_key_first > file_mention.file_mention_key_first + 9);
}

test "commit argv is chdir script plus git commit -m and its own message slot" {
    var buf: [commit_argv_len][]const u8 = undefined;
    const argv = commitArgvFor("/tmp/faku-commit", "fix dirty count", &buf);
    try std.testing.expectEqual(@as(usize, 9), argv.len);
    try std.testing.expectEqualStrings(sh_bin, argv[0]);
    try std.testing.expectEqualStrings("-c", argv[1]);
    try std.testing.expectEqualStrings(main.fx_ask_chdir_script, argv[2]);
    try std.testing.expectEqualStrings("sh", argv[3]);
    try std.testing.expectEqualStrings("/tmp/faku-commit", argv[4]);
    try std.testing.expectEqualStrings(git_bin, argv[5]);
    try std.testing.expectEqualStrings(git_commit_cmd, argv[6]);
    try std.testing.expectEqualStrings(git_message_flag, argv[7]);
    try std.testing.expectEqualStrings("fix dirty count", argv[8]);
    try std.testing.expect(isGitCommitArgv(argv));
    try std.testing.expect(!isGitCommitAddArgv(argv));
    try std.testing.expect(!git_checkout.isGitPushArgv(argv));
    try std.testing.expect(!git_checkout.isGitFetchArgv(argv));
    try std.testing.expect(std.mem.indexOf(u8, argv[2], git_commit_cmd) == null);
    try std.testing.expect(std.mem.indexOf(u8, argv[2], git_message_flag) == null);
    try std.testing.expect(std.mem.indexOf(u8, argv[2], "fix dirty count") == null);

    var push_buf: [7][]const u8 = undefined;
    const push = git_checkout.pushArgvFor("/tmp/faku-commit", &push_buf);
    try std.testing.expect(!isGitCommitArgv(push));
    try std.testing.expect(!isGitCommitAddArgv(push));
    var fetch_buf: [8][]const u8 = undefined;
    const fetch = git_checkout.fetchArgvFor("/tmp/faku-commit", &fetch_buf);
    try std.testing.expect(!isGitCommitArgv(fetch));
    try std.testing.expect(!isGitCommitAddArgv(fetch));
}

test "empty or whitespace message does not spawn" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/git-commit-empty", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("commit empty", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);
    model.git_dirty_count = 2;
    model.git_dirty_key = 0;
    try std.testing.expect(canCommitGit(&model));

    startCommit(&model);
    try std.testing.expect(model.git_commit_active);
    confirmCommit(&model, &fx);
    try std.testing.expectEqual(@as(u64, 0), model.git_commit_key);
    try std.testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
    try std.testing.expectEqualStrings(empty_message_status, model.attach_status());

    model.git_commit_buffer.apply(.{ .insert_text = "   \n\t  " });
    model.clearAttachStatus();
    confirmCommit(&model, &fx);
    try std.testing.expectEqual(@as(u64, 0), model.git_commit_key);
    try std.testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
    try std.testing.expectEqualStrings(empty_message_status, model.attach_status());
}

test "canCommitGit hides in-flight dirty and a zero count" {
    var model = Model{};
    try std.testing.expect(!canCommitGit(&model));
    try std.testing.expect(!model.can_commit_git());

    model.git_dirty_count = 3;
    try std.testing.expect(canCommitGit(&model));
    try std.testing.expect(model.can_commit_git());

    model.git_dirty_key = git_dirty.git_dirty_key_first;
    try std.testing.expect(!canCommitGit(&model));
    try std.testing.expect(!model.can_commit_git());

    model.git_dirty_key = 0;
    model.git_dirty_count = 0;
    try std.testing.expect(!canCommitGit(&model));
}

test "add failure sets Could not commit and does not spawn commit" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/git-commit-add-fail", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("commit add fail", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);
    model.git_dirty_count = 1;
    model.git_dirty_key = 0;

    startCommit(&model);
    model.git_commit_buffer.apply(.{ .insert_text = "save work" });
    confirmCommit(&model, &fx);
    try std.testing.expectEqual(git_commit_key_first, model.git_commit_key);
    try std.testing.expectEqual(GitCommitPhase.add, model.git_commit_phase);
    try std.testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());
    const add = fx.pendingSpawnAt(0).?;
    try std.testing.expect(isGitCommitAddArgv(add.argv));
    try std.testing.expect(!isGitCommitArgv(add.argv));
    try std.testing.expect(add.key >= git_commit_key_first);
    try std.testing.expect(add.key != file_mention.file_mention_key_first);

    handleCommitExit(&model, &fx, .{ .key = add.key, .reason = .exited, .code = 1 });
    try std.testing.expectEqualStrings(commit_failed_status, model.attach_status());
    try std.testing.expectEqual(@as(u64, 0), model.git_commit_key);
    try std.testing.expectEqual(GitCommitPhase.idle, model.git_commit_phase);
    try std.testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());
    try std.testing.expect(model.git_commit_active);
}

test "commit success refreshes the same workspace probes as other git mutations" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/git-commit-ok", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("commit ok", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);
    model.git_dirty_count = 4;
    model.git_dirty_key = 0;

    startCommit(&model);
    try std.testing.expect(model.git_commit_active);
    model.git_commit_buffer.apply(.{ .insert_text = "  wrap the dirty probe  " });
    confirmCommit(&model, &fx);
    const add = fx.pendingSpawnAt(0).?;
    try std.testing.expect(isGitCommitAddArgv(add.argv));
    handleCommitExit(&model, &fx, .{ .key = add.key, .reason = .exited, .code = 0 });
    try std.testing.expect(!model.has_attach_status());
    try std.testing.expectEqual(GitCommitPhase.commit, model.git_commit_phase);
    try std.testing.expect(model.git_commit_key != 0);
    try std.testing.expect(model.git_commit_key != add.key);

    var commit_spawn: ?@TypeOf(add) = null;
    var i: usize = 0;
    while (i < fx.pendingSpawnCount()) : (i += 1) {
        const spawn = fx.pendingSpawnAt(i).?;
        if (spawn.key == model.git_commit_key and isGitCommitArgv(spawn.argv)) {
            commit_spawn = spawn;
            break;
        }
    }
    const commit = commit_spawn orelse return error.MissingGitCommitSpawn;
    try std.testing.expectEqualStrings("wrap the dirty probe", commit.argv[8]);
    try std.testing.expect(std.mem.indexOf(u8, commit.argv[2], "wrap the dirty probe") == null);
    try std.testing.expect(commit.key >= git_commit_key_first);
    try std.testing.expect(commit.key > file_mention.file_mention_key_first + 9);

    handleCommitExit(&model, &fx, .{ .key = commit.key, .reason = .exited, .code = 0 });
    try std.testing.expect(!model.git_commit_active);
    try std.testing.expectEqual(@as(u64, 0), model.git_commit_key);
    try std.testing.expect(!model.has_attach_status());
    try std.testing.expect(model.git_branch_key != 0);
    try std.testing.expect(model.git_dirty_key != 0);
    try std.testing.expect(model.git_numstat_key != 0);
    try std.testing.expect(model.git_ahead_behind_key != 0);
    try std.testing.expect(model.file_mention_key != 0);
    try std.testing.expect(model.git_branch_list_key != 0);
}

test "normalizeMessage trims, takes one line, and caps at 200 chars" {
    var buf: [max_commit_message]u8 = undefined;
    try std.testing.expect(normalizeMessage("   \n", &buf) == null);
    try std.testing.expectEqualStrings("fix probe", normalizeMessage("  fix probe  \n", &buf).?);
    try std.testing.expectEqualStrings("first", normalizeMessage("first\nsecond", &buf).?);
    var long: [240]u8 = undefined;
    @memset(long[0..], 'a');
    const capped = normalizeMessage(long[0..], &buf).?;
    try std.testing.expectEqual(@as(usize, 200), capped.len);
}

test "startCommit and confirm no-op when gated, busy, or cwd is missing" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    const id = model.addSession("commit gate", .fx);
    model.selected = id;
    model.git_dirty_count = 1;
    startCommit(&model);
    try std.testing.expect(!model.git_commit_active);
    try std.testing.expectEqual(@as(u64, 0), model.git_commit_key);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/git-commit-gate", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);
    model.store_io = std.testing.io;
    if (model.sessionById(id)) |session| session.setProjectPath(project);

    model.git_dirty_key = git_dirty.git_dirty_key_first;
    startCommit(&model);
    try std.testing.expect(!model.git_commit_active);
    model.git_dirty_key = 0;

    model.git_push_key = git_checkout.git_push_key_first;
    startCommit(&model);
    try std.testing.expect(!model.git_commit_active);
    try std.testing.expect(git_checkout.gitMutationInFlight(&model));
    model.git_push_key = 0;

    startCommit(&model);
    try std.testing.expect(model.git_commit_active);
    model.git_commit_buffer.apply(.{ .insert_text = "ok" });
    model.phase = .streaming;
    confirmCommit(&model, &fx);
    try std.testing.expectEqual(@as(u64, 0), model.git_commit_key);
    try std.testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
}
