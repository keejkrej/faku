//! First-cut Waku right panel: Files, Diff, Browser, Terminal, Background.
//!
//! Toggleable pane to the right of the conversation column. Files
//! lists the selected session's project files from the existing
//! `file_mention` cache (`git ls-files --cached --others
//! --exclude-standard`, then the bounded walk) plus derived
//! parent directories collected there. Diff shows the existing
//! Environment Compare / Review body inline (source chips + status +
//! file list + hunk text) via `review_diff` — not a second git probe
//! stack. Background is a runtime-only surface for the Environment
//! Summary Process / Monitor / Subagent row that was clicked (kind,
//! title, live-or-settled status, Monitor / Subagent 512KB last-window log
//! with newlines kept and CSI/ANSI stripped for display;
//! Environment Summary stays a one-line preview; Stop when the
//! selected row is a live Process, live Monitor, or live Subagent;
//! Dismiss when the selected row is a settled Monitor or Subagent). Tab
//! click with no selected row, or a selected row that is gone, shows
//! "No background work". Browser and Terminal are honest OS-open
//! first-cuts this cut (system browser via `open_url`, host terminal
//! via `open_terminal`) — not an embedded webview or PTY.
//! Claude CLI TaskStop (Faku-side Monitor and
//! Subagent Stop on one-shot `claude -p` ships; live Stop dismisses
//! that live row and does not invoke TaskStop mid-turn; settled
//! rows offer Dismiss), daemon
//! `refreshBackgroundWork`, GPUI SharedString, or full
//! BackgroundWorkRegistry event/reconcile parity. This cut ships a
//! 100ms CSI-stripped last-window render cache on Monitor / Subagent
//! (piggybacks `now_ms` / the stream tick; Native has no dedicated
//! 100ms timer). First-cut
//! settled Monitor / Subagent stay in the runtime registry after the
//! turn (status from Process settle; Monitor / Subagent last-window kept;
//! Faku-side Dismiss, not Claude TaskStop / daemon
//! `refreshBackgroundWork`; not live after `-p` exits). First-cut
//! daemon `WorkspaceOperation::ListTree` ships on Files refresh
//! when a daemon address is set (ok paints the file cache from
//! `workingTree` file entries; expand after a daemon fill re-probes
//! ListTree; Native 4 KiB stdin overflow / error / unusable parse
//! falls back to local git ls-files then walk; no address keeps
//! today's local path). First-cut daemon
//! `WorkspaceOperation::CollectReviewDiff` ships on Review / Diff
//! open / refresh / source-switch when a daemon address is set (ok
//! paints the file list from `numstat` and selected hunk from
//! `patch`; LastTurn stays local; Native 4 KiB stdin overflow /
//! error / unusable parse falls back to local name-status + hunk
//! probes; no address keeps today's local path). First-cut daemon
//! `WorkspaceOperation::BrowseDirectory` ships in `pick_folder`
//! (Pick folder in-app browser when a daemon address is set;
//! overflow / error / unusable parse falls back to the local OS
//! folder dialog). First-cut daemon `WorkspaceOperation::ReadTextFile`
//! ships on Files preview load (select / Reload) when a daemon
//! address is set (ok paints the same 256KB UTF-8 preview buffers;
//! Native 4 KiB stdin overflow / error / unusable parse falls back
//! to local `readFileAlloc`; no address keeps today's local path).
//! First-cut daemon `WorkspaceOperation::WriteTextFile` ships on
//! Files preview Save when a daemon address is set (hello +
//! `writeTextFile`; ok Ack adopts the saved buffer as the preview
//! body; Native 4 KiB stdin overflow / spawn failure / non-ok /
//! non-ack / unusable parse falls back to today's local atomic
//! write; no address keeps today's local path; truncated / binary /
//! gated refuse paths stay local with no daemon attempt; Open-in-editor
//! stays local). Leftovers: remotes-on-daemon-list, amend/force over
//! daemon, remote `--track` over daemon, ref ops.
//! Not Waku's 50k-file index (cap 256). Windows probes the same
//! cache (`git.exe -C` then a PowerShell walk; still not Waku's
//! 50k index or a Native FS watcher).
//!
//! Files tab ships a bounded inline file preview (prefer daemon
//! `ReadTextFile` when an address is set, else Faku-side
//! `readFileAlloc`; 256KB cap, truncated label when larger, binary /
//! non-UTF-8 honest empty state, unreadable one-line error, newlines
//! kept, Native `<code>` highlighting with `line-numbers`, runtime-only,
//! cleared on session switch / remove / panel hide). Language is a
//! documented Native lexer name from the path (unknown / Dockerfile /
//! Makefile / Cargo.toml → `plain`). Native numbered mode omits the
//! gutter above 128 logical lines but keeps the source.
//! `previewLineRows` remains for tests.
//!
//! First-cut edit + save ships: Edit switches a text body to a Native
//! `<textarea>` (same widget as the composer; highlighting drops while
//! dirty). `on-input` updates a Model edit buffer. Dirty is buffer ≠
//! loaded body. Save prefers hello + daemon `WriteTextFile` when a
//! daemon address is set (ok Ack adopts the saved buffer as the
//! preview body). Native 4 KiB stdin overflow / sidecar failure /
//! non-ack falls back to Zig `std.Io` `createFileAtomic` (temp +
//! rename, same class of local I/O as `store` / `sessions.json`; no
//! Native write effect). No address keeps that local path. Success
//! adopts the saved bytes as the new preview body, clears dirty, and
//! returns to the read-only `<code>` view. Failure sets a short status
//! string and leaves the on-disk file untouched when the atomic replace
//! does not run. Save is gated: not editing / not dirty / binary / no
//! abs path / truncated (saving a 256KB window would clobber the rest
//! of the file — refuse with a short message; truncated stays
//! Open-in-editor + Reload; truncated / binary / gated refuse do not
//! attempt the daemon). Reload always re-reads (prefer daemon
//! ReadTextFile when an address is set; else disk) and discards
//! unsaved edits (the click is the confirm; no extra dialog chrome).
//! Open in editor and Close stay. First-cut unsaved discard confirm
//! ships as inline preview-header chrome (ghost sm buttons, same class
//! as git commit/branch confirm rows — not a Native modal): switching
//! files / Close / hide / session switch while dirty parks that action,
//! keeps the dirty editor open, and asks Discard vs Keep editing.
//! Discard runs the parked action; Keep editing clears the park.
//! Successful Save, Reload, or the buffer matching the loaded body
//! (dirty becomes false) clears the pending confirm. First-cut live
//! reload polls the open preview file's `stat` size + mtime on the
//! TEA `update` tick (same `now_ms` piggyback as Background's 100ms
//! render cache; Native has no FS watcher / dedicated timer). Dirty
//! buffers are never auto-reloaded. Not a real FS watcher / Native
//! watch API, not an embedded Browser / Terminal (those tabs are
//! OS-open workarounds; Native has no PTY / webview), or autosave.
//!
//! Default closed: Waku `RightPanelSessionState::take_or_closed` uses
//! `empty(false)` and persistence `default_right_panel_visibility` is
//! false. Files tab widths are Waku `DEFAULT_FILE_TREE_WIDTH` (184) /
//! `FILE_TREE_MIN_WIDTH` (140) / `FILE_TREE_MAX_WIDTH` (360). Diff and
//! Background, Browser, and Terminal bump toward Waku
//! `DEFAULT_RIGHT_PANEL_WIDTH` (460) when the pane is still
//! file-tree-narrow; first-cut max is 460 (Waku
//! `RIGHT_PANEL_MAX_WIDTH` is 1000). Selected tab and Browser draft URL
//! persist on `sessions.json` extras (`right_panel_tab` / `browser_url`;
//! missing / unknown tab → `files`, missing / empty URL → empty draft).
//! Selected Background row, Files preview, directory expands, and
//! output stay runtime-only. Default `files` when the panel opens.
//!
//! Directory expand/collapse is a runtime-only set of relative dir
//! paths matching `file_mention.derivedDirParents` (no trailing
//! slash), cap `max_file_mention_dirs`. Empty set = collapsed tree
//! (Waku empty `expanded_paths` HashSet): only depth-0 files and
//! top-level dirs. Not persisted to `sessions.json` this cut (Waku
//! keeps `expanded_paths` on in-memory per-session
//! `RightPanelSessionState`).

const std = @import("std");
const native_sdk = @import("native_sdk");
const main = @import("main.zig");
const file_mention = @import("file_mention.zig");
const composer = @import("composer.zig");
const open_editor = @import("open_editor.zig");
const review_diff = @import("review_diff.zig");
const store = @import("store.zig");
const daemon_proxy = @import("daemon_proxy.zig");
const protocol = @import("protocol.zig");

const canvas = native_sdk.canvas;

const Model = main.Model;
const Effects = main.Effects;
const RightPanelFileRow = main.RightPanelFileRow;

/// Runtime-only Files | Diff | Browser | Terminal | Background
/// surface. Default `files` when the panel opens. Tab name persists on
/// `sessions.json` extras (`files` / `diff` / `browser` / `terminal` /
/// `background`; missing / unknown → `files`).
pub const Tab = enum {
    files,
    diff,
    browser,
    terminal,
    background,

    pub fn persistName(self: Tab) []const u8 {
        return switch (self) {
            .files => "files",
            .diff => "diff",
            .browser => "browser",
            .terminal => "terminal",
            .background => "background",
        };
    }

    pub fn fromPersist(value: []const u8) Tab {
        if (std.mem.eql(u8, value, "diff")) return .diff;
        if (std.mem.eql(u8, value, "browser")) return .browser;
        if (std.mem.eql(u8, value, "terminal")) return .terminal;
        if (std.mem.eql(u8, value, "background")) return .background;
        return .files;
    }
};

/// Parked action that would discard a dirty Files preview buffer.
/// Runtime-only; not persisted. Stored on Model as kind + id.
pub const PendingDiscardKind = enum {
    none,
    switch_file,
    close_preview,
    hide_panel,
    switch_session,
    new_session,
    remove_session,
};

pub const PendingDiscard = union(PendingDiscardKind) {
    none,
    switch_file: u32,
    close_preview,
    hide_panel,
    switch_session: u32,
    new_session,
    remove_session: u32,
};

pub const discard_unsaved_label = "Discard unsaved changes?";

/// Mild tree indent per `fileMentionDepth`. Sidebar grouped rows use 15px.
pub const indent_step: f32 = 12;

/// Files-tab inline preview read cap (256KB). Truncation is labeled.
pub const max_file_preview_bytes: usize = 256 * 1024;

/// Native stdout line budget for a ReadTextFile sidecar. Matches
/// Native's `max_effect_line_bytes_ceiling` (256KB); a request above
/// that is rejected. Content is still capped at `max_file_preview_bytes`
/// after parse. JSON wrapping of a near-cap file that blows this bound
/// truncates the line and falls back to local read.
pub const file_preview_daemon_line_bytes: usize = max_file_preview_bytes;

/// First-cut Files preview live reload. Stat size + mtime at most
/// once per this many milliseconds of `model.now_ms`. Piggybacks the
/// update loop / stream tick; Native has no FS watcher / dedicated
/// timer this cut.
pub const file_preview_disk_poll_interval_ms: i64 = 500;

/// Cap Native gutter rows materialized for the preview body. Typical
/// source in a 256KB window stays under this; dense one-char lines may
/// stop early. File-size honesty stays the 256KB truncated label (no
/// second truncation chrome).
pub const max_file_preview_line_rows: usize = 2048;

pub const binary_file_label = "Binary file — not shown";
pub const truncated_file_label = "Truncated — showing first 256 KB";
pub const unreadable_file_label = "Cannot read file";
pub const missing_file_label = "File not found";
pub const truncated_save_label = "Cannot save truncated preview — open in editor";
pub const binary_save_label = "Cannot save binary file";
pub const cannot_save_label = "Cannot save file";

/// Documented Native `language=` lexer name for a preview path. Unknown
/// extensions and well-known names Native has no lexer for
/// (Dockerfile, Makefile, Cargo.toml) are `"plain"`. Never invents a
/// lexer id; names match `native_sdk.canvas.code.languageFromName`.
pub fn previewLanguage(path: []const u8) []const u8 {
    const base = composer.fileMentionBasename(path);
    if (std.ascii.eqlIgnoreCase(base, "Dockerfile") or
        std.ascii.eqlIgnoreCase(base, "Containerfile") or
        std.ascii.eqlIgnoreCase(base, "Makefile") or
        std.ascii.eqlIgnoreCase(base, "GNUmakefile") or
        std.ascii.eqlIgnoreCase(base, "Cargo.toml"))
    {
        return "plain";
    }
    const ext = extensionOf(base);
    if (std.ascii.eqlIgnoreCase(ext, "zig")) return "zig";
    if (std.ascii.eqlIgnoreCase(ext, "js") or
        std.ascii.eqlIgnoreCase(ext, "mjs") or
        std.ascii.eqlIgnoreCase(ext, "cjs")) return "javascript";
    if (std.ascii.eqlIgnoreCase(ext, "tsx")) return "tsx";
    if (std.ascii.eqlIgnoreCase(ext, "jsx")) return "jsx";
    if (std.ascii.eqlIgnoreCase(ext, "ts")) return "typescript";
    if (std.ascii.eqlIgnoreCase(ext, "json") or std.ascii.eqlIgnoreCase(ext, "jsonc")) return "json";
    if (std.ascii.eqlIgnoreCase(ext, "yaml") or std.ascii.eqlIgnoreCase(ext, "yml")) return "yaml";
    if (std.ascii.eqlIgnoreCase(ext, "sh") or
        std.ascii.eqlIgnoreCase(ext, "bash") or
        std.ascii.eqlIgnoreCase(ext, "zsh")) return "shell";
    if (std.ascii.eqlIgnoreCase(ext, "py") or std.ascii.eqlIgnoreCase(ext, "pyi")) return "python";
    if (std.ascii.eqlIgnoreCase(ext, "rs")) return "rust";
    if (std.ascii.eqlIgnoreCase(ext, "c") or std.ascii.eqlIgnoreCase(ext, "h") or
        std.ascii.eqlIgnoreCase(ext, "cc") or std.ascii.eqlIgnoreCase(ext, "cpp") or
        std.ascii.eqlIgnoreCase(ext, "cxx") or std.ascii.eqlIgnoreCase(ext, "hpp") or
        std.ascii.eqlIgnoreCase(ext, "hh") or std.ascii.eqlIgnoreCase(ext, "cs") or
        std.ascii.eqlIgnoreCase(ext, "java") or std.ascii.eqlIgnoreCase(ext, "kt") or
        std.ascii.eqlIgnoreCase(ext, "kts") or std.ascii.eqlIgnoreCase(ext, "swift")) return "c";
    if (std.ascii.eqlIgnoreCase(ext, "go")) return "go";
    if (std.ascii.eqlIgnoreCase(ext, "html") or std.ascii.eqlIgnoreCase(ext, "htm") or
        std.ascii.eqlIgnoreCase(ext, "xml") or std.ascii.eqlIgnoreCase(ext, "svg")) return "html";
    if (std.ascii.eqlIgnoreCase(ext, "css") or
        std.ascii.eqlIgnoreCase(ext, "scss") or
        std.ascii.eqlIgnoreCase(ext, "less")) return "css";
    if (std.ascii.eqlIgnoreCase(ext, "sql")) return "sql";
    if (std.ascii.eqlIgnoreCase(ext, "md") or std.ascii.eqlIgnoreCase(ext, "markdown")) return "markdown";
    return "plain";
}

fn extensionOf(name: []const u8) []const u8 {
    if (std.mem.lastIndexOfScalar(u8, name, '.')) |dot| {
        if (dot == 0 or dot + 1 >= name.len) return "";
        return name[dot + 1 ..];
    }
    return "";
}

/// Native `for each="file_preview_line_rows"` row. `id` is the 1-based
/// line number (never 0). `text` is a slice into the preview buffer
/// with the newline stripped (a trailing `\r` is dropped). Empty lines
/// still get a number. Newline is a terminator: a trailing `\n` does
/// not add an extra empty row.
pub const FilePreviewLineRow = struct {
    id: u32,
    n_label: []const u8,
    text: []const u8,
};

/// Files-tree clamp (Waku 184/140/360). Kept for tests and hide/Files.
pub fn clampWidth(width: f32) f32 {
    return clampWidthTab(width, .files);
}

pub fn defaultWidth(tab: Tab) f32 {
    return switch (tab) {
        .files => main.right_panel_default_width,
        .diff, .browser, .terminal, .background => main.right_panel_diff_default_width,
    };
}

pub fn maxWidth(tab: Tab) f32 {
    return switch (tab) {
        .files => main.right_panel_max_width,
        .diff, .browser, .terminal, .background => main.right_panel_diff_max_width,
    };
}

pub fn clampWidthTab(width: f32, tab: Tab) f32 {
    const raw = if (width > 0) width else defaultWidth(tab);
    return @max(main.right_panel_min_width, @min(maxWidth(tab), raw));
}

pub fn restWidth(model: *const Model) f32 {
    const sidebar = if (model.sidebar_collapsed)
        main.sidebar_rail_width
    else if (model.sidebar_last_width > 0)
        model.sidebar_last_width
    else
        main.sidebar_default_width;
    return @max(1, main.window_width - sidebar);
}

pub fn splitForWidth(model: *const Model, width: f32) f32 {
    const rest = restWidth(model);
    const pane = clampWidthTab(width, model.right_panel_tab);
    const conversation = @max(0, rest - pane);
    return conversation / rest;
}

/// Restore open flag, tab, and width from sessions.json. Sets the tab
/// before clamping so Diff / Browser / Terminal / Background use the
/// wide max (not Files 360). When the panel is open on a wide tab,
/// bump toward 460 the same way `selectDiff` / `selectBrowser` /
/// `selectTerminal` / `selectBackground` would if the stored width is
/// still file-tree-narrow. Does not start Compare, refresh mentions,
/// or persist.
pub fn applyPersisted(model: *Model, open: bool, tab: Tab, width_px: u32) void {
    model.right_panel_open = open;
    model.right_panel_tab = tab;
    if (open and tab != .files) bumpWideTabWidth(model);
    if (width_px != 0) {
        model.right_panel_width = clampWidthTab(@floatFromInt(width_px), tab);
    } else {
        model.right_panel_width = clampWidthTab(model.right_panel_width, tab);
    }
    model.syncRightPanelSplit();
}

pub fn closedSplit() f32 {
    return 1.0;
}

/// Absolute `project_path` + cached relpath. Empty project or relpath
/// is a miss. Does not invent a file that is not in the cache.
pub fn joinProjectRelpath(project: []const u8, relpath: []const u8, buf: []u8) ?[]const u8 {
    const root = std.mem.trimEnd(u8, project, "/");
    const rel = std.mem.trimStart(u8, relpath, "/");
    if (root.len == 0 or rel.len == 0) return null;
    return std.fmt.bufPrint(buf, "{s}/{s}", .{ root, rel }) catch null;
}

pub fn hasProject(model: *const Model) bool {
    return file_mention.probePath(model).len > 0;
}

pub fn isLoading(model: *const Model) bool {
    return hasProject(model) and model.file_mention_key != 0 and model.file_mention_count == 0;
}

/// `derivedDirParents` spelling: no trailing slash. `src/` → `src`.
pub fn dirKey(path: []const u8) []const u8 {
    return std.mem.trimEnd(u8, path, "/");
}

/// True when every ancestor directory of `path` is in `expanded`.
/// Root files and top-level dirs (parent `""`) are always visible.
/// Unknown expanded keys are ignored.
pub fn ancestorsExpanded(path: []const u8, expanded: []const []const u8) bool {
    var parent = composer.fileMentionParent(path);
    while (parent.len > 0) {
        if (!containsKey(expanded, parent)) return false;
        parent = composer.fileMentionParent(parent);
    }
    return true;
}

fn containsKey(keys: []const []const u8, needle: []const u8) bool {
    for (keys) |item| {
        if (std.mem.eql(u8, item, needle)) return true;
    }
    return false;
}

pub fn expandedKeys(model: *const Model, buf: [][]const u8) []const []const u8 {
    const n = @min(model.right_panel_expanded_count, buf.len);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        buf[i] = model.right_panel_expanded_store[i].text();
    }
    return buf[0..n];
}

pub fn isDirExpanded(model: *const Model, path: []const u8) bool {
    const key = dirKey(path);
    if (key.len == 0) return false;
    var buf: [file_mention.max_file_mention_dirs][]const u8 = undefined;
    return containsKey(expandedKeys(model, &buf), key);
}

pub fn rows(model: *const Model, arena: std.mem.Allocator) []const RightPanelFileRow {
    if (!model.right_panel_open) return &.{};
    if (model.right_panel_tab != .files) return &.{};
    if (!hasProject(model)) return &.{};
    if (model.file_mention_count == 0) return &.{};

    var key_buf: [file_mention.max_file_mention_dirs][]const u8 = undefined;
    const expanded = expandedKeys(model, &key_buf);

    var parents: [file_mention.max_file_mention_dirs][]const u8 = undefined;
    const dir_n = file_mention.derivedDirParents(model, &parents);
    const file_n = model.file_mention_count;
    const cap = dir_n + file_n;
    const out = arena.alloc(RightPanelFileRow, cap) catch return &.{};
    var n: usize = 0;
    for (parents[0..dir_n], 0..) |parent, dir_index| {
        const path = std.fmt.allocPrint(arena, "{s}/", .{parent}) catch continue;
        if (!ancestorsExpanded(path, expanded)) continue;
        out[n] = makeRow(path, file_mention.dirMentionId(dir_index), false, containsKey(expanded, parent), false);
        n += 1;
    }
    var file_i: usize = 0;
    while (file_i < file_n) : (file_i += 1) {
        const path = file_mention.cachedPath(model, file_i);
        if (file_mention.isDirSentinel(path)) continue;
        if (!ancestorsExpanded(path, expanded)) continue;
        const file_id = file_mention.fileMentionId(file_i);
        out[n] = makeRow(path, file_id, true, false, model.right_panel_file_preview_id == file_id);
        n += 1;
    }
    const lessThan = struct {
        fn lessThan(_: void, a: RightPanelFileRow, b: RightPanelFileRow) bool {
            const order = std.mem.order(u8, a.path, b.path);
            if (order != .eq) return order == .lt;
            return a.id < b.id;
        }
    }.lessThan;
    std.mem.sort(RightPanelFileRow, out[0..n], {}, lessThan);
    return out[0..n];
}

fn makeRow(path: []const u8, id: u32, is_file: bool, expanded: bool, selected: bool) RightPanelFileRow {
    const name = composer.fileMentionBasename(path);
    const parent = composer.fileMentionParent(path);
    const depth = composer.fileMentionDepth(path);
    return .{
        .id = id,
        .path = path,
        .name = name,
        .parent = parent,
        .has_parent = parent.len > 0,
        .is_file = is_file,
        .expanded = expanded,
        .depth = depth,
        .has_indent = depth > 0,
        .indent = @as(f32, @floatFromInt(depth)) * indent_step,
        .selected = selected,
    };
}

/// Toggle a derived-dir id in the runtime expanded set. File ids and
/// missing dir ids are no-ops. Cap is `max_file_mention_dirs`.
/// When the last Files fill was daemon ListTree, re-prefers hello +
/// ListTree with the updated expand set (daemon does not return
/// children of collapsed dirs). Local fill stays filter-only.
pub fn toggleDir(model: *Model, fx: *Effects, id: u32) void {
    if (id < file_mention.file_mention_dir_id_base) return;
    var rel_buf: [file_mention.max_file_mention_path + 1]u8 = undefined;
    const rel = file_mention.mentionRelpath(model, id, &rel_buf) orelse return;
    const key = dirKey(rel);
    if (key.len == 0) return;
    if (indexOfExpanded(model, key)) |index| {
        removeExpandedAt(model, index);
        file_mention.refreshAfterExpand(model, fx);
        return;
    }
    if (model.right_panel_expanded_count >= file_mention.max_file_mention_dirs) return;
    model.right_panel_expanded_store[model.right_panel_expanded_count].set(key);
    model.right_panel_expanded_count += 1;
    file_mention.refreshAfterExpand(model, fx);
}

fn indexOfExpanded(model: *const Model, key: []const u8) ?usize {
    var i: usize = 0;
    while (i < model.right_panel_expanded_count) : (i += 1) {
        if (std.mem.eql(u8, model.right_panel_expanded_store[i].text(), key)) return i;
    }
    return null;
}

fn removeExpandedAt(model: *Model, index: usize) void {
    if (index >= model.right_panel_expanded_count) return;
    var i = index;
    while (i + 1 < model.right_panel_expanded_count) : (i += 1) {
        model.right_panel_expanded_store[i] = model.right_panel_expanded_store[i + 1];
    }
    model.right_panel_expanded_count -= 1;
}

/// Files tab. Opens the pane if closed. Clamps width to the file-tree max.
pub fn selectFiles(model: *Model, fx: *Effects) void {
    const was_open = model.right_panel_open;
    model.right_panel_open = true;
    model.right_panel_tab = .files;
    model.right_panel_width = clampWidthTab(model.right_panel_width, .files);
    model.syncRightPanelSplit();
    if (!was_open) file_mention.refresh(model, fx);
}

/// Diff tab. Opens the pane if closed, selects Diff, bumps width toward
/// 460 when still file-tree-narrow, and starts/refreshes Compare
/// (Uncommitted when none is active; keeps the current source otherwise).
pub fn selectDiff(model: *Model, fx: *Effects) void {
    const was_open = model.right_panel_open;
    model.right_panel_open = true;
    bumpWideTabWidth(model);
    model.right_panel_tab = .diff;
    model.right_panel_width = clampWidthTab(model.right_panel_width, .diff);
    model.syncRightPanelSplit();
    if (!was_open) file_mention.refresh(model, fx);
    review_diff.ensureDiff(model, fx);
}

/// Background tab. Opens the pane if closed, selects Background, and
/// bumps width toward 460 when still file-tree-narrow (same clamp as
/// Diff). Non-zero `row_id` stores the selected Environment Summary
/// row; `0` is the tab click (keep the current selection, empty
/// state when none / gone). Tab persists via layout extras; the
/// selected row does not.
pub fn selectBackground(model: *Model, fx: *Effects, row_id: u32) void {
    const was_open = model.right_panel_open;
    model.right_panel_open = true;
    if (row_id != 0) model.right_panel_background_row_id = row_id;
    bumpWideTabWidth(model);
    model.right_panel_tab = .background;
    model.right_panel_width = clampWidthTab(model.right_panel_width, .background);
    model.syncRightPanelSplit();
    if (!was_open) file_mention.refresh(model, fx);
}

/// Browser tab. Opens the pane if closed, selects Browser, and bumps
/// width toward 460 when still file-tree-narrow (same clamp as Diff).
/// Native has no webview; the body is an OS-open URL field. Tab and
/// draft URL persist via layout extras.
pub fn selectBrowser(model: *Model, fx: *Effects) void {
    const was_open = model.right_panel_open;
    model.right_panel_open = true;
    bumpWideTabWidth(model);
    model.right_panel_tab = .browser;
    model.right_panel_width = clampWidthTab(model.right_panel_width, .browser);
    model.syncRightPanelSplit();
    if (!was_open) file_mention.refresh(model, fx);
}

/// Terminal tab. Opens the pane if closed, selects Terminal, and bumps
/// width toward 460 when still file-tree-narrow (same clamp as Diff).
/// Native has no PTY; the body is Open in Terminal. Tab persists via
/// layout extras.
pub fn selectTerminal(model: *Model, fx: *Effects) void {
    const was_open = model.right_panel_open;
    model.right_panel_open = true;
    bumpWideTabWidth(model);
    model.right_panel_tab = .terminal;
    model.right_panel_width = clampWidthTab(model.right_panel_width, .terminal);
    model.syncRightPanelSplit();
    if (!was_open) file_mention.refresh(model, fx);
}

fn bumpWideTabWidth(model: *Model) void {
    if (model.right_panel_width <= main.right_panel_max_width) {
        model.right_panel_width = main.right_panel_diff_default_width;
    }
}

pub fn clearFilePreview(model: *Model) void {
    freePreviewBody(model);
    model.right_panel_file_preview_id = 0;
    model.right_panel_file_preview_relpath_len = 0;
    model.right_panel_file_preview_abs_len = 0;
    model.right_panel_file_preview_editing = false;
    model.file_preview_edit_buffer.clear();
    model.right_panel_file_preview_status_len = 0;
    model.file_preview_key = 0;
    model.file_preview_via_daemon = false;
    model.file_preview_daemon_ok = false;
    model.file_preview_save_key = 0;
    model.file_preview_save_via_daemon = false;
    model.file_preview_save_daemon_ok = false;
    model.file_preview_restore_editing = false;
    clearPreviewDiskFingerprint(model);
    model.file_preview_disk_poll_ms = null;
    clearPendingDiscard(model);
}

pub fn clearPendingDiscard(model: *Model) void {
    model.file_preview_pending_kind = .none;
    model.file_preview_pending_id = 0;
}

pub fn pendingDiscard(model: *const Model) PendingDiscard {
    return switch (model.file_preview_pending_kind) {
        .none => .none,
        .switch_file => .{ .switch_file = model.file_preview_pending_id },
        .close_preview => .close_preview,
        .hide_panel => .hide_panel,
        .switch_session => .{ .switch_session = model.file_preview_pending_id },
        .new_session => .new_session,
        .remove_session => .{ .remove_session = model.file_preview_pending_id },
    };
}

fn setPendingDiscard(model: *Model, intent: PendingDiscard) void {
    model.file_preview_pending_kind = switch (intent) {
        .none => .none,
        .switch_file => .switch_file,
        .close_preview => .close_preview,
        .hide_panel => .hide_panel,
        .switch_session => .switch_session,
        .new_session => .new_session,
        .remove_session => .remove_session,
    };
    model.file_preview_pending_id = switch (intent) {
        .switch_file => |id| id,
        .switch_session => |id| id,
        .remove_session => |id| id,
        else => 0,
    };
}

fn clearPendingIfClean(model: *Model) void {
    if (!isPreviewDirty(model)) clearPendingDiscard(model);
}

/// True when a discard action is parked and the preview is still dirty.
pub fn discardConfirmOpen(model: *const Model) bool {
    if (!isPreviewDirty(model)) return false;
    return model.file_preview_pending_kind != .none;
}

/// Park `intent` when the preview is dirty; otherwise clear any stale
/// park and tell the caller to proceed. Returns false when the dirty
/// editor must stay open.
pub fn beginDiscardOrPark(model: *Model, intent: PendingDiscard) bool {
    if (intent == .none) return true;
    if (!isPreviewDirty(model)) {
        clearPendingDiscard(model);
        return true;
    }
    setPendingDiscard(model, intent);
    return false;
}

/// Keep editing: drop the parked action, leave the dirty buffer.
pub fn cancelPendingDiscard(model: *Model) void {
    clearPendingDiscard(model);
}

/// Discard: drop the dirty buffer so nested paths proceed, and return
/// the parked intent for the caller to perform. No-op when none is parked.
pub fn acceptPendingDiscard(model: *Model) PendingDiscard {
    const intent = pendingDiscard(model);
    if (intent == .none) return .none;
    clearPendingDiscard(model);
    model.right_panel_file_preview_editing = false;
    model.file_preview_edit_buffer.clear();
    return intent;
}

/// Close preview. Parks a confirm when dirty instead of discarding.
pub fn closeFilePreview(model: *Model) void {
    if (!beginDiscardOrPark(model, .close_preview)) return;
    clearFilePreview(model);
}

fn freePreviewBody(model: *Model) void {
    if (model.right_panel_file_preview_storage.len != 0) {
        std.heap.page_allocator.free(model.right_panel_file_preview_storage);
    }
    model.right_panel_file_preview_storage = &.{};
    model.right_panel_file_preview_len = 0;
    model.right_panel_file_preview_truncated = false;
    model.right_panel_file_preview_binary = false;
    model.right_panel_file_preview_error_len = 0;
}

fn setPreviewStatus(model: *Model, message: []const u8) void {
    main.writeFixed(
        &model.right_panel_file_preview_status_storage,
        &model.right_panel_file_preview_status_len,
        message,
    );
}

/// Successful text load (including empty). Binary / read-error / closed
/// are not text.
pub fn previewTextOk(model: *const Model) bool {
    return model.right_panel_file_preview_id != 0
        and !model.right_panel_file_preview_binary
        and model.right_panel_file_preview_error_len == 0;
}

pub fn isPreviewDirty(model: *const Model) bool {
    if (!model.right_panel_file_preview_editing) return false;
    return !std.mem.eql(u8, model.file_preview_edit_buffer.text(), model.file_preview_body());
}

/// Edit is offered for a full text window with an abs path. Truncated
/// stays Open-in-editor + Reload (saving the 256KB window would clobber
/// the rest of the file).
pub fn canStartPreviewEdit(model: *const Model) bool {
    return previewTextOk(model)
        and model.right_panel_file_preview_abs_len > 0
        and !model.right_panel_file_preview_truncated
        and !model.right_panel_file_preview_editing;
}

pub fn canSavePreview(model: *const Model) bool {
    return model.right_panel_file_preview_editing
        and isPreviewDirty(model)
        and previewTextOk(model)
        and model.right_panel_file_preview_abs_len > 0
        and !model.right_panel_file_preview_truncated
        and !model.right_panel_file_preview_binary;
}

pub fn canReloadPreview(model: *const Model) bool {
    return model.right_panel_file_preview_id != 0 and model.right_panel_file_preview_abs_len > 0;
}

fn setPreviewError(model: *Model, message: []const u8) void {
    main.writeFixed(
        &model.right_panel_file_preview_error_storage,
        &model.right_panel_file_preview_error_len,
        message,
    );
}

fn previewReadError(err: anyerror) []const u8 {
    return switch (err) {
        error.FileNotFound => missing_file_label,
        else => unreadable_file_label,
    };
}

const PreviewWindow = struct {
    bytes: []u8,
    truncated: bool,
};

/// `readFileAlloc` + `.limited` errors with `StreamTooLong` when the file
/// size reaches the cap. That path then reads the first 256KB via
/// `File.Reader` and labels truncation from `stat`.
fn readPreviewWindow(io: std.Io, abs: []const u8) !PreviewWindow {
    const bytes = std.Io.Dir.cwd().readFileAlloc(
        io,
        abs,
        std.heap.page_allocator,
        .limited(max_file_preview_bytes),
    ) catch |err| {
        if (err != error.StreamTooLong) return err;
        return readCappedHead(io, abs);
    };
    return .{ .bytes = bytes, .truncated = false };
}

fn readCappedHead(io: std.Io, abs: []const u8) !PreviewWindow {
    var file = try std.Io.Dir.cwd().openFile(io, abs, .{});
    defer file.close(io);
    const size = (try file.stat(io)).size;
    const take: usize = @intCast(@min(size, max_file_preview_bytes));
    const truncated = size > max_file_preview_bytes;
    const buf = try std.heap.page_allocator.alloc(u8, take);
    errdefer std.heap.page_allocator.free(buf);
    if (take > 0) {
        var file_reader = file.reader(io, &.{});
        file_reader.interface.readSliceAll(buf) catch return error.Unexpected;
    }
    return .{ .bytes = buf, .truncated = truncated };
}

/// Longest valid UTF-8 prefix. `null` when a complete sequence is invalid
/// (including a NUL byte). Incomplete tail after a cap is dropped.
fn utf8PreviewPrefix(bytes: []const u8) ?[]const u8 {
    if (std.mem.indexOfScalar(u8, bytes, 0) != null) return null;
    var i: usize = 0;
    while (i < bytes.len) {
        const len = std.unicode.utf8ByteSequenceLength(bytes[i]) catch return null;
        if (i + len > bytes.len) return bytes[0..i];
        _ = std.unicode.utf8Decode(bytes[i..][0..len]) catch return null;
        i += len;
    }
    return bytes;
}

fn loadFilePreviewBodyLocal(model: *Model) void {
    const abs = model.right_panel_file_preview_abs_storage[0..model.right_panel_file_preview_abs_len];
    const io = model.store_io;
    if (io == null or abs.len == 0) {
        setPreviewError(model, unreadable_file_label);
        clearPreviewDiskFingerprint(model);
        return;
    }
    const read = readPreviewWindow(io.?, abs) catch |err| {
        setPreviewError(model, previewReadError(err));
        clearPreviewDiskFingerprint(model);
        return;
    };
    defer std.heap.page_allocator.free(read.bytes);

    const raw = if (read.truncated)
        read.bytes[0..@min(read.bytes.len, max_file_preview_bytes)]
    else
        read.bytes;
    paintPreviewWindow(model, raw, read.truncated);
}

/// Cap daemon `textFile.content` to the same 256KB window as local
/// `readPreviewWindow`, then paint UTF-8 / binary the same way.
fn paintPreviewContent(model: *Model, content: []const u8) void {
    const truncated = content.len > max_file_preview_bytes;
    const raw = if (truncated) content[0..max_file_preview_bytes] else content;
    paintPreviewWindow(model, raw, truncated);
}

fn paintPreviewWindow(model: *Model, raw: []const u8, truncated: bool) void {
    freePreviewBody(model);
    const window = utf8PreviewPrefix(raw) orelse {
        model.right_panel_file_preview_binary = true;
        refreshPreviewDiskFingerprint(model);
        return;
    };

    const buf = std.heap.page_allocator.alloc(u8, window.len) catch {
        setPreviewError(model, unreadable_file_label);
        return;
    };
    @memcpy(buf, window);
    model.right_panel_file_preview_storage = buf;
    model.right_panel_file_preview_len = window.len;
    model.right_panel_file_preview_truncated = truncated;
    refreshPreviewDiskFingerprint(model);
}

fn loadFilePreviewBody(model: *Model, fx: ?*Effects) void {
    if (fx) |effects| {
        if (trySpawnDaemonReadTextFile(model, effects)) {
            model.right_panel_file_preview_editing = false;
            return;
        }
    }
    loadFilePreviewBodyLocal(model);
    finishPreviewLoad(model);
}

fn finishPreviewLoad(model: *Model) void {
    if (model.file_preview_restore_editing and previewTextOk(model) and !model.right_panel_file_preview_truncated) {
        model.file_preview_edit_buffer.set(model.file_preview_body());
        model.right_panel_file_preview_editing = true;
    } else {
        model.right_panel_file_preview_editing = false;
        model.file_preview_edit_buffer.clear();
    }
    model.file_preview_restore_editing = false;
    model.right_panel_file_preview_status_len = 0;
    clearPendingIfClean(model);
}

fn cancelDaemonRead(model: *Model, fx: *Effects) void {
    if (model.file_preview_key == 0) return;
    fx.cancel(model.file_preview_key);
    model.file_preview_key = 0;
    model.file_preview_via_daemon = false;
    model.file_preview_daemon_ok = false;
}

fn cancelDaemonSave(model: *Model, fx: *Effects) void {
    if (model.file_preview_save_key == 0) return;
    fx.cancel(model.file_preview_save_key);
    model.file_preview_save_key = 0;
    model.file_preview_save_via_daemon = false;
    model.file_preview_save_daemon_ok = false;
}

/// Best-effort hello + `WorkspaceOperation::ReadTextFile` when a
/// daemon address is set. Own daemon spawn key so ListTree /
/// BrowseDirectory sidecars stay distinct. Missing address or
/// Native 4 KiB stdin overflow returns false and leaves local
/// `readFileAlloc`.
fn trySpawnDaemonReadTextFile(model: *Model, fx: *Effects) bool {
    const address = store.resolveDaemonMirrorAddress(model);
    if (address.len == 0) return false;
    const root = model.selectedProjectPath();
    const rel = model.right_panel_file_preview_relpath_storage[0..model.right_panel_file_preview_relpath_len];
    if (root.len == 0 or rel.len == 0) return false;

    var stdin_buf: [4096]u8 = undefined;
    const stdin = daemon_proxy.writeWorkspaceStdin(&stdin_buf, .{
        .token = model.daemonToken(),
        .operation = .{ .read_text_file = .{ .root = root, .relative_path = rel } },
    }) catch return false;

    cancelDaemonRead(model, fx);
    const key = model.next_daemon_key;
    model.next_daemon_key += 1;
    model.file_preview_key = key;
    model.file_preview_via_daemon = true;
    model.file_preview_daemon_ok = false;
    fx.spawn(.{
        .key = key,
        .argv = &.{ model.sidecarPath(), daemon_proxy.SUBCOMMAND, address },
        .stdin = stdin,
        .max_line_bytes = file_preview_daemon_line_bytes,
        .on_line = Effects.lineMsg(.fx_line),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
    return true;
}

pub fn applyDaemonLine(model: *Model, line: native_sdk.EffectLine) void {
    if (line.key != model.file_preview_key or model.file_preview_key == 0) return;
    if (!model.file_preview_via_daemon) return;
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const parsed = protocol.parseTextFile(arena_state.allocator(), line.line);
    if (!parsed.ok) return;
    paintPreviewContent(model, parsed.content);
    model.file_preview_daemon_ok = true;
    finishPreviewLoad(model);
}

pub fn handleDaemonExit(model: *Model, fx: *Effects, exit: native_sdk.EffectExit) void {
    if (exit.key != model.file_preview_key or model.file_preview_key == 0) return;
    const via = model.file_preview_via_daemon;
    const ok = model.file_preview_daemon_ok;
    model.file_preview_key = 0;
    model.file_preview_via_daemon = false;
    model.file_preview_daemon_ok = false;
    if (!via or ok) return;
    if (model.right_panel_file_preview_id == 0) return;
    loadFilePreviewBodyLocal(model);
    finishPreviewLoad(model);
    _ = fx;
}

/// Numbered preview rows for Native bind. Slices `text` from the
/// existing 256KB window; `n_label` is arena-owned. Empty when there
/// is no text body (binary / error / closed).
pub fn previewLineRows(model: *const Model, arena: std.mem.Allocator) []const FilePreviewLineRow {
    if (!model.file_preview_has_body()) return &.{};
    return previewLinesFromBody(model.file_preview_body(), arena);
}

/// Split a UTF-8 preview window into 1-based gutter rows.
///
/// Newline terminates a line: a trailing newline does not add an extra
/// empty row. Mid-file empty lines still get a number. A file that is
/// only a newline is one empty numbered row. Stops at
/// `max_file_preview_line_rows`.
pub fn previewLinesFromBody(body: []const u8, arena: std.mem.Allocator) []const FilePreviewLineRow {
    if (body.len == 0) return &.{};
    const out = arena.alloc(FilePreviewLineRow, max_file_preview_line_rows) catch return &.{};
    var n: usize = 0;
    var start: usize = 0;
    var i: usize = 0;
    while (i <= body.len and n < max_file_preview_line_rows) {
        const at_end = i == body.len;
        if (!at_end and body[i] != '\n') {
            i += 1;
            continue;
        }
        if (at_end and start == body.len) break;
        var text = body[start..i];
        if (text.len > 0 and text[text.len - 1] == '\r') {
            text = text[0 .. text.len - 1];
        }
        const line_id: u32 = @intCast(n + 1);
        const n_label = std.fmt.allocPrint(arena, "{d}", .{line_id}) catch return out[0..n];
        out[n] = .{
            .id = line_id,
            .n_label = n_label,
            .text = text,
        };
        n += 1;
        if (at_end) break;
        i += 1;
        start = i;
    }
    return out[0..n];
}

/// Files-pane file click: select the row and load a bounded read-only
/// inline preview. Prefers hello + daemon ReadTextFile when a daemon
/// address is set. Does not open an external editor.
pub fn selectCachedFile(model: *Model, fx: *Effects, id: u32) void {
    if (id == 0 or id >= file_mention.file_mention_dir_id_base) return;
    var rel_buf: [file_mention.max_file_mention_path + 1]u8 = undefined;
    const rel = file_mention.mentionRelpath(model, id, &rel_buf) orelse return;
    const project = model.selectedProjectPath();
    var abs_buf: [open_editor.max_open_path]u8 = undefined;
    const abs = joinProjectRelpath(project, rel, &abs_buf) orelse return;

    if (!beginDiscardOrPark(model, .{ .switch_file = id })) return;

    cancelDaemonRead(model, fx);
    cancelDaemonSave(model, fx);
    clearFilePreview(model);
    model.right_panel_file_preview_id = id;
    main.writeFixed(
        &model.right_panel_file_preview_relpath_storage,
        &model.right_panel_file_preview_relpath_len,
        rel,
    );
    main.writeFixed(
        &model.right_panel_file_preview_abs_storage,
        &model.right_panel_file_preview_abs_len,
        abs,
    );
    loadFilePreviewBody(model, fx);
}

/// Files-pane preview header: Open in editor at the stored absolute path.
pub fn openPreviewInEditor(model: *Model, fx: *Effects) void {
    if (model.right_panel_file_preview_id == 0) return;
    const abs = model.right_panel_file_preview_abs_storage[0..model.right_panel_file_preview_abs_len];
    if (abs.len == 0) return;
    open_editor.startOpenEditorAt(model, fx, abs);
}

/// Switch the open text preview to the composer `<textarea>`. No-op for
/// binary / error / truncated / missing abs path / already editing.
pub fn startFilePreviewEdit(model: *Model) void {
    if (!canStartPreviewEdit(model)) {
        if (model.right_panel_file_preview_truncated) {
            setPreviewStatus(model, truncated_save_label);
        } else if (model.right_panel_file_preview_binary) {
            setPreviewStatus(model, binary_save_label);
        }
        return;
    }
    model.file_preview_edit_buffer.set(model.file_preview_body());
    model.right_panel_file_preview_editing = true;
    model.right_panel_file_preview_status_len = 0;
}

pub fn applyFilePreviewEdit(model: *Model, edit: canvas.TextInputEvent) void {
    if (!model.right_panel_file_preview_editing) return;
    model.file_preview_edit_buffer.apply(edit);
    clearPendingIfClean(model);
}

fn atomicWriteAbs(io: std.Io, abs: []const u8, bytes: []const u8) !void {
    const cwd = std.Io.Dir.cwd();
    var atomic = try cwd.createFileAtomic(io, abs, .{ .make_path = false, .replace = true });
    defer atomic.deinit(io);
    try atomic.file.writePositionalAll(io, bytes, 0);
    try atomic.file.sync(io);
    try atomic.replace(io);
}

fn replacePreviewBody(model: *Model, bytes: []const u8) void {
    if (model.right_panel_file_preview_storage.len != 0) {
        std.heap.page_allocator.free(model.right_panel_file_preview_storage);
    }
    model.right_panel_file_preview_storage = &.{};
    model.right_panel_file_preview_len = 0;
    if (bytes.len == 0) return;
    const buf = std.heap.page_allocator.alloc(u8, bytes.len) catch {
        setPreviewError(model, unreadable_file_label);
        return;
    };
    @memcpy(buf, bytes);
    model.right_panel_file_preview_storage = buf;
    model.right_panel_file_preview_len = bytes.len;
}

fn adoptSavedPreview(model: *Model, bytes: []const u8) void {
    replacePreviewBody(model, bytes);
    model.right_panel_file_preview_truncated = false;
    model.right_panel_file_preview_binary = false;
    model.right_panel_file_preview_error_len = 0;
    model.right_panel_file_preview_editing = false;
    model.file_preview_edit_buffer.clear();
    model.right_panel_file_preview_status_len = 0;
    refreshPreviewDiskFingerprint(model);
    clearPendingDiscard(model);
}

fn saveFilePreviewLocal(model: *Model, bytes: []const u8) void {
    const io = model.store_io orelse {
        setPreviewStatus(model, cannot_save_label);
        return;
    };
    const abs = model.right_panel_file_preview_abs_storage[0..model.right_panel_file_preview_abs_len];
    atomicWriteAbs(io, abs, bytes) catch {
        setPreviewStatus(model, cannot_save_label);
        return;
    };
    adoptSavedPreview(model, bytes);
}

/// Best-effort hello + `WorkspaceOperation::WriteTextFile` when a
/// daemon address is set. Own daemon spawn key so an in-flight
/// ReadTextFile / ListTree / BrowseDirectory stays distinct. Missing
/// address or Native 4 KiB stdin overflow (`NoSpaceLeft` from
/// `writeWorkspaceStdin` / JSON wrapping of `content`) returns false
/// and leaves today's local atomic write.
fn trySpawnDaemonWriteTextFile(model: *Model, fx: *Effects, content: []const u8) bool {
    const address = store.resolveDaemonMirrorAddress(model);
    if (address.len == 0) return false;
    const root = model.selectedProjectPath();
    const rel = model.right_panel_file_preview_relpath_storage[0..model.right_panel_file_preview_relpath_len];
    if (root.len == 0 or rel.len == 0) return false;

    var stdin_buf: [4096]u8 = undefined;
    const stdin = daemon_proxy.writeWorkspaceStdin(&stdin_buf, .{
        .token = model.daemonToken(),
        .operation = .{
            .write_text_file = .{
                .root = root,
                .relative_path = rel,
                .content = content,
            },
        },
    }) catch return false;

    cancelDaemonSave(model, fx);
    const key = model.next_daemon_key;
    model.next_daemon_key += 1;
    model.file_preview_save_key = key;
    model.file_preview_save_via_daemon = true;
    model.file_preview_save_daemon_ok = false;
    fx.spawn(.{
        .key = key,
        .argv = &.{ model.sidecarPath(), daemon_proxy.SUBCOMMAND, address },
        .stdin = stdin,
        .max_line_bytes = main.daemon_line_bytes,
        .on_line = Effects.lineMsg(.fx_line),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
    return true;
}

pub fn applyDaemonSaveLine(model: *Model, line: native_sdk.EffectLine) void {
    if (line.key != model.file_preview_save_key or model.file_preview_save_key == 0) return;
    if (!model.file_preview_save_via_daemon) return;
    if (model.file_preview_save_daemon_ok) return;
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    if (!protocol.isWorkspaceAck(arena_state.allocator(), line.line)) return;
    model.file_preview_save_daemon_ok = true;
    if (!model.right_panel_file_preview_editing) return;
    adoptSavedPreview(model, model.file_preview_edit_buffer.text());
}

pub fn handleDaemonSaveExit(model: *Model, fx: *Effects, exit: native_sdk.EffectExit) void {
    if (exit.key != model.file_preview_save_key or model.file_preview_save_key == 0) return;
    const via = model.file_preview_save_via_daemon;
    const ok = model.file_preview_save_daemon_ok;
    model.file_preview_save_key = 0;
    model.file_preview_save_via_daemon = false;
    model.file_preview_save_daemon_ok = false;
    if (!via or ok) return;
    if (model.right_panel_file_preview_id == 0) return;
    if (!model.right_panel_file_preview_editing or !isPreviewDirty(model)) return;
    saveFilePreviewLocal(model, model.file_preview_edit_buffer.text());
    _ = fx;
}

/// Write the edit buffer to the stored abs path. Prefers hello +
/// daemon WriteTextFile when a daemon address is set. Gated: not
/// editing / not dirty / binary / no abs path / truncated refuse with
/// a short status (no daemon attempt). Success adopts the saved bytes
/// as the preview body and returns to the read-only `<code>` view.
/// Native 4 KiB stdin overflow / sidecar failure / non-ack falls back
/// to local `createFileAtomic`.
pub fn saveFilePreview(model: *Model, fx: *Effects) void {
    if (model.right_panel_file_preview_id == 0) return;
    if (model.right_panel_file_preview_binary) {
        setPreviewStatus(model, binary_save_label);
        return;
    }
    if (model.right_panel_file_preview_truncated) {
        setPreviewStatus(model, truncated_save_label);
        return;
    }
    if (model.right_panel_file_preview_abs_len == 0) {
        setPreviewStatus(model, cannot_save_label);
        return;
    }
    if (!model.right_panel_file_preview_editing or !isPreviewDirty(model)) return;

    const bytes = model.file_preview_edit_buffer.text();
    if (trySpawnDaemonWriteTextFile(model, fx, bytes)) return;
    saveFilePreviewLocal(model, bytes);
}

/// Re-read the stored abs path into the preview. Prefers daemon
/// ReadTextFile when an address is set. Discards unsaved edits
/// (the Reload click is the confirm; no dialog this cut). Stays in edit
/// mode when the reloaded window is still a full text body.
pub fn reloadFilePreview(model: *Model, fx: *Effects) void {
    if (!canReloadPreview(model)) return;
    model.file_preview_restore_editing = model.right_panel_file_preview_editing;
    cancelDaemonRead(model, fx);
    cancelDaemonSave(model, fx);
    freePreviewBody(model);
    loadFilePreviewBody(model, fx);
}

const PreviewDiskFingerprint = struct {
    size: u64,
    mtime_ns: i64,
};

/// Zig `File.Stat.mtime` is ns since epoch: a raw integer on some
/// std cuts, `Io.Timestamp{ .nanoseconds }` on others. Compile against
/// whichever this repo's Zig exposes.
fn mtimeToNs(mtime: anytype) i64 {
    return switch (@typeInfo(@TypeOf(mtime))) {
        .int => @intCast(mtime),
        .@"struct" => @intCast(mtime.nanoseconds),
        else => @compileError("unexpected File.Stat.mtime type"),
    };
}

fn statPreviewAbs(io: std.Io, abs: []const u8) !PreviewDiskFingerprint {
    var file = try std.Io.Dir.cwd().openFile(io, abs, .{});
    defer file.close(io);
    const st = try file.stat(io);
    return .{
        .size = st.size,
        .mtime_ns = mtimeToNs(st.mtime),
    };
}

fn clearPreviewDiskFingerprint(model: *Model) void {
    model.right_panel_file_preview_disk_size = 0;
    model.right_panel_file_preview_disk_mtime_ns = 0;
    model.right_panel_file_preview_disk_valid = false;
}

fn refreshPreviewDiskFingerprint(model: *Model) void {
    clearPreviewDiskFingerprint(model);
    const io = model.store_io orelse return;
    const abs = model.right_panel_file_preview_abs_storage[0..model.right_panel_file_preview_abs_len];
    if (abs.len == 0) return;
    const fp = statPreviewAbs(io, abs) catch return;
    model.right_panel_file_preview_disk_size = fp.size;
    model.right_panel_file_preview_disk_mtime_ns = fp.mtime_ns;
    model.right_panel_file_preview_disk_valid = true;
}

/// Poll the open Files preview's disk fingerprint on the TEA `update`
/// tick. No-op when closed, missing abs path, no `store_io`, dirty,
/// or a ReadTextFile / WriteTextFile sidecar is in flight. Throttled to
/// `file_preview_disk_poll_interval_ms` of `model.now_ms`.
/// Size or mtime change (or a failed stat after a previously valid
/// fingerprint) reuses `reloadFilePreview`. A daemon fill that could
/// not stat keeps `disk_valid` false and does not spam Reload.
/// Native has no FS watcher / dedicated timer this cut. Returns true
/// when a reload ran.
pub fn pollFilePreviewDisk(model: *Model, fx: *Effects) bool {
    if (model.right_panel_file_preview_id == 0) return false;
    if (model.right_panel_file_preview_abs_len == 0) return false;
    if (model.file_preview_key != 0) return false;
    if (model.file_preview_save_key != 0) return false;
    const io = model.store_io orelse return false;
    if (isPreviewDirty(model)) return false;

    if (model.file_preview_disk_poll_ms) |last| {
        if (model.now_ms >= last and model.now_ms - last < file_preview_disk_poll_interval_ms) {
            return false;
        }
    }
    model.file_preview_disk_poll_ms = model.now_ms;

    const abs = model.right_panel_file_preview_abs_storage[0..model.right_panel_file_preview_abs_len];
    const fp = statPreviewAbs(io, abs) catch {
        if (!model.right_panel_file_preview_disk_valid) return false;
        reloadFilePreview(model, fx);
        return true;
    };
    if (model.right_panel_file_preview_disk_valid and
        fp.size == model.right_panel_file_preview_disk_size and
        fp.mtime_ns == model.right_panel_file_preview_disk_mtime_ns)
    {
        return false;
    }
    reloadFilePreview(model, fx);
    return true;
}

pub fn openCachedFile(model: *Model, fx: *Effects, id: u32) void {
    selectCachedFile(model, fx, id);
}

test "file-tree widths match Waku DEFAULT_FILE_TREE / FILE_TREE_MIN / MAX" {
    try std.testing.expectEqual(@as(f32, 184), main.right_panel_default_width);
    try std.testing.expectEqual(@as(f32, 140), main.right_panel_min_width);
    try std.testing.expectEqual(@as(f32, 360), main.right_panel_max_width);
    try std.testing.expectEqual(@as(f32, 184), clampWidth(0));
    try std.testing.expectEqual(@as(f32, 140), clampWidth(100));
    try std.testing.expectEqual(@as(f32, 360), clampWidth(500));
    try std.testing.expectEqual(@as(f32, 200), clampWidth(200));
}

test "Diff tab default 460 / max 460; Browser Terminal Background share Diff clamp; Files clamp stays 360" {
    try std.testing.expectEqual(@as(f32, 460), main.right_panel_diff_default_width);
    try std.testing.expectEqual(@as(f32, 460), main.right_panel_diff_max_width);
    try std.testing.expectEqual(@as(f32, 460), clampWidthTab(0, .diff));
    try std.testing.expectEqual(@as(f32, 140), clampWidthTab(100, .diff));
    try std.testing.expectEqual(@as(f32, 460), clampWidthTab(500, .diff));
    try std.testing.expectEqual(@as(f32, 400), clampWidthTab(400, .diff));
    try std.testing.expectEqual(@as(f32, 460), clampWidthTab(0, .background));
    try std.testing.expectEqual(@as(f32, 140), clampWidthTab(100, .background));
    try std.testing.expectEqual(@as(f32, 460), clampWidthTab(500, .background));
    try std.testing.expectEqual(@as(f32, 400), clampWidthTab(400, .background));
    try std.testing.expectEqual(@as(f32, 460), clampWidthTab(0, .browser));
    try std.testing.expectEqual(@as(f32, 140), clampWidthTab(100, .browser));
    try std.testing.expectEqual(@as(f32, 460), clampWidthTab(500, .browser));
    try std.testing.expectEqual(@as(f32, 400), clampWidthTab(400, .browser));
    try std.testing.expectEqual(@as(f32, 460), clampWidthTab(0, .terminal));
    try std.testing.expectEqual(@as(f32, 140), clampWidthTab(100, .terminal));
    try std.testing.expectEqual(@as(f32, 460), clampWidthTab(500, .terminal));
    try std.testing.expectEqual(@as(f32, 400), clampWidthTab(400, .terminal));
    try std.testing.expectEqual(@as(f32, 360), clampWidthTab(400, .files));
    try std.testing.expectEqual(@as(f32, 360), clampWidthTab(460, .files));
}

test "tab persist names are stable lowercase; missing unknown is files" {
    try std.testing.expectEqualStrings("files", Tab.files.persistName());
    try std.testing.expectEqualStrings("diff", Tab.diff.persistName());
    try std.testing.expectEqualStrings("browser", Tab.browser.persistName());
    try std.testing.expectEqualStrings("terminal", Tab.terminal.persistName());
    try std.testing.expectEqualStrings("background", Tab.background.persistName());
    try std.testing.expectEqual(Tab.files, Tab.fromPersist(""));
    try std.testing.expectEqual(Tab.files, Tab.fromPersist("nope"));
    try std.testing.expectEqual(Tab.files, Tab.fromPersist("Files"));
    try std.testing.expectEqual(Tab.files, Tab.fromPersist("files"));
    try std.testing.expectEqual(Tab.diff, Tab.fromPersist("diff"));
    try std.testing.expectEqual(Tab.browser, Tab.fromPersist("browser"));
    try std.testing.expectEqual(Tab.terminal, Tab.fromPersist("terminal"));
    try std.testing.expectEqual(Tab.background, Tab.fromPersist("background"));
}

test "applyPersisted restores wide tabs at Diff max, not Files 360" {
    var model = Model{};
    applyPersisted(&model, true, .diff, 460);
    try std.testing.expect(model.right_panel_open);
    try std.testing.expectEqual(Tab.diff, model.right_panel_tab);
    try std.testing.expectEqual(@as(f32, 460), model.right_panel_width);

    var browser = Model{};
    applyPersisted(&browser, true, .browser, 460);
    try std.testing.expectEqual(Tab.browser, browser.right_panel_tab);
    try std.testing.expectEqual(@as(f32, 460), browser.right_panel_width);

    var terminal = Model{};
    applyPersisted(&terminal, true, .terminal, 460);
    try std.testing.expectEqual(Tab.terminal, terminal.right_panel_tab);
    try std.testing.expectEqual(@as(f32, 460), terminal.right_panel_width);

    var background = Model{};
    applyPersisted(&background, true, .background, 460);
    try std.testing.expectEqual(Tab.background, background.right_panel_tab);
    try std.testing.expectEqual(@as(f32, 460), background.right_panel_width);

    var files = Model{};
    applyPersisted(&files, true, .files, 460);
    try std.testing.expectEqual(Tab.files, files.right_panel_tab);
    try std.testing.expectEqual(@as(f32, 360), files.right_panel_width);
}

test "tab defaults to files; Diff Background Browser Terminal open the panel; Files↔wide tabs clamp width" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    try std.testing.expect(!model.right_panel_open);
    try std.testing.expectEqual(Tab.files, model.right_panel_tab);
    try std.testing.expectEqual(@as(f32, 184), model.right_panel_width);

    selectDiff(&model, &fx);
    try std.testing.expect(model.right_panel_open);
    try std.testing.expectEqual(Tab.diff, model.right_panel_tab);
    try std.testing.expectEqual(@as(f32, 460), model.right_panel_width);
    try std.testing.expect(model.right_panel_split < 1.0);

    selectFiles(&model, &fx);
    try std.testing.expect(model.right_panel_open);
    try std.testing.expectEqual(Tab.files, model.right_panel_tab);
    try std.testing.expectEqual(@as(f32, 360), model.right_panel_width);

    selectDiff(&model, &fx);
    try std.testing.expectEqual(Tab.diff, model.right_panel_tab);
    try std.testing.expectEqual(@as(f32, 460), model.right_panel_width);

    model.right_panel_width = 400;
    selectFiles(&model, &fx);
    try std.testing.expectEqual(@as(f32, 360), model.right_panel_width);

    selectBackground(&model, &fx, 0);
    try std.testing.expect(model.right_panel_open);
    try std.testing.expectEqual(Tab.background, model.right_panel_tab);
    try std.testing.expectEqual(@as(f32, 460), model.right_panel_width);
    try std.testing.expectEqual(@as(u32, 0), model.right_panel_background_row_id);

    selectBackground(&model, &fx, 1);
    try std.testing.expectEqual(Tab.background, model.right_panel_tab);
    try std.testing.expectEqual(@as(u32, 1), model.right_panel_background_row_id);
    try std.testing.expectEqual(@as(f32, 460), model.right_panel_width);

    selectBackground(&model, &fx, 0);
    try std.testing.expectEqual(@as(u32, 1), model.right_panel_background_row_id);

    selectBrowser(&model, &fx);
    try std.testing.expect(model.right_panel_open);
    try std.testing.expectEqual(Tab.browser, model.right_panel_tab);
    try std.testing.expectEqual(@as(f32, 460), model.right_panel_width);
    try std.testing.expectEqual(@as(u32, 1), model.right_panel_background_row_id);

    selectTerminal(&model, &fx);
    try std.testing.expectEqual(Tab.terminal, model.right_panel_tab);
    try std.testing.expectEqual(@as(f32, 460), model.right_panel_width);

    selectFiles(&model, &fx);
    try std.testing.expectEqual(Tab.files, model.right_panel_tab);
    try std.testing.expectEqual(@as(f32, 360), model.right_panel_width);
    try std.testing.expectEqual(@as(u32, 1), model.right_panel_background_row_id);

    selectDiff(&model, &fx);
    try std.testing.expectEqual(Tab.diff, model.right_panel_tab);

    model.hideRightPanel();
    try std.testing.expect(!model.right_panel_open);
    try std.testing.expectEqual(Tab.files, model.right_panel_tab);
    try std.testing.expectEqual(@as(f32, 360), model.right_panel_width);
}

test "Diff keeps an active Compare source; Uncommitted is the empty default" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, "/tmp/faku-diff-tab-{s}", .{tmp.sub_path});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("diff tab", .fx);
    model.selected = id;
    model.setSelectedProjectPath(project);

    selectDiff(&model, &fx);
    try std.testing.expect(model.review_diff_active);
    try std.testing.expectEqual(review_diff.Source.uncommitted, model.review_diff_source);
    try std.testing.expect(model.review_diff_key >= review_diff.review_diff_key_first);
    const first_key = model.review_diff_key;

    review_diff.setSource(&model, &fx, .branch);
    try std.testing.expectEqual(review_diff.Source.branch, model.review_diff_source);
    try std.testing.expect(model.review_diff_key != first_key);

    selectFiles(&model, &fx);
    try std.testing.expectEqual(Tab.files, model.right_panel_tab);
    try std.testing.expect(model.review_diff_active);
    try std.testing.expectEqual(review_diff.Source.branch, model.review_diff_source);

    const branch_key = model.review_diff_key;
    selectDiff(&model, &fx);
    try std.testing.expectEqual(Tab.diff, model.right_panel_tab);
    try std.testing.expectEqual(review_diff.Source.branch, model.review_diff_source);
    try std.testing.expect(model.review_diff_key != branch_key);
}

test "joinProjectRelpath joins root and relpath; empty sides miss" {
    var buf: [64]u8 = undefined;
    try std.testing.expectEqualStrings("/tmp/proj/src/main.zig", joinProjectRelpath("/tmp/proj", "src/main.zig", &buf).?);
    try std.testing.expectEqualStrings("/tmp/proj/src/main.zig", joinProjectRelpath("/tmp/proj/", "/src/main.zig", &buf).?);
    try std.testing.expect(joinProjectRelpath("", "src/main.zig", &buf) == null);
    try std.testing.expect(joinProjectRelpath("/tmp/proj", "", &buf) == null);
}

test "dirKey strips a trailing slash; ancestorsExpanded is collapsed by default" {
    try std.testing.expectEqualStrings("src", dirKey("src/"));
    try std.testing.expectEqualStrings("src/lib", dirKey("src/lib/"));
    try std.testing.expectEqualStrings("src/main.zig", dirKey("src/main.zig"));
    const none = [_][]const u8{};
    try std.testing.expect(ancestorsExpanded("README.md", &none));
    try std.testing.expect(ancestorsExpanded("src/", &none));
    try std.testing.expect(!ancestorsExpanded("src/main.zig", &none));
    try std.testing.expect(!ancestorsExpanded("src/lib/", &none));
    try std.testing.expect(!ancestorsExpanded("src/lib/a.zig", &none));
    const src_only = [_][]const u8{"src"};
    try std.testing.expect(ancestorsExpanded("src/main.zig", &src_only));
    try std.testing.expect(ancestorsExpanded("src/lib/", &src_only));
    try std.testing.expect(!ancestorsExpanded("src/lib/a.zig", &src_only));
    const nested = [_][]const u8{ "src", "src/lib" };
    try std.testing.expect(ancestorsExpanded("src/lib/a.zig", &nested));
    const stale = [_][]const u8{"src/lib"};
    try std.testing.expect(!ancestorsExpanded("src/lib/a.zig", &stale));
}

test "rows are empty when closed or without a cache" {
    var model = Model{};
    try std.testing.expect(!model.right_panel_open);
    try std.testing.expectEqual(@as(usize, 0), rows(&model, std.testing.allocator).len);

    model.right_panel_open = true;
    try std.testing.expectEqual(@as(usize, 0), rows(&model, std.testing.allocator).len);
}

test "collapsed default, expand shows children, collapse hides descendants" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, "/tmp/faku-files-tree-{s}", .{tmp.sub_path});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("tree", .fx);
    model.selected = id;
    model.setSelectedProjectPath(project);
    model.right_panel_open = true;
    file_mention.applyStdoutPaths(&model,
        \\src/lib/a.zig
        \\src/main.zig
        \\README.md
    );

    var parents: [file_mention.max_file_mention_dirs][]const u8 = undefined;
    const dir_n = file_mention.derivedDirParents(&model, &parents);
    try std.testing.expectEqual(@as(usize, 2), dir_n);
    try std.testing.expectEqualStrings("src/lib", parents[0]);
    try std.testing.expectEqualStrings("src", parents[1]);
    const src_lib_id = file_mention.dirMentionId(0);
    const src_id = file_mention.dirMentionId(1);

    {
        const visible = rows(&model, arena);
        try std.testing.expectEqual(@as(usize, 2), visible.len);
        try std.testing.expectEqualStrings("README.md", visible[0].path);
        try std.testing.expect(visible[0].is_file);
        try std.testing.expectEqual(@as(u32, 0), visible[0].depth);
        try std.testing.expectEqualStrings("src/", visible[1].path);
        try std.testing.expect(!visible[1].is_file);
        try std.testing.expect(!visible[1].expanded);
        try std.testing.expectEqual(src_id, visible[1].id);
        try std.testing.expectEqual(@as(u32, 0), visible[1].depth);
    }

    toggleDir(&model, &fx, src_id);
    try std.testing.expect(isDirExpanded(&model, "src/"));
    {
        const visible = rows(&model, arena);
        try std.testing.expectEqual(@as(usize, 4), visible.len);
        try std.testing.expectEqualStrings("README.md", visible[0].path);
        try std.testing.expectEqualStrings("src/", visible[1].path);
        try std.testing.expect(visible[1].expanded);
        try std.testing.expectEqualStrings("src/lib/", visible[2].path);
        try std.testing.expect(!visible[2].expanded);
        try std.testing.expectEqual(src_lib_id, visible[2].id);
        try std.testing.expectEqual(@as(u32, 1), visible[2].depth);
        try std.testing.expect(visible[2].has_indent);
        try std.testing.expectEqual(indent_step, visible[2].indent);
        try std.testing.expectEqualStrings("src/main.zig", visible[3].path);
        try std.testing.expect(visible[3].is_file);
        try std.testing.expect(!visible[3].expanded);
    }

    toggleDir(&model, &fx, src_lib_id);
    {
        const visible = rows(&model, arena);
        try std.testing.expectEqual(@as(usize, 5), visible.len);
        try std.testing.expectEqualStrings("src/lib/a.zig", visible[3].path);
        try std.testing.expectEqual(@as(u32, 2), visible[3].depth);
        try std.testing.expectEqualStrings("src/main.zig", visible[4].path);
    }

    toggleDir(&model, &fx, src_id);
    try std.testing.expect(!isDirExpanded(&model, "src/"));
    {
        const visible = rows(&model, arena);
        try std.testing.expectEqual(@as(usize, 2), visible.len);
        try std.testing.expectEqualStrings("README.md", visible[0].path);
        try std.testing.expectEqualStrings("src/", visible[1].path);
        try std.testing.expect(isDirExpanded(&model, "src/lib/"));
    }

    toggleDir(&model, &fx, 0);
    toggleDir(&model, &fx, 1);
    toggleDir(&model, &fx, file_mention.dirMentionId(99));
    try std.testing.expectEqual(@as(u32, 1), model.right_panel_expanded_count);

    openCachedFile(&model, &fx, src_id);
    try std.testing.expect(fx.pendingSpawnAt(0) == null);
    openCachedFile(&model, &fx, 1);
    try std.testing.expect(fx.pendingSpawnAt(0) == null);
    try std.testing.expectEqual(@as(u32, 1), model.right_panel_file_preview_id);
    openPreviewInEditor(&model, &fx);
    try std.testing.expect(fx.pendingSpawnAt(0) != null);

    model.hideRightPanel();
    try std.testing.expectEqual(@as(u32, 0), model.right_panel_expanded_count);
    model.showRightPanel();
    try std.testing.expectEqual(@as(usize, 2), rows(&model, arena).len);

    toggleDir(&model, &fx, src_id);
    try std.testing.expectEqual(@as(u32, 1), model.right_panel_expanded_count);
    file_mention.clearCache(&model);
    try std.testing.expectEqual(@as(u32, 0), model.right_panel_expanded_count);
}

fn writePreviewFile(io: std.Io, abs: []const u8, data: []const u8) !void {
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = abs, .data = data });
}

fn pickFile(model: *Model, id: u32) void {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;
    selectCachedFile(model, &fx, id);
}

fn savePreview(model: *Model) void {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;
    saveFilePreview(model, &fx);
}

fn reloadPreview(model: *Model) void {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;
    reloadFilePreview(model, &fx);
}

fn pollPreview(model: *Model) bool {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;
    return pollFilePreviewDisk(model, &fx);
}

test "inline preview caps at 256KB and labels truncation" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, "/tmp/faku-preview-cap-{s}", .{tmp.sub_path});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var path_buf: [300]u8 = undefined;
    const abs = try std.fmt.bufPrint(&path_buf, "{s}/big.txt", .{project});
    const over = max_file_preview_bytes + 8;
    const blob = try std.testing.allocator.alloc(u8, over);
    defer std.testing.allocator.free(blob);
    @memset(blob, 'a');
    try writePreviewFile(std.testing.io, abs, blob);

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("preview cap", .fx);
    model.selected = id;
    model.setSelectedProjectPath(project);
    model.right_panel_open = true;
    file_mention.applyStdoutPaths(&model, "big.txt\n");
    defer clearFilePreview(&model);

    pickFile(&model, 1);
    try std.testing.expectEqual(@as(u32, 1), model.right_panel_file_preview_id);
    try std.testing.expect(model.file_preview_truncated());
    try std.testing.expectEqual(max_file_preview_bytes, model.right_panel_file_preview_len);
    try std.testing.expect(!model.file_preview_binary());
    try std.testing.expectEqualStrings("big.txt", model.file_preview_path());
    try std.testing.expectEqualStrings("plain", model.file_preview_language());
    {
        var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena_state.deinit();
        const lines = model.file_preview_line_rows(arena_state.allocator());
        try std.testing.expectEqual(@as(usize, 1), lines.len);
        try std.testing.expectEqualStrings("1", lines[0].n_label);
        try std.testing.expectEqual(max_file_preview_bytes, lines[0].text.len);
    }
}

test "inline preview rejects NUL and invalid UTF-8" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, "/tmp/faku-preview-bin-{s}", .{tmp.sub_path});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var nul_buf: [300]u8 = undefined;
    const nul_abs = try std.fmt.bufPrint(&nul_buf, "{s}/nul.bin", .{project});
    try writePreviewFile(std.testing.io, nul_abs, "ok\x00still");

    var bad_buf: [300]u8 = undefined;
    const bad_abs = try std.fmt.bufPrint(&bad_buf, "{s}/bad.txt", .{project});
    try writePreviewFile(std.testing.io, bad_abs, "ok\xff");

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("preview bin", .fx);
    model.selected = id;
    model.setSelectedProjectPath(project);
    model.right_panel_open = true;
    file_mention.applyStdoutPaths(&model, "nul.bin\nbad.txt\n");
    defer clearFilePreview(&model);

    pickFile(&model, 1);
    try std.testing.expect(model.file_preview_binary());
    try std.testing.expectEqual(@as(usize, 0), model.right_panel_file_preview_len);
    try std.testing.expectEqualStrings(binary_file_label, binary_file_label);
    try std.testing.expectEqual(@as(usize, 0), model.file_preview_line_rows(std.testing.allocator).len);

    pickFile(&model, 2);
    try std.testing.expect(model.file_preview_binary());
    try std.testing.expectEqual(@as(usize, 0), model.right_panel_file_preview_len);
    try std.testing.expectEqual(@as(usize, 0), model.file_preview_line_rows(std.testing.allocator).len);
}

test "inline preview missing path is a one-line error" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, "/tmp/faku-preview-miss-{s}", .{tmp.sub_path});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("preview miss", .fx);
    model.selected = id;
    model.setSelectedProjectPath(project);
    model.right_panel_open = true;
    file_mention.applyStdoutPaths(&model, "gone.txt\n");
    defer clearFilePreview(&model);

    pickFile(&model, 1);
    try std.testing.expect(model.file_preview_has_error());
    try std.testing.expectEqualStrings(missing_file_label, model.file_preview_error());
    try std.testing.expectEqual(@as(usize, 0), model.right_panel_file_preview_len);
    try std.testing.expect(!model.file_preview_binary());
    try std.testing.expectEqual(@as(usize, 0), model.file_preview_line_rows(std.testing.allocator).len);
}

test "inline preview close, hide, and session switch free the heap buffer" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, "/tmp/faku-preview-free-{s}", .{tmp.sub_path});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);
    var path_buf: [300]u8 = undefined;
    const abs = try std.fmt.bufPrint(&path_buf, "{s}/note.txt", .{project});
    try writePreviewFile(std.testing.io, abs, "hello\nworld\n");

    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = std.testing.io;
    const first = model.addSession("preview free", .fx);
    const second = model.addSession("other", .fx);
    model.selected = first;
    model.setSelectedProjectPath(project);
    model.right_panel_open = true;
    file_mention.applyStdoutPaths(&model, "note.txt\n");

    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    pickFile(&model, 1);
    try std.testing.expect(model.file_preview_has_body());
    try std.testing.expectEqualStrings("hello\nworld\n", model.file_preview_body());
    try std.testing.expectEqualStrings("plain", model.file_preview_language());
    try std.testing.expect(model.right_panel_file_preview_storage.len != 0);
    {
        const lines = model.file_preview_line_rows(arena);
        try std.testing.expectEqual(@as(usize, 2), lines.len);
        try std.testing.expectEqualStrings("1", lines[0].n_label);
        try std.testing.expectEqualStrings("hello", lines[0].text);
        try std.testing.expectEqualStrings("2", lines[1].n_label);
        try std.testing.expectEqualStrings("world", lines[1].text);
    }

    clearFilePreview(&model);
    try std.testing.expectEqual(@as(u32, 0), model.right_panel_file_preview_id);
    try std.testing.expectEqual(@as(usize, 0), model.right_panel_file_preview_storage.len);
    try std.testing.expectEqual(@as(usize, 0), model.file_preview_line_rows(arena).len);

    pickFile(&model, 1);
    try std.testing.expect(model.right_panel_file_preview_storage.len != 0);
    model.hideRightPanel();
    try std.testing.expectEqual(@as(u32, 0), model.right_panel_file_preview_id);
    try std.testing.expectEqual(@as(usize, 0), model.right_panel_file_preview_storage.len);
    try std.testing.expectEqual(@as(usize, 0), model.file_preview_line_rows(arena).len);

    model.showRightPanel();
    pickFile(&model, 1);
    try std.testing.expect(model.right_panel_file_preview_storage.len != 0);
    const palette_run = @import("palette_run.zig");
    palette_run.applySessionSelection(&model, &fx, second);
    try std.testing.expectEqual(@as(u32, 0), model.right_panel_file_preview_id);
    try std.testing.expectEqual(@as(usize, 0), model.right_panel_file_preview_storage.len);
    try std.testing.expectEqual(@as(usize, 0), model.file_preview_line_rows(arena).len);

    model.selected = first;
    model.setSelectedProjectPath(project);
    file_mention.applyStdoutPaths(&model, "note.txt\n");
    pickFile(&model, 1);
    var editor_fx = Effects.init(std.testing.allocator);
    defer editor_fx.deinit();
    editor_fx.executor = .fake;
    openPreviewInEditor(&model, &editor_fx);
    const spawn = editor_fx.pendingSpawnAt(0) orelse return error.MissingOpenEditorSpawn;
    try std.testing.expect(open_editor.isEditorArgv(spawn.argv));
    try std.testing.expectEqualStrings(abs, spawn.argv[1]);
    clearFilePreview(&model);
}

test "preview gutter numbers 1..N; trailing newline is a terminator; empty lines keep a number" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    {
        const lines = previewLinesFromBody("hello\nworld\n", arena);
        try std.testing.expectEqual(@as(usize, 2), lines.len);
        try std.testing.expectEqual(@as(u32, 1), lines[0].id);
        try std.testing.expectEqualStrings("1", lines[0].n_label);
        try std.testing.expectEqualStrings("hello", lines[0].text);
        try std.testing.expectEqual(@as(u32, 2), lines[1].id);
        try std.testing.expectEqualStrings("2", lines[1].n_label);
        try std.testing.expectEqualStrings("world", lines[1].text);
    }
    {
        const lines = previewLinesFromBody("hello\n\nworld\n", arena);
        try std.testing.expectEqual(@as(usize, 3), lines.len);
        try std.testing.expectEqualStrings("hello", lines[0].text);
        try std.testing.expectEqualStrings("", lines[1].text);
        try std.testing.expectEqualStrings("2", lines[1].n_label);
        try std.testing.expectEqualStrings("world", lines[2].text);
    }
    {
        const lines = previewLinesFromBody("solo", arena);
        try std.testing.expectEqual(@as(usize, 1), lines.len);
        try std.testing.expectEqualStrings("1", lines[0].n_label);
        try std.testing.expectEqualStrings("solo", lines[0].text);
    }
    {
        const lines = previewLinesFromBody("\n", arena);
        try std.testing.expectEqual(@as(usize, 1), lines.len);
        try std.testing.expectEqualStrings("1", lines[0].n_label);
        try std.testing.expectEqualStrings("", lines[0].text);
    }
    {
        const lines = previewLinesFromBody("a\r\nb\r\n", arena);
        try std.testing.expectEqual(@as(usize, 2), lines.len);
        try std.testing.expectEqualStrings("a", lines[0].text);
        try std.testing.expectEqualStrings("b", lines[1].text);
    }
    {
        const lines = previewLinesFromBody("", arena);
        try std.testing.expectEqual(@as(usize, 0), lines.len);
    }
}

test "preview gutter materializes at most max_file_preview_line_rows" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const over = max_file_preview_line_rows + 2;
    const blob = try std.testing.allocator.alloc(u8, over * 2);
    defer std.testing.allocator.free(blob);
    var i: usize = 0;
    while (i < over) : (i += 1) {
        blob[i * 2] = 'x';
        blob[i * 2 + 1] = '\n';
    }
    const lines = previewLinesFromBody(blob, arena);
    try std.testing.expectEqual(max_file_preview_line_rows, lines.len);
    try std.testing.expectEqual(@as(u32, 1), lines[0].id);
    try std.testing.expectEqualStrings("x", lines[0].text);
    try std.testing.expectEqual(@as(u32, @intCast(max_file_preview_line_rows)), lines[lines.len - 1].id);
    try std.testing.expectEqualStrings("x", lines[lines.len - 1].text);
}

test "preview language maps documented extensions; unknown and well-known names are plain" {
    const code = native_sdk.canvas.code;

    try std.testing.expectEqualStrings("zig", previewLanguage("src/main.zig"));
    try std.testing.expectEqual(code.Language.zig, code.languageFromName(previewLanguage("src/main.zig")));
    try std.testing.expectEqualStrings("javascript", previewLanguage("app.js"));
    try std.testing.expectEqualStrings("javascript", previewLanguage("mod.mjs"));
    try std.testing.expectEqualStrings("typescript", previewLanguage("src/index.ts"));
    try std.testing.expectEqualStrings("tsx", previewLanguage("Button.tsx"));
    try std.testing.expectEqualStrings("jsx", previewLanguage("view.jsx"));
    try std.testing.expectEqualStrings("json", previewLanguage("package.json"));
    try std.testing.expectEqualStrings("yaml", previewLanguage("compose.yml"));
    try std.testing.expectEqualStrings("shell", previewLanguage("scripts/install.sh"));
    try std.testing.expectEqualStrings("python", previewLanguage("main.py"));
    try std.testing.expectEqualStrings("rust", previewLanguage("src/lib.rs"));
    try std.testing.expectEqualStrings("c", previewLanguage("foo.c"));
    try std.testing.expectEqualStrings("c", previewLanguage("bar.cpp"));
    try std.testing.expectEqualStrings("c", previewLanguage("Main.java"));
    try std.testing.expectEqualStrings("go", previewLanguage("main.go"));
    try std.testing.expectEqualStrings("html", previewLanguage("index.html"));
    try std.testing.expectEqualStrings("html", previewLanguage("icon.svg"));
    try std.testing.expectEqualStrings("css", previewLanguage("theme.css"));
    try std.testing.expectEqualStrings("sql", previewLanguage("schema.sql"));
    try std.testing.expectEqualStrings("markdown", previewLanguage("README.md"));
    try std.testing.expectEqualStrings("plain", previewLanguage("Dockerfile"));
    try std.testing.expectEqualStrings("plain", previewLanguage("Makefile"));
    try std.testing.expectEqualStrings("plain", previewLanguage("Cargo.toml"));
    try std.testing.expectEqualStrings("plain", previewLanguage("notes.txt"));
    try std.testing.expectEqualStrings("plain", previewLanguage("lock.foo"));
    try std.testing.expect(code.isLanguageName(previewLanguage("src/main.zig")));
    try std.testing.expect(code.isLanguageName(previewLanguage("Dockerfile")));
    try std.testing.expectEqual(code.Language.plain, code.languageFromName(previewLanguage("Cargo.toml")));
    try std.testing.expectEqual(code.Language.javascript, code.languageFromName(previewLanguage("app.js")));
    try std.testing.expectEqual(code.Language.c_like, code.languageFromName(previewLanguage("foo.c")));
}

test "edit buffer dirty/save gates; save writes abs path and returns to read-only" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, "/tmp/faku-preview-save-{s}", .{tmp.sub_path});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);
    var path_buf: [300]u8 = undefined;
    const abs = try std.fmt.bufPrint(&path_buf, "{s}/note.txt", .{project});
    try writePreviewFile(std.testing.io, abs, "hello\n");

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("preview save", .fx);
    model.selected = id;
    model.setSelectedProjectPath(project);
    model.right_panel_open = true;
    file_mention.applyStdoutPaths(&model, "note.txt\n");
    defer clearFilePreview(&model);

    pickFile(&model, 1);
    try std.testing.expect(model.file_preview_can_edit());
    try std.testing.expect(!model.file_preview_editing());
    try std.testing.expect(!model.file_preview_dirty());
    try std.testing.expect(!model.file_preview_can_save());
    try std.testing.expect(model.file_preview_can_reload());

    savePreview(&model);
    try std.testing.expectEqualStrings("hello\n", model.file_preview_body());

    startFilePreviewEdit(&model);
    try std.testing.expect(model.file_preview_editing());
    try std.testing.expect(!model.file_preview_can_edit());
    try std.testing.expect(!model.file_preview_dirty());
    try std.testing.expect(!model.file_preview_can_save());
    try std.testing.expectEqualStrings("hello\n", model.file_preview_draft());

    applyFilePreviewEdit(&model, .{ .insert_text = "world\n" });
    try std.testing.expect(model.file_preview_dirty());
    try std.testing.expect(model.file_preview_can_save());
    try std.testing.expectEqualStrings("hello\nworld\n", model.file_preview_draft());
    try std.testing.expectEqualStrings("hello\n", model.file_preview_body());

    savePreview(&model);
    try std.testing.expect(!model.file_preview_editing());
    try std.testing.expect(!model.file_preview_dirty());
    try std.testing.expect(!model.file_preview_can_save());
    try std.testing.expect(model.file_preview_can_edit());
    try std.testing.expectEqualStrings("hello\nworld\n", model.file_preview_body());
    try std.testing.expectEqual(@as(usize, 0), model.file_preview_draft().len);

    const got = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, abs, std.testing.allocator, .limited(64));
    defer std.testing.allocator.free(got);
    try std.testing.expectEqualStrings("hello\nworld\n", got);
}

test "reload discards dirty buffer; truncated and binary refuse save" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, "/tmp/faku-preview-gates-{s}", .{tmp.sub_path});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var note_buf: [300]u8 = undefined;
    const note_abs = try std.fmt.bufPrint(&note_buf, "{s}/note.txt", .{project});
    try writePreviewFile(std.testing.io, note_abs, "disk\n");

    var nul_buf: [300]u8 = undefined;
    const nul_abs = try std.fmt.bufPrint(&nul_buf, "{s}/nul.bin", .{project});
    try writePreviewFile(std.testing.io, nul_abs, "ok\x00still");

    var big_buf: [300]u8 = undefined;
    const big_abs = try std.fmt.bufPrint(&big_buf, "{s}/big.txt", .{project});
    const over = max_file_preview_bytes + 8;
    const blob = try std.testing.allocator.alloc(u8, over);
    defer std.testing.allocator.free(blob);
    @memset(blob, 'a');
    try writePreviewFile(std.testing.io, big_abs, blob);

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("preview gates", .fx);
    model.selected = id;
    model.setSelectedProjectPath(project);
    model.right_panel_open = true;
    file_mention.applyStdoutPaths(&model, "note.txt\nnul.bin\nbig.txt\n");
    defer clearFilePreview(&model);

    pickFile(&model, 1);
    startFilePreviewEdit(&model);
    applyFilePreviewEdit(&model, .{ .insert_text = "dirty" });
    try std.testing.expect(model.file_preview_dirty());
    try std.testing.expectEqualStrings("disk\ndirty", model.file_preview_draft());

    reloadPreview(&model);
    try std.testing.expectEqualStrings("disk\n", model.file_preview_body());
    try std.testing.expect(model.file_preview_editing());
    try std.testing.expect(!model.file_preview_dirty());
    try std.testing.expectEqualStrings("disk\n", model.file_preview_draft());
    const still = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, note_abs, std.testing.allocator, .limited(64));
    defer std.testing.allocator.free(still);
    try std.testing.expectEqualStrings("disk\n", still);

    pickFile(&model, 2);
    try std.testing.expect(model.file_preview_binary());
    try std.testing.expect(!model.file_preview_can_edit());
    try std.testing.expect(!model.file_preview_can_save());
    startFilePreviewEdit(&model);
    try std.testing.expect(!model.file_preview_editing());
    try std.testing.expectEqualStrings(binary_save_label, model.file_preview_status());
    savePreview(&model);
    try std.testing.expectEqualStrings(binary_save_label, model.file_preview_status());
    const bin_still = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, nul_abs, std.testing.allocator, .limited(64));
    defer std.testing.allocator.free(bin_still);
    try std.testing.expectEqualStrings("ok\x00still", bin_still);

    pickFile(&model, 3);
    try std.testing.expect(model.file_preview_truncated());
    try std.testing.expect(model.file_preview_has_body());
    try std.testing.expect(!model.file_preview_can_edit());
    try std.testing.expect(!model.file_preview_can_save());
    startFilePreviewEdit(&model);
    try std.testing.expect(!model.file_preview_editing());
    try std.testing.expectEqualStrings(truncated_save_label, model.file_preview_status());
    savePreview(&model);
    try std.testing.expectEqualStrings(truncated_save_label, model.file_preview_status());
    try std.testing.expectEqual(max_file_preview_bytes, model.right_panel_file_preview_len);
}

fn loadTwoPreviewNotes(model: *Model, project: []const u8) !void {
    var a_buf: [300]u8 = undefined;
    const a_abs = try std.fmt.bufPrint(&a_buf, "{s}/a.txt", .{project});
    try writePreviewFile(std.testing.io, a_abs, "aaa\n");
    var b_buf: [300]u8 = undefined;
    const b_abs = try std.fmt.bufPrint(&b_buf, "{s}/b.txt", .{project});
    try writePreviewFile(std.testing.io, b_abs, "bbb\n");
    model.store_io = std.testing.io;
    model.setSelectedProjectPath(project);
    model.right_panel_open = true;
    file_mention.applyStdoutPaths(model, "a.txt\nb.txt\n");
}

fn dirtyFirstPreview(model: *Model) void {
    pickFile(model, 1);
    startFilePreviewEdit(model);
    applyFilePreviewEdit(model, .{ .insert_text = "x" });
}

test "dirty preview parks switch / close / hide / keep-editing / discard" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, "/tmp/faku-preview-discard-{s}", .{tmp.sub_path});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    const id = model.addSession("preview discard", .fx);
    model.selected = id;
    try loadTwoPreviewNotes(&model, project);
    defer clearFilePreview(&model);

    dirtyFirstPreview(&model);
    try std.testing.expect(model.file_preview_dirty());
    try std.testing.expect(!model.file_preview_discard_confirm());

    pickFile(&model, 2);
    try std.testing.expect(model.file_preview_discard_confirm());
    try std.testing.expectEqual(PendingDiscard{ .switch_file = 2 }, pendingDiscard(&model));
    try std.testing.expectEqual(@as(u32, 1), model.right_panel_file_preview_id);
    try std.testing.expectEqualStrings("aaa\nx", model.file_preview_draft());
    try std.testing.expectEqualStrings("aaa\n", model.file_preview_body());

    cancelPendingDiscard(&model);
    try std.testing.expect(!model.file_preview_discard_confirm());
    try std.testing.expect(model.file_preview_dirty());
    try std.testing.expectEqual(@as(u32, 1), model.right_panel_file_preview_id);
    try std.testing.expectEqualStrings("aaa\nx", model.file_preview_draft());

    pickFile(&model, 2);
    try std.testing.expectEqual(PendingDiscard{ .switch_file = 2 }, pendingDiscard(&model));
    closeFilePreview(&model);
    try std.testing.expectEqual(PendingDiscard.close_preview, pendingDiscard(&model));
    try std.testing.expect(model.right_panel_file_preview_open());
    try std.testing.expect(model.file_preview_dirty());

    var intent = acceptPendingDiscard(&model);
    try std.testing.expectEqual(PendingDiscard.close_preview, intent);
    try std.testing.expect(!model.file_preview_dirty());
    try std.testing.expect(!model.file_preview_discard_confirm());
    closeFilePreview(&model);
    try std.testing.expect(!model.right_panel_file_preview_open());

    try loadTwoPreviewNotes(&model, project);
    dirtyFirstPreview(&model);
    model.hideRightPanel();
    try std.testing.expect(model.right_panel_open);
    try std.testing.expectEqual(PendingDiscard.hide_panel, pendingDiscard(&model));
    try std.testing.expect(model.file_preview_dirty());
    try std.testing.expectEqualStrings("aaa\nx", model.file_preview_draft());

    cancelPendingDiscard(&model);
    try std.testing.expect(model.right_panel_open);
    try std.testing.expect(model.file_preview_dirty());

    model.hideRightPanel();
    intent = acceptPendingDiscard(&model);
    try std.testing.expectEqual(PendingDiscard.hide_panel, intent);
    model.hideRightPanel();
    try std.testing.expect(!model.right_panel_open);
    try std.testing.expect(!model.right_panel_file_preview_open());
}

test "dirty preview discard switches file; save and reload clear pending confirm" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, "/tmp/faku-preview-discard-save-{s}", .{tmp.sub_path});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    const id = model.addSession("preview discard save", .fx);
    model.selected = id;
    try loadTwoPreviewNotes(&model, project);
    defer clearFilePreview(&model);

    dirtyFirstPreview(&model);
    pickFile(&model, 2);
    try std.testing.expectEqual(PendingDiscard{ .switch_file = 2 }, pendingDiscard(&model));
    const intent = acceptPendingDiscard(&model);
    try std.testing.expectEqual(PendingDiscard{ .switch_file = 2 }, intent);
    pickFile(&model, 2);
    try std.testing.expectEqual(@as(u32, 2), model.right_panel_file_preview_id);
    try std.testing.expect(!model.file_preview_dirty());
    try std.testing.expectEqualStrings("bbb\n", model.file_preview_body());
    try std.testing.expect(pendingDiscard(&model) == .none);

    pickFile(&model, 1);
    startFilePreviewEdit(&model);
    applyFilePreviewEdit(&model, .{ .insert_text = "y" });
    pickFile(&model, 2);
    try std.testing.expect(model.file_preview_discard_confirm());
    savePreview(&model);
    try std.testing.expect(!model.file_preview_dirty());
    try std.testing.expect(!model.file_preview_discard_confirm());
    try std.testing.expectEqual(@as(u32, 1), model.right_panel_file_preview_id);
    try std.testing.expectEqualStrings("aaa\ny", model.file_preview_body());
    try std.testing.expect(pendingDiscard(&model) == .none);

    startFilePreviewEdit(&model);
    applyFilePreviewEdit(&model, .{ .insert_text = "z" });
    pickFile(&model, 2);
    try std.testing.expect(model.file_preview_discard_confirm());
    reloadPreview(&model);
    try std.testing.expect(!model.file_preview_dirty());
    try std.testing.expect(!model.file_preview_discard_confirm());
    try std.testing.expectEqual(@as(u32, 1), model.right_panel_file_preview_id);
    try std.testing.expectEqualStrings("aaa\ny", model.file_preview_body());
    try std.testing.expect(pendingDiscard(&model) == .none);

    applyFilePreviewEdit(&model, .{ .insert_text = "q" });
    try std.testing.expect(model.file_preview_dirty());
    pickFile(&model, 2);
    try std.testing.expect(model.file_preview_discard_confirm());
    model.file_preview_edit_buffer.set(model.file_preview_body());
    applyFilePreviewEdit(&model, .{ .insert_text = "" });
    try std.testing.expect(!model.file_preview_dirty());
    try std.testing.expect(!model.file_preview_discard_confirm());
    try std.testing.expect(pendingDiscard(&model) == .none);
}

test "dirty preview parks session switch until discard" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, "/tmp/faku-preview-discard-session-{s}", .{tmp.sub_path});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var fx = main.Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    const first = model.addSession("preview discard first", .fx);
    const second = model.addSession("preview discard second", .fx);
    model.selected = first;
    try loadTwoPreviewNotes(&model, project);
    defer clearFilePreview(&model);

    dirtyFirstPreview(&model);
    const palette_run = @import("palette_run.zig");
    palette_run.applySessionSelection(&model, &fx, second);
    try std.testing.expectEqual(first, model.selected);
    try std.testing.expectEqual(PendingDiscard{ .switch_session = second }, pendingDiscard(&model));
    try std.testing.expect(model.file_preview_dirty());
    try std.testing.expectEqual(@as(u32, 1), model.right_panel_file_preview_id);

    cancelPendingDiscard(&model);
    try std.testing.expectEqual(first, model.selected);
    try std.testing.expect(model.file_preview_dirty());

    palette_run.applySessionSelection(&model, &fx, second);
    const intent = acceptPendingDiscard(&model);
    try std.testing.expectEqual(PendingDiscard{ .switch_session = second }, intent);
    palette_run.applySessionSelection(&model, &fx, second);
    try std.testing.expectEqual(second, model.selected);
    try std.testing.expect(!model.right_panel_file_preview_open());
    try std.testing.expect(pendingDiscard(&model) == .none);
}

test "clean preview still switches and closes without confirm" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, "/tmp/faku-preview-discard-clean-{s}", .{tmp.sub_path});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    const id = model.addSession("preview discard clean", .fx);
    model.selected = id;
    try loadTwoPreviewNotes(&model, project);
    defer clearFilePreview(&model);

    pickFile(&model, 1);
    startFilePreviewEdit(&model);
    try std.testing.expect(!model.file_preview_dirty());
    pickFile(&model, 2);
    try std.testing.expect(!model.file_preview_discard_confirm());
    try std.testing.expectEqual(@as(u32, 2), model.right_panel_file_preview_id);

    closeFilePreview(&model);
    try std.testing.expect(!model.right_panel_file_preview_open());
    try std.testing.expect(pendingDiscard(&model) == .none);

    pickFile(&model, 1);
    model.hideRightPanel();
    try std.testing.expect(!model.right_panel_open);
    try std.testing.expect(!model.right_panel_file_preview_open());
}

test "clean preview poll reloads when size or mtime changes" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, "/tmp/faku-preview-poll-clean-{s}", .{tmp.sub_path});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);
    var path_buf: [300]u8 = undefined;
    const abs = try std.fmt.bufPrint(&path_buf, "{s}/note.txt", .{project});
    try writePreviewFile(std.testing.io, abs, "hello\n");

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("preview poll clean", .fx);
    model.selected = id;
    model.setSelectedProjectPath(project);
    model.right_panel_open = true;
    file_mention.applyStdoutPaths(&model, "note.txt\n");
    defer clearFilePreview(&model);

    pickFile(&model, 1);
    try std.testing.expectEqualStrings("hello\n", model.file_preview_body());
    try std.testing.expect(model.right_panel_file_preview_disk_valid);
    try std.testing.expect(!model.file_preview_editing());

    try writePreviewFile(std.testing.io, abs, "from disk\n");
    model.now_ms = file_preview_disk_poll_interval_ms;
    try std.testing.expect(pollPreview(&model));
    try std.testing.expectEqualStrings("from disk\n", model.file_preview_body());
    try std.testing.expect(!model.file_preview_editing());
    try std.testing.expect(!model.file_preview_dirty());
    try std.testing.expect(model.right_panel_file_preview_disk_valid);
}

test "dirty preview poll leaves body and buffer unchanged" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, "/tmp/faku-preview-poll-dirty-{s}", .{tmp.sub_path});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);
    var path_buf: [300]u8 = undefined;
    const abs = try std.fmt.bufPrint(&path_buf, "{s}/note.txt", .{project});
    try writePreviewFile(std.testing.io, abs, "hello\n");

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("preview poll dirty", .fx);
    model.selected = id;
    model.setSelectedProjectPath(project);
    model.right_panel_open = true;
    file_mention.applyStdoutPaths(&model, "note.txt\n");
    defer clearFilePreview(&model);

    pickFile(&model, 1);
    startFilePreviewEdit(&model);
    applyFilePreviewEdit(&model, .{ .insert_text = "dirty" });
    try std.testing.expect(model.file_preview_dirty());
    try std.testing.expectEqualStrings("hello\ndirty", model.file_preview_draft());

    try writePreviewFile(std.testing.io, abs, "from disk\n");
    model.now_ms = file_preview_disk_poll_interval_ms;
    try std.testing.expect(!pollPreview(&model));
    try std.testing.expectEqualStrings("hello\n", model.file_preview_body());
    try std.testing.expectEqualStrings("hello\ndirty", model.file_preview_draft());
    try std.testing.expect(model.file_preview_dirty());
    try std.testing.expect(model.file_preview_editing());
}

test "preview disk poll is throttled to the interval" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, "/tmp/faku-preview-poll-throttle-{s}", .{tmp.sub_path});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);
    var path_buf: [300]u8 = undefined;
    const abs = try std.fmt.bufPrint(&path_buf, "{s}/note.txt", .{project});
    try writePreviewFile(std.testing.io, abs, "hello\n");

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("preview poll throttle", .fx);
    model.selected = id;
    model.setSelectedProjectPath(project);
    model.right_panel_open = true;
    file_mention.applyStdoutPaths(&model, "note.txt\n");
    defer clearFilePreview(&model);

    pickFile(&model, 1);
    try std.testing.expectEqualStrings("hello\n", model.file_preview_body());

    model.now_ms = 1_000;
    try std.testing.expect(!pollPreview(&model));
    try std.testing.expectEqual(@as(i64, 1_000), model.file_preview_disk_poll_ms.?);

    try writePreviewFile(std.testing.io, abs, "changed\n");
    try std.testing.expect(!pollPreview(&model));
    try std.testing.expectEqualStrings("hello\n", model.file_preview_body());

    model.now_ms = 1_000 + file_preview_disk_poll_interval_ms - 1;
    try std.testing.expect(!pollPreview(&model));
    try std.testing.expectEqualStrings("hello\n", model.file_preview_body());

    model.now_ms = 1_000 + file_preview_disk_poll_interval_ms;
    try std.testing.expect(pollPreview(&model));
    try std.testing.expectEqualStrings("changed\n", model.file_preview_body());
}

fn pendingSpawnKey(fx: *Effects, key: u64) ?@TypeOf(fx.pendingSpawnAt(0).?) {
    var i: usize = 0;
    while (fx.pendingSpawnAt(i)) |spawn| : (i += 1) {
        if (spawn.key == key) return spawn;
    }
    return null;
}

const text_file_ok_line = "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000014\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"workspace\",\"result\":{\"type\":\"textFile\",\"content\":\"from daemon\\n\"}}}}";
const text_file_empty_line = "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000014\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"workspace\",\"result\":{\"type\":\"textFile\",\"content\":\"\"}}}}";
const text_file_ack_line = "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000014\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"workspace\",\"result\":{\"type\":\"ack\"}}}}";

test "Files preview with a daemon address spawns ReadTextFile sidecar" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, "/tmp/faku-preview-daemon-spawn-{s}", .{tmp.sub_path});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);
    var path_buf: [300]u8 = undefined;
    const abs = try std.fmt.bufPrint(&path_buf, "{s}/note.txt", .{project});
    try writePreviewFile(std.testing.io, abs, "from disk\n");

    var model = Model{};
    model.store_io = std.testing.io;
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    const id = model.addSession("preview daemon spawn", .fx);
    model.selected = id;
    model.setSelectedProjectPath(project);
    model.right_panel_open = true;
    file_mention.applyStdoutPaths(&model, "note.txt\n");
    defer clearFilePreview(&model);

    selectCachedFile(&model, &fx, 1);
    const sidecar = pendingSpawnKey(&fx, model.file_preview_key) orelse return error.MissingDaemonReadTextFile;
    try std.testing.expect(daemon_proxy.isSidecarArgv(sidecar.argv));
    try std.testing.expectEqualStrings("faku", sidecar.argv[0]);
    try std.testing.expectEqualStrings(daemon_proxy.SUBCOMMAND, sidecar.argv[1]);
    try std.testing.expectEqualStrings("127.0.0.1:8787", sidecar.argv[2]);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"hello\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"workspace\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"readTextFile\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"relative_path\":\"note.txt\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "relativePath") == null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"prompt\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"attachSession\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"listTree\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"browseDirectory\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"writeTextFile\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, project) != null);
    try std.testing.expect(model.file_preview_via_daemon);
    try std.testing.expect(!model.file_preview_daemon_ok);
    try std.testing.expectEqual(sidecar.key, model.file_preview_key);
    try std.testing.expect(sidecar.key < file_mention.file_mention_key_first);
    try std.testing.expectEqual(@as(usize, 0), model.right_panel_file_preview_len);
}

test "Files preview without a daemon address still reads local disk" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, "/tmp/faku-preview-local-{s}", .{tmp.sub_path});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);
    var path_buf: [300]u8 = undefined;
    const abs = try std.fmt.bufPrint(&path_buf, "{s}/note.txt", .{project});
    try writePreviewFile(std.testing.io, abs, "from disk\n");

    var model = Model{};
    model.store_io = std.testing.io;
    model.setSidecarPath("faku");
    const id = model.addSession("preview local", .fx);
    model.selected = id;
    model.setSelectedProjectPath(project);
    model.right_panel_open = true;
    file_mention.applyStdoutPaths(&model, "note.txt\n");
    defer clearFilePreview(&model);
    try std.testing.expectEqual(@as(usize, 0), store.resolveDaemonMirrorAddress(&model).len);

    selectCachedFile(&model, &fx, 1);
    try std.testing.expect(pendingSpawnKey(&fx, model.file_preview_key) == null);
    try std.testing.expect(!model.file_preview_via_daemon);
    try std.testing.expectEqualStrings("from disk\n", model.file_preview_body());
}

test "ReadTextFile sidecar paints Files preview from textFile content" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, "/tmp/faku-preview-daemon-fill-{s}", .{tmp.sub_path});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);
    var path_buf: [300]u8 = undefined;
    const abs = try std.fmt.bufPrint(&path_buf, "{s}/note.txt", .{project});
    try writePreviewFile(std.testing.io, abs, "from disk\n");

    var model = Model{};
    model.store_io = std.testing.io;
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    const id = model.addSession("preview daemon fill", .fx);
    model.selected = id;
    model.setSelectedProjectPath(project);
    model.right_panel_open = true;
    file_mention.applyStdoutPaths(&model, "note.txt\n");
    defer clearFilePreview(&model);

    selectCachedFile(&model, &fx, 1);
    const sidecar = pendingSpawnKey(&fx, model.file_preview_key) orelse return error.MissingDaemonReadTextFileFill;
    applyDaemonLine(&model, .{ .key = sidecar.key, .line = "{\"type\":\"hello\"}" });
    try std.testing.expectEqual(@as(usize, 0), model.right_panel_file_preview_len);
    applyDaemonLine(&model, .{ .key = sidecar.key, .line = text_file_ok_line });
    try std.testing.expect(model.file_preview_daemon_ok);
    try std.testing.expectEqualStrings("from daemon\n", model.file_preview_body());
    try std.testing.expect(!model.file_preview_binary());
    try std.testing.expect(!model.file_preview_truncated());
    try std.testing.expect(model.right_panel_file_preview_disk_valid);
    handleDaemonExit(&model, &fx, .{ .key = sidecar.key, .reason = .exited, .code = 0 });
    try std.testing.expectEqual(@as(u64, 0), model.file_preview_key);
    try std.testing.expect(!model.file_preview_via_daemon);
    try std.testing.expectEqualStrings("from daemon\n", model.file_preview_body());

    reloadFilePreview(&model, &fx);
    const second = pendingSpawnKey(&fx, model.file_preview_key) orelse return error.MissingDaemonReadTextFileReload;
    try std.testing.expect(daemon_proxy.isSidecarArgv(second.argv));
    try std.testing.expect(second.key != sidecar.key);
    try std.testing.expect(std.mem.indexOf(u8, second.stdin, "\"type\":\"readTextFile\"") != null);
    applyDaemonLine(&model, .{ .key = second.key, .line = text_file_empty_line });
    handleDaemonExit(&model, &fx, .{ .key = second.key, .reason = .exited, .code = 0 });
    try std.testing.expect(previewTextOk(&model));
    try std.testing.expectEqualStrings("", model.file_preview_body());
}

test "ReadTextFile sidecar non-ok falls back to local readFileAlloc" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, "/tmp/faku-preview-daemon-fallback-{s}", .{tmp.sub_path});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);
    var path_buf: [300]u8 = undefined;
    const abs = try std.fmt.bufPrint(&path_buf, "{s}/note.txt", .{project});
    try writePreviewFile(std.testing.io, abs, "from disk\n");

    var model = Model{};
    model.store_io = std.testing.io;
    model.setDaemonAddress("10.0.0.2:9");
    model.setSidecarPath("faku");
    const id = model.addSession("preview daemon fallback", .fx);
    model.selected = id;
    model.setSelectedProjectPath(project);
    model.right_panel_open = true;
    file_mention.applyStdoutPaths(&model, "note.txt\n");
    defer clearFilePreview(&model);

    selectCachedFile(&model, &fx, 1);
    const sidecar = pendingSpawnKey(&fx, model.file_preview_key) orelse return error.MissingDaemonReadTextFileFallback;
    applyDaemonLine(&model, .{ .key = sidecar.key, .line = text_file_ack_line });
    try std.testing.expect(!model.file_preview_daemon_ok);
    try std.testing.expectEqual(@as(usize, 0), model.right_panel_file_preview_len);
    handleDaemonExit(&model, &fx, .{ .key = sidecar.key, .reason = .exited, .code = 1 });
    try std.testing.expect(!model.file_preview_via_daemon);
    try std.testing.expectEqual(@as(u64, 0), model.file_preview_key);
    try std.testing.expectEqualStrings("from disk\n", model.file_preview_body());
}

test "ReadTextFile sidecar content over 256KB is truncated client-side" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, "/tmp/faku-preview-daemon-cap-{s}", .{tmp.sub_path});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);
    var path_buf: [300]u8 = undefined;
    const abs = try std.fmt.bufPrint(&path_buf, "{s}/big.txt", .{project});
    try writePreviewFile(std.testing.io, abs, "disk\n");

    var model = Model{};
    model.store_io = std.testing.io;
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    const id = model.addSession("preview daemon cap", .fx);
    model.selected = id;
    model.setSelectedProjectPath(project);
    model.right_panel_open = true;
    file_mention.applyStdoutPaths(&model, "big.txt\n");
    defer clearFilePreview(&model);

    selectCachedFile(&model, &fx, 1);
    const sidecar = pendingSpawnKey(&fx, model.file_preview_key) orelse return error.MissingDaemonReadTextFileCap;
    const over = max_file_preview_bytes + 8;
    const blob = try std.testing.allocator.alloc(u8, over);
    defer std.testing.allocator.free(blob);
    @memset(blob, 'a');
    const line = try std.fmt.allocPrint(
        std.testing.allocator,
        "{{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000014\",\"outcome\":{{\"status\":\"ok\",\"payload\":{{\"type\":\"workspace\",\"result\":{{\"type\":\"textFile\",\"content\":\"{s}\"}}}}}}}}",
        .{blob},
    );
    defer std.testing.allocator.free(line);
    applyDaemonLine(&model, .{ .key = sidecar.key, .line = line });
    try std.testing.expect(model.file_preview_daemon_ok);
    try std.testing.expect(model.file_preview_truncated());
    try std.testing.expectEqual(max_file_preview_bytes, model.right_panel_file_preview_len);
    try std.testing.expect(!model.file_preview_binary());
}

fn dirtyLocalPreview(model: *Model, project: []const u8, insert: []const u8) !void {
    var path_buf: [300]u8 = undefined;
    const abs = try std.fmt.bufPrint(&path_buf, "{s}/note.txt", .{project});
    try writePreviewFile(std.testing.io, abs, "hello\n");
    model.store_io = std.testing.io;
    model.setSelectedProjectPath(project);
    model.right_panel_open = true;
    file_mention.applyStdoutPaths(model, "note.txt\n");
    pickFile(model, 1);
    startFilePreviewEdit(model);
    applyFilePreviewEdit(model, .{ .insert_text = insert });
}

test "Files preview Save with a daemon address spawns WriteTextFile sidecar" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, "/tmp/faku-preview-save-daemon-spawn-{s}", .{tmp.sub_path});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.setSidecarPath("faku");
    const id = model.addSession("preview save daemon spawn", .fx);
    model.selected = id;
    try dirtyLocalPreview(&model, project, "world\n");
    defer clearFilePreview(&model);
    try std.testing.expectEqualStrings("hello\nworld\n", model.file_preview_draft());

    model.setLastDaemonAddress("127.0.0.1:8787");
    saveFilePreview(&model, &fx);
    const sidecar = pendingSpawnKey(&fx, model.file_preview_save_key) orelse return error.MissingDaemonWriteTextFile;
    try std.testing.expect(daemon_proxy.isSidecarArgv(sidecar.argv));
    try std.testing.expectEqualStrings("faku", sidecar.argv[0]);
    try std.testing.expectEqualStrings(daemon_proxy.SUBCOMMAND, sidecar.argv[1]);
    try std.testing.expectEqualStrings("127.0.0.1:8787", sidecar.argv[2]);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"hello\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"workspace\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"writeTextFile\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"relative_path\":\"note.txt\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"content\":\"hello\\nworld\\n\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "relativePath") == null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"readTextFile\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"prompt\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"attachSession\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, sidecar.stdin, project) != null);
    try std.testing.expect(model.file_preview_save_via_daemon);
    try std.testing.expect(!model.file_preview_save_daemon_ok);
    try std.testing.expectEqual(sidecar.key, model.file_preview_save_key);
    try std.testing.expect(sidecar.key != model.file_preview_key);
    try std.testing.expect(sidecar.key < file_mention.file_mention_key_first);
    try std.testing.expect(model.file_preview_editing());
    try std.testing.expect(model.file_preview_dirty());
}

test "WriteTextFile sidecar Ack adopts the saved buffer without a local write" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, "/tmp/faku-preview-save-daemon-ack-{s}", .{tmp.sub_path});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.setSidecarPath("faku");
    const id = model.addSession("preview save daemon ack", .fx);
    model.selected = id;
    try dirtyLocalPreview(&model, project, "world\n");
    defer clearFilePreview(&model);

    model.setLastDaemonAddress("127.0.0.1:8787");
    saveFilePreview(&model, &fx);
    const sidecar = pendingSpawnKey(&fx, model.file_preview_save_key) orelse return error.MissingDaemonWriteTextFileAck;
    applyDaemonSaveLine(&model, .{ .key = sidecar.key, .line = "{\"type\":\"hello\"}" });
    try std.testing.expect(model.file_preview_editing());
    try std.testing.expectEqualStrings("hello\n", model.file_preview_body());
    applyDaemonSaveLine(&model, .{ .key = sidecar.key, .line = text_file_ok_line });
    try std.testing.expect(!model.file_preview_save_daemon_ok);
    try std.testing.expect(model.file_preview_editing());
    applyDaemonSaveLine(&model, .{ .key = sidecar.key, .line = text_file_ack_line });
    try std.testing.expect(model.file_preview_save_daemon_ok);
    try std.testing.expect(!model.file_preview_editing());
    try std.testing.expect(!model.file_preview_dirty());
    try std.testing.expectEqualStrings("hello\nworld\n", model.file_preview_body());
    try std.testing.expectEqual(@as(usize, 0), model.file_preview_draft().len);
    handleDaemonSaveExit(&model, &fx, .{ .key = sidecar.key, .reason = .exited, .code = 0 });
    try std.testing.expectEqual(@as(u64, 0), model.file_preview_save_key);
    try std.testing.expect(!model.file_preview_save_via_daemon);
    try std.testing.expectEqualStrings("hello\nworld\n", model.file_preview_body());

    var path_buf: [300]u8 = undefined;
    const abs = try std.fmt.bufPrint(&path_buf, "{s}/note.txt", .{project});
    const got = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, abs, std.testing.allocator, .limited(64));
    defer std.testing.allocator.free(got);
    try std.testing.expectEqualStrings("hello\n", got);
}

test "WriteTextFile sidecar non-ack falls back to local atomic write" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, "/tmp/faku-preview-save-daemon-fallback-{s}", .{tmp.sub_path});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.setSidecarPath("faku");
    const id = model.addSession("preview save daemon fallback", .fx);
    model.selected = id;
    try dirtyLocalPreview(&model, project, "world\n");
    defer clearFilePreview(&model);

    model.setLastDaemonAddress("127.0.0.1:8787");
    saveFilePreview(&model, &fx);
    const sidecar = pendingSpawnKey(&fx, model.file_preview_save_key) orelse return error.MissingDaemonWriteTextFileFallback;
    applyDaemonSaveLine(&model, .{ .key = sidecar.key, .line = text_file_ok_line });
    try std.testing.expect(!model.file_preview_save_daemon_ok);
    handleDaemonSaveExit(&model, &fx, .{ .key = sidecar.key, .reason = .exited, .code = 1 });
    try std.testing.expectEqual(@as(u64, 0), model.file_preview_save_key);
    try std.testing.expect(!model.file_preview_save_via_daemon);
    try std.testing.expect(!model.file_preview_editing());
    try std.testing.expect(!model.file_preview_dirty());
    try std.testing.expectEqualStrings("hello\nworld\n", model.file_preview_body());

    var path_buf: [300]u8 = undefined;
    const abs = try std.fmt.bufPrint(&path_buf, "{s}/note.txt", .{project});
    const got = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, abs, std.testing.allocator, .limited(64));
    defer std.testing.allocator.free(got);
    try std.testing.expectEqualStrings("hello\nworld\n", got);
}

test "WriteTextFile stdin overflow falls back to local write; truncated stays local" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, "/tmp/faku-preview-save-overflow-{s}", .{tmp.sub_path});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var model = Model{};
    model.setSidecarPath("faku");
    const id = model.addSession("preview save overflow", .fx);
    model.selected = id;
    const blob = try std.testing.allocator.alloc(u8, 3800);
    defer std.testing.allocator.free(blob);
    @memset(blob, 'a');
    try dirtyLocalPreview(&model, project, blob);
    defer clearFilePreview(&model);

    model.setLastDaemonAddress("127.0.0.1:8787");
    saveFilePreview(&model, &fx);
    try std.testing.expectEqual(@as(u64, 0), model.file_preview_save_key);
    try std.testing.expect(pendingSpawnKey(&fx, model.file_preview_save_key) == null);
    try std.testing.expect(!model.file_preview_save_via_daemon);
    try std.testing.expect(!model.file_preview_editing());
    try std.testing.expect(std.mem.startsWith(u8, model.file_preview_body(), "hello\n"));
    try std.testing.expectEqual(@as(usize, "hello\n".len + blob.len), model.file_preview_body().len);

    model.right_panel_file_preview_truncated = true;
    startFilePreviewEdit(&model);
    try std.testing.expect(!model.file_preview_editing());
    saveFilePreview(&model, &fx);
    try std.testing.expectEqual(@as(u64, 0), model.file_preview_save_key);
    try std.testing.expectEqualStrings(truncated_save_label, model.file_preview_status());
}
