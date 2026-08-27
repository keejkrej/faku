//! Settings / Esc-stop / composer-picker update helpers.
//!
//! `handleStop` / `handleToggleGoalStatusPicker` / settings panel /
//! composer chip cycles + pickers live here.
//! Msg routing stays in `main.update`. Behavior is unchanged
//! from the former `main` update arms.

const native_sdk = @import("native_sdk");
const main = @import("main.zig");
const store = @import("store.zig");
const persist = @import("persist.zig");
const session_switcher = @import("switcher.zig");
const turn_stream = @import("stream.zig");

const Model = main.Model;
const Effects = main.Effects;
const canvas = native_sdk.canvas;

pub fn handleStop(model: *Model, fx: *Effects) void {
    if (model.switcher_open) {
        session_switcher.closeSwitcher(model);
        return;
    }
    if (model.access_picker_open) {
        model.closeAccessPicker();
        return;
    }
    if (model.effort_picker_open) {
        model.closeEffortPicker();
        return;
    }
    if (model.settings_effort_picker_open) {
        model.closeSettingsEffortPicker();
        return;
    }
    if (model.goal_status_picker_open) {
        model.closeGoalStatusPicker();
        return;
    }
    if (model.model_picker_open) {
        model.closeModelPicker();
        return;
    }
    if (model.palette_open) {
        model.closePalette();
        return;
    }
    if (model.settings_open) {
        model.closeSettings();
        return;
    }
    if (model.project_edit_active) {
        model.closeProjectEdit();
        return;
    }
    if (model.image_attach_active) {
        model.closeImageAttach();
        return;
    }
    if (model.commands_open) {
        model.closeCommands();
        return;
    }
    if (model.editing_folder_id != 0) {
        model.closeFolderTitleEdit();
        return;
    }
    if (model.editing_session_id != 0) {
        model.closeSessionTitleEdit();
        return;
    }
    if (model.find_active or model.find_query().len > 0) {
        model.exitFind();
        return;
    }
    turn_stream.stopStream(model, fx);
}

pub fn handleToggleGoalStatusPicker(model: *Model) void {
    if (!model.goal_status_picker_open) {
        session_switcher.closeSwitcher(model);
        if (model.palette_open) model.closePalette();
        model.model_picker_open = false;
        model.access_picker_open = false;
        model.effort_picker_open = false;
        model.settings_effort_picker_open = false;
    }
    model.toggleGoalStatusPicker();
}

pub fn handleToggleSettings(model: *Model) void {
    model.toggleSettings();
}

pub fn handleSettingsModelEdit(model: *Model, edit: canvas.TextInputEvent) void {
    model.applySettingsModel(edit);
    store.persistSettingsIfPossible(model);
}

pub fn handleSettingsProjectEdit(model: *Model, edit: canvas.TextInputEvent) void {
    model.applySettingsProject(edit);
    store.persistSettingsIfPossible(model);
}

pub fn handleSettingsDaemonEdit(model: *Model, edit: canvas.TextInputEvent) void {
    model.applySettingsDaemon(edit);
    store.persistSettingsIfPossible(model);
}

pub fn handleSettingsAccessAsk(model: *Model) void {
    model.setSettingsAccess("ask");
    store.persistSettingsIfPossible(model);
}

pub fn handleSettingsAccessAuto(model: *Model) void {
    model.setSettingsAccess("auto");
    store.persistSettingsIfPossible(model);
}

pub fn handleSettingsAccessFull(model: *Model) void {
    model.setSettingsAccess("fullAccess");
    store.persistSettingsIfPossible(model);
}

pub fn handleSettingsInteractionBuild(model: *Model) void {
    model.setSettingsInteraction("build");
    store.persistSettingsIfPossible(model);
}

pub fn handleSettingsInteractionPlan(model: *Model) void {
    model.setSettingsInteraction("plan");
    store.persistSettingsIfPossible(model);
}

pub fn handleToggleSettingsEffortPicker(model: *Model) void {
    if (!model.settings_effort_picker_open) {
        session_switcher.closeSwitcher(model);
        if (model.palette_open) model.closePalette();
        model.closeComposerPickers();
    }
    model.toggleSettingsEffortPicker();
}

pub fn handlePickSettingsEffort(model: *Model, id: []const u8) void {
    model.pickSettingsEffort(id);
    store.persistSettingsIfPossible(model);
}

pub fn handleCycleAccess(model: *Model, fx: *Effects) void {
    model.cycleSelectedAccess();
    persist.persistComposerChips(model, fx);
}

pub fn handleCycleInteraction(model: *Model, fx: *Effects) void {
    model.cycleSelectedInteraction();
    persist.persistComposerChips(model, fx);
}

pub fn handleCycleEffort(model: *Model, fx: *Effects) void {
    model.cycleSelectedEffort();
    persist.persistComposerChips(model, fx);
}

pub fn handleToggleModelPicker(model: *Model) void {
    if (!model.model_picker_open) {
        session_switcher.closeSwitcher(model);
        if (model.palette_open) model.closePalette();
        model.access_picker_open = false;
        model.effort_picker_open = false;
        model.settings_effort_picker_open = false;
        model.goal_status_picker_open = false;
    }
    model.toggleModelPicker();
}

pub fn handlePickModel(model: *Model, fx: *Effects, id: []const u8) void {
    model.pickSelectedModel(id);
    persist.persistComposerChips(model, fx);
}

pub fn handleToggleAccessPicker(model: *Model) void {
    if (!model.access_picker_open) {
        session_switcher.closeSwitcher(model);
        if (model.palette_open) model.closePalette();
        model.model_picker_open = false;
        model.effort_picker_open = false;
        model.settings_effort_picker_open = false;
        model.goal_status_picker_open = false;
    }
    model.toggleAccessPicker();
}

pub fn handlePickAccess(model: *Model, fx: *Effects, id: []const u8) void {
    model.pickSelectedAccess(id);
    persist.persistComposerChips(model, fx);
}

pub fn handleToggleEffortPicker(model: *Model) void {
    if (!model.effort_picker_open) {
        session_switcher.closeSwitcher(model);
        if (model.palette_open) model.closePalette();
        model.model_picker_open = false;
        model.access_picker_open = false;
        model.settings_effort_picker_open = false;
        model.goal_status_picker_open = false;
    }
    model.toggleEffortPicker();
}

pub fn handlePickEffort(model: *Model, fx: *Effects, id: []const u8) void {
    model.pickSelectedEffort(id);
    persist.persistComposerChips(model, fx);
}
