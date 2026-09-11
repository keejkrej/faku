//! Transcript assistant markdown images (first-cut).
//!
//! Visible assistant turns paint Native `<markdown source="{t.text}"
//! images="{transcript_images}">`. Discovery uses Native
//! `canvas.markdown.collectImageSources` (cap `max_markdown_images`)
//! over the selected-session assistant bodies (same find filter as
//! `visible_turns`). Then `fx.loadImage`s **in-project local** paths
//! (`.path`) and **http(s)** URLs (`.url` only; omit path), and
//! registers a practical `data:image/<subtype>;base64,…` subset via
//! `fx.registerImageBytes` (sync; same registry as `loadImage`).
//! Canonical source bytes stay the markdown `src` so `images=`
//! mappings match the renderer. Outside-project / unresolved /
//! malformed `data:` stay unmapped (alt-text). User / tool /
//! reasoning rows stay `<text>` this cut. Files Preview markdown
//! images (ids 800–815) and composer attach preview (33–63) are
//! untouched.
//!
//! Path rules reuse `file_preview_images.resolveInProjectImagePath`
//! (`open_url.resolveMarkdownFilePath` + in-project gate). Relative
//! sources resolve against the selected session `project_path` (host
//! cwd when that path is empty). Verified: Native markdown `images=`
//! + `fx.loadImage` local `.path` and network `.url`, plus
//! `fx.registerImageBytes` for encoded bytes.

const std = @import("std");
const native_sdk = @import("native_sdk");
const main = @import("main.zig");
const open_url = @import("open_url.zig");
const file_preview_images = @import("file_preview_images.zig");

const canvas = native_sdk.canvas;

const Model = main.Model;
const Effects = main.Effects;

/// Recycled ImageId / effect-key band. Distinct from attach preview
/// 33–63, OS sidecars 25–32, pty 700–703, overlap 64+, git 200+,
/// Files Preview markdown images 800–815.
pub const id_first: u64 = file_preview_images.id_last + 1;
pub const id_last: u64 = id_first + canvas.markdown.max_markdown_images - 1;
pub const max_images: usize = canvas.markdown.max_markdown_images;
pub const max_source_bytes: usize = canvas.markdown.max_markdown_image_source_bytes;
pub const max_data_decoded_bytes: usize = file_preview_images.max_data_decoded_bytes;

pub const Slot = file_preview_images.Slot;

/// Cancel in-flight loads, unregister pixels, and zero slots.
pub fn drop(model: *Model, fx: ?*Effects) void {
    for (&model.transcript_image_slots) |*slot| {
        if (slot.id != 0) {
            if (fx) |effects| {
                effects.cancel(slot.id);
                _ = effects.unregisterImage(slot.id);
            }
        }
        slot.* = .{};
    }
}

pub fn loadedCount(model: *const Model) usize {
    var count: usize = 0;
    for (model.transcript_image_slots) |slot| {
        if (slot.loaded) count += 1;
    }
    return count;
}

pub fn occupiedCount(model: *const Model) usize {
    var count: usize = 0;
    for (model.transcript_image_slots) |slot| {
        if (slot.source_len > 0) count += 1;
    }
    return count;
}

/// Arena binding for `<markdown images="{transcript_images}">`.
pub fn resolved(model: *const Model, arena: std.mem.Allocator) []const canvas.markdown.ResolvedImage {
    const count = loadedCount(model);
    if (count == 0) return &.{};
    const out = arena.alloc(canvas.markdown.ResolvedImage, count) catch return &.{};
    var index: usize = 0;
    for (&model.transcript_image_slots) |*slot| {
        if (!slot.loaded) continue;
        out[index] = .{
            .source = slot.source(),
            .image = slot.id,
            .width = @floatFromInt(slot.width),
            .height = @floatFromInt(slot.height),
        };
        index += 1;
    }
    return out;
}

fn nextId(model: *Model) u64 {
    var id = model.next_transcript_image_id;
    if (id < id_first or id > id_last) id = id_first;
    var attempts: usize = 0;
    while (attempts < max_images) : (attempts += 1) {
        var used = false;
        for (model.transcript_image_slots) |slot| {
            if (slot.id == id) {
                used = true;
                break;
            }
        }
        if (!used) {
            model.next_transcript_image_id = if (id >= id_last) id_first else id + 1;
            return id;
        }
        id = if (id >= id_last) id_first else id + 1;
    }
    model.next_transcript_image_id = id_first;
    return id_first;
}

fn freeSlot(model: *Model) ?*Slot {
    for (&model.transcript_image_slots) |*slot| {
        if (slot.source_len == 0) return slot;
    }
    return null;
}

fn sourceIsWanted(sources: []const []const u8, source: []const u8) bool {
    for (sources) |candidate| {
        if (std.mem.eql(u8, candidate, source)) return true;
    }
    return false;
}

fn projectOrCwd(model: *const Model, cwd_buf: []u8) []const u8 {
    const project = model.selectedProjectPath();
    if (project.len > 0) return project;
    const io = model.store_io orelse return "";
    const n = std.process.currentPath(io, cwd_buf) catch return "";
    if (n == 0) return "";
    return cwd_buf[0..n];
}

fn previewAbsForProject(project: []const u8, dest: []u8) []const u8 {
    if (project.len == 0) return "";
    return std.fmt.bufPrint(dest, "{s}/.", .{project}) catch "";
}

fn findQuery(model: *const Model) []const u8 {
    if (!model.find_active) return "";
    return std.mem.trim(u8, model.find_query(), " \t\r\n");
}

/// Reconcile collected assistant-turn sources with model/effect
/// state. Missing fx drops mappings. Existing successes for still-
/// wanted sources survive without refetching. Cap Native
/// `max_markdown_images` across the visible assistant set.
pub fn refresh(model: *Model, fx: ?*Effects) void {
    const effects = fx orelse {
        drop(model, null);
        return;
    };

    var cwd_buf: [main.max_project_path]u8 = undefined;
    const project = projectOrCwd(model, &cwd_buf);
    var preview_buf: [open_url.max_file_link_path]u8 = undefined;
    const preview_abs = previewAbsForProject(project, &preview_buf);

    var wanted_storage: [max_images][]const u8 = undefined;
    var wanted_copies: [max_images][max_source_bytes]u8 = undefined;
    var wanted_paths: [max_images][open_url.max_file_link_path]u8 = undefined;
    var wanted_path_lens: [max_images]usize = undefined;
    var wanted_len: usize = 0;
    const query = findQuery(model);

    for (model.turn_store[0..model.turn_count]) |*turn| {
        if (wanted_len >= max_images) break;
        if (turn.session_id != model.selected) continue;
        if (turn.role != .assistant) continue;
        if (query.len > 0 and !main.asciiContainsIgnoreCase(turn.text(), query)) continue;

        var source_storage: [max_images]canvas.markdown.CollectedImageSource = undefined;
        const discovered = canvas.markdown.collectImageSources(turn.text(), &source_storage);
        for (discovered) |*collected| {
            if (wanted_len >= max_images) break;
            const source = collected.value();
            if (sourceIsWanted(wanted_storage[0..wanted_len], source)) continue;

            var path_len: usize = 0;
            if (file_preview_images.isRemoteHttpImageSource(source) or file_preview_images.isDataImageSource(source)) {
                // url / data: — no filesystem path
            } else {
                var path_buf: [open_url.max_file_link_path]u8 = undefined;
                const path = file_preview_images.resolveInProjectImagePath(source, preview_abs, project, &path_buf) orelse continue;
                @memcpy(wanted_paths[wanted_len][0..path.len], path);
                path_len = path.len;
            }
            @memcpy(wanted_copies[wanted_len][0..source.len], source);
            wanted_storage[wanted_len] = wanted_copies[wanted_len][0..source.len];
            wanted_path_lens[wanted_len] = path_len;
            wanted_len += 1;
        }
    }
    const wanted = wanted_storage[0..wanted_len];

    for (&model.transcript_image_slots) |*slot| {
        if (slot.source_len == 0 or sourceIsWanted(wanted, slot.source())) continue;
        effects.cancel(slot.id);
        _ = effects.unregisterImage(slot.id);
        slot.* = .{};
    }

    for (wanted, 0..) |source, index| {
        var present = false;
        for (model.transcript_image_slots) |slot| {
            if (slot.source_len > 0 and std.mem.eql(u8, slot.source(), source)) {
                present = true;
                break;
            }
        }
        if (present) continue;
        const slot = freeSlot(model) orelse break;
        @memcpy(slot.source_storage[0..source.len], source);
        slot.source_len = source.len;
        const path_len = wanted_path_lens[index];
        if (path_len > 0) {
            const path = wanted_paths[index][0..path_len];
            @memcpy(slot.path_storage[0..path.len], path);
            slot.path_len = path.len;
            slot.id = nextId(model);
            effects.loadImage(.{
                .id = slot.id,
                .path = slot.path(),
                .on_result = Effects.imageMsg(.transcript_image_done),
            });
            continue;
        }
        if (file_preview_images.isRemoteHttpImageSource(source)) {
            slot.id = nextId(model);
            effects.loadImage(.{
                .id = slot.id,
                .url = slot.source(),
                .on_result = Effects.imageMsg(.transcript_image_done),
            });
            continue;
        }
        var decoded_buf: [max_data_decoded_bytes]u8 = undefined;
        const decoded = file_preview_images.decodeDataImageSource(source, &decoded_buf) orelse {
            slot.* = .{};
            continue;
        };
        slot.id = nextId(model);
        const registered = file_preview_images.registerMarkdownImageBytes(effects, slot.id, decoded) orelse {
            slot.* = .{};
            continue;
        };
        slot.loaded = true;
        slot.width = registered.width;
        slot.height = registered.height;
    }
}

pub fn applyResult(model: *Model, fx: *Effects, result: native_sdk.EffectImageResult) void {
    if (result.id < id_first or result.id > id_last) {
        if (result.outcome == .loaded) _ = fx.unregisterImage(result.id);
        return;
    }
    var retained = false;
    for (&model.transcript_image_slots) |*slot| {
        if (slot.source_len == 0 or slot.id != result.id) continue;
        retained = true;
        if (result.outcome == .loaded and result.width > 0 and result.height > 0) {
            slot.loaded = true;
            slot.width = result.width;
            slot.height = result.height;
        } else if (result.outcome == .loaded) {
            _ = fx.unregisterImage(result.id);
        }
        break;
    }
    if (!retained and result.outcome == .loaded) _ = fx.unregisterImage(result.id);
}

/// Native `<markdown on-link>` from assistant turns: http(s) / bare
/// hosts reuse `open_url` OS browser spawn. Relative / `file:` / other
/// targets stay unhandled this cut (no Files Preview routing).
pub fn openUrl(model: *Model, fx: *Effects, url: []const u8) void {
    if (open_url.isRelativeOrFileUrl(url)) return;
    _ = open_url.startOpenUrlText(model, fx, url);
}

test "id band is 16 slots after Files Preview 800-815 and distinct from attach" {
    const attach = @import("attach.zig");
    const pty_terminal = @import("pty_terminal.zig");
    try std.testing.expectEqual(@as(usize, 16), max_images);
    try std.testing.expectEqual(@as(u64, 816), id_first);
    try std.testing.expectEqual(@as(u64, 831), id_last);
    try std.testing.expectEqual(file_preview_images.id_last + 1, id_first);
    try std.testing.expect(id_first > file_preview_images.id_last);
    try std.testing.expect(id_first > attach.attach_preview_id_last);
    try std.testing.expect(id_first > pty_terminal.pty_shell_key_last);
    try std.testing.expectEqual(max_images, id_last - id_first + 1);
}

fn pendingLoadWithPath(fx: *Effects) !Effects.ImageLoadRequest {
    var index: usize = 0;
    while (index < fx.pendingImageLoadCount()) : (index += 1) {
        const load = fx.pendingImageLoadAt(index) orelse return error.MissingImageLoad;
        if (load.path.len > 0 and load.url.len == 0) return load;
    }
    return error.MissingImageLoad;
}

fn pendingLoadWithUrl(fx: *Effects) !Effects.ImageLoadRequest {
    var index: usize = 0;
    while (index < fx.pendingImageLoadCount()) : (index += 1) {
        const load = fx.pendingImageLoadAt(index) orelse return error.MissingImageLoad;
        if (load.url.len > 0 and load.path.len == 0) return load;
    }
    return error.MissingImageLoad;
}

/// 1×1 PNG (standard 68-byte fixture). Same bytes as Files Preview.
const tiny_png_b64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==";
const tiny_png_data_url = "data:image/png;base64," ++ tiny_png_b64;

test "refresh loads in-project local path, http(s) url, and data:; user tool reasoning stay unmapped" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, "/tmp/faku-tx-images-{s}", .{tmp.sub_path});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("tx images", .fx);
    model.selected = id;
    model.setSelectedProjectPath(project);

    const body = "![local](./shot.png)\n\n![remote](https://example.com/x.png)\n\n![data](" ++ tiny_png_data_url ++ ")\n\n![out](file:///tmp/outside.png)\n";
    _ = model.appendTurn(id, .user, "![user](./user.png)\n");
    _ = model.appendTurn(id, .tool, "![tool](https://example.com/tool.png)\n");
    _ = model.appendTurn(id, .reasoning, "![think](./think.png)\n");
    _ = model.appendTurn(id, .assistant, body);

    refresh(&model, &fx);
    try std.testing.expectEqual(@as(usize, 3), occupiedCount(&model));
    try std.testing.expectEqual(@as(usize, 1), loadedCount(&model));
    try std.testing.expectEqual(@as(usize, 2), fx.pendingImageLoadCount());

    const local_load = try pendingLoadWithPath(&fx);
    try std.testing.expect(std.mem.endsWith(u8, local_load.path, "/shot.png"));
    try std.testing.expect(std.mem.startsWith(u8, local_load.path, project));
    try std.testing.expectEqual(@as(usize, 0), local_load.url.len);
    try std.testing.expect(local_load.id >= id_first);
    try std.testing.expect(local_load.id <= id_last);
    try std.testing.expect(local_load.id > file_preview_images.id_last);
    try std.testing.expectEqualStrings("./shot.png", model.transcript_image_slots[0].source());

    const remote_load = try pendingLoadWithUrl(&fx);
    try std.testing.expectEqualStrings("https://example.com/x.png", remote_load.url);
    try std.testing.expectEqual(@as(usize, 0), remote_load.path.len);
    try std.testing.expect(remote_load.id >= id_first);
    try std.testing.expect(remote_load.id <= id_last);
    try std.testing.expect(remote_load.id != local_load.id);

    var data_id: u64 = 0;
    for (model.transcript_image_slots) |slot| {
        if (slot.source_len > 0 and std.mem.eql(u8, slot.source(), tiny_png_data_url)) {
            try std.testing.expect(slot.loaded);
            try std.testing.expect(slot.id >= id_first);
            try std.testing.expect(slot.id <= id_last);
            data_id = slot.id;
        }
    }
    try std.testing.expect(data_id != 0);
    try std.testing.expect(data_id != local_load.id);
    try std.testing.expect(data_id != remote_load.id);

    try fx.feedImageResult(local_load.id, .loaded, 8, 8, 0, "");
    while (fx.takeMsg()) |msg| main.update(&model, msg, &fx);
    try fx.feedImageResult(remote_load.id, .loaded, 16, 12, 0, "");
    while (fx.takeMsg()) |msg| main.update(&model, msg, &fx);
    try std.testing.expectEqual(@as(usize, 3), loadedCount(&model));

    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const mapped = resolved(&model, arena_state.allocator());
    try std.testing.expectEqual(@as(usize, 3), mapped.len);
    try std.testing.expectEqualStrings("./shot.png", mapped[0].source);
    try std.testing.expectEqual(local_load.id, mapped[0].image);
    try std.testing.expectEqualStrings("https://example.com/x.png", mapped[1].source);
    try std.testing.expectEqual(remote_load.id, mapped[1].image);
    try std.testing.expectEqualStrings(tiny_png_data_url, mapped[2].source);
    try std.testing.expectEqual(data_id, mapped[2].image);

    drop(&model, &fx);
    try std.testing.expectEqual(@as(usize, 0), occupiedCount(&model));
    try std.testing.expectEqual(@as(usize, 0), loadedCount(&model));
}

test "refresh drops on session switch; other session assistant bodies are ignored" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, "/tmp/faku-tx-switch-{s}", .{tmp.sub_path});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = std.testing.io;
    const first = model.addSession("tx first", .fx);
    const second = model.addSession("tx second", .fx);
    model.selected = first;
    model.setSelectedProjectPath(project);
    _ = model.appendTurn(first, .assistant, "![a](https://example.com/a.png)\n");
    _ = model.appendTurn(second, .assistant, "![b](https://example.com/b.png)\n");

    refresh(&model, &fx);
    try std.testing.expectEqual(@as(usize, 1), occupiedCount(&model));
    try std.testing.expectEqualStrings("https://example.com/a.png", model.transcript_image_slots[0].source());
    const first_id = model.transcript_image_slots[0].id;
    try std.testing.expect(first_id >= id_first);
    try std.testing.expect(first_id <= id_last);

    main.update(&model, .{ .select = second }, &fx);
    try std.testing.expectEqual(second, model.selected);
    try std.testing.expectEqual(@as(usize, 1), occupiedCount(&model));
    try std.testing.expectEqualStrings("https://example.com/b.png", model.transcript_image_slots[0].source());
    try std.testing.expect(model.transcript_image_slots[0].id >= id_first);
    try std.testing.expect(model.transcript_image_slots[0].id <= id_last);
    try std.testing.expect(model.transcript_image_slots[0].id != first_id);

    main.update(&model, .new_session, &fx);
    try std.testing.expectEqual(@as(usize, 0), occupiedCount(&model));
    try std.testing.expectEqual(@as(usize, 0), loadedCount(&model));
}

test "applyResult unregisters stray loaded pixels outside the transcript id band" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    applyResult(&model, &fx, .{
        .id = 800,
        .outcome = .loaded,
        .width = 8,
        .height = 8,
        .status = 0,
    });
    applyResult(&model, &fx, .{
        .id = 33,
        .outcome = .loaded,
        .width = 8,
        .height = 8,
        .status = 0,
    });
    try std.testing.expectEqual(@as(usize, 0), occupiedCount(&model));
    try std.testing.expectEqual(@as(usize, 0), loadedCount(&model));
}

test "refresh skips malformed data empty and outside-project" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, "/tmp/faku-tx-skip-{s}", .{tmp.sub_path});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("tx skip", .fx);
    model.selected = id;
    model.setSelectedProjectPath(project);
    _ = model.appendTurn(id, .assistant, "![http](http://example.com/a.png)\n\n![data](data:image/png;base64,aaa)\n\n![]()\n\n![out](file:///tmp/outside.png)\n");

    refresh(&model, &fx);
    try std.testing.expectEqual(@as(usize, 1), occupiedCount(&model));
    try std.testing.expectEqual(@as(usize, 1), fx.pendingImageLoadCount());
    const load = try pendingLoadWithUrl(&fx);
    try std.testing.expectEqualStrings("http://example.com/a.png", load.url);
    try std.testing.expectEqual(@as(usize, 0), load.path.len);
    try std.testing.expectEqualStrings("http://example.com/a.png", model.transcript_image_slots[0].source());
    try std.testing.expect(load.id >= id_first);
    try std.testing.expect(load.id <= id_last);
}
