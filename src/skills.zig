//! Settings Skills + composer `$` insert: bounded `SKILL.md` scan.
//!
//! Native has no FS watcher. Faku one-shots a packed `find` for
//! `SKILL.md` through the same `/bin/sh -c` chdir workaround `fx ask`
//! uses (`fx_ask_chdir_script`). Settings → Skills still `refresh`s on
//! page open. Composer `$` calls `ensureScanned` even when
//! `settings_page != .skills`. Scan root is the selected session
//! `project_path` when that directory exists, else settings
//! `last_project_path`. Skip `node_modules` / `target` / `dist` /
//! `build` / `out` / `vendor` / `__pycache__`. Cap 64 rows. Name comes
//! from YAML `name:` frontmatter when present, else the parent folder.
//! Settings selecting a row shows the body with frontmatter stripped.
//! Composer `$` inserts `$name ` into the draft; Send still ships that
//! composer text as-is (fx loads the skill). Runtime-only (not
//! `sessions.json`). Not SKILL.md body stuffing, not enable/disable,
//! not a daemon SkillsCatalog / WorkspaceOperation, not ACP `/name`
//! slash rows. Windows stays empty this cut.
//!
//! Spawn/line/exit orchestration lives here. Tests do not need a live
//! daemon or fx.

const std = @import("std");
const builtin = @import("builtin");
const native_sdk = @import("native_sdk");
const main = @import("main.zig");
const file_mention = @import("file_mention.zig");

const Model = main.Model;
const Effects = main.Effects;
const writeFixed = main.writeFixed;

/// One-shot Skills `find` for `SKILL.md`. Distinct from review hunk
/// (520+). Band is 530+. Incremented per scan so a cancelled spawn
/// cannot paint a later Settings open.
pub const skills_key_first: u64 = 530;

pub const max_skills: usize = 64;
pub const max_skill_path: usize = 255;
pub const max_skill_name: usize = 64;
pub const max_skill_body: usize = 4096;
pub const max_skill_file_read: usize = 8192;

pub const skill_filename = "SKILL.md";
pub const skill_fallback_name = "SKILL";

pub const sh_bin = file_mention.sh_bin;
pub const find_bin = file_mention.find_bin;
pub const find_maxdepth_flag = file_mention.find_maxdepth_flag;
pub const find_maxdepth = file_mention.find_maxdepth;
pub const find_prune = file_mention.find_prune;
pub const find_type_file = file_mention.find_type_file;
pub const find_name_flag = "-name";

pub const walk_skip_node_modules = file_mention.walk_skip_node_modules;
pub const walk_skip_target = file_mention.walk_skip_target;
pub const walk_skip_dist = file_mention.walk_skip_dist;
pub const walk_skip_build = file_mention.walk_skip_build;
pub const walk_skip_out = file_mention.walk_skip_out;
pub const walk_skip_vendor = file_mention.walk_skip_vendor;
pub const walk_skip_pycache = file_mention.walk_skip_pycache;
pub const walk_skip_names = file_mention.walk_skip_names;

/// Packed into one `-c` string so the spawn stays under Native
/// `max_effect_argv` (16). Does not prune `.*` — project skills live
/// under `.cursor/skills` / `.agents/skills`.
pub const find_skills_script =
    "find . -maxdepth 8 \\( -name node_modules -o -name target -o -name dist -o -name build -o -name out -o -name vendor -o -name __pycache__ \\) -prune -o -type f -name SKILL.md -print";

const walk_argv_len: usize = 8;

pub const Page = enum { general, skills };

pub const CachedSkill = struct {
    path_storage: [max_skill_path]u8 = [_]u8{0} ** max_skill_path,
    path_len: usize = 0,
    name_storage: [max_skill_name]u8 = [_]u8{0} ** max_skill_name,
    name_len: usize = 0,

    pub fn path(self: *const CachedSkill) []const u8 {
        return self.path_storage[0..self.path_len];
    }

    pub fn name(self: *const CachedSkill) []const u8 {
        return self.name_storage[0..self.name_len];
    }

    pub fn setPath(self: *CachedSkill, value: []const u8) void {
        writeFixed(&self.path_storage, &self.path_len, value);
    }

    pub fn setName(self: *CachedSkill, value: []const u8) void {
        writeFixed(&self.name_storage, &self.name_len, value);
    }
};

pub fn argvFor(cwd: []const u8, buf: *[walk_argv_len][]const u8) []const []const u8 {
    buf.* = .{
        sh_bin,
        "-c",
        main.fx_ask_chdir_script,
        "sh",
        cwd,
        sh_bin,
        "-c",
        find_skills_script,
    };
    return buf;
}

fn scriptHas(script: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, script, needle) != null;
}

pub fn isSkillsWalkArgv(argv: []const []const u8) bool {
    if (argv.len != walk_argv_len) return false;
    if (!std.mem.eql(u8, argv[0], sh_bin)) return false;
    if (!std.mem.eql(u8, argv[1], "-c")) return false;
    if (!std.mem.eql(u8, argv[2], main.fx_ask_chdir_script)) return false;
    if (!std.mem.eql(u8, argv[5], sh_bin)) return false;
    if (!std.mem.eql(u8, argv[6], "-c")) return false;
    if (!std.mem.eql(u8, argv[7], find_skills_script)) return false;
    if (!scriptHas(argv[7], find_maxdepth_flag)) return false;
    if (!scriptHas(argv[7], find_maxdepth)) return false;
    if (!scriptHas(argv[7], find_prune)) return false;
    if (!scriptHas(argv[7], find_type_file)) return false;
    if (!scriptHas(argv[7], find_name_flag)) return false;
    if (!scriptHas(argv[7], skill_filename)) return false;
    inline for (walk_skip_names) |name| {
        if (!scriptHas(argv[7], name)) return false;
    }
    return true;
}

pub fn scanSupported() bool {
    return builtin.os.tag != .windows;
}

pub fn cachedCount(model: *const Model) u32 {
    return model.skill_count;
}

pub fn cachedPath(model: *const Model, index: usize) []const u8 {
    if (index >= model.skill_count) return "";
    return model.skill_store[index].path();
}

pub fn cachedName(model: *const Model, index: usize) []const u8 {
    if (index >= model.skill_count) return "";
    return model.skill_store[index].name();
}

pub fn skillId(index: usize) u32 {
    return @intCast(index + 1);
}

pub fn clearCache(model: *Model) void {
    model.skill_count = 0;
    model.skill_selected_id = 0;
    model.skill_body_len = 0;
}

fn cancelInFlight(model: *Model, fx: *Effects) void {
    if (model.skill_key == 0) return;
    fx.cancel(model.skill_key);
    model.skill_key = 0;
}

/// Selected-session directory when it exists, else settings last
/// project path. Empty / missing stays empty so Skills does not
/// invent a project.
pub fn probePath(model: *const Model) []const u8 {
    const io = model.store_io orelse return "";
    const selected = model.selectedProjectPath();
    if (selected.len > 0 and main.directoryExists(io, selected)) return selected;
    const last = model.lastProjectPath();
    if (last.len > 0 and main.directoryExists(io, last)) return last;
    return "";
}

pub fn close(model: *Model, fx: *Effects) void {
    cancelInFlight(model, fx);
    clearCache(model);
    model.skill_probe_path_len = 0;
    model.skills_filter_buffer.clear();
}

/// One-shot find when the probe path is empty or changed. No-op when
/// that path is already current (in-flight or a finished scan), so a
/// composer `$to…` keystroke does not spawn again. Works when
/// `settings_page != .skills`. Empty / missing / Windows skips.
pub fn ensureScanned(model: *Model, fx: *Effects) void {
    if (!scanSupported()) return;
    const cwd = probePath(model);
    const probed = model.skill_probe_path_storage[0..model.skill_probe_path_len];
    if (std.mem.eql(u8, cwd, probed)) return;
    refresh(model, fx);
}

/// Cancel any in-flight scan, drop the cache, and spawn find when
/// Settings has an existing project path. Empty / missing / Windows
/// skips the spawn so the list stays empty.
pub fn refresh(model: *Model, fx: *Effects) void {
    cancelInFlight(model, fx);
    clearCache(model);
    if (!scanSupported()) {
        model.skill_probe_path_len = 0;
        return;
    }
    const cwd = probePath(model);
    if (cwd.len == 0) {
        model.skill_probe_path_len = 0;
        return;
    }

    writeFixed(&model.skill_probe_path_storage, &model.skill_probe_path_len, cwd);
    spawnWalk(model, fx, cwd);
}

fn spawnWalk(model: *Model, fx: *Effects, cwd: []const u8) void {
    const key = model.next_skill_key;
    model.next_skill_key = key + 1;
    model.skill_key = key;
    var argv_buf: [walk_argv_len][]const u8 = undefined;
    fx.spawn(.{
        .key = key,
        .argv = argvFor(cwd, &argv_buf),
        .on_line = Effects.lineMsg(.fx_line),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
}

fn probeStillCurrent(model: *const Model) bool {
    if (model.skill_key == 0) return false;
    const path = probePath(model);
    const probed = model.skill_probe_path_storage[0..model.skill_probe_path_len];
    return std.mem.eql(u8, path, probed);
}

pub fn isSkillMdPath(path: []const u8) bool {
    if (path.len < skill_filename.len) return false;
    const base = if (std.mem.lastIndexOfScalar(u8, path, '/')) |slash|
        path[slash + 1 ..]
    else
        path;
    return std.mem.eql(u8, base, skill_filename);
}

/// Parent folder of `SKILL.md`. Empty when the file sits at the scan
/// root (`SKILL.md` / `./SKILL.md`).
pub fn parentDirName(relpath: []const u8) []const u8 {
    const slash = std.mem.lastIndexOfScalar(u8, relpath, '/') orelse return "";
    const dir = relpath[0..slash];
    if (dir.len == 0 or std.mem.eql(u8, dir, ".")) return "";
    if (std.mem.lastIndexOfScalar(u8, dir, '/')) |prev| return dir[prev + 1 ..];
    return dir;
}

pub fn displayName(relpath: []const u8, frontmatter_name: []const u8) []const u8 {
    const named = std.mem.trim(u8, frontmatter_name, " \t\r\n");
    if (named.len > 0) return named;
    const parent = parentDirName(relpath);
    if (parent.len > 0) return parent;
    return skill_fallback_name;
}

fn trimOneNewline(text: []const u8) []const u8 {
    if (text.len >= 2 and text[0] == '\r' and text[1] == '\n') return text[2..];
    if (text.len >= 1 and (text[0] == '\n' or text[0] == '\r')) return text[1..];
    return text;
}

fn frontmatterClose(rest: []const u8) ?usize {
    var i: usize = 0;
    while (i < rest.len) : (i += 1) {
        if (rest[i] != '\n') continue;
        const after = rest[i + 1 ..];
        if (std.mem.startsWith(u8, after, "---")) return i;
    }
    return null;
}

/// Light YAML `name:` in a leading `---` fence. Empty when missing.
pub fn parseFrontmatterName(source: []const u8) []const u8 {
    const start = std.mem.trimStart(u8, source, " \t\r\n");
    if (!std.mem.startsWith(u8, start, "---")) return "";
    const rest = trimOneNewline(start[3..]);
    const fence = frontmatterClose(rest) orelse return "";
    const fm = rest[0..fence];
    var lines = std.mem.splitScalar(u8, fm, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (!std.mem.startsWith(u8, line, "name:")) continue;
        var value = std.mem.trim(u8, line["name:".len..], " \t\r");
        if (value.len >= 2) {
            const q = value[0];
            if ((q == '"' or q == '\'') and value[value.len - 1] == q) {
                value = value[1 .. value.len - 1];
            }
        }
        return value;
    }
    return "";
}

/// Body after a leading `---` / `---` fence. Unfenced source is
/// trimmed as-is.
pub fn stripFrontmatter(source: []const u8) []const u8 {
    const start = std.mem.trimStart(u8, source, " \t\r\n");
    if (!std.mem.startsWith(u8, start, "---")) {
        return std.mem.trim(u8, source, " \t\r\n");
    }
    const rest = trimOneNewline(start[3..]);
    const fence = frontmatterClose(rest) orelse return std.mem.trim(u8, source, " \t\r\n");
    var body = rest[fence + 1 ..];
    if (std.mem.startsWith(u8, body, "---")) body = body[3..];
    body = trimOneNewline(body);
    return std.mem.trim(u8, body, " \t\r\n");
}

fn readSkillSource(io: std.Io, abs: []const u8, buf: []u8) []const u8 {
    const bytes = std.Io.Dir.cwd().readFileAlloc(io, abs, std.heap.page_allocator, .limited(buf.len)) catch return "";
    defer std.heap.page_allocator.free(bytes);
    const n = @min(buf.len, bytes.len);
    @memcpy(buf[0..n], bytes[0..n]);
    return buf[0..n];
}

fn joinProbeRelpath(root: []const u8, relpath: []const u8, buf: []u8) ?[]const u8 {
    const base = std.mem.trimEnd(u8, root, "/");
    const rel = std.mem.trimStart(u8, relpath, "/");
    if (base.len == 0 or rel.len == 0) return null;
    return std.fmt.bufPrint(buf, "{s}/{s}", .{ base, rel }) catch null;
}

fn hydrateOne(model: *Model, index: usize) void {
    const relpath = model.skill_store[index].path();
    const io = model.store_io;
    const root = model.skill_probe_path_storage[0..model.skill_probe_path_len];
    var name: []const u8 = "";
    if (io != null and root.len > 0) {
        var path_buf: [main.max_project_path + max_skill_path + 1]u8 = undefined;
        if (joinProbeRelpath(root, relpath, &path_buf)) |abs| {
            var file_buf: [max_skill_file_read]u8 = undefined;
            const source = readSkillSource(io.?, abs, &file_buf);
            name = parseFrontmatterName(source);
        }
    }
    model.skill_store[index].setName(displayName(relpath, name));
}

/// Append trimmed `SKILL.md` paths until `max_skills`. Later lines are
/// dropped. Names start as the parent folder and pick up YAML `name:`
/// when the file can be read.
pub fn applyStdoutPaths(model: *Model, raw: []const u8) void {
    var it = std.mem.splitScalar(u8, raw, '\n');
    while (it.next()) |line| {
        if (model.skill_count >= max_skills) return;
        const path = file_mention.normalizeStdoutPath(line);
        if (path.len == 0 or !isSkillMdPath(path)) continue;
        const index = model.skill_count;
        model.skill_store[index].setPath(path);
        model.skill_store[index].setName(displayName(path, ""));
        hydrateOne(model, index);
        model.skill_count += 1;
    }
}

pub fn applyLine(model: *Model, line: native_sdk.EffectLine) void {
    if (line.key != model.skill_key or model.skill_key == 0) return;
    if (!probeStillCurrent(model)) return;
    applyStdoutPaths(model, line.line);
}

pub fn handleExit(model: *Model, fx: *Effects, exit: native_sdk.EffectExit) void {
    _ = fx;
    if (exit.key != model.skill_key or model.skill_key == 0) return;
    const current = probeStillCurrent(model);
    model.skill_key = 0;
    const succeeded = exit.reason == .exited and exit.code == 0;
    if (succeeded and current) return;
    clearCache(model);
}

pub fn selectSkill(model: *Model, id: u32) void {
    if (id == 0 or id > model.skill_count) {
        model.skill_selected_id = 0;
        model.skill_body_len = 0;
        return;
    }
    model.skill_selected_id = id;
    loadBody(model, id - 1);
}

fn loadBody(model: *Model, index: usize) void {
    model.skill_body_len = 0;
    const io = model.store_io orelse return;
    const root = model.skill_probe_path_storage[0..model.skill_probe_path_len];
    if (root.len == 0) return;
    const relpath = model.skill_store[index].path();
    var path_buf: [main.max_project_path + max_skill_path + 1]u8 = undefined;
    const abs = joinProbeRelpath(root, relpath, &path_buf) orelse return;
    var file_buf: [max_skill_file_read]u8 = undefined;
    const source = readSkillSource(io, abs, &file_buf);
    if (source.len == 0) return;
    writeFixed(&model.skill_body_storage, &model.skill_body_len, stripFrontmatter(source));
}

pub fn emptyHint(model: *const Model) []const u8 {
    if (probePath(model).len == 0) return "Open a project";
    if (model.skill_key != 0 and model.skill_count == 0) return "";
    return "No skills found";
}

test "argv is chdir script plus find SKILL.md skips; not file-mention walk" {
    var buf: [walk_argv_len][]const u8 = undefined;
    const argv = argvFor("/tmp/faku-skills", &buf);
    try std.testing.expectEqualStrings(sh_bin, argv[0]);
    try std.testing.expectEqualStrings("-c", argv[1]);
    try std.testing.expectEqualStrings(main.fx_ask_chdir_script, argv[2]);
    try std.testing.expectEqualStrings("sh", argv[3]);
    try std.testing.expectEqualStrings("/tmp/faku-skills", argv[4]);
    try std.testing.expectEqualStrings(sh_bin, argv[5]);
    try std.testing.expectEqualStrings("-c", argv[6]);
    try std.testing.expectEqualStrings(find_skills_script, argv[7]);
    try std.testing.expect(isSkillsWalkArgv(argv));
    try std.testing.expect(!file_mention.isWalkArgv(argv));
    try std.testing.expect(!file_mention.isGitLsFilesArgv(argv));
    try std.testing.expect(scriptHas(argv[7], find_maxdepth_flag));
    try std.testing.expect(scriptHas(argv[7], find_maxdepth));
    try std.testing.expect(scriptHas(argv[7], find_prune));
    try std.testing.expect(scriptHas(argv[7], find_type_file));
    try std.testing.expect(scriptHas(argv[7], skill_filename));
    try std.testing.expect(!scriptHas(argv[7], file_mention.find_dot_star));
    inline for (walk_skip_names) |name| {
        try std.testing.expect(scriptHas(argv[7], name));
    }
    try std.testing.expect(!isSkillsWalkArgv(&.{ find_bin, find_skills_script }));
    var mention_buf: [8][]const u8 = undefined;
    try std.testing.expect(!isSkillsWalkArgv(file_mention.walkArgvFor("/tmp/faku-skills", &mention_buf)));
    try std.testing.expect(skills_key_first > file_mention.file_mention_key_first);
    try std.testing.expect(skills_key_first > 520);
}

test "parse name from frontmatter; quoted and missing" {
    try std.testing.expectEqualStrings("my-skill", parseFrontmatterName(
        \\---
        \\name: my-skill
        \\description: hello
        \\---
        \\
        \\# Body
    ));
    try std.testing.expectEqualStrings("Pretty Name", parseFrontmatterName(
        \\---
        \\name: "Pretty Name"
        \\---
        \\body
    ));
    try std.testing.expectEqualStrings("quoted", parseFrontmatterName(
        \\---
        \\name: 'quoted'
        \\---
    ));
    try std.testing.expectEqualStrings("", parseFrontmatterName("# no fence\nname: nope\n"));
    try std.testing.expectEqualStrings("", parseFrontmatterName("---\ndescription: x\n---\n"));
    try std.testing.expectEqualStrings("", parseFrontmatterName(""));
    try std.testing.expectEqualStrings("My Skill", stripFrontmatter(
        \\---
        \\name: x
        \\---
        \\
        \\My Skill
        \\
    ));
    try std.testing.expectEqualStrings("plain body", stripFrontmatter("plain body\n"));
}

test "empty scan; list cap; parent folder name" {
    var model = Model{};
    applyStdoutPaths(&model, "");
    try std.testing.expectEqual(@as(u32, 0), cachedCount(&model));
    try std.testing.expectEqualStrings("Open a project", emptyHint(&model));
    applyStdoutPaths(&model, "\n  \n./\n.\nreadme.md\nsrc/main.zig\n");
    try std.testing.expectEqual(@as(u32, 0), cachedCount(&model));

    applyStdoutPaths(&model, "./.cursor/skills/demo/SKILL.md\nskills/other/SKILL.md\nSKILL.md\n");
    try std.testing.expectEqual(@as(u32, 3), cachedCount(&model));
    try std.testing.expectEqualStrings(".cursor/skills/demo/SKILL.md", cachedPath(&model, 0));
    try std.testing.expectEqualStrings("demo", cachedName(&model, 0));
    try std.testing.expectEqualStrings("skills/other/SKILL.md", cachedPath(&model, 1));
    try std.testing.expectEqualStrings("other", cachedName(&model, 1));
    try std.testing.expectEqualStrings("SKILL.md", cachedPath(&model, 2));
    try std.testing.expectEqualStrings(skill_fallback_name, cachedName(&model, 2));
    try std.testing.expectEqualStrings("demo", parentDirName(".cursor/skills/demo/SKILL.md"));
    try std.testing.expectEqualStrings("", parentDirName("SKILL.md"));
    try std.testing.expectEqualStrings("demo", displayName(".cursor/skills/demo/SKILL.md", ""));
    try std.testing.expectEqualStrings("from-yaml", displayName(".cursor/skills/demo/SKILL.md", "from-yaml"));

    var overflow: [max_skills * 24 + 16]u8 = undefined;
    var n: usize = 0;
    var i: usize = 0;
    while (i < max_skills + 4) : (i += 1) {
        const piece = "skills/x/SKILL.md\n";
        @memcpy(overflow[n .. n + piece.len], piece);
        n += piece.len;
    }
    clearCache(&model);
    applyStdoutPaths(&model, overflow[0..n]);
    try std.testing.expectEqual(@as(u32, max_skills), cachedCount(&model));
}

test "hydrate name from SKILL.md frontmatter in a temp project" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const root = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-skills-name", .{tmp.sub_path[0..]});
    var skill_dir_buf: [256]u8 = undefined;
    const skill_dir = try std.fmt.bufPrint(&skill_dir_buf, "{s}/skills/named", .{root});
    try std.Io.Dir.cwd().createDirPath(testing.io, skill_dir);
    var file_buf: [256]u8 = undefined;
    const file_path = try std.fmt.bufPrint(&file_buf, "{s}/SKILL.md", .{skill_dir});
    try std.Io.Dir.cwd().writeFile(testing.io, .{
        .sub_path = file_path,
        .data =
        \\---
        \\name: pretty-skill
        \\---
        \\
        \\Do the thing.
        \\
        ,
    });

    var model = Model{};
    model.store_io = testing.io;
    writeFixed(&model.skill_probe_path_storage, &model.skill_probe_path_len, root);
    applyStdoutPaths(&model, "skills/named/SKILL.md\n");
    try std.testing.expectEqual(@as(u32, 1), cachedCount(&model));
    try std.testing.expectEqualStrings("pretty-skill", cachedName(&model, 0));

    selectSkill(&model, 1);
    try std.testing.expectEqual(@as(u32, 1), model.skill_selected_id);
    try std.testing.expectEqualStrings("Do the thing.", model.skill_body_storage[0..model.skill_body_len]);
}

test "ensureScanned one-shots find when the probe path is empty; no-op when current" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const root = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-skills-ensure", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(testing.io, root);

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = testing.io;
    const id = model.addSession("ensure scanned", .fx);
    model.selected = id;
    model.sessionById(id).?.setProjectPath(root);
    try testing.expect(model.settings_page != .skills);
    try testing.expectEqual(@as(u32, 0), cachedCount(&model));

    ensureScanned(&model, &fx);
    try testing.expect(model.skill_key >= skills_key_first);
    const first_key = model.skill_key;
    var i: usize = 0;
    var spawn = fx.pendingSpawnAt(0);
    while (spawn) |item| : (i += 1) {
        if (item.key == first_key and isSkillsWalkArgv(item.argv)) break;
        spawn = fx.pendingSpawnAt(i + 1);
    }
    try testing.expect(spawn != null);
    try testing.expectEqualStrings(root, spawn.?.argv[4]);
    const after_first = fx.pendingSpawnCount();

    ensureScanned(&model, &fx);
    try testing.expectEqual(first_key, model.skill_key);
    try testing.expectEqual(after_first, fx.pendingSpawnCount());

    applyStdoutPaths(&model, "skills/named/SKILL.md\n");
    handleExit(&model, &fx, .{ .key = first_key, .reason = .exited, .code = 0 });
    try testing.expectEqual(@as(u64, 0), model.skill_key);
    try testing.expectEqual(@as(u32, 1), cachedCount(&model));

    ensureScanned(&model, &fx);
    try testing.expectEqual(@as(u64, 0), model.skill_key);
    try testing.expectEqual(after_first, fx.pendingSpawnCount());
    try testing.expectEqual(@as(u32, 1), cachedCount(&model));
}
