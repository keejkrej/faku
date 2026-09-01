//! Prompt-start and provider-spawn helpers.
//!
//! `startPrompt` path selection (daemon / fx acp / fx ask / probed
//! ACP stdio via acp-proxy / Claude print-mode / Codex exec / Amp
//! execute-mode / Pi json-mode / demo), StartOptions mapping, and
//! `takeFxAskSessionId` live here. Stream lifecycle lives in
//! `stream.zig`. Line handlers live in `lines.zig`.
//!
//! Non-fx live Send this cut: `ProviderId.speaksAcpStdio` (cursor /
//! opencode bare `acp`, grok `agent stdio`) when
//! `providers.isAvailable`. Same one-shot `faku acp-proxy -- {binary}
//! …transport…` as fx. `reply_path` stays `.fx` so ACP stream parsing
//! (`fx_spawn_acp` / `fx_line` / `fx_exit`) is unchanged. After that,
//! Available Claude is one-shot `{binary} -p --output-format
//! stream-json --verbose --include-partial-messages
//! --forward-subagent-text {prompt}`
//! (empty stdin, not ACP, not acp-proxy), with documented `--resume
//! {fx_session_id}` as two argv slots after `--forward-subagent-text`
//! when that field is non-empty (first Send and Fork omit both; not
//! `--continue`), and with the documented image path inside that
//! single `-p` prompt when a composer image exists
//! (code.claude.com/docs/en/common-workflows "Work with images":
//! `Analyze this image: {path}` then the user prompt). There is no
//! `--image` flag (code.claude.com/docs/en/cli-reference).
//! `fx_spawn_claude_json` routes stdout through the Claude JSON
//! parser in `lines.zig` (live `stream_event` / `text_delta`, not a
//! prose dump of raw NDJSON). Available Codex is one-shot `{binary}
//! exec {prompt}` (empty stdin, not ACP, not acp-proxy), with
//! documented `--image {path}` after the prompt when a composer
//! image exists. Available Amp is one-shot `{binary} -x {prompt}`
//! (empty stdin, not ACP, not acp-proxy; `--execute` is the long
//! form), with a documented `@{path}` mention inside that single `-x`
//! prompt when a composer image exists. There is no `--image` flag.
//! Available Pi is one-shot `{binary} --mode json {prompt}` (empty
//! stdin, not ACP, not acp-proxy, not `--mode rpc`), with documented
//! `@{path}` after `--mode json` when a composer image exists
//! (`pi --mode json @screenshot.png "What's in this image?"`).
//! `reply_path` stays `.fx` with `fx_spawn_acp = false`. Pi sets
//! `fx_spawn_pi_json = true` so stdout lines use the Pi JSON parser
//! in `lines.zig` (live `text_delta`, not prose / raw JSON dump).
//! Composer image attach on cursor / opencode / grok uses official
//! ACP v1 image content blocks (base64 + mimeType) on the one-shot
//! acp-proxy `session/prompt`. fx still uses `fx ask --image` (no
//! ACP image blocks). Overflow / missing / unknown type fail closed
//! to demo.

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
const environment_summary = @import("environment_summary.zig");

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
    model.fx_spawn_pi_json = false;
    model.fx_spawn_claude_json = false;
    environment_summary.clearDismissedSubagentIds(model);
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
        // Official ACP v1 image content blocks on session/prompt when
        // a composer image is attached (non-fx only). Missing /
        // unreadable / unknown type / overflow fail closed to demo.
        // fx never takes this branch (not speaksAcpStdio).
        const binary = providers.binaryFor(model, session.provider);
        // Reuse fx spawn keys / fx_line / fx_exit / reply_path=.fx
        // so handleAcpLine keeps working. Not a new ReplyPath alias.
        model.reply_path = .fx;
        if (startAcpProxy(model, fx, session, binary, text)) return;
    }
    if (session.provider == .claude and providers.isAvailable(model, .claude)) {
        // Claude Code is not ACP. Official print-mode streaming is
        // one-shot `claude -p --output-format stream-json --verbose
        // --include-partial-messages --forward-subagent-text`
        // (code.claude.com/docs/en/headless). Later Sends pass
        // documented `--resume {fx_session_id}` when that field is
        // non-empty; first Send and Fork omit it. Not `--continue`.
        // `--forward-subagent-text` is always its own argv slot after
        // `--include-partial-messages` (CLI reference; requires `-p`
        // and stream-json). Documented image attach
        // is the filesystem path inside that single `-p` prompt
        // (`Analyze this image: {path}` then the user prompt;
        // code.claude.com/docs/en/common-workflows). There is no
        // `--image` flag. Join overflow fails closed to demo rather
        // than truncating. Unavailable Claude stays demo.
        if (startClaudePrint(model, fx, session, text)) {
            model.reply_path = .fx;
            return;
        }
    }
    if (session.provider == .codex and providers.isAvailable(model, .codex)) {
        // Codex is not ACP. Official non-interactive mode is one-shot
        // `codex exec {prompt}`. Documented `--image {path}` after the
        // prompt when a composer image exists (`--image` is clap
        // `num_args = 1..`, so a following prompt would be eaten as
        // another image path). Unavailable Codex stays demo.
        if (startCodexExec(model, fx, session, text)) {
            model.reply_path = .fx;
            return;
        }
    }
    if (session.provider == .amp and providers.isAvailable(model, .amp)) {
        // Amp is not ACP. Official execute mode is one-shot
        // `amp -x {prompt}` (`--execute` is the long form). Documented
        // image attach is an `@path` mention inside that single `-x`
        // prompt (`amp -x '@{path}\n{prompt}'`). There is no `--image`
        // flag. Unavailable Amp stays demo.
        if (startAmpExecute(model, fx, session, text)) {
            model.reply_path = .fx;
            return;
        }
    }
    if (session.provider == .pi and providers.isAvailable(model, .pi)) {
        // Pi is not ACP. Official JSON event-stream mode is one-shot
        // `pi --mode json {prompt}`. Documented `@{path}` after
        // `--mode json` when a composer image exists
        // (`pi --mode json @screenshot.png "What's in this image?"`).
        // There is no `--image` flag. Unavailable Pi stays demo.
        if (startPiJson(model, fx, session, text)) {
            model.reply_path = .fx;
            return;
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
///
/// Non-fx ACP stdio may attach one official image content block
/// when the composer draft has an image path. fx never gets image
/// blocks here (callers route fx images to `fx ask --image`).
/// Missing / unreadable / unknown type / overflow return false so
/// `startPrompt` fail-closes to demo.
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

    var stdin_buf: [acp.stdin_cap]u8 = undefined;
    var image_raw: [acp.max_image_bytes]u8 = undefined;
    var image: ?acp.ImageContent = null;
    // fx REJECTS image blocks. Only probed ACP stdio (cursor /
    // opencode / grok) may attach ImageContent on session/prompt.
    const image_path = if (session.provider.speaksAcpStdio()) model.draftImagePath() else "";
    if (image_path.len > 0) {
        const io = model.store_io orelse return false;
        const mime = acp.mimeTypeForImagePath(image_path) orelse return false;
        const bytes = acp.readImageBytes(io, image_path, &image_raw) orelse return false;
        image = .{ .bytes = bytes, .mime_type = mime };
    }
    const stdin = acp.writeTurnStdin(&stdin_buf, .{
        .cwd = cwd,
        .resume_id = resume_id,
        .prompt = prompt,
        .model = model_id,
        .access_mode = session.accessMode(),
        .image = image,
    }) catch return false;
    if (image_path.len > 0) model.setLastSpawnImagePath(image_path);

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

/// Documented Claude image recipe from
/// https://code.claude.com/docs/en/common-workflows "Work with images":
/// `Provide an image path to Claude. E.g., "Analyze this image: /path/to/your/image.png"`.
/// CLI reference (https://code.claude.com/docs/en/cli-reference) has
/// no `--image` / `-i` flag. The path lives inside the single `-p`
/// prompt argv, not a sibling slot.
const claude_image_prompt_prefix = "Analyze this image: ";

/// One-shot official Claude Code print-mode stream-json:
/// `{binary} -p --output-format stream-json --verbose
/// --include-partial-messages --forward-subagent-text {prompt}`,
/// or the same flags with `'Analyze this image: {path}\n{prompt}'`
/// when a composer image exists. Prompt is an argv slot after the
/// flags (documented `claude -p "query"`; streaming recipe at
/// code.claude.com/docs/en/headless). `--include-partial-messages`
/// requires `--print` (`-p`) and `--output-format stream-json`
/// (code.claude.com/docs/en/cli-reference). `--forward-subagent-text`
/// is always its own argv slot after `--include-partial-messages`
/// and before optional `--resume` / the prompt (same CLI page;
/// requires `-p` and stream-json; prefer the argv flag over
/// `CLAUDE_CODE_FORWARD_SUBAGENT_TEXT`). When
/// `session.fxSessionId()` is non-empty, documented `--resume {id}`
/// is two argv slots after `--forward-subagent-text` and before
/// the prompt (code.claude.com/docs/en/headless "Continue
/// conversations"; CLI `--resume` / `-r`). Empty id omits both
/// slots — never a bare `--resume`. Not `--continue` / `-c` (that
/// is most-recent in the current directory, and would mix Faku
/// sessions). Composer images are documented as a path inside that
/// prompt (code.claude.com/docs/en/common-workflows "Work with
/// images"); there is no `--image` / `-i` flag. The join is a stack
/// buffer sized for the documented prefix + `max_project_path` +
/// newline + `max_draft` (same caps as the draft image / prompt
/// stores). Overflow returns false so Send fails closed to demo
/// rather than truncating into a wrong command. Empty stdin.
/// Stream-json stdout is NDJSON; `fx_spawn_claude_json` routes it
/// through the Claude parser (live `stream_event` /
/// `event.delta.type == text_delta`, not a prose dump). Non-empty
/// `parent_tool_use_id` is subagent traffic (not main-turn prose).
/// Forwarded `parent_tool_use_id` text (`text_delta` / assistant
/// text) fills a bounded 512KB last-window on that live Subagent
/// (same size/policy as Monitor; not `appendToTurn`).
/// `tool_use` with `name` `Monitor` fills live Monitor Background
/// (not Bash / Agent / `parent_tool_use_id`). Matching user
/// `tool_result` fills a bounded 512KB last-window log on that live
/// row (newlines kept; CSI stripped for display; Environment
/// Summary stays a one-line preview; not `appendToTurn`; does not
/// register a new Monitor).
/// Not ACP, not `claude acp`, not `--input-format stream-json`, not
/// `--mode rpc`, not `--bare`, not permissions bypass, not
/// acp-proxy. Caller sets `reply_path` to `.fx` on success;
/// `fx_spawn_acp` stays false. Project cwd reuses
/// `fx_ask_chdir_script` (Native SpawnOptions has no cwd field).
/// Resume id is its own argv slot — never interpolated into the
/// chdir `-c` script. Empty binary is a no-op (PATH default is
/// `claude`).
pub fn startClaudePrint(model: *Model, fx: *Effects, session: *const Session, prompt: []const u8) bool {
    const binary = providers.binaryFor(model, .claude);
    if (binary.len == 0) return false;
    const cwd = model.resolveSpawnCwd(session);
    const resume_id = session.fxSessionId();
    const image_path = model.resolveSpawnImage();

    var print_prompt_buf: [claude_image_prompt_prefix.len + main.max_project_path + 1 + main.max_draft]u8 = undefined;
    const print_prompt = if (image_path.len > 0)
        std.fmt.bufPrint(
            &print_prompt_buf,
            claude_image_prompt_prefix ++ "{s}\n{s}",
            .{ image_path, prompt },
        ) catch return false
    else
        prompt;

    model.setLastSpawnCwd(cwd);
    model.setLastSpawnImagePath(image_path);

    // chdir (5) + binary + -p + --output-format + stream-json +
    // --verbose + --include-partial-messages +
    // --forward-subagent-text + --resume + id + prompt = 15.
    // Keep headroom rather than truncating.
    var argv_buf: [18][]const u8 = undefined;
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
    argv_buf[n] = "stream-json";
    n += 1;
    argv_buf[n] = "--verbose";
    n += 1;
    argv_buf[n] = "--include-partial-messages";
    n += 1;
    argv_buf[n] = "--forward-subagent-text";
    n += 1;
    if (resume_id.len > 0) {
        argv_buf[n] = "--resume";
        n += 1;
        argv_buf[n] = resume_id;
        n += 1;
    }
    argv_buf[n] = print_prompt;
    n += 1;

    model.fx_spawn_acp = false;
    model.fx_spawn_claude_json = true;
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
/// `{binary} exec {prompt}`, or `{binary} exec {prompt} --image {path}`
/// when a composer image exists. Prompt is an argv slot (documented
/// `codex exec [OPTIONS] [PROMPT]`). `--image` / `-i` is documented
/// on `codex exec` (clap `num_args = 1..`); this cut uses the long
/// form and one path. The flag must follow the positional prompt —
/// `codex exec --image {path} {prompt}` makes clap treat the prompt
/// as another image path. Same argv-slot pattern as `fx ask --image`
/// (flag then path), not path-in-prompt. Empty stdin. Progress
/// streams to stderr; the final agent message prints to stdout, so
/// the existing non-ACP `handleFxLine` path is safe. Not ACP, not
/// acp-proxy, not stream-json, not `--full-auto` / sandbox bypass /
/// `--ask-for-approval never`. Caller sets `reply_path` to `.fx` on
/// success; `fx_spawn_acp` stays false. Project cwd reuses
/// `fx_ask_chdir_script` (Native SpawnOptions has no cwd field).
/// Empty binary is a no-op (PATH default is `codex`).
pub fn startCodexExec(model: *Model, fx: *Effects, session: *const Session, prompt: []const u8) bool {
    const binary = providers.binaryFor(model, .codex);
    if (binary.len == 0) return false;
    const cwd = model.resolveSpawnCwd(session);
    const image_path = model.resolveSpawnImage();
    model.setLastSpawnCwd(cwd);
    model.setLastSpawnImagePath(image_path);

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
    if (image_path.len > 0) {
        argv_buf[n] = "--image";
        n += 1;
        argv_buf[n] = image_path;
        n += 1;
    }

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

/// One-shot official Amp execute mode: `{binary} -x {prompt}`, or
/// `{binary} -x '@{image_path}\n{prompt}'` when a composer image
/// exists. Prompt is an argv slot (documented `amp -x "query"`;
/// `--execute` is the long form). Composer images are documented
/// `@path` mentions by file path (ampcode.com/docs/prompting
/// "Attaching Images"; ampcode.com/news/cli-image-support); there
/// is no `--image` / `-i` flag. The mention lives inside the single
/// `-x` prompt argv, not as a separate undocumented slot. The `@` +
/// path is a stack buffer sized for `@` + `max_project_path` (same
/// cap as the draft image store). Empty stdin. Execute mode sends
/// the message, waits until the agent ends its turn, prints its
/// final message, and exits, so the existing non-ACP `handleFxLine`
/// path is safe. Not ACP, not `amp acp`, not acp-proxy, not
/// `--stream-json`, not `--dangerously-allow-all` /
/// `dangerouslyAllowAll`. Caller sets `reply_path` to `.fx` on
/// success; `fx_spawn_acp` stays false. Project cwd reuses
/// `fx_ask_chdir_script` (Native SpawnOptions has no cwd field).
/// Empty binary is a no-op (PATH default is `amp`).
pub fn startAmpExecute(model: *Model, fx: *Effects, session: *const Session, prompt: []const u8) bool {
    const binary = providers.binaryFor(model, .amp);
    if (binary.len == 0) return false;
    const cwd = model.resolveSpawnCwd(session);
    const image_path = model.resolveSpawnImage();
    model.setLastSpawnCwd(cwd);
    model.setLastSpawnImagePath(image_path);

    var at_path_buf: [1 + main.max_project_path]u8 = undefined;
    const at_path = if (image_path.len > 0)
        std.fmt.bufPrint(&at_path_buf, "@{s}", .{image_path}) catch ""
    else
        "";

    var execute_prompt_buf: [1 + main.max_project_path + 1 + main.max_draft]u8 = undefined;
    const execute_prompt = if (at_path.len > 0)
        std.fmt.bufPrint(&execute_prompt_buf, "{s}\n{s}", .{ at_path, prompt }) catch prompt
    else
        prompt;

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
    argv_buf[n] = execute_prompt;
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

/// Documented Pi file/image argv slot: `@` + path. Buffer is sized
/// for `@` + `max_project_path` (same cap as the draft image store).
/// Overflow returns null so Send fails closed to demo rather than
/// dropping the `@` or truncating the path.
fn formatPiAtPath(buf: []u8, image_path: []const u8) ?[]const u8 {
    if (image_path.len == 0) return null;
    return std.fmt.bufPrint(buf, "@{s}", .{image_path}) catch null;
}

/// One-shot official Pi JSON event-stream mode:
/// `{binary} --mode json {prompt}`, or
/// `{binary} --mode json @{image_path} {prompt}` when a composer
/// image exists. Prompt is an argv slot (documented
/// `pi --mode json "Your prompt"`). File/image args are documented
/// `@path` prefixes
/// (`pi --mode json @screenshot.png "What's in this image?"`); there
/// is no `--image` flag. The `@` + path slot is a stack buffer sized
/// for `@` + `max_project_path` (same cap as the draft image store).
/// Overflow returns false so Send fails closed to demo. Empty stdin.
/// JSON mode emits session events as JSON lines; `fx_spawn_pi_json`
/// routes stdout through the Pi parser (live `text_delta`, not a
/// prose dump of raw JSON). Not ACP, not acp-proxy, not `--mode rpc`,
/// not `-p` / `--print`, not `-a` / `--approve` / invented
/// dangerously-* flags. Caller sets `reply_path` to `.fx` on success;
/// `fx_spawn_acp` stays false. Project cwd reuses
/// `fx_ask_chdir_script` (Native SpawnOptions has no cwd field).
/// Empty binary is a no-op (PATH default is `pi`).
pub fn startPiJson(model: *Model, fx: *Effects, session: *const Session, prompt: []const u8) bool {
    const binary = providers.binaryFor(model, .pi);
    if (binary.len == 0) return false;
    const cwd = model.resolveSpawnCwd(session);
    const image_path = model.resolveSpawnImage();

    var at_path_buf: [1 + main.max_project_path]u8 = undefined;
    const at_path = if (image_path.len > 0)
        formatPiAtPath(&at_path_buf, image_path) orelse return false
    else
        "";

    model.setLastSpawnCwd(cwd);
    model.setLastSpawnImagePath(image_path);

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
    argv_buf[n] = "--mode";
    n += 1;
    argv_buf[n] = "json";
    n += 1;
    if (at_path.len > 0) {
        argv_buf[n] = at_path;
        n += 1;
    }
    argv_buf[n] = prompt;
    n += 1;

    model.fx_spawn_acp = false;
    model.fx_spawn_pi_json = true;
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

test "cursor image attach uses ACP image content block" {
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
    try testing.expectEqual(main.ReplyPath.fx, model.reply_path);
    try testing.expect(model.fx_spawn_acp);
    try testing.expectEqual(@as(usize, 0), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());
    try testing.expectEqualStrings(image, model.lastSpawnImagePath());

    const request = fx.pendingSpawnAt(0).?;
    try testing.expect(testArgvHas(request.argv, acp_proxy.SUBCOMMAND));
    try testing.expect(testArgvHas(request.argv, "cursor-agent"));
    try testing.expect(testArgvHas(request.argv, "acp"));
    try testing.expect(!testArgvHas(request.argv, "ask"));
    try testing.expect(!testArgvHas(request.argv, "--image"));
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"method\":\"session/prompt\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"type\":\"text\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "describe this") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"type\":\"image\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"data\":\"cG5n\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"mimeType\":\"image/png\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"uri\"") == null);
}

test "cursor image attach unknown type stays demo" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var image_buf: [256]u8 = undefined;
    const image = try std.fmt.bufPrint(&image_buf, ".zig-cache/tmp/{s}/shot.bmp", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().writeFile(testing.io, .{ .sub_path = image, .data = "bmp" });

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = testing.io;
    model.setSidecarPath("faku");
    model.cli_available[@intFromEnum(protocol.ProviderId.cursor)] = true;
    const id = model.addSession("cursor bmp", .cursor);
    model.selected = id;
    model.setDraftImagePath(image);

    startPrompt(&model, &fx, id, "describe this");
    try testing.expectEqual(main.ReplyPath.demo, model.reply_path);
    try testing.expect(!model.fx_spawn_acp);
    try testing.expectEqual(@as(usize, 1), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
}

test "cursor image attach overflow stays demo" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var image_buf: [256]u8 = undefined;
    const image = try std.fmt.bufPrint(&image_buf, ".zig-cache/tmp/{s}/over.png", .{tmp.sub_path[0..]});
    var over: [acp.max_image_bytes + 1]u8 = undefined;
    @memset(&over, 'A');
    try std.Io.Dir.cwd().writeFile(testing.io, .{ .sub_path = image, .data = &over });

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = testing.io;
    model.setSidecarPath("faku");
    model.cli_available[@intFromEnum(protocol.ProviderId.cursor)] = true;
    const id = model.addSession("cursor overflow", .cursor);
    model.selected = id;
    model.setDraftImagePath(image);

    startPrompt(&model, &fx, id, "describe this");
    try testing.expectEqual(main.ReplyPath.demo, model.reply_path);
    try testing.expect(!model.fx_spawn_acp);
    try testing.expectEqual(@as(usize, 1), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
}

test "cursor image attach missing file stays demo" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = testing.io;
    model.setSidecarPath("faku");
    model.cli_available[@intFromEnum(protocol.ProviderId.cursor)] = true;
    const id = model.addSession("cursor missing image", .cursor);
    model.selected = id;
    model.setDraftImagePath(".zig-cache/tmp/faku-acp-image-missing.png");

    startPrompt(&model, &fx, id, "describe this");
    try testing.expectEqual(main.ReplyPath.demo, model.reply_path);
    try testing.expect(!model.fx_spawn_acp);
    try testing.expectEqual(@as(usize, 1), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
}

test "claude + cli_available selects print-mode claude -p --output-format stream-json" {
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
    try testing.expect(model.fx_spawn_claude_json);
    try testing.expect(!model.fx_spawn_pi_json);
    try testing.expectEqual(@as(usize, 0), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());

    const request = fx.pendingSpawnAt(0).?;
    try testing.expectEqual(main.fx_ask_key, request.key);
    try testing.expect(testArgvHas(request.argv, "claude"));
    try testing.expect(testArgvHas(request.argv, "-p"));
    try testing.expect(testArgvHas(request.argv, "--output-format"));
    try testing.expect(testArgvHas(request.argv, "stream-json"));
    try testing.expect(testArgvHas(request.argv, "--verbose"));
    try testing.expect(testArgvHas(request.argv, "--include-partial-messages"));
    try testing.expect(testArgvHas(request.argv, "--forward-subagent-text"));
    try testing.expect(testArgvHas(request.argv, "hello claude"));
    try testing.expect(!testArgvHas(request.argv, "text"));
    try testing.expect(!testArgvHas(request.argv, acp_proxy.SUBCOMMAND));
    try testing.expect(!testArgvHas(request.argv, "acp"));
    try testing.expect(!testArgvHas(request.argv, "agent"));
    try testing.expect(!testArgvHas(request.argv, "stdio"));
    try testing.expect(!testArgvHas(request.argv, "ask"));
    try testing.expect(!testArgvHas(request.argv, "fx"));
    try testing.expect(!testArgvHas(request.argv, "--dangerously-skip-permissions"));
    try testing.expect(!testArgvHas(request.argv, "--always-approve"));
    try testing.expect(!testArgvHas(request.argv, "--image"));
    try testing.expect(!testArgvHas(request.argv, "--input-format"));
    try testing.expect(!testArgvHas(request.argv, "--continue"));
    try testing.expect(!testArgvHas(request.argv, "--resume"));
    try testing.expect(!testArgvHas(request.argv, "--bare"));
    try testing.expect(!testArgvHas(request.argv, "--allowedTools"));
    try testing.expect(!testArgvHas(request.argv, "--permission-mode"));
    try testing.expect(!testArgvHas(request.argv, daemon_proxy.SUBCOMMAND));
    try testing.expectEqualStrings("", request.stdin);
    try testing.expectEqualStrings("", model.lastSpawnImagePath());
    const binary_at = testArgvIndex(request.argv, "claude") orelse return error.MissingBinary;
    const p_at = testArgvIndex(request.argv, "-p") orelse return error.MissingPrint;
    const format_at = testArgvIndex(request.argv, "--output-format") orelse return error.MissingFormat;
    const stream_at = testArgvIndex(request.argv, "stream-json") orelse return error.MissingStreamJson;
    const verbose_at = testArgvIndex(request.argv, "--verbose") orelse return error.MissingVerbose;
    const partial_at = testArgvIndex(request.argv, "--include-partial-messages") orelse return error.MissingPartial;
    const forward_at = testArgvIndex(request.argv, "--forward-subagent-text") orelse return error.MissingForwardSubagent;
    const prompt_at = testArgvIndex(request.argv, "hello claude") orelse return error.MissingPrompt;
    try testing.expectEqual(binary_at + 1, p_at);
    try testing.expectEqual(p_at + 1, format_at);
    try testing.expectEqual(format_at + 1, stream_at);
    try testing.expectEqual(stream_at + 1, verbose_at);
    try testing.expectEqual(verbose_at + 1, partial_at);
    try testing.expectEqual(partial_at + 1, forward_at);
    try testing.expectEqual(forward_at + 1, prompt_at);
}

test "claude + stored fx_session_id resumes with --resume {id}" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setSidecarPath("faku");
    const id = model.addSession("claude resume", .claude);
    model.cli_available[@intFromEnum(protocol.ProviderId.claude)] = true;
    if (model.sessionById(id)) |session| session.setFxSessionId("claude-sess-resume-1");

    startPrompt(&model, &fx, id, "continue that review");
    try testing.expectEqual(main.ReplyPath.fx, model.reply_path);
    try testing.expect(!model.fx_spawn_acp);
    try testing.expect(model.fx_spawn_claude_json);
    try testing.expect(!model.fx_spawn_pi_json);
    try testing.expectEqual(@as(usize, 0), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());

    const request = fx.pendingSpawnAt(0).?;
    try testing.expectEqual(main.fx_ask_key, request.key);
    try testing.expect(testArgvHas(request.argv, "claude"));
    try testing.expect(testArgvHas(request.argv, "-p"));
    try testing.expect(testArgvHas(request.argv, "--output-format"));
    try testing.expect(testArgvHas(request.argv, "stream-json"));
    try testing.expect(testArgvHas(request.argv, "--verbose"));
    try testing.expect(testArgvHas(request.argv, "--include-partial-messages"));
    try testing.expect(testArgvHas(request.argv, "--forward-subagent-text"));
    try testing.expect(testArgvHas(request.argv, "--resume"));
    try testing.expect(testArgvHas(request.argv, "claude-sess-resume-1"));
    try testing.expect(testArgvHas(request.argv, "continue that review"));
    try testing.expect(!testArgvHas(request.argv, "text"));
    try testing.expect(!testArgvHas(request.argv, acp_proxy.SUBCOMMAND));
    try testing.expect(!testArgvHas(request.argv, "acp"));
    try testing.expect(!testArgvHas(request.argv, "agent"));
    try testing.expect(!testArgvHas(request.argv, "stdio"));
    try testing.expect(!testArgvHas(request.argv, "ask"));
    try testing.expect(!testArgvHas(request.argv, "fx"));
    try testing.expect(!testArgvHas(request.argv, "--dangerously-skip-permissions"));
    try testing.expect(!testArgvHas(request.argv, "--always-approve"));
    try testing.expect(!testArgvHas(request.argv, "--image"));
    try testing.expect(!testArgvHas(request.argv, "--input-format"));
    try testing.expect(!testArgvHas(request.argv, "--continue"));
    try testing.expect(!testArgvHas(request.argv, "-c"));
    try testing.expect(!testArgvHas(request.argv, "-r"));
    try testing.expect(!testArgvHas(request.argv, "--bare"));
    try testing.expect(!testArgvHas(request.argv, "--allowedTools"));
    try testing.expect(!testArgvHas(request.argv, "--permission-mode"));
    try testing.expect(!testArgvHas(request.argv, daemon_proxy.SUBCOMMAND));
    try testing.expectEqualStrings("", request.stdin);
    try testing.expectEqualStrings("", model.lastSpawnImagePath());
    const binary_at = testArgvIndex(request.argv, "claude") orelse return error.MissingBinary;
    const p_at = testArgvIndex(request.argv, "-p") orelse return error.MissingPrint;
    const format_at = testArgvIndex(request.argv, "--output-format") orelse return error.MissingFormat;
    const stream_at = testArgvIndex(request.argv, "stream-json") orelse return error.MissingStreamJson;
    const verbose_at = testArgvIndex(request.argv, "--verbose") orelse return error.MissingVerbose;
    const partial_at = testArgvIndex(request.argv, "--include-partial-messages") orelse return error.MissingPartial;
    const forward_at = testArgvIndex(request.argv, "--forward-subagent-text") orelse return error.MissingForwardSubagent;
    const resume_at = testArgvIndex(request.argv, "--resume") orelse return error.MissingResume;
    const prompt_at = testArgvIndex(request.argv, "continue that review") orelse return error.MissingPrompt;
    try testing.expectEqual(binary_at + 1, p_at);
    try testing.expectEqual(p_at + 1, format_at);
    try testing.expectEqual(format_at + 1, stream_at);
    try testing.expectEqual(stream_at + 1, verbose_at);
    try testing.expectEqual(verbose_at + 1, partial_at);
    try testing.expectEqual(partial_at + 1, forward_at);
    try testing.expectEqual(forward_at + 1, resume_at);
    try testing.expect(resume_at + 1 < request.argv.len);
    try testing.expectEqualStrings("claude-sess-resume-1", request.argv[resume_at + 1]);
    try testing.expectEqual(resume_at + 2, prompt_at);
}

test "claude empty fx_session_id omits --resume" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setSidecarPath("faku");
    const id = model.addSession("claude empty resume", .claude);
    model.cli_available[@intFromEnum(protocol.ProviderId.claude)] = true;
    if (model.sessionById(id)) |session| session.setFxSessionId("");

    startPrompt(&model, &fx, id, "first send");
    try testing.expectEqual(main.ReplyPath.fx, model.reply_path);
    try testing.expect(model.fx_spawn_claude_json);
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());
    const request = fx.pendingSpawnAt(0).?;
    try testing.expect(testArgvHas(request.argv, "-p"));
    try testing.expect(testArgvHas(request.argv, "first send"));
    try testing.expect(!testArgvHas(request.argv, "--resume"));
    try testing.expect(!testArgvHas(request.argv, "--continue"));
    const partial_at = testArgvIndex(request.argv, "--include-partial-messages") orelse return error.MissingPartial;
    const forward_at = testArgvIndex(request.argv, "--forward-subagent-text") orelse return error.MissingForwardSubagent;
    const prompt_at = testArgvIndex(request.argv, "first send") orelse return error.MissingPrompt;
    try testing.expectEqual(partial_at + 1, forward_at);
    try testing.expectEqual(forward_at + 1, prompt_at);
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
    try testing.expect(!model.fx_spawn_claude_json);
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
    try testing.expect(!testArgvHas(request.argv, "--image"));
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
    try testing.expect(!testArgvHas(request.argv, "--image"));
    try testing.expect(!testArgvHas(request.argv, daemon_proxy.SUBCOMMAND));
    try testing.expectEqualStrings("", request.stdin);
    try testing.expectEqualStrings("", model.lastSpawnImagePath());
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

test "amp image attach uses execute @path in the -x prompt" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var image_buf: [256]u8 = undefined;
    const image = try std.fmt.bufPrint(&image_buf, ".zig-cache/tmp/{s}/amp-shot.png", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().writeFile(testing.io, .{ .sub_path = image, .data = "png" });
    var at_buf: [257]u8 = undefined;
    const at_image = try std.fmt.bufPrint(&at_buf, "@{s}", .{image});

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
    try testing.expectEqual(main.ReplyPath.fx, model.reply_path);
    try testing.expect(!model.fx_spawn_acp);
    try testing.expectEqual(@as(usize, 0), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());
    try testing.expectEqualStrings(image, model.lastSpawnImagePath());

    const request = fx.pendingSpawnAt(0).?;
    try testing.expect(testArgvHas(request.argv, "amp"));
    try testing.expect(testArgvHas(request.argv, "-x"));
    try testing.expect(!testArgvHas(request.argv, at_image));
    try testing.expect(!testArgvHas(request.argv, "describe this"));
    try testing.expect(!testArgvHas(request.argv, "--image"));
    try testing.expect(!testArgvHas(request.argv, "--execute"));
    try testing.expect(!testArgvHas(request.argv, acp_proxy.SUBCOMMAND));
    try testing.expect(!testArgvHas(request.argv, "ask"));
    try testing.expect(!testArgvHas(request.argv, "fx"));
    try testing.expect(!testArgvHas(request.argv, daemon_proxy.SUBCOMMAND));
    try testing.expectEqualStrings("", request.stdin);
    const binary_at = testArgvIndex(request.argv, "amp") orelse return error.MissingBinary;
    const x_at = testArgvIndex(request.argv, "-x") orelse return error.MissingExecute;
    try testing.expectEqual(binary_at + 1, x_at);
    try testing.expect(x_at + 1 < request.argv.len);
    const execute_prompt = request.argv[x_at + 1];
    try testing.expect(std.mem.indexOf(u8, execute_prompt, at_image) != null);
    try testing.expect(std.mem.indexOf(u8, execute_prompt, image) != null);
    try testing.expect(std.mem.indexOf(u8, execute_prompt, "describe this") != null);
    try testing.expect(std.mem.startsWith(u8, execute_prompt, at_image));
    try testing.expectEqual(x_at + 2, request.argv.len);
}

test "amp unavailable image attach stays demo" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var image_buf: [256]u8 = undefined;
    const image = try std.fmt.bufPrint(&image_buf, ".zig-cache/tmp/{s}/amp-missing-shot.png", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().writeFile(testing.io, .{ .sub_path = image, .data = "png" });

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = testing.io;
    const id = model.addSession("amp missing image", .amp);
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

test "pi + cli_available selects json-mode pi --mode json {prompt}" {
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
    try testing.expect(model.fx_spawn_pi_json);
    try testing.expect(!model.fx_spawn_claude_json);
    try testing.expectEqual(@as(usize, 0), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());

    const request = fx.pendingSpawnAt(0).?;
    try testing.expectEqual(main.fx_ask_key, request.key);
    try testing.expect(testArgvHas(request.argv, "pi"));
    try testing.expect(testArgvHas(request.argv, "--mode"));
    try testing.expect(testArgvHas(request.argv, "json"));
    try testing.expect(testArgvHas(request.argv, "hello pi"));
    try testing.expect(!testArgvHas(request.argv, acp_proxy.SUBCOMMAND));
    try testing.expect(!testArgvHas(request.argv, "acp"));
    try testing.expect(!testArgvHas(request.argv, "agent"));
    try testing.expect(!testArgvHas(request.argv, "stdio"));
    try testing.expect(!testArgvHas(request.argv, "ask"));
    try testing.expect(!testArgvHas(request.argv, "fx"));
    try testing.expect(!testArgvHas(request.argv, "-x"));
    try testing.expect(!testArgvHas(request.argv, "exec"));
    try testing.expect(!testArgvHas(request.argv, "-p"));
    try testing.expect(!testArgvHas(request.argv, "--print"));
    try testing.expect(!testArgvHas(request.argv, "--output-format"));
    try testing.expect(!testArgvHas(request.argv, "rpc"));
    try testing.expect(!testArgvHas(request.argv, "-a"));
    try testing.expect(!testArgvHas(request.argv, "--approve"));
    try testing.expect(!testArgvHas(request.argv, "--no-approve"));
    try testing.expect(!testArgvHas(request.argv, "--dangerously-skip-permissions"));
    try testing.expect(!testArgvHas(request.argv, "--dangerously-allow-all"));
    try testing.expect(!testArgvHas(request.argv, daemon_proxy.SUBCOMMAND));
    try testing.expect(!testArgvHas(request.argv, "--image"));
    try testing.expectEqualStrings("", request.stdin);
    try testing.expectEqualStrings("", model.lastSpawnImagePath());
    const binary_at = testArgvIndex(request.argv, "pi") orelse return error.MissingBinary;
    const mode_at = testArgvIndex(request.argv, "--mode") orelse return error.MissingMode;
    const json_at = testArgvIndex(request.argv, "json") orelse return error.MissingJson;
    const prompt_at = testArgvIndex(request.argv, "hello pi") orelse return error.MissingPrompt;
    try testing.expectEqual(binary_at + 1, mode_at);
    try testing.expectEqual(mode_at + 1, json_at);
    try testing.expectEqual(json_at + 1, prompt_at);
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
    try testing.expect(!model.fx_spawn_pi_json);
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

test "pi image attach uses json-mode @path" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var image_buf: [256]u8 = undefined;
    const image = try std.fmt.bufPrint(&image_buf, ".zig-cache/tmp/{s}/pi-shot.png", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().writeFile(testing.io, .{ .sub_path = image, .data = "png" });
    var at_buf: [257]u8 = undefined;
    const at_image = try std.fmt.bufPrint(&at_buf, "@{s}", .{image});

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
    try testing.expectEqual(main.ReplyPath.fx, model.reply_path);
    try testing.expect(!model.fx_spawn_acp);
    try testing.expect(model.fx_spawn_pi_json);
    try testing.expectEqual(@as(usize, 0), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());
    try testing.expectEqualStrings(image, model.lastSpawnImagePath());

    const request = fx.pendingSpawnAt(0).?;
    try testing.expect(testArgvHas(request.argv, "pi"));
    try testing.expect(testArgvHas(request.argv, "--mode"));
    try testing.expect(testArgvHas(request.argv, "json"));
    try testing.expect(testArgvHas(request.argv, at_image));
    try testing.expect(testArgvHas(request.argv, "describe this"));
    try testing.expect(!testArgvHas(request.argv, image));
    try testing.expect(!testArgvHas(request.argv, "--image"));
    try testing.expect(!testArgvHas(request.argv, "-p"));
    try testing.expect(!testArgvHas(request.argv, "--print"));
    try testing.expect(!testArgvHas(request.argv, "rpc"));
    try testing.expect(!testArgvHas(request.argv, "-a"));
    try testing.expect(!testArgvHas(request.argv, "--approve"));
    try testing.expect(!testArgvHas(request.argv, acp_proxy.SUBCOMMAND));
    try testing.expect(!testArgvHas(request.argv, "ask"));
    try testing.expect(!testArgvHas(request.argv, "fx"));
    try testing.expect(!testArgvHas(request.argv, daemon_proxy.SUBCOMMAND));
    try testing.expectEqualStrings("", request.stdin);
    const binary_at = testArgvIndex(request.argv, "pi") orelse return error.MissingBinary;
    const mode_at = testArgvIndex(request.argv, "--mode") orelse return error.MissingMode;
    const json_at = testArgvIndex(request.argv, "json") orelse return error.MissingJson;
    const at_at = testArgvIndex(request.argv, at_image) orelse return error.MissingAtPath;
    const prompt_at = testArgvIndex(request.argv, "describe this") orelse return error.MissingPrompt;
    try testing.expectEqual(binary_at + 1, mode_at);
    try testing.expectEqual(mode_at + 1, json_at);
    try testing.expectEqual(json_at + 1, at_at);
    try testing.expectEqual(at_at + 1, prompt_at);
}

test "pi unavailable image attach stays demo" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var image_buf: [256]u8 = undefined;
    const image = try std.fmt.bufPrint(&image_buf, ".zig-cache/tmp/{s}/pi-missing-shot.png", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().writeFile(testing.io, .{ .sub_path = image, .data = "png" });

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = testing.io;
    const id = model.addSession("pi missing image", .pi);
    model.selected = id;
    model.setDraftImagePath(image);

    startPrompt(&model, &fx, id, "describe this");
    try testing.expectEqual(main.ReplyPath.demo, model.reply_path);
    try testing.expect(!model.fx_spawn_acp);
    try testing.expect(!model.fx_spawn_pi_json);
    try testing.expectEqual(@as(usize, 1), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
}

test "pi json-mode reuses fx_ask_chdir_script when project cwd exists" {
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
    try testing.expect(model.fx_spawn_pi_json);
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());
    const request = fx.pendingSpawnAt(0).?;
    try testing.expect(testArgvHas(request.argv, "/bin/sh"));
    try testing.expect(testArgvHas(request.argv, "-c"));
    try testing.expect(testArgvHas(request.argv, fx_ask_chdir_script));
    try testing.expect(testArgvHas(request.argv, project));
    const binary_at = testArgvIndex(request.argv, "pi") orelse return error.MissingBinary;
    const mode_at = testArgvIndex(request.argv, "--mode") orelse return error.MissingMode;
    const json_at = testArgvIndex(request.argv, "json") orelse return error.MissingJson;
    const prompt_at = testArgvIndex(request.argv, "in project") orelse return error.MissingPrompt;
    try testing.expect(binary_at > 0);
    try testing.expectEqual(binary_at + 1, mode_at);
    try testing.expectEqual(mode_at + 1, json_at);
    try testing.expectEqual(json_at + 1, prompt_at);
    try testing.expectEqualStrings(project, request.argv[binary_at - 1]);
}

test "pi @path join overflow fails closed" {
    const testing = std.testing;
    var tiny: [4]u8 = undefined;
    try testing.expect(formatPiAtPath(&tiny, "/too/long/image.png") == null);
    var ok_buf: [32]u8 = undefined;
    const ok = formatPiAtPath(&ok_buf, "shot.png") orelse return error.JoinFailed;
    try testing.expectEqualStrings("@shot.png", ok);
    try testing.expect(formatPiAtPath(&ok_buf, "") == null);
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
    try testing.expect(!model.fx_spawn_claude_json);
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
    try testing.expect(!model.fx_spawn_claude_json);
    try testing.expectEqual(@as(usize, 1), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
}

test "claude image attach uses print-mode path in the -p prompt" {
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
    try testing.expectEqual(main.ReplyPath.fx, model.reply_path);
    try testing.expect(!model.fx_spawn_acp);
    try testing.expect(model.fx_spawn_claude_json);
    try testing.expect(!model.fx_spawn_pi_json);
    try testing.expectEqual(@as(usize, 0), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());
    try testing.expectEqualStrings(image, model.lastSpawnImagePath());

    const request = fx.pendingSpawnAt(0).?;
    try testing.expect(testArgvHas(request.argv, "claude"));
    try testing.expect(testArgvHas(request.argv, "-p"));
    try testing.expect(testArgvHas(request.argv, "--output-format"));
    try testing.expect(testArgvHas(request.argv, "stream-json"));
    try testing.expect(testArgvHas(request.argv, "--verbose"));
    try testing.expect(testArgvHas(request.argv, "--include-partial-messages"));
    try testing.expect(testArgvHas(request.argv, "--forward-subagent-text"));
    try testing.expect(!testArgvHas(request.argv, "text"));
    try testing.expect(!testArgvHas(request.argv, image));
    try testing.expect(!testArgvHas(request.argv, "describe this"));
    try testing.expect(!testArgvHas(request.argv, "--image"));
    try testing.expect(!testArgvHas(request.argv, "-i"));
    try testing.expect(!testArgvHas(request.argv, "--input-format"));
    try testing.expect(!testArgvHas(request.argv, "--continue"));
    try testing.expect(!testArgvHas(request.argv, "--resume"));
    try testing.expect(!testArgvHas(request.argv, "acp"));
    try testing.expect(!testArgvHas(request.argv, acp_proxy.SUBCOMMAND));
    try testing.expect(!testArgvHas(request.argv, "ask"));
    try testing.expect(!testArgvHas(request.argv, "fx"));
    try testing.expect(!testArgvHas(request.argv, daemon_proxy.SUBCOMMAND));
    try testing.expectEqualStrings("", request.stdin);
    const binary_at = testArgvIndex(request.argv, "claude") orelse return error.MissingBinary;
    const p_at = testArgvIndex(request.argv, "-p") orelse return error.MissingPrint;
    const format_at = testArgvIndex(request.argv, "--output-format") orelse return error.MissingFormat;
    const stream_at = testArgvIndex(request.argv, "stream-json") orelse return error.MissingStreamJson;
    const verbose_at = testArgvIndex(request.argv, "--verbose") orelse return error.MissingVerbose;
    const partial_at = testArgvIndex(request.argv, "--include-partial-messages") orelse return error.MissingPartial;
    const forward_at = testArgvIndex(request.argv, "--forward-subagent-text") orelse return error.MissingForwardSubagent;
    try testing.expectEqual(binary_at + 1, p_at);
    try testing.expectEqual(p_at + 1, format_at);
    try testing.expectEqual(format_at + 1, stream_at);
    try testing.expectEqual(stream_at + 1, verbose_at);
    try testing.expectEqual(verbose_at + 1, partial_at);
    try testing.expectEqual(partial_at + 1, forward_at);
    try testing.expect(forward_at + 1 < request.argv.len);
    const print_prompt = request.argv[forward_at + 1];
    try testing.expect(std.mem.indexOf(u8, print_prompt, claude_image_prompt_prefix) != null);
    try testing.expect(std.mem.indexOf(u8, print_prompt, image) != null);
    try testing.expect(std.mem.indexOf(u8, print_prompt, "describe this") != null);
    try testing.expect(std.mem.startsWith(u8, print_prompt, claude_image_prompt_prefix));
    try testing.expectEqual(forward_at + 2, request.argv.len);
}

test "claude image attach + stored fx_session_id uses path-in-prompt and --resume" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var image_buf: [256]u8 = undefined;
    const image = try std.fmt.bufPrint(&image_buf, ".zig-cache/tmp/{s}/claude-resume-shot.png", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().writeFile(testing.io, .{ .sub_path = image, .data = "png" });

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = testing.io;
    model.setSidecarPath("faku");
    model.cli_available[@intFromEnum(protocol.ProviderId.claude)] = true;
    const id = model.addSession("claude image resume", .claude);
    model.selected = id;
    model.setDraftImagePath(image);
    if (model.sessionById(id)) |session| session.setFxSessionId("claude-sess-image-1");

    startPrompt(&model, &fx, id, "describe this");
    try testing.expectEqual(main.ReplyPath.fx, model.reply_path);
    try testing.expect(!model.fx_spawn_acp);
    try testing.expect(model.fx_spawn_claude_json);
    try testing.expectEqual(@as(usize, 0), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());
    try testing.expectEqualStrings(image, model.lastSpawnImagePath());

    const request = fx.pendingSpawnAt(0).?;
    try testing.expect(testArgvHas(request.argv, "claude"));
    try testing.expect(testArgvHas(request.argv, "-p"));
    try testing.expect(testArgvHas(request.argv, "--output-format"));
    try testing.expect(testArgvHas(request.argv, "stream-json"));
    try testing.expect(testArgvHas(request.argv, "--verbose"));
    try testing.expect(testArgvHas(request.argv, "--include-partial-messages"));
    try testing.expect(testArgvHas(request.argv, "--forward-subagent-text"));
    try testing.expect(testArgvHas(request.argv, "--resume"));
    try testing.expect(testArgvHas(request.argv, "claude-sess-image-1"));
    try testing.expect(!testArgvHas(request.argv, image));
    try testing.expect(!testArgvHas(request.argv, "describe this"));
    try testing.expect(!testArgvHas(request.argv, "--image"));
    try testing.expect(!testArgvHas(request.argv, "-i"));
    try testing.expect(!testArgvHas(request.argv, "--input-format"));
    try testing.expect(!testArgvHas(request.argv, "--continue"));
    try testing.expect(!testArgvHas(request.argv, "acp"));
    try testing.expect(!testArgvHas(request.argv, acp_proxy.SUBCOMMAND));
    try testing.expect(!testArgvHas(request.argv, "--dangerously-skip-permissions"));
    try testing.expectEqualStrings("", request.stdin);
    const binary_at = testArgvIndex(request.argv, "claude") orelse return error.MissingBinary;
    const p_at = testArgvIndex(request.argv, "-p") orelse return error.MissingPrint;
    const partial_at = testArgvIndex(request.argv, "--include-partial-messages") orelse return error.MissingPartial;
    const forward_at = testArgvIndex(request.argv, "--forward-subagent-text") orelse return error.MissingForwardSubagent;
    const resume_at = testArgvIndex(request.argv, "--resume") orelse return error.MissingResume;
    try testing.expectEqual(binary_at + 1, p_at);
    try testing.expectEqual(partial_at + 1, forward_at);
    try testing.expectEqual(forward_at + 1, resume_at);
    try testing.expect(resume_at + 1 < request.argv.len);
    try testing.expectEqualStrings("claude-sess-image-1", request.argv[resume_at + 1]);
    try testing.expect(resume_at + 2 < request.argv.len);
    const print_prompt = request.argv[resume_at + 2];
    try testing.expect(std.mem.indexOf(u8, print_prompt, claude_image_prompt_prefix) != null);
    try testing.expect(std.mem.indexOf(u8, print_prompt, image) != null);
    try testing.expect(std.mem.indexOf(u8, print_prompt, "describe this") != null);
    try testing.expect(std.mem.startsWith(u8, print_prompt, claude_image_prompt_prefix));
    try testing.expectEqual(resume_at + 3, request.argv.len);
}

test "claude unavailable image attach stays demo" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var image_buf: [256]u8 = undefined;
    const image = try std.fmt.bufPrint(&image_buf, ".zig-cache/tmp/{s}/claude-missing-shot.png", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().writeFile(testing.io, .{ .sub_path = image, .data = "png" });

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = testing.io;
    const id = model.addSession("claude missing image", .claude);
    model.selected = id;
    model.setDraftImagePath(image);

    startPrompt(&model, &fx, id, "describe this");
    try testing.expectEqual(main.ReplyPath.demo, model.reply_path);
    try testing.expect(!model.fx_spawn_acp);
    try testing.expect(!model.fx_spawn_claude_json);
    try testing.expectEqual(@as(usize, 1), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
}

test "claude image attach overflow stays demo" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var image_buf: [256]u8 = undefined;
    const image = try std.fmt.bufPrint(&image_buf, ".zig-cache/tmp/{s}/claude-overflow-shot.png", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().writeFile(testing.io, .{ .sub_path = image, .data = "png" });

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = testing.io;
    model.setSidecarPath("faku");
    model.cli_available[@intFromEnum(protocol.ProviderId.claude)] = true;
    const id = model.addSession("claude overflow image", .claude);
    model.selected = id;
    model.setDraftImagePath(image);

    var long_prompt: [main.max_draft + main.max_project_path]u8 = undefined;
    @memset(&long_prompt, 'x');
    startPrompt(&model, &fx, id, &long_prompt);
    try testing.expectEqual(main.ReplyPath.demo, model.reply_path);
    try testing.expect(!model.fx_spawn_acp);
    try testing.expect(!model.fx_spawn_claude_json);
    try testing.expectEqual(@as(usize, 1), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
    try testing.expectEqual(@as(usize, 0), model.lastSpawnImagePath().len);
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
    try testing.expect(model.fx_spawn_claude_json);
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());
    const request = fx.pendingSpawnAt(0).?;
    try testing.expect(testArgvHas(request.argv, "/bin/sh"));
    try testing.expect(testArgvHas(request.argv, "-c"));
    try testing.expect(testArgvHas(request.argv, fx_ask_chdir_script));
    try testing.expect(testArgvHas(request.argv, project));
    try testing.expect(testArgvHas(request.argv, "stream-json"));
    try testing.expect(testArgvHas(request.argv, "--verbose"));
    try testing.expect(testArgvHas(request.argv, "--include-partial-messages"));
    const binary_at = testArgvIndex(request.argv, "claude") orelse return error.MissingBinary;
    const p_at = testArgvIndex(request.argv, "-p") orelse return error.MissingPrint;
    try testing.expect(binary_at > 0);
    try testing.expectEqual(binary_at + 1, p_at);
    try testing.expectEqualStrings(project, request.argv[binary_at - 1]);
    try testing.expect(!testArgvHas(request.argv, "--resume"));
    try testing.expect(!testArgvHas(request.argv, "--continue"));
}

test "claude print-mode chdir + stored fx_session_id keeps resume as argv slots" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/claude-cwd-resume", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(testing.io, project);

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = testing.io;
    const id = model.addSession("claude cwd resume", .claude);
    model.cli_available[@intFromEnum(protocol.ProviderId.claude)] = true;
    if (model.sessionById(id)) |session| {
        session.setProjectPath(project);
        session.setFxSessionId("claude-sess-cwd-1");
    }

    startPrompt(&model, &fx, id, "in project");
    try testing.expectEqual(main.ReplyPath.fx, model.reply_path);
    try testing.expect(model.fx_spawn_claude_json);
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());
    const request = fx.pendingSpawnAt(0).?;
    try testing.expect(testArgvHas(request.argv, "/bin/sh"));
    try testing.expect(testArgvHas(request.argv, fx_ask_chdir_script));
    try testing.expect(testArgvHas(request.argv, project));
    try testing.expect(testArgvHas(request.argv, "--resume"));
    try testing.expect(testArgvHas(request.argv, "claude-sess-cwd-1"));
    try testing.expect(!testArgvHas(request.argv, "--continue"));
    try testing.expectEqualStrings(fx_ask_chdir_script, request.argv[2]);
    try testing.expect(std.mem.indexOf(u8, request.argv[2], "claude-sess-cwd-1") == null);
    const resume_at = testArgvIndex(request.argv, "--resume") orelse return error.MissingResume;
    try testing.expectEqualStrings("claude-sess-cwd-1", request.argv[resume_at + 1]);
    const partial_at = testArgvIndex(request.argv, "--include-partial-messages") orelse return error.MissingPartial;
    const forward_at = testArgvIndex(request.argv, "--forward-subagent-text") orelse return error.MissingForwardSubagent;
    try testing.expectEqual(partial_at + 1, forward_at);
    try testing.expectEqual(forward_at + 1, resume_at);
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

test "codex image attach uses exec --image" {
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
    try testing.expectEqual(main.ReplyPath.fx, model.reply_path);
    try testing.expect(!model.fx_spawn_acp);
    try testing.expectEqual(@as(usize, 0), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());
    try testing.expectEqualStrings(image, model.lastSpawnImagePath());

    const request = fx.pendingSpawnAt(0).?;
    try testing.expect(testArgvHas(request.argv, "codex"));
    try testing.expect(testArgvHas(request.argv, "exec"));
    try testing.expect(testArgvHas(request.argv, "--image"));
    try testing.expect(testArgvHas(request.argv, image));
    try testing.expect(testArgvHas(request.argv, "describe this"));
    try testing.expect(!testArgvHas(request.argv, acp_proxy.SUBCOMMAND));
    try testing.expect(!testArgvHas(request.argv, "ask"));
    try testing.expect(!testArgvHas(request.argv, "fx"));
    try testing.expect(!testArgvHas(request.argv, "--full-auto"));
    try testing.expect(!testArgvHas(request.argv, "--ask-for-approval"));
    try testing.expect(!testArgvHas(request.argv, "never"));
    try testing.expect(!testArgvHas(request.argv, "--sandbox"));
    try testing.expect(!testArgvHas(request.argv, daemon_proxy.SUBCOMMAND));
    try testing.expectEqualStrings("", request.stdin);
    const binary_at = testArgvIndex(request.argv, "codex") orelse return error.MissingBinary;
    const exec_at = testArgvIndex(request.argv, "exec") orelse return error.MissingExec;
    const image_at = testArgvIndex(request.argv, "--image") orelse return error.MissingImage;
    const prompt_at = testArgvIndex(request.argv, "describe this") orelse return error.MissingPrompt;
    try testing.expectEqual(binary_at + 1, exec_at);
    try testing.expectEqual(exec_at + 1, prompt_at);
    try testing.expectEqualStrings("describe this", request.argv[prompt_at]);
    try testing.expectEqual(prompt_at + 1, image_at);
    try testing.expectEqualStrings(image, request.argv[image_at + 1]);
}

test "codex unavailable image attach stays demo" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var image_buf: [256]u8 = undefined;
    const image = try std.fmt.bufPrint(&image_buf, ".zig-cache/tmp/{s}/codex-missing-shot.png", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().writeFile(testing.io, .{ .sub_path = image, .data = "png" });

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = testing.io;
    const id = model.addSession("codex missing image", .codex);
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

test "grok image attach uses ACP image content block" {
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
    try testing.expectEqual(main.ReplyPath.fx, model.reply_path);
    try testing.expect(model.fx_spawn_acp);
    try testing.expectEqual(@as(usize, 0), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());
    try testing.expectEqualStrings(image, model.lastSpawnImagePath());

    const request = fx.pendingSpawnAt(0).?;
    try testing.expect(testArgvHas(request.argv, acp_proxy.SUBCOMMAND));
    try testing.expect(testArgvHas(request.argv, "grok"));
    try testing.expect(testArgvHas(request.argv, "agent"));
    try testing.expect(testArgvHas(request.argv, "stdio"));
    try testing.expect(!testArgvHas(request.argv, "acp"));
    try testing.expect(!testArgvHas(request.argv, "--image"));
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"method\":\"session/prompt\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "describe this") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"type\":\"image\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"data\":\"cG5n\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"mimeType\":\"image/png\"") != null);
}
