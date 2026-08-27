//! TEA Model / Msg type graph.
//!
//! `Mode` / `Role` / `Phase` / `ReplyPath`, Turn / Folder / row types,
//! `Msg`, and `Model` live here. `update` / `initFx` / `initialModel`
//! stay in `main.zig`. Helpers that `@import("main.zig")` keep working
//! via re-exports. Behavior is unchanged from the former `main` Model
//! cluster.

const std = @import("std");
const native_sdk = @import("native_sdk");
const protocol = @import("protocol.zig");
const composer = @import("composer.zig");
const palette = @import("palette.zig");
const sidebar_row_helpers = @import("sidebar_rows.zig");
const store = @import("store.zig");
const session_mod = @import("session.zig");
const git_branch = @import("git_branch.zig");

const canvas = native_sdk.canvas;
const main = @import("main.zig");

const Session = session_mod.Session;
const Provider = session_mod.Provider;
const writeFixed = session_mod.writeFixed;
const max_title = session_mod.max_title;
const max_project_path = session_mod.max_project_path;
const max_fx_model = session_mod.max_fx_model;
const max_access_mode = session_mod.max_access_mode;
const max_interaction_mode = session_mod.max_interaction_mode;
const max_reasoning_effort = session_mod.max_reasoning_effort;
const max_command_name = session_mod.max_command_name;

const PaletteRow = palette.PaletteRow;
const slashCommandPrefix = composer.slashCommandPrefix;
const accessLabel = composer.accessLabel;
const effortLabel = composer.effortLabel;
const nextAccessMode = composer.nextAccessMode;
const nextReasoningEffort = composer.nextReasoningEffort;
const isDocumentedReasoningEffort = composer.isDocumentedReasoningEffort;
const access_chip_options = composer.access_chip_options;
const effort_chip_options = composer.effort_chip_options;

pub const max_sessions = 16;
const max_folders = 16;
/// In-memory session selection history for sidebar Back / Forward.
pub const selection_history_cap: u32 = 32;
pub const max_turns = 128;
const max_search = 64;
pub const max_body = 4096;
pub const max_draft = 512;
pub const max_queued = 16;
pub const max_queued_text = 1024;
pub const max_fx_path = 256;
pub const max_store_dir = 512;
pub const max_attach_status = 192;
pub const max_tool_call_id = 128;
pub const max_tool_kind = 32;
pub const max_tool_status = 32;
pub const max_daemon_address = 128;
pub const max_daemon_token = 256;
pub const max_sidecar_path = 512;

// Field-default copies of shell / key constants that stay defined in
// `main` / `switcher` / `attach`. Values must stay in sync.
const switcher_cap: u32 = 10;
const sidebar_default_width: f32 = 252;
const window_width: f32 = 1380;
const default_sidebar_split: f32 = sidebar_default_width / window_width;
const sidebar_min_width: f32 = 180;
const sidebar_rail_width: f32 = 48;
const attach_preview_id_first: u64 = 33;
const daemon_proxy_key_first: u64 = 4;
const fx_spawn_overlap_key_first: u64 = 64;
const transcript_pin_offset: f32 = 1_000_000;
const acp_cwd_fallback = ".";
const default_access_mode = "fullAccess";
const default_interaction_mode = "build";
const default_reasoning_effort = "auto";

pub const Mode = enum { demo, daemon };
pub const Role = enum { user, assistant, tool, reasoning };
pub const Phase = enum { idle, streaming };
pub const ReplyPath = enum { demo, fx, daemon };

pub const Turn = struct {
    id: u32 = 0,
    session_id: u32 = 0,
    role: Role = .user,
    body_storage: [max_body]u8 = [_]u8{0} ** max_body,
    body_len: usize = 0,
    /// Live ACP `toolCallId` so `tool_call_update` can find this row.
    /// Not a blob store — persist still writes `role` + body text.
    tool_call_id_storage: [max_tool_call_id]u8 = [_]u8{0} ** max_tool_call_id,
    tool_call_id_len: usize = 0,
    tool_title_storage: [max_title]u8 = [_]u8{0} ** max_title,
    tool_title_len: usize = 0,
    tool_kind_storage: [max_tool_kind]u8 = [_]u8{0} ** max_tool_kind,
    tool_kind_len: usize = 0,
    tool_status_storage: [max_tool_status]u8 = [_]u8{0} ** max_tool_status,
    tool_status_len: usize = 0,
    /// Last ACP `ToolCallContent[]` rendered as text/diff source.
    /// Replaced when an update carries `content`; persist is still body text.
    tool_content_storage: [max_body]u8 = [_]u8{0} ** max_body,
    tool_content_len: usize = 0,

    pub fn text(self: *const Turn) []const u8 {
        return self.body_storage[0..self.body_len];
    }

    pub fn toolCallId(self: *const Turn) []const u8 {
        return self.tool_call_id_storage[0..self.tool_call_id_len];
    }

    pub fn toolTitle(self: *const Turn) []const u8 {
        return self.tool_title_storage[0..self.tool_title_len];
    }

    pub fn toolKind(self: *const Turn) []const u8 {
        return self.tool_kind_storage[0..self.tool_kind_len];
    }

    pub fn toolStatus(self: *const Turn) []const u8 {
        return self.tool_status_storage[0..self.tool_status_len];
    }

    pub fn toolContent(self: *const Turn) []const u8 {
        return self.tool_content_storage[0..self.tool_content_len];
    }

    pub fn role_label(self: *const Turn) []const u8 {
        return switch (self.role) {
            .user => "You",
            .assistant => "Assistant",
            .tool => "Tool",
            .reasoning => "Reasoning",
        };
    }
};

pub const Folder = struct {
    id: u32 = 0,
    title_storage: [max_title]u8 = [_]u8{0} ** max_title,
    title_len: usize = 0,
    collapsed: bool = false,

    pub fn title(self: *const Folder) []const u8 {
        return self.title_storage[0..self.title_len];
    }

    pub fn setTitle(self: *Folder, title_text: []const u8) void {
        const trimmed = std.mem.trim(u8, title_text, " \t\r\n");
        const resolved = if (trimmed.len == 0) "New folder" else trimmed;
        writeFixed(&self.title_storage, &self.title_len, resolved);
    }
};

pub const SessionRow = struct {
    id: u32,
    title: []const u8,
    provider: []const u8,
    selected: bool,
};

/// Flattened date-bucket sessions + folder headers + folder sessions.
pub const SidebarRow = struct {
    id: u32,
    title: []const u8,
    provider: []const u8,
    selected: bool,
    is_header: bool,
    editing: bool,
    folder_id: u32,
    /// True for session rows nested under a folder (`folder_id != 0`).
    /// False for folder headers, date headers, and unassigned sessions.
    grouped: bool = false,
    /// Process-local. Headers stay false; store schema does not persist this.
    busy: bool = false,
    /// Today / Yesterday / This week / This month / This year / Older label.
    /// Not a folder; no assign/delete chrome.
    is_date_header: bool = false,
    /// Static last-activity label from `updated_at` vs `now_ms`. Empty when
    /// `updated_at` or the clock is missing/0 so chrome does not invent a time.
    relative_time: []const u8 = "",
    has_relative_time: bool = false,
    /// Folder headers mirror `Folder.collapsed`. Session and date rows stay false.
    collapsed: bool = false,
};

pub const AssignFolder = struct {
    session_id: u32,
    folder_id: u32,
};

pub const TurnRow = struct {
    id: u32,
    role_label: []const u8,
    text: []const u8,
    is_user: bool,
    is_tool: bool,
    is_reasoning: bool,
};

/// Stored ACP command for the composer Commands list. `id` is a 1-based
/// index into the session's stored commands (stable across slash
/// filters) so Native `insert_command:{c.id}` never binds 0 and a
/// filtered click still inserts that row, not a neighbor.
pub const CommandRow = struct {
    id: u32,
    slash_name: []const u8,
    description: []const u8,
    has_description: bool,
};

/// Composer model picker row. `row_id` is a 1-based Native `for` key.
/// `id` is the ACP wire value (empty clears `session.model`).
pub const ModelPickerRow = struct {
    row_id: u32,
    id: []const u8,
    label: []const u8,
    selected: bool,
};

/// Composer access/effort/goal-status picker row. `row_id` is a 1-based Native
/// `for` key. `id` is the stored chip value (ask/auto/fullAccess, fx effort,
/// or Codex `ThreadGoalStatus` camelCase).
pub const ChipPickerRow = struct {
    row_id: u32,
    id: []const u8,
    label: []const u8,
    selected: bool,
};

/// Follow-up queued while that session is busy. Becomes its own turn after a
/// successful finish — not after Stop/Esc or a non-zero `fx ask` exit.
pub const QueuedMessage = struct {
    id: u32 = 0,
    session_id: u32 = 0,
    text_storage: [max_queued_text]u8 = [_]u8{0} ** max_queued_text,
    text_len: usize = 0,

    pub fn text(self: *const QueuedMessage) []const u8 {
        return self.text_storage[0..self.text_len];
    }
};

/// Selected-session follow-ups for chrome. Native iterates this the way
/// `visible_turns` / `sidebar_rows` work — not `queued_store` itself.
pub const QueuedRow = struct {
    id: u32,
    text: []const u8,
};

pub const Msg = union(enum) {
    new_session,
    select: u32,
    remove_session: u32,
    rename_session: u32,
    start_search,
    palette_confirm,
    palette_cancel,
    palette_pick: u32,
    focus_composer,
    /// Cmd/Ctrl-F: open transcript find (keep query if already open).
    open_find,
    close_find,
    search_edit: canvas.TextInputEvent,
    find_edit: canvas.TextInputEvent,
    draft_edit: canvas.TextInputEvent,
    send,
    steer,
    /// Composer / header Codex `/goal` set. Reuses the draft as objective.
    /// No-op without a daemon address (does not fake Goal on fx/demo).
    goal_set,
    goal_clear,
    goal_refresh,
    toggle_goal_status_picker,
    close_goal_status_picker,
    /// Composer `/goal` status chip. Wire name is Codex `ThreadGoalStatus`.
    pick_goal_status: []const u8,
    stop,
    /// Composer circle while a turn is streaming. Cancels without the
    /// Esc overlay cascade (find open still stops the turn).
    stop_turn,
    clear_queue,
    remove_queued: u32,
    /// Click a queued follow-up: restore its text to the composer and drop it.
    edit_queued: u32,
    toggle_sidebar,
    toggle_settings,
    settings_model_edit: canvas.TextInputEvent,
    settings_project_edit: canvas.TextInputEvent,
    settings_daemon_edit: canvas.TextInputEvent,
    settings_access_ask,
    settings_access_auto,
    settings_access_full,
    settings_interaction_build,
    settings_interaction_plan,
    toggle_settings_effort_picker,
    close_settings_effort_picker,
    pick_settings_effort: []const u8,
    cycle_access,
    cycle_interaction,
    cycle_effort,
    toggle_model_picker,
    close_model_picker,
    pick_model: []const u8,
    toggle_access_picker,
    close_access_picker,
    pick_access: []const u8,
    toggle_effort_picker,
    close_effort_picker,
    pick_effort: []const u8,
    start_project_edit,
    project_path_edit: canvas.TextInputEvent,
    /// Composer Pick folder: one-shot OS directory-dialog sidecar. Not `fx.pickFile`.
    pick_folder,
    start_image_attach,
    /// Composer Pick image: one-shot OS file-dialog sidecar. Not `fx.pickFile`.
    pick_image,
    image_path_edit: canvas.TextInputEvent,
    /// Native window file drop. Path is a local image Faku already
    /// understands for `fx ask --image` (see `imagePathFromDrop`).
    file_drop: []const u8,
    clear_image_attach,
    toggle_commands,
    insert_command: u32,
    rewind,
    fork,
    fork_turn: u32,
    history_back,
    history_forward,
    new_folder,
    toggle_folder: u32,
    collapse_all_folders,
    rename_folder: u32,
    delete_folder: u32,
    assign_selected: u32,
    unassign_selected,
    assign_folder: AssignFolder,
    folder_title_edit: canvas.TextInputEvent,
    edit_session_title,
    session_title_edit: canvas.TextInputEvent,
    close_window,
    minimize_window,
    /// Chromeless Maximize: one-shot OS zoom sidecar. Not `fx.maximizeWindow`.
    maximize_window,
    quit_app,
    sidebar_resized: f32,
    transcript_scrolled: canvas.ScrollState,
    jump_latest,
    copy_turn: u32,
    copy_last_turn,
    copy_session,
    /// Palette: local numeric session id as decimal text. Not a UUID.
    copy_session_id,
    /// Palette: `fx_session_id` / ACP sessionId. Empty is a status, not a write.
    copy_fx_session_id,
    switcher_forward,
    switcher_backward,
    switcher_confirm,
    switcher_cancel,
    switcher_pick: u32,
    clipboard_done: native_sdk.EffectClipboardResult,
    attach_preview_done: native_sdk.EffectImageResult,
    tick: native_sdk.EffectTimer,
    fx_line: native_sdk.EffectLine,
    fx_exit: native_sdk.EffectExit,
    fx_probe_exit: native_sdk.EffectExit,

    pub const view_unbound = .{ "tick", "stop", "steer", "assign_folder", "fx_line", "fx_exit", "fx_probe_exit", "copy_last_turn", "copy_session_id", "copy_fx_session_id", "focus_composer", "open_find", "clipboard_done", "attach_preview_done", "switcher_forward", "switcher_backward", "file_drop", "cycle_access", "cycle_effort", "quit_app" };
};

pub const Model = struct {
    session_store: [max_sessions]Session = [_]Session{.{}} ** max_sessions,
    session_count: u32 = 0,
    folder_store: [max_folders]Folder = [_]Folder{.{}} ** max_folders,
    folder_count: u32 = 0,
    next_folder_id: u32 = 1,
    selected: u32 = 0,
    history_store: [selection_history_cap]u32 = [_]u32{0} ** selection_history_cap,
    history_count: u32 = 0,
    history_index: u32 = 0,
    next_id: u32 = 1,
    turn_store: [max_turns]Turn = [_]Turn{.{}} ** max_turns,
    turn_count: u32 = 0,
    next_turn_id: u32 = 1,
    draft_buffer: canvas.TextBuffer(max_draft) = .{},
    search_buffer: canvas.TextBuffer(max_search) = .{},
    /// Runtime-only command palette. Not persisted to sessions.json.
    palette_open: bool = false,
    /// Runtime-only composer model picker. Not persisted to sessions.json.
    model_picker_open: bool = false,
    /// Runtime-only composer access picker. Not persisted to sessions.json.
    access_picker_open: bool = false,
    /// Runtime-only composer effort picker. Not persisted to sessions.json.
    effort_picker_open: bool = false,
    /// Runtime-only settings effort picker. Not persisted to sessions.json.
    settings_effort_picker_open: bool = false,
    /// Runtime-only composer `/goal` status picker. Not persisted.
    goal_status_picker_open: bool = false,
    palette_highlight: u32 = 0,
    find_buffer: canvas.TextBuffer(max_search) = .{},
    find_active: bool = false,
    composer_active: bool = false,
    mode: Mode = .demo,
    phase: Phase = .idle,
    stream_cursor: u32 = 0,
    stream_turn_id: u32 = 0,
    streaming_session: u32 = 0,
    queued_store: [max_queued]QueuedMessage = [_]QueuedMessage{.{}} ** max_queued,
    queued_count: u32 = 0,
    next_queued_id: u32 = 1,
    sidebar_split: f32 = default_sidebar_split,
    sidebar_collapsed: bool = false,
    sidebar_last_width: f32 = sidebar_default_width,
    settings_open: bool = false,
    /// Runtime-only Ctrl-Tab overlay. Not persisted to sessions.json.
    switcher_open: bool = false,
    switcher_ids: [switcher_cap]u32 = [_]u32{0} ** switcher_cap,
    switcher_count: u32 = 0,
    switcher_highlight: u32 = 0,
    settings_model_buffer: canvas.TextBuffer(max_fx_model) = .{},
    settings_project_buffer: canvas.TextBuffer(max_project_path) = .{},
    settings_daemon_buffer: canvas.TextBuffer(max_daemon_address) = .{},
    project_edit_active: bool = false,
    project_edit_buffer: canvas.TextBuffer(max_project_path) = .{},
    image_attach_active: bool = false,
    image_path_buffer: canvas.TextBuffer(max_project_path) = .{},
    /// Runtime-only composer status for picker cancel / missing-tool.
    attach_status_storage: [max_attach_status]u8 = [_]u8{0} ** max_attach_status,
    attach_status_len: usize = 0,
    pick_image_live: bool = false,
    pick_image_got_path: bool = false,
    pick_image_tried_fallback: bool = false,
    pick_folder_live: bool = false,
    pick_folder_got_path: bool = false,
    pick_folder_tried_fallback: bool = false,
    /// Runtime-only chrome status when the OS maximize sidecar is missing.
    window_status_storage: [max_attach_status]u8 = [_]u8{0} ** max_attach_status,
    window_status_len: usize = 0,
    maximize_window_live: bool = false,
    maximize_window_tried_fallback: bool = false,
    /// Runtime-only composer branch label. One-shot `git branch
    /// --show-current`; not persisted to sessions.json.
    git_branch_storage: [git_branch.max_git_branch]u8 = [_]u8{0} ** git_branch.max_git_branch,
    git_branch_len: usize = 0,
    git_branch_key: u64 = 0,
    next_git_branch_key: u64 = git_branch.git_branch_key_first,
    git_branch_probe_session: u32 = 0,
    git_branch_probe_path_storage: [max_project_path]u8 = [_]u8{0} ** max_project_path,
    git_branch_probe_path_len: usize = 0,
    /// Runtime ImageId bound by the composer `<image>`. 0 until
    /// `fx.loadImage` reports `.loaded`. Same draft `image_path` as
    /// the chip — not a second persist field.
    attach_preview: canvas.ImageId = 0,
    attach_preview_load_id: u64 = 0,
    next_attach_preview_id: u64 = attach_preview_id_first,
    commands_open: bool = false,
    editing_folder_id: u32 = 0,
    folder_title_buffer: canvas.TextBuffer(max_title) = .{},
    editing_session_id: u32 = 0,
    session_title_buffer: canvas.TextBuffer(max_title) = .{},
    /// Controlled Native `<scroll value>` offset. Setting it scrolls
    /// the region; the engine clamps past the content edge.
    transcript_scroll: f32 = 0,
    transcript_viewport_extent: f32 = 0,
    transcript_content_extent: f32 = 0,
    /// True while the last `on-scroll` was at the content end, or
    /// before any observation (this slice pins until the user scrolls
    /// away). Native `ScrollState` extents are the at-bottom signal.
    transcript_pinned: bool = true,
    fx_available: bool = false,
    fx_path_storage: [max_fx_path]u8 = [_]u8{0} ** max_fx_path,
    fx_path_len: usize = 0,
    fx_probe_started: bool = false,
    fx_probe_index: u32 = 0,
    home_storage: [max_fx_path]u8 = [_]u8{0} ** max_fx_path,
    home_len: usize = 0,
    reply_path: ReplyPath = .demo,
    store_dir_storage: [max_store_dir]u8 = [_]u8{0} ** max_store_dir,
    store_dir_len: usize = 0,
    /// Same guard as waku-client: refuse catalog writes until a successful load.
    task_state_loaded: bool = false,
    store_io: ?std.Io = null,
    last_project_path_storage: [max_project_path]u8 = [_]u8{0} ** max_project_path,
    last_project_path_len: usize = 0,
    last_spawn_cwd_storage: [max_project_path]u8 = [_]u8{0} ** max_project_path,
    last_spawn_cwd_len: usize = 0,
    last_model_storage: [max_fx_model]u8 = [_]u8{0} ** max_fx_model,
    last_model_len: usize = 0,
    last_access_mode_storage: [max_access_mode]u8 = [_]u8{0} ** max_access_mode,
    last_access_mode_len: usize = 0,
    last_interaction_mode_storage: [max_interaction_mode]u8 = [_]u8{0} ** max_interaction_mode,
    last_interaction_mode_len: usize = 0,
    last_reasoning_effort_storage: [max_reasoning_effort]u8 = [_]u8{0} ** max_reasoning_effort,
    last_reasoning_effort_len: usize = 0,
    last_spawn_fx_model_storage: [max_fx_model]u8 = [_]u8{0} ** max_fx_model,
    last_spawn_fx_model_len: usize = 0,
    last_spawn_fx_permission_mode_storage: [max_access_mode]u8 = [_]u8{0} ** max_access_mode,
    last_spawn_fx_permission_mode_len: usize = 0,
    draft_image_path_storage: [max_project_path]u8 = [_]u8{0} ** max_project_path,
    draft_image_path_len: usize = 0,
    last_spawn_image_path_storage: [max_project_path]u8 = [_]u8{0} ** max_project_path,
    last_spawn_image_path_len: usize = 0,
    daemon_address_storage: [max_daemon_address]u8 = [_]u8{0} ** max_daemon_address,
    daemon_address_len: usize = 0,
    last_daemon_address_storage: [max_daemon_address]u8 = [_]u8{0} ** max_daemon_address,
    last_daemon_address_len: usize = 0,
    daemon_token_storage: [max_daemon_token]u8 = [_]u8{0} ** max_daemon_token,
    daemon_token_len: usize = 0,
    sidecar_path_storage: [max_sidecar_path]u8 = [_]u8{0} ** max_sidecar_path,
    sidecar_path_len: usize = 0,
    daemon_spawn_key: u64 = 0,
    next_daemon_key: u64 = daemon_proxy_key_first,
    /// First-run `loadTaskState` sidecar. Distinct from `daemon_spawn_key`
    /// so a catalog fill cannot settle a live turn.
    daemon_load_key: u64 = 0,
    pending_daemon_catalog: bool = false,
    /// Empty-transcript `hydrateSession` sidecar. Distinct from the live
    /// turn key and the catalog-fill key.
    daemon_hydrate_key: u64 = 0,
    daemon_hydrate_session: u32 = 0,
    fx_spawn_key: u64 = 0,
    next_fx_key: u64 = fx_spawn_overlap_key_first,
    fx_spawn_live: bool = false,
    fx_spawn_acp: bool = false,
    /// Journaled wall-clock ms from `fx.wallMs` (or a test pin). 0 means
    /// grouping treats missing `updated_at` as Today and relative-time
    /// labels stay omitted.
    now_ms: i64 = 0,

    pub const view_unbound = .{
        "session_store",
        "sessions",
        "session_count",
        "folder_store",
        "folders",
        "folder_count",
        "next_folder_id",
        "addFolder",
        "restoreFolder",
        "clearFolders",
        "folderById",
        "folderByIdConst",
        "assignSessionFolder",
        "toggleFolderCollapsed",
        "collapseAllFolders",
        "all_folders_collapsed",
        "deleteFolder",
        "nextUntitledFolderTitle",
        "startFolderTitleEdit",
        "closeFolderTitleEdit",
        "applyFolderTitle",
        "editing_folder_id",
        "folder_title_buffer",
        "startSessionTitleEdit",
        "closeSessionTitleEdit",
        "applySessionTitle",
        "editing_session_id",
        "session_title_buffer",
        "session_rows",
        "selected",
        "history_store",
        "history_count",
        "history_index",
        "can_go_back",
        "can_go_forward",
        "has_goal",
        "pushSelectionHistory",
        "dropSelectionHistory",
        "next_id",
        "turn_store",
        "turn_count",
        "next_turn_id",
        "draft_buffer",
        "search_buffer",
        "palette_highlight",
        "find_buffer",
        "mode",
        "phase",
        "stream_cursor",
        "stream_turn_id",
        "streaming_session",
        "queued_store",
        "queued_count",
        "next_queued_id",
        "queued_text",
        "dropQueued",
        "takeQueued",
        "sidebar_collapsed",
        "sidebar_last_width",
        "sidebarWidthPixels",
        "applySidebarWidth",
        "syncSidebarSplit",
        "toggleSidebar",
        "settings_model_buffer",
        "settings_project_buffer",
        "settings_daemon_buffer",
        "project_edit_buffer",
        "image_path_buffer",
        "attach_status_storage",
        "attach_status_len",
        "pick_image_live",
        "pick_image_got_path",
        "pick_image_tried_fallback",
        "pick_folder_live",
        "pick_folder_got_path",
        "pick_folder_tried_fallback",
        "setAttachStatus",
        "clearAttachStatus",
        "window_status_storage",
        "window_status_len",
        "maximize_window_live",
        "maximize_window_tried_fallback",
        "setWindowStatus",
        "clearWindowStatus",
        "git_branch_storage",
        "git_branch_len",
        "git_branch_key",
        "next_git_branch_key",
        "git_branch_probe_session",
        "git_branch_probe_path_storage",
        "git_branch_probe_path_len",
        "attach_preview_load_id",
        "next_attach_preview_id",
        "startImageAttach",
        "closeImageAttach",
        "applyImagePath",
        "clearImageAttach",
        "toggleCommands",
        "closeCommands",
        "insertAvailableCommand",
        "switcher_ids",
        "switcher_count",
        "switcher_highlight",
        "openSettings",
        "closeSettings",
        "toggleSettings",
        "applySettingsModel",
        "applySettingsProject",
        "applySettingsDaemon",
        "setSettingsAccess",
        "setSettingsInteraction",
        "cycleSelectedAccess",
        "cycleSelectedInteraction",
        "cycleSelectedEffort",
        "pickSelectedModel",
        "toggleModelPicker",
        "closeModelPicker",
        "pickSelectedAccess",
        "toggleAccessPicker",
        "closeAccessPicker",
        "pickSelectedEffort",
        "toggleEffortPicker",
        "closeEffortPicker",
        "pickSettingsEffort",
        "toggleSettingsEffortPicker",
        "closeSettingsEffortPicker",
        "toggleGoalStatusPicker",
        "closeGoalStatusPicker",
        "closeComposerPickers",
        "access_selected_ask",
        "access_selected_auto",
        "access_selected_full",
        "effort_selected_auto",
        "effort_selected_none",
        "effort_selected_minimal",
        "effort_selected_low",
        "effort_selected_medium",
        "effort_selected_high",
        "effort_selected_xhigh",
        "effort_selected_max",
        "startProjectEdit",
        "closeProjectEdit",
        "applySelectedProjectPath",
        "setSelectedProjectPath",
        "selectedProjectPath",
        "resolvedAccessMode",
        "resolvedInteractionMode",
        "resolvedReasoningEffort",
        "send_label",
        "fx_available",
        "fx_path_storage",
        "fx_path_len",
        "fx_probe_started",
        "fx_probe_index",
        "home_storage",
        "home_len",
        "reply_path",
        "store_dir_storage",
        "store_dir_len",
        "task_state_loaded",
        "store_io",
        "now_ms",
        "last_project_path_storage",
        "last_project_path_len",
        "last_spawn_cwd_storage",
        "last_spawn_cwd_len",
        "last_model_storage",
        "last_model_len",
        "last_access_mode_storage",
        "last_access_mode_len",
        "last_interaction_mode_storage",
        "last_interaction_mode_len",
        "last_reasoning_effort_storage",
        "last_reasoning_effort_len",
        "last_spawn_fx_model_storage",
        "last_spawn_fx_model_len",
        "last_spawn_fx_permission_mode_storage",
        "last_spawn_fx_permission_mode_len",
        "draft_image_path_storage",
        "draft_image_path_len",
        "last_spawn_image_path_storage",
        "last_spawn_image_path_len",
        "lastProjectPath",
        "setLastProjectPath",
        "lastModel",
        "setLastModel",
        "lastAccessMode",
        "setLastAccessMode",
        "lastInteractionMode",
        "setLastInteractionMode",
        "lastReasoningEffort",
        "setLastReasoningEffort",
        "lastSpawnCwd",
        "setLastSpawnCwd",
        "lastSpawnFxModel",
        "setLastSpawnFxModel",
        "lastSpawnFxPermissionMode",
        "setLastSpawnFxPermissionMode",
        "draftImagePath",
        "setDraftImagePath",
        "lastSpawnImagePath",
        "setLastSpawnImagePath",
        "daemon_address_storage",
        "daemon_address_len",
        "last_daemon_address_storage",
        "last_daemon_address_len",
        "daemon_token_storage",
        "daemon_token_len",
        "sidecar_path_storage",
        "sidecar_path_len",
        "daemon_spawn_key",
        "next_daemon_key",
        "daemon_load_key",
        "pending_daemon_catalog",
        "daemon_hydrate_key",
        "daemon_hydrate_session",
        "fx_spawn_key",
        "next_fx_key",
        "fx_spawn_live",
        "fx_spawn_acp",
        "daemonAddress",
        "setDaemonAddress",
        "lastDaemonAddress",
        "setLastDaemonAddress",
        "daemonToken",
        "setDaemonToken",
        "sidecarPath",
        "setSidecarPath",
        "resolveSpawnImage",
        "resolveSpawnCwd",
        "resolveAcpCwd",
        "fxPath",
        "setFxPath",
        "setHome",
        "homeDir",
        "storeDir",
        "setStoreDir",
        "exitSearch",
        "closePalette",
        "exitFind",
        "selected_title",
        "selected_provider",
        "status_line",
        "empty_hint",
        "has_turns",
        "transcript_viewport_extent",
        "transcript_content_extent",
        "transcript_pinned",
        "applyTranscriptScroll",
        "pinTranscriptToLatest",
        "transcriptAtEnd",
    };

    pub fn draft(model: *const Model) []const u8 {
        return model.draft_buffer.text();
    }

    pub fn search_query(model: *const Model) []const u8 {
        return model.search_buffer.text();
    }

    pub fn exitSearch(model: *Model) void {
        model.closePalette();
    }

    pub fn closePalette(model: *Model) void {
        model.search_buffer.clear();
        model.palette_open = false;
        model.palette_highlight = 0;
    }

    pub fn closeComposerPickers(model: *Model) void {
        model.model_picker_open = false;
        model.access_picker_open = false;
        model.effort_picker_open = false;
        model.goal_status_picker_open = false;
    }

    pub fn closeModelPicker(model: *Model) void {
        model.closeComposerPickers();
    }

    pub fn toggleModelPicker(model: *Model) void {
        model.model_picker_open = !model.model_picker_open;
    }

    pub fn closeAccessPicker(model: *Model) void {
        model.access_picker_open = false;
    }

    pub fn toggleAccessPicker(model: *Model) void {
        model.access_picker_open = !model.access_picker_open;
    }

    pub fn closeEffortPicker(model: *Model) void {
        model.effort_picker_open = false;
    }

    pub fn toggleEffortPicker(model: *Model) void {
        model.effort_picker_open = !model.effort_picker_open;
    }

    pub fn closeSettingsEffortPicker(model: *Model) void {
        model.settings_effort_picker_open = false;
    }

    pub fn toggleSettingsEffortPicker(model: *Model) void {
        if (!model.settings_effort_picker_open) {
            model.closeComposerPickers();
        }
        model.settings_effort_picker_open = !model.settings_effort_picker_open;
    }

    pub fn closeGoalStatusPicker(model: *Model) void {
        model.goal_status_picker_open = false;
    }

    pub fn toggleGoalStatusPicker(model: *Model) void {
        model.goal_status_picker_open = !model.goal_status_picker_open;
    }

    pub fn find_query(model: *const Model) []const u8 {
        return model.find_buffer.text();
    }

    pub fn exitFind(model: *Model) void {
        model.find_buffer.clear();
        model.find_active = false;
    }

    pub fn is_streaming(model: *const Model) bool {
        return model.phase == .streaming;
    }

    pub fn sessions(model: *const Model) []const Session {
        return model.session_store[0..model.session_count];
    }

    pub fn session_rows(model: *const Model, arena: std.mem.Allocator) []const SessionRow {
        const out = arena.alloc(SessionRow, model.session_count) catch return &.{};
        var i: usize = 0;
        for (model.session_store[0..model.session_count]) |*session| {
            out[i] = .{
                .id = session.id,
                .title = main.sessionDisplayTitle(session),
                .provider = session.provider_label(),
                .selected = session.id == model.selected,
            };
            i += 1;
        }
        return out[0..i];
    }

    pub fn folders(model: *const Model) []const Folder {
        return model.folder_store[0..model.folder_count];
    }

    pub fn sidebar_rows(model: *const Model, arena: std.mem.Allocator) []const SidebarRow {
        return sidebar_row_helpers.rows(model, arena);
    }

    pub fn switcher_rows(model: *const Model, arena: std.mem.Allocator) []const SessionRow {
        if (!model.switcher_open or model.switcher_count == 0) return &.{};
        const out = arena.alloc(SessionRow, model.switcher_count) catch return &.{};
        var n: usize = 0;
        var i: usize = 0;
        while (i < model.switcher_count) : (i += 1) {
            const id = model.switcher_ids[i];
            const session = model.sessionByIdConst(id) orelse continue;
            out[n] = .{
                .id = session.id,
                .title = main.sessionDisplayTitle(session),
                .provider = session.provider_label(),
                .selected = i == model.switcher_highlight,
            };
            n += 1;
        }
        return out[0..n];
    }

    pub fn palette_rows(model: *const Model, arena: std.mem.Allocator) []const PaletteRow {
        return palette.rows(model, arena);
    }

    pub fn command_rows(model: *const Model, arena: std.mem.Allocator) []const CommandRow {
        const session = model.sessionByIdConst(model.selected) orelse return &.{};
        const commands = session.availableCommands();
        if (commands.len == 0) return &.{};
        const prefix = slashCommandPrefix(model.draft());
        const out = arena.alloc(CommandRow, commands.len) catch return &.{};
        var i: usize = 0;
        for (commands, 0..) |*cmd, index| {
            if (prefix) |filter| {
                if (!commandNameStartsWith(cmd.name(), filter)) continue;
            }
            const slash = std.fmt.allocPrint(arena, "/{s}", .{cmd.name()}) catch continue;
            out[i] = .{
                .id = @intCast(index + 1),
                .slash_name = slash,
                .description = cmd.description(),
                .has_description = cmd.description().len > 0,
            };
            i += 1;
        }
        return out[0..i];
    }

    pub fn model_picker_rows(model: *const Model, arena: std.mem.Allocator) []const ModelPickerRow {
        const session = model.sessionByIdConst(model.selected);
        const current = if (session) |s| s.model() else "";
        const catalog = if (session) |s| s.modelOptions() else &.{};
        if (catalog.len > 0) {
            const out = arena.alloc(ModelPickerRow, catalog.len) catch return &.{};
            for (catalog, 0..) |*opt, index| {
                const option_id = opt.id();
                const option_label = opt.label();
                out[index] = .{
                    .row_id = @intCast(index + 1),
                    .id = option_id,
                    .label = if (option_label.len > 0) option_label else if (option_id.len > 0) option_id else "FX_MODEL",
                    .selected = std.mem.eql(u8, current, option_id),
                };
            }
            return out;
        }

        const last = model.lastModel();
        const include_last = last.len > 0;
        const count: usize = if (include_last) 2 else 1;
        const out = arena.alloc(ModelPickerRow, count) catch return &.{};
        out[0] = .{
            .row_id = 1,
            .id = "",
            .label = "FX_MODEL",
            .selected = current.len == 0,
        };
        if (include_last) {
            out[1] = .{
                .row_id = 2,
                .id = last,
                .label = last,
                .selected = std.mem.eql(u8, current, last),
            };
        }
        return out;
    }

    pub fn access_picker_rows(model: *const Model, arena: std.mem.Allocator) []const ChipPickerRow {
        const current = accessLabel(model.resolvedAccessMode());
        const out = arena.alloc(ChipPickerRow, access_chip_options.len) catch return &.{};
        for (access_chip_options, 0..) |opt, index| {
            out[index] = .{
                .row_id = @intCast(index + 1),
                .id = opt.id,
                .label = opt.label,
                .selected = std.mem.eql(u8, current, opt.label),
            };
        }
        return out;
    }

    pub fn effort_picker_rows(model: *const Model, arena: std.mem.Allocator) []const ChipPickerRow {
        const current = effortLabel(model.resolvedReasoningEffort());
        const out = arena.alloc(ChipPickerRow, effort_chip_options.len) catch return &.{};
        for (effort_chip_options, 0..) |opt, index| {
            out[index] = .{
                .row_id = @intCast(index + 1),
                .id = opt.id,
                .label = opt.label,
                .selected = std.mem.eql(u8, current, opt.label),
            };
        }
        return out;
    }

    /// Codex `ThreadGoalStatus` wire names. Hidden unless `show_goal`.
    pub fn goal_status_picker_rows(model: *const Model, arena: std.mem.Allocator) []const ChipPickerRow {
        const tags = std.meta.tags(protocol.ThreadGoalStatus);
        const current = if (model.sessionByIdConst(model.selected)) |session|
            session.threadGoalStatus()
        else
            "";
        const out = arena.alloc(ChipPickerRow, tags.len) catch return &.{};
        for (tags, 0..) |status, index| {
            const name = status.wireName();
            out[index] = .{
                .row_id = @intCast(index + 1),
                .id = name,
                .label = name,
                .selected = std.mem.eql(u8, current, name),
            };
        }
        return out;
    }

    /// Settings menu checkmark. Uses lastReasoningEffort(), not resolvedReasoningEffort().
    pub fn settings_effort_picker_rows(model: *const Model, arena: std.mem.Allocator) []const ChipPickerRow {
        const current = effortLabel(model.lastReasoningEffort());
        const out = arena.alloc(ChipPickerRow, effort_chip_options.len) catch return &.{};
        for (effort_chip_options, 0..) |opt, index| {
            out[index] = .{
                .row_id = @intCast(index + 1),
                .id = opt.id,
                .label = opt.label,
                .selected = std.mem.eql(u8, current, opt.label),
            };
        }
        return out;
    }

    pub fn visible_turns(model: *const Model, arena: std.mem.Allocator) []const TurnRow {
        const query = if (model.find_active)
            std.mem.trim(u8, model.find_query(), " \t\r\n")
        else
            "";
        var count: usize = 0;
        for (model.turn_store[0..model.turn_count]) |turn| {
            if (turn.session_id != model.selected) continue;
            if (query.len > 0 and !main.asciiContainsIgnoreCase(turn.text(), query)) continue;
            count += 1;
        }
        const out = arena.alloc(TurnRow, count) catch return &.{};
        var i: usize = 0;
        for (model.turn_store[0..model.turn_count]) |*turn| {
            if (turn.session_id != model.selected) continue;
            if (query.len > 0 and !main.asciiContainsIgnoreCase(turn.text(), query)) continue;
            out[i] = .{
                .id = turn.id,
                .role_label = turn.role_label(),
                .text = turn.text(),
                .is_user = turn.role == .user,
                .is_tool = turn.role == .tool,
                .is_reasoning = turn.role == .reasoning,
            };
            i += 1;
        }
        return out[0..i];
    }

    /// Find-bar muted count (`1 match` / `N matches` / `No matches`). Empty
    /// when find is inactive or the trimmed query is blank so the row can hide it.
    /// Same selected-session ascii-contains predicate as `visible_turns`.
    pub fn find_match_label(model: *const Model, arena: std.mem.Allocator) []const u8 {
        if (!model.find_active) return "";
        const query = std.mem.trim(u8, model.find_query(), " \t\r\n");
        if (query.len == 0) return "";
        var count: usize = 0;
        for (model.turn_store[0..model.turn_count]) |turn| {
            if (turn.session_id != model.selected) continue;
            if (!main.asciiContainsIgnoreCase(turn.text(), query)) continue;
            count += 1;
        }
        return switch (count) {
            0 => "No matches",
            1 => "1 match",
            else => std.fmt.allocPrint(arena, "{d} matches", .{count}) catch "matches",
        };
    }

    /// True when the find bar should show `find_match_label`.
    pub fn has_find_match_label(model: *const Model) bool {
        if (!model.find_active) return false;
        return std.mem.trim(u8, model.find_query(), " \t\r\n").len > 0;
    }

    pub fn selected_title(model: *const Model) []const u8 {
        if (model.activeSessionConst()) |session| return session.title();
        return "untitled";
    }

    pub fn header_title(model: *const Model) []const u8 {
        if (model.activeSessionConst()) |session| {
            if (session.untitled) return "New task";
            return session.title();
        }
        return "New task";
    }

    pub fn selected_provider(model: *const Model) []const u8 {
        if (model.activeSessionConst()) |session| return session.provider_label();
        return Provider.default.wireName();
    }

    pub fn status_line(model: *const Model, arena: std.mem.Allocator) []const u8 {
        const path = switch (model.reply_path) {
            .demo => "demo",
            .fx => "fx",
            .daemon => "daemon",
        };
        return std.fmt.allocPrint(arena, "{d} sessions · {s} · {s}", .{
            model.session_count,
            path,
            model.selected_provider(),
        }) catch "demo";
    }

    pub fn empty_hint(model: *const Model) []const u8 {
        if (model.daemonAddress().len > 0) {
            return "Message the daemon sidecar. Send is one-shot hello/attachSession/start/prompt over ws://{addr}/v1 when no runtime id; later sends keep attach + prompt. Missing address keeps `fx ask` / demo.";
        }
        if (model.fx_available) {
            return "Message fx. Send runs one-shot `fx acp` via acp-proxy (initialize / session/new|resume / set model|mode / session/prompt). Images still use `fx ask --image`.";
        }
        return "Message fx. Demo replies locally until the fx CLI is found; then Send runs one-shot `fx acp`. Images still use `fx ask --image`.";
    }

    pub fn has_turns(model: *const Model) bool {
        return model.turnCount(model.selected) > 0;
    }

    /// Shown only after the user scrolls away from the latest turn.
    pub fn show_jump_latest(model: *const Model) bool {
        return !model.transcript_pinned;
    }

    pub fn transcriptAtEnd(scroll: canvas.ScrollState) bool {
        const max_offset = @max(0, scroll.content_extent_y - scroll.viewport_extent_y);
        return scroll.offset_y + 1.0 >= max_offset;
    }

    pub fn applyTranscriptScroll(model: *Model, scroll: canvas.ScrollState) void {
        model.transcript_viewport_extent = scroll.viewport_extent_y;
        model.transcript_content_extent = scroll.content_extent_y;
        model.transcript_scroll = scroll.offset_y;
        model.transcript_pinned = Model.transcriptAtEnd(scroll);
    }

    pub fn pinTranscriptToLatest(model: *Model) void {
        model.transcript_pinned = true;
        model.transcript_scroll = transcript_pin_offset;
    }

    pub fn has_queued(model: *const Model) bool {
        return model.queuedCount(model.selected) > 0;
    }

    pub fn has_commands(model: *const Model) bool {
        const session = model.sessionByIdConst(model.selected) orelse return false;
        return session.available_command_count > 0;
    }

    /// Commands button stays visible when the list is stored. The card
    /// renders when the button toggled it open or the composer draft is
    /// an active slash prefix. A slash filter with no name matches hides
    /// the card so a mistype does not leave an empty box.
    pub fn commands_list_open(model: *const Model) bool {
        if (!model.has_commands()) return false;
        const prefix = slashCommandPrefix(model.draft());
        if (!model.commands_open and prefix == null) return false;
        if (prefix) |filter| {
            if (filter.len > 0 and !hasCommandNamePrefix(model, filter)) return false;
        }
        return true;
    }

    pub fn queued_text(model: *const Model) []const u8 {
        return model.firstQueuedText(model.selected);
    }

    pub fn queued_rows(model: *const Model, arena: std.mem.Allocator) []const QueuedRow {
        var count: usize = 0;
        for (model.queued_store[0..model.queued_count]) |item| {
            if (item.session_id == model.selected) count += 1;
        }
        if (count == 0) return &.{};
        const out = arena.alloc(QueuedRow, count) catch return &.{};
        var i: usize = 0;
        for (model.queued_store[0..model.queued_count]) |*item| {
            if (item.session_id != model.selected) continue;
            out[i] = .{
                .id = item.id,
                .text = item.text(),
            };
            i += 1;
        }
        return out[0..i];
    }

    pub fn composer_placeholder(model: *const Model) []const u8 {
        return if (model.is_streaming()) "Queue a follow-up..." else "Do anything...";
    }

    pub fn send_label(model: *const Model) []const u8 {
        return if (model.is_streaming()) "Stop" else "Send";
    }

    pub fn sidebar_expanded(model: *const Model) bool {
        return !model.sidebar_collapsed;
    }

    pub fn sidebar_pane_min(model: *const Model) f32 {
        return if (model.sidebar_collapsed) sidebar_rail_width else sidebar_min_width;
    }

    pub fn sidebar_toggle_label(model: *const Model) []const u8 {
        return if (model.sidebar_collapsed) "Expand sidebar" else "Collapse sidebar";
    }

    pub fn can_go_back(model: *const Model) bool {
        return model.history_count > 0 and model.history_index > 0;
    }

    pub fn can_go_forward(model: *const Model) bool {
        return model.history_count > 0 and model.history_index + 1 < model.history_count;
    }

    /// Record a user selection. Re-selecting the current entry is a no-op.
    /// Selecting after Back forks: everything ahead of the index is dropped.
    /// The oldest entry is discarded when the stack hits `selection_history_cap`.
    pub fn pushSelectionHistory(model: *Model, id: u32) void {
        if (id == 0) return;
        if (model.history_count > 0 and model.history_store[model.history_index] == id) return;

        if (model.history_count == 0) {
            if (model.selected != 0 and model.selected != id) {
                model.history_store[0] = model.selected;
                model.history_count = 1;
                model.history_index = 0;
            } else {
                model.history_store[0] = id;
                model.history_count = 1;
                model.history_index = 0;
                return;
            }
        }

        model.history_count = model.history_index + 1;
        if (model.history_count >= selection_history_cap) {
            var i: usize = 0;
            while (i + 1 < selection_history_cap) : (i += 1) {
                model.history_store[i] = model.history_store[i + 1];
            }
            model.history_count = selection_history_cap - 1;
            model.history_index = model.history_count - 1;
        }

        model.history_store[model.history_count] = id;
        model.history_count += 1;
        model.history_index = model.history_count - 1;
    }

    /// Drop every occurrence of `id` so Back / Forward cannot land on a
    /// removed session. Index stays on the last remaining entry at or
    /// before the old cursor (or 0 when the stack is empty).
    pub fn dropSelectionHistory(model: *Model, id: u32) void {
        if (id == 0 or model.history_count == 0) return;
        var kept: u32 = 0;
        var new_index: u32 = 0;
        var i: u32 = 0;
        while (i < model.history_count) : (i += 1) {
            if (model.history_store[i] == id) continue;
            if (i <= model.history_index) new_index = kept;
            model.history_store[kept] = model.history_store[i];
            kept += 1;
        }
        model.history_count = kept;
        if (kept == 0) {
            model.history_index = 0;
            return;
        }
        if (new_index >= kept) new_index = kept - 1;
        model.history_index = new_index;
    }

    pub fn sidebarWidthPixels(model: *const Model) u32 {
        return @intFromFloat(@round(sidebar_row_helpers.clampSidebarWidth(model.sidebar_last_width)));
    }

    pub fn applySidebarWidth(model: *Model, width: u32) void {
        if (width == 0) return;
        model.sidebar_last_width = sidebar_row_helpers.clampSidebarWidth(@floatFromInt(width));
    }

    pub fn syncSidebarSplit(model: *Model) void {
        if (model.sidebar_collapsed) {
            model.sidebar_split = sidebar_row_helpers.collapsedSidebarSplit();
            return;
        }
        const width = if (model.sidebar_last_width > 0) model.sidebar_last_width else sidebar_default_width;
        model.sidebar_split = sidebar_row_helpers.clampExpandedSidebarSplit(width / window_width);
    }

    pub fn toggleSidebar(model: *Model) void {
        if (model.sidebar_collapsed) {
            model.sidebar_collapsed = false;
        } else {
            sidebar_row_helpers.rememberExpandedWidth(model);
            model.sidebar_collapsed = true;
        }
        model.syncSidebarSplit();
    }

    pub fn settings_model(model: *const Model) []const u8 {
        return model.settings_model_buffer.text();
    }

    pub fn settings_project(model: *const Model) []const u8 {
        return model.settings_project_buffer.text();
    }

    pub fn settings_daemon(model: *const Model) []const u8 {
        return model.settings_daemon_buffer.text();
    }

    pub fn access_ask(model: *const Model) bool {
        return std.mem.eql(u8, model.lastAccessMode(), "ask");
    }

    pub fn access_auto(model: *const Model) bool {
        const mode = model.lastAccessMode();
        return std.mem.eql(u8, mode, "auto") or std.mem.eql(u8, mode, "autoAcceptEdits");
    }

    pub fn access_full(model: *const Model) bool {
        const mode = model.lastAccessMode();
        return mode.len == 0 or std.mem.eql(u8, mode, "fullAccess") or std.mem.eql(u8, mode, "yolo");
    }

    pub fn interaction_build(model: *const Model) bool {
        const mode = model.lastInteractionMode();
        return mode.len == 0 or std.mem.eql(u8, mode, "build");
    }

    pub fn interaction_plan(model: *const Model) bool {
        return std.mem.eql(u8, model.lastInteractionMode(), "plan");
    }

    /// Settings select label. Uses lastReasoningEffort(), not resolvedReasoningEffort().
    pub fn settings_effort_label(model: *const Model) []const u8 {
        return effortLabel(model.lastReasoningEffort());
    }

    pub fn openSettings(model: *Model) void {
        model.closeProjectEdit();
        model.closeImageAttach();
        model.closeCommands();
        model.closeModelPicker();
        model.closeSettingsEffortPicker();
        model.closeFolderTitleEdit();
        model.closeSessionTitleEdit();
        model.settings_open = true;
        model.settings_model_buffer.set(model.lastModel());
        model.settings_project_buffer.set(model.lastProjectPath());
        model.settings_daemon_buffer.set(model.lastDaemonAddress());
    }

    pub fn closeSettings(model: *Model) void {
        model.closeSettingsEffortPicker();
        model.settings_open = false;
    }

    pub fn toggleSettings(model: *Model) void {
        if (model.settings_open) {
            model.closeSettings();
        } else {
            model.openSettings();
        }
    }

    pub fn applySettingsModel(model: *Model, edit: canvas.TextInputEvent) void {
        model.settings_model_buffer.apply(edit);
        model.setLastModel(std.mem.trim(u8, model.settings_model(), " \t\r\n"));
    }

    pub fn applySettingsProject(model: *Model, edit: canvas.TextInputEvent) void {
        model.settings_project_buffer.apply(edit);
        model.setLastProjectPath(std.mem.trim(u8, model.settings_project(), " \t\r\n"));
    }

    pub fn applySettingsDaemon(model: *Model, edit: canvas.TextInputEvent) void {
        model.settings_daemon_buffer.apply(edit);
        model.setLastDaemonAddress(std.mem.trim(u8, model.settings_daemon(), " \t\r\n"));
    }

    pub fn setSettingsAccess(model: *Model, mode: []const u8) void {
        if (std.mem.eql(u8, mode, "ask") or std.mem.eql(u8, mode, "auto") or std.mem.eql(u8, mode, "fullAccess")) {
            model.setLastAccessMode(mode);
        }
    }

    pub fn setSettingsInteraction(model: *Model, mode: []const u8) void {
        if (std.mem.eql(u8, mode, "build") or std.mem.eql(u8, mode, "plan")) {
            model.setLastInteractionMode(mode);
        }
    }

    pub fn resolvedAccessMode(model: *const Model) []const u8 {
        if (model.sessionByIdConst(model.selected)) |session| {
            if (session.accessMode().len > 0) return session.accessMode();
        }
        if (model.lastAccessMode().len > 0) return model.lastAccessMode();
        return default_access_mode;
    }

    pub fn resolvedInteractionMode(model: *const Model) []const u8 {
        if (model.sessionByIdConst(model.selected)) |session| {
            if (session.interactionMode().len > 0) return session.interactionMode();
        }
        if (model.lastInteractionMode().len > 0) return model.lastInteractionMode();
        return default_interaction_mode;
    }

    pub fn resolvedReasoningEffort(model: *const Model) []const u8 {
        if (model.sessionByIdConst(model.selected)) |session| {
            if (session.reasoningEffort().len > 0) return session.reasoningEffort();
        }
        if (model.lastReasoningEffort().len > 0) return model.lastReasoningEffort();
        return default_reasoning_effort;
    }

    pub fn access_label(model: *const Model) []const u8 {
        return accessLabel(model.resolvedAccessMode());
    }

    /// Composer menu checkmark. Uses resolvedAccessMode(), not lastAccessMode().
    pub fn access_selected_ask(model: *const Model) bool {
        return std.mem.eql(u8, accessLabel(model.resolvedAccessMode()), "Ask");
    }

    pub fn access_selected_auto(model: *const Model) bool {
        return std.mem.eql(u8, accessLabel(model.resolvedAccessMode()), "Auto");
    }

    pub fn access_selected_full(model: *const Model) bool {
        return std.mem.eql(u8, accessLabel(model.resolvedAccessMode()), "Full access");
    }

    pub fn interaction_label(model: *const Model) []const u8 {
        return if (std.mem.eql(u8, model.resolvedInteractionMode(), "plan")) "Plan" else "Build";
    }

    pub fn effort_label(model: *const Model) []const u8 {
        return effortLabel(model.resolvedReasoningEffort());
    }

    /// Composer menu checkmark. Uses resolvedReasoningEffort(), not lastReasoningEffort().
    pub fn effort_selected_auto(model: *const Model) bool {
        return std.mem.eql(u8, effortLabel(model.resolvedReasoningEffort()), "Auto");
    }

    pub fn effort_selected_none(model: *const Model) bool {
        return std.mem.eql(u8, effortLabel(model.resolvedReasoningEffort()), "None");
    }

    pub fn effort_selected_minimal(model: *const Model) bool {
        return std.mem.eql(u8, effortLabel(model.resolvedReasoningEffort()), "Minimal");
    }

    pub fn effort_selected_low(model: *const Model) bool {
        return std.mem.eql(u8, effortLabel(model.resolvedReasoningEffort()), "Low");
    }

    pub fn effort_selected_medium(model: *const Model) bool {
        return std.mem.eql(u8, effortLabel(model.resolvedReasoningEffort()), "Medium");
    }

    pub fn effort_selected_high(model: *const Model) bool {
        return std.mem.eql(u8, effortLabel(model.resolvedReasoningEffort()), "High");
    }

    pub fn effort_selected_xhigh(model: *const Model) bool {
        return std.mem.eql(u8, effortLabel(model.resolvedReasoningEffort()), "Extra high");
    }

    pub fn effort_selected_max(model: *const Model) bool {
        return std.mem.eql(u8, effortLabel(model.resolvedReasoningEffort()), "Max");
    }

    pub fn model_label(model: *const Model) []const u8 {
        if (model.sessionByIdConst(model.selected)) |session| {
            if (session.model().len > 0) return session.model();
        }
        return "FX_MODEL";
    }

    pub fn selectedProjectPath(model: *const Model) []const u8 {
        if (model.sessionByIdConst(model.selected)) |session| return session.projectPath();
        return "";
    }

    pub fn project_label(model: *const Model) []const u8 {
        const path = model.selectedProjectPath();
        if (path.len > 0) return path;
        return "choose a project";
    }

    pub fn project_is_local(model: *const Model) bool {
        return model.selectedProjectPath().len == 0;
    }

    /// Runtime-only muted branch on the composer project row.
    pub fn git_branch_label(model: *const Model) []const u8 {
        return git_branch.gitBranchLabel(model);
    }

    pub fn has_git_branch(model: *const Model) bool {
        return git_branch.hasGitBranch(model);
    }

    /// Composer usage control. 0 when the live path has not reported usage.
    pub fn context_usage(model: *const Model) f32 {
        const session = model.sessionByIdConst(model.selected) orelse return 0;
        return session.contextUsageFraction();
    }

    /// Header Rewind control. Latest Send-time 40-char hex sha only; no picker.
    pub fn can_rewind(model: *const Model) bool {
        const session = model.sessionByIdConst(model.selected) orelse return false;
        return session.latestRewindSha() != null;
    }

    /// Header Fork control. Local catalog clone through the last turn.
    /// Disabled (hidden) when the selected session has no turns.
    pub fn can_fork(model: *const Model) bool {
        if (model.sessionByIdConst(model.selected) == null) return false;
        return model.turnCount(model.selected) > 0;
    }

    /// Composer `/goal` row. Live `WAKU_DAEMON_ADDRESS` or persisted
    /// `last_daemon_address`. Hidden on fx ask / fx acp / demo.
    pub fn show_goal(model: *const Model) bool {
        return store.resolveDaemonMirrorAddress(model).len > 0;
    }

    pub fn has_goal(model: *const Model) bool {
        const session = model.sessionByIdConst(model.selected) orelse return false;
        return session.threadGoalObjective().len > 0;
    }

    /// Current objective, or a muted empty label. Markup ellipsizes.
    pub fn goal_label(model: *const Model) []const u8 {
        const session = model.sessionByIdConst(model.selected) orelse return "No goal";
        if (session.threadGoalObjective().len == 0) return "No goal";
        return session.threadGoalObjective();
    }

    /// Current Codex `ThreadGoalStatus` wire name, or "Status".
    pub fn goal_status_label(model: *const Model) []const u8 {
        const session = model.sessionByIdConst(model.selected) orelse return "Status";
        if (session.threadGoalStatus().len == 0) return "Status";
        return session.threadGoalStatus();
    }

    /// True when last-known `tokensUsed` / `tokenBudget` / `timeUsedSeconds`
    /// can fill the muted composer meter.
    pub fn has_goal_usage(model: *const Model) bool {
        const session = model.sessionByIdConst(model.selected) orelse return false;
        return session.threadGoalUsageLabel().len > 0;
    }

    /// Compact `12k/100k · 3m` (or `tokensUsed` without a budget).
    pub fn goal_usage_label(model: *const Model) []const u8 {
        const session = model.sessionByIdConst(model.selected) orelse return "";
        return session.threadGoalUsageLabel();
    }

    pub fn project_edit(model: *const Model) []const u8 {
        return model.project_edit_buffer.text();
    }

    pub fn folder_title_draft(model: *const Model) []const u8 {
        return model.folder_title_buffer.text();
    }

    pub fn startFolderTitleEdit(model: *Model, folder_id: u32) void {
        const folder = model.folderByIdConst(folder_id) orelse return;
        model.closeSessionTitleEdit();
        model.editing_folder_id = folder_id;
        model.folder_title_buffer.set(folder.title());
        model.composer_active = false;
    }

    pub fn closeFolderTitleEdit(model: *Model) void {
        model.editing_folder_id = 0;
        model.folder_title_buffer.clear();
    }

    pub fn applyFolderTitle(model: *Model, edit: canvas.TextInputEvent) void {
        const folder = model.folderById(model.editing_folder_id) orelse return;
        model.folder_title_buffer.apply(edit);
        folder.setTitle(model.folder_title_draft());
    }

    pub fn session_title_draft(model: *const Model) []const u8 {
        return model.session_title_buffer.text();
    }

    pub fn session_title_editing(model: *const Model) bool {
        return model.editing_session_id != 0;
    }

    pub fn startSessionTitleEdit(model: *Model, session_id: u32) void {
        const session = model.sessionByIdConst(session_id) orelse return;
        model.closeFolderTitleEdit();
        model.editing_session_id = session_id;
        model.session_title_buffer.set(session.title());
        model.composer_active = false;
    }

    pub fn closeSessionTitleEdit(model: *Model) void {
        model.editing_session_id = 0;
        model.session_title_buffer.clear();
    }

    pub fn applySessionTitle(model: *Model, edit: canvas.TextInputEvent) void {
        const session = model.sessionById(model.editing_session_id) orelse return;
        model.session_title_buffer.apply(edit);
        session.setTitle(model.session_title_draft());
    }

    pub fn startProjectEdit(model: *Model) void {
        model.project_edit_active = true;
        model.project_edit_buffer.set(model.selectedProjectPath());
    }

    pub fn closeProjectEdit(model: *Model) void {
        model.project_edit_active = false;
    }

    pub fn applySelectedProjectPath(model: *Model, edit: canvas.TextInputEvent) void {
        model.project_edit_buffer.apply(edit);
        const path = std.mem.trim(u8, model.project_edit(), " \t\r\n");
        if (model.sessionById(model.selected)) |session| {
            session.setProjectPath(path);
        }
        model.setLastProjectPath(path);
    }

    /// Sets the selected session cwd and `last_project_path`. Same write
    /// as typing a path on the composer project row.
    pub fn setSelectedProjectPath(model: *Model, path: []const u8) void {
        const trimmed = std.mem.trim(u8, path, " \t\r\n");
        model.project_edit_buffer.set(trimmed);
        if (model.sessionById(model.selected)) |session| {
            session.setProjectPath(trimmed);
        }
        model.setLastProjectPath(trimmed);
    }

    pub fn cycleSelectedAccess(model: *Model) void {
        const session = model.sessionById(model.selected) orelse return;
        const next = nextAccessMode(model.resolvedAccessMode());
        session.setAccessMode(next);
        model.setLastAccessMode(next);
    }

    pub fn cycleSelectedInteraction(model: *Model) void {
        const session = model.sessionById(model.selected) orelse return;
        const next: []const u8 = if (std.mem.eql(u8, model.resolvedInteractionMode(), "plan")) "build" else "plan";
        session.setInteractionMode(next);
        model.setLastInteractionMode(next);
    }

    pub fn cycleSelectedEffort(model: *Model) void {
        const session = model.sessionById(model.selected) orelse return;
        const next = nextReasoningEffort(model.resolvedReasoningEffort());
        session.setReasoningEffort(next);
        model.setLastReasoningEffort(next);
    }

    pub fn pickSelectedModel(model: *Model, id: []const u8) void {
        const session = model.sessionById(model.selected) orelse return;
        var copy: [max_fx_model]u8 = undefined;
        const take = @min(id.len, copy.len);
        @memcpy(copy[0..take], id[0..take]);
        const chosen = copy[0..take];
        session.setModel(chosen);
        if (chosen.len > 0) model.setLastModel(chosen);
        model.closeModelPicker();
    }

    pub fn pickSelectedAccess(model: *Model, id: []const u8) void {
        const session = model.sessionById(model.selected) orelse return;
        if (std.mem.eql(u8, id, "ask") or std.mem.eql(u8, id, "auto") or std.mem.eql(u8, id, "fullAccess")) {
            session.setAccessMode(id);
            model.setLastAccessMode(id);
        }
        model.closeAccessPicker();
    }

    pub fn pickSelectedEffort(model: *Model, id: []const u8) void {
        const session = model.sessionById(model.selected) orelse return;
        if (isDocumentedReasoningEffort(id)) {
            session.setReasoningEffort(id);
            model.setLastReasoningEffort(id);
        }
        model.closeEffortPicker();
    }

    pub fn pickSettingsEffort(model: *Model, id: []const u8) void {
        if (isDocumentedReasoningEffort(id)) {
            model.setLastReasoningEffort(id);
        }
        model.closeSettingsEffortPicker();
    }

    pub fn fxPath(model: *const Model) []const u8 {
        return model.fx_path_storage[0..model.fx_path_len];
    }

    pub fn setFxPath(model: *Model, path: []const u8) void {
        writeFixed(&model.fx_path_storage, &model.fx_path_len, path);
    }

    pub fn setHome(model: *Model, home: []const u8) void {
        writeFixed(&model.home_storage, &model.home_len, home);
    }

    pub fn homeDir(model: *const Model) []const u8 {
        return model.home_storage[0..model.home_len];
    }

    pub fn storeDir(model: *const Model) []const u8 {
        return model.store_dir_storage[0..model.store_dir_len];
    }

    pub fn setStoreDir(model: *Model, dir: []const u8) void {
        writeFixed(&model.store_dir_storage, &model.store_dir_len, dir);
    }

    pub fn lastProjectPath(model: *const Model) []const u8 {
        return model.last_project_path_storage[0..model.last_project_path_len];
    }

    pub fn setLastProjectPath(model: *Model, path: []const u8) void {
        writeFixed(&model.last_project_path_storage, &model.last_project_path_len, path);
    }

    pub fn lastSpawnCwd(model: *const Model) []const u8 {
        return model.last_spawn_cwd_storage[0..model.last_spawn_cwd_len];
    }

    pub fn setLastSpawnCwd(model: *Model, path: []const u8) void {
        writeFixed(&model.last_spawn_cwd_storage, &model.last_spawn_cwd_len, path);
    }

    pub fn lastModel(model: *const Model) []const u8 {
        return model.last_model_storage[0..model.last_model_len];
    }

    pub fn setLastModel(model: *Model, value: []const u8) void {
        writeFixed(&model.last_model_storage, &model.last_model_len, value);
    }

    pub fn lastAccessMode(model: *const Model) []const u8 {
        return model.last_access_mode_storage[0..model.last_access_mode_len];
    }

    pub fn setLastAccessMode(model: *Model, value: []const u8) void {
        writeFixed(&model.last_access_mode_storage, &model.last_access_mode_len, value);
    }

    pub fn lastInteractionMode(model: *const Model) []const u8 {
        return model.last_interaction_mode_storage[0..model.last_interaction_mode_len];
    }

    pub fn setLastInteractionMode(model: *Model, value: []const u8) void {
        writeFixed(&model.last_interaction_mode_storage, &model.last_interaction_mode_len, value);
    }

    pub fn lastReasoningEffort(model: *const Model) []const u8 {
        return model.last_reasoning_effort_storage[0..model.last_reasoning_effort_len];
    }

    pub fn setLastReasoningEffort(model: *Model, value: []const u8) void {
        writeFixed(&model.last_reasoning_effort_storage, &model.last_reasoning_effort_len, value);
    }

    pub fn lastSpawnFxModel(model: *const Model) []const u8 {
        return model.last_spawn_fx_model_storage[0..model.last_spawn_fx_model_len];
    }

    pub fn setLastSpawnFxModel(model: *Model, value: []const u8) void {
        writeFixed(&model.last_spawn_fx_model_storage, &model.last_spawn_fx_model_len, value);
    }

    pub fn lastSpawnFxPermissionMode(model: *const Model) []const u8 {
        return model.last_spawn_fx_permission_mode_storage[0..model.last_spawn_fx_permission_mode_len];
    }

    pub fn setLastSpawnFxPermissionMode(model: *Model, value: []const u8) void {
        writeFixed(&model.last_spawn_fx_permission_mode_storage, &model.last_spawn_fx_permission_mode_len, value);
    }

    pub fn draftImagePath(model: *const Model) []const u8 {
        return model.draft_image_path_storage[0..model.draft_image_path_len];
    }

    pub fn setDraftImagePath(model: *Model, path: []const u8) void {
        writeFixed(&model.draft_image_path_storage, &model.draft_image_path_len, path);
    }

    pub fn image_edit(model: *const Model) []const u8 {
        return model.image_path_buffer.text();
    }

    pub fn has_image_attach(model: *const Model) bool {
        return model.draftImagePath().len > 0;
    }

    /// Chip stays when the path is set. Preview only when that file exists
    /// so a missing path does not bind a dead `<image>`.
    pub fn has_image_preview(model: *const Model) bool {
        return model.resolveSpawnImage().len > 0;
    }

    pub fn image_chip_label(model: *const Model) []const u8 {
        const path = model.draftImagePath();
        if (path.len == 0) return "";
        return std.fs.path.basename(path);
    }

    pub fn attach_status(model: *const Model) []const u8 {
        return model.attach_status_storage[0..model.attach_status_len];
    }

    pub fn has_attach_status(model: *const Model) bool {
        return model.attach_status_len > 0;
    }

    pub fn setAttachStatus(model: *Model, text: []const u8) void {
        writeFixed(&model.attach_status_storage, &model.attach_status_len, std.mem.trim(u8, text, " \t\r\n"));
    }

    pub fn clearAttachStatus(model: *Model) void {
        model.attach_status_len = 0;
    }

    pub fn window_status(model: *const Model) []const u8 {
        return model.window_status_storage[0..model.window_status_len];
    }

    pub fn has_window_status(model: *const Model) bool {
        return model.window_status_len > 0;
    }

    pub fn setWindowStatus(model: *Model, text: []const u8) void {
        writeFixed(&model.window_status_storage, &model.window_status_len, std.mem.trim(u8, text, " \t\r\n"));
    }

    pub fn clearWindowStatus(model: *Model) void {
        model.window_status_len = 0;
    }

    pub fn startImageAttach(model: *Model) void {
        model.image_attach_active = true;
        model.image_path_buffer.set(model.draftImagePath());
    }

    pub fn closeImageAttach(model: *Model) void {
        model.image_attach_active = false;
    }

    pub fn applyImagePath(model: *Model, edit: canvas.TextInputEvent) void {
        model.image_path_buffer.apply(edit);
        model.setDraftImagePath(std.mem.trim(u8, model.image_edit(), " \t\r\n"));
    }

    pub fn clearImageAttach(model: *Model) void {
        model.setDraftImagePath("");
        model.image_path_buffer.clear();
        model.image_attach_active = false;
    }

    pub fn toggleCommands(model: *Model) void {
        if (!model.has_commands()) {
            model.commands_open = false;
            return;
        }
        model.commands_open = !model.commands_open;
    }

    pub fn closeCommands(model: *Model) void {
        model.commands_open = false;
    }

    /// Official ACP slash insert is `/name` plus a trailing space so the
    /// user can type input. This cut does not store `input`; space is
    /// always appended. Writes the composer draft only — no spawn.
    pub fn insertAvailableCommand(model: *Model, id: u32) void {
        const session = model.sessionById(model.selected) orelse return;
        if (id == 0 or id > session.available_command_count) return;
        const cmd = session.available_commands[id - 1];
        var buf: [max_command_name + 2]u8 = undefined;
        const text = std.fmt.bufPrint(&buf, "/{s} ", .{cmd.name()}) catch return;
        model.draft_buffer.set(text);
        model.commands_open = false;
    }

    pub fn lastSpawnImagePath(model: *const Model) []const u8 {
        return model.last_spawn_image_path_storage[0..model.last_spawn_image_path_len];
    }

    pub fn setLastSpawnImagePath(model: *Model, path: []const u8) void {
        writeFixed(&model.last_spawn_image_path_storage, &model.last_spawn_image_path_len, path);
    }

    pub fn daemonAddress(model: *const Model) []const u8 {
        return model.daemon_address_storage[0..model.daemon_address_len];
    }

    pub fn setDaemonAddress(model: *Model, addr: []const u8) void {
        writeFixed(&model.daemon_address_storage, &model.daemon_address_len, addr);
        if (addr.len > 0) model.setLastDaemonAddress(addr);
    }

    pub fn lastDaemonAddress(model: *const Model) []const u8 {
        return model.last_daemon_address_storage[0..model.last_daemon_address_len];
    }

    pub fn setLastDaemonAddress(model: *Model, addr: []const u8) void {
        writeFixed(&model.last_daemon_address_storage, &model.last_daemon_address_len, addr);
    }

    pub fn daemonToken(model: *const Model) []const u8 {
        return model.daemon_token_storage[0..model.daemon_token_len];
    }

    pub fn setDaemonToken(model: *Model, token: []const u8) void {
        writeFixed(&model.daemon_token_storage, &model.daemon_token_len, token);
    }

    pub fn sidecarPath(model: *const Model) []const u8 {
        if (model.sidecar_path_len == 0) return "faku";
        return model.sidecar_path_storage[0..model.sidecar_path_len];
    }

    pub fn setSidecarPath(model: *Model, path: []const u8) void {
        writeFixed(&model.sidecar_path_storage, &model.sidecar_path_len, path);
    }

    /// `fx ask --image` path when the draft has a non-empty path that exists.
    /// Missing files omit the flag; Native spawn has no attachment/blob API.
    pub fn resolveSpawnImage(model: *const Model) []const u8 {
        const path = model.draftImagePath();
        if (path.len == 0) return "";
        const io = model.store_io orelse return "";
        if (!main.fileExists(io, path)) return "";
        return path;
    }

    /// Child cwd for `fx ask`: session project_path when it is non-empty and
    /// a real directory. Otherwise empty — Native spawn has no cwd field
    /// (0.9.3 SpawnOptions), so an empty result leaves the host process cwd.
    pub fn resolveSpawnCwd(model: *const Model, session: *const Session) []const u8 {
        const path = session.projectPath();
        if (path.len == 0) return "";
        const io = model.store_io orelse return "";
        if (!main.directoryExists(io, path)) return "";
        return path;
    }

    /// `session/new` / `session/resume` cwd: project_path when it exists,
    /// else ".". ACP requires a cwd string; this cut does not invent an
    /// absolute-path resolver.
    pub fn resolveAcpCwd(model: *const Model, session: *const Session) []const u8 {
        const path = model.resolveSpawnCwd(session);
        if (path.len > 0) return path;
        return acp_cwd_fallback;
    }

    fn activeSession(model: *Model) ?*Session {
        return model.sessionById(model.selected);
    }

    fn activeSessionConst(model: *const Model) ?*const Session {
        for (model.session_store[0..model.session_count]) |*session| {
            if (session.id == model.selected) return session;
        }
        return null;
    }

    pub fn sessionById(model: *Model, id: u32) ?*Session {
        for (model.session_store[0..model.session_count]) |*session| {
            if (session.id == id) return session;
        }
        return null;
    }

    pub fn sessionByIdConst(model: *const Model, id: u32) ?*const Session {
        for (model.session_store[0..model.session_count]) |*session| {
            if (session.id == id) return session;
        }
        return null;
    }

    pub fn turnById(model: *Model, id: u32) ?*Turn {
        for (model.turn_store[0..model.turn_count]) |*turn| {
            if (turn.id == id) return turn;
        }
        return null;
    }

    pub fn addFolder(model: *Model, title_text: []const u8) u32 {
        if (model.folder_count >= max_folders) return 0;
        var folder = Folder{ .id = model.next_folder_id };
        writeFixed(&folder.title_storage, &folder.title_len, title_text);
        model.folder_store[model.folder_count] = folder;
        model.folder_count += 1;
        model.next_folder_id += 1;
        return folder.id;
    }

    pub fn restoreFolder(model: *Model, id: u32, title_text: []const u8, collapsed: bool) void {
        if (model.folder_count >= max_folders) return;
        var folder = Folder{ .id = id, .collapsed = collapsed };
        writeFixed(&folder.title_storage, &folder.title_len, title_text);
        model.folder_store[model.folder_count] = folder;
        model.folder_count += 1;
        if (id >= model.next_folder_id) model.next_folder_id = id + 1;
    }

    pub fn clearFolders(model: *Model) void {
        model.folder_count = 0;
        model.next_folder_id = 1;
    }

    pub fn folderById(model: *Model, id: u32) ?*Folder {
        for (model.folder_store[0..model.folder_count]) |*folder| {
            if (folder.id == id) return folder;
        }
        return null;
    }

    pub fn folderByIdConst(model: *const Model, id: u32) ?*const Folder {
        for (model.folder_store[0..model.folder_count]) |*folder| {
            if (folder.id == id) return folder;
        }
        return null;
    }

    pub fn assignSessionFolder(model: *Model, session_id: u32, folder_id: u32) bool {
        const session = model.sessionById(session_id) orelse return false;
        if (folder_id != 0 and model.folderById(folder_id) == null) return false;
        session.folder_id = folder_id;
        return true;
    }

    pub fn toggleFolderCollapsed(model: *Model, folder_id: u32) void {
        const folder = model.folderById(folder_id) orelse return;
        folder.collapsed = !folder.collapsed;
    }

    /// Mark every catalog folder collapsed. Does not touch `sidebar_collapsed`
    /// (the rail). Returns whether any folder actually changed.
    pub fn collapseAllFolders(model: *Model) bool {
        var changed = false;
        for (model.folder_store[0..model.folder_count]) |*folder| {
            if (folder.collapsed) continue;
            folder.collapsed = true;
            changed = true;
        }
        return changed;
    }

    pub fn all_folders_collapsed(model: *const Model) bool {
        if (model.folder_count == 0) return true;
        for (model.folder_store[0..model.folder_count]) |folder| {
            if (!folder.collapsed) return false;
        }
        return true;
    }

    pub fn can_collapse_folders(model: *const Model) bool {
        return model.folder_count > 0 and !model.all_folders_collapsed();
    }

    /// Drop folder F and unassign its sessions (`folder_id` 0 → Today).
    /// Sessions stay. This is Waku-style group delete, not `removeSession`.
    pub fn deleteFolder(model: *Model, folder_id: u32) bool {
        if (model.folderById(folder_id) == null) return false;
        if (model.editing_folder_id == folder_id) model.closeFolderTitleEdit();
        for (model.session_store[0..model.session_count]) |*session| {
            if (session.folder_id == folder_id) session.folder_id = 0;
        }
        var kept: u32 = 0;
        for (model.folder_store[0..model.folder_count]) |folder| {
            if (folder.id == folder_id) continue;
            model.folder_store[kept] = folder;
            kept += 1;
        }
        model.folder_count = kept;
        return true;
    }

    pub fn nextUntitledFolderTitle(model: *const Model, buf: []u8) []const u8 {
        if (!sidebar_row_helpers.folderTitleTaken(model, "New folder")) return "New folder";
        var n: u32 = 2;
        while (n < 1000) : (n += 1) {
            const title = std.fmt.bufPrint(buf, "New folder {d}", .{n}) catch return "New folder";
            if (!sidebar_row_helpers.folderTitleTaken(model, title)) return title;
        }
        return "New folder";
    }

    pub fn addSession(model: *Model, title_text: []const u8, provider: Provider) u32 {
        if (model.session_count >= max_sessions) return 0;
        var session = Session{ .id = model.next_id, .provider = provider };
        writeFixed(&session.title_storage, &session.title_len, title_text);
        writeFixed(&session.project_path_storage, &session.project_path_len, model.lastProjectPath());
        writeFixed(&session.model_storage, &session.model_len, model.lastModel());
        const access = if (model.lastAccessMode().len > 0) model.lastAccessMode() else default_access_mode;
        writeFixed(&session.access_mode_storage, &session.access_mode_len, access);
        const interaction = if (model.lastInteractionMode().len > 0) model.lastInteractionMode() else default_interaction_mode;
        writeFixed(&session.interaction_mode_storage, &session.interaction_mode_len, interaction);
        const effort = if (model.lastReasoningEffort().len > 0) model.lastReasoningEffort() else default_reasoning_effort;
        writeFixed(&session.reasoning_effort_storage, &session.reasoning_effort_len, effort);
        session.updated_at = model.now_ms;
        model.session_store[model.session_count] = session;
        model.session_count += 1;
        model.next_id += 1;
        return session.id;
    }

    pub fn appendTurn(model: *Model, session_id: u32, role: Role, body: []const u8) u32 {
        if (model.turn_count >= max_turns) return 0;
        var turn = Turn{ .id = model.next_turn_id, .session_id = session_id, .role = role };
        writeFixed(&turn.body_storage, &turn.body_len, body);
        model.turn_store[model.turn_count] = turn;
        model.turn_count += 1;
        model.next_turn_id += 1;
        if (model.sessionById(session_id)) |session| {
            session.has_started = true;
            if (role == .user or role == .assistant) main.stampSessionActivity(session, model.now_ms);
        }
        if (model.transcript_pinned and (session_id == model.selected or model.selected == 0)) {
            model.pinTranscriptToLatest();
        }
        return turn.id;
    }

    pub fn clearSessions(model: *Model) void {
        model.session_count = 0;
        model.turn_count = 0;
        model.queued_count = 0;
        model.selected = 0;
        model.history_count = 0;
        model.history_index = 0;
        model.next_id = 1;
        model.next_turn_id = 1;
        model.next_queued_id = 1;
    }

    pub fn enqueue(model: *Model, session_id: u32, text: []const u8) u32 {
        if (model.sessionById(session_id) == null) return 0;
        if (model.queued_count >= max_queued) return 0;
        var item = QueuedMessage{ .id = model.next_queued_id, .session_id = session_id };
        writeFixed(&item.text_storage, &item.text_len, text);
        model.queued_store[model.queued_count] = item;
        model.queued_count += 1;
        model.next_queued_id += 1;
        return item.id;
    }

    pub fn queuedCount(model: *const Model, session_id: u32) u32 {
        var n: u32 = 0;
        for (model.queued_store[0..model.queued_count]) |item| {
            if (item.session_id == session_id) n += 1;
        }
        return n;
    }

    pub fn turnCount(model: *const Model, session_id: u32) u32 {
        var n: u32 = 0;
        for (model.turn_store[0..model.turn_count]) |turn| {
            if (turn.session_id == session_id) n += 1;
        }
        return n;
    }

    pub fn firstQueuedText(model: *const Model, session_id: u32) []const u8 {
        for (model.queued_store[0..model.queued_count]) |*item| {
            if (item.session_id == session_id) return item.text();
        }
        return "";
    }

    pub fn takeNextQueued(model: *Model, session_id: u32, dest: []u8) ?usize {
        var i: usize = 0;
        while (i < model.queued_count) : (i += 1) {
            if (model.queued_store[i].session_id != session_id) continue;
            const n = @min(dest.len, model.queued_store[i].text_len);
            @memcpy(dest[0..n], model.queued_store[i].text_storage[0..n]);
            var j = i;
            while (j + 1 < model.queued_count) : (j += 1) {
                model.queued_store[j] = model.queued_store[j + 1];
            }
            model.queued_count -= 1;
            return n;
        }
        return null;
    }

    pub fn restoreQueued(model: *Model, id: u32, session_id: u32, text: []const u8) void {
        if (model.queued_count >= max_queued) return;
        var item = QueuedMessage{ .id = id, .session_id = session_id };
        writeFixed(&item.text_storage, &item.text_len, text);
        model.queued_store[model.queued_count] = item;
        model.queued_count += 1;
        if (id >= model.next_queued_id) model.next_queued_id = id + 1;
    }

    pub fn dropQueuedForSession(model: *Model, session_id: u32) void {
        var kept: u32 = 0;
        for (model.queued_store[0..model.queued_count]) |item| {
            if (item.session_id == session_id) continue;
            model.queued_store[kept] = item;
            kept += 1;
        }
        model.queued_count = kept;
    }

    pub fn dropQueued(model: *Model, id: u32) bool {
        var i: usize = 0;
        while (i < model.queued_count) : (i += 1) {
            if (model.queued_store[i].id != id) continue;
            var j = i;
            while (j + 1 < model.queued_count) : (j += 1) {
                model.queued_store[j] = model.queued_store[j + 1];
            }
            model.queued_count -= 1;
            return true;
        }
        return false;
    }

    /// Copy that queued item's text into dest, compact it out like
    /// `dropQueued`, and return the copied length. Unknown id → null.
    pub fn takeQueued(model: *Model, id: u32, dest: []u8) ?usize {
        var i: usize = 0;
        while (i < model.queued_count) : (i += 1) {
            if (model.queued_store[i].id != id) continue;
            const n = @min(dest.len, model.queued_store[i].text_len);
            @memcpy(dest[0..n], model.queued_store[i].text_storage[0..n]);
            if (!model.dropQueued(id)) return null;
            return n;
        }
        return null;
    }

    pub fn restoreSession(
        model: *Model,
        id: u32,
        title_text: []const u8,
        provider: Provider,
        untitled: bool,
        has_started: bool,
        project_path: []const u8,
        fx_session_id: []const u8,
        model_id: []const u8,
        access_mode: []const u8,
        runtime_id: []const u8,
        interaction_mode: []const u8,
        reasoning_effort: []const u8,
        folder_id: u32,
        updated_at: i64,
    ) void {
        if (model.session_count >= max_sessions) return;
        var session = Session{
            .id = id,
            .provider = provider,
            .untitled = untitled,
            .has_started = has_started,
            .detail_loaded = false,
            .updated_at = updated_at,
        };
        writeFixed(&session.title_storage, &session.title_len, title_text);
        writeFixed(&session.project_path_storage, &session.project_path_len, project_path);
        writeFixed(&session.fx_session_id_storage, &session.fx_session_id_len, fx_session_id);
        writeFixed(&session.model_storage, &session.model_len, model_id);
        writeFixed(&session.access_mode_storage, &session.access_mode_len, access_mode);
        writeFixed(&session.runtime_id_storage, &session.runtime_id_len, runtime_id);
        writeFixed(&session.interaction_mode_storage, &session.interaction_mode_len, interaction_mode);
        writeFixed(&session.reasoning_effort_storage, &session.reasoning_effort_len, reasoning_effort);
        session.folder_id = folder_id;
        model.session_store[model.session_count] = session;
        model.session_count += 1;
        if (id >= model.next_id) model.next_id = id + 1;
    }

    pub fn restoreTurn(model: *Model, id: u32, session_id: u32, role: Role, body: []const u8) void {
        if (model.turn_count >= max_turns) return;
        var turn = Turn{ .id = id, .session_id = session_id, .role = role };
        writeFixed(&turn.body_storage, &turn.body_len, body);
        model.turn_store[model.turn_count] = turn;
        model.turn_count += 1;
        if (id >= model.next_turn_id) model.next_turn_id = id + 1;
    }

    pub fn dropTurnsForSession(model: *Model, session_id: u32) void {
        var kept: u32 = 0;
        for (model.turn_store[0..model.turn_count]) |turn| {
            if (turn.session_id == session_id) continue;
            model.turn_store[kept] = turn;
            kept += 1;
        }
        model.turn_count = kept;
    }

    /// Drop the trailing user turn plus following assistant / tool / thought
    /// turns for this session. Empty remaining transcript is fine.
    pub fn dropLastPromptTurns(model: *Model, session_id: u32) void {
        var last_user: ?usize = null;
        for (model.turn_store[0..model.turn_count], 0..) |turn, i| {
            if (turn.session_id == session_id and turn.role == .user) last_user = i;
        }
        const start = last_user orelse return;
        var kept: u32 = 0;
        for (model.turn_store[0..model.turn_count], 0..) |turn, i| {
            if (turn.session_id == session_id and i >= start) continue;
            model.turn_store[kept] = turn;
            kept += 1;
        }
        model.turn_count = kept;
    }

    pub fn dropSession(model: *Model, session_id: u32) void {
        model.dropTurnsForSession(session_id);
        model.dropQueuedForSession(session_id);
        model.dropSelectionHistory(session_id);
        var kept: u32 = 0;
        for (model.session_store[0..model.session_count]) |session| {
            if (session.id == session_id) continue;
            model.session_store[kept] = session;
            kept += 1;
        }
        model.session_count = kept;
        if (model.selected == session_id) {
            model.selected = if (model.session_count > 0) model.session_store[0].id else 0;
        }
    }

    pub fn appendToTurn(model: *Model, turn_id: u32, extra: []const u8) void {
        const turn = model.turnById(turn_id) orelse return;
        const session_id = turn.session_id;
        const room = turn.body_storage.len - turn.body_len;
        const take = @min(room, extra.len);
        if (take == 0) return;
        @memcpy(turn.body_storage[turn.body_len..][0..take], extra[0..take]);
        turn.body_len += take;
        if (model.transcript_pinned and session_id == model.selected) {
            model.pinTranscriptToLatest();
        }
    }
};

fn commandNameStartsWith(name: []const u8, prefix: []const u8) bool {
    if (prefix.len == 0) return true;
    if (prefix.len > name.len) return false;
    return asciiEqlIgnoreCase(name[0..prefix.len], prefix);
}

fn hasCommandNamePrefix(model: *const Model, prefix: []const u8) bool {
    const session = model.sessionByIdConst(model.selected) orelse return false;
    for (session.availableCommands()) |*cmd| {
        if (commandNameStartsWith(cmd.name(), prefix)) return true;
    }
    return false;
}


fn asciiEqlIgnoreCase(left: []const u8, right: []const u8) bool {
    if (left.len != right.len) return false;
    for (left, right) |a, b| {
        if (std.ascii.toLower(a) != std.ascii.toLower(b)) return false;
    }
    return true;
}

