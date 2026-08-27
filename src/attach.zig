//! Composer attach preview, file-drop, and OS picker helpers.
//!
//! Preview ImageId recycle, window file drop, and Pick image sidecar
//! wiring live here. Model image-path fields and Msg routing stay in
//! `main.zig`. Behavior is unchanged from the former `main` attach
//! helpers.

const std = @import("std");
const native_sdk = @import("native_sdk");
const main = @import("main.zig");
const store = @import("store.zig");
const pick_image = @import("pick_image.zig");
const composer = @import("composer.zig");

const Model = main.Model;
const Effects = main.Effects;
const Msg = main.Msg;
const imagePathFromDrop = composer.imagePathFromDrop;
const isAttachImagePath = composer.isAttachImagePath;

/// One-shot OS image-picker sidecar (`osascript` / `zenity` / `kdialog`).
/// Distinct from fx ask / daemon / clipboard / preview keys. Native has
/// no `fx.pickFile`; this spawn is the documented workaround.
pub const pick_image_key: u64 = 31;
/// Caller-chosen ImageId for the composer attach preview. `fx.loadImage`
/// uses this as the effect key (shared with spawn / clipboard / file).
/// 0 is the no-image sentinel. Sits in the gap after `copy_turn_key`
/// and before `fx_spawn_overlap`. Verified: Native 0.9.3
/// `LoadImageOptions` + markup `<image image="{binding}">`.
pub const attach_preview_id_first: u64 = 33;
pub const attach_preview_id_last: u64 = 63;

fn nextAttachPreviewId(model: *Model) u64 {
    var id = model.next_attach_preview_id;
    if (id < attach_preview_id_first or id > attach_preview_id_last) {
        id = attach_preview_id_first;
    }
    if (id == model.attach_preview or id == model.attach_preview_load_id) {
        id += 1;
        if (id > attach_preview_id_last) id = attach_preview_id_first;
    }
    model.next_attach_preview_id = if (id >= attach_preview_id_last)
        attach_preview_id_first
    else
        id + 1;
    return id;
}

/// Drop in-flight / displayed preview pixels. Does not touch `image_path`.
fn dropAttachPreview(model: *Model, fx: *Effects) void {
    if (model.attach_preview != 0) {
        _ = fx.unregisterImage(model.attach_preview);
        model.attach_preview = 0;
    }
    if (model.attach_preview_load_id != 0) {
        fx.cancel(model.attach_preview_load_id);
        model.attach_preview_load_id = 0;
    }
}

/// Load a Native preview for the current draft path when that file exists.
/// Missing path keeps the basename chip only. Verified: Native 0.9.3
/// `fx.loadImage` local-path first + `<image image="{attach_preview}">`.
pub fn refreshAttachPreview(model: *Model, fx: *Effects) void {
    dropAttachPreview(model, fx);
    const path = model.resolveSpawnImage();
    if (path.len == 0) return;
    const id = nextAttachPreviewId(model);
    model.attach_preview_load_id = id;
    fx.loadImage(.{
        .id = id,
        .path = path,
        .on_result = Effects.imageMsg(.attach_preview_done),
    });
}

pub fn applyAttachPreviewResult(model: *Model, fx: *Effects, result: native_sdk.EffectImageResult) void {
    if (result.id != model.attach_preview_load_id) {
        if (result.outcome == .loaded) _ = fx.unregisterImage(result.id);
        return;
    }
    model.attach_preview_load_id = 0;
    if (result.outcome == .loaded) {
        model.attach_preview = result.id;
    }
}

/// Native `UiApp.Options.on_drop` → Msg. Window-level; no OS picker.
pub fn onDrop(drop: native_sdk.platform.FileDropEvent) ?Msg {
    const path = imagePathFromDrop(drop.paths) orelse return null;
    return .{ .file_drop = path };
}

pub fn applyFileDrop(model: *Model, fx: *Effects, path: []const u8) void {
    const trimmed = std.mem.trim(u8, path, " \t\r\n");
    if (!isAttachImagePath(trimmed)) return;
    if (model.store_io) |io| {
        if (main.directoryExists(io, trimmed)) return;
    }
    model.image_path_buffer.clear();
    model.applyImagePath(.{ .insert_text = trimmed });
    model.clearAttachStatus();
    store.persistDraftIfPossible(model);
    refreshAttachPreview(model, fx);
}

pub fn startPickImage(model: *Model, fx: *Effects) void {
    if (model.pick_image_live) return;
    const argv = pick_image.hostArgv(.first) orelse {
        model.setAttachStatus(pick_image.hostMissingStatus());
        return;
    };
    model.pick_image_live = true;
    model.pick_image_got_path = false;
    model.pick_image_tried_fallback = false;
    model.clearAttachStatus();
    fx.spawn(.{
        .key = pick_image_key,
        .argv = argv,
        .on_line = Effects.lineMsg(.fx_line),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
}

pub fn applyPickImageLine(model: *Model, fx: *Effects, line: native_sdk.EffectLine) void {
    const raw = pick_image.firstStdoutPath(line.line);
    if (pick_image.takeErrorMessage(raw)) |msg| {
        model.setAttachStatus(msg);
        return;
    }
    const path = imagePathFromDrop(&.{raw}) orelse return;
    applyFileDrop(model, fx, path);
    model.pick_image_got_path = true;
}

fn isMissingPickerExit(exit: native_sdk.EffectExit) bool {
    if (exit.reason != .exited) return true;
    return exit.code == 127 or exit.code == pick_image.missing_exit;
}

pub fn handlePickImageExit(model: *Model, fx: *Effects, exit: native_sdk.EffectExit) void {
    if (model.pick_image_got_path) {
        model.pick_image_live = false;
        return;
    }
    if (isMissingPickerExit(exit)) {
        if (!model.pick_image_tried_fallback) {
            if (pick_image.hostArgv(.fallback)) |argv| {
                model.pick_image_tried_fallback = true;
                fx.spawn(.{
                    .key = pick_image_key,
                    .argv = argv,
                    .on_line = Effects.lineMsg(.fx_line),
                    .on_exit = Effects.exitMsg(.fx_exit),
                });
                return;
            }
        }
        model.pick_image_live = false;
        if (!model.has_attach_status()) {
            model.setAttachStatus(pick_image.hostMissingStatus());
        }
        return;
    }
    model.pick_image_live = false;
}
