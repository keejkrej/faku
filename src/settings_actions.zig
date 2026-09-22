//! Settings / Esc-stop / composer-picker update helpers.
//!
//! `handleStop` / `handleCloseSettings` / `handleToggleSettings` /
//! `handleToggleGoalStatusPicker` / settings panel / composer chip
//! cycles + pickers live here, including Settings nav Up/Down
//! (`cycle_settings_page_*` → the same set-page handlers clicks use).
//! Msg routing stays in `update.zig`. Behavior is unchanged
//! from the former `main` update arms except Settings Back
//! (`close_settings` → `handleCloseSettings` → `closeSettings`).

const std = @import("std");
const native_sdk = @import("native_sdk");
const main = @import("main.zig");
const model_exports = @import("model_exports.zig");
const store = @import("store.zig");
const persist = @import("persist.zig");
const session_switcher = @import("switcher.zig");
const turn_stream = @import("stream.zig");
const git_checkout = @import("git_checkout.zig");
const git_commit = @import("git_commit.zig");
const session_workspace = @import("session_workspace.zig");
const environment_summary = @import("environment_summary.zig");
const review_diff = @import("review_diff.zig");
const skills = @import("skills.zig");
const providers = @import("providers.zig");
const slash_commands = @import("slash_commands.zig");
const pick_folder = @import("pick_folder.zig");
const usage_history = @import("usage_history.zig");
const usage_meter = @import("usage_meter.zig");
const copy = @import("copy.zig");
const litellm_rates = @import("litellm_rates.zig");
const right_panel = @import("right_panel.zig");
const browser_pane = @import("browser_pane.zig");

const Model = model_exports.Model;
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
    if (model.daemon_dir_browser_open) {
        pick_folder.closeDaemonBrowser(model, fx);
        return;
    }
    if (model.workspace_picker_open) {
        model.closeWorkspacePicker();
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
    if (model.skills_source_picker_open) {
        model.closeSkillsSourcePicker();
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
        handleCloseSettings(model, fx);
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
    if (model.git_worktree_base_picker_open) {
        git_checkout.closeWorktreeBasePicker(model);
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
    if (model.git_push_confirm_active) {
        git_checkout.cancelPushConfirm(model);
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
    // Waku BrowserAddressCancel: Escape restores the address draft
    // when that field is active. Stay on `.stop` in keys.zig; gate
    // here like other Browser-tab chords. First-cut Stop loading
    // (address not focused) is next: loading-guess + previous URL /
    // blank, not a Native stop callback.
    if (model.browser_address_active and model.browser_keyboard_active()) {
        browser_pane.restoreAddressFromCommitted(model);
        model.browser_address_active = false;
        store.persistLayoutIfPossible(model);
        return;
    }
    if (model.browser_keyboard_active() and browser_pane.loadingGuessActive(model)) {
        browser_pane.stopLoading(model);
        store.persistLayoutIfPossible(model);
        return;
    }
    if (model.find_active or model.find_query().len > 0) {
        model.exitFind();
        return;
    }
    if (right_panel.filePreviewFindActive(model) or model.file_preview_find_active) {
        right_panel.closeFilePreviewFind(model);
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
        model.closeSkillsSourcePicker();
        model.closeGitBranchPicker();
    }
    model.toggleGoalStatusPicker();
}

pub fn handleCloseSettings(model: *Model, fx: *Effects) void {
    if (!model.settings_open) return;
    skills.close(model, fx);
    providers.close(model, fx);
    usage_history.cancel(model, fx);
    litellm_rates.cancel(model, fx);
    model.closeSettings();
}

pub fn handleToggleSettings(model: *Model, fx: *Effects) void {
    if (model.settings_open) {
        handleCloseSettings(model, fx);
        return;
    }
    review_diff.close(model, fx);
    pick_folder.closeDaemonBrowser(model, fx);
    usage_meter.close(model);
    model.openSettings();
    store.persistSettingsIfPossible(model);
    resumeSettingsPage(model, fx);
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

pub fn handleDaemonDisconnect(model: *Model) void {
    model.disconnectSettingsDaemon();
}

pub fn handleDaemonForget(model: *Model) void {
    model.forgetSettingsDaemon();
    store.persistSettingsIfPossible(model);
}

pub fn handleDaemonReconnect(model: *Model) void {
    model.reconnectSettingsDaemon();
}

pub fn handleDaemonCopyUrl(model: *Model, fx: *Effects) void {
    if (!model.daemon_settings_show_copy()) return;
    copy.copyText(fx, model.lastDaemonAddress());
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
        model.closeSkillsSourcePicker();
    }
    model.toggleSettingsEffortPicker();
}

pub fn handlePickSettingsEffort(model: *Model, id: []const u8) void {
    model.pickSettingsEffort(id);
    store.persistSettingsIfPossible(model);
}

pub fn handleToggleSkillsSourcePicker(model: *Model) void {
    if (model.settings_page != .skills) return;
    if (!model.skills_source_picker_open) {
        session_switcher.closeSwitcher(model);
        if (model.palette_open) model.closePalette();
        model.closeComposerPickers();
        model.closeSettingsEffortPicker();
    }
    model.toggleSkillsSourcePicker();
}

pub fn handlePickSkillsSource(model: *Model, id: []const u8) void {
    if (model.settings_page != .skills) return;
    model.pickSkillsSource(id);
}

pub fn handleSetSettingsPageGeneral(model: *Model, fx: *Effects) void {
    handleSetSettingsPage(model, fx, .general);
}

pub fn handleSetSettingsPageAppearance(model: *Model, fx: *Effects) void {
    handleSetSettingsPage(model, fx, .appearance);
}

pub fn handleSetSettingsPageProviders(model: *Model, fx: *Effects) void {
    handleSetSettingsPage(model, fx, .providers);
}

pub fn handleSetSettingsPageSkills(model: *Model, fx: *Effects) void {
    handleSetSettingsPage(model, fx, .skills);
}

pub fn handleSetSettingsPageUsage(model: *Model, fx: *Effects) void {
    handleSetSettingsPage(model, fx, .usage);
}

pub fn handleSetUsageViewDaily(model: *Model, fx: *Effects) void {
    if (model.settings_page != .usage) return;
    usage_history.setView(model, fx, .daily);
    store.persistSettingsIfPossible(model);
}

pub fn handleSetUsageViewMonthly(model: *Model, fx: *Effects) void {
    if (model.settings_page != .usage) return;
    usage_history.setView(model, fx, .monthly);
    store.persistSettingsIfPossible(model);
}

pub fn handleSetUsageViewProjects(model: *Model, fx: *Effects) void {
    if (model.settings_page != .usage) return;
    usage_history.setView(model, fx, .projects);
    store.persistSettingsIfPossible(model);
}

pub fn handleSetUsageWindow7d(model: *Model, fx: *Effects) void {
    if (model.settings_page != .usage) return;
    usage_history.setWindow(model, fx, .trailing_7);
    store.persistSettingsIfPossible(model);
}

pub fn handleSetUsageWindow30d(model: *Model, fx: *Effects) void {
    if (model.settings_page != .usage) return;
    usage_history.setWindow(model, fx, .trailing_30);
    store.persistSettingsIfPossible(model);
}

pub fn handleSetUsageWindow90d(model: *Model, fx: *Effects) void {
    if (model.settings_page != .usage) return;
    usage_history.setWindow(model, fx, .trailing_90);
    store.persistSettingsIfPossible(model);
}

pub fn handleSetUsageWindowThisMonth(model: *Model, fx: *Effects) void {
    if (model.settings_page != .usage) return;
    usage_history.setWindow(model, fx, .this_month);
    store.persistSettingsIfPossible(model);
}

pub fn handleSetUsageWindowLastMonth(model: *Model, fx: *Effects) void {
    if (model.settings_page != .usage) return;
    usage_history.setWindow(model, fx, .last_month);
    store.persistSettingsIfPossible(model);
}

pub fn handleSetUsageShareCost(model: *Model) void {
    if (model.settings_page != .usage) return;
    usage_history.setShareMetric(model, .cost);
    store.persistSettingsIfPossible(model);
}

pub fn handleSetUsageShareTokens(model: *Model) void {
    if (model.settings_page != .usage) return;
    usage_history.setShareMetric(model, .tokens);
    store.persistSettingsIfPossible(model);
}

pub fn handleSetUsageBreakdownModel(model: *Model) void {
    if (model.settings_page != .usage) return;
    usage_history.setBreakdown(model, .model);
    store.persistSettingsIfPossible(model);
}

pub fn handleSetUsageBreakdownDays(model: *Model) void {
    if (model.settings_page != .usage) return;
    usage_history.setBreakdown(model, .days);
    store.persistSettingsIfPossible(model);
}

pub fn handleRefreshUsageHistory(model: *Model, fx: *Effects) void {
    if (model.settings_page != .usage) return;
    usage_history.refresh(model, fx);
    litellm_rates.ensure(model, fx);
}

pub fn handleToggleUsageMeter(model: *Model, fx: *Effects) void {
    if (!usage_meter.available(model) or model.settings_open) return;
    if (!model.usage_meter_open) {
        session_switcher.closeSwitcher(model);
        if (model.palette_open) model.closePalette();
        model.model_picker_open = false;
        model.access_picker_open = false;
        model.effort_picker_open = false;
        model.settings_effort_picker_open = false;
        model.closeSkillsSourcePicker();
        model.goal_status_picker_open = false;
        model.closeGitBranchPicker();
        model.workspace_picker_open = false;
        model.environment_summary_open = false;
    }
    usage_meter.toggle(model, fx);
    store.persistSettingsIfPossible(model);
}

pub fn handleCloseUsageMeter(model: *Model) void {
    usage_meter.close(model);
    store.persistSettingsIfPossible(model);
}

pub fn handleRefreshPlanUsage(model: *Model, fx: *Effects) void {
    if (!model.usage_meter_open) return;
    usage_meter.refresh(model, fx);
}

pub fn handleUsageProjectFilterEdit(model: *Model, edit: canvas.TextInputEvent) void {
    if (model.settings_page != .usage or model.usage_view != .projects) return;
    usage_history.applyProjectFilter(model, edit);
    store.persistSettingsIfPossible(model);
}

pub fn handleSetSettingsPageDaemon(model: *Model, fx: *Effects) void {
    handleSetSettingsPage(model, fx, .daemon);
}

pub fn handleSetSettingsPageComputerUse(model: *Model, fx: *Effects) void {
    handleSetSettingsPage(model, fx, .computer_use);
}

pub fn handleCycleSettingsPageDown(model: *Model, fx: *Effects) void {
    handleCycleSettingsPage(model, fx, true);
}

pub fn handleCycleSettingsPageUp(model: *Model, fx: *Effects) void {
    handleCycleSettingsPage(model, fx, false);
}

fn handleCycleSettingsPage(model: *Model, fx: *Effects, down: bool) void {
    if (!model.settings_open) return;
    const page = model.nextVisibleSettingsPage(down) orelse return;
    handleSetSettingsPage(model, fx, page);
}

fn handleSetSettingsPage(model: *Model, fx: *Effects, page: skills.Page) void {
    switch (page) {
        .general, .appearance, .providers, .daemon, .computer_use => {
            leaveUsagePage(model);
            leaveSkillsPage(model, fx);
        },
        .skills => leaveUsagePage(model),
        .usage => leaveSkillsPage(model, fx),
    }
    model.settings_page = page;
    switch (page) {
        .providers => providers.startProbes(model, fx),
        .skills => skills.refresh(model, fx),
        .usage => {
            usage_history.refresh(model, fx);
            litellm_rates.ensure(model, fx);
        },
        .general, .appearance, .daemon, .computer_use => {},
    }
    store.persistSettingsIfPossible(model);
}

/// Settings General Share anonymous usage data chip. Closes
/// switcher / palette / Settings effort picker like other Settings
/// General overlays, then flips `analytics_enabled` and merge-writes
/// extras. Preference + UI only; no telemetry this cut.
pub fn handleToggleAnalyticsEnabled(model: *Model) void {
    session_switcher.closeSwitcher(model);
    if (model.palette_open) model.closePalette();
    model.closeSettingsEffortPicker();
    model.closeSkillsSourcePicker();
    model.analytics_enabled = !model.analytics_enabled;
    store.persistSettingsIfPossible(model);
}

/// Settings General Render math expressions chip. Closes
/// switcher / palette / Settings effort picker like other Settings
/// General overlays, then flips `render_math` and merge-writes
/// extras. Preference + UI only; Native `<markdown>` has no math
/// flag this cut.
pub fn handleToggleRenderMath(model: *Model) void {
    session_switcher.closeSwitcher(model);
    if (model.palette_open) model.closePalette();
    model.closeSettingsEffortPicker();
    model.closeSkillsSourcePicker();
    model.render_math = !model.render_math;
    store.persistSettingsIfPossible(model);
}

/// Settings General Automatic updates chip. Closes
/// switcher / palette / Settings effort picker like other Settings
/// General overlays, then flips `automatic_updates_enabled` and merge-writes
/// extras. Preference + UI only; no Sparkle / check-for-updates /
/// download / install this cut.
pub fn handleToggleAutomaticUpdates(model: *Model) void {
    session_switcher.closeSwitcher(model);
    if (model.palette_open) model.closePalette();
    model.closeSettingsEffortPicker();
    model.closeSkillsSourcePicker();
    model.automatic_updates_enabled = !model.automatic_updates_enabled;
    store.persistSettingsIfPossible(model);
}

fn leaveUsagePage(model: *Model) void {
    if (model.settings_page != .usage) return;
    usage_history.leaveUsage(model);
}

fn leaveSkillsPage(model: *Model, fx: *Effects) void {
    if (model.settings_page != .skills) return;
    skills.leavePage(model, fx);
}

/// Re-kick Providers / Skills / Usage probes when Settings opens onto a
/// persisted page. Nav handlers already start those probes; open must
/// match so reboot-restore is not an empty page until Refresh.
fn resumeSettingsPage(model: *Model, fx: *Effects) void {
    switch (model.settings_page) {
        .providers => providers.startProbes(model, fx),
        .skills => skills.refresh(model, fx),
        .usage => {
            usage_history.refresh(model, fx);
            litellm_rates.ensure(model, fx);
        },
        .general, .appearance, .daemon, .computer_use => {},
    }
}

pub fn handleSettingsThemeSystem(model: *Model) void {
    model.setThemePreference(.system);
    store.persistSettingsIfPossible(model);
}

pub fn handleSettingsThemeLight(model: *Model) void {
    model.setThemePreference(.light);
    store.persistSettingsIfPossible(model);
}

pub fn handleSettingsThemeDark(model: *Model) void {
    model.setThemePreference(.dark);
    store.persistSettingsIfPossible(model);
}

pub fn handleSettingsUiFontSize(model: *Model, size: u8) void {
    model.setUiFontSize(size);
    store.persistSettingsIfPossible(model);
}

pub fn handleSettingsCodeFontSize(model: *Model, size: u8) void {
    model.setCodeFontSize(size);
    store.persistSettingsIfPossible(model);
}

pub fn handleSettingsLanguageSystem(model: *Model) void {
    model.setLanguagePreference(.system);
    store.persistSettingsIfPossible(model);
}

pub fn handleSettingsLanguageEnglish(model: *Model) void {
    model.setLanguagePreference(.english);
    store.persistSettingsIfPossible(model);
}

pub fn handleSettingsLanguageSimplifiedChinese(model: *Model) void {
    model.setLanguagePreference(.simplified_chinese);
    store.persistSettingsIfPossible(model);
}

pub fn handleSettingsLanguageJapanese(model: *Model) void {
    model.setLanguagePreference(.japanese);
    store.persistSettingsIfPossible(model);
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

pub fn handleToggleProviderEnabled(model: *Model, id: u32) void {
    if (!providers.toggleProviderEnabled(model, id)) return;
    store.persistSettingsIfPossible(model);
}

pub fn handleToggleProviderExpanded(model: *Model, fx: *Effects, id: u32) void {
    if (!providers.toggleExpanded(model, fx, id)) return;
    store.persistSettingsIfPossible(model);
}

pub fn handleProviderOverrideEdit(model: *Model, edit: canvas.TextInputEvent) void {
    model.applyProviderOverrideEdit(edit);
}

pub fn handleApplyProviderPathOverride(model: *Model, fx: *Effects) void {
    if (!providers.applyPathOverride(model, fx)) return;
    store.persistSettingsIfPossible(model);
}

pub fn handleClearProviderPathOverride(model: *Model, fx: *Effects) void {
    if (!providers.clearPathOverride(model, fx)) return;
    store.persistSettingsIfPossible(model);
}

pub fn handleOpencode2AttachEdit(model: *Model, edit: canvas.TextInputEvent) void {
    model.applyOpencode2AttachEdit(edit);
}

pub fn handleApplyOpencode2Attach(model: *Model, fx: *Effects) void {
    if (!providers.applyAttachUrl(model, fx)) return;
    store.persistSettingsIfPossible(model);
}

pub fn handleClearOpencode2Attach(model: *Model, fx: *Effects) void {
    if (!providers.clearAttachUrl(model, fx)) return;
    store.persistSettingsIfPossible(model);
}

pub fn handleOpencode2PasswordEdit(model: *Model, edit: canvas.TextInputEvent) void {
    model.applyOpencode2PasswordEdit(edit);
}

pub fn handleApplyOpencode2Password(model: *Model, fx: *Effects) void {
    if (!providers.applyServerPassword(model, fx)) return;
    store.persistSettingsIfPossible(model);
}

pub fn handleClearOpencode2Password(model: *Model, fx: *Effects) void {
    if (!providers.clearServerPassword(model, fx)) return;
    store.persistSettingsIfPossible(model);
}

pub fn handleOpencode2UsernameEdit(model: *Model, edit: canvas.TextInputEvent) void {
    model.applyOpencode2UsernameEdit(edit);
}

pub fn handleApplyOpencode2Username(model: *Model, fx: *Effects) void {
    if (!providers.applyServerUsername(model, fx)) return;
    store.persistSettingsIfPossible(model);
}

pub fn handleClearOpencode2Username(model: *Model, fx: *Effects) void {
    if (!providers.clearServerUsername(model, fx)) return;
    store.persistSettingsIfPossible(model);
}

pub fn handleApplySessionProvider(model: *Model, fx: *Effects) void {
    if (!providers.applyToSession(model)) return;
    store.persistIfPossible(model, model.selected, fx);
    slash_commands.refresh(model, fx);
    usage_meter.onSessionChange(model, fx);
}

pub fn handleCopyFxInstall(model: *Model, fx: *Effects) void {
    providers.copyFxInstall(model, fx);
}

pub fn handleCopyFxLogin(model: *Model, fx: *Effects) void {
    providers.copyFxLogin(model, fx);
}

pub fn handleCopyOpencode2Serve(model: *Model, fx: *Effects) void {
    providers.copyOpencode2Serve(model, fx);
}

pub fn handleCheckOpencode2Serve(model: *Model, fx: *Effects) void {
    providers.startCheckOpencode2Serve(model, fx);
}

pub fn handleCopyDeepseekWeb(model: *Model, fx: *Effects) void {
    providers.copyDeepseekWeb(model, fx);
}

pub fn handleSkillsFilterEdit(model: *Model, edit: canvas.TextInputEvent) void {
    model.applySkillsFilter(edit);
}

pub fn handleSettingsSearchEdit(model: *Model, edit: canvas.TextInputEvent) void {
    model.applySettingsSearch(edit);
}

pub fn handleSelectSkill(model: *Model, id: u32) void {
    skills.selectSkill(model, id);
}

pub fn handleToggleSkillEnabled(model: *Model, fx: *Effects) void {
    skills.toggleSkillEnabled(model, fx);
}

pub fn handleArmSkillDelete(model: *Model) void {
    skills.armSkillDelete(model);
}

pub fn handleConfirmSkillDelete(model: *Model, fx: *Effects) void {
    skills.confirmSkillDelete(model, fx);
}

pub fn handleOpenSkillInEditor(model: *Model, fx: *Effects) void {
    skills.openSelectedSkillInEditor(model, fx);
}

pub fn handleRevealSkill(model: *Model, fx: *Effects) void {
    skills.revealSelectedSkill(model, fx);
}

pub fn handleCopySkillPath(model: *Model, fx: *Effects) void {
    skills.copySelectedSkillPath(model, fx);
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
        model.closeSkillsSourcePicker();
        model.goal_status_picker_open = false;
        model.closeGitBranchPicker();
        usage_meter.close(model);
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
        model.closeSkillsSourcePicker();
        model.goal_status_picker_open = false;
        model.closeGitBranchPicker();
        usage_meter.close(model);
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
        model.closeSkillsSourcePicker();
        model.goal_status_picker_open = false;
        model.closeGitBranchPicker();
        usage_meter.close(model);
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
        model.closeSkillsSourcePicker();
        model.goal_status_picker_open = false;
        model.workspace_picker_open = false;
        git_checkout.closeDelete(model);
        git_checkout.closePushConfirm(model);
    }
    model.toggleGitBranchPicker();
}

pub fn handleGitBranchSearchEdit(model: *Model, edit: canvas.TextInputEvent) void {
    model.applyGitBranchSearch(edit);
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

pub fn handleConfirmGitPush(model: *Model, fx: *Effects) void {
    git_checkout.confirmPush(model, fx);
}

pub fn handleCancelGitPush(model: *Model) void {
    git_checkout.cancelPushConfirm(model);
}

pub fn handleToggleGitPushForce(model: *Model, fx: *Effects) void {
    git_checkout.togglePushForce(model, fx);
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

pub fn handleToggleGitWorktreeBasePicker(model: *Model) void {
    git_checkout.toggleWorktreeBasePicker(model);
}

pub fn handlePickGitWorktreeBase(model: *Model, fx: *Effects, name: []const u8) void {
    git_checkout.pickWorktreeBaseName(model, name);
    if (session_workspace.selectedIsNewWorktree(model)) {
        persist.persistComposerChips(model, fx);
    }
}

pub fn handleToggleWorkspacePicker(model: *Model) void {
    if (!model.workspace_picker_open) {
        session_switcher.closeSwitcher(model);
        if (model.palette_open) model.closePalette();
        model.model_picker_open = false;
        model.access_picker_open = false;
        model.effort_picker_open = false;
        model.settings_effort_picker_open = false;
        model.closeSkillsSourcePicker();
        model.goal_status_picker_open = false;
        model.closeGitBranchPicker();
        git_checkout.closeDelete(model);
        git_checkout.closePushConfirm(model);
    }
    model.toggleWorkspacePicker();
}

pub fn handlePickWorkspaceLocal(model: *Model, fx: *Effects) void {
    session_workspace.pickLocal(model, fx);
}

pub fn handlePickWorkspaceNewWorktree(model: *Model, fx: *Effects) void {
    session_workspace.pickNewWorktree(model, fx);
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

test "handleToggleProviderExpanded applies pending override; empty apply clears" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    handleToggleProviderExpanded(&model, &fx, 0);
    try testing.expectEqual(@as(u32, 0), model.provider_expanded_id);

    handleToggleProviderExpanded(&model, &fx, providers.rowId(.claude));
    try testing.expectEqual(providers.rowId(.claude), model.provider_expanded_id);
    handleProviderOverrideEdit(&model, .{ .insert_text = "/opt/claude" });
    try testing.expectEqualStrings("/opt/claude", model.provider_override_draft());
    handleApplyProviderPathOverride(&model, &fx);
    try testing.expectEqualStrings("/opt/claude", model.providerBinaryOverride(.claude));

    handleToggleProviderExpanded(&model, &fx, providers.rowId(.fx));
    try testing.expectEqual(providers.rowId(.fx), model.provider_expanded_id);
    try testing.expectEqualStrings("/opt/claude", model.providerBinaryOverride(.claude));

    handleProviderOverrideEdit(&model, .{ .insert_text = "/opt/fx" });
    handleToggleProviderExpanded(&model, &fx, providers.rowId(.claude));
    try testing.expectEqual(providers.rowId(.claude), model.provider_expanded_id);
    try testing.expectEqualStrings("/opt/fx", model.providerBinaryOverride(.fx));
    try testing.expectEqualStrings("/opt/claude", model.provider_override_draft());

    handleClearProviderPathOverride(&model, &fx);
    try testing.expectEqualStrings("", model.providerBinaryOverride(.claude));
    try testing.expectEqualStrings("/opt/fx", model.providerBinaryOverride(.fx));
}

test "handleApplyOpencode2Attach persists; empty apply and Reset clear" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    handleToggleProviderExpanded(&model, &fx, providers.rowId(.opencode2));
    try testing.expectEqual(providers.rowId(.opencode2), model.provider_expanded_id);
    handleOpencode2AttachEdit(&model, .{ .insert_text = "http://localhost:4096" });
    try testing.expectEqualStrings("http://localhost:4096", model.opencode2_attach_draft());
    handleApplyOpencode2Attach(&model, &fx);
    try testing.expectEqualStrings("http://localhost:4096", model.opencode2AttachUrl());

    handleToggleProviderExpanded(&model, &fx, providers.rowId(.fx));
    try testing.expectEqualStrings("http://localhost:4096", model.opencode2AttachUrl());
    handleOpencode2AttachEdit(&model, .{ .insert_text = "http://ignored" });
    handleApplyOpencode2Attach(&model, &fx);
    try testing.expectEqualStrings("http://localhost:4096", model.opencode2AttachUrl());

    handleToggleProviderExpanded(&model, &fx, providers.rowId(.opencode2));
    try testing.expectEqualStrings("http://localhost:4096", model.opencode2_attach_draft());
    handleClearOpencode2Attach(&model, &fx);
    try testing.expectEqualStrings("", model.opencode2AttachUrl());
    try testing.expectEqualStrings("", model.opencode2_attach_draft());
}

test "handleApplyOpencode2Password persists; empty apply and Reset clear" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    handleToggleProviderExpanded(&model, &fx, providers.rowId(.opencode2));
    try testing.expectEqual(providers.rowId(.opencode2), model.provider_expanded_id);
    handleOpencode2PasswordEdit(&model, .{ .insert_text = "s3cret" });
    try testing.expectEqualStrings("s3cret", model.opencode2_password_draft());
    handleApplyOpencode2Password(&model, &fx);
    try testing.expectEqualStrings("s3cret", model.opencode2ServerPassword());

    handleToggleProviderExpanded(&model, &fx, providers.rowId(.fx));
    try testing.expectEqualStrings("s3cret", model.opencode2ServerPassword());
    handleOpencode2PasswordEdit(&model, .{ .insert_text = "ignored" });
    handleApplyOpencode2Password(&model, &fx);
    try testing.expectEqualStrings("s3cret", model.opencode2ServerPassword());

    handleToggleProviderExpanded(&model, &fx, providers.rowId(.opencode2));
    try testing.expectEqualStrings("s3cret", model.opencode2_password_draft());
    handleClearOpencode2Password(&model, &fx);
    try testing.expectEqualStrings("", model.opencode2ServerPassword());
    try testing.expectEqualStrings("", model.opencode2_password_draft());
}

test "handleApplyOpencode2Username persists; empty apply and Reset clear" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    handleToggleProviderExpanded(&model, &fx, providers.rowId(.opencode2));
    try testing.expectEqual(providers.rowId(.opencode2), model.provider_expanded_id);
    handleOpencode2UsernameEdit(&model, .{ .insert_text = "alice" });
    try testing.expectEqualStrings("alice", model.opencode2_username_draft());
    handleApplyOpencode2Username(&model, &fx);
    try testing.expectEqualStrings("alice", model.opencode2ServerUsername());

    handleToggleProviderExpanded(&model, &fx, providers.rowId(.fx));
    try testing.expectEqualStrings("alice", model.opencode2ServerUsername());
    handleOpencode2UsernameEdit(&model, .{ .insert_text = "ignored" });
    handleApplyOpencode2Username(&model, &fx);
    try testing.expectEqualStrings("alice", model.opencode2ServerUsername());

    handleToggleProviderExpanded(&model, &fx, providers.rowId(.opencode2));
    try testing.expectEqualStrings("alice", model.opencode2_username_draft());
    handleClearOpencode2Username(&model, &fx);
    try testing.expectEqualStrings("", model.opencode2ServerUsername());
    try testing.expectEqualStrings("", model.opencode2_username_draft());
}
