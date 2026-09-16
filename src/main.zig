//! Faku: Native SDK desktop for a Waku-protocol compatible coding-agent shell.
//!
//! First-party provider is the keejkrej/fx fork (https://github.com/keejkrej/fx). Send on an `.fx`
//! session runs one-shot `faku acp-proxy -- … fx acp` when the CLI is
//! installed (NDJSON stdin: initialize, session/new or session/resume,
//! set model/mode, session/prompt). The sidecar keeps fx stdin open and
//! auto-answers `session/request_permission` from that run's access
//! mode. Draft `image_path` still uses `fx ask --image` (ACP rejects
//! image blocks). After the fx branch, probed ACP stdio providers
//! (cursor / opencode / kimi `acp`, grok `agent stdio`) use the same acp-proxy
//! path when `--help` is available, including first-cut official ACP
//! v1 image content blocks on `session/prompt` when a composer image
//! is attached (base64 + mimeType; overflow / bad file fail closed to
//! demo); Available Claude uses one-shot
//! print-mode stream-json (`claude -p --output-format stream-json
//! --verbose --include-partial-messages --forward-subagent-text`,
//! not ACP), with documented
//! `--resume {fx_session_id}` on later Sends when that field is
//! non-empty (first Send and Fork omit it; not `--continue`), and
//! with the documented image path inside that `-p` prompt when a
//! composer image is attached (code.claude.com/docs/en/common-workflows;
//! stdout is NDJSON: live `text_delta` into the transcript, not a
//! prose dump; non-empty `parent_tool_use_id` is subagent traffic
//! (forwarded text fills a bounded 512KB last-window on that
//! Subagent Background row; still off the main turn);
//! `tool_use` with `name` `Monitor` fills live Monitor Background;
//! matching user `tool_result` fills a bounded 512KB last-window
//! log on that row (newlines kept; CSI stripped for display;
//! Environment Summary stays a one-line preview); Available Codex uses one-shot `codex exec {prompt}` (not ACP), with
//! documented `--image {path}` after the prompt when a composer image
//! is attached; Available Amp uses one-shot `amp -x {prompt}` (not ACP),
//! with a documented `@{path}` mention in that `-x` prompt when a
//! composer image is attached; Available Pi uses one-shot
//! `pi --mode json {prompt}` (not ACP, not `--mode rpc`), with
//! documented `@{path}` after `--mode json` when a composer image
//! is attached (stdout is JSON events: live `text_delta` into the
//! transcript, not a prose dump); cursor / opencode / kimi / grok image
//! attach uses ACP image content blocks (not `fx ask --image`).
//! When `WAKU_DAEMON_ADDRESS` is set, Send instead
//! spawns a one-shot `daemon-proxy` sidecar (hello + attachSession +
//! start + prompt when no runtime id; later sends keep attach + prompt).
//! Stop / Esc of that daemon turn `fx.cancel`s the prompt spawn and
//! one-shots hello + `cancel` on a distinct key. Missing address /
//! image / ACP stdin overflow keep `fx ask` or the demo timer. This
//! is not a long-lived ACP or daemon runtime loop — Native stdin is
//! one buffer, then it closes. The ACP sidecar owns the child stdin.

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

pub const panic = std.debug.FullPanic(native_sdk.debug.capturePanic);

const geometry = native_sdk.geometry;

const canvas_label = shell_mod.canvas_label;
const window_width = shell_mod.window_width;
const window_height = shell_mod.window_height;
const shell_scene = shell_mod.shell_scene;
const registerIcons = shell_mod.registerIcons;
/// Native model contract looks for `pub const app_icons` on the app root.
pub const app_icons = shell_mod.app_icons;

const app_permissions = [_][]const u8{ native_sdk.security.permission_command, native_sdk.security.permission_view };

const Msg = model_exports.Msg;
const Model = model_exports.Model;

pub const Effects = native_sdk.Effects(Msg);

pub const update = update_mod.update;
pub const initFx = update_mod.initFx;

/// Native `UiApp.Options.on_drop` → Msg. Window-level; no OS picker.
pub const onDrop = attach_helpers.onDrop;

pub const app_markup = @embedFile("app.native");

const FakuApp = native_sdk.UiApp(Model, Msg);

pub fn main(init: std.process.Init) !void {
    if (try daemon_proxy.maybeRun(init)) return;
    if (try acp_proxy.maybeRun(init)) return;
    _ = protocol.FX_ACP_ARGV;
    _ = acp.PROTOCOL_VERSION;
    registerIcons();
    const app_state = try FakuApp.create(std.heap.page_allocator, .{
        .name = "faku",
        .scene = shell_scene,
        .canvas_label = canvas_label,
        .update_fx = update,
        .init_fx = initFx,
        .on_key = keys.onKey,
        .on_drop = onDrop,
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

test {
    _ = @import("root_tests.zig");
}
