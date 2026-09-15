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
const rewind = @import("rewind.zig");
const keys = @import("keys.zig");
const palette = @import("palette.zig");
const sidebar_dates = @import("sidebar_dates.zig");
const goal = @import("goal.zig");
const composer = @import("composer.zig");
const session_switcher = @import("switcher.zig");
const sidebar_row_helpers = @import("sidebar_rows.zig");
const attach_helpers = @import("attach.zig");
const prompt_spawn = @import("spawn.zig");
const sidecar_lines = @import("lines.zig");
const fx_probe = @import("fx_probe.zig");
const palette_run = @import("palette_run.zig");
const update_mod = @import("update.zig");
const boot_mod = @import("boot.zig");
const shell_mod = @import("shell.zig");
const model_exports = @import("model_exports.zig");
const i18n = @import("i18n.zig");
const environment_summary = @import("environment_summary.zig");
const right_panel = @import("right_panel.zig");
const util = @import("util.zig");
const browser_pane = @import("browser_pane.zig");
const file_preview_details = @import("file_preview_details.zig");
const transcript_details = @import("transcript_details.zig");

pub const panic = std.debug.FullPanic(native_sdk.debug.capturePanic);

const canvas = native_sdk.canvas;
const geometry = native_sdk.geometry;

const canvas_label = shell_mod.canvas_label;
const window_width = shell_mod.window_width;
const window_height = shell_mod.window_height;
const shell_scene = shell_mod.shell_scene;
const registerIcons = shell_mod.registerIcons;
/// Native model contract looks for `pub const app_icons` on the app root.
pub const app_icons = shell_mod.app_icons;
pub const max_sessions = model_exports.max_sessions;
/// Sidebar folder-header keys sit above session ids so `for` keys stay unique.
pub const folder_row_id_base: u32 = 1_000_000;
/// Date-bucket header keys sit above folder headers.
pub const date_row_id_base = sidebar_row_helpers.date_row_id_base;
pub const selection_history_cap = model_exports.selection_history_cap;
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
pub const max_turns = model_exports.max_turns;
pub const max_title = model_exports.max_title;
pub const max_body = model_exports.max_body;
pub const max_draft = model_exports.max_draft;
pub const max_queued = model_exports.max_queued;
pub const max_queued_text = model_exports.max_queued_text;
pub const max_fx_path = model_exports.max_fx_path;
pub const max_store_dir = model_exports.max_store_dir;
pub const max_project_path = model_exports.max_project_path;
pub const max_attach_status = model_exports.max_attach_status;
pub const max_fx_session_id = model_exports.max_fx_session_id;
pub const max_tool_call_id = model_exports.max_tool_call_id;
pub const max_tool_kind = model_exports.max_tool_kind;
pub const max_tool_status = model_exports.max_tool_status;
pub const max_runtime_id = model_exports.max_runtime_id;
pub const max_fx_model = model_exports.max_fx_model;
pub const max_access_mode = model_exports.max_access_mode;
pub const max_interaction_mode = model_exports.max_interaction_mode;
pub const max_reasoning_effort = model_exports.max_reasoning_effort;
pub const max_thread_goal_objective = model_exports.max_thread_goal_objective;
pub const max_thread_goal_status = model_exports.max_thread_goal_status;
pub const max_thread_goal_usage_label = model_exports.max_thread_goal_usage_label;
pub const max_available_commands = model_exports.max_available_commands;
pub const max_model_options = model_exports.max_model_options;
pub const max_command_name = model_exports.max_command_name;
pub const max_command_description = model_exports.max_command_description;
pub const default_access_mode = model_exports.default_access_mode;
pub const default_interaction_mode = model_exports.default_interaction_mode;
pub const default_reasoning_effort = model_exports.default_reasoning_effort;
pub const fx_env_bin = "/usr/bin/env";
pub const max_line_keep = 4096;

const app_permissions = [_][]const u8{ native_sdk.security.permission_command, native_sdk.security.permission_view };

pub const fx_probe_key = fx_probe.fx_probe_key;
pub const max_daemon_address = model_exports.max_daemon_address;
pub const max_daemon_token = model_exports.max_daemon_token;
pub const max_sidecar_path = model_exports.max_sidecar_path;
pub const demo_ticks_complete: u32 = 12;
pub const demo_reply = "fx here (demo). The fx CLI was not found, so this is a local timer stream. Install fx and Send runs `fx ask`.";

pub const Mode = model_exports.Mode;
pub const Role = model_exports.Role;
pub const Phase = model_exports.Phase;
pub const ReplyPath = model_exports.ReplyPath;

pub const Provider = model_exports.Provider;
pub const AvailableCommand = model_exports.AvailableCommand;
pub const ModelOption = model_exports.ModelOption;
pub const Session = model_exports.Session;

pub const Turn = model_exports.Turn;
pub const Folder = model_exports.Folder;
pub const SessionRow = model_exports.SessionRow;
pub const SidebarRow = model_exports.SidebarRow;

pub const DateBucket = sidebar_dates.DateBucket;
pub const sessionDateBucket = sidebar_dates.sessionDateBucket;
pub const sessionRelativeTime = sidebar_dates.sessionRelativeTime;
pub const formatThreadGoalUsage = goal.formatThreadGoalUsage;

pub const AssignFolder = model_exports.AssignFolder;
pub const TurnRow = model_exports.TurnRow;
pub const CommandRow = model_exports.CommandRow;
pub const ModelPickerRow = model_exports.ModelPickerRow;
pub const ChipPickerRow = model_exports.ChipPickerRow;
pub const DaemonDirBrowserRow = model_exports.DaemonDirBrowserRow;

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

pub const QueuedMessage = model_exports.QueuedMessage;
pub const QueuedRow = model_exports.QueuedRow;
pub const BackgroundRow = environment_summary.BackgroundRow;
pub const RightPanelFileRow = model_exports.RightPanelFileRow;
pub const FilePreviewLineRow = right_panel.FilePreviewLineRow;
pub const SkillRow = model_exports.SkillRow;
pub const UsageHistoryRow = model_exports.UsageHistoryRow;
pub const ProviderRow = model_exports.ProviderRow;
pub const Msg = model_exports.Msg;
pub const Model = model_exports.Model;
pub const ThemePreference = model_exports.ThemePreference;
pub const LanguagePreference = model_exports.LanguagePreference;

pub const writeFixed = model_exports.writeFixed;

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
        .web_panes = browser_pane.webPanes,
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
            .navigation = .{ .allowed_origins = &.{ "zero://inline", "zero://app", "*" } },
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
    _ = @import("pty_terminal.zig");
    _ = @import("open_url.zig");
    _ = @import("browser_pane.zig");
    _ = @import("open_editor.zig");
    _ = @import("code_language.zig");
    _ = @import("file_icon.zig");
    _ = @import("file_type_icons.zig");
    _ = @import("right_panel.zig");
    _ = @import("right_panel_session.zig");
    _ = @import("file_preview_images.zig");
    _ = @import("file_preview_details.zig");
    _ = @import("file_preview_issue_link.zig");
    _ = @import("transcript_images.zig");
    _ = @import("transcript_details.zig");
    _ = @import("file_preview_find.zig");
    _ = @import("file_preview_regex.zig");
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
    _ = @import("sidecar_keys.zig");
    _ = @import("git_keys.zig");
    _ = @import("model_exports.zig");
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
    _ = @import("slash_commands.zig");
    _ = @import("usage_history.zig");
    _ = @import("litellm_rates.zig");
    _ = @import("usage_meter.zig");
    _ = @import("background_work.zig");
    _ = @import("projectless.zig");
    _ = @import("skills.zig");
    _ = @import("providers.zig");
    _ = @import("environment_summary.zig");
    _ = @import("review_diff.zig");
    _ = @import("util.zig");
}
