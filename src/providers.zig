//! Settings Providers: fx probe status plus catalog ids.
//!
//! First-cut Settings page. Lists every `protocol.ProviderId` as a
//! runtime-only row. fx (first-party default) reads existing
//! `model.fx_available` / `fxPath()` — no new probe key. Refresh
//! resets `fx_probe_started` and calls `fx_probe.startFxProbe` so
//! status can update. Other ids are honest catalog rows only.
//! Tests do not need a live daemon or fx binary.
//!
//! Leftovers: probing every non-fx CLI with `--help`; install /
//! sign-in / auto-detect onboarding; enabling non-fx providers on
//! Send or changing `session.provider` from this page; Appearance /
//! Usage / Computer Use settings pages. Not Waku install/auth.

const std = @import("std");
const main = @import("main.zig");
const protocol = @import("protocol.zig");
const fx_probe = @import("fx_probe.zig");

const Model = main.Model;
const Effects = main.Effects;

pub const fx_available_status = "Available";
pub const fx_missing_status = "Not found";
pub const catalog_status = "Catalog id only";
pub const catalog_detail_note = "Not a live driver this cut.";
pub const first_party_label = "First-party default";
pub const fx_transport_note = "Live path is one-shot fx acp via acp-proxy.";

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
    return @intFromEnum(id) + 1;
}

pub fn fromRowId(id: u32) ?protocol.ProviderId {
    if (id == 0) return null;
    const tags = std.meta.tags(protocol.ProviderId);
    const index = id - 1;
    if (index >= tags.len) return null;
    return tags[index];
}

pub fn statusFor(model: *const Model, id: protocol.ProviderId) []const u8 {
    if (id != .fx) return catalog_status;
    if (model.fx_available) return fx_available_status;
    return fx_missing_status;
}

/// Probed fx path when that probe succeeded, else `defaultBinary`.
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
            fx_missing_status,
            fx_transport_note,
        }) catch "";
    }
    return std.fmt.allocPrint(arena, "{s}\nBinary: {s}\n{s}. {s}", .{
        id.wireName(),
        id.defaultBinary(),
        catalog_status,
        catalog_detail_note,
    }) catch "";
}

pub fn selectProvider(model: *Model, id: u32) void {
    if (fromRowId(id) == null) {
        model.provider_selected_id = 0;
        return;
    }
    model.provider_selected_id = id;
}

pub fn close(model: *Model) void {
    model.provider_selected_id = 0;
}

/// Re-run the existing fx `--help` probe. Does not probe non-fx CLIs.
pub fn refresh(model: *Model, fx: *Effects) void {
    fx_probe.restartFxProbe(model, fx);
}

test "catalog lists every ProviderId; fx is row 1" {
    const tags = std.meta.tags(protocol.ProviderId);
    try std.testing.expectEqual(@as(usize, 8), catalogLen());
    try std.testing.expectEqual(@as(usize, 8), tags.len);
    try std.testing.expectEqual(protocol.ProviderId.fx, tags[0]);
    try std.testing.expectEqual(@as(u32, 1), rowId(.fx));
    try std.testing.expectEqual(protocol.ProviderId.fx, fromRowId(1).?);
    try std.testing.expectEqual(protocol.ProviderId.claude, fromRowId(2).?);
    try std.testing.expectEqual(protocol.ProviderId.pi, fromRowId(8).?);
    try std.testing.expect(fromRowId(0) == null);
    try std.testing.expect(fromRowId(9) == null);
    try std.testing.expectEqualStrings("fx", protocol.ProviderId.fx.wireName());
    try std.testing.expectEqualStrings("cursor-agent", protocol.ProviderId.cursor.defaultBinary());
}

test "fx status from model fields without spawning; catalog ids stay catalog-only" {
    var model = Model{};
    try std.testing.expectEqualStrings(fx_missing_status, statusFor(&model, .fx));
    try std.testing.expectEqualStrings("fx", binaryFor(&model, .fx));
    try std.testing.expectEqualStrings(catalog_status, statusFor(&model, .claude));
    try std.testing.expectEqualStrings(catalog_status, statusFor(&model, .codex));
    try std.testing.expectEqualStrings(catalog_status, statusFor(&model, .amp));
    try std.testing.expectEqualStrings(catalog_status, statusFor(&model, .grok));
    try std.testing.expectEqualStrings(catalog_status, statusFor(&model, .opencode));
    try std.testing.expectEqualStrings(catalog_status, statusFor(&model, .cursor));
    try std.testing.expectEqualStrings(catalog_status, statusFor(&model, .pi));
    try std.testing.expectEqualStrings("cursor-agent", binaryFor(&model, .cursor));

    model.fx_available = true;
    model.setFxPath("/tmp/faku-fx");
    try std.testing.expectEqualStrings(fx_available_status, statusFor(&model, .fx));
    try std.testing.expectEqualStrings("/tmp/faku-fx", binaryFor(&model, .fx));
    try std.testing.expectEqualStrings(catalog_status, statusFor(&model, .claude));

    const fx_row = rowFor(&model, .fx);
    try std.testing.expect(fx_row.first_party);
    try std.testing.expectEqualStrings(first_party_label, first_party_label);
    try std.testing.expectEqualStrings(fx_available_status, fx_row.status);
    try std.testing.expect(!rowFor(&model, .claude).first_party);
}

test "selectProvider; detail names binary, fx path, and one-shot acp-proxy" {
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
    try testing.expect(std.mem.indexOf(u8, claude_detail, catalog_status) != null);
    try testing.expect(std.mem.indexOf(u8, claude_detail, catalog_detail_note) != null);
    try testing.expect(std.mem.indexOf(u8, claude_detail, fx_transport_note) == null);

    selectProvider(&model, 99);
    try testing.expectEqual(@as(u32, 0), model.provider_selected_id);
    try testing.expectEqualStrings("", detailText(&model, testing.allocator));
}

test "refresh queues fx --help probe when started was already true" {
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
    var i: usize = 0;
    var spawn = fx.pendingSpawnAt(0);
    while (spawn) |item| : (i += 1) {
        if (item.key == fx_probe.fx_probe_key and fx_probe.isFxProbeArgv(item.argv)) break;
        spawn = fx.pendingSpawnAt(i + 1);
    }
    try testing.expect(spawn != null);
    try testing.expectEqual(fx_probe.fx_probe_key, spawn.?.key);
    try testing.expect(fx_probe.isFxProbeArgv(spawn.?.argv));
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
    try std.testing.expectEqualStrings(catalog_status, on[1].status);
}
