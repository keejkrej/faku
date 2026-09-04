//! One-shot `git rev-parse --show-toplevel` canonicalize for the
//! selected session `project_path`.
//!
//! Native has no git/workspace effect. When the selected session has a
//! non-empty `project_path` that exists, Faku `fx.spawn`s
//! `git rev-parse --show-toplevel`. Every flag and operand is its own
//! argv slot — never interpolated into a script. Reuses
//! `git_checkout.git_bin` / `sh_bin` on Unix. A ready bit plus the
//! trimmed path let occupancy treat "this worktree" as `worktreepath`
//! equal to that toplevel. New worktree… nest prefers
//! `git_common_dir.zig` and falls back to this ready toplevel so
//! subdirs of the same checkout still share
//! `~/.faku/worktrees/<nest>/` while that probe is empty. Failed /
//! empty / cancel leave ready false and the path empty so consumers
//! fall back to today's `project_path` heuristic. Distinct spawn-key
//! band (490+); does not share remotes (480+) or common-dir (500+).
//! Runtime-only (not `sessions.json`). Not a live watch, not an
//! invented Native git effect, and not occupancy of linked
//! worktrees via `git-common-dir`.
//!
//! Unix uses the same `/bin/sh -c` chdir workaround `fx ask` uses
//! (`fx_ask_chdir_script`). Windows cannot use `/bin/sh`:
//! `git.exe -C <project_path> rev-parse --show-toplevel` (path is
//! its own argv slot, not interpolated into a script). Toplevel
//! stdout is the same on Windows; CRLF is already trimmed in the
//! line helpers. app.zon already includes windows. Remaining git
//! modules (common_dir, checkout/commit) still skip Windows this
//! cut. Windows numstat untracked rows stay Unix-only.
//!
//! Spawn/line/exit orchestration lives here. Effect key stays
//! `git_toplevel_key_first` (490+).

const std = @import("std");
const builtin = @import("builtin");
const native_sdk = @import("native_sdk");
const main = @import("main.zig");
const git_checkout = @import("git_checkout.zig");

const Model = main.Model;
const Effects = main.Effects;
const writeFixed = main.writeFixed;

/// One-shot `git rev-parse --show-toplevel`. Distinct from
/// git_remotes (480+), git_commit_generate (470+), and the rest of
/// the git probe bands. Band is 490+. Incremented per refresh so a
/// cancelled spawn cannot paint a later session.
pub const git_toplevel_key_first: u64 = 490;

pub const git_bin = git_checkout.git_bin;
/// PATH-resolved Windows Git (explicit `.exe` like sibling
/// `powershell.exe` / `explorer.exe` / `wt.exe` / `cmd.exe`).
pub const windows_git_bin = "git.exe";
pub const git_c_flag = "-C";
pub const sh_bin = git_checkout.sh_bin;
pub const git_show_toplevel = "--show-toplevel";

/// Unix `/bin/sh -c` chdir + git rev-parse --show-toplevel (8).
/// Windows `git.exe -C` is 5; this is the spawn buffer (max of the two).
pub const argv_len: usize = 8;
pub const unix_argv_len: usize = 8;
pub const windows_argv_len: usize = 5;

/// Unix: same 8-slot chdir script + `git rev-parse --show-toplevel`.
pub fn unixArgvFor(cwd: []const u8, buf: *[argv_len][]const u8) []const []const u8 {
    buf.* = .{
        sh_bin,
        "-c",
        main.fx_ask_chdir_script,
        "sh",
        cwd,
        git_bin,
        git_checkout.git_rev_parse_cmd,
        git_show_toplevel,
    };
    return buf[0..unix_argv_len];
}

/// Windows: `git.exe -C <project_path> rev-parse --show-toplevel`.
/// Path is its own argv slot (no `/bin/sh`, no packing into a cmd
/// string).
pub fn windowsArgvFor(cwd: []const u8, buf: *[argv_len][]const u8) []const []const u8 {
    buf[0] = windows_git_bin;
    buf[1] = git_c_flag;
    buf[2] = cwd;
    buf[3] = git_checkout.git_rev_parse_cmd;
    buf[4] = git_show_toplevel;
    return buf[0..windows_argv_len];
}

pub fn argvFor(cwd: []const u8, buf: *[argv_len][]const u8) []const []const u8 {
    return switch (builtin.os.tag) {
        .windows => windowsArgvFor(cwd, buf),
        else => unixArgvFor(cwd, buf),
    };
}

fn isUnixGitToplevelArgv(argv: []const []const u8) bool {
    if (argv.len != unix_argv_len) return false;
    if (!std.mem.eql(u8, argv[0], sh_bin)) return false;
    if (!std.mem.eql(u8, argv[1], "-c")) return false;
    if (!std.mem.eql(u8, argv[2], main.fx_ask_chdir_script)) return false;
    if (!std.mem.eql(u8, argv[5], git_bin)) return false;
    if (!std.mem.eql(u8, argv[6], git_checkout.git_rev_parse_cmd)) return false;
    return std.mem.eql(u8, argv[7], git_show_toplevel);
}

fn isWindowsGitToplevelArgv(argv: []const []const u8) bool {
    if (argv.len != windows_argv_len) return false;
    const bin_ok = std.mem.eql(u8, argv[0], windows_git_bin) or std.mem.eql(u8, argv[0], git_bin);
    if (!bin_ok) return false;
    if (!std.mem.eql(u8, argv[1], git_c_flag)) return false;
    if (argv[2].len == 0) return false;
    if (!std.mem.eql(u8, argv[3], git_checkout.git_rev_parse_cmd)) return false;
    return std.mem.eql(u8, argv[4], git_show_toplevel);
}

pub fn isGitToplevelArgv(argv: []const []const u8) bool {
    return isUnixGitToplevelArgv(argv) or isWindowsGitToplevelArgv(argv);
}

pub fn probeSupported() bool {
    return true;
}

/// First stdout line, trimmed. Empty / whitespace is not a path.
pub fn firstStdoutLine(raw: []const u8) []const u8 {
    const trimmed = std.mem.trim(u8, raw, " \t\r\n");
    if (trimmed.len == 0) return "";
    const end = std.mem.indexOfAny(u8, trimmed, "\r\n") orelse trimmed.len;
    return std.mem.trim(u8, trimmed[0..end], " \t");
}

/// Accept a show-toplevel path. Reject empty / `..` / NUL / overflow
/// of `session.max_project_path` so a truncated root is never stored.
pub fn parseToplevelLine(raw: []const u8) []const u8 {
    const line = firstStdoutLine(raw);
    if (line.len == 0 or line.len > main.max_project_path) return "";
    if (std.mem.indexOf(u8, line, "..") != null) return "";
    if (std.mem.indexOfScalar(u8, line, 0) != null) return "";
    return line;
}

pub fn gitToplevelPath(model: *const Model) []const u8 {
    return model.git_toplevel_path_storage[0..model.git_toplevel_path_len];
}

/// Ready canonical toplevel, or empty when the probe is in flight /
/// failed / never finished (consumers fall back).
pub fn readyPath(model: *const Model) []const u8 {
    if (model.git_toplevel_key != 0) return "";
    if (!model.git_toplevel_ready) return "";
    return gitToplevelPath(model);
}

pub fn clearGitToplevel(model: *Model) void {
    model.git_toplevel_ready = false;
    model.git_toplevel_path_len = 0;
}

fn cancelInFlight(model: *Model, fx: *Effects) void {
    if (model.git_toplevel_key == 0) return;
    fx.cancel(model.git_toplevel_key);
    model.git_toplevel_key = 0;
}

fn probePath(model: *const Model) []const u8 {
    const path = model.selectedProjectPath();
    if (path.len == 0) return "";
    const io = model.store_io orelse return "";
    if (!main.directoryExists(io, path)) return "";
    return path;
}

/// Cancel any in-flight probe, drop ready/path, and spawn again when
/// the selected session has an existing `project_path`. Empty /
/// missing skips the spawn so consumers keep the fallback.
pub fn refresh(model: *Model, fx: *Effects) void {
    cancelInFlight(model, fx);
    clearGitToplevel(model);
    if (!probeSupported()) return;
    const cwd = probePath(model);
    if (cwd.len == 0) return;

    const key = model.next_git_toplevel_key;
    model.next_git_toplevel_key = key + 1;
    model.git_toplevel_key = key;
    model.git_toplevel_probe_session = model.selected;
    writeFixed(&model.git_toplevel_probe_path_storage, &model.git_toplevel_probe_path_len, cwd);

    var argv_buf: [argv_len][]const u8 = undefined;
    fx.spawn(.{
        .key = key,
        .argv = argvFor(cwd, &argv_buf),
        .on_line = Effects.lineMsg(.fx_line),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
}

fn probeStillCurrent(model: *const Model) bool {
    if (model.git_toplevel_key == 0) return false;
    if (model.git_toplevel_probe_session != model.selected) return false;
    const path = model.selectedProjectPath();
    const probed = model.git_toplevel_probe_path_storage[0..model.git_toplevel_probe_path_len];
    return std.mem.eql(u8, path, probed);
}

pub fn applyLine(model: *Model, line: native_sdk.EffectLine) void {
    if (line.key != model.git_toplevel_key or model.git_toplevel_key == 0) return;
    if (!probeStillCurrent(model)) return;
    const parsed = parseToplevelLine(line.line);
    if (parsed.len == 0) return;
    writeFixed(&model.git_toplevel_path_storage, &model.git_toplevel_path_len, parsed);
}

pub fn handleExit(model: *Model, exit: native_sdk.EffectExit) void {
    if (exit.key != model.git_toplevel_key or model.git_toplevel_key == 0) return;
    const current = probeStillCurrent(model);
    model.git_toplevel_key = 0;
    if (!current or exit.reason != .exited or exit.code != 0) {
        clearGitToplevel(model);
        return;
    }
    if (parseToplevelLine(gitToplevelPath(model)).len == 0) {
        clearGitToplevel(model);
        return;
    }
    model.git_toplevel_ready = true;
}

test "argv is chdir script plus git rev-parse --show-toplevel as own slots" {
    const git_remotes = @import("git_remotes.zig");
    var buf: [argv_len][]const u8 = undefined;
    const argv = unixArgvFor("/tmp/faku-toplevel", &buf);
    try std.testing.expectEqual(@as(usize, unix_argv_len), argv.len);
    try std.testing.expectEqualStrings(sh_bin, argv[0]);
    try std.testing.expectEqualStrings("-c", argv[1]);
    try std.testing.expectEqualStrings(main.fx_ask_chdir_script, argv[2]);
    try std.testing.expectEqualStrings("sh", argv[3]);
    try std.testing.expectEqualStrings("/tmp/faku-toplevel", argv[4]);
    try std.testing.expectEqualStrings(git_bin, argv[5]);
    try std.testing.expectEqualStrings(git_checkout.git_rev_parse_cmd, argv[6]);
    try std.testing.expectEqualStrings(git_show_toplevel, argv[7]);
    try std.testing.expect(isGitToplevelArgv(argv));
    try std.testing.expect(std.mem.indexOf(u8, argv[2], git_checkout.git_rev_parse_cmd) == null);
    try std.testing.expect(std.mem.indexOf(u8, argv[2], git_show_toplevel) == null);
    try std.testing.expect(!isGitToplevelArgv(&.{ git_bin, git_checkout.git_rev_parse_cmd, git_show_toplevel }));
    var remotes_buf: [git_remotes.argv_len][]const u8 = undefined;
    const remotes = git_remotes.unixArgvFor("/tmp/faku-toplevel", &remotes_buf);
    try std.testing.expect(!isGitToplevelArgv(remotes));
    try std.testing.expect(!git_remotes.isGitRemotesArgv(argv));
    try std.testing.expect(git_toplevel_key_first >= 490);
    try std.testing.expect(git_toplevel_key_first > git_remotes.git_remotes_key_first);
    try std.testing.expect(git_remotes.git_remotes_key_first >= 480);
}

test "windows git argv is git.exe -C PATH rev-parse --show-toplevel; path is its own slot" {
    const git_branch = @import("git_branch.zig");
    const git_dirty = @import("git_dirty.zig");
    const git_ahead_behind = @import("git_ahead_behind.zig");
    const git_numstat = @import("git_numstat.zig");
    const git_remotes = @import("git_remotes.zig");
    const file_mention = @import("file_mention.zig");
    var buf: [argv_len][]const u8 = undefined;
    const cwd = "C:\\Users\\me\\proj";
    const argv = windowsArgvFor(cwd, &buf);
    try std.testing.expectEqual(@as(usize, windows_argv_len), argv.len);
    try std.testing.expect(argv.len <= 16);
    try std.testing.expectEqualStrings(windows_git_bin, argv[0]);
    try std.testing.expectEqualStrings(git_c_flag, argv[1]);
    try std.testing.expectEqualStrings(cwd, argv[2]);
    try std.testing.expectEqualStrings(git_checkout.git_rev_parse_cmd, argv[3]);
    try std.testing.expectEqualStrings(git_show_toplevel, argv[4]);
    try std.testing.expect(isGitToplevelArgv(argv));
    try std.testing.expect(!std.mem.eql(u8, argv[0], sh_bin));
    try std.testing.expect(!isGitToplevelArgv(&.{ windows_git_bin, git_c_flag, cwd }));
    try std.testing.expect(!isGitToplevelArgv(&.{
        windows_git_bin,
        git_c_flag,
        cwd,
        git_checkout.git_rev_parse_cmd,
    }));
    var git_only: [argv_len][]const u8 = undefined;
    git_only[0] = git_bin;
    git_only[1] = git_c_flag;
    git_only[2] = cwd;
    git_only[3] = git_checkout.git_rev_parse_cmd;
    git_only[4] = git_show_toplevel;
    try std.testing.expect(isGitToplevelArgv(git_only[0..windows_argv_len]));
    var remotes_buf: [git_remotes.argv_len][]const u8 = undefined;
    try std.testing.expect(!isGitToplevelArgv(git_remotes.windowsArgvFor(cwd, &remotes_buf)));
    try std.testing.expect(!git_remotes.isGitRemotesArgv(argv));
    var branch_buf: [git_branch.argv_len][]const u8 = undefined;
    try std.testing.expect(!isGitToplevelArgv(git_branch.windowsArgvFor(cwd, &branch_buf)));
    try std.testing.expect(!git_branch.isGitBranchArgv(argv));
    var dirty_buf: [git_dirty.argv_len][]const u8 = undefined;
    try std.testing.expect(!isGitToplevelArgv(git_dirty.windowsArgvFor(cwd, &dirty_buf)));
    try std.testing.expect(!git_dirty.isGitDirtyArgv(argv));
    var ahead_buf: [git_ahead_behind.argv_len][]const u8 = undefined;
    try std.testing.expect(!isGitToplevelArgv(git_ahead_behind.windowsArgvFor(cwd, &ahead_buf)));
    try std.testing.expect(!git_ahead_behind.isGitAheadBehindArgv(argv));
    var numstat_buf: [git_numstat.argv_len][]const u8 = undefined;
    try std.testing.expect(!isGitToplevelArgv(git_numstat.windowsArgvFor(cwd, &numstat_buf)));
    try std.testing.expect(!git_numstat.isGitNumstatArgv(argv));
    var mention_buf: [file_mention.git_argv_len][]const u8 = undefined;
    try std.testing.expect(!isGitToplevelArgv(file_mention.windowsArgvFor(cwd, &mention_buf)));
    try std.testing.expect(!file_mention.isGitLsFilesArgv(argv));
}

test "host argvFor matches the process OS" {
    var buf: [argv_len][]const u8 = undefined;
    const argv = argvFor("/tmp/faku-toplevel", &buf);
    try std.testing.expect(isGitToplevelArgv(argv));
    switch (builtin.os.tag) {
        .windows => {
            try std.testing.expectEqualStrings(windows_git_bin, argv[0]);
            try std.testing.expectEqualStrings(git_c_flag, argv[1]);
            try std.testing.expectEqualStrings(git_checkout.git_rev_parse_cmd, argv[3]);
            try std.testing.expectEqualStrings(git_show_toplevel, argv[4]);
        },
        else => {
            try std.testing.expectEqualStrings(sh_bin, argv[0]);
            try std.testing.expectEqualStrings(git_show_toplevel, argv[7]);
        },
    }
}

test "probeSupported is true on macOS, Linux, and Windows" {
    try std.testing.expect(probeSupported());
}

test "refresh one-shots show-toplevel on a distinct key; empty fail and success" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/git-toplevel", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("toplevel probe", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);

    refresh(&model, &fx);
    try std.testing.expectEqual(git_toplevel_key_first, model.git_toplevel_key);
    try std.testing.expect(!model.git_toplevel_ready);
    try std.testing.expectEqual(@as(usize, 0), model.git_toplevel_path_len);
    try std.testing.expectEqualStrings("", readyPath(&model));
    try std.testing.expect(!git_checkout.gitMutationInFlight(&model));

    var found: ?@TypeOf(fx.pendingSpawnAt(0).?) = null;
    var i: usize = 0;
    while (i < fx.pendingSpawnCount()) : (i += 1) {
        const spawn = fx.pendingSpawnAt(i).?;
        if (spawn.key == model.git_toplevel_key and isGitToplevelArgv(spawn.argv)) {
            found = spawn;
            break;
        }
    }
    const spawn = found orelse return error.MissingGitToplevelSpawn;
    try std.testing.expect(spawn.key >= git_toplevel_key_first);
    try std.testing.expect(spawn.key != git_checkout.git_push_key_first);
    switch (builtin.os.tag) {
        .windows => {
            try std.testing.expectEqualStrings(project, spawn.argv[2]);
            try std.testing.expectEqualStrings(git_show_toplevel, spawn.argv[spawn.argv.len - 1]);
        },
        else => {
            try std.testing.expectEqualStrings(project, spawn.argv[4]);
            try std.testing.expectEqualStrings(git_show_toplevel, spawn.argv[7]);
            try std.testing.expect(std.mem.indexOf(u8, spawn.argv[2], git_show_toplevel) == null);
        },
    }

    applyLine(&model, .{ .key = spawn.key, .line = "  /tmp/canonical-root  \n" });
    try std.testing.expectEqualStrings("/tmp/canonical-root", gitToplevelPath(&model));
    try std.testing.expect(!model.git_toplevel_ready);
    handleExit(&model, .{ .key = spawn.key, .reason = .exited, .code = 0 });
    try std.testing.expectEqual(@as(u64, 0), model.git_toplevel_key);
    try std.testing.expect(model.git_toplevel_ready);
    try std.testing.expectEqualStrings("/tmp/canonical-root", readyPath(&model));

    refresh(&model, &fx);
    const key2 = model.git_toplevel_key;
    try std.testing.expect(key2 != spawn.key);
    try std.testing.expect(!model.git_toplevel_ready);
    try std.testing.expectEqualStrings("", readyPath(&model));
    handleExit(&model, .{ .key = key2, .reason = .exited, .code = 0 });
    try std.testing.expect(!model.git_toplevel_ready);
    try std.testing.expectEqualStrings("", readyPath(&model));

    refresh(&model, &fx);
    const key3 = model.git_toplevel_key;
    applyLine(&model, .{ .key = key3, .line = "/tmp/should-clear\n" });
    handleExit(&model, .{ .key = key3, .reason = .exited, .code = 1 });
    try std.testing.expect(!model.git_toplevel_ready);
    try std.testing.expectEqualStrings("", readyPath(&model));

    refresh(&model, &fx);
    const key4 = model.git_toplevel_key;
    applyLine(&model, .{ .key = key4, .line = "..\n" });
    handleExit(&model, .{ .key = key4, .reason = .exited, .code = 0 });
    try std.testing.expect(!model.git_toplevel_ready);
    try std.testing.expectEqualStrings("", readyPath(&model));
}

test "session change drops an in-flight toplevel probe" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var a_buf: [256]u8 = undefined;
    var b_buf: [256]u8 = undefined;
    const project_a = try std.fmt.bufPrint(&a_buf, ".zig-cache/tmp/{s}/git-toplevel-a", .{tmp.sub_path[0..]});
    const project_b = try std.fmt.bufPrint(&b_buf, ".zig-cache/tmp/{s}/git-toplevel-b", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project_a);
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project_b);

    var model = Model{};
    model.store_io = std.testing.io;
    const first = model.addSession("toplevel a", .fx);
    const second = model.addSession("toplevel b", .fx);
    model.selected = first;
    if (model.sessionById(first)) |session| session.setProjectPath(project_a);
    if (model.sessionById(second)) |session| session.setProjectPath(project_b);

    refresh(&model, &fx);
    const first_key = model.git_toplevel_key;
    applyLine(&model, .{ .key = first_key, .line = "/tmp/first-root\n" });
    try std.testing.expectEqualStrings("/tmp/first-root", gitToplevelPath(&model));

    model.selected = second;
    refresh(&model, &fx);
    try std.testing.expect(model.git_toplevel_key != first_key);
    try std.testing.expectEqualStrings("", gitToplevelPath(&model));
    applyLine(&model, .{ .key = first_key, .line = "/tmp/stale-root\n" });
    handleExit(&model, .{ .key = first_key, .reason = .exited, .code = 0 });
    try std.testing.expect(!model.git_toplevel_ready);
    try std.testing.expectEqualStrings("", readyPath(&model));
}

test "ready toplevel occupancy and nest key share the repo root" {
    var model = Model{};
    const id = model.addSession("toplevel occupancy", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath("/tmp/proj/src");

    try std.testing.expect(git_checkout.isThisWorktreePath("/tmp/proj", "/tmp/proj/src"));
    try std.testing.expect(!git_checkout.isThisWorktreePath("/tmp/other-worktree", "/tmp/proj/src"));
    try std.testing.expect(git_checkout.isThisWorktreePathFor("/tmp/proj", "/tmp/proj/src", &model));

    var nest_raw_buf: [git_checkout.worktree_nest_key_len]u8 = undefined;
    var nest_top_buf: [git_checkout.worktree_nest_key_len]u8 = undefined;
    var nest_model_buf: [git_checkout.worktree_nest_key_len]u8 = undefined;
    const nest_raw = git_checkout.worktreeNestKey("/tmp/proj/src", nest_raw_buf[0..]).?;
    const nest_top = git_checkout.worktreeNestKey("/tmp/proj", nest_top_buf[0..]).?;
    try std.testing.expect(!std.mem.eql(u8, nest_raw, nest_top));
    try std.testing.expectEqualStrings(nest_raw, git_checkout.worktreeNestKeyFor("/tmp/proj/src", nest_model_buf[0..], &model).?);

    writeFixed(&model.git_toplevel_path_storage, &model.git_toplevel_path_len, "/tmp/proj");
    model.git_toplevel_ready = true;
    try std.testing.expectEqualStrings("/tmp/proj", readyPath(&model));
    try std.testing.expect(git_checkout.isThisWorktreePathFor("/tmp/proj", "/tmp/proj/src", &model));
    try std.testing.expect(!git_checkout.isThisWorktreePathFor("/tmp/other-worktree", "/tmp/proj/src", &model));
    try std.testing.expectEqualStrings(nest_top, git_checkout.worktreeNestKeyFor("/tmp/proj/src", nest_model_buf[0..], &model).?);
    try std.testing.expect(!git_checkout.localHeadOccupiedFor(false, "/tmp/proj", "/tmp/proj/src", &model));
    try std.testing.expect(git_checkout.localHeadOccupiedFor(false, "/tmp/other-worktree", "/tmp/proj/src", &model));
}
