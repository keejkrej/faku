//! Settings Providers: fx probe status plus non-fx `--help` probes.
//!
//! Settings page. Lists every `protocol.ProviderId` as a runtime-only
//! row. fx (first-party default) reads existing `model.fx_available` /
//! `fxPath()` — no new probe key. Other ids one-shot PATH
//! `{probeBinary()} --help` via `cli_probe.zig` (persisted override
//! when set, else PATH `defaultBinary()`; Available / Not found when
//! that exit lands). Boot (`initFx`) starts non-fx probes
//! alongside the fx probe; Settings → Providers open calls
//! `startProbes` (no-op when already started). Refresh re-runs
//! fx_probe and every non-fx probe. Selecting a row highlights
//! and shows detail; Apply ("Use for this session") sets the selected
//! chat session's `provider` and persists via `sessions.json`. First-cut
//! per-row Enable/Disable persists `disabled_providers` (wire names) on
//! that same extras bag. Expand chevron + binary-path override persist
//! `provider_binary_overrides` (wireName → path object; omit empty)
//! on that same bag. One expanded row at a time (runtime-only
//! `provider_expanded_id`); switching applies the previous draft.
//! OpenCode 2 expanded row also persists optional `opencode2_attach_url`
//! (string; missing / empty / overflow → empty = cold `run`) and
//! copies `{binary} serve` when Available (`copyOpencode2Serve`;
//! honor `provider_binary_overrides` / `binaryFor`; hide / no-op
//! when Not found; clipboard only, never spawns serve). DeepSeek
//! expanded row copies `{binary} web` when Available
//! (`copyDeepseekWeb`; documented `dsh web` alias for `--profile
//! web`; honor `provider_binary_overrides` / `binaryFor`; hide /
//! no-op when Not found; clipboard only, never spawns web). The
//! Enable/Disable chip is disable-flag-only
//! (user can toggle regardless of install). `providerEnabled` (the
//! plan-usage `maybeRefresh` gate) is `!disabled && isAvailable`.
//! Disabled or Not-found / unset skips background plan-usage refresh
//! unless the selected session already uses that id; a started session
//! on a disabled or uninstalled provider still works and still fetches
//! when selected. New
//! sessions stay `.fx`. Live Send for probed ACP stdio providers
//! (cursor, opencode, kimi, grok, deepseek) is `spawn.startPrompt`
//! (first-cut ACP v1 image content blocks when a composer image is
//! attached, except DeepSeek which fail-closes to demo — official dsh
//! ACP advertises no image capability); Available Claude
//! is one-shot print-mode stream-json (`claude -p --output-format
//! stream-json --verbose --include-partial-messages
//! --forward-subagent-text`; documented
//! `--resume {fx_session_id}` on later Sends when that field is
//! non-empty; first Send and Fork omit it; not `--continue`;
//! documented image path inside that `-p` prompt when a composer image is
//! attached; stdout is NDJSON with live `text_delta`; live Subagent
//! Background from `parent_tool_use_id` plus a bounded 512KB
//! last-window from forwarded `parent_tool_use_id` text; live Monitor Background from
//! Claude `Monitor` `tool_use` plus a bounded 512KB last-window
//! log from matching user `tool_result` (Environment Summary
//! stays a one-line preview; right-panel Background shows the
//! stored log with CSI stripped); Available Codex is one-shot `codex exec {prompt}`
//! (documented `--image {path}` after the prompt when a composer image
//! is attached); Available Amp is
//! one-shot `amp -x {prompt}` (`--execute` is the long form; documented
//! `@{path}` in the `-x` prompt when a composer image is attached);
//! Available Pi is
//! one-shot `pi --mode rpc --no-session` (stdin prompt JSONL;
//! documented RPC `images` when a composer image is attached);
//! Available Oh My Pi is one-shot `omp --mode rpc --yolo --no-session`
//! (same Pi RPC parser / stdin prompt JSONL / RPC `images`; Waku
//! `PiFlavor::OhMyPi` full-access arg `--yolo`; `--no-session` is a
//! documented omp flag used by Waku model discovery). Available OpenCode 2 is
//! one-shot `{binary} run --format json --auto` (documented `--session`
//! / `--model` / `--file`; documented `--attach {url}` when
//! `opencode2_attach_url` is set; not `opencode acp`; user-owned
//! serve; Copy serve command ships; in-app HTTP/SSE serve client stays deferred). Available DeepSeek is one-shot `dsh --profile acp`
//! via acp-proxy (not `dsh acp`; composer image fail-closes to demo;
//! Copy web command ships; Harness HTTP/SSE / in-app web client stay
//! deferred; `--profile headless` ships on empty-Commit… generate
//! only). fx
//! Not found copies the verified keejkrej/fx install script
//! (Unix `releases/latest/download/install` curl|bash into `~/.fx/bin`;
//! Windows `install.ps1` irm|iex on the same latest release; clipboard
//! only, never auto-runs; not fx.sh). fx Available copies
//! `fx login` the same way — convenience copy, not auth-state detection
//! or OAuth UI. Other missing CLIs get a muted PATH hint only (no
//! invented install URLs). Status / Apply / Copy / First-party
//! follow `i18n.ProvidersChrome`. Enable %{name} / Disable %{name}
//! chip follows `i18n.ProvidersEnableNamedChrome` (short Enable /
//! Disable stay for non-button uses). Detail transport notes, fx login notes,
//! the other-CLI PATH hint, and `Binary:` / `Path:` prefixes follow
//! `i18n.ProvidersDetailChrome`. Coding agents card title /
//! description / Checked … caption follow
//! `i18n.ProvidersCodingAgentsChrome` (Faku-adapted Waku
//! `providers.description`; Refresh lives in the Coding agents
//! card via `i18n.SettingsRefreshChrome`; Skills / Usage Refresh
//! stay in the Settings header). Expand chevron Show/Hide %{provider} settings and
//! Binary path override follow `i18n.ProvidersBinaryOverrideChrome`
//! (Faku, not Waku, in product-named strings). OpenCode 2 Serve attach
//! URL follows `i18n.ProvidersOpencodeAttachChrome` (Faku, not Waku;
//! user-owned serve; Faku only passes `--attach`). Copy serve command
//! follows `i18n.ProvidersOpencodeServeChrome` (clipboard
//! `{binary} serve` when Available; honor override; hide / no-op
//! when Not found). Copy web command follows
//! `i18n.ProvidersDeepseekWebChrome` (clipboard `{binary} web` when
//! Available; honor override; hide / no-op when Not found; Faku
//! does not spawn web). Model-count /
//! disabled caption follows `i18n.ProvidersModelCountChrome`
//! (static Waku `fallback_models` lengths; Latin digits). Tests do not
//! need a live daemon or any real CLI install.
//!
//! Leftovers: full onboarding / OAuth / auto-install; Pi ACP /
//! long-lived RPC (steer / follow_up / session resume); Claude ACP; `--continue`; circular GPUI gauge;
//! LiteLLM rate-table; T3 layered Usage chart; amend/force and
//! remote `--track` over daemon (local already); Native-blocked UI
//! (gauge / chart fill / DevTools / edge fades / sticky / KaTeX);
//! OpenCode 2 HTTP/SSE serve client (Copy serve command ships;
//! Faku still does not spawn serve); DeepSeek Harness HTTP/SSE /
//! in-app web client (Copy web command ships; Faku still does not
//! spawn web). `--profile headless` ships on empty-Commit…
//! generate only.
//! Settings Daemon first-cut ships this cut (nav + external-only
//! page). Version badge ships
//! this cut (runtime `{binary} --version` parse; muted `v{version}`
//! beside Available names). Refresh-in-card ships this cut.
//! model_count ships this cut (static Waku `fallback_models`
//! lengths; Available enabled paints N model(s); Available
//! disabled paints Disabled for new tasks; empty-catalog /
//! Not found omit). Provider row icons (`app:provider-*`) ship
//! this cut (Native `list-item` `icon="{p.icon}"`; Codex uses the
//! OpenAI mark). Colored status-dot overlays ship this cut (Native
//! `●` with `foreground="success"` when Available and
//! `foreground="text_muted"` when Not found; `{p.status}` stays
//! beside the glyph so availability is not color-only).
//! Disabling does not
//! move unstarted drafts / last_provider (Faku new sessions stay fx;
//! drafts.json has no provider).
//! Claude print-mode stream-json (later Sends pass documented
//! `--resume {fx_session_id}` when that field is non-empty; first
//! Send and Fork omit it; `--forward-subagent-text` always;
//! image path in the `-p` prompt when
//! attached),
//! Codex exec (`--image` when attached), Amp
//! execute-mode (`@path` when attached), Pi RPC one-shot
//! (`--mode rpc --no-session`, stdin prompt JSONL, RPC `images` when
//! attached), and Oh My Pi RPC one-shot (`--mode rpc --yolo
//! --no-session`, same stdin / images path) ship this cut (not ACP,
//! not a long-lived RPC loop, not `--mode json`, not permissions
//! bypass). OpenCode 2 one-shot `run --format json --auto` ships this
//! cut (display **OpenCode 2**; not `opencode acp`; documented
//! `--attach {url}` when `opencode2_attach_url` is set; user-owned
//! serve; Copy serve command ships; in-app HTTP/SSE serve client still deferred). DeepSeek one-shot
//! `dsh --profile acp` via acp-proxy ships this cut (display **DeepSeek**;
//! no image attach; Copy web command ships; Harness HTTP/SSE / in-app
//! web client still deferred; `--profile headless` ships on
//! empty-Commit… generate only). Appearance theme,
//! Usage, and Computer Use first-cut pages ship (Computer Use is
//! Unavailable / Off; no Native helper). Not Waku install/auth.

const std = @import("std");
const builtin = @import("builtin");
const main = @import("main.zig");
const model_exports = @import("model_exports.zig");
const sidecar_keys = @import("sidecar_keys.zig");
const protocol = @import("protocol.zig");
const fx_probe = @import("fx_probe.zig");
const cli_probe = @import("cli_probe.zig");
const cli_version = @import("cli_version.zig");
const copy_helpers = @import("copy.zig");
const i18n = @import("i18n.zig");

const Model = model_exports.Model;
const Effects = main.Effects;

fn chrome(model: *const Model) i18n.ProvidersChrome {
    return i18n.providersChromeFor(model.language_preference, model.systemLocaleId());
}

fn detailChrome(model: *const Model) i18n.ProvidersDetailChrome {
    return i18n.providersDetailChromeFor(model.language_preference, model.systemLocaleId());
}

/// English defaults from `i18n.ProvidersChrome`. Tests and callers that
/// still want the former hardcoded copy use these; rows / detail /
/// status resolve through `chrome` for the Appearance locale.
const providers_chrome_en = i18n.providersChromeFor(.english, "");
/// English defaults from `i18n.ProvidersDetailChrome`. Tests that
/// still want the former EN literals use these; `detailText` and
/// Model getters resolve through `detailChrome` for the Appearance
/// locale.
const providers_detail_chrome_en = i18n.providersDetailChromeFor(.english, "");
pub const available_status = providers_chrome_en.available;
pub const missing_status = providers_chrome_en.not_found;
pub const fx_available_status = available_status;
pub const fx_missing_status = missing_status;
pub const catalog_detail_note = providers_detail_chrome_en.catalog_detail_note;
pub const first_party_label = providers_chrome_en.first_party;
pub const fx_transport_note = providers_detail_chrome_en.fx_transport_note;
pub const acp_transport_note = providers_detail_chrome_en.acp_transport_note;
pub const grok_transport_note = providers_detail_chrome_en.grok_transport_note;
pub const claude_transport_note = providers_detail_chrome_en.claude_transport_note;
pub const codex_transport_note = providers_detail_chrome_en.codex_transport_note;
pub const amp_transport_note = providers_detail_chrome_en.amp_transport_note;
pub const pi_transport_note = providers_detail_chrome_en.pi_transport_note;
pub const ohmypi_transport_note = providers_detail_chrome_en.ohmypi_transport_note;
pub const opencode2_transport_note = providers_detail_chrome_en.opencode2_transport_note;
pub const deepseek_transport_note = providers_detail_chrome_en.deepseek_transport_note;
pub const apply_session_label = providers_chrome_en.apply;
/// Working keejkrej/fx Unix install script on the latest GitHub Release.
/// Copied to the clipboard on Unix hosts; never auto-run. Not fx.sh.
/// Lands in `~/.fx/bin`.
pub const fx_install_command = "curl -fsSL https://github.com/keejkrej/fx/releases/latest/download/install | bash";
/// Working keejkrej/fx Windows PowerShell install on the same latest
/// GitHub Release (`install.ps1`). Copied to the clipboard on Windows
/// hosts; never auto-run. Not fx.sh.
pub const fx_install_command_windows = "irm https://github.com/keejkrej/fx/releases/latest/download/install.ps1 | iex";
/// Convenience copy only. Fork pitch is also `fx login grok` / `fx login codex`.
pub const fx_login_command = "fx login";
pub const copy_install_label = providers_chrome_en.copy_install;
pub const copy_login_label = providers_chrome_en.copy_login;
/// English default from `i18n.ProvidersOpencodeServeChrome`. Distinct
/// from Copy install / Copy login.
pub const copy_serve_label = i18n.providersOpencodeServeChromeFor(.english, "").copy_serve;
/// English default from `i18n.ProvidersDeepseekWebChrome`. Distinct
/// from Copy install / Copy login / Copy serve.
pub const copy_web_label = i18n.providersDeepseekWebChromeFor(.english, "").copy_web;
pub const fx_login_note = providers_detail_chrome_en.fx_login_note;
pub const fx_login_codex_note = providers_detail_chrome_en.fx_login_codex_note;
pub const other_install_hint = providers_detail_chrome_en.other_install_hint;
pub const enable_label = providers_chrome_en.enable;
pub const disable_label = providers_chrome_en.disable;

/// English defaults from `i18n.ProvidersEnableNamedChrome`. Distinct
/// from ProvidersChrome Enable / Disable. Named Enable %{name} /
/// Disable %{name} is the Settings row chip.
const providers_enable_named_chrome_en = i18n.providersEnableNamedChromeFor(.english, "");
pub const enable_named_template = providers_enable_named_chrome_en.enable_named;
pub const disable_named_template = providers_enable_named_chrome_en.disable_named;

/// Settings Providers row. `id` is 1-based `@intFromEnum(ProviderId)`
/// so Native `select_provider:{p.id}` / `toggle_provider_enabled:{p.id}`
/// never bind 0.
pub const ProviderRow = struct {
    id: u32,
    name: []const u8,
    status: []const u8,
    binary: []const u8,
    has_binary: bool = false,
    first_party: bool = false,
    selected: bool = false,
    /// Settings Enable/Disable chip: persisted `!disabled_providers`
    /// only. Not the `providerEnabled` gate (that also ANDs installed).
    enabled: bool = true,
    /// Named Enable %{name} / Disable %{name} via
    /// `i18n.ProvidersEnableNamedChrome`. Arena-owned when built
    /// through `rowFor` / `rows`. Distinct from short Enable /
    /// Disable (`enable_label` / `disable_label` constants).
    enable_label: []const u8 = disable_label,
    /// First-party badge. Empty on non-fx rows; markup gates on
    /// `first_party`. Localized via `i18n.ProvidersChrome`.
    first_party_label: []const u8 = "",
    /// Runtime-only expand chevron. One row at a time.
    expanded: bool = false,
    /// Show/Hide %{provider} settings. Arena-owned when built
    /// through `rowFor` / `rows`.
    expand_label: []const u8 = "",
    /// Persisted override is non-empty (Reset control visible).
    has_override: bool = false,
    /// using_override / invalid_override / detected_at / detected_as /
    /// searches_path. Arena-owned. Empty when none.
    override_caption: []const u8 = "",
    has_override_caption: bool = false,
    /// Binary path description with %{provider}. Arena-owned.
    binary_path_description: []const u8 = "",
    /// OpenCode 2 expanded row only. Markup gates the Serve attach
    /// URL field on this flag.
    show_opencode_attach: bool = false,
    /// DeepSeek expanded row only. Markup gates Copy web command on
    /// this flag so the button never paints on unrelated rows.
    show_deepseek_web: bool = false,
    /// Persisted `opencode2_attach_url` is non-empty (Reset visible).
    has_opencode_attach: bool = false,
    /// Painted `v{token}` when Available and the `--version` parse
    /// succeeded. Empty otherwise. Arena-owned. Latin data, not i18n.
    version: []const u8 = "",
    has_version: bool = false,
    /// Muted model-count / disabled caption when Available.
    /// Disabled paints `disabled_for_new_tasks`; else static
    /// fallback catalog one/many when count > 0. Empty on
    /// Not found and empty-catalog Available rows. Arena-owned
    /// when formatted from a count template.
    model_count_label: []const u8 = "",
    has_model_count: bool = false,
    /// Leading Native `app:provider-*` mark. Codex uses the OpenAI
    /// registry name (`app:provider-openai`). Static, not arena-owned.
    icon: []const u8 = "",
    /// Colored Native status-dot overlay flags. `rowFor` sets them
    /// from `isAvailable` (same source as `{p.status}`). Markup
    /// paints `●` with `foreground="success"` when Available and
    /// `text_muted` when Not found; `{p.status}` stays beside the
    /// glyph so availability is not color-only. Complementary: one
    /// is true, the other false.
    status_available: bool = false,
    status_missing: bool = false,
};

/// Waku `provider-*.svg` registry name for a catalog id. Codex uses
/// the OpenAI mark. Markup binds `icon="{p.icon}"` on the Providers
/// `list-item`.
pub fn iconName(id: protocol.ProviderId) []const u8 {
    return switch (id) {
        .fx => "app:provider-fx",
        .claude => "app:provider-claude",
        .codex => "app:provider-openai",
        .amp => "app:provider-amp",
        .grok => "app:provider-grok",
        .opencode => "app:provider-opencode",
        .cursor => "app:provider-cursor",
        .pi => "app:provider-pi",
        .kimi => "app:provider-kimi",
        .ohmypi => "app:provider-ohmypi",
        .opencode2 => "app:provider-opencode2",
        .deepseek => "app:provider-deepseek",
    };
}

pub fn catalogLen() usize {
    return std.meta.tags(protocol.ProviderId).len;
}

pub fn rowId(id: protocol.ProviderId) u32 {
    return @as(u32, @intFromEnum(id)) + 1;
}

pub fn fromRowId(id: u32) ?protocol.ProviderId {
    if (id == 0) return null;
    const tags = std.meta.tags(protocol.ProviderId);
    const index = id - 1;
    if (index >= tags.len) return null;
    return tags[index];
}

pub fn isAvailable(model: *const Model, id: protocol.ProviderId) bool {
    if (id == .fx) return model.fx_available;
    return model.cli_available[@intFromEnum(id)];
}

/// First-cut Waku `provider_enabled`: not in persisted
/// `disabled_providers` **and** PATH `--help` probe-installed
/// (`isAvailable`: fx → `fx_available`, others → `cli_available`).
/// Boot starts non-fx probes so cadence is not starved until Settings
/// → Providers opens. Until a probe exit lands, availability defaults
/// false (unselected plan-usage providers stay skipped). Settings
/// Enable/Disable chip is still disable-flag-only (`rowFor.enabled`).
pub fn providerEnabled(model: *const Model, id: protocol.ProviderId) bool {
    if (model.disabled_providers[@intFromEnum(id)]) return false;
    return isAvailable(model, id);
}

pub fn setProviderEnabled(model: *Model, id: protocol.ProviderId, enabled: bool) void {
    model.disabled_providers[@intFromEnum(id)] = !enabled;
}

/// Toggle persisted enable for the 1-based Providers row. No-op on an
/// unknown id. Returns true when the flag changed.
pub fn toggleProviderEnabled(model: *Model, row_id: u32) bool {
    const id = fromRowId(row_id) orelse return false;
    const index = @intFromEnum(id);
    model.disabled_providers[index] = !model.disabled_providers[index];
    return true;
}

pub fn statusFor(model: *const Model, id: protocol.ProviderId) []const u8 {
    const pack = chrome(model);
    if (isAvailable(model, id)) return pack.available;
    return pack.not_found;
}

/// Persisted override when set (absolute or as stored), else probed
/// fx path when that probe succeeded, else PATH `defaultBinary`.
/// Empty override means PATH detect. Spawn / probe fail closed when
/// this is empty.
pub fn binaryFor(model: *const Model, id: protocol.ProviderId) []const u8 {
    const override = model.providerBinaryOverride(id);
    if (override.len > 0) return override;
    if (id == .fx and model.fx_available) {
        const path = model.fxPath();
        if (path.len > 0) return path;
    }
    return id.defaultBinary();
}

fn overrideChrome(model: *const Model) i18n.ProvidersBinaryOverrideChrome {
    return i18n.providersBinaryOverrideChromeFor(model.language_preference, model.systemLocaleId());
}

fn modelCountChrome(model: *const Model) i18n.ProvidersModelCountChrome {
    return i18n.providersModelCountChromeFor(model.language_preference, model.systemLocaleId());
}

/// Static Waku `fallback_models(provider)` lengths. Live discovery
/// stays out this cut. Empty-catalog ids (fx / grok / kimi /
/// opencode / pi / ohmypi / opencode2 / deepseek) return 0 — do not invent catalogs.
pub fn fallbackModelCount(id: protocol.ProviderId) usize {
    return switch (id) {
        .amp => 4,
        .codex => 5,
        .claude => 9,
        .cursor => 1,
        .fx, .grok, .kimi, .opencode, .pi, .ohmypi, .opencode2, .deepseek => 0,
    };
}

fn seedOverrideDraft(model: *Model, id: protocol.ProviderId) void {
    model.provider_override_buffer.set(model.providerBinaryOverride(id));
}

fn seedAttachDraft(model: *Model, id: protocol.ProviderId) void {
    if (id == .opencode2) {
        model.opencode2_attach_buffer.set(model.opencode2AttachUrl());
    } else {
        model.opencode2_attach_buffer.clear();
    }
}

/// Apply the expanded row's Binary path draft. Empty / whitespace
/// clears the override (PATH detect). Restarts that provider's
/// `--help` probe when the stored path changes. Returns true when
/// the persisted override changed.
pub fn applyPathOverride(model: *Model, fx: *Effects) bool {
    const id = fromRowId(model.provider_expanded_id) orelse return false;
    const trimmed = std.mem.trim(u8, model.provider_override_buffer.text(), " \t\r\n");
    const current = model.providerBinaryOverride(id);
    if (std.mem.eql(u8, trimmed, current)) return false;
    model.setProviderBinaryOverride(id, trimmed);
    model.provider_override_buffer.set(model.providerBinaryOverride(id));
    restartProbeFor(model, fx, id);
    return true;
}

/// Clear the expanded row's persisted override and draft, then
/// re-probe PATH. Returns true when an override was cleared.
pub fn clearPathOverride(model: *Model, fx: *Effects) bool {
    const id = fromRowId(model.provider_expanded_id) orelse return false;
    if (model.providerBinaryOverride(id).len == 0) {
        model.provider_override_buffer.clear();
        return false;
    }
    model.setProviderBinaryOverride(id, "");
    model.provider_override_buffer.clear();
    restartProbeFor(model, fx, id);
    return true;
}

/// Apply the OpenCode 2 expanded row's Serve attach URL draft.
/// Empty / whitespace / overflow clears (cold `run`). Returns true
/// when the persisted URL changed. No-op when another row is expanded.
pub fn applyAttachUrl(model: *Model) bool {
    const id = fromRowId(model.provider_expanded_id) orelse return false;
    if (id != .opencode2) return false;
    const trimmed = std.mem.trim(u8, model.opencode2_attach_buffer.text(), " \t\r\n");
    const current = model.opencode2AttachUrl();
    if (std.mem.eql(u8, trimmed, current)) return false;
    model.setOpencode2AttachUrl(trimmed);
    model.opencode2_attach_buffer.set(model.opencode2AttachUrl());
    return true;
}

/// Clear the OpenCode 2 attach URL and draft. Returns true when a
/// URL was cleared. No-op when another row is expanded.
pub fn clearAttachUrl(model: *Model) bool {
    const id = fromRowId(model.provider_expanded_id) orelse return false;
    if (id != .opencode2) {
        model.opencode2_attach_buffer.clear();
        return false;
    }
    if (model.opencode2AttachUrl().len == 0) {
        model.opencode2_attach_buffer.clear();
        return false;
    }
    model.setOpencode2AttachUrl("");
    model.opencode2_attach_buffer.clear();
    return true;
}

fn restartProbeFor(model: *Model, fx: *Effects, id: protocol.ProviderId) void {
    if (id == .fx) {
        if (model.providerBinaryOverride(.fx).len > 0) {
            model.setFxPath(model.providerBinaryOverride(.fx));
        } else {
            model.fx_path_len = 0;
        }
        model.fx_available = false;
        fx_probe.restartFxProbe(model, fx);
        return;
    }
    model.cli_available[@intFromEnum(id)] = false;
    cli_probe.restartCliProbe(model, fx, id);
}

/// Toggle the expand chevron. One expanded at a time. Switching
/// applies the previous row's pending draft first. Same-row toggle
/// applies then collapses.
pub fn toggleExpanded(model: *Model, fx: *Effects, row_id: u32) bool {
    const id = fromRowId(row_id) orelse return false;
    if (model.provider_expanded_id != 0 and model.provider_expanded_id != row_id) {
        _ = applyPathOverride(model, fx);
        _ = applyAttachUrl(model);
    }
    if (model.provider_expanded_id == row_id) {
        _ = applyPathOverride(model, fx);
        _ = applyAttachUrl(model);
        model.provider_expanded_id = 0;
        model.provider_override_buffer.clear();
        model.opencode2_attach_buffer.clear();
        return true;
    }
    model.provider_expanded_id = row_id;
    seedOverrideDraft(model, id);
    seedAttachDraft(model, id);
    return true;
}

fn expandLabelFor(model: *const Model, id: protocol.ProviderId, expanded: bool, arena: std.mem.Allocator) []const u8 {
    var buf: [i18n.providers_binary_override_label_max]u8 = undefined;
    const text = i18n.formatProvidersExpandSettings(overrideChrome(model), expanded, id.displayName(), &buf);
    return copyNamed(arena, text);
}

fn binaryPathDescriptionFor(model: *const Model, id: protocol.ProviderId, arena: std.mem.Allocator) []const u8 {
    var buf: [i18n.providers_binary_override_label_max]u8 = undefined;
    const text = i18n.formatProvidersBinaryPathDescription(overrideChrome(model), id.displayName(), &buf);
    return copyNamed(arena, text);
}

fn overrideCaptionFor(model: *const Model, id: protocol.ProviderId, arena: std.mem.Allocator) []const u8 {
    const pack = overrideChrome(model);
    const override = model.providerBinaryOverride(id);
    var buf: [i18n.providers_binary_override_caption_max]u8 = undefined;
    const text = if (override.len > 0)
        if (isAvailable(model, id))
            i18n.formatProvidersUsingOverride(pack, override, &buf)
        else
            pack.invalid_override
    else if (id == .fx and isAvailable(model, .fx) and model.fxPath().len > 0)
        i18n.formatProvidersDetectedAt(pack, model.fxPath(), &buf)
    else if (isAvailable(model, id))
        i18n.formatProvidersDetectedAs(pack, id.defaultBinary(), &buf)
    else
        i18n.formatProvidersSearchesPath(pack, id.defaultBinary(), &buf);
    return copyNamed(arena, text);
}

fn copyNamed(arena: std.mem.Allocator, text: []const u8) []const u8 {
    if (text.len == 0) return "";
    const out = arena.alloc(u8, text.len) catch return "";
    @memcpy(out, text);
    return out;
}

/// Named Enable %{name} / Disable %{name} for a catalog row.
/// Localized via `i18n.ProvidersEnableNamedChrome`. Distinct from
/// ProvidersChrome Enable / Disable. Empty name still paints.
/// Writes through `arena` like Skills `enableLabel`.
pub fn enableLabelFor(model: *const Model, id: protocol.ProviderId, arena: std.mem.Allocator) []const u8 {
    const named = i18n.providersEnableNamedChromeFor(model.language_preference, model.systemLocaleId());
    const enabled = !model.disabled_providers[@intFromEnum(id)];
    var buf: [i18n.providers_enable_named_max]u8 = undefined;
    const text = i18n.formatProvidersEnableNamed(named, enabled, id.displayName(), &buf);
    return copyNamed(arena, text);
}

fn versionLabelFor(token: []const u8, arena: std.mem.Allocator) []const u8 {
    if (token.len == 0) return "";
    const out = arena.alloc(u8, token.len + 1) catch return "";
    out[0] = 'v';
    @memcpy(out[1..], token);
    return out;
}

fn modelCountLabelFor(model: *const Model, id: protocol.ProviderId, enabled: bool, arena: std.mem.Allocator) []const u8 {
    if (!isAvailable(model, id)) return "";
    const pack = modelCountChrome(model);
    if (!enabled) return pack.disabled_for_new_tasks;
    const count = fallbackModelCount(id);
    if (count == 0) return "";
    var buf: [i18n.providers_model_count_label_max]u8 = undefined;
    const text = i18n.formatProvidersModelCount(pack, count, &buf);
    return copyNamed(arena, text);
}

/// `arena` owns `enable_label` (named Enable %{name} / Disable
/// %{name}), the optional `v{version}` badge, and the optional
/// formatted model-count caption. Callers of `rows`
/// pass the Native frame arena. Tests pass an ArenaAllocator (or any
/// allocator that outlives the row).
pub fn rowFor(model: *const Model, id: protocol.ProviderId, arena: std.mem.Allocator) ProviderRow {
    const binary = binaryFor(model, id);
    const rid = rowId(id);
    const enabled = !model.disabled_providers[@intFromEnum(id)];
    const pack = chrome(model);
    const token = cli_version.providerVersion(model, id);
    const available = isAvailable(model, id);
    const version = if (available) versionLabelFor(token, arena) else "";
    const model_count_label = modelCountLabelFor(model, id, enabled, arena);
    return .{
        .id = rid,
        .name = id.displayName(),
        .status = statusFor(model, id),
        .binary = binary,
        .has_binary = binary.len > 0,
        .first_party = id == .fx,
        .selected = model.provider_selected_id == rid,
        .enabled = enabled,
        .enable_label = enableLabelFor(model, id, arena),
        .first_party_label = if (id == .fx) pack.first_party else "",
        .expanded = model.provider_expanded_id == rid,
        .expand_label = expandLabelFor(model, id, model.provider_expanded_id == rid, arena),
        .has_override = model.providerBinaryOverride(id).len > 0,
        .override_caption = overrideCaptionFor(model, id, arena),
        .has_override_caption = true,
        .binary_path_description = binaryPathDescriptionFor(model, id, arena),
        .show_opencode_attach = id == .opencode2,
        .has_opencode_attach = id == .opencode2 and model.opencode2AttachUrl().len > 0,
        .show_deepseek_web = id == .deepseek,
        .version = version,
        .has_version = version.len > 0,
        .model_count_label = model_count_label,
        .has_model_count = model_count_label.len > 0,
        .icon = iconName(id),
        .status_available = available,
        .status_missing = !available,
    };
}

pub fn rows(model: *const Model, arena: std.mem.Allocator) []const ProviderRow {
    if (model.settings_page != .providers) return &.{};
    const tags = std.meta.tags(protocol.ProviderId);
    const out = arena.alloc(ProviderRow, tags.len) catch return &.{};
    for (tags, 0..) |id, i| {
        out[i] = rowFor(model, id, arena);
    }
    return out;
}

pub fn detailText(model: *const Model, arena: std.mem.Allocator) []const u8 {
    const id = fromRowId(model.provider_selected_id) orelse return "";
    const pack = chrome(model);
    const notes = detailChrome(model);
    const override = model.providerBinaryOverride(id);
    const shown_binary = if (override.len > 0) override else id.defaultBinary();
    if (id == .fx) {
        const path = if (override.len > 0) override else model.fxPath();
        if ((model.fx_available or override.len > 0) and path.len > 0) {
            return std.fmt.allocPrint(arena, "{s}\n{s}\n{s} {s}\n{s} {s}\n{s}", .{
                id.displayName(),
                pack.first_party,
                notes.binary_prefix,
                shown_binary,
                notes.path_prefix,
                path,
                notes.fx_transport_note,
            }) catch "";
        }
        return std.fmt.allocPrint(arena, "{s}\n{s}\n{s} {s}\n{s}\n{s}", .{
            id.displayName(),
            pack.first_party,
            notes.binary_prefix,
            shown_binary,
            pack.not_found,
            notes.fx_transport_note,
        }) catch "";
    }
    const note = if (id == .grok)
        notes.grok_transport_note
    else if (id == .claude)
        notes.claude_transport_note
    else if (id == .codex)
        notes.codex_transport_note
    else if (id == .amp)
        notes.amp_transport_note
    else if (id == .pi)
        notes.pi_transport_note
    else if (id == .ohmypi)
        notes.ohmypi_transport_note
    else if (id == .opencode2)
        notes.opencode2_transport_note
    else if (id == .deepseek)
        notes.deepseek_transport_note
    else if (id.speaksBareAcp())
        notes.acp_transport_note
    else
        notes.catalog_detail_note;
    if (override.len > 0) {
        return std.fmt.allocPrint(arena, "{s}\n{s} {s}\n{s} {s}\n{s}\n{s}", .{
            id.displayName(),
            notes.binary_prefix,
            shown_binary,
            notes.path_prefix,
            override,
            statusFor(model, id),
            note,
        }) catch "";
    }
    return std.fmt.allocPrint(arena, "{s}\n{s} {s}\n{s}\n{s}", .{
        id.displayName(),
        notes.binary_prefix,
        shown_binary,
        statusFor(model, id),
        note,
    }) catch "";
}

pub fn selectProvider(model: *Model, id: u32) void {
    if (fromRowId(id) == null) {
        model.provider_selected_id = 0;
        return;
    }
    model.provider_selected_id = id;
}

/// True when a valid Providers row is highlighted and a chat session
/// is selected. Row press does not apply; Apply is explicit.
pub fn canApplyToSession(model: *const Model) bool {
    if (fromRowId(model.provider_selected_id) == null) return false;
    return model.sessionByIdConst(model.selected) != null;
}

/// Sets the selected session's `provider` from the highlighted
/// Providers row. No-op when there is no selected session or the row
/// id is unknown. Does not spawn; Send path is `spawn.startPrompt`.
pub fn applyToSession(model: *Model) bool {
    const id = fromRowId(model.provider_selected_id) orelse return false;
    const session = model.sessionById(model.selected) orelse return false;
    session.provider = id;
    return true;
}

/// Highlighted row is fx and the `--help` probe did not find it.
pub fn canCopyFxInstall(model: *const Model) bool {
    const id = fromRowId(model.provider_selected_id) orelse return false;
    return id == .fx and !isAvailable(model, .fx);
}

/// Highlighted row is fx and the `--help` probe found it. Auth
/// state is not probed; this only gates the login-command copy.
pub fn canCopyFxLogin(model: *const Model) bool {
    const id = fromRowId(model.provider_selected_id) orelse return false;
    return id == .fx and isAvailable(model, .fx);
}

/// Highlighted non-fx row is Not found. Muted PATH hint only.
pub fn showsOtherInstallHint(model: *const Model) bool {
    const id = fromRowId(model.provider_selected_id) orelse return false;
    return id != .fx and !isAvailable(model, id);
}

/// Host-OS Copy install command: Unix curl|bash, Windows irm|iex.
/// Clipboard-only; never auto-run. Not fx.sh.
pub fn fxInstallCommand() []const u8 {
    return fxInstallCommandForOs(builtin.os.tag);
}

/// Same verified commands as README. Unix keeps today's curl|bash;
/// Windows copies `install.ps1` irm|iex. Other tags stay Unix.
pub fn fxInstallCommandForOs(tag: std.Target.Os.Tag) []const u8 {
    return switch (tag) {
        .windows => fx_install_command_windows,
        else => fx_install_command,
    };
}

/// Copy the verified fx install command for this host OS. No-op when
/// the install button would be hidden. Does not spawn a shell.
pub fn copyFxInstall(model: *const Model, fx: *Effects) void {
    if (!canCopyFxInstall(model)) return;
    copy_helpers.copyText(fx, fxInstallCommand());
}

/// Copy `fx login`. No-op when the login button would be hidden.
/// Does not spawn fx or start OAuth.
pub fn copyFxLogin(model: *const Model, fx: *Effects) void {
    if (!canCopyFxLogin(model)) return;
    copy_helpers.copyText(fx, fx_login_command);
}

/// `{binary} serve` scratch: override path cap plus the documented
/// OpenCode CLI subcommand. Same class as `max_fx_path` argv[0].
pub const opencode2_serve_command_max: usize = model_exports.max_fx_path + " serve".len;

/// Documented OpenCode CLI `serve` (https://opencode.ai/docs/cli/#serve).
/// Binary is `providers.binaryFor` (override, else PATH `opencode2`).
pub fn opencode2ServeCommand(model: *const Model, buf: []u8) []const u8 {
    const binary = binaryFor(model, .opencode2);
    if (binary.len == 0) return "";
    return std.fmt.bufPrint(buf, "{s} serve", .{binary}) catch "";
}

/// OpenCode 2 PATH `--help` probe found it. Clipboard-only gate for
/// Copy serve command; does not spawn `serve` or probe HTTP/SSE.
pub fn canCopyOpencode2Serve(model: *const Model) bool {
    return isAvailable(model, .opencode2);
}

/// Copy `{binary} serve`. No-op when the button would be hidden
/// (OpenCode 2 Not found / unset). Does not spawn serve.
pub fn copyOpencode2Serve(model: *const Model, fx: *Effects) void {
    if (!canCopyOpencode2Serve(model)) return;
    var buf: [opencode2_serve_command_max]u8 = undefined;
    copy_helpers.copyText(fx, opencode2ServeCommand(model, &buf));
}

/// `{binary} web` scratch: override path cap plus the documented
/// DeepSeek CLI web alias. Same class as `opencode2_serve_command_max`.
pub const deepseek_web_command_max: usize = model_exports.max_fx_path + " web".len;

/// Documented DeepSeek Harness CLI `web` (hardcoded alias for
/// `--profile web`; https://github.com/deepseek-ai/deepseek-harness).
/// Binary is `providers.binaryFor` (override, else PATH `dsh`).
pub fn deepseekWebCommand(model: *const Model, buf: []u8) []const u8 {
    const binary = binaryFor(model, .deepseek);
    if (binary.len == 0) return "";
    return std.fmt.bufPrint(buf, "{s} web", .{binary}) catch "";
}

/// DeepSeek PATH `--help` probe found it. Clipboard-only gate for
/// Copy web command; does not spawn `web` or probe HTTP/SSE.
pub fn canCopyDeepseekWeb(model: *const Model) bool {
    return isAvailable(model, .deepseek);
}

/// Copy `{binary} web`. No-op when the button would be hidden
/// (DeepSeek Not found / unset). Does not spawn web.
pub fn copyDeepseekWeb(model: *const Model, fx: *Effects) void {
    if (!canCopyDeepseekWeb(model)) return;
    var buf: [deepseek_web_command_max]u8 = undefined;
    copy_helpers.copyText(fx, deepseekWebCommand(model, &buf));
}

pub fn close(model: *Model, fx: *Effects) void {
    _ = applyPathOverride(model, fx);
    _ = applyAttachUrl(model);
    model.provider_expanded_id = 0;
    model.provider_override_buffer.clear();
    model.opencode2_attach_buffer.clear();
    model.provider_selected_id = 0;
}

/// Non-fx PATH `--help` probes only. Boot (`initFx`) also calls this
/// via `cli_probe.startCliProbes`. Settings → Providers open is a
/// no-op when already started. Does not restart fx.
pub fn startProbes(model: *Model, fx: *Effects) void {
    cli_probe.startCliProbes(model, fx);
}

/// Re-run fx `--help` and every non-fx PATH `--help` probe.
/// Clears the Coding agents Checked … stamp so the caption hides
/// while probes are in flight (Waku hides Checked while `checking`).
pub fn refresh(model: *Model, fx: *Effects) void {
    model.provider_detection_checked_at_ms = 0;
    fx_probe.restartFxProbe(model, fx);
    cli_probe.restartCliProbes(model, fx);
}

test "catalog lists every ProviderId; fx is row 1" {
    const tags = std.meta.tags(protocol.ProviderId);
    try std.testing.expectEqual(@as(usize, 12), catalogLen());
    try std.testing.expectEqual(protocol.provider_id_count, catalogLen());
    try std.testing.expectEqual(@as(usize, 12), tags.len);
    try std.testing.expectEqual(protocol.ProviderId.fx, tags[0]);
    try std.testing.expectEqual(@as(u32, 1), rowId(.fx));
    try std.testing.expectEqual(@as(u32, 2), rowId(.claude));
    try std.testing.expectEqual(@as(u32, 8), rowId(.pi));
    try std.testing.expectEqual(@as(u32, 9), rowId(.kimi));
    try std.testing.expectEqual(@as(u32, 10), rowId(.ohmypi));
    try std.testing.expectEqual(@as(u32, 11), rowId(.opencode2));
    try std.testing.expectEqual(@as(u32, 12), rowId(.deepseek));
    try std.testing.expectEqual(protocol.ProviderId.fx, fromRowId(1).?);
    try std.testing.expectEqual(protocol.ProviderId.claude, fromRowId(2).?);
    try std.testing.expectEqual(protocol.ProviderId.pi, fromRowId(8).?);
    try std.testing.expectEqual(protocol.ProviderId.kimi, fromRowId(9).?);
    try std.testing.expectEqual(protocol.ProviderId.ohmypi, fromRowId(10).?);
    try std.testing.expectEqual(protocol.ProviderId.opencode2, fromRowId(11).?);
    try std.testing.expectEqual(protocol.ProviderId.deepseek, fromRowId(12).?);
    try std.testing.expect(fromRowId(0) == null);
    try std.testing.expect(fromRowId(13) == null);
    try std.testing.expectEqualStrings("fx", protocol.ProviderId.fx.wireName());
    try std.testing.expectEqualStrings("cursor-agent", protocol.ProviderId.cursor.defaultBinary());
    try std.testing.expectEqualStrings("kimi", protocol.ProviderId.kimi.wireName());
    try std.testing.expectEqualStrings("kimi", protocol.ProviderId.kimi.defaultBinary());
    try std.testing.expectEqualStrings("ohmypi", protocol.ProviderId.ohmypi.wireName());
    try std.testing.expectEqualStrings("omp", protocol.ProviderId.ohmypi.defaultBinary());
    try std.testing.expectEqualStrings("ohMyPi", protocol.ProviderId.ohmypi.daemonProviderKind());
    try std.testing.expectEqualStrings("Oh My Pi", protocol.ProviderId.ohmypi.displayName());
    try std.testing.expectEqualStrings("app:provider-ohmypi", iconName(.ohmypi));
    try std.testing.expectEqualStrings("opencode2", protocol.ProviderId.opencode2.wireName());
    try std.testing.expectEqualStrings("opencode2", protocol.ProviderId.opencode2.defaultBinary());
    try std.testing.expectEqualStrings("openCode2", protocol.ProviderId.opencode2.daemonProviderKind());
    try std.testing.expectEqualStrings("OpenCode 2", protocol.ProviderId.opencode2.displayName());
    try std.testing.expectEqualStrings("app:provider-opencode2", iconName(.opencode2));
    try std.testing.expectEqualStrings("deepseek", protocol.ProviderId.deepseek.wireName());
    try std.testing.expectEqualStrings("dsh", protocol.ProviderId.deepseek.defaultBinary());
    try std.testing.expectEqualStrings("deepSeek", protocol.ProviderId.deepseek.daemonProviderKind());
    try std.testing.expectEqualStrings("DeepSeek", protocol.ProviderId.deepseek.displayName());
    try std.testing.expectEqualStrings("app:provider-deepseek", iconName(.deepseek));
}

test "fx status from model fields without spawning; non-fx defaults Not found" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var model = Model{};
    try std.testing.expectEqualStrings(missing_status, statusFor(&model, .fx));
    try std.testing.expectEqualStrings("fx", binaryFor(&model, .fx));
    try std.testing.expectEqualStrings(missing_status, statusFor(&model, .claude));
    try std.testing.expectEqualStrings(missing_status, statusFor(&model, .codex));
    try std.testing.expectEqualStrings(missing_status, statusFor(&model, .amp));
    try std.testing.expectEqualStrings(missing_status, statusFor(&model, .grok));
    try std.testing.expectEqualStrings(missing_status, statusFor(&model, .opencode));
    try std.testing.expectEqualStrings(missing_status, statusFor(&model, .cursor));
    try std.testing.expectEqualStrings(missing_status, statusFor(&model, .pi));
    try std.testing.expectEqualStrings(missing_status, statusFor(&model, .kimi));
    try std.testing.expectEqualStrings(missing_status, statusFor(&model, .ohmypi));
    try std.testing.expectEqualStrings(missing_status, statusFor(&model, .opencode2));
    try std.testing.expectEqualStrings("cursor-agent", binaryFor(&model, .cursor));
    try std.testing.expectEqualStrings("claude", binaryFor(&model, .claude));
    try std.testing.expectEqualStrings("kimi", binaryFor(&model, .kimi));
    try std.testing.expectEqualStrings("omp", binaryFor(&model, .ohmypi));
    try std.testing.expectEqualStrings("opencode2", binaryFor(&model, .opencode2));

    model.fx_available = true;
    model.setFxPath("/tmp/faku-fx");
    try std.testing.expectEqualStrings(available_status, statusFor(&model, .fx));
    try std.testing.expectEqualStrings("/tmp/faku-fx", binaryFor(&model, .fx));
    try std.testing.expectEqualStrings(missing_status, statusFor(&model, .claude));

    const fx_row = rowFor(&model, .fx, arena);
    try std.testing.expect(fx_row.first_party);
    try std.testing.expectEqualStrings(first_party_label, fx_row.first_party_label);
    try std.testing.expectEqualStrings(available_status, fx_row.status);
    try std.testing.expect(fx_row.status_available);
    try std.testing.expect(!fx_row.status_missing);
    try std.testing.expect(!rowFor(&model, .claude, arena).first_party);
    try std.testing.expectEqualStrings("", rowFor(&model, .claude, arena).first_party_label);
    try std.testing.expect(!rowFor(&model, .claude, arena).status_available);
    try std.testing.expect(rowFor(&model, .claude, arena).status_missing);
}

test "non-fx success exit is Available; non-zero is Not found; fx stays on fx_available" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    cli_probe.handleCliProbeExit(&model, &fx, .{
        .key = cli_probe.probeKey(.claude),
        .reason = .exited,
        .code = 0,
    });
    try std.testing.expectEqualStrings(available_status, statusFor(&model, .claude));
    try std.testing.expectEqualStrings("claude", binaryFor(&model, .claude));
    try std.testing.expectEqualStrings(missing_status, statusFor(&model, .fx));
    try std.testing.expect(!rowFor(&model, .claude, arena).has_version);

    cli_probe.handleCliProbeExit(&model, &fx, .{
        .key = cli_probe.probeKey(.codex),
        .reason = .exited,
        .code = 127,
    });
    try std.testing.expectEqualStrings(missing_status, statusFor(&model, .codex));

    model.fx_available = true;
    try std.testing.expectEqualStrings(available_status, statusFor(&model, .fx));
    try std.testing.expectEqualStrings(available_status, rowFor(&model, .claude, arena).status);
    try std.testing.expect(rowFor(&model, .claude, arena).status_available);
    try std.testing.expect(!rowFor(&model, .claude, arena).status_missing);
    try std.testing.expectEqualStrings(missing_status, rowFor(&model, .codex, arena).status);
    try std.testing.expect(!rowFor(&model, .codex, arena).status_available);
    try std.testing.expect(rowFor(&model, .codex, arena).status_missing);
}

test "selectProvider; detail names binary, fx path, probe status, and one-shot acp-proxy" {
    const testing = std.testing;
    var model = Model{};
    model.fx_available = true;
    model.setFxPath("/home/probe/.local/bin/fx");
    selectProvider(&model, 1);
    try testing.expectEqual(@as(u32, 1), model.provider_selected_id);
    const fx_detail = detailText(&model, testing.allocator);
    defer if (fx_detail.len > 0) testing.allocator.free(fx_detail);
    try testing.expect(std.mem.indexOf(u8, fx_detail, "fx") != null);
    try testing.expect(std.mem.indexOf(u8, fx_detail, first_party_label) != null);
    try testing.expect(std.mem.indexOf(u8, fx_detail, "Binary: fx") != null);
    try testing.expect(std.mem.indexOf(u8, fx_detail, "Path: /home/probe/.local/bin/fx") != null);
    try testing.expect(std.mem.indexOf(u8, fx_detail, "/home/probe/.local/bin/fx") != null);
    try testing.expect(std.mem.indexOf(u8, fx_detail, fx_transport_note) != null);
    try testing.expect(std.mem.indexOf(u8, fx_detail, catalog_detail_note) == null);

    selectProvider(&model, 2);
    try testing.expectEqual(@as(u32, 2), model.provider_selected_id);
    const claude_detail = detailText(&model, testing.allocator);
    defer if (claude_detail.len > 0) testing.allocator.free(claude_detail);
    try testing.expect(std.mem.indexOf(u8, claude_detail, "claude") != null);
    try testing.expect(std.mem.indexOf(u8, claude_detail, "Binary: claude") != null);
    try testing.expect(std.mem.indexOf(u8, claude_detail, missing_status) != null);
    try testing.expect(std.mem.indexOf(u8, claude_detail, claude_transport_note) != null);
    try testing.expect(std.mem.indexOf(u8, claude_detail, catalog_detail_note) == null);
    try testing.expect(std.mem.indexOf(u8, claude_detail, fx_transport_note) == null);
    try testing.expect(std.mem.indexOf(u8, claude_detail, acp_transport_note) == null);

    model.cli_available[@intFromEnum(protocol.ProviderId.claude)] = true;
    const claude_ok = detailText(&model, testing.allocator);
    defer if (claude_ok.len > 0) testing.allocator.free(claude_ok);
    try testing.expect(std.mem.indexOf(u8, claude_ok, available_status) != null);
    try testing.expect(std.mem.indexOf(u8, claude_ok, claude_transport_note) != null);
    try testing.expect(std.mem.indexOf(u8, claude_ok, catalog_detail_note) == null);
    try testing.expect(std.mem.indexOf(u8, claude_ok, acp_transport_note) == null);

    selectProvider(&model, rowId(.codex));
    try testing.expectEqual(rowId(.codex), model.provider_selected_id);
    const codex_detail = detailText(&model, testing.allocator);
    defer if (codex_detail.len > 0) testing.allocator.free(codex_detail);
    try testing.expect(std.mem.indexOf(u8, codex_detail, "codex") != null);
    try testing.expect(std.mem.indexOf(u8, codex_detail, missing_status) != null);
    try testing.expect(std.mem.indexOf(u8, codex_detail, codex_transport_note) != null);
    try testing.expect(std.mem.indexOf(u8, codex_detail, catalog_detail_note) == null);
    try testing.expect(std.mem.indexOf(u8, codex_detail, fx_transport_note) == null);
    try testing.expect(std.mem.indexOf(u8, codex_detail, acp_transport_note) == null);
    try testing.expect(std.mem.indexOf(u8, codex_detail, claude_transport_note) == null);

    model.cli_available[@intFromEnum(protocol.ProviderId.codex)] = true;
    const codex_ok = detailText(&model, testing.allocator);
    defer if (codex_ok.len > 0) testing.allocator.free(codex_ok);
    try testing.expect(std.mem.indexOf(u8, codex_ok, available_status) != null);
    try testing.expect(std.mem.indexOf(u8, codex_ok, codex_transport_note) != null);
    try testing.expect(std.mem.indexOf(u8, codex_ok, catalog_detail_note) == null);
    try testing.expect(std.mem.indexOf(u8, codex_ok, acp_transport_note) == null);

    selectProvider(&model, rowId(.amp));
    const amp_detail = detailText(&model, testing.allocator);
    defer if (amp_detail.len > 0) testing.allocator.free(amp_detail);
    try testing.expect(std.mem.indexOf(u8, amp_detail, "amp") != null);
    try testing.expect(std.mem.indexOf(u8, amp_detail, missing_status) != null);
    try testing.expect(std.mem.indexOf(u8, amp_detail, amp_transport_note) != null);
    try testing.expect(std.mem.indexOf(u8, amp_detail, catalog_detail_note) == null);
    try testing.expect(std.mem.indexOf(u8, amp_detail, codex_transport_note) == null);
    try testing.expect(std.mem.indexOf(u8, amp_detail, fx_transport_note) == null);
    try testing.expect(std.mem.indexOf(u8, amp_detail, acp_transport_note) == null);
    try testing.expect(std.mem.indexOf(u8, amp_detail, claude_transport_note) == null);

    model.cli_available[@intFromEnum(protocol.ProviderId.amp)] = true;
    const amp_ok = detailText(&model, testing.allocator);
    defer if (amp_ok.len > 0) testing.allocator.free(amp_ok);
    try testing.expect(std.mem.indexOf(u8, amp_ok, available_status) != null);
    try testing.expect(std.mem.indexOf(u8, amp_ok, amp_transport_note) != null);
    try testing.expect(std.mem.indexOf(u8, amp_ok, catalog_detail_note) == null);
    try testing.expect(std.mem.indexOf(u8, amp_ok, acp_transport_note) == null);

    selectProvider(&model, rowId(.pi));
    const pi_detail = detailText(&model, testing.allocator);
    defer if (pi_detail.len > 0) testing.allocator.free(pi_detail);
    try testing.expect(std.mem.indexOf(u8, pi_detail, "pi") != null);
    try testing.expect(std.mem.indexOf(u8, pi_detail, missing_status) != null);
    try testing.expect(std.mem.indexOf(u8, pi_detail, pi_transport_note) != null);
    try testing.expect(std.mem.indexOf(u8, pi_detail, catalog_detail_note) == null);
    try testing.expect(std.mem.indexOf(u8, pi_detail, amp_transport_note) == null);
    try testing.expect(std.mem.indexOf(u8, pi_detail, codex_transport_note) == null);
    try testing.expect(std.mem.indexOf(u8, pi_detail, fx_transport_note) == null);
    try testing.expect(std.mem.indexOf(u8, pi_detail, acp_transport_note) == null);
    try testing.expect(std.mem.indexOf(u8, pi_detail, claude_transport_note) == null);

    model.cli_available[@intFromEnum(protocol.ProviderId.pi)] = true;
    const pi_ok = detailText(&model, testing.allocator);
    defer if (pi_ok.len > 0) testing.allocator.free(pi_ok);
    try testing.expect(std.mem.indexOf(u8, pi_ok, available_status) != null);
    try testing.expect(std.mem.indexOf(u8, pi_ok, pi_transport_note) != null);
    try testing.expect(std.mem.indexOf(u8, pi_ok, catalog_detail_note) == null);
    try testing.expect(std.mem.indexOf(u8, pi_ok, acp_transport_note) == null);

    selectProvider(&model, rowId(.cursor));
    try testing.expectEqual(rowId(.cursor), model.provider_selected_id);
    const cursor_detail = detailText(&model, testing.allocator);
    defer if (cursor_detail.len > 0) testing.allocator.free(cursor_detail);
    try testing.expect(std.mem.indexOf(u8, cursor_detail, "cursor") != null);
    try testing.expect(std.mem.indexOf(u8, cursor_detail, "cursor-agent") != null);
    try testing.expect(std.mem.indexOf(u8, cursor_detail, acp_transport_note) != null);
    try testing.expect(std.mem.indexOf(u8, cursor_detail, catalog_detail_note) == null);
    try testing.expect(std.mem.indexOf(u8, cursor_detail, fx_transport_note) == null);

    model.cli_available[@intFromEnum(protocol.ProviderId.opencode)] = true;
    selectProvider(&model, rowId(.opencode));
    try testing.expectEqual(rowId(.opencode), model.provider_selected_id);
    const opencode_detail = detailText(&model, testing.allocator);
    defer if (opencode_detail.len > 0) testing.allocator.free(opencode_detail);
    try testing.expect(std.mem.indexOf(u8, opencode_detail, "opencode") != null);
    try testing.expect(std.mem.indexOf(u8, opencode_detail, available_status) != null);
    try testing.expect(std.mem.indexOf(u8, opencode_detail, acp_transport_note) != null);
    try testing.expect(std.mem.indexOf(u8, opencode_detail, catalog_detail_note) == null);
    try testing.expect(std.mem.indexOf(u8, opencode_detail, fx_transport_note) == null);

    model.cli_available[@intFromEnum(protocol.ProviderId.grok)] = true;
    selectProvider(&model, rowId(.grok));
    try testing.expectEqual(rowId(.grok), model.provider_selected_id);
    const grok_detail = detailText(&model, testing.allocator);
    defer if (grok_detail.len > 0) testing.allocator.free(grok_detail);
    try testing.expect(std.mem.indexOf(u8, grok_detail, "grok") != null);
    try testing.expect(std.mem.indexOf(u8, grok_detail, available_status) != null);
    try testing.expect(std.mem.indexOf(u8, grok_detail, grok_transport_note) != null);
    try testing.expect(std.mem.indexOf(u8, grok_detail, catalog_detail_note) == null);
    try testing.expect(std.mem.indexOf(u8, grok_detail, acp_transport_note) == null);
    try testing.expect(std.mem.indexOf(u8, grok_detail, fx_transport_note) == null);
    try testing.expect(std.mem.indexOf(u8, grok_detail, claude_transport_note) == null);
    try testing.expect(std.mem.indexOf(u8, grok_detail, codex_transport_note) == null);
    try testing.expect(std.mem.indexOf(u8, grok_detail, amp_transport_note) == null);
    try testing.expect(std.mem.indexOf(u8, grok_detail, pi_transport_note) == null);

    model.cli_available[@intFromEnum(protocol.ProviderId.kimi)] = true;
    selectProvider(&model, rowId(.kimi));
    try testing.expectEqual(rowId(.kimi), model.provider_selected_id);
    const kimi_detail = detailText(&model, testing.allocator);
    defer if (kimi_detail.len > 0) testing.allocator.free(kimi_detail);
    try testing.expect(std.mem.indexOf(u8, kimi_detail, "kimi") != null);
    try testing.expect(std.mem.indexOf(u8, kimi_detail, available_status) != null);
    try testing.expect(std.mem.indexOf(u8, kimi_detail, acp_transport_note) != null);
    try testing.expect(std.mem.indexOf(u8, kimi_detail, catalog_detail_note) == null);
    try testing.expect(std.mem.indexOf(u8, kimi_detail, fx_transport_note) == null);
    try testing.expect(std.mem.indexOf(u8, kimi_detail, grok_transport_note) == null);
    try testing.expect(std.mem.indexOf(u8, kimi_detail, pi_transport_note) == null);

    model.cli_available[@intFromEnum(protocol.ProviderId.ohmypi)] = true;
    selectProvider(&model, rowId(.ohmypi));
    try testing.expectEqual(rowId(.ohmypi), model.provider_selected_id);
    const ohmypi_detail = detailText(&model, testing.allocator);
    defer if (ohmypi_detail.len > 0) testing.allocator.free(ohmypi_detail);
    try testing.expect(std.mem.indexOf(u8, ohmypi_detail, "Oh My Pi") != null);
    try testing.expect(std.mem.indexOf(u8, ohmypi_detail, "omp") != null);
    try testing.expect(std.mem.indexOf(u8, ohmypi_detail, available_status) != null);
    try testing.expect(std.mem.indexOf(u8, ohmypi_detail, ohmypi_transport_note) != null);
    try testing.expect(std.mem.indexOf(u8, ohmypi_detail, catalog_detail_note) == null);
    try testing.expect(std.mem.indexOf(u8, ohmypi_detail, pi_transport_note) == null);
    try testing.expect(std.mem.indexOf(u8, ohmypi_detail, acp_transport_note) == null);
    try testing.expect(std.mem.indexOf(u8, ohmypi_detail, fx_transport_note) == null);

    model.cli_available[@intFromEnum(protocol.ProviderId.opencode2)] = true;
    selectProvider(&model, rowId(.opencode2));
    try testing.expectEqual(rowId(.opencode2), model.provider_selected_id);
    const opencode2_detail = detailText(&model, testing.allocator);
    defer if (opencode2_detail.len > 0) testing.allocator.free(opencode2_detail);
    try testing.expect(std.mem.indexOf(u8, opencode2_detail, "OpenCode 2") != null);
    try testing.expect(std.mem.indexOf(u8, opencode2_detail, "opencode2") != null);
    try testing.expect(std.mem.indexOf(u8, opencode2_detail, available_status) != null);
    try testing.expect(std.mem.indexOf(u8, opencode2_detail, opencode2_transport_note) != null);
    try testing.expect(std.mem.indexOf(u8, opencode2_detail, catalog_detail_note) == null);
    try testing.expect(std.mem.indexOf(u8, opencode2_detail, acp_transport_note) == null);
    try testing.expect(std.mem.indexOf(u8, opencode2_detail, ohmypi_transport_note) == null);
    try testing.expect(std.mem.indexOf(u8, opencode2_detail, fx_transport_note) == null);

    model.cli_available[@intFromEnum(protocol.ProviderId.deepseek)] = true;
    selectProvider(&model, rowId(.deepseek));
    try testing.expectEqual(rowId(.deepseek), model.provider_selected_id);
    const deepseek_detail = detailText(&model, testing.allocator);
    defer if (deepseek_detail.len > 0) testing.allocator.free(deepseek_detail);
    try testing.expect(std.mem.indexOf(u8, deepseek_detail, "DeepSeek") != null);
    try testing.expect(std.mem.indexOf(u8, deepseek_detail, "dsh") != null);
    try testing.expect(std.mem.indexOf(u8, deepseek_detail, available_status) != null);
    try testing.expect(std.mem.indexOf(u8, deepseek_detail, deepseek_transport_note) != null);
    try testing.expect(std.mem.indexOf(u8, deepseek_detail, catalog_detail_note) == null);
    try testing.expect(std.mem.indexOf(u8, deepseek_detail, acp_transport_note) == null);
    try testing.expect(std.mem.indexOf(u8, deepseek_detail, opencode2_transport_note) == null);
    try testing.expect(std.mem.indexOf(u8, deepseek_detail, fx_transport_note) == null);

    try testing.expect(protocol.ProviderId.cursor.speaksBareAcp());
    try testing.expect(protocol.ProviderId.opencode.speaksBareAcp());
    try testing.expect(protocol.ProviderId.kimi.speaksBareAcp());
    try testing.expect(!protocol.ProviderId.claude.speaksBareAcp());
    try testing.expect(!protocol.ProviderId.fx.speaksBareAcp());
    try testing.expect(!protocol.ProviderId.grok.speaksBareAcp());
    try testing.expect(!protocol.ProviderId.opencode2.speaksBareAcp());
    try testing.expect(!protocol.ProviderId.opencode2.speaksPiRpc());
    try testing.expect(!protocol.ProviderId.opencode2.speaksAcpStdio());
    try testing.expect(protocol.ProviderId.opencode2.speaksOpencodeRun());
    try testing.expect(!protocol.ProviderId.opencode.speaksOpencodeRun());
    try testing.expect(!protocol.ProviderId.deepseek.speaksBareAcp());
    try testing.expect(!protocol.ProviderId.deepseek.speaksPiRpc());
    try testing.expect(protocol.ProviderId.deepseek.speaksAcpStdio());
    try testing.expect(protocol.ProviderId.grok.speaksAcpStdio());
    try testing.expect(protocol.ProviderId.cursor.speaksAcpStdio());
    try testing.expect(protocol.ProviderId.kimi.speaksAcpStdio());

    selectProvider(&model, 99);
    try testing.expectEqual(@as(u32, 0), model.provider_selected_id);
    try testing.expectEqualStrings("", detailText(&model, testing.allocator));
}

test "applyToSession sets selected session provider; unknown id and empty selection no-op" {
    const testing = std.testing;
    var model = Model{};
    const id = model.addSession("thread", .fx);
    model.selected = id;
    try testing.expectEqual(protocol.ProviderId.fx, model.sessionByIdConst(id).?.provider);
    try testing.expect(!canApplyToSession(&model));
    try testing.expect(!applyToSession(&model));
    try testing.expectEqual(protocol.ProviderId.fx, model.sessionByIdConst(id).?.provider);

    selectProvider(&model, rowId(.claude));
    try testing.expect(canApplyToSession(&model));
    try testing.expect(applyToSession(&model));
    try testing.expectEqual(protocol.ProviderId.claude, model.sessionByIdConst(id).?.provider);
    try testing.expectEqualStrings("claude", model.sessionByIdConst(id).?.provider_label());

    selectProvider(&model, rowId(.fx));
    try testing.expect(applyToSession(&model));
    try testing.expectEqual(protocol.ProviderId.fx, model.sessionByIdConst(id).?.provider);

    model.provider_selected_id = 99;
    try testing.expect(!canApplyToSession(&model));
    try testing.expect(!applyToSession(&model));
    try testing.expectEqual(protocol.ProviderId.fx, model.sessionByIdConst(id).?.provider);

    selectProvider(&model, rowId(.pi));
    model.selected = 0;
    try testing.expect(!canApplyToSession(&model));
    try testing.expect(!applyToSession(&model));
    try testing.expectEqual(protocol.ProviderId.fx, model.sessionByIdConst(id).?.provider);

    model.selected = id;
    const other = model.addSession("other", .codex);
    selectProvider(&model, rowId(.amp));
    try testing.expect(applyToSession(&model));
    try testing.expectEqual(protocol.ProviderId.amp, model.sessionByIdConst(id).?.provider);
    try testing.expectEqual(protocol.ProviderId.codex, model.sessionByIdConst(other).?.provider);
}

test "applyToSession persistIfPossible writes provider on a started session skeleton" {
    const testing = std.testing;
    const store = @import("store.zig");
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-apply-provider-unit", .{tmp.sub_path[0..]});

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.task_state_loaded = true;
    model.setStoreDir(dir);
    model.store_io = testing.io;
    const id = model.addSession("apply me", .fx);
    _ = model.appendTurn(id, .user, "started");
    model.selected = id;
    selectProvider(&model, rowId(.claude));
    try testing.expect(applyToSession(&model));
    store.persistIfPossible(&model, id, &fx);

    var loaded = Model{};
    loaded.setStoreDir(dir);
    loaded.store_io = testing.io;
    try testing.expectEqual(store.LoadKind.loaded, store.loadCatalog(&loaded, testing.allocator, testing.io));
    try testing.expectEqual(@as(u32, 1), loaded.session_count);
    try testing.expectEqual(protocol.ProviderId.claude, loaded.session_store[0].provider);
    try testing.expectEqualStrings("claude", loaded.session_store[0].provider_label());
}

test "refresh queues fx_probe_key and every non-fx PATH --help probe" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.fx_probe_started = true;
    model.fx_available = true;
    model.setFxPath("/tmp/faku-fx");
    model.provider_detection_checked_at_ms = 12_345;
    try testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());

    refresh(&model, &fx);
    try testing.expectEqual(@as(i64, 0), model.provider_detection_checked_at_ms);
    try testing.expect(model.fx_probe_started);
    var saw_fx = false;
    var cli_n: usize = 0;
    var i: usize = 0;
    while (fx.pendingSpawnAt(i)) |item| : (i += 1) {
        if (item.key == fx_probe.fx_probe_key and fx_probe.isFxProbeArgv(item.argv)) {
            saw_fx = true;
            continue;
        }
        if (cli_probe.fromProbeKey(item.key)) |id| {
            try testing.expect(id != .fx);
            try testing.expect(cli_probe.isCliProbeArgv(item.argv, id));
            try testing.expect(item.key != fx_probe.fx_probe_key);
            cli_n += 1;
        }
    }
    try testing.expect(saw_fx);
    try testing.expectEqual(cli_probe.nonFxCount(), cli_n);
}

test "startProbes does not queue fx_probe_key" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    startProbes(&model, &fx);
    var i: usize = 0;
    while (fx.pendingSpawnAt(i)) |item| : (i += 1) {
        try testing.expect(item.key != fx_probe.fx_probe_key);
        try testing.expect(!fx_probe.isFxProbeArgv(item.argv));
    }
    try testing.expectEqual(cli_probe.nonFxCount(), i);
}

test "initFx queues fx --help and every non-fx PATH --help probe; startProbes is then a no-op" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    main.initFx(&model, &fx);
    try testing.expect(model.fx_probe_started);

    var saw_fx = false;
    var cli_n: usize = 0;
    var i: usize = 0;
    while (fx.pendingSpawnAt(i)) |item| : (i += 1) {
        if (item.key == fx_probe.fx_probe_key and fx_probe.isFxProbeArgv(item.argv)) {
            saw_fx = true;
            continue;
        }
        if (cli_probe.fromProbeKey(item.key)) |id| {
            try testing.expect(id != .fx);
            try testing.expect(cli_probe.isCliProbeArgv(item.argv, id));
            try testing.expect(item.key != fx_probe.fx_probe_key);
            try testing.expect(model.cli_probe_started[@intFromEnum(id)]);
            cli_n += 1;
        }
    }
    try testing.expect(saw_fx);
    try testing.expectEqual(cli_probe.nonFxCount(), cli_n);
    try testing.expect(!model.cli_probe_started[0]);

    const after_boot = fx.pendingSpawnCount();
    startProbes(&model, &fx);
    try testing.expectEqual(after_boot, fx.pendingSpawnCount());

    var fx_n: usize = 0;
    i = 0;
    while (fx.pendingSpawnAt(i)) |item| : (i += 1) {
        if (item.key == fx_probe.fx_probe_key) fx_n += 1;
    }
    try testing.expectEqual(@as(usize, 1), fx_n);
}

test "rows empty off the Providers page" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var model = Model{};
    const off = rows(&model, arena);
    try std.testing.expectEqual(@as(usize, 0), off.len);
    model.settings_page = .providers;
    const on = rows(&model, arena);
    try std.testing.expectEqual(catalogLen(), on.len);
    try std.testing.expectEqualStrings("fx", on[0].name);
    try std.testing.expect(on[0].first_party);
    try std.testing.expectEqualStrings("claude", on[1].name);
    try std.testing.expectEqualStrings(missing_status, on[1].status);
    try std.testing.expectEqualStrings("claude", on[1].binary);
    try std.testing.expect(on[0].enabled);
    try std.testing.expect(on[1].enabled);
    try std.testing.expectEqualStrings("Disable fx", on[0].enable_label);
    try std.testing.expect(!std.mem.eql(u8, on[0].enable_label, disable_label));
    try std.testing.expectEqualStrings("Disable claude", on[1].enable_label);
}

test "copy command strings are the verified keejkrej/fx install / login commands" {
    try std.testing.expectEqualStrings(
        "curl -fsSL https://github.com/keejkrej/fx/releases/latest/download/install | bash",
        fx_install_command,
    );
    try std.testing.expectEqualStrings(
        "irm https://github.com/keejkrej/fx/releases/latest/download/install.ps1 | iex",
        fx_install_command_windows,
    );
    try std.testing.expectEqualStrings("fx login", fx_login_command);
    try std.testing.expectEqualStrings("Copy install command", copy_install_label);
    try std.testing.expectEqualStrings("Copy login command", copy_login_label);
    try std.testing.expectEqualStrings("Copy serve command", copy_serve_label);
    try std.testing.expectEqualStrings("Copy web command", copy_web_label);
}

test "fxInstallCommandForOs picks Unix curl|bash vs Windows irm|iex" {
    try std.testing.expectEqualStrings(fx_install_command, fxInstallCommandForOs(.linux));
    try std.testing.expectEqualStrings(fx_install_command, fxInstallCommandForOs(.macos));
    try std.testing.expectEqualStrings(fx_install_command_windows, fxInstallCommandForOs(.windows));
    try std.testing.expectEqualStrings(fxInstallCommandForOs(builtin.os.tag), fxInstallCommand());
    switch (builtin.os.tag) {
        .windows => try std.testing.expectEqualStrings(fx_install_command_windows, fxInstallCommand()),
        else => try std.testing.expectEqualStrings(fx_install_command, fxInstallCommand()),
    }
}

test "install/login copy predicates: fx missing, fx available, other missing" {
    var model = Model{};
    try std.testing.expect(!canCopyFxInstall(&model));
    try std.testing.expect(!canCopyFxLogin(&model));
    try std.testing.expect(!canCopyOpencode2Serve(&model));
    try std.testing.expect(!canCopyDeepseekWeb(&model));
    try std.testing.expect(!showsOtherInstallHint(&model));

    selectProvider(&model, rowId(.fx));
    try std.testing.expect(canCopyFxInstall(&model));
    try std.testing.expect(!canCopyFxLogin(&model));
    try std.testing.expect(!canCopyOpencode2Serve(&model));
    try std.testing.expect(!canCopyDeepseekWeb(&model));
    try std.testing.expect(!showsOtherInstallHint(&model));

    model.fx_available = true;
    try std.testing.expect(!canCopyFxInstall(&model));
    try std.testing.expect(canCopyFxLogin(&model));
    try std.testing.expect(!canCopyOpencode2Serve(&model));
    try std.testing.expect(!canCopyDeepseekWeb(&model));
    try std.testing.expect(!showsOtherInstallHint(&model));

    selectProvider(&model, rowId(.claude));
    try std.testing.expect(!canCopyFxInstall(&model));
    try std.testing.expect(!canCopyFxLogin(&model));
    try std.testing.expect(!canCopyOpencode2Serve(&model));
    try std.testing.expect(!canCopyDeepseekWeb(&model));
    try std.testing.expect(showsOtherInstallHint(&model));

    model.cli_available[@intFromEnum(protocol.ProviderId.claude)] = true;
    try std.testing.expect(!showsOtherInstallHint(&model));

    const others = [_]protocol.ProviderId{ .codex, .amp, .grok, .opencode, .cursor, .pi, .kimi, .ohmypi, .opencode2, .deepseek };
    for (others) |id| {
        selectProvider(&model, rowId(id));
        try std.testing.expect(!canCopyFxInstall(&model));
        try std.testing.expect(!canCopyFxLogin(&model));
        try std.testing.expect(showsOtherInstallHint(&model));
        model.cli_available[@intFromEnum(id)] = true;
        try std.testing.expect(!showsOtherInstallHint(&model));
    }

    selectProvider(&model, 99);
    try std.testing.expect(!canCopyFxInstall(&model));
    try std.testing.expect(!canCopyFxLogin(&model));
    try std.testing.expect(!showsOtherInstallHint(&model));
}

test "copyFxInstall / copyFxLogin write verified commands; wrong state is a no-op" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    copyFxInstall(&model, &fx);
    copyFxLogin(&model, &fx);
    try testing.expectEqual(@as(usize, 0), fx.pendingClipboardCount());
    try testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());

    selectProvider(&model, rowId(.fx));
    copyFxLogin(&model, &fx);
    try testing.expectEqual(@as(usize, 0), fx.pendingClipboardCount());
    copyFxInstall(&model, &fx);
    try testing.expectEqual(@as(usize, 1), fx.pendingClipboardCount());
    try testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
    const install = fx.pendingClipboardAt(0).?;
    try testing.expectEqual(sidecar_keys.copy_turn_key, install.key);
    try testing.expectEqual(@import("native_sdk").EffectClipboardOp.write, install.op);
    try testing.expectEqualStrings(fxInstallCommand(), install.text);
    switch (builtin.os.tag) {
        .windows => try testing.expectEqualStrings(fx_install_command_windows, install.text),
        else => try testing.expectEqualStrings(fx_install_command, install.text),
    }

    model.fx_available = true;
    copyFxInstall(&model, &fx);
    try testing.expectEqual(@as(usize, 1), fx.pendingClipboardCount());
    try testing.expectEqualStrings(fxInstallCommand(), fx.pendingClipboardAt(0).?.text);

    var login_fx = Effects.init(testing.allocator);
    defer login_fx.deinit();
    login_fx.executor = .fake;
    copyFxLogin(&model, &login_fx);
    try testing.expectEqual(@as(usize, 1), login_fx.pendingClipboardCount());
    const login = login_fx.pendingClipboardAt(0).?;
    try testing.expectEqual(sidecar_keys.copy_turn_key, login.key);
    try testing.expectEqual(@import("native_sdk").EffectClipboardOp.write, login.op);
    try testing.expectEqualStrings(fx_login_command, login.text);
    try testing.expectEqualStrings("fx login", login.text);
    try testing.expectEqual(@as(usize, 0), login_fx.pendingSpawnCount());

    selectProvider(&model, rowId(.claude));
    var other_fx = Effects.init(testing.allocator);
    defer other_fx.deinit();
    other_fx.executor = .fake;
    copyFxInstall(&model, &other_fx);
    copyFxLogin(&model, &other_fx);
    try testing.expectEqual(@as(usize, 0), other_fx.pendingClipboardCount());
    try testing.expectEqual(@as(usize, 0), other_fx.pendingSpawnCount());
}

test "opencode2ServeCommand is binaryFor plus serve; override binary; unavailable copy is a no-op" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    var buf: [opencode2_serve_command_max]u8 = undefined;
    try testing.expectEqualStrings("opencode2", binaryFor(&model, .opencode2));
    try testing.expectEqualStrings("opencode2 serve", opencode2ServeCommand(&model, &buf));
    try testing.expectEqualStrings("Copy serve command", copy_serve_label);
    try testing.expect(!canCopyOpencode2Serve(&model));
    copyOpencode2Serve(&model, &fx);
    try testing.expectEqual(@as(usize, 0), fx.pendingClipboardCount());
    try testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());

    selectProvider(&model, rowId(.opencode2));
    copyOpencode2Serve(&model, &fx);
    try testing.expectEqual(@as(usize, 0), fx.pendingClipboardCount());

    model.cli_available[@intFromEnum(protocol.ProviderId.opencode2)] = true;
    try testing.expect(canCopyOpencode2Serve(&model));
    copyOpencode2Serve(&model, &fx);
    try testing.expectEqual(@as(usize, 1), fx.pendingClipboardCount());
    try testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
    const copied = fx.pendingClipboardAt(0).?;
    try testing.expectEqual(sidecar_keys.copy_turn_key, copied.key);
    try testing.expectEqual(@import("native_sdk").EffectClipboardOp.write, copied.op);
    try testing.expectEqualStrings("opencode2 serve", copied.text);

    model.setProviderBinaryOverride(.opencode2, "/opt/custom-opencode2");
    try testing.expectEqualStrings("/opt/custom-opencode2", binaryFor(&model, .opencode2));
    try testing.expectEqualStrings("/opt/custom-opencode2 serve", opencode2ServeCommand(&model, &buf));
    var override_fx = Effects.init(testing.allocator);
    defer override_fx.deinit();
    override_fx.executor = .fake;
    copyOpencode2Serve(&model, &override_fx);
    try testing.expectEqual(@as(usize, 1), override_fx.pendingClipboardCount());
    try testing.expectEqualStrings("/opt/custom-opencode2 serve", override_fx.pendingClipboardAt(0).?.text);
    try testing.expectEqual(@as(usize, 0), override_fx.pendingSpawnCount());

    model.cli_available[@intFromEnum(protocol.ProviderId.opencode2)] = false;
    try testing.expect(!canCopyOpencode2Serve(&model));
    var missing_fx = Effects.init(testing.allocator);
    defer missing_fx.deinit();
    missing_fx.executor = .fake;
    copyOpencode2Serve(&model, &missing_fx);
    try testing.expectEqual(@as(usize, 0), missing_fx.pendingClipboardCount());
    try testing.expectEqual(@as(usize, 0), missing_fx.pendingSpawnCount());
}

test "deepseekWebCommand is binaryFor plus web; override binary; unavailable copy is a no-op" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    var buf: [deepseek_web_command_max]u8 = undefined;
    try testing.expectEqualStrings("dsh", binaryFor(&model, .deepseek));
    try testing.expectEqualStrings("dsh web", deepseekWebCommand(&model, &buf));
    try testing.expectEqualStrings("Copy web command", copy_web_label);
    try testing.expect(!canCopyDeepseekWeb(&model));
    try testing.expect(!canCopyOpencode2Serve(&model));
    copyDeepseekWeb(&model, &fx);
    try testing.expectEqual(@as(usize, 0), fx.pendingClipboardCount());
    try testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());

    selectProvider(&model, rowId(.deepseek));
    copyDeepseekWeb(&model, &fx);
    try testing.expectEqual(@as(usize, 0), fx.pendingClipboardCount());

    model.cli_available[@intFromEnum(protocol.ProviderId.deepseek)] = true;
    try testing.expect(canCopyDeepseekWeb(&model));
    try testing.expect(!canCopyOpencode2Serve(&model));
    copyDeepseekWeb(&model, &fx);
    try testing.expectEqual(@as(usize, 1), fx.pendingClipboardCount());
    try testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
    const copied = fx.pendingClipboardAt(0).?;
    try testing.expectEqual(sidecar_keys.copy_turn_key, copied.key);
    try testing.expectEqual(@import("native_sdk").EffectClipboardOp.write, copied.op);
    try testing.expectEqualStrings("dsh web", copied.text);

    model.setProviderBinaryOverride(.deepseek, "/opt/custom-dsh");
    try testing.expectEqualStrings("/opt/custom-dsh", binaryFor(&model, .deepseek));
    try testing.expectEqualStrings("/opt/custom-dsh web", deepseekWebCommand(&model, &buf));
    var override_fx = Effects.init(testing.allocator);
    defer override_fx.deinit();
    override_fx.executor = .fake;
    copyDeepseekWeb(&model, &override_fx);
    try testing.expectEqual(@as(usize, 1), override_fx.pendingClipboardCount());
    try testing.expectEqualStrings("/opt/custom-dsh web", override_fx.pendingClipboardAt(0).?.text);
    try testing.expectEqual(@as(usize, 0), override_fx.pendingSpawnCount());

    model.cli_available[@intFromEnum(protocol.ProviderId.deepseek)] = false;
    try testing.expect(!canCopyDeepseekWeb(&model));
    var missing_fx = Effects.init(testing.allocator);
    defer missing_fx.deinit();
    missing_fx.executor = .fake;
    copyDeepseekWeb(&model, &missing_fx);
    try testing.expectEqual(@as(usize, 0), missing_fx.pendingClipboardCount());
    try testing.expectEqual(@as(usize, 0), missing_fx.pendingSpawnCount());
}

test "OpenCode 2 Available does not unlock DeepSeek Copy web; DeepSeek Available does not unlock Copy serve" {
    const testing = std.testing;
    var model = Model{};
    try testing.expect(!canCopyOpencode2Serve(&model));
    try testing.expect(!canCopyDeepseekWeb(&model));

    model.cli_available[@intFromEnum(protocol.ProviderId.opencode2)] = true;
    try testing.expect(canCopyOpencode2Serve(&model));
    try testing.expect(!canCopyDeepseekWeb(&model));

    model.cli_available[@intFromEnum(protocol.ProviderId.opencode2)] = false;
    model.cli_available[@intFromEnum(protocol.ProviderId.deepseek)] = true;
    try testing.expect(!canCopyOpencode2Serve(&model));
    try testing.expect(canCopyDeepseekWeb(&model));
}

test "providerEnabled is not-disabled AND probe-installed; chip is disable-flag-only" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var model = Model{};
    try std.testing.expect(!providerEnabled(&model, .claude));
    try std.testing.expect(!providerEnabled(&model, .grok));
    try std.testing.expect(!providerEnabled(&model, .fx));
    try std.testing.expect(rowFor(&model, .claude, arena).enabled);
    try std.testing.expectEqualStrings("Disable claude", rowFor(&model, .claude, arena).enable_label);
    try std.testing.expect(!std.mem.eql(u8, rowFor(&model, .claude, arena).enable_label, disable_label));
    try std.testing.expect(rowFor(&model, .fx, arena).enabled);

    model.cli_available[@intFromEnum(protocol.ProviderId.claude)] = true;
    try std.testing.expect(providerEnabled(&model, .claude));
    try std.testing.expect(rowFor(&model, .claude, arena).enabled);
    try std.testing.expect(!providerEnabled(&model, .grok));
    try std.testing.expect(rowFor(&model, .grok, arena).enabled);

    setProviderEnabled(&model, .claude, false);
    try std.testing.expect(!providerEnabled(&model, .claude));
    try std.testing.expect(!rowFor(&model, .claude, arena).enabled);
    try std.testing.expectEqualStrings("Enable claude", rowFor(&model, .claude, arena).enable_label);
    try std.testing.expect(!std.mem.eql(u8, rowFor(&model, .claude, arena).enable_label, enable_label));
    try std.testing.expect(!providerEnabled(&model, .grok));
    try std.testing.expect(rowFor(&model, .grok, arena).enabled);

    setProviderEnabled(&model, .claude, true);
    try std.testing.expect(providerEnabled(&model, .claude));
    try std.testing.expect(!model.disabled_providers[@intFromEnum(protocol.ProviderId.claude)]);
    try std.testing.expect(rowFor(&model, .claude, arena).enabled);
    try std.testing.expectEqualStrings("Disable claude", rowFor(&model, .claude, arena).enable_label);

    model.cli_available[@intFromEnum(protocol.ProviderId.grok)] = true;
    try std.testing.expect(providerEnabled(&model, .grok));
    try std.testing.expect(toggleProviderEnabled(&model, rowId(.grok)));
    try std.testing.expect(!providerEnabled(&model, .grok));
    try std.testing.expect(!rowFor(&model, .grok, arena).enabled);
    try std.testing.expect(toggleProviderEnabled(&model, rowId(.grok)));
    try std.testing.expect(providerEnabled(&model, .grok));
    try std.testing.expect(!toggleProviderEnabled(&model, 0));
    try std.testing.expect(!toggleProviderEnabled(&model, 99));

    model.fx_available = true;
    try std.testing.expect(providerEnabled(&model, .fx));
    try std.testing.expect(rowFor(&model, .fx, arena).enabled);
    setProviderEnabled(&model, .fx, false);
    try std.testing.expect(!providerEnabled(&model, .fx));
    try std.testing.expect(!rowFor(&model, .fx, arena).enabled);
    try std.testing.expectEqualStrings("Enable fx", rowFor(&model, .fx, arena).enable_label);
}

test "statusFor / rowFor english default matches former copy; zh-CN / ja localize status enable_label first_party" {
    const testing = std.testing;
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var model = Model{};
    try testing.expectEqualStrings("Not found", statusFor(&model, .fx));
    try testing.expectEqualStrings("Not found", statusFor(&model, .claude));
    try testing.expectEqualStrings(missing_status, statusFor(&model, .fx));
    try testing.expectEqualStrings("Disable fx", rowFor(&model, .fx, arena).enable_label);
    try testing.expect(!std.mem.eql(u8, rowFor(&model, .fx, arena).enable_label, disable_label));
    try testing.expectEqualStrings("First-party default", rowFor(&model, .fx, arena).first_party_label);
    try testing.expectEqualStrings(first_party_label, rowFor(&model, .fx, arena).first_party_label);
    try testing.expectEqualStrings("", rowFor(&model, .claude, arena).first_party_label);
    try testing.expectEqualStrings("fx", rowFor(&model, .fx, arena).name);
    try testing.expectEqualStrings("claude", rowFor(&model, .claude, arena).name);

    model.fx_available = true;
    try testing.expectEqualStrings("Available", statusFor(&model, .fx));
    try testing.expectEqualStrings(available_status, statusFor(&model, .fx));
    setProviderEnabled(&model, .fx, false);
    try testing.expectEqualStrings("Enable fx", rowFor(&model, .fx, arena).enable_label);
    try testing.expect(!std.mem.eql(u8, rowFor(&model, .fx, arena).enable_label, enable_label));

    model.language_preference = .simplified_chinese;
    try testing.expectEqualStrings("可用", statusFor(&model, .fx));
    try testing.expectEqualStrings("未找到", statusFor(&model, .claude));
    try testing.expectEqualStrings("启用fx", rowFor(&model, .fx, arena).enable_label);
    try testing.expectEqualStrings("禁用claude", rowFor(&model, .claude, arena).enable_label);
    try testing.expect(!std.mem.eql(u8, rowFor(&model, .claude, arena).enable_label, i18n.skillsEnableNamedChromeFor(.simplified_chinese, "").disable_named));
    try testing.expectEqualStrings("第一方默认", rowFor(&model, .fx, arena).first_party_label);
    try testing.expectEqualStrings("fx", rowFor(&model, .fx, arena).name);
    try testing.expectEqualStrings("claude", rowFor(&model, .claude, arena).name);
    selectProvider(&model, rowId(.fx));
    const zh_detail = detailText(&model, testing.allocator);
    defer if (zh_detail.len > 0) testing.allocator.free(zh_detail);
    try testing.expect(std.mem.indexOf(u8, zh_detail, "第一方默认") != null);
    try testing.expect(std.mem.indexOf(u8, zh_detail, "fx") != null);
    try testing.expect(std.mem.indexOf(u8, zh_detail, i18n.providersDetailChromeFor(.simplified_chinese, "").fx_transport_note) != null);
    try testing.expect(std.mem.indexOf(u8, zh_detail, fx_transport_note) == null);

    model.language_preference = .japanese;
    setProviderEnabled(&model, .fx, true);
    try testing.expectEqualStrings("利用可能", statusFor(&model, .fx));
    try testing.expectEqualStrings("見つかりません", statusFor(&model, .claude));
    try testing.expectEqualStrings("fx を無効にする", rowFor(&model, .fx, arena).enable_label);
    try testing.expectEqualStrings("claude を無効にする", rowFor(&model, .claude, arena).enable_label);
    try testing.expectEqualStrings("ファーストパーティ既定", rowFor(&model, .fx, arena).first_party_label);
    setProviderEnabled(&model, .claude, false);
    try testing.expectEqualStrings("claude を有効にする", rowFor(&model, .claude, arena).enable_label);
    const ja_detail = detailText(&model, testing.allocator);
    defer if (ja_detail.len > 0) testing.allocator.free(ja_detail);
    try testing.expect(std.mem.indexOf(u8, ja_detail, "ファーストパーティ既定") != null);
    try testing.expect(std.mem.indexOf(u8, ja_detail, i18n.providersDetailChromeFor(.japanese, "").fx_transport_note) != null);
    try testing.expect(std.mem.indexOf(u8, ja_detail, fx_transport_note) == null);

    selectProvider(&model, rowId(.claude));
    const ja_claude = detailText(&model, testing.allocator);
    defer if (ja_claude.len > 0) testing.allocator.free(ja_claude);
    try testing.expect(std.mem.indexOf(u8, ja_claude, i18n.providersDetailChromeFor(.japanese, "").claude_transport_note) != null);
    try testing.expect(std.mem.indexOf(u8, ja_claude, claude_transport_note) == null);

    model.language_preference = .english;
    model.setSystemLocaleId("ja_JP.UTF-8");
    try testing.expectEqualStrings("Available", statusFor(&model, .fx));
    try testing.expectEqualStrings("Not found", statusFor(&model, .claude));
    try testing.expectEqualStrings("Disable fx", rowFor(&model, .fx, arena).enable_label);
    try testing.expectEqualStrings("First-party default", rowFor(&model, .fx, arena).first_party_label);

    model.language_preference = .system;
    model.setSystemLocaleId("zh_CN.UTF-8");
    try testing.expectEqualStrings("可用", statusFor(&model, .fx));
    try testing.expectEqualStrings("未找到", statusFor(&model, .claude));
    try testing.expectEqualStrings("禁用fx", rowFor(&model, .fx, arena).enable_label);
    try testing.expectEqualStrings("第一方默认", rowFor(&model, .fx, arena).first_party_label);

    model.setSystemLocaleId("ja_JP.UTF-8");
    try testing.expectEqualStrings("利用可能", statusFor(&model, .fx));
    try testing.expectEqualStrings("見つかりません", statusFor(&model, .claude));
    try testing.expectEqualStrings("fx を無効にする", rowFor(&model, .fx, arena).enable_label);
    try testing.expectEqualStrings("ファーストパーティ既定", rowFor(&model, .fx, arena).first_party_label);
}

test "enableLabelFor formats Enable %{name} / Disable %{name}; empty name still paints" {
    const testing = std.testing;
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    try testing.expectEqualStrings("Enable %{name}", enable_named_template);
    try testing.expectEqualStrings("Disable %{name}", disable_named_template);
    try testing.expect(!std.mem.eql(u8, enable_named_template, enable_label));
    try testing.expect(!std.mem.eql(u8, disable_named_template, disable_label));
    try testing.expectEqualStrings(enable_named_template, i18n.skillsEnableNamedChromeFor(.english, "").enable_named);
    try testing.expect(!std.mem.eql(
        u8,
        i18n.providersEnableNamedChromeFor(.simplified_chinese, "").disable_named,
        i18n.skillsEnableNamedChromeFor(.simplified_chinese, "").disable_named,
    ));

    var model = Model{};
    try testing.expectEqualStrings("Disable fx", enableLabelFor(&model, .fx, arena));
    try testing.expectEqualStrings("Disable claude", enableLabelFor(&model, .claude, arena));
    {
        var buf: [i18n.providers_enable_named_max]u8 = undefined;
        try testing.expectEqualStrings(
            i18n.formatProvidersEnableNamed(i18n.providersEnableNamedChromeFor(.english, ""), true, "fx", &buf),
            enableLabelFor(&model, .fx, arena),
        );
        try testing.expectEqualStrings("Enable ", i18n.formatProvidersEnableNamed(
            i18n.providersEnableNamedChromeFor(.english, ""),
            false,
            "",
            &buf,
        ));
    }
    try testing.expect(!std.mem.eql(u8, enableLabelFor(&model, .fx, arena), disable_label));
    try testing.expect(!std.mem.eql(u8, enableLabelFor(&model, .fx, arena), i18n.providersChromeFor(.english, "").disable));

    setProviderEnabled(&model, .claude, false);
    try testing.expectEqualStrings("Enable claude", enableLabelFor(&model, .claude, arena));
    try testing.expect(!std.mem.eql(u8, enableLabelFor(&model, .claude, arena), enable_label));
    try testing.expect(!std.mem.eql(u8, enableLabelFor(&model, .claude, arena), i18n.providersChromeFor(.english, "").enable));

    model.language_preference = .simplified_chinese;
    try testing.expectEqualStrings("启用claude", enableLabelFor(&model, .claude, arena));
    setProviderEnabled(&model, .fx, true);
    try testing.expectEqualStrings("禁用fx", enableLabelFor(&model, .fx, arena));
    {
        var skills_buf: [i18n.skills_enable_named_max]u8 = undefined;
        try testing.expect(!std.mem.eql(u8, enableLabelFor(&model, .fx, arena), i18n.formatSkillsEnableNamed(
            i18n.skillsEnableNamedChromeFor(.simplified_chinese, ""),
            true,
            "fx",
            &skills_buf,
        )));
        try testing.expectEqualStrings("停用fx", i18n.formatSkillsEnableNamed(
            i18n.skillsEnableNamedChromeFor(.simplified_chinese, ""),
            true,
            "fx",
            &skills_buf,
        ));
    }

    model.language_preference = .japanese;
    try testing.expectEqualStrings("fx を無効にする", enableLabelFor(&model, .fx, arena));
    try testing.expectEqualStrings("claude を有効にする", enableLabelFor(&model, .claude, arena));

    model.language_preference = .english;
    model.setSystemLocaleId("ja_JP.UTF-8");
    try testing.expectEqualStrings("Enable claude", enableLabelFor(&model, .claude, arena));
    model.language_preference = .system;
    model.setSystemLocaleId("zh_CN.UTF-8");
    try testing.expectEqualStrings("启用claude", enableLabelFor(&model, .claude, arena));
    model.setSystemLocaleId("ja_JP.UTF-8");
    try testing.expectEqualStrings("claude を有効にする", enableLabelFor(&model, .claude, arena));
}

test "detailText english default matches former Binary/Path prefixes; zh-CN / ja localize prefixes; english ignores LANG" {
    const testing = std.testing;
    var model = Model{};
    model.fx_available = true;
    model.setFxPath("/home/probe/.local/bin/fx");
    selectProvider(&model, rowId(.fx));
    const en_fx = detailText(&model, testing.allocator);
    defer if (en_fx.len > 0) testing.allocator.free(en_fx);
    try testing.expect(std.mem.indexOf(u8, en_fx, "Binary: fx") != null);
    try testing.expect(std.mem.indexOf(u8, en_fx, "Path: /home/probe/.local/bin/fx") != null);
    try testing.expect(std.mem.indexOf(u8, en_fx, first_party_label) != null);
    try testing.expect(std.mem.indexOf(u8, en_fx, fx_transport_note) != null);

    selectProvider(&model, rowId(.claude));
    const en_claude = detailText(&model, testing.allocator);
    defer if (en_claude.len > 0) testing.allocator.free(en_claude);
    try testing.expect(std.mem.indexOf(u8, en_claude, "Binary: claude") != null);
    try testing.expect(std.mem.indexOf(u8, en_claude, "Path:") == null);
    try testing.expect(std.mem.indexOf(u8, en_claude, "claude") != null);

    model.fx_available = false;
    selectProvider(&model, rowId(.fx));
    const en_fx_missing = detailText(&model, testing.allocator);
    defer if (en_fx_missing.len > 0) testing.allocator.free(en_fx_missing);
    try testing.expect(std.mem.indexOf(u8, en_fx_missing, "Binary: fx") != null);
    try testing.expect(std.mem.indexOf(u8, en_fx_missing, "Path:") == null);
    try testing.expect(std.mem.indexOf(u8, en_fx_missing, missing_status) != null);

    model.fx_available = true;
    model.language_preference = .simplified_chinese;
    const zh_fx = detailText(&model, testing.allocator);
    defer if (zh_fx.len > 0) testing.allocator.free(zh_fx);
    try testing.expect(std.mem.indexOf(u8, zh_fx, "二进制: fx") != null);
    try testing.expect(std.mem.indexOf(u8, zh_fx, "路径: /home/probe/.local/bin/fx") != null);
    try testing.expect(std.mem.indexOf(u8, zh_fx, "/home/probe/.local/bin/fx") != null);
    try testing.expect(std.mem.indexOf(u8, zh_fx, "Binary:") == null);
    try testing.expect(std.mem.indexOf(u8, zh_fx, "Path:") == null);
    try testing.expect(std.mem.indexOf(u8, zh_fx, "fx") != null);
    try testing.expect(std.mem.indexOf(u8, zh_fx, "第一方默认") != null);

    selectProvider(&model, rowId(.claude));
    const zh_claude = detailText(&model, testing.allocator);
    defer if (zh_claude.len > 0) testing.allocator.free(zh_claude);
    try testing.expect(std.mem.indexOf(u8, zh_claude, "二进制: claude") != null);
    try testing.expect(std.mem.indexOf(u8, zh_claude, "claude") != null);
    try testing.expect(std.mem.indexOf(u8, zh_claude, "Binary:") == null);
    try testing.expect(std.mem.indexOf(u8, zh_claude, "Path:") == null);

    model.language_preference = .japanese;
    selectProvider(&model, rowId(.fx));
    const ja_fx = detailText(&model, testing.allocator);
    defer if (ja_fx.len > 0) testing.allocator.free(ja_fx);
    try testing.expect(std.mem.indexOf(u8, ja_fx, "バイナリ: fx") != null);
    try testing.expect(std.mem.indexOf(u8, ja_fx, "パス: /home/probe/.local/bin/fx") != null);
    try testing.expect(std.mem.indexOf(u8, ja_fx, "/home/probe/.local/bin/fx") != null);
    try testing.expect(std.mem.indexOf(u8, ja_fx, "Binary:") == null);
    try testing.expect(std.mem.indexOf(u8, ja_fx, "Path:") == null);
    try testing.expect(std.mem.indexOf(u8, ja_fx, "ファーストパーティ既定") != null);

    selectProvider(&model, rowId(.claude));
    const ja_claude = detailText(&model, testing.allocator);
    defer if (ja_claude.len > 0) testing.allocator.free(ja_claude);
    try testing.expect(std.mem.indexOf(u8, ja_claude, "バイナリ: claude") != null);
    try testing.expect(std.mem.indexOf(u8, ja_claude, "claude") != null);
    try testing.expect(std.mem.indexOf(u8, ja_claude, "Binary:") == null);
    try testing.expect(std.mem.indexOf(u8, ja_claude, "Path:") == null);

    model.language_preference = .english;
    model.setSystemLocaleId("ja_JP.UTF-8");
    selectProvider(&model, rowId(.fx));
    const en_ignores_ja = detailText(&model, testing.allocator);
    defer if (en_ignores_ja.len > 0) testing.allocator.free(en_ignores_ja);
    try testing.expect(std.mem.indexOf(u8, en_ignores_ja, "Binary: fx") != null);
    try testing.expect(std.mem.indexOf(u8, en_ignores_ja, "Path: /home/probe/.local/bin/fx") != null);
    try testing.expect(std.mem.indexOf(u8, en_ignores_ja, "バイナリ:") == null);
    try testing.expect(std.mem.indexOf(u8, en_ignores_ja, "パス:") == null);

    model.language_preference = .system;
    model.setSystemLocaleId("zh_CN.UTF-8");
    const sys_zh = detailText(&model, testing.allocator);
    defer if (sys_zh.len > 0) testing.allocator.free(sys_zh);
    try testing.expect(std.mem.indexOf(u8, sys_zh, "二进制: fx") != null);
    try testing.expect(std.mem.indexOf(u8, sys_zh, "路径: /home/probe/.local/bin/fx") != null);
    try testing.expect(std.mem.indexOf(u8, sys_zh, "Binary:") == null);
    try testing.expect(std.mem.indexOf(u8, sys_zh, "Path:") == null);

    model.setSystemLocaleId("ja_JP.UTF-8");
    const sys_ja = detailText(&model, testing.allocator);
    defer if (sys_ja.len > 0) testing.allocator.free(sys_ja);
    try testing.expect(std.mem.indexOf(u8, sys_ja, "バイナリ: fx") != null);
    try testing.expect(std.mem.indexOf(u8, sys_ja, "パス: /home/probe/.local/bin/fx") != null);
    try testing.expect(std.mem.indexOf(u8, sys_ja, "Binary:") == null);
    try testing.expect(std.mem.indexOf(u8, sys_ja, "Path:") == null);
}

test "toggleExpanded is one-at-a-time; switching applies pending override" {
    const testing = std.testing;
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.settings_page = .providers;
    try testing.expect(!toggleExpanded(&model, &fx, 0));
    try testing.expect(!toggleExpanded(&model, &fx, 99));
    try testing.expectEqual(@as(u32, 0), model.provider_expanded_id);

    try testing.expect(toggleExpanded(&model, &fx, rowId(.claude)));
    try testing.expectEqual(rowId(.claude), model.provider_expanded_id);
    try testing.expect(rowFor(&model, .claude, arena).expanded);
    try testing.expectEqualStrings("Show fx settings", rowFor(&model, .fx, arena).expand_label);
    try testing.expectEqualStrings("Hide claude settings", rowFor(&model, .claude, arena).expand_label);
    try testing.expect(!rowFor(&model, .fx, arena).expanded);
    try testing.expectEqualStrings("", model.provider_override_buffer.text());

    model.provider_override_buffer.set(" /opt/claude ");
    try testing.expect(toggleExpanded(&model, &fx, rowId(.fx)));
    try testing.expectEqual(rowId(.fx), model.provider_expanded_id);
    try testing.expectEqualStrings("/opt/claude", model.providerBinaryOverride(.claude));
    try testing.expectEqualStrings("", model.providerBinaryOverride(.fx));
    try testing.expect(rowFor(&model, .fx, arena).expanded);
    try testing.expect(!rowFor(&model, .claude, arena).expanded);

    try testing.expect(toggleExpanded(&model, &fx, rowId(.fx)));
    try testing.expectEqual(@as(u32, 0), model.provider_expanded_id);
    try testing.expect(!rowFor(&model, .fx, arena).expanded);
}

test "applyPathOverride empty clears; captions invalid vs using; binaryFor prefers override" {
    const testing = std.testing;
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    try testing.expect(!applyPathOverride(&model, &fx));
    try testing.expect(!clearPathOverride(&model, &fx));

    try testing.expect(toggleExpanded(&model, &fx, rowId(.claude)));
    model.provider_override_buffer.set("/opt/claude");
    try testing.expect(applyPathOverride(&model, &fx));
    try testing.expectEqualStrings("/opt/claude", model.providerBinaryOverride(.claude));
    try testing.expectEqualStrings("/opt/claude", binaryFor(&model, .claude));
    try testing.expect(rowFor(&model, .claude, arena).has_override);
    try testing.expectEqualStrings(
        "Nothing runnable at this path. Clear it to detect from PATH",
        rowFor(&model, .claude, arena).override_caption,
    );
    try testing.expect(!isAvailable(&model, .claude));

    model.cli_available[@intFromEnum(protocol.ProviderId.claude)] = true;
    try testing.expectEqualStrings(
        "Using /opt/claude instead of PATH detection",
        rowFor(&model, .claude, arena).override_caption,
    );

    model.provider_override_buffer.set("");
    try testing.expect(applyPathOverride(&model, &fx));
    try testing.expectEqualStrings("", model.providerBinaryOverride(.claude));
    try testing.expectEqualStrings("claude", binaryFor(&model, .claude));
    try testing.expect(!rowFor(&model, .claude, arena).has_override);

    model.setProviderBinaryOverride(.claude, "/opt/claude");
    model.provider_override_buffer.set("/opt/claude");
    try testing.expect(clearPathOverride(&model, &fx));
    try testing.expectEqualStrings("", model.providerBinaryOverride(.claude));
    try testing.expectEqualStrings("", model.provider_override_buffer.text());
}

test "applyAttachUrl empty clears; OpenCode 2 row only; switching applies pending draft" {
    const testing = std.testing;
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    try testing.expect(!applyAttachUrl(&model));
    try testing.expect(!clearAttachUrl(&model));
    try testing.expect(!rowFor(&model, .fx, arena).show_opencode_attach);
    try testing.expect(!rowFor(&model, .claude, arena).show_opencode_attach);
    try testing.expect(rowFor(&model, .opencode2, arena).show_opencode_attach);
    try testing.expect(!rowFor(&model, .opencode2, arena).has_opencode_attach);
    try testing.expect(!rowFor(&model, .fx, arena).show_deepseek_web);
    try testing.expect(!rowFor(&model, .claude, arena).show_deepseek_web);
    try testing.expect(!rowFor(&model, .opencode2, arena).show_deepseek_web);
    try testing.expect(rowFor(&model, .deepseek, arena).show_deepseek_web);

    try testing.expect(toggleExpanded(&model, &fx, rowId(.opencode2)));
    model.opencode2_attach_buffer.set("  http://localhost:4096  ");
    try testing.expect(applyAttachUrl(&model));
    try testing.expectEqualStrings("http://localhost:4096", model.opencode2AttachUrl());
    try testing.expectEqualStrings("http://localhost:4096", model.opencode2_attach_buffer.text());
    try testing.expect(rowFor(&model, .opencode2, arena).has_opencode_attach);

    try testing.expect(toggleExpanded(&model, &fx, rowId(.fx)));
    try testing.expectEqualStrings("http://localhost:4096", model.opencode2AttachUrl());
    try testing.expectEqualStrings("", model.opencode2_attach_buffer.text());
    try testing.expect(!applyAttachUrl(&model));

    try testing.expect(toggleExpanded(&model, &fx, rowId(.opencode2)));
    try testing.expectEqualStrings("http://localhost:4096", model.opencode2_attach_buffer.text());
    model.opencode2_attach_buffer.set("");
    try testing.expect(applyAttachUrl(&model));
    try testing.expectEqualStrings("", model.opencode2AttachUrl());
    try testing.expect(!rowFor(&model, .opencode2, arena).has_opencode_attach);

    model.setOpencode2AttachUrl("http://127.0.0.1:4096");
    model.opencode2_attach_buffer.set("http://127.0.0.1:4096");
    try testing.expect(clearAttachUrl(&model));
    try testing.expectEqualStrings("", model.opencode2AttachUrl());
    try testing.expectEqualStrings("", model.opencode2_attach_buffer.text());
}

test "no override captions: detected_at / detected_as / searches_path; zh and ja expand labels" {
    const testing = std.testing;
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var model = Model{};
    try testing.expectEqualStrings(
        "Faku did not detect claude in PATH",
        rowFor(&model, .claude, arena).override_caption,
    );
    try testing.expectEqualStrings(
        "Faku did not detect fx in PATH",
        rowFor(&model, .fx, arena).override_caption,
    );

    model.fx_available = true;
    model.setFxPath("/home/probe/.fx/bin/fx");
    try testing.expectEqualStrings(
        "Detected at /home/probe/.fx/bin/fx",
        rowFor(&model, .fx, arena).override_caption,
    );
    model.cli_available[@intFromEnum(protocol.ProviderId.claude)] = true;
    try testing.expectEqualStrings(
        "Detected as claude",
        rowFor(&model, .claude, arena).override_caption,
    );

    model.language_preference = .simplified_chinese;
    try testing.expectEqualStrings("显示 fx 设置", rowFor(&model, .fx, arena).expand_label);
    try testing.expectEqualStrings("已在 /home/probe/.fx/bin/fx 检测到", rowFor(&model, .fx, arena).override_caption);
    try testing.expectEqualStrings("已检测到 claude", rowFor(&model, .claude, arena).override_caption);
    try testing.expect(std.mem.indexOf(u8, rowFor(&model, .fx, arena).binary_path_description, "Faku") != null);
    try testing.expect(std.mem.indexOf(u8, rowFor(&model, .fx, arena).binary_path_description, "Waku") == null);

    model.language_preference = .japanese;
    try testing.expectEqualStrings("fx の設定を表示", rowFor(&model, .fx, arena).expand_label);
    try testing.expectEqualStrings("/home/probe/.fx/bin/fx で検出されました", rowFor(&model, .fx, arena).override_caption);
    try testing.expectEqualStrings("claude として検出されました", rowFor(&model, .claude, arena).override_caption);

    model.language_preference = .english;
    model.setSystemLocaleId("ja_JP.UTF-8");
    try testing.expectEqualStrings("Show fx settings", rowFor(&model, .fx, arena).expand_label);
    model.language_preference = .system;
    model.setSystemLocaleId("zh_CN.UTF-8");
    try testing.expectEqualStrings("显示 fx 设置", rowFor(&model, .fx, arena).expand_label);
}

test "refresh / apply override probe argv uses override path" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setProviderBinaryOverride(.claude, "/opt/claude");
    model.setProviderBinaryOverride(.fx, "/opt/fx");
    refresh(&model, &fx);

    var saw_fx_override = false;
    var saw_claude_override = false;
    var i: usize = 0;
    while (fx.pendingSpawnAt(i)) |item| : (i += 1) {
        if (item.key == fx_probe.fx_probe_key) {
            try testing.expect(fx_probe.isFxProbeArgv(item.argv));
            try testing.expectEqualStrings("/opt/fx", item.argv[0]);
            saw_fx_override = true;
            continue;
        }
        if (cli_probe.fromProbeKey(item.key)) |id| {
            if (id == .claude) {
                try testing.expect(cli_probe.isCliProbeArgvWith(item.argv, .claude, "/opt/claude"));
                try testing.expectEqualStrings("/opt/claude", item.argv[0]);
                saw_claude_override = true;
            } else {
                try testing.expect(cli_probe.isCliProbeArgv(item.argv, id));
            }
        }
    }
    try testing.expect(saw_fx_override);
    try testing.expect(saw_claude_override);
    try testing.expectEqualStrings("/opt/fx", binaryFor(&model, .fx));
    try testing.expectEqualStrings("/opt/claude", binaryFor(&model, .claude));
}

test "rowFor paints v{version} only when Available and parse succeeded" {
    const testing = std.testing;
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    try testing.expect(!rowFor(&model, .claude, arena).has_version);
    try testing.expectEqualStrings("", rowFor(&model, .claude, arena).version);
    try testing.expect(!rowFor(&model, .fx, arena).has_version);

    cli_probe.handleCliProbeExit(&model, &fx, .{
        .key = cli_probe.probeKey(.claude),
        .reason = .exited,
        .code = 0,
    });
    try testing.expectEqualStrings(available_status, statusFor(&model, .claude));
    try testing.expect(!rowFor(&model, .claude, arena).has_version);

    const version_spawn = findPendingVersion(&fx, .claude) orelse return error.MissingClaudeVersion;
    try testing.expect(cli_version.isCliVersionArgv(version_spawn.argv, "claude"));
    try testing.expectEqual(cli_version.versionKey(.claude), version_spawn.key);
    try testing.expect(version_spawn.key != cli_probe.probeKey(.claude));

    cli_version.handleCliVersionExit(&model, .{
        .key = cli_version.versionKey(.claude),
        .reason = .exited,
        .code = 0,
        .output = "2.1.24 (Claude Code)\n",
    });
    try testing.expect(rowFor(&model, .claude, arena).has_version);
    try testing.expectEqualStrings("v2.1.24", rowFor(&model, .claude, arena).version);
    try testing.expect(!std.mem.eql(u8, cli_version.providerVersion(&model, .claude), rowFor(&model, .claude, arena).version));

    cli_probe.handleCliProbeExit(&model, &fx, .{
        .key = cli_probe.probeKey(.claude),
        .reason = .exited,
        .code = 127,
    });
    try testing.expectEqualStrings(missing_status, statusFor(&model, .claude));
    try testing.expect(!rowFor(&model, .claude, arena).has_version);
    try testing.expectEqualStrings("", rowFor(&model, .claude, arena).version);
    try testing.expectEqualStrings("", cli_version.providerVersion(&model, .claude));
}

test "Refresh clears versions and restarts --version only after Available help" {
    const testing = std.testing;
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setFxPath("/tmp/faku-fx");
    model.setProviderBinaryOverride(.fx, "/tmp/faku-fx");
    model.fx_available = true;
    cli_version.handleCliVersionExit(&model, .{
        .key = cli_version.versionKey(.fx),
        .reason = .exited,
        .code = 0,
        .output = "fx 0.1.0\n",
    });
    cli_version.handleCliVersionExit(&model, .{
        .key = cli_version.versionKey(.claude),
        .reason = .exited,
        .code = 0,
        .output = "2.1.24 (Claude Code)\n",
    });
    model.cli_available[@intFromEnum(protocol.ProviderId.claude)] = true;
    try testing.expect(rowFor(&model, .fx, arena).has_version);
    try testing.expectEqualStrings("v0.1.0", rowFor(&model, .fx, arena).version);
    try testing.expect(rowFor(&model, .claude, arena).has_version);

    refresh(&model, &fx);
    try testing.expect(!rowFor(&model, .fx, arena).has_version);
    try testing.expect(!rowFor(&model, .claude, arena).has_version);
    try testing.expectEqualStrings("", cli_version.providerVersion(&model, .fx));
    try testing.expectEqualStrings("", cli_version.providerVersion(&model, .claude));
    try testing.expect(findPendingVersion(&fx, .fx) == null);
    try testing.expect(findPendingVersion(&fx, .claude) == null);

    fx_probe.handleFxProbeExit(&model, &fx, .{
        .key = fx_probe.fx_probe_key,
        .reason = .exited,
        .code = 0,
    });
    const fx_version = findPendingVersion(&fx, .fx) orelse return error.MissingFxVersionAfterHelp;
    try testing.expect(cli_version.isCliVersionArgv(fx_version.argv, "/tmp/faku-fx"));

    cli_probe.handleCliProbeExit(&model, &fx, .{
        .key = cli_probe.probeKey(.claude),
        .reason = .exited,
        .code = 0,
    });
    const claude_version = findPendingVersion(&fx, .claude) orelse return error.MissingClaudeVersionAfterHelp;
    try testing.expect(cli_version.isCliVersionArgv(claude_version.argv, "claude"));
}

test "apply / reset override cancel version probe and clear stored token" {
    const testing = std.testing;
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.provider_expanded_id = rowId(.claude);
    model.cli_available[@intFromEnum(protocol.ProviderId.claude)] = true;
    cli_version.handleCliVersionExit(&model, .{
        .key = cli_version.versionKey(.claude),
        .reason = .exited,
        .code = 0,
        .output = "2.1.24 (Claude Code)\n",
    });
    try testing.expect(rowFor(&model, .claude, arena).has_version);

    model.provider_override_buffer.set("/opt/claude");
    try testing.expect(applyPathOverride(&model, &fx));
    try testing.expect(!rowFor(&model, .claude, arena).has_version);
    try testing.expectEqualStrings("", cli_version.providerVersion(&model, .claude));
    try testing.expect(findPendingVersion(&fx, .claude) == null);

    cli_probe.handleCliProbeExit(&model, &fx, .{
        .key = cli_probe.probeKey(.claude),
        .reason = .exited,
        .code = 0,
    });
    const after_apply = findPendingVersion(&fx, .claude) orelse return error.MissingClaudeVersionAfterApply;
    try testing.expect(cli_version.isCliVersionArgv(after_apply.argv, "/opt/claude"));

    cli_version.handleCliVersionExit(&model, .{
        .key = cli_version.versionKey(.claude),
        .reason = .exited,
        .code = 0,
        .output = "2.1.24 (Claude Code)\n",
    });
    try testing.expect(rowFor(&model, .claude, arena).has_version);

    try testing.expect(clearPathOverride(&model, &fx));
    try testing.expect(!rowFor(&model, .claude, arena).has_version);
    try testing.expectEqualStrings("", cli_version.providerVersion(&model, .claude));
    try testing.expect(findPendingVersion(&fx, .claude) == null);
}

test "fallbackModelCount matches Waku fallback_models lengths" {
    const testing = std.testing;
    try testing.expectEqual(@as(usize, 4), fallbackModelCount(.amp));
    try testing.expectEqual(@as(usize, 5), fallbackModelCount(.codex));
    try testing.expectEqual(@as(usize, 9), fallbackModelCount(.claude));
    try testing.expectEqual(@as(usize, 1), fallbackModelCount(.cursor));
    try testing.expectEqual(@as(usize, 0), fallbackModelCount(.fx));
    try testing.expectEqual(@as(usize, 0), fallbackModelCount(.pi));
    try testing.expectEqual(@as(usize, 0), fallbackModelCount(.grok));
    try testing.expectEqual(@as(usize, 0), fallbackModelCount(.kimi));
    try testing.expectEqual(@as(usize, 0), fallbackModelCount(.opencode));
    try testing.expectEqual(@as(usize, 0), fallbackModelCount(.ohmypi));
    try testing.expectEqual(@as(usize, 0), fallbackModelCount(.opencode2));
    try testing.expectEqual(@as(usize, 0), fallbackModelCount(.deepseek));
}

test "rowFor paints model_count when Available with a catalog; disabled wins; Not found omits" {
    const testing = std.testing;
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var model = Model{};

    try testing.expect(!rowFor(&model, .claude, arena).has_model_count);
    try testing.expectEqualStrings("", rowFor(&model, .claude, arena).model_count_label);
    try testing.expect(!rowFor(&model, .fx, arena).has_model_count);
    try testing.expect(!rowFor(&model, .cursor, arena).has_model_count);
    try testing.expect(!rowFor(&model, .amp, arena).has_model_count);

    model.cli_available[@intFromEnum(protocol.ProviderId.claude)] = true;
    model.cli_available[@intFromEnum(protocol.ProviderId.cursor)] = true;
    model.cli_available[@intFromEnum(protocol.ProviderId.amp)] = true;
    model.cli_available[@intFromEnum(protocol.ProviderId.codex)] = true;
    model.fx_available = true;
    model.cli_available[@intFromEnum(protocol.ProviderId.pi)] = true;
    model.cli_available[@intFromEnum(protocol.ProviderId.ohmypi)] = true;
    model.cli_available[@intFromEnum(protocol.ProviderId.opencode2)] = true;
    model.cli_available[@intFromEnum(protocol.ProviderId.deepseek)] = true;

    try testing.expect(rowFor(&model, .claude, arena).has_model_count);
    try testing.expectEqualStrings("9 models", rowFor(&model, .claude, arena).model_count_label);
    try testing.expect(rowFor(&model, .amp, arena).has_model_count);
    try testing.expectEqualStrings("4 models", rowFor(&model, .amp, arena).model_count_label);
    try testing.expect(rowFor(&model, .codex, arena).has_model_count);
    try testing.expectEqualStrings("5 models", rowFor(&model, .codex, arena).model_count_label);
    try testing.expect(rowFor(&model, .cursor, arena).has_model_count);
    try testing.expectEqualStrings("1 model", rowFor(&model, .cursor, arena).model_count_label);
    try testing.expect(!rowFor(&model, .fx, arena).has_model_count);
    try testing.expectEqualStrings("", rowFor(&model, .fx, arena).model_count_label);
    try testing.expect(!rowFor(&model, .pi, arena).has_model_count);
    try testing.expectEqualStrings("", rowFor(&model, .pi, arena).model_count_label);
    try testing.expect(!rowFor(&model, .ohmypi, arena).has_model_count);
    try testing.expectEqualStrings("", rowFor(&model, .ohmypi, arena).model_count_label);
    try testing.expectEqualStrings("Oh My Pi", rowFor(&model, .ohmypi, arena).name);
    try testing.expect(!rowFor(&model, .opencode2, arena).has_model_count);
    try testing.expectEqualStrings("", rowFor(&model, .opencode2, arena).model_count_label);
    try testing.expectEqualStrings("OpenCode 2", rowFor(&model, .opencode2, arena).name);
    try testing.expect(!rowFor(&model, .deepseek, arena).has_model_count);
    try testing.expectEqualStrings("", rowFor(&model, .deepseek, arena).model_count_label);
    try testing.expectEqualStrings("DeepSeek", rowFor(&model, .deepseek, arena).name);

    setProviderEnabled(&model, .claude, false);
    try testing.expect(rowFor(&model, .claude, arena).has_model_count);
    try testing.expectEqualStrings("Disabled for new tasks", rowFor(&model, .claude, arena).model_count_label);
    try testing.expect(std.mem.indexOf(u8, rowFor(&model, .claude, arena).model_count_label, "model") == null);

    setProviderEnabled(&model, .fx, false);
    try testing.expect(rowFor(&model, .fx, arena).has_model_count);
    try testing.expectEqualStrings("Disabled for new tasks", rowFor(&model, .fx, arena).model_count_label);

    setProviderEnabled(&model, .claude, true);
    model.cli_available[@intFromEnum(protocol.ProviderId.claude)] = false;
    try testing.expect(!rowFor(&model, .claude, arena).has_model_count);
    try testing.expectEqualStrings("", rowFor(&model, .claude, arena).model_count_label);

    model.language_preference = .simplified_chinese;
    model.cli_available[@intFromEnum(protocol.ProviderId.claude)] = true;
    try testing.expectEqualStrings("9 个模型", rowFor(&model, .claude, arena).model_count_label);
    setProviderEnabled(&model, .claude, false);
    try testing.expectEqualStrings("新建任务时不可用", rowFor(&model, .claude, arena).model_count_label);

    model.language_preference = .japanese;
    setProviderEnabled(&model, .claude, true);
    try testing.expectEqualStrings("9 個のモデル", rowFor(&model, .claude, arena).model_count_label);
    setProviderEnabled(&model, .cursor, false);
    try testing.expectEqualStrings("新規タスクでは無効", rowFor(&model, .cursor, arena).model_count_label);
}

test "rowFor icon is app:provider-* for each ProviderId; Codex uses OpenAI mark" {
    const testing = std.testing;
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var model = Model{};

    try testing.expectEqualStrings("app:provider-fx", iconName(.fx));
    try testing.expectEqualStrings("app:provider-claude", iconName(.claude));
    try testing.expectEqualStrings("app:provider-openai", iconName(.codex));
    try testing.expectEqualStrings("app:provider-amp", iconName(.amp));
    try testing.expectEqualStrings("app:provider-grok", iconName(.grok));
    try testing.expectEqualStrings("app:provider-opencode", iconName(.opencode));
    try testing.expectEqualStrings("app:provider-cursor", iconName(.cursor));
    try testing.expectEqualStrings("app:provider-pi", iconName(.pi));
    try testing.expectEqualStrings("app:provider-kimi", iconName(.kimi));
    try testing.expectEqualStrings("app:provider-ohmypi", iconName(.ohmypi));
    try testing.expectEqualStrings("app:provider-opencode2", iconName(.opencode2));
    try testing.expectEqualStrings("app:provider-deepseek", iconName(.deepseek));
    try testing.expect(!std.mem.eql(u8, iconName(.codex), "app:provider-codex"));
    try testing.expect(!std.mem.eql(u8, iconName(.opencode2), iconName(.opencode)));

    for (std.meta.tags(protocol.ProviderId)) |id| {
        const row = rowFor(&model, id, arena);
        try testing.expectEqualStrings(iconName(id), row.icon);
        try testing.expect(std.mem.startsWith(u8, row.icon, "app:provider-"));
    }
}

test "rowFor status_available / status_missing follow isAvailable; Not found vs probe Available" {
    const testing = std.testing;
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    const missing_fx = rowFor(&model, .fx, arena);
    try testing.expect(!missing_fx.status_available);
    try testing.expect(missing_fx.status_missing);
    try testing.expectEqualStrings(missing_status, missing_fx.status);
    const missing_claude = rowFor(&model, .claude, arena);
    try testing.expect(!missing_claude.status_available);
    try testing.expect(missing_claude.status_missing);
    try testing.expectEqualStrings(missing_status, missing_claude.status);

    model.fx_available = true;
    const available_fx = rowFor(&model, .fx, arena);
    try testing.expect(available_fx.status_available);
    try testing.expect(!available_fx.status_missing);
    try testing.expectEqualStrings(available_status, available_fx.status);
    try testing.expect(!rowFor(&model, .claude, arena).status_available);
    try testing.expect(rowFor(&model, .claude, arena).status_missing);

    cli_probe.handleCliProbeExit(&model, &fx, .{
        .key = cli_probe.probeKey(.claude),
        .reason = .exited,
        .code = 0,
    });
    const available_claude = rowFor(&model, .claude, arena);
    try testing.expect(available_claude.status_available);
    try testing.expect(!available_claude.status_missing);
    try testing.expectEqualStrings(available_status, available_claude.status);

    cli_probe.handleCliProbeExit(&model, &fx, .{
        .key = cli_probe.probeKey(.codex),
        .reason = .exited,
        .code = 127,
    });
    const missing_codex = rowFor(&model, .codex, arena);
    try testing.expect(!missing_codex.status_available);
    try testing.expect(missing_codex.status_missing);
    try testing.expectEqualStrings(missing_status, missing_codex.status);
}

fn findPendingVersion(fx: *Effects, id: protocol.ProviderId) ?@TypeOf(fx.pendingSpawnAt(0).?) {
    const key = cli_version.versionKey(id);
    var i: usize = 0;
    while (fx.pendingSpawnAt(i)) |item| : (i += 1) {
        if (item.key == key) return item;
    }
    return null;
}

