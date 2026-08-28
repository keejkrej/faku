//! First-cut local branch list + checkout for the composer project row.
//!
//! Native has no git/workspace effect. When the selected session has a
//! non-empty `project_path` that exists, Faku `fx.spawn`s
//! `git for-each-ref --format=%(refname:short) refs/heads` through the
//! same `/bin/sh -c` chdir workaround `fx ask` uses
//! (`fx_ask_chdir_script`). Checking out a listed name one-shots
//! `git checkout <name>` with that name as its own argv slot — never
//! interpolated into the `-c` script. Cap is 64 local heads, sorted
//! lexicographically. Not Waku's daemon `InspectBranches` picker,
//! worktrees, create-branch, remotes, stash, merge, or a live watch.
//!
//! Spawn/line/exit orchestration lives here. Windows is skipped
//! (app.zon is macos/linux; no Windows spawn path).

const std = @import("std");
const builtin = @import("builtin");
const native_sdk = @import("native_sdk");
const main = @import("main.zig");
const git_branch = @import("git_branch.zig");
const git_dirty = @import("git_dirty.zig");
const git_numstat = @import("git_numstat.zig");
const file_mention = @import("file_mention.zig");

const Model = main.Model;
const Effects = main.Effects;
const writeFixed = main.writeFixed;

/// One-shot local `refs/heads` list. Distinct from git_branch (200+),
/// git_checkout (275+), git_dirty (300+), git_numstat (350+), and
/// file_mention (400+). Incremented per refresh so a cancelled spawn
/// cannot paint a later session.
pub const git_branch_list_key_first: u64 = 250;

/// One-shot `git checkout <name>`. Distinct from the list family
/// (250+), git_branch (200+), git_dirty (300+), git_numstat (350+),
/// and file_mention (400+).
pub const git_checkout_key_first: u64 = 275;

pub const max_local_branches: usize = 64;
pub const checkout_failed_status = "Could not check out branch.";

pub const git_bin = git_branch.git_bin;
pub const git_for_each_ref_cmd = "for-each-ref";
pub const git_refname_short_format = "--format=%(refname:short)";
pub const git_heads_ref = "refs/heads";
pub const git_checkout_cmd = "checkout";
pub const sh_bin = git_branch.sh_bin;

const list_argv_len: usize = 9;
const checkout_argv_len: usize = 8;

pub const CachedBranch = struct {
    storage: [git_branch.max_git_branch]u8 = [_]u8{0} ** git_branch.max_git_branch,
    len: usize = 0,

    pub fn text(self: *const CachedBranch) []const u8 {
        return self.storage[0..self.len];
    }

    pub fn set(self: *CachedBranch, name: []const u8) void {
        writeFixed(&self.storage, &self.len, name);
    }
};

pub fn listArgvFor(cwd: []const u8, buf: *[list_argv_len][]const u8) []const []const u8 {
    buf.* = .{
        sh_bin,
        "-c",
        main.fx_ask_chdir_script,
        "sh",
        cwd,
        git_bin,
        git_for_each_ref_cmd,
        git_refname_short_format,
        git_heads_ref,
    };
    return buf;
}

pub fn isGitBranchListArgv(argv: []const []const u8) bool {
    if (argv.len != list_argv_len) return false;
    if (!std.mem.eql(u8, argv[0], sh_bin)) return false;
    if (!std.mem.eql(u8, argv[1], "-c")) return false;
    if (!std.mem.eql(u8, argv[2], main.fx_ask_chdir_script)) return false;
    if (!std.mem.eql(u8, argv[5], git_bin)) return false;
    if (!std.mem.eql(u8, argv[6], git_for_each_ref_cmd)) return false;
    if (!std.mem.eql(u8, argv[7], git_refname_short_format)) return false;
    return std.mem.eql(u8, argv[8], git_heads_ref);
}

/// `git checkout <name>` as a trailing argv slot. Rejects names that
/// fail `isPlausibleBranchName` so a raw string never reaches the
/// shell script.
pub fn checkoutArgvFor(cwd: []const u8, name: []const u8, buf: *[checkout_argv_len][]const u8) ?[]const []const u8 {
    if (!git_branch.isPlausibleBranchName(name)) return null;
    buf.* = .{
        sh_bin,
        "-c",
        main.fx_ask_chdir_script,
        "sh",
        cwd,
        git_bin,
        git_checkout_cmd,
        name,
    };
    return buf;
}

pub fn isGitCheckoutArgv(argv: []const []const u8) bool {
    if (argv.len != checkout_argv_len) return false;
    if (!std.mem.eql(u8, argv[0], sh_bin)) return false;
    if (!std.mem.eql(u8, argv[1], "-c")) return false;
    if (!std.mem.eql(u8, argv[2], main.fx_ask_chdir_script)) return false;
    if (!std.mem.eql(u8, argv[5], git_bin)) return false;
    if (!std.mem.eql(u8, argv[6], git_checkout_cmd)) return false;
    return git_branch.isPlausibleBranchName(argv[7]);
}

fn branchNameLessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

/// Trim, skip empty / implausible names, cap at `out.len`, then sort
/// lexicographically. Slices alias `raw`.
pub fn collectStdoutBranches(raw: []const u8, out: [][]const u8) usize {
    var n: usize = 0;
    var it = std.mem.splitScalar(u8, raw, '\n');
    while (it.next()) |line| {
        if (n >= out.len) break;
        const name = std.mem.trim(u8, line, " \t\r\n");
        if (!git_branch.isPlausibleBranchName(name)) continue;
        out[n] = name;
        n += 1;
    }
    std.mem.sort([]const u8, out[0..n], {}, branchNameLessThan);
    return n;
}

fn cachedBranchLessThan(_: void, a: CachedBranch, b: CachedBranch) bool {
    return std.mem.lessThan(u8, a.text(), b.text());
}

pub fn sortListedBranches(model: *Model) void {
    const n = model.git_branch_list_count;
    if (n < 2) return;
    std.mem.sort(CachedBranch, model.git_branch_list_store[0..n], {}, cachedBranchLessThan);
}

pub fn listedBranch(model: *const Model, index: usize) []const u8 {
    if (index >= model.git_branch_list_count) return "";
    return model.git_branch_list_store[index].text();
}

pub fn hasListedBranches(model: *const Model) bool {
    return model.git_branch_list_count > 0;
}

pub fn canPickGitBranch(model: *const Model) bool {
    return git_branch.hasGitBranch(model) or hasListedBranches(model);
}

pub fn clearListedBranches(model: *Model) void {
    model.git_branch_list_count = 0;
}

pub fn closePicker(model: *Model) void {
    model.git_branch_picker_open = false;
}

fn appendListedBranch(model: *Model, name: []const u8) void {
    if (model.git_branch_list_count >= max_local_branches) return;
    if (!git_branch.isPlausibleBranchName(name)) return;
    var i: usize = 0;
    while (i < model.git_branch_list_count) : (i += 1) {
        if (std.mem.eql(u8, listedBranch(model, i), name)) return;
    }
    model.git_branch_list_store[model.git_branch_list_count].set(name);
    model.git_branch_list_count += 1;
}

pub fn applyStdoutBranches(model: *Model, raw: []const u8) void {
    var names: [max_local_branches][]const u8 = undefined;
    const n = collectStdoutBranches(raw, names[0..]);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        appendListedBranch(model, names[i]);
    }
}

fn cancelList(model: *Model, fx: *Effects) void {
    if (model.git_branch_list_key == 0) return;
    fx.cancel(model.git_branch_list_key);
    model.git_branch_list_key = 0;
}

fn cancelCheckout(model: *Model, fx: *Effects) void {
    if (model.git_checkout_key == 0) return;
    fx.cancel(model.git_checkout_key);
    model.git_checkout_key = 0;
}

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

/// Cancel any in-flight list / checkout, drop the cached heads, and
/// spawn `for-each-ref` when the selected session has an existing
/// `project_path`. Empty / missing / Windows skips the spawn so the
/// picker stays omitted unless `has_git_branch` is already true.
pub fn refresh(model: *Model, fx: *Effects) void {
    cancelList(model, fx);
    cancelCheckout(model, fx);
    clearListedBranches(model);
    closePicker(model);
    if (!probeSupported()) return;
    const cwd = probePath(model);
    if (cwd.len == 0) return;

    const key = model.next_git_branch_list_key;
    model.next_git_branch_list_key = key + 1;
    model.git_branch_list_key = key;
    model.git_branch_list_probe_session = model.selected;
    writeFixed(&model.git_branch_list_probe_path_storage, &model.git_branch_list_probe_path_len, cwd);

    var argv_buf: [list_argv_len][]const u8 = undefined;
    fx.spawn(.{
        .key = key,
        .argv = listArgvFor(cwd, &argv_buf),
        .on_line = Effects.lineMsg(.fx_line),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
}

fn listStillCurrent(model: *const Model) bool {
    if (model.git_branch_list_key == 0) return false;
    if (model.git_branch_list_probe_session != model.selected) return false;
    const path = model.selectedProjectPath();
    const probed = model.git_branch_list_probe_path_storage[0..model.git_branch_list_probe_path_len];
    return std.mem.eql(u8, path, probed);
}

fn checkoutStillCurrent(model: *const Model) bool {
    if (model.git_checkout_key == 0) return false;
    if (model.git_checkout_probe_session != model.selected) return false;
    const path = model.selectedProjectPath();
    const probed = model.git_checkout_probe_path_storage[0..model.git_checkout_probe_path_len];
    return std.mem.eql(u8, path, probed);
}

pub fn applyListLine(model: *Model, line: native_sdk.EffectLine) void {
    if (line.key != model.git_branch_list_key or model.git_branch_list_key == 0) return;
    if (!listStillCurrent(model)) return;
    applyStdoutBranches(model, line.line);
}

pub fn handleListExit(model: *Model, exit: native_sdk.EffectExit) void {
    if (exit.key != model.git_branch_list_key or model.git_branch_list_key == 0) return;
    const current = listStillCurrent(model);
    model.git_branch_list_key = 0;
    if (!current or exit.reason != .exited or exit.code != 0) {
        clearListedBranches(model);
        if (!git_branch.hasGitBranch(model)) closePicker(model);
        return;
    }
    sortListedBranches(model);
}

fn refreshWorkspaceProbes(model: *Model, fx: *Effects) void {
    git_branch.refresh(model, fx);
    git_dirty.refresh(model, fx);
    git_numstat.refresh(model, fx);
    file_mention.refresh(model, fx);
    refresh(model, fx);
}

/// Selecting the current branch closes the picker. Another plausible
/// local name one-shots `git checkout`. Implausible names are ignored.
pub fn pickBranch(model: *Model, fx: *Effects, name: []const u8) void {
    closePicker(model);
    if (!git_branch.isPlausibleBranchName(name)) return;
    if (std.mem.eql(u8, name, git_branch.gitBranchLabel(model))) return;
    if (!probeSupported()) return;
    const cwd = probePath(model);
    if (cwd.len == 0) return;

    var argv_buf: [checkout_argv_len][]const u8 = undefined;
    const argv = checkoutArgvFor(cwd, name, &argv_buf) orelse return;

    cancelCheckout(model, fx);
    const key = model.next_git_checkout_key;
    model.next_git_checkout_key = key + 1;
    model.git_checkout_key = key;
    model.git_checkout_probe_session = model.selected;
    writeFixed(&model.git_checkout_probe_path_storage, &model.git_checkout_probe_path_len, cwd);

    fx.spawn(.{
        .key = key,
        .argv = argv,
        .on_line = Effects.lineMsg(.fx_line),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
}

pub fn handleCheckoutExit(model: *Model, fx: *Effects, exit: native_sdk.EffectExit) void {
    if (exit.key != model.git_checkout_key or model.git_checkout_key == 0) return;
    const current = checkoutStillCurrent(model);
    model.git_checkout_key = 0;
    if (!current) return;
    if (exit.reason == .exited and exit.code == 0) {
        refreshWorkspaceProbes(model, fx);
        return;
    }
    model.setAttachStatus(checkout_failed_status);
}

test "list argv is chdir script plus for-each-ref refs/heads" {
    var buf: [list_argv_len][]const u8 = undefined;
    const argv = listArgvFor("/tmp/faku-heads", &buf);
    try std.testing.expectEqualStrings(sh_bin, argv[0]);
    try std.testing.expectEqualStrings("-c", argv[1]);
    try std.testing.expectEqualStrings(main.fx_ask_chdir_script, argv[2]);
    try std.testing.expectEqualStrings("sh", argv[3]);
    try std.testing.expectEqualStrings("/tmp/faku-heads", argv[4]);
    try std.testing.expectEqualStrings(git_bin, argv[5]);
    try std.testing.expectEqualStrings(git_for_each_ref_cmd, argv[6]);
    try std.testing.expectEqualStrings(git_refname_short_format, argv[7]);
    try std.testing.expectEqualStrings(git_heads_ref, argv[8]);
    try std.testing.expect(isGitBranchListArgv(argv));
    try std.testing.expect(!isGitBranchListArgv(&.{ git_bin, git_for_each_ref_cmd, git_refname_short_format, git_heads_ref }));
    try std.testing.expect(!git_branch.isGitBranchArgv(argv));
    try std.testing.expect(!isGitCheckoutArgv(argv));
}

test "checkout argv keeps the name as its own slot and rejects implausible names" {
    var buf: [checkout_argv_len][]const u8 = undefined;
    const argv = checkoutArgvFor("/tmp/faku-co", "feat/composer", &buf).?;
    try std.testing.expectEqualStrings(sh_bin, argv[0]);
    try std.testing.expectEqualStrings(main.fx_ask_chdir_script, argv[2]);
    try std.testing.expectEqualStrings("/tmp/faku-co", argv[4]);
    try std.testing.expectEqualStrings(git_bin, argv[5]);
    try std.testing.expectEqualStrings(git_checkout_cmd, argv[6]);
    try std.testing.expectEqualStrings("feat/composer", argv[7]);
    try std.testing.expect(isGitCheckoutArgv(argv));
    try std.testing.expect(!isGitBranchListArgv(argv));
    try std.testing.expect(!git_branch.isGitBranchArgv(argv));
    try std.testing.expect(std.mem.indexOf(u8, argv[2], "feat/composer") == null);

    try std.testing.expect(checkoutArgvFor("/tmp/faku-co", "not a branch", &buf) == null);
    try std.testing.expect(checkoutArgvFor("/tmp/faku-co", "../escape", &buf) == null);
    try std.testing.expect(checkoutArgvFor("/tmp/faku-co", "/abs", &buf) == null);
    try std.testing.expect(checkoutArgvFor("/tmp/faku-co", ".hidden", &buf) == null);
    try std.testing.expect(checkoutArgvFor("/tmp/faku-co", "trailing.", &buf) == null);
    try std.testing.expect(checkoutArgvFor("/tmp/faku-co", "@", &buf) == null);
    try std.testing.expect(checkoutArgvFor("/tmp/faku-co", "foo@{bar", &buf) == null);
    try std.testing.expect(checkoutArgvFor("/tmp/faku-co", "", &buf) == null);
    try std.testing.expect(git_checkout_key_first > git_branch_list_key_first);
    try std.testing.expect(git_branch_list_key_first > git_branch.git_branch_key_first);
    try std.testing.expect(git_dirty.git_dirty_key_first > git_checkout_key_first);
}

test "collectStdoutBranches trims, skips empty/implausible, sorts, and caps" {
    var names: [max_local_branches][]const u8 = undefined;
    const n = collectStdoutBranches("  zeta \n\nmain\nnot a branch\n../escape\nfeat/a\n", names[0..]);
    try std.testing.expectEqual(@as(usize, 3), n);
    try std.testing.expectEqualStrings("feat/a", names[0]);
    try std.testing.expectEqualStrings("main", names[1]);
    try std.testing.expectEqualStrings("zeta", names[2]);

    try std.testing.expectEqual(@as(usize, 0), collectStdoutBranches("   \n\n", names[0..]));
    try std.testing.expectEqual(@as(usize, 0), collectStdoutBranches("", names[0..]));

    var tiny: [1][]const u8 = undefined;
    const capped = collectStdoutBranches("c\nb\na\n", tiny[0..]);
    try std.testing.expectEqual(@as(usize, 1), capped);
}
