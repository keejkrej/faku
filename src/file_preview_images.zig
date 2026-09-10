//! Files Preview markdown images (first-cut).
//!
//! Rendered Files `<markdown>` discovers leading image sources with
//! Native `canvas.markdown.collectImageSources` (cap
//! `max_markdown_images`), then `fx.loadImage`s **in-project local**
//! paths (`.path`) and **http(s)** URLs (`.url` only; omit path).
//! Canonical source bytes stay the markdown `src` so `images=`
//! mappings match the renderer. `data:` / outside-project /
//! unresolved stay unmapped (alt-text). Composer attach preview
//! (ids 33–63) is untouched.
//!
//! Path rules reuse `open_url.resolveMarkdownFilePath` (strip location
//! fragment, percent-decode, lexical normalize; relative vs preview abs
//! dir) plus `workspaceRelativeFilePath` for the in-project gate.
//! Verified: Native markdown `images=` + `fx.loadImage` local `.path`
//! and network `.url`.

const std = @import("std");
const native_sdk = @import("native_sdk");
const main = @import("main.zig");
const open_url = @import("open_url.zig");

const canvas = native_sdk.canvas;

const Model = main.Model;
const Effects = main.Effects;

/// Recycled ImageId / effect-key band. Distinct from attach preview
/// 33–63, OS sidecars 25–32, pty 700–703, overlap 64+, git 200+.
pub const id_first: u64 = 800;
pub const id_last: u64 = id_first + canvas.markdown.max_markdown_images - 1;
pub const max_images: usize = canvas.markdown.max_markdown_images;
pub const max_source_bytes: usize = canvas.markdown.max_markdown_image_source_bytes;

pub const Slot = struct {
    source_storage: [max_source_bytes]u8 = undefined,
    source_len: usize = 0,
    path_storage: [open_url.max_file_link_path]u8 = undefined,
    path_len: usize = 0,
    id: canvas.ImageId = 0,
    width: usize = 0,
    height: usize = 0,
    loaded: bool = false,

    pub fn source(slot: *const Slot) []const u8 {
        return slot.source_storage[0..slot.source_len];
    }

    pub fn path(slot: *const Slot) []const u8 {
        return slot.path_storage[0..slot.path_len];
    }
};

/// Local in-project filesystem path for a collected markdown image
/// source, or `null` to leave alt-text (`data:` / non-file /
/// outside-project / unresolved / over-long). http(s) sources use
/// `isRemoteHttpImageSource` + `fx.loadImage` `.url` instead.
pub fn resolveInProjectImagePath(
    source: []const u8,
    preview_abs: []const u8,
    project: []const u8,
    dest: []u8,
) ?[]const u8 {
    if (source.len == 0 or source.len > max_source_bytes) return null;
    if (open_url.isHttpUrl(source)) return null;
    if (std.ascii.startsWithIgnoreCase(source, "data:")) return null;
    var path_buf: [open_url.max_file_link_path]u8 = undefined;
    const abs_path = open_url.resolveMarkdownFilePath(source, preview_abs, &path_buf) orelse return null;
    var rel_buf: [open_url.max_file_link_path]u8 = undefined;
    if (open_url.workspaceRelativeFilePath(project, abs_path, &rel_buf) == null) return null;
    if (abs_path.len > dest.len) return null;
    @memcpy(dest[0..abs_path.len], abs_path);
    return dest[0..abs_path.len];
}

/// http(s) markdown image source eligible for url-only `fx.loadImage`.
/// Empty, over-long, `data:`, and non-http(s) stay alt-text.
pub fn isRemoteHttpImageSource(source: []const u8) bool {
    if (source.len == 0 or source.len > max_source_bytes) return false;
    if (source.len > native_sdk.max_effect_url_bytes) return false;
    return open_url.isHttpUrl(source);
}

fn nextId(model: *Model) u64 {
    var id = model.next_file_preview_image_id;
    if (id < id_first or id > id_last) id = id_first;
    var attempts: usize = 0;
    while (attempts < max_images) : (attempts += 1) {
        var used = false;
        for (model.file_preview_image_slots) |slot| {
            if (slot.id == id) {
                used = true;
                break;
            }
        }
        if (!used) {
            model.next_file_preview_image_id = if (id >= id_last) id_first else id + 1;
            return id;
        }
        id = if (id >= id_last) id_first else id + 1;
    }
    model.next_file_preview_image_id = id_first;
    return id_first;
}

fn freeSlot(model: *Model) ?*Slot {
    for (&model.file_preview_image_slots) |*slot| {
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

/// Cancel in-flight loads, unregister pixels, and zero slots.
pub fn drop(model: *Model, fx: ?*Effects) void {
    for (&model.file_preview_image_slots) |*slot| {
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
    for (model.file_preview_image_slots) |slot| {
        if (slot.loaded) count += 1;
    }
    return count;
}

pub fn occupiedCount(model: *const Model) usize {
    var count: usize = 0;
    for (model.file_preview_image_slots) |slot| {
        if (slot.source_len > 0) count += 1;
    }
    return count;
}

/// Arena binding for `<markdown images="{file_preview_images}">`.
pub fn resolved(model: *const Model, arena: std.mem.Allocator) []const canvas.markdown.ResolvedImage {
    const count = loadedCount(model);
    if (count == 0) return &.{};
    const out = arena.alloc(canvas.markdown.ResolvedImage, count) catch return &.{};
    var index: usize = 0;
    for (&model.file_preview_image_slots) |*slot| {
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

/// Reconcile collected sources with model/effect state. Missing fx or
/// a non-rendered preview drops mappings. Existing successes for still-
/// wanted sources survive without refetching.
pub fn refresh(model: *Model, fx: ?*Effects) void {
    const effects = fx orelse {
        drop(model, null);
        return;
    };
    if (!model.file_preview_shows_rendered_markdown()) {
        drop(model, effects);
        return;
    }

    var source_storage: [max_images]canvas.markdown.CollectedImageSource = undefined;
    const discovered = canvas.markdown.collectImageSources(model.file_preview_body(), &source_storage);

    const preview_abs = model.right_panel_file_preview_abs_storage[0..model.right_panel_file_preview_abs_len];
    const project = model.selectedProjectPath();

    var wanted_storage: [max_images][]const u8 = undefined;
    var wanted_paths: [max_images][open_url.max_file_link_path]u8 = undefined;
    var wanted_path_lens: [max_images]usize = undefined;
    var wanted_len: usize = 0;
    for (discovered) |*collected| {
        const source = collected.value();
        if (isRemoteHttpImageSource(source)) {
            wanted_storage[wanted_len] = source;
            wanted_path_lens[wanted_len] = 0;
            wanted_len += 1;
            continue;
        }
        var path_buf: [open_url.max_file_link_path]u8 = undefined;
        const path = resolveInProjectImagePath(source, preview_abs, project, &path_buf) orelse continue;
        wanted_storage[wanted_len] = source;
        @memcpy(wanted_paths[wanted_len][0..path.len], path);
        wanted_path_lens[wanted_len] = path.len;
        wanted_len += 1;
    }
    const wanted = wanted_storage[0..wanted_len];

    for (&model.file_preview_image_slots) |*slot| {
        if (slot.source_len == 0 or sourceIsWanted(wanted, slot.source())) continue;
        effects.cancel(slot.id);
        _ = effects.unregisterImage(slot.id);
        slot.* = .{};
    }

    for (wanted, 0..) |source, index| {
        var present = false;
        for (model.file_preview_image_slots) |slot| {
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
        }
        slot.id = nextId(model);
        if (slot.path_len > 0) {
            effects.loadImage(.{
                .id = slot.id,
                .path = slot.path(),
                .on_result = Effects.imageMsg(.file_preview_image_done),
            });
        } else {
            effects.loadImage(.{
                .id = slot.id,
                .url = slot.source(),
                .on_result = Effects.imageMsg(.file_preview_image_done),
            });
        }
    }
}

pub fn applyResult(model: *Model, fx: *Effects, result: native_sdk.EffectImageResult) void {
    if (result.id < id_first or result.id > id_last) {
        if (result.outcome == .loaded) _ = fx.unregisterImage(result.id);
        return;
    }
    var retained = false;
    for (&model.file_preview_image_slots) |*slot| {
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

test "id band is 16 slots after pty and distinct from attach preview" {
    const attach = @import("attach.zig");
    const pty_terminal = @import("pty_terminal.zig");
    try std.testing.expectEqual(@as(usize, 16), max_images);
    try std.testing.expectEqual(@as(u64, 800), id_first);
    try std.testing.expectEqual(@as(u64, 815), id_last);
    try std.testing.expect(id_first > attach.attach_preview_id_last);
    try std.testing.expect(id_first > pty_terminal.pty_shell_key_last);
    try std.testing.expectEqual(max_images, id_last - id_first + 1);
}

test "resolveInProjectImagePath accepts in-project local; rejects remote and outside" {
    var dest: [open_url.max_file_link_path]u8 = undefined;
    const preview = "/tmp/proj/docs/README.md";
    const project = "/tmp/proj";

    try std.testing.expectEqualStrings(
        "/tmp/proj/docs/shot.png",
        resolveInProjectImagePath("./shot.png", preview, project, &dest).?,
    );
    try std.testing.expectEqualStrings(
        "/tmp/proj/docs/img/a.png",
        resolveInProjectImagePath("img/a.png", preview, project, &dest).?,
    );
    try std.testing.expectEqualStrings(
        "/tmp/proj/docs/shot.png",
        resolveInProjectImagePath("file:///tmp/proj/docs/shot.png#L1", preview, project, &dest).?,
    );
    try std.testing.expectEqualStrings(
        "/tmp/proj/docs/foo bar.png",
        resolveInProjectImagePath("./foo%20bar.png", preview, project, &dest).?,
    );
    try std.testing.expectEqualStrings(
        "/tmp/proj/docs/shot.png",
        resolveInProjectImagePath("/tmp/proj/docs/shot.png", preview, project, &dest).?,
    );

    try std.testing.expect(resolveInProjectImagePath("https://example.com/a.png", preview, project, &dest) == null);
    try std.testing.expect(resolveInProjectImagePath("http://example.com/a.png", preview, project, &dest) == null);
    try std.testing.expect(resolveInProjectImagePath("data:image/png;base64,aaa", preview, project, &dest) == null);
    try std.testing.expect(resolveInProjectImagePath("mailto:hi@example.com", preview, project, &dest) == null);
    try std.testing.expect(resolveInProjectImagePath("#anchor", preview, project, &dest) == null);
    try std.testing.expect(resolveInProjectImagePath("", preview, project, &dest) == null);
    try std.testing.expect(resolveInProjectImagePath("file:///tmp/outside.png", preview, project, &dest) == null);
    try std.testing.expect(resolveInProjectImagePath("/etc/passwd", preview, project, &dest) == null);
    try std.testing.expect(resolveInProjectImagePath("../../etc/passwd", preview, project, &dest) == null);
}

test "isRemoteHttpImageSource accepts http(s); skips data empty overlong and local" {
    try std.testing.expect(isRemoteHttpImageSource("https://example.com/a.png"));
    try std.testing.expect(isRemoteHttpImageSource("http://example.com/a.png"));
    try std.testing.expect(isRemoteHttpImageSource("HTTPS://cdn.example.com/art.png"));
    try std.testing.expect(!isRemoteHttpImageSource("data:image/png;base64,aaa"));
    try std.testing.expect(!isRemoteHttpImageSource(""));
    try std.testing.expect(!isRemoteHttpImageSource("./shot.png"));
    try std.testing.expect(!isRemoteHttpImageSource("file:///tmp/proj/docs/shot.png"));

    const overlong = try std.testing.allocator.alloc(u8, native_sdk.max_effect_url_bytes + 8);
    defer std.testing.allocator.free(overlong);
    @memset(overlong, 'a');
    @memcpy(overlong[0..8], "https://");
    try std.testing.expect(!isRemoteHttpImageSource(overlong));
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

test "refresh loads in-project local path and http(s) url; drop and file switch clear mappings" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, "/tmp/faku-md-images-{s}", .{tmp.sub_path});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);
    var docs_buf: [280]u8 = undefined;
    const docs = try std.fmt.bufPrint(&docs_buf, "{s}/docs", .{project});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, docs);
    var readme_buf: [300]u8 = undefined;
    const readme = try std.fmt.bufPrint(&readme_buf, "{s}/docs/README.md", .{project});
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{
        .sub_path = readme,
        .data = "![local](./shot.png)\n\n![remote](https://example.com/x.png)\n\n![out](file:///tmp/outside.png)\n",
    });
    var other_buf: [300]u8 = undefined;
    const other = try std.fmt.bufPrint(&other_buf, "{s}/docs/other.md", .{project});
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{
        .sub_path = other,
        .data = "# no images\n",
    });

    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("md images", .fx);
    model.selected = id;
    model.setSelectedProjectPath(project);
    model.right_panel_open = true;
    const file_mention = @import("file_mention.zig");
    const right_panel = @import("right_panel.zig");
    file_mention.applyStdoutPaths(&model, "docs/README.md\ndocs/other.md\n");
    defer right_panel.clearFilePreview(&model);
    defer file_mention.clearCache(&model);

    right_panel.selectCachedFile(&model, &fx, 1);
    try std.testing.expect(model.file_preview_shows_rendered_markdown());
    try std.testing.expectEqual(@as(usize, 2), occupiedCount(&model));
    try std.testing.expectEqual(@as(usize, 2), fx.pendingImageLoadCount());

    const local_load = try pendingLoadWithPath(&fx);
    try std.testing.expect(std.mem.endsWith(u8, local_load.path, "/docs/shot.png"));
    try std.testing.expect(std.mem.startsWith(u8, local_load.path, project));
    try std.testing.expectEqual(@as(usize, 0), local_load.url.len);
    try std.testing.expect(local_load.id >= id_first);
    try std.testing.expect(local_load.id <= id_last);
    try std.testing.expectEqualStrings("./shot.png", model.file_preview_image_slots[0].source());

    const remote_load = try pendingLoadWithUrl(&fx);
    try std.testing.expectEqualStrings("https://example.com/x.png", remote_load.url);
    try std.testing.expectEqual(@as(usize, 0), remote_load.path.len);
    try std.testing.expect(remote_load.id >= id_first);
    try std.testing.expect(remote_load.id <= id_last);
    try std.testing.expect(remote_load.id != local_load.id);
    try std.testing.expectEqualStrings("https://example.com/x.png", model.file_preview_image_slots[1].source());

    try fx.feedImageResult(local_load.id, .loaded, 8, 8, 0, "");
    while (fx.takeMsg()) |msg| main.update(&model, msg, &fx);
    try std.testing.expectEqual(@as(usize, 1), loadedCount(&model));

    try fx.feedImageResult(remote_load.id, .loaded, 16, 12, 0, "");
    while (fx.takeMsg()) |msg| main.update(&model, msg, &fx);
    try std.testing.expectEqual(@as(usize, 2), loadedCount(&model));

    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const mapped = resolved(&model, arena_state.allocator());
    try std.testing.expectEqual(@as(usize, 2), mapped.len);
    try std.testing.expectEqualStrings("./shot.png", mapped[0].source);
    try std.testing.expectEqual(local_load.id, mapped[0].image);
    try std.testing.expectEqualStrings("https://example.com/x.png", mapped[1].source);
    try std.testing.expectEqual(remote_load.id, mapped[1].image);

    main.update(&model, .set_file_preview_markdown_source, &fx);
    try std.testing.expect(!model.file_preview_shows_rendered_markdown());
    try std.testing.expectEqual(@as(usize, 0), occupiedCount(&model));
    try std.testing.expectEqual(@as(usize, 0), loadedCount(&model));

    main.update(&model, .set_file_preview_markdown_preview, &fx);
    try std.testing.expectEqual(@as(usize, 2), occupiedCount(&model));
    const reload_local = try pendingLoadWithPath(&fx);
    const reload_remote = try pendingLoadWithUrl(&fx);
    try fx.feedImageResult(reload_local.id, .loaded, 8, 8, 0, "");
    try fx.feedImageResult(reload_remote.id, .loaded, 16, 12, 0, "");
    while (fx.takeMsg()) |msg| main.update(&model, msg, &fx);
    try std.testing.expectEqual(@as(usize, 2), loadedCount(&model));

    right_panel.selectCachedFile(&model, &fx, 2);
    try std.testing.expectEqual(@as(usize, 0), occupiedCount(&model));
    try std.testing.expectEqual(@as(usize, 0), loadedCount(&model));

    right_panel.selectCachedFile(&model, &fx, 1);
    try std.testing.expectEqual(@as(usize, 2), occupiedCount(&model));
    drop(&model, &fx);
    try std.testing.expectEqual(@as(usize, 0), occupiedCount(&model));
}

test "refresh skips data empty and outside-project; http(s) stays url-only" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, "/tmp/faku-md-remote-{s}", .{tmp.sub_path});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);
    var docs_buf: [280]u8 = undefined;
    const docs = try std.fmt.bufPrint(&docs_buf, "{s}/docs", .{project});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, docs);
    var readme_buf: [300]u8 = undefined;
    const readme = try std.fmt.bufPrint(&readme_buf, "{s}/docs/README.md", .{project});
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{
        .sub_path = readme,
        .data = "![http](http://example.com/a.png)\n\n![data](data:image/png;base64,aaa)\n\n![]()\n\n![out](file:///tmp/outside.png)\n",
    });

    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("md remote", .fx);
    model.selected = id;
    model.setSelectedProjectPath(project);
    model.right_panel_open = true;
    const file_mention = @import("file_mention.zig");
    const right_panel = @import("right_panel.zig");
    file_mention.applyStdoutPaths(&model, "docs/README.md\n");
    defer right_panel.clearFilePreview(&model);
    defer file_mention.clearCache(&model);

    right_panel.selectCachedFile(&model, &fx, 1);
    try std.testing.expectEqual(@as(usize, 1), occupiedCount(&model));
    try std.testing.expectEqual(@as(usize, 1), fx.pendingImageLoadCount());
    const load = try pendingLoadWithUrl(&fx);
    try std.testing.expectEqualStrings("http://example.com/a.png", load.url);
    try std.testing.expectEqual(@as(usize, 0), load.path.len);
    try std.testing.expectEqualStrings("http://example.com/a.png", model.file_preview_image_slots[0].source());

    try fx.feedImageResult(load.id, .loaded, 4, 4, 200, "");
    while (fx.takeMsg()) |msg| main.update(&model, msg, &fx);
    try std.testing.expectEqual(@as(usize, 1), loadedCount(&model));

    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const mapped = resolved(&model, arena_state.allocator());
    try std.testing.expectEqual(@as(usize, 1), mapped.len);
    try std.testing.expectEqualStrings("http://example.com/a.png", mapped[0].source);
    try std.testing.expectEqual(load.id, mapped[0].image);
}

test "applyResult unregisters stray loaded pixels outside the id band" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
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
