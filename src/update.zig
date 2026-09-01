//! Msg `update` dispatch and boot `initFx`.
//!
//! `pub fn update` is the TEA switch over `Msg`. `initFx` is the
//! matching `.init_fx` boot (catalog hydrate + git probes + fx `--help`).
//! Re-exported from `main.zig` so `UiApp` and tests keep `main.update` /
//! `main.initFx`. Behavior is unchanged from the former `main` functions.
//! `initialModel` / appearance boot live in `boot.zig`.

const main = @import("main.zig");
const store = @import("store.zig");
const maximize_window = @import("maximize_window.zig");
const goal = @import("goal.zig");
const session_switcher = @import("switcher.zig");
const sidebar_row_helpers = @import("sidebar_rows.zig");
const attach_helpers = @import("attach.zig");
const session_fork = @import("fork.zig");
const turn_stream = @import("stream.zig");
const sidecar_lines = @import("lines.zig");
const fx_probe = @import("fx_probe.zig");
const cli_probe = @import("cli_probe.zig");
const palette_run = @import("palette_run.zig");
const persist = @import("persist.zig");
const session_actions = @import("session_actions.zig");
const settings_actions = @import("settings_actions.zig");
const git_branch = @import("git_branch.zig");
const git_checkout = @import("git_checkout.zig");
const git_dirty = @import("git_dirty.zig");
const git_numstat = @import("git_numstat.zig");
const git_ahead_behind = @import("git_ahead_behind.zig");
const git_remotes = @import("git_remotes.zig");
const git_toplevel = @import("git_toplevel.zig");
const git_common_dir = @import("git_common_dir.zig");
const git_commit = @import("git_commit.zig");
const environment_summary = @import("environment_summary.zig");
const review_diff = @import("review_diff.zig");
const file_mention = @import("file_mention.zig");
const pick_folder = @import("pick_folder.zig");
const reveal_folder = @import("reveal_folder.zig");
const open_terminal = @import("open_terminal.zig");
const open_editor = @import("open_editor.zig");
const copy_helpers = @import("copy.zig");
const right_panel = @import("right_panel.zig");

const Model = main.Model;
const Msg = main.Msg;
const Effects = main.Effects;
const main_window_label = main.main_window_label;

pub fn update(model: *Model, msg: Msg, fx: *Effects) void {
    model.now_ms = fx.wallMs();
    switch (msg) {
        .new_session => session_actions.handleNewSession(model, fx),
        .select => |id| session_actions.handleSelect(model, fx, id),
        .history_back => palette_run.goHistory(-1, model, fx),
        .history_forward => palette_run.goHistory(1, model, fx),
        .new_folder => session_actions.handleNewFolder(model),
        .toggle_folder => |folder_id| session_actions.handleToggleFolder(model, folder_id),
        .collapse_all_folders => session_actions.handleCollapseAllFolders(model),
        .rename_folder => |id| session_actions.handleRenameFolder(model, id),
        .delete_folder => |folder_id| persist.persistDeletedFolder(model, folder_id, fx),
        .assign_selected => |folder_id| session_actions.handleAssignSelected(model, fx, folder_id),
        .unassign_selected => session_actions.handleUnassignSelected(model, fx),
        .folder_title_edit => |edit| session_actions.handleFolderTitleEdit(model, edit),
        .edit_session_title => session_actions.handleEditSessionTitle(model),
        .rename_session => |id| session_actions.handleRenameSession(model, id),
        .session_title_edit => |edit| session_actions.handleSessionTitleEdit(model, fx, edit),
        .assign_folder => |assign| persist.persistAssignedFolder(model, assign.session_id, assign.folder_id, fx),
        // Chromeless titlebar has no OS close. This is the documented
        // window-action effect (`examples/deck`): last-window close
        // follows the host exit path. Esc stays `.stop` so the session
        // switcher / Environment dropdown / Review card / command palette / settings / transcript-find / project-edit /
        // image-attach / commands / typing-triggered @ / slash card /
        // folder-title-edit / session-title-edit / a live turn keep it.
        .close_window => fx.closeWindow(main_window_label),
        .minimize_window => fx.minimizeWindow(main_window_label),
        .maximize_window => maximize_window.startMaximizeWindow(model, fx),
        .quit_app => fx.quitApp(),
        .appearance_changed => |appearance| model.appearance = appearance,
        .remove_session => |id| session_actions.handleRemoveSession(model, fx, id),
        .start_search => palette_run.openPalette(model),
        .palette_confirm => palette_run.confirmPalette(model, fx),
        .palette_cancel => model.closePalette(),
        .palette_pick => |id| palette_run.runPalettePick(model, fx, id),
        .open_find => {
            model.find_active = true;
            model.composer_active = false;
            model.resetFindMatchIndex();
        },
        .close_find => model.exitFind(),
        .find_next => model.stepFindMatch(false),
        .find_prev => model.stepFindMatch(true),
        .focus_composer => model.composer_active = true,
        .search_edit => |edit| {
            model.search_buffer.apply(edit);
            model.palette_highlight = 0;
            if (model.palette_open) palette_run.clampPaletteHighlight(model);
        },
        .find_edit => |edit| {
            model.find_buffer.apply(edit);
            model.resetFindMatchIndex();
        },
        .draft_edit => |edit| {
            model.draft_buffer.apply(edit);
            model.autocomplete_dismissed = false;
            model.autocomplete_highlight = 0;
            store.persistDraftIfPossible(model);
            model.maybeEnsureSkillsScanned(fx);
        },
        .composer_enter => {
            if (model.commands_list_open() or model.skills_list_open() or model.mentions_list_open()) {
                if (model.insertHighlightedAutocomplete()) {
                    store.persistDraftIfPossible(model);
                }
            } else {
                turn_stream.handleSend(model, fx);
            }
        },
        .send => turn_stream.handleSend(model, fx),
        .stop_turn => turn_stream.stopStream(model, fx),
        .steer => turn_stream.handleSteer(model, fx),
        .goal_set => goal.handleGoalSet(model, fx),
        .goal_clear => goal.handleGoalClear(model, fx),
        .goal_refresh => goal.handleGoalRefresh(model, fx),
        .toggle_goal_status_picker => settings_actions.handleToggleGoalStatusPicker(model),
        .close_goal_status_picker => model.closeGoalStatusPicker(),
        .pick_goal_status => |status| goal.handleGoalSetStatus(model, fx, status),
        .switcher_forward => session_switcher.cycleSwitcher(model, false),
        .switcher_backward => session_switcher.cycleSwitcher(model, true),
        .switcher_confirm => session_switcher.confirmSwitcher(model, fx),
        .switcher_cancel => session_switcher.closeSwitcher(model),
        .switcher_pick => |id| session_switcher.pickSwitcher(model, fx, id),
        .stop => settings_actions.handleStop(model, fx),
        .toggle_settings => settings_actions.handleToggleSettings(model, fx),
        .settings_model_edit => |edit| settings_actions.handleSettingsModelEdit(model, edit),
        .settings_project_edit => |edit| settings_actions.handleSettingsProjectEdit(model, edit),
        .settings_daemon_edit => |edit| settings_actions.handleSettingsDaemonEdit(model, edit),
        .settings_access_ask => settings_actions.handleSettingsAccessAsk(model),
        .settings_access_auto => settings_actions.handleSettingsAccessAuto(model),
        .settings_access_full => settings_actions.handleSettingsAccessFull(model),
        .settings_interaction_build => settings_actions.handleSettingsInteractionBuild(model),
        .settings_interaction_plan => settings_actions.handleSettingsInteractionPlan(model),
        .toggle_settings_effort_picker => settings_actions.handleToggleSettingsEffortPicker(model),
        .close_settings_effort_picker => model.closeSettingsEffortPicker(),
        .pick_settings_effort => |id| settings_actions.handlePickSettingsEffort(model, id),
        .set_settings_page_general => settings_actions.handleSetSettingsPageGeneral(model),
        .set_settings_page_appearance => settings_actions.handleSetSettingsPageAppearance(model),
        .set_settings_page_providers => settings_actions.handleSetSettingsPageProviders(model, fx),
        .set_settings_page_skills => settings_actions.handleSetSettingsPageSkills(model, fx),
        .set_settings_page_usage => settings_actions.handleSetSettingsPageUsage(model),
        .set_settings_page_computer_use => settings_actions.handleSetSettingsPageComputerUse(model),
        .settings_theme_system => settings_actions.handleSettingsThemeSystem(model),
        .settings_theme_light => settings_actions.handleSettingsThemeLight(model),
        .settings_theme_dark => settings_actions.handleSettingsThemeDark(model),
        .settings_language_system => settings_actions.handleSettingsLanguageSystem(model),
        .settings_language_english => settings_actions.handleSettingsLanguageEnglish(model),
        .settings_language_simplified_chinese => settings_actions.handleSettingsLanguageSimplifiedChinese(model),
        .settings_language_japanese => settings_actions.handleSettingsLanguageJapanese(model),
        .refresh_skills => settings_actions.handleRefreshSkills(model, fx),
        .refresh_providers => settings_actions.handleRefreshProviders(model, fx),
        .skills_filter_edit => |edit| settings_actions.handleSkillsFilterEdit(model, edit),
        .select_skill => |id| settings_actions.handleSelectSkill(model, id),
        .select_provider => |id| settings_actions.handleSelectProvider(model, id),
        .apply_session_provider => settings_actions.handleApplySessionProvider(model, fx),
        .copy_fx_install => settings_actions.handleCopyFxInstall(model, fx),
        .copy_fx_login => settings_actions.handleCopyFxLogin(model, fx),
        .cycle_access => settings_actions.handleCycleAccess(model, fx),
        .cycle_interaction => settings_actions.handleCycleInteraction(model, fx),
        .cycle_effort => settings_actions.handleCycleEffort(model, fx),
        .toggle_model_picker => settings_actions.handleToggleModelPicker(model),
        .close_model_picker => model.closeModelPicker(),
        .pick_model => |id| settings_actions.handlePickModel(model, fx, id),
        .toggle_access_picker => settings_actions.handleToggleAccessPicker(model),
        .close_access_picker => model.closeAccessPicker(),
        .pick_access => |id| settings_actions.handlePickAccess(model, fx, id),
        .toggle_effort_picker => settings_actions.handleToggleEffortPicker(model),
        .close_effort_picker => model.closeEffortPicker(),
        .pick_effort => |id| settings_actions.handlePickEffort(model, fx, id),
        .toggle_git_branch_picker => settings_actions.handleToggleGitBranchPicker(model),
        .close_git_branch_picker => model.closeGitBranchPicker(),
        .pick_git_branch => |name| settings_actions.handlePickGitBranch(model, fx, name),
        .start_git_branch_create => settings_actions.handleStartGitBranchCreate(model, fx),
        .git_branch_create_edit => |edit| settings_actions.handleGitBranchCreateEdit(model, edit),
        .confirm_git_branch_create => settings_actions.handleConfirmGitBranchCreate(model, fx),
        .cancel_git_branch_create => settings_actions.handleCancelGitBranchCreate(model),
        .start_git_branch_delete => settings_actions.handleStartGitBranchDelete(model, fx),
        .toggle_git_branch_delete_picker => settings_actions.handleToggleGitBranchDeletePicker(model),
        .close_git_branch_delete_picker => model.closeGitBranchDeletePicker(),
        .pick_git_branch_delete => |name| settings_actions.handlePickGitBranchDelete(model, name),
        .confirm_git_branch_delete => settings_actions.handleConfirmGitBranchDelete(model, fx),
        .cancel_git_branch_delete => settings_actions.handleCancelGitBranchDelete(model),
        .toggle_git_branch_delete_force => settings_actions.handleToggleGitBranchDeleteForce(model, fx),
        .start_git_fetch => settings_actions.handleStartGitFetch(model, fx),
        .start_git_push => settings_actions.handleStartGitPush(model, fx),
        .start_git_worktree_create => settings_actions.handleStartGitWorktreeCreate(model, fx),
        .git_worktree_create_edit => |edit| settings_actions.handleGitWorktreeCreateEdit(model, edit),
        .confirm_git_worktree_create => settings_actions.handleConfirmGitWorktreeCreate(model, fx),
        .cancel_git_worktree_create => settings_actions.handleCancelGitWorktreeCreate(model, fx),
        .start_git_commit => settings_actions.handleStartGitCommit(model, fx),
        .toggle_environment_summary => environment_summary.toggle(model),
        .close_environment_summary => environment_summary.close(model),
        .environment_commit_or_push => environment_summary.commitOrPush(model, fx),
        .environment_compare => {
            environment_summary.compare(model, fx);
            store.persistLayoutIfPossible(model);
        },
        .environment_copy_task_id => environment_summary.copyTaskId(model, fx),
        .environment_copy_agent_thread_id => environment_summary.copyAgentCliThreadId(model, fx),
        .environment_stop_background => |id| environment_summary.stopBackground(model, fx, id),
        .close_review_diff => review_diff.dismiss(model, fx),
        .set_review_diff_source_branch => review_diff.setSource(model, fx, .branch),
        .set_review_diff_source_uncommitted => review_diff.setSource(model, fx, .uncommitted),
        .set_review_diff_source_staged => review_diff.setSource(model, fx, .staged),
        .set_review_diff_source_unstaged => review_diff.setSource(model, fx, .unstaged),
        .set_review_diff_source_committed => review_diff.setSource(model, fx, .committed),
        .set_review_diff_source_last_turn => review_diff.setSource(model, fx, .last_turn),
        .select_review_diff_file => |id| review_diff.selectFile(model, fx, id),
        .git_commit_edit => |edit| settings_actions.handleGitCommitEdit(model, edit),
        .confirm_git_commit => settings_actions.handleConfirmGitCommit(model, fx),
        .confirm_git_commit_and_push => settings_actions.handleConfirmGitCommitAndPush(model, fx),
        .confirm_git_commit_push => settings_actions.handleConfirmGitCommitPush(model, fx),
        .cancel_git_commit => settings_actions.handleCancelGitCommit(model, fx),
        .toggle_git_commit_include_unstaged => settings_actions.handleToggleGitCommitIncludeUnstaged(model, fx),
        .toggle_git_commit_amend => settings_actions.handleToggleGitCommitAmend(model, fx),
        .start_project_edit => {
            git_commit.dropCommitNumstat(model, fx);
            review_diff.close(model, fx);
            model.startProjectEdit();
        },
        .project_path_edit => |edit| {
            model.applySelectedProjectPath(edit);
            persist.persistComposerProject(model, fx);
        },
        .pick_folder => pick_folder.startPickFolder(model, fx),
        .reveal_folder => reveal_folder.startRevealFolder(model, fx),
        .open_terminal => open_terminal.startOpenTerminal(model, fx),
        .open_editor => open_editor.startOpenEditor(model, fx),
        .copy_project_path => copy_helpers.copyProjectPath(model, fx),
        .start_image_attach => model.startImageAttach(),
        .pick_image => attach_helpers.startPickImage(model, fx),
        .image_path_edit => |edit| {
            model.applyImagePath(edit);
            store.persistDraftIfPossible(model);
            attach_helpers.refreshAttachPreview(model, fx);
        },
        .file_drop => |path| attach_helpers.applyFileDrop(model, fx, path),
        .clear_image_attach => {
            model.clearImageAttach();
            store.persistDraftIfPossible(model);
            attach_helpers.refreshAttachPreview(model, fx);
        },
        .toggle_commands => model.toggleCommands(),
        .insert_command => |id| {
            model.insertAvailableCommand(id);
            store.persistDraftIfPossible(model);
        },
        .insert_mention => |id| {
            model.insertAvailableMention(id);
            store.persistDraftIfPossible(model);
        },
        .insert_skill => |id| {
            model.insertAvailableSkill(id);
            store.persistDraftIfPossible(model);
        },
        .rewind => session_fork.applyRewindIfPossible(model, fx),
        .fork => session_fork.forkSelectedSession(model, fx),
        .fork_turn => |id| session_fork.forkSelectedThroughTurn(model, fx, id),
        .clear_queue => {
            model.dropQueuedForSession(model.selected);
            store.persistIfPossible(model, model.selected, fx);
        },
        .remove_queued => |id| {
            if (model.dropQueued(id)) {
                store.persistIfPossible(model, model.selected, fx);
            }
        },
        .edit_queued => |id| session_actions.handleEditQueued(model, fx, id),
        .toggle_sidebar => {
            model.toggleSidebar();
            store.persistLayoutIfPossible(model);
        },
        .show_right_panel => {
            model.showRightPanel();
            file_mention.refresh(model, fx);
            store.persistLayoutIfPossible(model);
        },
        .hide_right_panel => {
            model.hideRightPanel();
            store.persistLayoutIfPossible(model);
        },
        .toggle_right_panel => {
            const opening = !model.right_panel_open;
            model.toggleRightPanel();
            if (opening) file_mention.refresh(model, fx);
            store.persistLayoutIfPossible(model);
        },
        .right_panel_resized => |fraction| {
            model.applyRightPanelResize(fraction);
            store.persistLayoutIfPossible(model);
        },
        .open_right_panel_file => |id| right_panel.openCachedFile(model, fx, id),
        .toggle_right_panel_dir => |id| right_panel.toggleDir(model, id),
        .set_right_panel_tab_files => {
            right_panel.selectFiles(model, fx);
            store.persistLayoutIfPossible(model);
        },
        .set_right_panel_tab_diff => {
            right_panel.selectDiff(model, fx);
            store.persistLayoutIfPossible(model);
        },
        .set_right_panel_tab_background => {
            right_panel.selectBackground(model, fx, 0);
            store.persistLayoutIfPossible(model);
        },
        .open_background_work => |id| {
            environment_summary.openBackgroundWork(model, fx, id);
            store.persistLayoutIfPossible(model);
        },
        .sidebar_resized => |fraction| {
            sidebar_row_helpers.applySidebarResize(model, fraction);
            model.syncRightPanelSplit();
            store.persistLayoutIfPossible(model);
        },
        .transcript_scrolled => |scroll| model.applyTranscriptScroll(scroll),
        .jump_latest => model.pinTranscriptToLatest(),
        .copy_turn => |id| copy_helpers.copyTurn(model, fx, id),
        .copy_last_turn => copy_helpers.copyLastTurn(model, fx),
        .copy_session => copy_helpers.copySession(model, fx),
        .copy_session_id => copy_helpers.copySessionId(model, fx),
        .copy_fx_session_id => copy_helpers.copyFxSessionId(model, fx),
        .clipboard_done => {},
        .attach_preview_done => |result| attach_helpers.applyAttachPreviewResult(model, fx, result),
        .tick => |timer| {
            if (timer.outcome != .fired) return;
            turn_stream.tickStream(model, fx);
        },
        .fx_line => |line| sidecar_lines.handleFxLine(model, fx, line),
        .fx_exit => |exit| sidecar_lines.handleFxExit(model, fx, exit),
        .fx_probe_exit => |exit| fx_probe.handleFxProbeExit(model, fx, exit),
        .cli_probe_exit => |exit| cli_probe.handleCliProbeExit(model, exit),
    }
    // Waku-parity 100ms Background render cache. Piggybacks
    // `now_ms` (stamped above) and this stream tick / fx_line
    // path. Native has no dedicated 100ms timer this cut.
    _ = environment_summary.refreshBackgroundOutputCache(model);
}

/// Boot probe: `~/.local/bin/fx --help` then `fx --help` (PATH). Wired
/// through `.init_fx` so the first paint already has the spawn in flight.
pub fn initFx(model: *Model, fx: *Effects) void {
    model.now_ms = fx.wallMs();
    store.maybeLoadDaemonCatalog(model, fx);
    store.maybeHydrateDaemonSession(model, fx, model.selected);
    attach_helpers.refreshAttachPreview(model, fx);
    git_branch.refresh(model, fx);
    git_dirty.refresh(model, fx);
    git_numstat.refresh(model, fx);
    git_ahead_behind.refresh(model, fx);
    git_remotes.refresh(model, fx);
    git_toplevel.refresh(model, fx);
    git_common_dir.refresh(model, fx);
    file_mention.refresh(model, fx);
    git_checkout.refresh(model, fx);
    fx_probe.startFxProbe(model, fx);
}
