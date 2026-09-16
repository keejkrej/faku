//! Desktop bootstrap: proxy early-exit, UiApp.create, model bind,
//! `runner.runWithOptions`.
//!
//! Native-root contracts stay on `main.zig` (`app_icons`, `Effects`,
//! `update` / `initFx`, `onDrop`, `app_markup`, `panic`). This module
//! owns the former `main()` body. Callers import it directly
//! (`app_run.run`); `main` is a thin `try app_run.run(init)`.
//! Behavior is unchanged from the former `main` function.

const std = @import("std");
const runner = @import("runner");
const native_sdk = @import("native_sdk");
const protocol = @import("protocol.zig");
const acp = @import("acp.zig");
const store = @import("store.zig");
const daemon_proxy = @import("daemon_proxy.zig");
const acp_proxy = @import("acp_proxy.zig");
const keys = @import("keys.zig");
const attach_helpers = @import("attach.zig");
const update_mod = @import("update.zig");
const boot_mod = @import("boot.zig");
const shell_mod = @import("shell.zig");
const model_exports = @import("model_exports.zig");
const i18n = @import("i18n.zig");
const util = @import("util.zig");
const browser_pane = @import("browser_pane.zig");

const geometry = native_sdk.geometry;

const canvas_label = shell_mod.canvas_label;
const window_width = shell_mod.window_width;
const window_height = shell_mod.window_height;
const shell_scene = shell_mod.shell_scene;
const registerIcons = shell_mod.registerIcons;

const app_permissions = [_][]const u8{ native_sdk.security.permission_command, native_sdk.security.permission_view };

const Msg = model_exports.Msg;
const Model = model_exports.Model;

/// Native markup contract lives on `main` as a re-export so `native check`
/// and tests keep `main.app_markup`. Embed once here.
pub const app_markup = @embedFile("app.native");

const FakuApp = native_sdk.UiApp(Model, Msg);

pub fn run(init: std.process.Init) !void {
    if (try daemon_proxy.maybeRun(init)) return;
    if (try acp_proxy.maybeRun(init)) return;
    _ = protocol.FX_ACP_ARGV;
    _ = acp.PROTOCOL_VERSION;
    registerIcons();
    const app_state = try FakuApp.create(std.heap.page_allocator, .{
        .name = "faku",
        .scene = shell_scene,
        .canvas_label = canvas_label,
        .update_fx = update_mod.update,
        .init_fx = update_mod.initFx,
        .on_key = keys.onKey,
        .on_drop = attach_helpers.onDrop,
        .on_appearance = boot_mod.onAppearance,
        .tokens_fn = boot_mod.designTokens,
        .markup = .{ .source = app_markup, .watch_path = "src/app.native", .io = init.io },
        .web_panes = browser_pane.webPanes,
    });
    defer app_state.destroy();
    app_state.model = boot_mod.initialModel();
    if (init.environ_map.get("HOME")) |home| {
        app_state.model.setHome(home);
        store.bindDefaultDir(&app_state.model, home, init.environ_map.get("XDG_DATA_HOME"));
    }
    util.bindDaemonEnv(&app_state.model, init);
    app_state.model.setSystemLocaleId(i18n.pickSystemLocaleId(
        init.environ_map.get("LC_ALL") orelse "",
        init.environ_map.get("LC_MESSAGES") orelse "",
        init.environ_map.get("LANG") orelse "",
    ));
    _ = store.boot(&app_state.model, std.heap.page_allocator, init.io);
    if (init.environ_map.get(protocol.DAEMON_ADDRESS_ENV)) |addr| {
        app_state.model.setDaemonAddress(addr);
    }

    try runner.runWithOptions(app_state.app(), .{
        .app_name = "faku",
        .window_title = "Faku",
        .bundle_id = "com.faku.app",
        .icon_path = "assets/icon.png",
        .default_frame = geometry.RectF.init(0, 0, window_width, window_height),
        .js_window_api = false,
        .security = .{
            .permissions = &app_permissions,
            .navigation = .{ .allowed_origins = &.{ "zero://inline", "zero://app", "*" } },
        },
    }, init);
}

test "app_permissions stay command and view" {
    try std.testing.expectEqual(@as(usize, 2), app_permissions.len);
    try std.testing.expectEqualStrings(native_sdk.security.permission_command, app_permissions[0]);
    try std.testing.expectEqualStrings(native_sdk.security.permission_view, app_permissions[1]);
}
