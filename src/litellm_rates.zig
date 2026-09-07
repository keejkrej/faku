//! First-cut LiteLLM model rate-table fetch + 24h disk cache.
//!
//! Settings → Usage loads LiteLLM's `model_prices_and_context_window.json`
//! through one-shot `fx.spawn` curl (`-o` into the Faku data dir so the
//! multi-MB document never streams through Native EffectLine). Compact
//! cache `usage-model-rates.json` sits beside `sessions.json` (Native
//! `app_dirs` data, app name `faku` — not `~/.waku`). TTL is 24 hours.
//! Runtime map only; not `sessions.json`. Daemon `LoadUsageHistory`
//! still owns transcript scanning. Native has no HTTP effect.
//!
//! Parse keeps entries with finite `input_cost_per_token` AND
//! `output_cost_per_token`; missing cache rates fall back to input.
//! Model names trim, lowercase, and strip the last `provider/` prefix.
//! Unpriceable names (`<synthetic>`, `synthetic`, `opus`, `sonnet`,
//! `haiku`, `fable`) never look up. Cap ~4096 models; extras drop.
//! Status: Fresh (just fetched), Cached (TTL hit or stale fallback
//! after a failed fetch), Unavailable (no usable table). Miss must
//! not toast-block Settings.

const std = @import("std");
const builtin = @import("builtin");
const native_sdk = @import("native_sdk");
const main = @import("main.zig");

const Model = main.Model;
const Effects = main.Effects;
const writeFixed = main.writeFixed;

pub const litellm_rates_key: u64 = 650;

pub const litellm_url =
    "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json";
pub const cache_name = "usage-model-rates.json";
pub const raw_name = "usage-model-rates.raw.json";
pub const ttl_ms: i64 = 24 * 3600 * 1000;
pub const max_models: usize = 4096;
pub const max_raw_bytes: usize = 16 * 1024 * 1024;
pub const max_cache_bytes: usize = 2 * 1024 * 1024;
pub const max_rates_path: usize = 768;
pub const accept_header = "Accept: application/json";

pub const unix_curl_bin = "/usr/bin/curl";
pub const path_curl_bin = "curl";
pub const windows_curl_bin = "curl.exe";

pub const status_fresh_label = "Rates fresh";
pub const status_cached_label = "Rates cached";
pub const status_unavailable_label = "Rates unavailable";

const unpriceable_models = [_][]const u8{
    "<synthetic>",
    "synthetic",
    "opus",
    "sonnet",
    "haiku",
    "fable",
};

const argv_len: usize = 7;

pub const Status = enum {
    fresh,
    cached,
    unavailable,
};

pub const Rate = struct {
    input: f64 = 0,
    output: f64 = 0,
    cache_read: f64 = 0,
    cache_creation: f64 = 0,
};

pub const Entry = struct {
    name: []u8 = &.{},
    rate: Rate = .{},
};

/// Runtime-only rate table. Heap entries; not sessions.json.
pub const Table = struct {
    allocator: std.mem.Allocator = std.heap.page_allocator,
    entries: []Entry = &.{},
    count: usize = 0,
    fetched_at_ms: i64 = 0,
    status: Status = .unavailable,

    pub fn deinit(self: *Table) void {
        const allocator = self.allocator;
        for (self.entries) |entry| {
            if (entry.name.len > 0) allocator.free(entry.name);
        }
        if (self.entries.len > 0) allocator.free(self.entries);
        self.entries = &.{};
        self.count = 0;
        self.fetched_at_ms = 0;
        self.status = .unavailable;
        self.allocator = allocator;
    }
};

pub fn curlBin() []const u8 {
    return switch (builtin.os.tag) {
        .windows => windows_curl_bin,
        else => unix_curl_bin,
    };
}

pub fn argvFor(raw_path: []const u8, buf: *[argv_len][]const u8) []const []const u8 {
    return argvForBin(curlBin(), raw_path, buf);
}

pub fn argvForBin(bin: []const u8, raw_path: []const u8, buf: *[argv_len][]const u8) []const []const u8 {
    buf[0] = bin;
    buf[1] = "-fsSL";
    buf[2] = "-H";
    buf[3] = accept_header;
    buf[4] = "-o";
    buf[5] = raw_path;
    buf[6] = litellm_url;
    return buf[0..7];
}

pub fn isCurlArgv(argv: []const []const u8) bool {
    if (argv.len != 7) return false;
    const bin_ok = std.mem.eql(u8, argv[0], unix_curl_bin) or
        std.mem.eql(u8, argv[0], path_curl_bin) or
        std.mem.eql(u8, argv[0], windows_curl_bin);
    if (!bin_ok) return false;
    if (!std.mem.eql(u8, argv[1], "-fsSL")) return false;
    if (!std.mem.eql(u8, argv[2], "-H")) return false;
    if (!std.mem.eql(u8, argv[3], accept_header)) return false;
    if (!std.mem.eql(u8, argv[4], "-o")) return false;
    if (argv[5].len == 0) return false;
    return std.mem.eql(u8, argv[6], litellm_url);
}

pub fn cachePath(dir: []const u8, buf: []u8) ?[]const u8 {
    return joinDirFile(dir, cache_name, buf);
}

pub fn rawPath(dir: []const u8, buf: []u8) ?[]const u8 {
    return joinDirFile(dir, raw_name, buf);
}

fn joinDirFile(dir: []const u8, name: []const u8, buf: []u8) ?[]const u8 {
    if (dir.len == 0) return null;
    return std.fmt.bufPrint(buf, "{s}{s}{s}", .{ dir, std.fs.path.sep_str, name }) catch null;
}

/// Trim, lowercase, strip the last `provider/` prefix. Dest must be
/// at least `model.len` bytes.
pub fn normalizeModelName(model: []const u8, dest: []u8) []const u8 {
    const trimmed = std.mem.trim(u8, model, " \t\r\n");
    if (trimmed.len > dest.len) return dest[0..0];
    var i: usize = 0;
    while (i < trimmed.len) : (i += 1) {
        dest[i] = std.ascii.toLower(trimmed[i]);
    }
    const lowered = dest[0..trimmed.len];
    if (std.mem.lastIndexOfScalar(u8, lowered, '/')) |slash| {
        return lowered[slash + 1 ..];
    }
    return lowered;
}

pub fn isUnpriceable(normalized: []const u8) bool {
    for (unpriceable_models) |name| {
        if (std.mem.eql(u8, normalized, name)) return true;
    }
    return false;
}

pub fn lookup(table: *const Table, model: []const u8) ?Rate {
    var name_buf: [256]u8 = undefined;
    const normalized = normalizeModelName(model, &name_buf);
    if (normalized.len == 0 or isUnpriceable(normalized)) return null;
    for (table.entries[0..table.count]) |entry| {
        if (std.mem.eql(u8, entry.name, normalized)) return entry.rate;
    }
    return null;
}

pub fn statusLabel(status: Status) []const u8 {
    return switch (status) {
        .fresh => status_fresh_label,
        .cached => status_cached_label,
        .unavailable => status_unavailable_label,
    };
}

/// Compact `$1.00/$2.00/MTok` from input/output per-token rates.
pub fn formatRateHint(buf: []u8, rate: Rate) ?[]const u8 {
    if (!std.math.isFinite(rate.input) or !std.math.isFinite(rate.output)) return null;
    const in_mtok = rate.input * 1_000_000.0;
    const out_mtok = rate.output * 1_000_000.0;
    if (!std.math.isFinite(in_mtok) or !std.math.isFinite(out_mtok)) return null;
    return std.fmt.bufPrint(buf, "${d:.2}/${d:.2}/MTok", .{ in_mtok, out_mtok }) catch null;
}

pub fn parseLiteLlmDocument(allocator: std.mem.Allocator, json: []const u8) Table {
    return parseLiteLlmDocumentCapped(allocator, json, max_models);
}

pub fn parseLiteLlmDocumentCapped(allocator: std.mem.Allocator, json: []const u8, cap: usize) Table {
    var table = Table{ .allocator = allocator };
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const root = std.json.parseFromSliceLeaky(std.json.Value, arena_state.allocator(), json, .{}) catch return table;
    const object = switch (root) {
        .object => |obj| obj,
        else => return table,
    };
    fillFromLiteLlmObject(&table, object, cap);
    return table;
}

fn fillFromLiteLlmObject(table: *Table, object: std.json.ObjectMap, cap: usize) void {
    var list: std.ArrayList(Entry) = .empty;
    var transferred = false;
    defer {
        if (!transferred) {
            for (list.items) |entry| {
                if (entry.name.len > 0) table.allocator.free(entry.name);
            }
            list.deinit(table.allocator);
        }
    }

    var it = object.iterator();
    while (it.next()) |kv| {
        const entry_obj = switch (kv.value_ptr.*) {
            .object => |obj| obj,
            else => continue,
        };
        const input = jsonFiniteF64(entry_obj.get("input_cost_per_token")) orelse continue;
        const output = jsonFiniteF64(entry_obj.get("output_cost_per_token")) orelse continue;
        var name_buf: [256]u8 = undefined;
        const normalized = normalizeModelName(kv.key_ptr.*, &name_buf);
        if (normalized.len == 0) continue;
        const cache_read = jsonFiniteF64(entry_obj.get("cache_read_input_token_cost")) orelse input;
        const cache_creation = jsonFiniteF64(entry_obj.get("cache_creation_input_token_cost")) orelse input;
        const rate = Rate{
            .input = input,
            .output = output,
            .cache_read = cache_read,
            .cache_creation = cache_creation,
        };
        if (findEntryIndex(list.items, normalized)) |index| {
            list.items[index].rate = rate;
            continue;
        }
        if (list.items.len >= cap) continue;
        const name = table.allocator.dupe(u8, normalized) catch continue;
        list.append(table.allocator, .{ .name = name, .rate = rate }) catch {
            table.allocator.free(name);
            continue;
        };
    }

    table.entries = list.toOwnedSlice(table.allocator) catch return;
    transferred = true;
    table.count = table.entries.len;
}

pub fn parseCompactCache(allocator: std.mem.Allocator, json: []const u8) Table {
    return parseCompactCacheCapped(allocator, json, max_models);
}

pub fn parseCompactCacheCapped(allocator: std.mem.Allocator, json: []const u8, cap: usize) Table {
    var table = Table{ .allocator = allocator };
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const root = std.json.parseFromSliceLeaky(std.json.Value, arena_state.allocator(), json, .{}) catch return table;
    const object = switch (root) {
        .object => |obj| obj,
        else => return table,
    };
    const fetched = jsonI64(object.get("fetched_at_ms")) orelse return table;
    const rates_value = object.get("rates") orelse return table;
    const rates_obj = switch (rates_value) {
        .object => |obj| obj,
        else => return table,
    };

    var list: std.ArrayList(Entry) = .empty;
    var transferred = false;
    defer {
        if (!transferred) {
            for (list.items) |entry| {
                if (entry.name.len > 0) table.allocator.free(entry.name);
            }
            list.deinit(table.allocator);
        }
    }

    var it = rates_obj.iterator();
    while (it.next()) |kv| {
        const values = switch (kv.value_ptr.*) {
            .array => |arr| arr,
            else => continue,
        };
        if (values.items.len < 4) continue;
        const input = jsonFiniteF64(values.items[0]) orelse continue;
        const output = jsonFiniteF64(values.items[1]) orelse continue;
        const cache_read = jsonFiniteF64(values.items[2]) orelse continue;
        const cache_creation = jsonFiniteF64(values.items[3]) orelse continue;
        if (kv.key_ptr.len == 0) continue;
        if (findEntryIndex(list.items, kv.key_ptr.*) != null) continue;
        if (list.items.len >= cap) continue;
        const name = table.allocator.dupe(u8, kv.key_ptr.*) catch continue;
        list.append(table.allocator, .{
            .name = name,
            .rate = .{
                .input = input,
                .output = output,
                .cache_read = cache_read,
                .cache_creation = cache_creation,
            },
        }) catch {
            table.allocator.free(name);
            continue;
        };
    }

    if (list.items.len == 0) return table;
    table.entries = list.toOwnedSlice(table.allocator) catch return table;
    transferred = true;
    table.count = table.entries.len;
    table.fetched_at_ms = fetched;
    return table;
}

fn findEntryIndex(entries: []const Entry, name: []const u8) ?usize {
    var i: usize = 0;
    while (i < entries.len) : (i += 1) {
        if (std.mem.eql(u8, entries[i].name, name)) return i;
    }
    return null;
}

pub fn writeCompactCache(allocator: std.mem.Allocator, io: std.Io, path: []const u8, table: *const Table) !void {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);
    try out.appendSlice(allocator, "{\"fetched_at_ms\":");
    try appendInt(&out, allocator, table.fetched_at_ms);
    try out.appendSlice(allocator, ",\"rates\":{");
    var i: usize = 0;
    while (i < table.count) : (i += 1) {
        if (i > 0) try out.append(allocator, ',');
        try appendJsonString(&out, allocator, table.entries[i].name);
        try out.append(allocator, ':');
        try out.append(allocator, '[');
        const rate = table.entries[i].rate;
        try appendFloat(&out, allocator, rate.input);
        try out.append(allocator, ',');
        try appendFloat(&out, allocator, rate.output);
        try out.append(allocator, ',');
        try appendFloat(&out, allocator, rate.cache_read);
        try out.append(allocator, ',');
        try appendFloat(&out, allocator, rate.cache_creation);
        try out.append(allocator, ']');
    }
    try out.appendSlice(allocator, "}}");
    try atomicWrite(io, path, out.items);
}

fn appendInt(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: i64) !void {
    var num: [24]u8 = undefined;
    const piece = std.fmt.bufPrint(&num, "{d}", .{value}) catch return error.NoSpaceLeft;
    try out.appendSlice(allocator, piece);
}

fn appendFloat(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: f64) !void {
    var num: [64]u8 = undefined;
    const piece = std.fmt.bufPrint(&num, "{d}", .{value}) catch return error.NoSpaceLeft;
    try out.appendSlice(allocator, piece);
}

fn appendJsonString(out: *std.ArrayList(u8), allocator: std.mem.Allocator, text: []const u8) !void {
    try out.append(allocator, '"');
    for (text) |c| {
        switch (c) {
            '"' => try out.appendSlice(allocator, "\\\""),
            '\\' => try out.appendSlice(allocator, "\\\\"),
            '\n' => try out.appendSlice(allocator, "\\n"),
            '\r' => try out.appendSlice(allocator, "\\r"),
            '\t' => try out.appendSlice(allocator, "\\t"),
            else => {
                if (c < 0x20) {
                    var hex: [6]u8 = undefined;
                    const piece = std.fmt.bufPrint(&hex, "\\u{x:0>4}", .{c}) catch return error.NoSpaceLeft;
                    try out.appendSlice(allocator, piece);
                } else {
                    try out.append(allocator, c);
                }
            },
        }
    }
    try out.append(allocator, '"');
}

fn atomicWrite(io: std.Io, path: []const u8, bytes: []const u8) !void {
    const cwd = std.Io.Dir.cwd();
    var atomic = try cwd.createFileAtomic(io, path, .{ .make_path = true, .replace = true });
    defer atomic.deinit(io);
    try atomic.file.writePositionalAll(io, bytes, 0);
    try atomic.file.sync(io);
    try atomic.replace(io);
}

fn jsonFiniteF64(value: ?std.json.Value) ?f64 {
    const item = value orelse return null;
    return switch (item) {
        .float => |f| if (std.math.isFinite(f)) f else null,
        .integer => |n| @floatFromInt(n),
        .number_string => |s| blk: {
            const parsed = std.fmt.parseFloat(f64, s) catch break :blk null;
            break :blk if (std.math.isFinite(parsed)) parsed else null;
        },
        else => null,
    };
}

fn jsonI64(value: ?std.json.Value) ?i64 {
    const item = value orelse return null;
    return switch (item) {
        .integer => |n| n,
        .float => |f| blk: {
            if (!std.math.isFinite(f)) break :blk null;
            if (f < @as(f64, @floatFromInt(std.math.minInt(i64)))) break :blk null;
            if (f > @as(f64, @floatFromInt(std.math.maxInt(i64)))) break :blk null;
            break :blk @intFromFloat(f);
        },
        else => null,
    };
}

fn cacheAgeMs(now_ms: i64, fetched_at_ms: i64) i64 {
    if (now_ms >= fetched_at_ms) return now_ms - fetched_at_ms;
    return 0;
}

fn cacheWithinTtl(now_ms: i64, fetched_at_ms: i64) bool {
    return cacheAgeMs(now_ms, fetched_at_ms) < ttl_ms;
}

fn readCompactFromDisk(model: *const Model) Table {
    const io = model.store_io orelse return .{};
    const dir = model.storeDir();
    var path_buf: [max_rates_path]u8 = undefined;
    const path = cachePath(dir, &path_buf) orelse return .{};
    const allocator = model.litellm_rates.allocator;
    const bytes = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(max_cache_bytes)) catch return .{};
    defer allocator.free(bytes);
    var table = parseCompactCache(allocator, bytes);
    if (table.count == 0) {
        table.deinit();
        return .{ .allocator = allocator };
    }
    return table;
}

fn adoptTable(model: *Model, table: Table, status: Status) void {
    const allocator = model.litellm_rates.allocator;
    var next = table;
    next.allocator = allocator;
    next.status = status;
    model.litellm_rates.deinit();
    model.litellm_rates = next;
}

fn loadDiskIntoModel(model: *Model, status: Status) bool {
    var table = readCompactFromDisk(model);
    if (table.count == 0) {
        table.deinit();
        return false;
    }
    adoptTable(model, table, status);
    return true;
}

fn markUnavailableIfEmpty(model: *Model) void {
    if (model.litellm_rates.count == 0) {
        model.litellm_rates.status = .unavailable;
        model.litellm_rates.fetched_at_ms = 0;
    }
}

/// Drop an in-flight curl. Safe when none is live. Keeps the runtime table.
pub fn cancel(model: *Model, fx: *Effects) void {
    if (!model.litellm_rates_live) return;
    fx.cancel(litellm_rates_key);
    model.litellm_rates_live = false;
}

/// Settings → Usage open / Refresh. TTL-fresh compact cache → Cached,
/// no spawn. Else curl (cancel/replace the same key). Missing data dir
/// / io stays Unavailable and does not toast.
pub fn ensure(model: *Model, fx: *Effects) void {
    const now_ms = model.now_ms;
    if (loadDiskIntoModel(model, .cached)) {
        if (cacheWithinTtl(now_ms, model.litellm_rates.fetched_at_ms)) {
            cancel(model, fx);
            model.litellm_rates.status = .cached;
            return;
        }
        model.litellm_rates.status = .cached;
    } else {
        markUnavailableIfEmpty(model);
    }
    spawnCurl(model, fx);
}

fn spawnCurl(model: *Model, fx: *Effects) void {
    const io = model.store_io orelse return;
    const dir = model.storeDir();
    if (dir.len == 0) return;
    std.Io.Dir.cwd().createDirPath(io, dir) catch {};
    var path_buf: [max_rates_path]u8 = undefined;
    const path = rawPath(dir, &path_buf) orelse return;
    writeFixed(&model.litellm_rates_raw_storage, &model.litellm_rates_raw_len, path);

    cancel(model, fx);
    model.litellm_rates_live = true;
    var argv_buf: [argv_len][]const u8 = undefined;
    fx.spawn(.{
        .key = litellm_rates_key,
        .argv = argvFor(model.litellm_rates_raw_storage[0..model.litellm_rates_raw_len], &argv_buf),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
}

pub fn handleExit(model: *Model, exit: native_sdk.EffectExit) void {
    if (exit.key != litellm_rates_key) return;
    if (!model.litellm_rates_live) return;
    if (exit.reason != .exited) return;
    model.litellm_rates_live = false;
    model.litellm_rates_settled = true;
    if (exit.code == 0 and adoptFromRaw(model)) {
        model.litellm_rates.status = .fresh;
        deleteRaw(model);
        return;
    }
    if (model.litellm_rates.count > 0) {
        model.litellm_rates.status = .cached;
        return;
    }
    if (loadDiskIntoModel(model, .cached)) return;
    markUnavailableIfEmpty(model);
}

fn adoptFromRaw(model: *Model) bool {
    const io = model.store_io orelse return false;
    const raw = model.litellm_rates_raw_storage[0..model.litellm_rates_raw_len];
    if (raw.len == 0) return false;
    const allocator = model.litellm_rates.allocator;
    const bytes = std.Io.Dir.cwd().readFileAlloc(io, raw, allocator, .limited(max_raw_bytes)) catch return false;
    defer allocator.free(bytes);
    var table = parseLiteLlmDocument(allocator, bytes);
    if (table.count == 0) {
        table.deinit();
        return false;
    }
    table.fetched_at_ms = model.now_ms;
    var path_buf: [max_rates_path]u8 = undefined;
    if (cachePath(model.storeDir(), &path_buf)) |path| {
        writeCompactCache(allocator, io, path, &table) catch {};
    }
    adoptTable(model, table, .fresh);
    return true;
}

fn deleteRaw(model: *Model) void {
    const io = model.store_io orelse return;
    const raw = model.litellm_rates_raw_storage[0..model.litellm_rates_raw_len];
    if (raw.len == 0) return;
    std.Io.Dir.cwd().deleteFile(io, raw) catch {};
}

fn pendingSpawnKey(fx: *Effects, key: u64) ?@TypeOf(fx.pendingSpawnAt(0).?) {
    var i: usize = 0;
    while (fx.pendingSpawnAt(i)) |spawn| : (i += 1) {
        if (spawn.key == key) return spawn;
    }
    return null;
}

fn testStoreDir(tmp: *const std.testing.TmpDir, buffer: []u8) ![]const u8 {
    return std.fmt.bufPrint(buffer, ".zig-cache/tmp/{s}/faku-rates", .{tmp.sub_path[0..]});
}

test "litellm_rates_key sits above cli_probe and is unused by OS sidecars" {
    try std.testing.expectEqual(@as(u64, 650), litellm_rates_key);
    try std.testing.expect(litellm_rates_key > main.cli_probe_key_first + 8);
    try std.testing.expect(litellm_rates_key != 25);
    try std.testing.expect(litellm_rates_key != 31);
}

test "normalize strips last provider prefix and lowercases" {
    var buf: [64]u8 = undefined;
    try std.testing.expectEqualStrings("claude-fable-5", normalizeModelName("anthropic/Claude-Fable-5", &buf));
    try std.testing.expectEqualStrings("gpt-5.3-codex", normalizeModelName("  gpt-5.3-codex ", &buf));
    try std.testing.expectEqualStrings("baz", normalizeModelName("foo/bar/Baz", &buf));
    try std.testing.expectEqualStrings("", normalizeModelName("   ", &buf));
}

test "lookup skips unpriceable names even when the table has them" {
    const testing = std.testing;
    const fixture =
        \\{"fable":{"input_cost_per_token":1e-6,"output_cost_per_token":2e-6},"claude-fable-5":{"input_cost_per_token":1e-6,"output_cost_per_token":2e-6,"cache_read_input_token_cost":1e-7,"cache_creation_input_token_cost":1.25e-6}}
    ;
    var table = parseLiteLlmDocument(testing.allocator, fixture);
    defer table.deinit();
    try testing.expect(lookup(&table, "Fable") == null);
    try testing.expect(lookup(&table, "<synthetic>") == null);
    try testing.expect(lookup(&table, "synthetic") == null);
    try testing.expect(lookup(&table, "opus") == null);
    try testing.expect(lookup(&table, "sonnet") == null);
    try testing.expect(lookup(&table, "haiku") == null);
    const hit = lookup(&table, "anthropic/claude-fable-5") orelse return error.MissingPricedModel;
    try testing.expectApproxEqAbs(@as(f64, 1e-6), hit.input, 1e-12);
    try testing.expectApproxEqAbs(@as(f64, 2e-6), hit.output, 1e-12);
}

test "parse drops half-priced models and defaults missing cache rates to input" {
    const testing = std.testing;
    const fixture =
        \\{
        \\  "claude-fable-5": {"input_cost_per_token": 1e-6, "output_cost_per_token": 2e-6,
        \\      "cache_read_input_token_cost": 1e-7, "cache_creation_input_token_cost": 1.25e-6},
        \\  "no-output-rate": {"input_cost_per_token": 1e-6},
        \\  "gpt-5.3-codex": {"input_cost_per_token": 3e-6, "output_cost_per_token": 9e-6}
        \\}
    ;
    var table = parseLiteLlmDocument(testing.allocator, fixture);
    defer table.deinit();
    try testing.expectEqual(@as(usize, 2), table.count);
    const fable = lookup(&table, "claude-fable-5") orelse return error.MissingFable;
    try testing.expectApproxEqAbs(@as(f64, 1e-7), fable.cache_read, 1e-12);
    try testing.expectApproxEqAbs(@as(f64, 1.25e-6), fable.cache_creation, 1e-12);
    const gpt = lookup(&table, "gpt-5.3-codex") orelse return error.MissingGpt;
    try testing.expectApproxEqAbs(@as(f64, 3e-6), gpt.cache_read, 1e-12);
    try testing.expectApproxEqAbs(@as(f64, 3e-6), gpt.cache_creation, 1e-12);
    try testing.expect(lookup(&table, "no-output-rate") == null);
}

test "parse cap drops extras rather than growing without bound" {
    const testing = std.testing;
    const fixture =
        \\{"a":{"input_cost_per_token":1,"output_cost_per_token":2},"b":{"input_cost_per_token":3,"output_cost_per_token":4},"c":{"input_cost_per_token":5,"output_cost_per_token":6}}
    ;
    var table = parseLiteLlmDocumentCapped(testing.allocator, fixture, 2);
    defer table.deinit();
    try testing.expectEqual(@as(usize, 2), table.count);
}

test "compact cache round-trips fetched_at_ms and four-field rates" {
    const testing = std.testing;
    const fixture =
        \\{"claude-fable-5":{"input_cost_per_token":1e-6,"output_cost_per_token":2e-6,"cache_read_input_token_cost":1e-7,"cache_creation_input_token_cost":1.25e-6}}
    ;
    var parsed = parseLiteLlmDocument(testing.allocator, fixture);
    defer parsed.deinit();
    parsed.fetched_at_ms = 12345;

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try testStoreDir(&tmp, &dir_buf);
    const io = testing.io;
    std.Io.Dir.cwd().createDirPath(io, dir) catch {};
    var path_buf: [max_rates_path]u8 = undefined;
    const path = cachePath(dir, &path_buf) orelse return error.MissingCachePath;
    try writeCompactCache(testing.allocator, io, path, &parsed);

    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, path, testing.allocator, .limited(max_cache_bytes));
    defer testing.allocator.free(bytes);
    var restored = parseCompactCache(testing.allocator, bytes);
    defer restored.deinit();
    try testing.expectEqual(@as(i64, 12345), restored.fetched_at_ms);
    try testing.expectEqual(@as(usize, 1), restored.count);
    const rate = lookup(&restored, "claude-fable-5") orelse return error.MissingRestored;
    try testing.expectApproxEqAbs(@as(f64, 1e-6), rate.input, 1e-12);
    try testing.expectApproxEqAbs(@as(f64, 2e-6), rate.output, 1e-12);
    try testing.expectApproxEqAbs(@as(f64, 1e-7), rate.cache_read, 1e-12);
    try testing.expectApproxEqAbs(@as(f64, 1.25e-6), rate.cache_creation, 1e-12);
}

test "TTL hit is Cached without curl; stale fetch success is Fresh" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try testStoreDir(&tmp, &dir_buf);
    const io = testing.io;
    std.Io.Dir.cwd().createDirPath(io, dir) catch {};

    const fixture =
        \\{"claude-fable-5":{"input_cost_per_token":1e-6,"output_cost_per_token":2e-6}}
    ;
    var parsed = parseLiteLlmDocument(testing.allocator, fixture);
    defer parsed.deinit();
    parsed.fetched_at_ms = 10_000;
    var path_buf: [max_rates_path]u8 = undefined;
    const path = cachePath(dir, &path_buf) orelse return error.MissingCachePath;
    try writeCompactCache(testing.allocator, io, path, &parsed);

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setStoreDir(dir);
    model.store_io = io;
    model.now_ms = 10_000 + ttl_ms - 1;
    defer model.litellm_rates.deinit();

    ensure(&model, &fx);
    try testing.expectEqual(Status.cached, model.litellm_rates.status);
    try testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
    try testing.expect(!model.litellm_rates_live);
    try testing.expect(lookup(&model.litellm_rates, "claude-fable-5") != null);

    model.now_ms = 10_000 + ttl_ms;
    ensure(&model, &fx);
    try testing.expectEqual(Status.cached, model.litellm_rates.status);
    const spawn = pendingSpawnKey(&fx, litellm_rates_key) orelse return error.MissingStaleCurl;
    try testing.expect(isCurlArgv(spawn.argv));
    try testing.expectEqual(litellm_rates_key, spawn.key);
    try testing.expectEqualStrings("", spawn.stdin);
    try testing.expect(model.litellm_rates_live);

    const raw = model.litellm_rates_raw_storage[0..model.litellm_rates_raw_len];
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = raw, .data = fixture });
    handleExit(&model, .{ .key = litellm_rates_key, .reason = .exited, .code = 0 });
    try testing.expectEqual(Status.fresh, model.litellm_rates.status);
    try testing.expectEqual(model.now_ms, model.litellm_rates.fetched_at_ms);
    try testing.expect(!model.litellm_rates_live);
}

test "failed fetch keeps stale Cached; empty miss is Unavailable" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try testStoreDir(&tmp, &dir_buf);
    const io = testing.io;
    std.Io.Dir.cwd().createDirPath(io, dir) catch {};

    const fixture =
        \\{"claude-fable-5":{"input_cost_per_token":1e-6,"output_cost_per_token":2e-6}}
    ;
    var parsed = parseLiteLlmDocument(testing.allocator, fixture);
    defer parsed.deinit();
    parsed.fetched_at_ms = 1;
    var path_buf: [max_rates_path]u8 = undefined;
    const path = cachePath(dir, &path_buf) orelse return error.MissingCachePath;
    try writeCompactCache(testing.allocator, io, path, &parsed);

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.setStoreDir(dir);
    model.store_io = io;
    model.now_ms = 1 + ttl_ms + 1;
    defer model.litellm_rates.deinit();

    ensure(&model, &fx);
    try testing.expect(model.litellm_rates_live);
    handleExit(&model, .{ .key = litellm_rates_key, .reason = .exited, .code = 22 });
    try testing.expectEqual(Status.cached, model.litellm_rates.status);
    try testing.expect(lookup(&model.litellm_rates, "claude-fable-5") != null);

    var empty = Model{};
    empty.setStoreDir(dir);
    empty.store_io = io;
    empty.now_ms = 1 + ttl_ms + 1;
    std.Io.Dir.cwd().deleteFile(io, path) catch {};
    defer empty.litellm_rates.deinit();
    ensure(&empty, &fx);
    try testing.expectEqual(Status.unavailable, empty.litellm_rates.status);
    handleExit(&empty, .{ .key = litellm_rates_key, .reason = .exited, .code = 22 });
    try testing.expectEqual(Status.unavailable, empty.litellm_rates.status);
    try testing.expectEqual(@as(usize, 0), empty.litellm_rates.count);
}

test "ensure without a data dir does not spawn and stays Unavailable" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.now_ms = 10_000;
    ensure(&model, &fx);
    try std.testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
    try std.testing.expectEqual(Status.unavailable, model.litellm_rates.status);
    try std.testing.expect(!model.litellm_rates_live);
}

test "formatRateHint is compact per-MTok" {
    var buf: [32]u8 = undefined;
    const text = formatRateHint(&buf, .{ .input = 1e-6, .output = 2e-6 }) orelse return error.MissingHint;
    try std.testing.expectEqualStrings("$1.00/$2.00/MTok", text);
}
