//! Local session catalog + turns. This is not the Waku daemon.
//!
//! Files live in Native's per-app data directory (`native_sdk.app_dirs` `.data`),
//! not a daemon socket and not `~/.waku`:
//!   Linux:  $XDG_DATA_HOME/faku or ~/.local/share/faku
//!   macOS:  ~/Library/Application Support/faku
//!
//! One JSON document `sessions.json`. Catalog load copies only session
//! skeletons (id, title, provider, untitled, has_started, project_path,
//! fx_session_id, runtime_id, model, access_mode, interaction_mode, reasoning_effort, folder_id, updated_at, rewind_refs,
//! worktree_snapshot_sha, worktree_turn_end_sha, worktree_turn_diff_sha, context_used, context_size, available_commands, thread_goal_objective, thread_goal_status,
//! thread_goal_token_budget, thread_goal_tokens_used, thread_goal_time_used_seconds) — no transcripts. Selecting
//! a session hydrates its turns,
//! `queued_messages`, `rewind_refs`, `worktree_snapshot_sha`, `worktree_turn_end_sha`, `worktree_turn_diff_sha`, and last-known context usage. Document extras also keep
//! `sidebar_collapsed` and `sidebar_width` so reboot restores the rail,
//! plus `right_panel_open` / `right_panel_width` for the first-cut Files +
//! Diff + Background pane (default closed; Waku file-tree 184px; Diff and
//! Background tabs are runtime-only),
//! plus `last_model` / `last_access_mode` / `last_interaction_mode` /
//! `last_reasoning_effort` /
//! `last_project_path` / `last_daemon_address` / `theme_preference` /
//! `language_preference` so the settings gear and
//! composer chips can edit persisted defaults, and `folders` /
//! `collapsed_folder_ids` so New folder groups persist. A session
//! `folder_id` of 0 (or omitted) stays in the ungrouped date buckets
//! (Today / Yesterday / This week / This month / This year / Older from `updated_at`).
//! Missing `updated_at` is 0 and groups as Today.
//! Save is merge-only (never deletes session rows).
//! `removeSession` is the only session delete. Deleting a folder rewrites
//! `folders` extras and unassigns `folder_id`; it is not `removeSession`.
//! Refuses to write until a successful
//! load (`task_state_loaded`), same guard as waku-client. After a successful
//! started-session save, a one-shot sidecar may send `saveTaskState` when
//! `WAKU_DAEMON_ADDRESS` or `last_daemon_address` is set. Sidecar failure
//! does not roll back the local catalog. When the local catalog is missing
//! and a daemon address is set, a one-shot sidecar may send `loadTaskState`
//! and fill session skeletons. That daemon load does not run when the
//! local file loaded or is corrupt. Selecting a session whose local
//! turns are empty may send `hydrateSession` when a daemon address is
//! set. Local turns win; a failed sidecar leaves the empty transcript.
//! After a successful local `removeSession`, a one-shot sidecar may send
//! `closeSession` when a daemon address is set. Sidecar failure does
//! not resurrect the local row.
//!
//! Composer drafts live in a sibling `drafts.json` (not the session
//! catalog) so an unstarted New Task can persist before the session row
//! exists. Keys match Waku: `newSession` / `newSession{project_path}`
//! for untitled drafts, `session{id}` after the session has started.
//! Each record is `{ text, image_path }` — one optional local file path
//! for `fx ask --image`, not a Waku attachment/blob.

const std = @import("std");
const native_sdk = @import("native_sdk");
const main = @import("main.zig");
const protocol = @import("protocol.zig");
const daemon_proxy = @import("daemon_proxy.zig");
const rewind = @import("rewind.zig");

const Model = main.Model;
const Role = main.Role;
const Provider = main.Provider;

pub const catalog_name = "sessions.json";
pub const drafts_name = "drafts.json";
pub const app_store_name = "faku";
pub const format_version: u32 = 1;
pub const max_document_bytes: usize = 16 * 1024 * 1024;
pub const max_drafts_bytes: usize = 64 * 1024;
pub const max_draft_key = main.max_project_path + 16;
pub const max_draft_entries: usize = 32;

pub const LoadKind = enum { loaded, missing, failed };

pub fn resolveDefaultDir(home: []const u8, xdg_data_home: ?[]const u8, buf: []u8) ?[]const u8 {
    return native_sdk.app_dirs.resolveOne(
        .{ .name = app_store_name },
        native_sdk.app_dirs.currentPlatform(),
        .{ .home = home, .xdg_data_home = xdg_data_home },
        .data,
        buf,
    ) catch null;
}

pub fn catalogPath(dir: []const u8, buf: []u8) ?[]const u8 {
    if (dir.len == 0) return null;
    return std.fmt.bufPrint(buf, "{s}{s}{s}", .{ dir, std.fs.path.sep_str, catalog_name }) catch null;
}

pub fn draftsPath(dir: []const u8, buf: []u8) ?[]const u8 {
    if (dir.len == 0) return null;
    return std.fmt.bufPrint(buf, "{s}{s}{s}", .{ dir, std.fs.path.sep_str, drafts_name }) catch null;
}

/// Waku composer keys: `newSession` / `newSession{project_path}` until the
/// session has started, then `session{id}` so the first prompt cannot
/// resurrect on New Task.
pub fn draftKey(session: *const main.Session, buf: []u8) ?[]const u8 {
    if (session.untitled or !session.hasStarted()) {
        const project = session.projectPath();
        if (project.len == 0) return std.fmt.bufPrint(buf, "newSession", .{}) catch null;
        return std.fmt.bufPrint(buf, "newSession{s}", .{project}) catch null;
    }
    return std.fmt.bufPrint(buf, "session{d}", .{session.id}) catch null;
}

pub fn persistDraftIfPossible(model: *Model) void {
    const io = model.store_io orelse return;
    const session = model.sessionById(model.selected) orelse return;
    var key_buf: [max_draft_key]u8 = undefined;
    const key = draftKey(session, &key_buf) orelse return;
    upsertDraft(model, io, key, model.draft(), model.draftImagePath()) catch {};
}

pub fn loadDraftIfPossible(model: *Model) void {
    const io = model.store_io orelse return;
    loadDraft(model, std.heap.page_allocator, io);
}

pub fn discardDraftIfPossible(model: *Model, key: []const u8) void {
    const io = model.store_io orelse return;
    upsertDraft(model, io, key, "", "") catch {};
}

fn loadDraft(model: *Model, allocator: std.mem.Allocator, io: std.Io) void {
    const session = model.sessionById(model.selected) orelse {
        model.draft_buffer.clear();
        model.setDraftImagePath("");
        return;
    };
    var key_buf: [max_draft_key]u8 = undefined;
    const key = draftKey(session, &key_buf) orelse {
        model.draft_buffer.clear();
        model.setDraftImagePath("");
        return;
    };
    var text_buf: [main.max_draft]u8 = undefined;
    var image_buf: [main.max_project_path]u8 = undefined;
    if (readDraftRecord(allocator, io, model.storeDir(), key, &text_buf, &image_buf)) |record| {
        model.draft_buffer.set(record.text);
        model.setDraftImagePath(record.image_path);
    } else {
        model.draft_buffer.clear();
        model.setDraftImagePath("");
    }
}

/// Bind Native's user-data dir and attempt a catalog load. Missing file keeps
/// the demo rows and still marks the catalog loaded (first-run may create the
/// store). Corrupt/unreadable files keep the demos and refuse later saves.
pub fn boot(model: *Model, allocator: std.mem.Allocator, io: std.Io) LoadKind {
    model.store_io = io;
    return switch (loadCatalog(model, allocator, io)) {
        .loaded => {
            model.pending_daemon_catalog = false;
            hydrateSession(model, model.selected, allocator, io);
            loadDraft(model, allocator, io);
            return .loaded;
        },
        .missing => {
            model.task_state_loaded = true;
            if (resolveDaemonMirrorAddress(model).len > 0) {
                model.pending_daemon_catalog = true;
            }
            loadDraft(model, allocator, io);
            return .missing;
        },
        .failed => {
            model.task_state_loaded = false;
            model.pending_daemon_catalog = false;
            return .failed;
        },
    };
}

pub fn bindDefaultDir(model: *Model, home: []const u8, xdg_data_home: ?[]const u8) void {
    var buf: [main.max_store_dir]u8 = undefined;
    if (resolveDefaultDir(home, xdg_data_home, &buf)) |dir| {
        model.setStoreDir(dir);
    }
}

pub fn loadCatalog(model: *Model, allocator: std.mem.Allocator, io: std.Io) LoadKind {
    const dir = model.storeDir();
    if (dir.len == 0) return .missing;

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = catalogPath(dir, &path_buf) orelse return .failed;
    const bytes = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(max_document_bytes)) catch |err| {
        return if (err == error.FileNotFound) .missing else .failed;
    };
    defer allocator.free(bytes);

    applyCatalog(model, allocator, bytes) catch return .failed;
    model.task_state_loaded = true;
    loadDraft(model, allocator, io);
    return .loaded;
}

pub fn hydrateSession(model: *Model, session_id: u32, allocator: std.mem.Allocator, io: std.Io) void {
    const session = model.sessionById(session_id) orelse return;
    if (session.detail_loaded) return;

    const dir = model.storeDir();
    if (dir.len == 0) {
        session.detail_loaded = true;
        return;
    }

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = catalogPath(dir, &path_buf) orelse return;
    const bytes = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(max_document_bytes)) catch return;
    defer allocator.free(bytes);

    applyDetail(model, allocator, bytes, session_id) catch return;
    if (model.sessionById(session_id)) |loaded| loaded.detail_loaded = true;
}

pub fn saveSession(model: *const Model, session_id: u32, allocator: std.mem.Allocator, io: std.Io) !void {
    if (!model.task_state_loaded) return error.TaskStateNotLoaded;
    const dir = model.storeDir();
    if (dir.len == 0) return error.NoStoreDir;
    const session = model.sessionByIdConst(session_id) orelse return;
    if (!session.hasStarted()) return;

    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var document = readDocument(arena, io, dir) catch |err| switch (err) {
        error.FileNotFound => Document.empty(model),
        else => return error.Corrupt,
    };
    upsertSession(&document, arena, model, session_id) catch return error.OutOfMemory;
    document.selected = model.selected;
    document.next_id = model.next_id;
    document.next_turn_id = model.next_turn_id;
    document.next_queued_id = model.next_queued_id;
    document.last_project_path = lastProjectPathForSave(model, session);
    document.last_model = lastModelForSave(model, session);
    document.last_access_mode = lastAccessModeForSave(model, session);
    document.last_interaction_mode = lastInteractionModeForSave(model, session);
    document.last_reasoning_effort = lastReasoningEffortForSave(model, session);
    document.last_daemon_address = lastDaemonAddressForSave(model);
    document.theme_preference = model.theme_preference;
    document.language_preference = model.language_preference;
    applySidebarExtras(&document, model);
    try applyFolderExtras(&document, arena, model);
    try writeDocument(allocator, io, dir, document);
}

/// Merge-only save of every started session. Used by tests and first persist
/// of a selected session after a successful load.
pub fn saveStartedSessions(model: *const Model, allocator: std.mem.Allocator, io: std.Io) !void {
    if (!model.task_state_loaded) return error.TaskStateNotLoaded;
    for (model.sessions()) |session| {
        if (session.hasStarted()) try saveSession(model, session.id, allocator, io);
    }
}

pub fn removeSession(model: *Model, session_id: u32, allocator: std.mem.Allocator, io: std.Io) !void {
    if (!model.task_state_loaded) return error.TaskStateNotLoaded;
    const dir = model.storeDir();
    if (dir.len == 0) return error.NoStoreDir;

    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var document = readDocument(arena, io, dir) catch |err| switch (err) {
        error.FileNotFound => Document.empty(model),
        else => return error.Corrupt,
    };
    dropStoredSession(&document, session_id);
    if (document.selected == session_id) {
        document.selected = if (document.sessions.len > 0) document.sessions[0].id else 0;
    }
    document.last_project_path = model.lastProjectPath();
    document.last_model = model.lastModel();
    document.last_access_mode = model.lastAccessMode();
    document.last_interaction_mode = model.lastInteractionMode();
    document.last_reasoning_effort = model.lastReasoningEffort();
    document.last_daemon_address = lastDaemonAddressForSave(model);
    document.theme_preference = model.theme_preference;
    document.language_preference = model.language_preference;
    applySidebarExtras(&document, model);
    try applyFolderExtras(&document, arena, model);
    try writeDocument(allocator, io, dir, document);
    model.dropSession(session_id);
}

/// Local delete, then a best-effort hello + `closeSession` when a daemon
/// address is set. Sidecar failure must not resurrect the row already
/// dropped from `sessions.json`.
pub fn removeIfPossible(model: *Model, session_id: u32, fx: *main.Effects) void {
    const io = model.store_io orelse return;
    const address = resolveDaemonMirrorAddress(model);
    var id_buf: [36]u8 = undefined;
    const wire_id = daemon_proxy.wireUuid(session_id, &id_buf);
    removeSession(model, session_id, std.heap.page_allocator, io) catch return;
    maybeCloseDaemonSession(model, fx, wire_id, address);
}

pub fn persistIfPossible(model: *Model, session_id: u32, fx: *main.Effects) void {
    if (model.sessionById(session_id)) |session| {
        if (session.projectPath().len > 0) model.setLastProjectPath(session.projectPath());
        if (session.model().len > 0) model.setLastModel(session.model());
        if (session.accessMode().len > 0) model.setLastAccessMode(session.accessMode());
        if (session.interactionMode().len > 0) model.setLastInteractionMode(session.interactionMode());
        if (session.reasoningEffort().len > 0) model.setLastReasoningEffort(session.reasoningEffort());
    }
    if (model.daemonAddress().len > 0) model.setLastDaemonAddress(model.daemonAddress());
    const io = model.store_io orelse return;
    saveSession(model, session_id, std.heap.page_allocator, io) catch return;
    mirrorSaveTaskStateIfPossible(model, session_id, fx);
}

/// Merge-only write of layout extras (`sidebar_collapsed`,
/// `sidebar_width`, `right_panel_open`, `right_panel_width`). Does not
/// create `sessions.json` and does not spawn a daemon sidecar. Missing
/// / corrupt catalogs are a no-op.
pub fn persistLayoutIfPossible(model: *const Model) void {
    const io = model.store_io orelse return;
    saveExtras(model, std.heap.page_allocator, io, .layout) catch {};
}

/// Merge-only write of settings extras (`last_model`, `last_access_mode`,
/// `last_interaction_mode`, `last_reasoning_effort`, `last_project_path`, `last_daemon_address`,
/// `theme_preference`, `language_preference`).
/// Same first-run rule as sidebar collapse: does not create `sessions.json`
/// and does not spawn a daemon sidecar. Missing / corrupt catalogs are a no-op.
pub fn persistSettingsIfPossible(model: *const Model) void {
    const io = model.store_io orelse return;
    saveExtras(model, std.heap.page_allocator, io, .settings) catch {};
}

/// Merge-only write of folder extras (`folders`, `next_folder_id`,
/// `collapsed_folder_ids`). Same first-run rule as sidebar collapse:
/// does not create `sessions.json` and does not spawn a daemon sidecar.
pub fn persistFoldersIfPossible(model: *const Model) void {
    const io = model.store_io orelse return;
    saveExtras(model, std.heap.page_allocator, io, .folders) catch {};
}

const ExtrasKind = enum { layout, settings, folders };

fn saveExtras(model: *const Model, allocator: std.mem.Allocator, io: std.Io, kind: ExtrasKind) !void {
    if (!model.task_state_loaded) return error.TaskStateNotLoaded;
    const dir = model.storeDir();
    if (dir.len == 0) return error.NoStoreDir;

    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var document = readDocument(arena, io, dir) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return error.Corrupt,
    };
    switch (kind) {
        .layout => applySidebarExtras(&document, model),
        .settings => applySettingsExtras(&document, model),
        .folders => try applyFolderExtras(&document, arena, model),
    }
    try writeDocument(allocator, io, dir, document);
}

fn applySidebarExtras(document: *Document, model: *const Model) void {
    document.sidebar_collapsed = model.sidebar_collapsed;
    document.sidebar_width = model.sidebarWidthPixels();
    document.right_panel_open = model.right_panel_open;
    document.right_panel_width = model.rightPanelWidthPixels();
}

fn applySettingsExtras(document: *Document, model: *const Model) void {
    document.last_project_path = model.lastProjectPath();
    document.last_model = model.lastModel();
    document.last_access_mode = model.lastAccessMode();
    document.last_interaction_mode = model.lastInteractionMode();
    document.last_reasoning_effort = model.lastReasoningEffort();
    document.last_daemon_address = model.lastDaemonAddress();
    document.theme_preference = model.theme_preference;
    document.language_preference = model.language_preference;
}

fn applyFolderExtras(document: *Document, arena: std.mem.Allocator, model: *const Model) !void {
    document.next_folder_id = model.next_folder_id;
    const folders = try arena.alloc(StoredFolder, model.folder_count);
    var collapsed_n: usize = 0;
    for (model.folder_store[0..model.folder_count], folders) |folder, *out| {
        out.* = .{
            .id = folder.id,
            .title = try arena.dupe(u8, folder.title()),
        };
        if (folder.collapsed) collapsed_n += 1;
    }
    document.folders = folders;
    const collapsed = try arena.alloc(u32, collapsed_n);
    var i: usize = 0;
    for (model.folder_store[0..model.folder_count]) |folder| {
        if (!folder.collapsed) continue;
        collapsed[i] = folder.id;
        i += 1;
    }
    document.collapsed_folder_ids = collapsed;
}

/// Live `WAKU_DAEMON_ADDRESS` wins; otherwise the last persisted sidecar address.
pub fn resolveDaemonMirrorAddress(model: *const Model) []const u8 {
    if (model.daemonAddress().len > 0) return model.daemonAddress();
    return model.lastDaemonAddress();
}

/// First-run fill: hello + loadTaskState when the local catalog is missing
/// and a daemon address is set. No-op when the file loaded, is corrupt, or
/// there is no address. Sidecar failure keeps the demo sessions.
pub fn maybeLoadDaemonCatalog(model: *Model, fx: *main.Effects) void {
    if (!model.pending_daemon_catalog) return;
    if (!model.task_state_loaded) {
        model.pending_daemon_catalog = false;
        return;
    }
    const address = resolveDaemonMirrorAddress(model);
    if (address.len == 0) {
        model.pending_daemon_catalog = false;
        return;
    }

    var stdin_buf: [4096]u8 = undefined;
    const stdin = daemon_proxy.writeLoadStdin(&stdin_buf, .{
        .token = model.daemonToken(),
    }) catch {
        model.pending_daemon_catalog = false;
        return;
    };

    const key = model.next_daemon_key;
    model.next_daemon_key += 1;
    model.daemon_load_key = key;
    fx.spawn(.{
        .key = key,
        .argv = &.{ model.sidecarPath(), daemon_proxy.SUBCOMMAND, address },
        .stdin = stdin,
        .max_line_bytes = main.daemon_line_bytes,
        .on_line = main.Effects.lineMsg(.fx_line),
        .on_exit = main.Effects.exitMsg(.fx_exit),
    });
}

/// Apply a sidecar stdout line only while a first-run daemon fill is pending.
/// Empty / unparsed / non-taskState lines leave the demo sessions in place.
pub fn applyDaemonCatalogLine(model: *Model, line: []const u8) void {
    if (!model.pending_daemon_catalog) return;
    if (!model.task_state_loaded) return;

    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const parsed = protocol.parseTaskStateSkeletons(arena_state.allocator(), line);
    if (parsed.session_count == 0) return;
    applyDaemonSkeletons(model, parsed.sessions[0..parsed.session_count]);
}

fn applyDaemonSkeletons(model: *Model, skeletons: []const protocol.TaskStateSkeleton) void {
    var valid: usize = 0;
    for (skeletons) |skel| {
        if (skel.session_id.len == 0 or skel.title.len == 0) continue;
        if (Provider.fromWire(skel.provider) == null) continue;
        valid += 1;
    }
    if (valid == 0) return;

    model.clearSessions();
    for (skeletons) |skel| {
        const provider = Provider.fromWire(skel.provider) orelse continue;
        const parsed_id = daemon_proxy.localIdFromWire(skel.session_id);
        const id = if (parsed_id) |n| (if (n == 0) model.next_id else n) else model.next_id;
        model.restoreSession(
            id,
            skel.title,
            provider,
            !skel.has_started,
            skel.has_started,
            skel.project_path,
            "",
            "",
            "",
            "",
            "",
            "",
            0,
            0,
        );
    }
    if (model.session_count == 0) return;
    model.selected = model.session_store[0].id;
    model.task_state_loaded = true;
    model.pending_daemon_catalog = false;
}

/// Best-effort one-shot hello + saveTaskState. Missing address is a no-op.
/// Sidecar failure must not roll back the local catalog already written.
fn mirrorSaveTaskStateIfPossible(model: *Model, session_id: u32, fx: *main.Effects) void {
    const session = model.sessionById(session_id) orelse return;
    if (!session.hasStarted()) return;
    const address = resolveDaemonMirrorAddress(model);
    if (address.len == 0) return;

    var id_buf: [36]u8 = undefined;
    const wire_id = daemon_proxy.wireUuid(session.id, &id_buf);
    const runtime_mode = if (session.accessMode().len > 0) session.accessMode() else main.default_access_mode;
    var stdin_buf: [4096]u8 = undefined;
    const stdin = daemon_proxy.writeSaveStdin(&stdin_buf, .{
        .token = model.daemonToken(),
        .skeleton = .{
            .session_id = wire_id,
            .title = session.title(),
            .provider = session.provider.wireName(),
            .project_path = session.projectPath(),
            .has_started = true,
            .runtime_mode = runtime_mode,
        },
    }) catch return;

    const key = model.next_daemon_key;
    model.next_daemon_key += 1;
    fx.spawn(.{
        .key = key,
        .argv = &.{ model.sidecarPath(), daemon_proxy.SUBCOMMAND, address },
        .stdin = stdin,
        .max_line_bytes = main.daemon_line_bytes,
        .on_line = main.Effects.lineMsg(.fx_line),
        .on_exit = main.Effects.exitMsg(.fx_exit),
    });
}

/// Best-effort one-shot hello + bare `closeSession`. Missing address is
/// a no-op. Sidecar failure must not write the session back.
fn maybeCloseDaemonSession(model: *Model, fx: *main.Effects, session_id: []const u8, address: []const u8) void {
    if (address.len == 0) return;

    var stdin_buf: [4096]u8 = undefined;
    const stdin = daemon_proxy.writeCloseStdin(&stdin_buf, .{
        .token = model.daemonToken(),
        .session_id = session_id,
    }) catch return;

    const key = model.next_daemon_key;
    model.next_daemon_key += 1;
    fx.spawn(.{
        .key = key,
        .argv = &.{ model.sidecarPath(), daemon_proxy.SUBCOMMAND, address },
        .stdin = stdin,
        .max_line_bytes = main.daemon_line_bytes,
        .on_line = main.Effects.lineMsg(.fx_line),
        .on_exit = main.Effects.exitMsg(.fx_exit),
    });
}

pub fn hydrateIfPossible(model: *Model, session_id: u32) void {
    const io = model.store_io orelse return;
    hydrateSession(model, session_id, std.heap.page_allocator, io);
}

/// Empty local transcript + a daemon address → one-shot hello +
/// `hydrateSession`. Local turns win: a session that already has turns
/// is left alone. Sidecar failure keeps the empty transcript and does
/// not clear the catalog.
pub fn maybeHydrateDaemonSession(model: *Model, fx: *main.Effects, session_id: u32) void {
    const session = model.sessionById(session_id) orelse return;
    if (session.daemon_hydrate_started) return;
    if (model.turnCount(session_id) > 0) return;
    const address = resolveDaemonMirrorAddress(model);
    if (address.len == 0) return;

    var id_buf: [36]u8 = undefined;
    const wire_id = daemon_proxy.wireUuid(session.id, &id_buf);
    var stdin_buf: [4096]u8 = undefined;
    const stdin = daemon_proxy.writeHydrateStdin(&stdin_buf, .{
        .token = model.daemonToken(),
        .session_id = wire_id,
    }) catch return;

    session.daemon_hydrate_started = true;
    const key = model.next_daemon_key;
    model.next_daemon_key += 1;
    model.daemon_hydrate_key = key;
    model.daemon_hydrate_session = session_id;
    fx.spawn(.{
        .key = key,
        .argv = &.{ model.sidecarPath(), daemon_proxy.SUBCOMMAND, address },
        .stdin = stdin,
        .max_line_bytes = main.daemon_line_bytes,
        .on_line = main.Effects.lineMsg(.fx_line),
        .on_exit = main.Effects.exitMsg(.fx_exit),
    });
}

/// Apply a sidecar stdout line only while a daemon hydrate is in flight
/// for a session that still has no local turns. Unparsed / failed /
/// null-session lines leave the empty transcript in place.
pub fn applyDaemonHydrateLine(model: *Model, line: []const u8) void {
    const session_id = model.daemon_hydrate_session;
    if (session_id == 0) return;
    if (model.sessionById(session_id) == null) return;
    if (model.turnCount(session_id) > 0) return;

    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const parsed = protocol.parseHydratedSession(arena_state.allocator(), line);
    if (!parsed.ok) return;
    applyDaemonHydrate(model, session_id, parsed);
}

fn applyDaemonHydrate(model: *Model, session_id: u32, parsed: protocol.ParsedHydrate) void {
    if (model.sessionById(session_id) == null) return;
    model.dropTurnsForSession(session_id);
    model.dropQueuedForSession(session_id);
    for (parsed.messages[0..parsed.message_count]) |message| {
        const role = roleFromHydrate(message.role) orelse continue;
        _ = model.appendTurn(session_id, role, message.content);
    }
    for (parsed.queued[0..parsed.queued_count]) |queued| {
        _ = model.enqueue(session_id, queued.content);
    }
    if (model.sessionById(session_id)) |session| session.detail_loaded = true;
}

fn roleFromHydrate(name: []const u8) ?Role {
    if (std.mem.eql(u8, name, "user")) return .user;
    if (std.mem.eql(u8, name, "assistant")) return .assistant;
    return null;
}

fn upsertDraft(model: *const Model, io: std.Io, key: []const u8, text: []const u8, image_path: []const u8) !void {
    const dir = model.storeDir();
    if (dir.len == 0 or key.len == 0) return;
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var document = readDraftDocument(arena, io, dir) catch |err| switch (err) {
        error.FileNotFound => DraftDocument{},
        else => return,
    };
    applyDraftChange(&document, arena, key, text, image_path) catch return;
    try writeDraftDocument(arena, io, dir, document);
}

const LoadedDraft = struct {
    text: []const u8,
    image_path: []const u8,
};

fn readDraftRecord(
    allocator: std.mem.Allocator,
    io: std.Io,
    dir: []const u8,
    key: []const u8,
    text_dest: []u8,
    image_dest: []u8,
) ?LoadedDraft {
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const document = readDraftDocument(arena_state.allocator(), io, dir) catch return null;
    for (document.drafts) |entry| {
        if (!std.mem.eql(u8, entry.key, key)) continue;
        const text_take = @min(text_dest.len, entry.text.len);
        @memcpy(text_dest[0..text_take], entry.text[0..text_take]);
        const image_take = @min(image_dest.len, entry.image_path.len);
        @memcpy(image_dest[0..image_take], entry.image_path[0..image_take]);
        return .{ .text = text_dest[0..text_take], .image_path = image_dest[0..image_take] };
    }
    return null;
}

const DraftEntry = struct {
    key: []const u8,
    text: []const u8,
    image_path: []const u8 = "",
};

const DraftDocument = struct {
    version: u32 = format_version,
    drafts: []DraftEntry = &.{},
};

fn applyDraftChange(document: *DraftDocument, arena: std.mem.Allocator, key: []const u8, text: []const u8, image_path: []const u8) !void {
    const trimmed = std.mem.trim(u8, text, " \t\r\n");
    const image = std.mem.trim(u8, image_path, " \t\r\n");
    var kept: usize = 0;
    for (document.drafts) |entry| {
        if (std.mem.eql(u8, entry.key, key)) continue;
        document.drafts[kept] = entry;
        kept += 1;
    }
    document.drafts = document.drafts[0..kept];
    if (trimmed.len == 0 and image.len == 0) return;
    if (document.drafts.len >= max_draft_entries) {
        document.drafts = document.drafts[1..];
    }
    const next = try arena.alloc(DraftEntry, document.drafts.len + 1);
    @memcpy(next[0..document.drafts.len], document.drafts);
    next[document.drafts.len] = .{
        .key = try arena.dupe(u8, key),
        .text = try arena.dupe(u8, text),
        .image_path = try arena.dupe(u8, image),
    };
    document.drafts = next;
}

fn readDraftDocument(arena: std.mem.Allocator, io: std.Io, dir: []const u8) !DraftDocument {
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = draftsPath(dir, &path_buf) orelse return error.NoSpaceLeft;
    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, path, arena, .limited(max_drafts_bytes));
    return parseDraftDocument(arena, bytes);
}

fn parseDraftDocument(arena: std.mem.Allocator, bytes: []const u8) !DraftDocument {
    const root = std.json.parseFromSliceLeaky(std.json.Value, arena, bytes, .{}) catch return error.Corrupt;
    const obj = switch (root) {
        .object => |o| o,
        else => return error.Corrupt,
    };
    const version = jsonUint(obj.get("version")) orelse return error.Corrupt;
    if (version != format_version) return error.Corrupt;
    const drafts_val = obj.get("drafts") orelse return error.Corrupt;
    const drafts_obj = switch (drafts_val) {
        .object => |o| o,
        else => return error.Corrupt,
    };
    var drafts: std.ArrayList(DraftEntry) = .empty;
    var it = drafts_obj.iterator();
    while (it.next()) |entry| {
        switch (entry.value_ptr.*) {
            .string => |s| try drafts.append(arena, .{ .key = entry.key_ptr.*, .text = s }),
            .object => |o| try drafts.append(arena, .{
                .key = entry.key_ptr.*,
                .text = jsonString(o.get("text")) orelse "",
                .image_path = jsonString(o.get("image_path")) orelse "",
            }),
            else => continue,
        }
    }
    return .{ .version = version, .drafts = try drafts.toOwnedSlice(arena) };
}

fn writeDraftDocument(allocator: std.mem.Allocator, io: std.Io, dir: []const u8, document: DraftDocument) !void {
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = draftsPath(dir, &path_buf) orelse return error.NoSpaceLeft;
    const bytes = try encodeDraftDocument(allocator, document);
    defer allocator.free(bytes);
    try atomicWrite(io, path, bytes);
}

fn encodeDraftDocument(allocator: std.mem.Allocator, document: DraftDocument) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    try out.appendSlice(allocator, "{\"version\":");
    try appendUint(&out, allocator, document.version);
    try out.appendSlice(allocator, ",\"drafts\":{");
    for (document.drafts, 0..) |entry, i| {
        if (i != 0) try out.append(allocator, ',');
        try appendJsonString(&out, allocator, entry.key);
        try out.appendSlice(allocator, ":{\"text\":");
        try appendJsonString(&out, allocator, entry.text);
        try out.appendSlice(allocator, ",\"image_path\":");
        try appendJsonString(&out, allocator, entry.image_path);
        try out.append(allocator, '}');
    }
    try out.appendSlice(allocator, "}}");
    return out.toOwnedSlice(allocator);
}

const StoredTurn = struct {
    id: u32,
    role: Role,
    body: []const u8,
};

const StoredQueued = struct {
    id: u32,
    text: []const u8,
};

const StoredRewind = struct {
    sha: []const u8,
    ref: []const u8,
    recorded_at: i64,
};

const StoredSession = struct {
    id: u32,
    title: []const u8,
    provider: Provider,
    untitled: bool,
    has_started: bool,
    project_path: []const u8 = "",
    fx_session_id: []const u8 = "",
    runtime_id: []const u8 = "",
    model: []const u8 = "",
    access_mode: []const u8 = "",
    interaction_mode: []const u8 = "",
    reasoning_effort: []const u8 = "",
    turns: []StoredTurn,
    queued_messages: []StoredQueued,
    rewind_refs: []StoredRewind = &.{},
    worktree_snapshot_sha: []const u8 = "",
    worktree_turn_end_sha: []const u8 = "",
    worktree_turn_diff_sha: []const u8 = "",
    folder_id: u32 = 0,
    updated_at: i64 = 0,
    context_used: u64 = 0,
    context_size: u64 = 0,
    available_commands: []StoredCommand = &.{},
    thread_goal_objective: []const u8 = "",
    thread_goal_status: []const u8 = "",
    thread_goal_token_budget: ?u64 = null,
    thread_goal_tokens_used: ?u64 = null,
    thread_goal_time_used_seconds: ?u64 = null,
};

const StoredCommand = struct {
    name: []const u8,
    description: []const u8 = "",
};

const StoredFolder = struct {
    id: u32,
    title: []const u8,
};

const Document = struct {
    version: u32 = format_version,
    selected: u32 = 0,
    next_id: u32 = 1,
    next_turn_id: u32 = 1,
    next_queued_id: u32 = 1,
    next_folder_id: u32 = 1,
    last_project_path: []const u8 = "",
    last_model: []const u8 = "",
    last_access_mode: []const u8 = "",
    last_interaction_mode: []const u8 = "",
    last_reasoning_effort: []const u8 = "",
    last_daemon_address: []const u8 = "",
    theme_preference: main.ThemePreference = .system,
    language_preference: main.LanguagePreference = .system,
    sidebar_collapsed: bool = false,
    sidebar_width: u32 = 0,
    right_panel_open: bool = false,
    right_panel_width: u32 = 0,
    folders: []StoredFolder = &.{},
    collapsed_folder_ids: []u32 = &.{},
    sessions: []StoredSession = &.{},

    fn empty(model: *const Model) Document {
        return .{
            .selected = model.selected,
            .next_id = model.next_id,
            .next_turn_id = model.next_turn_id,
            .next_queued_id = model.next_queued_id,
            .next_folder_id = model.next_folder_id,
            .last_project_path = model.lastProjectPath(),
            .last_model = model.lastModel(),
            .last_access_mode = model.lastAccessMode(),
            .last_interaction_mode = model.lastInteractionMode(),
            .last_reasoning_effort = model.lastReasoningEffort(),
            .last_daemon_address = lastDaemonAddressForSave(model),
            .theme_preference = model.theme_preference,
            .language_preference = model.language_preference,
            .sidebar_collapsed = model.sidebar_collapsed,
            .sidebar_width = model.sidebarWidthPixels(),
            .right_panel_open = model.right_panel_open,
            .right_panel_width = model.rightPanelWidthPixels(),
            .sessions = &.{},
        };
    }
};

fn lastProjectPathForSave(model: *const Model, session: *const main.Session) []const u8 {
    if (model.lastProjectPath().len > 0) return model.lastProjectPath();
    return session.projectPath();
}

fn lastModelForSave(model: *const Model, session: *const main.Session) []const u8 {
    if (model.lastModel().len > 0) return model.lastModel();
    return session.model();
}

fn lastAccessModeForSave(model: *const Model, session: *const main.Session) []const u8 {
    if (model.lastAccessMode().len > 0) return model.lastAccessMode();
    return session.accessMode();
}

fn lastInteractionModeForSave(model: *const Model, session: *const main.Session) []const u8 {
    if (model.lastInteractionMode().len > 0) return model.lastInteractionMode();
    return session.interactionMode();
}

fn lastReasoningEffortForSave(model: *const Model, session: *const main.Session) []const u8 {
    if (model.lastReasoningEffort().len > 0) return model.lastReasoningEffort();
    return session.reasoningEffort();
}

fn lastDaemonAddressForSave(model: *const Model) []const u8 {
    if (model.lastDaemonAddress().len > 0) return model.lastDaemonAddress();
    return model.daemonAddress();
}

fn applyCatalog(model: *Model, allocator: std.mem.Allocator, bytes: []const u8) !void {
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const document = try parseDocument(arena_state.allocator(), bytes);

    model.clearSessions();
    model.clearFolders();
    model.next_id = document.next_id;
    model.next_turn_id = document.next_turn_id;
    model.next_queued_id = document.next_queued_id;
    model.next_folder_id = if (document.next_folder_id > 0) document.next_folder_id else 1;
    model.setLastProjectPath(document.last_project_path);
    model.setLastModel(document.last_model);
    model.setLastAccessMode(document.last_access_mode);
    model.setLastInteractionMode(document.last_interaction_mode);
    model.setLastReasoningEffort(document.last_reasoning_effort);
    model.setLastDaemonAddress(document.last_daemon_address);
    model.theme_preference = document.theme_preference;
    model.language_preference = document.language_preference;
    model.sidebar_collapsed = document.sidebar_collapsed;
    model.applySidebarWidth(document.sidebar_width);
    model.right_panel_open = document.right_panel_open;
    model.applyRightPanelWidth(document.right_panel_width);
    model.syncSidebarSplit();
    for (document.folders) |folder| {
        const collapsed = folderIdCollapsed(document.collapsed_folder_ids, folder.id);
        model.restoreFolder(folder.id, folder.title, collapsed);
    }
    for (document.sessions) |stored| {
        model.restoreSession(stored.id, stored.title, stored.provider, stored.untitled, stored.has_started, stored.project_path, stored.fx_session_id, stored.model, stored.access_mode, stored.runtime_id, stored.interaction_mode, stored.reasoning_effort, stored.folder_id, stored.updated_at);
        applyRewindRefs(model, stored.id, stored.rewind_refs);
        applyWorktreeSnapshotSha(model, stored.id, stored.worktree_snapshot_sha);
        applyWorktreeTurnEndSha(model, stored.id, stored.worktree_turn_end_sha);
        applyWorktreeTurnDiffSha(model, stored.id, stored.worktree_turn_diff_sha);
        applyContextUsage(model, stored.id, stored.context_used, stored.context_size);
        applyAvailableCommands(model, stored.id, stored.available_commands);
        applyThreadGoal(model, stored.id, stored.thread_goal_objective, stored.thread_goal_status, stored.thread_goal_token_budget, stored.thread_goal_tokens_used, stored.thread_goal_time_used_seconds);
    }
    if (model.sessionById(document.selected) != null) {
        model.selected = document.selected;
    } else if (model.session_count > 0) {
        model.selected = model.session_store[0].id;
    }
}

fn applyDetail(model: *Model, allocator: std.mem.Allocator, bytes: []const u8, session_id: u32) !void {
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const document = try parseDocument(arena_state.allocator(), bytes);
    const stored = findStored(document, session_id) orelse return;
    model.dropTurnsForSession(session_id);
    model.dropQueuedForSession(session_id);
    for (stored.turns) |turn| {
        model.restoreTurn(turn.id, session_id, turn.role, turn.body);
    }
    for (stored.queued_messages) |queued| {
        model.restoreQueued(queued.id, session_id, queued.text);
    }
    applyRewindRefs(model, session_id, stored.rewind_refs);
    applyWorktreeSnapshotSha(model, session_id, stored.worktree_snapshot_sha);
    applyWorktreeTurnEndSha(model, session_id, stored.worktree_turn_end_sha);
    applyWorktreeTurnDiffSha(model, session_id, stored.worktree_turn_diff_sha);
    applyContextUsage(model, session_id, stored.context_used, stored.context_size);
    applyAvailableCommands(model, session_id, stored.available_commands);
    applyThreadGoal(model, session_id, stored.thread_goal_objective, stored.thread_goal_status, stored.thread_goal_token_budget, stored.thread_goal_tokens_used, stored.thread_goal_time_used_seconds);
}

fn findStored(document: Document, id: u32) ?*StoredSession {
    for (document.sessions) |*session| {
        if (session.id == id) return session;
    }
    return null;
}

fn upsertSession(document: *Document, arena: std.mem.Allocator, model: *const Model, session_id: u32) !void {
    const live = model.sessionByIdConst(session_id) orelse return;
    const incoming = try snapshotSession(arena, model, live);
    if (findStored(document.*, session_id)) |existing| {
        existing.title = incoming.title;
        existing.provider = incoming.provider;
        existing.untitled = incoming.untitled;
        existing.has_started = incoming.has_started;
        existing.project_path = incoming.project_path;
        existing.fx_session_id = incoming.fx_session_id;
        existing.runtime_id = incoming.runtime_id;
        existing.model = incoming.model;
        existing.access_mode = incoming.access_mode;
        existing.interaction_mode = incoming.interaction_mode;
        existing.reasoning_effort = incoming.reasoning_effort;
        existing.folder_id = incoming.folder_id;
        existing.updated_at = incoming.updated_at;
        existing.rewind_refs = incoming.rewind_refs;
        existing.worktree_snapshot_sha = incoming.worktree_snapshot_sha;
        existing.worktree_turn_end_sha = incoming.worktree_turn_end_sha;
        existing.worktree_turn_diff_sha = incoming.worktree_turn_diff_sha;
        existing.context_used = incoming.context_used;
        existing.context_size = incoming.context_size;
        existing.available_commands = incoming.available_commands;
        existing.thread_goal_objective = incoming.thread_goal_objective;
        existing.thread_goal_status = incoming.thread_goal_status;
        existing.thread_goal_token_budget = incoming.thread_goal_token_budget;
        existing.thread_goal_tokens_used = incoming.thread_goal_tokens_used;
        existing.thread_goal_time_used_seconds = incoming.thread_goal_time_used_seconds;
        if (live.detail_loaded) {
            existing.turns = incoming.turns;
            existing.queued_messages = incoming.queued_messages;
        }
        return;
    }
    const next = try arena.alloc(StoredSession, document.sessions.len + 1);
    @memcpy(next[0..document.sessions.len], document.sessions);
    next[document.sessions.len] = incoming;
    document.sessions = next;
}

fn dropStoredSession(document: *Document, session_id: u32) void {
    var kept: usize = 0;
    for (document.sessions) |session| {
        if (session.id == session_id) continue;
        document.sessions[kept] = session;
        kept += 1;
    }
    document.sessions = document.sessions[0..kept];
}

fn snapshotSession(arena: std.mem.Allocator, model: *const Model, session: *const main.Session) !StoredSession {
    var turns: std.ArrayList(StoredTurn) = .empty;
    var queued: std.ArrayList(StoredQueued) = .empty;
    if (session.detail_loaded) {
        for (model.turn_store[0..model.turn_count]) |turn| {
            if (turn.session_id != session.id) continue;
            try turns.append(arena, .{
                .id = turn.id,
                .role = turn.role,
                .body = try arena.dupe(u8, turn.text()),
            });
        }
        for (model.queued_store[0..model.queued_count]) |item| {
            if (item.session_id != session.id) continue;
            try queued.append(arena, .{
                .id = item.id,
                .text = try arena.dupe(u8, item.text()),
            });
        }
    }
    return .{
        .id = session.id,
        .title = try arena.dupe(u8, session.title()),
        .provider = session.provider,
        .untitled = session.untitled,
        .has_started = session.hasStarted(),
        .project_path = try arena.dupe(u8, session.projectPath()),
        .fx_session_id = try arena.dupe(u8, session.fxSessionId()),
        .runtime_id = try arena.dupe(u8, session.runtimeId()),
        .model = try arena.dupe(u8, session.model()),
        .access_mode = try arena.dupe(u8, session.accessMode()),
        .interaction_mode = try arena.dupe(u8, session.interactionMode()),
        .reasoning_effort = try arena.dupe(u8, session.reasoningEffort()),
        .folder_id = session.folder_id,
        .updated_at = session.updated_at,
        .context_used = session.context_used,
        .context_size = session.context_size,
        .available_commands = try snapshotAvailableCommands(arena, session),
        .thread_goal_objective = try arena.dupe(u8, session.threadGoalObjective()),
        .thread_goal_status = try arena.dupe(u8, session.threadGoalStatus()),
        .thread_goal_token_budget = session.threadGoalTokenBudget(),
        .thread_goal_tokens_used = session.threadGoalTokensUsed(),
        .thread_goal_time_used_seconds = session.threadGoalTimeUsedSeconds(),
        .turns = try turns.toOwnedSlice(arena),
        .queued_messages = try queued.toOwnedSlice(arena),
        .rewind_refs = try snapshotRewindRefs(arena, session),
        .worktree_snapshot_sha = try arena.dupe(u8, session.worktreeSnapshotSha()),
        .worktree_turn_end_sha = try arena.dupe(u8, session.worktreeTurnEndSha()),
        .worktree_turn_diff_sha = try arena.dupe(u8, session.worktreeTurnDiffSha()),
    };
}

fn snapshotRewindRefs(arena: std.mem.Allocator, session: *const main.Session) ![]StoredRewind {
    const live = session.rewindRefs();
    const out = try arena.alloc(StoredRewind, live.len);
    for (live, 0..) |item, i| {
        out[i] = .{
            .sha = try arena.dupe(u8, item.sha()),
            .ref = try arena.dupe(u8, item.refName()),
            .recorded_at = item.recorded_at,
        };
    }
    return out;
}

fn applyRewindRefs(model: *Model, session_id: u32, refs: []const StoredRewind) void {
    const session = model.sessionById(session_id) orelse return;
    session.clearRewindRefs();
    for (refs) |item| {
        session.appendRewindRef(item.sha, item.ref, item.recorded_at);
    }
}

fn applyWorktreeSnapshotSha(model: *Model, session_id: u32, sha: []const u8) void {
    const session = model.sessionById(session_id) orelse return;
    session.clearWorktreeSnapshotSha();
    session.setWorktreeSnapshotSha(sha);
}

fn applyWorktreeTurnEndSha(model: *Model, session_id: u32, sha: []const u8) void {
    const session = model.sessionById(session_id) orelse return;
    session.clearWorktreeTurnEndSha();
    session.setWorktreeTurnEndSha(sha);
}

fn applyWorktreeTurnDiffSha(model: *Model, session_id: u32, sha: []const u8) void {
    const session = model.sessionById(session_id) orelse return;
    session.clearWorktreeTurnDiffSha();
    session.setWorktreeTurnDiffSha(sha);
}

fn applyContextUsage(model: *Model, session_id: u32, used: u64, size: u64) void {
    const session = model.sessionById(session_id) orelse return;
    session.setContextUsage(used, size);
}

fn snapshotAvailableCommands(arena: std.mem.Allocator, session: *const main.Session) ![]StoredCommand {
    const live = session.availableCommands();
    const out = try arena.alloc(StoredCommand, live.len);
    for (live, 0..) |item, i| {
        out[i] = .{
            .name = try arena.dupe(u8, item.name()),
            .description = try arena.dupe(u8, item.description()),
        };
    }
    return out;
}

fn applyAvailableCommands(model: *Model, session_id: u32, commands: []const StoredCommand) void {
    const session = model.sessionById(session_id) orelse return;
    session.clearAvailableCommands();
    for (commands) |item| {
        session.appendAvailableCommand(item.name, item.description);
    }
}

fn applyThreadGoal(
    model: *Model,
    session_id: u32,
    objective: []const u8,
    status: []const u8,
    token_budget: ?u64,
    tokens_used: ?u64,
    time_used_seconds: ?u64,
) void {
    const session = model.sessionById(session_id) orelse return;
    session.setThreadGoal(objective, status);
    session.setThreadGoalUsage(token_budget, tokens_used, time_used_seconds);
}

fn readDocument(arena: std.mem.Allocator, io: std.Io, dir: []const u8) !Document {
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = catalogPath(dir, &path_buf) orelse return error.NoSpaceLeft;
    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, path, arena, .limited(max_document_bytes));
    return parseDocument(arena, bytes);
}

fn parseDocument(arena: std.mem.Allocator, bytes: []const u8) !Document {
    const root = std.json.parseFromSliceLeaky(std.json.Value, arena, bytes, .{}) catch return error.Corrupt;
    const obj = switch (root) {
        .object => |o| o,
        else => return error.Corrupt,
    };
    const version = jsonUint(obj.get("version")) orelse return error.Corrupt;
    if (version != format_version) return error.Corrupt;

    const sessions_val = obj.get("sessions") orelse return error.Corrupt;
    const sessions_arr = switch (sessions_val) {
        .array => |a| a,
        else => return error.Corrupt,
    };

    var sessions: std.ArrayList(StoredSession) = .empty;
    for (sessions_arr.items) |item| {
        try sessions.append(arena, try parseSession(arena, item));
    }

    return .{
        .version = version,
        .selected = jsonUint(obj.get("selected")) orelse 0,
        .next_id = jsonUint(obj.get("next_id")) orelse 1,
        .next_turn_id = jsonUint(obj.get("next_turn_id")) orelse 1,
        .next_queued_id = jsonUint(obj.get("next_queued_id")) orelse 1,
        .last_project_path = jsonString(obj.get("last_project_path")) orelse "",
        .last_model = jsonString(obj.get("last_model")) orelse "",
        .last_access_mode = jsonString(obj.get("last_access_mode")) orelse "",
        .last_interaction_mode = jsonString(obj.get("last_interaction_mode")) orelse "",
        .last_reasoning_effort = jsonString(obj.get("last_reasoning_effort")) orelse "",
        .last_daemon_address = jsonString(obj.get("last_daemon_address")) orelse "",
        .theme_preference = main.ThemePreference.fromPersist(jsonString(obj.get("theme_preference")) orelse ""),
        .language_preference = main.LanguagePreference.fromPersist(jsonString(obj.get("language_preference")) orelse ""),
        .sidebar_collapsed = jsonBool(obj.get("sidebar_collapsed")) orelse false,
        .sidebar_width = jsonUint(obj.get("sidebar_width")) orelse 0,
        .right_panel_open = jsonBool(obj.get("right_panel_open")) orelse false,
        .right_panel_width = jsonUint(obj.get("right_panel_width")) orelse 0,
        .next_folder_id = jsonUint(obj.get("next_folder_id")) orelse 1,
        .folders = try parseFolders(arena, obj.get("folders")),
        .collapsed_folder_ids = try parseUintList(arena, obj.get("collapsed_folder_ids")),
        .sessions = try sessions.toOwnedSlice(arena),
    };
}

fn parseSession(arena: std.mem.Allocator, value: std.json.Value) !StoredSession {
    const obj = switch (value) {
        .object => |o| o,
        else => return error.Corrupt,
    };
    const id = jsonUint(obj.get("id")) orelse return error.Corrupt;
    const title = jsonString(obj.get("title")) orelse return error.Corrupt;
    const provider_name = jsonString(obj.get("provider")) orelse return error.Corrupt;
    const provider = protocol.ProviderId.fromWire(provider_name) orelse return error.Corrupt;
    const untitled = jsonBool(obj.get("untitled")) orelse false;
    const has_started = jsonBool(obj.get("has_started")) orelse false;

    var turns: std.ArrayList(StoredTurn) = .empty;
    if (obj.get("turns")) |turns_val| {
        const turns_arr = switch (turns_val) {
            .array => |a| a,
            else => return error.Corrupt,
        };
        for (turns_arr.items) |item| {
            try turns.append(arena, try parseTurn(item));
        }
    }

    var queued: std.ArrayList(StoredQueued) = .empty;
    if (obj.get("queued_messages")) |queued_val| {
        const queued_arr = switch (queued_val) {
            .array => |a| a,
            else => return error.Corrupt,
        };
        for (queued_arr.items) |item| {
            try queued.append(arena, try parseQueued(item));
        }
    }

    return .{
        .id = id,
        .title = title,
        .provider = provider,
        .untitled = untitled,
        .has_started = has_started,
        .project_path = jsonString(obj.get("project_path")) orelse "",
        .fx_session_id = jsonString(obj.get("fx_session_id")) orelse "",
        .runtime_id = jsonString(obj.get("runtime_id")) orelse "",
        .model = jsonString(obj.get("model")) orelse "",
        .access_mode = jsonString(obj.get("access_mode")) orelse "",
        .interaction_mode = jsonString(obj.get("interaction_mode")) orelse "",
        .reasoning_effort = jsonString(obj.get("reasoning_effort")) orelse "",
        .turns = try turns.toOwnedSlice(arena),
        .queued_messages = try queued.toOwnedSlice(arena),
        .rewind_refs = try parseRewindRefs(arena, obj.get("rewind_refs")),
        .worktree_snapshot_sha = jsonString(obj.get("worktree_snapshot_sha")) orelse "",
        .worktree_turn_end_sha = jsonString(obj.get("worktree_turn_end_sha")) orelse "",
        .worktree_turn_diff_sha = jsonString(obj.get("worktree_turn_diff_sha")) orelse "",
        .folder_id = jsonUint(obj.get("folder_id")) orelse 0,
        .updated_at = jsonInt(obj.get("updated_at")) orelse 0,
        .context_used = jsonU64(obj.get("context_used")) orelse 0,
        .context_size = jsonU64(obj.get("context_size")) orelse 0,
        .available_commands = try parseAvailableCommands(arena, obj.get("available_commands")),
        .thread_goal_objective = jsonString(obj.get("thread_goal_objective")) orelse "",
        .thread_goal_status = jsonString(obj.get("thread_goal_status")) orelse "",
        .thread_goal_token_budget = jsonU64(obj.get("thread_goal_token_budget")),
        .thread_goal_tokens_used = jsonU64(obj.get("thread_goal_tokens_used")),
        .thread_goal_time_used_seconds = jsonU64(obj.get("thread_goal_time_used_seconds")),
    };
}

fn parseFolders(arena: std.mem.Allocator, value: ?std.json.Value) ![]StoredFolder {
    const folders_val = value orelse return &.{};
    const folders_arr = switch (folders_val) {
        .array => |a| a,
        else => return error.Corrupt,
    };
    var folders: std.ArrayList(StoredFolder) = .empty;
    for (folders_arr.items) |item| {
        try folders.append(arena, try parseFolder(item));
    }
    return folders.toOwnedSlice(arena);
}

fn parseFolder(value: std.json.Value) !StoredFolder {
    const obj = switch (value) {
        .object => |o| o,
        else => return error.Corrupt,
    };
    const id = jsonUint(obj.get("id")) orelse return error.Corrupt;
    const title = jsonString(obj.get("title")) orelse return error.Corrupt;
    return .{ .id = id, .title = title };
}

fn parseUintList(arena: std.mem.Allocator, value: ?std.json.Value) ![]u32 {
    const list_val = value orelse return &.{};
    const list_arr = switch (list_val) {
        .array => |a| a,
        else => return error.Corrupt,
    };
    var ids: std.ArrayList(u32) = .empty;
    for (list_arr.items) |item| {
        const id = jsonUint(item) orelse return error.Corrupt;
        try ids.append(arena, id);
    }
    return ids.toOwnedSlice(arena);
}

fn folderIdCollapsed(ids: []const u32, folder_id: u32) bool {
    for (ids) |id| {
        if (id == folder_id) return true;
    }
    return false;
}

fn parseAvailableCommands(arena: std.mem.Allocator, value: ?std.json.Value) ![]StoredCommand {
    const commands_val = value orelse return &.{};
    const commands_arr = switch (commands_val) {
        .array => |a| a,
        else => return error.Corrupt,
    };
    var commands: std.ArrayList(StoredCommand) = .empty;
    for (commands_arr.items) |item| {
        const parsed = parseAvailableCommand(item) catch continue;
        if (parsed.name.len == 0) continue;
        try commands.append(arena, parsed);
        if (commands.items.len >= main.max_available_commands) break;
    }
    return commands.toOwnedSlice(arena);
}

fn parseAvailableCommand(value: std.json.Value) !StoredCommand {
    const obj = switch (value) {
        .object => |o| o,
        else => return error.Corrupt,
    };
    const name = jsonString(obj.get("name")) orelse return error.Corrupt;
    return .{
        .name = name,
        .description = jsonString(obj.get("description")) orelse "",
    };
}

fn parseRewindRefs(arena: std.mem.Allocator, value: ?std.json.Value) ![]StoredRewind {
    const refs_val = value orelse return &.{};
    const refs_arr = switch (refs_val) {
        .array => |a| a,
        else => return error.Corrupt,
    };
    var refs: std.ArrayList(StoredRewind) = .empty;
    for (refs_arr.items) |item| {
        try refs.append(arena, try parseRewind(item));
    }
    if (refs.items.len > rewind.max_refs) {
        const start = refs.items.len - rewind.max_refs;
        return refs.items[start..];
    }
    return refs.toOwnedSlice(arena);
}

fn parseRewind(value: std.json.Value) !StoredRewind {
    const obj = switch (value) {
        .object => |o| o,
        else => return error.Corrupt,
    };
    const sha = jsonString(obj.get("sha")) orelse return error.Corrupt;
    const ref = jsonString(obj.get("ref")) orelse rewind.recorded_ref;
    const recorded_at = jsonInt(obj.get("recorded_at")) orelse 0;
    return .{ .sha = sha, .ref = ref, .recorded_at = recorded_at };
}

fn parseQueued(value: std.json.Value) !StoredQueued {
    const obj = switch (value) {
        .object => |o| o,
        else => return error.Corrupt,
    };
    const id = jsonUint(obj.get("id")) orelse return error.Corrupt;
    const text = jsonString(obj.get("text")) orelse return error.Corrupt;
    return .{ .id = id, .text = text };
}

fn parseTurn(value: std.json.Value) !StoredTurn {
    const obj = switch (value) {
        .object => |o| o,
        else => return error.Corrupt,
    };
    const id = jsonUint(obj.get("id")) orelse return error.Corrupt;
    const role_name = jsonString(obj.get("role")) orelse return error.Corrupt;
    const role = roleFromWire(role_name) orelse return error.Corrupt;
    const body = jsonString(obj.get("body")) orelse return error.Corrupt;
    return .{ .id = id, .role = role, .body = body };
}

fn jsonUint(value: ?std.json.Value) ?u32 {
    const item = value orelse return null;
    return switch (item) {
        .integer => |n| if (n >= 0 and n <= std.math.maxInt(u32)) @intCast(n) else null,
        else => null,
    };
}

fn jsonU64(value: ?std.json.Value) ?u64 {
    const item = value orelse return null;
    return switch (item) {
        .integer => |n| if (n >= 0) @intCast(n) else null,
        else => null,
    };
}

fn jsonInt(value: ?std.json.Value) ?i64 {
    const item = value orelse return null;
    return switch (item) {
        .integer => |n| n,
        else => null,
    };
}

fn jsonString(value: ?std.json.Value) ?[]const u8 {
    const item = value orelse return null;
    return switch (item) {
        .string => |s| s,
        else => null,
    };
}

fn jsonBool(value: ?std.json.Value) ?bool {
    const item = value orelse return null;
    return switch (item) {
        .bool => |b| b,
        else => null,
    };
}

fn roleFromWire(name: []const u8) ?Role {
    if (std.mem.eql(u8, name, "user")) return .user;
    if (std.mem.eql(u8, name, "assistant")) return .assistant;
    if (std.mem.eql(u8, name, "tool")) return .tool;
    if (std.mem.eql(u8, name, "reasoning")) return .reasoning;
    return null;
}

fn roleWire(role: Role) []const u8 {
    return switch (role) {
        .user => "user",
        .assistant => "assistant",
        .tool => "tool",
        .reasoning => "reasoning",
    };
}

fn writeDocument(allocator: std.mem.Allocator, io: std.Io, dir: []const u8, document: Document) !void {
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = catalogPath(dir, &path_buf) orelse return error.NoSpaceLeft;
    const bytes = try encodeDocument(allocator, document);
    defer allocator.free(bytes);
    try atomicWrite(io, path, bytes);
}

fn encodeDocument(allocator: std.mem.Allocator, document: Document) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    try out.appendSlice(allocator, "{\"version\":");
    try appendUint(&out, allocator, document.version);
    try out.appendSlice(allocator, ",\"selected\":");
    try appendUint(&out, allocator, document.selected);
    try out.appendSlice(allocator, ",\"next_id\":");
    try appendUint(&out, allocator, document.next_id);
    try out.appendSlice(allocator, ",\"next_turn_id\":");
    try appendUint(&out, allocator, document.next_turn_id);
    try out.appendSlice(allocator, ",\"next_queued_id\":");
    try appendUint(&out, allocator, document.next_queued_id);
    try out.appendSlice(allocator, ",\"last_project_path\":");
    try appendJsonString(&out, allocator, document.last_project_path);
    try out.appendSlice(allocator, ",\"last_model\":");
    try appendJsonString(&out, allocator, document.last_model);
    try out.appendSlice(allocator, ",\"last_access_mode\":");
    try appendJsonString(&out, allocator, document.last_access_mode);
    try out.appendSlice(allocator, ",\"last_interaction_mode\":");
    try appendJsonString(&out, allocator, document.last_interaction_mode);
    try out.appendSlice(allocator, ",\"last_reasoning_effort\":");
    try appendJsonString(&out, allocator, document.last_reasoning_effort);
    try out.appendSlice(allocator, ",\"last_daemon_address\":");
    try appendJsonString(&out, allocator, document.last_daemon_address);
    try out.appendSlice(allocator, ",\"theme_preference\":");
    try appendJsonString(&out, allocator, document.theme_preference.persistName());
    try out.appendSlice(allocator, ",\"language_preference\":");
    try appendJsonString(&out, allocator, document.language_preference.persistName());
    try out.appendSlice(allocator, ",\"sidebar_collapsed\":");
    try out.appendSlice(allocator, if (document.sidebar_collapsed) "true" else "false");
    try out.appendSlice(allocator, ",\"sidebar_width\":");
    try appendUint(&out, allocator, document.sidebar_width);
    try out.appendSlice(allocator, ",\"right_panel_open\":");
    try out.appendSlice(allocator, if (document.right_panel_open) "true" else "false");
    try out.appendSlice(allocator, ",\"right_panel_width\":");
    try appendUint(&out, allocator, document.right_panel_width);
    try out.appendSlice(allocator, ",\"next_folder_id\":");
    try appendUint(&out, allocator, document.next_folder_id);
    try out.appendSlice(allocator, ",\"folders\":[");
    for (document.folders, 0..) |folder, i| {
        if (i != 0) try out.append(allocator, ',');
        try out.appendSlice(allocator, "{\"id\":");
        try appendUint(&out, allocator, folder.id);
        try out.appendSlice(allocator, ",\"title\":");
        try appendJsonString(&out, allocator, folder.title);
        try out.append(allocator, '}');
    }
    try out.appendSlice(allocator, "],\"collapsed_folder_ids\":[");
    for (document.collapsed_folder_ids, 0..) |id, i| {
        if (i != 0) try out.append(allocator, ',');
        try appendUint(&out, allocator, id);
    }
    try out.appendSlice(allocator, "],\"sessions\":[");
    for (document.sessions, 0..) |session, i| {
        if (i != 0) try out.append(allocator, ',');
        try appendSession(&out, allocator, session);
    }
    try out.appendSlice(allocator, "]}");
    return out.toOwnedSlice(allocator);
}

fn appendSession(out: *std.ArrayList(u8), allocator: std.mem.Allocator, session: StoredSession) !void {
    try out.appendSlice(allocator, "{\"id\":");
    try appendUint(out, allocator, session.id);
    try out.appendSlice(allocator, ",\"title\":");
    try appendJsonString(out, allocator, session.title);
    try out.appendSlice(allocator, ",\"provider\":");
    try appendJsonString(out, allocator, session.provider.wireName());
    try out.appendSlice(allocator, ",\"untitled\":");
    try out.appendSlice(allocator, if (session.untitled) "true" else "false");
    try out.appendSlice(allocator, ",\"has_started\":");
    try out.appendSlice(allocator, if (session.has_started) "true" else "false");
    try out.appendSlice(allocator, ",\"project_path\":");
    try appendJsonString(out, allocator, session.project_path);
    try out.appendSlice(allocator, ",\"fx_session_id\":");
    try appendJsonString(out, allocator, session.fx_session_id);
    try out.appendSlice(allocator, ",\"runtime_id\":");
    try appendJsonString(out, allocator, session.runtime_id);
    try out.appendSlice(allocator, ",\"model\":");
    try appendJsonString(out, allocator, session.model);
    try out.appendSlice(allocator, ",\"access_mode\":");
    try appendJsonString(out, allocator, session.access_mode);
    try out.appendSlice(allocator, ",\"interaction_mode\":");
    try appendJsonString(out, allocator, session.interaction_mode);
    try out.appendSlice(allocator, ",\"reasoning_effort\":");
    try appendJsonString(out, allocator, session.reasoning_effort);
    try out.appendSlice(allocator, ",\"folder_id\":");
    try appendUint(out, allocator, session.folder_id);
    try out.appendSlice(allocator, ",\"updated_at\":");
    try appendInt(out, allocator, session.updated_at);
    try out.appendSlice(allocator, ",\"context_used\":");
    try appendU64(out, allocator, session.context_used);
    try out.appendSlice(allocator, ",\"context_size\":");
    try appendU64(out, allocator, session.context_size);
    try out.appendSlice(allocator, ",\"available_commands\":[");
    for (session.available_commands, 0..) |item, i| {
        if (i != 0) try out.append(allocator, ',');
        try out.appendSlice(allocator, "{\"name\":");
        try appendJsonString(out, allocator, item.name);
        try out.appendSlice(allocator, ",\"description\":");
        try appendJsonString(out, allocator, item.description);
        try out.append(allocator, '}');
    }
    try out.appendSlice(allocator, "],\"thread_goal_objective\":");
    try appendJsonString(out, allocator, session.thread_goal_objective);
    try out.appendSlice(allocator, ",\"thread_goal_status\":");
    try appendJsonString(out, allocator, session.thread_goal_status);
    if (session.thread_goal_token_budget) |budget| {
        try out.appendSlice(allocator, ",\"thread_goal_token_budget\":");
        try appendU64(out, allocator, budget);
    }
    if (session.thread_goal_tokens_used) |used| {
        try out.appendSlice(allocator, ",\"thread_goal_tokens_used\":");
        try appendU64(out, allocator, used);
    }
    if (session.thread_goal_time_used_seconds) |secs| {
        try out.appendSlice(allocator, ",\"thread_goal_time_used_seconds\":");
        try appendU64(out, allocator, secs);
    }
    try out.appendSlice(allocator, ",\"turns\":[");
    for (session.turns, 0..) |turn, i| {
        if (i != 0) try out.append(allocator, ',');
        try out.appendSlice(allocator, "{\"id\":");
        try appendUint(out, allocator, turn.id);
        try out.appendSlice(allocator, ",\"role\":");
        try appendJsonString(out, allocator, roleWire(turn.role));
        try out.appendSlice(allocator, ",\"body\":");
        try appendJsonString(out, allocator, turn.body);
        try out.append(allocator, '}');
    }
    try out.appendSlice(allocator, "],\"queued_messages\":[");
    for (session.queued_messages, 0..) |queued, i| {
        if (i != 0) try out.append(allocator, ',');
        try out.appendSlice(allocator, "{\"id\":");
        try appendUint(out, allocator, queued.id);
        try out.appendSlice(allocator, ",\"text\":");
        try appendJsonString(out, allocator, queued.text);
        try out.append(allocator, '}');
    }
    try out.appendSlice(allocator, "],\"rewind_refs\":[");
    for (session.rewind_refs, 0..) |item, i| {
        if (i != 0) try out.append(allocator, ',');
        try out.appendSlice(allocator, "{\"sha\":");
        try appendJsonString(out, allocator, item.sha);
        try out.appendSlice(allocator, ",\"ref\":");
        try appendJsonString(out, allocator, item.ref);
        try out.appendSlice(allocator, ",\"recorded_at\":");
        try appendInt(out, allocator, item.recorded_at);
        try out.append(allocator, '}');
    }
    try out.appendSlice(allocator, "],\"worktree_snapshot_sha\":");
    try appendJsonString(out, allocator, session.worktree_snapshot_sha);
    try out.appendSlice(allocator, ",\"worktree_turn_end_sha\":");
    try appendJsonString(out, allocator, session.worktree_turn_end_sha);
    try out.appendSlice(allocator, ",\"worktree_turn_diff_sha\":");
    try appendJsonString(out, allocator, session.worktree_turn_diff_sha);
    try out.appendSlice(allocator, "}");
}

fn appendUint(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: u32) !void {
    var num: [10]u8 = undefined;
    const piece = std.fmt.bufPrint(&num, "{d}", .{value}) catch return error.NoSpaceLeft;
    try out.appendSlice(allocator, piece);
}

fn appendU64(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: u64) !void {
    var num: [20]u8 = undefined;
    const piece = std.fmt.bufPrint(&num, "{d}", .{value}) catch return error.NoSpaceLeft;
    try out.appendSlice(allocator, piece);
}

fn appendInt(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: i64) !void {
    var num: [24]u8 = undefined;
    const piece = std.fmt.bufPrint(&num, "{d}", .{value}) catch return error.NoSpaceLeft;
    try out.appendSlice(allocator, piece);
}

fn appendJsonString(out: *std.ArrayList(u8), allocator: std.mem.Allocator, text: []const u8) !void {
    try out.append(allocator, '"');
    for (text) |c| {
        switch (c) {
            '"' => try out.appendSlice(allocator, "\\\""),
            '\\' => try out.appendSlice(allocator, "\\\\"),
            '\n' => try out.appendSlice(allocator, "\\n"),
            '\r' => try out.appendSlice(allocator, "\\r"),
            '\t' => try out.appendSlice(allocator, "\\t"),
            else => {
                if (c < 0x20) {
                    var hex: [6]u8 = undefined;
                    const piece = std.fmt.bufPrint(&hex, "\\u{x:0>4}", .{c}) catch return error.NoSpaceLeft;
                    try out.appendSlice(allocator, piece);
                } else {
                    try out.append(allocator, c);
                }
            },
        }
    }
    try out.append(allocator, '"');
}

fn atomicWrite(io: std.Io, path: []const u8, bytes: []const u8) !void {
    const cwd = std.Io.Dir.cwd();
    var atomic = try cwd.createFileAtomic(io, path, .{ .make_path = true, .replace = true });
    defer atomic.deinit(io);
    try atomic.file.writePositionalAll(io, bytes, 0);
    try atomic.file.sync(io);
    try atomic.replace(io);
}

fn testStoreDir(tmp: *const std.testing.TmpDir, buffer: []u8) ![]const u8 {
    return std.fmt.bufPrint(buffer, ".zig-cache/tmp/{s}/faku-store", .{tmp.sub_path[0..]});
}

fn writeRaw(io: std.Io, dir: []const u8, bytes: []const u8) !void {
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = catalogPath(dir, &path_buf) orelse return error.NoSpaceLeft;
    const cwd = std.Io.Dir.cwd();
    cwd.createDirPath(io, dir) catch {};
    try cwd.writeFile(io, .{ .sub_path = path, .data = bytes });
}

fn seedTwoSessions(model: *Model) struct { a: u32, b: u32 } {
    const a = model.addSession("port waku to zig", .fx);
    _ = model.appendTurn(a, .user, "replace the GPUI desktop");
    _ = model.appendTurn(a, .assistant, "fx-first demo shell");
    const b = model.addSession("fix auth listener", .claude);
    _ = model.appendTurn(b, .user, "the auth listener drops the first event");
    _ = model.appendTurn(b, .assistant, "inspect the reconnect path");
    _ = model.appendTurn(b, .tool, "read src/auth/listener.ts");
    model.selected = a;
    return .{ .a = a, .b = b };
}

test "default store path is Native app_dirs data, not the Waku daemon" {
    var buf: [256]u8 = undefined;
    const linux = try native_sdk.app_dirs.resolveOne(
        .{ .name = app_store_name },
        .linux,
        .{ .home = "/home/alice" },
        .data,
        &buf,
    );
    try std.testing.expectEqualStrings("/home/alice/.local/share/faku", linux);
    try std.testing.expect(std.mem.indexOf(u8, linux, ".waku") == null);

    const macos = try native_sdk.app_dirs.resolveOne(
        .{ .name = app_store_name },
        .macos,
        .{ .home = "/Users/alice" },
        .data,
        &buf,
    );
    try std.testing.expectEqualStrings("/Users/alice/Library/Application Support/faku", macos);
}

test "save + load round-trips two sessions and hydrate restores turns" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try testStoreDir(&tmp, &dir_buf);
    const io = testing.io;
    const allocator = testing.allocator;

    var source = Model{};
    source.task_state_loaded = true;
    source.setStoreDir(dir);
    source.store_io = io;
    const ids = seedTwoSessions(&source);
    try saveSession(&source, ids.a, allocator, io);
    try saveSession(&source, ids.b, allocator, io);

    var loaded = Model{};
    loaded.setStoreDir(dir);
    loaded.store_io = io;
    try testing.expectEqual(LoadKind.loaded, loadCatalog(&loaded, allocator, io));
    try testing.expectEqual(@as(u32, 2), loaded.session_count);
    try testing.expectEqual(ids.a, loaded.session_store[0].id);
    try testing.expectEqual(ids.b, loaded.session_store[1].id);
    try testing.expectEqualStrings("port waku to zig", loaded.session_store[0].title());
    try testing.expectEqualStrings("fix auth listener", loaded.session_store[1].title());
    try testing.expectEqual(Provider.fx, loaded.session_store[0].provider);
    try testing.expectEqual(Provider.claude, loaded.session_store[1].provider);
    try testing.expectEqual(@as(u32, 0), loaded.turn_count);
    try testing.expect(!loaded.session_store[0].detail_loaded);
    try testing.expect(!loaded.session_store[1].detail_loaded);

    hydrateSession(&loaded, ids.a, allocator, io);
    try testing.expect(loaded.session_store[0].detail_loaded);
    try testing.expectEqual(@as(u32, 2), loaded.turn_count);
    try testing.expectEqualStrings("replace the GPUI desktop", loaded.turn_store[0].text());
    try testing.expectEqualStrings("fx-first demo shell", loaded.turn_store[1].text());

    hydrateSession(&loaded, ids.b, allocator, io);
    try testing.expect(loaded.session_store[1].detail_loaded);
    try testing.expectEqual(@as(u32, 5), loaded.turn_count);
    try testing.expectEqualStrings("the auth listener drops the first event", loaded.turn_store[2].text());
    try testing.expectEqual(Role.tool, loaded.turn_store[4].role);
    try testing.expectEqualStrings("read src/auth/listener.ts", loaded.turn_store[4].text());
}

test "session project_path persists and new sessions inherit last_project_path" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try testStoreDir(&tmp, &dir_buf);
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/project", .{tmp.sub_path[0..]});
    const io = testing.io;
    try std.Io.Dir.cwd().createDirPath(io, project);
    const allocator = testing.allocator;

    var source = Model{};
    source.task_state_loaded = true;
    source.setStoreDir(dir);
    source.store_io = io;
    const id = source.addSession("cwd session", .fx);
    if (source.sessionById(id)) |session| session.setProjectPath(project);
    source.setLastProjectPath(project);
    _ = source.appendTurn(id, .user, "open this workspace");
    try saveSession(&source, id, allocator, io);

    var loaded = Model{};
    loaded.setStoreDir(dir);
    loaded.store_io = io;
    try testing.expectEqual(LoadKind.loaded, loadCatalog(&loaded, allocator, io));
    try testing.expectEqual(@as(u32, 1), loaded.session_count);
    try testing.expectEqualStrings(project, loaded.session_store[0].projectPath());
    try testing.expectEqualStrings(project, loaded.lastProjectPath());

    const inherited = loaded.addSession("untitled next", .fx);
    try testing.expectEqualStrings(project, loaded.sessionById(inherited).?.projectPath());
}

test "session context usage persists and hydrates" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try testStoreDir(&tmp, &dir_buf);
    const io = testing.io;
    const allocator = testing.allocator;

    var source = Model{};
    source.task_state_loaded = true;
    source.setStoreDir(dir);
    source.store_io = io;
    const id = source.addSession("usage thread", .fx);
    if (source.sessionById(id)) |session| session.setContextUsage(53000, 200000);
    _ = source.appendTurn(id, .user, "remember usage");
    try saveSession(&source, id, allocator, io);

    var loaded = Model{};
    loaded.setStoreDir(dir);
    try testing.expectEqual(LoadKind.loaded, loadCatalog(&loaded, allocator, io));
    try testing.expectEqual(@as(u64, 53000), loaded.session_store[0].context_used);
    try testing.expectEqual(@as(u64, 200000), loaded.session_store[0].context_size);
    try testing.expectApproxEqAbs(@as(f32, 0.265), loaded.context_usage(), 0.0001);

    hydrateSession(&loaded, loaded.session_store[0].id, allocator, io);
    try testing.expectEqual(@as(u64, 53000), loaded.session_store[0].context_used);
    try testing.expectEqual(@as(u64, 200000), loaded.session_store[0].context_size);
    try testing.expectApproxEqAbs(@as(f32, 0.265), loaded.context_usage(), 0.0001);
}

test "session available_commands persist, replace, and hydrate; empty clears" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try testStoreDir(&tmp, &dir_buf);
    const io = testing.io;
    const allocator = testing.allocator;

    var source = Model{};
    source.task_state_loaded = true;
    source.setStoreDir(dir);
    source.store_io = io;
    const id = source.addSession("commands thread", .fx);
    if (source.sessionById(id)) |session| {
        session.appendAvailableCommand("web", "Search the web for information");
        session.appendAvailableCommand("compact", "");
    }
    _ = source.appendTurn(id, .user, "remember commands");
    try saveSession(&source, id, allocator, io);

    var loaded = Model{};
    loaded.setStoreDir(dir);
    try testing.expectEqual(LoadKind.loaded, loadCatalog(&loaded, allocator, io));
    try testing.expectEqual(@as(usize, 2), loaded.session_store[0].availableCommands().len);
    try testing.expectEqualStrings("web", loaded.session_store[0].availableCommands()[0].name());
    try testing.expectEqualStrings("Search the web for information", loaded.session_store[0].availableCommands()[0].description());
    try testing.expectEqualStrings("compact", loaded.session_store[0].availableCommands()[1].name());
    try testing.expectEqualStrings("", loaded.session_store[0].availableCommands()[1].description());

    hydrateSession(&loaded, loaded.session_store[0].id, allocator, io);
    try testing.expectEqual(@as(usize, 2), loaded.session_store[0].availableCommands().len);
    try testing.expectEqualStrings("web", loaded.session_store[0].availableCommands()[0].name());

    if (loaded.sessionById(loaded.session_store[0].id)) |session| {
        session.clearAvailableCommands();
        session.appendAvailableCommand("plan", "Create a detailed implementation plan");
    }
    try saveSession(&loaded, loaded.session_store[0].id, allocator, io);

    var replaced = Model{};
    replaced.setStoreDir(dir);
    try testing.expectEqual(LoadKind.loaded, loadCatalog(&replaced, allocator, io));
    try testing.expectEqual(@as(usize, 1), replaced.session_store[0].availableCommands().len);
    try testing.expectEqualStrings("plan", replaced.session_store[0].availableCommands()[0].name());

    if (replaced.sessionById(replaced.session_store[0].id)) |session| session.clearAvailableCommands();
    try saveSession(&replaced, replaced.session_store[0].id, allocator, io);

    var cleared = Model{};
    cleared.setStoreDir(dir);
    try testing.expectEqual(LoadKind.loaded, loadCatalog(&cleared, allocator, io));
    try testing.expectEqual(@as(usize, 0), cleared.session_store[0].availableCommands().len);
}

test "session thread goal persists, hydrates, and clears" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try testStoreDir(&tmp, &dir_buf);
    const io = testing.io;
    const allocator = testing.allocator;

    var source = Model{};
    source.task_state_loaded = true;
    source.setStoreDir(dir);
    source.store_io = io;
    const id = source.addSession("goal thread", .fx);
    if (source.sessionById(id)) |session| {
        session.setThreadGoal("Ship the feature", "active");
        session.setThreadGoalUsage(100_000, 12_000, 180);
    }
    _ = source.appendTurn(id, .user, "remember goal");
    try saveSession(&source, id, allocator, io);

    var loaded = Model{};
    loaded.setStoreDir(dir);
    try testing.expectEqual(LoadKind.loaded, loadCatalog(&loaded, allocator, io));
    try testing.expectEqualStrings("Ship the feature", loaded.session_store[0].threadGoalObjective());
    try testing.expectEqualStrings("active", loaded.session_store[0].threadGoalStatus());
    try testing.expectEqual(@as(?u64, 100_000), loaded.session_store[0].threadGoalTokenBudget());
    try testing.expectEqual(@as(?u64, 12_000), loaded.session_store[0].threadGoalTokensUsed());
    try testing.expectEqual(@as(?u64, 180), loaded.session_store[0].threadGoalTimeUsedSeconds());
    try testing.expectEqualStrings("12k/100k · 3m", loaded.session_store[0].threadGoalUsageLabel());

    hydrateSession(&loaded, loaded.session_store[0].id, allocator, io);
    try testing.expectEqualStrings("Ship the feature", loaded.session_store[0].threadGoalObjective());
    try testing.expectEqualStrings("active", loaded.session_store[0].threadGoalStatus());
    try testing.expectEqual(@as(?u64, 12_000), loaded.session_store[0].threadGoalTokensUsed());

    if (loaded.sessionById(loaded.session_store[0].id)) |session| {
        session.setThreadGoalUsage(null, 12_000, null);
    }
    try saveSession(&loaded, loaded.session_store[0].id, allocator, io);

    var used_only = Model{};
    used_only.setStoreDir(dir);
    try testing.expectEqual(LoadKind.loaded, loadCatalog(&used_only, allocator, io));
    try testing.expectEqual(@as(?u64, null), used_only.session_store[0].threadGoalTokenBudget());
    try testing.expectEqual(@as(?u64, 12_000), used_only.session_store[0].threadGoalTokensUsed());
    try testing.expectEqual(@as(?u64, null), used_only.session_store[0].threadGoalTimeUsedSeconds());
    try testing.expectEqualStrings("12k", used_only.session_store[0].threadGoalUsageLabel());

    if (used_only.sessionById(used_only.session_store[0].id)) |session| session.clearThreadGoal();
    try saveSession(&used_only, used_only.session_store[0].id, allocator, io);

    var cleared = Model{};
    cleared.setStoreDir(dir);
    try testing.expectEqual(LoadKind.loaded, loadCatalog(&cleared, allocator, io));
    try testing.expectEqual(@as(usize, 0), cleared.session_store[0].threadGoalObjective().len);
    try testing.expectEqual(@as(usize, 0), cleared.session_store[0].threadGoalStatus().len);
    try testing.expectEqual(@as(?u64, null), cleared.session_store[0].threadGoalTokenBudget());
    try testing.expectEqual(@as(?u64, null), cleared.session_store[0].threadGoalTokensUsed());
    try testing.expectEqual(@as(?u64, null), cleared.session_store[0].threadGoalTimeUsedSeconds());
    try testing.expectEqual(@as(usize, 0), cleared.session_store[0].threadGoalUsageLabel().len);
}

test "session fx_session_id persists and loads" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try testStoreDir(&tmp, &dir_buf);
    const io = testing.io;
    const allocator = testing.allocator;

    var source = Model{};
    source.task_state_loaded = true;
    source.setStoreDir(dir);
    source.store_io = io;
    const id = source.addSession("resume later", .fx);
    if (source.sessionById(id)) |session| session.setFxSessionId("fx-sess-roundtrip");
    _ = source.appendTurn(id, .user, "remember this thread");
    try saveSession(&source, id, allocator, io);

    var loaded = Model{};
    loaded.setStoreDir(dir);
    try testing.expectEqual(LoadKind.loaded, loadCatalog(&loaded, allocator, io));
    try testing.expectEqualStrings("fx-sess-roundtrip", loaded.session_store[0].fxSessionId());
}

test "session runtime_id persists and loads" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try testStoreDir(&tmp, &dir_buf);
    const io = testing.io;
    const allocator = testing.allocator;

    var source = Model{};
    source.task_state_loaded = true;
    source.setStoreDir(dir);
    source.store_io = io;
    const id = source.addSession("runtime later", .fx);
    if (source.sessionById(id)) |session| session.setRuntimeId("00000000-0000-0000-0000-000000000003");
    _ = source.appendTurn(id, .user, "remember this runtime");
    try saveSession(&source, id, allocator, io);

    var loaded = Model{};
    loaded.setStoreDir(dir);
    try testing.expectEqual(LoadKind.loaded, loadCatalog(&loaded, allocator, io));
    try testing.expectEqualStrings("00000000-0000-0000-0000-000000000003", loaded.session_store[0].runtimeId());
}

test "session model and access_mode persist; new sessions inherit last-used" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try testStoreDir(&tmp, &dir_buf);
    const io = testing.io;
    const allocator = testing.allocator;

    var source = Model{};
    source.task_state_loaded = true;
    source.setStoreDir(dir);
    source.store_io = io;
    const id = source.addSession("model session", .fx);
    if (source.sessionById(id)) |session| {
        session.setModel("openai/gpt-5.4");
        session.setAccessMode("ask");
        session.setInteractionMode("plan");
        session.setReasoningEffort("high");
    }
    source.setLastModel("openai/gpt-5.4");
    source.setLastAccessMode("ask");
    source.setLastInteractionMode("plan");
    source.setLastReasoningEffort("high");
    _ = source.appendTurn(id, .user, "use this model");
    try saveSession(&source, id, allocator, io);

    var loaded = Model{};
    loaded.setStoreDir(dir);
    try testing.expectEqual(LoadKind.loaded, loadCatalog(&loaded, allocator, io));
    try testing.expectEqualStrings("openai/gpt-5.4", loaded.session_store[0].model());
    try testing.expectEqualStrings("ask", loaded.session_store[0].accessMode());
    try testing.expectEqualStrings("plan", loaded.session_store[0].interactionMode());
    try testing.expectEqualStrings("high", loaded.session_store[0].reasoningEffort());
    try testing.expectEqualStrings("openai/gpt-5.4", loaded.lastModel());
    try testing.expectEqualStrings("ask", loaded.lastAccessMode());
    try testing.expectEqualStrings("plan", loaded.lastInteractionMode());
    try testing.expectEqualStrings("high", loaded.lastReasoningEffort());

    const inherited = loaded.addSession("next", .fx);
    try testing.expectEqualStrings("openai/gpt-5.4", loaded.sessionById(inherited).?.model());
    try testing.expectEqualStrings("ask", loaded.sessionById(inherited).?.accessMode());
    try testing.expectEqualStrings("plan", loaded.sessionById(inherited).?.interactionMode());
    try testing.expectEqualStrings("high", loaded.sessionById(inherited).?.reasoningEffort());
}

test "sidebar collapsed flag and last width reload from document extras" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try testStoreDir(&tmp, &dir_buf);
    const io = testing.io;
    const allocator = testing.allocator;

    var source = Model{};
    source.task_state_loaded = true;
    source.setStoreDir(dir);
    source.store_io = io;
    const id = source.addSession("layout later", .fx);
    _ = source.appendTurn(id, .user, "remember the rail");
    source.sidebar_last_width = 300;
    source.sidebar_split = 300 / main.window_width;
    try saveSession(&source, id, allocator, io);

    source.toggleSidebar();
    persistLayoutIfPossible(&source);
    try testing.expect(source.sidebar_collapsed);
    try testing.expectEqual(@as(u32, 300), source.sidebarWidthPixels());

    var loaded = Model{};
    loaded.setStoreDir(dir);
    loaded.store_io = io;
    try testing.expectEqual(LoadKind.loaded, loadCatalog(&loaded, allocator, io));
    try testing.expect(loaded.sidebar_collapsed);
    try testing.expectEqual(@as(u32, 300), loaded.sidebarWidthPixels());
    try testing.expectEqual(main.sidebar_rail_width / main.window_width, loaded.sidebar_split);

    loaded.toggleSidebar();
    persistLayoutIfPossible(&loaded);
    try testing.expect(!loaded.sidebar_collapsed);

    var restored = Model{};
    restored.setStoreDir(dir);
    try testing.expectEqual(LoadKind.loaded, loadCatalog(&restored, allocator, io));
    try testing.expect(!restored.sidebar_collapsed);
    try testing.expectEqual(@as(u32, 300), restored.sidebarWidthPixels());
}

test "right panel open flag and width reload from document extras" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try testStoreDir(&tmp, &dir_buf);
    const io = testing.io;
    const allocator = testing.allocator;

    var source = Model{};
    source.task_state_loaded = true;
    source.setStoreDir(dir);
    source.store_io = io;
    const id = source.addSession("files pane later", .fx);
    _ = source.appendTurn(id, .user, "remember the files pane");
    try saveSession(&source, id, allocator, io);

    try testing.expect(!source.right_panel_open);
    source.right_panel_open = true;
    source.right_panel_width = 220;
    source.syncRightPanelSplit();
    persistLayoutIfPossible(&source);
    try testing.expect(source.right_panel_open);
    try testing.expectEqual(@as(u32, 220), source.rightPanelWidthPixels());

    var loaded = Model{};
    loaded.setStoreDir(dir);
    loaded.store_io = io;
    try testing.expectEqual(LoadKind.loaded, loadCatalog(&loaded, allocator, io));
    try testing.expect(loaded.right_panel_open);
    try testing.expectEqual(@as(u32, 220), loaded.rightPanelWidthPixels());
    try testing.expect(loaded.right_panel_split < 1.0);

    loaded.hideRightPanel();
    persistLayoutIfPossible(&loaded);
    try testing.expect(!loaded.right_panel_open);

    var restored = Model{};
    restored.setStoreDir(dir);
    try testing.expectEqual(LoadKind.loaded, loadCatalog(&restored, allocator, io));
    try testing.expect(!restored.right_panel_open);
    try testing.expectEqual(@as(u32, 220), restored.rightPanelWidthPixels());
    try testing.expectEqual(@as(f32, 1.0), restored.right_panel_split);
}

test "Background tab, selected row, and output are not written to sessions.json" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try testStoreDir(&tmp, &dir_buf);
    const io = testing.io;
    const allocator = testing.allocator;

    var source = Model{};
    source.task_state_loaded = true;
    source.setStoreDir(dir);
    source.store_io = io;
    const id = source.addSession("background pane later", .fx);
    _ = source.appendTurn(id, .user, "remember the files pane");
    source.selected = id;
    source.phase = .streaming;
    source.streaming_session = id;
    try saveSession(&source, id, allocator, io);

    var fx = main.Effects.init(allocator);
    defer fx.deinit();
    fx.executor = .fake;
    source.environment_summary_open = true;
    const environment_summary = @import("environment_summary.zig");
    environment_summary.openBackgroundWork(&source, &fx, environment_summary.process_row_id);
    persistLayoutIfPossible(&source);
    try testing.expect(source.right_panel_open);
    try testing.expect(source.right_panel_tab_background());
    try testing.expectEqual(environment_summary.process_row_id, source.right_panel_background_row_id);

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = catalogPath(dir, &path_buf).?;
    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(max_document_bytes));
    defer allocator.free(bytes);
    try testing.expect(std.mem.indexOf(u8, bytes, "\"right_panel_open\":true") != null);
    try testing.expect(std.mem.indexOf(u8, bytes, "\"right_panel_width\":460") != null);
    try testing.expect(std.mem.indexOf(u8, bytes, "right_panel_tab") == null);
    try testing.expect(std.mem.indexOf(u8, bytes, "right_panel_background") == null);
    try testing.expect(std.mem.indexOf(u8, bytes, "background_work") == null);
    try testing.expect(std.mem.indexOf(u8, bytes, "Agent turn") == null);
    try testing.expect(std.mem.indexOf(u8, bytes, "Running") == null);

    var loaded = Model{};
    loaded.setStoreDir(dir);
    loaded.store_io = io;
    try testing.expectEqual(LoadKind.loaded, loadCatalog(&loaded, allocator, io));
    try testing.expect(loaded.right_panel_open);
    try testing.expect(loaded.right_panel_tab_files());
    try testing.expectEqual(@as(u32, 0), loaded.right_panel_background_row_id);
    try testing.expect(loaded.background_work_empty());
}

test "settings extras persist last_model access path and daemon; missing catalog is not created" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try testStoreDir(&tmp, &dir_buf);
    const io = testing.io;
    const allocator = testing.allocator;

    var missing = Model{};
    missing.task_state_loaded = true;
    missing.setStoreDir(dir);
    missing.store_io = io;
    missing.setLastModel("openai/gpt-5.4");
    persistSettingsIfPossible(&missing);
    var missing_path: [std.fs.max_path_bytes]u8 = undefined;
    try testing.expectError(error.FileNotFound, std.Io.Dir.cwd().readFileAlloc(io, catalogPath(dir, &missing_path).?, allocator, .limited(64)));

    var source = Model{};
    source.task_state_loaded = true;
    source.setStoreDir(dir);
    source.store_io = io;
    const id = source.addSession("settings later", .fx);
    _ = source.appendTurn(id, .user, "remember defaults");
    try saveSession(&source, id, allocator, io);

    source.setLastModel("openai/gpt-5.4");
    source.setLastAccessMode("auto");
    source.setLastInteractionMode("plan");
    source.setLastReasoningEffort("high");
    source.setLastProjectPath("/tmp/faku-settings");
    source.setLastDaemonAddress("127.0.0.1:8787");
    source.theme_preference = .light;
    source.language_preference = .japanese;
    persistSettingsIfPossible(&source);

    var loaded = Model{};
    loaded.setStoreDir(dir);
    loaded.store_io = io;
    try testing.expectEqual(LoadKind.loaded, loadCatalog(&loaded, allocator, io));
    try testing.expectEqualStrings("openai/gpt-5.4", loaded.lastModel());
    try testing.expectEqualStrings("auto", loaded.lastAccessMode());
    try testing.expectEqualStrings("plan", loaded.lastInteractionMode());
    try testing.expectEqualStrings("high", loaded.lastReasoningEffort());
    try testing.expectEqualStrings("/tmp/faku-settings", loaded.lastProjectPath());
    try testing.expectEqualStrings("127.0.0.1:8787", loaded.lastDaemonAddress());
    try testing.expectEqual(main.ThemePreference.light, loaded.theme_preference);
    try testing.expectEqual(main.LanguagePreference.japanese, loaded.language_preference);
    try testing.expectEqual(@as(usize, 0), loaded.daemonAddress().len);

    const inherited = loaded.addSession("next", .fx);
    try testing.expectEqualStrings("openai/gpt-5.4", loaded.sessionById(inherited).?.model());
    try testing.expectEqualStrings("auto", loaded.sessionById(inherited).?.accessMode());
    try testing.expectEqualStrings("plan", loaded.sessionById(inherited).?.interactionMode());
    try testing.expectEqualStrings("high", loaded.sessionById(inherited).?.reasoningEffort());
    try testing.expectEqualStrings("/tmp/faku-settings", loaded.sessionById(inherited).?.projectPath());

    loaded.setLastDaemonAddress("");
    persistSettingsIfPossible(&loaded);
    var cleared = Model{};
    cleared.setStoreDir(dir);
    try testing.expectEqual(LoadKind.loaded, loadCatalog(&cleared, allocator, io));
    try testing.expectEqual(@as(usize, 0), cleared.lastDaemonAddress().len);
    try testing.expectEqualStrings("openai/gpt-5.4", cleared.lastModel());
    try testing.expectEqualStrings("plan", cleared.lastInteractionMode());
    try testing.expectEqualStrings("high", cleared.lastReasoningEffort());
    try testing.expectEqual(main.ThemePreference.light, cleared.theme_preference);
    try testing.expectEqual(main.LanguagePreference.japanese, cleared.language_preference);
}

test "theme_preference missing or unknown loads as System" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try testStoreDir(&tmp, &dir_buf);
    const io = testing.io;
    const allocator = testing.allocator;

    try writeRaw(io, dir,
        \\{"version":1,"selected":1,"next_id":2,"next_turn_id":2,"next_queued_id":1,"sessions":[{"id":1,"title":"legacy","provider":"fx","untitled":false,"has_started":true,"turns":[{"id":1,"role":"user","body":"hi"}],"queued_messages":[]}]}
    );
    var missing = Model{};
    missing.setStoreDir(dir);
    try testing.expectEqual(LoadKind.loaded, loadCatalog(&missing, allocator, io));
    try testing.expectEqual(main.ThemePreference.system, missing.theme_preference);

    try writeRaw(io, dir,
        \\{"version":1,"selected":1,"next_id":2,"next_turn_id":2,"next_queued_id":1,"theme_preference":"nope","sessions":[{"id":1,"title":"legacy","provider":"fx","untitled":false,"has_started":true,"turns":[{"id":1,"role":"user","body":"hi"}],"queued_messages":[]}]}
    );
    var unknown = Model{};
    unknown.setStoreDir(dir);
    try testing.expectEqual(LoadKind.loaded, loadCatalog(&unknown, allocator, io));
    try testing.expectEqual(main.ThemePreference.system, unknown.theme_preference);

    try writeRaw(io, dir,
        \\{"version":1,"selected":1,"next_id":2,"next_turn_id":2,"next_queued_id":1,"theme_preference":"dark","sessions":[{"id":1,"title":"legacy","provider":"fx","untitled":false,"has_started":true,"turns":[{"id":1,"role":"user","body":"hi"}],"queued_messages":[]}]}
    );
    var dark = Model{};
    dark.setStoreDir(dir);
    try testing.expectEqual(LoadKind.loaded, loadCatalog(&dark, allocator, io));
    try testing.expectEqual(main.ThemePreference.dark, dark.theme_preference);
}

test "language_preference missing or unknown loads as System; extras roundtrip" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try testStoreDir(&tmp, &dir_buf);
    const io = testing.io;
    const allocator = testing.allocator;

    try writeRaw(io, dir,
        \\{"version":1,"selected":1,"next_id":2,"next_turn_id":2,"next_queued_id":1,"sessions":[{"id":1,"title":"legacy","provider":"fx","untitled":false,"has_started":true,"turns":[{"id":1,"role":"user","body":"hi"}],"queued_messages":[]}]}
    );
    var missing = Model{};
    missing.setStoreDir(dir);
    try testing.expectEqual(LoadKind.loaded, loadCatalog(&missing, allocator, io));
    try testing.expectEqual(main.LanguagePreference.system, missing.language_preference);

    try writeRaw(io, dir,
        \\{"version":1,"selected":1,"next_id":2,"next_turn_id":2,"next_queued_id":1,"language_preference":"nope","sessions":[{"id":1,"title":"legacy","provider":"fx","untitled":false,"has_started":true,"turns":[{"id":1,"role":"user","body":"hi"}],"queued_messages":[]}]}
    );
    var unknown = Model{};
    unknown.setStoreDir(dir);
    try testing.expectEqual(LoadKind.loaded, loadCatalog(&unknown, allocator, io));
    try testing.expectEqual(main.LanguagePreference.system, unknown.language_preference);

    var source = Model{};
    source.task_state_loaded = true;
    source.setStoreDir(dir);
    source.store_io = io;
    const id = source.addSession("language later", .fx);
    _ = source.appendTurn(id, .user, "remember language");
    try saveSession(&source, id, allocator, io);

    source.language_preference = .english;
    persistSettingsIfPossible(&source);
    var english = Model{};
    english.setStoreDir(dir);
    try testing.expectEqual(LoadKind.loaded, loadCatalog(&english, allocator, io));
    try testing.expectEqual(main.LanguagePreference.english, english.language_preference);

    source.language_preference = .simplified_chinese;
    persistSettingsIfPossible(&source);
    var zh = Model{};
    zh.setStoreDir(dir);
    try testing.expectEqual(LoadKind.loaded, loadCatalog(&zh, allocator, io));
    try testing.expectEqual(main.LanguagePreference.simplified_chinese, zh.language_preference);

    source.language_preference = .japanese;
    persistSettingsIfPossible(&source);
    var ja = Model{};
    ja.setStoreDir(dir);
    try testing.expectEqual(LoadKind.loaded, loadCatalog(&ja, allocator, io));
    try testing.expectEqual(main.LanguagePreference.japanese, ja.language_preference);
}

test "folder extras persist untitled folders; missing catalog is not created" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try testStoreDir(&tmp, &dir_buf);
    const io = testing.io;
    const allocator = testing.allocator;

    var missing = Model{};
    missing.task_state_loaded = true;
    missing.setStoreDir(dir);
    missing.store_io = io;
    _ = missing.addFolder("New folder");
    persistFoldersIfPossible(&missing);
    var missing_path: [std.fs.max_path_bytes]u8 = undefined;
    try testing.expectError(error.FileNotFound, std.Io.Dir.cwd().readFileAlloc(io, catalogPath(dir, &missing_path).?, allocator, .limited(64)));

    var source = Model{};
    source.task_state_loaded = true;
    source.setStoreDir(dir);
    source.store_io = io;
    const id = source.addSession("folder later", .fx);
    _ = source.appendTurn(id, .user, "remember folders");
    try saveSession(&source, id, allocator, io);

    const folder_id = source.addFolder("New folder");
    try testing.expect(source.assignSessionFolder(id, folder_id));
    persistFoldersIfPossible(&source);
    try saveSession(&source, id, allocator, io);

    var loaded = Model{};
    loaded.setStoreDir(dir);
    loaded.store_io = io;
    try testing.expectEqual(LoadKind.loaded, loadCatalog(&loaded, allocator, io));
    try testing.expectEqual(@as(u32, 1), loaded.folder_count);
    try testing.expectEqual(folder_id, loaded.folder_store[0].id);
    try testing.expectEqualStrings("New folder", loaded.folder_store[0].title());
    try testing.expectEqual(folder_id, loaded.session_store[0].folder_id);

    loaded.toggleFolderCollapsed(folder_id);
    persistFoldersIfPossible(&loaded);
    var collapsed = Model{};
    collapsed.setStoreDir(dir);
    try testing.expectEqual(LoadKind.loaded, loadCatalog(&collapsed, allocator, io));
    try testing.expect(collapsed.folder_store[0].collapsed);
    try testing.expectEqual(folder_id, collapsed.session_store[0].folder_id);
}

test "deleting a folder unassigns its sessions and drops the folder" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try testStoreDir(&tmp, &dir_buf);
    const io = testing.io;
    const allocator = testing.allocator;

    var source = Model{};
    source.task_state_loaded = true;
    source.setStoreDir(dir);
    source.store_io = io;
    const id = source.addSession("stay after folder delete", .fx);
    _ = source.appendTurn(id, .user, "keep the session");
    try saveSession(&source, id, allocator, io);

    const folder_id = source.addFolder("New folder");
    try testing.expect(source.assignSessionFolder(id, folder_id));
    persistFoldersIfPossible(&source);
    try saveSession(&source, id, allocator, io);

    try testing.expect(source.deleteFolder(folder_id));
    try testing.expectEqual(@as(u32, 0), source.folder_count);
    try testing.expectEqual(@as(u32, 0), source.session_store[0].folder_id);
    try testing.expectEqual(@as(u32, 1), source.session_count);
    persistFoldersIfPossible(&source);
    try saveSession(&source, id, allocator, io);

    var loaded = Model{};
    loaded.setStoreDir(dir);
    loaded.store_io = io;
    try testing.expectEqual(LoadKind.loaded, loadCatalog(&loaded, allocator, io));
    try testing.expectEqual(@as(u32, 0), loaded.folder_count);
    try testing.expectEqual(@as(u32, 1), loaded.session_count);
    try testing.expectEqualStrings("stay after folder delete", loaded.session_store[0].title());
    try testing.expectEqual(@as(u32, 0), loaded.session_store[0].folder_id);
}

test "last_daemon_address persists and loads without becoming the live switch" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try testStoreDir(&tmp, &dir_buf);
    const io = testing.io;
    const allocator = testing.allocator;

    var source = Model{};
    source.task_state_loaded = true;
    source.setStoreDir(dir);
    source.setDaemonAddress("127.0.0.1:8787");
    const id = source.addSession("daemon later", .fx);
    _ = source.appendTurn(id, .user, "remember the addr");
    try saveSession(&source, id, allocator, io);

    var loaded = Model{};
    loaded.setStoreDir(dir);
    try testing.expectEqual(LoadKind.loaded, loadCatalog(&loaded, allocator, io));
    try testing.expectEqualStrings("127.0.0.1:8787", loaded.lastDaemonAddress());
    try testing.expectEqual(@as(usize, 0), loaded.daemonAddress().len);
}

test "session rewind_refs persist on the row and hydrate with the session" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try testStoreDir(&tmp, &dir_buf);
    const io = testing.io;
    const allocator = testing.allocator;

    var source = Model{};
    source.task_state_loaded = true;
    source.setStoreDir(dir);
    source.store_io = io;
    const id = source.addSession("rewind later", .fx);
    if (source.sessionById(id)) |session| {
        session.appendRewindRef("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", rewind.recorded_ref, 1_700_000_000);
        session.appendRewindRef("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", rewind.recorded_ref, 1_700_000_001);
    }
    _ = source.appendTurn(id, .user, "remember this head");
    try saveSession(&source, id, allocator, io);

    var loaded = Model{};
    loaded.setStoreDir(dir);
    try testing.expectEqual(LoadKind.loaded, loadCatalog(&loaded, allocator, io));
    try testing.expectEqual(@as(usize, 2), loaded.session_store[0].rewind_ref_count);
    try testing.expectEqualStrings("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", loaded.session_store[0].rewindRefs()[0].sha());
    try testing.expectEqualStrings(rewind.recorded_ref, loaded.session_store[0].rewindRefs()[0].refName());
    try testing.expectEqual(@as(i64, 1_700_000_000), loaded.session_store[0].rewindRefs()[0].recorded_at);
    try testing.expectEqualStrings("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", loaded.session_store[0].rewindRefs()[1].sha());

    hydrateSession(&loaded, id, allocator, io);
    try testing.expectEqual(@as(usize, 2), loaded.session_store[0].rewind_ref_count);
    try testing.expectEqualStrings("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", loaded.session_store[0].rewindRefs()[1].sha());
}

test "session worktree_snapshot_sha persists on the row and hydrates with the session" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try testStoreDir(&tmp, &dir_buf);
    const io = testing.io;
    const allocator = testing.allocator;

    const snap = "cccccccccccccccccccccccccccccccccccccccc";
    var source = Model{};
    source.task_state_loaded = true;
    source.setStoreDir(dir);
    source.store_io = io;
    const id = source.addSession("snapshot later", .fx);
    if (source.sessionById(id)) |session| {
        session.setWorktreeSnapshotSha(snap);
        session.setWorktreeSnapshotSha("not-a-sha");
        try testing.expectEqualStrings(snap, session.worktreeSnapshotSha());
    }
    _ = source.appendTurn(id, .user, "remember this tree");
    try saveSession(&source, id, allocator, io);

    var loaded = Model{};
    loaded.setStoreDir(dir);
    try testing.expectEqual(LoadKind.loaded, loadCatalog(&loaded, allocator, io));
    try testing.expectEqualStrings(snap, loaded.session_store[0].worktreeSnapshotSha());

    if (loaded.sessionById(id)) |session| session.clearWorktreeSnapshotSha();
    hydrateSession(&loaded, id, allocator, io);
    try testing.expectEqualStrings(snap, loaded.session_store[0].worktreeSnapshotSha());
}

test "session worktree_turn_end_sha persists on the row and hydrates with the session" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try testStoreDir(&tmp, &dir_buf);
    const io = testing.io;
    const allocator = testing.allocator;

    const start = "cccccccccccccccccccccccccccccccccccccccc";
    const end = "dddddddddddddddddddddddddddddddddddddddd";
    var source = Model{};
    source.task_state_loaded = true;
    source.setStoreDir(dir);
    source.store_io = io;
    const id = source.addSession("end snapshot later", .fx);
    if (source.sessionById(id)) |session| {
        session.setWorktreeSnapshotSha(start);
        session.setWorktreeTurnEndSha(end);
        session.setWorktreeTurnEndSha("not-a-sha");
        try testing.expectEqualStrings(start, session.worktreeSnapshotSha());
        try testing.expectEqualStrings(end, session.worktreeTurnEndSha());
    }
    _ = source.appendTurn(id, .user, "remember this end tree");
    try saveSession(&source, id, allocator, io);

    var loaded = Model{};
    loaded.setStoreDir(dir);
    try testing.expectEqual(LoadKind.loaded, loadCatalog(&loaded, allocator, io));
    try testing.expectEqualStrings(start, loaded.session_store[0].worktreeSnapshotSha());
    try testing.expectEqualStrings(end, loaded.session_store[0].worktreeTurnEndSha());

    if (loaded.sessionById(id)) |session| {
        session.clearWorktreeSnapshotSha();
        session.clearWorktreeTurnEndSha();
    }
    hydrateSession(&loaded, id, allocator, io);
    try testing.expectEqualStrings(start, loaded.session_store[0].worktreeSnapshotSha());
    try testing.expectEqualStrings(end, loaded.session_store[0].worktreeTurnEndSha());
}

test "session worktree_turn_diff_sha persists on the row and hydrates with the session" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try testStoreDir(&tmp, &dir_buf);
    const io = testing.io;
    const allocator = testing.allocator;

    const start = "cccccccccccccccccccccccccccccccccccccccc";
    const end = "dddddddddddddddddddddddddddddddddddddddd";
    const diff = "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee";
    var source = Model{};
    source.task_state_loaded = true;
    source.setStoreDir(dir);
    source.store_io = io;
    const id = source.addSession("diff snapshot later", .fx);
    if (source.sessionById(id)) |session| {
        session.setWorktreeSnapshotSha(start);
        session.setWorktreeTurnEndSha(end);
        session.setWorktreeTurnDiffSha(diff);
        session.setWorktreeTurnDiffSha("not-a-sha");
        try testing.expectEqualStrings(start, session.worktreeSnapshotSha());
        try testing.expectEqualStrings(end, session.worktreeTurnEndSha());
        try testing.expectEqualStrings(diff, session.worktreeTurnDiffSha());
    }
    _ = source.appendTurn(id, .user, "remember this diff base");
    try saveSession(&source, id, allocator, io);

    var loaded = Model{};
    loaded.setStoreDir(dir);
    try testing.expectEqual(LoadKind.loaded, loadCatalog(&loaded, allocator, io));
    try testing.expectEqualStrings(start, loaded.session_store[0].worktreeSnapshotSha());
    try testing.expectEqualStrings(end, loaded.session_store[0].worktreeTurnEndSha());
    try testing.expectEqualStrings(diff, loaded.session_store[0].worktreeTurnDiffSha());

    if (loaded.sessionById(id)) |session| {
        session.clearWorktreeSnapshotSha();
        session.clearWorktreeTurnEndSha();
        session.clearWorktreeTurnDiffSha();
    }
    hydrateSession(&loaded, id, allocator, io);
    try testing.expectEqualStrings(start, loaded.session_store[0].worktreeSnapshotSha());
    try testing.expectEqualStrings(end, loaded.session_store[0].worktreeTurnEndSha());
    try testing.expectEqualStrings(diff, loaded.session_store[0].worktreeTurnDiffSha());
}

test "draft keys are newSession until started, then session id" {
    var session = main.Session{ .id = 7, .untitled = true };
    var key_buf: [max_draft_key]u8 = undefined;
    try std.testing.expectEqualStrings("newSession", draftKey(&session, &key_buf).?);
    session.setProjectPath("/tmp/proj");
    try std.testing.expectEqualStrings("newSession/tmp/proj", draftKey(&session, &key_buf).?);
    session.untitled = false;
    session.has_started = true;
    try std.testing.expectEqualStrings("session7", draftKey(&session, &key_buf).?);
}

test "composer draft persists for a started session key" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try testStoreDir(&tmp, &dir_buf);
    const io = testing.io;
    const allocator = testing.allocator;

    var source = Model{};
    source.task_state_loaded = true;
    source.setStoreDir(dir);
    source.store_io = io;
    const id = source.addSession("draft session", .fx);
    _ = source.appendTurn(id, .user, "already started");
    source.selected = id;
    try saveSession(&source, id, allocator, io);
    source.draft_buffer.set("unsent follow-up");
    persistDraftIfPossible(&source);

    var loaded = Model{};
    loaded.setStoreDir(dir);
    loaded.store_io = io;
    try testing.expectEqual(LoadKind.loaded, loadCatalog(&loaded, allocator, io));
    try testing.expectEqual(id, loaded.selected);
    try testing.expectEqualStrings("unsent follow-up", loaded.draft());
}

test "draft image_path persists with the draft key" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try testStoreDir(&tmp, &dir_buf);
    var image_buf: [256]u8 = undefined;
    const image = try std.fmt.bufPrint(&image_buf, ".zig-cache/tmp/{s}/shot.png", .{tmp.sub_path[0..]});
    const io = testing.io;
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = image, .data = "png" });
    const allocator = testing.allocator;

    var source = Model{};
    source.task_state_loaded = true;
    source.setStoreDir(dir);
    source.store_io = io;
    const id = source.addSession("image draft", .fx);
    _ = source.appendTurn(id, .user, "already started");
    source.selected = id;
    try saveSession(&source, id, allocator, io);
    source.draft_buffer.set("look at this");
    source.setDraftImagePath(image);
    persistDraftIfPossible(&source);

    var loaded = Model{};
    loaded.setStoreDir(dir);
    loaded.store_io = io;
    try testing.expectEqual(LoadKind.loaded, loadCatalog(&loaded, allocator, io));
    try testing.expectEqualStrings("look at this", loaded.draft());
    try testing.expectEqualStrings(image, loaded.draftImagePath());
}

test "queued_messages survive save and hydrate" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try testStoreDir(&tmp, &dir_buf);
    const io = testing.io;
    const allocator = testing.allocator;

    var source = Model{};
    source.task_state_loaded = true;
    source.setStoreDir(dir);
    const ids = seedTwoSessions(&source);
    const q1 = source.enqueue(ids.a, "then port the composer");
    const q2 = source.enqueue(ids.a, "and the status bar");
    try testing.expect(q1 != 0);
    try testing.expect(q2 != 0);
    try saveSession(&source, ids.a, allocator, io);
    try saveSession(&source, ids.b, allocator, io);

    var loaded = Model{};
    loaded.setStoreDir(dir);
    try testing.expectEqual(LoadKind.loaded, loadCatalog(&loaded, allocator, io));
    try testing.expectEqual(@as(u32, 0), loaded.queued_count);

    hydrateSession(&loaded, ids.a, allocator, io);
    try testing.expectEqual(@as(u32, 2), loaded.queuedCount(ids.a));
    try testing.expectEqual(q1, loaded.queued_store[0].id);
    try testing.expectEqualStrings("then port the composer", loaded.firstQueuedText(ids.a));
    try testing.expectEqualStrings("and the status bar", loaded.queued_store[1].text());
    try testing.expectEqual(@as(u32, 0), loaded.queuedCount(ids.b));

    hydrateSession(&loaded, ids.b, allocator, io);
    try testing.expectEqual(@as(u32, 0), loaded.queuedCount(ids.b));
}

test "missing store keeps demos; corrupt store is not overwritten" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try testStoreDir(&tmp, &dir_buf);
    const io = testing.io;
    const allocator = testing.allocator;

    var missing = main.initialModel();
    missing.setStoreDir(dir);
    missing.store_io = io;
    try testing.expectEqual(LoadKind.missing, boot(&missing, allocator, io));
    try testing.expectEqual(@as(u32, 2), missing.session_count);
    try testing.expectEqualStrings("port waku to zig", missing.selected_title());
    try testing.expect(missing.task_state_loaded);

    try writeRaw(io, dir, "{not json");
    var corrupt = main.initialModel();
    corrupt.setStoreDir(dir);
    corrupt.store_io = io;
    try testing.expectEqual(LoadKind.failed, boot(&corrupt, allocator, io));
    try testing.expectEqual(@as(u32, 2), corrupt.session_count);
    try testing.expect(!corrupt.task_state_loaded);
    try testing.expectError(error.TaskStateNotLoaded, saveSession(&corrupt, corrupt.selected, allocator, io));

    corrupt.setDaemonAddress("127.0.0.1:8787");
    try testing.expect(!corrupt.pending_daemon_catalog);
    try testing.expect(!corrupt.task_state_loaded);

    var path_buf: [256]u8 = undefined;
    const leftover = try std.Io.Dir.cwd().readFileAlloc(io, catalogPath(dir, &path_buf).?, allocator, .limited(64));
    defer allocator.free(leftover);
    try testing.expectEqualStrings("{not json", leftover);
}

test "new session is skipped until first content; save is merge-only" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try testStoreDir(&tmp, &dir_buf);
    const io = testing.io;
    const allocator = testing.allocator;

    var model = Model{};
    model.task_state_loaded = true;
    model.setStoreDir(dir);
    const first = model.addSession("kept", .fx);
    _ = model.appendTurn(first, .user, "hello");
    try saveSession(&model, first, allocator, io);

    const untitled = model.addSession("untitled", .fx);
    if (model.sessionById(untitled)) |session| session.untitled = true;
    try saveSession(&model, untitled, allocator, io);

    var loaded = Model{};
    loaded.setStoreDir(dir);
    try testing.expectEqual(LoadKind.loaded, loadCatalog(&loaded, allocator, io));
    try testing.expectEqual(@as(u32, 1), loaded.session_count);
    try testing.expectEqual(first, loaded.session_store[0].id);

    if (model.sessionById(untitled)) |session| {
        writeTitle(session, "after first send");
        session.untitled = false;
    }
    _ = model.appendTurn(untitled, .user, "real content");
    try saveSession(&model, untitled, allocator, io);

    var merged = Model{};
    merged.setStoreDir(dir);
    try testing.expectEqual(LoadKind.loaded, loadCatalog(&merged, allocator, io));
    try testing.expectEqual(@as(u32, 2), merged.session_count);
    try testing.expectEqual(first, merged.session_store[0].id);
    try testing.expectEqual(untitled, merged.session_store[1].id);
}

fn writeTitle(session: *main.Session, title: []const u8) void {
    const take = @min(session.title_storage.len, title.len);
    @memcpy(session.title_storage[0..take], title[0..take]);
    session.title_len = take;
}

test "updated_at persists; missing field loads as 0" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try testStoreDir(&tmp, &dir_buf);
    const io = testing.io;
    const allocator = testing.allocator;

    var source = Model{};
    source.task_state_loaded = true;
    source.setStoreDir(dir);
    source.store_io = io;
    source.now_ms = 1_704_067_200_000;
    const id = source.addSession("stamp me", .fx);
    try testing.expectEqual(@as(i64, 1_704_067_200_000), source.sessionById(id).?.updated_at);
    _ = source.appendTurn(id, .user, "hello");
    source.sessionById(id).?.updated_at = 1_703_980_800_000;
    try saveSession(&source, id, allocator, io);

    var loaded = Model{};
    loaded.setStoreDir(dir);
    try testing.expectEqual(LoadKind.loaded, loadCatalog(&loaded, allocator, io));
    try testing.expectEqual(@as(i64, 1_703_980_800_000), loaded.session_store[0].updated_at);

    try writeRaw(io, dir,
        \\{"version":1,"selected":1,"next_id":2,"next_turn_id":2,"next_queued_id":1,"sessions":[{"id":1,"title":"legacy","provider":"fx","untitled":false,"has_started":true,"turns":[{"id":1,"role":"user","body":"hi"}],"queued_messages":[]}]}
    );
    var legacy = Model{};
    legacy.setStoreDir(dir);
    try testing.expectEqual(LoadKind.loaded, loadCatalog(&legacy, allocator, io));
    try testing.expectEqual(@as(u32, 1), legacy.session_count);
    try testing.expectEqual(@as(i64, 0), legacy.session_store[0].updated_at);
    try testing.expectEqual(main.DateBucket.today, main.sessionDateBucket(legacy.session_store[0].updated_at, 1_704_067_200_000));
}
