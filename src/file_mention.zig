//! One-shot tracked-file probe for composer `@` mentions.
//!
//! Native has no git/workspace/file-index effect. When the selected
//! session has a non-empty `project_path` that exists, Faku `fx.spawn`s
//! `git ls-files` through the same `/bin/sh -c` chdir workaround
//! `fx ask` uses (`fx_ask_chdir_script`). First-N stdout paths stay in
//! a bounded runtime cache on the Model — not `sessions.json`.
//!
//! Not Waku's 50k-file index, fuzzy rank, or caret-aware trigger.
//! Tracked files only. Untracked / ignored / non-git / Windows stay
//! empty this cut. Not Open-in, not copy path, not a daemon catalog.
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

/// One-shot `git ls-files` probe. Distinct from git_branch (200+),
/// maximize / pick-image / fx-ask / daemon / clipboard / probe keys.
/// Incremented per refresh so a cancelled spawn cannot paint a later
/// session.
pub const file_mention_key_first: u64 = 400;

pub const max_file_mentions: usize = 256;
pub const max_file_mention_path: usize = 255;
/// Same visible-row cap as the command palette task section.
pub const file_mention_visible_cap: usize = 12;

pub const git_bin = "git";
pub const git_ls_files_cmd = "ls-files";
pub const sh_bin = "/bin/sh";

const chdir_argv_len: usize = 7;

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

pub fn argvFor(cwd: []const u8, buf: *[chdir_argv_len][]const u8) []const []const u8 {
    buf.* = .{
        sh_bin,
        "-c",
        main.fx_ask_chdir_script,
        "sh",
        cwd,
        git_bin,
        git_ls_files_cmd,
    };
    return buf;
}

pub fn isGitLsFilesArgv(argv: []const []const u8) bool {
    if (argv.len != chdir_argv_len) return false;
    if (!std.mem.eql(u8, argv[0], sh_bin)) return false;
    if (!std.mem.eql(u8, argv[1], "-c")) return false;
    if (!std.mem.eql(u8, argv[2], main.fx_ask_chdir_script)) return false;
    if (!std.mem.eql(u8, argv[5], git_bin)) return false;
    return std.mem.eql(u8, argv[6], git_ls_files_cmd);
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

/// Cancel any in-flight probe, drop the cache, and spawn again when the
/// selected session has an existing `project_path`. Empty / missing /
/// Windows skips the spawn so the mention list stays hidden.
pub fn refresh(model: *Model, fx: *Effects) void {
    cancelInFlight(model, fx);
    clearCache(model);
    if (!probeSupported()) return;
    const cwd = probePath(model);
    if (cwd.len == 0) return;

    const key = model.next_file_mention_key;
    model.next_file_mention_key = key + 1;
    model.file_mention_key = key;
    model.file_mention_probe_session = model.selected;
    writeFixed(&model.file_mention_probe_path_storage, &model.file_mention_probe_path_len, cwd);

    var argv_buf: [chdir_argv_len][]const u8 = undefined;
    fx.spawn(.{
        .key = key,
        .argv = argvFor(cwd, &argv_buf),
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

/// Append trimmed non-empty stdout paths until `max_file_mentions`.
/// Later lines are dropped — this is not Waku's 50k-file index.
pub fn applyStdoutPaths(model: *Model, raw: []const u8) void {
    var it = std.mem.splitScalar(u8, raw, '\n');
    while (it.next()) |line| {
        if (model.file_mention_count >= max_file_mentions) return;
        const path = std.mem.trim(u8, line, " \t\r\n");
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

pub fn handleExit(model: *Model, exit: native_sdk.EffectExit) void {
    if (exit.key != model.file_mention_key or model.file_mention_key == 0) return;
    const current = probeStillCurrent(model);
    model.file_mention_key = 0;
    if (!current or exit.reason != .exited or exit.code != 0) {
        clearCache(model);
    }
}

test "argv is chdir script plus git ls-files; not git branch" {
    const git_branch = @import("git_branch.zig");
    var buf: [chdir_argv_len][]const u8 = undefined;
    const argv = argvFor("/tmp/faku-ls", &buf);
    try std.testing.expectEqualStrings(sh_bin, argv[0]);
    try std.testing.expectEqualStrings("-c", argv[1]);
    try std.testing.expectEqualStrings(main.fx_ask_chdir_script, argv[2]);
    try std.testing.expectEqualStrings("sh", argv[3]);
    try std.testing.expectEqualStrings("/tmp/faku-ls", argv[4]);
    try std.testing.expectEqualStrings(git_bin, argv[5]);
    try std.testing.expectEqualStrings(git_ls_files_cmd, argv[6]);
    try std.testing.expect(isGitLsFilesArgv(argv));
    try std.testing.expect(!isGitLsFilesArgv(&.{ git_bin, git_ls_files_cmd }));
    try std.testing.expect(!git_branch.isGitBranchArgv(argv));
    var branch_buf: [8][]const u8 = undefined;
    const branch = git_branch.argvFor("/tmp/faku-ls", &branch_buf);
    try std.testing.expect(!isGitLsFilesArgv(branch));
    try std.testing.expect(file_mention_key_first > git_branch.git_branch_key_first);
}

test "applyStdoutPaths keeps first N; empty lines skipped" {
    var model = Model{};
    applyStdoutPaths(&model, "src/main.zig\n\n  src/composer.zig  \n");
    try std.testing.expectEqual(@as(u32, 2), cachedCount(&model));
    try std.testing.expectEqualStrings("src/main.zig", cachedPath(&model, 0));
    try std.testing.expectEqualStrings("src/composer.zig", cachedPath(&model, 1));

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
