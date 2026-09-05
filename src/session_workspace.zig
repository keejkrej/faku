//! First-cut defer-until-Send workspace mode.
//!
//! Composer **Work in** is `local` (ordinary `project_path`) or
//! `newWorktree` (draft only — no `git worktree add` until Send).
//! Send on `newWorktree` queues the prompt, shows Creating worktree…,
//! and reuses `git_checkout.beginWorktreeAdd` (same spawn / retry /
//! candidate path as New worktree…) when no daemon address is set.
//! When `WAKU_DAEMON_ADDRESS` or persisted `last_daemon_address` is
//! set, Send prefers hello + `WorkspaceOperation::CreateWorktree`
//! (nil request-frame session/runtime ids; snake_case operation
//! fields; ok is `worktreeCreated` path + branch). Native 4 KiB
//! stdin overflow falls back to local `git worktree add`. Success
//! retargets `project_path`, sets `worktree` {path, branch}, then
//! `startPrompt`. Failure leaves `newWorktree` and does not start
//! the provider. Native has no git effect. Optional Work-in Base on
//! a `newWorktree` draft persists camelCase `baseBranch` (Waku
//! `NewWorktree { base_branch }`) and keeps
//! `git_worktree_base_override_*` in sync. Send prep prefers that
//! stored base for the trailing `git worktree add` argv slot (and
//! as CreateWorktree `base_branch` when the daemon path is used).
//! First-cut daemon `WorkspaceOperation::Push` ships in
//! `git_checkout` (best-effort sidecar when a daemon address is set;
//! Force stays local git). First-cut daemon
//! `WorkspaceOperation::Commit` ships in `git_commit` (best-effort
//! sidecar when a daemon address is set; Amend and Force+Commit and
//! Push stay local git). First-cut daemon
//! `WorkspaceOperation::InspectBranches` ships in `git_checkout`
//! (best-effort sidecar when a daemon address is set; local heads
//! only; remotes-on-daemon-list leftover; falls back to local
//! `for-each-ref`). First-cut daemon
//! `WorkspaceOperation::CheckoutBranch` ships in `git_checkout`
//! (best-effort sidecar on picker local-head checkout and New
//! branch create when a daemon address is set; remote `--track`
//! stays local git; overflow falls back to local checkout). First-cut
//! daemon `WorkspaceOperation::InspectCommit` ships in `git_commit`
//! (best-effort sidecar on Commit… open when a daemon address is
//! set; overflow / error / unusable snapshot falls back to local
//! numstat). Leftovers:
//! other daemon `WorkspaceOperation` variants (CaptureTurn,
//! ListTree, GenerateCommitMessage,
//! CollectReviewDiff, ref ops, remotes-on-daemon-list, amend/force
//! over daemon, remote `--track` over daemon, …). Fork copies
//! `project_path` and resets kind to `local` (drops `baseBranch`).

const std = @import("std");
const main = @import("main.zig");
const git_checkout = @import("git_checkout.zig");
const persist = @import("persist.zig");
const prompt_spawn = @import("spawn.zig");
const attach_helpers = @import("attach.zig");
const store = @import("store.zig");
const git_branch = @import("git_branch.zig");
const git_dirty = @import("git_dirty.zig");
const git_numstat = @import("git_numstat.zig");
const git_ahead_behind = @import("git_ahead_behind.zig");
const session_fork = @import("fork.zig");
const daemon_proxy = @import("daemon_proxy.zig");
const protocol = @import("protocol.zig");

const Model = main.Model;
const Effects = main.Effects;
const Session = main.Session;

pub const preparing_status = "Creating worktree…";
pub const local_label = "Local";
pub const new_worktree_label = "New worktree";
pub const worktree_fallback_label = "Worktree";

pub fn isLocal(session: *const Session) bool {
    return session.workspace_kind == .local;
}

pub fn isNewWorktree(session: *const Session) bool {
    return session.workspace_kind == .new_worktree;
}

pub fn isMaterialized(session: *const Session) bool {
    return session.workspace_kind == .worktree;
}

pub fn selectedIsNewWorktree(model: *const Model) bool {
    const session = model.sessionByIdConst(model.selected) orelse return false;
    return isNewWorktree(session);
}

pub fn canPick(model: *const Model) bool {
    const session = model.sessionByIdConst(model.selected) orelse return false;
    if (session.projectPath().len == 0) return false;
    return !isMaterialized(session);
}

/// Base ghost beside Work in. Hidden while the immediate New worktree…
/// card already shows its Base picker.
pub fn canPickBase(model: *const Model) bool {
    if (model.git_worktree_create_active) return false;
    return selectedIsNewWorktree(model);
}

pub fn label(model: *const Model) []const u8 {
    const session = model.sessionByIdConst(model.selected) orelse return local_label;
    return switch (session.workspace_kind) {
        .local => local_label,
        .new_worktree => new_worktree_label,
        .worktree => if (session.workspaceBranch().len > 0) session.workspaceBranch() else worktree_fallback_label,
    };
}

pub fn pickLocal(model: *Model, fx: *Effects) void {
    model.workspace_picker_open = false;
    const session = model.sessionById(model.selected) orelse return;
    if (isMaterialized(session)) return;
    session.setWorkspaceLocal();
    model.git_worktree_base_override_len = 0;
    model.git_worktree_base_picker_open = false;
    persist.persistComposerChips(model, fx);
}

/// Mark the selected draft `newWorktree`. Does not spawn
/// `git worktree add`. No-op without a project path or when already a
/// materialized worktree. Re-picking New worktree keeps an already
/// stored `baseBranch`.
pub fn pickNewWorktree(model: *Model, fx: *Effects) void {
    model.workspace_picker_open = false;
    const session = model.sessionById(model.selected) orelse return;
    if (session.projectPath().len == 0) return;
    if (isMaterialized(session)) return;
    session.setWorkspaceNewWorktree();
    git_checkout.syncWorktreeBaseOverrideFromSession(model);
    persist.persistComposerChips(model, fx);
}

pub fn shouldPrepOnSend(model: *const Model) bool {
    if (model.workspace_prep_active) return true;
    const session = model.sessionByIdConst(model.selected) orelse return false;
    return isNewWorktree(session);
}

/// Queue the prompt and start worktree add. Returns false when prep
/// cannot start (in-flight mutation, no cwd, already preparing) so
/// the caller keeps the composer draft.
pub fn beginPrep(model: *Model, fx: *Effects, text: []const u8) bool {
    if (model.workspace_prep_active) return false;
    if (git_checkout.gitMutationInFlight(model)) return false;
    if (model.is_streaming()) return false;
    const session = model.sessionById(model.selected) orelse return false;
    if (!isNewWorktree(session)) return false;

    const src = if (session.untitled) text else session.title();
    var slug_buf: [git_checkout.max_worktree_slug_bytes]u8 = undefined;
    const slug = git_checkout.worktreeSlug(src, slug_buf[0..]);

    model.queueWorkspacePrep(session.id, text, model.draftImagePath());
    model.setAttachStatus(preparing_status);
    if (!git_checkout.trySpawnDaemonCreateWorktree(model, fx, text)) {
        git_checkout.beginWorktreeAdd(model, fx, slug);
    }
    if (model.git_worktree_add_key == 0 and model.git_worktree_base_key == 0) {
        model.abortWorkspacePrep();
        model.setAttachStatus(git_checkout.worktree_add_failed_status);
        return false;
    }
    return true;
}

pub fn completePrepIfNeeded(model: *Model, fx: *Effects) void {
    if (!model.workspace_prep_active) return;
    if (model.workspace_prep_session != model.selected) {
        model.clearWorkspacePrep();
        return;
    }
    const session = model.sessionById(model.selected) orelse {
        model.clearWorkspacePrep();
        return;
    };
    if (session.workspace_kind != .worktree) {
        model.abortWorkspacePrep();
        return;
    }

    var text_buf: [main.max_draft]u8 = undefined;
    const text_n = @min(text_buf.len, model.workspace_prep_text_len);
    @memcpy(text_buf[0..text_n], model.workspace_prep_text_storage[0..text_n]);
    var image_buf: [main.max_project_path]u8 = undefined;
    const image_n = @min(image_buf.len, model.workspace_prep_image_len);
    @memcpy(image_buf[0..image_n], model.workspace_prep_image_storage[0..image_n]);
    const session_id = session.id;
    model.clearWorkspacePrep();
    model.clearAttachStatus();
    model.setDraftImagePath(image_buf[0..image_n]);
    prompt_spawn.startPrompt(model, fx, session_id, text_buf[0..text_n]);
    model.clearImageAttach();
    attach_helpers.refreshAttachPreview(model, fx);
}

pub fn failPrepIfIdle(model: *Model) void {
    if (!model.workspace_prep_active) return;
    if (model.git_worktree_add_key != 0 or model.git_worktree_base_key != 0) return;
    model.abortWorkspacePrep();
}

fn drainEffects(model: *Model, fx: *Effects) void {
    while (fx.takeMsg()) |msg| main.update(model, msg, fx);
}

fn findWorktreeBaseSpawn(fx: *Effects, key: u64) ?@TypeOf(fx.pendingSpawnAt(0).?) {
    var i: usize = 0;
    while (fx.pendingSpawnAt(i)) |spawn| : (i += 1) {
        if (spawn.key == key and git_checkout.isGitWorktreeBaseArgv(spawn.argv)) return spawn;
    }
    return null;
}

fn findWorktreeAddSpawn(fx: *Effects, key: u64) ?@TypeOf(fx.pendingSpawnAt(0).?) {
    var i: usize = 0;
    while (fx.pendingSpawnAt(i)) |spawn| : (i += 1) {
        if (spawn.key == key and git_checkout.isGitWorktreeAddArgv(spawn.argv)) return spawn;
    }
    return null;
}

fn findDaemonWorkspaceSpawn(fx: *Effects, key: u64) ?@TypeOf(fx.pendingSpawnAt(0).?) {
    var i: usize = 0;
    while (fx.pendingSpawnAt(i)) |spawn| : (i += 1) {
        if (spawn.key == key and git_checkout.isDaemonWorkspacePushArgv(spawn.argv)) return spawn;
    }
    return null;
}

fn pendingProviderStart(fx: *Effects) bool {
    if (fx.pendingTimerCount() > 0) return true;
    var i: usize = 0;
    while (fx.pendingSpawnAt(i)) |spawn| : (i += 1) {
        if (git_checkout.isGitWorktreeAddArgv(spawn.argv)) continue;
        if (git_checkout.isGitWorktreeBaseArgv(spawn.argv)) continue;
        if (git_checkout.isDaemonWorkspacePushArgv(spawn.argv)) continue;
        if (git_checkout.isGitBranchListArgv(spawn.argv)) continue;
        if (git_branch.isGitBranchArgv(spawn.argv)) continue;
        if (git_dirty.isGitDirtyArgv(spawn.argv)) continue;
        if (git_numstat.isGitNumstatArgv(spawn.argv)) continue;
        if (git_ahead_behind.isGitAheadBehindArgv(spawn.argv)) continue;
        return true;
    }
    return false;
}

test "default workspace is local" {
    var model = Model{};
    const id = model.addSession("untitled", .fx);
    const session = model.sessionByIdConst(id).?;
    try std.testing.expect(isLocal(session));
    try std.testing.expect(!isNewWorktree(session));
    try std.testing.expect(!isMaterialized(session));
}

test "selecting New worktree does not spawn" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/ws-pick", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("pick worktree", .fx);
    model.selected = id;
    model.sessionById(id).?.setProjectPath(project);

    pickNewWorktree(&model, &fx);
    try std.testing.expect(isNewWorktree(model.sessionByIdConst(id).?));
    try std.testing.expectEqual(@as(u64, 0), model.git_worktree_add_key);
    try std.testing.expectEqual(@as(u64, 0), model.git_worktree_base_key);
    try std.testing.expect(!pendingProviderStart(&fx));
    try std.testing.expectEqualStrings(project, model.selectedProjectPath());

    pickLocal(&model, &fx);
    try std.testing.expect(isLocal(model.sessionByIdConst(id).?));
    try std.testing.expectEqual(@as(u64, 0), model.git_worktree_add_key);
}

test "Send while newWorktree enters prep and does not start the provider until success" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/ws-send-ok", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);
    var home_buf: [256]u8 = undefined;
    const home = try std.fmt.bufPrint(&home_buf, "/tmp/faku-ws-ok-{s}", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, home);

    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = std.testing.io;
    model.fx_probe_started = true;
    model.setHome(home);
    const id = model.addSession("feat send", .fx);
    model.selected = id;
    model.sessionById(id).?.setProjectPath(project);
    pickNewWorktree(&model, &fx);
    try std.testing.expect(isNewWorktree(model.sessionByIdConst(id).?));

    model.draft_buffer.apply(.{ .insert_text = "ship the workspace cut" });
    main.update(&model, .send, &fx);
    try std.testing.expect(model.workspace_prep_active);
    try std.testing.expect(!model.is_streaming());
    try std.testing.expectEqualStrings(preparing_status, model.attach_status());
    try std.testing.expectEqualStrings("", model.draft());
    try std.testing.expect(model.git_worktree_base_key != 0);
    try std.testing.expectEqual(@as(u64, 0), model.git_worktree_add_key);
    try std.testing.expect(!pendingProviderStart(&fx));
    try std.testing.expectEqual(@as(usize, 0), fx.pendingTimerCount());
    try std.testing.expect(isNewWorktree(model.sessionByIdConst(id).?));
    try std.testing.expectEqualStrings(project, model.selectedProjectPath());

    const probe = findWorktreeBaseSpawn(&fx, model.git_worktree_base_key) orelse return error.MissingWorktreeBase;
    try fx.feedLine(probe.key, "origin/main\n");
    drainEffects(&model, &fx);
    try fx.feedExit(probe.key, 0);
    drainEffects(&model, &fx);
    try std.testing.expect(!model.is_streaming());
    try std.testing.expect(model.workspace_prep_active);
    const created = findWorktreeAddSpawn(&fx, model.git_worktree_add_key) orelse return error.MissingWorktreeAdd;
    try std.testing.expect(git_checkout.isGitWorktreeAddArgv(created.argv));

    var dest_buf: [main.max_project_path]u8 = undefined;
    const dest = git_checkout.worktreeDestPath(home, project, "feat-send", dest_buf[0..]) orelse return error.MissingDest;
    try fx.feedExit(created.key, 0);
    drainEffects(&model, &fx);
    try std.testing.expectEqual(@as(u64, 0), model.git_worktree_add_key);
    try std.testing.expect(!model.workspace_prep_active);
    const session = model.sessionByIdConst(id).?;
    try std.testing.expect(isMaterialized(session));
    try std.testing.expectEqualStrings(dest, session.projectPath());
    try std.testing.expectEqualStrings(dest, session.workspacePath());
    try std.testing.expectEqualStrings("faku/feat-send", session.workspaceBranch());
    try std.testing.expect(model.is_streaming());
    try std.testing.expectEqual(main.ReplyPath.demo, model.reply_path);
    try std.testing.expectEqual(@as(usize, 1), fx.pendingTimerCount());
}

test "Send worktree add failure leaves newWorktree and does not prompt" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/ws-send-fail", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);
    var home_buf: [256]u8 = undefined;
    const home = try std.fmt.bufPrint(&home_buf, "/tmp/faku-ws-fail-{s}", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, home);

    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = std.testing.io;
    model.fx_probe_started = true;
    model.setHome(home);
    const id = model.addSession("feat fail", .fx);
    model.selected = id;
    model.sessionById(id).?.setProjectPath(project);
    pickNewWorktree(&model, &fx);

    model.draft_buffer.apply(.{ .insert_text = "do not start yet" });
    main.update(&model, .send, &fx);
    try std.testing.expect(model.workspace_prep_active);
    try std.testing.expect(!model.is_streaming());

    const probe = findWorktreeBaseSpawn(&fx, model.git_worktree_base_key) orelse return error.MissingWorktreeBaseFail;
    try fx.feedExit(probe.key, 1);
    drainEffects(&model, &fx);
    const first = findWorktreeAddSpawn(&fx, model.git_worktree_add_key) orelse return error.MissingWorktreeAddFail;
    try fx.feedExit(first.key, 1);
    drainEffects(&model, &fx);
    try std.testing.expect(!model.has_attach_status() or std.mem.eql(u8, model.attach_status(), preparing_status) or model.git_worktree_add_key != 0);

    model.git_worktree_add_attempt = git_checkout.max_worktree_candidates - 1;
    const retry = findWorktreeAddSpawn(&fx, model.git_worktree_add_key) orelse return error.MissingWorktreeAddRetry;
    try fx.feedExit(retry.key, 1);
    drainEffects(&model, &fx);

    try std.testing.expectEqual(@as(u64, 0), model.git_worktree_add_key);
    try std.testing.expect(!model.workspace_prep_active);
    try std.testing.expect(!model.is_streaming());
    try std.testing.expectEqual(@as(usize, 0), fx.pendingTimerCount());
    try std.testing.expect(isNewWorktree(model.sessionByIdConst(id).?));
    try std.testing.expectEqualStrings(project, model.selectedProjectPath());
    try std.testing.expectEqualStrings(git_checkout.worktree_add_failed_status, model.attach_status());
    try std.testing.expectEqualStrings("do not start yet", model.draft());
}

test "sessions.json omits local and restores newWorktree and worktree" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-ws-store", .{tmp.sub_path[0..]});
    const io = testing.io;
    const allocator = testing.allocator;

    var source = Model{};
    source.task_state_loaded = true;
    source.setStoreDir(dir);
    source.store_io = io;

    const local_id = source.addSession("local row", .fx);
    _ = source.appendTurn(local_id, .user, "keep local");
    try std.testing.expect(isLocal(source.sessionByIdConst(local_id).?));

    const draft_id = source.addSession("new worktree row", .fx);
    _ = source.appendTurn(draft_id, .user, "defer me");
    source.sessionById(draft_id).?.setWorkspaceNewWorktree();
    source.sessionById(draft_id).?.setProjectPath("/tmp/proj");

    const wt_id = source.addSession("materialized row", .fx);
    _ = source.appendTurn(wt_id, .user, "already grown");
    source.sessionById(wt_id).?.setProjectPath("/tmp/faku/wt");
    source.sessionById(wt_id).?.setWorkspaceWorktree("/tmp/faku/wt", "faku/feat");

    try store.saveSession(&source, local_id, allocator, io);
    try store.saveSession(&source, draft_id, allocator, io);
    try store.saveSession(&source, wt_id, allocator, io);

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const catalog = store.catalogPath(dir, &path_buf) orelse return error.MissingCatalog;
    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, catalog, allocator, .limited(store.max_document_bytes));
    defer allocator.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"kind\":\"local\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"kind\":\"newWorktree\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"kind\":\"worktree\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"path\":\"/tmp/faku/wt\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"branch\":\"faku/feat\"") != null);

    var loaded = Model{};
    loaded.setStoreDir(dir);
    loaded.store_io = io;
    try std.testing.expectEqual(store.LoadKind.loaded, store.loadCatalog(&loaded, allocator, io));
    try std.testing.expect(isLocal(loaded.sessionByIdConst(local_id).?));
    try std.testing.expect(isNewWorktree(loaded.sessionByIdConst(draft_id).?));
    const wt = loaded.sessionByIdConst(wt_id).?;
    try std.testing.expect(isMaterialized(wt));
    try std.testing.expectEqualStrings("/tmp/faku/wt", wt.workspacePath());
    try std.testing.expectEqualStrings("faku/feat", wt.workspaceBranch());
    try std.testing.expectEqualStrings("/tmp/faku/wt", wt.projectPath());
}

test "sessions.json round-trips newWorktree with and without baseBranch; upsert copies workspace" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-ws-base", .{tmp.sub_path[0..]});
    const io = testing.io;
    const allocator = testing.allocator;

    var source = Model{};
    source.task_state_loaded = true;
    source.setStoreDir(dir);
    source.store_io = io;

    const local_id = source.addSession("local first", .fx);
    _ = source.appendTurn(local_id, .user, "seed row");
    source.selected = local_id;
    try store.saveSession(&source, local_id, allocator, io);

    source.sessionById(local_id).?.setWorkspaceNewWorktree();
    source.sessionById(local_id).?.setWorkspaceBaseBranch("feat");
    source.sessionById(local_id).?.setProjectPath("/tmp/proj");
    try store.saveSession(&source, local_id, allocator, io);

    const bare_id = source.addSession("bare new worktree", .fx);
    _ = source.appendTurn(bare_id, .user, "no base");
    source.sessionById(bare_id).?.setWorkspaceNewWorktree();
    source.sessionById(bare_id).?.setProjectPath("/tmp/proj");
    try store.saveSession(&source, bare_id, allocator, io);
    source.selected = local_id;
    try store.saveSession(&source, local_id, allocator, io);

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const catalog = store.catalogPath(dir, &path_buf) orelse return error.MissingCatalog;
    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, catalog, allocator, .limited(store.max_document_bytes));
    defer allocator.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"kind\":\"newWorktree\",\"baseBranch\":\"feat\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"kind\":\"newWorktree\"}") != null);

    var loaded = Model{};
    loaded.setStoreDir(dir);
    loaded.store_io = io;
    try std.testing.expectEqual(store.LoadKind.loaded, store.loadCatalog(&loaded, allocator, io));
    const with_base = loaded.sessionByIdConst(local_id).?;
    try std.testing.expect(isNewWorktree(with_base));
    try std.testing.expectEqualStrings("feat", with_base.workspaceBaseBranch());
    const bare = loaded.sessionByIdConst(bare_id).?;
    try std.testing.expect(isNewWorktree(bare));
    try std.testing.expectEqualStrings("", bare.workspaceBaseBranch());
    try std.testing.expectEqual(local_id, loaded.selected);
    try std.testing.expectEqualStrings("feat", git_checkout.gitWorktreeBaseOverride(&loaded));

    loaded.selected = bare_id;
    loaded.syncGitWorktreeBaseOverride();
    try std.testing.expectEqual(@as(usize, 0), loaded.git_worktree_base_override_len);
    loaded.selected = local_id;
    loaded.syncGitWorktreeBaseOverride();
    try std.testing.expectEqualStrings("feat", git_checkout.gitWorktreeBaseOverride(&loaded));
}

test "Work-in Base pick persists baseBranch and clear Base clears both" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-ws-pick-base", .{tmp.sub_path[0..]});
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/ws-pick-base", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(testing.io, project);

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.task_state_loaded = true;
    model.setStoreDir(dir);
    model.store_io = testing.io;
    const id = model.addSession("pick base", .fx);
    _ = model.appendTurn(id, .user, "started");
    model.selected = id;
    model.sessionById(id).?.setProjectPath(project);
    model.git_branch_list_store[0].set("main", false, false);
    model.git_branch_list_store[1].set("feat", false, false);
    model.git_branch_list_count = 2;

    pickNewWorktree(&model, &fx);
    git_checkout.pickWorktreeBaseName(&model, "feat");
    persist.persistComposerChips(&model, &fx);
    try std.testing.expectEqualStrings("feat", model.sessionByIdConst(id).?.workspaceBaseBranch());
    try std.testing.expectEqualStrings("feat", git_checkout.gitWorktreeBaseOverride(&model));

    git_checkout.clearWorktreeBaseName(&model);
    persist.persistComposerChips(&model, &fx);
    try std.testing.expectEqualStrings("", model.sessionByIdConst(id).?.workspaceBaseBranch());
    try std.testing.expectEqual(@as(usize, 0), model.git_worktree_base_override_len);

    git_checkout.pickWorktreeBaseName(&model, "feat");
    persist.persistComposerChips(&model, &fx);
    git_checkout.pickWorktreeBaseName(&model, "");
    persist.persistComposerChips(&model, &fx);
    try std.testing.expectEqualStrings("", model.sessionByIdConst(id).?.workspaceBaseBranch());
    try std.testing.expectEqual(@as(usize, 0), model.git_worktree_base_override_len);

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const catalog = store.catalogPath(dir, &path_buf) orelse return error.MissingCatalog;
    const bytes = try std.Io.Dir.cwd().readFileAlloc(testing.io, catalog, testing.allocator, .limited(store.max_document_bytes));
    defer testing.allocator.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"baseBranch\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"kind\":\"newWorktree\"") != null);
}

test "Local and Fork-to-local clear stored baseBranch" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-ws-clear-base", .{tmp.sub_path[0..]});
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/ws-clear-base", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(testing.io, project);

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.task_state_loaded = true;
    model.setStoreDir(dir);
    model.store_io = testing.io;
    const id = model.addSession("clear base", .fx);
    _ = model.appendTurn(id, .user, "keep me");
    _ = model.appendTurn(id, .assistant, "ok");
    model.selected = id;
    model.sessionById(id).?.setProjectPath(project);
    pickNewWorktree(&model, &fx);
    model.sessionById(id).?.setWorkspaceBaseBranch("feat");
    main.writeFixed(&model.git_worktree_base_override_storage, &model.git_worktree_base_override_len, "feat");
    persist.persistComposerChips(&model, &fx);

    pickLocal(&model, &fx);
    try std.testing.expect(isLocal(model.sessionByIdConst(id).?));
    try std.testing.expectEqualStrings("", model.sessionByIdConst(id).?.workspaceBaseBranch());
    try std.testing.expectEqual(@as(usize, 0), model.git_worktree_base_override_len);

    pickNewWorktree(&model, &fx);
    model.sessionById(id).?.setWorkspaceBaseBranch("feat");
    persist.persistComposerChips(&model, &fx);

    session_fork.forkSelectedThrough(&model, &fx, 1);
    const fork_id = model.selected;
    try std.testing.expect(fork_id != id);
    const forked = model.sessionByIdConst(fork_id).?;
    try std.testing.expect(isLocal(forked));
    try std.testing.expectEqualStrings("", forked.workspaceBaseBranch());
    try std.testing.expectEqual(@as(usize, 0), model.git_worktree_base_override_len);
    const source = model.sessionByIdConst(id).?;
    try std.testing.expect(isNewWorktree(source));
    try std.testing.expectEqualStrings("feat", source.workspaceBaseBranch());
}

test "Send with stored baseBranch skips origin/HEAD and uses that argv slot; materialize clears it" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/ws-send-base", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);
    var home_buf: [256]u8 = undefined;
    const home = try std.fmt.bufPrint(&home_buf, "/tmp/faku-ws-base-{s}", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, home);

    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = std.testing.io;
    model.fx_probe_started = true;
    model.setHome(home);
    const id = model.addSession("feat stored base", .fx);
    model.selected = id;
    model.sessionById(id).?.setProjectPath(project);
    pickNewWorktree(&model, &fx);
    model.sessionById(id).?.setWorkspaceBaseBranch("feat");
    try std.testing.expectEqual(@as(usize, 0), model.git_worktree_base_override_len);

    model.draft_buffer.apply(.{ .insert_text = "ship with stored base" });
    main.update(&model, .send, &fx);
    try std.testing.expect(model.workspace_prep_active);
    try std.testing.expectEqual(@as(u64, 0), model.git_worktree_base_key);
    try std.testing.expect(model.git_worktree_add_key != 0);
    try std.testing.expect(!pendingProviderStart(&fx));

    const created = findWorktreeAddSpawn(&fx, model.git_worktree_add_key) orelse return error.MissingWorktreeAddStoredBase;
    try std.testing.expect(git_checkout.isGitWorktreeAddArgv(created.argv));
    try std.testing.expectEqualStrings("feat", created.argv[created.argv.len - 1]);
    if (std.mem.eql(u8, created.argv[0], "/bin/sh")) {
        try std.testing.expect(std.mem.indexOf(u8, created.argv[2], "feat") == null);
    }

    var dest_buf: [main.max_project_path]u8 = undefined;
    const dest = git_checkout.worktreeDestPath(home, project, "feat-stored-base", dest_buf[0..]) orelse return error.MissingDest;
    try fx.feedExit(created.key, 0);
    drainEffects(&model, &fx);
    const session = model.sessionByIdConst(id).?;
    try std.testing.expect(isMaterialized(session));
    try std.testing.expectEqualStrings("", session.workspaceBaseBranch());
    try std.testing.expectEqualStrings(dest, session.projectPath());
    try std.testing.expect(model.is_streaming());
}

const worktree_created_line =
    "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000014\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"workspace\",\"result\":{\"type\":\"worktreeCreated\",\"worktree\":{\"path\":\"/tmp/daemon-wt\",\"branch\":\"waku/feat-send\"}}}}}";

test "Send while newWorktree with a daemon address spawns CreateWorktree sidecar" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/ws-send-daemon", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);
    var home_buf: [256]u8 = undefined;
    const home = try std.fmt.bufPrint(&home_buf, "/tmp/faku-ws-daemon-{s}", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, home);

    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = std.testing.io;
    model.fx_probe_started = true;
    model.setHome(home);
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    const id = model.addSession("feat daemon", .fx);
    model.selected = id;
    model.sessionById(id).?.setProjectPath(project);
    pickNewWorktree(&model, &fx);

    model.draft_buffer.apply(.{ .insert_text = "ship the workspace cut" });
    main.update(&model, .send, &fx);
    try std.testing.expect(model.workspace_prep_active);
    try std.testing.expect(!model.is_streaming());
    try std.testing.expectEqualStrings(preparing_status, model.attach_status());
    try std.testing.expectEqual(@as(u64, 0), model.git_worktree_base_key);
    try std.testing.expect(model.git_worktree_add_key != 0);
    try std.testing.expect(!pendingProviderStart(&fx));
    try std.testing.expect(findWorktreeAddSpawn(&fx, model.git_worktree_add_key) == null);
    try std.testing.expect(isNewWorktree(model.sessionByIdConst(id).?));
    try std.testing.expectEqualStrings(project, model.selectedProjectPath());

    const sidecar = findDaemonWorkspaceSpawn(&fx, model.git_worktree_add_key) orelse return error.MissingDaemonCreateWorktree;
    try std.testing.expect(git_checkout.isDaemonWorkspacePushArgv(sidecar.argv));
    try std.testing.expectEqualStrings("faku", sidecar.argv[0]);
    try std.testing.expectEqualStrings(daemon_proxy.SUBCOMMAND, sidecar.argv[1]);
    try std.testing.expectEqualStrings("127.0.0.1:8787", sidecar.argv[2]);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"workspace\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"createWorktree\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"push\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, project) != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"prompt\":\"ship the workspace cut\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"base_branch\":null") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"sessionId\":\"" ++ protocol.NIL_UUID ++ "\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"runtimeId\":\"" ++ protocol.NIL_UUID ++ "\"") != null);
    var id_buf: [36]u8 = undefined;
    const wire_id = daemon_proxy.wireUuid(id, &id_buf);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, wire_id) != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"session_id\":\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"project_id\":\"") != null);

    try fx.feedLine(sidecar.key, worktree_created_line);
    drainEffects(&model, &fx);
    try fx.feedExit(sidecar.key, 0);
    drainEffects(&model, &fx);

    try std.testing.expectEqual(@as(u64, 0), model.git_worktree_add_key);
    try std.testing.expect(!model.workspace_prep_active);
    const session = model.sessionByIdConst(id).?;
    try std.testing.expect(isMaterialized(session));
    try std.testing.expectEqualStrings("/tmp/daemon-wt", session.projectPath());
    try std.testing.expectEqualStrings("/tmp/daemon-wt", session.workspacePath());
    try std.testing.expectEqualStrings("waku/feat-send", session.workspaceBranch());
    try std.testing.expect(model.is_streaming());
    try std.testing.expectEqual(main.ReplyPath.demo, model.reply_path);
    try std.testing.expectEqual(@as(usize, 1), fx.pendingTimerCount());
}

test "Send CreateWorktree sidecar failure leaves newWorktree and does not prompt" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/ws-send-daemon-fail", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);
    var home_buf: [256]u8 = undefined;
    const home = try std.fmt.bufPrint(&home_buf, "/tmp/faku-ws-daemon-fail-{s}", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, home);

    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = std.testing.io;
    model.fx_probe_started = true;
    model.setHome(home);
    model.setLastDaemonAddress("10.0.0.2:9");
    model.setSidecarPath("faku");
    const id = model.addSession("feat daemon fail", .fx);
    model.selected = id;
    model.sessionById(id).?.setProjectPath(project);
    pickNewWorktree(&model, &fx);

    model.draft_buffer.apply(.{ .insert_text = "do not start yet" });
    main.update(&model, .send, &fx);
    try std.testing.expect(model.workspace_prep_active);
    try std.testing.expect(!model.is_streaming());

    const sidecar = findDaemonWorkspaceSpawn(&fx, model.git_worktree_add_key) orelse return error.MissingDaemonCreateWorktreeFail;
    try fx.feedExit(sidecar.key, 1);
    drainEffects(&model, &fx);

    try std.testing.expectEqual(@as(u64, 0), model.git_worktree_add_key);
    try std.testing.expect(!model.workspace_prep_active);
    try std.testing.expect(!model.is_streaming());
    try std.testing.expectEqual(@as(usize, 0), fx.pendingTimerCount());
    try std.testing.expect(isNewWorktree(model.sessionByIdConst(id).?));
    try std.testing.expectEqualStrings(project, model.selectedProjectPath());
    try std.testing.expectEqualStrings(git_checkout.worktree_add_failed_status, model.attach_status());
    try std.testing.expectEqualStrings("do not start yet", model.draft());
}

test "Send CreateWorktree sidecar with stored baseBranch puts it on the wire" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/ws-send-daemon-base", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);
    var home_buf: [256]u8 = undefined;
    const home = try std.fmt.bufPrint(&home_buf, "/tmp/faku-ws-daemon-base-{s}", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, home);

    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = std.testing.io;
    model.fx_probe_started = true;
    model.setHome(home);
    model.setDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    const id = model.addSession("feat daemon base", .fx);
    model.selected = id;
    model.sessionById(id).?.setProjectPath(project);
    pickNewWorktree(&model, &fx);
    model.sessionById(id).?.setWorkspaceBaseBranch("feat");

    model.draft_buffer.apply(.{ .insert_text = "ship with stored base" });
    main.update(&model, .send, &fx);
    try std.testing.expect(model.workspace_prep_active);
    try std.testing.expectEqual(@as(u64, 0), model.git_worktree_base_key);
    try std.testing.expect(findWorktreeAddSpawn(&fx, model.git_worktree_add_key) == null);

    const sidecar = findDaemonWorkspaceSpawn(&fx, model.git_worktree_add_key) orelse return error.MissingDaemonCreateWorktreeBase;
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"base_branch\":\"feat\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"base_branch\":null") == null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"prompt\":\"ship with stored base\"") != null);

    try fx.feedLine(sidecar.key, worktree_created_line);
    drainEffects(&model, &fx);
    try fx.feedExit(sidecar.key, 0);
    drainEffects(&model, &fx);
    const session = model.sessionByIdConst(id).?;
    try std.testing.expect(isMaterialized(session));
    try std.testing.expectEqualStrings("", session.workspaceBaseBranch());
    try std.testing.expectEqualStrings("/tmp/daemon-wt", session.projectPath());
    try std.testing.expect(model.is_streaming());
}

test "Send CreateWorktree sidecar exit 0 without worktreeCreated fails closed" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/ws-send-daemon-ack", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);
    var home_buf: [256]u8 = undefined;
    const home = try std.fmt.bufPrint(&home_buf, "/tmp/faku-ws-daemon-ack-{s}", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, home);

    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = std.testing.io;
    model.fx_probe_started = true;
    model.setHome(home);
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    const id = model.addSession("feat daemon ack", .fx);
    model.selected = id;
    model.sessionById(id).?.setProjectPath(project);
    pickNewWorktree(&model, &fx);

    model.draft_buffer.apply(.{ .insert_text = "need a worktree result" });
    main.update(&model, .send, &fx);
    const sidecar = findDaemonWorkspaceSpawn(&fx, model.git_worktree_add_key) orelse return error.MissingDaemonCreateWorktreeAck;
    try fx.feedLine(sidecar.key, "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000014\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"workspace\",\"result\":{\"type\":\"ack\"}}}}");
    drainEffects(&model, &fx);
    try fx.feedExit(sidecar.key, 0);
    drainEffects(&model, &fx);

    try std.testing.expect(!model.is_streaming());
    try std.testing.expect(isNewWorktree(model.sessionByIdConst(id).?));
    try std.testing.expectEqualStrings(project, model.selectedProjectPath());
    try std.testing.expectEqualStrings(git_checkout.worktree_add_failed_status, model.attach_status());
}
