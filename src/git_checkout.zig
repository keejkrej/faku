//! First-cut local + remote-tracking branch list, checkout, create,
//! and safe delete for the composer project row.
//!
//! Native has no git/workspace effect. When the selected session has a
//! non-empty `project_path` that exists, Faku `fx.spawn`s
//! `git for-each-ref --format=%(refname) refs/heads refs/remotes`
//! through the same `/bin/sh -c` chdir workaround `fx ask` uses
//! (`fx_ask_chdir_script`). `%(refname)` (not `:short`) is required
//! so `refs/heads/feat/foo` is not confused with a remote. Checking
//! out a listed local name one-shots `git checkout <name>` with that
//! name as its own argv slot — never interpolated into the `-c`
//! script. A listed remote-tracking name one-shots
//! `git checkout --track <name>` the same way (`--track` and the name
//! each their own slot; same checkout key band). New branch…
//! one-shots `git checkout -b <name>` from current HEAD. Delete
//! branch… one-shots `git branch -d <name>` for listed local heads
//! only (safe delete; never `-D`; never `origin/…`). Cap is 64 local
//! heads plus 32 remote-tracking names that have no local counterpart
//! (skip symbolic `*/HEAD`), sorted lexicographically. Not Waku's
//! daemon `InspectBranches` picker, worktrees, fetch/push/prune,
//! stash, merge, force delete, live watch, or Environment Summary.
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

/// One-shot `refs/heads` + `refs/remotes` list. Distinct from
/// git_branch (200+), git_checkout (275+; also `--track`),
/// git_create (290+), git_dirty (300+), git_delete (320+),
/// git_numstat (350+), and file_mention (400+). Incremented per
/// refresh so a cancelled spawn cannot paint a later session.
pub const git_branch_list_key_first: u64 = 250;

/// One-shot `git checkout <name>` or `git checkout --track <name>`.
/// Distinct from the list family (250+), git_create (290+),
/// git_branch (200+), git_dirty (300+), git_delete (320+),
/// git_numstat (350+), and file_mention (400+).
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
pub const max_remote_branches: usize = 32;
pub const max_listed_branches: usize = max_local_branches + max_remote_branches;
pub const checkout_failed_status = "Could not check out branch.";
pub const create_failed_status = "Could not create branch.";
pub const delete_failed_status = "Could not delete branch.";

pub const git_bin = git_branch.git_bin;
pub const git_for_each_ref_cmd = "for-each-ref";
pub const git_refname_format = "--format=%(refname)";
pub const git_heads_ref = "refs/heads";
pub const git_remotes_ref = "refs/remotes";
pub const git_heads_prefix = "refs/heads/";
pub const git_remotes_prefix = "refs/remotes/";
pub const git_checkout_cmd = "checkout";
pub const git_track_flag = "--track";
pub const git_create_b_flag = "-b";
pub const git_branch_cmd = git_branch.git_branch_cmd;
pub const git_delete_d_flag = "-d";
pub const sh_bin = git_branch.sh_bin;

const list_argv_len: usize = 10;
const checkout_argv_len: usize = 8;
const track_checkout_argv_len: usize = 9;
const create_argv_len: usize = 9;
const delete_argv_len: usize = 9;

pub const CachedBranch = struct {
    storage: [git_branch.max_git_branch]u8 = [_]u8{0} ** git_branch.max_git_branch,
    len: usize = 0,
    remote: bool = false,

    pub fn text(self: *const CachedBranch) []const u8 {
        return self.storage[0..self.len];
    }

    pub fn set(self: *CachedBranch, name: []const u8, remote: bool) void {
        writeFixed(&self.storage, &self.len, name);
        self.remote = remote;
    }
};

pub const ParsedRef = struct {
    name: []const u8,
    remote: bool,
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
        git_refname_format,
        git_heads_ref,
        git_remotes_ref,
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
    if (!std.mem.eql(u8, argv[7], git_refname_format)) return false;
    if (!std.mem.eql(u8, argv[8], git_heads_ref)) return false;
    return std.mem.eql(u8, argv[9], git_remotes_ref);
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

/// `git checkout --track <name>` as trailing argv slots. Rejects names
/// that fail `isPlausibleBranchName` so a raw string never reaches the
/// shell script.
pub fn trackCheckoutArgvFor(cwd: []const u8, name: []const u8, buf: *[track_checkout_argv_len][]const u8) ?[]const []const u8 {
    if (!git_branch.isPlausibleBranchName(name)) return null;
    buf.* = .{
        sh_bin,
        "-c",
        main.fx_ask_chdir_script,
        "sh",
        cwd,
        git_bin,
        git_checkout_cmd,
        git_track_flag,
        name,
    };
    return buf;
}

pub fn isGitTrackCheckoutArgv(argv: []const []const u8) bool {
    if (argv.len != track_checkout_argv_len) return false;
    if (!std.mem.eql(u8, argv[0], sh_bin)) return false;
    if (!std.mem.eql(u8, argv[1], "-c")) return false;
    if (!std.mem.eql(u8, argv[2], main.fx_ask_chdir_script)) return false;
    if (!std.mem.eql(u8, argv[5], git_bin)) return false;
    if (!std.mem.eql(u8, argv[6], git_checkout_cmd)) return false;
    if (!std.mem.eql(u8, argv[7], git_track_flag)) return false;
    return git_branch.isPlausibleBranchName(argv[8]);
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

fn parsedRefLessThan(_: void, a: ParsedRef, b: ParsedRef) bool {
    return std.mem.lessThan(u8, a.name, b.name);
}

fn isRemoteHeadName(name: []const u8) bool {
    return std.mem.eql(u8, name, "HEAD") or std.mem.endsWith(u8, name, "/HEAD");
}

/// Short name after the first path segment (`origin/feat` → `feat`).
pub fn remoteLocalCounterpart(name: []const u8) []const u8 {
    const slash = std.mem.indexOfScalar(u8, name, '/') orelse return "";
    return name[slash + 1 ..];
}

/// Classify one `%(refname)` line. Locals are `refs/heads/<name>`;
/// remotes are `refs/remotes/<name>` minus symbolic `*/HEAD`.
pub fn classifyRefname(raw: []const u8) ?ParsedRef {
    const trimmed = std.mem.trim(u8, raw, " \t\r\n");
    if (std.mem.startsWith(u8, trimmed, git_heads_prefix)) {
        const name = trimmed[git_heads_prefix.len..];
        if (!git_branch.isPlausibleBranchName(name)) return null;
        return .{ .name = name, .remote = false };
    }
    if (std.mem.startsWith(u8, trimmed, git_remotes_prefix)) {
        const name = trimmed[git_remotes_prefix.len..];
        if (isRemoteHeadName(name)) return null;
        if (!git_branch.isPlausibleBranchName(name)) return null;
        return .{ .name = name, .remote = true };
    }
    return null;
}

fn parsedRefNameEquals(refs: []const ParsedRef, name: []const u8) bool {
    for (refs) |item| {
        if (std.mem.eql(u8, item.name, name)) return true;
    }
    return false;
}

/// Parse `%(refname)` lines. Locals first (cap 64), then remotes that
/// are not `*/HEAD` and whose local counterpart is not already in this
/// batch (cap 32). Skip empty / implausible names. Then sort by
/// display name. Slices alias `raw`.
pub fn collectStdoutRefs(raw: []const u8, out: []ParsedRef) usize {
    var n: usize = 0;
    var local_n: usize = 0;
    var it = std.mem.splitScalar(u8, raw, '\n');
    while (it.next()) |line| {
        if (n >= out.len or local_n >= max_local_branches) break;
        const parsed = classifyRefname(line) orelse continue;
        if (parsed.remote) continue;
        if (parsedRefNameEquals(out[0..n], parsed.name)) continue;
        out[n] = parsed;
        n += 1;
        local_n += 1;
    }
    var remote_n: usize = 0;
    it = std.mem.splitScalar(u8, raw, '\n');
    while (it.next()) |line| {
        if (n >= out.len or remote_n >= max_remote_branches) break;
        const parsed = classifyRefname(line) orelse continue;
        if (!parsed.remote) continue;
        const counterpart = remoteLocalCounterpart(parsed.name);
        if (counterpart.len > 0 and parsedRefNameEquals(out[0..local_n], counterpart)) continue;
        if (parsedRefNameEquals(out[0..n], parsed.name)) continue;
        out[n] = parsed;
        n += 1;
        remote_n += 1;
    }
    std.mem.sort(ParsedRef, out[0..n], {}, parsedRefLessThan);
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

pub fn listedBranchIsRemote(model: *const Model, index: usize) bool {
    if (index >= model.git_branch_list_count) return false;
    return model.git_branch_list_store[index].remote;
}

pub fn hasListedBranches(model: *const Model) bool {
    return model.git_branch_list_count > 0;
}

pub fn canPickGitBranch(model: *const Model) bool {
    return git_branch.hasGitBranch(model) or hasListedBranches(model);
}

fn listedKindCount(model: *const Model, remote: bool) usize {
    var n: usize = 0;
    var i: usize = 0;
    while (i < model.git_branch_list_count) : (i += 1) {
        if (model.git_branch_list_store[i].remote == remote) n += 1;
    }
    return n;
}

fn hasListedLocalName(model: *const Model, name: []const u8) bool {
    var i: usize = 0;
    while (i < model.git_branch_list_count) : (i += 1) {
        if (model.git_branch_list_store[i].remote) continue;
        if (std.mem.eql(u8, listedBranch(model, i), name)) return true;
    }
    return false;
}

pub fn isListedRemoteName(model: *const Model, name: []const u8) bool {
    var i: usize = 0;
    while (i < model.git_branch_list_count) : (i += 1) {
        if (!model.git_branch_list_store[i].remote) continue;
        if (std.mem.eql(u8, listedBranch(model, i), name)) return true;
    }
    return false;
}

/// True when at least one listed local head is not the current branch.
/// Remote-tracking rows are never deletable. Detached HEAD (sha label)
/// treats every listed local head as deletable.
pub fn canDeleteGitBranch(model: *const Model) bool {
    const current = git_branch.gitBranchLabel(model);
    var i: usize = 0;
    while (i < model.git_branch_list_count) : (i += 1) {
        if (listedBranchIsRemote(model, i)) continue;
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
        if (listedBranchIsRemote(model, i)) continue;
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

fn appendListedBranch(model: *Model, name: []const u8, remote: bool) void {
    if (model.git_branch_list_count >= max_listed_branches) return;
    if (!git_branch.isPlausibleBranchName(name)) return;
    if (remote) {
        if (listedKindCount(model, true) >= max_remote_branches) return;
        const counterpart = remoteLocalCounterpart(name);
        if (counterpart.len > 0 and hasListedLocalName(model, counterpart)) return;
    } else if (listedKindCount(model, false) >= max_local_branches) return;
    var i: usize = 0;
    while (i < model.git_branch_list_count) : (i += 1) {
        if (std.mem.eql(u8, listedBranch(model, i), name)) return;
    }
    model.git_branch_list_store[model.git_branch_list_count].set(name, remote);
    model.git_branch_list_count += 1;
}

pub fn applyStdoutBranches(model: *Model, raw: []const u8) void {
    var refs: [max_listed_branches]ParsedRef = undefined;
    const n = collectStdoutRefs(raw, refs[0..]);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (!refs[i].remote) appendListedBranch(model, refs[i].name, false);
    }
    i = 0;
    while (i < n) : (i += 1) {
        if (refs[i].remote) appendListedBranch(model, refs[i].name, true);
    }
}

fn dropRemotesWithLocalCounterpart(model: *Model) void {
    var write: u32 = 0;
    var i: u32 = 0;
    while (i < model.git_branch_list_count) : (i += 1) {
        const item = model.git_branch_list_store[i];
        if (item.remote) {
            const counterpart = remoteLocalCounterpart(item.text());
            if (counterpart.len > 0 and hasListedLocalName(model, counterpart)) continue;
        }
        if (write != i) model.git_branch_list_store[write] = item;
        write += 1;
    }
    model.git_branch_list_count = write;
}

/// Drop remotes whose local counterpart arrived later, then sort.
pub fn finalizeListedBranches(model: *Model) void {
    dropRemotesWithLocalCounterpart(model);
    sortListedBranches(model);
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
/// cached heads and remotes, and spawn `for-each-ref` when the
/// selected session has an existing `project_path`. Empty / missing /
/// Windows skips the spawn so the picker stays omitted unless
/// `has_git_branch` is already true.
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
    finalizeListedBranches(model);
}

fn refreshWorkspaceProbes(model: *Model, fx: *Effects) void {
    git_branch.refresh(model, fx);
    git_dirty.refresh(model, fx);
    git_numstat.refresh(model, fx);
    file_mention.refresh(model, fx);
    refresh(model, fx);
}

/// Selecting the current branch closes the picker. A listed
/// remote-tracking name one-shots `git checkout --track` even when
/// its local counterpart is the current branch. Another plausible
/// local name one-shots `git checkout`. Implausible names are ignored.
/// In-flight create or delete is a no-op so the one-shots do not overlap.
pub fn pickBranch(model: *Model, fx: *Effects, name: []const u8) void {
    closePicker(model);
    if (model.git_create_key != 0 or model.git_delete_key != 0) return;
    if (!git_branch.isPlausibleBranchName(name)) return;
    const remote = isListedRemoteName(model, name);
    if (!remote and std.mem.eql(u8, name, git_branch.gitBranchLabel(model))) return;
    if (!probeSupported()) return;
    const cwd = probePath(model);
    if (cwd.len == 0) return;

    if (remote) {
        var track_buf: [track_checkout_argv_len][]const u8 = undefined;
        const argv = trackCheckoutArgvFor(cwd, name, &track_buf) orelse return;
        spawnCheckout(model, fx, cwd, argv);
        return;
    }

    var argv_buf: [checkout_argv_len][]const u8 = undefined;
    const argv = checkoutArgvFor(cwd, name, &argv_buf) orelse return;
    spawnCheckout(model, fx, cwd, argv);
}

fn spawnCheckout(model: *Model, fx: *Effects, cwd: []const u8, argv: []const []const u8) void {
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

test "list argv is chdir script plus for-each-ref refs/heads and refs/remotes" {
    var buf: [list_argv_len][]const u8 = undefined;
    const argv = listArgvFor("/tmp/faku-heads", &buf);
    try std.testing.expectEqualStrings(sh_bin, argv[0]);
    try std.testing.expectEqualStrings("-c", argv[1]);
    try std.testing.expectEqualStrings(main.fx_ask_chdir_script, argv[2]);
    try std.testing.expectEqualStrings("sh", argv[3]);
    try std.testing.expectEqualStrings("/tmp/faku-heads", argv[4]);
    try std.testing.expectEqualStrings(git_bin, argv[5]);
    try std.testing.expectEqualStrings(git_for_each_ref_cmd, argv[6]);
    try std.testing.expectEqualStrings(git_refname_format, argv[7]);
    try std.testing.expectEqualStrings(git_heads_ref, argv[8]);
    try std.testing.expectEqualStrings(git_remotes_ref, argv[9]);
    try std.testing.expect(isGitBranchListArgv(argv));
    try std.testing.expect(!isGitBranchListArgv(&.{ git_bin, git_for_each_ref_cmd, git_refname_format, git_heads_ref }));
    try std.testing.expect(!isGitBranchListArgv(&.{
        sh_bin,
        "-c",
        main.fx_ask_chdir_script,
        "sh",
        "/tmp/faku-heads",
        git_bin,
        git_for_each_ref_cmd,
        "--format=%(refname:short)",
        git_heads_ref,
    }));
    try std.testing.expect(!git_branch.isGitBranchArgv(argv));
    try std.testing.expect(!isGitCheckoutArgv(argv));
    try std.testing.expect(!isGitTrackCheckoutArgv(argv));
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
    try std.testing.expect(!isGitTrackCheckoutArgv(argv));
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

test "track checkout argv is checkout --track with the name as its own slot and rejects implausible names" {
    var buf: [track_checkout_argv_len][]const u8 = undefined;
    const argv = trackCheckoutArgvFor("/tmp/faku-track", "origin/feat", &buf).?;
    try std.testing.expectEqualStrings(sh_bin, argv[0]);
    try std.testing.expectEqualStrings("-c", argv[1]);
    try std.testing.expectEqualStrings(main.fx_ask_chdir_script, argv[2]);
    try std.testing.expectEqualStrings("sh", argv[3]);
    try std.testing.expectEqualStrings("/tmp/faku-track", argv[4]);
    try std.testing.expectEqualStrings(git_bin, argv[5]);
    try std.testing.expectEqualStrings(git_checkout_cmd, argv[6]);
    try std.testing.expectEqualStrings(git_track_flag, argv[7]);
    try std.testing.expectEqualStrings("origin/feat", argv[8]);
    try std.testing.expect(isGitTrackCheckoutArgv(argv));
    try std.testing.expect(!isGitCheckoutArgv(argv));
    try std.testing.expect(!isGitCreateArgv(argv));
    try std.testing.expect(!isGitBranchListArgv(argv));
    try std.testing.expect(!isGitDeleteArgv(argv));
    try std.testing.expect(!git_branch.isGitBranchArgv(argv));
    try std.testing.expect(std.mem.indexOf(u8, argv[2], "origin/feat") == null);
    try std.testing.expect(std.mem.indexOf(u8, argv[2], "--track") == null);

    try std.testing.expect(trackCheckoutArgvFor("/tmp/faku-track", "not a branch", &buf) == null);
    try std.testing.expect(trackCheckoutArgvFor("/tmp/faku-track", "../escape", &buf) == null);
    try std.testing.expect(trackCheckoutArgvFor("/tmp/faku-track", "/abs", &buf) == null);
    try std.testing.expect(trackCheckoutArgvFor("/tmp/faku-track", ".hidden", &buf) == null);
    try std.testing.expect(trackCheckoutArgvFor("/tmp/faku-track", "trailing.", &buf) == null);
    try std.testing.expect(trackCheckoutArgvFor("/tmp/faku-track", "@", &buf) == null);
    try std.testing.expect(trackCheckoutArgvFor("/tmp/faku-track", "foo@{bar", &buf) == null);
    try std.testing.expect(trackCheckoutArgvFor("/tmp/faku-track", "", &buf) == null);
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
    try std.testing.expect(!isGitTrackCheckoutArgv(argv));
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
    try std.testing.expect(!isGitTrackCheckoutArgv(argv));
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

test "collectStdoutRefs skips remote HEAD, de-dupes local counterparts, and caps remotes" {
    var refs: [max_listed_branches]ParsedRef = undefined;
    const raw =
        \\  refs/heads/zeta 
        \\
        \\refs/heads/main
        \\not a branch
        \\../escape
        \\refs/heads/feat/a
        \\refs/remotes/origin/HEAD
        \\refs/remotes/origin/main
        \\refs/remotes/origin/feat/a
        \\refs/remotes/origin/feat/foo
        \\refs/heads/feat/foo
        \\refs/remotes/origin/only
        \\refs/remotes/upstream/other
        \\
    ;
    const n = collectStdoutRefs(raw, refs[0..]);
    try std.testing.expectEqual(@as(usize, 6), n);
    try std.testing.expectEqualStrings("feat/a", refs[0].name);
    try std.testing.expect(!refs[0].remote);
    try std.testing.expectEqualStrings("feat/foo", refs[1].name);
    try std.testing.expect(!refs[1].remote);
    try std.testing.expectEqualStrings("main", refs[2].name);
    try std.testing.expect(!refs[2].remote);
    try std.testing.expectEqualStrings("origin/only", refs[3].name);
    try std.testing.expect(refs[3].remote);
    try std.testing.expectEqualStrings("upstream/other", refs[4].name);
    try std.testing.expect(refs[4].remote);
    try std.testing.expectEqualStrings("zeta", refs[5].name);
    try std.testing.expect(!refs[5].remote);

    try std.testing.expectEqual(@as(usize, 0), collectStdoutRefs("   \n\n", refs[0..]));
    try std.testing.expectEqual(@as(usize, 0), collectStdoutRefs("", refs[0..]));
    try std.testing.expectEqual(@as(usize, 0), collectStdoutRefs("main\nfeat/a\norigin/feat\n", refs[0..]));
    try std.testing.expect(classifyRefname("refs/remotes/origin/HEAD") == null);
    try std.testing.expect(classifyRefname("refs/remotes/HEAD") == null);
    try std.testing.expectEqualStrings("feat", remoteLocalCounterpart("origin/feat"));
    try std.testing.expectEqualStrings("feat/foo", remoteLocalCounterpart("origin/feat/foo"));

    var tiny: [1]ParsedRef = undefined;
    const capped = collectStdoutRefs("refs/heads/c\nrefs/heads/b\nrefs/heads/a\n", tiny[0..]);
    try std.testing.expectEqual(@as(usize, 1), capped);
    try std.testing.expectEqualStrings("c", tiny[0].name);

    var remote_model = Model{};
    var i: usize = 0;
    while (i < max_remote_branches + 1) : (i += 1) {
        var line_buf: [64]u8 = undefined;
        const line = std.fmt.bufPrint(&line_buf, "refs/remotes/origin/r{d}\n", .{i}) catch unreachable;
        applyStdoutBranches(&remote_model, line);
    }
    try std.testing.expectEqual(@as(u32, max_remote_branches), remote_model.git_branch_list_count);
}

test "finalizeListedBranches drops remotes after a later local counterpart arrives" {
    var model = Model{};
    applyStdoutBranches(&model, "refs/remotes/origin/feat\nrefs/remotes/origin/HEAD\n");
    try std.testing.expectEqual(@as(u32, 1), model.git_branch_list_count);
    try std.testing.expectEqualStrings("origin/feat", listedBranch(&model, 0));
    try std.testing.expect(listedBranchIsRemote(&model, 0));
    applyStdoutBranches(&model, "refs/heads/feat\n");
    try std.testing.expectEqual(@as(u32, 2), model.git_branch_list_count);
    finalizeListedBranches(&model);
    try std.testing.expectEqual(@as(u32, 1), model.git_branch_list_count);
    try std.testing.expectEqualStrings("feat", listedBranch(&model, 0));
    try std.testing.expect(!listedBranchIsRemote(&model, 0));
    try std.testing.expect(!isListedRemoteName(&model, "origin/feat"));
}
