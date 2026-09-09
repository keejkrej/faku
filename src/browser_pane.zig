//! First-cut embedded right-panel Browser: Native canvas `web_panes`.
//!
//! Canvas-first apps declare scene `.webview` views parented to the
//! gpu_surface and drive them with `UiApp.Options.web_panes` (workbench /
//! canvas-preview at vercel-labs/native @ 064ca989). Native
//! `max_web_panes` is 4 (`ui_app.zig`); this module declares one scene
//! webview per slot (`browser-web-0`..`browser-web-3`). This is not a
//! markup `<webview>` tag and not Waku BrowserView (UUID right-panel
//! surfaces, DevTools, UA spoof).
//!
//! First-cut multi-session lives **inside** the existing Browser tab:
//! up to four slots (chips + New + Close; Close keeps at least one).
//! Each occupied slot keeps its own address-bar draft, committed
//! history ring, history index, and `reload_token`. Inactive occupied
//! slots park at 1×1 with `anchor = null` so they do not overlay
//! Files/Diff/Terminal but keep the webview process/state. Unopened
//! slots stay parked at the home placeholder. Hidden Browser parks
//! **all** panes the same way.
//!
//! Pane URL is the committed history entry, never the address-bar draft.
//! `sessions.json` extras persist the **active** slot's address draft
//! (`browser_url`) plus occupied slot committed URLs (`browser_slots`)
//! and `browser_active`. Full history rings, back/forward index, and
//! `reload_token` stay runtime-only. Empty history uses the scene
//! placeholder `https://example.com` until Navigate/Enter.
//! Enter/Navigate uses Safari/Waku omnibox resolve (explicit schemes,
//! localhost/IPv4 → `http`, host-like → `https`, else Google search).
//!
//! Native `applyWebPane` keeps the last frame when the anchor is missing
//! or width/height < 1 (`ui_app.zig`). Public `WebViewPane` has no
//! `visible` field. Parking uses `anchor = null` and a 1×1 frame at
//! (0,0).

const std = @import("std");
const native_sdk = @import("native_sdk");
const model_mod = @import("model.zig");
const open_url = @import("open_url.zig");

const canvas = native_sdk.canvas;
const geometry = native_sdk.geometry;

const Model = model_mod.Model;
const Msg = model_mod.Msg;

const FakuApp = native_sdk.UiApp(Model, Msg);
pub const WebViewPane = FakuApp.WebViewPane;

/// Native `UiApp` `max_web_panes` (vercel-labs/native `ui_app.zig` @
/// 064ca989). Cap matches that documented array.
pub const max_sessions: usize = 4;
/// Scene `.webview` labels. Same spelling as `app.zon` / `app.json` /
/// `shell.zig`. One live webview process per slot.
pub const web_view_labels = [_][]const u8{
    "browser-web-0",
    "browser-web-1",
    "browser-web-2",
    "browser-web-3",
};
/// Occupancy-order chip labels (`1`..`n`), matching Terminal.
pub const slot_labels = [_][]const u8{ "1", "2", "3", "4" };
/// Markup semantics label the **active** pane snaps to
/// (`<column label="browser-pane">`).
pub const web_pane_anchor = "browser-pane";
/// Scene placeholder and empty-history pane URL.
pub const home_url = "https://example.com";
/// Workbench `max_history` ring. Runtime-only.
pub const max_history = 32;
/// Parking frame: positive size so `applyWebPane` does not keep the last
/// content-sized snapshot when the Browser tab is hidden or the slot is
/// inactive.
pub const parked_frame = geometry.RectF.init(0, 0, 1, 1);

/// Per-slot Browser state. Occupied slots keep a live scene webview.
/// Occupancy, the committed pane URL, and the active index persist on
/// `sessions.json` extras (`browser_slots` / `browser_active`); the
/// active address draft still persists as `browser_url`. History rings
/// and `reload_token` stay runtime-only.
pub const Slot = struct {
    occupied: bool = false,
    url_buffer: canvas.TextBuffer(open_url.max_url) = .{},
    history: [max_history]canvas.TextBuffer(open_url.max_spawn_url) = [_]canvas.TextBuffer(open_url.max_spawn_url){.{}} ** max_history,
    history_count: usize = 0,
    history_index: usize = 0,
    reload_token: u64 = 0,
};

pub const BrowserSessionRow = struct {
    id: u32,
    label: []const u8,
    selected: bool,
};

/// Occupied slot persist row. `url` is the committed history entry
/// (empty when the slot has never navigated). Unoccupied slots are
/// `occupied = false` and encode as JSON `null`.
pub const PersistedSlot = struct {
    occupied: bool = false,
    url: []const u8 = "",
};

/// Slot 0 starts occupied so the first-cut Browser tab still has a
/// session without clicking New (today's single-pane behavior).
pub const default_slots: [max_sessions]Slot = init: {
    var slots = [_]Slot{.{}} ** max_sessions;
    slots[0].occupied = true;
    break :init slots;
};

pub fn webViewLabel(index: usize) []const u8 {
    return web_view_labels[index];
}

pub fn slotIndexForId(id: u32) ?usize {
    if (id == 0 or id > max_sessions) return null;
    return id - 1;
}

fn slotId(index: usize) u32 {
    return @intCast(index + 1);
}

pub fn activeIndex(model: *const Model) usize {
    if (model.browser_active >= max_sessions) return 0;
    return model.browser_active;
}

fn slotConst(model: *const Model, index: usize) *const Slot {
    return &model.browser_slots[index];
}

fn slotPtr(model: *Model, index: usize) *Slot {
    return &model.browser_slots[index];
}

pub fn activeSlotConst(model: *const Model) *const Slot {
    return slotConst(model, activeIndex(model));
}

pub fn activeSlot(model: *Model) *Slot {
    return slotPtr(model, activeIndex(model));
}

pub fn occupiedCount(model: *const Model) usize {
    var n: usize = 0;
    for (&model.browser_slots) |*slot| {
        if (slot.occupied) n += 1;
    }
    return n;
}

fn findFreeIndex(model: *const Model) ?usize {
    for (model.browser_slots, 0..) |slot, i| {
        if (!slot.occupied) return i;
    }
    return null;
}

pub fn can_new_browser(model: *const Model) bool {
    return occupiedCount(model) < max_sessions;
}

/// Close stays available while a neighbor remains. First-cut keeps at
/// least one session so the address bar always has an active slot.
pub fn can_close_browser(model: *const Model) bool {
    return occupiedCount(model) > 1 and activeSlotConst(model).occupied;
}

/// Occupancy-order chips (`1`..`n`) with stable 1-based slot ids.
pub fn sessionRows(model: *const Model, arena: std.mem.Allocator) []const BrowserSessionRow {
    const count = occupiedCount(model);
    if (count == 0) return &.{};
    const out = arena.alloc(BrowserSessionRow, count) catch return &.{};
    var n: usize = 0;
    const active = activeIndex(model);
    for (model.browser_slots, 0..) |slot, i| {
        if (!slot.occupied) continue;
        out[n] = .{
            .id = slotId(i),
            .label = slot_labels[n],
            .selected = i == active,
        };
        n += 1;
    }
    return out[0..n];
}

pub fn setDraft(model: *Model, url: []const u8) void {
    activeSlot(model).url_buffer.set(url);
}

pub fn clearDraft(model: *Model) void {
    activeSlot(model).url_buffer.clear();
}

pub fn applyDraft(model: *Model, edit: canvas.TextInputEvent) void {
    activeSlot(model).url_buffer.apply(edit);
}

pub fn draft(model: *const Model) []const u8 {
    return activeSlotConst(model).url_buffer.text();
}

fn currentUrlAt(model: *const Model, index: usize) []const u8 {
    const slot = slotConst(model, index);
    if (!slot.occupied or slot.history_count == 0) return home_url;
    return slot.history[slot.history_index].text();
}

/// Committed pane URL for persist. Empty when the slot is unoccupied
/// or has never navigated (the live pane still shows `home_url`).
pub fn committedUrlAt(model: *const Model, index: usize) []const u8 {
    const slot = slotConst(model, index);
    if (!slot.occupied or slot.history_count == 0) return "";
    return slot.history[slot.history_index].text();
}

pub fn capturePersisted(model: *const Model, out: *[max_sessions]PersistedSlot) void {
    for (0..max_sessions) |i| {
        const occupied = slotConst(model, i).occupied;
        out[i] = .{
            .occupied = occupied,
            .url = if (occupied) committedUrlAt(model, i) else "",
        };
    }
}

/// Rebuild occupancy, a single-entry history for each committed URL,
/// and the active index. Does not restore back/forward rings or
/// `reload_token`. Zero occupied slots keep today's slot-0 session.
pub fn restoreFromPersist(model: *Model, slots: []const PersistedSlot, active: u8) void {
    model.browser_slots = [_]Slot{.{}} ** max_sessions;
    const n = @min(slots.len, max_sessions);
    var any = false;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (!slots[i].occupied) continue;
        any = true;
        restoreOccupied(&model.browser_slots[i], slots[i].url);
    }
    if (!any) model.browser_slots[0].occupied = true;
    if (active < max_sessions and model.browser_slots[active].occupied) {
        model.browser_active = active;
        return;
    }
    model.browser_active = 0;
    for (model.browser_slots, 0..) |slot, idx| {
        if (!slot.occupied) continue;
        model.browser_active = @intCast(idx);
        return;
    }
}

fn restoreOccupied(slot: *Slot, url: []const u8) void {
    slot.* = .{ .occupied = true };
    if (url.len == 0) return;
    slot.history[0].set(url);
    slot.history_count = 1;
    slot.history_index = 0;
    slot.url_buffer.set(url);
}

pub fn currentUrl(model: *const Model) []const u8 {
    return currentUrlAt(model, activeIndex(model));
}

pub fn backDisabled(model: *const Model) bool {
    return activeSlotConst(model).history_index == 0;
}

pub fn forwardDisabled(model: *const Model) bool {
    const slot = activeSlotConst(model);
    return slot.history_count == 0 or slot.history_index + 1 >= slot.history_count;
}

fn selectNeighbor(model: *Model, closed_index: usize) void {
    var i = closed_index;
    while (i > 0) {
        i -= 1;
        if (slotConst(model, i).occupied) {
            model.browser_active = @intCast(i);
            return;
        }
    }
    i = closed_index + 1;
    while (i < max_sessions) : (i += 1) {
        if (slotConst(model, i).occupied) {
            model.browser_active = @intCast(i);
            return;
        }
    }
    model.browser_active = 0;
}

fn occupyAt(model: *Model, index: usize) void {
    slotPtr(model, index).* = .{ .occupied = true };
    model.browser_active = @intCast(index);
}

pub fn newSession(model: *Model) void {
    const index = findFreeIndex(model) orelse return;
    occupyAt(model, index);
}

pub fn selectSession(model: *Model, id: u32) void {
    const index = slotIndexForId(id) orelse return;
    if (!slotConst(model, index).occupied) return;
    model.browser_active = @intCast(index);
}

/// Close the active slot and select the previous occupied neighbor,
/// else the next. No-op when only one session remains.
pub fn closeActive(model: *Model) void {
    if (!can_close_browser(model)) return;
    const index = activeIndex(model);
    slotPtr(model, index).* = .{};
    selectNeighbor(model, index);
}

const google_search_prefix = "https://www.google.com/search?q=";
const form_url_hex = "0123456789ABCDEF";

/// Safari/Waku omnibox resolve (egoist/waku `src/browser.rs`
/// `resolve_address` + `search_url`, read-only). Empty / whitespace-only
/// and dest overflow are misses. Explicit schemes pass through; host-like
/// text gets `http` (localhost / IPv4) or `https`; anything else is a
/// Google search URL.
pub fn resolveAddress(raw: []const u8, dest: []u8) ?[]const u8 {
    const trimmed = std.mem.trim(u8, raw, " \t\r\n");
    if (trimmed.len == 0) return null;
    if (hasExplicitScheme(trimmed)) return copyInto(trimmed, dest);
    if (hasInternalWhitespace(trimmed)) return writeSearchUrl(trimmed, dest);

    const authority = authorityOf(trimmed);
    const parsed = splitHostPort(authority) orelse return writeSearchUrl(trimmed, dest);
    const is_ip = isIpv4Like(parsed.host);
    const is_local = std.ascii.eqlIgnoreCase(parsed.host, "localhost") or is_ip;
    const host_like = is_local or isHostLikeName(parsed.host);
    if (!host_like) return writeSearchUrl(trimmed, dest);
    const scheme: []const u8 = if (is_local or (parsed.has_port and std.ascii.eqlIgnoreCase(parsed.host, "localhost")))
        "http"
    else
        "https";
    return std.fmt.bufPrint(dest, "{s}://{s}", .{ scheme, trimmed }) catch null;
}

fn copyInto(text: []const u8, dest: []u8) ?[]const u8 {
    if (text.len > dest.len) return null;
    @memcpy(dest[0..text.len], text);
    return dest[0..text.len];
}

fn hasExplicitScheme(trimmed: []const u8) bool {
    const colon = std.mem.indexOfScalar(u8, trimmed, ':') orelse return false;
    const scheme = trimmed[0..colon];
    const rest = trimmed[colon + 1 ..];
    if (scheme.len == 0 or !std.ascii.isAlphabetic(scheme[0])) return false;
    for (scheme) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '+' and c != '-' and c != '.') return false;
    }
    if (std.mem.startsWith(u8, rest, "//")) return true;
    return std.mem.eql(u8, scheme, "about") or
        std.mem.eql(u8, scheme, "data") or
        std.mem.eql(u8, scheme, "mailto") or
        std.mem.eql(u8, scheme, "file");
}

fn hasInternalWhitespace(text: []const u8) bool {
    for (text) |c| {
        if (std.ascii.isWhitespace(c)) return true;
    }
    return false;
}

fn authorityOf(trimmed: []const u8) []const u8 {
    const end = std.mem.indexOfAny(u8, trimmed, "/?#") orelse return trimmed;
    return trimmed[0..end];
}

const HostPort = struct {
    host: []const u8,
    has_port: bool,
};

/// Host plus whether a numeric port was present. `null` when a colon is
/// present but the tail is not an all-digit port (Waku treats that as search).
fn splitHostPort(authority: []const u8) ?HostPort {
    const colon = std.mem.lastIndexOfScalar(u8, authority, ':') orelse {
        return .{ .host = authority, .has_port = false };
    };
    const port = authority[colon + 1 ..];
    if (port.len == 0 or !isAllAsciiDigits(port)) return null;
    return .{ .host = authority[0..colon], .has_port = true };
}

fn isAllAsciiDigits(text: []const u8) bool {
    for (text) |c| {
        if (!std.ascii.isDigit(c)) return false;
    }
    return true;
}

fn isIpv4Like(host: []const u8) bool {
    if (host.len == 0) return false;
    var parts: usize = 1;
    for (host) |c| {
        if (c == '.') {
            parts += 1;
            if (parts > 4) return false;
        } else if (!std.ascii.isDigit(c)) {
            return false;
        }
    }
    return parts == 4;
}

fn isHostLikeName(host: []const u8) bool {
    if (host.len == 0 or host[0] == '.' or host[host.len - 1] == '.') return false;
    var saw_dot = false;
    for (host) |c| {
        if (c == '.') {
            saw_dot = true;
        } else if (!std.ascii.isAlphanumeric(c) and c != '-') {
            return false;
        }
    }
    return saw_dot;
}

fn writeSearchUrl(query: []const u8, dest: []u8) ?[]const u8 {
    if (google_search_prefix.len > dest.len) return null;
    @memcpy(dest[0..google_search_prefix.len], google_search_prefix);
    var i: usize = google_search_prefix.len;
    for (query) |byte| {
        switch (byte) {
            'A'...'Z', 'a'...'z', '0'...'9', '-', '.', '_', '~' => {
                if (i >= dest.len) return null;
                dest[i] = byte;
                i += 1;
            },
            ' ' => {
                if (i >= dest.len) return null;
                dest[i] = '+';
                i += 1;
            },
            else => {
                if (i + 3 > dest.len) return null;
                dest[i] = '%';
                dest[i + 1] = form_url_hex[byte >> 4];
                dest[i + 2] = form_url_hex[byte & 0x0F];
                i += 3;
            },
        }
    }
    return dest[0..i];
}

/// Commit the address-bar draft: Safari/Waku omnibox resolve, drop the
/// forward tail, append, and point the **active** pane at it. Empty /
/// overflow is a no-op (history unchanged). Open-in-OS still uses
/// `open_url.normalizeUrl`.
pub fn commitNavigation(model: *Model) void {
    var resolved: [open_url.max_spawn_url]u8 = undefined;
    const url = resolveAddress(draft(model), &resolved) orelse return;
    const slot = activeSlot(model);
    if (!slot.occupied) occupyAt(model, activeIndex(model));
    const live = activeSlot(model);
    if (live.history_count > 0) {
        live.history_index += 1;
    }
    if (live.history_index >= max_history) {
        std.mem.copyForwards(
            canvas.TextBuffer(open_url.max_spawn_url),
            live.history[0 .. max_history - 1],
            live.history[1..max_history],
        );
        live.history_index = max_history - 1;
    }
    live.history[live.history_index].set(url);
    live.history_count = live.history_index + 1;
    live.url_buffer.set(url);
}

pub fn goBack(model: *Model) void {
    const slot = activeSlot(model);
    if (slot.history_index == 0) return;
    slot.history_index -= 1;
    slot.url_buffer.set(slot.history[slot.history_index].text());
}

pub fn goForward(model: *Model) void {
    const slot = activeSlot(model);
    if (slot.history_count == 0 or slot.history_index + 1 >= slot.history_count) return;
    slot.history_index += 1;
    slot.url_buffer.set(slot.history[slot.history_index].text());
}

pub fn reload(model: *Model) void {
    activeSlot(model).reload_token +%= 1;
}

/// Model-derived webview panes. Always one pane per scene webview
/// (Native `max_web_panes` = 4). The active occupied slot snaps to
/// `browser-pane` when the Browser tab is showing; every other pane
/// parks at 1×1 with no anchor. Unopened slots use the home URL.
pub fn webPanes(model: *const Model, out: []WebViewPane) usize {
    const showing = model.right_panel_showing_browser();
    const active = activeIndex(model);
    var n: usize = 0;
    for (0..max_sessions) |i| {
        const occupied = slotConst(model, i).occupied;
        const snap = showing and occupied and i == active;
        out[n] = .{
            .label = web_view_labels[i],
            .anchor = if (snap) web_pane_anchor else null,
            .frame = if (snap) geometry.RectF.init(0, 0, 0, 0) else parked_frame,
            .url = currentUrlAt(model, i),
            .reload_token = if (occupied) slotConst(model, i).reload_token else 0,
        };
        n += 1;
    }
    return n;
}

fn expectParked(pane: WebViewPane) !void {
    try std.testing.expect(pane.anchor == null);
    try std.testing.expectEqual(@as(f32, 0), pane.frame.x);
    try std.testing.expectEqual(@as(f32, 0), pane.frame.y);
    try std.testing.expectEqual(@as(f32, 1), pane.frame.width);
    try std.testing.expectEqual(@as(f32, 1), pane.frame.height);
}

test "web_panes labels match the four scene placeholders and Native pane cap" {
    try std.testing.expectEqual(@as(usize, 4), max_sessions);
    try std.testing.expectEqual(@as(usize, 4), web_view_labels.len);
    try std.testing.expectEqualStrings("browser-web-0", web_view_labels[0]);
    try std.testing.expectEqualStrings("browser-web-3", web_view_labels[3]);
    try std.testing.expectEqualStrings("browser-pane", web_pane_anchor);
    try std.testing.expectEqualStrings("https://example.com", home_url);
    try std.testing.expectEqual(@as(usize, 32), max_history);
    try std.testing.expectEqual(max_history, @typeInfo(@FieldType(Slot, "history")).array.len);
    const views = @import("shell.zig").shell_scene.windows[0].views;
    try std.testing.expectEqual(@as(usize, 1 + max_sessions), views.len);
    var i: usize = 0;
    while (i < max_sessions) : (i += 1) {
        try std.testing.expectEqualStrings(web_view_labels[i], views[1 + i].label);
        try std.testing.expect(views[1 + i].kind == .webview);
        try std.testing.expectEqualStrings(home_url, views[1 + i].url.?);
    }
    try std.testing.expectEqual(@as(f32, 1), parked_frame.width);
    try std.testing.expectEqual(@as(f32, 1), parked_frame.height);
}

test "hidden Browser parks every pane 1x1 with no anchor; showing snaps only the active slot" {
    var model: Model = .{};
    var panes: [max_sessions]WebViewPane = undefined;

    try std.testing.expect(!model.right_panel_showing_browser());
    try std.testing.expectEqual(@as(usize, 4), webPanes(&model, &panes));
    try std.testing.expectEqualStrings(web_view_labels[0], panes[0].label);
    try expectParked(panes[0]);
    try std.testing.expectEqualStrings(home_url, panes[0].url);
    try std.testing.expectEqual(@as(u64, 0), panes[0].reload_token);
    try expectParked(panes[1]);
    try expectParked(panes[2]);
    try expectParked(panes[3]);
    try std.testing.expectEqualStrings(web_view_labels[3], panes[3].label);

    model.right_panel_open = true;
    model.right_panel_tab = .files;
    _ = webPanes(&model, &panes);
    try expectParked(panes[0]);
    try expectParked(panes[1]);

    model.right_panel_tab = .browser;
    try std.testing.expect(model.right_panel_showing_browser());
    _ = webPanes(&model, &panes);
    try std.testing.expectEqualStrings(web_pane_anchor, panes[0].anchor orelse "");
    try std.testing.expectEqualStrings(home_url, panes[0].url);
    try expectParked(panes[1]);
    try expectParked(panes[2]);
    try expectParked(panes[3]);
}

test "address keystrokes do not navigate; Enter/Navigate commits a normalized URL" {
    var model: Model = .{};
    var panes: [max_sessions]WebViewPane = undefined;

    setDraft(&model, "  example.com/path  ");
    _ = webPanes(&model, &panes);
    try std.testing.expectEqualStrings(home_url, panes[0].url);
    try std.testing.expectEqualStrings("  example.com/path  ", draft(&model));

    commitNavigation(&model);
    _ = webPanes(&model, &panes);
    try std.testing.expectEqualStrings("https://example.com/path", panes[0].url);
    try std.testing.expectEqualStrings("https://example.com/path", draft(&model));
    try std.testing.expectEqualStrings("https://example.com/path", currentUrl(&model));
    try std.testing.expect(backDisabled(&model));
    try std.testing.expect(forwardDisabled(&model));

    setDraft(&model, "http://localhost:3000");
    commitNavigation(&model);
    _ = webPanes(&model, &panes);
    try std.testing.expectEqualStrings("http://localhost:3000", panes[0].url);
    try std.testing.expect(!backDisabled(&model));
    try std.testing.expect(forwardDisabled(&model));
}

test "empty navigate is a no-op; overflow-normalize is a no-op" {
    var model: Model = .{};
    commitNavigation(&model);
    try std.testing.expectEqual(@as(usize, 0), activeSlotConst(&model).history_count);
    try std.testing.expectEqualStrings(home_url, currentUrl(&model));

    setDraft(&model, "   \t  ");
    commitNavigation(&model);
    try std.testing.expectEqual(@as(usize, 0), activeSlotConst(&model).history_count);
}

test "back and forward walk the app-owned history; a new navigation drops the tail" {
    var model: Model = .{};

    setDraft(&model, "https://a.example");
    commitNavigation(&model);
    setDraft(&model, "https://b.example");
    commitNavigation(&model);
    try std.testing.expectEqual(@as(usize, 2), activeSlotConst(&model).history_count);

    goBack(&model);
    try std.testing.expectEqualStrings("https://a.example", currentUrl(&model));
    try std.testing.expectEqualStrings("https://a.example", draft(&model));
    try std.testing.expect(!forwardDisabled(&model));

    goForward(&model);
    try std.testing.expectEqualStrings("https://b.example", currentUrl(&model));
    try std.testing.expect(forwardDisabled(&model));

    goBack(&model);
    setDraft(&model, "https://c.example");
    commitNavigation(&model);
    try std.testing.expectEqual(@as(usize, 2), activeSlotConst(&model).history_count);
    try std.testing.expectEqualStrings("https://c.example", currentUrl(&model));
    try std.testing.expect(forwardDisabled(&model));

    goForward(&model);
    try std.testing.expectEqualStrings("https://c.example", currentUrl(&model));
    goBack(&model);
    goBack(&model);
    try std.testing.expectEqualStrings("https://a.example", currentUrl(&model));
}

test "reload bumps the pane token without changing the URL" {
    var model: Model = .{};
    var panes: [max_sessions]WebViewPane = undefined;
    setDraft(&model, "https://example.com/ok");
    commitNavigation(&model);
    _ = webPanes(&model, &panes);
    const before = panes[0].reload_token;
    reload(&model);
    _ = webPanes(&model, &panes);
    try std.testing.expect(panes[0].reload_token != before);
    try std.testing.expectEqualStrings("https://example.com/ok", panes[0].url);
}

test "history ring shifts the oldest entry once full" {
    var model: Model = .{};
    var i: usize = 0;
    while (i < max_history + 2) : (i += 1) {
        var buf: [64]u8 = undefined;
        const url = std.fmt.bufPrint(&buf, "https://n{d}.example", .{i}) catch unreachable;
        setDraft(&model, url);
        commitNavigation(&model);
    }
    try std.testing.expectEqual(max_history, activeSlotConst(&model).history_count);
    try std.testing.expectEqual(max_history - 1, activeSlotConst(&model).history_index);
    try std.testing.expectEqualStrings("https://n33.example", currentUrl(&model));
    goBack(&model);
    try std.testing.expectEqualStrings("https://n32.example", currentUrl(&model));
}

fn expectResolved(raw: []const u8, expected: []const u8) !void {
    var dest: [open_url.max_spawn_url]u8 = undefined;
    const got = resolveAddress(raw, &dest) orelse return error.ResolveMiss;
    try std.testing.expectEqualStrings(expected, got);
}

test "resolveAddress matches Waku omnibox cases" {
    try expectResolved("https://example.com", "https://example.com");
    try expectResolved("localhost:3000", "http://localhost:3000");
    try expectResolved("127.0.0.1:8080/api", "http://127.0.0.1:8080/api");
    try expectResolved("example.com/docs?q=1", "https://example.com/docs?q=1");
    try expectResolved("about:blank", "about:blank");
    try expectResolved("rust borrow checker", "https://www.google.com/search?q=rust+borrow+checker");
    try expectResolved("what is wry", "https://www.google.com/search?q=what+is+wry");
    try expectResolved("readme", "https://www.google.com/search?q=readme");
    try expectResolved("a&b=c", "https://www.google.com/search?q=a%26b%3Dc");
    try expectResolved("  example.com/path  ", "https://example.com/path");
    try expectResolved("http://localhost:3000", "http://localhost:3000");
    try expectResolved("mailto:hi@example.com", "mailto:hi@example.com");
    try expectResolved("data:text/plain,hi", "data:text/plain,hi");
    try expectResolved("file:///tmp/a", "file:///tmp/a");
    var dest: [open_url.max_spawn_url]u8 = undefined;
    try std.testing.expect(resolveAddress("", &dest) == null);
    try std.testing.expect(resolveAddress("   ", &dest) == null);
    try std.testing.expect(resolveAddress("   \t  ", &dest) == null);
    var tiny: [8]u8 = undefined;
    try std.testing.expect(resolveAddress("example.com", &tiny) == null);
    try std.testing.expect(resolveAddress("rust borrow checker", &tiny) == null);
}

test "commitNavigation resolves localhost http and search queries" {
    var model: Model = .{};
    setDraft(&model, "localhost:3000");
    commitNavigation(&model);
    try std.testing.expectEqualStrings("http://localhost:3000", currentUrl(&model));
    try std.testing.expectEqualStrings("http://localhost:3000", draft(&model));

    setDraft(&model, "127.0.0.1:8080/api");
    commitNavigation(&model);
    try std.testing.expectEqualStrings("http://127.0.0.1:8080/api", currentUrl(&model));

    setDraft(&model, "rust borrow checker");
    commitNavigation(&model);
    try std.testing.expectEqualStrings("https://www.google.com/search?q=rust+borrow+checker", currentUrl(&model));
    try std.testing.expectEqualStrings("https://www.google.com/search?q=rust+borrow+checker", draft(&model));
}

test "search overflow is a no-op" {
    var model: Model = .{};
    var raw: [open_url.max_url]u8 = undefined;
    @memset(&raw, '&');
    setDraft(&model, &raw);
    commitNavigation(&model);
    try std.testing.expectEqual(@as(usize, 0), activeSlotConst(&model).history_count);
    try std.testing.expectEqualStrings(home_url, currentUrl(&model));
}

test "New / switch / Close host four Browser slots; toolbar targets the active slot" {
    var model: Model = .{};
    var panes: [max_sessions]WebViewPane = undefined;
    model.right_panel_open = true;
    model.right_panel_tab = .browser;

    try std.testing.expectEqual(@as(usize, 1), occupiedCount(&model));
    try std.testing.expect(can_new_browser(&model));
    try std.testing.expect(!can_close_browser(&model));
    setDraft(&model, "https://a.example");
    commitNavigation(&model);

    newSession(&model);
    try std.testing.expectEqual(@as(u8, 1), model.browser_active);
    try std.testing.expectEqual(@as(usize, 2), occupiedCount(&model));
    try std.testing.expect(can_close_browser(&model));
    try std.testing.expectEqualStrings("", draft(&model));
    try std.testing.expectEqualStrings(home_url, currentUrl(&model));
    setDraft(&model, "https://b.example");
    commitNavigation(&model);

    _ = webPanes(&model, &panes);
    try std.testing.expectEqualStrings(web_view_labels[1], panes[1].label);
    try std.testing.expectEqualStrings(web_pane_anchor, panes[1].anchor orelse "");
    try std.testing.expectEqualStrings("https://b.example", panes[1].url);
    try expectParked(panes[0]);
    try std.testing.expectEqualStrings("https://a.example", panes[0].url);
    try expectParked(panes[2]);
    try expectParked(panes[3]);

    selectSession(&model, 1);
    try std.testing.expectEqual(@as(u8, 0), model.browser_active);
    try std.testing.expectEqualStrings("https://a.example", currentUrl(&model));
    try std.testing.expectEqualStrings("https://a.example", draft(&model));
    try std.testing.expect(backDisabled(&model));
    _ = webPanes(&model, &panes);
    try std.testing.expectEqualStrings(web_pane_anchor, panes[0].anchor orelse "");
    try expectParked(panes[1]);
    try std.testing.expectEqualStrings("https://b.example", panes[1].url);

    selectSession(&model, 2);
    try std.testing.expectEqualStrings("https://b.example", currentUrl(&model));
    try std.testing.expect(backDisabled(&model));

    reload(&model);
    _ = webPanes(&model, &panes);
    try std.testing.expect(panes[1].reload_token != 0);
    try std.testing.expectEqual(@as(u64, 0), panes[0].reload_token);

    newSession(&model);
    newSession(&model);
    try std.testing.expectEqual(@as(usize, 4), occupiedCount(&model));
    try std.testing.expect(!can_new_browser(&model));
    newSession(&model);
    try std.testing.expectEqual(@as(u8, 3), model.browser_active);

    closeActive(&model);
    try std.testing.expectEqual(@as(usize, 3), occupiedCount(&model));
    try std.testing.expect(can_new_browser(&model));
    try std.testing.expect(!model.browser_slots[3].occupied);
    _ = webPanes(&model, &panes);
    try expectParked(panes[3]);
    try std.testing.expectEqualStrings(home_url, panes[3].url);

    closeActive(&model);
    closeActive(&model);
    try std.testing.expectEqual(@as(usize, 1), occupiedCount(&model));
    try std.testing.expect(!can_close_browser(&model));
    closeActive(&model);
    try std.testing.expectEqual(@as(usize, 1), occupiedCount(&model));
    try std.testing.expect(model.browser_slots[0].occupied);

    model.right_panel_tab = .files;
    _ = webPanes(&model, &panes);
    try expectParked(panes[0]);
    try expectParked(panes[1]);
}

test "restoreFromPersist rebuilds occupancy, committed URLs, and active snap" {
    var model: Model = .{};
    var panes: [max_sessions]WebViewPane = undefined;
    const slots = [_]PersistedSlot{
        .{ .occupied = true, .url = "https://a.example" },
        .{},
        .{ .occupied = true, .url = "https://c.example" },
        .{ .occupied = true, .url = "" },
    };
    restoreFromPersist(&model, &slots, 2);
    try std.testing.expectEqual(@as(usize, 3), occupiedCount(&model));
    try std.testing.expect(model.browser_slots[0].occupied);
    try std.testing.expect(!model.browser_slots[1].occupied);
    try std.testing.expect(model.browser_slots[2].occupied);
    try std.testing.expect(model.browser_slots[3].occupied);
    try std.testing.expectEqual(@as(u8, 2), model.browser_active);
    try std.testing.expectEqualStrings("https://a.example", committedUrlAt(&model, 0));
    try std.testing.expectEqualStrings("https://c.example", currentUrl(&model));
    try std.testing.expectEqualStrings("", committedUrlAt(&model, 3));
    try std.testing.expect(backDisabled(&model));
    try std.testing.expectEqual(@as(u64, 0), model.browser_slots[0].reload_token);

    model.right_panel_open = true;
    model.right_panel_tab = .browser;
    _ = webPanes(&model, &panes);
    try expectParked(panes[0]);
    try std.testing.expectEqualStrings("https://a.example", panes[0].url);
    try expectParked(panes[1]);
    try std.testing.expectEqualStrings(web_pane_anchor, panes[2].anchor orelse "");
    try std.testing.expectEqualStrings("https://c.example", panes[2].url);
    try expectParked(panes[3]);
    try std.testing.expectEqualStrings(home_url, panes[3].url);

    restoreFromPersist(&model, &[_]PersistedSlot{}, 3);
    try std.testing.expectEqual(@as(usize, 1), occupiedCount(&model));
    try std.testing.expect(model.browser_slots[0].occupied);
    try std.testing.expectEqual(@as(u8, 0), model.browser_active);
}

test "CONTEXT and README describe first-cut Browser multi-session inside the tab" {
    const context = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "CONTEXT.md", std.testing.allocator, .limited(512 * 1024));
    defer std.testing.allocator.free(context);
    const readme = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "README.md", std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(readme);
    try std.testing.expect(std.mem.indexOf(u8, context, "First-cut multi-session inside the Browser tab") != null);
    try std.testing.expect(std.mem.indexOf(u8, context, "browser-web-0") != null);
    try std.testing.expect(std.mem.indexOf(u8, context, "not Waku surface UUID tabs") != null);
    try std.testing.expect(std.mem.indexOf(u8, context, "occupied slot URLs") != null);
    try std.testing.expect(std.mem.indexOf(u8, context, "Not Waku tabs / DevTools / multi-session.") == null);
    const browser_cut = std.mem.indexOf(u8, readme, "First-cut embedded Browser tab") orelse return error.MissingBrowserReadme;
    const window = readme[browser_cut..@min(readme.len, browser_cut + 240)];
    try std.testing.expect(std.mem.indexOf(u8, window, "up to 4 sessions") != null);
    try std.testing.expect(std.mem.indexOf(u8, window, "occupied URLs persist") != null);
    try std.testing.expect(std.mem.indexOf(u8, readme, "not … multi-session") == null);
}
