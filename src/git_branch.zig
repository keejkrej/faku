//! One-shot current-branch probe for the composer project row.
//!
//! Native has no git/workspace effect. When the selected session has a
//! non-empty `project_path` that exists, Faku `fx.spawn`s
//! `git branch --show-current` through the same `/bin/sh -c` chdir
//! workaround `fx ask` uses (`fx_ask_chdir_script`). Detached HEAD and
//! non-repos print empty; this cut does not invent a name, list
//! branches, or check out. Not Waku's daemon `InspectBranches` picker
//! and not a live `git status` watch.
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

/// One-shot `git branch --show-current` probe. Distinct from maximize /
/// pick-image / fx-ask / daemon / clipboard / probe keys, from
/// git_dirty (300+), and from file_mention (400+). Incremented per
/// refresh so a cancelled spawn cannot paint a later session.
pub const git_branch_key_first: u64 = 200;

pub const max_git_branch: usize = 255;

pub const git_bin = "git";
pub const git_branch_cmd = "branch";
pub const git_show_current = "--show-current";
pub const sh_bin = "/bin/sh";

const chdir_argv_len: usize = 8;

pub fn argvFor(cwd: []const u8, buf: *[chdir_argv_len][]const u8) []const []const u8 {
    buf.* = .{
        sh_bin,
        "-c",
        main.fx_ask_chdir_script,
        "sh",
        cwd,
        git_bin,
        git_branch_cmd,
        git_show_current,
    };
    return buf;
}

pub fn isGitBranchArgv(argv: []const []const u8) bool {
    if (argv.len != chdir_argv_len) return false;
    if (!std.mem.eql(u8, argv[0], sh_bin)) return false;
    if (!std.mem.eql(u8, argv[1], "-c")) return false;
    if (!std.mem.eql(u8, argv[2], main.fx_ask_chdir_script)) return false;
    if (!std.mem.eql(u8, argv[5], git_bin)) return false;
    if (!std.mem.eql(u8, argv[6], git_branch_cmd)) return false;
    return std.mem.eql(u8, argv[7], git_show_current);
}

/// First stdout line, trimmed. Empty / whitespace is not a branch.
pub fn firstStdoutBranch(raw: []const u8) []const u8 {
    const trimmed = std.mem.trim(u8, raw, " \t\r\n");
    if (trimmed.len == 0) return "";
    const end = std.mem.indexOfAny(u8, trimmed, "\r\n") orelse trimmed.len;
    return std.mem.trim(u8, trimmed[0..end], " \t");
}

/// Conservative `git check-ref-format --branch` subset. One line, no
/// spaces, no invented placeholder. `HEAD` is allowed only when git
/// actually printed it.
pub fn isPlausibleBranchName(name: []const u8) bool {
    if (name.len == 0 or name.len > max_git_branch) return false;
    if (name[0] == '/' or name[0] == '.' or name[0] == '-') return false;
    if (name[name.len - 1] == '/' or name[name.len - 1] == '.') return false;
    if (std.mem.eql(u8, name, "@")) return false;
    if (std.mem.indexOf(u8, name, "..") != null) return false;
    if (std.mem.indexOf(u8, name, "@{") != null) return false;
    for (name) |c| {
        if (c < 32 or c == 127) return false;
        const ok = std.ascii.isAlphanumeric(c) or c == '.' or c == '_' or c == '-' or c == '/';
        if (!ok) return false;
    }
    return true;
}

pub fn takeBranchName(raw: []const u8) ?[]const u8 {
    const name = firstStdoutBranch(raw);
    if (!isPlausibleBranchName(name)) return null;
    return name;
}

pub fn gitBranchLabel(model: *const Model) []const u8 {
    return model.git_branch_storage[0..model.git_branch_len];
}

pub fn hasGitBranch(model: *const Model) bool {
    return model.git_branch_len > 0;
}

pub fn clearGitBranch(model: *Model) void {
    model.git_branch_len = 0;
}

fn setGitBranch(model: *Model, name: []const u8) void {
    writeFixed(&model.git_branch_storage, &model.git_branch_len, name);
}

fn cancelInFlight(model: *Model, fx: *Effects) void {
    if (model.git_branch_key == 0) return;
    fx.cancel(model.git_branch_key);
    model.git_branch_key = 0;
}

fn probePath(model: *const Model) []const u8 {
    const path = model.selectedProjectPath();
    if (path.len == 0) return "";
    const io = model.store_io orelse return "";
    if (!main.directoryExists(io, path)) return "";
    return path;
}

/// Cancel any in-flight probe, drop the label, and spawn again when the
/// selected session has an existing `project_path`. Empty / missing /
/// Windows skips the spawn so the label stays omitted.
pub fn refresh(model: *Model, fx: *Effects) void {
    cancelInFlight(model, fx);
    clearGitBranch(model);
    if (builtin.os.tag == .windows) return;
    const cwd = probePath(model);
    if (cwd.len == 0) return;

    const key = model.next_git_branch_key;
    model.next_git_branch_key = key + 1;
    model.git_branch_key = key;
    model.git_branch_probe_session = model.selected;
    writeFixed(&model.git_branch_probe_path_storage, &model.git_branch_probe_path_len, cwd);

    var argv_buf: [chdir_argv_len][]const u8 = undefined;
    fx.spawn(.{
        .key = key,
        .argv = argvFor(cwd, &argv_buf),
        .on_line = Effects.lineMsg(.fx_line),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
}

fn probeStillCurrent(model: *const Model) bool {
    if (model.git_branch_key == 0) return false;
    if (model.git_branch_probe_session != model.selected) return false;
    const path = model.selectedProjectPath();
    const probed = model.git_branch_probe_path_storage[0..model.git_branch_probe_path_len];
    return std.mem.eql(u8, path, probed);
}

pub fn applyLine(model: *Model, line: native_sdk.EffectLine) void {
    if (line.key != model.git_branch_key or model.git_branch_key == 0) return;
    if (!probeStillCurrent(model)) return;
    if (takeBranchName(line.line)) |name| {
        setGitBranch(model, name);
    } else {
        clearGitBranch(model);
    }
}

pub fn handleExit(model: *Model, exit: native_sdk.EffectExit) void {
    if (exit.key != model.git_branch_key or model.git_branch_key == 0) return;
    const current = probeStillCurrent(model);
    model.git_branch_key = 0;
    if (!current or exit.reason != .exited or exit.code != 0) {
        clearGitBranch(model);
    }
}

test "argv is chdir script plus git branch --show-current" {
    var buf: [chdir_argv_len][]const u8 = undefined;
    const argv = argvFor("/tmp/faku-git", &buf);
    try std.testing.expectEqualStrings(sh_bin, argv[0]);
    try std.testing.expectEqualStrings("-c", argv[1]);
    try std.testing.expectEqualStrings(main.fx_ask_chdir_script, argv[2]);
    try std.testing.expectEqualStrings("sh", argv[3]);
    try std.testing.expectEqualStrings("/tmp/faku-git", argv[4]);
    try std.testing.expectEqualStrings(git_bin, argv[5]);
    try std.testing.expectEqualStrings(git_branch_cmd, argv[6]);
    try std.testing.expectEqualStrings(git_show_current, argv[7]);
    try std.testing.expect(isGitBranchArgv(argv));
    try std.testing.expect(!isGitBranchArgv(&.{ git_bin, git_branch_cmd, git_show_current }));
}

test "firstStdoutBranch trims one line; implausible names are omitted" {
    try std.testing.expectEqualStrings("main", firstStdoutBranch("  main \n"));
    try std.testing.expectEqualStrings("feat/composer", firstStdoutBranch("feat/composer\norigin\n"));
    try std.testing.expectEqualStrings("", firstStdoutBranch("   \n"));
    try std.testing.expectEqualStrings("", firstStdoutBranch(""));
    try std.testing.expectEqualStrings("main", takeBranchName("  main \n").?);
    try std.testing.expectEqualStrings("feat/foo-bar", takeBranchName("feat/foo-bar").?);
    try std.testing.expect(takeBranchName("   ") == null);
    try std.testing.expect(takeBranchName("not a branch") == null);
    try std.testing.expect(takeBranchName("../escape") == null);
    try std.testing.expect(takeBranchName("/abs") == null);
    try std.testing.expect(takeBranchName(".hidden") == null);
    try std.testing.expect(takeBranchName("trailing.") == null);
    try std.testing.expect(takeBranchName("@") == null);
    try std.testing.expect(takeBranchName("foo@{bar") == null);
    try std.testing.expectEqualStrings("HEAD", takeBranchName("HEAD").?);
}
