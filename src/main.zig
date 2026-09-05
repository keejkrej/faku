//! Faku: Native SDK desktop for a Waku-protocol compatible coding-agent shell.
//!
//! First-party provider is the keejkrej/fx fork (https://github.com/keejkrej/fx). Send on an `.fx`
//! session runs one-shot `faku acp-proxy -- … fx acp` when the CLI is
//! installed (NDJSON stdin: initialize, session/new or session/resume,
//! set model/mode, session/prompt). The sidecar keeps fx stdin open and
//! auto-answers `session/request_permission` from that run's access
//! mode. Draft `image_path` still uses `fx ask --image` (ACP rejects
//! image blocks). After the fx branch, probed ACP stdio providers
//! (cursor / opencode / kimi `acp`, grok `agent stdio`) use the same acp-proxy
//! path when `--help` is available, including first-cut official ACP
//! v1 image content blocks on `session/prompt` when a composer image
//! is attached (base64 + mimeType; overflow / bad file fail closed to
//! demo); Available Claude uses one-shot
//! print-mode stream-json (`claude -p --output-format stream-json
//! --verbose --include-partial-messages --forward-subagent-text`,
//! not ACP), with documented
//! `--resume {fx_session_id}` on later Sends when that field is
//! non-empty (first Send and Fork omit it; not `--continue`), and
//! with the documented image path inside that `-p` prompt when a
//! composer image is attached (code.claude.com/docs/en/common-workflows;
//! stdout is NDJSON: live `text_delta` into the transcript, not a
//! prose dump; non-empty `parent_tool_use_id` is subagent traffic
//! (forwarded text fills a bounded 512KB last-window on that
//! Subagent Background row; still off the main turn);
//! `tool_use` with `name` `Monitor` fills live Monitor Background;
//! matching user `tool_result` fills a bounded 512KB last-window
//! log on that row (newlines kept; CSI stripped for display;
//! Environment Summary stays a one-line preview); Available Codex uses one-shot `codex exec {prompt}` (not ACP), with
//! documented `--image {path}` after the prompt when a composer image
//! is attached; Available Amp uses one-shot `amp -x {prompt}` (not ACP),
//! with a documented `@{path}` mention in that `-x` prompt when a
//! composer image is attached; Available Pi uses one-shot
//! `pi --mode json {prompt}` (not ACP, not `--mode rpc`), with
//! documented `@{path}` after `--mode json` when a composer image
//! is attached (stdout is JSON events: live `text_delta` into the
//! transcript, not a prose dump); cursor / opencode / kimi / grok image
//! attach uses ACP image content blocks (not `fx ask --image`).
//! When `WAKU_DAEMON_ADDRESS` is set, Send instead
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
const prompt_spawn = @import("spawn.zig");
const sidecar_lines = @import("lines.zig");
const fx_probe = @import("fx_probe.zig");
const cli_probe = @import("cli_probe.zig");
const palette_run = @import("palette_run.zig");
const update_mod = @import("update.zig");
const boot_mod = @import("boot.zig");
const shell_mod = @import("shell.zig");
const layout_mod = @import("layout.zig");
const effect_keys = @import("effect_keys.zig");
const session_mod = @import("session.zig");
const model_mod = @import("model.zig");
const i18n = @import("i18n.zig");
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
const right_panel = @import("right_panel.zig");
const review_diff = @import("review_diff.zig");
const file_mention = @import("file_mention.zig");
const skills = @import("skills.zig");
const util = @import("util.zig");
const pick_folder = @import("pick_folder.zig");
const reveal_folder = @import("reveal_folder.zig");
const open_terminal = @import("open_terminal.zig");
const open_url = @import("open_url.zig");
const open_editor = @import("open_editor.zig");

pub const panic = std.debug.FullPanic(native_sdk.debug.capturePanic);

const canvas = native_sdk.canvas;
const geometry = native_sdk.geometry;

const canvas_label = shell_mod.canvas_label;
pub const main_window_label = shell_mod.main_window_label;
pub const window_width = shell_mod.window_width;
pub const window_height = shell_mod.window_height;
pub const window_min_width = shell_mod.window_min_width;
pub const window_min_height = shell_mod.window_min_height;
pub const sidebar_default_width = layout_mod.sidebar_default_width;
pub const sidebar_min_width = layout_mod.sidebar_min_width;
pub const sidebar_max_width = layout_mod.sidebar_max_width;
pub const sidebar_rail_width = layout_mod.sidebar_rail_width;
pub const right_panel_default_width = layout_mod.right_panel_default_width;
pub const right_panel_min_width = layout_mod.right_panel_min_width;
pub const right_panel_max_width = layout_mod.right_panel_max_width;
pub const right_panel_diff_default_width = layout_mod.right_panel_diff_default_width;
pub const right_panel_diff_max_width = layout_mod.right_panel_diff_max_width;
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
pub const shell_scene = shell_mod.shell_scene;
pub const app_icons = shell_mod.app_icons;
pub const registerIcons = shell_mod.registerIcons;

pub const stream_timer_key = effect_keys.stream_timer_key;
pub const fx_ask_key = effect_keys.fx_ask_key;
pub const fx_probe_key = fx_probe.fx_probe_key;
pub const daemon_proxy_key_first = effect_keys.daemon_proxy_key_first;
pub const fx_spawn_overlap_key_first = effect_keys.fx_spawn_overlap_key_first;
pub const acp_cwd_fallback = effect_keys.acp_cwd_fallback;
pub const max_daemon_address = model_mod.max_daemon_address;
pub const max_daemon_token = model_mod.max_daemon_token;
pub const max_sidecar_path = model_mod.max_sidecar_path;
pub const daemon_line_bytes = effect_keys.daemon_line_bytes;
pub const stream_interval_ms = effect_keys.stream_interval_ms;
pub const stream_chunk_bytes = effect_keys.stream_chunk_bytes;
pub const transcript_pin_offset = effect_keys.transcript_pin_offset;
/// One-shot OS maximize sidecar (`osascript` / `wmctrl` / `xdotool`).
/// Distinct from fx ask / daemon / picker / clipboard keys. Native
/// still has no `fx.maximizeWindow`; this spawn is the workaround.
pub const maximize_window_key = maximize_window.maximize_window_key;
/// One-shot OS image-picker sidecar (`osascript` / `zenity` / `kdialog` /
/// Windows `powershell.exe` OpenFileDialog). Distinct from fx ask / daemon /
/// clipboard / preview keys. Native has no `fx.pickFile`; this spawn is the
/// documented workaround.
pub const pick_image_key = attach_helpers.pick_image_key;
/// One-shot OS folder-picker sidecar (`osascript` / `zenity` / `kdialog` /
/// Windows `powershell.exe` FolderBrowserDialog). Distinct from pick_image
/// (31), maximize (30), copy_turn (32). Native has no `fx.pickFile`; this
/// spawn is the documented workaround.
pub const pick_folder_key = pick_folder.pick_folder_key;
/// One-shot OS file-manager sidecar (`open` / `xdg-open` / Windows `explorer.exe`). Distinct from
/// pick_folder (29), maximize (30), pick_image (31), copy_turn (32).
/// Native has no typed `fx.revealPath` on this Effects revision.
pub const reveal_folder_key = reveal_folder.reveal_folder_key;
/// One-shot OS URL-open sidecar (`open` / `xdg-open` / Windows
/// `cmd.exe /c start`). Distinct from open_editor (26), open_terminal
/// (27), reveal_folder (28). Native has no documented webview effect
/// on this cut.
pub const open_url_key = open_url.open_url_key;
/// One-shot OS terminal sidecar (`open -a Terminal` / `x-terminal-emulator` /
/// Windows `wt.exe -d` then `cmd.exe /c start "" /D`). Distinct from
/// reveal_folder (28), pick_folder (29), maximize (30), pick_image (31),
/// copy_turn (32). Native has no typed open-terminal effect on this
/// Effects revision.
pub const open_terminal_key = open_terminal.open_terminal_key;
/// One-shot OS editor sidecar (`cursor` / `code`, macOS `open -a`, Windows `cursor.cmd` / `code.cmd`).
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
/// One-shot Branch `git diff --name-status @{upstream}...HEAD` for
/// the Environment Compare Review card. Distinct from common-dir
/// (500+). Band is 510+. Incremented per open from
/// `review_diff_key_first`.
pub const review_diff_key_first = review_diff.review_diff_key_first;
/// One-shot Review `git diff [operand] -- <path>` hunk probe.
/// Distinct from name-status 510+. Band is 520+. Incremented
/// per file click from `review_diff_hunk_key_first`.
pub const review_diff_hunk_key_first = review_diff.review_diff_hunk_key_first;
/// One-shot Settings Skills `find` for `SKILL.md`. Distinct from
/// review hunk (520+). Band is 530+. Incremented per scan from
/// `skills_key_first`.
pub const skills_key_first = skills.skills_key_first;
/// One-shot Settings Providers non-fx `{binary} --help` probes.
/// Distinct from skills (530+). Band is 600+ `@intFromEnum(id)`
/// so claude=601 … kimi=608. fx stays on `fx_probe_key` (3).
pub const cli_probe_key_first = cli_probe.cli_probe_key_first;
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
pub const DaemonDirBrowserRow = model_mod.DaemonDirBrowserRow;

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
pub const BackgroundRow = environment_summary.BackgroundRow;
pub const RightPanelFileRow = model_mod.RightPanelFileRow;
pub const FilePreviewLineRow = right_panel.FilePreviewLineRow;
pub const SkillRow = model_mod.SkillRow;
pub const ProviderRow = model_mod.ProviderRow;
pub const Msg = model_mod.Msg;
pub const Model = model_mod.Model;
pub const ThemePreference = model_mod.ThemePreference;
pub const LanguagePreference = i18n.LanguagePreference;

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

pub const update = update_mod.update;
pub const initFx = update_mod.initFx;
pub const initialModel = boot_mod.initialModel;
pub const onAppearance = boot_mod.onAppearance;
pub const resolvedColorScheme = boot_mod.resolvedColorScheme;
pub const designTokens = boot_mod.designTokens;

pub const startFxProbe = fx_probe.startFxProbe;

/// Native `UiApp.Options.on_drop` → Msg. Window-level; no OS picker.
pub const onDrop = attach_helpers.onDrop;

pub const AppUi = canvas.Ui(Msg);
pub const app_markup = @embedFile("app.native");

const FakuApp = native_sdk.UiApp(Model, Msg);

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
    app_state.model.setSystemLocaleId(i18n.pickSystemLocaleId(
        init.environ_map.get("LC_ALL") orelse "",
        init.environ_map.get("LC_MESSAGES") orelse "",
        init.environ_map.get("LANG") orelse "",
    ));
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
    _ = @import("open_url.zig");
    _ = @import("open_editor.zig");
    _ = @import("right_panel.zig");
    _ = @import("maximize_window.zig");
    _ = @import("rewind.zig");
    _ = @import("checkpoint.zig");
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
    _ = @import("cli_probe.zig");
    _ = @import("palette_run.zig");
    _ = @import("persist.zig");
    _ = @import("session_actions.zig");
    _ = @import("settings_actions.zig");
    _ = @import("update.zig");
    _ = @import("boot.zig");
    _ = @import("shell.zig");
    _ = @import("layout.zig");
    _ = @import("effect_keys.zig");
    _ = @import("session.zig");
    _ = @import("session_workspace.zig");
    _ = @import("model.zig");
    _ = @import("i18n.zig");
    _ = @import("git_branch.zig");
    _ = @import("git_checkout.zig");
    _ = @import("git_dirty.zig");
    _ = @import("git_numstat.zig");
    _ = @import("git_ahead_behind.zig");
    _ = @import("git_remotes.zig");
    _ = @import("git_toplevel.zig");
    _ = @import("git_common_dir.zig");
    _ = @import("file_mention.zig");
    _ = @import("skills.zig");
    _ = @import("providers.zig");
    _ = @import("environment_summary.zig");
    _ = @import("review_diff.zig");
    _ = @import("util.zig");
}
