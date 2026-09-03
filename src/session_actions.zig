//! Session / folder / title-edit update helpers.
//!
//! `handleNewSession` / `handleSelect` / folder + title edits /
//! `handleRemoveSession` / `handleEditQueued` live here.
//! Msg routing stays in `update.zig`. Behavior is unchanged
//! from the former `main` update arms.

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
const sidebar_row_helpers = @import("sidebar_rows.zig");
const palette_run = @import("palette_run.zig");
const environment_summary = @import("environment_summary.zig");
const review_diff = @import("review_diff.zig");
const right_panel = @import("right_panel.zig");

const Model = main.Model;
const Effects = main.Effects;
const max_title = main.max_title;
const max_queued_text = main.max_queued_text;
const canvas = native_sdk.canvas;

pub fn handleNewSession(model: *Model, fx: *Effects) void {
    store.persistDraftIfPossible(model);
    environment_summary.close(model);
    review_diff.close(model, fx);
    right_panel.clearFilePreview(model);
    model.closeProjectEdit();
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
    attach_helpers.refreshAttachPreview(model, fx);
    git_branch.refresh(model, fx);
    git_dirty.refresh(model, fx);
    git_numstat.refresh(model, fx);
    file_mention.refresh(model, fx);
    git_checkout.refresh(model, fx);
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
    if (model.editing_session_id == id) model.closeSessionTitleEdit();
    model.closeCommands();
    right_panel.clearFilePreview(model);
    environment_summary.clearSettledIfSession(model, id);
    store.removeIfPossible(model, id, fx);
    store.loadDraftIfPossible(model);
    attach_helpers.refreshAttachPreview(model, fx);
    git_branch.refresh(model, fx);
    git_dirty.refresh(model, fx);
    git_numstat.refresh(model, fx);
    file_mention.refresh(model, fx);
    git_checkout.refresh(model, fx);
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
