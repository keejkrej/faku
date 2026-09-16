//! Faku: Native SDK desktop for a Waku-protocol compatible coding-agent shell.
//!
//! First-party provider is the keejkrej/fx fork (https://github.com/keejkrej/fx).
//! Native-root contracts live here (`app_icons`, `Effects`, `update` /
//! `initFx`, `onDrop`, `app_markup`, `panic`). Desktop bootstrap
//! (`UiApp.create`, model bind, `runner.runWithOptions`) lives in
//! `app_run.zig`. Product language: `CONTEXT.md`.

const std = @import("std");
const native_sdk = @import("native_sdk");
const attach_helpers = @import("attach.zig");
const update_mod = @import("update.zig");
const shell_mod = @import("shell.zig");
const model_exports = @import("model_exports.zig");
const app_run = @import("app_run.zig");

pub const panic = std.debug.FullPanic(native_sdk.debug.capturePanic);

/// Native model contract looks for `pub const app_icons` on the app root.
pub const app_icons = shell_mod.app_icons;

const Msg = model_exports.Msg;

pub const Effects = native_sdk.Effects(Msg);

pub const update = update_mod.update;
pub const initFx = update_mod.initFx;

/// Native `UiApp.Options.on_drop` → Msg. Window-level; no OS picker.
pub const onDrop = attach_helpers.onDrop;

/// Native markup contract. Embed lives in `app_run` so the window loop
/// and `native check` share one `@embedFile`.
pub const app_markup = app_run.app_markup;

pub fn main(init: std.process.Init) !void {
    try app_run.run(init);
}

test {
    _ = @import("root_tests.zig");
}
