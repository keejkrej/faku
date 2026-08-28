//! Command-palette runners and session-selection helpers.
//!
//! `openPalette` / `clampPaletteHighlight` / `runPaletteAction` /
//! `runPalettePick` / `confirmPalette` / `applySessionSelection` /
//! `goHistory` live here. Palette row building stays in `palette.zig`.
//! Msg routing and Model fields stay in `main.zig`. Behavior is
//! unchanged from the former `main` palette runners.

const main = @import("main.zig");
const palette = @import("palette.zig");
const store = @import("store.zig");
const attach_helpers = @import("attach.zig");
const session_switcher = @import("switcher.zig");
const git_branch = @import("git_branch.zig");
const git_dirty = @import("git_dirty.zig");
const git_numstat = @import("git_numstat.zig");
const file_mention = @import("file_mention.zig");

const Model = main.Model;
const Effects = main.Effects;
const PaletteAction = main.PaletteAction;
const palette_action_id_base = main.palette_action_id_base;
const palette_header_id_base = main.palette_header_id_base;

pub fn openPalette(model: *Model) void {
    session_switcher.closeSwitcher(model);
    model.closeModelPicker();
    model.palette_open = true;
    model.search_buffer.clear();
    model.palette_highlight = 0;
    model.composer_active = false;
}

pub fn clampPaletteHighlight(model: *Model) void {
    palette.clampHighlight(model);
}

fn runPaletteAction(model: *Model, fx: *Effects, action: PaletteAction) void {
    switch (action) {
        .new_task => main.update(model, .new_session, fx),
        .focus_composer => main.update(model, .focus_composer, fx),
        .toggle_sidebar => main.update(model, .toggle_sidebar, fx),
        .collapse_folders => main.update(model, .collapse_all_folders, fx),
        .find_in_transcript => main.update(model, .open_find, fx),
        .settings => main.update(model, .toggle_settings, fx),
        .minimize => main.update(model, .minimize_window, fx),
        .maximize => main.update(model, .maximize_window, fx),
        .copy_session_id => main.update(model, .copy_session_id, fx),
        .copy_fx_session_id => main.update(model, .copy_fx_session_id, fx),
        .reveal_folder => main.update(model, .reveal_folder, fx),
        .open_terminal => main.update(model, .open_terminal, fx),
        .open_editor => main.update(model, .open_editor, fx),
        .copy_project_path => main.update(model, .copy_project_path, fx),
    }
}

pub fn runPalettePick(model: *Model, fx: *Effects, id: u32) void {
    if (!model.palette_open or id == 0) return;
    if (id >= palette_header_id_base) return;
    if (id >= palette_action_id_base) {
        const action = palette.paletteActionFromId(id) orelse return;
        if (action == .collapse_folders and !model.can_collapse_folders()) return;
        model.closePalette();
        runPaletteAction(model, fx, action);
        return;
    }
    if (model.sessionByIdConst(id) == null) return;
    model.closePalette();
    model.pushSelectionHistory(id);
    applySessionSelection(model, fx, id);
}

pub fn confirmPalette(model: *Model, fx: *Effects) void {
    if (!model.palette_open) return;
    clampPaletteHighlight(model);
    const id = palette.selectableIdAt(model, model.palette_highlight) orelse return;
    runPalettePick(model, fx, id);
}

pub fn applySessionSelection(model: *Model, fx: *Effects, id: u32) void {
    if (model.sessionById(id) == null) return;
    store.persistDraftIfPossible(model);
    model.closeProjectEdit();
    model.closeImageAttach();
    model.closeCommands();
    model.closeModelPicker();
    model.closeFolderTitleEdit();
    model.closeSessionTitleEdit();
    model.selected = id;
    store.hydrateIfPossible(model, id);
    store.maybeHydrateDaemonSession(model, fx, id);
    store.loadDraftIfPossible(model);
    attach_helpers.refreshAttachPreview(model, fx);
    git_branch.refresh(model, fx);
    git_dirty.refresh(model, fx);
    git_numstat.refresh(model, fx);
    file_mention.refresh(model, fx);
    model.pinTranscriptToLatest();
    model.composer_active = true;
}

pub fn goHistory(step: i32, model: *Model, fx: *Effects) void {
    if (step == 0 or model.history_count == 0) return;
    var i: i32 = @intCast(model.history_index);
    const last: i32 = @intCast(model.history_count - 1);
    while (true) {
        i += step;
        if (i < 0 or i > last) return;
        const id = model.history_store[@intCast(i)];
        if (model.sessionById(id) == null) continue;
        model.history_index = @intCast(i);
        applySessionSelection(model, fx, id);
        return;
    }
}
