//! Waku-parity empty-Commit… generate argv for the selected session
//! provider CLI (`agent_arguments` / docs/commit-messages.md).
//!
//! Faku does not copy Waku Rust. This builder emits documented
//! one-shot / tool-free argv only. Prompt is last positional unless
//! the provider documents `--single` (Grok) or `--prompt` (Kimi).
//! Claude and Codex stay pinned. DeepSeek never gets a model flag.
//! Native `SpawnOptions` has no `env` / `cwd` and `max_effect_argv`
//! is 16. Unix chdir + `export NO_COLOR=1 CI=1` live in one `-c`
//! script; when documented flags would overflow that 16, they stay
//! literals in that script and cwd / binary / prompt / optionals stay
//! `$N` slots. Windows keeps the same slot discipline in `-Args`.
//! Amp writes a temp settings JSON and callers delete it (including
//! the error path). Fx keep-today `ask --no-save --auto --json` lives
//! in `git_commit.generateArgvFor` — this module still exposes the
//! same fx flag slots for the per-provider table test.

const std = @import("std");
const builtin = @import("builtin");
const protocol = @import("protocol.zig");
const util = @import("util.zig");

pub const sh_bin = "/bin/sh";
pub const powershell_bin = "powershell.exe";
pub const powershell_noprofile = "-NoProfile";
pub const powershell_command = "-Command";
pub const powershell_args_flag = "-Args";

pub const env_no_color = "NO_COLOR=1";
pub const env_ci = "CI=1";
pub const max_effect_argv: usize = 16;

pub const empty_tools = "";

pub const amp_settings_json =
    "{\"amp.tools.enable\":[],\"amp.notifications.enabled\":false,\"amp.skills.disableClaudeCodeSkills\":true}";

/// Unix chdir + child-only env. `$1` is cwd; after `shift`, `$@` is
/// binary + documented generate flags / prompt. Literals only.
pub const generate_chdir_env_script =
    "cd -- \"$1\" && shift && export NO_COLOR=1 CI=1 && exec \"$@\"";

/// Scriptblock + `$args[N]`: cwd, binary, and remaining provider
/// slots stay their own argv slots after `-Args`. `NO_COLOR` / `CI`
/// are literals in the scriptblock. Used when the splat fits in
/// Native `max_effect_argv` 16.
pub const powershell_provider_generate_script =
    "{ $ErrorActionPreference='Stop'; $env:NO_COLOR='1'; $env:CI='1'; Set-Location -LiteralPath $args[0]; & $args[1] @($args[2..($args.Length-1)]); exit $LASTEXITCODE }";

pub const unix_packed_amp =
    "cd -- \"$1\" && export NO_COLOR=1 CI=1 && exec \"$2\" --execute --no-color --no-ide --no-notifications --settings-file \"$3\"${4:+ --mode \"$4\"}${5:+ --effort \"$5\"} \"$6\"";
pub const unix_packed_claude =
    "cd -- \"$1\" && export NO_COLOR=1 CI=1 && exec \"$2\" --print --output-format text --permission-mode plan --tools \"\" --disable-slash-commands --no-session-persistence --no-chrome --model claude-haiku-4-5 --effort low \"$3\"";
pub const unix_packed_codex =
    "cd -- \"$1\" && export NO_COLOR=1 CI=1 && exec \"$2\" exec --sandbox read-only --ephemeral --color never --skip-git-repo-check --model gpt-5.6-luna -c model_reasoning_effort=\"none\" \"$3\"";
pub const unix_packed_cursor =
    "cd -- \"$1\" && export NO_COLOR=1 CI=1 && exec \"$2\" --print --output-format text --mode ask --sandbox enabled --trust${3:+ --model \"$3\"} \"$4\"";
pub const unix_packed_grok =
    "cd -- \"$1\" && export NO_COLOR=1 CI=1 && exec \"$2\" --single \"$3\" --output-format plain --permission-mode plan --tools \"\" --no-memory --no-subagents --disable-web-search --verbatim${4:+ --model \"$4\"}${5:+ --reasoning-effort \"$5\"}";
pub const unix_packed_pi =
    "cd -- \"$1\" && export NO_COLOR=1 CI=1 && exec \"$2\" --print --no-session --no-tools --no-context-files --no-extensions --no-skills --no-prompt-templates --no-approve${3:+ --model \"$3\"}${4:+ --thinking \"$4\"} \"$5\"";
pub const unix_packed_ohmypi =
    "cd -- \"$1\" && export NO_COLOR=1 CI=1 && exec \"$2\" --print --no-session --no-tools --no-rules --no-extensions --no-skills${3:+ --model \"$3\"}${4:+ --thinking \"$4\"} \"$5\"";

pub const windows_packed_amp =
    "{ $ErrorActionPreference='Stop'; $env:NO_COLOR='1'; $env:CI='1'; Set-Location -LiteralPath $args[0]; $mode=@(); if ($args[3]) { $mode=@('--mode', $args[3]) }; $effort=@(); if ($args[4]) { $effort=@('--effort', $args[4]) }; & $args[1] --execute --no-color --no-ide --no-notifications --settings-file $args[2] @mode @effort $args[5]; exit $LASTEXITCODE }";
pub const windows_packed_claude =
    "{ $ErrorActionPreference='Stop'; $env:NO_COLOR='1'; $env:CI='1'; Set-Location -LiteralPath $args[0]; & $args[1] --print --output-format text --permission-mode plan --tools '' --disable-slash-commands --no-session-persistence --no-chrome --model claude-haiku-4-5 --effort low $args[2]; exit $LASTEXITCODE }";
pub const windows_packed_codex =
    "{ $ErrorActionPreference='Stop'; $env:NO_COLOR='1'; $env:CI='1'; Set-Location -LiteralPath $args[0]; & $args[1] exec --sandbox read-only --ephemeral --color never --skip-git-repo-check --model gpt-5.6-luna -c 'model_reasoning_effort=\"none\"' $args[2]; exit $LASTEXITCODE }";
pub const windows_packed_cursor =
    "{ $ErrorActionPreference='Stop'; $env:NO_COLOR='1'; $env:CI='1'; Set-Location -LiteralPath $args[0]; $model=@(); if ($args[2]) { $model=@('--model', $args[2]) }; & $args[1] --print --output-format text --mode ask --sandbox enabled --trust @model $args[3]; exit $LASTEXITCODE }";
pub const windows_packed_grok =
    "{ $ErrorActionPreference='Stop'; $env:NO_COLOR='1'; $env:CI='1'; Set-Location -LiteralPath $args[0]; $model=@(); if ($args[3]) { $model=@('--model', $args[3]) }; $effort=@(); if ($args[4]) { $effort=@('--reasoning-effort', $args[4]) }; & $args[1] --single $args[2] --output-format plain --permission-mode plan --tools '' --no-memory --no-subagents --disable-web-search --verbatim @model @effort; exit $LASTEXITCODE }";
pub const windows_packed_pi =
    "{ $ErrorActionPreference='Stop'; $env:NO_COLOR='1'; $env:CI='1'; Set-Location -LiteralPath $args[0]; $model=@(); if ($args[2]) { $model=@('--model', $args[2]) }; $effort=@(); if ($args[3]) { $effort=@('--thinking', $args[3]) }; & $args[1] --print --no-session --no-tools --no-context-files --no-extensions --no-skills --no-prompt-templates --no-approve @model @effort $args[4]; exit $LASTEXITCODE }";
pub const windows_packed_ohmypi =
    "{ $ErrorActionPreference='Stop'; $env:NO_COLOR='1'; $env:CI='1'; Set-Location -LiteralPath $args[0]; $model=@(); if ($args[2]) { $model=@('--model', $args[2]) }; $effort=@(); if ($args[3]) { $effort=@('--thinking', $args[3]) }; & $args[1] --print --no-session --no-tools --no-rules --no-extensions --no-skills @model @effort $args[4]; exit $LASTEXITCODE }";

/// Args after the binary. Grok is the longest documented row.
pub const provider_args_len: usize = 20;

/// Packed or generic wrap; never more than Native `max_effect_argv`.
pub const provider_generate_argv_len: usize = 16;

/// Generic Unix: sh -c script sh cwd binary.
pub const unix_provider_generate_prefix_len: usize = 6;
pub const windows_provider_generate_prefix_len: usize = 7;

pub const claude_generate_model = "claude-haiku-4-5";
pub const claude_generate_effort = "low";
pub const codex_generate_model = "gpt-5.6-luna";
pub const codex_generate_effort_config = "model_reasoning_effort=\"none\"";

pub const GenerateSpec = struct {
    provider: protocol.ProviderId,
    cwd: []const u8,
    binary: []const u8,
    prompt: []const u8,
    model: []const u8 = "",
    effort: []const u8 = "",
    amp_settings_path: []const u8 = "",
};

/// Documented flags after the binary. Null when the id cannot be
/// spawned safely (empty binary, Amp without a settings path).
pub fn providerArgsFor(spec: GenerateSpec, buf: *[provider_args_len][]const u8) ?[]const []const u8 {
    if (spec.binary.len == 0) return null;
    if (spec.provider == .amp and spec.amp_settings_path.len == 0) return null;

    var n: usize = 0;
    switch (spec.provider) {
        .fx => {
            buf[n] = "ask";
            n += 1;
            buf[n] = "--no-save";
            n += 1;
            buf[n] = "--auto";
            n += 1;
            buf[n] = "--json";
            n += 1;
            buf[n] = "--";
            n += 1;
            buf[n] = spec.prompt;
            n += 1;
        },
        .amp => {
            buf[n] = "--execute";
            n += 1;
            buf[n] = "--no-color";
            n += 1;
            buf[n] = "--no-ide";
            n += 1;
            buf[n] = "--no-notifications";
            n += 1;
            buf[n] = "--settings-file";
            n += 1;
            buf[n] = spec.amp_settings_path;
            n += 1;
            if (spec.model.len > 0) {
                buf[n] = "--mode";
                n += 1;
                buf[n] = spec.model;
                n += 1;
            }
            if (spec.effort.len > 0) {
                buf[n] = "--effort";
                n += 1;
                buf[n] = spec.effort;
                n += 1;
            }
            buf[n] = spec.prompt;
            n += 1;
        },
        .claude => {
            buf[n] = "--print";
            n += 1;
            buf[n] = "--output-format";
            n += 1;
            buf[n] = "text";
            n += 1;
            buf[n] = "--permission-mode";
            n += 1;
            buf[n] = "plan";
            n += 1;
            buf[n] = "--tools";
            n += 1;
            buf[n] = empty_tools;
            n += 1;
            buf[n] = "--disable-slash-commands";
            n += 1;
            buf[n] = "--no-session-persistence";
            n += 1;
            buf[n] = "--no-chrome";
            n += 1;
            buf[n] = "--model";
            n += 1;
            buf[n] = claude_generate_model;
            n += 1;
            buf[n] = "--effort";
            n += 1;
            buf[n] = claude_generate_effort;
            n += 1;
            buf[n] = spec.prompt;
            n += 1;
        },
        .codex => {
            buf[n] = "exec";
            n += 1;
            buf[n] = "--sandbox";
            n += 1;
            buf[n] = "read-only";
            n += 1;
            buf[n] = "--ephemeral";
            n += 1;
            buf[n] = "--color";
            n += 1;
            buf[n] = "never";
            n += 1;
            buf[n] = "--skip-git-repo-check";
            n += 1;
            buf[n] = "--model";
            n += 1;
            buf[n] = codex_generate_model;
            n += 1;
            buf[n] = "-c";
            n += 1;
            buf[n] = codex_generate_effort_config;
            n += 1;
            buf[n] = spec.prompt;
            n += 1;
        },
        .cursor => {
            buf[n] = "--print";
            n += 1;
            buf[n] = "--output-format";
            n += 1;
            buf[n] = "text";
            n += 1;
            buf[n] = "--mode";
            n += 1;
            buf[n] = "ask";
            n += 1;
            buf[n] = "--sandbox";
            n += 1;
            buf[n] = "enabled";
            n += 1;
            buf[n] = "--trust";
            n += 1;
            if (spec.model.len > 0) {
                buf[n] = "--model";
                n += 1;
                buf[n] = spec.model;
                n += 1;
            }
            buf[n] = spec.prompt;
            n += 1;
        },
        .deepseek => {
            buf[n] = "--profile";
            n += 1;
            buf[n] = "headless";
            n += 1;
            buf[n] = spec.prompt;
            n += 1;
        },
        .opencode => {
            buf[n] = "run";
            n += 1;
            buf[n] = "--pure";
            n += 1;
            buf[n] = "--agent";
            n += 1;
            buf[n] = "plan";
            n += 1;
            if (spec.model.len > 0) {
                buf[n] = "--model";
                n += 1;
                buf[n] = spec.model;
                n += 1;
            }
            if (spec.effort.len > 0) {
                buf[n] = "--variant";
                n += 1;
                buf[n] = spec.effort;
                n += 1;
            }
            buf[n] = spec.prompt;
            n += 1;
        },
        .opencode2 => {
            buf[n] = "run";
            n += 1;
            buf[n] = "--standalone";
            n += 1;
            buf[n] = "--agent";
            n += 1;
            buf[n] = "plan";
            n += 1;
            if (spec.model.len > 0) {
                buf[n] = "--model";
                n += 1;
                buf[n] = spec.model;
                n += 1;
            }
            buf[n] = spec.prompt;
            n += 1;
        },
        .grok => {
            buf[n] = "--single";
            n += 1;
            buf[n] = spec.prompt;
            n += 1;
            buf[n] = "--output-format";
            n += 1;
            buf[n] = "plain";
            n += 1;
            buf[n] = "--permission-mode";
            n += 1;
            buf[n] = "plan";
            n += 1;
            buf[n] = "--tools";
            n += 1;
            buf[n] = empty_tools;
            n += 1;
            buf[n] = "--no-memory";
            n += 1;
            buf[n] = "--no-subagents";
            n += 1;
            buf[n] = "--disable-web-search";
            n += 1;
            buf[n] = "--verbatim";
            n += 1;
            if (spec.model.len > 0) {
                buf[n] = "--model";
                n += 1;
                buf[n] = spec.model;
                n += 1;
            }
            if (spec.effort.len > 0) {
                buf[n] = "--reasoning-effort";
                n += 1;
                buf[n] = spec.effort;
                n += 1;
            }
        },
        .pi => {
            buf[n] = "--print";
            n += 1;
            buf[n] = "--no-session";
            n += 1;
            buf[n] = "--no-tools";
            n += 1;
            buf[n] = "--no-context-files";
            n += 1;
            buf[n] = "--no-extensions";
            n += 1;
            buf[n] = "--no-skills";
            n += 1;
            buf[n] = "--no-prompt-templates";
            n += 1;
            buf[n] = "--no-approve";
            n += 1;
            if (spec.model.len > 0) {
                buf[n] = "--model";
                n += 1;
                buf[n] = spec.model;
                n += 1;
            }
            if (spec.effort.len > 0) {
                buf[n] = "--thinking";
                n += 1;
                buf[n] = spec.effort;
                n += 1;
            }
            buf[n] = spec.prompt;
            n += 1;
        },
        .ohmypi => {
            buf[n] = "--print";
            n += 1;
            buf[n] = "--no-session";
            n += 1;
            buf[n] = "--no-tools";
            n += 1;
            buf[n] = "--no-rules";
            n += 1;
            buf[n] = "--no-extensions";
            n += 1;
            buf[n] = "--no-skills";
            n += 1;
            if (spec.model.len > 0) {
                buf[n] = "--model";
                n += 1;
                buf[n] = spec.model;
                n += 1;
            }
            if (spec.effort.len > 0) {
                buf[n] = "--thinking";
                n += 1;
                buf[n] = spec.effort;
                n += 1;
            }
            buf[n] = spec.prompt;
            n += 1;
        },
        .kimi => {
            buf[n] = "--prompt";
            n += 1;
            buf[n] = spec.prompt;
            n += 1;
            buf[n] = "--output-format";
            n += 1;
            buf[n] = "text";
            n += 1;
            if (spec.model.len > 0) {
                buf[n] = "--model";
                n += 1;
                buf[n] = spec.model;
                n += 1;
            }
        },
    }
    return buf[0..n];
}

fn unixGenericLen(args_len: usize) usize {
    return unix_provider_generate_prefix_len + args_len;
}

fn windowsGenericLen(args_len: usize) usize {
    return windows_provider_generate_prefix_len + args_len;
}

fn writeUnixGeneric(
    spec: GenerateSpec,
    args: []const []const u8,
    buf: *[provider_generate_argv_len][]const u8,
) []const []const u8 {
    var n: usize = 0;
    buf[n] = sh_bin;
    n += 1;
    buf[n] = "-c";
    n += 1;
    buf[n] = generate_chdir_env_script;
    n += 1;
    buf[n] = "sh";
    n += 1;
    buf[n] = spec.cwd;
    n += 1;
    buf[n] = spec.binary;
    n += 1;
    for (args) |arg| {
        buf[n] = arg;
        n += 1;
    }
    return buf[0..n];
}

fn writeWindowsGeneric(
    spec: GenerateSpec,
    args: []const []const u8,
    buf: *[provider_generate_argv_len][]const u8,
) []const []const u8 {
    var n: usize = 0;
    buf[n] = powershell_bin;
    n += 1;
    buf[n] = powershell_noprofile;
    n += 1;
    buf[n] = powershell_command;
    n += 1;
    buf[n] = powershell_provider_generate_script;
    n += 1;
    buf[n] = powershell_args_flag;
    n += 1;
    buf[n] = spec.cwd;
    n += 1;
    buf[n] = spec.binary;
    n += 1;
    for (args) |arg| {
        buf[n] = arg;
        n += 1;
    }
    return buf[0..n];
}

fn writeUnixPacked(spec: GenerateSpec, buf: *[provider_generate_argv_len][]const u8) ?[]const []const u8 {
    var n: usize = 0;
    buf[n] = sh_bin;
    n += 1;
    buf[n] = "-c";
    n += 1;
    switch (spec.provider) {
        .amp => {
            buf[n] = unix_packed_amp;
            n += 1;
            buf[n] = "sh";
            n += 1;
            buf[n] = spec.cwd;
            n += 1;
            buf[n] = spec.binary;
            n += 1;
            buf[n] = spec.amp_settings_path;
            n += 1;
            buf[n] = spec.model;
            n += 1;
            buf[n] = spec.effort;
            n += 1;
            buf[n] = spec.prompt;
            n += 1;
        },
        .claude => {
            buf[n] = unix_packed_claude;
            n += 1;
            buf[n] = "sh";
            n += 1;
            buf[n] = spec.cwd;
            n += 1;
            buf[n] = spec.binary;
            n += 1;
            buf[n] = spec.prompt;
            n += 1;
        },
        .codex => {
            buf[n] = unix_packed_codex;
            n += 1;
            buf[n] = "sh";
            n += 1;
            buf[n] = spec.cwd;
            n += 1;
            buf[n] = spec.binary;
            n += 1;
            buf[n] = spec.prompt;
            n += 1;
        },
        .cursor => {
            buf[n] = unix_packed_cursor;
            n += 1;
            buf[n] = "sh";
            n += 1;
            buf[n] = spec.cwd;
            n += 1;
            buf[n] = spec.binary;
            n += 1;
            buf[n] = spec.model;
            n += 1;
            buf[n] = spec.prompt;
            n += 1;
        },
        .grok => {
            buf[n] = unix_packed_grok;
            n += 1;
            buf[n] = "sh";
            n += 1;
            buf[n] = spec.cwd;
            n += 1;
            buf[n] = spec.binary;
            n += 1;
            buf[n] = spec.prompt;
            n += 1;
            buf[n] = spec.model;
            n += 1;
            buf[n] = spec.effort;
            n += 1;
        },
        .pi => {
            buf[n] = unix_packed_pi;
            n += 1;
            buf[n] = "sh";
            n += 1;
            buf[n] = spec.cwd;
            n += 1;
            buf[n] = spec.binary;
            n += 1;
            buf[n] = spec.model;
            n += 1;
            buf[n] = spec.effort;
            n += 1;
            buf[n] = spec.prompt;
            n += 1;
        },
        .ohmypi => {
            buf[n] = unix_packed_ohmypi;
            n += 1;
            buf[n] = "sh";
            n += 1;
            buf[n] = spec.cwd;
            n += 1;
            buf[n] = spec.binary;
            n += 1;
            buf[n] = spec.model;
            n += 1;
            buf[n] = spec.effort;
            n += 1;
            buf[n] = spec.prompt;
            n += 1;
        },
        .fx, .deepseek, .opencode, .opencode2, .kimi => return null,
    }
    return buf[0..n];
}

fn writeWindowsPacked(spec: GenerateSpec, buf: *[provider_generate_argv_len][]const u8) ?[]const []const u8 {
    var n: usize = 0;
    buf[n] = powershell_bin;
    n += 1;
    buf[n] = powershell_noprofile;
    n += 1;
    buf[n] = powershell_command;
    n += 1;
    switch (spec.provider) {
        .amp => {
            buf[n] = windows_packed_amp;
            n += 1;
            buf[n] = powershell_args_flag;
            n += 1;
            buf[n] = spec.cwd;
            n += 1;
            buf[n] = spec.binary;
            n += 1;
            buf[n] = spec.amp_settings_path;
            n += 1;
            buf[n] = spec.model;
            n += 1;
            buf[n] = spec.effort;
            n += 1;
            buf[n] = spec.prompt;
            n += 1;
        },
        .claude => {
            buf[n] = windows_packed_claude;
            n += 1;
            buf[n] = powershell_args_flag;
            n += 1;
            buf[n] = spec.cwd;
            n += 1;
            buf[n] = spec.binary;
            n += 1;
            buf[n] = spec.prompt;
            n += 1;
        },
        .codex => {
            buf[n] = windows_packed_codex;
            n += 1;
            buf[n] = powershell_args_flag;
            n += 1;
            buf[n] = spec.cwd;
            n += 1;
            buf[n] = spec.binary;
            n += 1;
            buf[n] = spec.prompt;
            n += 1;
        },
        .cursor => {
            buf[n] = windows_packed_cursor;
            n += 1;
            buf[n] = powershell_args_flag;
            n += 1;
            buf[n] = spec.cwd;
            n += 1;
            buf[n] = spec.binary;
            n += 1;
            buf[n] = spec.model;
            n += 1;
            buf[n] = spec.prompt;
            n += 1;
        },
        .grok => {
            buf[n] = windows_packed_grok;
            n += 1;
            buf[n] = powershell_args_flag;
            n += 1;
            buf[n] = spec.cwd;
            n += 1;
            buf[n] = spec.binary;
            n += 1;
            buf[n] = spec.prompt;
            n += 1;
            buf[n] = spec.model;
            n += 1;
            buf[n] = spec.effort;
            n += 1;
        },
        .pi => {
            buf[n] = windows_packed_pi;
            n += 1;
            buf[n] = powershell_args_flag;
            n += 1;
            buf[n] = spec.cwd;
            n += 1;
            buf[n] = spec.binary;
            n += 1;
            buf[n] = spec.model;
            n += 1;
            buf[n] = spec.effort;
            n += 1;
            buf[n] = spec.prompt;
            n += 1;
        },
        .ohmypi => {
            buf[n] = windows_packed_ohmypi;
            n += 1;
            buf[n] = powershell_args_flag;
            n += 1;
            buf[n] = spec.cwd;
            n += 1;
            buf[n] = spec.binary;
            n += 1;
            buf[n] = spec.model;
            n += 1;
            buf[n] = spec.effort;
            n += 1;
            buf[n] = spec.prompt;
            n += 1;
        },
        .fx, .deepseek, .opencode, .opencode2, .kimi => return null,
    }
    return buf[0..n];
}

pub fn unixProviderGenerateArgvFor(
    spec: GenerateSpec,
    buf: *[provider_generate_argv_len][]const u8,
) ?[]const []const u8 {
    var args_buf: [provider_args_len][]const u8 = undefined;
    const args = providerArgsFor(spec, &args_buf) orelse return null;
    if (unixGenericLen(args.len) <= max_effect_argv)
        return writeUnixGeneric(spec, args, buf);
    return writeUnixPacked(spec, buf);
}

pub fn windowsProviderGenerateArgvFor(
    spec: GenerateSpec,
    buf: *[provider_generate_argv_len][]const u8,
) ?[]const []const u8 {
    var args_buf: [provider_args_len][]const u8 = undefined;
    const args = providerArgsFor(spec, &args_buf) orelse return null;
    if (windowsGenericLen(args.len) <= max_effect_argv)
        return writeWindowsGeneric(spec, args, buf);
    return writeWindowsPacked(spec, buf);
}

/// Host spawn argv for a non-fx provider. Fx stays on
/// `git_commit.generateArgvFor` (today's JSON ask path).
pub fn providerGenerateArgvFor(
    spec: GenerateSpec,
    buf: *[provider_generate_argv_len][]const u8,
) ?[]const []const u8 {
    if (spec.provider == .fx) return null;
    return switch (builtin.os.tag) {
        .windows => windowsProviderGenerateArgvFor(spec, buf),
        else => unixProviderGenerateArgvFor(spec, buf),
    };
}

pub fn isUnixPackedGenerateScript(script: []const u8) bool {
    return std.mem.indexOf(u8, script, "export NO_COLOR=1 CI=1") != null and
        std.mem.indexOf(u8, script, "cd -- \"$1\"") != null and
        !std.mem.eql(u8, script, generate_chdir_env_script);
}

pub fn isUnixProviderGenerateArgv(argv: []const []const u8) bool {
    if (argv.len < 6 or argv.len > max_effect_argv) return false;
    if (!std.mem.eql(u8, argv[0], sh_bin)) return false;
    if (!std.mem.eql(u8, argv[1], "-c")) return false;
    if (!std.mem.eql(u8, argv[3], "sh")) return false;
    if (argv[4].len == 0 or argv[5].len == 0) return false;
    if (std.mem.eql(u8, argv[2], generate_chdir_env_script)) return argv.len > unix_provider_generate_prefix_len;
    return isUnixPackedGenerateScript(argv[2]);
}

pub fn isWindowsProviderGenerateArgv(argv: []const []const u8) bool {
    if (argv.len < 7 or argv.len > max_effect_argv) return false;
    if (!std.mem.eql(u8, argv[0], powershell_bin)) return false;
    if (!std.mem.eql(u8, argv[1], powershell_noprofile)) return false;
    if (!std.mem.eql(u8, argv[2], powershell_command)) return false;
    if (!std.mem.eql(u8, argv[4], powershell_args_flag)) return false;
    if (argv[5].len == 0 or argv[6].len == 0) return false;
    // Cwd stays a `-Args` slot. Do not reject when a short binary
    // name is a substring of a packed literal (Claude `claude` vs
    // `--model claude-haiku-4-5`).
    if (std.mem.indexOf(u8, argv[3], argv[5]) != null) return false;
    if (std.mem.indexOf(u8, argv[3], "$args[0]") == null) return false;
    if (std.mem.indexOf(u8, argv[3], "$args[1]") == null) return false;
    if (std.mem.indexOf(u8, argv[3], "$env:NO_COLOR='1'") == null) return false;
    return std.mem.eql(u8, argv[3], powershell_provider_generate_script) or
        std.mem.indexOf(u8, argv[3], "Set-Location -LiteralPath $args[0]") != null;
}

pub fn isProviderGenerateArgv(argv: []const []const u8) bool {
    return isUnixProviderGenerateArgv(argv) or isWindowsProviderGenerateArgv(argv);
}

pub fn isGenericUnixProviderGenerateArgv(argv: []const []const u8) bool {
    return isUnixProviderGenerateArgv(argv) and std.mem.eql(u8, argv[2], generate_chdir_env_script);
}

pub fn isGenericWindowsProviderGenerateArgv(argv: []const []const u8) bool {
    return isWindowsProviderGenerateArgv(argv) and std.mem.eql(u8, argv[3], powershell_provider_generate_script);
}

/// Slots after the provider binary for the generic wrap. Packed
/// rows keep documented flags as literals in the `-c` / `-Command`
/// script, so this returns empty there.
pub fn providerArgsFromGenerateArgv(argv: []const []const u8) []const []const u8 {
    if (isGenericUnixProviderGenerateArgv(argv)) return argv[unix_provider_generate_prefix_len..];
    if (isGenericWindowsProviderGenerateArgv(argv)) return argv[windows_provider_generate_prefix_len..];
    return &.{};
}

pub fn generateBinaryFromArgv(argv: []const []const u8) []const u8 {
    if (isUnixProviderGenerateArgv(argv)) return argv[5];
    if (isWindowsProviderGenerateArgv(argv)) return argv[6];
    return "";
}

pub fn generateScriptFromArgv(argv: []const []const u8) []const u8 {
    if (isUnixProviderGenerateArgv(argv)) return argv[2];
    if (isWindowsProviderGenerateArgv(argv)) return argv[3];
    return "";
}

pub fn ampSettingsPathFromGenerateArgv(argv: []const []const u8) []const u8 {
    const args = providerArgsFromGenerateArgv(argv);
    var i: usize = 0;
    while (i + 1 < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--settings-file")) return args[i + 1];
    }
    const script = generateScriptFromArgv(argv);
    if (std.mem.indexOf(u8, script, "--settings-file") == null) return "";
    if (isUnixProviderGenerateArgv(argv) and argv.len > 6) return argv[6];
    if (isWindowsProviderGenerateArgv(argv) and argv.len > 7) return argv[7];
    return "";
}

fn generateContains(argv: []const []const u8, needle: []const u8) bool {
    if (hasArg(argv, needle)) return true;
    return std.mem.indexOf(u8, generateScriptFromArgv(argv), needle) != null;
}

pub fn writeAmpSettings(io: std.Io, path: []const u8) bool {
    if (path.len == 0) return false;
    std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = amp_settings_json }) catch return false;
    return true;
}

pub fn deleteAmpSettings(io: std.Io, path: []const u8) void {
    if (path.len == 0) return;
    std.Io.Dir.cwd().deleteFile(io, path) catch {};
}

fn hasArg(argv: []const []const u8, needle: []const u8) bool {
    for (argv) |arg| {
        if (std.mem.eql(u8, arg, needle)) return true;
    }
    return false;
}

fn hasPair(argv: []const []const u8, flag: []const u8, value: []const u8) bool {
    var i: usize = 0;
    while (i + 1 < argv.len) : (i += 1) {
        if (std.mem.eql(u8, argv[i], flag) and std.mem.eql(u8, argv[i + 1], value)) return true;
    }
    return false;
}

fn lastArg(argv: []const []const u8) []const u8 {
    if (argv.len == 0) return "";
    return argv[argv.len - 1];
}

fn expectPromptLast(args: []const []const u8, prompt: []const u8) !void {
    try std.testing.expectEqualStrings(prompt, lastArg(args));
}

fn catalogSpec(id: protocol.ProviderId, prompt: []const u8) GenerateSpec {
    return .{
        .provider = id,
        .cwd = "/tmp/faku-generate",
        .binary = id.defaultBinary(),
        .prompt = prompt,
        .model = "session-model",
        .effort = "high",
        .amp_settings_path = "/tmp/faku-amp-settings.json",
    };
}

fn expectProviderArgs(id: protocol.ProviderId, args: []const []const u8, prompt: []const u8) !void {
    switch (id) {
        .fx => {
            try std.testing.expect(hasArg(args, "ask"));
            try std.testing.expect(hasArg(args, "--no-save"));
            try std.testing.expect(hasArg(args, "--auto"));
            try std.testing.expect(hasArg(args, "--json"));
            try std.testing.expect(hasArg(args, "--"));
            try expectPromptLast(args, prompt);
            try std.testing.expect(!hasArg(args, "--no-color"));
        },
        .amp => {
            try std.testing.expect(hasArg(args, "--execute"));
            try std.testing.expect(hasArg(args, "--no-color"));
            try std.testing.expect(hasArg(args, "--no-ide"));
            try std.testing.expect(hasArg(args, "--no-notifications"));
            try std.testing.expect(hasPair(args, "--settings-file", "/tmp/faku-amp-settings.json"));
            try std.testing.expect(hasPair(args, "--mode", "session-model"));
            try std.testing.expect(hasPair(args, "--effort", "high"));
            try expectPromptLast(args, prompt);
        },
        .claude => {
            try std.testing.expect(hasArg(args, "--print"));
            try std.testing.expect(hasPair(args, "--output-format", "text"));
            try std.testing.expect(hasPair(args, "--permission-mode", "plan"));
            try std.testing.expect(hasPair(args, "--tools", empty_tools));
            try std.testing.expect(hasArg(args, "--disable-slash-commands"));
            try std.testing.expect(hasArg(args, "--no-session-persistence"));
            try std.testing.expect(hasArg(args, "--no-chrome"));
            try std.testing.expect(hasPair(args, "--model", claude_generate_model));
            try std.testing.expect(hasPair(args, "--effort", claude_generate_effort));
            try std.testing.expect(!hasArg(args, "session-model"));
            try std.testing.expect(!hasArg(args, "high"));
            try expectPromptLast(args, prompt);
        },
        .codex => {
            try std.testing.expect(hasArg(args, "exec"));
            try std.testing.expect(hasPair(args, "--sandbox", "read-only"));
            try std.testing.expect(hasArg(args, "--ephemeral"));
            try std.testing.expect(hasPair(args, "--color", "never"));
            try std.testing.expect(hasArg(args, "--skip-git-repo-check"));
            try std.testing.expect(hasPair(args, "--model", codex_generate_model));
            try std.testing.expect(hasPair(args, "-c", codex_generate_effort_config));
            try std.testing.expect(!hasArg(args, "session-model"));
            try expectPromptLast(args, prompt);
        },
        .cursor => {
            try std.testing.expect(hasArg(args, "--print"));
            try std.testing.expect(hasPair(args, "--output-format", "text"));
            try std.testing.expect(hasPair(args, "--mode", "ask"));
            try std.testing.expect(hasPair(args, "--sandbox", "enabled"));
            try std.testing.expect(hasArg(args, "--trust"));
            try std.testing.expect(hasPair(args, "--model", "session-model"));
            try expectPromptLast(args, prompt);
        },
        .deepseek => {
            try std.testing.expect(hasPair(args, "--profile", "headless"));
            try std.testing.expect(!hasArg(args, "--model"));
            try std.testing.expect(!hasArg(args, "session-model"));
            try std.testing.expect(!hasArg(args, "acp"));
            try expectPromptLast(args, prompt);
        },
        .opencode => {
            try std.testing.expect(hasArg(args, "run"));
            try std.testing.expect(hasArg(args, "--pure"));
            try std.testing.expect(hasPair(args, "--agent", "plan"));
            try std.testing.expect(hasPair(args, "--model", "session-model"));
            try std.testing.expect(hasPair(args, "--variant", "high"));
            try std.testing.expect(!hasArg(args, "--standalone"));
            try expectPromptLast(args, prompt);
        },
        .opencode2 => {
            try std.testing.expect(hasArg(args, "run"));
            try std.testing.expect(hasArg(args, "--standalone"));
            try std.testing.expect(hasPair(args, "--agent", "plan"));
            try std.testing.expect(hasPair(args, "--model", "session-model"));
            try std.testing.expect(!hasArg(args, "--pure"));
            try std.testing.expect(!hasArg(args, "--variant"));
            try expectPromptLast(args, prompt);
        },
        .grok => {
            try std.testing.expect(hasPair(args, "--single", prompt));
            try std.testing.expect(hasPair(args, "--output-format", "plain"));
            try std.testing.expect(hasPair(args, "--permission-mode", "plan"));
            try std.testing.expect(hasPair(args, "--tools", empty_tools));
            try std.testing.expect(hasArg(args, "--no-memory"));
            try std.testing.expect(hasArg(args, "--no-subagents"));
            try std.testing.expect(hasArg(args, "--disable-web-search"));
            try std.testing.expect(hasArg(args, "--verbatim"));
            try std.testing.expect(hasPair(args, "--model", "session-model"));
            try std.testing.expect(hasPair(args, "--reasoning-effort", "high"));
            try std.testing.expect(!std.mem.eql(u8, lastArg(args), prompt));
        },
        .pi => {
            try std.testing.expect(hasArg(args, "--print"));
            try std.testing.expect(hasArg(args, "--no-session"));
            try std.testing.expect(hasArg(args, "--no-tools"));
            try std.testing.expect(hasArg(args, "--no-context-files"));
            try std.testing.expect(hasArg(args, "--no-extensions"));
            try std.testing.expect(hasArg(args, "--no-skills"));
            try std.testing.expect(hasArg(args, "--no-prompt-templates"));
            try std.testing.expect(hasArg(args, "--no-approve"));
            try std.testing.expect(hasPair(args, "--model", "session-model"));
            try std.testing.expect(hasPair(args, "--thinking", "high"));
            try expectPromptLast(args, prompt);
        },
        .ohmypi => {
            try std.testing.expect(hasArg(args, "--print"));
            try std.testing.expect(hasArg(args, "--no-session"));
            try std.testing.expect(hasArg(args, "--no-tools"));
            try std.testing.expect(hasArg(args, "--no-rules"));
            try std.testing.expect(hasArg(args, "--no-extensions"));
            try std.testing.expect(hasArg(args, "--no-skills"));
            try std.testing.expect(hasPair(args, "--model", "session-model"));
            try std.testing.expect(hasPair(args, "--thinking", "high"));
            try std.testing.expect(!hasArg(args, "--no-context-files"));
            try expectPromptLast(args, prompt);
        },
        .kimi => {
            try std.testing.expect(hasPair(args, "--prompt", prompt));
            try std.testing.expect(hasPair(args, "--output-format", "text"));
            try std.testing.expect(hasPair(args, "--model", "session-model"));
            try std.testing.expect(!std.mem.eql(u8, lastArg(args), prompt));
        },
    }
}

test "every provider uses a noninteractive generation mode" {
    const prompt = "Write a one-line Git commit subject.";
    var count: usize = 0;
    for (std.meta.tags(protocol.ProviderId)) |id| {
        count += 1;
        var args_buf: [provider_args_len][]const u8 = undefined;
        const args = providerArgsFor(catalogSpec(id, prompt), &args_buf) orelse return error.MissingProviderArgs;
        try std.testing.expect(args.len > 0);
        try std.testing.expect(args.len <= provider_args_len);
        try expectProviderArgs(id, args, prompt);
        if (id != .codex) {
            var i: usize = 0;
            while (i < args.len) : (i += 1) {
                try std.testing.expect(!std.mem.eql(u8, args[i], "--yolo"));
                try std.testing.expect(!std.mem.eql(u8, args[i], "--resume"));
                try std.testing.expect(!std.mem.eql(u8, args[i], "--continue"));
            }
        } else {
            try std.testing.expect(!hasArg(args, "--yolo"));
            try std.testing.expect(!hasArg(args, "--resume"));
            try std.testing.expect(!hasArg(args, "--continue"));
        }
        try std.testing.expect(!hasArg(args, "--input-format"));
    }
    try std.testing.expectEqual(protocol.provider_id_count, count);
}

test "unix provider generate argv prefixes env and chdir; prompt stays a slot" {
    const prompt = "ship the dirty probe";
    var buf: [provider_generate_argv_len][]const u8 = undefined;
    const argv = unixProviderGenerateArgvFor(catalogSpec(.deepseek, prompt), &buf) orelse return error.MissingUnixArgv;
    try std.testing.expect(isUnixProviderGenerateArgv(argv));
    try std.testing.expect(isGenericUnixProviderGenerateArgv(argv));
    try std.testing.expect(isProviderGenerateArgv(argv));
    try std.testing.expect(argv.len <= max_effect_argv);
    try std.testing.expectEqualStrings(sh_bin, argv[0]);
    try std.testing.expectEqualStrings("-c", argv[1]);
    try std.testing.expectEqualStrings(generate_chdir_env_script, argv[2]);
    try std.testing.expectEqualStrings("sh", argv[3]);
    try std.testing.expectEqualStrings("/tmp/faku-generate", argv[4]);
    try std.testing.expectEqualStrings("dsh", argv[5]);
    try std.testing.expectEqualStrings("dsh", generateBinaryFromArgv(argv));
    try std.testing.expect(std.mem.indexOf(u8, argv[2], prompt) == null);
    try std.testing.expect(std.mem.indexOf(u8, argv[2], "dsh") == null);
    const args = providerArgsFromGenerateArgv(argv);
    try expectProviderArgs(.deepseek, args, prompt);
}

test "packed unix generate folds long flag lists into the chdir script" {
    const prompt = "ship the dirty probe";
    var buf: [provider_generate_argv_len][]const u8 = undefined;
    const claude = unixProviderGenerateArgvFor(catalogSpec(.claude, prompt), &buf) orelse return error.MissingUnixClaudePacked;
    try std.testing.expect(isUnixProviderGenerateArgv(claude));
    try std.testing.expect(!isGenericUnixProviderGenerateArgv(claude));
    try std.testing.expect(claude.len <= max_effect_argv);
    try std.testing.expectEqualStrings(unix_packed_claude, claude[2]);
    try std.testing.expectEqualStrings("claude", generateBinaryFromArgv(claude));
    try std.testing.expectEqualStrings(prompt, claude[6]);
    try std.testing.expect(generateContains(claude, "--print"));
    try std.testing.expect(generateContains(claude, claude_generate_model));
    try std.testing.expect(generateContains(claude, claude_generate_effort));
    try std.testing.expect(!generateContains(claude, "session-model"));
    try std.testing.expect(std.mem.indexOf(u8, claude[2], prompt) == null);

    const amp = unixProviderGenerateArgvFor(catalogSpec(.amp, prompt), &buf) orelse return error.MissingUnixAmpPacked;
    try std.testing.expect(isUnixPackedGenerateScript(amp[2]));
    try std.testing.expect(amp.len <= max_effect_argv);
    try std.testing.expectEqualStrings("amp", generateBinaryFromArgv(amp));
    try std.testing.expectEqualStrings("/tmp/faku-amp-settings.json", ampSettingsPathFromGenerateArgv(amp));
    try std.testing.expectEqualStrings("session-model", amp[7]);
    try std.testing.expectEqualStrings("high", amp[8]);
    try std.testing.expectEqualStrings(prompt, amp[9]);
    try std.testing.expect(generateContains(amp, "--execute"));
    try std.testing.expect(generateContains(amp, "--settings-file"));
    try std.testing.expect(std.mem.indexOf(u8, amp[2], prompt) == null);
}

test "every catalog provider host argv stays within Native max_effect_argv" {
    const prompt = "Write a one-line Git commit subject.";
    var unix_buf: [provider_generate_argv_len][]const u8 = undefined;
    var win_buf: [provider_generate_argv_len][]const u8 = undefined;
    for (std.meta.tags(protocol.ProviderId)) |id| {
        if (id == .fx) continue;
        const unix = unixProviderGenerateArgvFor(catalogSpec(id, prompt), &unix_buf) orelse return error.MissingUnixHost;
        try std.testing.expect(unix.len <= max_effect_argv);
        try std.testing.expect(isUnixProviderGenerateArgv(unix));
        try std.testing.expectEqualStrings(id.defaultBinary(), generateBinaryFromArgv(unix));
        const win = windowsProviderGenerateArgvFor(catalogSpec(id, prompt), &win_buf) orelse return error.MissingWindowsHost;
        try std.testing.expect(win.len <= max_effect_argv);
        try std.testing.expect(isWindowsProviderGenerateArgv(win));
        try std.testing.expectEqualStrings(id.defaultBinary(), generateBinaryFromArgv(win));
        try std.testing.expect(std.mem.indexOf(u8, generateScriptFromArgv(win), prompt) == null);
    }
}

test "windows provider generate argv keeps cwd binary and prompt as -Args slots" {
    const prompt = "ship the dirty probe";
    var spec = catalogSpec(.deepseek, prompt);
    spec.cwd = "C:\\Users\\me\\proj";
    spec.binary = "C:\\bin\\dsh.exe";
    var buf: [provider_generate_argv_len][]const u8 = undefined;
    const argv = windowsProviderGenerateArgvFor(spec, &buf) orelse return error.MissingWindowsArgv;
    try std.testing.expect(isWindowsProviderGenerateArgv(argv));
    try std.testing.expect(isProviderGenerateArgv(argv));
    try std.testing.expectEqualStrings(powershell_bin, argv[0]);
    try std.testing.expectEqualStrings(powershell_provider_generate_script, argv[3]);
    try std.testing.expectEqualStrings(spec.cwd, argv[5]);
    try std.testing.expectEqualStrings(spec.binary, argv[6]);
    try std.testing.expect(std.mem.indexOf(u8, argv[3], spec.cwd) == null);
    try std.testing.expect(std.mem.indexOf(u8, argv[3], spec.binary) == null);
    try std.testing.expect(std.mem.indexOf(u8, argv[3], prompt) == null);
    try std.testing.expect(std.mem.indexOf(u8, argv[3], "$args[0]") != null);
    try std.testing.expect(std.mem.indexOf(u8, argv[3], "$args[1]") != null);
    try std.testing.expect(std.mem.indexOf(u8, argv[3], "exit $LASTEXITCODE") != null);
    const args = providerArgsFromGenerateArgv(argv);
    try expectProviderArgs(.deepseek, args, prompt);
}

test "amp generate requires a settings path; optional mode and effort omit when empty" {
    var missing_buf: [provider_args_len][]const u8 = undefined;
    try std.testing.expect(providerArgsFor(.{
        .provider = .amp,
        .cwd = "/tmp/faku-generate",
        .binary = "amp",
        .prompt = "subject",
        .amp_settings_path = "",
    }, &missing_buf) == null);
    try std.testing.expect(providerArgsFor(.{
        .provider = .amp,
        .cwd = "/tmp/faku-generate",
        .binary = "",
        .prompt = "subject",
        .amp_settings_path = "/tmp/s.json",
    }, &missing_buf) == null);

    var args_buf: [provider_args_len][]const u8 = undefined;
    const args = providerArgsFor(.{
        .provider = .amp,
        .cwd = "/tmp/faku-generate",
        .binary = "/opt/amp",
        .prompt = "subject",
        .amp_settings_path = "/tmp/s.json",
    }, &args_buf) orelse return error.MissingAmpArgs;
    try std.testing.expect(hasPair(args, "--settings-file", "/tmp/s.json"));
    try std.testing.expect(!hasArg(args, "--mode"));
    try std.testing.expect(!hasArg(args, "--effort"));
    try expectPromptLast(args, "subject");
}

test "grok and kimi keep the prompt on the documented flag, not last positional" {
    var args_buf: [provider_args_len][]const u8 = undefined;
    const grok = providerArgsFor(catalogSpec(.grok, "plain subject"), &args_buf) orelse return error.MissingGrok;
    try std.testing.expect(hasPair(grok, "--single", "plain subject"));
    try std.testing.expect(!std.mem.eql(u8, lastArg(grok), "plain subject"));

    const kimi = providerArgsFor(catalogSpec(.kimi, "plain subject"), &args_buf) orelse return error.MissingKimi;
    try std.testing.expect(hasPair(kimi, "--prompt", "plain subject"));
    try std.testing.expect(!std.mem.eql(u8, lastArg(kimi), "plain subject"));
}

test "providerGenerateArgvFor skips fx so today's JSON ask path stays in git_commit" {
    var buf: [provider_generate_argv_len][]const u8 = undefined;
    try std.testing.expect(providerGenerateArgvFor(catalogSpec(.fx, "subject"), &buf) == null);
    const deepseek = providerGenerateArgvFor(catalogSpec(.deepseek, "subject"), &buf) orelse return error.MissingDeepSeekHost;
    try std.testing.expect(isProviderGenerateArgv(deepseek));
}

test "writeAmpSettings then deleteAmpSettings removes the temp JSON" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [256]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, ".zig-cache/tmp/{s}/amp-settings.json", .{tmp.sub_path[0..]});
    const dir = std.fs.path.dirname(path) orelse return error.MissingAmpDir;
    try std.Io.Dir.cwd().createDirPath(std.testing.io, dir);
    try std.testing.expect(writeAmpSettings(std.testing.io, path));
    try std.testing.expect(util.fileExists(std.testing.io, path));
    const body = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, std.testing.allocator, .limited(256));
    defer std.testing.allocator.free(body);
    try std.testing.expectEqualStrings(amp_settings_json, body);
    deleteAmpSettings(std.testing.io, path);
    try std.testing.expect(!util.fileExists(std.testing.io, path));
}
