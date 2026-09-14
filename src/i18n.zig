//! Settings chrome locale: LanguagePreference, System env resolve, labels.
//!
//! Native has no locale / NSLocale API this cut. System follows process
//! `LC_ALL`, else `LC_MESSAGES`, else `LANG` (non-macOS Waku path), copied
//! at boot onto the model. Settings chrome strings, first-cut sidebar
//! date-bucket titles, first-cut sidebar New Task / Search / folder
//! chrome, session context-menu Rename / Remove, palette action
//! display labels (same `Sidebar` / `Chrome` strings for New Task /
//! Settings / Collapse all folders; remaining command names in
//! `Palette`), palette overlay section headers, empty-state
//! lines, footer Confirm, and dialog title (`PaletteChrome`; Cancel
//! reuses `CommitChrome`), composer / Settings General Ask / Auto /
//! Full access (same `Access` strings), first-cut composer effort chip /
//! Settings General effort labels (same `Effort` strings),
//! first-cut composer interaction chip / Settings General Build /
//! Plan (same `Interaction` strings), first-cut right-panel tab
//! button labels (same `RightPanelTabs` strings; EN Diff tab reads
//! Review), first-cut right-panel Diff filter + Files/Background
//! empty-state chrome (including Files empty secondary Open a
//! project to browse its files / Loading files…) plus Browser
//! start page / Open in browser / Open in Terminal (same
//! `RightPanelChrome` strings), and first-cut
//! composer project-row Pick folder / Reveal folder / Open in Editor /
//! Copy path (same `ComposerProjectChrome` strings; Open in Terminal
//! reuses `RightPanelChrome.open_in_terminal`), and first-cut Review
//! Diff header title / Cancel / source chips / gap expand
//! Start / End / Both / All (same `ReviewDiffChrome` strings),
//! and first-cut Background row kind /
//! status / stop·dismiss chrome (same `BackgroundChrome` strings;
//! Environment Summary + right-panel Background body), and
//! first-cut Environment info-button a11y + dropdown-menu header /
//! menu-item chrome plus the dropdown Background section header
//! (same `EnvironmentChrome` strings), and first-cut
//! Settings Skills filter placeholder plus Settings Usage Projects
//! search-field placeholder + a11y label and empty-state No project
//! usage / No matching projects (same `FilterChrome` strings), and first-cut Files
//! right-panel file-preview toolbar / find-replace / discard /
//! truncated·binary chrome (same `FilePreviewChrome` strings), and
//! first-cut Files preview error/save Cannot read file / File not
//! found / Cannot save truncated preview — open in editor /
//! Cannot save binary file / Cannot save file (same
//! `FilePreviewErrorChrome` strings; distinct from
//! `FilePreviewChrome` / `FilePreviewFindMatchChrome`; paths /
//! file contents stay English/data), and
//! first-cut Commit message composer chrome (same `CommitChrome`
//! strings), and first-cut composer branch-picker dropdown plus
//! New branch / New worktree / Delete branch / Push-confirm
//! composer-row chrome (same `BranchChrome` strings; Force / Push /
//! Cancel reuse `CommitChrome`), and first-cut composer workspace
//! picker Work in / Local / New worktree (same `WorkspaceChrome`
//! strings; worktree stays Latin in zh-CN / ja) plus Work-in Base
//! (reuses `BranchChrome.base`) and project-row Local (reuses
//! `WorkspaceChrome.local`) plus Send-prep attach status Creating
//! worktree… / Could not create worktree. (same
//! `WorktreeStatusChrome` strings; distinct from `WorkspaceChrome`
//! picker labels / `BranchChrome` / `CommitChrome`
//! pushing/committing; worktree stays Latin in zh-CN / ja) plus
//! branch-menu attach-status Could not check out branch. / Already
//! checked out in another worktree. / Could not create branch. /
//! Could not delete branch. / Could not fetch. / Could not push.
//! (same `BranchOpStatusChrome` strings; distinct from
//! `BranchChrome` / `CommitChrome` / `WorktreeStatusChrome` /
//! `WorkspaceChrome`; worktree stays Latin in zh-CN / ja) plus
//! Commit… attach-status Enter a commit message. / Could not
//! commit. / Nothing staged to commit. / Could not generate a
//! commit message. (same `CommitAttachStatusChrome` strings;
//! distinct from `CommitChrome` pending Generating… /
//! `BranchOpStatusChrome` / `WorktreeStatusChrome` /
//! `WorkspaceChrome`) plus daemon-dir
//! in-app browser Up / Home / Choose / Loading… (same `DaemonDirChrome`
//! strings; Cancel reuses `CommitChrome`) plus session-switcher
//! title / Switch (same `SwitcherChrome` strings; Cancel reuses
//! `CommitChrome`) plus Settings General / project-edit Workspace path
//! placeholders (same `WorkspacePathChrome` strings) plus transcript
//! Find placeholder (reuses `FilePreviewChrome.find`) and Find in
//! transcript a11y (reuses `Palette.find_in_transcript`) plus find-bar
//! Previous match / Next match / Close find a11y (same
//! `FindBarChrome` strings; distinct from `FilePreviewChrome`
//! previous/next/close file-find so transcript find-bar chrome stays
//! independently evolvable; `on-press` stays `find_prev` /
//! `find_next` / `close_find`) plus find-bar muted match-position
//! No matches / k of N (same `FindMatchChrome` strings; distinct from
//! `FindBarChrome` / `FilePreviewChrome` / `TranscriptTurnChrome.match`
//! / `FilePreviewFindMatchChrome` so transcript find-match chrome
//! stays independently evolvable; numbers stay Latin) plus Files
//! preview find muted match-position `n of m · L#line` / `invalid`
//! / `0` (same `FilePreviewFindMatchChrome` strings; distinct from
//! `FindMatchChrome` / `FilePreviewChrome` so file-preview match
//! chrome stays independently evolvable; numbers stay Latin; `+`
//! cap and ` · ` stay) plus header Copy session a11y and
//! Fork / Rewind button chrome (same `HeaderSessionChrome` strings;
//! distinct from `Palette.copy_session_id` / `TranscriptTurnChrome`
//! so header session chrome stays independently
//! evolvable; `on-press` stays `copy_session` / `fork` / `rewind`)
//! plus transcript turn You said / Assistant said a11y (same
//! `TranscriptRoleChrome` strings; distinct from
//! `HeaderSessionChrome` / `TranscriptTurnChrome` so
//! transcript role chrome stays independently evolvable)
//! plus transcript turn Match chip and per-turn Copy / Fork
//! chrome (same `TranscriptTurnChrome` strings; distinct from
//! `HeaderSessionChrome` / `TranscriptRoleChrome` /
//! `Palette.copy_session_id` / `FindBarChrome` /
//! `FilePreviewChrome` so transcript turn action chrome stays
//! independently evolvable; `on-press` stays `copy_turn:{t.id}` /
//! `fork_turn:{t.id}`)
//! plus composer queue card Queued / Dismiss all / Remove queued
//! and transcript Jump to latest (same `QueueChrome` strings;
//! distinct from `EnvironmentChrome.dismiss_all_settled` /
//! `BackgroundChrome` Dismiss* / `TranscriptTurnChrome` /
//! `HeaderSessionChrome` so queue chrome stays independently
//! evolvable; `on-press` stays `jump_latest` / `clear_queue` /
//! `remove_queued:{id}` / `edit_queued:{id}`; queued message
//! body text stays data)
//! plus session
//! title untitled placeholders (same `UntitledChrome` strings; catalog
//! titles stay English `untitled`) plus header untitled display title
//! New task (same `HeaderUntitledChrome` strings; distinct from
//! `Sidebar.new_task` so header untitled chrome stays independently
//! evolvable; catalog titles stay English `untitled`) plus Settings
//! General daemon address
//! placeholder (same `DaemonAddressChrome` strings; Latin `host:port`
//! in every locale) plus Settings General field labels Default model /
//! Access mode / Interaction / Effort / Last project path / Daemon
//! address and Default model / Effort placeholders (same
//! `SettingsGeneralChrome` strings; Latin `FX_MODEL` in every locale)
//! plus composer Image path placeholder, Pick image button,
//! Attach image a11y, Clear image a11y, Attached image a11y,
//! Goal Status picker placeholder / empty label, and Commands
//! toggle chip (same `ComposerChrome` strings; Commands wording
//! matches `PaletteChrome.commands` but stays a separate field so
//! the composer chip does not couple to the palette overlay
//! header; Clear image `on-press` stays `clear_image_attach`)
//! plus composer primary Send / Stop a11y labels and visible
//! `send_label` (same `ComposerSendStopChrome` strings; idle
//! `send` / streaming `stop`; distinct from
//! `BackgroundChrome.daemon_stop` / `ComposerChrome` so composer
//! Send/Stop stay independently evolvable; `on-press` stays
//! `send` / `stop_turn`; icon-button a11y stays
//! `composer_send_label` / `composer_stop_label`)
//! plus composer textarea idle / streaming placeholders (same
//! `ComposerPlaceholderChrome` strings; distinct from
//! `QueueChrome` / `ComposerChrome` / `ComposerSendStopChrome` so
//! composer placeholders stay independently evolvable; `on-input`
//! / on-submit stay `draft_edit` / `composer_enter`; draft text
//! stays data)
//! plus empty-transcript welcome title / subtitle (same
//! `WelcomeChrome` strings; distinct from `HeaderUntitledChrome` /
//! `ComposerPlaceholderChrome` / `QueueChrome` so welcome wording
//! stays independently evolvable; real session titles and typed
//! draft text stay data)
//! plus Browser address-field Address label and
//! `https://example.com` placeholder (same `BrowserAddressChrome`
//! strings; Latin `https://example.com` in every locale)
//! plus Browser toolbar Back / Forward / Reload / Hard Reload /
//! Navigate and Secure / Not secure a11y (same
//! `BrowserToolbarChrome` strings)
//! plus Browser start-page globe icon a11y (same
//! `BrowserStartIconChrome` strings; distinct from
//! `RightPanelChrome.browse_the_web` / `BrowserToolbarChrome` /
//! `BrowserAddressChrome` so start-page icon a11y stays independently
//! evolvable)
//! plus sidebar titlebar session-history Back / Forward a11y
//! (same `SidebarHistoryChrome` strings)
//! plus Browser / Terminal multi-session New / Close chips
//! (same `SessionChipsChrome` strings)
//! plus Terminal Restart (same `TerminalRestartChrome` strings)
//! plus Settings Computer Use page body chrome (same
//! `ComputerUseChrome` strings; title wording matches `Chrome.computer_use`
//! but stays a dedicated field so the page title does not couple to
//! Settings nav; wire ids stay English)
//! plus Settings Usage Daily / Monthly / Projects view chips,
//! Daily / Projects window chips, Cost|Tokens metric chips, and
//! Daily-only Model|Days breakdown chips (same `UsageViewChrome`
//! strings; `7d` / `30d` / `90d` stay Latin in every locale; Projects
//! stays a dedicated field so the view chip does not couple to other
//! Projects wording; Days stays distinct from Daily; wire ids stay
//! English)
//! plus Settings Providers / Skills / Usage Refresh (same
//! `SettingsRefreshChrome` strings; one Refresh field shared by all
//! three Settings pages; wire ids / on-press stay English)
//! plus composer Refresh goal / plan Refresh (same
//! `GoalPlanRefreshChrome` strings; distinct from Settings Refresh
//! so the plan-meter short verb and Refresh goal stay independently
//! evolvable; wire ids / on-press stay English)
//! plus composer Set goal / Clear goal (same
//! `GoalActionChrome` strings; distinct from Refresh goal /
//! plan Refresh so the set/clear verbs stay independently
//! evolvable; wire ids / on-press stay English)
//! plus composer Goal empty label `No goal` (same
//! `GoalEmptyChrome` strings; distinct from Set/Clear /
//! Refresh goal / Goal Status so the empty label stays
//! independently evolvable; objective text stays data)
//! plus composer Goal Status display labels Active / Paused /
//! Blocked / Usage limited / Budget limited / Complete (same
//! `GoalStatusChrome` strings; distinct from ComposerChrome
//! Status placeholder / GoalActionChrome / GoalEmptyChrome /
//! GoalPlanRefreshChrome / BackgroundChrome settled_completed
//! so Goal Status stays independently evolvable; wire ids /
//! on-press `pick_goal_status` / stored session status stay
//! English)
//! plus Settings Usage Cost quality / LiteLLM Rates status /
//! five-tile metric-strip labels (same `UsageCostQualityChrome`
//! strings; distinct from UsageViewChrome Cost|Tokens chips so
//! quality / rates / tile labels stay independently evolvable;
//! `token` stays Latin in zh-CN; daemon `errors[]` notice text
//! stays English data this cut)
//! plus Settings Usage Daily scan-footer unit labels (same
//! `UsageScanFooterChrome` strings; ` · ` separators and Latin
//! `{d:.1}s` stay; distinct from UsageCostQualityChrome so the
//! footer units stay independently evolvable)
//! plus Settings Usage sessions unit and connect-daemon hint (same
//! `UsageSessionsChrome` strings; `{d} sessions` / ` · {d} sessions`
//! keep numbers and ` · `; distinct from UsageScanFooterChrome so
//! the sessions unit stays independently evolvable; daemon
//! `errors[]` notice text stays English data this cut)
//! plus composer Usage meter plan-usage chrome (same
//! `UsageMeterChrome` strings; distinct from UsageSessionsChrome so
//! the Settings Usage history connect hint stays independently
//! evolvable; numbers, Latin `m`/`h`/`d`, and ` · ` stay; daemon
//! plan window labels / planLabel stay English data this cut)
//! plus Settings Usage local session cards and the composer Usage
//! meter panel Context window heading (same `UsageLocalChrome`
//! strings; distinct from `Chrome.usage` / UsageMeterChrome /
//! UsageSessionsChrome / UsageViewChrome / FilterChrome
//! no_project_usage so local session chrome stays independently
//! evolvable; wire ids / numeric usage values stay English/data)
//! plus Settings Providers Available / Not found, Enable /
//! Disable, Use for this session, Copy install command / Copy login
//! command, and First-party default (same `ProvidersChrome` strings;
//! distinct from `ComputerUseChrome` Enable / Off so Providers
//! Enable/Disable stay independently evolvable; provider wire
//! names, binary paths, install/login commands, and on-press ids
//! stay English)
//! plus Settings Providers detail transport notes /
//! fx_login_note / fx_login_codex_note / other_install_hint and
//! `Binary:` / `Path:` prefixes (same `ProvidersDetailChrome`
//! strings; distinct from `ProvidersChrome` so status / Enable /
//! Apply stay independently evolvable; wire names / binary paths /
//! install/login commands stay English)
//! plus Settings Skills empty-state Open a project / No skills
//! found (same `SkillsEmptyChrome` strings; distinct from
//! FilterChrome / RightPanelChrome so Skills empty stays
//! independently evolvable; composer `$` insert empty reuses the
//! same hint; wire ids stay English)
//! plus OS folder-dialog prompts / missing-picker
//! status (same `OsFolderDialogChrome` strings; osascript /
//! PowerShell / zenity `--title` / kdialog `--title` at spawn) plus
//! OS image-dialog prompts / missing-picker status (same
//! `OsImageDialogChrome` strings; osascript / PowerShell / zenity
//! `--title` / kdialog `--title` at spawn) live here so `main.zig`
//! does not grow. Palette ids / `PaletteAction` /
//! keywords stay English.
//! Wire `access_mode` ids stay `ask` / `auto` / `fullAccess`. Wire
//! `reasoning_effort` ids stay `auto` / `none` / `minimal` / `low` /
//! `medium` / `high` / `xhigh` / `max`. Wire `interaction_mode` ids
//! stay `build` / `plan`. Wire `right_panel_tab` ids stay `files` /
//! `diff` / `browser` / `terminal` / `background`. Diff filter
//! `on-input` and filter text stay English. Open in browser / Open
//! in Terminal `on-press` stay `open_url` / `open_terminal`. Composer
//! Pick folder / Reveal folder / Open in Editor / Copy path
//! `on-press` stay `pick_folder` / `reveal_folder` / `open_editor` /
//! `copy_project_path`. Review Diff Cancel / source chips / gap
//! expand `on-press` stay `close_review_diff` /
//! `set_review_diff_source_*` / `expand_review_diff_gap_*`. Background
//! Stop / Dismiss `on-press` stay `environment_stop_background:*` /
//! `open_background_work:*`. Environment info / menu `on-press`
//! stay `toggle_environment_summary` / `close_environment_summary` /
//! `environment_commit_or_push` / `environment_compare` /
//! `environment_copy_task_id` / `environment_copy_agent_thread_id` /
//! `environment_dismiss_settled_background`. Skills / Usage Projects
//! filter `on-input` stay `skills_filter_edit` /
//! `usage_project_filter_edit`; filter text stays English (user-typed).
//! File-preview toolbar `on-press` / `on-input` stay English
//! (`file_preview_save` / `close_right_panel_file_preview` /
//! `toggle_file_preview_find_replace` / `file_preview_find_edit` /
//! …). Commit composer `on-press` / `on-input` stay English
//! (`git_commit_edit` / `toggle_git_commit_include_unstaged` /
//! `toggle_git_commit_amend` / `toggle_git_push_force` /
//! `confirm_git_commit` / `confirm_git_commit_and_push` /
//! `confirm_git_commit_push` / `cancel_git_commit`). Branch picker
//! / create / delete / push-confirm `on-press` / `on-input` stay
//! English (`toggle_git_branch_picker` / `git_branch_search_edit` /
//! `start_git_branch_create` / `start_git_worktree_create` /
//! `start_git_branch_delete` / `start_git_fetch` /
//! `start_git_commit` / `start_git_push` / `git_branch_create_edit` /
//! `git_worktree_create_edit` / `confirm_git_branch_create` /
//! `cancel_git_branch_create` / `toggle_git_worktree_base_picker` /
//! `confirm_git_worktree_create` / `cancel_git_worktree_create` /
//! `toggle_git_branch_delete_force` / `confirm_git_branch_delete` /
//! `cancel_git_branch_delete` / `confirm_git_push` /
//! `cancel_git_push`). Branch names and search typed text stay
//! English (data). Workspace picker `on-press` stays English
//! (`toggle_workspace_picker` / `close_workspace_picker` /
//! `pick_workspace_local` / `pick_workspace_new_worktree`).
//! Send-prep Creating worktree… / Could not create worktree.
//! follow the resolved locale this cut (same `WorktreeStatusChrome`
//! strings; distinct from `WorkspaceChrome` / `BranchChrome` /
//! `CommitChrome`; worktree stays Latin in zh-CN / ja).
//! Branch-op attach status Could not check out branch. / Already
//! checked out in another worktree. / Could not create branch. /
//! Could not delete branch. / Could not fetch. / Could not push.
//! follow the resolved locale this cut (same `BranchOpStatusChrome`
//! strings; distinct from `BranchChrome` / `CommitChrome` /
//! `WorktreeStatusChrome` / `WorkspaceChrome`; worktree stays Latin
//! in zh-CN / ja).
//! Commit… attach status Enter a commit message. / Could not
//! commit. / Nothing staged to commit. / Could not generate a
//! commit message. follow the resolved locale this cut (same
//! `CommitAttachStatusChrome` strings; distinct from `CommitChrome`
//! pending Generating… / `BranchOpStatusChrome` /
//! `WorktreeStatusChrome` / `WorkspaceChrome`).
//! Daemon-dir browser `on-press` stays English
//! (`daemon_dir_browser_up` / `daemon_dir_browser_home` /
//! `confirm_daemon_dir_browser` / `cancel_daemon_dir_browser`).
//! Palette footer / switcher `on-press` / on-dismiss stay English
//! (`palette_cancel` / `palette_confirm` / `switcher_cancel` /
//! `switcher_confirm`). Workspace path `on-input` stays English
//! (`settings_project_edit` / `project_path_edit`); typed path text
//! stays English (data). Transcript Find `on-input` / on-submit /
//! Previous / Next / Close `on-press` stay English (`find_edit` /
//! `find_next` / `find_prev` / `close_find`); typed query stays
//! English (data). Find-bar muted match-position No matches / k of N
//! follow the resolved locale this cut (same `FindMatchChrome`
//! strings). Files preview find muted match-position
//! `n of m · L#line` / `invalid` / `0` follow the resolved locale
//! this cut (same `FilePreviewFindMatchChrome` strings; `on-press`
//! / on-input / find query / replace text stay English). Files
//! preview error/save Cannot read file / File not found / Cannot
//! save truncated preview — open in editor / Cannot save binary
//! file / Cannot save file follow the resolved locale this cut
//! (same `FilePreviewErrorChrome` strings; distinct from
//! `FilePreviewChrome` / `FilePreviewFindMatchChrome`; paths /
//! file contents stay English/data). Header
//! Copy session / Fork / Rewind `on-press`
//! stay English (`copy_session` / `fork` / `rewind`). Transcript
//! turn You said / Assistant said a11y follow the resolved locale
//! this cut (same `TranscriptRoleChrome` strings). Per-turn
//! transcript Match / Copy / Fork follow the resolved locale this
//! cut (same `TranscriptTurnChrome` strings; `on-press` stays
//! `copy_turn:{t.id}` / `fork_turn:{t.id}`). Composer queue Queued /
//! Dismiss all / Remove queued plus Jump to latest follow the
//! resolved locale this cut (same `QueueChrome` strings; `on-press`
//! stays `jump_latest` / `clear_queue` / `remove_queued:{id}` /
//! `edit_queued:{id}`; queued message body text stays data). Header
//! untitled New task follows the resolved locale this cut (same
//! `HeaderUntitledChrome` strings; distinct from `Sidebar.new_task`;
//! `on-press` stays `edit_session_title`). Session title
//! `on-input` stays English
//! (`session_title_edit`). Daemon address `on-input` stays English
//! (`settings_daemon_edit`). Settings General field labels / Default
//! model / Effort placeholders (same `SettingsGeneralChrome` strings;
//! Latin `FX_MODEL` in every locale) follow the resolved locale this
//! cut. Settings model `on-input` stays English
//! (`settings_model_edit`); effort picker `on-press` stays English
//! (`toggle_settings_effort_picker`). Composer Image path `on-input`
//! stays English (`image_path_edit`); Goal Status picker `on-press`
//! stays English (`toggle_goal_status_picker` / `pick_goal_status`); Pick image / Attach
//! image `on-press` stays English (`pick_image`); Clear image
//! `on-press` stays English (`clear_image_attach`); Commands chip
//! `on-press` stays English (`toggle_commands`); composer Send /
//! Stop `on-press` stay English (`send` / `stop_turn`). Composer
//! textarea idle / streaming placeholders follow the resolved
//! locale this cut (same `ComposerPlaceholderChrome` strings;
//! `on-input` / on-submit stay English (`draft_edit` /
//! `composer_enter`); draft text stays data). Empty-transcript
//! welcome title / subtitle follow the resolved locale this cut
//! (same `WelcomeChrome` strings; distinct from
//! `HeaderUntitledChrome` / `ComposerPlaceholderChrome` /
//! `QueueChrome`; real session titles and typed draft text stay
//! data). Typed path text stays
//! English (data). ThreadGoalStatus wire names stay English;
//! picker-row / selected-chip display labels live in
//! `GoalStatusChrome`. Browser
//! address `on-input` / on-submit stay English (`browser_url_edit` /
//! `browser_navigate`). Browser toolbar `on-press` stays English
//! (`browser_back` / `browser_forward` / `browser_reload` /
//! `browser_hard_reload` / `browser_navigate`). Browser start-page globe icon a11y follows
//! the resolved locale this cut (same `BrowserStartIconChrome`
//! strings). Sidebar titlebar history `on-press` stays
//! English (`history_back` / `history_forward`). Browser / Terminal
//! session-chip `on-press` stays English (`new_browser` /
//! `close_browser` / `new_terminal` / `close_terminal`). Terminal
//! Restart `on-press` stays English (`restart_terminal`). Settings
//! Usage view / window chip `on-press` stay English
//! (`set_usage_view_daily` / `set_usage_view_monthly` /
//! `set_usage_view_projects` / `set_usage_window_7d` /
//! `set_usage_window_30d` / `set_usage_window_90d` /
//! `set_usage_window_this_month` / `set_usage_window_last_month`).
//! Settings Usage Cost|Tokens / Model|Days chip `on-press` stay
//! English (`set_usage_share_cost` / `set_usage_share_tokens` /
//! `set_usage_breakdown_model` / `set_usage_breakdown_days`).
//! Settings Providers / Skills / Usage Refresh `on-press` stay
//! English (`refresh_providers` / `refresh_skills` /
//! `refresh_usage_history`). Settings Providers Apply / Copy install /
//! Copy login `on-press` stay English (`apply_session_provider` /
//! `copy_fx_install` / `copy_fx_login`). Refresh goal / plan Refresh `on-press`
//! stay English (`goal_refresh` / `refresh_plan_usage`). Set goal /
//! Clear goal `on-press` stay English (`goal_set` / `goal_clear`).
//! Composer Goal empty label (`No goal`) follows the resolved
//! locale this cut (same `GoalEmptyChrome` strings; objective
//! text stays data). Composer Goal Status display labels
//! follow the resolved locale this cut (same
//! `GoalStatusChrome` strings; distinct from ComposerChrome
//! Status placeholder; wire ids / on-press `pick_goal_status`
//! / stored session status stay English).
//! Settings Usage local session cards (Context window / No
//! context usage reported yet / Thread goal tokens / No thread
//! goal usage) plus the composer Usage meter panel Context
//! window heading follow the resolved locale this cut (same
//! `UsageLocalChrome` strings; distinct from `Chrome.usage` /
//! UsageMeterChrome / UsageSessionsChrome / UsageViewChrome /
//! FilterChrome no_project_usage; wire ids / numeric usage
//! values stay English/data).
//! Typed URL text
//! stays data. Parked `home_url`
//! / scene URLs stay data. OS
//! folder-dialog prompts / missing-picker
//! status (same `OsFolderDialogChrome` strings; osascript / PowerShell
//! / zenity `--title` / kdialog `--title` at spawn) follow the
//! resolved locale this cut. OS image-dialog prompts / missing-picker
//! status (same `OsImageDialogChrome` strings; osascript / PowerShell
//! / zenity `--title` / kdialog `--title` at spawn) follow the
//! resolved locale this cut. Aa / Ab / .* glyphs stay. Path text and
//! body content stay data.
//! Not rust_i18n, not YAML catalogs, not full-app translation, not
//! tz-aware grouping.

const std = @import("std");

/// Settings → Appearance chrome language. Default System. Missing /
/// unknown persist strings load as System. Explicit chips are
/// autonyms (English / 简体中文 / 日本語) in every locale.
pub const LanguagePreference = enum {
    system,
    english,
    simplified_chinese,
    japanese,

    pub fn persistName(self: LanguagePreference) []const u8 {
        return switch (self) {
            .system => "system",
            .english => "english",
            .simplified_chinese => "simplified-chinese",
            .japanese => "japanese",
        };
    }

    pub fn fromPersist(value: []const u8) LanguagePreference {
        if (std.mem.eql(u8, value, "english")) return .english;
        if (std.mem.eql(u8, value, "simplified-chinese")) return .simplified_chinese;
        if (std.mem.eql(u8, value, "japanese")) return .japanese;
        return .system;
    }
};

pub const english_autonym = "English";
pub const simplified_chinese_autonym = "简体中文";
pub const japanese_autonym = "日本語";

pub const Chrome = struct {
    settings: []const u8,
    general: []const u8,
    appearance: []const u8,
    providers: []const u8,
    skills: []const u8,
    usage: []const u8,
    computer_use: []const u8,
    theme: []const u8,
    light: []const u8,
    dark: []const u8,
    language: []const u8,
    language_description: []const u8,
    system: []const u8,
    os_caption_hc_on_rm_on: []const u8,
    os_caption_hc_on_rm_off: []const u8,
    os_caption_hc_off_rm_on: []const u8,
    os_caption_hc_off_rm_off: []const u8,
};

const chrome_en: Chrome = .{
    .settings = "Settings",
    .general = "General",
    .appearance = "Appearance",
    .providers = "Providers",
    .skills = "Skills",
    .usage = "Usage",
    .computer_use = "Computer Use",
    .theme = "Theme",
    .light = "Light",
    .dark = "Dark",
    .language = "Language",
    .language_description = "Language for Faku chrome. System follows LC_ALL / LC_MESSAGES / LANG.",
    .system = "System",
    .os_caption_hc_on_rm_on = "High contrast on, reduce motion on. These follow the OS.",
    .os_caption_hc_on_rm_off = "High contrast on, reduce motion off. These follow the OS.",
    .os_caption_hc_off_rm_on = "High contrast off, reduce motion on. These follow the OS.",
    .os_caption_hc_off_rm_off = "High contrast off, reduce motion off. These follow the OS.",
};

const chrome_zh_cn: Chrome = .{
    .settings = "设置",
    .general = "通用",
    .appearance = "外观",
    .providers = "提供商",
    .skills = "技能",
    .usage = "用量",
    .computer_use = "电脑使用",
    .theme = "主题",
    .light = "浅色",
    .dark = "深色",
    .language = "语言",
    .language_description = "Faku 界面语言。系统跟随 LC_ALL / LC_MESSAGES / LANG。",
    .system = "系统",
    .os_caption_hc_on_rm_on = "高对比度开，减弱动态效果开。这些跟随操作系统。",
    .os_caption_hc_on_rm_off = "高对比度开，减弱动态效果关。这些跟随操作系统。",
    .os_caption_hc_off_rm_on = "高对比度关，减弱动态效果开。这些跟随操作系统。",
    .os_caption_hc_off_rm_off = "高对比度关，减弱动态效果关。这些跟随操作系统。",
};

const chrome_ja: Chrome = .{
    .settings = "設定",
    .general = "一般",
    .appearance = "外観",
    .providers = "プロバイダー",
    .skills = "スキル",
    .usage = "使用量",
    .computer_use = "コンピュータ使用",
    .theme = "テーマ",
    .light = "ライト",
    .dark = "ダーク",
    .language = "言語",
    .language_description = "Faku の画面言語です。システムは LC_ALL / LC_MESSAGES / LANG に従います。",
    .system = "システム",
    .os_caption_hc_on_rm_on = "ハイコントラストオン、動きを減らすオン。これらは OS に従います。",
    .os_caption_hc_on_rm_off = "ハイコントラストオン、動きを減らすオフ。これらは OS に従います。",
    .os_caption_hc_off_rm_on = "ハイコントラストオフ、動きを減らすオン。これらは OS に従います。",
    .os_caption_hc_off_rm_off = "ハイコントラストオフ、動きを減らすオフ。これらは OS に従います。",
};

/// First-cut sidebar date-bucket titles plus the static relative-time
/// words that are already string literals. Chrome unassign Today reuses
/// `today`. Numeric `{d}m` / `{d}h` / `{d}d` / `YYYY-MM-DD` stay
/// untranslated. Same resolve path as Chrome.
pub const Dates = struct {
    today: []const u8,
    yesterday: []const u8,
    this_week: []const u8,
    this_month: []const u8,
    this_year: []const u8,
    older: []const u8,
    just_now: []const u8,
};

const dates_en: Dates = .{
    .today = "Today",
    .yesterday = "Yesterday",
    .this_week = "This week",
    .this_month = "This month",
    .this_year = "This year",
    .older = "Older",
    .just_now = "just now",
};

const dates_zh_cn: Dates = .{
    .today = "今日",
    .yesterday = "昨天",
    .this_week = "本周",
    .this_month = "本月",
    .this_year = "今年",
    .older = "更早",
    .just_now = "刚刚",
};

const dates_ja: Dates = .{
    .today = "今日",
    .yesterday = "昨日",
    .this_week = "今週",
    .this_month = "今月",
    .this_year = "今年",
    .older = "以前",
    .just_now = "たった今",
};

/// First-cut high-traffic sidebar chrome. Same resolve path as Chrome /
/// Dates. Search is the sidebar entry and the command-palette overlay
/// placeholder (same wording). New folder is the button label and the
/// folder title-field placeholder; stored catalog titles stay English
/// `New folder` (data, not chrome). Folder context-menu Rename / Delete
/// are chrome (plain Delete, not `delete_folder`). Session context-menu
/// Rename reuses `rename` (same wording). Session Remove is distinct
/// from folder Delete (`remove` vs `delete`); trash a11y is
/// `remove_session` ("Remove session"). Folder-header chevron a11y is
/// `expand_folder` / `collapse_folder` (distinct from
/// `collapse_all_folders`). Palette Collapse all folders reuses
/// `collapse_all_folders`. Palette New Task / Settings reuse
/// `new_task` / `Chrome.settings`. Remaining palette action labels
/// live in `Palette` (same resolve path). Composer Ask / Auto /
/// Full access live in `Access` (same resolve path). Composer
/// effort chip / Settings General effort labels live in `Effort`
/// (same resolve path). Composer Build / Plan live in `Interaction`
/// (same resolve path).
pub const Sidebar = struct {
    new_task: []const u8,
    search: []const u8,
    new_folder: []const u8,
    collapse_all_folders: []const u8,
    expand_folder: []const u8,
    collapse_folder: []const u8,
    delete_folder: []const u8,
    rename: []const u8,
    delete: []const u8,
    remove: []const u8,
    remove_session: []const u8,
};

const sidebar_en: Sidebar = .{
    .new_task = "New Task",
    .search = "Search",
    .new_folder = "New folder",
    .collapse_all_folders = "Collapse all folders",
    .expand_folder = "Expand folder",
    .collapse_folder = "Collapse folder",
    .delete_folder = "Delete folder",
    .rename = "Rename",
    .delete = "Delete",
    .remove = "Remove",
    .remove_session = "Remove session",
};

const sidebar_zh_cn: Sidebar = .{
    .new_task = "新建任务",
    .search = "搜索",
    .new_folder = "新建文件夹",
    .collapse_all_folders = "折叠所有文件夹",
    .expand_folder = "展开文件夹",
    .collapse_folder = "折叠文件夹",
    .delete_folder = "删除文件夹",
    .rename = "重命名",
    .delete = "删除",
    .remove = "移除",
    .remove_session = "移除会话",
};

const sidebar_ja: Sidebar = .{
    .new_task = "新しいタスク",
    .search = "検索",
    .new_folder = "新しいフォルダ",
    .collapse_all_folders = "すべてのフォルダを折りたたむ",
    .expand_folder = "フォルダを展開",
    .collapse_folder = "フォルダを折りたたむ",
    .delete_folder = "フォルダを削除",
    .rename = "名前を変更",
    .delete = "削除",
    .remove = "取り除く",
    .remove_session = "セッションを取り除く",
};

/// Composer chip, access picker rows, and Settings General Ask / Auto /
/// Full access buttons. Same resolve path as Sidebar. Wire `access_mode`
/// ids stay `ask` / `auto` / `fullAccess` (plus aliases `autoAcceptEdits`
/// / `yolo`); only the chrome label translates. English matches
/// `composer.accessLabel` / `access_chip_options`.
pub const Access = struct {
    ask: []const u8,
    auto: []const u8,
    full_access: []const u8,

    /// `id` is a chip option id (`ask` / `auto` / `fullAccess`), not a
    /// persisted alias. Unknown ids fall through to Full access.
    pub fn labelForId(self: Access, id: []const u8) []const u8 {
        if (std.mem.eql(u8, id, "ask")) return self.ask;
        if (std.mem.eql(u8, id, "auto")) return self.auto;
        return self.full_access;
    }
};

const access_en: Access = .{
    .ask = "Ask",
    .auto = "Auto",
    .full_access = "Full access",
};

const access_zh_cn: Access = .{
    .ask = "询问",
    .auto = "自动",
    .full_access = "完全访问",
};

const access_ja: Access = .{
    .ask = "確認",
    .auto = "自動",
    .full_access = "フルアクセス",
};

/// Composer effort chip, effort picker rows, and Settings General effort
/// select. Same resolve path as Access. Wire `reasoning_effort` ids stay
/// `auto` / `none` / `minimal` / `low` / `medium` / `high` / `xhigh` /
/// `max`; only the chrome label translates. English matches
/// `composer.effortLabel` / `effort_chip_options`.
pub const Effort = struct {
    auto: []const u8,
    none: []const u8,
    minimal: []const u8,
    low: []const u8,
    medium: []const u8,
    high: []const u8,
    extra_high: []const u8,
    max: []const u8,

    /// `id` is a chip option id (`auto` / `none` / `minimal` / `low` /
    /// `medium` / `high` / `xhigh` / `max`). Unknown ids fall through to Auto.
    pub fn labelForId(self: Effort, id: []const u8) []const u8 {
        if (std.mem.eql(u8, id, "none")) return self.none;
        if (std.mem.eql(u8, id, "minimal")) return self.minimal;
        if (std.mem.eql(u8, id, "low")) return self.low;
        if (std.mem.eql(u8, id, "medium")) return self.medium;
        if (std.mem.eql(u8, id, "high")) return self.high;
        if (std.mem.eql(u8, id, "xhigh")) return self.extra_high;
        if (std.mem.eql(u8, id, "max")) return self.max;
        return self.auto;
    }
};

const effort_en: Effort = .{
    .auto = "Auto",
    .none = "None",
    .minimal = "Minimal",
    .low = "Low",
    .medium = "Medium",
    .high = "High",
    .extra_high = "Extra high",
    .max = "Max",
};

const effort_zh_cn: Effort = .{
    .auto = "自动",
    .none = "无",
    .minimal = "最低",
    .low = "低",
    .medium = "中",
    .high = "高",
    .extra_high = "极高",
    .max = "最大",
};

const effort_ja: Effort = .{
    .auto = "自動",
    .none = "なし",
    .minimal = "最小",
    .low = "低",
    .medium = "中",
    .high = "高",
    .extra_high = "非常に高い",
    .max = "最大",
};

/// Composer interaction chip and Settings General Build / Plan buttons.
/// Same resolve path as Effort. Wire `interaction_mode` ids stay
/// `build` / `plan`; only the chrome label translates. English matches
/// the former hardcoded composer chip / Settings General buttons.
pub const Interaction = struct {
    build: []const u8,
    plan: []const u8,

    /// `id` is a wire id (`build` / `plan`). Unknown / empty fall through to Build.
    pub fn labelForId(self: Interaction, id: []const u8) []const u8 {
        if (std.mem.eql(u8, id, "plan")) return self.plan;
        return self.build;
    }
};

const interaction_en: Interaction = .{
    .build = "Build",
    .plan = "Plan",
};

const interaction_zh_cn: Interaction = .{
    .build = "构建",
    .plan = "计划",
};

const interaction_ja: Interaction = .{
    .build = "ビルド",
    .plan = "プラン",
};

/// Command-palette action display labels for the resolved locale.
/// Same resolve path as Interaction. New Task / Settings / Collapse
/// all folders reuse `Sidebar` / `Chrome` (not duplicated here).
/// Overlay Suggested / Commands / Tasks headers and empty-state
/// lines live in `PaletteChrome` (not duplicated here). Palette ids
/// / `PaletteAction` / keywords stay English; matching still checks
/// the English spec label, the localized label, and English keywords.
/// Expand / Collapse sidebar are chrome a11y
/// (`sidebar_toggle_label`), not the palette "Toggle sidebar"
/// command name. Transcript Find a11y reuses `find_in_transcript`
/// via a distinct Model getter; palette command wiring is unchanged.
pub const Palette = struct {
    focus_composer: []const u8,
    toggle_sidebar: []const u8,
    find_in_transcript: []const u8,
    minimize: []const u8,
    maximize: []const u8,
    copy_session_id: []const u8,
    copy_provider_session_id: []const u8,
    reveal_project_folder: []const u8,
    open_project_in_terminal: []const u8,
    open_project_in_editor: []const u8,
    copy_project_path: []const u8,
    show_right_panel: []const u8,
    hide_right_panel: []const u8,
    show_browser_tab: []const u8,
    show_terminal_tab: []const u8,
    expand_sidebar: []const u8,
    collapse_sidebar: []const u8,
};

const palette_en: Palette = .{
    .focus_composer = "Focus composer",
    .toggle_sidebar = "Toggle sidebar",
    .find_in_transcript = "Find in transcript",
    .minimize = "Minimize",
    .maximize = "Maximize",
    .copy_session_id = "Copy session id",
    .copy_provider_session_id = "Copy provider session id",
    .reveal_project_folder = "Reveal project folder",
    .open_project_in_terminal = "Open project in Terminal",
    .open_project_in_editor = "Open project in Editor",
    .copy_project_path = "Copy project path",
    .show_right_panel = "Show right panel",
    .hide_right_panel = "Hide right panel",
    .show_browser_tab = "Show Browser tab",
    .show_terminal_tab = "Show Terminal tab",
    .expand_sidebar = "Expand sidebar",
    .collapse_sidebar = "Collapse sidebar",
};

const palette_zh_cn: Palette = .{
    .focus_composer = "聚焦输入框",
    .toggle_sidebar = "切换侧边栏",
    .find_in_transcript = "在记录中查找",
    .minimize = "最小化",
    .maximize = "最大化",
    .copy_session_id = "复制会话 ID",
    .copy_provider_session_id = "复制提供商会话 ID",
    .reveal_project_folder = "显示项目文件夹",
    .open_project_in_terminal = "在终端中打开项目",
    .open_project_in_editor = "在编辑器中打开项目",
    .copy_project_path = "复制项目路径",
    .show_right_panel = "显示右侧面板",
    .hide_right_panel = "隐藏右侧面板",
    .show_browser_tab = "显示浏览器标签页",
    .show_terminal_tab = "显示终端标签页",
    .expand_sidebar = "展开侧边栏",
    .collapse_sidebar = "折叠侧边栏",
};

const palette_ja: Palette = .{
    .focus_composer = "入力欄にフォーカス",
    .toggle_sidebar = "サイドバーを切り替え",
    .find_in_transcript = "記録内を検索",
    .minimize = "最小化",
    .maximize = "最大化",
    .copy_session_id = "セッション ID をコピー",
    .copy_provider_session_id = "プロバイダーセッション ID をコピー",
    .reveal_project_folder = "プロジェクトフォルダを表示",
    .open_project_in_terminal = "ターミナルでプロジェクトを開く",
    .open_project_in_editor = "エディターでプロジェクトを開く",
    .copy_project_path = "プロジェクトパスをコピー",
    .show_right_panel = "右パネルを表示",
    .hide_right_panel = "右パネルを非表示",
    .show_browser_tab = "ブラウザーのタブを表示",
    .show_terminal_tab = "ターミナルのタブを表示",
    .expand_sidebar = "サイドバーを展開",
    .collapse_sidebar = "サイドバーを折りたたむ",
};

/// Command-palette overlay section headers, empty-state lines,
/// footer Confirm, and dialog title. Same resolve path as Palette.
/// Action names stay in `Palette`; ids / `PaletteAction` / keywords
/// stay English. Footer Cancel reuses `CommitChrome.cancel`.
/// English dialog title matches the former hardcoded copy.
/// Right-panel tab button labels live in `RightPanelTabs` (not
/// duplicated here).
pub const PaletteChrome = struct {
    suggested: []const u8,
    commands: []const u8,
    tasks: []const u8,
    no_matches: []const u8,
    try_query: []const u8,
    confirm: []const u8,
    dialog_title: []const u8,
};

const palette_chrome_en: PaletteChrome = .{
    .suggested = "Suggested",
    .commands = "Commands",
    .tasks = "Tasks",
    .no_matches = "No matching tasks or commands",
    .try_query = "Try a task title, project, provider, model, or command",
    .confirm = "Confirm",
    .dialog_title = "Command palette",
};

const palette_chrome_zh_cn: PaletteChrome = .{
    .suggested = "建议",
    .commands = "命令",
    .tasks = "任务",
    .no_matches = "没有匹配的任务或命令",
    .try_query = "试试任务标题、项目、提供商、模型或命令",
    .confirm = "确认",
    .dialog_title = "命令面板",
};

const palette_chrome_ja: PaletteChrome = .{
    .suggested = "おすすめ",
    .commands = "コマンド",
    .tasks = "タスク",
    .no_matches = "一致するタスクやコマンドはありません",
    .try_query = "タスク名、プロジェクト、プロバイダー、モデル、コマンドを試す",
    .confirm = "確認",
    .dialog_title = "コマンドパレット",
};

/// Right-panel tab button labels for the resolved locale. Same resolve
/// path as PaletteChrome. Wire `right_panel_tab` ids stay `files` /
/// `diff` / `browser` / `terminal` / `background`; only the visible
/// label translates. English Diff tab reads Review (Waku
/// `right_panel.diff`), not Diff. Diff filter / Files empty
/// (including empty secondary Open a project to browse its files /
/// Loading files…) / Background empty / Browser start page /
/// Open in browser / Open in Terminal chrome live in
/// `RightPanelChrome`. Background row kind / status / stop·dismiss
/// chrome live in `BackgroundChrome`. Pane `label=` attributes stay
/// English.
pub const RightPanelTabs = struct {
    files: []const u8,
    diff: []const u8,
    browser: []const u8,
    terminal: []const u8,
    background: []const u8,
};

const right_panel_tabs_en: RightPanelTabs = .{
    .files = "Files",
    .diff = "Review",
    .browser = "Browser",
    .terminal = "Terminal",
    .background = "Background",
};

const right_panel_tabs_zh_cn: RightPanelTabs = .{
    .files = "文件",
    .diff = "审阅",
    .browser = "浏览器",
    .terminal = "终端",
    .background = "后台工作",
};

const right_panel_tabs_ja: RightPanelTabs = .{
    .files = "ファイル",
    .diff = "レビュー",
    .browser = "ブラウザ",
    .terminal = "ターミナル",
    .background = "バックグラウンド",
};

/// Right-panel Diff filter placeholder, Files/Background empty-state
/// chrome (including Files empty secondary Open a project to browse
/// its files / Loading files…), and Browser start-page / Open in
/// browser / Open in Terminal labels for the resolved locale. Same
/// resolve path as RightPanelTabs. Wire ids / on-press / filter text
/// stay English; only these visible strings translate. English Diff
/// filter reads "Filter files", not Filter. Composer Open in Terminal
/// reuses `open_in_terminal`. Background empty-state reuses
/// `no_background_work` / `no_output`; row kind / status /
/// stop·dismiss chrome live in `BackgroundChrome`.
pub const RightPanelChrome = struct {
    filter_files: []const u8,
    no_project_open: []const u8,
    open_project_to_browse_files: []const u8,
    loading_files: []const u8,
    no_background_work: []const u8,
    no_output: []const u8,
    browse_the_web: []const u8,
    address_focus_hint: []const u8,
    open_in_browser: []const u8,
    open_in_terminal: []const u8,
};

const right_panel_chrome_en: RightPanelChrome = .{
    .filter_files = "Filter files",
    .no_project_open = "No project open",
    .open_project_to_browse_files = "Open a project to browse its files",
    .loading_files = "Loading files…",
    .no_background_work = "No background work",
    .no_output = "No output",
    .browse_the_web = "Browse the web",
    .address_focus_hint = "Cmd/Ctrl-L focuses the address.",
    .open_in_browser = "Open in browser",
    .open_in_terminal = "Open in Terminal",
};

const right_panel_chrome_zh_cn: RightPanelChrome = .{
    .filter_files = "筛选文件",
    .no_project_open = "未打开项目",
    .open_project_to_browse_files = "打开项目以浏览文件",
    .loading_files = "正在加载文件…",
    .no_background_work = "没有后台工作",
    .no_output = "没有输出",
    .browse_the_web = "浏览网页",
    .address_focus_hint = "Cmd/Ctrl-L 聚焦地址栏。",
    .open_in_browser = "在浏览器中打开",
    .open_in_terminal = "在终端中打开",
};

const right_panel_chrome_ja: RightPanelChrome = .{
    .filter_files = "ファイルを絞り込む",
    .no_project_open = "プロジェクトが開かれていません",
    .open_project_to_browse_files = "プロジェクトを開いてファイルを閲覧",
    .loading_files = "ファイルを読み込み中…",
    .no_background_work = "バックグラウンド作業はありません",
    .no_output = "出力がありません",
    .browse_the_web = "ウェブを閲覧",
    .address_focus_hint = "Cmd/Ctrl-L でアドレス欄にフォーカス。",
    .open_in_browser = "ブラウザで開く",
    .open_in_terminal = "ターミナルで開く",
};

/// Composer project-row Pick folder / Reveal folder / Open in Editor /
/// Copy path for the resolved locale. Same resolve path as RightPanelChrome.
/// Open in Terminal reuses `RightPanelChrome.open_in_terminal` (not
/// duplicated here). Wire ids / on-press stay English. English matches
/// the former hardcoded composer buttons. Distinct from palette
/// `Open project in Editor` / `Reveal project folder` / `Copy project path`.
pub const ComposerProjectChrome = struct {
    pick_folder: []const u8,
    reveal_folder: []const u8,
    open_in_editor: []const u8,
    copy_path: []const u8,
};

const composer_project_chrome_en: ComposerProjectChrome = .{
    .pick_folder = "Pick folder",
    .reveal_folder = "Reveal folder",
    .open_in_editor = "Open in Editor",
    .copy_path = "Copy path",
};

const composer_project_chrome_zh_cn: ComposerProjectChrome = .{
    .pick_folder = "选择文件夹",
    .reveal_folder = "显示文件夹",
    .open_in_editor = "在编辑器中打开",
    .copy_path = "复制路径",
};

const composer_project_chrome_ja: ComposerProjectChrome = .{
    .pick_folder = "フォルダを選択",
    .reveal_folder = "フォルダを表示",
    .open_in_editor = "エディターで開く",
    .copy_path = "パスをコピー",
};

/// Review Diff header title / Cancel, source chips, and gap
/// expand Start / End / Both / All for the resolved locale. Same
/// resolve path as ComposerProjectChrome. Wire ids / on-press
/// stay English (`close_review_diff` / `set_review_diff_source_*`
/// / `expand_review_diff_gap_*`); selected-state bools stay
/// `review_diff_source_*`. English matches the former hardcoded
/// header, chips, and gap expand buttons. Title EN Review matches
/// the Diff tab (`RightPanelTabs.diff`), not Diff. Remaining hunk
/// chrome (unmodified-line gap labels, `label="Review hunk"`)
/// stays English.
pub const ReviewDiffChrome = struct {
    review_title: []const u8,
    cancel: []const u8,
    branch: []const u8,
    uncommitted: []const u8,
    staged: []const u8,
    unstaged: []const u8,
    committed: []const u8,
    last_turn: []const u8,
    gap_expand_start: []const u8,
    gap_expand_end: []const u8,
    gap_expand_both: []const u8,
    gap_expand_all: []const u8,
};

const review_diff_chrome_en: ReviewDiffChrome = .{
    .review_title = "Review",
    .cancel = "Cancel",
    .branch = "Branch",
    .uncommitted = "Uncommitted",
    .staged = "Staged",
    .unstaged = "Unstaged",
    .committed = "Committed",
    .last_turn = "Last turn",
    .gap_expand_start = "Start",
    .gap_expand_end = "End",
    .gap_expand_both = "Both",
    .gap_expand_all = "All",
};

const review_diff_chrome_zh_cn: ReviewDiffChrome = .{
    .review_title = "审阅",
    .cancel = "取消",
    .branch = "分支",
    .uncommitted = "未提交",
    .staged = "已暂存",
    .unstaged = "未暂存",
    .committed = "已提交",
    .last_turn = "上一轮",
    .gap_expand_start = "开头",
    .gap_expand_end = "末尾",
    .gap_expand_both = "两端",
    .gap_expand_all = "全部",
};

const review_diff_chrome_ja: ReviewDiffChrome = .{
    .review_title = "レビュー",
    .cancel = "キャンセル",
    .branch = "ブランチ",
    .uncommitted = "未コミット",
    .staged = "ステージ済み",
    .unstaged = "未ステージ",
    .committed = "コミット済み",
    .last_turn = "直前のターン",
    .gap_expand_start = "先頭",
    .gap_expand_end = "末尾",
    .gap_expand_both = "両端",
    .gap_expand_all = "すべて",
};

/// Background row kind / status / stop·dismiss chrome for the
/// resolved locale. Same resolve path as ReviewDiffChrome. Paints
/// Environment Summary `background_rows` and right-panel
/// `background_work_*` fields. Wire ids / on-press stay English
/// (`environment_stop_background:*` / `open_background_work:*`).
/// Empty-state No background work / No output stay on
/// `RightPanelChrome`. Environment info-button a11y + dropdown
/// header / menu-item chrome live in `EnvironmentChrome`. English
/// matches the former hardcoded constants. Custom daemon titles
/// are data, not chrome.
pub const BackgroundChrome = struct {
    kind_process: []const u8,
    kind_monitor: []const u8,
    kind_subagent: []const u8,
    process_row: []const u8,
    settled_completed: []const u8,
    settled_stopped: []const u8,
    settled_failed: []const u8,
    live_running: []const u8,
    live_monitoring: []const u8,
    live_stopping: []const u8,
    process_stop: []const u8,
    monitor_stop: []const u8,
    monitor_dismiss: []const u8,
    subagent_stop: []const u8,
    subagent_dismiss: []const u8,
    daemon_stop: []const u8,
    daemon_dismiss: []const u8,
};

pub const background_chrome_en: BackgroundChrome = .{
    .kind_process = "Process",
    .kind_monitor = "Monitor",
    .kind_subagent = "Subagent",
    .process_row = "Agent turn",
    .settled_completed = "Completed",
    .settled_stopped = "Stopped",
    .settled_failed = "Failed",
    .live_running = "Running",
    .live_monitoring = "Monitoring",
    .live_stopping = "Stopping",
    .process_stop = "Stop agent",
    .monitor_stop = "Stop monitor",
    .monitor_dismiss = "Dismiss monitor",
    .subagent_stop = "Stop subagent",
    .subagent_dismiss = "Dismiss subagent",
    .daemon_stop = "Stop",
    .daemon_dismiss = "Dismiss",
};

const background_chrome_zh_cn: BackgroundChrome = .{
    .kind_process = "进程",
    .kind_monitor = "监视器",
    .kind_subagent = "子代理",
    .process_row = "代理轮次",
    .settled_completed = "已完成",
    .settled_stopped = "已停止",
    .settled_failed = "失败",
    .live_running = "运行中",
    .live_monitoring = "监视中",
    .live_stopping = "正在停止",
    .process_stop = "停止代理",
    .monitor_stop = "停止监视器",
    .monitor_dismiss = "关闭监视器",
    .subagent_stop = "停止子代理",
    .subagent_dismiss = "关闭子代理",
    .daemon_stop = "停止",
    .daemon_dismiss = "关闭",
};

const background_chrome_ja: BackgroundChrome = .{
    .kind_process = "プロセス",
    .kind_monitor = "モニター",
    .kind_subagent = "サブエージェント",
    .process_row = "エージェントのターン",
    .settled_completed = "完了",
    .settled_stopped = "停止済み",
    .settled_failed = "失敗",
    .live_running = "実行中",
    .live_monitoring = "監視中",
    .live_stopping = "停止中",
    .process_stop = "エージェントを停止",
    .monitor_stop = "モニターを停止",
    .monitor_dismiss = "モニターを閉じる",
    .subagent_stop = "サブエージェントを停止",
    .subagent_dismiss = "サブエージェントを閉じる",
    .daemon_stop = "停止",
    .daemon_dismiss = "閉じる",
};

/// Environment info-button a11y label and dropdown-menu header +
/// menu-item chrome for the resolved locale. Same resolve path as
/// BackgroundChrome. Wire ids / on-press stay English
/// (`toggle_environment_summary` / `close_environment_summary` /
/// `environment_commit_or_push` / `environment_compare` /
/// `environment_copy_task_id` / `environment_copy_agent_thread_id` /
/// `environment_dismiss_settled_background`). English matches the
/// former hardcoded copy. Title EN Environment is also the a11y
/// label. Dropdown Background section header lives here (EN matches
/// `RightPanelTabs.background`; dedicated field so Environment chrome
/// stays self-contained). Row chrome lives in `BackgroundChrome`.
pub const EnvironmentChrome = struct {
    environment: []const u8,
    commit_or_push: []const u8,
    compare: []const u8,
    copy_task_id: []const u8,
    copy_agent_thread_id: []const u8,
    dismiss_all_settled: []const u8,
    background_section: []const u8,
};

const environment_chrome_en: EnvironmentChrome = .{
    .environment = "Environment",
    .commit_or_push = "Commit or Push",
    .compare = "Compare",
    .copy_task_id = "Copy task ID",
    .copy_agent_thread_id = "Copy agent CLI thread ID",
    .dismiss_all_settled = "Dismiss all settled",
    .background_section = "Background",
};

const environment_chrome_zh_cn: EnvironmentChrome = .{
    .environment = "环境",
    .commit_or_push = "提交或推送",
    .compare = "比较",
    .copy_task_id = "复制任务 ID",
    .copy_agent_thread_id = "复制代理 CLI 线程 ID",
    .dismiss_all_settled = "关闭全部已结束项",
    .background_section = "后台工作",
};

const environment_chrome_ja: EnvironmentChrome = .{
    .environment = "環境",
    .commit_or_push = "コミットまたはプッシュ",
    .compare = "比較",
    .copy_task_id = "タスク ID をコピー",
    .copy_agent_thread_id = "エージェント CLI スレッド ID をコピー",
    .dismiss_all_settled = "終了した項目をすべて閉じる",
    .background_section = "バックグラウンド",
};

/// Settings Skills filter placeholder and Settings Usage Projects
/// search-field placeholder + a11y label plus empty-state No project
/// usage / No matching projects for the resolved locale. Same
/// resolve path as EnvironmentChrome. Wire ids / on-input stay
/// English (`skills_filter_edit` / `usage_project_filter_edit`).
/// Filter text itself stays English (user-typed). English matches
/// the former hardcoded copy. No matching projects is distinct from
/// No project usage.
pub const FilterChrome = struct {
    filter_skills: []const u8,
    filter_projects: []const u8,
    no_project_usage: []const u8,
    no_matching_projects: []const u8,
};

const filter_chrome_en: FilterChrome = .{
    .filter_skills = "Filter skills",
    .filter_projects = "Filter projects",
    .no_project_usage = "No project usage",
    .no_matching_projects = "No matching projects",
};

const filter_chrome_zh_cn: FilterChrome = .{
    .filter_skills = "筛选技能",
    .filter_projects = "筛选项目",
    .no_project_usage = "没有项目用量",
    .no_matching_projects = "没有匹配的项目",
};

const filter_chrome_ja: FilterChrome = .{
    .filter_skills = "スキルを絞り込む",
    .filter_projects = "プロジェクトを絞り込む",
    .no_project_usage = "プロジェクトの使用量はありません",
    .no_matching_projects = "一致するプロジェクトはありません",
};

/// Files right-panel file-preview toolbar / find-replace / discard /
/// truncated·binary chrome for the resolved locale. Same resolve path
/// as FilterChrome. Wire ids / on-press / on-input stay English
/// (`file_preview_save` / `close_right_panel_file_preview` /
/// `toggle_file_preview_find_replace` / `file_preview_find_edit` /
/// `file_preview_find_replace_edit`). English matches the former
/// hardcoded copy. Distinct from composer `Open in Editor` (title
/// case), from `FilePreviewFindMatchChrome` (file-preview
/// `n of m · L#line` / `invalid` / `0`), and from
/// `FilePreviewErrorChrome` (Cannot read file / File not found /
/// Cannot save truncated preview — open in editor / Cannot save
/// binary file / Cannot save file). Aa / Ab / .* glyphs stay. Path text and body content stay
/// data. Transcript Find placeholder reuses `find` via a distinct
/// Model getter; a11y reuses `Palette.find_in_transcript`.
pub const FilePreviewChrome = struct {
    unsaved: []const u8,
    preview: []const u8,
    source: []const u8,
    edit: []const u8,
    save: []const u8,
    reload: []const u8,
    open_in_editor: []const u8,
    close: []const u8,
    hide_replace: []const u8,
    show_replace: []const u8,
    find: []const u8,
    find_in_file: []const u8,
    previous_file_match: []const u8,
    next_file_match: []const u8,
    close_file_find: []const u8,
    replace: []const u8,
    replace_in_file: []const u8,
    replace_all: []const u8,
    read_only: []const u8,
    discard_unsaved: []const u8,
    discard: []const u8,
    keep_editing: []const u8,
    truncated: []const u8,
    binary_file: []const u8,
};

const file_preview_chrome_en: FilePreviewChrome = .{
    .unsaved = "Unsaved",
    .preview = "Preview",
    .source = "Source",
    .edit = "Edit",
    .save = "Save",
    .reload = "Reload",
    .open_in_editor = "Open in editor",
    .close = "Close",
    .hide_replace = "Hide replace",
    .show_replace = "Show replace",
    .find = "Find",
    .find_in_file = "Find in file",
    .previous_file_match = "Previous file match",
    .next_file_match = "Next file match",
    .close_file_find = "Close file find",
    .replace = "Replace",
    .replace_in_file = "Replace in file",
    .replace_all = "Replace all",
    .read_only = "Read-only",
    .discard_unsaved = "Discard unsaved changes?",
    .discard = "Discard",
    .keep_editing = "Keep editing",
    .truncated = "Truncated — showing first 256 KB",
    .binary_file = "Binary file — not shown",
};

const file_preview_chrome_zh_cn: FilePreviewChrome = .{
    .unsaved = "未保存",
    .preview = "预览",
    .source = "源码",
    .edit = "编辑",
    .save = "保存",
    .reload = "重新加载",
    .open_in_editor = "在编辑器中打开",
    .close = "关闭",
    .hide_replace = "隐藏替换",
    .show_replace = "显示替换",
    .find = "查找",
    .find_in_file = "在文件中查找",
    .previous_file_match = "上一个文件匹配",
    .next_file_match = "下一个文件匹配",
    .close_file_find = "关闭文件查找",
    .replace = "替换",
    .replace_in_file = "在文件中替换",
    .replace_all = "全部替换",
    .read_only = "只读",
    .discard_unsaved = "放弃未保存的更改？",
    .discard = "放弃",
    .keep_editing = "继续编辑",
    .truncated = "已截断 — 仅显示前 256 KB",
    .binary_file = "二进制文件 — 未显示",
};

const file_preview_chrome_ja: FilePreviewChrome = .{
    .unsaved = "未保存",
    .preview = "プレビュー",
    .source = "ソース",
    .edit = "編集",
    .save = "保存",
    .reload = "再読み込み",
    .open_in_editor = "エディターで開く",
    .close = "閉じる",
    .hide_replace = "置換を隠す",
    .show_replace = "置換を表示",
    .find = "検索",
    .find_in_file = "ファイル内を検索",
    .previous_file_match = "前のファイル一致",
    .next_file_match = "次のファイル一致",
    .close_file_find = "ファイル検索を閉じる",
    .replace = "置換",
    .replace_in_file = "ファイル内を置換",
    .replace_all = "すべて置換",
    .read_only = "読み取り専用",
    .discard_unsaved = "未保存の変更を破棄しますか？",
    .discard = "破棄",
    .keep_editing = "編集を続ける",
    .truncated = "切り詰め済み — 先頭 256 KB を表示",
    .binary_file = "バイナリファイル — 非表示",
};

/// Files preview error/save chrome for the resolved locale. Same
/// resolve path as FilePreviewChrome. English matches the former
/// hardcoded copy (`Cannot read file` / `File not found` /
/// `Cannot save truncated preview — open in editor` / `Cannot
/// save binary file` / `Cannot save file`). Distinct from
/// `FilePreviewChrome` toolbar Unsaved / Preview / Save / …
/// Truncated — showing first 256 KB / Binary file — not shown and
/// from `FilePreviewFindMatchChrome` so file-preview error/save
/// chrome stays independently evolvable. Wire ids / on-press /
/// paths / file contents stay English/data.
pub const FilePreviewErrorChrome = struct {
    unreadable: []const u8,
    missing: []const u8,
    truncated_save: []const u8,
    binary_save: []const u8,
    cannot_save: []const u8,
};

const file_preview_error_chrome_en: FilePreviewErrorChrome = .{
    .unreadable = "Cannot read file",
    .missing = "File not found",
    .truncated_save = "Cannot save truncated preview — open in editor",
    .binary_save = "Cannot save binary file",
    .cannot_save = "Cannot save file",
};

const file_preview_error_chrome_zh_cn: FilePreviewErrorChrome = .{
    .unreadable = "无法读取文件",
    .missing = "找不到文件",
    .truncated_save = "无法保存已截断的预览 — 请在编辑器中打开",
    .binary_save = "无法保存二进制文件",
    .cannot_save = "无法保存文件",
};

const file_preview_error_chrome_ja: FilePreviewErrorChrome = .{
    .unreadable = "ファイルを読み取れません",
    .missing = "ファイルが見つかりません",
    .truncated_save = "切り詰められたプレビューは保存できません — エディターで開いてください",
    .binary_save = "バイナリファイルは保存できません",
    .cannot_save = "ファイルを保存できません",
};

/// Commit message composer chrome for the resolved locale. Same
/// resolve path as FilePreviewChrome. Paints the `git_commit_active`
/// row only. Wire ids / on-press / on-input stay English
/// (`git_commit_edit` / `toggle_git_commit_include_unstaged` /
/// `toggle_git_commit_amend` / `toggle_git_push_force` /
/// `confirm_git_commit` / `confirm_git_commit_and_push` /
/// `confirm_git_commit_push` / `cancel_git_commit`). English matches
/// the former hardcoded copy. Branch-picker `Commit…` / `Push…`
/// live in `BranchChrome`. Delete / push-confirm Force / Push /
/// Cancel reuse `force` / `push` / `cancel` here.
/// Commit attach-status Enter a commit message. / Could not
/// commit. / Nothing staged to commit. / Could not generate a
/// commit message. live in `CommitAttachStatusChrome`.
pub const CommitChrome = struct {
    commit_message: []const u8,
    include_unstaged: []const u8,
    amend: []const u8,
    force: []const u8,
    generating: []const u8,
    amending: []const u8,
    committing_and_pushing: []const u8,
    committing: []const u8,
    pushing: []const u8,
    commit: []const u8,
    commit_and_push: []const u8,
    push: []const u8,
    cancel: []const u8,
};

const commit_chrome_en: CommitChrome = .{
    .commit_message = "Commit message",
    .include_unstaged = "Include unstaged",
    .amend = "Amend",
    .force = "Force",
    .generating = "Generating…",
    .amending = "Amending…",
    .committing_and_pushing = "Committing and pushing…",
    .committing = "Committing…",
    .pushing = "Pushing…",
    .commit = "Commit",
    .commit_and_push = "Commit and Push",
    .push = "Push",
    .cancel = "Cancel",
};

const commit_chrome_zh_cn: CommitChrome = .{
    .commit_message = "提交信息",
    .include_unstaged = "包含未暂存",
    .amend = "修订",
    .force = "强制",
    .generating = "正在生成…",
    .amending = "正在修订…",
    .committing_and_pushing = "正在提交并推送…",
    .committing = "正在提交…",
    .pushing = "正在推送…",
    .commit = "提交",
    .commit_and_push = "提交并推送",
    .push = "推送",
    .cancel = "取消",
};

const commit_chrome_ja: CommitChrome = .{
    .commit_message = "コミットメッセージ",
    .include_unstaged = "未ステージを含める",
    .amend = "修正",
    .force = "強制",
    .generating = "生成中…",
    .amending = "修正中…",
    .committing_and_pushing = "コミットしてプッシュ中…",
    .committing = "コミット中…",
    .pushing = "プッシュ中…",
    .commit = "コミット",
    .commit_and_push = "コミットしてプッシュ",
    .push = "プッシュ",
    .cancel = "キャンセル",
};

/// Composer branch-picker dropdown plus New branch / New worktree /
/// Delete branch / Push-confirm composer-row chrome for the resolved
/// locale. Same resolve path as CommitChrome. Wire ids / on-press /
/// on-input stay English (`toggle_git_branch_picker` /
/// `git_branch_search_edit` / `start_git_branch_create` /
/// `start_git_worktree_create` / `start_git_branch_delete` /
/// `start_git_fetch` / `start_git_commit` / `start_git_push` /
/// `git_branch_create_edit` / `git_worktree_create_edit` /
/// `confirm_git_branch_create` / `cancel_git_branch_create` /
/// `toggle_git_worktree_base_picker` / `confirm_git_worktree_create` /
/// `cancel_git_worktree_create` / `toggle_git_branch_delete_force` /
/// `confirm_git_branch_delete` / `cancel_git_branch_delete` /
/// `confirm_git_push` / `cancel_git_push`). Branch names and search
/// typed text stay English (data). English matches the former
/// hardcoded copy. Force / Push (no ellipsis) / Cancel reuse
/// `CommitChrome`. Workspace picker Work in / Local / New worktree
/// (no ellipsis) live in `WorkspaceChrome`. Work-in Base reuses
/// `base` here (same Model helper as New worktree… card Base).
/// Worktree is git jargon and
/// stays Latin in zh-CN / ja.
pub const BranchChrome = struct {
    branch_placeholder: []const u8,
    search_branches: []const u8,
    new_branch_menu: []const u8,
    new_worktree_menu: []const u8,
    delete_branch_menu: []const u8,
    fetch_menu: []const u8,
    commit_menu: []const u8,
    push_menu: []const u8,
    new_branch_name: []const u8,
    new_worktree_name: []const u8,
    base: []const u8,
    create: []const u8,
    delete: []const u8,
};

const branch_chrome_en: BranchChrome = .{
    .branch_placeholder = "Branch",
    .search_branches = "Search branches",
    .new_branch_menu = "New branch…",
    .new_worktree_menu = "New worktree…",
    .delete_branch_menu = "Delete branch…",
    .fetch_menu = "Fetch…",
    .commit_menu = "Commit…",
    .push_menu = "Push…",
    .new_branch_name = "New branch name",
    .new_worktree_name = "New worktree name",
    .base = "Base",
    .create = "Create",
    .delete = "Delete",
};

const branch_chrome_zh_cn: BranchChrome = .{
    .branch_placeholder = "分支",
    .search_branches = "搜索分支",
    .new_branch_menu = "新建分支…",
    .new_worktree_menu = "新建 worktree…",
    .delete_branch_menu = "删除分支…",
    .fetch_menu = "获取…",
    .commit_menu = "提交…",
    .push_menu = "推送…",
    .new_branch_name = "新分支名称",
    .new_worktree_name = "新 worktree 名称",
    .base = "基准",
    .create = "创建",
    .delete = "删除",
};

const branch_chrome_ja: BranchChrome = .{
    .branch_placeholder = "ブランチ",
    .search_branches = "ブランチを検索",
    .new_branch_menu = "新しいブランチ…",
    .new_worktree_menu = "新しい worktree…",
    .delete_branch_menu = "ブランチを削除…",
    .fetch_menu = "フェッチ…",
    .commit_menu = "コミット…",
    .push_menu = "プッシュ…",
    .new_branch_name = "新しいブランチ名",
    .new_worktree_name = "新しい worktree 名",
    .base = "ベース",
    .create = "作成",
    .delete = "削除",
};

/// Composer workspace picker chrome for the resolved locale. Same
/// resolve path as BranchChrome. Wire ids / on-press stay English
/// (`toggle_workspace_picker` / `close_workspace_picker` /
/// `pick_workspace_local` / `pick_workspace_new_worktree`). English
/// matches the former hardcoded copy. Distinct from branch-menu
/// `New worktree…` (`BranchChrome.new_worktree_menu`). Worktree is
/// git jargon and stays Latin in zh-CN / ja. Work-in Base reuses
/// `BranchChrome.base`. Project-row Local reuses `local` here
/// (distinct Model getter from the workspace picker menu).
pub const WorkspaceChrome = struct {
    work_in: []const u8,
    local: []const u8,
    new_worktree: []const u8,
};

const workspace_chrome_en: WorkspaceChrome = .{
    .work_in = "Work in",
    .local = "Local",
    .new_worktree = "New worktree",
};

const workspace_chrome_zh_cn: WorkspaceChrome = .{
    .work_in = "工作于",
    .local = "本地",
    .new_worktree = "新建 worktree",
};

const workspace_chrome_ja: WorkspaceChrome = .{
    .work_in = "作業場所",
    .local = "ローカル",
    .new_worktree = "新しい worktree",
};

/// Send-prep attach status Creating worktree… / Could not create
/// worktree. for the resolved locale. Same resolve path as
/// WorkspaceChrome. English matches the former hardcoded copy.
/// Distinct from workspace picker Work in / Local / New worktree
/// (`WorkspaceChrome`), branch-menu New worktree… (`BranchChrome`),
/// and CommitChrome generating / amending / committing / pushing so
/// worktree attach-status chrome stays independently evolvable.
/// Worktree is git jargon and stays Latin in zh-CN / ja. Creating
/// uses the ellipsis character (same style as CommitChrome
/// generating / amending). Branch-op attach statuses live on
/// `BranchOpStatusChrome`. Commit attach-status lives on
/// `CommitAttachStatusChrome`. Wire ids / on-press / git argv stay English.
pub const WorktreeStatusChrome = struct {
    creating: []const u8,
    create_failed: []const u8,
};

const worktree_status_chrome_en: WorktreeStatusChrome = .{
    .creating = "Creating worktree…",
    .create_failed = "Could not create worktree.",
};

const worktree_status_chrome_zh_cn: WorktreeStatusChrome = .{
    .creating = "正在创建 worktree…",
    .create_failed = "无法创建 worktree。",
};

const worktree_status_chrome_ja: WorktreeStatusChrome = .{
    .creating = "worktree を作成中…",
    .create_failed = "worktree を作成できませんでした。",
};

/// Branch-menu attach-status Could not check out branch. / Already
/// checked out in another worktree. / Could not create branch. /
/// Could not delete branch. / Could not fetch. / Could not push.
/// for the resolved locale. Same resolve path as
/// WorktreeStatusChrome. English matches the former hardcoded copy.
/// Distinct from branch-picker menu labels (`BranchChrome`), Commit
/// dialog pending Generating… / Pushing… (`CommitChrome`), Send-prep
/// Creating worktree… (`WorktreeStatusChrome`), and workspace picker
/// Work in / Local / New worktree (`WorkspaceChrome`) so branch-op
/// attach-status chrome stays independently evolvable. Worktree is
/// git jargon and stays Latin in zh-CN / ja where it appears in the
/// occupied string. Commit attach-status lives on
/// `CommitAttachStatusChrome`. Wire ids / on-press / git argv stay
/// English.
pub const BranchOpStatusChrome = struct {
    checkout_failed: []const u8,
    occupied_checkout: []const u8,
    create_failed: []const u8,
    delete_failed: []const u8,
    fetch_failed: []const u8,
    push_failed: []const u8,
};

const branch_op_status_chrome_en: BranchOpStatusChrome = .{
    .checkout_failed = "Could not check out branch.",
    .occupied_checkout = "Already checked out in another worktree.",
    .create_failed = "Could not create branch.",
    .delete_failed = "Could not delete branch.",
    .fetch_failed = "Could not fetch.",
    .push_failed = "Could not push.",
};

const branch_op_status_chrome_zh_cn: BranchOpStatusChrome = .{
    .checkout_failed = "无法检出分支。",
    .occupied_checkout = "已在另一个 worktree 中检出。",
    .create_failed = "无法创建分支。",
    .delete_failed = "无法删除分支。",
    .fetch_failed = "无法获取。",
    .push_failed = "无法推送。",
};

const branch_op_status_chrome_ja: BranchOpStatusChrome = .{
    .checkout_failed = "ブランチをチェックアウトできませんでした。",
    .occupied_checkout = "別の worktree で既にチェックアウトされています。",
    .create_failed = "ブランチを作成できませんでした。",
    .delete_failed = "ブランチを削除できませんでした。",
    .fetch_failed = "フェッチできませんでした。",
    .push_failed = "プッシュできませんでした。",
};

/// Commit… attach-status Enter a commit message. / Could not
/// commit. / Nothing staged to commit. / Could not generate a
/// commit message. for the resolved locale. Same resolve path as
/// BranchOpStatusChrome. English matches the former hardcoded copy.
/// Distinct from Commit dialog labels / pending Generating… /
/// Amending… / Committing… / Committing and pushing… / Pushing…
/// (`CommitChrome`), branch-op Could not push. (`BranchOpStatusChrome`),
/// Send-prep Creating worktree… (`WorktreeStatusChrome`), and
/// workspace picker (`WorkspaceChrome`) so commit attach-status
/// chrome stays independently evolvable. Wire ids / on-press / git
/// argv stay English.
pub const CommitAttachStatusChrome = struct {
    empty_message: []const u8,
    commit_failed: []const u8,
    nothing_staged: []const u8,
    generate_failed: []const u8,
};

const commit_attach_status_chrome_en: CommitAttachStatusChrome = .{
    .empty_message = "Enter a commit message.",
    .commit_failed = "Could not commit.",
    .nothing_staged = "Nothing staged to commit.",
    .generate_failed = "Could not generate a commit message.",
};

const commit_attach_status_chrome_zh_cn: CommitAttachStatusChrome = .{
    .empty_message = "请输入提交信息。",
    .commit_failed = "无法提交。",
    .nothing_staged = "没有可提交的暂存更改。",
    .generate_failed = "无法生成提交信息。",
};

const commit_attach_status_chrome_ja: CommitAttachStatusChrome = .{
    .empty_message = "コミットメッセージを入力してください。",
    .commit_failed = "コミットできませんでした。",
    .nothing_staged = "コミットするステージ済みの変更がありません。",
    .generate_failed = "コミットメッセージを生成できませんでした。",
};

/// Daemon-dir in-app BrowseDirectory browser chrome for the resolved
/// locale. Same resolve path as CommitAttachStatusChrome. Wire ids / on-press
/// stay English (`daemon_dir_browser_up` / `daemon_dir_browser_home` /
/// `confirm_daemon_dir_browser` / `cancel_daemon_dir_browser`).
/// English matches the former hardcoded copy. Cancel reuses
/// `CommitChrome.cancel`. Loading… uses the ellipsis character
/// (same style as `RightPanelChrome.loading_files`). OS folder-dialog
/// prompts live in `OsFolderDialogChrome`.
pub const DaemonDirChrome = struct {
    up: []const u8,
    home: []const u8,
    choose: []const u8,
    loading: []const u8,
};

const daemon_dir_chrome_en: DaemonDirChrome = .{
    .up = "Up",
    .home = "Home",
    .choose = "Choose",
    .loading = "Loading…",
};

const daemon_dir_chrome_zh_cn: DaemonDirChrome = .{
    .up = "上级",
    .home = "主目录",
    .choose = "选择",
    .loading = "加载中…",
};

const daemon_dir_chrome_ja: DaemonDirChrome = .{
    .up = "上へ",
    .home = "ホーム",
    .choose = "選択",
    .loading = "読み込み中…",
};

/// Session-switcher dialog title and Switch. Same resolve path as
/// DaemonDirChrome. Wire ids / on-press / on-dismiss stay English
/// (`switcher_confirm` / `switcher_cancel`). English matches the
/// former hardcoded copy. Cancel reuses `CommitChrome.cancel`.
pub const SwitcherChrome = struct {
    title: []const u8,
    switch_label: []const u8,
};

const switcher_chrome_en: SwitcherChrome = .{
    .title = "Switch session",
    .switch_label = "Switch",
};

const switcher_chrome_zh_cn: SwitcherChrome = .{
    .title = "切换会话",
    .switch_label = "切换",
};

const switcher_chrome_ja: SwitcherChrome = .{
    .title = "セッションを切り替え",
    .switch_label = "切り替え",
};

/// Settings General / project-edit Workspace path placeholders for
/// the resolved locale. Same resolve path as SwitcherChrome. Wire
/// ids / on-input stay English (`settings_project_edit` /
/// `project_path_edit`). English matches the former hardcoded copy.
/// Typed path text stays data. Distinct from OS folder-dialog
/// prompts (`OsFolderDialogChrome` in pick_folder).
pub const WorkspacePathChrome = struct {
    placeholder: []const u8,
};

const workspace_path_chrome_en: WorkspacePathChrome = .{
    .placeholder = "Workspace path",
};

const workspace_path_chrome_zh_cn: WorkspacePathChrome = .{
    .placeholder = "工作区路径",
};

const workspace_path_chrome_ja: WorkspacePathChrome = .{
    .placeholder = "ワークスペースのパス",
};

/// Session title rename placeholders for the resolved locale. Same
/// resolve path as WorkspacePathChrome. Wire ids / on-input stay
/// English (`session_title_edit`). English matches the former
/// hardcoded copy. Catalog titles stay English `untitled` (data,
/// not chrome).
pub const UntitledChrome = struct {
    placeholder: []const u8,
};

const untitled_chrome_en: UntitledChrome = .{
    .placeholder = "untitled",
};

const untitled_chrome_zh_cn: UntitledChrome = .{
    .placeholder = "未命名",
};

const untitled_chrome_ja: UntitledChrome = .{
    .placeholder = "無題",
};

/// Header untitled display title for the resolved locale (`New task`
/// in the 48px toolbar). Same resolve path as UntitledChrome. English
/// matches the former hardcoded copy (sentence case). Distinct from
/// `Sidebar.new_task` (title-case palette / sidebar New Task) so
/// header untitled chrome stays independently evolvable. Catalog
/// titles stay English `untitled` (data, not chrome). Wire ids /
/// on-press stay English (`edit_session_title`).
pub const HeaderUntitledChrome = struct {
    new_task: []const u8,
};

const header_untitled_chrome_en: HeaderUntitledChrome = .{
    .new_task = "New task",
};

const header_untitled_chrome_zh_cn: HeaderUntitledChrome = .{
    .new_task = "新建任务",
};

const header_untitled_chrome_ja: HeaderUntitledChrome = .{
    .new_task = "新しいタスク",
};

/// Settings General daemon address placeholder for the resolved
/// locale. Same resolve path as UntitledChrome. Wire ids / on-input
/// stay English (`settings_daemon_edit`). Latin `host:port` in every
/// locale (FX_MODEL-like technical token). English matches the former
/// hardcoded copy. Typed address text stays data.
pub const DaemonAddressChrome = struct {
    placeholder: []const u8,
};

const daemon_address_chrome_en: DaemonAddressChrome = .{
    .placeholder = "host:port",
};

const daemon_address_chrome_zh_cn: DaemonAddressChrome = .{
    .placeholder = "host:port",
};

const daemon_address_chrome_ja: DaemonAddressChrome = .{
    .placeholder = "host:port",
};

/// Settings General field labels (Default model / Access mode /
/// Interaction / Effort / Last project path / Daemon address) plus
/// Default model / Effort placeholders for the resolved locale. Same
/// resolve path as DaemonAddressChrome. Wire ids / on-input /
/// on-press stay English (`settings_model_edit` /
/// `toggle_settings_effort_picker`). Latin `FX_MODEL` in every
/// locale (FX_MODEL-like technical token, same rule as `host:port`).
/// English matches the former hardcoded copy. Access / Interaction /
/// Effort chip values stay on `Access` / `Interaction` / `Effort`.
/// Daemon address placeholder stays on `DaemonAddressChrome`.
/// Workspace path placeholder stays on `WorkspacePathChrome`.
pub const SettingsGeneralChrome = struct {
    default_model: []const u8,
    access_mode: []const u8,
    interaction: []const u8,
    effort: []const u8,
    last_project_path: []const u8,
    daemon_address: []const u8,
    default_model_placeholder: []const u8,
};

const settings_general_chrome_en: SettingsGeneralChrome = .{
    .default_model = "Default model",
    .access_mode = "Access mode",
    .interaction = "Interaction",
    .effort = "Effort",
    .last_project_path = "Last project path",
    .daemon_address = "Daemon address",
    .default_model_placeholder = "FX_MODEL",
};

const settings_general_chrome_zh_cn: SettingsGeneralChrome = .{
    .default_model = "默认模型",
    .access_mode = "访问模式",
    .interaction = "交互",
    .effort = "力度",
    .last_project_path = "上次项目路径",
    .daemon_address = "守护进程地址",
    .default_model_placeholder = "FX_MODEL",
};

const settings_general_chrome_ja: SettingsGeneralChrome = .{
    .default_model = "デフォルトモデル",
    .access_mode = "アクセスモード",
    .interaction = "インタラクション",
    .effort = "エフォート",
    .last_project_path = "前回のプロジェクトパス",
    .daemon_address = "デーモンアドレス",
    .default_model_placeholder = "FX_MODEL",
};

/// OS folder-dialog prompt and missing-picker status for the resolved
/// locale. Same resolve path as SettingsGeneralChrome. English matches
/// the former hardcoded `pick_folder` osascript / PowerShell /
/// zenity-or-kdialog copy. Binary names stay Latin (`zenity` /
/// `kdialog` / `osascript` / `powershell.exe`). OS image-dialog
/// prompts live in `OsImageDialogChrome`.
pub const OsFolderDialogChrome = struct {
    prompt: []const u8,
    linux_missing: []const u8,
    macos_missing: []const u8,
    windows_missing: []const u8,
};

const os_folder_dialog_chrome_en: OsFolderDialogChrome = .{
    .prompt = "Choose a project",
    .linux_missing = "No OS folder picker (install zenity or kdialog). Type a path.",
    .macos_missing = "No OS folder picker (osascript missing). Type a path.",
    .windows_missing = "No OS folder picker (powershell.exe missing). Type a path.",
};

const os_folder_dialog_chrome_zh_cn: OsFolderDialogChrome = .{
    .prompt = "选择一个项目",
    .linux_missing = "没有 OS 文件夹选择器（请安装 zenity 或 kdialog）。请输入路径。",
    .macos_missing = "没有 OS 文件夹选择器（缺少 osascript）。请输入路径。",
    .windows_missing = "没有 OS 文件夹选择器（缺少 powershell.exe）。请输入路径。",
};

const os_folder_dialog_chrome_ja: OsFolderDialogChrome = .{
    .prompt = "プロジェクトを選択",
    .linux_missing = "OS のフォルダ選択がありません（zenity または kdialog をインストールしてください）。パスを入力してください。",
    .macos_missing = "OS のフォルダ選択がありません（osascript がありません）。パスを入力してください。",
    .windows_missing = "OS のフォルダ選択がありません（powershell.exe がありません）。パスを入力してください。",
};

/// OS image-dialog prompt and missing-picker status for the resolved
/// locale. Same resolve path as OsFolderDialogChrome. English matches
/// the former hardcoded `pick_image` osascript / PowerShell /
/// zenity-or-kdialog copy. Binary names stay Latin (`zenity` /
/// `kdialog` / `osascript` / `powershell.exe`). Filter extensions
/// stay Latin.
pub const OsImageDialogChrome = struct {
    prompt: []const u8,
    linux_missing: []const u8,
    macos_missing: []const u8,
    windows_missing: []const u8,
};

const os_image_dialog_chrome_en: OsImageDialogChrome = .{
    .prompt = "Choose an image",
    .linux_missing = "No OS image picker (install zenity or kdialog). Type a path or drop a file.",
    .macos_missing = "No OS image picker (osascript missing). Type a path or drop a file.",
    .windows_missing = "No OS image picker (powershell.exe missing). Type a path or drop a file.",
};

const os_image_dialog_chrome_zh_cn: OsImageDialogChrome = .{
    .prompt = "选择一张图片",
    .linux_missing = "没有 OS 图片选择器（请安装 zenity 或 kdialog）。请输入路径或拖放文件。",
    .macos_missing = "没有 OS 图片选择器（缺少 osascript）。请输入路径或拖放文件。",
    .windows_missing = "没有 OS 图片选择器（缺少 powershell.exe）。请输入路径或拖放文件。",
};

const os_image_dialog_chrome_ja: OsImageDialogChrome = .{
    .prompt = "画像を選択",
    .linux_missing = "OS の画像選択がありません（zenity または kdialog をインストールしてください）。パスを入力するかファイルをドロップしてください。",
    .macos_missing = "OS の画像選択がありません（osascript がありません）。パスを入力するかファイルをドロップしてください。",
    .windows_missing = "OS の画像選択がありません（powershell.exe がありません）。パスを入力するかファイルをドロップしてください。",
};

/// Composer Image path placeholder, Pick image button, Attach image
/// a11y, Clear image a11y, Attached image a11y, Goal Status picker
/// placeholder / empty label, and Commands toggle chip for the resolved
/// locale. Same resolve path as SettingsGeneralChrome. English matches
/// the former hardcoded copy. Wire ids / on-press / on-input stay
/// English (`image_path_edit` / `toggle_goal_status_picker` /
/// `pick_image` / `clear_image_attach` / `toggle_commands`). Typed
/// path text stays data. ThreadGoalStatus wire names stay English
/// (`active` / `paused` / …); picker-row / selected-chip display
/// labels live in `GoalStatusChrome`. Commands wording matches
/// `PaletteChrome.commands` (命令 / コマンド) but lives here so the
/// composer chip stays distinct from the palette overlay header.
pub const ComposerChrome = struct {
    image_path: []const u8,
    status: []const u8,
    pick_image: []const u8,
    attach_image: []const u8,
    clear_image: []const u8,
    attached_image: []const u8,
    commands: []const u8,
};

const composer_chrome_en: ComposerChrome = .{
    .image_path = "Image path",
    .status = "Status",
    .pick_image = "Pick image",
    .attach_image = "Attach image",
    .clear_image = "Clear image",
    .attached_image = "Attached image",
    .commands = "Commands",
};

const composer_chrome_zh_cn: ComposerChrome = .{
    .image_path = "图片路径",
    .status = "状态",
    .pick_image = "选择图片",
    .attach_image = "附加图片",
    .clear_image = "清除图片",
    .attached_image = "已附加图片",
    .commands = "命令",
};

const composer_chrome_ja: ComposerChrome = .{
    .image_path = "画像パス",
    .status = "ステータス",
    .pick_image = "画像を選択",
    .attach_image = "画像を添付",
    .clear_image = "画像をクリア",
    .attached_image = "添付画像",
    .commands = "コマンド",
};

/// Composer primary Send / Stop a11y labels and visible `send_label`
/// for the resolved locale. Same resolve path as ComposerChrome.
/// English matches the former hardcoded copy. Distinct from
/// `BackgroundChrome.daemon_stop` and from `ComposerChrome`
/// (image/goal/commands) so composer Send/Stop stay independently
/// evolvable. Wire ids / on-press stay English (`send` /
/// `stop_turn`). Visible `send_label` is idle `send` / streaming
/// `stop`; icon-button a11y stays `composer_send_label` /
/// `composer_stop_label`.
pub const ComposerSendStopChrome = struct {
    send: []const u8,
    stop: []const u8,
};

const composer_send_stop_chrome_en: ComposerSendStopChrome = .{
    .send = "Send",
    .stop = "Stop",
};

const composer_send_stop_chrome_zh_cn: ComposerSendStopChrome = .{
    .send = "发送",
    .stop = "停止",
};

const composer_send_stop_chrome_ja: ComposerSendStopChrome = .{
    .send = "送信",
    .stop = "停止",
};

/// Composer textarea idle / streaming placeholders for the resolved
/// locale. Same resolve path as ComposerSendStopChrome. English
/// matches the former hardcoded copy. Distinct from `QueueChrome`
/// (queue card), `ComposerChrome` (image/goal/commands), and
/// `ComposerSendStopChrome` so composer placeholders stay independently
/// evolvable. Wire ids / on-input / on-submit stay English
/// (`draft_edit` / `composer_enter`). Draft text stays data.
pub const ComposerPlaceholderChrome = struct {
    idle: []const u8,
    streaming: []const u8,
};

const composer_placeholder_chrome_en: ComposerPlaceholderChrome = .{
    .idle = "Do anything...",
    .streaming = "Queue a follow-up...",
};

const composer_placeholder_chrome_zh_cn: ComposerPlaceholderChrome = .{
    .idle = "随便做什么...",
    .streaming = "排队跟进...",
};

const composer_placeholder_chrome_ja: ComposerPlaceholderChrome = .{
    .idle = "何でもどうぞ...",
    .streaming = "フォローアップをキュー...",
};

/// Empty-transcript welcome title / subtitle for the resolved locale
/// (centered empty state above the composer). Same resolve path as
/// ComposerPlaceholderChrome. English matches the former hardcoded
/// copy. Distinct from `HeaderUntitledChrome` (toolbar New task),
/// `ComposerPlaceholderChrome` (textarea placeholders), and
/// `QueueChrome` (queue card / Jump to latest) so welcome wording
/// stays independently evolvable. Wire ids stay English. Real
/// session titles and typed draft text stay data.
pub const WelcomeChrome = struct {
    title: []const u8,
    subtitle: []const u8,
};

const welcome_chrome_en: WelcomeChrome = .{
    .title = "What should we build?",
    .subtitle = "Pick a project, or just start typing.",
};

const welcome_chrome_zh_cn: WelcomeChrome = .{
    .title = "我们要构建什么？",
    .subtitle = "选择一个项目，或直接开始输入。",
};

const welcome_chrome_ja: WelcomeChrome = .{
    .title = "何を作りましょうか？",
    .subtitle = "プロジェクトを選ぶか、そのまま入力を始めてください。",
};

/// Transcript find-bar Previous match / Next match / Close find a11y
/// labels for the resolved locale. Same resolve path as
/// ComposerSendStopChrome. English matches the former hardcoded copy.
/// Distinct from `FilePreviewChrome` previous/next/close file-find
/// and from Palette find-in-transcript so transcript find-bar chrome
/// stays independently evolvable. Wire ids / on-press stay English
/// (`find_prev` / `find_next` / `close_find`).
pub const FindBarChrome = struct {
    previous_match: []const u8,
    next_match: []const u8,
    close_find: []const u8,
};

const find_bar_chrome_en: FindBarChrome = .{
    .previous_match = "Previous match",
    .next_match = "Next match",
    .close_find = "Close find",
};

const find_bar_chrome_zh_cn: FindBarChrome = .{
    .previous_match = "上一个匹配",
    .next_match = "下一个匹配",
    .close_find = "关闭查找",
};

const find_bar_chrome_ja: FindBarChrome = .{
    .previous_match = "前の一致",
    .next_match = "次の一致",
    .close_find = "検索を閉じる",
};

/// Transcript find-bar muted match-position chrome (`No matches` /
/// `k of N`) for the resolved locale. Same resolve path as
/// FindBarChrome. English matches the former hardcoded copy
/// (`No matches`, `{d} of {d}`). Distinct from `FindBarChrome`
/// previous/next/close a11y, from `FilePreviewChrome`, and from
/// `FilePreviewFindMatchChrome` (file-preview keeps its own
/// `n of m · L#line` path) and from `TranscriptTurnChrome.match` so
/// transcript find-match chrome stays independently evolvable.
/// Numbers stay Latin. Wire ids / on-press / find query stay
/// English.
pub const FindMatchChrome = struct {
    no_matches: []const u8,
    of_fmt: []const u8,
};

const find_match_chrome_en: FindMatchChrome = .{
    .no_matches = "No matches",
    .of_fmt = "{d} of {d}",
};

const find_match_chrome_zh_cn: FindMatchChrome = .{
    .no_matches = "无匹配",
    .of_fmt = "{d} / {d}",
};

const find_match_chrome_ja: FindMatchChrome = .{
    .no_matches = "一致なし",
    .of_fmt = "{d} / {d}",
};

/// Files preview find muted match-position chrome (`n of m · L#line`
/// / `invalid` / `0`) for the resolved locale. Same resolve path as
/// FindMatchChrome. English matches the former hardcoded copy
/// (`{d} of {d}{s} · L{d}`, `invalid`, `0`, allocPrint fallback
/// `match`). Distinct from `FindMatchChrome` / `FindBarChrome` /
/// `FilePreviewChrome` / `FilePreviewErrorChrome` so file-preview match chrome stays
/// independently evolvable. Numbers stay Latin. `+` cap marker and
/// middle-dot ` · ` stay. Wire ids / on-press / on-input / find
/// query / replace text stay English.
pub const FilePreviewFindMatchChrome = struct {
    of_line_fmt: []const u8,
    invalid: []const u8,
    zero: []const u8,
    match: []const u8,
};

const file_preview_find_match_chrome_en: FilePreviewFindMatchChrome = .{
    .of_line_fmt = "{d} of {d}{s} · L{d}",
    .invalid = "invalid",
    .zero = "0",
    .match = "match",
};

const file_preview_find_match_chrome_zh_cn: FilePreviewFindMatchChrome = .{
    .of_line_fmt = "{d} / {d}{s} · L{d}",
    .invalid = "无效",
    .zero = "0",
    .match = "匹配",
};

const file_preview_find_match_chrome_ja: FilePreviewFindMatchChrome = .{
    .of_line_fmt = "{d} / {d}{s} · L{d}",
    .invalid = "無効",
    .zero = "0",
    .match = "一致",
};

/// Header Copy session a11y plus Fork / Rewind button chrome for the
/// resolved locale. Same resolve path as FindBarChrome. English
/// matches the former hardcoded copy. Distinct from
/// `Palette.copy_session_id` ("Copy session id") and from
/// `TranscriptTurnChrome` so header session chrome stays
/// independently evolvable. Wire ids / on-press stay English
/// (`copy_session` / `fork` / `rewind`).
pub const HeaderSessionChrome = struct {
    copy_session: []const u8,
    fork: []const u8,
    rewind: []const u8,
};

const header_session_chrome_en: HeaderSessionChrome = .{
    .copy_session = "Copy session",
    .fork = "Fork",
    .rewind = "Rewind",
};

const header_session_chrome_zh_cn: HeaderSessionChrome = .{
    .copy_session = "复制会话",
    .fork = "分叉",
    .rewind = "回退",
};

const header_session_chrome_ja: HeaderSessionChrome = .{
    .copy_session = "セッションをコピー",
    .fork = "フォーク",
    .rewind = "巻き戻し",
};

/// Transcript turn You said / Assistant said a11y for the resolved
/// locale. Same resolve path as HeaderSessionChrome. English
/// matches the former hardcoded copy. Distinct from
/// `HeaderSessionChrome` and from `TranscriptTurnChrome` so
/// transcript role chrome stays independently evolvable. Wire
/// ids / on-press / turn data stay English.
pub const TranscriptRoleChrome = struct {
    you_said: []const u8,
    assistant_said: []const u8,
};

const transcript_role_chrome_en: TranscriptRoleChrome = .{
    .you_said = "You said",
    .assistant_said = "Assistant said",
};

const transcript_role_chrome_zh_cn: TranscriptRoleChrome = .{
    .you_said = "你说",
    .assistant_said = "助手说",
};

const transcript_role_chrome_ja: TranscriptRoleChrome = .{
    .you_said = "あなたが言った",
    .assistant_said = "アシスタントが言った",
};

/// Transcript turn Match chip plus per-turn Copy / Fork chrome for
/// the resolved locale. Same resolve path as TranscriptRoleChrome.
/// English matches the former hardcoded copy. Distinct from
/// `HeaderSessionChrome` / `TranscriptRoleChrome` /
/// `Palette.copy_session_id` / `FindBarChrome` /
/// `FilePreviewChrome` so transcript turn action chrome stays
/// independently evolvable. Wire ids / on-press stay English
/// (`copy_turn:{t.id}` / `fork_turn:{t.id}`).
pub const TranscriptTurnChrome = struct {
    match: []const u8,
    copy: []const u8,
    fork: []const u8,
};

const transcript_turn_chrome_en: TranscriptTurnChrome = .{
    .match = "Match",
    .copy = "Copy",
    .fork = "Fork",
};

const transcript_turn_chrome_zh_cn: TranscriptTurnChrome = .{
    .match = "匹配",
    .copy = "复制",
    .fork = "分叉",
};

const transcript_turn_chrome_ja: TranscriptTurnChrome = .{
    .match = "一致",
    .copy = "コピー",
    .fork = "フォーク",
};

/// Composer queue card Queued / Dismiss all / Remove queued plus
/// transcript Jump to latest chrome for the resolved locale. Same
/// resolve path as TranscriptTurnChrome. English matches the former
/// hardcoded copy. Distinct from `EnvironmentChrome.dismiss_all_settled`
/// ("Dismiss all settled") and from `BackgroundChrome` Dismiss* so
/// queue "Dismiss all" can evolve independently. Also distinct from
/// `TranscriptTurnChrome` / `HeaderSessionChrome`. Wire ids /
/// on-press stay English (`jump_latest` / `clear_queue` /
/// `remove_queued:{id}` / `edit_queued:{id}`). Queued message body
/// text stays data.
pub const QueueChrome = struct {
    jump_latest: []const u8,
    queued: []const u8,
    dismiss_all: []const u8,
    remove_queued: []const u8,
};

const queue_chrome_en: QueueChrome = .{
    .jump_latest = "Jump to latest",
    .queued = "Queued",
    .dismiss_all = "Dismiss all",
    .remove_queued = "Remove queued",
};

const queue_chrome_zh_cn: QueueChrome = .{
    .jump_latest = "跳到最新",
    .queued = "排队中",
    .dismiss_all = "全部清除",
    .remove_queued = "移除排队",
};

const queue_chrome_ja: QueueChrome = .{
    .jump_latest = "最新へジャンプ",
    .queued = "キュー",
    .dismiss_all = "すべて解除",
    .remove_queued = "キューを削除",
};

/// Browser address-field a11y label and placeholder for the resolved
/// locale. Same resolve path as ComposerChrome. English matches the
/// former hardcoded copy. Wire ids / on-input / on-submit stay
/// English (`browser_url_edit` / `browser_navigate`). Latin
/// `https://example.com` in every locale (same rule as `host:port` /
/// `FX_MODEL`). Typed URL text stays data. Parked `home_url` / shell
/// webview scene URLs stay data (protocol/home, not chrome).
pub const BrowserAddressChrome = struct {
    address: []const u8,
    placeholder: []const u8,
};

const browser_address_chrome_en: BrowserAddressChrome = .{
    .address = "Address",
    .placeholder = "https://example.com",
};

const browser_address_chrome_zh_cn: BrowserAddressChrome = .{
    .address = "地址",
    .placeholder = "https://example.com",
};

const browser_address_chrome_ja: BrowserAddressChrome = .{
    .address = "アドレス",
    .placeholder = "https://example.com",
};

/// Browser toolbar Back / Forward / Reload / Hard Reload / Navigate
/// and Secure / Not secure a11y for the resolved locale. Same resolve
/// path as BrowserAddressChrome. English matches the former
/// hardcoded copy (Hard Reload is first-cut EN). Wire ids / on-press
/// stay English (`browser_back` / `browser_forward` /
/// `browser_reload` / `browser_hard_reload` / `browser_navigate`).
/// Typed URL text stays data. Parked `home_url` / shell webview
/// scene URLs stay data. Distinct from sidebar titlebar
/// session-history Back / Forward (`SidebarHistoryChrome`;
/// `history_back` / `history_forward`).
pub const BrowserToolbarChrome = struct {
    back: []const u8,
    forward: []const u8,
    reload: []const u8,
    hard_reload: []const u8,
    navigate: []const u8,
    secure: []const u8,
    not_secure: []const u8,
};

const browser_toolbar_chrome_en: BrowserToolbarChrome = .{
    .back = "Back",
    .forward = "Forward",
    .reload = "Reload",
    .hard_reload = "Hard Reload",
    .navigate = "Navigate",
    .secure = "Secure",
    .not_secure = "Not secure",
};

const browser_toolbar_chrome_zh_cn: BrowserToolbarChrome = .{
    .back = "返回",
    .forward = "前进",
    .reload = "重新加载",
    .hard_reload = "强制重新加载",
    .navigate = "转到",
    .secure = "安全",
    .not_secure = "不安全",
};

const browser_toolbar_chrome_ja: BrowserToolbarChrome = .{
    .back = "戻る",
    .forward = "進む",
    .reload = "再読み込み",
    .hard_reload = "強制再読み込み",
    .navigate = "移動",
    .secure = "安全",
    .not_secure = "保護されていません",
};

/// Browser start-page globe icon a11y for the resolved locale. Same
/// resolve path as BrowserToolbarChrome. English matches the former
/// hardcoded copy (`Browse`, shorter than `RightPanelChrome.browse_the_web`
/// "Browse the web"). Distinct from `RightPanelChrome.browse_the_web` /
/// `BrowserToolbarChrome` / `BrowserAddressChrome` so start-page icon
/// a11y stays independently evolvable. No wire-id / on-press changes.
pub const BrowserStartIconChrome = struct {
    browse: []const u8,
};

const browser_start_icon_chrome_en: BrowserStartIconChrome = .{
    .browse = "Browse",
};

const browser_start_icon_chrome_zh_cn: BrowserStartIconChrome = .{
    .browse = "浏览",
};

const browser_start_icon_chrome_ja: BrowserStartIconChrome = .{
    .browse = "閲覧",
};

/// Sidebar titlebar session-history Back / Forward a11y for the
/// resolved locale. Same resolve path as BrowserToolbarChrome.
/// English matches the former hardcoded copy. zh-CN / ja reuse the
/// same Back / Forward wording as BrowserToolbarChrome, kept in a
/// separate struct so Browser vs sidebar stay independently
/// documented. Wire ids / on-press stay English (`history_back` /
/// `history_forward`). Distinct from Browser toolbar Back / Forward
/// (`browser_back` / `browser_forward`).
pub const SidebarHistoryChrome = struct {
    back: []const u8,
    forward: []const u8,
};

const sidebar_history_chrome_en: SidebarHistoryChrome = .{
    .back = "Back",
    .forward = "Forward",
};

const sidebar_history_chrome_zh_cn: SidebarHistoryChrome = .{
    .back = "返回",
    .forward = "前进",
};

const sidebar_history_chrome_ja: SidebarHistoryChrome = .{
    .back = "戻る",
    .forward = "進む",
};

/// Browser / Terminal multi-session New / Close chips for the
/// resolved locale. Same resolve path as SidebarHistoryChrome.
/// English matches the former hardcoded copy. zh-CN New is 新建
/// (same verb as New Task / New folder / New branch). ja New is
/// compact 新規 (chip, not 新しい…). Close wording matches
/// FilePreviewChrome.close (关闭 / 閉じる) but stays in this
/// dedicated struct so Browser / Terminal do not silently couple
/// to file-preview Close. Wire ids / on-press stay English
/// (`new_browser` / `close_browser` / `new_terminal` /
/// `close_terminal`). Browser and Terminal share identical
/// wording.
pub const SessionChipsChrome = struct {
    new: []const u8,
    close: []const u8,
};

const session_chips_chrome_en: SessionChipsChrome = .{
    .new = "New",
    .close = "Close",
};

const session_chips_chrome_zh_cn: SessionChipsChrome = .{
    .new = "新建",
    .close = "关闭",
};

const session_chips_chrome_ja: SessionChipsChrome = .{
    .new = "新規",
    .close = "閉じる",
};

/// Terminal tab Restart after the pty exit for the resolved locale.
/// Same resolve path as SessionChipsChrome. English matches the
/// former hardcoded copy. Distinct from Browser toolbar Reload
/// (`BrowserToolbarChrome.reload` / `browser_reload`). Wire ids /
/// on-press stay English (`restart_terminal`).
pub const TerminalRestartChrome = struct {
    restart: []const u8,
};

const terminal_restart_chrome_en: TerminalRestartChrome = .{
    .restart = "Restart",
};

const terminal_restart_chrome_zh_cn: TerminalRestartChrome = .{
    .restart = "重启",
};

const terminal_restart_chrome_ja: TerminalRestartChrome = .{
    .restart = "再起動",
};

/// Settings Computer Use page body chrome for the resolved locale.
/// Same resolve path as TerminalRestartChrome. English matches the
/// former hardcoded copy. Title wording matches `Chrome.computer_use`
/// (电脑使用 / コンピュータ使用) but lives here so the page title
/// does not couple to Settings nav. Availability stays Unavailable this
/// cut; Enable stays locked Off; Always-allowed apps stays the empty
/// state. Wire ids / selected stay English (`computer_use_off`). No
/// Enable on-press / persist / permission probe / app picker.
pub const ComputerUseChrome = struct {
    title: []const u8,
    availability: []const u8,
    unavailable: []const u8,
    unavailable_caption: []const u8,
    enable: []const u8,
    off: []const u8,
    always_allowed_apps: []const u8,
    no_always_allowed_apps: []const u8,
};

const computer_use_chrome_en: ComputerUseChrome = .{
    .title = "Computer Use",
    .availability = "Availability",
    .unavailable = "Unavailable",
    .unavailable_caption = "Native has no Screen Recording or Accessibility APIs this cut. Waku's helper is macOS-only.",
    .enable = "Enable",
    .off = "Off",
    .always_allowed_apps = "Always-allowed apps",
    .no_always_allowed_apps = "No always-allowed apps",
};

const computer_use_chrome_zh_cn: ComputerUseChrome = .{
    .title = "电脑使用",
    .availability = "可用性",
    .unavailable = "不可用",
    .unavailable_caption = "Native 本轮没有屏幕录制或辅助功能 API。Waku 的助手仅限 macOS。",
    .enable = "启用",
    .off = "关",
    .always_allowed_apps = "始终允许的应用",
    .no_always_allowed_apps = "没有始终允许的应用",
};

const computer_use_chrome_ja: ComputerUseChrome = .{
    .title = "コンピュータ使用",
    .availability = "可用性",
    .unavailable = "利用不可",
    .unavailable_caption = "Native には現状、画面収録やアクセシビリティの API がありません。Waku のヘルパーは macOS 専用です。",
    .enable = "有効",
    .off = "オフ",
    .always_allowed_apps = "常に許可するアプリ",
    .no_always_allowed_apps = "常に許可するアプリはありません",
};

/// Settings Usage Daily / Monthly / Projects view chips, Daily /
/// Projects window chips, Cost|Tokens metric chips, and Daily-only
/// Model|Days breakdown chips for the resolved locale. Same resolve
/// path as ComputerUseChrome. English matches the former hardcoded
/// copy. Projects stays a dedicated field so the view chip does not
/// couple to FilterChrome / other Projects wording if they diverge.
/// Days stays distinct from Daily (day-series breakdown vs Daily
/// view). `7d` / `30d` / `90d` stay Latin in every locale (same rule
/// as `host:port`). Wire ids / on-press / selected stay English
/// (`set_usage_view_daily` / `usage_view_daily` / `set_usage_window_7d` /
/// `usage_window_this_month` / `set_usage_share_cost` /
/// `usage_share_cost` / `set_usage_breakdown_model` /
/// `usage_breakdown_days` / …). Settings Refresh lives in
/// `SettingsRefreshChrome`.
pub const UsageViewChrome = struct {
    daily: []const u8,
    monthly: []const u8,
    projects: []const u8,
    window_7d: []const u8,
    window_30d: []const u8,
    window_90d: []const u8,
    this_month: []const u8,
    last_month: []const u8,
    cost: []const u8,
    tokens: []const u8,
    model: []const u8,
    days: []const u8,
};

const usage_view_chrome_en: UsageViewChrome = .{
    .daily = "Daily",
    .monthly = "Monthly",
    .projects = "Projects",
    .window_7d = "7d",
    .window_30d = "30d",
    .window_90d = "90d",
    .this_month = "This month",
    .last_month = "Last month",
    .cost = "Cost",
    .tokens = "Tokens",
    .model = "Model",
    .days = "Days",
};

const usage_view_chrome_zh_cn: UsageViewChrome = .{
    .daily = "每日",
    .monthly = "每月",
    .projects = "项目",
    .window_7d = "7d",
    .window_30d = "30d",
    .window_90d = "90d",
    .this_month = "本月",
    .last_month = "上月",
    .cost = "费用",
    .tokens = "Token",
    .model = "模型",
    .days = "按日",
};

const usage_view_chrome_ja: UsageViewChrome = .{
    .daily = "日次",
    .monthly = "月次",
    .projects = "プロジェクト",
    .window_7d = "7d",
    .window_30d = "30d",
    .window_90d = "90d",
    .this_month = "今月",
    .last_month = "先月",
    .cost = "コスト",
    .tokens = "トークン",
    .model = "モデル",
    .days = "日別",
};

/// Settings Providers / Skills / Usage Refresh for the resolved locale.
/// Same resolve path as UsageViewChrome. English matches the former
/// hardcoded copy. One Refresh field is shared by all three Settings
/// pages so Providers / Skills / Usage stay one chrome table. Distinct
/// from Refresh goal / plan Refresh (`GoalPlanRefreshChrome`) and from
/// Browser toolbar Reload (`BrowserToolbarChrome.reload`). Wire ids /
/// on-press stay English (`refresh_providers` / `refresh_skills` /
/// `refresh_usage_history`).
pub const SettingsRefreshChrome = struct {
    refresh: []const u8,
};

const settings_refresh_chrome_en: SettingsRefreshChrome = .{
    .refresh = "Refresh",
};

const settings_refresh_chrome_zh_cn: SettingsRefreshChrome = .{
    .refresh = "刷新",
};

const settings_refresh_chrome_ja: SettingsRefreshChrome = .{
    .refresh = "更新",
};

/// Composer Refresh goal and plan-meter Refresh for the resolved
/// locale. Same resolve path as SettingsRefreshChrome. English matches
/// the former hardcoded copy. Distinct from Settings Refresh
/// (`SettingsRefreshChrome.refresh`) so the plan-meter short verb
/// and Refresh goal stay independently evolvable (same pattern as
/// TerminalRestartChrome vs BrowserToolbarChrome.reload). The plan
/// meter may share the short Refresh verb with Settings in English /
/// zh-CN / ja, but the field stays here. Wire ids / on-press stay
/// English (`goal_refresh` / `refresh_plan_usage`).
pub const GoalPlanRefreshChrome = struct {
    refresh_goal: []const u8,
    plan_refresh: []const u8,
};

const goal_plan_refresh_chrome_en: GoalPlanRefreshChrome = .{
    .refresh_goal = "Refresh goal",
    .plan_refresh = "Refresh",
};

const goal_plan_refresh_chrome_zh_cn: GoalPlanRefreshChrome = .{
    .refresh_goal = "刷新目标",
    .plan_refresh = "刷新",
};

const goal_plan_refresh_chrome_ja: GoalPlanRefreshChrome = .{
    .refresh_goal = "目標を更新",
    .plan_refresh = "更新",
};

/// Composer Set goal and Clear goal for the resolved locale. Same
/// resolve path as GoalPlanRefreshChrome. English matches the former
/// hardcoded copy. Distinct from Refresh goal / plan Refresh
/// (`GoalPlanRefreshChrome`) so the set/clear verbs stay independently
/// evolvable. Wire ids / on-press stay English (`goal_set` /
/// `goal_clear`).
pub const GoalActionChrome = struct {
    set_goal: []const u8,
    clear_goal: []const u8,
};

const goal_action_chrome_en: GoalActionChrome = .{
    .set_goal = "Set goal",
    .clear_goal = "Clear goal",
};

const goal_action_chrome_zh_cn: GoalActionChrome = .{
    .set_goal = "设置目标",
    .clear_goal = "清除目标",
};

const goal_action_chrome_ja: GoalActionChrome = .{
    .set_goal = "目標を設定",
    .clear_goal = "目標をクリア",
};

/// Composer Goal empty label (`No goal`) for the resolved locale.
/// Same resolve path as GoalActionChrome. English matches the former
/// hardcoded copy. Distinct from Set goal / Clear goal
/// (`GoalActionChrome`), Refresh goal / plan Refresh
/// (`GoalPlanRefreshChrome`), Goal Status placeholder
/// (`ComposerChrome.status`), and Goal Status display
/// (`GoalStatusChrome`) so the empty label stays independently
/// evolvable. Objective text stays data. Wire ids stay English
/// (`{goal_label}`).
pub const GoalEmptyChrome = struct {
    no_goal: []const u8,
};

const goal_empty_chrome_en: GoalEmptyChrome = .{
    .no_goal = "No goal",
};

const goal_empty_chrome_zh_cn: GoalEmptyChrome = .{
    .no_goal = "无目标",
};

const goal_empty_chrome_ja: GoalEmptyChrome = .{
    .no_goal = "目標なし",
};

/// Composer Goal Status picker-row and selected-chip display labels
/// for the resolved locale. Same resolve path as GoalEmptyChrome.
/// English is title-case chrome for Codex / Waku `ThreadGoalStatus`
/// (`Active` / `Paused` / `Blocked` / `Usage limited` /
/// `Budget limited` / `Complete`). Distinct from Goal Status
/// placeholder (`ComposerChrome.status`), Set/Clear
/// (`GoalActionChrome`), empty No goal (`GoalEmptyChrome`),
/// Refresh goal / plan Refresh (`GoalPlanRefreshChrome`), and
/// Background settled Completed (`BackgroundChrome.settled_completed`)
/// so Goal Status stays independently evolvable. Wire names /
/// on-press `pick_goal_status` / stored session status stay English
/// (`active` / `paused` / `blocked` / `usageLimited` /
/// `budgetLimited` / `complete`).
pub const GoalStatusChrome = struct {
    active: []const u8,
    paused: []const u8,
    blocked: []const u8,
    usage_limited: []const u8,
    budget_limited: []const u8,
    complete: []const u8,

    /// `id` is a Codex `ThreadGoalStatus` wire name (`active` /
    /// `paused` / `blocked` / `usageLimited` / `budgetLimited` /
    /// `complete`). Unknown ids fall through to Active.
    pub fn labelForId(self: GoalStatusChrome, id: []const u8) []const u8 {
        if (std.mem.eql(u8, id, "paused")) return self.paused;
        if (std.mem.eql(u8, id, "blocked")) return self.blocked;
        if (std.mem.eql(u8, id, "usageLimited")) return self.usage_limited;
        if (std.mem.eql(u8, id, "budgetLimited")) return self.budget_limited;
        if (std.mem.eql(u8, id, "complete")) return self.complete;
        return self.active;
    }
};

const goal_status_chrome_en: GoalStatusChrome = .{
    .active = "Active",
    .paused = "Paused",
    .blocked = "Blocked",
    .usage_limited = "Usage limited",
    .budget_limited = "Budget limited",
    .complete = "Complete",
};

const goal_status_chrome_zh_cn: GoalStatusChrome = .{
    .active = "进行中",
    .paused = "已暂停",
    .blocked = "已阻塞",
    .usage_limited = "用量受限",
    .budget_limited = "预算受限",
    .complete = "已完成",
};

const goal_status_chrome_ja: GoalStatusChrome = .{
    .active = "進行中",
    .paused = "一時停止",
    .blocked = "ブロック中",
    .usage_limited = "使用量制限",
    .budget_limited = "予算制限",
    .complete = "完了",
};

/// Settings Usage Cost quality panel, LiteLLM Rates status, and
/// five-tile metric-strip labels for the resolved locale. Same
/// resolve path as GoalEmptyChrome. English matches the former
/// hardcoded copy. Distinct from UsageViewChrome so Cost|Tokens
/// chips stay independently evolvable from quality / rates /
/// tile labels. One `cache_savings` field is shared by the quality
/// row and the metric tile. `token` stays Latin in zh-CN (same
/// rule as UsageViewChrome Tokens). Daemon `errors[]` notice text
/// stays English data this cut. Wire / status enums stay
/// English (`fresh` / `cached` / `unavailable`).
pub const UsageCostQualityChrome = struct {
    cost_quality: []const u8,
    provider_reported: []const u8,
    model_priced: []const u8,
    unpriced: []const u8,
    cache_savings: []const u8,
    processed_tokens: []const u8,
    cached_input: []const u8,
    uncached_input: []const u8,
    output: []const u8,
    rates_fresh: []const u8,
    rates_cached: []const u8,
    rates_unavailable: []const u8,
    per_active_month: []const u8,
    per_active_day: []const u8,
    of_observed_input: []const u8,
    cache_writes: []const u8,
    includes_reasoning_prefix: []const u8,
    includes_reasoning_suffix: []const u8,
    raw_cost: []const u8,
    vs_full_input_rates: []const u8,
};

const usage_cost_quality_chrome_en: UsageCostQualityChrome = .{
    .cost_quality = "Cost quality",
    .provider_reported = "Provider reported",
    .model_priced = "Model priced",
    .unpriced = "Unpriced",
    .cache_savings = "Cache savings",
    .processed_tokens = "Processed tokens",
    .cached_input = "Cached input",
    .uncached_input = "Uncached input",
    .output = "Output",
    .rates_fresh = "Rates fresh",
    .rates_cached = "Rates cached",
    .rates_unavailable = "Rates unavailable",
    .per_active_month = "per active month",
    .per_active_day = "per active day",
    .of_observed_input = "of observed input",
    .cache_writes = "cache writes",
    .includes_reasoning_prefix = "includes ",
    .includes_reasoning_suffix = " reasoning",
    .raw_cost = "raw cost",
    .vs_full_input_rates = "vs full input rates",
};

const usage_cost_quality_chrome_zh_cn: UsageCostQualityChrome = .{
    .cost_quality = "费用质量",
    .provider_reported = "提供商上报",
    .model_priced = "模型定价",
    .unpriced = "未定价",
    .cache_savings = "缓存节省",
    .processed_tokens = "已处理 token",
    .cached_input = "缓存输入",
    .uncached_input = "非缓存输入",
    .output = "输出",
    .rates_fresh = "费率最新",
    .rates_cached = "费率缓存",
    .rates_unavailable = "费率不可用",
    .per_active_month = "每活跃月",
    .per_active_day = "每活跃日",
    .of_observed_input = "占观测输入",
    .cache_writes = "缓存写入",
    .includes_reasoning_prefix = "含 ",
    .includes_reasoning_suffix = " 推理",
    .raw_cost = "原始费用",
    .vs_full_input_rates = "对比完整输入费率",
};

const usage_cost_quality_chrome_ja: UsageCostQualityChrome = .{
    .cost_quality = "コスト品質",
    .provider_reported = "プロバイダー報告",
    .model_priced = "モデル価格",
    .unpriced = "未価格",
    .cache_savings = "キャッシュ節約",
    .processed_tokens = "処理済みトークン",
    .cached_input = "キャッシュ入力",
    .uncached_input = "非キャッシュ入力",
    .output = "出力",
    .rates_fresh = "レート最新",
    .rates_cached = "レートキャッシュ",
    .rates_unavailable = "レート利用不可",
    .per_active_month = "アクティブ月あたり",
    .per_active_day = "アクティブ日あたり",
    .of_observed_input = "の観測入力",
    .cache_writes = "キャッシュ書き込み",
    .includes_reasoning_prefix = "",
    .includes_reasoning_suffix = " の推論を含む",
    .raw_cost = "生コスト",
    .vs_full_input_rates = "全入力レート比",
};

/// Settings Usage Daily scan-footer unit labels for the resolved
/// locale. Same resolve path as UsageCostQualityChrome. English
/// matches the former hardcoded copy (`{d} files`, `{d} skipped`,
/// `{d} records`). Distinct from UsageCostQualityChrome so the
/// footer units stay independently evolvable. ` · ` separators and
/// Latin `{d:.1}s` stay in every locale. Daemon `errors[]` notice
/// text stays English data this cut.
pub const UsageScanFooterChrome = struct {
    files: []const u8,
    skipped: []const u8,
    records: []const u8,
};

const usage_scan_footer_chrome_en: UsageScanFooterChrome = .{
    .files = "files",
    .skipped = "skipped",
    .records = "records",
};

const usage_scan_footer_chrome_zh_cn: UsageScanFooterChrome = .{
    .files = "文件",
    .skipped = "已跳过",
    .records = "记录",
};

const usage_scan_footer_chrome_ja: UsageScanFooterChrome = .{
    .files = "ファイル",
    .skipped = "スキップ",
    .records = "レコード",
};

/// Settings Usage sessions unit and empty-state connect-daemon hint
/// for the resolved locale. Same resolve path as
/// UsageScanFooterChrome. English matches the former hardcoded copy
/// (`{d} sessions`, ` · {d} sessions`, `Connect a daemon for usage
/// history`). Distinct from UsageScanFooterChrome so the sessions
/// unit stays independently evolvable. Numbers and middle-dot ` · `
/// stay in every locale. Daemon `errors[]` notice text stays English
/// data this cut.
pub const UsageSessionsChrome = struct {
    sessions: []const u8,
    connect_daemon: []const u8,
};

const usage_sessions_chrome_en: UsageSessionsChrome = .{
    .sessions = "sessions",
    .connect_daemon = "Connect a daemon for usage history",
};

const usage_sessions_chrome_zh_cn: UsageSessionsChrome = .{
    .sessions = "会话",
    .connect_daemon = "连接守护进程以查看用量历史",
};

const usage_sessions_chrome_ja: UsageSessionsChrome = .{
    .sessions = "セッション",
    .connect_daemon = "デーモンに接続して使用量履歴を表示",
};

/// Composer Usage meter plan-usage hints, empty context, Plan
/// limits header, and Resets soon / Resets in {d}m|h|d for the
/// resolved locale. Same resolve path as UsageSessionsChrome.
/// English matches the former hardcoded copy (`Connect a daemon for
/// plan usage`, `Loading plan usage…`, `Plan usage unconfigured`,
/// `Plan usage unavailable`, `Nothing measured yet`, `Plan limits`,
/// `Plan limits · {s}`, `Resets soon`, `Resets in {d}m` / `{d}h` /
/// `{d}d`). Distinct from UsageSessionsChrome so the Settings Usage
/// history connect hint (`Connect a daemon for usage history`) stays
/// independently evolvable. Numbers, Latin unit letters `m` / `h` /
/// `d`, and middle-dot ` · ` stay in every locale. Daemon plan
/// window labels / planLabel from the wire stay English data this
/// cut.
pub const UsageMeterChrome = struct {
    connect_hint: []const u8,
    loading_hint: []const u8,
    unconfigured_hint: []const u8,
    unavailable_hint: []const u8,
    nothing_measured: []const u8,
    plan_limits: []const u8,
    resets_soon: []const u8,
    resets_in: []const u8,
};

const usage_meter_chrome_en: UsageMeterChrome = .{
    .connect_hint = "Connect a daemon for plan usage",
    .loading_hint = "Loading plan usage…",
    .unconfigured_hint = "Plan usage unconfigured",
    .unavailable_hint = "Plan usage unavailable",
    .nothing_measured = "Nothing measured yet",
    .plan_limits = "Plan limits",
    .resets_soon = "Resets soon",
    .resets_in = "Resets in",
};

const usage_meter_chrome_zh_cn: UsageMeterChrome = .{
    .connect_hint = "连接守护进程以查看套餐用量",
    .loading_hint = "正在加载套餐用量…",
    .unconfigured_hint = "套餐用量未配置",
    .unavailable_hint = "套餐用量不可用",
    .nothing_measured = "尚无用量",
    .plan_limits = "套餐限额",
    .resets_soon = "即将重置",
    .resets_in = "剩余",
};

const usage_meter_chrome_ja: UsageMeterChrome = .{
    .connect_hint = "デーモンに接続してプラン使用量を表示",
    .loading_hint = "プラン使用量を読み込み中…",
    .unconfigured_hint = "プラン使用量は未設定",
    .unavailable_hint = "プラン使用量は利用不可",
    .nothing_measured = "まだ計測なし",
    .plan_limits = "プラン上限",
    .resets_soon = "まもなくリセット",
    .resets_in = "あと",
};

/// Settings Usage local session cards (Context window / empty
/// context / Thread goal tokens / empty thread-goal) plus the
/// composer Usage meter panel Context window heading for the
/// resolved locale. Same resolve path as UsageMeterChrome.
/// English matches the former hardcoded copy. Distinct from
/// `Chrome.usage` (nav "Usage"), UsageMeterChrome (plan-usage
/// hints / Nothing measured yet / Plan limits),
/// UsageSessionsChrome (sessions unit / connect daemon for
/// history), UsageViewChrome (Daily/Monthly/Projects chips),
/// and FilterChrome `no_project_usage` / `no_matching_projects`
/// so local session chrome stays independently evolvable. Wire
/// ids / numeric usage values stay English/data.
pub const UsageLocalChrome = struct {
    context_window: []const u8,
    no_context_usage: []const u8,
    thread_goal_tokens: []const u8,
    no_thread_goal_usage: []const u8,
};

const usage_local_chrome_en: UsageLocalChrome = .{
    .context_window = "Context window",
    .no_context_usage = "No context usage reported yet",
    .thread_goal_tokens = "Thread goal tokens",
    .no_thread_goal_usage = "No thread goal usage",
};

const usage_local_chrome_zh_cn: UsageLocalChrome = .{
    .context_window = "上下文窗口",
    .no_context_usage = "尚未报告上下文用量",
    .thread_goal_tokens = "线程目标 Token",
    .no_thread_goal_usage = "没有线程目标用量",
};

const usage_local_chrome_ja: UsageLocalChrome = .{
    .context_window = "コンテキストウィンドウ",
    .no_context_usage = "コンテキスト使用量はまだ報告されていません",
    .thread_goal_tokens = "スレッド目標トークン",
    .no_thread_goal_usage = "スレッド目標の使用量はありません",
};

/// Settings Providers status, Enable/Disable chip, Apply, Copy
/// install/login, and First-party default for the resolved locale.
/// Same resolve path as UsageSessionsChrome. English matches the
/// former hardcoded copy. Distinct from ComputerUseChrome Enable /
/// Off so Providers Enable/Disable stay independently evolvable.
/// Provider wire names, binary paths, install/login *commands*, and
/// on-press ids stay English. Longer detail transport notes /
/// `fx_login_note` / `other_install_hint` and `Binary:` / `Path:`
/// prefixes live in `ProvidersDetailChrome`.
pub const ProvidersChrome = struct {
    available: []const u8,
    not_found: []const u8,
    first_party: []const u8,
    enable: []const u8,
    disable: []const u8,
    apply: []const u8,
    copy_install: []const u8,
    copy_login: []const u8,
};

const providers_chrome_en: ProvidersChrome = .{
    .available = "Available",
    .not_found = "Not found",
    .first_party = "First-party default",
    .enable = "Enable",
    .disable = "Disable",
    .apply = "Use for this session",
    .copy_install = "Copy install command",
    .copy_login = "Copy login command",
};

const providers_chrome_zh_cn: ProvidersChrome = .{
    .available = "可用",
    .not_found = "未找到",
    .first_party = "第一方默认",
    .enable = "启用",
    .disable = "禁用",
    .apply = "用于此会话",
    .copy_install = "复制安装命令",
    .copy_login = "复制登录命令",
};

const providers_chrome_ja: ProvidersChrome = .{
    .available = "利用可能",
    .not_found = "見つかりません",
    .first_party = "ファーストパーティ既定",
    .enable = "有効",
    .disable = "無効",
    .apply = "このセッションで使う",
    .copy_install = "インストールコマンドをコピー",
    .copy_login = "ログインコマンドをコピー",
};

/// Settings Providers muted detail transport notes, fx login notes,
/// other-CLI PATH hint, and `Binary:` / `Path:` prefixes for the
/// resolved locale. Same resolve path as ProvidersChrome. English
/// matches the former hardcoded copy. Distinct from ProvidersChrome
/// so status / Enable / Apply / Copy / First-party stay independently
/// evolvable. CLI flags, wire names, binary paths, and install/login
/// *commands* stay English. Prefix values keep the trailing colon; the
/// space after the colon stays in the `detailText` format string.
pub const ProvidersDetailChrome = struct {
    catalog_detail_note: []const u8,
    fx_transport_note: []const u8,
    acp_transport_note: []const u8,
    grok_transport_note: []const u8,
    claude_transport_note: []const u8,
    codex_transport_note: []const u8,
    amp_transport_note: []const u8,
    pi_transport_note: []const u8,
    fx_login_note: []const u8,
    fx_login_codex_note: []const u8,
    other_install_hint: []const u8,
    binary_prefix: []const u8,
    path_prefix: []const u8,
};

const providers_detail_chrome_en: ProvidersDetailChrome = .{
    .catalog_detail_note = "Status is a PATH --help probe. Send stays demo this cut.",
    .fx_transport_note = "Live path is one-shot fx acp via acp-proxy.",
    .acp_transport_note = "Live Send is one-shot acp via acp-proxy when Available (ACP image content blocks when attached).",
    .grok_transport_note = "Live Send is one-shot grok agent stdio via acp-proxy when Available (ACP image content blocks when attached).",
    .claude_transport_note = "Live Send is one-shot claude -p --output-format stream-json --forward-subagent-text when Available (later Sends --resume {fx_session_id} when stored; image path in the -p prompt when attached).",
    .codex_transport_note = "Live Send is one-shot codex exec when Available (`--image` when attached).",
    .amp_transport_note = "Live Send is one-shot amp -x / --execute when Available (`@path` when attached).",
    .pi_transport_note = "Live Send is one-shot pi --mode json when Available (`@path` when attached).",
    .fx_login_note = "Faku does not detect auth state from the --help probe. Copy is a convenience, not sign-in UI or OAuth.",
    .fx_login_codex_note = "Optional: fx login grok / fx login codex (no Gateway required).",
    .other_install_hint = "Install that CLI on PATH, then Refresh.",
    .binary_prefix = "Binary:",
    .path_prefix = "Path:",
};

const providers_detail_chrome_zh_cn: ProvidersDetailChrome = .{
    .catalog_detail_note = "状态来自 PATH --help 探测。本轮 Send 仍为演示。",
    .fx_transport_note = "实际路径是通过 acp-proxy 的一次性 fx acp。",
    .acp_transport_note = "可用时，实际 Send 是通过 acp-proxy 的一次性 acp（附加图片时使用 ACP 图像内容块）。",
    .grok_transport_note = "可用时，实际 Send 是通过 acp-proxy 的一次性 grok agent stdio（附加图片时使用 ACP 图像内容块）。",
    .claude_transport_note = "可用时，实际 Send 是一次性 claude -p --output-format stream-json --forward-subagent-text（已存储时后续 Send 使用 --resume {fx_session_id}；附加图片时在 -p 提示中放入路径）。",
    .codex_transport_note = "可用时，实际 Send 是一次性 codex exec（附加时使用 `--image`）。",
    .amp_transport_note = "可用时，实际 Send 是一次性 amp -x / --execute（附加时使用 `@path`）。",
    .pi_transport_note = "可用时，实际 Send 是一次性 pi --mode json（附加时使用 `@path`）。",
    .fx_login_note = "Faku 不会从 --help 探测中检测认证状态。复制仅为便利，不是登录界面或 OAuth。",
    .fx_login_codex_note = "可选：fx login grok / fx login codex（无需 Gateway）。",
    .other_install_hint = "将该 CLI 安装到 PATH，然后刷新。",
    .binary_prefix = "二进制:",
    .path_prefix = "路径:",
};

const providers_detail_chrome_ja: ProvidersDetailChrome = .{
    .catalog_detail_note = "状態は PATH --help のプローブです。現状の Send はデモのままです。",
    .fx_transport_note = "実経路は acp-proxy 経由のワンショット fx acp です。",
    .acp_transport_note = "利用可能なとき、実際の Send は acp-proxy 経由のワンショット acp です（添付時は ACP 画像コンテンツブロック）。",
    .grok_transport_note = "利用可能なとき、実際の Send は acp-proxy 経由のワンショット grok agent stdio です（添付時は ACP 画像コンテンツブロック）。",
    .claude_transport_note = "利用可能なとき、実際の Send はワンショット claude -p --output-format stream-json --forward-subagent-text です（保存済みなら後続 Send は --resume {fx_session_id}；添付時は -p プロンプトに画像パス）。",
    .codex_transport_note = "利用可能なとき、実際の Send はワンショット codex exec です（添付時は `--image`）。",
    .amp_transport_note = "利用可能なとき、実際の Send はワンショット amp -x / --execute です（添付時は `@path`）。",
    .pi_transport_note = "利用可能なとき、実際の Send はワンショット pi --mode json です（添付時は `@path`）。",
    .fx_login_note = "Faku は --help プローブから認証状態を検出しません。コピーは便宜であり、サインイン UI や OAuth ではありません。",
    .fx_login_codex_note = "任意: fx login grok / fx login codex（Gateway は不要）。",
    .other_install_hint = "その CLI を PATH にインストールしてから更新してください。",
    .binary_prefix = "バイナリ:",
    .path_prefix = "パス:",
};

/// Settings Skills empty-state Open a project / No skills found for
/// the resolved locale. Same resolve path as ProvidersDetailChrome.
/// English matches the former hardcoded copy. Distinct from
/// FilterChrome (filter placeholder / Usage Projects empty) and
/// RightPanelChrome (`Open a project to browse its files` / `No
/// project open`) so Skills empty stays independently evolvable.
/// Composer `$` insert empty reuses the same strings via
/// `skills.emptyHint`. Wire ids stay English.
pub const SkillsEmptyChrome = struct {
    open_project: []const u8,
    no_skills_found: []const u8,
};

const skills_empty_chrome_en: SkillsEmptyChrome = .{
    .open_project = "Open a project",
    .no_skills_found = "No skills found",
};

const skills_empty_chrome_zh_cn: SkillsEmptyChrome = .{
    .open_project = "打开项目",
    .no_skills_found = "未找到技能",
};

const skills_empty_chrome_ja: SkillsEmptyChrome = .{
    .open_project = "プロジェクトを開く",
    .no_skills_found = "スキルが見つかりません",
};

/// Map a POSIX locale id (or env fragment) onto english / simplified_chinese /
/// japanese. Never returns `.system`. Empty / C / unknown → english.
/// Tests pass an explicit id so they do not depend on the runner's LANG.
pub fn fromLocaleId(id: []const u8) LanguagePreference {
    const before_dot = if (std.mem.indexOfScalar(u8, id, '.')) |dot| id[0..dot] else id;
    if (before_dot.len == 0) return .english;

    var buf: [128]u8 = undefined;
    const n = @min(before_dot.len, buf.len);
    for (before_dot[0..n], 0..) |c, i| {
        buf[i] = if (c == '_') '-' else std.ascii.toLower(c);
    }
    const loc = buf[0..n];

    if (std.mem.eql(u8, loc, "zh-cn") or
        std.mem.eql(u8, loc, "zh-sg") or
        std.mem.startsWith(u8, loc, "zh-hans"))
        return .simplified_chinese;
    if (std.mem.eql(u8, loc, "ja") or std.mem.startsWith(u8, loc, "ja-"))
        return .japanese;
    return .english;
}

/// LC_ALL, else LC_MESSAGES, else LANG, else `"en"`. Empty values are skipped.
/// Native has no locale API; the window copies these process env strings at boot.
pub fn pickSystemLocaleId(lc_all: []const u8, lc_messages: []const u8, lang: []const u8) []const u8 {
    if (lc_all.len > 0) return lc_all;
    if (lc_messages.len > 0) return lc_messages;
    if (lang.len > 0) return lang;
    return "en";
}

/// Resolved chrome locale. `.system` follows `system_locale_id`; explicit
/// preferences ignore it (English stays English even when LANG is ja).
pub fn resolve(preference: LanguagePreference, system_locale_id: []const u8) LanguagePreference {
    if (preference == .system) return fromLocaleId(system_locale_id);
    return preference;
}

pub fn chromeFor(preference: LanguagePreference, system_locale_id: []const u8) Chrome {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => chrome_zh_cn,
        .japanese => chrome_ja,
        .system, .english => chrome_en,
    };
}

/// Sidebar date-bucket titles for the resolved chrome locale. Callers
/// pass Model `language_preference` + `system_locale_id`; this file
/// does not read process env.
pub fn datesFor(preference: LanguagePreference, system_locale_id: []const u8) Dates {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => dates_zh_cn,
        .japanese => dates_ja,
        .system, .english => dates_en,
    };
}

/// Sidebar New Task / Search / folder / session chrome for the resolved
/// locale. Callers pass Model `language_preference` + `system_locale_id`;
/// this file does not read process env.
pub fn sidebarFor(preference: LanguagePreference, system_locale_id: []const u8) Sidebar {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => sidebar_zh_cn,
        .japanese => sidebar_ja,
        .system, .english => sidebar_en,
    };
}

/// Composer / Settings General Ask / Auto / Full access for the
/// resolved locale. Callers pass Model `language_preference` +
/// `system_locale_id`; this file does not read process env.
pub fn accessFor(preference: LanguagePreference, system_locale_id: []const u8) Access {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => access_zh_cn,
        .japanese => access_ja,
        .system, .english => access_en,
    };
}

/// Composer / Settings General effort chrome for the resolved locale.
/// Callers pass Model `language_preference` + `system_locale_id`; this
/// file does not read process env.
pub fn effortFor(preference: LanguagePreference, system_locale_id: []const u8) Effort {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => effort_zh_cn,
        .japanese => effort_ja,
        .system, .english => effort_en,
    };
}

/// Composer / Settings General Build / Plan for the resolved locale.
/// Callers pass Model `language_preference` + `system_locale_id`; this
/// file does not read process env.
pub fn interactionFor(preference: LanguagePreference, system_locale_id: []const u8) Interaction {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => interaction_zh_cn,
        .japanese => interaction_ja,
        .system, .english => interaction_en,
    };
}

/// Palette action display labels for the resolved locale. Callers
/// pass Model `language_preference` + `system_locale_id`; this file
/// does not read process env. New Task / Settings / Collapse all
/// folders stay on `sidebarFor` / `chromeFor`.
pub fn paletteFor(preference: LanguagePreference, system_locale_id: []const u8) Palette {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => palette_zh_cn,
        .japanese => palette_ja,
        .system, .english => palette_en,
    };
}

/// Palette overlay section headers, empty-state lines, footer
/// Confirm, and dialog title for the resolved locale. Callers pass
/// Model `language_preference` + `system_locale_id`; this file does
/// not read process env. Action names stay on `paletteFor`. Footer
/// Cancel stays on `commitChromeFor`.
pub fn paletteChromeFor(preference: LanguagePreference, system_locale_id: []const u8) PaletteChrome {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => palette_chrome_zh_cn,
        .japanese => palette_chrome_ja,
        .system, .english => palette_chrome_en,
    };
}

/// Right-panel tab button labels for the resolved locale. Callers
/// pass Model `language_preference` + `system_locale_id`; this file
/// does not read process env. Wire ids stay on `right_panel.Tab`.
pub fn rightPanelTabsFor(preference: LanguagePreference, system_locale_id: []const u8) RightPanelTabs {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => right_panel_tabs_zh_cn,
        .japanese => right_panel_tabs_ja,
        .system, .english => right_panel_tabs_en,
    };
}

/// Right-panel Diff filter + Files/Background empty-state chrome
/// (including Files empty secondary / Loading files…) plus Browser
/// start page / Open in browser / Open in Terminal for the resolved
/// locale. Callers pass Model `language_preference` +
/// `system_locale_id`; this file does not read process env. Wire ids /
/// on-press / filter text stay English.
pub fn rightPanelChromeFor(preference: LanguagePreference, system_locale_id: []const u8) RightPanelChrome {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => right_panel_chrome_zh_cn,
        .japanese => right_panel_chrome_ja,
        .system, .english => right_panel_chrome_en,
    };
}

/// Composer project-row Pick folder / Reveal folder / Open in Editor /
/// Copy path for the resolved locale. Callers pass Model
/// `language_preference` + `system_locale_id`; this file does not read
/// process env. Open in Terminal stays on `rightPanelChromeFor`.
pub fn composerProjectChromeFor(preference: LanguagePreference, system_locale_id: []const u8) ComposerProjectChrome {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => composer_project_chrome_zh_cn,
        .japanese => composer_project_chrome_ja,
        .system, .english => composer_project_chrome_en,
    };
}

/// Review Diff header title / Cancel / source chips / gap expand
/// Start / End / Both / All for the resolved locale. Callers pass
/// Model `language_preference` + `system_locale_id`; this file
/// does not read process env. Wire ids / on-press stay English.
pub fn reviewDiffChromeFor(preference: LanguagePreference, system_locale_id: []const u8) ReviewDiffChrome {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => review_diff_chrome_zh_cn,
        .japanese => review_diff_chrome_ja,
        .system, .english => review_diff_chrome_en,
    };
}

/// Background row kind / status / stop·dismiss chrome for the
/// resolved locale. Callers pass Model `language_preference` +
/// `system_locale_id`; this file does not read process env. Wire
/// ids / on-press stay English. Empty-state strings stay on
/// `rightPanelChromeFor`.
pub fn backgroundChromeFor(preference: LanguagePreference, system_locale_id: []const u8) BackgroundChrome {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => background_chrome_zh_cn,
        .japanese => background_chrome_ja,
        .system, .english => background_chrome_en,
    };
}

/// Environment info-button a11y + dropdown-menu header / menu-item
/// chrome plus the dropdown Background section header for the resolved
/// locale. Callers pass Model `language_preference` +
/// `system_locale_id`; this file does not read process env. Wire ids /
/// on-press stay English.
pub fn environmentChromeFor(preference: LanguagePreference, system_locale_id: []const u8) EnvironmentChrome {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => environment_chrome_zh_cn,
        .japanese => environment_chrome_ja,
        .system, .english => environment_chrome_en,
    };
}

/// Settings Skills / Usage Projects filter chrome (including empty-state
/// No project usage / No matching projects) for the resolved locale.
/// Callers pass Model `language_preference` + `system_locale_id`;
/// this file does not read process env. Wire ids / on-input /
/// filter text stay English.
pub fn filterChromeFor(preference: LanguagePreference, system_locale_id: []const u8) FilterChrome {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => filter_chrome_zh_cn,
        .japanese => filter_chrome_ja,
        .system, .english => filter_chrome_en,
    };
}

/// Files right-panel file-preview toolbar chrome for the resolved
/// locale. Callers pass Model `language_preference` +
/// `system_locale_id`; this file does not read process env. Wire ids /
/// on-press / on-input stay English.
pub fn filePreviewChromeFor(preference: LanguagePreference, system_locale_id: []const u8) FilePreviewChrome {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => file_preview_chrome_zh_cn,
        .japanese => file_preview_chrome_ja,
        .system, .english => file_preview_chrome_en,
    };
}

/// Files preview error/save chrome for the resolved locale. Callers
/// pass Model `language_preference` + `system_locale_id`; this file
/// does not read process env. Distinct from FilePreviewChrome
/// toolbar / truncated·binary banners and from
/// FilePreviewFindMatchChrome. Paths / file contents stay
/// English/data.
pub fn filePreviewErrorChromeFor(preference: LanguagePreference, system_locale_id: []const u8) FilePreviewErrorChrome {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => file_preview_error_chrome_zh_cn,
        .japanese => file_preview_error_chrome_ja,
        .system, .english => file_preview_error_chrome_en,
    };
}

/// Commit message composer chrome for the resolved locale. Callers
/// pass Model `language_preference` + `system_locale_id`; this file
/// does not read process env. Wire ids / on-press / on-input stay
/// English. Branch-picker / create / delete / push-confirm chrome
/// lives on `branchChromeFor`. Commit attach-status lives on
/// `commitAttachStatusChromeFor`.
pub fn commitChromeFor(preference: LanguagePreference, system_locale_id: []const u8) CommitChrome {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => commit_chrome_zh_cn,
        .japanese => commit_chrome_ja,
        .system, .english => commit_chrome_en,
    };
}

/// Composer branch-picker dropdown plus New branch / New worktree /
/// Delete branch / Push-confirm composer-row chrome for the resolved
/// locale. Callers pass Model `language_preference` +
/// `system_locale_id`; this file does not read process env. Wire ids /
/// on-press / on-input stay English. Force / Push (no ellipsis) /
/// Cancel stay on `commitChromeFor`. Workspace picker chrome lives
/// on `workspaceChromeFor`. Branch-op attach status lives on
/// `branchOpStatusChromeFor`.
pub fn branchChromeFor(preference: LanguagePreference, system_locale_id: []const u8) BranchChrome {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => branch_chrome_zh_cn,
        .japanese => branch_chrome_ja,
        .system, .english => branch_chrome_en,
    };
}

/// Composer workspace picker chrome for the resolved locale. Callers
/// pass Model `language_preference` + `system_locale_id`; this file
/// does not read process env. Wire ids / on-press stay English.
/// Worktree stays Latin in zh-CN / ja. Send-prep attach status
/// lives on `worktreeStatusChromeFor`.
pub fn workspaceChromeFor(preference: LanguagePreference, system_locale_id: []const u8) WorkspaceChrome {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => workspace_chrome_zh_cn,
        .japanese => workspace_chrome_ja,
        .system, .english => workspace_chrome_en,
    };
}

/// Send-prep Creating worktree… / Could not create worktree. attach
/// status for the resolved locale. Callers pass Model
/// `language_preference` + `system_locale_id`; this file does not
/// read process env. Distinct from WorkspaceChrome picker labels /
/// BranchChrome / CommitChrome. Worktree stays Latin in zh-CN / ja.
/// Branch-op attach statuses live on `branchOpStatusChromeFor`.
pub fn worktreeStatusChromeFor(preference: LanguagePreference, system_locale_id: []const u8) WorktreeStatusChrome {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => worktree_status_chrome_zh_cn,
        .japanese => worktree_status_chrome_ja,
        .system, .english => worktree_status_chrome_en,
    };
}

/// Branch-menu Could not check out branch. / Already checked out in
/// another worktree. / Could not create branch. / Could not delete
/// branch. / Could not fetch. / Could not push. attach status for
/// the resolved locale. Callers pass Model `language_preference` +
/// `system_locale_id`; this file does not read process env. Distinct
/// from BranchChrome menu labels / CommitChrome / WorktreeStatusChrome
/// / WorkspaceChrome. Worktree stays Latin in zh-CN / ja. Commit
/// attach-status lives on `commitAttachStatusChromeFor`.
pub fn branchOpStatusChromeFor(preference: LanguagePreference, system_locale_id: []const u8) BranchOpStatusChrome {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => branch_op_status_chrome_zh_cn,
        .japanese => branch_op_status_chrome_ja,
        .system, .english => branch_op_status_chrome_en,
    };
}

/// Commit… Enter a commit message. / Could not commit. / Nothing
/// staged to commit. / Could not generate a commit message. attach
/// status for the resolved locale. Callers pass Model
/// `language_preference` + `system_locale_id`; this file does not
/// read process env. Distinct from CommitChrome dialog labels /
/// pending Generating… / BranchOpStatusChrome / WorktreeStatusChrome
/// / WorkspaceChrome.
pub fn commitAttachStatusChromeFor(preference: LanguagePreference, system_locale_id: []const u8) CommitAttachStatusChrome {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => commit_attach_status_chrome_zh_cn,
        .japanese => commit_attach_status_chrome_ja,
        .system, .english => commit_attach_status_chrome_en,
    };
}

/// Daemon-dir in-app browser chrome for the resolved locale. Callers
/// pass Model `language_preference` + `system_locale_id`; this file
/// does not read process env. Wire ids / on-press stay English.
/// Cancel stays on `commitChromeFor`.
pub fn daemonDirChromeFor(preference: LanguagePreference, system_locale_id: []const u8) DaemonDirChrome {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => daemon_dir_chrome_zh_cn,
        .japanese => daemon_dir_chrome_ja,
        .system, .english => daemon_dir_chrome_en,
    };
}

/// Session-switcher dialog title and Switch for the resolved locale.
/// Callers pass Model `language_preference` + `system_locale_id`;
/// this file does not read process env. Wire ids / on-press /
/// on-dismiss stay English. Cancel stays on `commitChromeFor`.
pub fn switcherChromeFor(preference: LanguagePreference, system_locale_id: []const u8) SwitcherChrome {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => switcher_chrome_zh_cn,
        .japanese => switcher_chrome_ja,
        .system, .english => switcher_chrome_en,
    };
}

/// Settings General / project-edit Workspace path placeholders for
/// the resolved locale. Callers pass Model `language_preference` +
/// `system_locale_id`; this file does not read process env. Wire
/// ids / on-input stay English. Typed path text stays data.
pub fn workspacePathChromeFor(preference: LanguagePreference, system_locale_id: []const u8) WorkspacePathChrome {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => workspace_path_chrome_zh_cn,
        .japanese => workspace_path_chrome_ja,
        .system, .english => workspace_path_chrome_en,
    };
}

/// Session title rename placeholders for the resolved locale. Callers
/// pass Model `language_preference` + `system_locale_id`; this file
/// does not read process env. Wire ids / on-input stay English.
/// Catalog titles stay English `untitled` (data).
pub fn untitledChromeFor(preference: LanguagePreference, system_locale_id: []const u8) UntitledChrome {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => untitled_chrome_zh_cn,
        .japanese => untitled_chrome_ja,
        .system, .english => untitled_chrome_en,
    };
}

/// Header untitled display title for the resolved locale. Callers
/// pass Model `language_preference` + `system_locale_id`; this file
/// does not read process env. Distinct from Sidebar.new_task so
/// header untitled chrome stays independently evolvable. Catalog
/// titles stay English `untitled` (data). Wire ids / on-press stay
/// English (`edit_session_title`).
pub fn headerUntitledChromeFor(preference: LanguagePreference, system_locale_id: []const u8) HeaderUntitledChrome {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => header_untitled_chrome_zh_cn,
        .japanese => header_untitled_chrome_ja,
        .system, .english => header_untitled_chrome_en,
    };
}

/// Settings General daemon address placeholder for the resolved
/// locale. Callers pass Model `language_preference` +
/// `system_locale_id`; this file does not read process env. Wire
/// ids / on-input stay English. Latin `host:port` in every locale.
/// Typed address text stays data.
pub fn daemonAddressChromeFor(preference: LanguagePreference, system_locale_id: []const u8) DaemonAddressChrome {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => daemon_address_chrome_zh_cn,
        .japanese => daemon_address_chrome_ja,
        .system, .english => daemon_address_chrome_en,
    };
}

/// Settings General field labels and Default model / Effort
/// placeholders for the resolved locale. Callers pass Model
/// `language_preference` + `system_locale_id`; this file does not
/// read process env. Wire ids / on-input / on-press stay English.
/// Latin `FX_MODEL` in every locale. Access / Interaction / Effort
/// chip values stay on `accessFor` / `interactionFor` / `effortFor`.
/// Daemon address placeholder stays on `daemonAddressChromeFor`.
/// Workspace path placeholder stays on `workspacePathChromeFor`.
pub fn settingsGeneralChromeFor(preference: LanguagePreference, system_locale_id: []const u8) SettingsGeneralChrome {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => settings_general_chrome_zh_cn,
        .japanese => settings_general_chrome_ja,
        .system, .english => settings_general_chrome_en,
    };
}

/// OS folder-dialog prompt and missing-picker status for the resolved
/// locale. Callers pass Model `language_preference` +
/// `system_locale_id`; this file does not read process env. Wire ids /
/// on-press stay English. Binary names stay Latin.
pub fn osFolderDialogChromeFor(preference: LanguagePreference, system_locale_id: []const u8) OsFolderDialogChrome {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => os_folder_dialog_chrome_zh_cn,
        .japanese => os_folder_dialog_chrome_ja,
        .system, .english => os_folder_dialog_chrome_en,
    };
}

/// OS image-dialog prompt and missing-picker status for the resolved
/// locale. Callers pass Model `language_preference` +
/// `system_locale_id`; this file does not read process env. Wire ids /
/// on-press stay English. Binary names stay Latin. Filter extensions
/// stay Latin.
pub fn osImageDialogChromeFor(preference: LanguagePreference, system_locale_id: []const u8) OsImageDialogChrome {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => os_image_dialog_chrome_zh_cn,
        .japanese => os_image_dialog_chrome_ja,
        .system, .english => os_image_dialog_chrome_en,
    };
}

/// Composer Image path placeholder, Pick image button, Attach image
/// a11y, Clear image a11y, Attached image a11y, Goal Status picker
/// placeholder / empty label, and Commands toggle chip for the
/// resolved locale. Callers pass Model `language_preference` +
/// `system_locale_id`; this file does not read process env. Wire
/// ids / on-press / on-input stay English. Typed path text stays
/// data. ThreadGoalStatus wire names stay English; picker-row /
/// selected-chip display labels live in `GoalStatusChrome`. Commands
/// `on-press` stays `toggle_commands`. Clear image `on-press`
/// stays `clear_image_attach`.
pub fn composerChromeFor(preference: LanguagePreference, system_locale_id: []const u8) ComposerChrome {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => composer_chrome_zh_cn,
        .japanese => composer_chrome_ja,
        .system, .english => composer_chrome_en,
    };
}

/// Composer primary Send / Stop a11y labels and visible `send_label`
/// for the resolved locale. Callers pass Model
/// `language_preference` + `system_locale_id`; this file does not
/// read process env. Distinct from BackgroundChrome.daemon_stop /
/// ComposerChrome so composer Send/Stop stay independently
/// evolvable. Wire ids / on-press stay English (`send` /
/// `stop_turn`). Visible `send_label` is idle `send` / streaming
/// `stop`; icon-button a11y stays `composer_send_label` /
/// `composer_stop_label`.
pub fn composerSendStopChromeFor(preference: LanguagePreference, system_locale_id: []const u8) ComposerSendStopChrome {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => composer_send_stop_chrome_zh_cn,
        .japanese => composer_send_stop_chrome_ja,
        .system, .english => composer_send_stop_chrome_en,
    };
}

/// Composer textarea idle / streaming placeholders for the resolved
/// locale. Callers pass Model `language_preference` +
/// `system_locale_id`; this file does not read process env. Distinct
/// from QueueChrome / ComposerChrome / ComposerSendStopChrome so
/// composer placeholders stay independently evolvable. Wire ids /
/// on-input / on-submit stay English (`draft_edit` /
/// `composer_enter`). Draft text stays data.
pub fn composerPlaceholderChromeFor(preference: LanguagePreference, system_locale_id: []const u8) ComposerPlaceholderChrome {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => composer_placeholder_chrome_zh_cn,
        .japanese => composer_placeholder_chrome_ja,
        .system, .english => composer_placeholder_chrome_en,
    };
}

/// Empty-transcript welcome title / subtitle for the resolved
/// locale. Callers pass Model `language_preference` +
/// `system_locale_id`; this file does not read process env. Distinct
/// from HeaderUntitledChrome / ComposerPlaceholderChrome / QueueChrome
/// so welcome wording stays independently evolvable. Wire ids stay
/// English. Real session titles and typed draft text stay data.
pub fn welcomeChromeFor(preference: LanguagePreference, system_locale_id: []const u8) WelcomeChrome {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => welcome_chrome_zh_cn,
        .japanese => welcome_chrome_ja,
        .system, .english => welcome_chrome_en,
    };
}

/// Transcript find-bar Previous match / Next match / Close find a11y
/// labels for the resolved locale. Callers pass Model
/// `language_preference` + `system_locale_id`; this file does not
/// read process env. Distinct from FilePreviewChrome
/// previous/next/close file-find / Palette find-in-transcript so
/// transcript find-bar chrome stays independently evolvable. Wire
/// ids / on-press stay English (`find_prev` / `find_next` /
/// `close_find`).
pub fn findBarChromeFor(preference: LanguagePreference, system_locale_id: []const u8) FindBarChrome {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => find_bar_chrome_zh_cn,
        .japanese => find_bar_chrome_ja,
        .system, .english => find_bar_chrome_en,
    };
}

/// Transcript find-bar muted match-position chrome for the resolved
/// locale. Callers pass Model `language_preference` +
/// `system_locale_id`; this file does not read process env. Distinct
/// from FindBarChrome / FilePreviewChrome / FilePreviewFindMatchChrome
/// / TranscriptTurnChrome.match so transcript find-match chrome
/// stays independently evolvable. Numbers stay Latin. Wire ids /
/// on-press / find query stay English.
pub fn findMatchChromeFor(preference: LanguagePreference, system_locale_id: []const u8) FindMatchChrome {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => find_match_chrome_zh_cn,
        .japanese => find_match_chrome_ja,
        .system, .english => find_match_chrome_en,
    };
}

/// Format transcript find-bar `k of N` from the pack's `of_fmt`.
/// Numbers stay Latin. `index` is 1-based.
pub fn formatFindMatchOf(chrome: FindMatchChrome, arena: std.mem.Allocator, index: u32, count: usize) []const u8 {
    if (std.mem.eql(u8, chrome.of_fmt, "{d} / {d}")) {
        return std.fmt.allocPrint(arena, "{d} / {d}", .{ index, count }) catch "match";
    }
    return std.fmt.allocPrint(arena, "{d} of {d}", .{ index, count }) catch "match";
}

/// Files preview find muted match-position chrome for the resolved
/// locale. Callers pass Model `language_preference` +
/// `system_locale_id`; this file does not read process env. Distinct
/// from FindMatchChrome / FindBarChrome / FilePreviewChrome /
/// FilePreviewErrorChrome so file-preview match chrome stays
/// independently evolvable.
/// Numbers stay Latin. `+` cap and ` · ` stay. Wire ids / on-press /
/// on-input / find query / replace text stay English.
pub fn filePreviewFindMatchChromeFor(preference: LanguagePreference, system_locale_id: []const u8) FilePreviewFindMatchChrome {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => file_preview_find_match_chrome_zh_cn,
        .japanese => file_preview_find_match_chrome_ja,
        .system, .english => file_preview_find_match_chrome_en,
    };
}

/// Format Files preview find `n of m · L#line` from the pack's
/// `of_line_fmt`. Numbers stay Latin. `index` is 1-based. `cap` is
/// `"+"` when matches were capped, else `""`.
pub fn formatFilePreviewFindMatchOf(
    chrome: FilePreviewFindMatchChrome,
    arena: std.mem.Allocator,
    index: u32,
    count: u32,
    cap: []const u8,
    line: u32,
) []const u8 {
    if (std.mem.eql(u8, chrome.of_line_fmt, "{d} / {d}{s} · L{d}")) {
        return std.fmt.allocPrint(arena, "{d} / {d}{s} · L{d}", .{ index, count, cap, line }) catch chrome.match;
    }
    return std.fmt.allocPrint(arena, "{d} of {d}{s} · L{d}", .{ index, count, cap, line }) catch chrome.match;
}

/// Header Copy session a11y plus Fork / Rewind button chrome for the
/// resolved locale. Callers pass Model `language_preference` +
/// `system_locale_id`; this file does not read process env. Distinct
/// from Palette.copy_session_id / TranscriptTurnChrome so header
/// session chrome stays independently evolvable. Wire ids /
/// on-press stay English (`copy_session` / `fork` / `rewind`).
pub fn headerSessionChromeFor(preference: LanguagePreference, system_locale_id: []const u8) HeaderSessionChrome {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => header_session_chrome_zh_cn,
        .japanese => header_session_chrome_ja,
        .system, .english => header_session_chrome_en,
    };
}

/// Transcript turn You said / Assistant said a11y for the resolved
/// locale. Callers pass Model `language_preference` +
/// `system_locale_id`; this file does not read process env. Distinct
/// from HeaderSessionChrome / TranscriptTurnChrome so transcript
/// role chrome stays independently evolvable. Wire ids / on-press /
/// turn data stay English.
pub fn transcriptRoleChromeFor(preference: LanguagePreference, system_locale_id: []const u8) TranscriptRoleChrome {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => transcript_role_chrome_zh_cn,
        .japanese => transcript_role_chrome_ja,
        .system, .english => transcript_role_chrome_en,
    };
}

/// Transcript turn Match chip plus per-turn Copy / Fork chrome for
/// the resolved locale. Callers pass Model `language_preference` +
/// `system_locale_id`; this file does not read process env. Distinct
/// from HeaderSessionChrome / TranscriptRoleChrome /
/// Palette.copy_session_id / FindBarChrome / FilePreviewChrome so
/// transcript turn action chrome stays independently evolvable.
/// Wire ids / on-press stay English (`copy_turn:{t.id}` /
/// `fork_turn:{t.id}`).
pub fn transcriptTurnChromeFor(preference: LanguagePreference, system_locale_id: []const u8) TranscriptTurnChrome {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => transcript_turn_chrome_zh_cn,
        .japanese => transcript_turn_chrome_ja,
        .system, .english => transcript_turn_chrome_en,
    };
}

/// Composer queue card Queued / Dismiss all / Remove queued plus
/// transcript Jump to latest chrome for the resolved locale. Callers
/// pass Model `language_preference` + `system_locale_id`; this file
/// does not read process env. Distinct from
/// EnvironmentChrome.dismiss_all_settled / BackgroundChrome Dismiss* /
/// TranscriptTurnChrome / HeaderSessionChrome so queue chrome stays
/// independently evolvable. Wire ids / on-press stay English
/// (`jump_latest` / `clear_queue` / `remove_queued:{id}` /
/// `edit_queued:{id}`). Queued message body text stays data.
pub fn queueChromeFor(preference: LanguagePreference, system_locale_id: []const u8) QueueChrome {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => queue_chrome_zh_cn,
        .japanese => queue_chrome_ja,
        .system, .english => queue_chrome_en,
    };
}

/// Browser address-field a11y label and placeholder for the resolved
/// locale. Callers pass Model `language_preference` +
/// `system_locale_id`; this file does not read process env. Wire ids /
/// on-input / on-submit stay English. Latin `https://example.com` in
/// every locale. Typed URL text stays data. Parked `home_url` /
/// scene URLs stay data.
pub fn browserAddressChromeFor(preference: LanguagePreference, system_locale_id: []const u8) BrowserAddressChrome {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => browser_address_chrome_zh_cn,
        .japanese => browser_address_chrome_ja,
        .system, .english => browser_address_chrome_en,
    };
}

/// Browser toolbar Back / Forward / Reload / Hard Reload / Navigate
/// and Secure / Not secure a11y for the resolved locale. Callers pass
/// Model `language_preference` + `system_locale_id`; this file does
/// not read process env. Wire ids / on-press stay English. Typed URL
/// text stays data. Parked `home_url` / scene URLs stay data.
pub fn browserToolbarChromeFor(preference: LanguagePreference, system_locale_id: []const u8) BrowserToolbarChrome {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => browser_toolbar_chrome_zh_cn,
        .japanese => browser_toolbar_chrome_ja,
        .system, .english => browser_toolbar_chrome_en,
    };
}

/// Browser start-page globe icon a11y for the resolved locale. Callers
/// pass Model `language_preference` + `system_locale_id`; this file
/// does not read process env. Distinct from RightPanelChrome.browse_the_web
/// / BrowserToolbarChrome / BrowserAddressChrome so start-page icon
/// a11y stays independently evolvable. No wire-id / on-press changes.
pub fn browserStartIconChromeFor(preference: LanguagePreference, system_locale_id: []const u8) BrowserStartIconChrome {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => browser_start_icon_chrome_zh_cn,
        .japanese => browser_start_icon_chrome_ja,
        .system, .english => browser_start_icon_chrome_en,
    };
}

/// Sidebar titlebar session-history Back / Forward a11y for the
/// resolved locale. Callers pass Model `language_preference` +
/// `system_locale_id`; this file does not read process env. Wire
/// ids / on-press stay English. Distinct from Browser toolbar
/// `browser_back` / `browser_forward`.
pub fn sidebarHistoryChromeFor(preference: LanguagePreference, system_locale_id: []const u8) SidebarHistoryChrome {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => sidebar_history_chrome_zh_cn,
        .japanese => sidebar_history_chrome_ja,
        .system, .english => sidebar_history_chrome_en,
    };
}

/// Browser / Terminal multi-session New / Close chips for the
/// resolved locale. Callers pass Model `language_preference` +
/// `system_locale_id`; this file does not read process env. Wire
/// ids / on-press stay English. Browser and Terminal share these
/// strings. Distinct from Files preview Close
/// (`close_right_panel_file_preview`).
pub fn sessionChipsChromeFor(preference: LanguagePreference, system_locale_id: []const u8) SessionChipsChrome {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => session_chips_chrome_zh_cn,
        .japanese => session_chips_chrome_ja,
        .system, .english => session_chips_chrome_en,
    };
}

/// Terminal tab Restart after the pty exit for the resolved locale.
/// Callers pass Model `language_preference` + `system_locale_id`;
/// this file does not read process env. Wire ids / on-press stay
/// English (`restart_terminal`). Distinct from Browser toolbar Reload
/// (`browser_reload`).
pub fn terminalRestartChromeFor(preference: LanguagePreference, system_locale_id: []const u8) TerminalRestartChrome {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => terminal_restart_chrome_zh_cn,
        .japanese => terminal_restart_chrome_ja,
        .system, .english => terminal_restart_chrome_en,
    };
}

/// Settings Computer Use page body chrome for the resolved locale.
/// Callers pass Model `language_preference` + `system_locale_id`;
/// this file does not read process env. Title wording matches
/// `chromeFor` Computer Use but stays a dedicated field. Wire ids /
/// selected stay English. No Enable on-press / persist.
pub fn computerUseChromeFor(preference: LanguagePreference, system_locale_id: []const u8) ComputerUseChrome {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => computer_use_chrome_zh_cn,
        .japanese => computer_use_chrome_ja,
        .system, .english => computer_use_chrome_en,
    };
}

/// Settings Usage Daily / Monthly / Projects view chips, Daily /
/// Projects window chips, Cost|Tokens metric chips, and Daily-only
/// Model|Days breakdown chips for the resolved locale. Callers pass
/// Model `language_preference` + `system_locale_id`; this file does
/// not read process env. Projects stays a dedicated field. Days stays
/// distinct from Daily. `7d` / `30d` / `90d` stay Latin in every
/// locale. Wire ids / on-press / selected stay English. Settings
/// Refresh lives in `settingsRefreshChromeFor`.
pub fn usageViewChromeFor(preference: LanguagePreference, system_locale_id: []const u8) UsageViewChrome {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => usage_view_chrome_zh_cn,
        .japanese => usage_view_chrome_ja,
        .system, .english => usage_view_chrome_en,
    };
}

/// Settings Providers / Skills / Usage Refresh for the resolved locale.
/// Callers pass Model `language_preference` + `system_locale_id`;
/// this file does not read process env. One Refresh field is shared
/// by all three Settings pages. Wire ids / on-press stay English.
/// Distinct from Refresh goal / plan Refresh
/// (`goalPlanRefreshChromeFor`) and from Browser toolbar Reload.
pub fn settingsRefreshChromeFor(preference: LanguagePreference, system_locale_id: []const u8) SettingsRefreshChrome {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => settings_refresh_chrome_zh_cn,
        .japanese => settings_refresh_chrome_ja,
        .system, .english => settings_refresh_chrome_en,
    };
}

/// Composer Refresh goal and plan-meter Refresh for the resolved
/// locale. Callers pass Model `language_preference` + `system_locale_id`;
/// this file does not read process env. Distinct from Settings Refresh
/// so the plan-meter short verb and Refresh goal stay independently
/// evolvable. Wire ids / on-press stay English.
pub fn goalPlanRefreshChromeFor(preference: LanguagePreference, system_locale_id: []const u8) GoalPlanRefreshChrome {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => goal_plan_refresh_chrome_zh_cn,
        .japanese => goal_plan_refresh_chrome_ja,
        .system, .english => goal_plan_refresh_chrome_en,
    };
}

/// Composer Set goal and Clear goal for the resolved locale.
/// Callers pass Model `language_preference` + `system_locale_id`;
/// this file does not read process env. Distinct from Refresh goal /
/// plan Refresh so the set/clear verbs stay independently evolvable.
/// Wire ids / on-press stay English.
pub fn goalActionChromeFor(preference: LanguagePreference, system_locale_id: []const u8) GoalActionChrome {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => goal_action_chrome_zh_cn,
        .japanese => goal_action_chrome_ja,
        .system, .english => goal_action_chrome_en,
    };
}

/// Composer Goal empty label (`No goal`) for the resolved locale.
/// Callers pass Model `language_preference` + `system_locale_id`;
/// this file does not read process env. Distinct from Set/Clear /
/// Refresh goal / Goal Status placeholder / Goal Status display
/// so the empty label stays independently evolvable. Objective
/// text stays data. Wire ids stay English.
pub fn goalEmptyChromeFor(preference: LanguagePreference, system_locale_id: []const u8) GoalEmptyChrome {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => goal_empty_chrome_zh_cn,
        .japanese => goal_empty_chrome_ja,
        .system, .english => goal_empty_chrome_en,
    };
}

/// Composer Goal Status picker-row and selected-chip display labels
/// for the resolved locale. Callers pass Model `language_preference`
/// + `system_locale_id`; this file does not read process env.
/// Distinct from ComposerChrome Status placeholder / GoalActionChrome
/// / GoalEmptyChrome / GoalPlanRefreshChrome / BackgroundChrome
/// settled_completed so Goal Status stays independently evolvable.
/// Wire ids / on-press `pick_goal_status` / stored session status
/// stay English.
pub fn goalStatusChromeFor(preference: LanguagePreference, system_locale_id: []const u8) GoalStatusChrome {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => goal_status_chrome_zh_cn,
        .japanese => goal_status_chrome_ja,
        .system, .english => goal_status_chrome_en,
    };
}

/// Settings Usage Cost quality / LiteLLM Rates status / five-tile
/// metric-strip labels for the resolved locale. Callers pass Model
/// `language_preference` + `system_locale_id`; this file does not
/// read process env. Distinct from UsageViewChrome so Cost|Tokens
/// chips stay independently evolvable. Daemon `errors[]` notice
/// text stays English data this cut. Wire / status enums stay
/// English.
pub fn usageCostQualityChromeFor(preference: LanguagePreference, system_locale_id: []const u8) UsageCostQualityChrome {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => usage_cost_quality_chrome_zh_cn,
        .japanese => usage_cost_quality_chrome_ja,
        .system, .english => usage_cost_quality_chrome_en,
    };
}

/// Settings Usage Daily scan-footer unit labels for the resolved
/// locale. Callers pass Model `language_preference` +
/// `system_locale_id`; this file does not read process env. Distinct
/// from UsageCostQualityChrome so the footer units stay independently
/// evolvable. ` · ` separators and Latin `{d:.1}s` stay. Daemon
/// `errors[]` notice text stays English data this cut.
pub fn usageScanFooterChromeFor(preference: LanguagePreference, system_locale_id: []const u8) UsageScanFooterChrome {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => usage_scan_footer_chrome_zh_cn,
        .japanese => usage_scan_footer_chrome_ja,
        .system, .english => usage_scan_footer_chrome_en,
    };
}

/// Settings Usage sessions unit and connect-daemon hint for the
/// resolved locale. Callers pass Model `language_preference` +
/// `system_locale_id`; this file does not read process env. Distinct
/// from UsageScanFooterChrome so the sessions unit stays independently
/// evolvable. Numbers and ` · ` stay. Daemon `errors[]` notice text
/// stays English data this cut.
pub fn usageSessionsChromeFor(preference: LanguagePreference, system_locale_id: []const u8) UsageSessionsChrome {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => usage_sessions_chrome_zh_cn,
        .japanese => usage_sessions_chrome_ja,
        .system, .english => usage_sessions_chrome_en,
    };
}

/// Composer Usage meter plan-usage chrome for the resolved locale.
/// Callers pass Model `language_preference` + `system_locale_id`;
/// this file does not read process env. Distinct from
/// UsageSessionsChrome so the Settings Usage history connect hint
/// stays independently evolvable. Numbers, Latin `m`/`h`/`d`, and
/// ` · ` stay. Daemon plan window labels / planLabel stay English
/// data this cut.
pub fn usageMeterChromeFor(preference: LanguagePreference, system_locale_id: []const u8) UsageMeterChrome {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => usage_meter_chrome_zh_cn,
        .japanese => usage_meter_chrome_ja,
        .system, .english => usage_meter_chrome_en,
    };
}

/// Settings Usage local session cards and composer Usage meter
/// panel Context window heading for the resolved locale.
/// Callers pass Model `language_preference` + `system_locale_id`;
/// this file does not read process env. Distinct from
/// `Chrome.usage` / UsageMeterChrome / UsageSessionsChrome /
/// UsageViewChrome / FilterChrome so local session chrome stays
/// independently evolvable. Wire ids / numeric usage values stay
/// English/data.
pub fn usageLocalChromeFor(preference: LanguagePreference, system_locale_id: []const u8) UsageLocalChrome {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => usage_local_chrome_zh_cn,
        .japanese => usage_local_chrome_ja,
        .system, .english => usage_local_chrome_en,
    };
}

/// Settings Providers status / Enable·Disable / Apply / Copy
/// install|login / First-party for the resolved locale. Callers pass
/// Model `language_preference` + `system_locale_id`; this file does
/// not read process env. Distinct from ComputerUseChrome so Enable /
/// Off stay independently evolvable. Provider wire names, binary
/// paths, install/login commands, and on-press stay English. Longer
/// detail notes and `Binary:` / `Path:` prefixes live in
/// `providersDetailChromeFor`.
pub fn providersChromeFor(preference: LanguagePreference, system_locale_id: []const u8) ProvidersChrome {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => providers_chrome_zh_cn,
        .japanese => providers_chrome_ja,
        .system, .english => providers_chrome_en,
    };
}

/// Settings Providers muted detail transport notes, fx login
/// notes, other-CLI PATH hint, and `Binary:` / `Path:` prefixes for
/// the resolved locale. Callers pass Model `language_preference` +
/// `system_locale_id`; this file does not read process env. Distinct
/// from ProvidersChrome so status / Enable / Apply stay independently
/// evolvable. CLI flags, wire names, binary paths, and install/login
/// commands stay English.
pub fn providersDetailChromeFor(preference: LanguagePreference, system_locale_id: []const u8) ProvidersDetailChrome {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => providers_detail_chrome_zh_cn,
        .japanese => providers_detail_chrome_ja,
        .system, .english => providers_detail_chrome_en,
    };
}

/// Settings Skills empty-state Open a project / No skills found for
/// the resolved locale. Callers pass Model `language_preference` +
/// `system_locale_id`; this file does not read process env. Distinct
/// from FilterChrome / RightPanelChrome so Skills empty stays
/// independently evolvable. Composer `$` insert empty reuses the
/// same strings. Wire ids stay English.
pub fn skillsEmptyChromeFor(preference: LanguagePreference, system_locale_id: []const u8) SkillsEmptyChrome {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => skills_empty_chrome_zh_cn,
        .japanese => skills_empty_chrome_ja,
        .system, .english => skills_empty_chrome_en,
    };
}

test "LanguagePreference persist names and unknown load as System" {
    const testing = std.testing;
    try testing.expectEqual(LanguagePreference.system, LanguagePreference.fromPersist(""));
    try testing.expectEqual(LanguagePreference.system, LanguagePreference.fromPersist("nope"));
    try testing.expectEqual(LanguagePreference.system, LanguagePreference.fromPersist("system"));
    try testing.expectEqual(LanguagePreference.english, LanguagePreference.fromPersist("english"));
    try testing.expectEqual(LanguagePreference.simplified_chinese, LanguagePreference.fromPersist("simplified-chinese"));
    try testing.expectEqual(LanguagePreference.japanese, LanguagePreference.fromPersist("japanese"));
    try testing.expectEqualStrings("system", LanguagePreference.system.persistName());
    try testing.expectEqualStrings("english", LanguagePreference.english.persistName());
    try testing.expectEqualStrings("simplified-chinese", LanguagePreference.simplified_chinese.persistName());
    try testing.expectEqualStrings("japanese", LanguagePreference.japanese.persistName());
}

test "fromLocaleId maps ja and zh-Hans; C empty and zh-Hant stay english" {
    const testing = std.testing;
    try testing.expectEqual(LanguagePreference.japanese, fromLocaleId("ja"));
    try testing.expectEqual(LanguagePreference.japanese, fromLocaleId("ja_JP"));
    try testing.expectEqual(LanguagePreference.japanese, fromLocaleId("ja-JP"));
    try testing.expectEqual(LanguagePreference.japanese, fromLocaleId("ja_JP.UTF-8"));
    try testing.expectEqual(LanguagePreference.simplified_chinese, fromLocaleId("zh-CN"));
    try testing.expectEqual(LanguagePreference.simplified_chinese, fromLocaleId("zh_SG"));
    try testing.expectEqual(LanguagePreference.simplified_chinese, fromLocaleId("zh-Hans-CN"));
    try testing.expectEqual(LanguagePreference.english, fromLocaleId("zh-Hant-TW"));
    try testing.expectEqual(LanguagePreference.english, fromLocaleId("en"));
    try testing.expectEqual(LanguagePreference.english, fromLocaleId("C"));
    try testing.expectEqual(LanguagePreference.english, fromLocaleId(""));
    try testing.expectEqual(LanguagePreference.english, fromLocaleId("en_US.UTF-8"));
}

test "resolve english ignores a japanese locale id" {
    const testing = std.testing;
    try testing.expectEqual(LanguagePreference.english, resolve(.english, "ja_JP.UTF-8"));
    try testing.expectEqual(LanguagePreference.japanese, resolve(.system, "ja"));
    try testing.expectEqualStrings("LC_ALL", pickSystemLocaleId("LC_ALL", "LC_MESSAGES", "LANG"));
    try testing.expectEqualStrings("LC_MESSAGES", pickSystemLocaleId("", "LC_MESSAGES", "LANG"));
    try testing.expectEqualStrings("LANG", pickSystemLocaleId("", "", "LANG"));
    try testing.expectEqualStrings("en", pickSystemLocaleId("", "", ""));
    try testing.expectEqualStrings("Appearance", chromeFor(.english, "ja").appearance);
    try testing.expectEqualStrings("外观", chromeFor(.simplified_chinese, "").appearance);
    try testing.expectEqualStrings("外観", chromeFor(.japanese, "").appearance);
    try testing.expectEqualStrings("Language", chromeFor(.english, "").language);
    try testing.expectEqualStrings("语言", chromeFor(.simplified_chinese, "").language);
    try testing.expectEqualStrings("言語", chromeFor(.japanese, "").language);
    try testing.expectEqualStrings("Theme", chromeFor(.english, "").theme);
    try testing.expectEqualStrings("主题", chromeFor(.simplified_chinese, "").theme);
    try testing.expectEqualStrings("テーマ", chromeFor(.japanese, "").theme);
    try testing.expectEqualStrings("Appearance", chromeFor(.system, "").appearance);
    try testing.expectEqualStrings("外観", chromeFor(.system, "ja_JP.UTF-8").appearance);
}

test "datesFor english default; zh and ja bucket titles; System follows locale id" {
    const testing = std.testing;
    try testing.expectEqualStrings("Today", datesFor(.english, "ja").today);
    try testing.expectEqualStrings("Yesterday", datesFor(.english, "").yesterday);
    try testing.expectEqualStrings("This week", datesFor(.english, "").this_week);
    try testing.expectEqualStrings("This month", datesFor(.english, "").this_month);
    try testing.expectEqualStrings("This year", datesFor(.english, "").this_year);
    try testing.expectEqualStrings("Older", datesFor(.english, "").older);
    try testing.expectEqualStrings("just now", datesFor(.english, "").just_now);
    try testing.expectEqualStrings("Today", datesFor(.system, "").today);

    try testing.expectEqualStrings("今日", datesFor(.simplified_chinese, "").today);
    try testing.expectEqualStrings("昨天", datesFor(.simplified_chinese, "").yesterday);
    try testing.expectEqualStrings("本周", datesFor(.simplified_chinese, "").this_week);
    try testing.expectEqualStrings("本月", datesFor(.simplified_chinese, "").this_month);
    try testing.expectEqualStrings("今年", datesFor(.simplified_chinese, "").this_year);
    try testing.expectEqualStrings("更早", datesFor(.simplified_chinese, "").older);
    try testing.expectEqualStrings("刚刚", datesFor(.simplified_chinese, "").just_now);

    try testing.expectEqualStrings("今日", datesFor(.japanese, "").today);
    try testing.expectEqualStrings("昨日", datesFor(.japanese, "").yesterday);
    try testing.expectEqualStrings("今週", datesFor(.japanese, "").this_week);
    try testing.expectEqualStrings("今月", datesFor(.japanese, "").this_month);
    try testing.expectEqualStrings("今年", datesFor(.japanese, "").this_year);
    try testing.expectEqualStrings("以前", datesFor(.japanese, "").older);
    try testing.expectEqualStrings("たった今", datesFor(.japanese, "").just_now);

    try testing.expectEqualStrings("今日", datesFor(.system, "zh_CN.UTF-8").today);
    try testing.expectEqualStrings("昨日", datesFor(.system, "ja_JP.UTF-8").yesterday);
    try testing.expectEqualStrings("Today", datesFor(.english, "ja_JP.UTF-8").today);
}

test "sidebarFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("New Task", sidebarFor(.english, "ja").new_task);
    try testing.expectEqualStrings("Search", sidebarFor(.english, "").search);
    try testing.expectEqualStrings("New folder", sidebarFor(.english, "").new_folder);
    try testing.expectEqualStrings("Collapse all folders", sidebarFor(.english, "").collapse_all_folders);
    try testing.expectEqualStrings("Expand folder", sidebarFor(.english, "").expand_folder);
    try testing.expectEqualStrings("Collapse folder", sidebarFor(.english, "").collapse_folder);
    try testing.expectEqualStrings("Delete folder", sidebarFor(.english, "").delete_folder);
    try testing.expectEqualStrings("Rename", sidebarFor(.english, "").rename);
    try testing.expectEqualStrings("Delete", sidebarFor(.english, "").delete);
    try testing.expectEqualStrings("Remove", sidebarFor(.english, "").remove);
    try testing.expectEqualStrings("Remove session", sidebarFor(.english, "").remove_session);
    try testing.expectEqualStrings("New Task", sidebarFor(.system, "").new_task);

    try testing.expectEqualStrings("新建任务", sidebarFor(.simplified_chinese, "").new_task);
    try testing.expectEqualStrings("搜索", sidebarFor(.simplified_chinese, "").search);
    try testing.expectEqualStrings("新建文件夹", sidebarFor(.simplified_chinese, "").new_folder);
    try testing.expectEqualStrings("折叠所有文件夹", sidebarFor(.simplified_chinese, "").collapse_all_folders);
    try testing.expectEqualStrings("展开文件夹", sidebarFor(.simplified_chinese, "").expand_folder);
    try testing.expectEqualStrings("折叠文件夹", sidebarFor(.simplified_chinese, "").collapse_folder);
    try testing.expectEqualStrings("删除文件夹", sidebarFor(.simplified_chinese, "").delete_folder);
    try testing.expectEqualStrings("重命名", sidebarFor(.simplified_chinese, "").rename);
    try testing.expectEqualStrings("删除", sidebarFor(.simplified_chinese, "").delete);
    try testing.expectEqualStrings("移除", sidebarFor(.simplified_chinese, "").remove);
    try testing.expectEqualStrings("移除会话", sidebarFor(.simplified_chinese, "").remove_session);

    try testing.expectEqualStrings("新しいタスク", sidebarFor(.japanese, "").new_task);
    try testing.expectEqualStrings("検索", sidebarFor(.japanese, "").search);
    try testing.expectEqualStrings("新しいフォルダ", sidebarFor(.japanese, "").new_folder);
    try testing.expectEqualStrings("すべてのフォルダを折りたたむ", sidebarFor(.japanese, "").collapse_all_folders);
    try testing.expectEqualStrings("フォルダを展開", sidebarFor(.japanese, "").expand_folder);
    try testing.expectEqualStrings("フォルダを折りたたむ", sidebarFor(.japanese, "").collapse_folder);
    try testing.expectEqualStrings("フォルダを削除", sidebarFor(.japanese, "").delete_folder);
    try testing.expectEqualStrings("名前を変更", sidebarFor(.japanese, "").rename);
    try testing.expectEqualStrings("削除", sidebarFor(.japanese, "").delete);
    try testing.expectEqualStrings("取り除く", sidebarFor(.japanese, "").remove);
    try testing.expectEqualStrings("セッションを取り除く", sidebarFor(.japanese, "").remove_session);

    try testing.expectEqualStrings("新建任务", sidebarFor(.system, "zh_CN.UTF-8").new_task);
    try testing.expectEqualStrings("検索", sidebarFor(.system, "ja_JP.UTF-8").search);
    try testing.expectEqualStrings("New Task", sidebarFor(.english, "ja_JP.UTF-8").new_task);
    try testing.expectEqualStrings("Search", sidebarFor(.english, "ja_JP.UTF-8").search);
    try testing.expectEqualStrings("New folder", sidebarFor(.english, "zh_CN.UTF-8").new_folder);
    try testing.expectEqualStrings("Rename", sidebarFor(.english, "ja_JP.UTF-8").rename);
    try testing.expectEqualStrings("Delete", sidebarFor(.english, "zh_CN.UTF-8").delete);
    try testing.expectEqualStrings("Remove", sidebarFor(.english, "zh_CN.UTF-8").remove);
    try testing.expectEqualStrings("Remove session", sidebarFor(.english, "ja_JP.UTF-8").remove_session);
    try testing.expectEqualStrings("Expand folder", sidebarFor(.english, "zh_CN.UTF-8").expand_folder);
    try testing.expectEqualStrings("Collapse folder", sidebarFor(.english, "ja_JP.UTF-8").collapse_folder);
}

test "accessFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("Ask", accessFor(.english, "ja").ask);
    try testing.expectEqualStrings("Auto", accessFor(.english, "").auto);
    try testing.expectEqualStrings("Full access", accessFor(.english, "").full_access);
    try testing.expectEqualStrings("Ask", accessFor(.system, "").ask);
    try testing.expectEqualStrings("Ask", accessFor(.english, "").labelForId("ask"));
    try testing.expectEqualStrings("Auto", accessFor(.english, "").labelForId("auto"));
    try testing.expectEqualStrings("Full access", accessFor(.english, "").labelForId("fullAccess"));
    try testing.expectEqualStrings("Full access", accessFor(.english, "").labelForId("yolo"));

    try testing.expectEqualStrings("询问", accessFor(.simplified_chinese, "").ask);
    try testing.expectEqualStrings("自动", accessFor(.simplified_chinese, "").auto);
    try testing.expectEqualStrings("完全访问", accessFor(.simplified_chinese, "").full_access);
    try testing.expectEqualStrings("询问", accessFor(.simplified_chinese, "").labelForId("ask"));
    try testing.expectEqualStrings("自动", accessFor(.simplified_chinese, "").labelForId("auto"));
    try testing.expectEqualStrings("完全访问", accessFor(.simplified_chinese, "").labelForId("fullAccess"));

    try testing.expectEqualStrings("確認", accessFor(.japanese, "").ask);
    try testing.expectEqualStrings("自動", accessFor(.japanese, "").auto);
    try testing.expectEqualStrings("フルアクセス", accessFor(.japanese, "").full_access);

    try testing.expectEqualStrings("询问", accessFor(.system, "zh_CN.UTF-8").ask);
    try testing.expectEqualStrings("自動", accessFor(.system, "ja_JP.UTF-8").auto);
    try testing.expectEqualStrings("Ask", accessFor(.english, "ja_JP.UTF-8").ask);
    try testing.expectEqualStrings("Auto", accessFor(.english, "zh_CN.UTF-8").auto);
    try testing.expectEqualStrings("Full access", accessFor(.english, "ja_JP.UTF-8").full_access);
}

test "effortFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("Auto", effortFor(.english, "ja").auto);
    try testing.expectEqualStrings("None", effortFor(.english, "").none);
    try testing.expectEqualStrings("Minimal", effortFor(.english, "").minimal);
    try testing.expectEqualStrings("Low", effortFor(.english, "").low);
    try testing.expectEqualStrings("Medium", effortFor(.english, "").medium);
    try testing.expectEqualStrings("High", effortFor(.english, "").high);
    try testing.expectEqualStrings("Extra high", effortFor(.english, "").extra_high);
    try testing.expectEqualStrings("Max", effortFor(.english, "").max);
    try testing.expectEqualStrings("Auto", effortFor(.system, "").auto);
    try testing.expectEqualStrings("Auto", effortFor(.english, "").labelForId("auto"));
    try testing.expectEqualStrings("None", effortFor(.english, "").labelForId("none"));
    try testing.expectEqualStrings("Minimal", effortFor(.english, "").labelForId("minimal"));
    try testing.expectEqualStrings("Low", effortFor(.english, "").labelForId("low"));
    try testing.expectEqualStrings("Medium", effortFor(.english, "").labelForId("medium"));
    try testing.expectEqualStrings("High", effortFor(.english, "").labelForId("high"));
    try testing.expectEqualStrings("Extra high", effortFor(.english, "").labelForId("xhigh"));
    try testing.expectEqualStrings("Max", effortFor(.english, "").labelForId("max"));
    try testing.expectEqualStrings("Auto", effortFor(.english, "").labelForId(""));
    try testing.expectEqualStrings("Auto", effortFor(.english, "").labelForId("nope"));

    try testing.expectEqualStrings("自动", effortFor(.simplified_chinese, "").auto);
    try testing.expectEqualStrings("无", effortFor(.simplified_chinese, "").none);
    try testing.expectEqualStrings("最低", effortFor(.simplified_chinese, "").minimal);
    try testing.expectEqualStrings("低", effortFor(.simplified_chinese, "").low);
    try testing.expectEqualStrings("中", effortFor(.simplified_chinese, "").medium);
    try testing.expectEqualStrings("高", effortFor(.simplified_chinese, "").high);
    try testing.expectEqualStrings("极高", effortFor(.simplified_chinese, "").extra_high);
    try testing.expectEqualStrings("最大", effortFor(.simplified_chinese, "").max);
    try testing.expectEqualStrings("自动", effortFor(.simplified_chinese, "").labelForId("auto"));
    try testing.expectEqualStrings("无", effortFor(.simplified_chinese, "").labelForId("none"));
    try testing.expectEqualStrings("极高", effortFor(.simplified_chinese, "").labelForId("xhigh"));
    try testing.expectEqualStrings("最大", effortFor(.simplified_chinese, "").labelForId("max"));

    try testing.expectEqualStrings("自動", effortFor(.japanese, "").auto);
    try testing.expectEqualStrings("なし", effortFor(.japanese, "").none);
    try testing.expectEqualStrings("最小", effortFor(.japanese, "").minimal);
    try testing.expectEqualStrings("低", effortFor(.japanese, "").low);
    try testing.expectEqualStrings("中", effortFor(.japanese, "").medium);
    try testing.expectEqualStrings("高", effortFor(.japanese, "").high);
    try testing.expectEqualStrings("非常に高い", effortFor(.japanese, "").extra_high);
    try testing.expectEqualStrings("最大", effortFor(.japanese, "").max);
    try testing.expectEqualStrings("自動", effortFor(.japanese, "").labelForId("auto"));
    try testing.expectEqualStrings("非常に高い", effortFor(.japanese, "").labelForId("xhigh"));

    try testing.expectEqualStrings("自动", effortFor(.system, "zh_CN.UTF-8").auto);
    try testing.expectEqualStrings("なし", effortFor(.system, "ja_JP.UTF-8").none);
    try testing.expectEqualStrings("Auto", effortFor(.english, "ja_JP.UTF-8").auto);
    try testing.expectEqualStrings("None", effortFor(.english, "zh_CN.UTF-8").none);
    try testing.expectEqualStrings("Extra high", effortFor(.english, "ja_JP.UTF-8").extra_high);
    try testing.expectEqualStrings("Max", effortFor(.english, "zh_CN.UTF-8").max);
}

test "interactionFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("Build", interactionFor(.english, "ja").build);
    try testing.expectEqualStrings("Plan", interactionFor(.english, "").plan);
    try testing.expectEqualStrings("Build", interactionFor(.system, "").build);
    try testing.expectEqualStrings("Build", interactionFor(.english, "").labelForId("build"));
    try testing.expectEqualStrings("Plan", interactionFor(.english, "").labelForId("plan"));
    try testing.expectEqualStrings("Build", interactionFor(.english, "").labelForId(""));
    try testing.expectEqualStrings("Build", interactionFor(.english, "").labelForId("nope"));

    try testing.expectEqualStrings("构建", interactionFor(.simplified_chinese, "").build);
    try testing.expectEqualStrings("计划", interactionFor(.simplified_chinese, "").plan);
    try testing.expectEqualStrings("构建", interactionFor(.simplified_chinese, "").labelForId("build"));
    try testing.expectEqualStrings("计划", interactionFor(.simplified_chinese, "").labelForId("plan"));
    try testing.expectEqualStrings("构建", interactionFor(.simplified_chinese, "").labelForId(""));
    try testing.expectEqualStrings("构建", interactionFor(.simplified_chinese, "").labelForId("nope"));

    try testing.expectEqualStrings("ビルド", interactionFor(.japanese, "").build);
    try testing.expectEqualStrings("プラン", interactionFor(.japanese, "").plan);
    try testing.expectEqualStrings("ビルド", interactionFor(.japanese, "").labelForId("build"));
    try testing.expectEqualStrings("プラン", interactionFor(.japanese, "").labelForId("plan"));

    try testing.expectEqualStrings("构建", interactionFor(.system, "zh_CN.UTF-8").build);
    try testing.expectEqualStrings("プラン", interactionFor(.system, "ja_JP.UTF-8").plan);
    try testing.expectEqualStrings("Build", interactionFor(.english, "ja_JP.UTF-8").build);
    try testing.expectEqualStrings("Plan", interactionFor(.english, "zh_CN.UTF-8").plan);
}

test "paletteFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("Focus composer", paletteFor(.english, "ja").focus_composer);
    try testing.expectEqualStrings("Toggle sidebar", paletteFor(.english, "").toggle_sidebar);
    try testing.expectEqualStrings("Find in transcript", paletteFor(.english, "").find_in_transcript);
    try testing.expectEqualStrings("Minimize", paletteFor(.english, "").minimize);
    try testing.expectEqualStrings("Maximize", paletteFor(.english, "").maximize);
    try testing.expectEqualStrings("Copy session id", paletteFor(.english, "").copy_session_id);
    try testing.expectEqualStrings("Copy provider session id", paletteFor(.english, "").copy_provider_session_id);
    try testing.expectEqualStrings("Reveal project folder", paletteFor(.english, "").reveal_project_folder);
    try testing.expectEqualStrings("Open project in Terminal", paletteFor(.english, "").open_project_in_terminal);
    try testing.expectEqualStrings("Open project in Editor", paletteFor(.english, "").open_project_in_editor);
    try testing.expectEqualStrings("Copy project path", paletteFor(.english, "").copy_project_path);
    try testing.expectEqualStrings("Show right panel", paletteFor(.english, "").show_right_panel);
    try testing.expectEqualStrings("Hide right panel", paletteFor(.english, "").hide_right_panel);
    try testing.expectEqualStrings("Show Browser tab", paletteFor(.english, "").show_browser_tab);
    try testing.expectEqualStrings("Show Terminal tab", paletteFor(.english, "").show_terminal_tab);
    try testing.expectEqualStrings("Expand sidebar", paletteFor(.english, "").expand_sidebar);
    try testing.expectEqualStrings("Collapse sidebar", paletteFor(.english, "").collapse_sidebar);
    try testing.expectEqualStrings("Focus composer", paletteFor(.system, "").focus_composer);

    try testing.expectEqualStrings("聚焦输入框", paletteFor(.simplified_chinese, "").focus_composer);
    try testing.expectEqualStrings("切换侧边栏", paletteFor(.simplified_chinese, "").toggle_sidebar);
    try testing.expectEqualStrings("在记录中查找", paletteFor(.simplified_chinese, "").find_in_transcript);
    try testing.expectEqualStrings("最小化", paletteFor(.simplified_chinese, "").minimize);
    try testing.expectEqualStrings("最大化", paletteFor(.simplified_chinese, "").maximize);
    try testing.expectEqualStrings("复制会话 ID", paletteFor(.simplified_chinese, "").copy_session_id);
    try testing.expectEqualStrings("复制提供商会话 ID", paletteFor(.simplified_chinese, "").copy_provider_session_id);
    try testing.expectEqualStrings("显示项目文件夹", paletteFor(.simplified_chinese, "").reveal_project_folder);
    try testing.expectEqualStrings("在终端中打开项目", paletteFor(.simplified_chinese, "").open_project_in_terminal);
    try testing.expectEqualStrings("在编辑器中打开项目", paletteFor(.simplified_chinese, "").open_project_in_editor);
    try testing.expectEqualStrings("复制项目路径", paletteFor(.simplified_chinese, "").copy_project_path);
    try testing.expectEqualStrings("显示右侧面板", paletteFor(.simplified_chinese, "").show_right_panel);
    try testing.expectEqualStrings("隐藏右侧面板", paletteFor(.simplified_chinese, "").hide_right_panel);
    try testing.expectEqualStrings("显示浏览器标签页", paletteFor(.simplified_chinese, "").show_browser_tab);
    try testing.expectEqualStrings("显示终端标签页", paletteFor(.simplified_chinese, "").show_terminal_tab);
    try testing.expectEqualStrings("展开侧边栏", paletteFor(.simplified_chinese, "").expand_sidebar);
    try testing.expectEqualStrings("折叠侧边栏", paletteFor(.simplified_chinese, "").collapse_sidebar);

    try testing.expectEqualStrings("入力欄にフォーカス", paletteFor(.japanese, "").focus_composer);
    try testing.expectEqualStrings("サイドバーを切り替え", paletteFor(.japanese, "").toggle_sidebar);
    try testing.expectEqualStrings("記録内を検索", paletteFor(.japanese, "").find_in_transcript);
    try testing.expectEqualStrings("最小化", paletteFor(.japanese, "").minimize);
    try testing.expectEqualStrings("最大化", paletteFor(.japanese, "").maximize);
    try testing.expectEqualStrings("セッション ID をコピー", paletteFor(.japanese, "").copy_session_id);
    try testing.expectEqualStrings("プロバイダーセッション ID をコピー", paletteFor(.japanese, "").copy_provider_session_id);
    try testing.expectEqualStrings("プロジェクトフォルダを表示", paletteFor(.japanese, "").reveal_project_folder);
    try testing.expectEqualStrings("ターミナルでプロジェクトを開く", paletteFor(.japanese, "").open_project_in_terminal);
    try testing.expectEqualStrings("エディターでプロジェクトを開く", paletteFor(.japanese, "").open_project_in_editor);
    try testing.expectEqualStrings("プロジェクトパスをコピー", paletteFor(.japanese, "").copy_project_path);
    try testing.expectEqualStrings("右パネルを表示", paletteFor(.japanese, "").show_right_panel);
    try testing.expectEqualStrings("右パネルを非表示", paletteFor(.japanese, "").hide_right_panel);
    try testing.expectEqualStrings("ブラウザーのタブを表示", paletteFor(.japanese, "").show_browser_tab);
    try testing.expectEqualStrings("ターミナルのタブを表示", paletteFor(.japanese, "").show_terminal_tab);
    try testing.expectEqualStrings("サイドバーを展開", paletteFor(.japanese, "").expand_sidebar);
    try testing.expectEqualStrings("サイドバーを折りたたむ", paletteFor(.japanese, "").collapse_sidebar);

    try testing.expectEqualStrings("聚焦输入框", paletteFor(.system, "zh_CN.UTF-8").focus_composer);
    try testing.expectEqualStrings("サイドバーを切り替え", paletteFor(.system, "ja_JP.UTF-8").toggle_sidebar);
    try testing.expectEqualStrings("Focus composer", paletteFor(.english, "ja_JP.UTF-8").focus_composer);
    try testing.expectEqualStrings("Toggle sidebar", paletteFor(.english, "zh_CN.UTF-8").toggle_sidebar);
    try testing.expectEqualStrings("Show right panel", paletteFor(.english, "ja_JP.UTF-8").show_right_panel);
    try testing.expectEqualStrings("Hide right panel", paletteFor(.english, "zh_CN.UTF-8").hide_right_panel);
    try testing.expectEqualStrings("Expand sidebar", paletteFor(.english, "ja_JP.UTF-8").expand_sidebar);
    try testing.expectEqualStrings("Collapse sidebar", paletteFor(.english, "zh_CN.UTF-8").collapse_sidebar);
}

test "paletteChromeFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("Suggested", paletteChromeFor(.english, "ja").suggested);
    try testing.expectEqualStrings("Commands", paletteChromeFor(.english, "").commands);
    try testing.expectEqualStrings("Tasks", paletteChromeFor(.english, "").tasks);
    try testing.expectEqualStrings("No matching tasks or commands", paletteChromeFor(.english, "").no_matches);
    try testing.expectEqualStrings("Try a task title, project, provider, model, or command", paletteChromeFor(.english, "").try_query);
    try testing.expectEqualStrings("Confirm", paletteChromeFor(.english, "").confirm);
    try testing.expectEqualStrings("Command palette", paletteChromeFor(.english, "").dialog_title);
    try testing.expectEqualStrings("Suggested", paletteChromeFor(.system, "").suggested);
    try testing.expectEqualStrings("Confirm", paletteChromeFor(.system, "").confirm);
    try testing.expectEqualStrings("Command palette", paletteChromeFor(.system, "").dialog_title);
    try testing.expectEqualStrings(commitChromeFor(.english, "").cancel, "Cancel");

    try testing.expectEqualStrings("建议", paletteChromeFor(.simplified_chinese, "").suggested);
    try testing.expectEqualStrings("命令", paletteChromeFor(.simplified_chinese, "").commands);
    try testing.expectEqualStrings("任务", paletteChromeFor(.simplified_chinese, "").tasks);
    try testing.expectEqualStrings("没有匹配的任务或命令", paletteChromeFor(.simplified_chinese, "").no_matches);
    try testing.expectEqualStrings("试试任务标题、项目、提供商、模型或命令", paletteChromeFor(.simplified_chinese, "").try_query);
    try testing.expectEqualStrings("确认", paletteChromeFor(.simplified_chinese, "").confirm);
    try testing.expectEqualStrings("命令面板", paletteChromeFor(.simplified_chinese, "").dialog_title);
    try testing.expectEqualStrings("取消", commitChromeFor(.simplified_chinese, "").cancel);

    try testing.expectEqualStrings("おすすめ", paletteChromeFor(.japanese, "").suggested);
    try testing.expectEqualStrings("コマンド", paletteChromeFor(.japanese, "").commands);
    try testing.expectEqualStrings("タスク", paletteChromeFor(.japanese, "").tasks);
    try testing.expectEqualStrings("一致するタスクやコマンドはありません", paletteChromeFor(.japanese, "").no_matches);
    try testing.expectEqualStrings("タスク名、プロジェクト、プロバイダー、モデル、コマンドを試す", paletteChromeFor(.japanese, "").try_query);
    try testing.expectEqualStrings("確認", paletteChromeFor(.japanese, "").confirm);
    try testing.expectEqualStrings("コマンドパレット", paletteChromeFor(.japanese, "").dialog_title);
    try testing.expectEqualStrings("キャンセル", commitChromeFor(.japanese, "").cancel);

    try testing.expectEqualStrings("建议", paletteChromeFor(.system, "zh_CN.UTF-8").suggested);
    try testing.expectEqualStrings("确认", paletteChromeFor(.system, "zh_CN.UTF-8").confirm);
    try testing.expectEqualStrings("命令面板", paletteChromeFor(.system, "zh_CN.UTF-8").dialog_title);
    try testing.expectEqualStrings("コマンド", paletteChromeFor(.system, "ja_JP.UTF-8").commands);
    try testing.expectEqualStrings("確認", paletteChromeFor(.system, "ja_JP.UTF-8").confirm);
    try testing.expectEqualStrings("コマンドパレット", paletteChromeFor(.system, "ja_JP.UTF-8").dialog_title);
    try testing.expectEqualStrings("Suggested", paletteChromeFor(.english, "ja_JP.UTF-8").suggested);
    try testing.expectEqualStrings("Commands", paletteChromeFor(.english, "zh_CN.UTF-8").commands);
    try testing.expectEqualStrings("Tasks", paletteChromeFor(.english, "ja_JP.UTF-8").tasks);
    try testing.expectEqualStrings("No matching tasks or commands", paletteChromeFor(.english, "zh_CN.UTF-8").no_matches);
    try testing.expectEqualStrings("Try a task title, project, provider, model, or command", paletteChromeFor(.english, "ja_JP.UTF-8").try_query);
    try testing.expectEqualStrings("Confirm", paletteChromeFor(.english, "ja_JP.UTF-8").confirm);
    try testing.expectEqualStrings("Confirm", paletteChromeFor(.english, "zh_CN.UTF-8").confirm);
    try testing.expectEqualStrings("Command palette", paletteChromeFor(.english, "ja_JP.UTF-8").dialog_title);
    try testing.expectEqualStrings("Command palette", paletteChromeFor(.english, "zh_CN.UTF-8").dialog_title);
}

test "rightPanelTabsFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("Files", rightPanelTabsFor(.english, "ja").files);
    try testing.expectEqualStrings("Review", rightPanelTabsFor(.english, "").diff);
    try testing.expectEqualStrings("Browser", rightPanelTabsFor(.english, "").browser);
    try testing.expectEqualStrings("Terminal", rightPanelTabsFor(.english, "").terminal);
    try testing.expectEqualStrings("Background", rightPanelTabsFor(.english, "").background);
    try testing.expectEqualStrings("Files", rightPanelTabsFor(.system, "").files);

    try testing.expectEqualStrings("文件", rightPanelTabsFor(.simplified_chinese, "").files);
    try testing.expectEqualStrings("审阅", rightPanelTabsFor(.simplified_chinese, "").diff);
    try testing.expectEqualStrings("浏览器", rightPanelTabsFor(.simplified_chinese, "").browser);
    try testing.expectEqualStrings("终端", rightPanelTabsFor(.simplified_chinese, "").terminal);
    try testing.expectEqualStrings("后台工作", rightPanelTabsFor(.simplified_chinese, "").background);

    try testing.expectEqualStrings("ファイル", rightPanelTabsFor(.japanese, "").files);
    try testing.expectEqualStrings("レビュー", rightPanelTabsFor(.japanese, "").diff);
    try testing.expectEqualStrings("ブラウザ", rightPanelTabsFor(.japanese, "").browser);
    try testing.expectEqualStrings("ターミナル", rightPanelTabsFor(.japanese, "").terminal);
    try testing.expectEqualStrings("バックグラウンド", rightPanelTabsFor(.japanese, "").background);

    try testing.expectEqualStrings("文件", rightPanelTabsFor(.system, "zh_CN.UTF-8").files);
    try testing.expectEqualStrings("レビュー", rightPanelTabsFor(.system, "ja_JP.UTF-8").diff);
    try testing.expectEqualStrings("Files", rightPanelTabsFor(.english, "ja_JP.UTF-8").files);
    try testing.expectEqualStrings("Review", rightPanelTabsFor(.english, "zh_CN.UTF-8").diff);
    try testing.expectEqualStrings("Browser", rightPanelTabsFor(.english, "ja_JP.UTF-8").browser);
    try testing.expectEqualStrings("Terminal", rightPanelTabsFor(.english, "zh_CN.UTF-8").terminal);
    try testing.expectEqualStrings("Background", rightPanelTabsFor(.english, "ja_JP.UTF-8").background);
}

test "rightPanelChromeFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("Filter files", rightPanelChromeFor(.english, "ja").filter_files);
    try testing.expectEqualStrings("No project open", rightPanelChromeFor(.english, "").no_project_open);
    try testing.expectEqualStrings("Open a project to browse its files", rightPanelChromeFor(.english, "").open_project_to_browse_files);
    try testing.expectEqualStrings("Loading files…", rightPanelChromeFor(.english, "").loading_files);
    try testing.expectEqualStrings("No background work", rightPanelChromeFor(.english, "").no_background_work);
    try testing.expectEqualStrings("No output", rightPanelChromeFor(.english, "").no_output);
    try testing.expectEqualStrings("Browse the web", rightPanelChromeFor(.english, "").browse_the_web);
    try testing.expectEqualStrings("Cmd/Ctrl-L focuses the address.", rightPanelChromeFor(.english, "").address_focus_hint);
    try testing.expectEqualStrings("Open in browser", rightPanelChromeFor(.english, "").open_in_browser);
    try testing.expectEqualStrings("Open in Terminal", rightPanelChromeFor(.english, "").open_in_terminal);
    try testing.expectEqualStrings("Filter files", rightPanelChromeFor(.system, "").filter_files);

    try testing.expectEqualStrings("筛选文件", rightPanelChromeFor(.simplified_chinese, "").filter_files);
    try testing.expectEqualStrings("未打开项目", rightPanelChromeFor(.simplified_chinese, "").no_project_open);
    try testing.expectEqualStrings("打开项目以浏览文件", rightPanelChromeFor(.simplified_chinese, "").open_project_to_browse_files);
    try testing.expectEqualStrings("正在加载文件…", rightPanelChromeFor(.simplified_chinese, "").loading_files);
    try testing.expectEqualStrings("没有后台工作", rightPanelChromeFor(.simplified_chinese, "").no_background_work);
    try testing.expectEqualStrings("没有输出", rightPanelChromeFor(.simplified_chinese, "").no_output);
    try testing.expectEqualStrings("浏览网页", rightPanelChromeFor(.simplified_chinese, "").browse_the_web);
    try testing.expectEqualStrings("Cmd/Ctrl-L 聚焦地址栏。", rightPanelChromeFor(.simplified_chinese, "").address_focus_hint);
    try testing.expectEqualStrings("在浏览器中打开", rightPanelChromeFor(.simplified_chinese, "").open_in_browser);
    try testing.expectEqualStrings("在终端中打开", rightPanelChromeFor(.simplified_chinese, "").open_in_terminal);

    try testing.expectEqualStrings("ファイルを絞り込む", rightPanelChromeFor(.japanese, "").filter_files);
    try testing.expectEqualStrings("プロジェクトが開かれていません", rightPanelChromeFor(.japanese, "").no_project_open);
    try testing.expectEqualStrings("プロジェクトを開いてファイルを閲覧", rightPanelChromeFor(.japanese, "").open_project_to_browse_files);
    try testing.expectEqualStrings("ファイルを読み込み中…", rightPanelChromeFor(.japanese, "").loading_files);
    try testing.expectEqualStrings("バックグラウンド作業はありません", rightPanelChromeFor(.japanese, "").no_background_work);
    try testing.expectEqualStrings("出力がありません", rightPanelChromeFor(.japanese, "").no_output);
    try testing.expectEqualStrings("ウェブを閲覧", rightPanelChromeFor(.japanese, "").browse_the_web);
    try testing.expectEqualStrings("Cmd/Ctrl-L でアドレス欄にフォーカス。", rightPanelChromeFor(.japanese, "").address_focus_hint);
    try testing.expectEqualStrings("ブラウザで開く", rightPanelChromeFor(.japanese, "").open_in_browser);
    try testing.expectEqualStrings("ターミナルで開く", rightPanelChromeFor(.japanese, "").open_in_terminal);

    try testing.expectEqualStrings("筛选文件", rightPanelChromeFor(.system, "zh_CN.UTF-8").filter_files);
    try testing.expectEqualStrings("打开项目以浏览文件", rightPanelChromeFor(.system, "zh_CN.UTF-8").open_project_to_browse_files);
    try testing.expectEqualStrings("正在加载文件…", rightPanelChromeFor(.system, "zh_CN.UTF-8").loading_files);
    try testing.expectEqualStrings("出力がありません", rightPanelChromeFor(.system, "ja_JP.UTF-8").no_output);
    try testing.expectEqualStrings("プロジェクトを開いてファイルを閲覧", rightPanelChromeFor(.system, "ja_JP.UTF-8").open_project_to_browse_files);
    try testing.expectEqualStrings("ファイルを読み込み中…", rightPanelChromeFor(.system, "ja_JP.UTF-8").loading_files);
    try testing.expectEqualStrings("浏览网页", rightPanelChromeFor(.system, "zh_CN.UTF-8").browse_the_web);
    try testing.expectEqualStrings("ターミナルで開く", rightPanelChromeFor(.system, "ja_JP.UTF-8").open_in_terminal);
    try testing.expectEqualStrings("Filter files", rightPanelChromeFor(.english, "ja_JP.UTF-8").filter_files);
    try testing.expectEqualStrings("No project open", rightPanelChromeFor(.english, "zh_CN.UTF-8").no_project_open);
    try testing.expectEqualStrings("Open a project to browse its files", rightPanelChromeFor(.english, "ja_JP.UTF-8").open_project_to_browse_files);
    try testing.expectEqualStrings("Loading files…", rightPanelChromeFor(.english, "zh_CN.UTF-8").loading_files);
    try testing.expectEqualStrings("No background work", rightPanelChromeFor(.english, "ja_JP.UTF-8").no_background_work);
    try testing.expectEqualStrings("No output", rightPanelChromeFor(.english, "zh_CN.UTF-8").no_output);
    try testing.expectEqualStrings("Browse the web", rightPanelChromeFor(.english, "ja_JP.UTF-8").browse_the_web);
    try testing.expectEqualStrings("Cmd/Ctrl-L focuses the address.", rightPanelChromeFor(.english, "zh_CN.UTF-8").address_focus_hint);
    try testing.expectEqualStrings("Open in browser", rightPanelChromeFor(.english, "ja_JP.UTF-8").open_in_browser);
    try testing.expectEqualStrings("Open in Terminal", rightPanelChromeFor(.english, "zh_CN.UTF-8").open_in_terminal);
}

test "composerProjectChromeFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("Pick folder", composerProjectChromeFor(.english, "ja").pick_folder);
    try testing.expectEqualStrings("Reveal folder", composerProjectChromeFor(.english, "").reveal_folder);
    try testing.expectEqualStrings("Open in Editor", composerProjectChromeFor(.english, "").open_in_editor);
    try testing.expectEqualStrings("Copy path", composerProjectChromeFor(.english, "").copy_path);
    try testing.expectEqualStrings("Pick folder", composerProjectChromeFor(.system, "").pick_folder);

    try testing.expectEqualStrings("选择文件夹", composerProjectChromeFor(.simplified_chinese, "").pick_folder);
    try testing.expectEqualStrings("显示文件夹", composerProjectChromeFor(.simplified_chinese, "").reveal_folder);
    try testing.expectEqualStrings("在编辑器中打开", composerProjectChromeFor(.simplified_chinese, "").open_in_editor);
    try testing.expectEqualStrings("复制路径", composerProjectChromeFor(.simplified_chinese, "").copy_path);

    try testing.expectEqualStrings("フォルダを選択", composerProjectChromeFor(.japanese, "").pick_folder);
    try testing.expectEqualStrings("フォルダを表示", composerProjectChromeFor(.japanese, "").reveal_folder);
    try testing.expectEqualStrings("エディターで開く", composerProjectChromeFor(.japanese, "").open_in_editor);
    try testing.expectEqualStrings("パスをコピー", composerProjectChromeFor(.japanese, "").copy_path);

    try testing.expectEqualStrings("选择文件夹", composerProjectChromeFor(.system, "zh_CN.UTF-8").pick_folder);
    try testing.expectEqualStrings("パスをコピー", composerProjectChromeFor(.system, "ja_JP.UTF-8").copy_path);
    try testing.expectEqualStrings("Pick folder", composerProjectChromeFor(.english, "ja_JP.UTF-8").pick_folder);
    try testing.expectEqualStrings("Reveal folder", composerProjectChromeFor(.english, "zh_CN.UTF-8").reveal_folder);
    try testing.expectEqualStrings("Open in Editor", composerProjectChromeFor(.english, "ja_JP.UTF-8").open_in_editor);
    try testing.expectEqualStrings("Copy path", composerProjectChromeFor(.english, "zh_CN.UTF-8").copy_path);

    try testing.expect(!std.mem.eql(u8, composerProjectChromeFor(.english, "").open_in_editor, paletteFor(.english, "").open_project_in_editor));
    try testing.expect(!std.mem.eql(u8, composerProjectChromeFor(.english, "").reveal_folder, paletteFor(.english, "").reveal_project_folder));
    try testing.expect(!std.mem.eql(u8, composerProjectChromeFor(.english, "").copy_path, paletteFor(.english, "").copy_project_path));
    try testing.expect(!std.mem.eql(u8, composerProjectChromeFor(.simplified_chinese, "").open_in_editor, paletteFor(.simplified_chinese, "").open_project_in_editor));
    try testing.expect(!std.mem.eql(u8, composerProjectChromeFor(.simplified_chinese, "").reveal_folder, paletteFor(.simplified_chinese, "").reveal_project_folder));
    try testing.expect(!std.mem.eql(u8, composerProjectChromeFor(.simplified_chinese, "").copy_path, paletteFor(.simplified_chinese, "").copy_project_path));
    try testing.expect(!std.mem.eql(u8, composerProjectChromeFor(.japanese, "").open_in_editor, paletteFor(.japanese, "").open_project_in_editor));
    try testing.expect(!std.mem.eql(u8, composerProjectChromeFor(.japanese, "").reveal_folder, paletteFor(.japanese, "").reveal_project_folder));
    try testing.expect(!std.mem.eql(u8, composerProjectChromeFor(.japanese, "").copy_path, paletteFor(.japanese, "").copy_project_path));
}

test "reviewDiffChromeFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("Review", reviewDiffChromeFor(.english, "ja").review_title);
    try testing.expectEqualStrings("Cancel", reviewDiffChromeFor(.english, "").cancel);
    try testing.expectEqualStrings("Branch", reviewDiffChromeFor(.english, "").branch);
    try testing.expectEqualStrings("Uncommitted", reviewDiffChromeFor(.english, "").uncommitted);
    try testing.expectEqualStrings("Staged", reviewDiffChromeFor(.english, "").staged);
    try testing.expectEqualStrings("Unstaged", reviewDiffChromeFor(.english, "").unstaged);
    try testing.expectEqualStrings("Committed", reviewDiffChromeFor(.english, "").committed);
    try testing.expectEqualStrings("Last turn", reviewDiffChromeFor(.english, "").last_turn);
    try testing.expectEqualStrings("Start", reviewDiffChromeFor(.english, "").gap_expand_start);
    try testing.expectEqualStrings("End", reviewDiffChromeFor(.english, "").gap_expand_end);
    try testing.expectEqualStrings("Both", reviewDiffChromeFor(.english, "").gap_expand_both);
    try testing.expectEqualStrings("All", reviewDiffChromeFor(.english, "").gap_expand_all);
    try testing.expectEqualStrings("Review", reviewDiffChromeFor(.system, "").review_title);
    try testing.expectEqualStrings(rightPanelTabsFor(.english, "").diff, reviewDiffChromeFor(.english, "").review_title);

    try testing.expectEqualStrings("审阅", reviewDiffChromeFor(.simplified_chinese, "").review_title);
    try testing.expectEqualStrings("取消", reviewDiffChromeFor(.simplified_chinese, "").cancel);
    try testing.expectEqualStrings("分支", reviewDiffChromeFor(.simplified_chinese, "").branch);
    try testing.expectEqualStrings("未提交", reviewDiffChromeFor(.simplified_chinese, "").uncommitted);
    try testing.expectEqualStrings("已暂存", reviewDiffChromeFor(.simplified_chinese, "").staged);
    try testing.expectEqualStrings("未暂存", reviewDiffChromeFor(.simplified_chinese, "").unstaged);
    try testing.expectEqualStrings("已提交", reviewDiffChromeFor(.simplified_chinese, "").committed);
    try testing.expectEqualStrings("上一轮", reviewDiffChromeFor(.simplified_chinese, "").last_turn);
    try testing.expectEqualStrings("开头", reviewDiffChromeFor(.simplified_chinese, "").gap_expand_start);
    try testing.expectEqualStrings("末尾", reviewDiffChromeFor(.simplified_chinese, "").gap_expand_end);
    try testing.expectEqualStrings("两端", reviewDiffChromeFor(.simplified_chinese, "").gap_expand_both);
    try testing.expectEqualStrings("全部", reviewDiffChromeFor(.simplified_chinese, "").gap_expand_all);
    try testing.expectEqualStrings(rightPanelTabsFor(.simplified_chinese, "").diff, reviewDiffChromeFor(.simplified_chinese, "").review_title);

    try testing.expectEqualStrings("レビュー", reviewDiffChromeFor(.japanese, "").review_title);
    try testing.expectEqualStrings("キャンセル", reviewDiffChromeFor(.japanese, "").cancel);
    try testing.expectEqualStrings("ブランチ", reviewDiffChromeFor(.japanese, "").branch);
    try testing.expectEqualStrings("未コミット", reviewDiffChromeFor(.japanese, "").uncommitted);
    try testing.expectEqualStrings("ステージ済み", reviewDiffChromeFor(.japanese, "").staged);
    try testing.expectEqualStrings("未ステージ", reviewDiffChromeFor(.japanese, "").unstaged);
    try testing.expectEqualStrings("コミット済み", reviewDiffChromeFor(.japanese, "").committed);
    try testing.expectEqualStrings("直前のターン", reviewDiffChromeFor(.japanese, "").last_turn);
    try testing.expectEqualStrings("先頭", reviewDiffChromeFor(.japanese, "").gap_expand_start);
    try testing.expectEqualStrings("末尾", reviewDiffChromeFor(.japanese, "").gap_expand_end);
    try testing.expectEqualStrings("両端", reviewDiffChromeFor(.japanese, "").gap_expand_both);
    try testing.expectEqualStrings("すべて", reviewDiffChromeFor(.japanese, "").gap_expand_all);
    try testing.expectEqualStrings(rightPanelTabsFor(.japanese, "").diff, reviewDiffChromeFor(.japanese, "").review_title);

    try testing.expectEqualStrings("审阅", reviewDiffChromeFor(.system, "zh_CN.UTF-8").review_title);
    try testing.expectEqualStrings("取消", reviewDiffChromeFor(.system, "zh_CN.UTF-8").cancel);
    try testing.expectEqualStrings("上一轮", reviewDiffChromeFor(.system, "zh_CN.UTF-8").last_turn);
    try testing.expectEqualStrings("开头", reviewDiffChromeFor(.system, "zh_CN.UTF-8").gap_expand_start);
    try testing.expectEqualStrings("末尾", reviewDiffChromeFor(.system, "zh_CN.UTF-8").gap_expand_end);
    try testing.expectEqualStrings("两端", reviewDiffChromeFor(.system, "zh_CN.UTF-8").gap_expand_both);
    try testing.expectEqualStrings("全部", reviewDiffChromeFor(.system, "zh_CN.UTF-8").gap_expand_all);
    try testing.expectEqualStrings("レビュー", reviewDiffChromeFor(.system, "ja_JP.UTF-8").review_title);
    try testing.expectEqualStrings("キャンセル", reviewDiffChromeFor(.system, "ja_JP.UTF-8").cancel);
    try testing.expectEqualStrings("直前のターン", reviewDiffChromeFor(.system, "ja_JP.UTF-8").last_turn);
    try testing.expectEqualStrings("先頭", reviewDiffChromeFor(.system, "ja_JP.UTF-8").gap_expand_start);
    try testing.expectEqualStrings("末尾", reviewDiffChromeFor(.system, "ja_JP.UTF-8").gap_expand_end);
    try testing.expectEqualStrings("両端", reviewDiffChromeFor(.system, "ja_JP.UTF-8").gap_expand_both);
    try testing.expectEqualStrings("すべて", reviewDiffChromeFor(.system, "ja_JP.UTF-8").gap_expand_all);
    try testing.expectEqualStrings("Review", reviewDiffChromeFor(.english, "ja_JP.UTF-8").review_title);
    try testing.expectEqualStrings("Cancel", reviewDiffChromeFor(.english, "zh_CN.UTF-8").cancel);
    try testing.expectEqualStrings("Branch", reviewDiffChromeFor(.english, "ja_JP.UTF-8").branch);
    try testing.expectEqualStrings("Uncommitted", reviewDiffChromeFor(.english, "zh_CN.UTF-8").uncommitted);
    try testing.expectEqualStrings("Staged", reviewDiffChromeFor(.english, "ja_JP.UTF-8").staged);
    try testing.expectEqualStrings("Unstaged", reviewDiffChromeFor(.english, "zh_CN.UTF-8").unstaged);
    try testing.expectEqualStrings("Committed", reviewDiffChromeFor(.english, "ja_JP.UTF-8").committed);
    try testing.expectEqualStrings("Last turn", reviewDiffChromeFor(.english, "zh_CN.UTF-8").last_turn);
    try testing.expectEqualStrings("Start", reviewDiffChromeFor(.english, "ja_JP.UTF-8").gap_expand_start);
    try testing.expectEqualStrings("End", reviewDiffChromeFor(.english, "zh_CN.UTF-8").gap_expand_end);
    try testing.expectEqualStrings("Both", reviewDiffChromeFor(.english, "ja_JP.UTF-8").gap_expand_both);
    try testing.expectEqualStrings("All", reviewDiffChromeFor(.english, "zh_CN.UTF-8").gap_expand_all);
}

test "backgroundChromeFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("Process", backgroundChromeFor(.english, "ja").kind_process);
    try testing.expectEqualStrings("Monitor", backgroundChromeFor(.english, "").kind_monitor);
    try testing.expectEqualStrings("Subagent", backgroundChromeFor(.english, "").kind_subagent);
    try testing.expectEqualStrings("Agent turn", backgroundChromeFor(.english, "").process_row);
    try testing.expectEqualStrings("Completed", backgroundChromeFor(.english, "").settled_completed);
    try testing.expectEqualStrings("Stopped", backgroundChromeFor(.english, "").settled_stopped);
    try testing.expectEqualStrings("Failed", backgroundChromeFor(.english, "").settled_failed);
    try testing.expectEqualStrings("Running", backgroundChromeFor(.english, "").live_running);
    try testing.expectEqualStrings("Monitoring", backgroundChromeFor(.english, "").live_monitoring);
    try testing.expectEqualStrings("Stopping", backgroundChromeFor(.english, "").live_stopping);
    try testing.expectEqualStrings("Stop agent", backgroundChromeFor(.english, "").process_stop);
    try testing.expectEqualStrings("Stop monitor", backgroundChromeFor(.english, "").monitor_stop);
    try testing.expectEqualStrings("Dismiss monitor", backgroundChromeFor(.english, "").monitor_dismiss);
    try testing.expectEqualStrings("Stop subagent", backgroundChromeFor(.english, "").subagent_stop);
    try testing.expectEqualStrings("Dismiss subagent", backgroundChromeFor(.english, "").subagent_dismiss);
    try testing.expectEqualStrings("Stop", backgroundChromeFor(.english, "").daemon_stop);
    try testing.expectEqualStrings("Dismiss", backgroundChromeFor(.english, "").daemon_dismiss);
    try testing.expectEqualStrings("Process", backgroundChromeFor(.system, "").kind_process);

    try testing.expectEqualStrings("进程", backgroundChromeFor(.simplified_chinese, "").kind_process);
    try testing.expectEqualStrings("监视器", backgroundChromeFor(.simplified_chinese, "").kind_monitor);
    try testing.expectEqualStrings("子代理", backgroundChromeFor(.simplified_chinese, "").kind_subagent);
    try testing.expectEqualStrings("代理轮次", backgroundChromeFor(.simplified_chinese, "").process_row);
    try testing.expectEqualStrings("已完成", backgroundChromeFor(.simplified_chinese, "").settled_completed);
    try testing.expectEqualStrings("已停止", backgroundChromeFor(.simplified_chinese, "").settled_stopped);
    try testing.expectEqualStrings("失败", backgroundChromeFor(.simplified_chinese, "").settled_failed);
    try testing.expectEqualStrings("运行中", backgroundChromeFor(.simplified_chinese, "").live_running);
    try testing.expectEqualStrings("监视中", backgroundChromeFor(.simplified_chinese, "").live_monitoring);
    try testing.expectEqualStrings("正在停止", backgroundChromeFor(.simplified_chinese, "").live_stopping);
    try testing.expectEqualStrings("停止代理", backgroundChromeFor(.simplified_chinese, "").process_stop);
    try testing.expectEqualStrings("停止监视器", backgroundChromeFor(.simplified_chinese, "").monitor_stop);
    try testing.expectEqualStrings("关闭监视器", backgroundChromeFor(.simplified_chinese, "").monitor_dismiss);
    try testing.expectEqualStrings("停止子代理", backgroundChromeFor(.simplified_chinese, "").subagent_stop);
    try testing.expectEqualStrings("关闭子代理", backgroundChromeFor(.simplified_chinese, "").subagent_dismiss);
    try testing.expectEqualStrings("停止", backgroundChromeFor(.simplified_chinese, "").daemon_stop);
    try testing.expectEqualStrings("关闭", backgroundChromeFor(.simplified_chinese, "").daemon_dismiss);

    try testing.expectEqualStrings("プロセス", backgroundChromeFor(.japanese, "").kind_process);
    try testing.expectEqualStrings("モニター", backgroundChromeFor(.japanese, "").kind_monitor);
    try testing.expectEqualStrings("サブエージェント", backgroundChromeFor(.japanese, "").kind_subagent);
    try testing.expectEqualStrings("エージェントのターン", backgroundChromeFor(.japanese, "").process_row);
    try testing.expectEqualStrings("完了", backgroundChromeFor(.japanese, "").settled_completed);
    try testing.expectEqualStrings("停止済み", backgroundChromeFor(.japanese, "").settled_stopped);
    try testing.expectEqualStrings("失敗", backgroundChromeFor(.japanese, "").settled_failed);
    try testing.expectEqualStrings("実行中", backgroundChromeFor(.japanese, "").live_running);
    try testing.expectEqualStrings("監視中", backgroundChromeFor(.japanese, "").live_monitoring);
    try testing.expectEqualStrings("停止中", backgroundChromeFor(.japanese, "").live_stopping);
    try testing.expectEqualStrings("エージェントを停止", backgroundChromeFor(.japanese, "").process_stop);
    try testing.expectEqualStrings("モニターを停止", backgroundChromeFor(.japanese, "").monitor_stop);
    try testing.expectEqualStrings("モニターを閉じる", backgroundChromeFor(.japanese, "").monitor_dismiss);
    try testing.expectEqualStrings("サブエージェントを停止", backgroundChromeFor(.japanese, "").subagent_stop);
    try testing.expectEqualStrings("サブエージェントを閉じる", backgroundChromeFor(.japanese, "").subagent_dismiss);
    try testing.expectEqualStrings("停止", backgroundChromeFor(.japanese, "").daemon_stop);
    try testing.expectEqualStrings("閉じる", backgroundChromeFor(.japanese, "").daemon_dismiss);

    try testing.expectEqualStrings("进程", backgroundChromeFor(.system, "zh_CN.UTF-8").kind_process);
    try testing.expectEqualStrings("关闭监视器", backgroundChromeFor(.system, "zh_CN.UTF-8").monitor_dismiss);
    try testing.expectEqualStrings("代理轮次", backgroundChromeFor(.system, "zh_CN.UTF-8").process_row);
    try testing.expectEqualStrings("プロセス", backgroundChromeFor(.system, "ja_JP.UTF-8").kind_process);
    try testing.expectEqualStrings("モニターを閉じる", backgroundChromeFor(.system, "ja_JP.UTF-8").monitor_dismiss);
    try testing.expectEqualStrings("エージェントのターン", backgroundChromeFor(.system, "ja_JP.UTF-8").process_row);
    try testing.expectEqualStrings("Process", backgroundChromeFor(.english, "ja_JP.UTF-8").kind_process);
    try testing.expectEqualStrings("Monitor", backgroundChromeFor(.english, "zh_CN.UTF-8").kind_monitor);
    try testing.expectEqualStrings("Subagent", backgroundChromeFor(.english, "ja_JP.UTF-8").kind_subagent);
    try testing.expectEqualStrings("Agent turn", backgroundChromeFor(.english, "zh_CN.UTF-8").process_row);
    try testing.expectEqualStrings("Completed", backgroundChromeFor(.english, "ja_JP.UTF-8").settled_completed);
    try testing.expectEqualStrings("Stopped", backgroundChromeFor(.english, "zh_CN.UTF-8").settled_stopped);
    try testing.expectEqualStrings("Failed", backgroundChromeFor(.english, "ja_JP.UTF-8").settled_failed);
    try testing.expectEqualStrings("Running", backgroundChromeFor(.english, "zh_CN.UTF-8").live_running);
    try testing.expectEqualStrings("Monitoring", backgroundChromeFor(.english, "ja_JP.UTF-8").live_monitoring);
    try testing.expectEqualStrings("Stopping", backgroundChromeFor(.english, "zh_CN.UTF-8").live_stopping);
    try testing.expectEqualStrings("Stop agent", backgroundChromeFor(.english, "ja_JP.UTF-8").process_stop);
    try testing.expectEqualStrings("Stop monitor", backgroundChromeFor(.english, "zh_CN.UTF-8").monitor_stop);
    try testing.expectEqualStrings("Dismiss monitor", backgroundChromeFor(.english, "ja_JP.UTF-8").monitor_dismiss);
    try testing.expectEqualStrings("Stop subagent", backgroundChromeFor(.english, "zh_CN.UTF-8").subagent_stop);
    try testing.expectEqualStrings("Dismiss subagent", backgroundChromeFor(.english, "ja_JP.UTF-8").subagent_dismiss);
    try testing.expectEqualStrings("Stop", backgroundChromeFor(.english, "zh_CN.UTF-8").daemon_stop);
    try testing.expectEqualStrings("Dismiss", backgroundChromeFor(.english, "ja_JP.UTF-8").daemon_dismiss);

    try testing.expectEqualStrings(rightPanelChromeFor(.english, "").no_background_work, "No background work");
    try testing.expectEqualStrings(rightPanelChromeFor(.english, "").no_output, "No output");
}

test "environmentChromeFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("Environment", environmentChromeFor(.english, "ja").environment);
    try testing.expectEqualStrings("Commit or Push", environmentChromeFor(.english, "").commit_or_push);
    try testing.expectEqualStrings("Compare", environmentChromeFor(.english, "").compare);
    try testing.expectEqualStrings("Copy task ID", environmentChromeFor(.english, "").copy_task_id);
    try testing.expectEqualStrings("Copy agent CLI thread ID", environmentChromeFor(.english, "").copy_agent_thread_id);
    try testing.expectEqualStrings("Dismiss all settled", environmentChromeFor(.english, "").dismiss_all_settled);
    try testing.expectEqualStrings("Background", environmentChromeFor(.english, "").background_section);
    try testing.expectEqualStrings("Environment", environmentChromeFor(.system, "").environment);
    try testing.expectEqualStrings("Background", environmentChromeFor(.system, "").background_section);

    try testing.expectEqualStrings("环境", environmentChromeFor(.simplified_chinese, "").environment);
    try testing.expectEqualStrings("提交或推送", environmentChromeFor(.simplified_chinese, "").commit_or_push);
    try testing.expectEqualStrings("比较", environmentChromeFor(.simplified_chinese, "").compare);
    try testing.expectEqualStrings("复制任务 ID", environmentChromeFor(.simplified_chinese, "").copy_task_id);
    try testing.expectEqualStrings("复制代理 CLI 线程 ID", environmentChromeFor(.simplified_chinese, "").copy_agent_thread_id);
    try testing.expectEqualStrings("关闭全部已结束项", environmentChromeFor(.simplified_chinese, "").dismiss_all_settled);
    try testing.expectEqualStrings("后台工作", environmentChromeFor(.simplified_chinese, "").background_section);

    try testing.expectEqualStrings("環境", environmentChromeFor(.japanese, "").environment);
    try testing.expectEqualStrings("コミットまたはプッシュ", environmentChromeFor(.japanese, "").commit_or_push);
    try testing.expectEqualStrings("比較", environmentChromeFor(.japanese, "").compare);
    try testing.expectEqualStrings("タスク ID をコピー", environmentChromeFor(.japanese, "").copy_task_id);
    try testing.expectEqualStrings("エージェント CLI スレッド ID をコピー", environmentChromeFor(.japanese, "").copy_agent_thread_id);
    try testing.expectEqualStrings("終了した項目をすべて閉じる", environmentChromeFor(.japanese, "").dismiss_all_settled);
    try testing.expectEqualStrings("バックグラウンド", environmentChromeFor(.japanese, "").background_section);

    try testing.expectEqualStrings("环境", environmentChromeFor(.system, "zh_CN.UTF-8").environment);
    try testing.expectEqualStrings("提交或推送", environmentChromeFor(.system, "zh_CN.UTF-8").commit_or_push);
    try testing.expectEqualStrings("关闭全部已结束项", environmentChromeFor(.system, "zh_CN.UTF-8").dismiss_all_settled);
    try testing.expectEqualStrings("后台工作", environmentChromeFor(.system, "zh_CN.UTF-8").background_section);
    try testing.expectEqualStrings("環境", environmentChromeFor(.system, "ja_JP.UTF-8").environment);
    try testing.expectEqualStrings("コミットまたはプッシュ", environmentChromeFor(.system, "ja_JP.UTF-8").commit_or_push);
    try testing.expectEqualStrings("終了した項目をすべて閉じる", environmentChromeFor(.system, "ja_JP.UTF-8").dismiss_all_settled);
    try testing.expectEqualStrings("バックグラウンド", environmentChromeFor(.system, "ja_JP.UTF-8").background_section);
    try testing.expectEqualStrings("Environment", environmentChromeFor(.english, "ja_JP.UTF-8").environment);
    try testing.expectEqualStrings("Commit or Push", environmentChromeFor(.english, "zh_CN.UTF-8").commit_or_push);
    try testing.expectEqualStrings("Compare", environmentChromeFor(.english, "ja_JP.UTF-8").compare);
    try testing.expectEqualStrings("Copy task ID", environmentChromeFor(.english, "zh_CN.UTF-8").copy_task_id);
    try testing.expectEqualStrings("Copy agent CLI thread ID", environmentChromeFor(.english, "ja_JP.UTF-8").copy_agent_thread_id);
    try testing.expectEqualStrings("Dismiss all settled", environmentChromeFor(.english, "zh_CN.UTF-8").dismiss_all_settled);
    try testing.expectEqualStrings("Background", environmentChromeFor(.english, "ja_JP.UTF-8").background_section);
}

test "filterChromeFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("Filter skills", filterChromeFor(.english, "ja").filter_skills);
    try testing.expectEqualStrings("Filter projects", filterChromeFor(.english, "").filter_projects);
    try testing.expectEqualStrings("No project usage", filterChromeFor(.english, "").no_project_usage);
    try testing.expectEqualStrings("No matching projects", filterChromeFor(.english, "").no_matching_projects);
    try testing.expectEqualStrings("Filter skills", filterChromeFor(.system, "").filter_skills);
    try testing.expectEqualStrings("Filter projects", filterChromeFor(.system, "").filter_projects);
    try testing.expectEqualStrings("No project usage", filterChromeFor(.system, "").no_project_usage);
    try testing.expectEqualStrings("No matching projects", filterChromeFor(.system, "").no_matching_projects);

    try testing.expectEqualStrings("筛选技能", filterChromeFor(.simplified_chinese, "").filter_skills);
    try testing.expectEqualStrings("筛选项目", filterChromeFor(.simplified_chinese, "").filter_projects);
    try testing.expectEqualStrings("没有项目用量", filterChromeFor(.simplified_chinese, "").no_project_usage);
    try testing.expectEqualStrings("没有匹配的项目", filterChromeFor(.simplified_chinese, "").no_matching_projects);

    try testing.expectEqualStrings("スキルを絞り込む", filterChromeFor(.japanese, "").filter_skills);
    try testing.expectEqualStrings("プロジェクトを絞り込む", filterChromeFor(.japanese, "").filter_projects);
    try testing.expectEqualStrings("プロジェクトの使用量はありません", filterChromeFor(.japanese, "").no_project_usage);
    try testing.expectEqualStrings("一致するプロジェクトはありません", filterChromeFor(.japanese, "").no_matching_projects);

    try testing.expectEqualStrings("筛选技能", filterChromeFor(.system, "zh_CN.UTF-8").filter_skills);
    try testing.expectEqualStrings("筛选项目", filterChromeFor(.system, "zh_CN.UTF-8").filter_projects);
    try testing.expectEqualStrings("没有项目用量", filterChromeFor(.system, "zh_CN.UTF-8").no_project_usage);
    try testing.expectEqualStrings("没有匹配的项目", filterChromeFor(.system, "zh_CN.UTF-8").no_matching_projects);
    try testing.expectEqualStrings("スキルを絞り込む", filterChromeFor(.system, "ja_JP.UTF-8").filter_skills);
    try testing.expectEqualStrings("プロジェクトを絞り込む", filterChromeFor(.system, "ja_JP.UTF-8").filter_projects);
    try testing.expectEqualStrings("プロジェクトの使用量はありません", filterChromeFor(.system, "ja_JP.UTF-8").no_project_usage);
    try testing.expectEqualStrings("一致するプロジェクトはありません", filterChromeFor(.system, "ja_JP.UTF-8").no_matching_projects);
    try testing.expectEqualStrings("Filter skills", filterChromeFor(.english, "ja_JP.UTF-8").filter_skills);
    try testing.expectEqualStrings("Filter projects", filterChromeFor(.english, "zh_CN.UTF-8").filter_projects);
    try testing.expectEqualStrings("No project usage", filterChromeFor(.english, "ja_JP.UTF-8").no_project_usage);
    try testing.expectEqualStrings("No matching projects", filterChromeFor(.english, "zh_CN.UTF-8").no_matching_projects);
}

test "filePreviewChromeFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("Unsaved", filePreviewChromeFor(.english, "ja").unsaved);
    try testing.expectEqualStrings("Preview", filePreviewChromeFor(.english, "").preview);
    try testing.expectEqualStrings("Source", filePreviewChromeFor(.english, "").source);
    try testing.expectEqualStrings("Edit", filePreviewChromeFor(.english, "").edit);
    try testing.expectEqualStrings("Save", filePreviewChromeFor(.english, "").save);
    try testing.expectEqualStrings("Reload", filePreviewChromeFor(.english, "").reload);
    try testing.expectEqualStrings("Open in editor", filePreviewChromeFor(.english, "").open_in_editor);
    try testing.expectEqualStrings("Close", filePreviewChromeFor(.english, "").close);
    try testing.expectEqualStrings("Hide replace", filePreviewChromeFor(.english, "").hide_replace);
    try testing.expectEqualStrings("Show replace", filePreviewChromeFor(.english, "").show_replace);
    try testing.expectEqualStrings("Find", filePreviewChromeFor(.english, "").find);
    try testing.expectEqualStrings("Find in file", filePreviewChromeFor(.english, "").find_in_file);
    try testing.expectEqualStrings("Previous file match", filePreviewChromeFor(.english, "").previous_file_match);
    try testing.expectEqualStrings("Next file match", filePreviewChromeFor(.english, "").next_file_match);
    try testing.expectEqualStrings("Close file find", filePreviewChromeFor(.english, "").close_file_find);
    try testing.expectEqualStrings("Replace", filePreviewChromeFor(.english, "").replace);
    try testing.expectEqualStrings("Replace in file", filePreviewChromeFor(.english, "").replace_in_file);
    try testing.expectEqualStrings("Replace all", filePreviewChromeFor(.english, "").replace_all);
    try testing.expectEqualStrings("Read-only", filePreviewChromeFor(.english, "").read_only);
    try testing.expectEqualStrings("Discard unsaved changes?", filePreviewChromeFor(.english, "").discard_unsaved);
    try testing.expectEqualStrings("Discard", filePreviewChromeFor(.english, "").discard);
    try testing.expectEqualStrings("Keep editing", filePreviewChromeFor(.english, "").keep_editing);
    try testing.expectEqualStrings("Truncated — showing first 256 KB", filePreviewChromeFor(.english, "").truncated);
    try testing.expectEqualStrings("Binary file — not shown", filePreviewChromeFor(.english, "").binary_file);
    try testing.expectEqualStrings("Unsaved", filePreviewChromeFor(.system, "").unsaved);
    try testing.expectEqualStrings("Find in file", filePreviewChromeFor(.system, "").find_in_file);
    try testing.expect(!std.mem.eql(u8, filePreviewChromeFor(.english, "").open_in_editor, composerProjectChromeFor(.english, "").open_in_editor));

    try testing.expectEqualStrings("未保存", filePreviewChromeFor(.simplified_chinese, "").unsaved);
    try testing.expectEqualStrings("预览", filePreviewChromeFor(.simplified_chinese, "").preview);
    try testing.expectEqualStrings("源码", filePreviewChromeFor(.simplified_chinese, "").source);
    try testing.expectEqualStrings("编辑", filePreviewChromeFor(.simplified_chinese, "").edit);
    try testing.expectEqualStrings("保存", filePreviewChromeFor(.simplified_chinese, "").save);
    try testing.expectEqualStrings("重新加载", filePreviewChromeFor(.simplified_chinese, "").reload);
    try testing.expectEqualStrings("在编辑器中打开", filePreviewChromeFor(.simplified_chinese, "").open_in_editor);
    try testing.expectEqualStrings("关闭", filePreviewChromeFor(.simplified_chinese, "").close);
    try testing.expectEqualStrings("隐藏替换", filePreviewChromeFor(.simplified_chinese, "").hide_replace);
    try testing.expectEqualStrings("显示替换", filePreviewChromeFor(.simplified_chinese, "").show_replace);
    try testing.expectEqualStrings("查找", filePreviewChromeFor(.simplified_chinese, "").find);
    try testing.expectEqualStrings("在文件中查找", filePreviewChromeFor(.simplified_chinese, "").find_in_file);
    try testing.expectEqualStrings("上一个文件匹配", filePreviewChromeFor(.simplified_chinese, "").previous_file_match);
    try testing.expectEqualStrings("下一个文件匹配", filePreviewChromeFor(.simplified_chinese, "").next_file_match);
    try testing.expectEqualStrings("关闭文件查找", filePreviewChromeFor(.simplified_chinese, "").close_file_find);
    try testing.expectEqualStrings("替换", filePreviewChromeFor(.simplified_chinese, "").replace);
    try testing.expectEqualStrings("在文件中替换", filePreviewChromeFor(.simplified_chinese, "").replace_in_file);
    try testing.expectEqualStrings("全部替换", filePreviewChromeFor(.simplified_chinese, "").replace_all);
    try testing.expectEqualStrings("只读", filePreviewChromeFor(.simplified_chinese, "").read_only);
    try testing.expectEqualStrings("放弃未保存的更改？", filePreviewChromeFor(.simplified_chinese, "").discard_unsaved);
    try testing.expectEqualStrings("放弃", filePreviewChromeFor(.simplified_chinese, "").discard);
    try testing.expectEqualStrings("继续编辑", filePreviewChromeFor(.simplified_chinese, "").keep_editing);
    try testing.expectEqualStrings("已截断 — 仅显示前 256 KB", filePreviewChromeFor(.simplified_chinese, "").truncated);
    try testing.expectEqualStrings("二进制文件 — 未显示", filePreviewChromeFor(.simplified_chinese, "").binary_file);

    try testing.expectEqualStrings("未保存", filePreviewChromeFor(.japanese, "").unsaved);
    try testing.expectEqualStrings("プレビュー", filePreviewChromeFor(.japanese, "").preview);
    try testing.expectEqualStrings("ソース", filePreviewChromeFor(.japanese, "").source);
    try testing.expectEqualStrings("編集", filePreviewChromeFor(.japanese, "").edit);
    try testing.expectEqualStrings("保存", filePreviewChromeFor(.japanese, "").save);
    try testing.expectEqualStrings("再読み込み", filePreviewChromeFor(.japanese, "").reload);
    try testing.expectEqualStrings("エディターで開く", filePreviewChromeFor(.japanese, "").open_in_editor);
    try testing.expectEqualStrings("閉じる", filePreviewChromeFor(.japanese, "").close);
    try testing.expectEqualStrings("置換を隠す", filePreviewChromeFor(.japanese, "").hide_replace);
    try testing.expectEqualStrings("置換を表示", filePreviewChromeFor(.japanese, "").show_replace);
    try testing.expectEqualStrings("検索", filePreviewChromeFor(.japanese, "").find);
    try testing.expectEqualStrings("ファイル内を検索", filePreviewChromeFor(.japanese, "").find_in_file);
    try testing.expectEqualStrings("前のファイル一致", filePreviewChromeFor(.japanese, "").previous_file_match);
    try testing.expectEqualStrings("次のファイル一致", filePreviewChromeFor(.japanese, "").next_file_match);
    try testing.expectEqualStrings("ファイル検索を閉じる", filePreviewChromeFor(.japanese, "").close_file_find);
    try testing.expectEqualStrings("置換", filePreviewChromeFor(.japanese, "").replace);
    try testing.expectEqualStrings("ファイル内を置換", filePreviewChromeFor(.japanese, "").replace_in_file);
    try testing.expectEqualStrings("すべて置換", filePreviewChromeFor(.japanese, "").replace_all);
    try testing.expectEqualStrings("読み取り専用", filePreviewChromeFor(.japanese, "").read_only);
    try testing.expectEqualStrings("未保存の変更を破棄しますか？", filePreviewChromeFor(.japanese, "").discard_unsaved);
    try testing.expectEqualStrings("破棄", filePreviewChromeFor(.japanese, "").discard);
    try testing.expectEqualStrings("編集を続ける", filePreviewChromeFor(.japanese, "").keep_editing);
    try testing.expectEqualStrings("切り詰め済み — 先頭 256 KB を表示", filePreviewChromeFor(.japanese, "").truncated);
    try testing.expectEqualStrings("バイナリファイル — 非表示", filePreviewChromeFor(.japanese, "").binary_file);

    try testing.expectEqualStrings("未保存", filePreviewChromeFor(.system, "zh_CN.UTF-8").unsaved);
    try testing.expectEqualStrings("在文件中查找", filePreviewChromeFor(.system, "zh_CN.UTF-8").find_in_file);
    try testing.expectEqualStrings("放弃未保存的更改？", filePreviewChromeFor(.system, "zh_CN.UTF-8").discard_unsaved);
    try testing.expectEqualStrings("未保存", filePreviewChromeFor(.system, "ja_JP.UTF-8").unsaved);
    try testing.expectEqualStrings("ファイル内を検索", filePreviewChromeFor(.system, "ja_JP.UTF-8").find_in_file);
    try testing.expectEqualStrings("未保存の変更を破棄しますか？", filePreviewChromeFor(.system, "ja_JP.UTF-8").discard_unsaved);
    try testing.expectEqualStrings("Unsaved", filePreviewChromeFor(.english, "ja_JP.UTF-8").unsaved);
    try testing.expectEqualStrings("Open in editor", filePreviewChromeFor(.english, "zh_CN.UTF-8").open_in_editor);
    try testing.expectEqualStrings("Find in file", filePreviewChromeFor(.english, "ja_JP.UTF-8").find_in_file);
    try testing.expectEqualStrings("Keep editing", filePreviewChromeFor(.english, "zh_CN.UTF-8").keep_editing);
    try testing.expectEqualStrings("Binary file — not shown", filePreviewChromeFor(.english, "ja_JP.UTF-8").binary_file);
}

test "filePreviewErrorChromeFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("Cannot read file", filePreviewErrorChromeFor(.english, "ja").unreadable);
    try testing.expectEqualStrings("File not found", filePreviewErrorChromeFor(.english, "ja").missing);
    try testing.expectEqualStrings("Cannot save truncated preview — open in editor", filePreviewErrorChromeFor(.english, "ja").truncated_save);
    try testing.expectEqualStrings("Cannot save binary file", filePreviewErrorChromeFor(.english, "ja").binary_save);
    try testing.expectEqualStrings("Cannot save file", filePreviewErrorChromeFor(.english, "ja").cannot_save);
    try testing.expectEqualStrings("Cannot read file", filePreviewErrorChromeFor(.english, "").unreadable);
    try testing.expectEqualStrings("File not found", filePreviewErrorChromeFor(.english, "").missing);
    try testing.expectEqualStrings("Cannot save truncated preview — open in editor", filePreviewErrorChromeFor(.english, "").truncated_save);
    try testing.expectEqualStrings("Cannot save binary file", filePreviewErrorChromeFor(.english, "").binary_save);
    try testing.expectEqualStrings("Cannot save file", filePreviewErrorChromeFor(.english, "").cannot_save);
    try testing.expectEqualStrings("Cannot read file", filePreviewErrorChromeFor(.system, "").unreadable);
    try testing.expectEqualStrings("File not found", filePreviewErrorChromeFor(.system, "").missing);
    try testing.expectEqualStrings("Cannot save truncated preview — open in editor", filePreviewErrorChromeFor(.system, "").truncated_save);
    try testing.expectEqualStrings("Cannot save binary file", filePreviewErrorChromeFor(.system, "").binary_save);
    try testing.expectEqualStrings("Cannot save file", filePreviewErrorChromeFor(.system, "").cannot_save);

    try testing.expectEqualStrings("无法读取文件", filePreviewErrorChromeFor(.simplified_chinese, "").unreadable);
    try testing.expectEqualStrings("找不到文件", filePreviewErrorChromeFor(.simplified_chinese, "").missing);
    try testing.expectEqualStrings("无法保存已截断的预览 — 请在编辑器中打开", filePreviewErrorChromeFor(.simplified_chinese, "").truncated_save);
    try testing.expectEqualStrings("无法保存二进制文件", filePreviewErrorChromeFor(.simplified_chinese, "").binary_save);
    try testing.expectEqualStrings("无法保存文件", filePreviewErrorChromeFor(.simplified_chinese, "").cannot_save);
    try testing.expectEqualStrings("ファイルを読み取れません", filePreviewErrorChromeFor(.japanese, "").unreadable);
    try testing.expectEqualStrings("ファイルが見つかりません", filePreviewErrorChromeFor(.japanese, "").missing);
    try testing.expectEqualStrings("切り詰められたプレビューは保存できません — エディターで開いてください", filePreviewErrorChromeFor(.japanese, "").truncated_save);
    try testing.expectEqualStrings("バイナリファイルは保存できません", filePreviewErrorChromeFor(.japanese, "").binary_save);
    try testing.expectEqualStrings("ファイルを保存できません", filePreviewErrorChromeFor(.japanese, "").cannot_save);

    try testing.expectEqualStrings("无法读取文件", filePreviewErrorChromeFor(.system, "zh_CN.UTF-8").unreadable);
    try testing.expectEqualStrings("找不到文件", filePreviewErrorChromeFor(.system, "zh_CN.UTF-8").missing);
    try testing.expectEqualStrings("无法保存已截断的预览 — 请在编辑器中打开", filePreviewErrorChromeFor(.system, "zh_CN.UTF-8").truncated_save);
    try testing.expectEqualStrings("无法保存二进制文件", filePreviewErrorChromeFor(.system, "zh_CN.UTF-8").binary_save);
    try testing.expectEqualStrings("无法保存文件", filePreviewErrorChromeFor(.system, "zh_CN.UTF-8").cannot_save);
    try testing.expectEqualStrings("ファイルを読み取れません", filePreviewErrorChromeFor(.system, "ja_JP.UTF-8").unreadable);
    try testing.expectEqualStrings("ファイルが見つかりません", filePreviewErrorChromeFor(.system, "ja_JP.UTF-8").missing);
    try testing.expectEqualStrings("切り詰められたプレビューは保存できません — エディターで開いてください", filePreviewErrorChromeFor(.system, "ja_JP.UTF-8").truncated_save);
    try testing.expectEqualStrings("バイナリファイルは保存できません", filePreviewErrorChromeFor(.system, "ja_JP.UTF-8").binary_save);
    try testing.expectEqualStrings("ファイルを保存できません", filePreviewErrorChromeFor(.system, "ja_JP.UTF-8").cannot_save);
    try testing.expectEqualStrings("Cannot read file", filePreviewErrorChromeFor(.english, "ja_JP.UTF-8").unreadable);
    try testing.expectEqualStrings("File not found", filePreviewErrorChromeFor(.english, "zh_CN.UTF-8").missing);
    try testing.expectEqualStrings("Cannot save truncated preview — open in editor", filePreviewErrorChromeFor(.english, "zh_CN.UTF-8").truncated_save);
    try testing.expectEqualStrings("Cannot save binary file", filePreviewErrorChromeFor(.english, "ja_JP.UTF-8").binary_save);
    try testing.expectEqualStrings("Cannot save file", filePreviewErrorChromeFor(.english, "ja_JP.UTF-8").cannot_save);

    try testing.expect(!std.mem.eql(u8, filePreviewErrorChromeFor(.english, "").unreadable, filePreviewErrorChromeFor(.english, "").missing));
    try testing.expect(!std.mem.eql(u8, filePreviewErrorChromeFor(.english, "").truncated_save, filePreviewErrorChromeFor(.english, "").binary_save));
    try testing.expect(!std.mem.eql(u8, filePreviewErrorChromeFor(.english, "").binary_save, filePreviewErrorChromeFor(.english, "").cannot_save));
    try testing.expect(!std.mem.eql(u8, filePreviewErrorChromeFor(.english, "").cannot_save, filePreviewErrorChromeFor(.english, "").unreadable));
    try testing.expect(!std.mem.eql(u8, filePreviewErrorChromeFor(.english, "").truncated_save, filePreviewChromeFor(.english, "").truncated));
    try testing.expect(!std.mem.eql(u8, filePreviewErrorChromeFor(.english, "").binary_save, filePreviewChromeFor(.english, "").binary_file));
    try testing.expect(!std.mem.eql(u8, filePreviewErrorChromeFor(.english, "").cannot_save, filePreviewChromeFor(.english, "").save));
    try testing.expect(!std.mem.eql(u8, filePreviewErrorChromeFor(.english, "").unreadable, filePreviewFindMatchChromeFor(.english, "").invalid));
    try testing.expect(std.mem.indexOf(u8, filePreviewErrorChromeFor(.english, "").truncated_save, "—") != null);
    try testing.expect(!std.mem.eql(u8, filePreviewErrorChromeFor(.simplified_chinese, "").truncated_save, filePreviewChromeFor(.simplified_chinese, "").truncated));
    try testing.expect(!std.mem.eql(u8, filePreviewErrorChromeFor(.japanese, "").truncated_save, filePreviewChromeFor(.japanese, "").truncated));
    try testing.expect(!std.mem.eql(u8, filePreviewErrorChromeFor(.simplified_chinese, "").binary_save, filePreviewChromeFor(.simplified_chinese, "").binary_file));
    try testing.expect(!std.mem.eql(u8, filePreviewErrorChromeFor(.japanese, "").binary_save, filePreviewChromeFor(.japanese, "").binary_file));
    try testing.expect(!std.mem.eql(u8, filePreviewErrorChromeFor(.simplified_chinese, "").unreadable, filePreviewErrorChromeFor(.english, "").unreadable));
    try testing.expect(!std.mem.eql(u8, filePreviewErrorChromeFor(.japanese, "").missing, filePreviewErrorChromeFor(.english, "").missing));
}

test "commitChromeFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("Commit message", commitChromeFor(.english, "ja").commit_message);
    try testing.expectEqualStrings("Include unstaged", commitChromeFor(.english, "").include_unstaged);
    try testing.expectEqualStrings("Amend", commitChromeFor(.english, "").amend);
    try testing.expectEqualStrings("Force", commitChromeFor(.english, "").force);
    try testing.expectEqualStrings("Generating…", commitChromeFor(.english, "").generating);
    try testing.expectEqualStrings("Amending…", commitChromeFor(.english, "").amending);
    try testing.expectEqualStrings("Committing and pushing…", commitChromeFor(.english, "").committing_and_pushing);
    try testing.expectEqualStrings("Committing…", commitChromeFor(.english, "").committing);
    try testing.expectEqualStrings("Pushing…", commitChromeFor(.english, "").pushing);
    try testing.expectEqualStrings("Commit", commitChromeFor(.english, "").commit);
    try testing.expectEqualStrings("Commit and Push", commitChromeFor(.english, "").commit_and_push);
    try testing.expectEqualStrings("Push", commitChromeFor(.english, "").push);
    try testing.expectEqualStrings("Cancel", commitChromeFor(.english, "").cancel);
    try testing.expectEqualStrings("Commit message", commitChromeFor(.system, "").commit_message);
    try testing.expectEqualStrings("Include unstaged", commitChromeFor(.system, "").include_unstaged);
    try testing.expectEqualStrings(reviewDiffChromeFor(.english, "").cancel, commitChromeFor(.english, "").cancel);

    try testing.expectEqualStrings("提交信息", commitChromeFor(.simplified_chinese, "").commit_message);
    try testing.expectEqualStrings("包含未暂存", commitChromeFor(.simplified_chinese, "").include_unstaged);
    try testing.expectEqualStrings("修订", commitChromeFor(.simplified_chinese, "").amend);
    try testing.expectEqualStrings("强制", commitChromeFor(.simplified_chinese, "").force);
    try testing.expectEqualStrings("正在生成…", commitChromeFor(.simplified_chinese, "").generating);
    try testing.expectEqualStrings("正在修订…", commitChromeFor(.simplified_chinese, "").amending);
    try testing.expectEqualStrings("正在提交并推送…", commitChromeFor(.simplified_chinese, "").committing_and_pushing);
    try testing.expectEqualStrings("正在提交…", commitChromeFor(.simplified_chinese, "").committing);
    try testing.expectEqualStrings("正在推送…", commitChromeFor(.simplified_chinese, "").pushing);
    try testing.expectEqualStrings("提交", commitChromeFor(.simplified_chinese, "").commit);
    try testing.expectEqualStrings("提交并推送", commitChromeFor(.simplified_chinese, "").commit_and_push);
    try testing.expectEqualStrings("推送", commitChromeFor(.simplified_chinese, "").push);
    try testing.expectEqualStrings("取消", commitChromeFor(.simplified_chinese, "").cancel);
    try testing.expectEqualStrings(reviewDiffChromeFor(.simplified_chinese, "").cancel, commitChromeFor(.simplified_chinese, "").cancel);

    try testing.expectEqualStrings("コミットメッセージ", commitChromeFor(.japanese, "").commit_message);
    try testing.expectEqualStrings("未ステージを含める", commitChromeFor(.japanese, "").include_unstaged);
    try testing.expectEqualStrings("修正", commitChromeFor(.japanese, "").amend);
    try testing.expectEqualStrings("強制", commitChromeFor(.japanese, "").force);
    try testing.expectEqualStrings("生成中…", commitChromeFor(.japanese, "").generating);
    try testing.expectEqualStrings("修正中…", commitChromeFor(.japanese, "").amending);
    try testing.expectEqualStrings("コミットしてプッシュ中…", commitChromeFor(.japanese, "").committing_and_pushing);
    try testing.expectEqualStrings("コミット中…", commitChromeFor(.japanese, "").committing);
    try testing.expectEqualStrings("プッシュ中…", commitChromeFor(.japanese, "").pushing);
    try testing.expectEqualStrings("コミット", commitChromeFor(.japanese, "").commit);
    try testing.expectEqualStrings("コミットしてプッシュ", commitChromeFor(.japanese, "").commit_and_push);
    try testing.expectEqualStrings("プッシュ", commitChromeFor(.japanese, "").push);
    try testing.expectEqualStrings("キャンセル", commitChromeFor(.japanese, "").cancel);
    try testing.expectEqualStrings(reviewDiffChromeFor(.japanese, "").cancel, commitChromeFor(.japanese, "").cancel);

    try testing.expectEqualStrings("提交信息", commitChromeFor(.system, "zh_CN.UTF-8").commit_message);
    try testing.expectEqualStrings("包含未暂存", commitChromeFor(.system, "zh_CN.UTF-8").include_unstaged);
    try testing.expectEqualStrings("正在提交并推送…", commitChromeFor(.system, "zh_CN.UTF-8").committing_and_pushing);
    try testing.expectEqualStrings("提交并推送", commitChromeFor(.system, "zh_CN.UTF-8").commit_and_push);
    try testing.expectEqualStrings("コミットメッセージ", commitChromeFor(.system, "ja_JP.UTF-8").commit_message);
    try testing.expectEqualStrings("未ステージを含める", commitChromeFor(.system, "ja_JP.UTF-8").include_unstaged);
    try testing.expectEqualStrings("コミットしてプッシュ中…", commitChromeFor(.system, "ja_JP.UTF-8").committing_and_pushing);
    try testing.expectEqualStrings("コミットしてプッシュ", commitChromeFor(.system, "ja_JP.UTF-8").commit_and_push);
    try testing.expectEqualStrings("Commit message", commitChromeFor(.english, "ja_JP.UTF-8").commit_message);
    try testing.expectEqualStrings("Include unstaged", commitChromeFor(.english, "zh_CN.UTF-8").include_unstaged);
    try testing.expectEqualStrings("Amend", commitChromeFor(.english, "ja_JP.UTF-8").amend);
    try testing.expectEqualStrings("Force", commitChromeFor(.english, "zh_CN.UTF-8").force);
    try testing.expectEqualStrings("Generating…", commitChromeFor(.english, "ja_JP.UTF-8").generating);
    try testing.expectEqualStrings("Amending…", commitChromeFor(.english, "zh_CN.UTF-8").amending);
    try testing.expectEqualStrings("Committing and pushing…", commitChromeFor(.english, "ja_JP.UTF-8").committing_and_pushing);
    try testing.expectEqualStrings("Committing…", commitChromeFor(.english, "zh_CN.UTF-8").committing);
    try testing.expectEqualStrings("Pushing…", commitChromeFor(.english, "ja_JP.UTF-8").pushing);
    try testing.expectEqualStrings("Commit", commitChromeFor(.english, "zh_CN.UTF-8").commit);
    try testing.expectEqualStrings("Commit and Push", commitChromeFor(.english, "ja_JP.UTF-8").commit_and_push);
    try testing.expectEqualStrings("Push", commitChromeFor(.english, "zh_CN.UTF-8").push);
    try testing.expectEqualStrings("Cancel", commitChromeFor(.english, "ja_JP.UTF-8").cancel);
}

test "branchChromeFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("Branch", branchChromeFor(.english, "ja").branch_placeholder);
    try testing.expectEqualStrings("Search branches", branchChromeFor(.english, "").search_branches);
    try testing.expectEqualStrings("New branch…", branchChromeFor(.english, "").new_branch_menu);
    try testing.expectEqualStrings("New worktree…", branchChromeFor(.english, "").new_worktree_menu);
    try testing.expectEqualStrings("Delete branch…", branchChromeFor(.english, "").delete_branch_menu);
    try testing.expectEqualStrings("Fetch…", branchChromeFor(.english, "").fetch_menu);
    try testing.expectEqualStrings("Commit…", branchChromeFor(.english, "").commit_menu);
    try testing.expectEqualStrings("Push…", branchChromeFor(.english, "").push_menu);
    try testing.expectEqualStrings("New branch name", branchChromeFor(.english, "").new_branch_name);
    try testing.expectEqualStrings("New worktree name", branchChromeFor(.english, "").new_worktree_name);
    try testing.expectEqualStrings("Base", branchChromeFor(.english, "").base);
    try testing.expectEqualStrings("Create", branchChromeFor(.english, "").create);
    try testing.expectEqualStrings("Delete", branchChromeFor(.english, "").delete);
    try testing.expectEqualStrings("Branch", branchChromeFor(.system, "").branch_placeholder);
    try testing.expectEqualStrings("Search branches", branchChromeFor(.system, "").search_branches);
    try testing.expectEqualStrings(reviewDiffChromeFor(.english, "").branch, branchChromeFor(.english, "").branch_placeholder);
    try testing.expectEqualStrings(sidebarFor(.english, "").delete, branchChromeFor(.english, "").delete);

    try testing.expectEqualStrings("分支", branchChromeFor(.simplified_chinese, "").branch_placeholder);
    try testing.expectEqualStrings("搜索分支", branchChromeFor(.simplified_chinese, "").search_branches);
    try testing.expectEqualStrings("新建分支…", branchChromeFor(.simplified_chinese, "").new_branch_menu);
    try testing.expectEqualStrings("新建 worktree…", branchChromeFor(.simplified_chinese, "").new_worktree_menu);
    try testing.expectEqualStrings("删除分支…", branchChromeFor(.simplified_chinese, "").delete_branch_menu);
    try testing.expectEqualStrings("获取…", branchChromeFor(.simplified_chinese, "").fetch_menu);
    try testing.expectEqualStrings("提交…", branchChromeFor(.simplified_chinese, "").commit_menu);
    try testing.expectEqualStrings("推送…", branchChromeFor(.simplified_chinese, "").push_menu);
    try testing.expectEqualStrings("新分支名称", branchChromeFor(.simplified_chinese, "").new_branch_name);
    try testing.expectEqualStrings("新 worktree 名称", branchChromeFor(.simplified_chinese, "").new_worktree_name);
    try testing.expectEqualStrings("基准", branchChromeFor(.simplified_chinese, "").base);
    try testing.expectEqualStrings("创建", branchChromeFor(.simplified_chinese, "").create);
    try testing.expectEqualStrings("删除", branchChromeFor(.simplified_chinese, "").delete);
    try testing.expectEqualStrings(reviewDiffChromeFor(.simplified_chinese, "").branch, branchChromeFor(.simplified_chinese, "").branch_placeholder);
    try testing.expectEqualStrings(sidebarFor(.simplified_chinese, "").delete, branchChromeFor(.simplified_chinese, "").delete);

    try testing.expectEqualStrings("ブランチ", branchChromeFor(.japanese, "").branch_placeholder);
    try testing.expectEqualStrings("ブランチを検索", branchChromeFor(.japanese, "").search_branches);
    try testing.expectEqualStrings("新しいブランチ…", branchChromeFor(.japanese, "").new_branch_menu);
    try testing.expectEqualStrings("新しい worktree…", branchChromeFor(.japanese, "").new_worktree_menu);
    try testing.expectEqualStrings("ブランチを削除…", branchChromeFor(.japanese, "").delete_branch_menu);
    try testing.expectEqualStrings("フェッチ…", branchChromeFor(.japanese, "").fetch_menu);
    try testing.expectEqualStrings("コミット…", branchChromeFor(.japanese, "").commit_menu);
    try testing.expectEqualStrings("プッシュ…", branchChromeFor(.japanese, "").push_menu);
    try testing.expectEqualStrings("新しいブランチ名", branchChromeFor(.japanese, "").new_branch_name);
    try testing.expectEqualStrings("新しい worktree 名", branchChromeFor(.japanese, "").new_worktree_name);
    try testing.expectEqualStrings("ベース", branchChromeFor(.japanese, "").base);
    try testing.expectEqualStrings("作成", branchChromeFor(.japanese, "").create);
    try testing.expectEqualStrings("削除", branchChromeFor(.japanese, "").delete);
    try testing.expectEqualStrings(reviewDiffChromeFor(.japanese, "").branch, branchChromeFor(.japanese, "").branch_placeholder);
    try testing.expectEqualStrings(sidebarFor(.japanese, "").delete, branchChromeFor(.japanese, "").delete);

    try testing.expectEqualStrings("分支", branchChromeFor(.system, "zh_CN.UTF-8").branch_placeholder);
    try testing.expectEqualStrings("搜索分支", branchChromeFor(.system, "zh_CN.UTF-8").search_branches);
    try testing.expectEqualStrings("新建分支…", branchChromeFor(.system, "zh_CN.UTF-8").new_branch_menu);
    try testing.expectEqualStrings("新建 worktree…", branchChromeFor(.system, "zh_CN.UTF-8").new_worktree_menu);
    try testing.expectEqualStrings("创建", branchChromeFor(.system, "zh_CN.UTF-8").create);
    try testing.expectEqualStrings("ブランチ", branchChromeFor(.system, "ja_JP.UTF-8").branch_placeholder);
    try testing.expectEqualStrings("ブランチを検索", branchChromeFor(.system, "ja_JP.UTF-8").search_branches);
    try testing.expectEqualStrings("新しいブランチ…", branchChromeFor(.system, "ja_JP.UTF-8").new_branch_menu);
    try testing.expectEqualStrings("新しい worktree…", branchChromeFor(.system, "ja_JP.UTF-8").new_worktree_menu);
    try testing.expectEqualStrings("作成", branchChromeFor(.system, "ja_JP.UTF-8").create);
    try testing.expectEqualStrings("Branch", branchChromeFor(.english, "ja_JP.UTF-8").branch_placeholder);
    try testing.expectEqualStrings("Search branches", branchChromeFor(.english, "zh_CN.UTF-8").search_branches);
    try testing.expectEqualStrings("New branch…", branchChromeFor(.english, "ja_JP.UTF-8").new_branch_menu);
    try testing.expectEqualStrings("New worktree…", branchChromeFor(.english, "zh_CN.UTF-8").new_worktree_menu);
    try testing.expectEqualStrings("Delete branch…", branchChromeFor(.english, "ja_JP.UTF-8").delete_branch_menu);
    try testing.expectEqualStrings("Fetch…", branchChromeFor(.english, "zh_CN.UTF-8").fetch_menu);
    try testing.expectEqualStrings("Commit…", branchChromeFor(.english, "ja_JP.UTF-8").commit_menu);
    try testing.expectEqualStrings("Push…", branchChromeFor(.english, "zh_CN.UTF-8").push_menu);
    try testing.expectEqualStrings("New branch name", branchChromeFor(.english, "ja_JP.UTF-8").new_branch_name);
    try testing.expectEqualStrings("New worktree name", branchChromeFor(.english, "zh_CN.UTF-8").new_worktree_name);
    try testing.expectEqualStrings("Base", branchChromeFor(.english, "ja_JP.UTF-8").base);
    try testing.expectEqualStrings("Create", branchChromeFor(.english, "zh_CN.UTF-8").create);
    try testing.expectEqualStrings("Delete", branchChromeFor(.english, "ja_JP.UTF-8").delete);
}

test "workspaceChromeFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("Work in", workspaceChromeFor(.english, "ja").work_in);
    try testing.expectEqualStrings("Local", workspaceChromeFor(.english, "").local);
    try testing.expectEqualStrings("New worktree", workspaceChromeFor(.english, "").new_worktree);
    try testing.expectEqualStrings("Work in", workspaceChromeFor(.system, "").work_in);
    try testing.expectEqualStrings("Local", workspaceChromeFor(.system, "").local);
    try testing.expectEqualStrings("New worktree", workspaceChromeFor(.system, "").new_worktree);
    try testing.expect(std.mem.startsWith(u8, branchChromeFor(.english, "").new_worktree_menu, workspaceChromeFor(.english, "").new_worktree));
    try testing.expect(std.mem.startsWith(u8, branchChromeFor(.simplified_chinese, "").new_worktree_menu, workspaceChromeFor(.simplified_chinese, "").new_worktree));
    try testing.expect(std.mem.startsWith(u8, branchChromeFor(.japanese, "").new_worktree_menu, workspaceChromeFor(.japanese, "").new_worktree));

    try testing.expectEqualStrings("工作于", workspaceChromeFor(.simplified_chinese, "").work_in);
    try testing.expectEqualStrings("本地", workspaceChromeFor(.simplified_chinese, "").local);
    try testing.expectEqualStrings("新建 worktree", workspaceChromeFor(.simplified_chinese, "").new_worktree);

    try testing.expectEqualStrings("作業場所", workspaceChromeFor(.japanese, "").work_in);
    try testing.expectEqualStrings("ローカル", workspaceChromeFor(.japanese, "").local);
    try testing.expectEqualStrings("新しい worktree", workspaceChromeFor(.japanese, "").new_worktree);

    try testing.expectEqualStrings("工作于", workspaceChromeFor(.system, "zh_CN.UTF-8").work_in);
    try testing.expectEqualStrings("本地", workspaceChromeFor(.system, "zh_CN.UTF-8").local);
    try testing.expectEqualStrings("新建 worktree", workspaceChromeFor(.system, "zh_CN.UTF-8").new_worktree);
    try testing.expectEqualStrings("作業場所", workspaceChromeFor(.system, "ja_JP.UTF-8").work_in);
    try testing.expectEqualStrings("ローカル", workspaceChromeFor(.system, "ja_JP.UTF-8").local);
    try testing.expectEqualStrings("新しい worktree", workspaceChromeFor(.system, "ja_JP.UTF-8").new_worktree);
    try testing.expectEqualStrings("Work in", workspaceChromeFor(.english, "ja_JP.UTF-8").work_in);
    try testing.expectEqualStrings("Local", workspaceChromeFor(.english, "zh_CN.UTF-8").local);
    try testing.expectEqualStrings("New worktree", workspaceChromeFor(.english, "ja_JP.UTF-8").new_worktree);
}

test "worktreeStatusChromeFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("Creating worktree…", worktreeStatusChromeFor(.english, "ja").creating);
    try testing.expectEqualStrings("Could not create worktree.", worktreeStatusChromeFor(.english, "ja").create_failed);
    try testing.expectEqualStrings("Creating worktree…", worktreeStatusChromeFor(.english, "").creating);
    try testing.expectEqualStrings("Could not create worktree.", worktreeStatusChromeFor(.english, "").create_failed);
    try testing.expectEqualStrings("Creating worktree…", worktreeStatusChromeFor(.system, "").creating);
    try testing.expectEqualStrings("Could not create worktree.", worktreeStatusChromeFor(.system, "").create_failed);

    try testing.expectEqualStrings("正在创建 worktree…", worktreeStatusChromeFor(.simplified_chinese, "").creating);
    try testing.expectEqualStrings("无法创建 worktree。", worktreeStatusChromeFor(.simplified_chinese, "").create_failed);
    try testing.expectEqualStrings("worktree を作成中…", worktreeStatusChromeFor(.japanese, "").creating);
    try testing.expectEqualStrings("worktree を作成できませんでした。", worktreeStatusChromeFor(.japanese, "").create_failed);

    try testing.expectEqualStrings("正在创建 worktree…", worktreeStatusChromeFor(.system, "zh_CN.UTF-8").creating);
    try testing.expectEqualStrings("无法创建 worktree。", worktreeStatusChromeFor(.system, "zh_CN.UTF-8").create_failed);
    try testing.expectEqualStrings("worktree を作成中…", worktreeStatusChromeFor(.system, "ja_JP.UTF-8").creating);
    try testing.expectEqualStrings("worktree を作成できませんでした。", worktreeStatusChromeFor(.system, "ja_JP.UTF-8").create_failed);
    try testing.expectEqualStrings("Creating worktree…", worktreeStatusChromeFor(.english, "ja_JP.UTF-8").creating);
    try testing.expectEqualStrings("Could not create worktree.", worktreeStatusChromeFor(.english, "zh_CN.UTF-8").create_failed);
    try testing.expectEqualStrings("Creating worktree…", worktreeStatusChromeFor(.english, "zh_CN.UTF-8").creating);
    try testing.expectEqualStrings("Could not create worktree.", worktreeStatusChromeFor(.english, "ja_JP.UTF-8").create_failed);

    try testing.expect(!std.mem.eql(u8, worktreeStatusChromeFor(.english, "").creating, worktreeStatusChromeFor(.english, "").create_failed));
    try testing.expect(!std.mem.eql(u8, worktreeStatusChromeFor(.english, "").creating, workspaceChromeFor(.english, "").new_worktree));
    try testing.expect(!std.mem.eql(u8, worktreeStatusChromeFor(.english, "").creating, branchChromeFor(.english, "").new_worktree_menu));
    try testing.expect(!std.mem.eql(u8, worktreeStatusChromeFor(.english, "").creating, commitChromeFor(.english, "").generating));
    try testing.expect(!std.mem.eql(u8, worktreeStatusChromeFor(.english, "").creating, commitChromeFor(.english, "").amending));
    try testing.expect(!std.mem.eql(u8, worktreeStatusChromeFor(.english, "").creating, commitChromeFor(.english, "").pushing));
    try testing.expect(!std.mem.eql(u8, worktreeStatusChromeFor(.english, "").creating, commitChromeFor(.english, "").committing));
    try testing.expect(!std.mem.eql(u8, worktreeStatusChromeFor(.english, "").create_failed, workspaceChromeFor(.english, "").new_worktree));
    try testing.expect(!std.mem.eql(u8, worktreeStatusChromeFor(.english, "").create_failed, branchChromeFor(.english, "").new_worktree_menu));
    try testing.expect(!std.mem.eql(u8, worktreeStatusChromeFor(.simplified_chinese, "").creating, workspaceChromeFor(.simplified_chinese, "").new_worktree));
    try testing.expect(!std.mem.eql(u8, worktreeStatusChromeFor(.japanese, "").creating, workspaceChromeFor(.japanese, "").new_worktree));
    try testing.expect(!std.mem.eql(u8, worktreeStatusChromeFor(.simplified_chinese, "").creating, commitChromeFor(.simplified_chinese, "").generating));
    try testing.expect(!std.mem.eql(u8, worktreeStatusChromeFor(.japanese, "").creating, commitChromeFor(.japanese, "").generating));
}

test "branchOpStatusChromeFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("Could not check out branch.", branchOpStatusChromeFor(.english, "ja").checkout_failed);
    try testing.expectEqualStrings("Already checked out in another worktree.", branchOpStatusChromeFor(.english, "ja").occupied_checkout);
    try testing.expectEqualStrings("Could not create branch.", branchOpStatusChromeFor(.english, "ja").create_failed);
    try testing.expectEqualStrings("Could not delete branch.", branchOpStatusChromeFor(.english, "ja").delete_failed);
    try testing.expectEqualStrings("Could not fetch.", branchOpStatusChromeFor(.english, "ja").fetch_failed);
    try testing.expectEqualStrings("Could not push.", branchOpStatusChromeFor(.english, "ja").push_failed);
    try testing.expectEqualStrings("Could not check out branch.", branchOpStatusChromeFor(.english, "").checkout_failed);
    try testing.expectEqualStrings("Already checked out in another worktree.", branchOpStatusChromeFor(.english, "").occupied_checkout);
    try testing.expectEqualStrings("Could not create branch.", branchOpStatusChromeFor(.english, "").create_failed);
    try testing.expectEqualStrings("Could not delete branch.", branchOpStatusChromeFor(.english, "").delete_failed);
    try testing.expectEqualStrings("Could not fetch.", branchOpStatusChromeFor(.english, "").fetch_failed);
    try testing.expectEqualStrings("Could not push.", branchOpStatusChromeFor(.english, "").push_failed);
    try testing.expectEqualStrings("Could not check out branch.", branchOpStatusChromeFor(.system, "").checkout_failed);
    try testing.expectEqualStrings("Already checked out in another worktree.", branchOpStatusChromeFor(.system, "").occupied_checkout);
    try testing.expectEqualStrings("Could not create branch.", branchOpStatusChromeFor(.system, "").create_failed);
    try testing.expectEqualStrings("Could not delete branch.", branchOpStatusChromeFor(.system, "").delete_failed);
    try testing.expectEqualStrings("Could not fetch.", branchOpStatusChromeFor(.system, "").fetch_failed);
    try testing.expectEqualStrings("Could not push.", branchOpStatusChromeFor(.system, "").push_failed);

    try testing.expectEqualStrings("无法检出分支。", branchOpStatusChromeFor(.simplified_chinese, "").checkout_failed);
    try testing.expectEqualStrings("已在另一个 worktree 中检出。", branchOpStatusChromeFor(.simplified_chinese, "").occupied_checkout);
    try testing.expectEqualStrings("无法创建分支。", branchOpStatusChromeFor(.simplified_chinese, "").create_failed);
    try testing.expectEqualStrings("无法删除分支。", branchOpStatusChromeFor(.simplified_chinese, "").delete_failed);
    try testing.expectEqualStrings("无法获取。", branchOpStatusChromeFor(.simplified_chinese, "").fetch_failed);
    try testing.expectEqualStrings("无法推送。", branchOpStatusChromeFor(.simplified_chinese, "").push_failed);
    try testing.expectEqualStrings("ブランチをチェックアウトできませんでした。", branchOpStatusChromeFor(.japanese, "").checkout_failed);
    try testing.expectEqualStrings("別の worktree で既にチェックアウトされています。", branchOpStatusChromeFor(.japanese, "").occupied_checkout);
    try testing.expectEqualStrings("ブランチを作成できませんでした。", branchOpStatusChromeFor(.japanese, "").create_failed);
    try testing.expectEqualStrings("ブランチを削除できませんでした。", branchOpStatusChromeFor(.japanese, "").delete_failed);
    try testing.expectEqualStrings("フェッチできませんでした。", branchOpStatusChromeFor(.japanese, "").fetch_failed);
    try testing.expectEqualStrings("プッシュできませんでした。", branchOpStatusChromeFor(.japanese, "").push_failed);

    try testing.expectEqualStrings("无法检出分支。", branchOpStatusChromeFor(.system, "zh_CN.UTF-8").checkout_failed);
    try testing.expectEqualStrings("已在另一个 worktree 中检出。", branchOpStatusChromeFor(.system, "zh_CN.UTF-8").occupied_checkout);
    try testing.expectEqualStrings("无法创建分支。", branchOpStatusChromeFor(.system, "zh_CN.UTF-8").create_failed);
    try testing.expectEqualStrings("无法删除分支。", branchOpStatusChromeFor(.system, "zh_CN.UTF-8").delete_failed);
    try testing.expectEqualStrings("无法获取。", branchOpStatusChromeFor(.system, "zh_CN.UTF-8").fetch_failed);
    try testing.expectEqualStrings("无法推送。", branchOpStatusChromeFor(.system, "zh_CN.UTF-8").push_failed);
    try testing.expectEqualStrings("ブランチをチェックアウトできませんでした。", branchOpStatusChromeFor(.system, "ja_JP.UTF-8").checkout_failed);
    try testing.expectEqualStrings("別の worktree で既にチェックアウトされています。", branchOpStatusChromeFor(.system, "ja_JP.UTF-8").occupied_checkout);
    try testing.expectEqualStrings("ブランチを作成できませんでした。", branchOpStatusChromeFor(.system, "ja_JP.UTF-8").create_failed);
    try testing.expectEqualStrings("ブランチを削除できませんでした。", branchOpStatusChromeFor(.system, "ja_JP.UTF-8").delete_failed);
    try testing.expectEqualStrings("フェッチできませんでした。", branchOpStatusChromeFor(.system, "ja_JP.UTF-8").fetch_failed);
    try testing.expectEqualStrings("プッシュできませんでした。", branchOpStatusChromeFor(.system, "ja_JP.UTF-8").push_failed);
    try testing.expectEqualStrings("Could not check out branch.", branchOpStatusChromeFor(.english, "ja_JP.UTF-8").checkout_failed);
    try testing.expectEqualStrings("Already checked out in another worktree.", branchOpStatusChromeFor(.english, "zh_CN.UTF-8").occupied_checkout);
    try testing.expectEqualStrings("Could not create branch.", branchOpStatusChromeFor(.english, "zh_CN.UTF-8").create_failed);
    try testing.expectEqualStrings("Could not delete branch.", branchOpStatusChromeFor(.english, "ja_JP.UTF-8").delete_failed);
    try testing.expectEqualStrings("Could not fetch.", branchOpStatusChromeFor(.english, "zh_CN.UTF-8").fetch_failed);
    try testing.expectEqualStrings("Could not push.", branchOpStatusChromeFor(.english, "ja_JP.UTF-8").push_failed);

    try testing.expect(!std.mem.eql(u8, branchOpStatusChromeFor(.english, "").checkout_failed, branchOpStatusChromeFor(.english, "").occupied_checkout));
    try testing.expect(!std.mem.eql(u8, branchOpStatusChromeFor(.english, "").checkout_failed, branchOpStatusChromeFor(.english, "").create_failed));
    try testing.expect(!std.mem.eql(u8, branchOpStatusChromeFor(.english, "").create_failed, branchOpStatusChromeFor(.english, "").delete_failed));
    try testing.expect(!std.mem.eql(u8, branchOpStatusChromeFor(.english, "").fetch_failed, branchOpStatusChromeFor(.english, "").push_failed));
    try testing.expect(!std.mem.eql(u8, branchOpStatusChromeFor(.english, "").create_failed, worktreeStatusChromeFor(.english, "").create_failed));
    try testing.expect(!std.mem.eql(u8, branchOpStatusChromeFor(.english, "").push_failed, commitChromeFor(.english, "").pushing));
    try testing.expect(!std.mem.eql(u8, branchOpStatusChromeFor(.english, "").push_failed, commitChromeFor(.english, "").push));
    try testing.expect(!std.mem.eql(u8, branchOpStatusChromeFor(.english, "").fetch_failed, branchChromeFor(.english, "").fetch_menu));
    try testing.expect(!std.mem.eql(u8, branchOpStatusChromeFor(.english, "").occupied_checkout, workspaceChromeFor(.english, "").new_worktree));
    try testing.expect(!std.mem.eql(u8, branchOpStatusChromeFor(.english, "").occupied_checkout, worktreeStatusChromeFor(.english, "").create_failed));
    try testing.expect(!std.mem.eql(u8, branchOpStatusChromeFor(.simplified_chinese, "").create_failed, worktreeStatusChromeFor(.simplified_chinese, "").create_failed));
    try testing.expect(!std.mem.eql(u8, branchOpStatusChromeFor(.japanese, "").create_failed, worktreeStatusChromeFor(.japanese, "").create_failed));
    try testing.expect(!std.mem.eql(u8, branchOpStatusChromeFor(.simplified_chinese, "").push_failed, commitChromeFor(.simplified_chinese, "").pushing));
    try testing.expect(!std.mem.eql(u8, branchOpStatusChromeFor(.japanese, "").push_failed, commitChromeFor(.japanese, "").pushing));
    try testing.expect(!std.mem.eql(u8, branchOpStatusChromeFor(.simplified_chinese, "").fetch_failed, branchChromeFor(.simplified_chinese, "").fetch_menu));
    try testing.expect(!std.mem.eql(u8, branchOpStatusChromeFor(.japanese, "").fetch_failed, branchChromeFor(.japanese, "").fetch_menu));
    try testing.expect(std.mem.indexOf(u8, branchOpStatusChromeFor(.simplified_chinese, "").occupied_checkout, "worktree") != null);
    try testing.expect(std.mem.indexOf(u8, branchOpStatusChromeFor(.japanese, "").occupied_checkout, "worktree") != null);
}

test "commitAttachStatusChromeFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("Enter a commit message.", commitAttachStatusChromeFor(.english, "ja").empty_message);
    try testing.expectEqualStrings("Could not commit.", commitAttachStatusChromeFor(.english, "ja").commit_failed);
    try testing.expectEqualStrings("Nothing staged to commit.", commitAttachStatusChromeFor(.english, "ja").nothing_staged);
    try testing.expectEqualStrings("Could not generate a commit message.", commitAttachStatusChromeFor(.english, "ja").generate_failed);
    try testing.expectEqualStrings("Enter a commit message.", commitAttachStatusChromeFor(.english, "").empty_message);
    try testing.expectEqualStrings("Could not commit.", commitAttachStatusChromeFor(.english, "").commit_failed);
    try testing.expectEqualStrings("Nothing staged to commit.", commitAttachStatusChromeFor(.english, "").nothing_staged);
    try testing.expectEqualStrings("Could not generate a commit message.", commitAttachStatusChromeFor(.english, "").generate_failed);
    try testing.expectEqualStrings("Enter a commit message.", commitAttachStatusChromeFor(.system, "").empty_message);
    try testing.expectEqualStrings("Could not commit.", commitAttachStatusChromeFor(.system, "").commit_failed);
    try testing.expectEqualStrings("Nothing staged to commit.", commitAttachStatusChromeFor(.system, "").nothing_staged);
    try testing.expectEqualStrings("Could not generate a commit message.", commitAttachStatusChromeFor(.system, "").generate_failed);

    try testing.expectEqualStrings("请输入提交信息。", commitAttachStatusChromeFor(.simplified_chinese, "").empty_message);
    try testing.expectEqualStrings("无法提交。", commitAttachStatusChromeFor(.simplified_chinese, "").commit_failed);
    try testing.expectEqualStrings("没有可提交的暂存更改。", commitAttachStatusChromeFor(.simplified_chinese, "").nothing_staged);
    try testing.expectEqualStrings("无法生成提交信息。", commitAttachStatusChromeFor(.simplified_chinese, "").generate_failed);
    try testing.expectEqualStrings("コミットメッセージを入力してください。", commitAttachStatusChromeFor(.japanese, "").empty_message);
    try testing.expectEqualStrings("コミットできませんでした。", commitAttachStatusChromeFor(.japanese, "").commit_failed);
    try testing.expectEqualStrings("コミットするステージ済みの変更がありません。", commitAttachStatusChromeFor(.japanese, "").nothing_staged);
    try testing.expectEqualStrings("コミットメッセージを生成できませんでした。", commitAttachStatusChromeFor(.japanese, "").generate_failed);

    try testing.expectEqualStrings("请输入提交信息。", commitAttachStatusChromeFor(.system, "zh_CN.UTF-8").empty_message);
    try testing.expectEqualStrings("无法提交。", commitAttachStatusChromeFor(.system, "zh_CN.UTF-8").commit_failed);
    try testing.expectEqualStrings("没有可提交的暂存更改。", commitAttachStatusChromeFor(.system, "zh_CN.UTF-8").nothing_staged);
    try testing.expectEqualStrings("无法生成提交信息。", commitAttachStatusChromeFor(.system, "zh_CN.UTF-8").generate_failed);
    try testing.expectEqualStrings("コミットメッセージを入力してください。", commitAttachStatusChromeFor(.system, "ja_JP.UTF-8").empty_message);
    try testing.expectEqualStrings("コミットできませんでした。", commitAttachStatusChromeFor(.system, "ja_JP.UTF-8").commit_failed);
    try testing.expectEqualStrings("コミットするステージ済みの変更がありません。", commitAttachStatusChromeFor(.system, "ja_JP.UTF-8").nothing_staged);
    try testing.expectEqualStrings("コミットメッセージを生成できませんでした。", commitAttachStatusChromeFor(.system, "ja_JP.UTF-8").generate_failed);
    try testing.expectEqualStrings("Enter a commit message.", commitAttachStatusChromeFor(.english, "ja_JP.UTF-8").empty_message);
    try testing.expectEqualStrings("Could not commit.", commitAttachStatusChromeFor(.english, "zh_CN.UTF-8").commit_failed);
    try testing.expectEqualStrings("Nothing staged to commit.", commitAttachStatusChromeFor(.english, "zh_CN.UTF-8").nothing_staged);
    try testing.expectEqualStrings("Could not generate a commit message.", commitAttachStatusChromeFor(.english, "ja_JP.UTF-8").generate_failed);

    try testing.expect(!std.mem.eql(u8, commitAttachStatusChromeFor(.english, "").empty_message, commitAttachStatusChromeFor(.english, "").commit_failed));
    try testing.expect(!std.mem.eql(u8, commitAttachStatusChromeFor(.english, "").commit_failed, commitAttachStatusChromeFor(.english, "").nothing_staged));
    try testing.expect(!std.mem.eql(u8, commitAttachStatusChromeFor(.english, "").commit_failed, commitAttachStatusChromeFor(.english, "").generate_failed));
    try testing.expect(!std.mem.eql(u8, commitAttachStatusChromeFor(.english, "").empty_message, commitChromeFor(.english, "").commit_message));
    try testing.expect(!std.mem.eql(u8, commitAttachStatusChromeFor(.english, "").commit_failed, commitChromeFor(.english, "").committing));
    try testing.expect(!std.mem.eql(u8, commitAttachStatusChromeFor(.english, "").generate_failed, commitChromeFor(.english, "").generating));
    try testing.expect(!std.mem.eql(u8, commitAttachStatusChromeFor(.english, "").commit_failed, branchOpStatusChromeFor(.english, "").push_failed));
    try testing.expect(!std.mem.eql(u8, commitAttachStatusChromeFor(.english, "").nothing_staged, worktreeStatusChromeFor(.english, "").create_failed));
    try testing.expect(!std.mem.eql(u8, commitAttachStatusChromeFor(.english, "").empty_message, workspaceChromeFor(.english, "").work_in));
    try testing.expect(!std.mem.eql(u8, commitAttachStatusChromeFor(.simplified_chinese, "").commit_failed, commitChromeFor(.simplified_chinese, "").committing));
    try testing.expect(!std.mem.eql(u8, commitAttachStatusChromeFor(.japanese, "").commit_failed, commitChromeFor(.japanese, "").committing));
    try testing.expect(!std.mem.eql(u8, commitAttachStatusChromeFor(.simplified_chinese, "").generate_failed, commitChromeFor(.simplified_chinese, "").generating));
    try testing.expect(!std.mem.eql(u8, commitAttachStatusChromeFor(.japanese, "").generate_failed, commitChromeFor(.japanese, "").generating));
    try testing.expect(!std.mem.eql(u8, commitAttachStatusChromeFor(.simplified_chinese, "").commit_failed, branchOpStatusChromeFor(.simplified_chinese, "").push_failed));
    try testing.expect(!std.mem.eql(u8, commitAttachStatusChromeFor(.japanese, "").commit_failed, branchOpStatusChromeFor(.japanese, "").push_failed));
}

test "daemonDirChromeFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("Up", daemonDirChromeFor(.english, "ja").up);
    try testing.expectEqualStrings("Home", daemonDirChromeFor(.english, "").home);
    try testing.expectEqualStrings("Choose", daemonDirChromeFor(.english, "").choose);
    try testing.expectEqualStrings("Loading…", daemonDirChromeFor(.english, "").loading);
    try testing.expectEqualStrings("Up", daemonDirChromeFor(.system, "").up);
    try testing.expectEqualStrings("Home", daemonDirChromeFor(.system, "").home);
    try testing.expectEqualStrings("Choose", daemonDirChromeFor(.system, "").choose);
    try testing.expectEqualStrings("Loading…", daemonDirChromeFor(.system, "").loading);

    try testing.expectEqualStrings("上级", daemonDirChromeFor(.simplified_chinese, "").up);
    try testing.expectEqualStrings("主目录", daemonDirChromeFor(.simplified_chinese, "").home);
    try testing.expectEqualStrings("选择", daemonDirChromeFor(.simplified_chinese, "").choose);
    try testing.expectEqualStrings("加载中…", daemonDirChromeFor(.simplified_chinese, "").loading);
    try testing.expectEqualStrings("取消", commitChromeFor(.simplified_chinese, "").cancel);

    try testing.expectEqualStrings("上へ", daemonDirChromeFor(.japanese, "").up);
    try testing.expectEqualStrings("ホーム", daemonDirChromeFor(.japanese, "").home);
    try testing.expectEqualStrings("選択", daemonDirChromeFor(.japanese, "").choose);
    try testing.expectEqualStrings("読み込み中…", daemonDirChromeFor(.japanese, "").loading);
    try testing.expectEqualStrings("キャンセル", commitChromeFor(.japanese, "").cancel);

    try testing.expectEqualStrings("上级", daemonDirChromeFor(.system, "zh_CN.UTF-8").up);
    try testing.expectEqualStrings("主目录", daemonDirChromeFor(.system, "zh_CN.UTF-8").home);
    try testing.expectEqualStrings("选择", daemonDirChromeFor(.system, "zh_CN.UTF-8").choose);
    try testing.expectEqualStrings("加载中…", daemonDirChromeFor(.system, "zh_CN.UTF-8").loading);
    try testing.expectEqualStrings("上へ", daemonDirChromeFor(.system, "ja_JP.UTF-8").up);
    try testing.expectEqualStrings("ホーム", daemonDirChromeFor(.system, "ja_JP.UTF-8").home);
    try testing.expectEqualStrings("選択", daemonDirChromeFor(.system, "ja_JP.UTF-8").choose);
    try testing.expectEqualStrings("読み込み中…", daemonDirChromeFor(.system, "ja_JP.UTF-8").loading);
    try testing.expectEqualStrings("Up", daemonDirChromeFor(.english, "ja_JP.UTF-8").up);
    try testing.expectEqualStrings("Home", daemonDirChromeFor(.english, "zh_CN.UTF-8").home);
    try testing.expectEqualStrings("Choose", daemonDirChromeFor(.english, "ja_JP.UTF-8").choose);
    try testing.expectEqualStrings("Loading…", daemonDirChromeFor(.english, "ja_JP.UTF-8").loading);
    try testing.expectEqualStrings("Loading…", daemonDirChromeFor(.english, "zh_CN.UTF-8").loading);
}

test "switcherChromeFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("Switch session", switcherChromeFor(.english, "ja").title);
    try testing.expectEqualStrings("Switch", switcherChromeFor(.english, "").switch_label);
    try testing.expectEqualStrings("Switch session", switcherChromeFor(.system, "").title);
    try testing.expectEqualStrings("Switch", switcherChromeFor(.system, "").switch_label);
    try testing.expectEqualStrings(commitChromeFor(.english, "").cancel, "Cancel");

    try testing.expectEqualStrings("切换会话", switcherChromeFor(.simplified_chinese, "").title);
    try testing.expectEqualStrings("切换", switcherChromeFor(.simplified_chinese, "").switch_label);
    try testing.expectEqualStrings("取消", commitChromeFor(.simplified_chinese, "").cancel);

    try testing.expectEqualStrings("セッションを切り替え", switcherChromeFor(.japanese, "").title);
    try testing.expectEqualStrings("切り替え", switcherChromeFor(.japanese, "").switch_label);
    try testing.expectEqualStrings("キャンセル", commitChromeFor(.japanese, "").cancel);

    try testing.expectEqualStrings("切换会话", switcherChromeFor(.system, "zh_CN.UTF-8").title);
    try testing.expectEqualStrings("切换", switcherChromeFor(.system, "zh_CN.UTF-8").switch_label);
    try testing.expectEqualStrings("セッションを切り替え", switcherChromeFor(.system, "ja_JP.UTF-8").title);
    try testing.expectEqualStrings("切り替え", switcherChromeFor(.system, "ja_JP.UTF-8").switch_label);
    try testing.expectEqualStrings("Switch session", switcherChromeFor(.english, "ja_JP.UTF-8").title);
    try testing.expectEqualStrings("Switch", switcherChromeFor(.english, "zh_CN.UTF-8").switch_label);
    try testing.expectEqualStrings("Switch", switcherChromeFor(.english, "ja_JP.UTF-8").switch_label);
}

test "workspacePathChromeFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("Workspace path", workspacePathChromeFor(.english, "ja").placeholder);
    try testing.expectEqualStrings("Workspace path", workspacePathChromeFor(.english, "").placeholder);
    try testing.expectEqualStrings("Workspace path", workspacePathChromeFor(.system, "").placeholder);

    try testing.expectEqualStrings("工作区路径", workspacePathChromeFor(.simplified_chinese, "").placeholder);
    try testing.expectEqualStrings("ワークスペースのパス", workspacePathChromeFor(.japanese, "").placeholder);

    try testing.expectEqualStrings("工作区路径", workspacePathChromeFor(.system, "zh_CN.UTF-8").placeholder);
    try testing.expectEqualStrings("ワークスペースのパス", workspacePathChromeFor(.system, "ja_JP.UTF-8").placeholder);
    try testing.expectEqualStrings("Workspace path", workspacePathChromeFor(.english, "ja_JP.UTF-8").placeholder);
    try testing.expectEqualStrings("Workspace path", workspacePathChromeFor(.english, "zh_CN.UTF-8").placeholder);
}

test "untitledChromeFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("untitled", untitledChromeFor(.english, "ja").placeholder);
    try testing.expectEqualStrings("untitled", untitledChromeFor(.english, "").placeholder);
    try testing.expectEqualStrings("untitled", untitledChromeFor(.system, "").placeholder);

    try testing.expectEqualStrings("未命名", untitledChromeFor(.simplified_chinese, "").placeholder);
    try testing.expectEqualStrings("無題", untitledChromeFor(.japanese, "").placeholder);

    try testing.expectEqualStrings("未命名", untitledChromeFor(.system, "zh_CN.UTF-8").placeholder);
    try testing.expectEqualStrings("無題", untitledChromeFor(.system, "ja_JP.UTF-8").placeholder);
    try testing.expectEqualStrings("untitled", untitledChromeFor(.english, "ja_JP.UTF-8").placeholder);
    try testing.expectEqualStrings("untitled", untitledChromeFor(.english, "zh_CN.UTF-8").placeholder);
}

test "headerUntitledChromeFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("New task", headerUntitledChromeFor(.english, "ja").new_task);
    try testing.expectEqualStrings("New task", headerUntitledChromeFor(.english, "").new_task);
    try testing.expectEqualStrings("New task", headerUntitledChromeFor(.system, "").new_task);

    try testing.expectEqualStrings("新建任务", headerUntitledChromeFor(.simplified_chinese, "").new_task);
    try testing.expectEqualStrings("新しいタスク", headerUntitledChromeFor(.japanese, "").new_task);

    try testing.expectEqualStrings("新建任务", headerUntitledChromeFor(.system, "zh_CN.UTF-8").new_task);
    try testing.expectEqualStrings("新しいタスク", headerUntitledChromeFor(.system, "ja_JP.UTF-8").new_task);
    try testing.expectEqualStrings("New task", headerUntitledChromeFor(.english, "ja_JP.UTF-8").new_task);
    try testing.expectEqualStrings("New task", headerUntitledChromeFor(.english, "zh_CN.UTF-8").new_task);

    try testing.expect(!std.mem.eql(u8, headerUntitledChromeFor(.english, "").new_task, sidebarFor(.english, "").new_task));
    try testing.expectEqualStrings(headerUntitledChromeFor(.simplified_chinese, "").new_task, sidebarFor(.simplified_chinese, "").new_task);
    try testing.expectEqualStrings(headerUntitledChromeFor(.japanese, "").new_task, sidebarFor(.japanese, "").new_task);
}

test "daemonAddressChromeFor latin host:port in every locale; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("host:port", daemonAddressChromeFor(.english, "ja").placeholder);
    try testing.expectEqualStrings("host:port", daemonAddressChromeFor(.english, "").placeholder);
    try testing.expectEqualStrings("host:port", daemonAddressChromeFor(.system, "").placeholder);
    try testing.expectEqualStrings("host:port", daemonAddressChromeFor(.simplified_chinese, "").placeholder);
    try testing.expectEqualStrings("host:port", daemonAddressChromeFor(.japanese, "").placeholder);
    try testing.expectEqualStrings("host:port", daemonAddressChromeFor(.system, "zh_CN.UTF-8").placeholder);
    try testing.expectEqualStrings("host:port", daemonAddressChromeFor(.system, "ja_JP.UTF-8").placeholder);
    try testing.expectEqualStrings("host:port", daemonAddressChromeFor(.english, "ja_JP.UTF-8").placeholder);
    try testing.expectEqualStrings("host:port", daemonAddressChromeFor(.english, "zh_CN.UTF-8").placeholder);
}

test "settingsGeneralChromeFor english default; zh and ja chrome; latin FX_MODEL; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("Default model", settingsGeneralChromeFor(.english, "ja").default_model);
    try testing.expectEqualStrings("Default model", settingsGeneralChromeFor(.english, "").default_model);
    try testing.expectEqualStrings("Default model", settingsGeneralChromeFor(.system, "").default_model);
    try testing.expectEqualStrings("Access mode", settingsGeneralChromeFor(.english, "").access_mode);
    try testing.expectEqualStrings("Interaction", settingsGeneralChromeFor(.english, "").interaction);
    try testing.expectEqualStrings("Effort", settingsGeneralChromeFor(.english, "").effort);
    try testing.expectEqualStrings("Last project path", settingsGeneralChromeFor(.english, "").last_project_path);
    try testing.expectEqualStrings("Daemon address", settingsGeneralChromeFor(.english, "").daemon_address);
    try testing.expectEqualStrings("FX_MODEL", settingsGeneralChromeFor(.english, "").default_model_placeholder);

    try testing.expectEqualStrings("默认模型", settingsGeneralChromeFor(.simplified_chinese, "").default_model);
    try testing.expectEqualStrings("访问模式", settingsGeneralChromeFor(.simplified_chinese, "").access_mode);
    try testing.expectEqualStrings("交互", settingsGeneralChromeFor(.simplified_chinese, "").interaction);
    try testing.expectEqualStrings("力度", settingsGeneralChromeFor(.simplified_chinese, "").effort);
    try testing.expectEqualStrings("上次项目路径", settingsGeneralChromeFor(.simplified_chinese, "").last_project_path);
    try testing.expectEqualStrings("守护进程地址", settingsGeneralChromeFor(.simplified_chinese, "").daemon_address);
    try testing.expectEqualStrings("FX_MODEL", settingsGeneralChromeFor(.simplified_chinese, "").default_model_placeholder);

    try testing.expectEqualStrings("デフォルトモデル", settingsGeneralChromeFor(.japanese, "").default_model);
    try testing.expectEqualStrings("アクセスモード", settingsGeneralChromeFor(.japanese, "").access_mode);
    try testing.expectEqualStrings("インタラクション", settingsGeneralChromeFor(.japanese, "").interaction);
    try testing.expectEqualStrings("エフォート", settingsGeneralChromeFor(.japanese, "").effort);
    try testing.expectEqualStrings("前回のプロジェクトパス", settingsGeneralChromeFor(.japanese, "").last_project_path);
    try testing.expectEqualStrings("デーモンアドレス", settingsGeneralChromeFor(.japanese, "").daemon_address);
    try testing.expectEqualStrings("FX_MODEL", settingsGeneralChromeFor(.japanese, "").default_model_placeholder);

    try testing.expectEqualStrings("默认模型", settingsGeneralChromeFor(.system, "zh_CN.UTF-8").default_model);
    try testing.expectEqualStrings("デフォルトモデル", settingsGeneralChromeFor(.system, "ja_JP.UTF-8").default_model);
    try testing.expectEqualStrings("Default model", settingsGeneralChromeFor(.english, "ja_JP.UTF-8").default_model);
    try testing.expectEqualStrings("Default model", settingsGeneralChromeFor(.english, "zh_CN.UTF-8").default_model);
    try testing.expectEqualStrings("上次项目路径", settingsGeneralChromeFor(.system, "zh_CN.UTF-8").last_project_path);
    try testing.expectEqualStrings("デーモンアドレス", settingsGeneralChromeFor(.system, "ja_JP.UTF-8").daemon_address);
    try testing.expectEqualStrings("FX_MODEL", settingsGeneralChromeFor(.system, "zh_CN.UTF-8").default_model_placeholder);
    try testing.expectEqualStrings("FX_MODEL", settingsGeneralChromeFor(.system, "ja_JP.UTF-8").default_model_placeholder);
}

test "osFolderDialogChromeFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("Choose a project", osFolderDialogChromeFor(.english, "ja").prompt);
    try testing.expectEqualStrings("Choose a project", osFolderDialogChromeFor(.english, "").prompt);
    try testing.expectEqualStrings("Choose a project", osFolderDialogChromeFor(.system, "").prompt);
    try testing.expectEqualStrings("No OS folder picker (install zenity or kdialog). Type a path.", osFolderDialogChromeFor(.english, "").linux_missing);
    try testing.expectEqualStrings("No OS folder picker (osascript missing). Type a path.", osFolderDialogChromeFor(.english, "").macos_missing);
    try testing.expectEqualStrings("No OS folder picker (powershell.exe missing). Type a path.", osFolderDialogChromeFor(.english, "").windows_missing);

    try testing.expectEqualStrings("选择一个项目", osFolderDialogChromeFor(.simplified_chinese, "").prompt);
    try testing.expectEqualStrings("没有 OS 文件夹选择器（请安装 zenity 或 kdialog）。请输入路径。", osFolderDialogChromeFor(.simplified_chinese, "").linux_missing);
    try testing.expectEqualStrings("没有 OS 文件夹选择器（缺少 osascript）。请输入路径。", osFolderDialogChromeFor(.simplified_chinese, "").macos_missing);
    try testing.expectEqualStrings("没有 OS 文件夹选择器（缺少 powershell.exe）。请输入路径。", osFolderDialogChromeFor(.simplified_chinese, "").windows_missing);

    try testing.expectEqualStrings("プロジェクトを選択", osFolderDialogChromeFor(.japanese, "").prompt);
    try testing.expectEqualStrings("OS のフォルダ選択がありません（zenity または kdialog をインストールしてください）。パスを入力してください。", osFolderDialogChromeFor(.japanese, "").linux_missing);
    try testing.expectEqualStrings("OS のフォルダ選択がありません（osascript がありません）。パスを入力してください。", osFolderDialogChromeFor(.japanese, "").macos_missing);
    try testing.expectEqualStrings("OS のフォルダ選択がありません（powershell.exe がありません）。パスを入力してください。", osFolderDialogChromeFor(.japanese, "").windows_missing);

    try testing.expectEqualStrings("选择一个项目", osFolderDialogChromeFor(.system, "zh_CN.UTF-8").prompt);
    try testing.expectEqualStrings("プロジェクトを選択", osFolderDialogChromeFor(.system, "ja_JP.UTF-8").prompt);
    try testing.expectEqualStrings("Choose a project", osFolderDialogChromeFor(.english, "ja_JP.UTF-8").prompt);
    try testing.expectEqualStrings("Choose a project", osFolderDialogChromeFor(.english, "zh_CN.UTF-8").prompt);
    try testing.expectEqualStrings("没有 OS 文件夹选择器（请安装 zenity 或 kdialog）。请输入路径。", osFolderDialogChromeFor(.system, "zh_CN.UTF-8").linux_missing);
    try testing.expectEqualStrings("OS のフォルダ選択がありません（osascript がありません）。パスを入力してください。", osFolderDialogChromeFor(.system, "ja_JP.UTF-8").macos_missing);
}

test "osImageDialogChromeFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("Choose an image", osImageDialogChromeFor(.english, "ja").prompt);
    try testing.expectEqualStrings("Choose an image", osImageDialogChromeFor(.english, "").prompt);
    try testing.expectEqualStrings("Choose an image", osImageDialogChromeFor(.system, "").prompt);
    try testing.expectEqualStrings("No OS image picker (install zenity or kdialog). Type a path or drop a file.", osImageDialogChromeFor(.english, "").linux_missing);
    try testing.expectEqualStrings("No OS image picker (osascript missing). Type a path or drop a file.", osImageDialogChromeFor(.english, "").macos_missing);
    try testing.expectEqualStrings("No OS image picker (powershell.exe missing). Type a path or drop a file.", osImageDialogChromeFor(.english, "").windows_missing);

    try testing.expectEqualStrings("选择一张图片", osImageDialogChromeFor(.simplified_chinese, "").prompt);
    try testing.expectEqualStrings("没有 OS 图片选择器（请安装 zenity 或 kdialog）。请输入路径或拖放文件。", osImageDialogChromeFor(.simplified_chinese, "").linux_missing);
    try testing.expectEqualStrings("没有 OS 图片选择器（缺少 osascript）。请输入路径或拖放文件。", osImageDialogChromeFor(.simplified_chinese, "").macos_missing);
    try testing.expectEqualStrings("没有 OS 图片选择器（缺少 powershell.exe）。请输入路径或拖放文件。", osImageDialogChromeFor(.simplified_chinese, "").windows_missing);

    try testing.expectEqualStrings("画像を選択", osImageDialogChromeFor(.japanese, "").prompt);
    try testing.expectEqualStrings("OS の画像選択がありません（zenity または kdialog をインストールしてください）。パスを入力するかファイルをドロップしてください。", osImageDialogChromeFor(.japanese, "").linux_missing);
    try testing.expectEqualStrings("OS の画像選択がありません（osascript がありません）。パスを入力するかファイルをドロップしてください。", osImageDialogChromeFor(.japanese, "").macos_missing);
    try testing.expectEqualStrings("OS の画像選択がありません（powershell.exe がありません）。パスを入力するかファイルをドロップしてください。", osImageDialogChromeFor(.japanese, "").windows_missing);

    try testing.expectEqualStrings("选择一张图片", osImageDialogChromeFor(.system, "zh_CN.UTF-8").prompt);
    try testing.expectEqualStrings("画像を選択", osImageDialogChromeFor(.system, "ja_JP.UTF-8").prompt);
    try testing.expectEqualStrings("Choose an image", osImageDialogChromeFor(.english, "ja_JP.UTF-8").prompt);
    try testing.expectEqualStrings("Choose an image", osImageDialogChromeFor(.english, "zh_CN.UTF-8").prompt);
    try testing.expectEqualStrings("没有 OS 图片选择器（请安装 zenity 或 kdialog）。请输入路径或拖放文件。", osImageDialogChromeFor(.system, "zh_CN.UTF-8").linux_missing);
    try testing.expectEqualStrings("OS の画像選択がありません（osascript がありません）。パスを入力するかファイルをドロップしてください。", osImageDialogChromeFor(.system, "ja_JP.UTF-8").macos_missing);
}

test "composerChromeFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("Image path", composerChromeFor(.english, "ja").image_path);
    try testing.expectEqualStrings("Image path", composerChromeFor(.english, "").image_path);
    try testing.expectEqualStrings("Image path", composerChromeFor(.system, "").image_path);
    try testing.expectEqualStrings("Status", composerChromeFor(.english, "").status);
    try testing.expectEqualStrings("Status", composerChromeFor(.system, "").status);
    try testing.expectEqualStrings("Pick image", composerChromeFor(.english, "").pick_image);
    try testing.expectEqualStrings("Pick image", composerChromeFor(.system, "").pick_image);
    try testing.expectEqualStrings("Attach image", composerChromeFor(.english, "").attach_image);
    try testing.expectEqualStrings("Attach image", composerChromeFor(.system, "").attach_image);
    try testing.expectEqualStrings("Clear image", composerChromeFor(.english, "").clear_image);
    try testing.expectEqualStrings("Clear image", composerChromeFor(.system, "").clear_image);
    try testing.expectEqualStrings("Attached image", composerChromeFor(.english, "").attached_image);
    try testing.expectEqualStrings("Attached image", composerChromeFor(.system, "").attached_image);
    try testing.expectEqualStrings("Commands", composerChromeFor(.english, "").commands);
    try testing.expectEqualStrings("Commands", composerChromeFor(.system, "").commands);
    try testing.expectEqualStrings(paletteChromeFor(.english, "").commands, composerChromeFor(.english, "").commands);

    try testing.expectEqualStrings("图片路径", composerChromeFor(.simplified_chinese, "").image_path);
    try testing.expectEqualStrings("状态", composerChromeFor(.simplified_chinese, "").status);
    try testing.expectEqualStrings("选择图片", composerChromeFor(.simplified_chinese, "").pick_image);
    try testing.expectEqualStrings("附加图片", composerChromeFor(.simplified_chinese, "").attach_image);
    try testing.expectEqualStrings("清除图片", composerChromeFor(.simplified_chinese, "").clear_image);
    try testing.expectEqualStrings("已附加图片", composerChromeFor(.simplified_chinese, "").attached_image);
    try testing.expectEqualStrings("命令", composerChromeFor(.simplified_chinese, "").commands);
    try testing.expectEqualStrings(paletteChromeFor(.simplified_chinese, "").commands, composerChromeFor(.simplified_chinese, "").commands);

    try testing.expectEqualStrings("画像パス", composerChromeFor(.japanese, "").image_path);
    try testing.expectEqualStrings("ステータス", composerChromeFor(.japanese, "").status);
    try testing.expectEqualStrings("画像を選択", composerChromeFor(.japanese, "").pick_image);
    try testing.expectEqualStrings("画像を添付", composerChromeFor(.japanese, "").attach_image);
    try testing.expectEqualStrings("画像をクリア", composerChromeFor(.japanese, "").clear_image);
    try testing.expectEqualStrings("添付画像", composerChromeFor(.japanese, "").attached_image);
    try testing.expectEqualStrings("コマンド", composerChromeFor(.japanese, "").commands);
    try testing.expectEqualStrings(paletteChromeFor(.japanese, "").commands, composerChromeFor(.japanese, "").commands);

    try testing.expectEqualStrings("图片路径", composerChromeFor(.system, "zh_CN.UTF-8").image_path);
    try testing.expectEqualStrings("状态", composerChromeFor(.system, "zh_CN.UTF-8").status);
    try testing.expectEqualStrings("选择图片", composerChromeFor(.system, "zh_CN.UTF-8").pick_image);
    try testing.expectEqualStrings("附加图片", composerChromeFor(.system, "zh_CN.UTF-8").attach_image);
    try testing.expectEqualStrings("清除图片", composerChromeFor(.system, "zh_CN.UTF-8").clear_image);
    try testing.expectEqualStrings("已附加图片", composerChromeFor(.system, "zh_CN.UTF-8").attached_image);
    try testing.expectEqualStrings("命令", composerChromeFor(.system, "zh_CN.UTF-8").commands);
    try testing.expectEqualStrings("画像パス", composerChromeFor(.system, "ja_JP.UTF-8").image_path);
    try testing.expectEqualStrings("ステータス", composerChromeFor(.system, "ja_JP.UTF-8").status);
    try testing.expectEqualStrings("画像を選択", composerChromeFor(.system, "ja_JP.UTF-8").pick_image);
    try testing.expectEqualStrings("画像を添付", composerChromeFor(.system, "ja_JP.UTF-8").attach_image);
    try testing.expectEqualStrings("画像をクリア", composerChromeFor(.system, "ja_JP.UTF-8").clear_image);
    try testing.expectEqualStrings("添付画像", composerChromeFor(.system, "ja_JP.UTF-8").attached_image);
    try testing.expectEqualStrings("コマンド", composerChromeFor(.system, "ja_JP.UTF-8").commands);
    try testing.expectEqualStrings("Image path", composerChromeFor(.english, "ja_JP.UTF-8").image_path);
    try testing.expectEqualStrings("Status", composerChromeFor(.english, "zh_CN.UTF-8").status);
    try testing.expectEqualStrings("Pick image", composerChromeFor(.english, "ja_JP.UTF-8").pick_image);
    try testing.expectEqualStrings("Attach image", composerChromeFor(.english, "zh_CN.UTF-8").attach_image);
    try testing.expectEqualStrings("Clear image", composerChromeFor(.english, "ja_JP.UTF-8").clear_image);
    try testing.expectEqualStrings("Attached image", composerChromeFor(.english, "zh_CN.UTF-8").attached_image);
    try testing.expectEqualStrings("Commands", composerChromeFor(.english, "ja_JP.UTF-8").commands);
    try testing.expectEqualStrings("Image path", composerChromeFor(.english, "zh_CN.UTF-8").image_path);
    try testing.expectEqualStrings("Status", composerChromeFor(.english, "ja_JP.UTF-8").status);
    try testing.expectEqualStrings("Pick image", composerChromeFor(.english, "zh_CN.UTF-8").pick_image);
    try testing.expectEqualStrings("Attach image", composerChromeFor(.english, "ja_JP.UTF-8").attach_image);
    try testing.expectEqualStrings("Clear image", composerChromeFor(.english, "zh_CN.UTF-8").clear_image);
    try testing.expectEqualStrings("Attached image", composerChromeFor(.english, "ja_JP.UTF-8").attached_image);
    try testing.expectEqualStrings("Commands", composerChromeFor(.english, "zh_CN.UTF-8").commands);
}

test "composerSendStopChromeFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("Send", composerSendStopChromeFor(.english, "ja").send);
    try testing.expectEqualStrings("Stop", composerSendStopChromeFor(.english, "ja").stop);
    try testing.expectEqualStrings("Send", composerSendStopChromeFor(.english, "").send);
    try testing.expectEqualStrings("Stop", composerSendStopChromeFor(.english, "").stop);
    try testing.expectEqualStrings("Send", composerSendStopChromeFor(.system, "").send);
    try testing.expectEqualStrings("Stop", composerSendStopChromeFor(.system, "").stop);

    try testing.expectEqualStrings("发送", composerSendStopChromeFor(.simplified_chinese, "").send);
    try testing.expectEqualStrings("停止", composerSendStopChromeFor(.simplified_chinese, "").stop);
    try testing.expectEqualStrings("送信", composerSendStopChromeFor(.japanese, "").send);
    try testing.expectEqualStrings("停止", composerSendStopChromeFor(.japanese, "").stop);

    try testing.expectEqualStrings("发送", composerSendStopChromeFor(.system, "zh_CN.UTF-8").send);
    try testing.expectEqualStrings("停止", composerSendStopChromeFor(.system, "zh_CN.UTF-8").stop);
    try testing.expectEqualStrings("送信", composerSendStopChromeFor(.system, "ja_JP.UTF-8").send);
    try testing.expectEqualStrings("停止", composerSendStopChromeFor(.system, "ja_JP.UTF-8").stop);
    try testing.expectEqualStrings("Send", composerSendStopChromeFor(.english, "ja_JP.UTF-8").send);
    try testing.expectEqualStrings("Stop", composerSendStopChromeFor(.english, "ja_JP.UTF-8").stop);
    try testing.expectEqualStrings("Send", composerSendStopChromeFor(.english, "zh_CN.UTF-8").send);
    try testing.expectEqualStrings("Stop", composerSendStopChromeFor(.english, "zh_CN.UTF-8").stop);

    try testing.expect(!std.mem.eql(u8, composerSendStopChromeFor(.english, "").send, composerSendStopChromeFor(.english, "").stop));
}

test "composerPlaceholderChromeFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("Do anything...", composerPlaceholderChromeFor(.english, "ja").idle);
    try testing.expectEqualStrings("Queue a follow-up...", composerPlaceholderChromeFor(.english, "ja").streaming);
    try testing.expectEqualStrings("Do anything...", composerPlaceholderChromeFor(.english, "").idle);
    try testing.expectEqualStrings("Queue a follow-up...", composerPlaceholderChromeFor(.english, "").streaming);
    try testing.expectEqualStrings("Do anything...", composerPlaceholderChromeFor(.system, "").idle);
    try testing.expectEqualStrings("Queue a follow-up...", composerPlaceholderChromeFor(.system, "").streaming);

    try testing.expectEqualStrings("随便做什么...", composerPlaceholderChromeFor(.simplified_chinese, "").idle);
    try testing.expectEqualStrings("排队跟进...", composerPlaceholderChromeFor(.simplified_chinese, "").streaming);
    try testing.expectEqualStrings("何でもどうぞ...", composerPlaceholderChromeFor(.japanese, "").idle);
    try testing.expectEqualStrings("フォローアップをキュー...", composerPlaceholderChromeFor(.japanese, "").streaming);

    try testing.expectEqualStrings("随便做什么...", composerPlaceholderChromeFor(.system, "zh_CN.UTF-8").idle);
    try testing.expectEqualStrings("排队跟进...", composerPlaceholderChromeFor(.system, "zh_CN.UTF-8").streaming);
    try testing.expectEqualStrings("何でもどうぞ...", composerPlaceholderChromeFor(.system, "ja_JP.UTF-8").idle);
    try testing.expectEqualStrings("フォローアップをキュー...", composerPlaceholderChromeFor(.system, "ja_JP.UTF-8").streaming);
    try testing.expectEqualStrings("Do anything...", composerPlaceholderChromeFor(.english, "ja_JP.UTF-8").idle);
    try testing.expectEqualStrings("Queue a follow-up...", composerPlaceholderChromeFor(.english, "ja_JP.UTF-8").streaming);
    try testing.expectEqualStrings("Do anything...", composerPlaceholderChromeFor(.english, "zh_CN.UTF-8").idle);
    try testing.expectEqualStrings("Queue a follow-up...", composerPlaceholderChromeFor(.english, "zh_CN.UTF-8").streaming);

    try testing.expect(!std.mem.eql(u8, composerPlaceholderChromeFor(.english, "").idle, composerPlaceholderChromeFor(.english, "").streaming));
    try testing.expect(!std.mem.eql(u8, composerPlaceholderChromeFor(.english, "").streaming, queueChromeFor(.english, "").queued));
    try testing.expect(!std.mem.eql(u8, composerPlaceholderChromeFor(.simplified_chinese, "").streaming, queueChromeFor(.simplified_chinese, "").queued));
    try testing.expect(!std.mem.eql(u8, composerPlaceholderChromeFor(.japanese, "").streaming, queueChromeFor(.japanese, "").queued));
    try testing.expect(!std.mem.eql(u8, composerPlaceholderChromeFor(.english, "").idle, composerChromeFor(.english, "").image_path));
    try testing.expect(!std.mem.eql(u8, composerPlaceholderChromeFor(.english, "").idle, composerSendStopChromeFor(.english, "").send));
}

test "welcomeChromeFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("What should we build?", welcomeChromeFor(.english, "ja").title);
    try testing.expectEqualStrings("Pick a project, or just start typing.", welcomeChromeFor(.english, "ja").subtitle);
    try testing.expectEqualStrings("What should we build?", welcomeChromeFor(.english, "").title);
    try testing.expectEqualStrings("Pick a project, or just start typing.", welcomeChromeFor(.english, "").subtitle);
    try testing.expectEqualStrings("What should we build?", welcomeChromeFor(.system, "").title);
    try testing.expectEqualStrings("Pick a project, or just start typing.", welcomeChromeFor(.system, "").subtitle);

    try testing.expectEqualStrings("我们要构建什么？", welcomeChromeFor(.simplified_chinese, "").title);
    try testing.expectEqualStrings("选择一个项目，或直接开始输入。", welcomeChromeFor(.simplified_chinese, "").subtitle);
    try testing.expectEqualStrings("何を作りましょうか？", welcomeChromeFor(.japanese, "").title);
    try testing.expectEqualStrings("プロジェクトを選ぶか、そのまま入力を始めてください。", welcomeChromeFor(.japanese, "").subtitle);

    try testing.expectEqualStrings("我们要构建什么？", welcomeChromeFor(.system, "zh_CN.UTF-8").title);
    try testing.expectEqualStrings("选择一个项目，或直接开始输入。", welcomeChromeFor(.system, "zh_CN.UTF-8").subtitle);
    try testing.expectEqualStrings("何を作りましょうか？", welcomeChromeFor(.system, "ja_JP.UTF-8").title);
    try testing.expectEqualStrings("プロジェクトを選ぶか、そのまま入力を始めてください。", welcomeChromeFor(.system, "ja_JP.UTF-8").subtitle);
    try testing.expectEqualStrings("What should we build?", welcomeChromeFor(.english, "ja_JP.UTF-8").title);
    try testing.expectEqualStrings("Pick a project, or just start typing.", welcomeChromeFor(.english, "ja_JP.UTF-8").subtitle);
    try testing.expectEqualStrings("What should we build?", welcomeChromeFor(.english, "zh_CN.UTF-8").title);
    try testing.expectEqualStrings("Pick a project, or just start typing.", welcomeChromeFor(.english, "zh_CN.UTF-8").subtitle);

    try testing.expect(!std.mem.eql(u8, welcomeChromeFor(.english, "").title, welcomeChromeFor(.english, "").subtitle));
    try testing.expect(!std.mem.eql(u8, welcomeChromeFor(.english, "").title, headerUntitledChromeFor(.english, "").new_task));
    try testing.expect(!std.mem.eql(u8, welcomeChromeFor(.english, "").title, composerPlaceholderChromeFor(.english, "").idle));
    try testing.expect(!std.mem.eql(u8, welcomeChromeFor(.english, "").subtitle, composerPlaceholderChromeFor(.english, "").idle));
    try testing.expect(!std.mem.eql(u8, welcomeChromeFor(.english, "").subtitle, queueChromeFor(.english, "").queued));
    try testing.expect(!std.mem.eql(u8, welcomeChromeFor(.simplified_chinese, "").title, headerUntitledChromeFor(.simplified_chinese, "").new_task));
    try testing.expect(!std.mem.eql(u8, welcomeChromeFor(.japanese, "").title, headerUntitledChromeFor(.japanese, "").new_task));
}

test "findBarChromeFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("Previous match", findBarChromeFor(.english, "ja").previous_match);
    try testing.expectEqualStrings("Next match", findBarChromeFor(.english, "ja").next_match);
    try testing.expectEqualStrings("Close find", findBarChromeFor(.english, "ja").close_find);
    try testing.expectEqualStrings("Previous match", findBarChromeFor(.english, "").previous_match);
    try testing.expectEqualStrings("Next match", findBarChromeFor(.english, "").next_match);
    try testing.expectEqualStrings("Close find", findBarChromeFor(.english, "").close_find);
    try testing.expectEqualStrings("Previous match", findBarChromeFor(.system, "").previous_match);
    try testing.expectEqualStrings("Next match", findBarChromeFor(.system, "").next_match);
    try testing.expectEqualStrings("Close find", findBarChromeFor(.system, "").close_find);

    try testing.expectEqualStrings("上一个匹配", findBarChromeFor(.simplified_chinese, "").previous_match);
    try testing.expectEqualStrings("下一个匹配", findBarChromeFor(.simplified_chinese, "").next_match);
    try testing.expectEqualStrings("关闭查找", findBarChromeFor(.simplified_chinese, "").close_find);
    try testing.expectEqualStrings("前の一致", findBarChromeFor(.japanese, "").previous_match);
    try testing.expectEqualStrings("次の一致", findBarChromeFor(.japanese, "").next_match);
    try testing.expectEqualStrings("検索を閉じる", findBarChromeFor(.japanese, "").close_find);

    try testing.expectEqualStrings("上一个匹配", findBarChromeFor(.system, "zh_CN.UTF-8").previous_match);
    try testing.expectEqualStrings("下一个匹配", findBarChromeFor(.system, "zh_CN.UTF-8").next_match);
    try testing.expectEqualStrings("关闭查找", findBarChromeFor(.system, "zh_CN.UTF-8").close_find);
    try testing.expectEqualStrings("前の一致", findBarChromeFor(.system, "ja_JP.UTF-8").previous_match);
    try testing.expectEqualStrings("次の一致", findBarChromeFor(.system, "ja_JP.UTF-8").next_match);
    try testing.expectEqualStrings("検索を閉じる", findBarChromeFor(.system, "ja_JP.UTF-8").close_find);
    try testing.expectEqualStrings("Previous match", findBarChromeFor(.english, "ja_JP.UTF-8").previous_match);
    try testing.expectEqualStrings("Next match", findBarChromeFor(.english, "ja_JP.UTF-8").next_match);
    try testing.expectEqualStrings("Close find", findBarChromeFor(.english, "ja_JP.UTF-8").close_find);
    try testing.expectEqualStrings("Previous match", findBarChromeFor(.english, "zh_CN.UTF-8").previous_match);
    try testing.expectEqualStrings("Next match", findBarChromeFor(.english, "zh_CN.UTF-8").next_match);
    try testing.expectEqualStrings("Close find", findBarChromeFor(.english, "zh_CN.UTF-8").close_find);
}

test "findMatchChromeFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("No matches", findMatchChromeFor(.english, "ja").no_matches);
    try testing.expectEqualStrings("{d} of {d}", findMatchChromeFor(.english, "ja").of_fmt);
    try testing.expectEqualStrings("No matches", findMatchChromeFor(.english, "").no_matches);
    try testing.expectEqualStrings("{d} of {d}", findMatchChromeFor(.english, "").of_fmt);
    try testing.expectEqualStrings("No matches", findMatchChromeFor(.system, "").no_matches);
    try testing.expectEqualStrings("{d} of {d}", findMatchChromeFor(.system, "").of_fmt);

    try testing.expectEqualStrings("无匹配", findMatchChromeFor(.simplified_chinese, "").no_matches);
    try testing.expectEqualStrings("{d} / {d}", findMatchChromeFor(.simplified_chinese, "").of_fmt);
    try testing.expectEqualStrings("一致なし", findMatchChromeFor(.japanese, "").no_matches);
    try testing.expectEqualStrings("{d} / {d}", findMatchChromeFor(.japanese, "").of_fmt);

    try testing.expectEqualStrings("无匹配", findMatchChromeFor(.system, "zh_CN.UTF-8").no_matches);
    try testing.expectEqualStrings("{d} / {d}", findMatchChromeFor(.system, "zh_CN.UTF-8").of_fmt);
    try testing.expectEqualStrings("一致なし", findMatchChromeFor(.system, "ja_JP.UTF-8").no_matches);
    try testing.expectEqualStrings("{d} / {d}", findMatchChromeFor(.system, "ja_JP.UTF-8").of_fmt);
    try testing.expectEqualStrings("No matches", findMatchChromeFor(.english, "ja_JP.UTF-8").no_matches);
    try testing.expectEqualStrings("{d} of {d}", findMatchChromeFor(.english, "ja_JP.UTF-8").of_fmt);
    try testing.expectEqualStrings("No matches", findMatchChromeFor(.english, "zh_CN.UTF-8").no_matches);
    try testing.expectEqualStrings("{d} of {d}", findMatchChromeFor(.english, "zh_CN.UTF-8").of_fmt);

    try testing.expect(!std.mem.eql(u8, findMatchChromeFor(.english, "").no_matches, transcriptTurnChromeFor(.english, "").match));
    try testing.expect(!std.mem.eql(u8, findMatchChromeFor(.simplified_chinese, "").no_matches, transcriptTurnChromeFor(.simplified_chinese, "").match));
    try testing.expect(!std.mem.eql(u8, findMatchChromeFor(.japanese, "").no_matches, transcriptTurnChromeFor(.japanese, "").match));
    try testing.expect(!std.mem.eql(u8, findMatchChromeFor(.english, "").no_matches, findBarChromeFor(.english, "").previous_match));
    try testing.expect(!std.mem.eql(u8, findMatchChromeFor(.simplified_chinese, "").no_matches, findBarChromeFor(.simplified_chinese, "").previous_match));
    try testing.expect(!std.mem.eql(u8, findMatchChromeFor(.japanese, "").no_matches, findBarChromeFor(.japanese, "").previous_match));
    try testing.expect(!std.mem.eql(u8, findMatchChromeFor(.english, "").no_matches, findBarChromeFor(.english, "").next_match));
    try testing.expect(!std.mem.eql(u8, findMatchChromeFor(.english, "").of_fmt, findBarChromeFor(.english, "").previous_match));
    try testing.expect(!std.mem.eql(u8, findMatchChromeFor(.english, "").of_fmt, filePreviewChromeFor(.english, "").find));
    try testing.expect(!std.mem.eql(u8, findMatchChromeFor(.simplified_chinese, "").no_matches, filePreviewChromeFor(.simplified_chinese, "").previous_file_match));
    try testing.expect(!std.mem.eql(u8, findMatchChromeFor(.japanese, "").no_matches, filePreviewChromeFor(.japanese, "").previous_file_match));
    try testing.expect(!std.mem.eql(u8, findMatchChromeFor(.english, "").of_fmt, filePreviewFindMatchChromeFor(.english, "").of_line_fmt));
    try testing.expect(!std.mem.eql(u8, findMatchChromeFor(.simplified_chinese, "").of_fmt, filePreviewFindMatchChromeFor(.simplified_chinese, "").of_line_fmt));

    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    try testing.expectEqualStrings("1 of 2", formatFindMatchOf(findMatchChromeFor(.english, ""), arena, 1, 2));
    try testing.expectEqualStrings("1 / 2", formatFindMatchOf(findMatchChromeFor(.simplified_chinese, ""), arena, 1, 2));
    try testing.expectEqualStrings("3 / 5", formatFindMatchOf(findMatchChromeFor(.japanese, ""), arena, 3, 5));
    try testing.expectEqualStrings("1 / 2", formatFindMatchOf(findMatchChromeFor(.system, "zh_CN.UTF-8"), arena, 1, 2));
    try testing.expectEqualStrings("1 of 2", formatFindMatchOf(findMatchChromeFor(.english, "ja_JP.UTF-8"), arena, 1, 2));
}

test "filePreviewFindMatchChromeFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("{d} of {d}{s} · L{d}", filePreviewFindMatchChromeFor(.english, "ja").of_line_fmt);
    try testing.expectEqualStrings("invalid", filePreviewFindMatchChromeFor(.english, "ja").invalid);
    try testing.expectEqualStrings("0", filePreviewFindMatchChromeFor(.english, "ja").zero);
    try testing.expectEqualStrings("match", filePreviewFindMatchChromeFor(.english, "ja").match);
    try testing.expectEqualStrings("{d} of {d}{s} · L{d}", filePreviewFindMatchChromeFor(.english, "").of_line_fmt);
    try testing.expectEqualStrings("invalid", filePreviewFindMatchChromeFor(.english, "").invalid);
    try testing.expectEqualStrings("0", filePreviewFindMatchChromeFor(.english, "").zero);
    try testing.expectEqualStrings("match", filePreviewFindMatchChromeFor(.english, "").match);
    try testing.expectEqualStrings("{d} of {d}{s} · L{d}", filePreviewFindMatchChromeFor(.system, "").of_line_fmt);
    try testing.expectEqualStrings("invalid", filePreviewFindMatchChromeFor(.system, "").invalid);

    try testing.expectEqualStrings("{d} / {d}{s} · L{d}", filePreviewFindMatchChromeFor(.simplified_chinese, "").of_line_fmt);
    try testing.expectEqualStrings("无效", filePreviewFindMatchChromeFor(.simplified_chinese, "").invalid);
    try testing.expectEqualStrings("0", filePreviewFindMatchChromeFor(.simplified_chinese, "").zero);
    try testing.expectEqualStrings("匹配", filePreviewFindMatchChromeFor(.simplified_chinese, "").match);
    try testing.expectEqualStrings("{d} / {d}{s} · L{d}", filePreviewFindMatchChromeFor(.japanese, "").of_line_fmt);
    try testing.expectEqualStrings("無効", filePreviewFindMatchChromeFor(.japanese, "").invalid);
    try testing.expectEqualStrings("0", filePreviewFindMatchChromeFor(.japanese, "").zero);
    try testing.expectEqualStrings("一致", filePreviewFindMatchChromeFor(.japanese, "").match);

    try testing.expectEqualStrings("无效", filePreviewFindMatchChromeFor(.system, "zh_CN.UTF-8").invalid);
    try testing.expectEqualStrings("{d} / {d}{s} · L{d}", filePreviewFindMatchChromeFor(.system, "zh_CN.UTF-8").of_line_fmt);
    try testing.expectEqualStrings("無効", filePreviewFindMatchChromeFor(.system, "ja_JP.UTF-8").invalid);
    try testing.expectEqualStrings("{d} / {d}{s} · L{d}", filePreviewFindMatchChromeFor(.system, "ja_JP.UTF-8").of_line_fmt);
    try testing.expectEqualStrings("invalid", filePreviewFindMatchChromeFor(.english, "ja_JP.UTF-8").invalid);
    try testing.expectEqualStrings("{d} of {d}{s} · L{d}", filePreviewFindMatchChromeFor(.english, "ja_JP.UTF-8").of_line_fmt);
    try testing.expectEqualStrings("invalid", filePreviewFindMatchChromeFor(.english, "zh_CN.UTF-8").invalid);
    try testing.expectEqualStrings("{d} of {d}{s} · L{d}", filePreviewFindMatchChromeFor(.english, "zh_CN.UTF-8").of_line_fmt);

    try testing.expect(!std.mem.eql(u8, filePreviewFindMatchChromeFor(.english, "").of_line_fmt, findMatchChromeFor(.english, "").of_fmt));
    try testing.expect(!std.mem.eql(u8, filePreviewFindMatchChromeFor(.english, "").invalid, filePreviewChromeFor(.english, "").find));
    try testing.expect(!std.mem.eql(u8, filePreviewFindMatchChromeFor(.simplified_chinese, "").invalid, "invalid"));
    try testing.expect(!std.mem.eql(u8, filePreviewFindMatchChromeFor(.japanese, "").invalid, "invalid"));
    try testing.expect(std.mem.indexOf(u8, filePreviewFindMatchChromeFor(.simplified_chinese, "").of_line_fmt, " of ") == null);
    try testing.expect(std.mem.indexOf(u8, filePreviewFindMatchChromeFor(.japanese, "").of_line_fmt, " of ") == null);
    try testing.expect(!std.mem.eql(u8, filePreviewFindMatchChromeFor(.simplified_chinese, "").invalid, filePreviewChromeFor(.simplified_chinese, "").previous_file_match));
    try testing.expect(!std.mem.eql(u8, filePreviewFindMatchChromeFor(.japanese, "").invalid, filePreviewChromeFor(.japanese, "").previous_file_match));
    try testing.expect(!std.mem.eql(u8, filePreviewFindMatchChromeFor(.english, "").match, findMatchChromeFor(.english, "").no_matches));

    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    try testing.expectEqualStrings("1 of 2 · L1", formatFilePreviewFindMatchOf(filePreviewFindMatchChromeFor(.english, ""), arena, 1, 2, "", 1));
    try testing.expectEqualStrings("1 of 2+ · L1", formatFilePreviewFindMatchOf(filePreviewFindMatchChromeFor(.english, ""), arena, 1, 2, "+", 1));
    try testing.expectEqualStrings("2 of 2 · L2", formatFilePreviewFindMatchOf(filePreviewFindMatchChromeFor(.english, ""), arena, 2, 2, "", 2));
    try testing.expectEqualStrings("1 / 2 · L1", formatFilePreviewFindMatchOf(filePreviewFindMatchChromeFor(.simplified_chinese, ""), arena, 1, 2, "", 1));
    try testing.expectEqualStrings("1 / 2+ · L3", formatFilePreviewFindMatchOf(filePreviewFindMatchChromeFor(.simplified_chinese, ""), arena, 1, 2, "+", 3));
    try testing.expectEqualStrings("3 / 5 · L8", formatFilePreviewFindMatchOf(filePreviewFindMatchChromeFor(.japanese, ""), arena, 3, 5, "", 8));
    try testing.expectEqualStrings("1 / 2 · L1", formatFilePreviewFindMatchOf(filePreviewFindMatchChromeFor(.system, "zh_CN.UTF-8"), arena, 1, 2, "", 1));
    try testing.expectEqualStrings("1 of 2 · L1", formatFilePreviewFindMatchOf(filePreviewFindMatchChromeFor(.english, "ja_JP.UTF-8"), arena, 1, 2, "", 1));
    try testing.expect(std.mem.indexOf(u8, formatFilePreviewFindMatchOf(filePreviewFindMatchChromeFor(.simplified_chinese, ""), arena, 1, 2, "", 1), " of ") == null);
    try testing.expect(std.mem.indexOf(u8, formatFilePreviewFindMatchOf(filePreviewFindMatchChromeFor(.japanese, ""), arena, 1, 2, "", 1), " of ") == null);
}

test "headerSessionChromeFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("Copy session", headerSessionChromeFor(.english, "ja").copy_session);
    try testing.expectEqualStrings("Fork", headerSessionChromeFor(.english, "ja").fork);
    try testing.expectEqualStrings("Rewind", headerSessionChromeFor(.english, "ja").rewind);
    try testing.expectEqualStrings("Copy session", headerSessionChromeFor(.english, "").copy_session);
    try testing.expectEqualStrings("Fork", headerSessionChromeFor(.english, "").fork);
    try testing.expectEqualStrings("Rewind", headerSessionChromeFor(.english, "").rewind);
    try testing.expectEqualStrings("Copy session", headerSessionChromeFor(.system, "").copy_session);
    try testing.expectEqualStrings("Fork", headerSessionChromeFor(.system, "").fork);
    try testing.expectEqualStrings("Rewind", headerSessionChromeFor(.system, "").rewind);

    try testing.expectEqualStrings("复制会话", headerSessionChromeFor(.simplified_chinese, "").copy_session);
    try testing.expectEqualStrings("分叉", headerSessionChromeFor(.simplified_chinese, "").fork);
    try testing.expectEqualStrings("回退", headerSessionChromeFor(.simplified_chinese, "").rewind);
    try testing.expectEqualStrings("セッションをコピー", headerSessionChromeFor(.japanese, "").copy_session);
    try testing.expectEqualStrings("フォーク", headerSessionChromeFor(.japanese, "").fork);
    try testing.expectEqualStrings("巻き戻し", headerSessionChromeFor(.japanese, "").rewind);

    try testing.expectEqualStrings("复制会话", headerSessionChromeFor(.system, "zh_CN.UTF-8").copy_session);
    try testing.expectEqualStrings("分叉", headerSessionChromeFor(.system, "zh_CN.UTF-8").fork);
    try testing.expectEqualStrings("回退", headerSessionChromeFor(.system, "zh_CN.UTF-8").rewind);
    try testing.expectEqualStrings("セッションをコピー", headerSessionChromeFor(.system, "ja_JP.UTF-8").copy_session);
    try testing.expectEqualStrings("フォーク", headerSessionChromeFor(.system, "ja_JP.UTF-8").fork);
    try testing.expectEqualStrings("巻き戻し", headerSessionChromeFor(.system, "ja_JP.UTF-8").rewind);
    try testing.expectEqualStrings("Copy session", headerSessionChromeFor(.english, "ja_JP.UTF-8").copy_session);
    try testing.expectEqualStrings("Fork", headerSessionChromeFor(.english, "ja_JP.UTF-8").fork);
    try testing.expectEqualStrings("Rewind", headerSessionChromeFor(.english, "ja_JP.UTF-8").rewind);
    try testing.expectEqualStrings("Copy session", headerSessionChromeFor(.english, "zh_CN.UTF-8").copy_session);
    try testing.expectEqualStrings("Fork", headerSessionChromeFor(.english, "zh_CN.UTF-8").fork);
    try testing.expectEqualStrings("Rewind", headerSessionChromeFor(.english, "zh_CN.UTF-8").rewind);

    try testing.expect(!std.mem.eql(u8, headerSessionChromeFor(.english, "").copy_session, paletteFor(.english, "").copy_session_id));
    try testing.expect(!std.mem.eql(u8, headerSessionChromeFor(.simplified_chinese, "").copy_session, paletteFor(.simplified_chinese, "").copy_session_id));
    try testing.expect(!std.mem.eql(u8, headerSessionChromeFor(.japanese, "").copy_session, paletteFor(.japanese, "").copy_session_id));
}

test "transcriptRoleChromeFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("You said", transcriptRoleChromeFor(.english, "ja").you_said);
    try testing.expectEqualStrings("Assistant said", transcriptRoleChromeFor(.english, "ja").assistant_said);
    try testing.expectEqualStrings("You said", transcriptRoleChromeFor(.english, "").you_said);
    try testing.expectEqualStrings("Assistant said", transcriptRoleChromeFor(.english, "").assistant_said);
    try testing.expectEqualStrings("You said", transcriptRoleChromeFor(.system, "").you_said);
    try testing.expectEqualStrings("Assistant said", transcriptRoleChromeFor(.system, "").assistant_said);

    try testing.expectEqualStrings("你说", transcriptRoleChromeFor(.simplified_chinese, "").you_said);
    try testing.expectEqualStrings("助手说", transcriptRoleChromeFor(.simplified_chinese, "").assistant_said);
    try testing.expectEqualStrings("あなたが言った", transcriptRoleChromeFor(.japanese, "").you_said);
    try testing.expectEqualStrings("アシスタントが言った", transcriptRoleChromeFor(.japanese, "").assistant_said);

    try testing.expectEqualStrings("你说", transcriptRoleChromeFor(.system, "zh_CN.UTF-8").you_said);
    try testing.expectEqualStrings("助手说", transcriptRoleChromeFor(.system, "zh_CN.UTF-8").assistant_said);
    try testing.expectEqualStrings("あなたが言った", transcriptRoleChromeFor(.system, "ja_JP.UTF-8").you_said);
    try testing.expectEqualStrings("アシスタントが言った", transcriptRoleChromeFor(.system, "ja_JP.UTF-8").assistant_said);
    try testing.expectEqualStrings("You said", transcriptRoleChromeFor(.english, "ja_JP.UTF-8").you_said);
    try testing.expectEqualStrings("Assistant said", transcriptRoleChromeFor(.english, "ja_JP.UTF-8").assistant_said);
    try testing.expectEqualStrings("You said", transcriptRoleChromeFor(.english, "zh_CN.UTF-8").you_said);
    try testing.expectEqualStrings("Assistant said", transcriptRoleChromeFor(.english, "zh_CN.UTF-8").assistant_said);
}

test "transcriptTurnChromeFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("Match", transcriptTurnChromeFor(.english, "ja").match);
    try testing.expectEqualStrings("Copy", transcriptTurnChromeFor(.english, "ja").copy);
    try testing.expectEqualStrings("Fork", transcriptTurnChromeFor(.english, "ja").fork);
    try testing.expectEqualStrings("Match", transcriptTurnChromeFor(.english, "").match);
    try testing.expectEqualStrings("Copy", transcriptTurnChromeFor(.english, "").copy);
    try testing.expectEqualStrings("Fork", transcriptTurnChromeFor(.english, "").fork);
    try testing.expectEqualStrings("Match", transcriptTurnChromeFor(.system, "").match);
    try testing.expectEqualStrings("Copy", transcriptTurnChromeFor(.system, "").copy);
    try testing.expectEqualStrings("Fork", transcriptTurnChromeFor(.system, "").fork);

    try testing.expectEqualStrings("匹配", transcriptTurnChromeFor(.simplified_chinese, "").match);
    try testing.expectEqualStrings("复制", transcriptTurnChromeFor(.simplified_chinese, "").copy);
    try testing.expectEqualStrings("分叉", transcriptTurnChromeFor(.simplified_chinese, "").fork);
    try testing.expectEqualStrings("一致", transcriptTurnChromeFor(.japanese, "").match);
    try testing.expectEqualStrings("コピー", transcriptTurnChromeFor(.japanese, "").copy);
    try testing.expectEqualStrings("フォーク", transcriptTurnChromeFor(.japanese, "").fork);

    try testing.expectEqualStrings("匹配", transcriptTurnChromeFor(.system, "zh_CN.UTF-8").match);
    try testing.expectEqualStrings("复制", transcriptTurnChromeFor(.system, "zh_CN.UTF-8").copy);
    try testing.expectEqualStrings("分叉", transcriptTurnChromeFor(.system, "zh_CN.UTF-8").fork);
    try testing.expectEqualStrings("一致", transcriptTurnChromeFor(.system, "ja_JP.UTF-8").match);
    try testing.expectEqualStrings("コピー", transcriptTurnChromeFor(.system, "ja_JP.UTF-8").copy);
    try testing.expectEqualStrings("フォーク", transcriptTurnChromeFor(.system, "ja_JP.UTF-8").fork);
    try testing.expectEqualStrings("Match", transcriptTurnChromeFor(.english, "ja_JP.UTF-8").match);
    try testing.expectEqualStrings("Copy", transcriptTurnChromeFor(.english, "ja_JP.UTF-8").copy);
    try testing.expectEqualStrings("Fork", transcriptTurnChromeFor(.english, "ja_JP.UTF-8").fork);
    try testing.expectEqualStrings("Match", transcriptTurnChromeFor(.english, "zh_CN.UTF-8").match);
    try testing.expectEqualStrings("Copy", transcriptTurnChromeFor(.english, "zh_CN.UTF-8").copy);
    try testing.expectEqualStrings("Fork", transcriptTurnChromeFor(.english, "zh_CN.UTF-8").fork);

    try testing.expect(!std.mem.eql(u8, transcriptTurnChromeFor(.english, "").copy, headerSessionChromeFor(.english, "").copy_session));
    try testing.expect(!std.mem.eql(u8, transcriptTurnChromeFor(.simplified_chinese, "").copy, headerSessionChromeFor(.simplified_chinese, "").copy_session));
    try testing.expect(!std.mem.eql(u8, transcriptTurnChromeFor(.japanese, "").copy, headerSessionChromeFor(.japanese, "").copy_session));
    try testing.expect(!std.mem.eql(u8, transcriptTurnChromeFor(.english, "").copy, paletteFor(.english, "").copy_session_id));
    try testing.expect(!std.mem.eql(u8, transcriptTurnChromeFor(.simplified_chinese, "").copy, paletteFor(.simplified_chinese, "").copy_session_id));
    try testing.expect(!std.mem.eql(u8, transcriptTurnChromeFor(.japanese, "").copy, paletteFor(.japanese, "").copy_session_id));
    try testing.expect(!std.mem.eql(u8, transcriptTurnChromeFor(.english, "").match, findBarChromeFor(.english, "").previous_match));
    try testing.expect(!std.mem.eql(u8, transcriptTurnChromeFor(.simplified_chinese, "").match, findBarChromeFor(.simplified_chinese, "").previous_match));
    try testing.expect(!std.mem.eql(u8, transcriptTurnChromeFor(.japanese, "").match, findBarChromeFor(.japanese, "").previous_match));
    try testing.expect(!std.mem.eql(u8, transcriptTurnChromeFor(.english, "").match, filePreviewChromeFor(.english, "").previous_file_match));
    try testing.expect(!std.mem.eql(u8, transcriptTurnChromeFor(.simplified_chinese, "").match, filePreviewChromeFor(.simplified_chinese, "").previous_file_match));
    try testing.expect(!std.mem.eql(u8, transcriptTurnChromeFor(.japanese, "").match, filePreviewChromeFor(.japanese, "").previous_file_match));
    try testing.expect(!std.mem.eql(u8, transcriptTurnChromeFor(.english, "").copy, transcriptRoleChromeFor(.english, "").you_said));
    try testing.expect(!std.mem.eql(u8, transcriptTurnChromeFor(.simplified_chinese, "").copy, transcriptRoleChromeFor(.simplified_chinese, "").you_said));
    try testing.expect(!std.mem.eql(u8, transcriptTurnChromeFor(.japanese, "").copy, transcriptRoleChromeFor(.japanese, "").you_said));
}

test "queueChromeFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("Jump to latest", queueChromeFor(.english, "ja").jump_latest);
    try testing.expectEqualStrings("Queued", queueChromeFor(.english, "ja").queued);
    try testing.expectEqualStrings("Dismiss all", queueChromeFor(.english, "ja").dismiss_all);
    try testing.expectEqualStrings("Remove queued", queueChromeFor(.english, "ja").remove_queued);
    try testing.expectEqualStrings("Jump to latest", queueChromeFor(.english, "").jump_latest);
    try testing.expectEqualStrings("Queued", queueChromeFor(.english, "").queued);
    try testing.expectEqualStrings("Dismiss all", queueChromeFor(.english, "").dismiss_all);
    try testing.expectEqualStrings("Remove queued", queueChromeFor(.english, "").remove_queued);
    try testing.expectEqualStrings("Jump to latest", queueChromeFor(.system, "").jump_latest);
    try testing.expectEqualStrings("Queued", queueChromeFor(.system, "").queued);
    try testing.expectEqualStrings("Dismiss all", queueChromeFor(.system, "").dismiss_all);
    try testing.expectEqualStrings("Remove queued", queueChromeFor(.system, "").remove_queued);

    try testing.expectEqualStrings("跳到最新", queueChromeFor(.simplified_chinese, "").jump_latest);
    try testing.expectEqualStrings("排队中", queueChromeFor(.simplified_chinese, "").queued);
    try testing.expectEqualStrings("全部清除", queueChromeFor(.simplified_chinese, "").dismiss_all);
    try testing.expectEqualStrings("移除排队", queueChromeFor(.simplified_chinese, "").remove_queued);
    try testing.expectEqualStrings("最新へジャンプ", queueChromeFor(.japanese, "").jump_latest);
    try testing.expectEqualStrings("キュー", queueChromeFor(.japanese, "").queued);
    try testing.expectEqualStrings("すべて解除", queueChromeFor(.japanese, "").dismiss_all);
    try testing.expectEqualStrings("キューを削除", queueChromeFor(.japanese, "").remove_queued);

    try testing.expectEqualStrings("跳到最新", queueChromeFor(.system, "zh_CN.UTF-8").jump_latest);
    try testing.expectEqualStrings("排队中", queueChromeFor(.system, "zh_CN.UTF-8").queued);
    try testing.expectEqualStrings("全部清除", queueChromeFor(.system, "zh_CN.UTF-8").dismiss_all);
    try testing.expectEqualStrings("移除排队", queueChromeFor(.system, "zh_CN.UTF-8").remove_queued);
    try testing.expectEqualStrings("最新へジャンプ", queueChromeFor(.system, "ja_JP.UTF-8").jump_latest);
    try testing.expectEqualStrings("キュー", queueChromeFor(.system, "ja_JP.UTF-8").queued);
    try testing.expectEqualStrings("すべて解除", queueChromeFor(.system, "ja_JP.UTF-8").dismiss_all);
    try testing.expectEqualStrings("キューを削除", queueChromeFor(.system, "ja_JP.UTF-8").remove_queued);
    try testing.expectEqualStrings("Jump to latest", queueChromeFor(.english, "ja_JP.UTF-8").jump_latest);
    try testing.expectEqualStrings("Queued", queueChromeFor(.english, "ja_JP.UTF-8").queued);
    try testing.expectEqualStrings("Dismiss all", queueChromeFor(.english, "ja_JP.UTF-8").dismiss_all);
    try testing.expectEqualStrings("Remove queued", queueChromeFor(.english, "ja_JP.UTF-8").remove_queued);
    try testing.expectEqualStrings("Jump to latest", queueChromeFor(.english, "zh_CN.UTF-8").jump_latest);
    try testing.expectEqualStrings("Queued", queueChromeFor(.english, "zh_CN.UTF-8").queued);
    try testing.expectEqualStrings("Dismiss all", queueChromeFor(.english, "zh_CN.UTF-8").dismiss_all);
    try testing.expectEqualStrings("Remove queued", queueChromeFor(.english, "zh_CN.UTF-8").remove_queued);

    try testing.expect(!std.mem.eql(u8, queueChromeFor(.english, "").dismiss_all, environmentChromeFor(.english, "").dismiss_all_settled));
    try testing.expect(!std.mem.eql(u8, queueChromeFor(.simplified_chinese, "").dismiss_all, environmentChromeFor(.simplified_chinese, "").dismiss_all_settled));
    try testing.expect(!std.mem.eql(u8, queueChromeFor(.japanese, "").dismiss_all, environmentChromeFor(.japanese, "").dismiss_all_settled));
    try testing.expect(!std.mem.eql(u8, queueChromeFor(.english, "").dismiss_all, backgroundChromeFor(.english, "").daemon_dismiss));
    try testing.expect(!std.mem.eql(u8, queueChromeFor(.simplified_chinese, "").dismiss_all, backgroundChromeFor(.simplified_chinese, "").daemon_dismiss));
    try testing.expect(!std.mem.eql(u8, queueChromeFor(.japanese, "").dismiss_all, backgroundChromeFor(.japanese, "").daemon_dismiss));
    try testing.expect(!std.mem.eql(u8, queueChromeFor(.english, "").dismiss_all, backgroundChromeFor(.english, "").monitor_dismiss));
    try testing.expect(!std.mem.eql(u8, queueChromeFor(.simplified_chinese, "").dismiss_all, backgroundChromeFor(.simplified_chinese, "").monitor_dismiss));
    try testing.expect(!std.mem.eql(u8, queueChromeFor(.japanese, "").dismiss_all, backgroundChromeFor(.japanese, "").monitor_dismiss));
    try testing.expect(!std.mem.eql(u8, queueChromeFor(.english, "").dismiss_all, backgroundChromeFor(.english, "").subagent_dismiss));
    try testing.expect(!std.mem.eql(u8, queueChromeFor(.simplified_chinese, "").dismiss_all, backgroundChromeFor(.simplified_chinese, "").subagent_dismiss));
    try testing.expect(!std.mem.eql(u8, queueChromeFor(.japanese, "").dismiss_all, backgroundChromeFor(.japanese, "").subagent_dismiss));
    try testing.expect(!std.mem.eql(u8, queueChromeFor(.english, "").jump_latest, transcriptTurnChromeFor(.english, "").match));
    try testing.expect(!std.mem.eql(u8, queueChromeFor(.simplified_chinese, "").jump_latest, transcriptTurnChromeFor(.simplified_chinese, "").match));
    try testing.expect(!std.mem.eql(u8, queueChromeFor(.japanese, "").jump_latest, transcriptTurnChromeFor(.japanese, "").match));
    try testing.expect(!std.mem.eql(u8, queueChromeFor(.english, "").queued, headerSessionChromeFor(.english, "").fork));
    try testing.expect(!std.mem.eql(u8, queueChromeFor(.simplified_chinese, "").queued, headerSessionChromeFor(.simplified_chinese, "").fork));
    try testing.expect(!std.mem.eql(u8, queueChromeFor(.japanese, "").queued, headerSessionChromeFor(.japanese, "").fork));
}

test "browserAddressChromeFor english default; zh and ja chrome; latin placeholder; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("Address", browserAddressChromeFor(.english, "ja").address);
    try testing.expectEqualStrings("Address", browserAddressChromeFor(.english, "").address);
    try testing.expectEqualStrings("Address", browserAddressChromeFor(.system, "").address);
    try testing.expectEqualStrings("https://example.com", browserAddressChromeFor(.english, "").placeholder);
    try testing.expectEqualStrings("https://example.com", browserAddressChromeFor(.system, "").placeholder);

    try testing.expectEqualStrings("地址", browserAddressChromeFor(.simplified_chinese, "").address);
    try testing.expectEqualStrings("https://example.com", browserAddressChromeFor(.simplified_chinese, "").placeholder);

    try testing.expectEqualStrings("アドレス", browserAddressChromeFor(.japanese, "").address);
    try testing.expectEqualStrings("https://example.com", browserAddressChromeFor(.japanese, "").placeholder);

    try testing.expectEqualStrings("地址", browserAddressChromeFor(.system, "zh_CN.UTF-8").address);
    try testing.expectEqualStrings("https://example.com", browserAddressChromeFor(.system, "zh_CN.UTF-8").placeholder);
    try testing.expectEqualStrings("アドレス", browserAddressChromeFor(.system, "ja_JP.UTF-8").address);
    try testing.expectEqualStrings("https://example.com", browserAddressChromeFor(.system, "ja_JP.UTF-8").placeholder);
    try testing.expectEqualStrings("Address", browserAddressChromeFor(.english, "ja_JP.UTF-8").address);
    try testing.expectEqualStrings("Address", browserAddressChromeFor(.english, "zh_CN.UTF-8").address);
    try testing.expectEqualStrings("https://example.com", browserAddressChromeFor(.english, "ja_JP.UTF-8").placeholder);
    try testing.expectEqualStrings("https://example.com", browserAddressChromeFor(.english, "zh_CN.UTF-8").placeholder);
    try testing.expectEqualStrings("https://example.com", browserAddressChromeFor(.simplified_chinese, "ja_JP.UTF-8").placeholder);
    try testing.expectEqualStrings("https://example.com", browserAddressChromeFor(.japanese, "zh_CN.UTF-8").placeholder);
}

test "browserToolbarChromeFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("Back", browserToolbarChromeFor(.english, "ja").back);
    try testing.expectEqualStrings("Back", browserToolbarChromeFor(.english, "").back);
    try testing.expectEqualStrings("Back", browserToolbarChromeFor(.system, "").back);
    try testing.expectEqualStrings("Forward", browserToolbarChromeFor(.english, "").forward);
    try testing.expectEqualStrings("Reload", browserToolbarChromeFor(.english, "").reload);
    try testing.expectEqualStrings("Hard Reload", browserToolbarChromeFor(.english, "").hard_reload);
    try testing.expectEqualStrings("Navigate", browserToolbarChromeFor(.english, "").navigate);
    try testing.expectEqualStrings("Secure", browserToolbarChromeFor(.english, "").secure);
    try testing.expectEqualStrings("Not secure", browserToolbarChromeFor(.system, "").not_secure);

    try testing.expectEqualStrings("返回", browserToolbarChromeFor(.simplified_chinese, "").back);
    try testing.expectEqualStrings("前进", browserToolbarChromeFor(.simplified_chinese, "").forward);
    try testing.expectEqualStrings("重新加载", browserToolbarChromeFor(.simplified_chinese, "").reload);
    try testing.expectEqualStrings("强制重新加载", browserToolbarChromeFor(.simplified_chinese, "").hard_reload);
    try testing.expectEqualStrings("转到", browserToolbarChromeFor(.simplified_chinese, "").navigate);
    try testing.expectEqualStrings("安全", browserToolbarChromeFor(.simplified_chinese, "").secure);
    try testing.expectEqualStrings("不安全", browserToolbarChromeFor(.simplified_chinese, "").not_secure);

    try testing.expectEqualStrings("戻る", browserToolbarChromeFor(.japanese, "").back);
    try testing.expectEqualStrings("進む", browserToolbarChromeFor(.japanese, "").forward);
    try testing.expectEqualStrings("再読み込み", browserToolbarChromeFor(.japanese, "").reload);
    try testing.expectEqualStrings("強制再読み込み", browserToolbarChromeFor(.japanese, "").hard_reload);
    try testing.expectEqualStrings("移動", browserToolbarChromeFor(.japanese, "").navigate);
    try testing.expectEqualStrings("安全", browserToolbarChromeFor(.japanese, "").secure);
    try testing.expectEqualStrings("保護されていません", browserToolbarChromeFor(.japanese, "").not_secure);

    try testing.expectEqualStrings("返回", browserToolbarChromeFor(.system, "zh_CN.UTF-8").back);
    try testing.expectEqualStrings("转到", browserToolbarChromeFor(.system, "zh_CN.UTF-8").navigate);
    try testing.expectEqualStrings("不安全", browserToolbarChromeFor(.system, "zh_CN.UTF-8").not_secure);
    try testing.expectEqualStrings("戻る", browserToolbarChromeFor(.system, "ja_JP.UTF-8").back);
    try testing.expectEqualStrings("移動", browserToolbarChromeFor(.system, "ja_JP.UTF-8").navigate);
    try testing.expectEqualStrings("保護されていません", browserToolbarChromeFor(.system, "ja_JP.UTF-8").not_secure);
    try testing.expectEqualStrings("Back", browserToolbarChromeFor(.english, "ja_JP.UTF-8").back);
    try testing.expectEqualStrings("Navigate", browserToolbarChromeFor(.english, "zh_CN.UTF-8").navigate);
    try testing.expectEqualStrings("Not secure", browserToolbarChromeFor(.english, "ja_JP.UTF-8").not_secure);
    try testing.expectEqualStrings("Reload", browserToolbarChromeFor(.english, "zh_CN.UTF-8").reload);
    try testing.expectEqualStrings("Hard Reload", browserToolbarChromeFor(.english, "zh_CN.UTF-8").hard_reload);
    try testing.expectEqualStrings("Forward", browserToolbarChromeFor(.english, "ja_JP.UTF-8").forward);
    try testing.expectEqualStrings("Secure", browserToolbarChromeFor(.english, "zh_CN.UTF-8").secure);
    try testing.expect(!std.mem.eql(u8, browserToolbarChromeFor(.english, "").reload, browserToolbarChromeFor(.english, "").hard_reload));
    try testing.expect(!std.mem.eql(u8, browserToolbarChromeFor(.simplified_chinese, "").reload, browserToolbarChromeFor(.simplified_chinese, "").hard_reload));
    try testing.expect(!std.mem.eql(u8, browserToolbarChromeFor(.japanese, "").reload, browserToolbarChromeFor(.japanese, "").hard_reload));
}

test "browserStartIconChromeFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("Browse", browserStartIconChromeFor(.english, "ja").browse);
    try testing.expectEqualStrings("Browse", browserStartIconChromeFor(.english, "").browse);
    try testing.expectEqualStrings("Browse", browserStartIconChromeFor(.system, "").browse);

    try testing.expectEqualStrings("浏览", browserStartIconChromeFor(.simplified_chinese, "").browse);
    try testing.expectEqualStrings("閲覧", browserStartIconChromeFor(.japanese, "").browse);

    try testing.expectEqualStrings("浏览", browserStartIconChromeFor(.system, "zh_CN.UTF-8").browse);
    try testing.expectEqualStrings("閲覧", browserStartIconChromeFor(.system, "ja_JP.UTF-8").browse);
    try testing.expectEqualStrings("Browse", browserStartIconChromeFor(.english, "ja_JP.UTF-8").browse);
    try testing.expectEqualStrings("Browse", browserStartIconChromeFor(.english, "zh_CN.UTF-8").browse);

    try testing.expect(!std.mem.eql(u8, browserStartIconChromeFor(.english, "").browse, rightPanelChromeFor(.english, "").browse_the_web));
    try testing.expect(!std.mem.eql(u8, browserStartIconChromeFor(.simplified_chinese, "").browse, rightPanelChromeFor(.simplified_chinese, "").browse_the_web));
    try testing.expect(!std.mem.eql(u8, browserStartIconChromeFor(.japanese, "").browse, rightPanelChromeFor(.japanese, "").browse_the_web));
    try testing.expect(!std.mem.eql(u8, browserStartIconChromeFor(.english, "").browse, browserToolbarChromeFor(.english, "").navigate));
    try testing.expect(!std.mem.eql(u8, browserStartIconChromeFor(.english, "").browse, browserAddressChromeFor(.english, "").address));
}

test "sidebarHistoryChromeFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("Back", sidebarHistoryChromeFor(.english, "ja").back);
    try testing.expectEqualStrings("Back", sidebarHistoryChromeFor(.english, "").back);
    try testing.expectEqualStrings("Back", sidebarHistoryChromeFor(.system, "").back);
    try testing.expectEqualStrings("Forward", sidebarHistoryChromeFor(.english, "").forward);

    try testing.expectEqualStrings("返回", sidebarHistoryChromeFor(.simplified_chinese, "").back);
    try testing.expectEqualStrings("前进", sidebarHistoryChromeFor(.simplified_chinese, "").forward);

    try testing.expectEqualStrings("戻る", sidebarHistoryChromeFor(.japanese, "").back);
    try testing.expectEqualStrings("進む", sidebarHistoryChromeFor(.japanese, "").forward);

    try testing.expectEqualStrings("返回", sidebarHistoryChromeFor(.system, "zh_CN.UTF-8").back);
    try testing.expectEqualStrings("前进", sidebarHistoryChromeFor(.system, "zh_CN.UTF-8").forward);
    try testing.expectEqualStrings("戻る", sidebarHistoryChromeFor(.system, "ja_JP.UTF-8").back);
    try testing.expectEqualStrings("進む", sidebarHistoryChromeFor(.system, "ja_JP.UTF-8").forward);
    try testing.expectEqualStrings("Back", sidebarHistoryChromeFor(.english, "ja_JP.UTF-8").back);
    try testing.expectEqualStrings("Forward", sidebarHistoryChromeFor(.english, "zh_CN.UTF-8").forward);
    try testing.expectEqualStrings("Back", sidebarHistoryChromeFor(.english, "zh_CN.UTF-8").back);
    try testing.expectEqualStrings("Forward", sidebarHistoryChromeFor(.english, "ja_JP.UTF-8").forward);
}

test "sessionChipsChromeFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("New", sessionChipsChromeFor(.english, "ja").new);
    try testing.expectEqualStrings("New", sessionChipsChromeFor(.english, "").new);
    try testing.expectEqualStrings("New", sessionChipsChromeFor(.system, "").new);
    try testing.expectEqualStrings("Close", sessionChipsChromeFor(.english, "").close);
    try testing.expectEqualStrings("Close", sessionChipsChromeFor(.system, "").close);
    try testing.expectEqualStrings(filePreviewChromeFor(.english, "").close, sessionChipsChromeFor(.english, "").close);

    try testing.expectEqualStrings("新建", sessionChipsChromeFor(.simplified_chinese, "").new);
    try testing.expectEqualStrings("关闭", sessionChipsChromeFor(.simplified_chinese, "").close);
    try testing.expectEqualStrings(filePreviewChromeFor(.simplified_chinese, "").close, sessionChipsChromeFor(.simplified_chinese, "").close);

    try testing.expectEqualStrings("新規", sessionChipsChromeFor(.japanese, "").new);
    try testing.expectEqualStrings("閉じる", sessionChipsChromeFor(.japanese, "").close);
    try testing.expectEqualStrings(filePreviewChromeFor(.japanese, "").close, sessionChipsChromeFor(.japanese, "").close);

    try testing.expectEqualStrings("新建", sessionChipsChromeFor(.system, "zh_CN.UTF-8").new);
    try testing.expectEqualStrings("关闭", sessionChipsChromeFor(.system, "zh_CN.UTF-8").close);
    try testing.expectEqualStrings("新規", sessionChipsChromeFor(.system, "ja_JP.UTF-8").new);
    try testing.expectEqualStrings("閉じる", sessionChipsChromeFor(.system, "ja_JP.UTF-8").close);
    try testing.expectEqualStrings("New", sessionChipsChromeFor(.english, "ja_JP.UTF-8").new);
    try testing.expectEqualStrings("Close", sessionChipsChromeFor(.english, "zh_CN.UTF-8").close);
    try testing.expectEqualStrings("New", sessionChipsChromeFor(.english, "zh_CN.UTF-8").new);
    try testing.expectEqualStrings("Close", sessionChipsChromeFor(.english, "ja_JP.UTF-8").close);
}

test "terminalRestartChromeFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("Restart", terminalRestartChromeFor(.english, "ja").restart);
    try testing.expectEqualStrings("Restart", terminalRestartChromeFor(.english, "").restart);
    try testing.expectEqualStrings("Restart", terminalRestartChromeFor(.system, "").restart);

    try testing.expectEqualStrings("重启", terminalRestartChromeFor(.simplified_chinese, "").restart);
    try testing.expectEqualStrings("再起動", terminalRestartChromeFor(.japanese, "").restart);

    try testing.expectEqualStrings("重启", terminalRestartChromeFor(.system, "zh_CN.UTF-8").restart);
    try testing.expectEqualStrings("再起動", terminalRestartChromeFor(.system, "ja_JP.UTF-8").restart);
    try testing.expectEqualStrings("Restart", terminalRestartChromeFor(.english, "ja_JP.UTF-8").restart);
    try testing.expectEqualStrings("Restart", terminalRestartChromeFor(.english, "zh_CN.UTF-8").restart);
}

test "computerUseChromeFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("Computer Use", computerUseChromeFor(.english, "ja").title);
    try testing.expectEqualStrings("Computer Use", computerUseChromeFor(.english, "").title);
    try testing.expectEqualStrings("Computer Use", computerUseChromeFor(.system, "").title);
    try testing.expectEqualStrings("Availability", computerUseChromeFor(.english, "").availability);
    try testing.expectEqualStrings("Unavailable", computerUseChromeFor(.english, "").unavailable);
    try testing.expectEqualStrings(
        "Native has no Screen Recording or Accessibility APIs this cut. Waku's helper is macOS-only.",
        computerUseChromeFor(.english, "").unavailable_caption,
    );
    try testing.expectEqualStrings("Enable", computerUseChromeFor(.english, "").enable);
    try testing.expectEqualStrings("Off", computerUseChromeFor(.english, "").off);
    try testing.expectEqualStrings("Always-allowed apps", computerUseChromeFor(.english, "").always_allowed_apps);
    try testing.expectEqualStrings("No always-allowed apps", computerUseChromeFor(.english, "").no_always_allowed_apps);
    try testing.expectEqualStrings(chromeFor(.english, "").computer_use, computerUseChromeFor(.english, "").title);

    try testing.expectEqualStrings("电脑使用", computerUseChromeFor(.simplified_chinese, "").title);
    try testing.expectEqualStrings("可用性", computerUseChromeFor(.simplified_chinese, "").availability);
    try testing.expectEqualStrings("不可用", computerUseChromeFor(.simplified_chinese, "").unavailable);
    try testing.expectEqualStrings(
        "Native 本轮没有屏幕录制或辅助功能 API。Waku 的助手仅限 macOS。",
        computerUseChromeFor(.simplified_chinese, "").unavailable_caption,
    );
    try testing.expectEqualStrings("启用", computerUseChromeFor(.simplified_chinese, "").enable);
    try testing.expectEqualStrings("关", computerUseChromeFor(.simplified_chinese, "").off);
    try testing.expectEqualStrings("始终允许的应用", computerUseChromeFor(.simplified_chinese, "").always_allowed_apps);
    try testing.expectEqualStrings("没有始终允许的应用", computerUseChromeFor(.simplified_chinese, "").no_always_allowed_apps);
    try testing.expectEqualStrings(chromeFor(.simplified_chinese, "").computer_use, computerUseChromeFor(.simplified_chinese, "").title);

    try testing.expectEqualStrings("コンピュータ使用", computerUseChromeFor(.japanese, "").title);
    try testing.expectEqualStrings("可用性", computerUseChromeFor(.japanese, "").availability);
    try testing.expectEqualStrings("利用不可", computerUseChromeFor(.japanese, "").unavailable);
    try testing.expectEqualStrings(
        "Native には現状、画面収録やアクセシビリティの API がありません。Waku のヘルパーは macOS 専用です。",
        computerUseChromeFor(.japanese, "").unavailable_caption,
    );
    try testing.expectEqualStrings("有効", computerUseChromeFor(.japanese, "").enable);
    try testing.expectEqualStrings("オフ", computerUseChromeFor(.japanese, "").off);
    try testing.expectEqualStrings("常に許可するアプリ", computerUseChromeFor(.japanese, "").always_allowed_apps);
    try testing.expectEqualStrings("常に許可するアプリはありません", computerUseChromeFor(.japanese, "").no_always_allowed_apps);
    try testing.expectEqualStrings(chromeFor(.japanese, "").computer_use, computerUseChromeFor(.japanese, "").title);

    try testing.expectEqualStrings("电脑使用", computerUseChromeFor(.system, "zh_CN.UTF-8").title);
    try testing.expectEqualStrings("不可用", computerUseChromeFor(.system, "zh_CN.UTF-8").unavailable);
    try testing.expectEqualStrings("コンピュータ使用", computerUseChromeFor(.system, "ja_JP.UTF-8").title);
    try testing.expectEqualStrings("利用不可", computerUseChromeFor(.system, "ja_JP.UTF-8").unavailable);
    try testing.expectEqualStrings("Computer Use", computerUseChromeFor(.english, "ja_JP.UTF-8").title);
    try testing.expectEqualStrings("Unavailable", computerUseChromeFor(.english, "zh_CN.UTF-8").unavailable);
    try testing.expectEqualStrings("Off", computerUseChromeFor(.english, "zh_CN.UTF-8").off);
}

test "usageViewChromeFor english default; zh and ja chrome; latin day chips; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("Daily", usageViewChromeFor(.english, "ja").daily);
    try testing.expectEqualStrings("Daily", usageViewChromeFor(.english, "").daily);
    try testing.expectEqualStrings("Daily", usageViewChromeFor(.system, "").daily);
    try testing.expectEqualStrings("Monthly", usageViewChromeFor(.english, "").monthly);
    try testing.expectEqualStrings("Projects", usageViewChromeFor(.english, "").projects);
    try testing.expectEqualStrings("7d", usageViewChromeFor(.english, "").window_7d);
    try testing.expectEqualStrings("30d", usageViewChromeFor(.english, "").window_30d);
    try testing.expectEqualStrings("90d", usageViewChromeFor(.english, "").window_90d);
    try testing.expectEqualStrings("This month", usageViewChromeFor(.english, "").this_month);
    try testing.expectEqualStrings("Last month", usageViewChromeFor(.english, "").last_month);
    try testing.expectEqualStrings("Cost", usageViewChromeFor(.english, "").cost);
    try testing.expectEqualStrings("Tokens", usageViewChromeFor(.english, "").tokens);
    try testing.expectEqualStrings("Model", usageViewChromeFor(.english, "").model);
    try testing.expectEqualStrings("Days", usageViewChromeFor(.english, "").days);

    try testing.expectEqualStrings("每日", usageViewChromeFor(.simplified_chinese, "").daily);
    try testing.expectEqualStrings("每月", usageViewChromeFor(.simplified_chinese, "").monthly);
    try testing.expectEqualStrings("项目", usageViewChromeFor(.simplified_chinese, "").projects);
    try testing.expectEqualStrings("7d", usageViewChromeFor(.simplified_chinese, "").window_7d);
    try testing.expectEqualStrings("30d", usageViewChromeFor(.simplified_chinese, "").window_30d);
    try testing.expectEqualStrings("90d", usageViewChromeFor(.simplified_chinese, "").window_90d);
    try testing.expectEqualStrings("本月", usageViewChromeFor(.simplified_chinese, "").this_month);
    try testing.expectEqualStrings("上月", usageViewChromeFor(.simplified_chinese, "").last_month);
    try testing.expectEqualStrings("费用", usageViewChromeFor(.simplified_chinese, "").cost);
    try testing.expectEqualStrings("Token", usageViewChromeFor(.simplified_chinese, "").tokens);
    try testing.expectEqualStrings("模型", usageViewChromeFor(.simplified_chinese, "").model);
    try testing.expectEqualStrings("按日", usageViewChromeFor(.simplified_chinese, "").days);

    try testing.expectEqualStrings("日次", usageViewChromeFor(.japanese, "").daily);
    try testing.expectEqualStrings("月次", usageViewChromeFor(.japanese, "").monthly);
    try testing.expectEqualStrings("プロジェクト", usageViewChromeFor(.japanese, "").projects);
    try testing.expectEqualStrings("7d", usageViewChromeFor(.japanese, "").window_7d);
    try testing.expectEqualStrings("30d", usageViewChromeFor(.japanese, "").window_30d);
    try testing.expectEqualStrings("90d", usageViewChromeFor(.japanese, "").window_90d);
    try testing.expectEqualStrings("今月", usageViewChromeFor(.japanese, "").this_month);
    try testing.expectEqualStrings("先月", usageViewChromeFor(.japanese, "").last_month);
    try testing.expectEqualStrings("コスト", usageViewChromeFor(.japanese, "").cost);
    try testing.expectEqualStrings("トークン", usageViewChromeFor(.japanese, "").tokens);
    try testing.expectEqualStrings("モデル", usageViewChromeFor(.japanese, "").model);
    try testing.expectEqualStrings("日別", usageViewChromeFor(.japanese, "").days);

    try testing.expectEqualStrings("每日", usageViewChromeFor(.system, "zh_CN.UTF-8").daily);
    try testing.expectEqualStrings("上月", usageViewChromeFor(.system, "zh_CN.UTF-8").last_month);
    try testing.expectEqualStrings("费用", usageViewChromeFor(.system, "zh_CN.UTF-8").cost);
    try testing.expectEqualStrings("按日", usageViewChromeFor(.system, "zh_CN.UTF-8").days);
    try testing.expectEqualStrings("日次", usageViewChromeFor(.system, "ja_JP.UTF-8").daily);
    try testing.expectEqualStrings("先月", usageViewChromeFor(.system, "ja_JP.UTF-8").last_month);
    try testing.expectEqualStrings("コスト", usageViewChromeFor(.system, "ja_JP.UTF-8").cost);
    try testing.expectEqualStrings("日別", usageViewChromeFor(.system, "ja_JP.UTF-8").days);
    try testing.expectEqualStrings("Daily", usageViewChromeFor(.english, "ja_JP.UTF-8").daily);
    try testing.expectEqualStrings("Projects", usageViewChromeFor(.english, "zh_CN.UTF-8").projects);
    try testing.expectEqualStrings("This month", usageViewChromeFor(.english, "zh_CN.UTF-8").this_month);
    try testing.expectEqualStrings("Cost", usageViewChromeFor(.english, "ja_JP.UTF-8").cost);
    try testing.expectEqualStrings("Tokens", usageViewChromeFor(.english, "zh_CN.UTF-8").tokens);
    try testing.expectEqualStrings("Model", usageViewChromeFor(.english, "zh_CN.UTF-8").model);
    try testing.expectEqualStrings("Days", usageViewChromeFor(.english, "ja_JP.UTF-8").days);
    try testing.expectEqualStrings("7d", usageViewChromeFor(.system, "zh_CN.UTF-8").window_7d);
    try testing.expectEqualStrings("30d", usageViewChromeFor(.system, "ja_JP.UTF-8").window_30d);
    try testing.expectEqualStrings("90d", usageViewChromeFor(.japanese, "zh_CN.UTF-8").window_90d);
}

test "settingsRefreshChromeFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("Refresh", settingsRefreshChromeFor(.english, "ja").refresh);
    try testing.expectEqualStrings("Refresh", settingsRefreshChromeFor(.english, "").refresh);
    try testing.expectEqualStrings("Refresh", settingsRefreshChromeFor(.system, "").refresh);

    try testing.expectEqualStrings("刷新", settingsRefreshChromeFor(.simplified_chinese, "").refresh);
    try testing.expectEqualStrings("更新", settingsRefreshChromeFor(.japanese, "").refresh);

    try testing.expectEqualStrings("刷新", settingsRefreshChromeFor(.system, "zh_CN.UTF-8").refresh);
    try testing.expectEqualStrings("更新", settingsRefreshChromeFor(.system, "ja_JP.UTF-8").refresh);
    try testing.expectEqualStrings("Refresh", settingsRefreshChromeFor(.english, "ja_JP.UTF-8").refresh);
    try testing.expectEqualStrings("Refresh", settingsRefreshChromeFor(.english, "zh_CN.UTF-8").refresh);
}

test "goalPlanRefreshChromeFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("Refresh goal", goalPlanRefreshChromeFor(.english, "ja").refresh_goal);
    try testing.expectEqualStrings("Refresh", goalPlanRefreshChromeFor(.english, "ja").plan_refresh);
    try testing.expectEqualStrings("Refresh goal", goalPlanRefreshChromeFor(.english, "").refresh_goal);
    try testing.expectEqualStrings("Refresh", goalPlanRefreshChromeFor(.english, "").plan_refresh);
    try testing.expectEqualStrings("Refresh goal", goalPlanRefreshChromeFor(.system, "").refresh_goal);
    try testing.expectEqualStrings("Refresh", goalPlanRefreshChromeFor(.system, "").plan_refresh);

    try testing.expectEqualStrings("刷新目标", goalPlanRefreshChromeFor(.simplified_chinese, "").refresh_goal);
    try testing.expectEqualStrings("刷新", goalPlanRefreshChromeFor(.simplified_chinese, "").plan_refresh);
    try testing.expectEqualStrings("目標を更新", goalPlanRefreshChromeFor(.japanese, "").refresh_goal);
    try testing.expectEqualStrings("更新", goalPlanRefreshChromeFor(.japanese, "").plan_refresh);

    try testing.expectEqualStrings("刷新目标", goalPlanRefreshChromeFor(.system, "zh_CN.UTF-8").refresh_goal);
    try testing.expectEqualStrings("刷新", goalPlanRefreshChromeFor(.system, "zh_CN.UTF-8").plan_refresh);
    try testing.expectEqualStrings("目標を更新", goalPlanRefreshChromeFor(.system, "ja_JP.UTF-8").refresh_goal);
    try testing.expectEqualStrings("更新", goalPlanRefreshChromeFor(.system, "ja_JP.UTF-8").plan_refresh);
    try testing.expectEqualStrings("Refresh goal", goalPlanRefreshChromeFor(.english, "ja_JP.UTF-8").refresh_goal);
    try testing.expectEqualStrings("Refresh", goalPlanRefreshChromeFor(.english, "ja_JP.UTF-8").plan_refresh);
    try testing.expectEqualStrings("Refresh goal", goalPlanRefreshChromeFor(.english, "zh_CN.UTF-8").refresh_goal);
    try testing.expectEqualStrings("Refresh", goalPlanRefreshChromeFor(.english, "zh_CN.UTF-8").plan_refresh);
}

test "goalActionChromeFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("Set goal", goalActionChromeFor(.english, "ja").set_goal);
    try testing.expectEqualStrings("Clear goal", goalActionChromeFor(.english, "ja").clear_goal);
    try testing.expectEqualStrings("Set goal", goalActionChromeFor(.english, "").set_goal);
    try testing.expectEqualStrings("Clear goal", goalActionChromeFor(.english, "").clear_goal);
    try testing.expectEqualStrings("Set goal", goalActionChromeFor(.system, "").set_goal);
    try testing.expectEqualStrings("Clear goal", goalActionChromeFor(.system, "").clear_goal);

    try testing.expectEqualStrings("设置目标", goalActionChromeFor(.simplified_chinese, "").set_goal);
    try testing.expectEqualStrings("清除目标", goalActionChromeFor(.simplified_chinese, "").clear_goal);
    try testing.expectEqualStrings("目標を設定", goalActionChromeFor(.japanese, "").set_goal);
    try testing.expectEqualStrings("目標をクリア", goalActionChromeFor(.japanese, "").clear_goal);

    try testing.expectEqualStrings("设置目标", goalActionChromeFor(.system, "zh_CN.UTF-8").set_goal);
    try testing.expectEqualStrings("清除目标", goalActionChromeFor(.system, "zh_CN.UTF-8").clear_goal);
    try testing.expectEqualStrings("目標を設定", goalActionChromeFor(.system, "ja_JP.UTF-8").set_goal);
    try testing.expectEqualStrings("目標をクリア", goalActionChromeFor(.system, "ja_JP.UTF-8").clear_goal);
    try testing.expectEqualStrings("Set goal", goalActionChromeFor(.english, "ja_JP.UTF-8").set_goal);
    try testing.expectEqualStrings("Clear goal", goalActionChromeFor(.english, "ja_JP.UTF-8").clear_goal);
    try testing.expectEqualStrings("Set goal", goalActionChromeFor(.english, "zh_CN.UTF-8").set_goal);
    try testing.expectEqualStrings("Clear goal", goalActionChromeFor(.english, "zh_CN.UTF-8").clear_goal);
}

test "goalEmptyChromeFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("No goal", goalEmptyChromeFor(.english, "ja").no_goal);
    try testing.expectEqualStrings("No goal", goalEmptyChromeFor(.english, "").no_goal);
    try testing.expectEqualStrings("No goal", goalEmptyChromeFor(.system, "").no_goal);

    try testing.expectEqualStrings("无目标", goalEmptyChromeFor(.simplified_chinese, "").no_goal);
    try testing.expectEqualStrings("目標なし", goalEmptyChromeFor(.japanese, "").no_goal);

    try testing.expectEqualStrings("无目标", goalEmptyChromeFor(.system, "zh_CN.UTF-8").no_goal);
    try testing.expectEqualStrings("目標なし", goalEmptyChromeFor(.system, "ja_JP.UTF-8").no_goal);
    try testing.expectEqualStrings("No goal", goalEmptyChromeFor(.english, "ja_JP.UTF-8").no_goal);
    try testing.expectEqualStrings("No goal", goalEmptyChromeFor(.english, "zh_CN.UTF-8").no_goal);
}

test "goalStatusChromeFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("Active", goalStatusChromeFor(.english, "ja").active);
    try testing.expectEqualStrings("Paused", goalStatusChromeFor(.english, "ja").paused);
    try testing.expectEqualStrings("Active", goalStatusChromeFor(.english, "").active);
    try testing.expectEqualStrings("Paused", goalStatusChromeFor(.english, "").paused);
    try testing.expectEqualStrings("Blocked", goalStatusChromeFor(.english, "").blocked);
    try testing.expectEqualStrings("Usage limited", goalStatusChromeFor(.english, "").usage_limited);
    try testing.expectEqualStrings("Budget limited", goalStatusChromeFor(.english, "").budget_limited);
    try testing.expectEqualStrings("Complete", goalStatusChromeFor(.english, "").complete);
    try testing.expectEqualStrings("Active", goalStatusChromeFor(.system, "").active);
    try testing.expectEqualStrings("Paused", goalStatusChromeFor(.system, "").paused);
    try testing.expectEqualStrings("Active", goalStatusChromeFor(.english, "").labelForId("active"));
    try testing.expectEqualStrings("Paused", goalStatusChromeFor(.english, "").labelForId("paused"));
    try testing.expectEqualStrings("Blocked", goalStatusChromeFor(.english, "").labelForId("blocked"));
    try testing.expectEqualStrings("Usage limited", goalStatusChromeFor(.english, "").labelForId("usageLimited"));
    try testing.expectEqualStrings("Budget limited", goalStatusChromeFor(.english, "").labelForId("budgetLimited"));
    try testing.expectEqualStrings("Complete", goalStatusChromeFor(.english, "").labelForId("complete"));
    try testing.expectEqualStrings("Active", goalStatusChromeFor(.english, "").labelForId(""));
    try testing.expectEqualStrings("Active", goalStatusChromeFor(.english, "").labelForId("nope"));

    try testing.expectEqualStrings("进行中", goalStatusChromeFor(.simplified_chinese, "").active);
    try testing.expectEqualStrings("已暂停", goalStatusChromeFor(.simplified_chinese, "").paused);
    try testing.expectEqualStrings("已阻塞", goalStatusChromeFor(.simplified_chinese, "").blocked);
    try testing.expectEqualStrings("用量受限", goalStatusChromeFor(.simplified_chinese, "").usage_limited);
    try testing.expectEqualStrings("预算受限", goalStatusChromeFor(.simplified_chinese, "").budget_limited);
    try testing.expectEqualStrings("已完成", goalStatusChromeFor(.simplified_chinese, "").complete);
    try testing.expectEqualStrings("进行中", goalStatusChromeFor(.simplified_chinese, "").labelForId("active"));
    try testing.expectEqualStrings("用量受限", goalStatusChromeFor(.simplified_chinese, "").labelForId("usageLimited"));
    try testing.expectEqualStrings("预算受限", goalStatusChromeFor(.simplified_chinese, "").labelForId("budgetLimited"));
    try testing.expectEqualStrings("進行中", goalStatusChromeFor(.japanese, "").active);
    try testing.expectEqualStrings("一時停止", goalStatusChromeFor(.japanese, "").paused);
    try testing.expectEqualStrings("ブロック中", goalStatusChromeFor(.japanese, "").blocked);
    try testing.expectEqualStrings("使用量制限", goalStatusChromeFor(.japanese, "").usage_limited);
    try testing.expectEqualStrings("予算制限", goalStatusChromeFor(.japanese, "").budget_limited);
    try testing.expectEqualStrings("完了", goalStatusChromeFor(.japanese, "").complete);
    try testing.expectEqualStrings("進行中", goalStatusChromeFor(.japanese, "").labelForId("active"));
    try testing.expectEqualStrings("使用量制限", goalStatusChromeFor(.japanese, "").labelForId("usageLimited"));

    try testing.expectEqualStrings("进行中", goalStatusChromeFor(.system, "zh_CN.UTF-8").active);
    try testing.expectEqualStrings("已暂停", goalStatusChromeFor(.system, "zh_CN.UTF-8").paused);
    try testing.expectEqualStrings("用量受限", goalStatusChromeFor(.system, "zh_CN.UTF-8").usage_limited);
    try testing.expectEqualStrings("進行中", goalStatusChromeFor(.system, "ja_JP.UTF-8").active);
    try testing.expectEqualStrings("一時停止", goalStatusChromeFor(.system, "ja_JP.UTF-8").paused);
    try testing.expectEqualStrings("使用量制限", goalStatusChromeFor(.system, "ja_JP.UTF-8").usage_limited);
    try testing.expectEqualStrings("Active", goalStatusChromeFor(.english, "ja_JP.UTF-8").active);
    try testing.expectEqualStrings("Paused", goalStatusChromeFor(.english, "ja_JP.UTF-8").paused);
    try testing.expectEqualStrings("Usage limited", goalStatusChromeFor(.english, "ja_JP.UTF-8").usage_limited);
    try testing.expectEqualStrings("Active", goalStatusChromeFor(.english, "zh_CN.UTF-8").active);
    try testing.expectEqualStrings("Budget limited", goalStatusChromeFor(.english, "zh_CN.UTF-8").budget_limited);
    try testing.expectEqualStrings("Complete", goalStatusChromeFor(.english, "zh_CN.UTF-8").complete);
}

test "usageCostQualityChromeFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("Cost quality", usageCostQualityChromeFor(.english, "ja").cost_quality);
    try testing.expectEqualStrings("Provider reported", usageCostQualityChromeFor(.english, "").provider_reported);
    try testing.expectEqualStrings("Model priced", usageCostQualityChromeFor(.english, "").model_priced);
    try testing.expectEqualStrings("Unpriced", usageCostQualityChromeFor(.english, "").unpriced);
    try testing.expectEqualStrings("Cache savings", usageCostQualityChromeFor(.english, "").cache_savings);
    try testing.expectEqualStrings("Processed tokens", usageCostQualityChromeFor(.english, "").processed_tokens);
    try testing.expectEqualStrings("Cached input", usageCostQualityChromeFor(.english, "").cached_input);
    try testing.expectEqualStrings("Uncached input", usageCostQualityChromeFor(.english, "").uncached_input);
    try testing.expectEqualStrings("Output", usageCostQualityChromeFor(.english, "").output);
    try testing.expectEqualStrings("Rates fresh", usageCostQualityChromeFor(.english, "").rates_fresh);
    try testing.expectEqualStrings("Rates cached", usageCostQualityChromeFor(.english, "").rates_cached);
    try testing.expectEqualStrings("Rates unavailable", usageCostQualityChromeFor(.english, "").rates_unavailable);
    try testing.expectEqualStrings("per active month", usageCostQualityChromeFor(.english, "").per_active_month);
    try testing.expectEqualStrings("per active day", usageCostQualityChromeFor(.english, "").per_active_day);
    try testing.expectEqualStrings("of observed input", usageCostQualityChromeFor(.english, "").of_observed_input);
    try testing.expectEqualStrings("cache writes", usageCostQualityChromeFor(.english, "").cache_writes);
    try testing.expectEqualStrings("includes ", usageCostQualityChromeFor(.english, "").includes_reasoning_prefix);
    try testing.expectEqualStrings(" reasoning", usageCostQualityChromeFor(.english, "").includes_reasoning_suffix);
    try testing.expectEqualStrings("raw cost", usageCostQualityChromeFor(.english, "").raw_cost);
    try testing.expectEqualStrings("vs full input rates", usageCostQualityChromeFor(.english, "").vs_full_input_rates);
    try testing.expectEqualStrings("Cost quality", usageCostQualityChromeFor(.system, "").cost_quality);

    try testing.expectEqualStrings("费用质量", usageCostQualityChromeFor(.simplified_chinese, "").cost_quality);
    try testing.expectEqualStrings("提供商上报", usageCostQualityChromeFor(.simplified_chinese, "").provider_reported);
    try testing.expectEqualStrings("模型定价", usageCostQualityChromeFor(.simplified_chinese, "").model_priced);
    try testing.expectEqualStrings("未定价", usageCostQualityChromeFor(.simplified_chinese, "").unpriced);
    try testing.expectEqualStrings("缓存节省", usageCostQualityChromeFor(.simplified_chinese, "").cache_savings);
    try testing.expectEqualStrings("已处理 token", usageCostQualityChromeFor(.simplified_chinese, "").processed_tokens);
    try testing.expectEqualStrings("缓存输入", usageCostQualityChromeFor(.simplified_chinese, "").cached_input);
    try testing.expectEqualStrings("非缓存输入", usageCostQualityChromeFor(.simplified_chinese, "").uncached_input);
    try testing.expectEqualStrings("输出", usageCostQualityChromeFor(.simplified_chinese, "").output);
    try testing.expectEqualStrings("费率最新", usageCostQualityChromeFor(.simplified_chinese, "").rates_fresh);
    try testing.expectEqualStrings("费率缓存", usageCostQualityChromeFor(.simplified_chinese, "").rates_cached);
    try testing.expectEqualStrings("费率不可用", usageCostQualityChromeFor(.simplified_chinese, "").rates_unavailable);
    try testing.expectEqualStrings("每活跃月", usageCostQualityChromeFor(.simplified_chinese, "").per_active_month);
    try testing.expectEqualStrings("每活跃日", usageCostQualityChromeFor(.simplified_chinese, "").per_active_day);
    try testing.expectEqualStrings("占观测输入", usageCostQualityChromeFor(.simplified_chinese, "").of_observed_input);
    try testing.expectEqualStrings("缓存写入", usageCostQualityChromeFor(.simplified_chinese, "").cache_writes);
    try testing.expectEqualStrings("含 ", usageCostQualityChromeFor(.simplified_chinese, "").includes_reasoning_prefix);
    try testing.expectEqualStrings(" 推理", usageCostQualityChromeFor(.simplified_chinese, "").includes_reasoning_suffix);
    try testing.expectEqualStrings("原始费用", usageCostQualityChromeFor(.simplified_chinese, "").raw_cost);
    try testing.expectEqualStrings("对比完整输入费率", usageCostQualityChromeFor(.simplified_chinese, "").vs_full_input_rates);

    try testing.expectEqualStrings("コスト品質", usageCostQualityChromeFor(.japanese, "").cost_quality);
    try testing.expectEqualStrings("プロバイダー報告", usageCostQualityChromeFor(.japanese, "").provider_reported);
    try testing.expectEqualStrings("モデル価格", usageCostQualityChromeFor(.japanese, "").model_priced);
    try testing.expectEqualStrings("未価格", usageCostQualityChromeFor(.japanese, "").unpriced);
    try testing.expectEqualStrings("キャッシュ節約", usageCostQualityChromeFor(.japanese, "").cache_savings);
    try testing.expectEqualStrings("処理済みトークン", usageCostQualityChromeFor(.japanese, "").processed_tokens);
    try testing.expectEqualStrings("キャッシュ入力", usageCostQualityChromeFor(.japanese, "").cached_input);
    try testing.expectEqualStrings("非キャッシュ入力", usageCostQualityChromeFor(.japanese, "").uncached_input);
    try testing.expectEqualStrings("出力", usageCostQualityChromeFor(.japanese, "").output);
    try testing.expectEqualStrings("レート最新", usageCostQualityChromeFor(.japanese, "").rates_fresh);
    try testing.expectEqualStrings("レートキャッシュ", usageCostQualityChromeFor(.japanese, "").rates_cached);
    try testing.expectEqualStrings("レート利用不可", usageCostQualityChromeFor(.japanese, "").rates_unavailable);
    try testing.expectEqualStrings("アクティブ月あたり", usageCostQualityChromeFor(.japanese, "").per_active_month);
    try testing.expectEqualStrings("アクティブ日あたり", usageCostQualityChromeFor(.japanese, "").per_active_day);
    try testing.expectEqualStrings("の観測入力", usageCostQualityChromeFor(.japanese, "").of_observed_input);
    try testing.expectEqualStrings("キャッシュ書き込み", usageCostQualityChromeFor(.japanese, "").cache_writes);
    try testing.expectEqualStrings("", usageCostQualityChromeFor(.japanese, "").includes_reasoning_prefix);
    try testing.expectEqualStrings(" の推論を含む", usageCostQualityChromeFor(.japanese, "").includes_reasoning_suffix);
    try testing.expectEqualStrings("生コスト", usageCostQualityChromeFor(.japanese, "").raw_cost);
    try testing.expectEqualStrings("全入力レート比", usageCostQualityChromeFor(.japanese, "").vs_full_input_rates);

    try testing.expectEqualStrings("费用质量", usageCostQualityChromeFor(.system, "zh_CN.UTF-8").cost_quality);
    try testing.expectEqualStrings("费率缓存", usageCostQualityChromeFor(.system, "zh_CN.UTF-8").rates_cached);
    try testing.expectEqualStrings("已处理 token", usageCostQualityChromeFor(.system, "zh_CN.UTF-8").processed_tokens);
    try testing.expectEqualStrings("コスト品質", usageCostQualityChromeFor(.system, "ja_JP.UTF-8").cost_quality);
    try testing.expectEqualStrings("レート最新", usageCostQualityChromeFor(.system, "ja_JP.UTF-8").rates_fresh);
    try testing.expectEqualStrings("処理済みトークン", usageCostQualityChromeFor(.system, "ja_JP.UTF-8").processed_tokens);
    try testing.expectEqualStrings("Cost quality", usageCostQualityChromeFor(.english, "ja_JP.UTF-8").cost_quality);
    try testing.expectEqualStrings("Rates unavailable", usageCostQualityChromeFor(.english, "zh_CN.UTF-8").rates_unavailable);
    try testing.expectEqualStrings("Processed tokens", usageCostQualityChromeFor(.english, "ja_JP.UTF-8").processed_tokens);
    try testing.expectEqualStrings("Cache savings", usageCostQualityChromeFor(.english, "zh_CN.UTF-8").cache_savings);
}

test "usageScanFooterChromeFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("files", usageScanFooterChromeFor(.english, "ja").files);
    try testing.expectEqualStrings("skipped", usageScanFooterChromeFor(.english, "").skipped);
    try testing.expectEqualStrings("records", usageScanFooterChromeFor(.english, "").records);
    try testing.expectEqualStrings("files", usageScanFooterChromeFor(.system, "").files);
    try testing.expectEqualStrings("skipped", usageScanFooterChromeFor(.system, "").skipped);
    try testing.expectEqualStrings("records", usageScanFooterChromeFor(.system, "").records);

    try testing.expectEqualStrings("文件", usageScanFooterChromeFor(.simplified_chinese, "").files);
    try testing.expectEqualStrings("已跳过", usageScanFooterChromeFor(.simplified_chinese, "").skipped);
    try testing.expectEqualStrings("记录", usageScanFooterChromeFor(.simplified_chinese, "").records);
    try testing.expectEqualStrings("ファイル", usageScanFooterChromeFor(.japanese, "").files);
    try testing.expectEqualStrings("スキップ", usageScanFooterChromeFor(.japanese, "").skipped);
    try testing.expectEqualStrings("レコード", usageScanFooterChromeFor(.japanese, "").records);

    try testing.expectEqualStrings("文件", usageScanFooterChromeFor(.system, "zh_CN.UTF-8").files);
    try testing.expectEqualStrings("已跳过", usageScanFooterChromeFor(.system, "zh_CN.UTF-8").skipped);
    try testing.expectEqualStrings("记录", usageScanFooterChromeFor(.system, "zh_CN.UTF-8").records);
    try testing.expectEqualStrings("ファイル", usageScanFooterChromeFor(.system, "ja_JP.UTF-8").files);
    try testing.expectEqualStrings("スキップ", usageScanFooterChromeFor(.system, "ja_JP.UTF-8").skipped);
    try testing.expectEqualStrings("レコード", usageScanFooterChromeFor(.system, "ja_JP.UTF-8").records);
    try testing.expectEqualStrings("files", usageScanFooterChromeFor(.english, "ja_JP.UTF-8").files);
    try testing.expectEqualStrings("skipped", usageScanFooterChromeFor(.english, "zh_CN.UTF-8").skipped);
    try testing.expectEqualStrings("records", usageScanFooterChromeFor(.english, "ja_JP.UTF-8").records);
}

test "usageSessionsChromeFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("sessions", usageSessionsChromeFor(.english, "ja").sessions);
    try testing.expectEqualStrings("Connect a daemon for usage history", usageSessionsChromeFor(.english, "").connect_daemon);
    try testing.expectEqualStrings("sessions", usageSessionsChromeFor(.system, "").sessions);
    try testing.expectEqualStrings("Connect a daemon for usage history", usageSessionsChromeFor(.system, "").connect_daemon);

    try testing.expectEqualStrings("会话", usageSessionsChromeFor(.simplified_chinese, "").sessions);
    try testing.expectEqualStrings("连接守护进程以查看用量历史", usageSessionsChromeFor(.simplified_chinese, "").connect_daemon);
    try testing.expectEqualStrings("セッション", usageSessionsChromeFor(.japanese, "").sessions);
    try testing.expectEqualStrings("デーモンに接続して使用量履歴を表示", usageSessionsChromeFor(.japanese, "").connect_daemon);

    try testing.expectEqualStrings("会话", usageSessionsChromeFor(.system, "zh_CN.UTF-8").sessions);
    try testing.expectEqualStrings("连接守护进程以查看用量历史", usageSessionsChromeFor(.system, "zh_CN.UTF-8").connect_daemon);
    try testing.expectEqualStrings("セッション", usageSessionsChromeFor(.system, "ja_JP.UTF-8").sessions);
    try testing.expectEqualStrings("デーモンに接続して使用量履歴を表示", usageSessionsChromeFor(.system, "ja_JP.UTF-8").connect_daemon);
    try testing.expectEqualStrings("sessions", usageSessionsChromeFor(.english, "ja_JP.UTF-8").sessions);
    try testing.expectEqualStrings("Connect a daemon for usage history", usageSessionsChromeFor(.english, "zh_CN.UTF-8").connect_daemon);
    try testing.expectEqualStrings("sessions", usageSessionsChromeFor(.english, "zh_CN.UTF-8").sessions);
}

test "usageMeterChromeFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("Connect a daemon for plan usage", usageMeterChromeFor(.english, "ja").connect_hint);
    try testing.expectEqualStrings("Loading plan usage…", usageMeterChromeFor(.english, "").loading_hint);
    try testing.expectEqualStrings("Plan usage unconfigured", usageMeterChromeFor(.english, "").unconfigured_hint);
    try testing.expectEqualStrings("Plan usage unavailable", usageMeterChromeFor(.english, "").unavailable_hint);
    try testing.expectEqualStrings("Nothing measured yet", usageMeterChromeFor(.english, "").nothing_measured);
    try testing.expectEqualStrings("Plan limits", usageMeterChromeFor(.english, "").plan_limits);
    try testing.expectEqualStrings("Resets soon", usageMeterChromeFor(.english, "").resets_soon);
    try testing.expectEqualStrings("Resets in", usageMeterChromeFor(.english, "").resets_in);
    try testing.expectEqualStrings("Connect a daemon for plan usage", usageMeterChromeFor(.system, "").connect_hint);
    try testing.expectEqualStrings("Nothing measured yet", usageMeterChromeFor(.system, "").nothing_measured);
    try testing.expectEqualStrings("Plan limits", usageMeterChromeFor(.system, "").plan_limits);
    try testing.expectEqualStrings("Resets soon", usageMeterChromeFor(.system, "").resets_soon);

    try testing.expectEqualStrings("连接守护进程以查看套餐用量", usageMeterChromeFor(.simplified_chinese, "").connect_hint);
    try testing.expectEqualStrings("正在加载套餐用量…", usageMeterChromeFor(.simplified_chinese, "").loading_hint);
    try testing.expectEqualStrings("套餐用量未配置", usageMeterChromeFor(.simplified_chinese, "").unconfigured_hint);
    try testing.expectEqualStrings("套餐用量不可用", usageMeterChromeFor(.simplified_chinese, "").unavailable_hint);
    try testing.expectEqualStrings("尚无用量", usageMeterChromeFor(.simplified_chinese, "").nothing_measured);
    try testing.expectEqualStrings("套餐限额", usageMeterChromeFor(.simplified_chinese, "").plan_limits);
    try testing.expectEqualStrings("即将重置", usageMeterChromeFor(.simplified_chinese, "").resets_soon);
    try testing.expectEqualStrings("剩余", usageMeterChromeFor(.simplified_chinese, "").resets_in);
    try testing.expectEqualStrings("デーモンに接続してプラン使用量を表示", usageMeterChromeFor(.japanese, "").connect_hint);
    try testing.expectEqualStrings("プラン使用量を読み込み中…", usageMeterChromeFor(.japanese, "").loading_hint);
    try testing.expectEqualStrings("プラン使用量は未設定", usageMeterChromeFor(.japanese, "").unconfigured_hint);
    try testing.expectEqualStrings("プラン使用量は利用不可", usageMeterChromeFor(.japanese, "").unavailable_hint);
    try testing.expectEqualStrings("まだ計測なし", usageMeterChromeFor(.japanese, "").nothing_measured);
    try testing.expectEqualStrings("プラン上限", usageMeterChromeFor(.japanese, "").plan_limits);
    try testing.expectEqualStrings("まもなくリセット", usageMeterChromeFor(.japanese, "").resets_soon);
    try testing.expectEqualStrings("あと", usageMeterChromeFor(.japanese, "").resets_in);

    try testing.expectEqualStrings("连接守护进程以查看套餐用量", usageMeterChromeFor(.system, "zh_CN.UTF-8").connect_hint);
    try testing.expectEqualStrings("尚无用量", usageMeterChromeFor(.system, "zh_CN.UTF-8").nothing_measured);
    try testing.expectEqualStrings("套餐限额", usageMeterChromeFor(.system, "zh_CN.UTF-8").plan_limits);
    try testing.expectEqualStrings("即将重置", usageMeterChromeFor(.system, "zh_CN.UTF-8").resets_soon);
    try testing.expectEqualStrings("剩余", usageMeterChromeFor(.system, "zh_CN.UTF-8").resets_in);
    try testing.expectEqualStrings("デーモンに接続してプラン使用量を表示", usageMeterChromeFor(.system, "ja_JP.UTF-8").connect_hint);
    try testing.expectEqualStrings("まだ計測なし", usageMeterChromeFor(.system, "ja_JP.UTF-8").nothing_measured);
    try testing.expectEqualStrings("プラン上限", usageMeterChromeFor(.system, "ja_JP.UTF-8").plan_limits);
    try testing.expectEqualStrings("まもなくリセット", usageMeterChromeFor(.system, "ja_JP.UTF-8").resets_soon);
    try testing.expectEqualStrings("あと", usageMeterChromeFor(.system, "ja_JP.UTF-8").resets_in);
    try testing.expectEqualStrings("Connect a daemon for plan usage", usageMeterChromeFor(.english, "ja_JP.UTF-8").connect_hint);
    try testing.expectEqualStrings("Nothing measured yet", usageMeterChromeFor(.english, "zh_CN.UTF-8").nothing_measured);
    try testing.expectEqualStrings("Plan limits", usageMeterChromeFor(.english, "ja_JP.UTF-8").plan_limits);
    try testing.expectEqualStrings("Resets soon", usageMeterChromeFor(.english, "zh_CN.UTF-8").resets_soon);
    try testing.expectEqualStrings("Resets in", usageMeterChromeFor(.english, "ja_JP.UTF-8").resets_in);
}

test "usageLocalChromeFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("Context window", usageLocalChromeFor(.english, "ja").context_window);
    try testing.expectEqualStrings("No context usage reported yet", usageLocalChromeFor(.english, "").no_context_usage);
    try testing.expectEqualStrings("Thread goal tokens", usageLocalChromeFor(.english, "").thread_goal_tokens);
    try testing.expectEqualStrings("No thread goal usage", usageLocalChromeFor(.english, "").no_thread_goal_usage);
    try testing.expectEqualStrings("Context window", usageLocalChromeFor(.system, "").context_window);
    try testing.expectEqualStrings("No context usage reported yet", usageLocalChromeFor(.system, "").no_context_usage);
    try testing.expectEqualStrings("Thread goal tokens", usageLocalChromeFor(.system, "").thread_goal_tokens);
    try testing.expectEqualStrings("No thread goal usage", usageLocalChromeFor(.system, "").no_thread_goal_usage);

    try testing.expectEqualStrings("上下文窗口", usageLocalChromeFor(.simplified_chinese, "").context_window);
    try testing.expectEqualStrings("尚未报告上下文用量", usageLocalChromeFor(.simplified_chinese, "").no_context_usage);
    try testing.expectEqualStrings("线程目标 Token", usageLocalChromeFor(.simplified_chinese, "").thread_goal_tokens);
    try testing.expectEqualStrings("没有线程目标用量", usageLocalChromeFor(.simplified_chinese, "").no_thread_goal_usage);
    try testing.expectEqualStrings("コンテキストウィンドウ", usageLocalChromeFor(.japanese, "").context_window);
    try testing.expectEqualStrings("コンテキスト使用量はまだ報告されていません", usageLocalChromeFor(.japanese, "").no_context_usage);
    try testing.expectEqualStrings("スレッド目標トークン", usageLocalChromeFor(.japanese, "").thread_goal_tokens);
    try testing.expectEqualStrings("スレッド目標の使用量はありません", usageLocalChromeFor(.japanese, "").no_thread_goal_usage);

    try testing.expectEqualStrings("上下文窗口", usageLocalChromeFor(.system, "zh_CN.UTF-8").context_window);
    try testing.expectEqualStrings("尚未报告上下文用量", usageLocalChromeFor(.system, "zh_CN.UTF-8").no_context_usage);
    try testing.expectEqualStrings("线程目标 Token", usageLocalChromeFor(.system, "zh_CN.UTF-8").thread_goal_tokens);
    try testing.expectEqualStrings("没有线程目标用量", usageLocalChromeFor(.system, "zh_CN.UTF-8").no_thread_goal_usage);
    try testing.expectEqualStrings("コンテキストウィンドウ", usageLocalChromeFor(.system, "ja_JP.UTF-8").context_window);
    try testing.expectEqualStrings("コンテキスト使用量はまだ報告されていません", usageLocalChromeFor(.system, "ja_JP.UTF-8").no_context_usage);
    try testing.expectEqualStrings("スレッド目標トークン", usageLocalChromeFor(.system, "ja_JP.UTF-8").thread_goal_tokens);
    try testing.expectEqualStrings("スレッド目標の使用量はありません", usageLocalChromeFor(.system, "ja_JP.UTF-8").no_thread_goal_usage);
    try testing.expectEqualStrings("Context window", usageLocalChromeFor(.english, "ja_JP.UTF-8").context_window);
    try testing.expectEqualStrings("No context usage reported yet", usageLocalChromeFor(.english, "zh_CN.UTF-8").no_context_usage);
    try testing.expectEqualStrings("Thread goal tokens", usageLocalChromeFor(.english, "ja_JP.UTF-8").thread_goal_tokens);
    try testing.expectEqualStrings("No thread goal usage", usageLocalChromeFor(.english, "zh_CN.UTF-8").no_thread_goal_usage);
}

test "providersChromeFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("Available", providersChromeFor(.english, "ja").available);
    try testing.expectEqualStrings("Not found", providersChromeFor(.english, "").not_found);
    try testing.expectEqualStrings("First-party default", providersChromeFor(.english, "").first_party);
    try testing.expectEqualStrings("Enable", providersChromeFor(.english, "").enable);
    try testing.expectEqualStrings("Disable", providersChromeFor(.english, "").disable);
    try testing.expectEqualStrings("Use for this session", providersChromeFor(.english, "").apply);
    try testing.expectEqualStrings("Copy install command", providersChromeFor(.english, "").copy_install);
    try testing.expectEqualStrings("Copy login command", providersChromeFor(.english, "").copy_login);
    try testing.expectEqualStrings("Available", providersChromeFor(.system, "").available);
    try testing.expectEqualStrings("Not found", providersChromeFor(.system, "").not_found);
    try testing.expectEqualStrings("First-party default", providersChromeFor(.system, "").first_party);
    try testing.expectEqualStrings("Enable", providersChromeFor(.system, "").enable);
    try testing.expectEqualStrings("Disable", providersChromeFor(.system, "").disable);
    try testing.expectEqualStrings("Use for this session", providersChromeFor(.system, "").apply);
    try testing.expectEqualStrings("Copy install command", providersChromeFor(.system, "").copy_install);
    try testing.expectEqualStrings("Copy login command", providersChromeFor(.system, "").copy_login);

    try testing.expectEqualStrings("可用", providersChromeFor(.simplified_chinese, "").available);
    try testing.expectEqualStrings("未找到", providersChromeFor(.simplified_chinese, "").not_found);
    try testing.expectEqualStrings("第一方默认", providersChromeFor(.simplified_chinese, "").first_party);
    try testing.expectEqualStrings("启用", providersChromeFor(.simplified_chinese, "").enable);
    try testing.expectEqualStrings("禁用", providersChromeFor(.simplified_chinese, "").disable);
    try testing.expectEqualStrings("用于此会话", providersChromeFor(.simplified_chinese, "").apply);
    try testing.expectEqualStrings("复制安装命令", providersChromeFor(.simplified_chinese, "").copy_install);
    try testing.expectEqualStrings("复制登录命令", providersChromeFor(.simplified_chinese, "").copy_login);
    try testing.expectEqualStrings("利用可能", providersChromeFor(.japanese, "").available);
    try testing.expectEqualStrings("見つかりません", providersChromeFor(.japanese, "").not_found);
    try testing.expectEqualStrings("ファーストパーティ既定", providersChromeFor(.japanese, "").first_party);
    try testing.expectEqualStrings("有効", providersChromeFor(.japanese, "").enable);
    try testing.expectEqualStrings("無効", providersChromeFor(.japanese, "").disable);
    try testing.expectEqualStrings("このセッションで使う", providersChromeFor(.japanese, "").apply);
    try testing.expectEqualStrings("インストールコマンドをコピー", providersChromeFor(.japanese, "").copy_install);
    try testing.expectEqualStrings("ログインコマンドをコピー", providersChromeFor(.japanese, "").copy_login);

    try testing.expectEqualStrings("可用", providersChromeFor(.system, "zh_CN.UTF-8").available);
    try testing.expectEqualStrings("未找到", providersChromeFor(.system, "zh_CN.UTF-8").not_found);
    try testing.expectEqualStrings("第一方默认", providersChromeFor(.system, "zh_CN.UTF-8").first_party);
    try testing.expectEqualStrings("启用", providersChromeFor(.system, "zh_CN.UTF-8").enable);
    try testing.expectEqualStrings("禁用", providersChromeFor(.system, "zh_CN.UTF-8").disable);
    try testing.expectEqualStrings("用于此会话", providersChromeFor(.system, "zh_CN.UTF-8").apply);
    try testing.expectEqualStrings("复制安装命令", providersChromeFor(.system, "zh_CN.UTF-8").copy_install);
    try testing.expectEqualStrings("复制登录命令", providersChromeFor(.system, "zh_CN.UTF-8").copy_login);
    try testing.expectEqualStrings("利用可能", providersChromeFor(.system, "ja_JP.UTF-8").available);
    try testing.expectEqualStrings("見つかりません", providersChromeFor(.system, "ja_JP.UTF-8").not_found);
    try testing.expectEqualStrings("ファーストパーティ既定", providersChromeFor(.system, "ja_JP.UTF-8").first_party);
    try testing.expectEqualStrings("有効", providersChromeFor(.system, "ja_JP.UTF-8").enable);
    try testing.expectEqualStrings("無効", providersChromeFor(.system, "ja_JP.UTF-8").disable);
    try testing.expectEqualStrings("このセッションで使う", providersChromeFor(.system, "ja_JP.UTF-8").apply);
    try testing.expectEqualStrings("インストールコマンドをコピー", providersChromeFor(.system, "ja_JP.UTF-8").copy_install);
    try testing.expectEqualStrings("ログインコマンドをコピー", providersChromeFor(.system, "ja_JP.UTF-8").copy_login);
    try testing.expectEqualStrings("Available", providersChromeFor(.english, "ja_JP.UTF-8").available);
    try testing.expectEqualStrings("Not found", providersChromeFor(.english, "zh_CN.UTF-8").not_found);
    try testing.expectEqualStrings("First-party default", providersChromeFor(.english, "zh_CN.UTF-8").first_party);
    try testing.expectEqualStrings("Enable", providersChromeFor(.english, "ja_JP.UTF-8").enable);
    try testing.expectEqualStrings("Disable", providersChromeFor(.english, "zh_CN.UTF-8").disable);
    try testing.expectEqualStrings("Use for this session", providersChromeFor(.english, "ja_JP.UTF-8").apply);
    try testing.expectEqualStrings("Copy install command", providersChromeFor(.english, "zh_CN.UTF-8").copy_install);
    try testing.expectEqualStrings("Copy login command", providersChromeFor(.english, "ja_JP.UTF-8").copy_login);
}

test "providersDetailChromeFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings(
        "Status is a PATH --help probe. Send stays demo this cut.",
        providersDetailChromeFor(.english, "ja").catalog_detail_note,
    );
    try testing.expectEqualStrings(
        "Live path is one-shot fx acp via acp-proxy.",
        providersDetailChromeFor(.english, "").fx_transport_note,
    );
    try testing.expectEqualStrings(
        "Live Send is one-shot acp via acp-proxy when Available (ACP image content blocks when attached).",
        providersDetailChromeFor(.english, "").acp_transport_note,
    );
    try testing.expectEqualStrings(
        "Live Send is one-shot grok agent stdio via acp-proxy when Available (ACP image content blocks when attached).",
        providersDetailChromeFor(.english, "").grok_transport_note,
    );
    try testing.expectEqualStrings(
        "Live Send is one-shot claude -p --output-format stream-json --forward-subagent-text when Available (later Sends --resume {fx_session_id} when stored; image path in the -p prompt when attached).",
        providersDetailChromeFor(.english, "").claude_transport_note,
    );
    try testing.expectEqualStrings(
        "Live Send is one-shot codex exec when Available (`--image` when attached).",
        providersDetailChromeFor(.english, "").codex_transport_note,
    );
    try testing.expectEqualStrings(
        "Live Send is one-shot amp -x / --execute when Available (`@path` when attached).",
        providersDetailChromeFor(.english, "").amp_transport_note,
    );
    try testing.expectEqualStrings(
        "Live Send is one-shot pi --mode json when Available (`@path` when attached).",
        providersDetailChromeFor(.english, "").pi_transport_note,
    );
    try testing.expectEqualStrings(
        "Faku does not detect auth state from the --help probe. Copy is a convenience, not sign-in UI or OAuth.",
        providersDetailChromeFor(.english, "").fx_login_note,
    );
    try testing.expectEqualStrings(
        "Optional: fx login grok / fx login codex (no Gateway required).",
        providersDetailChromeFor(.english, "").fx_login_codex_note,
    );
    try testing.expectEqualStrings(
        "Install that CLI on PATH, then Refresh.",
        providersDetailChromeFor(.english, "").other_install_hint,
    );
    try testing.expectEqualStrings("Binary:", providersDetailChromeFor(.english, "ja").binary_prefix);
    try testing.expectEqualStrings("Path:", providersDetailChromeFor(.english, "").path_prefix);
    try testing.expectEqualStrings(
        "Live path is one-shot fx acp via acp-proxy.",
        providersDetailChromeFor(.system, "").fx_transport_note,
    );
    try testing.expectEqualStrings(
        "Install that CLI on PATH, then Refresh.",
        providersDetailChromeFor(.system, "").other_install_hint,
    );
    try testing.expectEqualStrings("Binary:", providersDetailChromeFor(.system, "").binary_prefix);
    try testing.expectEqualStrings("Path:", providersDetailChromeFor(.system, "").path_prefix);

    try testing.expectEqualStrings("状态来自 PATH --help 探测。本轮 Send 仍为演示。", providersDetailChromeFor(.simplified_chinese, "").catalog_detail_note);
    try testing.expectEqualStrings("实际路径是通过 acp-proxy 的一次性 fx acp。", providersDetailChromeFor(.simplified_chinese, "").fx_transport_note);
    try testing.expectEqualStrings("可用时，实际 Send 是通过 acp-proxy 的一次性 acp（附加图片时使用 ACP 图像内容块）。", providersDetailChromeFor(.simplified_chinese, "").acp_transport_note);
    try testing.expectEqualStrings("可用时，实际 Send 是通过 acp-proxy 的一次性 grok agent stdio（附加图片时使用 ACP 图像内容块）。", providersDetailChromeFor(.simplified_chinese, "").grok_transport_note);
    try testing.expectEqualStrings("可用时，实际 Send 是一次性 claude -p --output-format stream-json --forward-subagent-text（已存储时后续 Send 使用 --resume {fx_session_id}；附加图片时在 -p 提示中放入路径）。", providersDetailChromeFor(.simplified_chinese, "").claude_transport_note);
    try testing.expectEqualStrings("可用时，实际 Send 是一次性 codex exec（附加时使用 `--image`）。", providersDetailChromeFor(.simplified_chinese, "").codex_transport_note);
    try testing.expectEqualStrings("可用时，实际 Send 是一次性 amp -x / --execute（附加时使用 `@path`）。", providersDetailChromeFor(.simplified_chinese, "").amp_transport_note);
    try testing.expectEqualStrings("可用时，实际 Send 是一次性 pi --mode json（附加时使用 `@path`）。", providersDetailChromeFor(.simplified_chinese, "").pi_transport_note);
    try testing.expectEqualStrings("Faku 不会从 --help 探测中检测认证状态。复制仅为便利，不是登录界面或 OAuth。", providersDetailChromeFor(.simplified_chinese, "").fx_login_note);
    try testing.expectEqualStrings("可选：fx login grok / fx login codex（无需 Gateway）。", providersDetailChromeFor(.simplified_chinese, "").fx_login_codex_note);
    try testing.expectEqualStrings("将该 CLI 安装到 PATH，然后刷新。", providersDetailChromeFor(.simplified_chinese, "").other_install_hint);
    try testing.expectEqualStrings("二进制:", providersDetailChromeFor(.simplified_chinese, "").binary_prefix);
    try testing.expectEqualStrings("路径:", providersDetailChromeFor(.simplified_chinese, "").path_prefix);

    try testing.expectEqualStrings("状態は PATH --help のプローブです。現状の Send はデモのままです。", providersDetailChromeFor(.japanese, "").catalog_detail_note);
    try testing.expectEqualStrings("実経路は acp-proxy 経由のワンショット fx acp です。", providersDetailChromeFor(.japanese, "").fx_transport_note);
    try testing.expectEqualStrings("利用可能なとき、実際の Send は acp-proxy 経由のワンショット acp です（添付時は ACP 画像コンテンツブロック）。", providersDetailChromeFor(.japanese, "").acp_transport_note);
    try testing.expectEqualStrings("利用可能なとき、実際の Send は acp-proxy 経由のワンショット grok agent stdio です（添付時は ACP 画像コンテンツブロック）。", providersDetailChromeFor(.japanese, "").grok_transport_note);
    try testing.expectEqualStrings("利用可能なとき、実際の Send はワンショット claude -p --output-format stream-json --forward-subagent-text です（保存済みなら後続 Send は --resume {fx_session_id}；添付時は -p プロンプトに画像パス）。", providersDetailChromeFor(.japanese, "").claude_transport_note);
    try testing.expectEqualStrings("利用可能なとき、実際の Send はワンショット codex exec です（添付時は `--image`）。", providersDetailChromeFor(.japanese, "").codex_transport_note);
    try testing.expectEqualStrings("利用可能なとき、実際の Send はワンショット amp -x / --execute です（添付時は `@path`）。", providersDetailChromeFor(.japanese, "").amp_transport_note);
    try testing.expectEqualStrings("利用可能なとき、実際の Send はワンショット pi --mode json です（添付時は `@path`）。", providersDetailChromeFor(.japanese, "").pi_transport_note);
    try testing.expectEqualStrings("Faku は --help プローブから認証状態を検出しません。コピーは便宜であり、サインイン UI や OAuth ではありません。", providersDetailChromeFor(.japanese, "").fx_login_note);
    try testing.expectEqualStrings("任意: fx login grok / fx login codex（Gateway は不要）。", providersDetailChromeFor(.japanese, "").fx_login_codex_note);
    try testing.expectEqualStrings("その CLI を PATH にインストールしてから更新してください。", providersDetailChromeFor(.japanese, "").other_install_hint);
    try testing.expectEqualStrings("バイナリ:", providersDetailChromeFor(.japanese, "").binary_prefix);
    try testing.expectEqualStrings("パス:", providersDetailChromeFor(.japanese, "").path_prefix);

    try testing.expectEqualStrings("实际路径是通过 acp-proxy 的一次性 fx acp。", providersDetailChromeFor(.system, "zh_CN.UTF-8").fx_transport_note);
    try testing.expectEqualStrings("将该 CLI 安装到 PATH，然后刷新。", providersDetailChromeFor(.system, "zh_CN.UTF-8").other_install_hint);
    try testing.expectEqualStrings("Faku 不会从 --help 探测中检测认证状态。复制仅为便利，不是登录界面或 OAuth。", providersDetailChromeFor(.system, "zh_CN.UTF-8").fx_login_note);
    try testing.expectEqualStrings("二进制:", providersDetailChromeFor(.system, "zh_CN.UTF-8").binary_prefix);
    try testing.expectEqualStrings("路径:", providersDetailChromeFor(.system, "zh_CN.UTF-8").path_prefix);
    try testing.expectEqualStrings("実経路は acp-proxy 経由のワンショット fx acp です。", providersDetailChromeFor(.system, "ja_JP.UTF-8").fx_transport_note);
    try testing.expectEqualStrings("その CLI を PATH にインストールしてから更新してください。", providersDetailChromeFor(.system, "ja_JP.UTF-8").other_install_hint);
    try testing.expectEqualStrings("Faku は --help プローブから認証状態を検出しません。コピーは便宜であり、サインイン UI や OAuth ではありません。", providersDetailChromeFor(.system, "ja_JP.UTF-8").fx_login_note);
    try testing.expectEqualStrings("バイナリ:", providersDetailChromeFor(.system, "ja_JP.UTF-8").binary_prefix);
    try testing.expectEqualStrings("パス:", providersDetailChromeFor(.system, "ja_JP.UTF-8").path_prefix);
    try testing.expectEqualStrings("Live path is one-shot fx acp via acp-proxy.", providersDetailChromeFor(.english, "ja_JP.UTF-8").fx_transport_note);
    try testing.expectEqualStrings("Install that CLI on PATH, then Refresh.", providersDetailChromeFor(.english, "zh_CN.UTF-8").other_install_hint);
    try testing.expectEqualStrings("Faku does not detect auth state from the --help probe. Copy is a convenience, not sign-in UI or OAuth.", providersDetailChromeFor(.english, "ja_JP.UTF-8").fx_login_note);
    try testing.expectEqualStrings("Optional: fx login grok / fx login codex (no Gateway required).", providersDetailChromeFor(.english, "zh_CN.UTF-8").fx_login_codex_note);
    try testing.expectEqualStrings("Binary:", providersDetailChromeFor(.english, "ja_JP.UTF-8").binary_prefix);
    try testing.expectEqualStrings("Path:", providersDetailChromeFor(.english, "zh_CN.UTF-8").path_prefix);
}

test "skillsEmptyChromeFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("Open a project", skillsEmptyChromeFor(.english, "ja").open_project);
    try testing.expectEqualStrings("No skills found", skillsEmptyChromeFor(.english, "").no_skills_found);
    try testing.expectEqualStrings("Open a project", skillsEmptyChromeFor(.system, "").open_project);
    try testing.expectEqualStrings("No skills found", skillsEmptyChromeFor(.system, "").no_skills_found);

    try testing.expectEqualStrings("打开项目", skillsEmptyChromeFor(.simplified_chinese, "").open_project);
    try testing.expectEqualStrings("未找到技能", skillsEmptyChromeFor(.simplified_chinese, "").no_skills_found);
    try testing.expectEqualStrings("プロジェクトを開く", skillsEmptyChromeFor(.japanese, "").open_project);
    try testing.expectEqualStrings("スキルが見つかりません", skillsEmptyChromeFor(.japanese, "").no_skills_found);

    try testing.expectEqualStrings("打开项目", skillsEmptyChromeFor(.system, "zh_CN.UTF-8").open_project);
    try testing.expectEqualStrings("未找到技能", skillsEmptyChromeFor(.system, "zh_CN.UTF-8").no_skills_found);
    try testing.expectEqualStrings("プロジェクトを開く", skillsEmptyChromeFor(.system, "ja_JP.UTF-8").open_project);
    try testing.expectEqualStrings("スキルが見つかりません", skillsEmptyChromeFor(.system, "ja_JP.UTF-8").no_skills_found);
    try testing.expectEqualStrings("Open a project", skillsEmptyChromeFor(.english, "ja_JP.UTF-8").open_project);
    try testing.expectEqualStrings("No skills found", skillsEmptyChromeFor(.english, "zh_CN.UTF-8").no_skills_found);

    try testing.expect(!std.mem.eql(u8, skillsEmptyChromeFor(.english, "").open_project, rightPanelChromeFor(.english, "").open_project_to_browse_files));
    try testing.expect(!std.mem.eql(u8, skillsEmptyChromeFor(.english, "").open_project, rightPanelChromeFor(.english, "").no_project_open));
    try testing.expect(!std.mem.eql(u8, skillsEmptyChromeFor(.simplified_chinese, "").open_project, rightPanelChromeFor(.simplified_chinese, "").open_project_to_browse_files));
    try testing.expect(!std.mem.eql(u8, skillsEmptyChromeFor(.japanese, "").open_project, rightPanelChromeFor(.japanese, "").open_project_to_browse_files));
}

