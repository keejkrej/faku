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
//! Occupied chips prefer a runtime-only `page_title` (Faku-side one-shot
//! HTML `<title>` fetch on committed `http://` / `https://`; Native
//! `WebViewPane` / `web_panes` still expose only label/anchor/url/
//! `reload_token` — no document-title callback), else host, else
//! truncated Waku `display_url`, from the committed history URL. Empty
//! history keeps occupancy-order `1`..`4`. Each occupied slot keeps its
//! own address-bar draft, committed history ring, history index, and
//! `reload_token`. Cmd/Ctrl-Shift-R Hard Reload (chord and toolbar) is
//! a Faku-side `about:blank` hop plus `reload_token` on the next update
//! tick (Native `WebViewPane` documents only `url` + `reload_token`;
//! not Waku cache-clear; no hard-reload flag). First-cut Stop loading
//! (toolbar + Esc when the address field is not active) is a Faku-side
//! loading-guess after navigate / reload / Hard Reload start, then
//! restore the previous committed history URL or `about:blank` (Native
//! has no loading/stop callback; guess clears on Stop or ~12s). Inactive occupied slots
//! park at 1×1 with
//! `anchor = null` so they do not overlay Files/Diff/Terminal but keep
//! the webview process/state. Unopened slots stay parked at the home
//! placeholder. Hidden Browser parks **all** panes the same way.
//! Empty history (`history_count == 0`, Waku `has_page` / missing
//! `current_url`) parks the **active** slot the same way even while the
//! Browser tab is showing: `home_url` stays the parked scene URL so the
//! process stays alive, but Faku paints a Native start page instead of
//! snapping to `browser-pane`. First Navigate/Enter that commits history
//! snaps the pane and hides the start page.
//!
//! Pane URL is the committed history entry, never the address-bar draft.
//! `sessions.json` extras persist the **active** slot's address draft
//! (`browser_url`) plus occupied slot committed URLs (`browser_slots`),
//! history rings (`browser_histories`), and `browser_active` as last-live
//! cold-start fallback. Session switch / New Task / remove restore
//! occupancy + histories + active from the in-memory
//! `right_panel_session` stash (`capturePersisted` / `restoreFromPersist`;
//! missing → `default_slots`). `reload_token`, Hard Reload's
//! pending blank hop, Stop loading's loading-guess / blank hop, and
//! `page_title` stay runtime-only (titles re-fetch on restore when a
//! committed http(s) URL is present; not `sessions.json`). Empty
//! history still parks on the
//! scene placeholder `https://example.com` and does not show it.
//! Enter/Navigate uses Safari/Waku omnibox resolve (explicit schemes,
//! localhost/IPv4 → `http`, host-like → `https`, else Google search).
//! The address field hides a leading `https://` (Waku `display_url`);
//! `http://` and other schemes stay visible. History, pane URLs, and
//! `browser_slots` persist stay full. A muted lock/globe beside the
//! field follows the committed pane URL (Waku `is_secure_url`), not
//! the in-progress draft and not `home_url`. Empty history is globe.
//! Native has no text-field icon helper.
//!
//! Native `applyWebPane` keeps the last frame when the anchor is missing
//! or width/height < 1 (`ui_app.zig`). Public `WebViewPane` has no
//! `visible` field. Parking uses `anchor = null` and a 1×1 frame at
//! (0,0).

const std = @import("std");
const builtin = @import("builtin");
const native_sdk = @import("native_sdk");
const main = @import("main.zig");
const model_mod = @import("model.zig");
const open_url = @import("open_url.zig");
const litellm_rates = @import("litellm_rates.zig");

const Effects = main.Effects;

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
/// Occupancy-order chip labels (`1`..`n`) when a slot has no committed
/// URL. Matching Terminal's empty-session chips.
pub const slot_labels = [_][]const u8{ "1", "2", "3", "4" };
/// Visible chip prefix before ellipsis. Hosts usually fit; long
/// `page_title` / `display_url` fallbacks truncate for chrome. Persist
/// still stores the full committed URL (not the title).
pub const chip_label_max_chars: usize = 24;
const chip_label_ellipsis = "…";
/// Stored `page_title` cap before chip truncate. Runtime-only.
pub const page_title_max: usize = 256;
/// Bounded HTML window for the title parse. Overflow keeps whatever
/// arrived and fail-closes on a parse miss.
pub const page_title_html_max: usize = 16 * 1024;
/// One-shot curl title fetch. Distinct from litellm (650) and pty
/// 700..703. Incremented per spawn from `page_title_key_first`; wraps
/// before 700 so the band cannot collide with `<terminal>`.
pub const page_title_key_first: u64 = 660;
pub const page_title_key_last: u64 = 699;
pub const page_title_max_time = "8";
pub const page_title_max_filesize = "65536";
pub const page_title_accept_header = "Accept: text/html";
const page_title_argv_len: usize = 9;
/// Markup semantics label the **active** pane snaps to
/// (`<column label="browser-pane">`).
pub const web_pane_anchor = "browser-pane";
/// Scene placeholder and parked empty-history pane URL. Empty history
/// does not treat this as a committed page (no snap, globe not lock).
pub const home_url = "https://example.com";
/// Documented Native pane URL for the Hard Reload blank hop and for
/// Stop loading when no previous committed URL exists. Not pushed
/// onto the user history ring.
pub const blank_url = "about:blank";
/// Workbench `max_history` ring. Occupied rings persist; `reload_token`,
/// Hard Reload's pending blank hop, and Stop loading's loading-guess /
/// blank hop stay runtime-only.
pub const max_history = 32;
/// First-cut Stop loading window. Native never reports load start/end,
/// so navigate / reload / Hard Reload start a Faku-side guess. Cleared
/// on Stop or `maybeClearLoadingGuess` after this many ms of `now_ms`.
pub const loading_guess_ms: i64 = 12_000;
/// Parking frame: positive size so `applyWebPane` does not keep the last
/// content-sized snapshot when the Browser tab is hidden or the slot is
/// inactive.
pub const parked_frame = geometry.RectF.init(0, 0, 1, 1);

/// Per-slot Browser state. Occupied slots keep a live scene webview.
/// Occupancy, the committed pane URL, history rings, and the active
/// index persist on `sessions.json` extras (`browser_slots` /
/// `browser_histories` / `browser_active`) as last-live cold-start;
/// session switch restores them from `right_panel_session`. The active
/// address draft still persists as `browser_url`. `reload_token`,
/// Hard Reload's pending blank hop, Stop loading's loading-guess /
/// blank hop, and `page_title` stay runtime-only.
pub const Slot = struct {
    occupied: bool = false,
    url_buffer: canvas.TextBuffer(open_url.max_url) = .{},
    history: [max_history]canvas.TextBuffer(open_url.max_spawn_url) = [_]canvas.TextBuffer(open_url.max_spawn_url){.{}} ** max_history,
    history_count: usize = 0,
    history_index: usize = 0,
    reload_token: u64 = 0,
    /// Runtime-only: next `webPanes` emits `blank_url` so Native
    /// navigates away; `maybeFinishHardReload` on the following update
    /// tick restores the committed URL and bumps `reload_token`.
    hard_reload_pending: bool = false,
    /// Runtime-only: `now_ms` deadline for the post-navigate loading
    /// guess. 0 is inactive. Not persisted.
    loading_guess_until_ms: i64 = 0,
    /// Runtime-only: Stop with no previous history URL emits `blank_url`
    /// this tick; `maybeFinishStopBlank` on the next update tick clears
    /// the page (empty history, occupancy kept).
    stop_blank_pending: bool = false,
    /// Runtime-only chip `page_title`. Not `sessions.json`.
    page_title: canvas.TextBuffer(page_title_max) = .{},
    /// In-flight curl key for this slot. 0 is none. Unique per spawn
    /// so a stale exit cannot match a newer commit.
    page_title_pending_key: u64 = 0,
    /// Bumped on every committed-URL change for this slot.
    page_title_generation: u64 = 0,
    /// Generation copied at spawn time. Stale exits ignore a mismatch.
    page_title_fetch_generation: u64 = 0,
    /// URL this spawn was keyed to. Stale exits ignore a mismatch.
    page_title_fetch_url: canvas.TextBuffer(open_url.max_spawn_url) = .{},
    page_title_html_storage: [page_title_html_max]u8 = [_]u8{0} ** page_title_html_max,
    page_title_html_len: usize = 0,
    page_title_binary: bool = false,
    /// Set when a committed http(s) URL lands; `startTitleFetches`
    /// drains it. Not an idle-tick poll.
    page_title_fetch_needed: bool = false,
};

pub const BrowserSessionRow = struct {
    id: u32,
    label: []const u8,
    selected: bool,
};

/// Occupied slot persist row. `url` is the committed history entry
/// (empty when the slot has never navigated) and stays the
/// `browser_slots` tip string. Occupied rings go on `browser_histories`
/// (`urls` + `index`). Unoccupied slots are `occupied = false` and encode
/// as JSON `null`. `history_present` is false for legacy tip-only rows.
pub const PersistedSlot = struct {
    occupied: bool = false,
    url: []const u8 = "",
    history_urls: [max_history][]const u8 = [_][]const u8{""} ** max_history,
    history_count: usize = 0,
    history_index: usize = 0,
    history_present: bool = false,
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

/// Occupied chips with stable 1-based slot ids. Label prefers a
/// non-empty runtime `page_title`, else host, else Waku `display_url`,
/// from the committed URL (truncated); empty history keeps
/// occupancy-order `1`..`n`. Native `WebViewPane` has no title callback.
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
            .label = allocChipLabel(arena, slot.page_title.text(), committedUrlAt(model, i), n),
            .selected = i == active,
        };
        n += 1;
    }
    return out[0..n];
}

/// Host when the committed URL has a usable hostname; otherwise Waku
/// `display_url`. Empty committed stays empty so chips keep `1`..`n`.
/// Same source as lock/globe / persist (`committedUrlAt`), never the
/// live home placeholder. Chip preference puts non-empty `page_title`
/// ahead of this fallback.
pub fn chipLabelSource(url: []const u8) []const u8 {
    if (url.len == 0) return "";
    if (hostOfUrl(url)) |host| return host;
    return displayUrl(url);
}

fn allocChipLabel(arena: std.mem.Allocator, page_title: []const u8, committed: []const u8, occupancy: usize) []const u8 {
    const fallback = slot_labels[occupancy];
    const source = if (page_title.len > 0) page_title else chipLabelSource(committed);
    if (source.len == 0) return fallback;
    return allocTruncatedChipLabel(arena, source) catch fallback;
}

fn allocTruncatedChipLabel(arena: std.mem.Allocator, text: []const u8) error{OutOfMemory}![]const u8 {
    if (text.len <= chip_label_max_chars) return arena.dupe(u8, text);
    const prefix = utf8Prefix(text, chip_label_max_chars);
    return std.fmt.allocPrint(arena, "{s}{s}", .{ prefix, chip_label_ellipsis });
}

fn utf8Prefix(text: []const u8, max_bytes: usize) []const u8 {
    if (text.len <= max_bytes) return text;
    var end = max_bytes;
    while (end > 0 and (text[end] & 0xC0) == 0x80) end -= 1;
    return text[0..end];
}

pub fn isPageTitleKey(key: u64) bool {
    return key >= page_title_key_first and key <= page_title_key_last;
}

pub fn isPendingTitleKey(model: *const Model, key: u64) bool {
    if (!isPageTitleKey(key)) return false;
    for (model.browser_slots) |slot| {
        if (slot.page_title_pending_key == key) return true;
    }
    return false;
}

fn slotForPendingTitleKey(model: *Model, key: u64) ?*Slot {
    if (!isPageTitleKey(key)) return null;
    for (&model.browser_slots) |*slot| {
        if (slot.page_title_pending_key == key) return slot;
    }
    return null;
}

fn titleFetchEligible(url: []const u8) bool {
    if (url.len == 0) return false;
    if (std.ascii.eqlIgnoreCase(url, blank_url)) return false;
    return open_url.isHttpUrl(url);
}

fn curlBin() []const u8 {
    return litellm_rates.curlBin();
}

pub fn argvFor(url: []const u8, buf: *[page_title_argv_len][]const u8) []const []const u8 {
    return argvForBin(curlBin(), url, buf);
}

pub fn argvForBin(bin: []const u8, url: []const u8, buf: *[page_title_argv_len][]const u8) []const []const u8 {
    buf[0] = bin;
    buf[1] = "-fsSL";
    buf[2] = "--max-time";
    buf[3] = page_title_max_time;
    buf[4] = "--max-filesize";
    buf[5] = page_title_max_filesize;
    buf[6] = "-H";
    buf[7] = page_title_accept_header;
    buf[8] = url;
    return buf[0..page_title_argv_len];
}

pub fn isTitleFetchArgv(argv: []const []const u8) bool {
    if (argv.len != page_title_argv_len) return false;
    const bin_ok = std.mem.eql(u8, argv[0], litellm_rates.unix_curl_bin) or
        std.mem.eql(u8, argv[0], litellm_rates.path_curl_bin) or
        std.mem.eql(u8, argv[0], litellm_rates.windows_curl_bin);
    if (!bin_ok) return false;
    if (!std.mem.eql(u8, argv[1], "-fsSL")) return false;
    if (!std.mem.eql(u8, argv[2], "--max-time")) return false;
    if (!std.mem.eql(u8, argv[3], page_title_max_time)) return false;
    if (!std.mem.eql(u8, argv[4], "--max-filesize")) return false;
    if (!std.mem.eql(u8, argv[5], page_title_max_filesize)) return false;
    if (!std.mem.eql(u8, argv[6], "-H")) return false;
    if (!std.mem.eql(u8, argv[7], page_title_accept_header)) return false;
    return argv[8].len > 0;
}

fn clearPageTitle(slot: *Slot) void {
    slot.page_title.clear();
}

fn clearTitleFetchBuffer(slot: *Slot) void {
    slot.page_title_html_len = 0;
    slot.page_title_binary = false;
}

fn noteCommittedUrlChanged(slot: *Slot) void {
    clearPageTitle(slot);
    clearTitleFetchBuffer(slot);
    slot.page_title_generation +%= 1;
    slot.page_title_fetch_needed = true;
}

fn cancelTitleFetch(slot: *Slot, fx: *Effects) void {
    if (slot.page_title_pending_key == 0) return;
    fx.cancel(slot.page_title_pending_key);
    slot.page_title_pending_key = 0;
}

pub fn cancelAllTitleFetches(model: *Model, fx: *Effects) void {
    for (&model.browser_slots) |*slot| {
        cancelTitleFetch(slot, fx);
    }
}

pub fn cancelTitleFetchAt(model: *Model, fx: *Effects, index: usize) void {
    if (index >= max_sessions) return;
    cancelTitleFetch(slotPtr(model, index), fx);
}

fn nextTitleKey(model: *Model) u64 {
    var key = model.next_page_title_key;
    var n: u64 = 0;
    while (n <= page_title_key_last - page_title_key_first) : (n += 1) {
        if (key < page_title_key_first or key > page_title_key_last) {
            key = page_title_key_first;
        }
        var taken = false;
        for (model.browser_slots) |slot| {
            if (slot.page_title_pending_key == key) {
                taken = true;
                break;
            }
        }
        const candidate = key;
        key += 1;
        if (key > page_title_key_last) key = page_title_key_first;
        if (!taken) {
            model.next_page_title_key = key;
            return candidate;
        }
    }
    model.next_page_title_key = page_title_key_first;
    return page_title_key_first;
}

fn startTitleFetchAt(model: *Model, fx: *Effects, index: usize) void {
    const slot = slotPtr(model, index);
    if (!slot.occupied) {
        cancelTitleFetch(slot, fx);
        slot.page_title_fetch_needed = false;
        return;
    }
    const url = committedUrlAt(model, index);
    slot.page_title_fetch_needed = false;
    if (!titleFetchEligible(url)) {
        cancelTitleFetch(slot, fx);
        clearPageTitle(slot);
        clearTitleFetchBuffer(slot);
        return;
    }
    if (slot.page_title_pending_key != 0 and
        slot.page_title_fetch_generation == slot.page_title_generation and
        std.mem.eql(u8, slot.page_title_fetch_url.text(), url))
    {
        return;
    }
    cancelTitleFetch(slot, fx);
    clearTitleFetchBuffer(slot);
    slot.page_title_fetch_url.set(url);
    const key = nextTitleKey(model);
    slot.page_title_pending_key = key;
    slot.page_title_fetch_generation = slot.page_title_generation;
    var argv_buf: [page_title_argv_len][]const u8 = undefined;
    fx.spawn(.{
        .key = key,
        .argv = argvFor(slot.page_title_fetch_url.text(), &argv_buf),
        .max_line_bytes = page_title_html_max,
        .on_line = Effects.lineMsg(.fx_line),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
}

/// Drain `page_title_fetch_needed` on occupied slots. Fire on commit /
/// restore only — not an idle chrome-tick poll.
pub fn startTitleFetches(model: *Model, fx: *Effects) void {
    for (0..max_sessions) |i| {
        if (!model.browser_slots[i].page_title_fetch_needed) continue;
        startTitleFetchAt(model, fx, i);
    }
}

pub fn applyLine(model: *Model, line: native_sdk.EffectLine) void {
    const slot = slotForPendingTitleKey(model, line.key) orelse return;
    if (slot.page_title_fetch_generation != slot.page_title_generation) return;
    if (slot.page_title_binary) return;
    const chunk = line.line;
    if (std.mem.indexOfScalar(u8, chunk, 0) != null) {
        slot.page_title_binary = true;
        slot.page_title_html_len = 0;
        return;
    }
    if (slot.page_title_html_len >= page_title_html_max) return;
    if (slot.page_title_html_len > 0) {
        slot.page_title_html_storage[slot.page_title_html_len] = '\n';
        slot.page_title_html_len += 1;
        if (slot.page_title_html_len >= page_title_html_max) return;
    }
    const room = page_title_html_max - slot.page_title_html_len;
    const take = @min(room, chunk.len);
    @memcpy(slot.page_title_html_storage[slot.page_title_html_len .. slot.page_title_html_len + take], chunk[0..take]);
    slot.page_title_html_len += take;
}

pub fn handleExit(model: *Model, exit: native_sdk.EffectExit) void {
    const slot = slotForPendingTitleKey(model, exit.key) orelse return;
    const gen = slot.page_title_fetch_generation;
    const html = slot.page_title_html_storage[0..slot.page_title_html_len];
    const binary = slot.page_title_binary;
    const fetch_url = slot.page_title_fetch_url.text();
    var fetch_buf: [open_url.max_spawn_url]u8 = undefined;
    const fetch_len = @min(fetch_url.len, fetch_buf.len);
    @memcpy(fetch_buf[0..fetch_len], fetch_url[0..fetch_len]);
    const keyed_url = fetch_buf[0..fetch_len];

    slot.page_title_pending_key = 0;
    clearTitleFetchBuffer(slot);

    if (slot.page_title_generation != gen) return;
    if (!slot.occupied) return;
    const committed = committedText(slot);
    if (!std.mem.eql(u8, committed, keyed_url)) return;
    if (exit.reason != .exited or exit.code != 0) return;
    if (binary) return;
    var decoded: [page_title_max]u8 = undefined;
    const title = extractTitle(html, &decoded);
    if (title.len == 0) return;
    slot.page_title.set(title);
}

/// First usable `<title>…</title>` (case-insensitive). Decodes trivial
/// entities, collapses ASCII whitespace, caps to `dest`. Empty on
/// binary / missing / parse miss.
pub fn extractTitle(html: []const u8, dest: []u8) []const u8 {
    if (dest.len == 0 or html.len == 0) return dest[0..0];
    if (std.mem.indexOfScalar(u8, html, 0) != null) return dest[0..0];
    const inner = titleInner(html) orelse return dest[0..0];
    return decodeTitleInner(inner, dest);
}

fn titleInner(html: []const u8) ?[]const u8 {
    const open_end = findTitleOpenEnd(html) orelse return null;
    const rest = html[open_end..];
    const close = findIgnoreCase(rest, "</title>") orelse return null;
    return rest[0..close];
}

fn findTitleOpenEnd(html: []const u8) ?usize {
    var i: usize = 0;
    while (i < html.len) : (i += 1) {
        if (html[i] != '<') continue;
        const rest = html[i + 1 ..];
        if (!startsWithIgnoreCase(rest, "title")) continue;
        if (rest.len < 5) return null;
        const after_name = rest[5..];
        if (after_name.len == 0) return null;
        const next = after_name[0];
        if (next != '>' and !std.ascii.isWhitespace(next) and next != '/') continue;
        const gt = std.mem.indexOfScalar(u8, rest, '>') orelse return null;
        return i + 1 + gt + 1;
    }
    return null;
}

fn findIgnoreCase(hay: []const u8, needle: []const u8) ?usize {
    if (needle.len == 0 or hay.len < needle.len) return null;
    var i: usize = 0;
    while (i + needle.len <= hay.len) : (i += 1) {
        if (std.ascii.eqlIgnoreCase(hay[i .. i + needle.len], needle)) return i;
    }
    return null;
}

fn startsWithIgnoreCase(text: []const u8, prefix: []const u8) bool {
    if (text.len < prefix.len) return false;
    return std.ascii.eqlIgnoreCase(text[0..prefix.len], prefix);
}

fn decodeTitleInner(inner: []const u8, dest: []u8) []const u8 {
    var out: usize = 0;
    var i: usize = 0;
    var pending_space = false;
    var emitted = false;
    while (i < inner.len and out < dest.len) {
        if (inner[i] == 0) return dest[0..0];
        if (inner[i] == '&') {
            var ent_buf: [4]u8 = undefined;
            if (decodeEntity(inner[i..], &ent_buf)) |ent| {
                i += ent.consumed;
                const bytes = ent_buf[0..ent.len];
                var b: usize = 0;
                while (b < bytes.len and out < dest.len) : (b += 1) {
                    if (emitTitleByte(bytes[b], dest, &out, &pending_space, &emitted)) continue;
                    return dest[0..0];
                }
                continue;
            }
        }
        const c = inner[i];
        i += 1;
        if (!emitTitleByte(c, dest, &out, &pending_space, &emitted)) return dest[0..0];
    }
    return utf8Prefix(dest[0..out], out);
}

fn emitTitleByte(c: u8, dest: []u8, out: *usize, pending_space: *bool, emitted: *bool) bool {
    if (c == 0) return false;
    if (c == ' ' or c == '\t' or c == '\n' or c == '\r' or c == 0x0c) {
        if (emitted.*) pending_space.* = true;
        return true;
    }
    if (pending_space.* and out.* < dest.len) {
        dest[out.*] = ' ';
        out.* += 1;
        pending_space.* = false;
        if (out.* >= dest.len) return true;
    }
    if (out.* >= dest.len) return true;
    dest[out.*] = c;
    out.* += 1;
    emitted.* = true;
    pending_space.* = false;
    return true;
}

const DecodedEntity = struct {
    len: usize,
    consumed: usize,
};

fn decodeEntity(text: []const u8, dest: *[4]u8) ?DecodedEntity {
    if (text.len < 3 or text[0] != '&') return null;
    if (namedEntity(text, dest)) |ent| return ent;
    if (text[1] != '#') return null;
    if (text.len >= 4 and (text[2] == 'x' or text[2] == 'X')) {
        return numericEntity(text, 3, 16, dest);
    }
    return numericEntity(text, 2, 10, dest);
}

fn namedEntity(text: []const u8, dest: *[4]u8) ?DecodedEntity {
    const pairs = [_]struct { name: []const u8, ch: u8 }{
        .{ .name = "&amp;", .ch = '&' },
        .{ .name = "&lt;", .ch = '<' },
        .{ .name = "&gt;", .ch = '>' },
        .{ .name = "&quot;", .ch = '"' },
        .{ .name = "&#39;", .ch = '\'' },
        .{ .name = "&apos;", .ch = '\'' },
    };
    for (pairs) |pair| {
        if (text.len >= pair.name.len and std.mem.eql(u8, text[0..pair.name.len], pair.name)) {
            dest[0] = pair.ch;
            return .{ .len = 1, .consumed = pair.name.len };
        }
    }
    return null;
}

fn digitValue(c: u8, base: u8) ?u32 {
    const d: u32 = switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        'A'...'F' => c - 'A' + 10,
        else => return null,
    };
    if (d >= base) return null;
    return d;
}

fn numericEntity(text: []const u8, start: usize, base: u8, dest: *[4]u8) ?DecodedEntity {
    if (start >= text.len) return null;
    var i = start;
    var value: u32 = 0;
    var digits: usize = 0;
    while (i < text.len) : (i += 1) {
        const c = text[i];
        if (c == ';') break;
        const digit = digitValue(c, base) orelse return null;
        value = value *% @as(u32, base) + digit;
        if (value > 0x10FFFF) return null;
        digits += 1;
        if (digits > 8) return null;
    }
    if (digits == 0 or i >= text.len or text[i] != ';') return null;
    if (value == 0) return null;
    const len = std.unicode.utf8Encode(@intCast(value), dest) catch return null;
    return .{ .len = len, .consumed = i + 1 };
}

/// Authority hostname without userinfo or port. Opaque schemes
/// (`about:`, `mailto:`, `data:`) and `file:///path` have no usable
/// host. IPv6 `[::1]` keeps the inner address.
fn hostOfUrl(url: []const u8) ?[]const u8 {
    const sep = std.mem.indexOf(u8, url, "://") orelse return null;
    const rest = url[sep + 3 ..];
    if (rest.len == 0) return null;
    const authority = authorityOf(rest);
    if (authority.len == 0) return null;
    const hostport = if (std.mem.lastIndexOfScalar(u8, authority, '@')) |at|
        authority[at + 1 ..]
    else
        authority;
    if (hostport.len == 0) return null;
    if (hostport[0] == '[') {
        const close = std.mem.indexOfScalar(u8, hostport, ']') orelse return null;
        const host = hostport[1..close];
        return if (host.len == 0) null else host;
    }
    const parsed = splitHostPort(hostport) orelse return null;
    return if (parsed.host.len == 0) null else parsed.host;
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

/// Safari/Waku address display (egoist/waku `src/browser.rs`
/// `display_url`). Hide a leading `https://` the way Safari does;
/// leave `http://` and every other scheme/path visible. Empty stays
/// empty. Companion lock chrome is `isSecureUrl` on the committed URL.
pub fn displayUrl(url: []const u8) []const u8 {
    const https_prefix = "https://";
    if (std.mem.startsWith(u8, url, https_prefix)) return url[https_prefix.len..];
    return url;
}

/// Safari/Waku lock chrome (egoist/waku `src/browser.rs`
/// `is_secure_url`). True iff the URL starts with `https://`. Empty /
/// `http` / other schemes are false. Case-sensitive, like Waku.
pub fn isSecureUrl(url: []const u8) bool {
    return std.mem.startsWith(u8, url, "https://");
}

fn committedText(slot: *const Slot) []const u8 {
    if (slot.history_count == 0) return "";
    return slot.history[slot.history_index].text();
}

fn syncDraftFromCommitted(slot: *Slot) void {
    slot.url_buffer.set(displayUrl(committedText(slot)));
}

/// Echo the committed history URL into the active slot's address draft
/// (Waku `restore_address` / `BrowserAddressCancel`). Empty history
/// clears the draft the same way `syncDraftFromCommitted` does.
pub fn restoreAddressFromCommitted(model: *Model) void {
    syncDraftFromCommitted(activeSlot(model));
}

fn currentUrlAt(model: *const Model, index: usize) []const u8 {
    const slot = slotConst(model, index);
    if (!slot.occupied or slot.history_count == 0) return home_url;
    return slot.history[slot.history_index].text();
}

/// Committed pane URL for persist. Empty when the slot is unoccupied
/// or has never navigated (the parked pane still uses `home_url`).
pub fn committedUrlAt(model: *const Model, index: usize) []const u8 {
    const slot = slotConst(model, index);
    if (!slot.occupied or slot.history_count == 0) return "";
    return slot.history[slot.history_index].text();
}

pub fn capturePersisted(model: *const Model, out: *[max_sessions]PersistedSlot) void {
    for (0..max_sessions) |i| {
        const slot = slotConst(model, i);
        if (!slot.occupied) {
            out[i] = .{};
            continue;
        }
        var persisted = PersistedSlot{
            .occupied = true,
            .url = committedUrlAt(model, i),
            .history_present = true,
        };
        const count = @min(slot.history_count, max_history);
        var j: usize = 0;
        while (j < count) : (j += 1) {
            persisted.history_urls[j] = slot.history[j].text();
        }
        persisted.history_count = count;
        persisted.history_index = clampedHistoryIndex(count, slot.history_index);
        out[i] = persisted;
    }
}

/// Rebuild occupancy, history rings + index when present, otherwise a
/// single-entry history from each committed tip. Does not restore
/// `reload_token`, a pending Hard Reload hop, Stop loading's
/// loading-guess / blank hop, or `page_title`. Occupied http(s) tips
/// arm a runtime title re-fetch (`page_title_fetch_needed`). Zero
/// occupied slots keep today's slot-0 session.
pub fn restoreFromPersist(model: *Model, slots: []const PersistedSlot, active: u8) void {
    model.browser_slots = [_]Slot{.{}} ** max_sessions;
    const n = @min(slots.len, max_sessions);
    var any = false;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (!slots[i].occupied) continue;
        any = true;
        restoreOccupied(&model.browser_slots[i], slots[i]);
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

fn clampedHistoryIndex(count: usize, index: usize) usize {
    if (count == 0) return 0;
    return @min(index, count - 1);
}

fn restoreOccupied(slot: *Slot, persisted: PersistedSlot) void {
    slot.* = .{ .occupied = true };
    if (persisted.history_present) {
        restoreHistory(slot, persisted);
        return;
    }
    if (persisted.url.len == 0) return;
    slot.history[0].set(persisted.url);
    slot.history_count = 1;
    slot.history_index = 0;
    syncDraftFromCommitted(slot);
    armTitleFetchIfEligible(slot);
}

fn restoreHistory(slot: *Slot, persisted: PersistedSlot) void {
    const count = @min(persisted.history_count, max_history);
    var n: usize = 0;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const url = persisted.history_urls[i];
        if (url.len == 0 or url.len > open_url.max_spawn_url) continue;
        slot.history[n].set(url);
        n += 1;
    }
    slot.history_count = n;
    slot.history_index = clampedHistoryIndex(n, persisted.history_index);
    if (n == 0) return;
    syncDraftFromCommitted(slot);
    armTitleFetchIfEligible(slot);
}

fn armTitleFetchIfEligible(slot: *Slot) void {
    if (titleFetchEligible(committedText(slot))) {
        noteCommittedUrlChanged(slot);
    }
}

pub fn currentUrl(model: *const Model) []const u8 {
    return currentUrlAt(model, activeIndex(model));
}

/// Waku `has_page`: the active slot has a committed history entry.
/// Empty history is not a page (`home_url` is only the parked scene).
pub fn hasPage(model: *const Model) bool {
    return activeSlotConst(model).history_count > 0;
}

/// Native start page in the Browser tab body: tab is showing and the
/// active occupied slot has never navigated. Inactive empty slots stay
/// parked without this chrome.
pub fn showingStartPage(model: *const Model) bool {
    return model.right_panel_showing_browser() and !hasPage(model);
}

/// Active slot's committed URL security (Waku `is_secure_url`). Empty
/// history is not secure (globe), even though the parked scene URL is
/// `home_url`. Not the in-progress address draft.
pub fn urlSecure(model: *const Model) bool {
    return isSecureUrl(committedUrlAt(model, activeIndex(model)));
}

pub fn backDisabled(model: *const Model) bool {
    const slot = activeSlotConst(model);
    return slot.history_count == 0 or slot.history_index == 0;
}

pub fn forwardDisabled(model: *const Model) bool {
    const slot = activeSlotConst(model);
    return slot.history_count == 0 or slot.history_index + 1 >= slot.history_count;
}

pub fn reloadDisabled(model: *const Model) bool {
    return !hasPage(model);
}

/// Stop loading toolbar: same has-page gate as Reload, plus the
/// loading-guess must still be live (so Esc cannot blank a settled
/// page after the guess window).
pub fn stopLoadingDisabled(model: *const Model) bool {
    return reloadDisabled(model) or !loadingGuessActive(model);
}

/// Active slot is inside the post-navigate / reload / Hard Reload
/// loading-guess window. `now_ms == 0` (unit tests that never stamp
/// the clock) treats a non-zero deadline as still live.
pub fn loadingGuessActive(model: *const Model) bool {
    const until = activeSlotConst(model).loading_guess_until_ms;
    if (until == 0) return false;
    if (model.now_ms <= 0) return true;
    return model.now_ms < until;
}

fn markLoadingGuess(model: *Model) void {
    const start: i64 = if (model.now_ms <= 0) 1 else model.now_ms;
    activeSlot(model).loading_guess_until_ms = start + loading_guess_ms;
}

fn clearLoadingGuess(slot: *Slot) void {
    slot.loading_guess_until_ms = 0;
}

/// Drop expired loading-guess deadlines. Piggybacks `now_ms` / the
/// update tick (Native has no load callback or dedicated timer).
pub fn maybeClearLoadingGuess(model: *Model) void {
    if (model.now_ms <= 0) return;
    for (&model.browser_slots) |*slot| {
        if (slot.loading_guess_until_ms == 0) continue;
        if (model.now_ms >= slot.loading_guess_until_ms) {
            slot.loading_guess_until_ms = 0;
        }
    }
}

pub fn openDisabled(model: *const Model) bool {
    return !hasPage(model);
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
    const switching = activeIndex(model) != index;
    model.browser_active = @intCast(index);
    if (switching) syncDraftFromCommitted(activeSlot(model));
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
    syncDraftFromCommitted(live);
    markLoadingGuess(model);
    noteCommittedUrlChanged(live);
}

pub fn goBack(model: *Model) void {
    const slot = activeSlot(model);
    if (slot.history_index == 0) return;
    slot.history_index -= 1;
    syncDraftFromCommitted(slot);
    noteCommittedUrlChanged(slot);
}

pub fn goForward(model: *Model) void {
    const slot = activeSlot(model);
    if (slot.history_count == 0 or slot.history_index + 1 >= slot.history_count) return;
    slot.history_index += 1;
    syncDraftFromCommitted(slot);
    noteCommittedUrlChanged(slot);
}

pub fn reload(model: *Model) void {
    if (!hasPage(model)) return;
    activeSlot(model).reload_token +%= 1;
    markLoadingGuess(model);
}

/// Hard Reload first-cut: documented Native `url` + `reload_token`
/// only. Capture stays on the history ring; the next `webPanes`
/// emits `about:blank` so Native navigates. `maybeFinishHardReload` on
/// the following update tick restores that URL and bumps
/// `reload_token`. No-op without a committed page (same as `reload`).
pub fn hardReload(model: *Model) void {
    if (!hasPage(model)) return;
    const slot = activeSlot(model);
    slot.hard_reload_pending = true;
    markLoadingGuess(model);
}

/// First-cut Stop loading: Native has no stop callback, so abandon
/// the in-flight navigation with a URL change. Previous committed
/// history URL when `history_index > 0` (ring kept); else `about:blank`
/// this tick and empty history on the next (`maybeFinishStopBlank`).
/// Clears the loading-guess. No-op when the guess is already idle.
pub fn stopLoading(model: *Model) void {
    if (!loadingGuessActive(model)) return;
    const slot = activeSlot(model);
    slot.hard_reload_pending = false;
    clearLoadingGuess(slot);
    if (!hasPage(model)) return;
    if (slot.history_index > 0) {
        goBack(model);
        return;
    }
    slot.stop_blank_pending = true;
}

/// Second tick of first-page Stop: after Native has applied
/// `about:blank`, drop the abandoned history entry. Occupancy stays
/// so the slot returns to the empty-history start page. Called at
/// the start of `update` so a same-tick blank→clear cannot collapse.
pub fn maybeFinishStopBlank(model: *Model) bool {
    var cleared = false;
    for (&model.browser_slots) |*slot| {
        if (!slot.stop_blank_pending) continue;
        slot.stop_blank_pending = false;
        slot.history_count = 0;
        slot.history_index = 0;
        slot.url_buffer.clear();
        clearPageTitle(slot);
        clearTitleFetchBuffer(slot);
        slot.page_title_fetch_needed = false;
        slot.page_title_generation +%= 1;
        cleared = true;
    }
    return cleared;
}

/// Second tick of Hard Reload: after Native has applied `about:blank`,
/// restore the committed pane URL and bump `reload_token`. History
/// is unchanged. Called at the start of `update` so a same-tick
/// blank→restore cannot collapse to one final URL.
pub fn maybeFinishHardReload(model: *Model) void {
    for (&model.browser_slots) |*slot| {
        if (!slot.hard_reload_pending) continue;
        slot.hard_reload_pending = false;
        slot.reload_token +%= 1;
    }
}

fn paneUrl(slot: *const Slot, committed: []const u8) []const u8 {
    if (slot.hard_reload_pending or slot.stop_blank_pending) return blank_url;
    return committed;
}

/// Model-derived webview panes. Always one pane per scene webview
/// (Native `max_web_panes` = 4). The active occupied slot snaps to
/// `browser-pane` when the Browser tab is showing **and** that slot
/// has a committed page; empty history parks at 1×1 with no anchor
/// (same as hidden / inactive) so the Native start page can paint.
/// Unopened / empty slots keep the home URL as the parked scene.
pub fn webPanes(model: *const Model, out: []WebViewPane) usize {
    const showing = model.right_panel_showing_browser();
    const active = activeIndex(model);
    var n: usize = 0;
    for (0..max_sessions) |i| {
        const slot = slotConst(model, i);
        const occupied = slot.occupied;
        const snap = showing and occupied and i == active and slot.history_count > 0;
        out[n] = .{
            .label = web_view_labels[i],
            .anchor = if (snap) web_pane_anchor else null,
            .frame = if (snap) geometry.RectF.init(0, 0, 0, 0) else parked_frame,
            .url = paneUrl(slot, currentUrlAt(model, i)),
            .reload_token = if (occupied) slot.reload_token else 0,
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
    try std.testing.expect(showingStartPage(&model));
    try std.testing.expect(!hasPage(&model));
    try std.testing.expect(!urlSecure(&model));
    _ = webPanes(&model, &panes);
    try expectParked(panes[0]);
    try std.testing.expectEqualStrings(home_url, panes[0].url);
    try expectParked(panes[1]);
    try expectParked(panes[2]);
    try expectParked(panes[3]);

    setDraft(&model, "https://a.example");
    commitNavigation(&model);
    try std.testing.expect(!showingStartPage(&model));
    try std.testing.expect(hasPage(&model));
    _ = webPanes(&model, &panes);
    try std.testing.expectEqualStrings(web_pane_anchor, panes[0].anchor orelse "");
    try std.testing.expectEqualStrings("https://a.example", panes[0].url);
    try expectParked(panes[1]);
}

test "empty active history parks even when Browser is showing; Navigate snaps" {
    var model: Model = .{};
    var panes: [max_sessions]WebViewPane = undefined;
    model.right_panel_open = true;
    model.right_panel_tab = .browser;

    try std.testing.expect(showingStartPage(&model));
    try std.testing.expect(!hasPage(&model));
    try std.testing.expect(!urlSecure(&model));
    try std.testing.expect(reloadDisabled(&model));
    try std.testing.expect(openDisabled(&model));
    try std.testing.expect(backDisabled(&model));
    try std.testing.expect(forwardDisabled(&model));
    _ = webPanes(&model, &panes);
    try expectParked(panes[0]);
    try std.testing.expectEqualStrings(home_url, panes[0].url);

    const token = panes[0].reload_token;
    reload(&model);
    _ = webPanes(&model, &panes);
    try std.testing.expectEqual(token, panes[0].reload_token);
    try expectParked(panes[0]);

    newSession(&model);
    try std.testing.expect(showingStartPage(&model));
    _ = webPanes(&model, &panes);
    try expectParked(panes[0]);
    try expectParked(panes[1]);
    try std.testing.expectEqualStrings(home_url, panes[0].url);
    try std.testing.expectEqualStrings(home_url, panes[1].url);

    selectSession(&model, 1);
    setDraft(&model, "https://a.example");
    commitNavigation(&model);
    try std.testing.expect(!showingStartPage(&model));
    try std.testing.expect(hasPage(&model));
    try std.testing.expect(urlSecure(&model));
    try std.testing.expect(!reloadDisabled(&model));
    try std.testing.expect(!openDisabled(&model));
    _ = webPanes(&model, &panes);
    try std.testing.expectEqualStrings(web_pane_anchor, panes[0].anchor orelse "");
    try std.testing.expectEqualStrings("https://a.example", panes[0].url);
    try expectParked(panes[1]);

    selectSession(&model, 2);
    try std.testing.expect(showingStartPage(&model));
    try std.testing.expect(!hasPage(&model));
    try std.testing.expect(!urlSecure(&model));
    _ = webPanes(&model, &panes);
    try expectParked(panes[0]);
    try expectParked(panes[1]);
    try std.testing.expectEqualStrings("https://a.example", panes[0].url);
    try std.testing.expectEqualStrings(home_url, panes[1].url);
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
    try std.testing.expectEqualStrings("example.com/path", draft(&model));
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
    try std.testing.expectEqualStrings("a.example", draft(&model));
    try std.testing.expect(!forwardDisabled(&model));

    goForward(&model);
    try std.testing.expectEqualStrings("https://b.example", currentUrl(&model));
    try std.testing.expectEqualStrings("b.example", draft(&model));
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
    try std.testing.expect(!model.browser_slots[0].hard_reload_pending);
}

test "hardReload no-ops without a committed page" {
    var model: Model = .{};
    var panes: [max_sessions]WebViewPane = undefined;
    model.right_panel_open = true;
    model.right_panel_tab = .browser;
    _ = webPanes(&model, &panes);
    const token = panes[0].reload_token;
    hardReload(&model);
    maybeFinishHardReload(&model);
    _ = webPanes(&model, &panes);
    try std.testing.expectEqual(token, panes[0].reload_token);
    try std.testing.expectEqualStrings(home_url, panes[0].url);
    try std.testing.expect(!model.browser_slots[0].hard_reload_pending);
    try std.testing.expectEqual(@as(usize, 0), activeSlotConst(&model).history_count);
}

test "hardReload blanks the pane URL then restore bumps reload_token without history" {
    var model: Model = .{};
    var panes: [max_sessions]WebViewPane = undefined;
    model.right_panel_open = true;
    model.right_panel_tab = .browser;
    setDraft(&model, "https://a.example");
    commitNavigation(&model);
    setDraft(&model, "https://b.example");
    commitNavigation(&model);
    _ = webPanes(&model, &panes);
    const before = panes[0].reload_token;
    try std.testing.expectEqual(@as(usize, 2), activeSlotConst(&model).history_count);
    try std.testing.expectEqual(@as(usize, 1), activeSlotConst(&model).history_index);

    hardReload(&model);
    _ = webPanes(&model, &panes);
    try std.testing.expect(model.browser_slots[0].hard_reload_pending);
    try std.testing.expectEqualStrings(blank_url, panes[0].url);
    try std.testing.expectEqual(before, panes[0].reload_token);
    try std.testing.expectEqualStrings("https://b.example", currentUrl(&model));
    try std.testing.expectEqualStrings("b.example", draft(&model));
    try std.testing.expectEqual(@as(usize, 2), activeSlotConst(&model).history_count);
    try std.testing.expectEqual(@as(usize, 1), activeSlotConst(&model).history_index);
    try std.testing.expectEqualStrings(web_pane_anchor, panes[0].anchor orelse "");

    maybeFinishHardReload(&model);
    _ = webPanes(&model, &panes);
    try std.testing.expect(!model.browser_slots[0].hard_reload_pending);
    try std.testing.expectEqualStrings("https://b.example", panes[0].url);
    try std.testing.expect(panes[0].reload_token != before);
    try std.testing.expectEqualStrings("https://b.example", currentUrl(&model));
    try std.testing.expectEqualStrings("b.example", draft(&model));
    try std.testing.expectEqual(@as(usize, 2), activeSlotConst(&model).history_count);
    try std.testing.expectEqual(@as(usize, 1), activeSlotConst(&model).history_index);
    goBack(&model);
    try std.testing.expectEqualStrings("https://a.example", currentUrl(&model));
}

test "loading guess starts on navigate reload and hardReload and clears on timeout" {
    var model: Model = .{};
    model.now_ms = 10_000;
    try std.testing.expect(!loadingGuessActive(&model));
    try std.testing.expect(stopLoadingDisabled(&model));

    stopLoading(&model);
    try std.testing.expect(!model.browser_slots[0].stop_blank_pending);

    setDraft(&model, "https://a.example");
    commitNavigation(&model);
    try std.testing.expect(loadingGuessActive(&model));
    try std.testing.expectEqual(@as(i64, 10_000 + loading_guess_ms), model.browser_slots[0].loading_guess_until_ms);
    try std.testing.expect(!stopLoadingDisabled(&model));

    model.now_ms = 10_000 + loading_guess_ms - 1;
    maybeClearLoadingGuess(&model);
    try std.testing.expect(loadingGuessActive(&model));

    model.now_ms = 10_000 + loading_guess_ms;
    maybeClearLoadingGuess(&model);
    try std.testing.expect(!loadingGuessActive(&model));
    try std.testing.expectEqual(@as(i64, 0), model.browser_slots[0].loading_guess_until_ms);
    try std.testing.expect(stopLoadingDisabled(&model));

    reload(&model);
    try std.testing.expect(loadingGuessActive(&model));
    model.browser_slots[0].loading_guess_until_ms = 0;
    try std.testing.expect(!loadingGuessActive(&model));

    hardReload(&model);
    try std.testing.expect(loadingGuessActive(&model));
    try std.testing.expect(model.browser_slots[0].hard_reload_pending);
}

test "stopLoading restores the previous committed URL without wiping the ring" {
    var model: Model = .{};
    var panes: [max_sessions]WebViewPane = undefined;
    model.right_panel_open = true;
    model.right_panel_tab = .browser;
    model.now_ms = 10_000;

    setDraft(&model, "https://a.example");
    commitNavigation(&model);
    setDraft(&model, "https://b.example");
    commitNavigation(&model);
    try std.testing.expectEqualStrings("https://b.example", currentUrl(&model));
    try std.testing.expect(loadingGuessActive(&model));
    try std.testing.expectEqual(@as(usize, 2), activeSlotConst(&model).history_count);
    try std.testing.expectEqual(@as(usize, 1), activeSlotConst(&model).history_index);

    stopLoading(&model);
    _ = webPanes(&model, &panes);
    try std.testing.expect(!loadingGuessActive(&model));
    try std.testing.expect(!model.browser_slots[0].stop_blank_pending);
    try std.testing.expectEqualStrings("https://a.example", currentUrl(&model));
    try std.testing.expectEqualStrings("https://a.example", panes[0].url);
    try std.testing.expectEqual(@as(usize, 2), activeSlotConst(&model).history_count);
    try std.testing.expectEqual(@as(usize, 0), activeSlotConst(&model).history_index);
    try std.testing.expect(!forwardDisabled(&model));
    try std.testing.expect(stopLoadingDisabled(&model));

    stopLoading(&model);
    try std.testing.expectEqualStrings("https://a.example", currentUrl(&model));
    try std.testing.expectEqual(@as(usize, 2), activeSlotConst(&model).history_count);
}

test "stopLoading blanks then clears occupancy on a first-page load" {
    var model: Model = .{};
    var panes: [max_sessions]WebViewPane = undefined;
    model.right_panel_open = true;
    model.right_panel_tab = .browser;
    model.now_ms = 10_000;

    setDraft(&model, "https://a.example");
    commitNavigation(&model);
    try std.testing.expect(hasPage(&model));
    try std.testing.expect(loadingGuessActive(&model));

    stopLoading(&model);
    _ = webPanes(&model, &panes);
    try std.testing.expect(!loadingGuessActive(&model));
    try std.testing.expect(model.browser_slots[0].stop_blank_pending);
    try std.testing.expectEqualStrings(blank_url, panes[0].url);
    try std.testing.expectEqualStrings("https://a.example", currentUrl(&model));
    try std.testing.expectEqual(@as(usize, 1), activeSlotConst(&model).history_count);
    try std.testing.expectEqualStrings(web_pane_anchor, panes[0].anchor orelse "");

    try std.testing.expect(maybeFinishStopBlank(&model));
    _ = webPanes(&model, &panes);
    try std.testing.expect(!model.browser_slots[0].stop_blank_pending);
    try std.testing.expect(!hasPage(&model));
    try std.testing.expect(showingStartPage(&model));
    try std.testing.expect(model.browser_slots[0].occupied);
    try std.testing.expectEqualStrings("", committedUrlAt(&model, 0));
    try std.testing.expectEqualStrings(home_url, panes[0].url);
    try expectParked(panes[0]);
    try std.testing.expect(!maybeFinishStopBlank(&model));
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

test "displayUrl hides a leading https:// only" {
    try std.testing.expectEqualStrings("example.com/x", displayUrl("https://example.com/x"));
    try std.testing.expectEqualStrings("http://localhost:3000", displayUrl("http://localhost:3000"));
    try std.testing.expectEqualStrings("", displayUrl(""));
    try std.testing.expectEqualStrings("about:blank", displayUrl("about:blank"));
    try std.testing.expectEqualStrings("file:///tmp/a", displayUrl("file:///tmp/a"));
    try std.testing.expectEqualStrings("mailto:hi@example.com", displayUrl("mailto:hi@example.com"));
    try std.testing.expectEqualStrings("HTTPS://EXAMPLE.COM", displayUrl("HTTPS://EXAMPLE.COM"));
}

test "restoreAddressFromCommitted echoes display_url of committed history" {
    var model: Model = .{};
    setDraft(&model, "https://example.com/x");
    commitNavigation(&model);
    try std.testing.expectEqualStrings("example.com/x", draft(&model));
    setDraft(&model, "dirty-draft");
    restoreAddressFromCommitted(&model);
    try std.testing.expectEqualStrings("example.com/x", draft(&model));
    try std.testing.expectEqualStrings("https://example.com/x", currentUrl(&model));
}

test "restoreAddressFromCommitted empty history is empty display draft" {
    var model: Model = .{};
    setDraft(&model, "half-typed");
    try std.testing.expectEqualStrings("half-typed", draft(&model));
    restoreAddressFromCommitted(&model);
    try std.testing.expectEqualStrings("", draft(&model));
}

test "isSecureUrl matches Waku starts_with https://" {
    try std.testing.expect(isSecureUrl("https://example.com"));
    try std.testing.expect(isSecureUrl("https://example.com/x"));
    try std.testing.expect(!isSecureUrl("http://localhost"));
    try std.testing.expect(!isSecureUrl("http://localhost:3000"));
    try std.testing.expect(!isSecureUrl(""));
    try std.testing.expect(!isSecureUrl("about:blank"));
    try std.testing.expect(!isSecureUrl("HTTPS://EXAMPLE.COM"));
}

test "urlSecure follows committed URL, not home_url or the address draft" {
    var model: Model = .{};
    try std.testing.expectEqualStrings(home_url, currentUrl(&model));
    try std.testing.expectEqualStrings("", committedUrlAt(&model, 0));
    try std.testing.expect(!hasPage(&model));
    try std.testing.expect(!urlSecure(&model));
    setDraft(&model, "http://localhost:3000");
    try std.testing.expectEqualStrings("http://localhost:3000", draft(&model));
    try std.testing.expect(!urlSecure(&model));
    commitNavigation(&model);
    try std.testing.expectEqualStrings("http://localhost:3000", currentUrl(&model));
    try std.testing.expect(!urlSecure(&model));
    setDraft(&model, "https://example.com");
    try std.testing.expectEqualStrings("https://example.com", draft(&model));
    try std.testing.expect(!urlSecure(&model));
    commitNavigation(&model);
    try std.testing.expect(urlSecure(&model));
    try std.testing.expectEqualStrings("example.com", draft(&model));
}

test "commitNavigation draft is display form while history stays full" {
    var model: Model = .{};
    setDraft(&model, "https://example.com/x");
    commitNavigation(&model);
    try std.testing.expectEqualStrings("https://example.com/x", currentUrl(&model));
    try std.testing.expectEqualStrings("https://example.com/x", activeSlotConst(&model).history[0].text());
    try std.testing.expectEqualStrings("example.com/x", draft(&model));
    try std.testing.expect(urlSecure(&model));

    setDraft(&model, "http://localhost:3000");
    commitNavigation(&model);
    try std.testing.expectEqualStrings("http://localhost:3000", currentUrl(&model));
    try std.testing.expectEqualStrings("http://localhost:3000", draft(&model));
    try std.testing.expect(!urlSecure(&model));
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
    try std.testing.expectEqualStrings("www.google.com/search?q=rust+borrow+checker", draft(&model));
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
    try std.testing.expect(showingStartPage(&model));
    try std.testing.expect(!hasPage(&model));
    _ = webPanes(&model, &panes);
    try expectParked(panes[0]);
    try expectParked(panes[1]);
    try std.testing.expectEqualStrings("https://a.example", panes[0].url);
    try std.testing.expectEqualStrings(home_url, panes[1].url);
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
    try std.testing.expectEqualStrings("a.example", draft(&model));
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

test "chipLabelSource prefers host then display_url; empty stays empty" {
    try std.testing.expectEqualStrings("", chipLabelSource(""));
    try std.testing.expectEqualStrings("example.com", chipLabelSource("https://example.com"));
    try std.testing.expectEqualStrings("example.com", chipLabelSource("https://example.com/x"));
    try std.testing.expectEqualStrings("localhost", chipLabelSource("http://localhost:3000"));
    try std.testing.expectEqualStrings("127.0.0.1", chipLabelSource("http://127.0.0.1:8080/api"));
    try std.testing.expectEqualStrings("::1", chipLabelSource("http://[::1]/"));
    try std.testing.expectEqualStrings("example.com", chipLabelSource("https://user:pass@example.com/x"));
    try std.testing.expectEqualStrings("about:blank", chipLabelSource("about:blank"));
    try std.testing.expectEqualStrings("file:///tmp/a", chipLabelSource("file:///tmp/a"));
    try std.testing.expectEqualStrings("mailto:hi@example.com", chipLabelSource("mailto:hi@example.com"));
    try std.testing.expectEqualStrings("data:text/plain,hi", chipLabelSource("data:text/plain,hi"));
    try std.testing.expectEqualStrings("www.google.com", chipLabelSource("https://www.google.com/search?q=what+is+wry"));
}

test "sessionRows chips use host or truncated display_url; empty history keeps index" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var model: Model = .{};
    var rows = sessionRows(&model, arena);
    try std.testing.expectEqual(@as(usize, 1), rows.len);
    try std.testing.expectEqualStrings("1", rows[0].label);
    try std.testing.expect(rows[0].selected);
    try std.testing.expectEqualStrings("", committedUrlAt(&model, 0));
    try std.testing.expectEqualStrings(home_url, currentUrl(&model));

    setDraft(&model, "https://example.com/docs");
    commitNavigation(&model);
    rows = sessionRows(&model, arena);
    try std.testing.expectEqualStrings("example.com", rows[0].label);
    try std.testing.expectEqualStrings("https://example.com/docs", committedUrlAt(&model, 0));

    setDraft(&model, "http://localhost:3000");
    commitNavigation(&model);
    rows = sessionRows(&model, arena);
    try std.testing.expectEqualStrings("localhost", rows[0].label);

    setDraft(&model, "about:blank");
    commitNavigation(&model);
    rows = sessionRows(&model, arena);
    try std.testing.expectEqualStrings("about:blank", rows[0].label);

    setDraft(&model, "file:///tmp/abcdefghijklmnopqrstuvwxyz");
    commitNavigation(&model);
    rows = sessionRows(&model, arena);
    const long_file = "file:///tmp/abcdefghijklmnopqrstuvwxyz";
    try std.testing.expect(long_file.len > chip_label_max_chars);
    try std.testing.expectEqualStrings("file:///tmp/abcdefghijkl…", rows[0].label);
    try std.testing.expectEqual(chip_label_max_chars + "…".len, rows[0].label.len);
    try std.testing.expectEqualStrings(long_file, committedUrlAt(&model, 0));

    setDraft(&model, "https://this-is-a-very-long-subdomain.example.com/path");
    commitNavigation(&model);
    rows = sessionRows(&model, arena);
    try std.testing.expectEqualStrings("this-is-a-very-long-subd…", rows[0].label);
    try std.testing.expectEqualStrings(
        "https://this-is-a-very-long-subdomain.example.com/path",
        committedUrlAt(&model, 0),
    );

    var persisted: [max_sessions]PersistedSlot = undefined;
    capturePersisted(&model, &persisted);
    try std.testing.expectEqualStrings(
        "https://this-is-a-very-long-subdomain.example.com/path",
        persisted[0].url,
    );
}

test "sessionRows multi-slot labels follow each committed URL" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var model: Model = .{};
    setDraft(&model, "https://a.example");
    commitNavigation(&model);
    newSession(&model);
    setDraft(&model, "http://127.0.0.1:8080/api");
    commitNavigation(&model);
    newSession(&model);

    const rows = sessionRows(&model, arena);
    try std.testing.expectEqual(@as(usize, 3), rows.len);
    try std.testing.expectEqualStrings("a.example", rows[0].label);
    try std.testing.expectEqual(@as(u32, 1), rows[0].id);
    try std.testing.expect(!rows[0].selected);
    try std.testing.expectEqualStrings("127.0.0.1", rows[1].label);
    try std.testing.expectEqual(@as(u32, 2), rows[1].id);
    try std.testing.expect(!rows[1].selected);
    try std.testing.expectEqualStrings("3", rows[2].label);
    try std.testing.expectEqual(@as(u32, 3), rows[2].id);
    try std.testing.expect(rows[2].selected);
    try std.testing.expect(!std.mem.eql(u8, rows[0].label, rows[1].label));
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
    try std.testing.expectEqualStrings("c.example", draft(&model));
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

    selectSession(&model, 1);
    try std.testing.expectEqualStrings("https://a.example", currentUrl(&model));
    try std.testing.expectEqualStrings("a.example", draft(&model));
    try std.testing.expectEqualStrings("https://a.example", committedUrlAt(&model, 0));

    restoreFromPersist(&model, &[_]PersistedSlot{}, 3);
    try std.testing.expectEqual(@as(usize, 1), occupiedCount(&model));
    try std.testing.expect(model.browser_slots[0].occupied);
    try std.testing.expectEqual(@as(u8, 0), model.browser_active);
}

test "restoreFromPersist rebuilds history rings so back and forward work" {
    var model: Model = .{};
    setDraft(&model, "https://a1.example");
    commitNavigation(&model);
    setDraft(&model, "https://a2.example");
    commitNavigation(&model);
    setDraft(&model, "https://a3.example");
    commitNavigation(&model);
    goBack(&model);
    try std.testing.expect(!backDisabled(&model));
    try std.testing.expect(!forwardDisabled(&model));
    try std.testing.expectEqualStrings("https://a2.example", currentUrl(&model));
    reload(&model);
    try std.testing.expect(model.browser_slots[0].reload_token != 0);

    newSession(&model);
    setDraft(&model, "https://b1.example");
    commitNavigation(&model);
    setDraft(&model, "https://b2.example");
    commitNavigation(&model);
    try std.testing.expect(!backDisabled(&model));
    try std.testing.expect(forwardDisabled(&model));

    var persisted: [max_sessions]PersistedSlot = undefined;
    capturePersisted(&model, &persisted);
    try std.testing.expect(persisted[0].history_present);
    try std.testing.expectEqual(@as(usize, 3), persisted[0].history_count);
    try std.testing.expectEqual(@as(usize, 1), persisted[0].history_index);
    try std.testing.expectEqualStrings("https://a1.example", persisted[0].history_urls[0]);
    try std.testing.expectEqualStrings("https://a2.example", persisted[0].history_urls[1]);
    try std.testing.expectEqualStrings("https://a3.example", persisted[0].history_urls[2]);
    try std.testing.expectEqualStrings("https://a2.example", persisted[0].url);
    try std.testing.expectEqual(@as(usize, 2), persisted[1].history_count);
    try std.testing.expectEqual(@as(usize, 1), persisted[1].history_index);
    try std.testing.expectEqualStrings("https://b2.example", persisted[1].url);

    var restored: Model = .{};
    restored.browser_slots[0].reload_token = 99;
    restored.browser_slots[0].hard_reload_pending = true;
    restored.browser_slots[0].loading_guess_until_ms = 99;
    restored.browser_slots[0].stop_blank_pending = true;
    restored.browser_slots[0].page_title.set("Stale title");
    restoreFromPersist(&restored, &persisted, 1);
    try std.testing.expectEqual(@as(u8, 1), restored.browser_active);
    try std.testing.expectEqual(@as(u64, 0), restored.browser_slots[0].reload_token);
    try std.testing.expectEqual(@as(u64, 0), restored.browser_slots[1].reload_token);
    try std.testing.expect(!restored.browser_slots[0].hard_reload_pending);
    try std.testing.expect(!restored.browser_slots[1].hard_reload_pending);
    try std.testing.expectEqual(@as(i64, 0), restored.browser_slots[0].loading_guess_until_ms);
    try std.testing.expect(!restored.browser_slots[0].stop_blank_pending);
    try std.testing.expect(!restored.browser_slots[1].stop_blank_pending);
    try std.testing.expectEqualStrings("", restored.browser_slots[0].page_title.text());
    try std.testing.expect(restored.browser_slots[0].page_title_fetch_needed);
    try std.testing.expect(restored.browser_slots[1].page_title_fetch_needed);
    try std.testing.expectEqual(@as(usize, 3), restored.browser_slots[0].history_count);
    try std.testing.expectEqual(@as(usize, 1), restored.browser_slots[0].history_index);
    try std.testing.expectEqualStrings("https://a2.example", committedUrlAt(&restored, 0));
    try std.testing.expectEqualStrings("https://b2.example", currentUrl(&restored));
    try std.testing.expectEqualStrings("b2.example", draft(&restored));
    try std.testing.expect(!backDisabled(&restored));
    try std.testing.expect(forwardDisabled(&restored));
    goBack(&restored);
    try std.testing.expectEqualStrings("https://b1.example", currentUrl(&restored));
    try std.testing.expect(backDisabled(&restored));
    goForward(&restored);
    try std.testing.expectEqualStrings("https://b2.example", currentUrl(&restored));

    selectSession(&restored, 1);
    try std.testing.expectEqualStrings("https://a2.example", currentUrl(&restored));
    try std.testing.expect(!backDisabled(&restored));
    try std.testing.expect(!forwardDisabled(&restored));
    goBack(&restored);
    try std.testing.expectEqualStrings("https://a1.example", currentUrl(&restored));
    try std.testing.expect(backDisabled(&restored));
    goForward(&restored);
    goForward(&restored);
    try std.testing.expectEqualStrings("https://a3.example", currentUrl(&restored));
    try std.testing.expect(forwardDisabled(&restored));
}

test "restoreFromPersist clamps history_index; legacy tip-only stays single-entry" {
    var slots = [_]PersistedSlot{.{}} ** max_sessions;
    slots[0] = .{
        .occupied = true,
        .url = "https://b.example",
        .history_present = true,
        .history_count = 2,
        .history_index = 99,
    };
    slots[0].history_urls[0] = "https://a.example";
    slots[0].history_urls[1] = "https://b.example";
    var model: Model = .{};
    restoreFromPersist(&model, &slots, 0);
    try std.testing.expectEqual(@as(usize, 2), model.browser_slots[0].history_count);
    try std.testing.expectEqual(@as(usize, 1), model.browser_slots[0].history_index);
    try std.testing.expectEqualStrings("https://b.example", currentUrl(&model));
    try std.testing.expect(!backDisabled(&model));
    try std.testing.expect(forwardDisabled(&model));

    const legacy = [_]PersistedSlot{
        .{ .occupied = true, .url = "https://legacy.example" },
        .{},
        .{},
        .{},
    };
    restoreFromPersist(&model, &legacy, 0);
    try std.testing.expectEqual(@as(usize, 1), model.browser_slots[0].history_count);
    try std.testing.expectEqual(@as(usize, 0), model.browser_slots[0].history_index);
    try std.testing.expectEqualStrings("https://legacy.example", currentUrl(&model));
    try std.testing.expect(backDisabled(&model));
    try std.testing.expect(forwardDisabled(&model));
    try std.testing.expectEqual(@as(u64, 0), model.browser_slots[0].reload_token);
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
    try std.testing.expect(std.mem.indexOf(u8, context, "history rings") != null);
    try std.testing.expect(std.mem.indexOf(u8, context, "browser_histories") != null);
    try std.testing.expect(std.mem.indexOf(u8, context, "`reload_token` stays runtime-only") != null);
    try std.testing.expect(std.mem.indexOf(u8, context, "Faku-side blank-hop") != null);
    try std.testing.expect(std.mem.indexOf(u8, context, "loading-guess") != null);
    try std.testing.expect(std.mem.indexOf(u8, context, "Stop loading") != null);
    try std.testing.expect(std.mem.indexOf(u8, context, "is_secure_url") != null);
    try std.testing.expect(std.mem.indexOf(u8, context, "lock/globe") != null);
    try std.testing.expect(std.mem.indexOf(u8, context, "page_title") != null);
    try std.testing.expect(std.mem.indexOf(u8, context, "one-shot") != null);
    try std.testing.expect(std.mem.indexOf(u8, context, "Faku-side one-shot HTML title") != null);
    try std.testing.expect(std.mem.indexOf(u8, context, "runtime-only") != null);
    try std.testing.expect(std.mem.indexOf(u8, context, "DevTools / `page_title` stay out") == null);
    try std.testing.expect(std.mem.indexOf(u8, context, "page_title still out") == null);
    try std.testing.expect(std.mem.indexOf(u8, context, "not Waku `page_title` / surface UUID tabs / DevTools") == null);
    try std.testing.expect(std.mem.indexOf(u8, context, "display_url/host first-cut") == null);
    try std.testing.expect(std.mem.indexOf(u8, context, "start page") != null);
    try std.testing.expect(std.mem.indexOf(u8, context, "empty history is globe") != null);
    try std.testing.expect(std.mem.indexOf(u8, context, "empty history uses home `https://example.com` → lock") == null);
    try std.testing.expect(std.mem.indexOf(u8, context, "Lock-icon") == null);
    try std.testing.expect(std.mem.indexOf(u8, context, "Not Waku tabs / DevTools / multi-session.") == null);
    try std.testing.expect(std.mem.indexOf(u8, context, "History ring / back / forward / `reload_token` stay runtime-only") == null);
    try std.testing.expect(std.mem.indexOf(u8, context, "Full history rings / back / forward / `reload_token` stay runtime-only") == null);
    const browser_cut = std.mem.indexOf(u8, readme, "First-cut embedded Browser tab") orelse return error.MissingBrowserReadme;
    const window = readme[browser_cut..@min(readme.len, browser_cut + 480)];
    try std.testing.expect(std.mem.indexOf(u8, window, "up to 4 sessions") != null);
    try std.testing.expect(std.mem.indexOf(u8, window, "occupied URLs persist") != null);
    try std.testing.expect(std.mem.indexOf(u8, window, "history rings persist") != null);
    try std.testing.expect(std.mem.indexOf(u8, window, "lock/globe") != null);
    try std.testing.expect(std.mem.indexOf(u8, window, "start page") != null);
    try std.testing.expect(std.mem.indexOf(u8, window, "page_title") != null);
    try std.testing.expect(std.mem.indexOf(u8, readme, "DevTools / `page_title` stay out") == null);
    try std.testing.expect(std.mem.indexOf(u8, readme, "not … multi-session") == null);
}

test "extractTitle is case-insensitive and decodes trivial entities" {
    var buf: [page_title_max]u8 = undefined;
    try std.testing.expectEqualStrings("Example", extractTitle("<html><title>Example</title></html>", &buf));
    try std.testing.expectEqualStrings("Docs", extractTitle("<TITLE  class=\"x\">Docs</TITLE>", &buf));
    try std.testing.expectEqualStrings("A & B <C>", extractTitle("<title>A &amp; B &lt;C&gt;</title>", &buf));
    try std.testing.expectEqualStrings("A \"B'C", extractTitle("<title>A &quot;B&#39;C</title>", &buf));
    try std.testing.expectEqualStrings("'", extractTitle("<title>&#x27;</title>", &buf));
    try std.testing.expectEqualStrings("Spaced name", extractTitle("<title>\n  Spaced   \nname\t</title>", &buf));
    try std.testing.expectEqualStrings("", extractTitle("<html><head></head></html>", &buf));
    try std.testing.expectEqualStrings("", extractTitle("<title>open only", &buf));
    try std.testing.expectEqualStrings("", extractTitle("", &buf));
    const binary = "\x00<title>Nope</title>";
    try std.testing.expectEqualStrings("", extractTitle(binary, &buf));
    const long = "<title>abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ</title>";
    const got = extractTitle(long, buf[0..24]);
    try std.testing.expectEqual(@as(usize, 24), got.len);
}

test "chip labels prefer page_title then host then display_url" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var model: Model = .{};
    setDraft(&model, "https://example.com/docs");
    commitNavigation(&model);
    var rows = sessionRows(&model, arena);
    try std.testing.expectEqualStrings("example.com", rows[0].label);

    model.browser_slots[0].page_title.set("Example Docs");
    rows = sessionRows(&model, arena);
    try std.testing.expectEqualStrings("Example Docs", rows[0].label);

    model.browser_slots[0].page_title.set("this is a very long document title for chips");
    rows = sessionRows(&model, arena);
    try std.testing.expectEqualStrings("this is a very long docu…", rows[0].label);

    model.browser_slots[0].page_title.clear();
    setDraft(&model, "about:blank");
    commitNavigation(&model);
    rows = sessionRows(&model, arena);
    try std.testing.expectEqualStrings("about:blank", rows[0].label);
    try std.testing.expectEqualStrings("", model.browser_slots[0].page_title.text());
}

test "title fetch argv is curl slots; stale exit does not overwrite a newer URL" {
    const testing = std.testing;
    var argv_buf: [page_title_argv_len][]const u8 = undefined;
    const argv = argvForBin(litellm_rates.unix_curl_bin, "https://example.com/docs", &argv_buf);
    try testing.expect(isTitleFetchArgv(argv));
    try testing.expectEqual(@as(usize, 9), argv.len);
    try testing.expectEqualStrings("-fsSL", argv[1]);
    try testing.expectEqualStrings("--max-time", argv[2]);
    try testing.expectEqualStrings(page_title_max_time, argv[3]);
    try testing.expectEqualStrings("--max-filesize", argv[4]);
    try testing.expectEqualStrings(page_title_max_filesize, argv[5]);
    try testing.expectEqualStrings("-H", argv[6]);
    try testing.expectEqualStrings(page_title_accept_header, argv[7]);
    try testing.expectEqualStrings("https://example.com/docs", argv[8]);
    try testing.expect(std.mem.indexOf(u8, argv[1], "https://") == null);
    try testing.expectEqual(@as(u64, 660), page_title_key_first);
    try testing.expectEqual(@as(u64, 699), page_title_key_last);
    try testing.expect(page_title_key_first > litellm_rates.litellm_rates_key);
    try testing.expect(page_title_key_last < 700);

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model: Model = .{};
    setDraft(&model, "https://first.example");
    commitNavigation(&model);
    startTitleFetches(&model, &fx);
    const first = pendingTitleSpawn(&fx, model.browser_slots[0].page_title_pending_key) orelse return error.MissingFirstTitleFetch;
    try testing.expect(isTitleFetchArgv(first.argv));
    try testing.expectEqualStrings("https://first.example", first.argv[8]);
    const first_key = first.key;
    try testing.expect(isPendingTitleKey(&model, first_key));

    applyLine(&model, .{ .key = first_key, .line = "<html><title>First Title</title></html>" });

    setDraft(&model, "https://second.example");
    commitNavigation(&model);
    startTitleFetches(&model, &fx);
    const second = pendingTitleSpawn(&fx, model.browser_slots[0].page_title_pending_key) orelse return error.MissingSecondTitleFetch;
    try testing.expect(second.key != first_key);
    try testing.expectEqualStrings("https://second.example", second.argv[8]);
    try testing.expectEqualStrings("", model.browser_slots[0].page_title.text());

    handleExit(&model, .{ .key = first_key, .reason = .exited, .code = 0 });
    try testing.expectEqualStrings("", model.browser_slots[0].page_title.text());
    try testing.expect(!isPendingTitleKey(&model, first_key));

    applyLine(&model, .{ .key = second.key, .line = "<title>Second Title</title>" });
    handleExit(&model, .{ .key = second.key, .reason = .exited, .code = 0 });
    try testing.expectEqualStrings("Second Title", model.browser_slots[0].page_title.text());

    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const rows = sessionRows(&model, arena_state.allocator());
    try testing.expectEqualStrings("Second Title", rows[0].label);

    setDraft(&model, "about:blank");
    commitNavigation(&model);
    startTitleFetches(&model, &fx);
    try testing.expectEqualStrings("", model.browser_slots[0].page_title.text());
    try testing.expect(!titleFetchEligible(committedUrlAt(&model, 0)));
}

test "title fetch fail-closed keeps host chip; at most one in-flight per slot" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model: Model = .{};
    setDraft(&model, "https://fail.example");
    commitNavigation(&model);
    startTitleFetches(&model, &fx);
    const first = pendingTitleSpawn(&fx, model.browser_slots[0].page_title_pending_key) orelse return error.MissingTitleFetch;
    const first_key = first.key;
    startTitleFetches(&model, &fx);
    try testing.expectEqual(first_key, model.browser_slots[0].page_title_pending_key);

    handleExit(&model, .{ .key = first_key, .reason = .exited, .code = 22 });
    try testing.expectEqualStrings("", model.browser_slots[0].page_title.text());

    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    var rows = sessionRows(&model, arena_state.allocator());
    try testing.expectEqualStrings("fail.example", rows[0].label);

    startTitleFetches(&model, &fx);
    try testing.expectEqual(@as(u64, 0), model.browser_slots[0].page_title_pending_key);

    model.browser_slots[0].page_title_fetch_needed = true;
    startTitleFetches(&model, &fx);
    const retry = pendingTitleSpawn(&fx, model.browser_slots[0].page_title_pending_key) orelse return error.MissingRetryTitleFetch;
    applyLine(&model, .{ .key = retry.key, .line = "<title></title>" });
    handleExit(&model, .{ .key = retry.key, .reason = .exited, .code = 0 });
    try testing.expectEqualStrings("", model.browser_slots[0].page_title.text());
    rows = sessionRows(&model, arena_state.allocator());
    try testing.expectEqualStrings("fail.example", rows[0].label);
}

fn pendingTitleSpawn(fx: *Effects, key: u64) ?@TypeOf(fx.pendingSpawnAt(0).?) {
    var i: usize = 0;
    while (fx.pendingSpawnAt(i)) |spawn| : (i += 1) {
        if (spawn.key == key) return spawn;
    }
    return null;
}
