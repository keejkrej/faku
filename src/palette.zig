//! Command palette: row building and action specs.
//!
//! Overlay matching, section headers, and action ids live here. `Msg`
//! and `Model` live in `model.zig` (re-exported from `main`). `Session`
//! lives in `session.zig`. Behavior is unchanged from the former
//! `main` palette helpers.

const std = @import("std");
const main = @import("main.zig");

const Model = main.Model;
const Session = main.Session;

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
    maximize = 8,
    /// Selected session's local numeric id as decimal text. Not a UUID.
    copy_session_id = 9,
    /// Selected session `fx_session_id` (fx ask --json / ACP sessionId).
    copy_fx_session_id = 10,
    /// Selected session workspace in the OS file manager. Not Open-in.
    reveal_folder = 11,
};

pub const PaletteActionSpec = struct {
    action: PaletteAction,
    label: []const u8,
    keywords: []const []const u8,
    suggested: bool,
};

pub const palette_action_specs = [_]PaletteActionSpec{
    .{ .action = .new_task, .label = "New Task", .keywords = &.{ "new", "task", "session" }, .suggested = true },
    .{ .action = .focus_composer, .label = "Focus composer", .keywords = &.{ "composer", "prompt", "input" }, .suggested = true },
    .{ .action = .toggle_sidebar, .label = "Toggle sidebar", .keywords = &.{ "sidebar", "panel" }, .suggested = false },
    .{ .action = .collapse_folders, .label = "Collapse all folders", .keywords = &.{ "collapse", "folder", "folders" }, .suggested = false },
    .{ .action = .find_in_transcript, .label = "Find in transcript", .keywords = &.{ "find", "search", "transcript" }, .suggested = false },
    .{ .action = .settings, .label = "Settings", .keywords = &.{ "settings", "preferences" }, .suggested = false },
    .{ .action = .minimize, .label = "Minimize", .keywords = &.{ "minimize", "window" }, .suggested = false },
    .{ .action = .maximize, .label = "Maximize", .keywords = &.{ "maximize", "window", "zoom" }, .suggested = false },
    .{ .action = .copy_session_id, .label = "Copy session id", .keywords = &.{ "copy", "id", "session" }, .suggested = false },
    .{ .action = .copy_fx_session_id, .label = "Copy provider session id", .keywords = &.{ "copy", "id", "session", "fx", "acp", "provider" }, .suggested = false },
    .{ .action = .reveal_folder, .label = "Reveal project folder", .keywords = &.{ "reveal", "finder", "files", "folder", "open", "project" }, .suggested = false },
};

pub fn paletteActionId(action: PaletteAction) u32 {
    return palette_action_id_base + @intFromEnum(action);
}

pub fn paletteActionFromId(id: u32) ?PaletteAction {
    if (id < palette_action_id_base or id >= palette_header_id_base) return null;
    const raw = id - palette_action_id_base;
    inline for (std.meta.tags(PaletteAction)) |action| {
        if (raw == @intFromEnum(action)) return action;
    }
    return null;
}

pub fn rows(model: *const Model, arena: std.mem.Allocator) []const PaletteRow {
    if (!model.palette_open) return &.{};
    const query = std.mem.trim(u8, model.search_query(), " \t\r\n");
    var specs_buf: [palette_action_specs.len]PaletteActionSpec = undefined;
    const specs = matchingPaletteActions(model, query, &specs_buf);
    var session_ids: [palette_max_task_results]u32 = undefined;
    const sessions_n = if (query.len == 0)
        0
    else
        matchingPaletteSessions(model, query, &session_ids);

    const miss = query.len > 0 and specs.len == 0 and sessions_n == 0;
    var count: usize = 0;
    if (query.len == 0) {
        count += 1 + suggestedPaletteCount(specs) + 1 + commandPaletteCount(specs);
    } else if (miss) {
        count = 2;
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
    } else if (miss) {
        out[i] = paletteHeaderRow(4, "No matching tasks or commands");
        i += 1;
        out[i] = paletteHeaderRow(5, "Try a task title, project, provider, model, or command");
        i += 1;
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

pub fn selectableCount(model: *const Model) u32 {
    const query = std.mem.trim(u8, model.search_query(), " \t\r\n");
    var specs_buf: [palette_action_specs.len]PaletteActionSpec = undefined;
    const specs = matchingPaletteActions(model, query, &specs_buf);
    var session_ids: [palette_max_task_results]u32 = undefined;
    const sessions_n = if (query.len == 0)
        0
    else
        matchingPaletteSessions(model, query, &session_ids);
    return @intCast(specs.len + sessions_n);
}

pub fn selectableIdAt(model: *const Model, index: u32) ?u32 {
    const query = std.mem.trim(u8, model.search_query(), " \t\r\n");
    var specs_buf: [palette_action_specs.len]PaletteActionSpec = undefined;
    const specs = matchingPaletteActions(model, query, &specs_buf);
    var cursor: u32 = 0;
    for (specs) |spec| {
        if (cursor == index) return paletteActionId(spec.action);
        cursor += 1;
    }
    if (query.len == 0) return null;
    var session_ids: [palette_max_task_results]u32 = undefined;
    const sessions_n = matchingPaletteSessions(model, query, &session_ids);
    var s: usize = 0;
    while (s < sessions_n) : (s += 1) {
        if (cursor == index) return session_ids[s];
        cursor += 1;
    }
    return null;
}

pub fn clampHighlight(model: *Model) void {
    const count = selectableCount(model);
    if (count == 0) {
        model.palette_highlight = 0;
        return;
    }
    if (model.palette_highlight >= count) model.palette_highlight = count - 1;
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
        .label = main.sessionDisplayTitle(session),
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
    if (main.asciiContainsIgnoreCase(spec.label, query)) return true;
    for (spec.keywords) |keyword| {
        if (main.asciiContainsIgnoreCase(keyword, query)) return true;
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

fn sessionMatchesQuery(session: *const Session, query: []const u8) bool {
    if (query.len == 0) return true;
    if (main.asciiContainsIgnoreCase(main.sessionDisplayTitle(session), query)) return true;
    if (main.asciiContainsIgnoreCase(session.title(), query)) return true;
    if (main.asciiContainsIgnoreCase(session.provider_label(), query)) return true;
    if (main.asciiContainsIgnoreCase(session.projectPath(), query)) return true;
    return main.asciiContainsIgnoreCase(session.model(), query);
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
