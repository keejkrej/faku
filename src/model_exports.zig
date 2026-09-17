//! Model / Msg barrel re-exports.
//!
//! Caps, session defaults, TEA types (`Mode` / `Role` / `Phase` /
//! `ReplyPath`, Turn / Folder / row types, `Msg`, `Model`), and
//! `writeFixed` live in `model.zig` / `session.zig` / `i18n.zig`.
//! This file only re-exports them (plus the three session-default
//! strings that used to be defined on `main`). Callers import this
//! module directly (`model_exports.Msg` / `model_exports.Model` /
//! `model_exports.max_turns`). Not re-exported from `main`. Behavior
//! is unchanged from the former `main` Model / Msg cluster.

const std = @import("std");
const model = @import("model.zig");
const session = @import("session.zig");
const i18n = @import("i18n.zig");

pub const max_sessions = model.max_sessions;
/// In-memory session selection history for sidebar Back / Forward.
pub const selection_history_cap = model.selection_history_cap;
pub const max_turns = model.max_turns;
pub const max_title = session.max_title;
pub const max_body = model.max_body;
pub const max_draft = model.max_draft;
pub const max_queued = model.max_queued;
pub const max_queued_text = model.max_queued_text;
pub const max_fx_path = model.max_fx_path;
pub const max_store_dir = model.max_store_dir;
pub const max_project_path = session.max_project_path;
pub const max_attach_status = model.max_attach_status;
pub const max_fx_session_id = session.max_fx_session_id;
pub const max_tool_call_id = model.max_tool_call_id;
pub const max_tool_kind = model.max_tool_kind;
pub const max_tool_status = model.max_tool_status;
pub const max_runtime_id = session.max_runtime_id;
pub const max_fx_model = session.max_fx_model;
pub const max_access_mode = session.max_access_mode;
pub const max_interaction_mode = session.max_interaction_mode;
pub const max_reasoning_effort = session.max_reasoning_effort;
/// Codex `ThreadGoal.objective`. Same cap as the composer draft.
pub const max_thread_goal_objective = session.max_thread_goal_objective;
/// Codex `ThreadGoalStatus` wire name (`budgetLimited` is 13).
pub const max_thread_goal_status = session.max_thread_goal_status;
/// Compact `12k/100k · 3m` meter on the composer goal row.
pub const max_thread_goal_usage_label = session.max_thread_goal_usage_label;
pub const max_available_commands = session.max_available_commands;
pub const max_model_options = session.max_model_options;
pub const max_command_name = session.max_command_name;
pub const max_command_description = session.max_command_description;
pub const max_daemon_address = model.max_daemon_address;
pub const max_daemon_token = model.max_daemon_token;
pub const max_sidecar_path = model.max_sidecar_path;

/// Waku `runtime_mode` default. Maps to fx `FX_PERMISSION_MODE=yolo`.
pub const default_access_mode = "fullAccess";
/// Waku `StartOptions.interaction_mode` default (`build` | `plan`).
pub const default_interaction_mode = "build";
/// fx documented `effort` default (`auto` | `none` | `minimal` | `low` |
/// `medium` | `high` | `xhigh` | `max`).
pub const default_reasoning_effort = "auto";

pub const Mode = model.Mode;
pub const Role = model.Role;
pub const Phase = model.Phase;
pub const ReplyPath = model.ReplyPath;

pub const Provider = session.Provider;
pub const AvailableCommand = session.AvailableCommand;
pub const ModelOption = session.ModelOption;
pub const Session = session.Session;

pub const Turn = model.Turn;
pub const Folder = model.Folder;
pub const SessionRow = model.SessionRow;
pub const SidebarRow = model.SidebarRow;

pub const AssignFolder = model.AssignFolder;
pub const TurnRow = model.TurnRow;
pub const CommandRow = model.CommandRow;
pub const ModelPickerRow = model.ModelPickerRow;
pub const ChipPickerRow = model.ChipPickerRow;
pub const DaemonDirBrowserRow = model.DaemonDirBrowserRow;

pub const QueuedMessage = model.QueuedMessage;
pub const QueuedRow = model.QueuedRow;
pub const RightPanelFileRow = model.RightPanelFileRow;
pub const SkillRow = model.SkillRow;
pub const UsageHistoryRow = model.UsageHistoryRow;
pub const ProviderRow = model.ProviderRow;
pub const Msg = model.Msg;
pub const Model = model.Model;
pub const ThemePreference = model.ThemePreference;
pub const LanguagePreference = i18n.LanguagePreference;
pub const ui_font_sizes = model.ui_font_sizes;
pub const default_ui_font_size = model.default_ui_font_size;
pub const sanitizeUiFontSize = model.sanitizeUiFontSize;
pub const code_font_sizes = model.code_font_sizes;
pub const default_code_font_size = model.default_code_font_size;
pub const sanitizeCodeFontSize = model.sanitizeCodeFontSize;

pub const writeFixed = session.writeFixed;

test "Model/Msg barrel types, caps, and defaults match owning modules" {
    _ = Msg;
    _ = Model;
    _ = ThemePreference;
    _ = LanguagePreference;
    _ = sanitizeUiFontSize;
    _ = sanitizeCodeFontSize;
    _ = Mode;
    _ = Role;
    _ = Phase;
    _ = ReplyPath;
    _ = Session;
    _ = Turn;
    _ = Folder;

    try std.testing.expect(Msg == model.Msg);
    try std.testing.expect(Model == model.Model);
    try std.testing.expect(Session == session.Session);
    try std.testing.expect(LanguagePreference == i18n.LanguagePreference);
    try std.testing.expectEqual(@as(u8, 14), default_ui_font_size);
    try std.testing.expectEqual(@as(usize, 8), ui_font_sizes.len);
    try std.testing.expectEqual(@as(u8, 14), sanitizeUiFontSize(14));
    try std.testing.expectEqual(@as(u8, 14), sanitizeUiFontSize(17));
    try std.testing.expectEqual(@as(u8, 11), sanitizeUiFontSize(11));
    try std.testing.expectEqual(@as(u8, 14), default_code_font_size);
    try std.testing.expectEqual(@as(usize, 8), code_font_sizes.len);
    try std.testing.expectEqual(@as(u8, 14), sanitizeCodeFontSize(14));
    try std.testing.expectEqual(@as(u8, 14), sanitizeCodeFontSize(17));
    try std.testing.expectEqual(@as(u8, 11), sanitizeCodeFontSize(11));
    try std.testing.expect(writeFixed == session.writeFixed);

    try std.testing.expectEqual(model.max_sessions, max_sessions);
    try std.testing.expectEqual(model.selection_history_cap, selection_history_cap);
    try std.testing.expectEqual(model.max_turns, max_turns);
    try std.testing.expectEqual(session.max_title, max_title);
    try std.testing.expectEqual(model.max_body, max_body);
    try std.testing.expectEqual(model.max_draft, max_draft);
    try std.testing.expectEqual(model.max_queued, max_queued);
    try std.testing.expectEqual(model.max_queued_text, max_queued_text);
    try std.testing.expectEqual(model.max_fx_path, max_fx_path);
    try std.testing.expectEqual(model.max_store_dir, max_store_dir);
    try std.testing.expectEqual(session.max_project_path, max_project_path);
    try std.testing.expectEqual(model.max_attach_status, max_attach_status);
    try std.testing.expectEqual(session.max_fx_session_id, max_fx_session_id);
    try std.testing.expectEqual(model.max_tool_call_id, max_tool_call_id);
    try std.testing.expectEqual(model.max_tool_kind, max_tool_kind);
    try std.testing.expectEqual(model.max_tool_status, max_tool_status);
    try std.testing.expectEqual(session.max_runtime_id, max_runtime_id);
    try std.testing.expectEqual(session.max_fx_model, max_fx_model);
    try std.testing.expectEqual(session.max_access_mode, max_access_mode);
    try std.testing.expectEqual(session.max_interaction_mode, max_interaction_mode);
    try std.testing.expectEqual(session.max_reasoning_effort, max_reasoning_effort);
    try std.testing.expectEqual(session.max_thread_goal_objective, max_thread_goal_objective);
    try std.testing.expectEqual(session.max_thread_goal_status, max_thread_goal_status);
    try std.testing.expectEqual(session.max_thread_goal_usage_label, max_thread_goal_usage_label);
    try std.testing.expectEqual(session.max_available_commands, max_available_commands);
    try std.testing.expectEqual(session.max_model_options, max_model_options);
    try std.testing.expectEqual(session.max_command_name, max_command_name);
    try std.testing.expectEqual(session.max_command_description, max_command_description);
    try std.testing.expectEqual(model.max_daemon_address, max_daemon_address);
    try std.testing.expectEqual(model.max_daemon_token, max_daemon_token);
    try std.testing.expectEqual(model.max_sidecar_path, max_sidecar_path);

    try std.testing.expectEqual(@as(usize, 16), max_sessions);
    try std.testing.expectEqual(@as(u32, 32), selection_history_cap);
    try std.testing.expectEqual(@as(usize, 128), max_turns);
    try std.testing.expectEqual(@as(usize, 64), max_title);
    try std.testing.expectEqual(@as(usize, 4096), max_body);
    try std.testing.expectEqual(@as(usize, 512), max_draft);
    try std.testing.expectEqual(@as(usize, 16), max_queued);
    try std.testing.expectEqual(@as(usize, 1024), max_queued_text);
    try std.testing.expectEqual(@as(usize, 256), max_fx_path);
    try std.testing.expectEqual(@as(usize, 512), max_store_dir);
    try std.testing.expectEqual(@as(usize, 512), max_project_path);
    try std.testing.expectEqual(@as(usize, 192), max_attach_status);
    try std.testing.expectEqual(@as(usize, 128), max_fx_session_id);
    try std.testing.expectEqual(@as(usize, 128), max_tool_call_id);
    try std.testing.expectEqual(@as(usize, 32), max_tool_kind);
    try std.testing.expectEqual(@as(usize, 32), max_tool_status);
    try std.testing.expectEqual(@as(usize, 36), max_runtime_id);
    try std.testing.expectEqual(@as(usize, 128), max_fx_model);
    try std.testing.expectEqual(@as(usize, 32), max_access_mode);
    try std.testing.expectEqual(@as(usize, 16), max_interaction_mode);
    try std.testing.expectEqual(@as(usize, 16), max_reasoning_effort);
    try std.testing.expectEqual(@as(usize, 512), max_thread_goal_objective);
    try std.testing.expectEqual(@as(usize, 16), max_thread_goal_status);
    try std.testing.expectEqual(@as(usize, 48), max_thread_goal_usage_label);
    try std.testing.expectEqual(@as(usize, 32), max_available_commands);
    try std.testing.expectEqual(@as(usize, 32), max_model_options);
    try std.testing.expectEqual(@as(usize, 64), max_command_name);
    try std.testing.expectEqual(@as(usize, 256), max_command_description);
    try std.testing.expectEqual(@as(usize, 128), max_daemon_address);
    try std.testing.expectEqual(@as(usize, 256), max_daemon_token);
    try std.testing.expectEqual(@as(usize, 512), max_sidecar_path);

    try std.testing.expectEqualStrings("fullAccess", default_access_mode);
    try std.testing.expectEqualStrings("build", default_interaction_mode);
    try std.testing.expectEqualStrings("auto", default_reasoning_effort);

    var buf: [8]u8 = undefined;
    var len: usize = 0;
    writeFixed(&buf, &len, "ok");
    try std.testing.expectEqual(@as(usize, 2), len);
    try std.testing.expectEqualStrings("ok", buf[0..len]);
}
