//! Session type, stored ACP commands, and model-option catalog.
//!
//! `AvailableCommand` / `ModelOption` / `Session` live here.
//! `writeFixed` is the shared fixed-buffer helper Session methods
//! use (re-exported from `main`). Update arms stay in
//! `session_actions.zig`. Model / Msg / `update` stay in `main.zig`.
//! Behavior is unchanged from the former `main` Session cluster.

const std = @import("std");
const protocol = @import("protocol.zig");
const acp = @import("acp.zig");
const rewind = @import("rewind.zig");
const goal = @import("goal.zig");

const formatThreadGoalUsage = goal.formatThreadGoalUsage;

pub const max_title = 64;
pub const max_project_path = 512;
pub const max_fx_session_id = 128;
pub const max_runtime_id = 36;
pub const max_fx_model = 128;
pub const max_access_mode = 32;
pub const max_interaction_mode = 16;
pub const max_reasoning_effort = 16;
/// Codex `ThreadGoal.objective`. Same cap as the composer draft.
pub const max_thread_goal_objective = 512;
/// Codex `ThreadGoalStatus` wire name (`budgetLimited` is 13).
pub const max_thread_goal_status = 16;
/// Compact `12k/100k · 3m` meter on the composer goal row.
pub const max_thread_goal_usage_label = 48;
pub const max_available_commands = acp.max_available_commands;
pub const max_model_options = acp.max_model_options;
pub const max_command_name = 64;
pub const max_command_description = 256;

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
    /// 0 = ungrouped (date buckets). Unknown ids also render ungrouped.
    folder_id: u32 = 0,
    /// Last user/assistant activity, unix milliseconds. 0 = missing and
    /// groups as Today. Distinct from rewind `recorded_at`.
    updated_at: i64 = 0,
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
    /// Last-known Codex thread goal. Daemon `goalUpdated` / local set/clear.
    /// Empty objective means no goal. Not invented on fx/demo.
    thread_goal_objective_storage: [max_thread_goal_objective]u8 = [_]u8{0} ** max_thread_goal_objective,
    thread_goal_objective_len: usize = 0,
    thread_goal_status_storage: [max_thread_goal_status]u8 = [_]u8{0} ** max_thread_goal_status,
    thread_goal_status_len: usize = 0,
    /// Documented `ThreadGoal` usage. Missing means last-known unknown.
    thread_goal_token_budget: ?u64 = null,
    thread_goal_tokens_used: ?u64 = null,
    thread_goal_time_used_seconds: ?u64 = null,
    thread_goal_usage_label_storage: [max_thread_goal_usage_label]u8 = [_]u8{0} ** max_thread_goal_usage_label,
    thread_goal_usage_label_len: usize = 0,

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

    pub fn threadGoalObjective(self: *const Session) []const u8 {
        return self.thread_goal_objective_storage[0..self.thread_goal_objective_len];
    }

    pub fn threadGoalStatus(self: *const Session) []const u8 {
        return self.thread_goal_status_storage[0..self.thread_goal_status_len];
    }

    pub fn setThreadGoalObjective(self: *Session, value: []const u8) void {
        writeFixed(&self.thread_goal_objective_storage, &self.thread_goal_objective_len, value);
    }

    pub fn setThreadGoalStatus(self: *Session, value: []const u8) void {
        writeFixed(&self.thread_goal_status_storage, &self.thread_goal_status_len, value);
    }

    pub fn setThreadGoal(self: *Session, objective: []const u8, status: []const u8) void {
        self.setThreadGoalObjective(objective);
        self.setThreadGoalStatus(status);
    }

    pub fn threadGoalTokenBudget(self: *const Session) ?u64 {
        return self.thread_goal_token_budget;
    }

    pub fn threadGoalTokensUsed(self: *const Session) ?u64 {
        return self.thread_goal_tokens_used;
    }

    pub fn threadGoalTimeUsedSeconds(self: *const Session) ?u64 {
        return self.thread_goal_time_used_seconds;
    }

    pub fn threadGoalUsageLabel(self: *const Session) []const u8 {
        return self.thread_goal_usage_label_storage[0..self.thread_goal_usage_label_len];
    }

    pub fn setThreadGoalUsage(self: *Session, token_budget: ?u64, tokens_used: ?u64, time_used_seconds: ?u64) void {
        self.thread_goal_token_budget = token_budget;
        self.thread_goal_tokens_used = tokens_used;
        self.thread_goal_time_used_seconds = time_used_seconds;
        self.refreshThreadGoalUsageLabel();
    }

    pub fn clearThreadGoalUsage(self: *Session) void {
        self.setThreadGoalUsage(null, null, null);
    }

    pub fn applyThreadGoalUsage(
        self: *Session,
        token_budget: ?u64,
        token_budget_null: bool,
        has_token_budget: bool,
        tokens_used: ?u64,
        time_used_seconds: ?u64,
    ) void {
        if (has_token_budget) {
            self.thread_goal_token_budget = if (token_budget_null) null else token_budget;
        }
        if (tokens_used) |used| self.thread_goal_tokens_used = used;
        if (time_used_seconds) |secs| self.thread_goal_time_used_seconds = secs;
        self.refreshThreadGoalUsageLabel();
    }

    fn refreshThreadGoalUsageLabel(self: *Session) void {
        var buf: [max_thread_goal_usage_label]u8 = undefined;
        if (formatThreadGoalUsage(&buf, self.thread_goal_token_budget, self.thread_goal_tokens_used, self.thread_goal_time_used_seconds)) |label| {
            writeFixed(&self.thread_goal_usage_label_storage, &self.thread_goal_usage_label_len, label);
        } else {
            self.thread_goal_usage_label_len = 0;
        }
    }

    pub fn clearThreadGoal(self: *Session) void {
        self.thread_goal_objective_len = 0;
        self.thread_goal_status_len = 0;
        self.clearThreadGoalUsage();
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

pub fn writeFixed(storage: []u8, len: *usize, text: []const u8) void {
    const take = @min(storage.len, text.len);
    @memcpy(storage[0..take], text[0..take]);
    len.* = take;
}
