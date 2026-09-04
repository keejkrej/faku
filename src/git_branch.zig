//! One-shot current-branch probe for the composer project row.
//!
//! Native has no git/workspace effect. When the selected session has a
//! non-empty `project_path` that exists, Faku `fx.spawn`s
//! `git branch --show-current`. Detached HEAD prints empty; a
//! follow-up `git rev-parse --short HEAD` may fill the select label
//! with a conservative short hex. Non-repos stay omitted. Local
//! heads, remote-tracking checkout, create, safe delete, fetch,
//! push, and New worktree… live in `git_checkout.zig`. Not Waku's
//! daemon `InspectBranches` picker and not a live watch.
//!
//! Unix uses the same `/bin/sh -c` chdir workaround `fx ask` uses
//! (`fx_ask_chdir_script`). Windows cannot use `/bin/sh`:
//! `git.exe -C <project_path>` (path is its own argv slot, not
//! interpolated into a script). app.zon already includes windows.
//! Remaining git module (checkout) still skips Windows this cut.
//!
//! Spawn/line/exit orchestration lives here. Effect key stays
//! `git_branch_key_first` (200+).

const std = @import("std");
const builtin = @import("builtin");
const native_sdk = @import("native_sdk");
const main = @import("main.zig");

const Model = main.Model;
const Effects = main.Effects;
const writeFixed = main.writeFixed;

/// One-shot `git branch --show-current` (and detached `rev-parse
/// --short HEAD`) probe. Distinct from maximize / pick-image /
/// fx-ask / daemon / clipboard / probe keys, from git_branch_list
/// (250+), git_checkout (275+), git_create (290+), git_dirty (300+),
/// git_delete (320+), git_fetch (340+), git_numstat (350+),
/// git_push (360+), git_worktree_add (370+), git_ahead_behind
/// (380+), and from file_mention (400+). Incremented per refresh
/// so a cancelled spawn cannot paint a later session.
pub const git_branch_key_first: u64 = 200;

pub const max_git_branch: usize = 255;
/// Conservative detached-HEAD display. git `--short` default is 7;
/// uniqueness can grow a little. Not a full 40-char object name.
pub const min_short_sha: usize = 4;
pub const max_short_sha: usize = 16;

pub const git_bin = "git";
/// PATH-resolved Windows Git (explicit `.exe` like sibling
/// `powershell.exe` / `explorer.exe` / `wt.exe` / `cmd.exe`).
pub const windows_git_bin = "git.exe";
pub const git_c_flag = "-C";
pub const git_branch_cmd = "branch";
pub const git_show_current = "--show-current";
pub const git_rev_parse_cmd = "rev-parse";
pub const git_short = "--short";
pub const git_head = "HEAD";
pub const sh_bin = "/bin/sh";

/// Unix `/bin/sh -c` chdir + git branch --show-current (8). Windows
/// `git.exe -C` is 5; this is the spawn buffer (max of the two).
pub const argv_len: usize = 8;
pub const unix_argv_len: usize = 8;
pub const windows_argv_len: usize = 5;
/// Unix `/bin/sh -c` chdir + git rev-parse --short HEAD (9). Windows
/// `git.exe -C` is 6; this is the spawn buffer (max of the two).
pub const rev_parse_argv_len: usize = 9;
pub const unix_rev_parse_argv_len: usize = 9;
pub const windows_rev_parse_argv_len: usize = 6;

pub fn unixArgvFor(cwd: []const u8, buf: *[argv_len][]const u8) []const []const u8 {
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
    return buf[0..unix_argv_len];
}

/// Windows: `git.exe -C <project_path> branch --show-current`. Path
/// is its own argv slot (no `/bin/sh`, no packing into a cmd string).
pub fn windowsArgvFor(cwd: []const u8, buf: *[argv_len][]const u8) []const []const u8 {
    buf[0] = windows_git_bin;
    buf[1] = git_c_flag;
    buf[2] = cwd;
    buf[3] = git_branch_cmd;
    buf[4] = git_show_current;
    return buf[0..windows_argv_len];
}

pub fn argvFor(cwd: []const u8, buf: *[argv_len][]const u8) []const []const u8 {
    return switch (builtin.os.tag) {
        .windows => windowsArgvFor(cwd, buf),
        else => unixArgvFor(cwd, buf),
    };
}

fn isUnixGitBranchArgv(argv: []const []const u8) bool {
    if (argv.len != unix_argv_len) return false;
    if (!std.mem.eql(u8, argv[0], sh_bin)) return false;
    if (!std.mem.eql(u8, argv[1], "-c")) return false;
    if (!std.mem.eql(u8, argv[2], main.fx_ask_chdir_script)) return false;
    if (!std.mem.eql(u8, argv[5], git_bin)) return false;
    if (!std.mem.eql(u8, argv[6], git_branch_cmd)) return false;
    return std.mem.eql(u8, argv[7], git_show_current);
}

fn isWindowsGitBranchArgv(argv: []const []const u8) bool {
    if (argv.len != windows_argv_len) return false;
    const bin_ok = std.mem.eql(u8, argv[0], windows_git_bin) or std.mem.eql(u8, argv[0], git_bin);
    if (!bin_ok) return false;
    if (!std.mem.eql(u8, argv[1], git_c_flag)) return false;
    if (argv[2].len == 0) return false;
    if (!std.mem.eql(u8, argv[3], git_branch_cmd)) return false;
    return std.mem.eql(u8, argv[4], git_show_current);
}

pub fn isGitBranchArgv(argv: []const []const u8) bool {
    return isUnixGitBranchArgv(argv) or isWindowsGitBranchArgv(argv);
}

pub fn unixRevParseArgvFor(cwd: []const u8, buf: *[rev_parse_argv_len][]const u8) []const []const u8 {
    buf.* = .{
        sh_bin,
        "-c",
        main.fx_ask_chdir_script,
        "sh",
        cwd,
        git_bin,
        git_rev_parse_cmd,
        git_short,
        git_head,
    };
    return buf[0..unix_rev_parse_argv_len];
}

/// Windows: `git.exe -C <project_path> rev-parse --short HEAD`. Path
/// is its own argv slot.
pub fn windowsRevParseArgvFor(cwd: []const u8, buf: *[rev_parse_argv_len][]const u8) []const []const u8 {
    buf[0] = windows_git_bin;
    buf[1] = git_c_flag;
    buf[2] = cwd;
    buf[3] = git_rev_parse_cmd;
    buf[4] = git_short;
    buf[5] = git_head;
    return buf[0..windows_rev_parse_argv_len];
}

pub fn revParseArgvFor(cwd: []const u8, buf: *[rev_parse_argv_len][]const u8) []const []const u8 {
    return switch (builtin.os.tag) {
        .windows => windowsRevParseArgvFor(cwd, buf),
        else => unixRevParseArgvFor(cwd, buf),
    };
}

fn isUnixGitRevParseArgv(argv: []const []const u8) bool {
    if (argv.len != unix_rev_parse_argv_len) return false;
    if (!std.mem.eql(u8, argv[0], sh_bin)) return false;
    if (!std.mem.eql(u8, argv[1], "-c")) return false;
    if (!std.mem.eql(u8, argv[2], main.fx_ask_chdir_script)) return false;
    if (!std.mem.eql(u8, argv[5], git_bin)) return false;
    if (!std.mem.eql(u8, argv[6], git_rev_parse_cmd)) return false;
    if (!std.mem.eql(u8, argv[7], git_short)) return false;
    return std.mem.eql(u8, argv[8], git_head);
}

fn isWindowsGitRevParseArgv(argv: []const []const u8) bool {
    if (argv.len != windows_rev_parse_argv_len) return false;
    const bin_ok = std.mem.eql(u8, argv[0], windows_git_bin) or std.mem.eql(u8, argv[0], git_bin);
    if (!bin_ok) return false;
    if (!std.mem.eql(u8, argv[1], git_c_flag)) return false;
    if (argv[2].len == 0) return false;
    if (!std.mem.eql(u8, argv[3], git_rev_parse_cmd)) return false;
    if (!std.mem.eql(u8, argv[4], git_short)) return false;
    return std.mem.eql(u8, argv[5], git_head);
}

pub fn isGitRevParseArgv(argv: []const []const u8) bool {
    return isUnixGitRevParseArgv(argv) or isWindowsGitRevParseArgv(argv);
}

pub fn probeSupported() bool {
    return true;
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

/// Conservative detached-HEAD label. Lowercase/uppercase hex only;
/// no invented placeholder, no `HEAD` string.
pub fn isPlausibleShortSha(name: []const u8) bool {
    if (name.len < min_short_sha or name.len > max_short_sha) return false;
    for (name) |c| {
        const hex = (c >= '0' and c <= '9') or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F');
        if (!hex) return false;
    }
    return true;
}

pub fn takeShortSha(raw: []const u8) ?[]const u8 {
    const name = firstStdoutBranch(raw);
    if (!isPlausibleShortSha(name)) return null;
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
/// selected session has an existing `project_path`. Empty / missing
/// skips the spawn so the label stays omitted.
pub fn refresh(model: *Model, fx: *Effects) void {
    cancelInFlight(model, fx);
    clearGitBranch(model);
    if (!probeSupported()) return;
    const cwd = probePath(model);
    if (cwd.len == 0) return;

    const key = model.next_git_branch_key;
    model.next_git_branch_key = key + 1;
    model.git_branch_key = key;
    model.git_branch_probe_session = model.selected;
    model.git_branch_probe_is_rev_parse = false;
    writeFixed(&model.git_branch_probe_path_storage, &model.git_branch_probe_path_len, cwd);

    var argv_buf: [argv_len][]const u8 = undefined;
    fx.spawn(.{
        .key = key,
        .argv = argvFor(cwd, &argv_buf),
        .on_line = Effects.lineMsg(.fx_line),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
}

fn spawnRevParse(model: *Model, fx: *Effects, cwd: []const u8) void {
    if (!probeSupported()) return;
    const key = model.next_git_branch_key;
    model.next_git_branch_key = key + 1;
    model.git_branch_key = key;
    model.git_branch_probe_is_rev_parse = true;
    var argv_buf: [rev_parse_argv_len][]const u8 = undefined;
    fx.spawn(.{
        .key = key,
        .argv = revParseArgvFor(cwd, &argv_buf),
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
    if (model.git_branch_probe_is_rev_parse) {
        if (takeShortSha(line.line)) |name| {
            setGitBranch(model, name);
        } else {
            clearGitBranch(model);
        }
        return;
    }
    if (takeBranchName(line.line)) |name| {
        setGitBranch(model, name);
    } else {
        clearGitBranch(model);
    }
}

pub fn handleExit(model: *Model, fx: *Effects, exit: native_sdk.EffectExit) void {
    if (exit.key != model.git_branch_key or model.git_branch_key == 0) return;
    const current = probeStillCurrent(model);
    const was_rev_parse = model.git_branch_probe_is_rev_parse;
    model.git_branch_key = 0;
    model.git_branch_probe_is_rev_parse = false;
    if (!current or exit.reason != .exited or exit.code != 0) {
        if (!was_rev_parse) clearGitBranch(model);
        return;
    }
    if (was_rev_parse or hasGitBranch(model)) return;
    const cwd = probePath(model);
    if (cwd.len == 0) return;
    spawnRevParse(model, fx, cwd);
}

test "argv is chdir script plus git branch --show-current" {
    const git_dirty = @import("git_dirty.zig");
    const file_mention = @import("file_mention.zig");
    var buf: [argv_len][]const u8 = undefined;
    const argv = unixArgvFor("/tmp/faku-git", &buf);
    try std.testing.expectEqual(@as(usize, unix_argv_len), argv.len);
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
    try std.testing.expect(!isGitRevParseArgv(argv));
    var dirty_buf: [git_dirty.argv_len][]const u8 = undefined;
    try std.testing.expect(!isGitBranchArgv(git_dirty.unixArgvFor("/tmp/faku-git", &dirty_buf)));
    try std.testing.expect(!git_dirty.isGitDirtyArgv(argv));
    var mention_buf: [file_mention.git_argv_len][]const u8 = undefined;
    try std.testing.expect(!isGitBranchArgv(file_mention.unixArgvFor("/tmp/faku-git", &mention_buf)));
    try std.testing.expect(!file_mention.isGitLsFilesArgv(argv));
}

test "windows git argv is git.exe -C PATH branch --show-current; path is its own slot" {
    const git_dirty = @import("git_dirty.zig");
    const file_mention = @import("file_mention.zig");
    var buf: [argv_len][]const u8 = undefined;
    const cwd = "C:\\Users\\me\\proj";
    const argv = windowsArgvFor(cwd, &buf);
    try std.testing.expectEqual(@as(usize, windows_argv_len), argv.len);
    try std.testing.expect(argv.len <= 16);
    try std.testing.expectEqualStrings(windows_git_bin, argv[0]);
    try std.testing.expectEqualStrings(git_c_flag, argv[1]);
    try std.testing.expectEqualStrings(cwd, argv[2]);
    try std.testing.expectEqualStrings(git_branch_cmd, argv[3]);
    try std.testing.expectEqualStrings(git_show_current, argv[4]);
    try std.testing.expect(isGitBranchArgv(argv));
    try std.testing.expect(!isGitRevParseArgv(argv));
    try std.testing.expect(!isGitBranchArgv(&.{ windows_git_bin, git_c_flag, cwd }));
    var git_only: [argv_len][]const u8 = undefined;
    git_only[0] = git_bin;
    git_only[1] = git_c_flag;
    git_only[2] = cwd;
    git_only[3] = git_branch_cmd;
    git_only[4] = git_show_current;
    try std.testing.expect(isGitBranchArgv(git_only[0..windows_argv_len]));
    var dirty_buf: [git_dirty.argv_len][]const u8 = undefined;
    try std.testing.expect(!isGitBranchArgv(git_dirty.windowsArgvFor(cwd, &dirty_buf)));
    try std.testing.expect(!git_dirty.isGitDirtyArgv(argv));
    var mention_buf: [file_mention.git_argv_len][]const u8 = undefined;
    try std.testing.expect(!isGitBranchArgv(file_mention.windowsArgvFor(cwd, &mention_buf)));
    try std.testing.expect(!file_mention.isGitLsFilesArgv(argv));
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

test "rev-parse argv is chdir script plus git rev-parse --short HEAD" {
    var buf: [rev_parse_argv_len][]const u8 = undefined;
    const argv = unixRevParseArgvFor("/tmp/faku-sha", &buf);
    try std.testing.expectEqual(@as(usize, unix_rev_parse_argv_len), argv.len);
    try std.testing.expectEqualStrings(sh_bin, argv[0]);
    try std.testing.expectEqualStrings("-c", argv[1]);
    try std.testing.expectEqualStrings(main.fx_ask_chdir_script, argv[2]);
    try std.testing.expectEqualStrings("/tmp/faku-sha", argv[4]);
    try std.testing.expectEqualStrings(git_bin, argv[5]);
    try std.testing.expectEqualStrings(git_rev_parse_cmd, argv[6]);
    try std.testing.expectEqualStrings(git_short, argv[7]);
    try std.testing.expectEqualStrings(git_head, argv[8]);
    try std.testing.expect(isGitRevParseArgv(argv));
    try std.testing.expect(!isGitBranchArgv(argv));
    try std.testing.expect(!isGitRevParseArgv(&.{ git_bin, git_rev_parse_cmd, git_short, git_head }));
}

test "windows rev-parse argv is git.exe -C PATH rev-parse --short HEAD" {
    var buf: [rev_parse_argv_len][]const u8 = undefined;
    const cwd = "C:\\Users\\me\\proj";
    const argv = windowsRevParseArgvFor(cwd, &buf);
    try std.testing.expectEqual(@as(usize, windows_rev_parse_argv_len), argv.len);
    try std.testing.expect(argv.len <= 16);
    try std.testing.expectEqualStrings(windows_git_bin, argv[0]);
    try std.testing.expectEqualStrings(git_c_flag, argv[1]);
    try std.testing.expectEqualStrings(cwd, argv[2]);
    try std.testing.expectEqualStrings(git_rev_parse_cmd, argv[3]);
    try std.testing.expectEqualStrings(git_short, argv[4]);
    try std.testing.expectEqualStrings(git_head, argv[5]);
    try std.testing.expect(isGitRevParseArgv(argv));
    try std.testing.expect(!isGitBranchArgv(argv));
    try std.testing.expect(!isGitRevParseArgv(&.{ windows_git_bin, git_c_flag, cwd }));
    var git_only: [rev_parse_argv_len][]const u8 = undefined;
    git_only[0] = git_bin;
    git_only[1] = git_c_flag;
    git_only[2] = cwd;
    git_only[3] = git_rev_parse_cmd;
    git_only[4] = git_short;
    git_only[5] = git_head;
    try std.testing.expect(isGitRevParseArgv(git_only[0..windows_rev_parse_argv_len]));
    var branch_buf: [argv_len][]const u8 = undefined;
    try std.testing.expect(!isGitRevParseArgv(windowsArgvFor(cwd, &branch_buf)));
}

test "host argvFor and revParseArgvFor match the process OS" {
    var branch_buf: [argv_len][]const u8 = undefined;
    const branch = argvFor("/tmp/faku-git", &branch_buf);
    try std.testing.expect(isGitBranchArgv(branch));
    var rev_buf: [rev_parse_argv_len][]const u8 = undefined;
    const rev = revParseArgvFor("/tmp/faku-sha", &rev_buf);
    try std.testing.expect(isGitRevParseArgv(rev));
    try std.testing.expect(!isGitRevParseArgv(branch));
    try std.testing.expect(!isGitBranchArgv(rev));
    switch (builtin.os.tag) {
        .windows => {
            try std.testing.expectEqualStrings(windows_git_bin, branch[0]);
            try std.testing.expectEqualStrings(git_c_flag, branch[1]);
            try std.testing.expectEqualStrings(windows_git_bin, rev[0]);
            try std.testing.expectEqualStrings(git_c_flag, rev[1]);
        },
        else => {
            try std.testing.expectEqualStrings(sh_bin, branch[0]);
            try std.testing.expectEqualStrings(sh_bin, rev[0]);
            try std.testing.expectEqualStrings(git_show_current, branch[7]);
            try std.testing.expectEqualStrings(git_head, rev[8]);
        },
    }
}

test "probeSupported is true on macOS, Linux, and Windows" {
    try std.testing.expect(probeSupported());
}

test "takeShortSha accepts conservative hex only" {
    try std.testing.expectEqualStrings("a1b2c3d", takeShortSha("  a1b2c3d \n").?);
    try std.testing.expectEqualStrings("DEADBEEF", takeShortSha("DEADBEEF").?);
    try std.testing.expect(takeShortSha("abc") == null);
    try std.testing.expect(takeShortSha("HEAD") == null);
    try std.testing.expect(takeShortSha("main") == null);
    try std.testing.expect(takeShortSha("not-hex") == null);
    try std.testing.expect(takeShortSha("   ") == null);
    try std.testing.expect(!isPlausibleShortSha("123"));
    try std.testing.expect(isPlausibleShortSha("abcd"));
}
