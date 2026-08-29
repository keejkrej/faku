//! Faku: Native SDK desktop for a Waku-protocol compatible coding-agent shell.
//!
//! First-party provider is Vercel `fx` (https://fx.sh). Send on an `.fx`
//! session runs one-shot `faku acp-proxy -- … fx acp` when the CLI is
//! installed (NDJSON stdin: initialize, session/new or session/resume,
//! set model/mode, session/prompt). The sidecar keeps fx stdin open and
//! auto-answers `session/request_permission` from that run's access
//! mode. Draft `image_path` still uses `fx ask --image` (ACP rejects
//! image blocks). When `WAKU_DAEMON_ADDRESS` is set, Send instead
//! spawns a one-shot `daemon-proxy` sidecar (hello + attachSession +
//! start + prompt when no runtime id; later sends keep attach + prompt).
//! Stop / Esc of that daemon turn `fx.cancel`s the prompt spawn and
//! one-shots hello + `cancel` on a distinct key. Missing address /
//! image / ACP stdin overflow keep `fx ask` or the demo timer. This
//! is not a long-lived ACP or daemon runtime loop — Native stdin is
//! one buffer, then it closes. The ACP sidecar owns the child stdin.

const std = @import("std");
const runner = @import("runner");
const native_sdk = @import("native_sdk");
const protocol = @import("protocol.zig");
const acp = @import("acp.zig");
const store = @import("store.zig");
const daemon_proxy = @import("daemon_proxy.zig");
const acp_proxy = @import("acp_proxy.zig");
const maximize_window = @import("maximize_window.zig");
const rewind = @import("rewind.zig");
const keys = @import("keys.zig");
const palette = @import("palette.zig");
const sidebar_dates = @import("sidebar_dates.zig");
const goal = @import("goal.zig");
const composer = @import("composer.zig");
const copy_helpers = @import("copy.zig");
const session_switcher = @import("switcher.zig");
const sidebar_row_helpers = @import("sidebar_rows.zig");
const attach_helpers = @import("attach.zig");
const session_fork = @import("fork.zig");
const prompt_spawn = @import("spawn.zig");
const turn_stream = @import("stream.zig");
const sidecar_lines = @import("lines.zig");
const fx_probe = @import("fx_probe.zig");
const palette_run = @import("palette_run.zig");
const persist = @import("persist.zig");
const session_actions = @import("session_actions.zig");
const settings_actions = @import("settings_actions.zig");
const session_mod = @import("session.zig");
const model_mod = @import("model.zig");
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
const file_mention = @import("file_mention.zig");
const util = @import("util.zig");
const pick_folder = @import("pick_folder.zig");
const reveal_folder = @import("reveal_folder.zig");
const open_terminal = @import("open_terminal.zig");
const open_editor = @import("open_editor.zig");

pub const panic = std.debug.FullPanic(native_sdk.debug.capturePanic);

const canvas = native_sdk.canvas;
const geometry = native_sdk.geometry;

const canvas_label = "main-canvas";
/// Declared shell-window label. Chromeless close/minimize ride
/// `fx.closeWindow` / `fx.minimizeWindow` against this spelling —
/// same address as `app.zon` / the scene. Unknown label is a no-op.
/// Maximize is an OS sidecar (`maximize_window.zig`); Native still
/// has no `fx.maximizeWindow`.
pub const main_window_label = "main";
pub const window_width: f32 = 1380;
pub const window_height: f32 = 880;
pub const window_min_width: f32 = 560;
pub const window_min_height: f32 = 480;
pub const sidebar_default_width: f32 = 252;
pub const sidebar_min_width: f32 = 180;
pub const sidebar_max_width: f32 = 420;
pub const sidebar_rail_width: f32 = 48;
pub const max_sessions = model_mod.max_sessions;
/// Sidebar folder-header keys sit above session ids so `for` keys stay unique.
pub const folder_row_id_base: u32 = 1_000_000;
/// Date-bucket header keys sit above folder headers.
pub const date_row_id_base = sidebar_row_helpers.date_row_id_base;
/// In-memory session selection history for sidebar Back / Forward.
pub const selection_history_cap = model_mod.selection_history_cap;
/// Runtime-only Ctrl-Tab switcher snapshot. Same cap as Waku's overlay.
pub const switcher_cap = session_switcher.switcher_cap;
pub const palette_action_id_base = palette.palette_action_id_base;
pub const palette_header_id_base = palette.palette_header_id_base;
pub const palette_max_task_results = palette.palette_max_task_results;
pub const palette_result_row_height = palette.palette_result_row_height;
pub const palette_search_row_height = palette.palette_search_row_height;
pub const palette_section_header_height = palette.palette_section_header_height;
pub const palette_card_width = palette.palette_card_width;
pub const palette_card_height = palette.palette_card_height;
pub const max_turns = model_mod.max_turns;
pub const max_title = session_mod.max_title;
pub const max_body = model_mod.max_body;
pub const max_draft = model_mod.max_draft;
pub const max_queued = model_mod.max_queued;
pub const max_queued_text = model_mod.max_queued_text;
pub const max_fx_path = model_mod.max_fx_path;
pub const max_store_dir = model_mod.max_store_dir;
pub const max_project_path = session_mod.max_project_path;
pub const max_attach_status = model_mod.max_attach_status;
pub const max_fx_session_id = session_mod.max_fx_session_id;
pub const max_tool_call_id = model_mod.max_tool_call_id;
pub const max_tool_kind = model_mod.max_tool_kind;
pub const max_tool_status = model_mod.max_tool_status;
pub const max_runtime_id = session_mod.max_runtime_id;
pub const max_fx_model = session_mod.max_fx_model;
pub const max_access_mode = session_mod.max_access_mode;
pub const max_interaction_mode = session_mod.max_interaction_mode;
pub const max_reasoning_effort = session_mod.max_reasoning_effort;
/// Codex `ThreadGoal.objective`. Same cap as the composer draft.
pub const max_thread_goal_objective = session_mod.max_thread_goal_objective;
/// Codex `ThreadGoalStatus` wire name (`budgetLimited` is 13).
pub const max_thread_goal_status = session_mod.max_thread_goal_status;
/// Compact `12k/100k · 3m` meter on the composer goal row.
pub const max_thread_goal_usage_label = session_mod.max_thread_goal_usage_label;
pub const max_available_commands = session_mod.max_available_commands;
pub const max_model_options = session_mod.max_model_options;
pub const max_command_name = session_mod.max_command_name;
pub const max_command_description = session_mod.max_command_description;
/// Waku `runtime_mode` default. Maps to fx `FX_PERMISSION_MODE=yolo`.
pub const default_access_mode = "fullAccess";
/// Waku `StartOptions.interaction_mode` default (`build` | `plan`).
pub const default_interaction_mode = "build";
/// fx documented `effort` default (`auto` | `none` | `minimal` | `low` |
/// `medium` | `high` | `xhigh` | `max`).
pub const default_reasoning_effort = "auto";
pub const fx_env_bin = "/usr/bin/env";
pub const max_line_keep = 4096;

const app_permissions = [_][]const u8{ native_sdk.security.permission_command, native_sdk.security.permission_view };
const shell_views = [_]native_sdk.ShellView{
    .{ .label = canvas_label, .kind = .gpu_surface, .fill = true, .role = "Faku canvas", .accessibility_label = "Faku", .gpu_backend = .metal, .gpu_pixel_format = .bgra8_unorm, .gpu_present_mode = .timer, .gpu_alpha_mode = .@"opaque", .gpu_color_space = .srgb, .gpu_vsync = true },
};
const shell_windows = [_]native_sdk.ShellWindow{.{
    .label = main_window_label,
    .title = "Faku",
    .width = window_width,
    .height = window_height,
    .min_width = window_min_width,
    .min_height = window_min_height,
    .titlebar = .hidden_inset_tall,
    .views = &shell_views,
}};
pub const shell_scene: native_sdk.ShellConfig = .{ .windows = &shell_windows };

/// Chromeless Minimize bar. The built-in icon set has no minus
/// (`examples/deck`); Native check rejects an invented `icon="minus"`.
const minimize_icon = canvas.svg_icon.parseComptime(@embedFile("icons/minimize.svg"));

/// Chromeless Maximize square. Native has no `fx.maximizeWindow`
/// and no built-in maximize glyph.
const maximize_icon = canvas.svg_icon.parseComptime(@embedFile("icons/maximize.svg"));

/// Composer Stop square. Native has no built-in stop/square
/// (https://native-sdk.dev/components/icon).
const stop_icon = canvas.svg_icon.parseComptime(@embedFile("icons/stop.svg"));

/// One table feeds boot registration and the model contract so
/// `icon="app:minimize"` / `icon="app:maximize"` / `icon="app:stop"`
/// are verified against what `main` registers.
pub const app_icons = [_]canvas.icons.Entry{
    .{ .name = "minimize", .icon = &minimize_icon },
    .{ .name = "maximize", .icon = &maximize_icon },
    .{ .name = "stop", .icon = &stop_icon },
};

/// Install the app icon table once, before views build.
pub fn registerIcons() void {
    canvas.icons.registerAppIcons(&app_icons);
}

pub const stream_timer_key: u64 = 1;
pub const fx_ask_key: u64 = 2;
pub const fx_probe_key = fx_probe.fx_probe_key;
pub const daemon_proxy_key_first: u64 = 4;
/// Overlapping one-shot `fx acp` / `fx ask` children (queue drain while
/// the previous process has not exited yet). Avoids probe/daemon keys.
pub const fx_spawn_overlap_key_first: u64 = 64;
pub const acp_cwd_fallback = ".";
pub const max_daemon_address = model_mod.max_daemon_address;
pub const max_daemon_token = model_mod.max_daemon_token;
pub const max_sidecar_path = model_mod.max_sidecar_path;
pub const daemon_line_bytes: usize = 64 * 1024;
pub const stream_interval_ms: u64 = 90;
pub const stream_chunk_bytes: usize = 8;
/// Overshoot for a programmatic jump to the transcript end. Native
/// clamps `scroll` `value` against the content edge
/// (`content_extent_y - viewport_extent_y`), so a large source offset
/// lands on the newest turn after layout. Verified: native-sdk.dev
/// scroll docs + engine clamp.
pub const transcript_pin_offset: f32 = 1_000_000;
/// One-shot OS maximize sidecar (`osascript` / `wmctrl` / `xdotool`).
/// Distinct from fx ask / daemon / picker / clipboard keys. Native
/// still has no `fx.maximizeWindow`; this spawn is the workaround.
pub const maximize_window_key = maximize_window.maximize_window_key;
/// One-shot OS image-picker sidecar (`osascript` / `zenity` / `kdialog`).
/// Distinct from fx ask / daemon / clipboard / preview keys. Native has
/// no `fx.pickFile`; this spawn is the documented workaround.
pub const pick_image_key = attach_helpers.pick_image_key;
/// One-shot OS folder-picker sidecar (`osascript` / `zenity` / `kdialog`).
/// Distinct from pick_image (31), maximize (30), copy_turn (32). Native
/// has no `fx.pickFile`; this spawn is the documented workaround.
pub const pick_folder_key = pick_folder.pick_folder_key;
/// One-shot OS file-manager sidecar (`open` / `xdg-open`). Distinct from
/// pick_folder (29), maximize (30), pick_image (31), copy_turn (32).
/// Native has no typed `fx.revealPath` on this Effects revision.
pub const reveal_folder_key = reveal_folder.reveal_folder_key;
/// One-shot OS terminal sidecar (`open -a Terminal` / `x-terminal-emulator`).
/// Distinct from reveal_folder (28), pick_folder (29), maximize (30),
/// pick_image (31), copy_turn (32). Native has no typed open-terminal
/// effect on this Effects revision.
pub const open_terminal_key = open_terminal.open_terminal_key;
/// One-shot OS editor sidecar (`cursor` / `code`, macOS `open -a`).
/// Distinct from open_terminal (27), reveal_folder (28), pick_folder (29),
/// maximize (30), pick_image (31), copy_turn (32). Native has no typed
/// open-editor effect on this Effects revision.
pub const open_editor_key = open_editor.open_editor_key;
/// One-shot `git branch --show-current` probe. Distinct from maximize /
/// pick-image / fx-ask / daemon / clipboard / probe keys, from
/// git_branch_list (250+), git_checkout (275+), and from
/// git_dirty (300+). Incremented per refresh from
/// `git_branch_key_first`.
pub const git_branch_key_first = git_branch.git_branch_key_first;
/// One-shot `refs/heads` + `refs/remotes` list. Distinct from
/// git_branch (200+), git_checkout (275+; also `--track`), git_dirty
/// (300+), git_numstat (350+), git_push (360+), git_ahead_behind
/// (380+), and file_mention (400+).
pub const git_branch_list_key_first = git_checkout.git_branch_list_key_first;
/// One-shot `git checkout <name>`. Distinct from git_branch (200+),
/// git_branch_list (250+), git_create (290+), git_dirty (300+),
/// git_numstat (350+), git_push (360+), git_ahead_behind (380+),
/// and file_mention (400+).
pub const git_checkout_key_first = git_checkout.git_checkout_key_first;
/// One-shot `git checkout -b <name>`. Distinct from list (250+),
/// checkout (275+), git_dirty (300+). Band is 290+.
pub const git_create_key_first = git_checkout.git_create_key_first;
/// One-shot `git branch -d <name>`. Distinct from create (290+),
/// git_dirty (300+), git_fetch (340+), git_numstat (350+), and
/// git_push (360+). Band is 320+.
pub const git_delete_key_first = git_checkout.git_delete_key_first;
/// One-shot `git fetch --prune`. Distinct from delete (320+) and
/// git_numstat (350+). Band is 340+.
pub const git_fetch_key_first = git_checkout.git_fetch_key_first;
/// One-shot `git push` (bare or `--set-upstream`) plus the probes
/// that choose the path. Distinct from fetch (340+), git_numstat
/// (350+), git_worktree_add (370+), git_ahead_behind (380+), and
/// file_mention (400+). Band is 360+.
pub const git_push_key_first = git_checkout.git_push_key_first;
/// One-shot `git worktree add -b`. Distinct from push (360+),
/// git_ahead_behind (380+), git_worktree_base (390+), and
/// file_mention (400+). Band is 370+.
pub const git_worktree_add_key_first = git_checkout.git_worktree_add_key_first;
/// One-shot `git rev-list --left-right --count @{upstream}...HEAD`.
/// Distinct from git_worktree_add (370+), git_worktree_base (390+),
/// and file_mention (400+). Band is 380+. Incremented per refresh
/// from `git_ahead_behind_key_first`.
pub const git_ahead_behind_key_first = git_ahead_behind.git_ahead_behind_key_first;
/// One-shot `git symbolic-ref --quiet --short refs/remotes/origin/HEAD`
/// for New worktree… base. Distinct from git_ahead_behind (380+)
/// and file_mention (400+). Band is 390+.
pub const git_worktree_base_key_first = git_checkout.git_worktree_base_key_first;
/// One-shot `git status --porcelain` dirty count. Distinct from
/// git_branch (200+), git_branch_list (250+), git_checkout (275+),
/// git_create (290+), git_delete (320+), git_fetch (340+),
/// git_numstat (350+), git_push (360+), git_ahead_behind (380+),
/// and file_mention (400+). Incremented per refresh from
/// `git_dirty_key_first`.
pub const git_dirty_key_first = git_dirty.git_dirty_key_first;
/// One-shot `git diff --numstat HEAD --` +/- plus untracked text-line
/// additions. Distinct from git_branch (200+), git_dirty (300+),
/// git_push (360+), git_ahead_behind (380+), and file_mention (400+).
/// Incremented per refresh from `git_numstat_key_first`.
pub const git_numstat_key_first = git_numstat.git_numstat_key_first;
/// One-shot file-mention probe (git ls-files, then a bounded walk
/// when git cannot list) for composer `@` mentions. Distinct from
/// git_branch (200+), git_dirty (300+), git_numstat (350+),
/// git_push (360+), git_worktree_add (370+), git_ahead_behind
/// (380+), and git_worktree_base (390+). Incremented per spawn
/// from `file_mention_key_first` (400).
pub const file_mention_key_first = file_mention.file_mention_key_first;
/// One-shot `git add -A -- .` then `git commit -m`. Distinct from
/// file_mention (400+); band is 450+ so it does not sit on 400–409.
/// Incremented per spawn from `git_commit_key_first`.
pub const git_commit_key_first = git_commit.git_commit_key_first;
/// One-shot CommitSnapshot numstat on the Commit… card (include-
/// unstaged reuses the project-row script; off is `--cached`).
/// Distinct from add/commit (450+) and project-row keys (350+).
/// Band is 460+. Incremented per probe from
/// `git_commit_numstat_key_first`.
pub const git_commit_numstat_key_first = git_commit.git_commit_numstat_key_first;
/// One-shot empty-message `fx ask` generate on the Commit… card.
/// Distinct from add/commit (450+) and CommitSnapshot numstat (460+).
/// Band is 470+. Incremented per spawn from
/// `git_commit_generate_key_first`.
pub const git_commit_generate_key_first = git_commit.git_commit_generate_key_first;
/// One-shot `git remote` for first-push remotes. Distinct from
/// generate (470+) and git_push remotes (360+). Band is 480+.
/// Incremented per refresh from `git_remotes_key_first`.
pub const git_remotes_key_first = git_remotes.git_remotes_key_first;
/// One-shot `git rev-parse --show-toplevel`. Distinct from remotes
/// (480+). Band is 490+. Incremented per refresh from
/// `git_toplevel_key_first`.
pub const git_toplevel_key_first = git_toplevel.git_toplevel_key_first;
/// One-shot `git rev-parse --git-common-dir`. Distinct from
/// toplevel (490+). Band is 500+. Incremented per refresh from
/// `git_common_dir_key_first`.
pub const git_common_dir_key_first = git_common_dir.git_common_dir_key_first;
pub const copy_turn_key = copy_helpers.copy_turn_key;
/// Empty `fx_session_id` / ACP sessionId: do not writeClipboard.
pub const no_provider_session_id_status = copy_helpers.no_provider_session_id_status;
/// Caller-chosen ImageId for the composer attach preview. `fx.loadImage`
/// uses this as the effect key (shared with spawn / clipboard / file).
/// 0 is the no-image sentinel. Sits in the gap after `copy_turn_key`
/// and before `fx_spawn_overlap`. Verified: Native 0.9.3
/// `LoadImageOptions` + markup `<image image="{binding}">`.
pub const attach_preview_id_first = attach_helpers.attach_preview_id_first;
pub const attach_preview_id_last = attach_helpers.attach_preview_id_last;
pub const demo_ticks_complete: u32 = 12;
pub const demo_reply = "fx here (demo). The fx CLI was not found, so this is a local timer stream. Install fx and Send runs `fx ask`.";
/// Desktop notification title when the session has no stored title.
pub const notify_fallback_title = copy_helpers.notify_fallback_title;
/// Desktop notification body when the last assistant turn is empty.
pub const notify_fallback_body = copy_helpers.notify_fallback_body;
/// Short body cap. Native allows 1024; keep the toast readable.
pub const notify_body_max = copy_helpers.notify_body_max;

pub const Mode = model_mod.Mode;
pub const Role = model_mod.Role;
pub const Phase = model_mod.Phase;
pub const ReplyPath = model_mod.ReplyPath;

pub const Provider = session_mod.Provider;
pub const AvailableCommand = session_mod.AvailableCommand;
pub const ModelOption = session_mod.ModelOption;
pub const Session = session_mod.Session;

pub const Turn = model_mod.Turn;
pub const Folder = model_mod.Folder;
pub const SessionRow = model_mod.SessionRow;
pub const SidebarRow = model_mod.SidebarRow;

pub const DateBucket = sidebar_dates.DateBucket;
pub const sessionDateBucket = sidebar_dates.sessionDateBucket;
pub const sessionRelativeTime = sidebar_dates.sessionRelativeTime;
pub const formatThreadGoalUsage = goal.formatThreadGoalUsage;

pub const AssignFolder = model_mod.AssignFolder;
pub const TurnRow = model_mod.TurnRow;
pub const CommandRow = model_mod.CommandRow;
pub const ModelPickerRow = model_mod.ModelPickerRow;
pub const ChipPickerRow = model_mod.ChipPickerRow;

pub const fxPermissionMode = composer.fxPermissionMode;
pub const startOptionsFromSession = prompt_spawn.startOptionsFromSession;
pub const takeFxAskSessionId = prompt_spawn.takeFxAskSessionId;
pub const stripFxDiagnostics = sidecar_lines.stripFxDiagnostics;
pub const nextAccessMode = composer.nextAccessMode;
pub const accessLabel = composer.accessLabel;
pub const nextReasoningEffort = composer.nextReasoningEffort;
pub const effortLabel = composer.effortLabel;
pub const imagePathFromDrop = composer.imagePathFromDrop;

pub const PaletteRow = palette.PaletteRow;
pub const PaletteAction = palette.PaletteAction;
pub const PaletteActionSpec = palette.PaletteActionSpec;
pub const paletteActionId = palette.paletteActionId;

pub const QueuedMessage = model_mod.QueuedMessage;
pub const QueuedRow = model_mod.QueuedRow;
pub const Msg = model_mod.Msg;
pub const Model = model_mod.Model;

pub const writeFixed = session_mod.writeFixed;

pub const sessionDisplayTitle = util.sessionDisplayTitle;
pub const stampSessionActivity = util.stampSessionActivity;
pub const asciiContainsIgnoreCase = util.asciiContainsIgnoreCase;
pub const directoryExists = util.directoryExists;
pub const fileExists = util.fileExists;
/// Native `SpawnOptions` (0.9.3) has no `cwd`. `std.process.spawn` does, but
/// Effects does not expose it. `cd` + `exec` is a real child cwd, not `PWD`.
pub const fx_ask_chdir_script = util.fx_ask_chdir_script;

pub const Effects = native_sdk.Effects(Msg);

pub const applySessionSelection = palette_run.applySessionSelection;

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
        // switcher / Environment dropdown / command palette / settings / transcript-find / project-edit /
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
        },
        .composer_enter => {
            if (model.commands_list_open() or model.mentions_list_open()) {
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
        .toggle_settings => settings_actions.handleToggleSettings(model),
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
        .environment_copy_task_id => environment_summary.copyTaskId(model, fx),
        .git_commit_edit => |edit| settings_actions.handleGitCommitEdit(model, edit),
        .confirm_git_commit => settings_actions.handleConfirmGitCommit(model, fx),
        .confirm_git_commit_and_push => settings_actions.handleConfirmGitCommitAndPush(model, fx),
        .confirm_git_commit_push => settings_actions.handleConfirmGitCommitPush(model, fx),
        .cancel_git_commit => settings_actions.handleCancelGitCommit(model, fx),
        .toggle_git_commit_include_unstaged => settings_actions.handleToggleGitCommitIncludeUnstaged(model, fx),
        .toggle_git_commit_amend => settings_actions.handleToggleGitCommitAmend(model, fx),
        .start_project_edit => {
            git_commit.dropCommitNumstat(model, fx);
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
        .sidebar_resized => |fraction| {
            sidebar_row_helpers.applySidebarResize(model, fraction);
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
    }
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

pub const startFxProbe = fx_probe.startFxProbe;

/// Native `UiApp.Options.on_drop` → Msg. Window-level; no OS picker.
pub const onDrop = attach_helpers.onDrop;

/// Keep custom Geist tokens in lockstep with the OS light/dark flip.
pub fn onAppearance(appearance: native_sdk.platform.Appearance) ?Msg {
    return .{ .appearance_changed = appearance };
}

/// Geist pack with anti-aliased edges. Geometry pixel-snap makes 1x
/// rounded rects and the send circle stair-step; signed-distance
/// coverage stays on when snapping is off. Slightly larger radii match
/// Waku's 13px composer card.
pub fn designTokens(model: *const Model) canvas.DesignTokens {
    const contrast: canvas.ColorContrast = if (model.appearance.high_contrast) .high else .standard;
    const scheme: canvas.ColorScheme = switch (model.appearance.color_scheme) {
        .light => .light,
        .dark => .dark,
    };
    return canvas.DesignTokens.themeWithOverrides(.{
        .pack = .house,
        .color_scheme = scheme,
        .contrast = contrast,
        .reduce_motion = model.appearance.reduce_motion,
    }, .{
        .pixel_snap = .{ .geometry = false },
    });
}

pub const AppUi = canvas.Ui(Msg);
pub const app_markup = @embedFile("app.native");

const FakuApp = native_sdk.UiApp(Model, Msg);

pub fn initialModel() Model {
    var model = Model{};
    const port = model.addSession("port waku to zig", .fx);
    _ = model.appendTurn(port, .user, "replace the GPUI desktop with a Native SDK Zig shell");
    _ = model.appendTurn(port, .assistant, "fx-first demo: sidebar, transcript, composer. Send runs `fx ask` when the CLI is installed.");

    const auth = model.addSession("fix auth listener", .claude);
    _ = model.appendTurn(auth, .user, "the auth listener drops the first event after reconnect");
    _ = model.appendTurn(auth, .assistant, "I will inspect the reconnect path and replay the last event.");
    _ = model.appendTurn(auth, .tool, "read src/auth/listener.ts");
    _ = model.appendTurn(auth, .assistant, "The handler unsubscribes before the replay buffer is flushed.");

    model.selected = port;
    model.pushSelectionHistory(port);
    model.pinTranscriptToLatest();
    if (model.sessionById(port)) |session| {
        session.has_started = true;
        session.detail_loaded = true;
    }
    if (model.sessionById(auth)) |session| {
        session.has_started = true;
        session.detail_loaded = true;
    }
    return model;
}

pub fn main(init: std.process.Init) !void {
    if (try daemon_proxy.maybeRun(init)) return;
    if (try acp_proxy.maybeRun(init)) return;
    _ = protocol.FX_ACP_ARGV;
    _ = acp.PROTOCOL_VERSION;
    registerIcons();
    const app_state = try FakuApp.create(std.heap.page_allocator, .{
        .name = "faku",
        .scene = shell_scene,
        .canvas_label = canvas_label,
        .update_fx = update,
        .init_fx = initFx,
        .on_key = keys.onKey,
        .on_drop = onDrop,
        .on_appearance = onAppearance,
        .tokens_fn = designTokens,
        .markup = .{ .source = app_markup, .watch_path = "src/app.native", .io = init.io },
    });
    defer app_state.destroy();
    app_state.model = initialModel();
    if (init.environ_map.get("HOME")) |home| {
        app_state.model.setHome(home);
        store.bindDefaultDir(&app_state.model, home, init.environ_map.get("XDG_DATA_HOME"));
    }
    util.bindDaemonEnv(&app_state.model, init);
    _ = store.boot(&app_state.model, std.heap.page_allocator, init.io);
    if (init.environ_map.get(protocol.DAEMON_ADDRESS_ENV)) |addr| {
        app_state.model.setDaemonAddress(addr);
    }

    try runner.runWithOptions(app_state.app(), .{
        .app_name = "faku",
        .window_title = "Faku",
        .bundle_id = "com.faku.app",
        .icon_path = "assets/icon.png",
        .default_frame = geometry.RectF.init(0, 0, window_width, window_height),
        .js_window_api = false,
        .security = .{
            .permissions = &app_permissions,
            .navigation = .{ .allowed_origins = &.{ "zero://inline", "zero://app" } },
        },
    }, init);
}

test {
    _ = @import("tests.zig");
    _ = @import("protocol.zig");
    _ = @import("acp.zig");
    _ = @import("store.zig");
    _ = @import("daemon_proxy.zig");
    _ = @import("acp_proxy.zig");
    _ = @import("pick_image.zig");
    _ = @import("pick_folder.zig");
    _ = @import("reveal_folder.zig");
    _ = @import("open_terminal.zig");
    _ = @import("open_editor.zig");
    _ = @import("maximize_window.zig");
    _ = @import("rewind.zig");
    _ = @import("keys.zig");
    _ = @import("palette.zig");
    _ = @import("sidebar_dates.zig");
    _ = @import("goal.zig");
    _ = @import("composer.zig");
    _ = @import("copy.zig");
    _ = @import("switcher.zig");
    _ = @import("sidebar_rows.zig");
    _ = @import("attach.zig");
    _ = @import("fork.zig");
    _ = @import("spawn.zig");
    _ = @import("stream.zig");
    _ = @import("lines.zig");
    _ = @import("fx_probe.zig");
    _ = @import("palette_run.zig");
    _ = @import("persist.zig");
    _ = @import("session_actions.zig");
    _ = @import("settings_actions.zig");
    _ = @import("session.zig");
    _ = @import("model.zig");
    _ = @import("git_branch.zig");
    _ = @import("git_checkout.zig");
    _ = @import("git_dirty.zig");
    _ = @import("git_numstat.zig");
    _ = @import("git_ahead_behind.zig");
    _ = @import("git_remotes.zig");
    _ = @import("git_toplevel.zig");
    _ = @import("git_common_dir.zig");
    _ = @import("file_mention.zig");
    _ = @import("environment_summary.zig");
    _ = @import("util.zig");
}
