//! OpenCode 2 first-cut HTTP Send against a user-owned serve.
//!
//! When OpenCode 2 is Available and persisted `opencode2_attach_url`
//! trim is non-empty, Send uses one-shot curl POST
//! `{attach_url}/session` (when `fx_session_id` is empty) then
//! `{attach_url}/session/{id}/message` (https://opencode.ai/docs/server/;
//! OpenAPI Session `id` and `{ info, parts: Part[] }`). Blocking wait
//! for the full `/message` response — no SSE `/global/event`, no
//! `text_delta` streaming. Faku does not spawn `opencode2 serve`.
//! Basic auth matches Check serve: curl `-u {user}:{password}` when
//! `opencode2_server_password` is set (`{user}` persist or default
//! `opencode`); empty password omits `-u`. Composer image/file is
//! omitted this cut (no undocumented FilePart upload). Empty attach
//! URL keeps CLI `run --format json --auto`. Tests inject spawn/effect;
//! no live serve.

const std = @import("std");
const native_sdk = @import("native_sdk");
const main = @import("main.zig");
const model_exports = @import("model_exports.zig");
const providers = @import("providers.zig");
const litellm_rates = @import("litellm_rates.zig");
const store = @import("store.zig");
const git_commit_generate = @import("git_commit_generate.zig");

const Model = model_exports.Model;
const Effects = main.Effects;
const Session = model_exports.Session;
const writeFixed = model_exports.writeFixed;

pub const session_path = "/session";
pub const message_path_suffix = "/message";
pub const max_time = "300";
pub const max_filesize = "65536";
pub const content_type_header = "Content-Type: application/json";
pub const accept_header = providers.opencode2_health_accept_header;
pub const argv_len: usize = 15;
pub const argv_len_plain: usize = 13;
pub const json_max: usize = 16 * 1024;
pub const body_max: usize = 64 * 1024;
pub const url_max: usize = model_exports.max_opencode2_attach_url + session_path.len + 1 + model_exports.max_fx_session_id + message_path_suffix.len;
pub const userpass_max: usize = providers.opencode2_health_userpass_max;

pub const ExitAction = enum { none, spawn_message, finish_ok, finish_fail };

const WriteError = error{NoSpaceLeft};

const Cursor = struct {
    buf: []u8,
    pos: usize = 0,

    fn write(self: *Cursor, bytes: []const u8) WriteError!void {
        if (self.pos + bytes.len > self.buf.len) return error.NoSpaceLeft;
        @memcpy(self.buf[self.pos..][0..bytes.len], bytes);
        self.pos += bytes.len;
    }

    fn slice(self: *const Cursor) []const u8 {
        return self.buf[0..self.pos];
    }
};

fn writeJsonString(cur: *Cursor, text: []const u8) WriteError!void {
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

/// Join `path` (must start with `/`) onto the serve base. Trailing
/// slash on the base does not double-slash.
pub fn joinUrl(attach: []const u8, path: []const u8, buf: []u8) []const u8 {
    const trimmed = std.mem.trim(u8, attach, " \t\r\n");
    if (trimmed.len == 0 or path.len == 0 or path[0] != '/') return "";
    const base = std.mem.trimEnd(u8, trimmed, "/");
    if (base.len == 0) return "";
    return std.fmt.bufPrint(buf, "{s}{s}", .{ base, path }) catch "";
}

pub fn sessionUrl(attach: []const u8, buf: []u8) []const u8 {
    return joinUrl(attach, session_path, buf);
}

pub fn messageUrl(attach: []const u8, session_id: []const u8, buf: []u8) []const u8 {
    const trimmed_id = std.mem.trim(u8, session_id, " \t\r\n");
    if (trimmed_id.len == 0) return "";
    var path_buf: [session_path.len + 1 + model_exports.max_fx_session_id + message_path_suffix.len]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "{s}/{s}{s}", .{ session_path, trimmed_id, message_path_suffix }) catch return "";
    return joinUrl(attach, path, buf);
}

/// Safe `provider/model` split from the stored session model. First
/// `/` only; both sides non-empty. Otherwise omit `model` and let
/// the server default — do not invent provider IDs.
pub fn splitProviderModel(model_id: []const u8) ?struct { provider_id: []const u8, model_id: []const u8 } {
    const trimmed = std.mem.trim(u8, model_id, " \t\r\n");
    const slash = std.mem.indexOfScalar(u8, trimmed, '/') orelse return null;
    if (slash == 0 or slash + 1 >= trimmed.len) return null;
    const provider_id = trimmed[0..slash];
    const rest = trimmed[slash + 1 ..];
    if (provider_id.len == 0 or rest.len == 0) return null;
    return .{ .provider_id = provider_id, .model_id = rest };
}

pub fn writeCreateJson(title: []const u8, buf: []u8) []const u8 {
    const trimmed = std.mem.trim(u8, title, " \t\r\n");
    if (trimmed.len == 0) {
        if (buf.len < 2) return "";
        buf[0] = '{';
        buf[1] = '}';
        return buf[0..2];
    }
    var cur = Cursor{ .buf = buf };
    cur.write("{\"title\":") catch return "";
    writeJsonString(&cur, trimmed) catch return "";
    cur.write("}") catch return "";
    return cur.slice();
}

pub fn writeMessageJson(prompt: []const u8, model_id: []const u8, buf: []u8) []const u8 {
    var cur = Cursor{ .buf = buf };
    cur.write("{\"parts\":[{\"type\":\"text\",\"text\":") catch return "";
    writeJsonString(&cur, prompt) catch return "";
    cur.write("}]") catch return "";
    if (splitProviderModel(model_id)) |pair| {
        cur.write(",\"model\":{\"providerID\":") catch return "";
        writeJsonString(&cur, pair.provider_id) catch return "";
        cur.write(",\"modelID\":") catch return "";
        writeJsonString(&cur, pair.model_id) catch return "";
        cur.write("}") catch return "";
    }
    cur.write("}") catch return "";
    return cur.slice();
}

pub fn argvForPost(bin: []const u8, url: []const u8, json: []const u8, userpass: []const u8, argv_buf: *[argv_len][]const u8) []const []const u8 {
    argv_buf[0] = bin;
    argv_buf[1] = "-fsSL";
    argv_buf[2] = "--max-time";
    argv_buf[3] = max_time;
    argv_buf[4] = "--max-filesize";
    argv_buf[5] = max_filesize;
    var n: usize = 6;
    if (userpass.len > 0) {
        argv_buf[n] = "-u";
        n += 1;
        argv_buf[n] = userpass;
        n += 1;
    }
    argv_buf[n] = "-H";
    n += 1;
    argv_buf[n] = content_type_header;
    n += 1;
    argv_buf[n] = "-H";
    n += 1;
    argv_buf[n] = accept_header;
    n += 1;
    argv_buf[n] = "-d";
    n += 1;
    argv_buf[n] = json;
    n += 1;
    argv_buf[n] = url;
    n += 1;
    return argv_buf[0..n];
}

pub fn isHttpArgv(argv: []const []const u8) bool {
    if (argv.len != argv_len_plain and argv.len != argv_len) return false;
    const bin_ok = std.mem.eql(u8, argv[0], litellm_rates.unix_curl_bin) or
        std.mem.eql(u8, argv[0], litellm_rates.path_curl_bin) or
        std.mem.eql(u8, argv[0], litellm_rates.windows_curl_bin);
    if (!bin_ok) return false;
    if (!std.mem.eql(u8, argv[1], "-fsSL")) return false;
    if (!std.mem.eql(u8, argv[2], "--max-time")) return false;
    if (!std.mem.eql(u8, argv[3], max_time)) return false;
    if (!std.mem.eql(u8, argv[4], "--max-filesize")) return false;
    if (!std.mem.eql(u8, argv[5], max_filesize)) return false;
    var i: usize = 6;
    if (argv.len == argv_len) {
        if (!std.mem.eql(u8, argv[i], "-u")) return false;
        const colon = std.mem.indexOfScalar(u8, argv[i + 1], ':') orelse return false;
        if (colon == 0 or colon + 1 >= argv[i + 1].len) return false;
        i += 2;
    }
    if (!std.mem.eql(u8, argv[i], "-H")) return false;
    if (!std.mem.eql(u8, argv[i + 1], content_type_header)) return false;
    if (!std.mem.eql(u8, argv[i + 2], "-H")) return false;
    if (!std.mem.eql(u8, argv[i + 3], accept_header)) return false;
    if (!std.mem.eql(u8, argv[i + 4], "-d")) return false;
    if (argv[i + 5].len == 0) return false;
    return argv[i + 6].len > 0;
}

pub fn parseSessionId(json: []const u8, dest: []u8) []const u8 {
    const trimmed = std.mem.trim(u8, json, " \t\r\n");
    if (trimmed.len < 2 or trimmed[0] != '{') return "";
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const root = std.json.parseFromSliceLeaky(std.json.Value, arena_state.allocator(), trimmed, .{}) catch return "";
    if (root != .object) return "";
    const raw = root.object.get("id") orelse return "";
    const id = switch (raw) {
        .string => |s| std.mem.trim(u8, s, " \t\r\n"),
        else => return "",
    };
    if (id.len == 0) return "";
    const take = @min(dest.len, id.len);
    @memcpy(dest[0..take], id[0..take]);
    return dest[0..take];
}

pub fn collectTextParts(json: []const u8, dest: []u8) []const u8 {
    const trimmed = std.mem.trim(u8, json, " \t\r\n");
    if (trimmed.len < 2 or trimmed[0] != '{') return "";
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const root = std.json.parseFromSliceLeaky(std.json.Value, arena_state.allocator(), trimmed, .{}) catch return "";
    if (root != .object) return "";
    const parts_val = root.object.get("parts") orelse return "";
    const parts = switch (parts_val) {
        .array => |a| a.items,
        else => return "",
    };
    var n: usize = 0;
    for (parts) |item| {
        if (item != .object) continue;
        const type_raw = item.object.get("type") orelse continue;
        const type_str = switch (type_raw) {
            .string => |s| s,
            else => continue,
        };
        if (!std.mem.eql(u8, type_str, "text")) continue;
        const text_raw = item.object.get("text") orelse continue;
        const text = switch (text_raw) {
            .string => |s| s,
            else => continue,
        };
        if (text.len == 0) continue;
        const room = dest.len - n;
        if (room == 0) break;
        const take = @min(room, text.len);
        @memcpy(dest[n .. n + take], text[0..take]);
        n += take;
    }
    return dest[0..n];
}

fn storeUserpass(model: *Model) void {
    const password = model.opencode2ServerPassword();
    if (password.len == 0) {
        model.opencode2_http_userpass_len = 0;
        return;
    }
    var buf: [userpass_max]u8 = undefined;
    const userpass = std.fmt.bufPrint(&buf, "{s}:{s}", .{ providers.opencode2HealthUsername(model), password }) catch {
        model.opencode2_http_userpass_len = 0;
        return;
    };
    writeFixed(&model.opencode2_http_userpass_storage, &model.opencode2_http_userpass_len, userpass);
}

fn spawnCurl(model: *Model, fx: *Effects, key: u64) bool {
    const url = model.opencode2_http_url_storage[0..model.opencode2_http_url_len];
    const json = model.opencode2_http_json_storage[0..model.opencode2_http_json_len];
    if (url.len == 0 or json.len == 0) return false;
    var argv_buf: [argv_len][]const u8 = undefined;
    const argv = argvForPost(
        litellm_rates.curlBin(),
        url,
        json,
        model.opencode2_http_userpass_storage[0..model.opencode2_http_userpass_len],
        &argv_buf,
    );
    if (argv.len > git_commit_generate.max_effect_argv) return false;
    model.opencode2_http_body_len = 0;
    model.fx_spawn_opencode_http = true;
    model.fx_spawn_opencode_run_json = false;
    fx.spawn(.{
        .key = key,
        .argv = argv,
        .stdin = "",
        .max_line_bytes = body_max,
        .on_line = Effects.lineMsg(.fx_line),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
    return true;
}

fn prepareCreate(model: *Model, session: *const Session) bool {
    var url_buf: [url_max]u8 = undefined;
    const url = sessionUrl(model.opencode2AttachUrl(), &url_buf);
    if (url.len == 0) return false;
    var json_buf: [json_max]u8 = undefined;
    const json = writeCreateJson(session.title(), &json_buf);
    if (json.len == 0) return false;
    writeFixed(&model.opencode2_http_url_storage, &model.opencode2_http_url_len, url);
    writeFixed(&model.opencode2_http_json_storage, &model.opencode2_http_json_len, json);
    model.fx_spawn_opencode_http_create = true;
    return true;
}

fn prepareMessage(model: *Model, session: *const Session) bool {
    var url_buf: [url_max]u8 = undefined;
    const url = messageUrl(model.opencode2AttachUrl(), session.fxSessionId(), &url_buf);
    if (url.len == 0) return false;
    const prompt = model.opencode2_http_prompt_storage[0..model.opencode2_http_prompt_len];
    var json_buf: [json_max]u8 = undefined;
    const json = writeMessageJson(prompt, session.model(), &json_buf);
    if (json.len == 0) return false;
    writeFixed(&model.opencode2_http_url_storage, &model.opencode2_http_url_len, url);
    writeFixed(&model.opencode2_http_json_storage, &model.opencode2_http_json_len, json);
    model.fx_spawn_opencode_http_create = false;
    return true;
}

/// First-cut HTTP Send. Caller supplies a Native spawn key
/// (`allocateFxSpawnKey`). Composer image/file is omitted. Returns
/// false so Send fail-closes to demo.
pub fn start(model: *Model, fx: *Effects, session: *const Session, prompt: []const u8, key: u64) bool {
    if (model.opencode2AttachUrl().len == 0) return false;
    writeFixed(&model.opencode2_http_prompt_storage, &model.opencode2_http_prompt_len, prompt);
    storeUserpass(model);
    const ready = if (session.fxSessionId().len == 0)
        prepareCreate(model, session)
    else
        prepareMessage(model, session);
    if (!ready) {
        clear(model);
        return false;
    }
    if (!spawnCurl(model, fx, key)) {
        clear(model);
        return false;
    }
    return true;
}

/// Second sequential spawn after POST /session captured `id`.
pub fn continueMessage(model: *Model, fx: *Effects, key: u64) bool {
    const session = model.sessionById(model.streaming_session) orelse return false;
    if (!prepareMessage(model, session)) return false;
    return spawnCurl(model, fx, key);
}

pub fn clear(model: *Model) void {
    model.fx_spawn_opencode_http = false;
    model.fx_spawn_opencode_http_create = false;
    model.opencode2_http_url_len = 0;
    model.opencode2_http_userpass_len = 0;
    model.opencode2_http_json_len = 0;
    model.opencode2_http_body_len = 0;
    model.opencode2_http_prompt_len = 0;
}

pub fn applyLine(model: *Model, line: native_sdk.EffectLine) void {
    if (!model.fx_spawn_opencode_http) return;
    if (model.fx_spawn_key != 0 and line.key != model.fx_spawn_key) return;
    const chunk = line.line;
    if (std.mem.indexOfScalar(u8, chunk, 0) != null) {
        model.opencode2_http_body_len = 0;
        return;
    }
    if (model.opencode2_http_body_len >= body_max) return;
    if (model.opencode2_http_body_len > 0) {
        model.opencode2_http_body_storage[model.opencode2_http_body_len] = '\n';
        model.opencode2_http_body_len += 1;
        if (model.opencode2_http_body_len >= body_max) return;
    }
    const room = body_max - model.opencode2_http_body_len;
    const take = @min(room, chunk.len);
    @memcpy(model.opencode2_http_body_storage[model.opencode2_http_body_len .. model.opencode2_http_body_len + take], chunk[0..take]);
    model.opencode2_http_body_len += take;
}

pub fn handleExit(model: *Model, fx: *Effects, exit: native_sdk.EffectExit) ExitAction {
    if (!model.fx_spawn_opencode_http) return .none;
    model.fx_spawn_live = false;
    if (exit.key == model.fx_spawn_key) model.fx_spawn_key = 0;
    const creating = model.fx_spawn_opencode_http_create;
    var body_copy: [body_max]u8 = undefined;
    const body_len = @min(model.opencode2_http_body_len, body_copy.len);
    @memcpy(body_copy[0..body_len], model.opencode2_http_body_storage[0..body_len]);
    model.opencode2_http_body_len = 0;
    if (model.phase != .streaming) {
        clear(model);
        return .none;
    }
    const ok = exit.reason == .exited and exit.code == 0;
    if (creating) {
        if (!ok) {
            clear(model);
            return .finish_fail;
        }
        var id_buf: [model_exports.max_fx_session_id]u8 = undefined;
        const session_id = parseSessionId(body_copy[0..body_len], &id_buf);
        if (session_id.len == 0) {
            clear(model);
            return .finish_fail;
        }
        if (model.sessionById(model.streaming_session)) |session| {
            session.setFxSessionId(session_id);
            store.persistIfPossible(model, session.id, fx);
        }
        model.fx_spawn_opencode_http_create = false;
        return .spawn_message;
    }
    if (ok) {
        var text_buf: [model_exports.max_body]u8 = undefined;
        const text = collectTextParts(body_copy[0..body_len], &text_buf);
        if (text.len > 0) model.appendToTurn(model.stream_turn_id, text);
    }
    clear(model);
    return if (ok) .finish_ok else .finish_fail;
}

test "joinUrl trims slash; session and message paths match docs" {
    const testing = std.testing;
    var buf: [url_max]u8 = undefined;
    try testing.expectEqualStrings("", joinUrl("", session_path, &buf));
    try testing.expectEqualStrings(
        "http://localhost:4096/session",
        sessionUrl("http://localhost:4096", &buf),
    );
    try testing.expectEqualStrings(
        "http://localhost:4096/session",
        sessionUrl("http://localhost:4096/", &buf),
    );
    try testing.expectEqualStrings(
        "http://localhost:4096/session/ses_1/message",
        messageUrl("http://localhost:4096", "ses_1", &buf),
    );
    try testing.expectEqualStrings("", messageUrl("http://localhost:4096", "", &buf));
}

test "splitProviderModel maps provider/model; omits unsafe strings" {
    const testing = std.testing;
    const ok = splitProviderModel("anthropic/claude-sonnet-4").?;
    try testing.expectEqualStrings("anthropic", ok.provider_id);
    try testing.expectEqualStrings("claude-sonnet-4", ok.model_id);
    const nested = splitProviderModel("opencode/gpt-5").?;
    try testing.expectEqualStrings("opencode", nested.provider_id);
    try testing.expectEqualStrings("gpt-5", nested.model_id);
    try testing.expect(splitProviderModel("") == null);
    try testing.expect(splitProviderModel("claude-sonnet-4") == null);
    try testing.expect(splitProviderModel("/model") == null);
    try testing.expect(splitProviderModel("provider/") == null);
}

test "writeCreateJson and writeMessageJson documented shapes" {
    const testing = std.testing;
    var buf: [json_max]u8 = undefined;
    try testing.expectEqualStrings("{}", writeCreateJson("", &buf));
    try testing.expectEqualStrings("{\"title\":\"hello\"}", writeCreateJson("hello", &buf));
    try testing.expectEqualStrings(
        "{\"parts\":[{\"type\":\"text\",\"text\":\"hi\"}]}",
        writeMessageJson("hi", "", &buf),
    );
    try testing.expectEqualStrings(
        "{\"parts\":[{\"type\":\"text\",\"text\":\"hi\"}],\"model\":{\"providerID\":\"anthropic\",\"modelID\":\"claude-sonnet-4\"}}",
        writeMessageJson("hi", "anthropic/claude-sonnet-4", &buf),
    );
    try testing.expectEqualStrings(
        "{\"parts\":[{\"type\":\"text\",\"text\":\"hi\"}]}",
        writeMessageJson("hi", "claude-sonnet-4", &buf),
    );
    try testing.expectEqualStrings(
        "{\"parts\":[{\"type\":\"text\",\"text\":\"say \\\"hi\\\"\"}]}",
        writeMessageJson("say \"hi\"", "", &buf),
    );
}

test "argvForPost is curl POST; -u when userpass set; fits Native 16" {
    const testing = std.testing;
    var argv_buf: [argv_len][]const u8 = undefined;
    const plain = argvForPost(litellm_rates.unix_curl_bin, "http://127.0.0.1:4096/session", "{}", "", &argv_buf);
    try testing.expectEqual(@as(usize, argv_len_plain), plain.len);
    try testing.expect(plain.len <= git_commit_generate.max_effect_argv);
    try testing.expect(isHttpArgv(plain));
    try testing.expectEqualStrings("-d", plain[10]);
    try testing.expectEqualStrings("{}", plain[11]);
    try testing.expectEqualStrings("http://127.0.0.1:4096/session", plain[12]);
    try testing.expect(!std.mem.eql(u8, plain[0], "opencode2"));

    const auth = argvForPost(litellm_rates.unix_curl_bin, "http://127.0.0.1:4096/session/ses/message", "{\"parts\":[]}", "alice:pw", &argv_buf);
    try testing.expectEqual(@as(usize, argv_len), auth.len);
    try testing.expect(auth.len <= git_commit_generate.max_effect_argv);
    try testing.expect(isHttpArgv(auth));
    try testing.expectEqualStrings("-u", auth[6]);
    try testing.expectEqualStrings("alice:pw", auth[7]);
}

test "parseSessionId reads Session.id; collectTextParts walks type text" {
    const testing = std.testing;
    var id_buf: [model_exports.max_fx_session_id]u8 = undefined;
    try testing.expectEqualStrings(
        "ses_abc",
        parseSessionId("{\"id\":\"ses_abc\",\"title\":\"t\",\"projectID\":\"p\",\"directory\":\"/\",\"version\":\"1\",\"time\":{\"created\":1,\"updated\":1}}", &id_buf),
    );
    try testing.expectEqualStrings("", parseSessionId("{\"title\":\"no id\"}", &id_buf));
    try testing.expectEqualStrings("", parseSessionId("not json", &id_buf));

    var text_buf: [model_exports.max_body]u8 = undefined;
    try testing.expectEqualStrings(
        "hello from serve",
        collectTextParts("{\"info\":{\"id\":\"m1\",\"role\":\"assistant\"},\"parts\":[{\"type\":\"text\",\"text\":\"hello from serve\"}]}", &text_buf),
    );
    try testing.expectEqualStrings(
        "ab",
        collectTextParts("{\"info\":{},\"parts\":[{\"type\":\"text\",\"text\":\"a\"},{\"type\":\"reasoning\",\"text\":\"nope\"},{\"type\":\"text\",\"text\":\"b\"}]}", &text_buf),
    );
    try testing.expectEqualStrings("", collectTextParts("{\"info\":{},\"parts\":[{\"type\":\"tool\"}]}", &text_buf));
}
