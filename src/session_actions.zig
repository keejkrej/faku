//! Session / folder / title-edit update helpers.
//!
//! `handleNewSession` / `handleSelect` / folder + title edits /
//! `handleRemoveSession` / `handleEditQueued` live here.
//! Msg routing stays in `update.zig`. When New Task would be
//! projectless, an existing unstarted non-legacy projectless draft
//! is selected (Waku `create_projectless_session`; same select
//! effects as clicking that session) instead of `addSession`.
//! First-cut daemon
//! `WorkspaceOperation::CreateProjectlessWorkspace` prefers hello +
//! createProjectlessWorkspace on actual create when there is no
//! ordinary project (empty `last_project_path`, or the selected
//! session is already projectless under `~/.waku/projects`); Native
//! 4 KiB stdin overflow / sidecar miss fall back to local mkdir.
//! Ordinary New Task with a real project path still copies
//! `last_project_path`.
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
const session_fork = @import("fork.zig");
const pick_folder = @import("pick_folder.zig");

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
    }
    right_panel_session.take(model);
    store.persistDraftIfPossible(model);
    environment_summary.close(model);
    review_diff.close(model, fx);
    file_preview_images.drop(model, fx);
    file_preview_details.drop(model);
    file_preview_issue_link.drop(model, fx);
    transcript_images.drop(model, fx);
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
    right_panel.clearFilePreview(model);
    environment_summary.clearSettledIfSession(model, id);
    store.cancelDaemonDeleteSessionRefs(model, fx);
    store.removeIfPossible(model, id, fx);
    store.loadDraftIfPossible(model);
    attach_helpers.refreshAttachPreview(model, fx);
    git_branch.refresh(model, fx);
    git_dirty.refresh(model, fx);
    git_numstat.refresh(model, fx);
    file_mention.refresh(model, fx);
    right_panel_session.restore(model, fx);
    git_checkout.refresh(model, fx);
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
