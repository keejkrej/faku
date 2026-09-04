//! One-shot file probe for composer `@` mentions.
//!
//! Native has no git/workspace/file-index effect. When the selected
//! session has a non-empty `project_path` that exists, Faku `fx.spawn`s
//! `git ls-files --cached --others --exclude-standard`. Git is
//! authoritative for a repo: success with zero files stays empty (do
//! not walk — that would dump `node_modules`). Only when that spawn
//! cannot run or exits non-zero does a bounded walk fill the same
//! runtime cache. First-N stdout paths stay on the Model — not
//! `sessions.json`.
//!
//! Unix uses the same `/bin/sh -c` chdir workaround `fx ask` uses
//! (`fx_ask_chdir_script`) plus a packed `find -maxdepth 8`. Windows
//! cannot use `/bin/sh` or `find`: `git.exe -C <project_path>` (path
//! is its own argv slot, not interpolated into a script) then a
//! `powershell.exe -NoProfile -Command {…} -Args <project_path>`
//! walk (`$args[0]`; same skip names / depth 8 / cap 256). `\` stdout
//! paths are normalized to `/` so Files / `@` rows match the Unix
//! cache shape. app.zon already includes windows. Still not Waku's
//! 50k-file index, not a Native FS watcher, not caret-aware.
//!
//! Visible `@` rows are scored over this bounded file cache (plus
//! derived parent directories at row time) in
//! `composer.fileMentionScore` — not first-N contains in cache
//! order. The sidecar stdout and this cache stay files-only. Not
//! Open-in, not copy path, not a daemon catalog.
//!
//! Spawn/line/exit orchestration lives here. Effect key stays
//! `file_mention_key_first` (400+).

const std = @import("std");
const builtin = @import("builtin");
const native_sdk = @import("native_sdk");
const main = @import("main.zig");

const Model = main.Model;
const Effects = main.Effects;
const writeFixed = main.writeFixed;

/// One-shot file-mention probe (git ls-files, then a bounded walk
/// when git cannot list). Distinct from git_branch (200+), git_dirty
/// (300+), git_numstat (350+), git_push (360+), git_worktree_add
/// (370+), git_ahead_behind (380+), git_worktree_base (390+),
/// maximize / pick-image / fx-ask / daemon / clipboard / probe
/// keys. Incremented per spawn so a cancelled probe cannot paint
/// a later session.
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
/// PATH-resolved Windows Git (explicit `.exe` like sibling
/// `powershell.exe` / `explorer.exe` / `wt.exe` / `cmd.exe`).
pub const windows_git_bin = "git.exe";
pub const git_c_flag = "-C";
pub const git_ls_files_cmd = "ls-files";
pub const git_ls_files_cached = "--cached";
pub const git_ls_files_others = "--others";
pub const git_ls_files_exclude_standard = "--exclude-standard";
pub const sh_bin = "/bin/sh";

pub const find_bin = "find";
pub const find_maxdepth_flag = "-maxdepth";
pub const find_maxdepth = "8";
pub const find_prune = "-prune";
pub const find_type_file = "f";
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
/// Packed into one `-c` string so the spawn stays under Native
/// `max_effect_argv` (16). `! -name .` keeps the start point from
/// matching `-name '.*'` and pruning the tree after chdir.
pub const find_walk_script =
    "find . -maxdepth 8 ! -name . \\( -name node_modules -o -name target -o -name dist -o -name build -o -name out -o -name vendor -o -name __pycache__ -o -name '.*' \\) -prune -o -type f -print";

/// PATH-resolved Windows PowerShell (no STA: this is Get-ChildItem,
/// not WinForms). Explicit `.exe` like sibling maximize / pickers.
pub const powershell_bin = "powershell.exe";
pub const powershell_noprofile = "-NoProfile";
pub const powershell_command = "-Command";
pub const powershell_args_flag = "-Args";
/// Scriptblock + `$args[0]`: project path is its own argv slot after
/// `-Args`, not spliced into the `-Command` body. Files only, depth 8,
/// same skip names / dot dirs as `find_walk_script`, relative paths
/// with `/`, cap `max_file_mentions` (256). Six argv slots total.
pub const powershell_walk_script =
    "{ $ErrorActionPreference='Stop'; $script:root=$args[0].TrimEnd('\\','/'); $script:skip=@('node_modules','target','dist','build','out','vendor','__pycache__'); $script:n=0; function Walk($dir,$depth){ if($script:n -ge 256){return}; foreach($item in (Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue)){ if($script:n -ge 256){return}; $d=$depth+1; if($d -gt 8){continue}; $name=$item.Name; if($name.StartsWith('.')){continue}; if($script:skip -contains $name){continue}; if($item.PSIsContainer){ if($d -lt 8){ Walk $item.FullName $d } } else { $rel=$item.FullName.Substring($script:root.Length).TrimStart('\\','/'); Write-Output ($rel -replace '\\\\','/'); $script:n++ } } }; Walk $script:root 0 }";

/// Unix `/bin/sh -c` chdir + git ls-files (10). Windows `git.exe -C`
/// is 7; this is the spawn buffer (max of the two).
pub const git_argv_len: usize = 10;
pub const unix_git_argv_len: usize = 10;
pub const windows_git_argv_len: usize = 7;
/// Unix `/bin/sh -c` chdir + `/bin/sh -c` + `find_walk_script` (8).
/// Windows powershell `-Command` + `-Args` is 6; this is the spawn
/// buffer (max of the two).
pub const walk_argv_len: usize = 8;
pub const unix_walk_argv_len: usize = 8;
pub const windows_walk_argv_len: usize = 6;

pub const CachedPath = struct {
    storage: [max_file_mention_path]u8 = [_]u8{0} ** max_file_mention_path,
    len: usize = 0,

    pub fn text(self: *const CachedPath) []const u8 {
        return self.storage[0..self.len];
    }

    pub fn set(self: *CachedPath, path: []const u8) void {
        writeFixed(&self.storage, &self.len, path);
        slashNormalizeInPlace(self.storage[0..self.len]);
    }
};

pub fn unixArgvFor(cwd: []const u8, buf: *[git_argv_len][]const u8) []const []const u8 {
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
    return buf[0..unix_git_argv_len];
}

/// Windows: `git.exe -C <project_path> ls-files --cached --others
/// --exclude-standard`. Path is its own argv slot (no `/bin/sh`, no
/// packing into a cmd string).
pub fn windowsArgvFor(cwd: []const u8, buf: *[git_argv_len][]const u8) []const []const u8 {
    buf[0] = windows_git_bin;
    buf[1] = git_c_flag;
    buf[2] = cwd;
    buf[3] = git_ls_files_cmd;
    buf[4] = git_ls_files_cached;
    buf[5] = git_ls_files_others;
    buf[6] = git_ls_files_exclude_standard;
    return buf[0..windows_git_argv_len];
}

pub fn argvFor(cwd: []const u8, buf: *[git_argv_len][]const u8) []const []const u8 {
    return switch (builtin.os.tag) {
        .windows => windowsArgvFor(cwd, buf),
        else => unixArgvFor(cwd, buf),
    };
}

fn isUnixGitLsFilesArgv(argv: []const []const u8) bool {
    if (argv.len != unix_git_argv_len) return false;
    if (!std.mem.eql(u8, argv[0], sh_bin)) return false;
    if (!std.mem.eql(u8, argv[1], "-c")) return false;
    if (!std.mem.eql(u8, argv[2], main.fx_ask_chdir_script)) return false;
    if (!std.mem.eql(u8, argv[5], git_bin)) return false;
    if (!std.mem.eql(u8, argv[6], git_ls_files_cmd)) return false;
    if (!std.mem.eql(u8, argv[7], git_ls_files_cached)) return false;
    if (!std.mem.eql(u8, argv[8], git_ls_files_others)) return false;
    return std.mem.eql(u8, argv[9], git_ls_files_exclude_standard);
}

fn isWindowsGitLsFilesArgv(argv: []const []const u8) bool {
    if (argv.len != windows_git_argv_len) return false;
    const bin_ok = std.mem.eql(u8, argv[0], windows_git_bin) or std.mem.eql(u8, argv[0], git_bin);
    if (!bin_ok) return false;
    if (!std.mem.eql(u8, argv[1], git_c_flag)) return false;
    if (argv[2].len == 0) return false;
    if (!std.mem.eql(u8, argv[3], git_ls_files_cmd)) return false;
    if (!std.mem.eql(u8, argv[4], git_ls_files_cached)) return false;
    if (!std.mem.eql(u8, argv[5], git_ls_files_others)) return false;
    return std.mem.eql(u8, argv[6], git_ls_files_exclude_standard);
}

pub fn isGitLsFilesArgv(argv: []const []const u8) bool {
    return isUnixGitLsFilesArgv(argv) or isWindowsGitLsFilesArgv(argv);
}

pub fn unixWalkArgvFor(cwd: []const u8, buf: *[walk_argv_len][]const u8) []const []const u8 {
    buf.* = .{
        sh_bin,
        "-c",
        main.fx_ask_chdir_script,
        "sh",
        cwd,
        sh_bin,
        "-c",
        find_walk_script,
    };
    return buf[0..unix_walk_argv_len];
}

/// Windows: `powershell.exe -NoProfile -Command {scriptblock} -Args
/// <project_path>`. Path stays `$args[0]` — not interpolated into
/// the `-Command` body.
pub fn windowsWalkArgvFor(cwd: []const u8, buf: *[walk_argv_len][]const u8) []const []const u8 {
    buf[0] = powershell_bin;
    buf[1] = powershell_noprofile;
    buf[2] = powershell_command;
    buf[3] = powershell_walk_script;
    buf[4] = powershell_args_flag;
    buf[5] = cwd;
    return buf[0..windows_walk_argv_len];
}

pub fn walkArgvFor(cwd: []const u8, buf: *[walk_argv_len][]const u8) []const []const u8 {
    return switch (builtin.os.tag) {
        .windows => windowsWalkArgvFor(cwd, buf),
        else => unixWalkArgvFor(cwd, buf),
    };
}

fn scriptHas(script: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, script, needle) != null;
}

fn isUnixWalkArgv(argv: []const []const u8) bool {
    if (argv.len != unix_walk_argv_len) return false;
    if (!std.mem.eql(u8, argv[0], sh_bin)) return false;
    if (!std.mem.eql(u8, argv[1], "-c")) return false;
    if (!std.mem.eql(u8, argv[2], main.fx_ask_chdir_script)) return false;
    if (!std.mem.eql(u8, argv[5], sh_bin)) return false;
    if (!std.mem.eql(u8, argv[6], "-c")) return false;
    if (!std.mem.eql(u8, argv[7], find_walk_script)) return false;
    if (!scriptHas(argv[7], find_maxdepth_flag)) return false;
    if (!scriptHas(argv[7], find_maxdepth)) return false;
    if (!scriptHas(argv[7], find_prune)) return false;
    if (!scriptHas(argv[7], find_type_file)) return false;
    if (!scriptHas(argv[7], find_dot_star)) return false;
    inline for (walk_skip_names) |name| {
        if (!scriptHas(argv[7], name)) return false;
    }
    return true;
}

fn isWindowsWalkArgv(argv: []const []const u8) bool {
    if (argv.len != windows_walk_argv_len) return false;
    if (!std.mem.eql(u8, argv[0], powershell_bin)) return false;
    if (!std.mem.eql(u8, argv[1], powershell_noprofile)) return false;
    if (!std.mem.eql(u8, argv[2], powershell_command)) return false;
    if (!std.mem.eql(u8, argv[3], powershell_walk_script)) return false;
    if (!std.mem.eql(u8, argv[4], powershell_args_flag)) return false;
    if (argv[5].len == 0) return false;
    if (!scriptHas(argv[3], "$args[0]")) return false;
    if (!scriptHas(argv[3], find_maxdepth)) return false;
    if (!scriptHas(argv[3], "256")) return false;
    if (!scriptHas(argv[3], "StartsWith('.'")) return false;
    inline for (walk_skip_names) |name| {
        if (!scriptHas(argv[3], name)) return false;
    }
    return true;
}

pub fn isWalkArgv(argv: []const []const u8) bool {
    return isUnixWalkArgv(argv) or isWindowsWalkArgv(argv);
}

pub fn probeSupported() bool {
    return true;
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
    model.clearRightPanelExpanded();
}

fn cancelInFlight(model: *Model, fx: *Effects) void {
    if (model.file_mention_key == 0) return;
    fx.cancel(model.file_mention_key);
    model.file_mention_key = 0;
}

/// Existing selected-session directory used by `@` mentions and the
/// Files pane. Empty / missing / Local stays empty so neither surface
/// invents a project.
pub fn probePath(model: *const Model) []const u8 {
    const path = model.selectedProjectPath();
    if (path.len == 0) return "";
    const io = model.store_io orelse return "";
    if (!main.directoryExists(io, path)) return "";
    return path;
}

/// Cancel any in-flight probe, drop the cache, and spawn git ls-files
/// when the selected session has an existing `project_path`. Empty /
/// missing skips both git and the walk so the mention list stays
/// hidden. A failed git spawn falls back to the walk in `handleExit`.
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

/// Strip a leading `./` or `.\` (`find -print` emits `./src/a.zig`;
/// git does not). `.` and empty are not files. Backslash → `/` happens
/// in `CachedPath.set` so Windows walk stdout matches Unix cache shape.
pub fn normalizeStdoutPath(raw: []const u8) []const u8 {
    const trimmed = std.mem.trim(u8, raw, " \t\r\n");
    const path = if (std.mem.startsWith(u8, trimmed, "./") or std.mem.startsWith(u8, trimmed, ".\\"))
        trimmed[2..]
    else
        trimmed;
    if (path.len == 0 or std.mem.eql(u8, path, ".") or std.mem.eql(u8, path, "\\")) return "";
    return path;
}

fn slashNormalizeInPlace(path: []u8) void {
    for (path) |*ch| {
        if (ch.* == '\\') ch.* = '/';
    }
}

/// Append trimmed non-empty stdout paths until `max_file_mentions`.
/// Later lines are dropped — this is not Waku's 50k-file index.
/// Windows `\` separators become `/` in `CachedPath.set`.
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
    const git_dirty = @import("git_dirty.zig");
    const git_numstat = @import("git_numstat.zig");
    var buf: [git_argv_len][]const u8 = undefined;
    const argv = unixArgvFor("/tmp/faku-ls", &buf);
    try std.testing.expectEqual(@as(usize, unix_git_argv_len), argv.len);
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
    try std.testing.expect(!git_dirty.isGitDirtyArgv(argv));
    try std.testing.expect(!git_numstat.isGitNumstatArgv(argv));
    var branch_buf: [git_branch.argv_len][]const u8 = undefined;
    const branch = git_branch.argvFor("/tmp/faku-ls", &branch_buf);
    try std.testing.expect(!isGitLsFilesArgv(branch));
    var dirty_buf: [git_dirty.argv_len][]const u8 = undefined;
    const dirty = git_dirty.argvFor("/tmp/faku-ls", &dirty_buf);
    try std.testing.expect(!isGitLsFilesArgv(dirty));
    var numstat_buf: [git_numstat.argv_len][]const u8 = undefined;
    const numstat = git_numstat.unixArgvFor("/tmp/faku-ls", &numstat_buf);
    try std.testing.expect(!isGitLsFilesArgv(numstat));
    try std.testing.expect(file_mention_key_first > git_numstat.git_numstat_key_first);
    try std.testing.expect(git_numstat.git_numstat_key_first > git_dirty.git_dirty_key_first);
    try std.testing.expect(git_dirty.git_dirty_key_first > git_branch.git_branch_key_first);
}

test "windows git argv is git.exe -C PATH ls-files; path is its own slot" {
    var buf: [git_argv_len][]const u8 = undefined;
    const cwd = "C:\\Users\\me\\proj";
    const argv = windowsArgvFor(cwd, &buf);
    try std.testing.expectEqual(@as(usize, windows_git_argv_len), argv.len);
    try std.testing.expect(argv.len <= 16);
    try std.testing.expectEqualStrings(windows_git_bin, argv[0]);
    try std.testing.expectEqualStrings(git_c_flag, argv[1]);
    try std.testing.expectEqualStrings(cwd, argv[2]);
    try std.testing.expectEqualStrings(git_ls_files_cmd, argv[3]);
    try std.testing.expectEqualStrings(git_ls_files_cached, argv[4]);
    try std.testing.expectEqualStrings(git_ls_files_others, argv[5]);
    try std.testing.expectEqualStrings(git_ls_files_exclude_standard, argv[6]);
    try std.testing.expect(isGitLsFilesArgv(argv));
    try std.testing.expect(!isWalkArgv(argv));
    try std.testing.expect(!isGitLsFilesArgv(&.{ windows_git_bin, git_c_flag, cwd }));
    var git_only: [git_argv_len][]const u8 = undefined;
    git_only[0] = git_bin;
    git_only[1] = git_c_flag;
    git_only[2] = cwd;
    git_only[3] = git_ls_files_cmd;
    git_only[4] = git_ls_files_cached;
    git_only[5] = git_ls_files_others;
    git_only[6] = git_ls_files_exclude_standard;
    try std.testing.expect(isGitLsFilesArgv(git_only[0..windows_git_argv_len]));
    const git_branch = @import("git_branch.zig");
    const git_dirty = @import("git_dirty.zig");
    try std.testing.expect(!git_branch.isGitBranchArgv(argv));
    try std.testing.expect(!git_dirty.isGitDirtyArgv(argv));
    var branch_buf: [git_branch.argv_len][]const u8 = undefined;
    try std.testing.expect(!isGitLsFilesArgv(git_branch.windowsArgvFor(cwd, &branch_buf)));
    var dirty_buf: [git_dirty.argv_len][]const u8 = undefined;
    try std.testing.expect(!isGitLsFilesArgv(git_dirty.windowsArgvFor(cwd, &dirty_buf)));
}

test "walk argv is chdir script plus find maxdepth 8 skips; not git" {
    const git_branch = @import("git_branch.zig");
    const git_dirty = @import("git_dirty.zig");
    const git_numstat = @import("git_numstat.zig");
    var buf: [walk_argv_len][]const u8 = undefined;
    const argv = unixWalkArgvFor("/tmp/faku-walk", &buf);
    try std.testing.expectEqual(@as(usize, unix_walk_argv_len), argv.len);
    try std.testing.expectEqualStrings(sh_bin, argv[0]);
    try std.testing.expectEqualStrings("-c", argv[1]);
    try std.testing.expectEqualStrings(main.fx_ask_chdir_script, argv[2]);
    try std.testing.expectEqualStrings("sh", argv[3]);
    try std.testing.expectEqualStrings("/tmp/faku-walk", argv[4]);
    try std.testing.expectEqualStrings(sh_bin, argv[5]);
    try std.testing.expectEqualStrings("-c", argv[6]);
    try std.testing.expectEqualStrings(find_walk_script, argv[7]);
    try std.testing.expect(isWalkArgv(argv));
    try std.testing.expect(!isGitLsFilesArgv(argv));
    try std.testing.expect(!git_branch.isGitBranchArgv(argv));
    try std.testing.expect(!git_dirty.isGitDirtyArgv(argv));
    try std.testing.expect(!git_numstat.isGitNumstatArgv(argv));
    try std.testing.expect(scriptHas(argv[7], find_maxdepth_flag));
    try std.testing.expect(scriptHas(argv[7], find_maxdepth));
    try std.testing.expect(scriptHas(argv[7], find_prune));
    try std.testing.expect(scriptHas(argv[7], find_type_file));
    try std.testing.expect(scriptHas(argv[7], find_dot_star));
    inline for (walk_skip_names) |name| {
        try std.testing.expect(scriptHas(argv[7], name));
    }
    try std.testing.expect(!isWalkArgv(&.{ find_bin, find_walk_script }));
    var git_buf: [git_argv_len][]const u8 = undefined;
    try std.testing.expect(!isWalkArgv(unixArgvFor("/tmp/faku-walk", &git_buf)));
}

test "windows walk argv is powershell scriptblock -Args PATH; path not in script" {
    var buf: [walk_argv_len][]const u8 = undefined;
    const cwd = "C:\\Users\\me\\proj";
    const argv = windowsWalkArgvFor(cwd, &buf);
    try std.testing.expectEqual(@as(usize, windows_walk_argv_len), argv.len);
    try std.testing.expect(argv.len <= 16);
    try std.testing.expectEqualStrings(powershell_bin, argv[0]);
    try std.testing.expectEqualStrings(powershell_noprofile, argv[1]);
    try std.testing.expectEqualStrings(powershell_command, argv[2]);
    try std.testing.expectEqualStrings(powershell_walk_script, argv[3]);
    try std.testing.expectEqualStrings(powershell_args_flag, argv[4]);
    try std.testing.expectEqualStrings(cwd, argv[5]);
    try std.testing.expect(isWalkArgv(argv));
    try std.testing.expect(!isGitLsFilesArgv(argv));
    try std.testing.expect(std.mem.indexOf(u8, argv[3], cwd) == null);
    try std.testing.expect(scriptHas(argv[3], "$args[0]"));
    try std.testing.expect(scriptHas(argv[3], find_maxdepth));
    try std.testing.expect(scriptHas(argv[3], "256"));
    try std.testing.expect(scriptHas(argv[3], "StartsWith('.'"));
    inline for (walk_skip_names) |name| {
        try std.testing.expect(scriptHas(argv[3], name));
    }
    try std.testing.expect(!isWalkArgv(&.{
        powershell_bin,
        powershell_noprofile,
        powershell_command,
        "Get-Date",
        powershell_args_flag,
        cwd,
    }));
    var git_buf: [git_argv_len][]const u8 = undefined;
    try std.testing.expect(!isWalkArgv(windowsArgvFor(cwd, &git_buf)));
}

test "host argvFor and walkArgvFor match the process OS" {
    var git_buf: [git_argv_len][]const u8 = undefined;
    const git_argv = argvFor("/tmp/faku-ls", &git_buf);
    try std.testing.expect(isGitLsFilesArgv(git_argv));
    var walk_buf: [walk_argv_len][]const u8 = undefined;
    const walk_argv = walkArgvFor("/tmp/faku-walk", &walk_buf);
    try std.testing.expect(isWalkArgv(walk_argv));
    try std.testing.expect(!isWalkArgv(git_argv));
    try std.testing.expect(!isGitLsFilesArgv(walk_argv));
    switch (builtin.os.tag) {
        .windows => {
            try std.testing.expectEqualStrings(windows_git_bin, git_argv[0]);
            try std.testing.expectEqualStrings(git_c_flag, git_argv[1]);
            try std.testing.expectEqualStrings(powershell_bin, walk_argv[0]);
            try std.testing.expectEqualStrings(powershell_args_flag, walk_argv[4]);
        },
        else => {
            try std.testing.expectEqualStrings(sh_bin, git_argv[0]);
            try std.testing.expectEqualStrings(sh_bin, walk_argv[0]);
            try std.testing.expectEqualStrings(find_walk_script, walk_argv[7]);
        },
    }
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
    try std.testing.expectEqualStrings("", normalizeStdoutPath(".\\"));
    try std.testing.expectEqualStrings("src\\a.zig", normalizeStdoutPath(".\\src\\a.zig"));

    clearCache(&model);
    applyStdoutPaths(&model, "src\\lib\\a.zig\n.\\b.zig\nfoo\\bar.txt\n");
    try std.testing.expectEqual(@as(u32, 3), cachedCount(&model));
    try std.testing.expectEqualStrings("src/lib/a.zig", cachedPath(&model, 0));
    try std.testing.expectEqualStrings("b.zig", cachedPath(&model, 1));
    try std.testing.expectEqualStrings("foo/bar.txt", cachedPath(&model, 2));
    var slash_parents: [max_file_mention_dirs][]const u8 = undefined;
    try std.testing.expectEqual(@as(usize, 3), derivedDirParents(&model, &slash_parents));
    try std.testing.expectEqualStrings("src/lib", slash_parents[0]);
    try std.testing.expectEqualStrings("src", slash_parents[1]);
    try std.testing.expectEqualStrings("foo", slash_parents[2]);

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

test "probeSupported is true on macOS, Linux, and Windows" {
    try std.testing.expect(probeSupported());
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
