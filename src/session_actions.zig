//! Session / folder / title-edit update helpers.
//!
//! `handleNewSession` / `handleSelect` / folder + title edits /
//! `handleRemoveSession` / `handleEditQueued` live here.
//! Msg routing stays in `update.zig`. First-cut remembered New Task
//! (runtime-only Waku SessionNavigation.new_task): selecting an
//! unstarted session stores its id. Ordinary New Task reopens that
//! draft when it still exists, has not started, and `projectPath()`
//! equals the current ordinary project path (Waku
//! `remembered_new_task` project filter; same select path as
//! projectless draft reuse). A draft for another path is skipped
//! without clearing the slot; create does not steal it. Visiting
//! started sessions does not clear the slot. Started / removed /
//! missing drafts are ignored.
//! Projectless New Task does not consult the slot (Waku
//! `create_projectless_session` never calls `remembered_new_task`).
//! An existing unstarted non-legacy projectless draft is selected
//! (same select effects as clicking that session) instead of
//! `addSession`.
//! First-cut remove destination (Waku `taskRemovalDestination` on
//! `project_path`): when the removed row was selected, remaining
//! same-path newest (`updated_at` desc, higher id on a tie) is
//! selected via `pushSelectionHistory` + equivalent refresh; else
//! projectless New Task (reuse `reusableUnstartedDraftId` or create
//! like `handleNewSession`); else ordinary New Task draft with that
//! path; else `selected = 0`. Non-selected remove leaves `selected`.
//! First-cut daemon
//! `WorkspaceOperation::CreateProjectlessWorkspace` prefers hello +
//! createProjectlessWorkspace on actual create when there is no
//! ordinary project (empty `last_project_path`, or the selected
//! session is already projectless under `~/.waku/projects`); Native
//! 4 KiB stdin overflow / sidecar miss fall back to local mkdir.
//! Ordinary New Task with a real project path still copies
//! `last_project_path`.
//! New Task create prefers the selected session's `access_mode`
//! when that field is non-empty (Waku `new_task_runtime_mode`);
//! else remembered `last_access_mode`; else `fullAccess`.
//! Remembered New Task / projectless draft reuse only select the
//! existing draft and do not rewrite its access mode.
//! First-cut daemon `WorkspaceOperation::MigrateProjectlessWorkspace`
//! prefers hello + migrateProjectlessWorkspace on session select /
//! boot when the selected cwd still needs migration (legacy
//! projectless, not under `~/.waku/projects`); Native 4 KiB stdin
//! overflow / sidecar miss fall back to local rename / fresh mkdir.

const std = @import("std");
const native_sdk = @import("native_sdk");
const main = @import("main.zig");
const store = @import("store.zig");
const persist = @import("persist.zig");
const attach_helpers = @import("attach.zig");
const git_branch = @import("git_branch.zig");
const git_checkout = @import("git_checkout.zig");
const git_dirty = @import("git_dirty.zig");
const git_numstat = @import("git_numstat.zig");
const file_mention = @import("file_mention.zig");
const slash_commands = @import("slash_commands.zig");
const projectless = @import("projectless.zig");
const sidebar_row_helpers = @import("sidebar_rows.zig");
const palette_run = @import("palette_run.zig");
const environment_summary = @import("environment_summary.zig");
const review_diff = @import("review_diff.zig");
const right_panel = @import("right_panel.zig");
const right_panel_session = @import("right_panel_session.zig");
const file_preview_images = @import("file_preview_images.zig");
const file_preview_details = @import("file_preview_details.zig");
const file_preview_issue_link = @import("file_preview_issue_link.zig");
const transcript_images = @import("transcript_images.zig");
const transcript_details = @import("transcript_details.zig");
const session_fork = @import("fork.zig");
const pick_folder = @import("pick_folder.zig");
const usage_meter = @import("usage_meter.zig");

const Model = main.Model;
const Effects = main.Effects;
const max_title = main.max_title;
const max_project_path = main.max_project_path;
const max_queued_text = main.max_queued_text;
const canvas = native_sdk.canvas;

pub fn handleNewSession(model: *Model, fx: *Effects) void {
    if (!right_panel.beginDiscardOrPark(model, .new_session)) return;
    var prior_buf: [max_project_path]u8 = undefined;
    const prior_src = model.selectedProjectPath();
    const prior_n = @min(prior_src.len, prior_buf.len);
    @memcpy(prior_buf[0..prior_n], prior_src[0..prior_n]);
    const prior = prior_buf[0..prior_n];
    if (projectless.wantsProjectlessWorkspace(model, prior)) {
        if (projectless.reusableUnstartedDraftId(model)) |draft_id| {
            model.pushSelectionHistory(draft_id);
            palette_run.applySessionSelection(model, fx, draft_id);
            return;
        }
    } else if (model.rememberedNewTask(ordinaryNewTaskProjectPath(model, prior))) |draft_id| {
        model.pushSelectionHistory(draft_id);
        palette_run.applySessionSelection(model, fx, draft_id);
        return;
    }
    right_panel_session.take(model);
    store.persistDraftIfPossible(model);
    environment_summary.close(model);
    review_diff.close(model, fx);
    file_preview_images.drop(model, fx);
    file_preview_details.drop(model);
    file_preview_issue_link.drop(model, fx);
    transcript_images.drop(model, fx);
    transcript_details.drop(model);
    right_panel.clearFilePreview(model);
    model.closeProjectEdit();
    pick_folder.closeDaemonBrowser(model, fx);
    model.closeImageAttach();
    model.closeCommands();
    model.closeModelPicker();
    model.closeFolderTitleEdit();
    model.closeSessionTitleEdit();
    const id = model.addSession("untitled", .fx);
    if (id == 0) return;
    if (model.sessionById(id)) |session| session.untitled = true;
    model.pushSelectionHistory(id);
    model.selected = id;
    // Occupied slot is a still-valid other-project draft (Waku
    // remembered_new_task returns None without clearing; create does
    // not steal it). Empty / started / missing already cleared to 0.
    if (model.new_task == 0) model.rememberNewTask(id);
    // Client-built; persist is a no-op until first real content.
    store.persistIfPossible(model, id, fx);
    store.loadDraftIfPossible(model);
    projectless.beginForNewSession(model, fx, prior);
    projectless.cancelMigrate(model, fx);
    attach_helpers.refreshAttachPreview(model, fx);
    git_branch.refresh(model, fx);
    git_dirty.refresh(model, fx);
    git_numstat.refresh(model, fx);
    file_mention.refresh(model, fx);
    right_panel_session.restore(model, fx);
    git_checkout.refresh(model, fx);
    file_preview_issue_link.refresh(model, fx);
    session_fork.cancelDaemonCaptureTurnStart(model, fx);
    session_fork.cancelDaemonCaptureTurn(model, fx);
    session_fork.cancelDaemonCopySessionRefs(model, fx);
    store.cancelDaemonDeleteSessionRefs(model, fx);
    session_fork.cancelDaemonHasRef(model, fx);
    session_fork.cancelDaemonCaptureRef(model, fx);
    session_fork.cancelDaemonRestoreRef(model, fx);
    session_fork.cancelDaemonDeleteRef(model, fx);
    session_fork.cancelDaemonDeleteTurnRefsAfter(model, fx);
    session_fork.cancelDaemonSessionTurnRefs(model, fx);
    session_fork.refreshSessionTurnRefs(model, fx);
    slash_commands.cancel(model, fx);
    slash_commands.refresh(model, fx);
    model.maybeEnsureSkillsScanned(fx);
    model.composer_active = true;
}

pub fn handleSelect(model: *Model, fx: *Effects, id: u32) void {
    if (model.editing_session_id == id) return;
    if (id == model.selected and model.sessionById(id) != null) {
        model.startSessionTitleEdit(id);
        return;
    }
    if (model.sessionById(id) != null) {
        if (!right_panel.beginDiscardOrPark(model, .{ .switch_session = id })) return;
        model.pushSelectionHistory(id);
        palette_run.applySessionSelection(model, fx, id);
    }
}

pub fn handleNewFolder(model: *Model) void {
    var title_buf: [max_title]u8 = undefined;
    const title = model.nextUntitledFolderTitle(&title_buf);
    if (model.addFolder(title) == 0) return;
    store.persistFoldersIfPossible(model);
}

pub fn handleToggleFolder(model: *Model, folder_id: u32) void {
    model.toggleFolderCollapsed(folder_id);
    store.persistFoldersIfPossible(model);
}

pub fn handleCollapseAllFolders(model: *Model) void {
    if (model.folder_count == 0) return;
    if (model.collapseAllFolders()) store.persistFoldersIfPossible(model);
}

pub fn handleRenameFolder(model: *Model, id: u32) void {
    model.startFolderTitleEdit(id);
}

pub fn handleAssignSelected(model: *Model, fx: *Effects, folder_id: u32) void {
    if (model.editing_folder_id == folder_id) return;
    if (model.editing_folder_id != 0) model.closeFolderTitleEdit();
    // Second click on the folder that already holds the selected
    // session edits the title and does not assign again.
    if (sidebar_row_helpers.selectedSessionInFolder(model, folder_id)) {
        model.startFolderTitleEdit(folder_id);
        return;
    }
    persist.persistAssignedFolder(model, model.selected, folder_id, fx);
}

pub fn handleUnassignSelected(model: *Model, fx: *Effects) void {
    model.closeFolderTitleEdit();
    persist.persistAssignedFolder(model, model.selected, 0, fx);
}

pub fn handleFolderTitleEdit(model: *Model, edit: canvas.TextInputEvent) void {
    model.applyFolderTitle(edit);
    store.persistFoldersIfPossible(model);
}

pub fn handleEditSessionTitle(model: *Model) void {
    if (model.selected != 0) model.startSessionTitleEdit(model.selected);
}

pub fn handleRenameSession(model: *Model, id: u32) void {
    model.startSessionTitleEdit(id);
}

pub fn handleSessionTitleEdit(model: *Model, fx: *Effects, edit: canvas.TextInputEvent) void {
    const session_id = model.editing_session_id;
    model.applySessionTitle(edit);
    store.persistIfPossible(model, session_id, fx);
}

pub fn handleRemoveSession(model: *Model, fx: *Effects, id: u32) void {
    if (!right_panel.beginDiscardOrPark(model, .{ .remove_session = id })) return;
    right_panel_session.take(model);
    if (model.editing_session_id == id) model.closeSessionTitleEdit();
    model.closeCommands();
    file_preview_images.drop(model, fx);
    file_preview_details.drop(model);
    file_preview_issue_link.drop(model, fx);
    transcript_images.drop(model, fx);
    transcript_details.drop(model);
    right_panel.clearFilePreview(model);
    environment_summary.clearSettledIfSession(model, id);
    store.cancelDaemonDeleteSessionRefs(model, fx);
    const was_selected = model.selected == id;
    var path_buf: [max_project_path]u8 = undefined;
    var path_len: usize = 0;
    if (was_selected) {
        if (model.sessionByIdConst(id)) |session| {
            const path = session.projectPath();
            path_len = @min(path.len, path_buf.len);
            @memcpy(path_buf[0..path_len], path[0..path_len]);
        }
    }
    store.removeIfPossible(model, id, fx);
    if (was_selected and model.sessionById(id) == null) {
        applyRemovalDestination(model, fx, path_buf[0..path_len]);
        store.persistSelectedIfPossible(model);
    }
    store.loadDraftIfPossible(model);
    attach_helpers.refreshAttachPreview(model, fx);
    git_branch.refresh(model, fx);
    git_dirty.refresh(model, fx);
    git_numstat.refresh(model, fx);
    file_mention.refresh(model, fx);
    right_panel_session.restore(model, fx);
    git_checkout.refresh(model, fx);
    file_preview_issue_link.refresh(model, fx);
    session_fork.cancelDaemonCaptureTurnStart(model, fx);
    session_fork.cancelDaemonCaptureTurn(model, fx);
    session_fork.cancelDaemonCopySessionRefs(model, fx);
    session_fork.cancelDaemonHasRef(model, fx);
    session_fork.cancelDaemonCaptureRef(model, fx);
    session_fork.cancelDaemonRestoreRef(model, fx);
    session_fork.cancelDaemonDeleteRef(model, fx);
    session_fork.cancelDaemonDeleteTurnRefsAfter(model, fx);
    session_fork.cancelDaemonSessionTurnRefs(model, fx);
    session_fork.refreshSessionTurnRefs(model, fx);
    slash_commands.cancel(model, fx);
    slash_commands.refresh(model, fx);
    if (model.daemon_projectless_session == id) projectless.cancel(model, fx);
    if (model.daemon_migrate_projectless_session == id) projectless.cancelMigrate(model, fx);
    model.maybeEnsureSkillsScanned(fx);
}

/// Path a fresh ordinary New Task draft would inherit: selected
/// session cwd when present, else `lastProjectPath()`. Callers already
/// checked `!wantsProjectlessWorkspace` (Faku has no Project UUID).
fn ordinaryNewTaskProjectPath(model: *const Model, prior: []const u8) []const u8 {
    if (prior.len > 0) return prior;
    return model.lastProjectPath();
}

/// After dropping the selected session: remaining same-path newest
/// is already `selected` from `dropSession` — push history + hydrate.
/// Else projectless New Task (reuse draft or create). Else ordinary
/// New Task with `project_path`. Else leave `selected = 0`.
fn applyRemovalDestination(model: *Model, fx: *Effects, project_path: []const u8) void {
    if (model.selected != 0) {
        refreshRemainingDestination(model, fx, model.selected);
        return;
    }
    if (projectless.isProjectlessPath(model.homeDir(), project_path)) {
        if (projectless.reusableUnstartedDraftId(model)) |draft_id| {
            model.pushSelectionHistory(draft_id);
            palette_run.applySessionSelection(model, fx, draft_id);
            return;
        }
        createUntitledDraft(model, fx, "");
        projectless.beginForNewSession(model, fx, project_path);
        return;
    }
    if (project_path.len > 0) {
        createUntitledDraft(model, fx, project_path);
    }
}

fn refreshRemainingDestination(model: *Model, fx: *Effects, id: u32) void {
    model.pushSelectionHistory(id);
    model.rememberNewTask(id);
    store.hydrateIfPossible(model, id);
    store.maybeHydrateDaemonSession(model, fx, id);
    usage_meter.onSessionChange(model, fx);
    projectless.beginMigrateForSelected(model, fx);
    model.pinTranscriptToLatest();
    model.composer_active = true;
}

fn createUntitledDraft(model: *Model, fx: *Effects, project_path: []const u8) void {
    const id = model.addSession("untitled", .fx);
    if (id == 0) return;
    if (model.sessionById(id)) |session| {
        session.untitled = true;
        if (project_path.len > 0) {
            session.setProjectPath(project_path);
            model.setLastProjectPath(project_path);
        }
    }
    model.pushSelectionHistory(id);
    model.selected = id;
    model.rememberNewTask(id);
    store.persistIfPossible(model, id, fx);
    store.loadDraftIfPossible(model);
    projectless.cancelMigrate(model, fx);
}

pub fn handleEditQueued(model: *Model, fx: *Effects, id: u32) void {
    var found = false;
    for (model.queued_store[0..model.queued_count]) |item| {
        if (item.id != id) continue;
        found = true;
        if (std.mem.trim(u8, item.text(), " \t\r\n").len == 0) return;
        break;
    }
    if (!found) return;
    var copy: [max_queued_text]u8 = undefined;
    const n = model.takeQueued(id, &copy) orelse return;
    const text = std.mem.trim(u8, copy[0..n], " \t\r\n");
    if (text.len == 0) return;
    model.draft_buffer.set(text);
    model.clearImageAttach();
    model.composer_active = true;
    store.persistIfPossible(model, model.selected, fx);
    store.persistDraftIfPossible(model);
    attach_helpers.refreshAttachPreview(model, fx);
}

fn pendingSpawnKey(fx: *Effects, key: u64) ?@TypeOf(fx.pendingSpawnAt(0).?) {
    var i: usize = 0;
    while (fx.pendingSpawnAt(i)) |spawn| : (i += 1) {
        if (spawn.key == key) return spawn;
    }
    return null;
}

test "handleNewSession with a daemon address issues createProjectlessWorkspace" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = std.testing.io;
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");

    handleNewSession(&model, &fx);
    const sidecar = pendingSpawnKey(&fx, model.daemon_projectless_key) orelse return error.MissingHandleNewSessionProjectless;
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"createProjectlessWorkspace\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"prompt\":null") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"sessionId\":\"" ++ @import("protocol.zig").NIL_UUID ++ "\"") != null);
    try std.testing.expect(model.sessionById(model.selected).?.untitled);
}

test "handleNewSession with a real last_project_path does not spawn createProjectlessWorkspace" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/new-task-real-project", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    model.setLastProjectPath(project);

    handleNewSession(&model, &fx);
    try std.testing.expectEqual(@as(u64, 0), model.daemon_projectless_key);
    try std.testing.expectEqualStrings(project, model.sessionById(model.selected).?.projectPath());
    try std.testing.expectEqualStrings(project, model.lastProjectPath());
}

test "handleNewSession reuses an unstarted non-legacy projectless draft" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = std.testing.io;
    model.setHome("/home/me");
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    model.setLastProjectPath("/home/me/.waku/projects/2026-09-06/new-chat");
    const draft = model.addSession("untitled", .fx);
    if (model.sessionById(draft)) |session| session.untitled = true;
    model.selected = draft;
    const count = model.session_count;

    handleNewSession(&model, &fx);
    try std.testing.expectEqual(draft, model.selected);
    try std.testing.expectEqual(count, model.session_count);
    try std.testing.expectEqual(@as(u64, 0), model.daemon_projectless_key);
    try std.testing.expect(model.composer_active);
}

test "handleNewSession with only a started projectless session still creates" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = std.testing.io;
    model.setHome("/home/me");
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    model.setLastProjectPath("/home/me/.waku/projects/2026-09-06/new-chat");
    const started = model.addSession("started", .fx);
    if (model.sessionById(started)) |session| session.has_started = true;
    model.selected = started;
    const count = model.session_count;

    handleNewSession(&model, &fx);
    try std.testing.expectEqual(count + 1, model.session_count);
    try std.testing.expect(model.selected != started);
    const sidecar = pendingSpawnKey(&fx, model.daemon_projectless_key) orelse return error.MissingCreateAfterStartedProjectless;
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"createProjectlessWorkspace\"") != null);
}

test "handleNewSession with a real project still creates even if a projectless draft exists" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/new-task-keep-real", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    model.setHome("/home/me");
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    model.setLastProjectPath("/home/me/.waku/projects/2026-09-06/new-chat");
    const draft = model.addSession("untitled", .fx);
    if (model.sessionById(draft)) |session| session.untitled = true;
    model.setLastProjectPath(project);
    const real = model.addSession("real", .fx);
    model.selected = real;
    const count = model.session_count;

    handleNewSession(&model, &fx);
    try std.testing.expectEqual(count + 1, model.session_count);
    try std.testing.expect(model.selected != draft);
    try std.testing.expect(model.selected != real);
    try std.testing.expectEqual(@as(u64, 0), model.daemon_projectless_key);
    try std.testing.expectEqualStrings(project, model.sessionById(model.selected).?.projectPath());
}

test "handleNewSession does not reuse a bare ~/.waku legacy draft" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = std.testing.io;
    model.setHome("/home/me");
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    model.setLastProjectPath("/home/me/.waku");
    const legacy = model.addSession("legacy", .fx);
    if (model.sessionById(legacy)) |session| session.untitled = true;
    model.selected = legacy;
    const count = model.session_count;

    handleNewSession(&model, &fx);
    try std.testing.expectEqual(count + 1, model.session_count);
    try std.testing.expect(model.selected != legacy);
    const sidecar = pendingSpawnKey(&fx, model.daemon_projectless_key) orelse return error.MissingCreateAfterBareLegacy;
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"createProjectlessWorkspace\"") != null);
}

test "handleNewSession reopens a remembered unstarted draft instead of creating" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/remembered-new-task", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    model.setLastProjectPath(project);
    handleNewSession(&model, &fx);
    const draft = model.selected;
    try std.testing.expect(model.sessionById(draft).?.untitled);
    try std.testing.expectEqual(draft, model.new_task);
    const count = model.session_count;

    handleNewSession(&model, &fx);
    try std.testing.expectEqual(draft, model.selected);
    try std.testing.expectEqual(count, model.session_count);
    try std.testing.expect(model.composer_active);
}

test "handleNewSession keeps remembered draft after visiting a started session" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/remembered-after-history", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    model.setLastProjectPath(project);
    const started = model.addSession("started", .fx);
    if (model.sessionById(started)) |session| session.has_started = true;
    model.selected = started;
    const draft = model.addSession("untitled", .fx);
    if (model.sessionById(draft)) |session| session.untitled = true;
    handleSelect(&model, &fx, draft);
    try std.testing.expectEqual(draft, model.new_task);
    handleSelect(&model, &fx, started);
    try std.testing.expectEqual(started, model.selected);
    try std.testing.expectEqual(draft, model.new_task);
    const count = model.session_count;

    handleNewSession(&model, &fx);
    try std.testing.expectEqual(draft, model.selected);
    try std.testing.expectEqual(count, model.session_count);
}

test "handleNewSession does not reopen a started remembered draft" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/remembered-started", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    model.setLastProjectPath(project);
    handleNewSession(&model, &fx);
    const draft = model.selected;
    _ = model.appendTurn(draft, .user, "started");
    try std.testing.expectEqual(@as(u32, 0), model.new_task);
    const count = model.session_count;

    handleNewSession(&model, &fx);
    try std.testing.expectEqual(count + 1, model.session_count);
    try std.testing.expect(model.selected != draft);
}

test "handleNewSession does not reopen a removed remembered draft" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/remembered-removed", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    model.setLastProjectPath(project);
    handleNewSession(&model, &fx);
    const draft = model.selected;
    try std.testing.expectEqual(draft, model.new_task);
    model.dropSession(draft);
    try std.testing.expectEqual(@as(u32, 0), model.new_task);
    const count = model.session_count;

    handleNewSession(&model, &fx);
    try std.testing.expectEqual(count + 1, model.session_count);
    try std.testing.expect(model.selected != draft);
}

test "handleNewSession reopening remembered draft restores right-panel stash" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/remembered-stash", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    model.setLastProjectPath(project);
    defer right_panel_session.freeStores(&model);

    const started = model.addSession("started", .fx);
    if (model.sessionById(started)) |session| session.has_started = true;
    model.selected = started;
    handleNewSession(&model, &fx);
    const draft = model.selected;
    model.showRightPanel();
    model.right_panel_tab = .diff;
    handleSelect(&model, &fx, started);
    try std.testing.expect(!model.right_panel_open);
    try std.testing.expectEqual(right_panel.Tab.files, model.right_panel_tab);

    handleNewSession(&model, &fx);
    try std.testing.expectEqual(draft, model.selected);
    try std.testing.expect(model.right_panel_open);
    try std.testing.expectEqual(right_panel.Tab.diff, model.right_panel_tab);
}

test "handleNewSession copies selected Ask over lastAccessMode FullAccess" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/new-task-selected-ask", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    model.setLastProjectPath(project);
    model.setLastAccessMode("fullAccess");
    const started = model.addSession("started", .fx);
    if (model.sessionById(started)) |session| {
        session.has_started = true;
        session.setAccessMode("ask");
    }
    model.selected = started;
    model.setLastAccessMode("fullAccess");
    const count = model.session_count;

    handleNewSession(&model, &fx);
    try std.testing.expectEqual(count + 1, model.session_count);
    try std.testing.expect(model.selected != started);
    try std.testing.expectEqualStrings("ask", model.sessionById(model.selected).?.accessMode());
}

test "handleNewSession copies selected FullAccess over lastAccessMode Ask" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/new-task-selected-full", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    model.setLastProjectPath(project);
    model.setLastAccessMode("ask");
    const started = model.addSession("started", .fx);
    if (model.sessionById(started)) |session| {
        session.has_started = true;
        session.setAccessMode("fullAccess");
    }
    model.selected = started;
    model.setLastAccessMode("ask");
    const count = model.session_count;

    handleNewSession(&model, &fx);
    try std.testing.expectEqual(count + 1, model.session_count);
    try std.testing.expect(model.selected != started);
    try std.testing.expectEqualStrings("fullAccess", model.sessionById(model.selected).?.accessMode());
}

test "handleNewSession falls back to lastAccessMode when no usable selected session" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/new-task-fallback-access", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    {
        var fx = Effects.init(std.testing.allocator);
        defer fx.deinit();
        fx.executor = .fake;
        var model = Model{};
        model.store_io = std.testing.io;
        model.setLastProjectPath(project);
        model.setLastAccessMode("ask");
        model.selected = 0;
        handleNewSession(&model, &fx);
        try std.testing.expectEqualStrings("ask", model.sessionById(model.selected).?.accessMode());
    }

    {
        var fx = Effects.init(std.testing.allocator);
        defer fx.deinit();
        fx.executor = .fake;
        var model = Model{};
        model.store_io = std.testing.io;
        model.setLastProjectPath(project);
        model.setLastAccessMode("ask");
        const started = model.addSession("started", .fx);
        if (model.sessionById(started)) |session| {
            session.has_started = true;
            session.setAccessMode("");
        }
        model.selected = started;
        model.setLastAccessMode("ask");
        handleNewSession(&model, &fx);
        try std.testing.expect(model.selected != started);
        try std.testing.expectEqualStrings("ask", model.sessionById(model.selected).?.accessMode());
    }

    {
        var fx = Effects.init(std.testing.allocator);
        defer fx.deinit();
        fx.executor = .fake;
        var model = Model{};
        model.store_io = std.testing.io;
        model.setLastProjectPath(project);
        model.selected = 0;
        handleNewSession(&model, &fx);
        try std.testing.expectEqualStrings("fullAccess", model.sessionById(model.selected).?.accessMode());
    }
}

test "handleNewSession reopening remembered draft does not overwrite access mode" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/remembered-keep-access", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    model.setLastProjectPath(project);
    handleNewSession(&model, &fx);
    const draft = model.selected;
    if (model.sessionById(draft)) |session| session.setAccessMode("ask");
    model.setLastAccessMode("fullAccess");
    const started = model.addSession("started", .fx);
    if (model.sessionById(started)) |session| session.has_started = true;
    handleSelect(&model, &fx, started);
    try std.testing.expectEqual(draft, model.new_task);
    const count = model.session_count;

    handleNewSession(&model, &fx);
    try std.testing.expectEqual(draft, model.selected);
    try std.testing.expectEqual(count, model.session_count);
    try std.testing.expectEqualStrings("ask", model.sessionById(draft).?.accessMode());
}

test "rememberedNewTask returns the current-project draft" {
    var model = Model{};
    const draft = model.addSession("untitled", .fx);
    if (model.sessionById(draft)) |session| {
        session.untitled = true;
        session.setProjectPath("/tmp/current");
    }
    model.new_task = draft;
    try std.testing.expectEqual(draft, model.rememberedNewTask("/tmp/current").?);
    try std.testing.expectEqual(draft, model.new_task);
}

test "rememberedNewTask skips another project without clearing" {
    var model = Model{};
    const draft = model.addSession("untitled", .fx);
    if (model.sessionById(draft)) |session| {
        session.untitled = true;
        session.setProjectPath("/tmp/a");
    }
    model.new_task = draft;
    try std.testing.expect(model.rememberedNewTask("/tmp/b") == null);
    try std.testing.expectEqual(draft, model.new_task);
}

test "rememberedNewTask clears a started draft" {
    var model = Model{};
    const draft = model.addSession("untitled", .fx);
    if (model.sessionById(draft)) |session| {
        session.setProjectPath("/tmp/a");
        session.has_started = true;
    }
    model.new_task = draft;
    try std.testing.expect(model.rememberedNewTask("/tmp/a") == null);
    try std.testing.expectEqual(@as(u32, 0), model.new_task);
}

test "handleNewSession reuses a remembered draft from the current project" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var a_buf: [256]u8 = undefined;
    const project_a = try std.fmt.bufPrint(&a_buf, ".zig-cache/tmp/{s}/remembered-current-a", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project_a);
    var b_buf: [256]u8 = undefined;
    const project_b = try std.fmt.bufPrint(&b_buf, ".zig-cache/tmp/{s}/remembered-current-b", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project_b);

    var model = Model{};
    model.store_io = std.testing.io;
    model.setLastProjectPath(project_a);
    handleNewSession(&model, &fx);
    const draft_a = model.selected;
    try std.testing.expectEqual(draft_a, model.new_task);
    const other = model.addSession("other project", .fx);
    if (model.sessionById(other)) |session| {
        session.setProjectPath(project_b);
        session.has_started = true;
    }
    const started = model.addSession("started same", .fx);
    if (model.sessionById(started)) |session| {
        session.setProjectPath(project_a);
        session.has_started = true;
    }
    handleSelect(&model, &fx, started);
    try std.testing.expectEqual(started, model.selected);
    try std.testing.expectEqual(draft_a, model.new_task);
    const count = model.session_count;

    handleNewSession(&model, &fx);
    try std.testing.expectEqual(draft_a, model.selected);
    try std.testing.expectEqual(count, model.session_count);
    try std.testing.expectEqual(draft_a, model.new_task);
}

test "handleNewSession does not reopen a remembered draft from another project" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var a_buf: [256]u8 = undefined;
    const project_a = try std.fmt.bufPrint(&a_buf, ".zig-cache/tmp/{s}/remembered-other-a", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project_a);
    var b_buf: [256]u8 = undefined;
    const project_b = try std.fmt.bufPrint(&b_buf, ".zig-cache/tmp/{s}/remembered-other-b", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project_b);

    var model = Model{};
    model.store_io = std.testing.io;
    model.setLastProjectPath(project_a);
    handleNewSession(&model, &fx);
    const draft_a = model.selected;
    try std.testing.expectEqual(draft_a, model.new_task);
    const started_b = model.addSession("started b", .fx);
    if (model.sessionById(started_b)) |session| {
        session.setProjectPath(project_b);
        session.has_started = true;
    }
    model.setLastProjectPath(project_b);
    handleSelect(&model, &fx, started_b);
    try std.testing.expectEqual(started_b, model.selected);
    try std.testing.expectEqual(draft_a, model.new_task);
    const count = model.session_count;

    handleNewSession(&model, &fx);
    try std.testing.expect(model.selected != draft_a);
    try std.testing.expectEqual(count + 1, model.session_count);
    try std.testing.expectEqual(draft_a, model.new_task);
    const created = model.sessionById(model.selected) orelse return error.MissingOrdinaryDraft;
    try std.testing.expect(created.untitled);
    try std.testing.expect(!created.hasStarted());
    try std.testing.expectEqualStrings(project_b, created.projectPath());
}

test "handleNewSession projectless ignores remembered and reuses a projectless draft" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/remembered-projectless-reuse", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    model.setHome("/home/me");
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    model.setLastProjectPath(project);
    handleNewSession(&model, &fx);
    const ordinary = model.selected;
    try std.testing.expectEqual(ordinary, model.new_task);
    const projectless_draft = model.addSession("untitled", .fx);
    if (model.sessionById(projectless_draft)) |session| {
        session.untitled = true;
        session.setProjectPath("/home/me/.waku/projects/2026-09-06/kept-draft");
    }
    model.setLastProjectPath("/home/me/.waku/projects/2026-09-06/new-chat");
    const count = model.session_count;

    handleNewSession(&model, &fx);
    try std.testing.expectEqual(projectless_draft, model.selected);
    try std.testing.expectEqual(count, model.session_count);
    try std.testing.expectEqual(projectless_draft, model.new_task);
    try std.testing.expectEqual(@as(u64, 0), model.daemon_projectless_key);
}

test "handleNewSession projectless ignores remembered and creates" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/remembered-projectless-create", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    model.setHome("/home/me");
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    model.setLastProjectPath(project);
    handleNewSession(&model, &fx);
    const ordinary = model.selected;
    try std.testing.expectEqual(ordinary, model.new_task);
    model.setLastProjectPath("/home/me/.waku/projects/2026-09-06/new-chat");
    const count = model.session_count;

    handleNewSession(&model, &fx);
    try std.testing.expect(model.selected != ordinary);
    try std.testing.expectEqual(count + 1, model.session_count);
    try std.testing.expectEqual(ordinary, model.new_task);
    const sidecar = pendingSpawnKey(&fx, model.daemon_projectless_key) orelse return error.MissingProjectlessCreateAfterRemembered;
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"createProjectlessWorkspace\"") != null);
}

test "handleSelect with a daemon address and legacy path issues migrateProjectlessWorkspace" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = std.testing.io;
    model.setHome("/home/me");
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    const first = model.addSession("first", .fx);
    model.selected = first;
    model.setLastProjectPath("/home/me/.waku/2026-09-06/legacy-chat");
    const legacy = model.addSession("legacy", .fx);

    handleSelect(&model, &fx, legacy);
    const sidecar = pendingSpawnKey(&fx, model.daemon_migrate_projectless_key) orelse return error.MissingHandleSelectMigrate;
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"migrateProjectlessWorkspace\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"path\":\"/home/me/.waku/2026-09-06/legacy-chat\"") != null);
    try std.testing.expectEqual(legacy, model.selected);
}

fn bindRemoveStore(model: *Model, tmp: *const std.testing.TmpDir, dir_buf: []u8, name: []const u8) !void {
    const dir = try std.fmt.bufPrint(dir_buf, ".zig-cache/tmp/{s}/{s}", .{ tmp.sub_path[0..], name });
    model.task_state_loaded = true;
    model.setStoreDir(dir);
    model.store_io = std.testing.io;
}

test "dropSession same-project newest wins over catalog order" {
    var model = Model{};
    const other = model.addSession("other project", .fx);
    const older = model.addSession("older same", .fx);
    const newer = model.addSession("newer same", .fx);
    if (model.sessionById(other)) |session| {
        session.setProjectPath("/tmp/other");
        session.updated_at = 30;
    }
    if (model.sessionById(older)) |session| {
        session.setProjectPath("/tmp/same");
        session.updated_at = 10;
    }
    if (model.sessionById(newer)) |session| {
        session.setProjectPath("/tmp/same");
        session.updated_at = 20;
    }
    model.selected = older;
    model.dropSession(older);
    try std.testing.expectEqual(newer, model.selected);
    try std.testing.expect(model.sessionById(older) == null);
    try std.testing.expect(model.sessionById(other) != null);
}

test "dropSession same-project tie-break prefers higher id" {
    var model = Model{};
    const first = model.addSession("first", .fx);
    const second = model.addSession("second", .fx);
    if (model.sessionById(first)) |session| {
        session.setProjectPath("/tmp/same");
        session.updated_at = 5;
    }
    if (model.sessionById(second)) |session| {
        session.setProjectPath("/tmp/same");
        session.updated_at = 5;
    }
    model.selected = first;
    model.dropSession(first);
    try std.testing.expectEqual(second, model.selected);
}

test "dropSession empty catalog selects 0" {
    var model = Model{};
    const only = model.addSession("only", .fx);
    model.selected = only;
    model.dropSession(only);
    try std.testing.expectEqual(@as(u32, 0), model.session_count);
    try std.testing.expectEqual(@as(u32, 0), model.selected);
}

test "handleRemoveSession same-project newest wins over catalog order" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    var model = Model{};
    try bindRemoveStore(&model, &tmp, &dir_buf, "remove-same-project");

    const other = model.addSession("other project", .fx);
    const older = model.addSession("older same", .fx);
    const newer = model.addSession("newer same", .fx);
    if (model.sessionById(other)) |session| {
        session.setProjectPath("/tmp/other");
        session.updated_at = 30;
        session.has_started = true;
    }
    if (model.sessionById(older)) |session| {
        session.setProjectPath("/tmp/same");
        session.updated_at = 10;
        session.has_started = true;
    }
    if (model.sessionById(newer)) |session| {
        session.setProjectPath("/tmp/same");
        session.updated_at = 20;
        session.has_started = true;
    }
    model.selected = older;
    handleRemoveSession(&model, &fx, older);
    try std.testing.expectEqual(newer, model.selected);
    try std.testing.expect(model.sessionById(older) == null);
    try std.testing.expect(model.sessionById(other) != null);
    try std.testing.expect(model.composer_active);
    try std.testing.expectEqual(newer, model.history_store[model.history_index]);
}

test "handleRemoveSession ordinary project with no siblings opens New Task draft" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    var model = Model{};
    try bindRemoveStore(&model, &tmp, &dir_buf, "remove-ordinary-new-task");

    const other = model.addSession("other project", .fx);
    const gone = model.addSession("last in project", .fx);
    if (model.sessionById(other)) |session| {
        session.setProjectPath("/tmp/other");
        session.has_started = true;
    }
    if (model.sessionById(gone)) |session| {
        session.setProjectPath("/tmp/proj");
        session.has_started = true;
    }
    model.selected = gone;
    const count = model.session_count;
    handleRemoveSession(&model, &fx, gone);
    try std.testing.expect(model.sessionById(gone) == null);
    try std.testing.expectEqual(count, model.session_count);
    try std.testing.expect(model.selected != other);
    const draft = model.sessionById(model.selected) orelse return error.MissingNewTaskDraft;
    try std.testing.expect(draft.untitled);
    try std.testing.expect(!draft.hasStarted());
    try std.testing.expectEqualStrings("/tmp/proj", draft.projectPath());
    try std.testing.expectEqual(model.selected, model.new_task);
}

test "handleRemoveSession projectless goes projectless not catalog first" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    var home_buf: [256]u8 = undefined;
    var model = Model{};
    try bindRemoveStore(&model, &tmp, &dir_buf, "remove-projectless");
    const home = try std.fmt.bufPrint(&home_buf, ".zig-cache/tmp/{s}/home", .{tmp.sub_path[0..]});
    model.setHome(home);
    model.now_ms = 1_750_000_000_000;

    var path_buf: [256]u8 = undefined;
    const projectless_path = try std.fmt.bufPrint(&path_buf, "{s}/.waku/projects/2026-09-06/new-chat", .{home});
    const ordinary = model.addSession("ordinary", .fx);
    const gone = model.addSession("projectless", .fx);
    if (model.sessionById(ordinary)) |session| {
        session.setProjectPath("/tmp/ordinary");
        session.has_started = true;
    }
    if (model.sessionById(gone)) |session| {
        session.setProjectPath(projectless_path);
        session.has_started = true;
    }
    model.setLastProjectPath(projectless_path);
    model.selected = gone;
    handleRemoveSession(&model, &fx, gone);
    try std.testing.expect(model.sessionById(gone) == null);
    try std.testing.expect(model.selected != ordinary);
    const dest = model.sessionById(model.selected) orelse return error.MissingProjectlessDestination;
    try std.testing.expect(dest.untitled);
    try std.testing.expect(!dest.hasStarted());
    try std.testing.expect(projectless.isProjectlessPath(home, dest.projectPath()));
}

test "handleRemoveSession reuses an unstarted projectless draft" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    var model = Model{};
    try bindRemoveStore(&model, &tmp, &dir_buf, "remove-projectless-reuse");
    model.setHome("/home/me");

    const ordinary = model.addSession("ordinary", .fx);
    const draft = model.addSession("untitled", .fx);
    const gone = model.addSession("started projectless", .fx);
    if (model.sessionById(ordinary)) |session| session.setProjectPath("/tmp/ordinary");
    if (model.sessionById(draft)) |session| {
        session.untitled = true;
        session.setProjectPath("/home/me/.waku/projects/2026-09-06/kept-draft");
    }
    if (model.sessionById(gone)) |session| {
        session.setProjectPath("/home/me/.waku/projects/2026-09-06/gone");
        session.has_started = true;
    }
    model.selected = gone;
    const count = model.session_count;
    handleRemoveSession(&model, &fx, gone);
    try std.testing.expectEqual(draft, model.selected);
    try std.testing.expectEqual(count - 1, model.session_count);
    try std.testing.expect(model.sessionById(ordinary) != null);
}

test "handleRemoveSession non-selected leaves selection" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    var model = Model{};
    try bindRemoveStore(&model, &tmp, &dir_buf, "remove-non-selected");

    const kept = model.addSession("kept", .fx);
    const gone = model.addSession("gone", .fx);
    if (model.sessionById(kept)) |session| session.setProjectPath("/tmp/a");
    if (model.sessionById(gone)) |session| session.setProjectPath("/tmp/b");
    model.selected = kept;
    handleRemoveSession(&model, &fx, gone);
    try std.testing.expectEqual(kept, model.selected);
    try std.testing.expect(model.sessionById(gone) == null);
}

test "handleRemoveSession last session selects 0" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    var model = Model{};
    try bindRemoveStore(&model, &tmp, &dir_buf, "remove-empty-catalog");

    const only = model.addSession("only", .fx);
    model.selected = only;
    handleRemoveSession(&model, &fx, only);
    try std.testing.expectEqual(@as(u32, 0), model.session_count);
    try std.testing.expectEqual(@as(u32, 0), model.selected);
}
