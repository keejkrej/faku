//! First-cut local branch list + checkout + create-and-checkout +
//! safe delete for the composer project row.
//!
//! Native has no git/workspace effect. When the selected session has a
//! non-empty `project_path` that exists, Faku `fx.spawn`s
//! `git for-each-ref --format=%(refname:short) refs/heads` through the
//! same `/bin/sh -c` chdir workaround `fx ask` uses
//! (`fx_ask_chdir_script`). Checking out a listed name one-shots
//! `git checkout <name>` with that name as its own argv slot — never
//! interpolated into the `-c` script. New branch… one-shots
//! `git checkout -b <name>` the same way (from current HEAD; no
//! tracking / remotes). Delete branch… one-shots `git branch -d
//! <name>` the same way (safe delete only; never `-D`). Cap is 64
//! local heads, sorted lexicographically. Not Waku's daemon
//! `InspectBranches` picker, worktrees, remotes, stash, merge, force
//! delete, or a live watch.
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
/// git_checkout (275+), git_create (290+), git_dirty (300+),
/// git_delete (320+), git_numstat (350+), and file_mention (400+).
/// Incremented per refresh so a cancelled spawn cannot paint a later
/// session.
pub const git_branch_list_key_first: u64 = 250;

/// One-shot `git checkout <name>`. Distinct from the list family
/// (250+), git_create (290+), git_branch (200+), git_dirty (300+),
/// git_delete (320+), git_numstat (350+), and file_mention (400+).
pub const git_checkout_key_first: u64 = 275;

/// One-shot `git checkout -b <name>`. Distinct from list (250+),
/// checkout (275+), git_dirty (300+), git_delete (320+),
/// git_numstat (350+), and file_mention (400+). Band is 290+
/// (below dirty 300+).
pub const git_create_key_first: u64 = 290;

/// One-shot `git branch -d <name>`. Distinct from list (250+),
/// checkout (275+), create (290+), git_dirty (300+), git_numstat
/// (350+), and file_mention (400+). Band is 320+ (between dirty
/// 300+ and numstat 350+).
pub const git_delete_key_first: u64 = 320;

pub const max_local_branches: usize = 64;
pub const checkout_failed_status = "Could not check out branch.";
pub const create_failed_status = "Could not create branch.";
pub const delete_failed_status = "Could not delete branch.";

pub const git_bin = git_branch.git_bin;
pub const git_for_each_ref_cmd = "for-each-ref";
pub const git_refname_short_format = "--format=%(refname:short)";
pub const git_heads_ref = "refs/heads";
pub const git_checkout_cmd = "checkout";
pub const git_create_b_flag = "-b";
pub const git_branch_cmd = git_branch.git_branch_cmd;
pub const git_delete_d_flag = "-d";
pub const sh_bin = git_branch.sh_bin;

const list_argv_len: usize = 9;
const checkout_argv_len: usize = 8;
const create_argv_len: usize = 9;
const delete_argv_len: usize = 9;

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

/// `git checkout -b <name>` with the name as a trailing argv slot.
/// Rejects names that fail `isPlausibleBranchName` so a raw string
/// never reaches the shell script.
pub fn createArgvFor(cwd: []const u8, name: []const u8, buf: *[create_argv_len][]const u8) ?[]const []const u8 {
    if (!git_branch.isPlausibleBranchName(name)) return null;
    buf.* = .{
        sh_bin,
        "-c",
        main.fx_ask_chdir_script,
        "sh",
        cwd,
        git_bin,
        git_checkout_cmd,
        git_create_b_flag,
        name,
    };
    return buf;
}

pub fn isGitCreateArgv(argv: []const []const u8) bool {
    if (argv.len != create_argv_len) return false;
    if (!std.mem.eql(u8, argv[0], sh_bin)) return false;
    if (!std.mem.eql(u8, argv[1], "-c")) return false;
    if (!std.mem.eql(u8, argv[2], main.fx_ask_chdir_script)) return false;
    if (!std.mem.eql(u8, argv[5], git_bin)) return false;
    if (!std.mem.eql(u8, argv[6], git_checkout_cmd)) return false;
    if (!std.mem.eql(u8, argv[7], git_create_b_flag)) return false;
    return git_branch.isPlausibleBranchName(argv[8]);
}

/// `git branch -d <name>` with the name as a trailing argv slot.
/// Rejects names that fail `isPlausibleBranchName` so a raw string
/// never reaches the shell script. Never emits `-D`.
pub fn deleteArgvFor(cwd: []const u8, name: []const u8, buf: *[delete_argv_len][]const u8) ?[]const []const u8 {
    if (!git_branch.isPlausibleBranchName(name)) return null;
    buf.* = .{
        sh_bin,
        "-c",
        main.fx_ask_chdir_script,
        "sh",
        cwd,
        git_bin,
        git_branch_cmd,
        git_delete_d_flag,
        name,
    };
    return buf;
}

pub fn isGitDeleteArgv(argv: []const []const u8) bool {
    if (argv.len != delete_argv_len) return false;
    if (!std.mem.eql(u8, argv[0], sh_bin)) return false;
    if (!std.mem.eql(u8, argv[1], "-c")) return false;
    if (!std.mem.eql(u8, argv[2], main.fx_ask_chdir_script)) return false;
    if (!std.mem.eql(u8, argv[5], git_bin)) return false;
    if (!std.mem.eql(u8, argv[6], git_branch_cmd)) return false;
    if (!std.mem.eql(u8, argv[7], git_delete_d_flag)) return false;
    return git_branch.isPlausibleBranchName(argv[8]);
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

/// True when at least one listed local head is not the current branch.
/// Detached HEAD (sha label) treats every listed head as deletable.
pub fn canDeleteGitBranch(model: *const Model) bool {
    const current = git_branch.gitBranchLabel(model);
    var i: usize = 0;
    while (i < model.git_branch_list_count) : (i += 1) {
        const name = listedBranch(model, i);
        if (!git_branch.isPlausibleBranchName(name)) continue;
        if (std.mem.eql(u8, name, current)) continue;
        return true;
    }
    return false;
}

pub fn gitBranchDeleteLabel(model: *const Model) []const u8 {
    return model.git_branch_delete_storage[0..model.git_branch_delete_len];
}

fn isListedNonCurrent(model: *const Model, name: []const u8) bool {
    if (!git_branch.isPlausibleBranchName(name)) return false;
    if (std.mem.eql(u8, name, git_branch.gitBranchLabel(model))) return false;
    var i: usize = 0;
    while (i < model.git_branch_list_count) : (i += 1) {
        if (std.mem.eql(u8, listedBranch(model, i), name)) return true;
    }
    return false;
}

pub fn clearListedBranches(model: *Model) void {
    model.git_branch_list_count = 0;
}

pub fn closePicker(model: *Model) void {
    model.git_branch_picker_open = false;
}

pub fn closeCreate(model: *Model) void {
    model.git_branch_create_active = false;
    model.git_branch_create_buffer.clear();
}

pub fn closeDelete(model: *Model) void {
    model.git_branch_delete_active = false;
    model.git_branch_delete_picker_open = false;
    model.git_branch_delete_len = 0;
}

/// Dismiss the select list and open the runtime-only create card.
/// Draft name is not persisted.
pub fn startCreate(model: *Model) void {
    closePicker(model);
    closeDelete(model);
    model.closeProjectEdit();
    model.git_branch_create_active = true;
}

/// Dismiss the select list and open the runtime-only delete card of
/// non-current listed local heads. Selected name is not persisted.
pub fn startDelete(model: *Model) void {
    closePicker(model);
    closeCreate(model);
    model.closeProjectEdit();
    model.git_branch_delete_active = true;
    model.git_branch_delete_picker_open = false;
    model.git_branch_delete_len = 0;
}

pub fn closeDeletePicker(model: *Model) void {
    model.git_branch_delete_picker_open = false;
}

pub fn toggleDeletePicker(model: *Model) void {
    if (!model.git_branch_delete_active) {
        model.git_branch_delete_picker_open = false;
        return;
    }
    model.git_branch_delete_picker_open = !model.git_branch_delete_picker_open;
}

/// Remember a listed non-current name on the delete card. Does not spawn.
pub fn pickDeleteName(model: *Model, name: []const u8) void {
    model.git_branch_delete_picker_open = false;
    if (!isListedNonCurrent(model, name)) return;
    writeFixed(&model.git_branch_delete_storage, &model.git_branch_delete_len, name);
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

fn cancelCreate(model: *Model, fx: *Effects) void {
    if (model.git_create_key == 0) return;
    fx.cancel(model.git_create_key);
    model.git_create_key = 0;
}

fn cancelDelete(model: *Model, fx: *Effects) void {
    if (model.git_delete_key == 0) return;
    fx.cancel(model.git_delete_key);
    model.git_delete_key = 0;
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

/// Cancel any in-flight list / checkout / create / delete, drop the
/// cached heads, and spawn `for-each-ref` when the selected session
/// has an existing `project_path`. Empty / missing / Windows skips
/// the spawn so the picker stays omitted unless `has_git_branch` is
/// already true.
pub fn refresh(model: *Model, fx: *Effects) void {
    cancelList(model, fx);
    cancelCheckout(model, fx);
    cancelCreate(model, fx);
    cancelDelete(model, fx);
    clearListedBranches(model);
    closePicker(model);
    closeCreate(model);
    closeDelete(model);
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

fn createStillCurrent(model: *const Model) bool {
    if (model.git_create_key == 0) return false;
    if (model.git_create_probe_session != model.selected) return false;
    const path = model.selectedProjectPath();
    const probed = model.git_create_probe_path_storage[0..model.git_create_probe_path_len];
    return std.mem.eql(u8, path, probed);
}

fn deleteStillCurrent(model: *const Model) bool {
    if (model.git_delete_key == 0) return false;
    if (model.git_delete_probe_session != model.selected) return false;
    const path = model.selectedProjectPath();
    const probed = model.git_delete_probe_path_storage[0..model.git_delete_probe_path_len];
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
/// In-flight create or delete is a no-op so the one-shots do not overlap.
pub fn pickBranch(model: *Model, fx: *Effects, name: []const u8) void {
    closePicker(model);
    if (model.git_create_key != 0 or model.git_delete_key != 0) return;
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

/// Confirm the create card: plausible draft one-shots `git checkout -b`.
/// Empty / implausible names do not spawn and keep the field open.
/// Busy session or in-flight create/checkout/delete is a no-op.
pub fn confirmCreate(model: *Model, fx: *Effects) void {
    if (model.git_create_key != 0 or model.git_checkout_key != 0 or model.git_delete_key != 0) return;
    if (model.is_streaming()) return;
    const name = std.mem.trim(u8, model.git_branch_create_buffer.text(), " \t\r\n");
    if (!git_branch.isPlausibleBranchName(name)) return;
    if (!probeSupported()) return;
    const cwd = probePath(model);
    if (cwd.len == 0) return;

    var argv_buf: [create_argv_len][]const u8 = undefined;
    const argv = createArgvFor(cwd, name, &argv_buf) orelse return;

    const key = model.next_git_create_key;
    model.next_git_create_key = key + 1;
    model.git_create_key = key;
    model.git_create_probe_session = model.selected;
    writeFixed(&model.git_create_probe_path_storage, &model.git_create_probe_path_len, cwd);

    fx.spawn(.{
        .key = key,
        .argv = argv,
        .on_line = Effects.lineMsg(.fx_line),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
}

pub fn handleCreateExit(model: *Model, fx: *Effects, exit: native_sdk.EffectExit) void {
    if (exit.key != model.git_create_key or model.git_create_key == 0) return;
    const current = createStillCurrent(model);
    model.git_create_key = 0;
    if (!current) return;
    if (exit.reason == .exited and exit.code == 0) {
        closeCreate(model);
        refreshWorkspaceProbes(model, fx);
        return;
    }
    model.setAttachStatus(create_failed_status);
}

/// Confirm the delete card: a listed non-current name one-shots
/// `git branch -d`. Empty / current / implausible names do not spawn
/// and keep the card open. Busy session or in-flight checkout/create/
/// delete is a no-op.
pub fn confirmDelete(model: *Model, fx: *Effects) void {
    if (model.git_delete_key != 0 or model.git_checkout_key != 0 or model.git_create_key != 0) return;
    if (model.is_streaming()) return;
    const name = std.mem.trim(u8, gitBranchDeleteLabel(model), " \t\r\n");
    if (!isListedNonCurrent(model, name)) return;
    if (!probeSupported()) return;
    const cwd = probePath(model);
    if (cwd.len == 0) return;

    var argv_buf: [delete_argv_len][]const u8 = undefined;
    const argv = deleteArgvFor(cwd, name, &argv_buf) orelse return;

    const key = model.next_git_delete_key;
    model.next_git_delete_key = key + 1;
    model.git_delete_key = key;
    model.git_delete_probe_session = model.selected;
    writeFixed(&model.git_delete_probe_path_storage, &model.git_delete_probe_path_len, cwd);

    fx.spawn(.{
        .key = key,
        .argv = argv,
        .on_line = Effects.lineMsg(.fx_line),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
}

pub fn handleDeleteExit(model: *Model, fx: *Effects, exit: native_sdk.EffectExit) void {
    if (exit.key != model.git_delete_key or model.git_delete_key == 0) return;
    const current = deleteStillCurrent(model);
    model.git_delete_key = 0;
    if (!current) return;
    if (exit.reason == .exited and exit.code == 0) {
        closeDelete(model);
        refreshWorkspaceProbes(model, fx);
        return;
    }
    model.setAttachStatus(delete_failed_status);
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
    try std.testing.expect(!isGitCreateArgv(argv));
    try std.testing.expect(!isGitDeleteArgv(argv));
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
    try std.testing.expect(!isGitCreateArgv(argv));
    try std.testing.expect(!isGitDeleteArgv(argv));
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
    try std.testing.expect(git_create_key_first > git_checkout_key_first);
    try std.testing.expect(git_branch_list_key_first > git_branch.git_branch_key_first);
    try std.testing.expect(git_dirty.git_dirty_key_first > git_create_key_first);
    try std.testing.expect(git_delete_key_first > git_dirty.git_dirty_key_first);
    try std.testing.expect(git_numstat.git_numstat_key_first > git_delete_key_first);
    try std.testing.expect(file_mention.file_mention_key_first > git_numstat.git_numstat_key_first);
}

test "create argv is checkout -b with the name as its own slot and rejects implausible names" {
    var buf: [create_argv_len][]const u8 = undefined;
    const argv = createArgvFor("/tmp/faku-new", "feat/new-branch", &buf).?;
    try std.testing.expectEqualStrings(sh_bin, argv[0]);
    try std.testing.expectEqualStrings("-c", argv[1]);
    try std.testing.expectEqualStrings(main.fx_ask_chdir_script, argv[2]);
    try std.testing.expectEqualStrings("sh", argv[3]);
    try std.testing.expectEqualStrings("/tmp/faku-new", argv[4]);
    try std.testing.expectEqualStrings(git_bin, argv[5]);
    try std.testing.expectEqualStrings(git_checkout_cmd, argv[6]);
    try std.testing.expectEqualStrings(git_create_b_flag, argv[7]);
    try std.testing.expectEqualStrings("feat/new-branch", argv[8]);
    try std.testing.expect(isGitCreateArgv(argv));
    try std.testing.expect(!isGitCheckoutArgv(argv));
    try std.testing.expect(!isGitBranchListArgv(argv));
    try std.testing.expect(!isGitDeleteArgv(argv));
    try std.testing.expect(!git_branch.isGitBranchArgv(argv));
    try std.testing.expect(std.mem.indexOf(u8, argv[2], "feat/new-branch") == null);

    try std.testing.expect(createArgvFor("/tmp/faku-new", "not a branch", &buf) == null);
    try std.testing.expect(createArgvFor("/tmp/faku-new", "../escape", &buf) == null);
    try std.testing.expect(createArgvFor("/tmp/faku-new", "/abs", &buf) == null);
    try std.testing.expect(createArgvFor("/tmp/faku-new", ".hidden", &buf) == null);
    try std.testing.expect(createArgvFor("/tmp/faku-new", "trailing.", &buf) == null);
    try std.testing.expect(createArgvFor("/tmp/faku-new", "@", &buf) == null);
    try std.testing.expect(createArgvFor("/tmp/faku-new", "foo@{bar", &buf) == null);
    try std.testing.expect(createArgvFor("/tmp/faku-new", "", &buf) == null);
}

test "delete argv is branch -d with the name as its own slot and rejects implausible names" {
    var buf: [delete_argv_len][]const u8 = undefined;
    const argv = deleteArgvFor("/tmp/faku-del", "feat/old-branch", &buf).?;
    try std.testing.expectEqualStrings(sh_bin, argv[0]);
    try std.testing.expectEqualStrings("-c", argv[1]);
    try std.testing.expectEqualStrings(main.fx_ask_chdir_script, argv[2]);
    try std.testing.expectEqualStrings("sh", argv[3]);
    try std.testing.expectEqualStrings("/tmp/faku-del", argv[4]);
    try std.testing.expectEqualStrings(git_bin, argv[5]);
    try std.testing.expectEqualStrings(git_branch_cmd, argv[6]);
    try std.testing.expectEqualStrings(git_delete_d_flag, argv[7]);
    try std.testing.expectEqualStrings("feat/old-branch", argv[8]);
    try std.testing.expect(isGitDeleteArgv(argv));
    try std.testing.expect(!isGitCreateArgv(argv));
    try std.testing.expect(!isGitCheckoutArgv(argv));
    try std.testing.expect(!isGitBranchListArgv(argv));
    try std.testing.expect(!git_branch.isGitBranchArgv(argv));
    try std.testing.expect(std.mem.indexOf(u8, argv[2], "feat/old-branch") == null);
    try std.testing.expect(!std.mem.eql(u8, argv[7], "-D"));

    try std.testing.expect(deleteArgvFor("/tmp/faku-del", "not a branch", &buf) == null);
    try std.testing.expect(deleteArgvFor("/tmp/faku-del", "../escape", &buf) == null);
    try std.testing.expect(deleteArgvFor("/tmp/faku-del", "/abs", &buf) == null);
    try std.testing.expect(deleteArgvFor("/tmp/faku-del", ".hidden", &buf) == null);
    try std.testing.expect(deleteArgvFor("/tmp/faku-del", "trailing.", &buf) == null);
    try std.testing.expect(deleteArgvFor("/tmp/faku-del", "@", &buf) == null);
    try std.testing.expect(deleteArgvFor("/tmp/faku-del", "foo@{bar", &buf) == null);
    try std.testing.expect(deleteArgvFor("/tmp/faku-del", "", &buf) == null);
    try std.testing.expect(!isGitDeleteArgv(&.{
        sh_bin,
        "-c",
        main.fx_ask_chdir_script,
        "sh",
        "/tmp/faku-del",
        git_bin,
        git_branch_cmd,
        "-D",
        "feat/old-branch",
    }));
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
