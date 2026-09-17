//! Settings Skills + composer `$` insert: bounded `SKILL.md` scan
//! plus first-cut enable/disable via on-disk rename.
//!
//! Native has no FS watcher. Unix one-shots a packed `find` for
//! `SKILL.md` and `SKILL.md.disabled` (Waku `DISABLED_SKILL_FILE`)
//! through the same `/bin/sh -c` chdir workaround `fx ask` uses
//! (`fx_ask_chdir_script`). Windows cannot use `/bin/sh` or `find`:
//! `powershell.exe -NoProfile -Command {…} -Args <project_path>`
//! (`$args[0]`; same skip names / depth 8 / cap `max_skills`). Does
//! **not** prune `.*` — project skills live under `.cursor/skills` /
//! `.agents/skills`. Settings → Skills still `refresh`s on page open.
//! Composer `$` calls `ensureScanned` even when
//! `settings_page != .skills`. Scan root is the selected session
//! `project_path` when that directory exists, else settings
//! `last_project_path`. Skip `node_modules` / `target` / `dist` /
//! `build` / `out` / `vendor` / `__pycache__`. Cap 64 rows. Name comes
//! from YAML `name:` frontmatter when present, else the parent folder.
//! Body read still uses the actual file on disk (including
//! `.disabled`). When both live and disabled exist in the same dir,
//! live wins (one row). Settings selecting a row shows the body with
//! frontmatter stripped. Enable/Disable is a Faku-side one-shot
//! rename in that skill directory (`SKILL.md` ↔ `SKILL.md.disabled`):
//! Unix `mv --` after the chdir wrapper; Windows powershell
//! Move-Item with argv slots for skill-dir / from / to (never
//! interpolated into `-Command`). Tools discover skills by exact
//! filename so the rename hides/shows the skill from fx and peers
//! the same as Waku. Composer `$` inserts `$name ` for **enabled**
//! skills only. Send prepends stripped `SKILL.md` bodies for `$name`
//! tokens (enabled rows only; missing/unreadable omit that block)
//! onto the prompt that `startPrompt` ships to every provider and
//! stores as the user turn; untitled titles still use the original
//! draft. Runtime-only (not `sessions.json`). Empty-state Open a
//! project / No skills found follow `i18n.SkillsEmptyChrome`
//! (distinct from FilterChrome / RightPanelChrome; composer `$`
//! insert empty reuses the same hint). Enable / Disable / Disabled
//! badge follow `i18n.SkillsEnableChrome` (distinct from
//! ProvidersChrome). Not a daemon SkillsCatalog / WorkspaceOperation,
//! not ACP `/name` slash rows. Not a Native FS API. app.zon already
//! includes windows.
//!
//! Spawn/line/exit orchestration lives here. Tests do not need a live
//! daemon or fx.

const std = @import("std");
const builtin = @import("builtin");
const native_sdk = @import("native_sdk");
const main = @import("main.zig");
const util = @import("util.zig");
const model_exports = @import("model_exports.zig");
const file_mention = @import("file_mention.zig");
const composer = @import("composer.zig");
const i18n = @import("i18n.zig");

const Model = model_exports.Model;
const Effects = main.Effects;
const writeFixed = model_exports.writeFixed;

/// One-shot Skills `find` for `SKILL.md` / `SKILL.md.disabled`.
/// Distinct from review hunk (520+). Band is 530+. Incremented per
/// scan so a cancelled spawn cannot paint a later Settings open.
pub const skills_key_first: u64 = 530;
/// One-shot Skills enable/disable `mv` (`SKILL.md` ↔
/// `SKILL.md.disabled`). Distinct from the scan key (530+) and
/// Files Preview issue-link (540+). Band is 580+. Incremented per
/// toggle so a stale rename exit cannot refresh a later scan.
pub const skills_rename_key_first: u64 = 580;

pub const max_skills: usize = 64;
pub const max_skills_s = std.fmt.comptimePrint("{d}", .{max_skills});
pub const max_skill_path: usize = 255;
pub const max_skill_name: usize = 64;
pub const max_skill_body: usize = 4096;
pub const max_skill_file_read: usize = 8192;

pub const skill_filename = "SKILL.md";
/// Waku `DISABLED_SKILL_FILE`. Exact filename so tools that match
/// `SKILL.md` only do not load a disabled skill.
pub const disabled_skill_filename = "SKILL.md.disabled";
pub const skill_fallback_name = "SKILL";
/// First-cut Send prepend heading. Stable English prompt data, not chrome.
pub const skill_prompt_heading = "### Skill: ";
pub const mv_bin = "mv";
pub const mv_end_of_options = "--";

pub const sh_bin = file_mention.sh_bin;
pub const find_bin = file_mention.find_bin;
pub const find_maxdepth_flag = file_mention.find_maxdepth_flag;
pub const find_maxdepth = file_mention.find_maxdepth;
pub const find_prune = file_mention.find_prune;
pub const find_type_file = file_mention.find_type_file;
pub const find_name_flag = "-name";
pub const powershell_bin = file_mention.powershell_bin;
pub const powershell_noprofile = file_mention.powershell_noprofile;
pub const powershell_command = file_mention.powershell_command;
pub const powershell_args_flag = file_mention.powershell_args_flag;

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
    "find . -maxdepth 8 \\( -name node_modules -o -name target -o -name dist -o -name build -o -name out -o -name vendor -o -name __pycache__ \\) -prune -o -type f \\( -name SKILL.md -o -name SKILL.md.disabled \\) -print";

/// Scriptblock + `$args[0]`: project path is its own argv slot after
/// `-Args`, not spliced into the `-Command` body. Distinct from
/// `file_mention.powershell_walk_script`: does **not** skip names
/// starting with `.` (skills live under `.cursor` / `.agents`). Files
/// named exactly `SKILL.md` / `SKILL.md.disabled` only, depth 8, same
/// skip names, relative paths with `/`, cap `max_skills`. Six argv
/// slots total.
pub const powershell_skills_walk_script =
    "{ $ErrorActionPreference='Stop'; $script:root=$args[0].TrimEnd('\\','/'); $script:skip=@('node_modules','target','dist','build','out','vendor','__pycache__'); $script:want=@('SKILL.md','SKILL.md.disabled'); $script:n=0; function Walk($dir,$depth){ if($script:n -ge " ++ max_skills_s ++ "){return}; foreach($item in (Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue)){ if($script:n -ge " ++ max_skills_s ++ "){return}; $d=$depth+1; if($d -gt 8){continue}; $name=$item.Name; if($script:skip -contains $name){continue}; if($item.PSIsContainer){ if($d -lt 8){ Walk $item.FullName $d } } else { if($script:want -cnotcontains $name){continue}; $rel=$item.FullName.Substring($script:root.Length).TrimStart('\\','/'); Write-Output ($rel -replace '\\\\','/'); $script:n++ } } }; Walk $script:root 0 }";

/// Scriptblock + `$args[0]` / `$args[1]` / `$args[2]`: skill-dir,
/// from-name, and to-name stay argv slots after `-Args` (never
/// interpolated into `-Command`). `Move-Item -LiteralPath`. Eight
/// argv slots.
pub const powershell_skills_rename_script =
    "{ $ErrorActionPreference='Stop'; $dir=$args[0]; $from=$args[1]; $to=$args[2]; Move-Item -LiteralPath (Join-Path $dir $from) -Destination (Join-Path $dir $to) }";

/// Unix `/bin/sh -c` chdir + `/bin/sh -c` + `find_skills_script` (8).
/// Windows powershell `-Command` + `-Args` is 6; this is the spawn
/// buffer (max of the two).
pub const walk_argv_len: usize = 8;
pub const unix_walk_argv_len: usize = 8;
pub const windows_walk_argv_len: usize = 6;
/// Unix `/bin/sh -c` chdir + `mv --` from to (9). Windows powershell
/// `-Command` + `-Args` skill-dir / from / to is 8; this is the spawn
/// buffer (max of the two). Native `max_effect_argv` is 16.
pub const rename_argv_len: usize = 9;
pub const unix_rename_argv_len: usize = 9;
pub const windows_rename_argv_len: usize = 8;

/// Settings sidebar page. Chrome is General | Appearance |
/// Providers | Skills | Usage | Computer Use. Computer Use is a
/// first-cut Unavailable page (no Native Screen Recording /
/// Accessibility APIs). Persists as `settings_page` on
/// `sessions.json` extras (`general` / `appearance` / `providers` /
/// `skills` / `usage` / `computer_use`). Missing / unknown / empty
/// loads as General. Skill rows stay runtime-only.
pub const Page = enum {
    general,
    appearance,
    providers,
    skills,
    usage,
    computer_use,

    pub fn persistName(self: Page) []const u8 {
        return switch (self) {
            .general => "general",
            .appearance => "appearance",
            .providers => "providers",
            .skills => "skills",
            .usage => "usage",
            .computer_use => "computer_use",
        };
    }

    /// Missing / unknown / empty → General.
    pub fn fromPersist(value: []const u8) Page {
        if (std.mem.eql(u8, value, "appearance")) return .appearance;
        if (std.mem.eql(u8, value, "providers")) return .providers;
        if (std.mem.eql(u8, value, "skills")) return .skills;
        if (std.mem.eql(u8, value, "usage")) return .usage;
        if (std.mem.eql(u8, value, "computer_use")) return .computer_use;
        return .general;
    }
};

pub const CachedSkill = struct {
    path_storage: [max_skill_path]u8 = [_]u8{0} ** max_skill_path,
    path_len: usize = 0,
    name_storage: [max_skill_name]u8 = [_]u8{0} ** max_skill_name,
    name_len: usize = 0,
    /// `SKILL.md` = true; `SKILL.md.disabled` = false.
    enabled: bool = true,

    pub fn path(self: *const CachedSkill) []const u8 {
        return self.path_storage[0..self.path_len];
    }

    pub fn name(self: *const CachedSkill) []const u8 {
        return self.name_storage[0..self.name_len];
    }

    pub fn setPath(self: *CachedSkill, value: []const u8) void {
        writeFixed(&self.path_storage, &self.path_len, value);
        slashNormalizeInPlace(self.path_storage[0..self.path_len]);
    }

    pub fn setName(self: *CachedSkill, value: []const u8) void {
        writeFixed(&self.name_storage, &self.name_len, value);
    }
};

pub fn unixWalkArgvFor(cwd: []const u8, buf: *[walk_argv_len][]const u8) []const []const u8 {
    buf.* = .{
        sh_bin,
        "-c",
        util.fx_ask_chdir_script,
        "sh",
        cwd,
        sh_bin,
        "-c",
        find_skills_script,
    };
    return buf[0..unix_walk_argv_len];
}

/// Windows: `powershell.exe -NoProfile -Command {scriptblock} -Args
/// <project_path>`. Path stays `$args[0]` — not interpolated into
/// the `-Command` body.
pub fn windowsWalkArgvFor(cwd: []const u8, buf: *[walk_argv_len][]const u8) []const []const u8 {
    buf[0] = powershell_bin;
    buf[1] = powershell_noprofile;
    buf[2] = powershell_command;
    buf[3] = powershell_skills_walk_script;
    buf[4] = powershell_args_flag;
    buf[5] = cwd;
    return buf[0..windows_walk_argv_len];
}

pub fn argvFor(cwd: []const u8, buf: *[walk_argv_len][]const u8) []const []const u8 {
    return switch (builtin.os.tag) {
        .windows => windowsWalkArgvFor(cwd, buf),
        else => unixWalkArgvFor(cwd, buf),
    };
}

fn scriptHas(script: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, script, needle) != null;
}

fn isUnixSkillsWalkArgv(argv: []const []const u8) bool {
    if (argv.len != unix_walk_argv_len) return false;
    if (!std.mem.eql(u8, argv[0], sh_bin)) return false;
    if (!std.mem.eql(u8, argv[1], "-c")) return false;
    if (!std.mem.eql(u8, argv[2], util.fx_ask_chdir_script)) return false;
    if (!std.mem.eql(u8, argv[5], sh_bin)) return false;
    if (!std.mem.eql(u8, argv[6], "-c")) return false;
    if (!std.mem.eql(u8, argv[7], find_skills_script)) return false;
    if (!scriptHas(argv[7], find_maxdepth_flag)) return false;
    if (!scriptHas(argv[7], find_maxdepth)) return false;
    if (!scriptHas(argv[7], find_prune)) return false;
    if (!scriptHas(argv[7], find_type_file)) return false;
    if (!scriptHas(argv[7], find_name_flag)) return false;
    if (!scriptHas(argv[7], skill_filename)) return false;
    if (!scriptHas(argv[7], disabled_skill_filename)) return false;
    inline for (walk_skip_names) |name| {
        if (!scriptHas(argv[7], name)) return false;
    }
    return true;
}

fn isWindowsSkillsWalkArgv(argv: []const []const u8) bool {
    if (argv.len != windows_walk_argv_len) return false;
    if (!std.mem.eql(u8, argv[0], powershell_bin)) return false;
    if (!std.mem.eql(u8, argv[1], powershell_noprofile)) return false;
    if (!std.mem.eql(u8, argv[2], powershell_command)) return false;
    if (!std.mem.eql(u8, argv[3], powershell_skills_walk_script)) return false;
    if (!std.mem.eql(u8, argv[4], powershell_args_flag)) return false;
    if (argv[5].len == 0) return false;
    if (!scriptHas(argv[3], "$args[0]")) return false;
    if (!scriptHas(argv[3], find_maxdepth)) return false;
    if (!scriptHas(argv[3], max_skills_s)) return false;
    if (!scriptHas(argv[3], skill_filename)) return false;
    if (!scriptHas(argv[3], disabled_skill_filename)) return false;
    inline for (walk_skip_names) |name| {
        if (!scriptHas(argv[3], name)) return false;
    }
    return true;
}

pub fn isSkillsWalkArgv(argv: []const []const u8) bool {
    return isUnixSkillsWalkArgv(argv) or isWindowsSkillsWalkArgv(argv);
}

/// `mv -- SKILL.md SKILL.md.disabled` (disable) or the reverse
/// (enable) after the chdir wrapper. Filenames are argv slots — never
/// interpolated into `fx_ask_chdir_script`.
pub fn unixRenameArgvFor(cwd: []const u8, enable: bool, buf: *[rename_argv_len][]const u8) []const []const u8 {
    const from = if (enable) disabled_skill_filename else skill_filename;
    const to = if (enable) skill_filename else disabled_skill_filename;
    buf.* = .{
        sh_bin,
        "-c",
        util.fx_ask_chdir_script,
        "sh",
        cwd,
        mv_bin,
        mv_end_of_options,
        from,
        to,
    };
    return buf[0..unix_rename_argv_len];
}

/// Windows: `powershell.exe -NoProfile -Command {scriptblock} -Args
/// <skill-dir> <from> <to>`. Paths stay `$args[0]` / `$args[1]` /
/// `$args[2]` — not interpolated into the `-Command` body.
pub fn windowsRenameArgvFor(cwd: []const u8, enable: bool, buf: *[rename_argv_len][]const u8) []const []const u8 {
    const from = if (enable) disabled_skill_filename else skill_filename;
    const to = if (enable) skill_filename else disabled_skill_filename;
    buf[0] = powershell_bin;
    buf[1] = powershell_noprofile;
    buf[2] = powershell_command;
    buf[3] = powershell_skills_rename_script;
    buf[4] = powershell_args_flag;
    buf[5] = cwd;
    buf[6] = from;
    buf[7] = to;
    return buf[0..windows_rename_argv_len];
}

pub fn renameArgvFor(cwd: []const u8, enable: bool, buf: *[rename_argv_len][]const u8) []const []const u8 {
    return switch (builtin.os.tag) {
        .windows => windowsRenameArgvFor(cwd, enable, buf),
        else => unixRenameArgvFor(cwd, enable, buf),
    };
}

fn renameFilenamesOk(from: []const u8, to: []const u8) bool {
    const disable = std.mem.eql(u8, from, skill_filename) and std.mem.eql(u8, to, disabled_skill_filename);
    const enable = std.mem.eql(u8, from, disabled_skill_filename) and std.mem.eql(u8, to, skill_filename);
    return disable or enable;
}

fn isUnixSkillsRenameArgv(argv: []const []const u8) bool {
    if (argv.len != unix_rename_argv_len) return false;
    if (!std.mem.eql(u8, argv[0], sh_bin)) return false;
    if (!std.mem.eql(u8, argv[1], "-c")) return false;
    if (!std.mem.eql(u8, argv[2], util.fx_ask_chdir_script)) return false;
    if (!std.mem.eql(u8, argv[5], mv_bin)) return false;
    if (!std.mem.eql(u8, argv[6], mv_end_of_options)) return false;
    return renameFilenamesOk(argv[7], argv[8]);
}

fn isWindowsSkillsRenameArgv(argv: []const []const u8) bool {
    if (argv.len != windows_rename_argv_len) return false;
    if (!std.mem.eql(u8, argv[0], powershell_bin)) return false;
    if (!std.mem.eql(u8, argv[1], powershell_noprofile)) return false;
    if (!std.mem.eql(u8, argv[2], powershell_command)) return false;
    if (!std.mem.eql(u8, argv[3], powershell_skills_rename_script)) return false;
    if (!std.mem.eql(u8, argv[4], powershell_args_flag)) return false;
    if (argv[5].len == 0) return false;
    if (!scriptHas(argv[3], "$args[0]")) return false;
    if (!scriptHas(argv[3], "$args[1]")) return false;
    if (!scriptHas(argv[3], "$args[2]")) return false;
    return renameFilenamesOk(argv[6], argv[7]);
}

pub fn isSkillsRenameArgv(argv: []const []const u8) bool {
    return isUnixSkillsRenameArgv(argv) or isWindowsSkillsRenameArgv(argv);
}

/// macOS / Linux / Windows. Other tags stay fail-closed (empty list).
pub fn scanSupportedOn(tag: std.Target.Os.Tag) bool {
    return switch (tag) {
        .linux, .macos, .windows => true,
        else => false,
    };
}

pub fn scanSupported() bool {
    return scanSupportedOn(builtin.os.tag);
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

pub fn cachedEnabled(model: *const Model, index: usize) bool {
    if (index >= model.skill_count) return false;
    return model.skill_store[index].enabled;
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

fn cancelRename(model: *Model, fx: *Effects) void {
    if (model.skill_rename_key == 0) return;
    fx.cancel(model.skill_rename_key);
    model.skill_rename_key = 0;
}

/// Selected-session directory when it exists, else settings last
/// project path. Empty / missing stays empty so Skills does not
/// invent a project.
pub fn probePath(model: *const Model) []const u8 {
    const io = model.store_io orelse return "";
    const selected = model.selectedProjectPath();
    if (selected.len > 0 and util.directoryExists(io, selected)) return selected;
    const last = model.lastProjectPath();
    if (last.len > 0 and util.directoryExists(io, last)) return last;
    return "";
}

pub fn close(model: *Model, fx: *Effects) void {
    cancelInFlight(model, fx);
    cancelRename(model, fx);
    clearCache(model);
    model.skill_probe_path_len = 0;
    model.skill_rename_cwd_len = 0;
    model.skills_filter_buffer.clear();
}

/// One-shot find when the probe path is empty or changed. No-op when
/// that path is already current (in-flight or a finished scan), so a
/// composer `$to…` keystroke does not spawn again. Works when
/// `settings_page != .skills`. Empty / missing skips.
pub fn ensureScanned(model: *Model, fx: *Effects) void {
    if (!scanSupported()) return;
    const cwd = probePath(model);
    const probed = model.skill_probe_path_storage[0..model.skill_probe_path_len];
    if (std.mem.eql(u8, cwd, probed)) return;
    refresh(model, fx);
}

/// Cancel any in-flight scan, drop the cache, and spawn find when
/// Settings has an existing project path. Empty / missing skips the
/// spawn so the list stays empty.
pub fn refresh(model: *Model, fx: *Effects) void {
    cancelInFlight(model, fx);
    cancelRename(model, fx);
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

pub fn pathBasename(path: []const u8) []const u8 {
    if (lastPathSep(path)) |slash|
        return path[slash + 1 ..];
    return path;
}

pub fn skillEnabledFromPath(path: []const u8) bool {
    return std.mem.eql(u8, pathBasename(path), skill_filename);
}

pub fn isSkillMdPath(path: []const u8) bool {
    const base = pathBasename(path);
    return std.mem.eql(u8, base, skill_filename) or std.mem.eql(u8, base, disabled_skill_filename);
}

/// Parent directory of the skill file (full relative dir, not the
/// last folder name). Empty when the file sits at the scan root.
pub fn skillDirKey(relpath: []const u8) []const u8 {
    const slash = lastPathSep(relpath) orelse return "";
    return relpath[0..slash];
}

/// Parent folder of `SKILL.md`. Empty when the file sits at the scan
/// root (`SKILL.md` / `./SKILL.md`).
pub fn parentDirName(relpath: []const u8) []const u8 {
    const slash = lastPathSep(relpath) orelse return "";
    const dir = relpath[0..slash];
    if (dir.len == 0 or std.mem.eql(u8, dir, ".")) return "";
    if (lastPathSep(dir)) |prev| return dir[prev + 1 ..];
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
    const base = std.mem.trimEnd(u8, root, "/\\");
    const rel = std.mem.trimStart(u8, relpath, "/\\");
    if (base.len == 0 or rel.len == 0) return null;
    const printed = std.fmt.bufPrint(buf, "{s}/{s}", .{ base, rel }) catch return null;
    slashNormalizeInPlace(printed);
    return printed;
}

fn lastPathSep(path: []const u8) ?usize {
    return std.mem.lastIndexOfAny(u8, path, "/\\");
}

fn slashNormalizeInPlace(path: []u8) void {
    for (path) |*ch| {
        if (ch.* == '\\') ch.* = '/';
    }
}

fn hydrateOne(model: *Model, index: usize) void {
    const relpath = model.skill_store[index].path();
    const io = model.store_io;
    const root = model.skill_probe_path_storage[0..model.skill_probe_path_len];
    var name: []const u8 = "";
    if (io != null and root.len > 0) {
        var path_buf: [model_exports.max_project_path + max_skill_path + 1]u8 = undefined;
        if (joinProbeRelpath(root, relpath, &path_buf)) |abs| {
            var file_buf: [max_skill_file_read]u8 = undefined;
            const source = readSkillSource(io.?, abs, &file_buf);
            name = parseFrontmatterName(source);
        }
    }
    model.skill_store[index].setName(displayName(relpath, name));
}

/// Append trimmed `SKILL.md` / `SKILL.md.disabled` paths until
/// `max_skills`. Later new dirs are dropped. When both live and
/// disabled exist in the same dir, live wins (replace in place).
/// Names start as the parent folder and pick up YAML `name:` when
/// the file can be read.
pub fn applyStdoutPaths(model: *Model, raw: []const u8) void {
    var it = std.mem.splitScalar(u8, raw, '\n');
    while (it.next()) |line| {
        const raw_path = file_mention.normalizeStdoutPath(line);
        if (raw_path.len == 0 or raw_path.len > max_skill_path) continue;
        var path_buf: [max_skill_path]u8 = undefined;
        @memcpy(path_buf[0..raw_path.len], raw_path);
        slashNormalizeInPlace(path_buf[0..raw_path.len]);
        const path = path_buf[0..raw_path.len];
        if (!isSkillMdPath(path)) continue;
        const enabled = skillEnabledFromPath(path);
        const dir = skillDirKey(path);
        if (indexOfSkillDir(model, dir)) |index| {
            if (enabled and !model.skill_store[index].enabled) {
                storeSkillAt(model, index, path, true);
            }
            continue;
        }
        if (model.skill_count >= max_skills) continue;
        const index = model.skill_count;
        storeSkillAt(model, index, path, enabled);
        model.skill_count += 1;
    }
}

fn indexOfSkillDir(model: *const Model, dir: []const u8) ?usize {
    var i: usize = 0;
    while (i < model.skill_count) : (i += 1) {
        if (std.mem.eql(u8, skillDirKey(model.skill_store[i].path()), dir)) return i;
    }
    return null;
}

fn storeSkillAt(model: *Model, index: usize, path: []const u8, enabled: bool) void {
    model.skill_store[index].setPath(path);
    model.skill_store[index].enabled = enabled;
    model.skill_store[index].setName(displayName(path, ""));
    hydrateOne(model, index);
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

pub fn handleRenameExit(model: *Model, fx: *Effects, exit: native_sdk.EffectExit) void {
    if (exit.key != model.skill_rename_key or model.skill_rename_key == 0) return;
    model.skill_rename_key = 0;
    const succeeded = exit.reason == .exited and exit.code == 0;
    if (!succeeded) return;
    refresh(model, fx);
}

/// Enable when the selected skill is disabled, Disable when enabled.
/// One-shot rename in the skill directory. Missing file / in-flight
/// rename fail closed (cache unchanged).
pub fn toggleSkillEnabled(model: *Model, fx: *Effects) void {
    if (!scanSupported()) return;
    if (model.skill_rename_key != 0) return;
    const id = model.skill_selected_id;
    if (id == 0 or id > model.skill_count) return;
    const index = id - 1;
    const relpath = model.skill_store[index].path();
    const enable = !model.skill_store[index].enabled;
    const io = model.store_io orelse return;
    const root = model.skill_probe_path_storage[0..model.skill_probe_path_len];
    if (root.len == 0) return;
    var file_buf: [model_exports.max_project_path + max_skill_path + 1]u8 = undefined;
    const abs = joinProbeRelpath(root, relpath, &file_buf) orelse return;
    if (!util.fileExists(io, abs)) return;
    var parent_buf: [model_exports.max_project_path + max_skill_path + 1]u8 = undefined;
    const parent = absSkillParent(root, relpath, &parent_buf) orelse return;
    writeFixed(&model.skill_rename_cwd_storage, &model.skill_rename_cwd_len, parent);
    spawnRename(model, fx, enable);
}

fn absSkillParent(root: []const u8, relpath: []const u8, buf: []u8) ?[]const u8 {
    const dir = skillDirKey(relpath);
    if (dir.len == 0) {
        const base = std.mem.trimEnd(u8, root, "/\\");
        if (base.len == 0 or base.len > buf.len) return null;
        @memcpy(buf[0..base.len], base);
        slashNormalizeInPlace(buf[0..base.len]);
        return buf[0..base.len];
    }
    return joinProbeRelpath(root, dir, buf);
}

fn spawnRename(model: *Model, fx: *Effects, enable: bool) void {
    const key = model.next_skill_rename_key;
    model.next_skill_rename_key = key + 1;
    model.skill_rename_key = key;
    const cwd = model.skill_rename_cwd_storage[0..model.skill_rename_cwd_len];
    var argv_buf: [rename_argv_len][]const u8 = undefined;
    fx.spawn(.{
        .key = key,
        .argv = renameArgvFor(cwd, enable, &argv_buf),
        .on_line = Effects.lineMsg(.fx_line),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
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
    var path_buf: [model_exports.max_project_path + max_skill_path + 1]u8 = undefined;
    const abs = joinProbeRelpath(root, relpath, &path_buf) orelse return;
    var file_buf: [max_skill_file_read]u8 = undefined;
    const source = readSkillSource(io, abs, &file_buf);
    if (source.len == 0) return;
    writeFixed(&model.skill_body_storage, &model.skill_body_len, stripFrontmatter(source));
}

fn enabledSkillIndex(model: *const Model, name: []const u8) ?usize {
    var i: usize = 0;
    while (i < model.skill_count) : (i += 1) {
        if (!model.skill_store[i].enabled) continue;
        if (std.mem.eql(u8, model.skill_store[i].name(), name)) return i;
    }
    return null;
}

fn nameAlreadyQueued(names: []const []const u8, name: []const u8) bool {
    for (names) |seen| {
        if (std.mem.eql(u8, seen, name)) return true;
    }
    return false;
}

/// Stripped body for an enabled cache row. Empty when the file is
/// missing/unreadable. Caps at `max_skill_body`.
fn readEnabledSkillBody(model: *const Model, index: usize, buf: []u8) []const u8 {
    if (index >= model.skill_count) return "";
    if (!model.skill_store[index].enabled) return "";
    const io = model.store_io orelse return "";
    const root = model.skill_probe_path_storage[0..model.skill_probe_path_len];
    if (root.len == 0) return "";
    var path_buf: [model_exports.max_project_path + max_skill_path + 1]u8 = undefined;
    const abs = joinProbeRelpath(root, model.skill_store[index].path(), &path_buf) orelse return "";
    var file_buf: [max_skill_file_read]u8 = undefined;
    const source = readSkillSource(io, abs, &file_buf);
    if (source.len == 0) return "";
    const stripped = stripFrontmatter(source);
    const take = @min(buf.len, @min(stripped.len, max_skill_body));
    @memcpy(buf[0..take], stripped[0..take]);
    return buf[0..take];
}

fn appendSlice(out: []u8, pos: *usize, slice: []const u8) bool {
    if (pos.* + slice.len > out.len) return false;
    @memcpy(out[pos.*..][0..slice.len], slice);
    pos.* += slice.len;
    return true;
}

/// Prepend stripped bodies for `$name` tokens in `text` (enabled
/// cache rows only, first-occurrence order, missing files omitted).
/// Returns `text` unchanged when nothing matches. Output is capped
/// to `out` (callers pass `max_body`) so the stored user turn and
/// the provider prompt stay the same slice; original draft is always
/// kept at the end.
pub fn expandPrompt(model: *const Model, text: []const u8, out: []u8) []const u8 {
    if (text.len > out.len) return text;

    var names: [max_skills][]const u8 = undefined;
    var name_count: usize = 0;
    var search: usize = 0;
    while (composer.nextSkillToken(text, search)) |tok| {
        search = tok.after;
        if (nameAlreadyQueued(names[0..name_count], tok.name)) continue;
        if (name_count >= names.len) break;
        names[name_count] = tok.name;
        name_count += 1;
    }
    if (name_count == 0) return text;

    var pos: usize = 0;
    var wrote = false;
    for (names[0..name_count]) |name| {
        const index = enabledSkillIndex(model, name) orelse continue;
        var body_buf: [max_skill_body]u8 = undefined;
        const body = readEnabledSkillBody(model, index, &body_buf);
        if (body.len == 0) continue;
        const heading_over = skill_prompt_heading.len + name.len + 1 + 2;
        if (pos + heading_over + text.len > out.len) continue;
        const room = out.len - pos - text.len;
        const take = @min(body.len, room - heading_over);
        if (take == 0) continue;
        if (!appendSlice(out, &pos, skill_prompt_heading)) continue;
        if (!appendSlice(out, &pos, name)) continue;
        if (!appendSlice(out, &pos, "\n")) continue;
        if (!appendSlice(out, &pos, body[0..take])) continue;
        if (!appendSlice(out, &pos, "\n\n")) continue;
        wrote = true;
    }
    if (!wrote) return text;
    if (!appendSlice(out, &pos, text)) return text;
    return out[0..pos];
}

/// Kick a project scan when `$name` tokens are present, then expand.
/// Scan is async (Native has no sync walk); first Send after a paste
/// may still no-op until the cache fills.
pub fn prepareSendPrompt(model: *Model, fx: *Effects, text: []const u8, out: []u8) []const u8 {
    if (composer.draftHasSkillToken(text)) {
        ensureScanned(model, fx);
    }
    return expandPrompt(model, text, out);
}

/// English defaults from `i18n.SkillsEmptyChrome`. Tests that still
/// want the former hardcoded copy use these; `emptyHint` resolves
/// through `skillsEmptyChrome` for the Appearance locale.
const skills_empty_chrome_en = i18n.skillsEmptyChromeFor(.english, "");
pub const open_project = skills_empty_chrome_en.open_project;
pub const no_skills_found = skills_empty_chrome_en.no_skills_found;

/// English defaults from `i18n.SkillsEnableChrome`. Distinct from
/// Providers Enable / Disable.
const skills_enable_chrome_en = i18n.skillsEnableChromeFor(.english, "");
pub const enable_label = skills_enable_chrome_en.enable;
pub const disable_label = skills_enable_chrome_en.disable;
pub const disabled_badge = skills_enable_chrome_en.disabled;

fn skillsEmptyChrome(model: *const Model) i18n.SkillsEmptyChrome {
    return i18n.skillsEmptyChromeFor(model.language_preference, model.systemLocaleId());
}

/// Settings Skills empty hint and composer `$` insert empty. Localized
/// via `i18n.SkillsEmptyChrome`. Empty while a scan is in flight.
pub fn emptyHint(model: *const Model) []const u8 {
    const chrome = skillsEmptyChrome(model);
    if (probePath(model).len == 0) return chrome.open_project;
    if (model.skill_key != 0 and model.skill_count == 0) return "";
    return chrome.no_skills_found;
}

test "argv is chdir script plus find SKILL.md skips; not file-mention walk" {
    var buf: [walk_argv_len][]const u8 = undefined;
    const argv = unixWalkArgvFor("/tmp/faku-skills", &buf);
    try std.testing.expectEqual(@as(usize, unix_walk_argv_len), argv.len);
    try std.testing.expectEqualStrings(sh_bin, argv[0]);
    try std.testing.expectEqualStrings("-c", argv[1]);
    try std.testing.expectEqualStrings(util.fx_ask_chdir_script, argv[2]);
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
    try std.testing.expect(scriptHas(argv[7], disabled_skill_filename));
    try std.testing.expect(!scriptHas(argv[7], file_mention.find_dot_star));
    inline for (walk_skip_names) |name| {
        try std.testing.expect(scriptHas(argv[7], name));
    }
    try std.testing.expect(!isSkillsWalkArgv(&.{ find_bin, find_skills_script }));
    var mention_buf: [file_mention.walk_argv_len][]const u8 = undefined;
    try std.testing.expect(!isSkillsWalkArgv(file_mention.unixWalkArgvFor("/tmp/faku-skills", &mention_buf)));
    try std.testing.expect(skills_key_first > file_mention.file_mention_key_first);
    try std.testing.expect(skills_key_first > 520);
    try std.testing.expect(skills_rename_key_first > skills_key_first);
    try std.testing.expect(skills_rename_key_first > 540);
    try std.testing.expect(skills_rename_key_first < 600);
}

test "windows walk argv is powershell scriptblock -Args PATH; descends into hidden dirs" {
    var buf: [walk_argv_len][]const u8 = undefined;
    const cwd = "C:\\Users\\me\\proj";
    const argv = windowsWalkArgvFor(cwd, &buf);
    try std.testing.expectEqual(@as(usize, windows_walk_argv_len), argv.len);
    try std.testing.expect(argv.len <= 16);
    try std.testing.expectEqualStrings(powershell_bin, argv[0]);
    try std.testing.expectEqualStrings(powershell_noprofile, argv[1]);
    try std.testing.expectEqualStrings(powershell_command, argv[2]);
    try std.testing.expectEqualStrings(powershell_skills_walk_script, argv[3]);
    try std.testing.expectEqualStrings(powershell_args_flag, argv[4]);
    try std.testing.expectEqualStrings(cwd, argv[5]);
    try std.testing.expect(isSkillsWalkArgv(argv));
    try std.testing.expect(!file_mention.isWalkArgv(argv));
    try std.testing.expect(!isSkillsRenameArgv(argv));
    try std.testing.expect(std.mem.indexOf(u8, argv[3], cwd) == null);
    try std.testing.expect(scriptHas(argv[3], "$args[0]"));
    try std.testing.expect(scriptHas(argv[3], find_maxdepth));
    try std.testing.expect(scriptHas(argv[3], max_skills_s));
    try std.testing.expect(scriptHas(argv[3], skill_filename));
    try std.testing.expect(scriptHas(argv[3], disabled_skill_filename));
    try std.testing.expect(!scriptHas(argv[3], "StartsWith('.'"));
    try std.testing.expect(!std.mem.eql(u8, argv[3], file_mention.powershell_walk_script));
    inline for (walk_skip_names) |name| {
        try std.testing.expect(scriptHas(argv[3], name));
    }
    try std.testing.expect(!isSkillsWalkArgv(&.{
        powershell_bin,
        powershell_noprofile,
        powershell_command,
        "Get-Date",
        powershell_args_flag,
        cwd,
    }));
    var mention_buf: [file_mention.walk_argv_len][]const u8 = undefined;
    try std.testing.expect(!isSkillsWalkArgv(file_mention.windowsWalkArgvFor(cwd, &mention_buf)));
}

test "host argvFor and renameArgvFor match the process OS" {
    var walk_buf: [walk_argv_len][]const u8 = undefined;
    const walk_argv = argvFor("/tmp/faku-skills", &walk_buf);
    try std.testing.expect(isSkillsWalkArgv(walk_argv));
    var rename_buf: [rename_argv_len][]const u8 = undefined;
    const rename_argv = renameArgvFor("/tmp/faku-skill-dir", false, &rename_buf);
    try std.testing.expect(isSkillsRenameArgv(rename_argv));
    try std.testing.expect(!isSkillsWalkArgv(rename_argv));
    try std.testing.expect(!isSkillsRenameArgv(walk_argv));
    switch (builtin.os.tag) {
        .windows => {
            try std.testing.expectEqualStrings(powershell_bin, walk_argv[0]);
            try std.testing.expectEqualStrings(powershell_args_flag, walk_argv[4]);
            try std.testing.expectEqualStrings(powershell_bin, rename_argv[0]);
            try std.testing.expectEqualStrings(powershell_args_flag, rename_argv[4]);
        },
        else => {
            try std.testing.expectEqualStrings(sh_bin, walk_argv[0]);
            try std.testing.expectEqualStrings(find_skills_script, walk_argv[7]);
            try std.testing.expectEqualStrings(sh_bin, rename_argv[0]);
            try std.testing.expectEqualStrings(mv_bin, rename_argv[5]);
        },
    }
}

test "scanSupported is true on macOS Linux Windows" {
    try std.testing.expect(scanSupportedOn(.linux));
    try std.testing.expect(scanSupportedOn(.macos));
    try std.testing.expect(scanSupportedOn(.windows));
    try std.testing.expect(scanSupported());
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
    try std.testing.expect(cachedEnabled(&model, 0));
    try std.testing.expectEqualStrings("skills/other/SKILL.md", cachedPath(&model, 1));
    try std.testing.expectEqualStrings("other", cachedName(&model, 1));
    try std.testing.expectEqualStrings("SKILL.md", cachedPath(&model, 2));
    try std.testing.expectEqualStrings(skill_fallback_name, cachedName(&model, 2));
    try std.testing.expectEqualStrings("demo", parentDirName(".cursor/skills/demo/SKILL.md"));
    try std.testing.expectEqualStrings("", parentDirName("SKILL.md"));
    try std.testing.expectEqualStrings("demo", displayName(".cursor/skills/demo/SKILL.md", ""));
    try std.testing.expectEqualStrings("from-yaml", displayName(".cursor/skills/demo/SKILL.md", "from-yaml"));

    var overflow: [max_skills * 32 + 16]u8 = undefined;
    var n: usize = 0;
    var i: usize = 0;
    while (i < max_skills + 4) : (i += 1) {
        const piece = try std.fmt.bufPrint(overflow[n..], "skills/x{d}/SKILL.md\n", .{i});
        n += piece.len;
    }
    clearCache(&model);
    applyStdoutPaths(&model, overflow[0..n]);
    try std.testing.expectEqual(@as(u32, max_skills), cachedCount(&model));
}

test "emptyHint follows Appearance language; No skills found with a project" {
    const testing = std.testing;
    var model = Model{};
    try testing.expectEqualStrings("Open a project", emptyHint(&model));
    try testing.expectEqualStrings(open_project, emptyHint(&model));
    try testing.expectEqualStrings("Open a project", i18n.skillsEmptyChromeFor(.english, "").open_project);
    try testing.expectEqualStrings("No skills found", no_skills_found);

    model.language_preference = .simplified_chinese;
    try testing.expectEqualStrings("打开项目", emptyHint(&model));
    model.language_preference = .japanese;
    try testing.expectEqualStrings("プロジェクトを開く", emptyHint(&model));
    model.language_preference = .english;
    model.setSystemLocaleId("ja_JP.UTF-8");
    try testing.expectEqualStrings("Open a project", emptyHint(&model));
    model.language_preference = .system;
    try testing.expectEqualStrings("プロジェクトを開く", emptyHint(&model));
    model.setSystemLocaleId("zh_CN.UTF-8");
    try testing.expectEqualStrings("打开项目", emptyHint(&model));
    model.setSystemLocaleId("");
    try testing.expectEqualStrings("Open a project", emptyHint(&model));

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const root = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-skills-empty", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(testing.io, root);
    model.store_io = testing.io;
    model.setLastProjectPath(root);
    model.language_preference = .english;
    try testing.expectEqualStrings("No skills found", emptyHint(&model));
    model.language_preference = .simplified_chinese;
    try testing.expectEqualStrings("未找到技能", emptyHint(&model));
    model.language_preference = .japanese;
    try testing.expectEqualStrings("スキルが見つかりません", emptyHint(&model));
    model.language_preference = .english;
    model.setSystemLocaleId("zh_CN.UTF-8");
    try testing.expectEqualStrings("No skills found", emptyHint(&model));
    model.language_preference = .system;
    try testing.expectEqualStrings("未找到技能", emptyHint(&model));
    model.setSystemLocaleId("ja_JP.UTF-8");
    try testing.expectEqualStrings("スキルが見つかりません", emptyHint(&model));
    model.skill_key = 1;
    try testing.expectEqualStrings("", emptyHint(&model));
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

test "Page includes appearance, usage, and computer_use; default stays general" {
    var model = Model{};
    try std.testing.expectEqual(Page.general, model.settings_page);
    model.settings_page = .appearance;
    try std.testing.expectEqual(Page.appearance, model.settings_page);
    try std.testing.expect(model.settings_page != .providers);
    try std.testing.expect(model.settings_page != .skills);
    try std.testing.expect(model.settings_page != .usage);
    try std.testing.expect(model.settings_page != .computer_use);
    model.settings_page = .usage;
    try std.testing.expectEqual(Page.usage, model.settings_page);
    try std.testing.expect(model.settings_page != .appearance);
    try std.testing.expect(model.settings_page != .general);
    model.settings_page = .computer_use;
    try std.testing.expectEqual(Page.computer_use, model.settings_page);
    try std.testing.expect(model.settings_page != .usage);
    try std.testing.expect(model.settings_page != .general);
}

test "Page persistName and fromPersist roundtrip; missing or unknown is general" {
    try std.testing.expectEqualStrings("general", Page.general.persistName());
    try std.testing.expectEqualStrings("appearance", Page.appearance.persistName());
    try std.testing.expectEqualStrings("providers", Page.providers.persistName());
    try std.testing.expectEqualStrings("skills", Page.skills.persistName());
    try std.testing.expectEqualStrings("usage", Page.usage.persistName());
    try std.testing.expectEqualStrings("computer_use", Page.computer_use.persistName());
    try std.testing.expectEqual(Page.general, Page.fromPersist(""));
    try std.testing.expectEqual(Page.general, Page.fromPersist("nope"));
    try std.testing.expectEqual(Page.general, Page.fromPersist("General"));
    try std.testing.expectEqual(Page.general, Page.fromPersist("computer-use"));
    try std.testing.expectEqual(Page.appearance, Page.fromPersist("appearance"));
    try std.testing.expectEqual(Page.providers, Page.fromPersist("providers"));
    try std.testing.expectEqual(Page.skills, Page.fromPersist("skills"));
    try std.testing.expectEqual(Page.usage, Page.fromPersist("usage"));
    try std.testing.expectEqual(Page.computer_use, Page.fromPersist("computer_use"));
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

test "path helpers detect enabled from filename; isSkillMdPath accepts both; displayName works for .disabled" {
    try std.testing.expect(isSkillMdPath("SKILL.md"));
    try std.testing.expect(isSkillMdPath("skills/demo/SKILL.md"));
    try std.testing.expect(isSkillMdPath("./.cursor/skills/demo/SKILL.md.disabled"));
    try std.testing.expect(isSkillMdPath("SKILL.md.disabled"));
    try std.testing.expect(!isSkillMdPath("skill.md"));
    try std.testing.expect(!isSkillMdPath("SKILL.md.bak"));
    try std.testing.expect(!isSkillMdPath("README.md"));
    try std.testing.expect(skillEnabledFromPath("skills/demo/SKILL.md"));
    try std.testing.expect(!skillEnabledFromPath("skills/demo/SKILL.md.disabled"));
    try std.testing.expect(!skillEnabledFromPath("SKILL.md.disabled"));
    try std.testing.expectEqualStrings("demo", parentDirName("skills/demo/SKILL.md.disabled"));
    try std.testing.expectEqualStrings("demo", displayName("skills/demo/SKILL.md.disabled", ""));
    try std.testing.expectEqualStrings("from-yaml", displayName("skills/demo/SKILL.md.disabled", "from-yaml"));
    try std.testing.expectEqualStrings(skill_fallback_name, displayName("SKILL.md.disabled", ""));
    try std.testing.expectEqualStrings("skills/demo", skillDirKey("skills/demo/SKILL.md.disabled"));
    try std.testing.expectEqualStrings("", skillDirKey("SKILL.md"));
    try std.testing.expectEqualStrings("", skillDirKey("SKILL.md.disabled"));
    try std.testing.expect(isSkillMdPath(".cursor\\skills\\demo\\SKILL.md"));
    try std.testing.expect(isSkillMdPath(".cursor\\skills\\demo\\SKILL.md.disabled"));
    try std.testing.expect(skillEnabledFromPath(".cursor\\skills\\demo\\SKILL.md"));
    try std.testing.expect(!skillEnabledFromPath(".cursor\\skills\\demo\\SKILL.md.disabled"));
    try std.testing.expectEqualStrings("demo", parentDirName(".cursor\\skills\\demo\\SKILL.md"));
    try std.testing.expectEqualStrings(".cursor\\skills\\demo", skillDirKey(".cursor\\skills\\demo\\SKILL.md"));
}

test "rename argv enable and disable round-trip; not the find walk" {
    var disable_buf: [rename_argv_len][]const u8 = undefined;
    const disable = unixRenameArgvFor("/tmp/faku-skill-dir", false, &disable_buf);
    try std.testing.expect(isSkillsRenameArgv(disable));
    try std.testing.expect(!isSkillsWalkArgv(disable));
    try std.testing.expectEqual(@as(usize, unix_rename_argv_len), disable.len);
    try std.testing.expectEqualStrings(sh_bin, disable[0]);
    try std.testing.expectEqualStrings(util.fx_ask_chdir_script, disable[2]);
    try std.testing.expectEqualStrings("/tmp/faku-skill-dir", disable[4]);
    try std.testing.expectEqualStrings(mv_bin, disable[5]);
    try std.testing.expectEqualStrings(mv_end_of_options, disable[6]);
    try std.testing.expectEqualStrings(skill_filename, disable[7]);
    try std.testing.expectEqualStrings(disabled_skill_filename, disable[8]);

    var enable_buf: [rename_argv_len][]const u8 = undefined;
    const enable = unixRenameArgvFor("/tmp/faku-skill-dir", true, &enable_buf);
    try std.testing.expect(isSkillsRenameArgv(enable));
    try std.testing.expect(!isSkillsWalkArgv(enable));
    try std.testing.expectEqualStrings(disabled_skill_filename, enable[7]);
    try std.testing.expectEqualStrings(skill_filename, enable[8]);
    try std.testing.expect(!isSkillsRenameArgv(&.{ mv_bin, skill_filename, disabled_skill_filename }));
    var walk_buf: [walk_argv_len][]const u8 = undefined;
    try std.testing.expect(!isSkillsRenameArgv(unixWalkArgvFor("/tmp/faku-skills", &walk_buf)));
}

test "windows rename argv enable and disable round-trip; paths stay -Args slots" {
    var disable_buf: [rename_argv_len][]const u8 = undefined;
    const cwd = "C:\\Users\\me\\proj\\.cursor\\skills\\demo";
    const disable = windowsRenameArgvFor(cwd, false, &disable_buf);
    try std.testing.expectEqual(@as(usize, windows_rename_argv_len), disable.len);
    try std.testing.expect(disable.len <= 16);
    try std.testing.expect(isSkillsRenameArgv(disable));
    try std.testing.expect(!isSkillsWalkArgv(disable));
    try std.testing.expectEqualStrings(powershell_bin, disable[0]);
    try std.testing.expectEqualStrings(powershell_noprofile, disable[1]);
    try std.testing.expectEqualStrings(powershell_command, disable[2]);
    try std.testing.expectEqualStrings(powershell_skills_rename_script, disable[3]);
    try std.testing.expectEqualStrings(powershell_args_flag, disable[4]);
    try std.testing.expectEqualStrings(cwd, disable[5]);
    try std.testing.expectEqualStrings(skill_filename, disable[6]);
    try std.testing.expectEqualStrings(disabled_skill_filename, disable[7]);
    try std.testing.expect(std.mem.indexOf(u8, disable[3], cwd) == null);
    try std.testing.expect(scriptHas(disable[3], "$args[0]"));
    try std.testing.expect(scriptHas(disable[3], "$args[1]"));
    try std.testing.expect(scriptHas(disable[3], "$args[2]"));
    try std.testing.expect(scriptHas(disable[3], "Move-Item"));
    try std.testing.expect(scriptHas(disable[3], "-LiteralPath"));

    var enable_buf: [rename_argv_len][]const u8 = undefined;
    const enable = windowsRenameArgvFor(cwd, true, &enable_buf);
    try std.testing.expect(isSkillsRenameArgv(enable));
    try std.testing.expect(!isSkillsWalkArgv(enable));
    try std.testing.expectEqualStrings(disabled_skill_filename, enable[6]);
    try std.testing.expectEqualStrings(skill_filename, enable[7]);
    try std.testing.expect(std.mem.indexOf(u8, enable[3], cwd) == null);
    try std.testing.expect(!isSkillsRenameArgv(&.{
        powershell_bin,
        powershell_noprofile,
        powershell_command,
        "Rename-Item",
        powershell_args_flag,
        cwd,
        skill_filename,
        disabled_skill_filename,
    }));
    var walk_buf: [walk_argv_len][]const u8 = undefined;
    try std.testing.expect(!isSkillsRenameArgv(windowsWalkArgvFor(cwd, &walk_buf)));
}

test "applyStdoutPaths prefers live SKILL.md when both live and disabled share a dir" {
    var model = Model{};
    applyStdoutPaths(&model, "skills/demo/SKILL.md.disabled\nskills/demo/SKILL.md\n");
    try std.testing.expectEqual(@as(u32, 1), cachedCount(&model));
    try std.testing.expectEqualStrings("skills/demo/SKILL.md", cachedPath(&model, 0));
    try std.testing.expect(cachedEnabled(&model, 0));

    clearCache(&model);
    applyStdoutPaths(&model, "skills/demo/SKILL.md\nskills/demo/SKILL.md.disabled\n");
    try std.testing.expectEqual(@as(u32, 1), cachedCount(&model));
    try std.testing.expectEqualStrings("skills/demo/SKILL.md", cachedPath(&model, 0));
    try std.testing.expect(cachedEnabled(&model, 0));

    clearCache(&model);
    applyStdoutPaths(&model, "skills/off/SKILL.md.disabled\nskills/on/SKILL.md\nSKILL.md.disabled\n");
    try std.testing.expectEqual(@as(u32, 3), cachedCount(&model));
    try std.testing.expectEqualStrings("skills/off/SKILL.md.disabled", cachedPath(&model, 0));
    try std.testing.expect(!cachedEnabled(&model, 0));
    try std.testing.expectEqualStrings("off", cachedName(&model, 0));
    try std.testing.expect(cachedEnabled(&model, 1));
    try std.testing.expectEqualStrings("SKILL.md.disabled", cachedPath(&model, 2));
    try std.testing.expect(!cachedEnabled(&model, 2));

    clearCache(&model);
    applyStdoutPaths(&model, ".cursor\\skills\\demo\\SKILL.md.disabled\n.cursor\\skills\\demo\\SKILL.md\n");
    try std.testing.expectEqual(@as(u32, 1), cachedCount(&model));
    try std.testing.expectEqualStrings(".cursor/skills/demo/SKILL.md", cachedPath(&model, 0));
    try std.testing.expect(cachedEnabled(&model, 0));
}

test "toggleSkillEnabled one-shots mv; success refreshes find; fail and stale keep cache" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const root = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-skills-toggle", .{tmp.sub_path[0..]});
    var skill_dir_buf: [256]u8 = undefined;
    const skill_dir = try std.fmt.bufPrint(&skill_dir_buf, "{s}/skills/demo", .{root});
    try std.Io.Dir.cwd().createDirPath(testing.io, skill_dir);
    var file_buf: [256]u8 = undefined;
    const file_path = try std.fmt.bufPrint(&file_buf, "{s}/SKILL.md", .{skill_dir});
    try std.Io.Dir.cwd().writeFile(testing.io, .{
        .sub_path = file_path,
        .data =
        \\---
        \\name: toggle-me
        \\---
        \\
        \\Body
        \\
        ,
    });

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = testing.io;
    model.setLastProjectPath(root);
    writeFixed(&model.skill_probe_path_storage, &model.skill_probe_path_len, root);
    applyStdoutPaths(&model, "skills/demo/SKILL.md\n");
    selectSkill(&model, 1);
    try testing.expect(cachedEnabled(&model, 0));
    try testing.expectEqualStrings("Body", model.skill_body_storage[0..model.skill_body_len]);

    toggleSkillEnabled(&model, &fx);
    try testing.expect(model.skill_rename_key >= skills_rename_key_first);
    const rename_key = model.skill_rename_key;
    var i: usize = 0;
    var spawn = fx.pendingSpawnAt(0);
    while (spawn) |item| : (i += 1) {
        if (item.key == rename_key and isSkillsRenameArgv(item.argv)) break;
        spawn = fx.pendingSpawnAt(i + 1);
    }
    try testing.expect(spawn != null);
    try testing.expectEqualStrings(skill_dir, spawn.?.argv[4]);
    try testing.expectEqualStrings(skill_filename, spawn.?.argv[7]);
    try testing.expectEqualStrings(disabled_skill_filename, spawn.?.argv[8]);
    try testing.expectEqual(@as(u32, 1), cachedCount(&model));

    handleRenameExit(&model, &fx, .{ .key = rename_key + 9, .reason = .exited, .code = 0 });
    try testing.expectEqual(rename_key, model.skill_rename_key);
    try testing.expectEqual(@as(u32, 1), cachedCount(&model));

    handleRenameExit(&model, &fx, .{ .key = rename_key, .reason = .exited, .code = 1 });
    try testing.expectEqual(@as(u64, 0), model.skill_rename_key);
    try testing.expectEqual(@as(u32, 1), cachedCount(&model));
    try testing.expect(cachedEnabled(&model, 0));

    toggleSkillEnabled(&model, &fx);
    const retry_key = model.skill_rename_key;
    try testing.expect(retry_key > rename_key);
    handleRenameExit(&model, &fx, .{ .key = retry_key, .reason = .exited, .code = 0 });
    try testing.expectEqual(@as(u64, 0), model.skill_rename_key);
    try testing.expectEqual(@as(u32, 0), cachedCount(&model));
    try testing.expect(model.skill_key >= skills_key_first);
    i = 0;
    spawn = fx.pendingSpawnAt(0);
    while (spawn) |item| : (i += 1) {
        if (item.key == model.skill_key and isSkillsWalkArgv(item.argv)) break;
        spawn = fx.pendingSpawnAt(i + 1);
    }
    try testing.expect(spawn != null);

    toggleSkillEnabled(&model, &fx);
    try testing.expectEqual(@as(u64, 0), model.skill_rename_key);
}

test "hydrate name from SKILL.md.disabled frontmatter" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const root = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-skills-disabled-name", .{tmp.sub_path[0..]});
    var skill_dir_buf: [256]u8 = undefined;
    const skill_dir = try std.fmt.bufPrint(&skill_dir_buf, "{s}/skills/named", .{root});
    try std.Io.Dir.cwd().createDirPath(testing.io, skill_dir);
    var file_buf: [256]u8 = undefined;
    const file_path = try std.fmt.bufPrint(&file_buf, "{s}/SKILL.md.disabled", .{skill_dir});
    try std.Io.Dir.cwd().writeFile(testing.io, .{
        .sub_path = file_path,
        .data =
        \\---
        \\name: pretty-disabled
        \\---
        \\
        \\Still readable.
        \\
        ,
    });

    var model = Model{};
    model.store_io = testing.io;
    writeFixed(&model.skill_probe_path_storage, &model.skill_probe_path_len, root);
    applyStdoutPaths(&model, "skills/named/SKILL.md.disabled\n");
    try std.testing.expectEqual(@as(u32, 1), cachedCount(&model));
    try std.testing.expectEqualStrings("pretty-disabled", cachedName(&model, 0));
    try std.testing.expect(!cachedEnabled(&model, 0));

    selectSkill(&model, 1);
    try std.testing.expectEqualStrings("Still readable.", model.skill_body_storage[0..model.skill_body_len]);
}

test "toggleSkillEnabled missing file keeps cache and does not spawn" {
    const testing = std.testing;
    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = testing.io;
    writeFixed(&model.skill_probe_path_storage, &model.skill_probe_path_len, "/tmp/faku-skills-missing");
    applyStdoutPaths(&model, "skills/gone/SKILL.md\n");
    selectSkill(&model, 1);
    const before = fx.pendingSpawnCount();
    toggleSkillEnabled(&model, &fx);
    try testing.expectEqual(@as(u64, 0), model.skill_rename_key);
    try testing.expectEqual(before, fx.pendingSpawnCount());
    try testing.expectEqual(@as(u32, 1), cachedCount(&model));
}

test "joinProbeRelpath and absSkillParent tolerate Windows roots and mixed separators" {
    var buf: [128]u8 = undefined;
    try std.testing.expectEqualStrings(
        "C:/Users/me/proj/.cursor/skills/demo/SKILL.md",
        joinProbeRelpath("C:\\Users\\me\\proj", ".cursor/skills/demo/SKILL.md", &buf).?,
    );
    try std.testing.expectEqualStrings(
        "C:/Users/me/proj/.cursor/skills/demo/SKILL.md",
        joinProbeRelpath("C:/Users/me/proj/", "/.cursor/skills/demo/SKILL.md", &buf).?,
    );
    try std.testing.expectEqualStrings(
        "C:/Users/me/proj/.cursor/skills/demo",
        absSkillParent("C:\\Users\\me\\proj", ".cursor/skills/demo/SKILL.md", &buf).?,
    );
    try std.testing.expectEqualStrings(
        "C:/Users/me/proj",
        absSkillParent("C:\\Users\\me\\proj", "SKILL.md", &buf).?,
    );
    try std.testing.expectEqualStrings(
        "C:/Users/me/proj/.cursor/skills/demo",
        absSkillParent("C:\\Users\\me\\proj\\", ".cursor\\skills\\demo\\SKILL.md.disabled", &buf).?,
    );
}

test "composer $ insert lists enabled skills only" {
    const testing = std.testing;
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var model = Model{};
    applyStdoutPaths(&model, "skills/off/SKILL.md.disabled\nskills/on/SKILL.md\n");
    try testing.expectEqual(@as(u32, 2), cachedCount(&model));
    try testing.expect(!cachedEnabled(&model, 0));
    try testing.expect(cachedEnabled(&model, 1));

    model.draft_buffer.set("$");
    const rows = model.skill_insert_rows(arena);
    try testing.expectEqual(@as(usize, 1), rows.len);
    try testing.expectEqualStrings("on", rows[0].name);
    try testing.expectEqualStrings("skills/on/SKILL.md", rows[0].path);
    try testing.expectEqual(@as(u32, 2), rows[0].id);

    model.draft_buffer.set("$off");
    try testing.expectEqual(@as(usize, 0), model.skill_insert_rows(arena).len);
}

fn writeTestSkill(io: std.Io, dir: []const u8, name: []const u8, body: []const u8, disabled: bool) !void {
    try std.Io.Dir.cwd().createDirPath(io, dir);
    var file_buf: [256]u8 = undefined;
    const filename = if (disabled) disabled_skill_filename else skill_filename;
    const file_path = try std.fmt.bufPrint(&file_buf, "{s}/{s}", .{ dir, filename });
    var data_buf: [512]u8 = undefined;
    const data = try std.fmt.bufPrint(&data_buf, "---\nname: {s}\n---\n\n{s}\n", .{ name, body });
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = file_path, .data = data });
}

test "expandPrompt no-op without $ tokens or matching enabled skills" {
    const testing = std.testing;
    var model = Model{};
    var out: [model_exports.max_body]u8 = undefined;
    try testing.expectEqualStrings("just a prompt", expandPrompt(&model, "just a prompt", &out));
    try testing.expectEqualStrings("price$", expandPrompt(&model, "price$", &out));
    try testing.expectEqualStrings("$unknown do it", expandPrompt(&model, "$unknown do it", &out));
}

test "expandPrompt prepends enabled bodies in first-occurrence order; dedupes; skips disabled and missing" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const root = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-skills-expand", .{tmp.sub_path[0..]});
    var alpha_dir_buf: [256]u8 = undefined;
    const alpha_dir = try std.fmt.bufPrint(&alpha_dir_buf, "{s}/skills/alpha", .{root});
    var beta_dir_buf: [256]u8 = undefined;
    const beta_dir = try std.fmt.bufPrint(&beta_dir_buf, "{s}/skills/beta", .{root});
    var off_dir_buf: [256]u8 = undefined;
    const off_dir = try std.fmt.bufPrint(&off_dir_buf, "{s}/skills/off", .{root});
    try writeTestSkill(testing.io, alpha_dir, "alpha", "Alpha body.", false);
    try writeTestSkill(testing.io, beta_dir, "beta", "Beta body.", false);
    try writeTestSkill(testing.io, off_dir, "off", "Hidden body.", true);

    var model = Model{};
    model.store_io = testing.io;
    writeFixed(&model.skill_probe_path_storage, &model.skill_probe_path_len, root);
    applyStdoutPaths(&model, "skills/alpha/SKILL.md\nskills/beta/SKILL.md\nskills/off/SKILL.md.disabled\nskills/gone/SKILL.md\n");
    try testing.expectEqualStrings("alpha", cachedName(&model, 0));
    try testing.expectEqualStrings("beta", cachedName(&model, 1));
    try testing.expectEqualStrings("off", cachedName(&model, 2));
    try testing.expect(!cachedEnabled(&model, 2));

    var out: [model_exports.max_body]u8 = undefined;
    const expanded = expandPrompt(&model, "$beta then $alpha and $beta again plus $off and $gone", &out);
    try testing.expectEqualStrings(
        \\### Skill: beta
        \\Beta body.
        \\
        \\### Skill: alpha
        \\Alpha body.
        \\
        \\$beta then $alpha and $beta again plus $off and $gone
    , expanded);

    const missing_only = expandPrompt(&model, "$gone only", &out);
    try testing.expectEqualStrings("$gone only", missing_only);

    const disabled_only = expandPrompt(&model, "$off please", &out);
    try testing.expectEqualStrings("$off please", disabled_only);
}
