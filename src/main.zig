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
const rewind = @import("rewind.zig");

pub const panic = std.debug.FullPanic(native_sdk.debug.capturePanic);

const canvas = native_sdk.canvas;
const geometry = native_sdk.geometry;

const canvas_label = "main-canvas";
/// Declared shell-window label. Chromeless close/minimize ride
/// `fx.closeWindow` / `fx.minimizeWindow` against this spelling —
/// same address as `app.zon` / the scene. Unknown label is a no-op.
pub const main_window_label = "main";
pub const window_width: f32 = 1380;
pub const window_height: f32 = 880;
pub const window_min_width: f32 = 560;
pub const window_min_height: f32 = 480;
pub const sidebar_default_width: f32 = 252;
pub const sidebar_min_width: f32 = 180;
pub const sidebar_max_width: f32 = 420;
pub const sidebar_rail_width: f32 = 48;
const default_sidebar_split: f32 = sidebar_default_width / window_width;

const max_sessions = 16;
const max_folders = 16;
/// Sidebar folder-header keys sit above session ids so `for` keys stay unique.
pub const folder_row_id_base: u32 = 1_000_000;
/// In-memory session selection history for sidebar Back / Forward.
pub const selection_history_cap: u32 = 32;
/// Runtime-only Ctrl-Tab switcher snapshot. Same cap as Waku's overlay.
pub const switcher_cap: u32 = 10;
/// Palette action keys sit above folder-header keys so `for` keys stay unique.
pub const palette_action_id_base: u32 = 2_000_000;
/// Palette section-header keys sit above action keys.
pub const palette_header_id_base: u32 = 3_000_000;
/// Runtime-only command palette. Same caps as Waku's overlay card.
pub const palette_max_task_results: u32 = 12;
pub const palette_result_row_height: f32 = 44;
pub const palette_search_row_height: f32 = 60;
pub const palette_section_header_height: f32 = 30;
pub const palette_card_width: f32 = 680;
pub const palette_card_height: f32 = 480;
const max_turns = 128;
const max_title = 64;
const max_search = 64;
const max_body = 4096;
pub const max_draft = 512;
pub const max_queued = 16;
pub const max_queued_text = 1024;
const max_fx_path = 256;
pub const max_store_dir = 512;
pub const max_project_path = 512;
pub const max_fx_session_id = 128;
pub const max_tool_call_id = 128;
pub const max_tool_kind = 32;
pub const max_tool_status = 32;
pub const max_runtime_id = 36;
pub const max_fx_model = 128;
pub const max_access_mode = 32;
pub const max_interaction_mode = 16;
pub const max_reasoning_effort = 16;
pub const max_available_commands = acp.max_available_commands;
pub const max_model_options = acp.max_model_options;
pub const max_command_name = 64;
pub const max_command_description = 256;
/// Waku `runtime_mode` default. Maps to fx `FX_PERMISSION_MODE=yolo`.
pub const default_access_mode = "fullAccess";
/// Waku `StartOptions.interaction_mode` default (`build` | `plan`).
pub const default_interaction_mode = "build";
/// fx documented `effort` default (`auto` | `none` | `minimal` | `low` |
/// `medium` | `high` | `xhigh` | `max`).
pub const default_reasoning_effort = "auto";
pub const fx_env_bin = "/usr/bin/env";
const max_line_keep = 4096;

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
    .titlebar = .chromeless,
    .views = &shell_views,
}};
pub const shell_scene: native_sdk.ShellConfig = .{ .windows = &shell_windows };

/// Chromeless Minimize bar. The built-in icon set has no minus
/// (`examples/deck`); Native check rejects an invented `icon="minus"`.
const minimize_icon = canvas.svg_icon.parseComptime(@embedFile("icons/minimize.svg"));

/// One table feeds boot registration and the model contract so
/// `icon="app:minimize"` is verified against what `main` registers.
pub const app_icons = [_]canvas.icons.Entry{
    .{ .name = "minimize", .icon = &minimize_icon },
};

/// Install the app icon table once, before views build.
pub fn registerIcons() void {
    canvas.icons.registerAppIcons(&app_icons);
}

pub const stream_timer_key: u64 = 1;
pub const fx_ask_key: u64 = 2;
pub const fx_probe_key: u64 = 3;
pub const daemon_proxy_key_first: u64 = 4;
/// Overlapping one-shot `fx acp` / `fx ask` children (queue drain while
/// the previous process has not exited yet). Avoids probe/daemon keys.
pub const fx_spawn_overlap_key_first: u64 = 64;
pub const acp_cwd_fallback = ".";
pub const max_daemon_address = 128;
pub const max_daemon_token = 256;
pub const max_sidecar_path = 512;
pub const daemon_line_bytes: usize = 64 * 1024;
pub const stream_interval_ms: u64 = 90;
const stream_chunk_bytes: usize = 8;
/// Overshoot for a programmatic jump to the transcript end. Native
/// clamps `scroll` `value` against the content edge
/// (`content_extent_y - viewport_extent_y`), so a large source offset
/// lands on the newest turn after layout. Verified: native-sdk.dev
/// scroll docs + engine clamp.
pub const transcript_pin_offset: f32 = 1_000_000;
/// Caller-chosen identity for `fx.writeClipboard` on a transcript
/// turn or a joined session. Shares the effects key space with spawn /
/// fetch / file; sits in the gap between daemon keys and
/// `fx_spawn_overlap`. Verified: Native Effects `WriteClipboardOptions`
/// + notes example.
pub const copy_turn_key: u64 = 32;
/// Worst-case join of every in-memory turn with a blank line between.
const max_copy_session = max_turns * max_body + (max_turns - 1) * 2;
/// Scratch for `copySession`. `writeClipboard` copies `.text` during
/// the call; this outlives the join so the slice stays valid.
var copy_session_buf: [max_copy_session]u8 = undefined;
/// Caller-chosen ImageId for the composer attach preview. `fx.loadImage`
/// uses this as the effect key (shared with spawn / clipboard / file).
/// 0 is the no-image sentinel. Sits in the gap after `copy_turn_key`
/// and before `fx_spawn_overlap`. Verified: Native 0.9.3
/// `LoadImageOptions` + markup `<image image="{binding}">`.
pub const attach_preview_id_first: u64 = 33;
pub const attach_preview_id_last: u64 = 63;
const demo_ticks_complete: u32 = 12;
const demo_reply = "fx here (demo). The fx CLI was not found, so this is a local timer stream. Install fx and Send runs `fx ask`.";

pub const Mode = enum { demo, daemon };
pub const Role = enum { user, assistant, tool, reasoning };
pub const Phase = enum { idle, streaming };
pub const ReplyPath = enum { demo, fx, daemon };

pub const Provider = protocol.ProviderId;

/// Stored ACP slash command (name + optional description). Composer
/// Commands inserts `/name ` into the draft. Not a palette RPC and
/// not `session/prompt` execution.
pub const AvailableCommand = struct {
    name_storage: [max_command_name]u8 = [_]u8{0} ** max_command_name,
    name_len: usize = 0,
    description_storage: [max_command_description]u8 = [_]u8{0} ** max_command_description,
    description_len: usize = 0,

    pub fn name(self: *const AvailableCommand) []const u8 {
        return self.name_storage[0..self.name_len];
    }

    pub fn description(self: *const AvailableCommand) []const u8 {
        return self.description_storage[0..self.description_len];
    }
};

/// Stored ACP model `options[]` entry. `id` is the wire value; `label`
/// is `name`, falling back to `value` when name is empty.
pub const ModelOption = struct {
    id_storage: [max_fx_model]u8 = [_]u8{0} ** max_fx_model,
    id_len: usize = 0,
    label_storage: [max_fx_model]u8 = [_]u8{0} ** max_fx_model,
    label_len: usize = 0,

    pub fn id(self: *const ModelOption) []const u8 {
        return self.id_storage[0..self.id_len];
    }

    pub fn label(self: *const ModelOption) []const u8 {
        return self.label_storage[0..self.label_len];
    }
};

pub const Session = struct {
    id: u32 = 0,
    title_storage: [max_title]u8 = [_]u8{0} ** max_title,
    title_len: usize = 0,
    provider: Provider = .fx,
    busy: bool = false,
    untitled: bool = false,
    has_started: bool = false,
    /// Process-local. Catalog load leaves this false; hydrate sets it.
    detail_loaded: bool = true,
    /// One daemon hydrate attempt per session this process. Failed sidecar
    /// keeps the empty transcript and does not retry on every select.
    daemon_hydrate_started: bool = false,
    /// Workspace path for `fx ask`. Empty means inherit the host process cwd.
    project_path_storage: [max_project_path]u8 = [_]u8{0} ** max_project_path,
    project_path_len: usize = 0,
    /// Saved fx session id (`fx ask --json` `session_id` / ACP `sessionId`).
    /// fx ACP sessions are the same saved sessions as interactive fx.
    fx_session_id_storage: [max_fx_session_id]u8 = [_]u8{0} ** max_fx_session_id,
    fx_session_id_len: usize = 0,
    /// Daemon `sessionRuntime.runtimeId`. Empty until attach returns one.
    runtime_id_storage: [max_runtime_id]u8 = [_]u8{0} ** max_runtime_id,
    runtime_id_len: usize = 0,
    /// Attach / start `supportsSteer`. Unknown and false both stay false
    /// (Waku queues in those cases; this port does the same).
    supports_steer: bool = false,
    /// Gateway model id for `FX_MODEL`. Empty inherits fx's own default.
    model_storage: [max_fx_model]u8 = [_]u8{0} ** max_fx_model,
    model_len: usize = 0,
    /// Waku `runtime_mode` (ask | autoAcceptEdits | auto | fullAccess).
    access_mode_storage: [max_access_mode]u8 = [_]u8{0} ** max_access_mode,
    access_mode_len: usize = 0,
    /// Waku `StartOptions.interaction_mode` (build | plan).
    interaction_mode_storage: [max_interaction_mode]u8 = [_]u8{0} ** max_interaction_mode,
    interaction_mode_len: usize = 0,
    /// fx documented effort / Waku `StartOptions.reasoningEffort`.
    reasoning_effort_storage: [max_reasoning_effort]u8 = [_]u8{0} ** max_reasoning_effort,
    reasoning_effort_len: usize = 0,
    /// Send-time HEAD snapshots. Cap last 20. Rewind uses the latest sha.
    rewind_refs: [rewind.max_refs]rewind.Ref = [_]rewind.Ref{.{}} ** rewind.max_refs,
    rewind_ref_count: usize = 0,
    /// 0 = ungrouped (Today). Unknown ids also render under Today.
    folder_id: u32 = 0,
    /// Last ACP `usage_update` token counts. `context_size == 0` means unknown.
    context_used: u64 = 0,
    context_size: u64 = 0,
    /// Last ACP `available_commands_update`. Replace, not append.
    /// Composer Commands inserts from this list; it does not run them.
    available_commands: [max_available_commands]AvailableCommand = [_]AvailableCommand{.{}} ** max_available_commands,
    available_command_count: usize = 0,
    /// Last ACP model `options[]` catalog. Replace, not append.
    /// Runtime-only; empty array is a real clear.
    model_options: [max_model_options]ModelOption = [_]ModelOption{.{}} ** max_model_options,
    model_option_count: usize = 0,

    pub fn title(self: *const Session) []const u8 {
        return self.title_storage[0..self.title_len];
    }

    pub fn setTitle(self: *Session, title_text: []const u8) void {
        const trimmed = std.mem.trim(u8, title_text, " \t\r\n");
        const resolved = if (trimmed.len == 0) "untitled" else trimmed;
        writeFixed(&self.title_storage, &self.title_len, resolved);
        if (trimmed.len > 0) self.untitled = false;
    }

    pub fn projectPath(self: *const Session) []const u8 {
        return self.project_path_storage[0..self.project_path_len];
    }

    pub fn setProjectPath(self: *Session, path: []const u8) void {
        writeFixed(&self.project_path_storage, &self.project_path_len, path);
    }

    pub fn fxSessionId(self: *const Session) []const u8 {
        return self.fx_session_id_storage[0..self.fx_session_id_len];
    }

    pub fn setFxSessionId(self: *Session, id: []const u8) void {
        writeFixed(&self.fx_session_id_storage, &self.fx_session_id_len, id);
    }

    pub fn runtimeId(self: *const Session) []const u8 {
        return self.runtime_id_storage[0..self.runtime_id_len];
    }

    pub fn setRuntimeId(self: *Session, id: []const u8) void {
        writeFixed(&self.runtime_id_storage, &self.runtime_id_len, id);
    }

    pub fn model(self: *const Session) []const u8 {
        return self.model_storage[0..self.model_len];
    }

    pub fn setModel(self: *Session, value: []const u8) void {
        writeFixed(&self.model_storage, &self.model_len, value);
    }

    pub fn accessMode(self: *const Session) []const u8 {
        return self.access_mode_storage[0..self.access_mode_len];
    }

    pub fn setAccessMode(self: *Session, value: []const u8) void {
        writeFixed(&self.access_mode_storage, &self.access_mode_len, value);
    }

    pub fn interactionMode(self: *const Session) []const u8 {
        return self.interaction_mode_storage[0..self.interaction_mode_len];
    }

    pub fn setInteractionMode(self: *Session, value: []const u8) void {
        writeFixed(&self.interaction_mode_storage, &self.interaction_mode_len, value);
    }

    pub fn reasoningEffort(self: *const Session) []const u8 {
        return self.reasoning_effort_storage[0..self.reasoning_effort_len];
    }

    pub fn setReasoningEffort(self: *Session, value: []const u8) void {
        writeFixed(&self.reasoning_effort_storage, &self.reasoning_effort_len, value);
    }

    pub fn rewindRefs(self: *const Session) []const rewind.Ref {
        return self.rewind_refs[0..self.rewind_ref_count];
    }

    pub fn clearRewindRefs(self: *Session) void {
        self.rewind_ref_count = 0;
    }

    pub fn appendRewindRef(self: *Session, sha: []const u8, ref_name: []const u8, recorded_at: i64) void {
        rewind.append(&self.rewind_refs, &self.rewind_ref_count, sha, ref_name, recorded_at);
    }

    pub fn latestRewindSha(self: *const Session) ?[]const u8 {
        return rewind.latestStoredSha(self.rewindRefs());
    }

    pub fn popLatestRewindRef(self: *Session) void {
        rewind.popLatestStored(&self.rewind_refs, &self.rewind_ref_count);
    }

    pub fn setContextUsage(self: *Session, used: u64, size: u64) void {
        self.context_used = used;
        self.context_size = size;
    }

    pub fn availableCommands(self: *const Session) []const AvailableCommand {
        return self.available_commands[0..self.available_command_count];
    }

    pub fn clearAvailableCommands(self: *Session) void {
        self.available_command_count = 0;
    }

    pub fn appendAvailableCommand(self: *Session, name: []const u8, description: []const u8) void {
        if (name.len == 0) return;
        if (self.available_command_count >= max_available_commands) return;
        var stored = AvailableCommand{};
        writeFixed(&stored.name_storage, &stored.name_len, name);
        writeFixed(&stored.description_storage, &stored.description_len, description);
        self.available_commands[self.available_command_count] = stored;
        self.available_command_count += 1;
    }

    pub fn replaceAvailableCommands(self: *Session, commands: []const acp.ParsedCommand) void {
        self.clearAvailableCommands();
        for (commands) |cmd| {
            self.appendAvailableCommand(cmd.name, cmd.description);
        }
    }

    pub fn modelOptions(self: *const Session) []const ModelOption {
        return self.model_options[0..self.model_option_count];
    }

    pub fn clearModelOptions(self: *Session) void {
        self.model_option_count = 0;
    }

    pub fn appendModelOption(self: *Session, option_id: []const u8, option_label: []const u8) void {
        if (self.model_option_count >= max_model_options) return;
        var stored = ModelOption{};
        writeFixed(&stored.id_storage, &stored.id_len, option_id);
        const resolved = if (option_label.len > 0) option_label else option_id;
        writeFixed(&stored.label_storage, &stored.label_len, resolved);
        self.model_options[self.model_option_count] = stored;
        self.model_option_count += 1;
    }

    pub fn replaceModelOptions(self: *Session, options: []const acp.ParsedModelOption) void {
        self.clearModelOptions();
        for (options) |opt| {
            self.appendModelOption(opt.value, opt.name);
        }
    }

    /// Native `progress` is a 0..1 fraction. Missing usage stays 0.
    pub fn contextUsageFraction(self: *const Session) f32 {
        if (self.context_size == 0) return 0;
        const used = @min(self.context_used, self.context_size);
        return @as(f32, @floatFromInt(used)) / @as(f32, @floatFromInt(self.context_size));
    }

    pub fn provider_label(self: *const Session) []const u8 {
        return self.provider.wireName();
    }

    /// A skeleton came from a stored row, so it has started even without turns.
    pub fn hasStarted(self: *const Session) bool {
        return !self.detail_loaded or self.has_started;
    }
};

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

/// Flattened Today sessions + folder headers + folder sessions for the sidebar.
pub const SidebarRow = struct {
    id: u32,
    title: []const u8,
    provider: []const u8,
    selected: bool,
    is_header: bool,
    editing: bool,
    folder_id: u32,
    /// True for session rows nested under a folder (`folder_id != 0`).
    /// False for folder headers and Today / unassigned sessions.
    grouped: bool = false,
    /// Process-local. Headers stay false; store schema does not persist this.
    busy: bool = false,
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

/// Composer access/effort picker row. `row_id` is a 1-based Native `for` key.
/// `id` is the stored chip value (ask/auto/fullAccess, or fx effort).
pub const ChipPickerRow = struct {
    row_id: u32,
    id: []const u8,
    label: []const u8,
    selected: bool,
};

const access_chip_options = [_]struct { id: []const u8, label: []const u8 }{
    .{ .id = "ask", .label = "Ask" },
    .{ .id = "auto", .label = "Auto" },
    .{ .id = "fullAccess", .label = "Full access" },
};

const effort_chip_options = [_]struct { id: []const u8, label: []const u8 }{
    .{ .id = "auto", .label = "Auto" },
    .{ .id = "none", .label = "None" },
    .{ .id = "minimal", .label = "Minimal" },
    .{ .id = "low", .label = "Low" },
    .{ .id = "medium", .label = "Medium" },
    .{ .id = "high", .label = "High" },
    .{ .id = "xhigh", .label = "Extra high" },
    .{ .id = "max", .label = "Max" },
};

/// Local command-palette row. `id` is never 0: actions use
/// `palette_action_id_base + kind`, sessions use the session id,
/// section headers use `palette_header_id_base + n`.
pub const PaletteRow = struct {
    id: u32,
    label: []const u8,
    detail: []const u8,
    selected: bool,
    is_header: bool,
    is_action: bool,
    is_session: bool,
};

pub const PaletteAction = enum(u32) {
    new_task = 1,
    focus_composer = 2,
    toggle_sidebar = 3,
    collapse_folders = 4,
    find_in_transcript = 5,
    settings = 6,
    minimize = 7,
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
    stop,
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
    start_image_attach,
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
    sidebar_resized: f32,
    transcript_scrolled: canvas.ScrollState,
    jump_latest,
    copy_turn: u32,
    copy_last_turn,
    copy_session,
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

    pub const view_unbound = .{ "tick", "stop", "steer", "assign_folder", "fx_line", "fx_exit", "fx_probe_exit", "copy_last_turn", "focus_composer", "open_find", "clipboard_done", "attach_preview_done", "switcher_forward", "switcher_backward", "file_drop", "cycle_access", "cycle_effort" };
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
        "selectedProjectPath",
        "resolvedAccessMode",
        "resolvedInteractionMode",
        "resolvedReasoningEffort",
        "is_streaming",
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
                .title = sessionDisplayTitle(session),
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
        var count: usize = 0;
        for (model.session_store[0..model.session_count]) |*session| {
            if (effectiveFolderId(model, session) == 0) count += 1;
        }
        for (model.folder_store[0..model.folder_count]) |*folder| {
            var matches: usize = 0;
            for (model.session_store[0..model.session_count]) |*session| {
                if (effectiveFolderId(model, session) == folder.id) matches += 1;
            }
            count += 1;
            if (!folder.collapsed) count += matches;
        }
        const out = arena.alloc(SidebarRow, count) catch return &.{};
        var i: usize = 0;
        for (model.session_store[0..model.session_count]) |*session| {
            if (effectiveFolderId(model, session) != 0) continue;
            out[i] = sessionSidebarRow(model, session);
            i += 1;
        }
        for (model.folder_store[0..model.folder_count]) |*folder| {
            out[i] = .{
                .id = folder_row_id_base + folder.id,
                .title = folder.title(),
                .provider = "",
                .selected = selectedSessionInFolder(model, folder.id),
                .is_header = true,
                .editing = model.editing_folder_id == folder.id,
                .folder_id = folder.id,
                .grouped = false,
            };
            i += 1;
            if (folder.collapsed) continue;
            for (model.session_store[0..model.session_count]) |*session| {
                if (effectiveFolderId(model, session) != folder.id) continue;
                out[i] = sessionSidebarRow(model, session);
                i += 1;
            }
        }
        return out[0..i];
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
                .title = sessionDisplayTitle(session),
                .provider = session.provider_label(),
                .selected = i == model.switcher_highlight,
            };
            n += 1;
        }
        return out[0..n];
    }

    pub fn palette_rows(model: *const Model, arena: std.mem.Allocator) []const PaletteRow {
        if (!model.palette_open) return &.{};
        const query = std.mem.trim(u8, model.search_query(), " \t\r\n");
        var specs_buf: [palette_action_specs.len]PaletteActionSpec = undefined;
        const specs = matchingPaletteActions(model, query, &specs_buf);
        var session_ids: [max_sessions]u32 = undefined;
        const sessions_n = if (query.len == 0)
            0
        else
            matchingPaletteSessions(model, query, &session_ids);

        var count: usize = 0;
        if (query.len == 0) {
            count += 1 + suggestedPaletteCount(specs) + 1 + commandPaletteCount(specs);
        } else {
            if (specs.len > 0) count += specs.len;
            if (sessions_n > 0) count += 1 + sessions_n;
        }
        if (count == 0) return &.{};
        const out = arena.alloc(PaletteRow, count) catch return &.{};
        var i: usize = 0;
        var selectable: u32 = 0;
        if (query.len == 0) {
            out[i] = paletteHeaderRow(1, "Suggested");
            i += 1;
            appendPaletteActionRows(out, &i, &selectable, model.palette_highlight, specs, true);
            out[i] = paletteHeaderRow(2, "Commands");
            i += 1;
            appendPaletteActionRows(out, &i, &selectable, model.palette_highlight, specs, false);
        } else {
            appendPaletteActionRows(out, &i, &selectable, model.palette_highlight, specs, null);
            if (sessions_n > 0) {
                out[i] = paletteHeaderRow(3, "Tasks");
                i += 1;
                var s: usize = 0;
                while (s < sessions_n) : (s += 1) {
                    const session = model.sessionByIdConst(session_ids[s]) orelse continue;
                    out[i] = paletteSessionRow(session, selectable == model.palette_highlight);
                    i += 1;
                    selectable += 1;
                }
            }
        }
        return out[0..i];
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

    pub fn visible_turns(model: *const Model, arena: std.mem.Allocator) []const TurnRow {
        const query = if (model.find_active)
            std.mem.trim(u8, model.find_query(), " \t\r\n")
        else
            "";
        var count: usize = 0;
        for (model.turn_store[0..model.turn_count]) |turn| {
            if (turn.session_id != model.selected) continue;
            if (query.len > 0 and !asciiContainsIgnoreCase(turn.text(), query)) continue;
            count += 1;
        }
        const out = arena.alloc(TurnRow, count) catch return &.{};
        var i: usize = 0;
        for (model.turn_store[0..model.turn_count]) |*turn| {
            if (turn.session_id != model.selected) continue;
            if (query.len > 0 and !asciiContainsIgnoreCase(turn.text(), query)) continue;
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

    pub fn composer_placeholder(_: *const Model) []const u8 {
        return "Do anything...";
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
        return @intFromFloat(@round(clampSidebarWidth(model.sidebar_last_width)));
    }

    pub fn applySidebarWidth(model: *Model, width: u32) void {
        if (width == 0) return;
        model.sidebar_last_width = clampSidebarWidth(@floatFromInt(width));
    }

    pub fn syncSidebarSplit(model: *Model) void {
        if (model.sidebar_collapsed) {
            model.sidebar_split = collapsedSidebarSplit();
            return;
        }
        const width = if (model.sidebar_last_width > 0) model.sidebar_last_width else sidebar_default_width;
        model.sidebar_split = clampExpandedSidebarSplit(width / window_width);
    }

    pub fn toggleSidebar(model: *Model) void {
        if (model.sidebar_collapsed) {
            model.sidebar_collapsed = false;
        } else {
            rememberExpandedWidth(model);
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

    pub fn openSettings(model: *Model) void {
        model.closeProjectEdit();
        model.closeImageAttach();
        model.closeCommands();
        model.closeModelPicker();
        model.closeFolderTitleEdit();
        model.closeSessionTitleEdit();
        model.settings_open = true;
        model.settings_model_buffer.set(model.lastModel());
        model.settings_project_buffer.set(model.lastProjectPath());
        model.settings_daemon_buffer.set(model.lastDaemonAddress());
    }

    pub fn closeSettings(model: *Model) void {
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
        if (!fileExists(io, path)) return "";
        return path;
    }

    /// Child cwd for `fx ask`: session project_path when it is non-empty and
    /// a real directory. Otherwise empty — Native spawn has no cwd field
    /// (0.9.3 SpawnOptions), so an empty result leaves the host process cwd.
    pub fn resolveSpawnCwd(model: *const Model, session: *const Session) []const u8 {
        const path = session.projectPath();
        if (path.len == 0) return "";
        const io = model.store_io orelse return "";
        if (!directoryExists(io, path)) return "";
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

    fn turnById(model: *Model, id: u32) ?*Turn {
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
        if (!folderTitleTaken(model, "New folder")) return "New folder";
        var n: u32 = 2;
        while (n < 1000) : (n += 1) {
            const title = std.fmt.bufPrint(buf, "New folder {d}", .{n}) catch return "New folder";
            if (!folderTitleTaken(model, title)) return title;
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
        if (model.sessionById(session_id)) |session| session.has_started = true;
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
    ) void {
        if (model.session_count >= max_sessions) return;
        var session = Session{
            .id = id,
            .provider = provider,
            .untitled = untitled,
            .has_started = has_started,
            .detail_loaded = false,
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

    fn appendToTurn(model: *Model, turn_id: u32, extra: []const u8) void {
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

fn writeFixed(storage: []u8, len: *usize, text: []const u8) void {
    const take = @min(storage.len, text.len);
    @memcpy(storage[0..take], text[0..take]);
    len.* = take;
}

fn sessionDisplayTitle(session: *const Session) []const u8 {
    if (session.untitled or std.mem.eql(u8, session.title(), "untitled")) return "New task";
    return session.title();
}

fn sessionMatchesQuery(session: *const Session, query: []const u8) bool {
    if (query.len == 0) return true;
    if (asciiContainsIgnoreCase(sessionDisplayTitle(session), query)) return true;
    if (asciiContainsIgnoreCase(session.title(), query)) return true;
    if (asciiContainsIgnoreCase(session.provider_label(), query)) return true;
    return asciiContainsIgnoreCase(session.projectPath(), query);
}

const PaletteActionSpec = struct {
    action: PaletteAction,
    label: []const u8,
    keywords: []const []const u8,
    suggested: bool,
};

const palette_action_specs = [_]PaletteActionSpec{
    .{ .action = .new_task, .label = "New Task", .keywords = &.{ "new", "task", "session" }, .suggested = true },
    .{ .action = .focus_composer, .label = "Focus composer", .keywords = &.{ "composer", "prompt", "input" }, .suggested = true },
    .{ .action = .toggle_sidebar, .label = "Toggle sidebar", .keywords = &.{ "sidebar", "panel" }, .suggested = false },
    .{ .action = .collapse_folders, .label = "Collapse all folders", .keywords = &.{ "collapse", "folder", "folders" }, .suggested = false },
    .{ .action = .find_in_transcript, .label = "Find in transcript", .keywords = &.{ "find", "search", "transcript" }, .suggested = false },
    .{ .action = .settings, .label = "Settings", .keywords = &.{ "settings", "preferences" }, .suggested = false },
    .{ .action = .minimize, .label = "Minimize", .keywords = &.{ "minimize", "window" }, .suggested = false },
};

pub fn paletteActionId(action: PaletteAction) u32 {
    return palette_action_id_base + @intFromEnum(action);
}

fn paletteActionFromId(id: u32) ?PaletteAction {
    if (id < palette_action_id_base or id >= palette_header_id_base) return null;
    const raw = id - palette_action_id_base;
    inline for (std.meta.tags(PaletteAction)) |action| {
        if (raw == @intFromEnum(action)) return action;
    }
    return null;
}

fn paletteHeaderRow(n: u32, label: []const u8) PaletteRow {
    return .{
        .id = palette_header_id_base + n,
        .label = label,
        .detail = "",
        .selected = false,
        .is_header = true,
        .is_action = false,
        .is_session = false,
    };
}

fn paletteActionRow(spec: PaletteActionSpec, selected: bool) PaletteRow {
    return .{
        .id = paletteActionId(spec.action),
        .label = spec.label,
        .detail = "",
        .selected = selected,
        .is_header = false,
        .is_action = true,
        .is_session = false,
    };
}

fn paletteSessionRow(session: *const Session, selected: bool) PaletteRow {
    return .{
        .id = session.id,
        .label = sessionDisplayTitle(session),
        .detail = session.provider_label(),
        .selected = selected,
        .is_header = false,
        .is_action = false,
        .is_session = true,
    };
}

fn paletteActionAvailable(model: *const Model, spec: PaletteActionSpec) bool {
    return spec.action != .collapse_folders or model.can_collapse_folders();
}

fn paletteActionMatches(spec: PaletteActionSpec, query: []const u8) bool {
    if (query.len == 0) return true;
    if (asciiContainsIgnoreCase(spec.label, query)) return true;
    for (spec.keywords) |keyword| {
        if (asciiContainsIgnoreCase(keyword, query)) return true;
    }
    return false;
}

fn matchingPaletteActions(model: *const Model, query: []const u8, dest: []PaletteActionSpec) []const PaletteActionSpec {
    var n: usize = 0;
    for (palette_action_specs) |spec| {
        if (!paletteActionAvailable(model, spec)) continue;
        if (!paletteActionMatches(spec, query)) continue;
        if (n >= dest.len) break;
        dest[n] = spec;
        n += 1;
    }
    return dest[0..n];
}

fn matchingPaletteSessions(model: *const Model, query: []const u8, dest: []u32) usize {
    var n: usize = 0;
    for (model.session_store[0..model.session_count]) |*session| {
        if (!session.hasStarted()) continue;
        if (!sessionMatchesQuery(session, query)) continue;
        if (n >= dest.len or n >= palette_max_task_results) break;
        dest[n] = session.id;
        n += 1;
    }
    return n;
}

fn suggestedPaletteCount(specs: []const PaletteActionSpec) usize {
    var n: usize = 0;
    for (specs) |spec| {
        if (spec.suggested) n += 1;
    }
    return n;
}

fn commandPaletteCount(specs: []const PaletteActionSpec) usize {
    var n: usize = 0;
    for (specs) |spec| {
        if (!spec.suggested) n += 1;
    }
    return n;
}

fn appendPaletteActionRows(
    out: []PaletteRow,
    i: *usize,
    selectable: *u32,
    highlight: u32,
    specs: []const PaletteActionSpec,
    suggested: ?bool,
) void {
    for (specs) |spec| {
        if (suggested) |want| {
            if (spec.suggested != want) continue;
        }
        out[i.*] = paletteActionRow(spec, selectable.* == highlight);
        i.* += 1;
        selectable.* += 1;
    }
}

fn paletteSelectableCount(model: *const Model) u32 {
    const query = std.mem.trim(u8, model.search_query(), " \t\r\n");
    var specs_buf: [palette_action_specs.len]PaletteActionSpec = undefined;
    const specs = matchingPaletteActions(model, query, &specs_buf);
    var session_ids: [max_sessions]u32 = undefined;
    const sessions_n = if (query.len == 0)
        0
    else
        matchingPaletteSessions(model, query, &session_ids);
    return @intCast(specs.len + sessions_n);
}

fn paletteSelectableIdAt(model: *const Model, index: u32) ?u32 {
    const query = std.mem.trim(u8, model.search_query(), " \t\r\n");
    var specs_buf: [palette_action_specs.len]PaletteActionSpec = undefined;
    const specs = matchingPaletteActions(model, query, &specs_buf);
    var cursor: u32 = 0;
    for (specs) |spec| {
        if (cursor == index) return paletteActionId(spec.action);
        cursor += 1;
    }
    if (query.len == 0) return null;
    var session_ids: [max_sessions]u32 = undefined;
    const sessions_n = matchingPaletteSessions(model, query, &session_ids);
    var s: usize = 0;
    while (s < sessions_n) : (s += 1) {
        if (cursor == index) return session_ids[s];
        cursor += 1;
    }
    return null;
}

fn sessionSidebarRow(model: *const Model, session: *const Session) SidebarRow {
    return .{
        .id = session.id,
        .title = sessionDisplayTitle(session),
        .provider = session.provider_label(),
        .selected = session.id == model.selected,
        .is_header = false,
        .editing = model.editing_session_id == session.id,
        .folder_id = session.folder_id,
        .grouped = session.folder_id != 0,
        .busy = session.busy,
    };
}

fn selectedSessionInFolder(model: *const Model, folder_id: u32) bool {
    const session = model.sessionByIdConst(model.selected) orelse return false;
    return effectiveFolderId(model, session) == folder_id;
}

fn effectiveFolderId(model: *const Model, session: *const Session) u32 {
    if (session.folder_id == 0) return 0;
    if (model.folderByIdConst(session.folder_id) == null) return 0;
    return session.folder_id;
}

fn folderTitleTaken(model: *const Model, title: []const u8) bool {
    for (model.folder_store[0..model.folder_count]) |*folder| {
        if (std.mem.eql(u8, folder.title(), title)) return true;
    }
    return false;
}

/// Active slash prefix: draft starts with `/` and the first token has
/// no whitespace yet. Returns the name after `/` (`""` for `/` alone).
/// `/commit ` or later text is a completed command — not a prefix.
fn slashCommandPrefix(draft: []const u8) ?[]const u8 {
    if (draft.len == 0 or draft[0] != '/') return null;
    const rest = draft[1..];
    for (rest) |c| {
        if (std.ascii.isWhitespace(c)) return null;
    }
    return rest;
}

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

fn asciiContainsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (needle.len > haystack.len) return false;
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        if (asciiEqlIgnoreCase(haystack[i .. i + needle.len], needle)) return true;
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

fn clampSidebarWidth(width: f32) f32 {
    const raw = if (width > 0) width else sidebar_default_width;
    return @max(sidebar_min_width, @min(sidebar_max_width, raw));
}

fn collapsedSidebarSplit() f32 {
    return sidebar_rail_width / window_width;
}

fn clampExpandedSidebarSplit(value: f32) f32 {
    const min_split = sidebar_min_width / window_width;
    const max_split = sidebar_max_width / window_width;
    return @max(min_split, @min(max_split, value));
}

fn rememberExpandedWidth(model: *Model) void {
    if (model.sidebar_collapsed) return;
    model.sidebar_last_width = clampSidebarWidth(model.sidebar_split * window_width);
}

fn applySidebarResize(model: *Model, fraction: f32) void {
    const width = fraction * window_width;
    if (model.sidebar_collapsed) {
        if (width < sidebar_min_width) return;
        model.sidebar_collapsed = false;
        model.sidebar_last_width = clampSidebarWidth(width);
        model.syncSidebarSplit();
        return;
    }
    model.sidebar_split = clampExpandedSidebarSplit(fraction);
    model.sidebar_last_width = clampSidebarWidth(model.sidebar_split * window_width);
}

fn directoryExists(io: std.Io, path: []const u8) bool {
    var dir = std.Io.Dir.cwd().openDir(io, path, .{}) catch return false;
    dir.close(io);
    return true;
}

fn fileExists(io: std.Io, path: []const u8) bool {
    var file = std.Io.Dir.cwd().openFile(io, path, .{}) catch return false;
    file.close(io);
    return true;
}

/// Native `SpawnOptions` (0.9.3) has no `cwd`. `std.process.spawn` does, but
/// Effects does not expose it. `cd` + `exec` is a real child cwd, not `PWD`.
pub const fx_ask_chdir_script = "cd -- \"$1\" && shift && exec \"$@\"";

pub const Effects = native_sdk.Effects(Msg);

/// Copy visible transcript text through Native `fx.writeClipboard`.
/// Empty text is a no-op — no fake clipboard, no `pbcopy` spawn.
fn writeVisibleClipboard(fx: *Effects, text: []const u8) void {
    if (text.len == 0) return;
    fx.writeClipboard(.{
        .key = copy_turn_key,
        .text = text,
        .on_result = Effects.clipboardMsg(.clipboard_done),
    });
}

/// Copy a turn's visible text (markdown source / tool / thought body)
/// through Native `fx.writeClipboard`. Empty text is a no-op.
fn copyTurn(model: *Model, fx: *Effects, id: u32) void {
    const turn = model.turnById(id) orelse return;
    writeVisibleClipboard(fx, turn.text());
}

/// Selected session, store order. Skip empty turns. Join remaining
/// user / assistant / tool / thought bodies with a blank line.
/// Returns null when nothing remains so the clipboard is not requested.
fn joinSelectedSessionText(model: *const Model) ?[]const u8 {
    var n: usize = 0;
    var any = false;
    for (model.turn_store[0..model.turn_count]) |*turn| {
        if (turn.session_id != model.selected) continue;
        const text = turn.text();
        if (text.len == 0) continue;
        if (any) {
            copy_session_buf[n] = '\n';
            copy_session_buf[n + 1] = '\n';
            n += 2;
        }
        @memcpy(copy_session_buf[n..][0..text.len], text);
        n += text.len;
        any = true;
    }
    if (!any) return null;
    return copy_session_buf[0..n];
}

fn copySession(model: *Model, fx: *Effects) void {
    const text = joinSelectedSessionText(model) orelse return;
    writeVisibleClipboard(fx, text);
}

/// Selected session, newest first. Empty text is skipped so a trailing
/// blank assistant/tool/thought turn does not hide the last real copy.
fn latestNonEmptyTurnId(model: *const Model) ?u32 {
    var i: usize = model.turn_count;
    while (i > 0) {
        i -= 1;
        const turn = model.turn_store[i];
        if (turn.session_id != model.selected) continue;
        if (turn.text().len == 0) continue;
        return turn.id;
    }
    return null;
}

fn copyLastTurn(model: *Model, fx: *Effects) void {
    const id = latestNonEmptyTurnId(model) orelse return;
    copyTurn(model, fx, id);
}

fn nextAttachPreviewId(model: *Model) u64 {
    var id = model.next_attach_preview_id;
    if (id < attach_preview_id_first or id > attach_preview_id_last) {
        id = attach_preview_id_first;
    }
    if (id == model.attach_preview or id == model.attach_preview_load_id) {
        id += 1;
        if (id > attach_preview_id_last) id = attach_preview_id_first;
    }
    model.next_attach_preview_id = if (id >= attach_preview_id_last)
        attach_preview_id_first
    else
        id + 1;
    return id;
}

/// Drop in-flight / displayed preview pixels. Does not touch `image_path`.
fn dropAttachPreview(model: *Model, fx: *Effects) void {
    if (model.attach_preview != 0) {
        _ = fx.unregisterImage(model.attach_preview);
        model.attach_preview = 0;
    }
    if (model.attach_preview_load_id != 0) {
        fx.cancel(model.attach_preview_load_id);
        model.attach_preview_load_id = 0;
    }
}

/// Load a Native preview for the current draft path when that file exists.
/// Missing path keeps the basename chip only. Verified: Native 0.9.3
/// `fx.loadImage` local-path first + `<image image="{attach_preview}">`.
fn refreshAttachPreview(model: *Model, fx: *Effects) void {
    dropAttachPreview(model, fx);
    const path = model.resolveSpawnImage();
    if (path.len == 0) return;
    const id = nextAttachPreviewId(model);
    model.attach_preview_load_id = id;
    fx.loadImage(.{
        .id = id,
        .path = path,
        .on_result = Effects.imageMsg(.attach_preview_done),
    });
}

fn applyAttachPreviewResult(model: *Model, fx: *Effects, result: native_sdk.EffectImageResult) void {
    if (result.id != model.attach_preview_load_id) {
        if (result.outcome == .loaded) _ = fx.unregisterImage(result.id);
        return;
    }
    model.attach_preview_load_id = 0;
    if (result.outcome == .loaded) {
        model.attach_preview = result.id;
    }
}

fn switcherContains(ids: []const u32, count: u32, id: u32) bool {
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        if (ids[i] == id) return true;
    }
    return false;
}

fn pushSwitcherId(ids: *[switcher_cap]u32, count: *u32, id: u32) void {
    if (id == 0 or count.* >= switcher_cap) return;
    if (switcherContains(ids, count.*, id)) return;
    ids[count.*] = id;
    count.* += 1;
}

fn switcherSessionAllowed(model: *const Model, id: u32, allow_current: bool) bool {
    const session = model.sessionByIdConst(id) orelse return false;
    if (allow_current and id == model.selected) return true;
    return session.hasStarted();
}

fn snapshotSwitcher(model: *Model) void {
    var ids = [_]u32{0} ** switcher_cap;
    var count: u32 = 0;

    if (switcherSessionAllowed(model, model.selected, true)) {
        pushSwitcherId(&ids, &count, model.selected);
    }

    if (model.history_count > 0) {
        var i: i32 = @intCast(model.history_count - 1);
        while (i >= 0) : (i -= 1) {
            const id = model.history_store[@intCast(i)];
            if (switcherSessionAllowed(model, id, false)) {
                pushSwitcherId(&ids, &count, id);
            }
        }
    }

    for (model.session_store[0..model.session_count]) |session| {
        if (session.hasStarted()) {
            pushSwitcherId(&ids, &count, session.id);
        }
    }

    model.switcher_ids = ids;
    model.switcher_count = count;
}

fn initialSwitcherHighlight(count: u32, first_is_current: bool, reverse: bool) u32 {
    if (count == 0) return 0;
    if (first_is_current) {
        if (count == 1) return 0;
        return if (reverse) count - 1 else 1;
    }
    return if (reverse) count - 1 else 0;
}

fn closeSwitcher(model: *Model) void {
    model.switcher_open = false;
    model.switcher_count = 0;
    model.switcher_highlight = 0;
    model.switcher_ids = [_]u32{0} ** switcher_cap;
}

fn openPalette(model: *Model) void {
    closeSwitcher(model);
    model.closeModelPicker();
    model.palette_open = true;
    model.search_buffer.clear();
    model.palette_highlight = 0;
    model.composer_active = false;
}

fn clampPaletteHighlight(model: *Model) void {
    const count = paletteSelectableCount(model);
    if (count == 0) {
        model.palette_highlight = 0;
        return;
    }
    if (model.palette_highlight >= count) model.palette_highlight = count - 1;
}

fn runPaletteAction(model: *Model, fx: *Effects, action: PaletteAction) void {
    switch (action) {
        .new_task => update(model, .new_session, fx),
        .focus_composer => update(model, .focus_composer, fx),
        .toggle_sidebar => update(model, .toggle_sidebar, fx),
        .collapse_folders => update(model, .collapse_all_folders, fx),
        .find_in_transcript => update(model, .open_find, fx),
        .settings => update(model, .toggle_settings, fx),
        .minimize => update(model, .minimize_window, fx),
    }
}

fn runPalettePick(model: *Model, fx: *Effects, id: u32) void {
    if (!model.palette_open or id == 0) return;
    if (id >= palette_header_id_base) return;
    if (id >= palette_action_id_base) {
        const action = paletteActionFromId(id) orelse return;
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

fn confirmPalette(model: *Model, fx: *Effects) void {
    if (!model.palette_open) return;
    clampPaletteHighlight(model);
    const id = paletteSelectableIdAt(model, model.palette_highlight) orelse return;
    runPalettePick(model, fx, id);
}

fn cycleSwitcher(model: *Model, reverse: bool) void {
    if (model.palette_open) model.closePalette();
    if (model.model_picker_open or model.access_picker_open or model.effort_picker_open) {
        model.closeModelPicker();
    }
    if (model.switcher_open) {
        if (model.switcher_count == 0) {
            closeSwitcher(model);
            return;
        }
        if (reverse) {
            model.switcher_highlight = if (model.switcher_highlight == 0)
                model.switcher_count - 1
            else
                model.switcher_highlight - 1;
        } else {
            model.switcher_highlight = (model.switcher_highlight + 1) % model.switcher_count;
        }
        return;
    }

    snapshotSwitcher(model);
    if (model.switcher_count == 0) return;
    const first_is_current = model.switcher_ids[0] == model.selected;
    model.switcher_highlight = initialSwitcherHighlight(model.switcher_count, first_is_current, reverse);
    model.switcher_open = true;
}

fn commitSwitcher(model: *Model, fx: *Effects, id: u32) void {
    if (!model.switcher_open) return;
    closeSwitcher(model);
    if (model.sessionById(id) == null) return;
    model.pushSelectionHistory(id);
    applySessionSelection(model, fx, id);
}

fn confirmSwitcher(model: *Model, fx: *Effects) void {
    if (!model.switcher_open or model.switcher_count == 0) return;
    if (model.switcher_highlight >= model.switcher_count) return;
    commitSwitcher(model, fx, model.switcher_ids[model.switcher_highlight]);
}

fn pickSwitcher(model: *Model, fx: *Effects, id: u32) void {
    if (!model.switcher_open) return;
    if (!switcherContains(&model.switcher_ids, model.switcher_count, id)) return;
    commitSwitcher(model, fx, id);
}

fn applySessionSelection(model: *Model, fx: *Effects, id: u32) void {
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
    refreshAttachPreview(model, fx);
    model.pinTranscriptToLatest();
    model.composer_active = true;
}

fn goHistory(step: i32, model: *Model, fx: *Effects) void {
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

fn persistAssignedFolder(model: *Model, session_id: u32, folder_id: u32, fx: *Effects) void {
    if (!model.assignSessionFolder(session_id, folder_id)) return;
    store.persistFoldersIfPossible(model);
    if (model.sessionByIdConst(session_id)) |session| {
        if (session.hasStarted()) store.persistIfPossible(model, session_id, fx);
    }
}

fn persistDeletedFolder(model: *Model, folder_id: u32, fx: *Effects) void {
    if (model.folderById(folder_id) == null) return;
    var started: [max_sessions]u32 = undefined;
    var started_n: usize = 0;
    for (model.session_store[0..model.session_count]) |session| {
        if (session.folder_id != folder_id or !session.hasStarted()) continue;
        started[started_n] = session.id;
        started_n += 1;
    }
    if (!model.deleteFolder(folder_id)) return;
    store.persistFoldersIfPossible(model);
    for (started[0..started_n]) |session_id| {
        store.persistIfPossible(model, session_id, fx);
    }
}

pub fn update(model: *Model, msg: Msg, fx: *Effects) void {
    switch (msg) {
        .new_session => {
            store.persistDraftIfPossible(model);
            model.closeProjectEdit();
            model.closeImageAttach();
            model.closeCommands();
            model.closeModelPicker();
            model.closeFolderTitleEdit();
            model.closeSessionTitleEdit();
            const id = model.addSession("untitled", .fx);
            if (id == 0) return;
            if (model.sessionById(id)) |session| session.untitled = true;
            model.pushSelectionHistory(id);
            model.selected = id;
            // Client-built; persist is a no-op until first real content.
            store.persistIfPossible(model, id, fx);
            store.loadDraftIfPossible(model);
            refreshAttachPreview(model, fx);
            model.composer_active = true;
        },
        .select => |id| {
            if (model.editing_session_id == id) return;
            if (id == model.selected and model.sessionById(id) != null) {
                model.startSessionTitleEdit(id);
                return;
            }
            if (model.sessionById(id) != null) {
                model.pushSelectionHistory(id);
                applySessionSelection(model, fx, id);
            }
        },
        .history_back => goHistory(-1, model, fx),
        .history_forward => goHistory(1, model, fx),
        .new_folder => {
            var title_buf: [max_title]u8 = undefined;
            const title = model.nextUntitledFolderTitle(&title_buf);
            if (model.addFolder(title) == 0) return;
            store.persistFoldersIfPossible(model);
        },
        .toggle_folder => |folder_id| {
            model.toggleFolderCollapsed(folder_id);
            store.persistFoldersIfPossible(model);
        },
        .collapse_all_folders => {
            if (model.folder_count == 0) return;
            if (model.collapseAllFolders()) store.persistFoldersIfPossible(model);
        },
        .rename_folder => |id| {
            model.startFolderTitleEdit(id);
        },
        .delete_folder => |folder_id| persistDeletedFolder(model, folder_id, fx),
        .assign_selected => |folder_id| {
            if (model.editing_folder_id == folder_id) return;
            if (model.editing_folder_id != 0) model.closeFolderTitleEdit();
            // Second click on the folder that already holds the selected
            // session edits the title and does not assign again.
            if (selectedSessionInFolder(model, folder_id)) {
                model.startFolderTitleEdit(folder_id);
                return;
            }
            persistAssignedFolder(model, model.selected, folder_id, fx);
        },
        .unassign_selected => {
            model.closeFolderTitleEdit();
            persistAssignedFolder(model, model.selected, 0, fx);
        },
        .folder_title_edit => |edit| {
            model.applyFolderTitle(edit);
            store.persistFoldersIfPossible(model);
        },
        .edit_session_title => {
            if (model.selected != 0) model.startSessionTitleEdit(model.selected);
        },
        .rename_session => |id| {
            model.startSessionTitleEdit(id);
        },
        .session_title_edit => |edit| {
            const session_id = model.editing_session_id;
            model.applySessionTitle(edit);
            store.persistIfPossible(model, session_id, fx);
        },
        .assign_folder => |assign| {
            persistAssignedFolder(model, assign.session_id, assign.folder_id, fx);
        },
        // Chromeless titlebar has no OS close. This is the documented
        // window-action effect (`examples/deck`): last-window close
        // follows the host exit path. Esc stays `.stop` so the session
        // switcher / command palette / settings / transcript-find / project-edit /
        // image-attach / commands / folder-title-edit / session-title-edit /
        // a live turn keep it.
        .close_window => fx.closeWindow(main_window_label),
        .minimize_window => fx.minimizeWindow(main_window_label),
        .remove_session => |id| {
            if (model.editing_session_id == id) model.closeSessionTitleEdit();
            model.closeCommands();
            store.removeIfPossible(model, id, fx);
            store.loadDraftIfPossible(model);
            refreshAttachPreview(model, fx);
        },
        .start_search => openPalette(model),
        .palette_confirm => confirmPalette(model, fx),
        .palette_cancel => model.closePalette(),
        .palette_pick => |id| runPalettePick(model, fx, id),
        .open_find => {
            model.find_active = true;
            model.composer_active = false;
        },
        .close_find => model.exitFind(),
        .focus_composer => model.composer_active = true,
        .search_edit => |edit| {
            model.search_buffer.apply(edit);
            model.palette_highlight = 0;
            if (model.palette_open) clampPaletteHighlight(model);
        },
        .find_edit => |edit| model.find_buffer.apply(edit),
        .draft_edit => |edit| {
            model.draft_buffer.apply(edit);
            store.persistDraftIfPossible(model);
        },
        .send => handleSend(model, fx),
        .steer => handleSteer(model, fx),
        .switcher_forward => cycleSwitcher(model, false),
        .switcher_backward => cycleSwitcher(model, true),
        .switcher_confirm => confirmSwitcher(model, fx),
        .switcher_cancel => closeSwitcher(model),
        .switcher_pick => |id| pickSwitcher(model, fx, id),
        .stop => {
            if (model.switcher_open) {
                closeSwitcher(model);
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
            stopStream(model, fx);
        },
        .toggle_settings => model.toggleSettings(),
        .settings_model_edit => |edit| {
            model.applySettingsModel(edit);
            store.persistSettingsIfPossible(model);
        },
        .settings_project_edit => |edit| {
            model.applySettingsProject(edit);
            store.persistSettingsIfPossible(model);
        },
        .settings_daemon_edit => |edit| {
            model.applySettingsDaemon(edit);
            store.persistSettingsIfPossible(model);
        },
        .settings_access_ask => {
            model.setSettingsAccess("ask");
            store.persistSettingsIfPossible(model);
        },
        .settings_access_auto => {
            model.setSettingsAccess("auto");
            store.persistSettingsIfPossible(model);
        },
        .settings_access_full => {
            model.setSettingsAccess("fullAccess");
            store.persistSettingsIfPossible(model);
        },
        .cycle_access => {
            model.cycleSelectedAccess();
            persistComposerChips(model, fx);
        },
        .cycle_interaction => {
            model.cycleSelectedInteraction();
            persistComposerChips(model, fx);
        },
        .cycle_effort => {
            model.cycleSelectedEffort();
            persistComposerChips(model, fx);
        },
        .toggle_model_picker => {
            if (!model.model_picker_open) {
                closeSwitcher(model);
                if (model.palette_open) model.closePalette();
                model.access_picker_open = false;
                model.effort_picker_open = false;
            }
            model.toggleModelPicker();
        },
        .close_model_picker => model.closeModelPicker(),
        .pick_model => |id| {
            model.pickSelectedModel(id);
            persistComposerChips(model, fx);
        },
        .toggle_access_picker => {
            if (!model.access_picker_open) {
                closeSwitcher(model);
                if (model.palette_open) model.closePalette();
                model.model_picker_open = false;
                model.effort_picker_open = false;
            }
            model.toggleAccessPicker();
        },
        .close_access_picker => model.closeAccessPicker(),
        .pick_access => |id| {
            model.pickSelectedAccess(id);
            persistComposerChips(model, fx);
        },
        .toggle_effort_picker => {
            if (!model.effort_picker_open) {
                closeSwitcher(model);
                if (model.palette_open) model.closePalette();
                model.model_picker_open = false;
                model.access_picker_open = false;
            }
            model.toggleEffortPicker();
        },
        .close_effort_picker => model.closeEffortPicker(),
        .pick_effort => |id| {
            model.pickSelectedEffort(id);
            persistComposerChips(model, fx);
        },
        .start_project_edit => model.startProjectEdit(),
        .project_path_edit => |edit| {
            model.applySelectedProjectPath(edit);
            persistComposerProject(model, fx);
        },
        .start_image_attach => model.startImageAttach(),
        .image_path_edit => |edit| {
            model.applyImagePath(edit);
            store.persistDraftIfPossible(model);
            refreshAttachPreview(model, fx);
        },
        .file_drop => |path| applyFileDrop(model, fx, path),
        .clear_image_attach => {
            model.clearImageAttach();
            store.persistDraftIfPossible(model);
            refreshAttachPreview(model, fx);
        },
        .toggle_commands => model.toggleCommands(),
        .insert_command => |id| {
            model.insertAvailableCommand(id);
            store.persistDraftIfPossible(model);
        },
        .rewind => applyRewindIfPossible(model, fx),
        .fork => forkSelectedSession(model, fx),
        .fork_turn => |id| forkSelectedThroughTurn(model, fx, id),
        .clear_queue => {
            model.dropQueuedForSession(model.selected);
            store.persistIfPossible(model, model.selected, fx);
        },
        .remove_queued => |id| {
            if (model.dropQueued(id)) {
                store.persistIfPossible(model, model.selected, fx);
            }
        },
        .edit_queued => |id| {
            var found = false;
            for (model.queued_store[0..model.queued_count]) |item| {
                if (item.id != id) continue;
                found = true;
                if (std.mem.trim(u8, item.text(), " \t\r\n").len == 0) return;
                break;
            }
            if (!found) return;
            var copy: [max_queued_text]u8 = undefined;
            const n = model.takeQueued(id, &copy) orelse return;
            const text = std.mem.trim(u8, copy[0..n], " \t\r\n");
            if (text.len == 0) return;
            model.draft_buffer.set(text);
            model.clearImageAttach();
            model.composer_active = true;
            store.persistIfPossible(model, model.selected, fx);
            store.persistDraftIfPossible(model);
            refreshAttachPreview(model, fx);
        },
        .toggle_sidebar => {
            model.toggleSidebar();
            store.persistLayoutIfPossible(model);
        },
        .sidebar_resized => |fraction| {
            applySidebarResize(model, fraction);
            store.persistLayoutIfPossible(model);
        },
        .transcript_scrolled => |scroll| model.applyTranscriptScroll(scroll),
        .jump_latest => model.pinTranscriptToLatest(),
        .copy_turn => |id| copyTurn(model, fx, id),
        .copy_last_turn => copyLastTurn(model, fx),
        .copy_session => copySession(model, fx),
        .clipboard_done => {},
        .attach_preview_done => |result| applyAttachPreviewResult(model, fx, result),
        .tick => |timer| {
            if (timer.outcome != .fired) return;
            tickStream(model, fx);
        },
        .fx_line => |line| handleFxLine(model, fx, line),
        .fx_exit => |exit| handleFxExit(model, fx, exit),
        .fx_probe_exit => |exit| handleFxProbeExit(model, fx, exit),
    }
}

/// Boot probe: `~/.local/bin/fx --help` then `fx --help` (PATH). Wired
/// through `.init_fx` so the first paint already has the spawn in flight.
pub fn initFx(model: *Model, fx: *Effects) void {
    store.maybeLoadDaemonCatalog(model, fx);
    store.maybeHydrateDaemonSession(model, fx, model.selected);
    refreshAttachPreview(model, fx);
    startFxProbe(model, fx);
}

fn handleSend(model: *Model, fx: *Effects) void {
    if (!model.fx_probe_started) startFxProbe(model, fx);
    const text = std.mem.trim(u8, model.draft(), " \t\r\n");
    var key_buf: [store.max_draft_key]u8 = undefined;
    const draft_key = if (model.sessionById(model.selected)) |session|
        store.draftKey(session, &key_buf)
    else
        null;
    if (model.is_streaming()) {
        if (text.len == 0) {
            stopStream(model, fx);
            return;
        }
        if (model.enqueue(model.selected, text) != 0) {
            store.persistIfPossible(model, model.selected, fx);
        }
        model.draft_buffer.clear();
        if (draft_key) |key| store.discardDraftIfPossible(model, key);
        model.clearImageAttach();
        refreshAttachPreview(model, fx);
        return;
    }
    if (text.len == 0) return;
    startPrompt(model, fx, model.selected, text);
    model.draft_buffer.clear();
    if (draft_key) |key| store.discardDraftIfPossible(model, key);
    model.clearImageAttach();
    refreshAttachPreview(model, fx);
}

/// Waku ⌘Enter: inject into a live daemon turn when attach reported
/// `supportsSteer`. Otherwise the same as Send (queue while busy).
fn handleSteer(model: *Model, fx: *Effects) void {
    if (!model.fx_probe_started) startFxProbe(model, fx);
    const text = std.mem.trim(u8, model.draft(), " \t\r\n");
    if (text.len == 0) return;
    if (maybeSteerDaemonTurn(model, fx, text)) {
        var key_buf: [store.max_draft_key]u8 = undefined;
        const draft_key = if (model.sessionById(model.selected)) |session|
            store.draftKey(session, &key_buf)
        else
            null;
        model.draft_buffer.clear();
        if (draft_key) |key| store.discardDraftIfPossible(model, key);
        model.clearImageAttach();
        refreshAttachPreview(model, fx);
        return;
    }
    handleSend(model, fx);
}

fn startPrompt(model: *Model, fx: *Effects, session_id: u32, text: []const u8) void {
    const session = model.sessionById(session_id) orelse return;
    recordRewindRefIfPossible(model, session.id);
    const titled = session.untitled;
    if (session.untitled) {
        writeFixed(&session.title_storage, &session.title_len, text);
        session.untitled = false;
    }
    _ = model.appendTurn(session.id, .user, text);
    const assistant_id = model.appendTurn(session.id, .assistant, "");
    if (titled) store.persistIfPossible(model, session.id, fx);
    session.busy = true;
    model.phase = .streaming;
    model.stream_cursor = 0;
    model.stream_turn_id = assistant_id;
    model.streaming_session = session.id;
    if (model.daemonAddress().len > 0) {
        model.reply_path = .daemon;
        startDaemonProxy(model, fx, session, text);
        return;
    }
    if (session.provider == .fx and model.fx_available and model.fxPath().len > 0) {
        model.reply_path = .fx;
        const image_path = model.resolveSpawnImage();
        if (image_path.len > 0) {
            startFxAsk(model, fx, session, text);
            return;
        }
        if (!startFxAcp(model, fx, session, text)) {
            startFxAsk(model, fx, session, text);
        }
        return;
    }
    model.reply_path = .demo;
    startDemoTimer(fx);
}

fn startDemoTimer(fx: *Effects) void {
    fx.startTimer(.{
        .key = stream_timer_key,
        .interval_ms = stream_interval_ms,
        .mode = .repeating,
        .on_fire = Effects.timerMsg(.tick),
    });
}

/// Waku `runtime_mode` → verified `FX_PERMISSION_MODE` (`ask`/`auto`/`yolo`).
/// Unknown strings persist but do not set the env.
pub fn fxPermissionMode(access_mode: []const u8) []const u8 {
    if (std.mem.eql(u8, access_mode, "ask")) return "ask";
    if (std.mem.eql(u8, access_mode, "autoAcceptEdits")) return "auto";
    if (std.mem.eql(u8, access_mode, "auto")) return "auto";
    if (std.mem.eql(u8, access_mode, "fullAccess")) return "yolo";
    if (std.mem.eql(u8, access_mode, "yolo")) return "yolo";
    return "";
}

/// ask → auto → fullAccess. `autoAcceptEdits` counts as auto; `yolo` / empty
/// count as fullAccess. Unknown strings restart at ask.
pub fn nextAccessMode(access_mode: []const u8) []const u8 {
    if (std.mem.eql(u8, access_mode, "ask")) return "auto";
    if (std.mem.eql(u8, access_mode, "auto") or std.mem.eql(u8, access_mode, "autoAcceptEdits")) return "fullAccess";
    return "ask";
}

pub fn accessLabel(access_mode: []const u8) []const u8 {
    if (std.mem.eql(u8, access_mode, "ask")) return "Ask";
    if (std.mem.eql(u8, access_mode, "auto") or std.mem.eql(u8, access_mode, "autoAcceptEdits")) return "Auto";
    return "Full access";
}

/// auto → none → minimal → low → medium → high → xhigh → max → auto.
/// Empty and unknown strings restart at none (same as starting from auto).
pub fn nextReasoningEffort(effort: []const u8) []const u8 {
    if (std.mem.eql(u8, effort, "auto") or effort.len == 0) return "none";
    if (std.mem.eql(u8, effort, "none")) return "minimal";
    if (std.mem.eql(u8, effort, "minimal")) return "low";
    if (std.mem.eql(u8, effort, "low")) return "medium";
    if (std.mem.eql(u8, effort, "medium")) return "high";
    if (std.mem.eql(u8, effort, "high")) return "xhigh";
    if (std.mem.eql(u8, effort, "xhigh")) return "max";
    return "auto";
}

pub fn effortLabel(effort: []const u8) []const u8 {
    if (std.mem.eql(u8, effort, "none")) return "None";
    if (std.mem.eql(u8, effort, "minimal")) return "Minimal";
    if (std.mem.eql(u8, effort, "low")) return "Low";
    if (std.mem.eql(u8, effort, "medium")) return "Medium";
    if (std.mem.eql(u8, effort, "high")) return "High";
    if (std.mem.eql(u8, effort, "xhigh")) return "Extra high";
    if (std.mem.eql(u8, effort, "max")) return "Max";
    return "Auto";
}

fn isDocumentedReasoningEffort(effort: []const u8) bool {
    return std.mem.eql(u8, effort, "auto") or
        std.mem.eql(u8, effort, "none") or
        std.mem.eql(u8, effort, "minimal") or
        std.mem.eql(u8, effort, "low") or
        std.mem.eql(u8, effort, "medium") or
        std.mem.eql(u8, effort, "high") or
        std.mem.eql(u8, effort, "xhigh") or
        std.mem.eql(u8, effort, "max");
}

fn persistComposerChips(model: *Model, fx: *Effects) void {
    store.persistSettingsIfPossible(model);
    store.persistIfPossible(model, model.selected, fx);
}

fn persistComposerProject(model: *Model, fx: *Effects) void {
    store.persistSettingsIfPossible(model);
    store.persistIfPossible(model, model.selected, fx);
}

/// Map stored session fields onto verified `StartOptions`. Empty
/// `project_path` becomes `"."`. Empty model is omitted on the wire.
/// `computer_use_enabled` is not stored here and stays false.
pub fn startOptionsFromSession(session: *const Session) protocol.StartOptions {
    return .{
        .provider = session.provider.wireName(),
        .binary = session.provider.defaultBinary(),
        .cwd = if (session.projectPath().len > 0) session.projectPath() else ".",
        .mode = if (session.accessMode().len > 0) session.accessMode() else default_access_mode,
        .interaction_mode = if (session.interactionMode().len > 0) session.interactionMode() else default_interaction_mode,
        .model = if (session.model().len > 0) session.model() else null,
        .reasoning_effort = if (session.reasoningEffort().len > 0) session.reasoningEffort() else null,
        .computer_use_enabled = false,
    };
}

fn startDaemonProxy(model: *Model, fx: *Effects, session: *const Session, prompt: []const u8) void {
    var id_buf: [36]u8 = undefined;
    const session_id = daemon_proxy.wireUuid(session.id, &id_buf);
    const has_runtime = protocol.isUsableRuntimeId(session.runtimeId());
    const runtime_id = if (has_runtime) session.runtimeId() else protocol.NIL_UUID;
    const start = if (has_runtime) null else startOptionsFromSession(session);
    var stdin_buf: [4096]u8 = undefined;
    const stdin = daemon_proxy.writeTurnStdin(&stdin_buf, .{
        .token = model.daemonToken(),
        .session_id = session_id,
        .runtime_id = runtime_id,
        .prompt = prompt,
        .start = start,
    }) catch {
        model.reply_path = .demo;
        startDemoTimer(fx);
        return;
    };

    model.setLastDaemonAddress(model.daemonAddress());
    model.daemon_spawn_key = model.next_daemon_key;
    model.next_daemon_key += 1;

    fx.spawn(.{
        .key = model.daemon_spawn_key,
        .argv = &.{ model.sidecarPath(), daemon_proxy.SUBCOMMAND, model.daemonAddress() },
        .stdin = stdin,
        .max_line_bytes = daemon_line_bytes,
        .on_line = Effects.lineMsg(.fx_line),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
}

fn allocateFxSpawnKey(model: *Model) u64 {
    const key = if (model.fx_spawn_live) blk: {
        const k = model.next_fx_key;
        model.next_fx_key = k + 1;
        break :blk k;
    } else fx_ask_key;
    model.fx_spawn_key = key;
    model.fx_spawn_live = true;
    return key;
}

fn startFxAcp(model: *Model, fx: *Effects, session: *const Session, prompt: []const u8) bool {
    const path = model.fxPath();
    const cwd = model.resolveAcpCwd(session);
    const resume_id = session.fxSessionId();
    const model_id = session.model();
    const permission_mode = fxPermissionMode(session.accessMode());
    model.setLastSpawnCwd(cwd);
    model.setLastSpawnFxModel(model_id);
    model.setLastSpawnFxPermissionMode(permission_mode);
    model.setLastSpawnImagePath("");

    var stdin_buf: [8192]u8 = undefined;
    const stdin = acp.writeTurnStdin(&stdin_buf, .{
        .cwd = cwd,
        .resume_id = resume_id,
        .prompt = prompt,
        .model = model_id,
        .access_mode = session.accessMode(),
    }) catch return false;

    var model_assign: [max_fx_model + 16]u8 = undefined;
    var perm_assign: [max_access_mode + 24]u8 = undefined;
    const model_arg = if (model_id.len > 0)
        std.fmt.bufPrint(&model_assign, "FX_MODEL={s}", .{model_id}) catch ""
    else
        "";
    const perm_arg = if (permission_mode.len > 0)
        std.fmt.bufPrint(&perm_assign, "FX_PERMISSION_MODE={s}", .{permission_mode}) catch ""
    else
        "";

    var argv_buf: [16][]const u8 = undefined;
    var n: usize = 0;
    argv_buf[n] = model.sidecarPath();
    n += 1;
    argv_buf[n] = acp_proxy.SUBCOMMAND;
    n += 1;
    argv_buf[n] = "--";
    n += 1;
    if (model_arg.len > 0 or perm_arg.len > 0) {
        argv_buf[n] = fx_env_bin;
        n += 1;
        if (model_arg.len > 0) {
            argv_buf[n] = model_arg;
            n += 1;
        }
        if (perm_arg.len > 0) {
            argv_buf[n] = perm_arg;
            n += 1;
        }
    }
    argv_buf[n] = path;
    n += 1;
    argv_buf[n] = "acp";
    n += 1;

    model.fx_spawn_acp = true;
    fx.spawn(.{
        .key = allocateFxSpawnKey(model),
        .argv = argv_buf[0..n],
        .stdin = stdin,
        .on_line = Effects.lineMsg(.fx_line),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
    return true;
}

fn startFxAsk(model: *Model, fx: *Effects, session: *const Session, prompt: []const u8) void {
    const path = model.fxPath();
    const cwd = model.resolveSpawnCwd(session);
    const resume_id = session.fxSessionId();
    const model_id = session.model();
    const permission_mode = fxPermissionMode(session.accessMode());
    const image_path = model.resolveSpawnImage();
    model.setLastSpawnCwd(cwd);
    model.setLastSpawnFxModel(model_id);
    model.setLastSpawnFxPermissionMode(permission_mode);
    model.setLastSpawnImagePath(image_path);

    // Native SpawnOptions has no `env`. `/usr/bin/env KEY=val` sets the
    // child only — do not export on the Faku process.
    var model_assign: [max_fx_model + 16]u8 = undefined;
    var perm_assign: [max_access_mode + 24]u8 = undefined;
    const model_arg = if (model_id.len > 0)
        std.fmt.bufPrint(&model_assign, "FX_MODEL={s}", .{model_id}) catch ""
    else
        "";
    const perm_arg = if (permission_mode.len > 0)
        std.fmt.bufPrint(&perm_assign, "FX_PERMISSION_MODE={s}", .{permission_mode}) catch ""
    else
        "";

    var argv_buf: [20][]const u8 = undefined;
    var n: usize = 0;
    if (cwd.len > 0) {
        argv_buf[n] = "/bin/sh";
        n += 1;
        argv_buf[n] = "-c";
        n += 1;
        argv_buf[n] = fx_ask_chdir_script;
        n += 1;
        argv_buf[n] = "sh";
        n += 1;
        argv_buf[n] = cwd;
        n += 1;
    }
    if (model_arg.len > 0 or perm_arg.len > 0) {
        argv_buf[n] = fx_env_bin;
        n += 1;
        if (model_arg.len > 0) {
            argv_buf[n] = model_arg;
            n += 1;
        }
        if (perm_arg.len > 0) {
            argv_buf[n] = perm_arg;
            n += 1;
        }
    }
    argv_buf[n] = path;
    n += 1;
    argv_buf[n] = "ask";
    n += 1;
    argv_buf[n] = "--json";
    n += 1;
    if (resume_id.len > 0) {
        argv_buf[n] = "--resume";
        n += 1;
        argv_buf[n] = resume_id;
        n += 1;
    }
    if (image_path.len > 0) {
        argv_buf[n] = "--image";
        n += 1;
        argv_buf[n] = image_path;
        n += 1;
    }
    argv_buf[n] = "--";
    n += 1;
    argv_buf[n] = prompt;
    n += 1;

    model.fx_spawn_acp = false;
    fx.spawn(.{
        .key = allocateFxSpawnKey(model),
        .argv = argv_buf[0..n],
        .on_line = Effects.lineMsg(.fx_line),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
}

/// A stdout line that is a JSON object with a non-empty `session_id`.
/// Copies the id into `dest` and returns the copied slice.
pub fn takeFxAskSessionId(line: []const u8, dest: []u8) ?[]const u8 {
    const trimmed = std.mem.trim(u8, line, " \t\r\n");
    if (trimmed.len < 2 or trimmed[0] != '{') return null;
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const root = std.json.parseFromSliceLeaky(std.json.Value, arena_state.allocator(), trimmed, .{}) catch return null;
    const obj = switch (root) {
        .object => |o| o,
        else => return null,
    };
    const raw = obj.get("session_id") orelse return null;
    const id = switch (raw) {
        .string => |s| s,
        else => return null,
    };
    if (id.len == 0) return null;
    const take = @min(dest.len, id.len);
    @memcpy(dest[0..take], id[0..take]);
    return dest[0..take];
}

fn tickStream(model: *Model, fx: *Effects) void {
    if (model.phase != .streaming) return;
    model.stream_cursor += 1;
    const start = @min(demo_reply.len, (model.stream_cursor - 1) * stream_chunk_bytes);
    const end = @min(demo_reply.len, start + stream_chunk_bytes);
    if (end > start) model.appendToTurn(model.stream_turn_id, demo_reply[start..end]);
    if (model.stream_cursor >= demo_ticks_complete or end >= demo_reply.len) {
        finishStream(model, fx, true);
    }
}

fn finishStream(model: *Model, fx: *Effects, drain: bool) void {
    const finished_id = model.streaming_session;
    if (model.sessionById(finished_id)) |session| session.busy = false;
    model.phase = .idle;
    model.stream_cursor = 0;
    model.stream_turn_id = 0;
    model.streaming_session = 0;
    fx.cancelTimer(stream_timer_key);
    if (drain) {
        var copy: [max_queued_text]u8 = undefined;
        if (model.takeNextQueued(finished_id, &copy)) |n| {
            store.persistIfPossible(model, finished_id, fx);
            startPrompt(model, fx, finished_id, copy[0..n]);
            return;
        }
    }
    store.persistIfPossible(model, finished_id, fx);
}

fn recordRewindRefIfPossible(model: *Model, session_id: u32) void {
    const io = model.store_io orelse return;
    const session = model.sessionById(session_id) orelse return;
    var sha_buf: [rewind.max_sha]u8 = undefined;
    const captured = rewind.captureHead(std.heap.page_allocator, io, session.projectPath(), &sha_buf) orelse return;
    session.appendRewindRef(captured.sha, rewind.recorded_ref, captured.recorded_at);
}

/// Header Fork: local catalog clone through the last turn.
fn forkSelectedSession(model: *Model, fx: *Effects) void {
    store.hydrateIfPossible(model, model.selected);
    const available = model.turnCount(model.selected);
    if (available == 0) return;
    forkSelectedThrough(model, fx, available - 1);
}

/// Per-turn Fork: clone turns `0..=index` of the selected session.
/// Unknown / other-session ids are a no-op.
fn forkSelectedThroughTurn(model: *Model, fx: *Effects, turn_id: u32) void {
    store.hydrateIfPossible(model, model.selected);
    const index = selectedTurnIndex(model, turn_id) orelse return;
    forkSelectedThrough(model, fx, index);
}

fn selectedTurnIndex(model: *const Model, turn_id: u32) ?u32 {
    var index: u32 = 0;
    for (model.turn_store[0..model.turn_count]) |turn| {
        if (turn.session_id != model.selected) continue;
        if (turn.id == turn_id) return index;
        index += 1;
    }
    return null;
}

/// Local catalog clone through `through_index` (inclusive). New id, empty
/// `fx_session_id` / `runtime_id` so the next Send uses `session/new`.
/// Not a provider session fork and not a daemon RPC. Empty / full / no
/// room / past-the-end cut is a no-op.
fn forkSelectedThrough(model: *Model, fx: *Effects, through_index: u32) void {
    const source_id = model.selected;
    store.hydrateIfPossible(model, source_id);
    const source = model.sessionById(source_id) orelse return;
    const available = model.turnCount(source_id);
    if (available == 0 or through_index >= available) return;
    const needed = through_index + 1;
    if (model.session_count >= max_sessions) return;
    if (model.turn_count + needed > max_turns) return;

    const fork_id = model.addSession(source.title(), source.provider);
    if (fork_id == 0) return;
    if (model.sessionById(source_id)) |from| {
        if (model.sessionById(fork_id)) |session| {
            session.setProjectPath(from.projectPath());
            session.setModel(from.model());
            session.setAccessMode(from.accessMode());
            session.setInteractionMode(from.interactionMode());
            session.setReasoningEffort(from.reasoningEffort());
            session.folder_id = from.folder_id;
            session.untitled = from.untitled;
            session.setFxSessionId("");
            session.setRuntimeId("");
            // Session-level refs: header fork keeps the whole prefix.
            // Mid-session cuts keep the same stored shas. Do not invent shas.
            for (from.rewindRefs()) |item| {
                session.appendRewindRef(item.sha(), item.refName(), item.recorded_at);
            }
        }
    }

    const original_turn_count = model.turn_count;
    var copied: u32 = 0;
    var i: usize = 0;
    while (i < original_turn_count) : (i += 1) {
        const turn = model.turn_store[i];
        if (turn.session_id != source_id) continue;
        if (copied > through_index) break;
        _ = model.appendTurn(fork_id, turn.role, turn.text());
        copied += 1;
    }

    model.pushSelectionHistory(fork_id);
    applySessionSelection(model, fx, fork_id);
    store.persistIfPossible(model, fork_id, fx);
}

/// Reset workspace files to the latest Send-time HEAD, consume that ref,
/// and drop the last prompt's turns. Does not change `fx_session_id`.
/// Failed git is a no-op (ref and transcript stay).
fn applyRewindIfPossible(model: *Model, fx: *Effects) void {
    const io = model.store_io orelse return;
    const session = model.sessionById(model.selected) orelse return;
    const sha = session.latestRewindSha() orelse return;
    if (!rewind.resetHard(std.heap.page_allocator, io, session.projectPath(), sha)) return;
    session.popLatestRewindRef();
    model.dropLastPromptTurns(session.id);
    store.persistIfPossible(model, session.id, fx);
}

fn stopStream(model: *Model, fx: *Effects) void {
    if (!model.is_streaming()) return;
    const finished_id = model.streaming_session;
    const was_daemon = model.daemon_spawn_key != 0;
    if (model.sessionById(finished_id)) |session| session.busy = false;
    model.phase = .idle;
    model.stream_cursor = 0;
    model.stream_turn_id = 0;
    model.streaming_session = 0;
    fx.cancelTimer(stream_timer_key);
    fx.cancel(fx_ask_key);
    if (model.fx_spawn_key != 0) fx.cancel(model.fx_spawn_key);
    if (model.daemon_spawn_key != 0) fx.cancel(model.daemon_spawn_key);
    model.fx_spawn_live = false;
    if (was_daemon) maybeCancelDaemonTurn(model, fx, finished_id);
    store.persistIfPossible(model, finished_id, fx);
}

/// Live daemon turn that Waku would steer: address set, prompt sidecar
/// still running, and attach/start reported `supportsSteer`. Unknown
/// or false queues instead (same as Waku `session_can_steer`).
fn canSteerLiveDaemonTurn(model: *const Model) bool {
    if (model.daemonAddress().len == 0) return false;
    if (model.daemon_spawn_key == 0 or !model.is_streaming()) return false;
    const session = model.sessionByIdConst(model.streaming_session) orelse return false;
    return session.supports_steer;
}

/// Best-effort one-shot hello + `steer` into a live daemon turn. Own
/// spawn key — Native cannot write into the running prompt sidecar.
/// Returns true only after a spawn is recorded so the caller can clear
/// the draft. Write failure leaves the draft and does not enqueue.
fn maybeSteerDaemonTurn(model: *Model, fx: *Effects, prompt: []const u8) bool {
    if (!canSteerLiveDaemonTurn(model)) return false;
    const session = model.sessionById(model.streaming_session) orelse return false;
    var id_buf: [36]u8 = undefined;
    const wire_id = daemon_proxy.wireUuid(session.id, &id_buf);
    const runtime_id = if (protocol.isUsableRuntimeId(session.runtimeId()))
        session.runtimeId()
    else
        protocol.NIL_UUID;
    var stdin_buf: [4096]u8 = undefined;
    const stdin = daemon_proxy.writeSteerStdin(&stdin_buf, .{
        .token = model.daemonToken(),
        .session_id = wire_id,
        .runtime_id = runtime_id,
        .prompt = prompt,
    }) catch return false;

    const key = model.next_daemon_key;
    model.next_daemon_key += 1;
    fx.spawn(.{
        .key = key,
        .argv = &.{ model.sidecarPath(), daemon_proxy.SUBCOMMAND, model.daemonAddress() },
        .stdin = stdin,
        .max_line_bytes = daemon_line_bytes,
        .on_line = Effects.lineMsg(.fx_line),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
    return true;
}

/// Best-effort one-shot hello + bare `cancel` after Stop / Esc of a
/// daemon turn. Own spawn key — Native cannot write into the running
/// prompt sidecar. Missing live address is a no-op (fx ask / fx acp /
/// demo stay cancel-the-spawn only). Sidecar failure must not
/// resurrect the turn already settled above.
fn maybeCancelDaemonTurn(model: *Model, fx: *Effects, session_id: u32) void {
    if (model.daemonAddress().len == 0) return;
    const session = model.sessionById(session_id) orelse return;
    var id_buf: [36]u8 = undefined;
    const wire_id = daemon_proxy.wireUuid(session.id, &id_buf);
    const runtime_id = if (protocol.isUsableRuntimeId(session.runtimeId()))
        session.runtimeId()
    else
        protocol.NIL_UUID;
    var stdin_buf: [4096]u8 = undefined;
    const stdin = daemon_proxy.writeCancelStdin(&stdin_buf, .{
        .token = model.daemonToken(),
        .session_id = wire_id,
        .runtime_id = runtime_id,
    }) catch return;

    const key = model.next_daemon_key;
    model.next_daemon_key += 1;
    fx.spawn(.{
        .key = key,
        .argv = &.{ model.sidecarPath(), daemon_proxy.SUBCOMMAND, model.daemonAddress() },
        .stdin = stdin,
        .max_line_bytes = daemon_line_bytes,
        .on_line = Effects.lineMsg(.fx_line),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
}

fn handleFxLine(model: *Model, fx: *Effects, line: native_sdk.EffectLine) void {
    if (model.daemon_load_key != 0 and line.key == model.daemon_load_key) {
        store.applyDaemonCatalogLine(model, line.line);
        store.maybeHydrateDaemonSession(model, fx, model.selected);
        return;
    }
    if (model.daemon_hydrate_key != 0 and line.key == model.daemon_hydrate_key) {
        store.applyDaemonHydrateLine(model, line.line);
        return;
    }
    if (model.phase != .streaming) return;
    if (line.key == model.daemon_spawn_key and model.daemon_spawn_key != 0) {
        handleDaemonLine(model, fx, line);
        return;
    }
    if (model.fx_spawn_key != 0 and line.key != model.fx_spawn_key) return;
    if (model.fx_spawn_key == 0 and line.key != fx_ask_key) return;
    if (model.fx_spawn_acp) {
        handleAcpLine(model, fx, line);
        return;
    }
    const keep = line.line[0..@min(line.line.len, max_line_keep)];
    var id_buf: [max_fx_session_id]u8 = undefined;
    if (takeFxAskSessionId(keep, &id_buf)) |session_id| {
        if (model.sessionById(model.streaming_session)) |session| {
            session.setFxSessionId(session_id);
            store.persistIfPossible(model, session.id, fx);
        }
        return;
    }
    if (model.turnById(model.stream_turn_id)) |turn| {
        if (turn.body_len > 0) model.appendToTurn(model.stream_turn_id, "\n");
    }
    model.appendToTurn(model.stream_turn_id, keep);
}

fn handleAcpLine(model: *Model, fx: *Effects, line: native_sdk.EffectLine) void {
    const keep = line.line[0..@min(line.line.len, max_line_keep)];
    const parsed = acp.parseLine(keep);
    const minted = acp.mintedSessionId(parsed);
    if (minted.len > 0) {
        if (model.sessionById(model.streaming_session)) |session| {
            session.setFxSessionId(minted);
            store.persistIfPossible(model, session.id, fx);
        }
    }
    if (acp.usageUpdate(parsed)) |usage| {
        if (model.sessionById(model.streaming_session)) |session| {
            session.setContextUsage(usage.used, usage.size);
            store.persistIfPossible(model, session.id, fx);
        }
        return;
    }
    if (acp.currentModeUpdate(parsed)) |access_mode| {
        applyAcpCurrentMode(model, fx, access_mode);
        return;
    }
    if (acp.configModelUpdate(&parsed)) |config_update| {
        applyAcpConfigModel(model, fx, config_update);
        return;
    }
    if (acp.availableCommandsUpdate(&parsed)) |commands| {
        applyAcpAvailableCommands(model, fx, commands);
        return;
    }
    if (acp.sessionInfoTitle(parsed)) |title| {
        applyAcpSessionInfoTitle(model, fx, title);
        return;
    }
    if (acp.toolUpdate(&parsed)) |tool| {
        applyAcpToolUpdate(model, fx, tool);
        return;
    }
    if (acp.isAgentThoughtText(parsed)) {
        applyAcpThoughtChunk(model, fx, parsed.text);
        return;
    }
    if (acp.isAgentMessageText(parsed)) {
        model.appendToTurn(model.stream_turn_id, parsed.text);
        return;
    }
    if (acp.isPromptResult(parsed) or (parsed.has_error and parsed.id != null)) {
        const drain = acp.promptSucceeded(parsed);
        if (model.fx_spawn_key != 0) fx.cancel(model.fx_spawn_key);
        finishStream(model, fx, drain);
    }
}

/// Official ACP `current_mode_update`. Reverse map is the inverse of
/// `session/set_mode`: fx `ask` → `ask`, fx `code` → `fullAccess`.
fn applyAcpCurrentMode(model: *Model, fx: *Effects, access_mode: []const u8) void {
    const session = model.sessionById(model.streaming_session) orelse return;
    session.setAccessMode(access_mode);
    store.persistIfPossible(model, session.id, fx);
}

/// Official ACP `config_option_update` / `session/set_config_option`
/// result for `id: "model"`. Empty `currentValue` clears the session
/// model so the chip stays `FX_MODEL`. A present `options` array
/// replaces the stored catalog (empty clears).
fn applyAcpConfigModel(model: *Model, fx: *Effects, config_update: acp.ConfigModelUpdate) void {
    const session = model.sessionById(model.streaming_session) orelse return;
    if (config_update.value) |value| {
        session.setModel(value);
    }
    if (config_update.has_options) {
        session.replaceModelOptions(config_update.options);
    }
    store.persistIfPossible(model, session.id, fx);
}

/// Official ACP `available_commands_update`. Replaces the session list
/// (empty clears). Names and descriptions only; Composer Commands can
/// insert `/name ` into the draft. No execution.
fn applyAcpAvailableCommands(model: *Model, fx: *Effects, commands: []const acp.ParsedCommand) void {
    const session = model.sessionById(model.streaming_session) orelse return;
    session.replaceAvailableCommands(commands);
    if (session.id == model.selected and session.available_command_count == 0) {
        model.closeCommands();
    }
    store.persistIfPossible(model, session.id, fx);
}

/// Official ACP `session_info_update` `title`. Same merge-only catalog
/// write as mode / model / commands. Empty titles never reach here.
fn applyAcpSessionInfoTitle(model: *Model, fx: *Effects, title: []const u8) void {
    const session = model.sessionById(model.streaming_session) orelse return;
    session.setTitle(title);
    store.persistIfPossible(model, session.id, fx);
}

fn applyAcpToolUpdate(model: *Model, fx: *Effects, tool: acp.ToolUpdate) void {
    const session_id = model.streaming_session;
    if (session_id == 0) return;
    if (findToolTurn(model, session_id, tool.tool_call_id)) |turn| {
        if (tool.title.len > 0) writeFixed(&turn.tool_title_storage, &turn.tool_title_len, tool.title);
        if (tool.kind.len > 0) writeFixed(&turn.tool_kind_storage, &turn.tool_kind_len, tool.kind);
        if (tool.status.len > 0) writeFixed(&turn.tool_status_storage, &turn.tool_status_len, tool.status);
        if (tool.has_content) writeFixed(&turn.tool_content_storage, &turn.tool_content_len, tool.content);
        refreshToolTurnText(turn);
    } else {
        var text_buf: [max_body]u8 = undefined;
        const text = acp.toolTurnBody(&text_buf, tool.title, tool.kind, tool.status, if (tool.has_content) tool.content else "");
        const turn_id = model.appendTurn(session_id, .tool, text);
        const turn = model.turnById(turn_id) orelse return;
        writeFixed(&turn.tool_call_id_storage, &turn.tool_call_id_len, tool.tool_call_id);
        writeFixed(&turn.tool_title_storage, &turn.tool_title_len, tool.title);
        writeFixed(&turn.tool_kind_storage, &turn.tool_kind_len, tool.kind);
        writeFixed(&turn.tool_status_storage, &turn.tool_status_len, tool.status);
        if (tool.has_content) writeFixed(&turn.tool_content_storage, &turn.tool_content_len, tool.content);
        refreshToolTurnText(turn);
    }
    store.persistIfPossible(model, session_id, fx);
}

/// Thought text stays off the assistant markdown turn. First chunk in
/// this stream appends a reasoning row; later chunks append to that row.
fn applyAcpThoughtChunk(model: *Model, fx: *Effects, text: []const u8) void {
    const session_id = model.streaming_session;
    if (session_id == 0) return;
    if (findLiveReasoningTurn(model, session_id)) |turn| {
        model.appendToTurn(turn.id, text);
    } else {
        _ = model.appendTurn(session_id, .reasoning, text);
    }
    store.persistIfPossible(model, session_id, fx);
}

/// Only the reasoning row created after this stream's assistant turn.
/// Earlier prompts keep their own thought text.
fn findLiveReasoningTurn(model: *Model, session_id: u32) ?*Turn {
    var found: ?*Turn = null;
    for (model.turn_store[0..model.turn_count]) |*turn| {
        if (turn.session_id != session_id or turn.role != .reasoning) continue;
        if (model.stream_turn_id != 0 and turn.id < model.stream_turn_id) continue;
        found = turn;
    }
    return found;
}

fn findToolTurn(model: *Model, session_id: u32, tool_call_id: []const u8) ?*Turn {
    if (tool_call_id.len == 0) return null;
    for (model.turn_store[0..model.turn_count]) |*turn| {
        if (turn.session_id != session_id or turn.role != .tool) continue;
        if (std.mem.eql(u8, turn.toolCallId(), tool_call_id)) return turn;
    }
    return null;
}

fn refreshToolTurnText(turn: *Turn) void {
    var text_buf: [max_body]u8 = undefined;
    const text = acp.toolTurnBody(&text_buf, turn.toolTitle(), turn.toolKind(), turn.toolStatus(), turn.toolContent());
    writeFixed(&turn.body_storage, &turn.body_len, text);
}

fn handleDaemonLine(model: *Model, fx: *Effects, line: native_sdk.EffectLine) void {
    const keep = line.line[0..@min(line.line.len, max_line_keep)];
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const parsed = protocol.parseServerFrame(arena_state.allocator(), keep);
    switch (parsed.frame) {
        .event => {
            if (parsed.event_kind == .text_delta and parsed.text_delta.len > 0) {
                model.appendToTurn(model.stream_turn_id, parsed.text_delta);
            } else if (parsed.event_kind == .turn_finished) {
                finishStream(model, fx, parsed.turn_success);
            } else if (parsed.event_kind == .@"error") {
                finishStream(model, fx, false);
            }
        },
        .response => persistDaemonRuntimeId(model, fx, parsed),
        .rejected => finishStream(model, fx, false),
        else => {},
    }
}

fn persistDaemonRuntimeId(model: *Model, fx: *Effects, parsed: protocol.ParsedServer) void {
    if (!parsed.response_ok) return;
    const session = model.sessionById(model.streaming_session) orelse return;
    const is_runtime = std.mem.eql(u8, parsed.payload_type, "sessionRuntime");
    const is_started = std.mem.eql(u8, parsed.payload_type, "started");
    if (!is_runtime and !is_started) return;
    session.supports_steer = parsed.supports_steer;
    if (is_runtime and protocol.isUsableRuntimeId(parsed.runtime_id)) {
        session.setRuntimeId(parsed.runtime_id);
        store.persistIfPossible(model, session.id, fx);
    }
}

fn handleFxExit(model: *Model, fx: *Effects, exit: native_sdk.EffectExit) void {
    if (model.daemon_load_key != 0 and exit.key == model.daemon_load_key) {
        model.daemon_load_key = 0;
        model.pending_daemon_catalog = false;
        return;
    }
    if (model.daemon_hydrate_key != 0 and exit.key == model.daemon_hydrate_key) {
        model.daemon_hydrate_key = 0;
        model.daemon_hydrate_session = 0;
        return;
    }
    const daemon = model.daemon_spawn_key != 0 and exit.key == model.daemon_spawn_key;
    const fx_child = model.fx_spawn_key != 0 and exit.key == model.fx_spawn_key;
    if (exit.key != fx_ask_key and !daemon and !fx_child) return;
    if (fx_child or exit.key == fx_ask_key) {
        if (model.fx_spawn_key != 0 and exit.key != model.fx_spawn_key) return;
        model.fx_spawn_live = false;
        if (model.phase != .streaming) {
            if (exit.key == model.fx_spawn_key) model.fx_spawn_key = 0;
            return;
        }
        if (exit.key == model.fx_spawn_key) model.fx_spawn_key = 0;
    }
    if (model.phase != .streaming) return;
    const success = exit.reason == .exited and exit.code == 0;
    finishStream(model, fx, success);
}

fn startFxProbe(model: *Model, fx: *Effects) void {
    if (model.fx_probe_started) return;
    model.fx_probe_started = true;
    model.fx_probe_index = 0;
    spawnFxProbe(model, fx);
}

fn spawnFxProbe(model: *Model, fx: *Effects) void {
    while (model.fx_probe_index < 2) {
        var path_buf: [max_fx_path]u8 = undefined;
        if (fxProbePath(model, model.fx_probe_index, &path_buf)) |path| {
            model.setFxPath(path);
            fx.spawn(.{
                .key = fx_probe_key,
                .argv = &.{ model.fxPath(), "--help" },
                .output = .collect,
                .on_exit = Effects.exitMsg(.fx_probe_exit),
            });
            return;
        }
        model.fx_probe_index += 1;
    }
    model.fx_available = false;
    model.fx_path_len = 0;
}

fn handleFxProbeExit(model: *Model, fx: *Effects, exit: native_sdk.EffectExit) void {
    if (exit.key != fx_probe_key) return;
    if (exit.reason == .exited and exit.code == 0) {
        model.fx_available = true;
        return;
    }
    model.fx_available = false;
    model.fx_path_len = 0;
    model.fx_probe_index += 1;
    spawnFxProbe(model, fx);
}

fn fxProbePath(model: *const Model, index: u32, buf: *[max_fx_path]u8) ?[]const u8 {
    switch (index) {
        0 => {
            const home = model.homeDir();
            if (home.len == 0) return null;
            const suffix = "/.local/bin/fx";
            if (home.len + suffix.len > buf.len) return null;
            @memcpy(buf[0..home.len], home);
            @memcpy(buf[home.len..][0..suffix.len], suffix);
            return buf[0 .. home.len + suffix.len];
        },
        1 => {
            const name = "fx";
            @memcpy(buf[0..name.len], name);
            return buf[0..name.len];
        },
        else => return null,
    }
}

/// First dropped path that is a local image Faku already understands
/// for `fx ask --image` / attach preview. Existing extensions only:
/// png, jpg, jpeg, webp, gif. Directories (trailing separator) and
/// empty lists are ignored.
pub fn imagePathFromDrop(paths: []const []const u8) ?[]const u8 {
    for (paths) |raw| {
        const path = std.mem.trim(u8, raw, " \t\r\n");
        if (!isAttachImagePath(path)) continue;
        return path;
    }
    return null;
}

fn isAttachImagePath(path: []const u8) bool {
    if (path.len == 0) return false;
    const last = path[path.len - 1];
    if (last == '/' or last == '\\') return false;
    const ext = std.fs.path.extension(path);
    return std.ascii.eqlIgnoreCase(ext, ".png") or
        std.ascii.eqlIgnoreCase(ext, ".jpg") or
        std.ascii.eqlIgnoreCase(ext, ".jpeg") or
        std.ascii.eqlIgnoreCase(ext, ".webp") or
        std.ascii.eqlIgnoreCase(ext, ".gif");
}

/// Native `UiApp.Options.on_drop` → Msg. Window-level; no OS picker.
pub fn onDrop(drop: native_sdk.platform.FileDropEvent) ?Msg {
    const path = imagePathFromDrop(drop.paths) orelse return null;
    return .{ .file_drop = path };
}

fn applyFileDrop(model: *Model, fx: *Effects, path: []const u8) void {
    const trimmed = std.mem.trim(u8, path, " \t\r\n");
    if (!isAttachImagePath(trimmed)) return;
    if (model.store_io) |io| {
        if (directoryExists(io, trimmed)) return;
    }
    model.image_path_buffer.clear();
    model.applyImagePath(.{ .insert_text = trimmed });
    store.persistDraftIfPossible(model);
    refreshAttachPreview(model, fx);
}

pub fn onKey(keyboard: canvas.WidgetKeyboardEvent) ?Msg {
    if (std.ascii.eqlIgnoreCase(keyboard.key, "escape")) return .stop;
    // Control-Tab is the session switcher on every platform. Cmd-Tab
    // stays with the OS app switcher — do not use hasNavigationModifier.
    if (std.ascii.eqlIgnoreCase(keyboard.key, "tab")) {
        if (keyboard.modifiers.control and !keyboard.modifiers.super) {
            return if (keyboard.modifiers.shift) .switcher_backward else .switcher_forward;
        }
        return null;
    }
    if (keyboard.modifiers.hasNavigationModifier() and std.ascii.eqlIgnoreCase(keyboard.key, "n")) {
        return .new_session;
    }
    if (keyboard.modifiers.hasNavigationModifier() and std.ascii.eqlIgnoreCase(keyboard.key, "k")) {
        return .start_search;
    }
    if (keyboard.modifiers.hasNavigationModifier() and isSlashKey(keyboard.key)) {
        return .toggle_model_picker;
    }
    if (keyboard.modifiers.hasNavigationModifier() and std.ascii.eqlIgnoreCase(keyboard.key, "f")) {
        return .open_find;
    }
    if (keyboard.modifiers.hasNavigationModifier() and std.ascii.eqlIgnoreCase(keyboard.key, "l")) {
        return .focus_composer;
    }
    if (keyboard.modifiers.hasNavigationModifier() and std.ascii.eqlIgnoreCase(keyboard.key, "m")) {
        return .minimize_window;
    }
    if (keyboard.modifiers.hasNavigationModifier() and std.ascii.eqlIgnoreCase(keyboard.key, "b")) {
        return .toggle_sidebar;
    }
    if (keyboard.modifiers.hasNavigationModifier() and std.ascii.eqlIgnoreCase(keyboard.key, "c")) {
        return .copy_last_turn;
    }
    if (keyboard.modifiers.hasNavigationModifier() and std.mem.eql(u8, keyboard.key, ",")) {
        return .toggle_settings;
    }
    if (keyboard.modifiers.hasNavigationModifier() and std.mem.eql(u8, keyboard.key, "[")) {
        return .history_back;
    }
    if (keyboard.modifiers.hasNavigationModifier() and std.mem.eql(u8, keyboard.key, "]")) {
        return .history_forward;
    }
    if (keyboard.modifiers.hasNavigationModifier() and isEnterKey(keyboard.key)) {
        return .steer;
    }
    return null;
}

fn isEnterKey(key: []const u8) bool {
    return std.ascii.eqlIgnoreCase(key, "enter") or std.ascii.eqlIgnoreCase(key, "return");
}

fn isSlashKey(key: []const u8) bool {
    return std.mem.eql(u8, key, "/") or std.ascii.eqlIgnoreCase(key, "slash");
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
        .on_key = onKey,
        .on_drop = onDrop,
        .markup = .{ .source = app_markup, .watch_path = "src/app.native", .io = init.io },
    });
    defer app_state.destroy();
    app_state.model = initialModel();
    if (init.environ_map.get("HOME")) |home| {
        app_state.model.setHome(home);
        store.bindDefaultDir(&app_state.model, home, init.environ_map.get("XDG_DATA_HOME"));
    }
    bindDaemonEnv(&app_state.model, init);
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

fn bindDaemonEnv(model: *Model, init: std.process.Init) void {
    if (init.environ_map.get(protocol.DAEMON_ADDRESS_ENV)) |addr| {
        model.setDaemonAddress(addr);
    }
    if (init.environ_map.get(protocol.DAEMON_TOKEN_ENV)) |token| {
        model.setDaemonToken(token);
    }
    const args = init.minimal.args.toSlice(init.arena.allocator()) catch return;
    if (args.len > 0 and args[0].len > 0) model.setSidecarPath(args[0]);
}

test {
    _ = @import("tests.zig");
    _ = @import("protocol.zig");
    _ = @import("acp.zig");
    _ = @import("store.zig");
    _ = @import("daemon_proxy.zig");
    _ = @import("acp_proxy.zig");
    _ = @import("rewind.zig");
}
