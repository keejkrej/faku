//! One-shot file probe for composer `@` mentions.
//!
//! Native has no git/workspace/file-index effect. When the selected
//! session has a non-empty `project_path` that exists, Faku `fx.spawn`s
//! `git ls-files --cached --others --exclude-standard` through the
//! same `/bin/sh -c` chdir workaround `fx ask` uses
//! (`fx_ask_chdir_script`). Git is authoritative for a repo: success
//! with zero files stays empty (do not walk — that would dump
//! `node_modules`). Only when that spawn cannot run or exits
//! non-zero does a bounded `find` walk fill the same runtime cache.
//! First-N stdout paths stay on the Model — not `sessions.json`.
//!
//! Not Waku's 50k-file index or caret-aware trigger. Visible `@`
//! rows are scored over this bounded file cache (plus derived parent
//! directories at row time) in `composer.fileMentionScore` — not
//! first-N contains in cache order. The sidecar stdout and this
//! cache stay files-only. Windows stays empty this cut. Not
//! Open-in, not copy path, not a daemon catalog.
//!
//! Spawn/line/exit orchestration lives here. Windows is skipped
//! (app.zon is macos/linux; no Windows spawn path).

const std = @import("std");
const builtin = @import("builtin");
const native_sdk = @import("native_sdk");
const main = @import("main.zig");

const Model = main.Model;
const Effects = main.Effects;
const writeFixed = main.writeFixed;

/// One-shot file-mention probe (git ls-files, then a bounded walk
/// when git cannot list). Distinct from git_branch (200+), maximize /
/// pick-image / fx-ask / daemon / clipboard / probe keys. Incremented
/// per spawn so a cancelled probe cannot paint a later session.
pub const file_mention_key_first: u64 = 400;

pub const max_file_mentions: usize = 256;
pub const max_file_mention_path: usize = 255;
/// Same visible-row cap as the command palette task section.
pub const file_mention_visible_cap: usize = 12;
/// 1-based file-cache ids are `1..=max_file_mentions`. Derived dir
/// ids start here so `insert_mention:{m.id}` cannot collide.
pub const file_mention_dir_id_base: u32 = 1000;
pub const max_file_mention_dirs: usize = 256;

pub const git_bin = "git";
pub const git_ls_files_cmd = "ls-files";
pub const git_ls_files_cached = "--cached";
pub const git_ls_files_others = "--others";
pub const git_ls_files_exclude_standard = "--exclude-standard";
pub const sh_bin = "/bin/sh";

pub const find_bin = "find";
pub const find_start = ".";
pub const find_maxdepth_flag = "-maxdepth";
pub const find_maxdepth = "8";
pub const find_not = "!";
pub const find_name_flag = "-name";
pub const find_paren_open = "(";
pub const find_paren_close = ")";
pub const find_or = "-o";
pub const find_prune = "-prune";
pub const find_type_flag = "-type";
pub const find_type_file = "f";
pub const find_print = "-print";
pub const find_dot_star = ".*";
pub const walk_skip_node_modules = "node_modules";
pub const walk_skip_target = "target";
pub const walk_skip_dist = "dist";
pub const walk_skip_build = "build";
pub const walk_skip_out = "out";
pub const walk_skip_vendor = "vendor";
pub const walk_skip_pycache = "__pycache__";
pub const walk_skip_names = [_][]const u8{
    walk_skip_node_modules,
    walk_skip_target,
    walk_skip_dist,
    walk_skip_build,
    walk_skip_out,
    walk_skip_vendor,
    walk_skip_pycache,
};

const git_argv_len: usize = 10;
/// `/bin/sh -c` chdir + `find . -maxdepth 8 ! -name . ( skips ) -prune -o -type f -print`.
/// `! -name .` keeps the start point from matching `-name .*` and pruning the tree.
const walk_argv_len: usize = 42;

pub const CachedPath = struct {
    storage: [max_file_mention_path]u8 = [_]u8{0} ** max_file_mention_path,
    len: usize = 0,

    pub fn text(self: *const CachedPath) []const u8 {
        return self.storage[0..self.len];
    }

    pub fn set(self: *CachedPath, path: []const u8) void {
        writeFixed(&self.storage, &self.len, path);
    }
};

pub fn argvFor(cwd: []const u8, buf: *[git_argv_len][]const u8) []const []const u8 {
    buf.* = .{
        sh_bin,
        "-c",
        main.fx_ask_chdir_script,
        "sh",
        cwd,
        git_bin,
        git_ls_files_cmd,
        git_ls_files_cached,
        git_ls_files_others,
        git_ls_files_exclude_standard,
    };
    return buf;
}

pub fn isGitLsFilesArgv(argv: []const []const u8) bool {
    if (argv.len != git_argv_len) return false;
    if (!std.mem.eql(u8, argv[0], sh_bin)) return false;
    if (!std.mem.eql(u8, argv[1], "-c")) return false;
    if (!std.mem.eql(u8, argv[2], main.fx_ask_chdir_script)) return false;
    if (!std.mem.eql(u8, argv[5], git_bin)) return false;
    if (!std.mem.eql(u8, argv[6], git_ls_files_cmd)) return false;
    if (!std.mem.eql(u8, argv[7], git_ls_files_cached)) return false;
    if (!std.mem.eql(u8, argv[8], git_ls_files_others)) return false;
    return std.mem.eql(u8, argv[9], git_ls_files_exclude_standard);
}

pub fn walkArgvFor(cwd: []const u8, buf: *[walk_argv_len][]const u8) []const []const u8 {
    buf.* = .{
        sh_bin,
        "-c",
        main.fx_ask_chdir_script,
        "sh",
        cwd,
        find_bin,
        find_start,
        find_maxdepth_flag,
        find_maxdepth,
        find_not,
        find_name_flag,
        find_start,
        find_paren_open,
        find_name_flag,
        walk_skip_node_modules,
        find_or,
        find_name_flag,
        walk_skip_target,
        find_or,
        find_name_flag,
        walk_skip_dist,
        find_or,
        find_name_flag,
        walk_skip_build,
        find_or,
        find_name_flag,
        walk_skip_out,
        find_or,
        find_name_flag,
        walk_skip_vendor,
        find_or,
        find_name_flag,
        walk_skip_pycache,
        find_or,
        find_name_flag,
        find_dot_star,
        find_paren_close,
        find_prune,
        find_or,
        find_type_flag,
        find_type_file,
        find_print,
    };
    return buf;
}

fn argvHas(argv: []const []const u8, needle: []const u8) bool {
    for (argv) |arg| {
        if (std.mem.eql(u8, arg, needle)) return true;
    }
    return false;
}

pub fn isWalkArgv(argv: []const []const u8) bool {
    if (argv.len != walk_argv_len) return false;
    if (!std.mem.eql(u8, argv[0], sh_bin)) return false;
    if (!std.mem.eql(u8, argv[1], "-c")) return false;
    if (!std.mem.eql(u8, argv[2], main.fx_ask_chdir_script)) return false;
    if (!std.mem.eql(u8, argv[5], find_bin)) return false;
    if (!std.mem.eql(u8, argv[6], find_start)) return false;
    if (!argvHas(argv, find_maxdepth_flag)) return false;
    if (!argvHas(argv, find_maxdepth)) return false;
    if (!argvHas(argv, find_prune)) return false;
    if (!argvHas(argv, find_type_file)) return false;
    if (!argvHas(argv, find_print)) return false;
    if (!argvHas(argv, find_dot_star)) return false;
    inline for (walk_skip_names) |name| {
        if (!argvHas(argv, name)) return false;
    }
    return true;
}

pub fn probeSupported() bool {
    return builtin.os.tag != .windows;
}

pub fn cachedCount(model: *const Model) u32 {
    return model.file_mention_count;
}

pub fn cachedPath(model: *const Model, index: usize) []const u8 {
    if (index >= model.file_mention_count) return "";
    return model.file_mention_store[index].text();
}

pub fn fileMentionId(index: usize) u32 {
    return @intCast(index + 1);
}

pub fn dirMentionId(index: usize) u32 {
    return file_mention_dir_id_base + @as(u32, @intCast(index));
}

/// Unique ancestor directories of cached file paths, without a trailing
/// slash. First-seen order (cache order, leaf-to-root). Skips `""` and
/// `.` so a file at the repo root does not yield a `.` / empty dir.
pub fn collectDerivedDirParents(paths: []const []const u8, out: [][]const u8) usize {
    var n: usize = 0;
    for (paths) |file| {
        var path = file;
        while (std.mem.lastIndexOfScalar(u8, path, '/')) |index| {
            path = path[0..index];
            if (skipDerivedDir(path)) continue;
            if (containsPath(out[0..n], path)) break;
            if (n == out.len) return n;
            out[n] = path;
            n += 1;
        }
    }
    return n;
}

fn skipDerivedDir(path: []const u8) bool {
    if (path.len == 0) return true;
    const name = if (std.mem.lastIndexOfScalar(u8, path, '/')) |slash|
        path[slash + 1 ..]
    else
        path;
    return name.len == 0 or std.mem.eql(u8, name, ".");
}

fn containsPath(haystack: []const []const u8, needle: []const u8) bool {
    for (haystack) |item| {
        if (std.mem.eql(u8, item, needle)) return true;
    }
    return false;
}

pub fn derivedDirParents(model: *const Model, out: [][]const u8) usize {
    var file_paths: [max_file_mentions][]const u8 = undefined;
    const n = model.file_mention_count;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        file_paths[i] = cachedPath(model, i);
    }
    return collectDerivedDirParents(file_paths[0..n], out);
}

/// Resolve a mention-row id to the insert path. File ids are 1-based
/// cache indexes. Dir ids are `file_mention_dir_id_base + index` and
/// write `parent/` into `dir_out`.
pub fn mentionRelpath(model: *const Model, id: u32, dir_out: []u8) ?[]const u8 {
    if (id == 0) return null;
    if (id >= file_mention_dir_id_base) {
        const dir_index = id - file_mention_dir_id_base;
        var parents: [max_file_mention_dirs][]const u8 = undefined;
        const n = derivedDirParents(model, &parents);
        if (dir_index >= n) return null;
        return std.fmt.bufPrint(dir_out, "{s}/", .{parents[dir_index]}) catch null;
    }
    if (id > model.file_mention_count) return null;
    const path = cachedPath(model, id - 1);
    if (path.len == 0) return null;
    return path;
}

pub fn clearCache(model: *Model) void {
    model.file_mention_count = 0;
}

fn cancelInFlight(model: *Model, fx: *Effects) void {
    if (model.file_mention_key == 0) return;
    fx.cancel(model.file_mention_key);
    model.file_mention_key = 0;
}

fn probePath(model: *const Model) []const u8 {
    const path = model.selectedProjectPath();
    if (path.len == 0) return "";
    const io = model.store_io orelse return "";
    if (!main.directoryExists(io, path)) return "";
    return path;
}

/// Cancel any in-flight probe, drop the cache, and spawn git ls-files
/// when the selected session has an existing `project_path`. Empty /
/// missing / Windows skips both git and the walk so the mention list
/// stays hidden. A failed git spawn falls back to the walk in
/// `handleExit`.
pub fn refresh(model: *Model, fx: *Effects) void {
    cancelInFlight(model, fx);
    clearCache(model);
    if (!probeSupported()) return;
    const cwd = probePath(model);
    if (cwd.len == 0) return;

    model.file_mention_probe_session = model.selected;
    writeFixed(&model.file_mention_probe_path_storage, &model.file_mention_probe_path_len, cwd);
    spawnGit(model, fx, cwd);
}

fn spawnGit(model: *Model, fx: *Effects, cwd: []const u8) void {
    const key = model.next_file_mention_key;
    model.next_file_mention_key = key + 1;
    model.file_mention_key = key;
    model.file_mention_probe_is_walk = false;
    var argv_buf: [git_argv_len][]const u8 = undefined;
    fx.spawn(.{
        .key = key,
        .argv = argvFor(cwd, &argv_buf),
        .on_line = Effects.lineMsg(.fx_line),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
}

fn spawnWalk(model: *Model, fx: *Effects, cwd: []const u8) void {
    const key = model.next_file_mention_key;
    model.next_file_mention_key = key + 1;
    model.file_mention_key = key;
    model.file_mention_probe_is_walk = true;
    var argv_buf: [walk_argv_len][]const u8 = undefined;
    fx.spawn(.{
        .key = key,
        .argv = walkArgvFor(cwd, &argv_buf),
        .on_line = Effects.lineMsg(.fx_line),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
}

fn probeStillCurrent(model: *const Model) bool {
    if (model.file_mention_key == 0) return false;
    if (model.file_mention_probe_session != model.selected) return false;
    const path = model.selectedProjectPath();
    const probed = model.file_mention_probe_path_storage[0..model.file_mention_probe_path_len];
    return std.mem.eql(u8, path, probed);
}

/// Strip a leading `./` (`find -print` emits `./src/a.zig`; git does
/// not). `.` and empty are not files.
pub fn normalizeStdoutPath(raw: []const u8) []const u8 {
    const trimmed = std.mem.trim(u8, raw, " \t\r\n");
    const path = if (std.mem.startsWith(u8, trimmed, "./")) trimmed[2..] else trimmed;
    if (path.len == 0 or std.mem.eql(u8, path, ".")) return "";
    return path;
}

/// Append trimmed non-empty stdout paths until `max_file_mentions`.
/// Later lines are dropped — this is not Waku's 50k-file index.
pub fn applyStdoutPaths(model: *Model, raw: []const u8) void {
    var it = std.mem.splitScalar(u8, raw, '\n');
    while (it.next()) |line| {
        if (model.file_mention_count >= max_file_mentions) return;
        const path = normalizeStdoutPath(line);
        if (path.len == 0) continue;
        model.file_mention_store[model.file_mention_count].set(path);
        model.file_mention_count += 1;
    }
}

pub fn applyLine(model: *Model, line: native_sdk.EffectLine) void {
    if (line.key != model.file_mention_key or model.file_mention_key == 0) return;
    if (!probeStillCurrent(model)) return;
    applyStdoutPaths(model, line.line);
}

pub fn handleExit(model: *Model, fx: *Effects, exit: native_sdk.EffectExit) void {
    if (exit.key != model.file_mention_key or model.file_mention_key == 0) return;
    const current = probeStillCurrent(model);
    const was_walk = model.file_mention_probe_is_walk;
    model.file_mention_key = 0;
    const succeeded = exit.reason == .exited and exit.code == 0;
    if (succeeded and current) return;
    clearCache(model);
    if (!current or was_walk or !probeSupported()) return;
    const cwd = model.file_mention_probe_path_storage[0..model.file_mention_probe_path_len];
    if (cwd.len == 0) return;
    spawnWalk(model, fx, cwd);
}

test "argv is chdir script plus git ls-files cached/others; not git branch" {
    const git_branch = @import("git_branch.zig");
    var buf: [git_argv_len][]const u8 = undefined;
    const argv = argvFor("/tmp/faku-ls", &buf);
    try std.testing.expectEqualStrings(sh_bin, argv[0]);
    try std.testing.expectEqualStrings("-c", argv[1]);
    try std.testing.expectEqualStrings(main.fx_ask_chdir_script, argv[2]);
    try std.testing.expectEqualStrings("sh", argv[3]);
    try std.testing.expectEqualStrings("/tmp/faku-ls", argv[4]);
    try std.testing.expectEqualStrings(git_bin, argv[5]);
    try std.testing.expectEqualStrings(git_ls_files_cmd, argv[6]);
    try std.testing.expectEqualStrings(git_ls_files_cached, argv[7]);
    try std.testing.expectEqualStrings(git_ls_files_others, argv[8]);
    try std.testing.expectEqualStrings(git_ls_files_exclude_standard, argv[9]);
    try std.testing.expect(isGitLsFilesArgv(argv));
    try std.testing.expect(!isGitLsFilesArgv(&.{ git_bin, git_ls_files_cmd }));
    try std.testing.expect(!isGitLsFilesArgv(&.{
        sh_bin,
        "-c",
        main.fx_ask_chdir_script,
        "sh",
        "/tmp/faku-ls",
        git_bin,
        git_ls_files_cmd,
    }));
    try std.testing.expect(!git_branch.isGitBranchArgv(argv));
    var branch_buf: [8][]const u8 = undefined;
    const branch = git_branch.argvFor("/tmp/faku-ls", &branch_buf);
    try std.testing.expect(!isGitLsFilesArgv(branch));
    try std.testing.expect(file_mention_key_first > git_branch.git_branch_key_first);
}

test "walk argv is chdir script plus find maxdepth 8 skips; not git" {
    const git_branch = @import("git_branch.zig");
    var buf: [walk_argv_len][]const u8 = undefined;
    const argv = walkArgvFor("/tmp/faku-walk", &buf);
    try std.testing.expectEqualStrings(sh_bin, argv[0]);
    try std.testing.expectEqualStrings("-c", argv[1]);
    try std.testing.expectEqualStrings(main.fx_ask_chdir_script, argv[2]);
    try std.testing.expectEqualStrings("sh", argv[3]);
    try std.testing.expectEqualStrings("/tmp/faku-walk", argv[4]);
    try std.testing.expectEqualStrings(find_bin, argv[5]);
    try std.testing.expectEqualStrings(find_start, argv[6]);
    try std.testing.expectEqualStrings(find_maxdepth_flag, argv[7]);
    try std.testing.expectEqualStrings(find_maxdepth, argv[8]);
    try std.testing.expectEqualStrings(find_not, argv[9]);
    try std.testing.expectEqualStrings(find_name_flag, argv[10]);
    try std.testing.expectEqualStrings(find_start, argv[11]);
    try std.testing.expect(isWalkArgv(argv));
    try std.testing.expect(!isGitLsFilesArgv(argv));
    try std.testing.expect(!git_branch.isGitBranchArgv(argv));
    inline for (walk_skip_names) |name| {
        try std.testing.expect(argvHas(argv, name));
    }
    try std.testing.expect(argvHas(argv, find_dot_star));
    try std.testing.expect(argvHas(argv, find_prune));
    try std.testing.expect(argvHas(argv, find_type_file));
    try std.testing.expect(!isWalkArgv(&.{ find_bin, find_start }));
    var git_buf: [git_argv_len][]const u8 = undefined;
    try std.testing.expect(!isWalkArgv(argvFor("/tmp/faku-walk", &git_buf)));
}

test "applyStdoutPaths keeps first N; empty lines skipped" {
    var model = Model{};
    applyStdoutPaths(&model, "src/main.zig\n\n  src/composer.zig  \n");
    try std.testing.expectEqual(@as(u32, 2), cachedCount(&model));
    try std.testing.expectEqualStrings("src/main.zig", cachedPath(&model, 0));
    try std.testing.expectEqualStrings("src/composer.zig", cachedPath(&model, 1));

    clearCache(&model);
    applyStdoutPaths(&model, "./src/a.zig\n.\n./\n./.\n  ./src/b.zig  \n");
    try std.testing.expectEqual(@as(u32, 2), cachedCount(&model));
    try std.testing.expectEqualStrings("src/a.zig", cachedPath(&model, 0));
    try std.testing.expectEqualStrings("src/b.zig", cachedPath(&model, 1));
    try std.testing.expectEqualStrings("", normalizeStdoutPath("."));
    try std.testing.expectEqualStrings("", normalizeStdoutPath("./"));
    try std.testing.expectEqualStrings("", normalizeStdoutPath("./."));
    try std.testing.expectEqualStrings("src/a.zig", normalizeStdoutPath("./src/a.zig"));

    var overflow: [max_file_mentions * 2 + 16]u8 = undefined;
    var n: usize = 0;
    var i: usize = 0;
    while (i < max_file_mentions + 4) : (i += 1) {
        overflow[n] = 'a';
        n += 1;
        overflow[n] = '\n';
        n += 1;
    }
    clearCache(&model);
    applyStdoutPaths(&model, overflow[0..n]);
    try std.testing.expectEqual(@as(u32, max_file_mentions), cachedCount(&model));
}

test "probeSupported is false only on Windows" {
    if (builtin.os.tag == .windows) {
        try std.testing.expect(!probeSupported());
    } else {
        try std.testing.expect(probeSupported());
    }
}

test "collectDerivedDirParents unique ancestors; skip empty and dot" {
    var out: [8][]const u8 = undefined;
    const n = collectDerivedDirParents(&.{
        "src/lib/util.zig",
        "src/main.zig",
        "README.md",
        "./hidden.txt",
        "/abs.zig",
        "foo/./x",
    }, &out);
    try std.testing.expectEqual(@as(usize, 3), n);
    try std.testing.expectEqualStrings("src/lib", out[0]);
    try std.testing.expectEqualStrings("src", out[1]);
    try std.testing.expectEqualStrings("foo", out[2]);

    var tiny: [1][]const u8 = undefined;
    try std.testing.expectEqual(@as(usize, 1), collectDerivedDirParents(&.{ "a/b/c.zig", "d/e.zig" }, &tiny));
    try std.testing.expectEqualStrings("a/b", tiny[0]);

    var model = Model{};
    applyStdoutPaths(&model, "src/lib/util.zig\nsrc/main.zig\nREADME.md\n");
    var parents: [max_file_mention_dirs][]const u8 = undefined;
    try std.testing.expectEqual(@as(usize, 2), derivedDirParents(&model, &parents));
    try std.testing.expectEqualStrings("src/lib", parents[0]);
    try std.testing.expectEqualStrings("src", parents[1]);

    var dir_buf: [max_file_mention_path + 1]u8 = undefined;
    try std.testing.expectEqualStrings("src/lib/util.zig", mentionRelpath(&model, 1, &dir_buf).?);
    try std.testing.expectEqualStrings("src/lib/", mentionRelpath(&model, dirMentionId(0), &dir_buf).?);
    try std.testing.expectEqualStrings("src/", mentionRelpath(&model, dirMentionId(1), &dir_buf).?);
    try std.testing.expect(mentionRelpath(&model, 0, &dir_buf) == null);
    try std.testing.expect(mentionRelpath(&model, 4, &dir_buf) == null);
    try std.testing.expect(mentionRelpath(&model, dirMentionId(2), &dir_buf) == null);
}
