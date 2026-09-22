//! Prompt-start and provider-spawn helpers.
//!
//! `startPrompt` path selection (daemon / fx acp / fx ask / probed
//! ACP stdio via acp-proxy / Claude print-mode / Codex exec / Amp
//! execute-mode / Pi RPC one-shot / OpenCode 2 run / demo), StartOptions mapping, and
//! `takeFxAskSessionId` live here. Callers import this module
//! directly (`spawn.startOptionsFromSession` /
//! `spawn.takeFxAskSessionId` / `spawn.startPrompt`). Not
//! re-exported from `main`. Stream lifecycle lives in
//! `stream.zig`. Line handlers live in `lines.zig`.
//! `startPrompt` prepends stripped enabled-skill bodies for `$name`
//! and skill-matching `/name` tokens (see `skills.prepareSendPrompt`)
//! before spawn; untitled titles keep the original draft.
//!
//! Non-fx live Send this cut: `ProviderId.speaksAcpStdio` (cursor /
//! opencode / kimi bare `acp`, grok `agent stdio`, deepseek
//! `--profile acp`) when `providers.isAvailable`. Same one-shot
//! `faku acp-proxy -- {binary} …transport…` as fx. `reply_path` stays
//! `.fx` so ACP stream parsing (`fx_spawn_acp` / `fx_line` /
//! `fx_exit`) is unchanged. After that,
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
//! Available Pi is one-shot `{binary} --mode rpc --no-session`
//! (stdin is one LF-terminated prompt JSONL command; Native closes
//! stdin after that buffer; not ACP, not acp-proxy, not `--mode
//! json`, not a long-lived RPC loop). Available Oh My Pi is the same
//! one-shot RPC path with `{binary}` `omp` (or override) and Waku
//! `PiFlavor::OhMyPi` argv `--mode rpc --yolo` plus documented
//! `--no-session`. Composer image attach uses
//! documented RPC `images` on that prompt command (`ImageContent`:
//! `type`/`data` base64/`mimeType`; png/jpeg/gif/webp; ~256KB raw
//! like ACP). Missing / unreadable / unknown type / overflow fail
//! closed to demo. There is no `--image` flag. `reply_path` stays
//! `.fx` with `fx_spawn_acp = false`. Pi / Oh My Pi set `fx_spawn_pi_json =
//! true` so stdout lines use the Pi JSONL parser in `lines.zig`
//! (RPC `message_update` / `assistantMessageEvent.type ==
//! text_delta` / `delta`, not json-mode top-level `type:text_delta`,
//! not prose / raw JSON dump). Available OpenCode 2 is one-shot
//! `{binary} run --format json --auto {prompt}` (empty stdin, not
//! ACP, not `opencode acp`, not acp-proxy, not an in-app HTTP/SSE
//! serve client), with documented `--attach {url}` when
//! `opencode2_attach_url` trim is non-empty (user-owned `opencode2
//! serve`; Faku does not spawn serve), documented `--password` when
//! attach URL and `opencode2_server_password` are both set
//! (documented `run --attach --password`), documented `--username`
//! when persist is non-empty, documented `--session
//! {fx_session_id}` when that field is non-empty (first Send and Fork
//! omit it), documented `--model` when the session model is non-empty
//! (`provider/model` form; no invented catalog), and documented
//! `--file {path}` when a composer image/file is attached. `--auto`
//! is always set this cut so non-interactive Send does not hang
//! (OpenCode run has no permission UI in Faku).
//! `fx_spawn_opencode_run_json` routes NDJSON `type:"text"` /
//! `part.text` in `lines.zig` and captures `sessionID` into
//! `fx_session_id`. Unavailable OpenCode 2 stays demo. In-app
//! HTTP/SSE serve client stays deferred.
//! Available DeepSeek is one-shot `dsh --profile acp` via acp-proxy
//! (not `dsh acp`; not Harness HTTP/SSE / in-app web; `--profile
//! headless` is empty-Commit… generate only).
//! Composer image attach on cursor / opencode / kimi / grok uses official
//! ACP v1 image content blocks (base64 + mimeType) on the one-shot
//! acp-proxy `session/prompt`. DeepSeek fail-closes to demo when a
//! composer image is attached (official dsh ACP advertises no image
//! capability; do not silently drop; do not invent image blocks).
//! fx still uses `fx ask --image` (no ACP image blocks). Overflow /
//! missing / unknown type fail closed to demo.

const std = @import("std");
const main = @import("main.zig");
const util = @import("util.zig");
const model_exports = @import("model_exports.zig");
const effect_keys = @import("effect_keys.zig");
const protocol = @import("protocol.zig");
const acp = @import("acp.zig");
const store = @import("store.zig");
const daemon_proxy = @import("daemon_proxy.zig");
const acp_proxy = @import("acp_proxy.zig");
const composer = @import("composer.zig");
const session_fork = @import("fork.zig");
const providers = @import("providers.zig");
const environment_summary = @import("environment_summary.zig");
const skills = @import("skills.zig");
const git_commit_generate = @import("git_commit_generate.zig");

const Model = model_exports.Model;
const Effects = main.Effects;
const Session = model_exports.Session;
const writeFixed = model_exports.writeFixed;
const fxPermissionMode = composer.fxPermissionMode;
const stream_timer_key = effect_keys.stream_timer_key;
const stream_interval_ms = effect_keys.stream_interval_ms;
const chrome_tick_key = effect_keys.chrome_tick_key;
const chrome_tick_interval_ms = effect_keys.chrome_tick_interval_ms;
const fx_ask_key = effect_keys.fx_ask_key;
const daemon_line_bytes = effect_keys.daemon_line_bytes;
const max_fx_model = model_exports.max_fx_model;
const max_access_mode = model_exports.max_access_mode;
const default_access_mode = model_exports.default_access_mode;
const default_interaction_mode = model_exports.default_interaction_mode;
const fx_env_bin = util.fx_env_bin;
const fx_ask_chdir_script = util.fx_ask_chdir_script;

/// Start a turn. Untitled titles use original `text`; `$name` /
/// skill-matching `/name` bodies are prepended onto the prompt that
/// is stored and spawned (`skills.prepareSendPrompt`). Worktree prep
/// stores the original draft and expands here when Send finally runs.
pub fn startPrompt(model: *Model, fx: *Effects, session_id: u32, text: []const u8) void {
    const session = model.sessionById(session_id) orelse return;
    session_fork.recordRewindRefIfPossible(model, fx, session.id);
    var expanded_buf: [model_exports.max_body]u8 = undefined;
    const prompt = skills.prepareSendPrompt(model, fx, text, &expanded_buf);
    const titled = session.untitled;
    if (session.untitled) {
        writeFixed(&session.title_storage, &session.title_len, text);
        session.untitled = false;
    }
    _ = model.appendTurn(session.id, .user, prompt);
    const assistant_id = model.appendTurn(session.id, .assistant, "");
    if (titled) store.persistIfPossible(model, session.id, fx);
    session.busy = true;
    model.phase = .streaming;
    model.stream_cursor = 0;
    model.stream_turn_id = assistant_id;
    model.streaming_session = session.id;
    model.fx_spawn_pi_json = false;
    model.fx_spawn_claude_json = false;
    model.fx_spawn_opencode_run_json = false;
    environment_summary.clearDismissedSubagentIds(model);
    environment_summary.noteLiveProcess(model);
    if (!model.daemon_disconnected and model.daemonAddress().len > 0) {
        model.reply_path = .daemon;
        startDaemonProxy(model, fx, session, prompt);
        return;
    }
    if (session.provider == .fx and model.fx_available and model.fxPath().len > 0) {
        model.reply_path = .fx;
        const image_path = model.resolveSpawnImage();
        if (image_path.len > 0) {
            startFxAsk(model, fx, session, prompt);
            return;
        }
        if (!startFxAcp(model, fx, session, prompt)) {
            startFxAsk(model, fx, session, prompt);
        }
        return;
    }
    if (session.provider.speaksAcpStdio() and providers.isAvailable(model, session.provider)) {
        // Official ACP v1 image content blocks on session/prompt when
        // a composer image is attached (cursor / opencode / kimi /
        // grok). DeepSeek fail-closes to demo in startAcpProxy when a
        // composer image is attached (official dsh ACP has no image
        // capability). Missing / unreadable / unknown type / overflow
        // fail closed to demo. fx never takes this branch (not
        // speaksAcpStdio).
        const binary = providers.binaryFor(model, session.provider);
        // Reuse fx spawn keys / fx_line / fx_exit / reply_path=.fx
        // so handleAcpLine keeps working. Not a new ReplyPath alias.
        model.reply_path = .fx;
        if (startAcpProxy(model, fx, session, binary, prompt)) return;
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
        if (startClaudePrint(model, fx, session, prompt)) {
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
        if (startCodexExec(model, fx, session, prompt)) {
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
        if (startAmpExecute(model, fx, session, prompt)) {
            model.reply_path = .fx;
            return;
        }
    }
    if (session.provider.speaksPiRpc() and providers.isAvailable(model, session.provider)) {
        // Pi / Oh My Pi are not ACP. Official first-cut live Send is
        // one-shot `{binary} --mode rpc` with one LF-terminated stdin
        // prompt JSONL command (Native closes stdin after write; keep
        // reading stdout until settle). Oh My Pi adds Waku
        // `PiFlavor::OhMyPi` `--yolo` (full-access arg). Both pass
        // documented `--no-session` (Waku omp model discovery uses
        // it; Faku one-shot has no session-file resume). Documented
        // RPC `images` on that command when a composer image exists.
        // Missing / unreadable / unknown type / overflow fail closed
        // to demo. There is no `--image` flag. Unavailable stays demo.
        if (startPiRpc(model, fx, session, prompt)) {
            model.reply_path = .fx;
            return;
        }
    }
    if (session.provider.speaksOpencodeRun() and providers.isAvailable(model, session.provider)) {
        // OpenCode 2 is not ACP (`opencode acp` is ProviderId.opencode).
        // Official first-cut live Send is one-shot `{binary} run
        // --format json --auto {prompt}` (opencode.ai/docs/cli/).
        // Later Sends pass documented `--session {fx_session_id}`
        // when that field is non-empty; first Send and Fork omit it.
        // Optional `--model` when the session model is non-empty.
        // Documented `--file {path}` when a composer image/file is
        // attached. `--auto` is always set this cut so Send does not
        // hang on permission prompts (no interactive permission UI
        // in Faku). Unavailable stays demo. HTTP/SSE serve is still
        // deferred.
        if (startOpencodeRun(model, fx, session, prompt)) {
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

/// First-cut repeating idle chrome tick. Arms for the app lifetime
/// from `initFx`. Own timer key — `finishStream` / `stopStream` must
/// not cancel it. `on_fire` is the same `.tick` Msg as the demo
/// stream timer; `update` gates `tickStream` on `stream_timer_key`.
pub fn startChromeTick(fx: *Effects) void {
    fx.startTimer(.{
        .key = chrome_tick_key,
        .interval_ms = chrome_tick_interval_ms,
        .mode = .repeating,
        .on_fire = Effects.timerMsg(.tick),
    });
}

/// Map stored session fields onto verified `StartOptions`. Empty
/// `project_path` becomes `"."`. Empty model is omitted on the wire.
/// `computer_use_enabled` is not stored here and stays false.
pub fn startOptionsFromSession(model: *const Model, session: *const Session) protocol.StartOptions {
    return .{
        .provider = session.provider.wireName(),
        .binary = providers.binaryFor(model, session.provider),
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
    const start = if (has_runtime) null else startOptionsFromSession(model, session);
    if (start) |opts| {
        if (opts.binary.len == 0) {
            model.reply_path = .demo;
            startDemoTimer(fx);
            return;
        }
    }
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
/// `ProviderId.acpTransportArgv` (`acp` for fx / cursor / opencode /
/// kimi, `agent stdio` for grok, `--profile acp` for deepseek). fx
/// still prefixes `FX_MODEL` / `FX_PERMISSION_MODE` via `/usr/bin/env`
/// (same as before). Permission also rides `session/set_mode` in the
/// batch. Empty binary or empty transport is a no-op.
///
/// Non-fx ACP stdio may attach one official image content block
/// when the composer draft has an image path, except DeepSeek:
/// official dsh ACP advertises no image capability, so a composer
/// image fail-closes to demo (do not silently drop; do not invent
/// image blocks). fx never gets image blocks here (callers route fx
/// images to `fx ask --image`). Missing / unreadable / unknown type
/// / overflow return false so `startPrompt` fail-closes to demo.
pub fn startAcpProxy(model: *Model, fx: *Effects, session: *const Session, binary: []const u8, prompt: []const u8) bool {
    if (binary.len == 0) return false;
    const transport = session.provider.acpTransportArgv();
    if (transport.len == 0) return false;
    // Official dsh ACP baseline prompts have no image capability.
    // Fail closed to demo rather than dropping the attach or inventing
    // an image content block.
    if (session.provider == .deepseek and model.draftImagePath().len > 0) return false;
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
    // fx REJECTS image blocks. DeepSeek already returned false above
    // when a composer image is attached. Only probed ACP stdio (cursor
    // / opencode / kimi / grok) may attach ImageContent on
    // session/prompt.
    const image_path = if (session.provider.speaksAcpStdio() and session.provider != .deepseek) model.draftImagePath() else "";
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
/// newline + `max_body` (Send may prepend skill bodies into the
/// prompt; turn storage is the same cap). Overflow returns false so Send fails closed to demo
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

    var print_prompt_buf: [claude_image_prompt_prefix.len + model_exports.max_project_path + 1 + model_exports.max_body]u8 = undefined;
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

    var at_path_buf: [1 + model_exports.max_project_path]u8 = undefined;
    const at_path = if (image_path.len > 0)
        std.fmt.bufPrint(&at_path_buf, "@{s}", .{image_path}) catch ""
    else
        "";

    var execute_prompt_buf: [1 + model_exports.max_project_path + 1 + model_exports.max_body]u8 = undefined;
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

/// One-shot Pi RPC stdin: one LF-terminated prompt JSONL command,
/// optionally with one `acp.max_image_bytes` standard-base64 image
/// (same raw cap as ACP). Prompt text is `max_body`; 16 KiB covers
/// JSON keys plus worst-case JSON escaping.
pub const pi_rpc_stdin_cap: usize = std.base64.standard.Encoder.calcSize(acp.max_image_bytes) + 16 * 1024;

const PiRpcWriteError = error{NoSpaceLeft};

const PiRpcCursor = struct {
    buf: []u8,
    pos: usize = 0,

    fn write(self: *PiRpcCursor, bytes: []const u8) PiRpcWriteError!void {
        if (self.pos + bytes.len > self.buf.len) return error.NoSpaceLeft;
        @memcpy(self.buf[self.pos..][0..bytes.len], bytes);
        self.pos += bytes.len;
    }

    fn slice(self: *const PiRpcCursor) []const u8 {
        return self.buf[0..self.pos];
    }
};

fn writePiRpcJsonString(cur: *PiRpcCursor, text: []const u8) PiRpcWriteError!void {
    try cur.write("\"");
    for (text) |c| {
        switch (c) {
            '"' => try cur.write("\\\""),
            '\\' => try cur.write("\\\\"),
            '\n' => try cur.write("\\n"),
            '\r' => try cur.write("\\r"),
            '\t' => try cur.write("\\t"),
            else => {
                if (c < 0x20) {
                    var hex: [6]u8 = undefined;
                    const piece = std.fmt.bufPrint(&hex, "\\u{x:0>4}", .{c}) catch return error.NoSpaceLeft;
                    try cur.write(piece);
                } else {
                    try cur.write(&.{c});
                }
            },
        }
    }
    try cur.write("\"");
}

/// Standard base64 into the JSON string. Alphabet is JSON-safe
/// (`A-Za-z0-9+/=`); do not run it through `writePiRpcJsonString`.
fn writePiRpcBase64(cur: *PiRpcCursor, bytes: []const u8) PiRpcWriteError!void {
    const encoded_len = std.base64.standard.Encoder.calcSize(bytes.len);
    if (cur.pos + encoded_len > cur.buf.len) return error.NoSpaceLeft;
    _ = std.base64.standard.Encoder.encode(cur.buf[cur.pos..][0..encoded_len], bytes);
    cur.pos += encoded_len;
}

/// Official Pi RPC `prompt` command as one LF-terminated JSONL line
/// (https://pi.dev/docs/latest/rpc). Native spawn writes this buffer
/// and closes stdin. `id` is `"1"` for first-cut one-shot correlation.
/// Optional `images` is one documented `ImageContent` object
/// (`type`/`data`/`mimeType`). Overflow returns `error.NoSpaceLeft`
/// so Send fail-closes to demo.
pub fn writePiRpcPromptStdin(buf: []u8, prompt: []const u8, image: ?acp.ImageContent) PiRpcWriteError![]const u8 {
    var cur = PiRpcCursor{ .buf = buf };
    try cur.write("{\"id\":\"1\",\"type\":\"prompt\",\"message\":");
    try writePiRpcJsonString(&cur, prompt);
    if (image) |img| {
        if (img.bytes.len > 0 and img.mime_type.len > 0) {
            try cur.write(",\"images\":[{\"type\":\"image\",\"data\":\"");
            try writePiRpcBase64(&cur, img.bytes);
            try cur.write("\",\"mimeType\":");
            try writePiRpcJsonString(&cur, img.mime_type);
            try cur.write("}]");
        }
    }
    try cur.write("}\n");
    return cur.slice();
}

/// One-shot official Pi-family RPC:
/// `{binary} --mode rpc` with one LF-terminated stdin
/// prompt JSONL command (`{"id":"1","type":"prompt","message":…}`).
/// Pi argv is `--mode rpc --no-session`. Oh My Pi argv matches Waku
/// `PiFlavor::OhMyPi` access (`--mode rpc --yolo`) plus documented
/// omp `--no-session` (Waku model discovery; Faku one-shot has no
/// session-file resume). Native closes stdin after that buffer;
/// stdout is read until process settle (ACP / daemon-proxy one-shot
/// pattern). Composer image attach uses documented RPC `images`
/// (`ImageContent` base64 + mimeType; png/jpeg/gif/webp;
/// `acp.max_image_bytes` raw). Missing / unreadable / unknown type /
/// overflow return false so Send fail-closes to demo. There is no
/// `--image` flag and no `@path` argv. `fx_spawn_pi_json` still means
/// “Pi JSONL stdout parser” (RPC `message_update` / `text_delta`).
/// Not ACP, not acp-proxy, not `--mode json`, not `-p` / `--print`,
/// not `-a` / `--approve` / invented dangerously-* flags, not a
/// long-lived stdin loop / steer / follow_up. Caller sets
/// `reply_path` to `.fx` on success; `fx_spawn_acp` stays false.
/// Project cwd reuses `fx_ask_chdir_script` (Native SpawnOptions has
/// no cwd field); cwd / binary / flags stay argv slots — never
/// interpolated into the chdir `-c` script. Empty binary is a no-op
/// (PATH default is `pi` / `omp`).
pub fn startPiRpc(model: *Model, fx: *Effects, session: *const Session, prompt: []const u8) bool {
    if (!session.provider.speaksPiRpc()) return false;
    const binary = providers.binaryFor(model, session.provider);
    if (binary.len == 0) return false;
    const cwd = model.resolveSpawnCwd(session);
    const image_path = model.draftImagePath();

    var stdin_buf: [pi_rpc_stdin_cap]u8 = undefined;
    var image_raw: [acp.max_image_bytes]u8 = undefined;
    var image: ?acp.ImageContent = null;
    if (image_path.len > 0) {
        const io = model.store_io orelse return false;
        const mime = acp.mimeTypeForImagePath(image_path) orelse return false;
        const bytes = acp.readImageBytes(io, image_path, &image_raw) orelse return false;
        image = .{ .bytes = bytes, .mime_type = mime };
    }
    const stdin = writePiRpcPromptStdin(&stdin_buf, prompt, image) catch return false;

    model.setLastSpawnCwd(cwd);
    model.setLastSpawnImagePath(if (image_path.len > 0) image_path else "");

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
    argv_buf[n] = "rpc";
    n += 1;
    if (session.provider == .ohmypi) {
        argv_buf[n] = "--yolo";
        n += 1;
    }
    argv_buf[n] = "--no-session";
    n += 1;

    model.fx_spawn_acp = false;
    model.fx_spawn_pi_json = true;
    fx.spawn(.{
        .key = allocateFxSpawnKey(model),
        .argv = argv_buf[0..n],
        .stdin = stdin,
        .on_line = Effects.lineMsg(.fx_line),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
    return true;
}

/// One-shot official OpenCode 2 non-interactive run:
/// `{binary} run --format json --auto {prompt}`
/// (https://opencode.ai/docs/cli/). Prompt is an argv slot after the
/// flags (documented `opencode run [message..]`). `--format json`
/// is NDJSON on stdout (`run.ts`:
/// `JSON.stringify({ type, timestamp, sessionID, ...data }) + EOL`;
/// text parts are `type == "text"` with `part.text`). `--auto`
/// auto-approves permissions that are not explicitly denied; this
/// cut always passes it so non-interactive Send does not hang
/// (OpenCode run has no permission UI in Faku; leftover vs a true
/// `ask` mode). When persisted `opencode2_attach_url` trim is
/// non-empty, documented `--attach {url}` is two argv slots after
/// `--auto` (user-owned `opencode2 serve`; Faku does not spawn
/// serve). Empty URL omits both — never a bare `--attach`. When
/// attach URL and persisted `opencode2_server_password` trim are
/// both non-empty, documented `--password {password}` is two argv
/// slots after `--attach {url}` and before `--session` / `--model` /
/// `--file` / prompt. Prefer long `--password` not `-p`. Empty
/// password omits both — never a bare `--password`. When attach URL
/// and persisted `opencode2_server_username` trim are both
/// non-empty, documented `--username {username}` is two argv slots
/// after optional `--password` (do not invent flags). Empty persist
/// omits both — CLI defaults to `opencode`. When
/// `session.fxSessionId()` is non-empty, documented `--session {id}`
/// is two argv slots after `--auto` / optional `--attach` and
/// before optional `--model` / `--file` / the prompt. Empty
/// id omits both — never a bare `--session`. Not `--continue` /
/// `-c`. Optional `--model {session.model()}` when that field is
/// non-empty (documented `provider/model` form; no invented
/// catalog). Composer image/file attach uses documented `--file
/// {path}` (long form; `-f` unused). The path is its own argv
/// slot — never interpolated into the chdir `-c` script. Empty
/// stdin. `fx_spawn_opencode_run_json` routes stdout through the
/// OpenCode run parser (live `type:"text"` / `part.text`, not a
/// prose dump). Capture `sessionID` into `fx_session_id` for later
/// `--session`. Not ACP, not `opencode acp` (that is
/// `ProviderId.opencode`), not acp-proxy, not an in-app HTTP/SSE
/// serve client. Caller sets `reply_path` to `.fx` on success;
/// `fx_spawn_acp` stays false. Project cwd reuses
/// `fx_ask_chdir_script` (Native SpawnOptions has no cwd field;
/// documented `--dir` would duplicate that house-style chdir).
/// Empty binary is a no-op (PATH default is `opencode2`).
pub fn startOpencodeRun(model: *Model, fx: *Effects, session: *const Session, prompt: []const u8) bool {
    if (!session.provider.speaksOpencodeRun()) return false;
    const binary = providers.binaryFor(model, session.provider);
    if (binary.len == 0) return false;
    const cwd = model.resolveSpawnCwd(session);
    const resume_id = session.fxSessionId();
    const model_id = session.model();
    const file_path = model.resolveSpawnImage();
    const attach_url = model.opencode2AttachUrl();
    const password = if (attach_url.len > 0) model.opencode2ServerPassword() else "";
    const username = if (attach_url.len > 0) model.opencode2ServerUsername() else "";

    model.setLastSpawnCwd(cwd);
    model.setLastSpawnImagePath(file_path);

    // Packed Unix chdir when generic host argv would exceed Native
    // `max_effect_argv` 16. `--password` / `--username` stay literals
    // in the `-c` script; cwd / binary / attach / password / username
    // / optionals / prompt stay `$N` slots — never drop attach,
    // password, or username when set.
    const opencode2_run_chdir_password_script =
        "cd -- \"$1\" && exec \"$2\" run --format json --auto --attach \"$3\" --password \"$4\"${5:+ --session \"$5\"}${6:+ --model \"$6\"}${7:+ --file \"$7\"} \"$8\"";
    const opencode2_run_chdir_password_username_script =
        "cd -- \"$1\" && exec \"$2\" run --format json --auto --attach \"$3\" --password \"$4\" --username \"$5\"${6:+ --session \"$6\"}${7:+ --model \"$7\"}${8:+ --file \"$8\"} \"$9\"";
    const opencode2_run_chdir_username_script =
        "cd -- \"$1\" && exec \"$2\" run --format json --auto --attach \"$3\" --username \"$4\"${5:+ --session \"$5\"}${6:+ --model \"$6\"}${7:+ --file \"$7\"} \"$8\"";

    var generic_len: usize = 5; // binary run --format json --auto
    if (cwd.len > 0) generic_len += 5;
    if (attach_url.len > 0) generic_len += 2;
    if (password.len > 0) generic_len += 2;
    if (username.len > 0) generic_len += 2;
    if (resume_id.len > 0) generic_len += 2;
    if (model_id.len > 0) generic_len += 2;
    if (file_path.len > 0) generic_len += 2;
    generic_len += 1; // prompt

    const pack_auth = cwd.len > 0 and attach_url.len > 0 and (password.len > 0 or username.len > 0) and
        generic_len > git_commit_generate.max_effect_argv;

    // chdir (5) + binary + run + --format + json + --auto +
    // --attach + url + --password + password + --username + username +
    // --session + id + --model + id + --file + path + prompt = 23.
    // Packed password+username form is 13. Keep headroom rather than
    // truncating (fake-executor tests).
    var argv_buf: [24][]const u8 = undefined;
    var n: usize = 0;
    if (pack_auth) {
        argv_buf[n] = "/bin/sh";
        n += 1;
        argv_buf[n] = "-c";
        n += 1;
        argv_buf[n] = if (password.len > 0 and username.len > 0)
            opencode2_run_chdir_password_username_script
        else if (password.len > 0)
            opencode2_run_chdir_password_script
        else
            opencode2_run_chdir_username_script;
        n += 1;
        argv_buf[n] = "sh";
        n += 1;
        argv_buf[n] = cwd;
        n += 1;
        argv_buf[n] = binary;
        n += 1;
        argv_buf[n] = attach_url;
        n += 1;
        if (password.len > 0) {
            argv_buf[n] = password;
            n += 1;
        }
        if (username.len > 0) {
            argv_buf[n] = username;
            n += 1;
        }
        argv_buf[n] = resume_id;
        n += 1;
        argv_buf[n] = model_id;
        n += 1;
        argv_buf[n] = file_path;
        n += 1;
        argv_buf[n] = prompt;
        n += 1;
    } else {
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
        argv_buf[n] = "run";
        n += 1;
        argv_buf[n] = "--format";
        n += 1;
        argv_buf[n] = "json";
        n += 1;
        argv_buf[n] = "--auto";
        n += 1;
        if (attach_url.len > 0) {
            argv_buf[n] = "--attach";
            n += 1;
            argv_buf[n] = attach_url;
            n += 1;
        }
        if (password.len > 0) {
            argv_buf[n] = "--password";
            n += 1;
            argv_buf[n] = password;
            n += 1;
        }
        if (username.len > 0) {
            argv_buf[n] = "--username";
            n += 1;
            argv_buf[n] = username;
            n += 1;
        }
        if (resume_id.len > 0) {
            argv_buf[n] = "--session";
            n += 1;
            argv_buf[n] = resume_id;
            n += 1;
        }
        if (model_id.len > 0) {
            argv_buf[n] = "--model";
            n += 1;
            argv_buf[n] = model_id;
            n += 1;
        }
        if (file_path.len > 0) {
            argv_buf[n] = "--file";
            n += 1;
            argv_buf[n] = file_path;
            n += 1;
        }
        argv_buf[n] = prompt;
        n += 1;
    }

    model.fx_spawn_acp = false;
    model.fx_spawn_opencode_run_json = true;
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

fn drainEffects(model: *Model, fx: *Effects) void {
    while (fx.takeMsg()) |msg| main.update(model, msg, fx);
}

fn pendingTimerByKey(fx: *Effects, key: u64) ?@TypeOf(fx.pendingTimerAt(0).?) {
    var i: usize = 0;
    while (fx.pendingTimerAt(i)) |timer| : (i += 1) {
        if (timer.key == key) return timer;
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
    try testing.expectEqual(model_exports.ReplyPath.fx, model.reply_path);
    try testing.expect(model.fx_spawn_acp);
    try testing.expectEqual(@as(usize, 0), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());

    const request = fx.pendingSpawnAt(0).?;
    try testing.expectEqual(effect_keys.fx_ask_key, request.key);
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
    try testing.expectEqual(model_exports.ReplyPath.fx, model.reply_path);
    try testing.expect(model.fx_spawn_acp);
    try testing.expectEqual(@as(usize, 0), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());

    const request = fx.pendingSpawnAt(0).?;
    try testing.expectEqual(effect_keys.fx_ask_key, request.key);
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
    try testing.expectEqual(model_exports.ReplyPath.demo, model.reply_path);
    try testing.expect(!model.fx_spawn_acp);
    try testing.expectEqual(@as(usize, 1), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
}

test "kimi + cli_available selects acp-proxy kimi acp" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setSidecarPath("faku");
    const id = model.addSession("kimi thread", .kimi);
    model.cli_available[@intFromEnum(protocol.ProviderId.kimi)] = true;

    startPrompt(&model, &fx, id, "hello kimi");
    try testing.expectEqual(model_exports.ReplyPath.fx, model.reply_path);
    try testing.expect(model.fx_spawn_acp);
    try testing.expectEqual(@as(usize, 0), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());

    const request = fx.pendingSpawnAt(0).?;
    try testing.expectEqual(effect_keys.fx_ask_key, request.key);
    try testing.expect(testArgvHas(request.argv, acp_proxy.SUBCOMMAND));
    try testing.expect(testArgvHas(request.argv, "--"));
    try testing.expect(testArgvHas(request.argv, "kimi"));
    try testing.expect(testArgvHas(request.argv, "acp"));
    try testing.expect(!testArgvHas(request.argv, "ask"));
    try testing.expect(!testArgvHas(request.argv, "fx"));
    try testing.expect(!testArgvHas(request.argv, "cursor-agent"));
    try testing.expect(!testArgvHas(request.argv, daemon_proxy.SUBCOMMAND));
    const dash = testArgvIndex(request.argv, "--") orelse return error.MissingDash;
    const binary_at = testArgvIndex(request.argv, "kimi") orelse return error.MissingBinary;
    const acp_at = testArgvIndex(request.argv, "acp") orelse return error.MissingAcp;
    try testing.expect(dash < binary_at);
    try testing.expectEqual(binary_at + 1, acp_at);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"method\":\"initialize\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"method\":\"session/new\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"method\":\"session/set_mode\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"method\":\"session/prompt\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "hello kimi") != null);
}

test "kimi unavailable stays demo" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;
    var model = Model{};
    const id = model.addSession("kimi missing", .kimi);
    startPrompt(&model, &fx, id, "no kimi");
    try testing.expectEqual(model_exports.ReplyPath.demo, model.reply_path);
    try testing.expect(!model.fx_spawn_acp);
    try testing.expectEqual(@as(usize, 1), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
}

test "speaksBareAcp is true for cursor, opencode, and kimi; speaksAcpStdio also covers grok and deepseek" {
    const testing = std.testing;
    try testing.expect(protocol.ProviderId.cursor.speaksBareAcp());
    try testing.expect(protocol.ProviderId.opencode.speaksBareAcp());
    try testing.expect(protocol.ProviderId.kimi.speaksBareAcp());
    try testing.expect(!protocol.ProviderId.fx.speaksBareAcp());
    try testing.expect(!protocol.ProviderId.claude.speaksBareAcp());
    try testing.expect(!protocol.ProviderId.codex.speaksBareAcp());
    try testing.expect(!protocol.ProviderId.amp.speaksBareAcp());
    try testing.expect(!protocol.ProviderId.grok.speaksBareAcp());
    try testing.expect(!protocol.ProviderId.pi.speaksBareAcp());
    try testing.expect(!protocol.ProviderId.ohmypi.speaksBareAcp());
    try testing.expect(!protocol.ProviderId.opencode2.speaksBareAcp());
    try testing.expect(!protocol.ProviderId.deepseek.speaksBareAcp());
    try testing.expect(protocol.ProviderId.pi.speaksPiRpc());
    try testing.expect(protocol.ProviderId.ohmypi.speaksPiRpc());
    try testing.expect(!protocol.ProviderId.opencode2.speaksPiRpc());
    try testing.expect(!protocol.ProviderId.deepseek.speaksPiRpc());
    try testing.expect(!protocol.ProviderId.kimi.speaksPiRpc());
    try testing.expect(protocol.ProviderId.opencode2.speaksOpencodeRun());
    try testing.expect(!protocol.ProviderId.opencode.speaksOpencodeRun());
    try testing.expect(!protocol.ProviderId.pi.speaksOpencodeRun());
    try testing.expect(!protocol.ProviderId.fx.speaksOpencodeRun());
    try testing.expect(protocol.ProviderId.cursor.speaksAcpStdio());
    try testing.expect(protocol.ProviderId.opencode.speaksAcpStdio());
    try testing.expect(protocol.ProviderId.kimi.speaksAcpStdio());
    try testing.expect(protocol.ProviderId.grok.speaksAcpStdio());
    try testing.expect(protocol.ProviderId.deepseek.speaksAcpStdio());
    try testing.expect(!protocol.ProviderId.fx.speaksAcpStdio());
    try testing.expect(!protocol.ProviderId.claude.speaksAcpStdio());
    try testing.expect(!protocol.ProviderId.amp.speaksAcpStdio());
    try testing.expect(!protocol.ProviderId.opencode2.speaksAcpStdio());
    try testing.expect(protocol.ProviderId.opencode2.speaksOpencodeRun());
    try testing.expect(!protocol.ProviderId.opencode.speaksOpencodeRun());
    try testing.expectEqualStrings("acp", protocol.ProviderId.kimi.acpTransportArgv()[0]);
    try testing.expectEqual(@as(usize, 1), protocol.ProviderId.kimi.acpTransportArgv().len);
    try testing.expectEqual(@as(usize, 0), protocol.ProviderId.amp.acpTransportArgv().len);
    try testing.expectEqual(@as(usize, 2), protocol.ProviderId.grok.acpTransportArgv().len);
    try testing.expectEqualStrings("agent", protocol.ProviderId.grok.acpTransportArgv()[0]);
    try testing.expectEqualStrings("stdio", protocol.ProviderId.grok.acpTransportArgv()[1]);
    try testing.expectEqual(@as(usize, 2), protocol.ProviderId.deepseek.acpTransportArgv().len);
    try testing.expectEqualStrings("--profile", protocol.ProviderId.deepseek.acpTransportArgv()[0]);
    try testing.expectEqualStrings("acp", protocol.ProviderId.deepseek.acpTransportArgv()[1]);
}

test "cursor unavailable stays demo" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;
    var model = Model{};
    const cursor_id = model.addSession("cursor missing", .cursor);
    startPrompt(&model, &fx, cursor_id, "no cursor-agent");
    try testing.expectEqual(model_exports.ReplyPath.demo, model.reply_path);
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
    try testing.expectEqual(model_exports.ReplyPath.fx, model.reply_path);
    try testing.expect(model.fx_spawn_acp);
    try testing.expectEqual(@as(usize, 0), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());

    const request = fx.pendingSpawnAt(0).?;
    try testing.expectEqual(effect_keys.fx_ask_key, request.key);
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
    try testing.expectEqual(model_exports.ReplyPath.demo, model.reply_path);
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
    try testing.expectEqual(model_exports.ReplyPath.fx, model.reply_path);
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
    try testing.expectEqual(model_exports.ReplyPath.fx, model.reply_path);
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

test "kimi image attach uses ACP image content block" {
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
    model.cli_available[@intFromEnum(protocol.ProviderId.kimi)] = true;
    const id = model.addSession("kimi image", .kimi);
    model.selected = id;
    model.setDraftImagePath(image);

    startPrompt(&model, &fx, id, "describe this");
    try testing.expectEqual(model_exports.ReplyPath.fx, model.reply_path);
    try testing.expect(model.fx_spawn_acp);
    try testing.expectEqual(@as(usize, 0), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());
    try testing.expectEqualStrings(image, model.lastSpawnImagePath());

    const request = fx.pendingSpawnAt(0).?;
    try testing.expect(testArgvHas(request.argv, acp_proxy.SUBCOMMAND));
    try testing.expect(testArgvHas(request.argv, "kimi"));
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
    try testing.expectEqual(model_exports.ReplyPath.demo, model.reply_path);
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
    try testing.expectEqual(model_exports.ReplyPath.demo, model.reply_path);
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
    try testing.expectEqual(model_exports.ReplyPath.demo, model.reply_path);
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
    try testing.expectEqual(model_exports.ReplyPath.fx, model.reply_path);
    try testing.expect(!model.fx_spawn_acp);
    try testing.expect(model.fx_spawn_claude_json);
    try testing.expect(!model.fx_spawn_pi_json);
    try testing.expectEqual(@as(usize, 0), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());

    const request = fx.pendingSpawnAt(0).?;
    try testing.expectEqual(effect_keys.fx_ask_key, request.key);
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
    try testing.expectEqual(model_exports.ReplyPath.fx, model.reply_path);
    try testing.expect(!model.fx_spawn_acp);
    try testing.expect(model.fx_spawn_claude_json);
    try testing.expect(!model.fx_spawn_pi_json);
    try testing.expectEqual(@as(usize, 0), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());

    const request = fx.pendingSpawnAt(0).?;
    try testing.expectEqual(effect_keys.fx_ask_key, request.key);
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
    try testing.expectEqual(model_exports.ReplyPath.fx, model.reply_path);
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
    try testing.expectEqual(model_exports.ReplyPath.demo, model.reply_path);
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
    try testing.expectEqual(model_exports.ReplyPath.fx, model.reply_path);
    try testing.expect(!model.fx_spawn_acp);
    try testing.expectEqual(@as(usize, 0), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());

    const request = fx.pendingSpawnAt(0).?;
    try testing.expectEqual(effect_keys.fx_ask_key, request.key);
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
    try testing.expectEqual(model_exports.ReplyPath.demo, model.reply_path);
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
    try testing.expectEqual(model_exports.ReplyPath.fx, model.reply_path);
    try testing.expect(!model.fx_spawn_acp);
    try testing.expectEqual(@as(usize, 0), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());

    const request = fx.pendingSpawnAt(0).?;
    try testing.expectEqual(effect_keys.fx_ask_key, request.key);
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
    try testing.expectEqual(model_exports.ReplyPath.demo, model.reply_path);
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
    try testing.expectEqual(model_exports.ReplyPath.fx, model.reply_path);
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
    try testing.expectEqual(model_exports.ReplyPath.demo, model.reply_path);
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
    try testing.expectEqual(model_exports.ReplyPath.fx, model.reply_path);
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
    try testing.expectEqual(model_exports.ReplyPath.demo, model.reply_path);
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
    try testing.expectEqual(model_exports.ReplyPath.fx, model.reply_path);
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

test "pi + cli_available selects one-shot pi --mode rpc --no-session with stdin prompt" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setSidecarPath("faku");
    const id = model.addSession("pi thread", .pi);
    model.cli_available[@intFromEnum(protocol.ProviderId.pi)] = true;

    startPrompt(&model, &fx, id, "hello pi");
    try testing.expectEqual(model_exports.ReplyPath.fx, model.reply_path);
    try testing.expect(!model.fx_spawn_acp);
    try testing.expect(model.fx_spawn_pi_json);
    try testing.expect(!model.fx_spawn_claude_json);
    try testing.expectEqual(@as(usize, 0), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());

    const request = fx.pendingSpawnAt(0).?;
    try testing.expectEqual(effect_keys.fx_ask_key, request.key);
    try testing.expect(testArgvHas(request.argv, "pi"));
    try testing.expect(testArgvHas(request.argv, "--mode"));
    try testing.expect(testArgvHas(request.argv, "rpc"));
    try testing.expect(testArgvHas(request.argv, "--no-session"));
    try testing.expect(!testArgvHas(request.argv, "hello pi"));
    try testing.expect(!testArgvHas(request.argv, "json"));
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
    try testing.expect(!testArgvHas(request.argv, "-a"));
    try testing.expect(!testArgvHas(request.argv, "--approve"));
    try testing.expect(!testArgvHas(request.argv, "--no-approve"));
    try testing.expect(!testArgvHas(request.argv, "--dangerously-skip-permissions"));
    try testing.expect(!testArgvHas(request.argv, "--dangerously-allow-all"));
    try testing.expect(!testArgvHas(request.argv, daemon_proxy.SUBCOMMAND));
    try testing.expect(!testArgvHas(request.argv, "--image"));
    try testing.expectEqualStrings("{\"id\":\"1\",\"type\":\"prompt\",\"message\":\"hello pi\"}\n", request.stdin);
    try testing.expectEqualStrings("", model.lastSpawnImagePath());
    const binary_at = testArgvIndex(request.argv, "pi") orelse return error.MissingBinary;
    const mode_at = testArgvIndex(request.argv, "--mode") orelse return error.MissingMode;
    const rpc_at = testArgvIndex(request.argv, "rpc") orelse return error.MissingRpc;
    const no_session_at = testArgvIndex(request.argv, "--no-session") orelse return error.MissingNoSession;
    try testing.expectEqual(binary_at + 1, mode_at);
    try testing.expectEqual(mode_at + 1, rpc_at);
    try testing.expectEqual(rpc_at + 1, no_session_at);
    try testing.expectEqual(no_session_at + 1, request.argv.len);
}

test "pi unavailable stays demo" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;
    var model = Model{};
    const id = model.addSession("pi missing", .pi);
    startPrompt(&model, &fx, id, "no pi");
    try testing.expectEqual(model_exports.ReplyPath.demo, model.reply_path);
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
    try testing.expectEqual(model_exports.ReplyPath.fx, model.reply_path);
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
    try testing.expectEqual(model_exports.ReplyPath.demo, model.reply_path);
    try testing.expect(!model.fx_spawn_acp);
    try testing.expectEqual(@as(usize, 1), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
}

test "pi image attach uses RPC images on the stdin prompt command" {
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
    try testing.expectEqual(model_exports.ReplyPath.fx, model.reply_path);
    try testing.expect(!model.fx_spawn_acp);
    try testing.expect(model.fx_spawn_pi_json);
    try testing.expectEqual(@as(usize, 0), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());
    try testing.expectEqualStrings(image, model.lastSpawnImagePath());

    const request = fx.pendingSpawnAt(0).?;
    try testing.expect(testArgvHas(request.argv, "pi"));
    try testing.expect(testArgvHas(request.argv, "--mode"));
    try testing.expect(testArgvHas(request.argv, "rpc"));
    try testing.expect(testArgvHas(request.argv, "--no-session"));
    try testing.expect(!testArgvHas(request.argv, "describe this"));
    try testing.expect(!testArgvHas(request.argv, image));
    try testing.expect(!testArgvHas(request.argv, "--image"));
    try testing.expect(!testArgvHas(request.argv, "json"));
    try testing.expect(!testArgvHas(request.argv, "-p"));
    try testing.expect(!testArgvHas(request.argv, "--print"));
    try testing.expect(!testArgvHas(request.argv, "-a"));
    try testing.expect(!testArgvHas(request.argv, "--approve"));
    try testing.expect(!testArgvHas(request.argv, acp_proxy.SUBCOMMAND));
    try testing.expect(!testArgvHas(request.argv, "ask"));
    try testing.expect(!testArgvHas(request.argv, "fx"));
    try testing.expect(!testArgvHas(request.argv, daemon_proxy.SUBCOMMAND));
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"type\":\"prompt\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"message\":\"describe this\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"images\":[{\"type\":\"image\",\"data\":\"cG5n\",\"mimeType\":\"image/png\"}]") != null);
    try testing.expect(std.mem.endsWith(u8, request.stdin, "\n"));
    const binary_at = testArgvIndex(request.argv, "pi") orelse return error.MissingBinary;
    const mode_at = testArgvIndex(request.argv, "--mode") orelse return error.MissingMode;
    const rpc_at = testArgvIndex(request.argv, "rpc") orelse return error.MissingRpc;
    const no_session_at = testArgvIndex(request.argv, "--no-session") orelse return error.MissingNoSession;
    try testing.expectEqual(binary_at + 1, mode_at);
    try testing.expectEqual(mode_at + 1, rpc_at);
    try testing.expectEqual(rpc_at + 1, no_session_at);
    try testing.expectEqual(no_session_at + 1, request.argv.len);
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
    try testing.expectEqual(model_exports.ReplyPath.demo, model.reply_path);
    try testing.expect(!model.fx_spawn_acp);
    try testing.expect(!model.fx_spawn_pi_json);
    try testing.expectEqual(@as(usize, 1), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
}

test "pi image attach unknown type stays demo" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var image_buf: [256]u8 = undefined;
    const image = try std.fmt.bufPrint(&image_buf, ".zig-cache/tmp/{s}/pi.bmp", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().writeFile(testing.io, .{ .sub_path = image, .data = "bmp" });

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = testing.io;
    model.setSidecarPath("faku");
    model.cli_available[@intFromEnum(protocol.ProviderId.pi)] = true;
    const id = model.addSession("pi bmp", .pi);
    model.selected = id;
    model.setDraftImagePath(image);

    startPrompt(&model, &fx, id, "describe this");
    try testing.expectEqual(model_exports.ReplyPath.demo, model.reply_path);
    try testing.expect(!model.fx_spawn_acp);
    try testing.expect(!model.fx_spawn_pi_json);
    try testing.expectEqual(@as(usize, 1), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
}

test "pi image attach overflow stays demo" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var image_buf: [256]u8 = undefined;
    const image = try std.fmt.bufPrint(&image_buf, ".zig-cache/tmp/{s}/pi-over.png", .{tmp.sub_path[0..]});
    var over: [acp.max_image_bytes + 1]u8 = undefined;
    @memset(&over, 'A');
    try std.Io.Dir.cwd().writeFile(testing.io, .{ .sub_path = image, .data = &over });

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = testing.io;
    model.setSidecarPath("faku");
    model.cli_available[@intFromEnum(protocol.ProviderId.pi)] = true;
    const id = model.addSession("pi overflow", .pi);
    model.selected = id;
    model.setDraftImagePath(image);

    startPrompt(&model, &fx, id, "describe this");
    try testing.expectEqual(model_exports.ReplyPath.demo, model.reply_path);
    try testing.expect(!model.fx_spawn_acp);
    try testing.expect(!model.fx_spawn_pi_json);
    try testing.expectEqual(@as(usize, 1), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
}

test "pi image attach missing file stays demo" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = testing.io;
    model.setSidecarPath("faku");
    model.cli_available[@intFromEnum(protocol.ProviderId.pi)] = true;
    const id = model.addSession("pi missing file", .pi);
    model.selected = id;
    model.setDraftImagePath(".zig-cache/tmp/faku-pi-image-missing.png");

    startPrompt(&model, &fx, id, "describe this");
    try testing.expectEqual(model_exports.ReplyPath.demo, model.reply_path);
    try testing.expect(!model.fx_spawn_acp);
    try testing.expect(!model.fx_spawn_pi_json);
    try testing.expectEqual(@as(usize, 1), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
}

test "pi rpc reuses fx_ask_chdir_script when project cwd exists" {
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
    try testing.expectEqual(model_exports.ReplyPath.fx, model.reply_path);
    try testing.expect(!model.fx_spawn_acp);
    try testing.expect(model.fx_spawn_pi_json);
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());
    const request = fx.pendingSpawnAt(0).?;
    try testing.expect(testArgvHas(request.argv, "/bin/sh"));
    try testing.expect(testArgvHas(request.argv, "-c"));
    try testing.expect(testArgvHas(request.argv, fx_ask_chdir_script));
    try testing.expect(testArgvHas(request.argv, project));
    try testing.expect(!testArgvHas(request.argv, "in project"));
    try testing.expectEqualStrings("{\"id\":\"1\",\"type\":\"prompt\",\"message\":\"in project\"}\n", request.stdin);
    const binary_at = testArgvIndex(request.argv, "pi") orelse return error.MissingBinary;
    const mode_at = testArgvIndex(request.argv, "--mode") orelse return error.MissingMode;
    const rpc_at = testArgvIndex(request.argv, "rpc") orelse return error.MissingRpc;
    const no_session_at = testArgvIndex(request.argv, "--no-session") orelse return error.MissingNoSession;
    try testing.expect(binary_at > 0);
    try testing.expectEqual(binary_at + 1, mode_at);
    try testing.expectEqual(mode_at + 1, rpc_at);
    try testing.expectEqual(rpc_at + 1, no_session_at);
    try testing.expectEqual(no_session_at + 1, request.argv.len);
    try testing.expectEqualStrings(project, request.argv[binary_at - 1]);
}

test "writePiRpcPromptStdin builds one LF-terminated prompt JSONL line" {
    const testing = std.testing;
    var buf: [256]u8 = undefined;
    const line = try writePiRpcPromptStdin(&buf, "hello", null);
    try testing.expectEqualStrings("{\"id\":\"1\",\"type\":\"prompt\",\"message\":\"hello\"}\n", line);

    const escaped = try writePiRpcPromptStdin(&buf, "say \"hi\"\nnext", null);
    try testing.expectEqualStrings("{\"id\":\"1\",\"type\":\"prompt\",\"message\":\"say \\\"hi\\\"\\nnext\"}\n", escaped);

    const with_image = try writePiRpcPromptStdin(&buf, "look", .{ .bytes = "png", .mime_type = "image/png" });
    try testing.expectEqualStrings(
        "{\"id\":\"1\",\"type\":\"prompt\",\"message\":\"look\",\"images\":[{\"type\":\"image\",\"data\":\"cG5n\",\"mimeType\":\"image/png\"}]}\n",
        with_image,
    );

    var tiny: [8]u8 = undefined;
    try testing.expectError(error.NoSpaceLeft, writePiRpcPromptStdin(&tiny, "hello", null));
}

test "ohmypi + cli_available selects one-shot omp --mode rpc --yolo --no-session with stdin prompt" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setSidecarPath("faku");
    const id = model.addSession("ohmypi thread", .ohmypi);
    model.cli_available[@intFromEnum(protocol.ProviderId.ohmypi)] = true;

    startPrompt(&model, &fx, id, "hello omp");
    try testing.expectEqual(model_exports.ReplyPath.fx, model.reply_path);
    try testing.expect(!model.fx_spawn_acp);
    try testing.expect(model.fx_spawn_pi_json);
    try testing.expect(!model.fx_spawn_claude_json);
    try testing.expectEqual(@as(usize, 0), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());

    const request = fx.pendingSpawnAt(0).?;
    try testing.expectEqual(effect_keys.fx_ask_key, request.key);
    try testing.expect(testArgvHas(request.argv, "omp"));
    try testing.expect(testArgvHas(request.argv, "--mode"));
    try testing.expect(testArgvHas(request.argv, "rpc"));
    try testing.expect(testArgvHas(request.argv, "--yolo"));
    try testing.expect(testArgvHas(request.argv, "--no-session"));
    try testing.expect(!testArgvHas(request.argv, "hello omp"));
    try testing.expect(!testArgvHas(request.argv, "pi"));
    try testing.expect(!testArgvHas(request.argv, "json"));
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
    try testing.expect(!testArgvHas(request.argv, "-a"));
    try testing.expect(!testArgvHas(request.argv, "--approve"));
    try testing.expect(!testArgvHas(request.argv, "--no-approve"));
    try testing.expect(!testArgvHas(request.argv, "--dangerously-skip-permissions"));
    try testing.expect(!testArgvHas(request.argv, "--dangerously-allow-all"));
    try testing.expect(!testArgvHas(request.argv, daemon_proxy.SUBCOMMAND));
    try testing.expect(!testArgvHas(request.argv, "--image"));
    try testing.expectEqualStrings("{\"id\":\"1\",\"type\":\"prompt\",\"message\":\"hello omp\"}\n", request.stdin);
    try testing.expectEqualStrings("", model.lastSpawnImagePath());
    const binary_at = testArgvIndex(request.argv, "omp") orelse return error.MissingBinary;
    const mode_at = testArgvIndex(request.argv, "--mode") orelse return error.MissingMode;
    const rpc_at = testArgvIndex(request.argv, "rpc") orelse return error.MissingRpc;
    const yolo_at = testArgvIndex(request.argv, "--yolo") orelse return error.MissingYolo;
    const no_session_at = testArgvIndex(request.argv, "--no-session") orelse return error.MissingNoSession;
    try testing.expectEqual(binary_at + 1, mode_at);
    try testing.expectEqual(mode_at + 1, rpc_at);
    try testing.expectEqual(rpc_at + 1, yolo_at);
    try testing.expectEqual(yolo_at + 1, no_session_at);
    try testing.expectEqual(no_session_at + 1, request.argv.len);
}

test "ohmypi unavailable stays demo" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;
    var model = Model{};
    const id = model.addSession("ohmypi missing", .ohmypi);
    startPrompt(&model, &fx, id, "no omp");
    try testing.expectEqual(model_exports.ReplyPath.demo, model.reply_path);
    try testing.expect(!model.fx_spawn_acp);
    try testing.expect(!model.fx_spawn_pi_json);
    try testing.expectEqual(@as(usize, 1), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
}

test "opencode2 + cli_available selects run --format json --auto" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setSidecarPath("faku");
    model.cli_available[@intFromEnum(protocol.ProviderId.opencode2)] = true;
    const id = model.addSession("opencode2 thread", .opencode2);
    startPrompt(&model, &fx, id, "hello opencode2");
    try testing.expectEqual(model_exports.ReplyPath.fx, model.reply_path);
    try testing.expect(!model.fx_spawn_acp);
    try testing.expect(!model.fx_spawn_pi_json);
    try testing.expect(!model.fx_spawn_claude_json);
    try testing.expect(model.fx_spawn_opencode_run_json);
    try testing.expectEqual(@as(usize, 0), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());
    try testing.expect(protocol.ProviderId.opencode2.speaksOpencodeRun());
    try testing.expect(!protocol.ProviderId.opencode2.speaksBareAcp());
    try testing.expect(!protocol.ProviderId.opencode2.speaksPiRpc());
    try testing.expect(!protocol.ProviderId.opencode2.speaksAcpStdio());

    const request = fx.pendingSpawnAt(0).?;
    try testing.expectEqual(effect_keys.fx_ask_key, request.key);
    try testing.expect(testArgvHas(request.argv, "opencode2"));
    try testing.expect(testArgvHas(request.argv, "run"));
    try testing.expect(testArgvHas(request.argv, "--format"));
    try testing.expect(testArgvHas(request.argv, "json"));
    try testing.expect(testArgvHas(request.argv, "--auto"));
    try testing.expect(testArgvHas(request.argv, "hello opencode2"));
    try testing.expect(!testArgvHas(request.argv, acp_proxy.SUBCOMMAND));
    try testing.expect(!testArgvHas(request.argv, "acp"));
    try testing.expect(!testArgvHas(request.argv, "agent"));
    try testing.expect(!testArgvHas(request.argv, "stdio"));
    try testing.expect(!testArgvHas(request.argv, "ask"));
    try testing.expect(!testArgvHas(request.argv, "fx"));
    try testing.expect(!testArgvHas(request.argv, "serve"));
    try testing.expect(!testArgvHas(request.argv, "--attach"));
    try testing.expect(!testArgvHas(request.argv, "--continue"));
    try testing.expect(!testArgvHas(request.argv, "-c"));
    try testing.expect(!testArgvHas(request.argv, "--session"));
    try testing.expect(!testArgvHas(request.argv, "--model"));
    try testing.expect(!testArgvHas(request.argv, "--file"));
    try testing.expect(!testArgvHas(request.argv, "-f"));
    try testing.expect(!testArgvHas(request.argv, "--dir"));
    try testing.expect(!testArgvHas(request.argv, "--resume"));
    try testing.expect(!testArgvHas(request.argv, daemon_proxy.SUBCOMMAND));
    try testing.expectEqualStrings("", request.stdin);
    try testing.expectEqualStrings("", model.lastSpawnImagePath());
    const binary_at = testArgvIndex(request.argv, "opencode2") orelse return error.MissingBinary;
    const run_at = testArgvIndex(request.argv, "run") orelse return error.MissingRun;
    const format_at = testArgvIndex(request.argv, "--format") orelse return error.MissingFormat;
    const json_at = testArgvIndex(request.argv, "json") orelse return error.MissingJson;
    const auto_at = testArgvIndex(request.argv, "--auto") orelse return error.MissingAuto;
    const prompt_at = testArgvIndex(request.argv, "hello opencode2") orelse return error.MissingPrompt;
    try testing.expectEqual(binary_at + 1, run_at);
    try testing.expectEqual(run_at + 1, format_at);
    try testing.expectEqual(format_at + 1, json_at);
    try testing.expectEqual(json_at + 1, auto_at);
    try testing.expectEqual(auto_at + 1, prompt_at);
}

test "opencode2 + opencode2_attach_url passes --attach then the URL as separate slots" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setSidecarPath("faku");
    model.cli_available[@intFromEnum(protocol.ProviderId.opencode2)] = true;
    model.setOpencode2AttachUrl("http://localhost:4096");
    const id = model.addSession("opencode2 attach", .opencode2);
    startPrompt(&model, &fx, id, "hello attach");
    try testing.expectEqual(model_exports.ReplyPath.fx, model.reply_path);
    try testing.expect(model.fx_spawn_opencode_run_json);
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());

    const request = fx.pendingSpawnAt(0).?;
    try testing.expect(testArgvHas(request.argv, "opencode2"));
    try testing.expect(testArgvHas(request.argv, "run"));
    try testing.expect(testArgvHas(request.argv, "--format"));
    try testing.expect(testArgvHas(request.argv, "json"));
    try testing.expect(testArgvHas(request.argv, "--auto"));
    try testing.expect(testArgvHas(request.argv, "--attach"));
    try testing.expect(testArgvHas(request.argv, "http://localhost:4096"));
    try testing.expect(testArgvHas(request.argv, "hello attach"));
    try testing.expect(!testArgvHas(request.argv, "serve"));
    try testing.expect(!testArgvHas(request.argv, "--password"));
    try testing.expect(!testArgvHas(request.argv, "--username"));
    try testing.expect(!testArgvHas(request.argv, "opencode run --attach http://localhost:4096"));
    const auto_at = testArgvIndex(request.argv, "--auto") orelse return error.MissingAuto;
    const attach_at = testArgvIndex(request.argv, "--attach") orelse return error.MissingAttach;
    const prompt_at = testArgvIndex(request.argv, "hello attach") orelse return error.MissingPrompt;
    try testing.expectEqual(auto_at + 1, attach_at);
    try testing.expectEqualStrings("http://localhost:4096", request.argv[attach_at + 1]);
    try testing.expectEqual(attach_at + 2, prompt_at);
}

test "opencode2 + attach URL + password passes --password then the password as separate slots" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setSidecarPath("faku");
    model.cli_available[@intFromEnum(protocol.ProviderId.opencode2)] = true;
    model.setOpencode2AttachUrl("http://localhost:4096");
    model.setOpencode2ServerPassword("s3cret");
    const id = model.addSession("opencode2 password", .opencode2);
    startPrompt(&model, &fx, id, "hello password");
    try testing.expectEqual(model_exports.ReplyPath.fx, model.reply_path);
    try testing.expect(model.fx_spawn_opencode_run_json);
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());

    const request = fx.pendingSpawnAt(0).?;
    try testing.expect(testArgvHas(request.argv, "opencode2"));
    try testing.expect(testArgvHas(request.argv, "run"));
    try testing.expect(testArgvHas(request.argv, "--attach"));
    try testing.expect(testArgvHas(request.argv, "http://localhost:4096"));
    try testing.expect(testArgvHas(request.argv, "--password"));
    try testing.expect(testArgvHas(request.argv, "s3cret"));
    try testing.expect(testArgvHas(request.argv, "hello password"));
    try testing.expect(!testArgvHas(request.argv, "--username"));
    try testing.expect(!testArgvHas(request.argv, "-p"));
    try testing.expect(!testArgvHas(request.argv, "-u"));
    try testing.expect(!testArgvHas(request.argv, "serve"));
    const attach_at = testArgvIndex(request.argv, "--attach") orelse return error.MissingAttach;
    const password_at = testArgvIndex(request.argv, "--password") orelse return error.MissingPassword;
    const prompt_at = testArgvIndex(request.argv, "hello password") orelse return error.MissingPrompt;
    try testing.expectEqual(attach_at + 2, password_at);
    try testing.expectEqualStrings("s3cret", request.argv[password_at + 1]);
    try testing.expectEqual(password_at + 2, prompt_at);
}

test "opencode2 + attach URL without password omits --password and --username" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setSidecarPath("faku");
    model.cli_available[@intFromEnum(protocol.ProviderId.opencode2)] = true;
    model.setOpencode2AttachUrl("http://localhost:4096");
    model.setOpencode2ServerPassword("   ");
    const id = model.addSession("opencode2 blank password", .opencode2);
    startPrompt(&model, &fx, id, "hello blank password");
    const request = fx.pendingSpawnAt(0).?;
    try testing.expect(testArgvHas(request.argv, "--attach"));
    try testing.expect(!testArgvHas(request.argv, "--password"));
    try testing.expect(!testArgvHas(request.argv, "--username"));
}

test "opencode2 password without attach URL omits --password" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setSidecarPath("faku");
    model.cli_available[@intFromEnum(protocol.ProviderId.opencode2)] = true;
    model.setOpencode2ServerPassword("s3cret");
    const id = model.addSession("opencode2 password no attach", .opencode2);
    startPrompt(&model, &fx, id, "hello no attach");
    const request = fx.pendingSpawnAt(0).?;
    try testing.expect(!testArgvHas(request.argv, "--attach"));
    try testing.expect(!testArgvHas(request.argv, "--password"));
    try testing.expect(!testArgvHas(request.argv, "--username"));
}

test "opencode2 chdir + attach + password + session + model + file packs --password into the Unix chdir script" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/opencode2-pw-cwd", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(testing.io, project);
    var image_buf: [256]u8 = undefined;
    const image = try std.fmt.bufPrint(&image_buf, ".zig-cache/tmp/{s}/opencode2-pw-shot.png", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().writeFile(testing.io, .{ .sub_path = image, .data = "png" });

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = testing.io;
    model.setSidecarPath("faku");
    model.cli_available[@intFromEnum(protocol.ProviderId.opencode2)] = true;
    model.setOpencode2AttachUrl("http://localhost:4096");
    model.setOpencode2ServerPassword("s3cret");
    const id = model.addSession("opencode2 packed password", .opencode2);
    model.selected = id;
    model.setDraftImagePath(image);
    if (model.sessionById(id)) |session| {
        session.setProjectPath(project);
        session.setFxSessionId("oc2-sess-pack");
        session.setModel("opencode/gpt-5");
    }

    startPrompt(&model, &fx, id, "packed prompt");
    try testing.expectEqual(model_exports.ReplyPath.fx, model.reply_path);
    const request = fx.pendingSpawnAt(0).?;
    try testing.expect(testArgvHas(request.argv, "/bin/sh"));
    try testing.expect(testArgvHas(request.argv, "-c"));
    try testing.expect(request.argv.len <= git_commit_generate.max_effect_argv);
    try testing.expect(std.mem.indexOf(u8, request.argv[2], "--password") != null);
    try testing.expect(testArgvHas(request.argv, "http://localhost:4096"));
    try testing.expect(testArgvHas(request.argv, "s3cret"));
    try testing.expect(testArgvHas(request.argv, "oc2-sess-pack"));
    try testing.expect(testArgvHas(request.argv, "opencode/gpt-5"));
    try testing.expect(testArgvHas(request.argv, image));
    try testing.expect(testArgvHas(request.argv, "packed prompt"));
    try testing.expect(!testArgvHas(request.argv, "--username"));
    try testing.expectEqualStrings("s3cret", request.argv[7]);
}

test "opencode2 + attach URL + password + username passes --username then the username as separate slots" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setSidecarPath("faku");
    model.cli_available[@intFromEnum(protocol.ProviderId.opencode2)] = true;
    model.setOpencode2AttachUrl("http://localhost:4096");
    model.setOpencode2ServerPassword("s3cret");
    model.setOpencode2ServerUsername("alice");
    const id = model.addSession("opencode2 username", .opencode2);
    startPrompt(&model, &fx, id, "hello username");
    try testing.expectEqual(model_exports.ReplyPath.fx, model.reply_path);
    try testing.expect(model.fx_spawn_opencode_run_json);
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());

    const request = fx.pendingSpawnAt(0).?;
    try testing.expect(testArgvHas(request.argv, "--attach"));
    try testing.expect(testArgvHas(request.argv, "http://localhost:4096"));
    try testing.expect(testArgvHas(request.argv, "--password"));
    try testing.expect(testArgvHas(request.argv, "s3cret"));
    try testing.expect(testArgvHas(request.argv, "--username"));
    try testing.expect(testArgvHas(request.argv, "alice"));
    try testing.expect(testArgvHas(request.argv, "hello username"));
    try testing.expect(!testArgvHas(request.argv, "-u"));
    try testing.expect(!testArgvHas(request.argv, "serve"));
    const password_at = testArgvIndex(request.argv, "--password") orelse return error.MissingPassword;
    const username_at = testArgvIndex(request.argv, "--username") orelse return error.MissingUsername;
    const prompt_at = testArgvIndex(request.argv, "hello username") orelse return error.MissingPrompt;
    try testing.expectEqual(password_at + 2, username_at);
    try testing.expectEqualStrings("alice", request.argv[username_at + 1]);
    try testing.expectEqual(username_at + 2, prompt_at);
}

test "opencode2 + attach URL + username without password passes --username only" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setSidecarPath("faku");
    model.cli_available[@intFromEnum(protocol.ProviderId.opencode2)] = true;
    model.setOpencode2AttachUrl("http://localhost:4096");
    model.setOpencode2ServerUsername("alice");
    const id = model.addSession("opencode2 username no password", .opencode2);
    startPrompt(&model, &fx, id, "hello user only");
    const request = fx.pendingSpawnAt(0).?;
    try testing.expect(testArgvHas(request.argv, "--attach"));
    try testing.expect(testArgvHas(request.argv, "--username"));
    try testing.expect(testArgvHas(request.argv, "alice"));
    try testing.expect(!testArgvHas(request.argv, "--password"));
}

test "opencode2 username without attach URL omits --username" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setSidecarPath("faku");
    model.cli_available[@intFromEnum(protocol.ProviderId.opencode2)] = true;
    model.setOpencode2ServerUsername("alice");
    const id = model.addSession("opencode2 username no attach", .opencode2);
    startPrompt(&model, &fx, id, "hello no attach user");
    const request = fx.pendingSpawnAt(0).?;
    try testing.expect(!testArgvHas(request.argv, "--attach"));
    try testing.expect(!testArgvHas(request.argv, "--username"));
    try testing.expect(!testArgvHas(request.argv, "--password"));
}

test "opencode2 chdir + attach + password + username + session + model + file packs --username into the Unix chdir script" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/opencode2-user-cwd", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(testing.io, project);
    var image_buf: [256]u8 = undefined;
    const image = try std.fmt.bufPrint(&image_buf, ".zig-cache/tmp/{s}/opencode2-user-shot.png", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().writeFile(testing.io, .{ .sub_path = image, .data = "png" });

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = testing.io;
    model.setSidecarPath("faku");
    model.cli_available[@intFromEnum(protocol.ProviderId.opencode2)] = true;
    model.setOpencode2AttachUrl("http://localhost:4096");
    model.setOpencode2ServerPassword("s3cret");
    model.setOpencode2ServerUsername("alice");
    const id = model.addSession("opencode2 packed username", .opencode2);
    model.selected = id;
    model.setDraftImagePath(image);
    if (model.sessionById(id)) |session| {
        session.setProjectPath(project);
        session.setFxSessionId("oc2-sess-user");
        session.setModel("opencode/gpt-5");
    }

    startPrompt(&model, &fx, id, "packed user prompt");
    try testing.expectEqual(model_exports.ReplyPath.fx, model.reply_path);
    const request = fx.pendingSpawnAt(0).?;
    try testing.expect(testArgvHas(request.argv, "/bin/sh"));
    try testing.expect(testArgvHas(request.argv, "-c"));
    try testing.expect(request.argv.len <= git_commit_generate.max_effect_argv);
    try testing.expect(std.mem.indexOf(u8, request.argv[2], "--password") != null);
    try testing.expect(std.mem.indexOf(u8, request.argv[2], "--username") != null);
    try testing.expect(testArgvHas(request.argv, "http://localhost:4096"));
    try testing.expect(testArgvHas(request.argv, "s3cret"));
    try testing.expect(testArgvHas(request.argv, "alice"));
    try testing.expect(testArgvHas(request.argv, "oc2-sess-user"));
    try testing.expect(testArgvHas(request.argv, "opencode/gpt-5"));
    try testing.expect(testArgvHas(request.argv, image));
    try testing.expect(testArgvHas(request.argv, "packed user prompt"));
    try testing.expectEqualStrings("s3cret", request.argv[7]);
    try testing.expectEqualStrings("alice", request.argv[8]);
}

test "opencode2 whitespace-only attach URL omits --attach" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setSidecarPath("faku");
    model.cli_available[@intFromEnum(protocol.ProviderId.opencode2)] = true;
    model.setOpencode2AttachUrl("   ");
    const id = model.addSession("opencode2 blank attach", .opencode2);
    startPrompt(&model, &fx, id, "hello blank");
    try testing.expectEqual(model_exports.ReplyPath.fx, model.reply_path);
    const request = fx.pendingSpawnAt(0).?;
    try testing.expect(!testArgvHas(request.argv, "--attach"));
}

test "opencode2 unavailable stays demo" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;
    var model = Model{};
    const id = model.addSession("opencode2 missing", .opencode2);
    startPrompt(&model, &fx, id, "no opencode2");
    try testing.expectEqual(model_exports.ReplyPath.demo, model.reply_path);
    try testing.expect(!model.fx_spawn_acp);
    try testing.expect(!model.fx_spawn_pi_json);
    try testing.expect(!model.fx_spawn_claude_json);
    try testing.expect(!model.fx_spawn_opencode_run_json);
    try testing.expectEqual(@as(usize, 1), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
}

test "opencode2 + stored fx_session_id resumes with --session {id}" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setSidecarPath("faku");
    model.cli_available[@intFromEnum(protocol.ProviderId.opencode2)] = true;
    const id = model.addSession("opencode2 resume", .opencode2);
    if (model.sessionById(id)) |session| session.setFxSessionId("oc2-sess-resume-1");

    startPrompt(&model, &fx, id, "continue that review");
    try testing.expectEqual(model_exports.ReplyPath.fx, model.reply_path);
    try testing.expect(!model.fx_spawn_acp);
    try testing.expect(model.fx_spawn_opencode_run_json);
    try testing.expectEqual(@as(usize, 0), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());

    const request = fx.pendingSpawnAt(0).?;
    try testing.expect(testArgvHas(request.argv, "opencode2"));
    try testing.expect(testArgvHas(request.argv, "run"));
    try testing.expect(testArgvHas(request.argv, "--format"));
    try testing.expect(testArgvHas(request.argv, "json"));
    try testing.expect(testArgvHas(request.argv, "--auto"));
    try testing.expect(testArgvHas(request.argv, "--session"));
    try testing.expect(testArgvHas(request.argv, "oc2-sess-resume-1"));
    try testing.expect(testArgvHas(request.argv, "continue that review"));
    try testing.expect(!testArgvHas(request.argv, "--continue"));
    try testing.expect(!testArgvHas(request.argv, "-c"));
    try testing.expect(!testArgvHas(request.argv, "--resume"));
    try testing.expect(!testArgvHas(request.argv, "acp"));
    try testing.expect(!testArgvHas(request.argv, acp_proxy.SUBCOMMAND));
    try testing.expectEqualStrings("", request.stdin);
    const auto_at = testArgvIndex(request.argv, "--auto") orelse return error.MissingAuto;
    const session_at = testArgvIndex(request.argv, "--session") orelse return error.MissingSession;
    const prompt_at = testArgvIndex(request.argv, "continue that review") orelse return error.MissingPrompt;
    try testing.expectEqual(auto_at + 1, session_at);
    try testing.expectEqualStrings("oc2-sess-resume-1", request.argv[session_at + 1]);
    try testing.expectEqual(session_at + 2, prompt_at);
}

test "opencode2 + session model passes --model {id}" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setSidecarPath("faku");
    model.cli_available[@intFromEnum(protocol.ProviderId.opencode2)] = true;
    const id = model.addSession("opencode2 model", .opencode2);
    if (model.sessionById(id)) |session| session.setModel("anthropic/claude-sonnet-4");

    startPrompt(&model, &fx, id, "use this model");
    try testing.expectEqual(model_exports.ReplyPath.fx, model.reply_path);
    try testing.expect(model.fx_spawn_opencode_run_json);
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());

    const request = fx.pendingSpawnAt(0).?;
    try testing.expect(testArgvHas(request.argv, "--model"));
    try testing.expect(testArgvHas(request.argv, "anthropic/claude-sonnet-4"));
    try testing.expect(!testArgvHas(request.argv, "--session"));
    const auto_at = testArgvIndex(request.argv, "--auto") orelse return error.MissingAuto;
    const model_at = testArgvIndex(request.argv, "--model") orelse return error.MissingModel;
    const prompt_at = testArgvIndex(request.argv, "use this model") orelse return error.MissingPrompt;
    try testing.expectEqual(auto_at + 1, model_at);
    try testing.expectEqualStrings("anthropic/claude-sonnet-4", request.argv[model_at + 1]);
    try testing.expectEqual(model_at + 2, prompt_at);
}

test "opencode2 image attach uses --file {path}" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var image_buf: [256]u8 = undefined;
    const image = try std.fmt.bufPrint(&image_buf, ".zig-cache/tmp/{s}/opencode2-shot.png", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().writeFile(testing.io, .{ .sub_path = image, .data = "png" });

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = testing.io;
    model.setSidecarPath("faku");
    model.cli_available[@intFromEnum(protocol.ProviderId.opencode2)] = true;
    const id = model.addSession("opencode2 image", .opencode2);
    model.selected = id;
    model.setDraftImagePath(image);

    startPrompt(&model, &fx, id, "describe this");
    try testing.expectEqual(model_exports.ReplyPath.fx, model.reply_path);
    try testing.expect(!model.fx_spawn_acp);
    try testing.expect(model.fx_spawn_opencode_run_json);
    try testing.expectEqual(@as(usize, 0), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());
    try testing.expectEqualStrings(image, model.lastSpawnImagePath());

    const request = fx.pendingSpawnAt(0).?;
    try testing.expect(testArgvHas(request.argv, "opencode2"));
    try testing.expect(testArgvHas(request.argv, "run"));
    try testing.expect(testArgvHas(request.argv, "--format"));
    try testing.expect(testArgvHas(request.argv, "json"));
    try testing.expect(testArgvHas(request.argv, "--auto"));
    try testing.expect(testArgvHas(request.argv, "--file"));
    try testing.expect(testArgvHas(request.argv, image));
    try testing.expect(testArgvHas(request.argv, "describe this"));
    try testing.expect(!testArgvHas(request.argv, "-f"));
    try testing.expect(!testArgvHas(request.argv, "--image"));
    try testing.expect(!testArgvHas(request.argv, "acp"));
    try testing.expect(!testArgvHas(request.argv, acp_proxy.SUBCOMMAND));
    try testing.expectEqualStrings("", request.stdin);
    const auto_at = testArgvIndex(request.argv, "--auto") orelse return error.MissingAuto;
    const file_at = testArgvIndex(request.argv, "--file") orelse return error.MissingFile;
    const prompt_at = testArgvIndex(request.argv, "describe this") orelse return error.MissingPrompt;
    try testing.expectEqual(auto_at + 1, file_at);
    try testing.expectEqualStrings(image, request.argv[file_at + 1]);
    try testing.expectEqual(file_at + 2, prompt_at);
}

test "opencode2 run reuses fx_ask_chdir_script when project cwd exists" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/opencode2-cwd", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(testing.io, project);

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = testing.io;
    const id = model.addSession("opencode2 cwd", .opencode2);
    model.cli_available[@intFromEnum(protocol.ProviderId.opencode2)] = true;
    if (model.sessionById(id)) |session| session.setProjectPath(project);

    startPrompt(&model, &fx, id, "in project");
    try testing.expectEqual(model_exports.ReplyPath.fx, model.reply_path);
    try testing.expect(!model.fx_spawn_acp);
    try testing.expect(model.fx_spawn_opencode_run_json);
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());
    const request = fx.pendingSpawnAt(0).?;
    try testing.expect(testArgvHas(request.argv, "/bin/sh"));
    try testing.expect(testArgvHas(request.argv, "-c"));
    try testing.expect(testArgvHas(request.argv, fx_ask_chdir_script));
    try testing.expect(testArgvHas(request.argv, project));
    try testing.expect(testArgvHas(request.argv, "run"));
    try testing.expect(testArgvHas(request.argv, "--format"));
    try testing.expect(testArgvHas(request.argv, "json"));
    try testing.expect(testArgvHas(request.argv, "--auto"));
    try testing.expect(!testArgvHas(request.argv, "--dir"));
    const binary_at = testArgvIndex(request.argv, "opencode2") orelse return error.MissingBinary;
    const run_at = testArgvIndex(request.argv, "run") orelse return error.MissingRun;
    try testing.expect(binary_at > 0);
    try testing.expectEqual(binary_at + 1, run_at);
    try testing.expectEqualStrings(project, request.argv[binary_at - 1]);
}

test "opencode2 binary override is argv[0]" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setSidecarPath("faku");
    model.cli_available[@intFromEnum(protocol.ProviderId.opencode2)] = true;
    model.setProviderBinaryOverride(.opencode2, "/opt/custom-opencode2");
    const id = model.addSession("opencode2 override", .opencode2);

    startPrompt(&model, &fx, id, "hello override");
    try testing.expectEqual(model_exports.ReplyPath.fx, model.reply_path);
    try testing.expect(model.fx_spawn_opencode_run_json);
    const request = fx.pendingSpawnAt(0).?;
    try testing.expect(testArgvHas(request.argv, "/opt/custom-opencode2"));
    try testing.expect(!testArgvHas(request.argv, "opencode2"));
    try testing.expect(testArgvHas(request.argv, "run"));
    try testing.expect(testArgvHas(request.argv, "--format"));
    try testing.expect(testArgvHas(request.argv, "json"));
    try testing.expect(testArgvHas(request.argv, "--auto"));
}

test "fx path stays preferred when provider is fx even if opencode2 is available" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.fx_available = true;
    model.fx_probe_started = true;
    model.setFxPath("fx");
    model.setSidecarPath("faku");
    model.cli_available[@intFromEnum(protocol.ProviderId.opencode2)] = true;
    const id = model.addSession("fx first", .fx);

    startPrompt(&model, &fx, id, "keep fx");
    try testing.expectEqual(model_exports.ReplyPath.fx, model.reply_path);
    try testing.expect(model.fx_spawn_acp);
    try testing.expect(!model.fx_spawn_opencode_run_json);
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());
    const request = fx.pendingSpawnAt(0).?;
    try testing.expect(testArgvHas(request.argv, acp_proxy.SUBCOMMAND));
    try testing.expect(testArgvHas(request.argv, "fx"));
    try testing.expect(testArgvHas(request.argv, "acp"));
    try testing.expect(!testArgvHas(request.argv, "opencode2"));
    try testing.expect(!testArgvHas(request.argv, "run"));
    try testing.expect(!testArgvHas(request.argv, "ask"));
}

test "deepseek + cli_available selects acp-proxy dsh --profile acp" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setSidecarPath("faku");
    const id = model.addSession("deepseek thread", .deepseek);
    model.cli_available[@intFromEnum(protocol.ProviderId.deepseek)] = true;

    startPrompt(&model, &fx, id, "hello deepseek");
    try testing.expectEqual(model_exports.ReplyPath.fx, model.reply_path);
    try testing.expect(model.fx_spawn_acp);
    try testing.expect(!model.fx_spawn_pi_json);
    try testing.expectEqual(@as(usize, 0), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());

    const request = fx.pendingSpawnAt(0).?;
    try testing.expectEqual(effect_keys.fx_ask_key, request.key);
    try testing.expect(testArgvHas(request.argv, acp_proxy.SUBCOMMAND));
    try testing.expect(testArgvHas(request.argv, "--"));
    try testing.expect(testArgvHas(request.argv, "dsh"));
    try testing.expect(testArgvHas(request.argv, "--profile"));
    try testing.expect(testArgvHas(request.argv, "acp"));
    try testing.expect(!testArgvHas(request.argv, "headless"));
    try testing.expect(!testArgvHas(request.argv, "agent"));
    try testing.expect(!testArgvHas(request.argv, "stdio"));
    try testing.expect(!testArgvHas(request.argv, "ask"));
    try testing.expect(!testArgvHas(request.argv, "fx"));
    try testing.expect(!testArgvHas(request.argv, "cursor-agent"));
    try testing.expect(!testArgvHas(request.argv, daemon_proxy.SUBCOMMAND));
    const dash = testArgvIndex(request.argv, "--") orelse return error.MissingDash;
    const binary_at = testArgvIndex(request.argv, "dsh") orelse return error.MissingBinary;
    const profile_at = testArgvIndex(request.argv, "--profile") orelse return error.MissingProfile;
    const acp_at = testArgvIndex(request.argv, "acp") orelse return error.MissingAcp;
    try testing.expect(dash < binary_at);
    try testing.expectEqual(binary_at + 1, profile_at);
    try testing.expectEqual(profile_at + 1, acp_at);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"method\":\"initialize\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"method\":\"session/new\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"method\":\"session/set_mode\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"method\":\"session/prompt\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "hello deepseek") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"type\":\"image\"") == null);
    try testing.expect(!protocol.ProviderId.deepseek.speaksBareAcp());
    try testing.expect(!protocol.ProviderId.deepseek.speaksPiRpc());
    try testing.expect(protocol.ProviderId.deepseek.speaksAcpStdio());
}

test "deepseek unavailable stays demo" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;
    var model = Model{};
    const id = model.addSession("deepseek missing", .deepseek);
    startPrompt(&model, &fx, id, "no dsh");
    try testing.expectEqual(model_exports.ReplyPath.demo, model.reply_path);
    try testing.expect(!model.fx_spawn_acp);
    try testing.expectEqual(@as(usize, 1), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
}

test "deepseek + composer image stays demo (fail closed; no ACP image blocks)" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var image_buf: [256]u8 = undefined;
    const image = try std.fmt.bufPrint(&image_buf, ".zig-cache/tmp/{s}/dsh-shot.png", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().writeFile(testing.io, .{ .sub_path = image, .data = "png" });

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = testing.io;
    model.setSidecarPath("faku");
    model.cli_available[@intFromEnum(protocol.ProviderId.deepseek)] = true;
    const id = model.addSession("deepseek image", .deepseek);
    model.selected = id;
    model.setDraftImagePath(image);

    startPrompt(&model, &fx, id, "describe this");
    try testing.expectEqual(model_exports.ReplyPath.demo, model.reply_path);
    try testing.expect(!model.fx_spawn_acp);
    try testing.expectEqual(@as(usize, 1), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
    try testing.expectEqualStrings("", model.lastSpawnImagePath());
}

test "fx path stays preferred when provider is fx even if deepseek is available" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.fx_available = true;
    model.fx_probe_started = true;
    model.setFxPath("fx");
    model.setSidecarPath("faku");
    model.cli_available[@intFromEnum(protocol.ProviderId.deepseek)] = true;
    const id = model.addSession("fx first", .fx);

    startPrompt(&model, &fx, id, "keep fx");
    try testing.expectEqual(model_exports.ReplyPath.fx, model.reply_path);
    try testing.expect(model.fx_spawn_acp);
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());
    const request = fx.pendingSpawnAt(0).?;
    try testing.expect(testArgvHas(request.argv, acp_proxy.SUBCOMMAND));
    try testing.expect(testArgvHas(request.argv, "fx"));
    try testing.expect(testArgvHas(request.argv, "acp"));
    try testing.expect(!testArgvHas(request.argv, "dsh"));
    try testing.expect(!testArgvHas(request.argv, "--profile"));
    try testing.expect(!testArgvHas(request.argv, "ask"));
}

test "ohmypi image attach uses RPC images on the stdin prompt command" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var image_buf: [256]u8 = undefined;
    const image = try std.fmt.bufPrint(&image_buf, ".zig-cache/tmp/{s}/ohmypi-shot.png", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().writeFile(testing.io, .{ .sub_path = image, .data = "png" });

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = testing.io;
    model.setSidecarPath("faku");
    model.cli_available[@intFromEnum(protocol.ProviderId.ohmypi)] = true;
    const id = model.addSession("ohmypi image", .ohmypi);
    model.selected = id;
    model.setDraftImagePath(image);

    startPrompt(&model, &fx, id, "describe this");
    try testing.expectEqual(model_exports.ReplyPath.fx, model.reply_path);
    try testing.expect(!model.fx_spawn_acp);
    try testing.expect(model.fx_spawn_pi_json);
    try testing.expectEqual(@as(usize, 0), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());
    try testing.expectEqualStrings(image, model.lastSpawnImagePath());

    const request = fx.pendingSpawnAt(0).?;
    try testing.expect(testArgvHas(request.argv, "omp"));
    try testing.expect(testArgvHas(request.argv, "--mode"));
    try testing.expect(testArgvHas(request.argv, "rpc"));
    try testing.expect(testArgvHas(request.argv, "--yolo"));
    try testing.expect(testArgvHas(request.argv, "--no-session"));
    try testing.expect(!testArgvHas(request.argv, "pi"));
    try testing.expect(!testArgvHas(request.argv, "describe this"));
    try testing.expect(!testArgvHas(request.argv, image));
    try testing.expect(!testArgvHas(request.argv, "--image"));
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"type\":\"prompt\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"message\":\"describe this\"") != null);
    try testing.expect(std.mem.indexOf(u8, request.stdin, "\"images\":[{\"type\":\"image\",\"data\":\"cG5n\",\"mimeType\":\"image/png\"}]") != null);
    try testing.expect(std.mem.endsWith(u8, request.stdin, "\n"));
}

test "ohmypi binary override is argv[0]; unavailable image attach stays demo" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setSidecarPath("faku");
    model.cli_available[@intFromEnum(protocol.ProviderId.ohmypi)] = true;
    model.setProviderBinaryOverride(.ohmypi, "/opt/custom-omp");
    const id = model.addSession("ohmypi override", .ohmypi);

    startPrompt(&model, &fx, id, "hello override");
    try testing.expectEqual(model_exports.ReplyPath.fx, model.reply_path);
    try testing.expect(model.fx_spawn_pi_json);
    const request = fx.pendingSpawnAt(0).?;
    try testing.expect(testArgvHas(request.argv, "/opt/custom-omp"));
    try testing.expect(!testArgvHas(request.argv, "omp"));
    try testing.expect(testArgvHas(request.argv, "--yolo"));
    try testing.expect(testArgvHas(request.argv, "--no-session"));
}

test "ohmypi image attach missing file stays demo" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = testing.io;
    model.setSidecarPath("faku");
    model.cli_available[@intFromEnum(protocol.ProviderId.ohmypi)] = true;
    const id = model.addSession("ohmypi missing file", .ohmypi);
    model.selected = id;
    model.setDraftImagePath(".zig-cache/tmp/faku-ohmypi-image-missing.png");

    startPrompt(&model, &fx, id, "describe this");
    try testing.expectEqual(model_exports.ReplyPath.demo, model.reply_path);
    try testing.expect(!model.fx_spawn_acp);
    try testing.expect(!model.fx_spawn_pi_json);
    try testing.expectEqual(@as(usize, 1), fx.pendingTimerCount());
    try testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
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
    try testing.expectEqual(model_exports.ReplyPath.fx, model.reply_path);
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
    try testing.expectEqual(model_exports.ReplyPath.demo, model.reply_path);
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
    try testing.expectEqual(model_exports.ReplyPath.fx, model.reply_path);
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
    try testing.expectEqual(model_exports.ReplyPath.fx, model.reply_path);
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
    try testing.expectEqual(model_exports.ReplyPath.demo, model.reply_path);
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

    var long_prompt: [model_exports.max_body + model_exports.max_project_path]u8 = undefined;
    @memset(&long_prompt, 'x');
    startPrompt(&model, &fx, id, &long_prompt);
    try testing.expectEqual(model_exports.ReplyPath.demo, model.reply_path);
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
    try testing.expectEqual(model_exports.ReplyPath.fx, model.reply_path);
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
    try testing.expectEqual(model_exports.ReplyPath.fx, model.reply_path);
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
    try testing.expectEqual(model_exports.ReplyPath.fx, model.reply_path);
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
    try testing.expectEqual(model_exports.ReplyPath.demo, model.reply_path);
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
    try testing.expectEqual(model_exports.ReplyPath.fx, model.reply_path);
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
    try testing.expectEqual(model_exports.ReplyPath.demo, model.reply_path);
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
    try testing.expectEqual(model_exports.ReplyPath.fx, model.reply_path);
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
    try testing.expectEqual(model_exports.ReplyPath.fx, model.reply_path);
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

test "startPrompt with last_daemon_address spawns CaptureTurnStart sidecar and still demos" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/send-capture-turn-start", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(testing.io, project);

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = testing.io;
    model.fx_probe_started = true;
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    const id = model.addSession("send capture", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);

    startPrompt(&model, &fx, id, "ship the capture cut");
    try testing.expectEqual(model_exports.ReplyPath.demo, model.reply_path);
    try testing.expect(model.is_streaming());
    try testing.expectEqual(@as(usize, 1), fx.pendingTimerCount());
    try testing.expect(model.daemon_capture_turn_start_key != 0);
    try testing.expect(model.daemon_spawn_key == 0);

    var found = false;
    var i: usize = 0;
    while (fx.pendingSpawnAt(i)) |spawn| : (i += 1) {
        if (spawn.key != model.daemon_capture_turn_start_key) continue;
        try testing.expect(daemon_proxy.isSidecarArgv(spawn.argv));
        try testing.expectEqualStrings("127.0.0.1:8787", spawn.argv[2]);
        try testing.expect(std.mem.indexOf(u8, spawn.stdin, "\"type\":\"captureTurnStart\"") != null);
        try testing.expect(std.mem.indexOf(u8, spawn.stdin, "\"type\":\"prompt\"") == null);
        try testing.expect(std.mem.indexOf(u8, spawn.stdin, project) != null);
        found = true;
    }
    try testing.expect(found);
}

test "startPrompt without a daemon address does not spawn CaptureTurnStart" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, ".zig-cache/tmp/{s}/send-capture-local", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(testing.io, project);

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = testing.io;
    model.fx_probe_started = true;
    model.setSidecarPath("faku");
    const id = model.addSession("send capture local", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| session.setProjectPath(project);
    try testing.expectEqual(@as(usize, 0), store.resolveDaemonMirrorAddress(&model).len);

    startPrompt(&model, &fx, id, "no daemon capture");
    try testing.expectEqual(model_exports.ReplyPath.demo, model.reply_path);
    try testing.expectEqual(@as(u64, 0), model.daemon_capture_turn_start_key);
    var i: usize = 0;
    while (fx.pendingSpawnAt(i)) |spawn| : (i += 1) {
        try testing.expect(std.mem.indexOf(u8, spawn.stdin, "\"type\":\"captureTurnStart\"") == null);
    }
}

test "startChromeTick arms a repeating 1s timer distinct from the demo stream timer" {
    const testing = std.testing;
    const native_sdk = @import("native_sdk");
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    startChromeTick(&fx);
    try testing.expectEqual(@as(usize, 1), fx.pendingTimerCount());
    const chrome = pendingTimerByKey(&fx, chrome_tick_key) orelse return error.ChromeTickMissing;
    try testing.expectEqual(chrome_tick_key, chrome.key);
    try testing.expectEqual(chrome_tick_interval_ms, chrome.interval_ms);
    try testing.expectEqual(native_sdk.TimerMode.repeating, chrome.mode);
    try testing.expect(pendingTimerByKey(&fx, stream_timer_key) == null);
}

test "initFx arms chrome tick for the app lifetime" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    main.initFx(&model, &fx);
    const chrome = pendingTimerByKey(&fx, chrome_tick_key) orelse return error.ChromeTickMissing;
    try testing.expectEqual(chrome_tick_interval_ms, chrome.interval_ms);
}

test "chrome tick does not bump demo stream_cursor; stream tick still does when phase=.streaming" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    const id = model.addSession("chrome tick stream", .fx);
    model.selected = id;
    startChromeTick(&fx);
    startPrompt(&model, &fx, id, "hello chrome tick");
    try testing.expect(model.is_streaming());
    try testing.expectEqual(model_exports.ReplyPath.demo, model.reply_path);
    try testing.expect(pendingTimerByKey(&fx, chrome_tick_key) != null);
    try testing.expect(pendingTimerByKey(&fx, stream_timer_key) != null);
    const before = model.stream_cursor;

    try fx.fireTimer(chrome_tick_key);
    drainEffects(&model, &fx);
    try testing.expectEqual(before, model.stream_cursor);
    try testing.expect(model.is_streaming());

    try fx.fireTimer(stream_timer_key);
    drainEffects(&model, &fx);
    try testing.expect(model.stream_cursor > before);
    try testing.expect(model.is_streaming());
}

test "finishStream and stopStream leave the chrome tick armed" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    const id = model.addSession("chrome tick survives", .fx);
    model.selected = id;
    startChromeTick(&fx);
    startPrompt(&model, &fx, id, "keep chrome ticking");
    try testing.expect(model.is_streaming());

    var n: u32 = 0;
    while (n < 16 and model.is_streaming()) : (n += 1) {
        try fx.fireTimer(stream_timer_key);
        drainEffects(&model, &fx);
    }
    try testing.expect(!model.is_streaming());
    try testing.expect(pendingTimerByKey(&fx, stream_timer_key) == null);
    const after_finish = pendingTimerByKey(&fx, chrome_tick_key) orelse return error.ChromeTickCancelledOnFinish;
    try testing.expectEqual(chrome_tick_interval_ms, after_finish.interval_ms);

    startPrompt(&model, &fx, id, "stop without dropping chrome");
    try testing.expect(model.is_streaming());
    main.update(&model, .stop_turn, &fx);
    try testing.expect(!model.is_streaming());
    try testing.expect(pendingTimerByKey(&fx, stream_timer_key) == null);
    try testing.expect(pendingTimerByKey(&fx, chrome_tick_key) != null);
}

test "startPrompt untitled title uses original draft; user turn stores expanded skill bodies" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const root = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-skills-send-title", .{tmp.sub_path[0..]});
    var skill_dir_buf: [256]u8 = undefined;
    const skill_dir = try std.fmt.bufPrint(&skill_dir_buf, "{s}/skills/alpha", .{root});
    try std.Io.Dir.cwd().createDirPath(testing.io, skill_dir);
    var file_buf: [256]u8 = undefined;
    const file_path = try std.fmt.bufPrint(&file_buf, "{s}/SKILL.md", .{skill_dir});
    try std.Io.Dir.cwd().writeFile(testing.io, .{
        .sub_path = file_path,
        .data =
            \\---
            \\name: alpha
            \\---
            \\
            \\Alpha body.
            \\
        ,
    });

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = testing.io;
    const id = model.addSession("untitled", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| {
        session.untitled = true;
        session.setProjectPath(root);
    }
    writeFixed(&model.skill_probe_path_storage, &model.skill_probe_path_len, root);
    skills.applyStdoutPaths(&model, "skills/alpha/SKILL.md\n");
    try testing.expectEqualStrings("alpha", skills.cachedName(&model, 0));

    const draft = "$alpha ship it";
    startPrompt(&model, &fx, id, draft);
    try testing.expect(!model.sessionById(id).?.untitled);
    try testing.expectEqualStrings(draft, model.sessionById(id).?.title());
    try testing.expectEqual(model_exports.Role.user, model.turn_store[0].role);
    try testing.expectEqualStrings(
        \\### Skill: alpha
        \\Alpha body.
        \\
        \\$alpha ship it
    , model.turn_store[0].text());
}

test "startPrompt untitled title uses original /name draft; user turn stores expanded skill bodies" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const root = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-skills-send-slash-title", .{tmp.sub_path[0..]});
    var skill_dir_buf: [256]u8 = undefined;
    const skill_dir = try std.fmt.bufPrint(&skill_dir_buf, "{s}/skills/alpha", .{root});
    try std.Io.Dir.cwd().createDirPath(testing.io, skill_dir);
    var file_buf: [256]u8 = undefined;
    const file_path = try std.fmt.bufPrint(&file_buf, "{s}/SKILL.md", .{skill_dir});
    try std.Io.Dir.cwd().writeFile(testing.io, .{
        .sub_path = file_path,
        .data =
            \\---
            \\name: alpha
            \\---
            \\
            \\Alpha body.
            \\
        ,
    });

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = testing.io;
    const id = model.addSession("untitled slash", .fx);
    model.selected = id;
    if (model.sessionById(id)) |session| {
        session.untitled = true;
        session.setProjectPath(root);
    }
    writeFixed(&model.skill_probe_path_storage, &model.skill_probe_path_len, root);
    skills.applyStdoutPaths(&model, "skills/alpha/SKILL.md\n");
    try testing.expectEqualStrings("alpha", skills.cachedName(&model, 0));

    const draft = "/alpha ship it";
    startPrompt(&model, &fx, id, draft);
    try testing.expect(!model.sessionById(id).?.untitled);
    try testing.expectEqualStrings(draft, model.sessionById(id).?.title());
    try testing.expectEqual(model_exports.Role.user, model.turn_store[0].role);
    try testing.expectEqualStrings(
        \\### Skill: alpha
        \\Alpha body.
        \\
        \\/alpha ship it
    , model.turn_store[0].text());
}
