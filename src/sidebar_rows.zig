//! Sidebar row builders: date buckets, folder rows, and width clamps.
//!
//! Ungrouped date-header rows, folder headers, session row shaping,
//! and sidebar split clamp/resize live here. `Model` and `SidebarRow`
//! live in `model.zig` (re-exported from `main`). `Session` lives in
//! `session.zig`. Behavior is unchanged from the former `main` sidebar
//! row helpers.

const std = @import("std");
const main = @import("main.zig");
const sidebar_dates = @import("sidebar_dates.zig");

const Model = main.Model;
const Session = main.Session;
const SidebarRow = main.SidebarRow;
const DateBucket = sidebar_dates.DateBucket;
const sessionDateBucket = sidebar_dates.sessionDateBucket;
const sessionRelativeTime = sidebar_dates.sessionRelativeTime;

/// Date-bucket header keys sit above folder headers.
pub const date_row_id_base: u32 = 4_000_000;

const max_sessions = @typeInfo(@FieldType(Model, "session_store")).array.len;

pub fn rows(model: *const Model, arena: std.mem.Allocator) []const SidebarRow {
    var ungrouped: [max_sessions]u32 = undefined;
    const ungrouped_n = collectUngroupedNewestFirst(model, &ungrouped);
    var today_n: usize = 0;
    var yesterday_n: usize = 0;
    var this_week_n: usize = 0;
    var this_month_n: usize = 0;
    var this_year_n: usize = 0;
    var older_n: usize = 0;
    for (ungrouped[0..ungrouped_n]) |id| {
        const session = model.sessionByIdConst(id) orelse continue;
        switch (sessionDateBucket(session.updated_at, model.now_ms)) {
            .today => today_n += 1,
            .yesterday => yesterday_n += 1,
            .this_week => this_week_n += 1,
            .this_month => this_month_n += 1,
            .this_year => this_year_n += 1,
            .older => older_n += 1,
        }
    }
    const show_date_headers = yesterday_n > 0 or this_week_n > 0 or this_month_n > 0 or this_year_n > 0 or older_n > 0;
    var count: usize = ungrouped_n;
    if (show_date_headers) {
        if (today_n > 0) count += 1;
        if (yesterday_n > 0) count += 1;
        if (this_week_n > 0) count += 1;
        if (this_month_n > 0) count += 1;
        if (this_year_n > 0) count += 1;
        if (older_n > 0) count += 1;
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
    if (show_date_headers) {
        i = appendDateBucket(model, out, i, ungrouped[0..ungrouped_n], .today, arena);
        i = appendDateBucket(model, out, i, ungrouped[0..ungrouped_n], .yesterday, arena);
        i = appendDateBucket(model, out, i, ungrouped[0..ungrouped_n], .this_week, arena);
        i = appendDateBucket(model, out, i, ungrouped[0..ungrouped_n], .this_month, arena);
        i = appendDateBucket(model, out, i, ungrouped[0..ungrouped_n], .this_year, arena);
        i = appendDateBucket(model, out, i, ungrouped[0..ungrouped_n], .older, arena);
    } else {
        for (ungrouped[0..ungrouped_n]) |id| {
            const session = model.sessionByIdConst(id) orelse continue;
            out[i] = sessionSidebarRow(model, session, arena);
            i += 1;
        }
    }
    for (model.folder_store[0..model.folder_count]) |*folder| {
        out[i] = .{
            .id = main.folder_row_id_base + folder.id,
            .title = folder.title(),
            .provider = "",
            .selected = selectedSessionInFolder(model, folder.id),
            .is_header = true,
            .editing = model.editing_folder_id == folder.id,
            .folder_id = folder.id,
            .grouped = false,
            .is_date_header = false,
        };
        i += 1;
        if (folder.collapsed) continue;
        for (model.session_store[0..model.session_count]) |*session| {
            if (effectiveFolderId(model, session) != folder.id) continue;
            out[i] = sessionSidebarRow(model, session, arena);
            i += 1;
        }
    }
    return out[0..i];
}

fn dateHeaderRow(bucket: DateBucket) SidebarRow {
    return .{
        .id = date_row_id_base + @intFromEnum(bucket) + 1,
        .title = bucket.title(),
        .provider = "",
        .selected = false,
        .is_header = true,
        .editing = false,
        .folder_id = 0,
        .grouped = false,
        .is_date_header = true,
    };
}

fn collectUngroupedNewestFirst(model: *const Model, dest: []u32) usize {
    var n: usize = 0;
    for (model.session_store[0..model.session_count]) |*session| {
        if (effectiveFolderId(model, session) != 0) continue;
        if (n >= dest.len) break;
        dest[n] = session.id;
        n += 1;
    }
    var i: usize = 1;
    while (i < n) : (i += 1) {
        const id = dest[i];
        const stamp = ungroupedSortStamp(model, id);
        var j = i;
        while (j > 0 and ungroupedSortStamp(model, dest[j - 1]) < stamp) {
            dest[j] = dest[j - 1];
            j -= 1;
        }
        dest[j] = id;
    }
    return n;
}

fn ungroupedSortStamp(model: *const Model, id: u32) i64 {
    const session = model.sessionByIdConst(id) orelse return 0;
    return session.updated_at;
}

fn appendDateBucket(
    model: *const Model,
    out: []SidebarRow,
    start: usize,
    ungrouped: []const u32,
    bucket: DateBucket,
    arena: std.mem.Allocator,
) usize {
    var i = start;
    var header = false;
    for (ungrouped) |id| {
        const session = model.sessionByIdConst(id) orelse continue;
        if (sessionDateBucket(session.updated_at, model.now_ms) != bucket) continue;
        if (!header) {
            out[i] = dateHeaderRow(bucket);
            i += 1;
            header = true;
        }
        out[i] = sessionSidebarRow(model, session, arena);
        i += 1;
    }
    return i;
}

fn sessionSidebarRow(model: *const Model, session: *const Session, arena: std.mem.Allocator) SidebarRow {
    const relative = allocRelativeTime(arena, session.updated_at, model.now_ms);
    return .{
        .id = session.id,
        .title = main.sessionDisplayTitle(session),
        .provider = session.provider_label(),
        .selected = session.id == model.selected,
        .is_header = false,
        .editing = model.editing_session_id == session.id,
        .folder_id = session.folder_id,
        .grouped = session.folder_id != 0,
        .busy = session.busy,
        .is_date_header = false,
        .relative_time = relative,
        .has_relative_time = relative.len > 0,
    };
}

fn allocRelativeTime(arena: std.mem.Allocator, updated_at: i64, now_ms: i64) []const u8 {
    var buf: [16]u8 = undefined;
    const label = sessionRelativeTime(updated_at, now_ms, &buf) orelse return "";
    return arena.dupe(u8, label) catch "";
}

pub fn selectedSessionInFolder(model: *const Model, folder_id: u32) bool {
    const session = model.sessionByIdConst(model.selected) orelse return false;
    return effectiveFolderId(model, session) == folder_id;
}

pub fn effectiveFolderId(model: *const Model, session: *const Session) u32 {
    if (session.folder_id == 0) return 0;
    if (model.folderByIdConst(session.folder_id) == null) return 0;
    return session.folder_id;
}

pub fn folderTitleTaken(model: *const Model, title: []const u8) bool {
    for (model.folder_store[0..model.folder_count]) |*folder| {
        if (std.mem.eql(u8, folder.title(), title)) return true;
    }
    return false;
}

pub fn clampSidebarWidth(width: f32) f32 {
    const raw = if (width > 0) width else main.sidebar_default_width;
    return @max(main.sidebar_min_width, @min(main.sidebar_max_width, raw));
}

pub fn collapsedSidebarSplit() f32 {
    return main.sidebar_rail_width / main.window_width;
}

pub fn clampExpandedSidebarSplit(value: f32) f32 {
    const min_split = main.sidebar_min_width / main.window_width;
    const max_split = main.sidebar_max_width / main.window_width;
    return @max(min_split, @min(max_split, value));
}

pub fn rememberExpandedWidth(model: *Model) void {
    if (model.sidebar_collapsed) return;
    model.sidebar_last_width = clampSidebarWidth(model.sidebar_split * main.window_width);
}

pub fn applySidebarResize(model: *Model, fraction: f32) void {
    const width = fraction * main.window_width;
    if (model.sidebar_collapsed) {
        if (width < main.sidebar_min_width) return;
        model.sidebar_collapsed = false;
        model.sidebar_last_width = clampSidebarWidth(width);
        model.syncSidebarSplit();
        return;
    }
    model.sidebar_split = clampExpandedSidebarSplit(fraction);
    model.sidebar_last_width = clampSidebarWidth(model.sidebar_split * main.window_width);
}
