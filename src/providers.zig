//! Settings Providers: fx probe status plus non-fx `--help` probes.
//!
//! Settings page. Lists every `protocol.ProviderId` as a runtime-only
//! row. fx (first-party default) reads existing `model.fx_available` /
//! `fxPath()` — no new probe key. Other ids one-shot PATH
//! `{defaultBinary()} --help` via `cli_probe.zig` (Available / Not
//! found when that exit lands). Open starts non-fx probes; Refresh
//! re-runs fx_probe and every non-fx probe. Selecting a row highlights
//! and shows detail; Apply ("Use for this session") sets the selected
//! chat session's `provider` and persists via `sessions.json`. New
//! sessions stay `.fx`. Live Send for probed ACP stdio providers
//! (cursor, opencode, grok) is `spawn.startPrompt`; Available Claude
//! is one-shot print-mode stream-json (`claude -p --output-format
//! stream-json --verbose --include-partial-messages
//! --forward-subagent-text`; documented
//! `--resume {fx_session_id}` on later Sends when that field is
//! non-empty; first Send and Fork omit it; not `--continue`;
//! documented image path inside that `-p` prompt when a composer image is
//! attached; stdout is NDJSON with live `text_delta`; live Subagent
//! Background from `parent_tool_use_id`; live Monitor Background from
//! Claude `Monitor` `tool_use`); Available Codex is one-shot `codex exec {prompt}`
//! (documented `--image {path}` after the prompt when a composer image
//! is attached); Available Amp is
//! one-shot `amp -x {prompt}` (`--execute` is the long form; documented
//! `@{path}` in the `-x` prompt when a composer image is attached);
//! Available Pi is
//! one-shot `pi --mode json {prompt}` (documented
//! `@{path}` after json when a composer image is attached). fx
//! Not found copies the verified `https://fx.sh` install
//! command via `fx.writeClipboard` (never auto-runs `setup.sh`). fx
//! Available copies `fx login` the same way — convenience copy, not
//! auth-state detection or OAuth UI. Other missing CLIs get a muted
//! PATH hint only (no invented install URLs). Tests do not need a live
//! daemon or any real CLI install.
//!
//! Leftovers: full onboarding / OAuth / auto-install; Pi ACP /
//! `--mode rpc`; Claude ACP; `--continue`.
//! Claude print-mode stream-json (later Sends pass documented
//! `--resume {fx_session_id}` when that field is non-empty; first
//! Send and Fork omit it; `--forward-subagent-text` always;
//! image path in the `-p` prompt when
//! attached),
//! Codex exec (`--image` when attached), Amp
//! execute-mode (`@path` when attached), and Pi json-mode (`@path`
//! when attached) ship this cut (not ACP, not `--mode rpc`, not
//! permissions bypass). Appearance theme,
//! Usage, and Computer Use first-cut pages ship (Computer Use is
//! Unavailable / Off; no Native helper). Not Waku install/auth.

const std = @import("std");
const main = @import("main.zig");
const protocol = @import("protocol.zig");
const fx_probe = @import("fx_probe.zig");
const cli_probe = @import("cli_probe.zig");
const copy_helpers = @import("copy.zig");

const Model = main.Model;
const Effects = main.Effects;

pub const available_status = "Available";
pub const missing_status = "Not found";
pub const fx_available_status = available_status;
pub const fx_missing_status = missing_status;
pub const catalog_detail_note = "Status is a PATH --help probe. Send stays demo this cut.";
pub const first_party_label = "First-party default";
pub const fx_transport_note = "Live path is one-shot fx acp via acp-proxy.";
pub const acp_transport_note = "Live Send is one-shot acp via acp-proxy when Available.";
pub const grok_transport_note = "Live Send is one-shot grok agent stdio via acp-proxy when Available.";
pub const claude_transport_note = "Live Send is one-shot claude -p --output-format stream-json --forward-subagent-text when Available (later Sends --resume {fx_session_id} when stored; image path in the -p prompt when attached).";
pub const codex_transport_note = "Live Send is one-shot codex exec when Available (`--image` when attached).";
pub const amp_transport_note = "Live Send is one-shot amp -x / --execute when Available (`@path` when attached).";
pub const pi_transport_note = "Live Send is one-shot pi --mode json when Available (`@path` when attached).";
pub const apply_session_label = "Use for this session";
/// Verified from https://fx.sh and vercel-labs/fx README. Copied
/// to the clipboard; never spawned as a shell that runs setup.sh.
pub const fx_install_command = "curl -fsSL https://fx.sh/setup.sh | bash";
/// Verified from vercel-labs/fx README. Convenience copy only.
pub const fx_login_command = "fx login";
pub const copy_install_label = "Copy install command";
pub const copy_login_label = "Copy login command";
pub const fx_login_note = "Faku does not detect auth state from the --help probe. Copy is a convenience, not sign-in UI or OAuth.";
pub const fx_login_codex_note = "Optional: fx login codex for ChatGPT/Codex OAuth.";
pub const other_install_hint = "Install that CLI on PATH, then Refresh.";

/// Settings Providers row. `id` is 1-based `@intFromEnum(ProviderId)`
/// so Native `select_provider:{p.id}` never binds 0.
pub const ProviderRow = struct {
    id: u32,
    name: []const u8,
    status: []const u8,
    binary: []const u8,
    has_binary: bool = false,
    first_party: bool = false,
    selected: bool = false,
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

pub fn statusFor(model: *const Model, id: protocol.ProviderId) []const u8 {
    if (isAvailable(model, id)) return available_status;
    return missing_status;
}

/// Probed fx path when that probe succeeded, else PATH `defaultBinary`.
pub fn binaryFor(model: *const Model, id: protocol.ProviderId) []const u8 {
    if (id == .fx and model.fx_available) {
        const path = model.fxPath();
        if (path.len > 0) return path;
    }
    return id.defaultBinary();
}

pub fn rowFor(model: *const Model, id: protocol.ProviderId) ProviderRow {
    const binary = binaryFor(model, id);
    const rid = rowId(id);
    return .{
        .id = rid,
        .name = id.wireName(),
        .status = statusFor(model, id),
        .binary = binary,
        .has_binary = binary.len > 0,
        .first_party = id == .fx,
        .selected = model.provider_selected_id == rid,
    };
}

pub fn rows(model: *const Model, arena: std.mem.Allocator) []const ProviderRow {
    if (model.settings_page != .providers) return &.{};
    const tags = std.meta.tags(protocol.ProviderId);
    const out = arena.alloc(ProviderRow, tags.len) catch return &.{};
    for (tags, 0..) |id, i| {
        out[i] = rowFor(model, id);
    }
    return out;
}

pub fn detailText(model: *const Model, arena: std.mem.Allocator) []const u8 {
    const id = fromRowId(model.provider_selected_id) orelse return "";
    if (id == .fx) {
        const path = model.fxPath();
        if (model.fx_available and path.len > 0) {
            return std.fmt.allocPrint(arena, "{s}\n{s}\nBinary: {s}\nPath: {s}\n{s}", .{
                id.wireName(),
                first_party_label,
                id.defaultBinary(),
                path,
                fx_transport_note,
            }) catch "";
        }
        return std.fmt.allocPrint(arena, "{s}\n{s}\nBinary: {s}\n{s}\n{s}", .{
            id.wireName(),
            first_party_label,
            id.defaultBinary(),
            missing_status,
            fx_transport_note,
        }) catch "";
    }
    const note = if (id == .grok)
        grok_transport_note
    else if (id == .claude)
        claude_transport_note
    else if (id == .codex)
        codex_transport_note
    else if (id == .amp)
        amp_transport_note
    else if (id == .pi)
        pi_transport_note
    else if (id.speaksBareAcp())
        acp_transport_note
    else
        catalog_detail_note;
    return std.fmt.allocPrint(arena, "{s}\nBinary: {s}\n{s}\n{s}", .{
        id.wireName(),
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

/// Copy the verified fx install command. No-op when the install
/// button would be hidden. Does not spawn a shell.
pub fn copyFxInstall(model: *const Model, fx: *Effects) void {
    if (!canCopyFxInstall(model)) return;
    copy_helpers.copyText(fx, fx_install_command);
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

/// Settings → Providers open. Non-fx PATH `--help` probes only.
pub fn startProbes(model: *Model, fx: *Effects) void {
    cli_probe.startCliProbes(model, fx);
}

/// Re-run fx `--help` and every non-fx PATH `--help` probe.
pub fn refresh(model: *Model, fx: *Effects) void {
    fx_probe.restartFxProbe(model, fx);
    cli_probe.restartCliProbes(model, fx);
}

test "catalog lists every ProviderId; fx is row 1" {
    const tags = std.meta.tags(protocol.ProviderId);
    try std.testing.expectEqual(@as(usize, 8), catalogLen());
    try std.testing.expectEqual(protocol.provider_id_count, catalogLen());
    try std.testing.expectEqual(@as(usize, 8), tags.len);
    try std.testing.expectEqual(protocol.ProviderId.fx, tags[0]);
    try std.testing.expectEqual(@as(u32, 1), rowId(.fx));
    try std.testing.expectEqual(@as(u32, 2), rowId(.claude));
    try std.testing.expectEqual(@as(u32, 8), rowId(.pi));
    try std.testing.expectEqual(protocol.ProviderId.fx, fromRowId(1).?);
    try std.testing.expectEqual(protocol.ProviderId.claude, fromRowId(2).?);
    try std.testing.expectEqual(protocol.ProviderId.pi, fromRowId(8).?);
    try std.testing.expect(fromRowId(0) == null);
    try std.testing.expect(fromRowId(9) == null);
    try std.testing.expectEqualStrings("fx", protocol.ProviderId.fx.wireName());
    try std.testing.expectEqualStrings("cursor-agent", protocol.ProviderId.cursor.defaultBinary());
}

test "fx status from model fields without spawning; non-fx defaults Not found" {
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
    try std.testing.expectEqualStrings("cursor-agent", binaryFor(&model, .cursor));
    try std.testing.expectEqualStrings("claude", binaryFor(&model, .claude));

    model.fx_available = true;
    model.setFxPath("/tmp/faku-fx");
    try std.testing.expectEqualStrings(available_status, statusFor(&model, .fx));
    try std.testing.expectEqualStrings("/tmp/faku-fx", binaryFor(&model, .fx));
    try std.testing.expectEqualStrings(missing_status, statusFor(&model, .claude));

    const fx_row = rowFor(&model, .fx);
    try std.testing.expect(fx_row.first_party);
    try std.testing.expectEqualStrings(first_party_label, first_party_label);
    try std.testing.expectEqualStrings(available_status, fx_row.status);
    try std.testing.expect(!rowFor(&model, .claude).first_party);
}

test "non-fx success exit is Available; non-zero is Not found; fx stays on fx_available" {
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
    try std.testing.expectEqualStrings(available_status, rowFor(&model, .claude).status);
    try std.testing.expectEqualStrings(missing_status, rowFor(&model, .codex).status);
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
    try testing.expect(std.mem.indexOf(u8, fx_detail, "/home/probe/.local/bin/fx") != null);
    try testing.expect(std.mem.indexOf(u8, fx_detail, fx_transport_note) != null);
    try testing.expect(std.mem.indexOf(u8, fx_detail, catalog_detail_note) == null);

    selectProvider(&model, 2);
    try testing.expectEqual(@as(u32, 2), model.provider_selected_id);
    const claude_detail = detailText(&model, testing.allocator);
    defer if (claude_detail.len > 0) testing.allocator.free(claude_detail);
    try testing.expect(std.mem.indexOf(u8, claude_detail, "claude") != null);
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

    try testing.expect(protocol.ProviderId.cursor.speaksBareAcp());
    try testing.expect(protocol.ProviderId.opencode.speaksBareAcp());
    try testing.expect(!protocol.ProviderId.claude.speaksBareAcp());
    try testing.expect(!protocol.ProviderId.fx.speaksBareAcp());
    try testing.expect(!protocol.ProviderId.grok.speaksBareAcp());
    try testing.expect(protocol.ProviderId.grok.speaksAcpStdio());
    try testing.expect(protocol.ProviderId.cursor.speaksAcpStdio());

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
    try testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());

    refresh(&model, &fx);
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

test "rows empty off the Providers page" {
    var model = Model{};
    const off = rows(&model, std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), off.len);
    model.settings_page = .providers;
    const on = rows(&model, std.testing.allocator);
    defer std.testing.allocator.free(on);
    try std.testing.expectEqual(catalogLen(), on.len);
    try std.testing.expectEqualStrings("fx", on[0].name);
    try std.testing.expect(on[0].first_party);
    try std.testing.expectEqualStrings("claude", on[1].name);
    try std.testing.expectEqualStrings(missing_status, on[1].status);
    try std.testing.expectEqualStrings("claude", on[1].binary);
}

test "copy command strings are the verified fx.sh / README commands" {
    try std.testing.expectEqualStrings(
        "curl -fsSL https://fx.sh/setup.sh | bash",
        fx_install_command,
    );
    try std.testing.expectEqualStrings("fx login", fx_login_command);
    try std.testing.expectEqualStrings("Copy install command", copy_install_label);
    try std.testing.expectEqualStrings("Copy login command", copy_login_label);
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

    const others = [_]protocol.ProviderId{ .codex, .amp, .grok, .opencode, .cursor, .pi };
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
    try testing.expectEqual(main.copy_turn_key, install.key);
    try testing.expectEqual(@import("native_sdk").EffectClipboardOp.write, install.op);
    try testing.expectEqualStrings(fx_install_command, install.text);
    try testing.expectEqualStrings("curl -fsSL https://fx.sh/setup.sh | bash", install.text);

    model.fx_available = true;
    copyFxInstall(&model, &fx);
    try testing.expectEqual(@as(usize, 1), fx.pendingClipboardCount());
    try testing.expectEqualStrings(fx_install_command, fx.pendingClipboardAt(0).?.text);

    var login_fx = Effects.init(testing.allocator);
    defer login_fx.deinit();
    login_fx.executor = .fake;
    copyFxLogin(&model, &login_fx);
    try testing.expectEqual(@as(usize, 1), login_fx.pendingClipboardCount());
    const login = login_fx.pendingClipboardAt(0).?;
    try testing.expectEqual(main.copy_turn_key, login.key);
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
