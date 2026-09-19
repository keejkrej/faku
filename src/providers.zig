//! Settings Providers: fx probe status plus non-fx `--help` probes.
//!
//! Settings page. Lists every `protocol.ProviderId` as a runtime-only
//! row. fx (first-party default) reads existing `model.fx_available` /
//! `fxPath()` — no new probe key. Other ids one-shot PATH
//! `{defaultBinary()} --help` via `cli_probe.zig` (Available / Not
//! found when that exit lands). Boot (`initFx`) starts non-fx probes
//! alongside the fx probe; Settings → Providers open calls
//! `startProbes` (no-op when already started). Refresh re-runs
//! fx_probe and every non-fx probe. Selecting a row highlights
//! and shows detail; Apply ("Use for this session") sets the selected
//! chat session's `provider` and persists via `sessions.json`. First-cut
//! per-row Enable/Disable persists `disabled_providers` (wire names) on
//! that same extras bag. The Enable/Disable chip is disable-flag-only
//! (user can toggle regardless of install). `providerEnabled` (the
//! plan-usage `maybeRefresh` gate) is `!disabled && isAvailable`.
//! Disabled or Not-found / unset skips background plan-usage refresh
//! unless the selected session already uses that id; a started session
//! on a disabled or uninstalled provider still works and still fetches
//! when selected. New
//! sessions stay `.fx`. Live Send for probed ACP stdio providers
//! (cursor, opencode, kimi, grok) is `spawn.startPrompt` (first-cut ACP v1
//! image content blocks when a composer image is attached); Available Claude
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
//! documented RPC `images` when a composer image is attached). fx
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
//! `providers.description`; Refresh stays the Settings header
//! button). Tests do not
//! need a live daemon or any real CLI install.
//!
//! Leftovers: full onboarding / OAuth / auto-install; Pi ACP /
//! long-lived RPC (steer / follow_up / session resume); Claude ACP; `--continue`; circular GPUI gauge;
//! LiteLLM rate-table; T3 layered Usage chart; amend/force and
//! remote `--track` over daemon (local already). Provider binary-path
//! override / version badge / model_count / expand chevron /
//! moving Refresh into the card stay out.
//! Disabling does not
//! move unstarted drafts / last_provider (Faku new sessions stay fx;
//! drafts.json has no provider).
//! Claude print-mode stream-json (later Sends pass documented
//! `--resume {fx_session_id}` when that field is non-empty; first
//! Send and Fork omit it; `--forward-subagent-text` always;
//! image path in the `-p` prompt when
//! attached),
//! Codex exec (`--image` when attached), Amp
//! execute-mode (`@path` when attached), and Pi RPC one-shot
//! (`--mode rpc --no-session`, stdin prompt JSONL, RPC `images` when
//! attached) ship this cut (not ACP, not a long-lived RPC loop, not
//! `--mode json`, not permissions bypass). Appearance theme,
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
};

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

/// Probed fx path when that probe succeeded, else PATH `defaultBinary`.
pub fn binaryFor(model: *const Model, id: protocol.ProviderId) []const u8 {
    if (id == .fx and model.fx_available) {
        const path = model.fxPath();
        if (path.len > 0) return path;
    }
    return id.defaultBinary();
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
    const text = i18n.formatProvidersEnableNamed(named, enabled, id.wireName(), &buf);
    return copyNamed(arena, text);
}

/// `arena` owns `enable_label` (named Enable %{name} / Disable
/// %{name}). Callers of `rows` pass the Native frame arena. Tests
/// pass an ArenaAllocator (or any allocator that outlives the row).
pub fn rowFor(model: *const Model, id: protocol.ProviderId, arena: std.mem.Allocator) ProviderRow {
    const binary = binaryFor(model, id);
    const rid = rowId(id);
    const enabled = !model.disabled_providers[@intFromEnum(id)];
    const pack = chrome(model);
    return .{
        .id = rid,
        .name = id.wireName(),
        .status = statusFor(model, id),
        .binary = binary,
        .has_binary = binary.len > 0,
        .first_party = id == .fx,
        .selected = model.provider_selected_id == rid,
        .enabled = enabled,
        .enable_label = enableLabelFor(model, id, arena),
        .first_party_label = if (id == .fx) pack.first_party else "",
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
    if (id == .fx) {
        const path = model.fxPath();
        if (model.fx_available and path.len > 0) {
            return std.fmt.allocPrint(arena, "{s}\n{s}\n{s} {s}\n{s} {s}\n{s}", .{
                id.wireName(),
                pack.first_party,
                notes.binary_prefix,
                id.defaultBinary(),
                notes.path_prefix,
                path,
                notes.fx_transport_note,
            }) catch "";
        }
        return std.fmt.allocPrint(arena, "{s}\n{s}\n{s} {s}\n{s}\n{s}", .{
            id.wireName(),
            pack.first_party,
            notes.binary_prefix,
            id.defaultBinary(),
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
    else if (id.speaksBareAcp())
        notes.acp_transport_note
    else
        notes.catalog_detail_note;
    return std.fmt.allocPrint(arena, "{s}\n{s} {s}\n{s}\n{s}", .{
        id.wireName(),
        notes.binary_prefix,
        id.defaultBinary(),
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

pub fn close(model: *Model) void {
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
    try std.testing.expectEqual(@as(usize, 9), catalogLen());
    try std.testing.expectEqual(protocol.provider_id_count, catalogLen());
    try std.testing.expectEqual(@as(usize, 9), tags.len);
    try std.testing.expectEqual(protocol.ProviderId.fx, tags[0]);
    try std.testing.expectEqual(@as(u32, 1), rowId(.fx));
    try std.testing.expectEqual(@as(u32, 2), rowId(.claude));
    try std.testing.expectEqual(@as(u32, 8), rowId(.pi));
    try std.testing.expectEqual(@as(u32, 9), rowId(.kimi));
    try std.testing.expectEqual(protocol.ProviderId.fx, fromRowId(1).?);
    try std.testing.expectEqual(protocol.ProviderId.claude, fromRowId(2).?);
    try std.testing.expectEqual(protocol.ProviderId.pi, fromRowId(8).?);
    try std.testing.expectEqual(protocol.ProviderId.kimi, fromRowId(9).?);
    try std.testing.expect(fromRowId(0) == null);
    try std.testing.expect(fromRowId(10) == null);
    try std.testing.expectEqualStrings("fx", protocol.ProviderId.fx.wireName());
    try std.testing.expectEqualStrings("cursor-agent", protocol.ProviderId.cursor.defaultBinary());
    try std.testing.expectEqualStrings("kimi", protocol.ProviderId.kimi.wireName());
    try std.testing.expectEqualStrings("kimi", protocol.ProviderId.kimi.defaultBinary());
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
    try std.testing.expectEqualStrings("cursor-agent", binaryFor(&model, .cursor));
    try std.testing.expectEqualStrings("claude", binaryFor(&model, .claude));
    try std.testing.expectEqualStrings("kimi", binaryFor(&model, .kimi));

    model.fx_available = true;
    model.setFxPath("/tmp/faku-fx");
    try std.testing.expectEqualStrings(available_status, statusFor(&model, .fx));
    try std.testing.expectEqualStrings("/tmp/faku-fx", binaryFor(&model, .fx));
    try std.testing.expectEqualStrings(missing_status, statusFor(&model, .claude));

    const fx_row = rowFor(&model, .fx, arena);
    try std.testing.expect(fx_row.first_party);
    try std.testing.expectEqualStrings(first_party_label, fx_row.first_party_label);
    try std.testing.expectEqualStrings(available_status, fx_row.status);
    try std.testing.expect(!rowFor(&model, .claude, arena).first_party);
    try std.testing.expectEqualStrings("", rowFor(&model, .claude, arena).first_party_label);
}

test "non-fx success exit is Available; non-zero is Not found; fx stays on fx_available" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var model = Model{};
    cli_probe.handleCliProbeExit(&model, .{
        .key = cli_probe.probeKey(.claude),
        .reason = .exited,
        .code = 0,
    });
    try std.testing.expectEqualStrings(available_status, statusFor(&model, .claude));
    try std.testing.expectEqualStrings("claude", binaryFor(&model, .claude));
    try std.testing.expectEqualStrings(missing_status, statusFor(&model, .fx));

    cli_probe.handleCliProbeExit(&model, .{
        .key = cli_probe.probeKey(.codex),
        .reason = .exited,
        .code = 127,
    });
    try std.testing.expectEqualStrings(missing_status, statusFor(&model, .codex));

    model.fx_available = true;
    try std.testing.expectEqualStrings(available_status, statusFor(&model, .fx));
    try std.testing.expectEqualStrings(available_status, rowFor(&model, .claude, arena).status);
    try std.testing.expectEqualStrings(missing_status, rowFor(&model, .codex, arena).status);
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

    try testing.expect(protocol.ProviderId.cursor.speaksBareAcp());
    try testing.expect(protocol.ProviderId.opencode.speaksBareAcp());
    try testing.expect(protocol.ProviderId.kimi.speaksBareAcp());
    try testing.expect(!protocol.ProviderId.claude.speaksBareAcp());
    try testing.expect(!protocol.ProviderId.fx.speaksBareAcp());
    try testing.expect(!protocol.ProviderId.grok.speaksBareAcp());
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
    try std.testing.expect(!showsOtherInstallHint(&model));

    selectProvider(&model, rowId(.fx));
    try std.testing.expect(canCopyFxInstall(&model));
    try std.testing.expect(!canCopyFxLogin(&model));
    try std.testing.expect(!showsOtherInstallHint(&model));

    model.fx_available = true;
    try std.testing.expect(!canCopyFxInstall(&model));
    try std.testing.expect(canCopyFxLogin(&model));
    try std.testing.expect(!showsOtherInstallHint(&model));

    selectProvider(&model, rowId(.claude));
    try std.testing.expect(!canCopyFxInstall(&model));
    try std.testing.expect(!canCopyFxLogin(&model));
    try std.testing.expect(showsOtherInstallHint(&model));

    model.cli_available[@intFromEnum(protocol.ProviderId.claude)] = true;
    try std.testing.expect(!showsOtherInstallHint(&model));

    const others = [_]protocol.ProviderId{ .codex, .amp, .grok, .opencode, .cursor, .pi, .kimi };
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

