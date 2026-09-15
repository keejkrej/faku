//! OS sidecar and media/preview effect-key re-exports.
//!
//! One-shot maximize / picker / reveal / URL / terminal / pty / editor
//! keys, clipboard + notify fallback constants, and attach / Files /
//! transcript preview ImageId bands. Owning modules keep the values;
//! this file only re-exports them. Callers import this module directly
//! (`sidecar_keys.maximize_window_key` / `sidecar_keys.copy_turn_key`).
//! Not re-exported from `main`. Behavior is unchanged from the former
//! `main` constants.

const std = @import("std");
const maximize_window = @import("maximize_window.zig");
const attach = @import("attach.zig");
const pick_folder = @import("pick_folder.zig");
const reveal_folder = @import("reveal_folder.zig");
const open_url = @import("open_url.zig");
const open_terminal = @import("open_terminal.zig");
const pty_terminal = @import("pty_terminal.zig");
const open_editor = @import("open_editor.zig");
const copy = @import("copy.zig");
const file_preview_images = @import("file_preview_images.zig");
const transcript_images = @import("transcript_images.zig");

/// One-shot OS maximize sidecar (`osascript` / `wmctrl` / `xdotool`).
/// Distinct from fx ask / daemon / picker / clipboard keys. Native
/// still has no `fx.maximizeWindow`; this spawn is the workaround.
pub const maximize_window_key = maximize_window.maximize_window_key;
/// One-shot OS image-picker sidecar (`osascript` / `zenity` / `kdialog` /
/// Windows `powershell.exe` OpenFileDialog). Distinct from fx ask / daemon /
/// clipboard / preview keys. Native has no `fx.pickFile`; this spawn is the
/// documented workaround.
pub const pick_image_key = attach.pick_image_key;
/// One-shot OS folder-picker sidecar (`osascript` / `zenity` / `kdialog` /
/// Windows `powershell.exe` FolderBrowserDialog). Distinct from pick_image
/// (31), maximize (30), copy_turn (32). Native has no `fx.pickFile`; this
/// spawn is the documented workaround.
pub const pick_folder_key = pick_folder.pick_folder_key;
/// One-shot OS file-manager sidecar (`open` / `xdg-open` / Windows `explorer.exe`). Distinct from
/// pick_folder (29), maximize (30), pick_image (31), copy_turn (32).
/// Native has no typed `fx.revealPath` on this Effects revision.
pub const reveal_folder_key = reveal_folder.reveal_folder_key;
/// One-shot OS URL-open sidecar (`open` / `xdg-open` / Windows
/// `cmd.exe /c start`). Distinct from open_editor (26), open_terminal
/// (27), reveal_folder (28). OS-host fallback beside the embedded
/// Browser `web_panes` webviews (up to four scene slots).
pub const open_url_key = open_url.open_url_key;
/// One-shot OS terminal sidecar (`open -a Terminal` / `x-terminal-emulator` /
/// Windows `wt.exe -d` then `cmd.exe /c start "" /D`). Distinct from
/// reveal_folder (28), pick_folder (29), maximize (30), pick_image (31),
/// copy_turn (32). OS-host fallback beside the embedded `<terminal>`
/// (`pty_shell_key`). Native has no typed open-terminal effect on this
/// Effects revision.
pub const open_terminal_key = open_terminal.open_terminal_key;
/// Dedicated pty occupancy for the right-panel `<terminal>` binding.
/// Distinct from Open in Terminal (27) and litellm (650). Fixed band
/// 700..703 (first-cut multi-session, cap 4).
pub const pty_shell_key = pty_terminal.pty_shell_key;
/// One-shot OS editor sidecar (`cursor` / `code`, macOS `open -a`, Windows `cursor.cmd` / `code.cmd`).
/// Distinct from open_terminal (27), reveal_folder (28), pick_folder (29),
/// maximize (30), pick_image (31), copy_turn (32). Native has no typed
/// open-editor effect on this Effects revision.
pub const open_editor_key = open_editor.open_editor_key;
pub const copy_turn_key = copy.copy_turn_key;
/// Empty `fx_session_id` / ACP sessionId: do not writeClipboard.
pub const no_provider_session_id_status = copy.no_provider_session_id_status;
/// Caller-chosen ImageId for the composer attach preview. `fx.loadImage`
/// uses this as the effect key (shared with spawn / clipboard / file).
/// 0 is the no-image sentinel. Sits in the gap after `copy_turn_key`
/// and before `fx_spawn_overlap`. Files markdown Preview images use
/// 800–815; transcript markdown images use 816–831.
/// Verified: Native 0.9.3 `LoadImageOptions` + markup
/// `<image image="{binding}">`.
pub const attach_preview_id_first = attach.attach_preview_id_first;
pub const attach_preview_id_last = attach.attach_preview_id_last;
/// Files Preview markdown image ids (`fx.loadImage` / `registerImageBytes`).
/// Cap Native `max_markdown_images`. Distinct from attach preview 33–63
/// and transcript markdown images 816–831.
pub const file_preview_image_id_first = file_preview_images.id_first;
pub const file_preview_image_id_last = file_preview_images.id_last;
/// Transcript markdown image ids (`fx.loadImage` /
/// `registerImageBytes`). Cap Native `max_markdown_images`. Distinct
/// from Files Preview 800–815 and attach preview 33–63.
pub const transcript_image_id_first = transcript_images.id_first;
pub const transcript_image_id_last = transcript_images.id_last;
/// Desktop notification title when the session has no stored title.
pub const notify_fallback_title = copy.notify_fallback_title;
/// Desktop notification body when the last assistant turn is empty.
pub const notify_fallback_body = copy.notify_fallback_body;
/// Short body cap. Native allows 1024; keep the toast readable.
pub const notify_body_max = copy.notify_body_max;

test "OS sidecar and media preview keys match owning modules" {
    try std.testing.expectEqual(maximize_window.maximize_window_key, maximize_window_key);
    try std.testing.expectEqual(attach.pick_image_key, pick_image_key);
    try std.testing.expectEqual(pick_folder.pick_folder_key, pick_folder_key);
    try std.testing.expectEqual(reveal_folder.reveal_folder_key, reveal_folder_key);
    try std.testing.expectEqual(open_url.open_url_key, open_url_key);
    try std.testing.expectEqual(open_terminal.open_terminal_key, open_terminal_key);
    try std.testing.expectEqual(pty_terminal.pty_shell_key, pty_shell_key);
    try std.testing.expectEqual(open_editor.open_editor_key, open_editor_key);
    try std.testing.expectEqual(copy.copy_turn_key, copy_turn_key);
    try std.testing.expectEqualStrings(copy.no_provider_session_id_status, no_provider_session_id_status);
    try std.testing.expectEqual(attach.attach_preview_id_first, attach_preview_id_first);
    try std.testing.expectEqual(attach.attach_preview_id_last, attach_preview_id_last);
    try std.testing.expectEqual(file_preview_images.id_first, file_preview_image_id_first);
    try std.testing.expectEqual(file_preview_images.id_last, file_preview_image_id_last);
    try std.testing.expectEqual(transcript_images.id_first, transcript_image_id_first);
    try std.testing.expectEqual(transcript_images.id_last, transcript_image_id_last);
    try std.testing.expectEqualStrings(copy.notify_fallback_title, notify_fallback_title);
    try std.testing.expectEqualStrings(copy.notify_fallback_body, notify_fallback_body);
    try std.testing.expectEqual(copy.notify_body_max, notify_body_max);
}
