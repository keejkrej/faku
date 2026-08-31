//! Prompt-start and provider-spawn helpers.
//!
//! `startPrompt` path selection (daemon / fx acp / fx ask / probed
//! ACP stdio via acp-proxy / Claude print-mode / Codex exec / Amp
//! execute-mode / Pi print-mode / demo), StartOptions mapping, and
//! `takeFxAskSessionId` live here. Stream lifecycle lives in
//! `stream.zig`. Line handlers live in `lines.zig`.
//!
//! Non-fx live Send this cut: `ProviderId.speaksAcpStdio` (cursor /
//! opencode bare `acp`, grok `agent stdio`) when
//! `providers.isAvailable`. Same one-shot `faku acp-proxy -- {binary}
//! …transport…` as fx. `reply_path` stays `.fx` so ACP stream parsing
//! (`fx_spawn_acp` / `fx_line` / `fx_exit`) is unchanged. After that,
//! Available Claude with no image attach is one-shot
//! `{binary} -p --output-format text {prompt}` (empty stdin, not ACP,
//! not acp-proxy). Available Codex with no image attach is one-shot
//! `{binary} exec {prompt}` (empty stdin, not ACP, not acp-proxy).
//! Available Amp with no image attach is one-shot `{binary} -x
//! {prompt}` (empty stdin, not ACP, not acp-proxy). Available Pi
//! with no image attach is one-shot `{binary} -p {prompt}` (empty
//! stdin, not ACP, not acp-proxy; `--print` is the long form).
//! `reply_path` stays `.fx` with `fx_spawn_acp = false` so stdout
//! lines use the existing non-ACP `handleFxLine` path. Image attach
//! on non-fx stays demo.

const std = @import("std");
const main = @import("main.zig");
const protocol = @import("protocol.zig");
const acp = @import("acp.zig");
const store = @import("store.zig");
const daemon_proxy = @import("daemon_proxy.zig");
const acp_proxy = @import("acp_proxy.zig");
const composer = @import("composer.zig");
const session_fork = @import("fork.zig");
const providers = @import("providers.zig");

const Model = main.Model;
const Effects = main.Effects;
const Session = main.Session;
const writeFixed = main.writeFixed;
const fxPermissionMode = composer.fxPermissionMode;
const stream_timer_key = main.stream_timer_key;
const stream_interval_ms = main.stream_interval_ms;
const fx_ask_key = main.fx_ask_key;
const daemon_line_bytes = main.daemon_line_bytes;
const max_fx_model = main.max_fx_model;
const max_access_mode = main.max_access_mode;
const default_access_mode = main.default_access_mode;
const default_interaction_mode = main.default_interaction_mode;
const fx_env_bin = main.fx_env_bin;
const fx_ask_chdir_script = main.fx_ask_chdir_script;

pub fn startPrompt(model: *Model, fx: *Effects, session_id: u32, text: []const u8) void {
    const session = model.sessionById(session_id) orelse return;
    session_fork.recordRewindRefIfPossible(model, session.id);
    const titled = session.untitled;
    if (session.untitled) {
        writeFixed(&session.title_storage, &session.title_len, text);
        session.untitled = false;
    }
    _ = model.appendTurn(session.id, .user, text);
    const assistant_id = model.appendTurn(session.id, .assistant, "");
    if (titled) store.persistIfPossible(model, session.id, fx);
    session.busy = true;
    model.phase = .streaming;
    model.stream_cursor = 0;
    model.stream_turn_id = assistant_id;
    model.streaming_session = session.id;
    if (model.daemonAddress().len > 0) {
        model.reply_path = .daemon;
        startDaemonProxy(model, fx, session, text);
        return;
    }
    if (session.provider == .fx and model.fx_available and model.fxPath().len > 0) {
        model.reply_path = .fx;
        const image_path = model.resolveSpawnImage();
        if (image_path.len > 0) {
            startFxAsk(model, fx, session, text);
            return;
        }
        if (!startFxAcp(model, fx, session, text)) {
            startFxAsk(model, fx, session, text);
        }
        return;
    }
    if (session.provider.speaksAcpStdio() and providers.isAvailable(model, session.provider)) {
        // ACP has no image blocks this cut; non-fx image attach stays demo.
        if (model.resolveSpawnImage().len == 0) {
            const binary = providers.binaryFor(model, session.provider);
            // Reuse fx spawn keys / fx_line / fx_exit / reply_path=.fx
            // so handleAcpLine keeps working. Not a new ReplyPath alias.
            model.reply_path = .fx;
            if (startAcpProxy(model, fx, session, binary, text)) return;
        }
    }
    if (session.provider == .claude and providers.isAvailable(model, .claude)) {
        // Claude Code is not ACP. Official print mode is one-shot
        // `claude -p --output-format text`. Image attach stays demo.
        if (model.resolveSpawnImage().len == 0) {
            if (startClaudePrint(model, fx, session, text)) {
                model.reply_path = .fx;
                return;
            }
        }
    }
    if (session.provider == .codex and providers.isAvailable(model, .codex)) {
        // Codex is not ACP. Official non-interactive mode is one-shot
        // `codex exec {prompt}`. Image attach stays demo.
        if (model.resolveSpawnImage().len == 0) {
            if (startCodexExec(model, fx, session, text)) {
                model.reply_path = .fx;
                return;
            }
        }
    }
    if (session.provider == .amp and providers.isAvailable(model, .amp)) {
        // Amp is not ACP. Official execute mode is one-shot
        // `amp -x {prompt}`. Image attach stays demo.
        if (model.resolveSpawnImage().len == 0) {
            if (startAmpExecute(model, fx, session, text)) {
                model.reply_path = .fx;
                return;
            }
        }
    }
    if (session.provider == .pi and providers.isAvailable(model, .pi)) {
        // Pi is not ACP. Official print mode is one-shot
        // `pi -p {prompt}` (`--print` is the long form). Image
        // attach stays demo.
        if (model.resolveSpawnImage().len == 0) {
            if (startPiPrint(model, fx, session, text)) {
                model.reply_path = .fx;
                return;
            }
        }
    }
    model.reply_path = .demo;
    startDemoTimer(fx);
}

pub fn startDemoTimer(fx: *Effects) void {
    fx.startTimer(.{
        .key = stream_timer_key,
        .interval_ms = stream_interval_ms,
        .mode = .repeating,
        .on_fire = Effects.timerMsg(.tick),
    });
}

/// Map stored session fields onto verified `StartOptions`. Empty
/// `project_path` becomes `"."`. Empty model is omitted on the wire.
/// `computer_use_enabled` is not stored here and stays false.
pub fn startOptionsFromSession(session: *const Session) protocol.StartOptions {
    return .{
        .provider = session.provider.wireName(),
        .binary = session.provider.defaultBinary(),
        .cwd = if (session.projectPath().len > 0) session.projectPath() else ".",
        .mode = if (session.accessMode().len > 0) session.accessMode() else default_access_mode,
        .interaction_mode = if (session.interactionMode().len > 0) session.interactionMode() else default_interaction_mode,
        .model = if (session.model().len > 0) session.model() else null,
        .reasoning_effort = if (session.reasoningEffort().len > 0) session.reasoningEffort() else null,
        .computer_use_enabled = false,
    };
}

pub fn startDaemonProxy(model: *Model, fx: *Effects, session: *const Session, prompt: []const u8) void {
    var id_buf: [36]u8 = undefined;
    const session_id = daemon_proxy.wireUuid(session.id, &id_buf);
    const has_runtime = protocol.isUsableRuntimeId(session.runtimeId());
    const runtime_id = if (has_runtime) session.runtimeId() else protocol.NIL_UUID;
    const start = if (has_runtime) null else startOptionsFromSession(session);
    var stdin_buf: [4096]u8 = undefined;
    const stdin = daemon_proxy.writeTurnStdin(&stdin_buf, .{
        .token = model.daemonToken(),
        .session_id = session_id,
        .runtime_id = runtime_id,
        .prompt = prompt,
        .start = start,
    }) catch {
        model.reply_path = .demo;
        startDemoTimer(fx);
        return;
    };

    model.setLastDaemonAddress(model.daemonAddress());
    model.daemon_spawn_key = model.next_daemon_key;
    model.next_daemon_key += 1;

    fx.spawn(.{
        .key = model.daemon_spawn_key,
        .argv = &.{ model.sidecarPath(), daemon_proxy.SUBCOMMAND, model.daemonAddress() },
        .stdin = stdin,
        .max_line_bytes = daemon_line_bytes,
        .on_line = Effects.lineMsg(.fx_line),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
}

pub fn allocateFxSpawnKey(model: *Model) u64 {
    const key = if (model.fx_spawn_live) blk: {
        const k = model.next_fx_key;
        model.next_fx_key = k + 1;
        break :blk k;
    } else fx_ask_key;
    model.fx_spawn_key = key;
    model.fx_spawn_live = true;
    return key;
}

pub fn startFxAcp(model: *Model, fx: *Effects, session: *const Session, prompt: []const u8) bool {
    return startAcpProxy(model, fx, session, model.fxPath(), prompt);
}

/// One-shot `faku acp-proxy -- {binary} …transport…` with the
/// existing ACP stdin batch. Transport comes from
/// `ProviderId.acpTransportArgv` (`acp` for fx / cursor / opencode,
/// `agent stdio` for grok). fx still prefixes `FX_MODEL` /
/// `FX_PERMISSION_MODE` via `/usr/bin/env` (same as before).
/// Permission also rides `session/set_mode` in the batch. Empty
/// binary or empty transport is a no-op.
pub fn startAcpProxy(model: *Model, fx: *Effects, session: *const Session, binary: []const u8, prompt: []const u8) bool {
    if (binary.len == 0) return false;
    const transport = session.provider.acpTransportArgv();
    if (transport.len == 0) return false;
    const cwd = model.resolveAcpCwd(session);
    const resume_id = session.fxSessionId();
    const model_id = session.model();
    const permission_mode = fxPermissionMode(session.accessMode());
    model.setLastSpawnCwd(cwd);
    model.setLastSpawnFxModel(model_id);
    model.setLastSpawnFxPermissionMode(permission_mode);
    model.setLastSpawnImagePath("");

    var stdin_buf: [8192]u8 = undefined;
    const stdin = acp.writeTurnStdin(&stdin_buf, .{
        .cwd = cwd,
        .resume_id = resume_id,
        .prompt = prompt,
        .model = model_id,
        .access_mode = session.accessMode(),
    }) catch return false;

    var model_assign: [max_fx_model + 16]u8 = undefined;
    var perm_assign: [max_access_mode + 24]u8 = undefined;
    const model_arg = if (model_id.len > 0)
        std.fmt.bufPrint(&model_assign, "FX_MODEL={s}", .{model_id}) catch ""
    else
        "";
    const perm_arg = if (permission_mode.len > 0)
        std.fmt.bufPrint(&perm_assign, "FX_PERMISSION_MODE={s}", .{permission_mode}) catch ""
    else
        "";

    var argv_buf: [16][]const u8 = undefined;
    var n: usize = 0;
    argv_buf[n] = model.sidecarPath();
    n += 1;
    argv_buf[n] = acp_proxy.SUBCOMMAND;
    n += 1;
    argv_buf[n] = "--";
    n += 1;
    if (model_arg.len > 0 or perm_arg.len > 0) {
        argv_buf[n] = fx_env_bin;
        n += 1;
        if (model_arg.len > 0) {
            argv_buf[n] = model_arg;
            n += 1;
        }
        if (perm_arg.len > 0) {
            argv_buf[n] = perm_arg;
            n += 1;
        }
    }
    argv_buf[n] = binary;
    n += 1;
    for (transport) |arg| {
        argv_buf[n] = arg;
        n += 1;
    }

    model.fx_spawn_acp = true;
    fx.spawn(.{
        .key = allocateFxSpawnKey(model),
        .argv = argv_buf[0..n],
        .stdin = stdin,
        .on_line = Effects.lineMsg(.fx_line),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
    return true;
}

pub fn startFxAsk(model: *Model, fx: *Effects, session: *const Session, prompt: []const u8) void {
    const path = model.fxPath();
    const cwd = model.resolveSpawnCwd(session);
    const resume_id = session.fxSessionId();
    const model_id = session.model();
    const permission_mode = fxPermissionMode(session.accessMode());
    const image_path = model.resolveSpawnImage();
    model.setLastSpawnCwd(cwd);
    model.setLastSpawnFxModel(model_id);
    model.setLastSpawnFxPermissionMode(permission_mode);
    model.setLastSpawnImagePath(image_path);

    // Native SpawnOptions has no `env`. `/usr/bin/env KEY=val` sets the
    // child only — do not export on the Faku process.
    var model_assign: [max_fx_model + 16]u8 = undefined;
    var perm_assign: [max_access_mode + 24]u8 = undefined;
    const model_arg = if (model_id.len > 0)
        std.fmt.bufPrint(&model_assign, "FX_MODEL={s}", .{model_id}) catch ""
    else
        "";
    const perm_arg = if (permission_mode.len > 0)
        std.fmt.bufPrint(&perm_assign, "FX_PERMISSION_MODE={s}", .{permission_mode}) catch ""
    else
        "";

    var argv_buf: [20][]const u8 = undefined;
    var n: usize = 0;
    if (cwd.len > 0) {
        argv_buf[n] = "/bin/sh";
        n += 1;
        argv_buf[n] = "-c";
        n += 1;
        argv_buf[n] = fx_ask_chdir_script;
        n += 1;
        argv_buf[n] = "sh";
        n += 1;
        argv_buf[n] = cwd;
        n += 1;
    }
    if (model_arg.len > 0 or perm_arg.len > 0) {
        argv_buf[n] = fx_env_bin;
        n += 1;
        if (model_arg.len > 0) {
            argv_buf[n] = model_arg;
            n += 1;
        }
        if (perm_arg.len > 0) {
            argv_buf[n] = perm_arg;
            n += 1;
        }
    }
    argv_buf[n] = path;
    n += 1;
    argv_buf[n] = "ask";
    n += 1;
    argv_buf[n] = "--json";
    n += 1;
    if (resume_id.len > 0) {
        argv_buf[n] = "--resume";
        n += 1;
        argv_buf[n] = resume_id;
        n += 1;
    }
    if (image_path.len > 0) {
        argv_buf[n] = "--image";
        n += 1;
        argv_buf[n] = image_path;
        n += 1;
    }
    argv_buf[n] = "--";
    n += 1;
    argv_buf[n] = prompt;
    n += 1;

    model.fx_spawn_acp = false;
    fx.spawn(.{
        .key = allocateFxSpawnKey(model),
        .argv = argv_buf[0..n],
        .on_line = Effects.lineMsg(.fx_line),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
}

/// One-shot official Claude Code print mode:
/// `{binary} -p --output-format text {prompt}`. Prompt is an argv
/// slot (documented `claude -p "query"`). Empty stdin. Not ACP, not
/// `claude acp`, not stream-json, not permissions bypass, not
/// acp-proxy. Caller sets `reply_path` to `.fx` on success;
/// `fx_spawn_acp` stays false so stdout lines reuse non-ACP
/// `handleFxLine` / `handleFxExit`. Project cwd reuses
/// `fx_ask_chdir_script` (Native SpawnOptions has no cwd field).
/// Empty binary is a no-op (PATH default is `claude`).
pub fn startClaudePrint(model: *Model, fx: *Effects, session: *const Session, prompt: []const u8) bool {
    const binary = providers.binaryFor(model, .claude);
    if (binary.len == 0) return false;
    const cwd = model.resolveSpawnCwd(session);
    model.setLastSpawnCwd(cwd);
    model.setLastSpawnImagePath("");

    var argv_buf: [16][]const u8 = undefined;
    var n: usize = 0;
    if (cwd.len > 0) {
        argv_buf[n] = "/bin/sh";
        n += 1;
        argv_buf[n] = "-c";
        n += 1;
        argv_buf[n] = fx_ask_chdir_script;
        n += 1;
        argv_buf[n] = "sh";
        n += 1;
        argv_buf[n] = cwd;
        n += 1;
    }
    argv_buf[n] = binary;
    n += 1;
    argv_buf[n] = "-p";
    n += 1;
    argv_buf[n] = "--output-format";
    n += 1;
    argv_buf[n] = "text";
    n += 1;
    argv_buf[n] = prompt;
    n += 1;

    model.fx_spawn_acp = false;
    fx.spawn(.{
        .key = allocateFxSpawnKey(model),
        .argv = argv_buf[0..n],
        .stdin = "",
        .on_line = Effects.lineMsg(.fx_line),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
    return true;
}

/// One-shot official Codex non-interactive mode:
/// `{binary} exec {prompt}`. Prompt is an argv slot (documented
/// `codex exec [OPTIONS] [PROMPT]`). Empty stdin. Progress streams
/// to stderr; the final agent message prints to stdout, so the
/// existing non-ACP `handleFxLine` path is safe. Not ACP, not
/// acp-proxy, not stream-json, not `--full-auto` / sandbox bypass /
/// `--ask-for-approval never`. Caller sets `reply_path` to `.fx` on
/// success; `fx_spawn_acp` stays false. Project cwd reuses
/// `fx_ask_chdir_script` (Native SpawnOptions has no cwd field).
/// Empty binary is a no-op (PATH default is `codex`).
pub fn startCodexExec(model: *Model, fx: *Effects, session: *const Session, prompt: []const u8) bool {
    const binary = providers.binaryFor(model, .codex);
    if (binary.len == 0) return false;
    const cwd = model.resolveSpawnCwd(session);
    model.setLastSpawnCwd(cwd);
    model.setLastSpawnImagePath("");

    var argv_buf: [16][]const u8 = undefined;
    var n: usize = 0;
    if (cwd.len > 0) {
        argv_buf[n] = "/bin/sh";
        n += 1;
        argv_buf[n] = "-c";
        n += 1;
        argv_buf[n] = fx_ask_chdir_script;
        n += 1;
        argv_buf[n] = "sh";
        n += 1;
        argv_buf[n] = cwd;
        n += 1;
    }
    argv_buf[n] = binary;
    n += 1;
    argv_buf[n] = "exec";
    n += 1;
    argv_buf[n] = prompt;
    n += 1;

    model.fx_spawn_acp = false;
    fx.spawn(.{
        .key = allocateFxSpawnKey(model),
        .argv = argv_buf[0..n],
        .stdin = "",
        .on_line = Effects.lineMsg(.fx_line),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
    return true;
}

/// One-shot official Amp execute mode: `{binary} -x {prompt}`.
/// Prompt is an argv slot (documented `amp -x "query"`; `--execute`
/// is the long form). Empty stdin. Execute mode sends the message,
/// waits until the agent ends its turn, prints its final message,
/// and exits, so the existing non-ACP `handleFxLine` path is safe.
/// Not ACP, not `amp acp`, not acp-proxy, not `--stream-json`, not
/// `--dangerously-allow-all` / `dangerouslyAllowAll`. Caller sets
/// `reply_path` to `.fx` on success; `fx_spawn_acp` stays false.
/// Project cwd reuses `fx_ask_chdir_script` (Native SpawnOptions
/// has no cwd field). Empty binary is a no-op (PATH default is
/// `amp`).
pub fn startAmpExecute(model: *Model, fx: *Effects, session: *const Session, prompt: []const u8) bool {
    const binary = providers.binaryFor(model, .amp);
    if (binary.len == 0) return false;
    const cwd = model.resolveSpawnCwd(session);
    model.setLastSpawnCwd(cwd);
    model.setLastSpawnImagePath("");

    var argv_buf: [16][]const u8 = undefined;
    var n: usize = 0;
    if (cwd.len > 0) {
        argv_buf[n] = "/bin/sh";
        n += 1;
        argv_buf[n] = "-c";
        n += 1;
        argv_buf[n] = fx_ask_chdir_script;
        n += 1;
        argv_buf[n] = "sh";
        n += 1;
        argv_buf[n] = cwd;
        n += 1;
    }
    argv_buf[n] = binary;
    n += 1;
    argv_buf[n] = "-x";
    n += 1;
    argv_buf[n] = prompt;
    n += 1;

    model.fx_spawn_acp = false;
    fx.spawn(.{
        .key = allocateFxSpawnKey(model),
        .argv = argv_buf[0..n],
        .stdin = "",
        .on_line = Effects.lineMsg(.fx_line),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
    return true;
}

/// One-shot official Pi print mode: `{binary} -p {prompt}`. Prompt
/// is an argv slot (documented `pi -p "query"`; `--print` is the
/// long form). Empty stdin. Print mode prints the response and
/// exits, so the existing non-ACP `handleFxLine` path is safe. Not
/// ACP, not acp-proxy, not `--mode json`, not RPC, not `-a` /
/// `--approve` / invented dangerously-* flags. Caller sets
/// `reply_path` to `.fx` on success; `fx_spawn_acp` stays false.
/// Project cwd reuses `fx_ask_chdir_script` (Native SpawnOptions
/// has no cwd field). Empty binary is a no-op (PATH default is
/// `pi`).
pub fn startPiPrint(model: *Model, fx: *Effects, session: *const Session, prompt: []const u8) bool {
    const binary = providers.binaryFor(model, .pi);
    if (binary.len == 0) return false;
    const cwd = model.resolveSpawnCwd(session);
    model.setLastSpawnCwd(cwd);
    model.setLastSpawnImagePath("");

    var argv_buf: [16][]const u8 = undefined;
    var n: usize = 0;
    if (cwd.len > 0) {
        argv_buf[n] = "/bin/sh";
        n += 1;
        argv_buf[n] = "-c";
        n += 1;
        argv_buf[n] = fx_ask_chdir_script;
        n += 1;
        argv_buf[n] = "sh";
        n += 1;
        argv_buf[n] = cwd;
        n += 1;
    }
    argv_buf[n] = binary;
    n += 1;
    argv_buf[n] = "-p";
    n += 1;
    argv_buf[n] = prompt;
    n += 1;

    model.fx_spawn_acp = false;
    fx.spawn(.{
        .key = allocateFxSpawnKey(model),
        .argv = argv_buf[0..n],
        .stdin = "",
        .on_line = Effects.lineMsg(.fx_line),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
    return true;
}

/// A stdout line that is a JSON object with a non-empty `session_id`.
/// Copies the id into `dest` and returns the copied slice.
pub fn takeFxAskSessionId(line: []const u8, dest: []u8) ?[]const u8 {
    const trimmed = std.mem.trim(u8, line, " \t\r\n");
    if (trimmed.len < 2 or trimmed[0] != '{') return null;
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const root = std.json.parseFromSliceLeaky(std.json.Value, arena_state.allocator(), trimmed, .{}) catch return null;
    const obj = switch (root) {
        .object => |o| o,
        else => return null,
    };
    const raw = obj.get("session_id") orelse return null;
    const id = switch (raw) {
        .string => |s| s,
        else => return null,
    };
    if (id.len == 0) return null;
    const take = @min(dest.len, id.len);
    @memcpy(dest[0..take], id[0..take]);
    return dest[0..take];
}

fn testArgvHas(argv: []const []const u8, needle: []const u8) bool {
    for (argv) |arg| {
        if (std.mem.eql(u8, arg, needle)) return true;
    }
    return false;
}

fn testArgvIndex(argv: []const []const u8, needle: []const u8) ?usize {
    for (argv, 0..) |arg, i| {
        if (std.mem.eql(u8, arg, needle)) return i;
    }
    return null;
}

test "cursor + cli_available selects acp-proxy cursor-agent acp" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setSidecarPath("faku");
    const id = model.addSession("cursor thread", .cursor);
    model.cli_available[@intFromEnum(protocol.ProviderId.cursor)] = true;

    startPrompt(&model, &fx, id, "hello cursor");
    try testing.expectEqual(main.ReplyPath.fx, model.reply_path);
    try testing.expect(model.fx_spawn_acp);
    try testing.expectEqual(@as(usize, 0), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());

    const request = fx.pendingSpawnAt(0).?;
    try testing.expectEqual(main.fx_ask_key, request.key);
    try testing.expect(testArgvHas(request.argv, acp_proxy.SUBCOMMAND));
    try testing.expect(testArgvHas(request.argv, "--"));
    try testing.expect(testArgvHas(request.argv, "cursor-agent"));
    try testing.expect(testArgvHas(request.argv, "acp"));
    try testing.expect(!testArgvHas(request.argv, "ask"));
    try testing.expect(!testArgvHas(request.argv, "fx"));
    try testing.expect(!testArgvHas(request.argv, daemon_proxy.SUBCOMMAND));
    const dash = testArgvIndex(request.argv, "--") orelse return error.MissingDash;
    const binary_at = testArgvIndex(request.argv, "cursor-agent") orelse return error.MissingBinary;
    const acp_at = testArgvIndex(request.argv, "acp") orelse return error.MissingAcp;
    try testing.expect(dash < binary_at);
    try testing.expectEqual(binary_at + 1, acp_at);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"method\":\"initialize\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"method\":\"session/new\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"method\":\"session/set_mode\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"method\":\"session/prompt\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "hello cursor") != null);
}

test "opencode + cli_available selects acp-proxy opencode acp" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setSidecarPath("faku");
    const id = model.addSession("opencode thread", .opencode);
    model.cli_available[@intFromEnum(protocol.ProviderId.opencode)] = true;

    startPrompt(&model, &fx, id, "hello opencode");
    try testing.expectEqual(main.ReplyPath.fx, model.reply_path);
    try testing.expect(model.fx_spawn_acp);
    try testing.expectEqual(@as(usize, 0), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());

    const request = fx.pendingSpawnAt(0).?;
    try testing.expectEqual(main.fx_ask_key, request.key);
    try testing.expect(testArgvHas(request.argv, acp_proxy.SUBCOMMAND));
    try testing.expect(testArgvHas(request.argv, "--"));
    try testing.expect(testArgvHas(request.argv, "opencode"));
    try testing.expect(testArgvHas(request.argv, "acp"));
    try testing.expect(!testArgvHas(request.argv, "ask"));
    try testing.expect(!testArgvHas(request.argv, "fx"));
    try testing.expect(!testArgvHas(request.argv, "cursor-agent"));
    try testing.expect(!testArgvHas(request.argv, daemon_proxy.SUBCOMMAND));
    const dash = testArgvIndex(request.argv, "--") orelse return error.MissingDash;
    const binary_at = testArgvIndex(request.argv, "opencode") orelse return error.MissingBinary;
    const acp_at = testArgvIndex(request.argv, "acp") orelse return error.MissingAcp;
    try testing.expect(dash < binary_at);
    try testing.expectEqual(binary_at + 1, acp_at);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"method\":\"initialize\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"method\":\"session/new\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"method\":\"session/set_mode\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"method\":\"session/prompt\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "hello opencode") != null);
}

test "opencode unavailable stays demo" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;
    var model = Model{};
    const id = model.addSession("opencode missing", .opencode);
    startPrompt(&model, &fx, id, "no opencode");
    try testing.expectEqual(main.ReplyPath.demo, model.reply_path);
    try testing.expect(!model.fx_spawn_acp);
    try testing.expectEqual(@as(usize, 1), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
}

test "speaksBareAcp is true for cursor and opencode; speaksAcpStdio also covers grok" {
    const testing = std.testing;
    try testing.expect(protocol.ProviderId.cursor.speaksBareAcp());
    try testing.expect(protocol.ProviderId.opencode.speaksBareAcp());
    try testing.expect(!protocol.ProviderId.fx.speaksBareAcp());
    try testing.expect(!protocol.ProviderId.claude.speaksBareAcp());
    try testing.expect(!protocol.ProviderId.codex.speaksBareAcp());
    try testing.expect(!protocol.ProviderId.amp.speaksBareAcp());
    try testing.expect(!protocol.ProviderId.grok.speaksBareAcp());
    try testing.expect(!protocol.ProviderId.pi.speaksBareAcp());
    try testing.expect(protocol.ProviderId.cursor.speaksAcpStdio());
    try testing.expect(protocol.ProviderId.opencode.speaksAcpStdio());
    try testing.expect(protocol.ProviderId.grok.speaksAcpStdio());
    try testing.expect(!protocol.ProviderId.fx.speaksAcpStdio());
    try testing.expect(!protocol.ProviderId.claude.speaksAcpStdio());
    try testing.expect(!protocol.ProviderId.amp.speaksAcpStdio());
    try testing.expectEqual(@as(usize, 0), protocol.ProviderId.amp.acpTransportArgv().len);
    try testing.expectEqual(@as(usize, 2), protocol.ProviderId.grok.acpTransportArgv().len);
    try testing.expectEqualStrings("agent", protocol.ProviderId.grok.acpTransportArgv()[0]);
    try testing.expectEqualStrings("stdio", protocol.ProviderId.grok.acpTransportArgv()[1]);
}

test "cursor unavailable stays demo" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;
    var model = Model{};
    const cursor_id = model.addSession("cursor missing", .cursor);
    startPrompt(&model, &fx, cursor_id, "no cursor-agent");
    try testing.expectEqual(main.ReplyPath.demo, model.reply_path);
    try testing.expect(!model.fx_spawn_acp);
    try testing.expectEqual(@as(usize, 1), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
}

test "grok + cli_available selects acp-proxy grok agent stdio" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setSidecarPath("faku");
    const id = model.addSession("grok thread", .grok);
    model.cli_available[@intFromEnum(protocol.ProviderId.grok)] = true;

    startPrompt(&model, &fx, id, "hello grok");
    try testing.expectEqual(main.ReplyPath.fx, model.reply_path);
    try testing.expect(model.fx_spawn_acp);
    try testing.expectEqual(@as(usize, 0), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());

    const request = fx.pendingSpawnAt(0).?;
    try testing.expectEqual(main.fx_ask_key, request.key);
    try testing.expect(testArgvHas(request.argv, acp_proxy.SUBCOMMAND));
    try testing.expect(testArgvHas(request.argv, "--"));
    try testing.expect(testArgvHas(request.argv, "grok"));
    try testing.expect(testArgvHas(request.argv, "agent"));
    try testing.expect(testArgvHas(request.argv, "stdio"));
    try testing.expect(!testArgvHas(request.argv, "acp"));
    try testing.expect(!testArgvHas(request.argv, "--always-approve"));
    try testing.expect(!testArgvHas(request.argv, "ask"));
    try testing.expect(!testArgvHas(request.argv, "fx"));
    try testing.expect(!testArgvHas(request.argv, "cursor-agent"));
    try testing.expect(!testArgvHas(request.argv, daemon_proxy.SUBCOMMAND));
    const dash = testArgvIndex(request.argv, "--") orelse return error.MissingDash;
    const binary_at = testArgvIndex(request.argv, "grok") orelse return error.MissingBinary;
    const agent_at = testArgvIndex(request.argv, "agent") orelse return error.MissingAgent;
    const stdio_at = testArgvIndex(request.argv, "stdio") orelse return error.MissingStdio;
    try testing.expect(dash < binary_at);
    try testing.expectEqual(binary_at + 1, agent_at);
    try testing.expectEqual(agent_at + 1, stdio_at);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"method\":\"initialize\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"method\":\"session/new\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"method\":\"session/set_mode\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"method\":\"session/prompt\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "hello grok") != null);
}

test "grok unavailable stays demo" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;
    var model = Model{};
    const id = model.addSession("grok missing", .grok);
    startPrompt(&model, &fx, id, "no grok");
    try testing.expectEqual(main.ReplyPath.demo, model.reply_path);
    try testing.expect(!model.fx_spawn_acp);
    try testing.expectEqual(@as(usize, 1), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
}

test "fx path stays preferred when provider is fx even if cursor is available" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.fx_available = true;
    model.fx_probe_started = true;
    model.setFxPath("fx");
    model.setSidecarPath("faku");
    model.cli_available[@intFromEnum(protocol.ProviderId.cursor)] = true;
    const id = model.addSession("fx first", .fx);

    startPrompt(&model, &fx, id, "keep fx");
    try testing.expectEqual(main.ReplyPath.fx, model.reply_path);
    try testing.expect(model.fx_spawn_acp);
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());
    const request = fx.pendingSpawnAt(0).?;
    try testing.expect(testArgvHas(request.argv, acp_proxy.SUBCOMMAND));
    try testing.expect(testArgvHas(request.argv, "fx"));
    try testing.expect(testArgvHas(request.argv, "acp"));
    try testing.expect(!testArgvHas(request.argv, "cursor-agent"));
    try testing.expect(!testArgvHas(request.argv, "ask"));
}

test "cursor image attach stays demo" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var image_buf: [256]u8 = undefined;
    const image = try std.fmt.bufPrint(&image_buf, ".zig-cache/tmp/{s}/shot.png", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().writeFile(testing.io, .{ .sub_path = image, .data = "png" });

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = testing.io;
    model.setSidecarPath("faku");
    model.cli_available[@intFromEnum(protocol.ProviderId.cursor)] = true;
    const id = model.addSession("cursor image", .cursor);
    model.selected = id;
    model.setDraftImagePath(image);

    startPrompt(&model, &fx, id, "describe this");
    try testing.expectEqual(main.ReplyPath.demo, model.reply_path);
    try testing.expect(!model.fx_spawn_acp);
    try testing.expectEqual(@as(usize, 1), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
}

test "claude + cli_available selects print-mode claude -p --output-format text" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setSidecarPath("faku");
    const id = model.addSession("claude thread", .claude);
    model.cli_available[@intFromEnum(protocol.ProviderId.claude)] = true;

    startPrompt(&model, &fx, id, "hello claude");
    try testing.expectEqual(main.ReplyPath.fx, model.reply_path);
    try testing.expect(!model.fx_spawn_acp);
    try testing.expectEqual(@as(usize, 0), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());

    const request = fx.pendingSpawnAt(0).?;
    try testing.expectEqual(main.fx_ask_key, request.key);
    try testing.expect(testArgvHas(request.argv, "claude"));
    try testing.expect(testArgvHas(request.argv, "-p"));
    try testing.expect(testArgvHas(request.argv, "--output-format"));
    try testing.expect(testArgvHas(request.argv, "text"));
    try testing.expect(testArgvHas(request.argv, "hello claude"));
    try testing.expect(!testArgvHas(request.argv, acp_proxy.SUBCOMMAND));
    try testing.expect(!testArgvHas(request.argv, "acp"));
    try testing.expect(!testArgvHas(request.argv, "agent"));
    try testing.expect(!testArgvHas(request.argv, "stdio"));
    try testing.expect(!testArgvHas(request.argv, "ask"));
    try testing.expect(!testArgvHas(request.argv, "fx"));
    try testing.expect(!testArgvHas(request.argv, "--dangerously-skip-permissions"));
    try testing.expect(!testArgvHas(request.argv, "--always-approve"));
    try testing.expect(!testArgvHas(request.argv, daemon_proxy.SUBCOMMAND));
    try testing.expectEqualStrings("", request.stdin);
    const binary_at = testArgvIndex(request.argv, "claude") orelse return error.MissingBinary;
    const p_at = testArgvIndex(request.argv, "-p") orelse return error.MissingPrint;
    const format_at = testArgvIndex(request.argv, "--output-format") orelse return error.MissingFormat;
    const text_at = testArgvIndex(request.argv, "text") orelse return error.MissingText;
    const prompt_at = testArgvIndex(request.argv, "hello claude") orelse return error.MissingPrompt;
    try testing.expectEqual(binary_at + 1, p_at);
    try testing.expectEqual(p_at + 1, format_at);
    try testing.expectEqual(format_at + 1, text_at);
    try testing.expectEqual(text_at + 1, prompt_at);
}

test "claude unavailable stays demo" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;
    var model = Model{};
    const id = model.addSession("claude missing", .claude);
    startPrompt(&model, &fx, id, "no claude");
    try testing.expectEqual(main.ReplyPath.demo, model.reply_path);
    try testing.expect(!model.fx_spawn_acp);
    try testing.expectEqual(@as(usize, 1), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
}

test "codex + cli_available selects exec-mode codex exec {prompt}" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setSidecarPath("faku");
    const id = model.addSession("codex thread", .codex);
    model.cli_available[@intFromEnum(protocol.ProviderId.codex)] = true;

    startPrompt(&model, &fx, id, "hello codex");
    try testing.expectEqual(main.ReplyPath.fx, model.reply_path);
    try testing.expect(!model.fx_spawn_acp);
    try testing.expectEqual(@as(usize, 0), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());

    const request = fx.pendingSpawnAt(0).?;
    try testing.expectEqual(main.fx_ask_key, request.key);
    try testing.expect(testArgvHas(request.argv, "codex"));
    try testing.expect(testArgvHas(request.argv, "exec"));
    try testing.expect(testArgvHas(request.argv, "hello codex"));
    try testing.expect(!testArgvHas(request.argv, acp_proxy.SUBCOMMAND));
    try testing.expect(!testArgvHas(request.argv, "acp"));
    try testing.expect(!testArgvHas(request.argv, "agent"));
    try testing.expect(!testArgvHas(request.argv, "stdio"));
    try testing.expect(!testArgvHas(request.argv, "ask"));
    try testing.expect(!testArgvHas(request.argv, "fx"));
    try testing.expect(!testArgvHas(request.argv, "-p"));
    try testing.expect(!testArgvHas(request.argv, "--output-format"));
    try testing.expect(!testArgvHas(request.argv, "--full-auto"));
    try testing.expect(!testArgvHas(request.argv, "--sandbox"));
    try testing.expect(!testArgvHas(request.argv, "danger-full-access"));
    try testing.expect(!testArgvHas(request.argv, "--ask-for-approval"));
    try testing.expect(!testArgvHas(request.argv, "never"));
    try testing.expect(!testArgvHas(request.argv, "--dangerously-skip-permissions"));
    try testing.expect(!testArgvHas(request.argv, daemon_proxy.SUBCOMMAND));
    try testing.expectEqualStrings("", request.stdin);
    const binary_at = testArgvIndex(request.argv, "codex") orelse return error.MissingBinary;
    const exec_at = testArgvIndex(request.argv, "exec") orelse return error.MissingExec;
    const prompt_at = testArgvIndex(request.argv, "hello codex") orelse return error.MissingPrompt;
    try testing.expectEqual(binary_at + 1, exec_at);
    try testing.expectEqual(exec_at + 1, prompt_at);
}

test "codex unavailable stays demo" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;
    var model = Model{};
    const id = model.addSession("codex missing", .codex);
    startPrompt(&model, &fx, id, "no codex");
    try testing.expectEqual(main.ReplyPath.demo, model.reply_path);
    try testing.expect(!model.fx_spawn_acp);
    try testing.expectEqual(@as(usize, 1), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
}

test "amp + cli_available selects execute-mode amp -x {prompt}" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setSidecarPath("faku");
    const id = model.addSession("amp thread", .amp);
    model.cli_available[@intFromEnum(protocol.ProviderId.amp)] = true;

    startPrompt(&model, &fx, id, "hello amp");
    try testing.expectEqual(main.ReplyPath.fx, model.reply_path);
    try testing.expect(!model.fx_spawn_acp);
    try testing.expectEqual(@as(usize, 0), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());

    const request = fx.pendingSpawnAt(0).?;
    try testing.expectEqual(main.fx_ask_key, request.key);
    try testing.expect(testArgvHas(request.argv, "amp"));
    try testing.expect(testArgvHas(request.argv, "-x"));
    try testing.expect(testArgvHas(request.argv, "hello amp"));
    try testing.expect(!testArgvHas(request.argv, acp_proxy.SUBCOMMAND));
    try testing.expect(!testArgvHas(request.argv, "acp"));
    try testing.expect(!testArgvHas(request.argv, "agent"));
    try testing.expect(!testArgvHas(request.argv, "stdio"));
    try testing.expect(!testArgvHas(request.argv, "ask"));
    try testing.expect(!testArgvHas(request.argv, "fx"));
    try testing.expect(!testArgvHas(request.argv, "-p"));
    try testing.expect(!testArgvHas(request.argv, "exec"));
    try testing.expect(!testArgvHas(request.argv, "--execute"));
    try testing.expect(!testArgvHas(request.argv, "--stream-json"));
    try testing.expect(!testArgvHas(request.argv, "--dangerously-allow-all"));
    try testing.expect(!testArgvHas(request.argv, "dangerouslyAllowAll"));
    try testing.expect(!testArgvHas(request.argv, "--dangerously-skip-permissions"));
    try testing.expect(!testArgvHas(request.argv, daemon_proxy.SUBCOMMAND));
    try testing.expectEqualStrings("", request.stdin);
    const binary_at = testArgvIndex(request.argv, "amp") orelse return error.MissingBinary;
    const x_at = testArgvIndex(request.argv, "-x") orelse return error.MissingExecute;
    const prompt_at = testArgvIndex(request.argv, "hello amp") orelse return error.MissingPrompt;
    try testing.expectEqual(binary_at + 1, x_at);
    try testing.expectEqual(x_at + 1, prompt_at);
}

test "amp unavailable stays demo" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;
    var model = Model{};
    const id = model.addSession("amp missing", .amp);
    startPrompt(&model, &fx, id, "no amp");
    try testing.expectEqual(main.ReplyPath.demo, model.reply_path);
    try testing.expect(!model.fx_spawn_acp);
    try testing.expectEqual(@as(usize, 1), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
}

test "fx path stays preferred when provider is fx even if amp is available" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.fx_available = true;
    model.fx_probe_started = true;
    model.setFxPath("fx");
    model.setSidecarPath("faku");
    model.cli_available[@intFromEnum(protocol.ProviderId.amp)] = true;
    const id = model.addSession("fx first", .fx);

    startPrompt(&model, &fx, id, "keep fx");
    try testing.expectEqual(main.ReplyPath.fx, model.reply_path);
    try testing.expect(model.fx_spawn_acp);
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());
    const request = fx.pendingSpawnAt(0).?;
    try testing.expect(testArgvHas(request.argv, acp_proxy.SUBCOMMAND));
    try testing.expect(testArgvHas(request.argv, "fx"));
    try testing.expect(testArgvHas(request.argv, "acp"));
    try testing.expect(!testArgvHas(request.argv, "amp"));
    try testing.expect(!testArgvHas(request.argv, "-x"));
    try testing.expect(!testArgvHas(request.argv, "ask"));
}

test "fx session stays demo when fx is missing even if amp is available" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.cli_available[@intFromEnum(protocol.ProviderId.amp)] = true;
    const id = model.addSession("fx missing", .fx);
    startPrompt(&model, &fx, id, "not amp");
    try testing.expectEqual(main.ReplyPath.demo, model.reply_path);
    try testing.expect(!model.fx_spawn_acp);
    try testing.expectEqual(@as(usize, 1), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
}

test "amp image attach stays demo" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var image_buf: [256]u8 = undefined;
    const image = try std.fmt.bufPrint(&image_buf, ".zig-cache/tmp/{s}/amp-shot.png", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().writeFile(testing.io, .{ .sub_path = image, .data = "png" });

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = testing.io;
    model.setSidecarPath("faku");
    model.cli_available[@intFromEnum(protocol.ProviderId.amp)] = true;
    const id = model.addSession("amp image", .amp);
    model.selected = id;
    model.setDraftImagePath(image);

    startPrompt(&model, &fx, id, "describe this");
    try testing.expectEqual(main.ReplyPath.demo, model.reply_path);
    try testing.expect(!model.fx_spawn_acp);
    try testing.expectEqual(@as(usize, 1), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
}

test "amp execute-mode reuses fx_ask_chdir_script when project cwd exists" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/amp-cwd", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(testing.io, project);

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = testing.io;
    const id = model.addSession("amp cwd", .amp);
    model.cli_available[@intFromEnum(protocol.ProviderId.amp)] = true;
    if (model.sessionById(id)) |session| session.setProjectPath(project);

    startPrompt(&model, &fx, id, "in project");
    try testing.expectEqual(main.ReplyPath.fx, model.reply_path);
    try testing.expect(!model.fx_spawn_acp);
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());
    const request = fx.pendingSpawnAt(0).?;
    try testing.expect(testArgvHas(request.argv, "/bin/sh"));
    try testing.expect(testArgvHas(request.argv, "-c"));
    try testing.expect(testArgvHas(request.argv, fx_ask_chdir_script));
    try testing.expect(testArgvHas(request.argv, project));
    const binary_at = testArgvIndex(request.argv, "amp") orelse return error.MissingBinary;
    const x_at = testArgvIndex(request.argv, "-x") orelse return error.MissingExecute;
    const prompt_at = testArgvIndex(request.argv, "in project") orelse return error.MissingPrompt;
    try testing.expect(binary_at > 0);
    try testing.expectEqual(binary_at + 1, x_at);
    try testing.expectEqual(x_at + 1, prompt_at);
    try testing.expectEqualStrings(project, request.argv[binary_at - 1]);
}

test "pi + cli_available selects print-mode pi -p {prompt}" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setSidecarPath("faku");
    const id = model.addSession("pi thread", .pi);
    model.cli_available[@intFromEnum(protocol.ProviderId.pi)] = true;

    startPrompt(&model, &fx, id, "hello pi");
    try testing.expectEqual(main.ReplyPath.fx, model.reply_path);
    try testing.expect(!model.fx_spawn_acp);
    try testing.expectEqual(@as(usize, 0), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());

    const request = fx.pendingSpawnAt(0).?;
    try testing.expectEqual(main.fx_ask_key, request.key);
    try testing.expect(testArgvHas(request.argv, "pi"));
    try testing.expect(testArgvHas(request.argv, "-p"));
    try testing.expect(testArgvHas(request.argv, "hello pi"));
    try testing.expect(!testArgvHas(request.argv, acp_proxy.SUBCOMMAND));
    try testing.expect(!testArgvHas(request.argv, "acp"));
    try testing.expect(!testArgvHas(request.argv, "agent"));
    try testing.expect(!testArgvHas(request.argv, "stdio"));
    try testing.expect(!testArgvHas(request.argv, "ask"));
    try testing.expect(!testArgvHas(request.argv, "fx"));
    try testing.expect(!testArgvHas(request.argv, "-x"));
    try testing.expect(!testArgvHas(request.argv, "exec"));
    try testing.expect(!testArgvHas(request.argv, "--print"));
    try testing.expect(!testArgvHas(request.argv, "--output-format"));
    try testing.expect(!testArgvHas(request.argv, "--mode"));
    try testing.expect(!testArgvHas(request.argv, "json"));
    try testing.expect(!testArgvHas(request.argv, "rpc"));
    try testing.expect(!testArgvHas(request.argv, "-a"));
    try testing.expect(!testArgvHas(request.argv, "--approve"));
    try testing.expect(!testArgvHas(request.argv, "--dangerously-skip-permissions"));
    try testing.expect(!testArgvHas(request.argv, "--dangerously-allow-all"));
    try testing.expect(!testArgvHas(request.argv, daemon_proxy.SUBCOMMAND));
    try testing.expectEqualStrings("", request.stdin);
    const binary_at = testArgvIndex(request.argv, "pi") orelse return error.MissingBinary;
    const p_at = testArgvIndex(request.argv, "-p") orelse return error.MissingPrint;
    const prompt_at = testArgvIndex(request.argv, "hello pi") orelse return error.MissingPrompt;
    try testing.expectEqual(binary_at + 1, p_at);
    try testing.expectEqual(p_at + 1, prompt_at);
}

test "pi unavailable stays demo" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;
    var model = Model{};
    const id = model.addSession("pi missing", .pi);
    startPrompt(&model, &fx, id, "no pi");
    try testing.expectEqual(main.ReplyPath.demo, model.reply_path);
    try testing.expect(!model.fx_spawn_acp);
    try testing.expectEqual(@as(usize, 1), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
}

test "fx path stays preferred when provider is fx even if pi is available" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.fx_available = true;
    model.fx_probe_started = true;
    model.setFxPath("fx");
    model.setSidecarPath("faku");
    model.cli_available[@intFromEnum(protocol.ProviderId.pi)] = true;
    const id = model.addSession("fx first", .fx);

    startPrompt(&model, &fx, id, "keep fx");
    try testing.expectEqual(main.ReplyPath.fx, model.reply_path);
    try testing.expect(model.fx_spawn_acp);
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());
    const request = fx.pendingSpawnAt(0).?;
    try testing.expect(testArgvHas(request.argv, acp_proxy.SUBCOMMAND));
    try testing.expect(testArgvHas(request.argv, "fx"));
    try testing.expect(testArgvHas(request.argv, "acp"));
    try testing.expect(!testArgvHas(request.argv, "pi"));
    try testing.expect(!testArgvHas(request.argv, "-p"));
    try testing.expect(!testArgvHas(request.argv, "ask"));
}

test "fx session stays demo when fx is missing even if pi is available" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.cli_available[@intFromEnum(protocol.ProviderId.pi)] = true;
    const id = model.addSession("fx missing", .fx);
    startPrompt(&model, &fx, id, "not pi");
    try testing.expectEqual(main.ReplyPath.demo, model.reply_path);
    try testing.expect(!model.fx_spawn_acp);
    try testing.expectEqual(@as(usize, 1), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
}

test "pi image attach stays demo" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var image_buf: [256]u8 = undefined;
    const image = try std.fmt.bufPrint(&image_buf, ".zig-cache/tmp/{s}/pi-shot.png", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().writeFile(testing.io, .{ .sub_path = image, .data = "png" });

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = testing.io;
    model.setSidecarPath("faku");
    model.cli_available[@intFromEnum(protocol.ProviderId.pi)] = true;
    const id = model.addSession("pi image", .pi);
    model.selected = id;
    model.setDraftImagePath(image);

    startPrompt(&model, &fx, id, "describe this");
    try testing.expectEqual(main.ReplyPath.demo, model.reply_path);
    try testing.expect(!model.fx_spawn_acp);
    try testing.expectEqual(@as(usize, 1), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
}

test "pi print-mode reuses fx_ask_chdir_script when project cwd exists" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/pi-cwd", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(testing.io, project);

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = testing.io;
    const id = model.addSession("pi cwd", .pi);
    model.cli_available[@intFromEnum(protocol.ProviderId.pi)] = true;
    if (model.sessionById(id)) |session| session.setProjectPath(project);

    startPrompt(&model, &fx, id, "in project");
    try testing.expectEqual(main.ReplyPath.fx, model.reply_path);
    try testing.expect(!model.fx_spawn_acp);
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());
    const request = fx.pendingSpawnAt(0).?;
    try testing.expect(testArgvHas(request.argv, "/bin/sh"));
    try testing.expect(testArgvHas(request.argv, "-c"));
    try testing.expect(testArgvHas(request.argv, fx_ask_chdir_script));
    try testing.expect(testArgvHas(request.argv, project));
    const binary_at = testArgvIndex(request.argv, "pi") orelse return error.MissingBinary;
    const p_at = testArgvIndex(request.argv, "-p") orelse return error.MissingPrint;
    const prompt_at = testArgvIndex(request.argv, "in project") orelse return error.MissingPrompt;
    try testing.expect(binary_at > 0);
    try testing.expectEqual(binary_at + 1, p_at);
    try testing.expectEqual(p_at + 1, prompt_at);
    try testing.expectEqualStrings(project, request.argv[binary_at - 1]);
}

test "fx path stays preferred when provider is fx even if claude is available" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.fx_available = true;
    model.fx_probe_started = true;
    model.setFxPath("fx");
    model.setSidecarPath("faku");
    model.cli_available[@intFromEnum(protocol.ProviderId.claude)] = true;
    const id = model.addSession("fx first", .fx);

    startPrompt(&model, &fx, id, "keep fx");
    try testing.expectEqual(main.ReplyPath.fx, model.reply_path);
    try testing.expect(model.fx_spawn_acp);
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());
    const request = fx.pendingSpawnAt(0).?;
    try testing.expect(testArgvHas(request.argv, acp_proxy.SUBCOMMAND));
    try testing.expect(testArgvHas(request.argv, "fx"));
    try testing.expect(testArgvHas(request.argv, "acp"));
    try testing.expect(!testArgvHas(request.argv, "claude"));
    try testing.expect(!testArgvHas(request.argv, "-p"));
    try testing.expect(!testArgvHas(request.argv, "ask"));
}

test "fx session stays demo when fx is missing even if claude is available" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.cli_available[@intFromEnum(protocol.ProviderId.claude)] = true;
    const id = model.addSession("fx missing", .fx);
    startPrompt(&model, &fx, id, "not claude");
    try testing.expectEqual(main.ReplyPath.demo, model.reply_path);
    try testing.expect(!model.fx_spawn_acp);
    try testing.expectEqual(@as(usize, 1), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
}

test "claude image attach stays demo" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var image_buf: [256]u8 = undefined;
    const image = try std.fmt.bufPrint(&image_buf, ".zig-cache/tmp/{s}/claude-shot.png", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().writeFile(testing.io, .{ .sub_path = image, .data = "png" });

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = testing.io;
    model.setSidecarPath("faku");
    model.cli_available[@intFromEnum(protocol.ProviderId.claude)] = true;
    const id = model.addSession("claude image", .claude);
    model.selected = id;
    model.setDraftImagePath(image);

    startPrompt(&model, &fx, id, "describe this");
    try testing.expectEqual(main.ReplyPath.demo, model.reply_path);
    try testing.expect(!model.fx_spawn_acp);
    try testing.expectEqual(@as(usize, 1), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
}

test "claude print-mode reuses fx_ask_chdir_script when project cwd exists" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/claude-cwd", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(testing.io, project);

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = testing.io;
    const id = model.addSession("claude cwd", .claude);
    model.cli_available[@intFromEnum(protocol.ProviderId.claude)] = true;
    if (model.sessionById(id)) |session| session.setProjectPath(project);

    startPrompt(&model, &fx, id, "in project");
    try testing.expectEqual(main.ReplyPath.fx, model.reply_path);
    try testing.expect(!model.fx_spawn_acp);
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());
    const request = fx.pendingSpawnAt(0).?;
    try testing.expect(testArgvHas(request.argv, "/bin/sh"));
    try testing.expect(testArgvHas(request.argv, "-c"));
    try testing.expect(testArgvHas(request.argv, fx_ask_chdir_script));
    try testing.expect(testArgvHas(request.argv, project));
    const binary_at = testArgvIndex(request.argv, "claude") orelse return error.MissingBinary;
    const p_at = testArgvIndex(request.argv, "-p") orelse return error.MissingPrint;
    try testing.expect(binary_at > 0);
    try testing.expectEqual(binary_at + 1, p_at);
    try testing.expectEqualStrings(project, request.argv[binary_at - 1]);
}

test "fx path stays preferred when provider is fx even if codex is available" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.fx_available = true;
    model.fx_probe_started = true;
    model.setFxPath("fx");
    model.setSidecarPath("faku");
    model.cli_available[@intFromEnum(protocol.ProviderId.codex)] = true;
    const id = model.addSession("fx first", .fx);

    startPrompt(&model, &fx, id, "keep fx");
    try testing.expectEqual(main.ReplyPath.fx, model.reply_path);
    try testing.expect(model.fx_spawn_acp);
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());
    const request = fx.pendingSpawnAt(0).?;
    try testing.expect(testArgvHas(request.argv, acp_proxy.SUBCOMMAND));
    try testing.expect(testArgvHas(request.argv, "fx"));
    try testing.expect(testArgvHas(request.argv, "acp"));
    try testing.expect(!testArgvHas(request.argv, "codex"));
    try testing.expect(!testArgvHas(request.argv, "exec"));
    try testing.expect(!testArgvHas(request.argv, "ask"));
}

test "fx session stays demo when fx is missing even if codex is available" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.cli_available[@intFromEnum(protocol.ProviderId.codex)] = true;
    const id = model.addSession("fx missing", .fx);
    startPrompt(&model, &fx, id, "not codex");
    try testing.expectEqual(main.ReplyPath.demo, model.reply_path);
    try testing.expect(!model.fx_spawn_acp);
    try testing.expectEqual(@as(usize, 1), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
}

test "codex image attach stays demo" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var image_buf: [256]u8 = undefined;
    const image = try std.fmt.bufPrint(&image_buf, ".zig-cache/tmp/{s}/codex-shot.png", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().writeFile(testing.io, .{ .sub_path = image, .data = "png" });

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = testing.io;
    model.setSidecarPath("faku");
    model.cli_available[@intFromEnum(protocol.ProviderId.codex)] = true;
    const id = model.addSession("codex image", .codex);
    model.selected = id;
    model.setDraftImagePath(image);

    startPrompt(&model, &fx, id, "describe this");
    try testing.expectEqual(main.ReplyPath.demo, model.reply_path);
    try testing.expect(!model.fx_spawn_acp);
    try testing.expectEqual(@as(usize, 1), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
}

test "codex exec reuses fx_ask_chdir_script when project cwd exists" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/codex-cwd", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(testing.io, project);

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = testing.io;
    const id = model.addSession("codex cwd", .codex);
    model.cli_available[@intFromEnum(protocol.ProviderId.codex)] = true;
    if (model.sessionById(id)) |session| session.setProjectPath(project);

    startPrompt(&model, &fx, id, "in project");
    try testing.expectEqual(main.ReplyPath.fx, model.reply_path);
    try testing.expect(!model.fx_spawn_acp);
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());
    const request = fx.pendingSpawnAt(0).?;
    try testing.expect(testArgvHas(request.argv, "/bin/sh"));
    try testing.expect(testArgvHas(request.argv, "-c"));
    try testing.expect(testArgvHas(request.argv, fx_ask_chdir_script));
    try testing.expect(testArgvHas(request.argv, project));
    const binary_at = testArgvIndex(request.argv, "codex") orelse return error.MissingBinary;
    const exec_at = testArgvIndex(request.argv, "exec") orelse return error.MissingExec;
    const prompt_at = testArgvIndex(request.argv, "in project") orelse return error.MissingPrompt;
    try testing.expect(binary_at > 0);
    try testing.expectEqual(binary_at + 1, exec_at);
    try testing.expectEqual(exec_at + 1, prompt_at);
    try testing.expectEqualStrings(project, request.argv[binary_at - 1]);
}

test "grok image attach stays demo" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var image_buf: [256]u8 = undefined;
    const image = try std.fmt.bufPrint(&image_buf, ".zig-cache/tmp/{s}/grok-shot.png", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().writeFile(testing.io, .{ .sub_path = image, .data = "png" });

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = testing.io;
    model.setSidecarPath("faku");
    model.cli_available[@intFromEnum(protocol.ProviderId.grok)] = true;
    const id = model.addSession("grok image", .grok);
    model.selected = id;
    model.setDraftImagePath(image);

    startPrompt(&model, &fx, id, "describe this");
    try testing.expectEqual(main.ReplyPath.demo, model.reply_path);
    try testing.expect(!model.fx_spawn_acp);
    try testing.expectEqual(@as(usize, 1), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
}
