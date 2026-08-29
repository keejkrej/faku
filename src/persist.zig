//! Folder and composer-chip persist wrappers.
//!
//! `persistAssignedFolder` / `persistDeletedFolder` /
//! `persistComposerChips` / `persistComposerProject` live here.
//! Disk IO stays in `store.zig`. Msg routing stays in `main.update`.
//! Behavior is unchanged from the former `main` persist helpers.

const main = @import("main.zig");
const store = @import("store.zig");
const git_branch = @import("git_branch.zig");
const git_checkout = @import("git_checkout.zig");
const git_dirty = @import("git_dirty.zig");
const git_numstat = @import("git_numstat.zig");
const git_ahead_behind = @import("git_ahead_behind.zig");
const git_remotes = @import("git_remotes.zig");
const git_toplevel = @import("git_toplevel.zig");
const git_common_dir = @import("git_common_dir.zig");
const file_mention = @import("file_mention.zig");

const Model = main.Model;
const Effects = main.Effects;
const max_sessions = main.max_sessions;

pub fn persistAssignedFolder(model: *Model, session_id: u32, folder_id: u32, fx: *Effects) void {
    if (!model.assignSessionFolder(session_id, folder_id)) return;
    store.persistFoldersIfPossible(model);
    if (model.sessionByIdConst(session_id)) |session| {
        if (session.hasStarted()) store.persistIfPossible(model, session_id, fx);
    }
}

pub fn persistDeletedFolder(model: *Model, folder_id: u32, fx: *Effects) void {
    if (model.folderById(folder_id) == null) return;
    var started: [max_sessions]u32 = undefined;
    var started_n: usize = 0;
    for (model.session_store[0..model.session_count]) |session| {
        if (session.folder_id != folder_id or !session.hasStarted()) continue;
        started[started_n] = session.id;
        started_n += 1;
    }
    if (!model.deleteFolder(folder_id)) return;
    store.persistFoldersIfPossible(model);
    for (started[0..started_n]) |session_id| {
        store.persistIfPossible(model, session_id, fx);
    }
}

pub fn persistComposerChips(model: *Model, fx: *Effects) void {
    store.persistSettingsIfPossible(model);
    store.persistIfPossible(model, model.selected, fx);
}

pub fn persistComposerProject(model: *Model, fx: *Effects) void {
    store.persistSettingsIfPossible(model);
    store.persistIfPossible(model, model.selected, fx);
    git_branch.refresh(model, fx);
    git_dirty.refresh(model, fx);
    git_numstat.refresh(model, fx);
    git_ahead_behind.refresh(model, fx);
    git_remotes.refresh(model, fx);
    git_toplevel.refresh(model, fx);
    git_common_dir.refresh(model, fx);
    file_mention.refresh(model, fx);
    git_checkout.refresh(model, fx);
}
