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
const git_checkout = @import("git_checkout.zig");
const git_commit = @import("git_commit.zig");
const environment_summary = @import("environment_summary.zig");
const review_diff = @import("review_diff.zig");
const skills = @import("skills.zig");
const providers = @import("providers.zig");

const Model = main.Model;
const Effects = main.Effects;
const canvas = native_sdk.canvas;

pub fn handleStop(model: *Model, fx: *Effects) void {
    if (model.switcher_open) {
        session_switcher.closeSwitcher(model);
        return;
    }
    if (model.environment_summary_open) {
        environment_summary.close(model);
        return;
    }
    if (model.git_branch_picker_open) {
        model.closeGitBranchPicker();
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
        skills.close(model, fx);
        providers.close(model);
        model.closeSettings();
        return;
    }
    if (model.project_edit_active) {
        model.closeProjectEdit();
        return;
    }
    if (model.git_branch_delete_picker_open) {
        git_checkout.closeDeletePicker(model);
        return;
    }
    if (model.git_branch_create_active) {
        git_checkout.closeCreate(model);
        return;
    }
    if (model.git_worktree_create_active) {
        git_checkout.dismissWorktreeCreate(model, fx);
        return;
    }
    if (model.git_commit_active) {
        git_commit.dismissCommit(model, fx);
        return;
    }
    if (model.review_diff_active) {
        review_diff.dismiss(model, fx);
        return;
    }
    if (model.git_branch_delete_active) {
        git_checkout.closeDelete(model);
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
    if (model.mentions_list_open() or model.skills_list_open() or model.slashPrefixCommandsShowing()) {
        model.autocomplete_dismissed = true;
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
        model.git_branch_picker_open = false;
    }
    model.toggleGoalStatusPicker();
}

pub fn handleToggleSettings(model: *Model, fx: *Effects) void {
    if (model.settings_open) {
        skills.close(model, fx);
        providers.close(model);
        model.closeSettings();
        return;
    }
    review_diff.close(model, fx);
    model.openSettings();
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

pub fn handleSetSettingsPageGeneral(model: *Model) void {
    model.settings_page = .general;
}

pub fn handleSetSettingsPageProviders(model: *Model, fx: *Effects) void {
    model.settings_page = .providers;
    providers.startProbes(model, fx);
}

pub fn handleSetSettingsPageSkills(model: *Model, fx: *Effects) void {
    model.settings_page = .skills;
    skills.refresh(model, fx);
}

pub fn handleRefreshSkills(model: *Model, fx: *Effects) void {
    if (model.settings_page != .skills) return;
    skills.refresh(model, fx);
}

pub fn handleRefreshProviders(model: *Model, fx: *Effects) void {
    if (model.settings_page != .providers) return;
    providers.refresh(model, fx);
}

pub fn handleSelectProvider(model: *Model, id: u32) void {
    providers.selectProvider(model, id);
}

pub fn handleApplySessionProvider(model: *Model, fx: *Effects) void {
    if (!providers.applyToSession(model)) return;
    store.persistIfPossible(model, model.selected, fx);
}

pub fn handleCopyFxInstall(model: *Model, fx: *Effects) void {
    providers.copyFxInstall(model, fx);
}

pub fn handleCopyFxLogin(model: *Model, fx: *Effects) void {
    providers.copyFxLogin(model, fx);
}

pub fn handleSkillsFilterEdit(model: *Model, edit: canvas.TextInputEvent) void {
    model.applySkillsFilter(edit);
}

pub fn handleSelectSkill(model: *Model, id: u32) void {
    skills.selectSkill(model, id);
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
        model.git_branch_picker_open = false;
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
        model.git_branch_picker_open = false;
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
        model.git_branch_picker_open = false;
    }
    model.toggleEffortPicker();
}

pub fn handleToggleGitBranchPicker(model: *Model) void {
    if (!model.git_branch_picker_open) {
        session_switcher.closeSwitcher(model);
        if (model.palette_open) model.closePalette();
        model.model_picker_open = false;
        model.access_picker_open = false;
        model.effort_picker_open = false;
        model.settings_effort_picker_open = false;
        model.goal_status_picker_open = false;
        git_checkout.closeDelete(model);
    }
    model.toggleGitBranchPicker();
}

pub fn handlePickGitBranch(model: *Model, fx: *Effects, name: []const u8) void {
    git_checkout.pickBranch(model, fx, name);
}

pub fn handleStartGitBranchCreate(model: *Model, fx: *Effects) void {
    git_commit.dropCommitNumstat(model, fx);
    git_checkout.startCreate(model);
}

pub fn handleGitBranchCreateEdit(model: *Model, edit: canvas.TextInputEvent) void {
    model.git_branch_create_buffer.apply(edit);
}

pub fn handleConfirmGitBranchCreate(model: *Model, fx: *Effects) void {
    git_checkout.confirmCreate(model, fx);
}

pub fn handleCancelGitBranchCreate(model: *Model) void {
    git_checkout.closeCreate(model);
}

pub fn handleStartGitBranchDelete(model: *Model, fx: *Effects) void {
    git_commit.dropCommitNumstat(model, fx);
    git_checkout.startDelete(model);
}

pub fn handleToggleGitBranchDeletePicker(model: *Model) void {
    git_checkout.toggleDeletePicker(model);
}

pub fn handlePickGitBranchDelete(model: *Model, name: []const u8) void {
    git_checkout.pickDeleteName(model, name);
}

pub fn handleConfirmGitBranchDelete(model: *Model, fx: *Effects) void {
    git_checkout.confirmDelete(model, fx);
}

pub fn handleCancelGitBranchDelete(model: *Model) void {
    git_checkout.closeDelete(model);
}

pub fn handleToggleGitBranchDeleteForce(model: *Model, fx: *Effects) void {
    git_checkout.toggleDeleteForce(model, fx);
}

pub fn handleStartGitFetch(model: *Model, fx: *Effects) void {
    git_checkout.startFetch(model, fx);
}

pub fn handleStartGitPush(model: *Model, fx: *Effects) void {
    git_checkout.startPush(model, fx);
}

pub fn handleStartGitWorktreeCreate(model: *Model, fx: *Effects) void {
    git_commit.dropCommitNumstat(model, fx);
    git_checkout.startWorktreeCreate(model);
}

pub fn handleGitWorktreeCreateEdit(model: *Model, edit: canvas.TextInputEvent) void {
    model.git_worktree_create_buffer.apply(edit);
}

pub fn handleConfirmGitWorktreeCreate(model: *Model, fx: *Effects) void {
    git_checkout.confirmWorktreeAdd(model, fx);
}

pub fn handleCancelGitWorktreeCreate(model: *Model, fx: *Effects) void {
    git_checkout.dismissWorktreeCreate(model, fx);
}

pub fn handleStartGitCommit(model: *Model, fx: *Effects) void {
    git_commit.startCommit(model, fx);
}

pub fn handleGitCommitEdit(model: *Model, edit: canvas.TextInputEvent) void {
    git_commit.applyCommitEdit(model, edit);
}

pub fn handleConfirmGitCommit(model: *Model, fx: *Effects) void {
    git_commit.confirmCommit(model, fx);
}

pub fn handleConfirmGitCommitAndPush(model: *Model, fx: *Effects) void {
    git_commit.confirmCommitAndPush(model, fx);
}

pub fn handleConfirmGitCommitPush(model: *Model, fx: *Effects) void {
    git_commit.confirmPushOnly(model, fx);
}

pub fn handleCancelGitCommit(model: *Model, fx: *Effects) void {
    git_commit.dismissCommit(model, fx);
}

pub fn handleToggleGitCommitIncludeUnstaged(model: *Model, fx: *Effects) void {
    git_commit.toggleIncludeUnstaged(model, fx);
}

pub fn handleToggleGitCommitAmend(model: *Model, fx: *Effects) void {
    git_commit.toggleAmend(model, fx);
}

pub fn handlePickEffort(model: *Model, fx: *Effects, id: []const u8) void {
    model.pickSelectedEffort(id);
    persist.persistComposerChips(model, fx);
}
