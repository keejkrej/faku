//! Settings Skills + composer `$` insert / `/` slash rows: bounded
//! `SKILL.md` scan plus first-cut enable/disable via daemon
//! `setSkillsEnabled` (ack) or on-disk rename fallback, and first-cut
//! Delete via daemon `trashSkills` (ack) or a Faku-side permanent
//! directory-remove fallback.
//!
//! Native has no FS watcher. Unix one-shots a packed `find` for
//! `SKILL.md` and `SKILL.md.disabled` (Waku `DISABLED_SKILL_FILE`)
//! through the same `/bin/sh -c` chdir workaround `fx ask` uses
//! (`fx_ask_chdir_script`). Windows cannot use `/bin/sh` or `find`:
//! `powershell.exe -NoProfile -Command {…} -Args <project_path>`
//! (`$args[0]`; same skip names / depth 8 / cap `max_skills`). Does
//! **not** prune `.*` — project skills live under `.cursor/skills` /
//! `.agents/skills`. Settings → Skills still `refresh`s on page open.
//! Composer `$` / `/` slash-prefix calls `ensureScanned` even when
//! `settings_page != .skills`. Scan root is the selected session
//! `project_path` when that directory exists, else settings
//! `last_project_path`. Skip `node_modules` / `target` / `dist` /
//! `build` / `out` / `vendor` / `__pycache__`. Cap 64 rows. Name comes
//! from YAML `name:` frontmatter when present, else the parent folder.
//! YAML `description:` (plain / quoted, leading `---` fence) is skill
//! data for Settings list / composer `$` insert / `/` skill-sourced
//! slash rows — not i18n; empty when missing. Cap `max_skill_description`.
//! Body read still uses the actual file on disk (including
//! `.disabled`). When both live and disabled exist in the same dir,
//! live wins (one row). Settings selecting a row shows the body with
//! frontmatter stripped. Enable/Disable prefers daemon
//! `setSkillsEnabled` when an address is set; fallback is a
//! Faku-side one-shot rename in that skill directory (`SKILL.md` ↔
//! `SKILL.md.disabled`):
//! Unix `mv --` after the chdir wrapper; Windows powershell
//! Move-Item with argv slots for skill-dir / from / to (never
//! interpolated into `-Command`). Tools discover skills by exact
//! filename so the rename hides/shows the skill from fx and peers
//! the same as Waku. Composer `$` inserts `$name ` for **enabled**
//! skills only. Composer `/` slash card (`command_rows`) lists ACP
//! `available_commands` first, then enabled `skill_store` rows
//! whose names do not collide (ACP name wins). Skill-sourced insert
//! writes `/name ` (ids `skillId + max_available_commands`). Slash
//! prefix triggers `ensureScanned`. Send prepends stripped
//! `SKILL.md` bodies for `$name` and skill-matching `/name` tokens
//! (enabled rows only; missing/unreadable omit that block) onto the
//! prompt that `startPrompt` ships to every provider and stores as
//! the user turn; untitled titles still use the original draft.
//! Runtime-only (not `sessions.json`). When
//! `WAKU_DAEMON_ADDRESS` or persisted `last_daemon_address` is set,
//! refresh / ensure prefer one-shot `faku daemon-proxy` hello +
//! `loadSkills` (one `[projectName, projectPath]` tuple for the
//! current probe path). Ok `skillsCatalog` replaces `skill_store`.
//! Unknown-command / parse / sidecar / empty / Native 4 KiB overflow
//! / no address keep today's local `find` / powershell walk. Own
//! daemon spawn key (`next_daemon_key` on `daemon_load_skills_key`)
//! — not the find-walk band (530+) or rename band (580+).
//! Enable/Disable prefers hello + `setSkillsEnabled` when a daemon
//! address is set (`dirs` = `[absSkillParent]`, `enabled` = !current;
//! own `next_daemon_key` on `daemon_set_skills_enabled_key`). Ok
//! Ack then `refresh`. Unknown-command / parse / sidecar / Native
//! 4 KiB overflow / no address keep today's Faku-side `SKILL.md` ↔
//! `SKILL.md.disabled` rename. In-flight rename,
//! `setSkillsEnabled`, or `trashSkills` fail closed. First-cut Delete
//! prefers hello + `trashSkills` when a daemon address is set
//! (`dirs` = `[absSkillParent]`; own `next_daemon_key` on
//! `daemon_trash_skills_key`). Ok Ack then clear arming and
//! `refresh`. Unknown-command / parse / sidecar / Native 4 KiB
//! overflow / no address keep a Faku-side **permanent** one-shot
//! remove of that absolute skill directory only (not OS Trash /
//! Recycle Bin — Faku has no trash crate): Unix `/bin/sh -c` chdir
//! wrapper + `rm -rf --` with the skill dir as an argv slot; Windows
//! powershell `Remove-Item -LiteralPath … -Recurse -Force` with argv
//! slots. Guard: only remove when the path is non-empty, absolute,
//! and looks like the selected skill's parent from cache — fail
//! closed otherwise. Empty-state Open a
//! project / No skills found follow `i18n.SkillsEmptyChrome`
//! (distinct from FilterChrome / RightPanelChrome; composer `$`
//! insert empty reuses the same hint). Enable / Disable / Disabled
//! badge follow `i18n.SkillsEnableChrome` (distinct from
//! ProvidersChrome). Enable/Disable rename-fail window_status
//! Could not update skill. follows `i18n.SkillsEnableStatusChrome`
//! (distinct from SkillsEnableChrome Enable / Disable / Disabled
//! and from SkillsTrashStatusChrome). Delete / Confirm delete follow
//! `i18n.SkillsTrashChrome` (distinct from SkillsEnableChrome /
//! SkillsEmptyChrome). Delete miss / remove-fail window_status
//! Could not delete skill. follows `i18n.SkillsTrashStatusChrome`
//! (distinct from SkillsTrashChrome Delete / Confirm delete).
//! Daemon `trashSkills` is best-effort; the fallback is a
//! permanent directory remove, not OS Trash. First-cut Open in
//! editor for the selected skill calls
//! `open_editor.startOpenEditorAt` at the absolute `SKILL.md` /
//! `SKILL.md.disabled` path from `joinProbeRelpath` (same Cursor /
//! code / `open -a` sidecar as Files preview). Fail closed with no
//! selection / empty / invalid path. Label reuses
//! `i18n.FilePreviewChrome.open_in_editor` via Model
//! `skill_open_in_editor_label`. Not an embedded editor, not
//! `open_in_app`, not a daemon method. First-cut Reveal for the
//! selected skill calls `reveal_folder.startRevealPath` at the
//! absolute `SKILL.md` / `SKILL.md.disabled` path from
//! `selectedSkillAbsPath` (parent directory via Finder / xdg-open /
//! explorer — same sidecar as composer Reveal folder). Fail closed
//! with no selection / empty / unresolved path (no spawn).
//! `.missing_bin` paints `hostMissingStatusFor`. Label reuses
//! `i18n.ComposerProjectChrome.reveal_folder` via Model
//! `skill_reveal_label`. Not Open in editor, not copy path, not a
//! daemon method. Not a Native FS API.
//! app.zon already includes windows.
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
const protocol = @import("protocol.zig");
const daemon_proxy = @import("daemon_proxy.zig");
const effect_keys = @import("effect_keys.zig");
const open_editor = @import("open_editor.zig");
const reveal_folder = @import("reveal_folder.zig");

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
/// One-shot Skills Delete `rm -rf` / Remove-Item fallback
/// (permanent directory remove, not OS Trash). Distinct from the
/// scan key (530+), rename (580+), Files Preview issue-link (540+),
/// and daemon `trashSkills` (`next_daemon_key`). Band is 590+.
pub const skills_remove_key_first: u64 = 590;

pub const max_skills: usize = 64;
pub const max_skills_s = std.fmt.comptimePrint("{d}", .{max_skills});
pub const max_skill_path: usize = 255;
pub const max_skill_name: usize = 64;
/// One-line UI cap for YAML `description:` (larger than name; not the body).
pub const max_skill_description: usize = 160;
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
pub const rm_bin = "rm";
pub const rm_rf_flag = "-rf";
pub const rm_end_of_options = "--";
/// English default for Enable/Disable rename-fail window_status.
/// Localized copy lives on `i18n.SkillsEnableStatusChrome.enable_failed`
/// via Model `skill_enable_failed_status`. Distinct from
/// SkillsEnableChrome Enable / Disable / Disabled.
pub const could_not_update_status = i18n.skillsEnableStatusChromeFor(.english, "").enable_failed;
/// English default for Delete miss / remove-fail window_status.
/// Localized copy lives on `i18n.SkillsTrashStatusChrome.delete_failed`
/// via Model `skill_delete_failed_status`. Distinct from
/// SkillsTrashChrome Delete / Confirm delete.
pub const could_not_delete_status = i18n.skillsTrashStatusChromeFor(.english, "").delete_failed;

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

/// Scriptblock + `$args[0]`: skill directory stays an argv slot after
/// `-Args` (never interpolated into `-Command`). Permanent
/// `Remove-Item -LiteralPath` recurse+force — not OS Recycle Bin.
/// Six argv slots.
pub const powershell_skills_remove_script =
    "{ $ErrorActionPreference='Stop'; Remove-Item -LiteralPath $args[0] -Recurse -Force }";

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
/// Unix `/bin/sh -c` chdir + `rm -rf --` skill-dir (9). Windows
/// powershell `-Command` + `-Args` skill-dir is 6; this is the spawn
/// buffer (max of the two). Native `max_effect_argv` is 16.
pub const remove_argv_len: usize = 9;
pub const unix_remove_argv_len: usize = 9;
pub const windows_remove_argv_len: usize = 6;

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
    description_storage: [max_skill_description]u8 = [_]u8{0} ** max_skill_description,
    description_len: usize = 0,
    /// `SKILL.md` = true; `SKILL.md.disabled` = false.
    enabled: bool = true,

    pub fn path(self: *const CachedSkill) []const u8 {
        return self.path_storage[0..self.path_len];
    }

    pub fn name(self: *const CachedSkill) []const u8 {
        return self.name_storage[0..self.name_len];
    }

    pub fn description(self: *const CachedSkill) []const u8 {
        return self.description_storage[0..self.description_len];
    }

    pub fn setPath(self: *CachedSkill, value: []const u8) void {
        writeFixed(&self.path_storage, &self.path_len, value);
        slashNormalizeInPlace(self.path_storage[0..self.path_len]);
    }

    pub fn setName(self: *CachedSkill, value: []const u8) void {
        writeFixed(&self.name_storage, &self.name_len, value);
    }

    pub fn setDescription(self: *CachedSkill, value: []const u8) void {
        writeFixed(&self.description_storage, &self.description_len, value);
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

/// `rm -rf -- <skill-dir>` after the chdir wrapper. The skill
/// directory is an argv slot — never interpolated into
/// `fx_ask_chdir_script`. Permanent remove, not OS Trash.
pub fn unixRemoveArgvFor(cwd: []const u8, dir: []const u8, buf: *[remove_argv_len][]const u8) []const []const u8 {
    buf.* = .{
        sh_bin,
        "-c",
        util.fx_ask_chdir_script,
        "sh",
        cwd,
        rm_bin,
        rm_rf_flag,
        rm_end_of_options,
        dir,
    };
    return buf[0..unix_remove_argv_len];
}

/// Windows: `powershell.exe -NoProfile -Command {scriptblock} -Args
/// <skill-dir>`. Path stays `$args[0]` — not interpolated into the
/// `-Command` body. Permanent `Remove-Item`, not Recycle Bin.
pub fn windowsRemoveArgvFor(dir: []const u8, buf: *[remove_argv_len][]const u8) []const []const u8 {
    buf[0] = powershell_bin;
    buf[1] = powershell_noprofile;
    buf[2] = powershell_command;
    buf[3] = powershell_skills_remove_script;
    buf[4] = powershell_args_flag;
    buf[5] = dir;
    return buf[0..windows_remove_argv_len];
}

pub fn removeArgvFor(cwd: []const u8, dir: []const u8, buf: *[remove_argv_len][]const u8) []const []const u8 {
    return switch (builtin.os.tag) {
        .windows => windowsRemoveArgvFor(dir, buf),
        else => unixRemoveArgvFor(cwd, dir, buf),
    };
}

fn isUnixSkillsRemoveArgv(argv: []const []const u8) bool {
    if (argv.len != unix_remove_argv_len) return false;
    if (!std.mem.eql(u8, argv[0], sh_bin)) return false;
    if (!std.mem.eql(u8, argv[1], "-c")) return false;
    if (!std.mem.eql(u8, argv[2], util.fx_ask_chdir_script)) return false;
    if (!std.mem.eql(u8, argv[5], rm_bin)) return false;
    if (!std.mem.eql(u8, argv[6], rm_rf_flag)) return false;
    if (!std.mem.eql(u8, argv[7], rm_end_of_options)) return false;
    return argv[8].len > 0;
}

fn isWindowsSkillsRemoveArgv(argv: []const []const u8) bool {
    if (argv.len != windows_remove_argv_len) return false;
    if (!std.mem.eql(u8, argv[0], powershell_bin)) return false;
    if (!std.mem.eql(u8, argv[1], powershell_noprofile)) return false;
    if (!std.mem.eql(u8, argv[2], powershell_command)) return false;
    if (!std.mem.eql(u8, argv[3], powershell_skills_remove_script)) return false;
    if (!std.mem.eql(u8, argv[4], powershell_args_flag)) return false;
    if (argv[5].len == 0) return false;
    if (!scriptHas(argv[3], "$args[0]")) return false;
    if (!scriptHas(argv[3], "Remove-Item")) return false;
    if (!scriptHas(argv[3], "-LiteralPath")) return false;
    if (!scriptHas(argv[3], "-Recurse")) return false;
    if (!scriptHas(argv[3], "-Force")) return false;
    return true;
}

pub fn isSkillsRemoveArgv(argv: []const []const u8) bool {
    return isUnixSkillsRemoveArgv(argv) or isWindowsSkillsRemoveArgv(argv);
}

/// Fail-closed guard for the permanent remove fallback. `dir` must be
/// non-empty, must not be `/` / `.` / `..`, must not contain a `..`
/// segment, and must contain the selected skill's parent dir from
/// cache (relative `skillDirKey`) as a path suffix. Absolute paths
/// preferred; nested relative paths (test zig-cache / unusual
/// relative `project_path`) are allowed when they still look like
/// that skill parent.
pub fn trashDirAllowed(dir: []const u8, parent_from_cache: []const u8) bool {
    if (dir.len == 0 or parent_from_cache.len == 0) return false;
    if (std.mem.eql(u8, dir, "/") or std.mem.eql(u8, dir, "\\")) return false;
    if (std.mem.eql(u8, dir, ".") or std.mem.eql(u8, dir, "..")) return false;
    if (std.mem.indexOf(u8, dir, "..") != null) return false;
    if (!pathEndsWithDir(dir, parent_from_cache)) return false;
    if (isAbsoluteSkillPath(dir) or std.fs.path.isAbsolute(dir)) return true;
    return std.mem.indexOfAny(u8, dir, "/\\") != null;
}

fn pathEndsWithDir(path: []const u8, dir: []const u8) bool {
    if (dir.len == 0 or path.len < dir.len) return false;
    if (!std.mem.endsWith(u8, path, dir)) return false;
    if (path.len == dir.len) return false;
    const sep = path[path.len - dir.len - 1];
    return sep == '/' or sep == '\\';
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

pub fn cachedDescription(model: *const Model, index: usize) []const u8 {
    if (index >= model.skill_count) return "";
    return model.skill_store[index].description();
}

pub fn cachedEnabled(model: *const Model, index: usize) bool {
    if (index >= model.skill_count) return false;
    return model.skill_store[index].enabled;
}

pub fn skillId(index: usize) u32 {
    return @intCast(index + 1);
}

/// Composer `/` slash-card id for a `skill_store` row. Offset by
/// `max_available_commands` so Native `insert_command:{c.id}` never
/// collides with ACP 1-based ids.
pub fn slashCommandId(index: usize) u32 {
    return skillId(index) + @as(u32, @intCast(model_exports.max_available_commands));
}

/// Inverse of `slashCommandId`. `null` when `id` is in the ACP band
/// (`1…max_available_commands`).
pub fn slashCommandIndex(id: u32) ?usize {
    const base = @as(u32, @intCast(model_exports.max_available_commands));
    if (id <= base) return null;
    return @as(usize, id - base - 1);
}

pub fn clearCache(model: *Model) void {
    model.skill_count = 0;
    model.skill_selected_id = 0;
    model.skill_body_len = 0;
    model.skill_delete_arming = false;
}

fn cancelInFlight(model: *Model, fx: *Effects) void {
    if (model.skill_key != 0) {
        fx.cancel(model.skill_key);
        model.skill_key = 0;
    }
    cancelDaemon(model, fx);
}

fn cancelDaemon(model: *Model, fx: *Effects) void {
    if (model.daemon_load_skills_key != 0) {
        fx.cancel(model.daemon_load_skills_key);
        model.daemon_load_skills_key = 0;
    }
    cancelSetSkillsEnabled(model, fx);
    cancelTrashSkills(model, fx);
}

fn cancelSetSkillsEnabled(model: *Model, fx: *Effects) void {
    if (model.daemon_set_skills_enabled_key == 0) return;
    fx.cancel(model.daemon_set_skills_enabled_key);
    model.daemon_set_skills_enabled_key = 0;
    model.skill_set_skills_enabled_ok = false;
}

fn cancelTrashSkills(model: *Model, fx: *Effects) void {
    if (model.daemon_trash_skills_key == 0) return;
    fx.cancel(model.daemon_trash_skills_key);
    model.daemon_trash_skills_key = 0;
    model.skill_trash_ok = false;
}

fn cancelRename(model: *Model, fx: *Effects) void {
    if (model.skill_rename_key == 0) return;
    fx.cancel(model.skill_rename_key);
    model.skill_rename_key = 0;
}

fn cancelRemove(model: *Model, fx: *Effects) void {
    if (model.skill_remove_key == 0) return;
    fx.cancel(model.skill_remove_key);
    model.skill_remove_key = 0;
}

fn mutationInFlight(model: *const Model) bool {
    return model.skill_rename_key != 0 or
        model.daemon_set_skills_enabled_key != 0 or
        model.daemon_trash_skills_key != 0 or
        model.skill_remove_key != 0;
}

pub fn clearDeleteArming(model: *Model) void {
    model.skill_delete_arming = false;
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
    cancelRemove(model, fx);
    clearCache(model);
    model.skill_probe_path_len = 0;
    model.skill_rename_cwd_len = 0;
    model.skill_trash_cwd_len = 0;
    model.skill_toggle_enable = false;
    model.skills_filter_buffer.clear();
}

/// Leaving Settings → Skills: drop Delete arming and cancel in-flight
/// `trashSkills` / remove (same cancel band refresh uses for
/// `setSkillsEnabled`). Catalog cache stays for composer `$` / `/`.
pub fn leavePage(model: *Model, fx: *Effects) void {
    clearDeleteArming(model);
    cancelTrashSkills(model, fx);
    cancelRemove(model, fx);
}

/// One-shot find when the probe path is empty or changed. No-op when
/// that path is already current (in-flight or a finished scan), so a
/// composer `$to…` / `/` keystroke does not spawn again. Works when
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
/// spawn so the list stays empty. When a daemon address is set,
/// prefer hello + `loadSkills`; overflow / miss keep the local walk.
pub fn refresh(model: *Model, fx: *Effects) void {
    cancelInFlight(model, fx);
    cancelRename(model, fx);
    cancelRemove(model, fx);
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
    if (trySpawnDaemon(model, fx, cwd)) return;
    spawnWalk(model, fx, cwd);
}

fn daemonMirrorAddress(model: *const Model) []const u8 {
    if (model.daemonAddress().len > 0) return model.daemonAddress();
    return model.lastDaemonAddress();
}

fn projectLabel(path: []const u8) []const u8 {
    const name = pathBasename(path);
    return if (name.len > 0) name else "project";
}

fn trySpawnDaemon(model: *Model, fx: *Effects, cwd: []const u8) bool {
    const address = daemonMirrorAddress(model);
    if (address.len == 0) return false;

    var stdin_buf: [4096]u8 = undefined;
    const stdin = daemon_proxy.writeLoadSkillsStdin(&stdin_buf, .{
        .token = model.daemonToken(),
        .projects = &.{.{ .name = projectLabel(cwd), .path = cwd }},
    }) catch return false;

    const key = model.next_daemon_key;
    model.next_daemon_key += 1;
    model.daemon_load_skills_key = key;
    fx.spawn(.{
        .key = key,
        .argv = &.{ model.sidecarPath(), daemon_proxy.SUBCOMMAND, address },
        .stdin = stdin,
        .max_line_bytes = effect_keys.daemon_line_bytes,
        .on_line = Effects.lineMsg(.fx_line),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
    return true;
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

fn probePathCurrent(model: *const Model) bool {
    const path = probePath(model);
    const probed = model.skill_probe_path_storage[0..model.skill_probe_path_len];
    return path.len > 0 and std.mem.eql(u8, path, probed);
}

fn probeStillCurrent(model: *const Model) bool {
    if (model.skill_key == 0) return false;
    return probePathCurrent(model);
}

/// Find-walk or `loadSkills` sidecar still running.
pub fn scanInFlight(model: *const Model) bool {
    return model.skill_key != 0 or model.daemon_load_skills_key != 0;
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
    return parseFrontmatterField(source, "name:");
}

/// Light YAML `description:` in a leading `---` fence. Empty when
/// missing. Plain / single-quoted / double-quoted like `name:`.
pub fn parseFrontmatterDescription(source: []const u8) []const u8 {
    return parseFrontmatterField(source, "description:");
}

fn parseFrontmatterField(source: []const u8, key: []const u8) []const u8 {
    const start = std.mem.trimStart(u8, source, " \t\r\n");
    if (!std.mem.startsWith(u8, start, "---")) return "";
    const rest = trimOneNewline(start[3..]);
    const fence = frontmatterClose(rest) orelse return "";
    const fm = rest[0..fence];
    var lines = std.mem.splitScalar(u8, fm, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (!std.mem.startsWith(u8, line, key)) continue;
        var value = std.mem.trim(u8, line[key.len..], " \t\r");
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
    if (isAbsoluteSkillPath(relpath)) {
        if (relpath.len == 0 or relpath.len > buf.len) return null;
        @memcpy(buf[0..relpath.len], relpath);
        slashNormalizeInPlace(buf[0..relpath.len]);
        return buf[0..relpath.len];
    }
    const base = std.mem.trimEnd(u8, root, "/\\");
    const rel = std.mem.trimStart(u8, relpath, "/\\");
    if (base.len == 0 or rel.len == 0) return null;
    const printed = std.fmt.bufPrint(buf, "{s}/{s}", .{ base, rel }) catch return null;
    slashNormalizeInPlace(printed);
    return printed;
}

/// Drive-letter paths and Unix paths that are not `/.hidden…`
/// (find sometimes emits a leading slash on a relative row).
pub fn isAbsoluteSkillPath(path: []const u8) bool {
    if (path.len == 0) return false;
    if (path.len >= 2 and std.ascii.isAlphabetic(path[0]) and path[1] == ':') return true;
    return path[0] == '/' and path.len >= 2 and path[1] != '.';
}

fn copySlashNormalized(src: []const u8, dest: []u8) ?[]u8 {
    if (src.len == 0 or src.len > dest.len) return null;
    @memcpy(dest[0..src.len], src);
    slashNormalizeInPlace(dest[0..src.len]);
    return dest[0..src.len];
}

fn pathHasRootPrefix(path: []const u8, root: []const u8) bool {
    if (root.len == 0 or path.len < root.len) return false;
    if (!std.mem.eql(u8, path[0..root.len], root)) return false;
    if (path.len == root.len) return true;
    return path[root.len] == '/';
}

/// Project-relative store path for a catalog `skillFile` / `dir`.
/// Strips `root` when the path sits under it. Directory-only rows
/// append `SKILL.md` / `SKILL.md.disabled` from `enabled`. Absolute
/// paths outside the project stay absolute so rename can still chdir.
pub fn catalogStorePath(root: []const u8, raw: []const u8, enabled: bool, buf: *[max_skill_path]u8) ?[]const u8 {
    const trimmed = std.mem.trim(u8, raw, " \t\r\n");
    if (trimmed.len == 0) return null;
    var path_tmp: [max_skill_path]u8 = undefined;
    const norm = copySlashNormalized(trimmed, &path_tmp) orelse return null;
    var root_tmp: [model_exports.max_project_path]u8 = undefined;
    const root_norm = copySlashNormalized(std.mem.trimEnd(u8, root, "/\\"), &root_tmp) orelse "";

    var rel: []const u8 = norm;
    if (root_norm.len > 0 and pathHasRootPrefix(norm, root_norm)) {
        rel = std.mem.trimStart(u8, norm[root_norm.len..], "/");
        if (rel.len == 0) return null;
    }

    var with_file = rel;
    var file_tmp: [max_skill_path]u8 = undefined;
    if (!isSkillMdPath(rel)) {
        const filename = if (enabled) skill_filename else disabled_skill_filename;
        const dir = std.mem.trimEnd(u8, rel, "/");
        if (dir.len == 0) return null;
        with_file = std.fmt.bufPrint(&file_tmp, "{s}/{s}", .{ dir, filename }) catch return null;
    }
    if (with_file.len == 0 or with_file.len > max_skill_path) return null;
    @memcpy(buf[0..with_file.len], with_file);
    slashNormalizeInPlace(buf[0..with_file.len]);
    return buf[0..with_file.len];
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
    var description: []const u8 = "";
    if (io != null and root.len > 0) {
        var path_buf: [model_exports.max_project_path + max_skill_path + 1]u8 = undefined;
        if (joinProbeRelpath(root, relpath, &path_buf)) |abs| {
            var file_buf: [max_skill_file_read]u8 = undefined;
            const source = readSkillSource(io.?, abs, &file_buf);
            name = parseFrontmatterName(source);
            description = parseFrontmatterDescription(source);
        }
    }
    model.skill_store[index].setName(displayName(relpath, name));
    model.skill_store[index].setDescription(description);
}

/// Append trimmed `SKILL.md` / `SKILL.md.disabled` paths until
/// `max_skills`. Later new dirs are dropped. When both live and
/// disabled exist in the same dir, live wins (replace in place).
/// Names start as the parent folder and pick up YAML `name:` when
/// the file can be read. YAML `description:` hydrates the same way
/// (empty when missing / unreadable).
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
    model.skill_store[index].setDescription("");
    hydrateOne(model, index);
}

pub fn applyLine(model: *Model, line: native_sdk.EffectLine) void {
    if (line.key != model.skill_key or model.skill_key == 0) return;
    if (!probeStillCurrent(model)) return;
    applyStdoutPaths(model, line.line);
}

pub fn applyDaemonLine(model: *Model, line: native_sdk.EffectLine) void {
    if (line.key != model.daemon_load_skills_key or model.daemon_load_skills_key == 0) return;
    if (!probePathCurrent(model)) return;
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const parsed = protocol.parseSkillsCatalog(arena_state.allocator(), line.line);
    if (!parsed.ok or parsed.skill_count == 0) return;
    applyCatalog(model, parsed);
}

fn applyCatalog(model: *Model, parsed: protocol.ParsedSkillsCatalog) void {
    clearCache(model);
    const root = model.skill_probe_path_storage[0..model.skill_probe_path_len];
    var i: usize = 0;
    while (i < parsed.skill_count) : (i += 1) {
        if (model.skill_count >= max_skills) break;
        const entry = parsed.skills[i];
        var path_buf: [max_skill_path]u8 = undefined;
        const path = catalogStorePath(root, entry.path, entry.enabled, &path_buf) orelse continue;
        if (path.len == 0 or path.len > max_skill_path) continue;
        const dir = skillDirKey(path);
        if (indexOfSkillDir(model, dir) != null) continue;
        const index = model.skill_count;
        storeSkillAt(model, index, path, entry.enabled);
        if (entry.name.len > 0) {
            model.skill_store[index].setName(displayName(path, entry.name));
        }
        if (entry.description.len > 0) {
            model.skill_store[index].setDescription(entry.description);
        }
        model.skill_count += 1;
    }
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

/// Unknown-command / parse / sidecar / empty catalog fall back to
/// today's local walk. A filled catalog stays even on a later miss.
pub fn handleDaemonExit(model: *Model, fx: *Effects, exit: native_sdk.EffectExit) void {
    if (exit.key != model.daemon_load_skills_key or model.daemon_load_skills_key == 0) return;
    model.daemon_load_skills_key = 0;
    if (model.skill_count > 0) return;
    if (!probePathCurrent(model)) return;
    if (!scanSupported()) return;
    const cwd = probePath(model);
    if (cwd.len == 0) return;
    spawnWalk(model, fx, cwd);
}

/// Success refreshes the catalog. Non-zero exit / non-exited keep
/// cache unchanged and set localized Could not update skill.
/// window_status (`skill_enable_failed_status`).
pub fn handleRenameExit(model: *Model, fx: *Effects, exit: native_sdk.EffectExit) void {
    if (exit.key != model.skill_rename_key or model.skill_rename_key == 0) return;
    model.skill_rename_key = 0;
    const succeeded = exit.reason == .exited and exit.code == 0;
    if (!succeeded) {
        failEnable(model);
        return;
    }
    refresh(model, fx);
}

pub fn applySetSkillsEnabledLine(model: *Model, line: native_sdk.EffectLine) void {
    if (line.key != model.daemon_set_skills_enabled_key or model.daemon_set_skills_enabled_key == 0) return;
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const parsed = protocol.parseAck(arena_state.allocator(), line.line);
    if (!parsed.ok) return;
    model.skill_set_skills_enabled_ok = true;
}

/// Ok Ack then `refresh`. Unknown-command / parse miss / sidecar
/// fail fall back to today's rename using the stored skill dir.
pub fn handleSetSkillsEnabledExit(model: *Model, fx: *Effects, exit: native_sdk.EffectExit) void {
    if (exit.key != model.daemon_set_skills_enabled_key or model.daemon_set_skills_enabled_key == 0) return;
    model.daemon_set_skills_enabled_key = 0;
    const ok = model.skill_set_skills_enabled_ok;
    model.skill_set_skills_enabled_ok = false;
    if (ok) {
        refresh(model, fx);
        return;
    }
    if (model.skill_rename_cwd_len == 0) return;
    spawnRename(model, fx, model.skill_toggle_enable);
}

pub fn applyTrashSkillsLine(model: *Model, line: native_sdk.EffectLine) void {
    if (line.key != model.daemon_trash_skills_key or model.daemon_trash_skills_key == 0) return;
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const parsed = protocol.parseAck(arena_state.allocator(), line.line);
    if (!parsed.ok) return;
    model.skill_trash_ok = true;
}

/// Ok Ack then clear arming and `refresh`. Unknown-command / parse
/// miss / sidecar fail fall back to today's permanent directory
/// remove using the stored skill dir.
pub fn handleTrashSkillsExit(model: *Model, fx: *Effects, exit: native_sdk.EffectExit) void {
    if (exit.key != model.daemon_trash_skills_key or model.daemon_trash_skills_key == 0) return;
    model.daemon_trash_skills_key = 0;
    const ok = model.skill_trash_ok;
    model.skill_trash_ok = false;
    if (ok) {
        clearDeleteArming(model);
        model.skill_selected_id = 0;
        model.skill_body_len = 0;
        refresh(model, fx);
        return;
    }
    if (model.skill_trash_cwd_len == 0) {
        failTrash(model);
        return;
    }
    spawnRemove(model, fx);
}

pub fn handleRemoveExit(model: *Model, fx: *Effects, exit: native_sdk.EffectExit) void {
    if (exit.key != model.skill_remove_key or model.skill_remove_key == 0) return;
    model.skill_remove_key = 0;
    const succeeded = exit.reason == .exited and exit.code == 0;
    if (!succeeded) {
        failTrash(model);
        return;
    }
    clearDeleteArming(model);
    model.skill_selected_id = 0;
    model.skill_body_len = 0;
    refresh(model, fx);
}

fn failTrash(model: *Model) void {
    model.setWindowStatus(model.skill_delete_failed_status());
}

fn failEnable(model: *Model) void {
    model.setWindowStatus(model.skill_enable_failed_status());
}

/// Enable when the selected skill is disabled, Disable when enabled.
/// Prefers one-shot `setSkillsEnabled` when a daemon address is set.
/// Unknown-command / parse / sidecar / overflow / no address keep
/// today's rename. Missing file / in-flight rename,
/// `setSkillsEnabled`, or `trashSkills` fail closed (cache unchanged).
pub fn toggleSkillEnabled(model: *Model, fx: *Effects) void {
    if (!scanSupported()) return;
    if (mutationInFlight(model)) return;
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
    model.skill_toggle_enable = enable;
    if (trySpawnSetSkillsEnabled(model, fx, parent, enable)) return;
    spawnRename(model, fx, enable);
}

fn trySpawnSetSkillsEnabled(model: *Model, fx: *Effects, dir: []const u8, enable: bool) bool {
    const address = daemonMirrorAddress(model);
    if (address.len == 0) return false;

    var stdin_buf: [4096]u8 = undefined;
    const stdin = daemon_proxy.writeSetSkillsEnabledStdin(&stdin_buf, .{
        .token = model.daemonToken(),
        .dirs = &.{dir},
        .enabled = enable,
    }) catch return false;

    const key = model.next_daemon_key;
    model.next_daemon_key += 1;
    model.daemon_set_skills_enabled_key = key;
    model.skill_set_skills_enabled_ok = false;
    fx.spawn(.{
        .key = key,
        .argv = &.{ model.sidecarPath(), daemon_proxy.SUBCOMMAND, address },
        .stdin = stdin,
        .max_line_bytes = effect_keys.daemon_line_bytes,
        .on_line = Effects.lineMsg(.fx_line),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
    return true;
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

pub fn armSkillDelete(model: *Model) void {
    if (model.skill_selected_id == 0 or model.skill_selected_id > model.skill_count) return;
    model.skill_delete_arming = true;
}

/// First-cut Settings → Skills Delete. Must be armed. Prefers
/// one-shot `trashSkills` when a daemon address is set.
/// Unknown-command / parse / sidecar / overflow / no address keep
/// today's permanent directory remove. In-flight rename,
/// `setSkillsEnabled`, or `trashSkills` fail closed.
pub fn confirmSkillDelete(model: *Model, fx: *Effects) void {
    if (!model.skill_delete_arming) return;
    trashSkill(model, fx);
}

fn trashSkill(model: *Model, fx: *Effects) void {
    if (!scanSupported()) return;
    if (mutationInFlight(model)) return;
    const id = model.skill_selected_id;
    if (id == 0 or id > model.skill_count) return;
    const index = id - 1;
    const relpath = model.skill_store[index].path();
    const parent_rel = skillDirKey(relpath);
    if (parent_rel.len == 0) {
        failTrash(model);
        return;
    }
    const root = model.skill_probe_path_storage[0..model.skill_probe_path_len];
    if (root.len == 0) {
        failTrash(model);
        return;
    }
    var parent_buf: [model_exports.max_project_path + max_skill_path + 1]u8 = undefined;
    const parent = absSkillParent(root, relpath, &parent_buf) orelse {
        failTrash(model);
        return;
    };
    if (!trashDirAllowed(parent, parent_rel)) {
        failTrash(model);
        return;
    }
    writeFixed(&model.skill_trash_cwd_storage, &model.skill_trash_cwd_len, parent);
    if (trySpawnTrashSkills(model, fx, parent)) return;
    spawnRemove(model, fx);
}

fn trySpawnTrashSkills(model: *Model, fx: *Effects, dir: []const u8) bool {
    const address = daemonMirrorAddress(model);
    if (address.len == 0) return false;

    var stdin_buf: [4096]u8 = undefined;
    const stdin = daemon_proxy.writeTrashSkillsStdin(&stdin_buf, .{
        .token = model.daemonToken(),
        .dirs = &.{dir},
    }) catch return false;

    const key = model.next_daemon_key;
    model.next_daemon_key += 1;
    model.daemon_trash_skills_key = key;
    model.skill_trash_ok = false;
    fx.spawn(.{
        .key = key,
        .argv = &.{ model.sidecarPath(), daemon_proxy.SUBCOMMAND, address },
        .stdin = stdin,
        .max_line_bytes = effect_keys.daemon_line_bytes,
        .on_line = Effects.lineMsg(.fx_line),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
    return true;
}

fn spawnRemove(model: *Model, fx: *Effects) void {
    const dir = model.skill_trash_cwd_storage[0..model.skill_trash_cwd_len];
    const cwd = model.skill_probe_path_storage[0..model.skill_probe_path_len];
    if (dir.len == 0 or cwd.len == 0) {
        failTrash(model);
        return;
    }
    const key = model.next_skill_remove_key;
    model.next_skill_remove_key = key + 1;
    model.skill_remove_key = key;
    var argv_buf: [remove_argv_len][]const u8 = undefined;
    fx.spawn(.{
        .key = key,
        .argv = removeArgvFor(cwd, dir, &argv_buf),
        .on_line = Effects.lineMsg(.fx_line),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
}

pub fn selectSkill(model: *Model, id: u32) void {
    if (id != model.skill_selected_id) {
        model.skill_delete_arming = false;
    }
    if (id == 0 or id > model.skill_count) {
        model.skill_selected_id = 0;
        model.skill_body_len = 0;
        return;
    }
    model.skill_selected_id = id;
    loadBody(model, id - 1);
}

/// Absolute `SKILL.md` / `SKILL.md.disabled` for the selected Settings
/// Skills row. Reuses `joinProbeRelpath` (same join as body read /
/// Enable/Disable / catalog store). Null when nothing is selected,
/// the store path is empty, or the join does not resolve.
pub fn selectedSkillAbsPath(model: *const Model, buf: []u8) ?[]const u8 {
    if (model.skill_selected_id == 0 or model.skill_selected_id > model.skill_count) return null;
    const relpath = model.skill_store[model.skill_selected_id - 1].path();
    if (relpath.len == 0) return null;
    const root = model.skill_probe_path_storage[0..model.skill_probe_path_len];
    const abs = joinProbeRelpath(root, relpath, buf) orelse return null;
    if (abs.len == 0) return null;
    return abs;
}

/// Settings Skills Open in editor. Same `cursor` / `code` /
/// `open -a` sidecar as Files preview. Fail closed with no
/// selection / empty / invalid path (no crash, no spawn). Missing
/// host editor window_status stays on `startOpenEditorAt`.
pub fn openSelectedSkillInEditor(model: *Model, fx: *Effects) void {
    var path_buf: [model_exports.max_project_path + max_skill_path + 1]u8 = undefined;
    const abs = selectedSkillAbsPath(model, &path_buf) orelse return;
    open_editor.startOpenEditorAt(model, fx, abs);
}

/// Settings Skills Reveal. Same Finder / xdg-open / Explorer sidecar
/// as composer Reveal folder (`startRevealPath` on the parent of a
/// file). Fail closed with no selection / empty / unresolved path
/// (no crash, no spawn). Missing host tool window_status stays on
/// `.missing_bin`.
pub fn revealSelectedSkill(model: *Model, fx: *Effects) void {
    var path_buf: [model_exports.max_project_path + max_skill_path + 1]u8 = undefined;
    const abs = selectedSkillAbsPath(model, &path_buf) orelse return;
    switch (reveal_folder.startRevealPath(model, fx, abs)) {
        .spawned, .live => {},
        .missing_bin => model.setWindowStatus(reveal_folder.hostMissingStatusFor(model.language_preference, model.systemLocaleId())),
        .no_path => {},
    }
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

/// Prepend stripped bodies for `$name` / skill-matching `/name`
/// tokens in `text` (enabled cache rows only, first-occurrence
/// order, missing files omitted; `$alpha` and `/alpha` dedupe).
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

/// Kick a project scan when `$name` / `/name` tokens are present,
/// then expand. Scan is async (Native has no sync walk); first Send
/// after a paste may still no-op until the cache fills.
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

/// English defaults from `i18n.SkillsTrashChrome`. Distinct from
/// Enable / Disable / empty-state.
const skills_trash_chrome_en = i18n.skillsTrashChromeFor(.english, "");
pub const delete_label = skills_trash_chrome_en.delete;
pub const confirm_delete_label = skills_trash_chrome_en.confirm;

fn skillsEmptyChrome(model: *const Model) i18n.SkillsEmptyChrome {
    return i18n.skillsEmptyChromeFor(model.language_preference, model.systemLocaleId());
}

/// Settings Skills empty hint and composer `$` insert empty. Localized
/// via `i18n.SkillsEmptyChrome`. Empty while a scan is in flight.
pub fn emptyHint(model: *const Model) []const u8 {
    const chrome = skillsEmptyChrome(model);
    if (probePath(model).len == 0) return chrome.open_project;
    if (scanInFlight(model) and model.skill_count == 0) return "";
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
    try std.testing.expect(skills_remove_key_first > skills_rename_key_first);
    try std.testing.expect(skills_remove_key_first < 600);
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
    var remove_buf: [remove_argv_len][]const u8 = undefined;
    const remove_argv = removeArgvFor("/tmp/faku-skills", "/tmp/faku-skills/.cursor/skills/demo", &remove_buf);
    try std.testing.expect(isSkillsRemoveArgv(remove_argv));
    try std.testing.expect(!isSkillsWalkArgv(remove_argv));
    try std.testing.expect(!isSkillsRenameArgv(remove_argv));
    try std.testing.expect(!isSkillsRemoveArgv(walk_argv));
    try std.testing.expect(!isSkillsRemoveArgv(rename_argv));
    switch (builtin.os.tag) {
        .windows => {
            try std.testing.expectEqualStrings(powershell_bin, walk_argv[0]);
            try std.testing.expectEqualStrings(powershell_args_flag, walk_argv[4]);
            try std.testing.expectEqualStrings(powershell_bin, rename_argv[0]);
            try std.testing.expectEqualStrings(powershell_args_flag, rename_argv[4]);
            try std.testing.expectEqualStrings(powershell_bin, remove_argv[0]);
            try std.testing.expectEqualStrings(powershell_args_flag, remove_argv[4]);
        },
        else => {
            try std.testing.expectEqualStrings(sh_bin, walk_argv[0]);
            try std.testing.expectEqualStrings(find_skills_script, walk_argv[7]);
            try std.testing.expectEqualStrings(sh_bin, rename_argv[0]);
            try std.testing.expectEqualStrings(mv_bin, rename_argv[5]);
            try std.testing.expectEqualStrings(sh_bin, remove_argv[0]);
            try std.testing.expectEqualStrings(rm_bin, remove_argv[5]);
            try std.testing.expectEqualStrings(rm_rf_flag, remove_argv[6]);
            try std.testing.expectEqualStrings(rm_end_of_options, remove_argv[7]);
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

test "parse description from frontmatter; quoted and missing" {
    try std.testing.expectEqualStrings("hello", parseFrontmatterDescription(
        \\---
        \\name: my-skill
        \\description: hello
        \\---
        \\
        \\# Body
    ));
    try std.testing.expectEqualStrings("Pretty desc", parseFrontmatterDescription(
        \\---
        \\description: "Pretty desc"
        \\---
        \\body
    ));
    try std.testing.expectEqualStrings("quoted", parseFrontmatterDescription(
        \\---
        \\description: 'quoted'
        \\---
    ));
    try std.testing.expectEqualStrings("", parseFrontmatterDescription("# no fence\ndescription: nope\n"));
    try std.testing.expectEqualStrings("", parseFrontmatterDescription("---\nname: x\n---\n"));
    try std.testing.expectEqualStrings("", parseFrontmatterDescription(""));
    try std.testing.expectEqualStrings("", parseFrontmatterDescription(
        \\---
        \\description:
        \\---
    ));
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
    try std.testing.expectEqualStrings("", cachedDescription(&model, 0));
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
        \\description: One-line skill summary.
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
    try std.testing.expectEqualStrings("One-line skill summary.", cachedDescription(&model, 0));

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

test "unix remove argv is chdir plus rm -rf -- skill dir; not rename or find" {
    var buf: [remove_argv_len][]const u8 = undefined;
    const dir = "/tmp/faku/.cursor/skills/demo";
    const argv = unixRemoveArgvFor("/tmp/faku", dir, &buf);
    try std.testing.expect(isSkillsRemoveArgv(argv));
    try std.testing.expect(!isSkillsWalkArgv(argv));
    try std.testing.expect(!isSkillsRenameArgv(argv));
    try std.testing.expectEqual(@as(usize, unix_remove_argv_len), argv.len);
    try std.testing.expectEqualStrings(sh_bin, argv[0]);
    try std.testing.expectEqualStrings("-c", argv[1]);
    try std.testing.expectEqualStrings(util.fx_ask_chdir_script, argv[2]);
    try std.testing.expectEqualStrings("/tmp/faku", argv[4]);
    try std.testing.expectEqualStrings(rm_bin, argv[5]);
    try std.testing.expectEqualStrings(rm_rf_flag, argv[6]);
    try std.testing.expectEqualStrings(rm_end_of_options, argv[7]);
    try std.testing.expectEqualStrings(dir, argv[8]);
    try std.testing.expect(std.mem.indexOf(u8, argv[2], dir) == null);
    try std.testing.expect(!isSkillsRemoveArgv(&.{ rm_bin, rm_rf_flag, rm_end_of_options, dir }));
    var rename_buf: [rename_argv_len][]const u8 = undefined;
    try std.testing.expect(!isSkillsRemoveArgv(unixRenameArgvFor("/tmp/faku-skill-dir", false, &rename_buf)));
}

test "windows remove argv is powershell Remove-Item -LiteralPath; path stays -Args slot" {
    var buf: [remove_argv_len][]const u8 = undefined;
    const dir = "C:\\Users\\me\\proj\\.cursor\\skills\\demo";
    const argv = windowsRemoveArgvFor(dir, &buf);
    try std.testing.expectEqual(@as(usize, windows_remove_argv_len), argv.len);
    try std.testing.expect(argv.len <= 16);
    try std.testing.expect(isSkillsRemoveArgv(argv));
    try std.testing.expect(!isSkillsWalkArgv(argv));
    try std.testing.expect(!isSkillsRenameArgv(argv));
    try std.testing.expectEqualStrings(powershell_bin, argv[0]);
    try std.testing.expectEqualStrings(powershell_noprofile, argv[1]);
    try std.testing.expectEqualStrings(powershell_command, argv[2]);
    try std.testing.expectEqualStrings(powershell_skills_remove_script, argv[3]);
    try std.testing.expectEqualStrings(powershell_args_flag, argv[4]);
    try std.testing.expectEqualStrings(dir, argv[5]);
    try std.testing.expect(std.mem.indexOf(u8, argv[3], dir) == null);
    try std.testing.expect(scriptHas(argv[3], "$args[0]"));
    try std.testing.expect(scriptHas(argv[3], "Remove-Item"));
    try std.testing.expect(scriptHas(argv[3], "-LiteralPath"));
    try std.testing.expect(scriptHas(argv[3], "-Recurse"));
    try std.testing.expect(scriptHas(argv[3], "-Force"));
    try std.testing.expect(!isSkillsRemoveArgv(&.{
        powershell_bin,
        powershell_noprofile,
        powershell_command,
        "Remove-Item",
        powershell_args_flag,
        dir,
    }));
}

test "trashDirAllowed requires absolute dir containing cache parent; fail closed otherwise" {
    try std.testing.expect(trashDirAllowed("/tmp/faku/.cursor/skills/demo", ".cursor/skills/demo"));
    try std.testing.expect(trashDirAllowed("/tmp/faku/skills/other", "skills/other"));
    try std.testing.expect(trashDirAllowed("C:/Users/me/proj/.cursor/skills/demo", ".cursor/skills/demo"));
    try std.testing.expect(trashDirAllowed(".zig-cache/tmp/x/skills/demo", "skills/demo"));
    try std.testing.expect(!trashDirAllowed("", ".cursor/skills/demo"));
    try std.testing.expect(!trashDirAllowed("/tmp/faku/.cursor/skills/demo", ""));
    try std.testing.expect(!trashDirAllowed(".cursor/skills/demo", ".cursor/skills/demo"));
    try std.testing.expect(!trashDirAllowed("/tmp/faku", ".cursor/skills/demo"));
    try std.testing.expect(!trashDirAllowed("/", ".cursor/skills/demo"));
    try std.testing.expect(trashDirAllowed("/tmp/faku", "faku"));
    try std.testing.expect(!trashDirAllowed("/tmp/skills-evil", "skills"));
    try std.testing.expect(!trashDirAllowed("/tmp/faku/../etc/.cursor/skills/demo", ".cursor/skills/demo"));
    try std.testing.expect(!trashDirAllowed("demo", "demo"));
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
    try testing.expect(!model.has_window_status());

    handleRenameExit(&model, &fx, .{ .key = rename_key, .reason = .exited, .code = 1 });
    try testing.expectEqual(@as(u64, 0), model.skill_rename_key);
    try testing.expectEqual(@as(u32, 1), cachedCount(&model));
    try testing.expect(cachedEnabled(&model, 0));
    try testing.expectEqualStrings(could_not_update_status, model.window_status());
    try testing.expectEqualStrings(model.skill_enable_failed_status(), model.window_status());

    model.clearWindowStatus();
    toggleSkillEnabled(&model, &fx);
    const retry_key = model.skill_rename_key;
    try testing.expect(retry_key > rename_key);
    handleRenameExit(&model, &fx, .{ .key = retry_key, .reason = .exited, .code = 0 });
    try testing.expectEqual(@as(u64, 0), model.skill_rename_key);
    try testing.expectEqual(@as(u32, 0), cachedCount(&model));
    try testing.expect(model.skill_key >= skills_key_first);
    try testing.expect(!model.has_window_status());
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
    try testing.expectEqual(@as(u64, 0), model.daemon_set_skills_enabled_key);
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
    try std.testing.expectEqualStrings(
        "/home/user/.cursor/skills/foo/SKILL.md",
        joinProbeRelpath("/tmp/proj", "/home/user/.cursor/skills/foo/SKILL.md", &buf).?,
    );
    try std.testing.expectEqualStrings(
        "/home/user/.cursor/skills/foo",
        absSkillParent("/tmp/proj", "/home/user/.cursor/skills/foo/SKILL.md", &buf).?,
    );
}

test "selectedSkillAbsPath joins probe root; absolute catalog paths stay absolute" {
    var model = Model{};
    writeFixed(&model.skill_probe_path_storage, &model.skill_probe_path_len, "C:\\Users\\me\\proj");
    applyStdoutPaths(&model, ".cursor/skills/demo/SKILL.md\n");
    try std.testing.expectEqual(@as(u32, 1), cachedCount(&model));

    var buf: [256]u8 = undefined;
    try std.testing.expect(selectedSkillAbsPath(&model, &buf) == null);

    selectSkill(&model, 1);
    try std.testing.expectEqualStrings(
        "C:/Users/me/proj/.cursor/skills/demo/SKILL.md",
        selectedSkillAbsPath(&model, &buf).?,
    );

    clearCache(&model);
    writeFixed(&model.skill_probe_path_storage, &model.skill_probe_path_len, "/tmp/proj");
    applyStdoutPaths(&model, ".cursor/skills/off/SKILL.md.disabled\n/home/user/.cursor/skills/foo/SKILL.md\n");
    selectSkill(&model, 1);
    try std.testing.expectEqualStrings(
        "/tmp/proj/.cursor/skills/off/SKILL.md.disabled",
        selectedSkillAbsPath(&model, &buf).?,
    );
    selectSkill(&model, 2);
    try std.testing.expectEqualStrings(
        "/home/user/.cursor/skills/foo/SKILL.md",
        selectedSkillAbsPath(&model, &buf).?,
    );

    model.skill_selected_id = 0;
    try std.testing.expect(selectedSkillAbsPath(&model, &buf) == null);
    model.skill_selected_id = 99;
    try std.testing.expect(selectedSkillAbsPath(&model, &buf) == null);

    model.skill_probe_path_len = 0;
    selectSkill(&model, 1);
    try std.testing.expect(selectedSkillAbsPath(&model, &buf) == null);
    selectSkill(&model, 2);
    try std.testing.expectEqualStrings(
        "/home/user/.cursor/skills/foo/SKILL.md",
        selectedSkillAbsPath(&model, &buf).?,
    );
}

test "openSelectedSkillInEditor queues host editor argv at the absolute skill file" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    writeFixed(&model.skill_probe_path_storage, &model.skill_probe_path_len, "/tmp/proj");
    applyStdoutPaths(&model, ".cursor/skills/demo/SKILL.md\n");
    selectSkill(&model, 1);

    openSelectedSkillInEditor(&model, &fx);
    const spawn = fx.pendingSpawnAt(0) orelse return error.MissingOpenEditorSpawn;
    try std.testing.expect(open_editor.isEditorArgv(spawn.argv));
    try std.testing.expectEqual(open_editor.open_editor_key, spawn.key);
    const path_slot: usize = if (spawn.argv.len == 4) 3 else 1;
    try std.testing.expectEqualStrings("/tmp/proj/.cursor/skills/demo/SKILL.md", spawn.argv[path_slot]);
}

test "openSelectedSkillInEditor fails closed with no selection or unresolved path" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    openSelectedSkillInEditor(&model, &fx);
    try std.testing.expect(fx.pendingSpawnAt(0) == null);
    try std.testing.expect(!model.open_editor_live);
    try std.testing.expectEqualStrings("", model.window_status());

    applyStdoutPaths(&model, ".cursor/skills/demo/SKILL.md\n");
    selectSkill(&model, 1);
    openSelectedSkillInEditor(&model, &fx);
    try std.testing.expect(fx.pendingSpawnAt(0) == null);
    try std.testing.expect(!model.open_editor_live);
    try std.testing.expectEqualStrings("", model.window_status());
}

test "revealSelectedSkill queues host reveal argv at the skill parent directory" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const root = try std.fmt.bufPrint(&dir_buf, "/tmp/faku-skills-reveal-{s}", .{tmp.sub_path});
    var skill_dir_buf: [320]u8 = undefined;
    const skill_dir = try std.fmt.bufPrint(&skill_dir_buf, "{s}/.cursor/skills/demo", .{root});
    try std.Io.Dir.cwd().createDirPath(testing.io, skill_dir);
    var file_buf: [360]u8 = undefined;
    const file_path = try std.fmt.bufPrint(&file_buf, "{s}/SKILL.md", .{skill_dir});
    try std.Io.Dir.cwd().writeFile(testing.io, .{
        .sub_path = file_path,
        .data =
        \\---
        \\name: demo
        \\---
        \\
        \\Body.
        \\
        ,
    });

    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = testing.io;
    writeFixed(&model.skill_probe_path_storage, &model.skill_probe_path_len, root);
    applyStdoutPaths(&model, ".cursor/skills/demo/SKILL.md\n");
    selectSkill(&model, 1);
    var abs_buf: [model_exports.max_project_path + max_skill_path + 1]u8 = undefined;
    try std.testing.expectEqualStrings(file_path, selectedSkillAbsPath(&model, &abs_buf).?);

    revealSelectedSkill(&model, &fx);
    const spawn = fx.pendingSpawnAt(0) orelse return error.MissingRevealFolderSpawn;
    try std.testing.expect(reveal_folder.isRevealArgv(spawn.argv));
    try std.testing.expectEqual(reveal_folder.reveal_folder_key, spawn.key);
    try std.testing.expectEqualStrings(reveal_folder.hostBin().?, spawn.argv[0]);
    try std.testing.expectEqualStrings(skill_dir, spawn.argv[1]);
}

test "revealSelectedSkill fails closed with no selection or unresolved path" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    revealSelectedSkill(&model, &fx);
    try std.testing.expect(fx.pendingSpawnAt(0) == null);
    try std.testing.expect(!model.reveal_folder_live);
    try std.testing.expectEqualStrings("", model.window_status());

    applyStdoutPaths(&model, ".cursor/skills/demo/SKILL.md\n");
    selectSkill(&model, 1);
    revealSelectedSkill(&model, &fx);
    try std.testing.expect(fx.pendingSpawnAt(0) == null);
    try std.testing.expect(!model.reveal_folder_live);
    try std.testing.expectEqualStrings("", model.window_status());
}

test "skill_reveal_label equals composerProjectChrome reveal_folder" {
    var model = Model{};
    try std.testing.expectEqualStrings(
        i18n.composerProjectChromeFor(.english, "").reveal_folder,
        model.skill_reveal_label(),
    );
    try std.testing.expectEqualStrings(model.reveal_folder_label(), model.skill_reveal_label());
    model.language_preference = .simplified_chinese;
    try std.testing.expectEqualStrings(
        i18n.composerProjectChromeFor(.simplified_chinese, "").reveal_folder,
        model.skill_reveal_label(),
    );
    model.language_preference = .japanese;
    try std.testing.expectEqualStrings(
        i18n.composerProjectChromeFor(.japanese, "").reveal_folder,
        model.skill_reveal_label(),
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
    try testing.expect(!rows[0].has_description);
    try testing.expectEqualStrings("", rows[0].description);

    model.draft_buffer.set("$off");
    try testing.expectEqual(@as(usize, 0), model.skill_insert_rows(arena).len);
}

test "hydrate description; skill_rows skill_insert_rows command_rows expose it" {
    const testing = std.testing;
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const root = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-skills-desc", .{tmp.sub_path[0..]});
    var with_dir_buf: [256]u8 = undefined;
    const with_dir = try std.fmt.bufPrint(&with_dir_buf, "{s}/skills/with-desc", .{root});
    try std.Io.Dir.cwd().createDirPath(testing.io, with_dir);
    var with_file_buf: [256]u8 = undefined;
    const with_file = try std.fmt.bufPrint(&with_file_buf, "{s}/SKILL.md", .{with_dir});
    try std.Io.Dir.cwd().writeFile(testing.io, .{
        .sub_path = with_file,
        .data =
        \\---
        \\name: with-desc
        \\description: "Does the described thing."
        \\---
        \\
        \\Body stays in the detail pane.
        \\
        ,
    });
    var bare_dir_buf: [256]u8 = undefined;
    const bare_dir = try std.fmt.bufPrint(&bare_dir_buf, "{s}/skills/bare", .{root});
    try std.Io.Dir.cwd().createDirPath(testing.io, bare_dir);
    var bare_file_buf: [256]u8 = undefined;
    const bare_file = try std.fmt.bufPrint(&bare_file_buf, "{s}/SKILL.md", .{bare_dir});
    try std.Io.Dir.cwd().writeFile(testing.io, .{
        .sub_path = bare_file,
        .data =
        \\---
        \\name: bare
        \\---
        \\
        \\No description field.
        \\
        ,
    });

    var model = Model{};
    model.store_io = testing.io;
    writeFixed(&model.skill_probe_path_storage, &model.skill_probe_path_len, root);
    applyStdoutPaths(&model, "skills/with-desc/SKILL.md\nskills/bare/SKILL.md\n");
    try testing.expectEqual(@as(u32, 2), cachedCount(&model));
    try testing.expectEqualStrings("Does the described thing.", cachedDescription(&model, 0));
    try testing.expectEqualStrings("", cachedDescription(&model, 1));

    model.settings_page = .skills;
    {
        const rows = model.skill_rows(arena);
        try testing.expectEqual(@as(usize, 2), rows.len);
        try testing.expect(rows[0].has_description);
        try testing.expectEqualStrings("Does the described thing.", rows[0].description);
        try testing.expect(!rows[1].has_description);
        try testing.expectEqualStrings("", rows[1].description);
    }

    model.draft_buffer.set("$");
    {
        const rows = model.skill_insert_rows(arena);
        try testing.expectEqual(@as(usize, 2), rows.len);
        try testing.expect(rows[0].has_description);
        try testing.expectEqualStrings("Does the described thing.", rows[0].description);
        try testing.expect(!rows[1].has_description);
    }

    model.draft_buffer.set("$described");
    {
        const rows = model.skill_insert_rows(arena);
        try testing.expectEqual(@as(usize, 1), rows.len);
        try testing.expectEqualStrings("with-desc", rows[0].name);
    }

    const id = model.addSession("desc rows", .fx);
    model.selected = id;
    model.draft_buffer.set("/");
    {
        const rows = model.command_rows(arena);
        try testing.expectEqual(@as(usize, 2), rows.len);
        try testing.expectEqualStrings("/with-desc", rows[0].slash_name);
        try testing.expect(rows[0].has_description);
        try testing.expectEqualStrings("Does the described thing.", rows[0].description);
        try testing.expectEqualStrings("/bare", rows[1].slash_name);
        try testing.expect(!rows[1].has_description);
        try testing.expectEqualStrings("", rows[1].description);
    }
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
    try testing.expectEqualStrings("/unknown do it", expandPrompt(&model, "/unknown do it", &out));
    try testing.expectEqualStrings("/", expandPrompt(&model, "/", &out));
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

    const slash_expanded = expandPrompt(&model, "/beta then $alpha and /beta again plus /off and /gone", &out);
    try testing.expectEqualStrings(
        \\### Skill: beta
        \\Beta body.
        \\
        \\### Skill: alpha
        \\Alpha body.
        \\
        \\/beta then $alpha and /beta again plus /off and /gone
    , slash_expanded);

    const slash_missing = expandPrompt(&model, "/gone only", &out);
    try testing.expectEqualStrings("/gone only", slash_missing);

    const slash_disabled = expandPrompt(&model, "/off please", &out);
    try testing.expectEqualStrings("/off please", slash_disabled);

    const mixed_dedupe = expandPrompt(&model, "$alpha then /alpha", &out);
    try testing.expectEqualStrings(
        \\### Skill: alpha
        \\Alpha body.
        \\
        \\$alpha then /alpha
    , mixed_dedupe);
}

test "slashCommandId sits above ACP max_available_commands" {
    const testing = std.testing;
    try testing.expectEqual(@as(u32, 1), skillId(0));
    try testing.expectEqual(@as(u32, @intCast(model_exports.max_available_commands + 1)), slashCommandId(0));
    try testing.expectEqual(@as(u32, @intCast(model_exports.max_available_commands + 2)), slashCommandId(1));
    try testing.expectEqual(@as(usize, 0), slashCommandIndex(slashCommandId(0)).?);
    try testing.expectEqual(@as(usize, 3), slashCommandIndex(slashCommandId(3)).?);
    try testing.expect(slashCommandIndex(0) == null);
    try testing.expect(slashCommandIndex(1) == null);
    try testing.expect(slashCommandIndex(@intCast(model_exports.max_available_commands)) == null);
}

fn pendingSpawnKey(fx: *Effects, key: u64) ?@TypeOf(fx.pendingSpawnAt(0).?) {
    var i: usize = 0;
    while (fx.pendingSpawnAt(i)) |spawn| : (i += 1) {
        if (spawn.key == key) return spawn;
    }
    return null;
}

const skills_catalog_empty_line =
    "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000019\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"skillsCatalog\",\"catalog\":{\"skills\":[]}}}}";

const skills_catalog_unknown_line =
    "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000019\",\"outcome\":{\"status\":\"error\",\"error\":{\"message\":\"unknown command\"}}}";

test "catalogStorePath strips project root; dir-only appends SKILL.md; outside stays absolute" {
    var buf: [max_skill_path]u8 = undefined;
    try std.testing.expectEqualStrings(
        ".cursor/skills/to-spec/SKILL.md",
        catalogStorePath("/tmp/faku", "/tmp/faku/.cursor/skills/to-spec/SKILL.md", true, &buf).?,
    );
    try std.testing.expectEqualStrings(
        ".cursor/skills/off/SKILL.md.disabled",
        catalogStorePath("/tmp/faku/", "/tmp/faku/.cursor/skills/off", false, &buf).?,
    );
    try std.testing.expectEqualStrings(
        ".cursor/skills/rel/SKILL.md",
        catalogStorePath("/tmp/faku", ".cursor/skills/rel/SKILL.md", true, &buf).?,
    );
    try std.testing.expectEqualStrings(
        "/home/user/.cursor/skills/user/SKILL.md",
        catalogStorePath("/tmp/faku", "/home/user/.cursor/skills/user/SKILL.md", true, &buf).?,
    );
    try std.testing.expect(isAbsoluteSkillPath("/tmp/faku/.cursor/skills/foo/SKILL.md"));
    try std.testing.expect(isAbsoluteSkillPath("C:\\Users\\me\\.cursor\\skills\\foo\\SKILL.md"));
    try std.testing.expect(!isAbsoluteSkillPath("/.cursor/skills/foo/SKILL.md"));
    try std.testing.expect(!isAbsoluteSkillPath(".cursor/skills/foo/SKILL.md"));
}

test "refresh with a daemon address spawns loadSkills sidecar" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const root = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-skills-daemon", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(testing.io, root);

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = testing.io;
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    const id = model.addSession("skills daemon", .fx);
    model.selected = id;
    model.sessionById(id).?.setProjectPath(root);

    refresh(&model, &fx);
    try testing.expectEqual(@as(u64, 0), model.skill_key);
    const sidecar = pendingSpawnKey(&fx, model.daemon_load_skills_key) orelse return error.MissingDaemonLoadSkills;
    try testing.expect(daemon_proxy.isSidecarArgv(sidecar.argv));
    try testing.expectEqualStrings("faku", sidecar.argv[0]);
    try testing.expectEqualStrings(daemon_proxy.SUBCOMMAND, sidecar.argv[1]);
    try testing.expectEqualStrings("127.0.0.1:8787", sidecar.argv[2]);
    try testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"hello\"") != null);
    try testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"loadSkills\"") != null);
    try testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"projects\":[[") != null);
    try testing.expect(std.mem.indexOf(u8, sidecar.stdin, root) != null);
    try testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"loadUsageHistory\"") == null);
    try testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"prompt\"") == null);
    try testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"workspace\"") == null);
    try testing.expectEqual(sidecar.key, model.daemon_load_skills_key);
    try testing.expect(scanInFlight(&model));
    try testing.expect(sidecar.key != model.skill_key);

    ensureScanned(&model, &fx);
    try testing.expectEqual(sidecar.key, model.daemon_load_skills_key);
}

test "refresh without a daemon address keeps local find walk" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const root = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-skills-local", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(testing.io, root);

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = testing.io;
    model.setSidecarPath("faku");
    const id = model.addSession("skills local", .fx);
    model.selected = id;
    model.sessionById(id).?.setProjectPath(root);

    refresh(&model, &fx);
    try testing.expectEqual(@as(u64, 0), model.daemon_load_skills_key);
    try testing.expect(model.skill_key >= skills_key_first);
    const walk = pendingSpawnKey(&fx, model.skill_key) orelse return error.MissingSkillsWalk;
    try testing.expect(isSkillsWalkArgv(walk.argv));
    try testing.expect(!daemon_proxy.isSidecarArgv(walk.argv));
}

test "LoadSkills sidecar fills skill_store; unknown-command falls back to find" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const root = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-skills-fill", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(testing.io, root);
    var on_dir_buf: [256]u8 = undefined;
    const on_dir = try std.fmt.bufPrint(&on_dir_buf, "{s}/.cursor/skills/to-spec", .{root});
    try std.Io.Dir.cwd().createDirPath(testing.io, on_dir);
    var on_file_buf: [256]u8 = undefined;
    const on_file = try std.fmt.bufPrint(&on_file_buf, "{s}/SKILL.md", .{on_dir});
    try std.Io.Dir.cwd().writeFile(testing.io, .{
        .sub_path = on_file,
        .data =
        \\---
        \\name: to-spec
        \\---
        \\
        \\Do the thing.
        \\
        ,
    });

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = testing.io;
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    const id = model.addSession("skills fill", .fx);
    model.selected = id;
    model.sessionById(id).?.setProjectPath(root);

    refresh(&model, &fx);
    const sidecar = pendingSpawnKey(&fx, model.daemon_load_skills_key) orelse return error.MissingDaemonLoadSkillsFill;
    const fill_key = sidecar.key;
    var line_buf: [2560]u8 = undefined;
    const ok_line = try std.fmt.bufPrint(&line_buf, "{s}{s}{s}{s}{s}{s}{s}{s}{s}", .{
        "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-000000000019\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"skillsCatalog\",\"catalog\":{\"skills\":[{\"name\":\"to-spec\",\"description\":\"Catalog summary.\",\"enabled\":true,\"installs\":[{\"dir\":\"",
        root,
        "/.cursor/skills/to-spec\",\"skillFile\":\"",
        root,
        "/.cursor/skills/to-spec/SKILL.md\",\"enabled\":true}]},{\"name\":\"off\",\"enabled\":false,\"installs\":[{\"dir\":\"",
        root,
        "/.cursor/skills/off\",\"skillFile\":\"",
        root,
        "/.cursor/skills/off/SKILL.md.disabled\",\"enabled\":false}]}]}}}}",
    });
    applyDaemonLine(&model, .{ .key = fill_key, .line = ok_line });
    try testing.expectEqual(@as(u32, 2), cachedCount(&model));
    try testing.expectEqualStrings("to-spec", cachedName(&model, 0));
    try testing.expectEqualStrings("Catalog summary.", cachedDescription(&model, 0));
    try testing.expect(cachedEnabled(&model, 0));
    try testing.expectEqualStrings(".cursor/skills/to-spec/SKILL.md", cachedPath(&model, 0));
    try testing.expectEqualStrings("off", cachedName(&model, 1));
    try testing.expectEqualStrings("", cachedDescription(&model, 1));
    try testing.expect(!cachedEnabled(&model, 1));
    try testing.expectEqualStrings(".cursor/skills/off/SKILL.md.disabled", cachedPath(&model, 1));
    var prompt_buf: [2048]u8 = undefined;
    const expanded = expandPrompt(&model, "$to-spec hello", &prompt_buf);
    try testing.expect(std.mem.indexOf(u8, expanded, "Do the thing.") != null);
    try testing.expect(std.mem.endsWith(u8, expanded, "$to-spec hello"));
    handleDaemonExit(&model, &fx, .{ .key = fill_key, .reason = .exited, .code = 0 });
    try testing.expectEqual(@as(u64, 0), model.daemon_load_skills_key);
    try testing.expectEqual(@as(u64, 0), model.skill_key);
    try testing.expectEqual(@as(u32, 2), cachedCount(&model));

    refresh(&model, &fx);
    const miss = pendingSpawnKey(&fx, model.daemon_load_skills_key) orelse return error.MissingDaemonLoadSkillsMiss;
    const miss_key = miss.key;
    applyDaemonLine(&model, .{ .key = miss_key, .line = skills_catalog_unknown_line });
    try testing.expectEqual(@as(u32, 0), cachedCount(&model));
    handleDaemonExit(&model, &fx, .{ .key = miss_key, .reason = .exited, .code = 1 });
    try testing.expectEqual(@as(u64, 0), model.daemon_load_skills_key);
    try testing.expect(model.skill_key >= skills_key_first);
    const fallback = pendingSpawnKey(&fx, model.skill_key) orelse return error.MissingSkillsWalkFallback;
    try testing.expect(isSkillsWalkArgv(fallback.argv));

    refresh(&model, &fx);
    const empty = pendingSpawnKey(&fx, model.daemon_load_skills_key) orelse return error.MissingDaemonLoadSkillsEmpty;
    applyDaemonLine(&model, .{ .key = empty.key, .line = skills_catalog_empty_line });
    try testing.expectEqual(@as(u32, 0), cachedCount(&model));
    handleDaemonExit(&model, &fx, .{ .key = empty.key, .reason = .exited, .code = 0 });
    try testing.expectEqual(@as(u64, 0), model.daemon_load_skills_key);
    try testing.expect(isSkillsWalkArgv((pendingSpawnKey(&fx, model.skill_key) orelse return error.MissingEmptyCatalogWalk).argv));
}

test "writeLoadSkillsStdin overflow keeps local walk" {
    var tiny: [32]u8 = undefined;
    try std.testing.expectError(error.NoSpaceLeft, daemon_proxy.writeLoadSkillsStdin(&tiny, .{
        .projects = &.{.{ .name = "faku", .path = "/tmp/faku" }},
    }));
}

const set_skills_enabled_ack_line =
    "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-00000000001a\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"ack\"}}}";

const set_skills_enabled_unknown_line =
    "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-00000000001a\",\"outcome\":{\"status\":\"error\",\"error\":{\"message\":\"unknown command\"}}}";

test "toggleSkillEnabled with a daemon address spawns setSkillsEnabled sidecar" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const root = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-skills-toggle-daemon", .{tmp.sub_path[0..]});
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
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    writeFixed(&model.skill_probe_path_storage, &model.skill_probe_path_len, root);
    applyStdoutPaths(&model, "skills/demo/SKILL.md\n");
    selectSkill(&model, 1);
    try testing.expect(cachedEnabled(&model, 0));

    toggleSkillEnabled(&model, &fx);
    try testing.expectEqual(@as(u64, 0), model.skill_rename_key);
    const sidecar = pendingSpawnKey(&fx, model.daemon_set_skills_enabled_key) orelse return error.MissingSetSkillsEnabled;
    try testing.expect(daemon_proxy.isSidecarArgv(sidecar.argv));
    try testing.expectEqualStrings("faku", sidecar.argv[0]);
    try testing.expectEqualStrings(daemon_proxy.SUBCOMMAND, sidecar.argv[1]);
    try testing.expectEqualStrings("127.0.0.1:8787", sidecar.argv[2]);
    try testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"hello\"") != null);
    try testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"setSkillsEnabled\"") != null);
    try testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"dirs\":[") != null);
    try testing.expect(std.mem.indexOf(u8, sidecar.stdin, skill_dir) != null);
    try testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"enabled\":false") != null);
    try testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"loadSkills\"") == null);
    try testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"trashSkills\"") == null);
    try testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"prompt\"") == null);
    try testing.expectEqual(sidecar.key, model.daemon_set_skills_enabled_key);
    try testing.expect(sidecar.key != model.daemon_load_skills_key);
    try testing.expect(sidecar.key != model.skill_key);
    try testing.expect(sidecar.key != model.skill_rename_key);
    try testing.expect(!model.skill_set_skills_enabled_ok);

    const in_flight = model.daemon_set_skills_enabled_key;
    const spawn_count = fx.pendingSpawnCount();
    toggleSkillEnabled(&model, &fx);
    try testing.expectEqual(in_flight, model.daemon_set_skills_enabled_key);
    try testing.expectEqual(spawn_count, fx.pendingSpawnCount());
    try testing.expectEqual(@as(u64, 0), model.skill_rename_key);
}

test "setSkillsEnabled ack refreshes; unknown-command falls back to rename" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const root = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-skills-toggle-ack", .{tmp.sub_path[0..]});
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
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    const id = model.addSession("skills toggle ack", .fx);
    model.selected = id;
    model.sessionById(id).?.setProjectPath(root);
    writeFixed(&model.skill_probe_path_storage, &model.skill_probe_path_len, root);
    applyStdoutPaths(&model, "skills/demo/SKILL.md\n");
    selectSkill(&model, 1);

    toggleSkillEnabled(&model, &fx);
    const sidecar = pendingSpawnKey(&fx, model.daemon_set_skills_enabled_key) orelse return error.MissingSetSkillsEnabledAck;
    const ack_key = sidecar.key;
    applySetSkillsEnabledLine(&model, .{ .key = ack_key + 9, .line = set_skills_enabled_ack_line });
    try testing.expect(!model.skill_set_skills_enabled_ok);
    applySetSkillsEnabledLine(&model, .{ .key = ack_key, .line = "{\"type\":\"hello\"}" });
    try testing.expect(!model.skill_set_skills_enabled_ok);
    applySetSkillsEnabledLine(&model, .{ .key = ack_key, .line = set_skills_enabled_ack_line });
    try testing.expect(model.skill_set_skills_enabled_ok);

    handleSetSkillsEnabledExit(&model, &fx, .{ .key = ack_key + 9, .reason = .exited, .code = 0 });
    try testing.expectEqual(ack_key, model.daemon_set_skills_enabled_key);
    try testing.expectEqual(@as(u32, 1), cachedCount(&model));

    handleSetSkillsEnabledExit(&model, &fx, .{ .key = ack_key, .reason = .exited, .code = 0 });
    try testing.expectEqual(@as(u64, 0), model.daemon_set_skills_enabled_key);
    try testing.expect(!model.skill_set_skills_enabled_ok);
    try testing.expectEqual(@as(u64, 0), model.skill_rename_key);
    try testing.expectEqual(@as(u32, 0), cachedCount(&model));
    const reload = pendingSpawnKey(&fx, model.daemon_load_skills_key) orelse return error.MissingLoadSkillsAfterAck;
    try testing.expect(std.mem.indexOf(u8, reload.stdin, "\"type\":\"loadSkills\"") != null);

    applyStdoutPaths(&model, "skills/demo/SKILL.md\n");
    selectSkill(&model, 1);
    toggleSkillEnabled(&model, &fx);
    const miss = pendingSpawnKey(&fx, model.daemon_set_skills_enabled_key) orelse return error.MissingSetSkillsEnabledMiss;
    const miss_key = miss.key;
    applySetSkillsEnabledLine(&model, .{ .key = miss_key, .line = set_skills_enabled_unknown_line });
    try testing.expect(!model.skill_set_skills_enabled_ok);
    handleSetSkillsEnabledExit(&model, &fx, .{ .key = miss_key, .reason = .exited, .code = 1 });
    try testing.expectEqual(@as(u64, 0), model.daemon_set_skills_enabled_key);
    try testing.expect(model.skill_rename_key >= skills_rename_key_first);
    const rename = pendingSpawnKey(&fx, model.skill_rename_key) orelse return error.MissingRenameFallback;
    try testing.expect(isSkillsRenameArgv(rename.argv));
    try testing.expectEqualStrings(skill_dir, rename.argv[4]);
    try testing.expectEqualStrings(skill_filename, rename.argv[7]);
    try testing.expectEqualStrings(disabled_skill_filename, rename.argv[8]);
    try testing.expectEqual(@as(u32, 1), cachedCount(&model));
}

test "writeSetSkillsEnabledStdin overflow keeps rename fallback" {
    var tiny: [32]u8 = undefined;
    try std.testing.expectError(error.NoSpaceLeft, daemon_proxy.writeSetSkillsEnabledStdin(&tiny, .{
        .dirs = &.{"/tmp/faku/.cursor/skills/to-spec"},
        .enabled = false,
    }));
}

const trash_skills_ack_line =
    "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-00000000001b\",\"outcome\":{\"status\":\"ok\",\"payload\":{\"type\":\"ack\"}}}";

const trash_skills_unknown_line =
    "{\"type\":\"response\",\"requestId\":\"00000000-0000-0000-0000-00000000001b\",\"outcome\":{\"status\":\"error\",\"error\":{\"message\":\"unknown command\"}}}";

test "arming clears on select change; same skill keeps arming" {
    var model = Model{};
    applyStdoutPaths(&model, "skills/one/SKILL.md\nskills/two/SKILL.md\n");
    selectSkill(&model, 1);
    try std.testing.expectEqual(@as(u32, 1), model.skill_selected_id);
    try std.testing.expect(!model.skill_delete_arming);
    armSkillDelete(&model);
    try std.testing.expect(model.skill_delete_arming);
    selectSkill(&model, 1);
    try std.testing.expect(model.skill_delete_arming);
    selectSkill(&model, 2);
    try std.testing.expect(!model.skill_delete_arming);
    try std.testing.expectEqual(@as(u32, 2), model.skill_selected_id);
    armSkillDelete(&model);
    try std.testing.expect(model.skill_delete_arming);
    selectSkill(&model, 0);
    try std.testing.expect(!model.skill_delete_arming);
}

test "confirmSkillDelete with a daemon address spawns trashSkills sidecar; no setSkillsEnabled" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const root = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-skills-trash-daemon", .{tmp.sub_path[0..]});
    var skill_dir_buf: [256]u8 = undefined;
    const skill_dir = try std.fmt.bufPrint(&skill_dir_buf, "{s}/skills/demo", .{root});
    try std.Io.Dir.cwd().createDirPath(testing.io, skill_dir);
    var file_buf: [256]u8 = undefined;
    const file_path = try std.fmt.bufPrint(&file_buf, "{s}/SKILL.md", .{skill_dir});
    try std.Io.Dir.cwd().writeFile(testing.io, .{
        .sub_path = file_path,
        .data =
        \\---
        \\name: trash-me
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
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    writeFixed(&model.skill_probe_path_storage, &model.skill_probe_path_len, root);
    applyStdoutPaths(&model, "skills/demo/SKILL.md\n");
    selectSkill(&model, 1);

    confirmSkillDelete(&model, &fx);
    try testing.expectEqual(@as(u64, 0), model.daemon_trash_skills_key);
    try testing.expectEqual(@as(u64, 0), model.skill_remove_key);

    armSkillDelete(&model);
    confirmSkillDelete(&model, &fx);
    try testing.expectEqual(@as(u64, 0), model.skill_rename_key);
    try testing.expectEqual(@as(u64, 0), model.daemon_set_skills_enabled_key);
    const sidecar = pendingSpawnKey(&fx, model.daemon_trash_skills_key) orelse return error.MissingTrashSkills;
    try testing.expect(daemon_proxy.isSidecarArgv(sidecar.argv));
    try testing.expectEqualStrings("faku", sidecar.argv[0]);
    try testing.expectEqualStrings(daemon_proxy.SUBCOMMAND, sidecar.argv[1]);
    try testing.expectEqualStrings("127.0.0.1:8787", sidecar.argv[2]);
    try testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"hello\"") != null);
    try testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"trashSkills\"") != null);
    try testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"dirs\":[") != null);
    try testing.expect(std.mem.indexOf(u8, sidecar.stdin, skill_dir) != null);
    try testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"enabled\"") == null);
    try testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"loadSkills\"") == null);
    try testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"setSkillsEnabled\"") == null);
    try testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"prompt\"") == null);
    try testing.expectEqual(sidecar.key, model.daemon_trash_skills_key);
    try testing.expect(sidecar.key != model.daemon_load_skills_key);
    try testing.expect(sidecar.key != model.daemon_set_skills_enabled_key);
    try testing.expect(sidecar.key != model.skill_key);
    try testing.expect(sidecar.key != model.skill_rename_key);
    try testing.expect(sidecar.key != model.skill_remove_key);
    try testing.expect(!model.skill_trash_ok);

    const in_flight = model.daemon_trash_skills_key;
    const spawn_count = fx.pendingSpawnCount();
    confirmSkillDelete(&model, &fx);
    try testing.expectEqual(in_flight, model.daemon_trash_skills_key);
    try testing.expectEqual(spawn_count, fx.pendingSpawnCount());
    try testing.expectEqual(@as(u64, 0), model.skill_remove_key);
    toggleSkillEnabled(&model, &fx);
    try testing.expectEqual(in_flight, model.daemon_trash_skills_key);
    try testing.expectEqual(@as(u64, 0), model.daemon_set_skills_enabled_key);
    try testing.expectEqual(spawn_count, fx.pendingSpawnCount());
}

test "trashSkills ack refreshes; unknown-command falls back to remove; no setSkillsEnabled" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const root = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-skills-trash-ack", .{tmp.sub_path[0..]});
    var skill_dir_buf: [256]u8 = undefined;
    const skill_dir = try std.fmt.bufPrint(&skill_dir_buf, "{s}/skills/demo", .{root});
    try std.Io.Dir.cwd().createDirPath(testing.io, skill_dir);
    var file_buf: [256]u8 = undefined;
    const file_path = try std.fmt.bufPrint(&file_buf, "{s}/SKILL.md", .{skill_dir});
    try std.Io.Dir.cwd().writeFile(testing.io, .{
        .sub_path = file_path,
        .data =
        \\---
        \\name: trash-me
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
    model.setLastDaemonAddress("127.0.0.1:8787");
    model.setSidecarPath("faku");
    const id = model.addSession("skills trash ack", .fx);
    model.selected = id;
    model.sessionById(id).?.setProjectPath(root);
    writeFixed(&model.skill_probe_path_storage, &model.skill_probe_path_len, root);
    applyStdoutPaths(&model, "skills/demo/SKILL.md\n");
    selectSkill(&model, 1);
    armSkillDelete(&model);

    confirmSkillDelete(&model, &fx);
    const sidecar = pendingSpawnKey(&fx, model.daemon_trash_skills_key) orelse return error.MissingTrashSkillsAck;
    const ack_key = sidecar.key;
    try testing.expect(std.mem.indexOf(u8, sidecar.stdin, "\"type\":\"setSkillsEnabled\"") == null);
    applyTrashSkillsLine(&model, .{ .key = ack_key + 9, .line = trash_skills_ack_line });
    try testing.expect(!model.skill_trash_ok);
    applyTrashSkillsLine(&model, .{ .key = ack_key, .line = "{\"type\":\"hello\"}" });
    try testing.expect(!model.skill_trash_ok);
    applyTrashSkillsLine(&model, .{ .key = ack_key, .line = trash_skills_ack_line });
    try testing.expect(model.skill_trash_ok);

    handleTrashSkillsExit(&model, &fx, .{ .key = ack_key + 9, .reason = .exited, .code = 0 });
    try testing.expectEqual(ack_key, model.daemon_trash_skills_key);
    try testing.expectEqual(@as(u32, 1), cachedCount(&model));

    handleTrashSkillsExit(&model, &fx, .{ .key = ack_key, .reason = .exited, .code = 0 });
    try testing.expectEqual(@as(u64, 0), model.daemon_trash_skills_key);
    try testing.expect(!model.skill_trash_ok);
    try testing.expect(!model.skill_delete_arming);
    try testing.expectEqual(@as(u64, 0), model.skill_remove_key);
    try testing.expectEqual(@as(u32, 0), cachedCount(&model));
    const reload = pendingSpawnKey(&fx, model.daemon_load_skills_key) orelse return error.MissingLoadSkillsAfterTrashAck;
    try testing.expect(std.mem.indexOf(u8, reload.stdin, "\"type\":\"loadSkills\"") != null);
    try testing.expect(std.mem.indexOf(u8, reload.stdin, "\"type\":\"setSkillsEnabled\"") == null);
    try testing.expect(std.mem.indexOf(u8, reload.stdin, "\"type\":\"trashSkills\"") == null);

    applyStdoutPaths(&model, "skills/demo/SKILL.md\n");
    selectSkill(&model, 1);
    armSkillDelete(&model);
    confirmSkillDelete(&model, &fx);
    const miss = pendingSpawnKey(&fx, model.daemon_trash_skills_key) orelse return error.MissingTrashSkillsMiss;
    const miss_key = miss.key;
    applyTrashSkillsLine(&model, .{ .key = miss_key, .line = trash_skills_unknown_line });
    try testing.expect(!model.skill_trash_ok);
    handleTrashSkillsExit(&model, &fx, .{ .key = miss_key, .reason = .exited, .code = 1 });
    try testing.expectEqual(@as(u64, 0), model.daemon_trash_skills_key);
    try testing.expect(model.skill_remove_key >= skills_remove_key_first);
    const remove = pendingSpawnKey(&fx, model.skill_remove_key) orelse return error.MissingRemoveFallback;
    try testing.expect(isSkillsRemoveArgv(remove.argv));
    try testing.expectEqualStrings(root, remove.argv[4]);
    try testing.expectEqualStrings(skill_dir, remove.argv[8]);
    try testing.expectEqual(@as(u32, 1), cachedCount(&model));
}

test "confirmSkillDelete without daemon address uses remove fallback" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const root = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-skills-trash-local", .{tmp.sub_path[0..]});
    var skill_dir_buf: [256]u8 = undefined;
    const skill_dir = try std.fmt.bufPrint(&skill_dir_buf, "{s}/skills/demo", .{root});
    try std.Io.Dir.cwd().createDirPath(testing.io, skill_dir);
    var file_buf: [256]u8 = undefined;
    const file_path = try std.fmt.bufPrint(&file_buf, "{s}/SKILL.md", .{skill_dir});
    try std.Io.Dir.cwd().writeFile(testing.io, .{
        .sub_path = file_path,
        .data =
        \\---
        \\name: trash-me
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
    writeFixed(&model.skill_probe_path_storage, &model.skill_probe_path_len, root);
    applyStdoutPaths(&model, "skills/demo/SKILL.md\n");
    selectSkill(&model, 1);
    armSkillDelete(&model);
    confirmSkillDelete(&model, &fx);
    try testing.expectEqual(@as(u64, 0), model.daemon_trash_skills_key);
    try testing.expect(model.skill_remove_key >= skills_remove_key_first);
    const remove = pendingSpawnKey(&fx, model.skill_remove_key) orelse return error.MissingLocalRemove;
    try testing.expect(isSkillsRemoveArgv(remove.argv));
    try testing.expectEqualStrings(skill_dir, remove.argv[8]);
}

test "writeTrashSkillsStdin overflow keeps remove fallback" {
    var tiny: [32]u8 = undefined;
    try std.testing.expectError(error.NoSpaceLeft, daemon_proxy.writeTrashSkillsStdin(&tiny, .{
        .dirs = &.{"/tmp/faku/.cursor/skills/to-spec"},
    }));
}

test "Delete miss / remove-fail window_status follows Appearance language" {
    const testing = std.testing;
    try testing.expectEqualStrings("Could not delete skill.", could_not_delete_status);
    try testing.expectEqualStrings(i18n.skillsTrashStatusChromeFor(.english, "").delete_failed, could_not_delete_status);

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    try testing.expectEqualStrings(could_not_delete_status, model.skill_delete_failed_status());

    model.skill_remove_key = skills_remove_key_first;
    handleRemoveExit(&model, &fx, .{ .key = skills_remove_key_first, .reason = .exited, .code = 1 });
    try testing.expectEqual(@as(u64, 0), model.skill_remove_key);
    try testing.expectEqualStrings(could_not_delete_status, model.window_status());
    try testing.expectEqualStrings(model.skill_delete_failed_status(), model.window_status());

    applyStdoutPaths(&model, "SKILL.md\n");
    selectSkill(&model, 1);
    armSkillDelete(&model);
    model.clearWindowStatus();
    confirmSkillDelete(&model, &fx);
    try testing.expectEqualStrings(could_not_delete_status, model.window_status());
    try testing.expectEqual(@as(u64, 0), model.skill_remove_key);
    try testing.expectEqual(@as(u64, 0), model.daemon_trash_skills_key);

    model.language_preference = .simplified_chinese;
    model.skill_remove_key = skills_remove_key_first;
    handleRemoveExit(&model, &fx, .{ .key = skills_remove_key_first, .reason = .exited, .code = 1 });
    try testing.expectEqualStrings("无法删除技能。", model.window_status());
    try testing.expectEqualStrings(i18n.skillsTrashStatusChromeFor(.simplified_chinese, "").delete_failed, model.window_status());
    try testing.expect(!std.mem.eql(u8, could_not_delete_status, model.window_status()));

    model.language_preference = .japanese;
    model.skill_remove_key = skills_remove_key_first;
    handleRemoveExit(&model, &fx, .{ .key = skills_remove_key_first, .reason = .exited, .code = 1 });
    try testing.expectEqualStrings("スキルを削除できませんでした。", model.window_status());
    try testing.expectEqualStrings(i18n.skillsTrashStatusChromeFor(.japanese, "").delete_failed, model.window_status());

    model.language_preference = .english;
    model.setSystemLocaleId("ja_JP.UTF-8");
    model.skill_remove_key = skills_remove_key_first;
    handleRemoveExit(&model, &fx, .{ .key = skills_remove_key_first, .reason = .exited, .code = 1 });
    try testing.expectEqualStrings(could_not_delete_status, model.window_status());
    try testing.expectEqualStrings("Could not delete skill.", model.window_status());

    model.language_preference = .system;
    model.setSystemLocaleId("zh_CN.UTF-8");
    model.skill_remove_key = skills_remove_key_first;
    handleRemoveExit(&model, &fx, .{ .key = skills_remove_key_first, .reason = .exited, .code = 1 });
    try testing.expectEqualStrings("无法删除技能。", model.window_status());

    model.setSystemLocaleId("ja_JP.UTF-8");
    model.skill_remove_key = skills_remove_key_first;
    handleRemoveExit(&model, &fx, .{ .key = skills_remove_key_first, .reason = .exited, .code = 1 });
    try testing.expectEqualStrings("スキルを削除できませんでした。", model.window_status());
}

test "Enable/Disable rename-fail window_status follows Appearance language" {
    const testing = std.testing;
    try testing.expectEqualStrings("Could not update skill.", could_not_update_status);
    try testing.expectEqualStrings(i18n.skillsEnableStatusChromeFor(.english, "").enable_failed, could_not_update_status);
    try testing.expect(!std.mem.eql(u8, could_not_update_status, could_not_delete_status));

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    try testing.expectEqualStrings(could_not_update_status, model.skill_enable_failed_status());

    applyStdoutPaths(&model, "SKILL.md\n");
    try testing.expectEqual(@as(u32, 1), cachedCount(&model));
    try testing.expect(cachedEnabled(&model, 0));

    model.skill_rename_key = skills_rename_key_first;
    handleRenameExit(&model, &fx, .{ .key = skills_rename_key_first, .reason = .exited, .code = 1 });
    try testing.expectEqual(@as(u64, 0), model.skill_rename_key);
    try testing.expectEqual(@as(u32, 1), cachedCount(&model));
    try testing.expect(cachedEnabled(&model, 0));
    try testing.expectEqualStrings(could_not_update_status, model.window_status());
    try testing.expectEqualStrings(model.skill_enable_failed_status(), model.window_status());

    model.clearWindowStatus();
    model.skill_rename_key = skills_rename_key_first + 1;
    handleRenameExit(&model, &fx, .{ .key = skills_rename_key_first + 1, .reason = .cancelled, .code = 0 });
    try testing.expectEqual(@as(u64, 0), model.skill_rename_key);
    try testing.expectEqual(@as(u32, 1), cachedCount(&model));
    try testing.expectEqualStrings(could_not_update_status, model.window_status());

    model.language_preference = .simplified_chinese;
    model.skill_rename_key = skills_rename_key_first;
    handleRenameExit(&model, &fx, .{ .key = skills_rename_key_first, .reason = .exited, .code = 1 });
    try testing.expectEqualStrings("无法更新技能。", model.window_status());
    try testing.expectEqualStrings(i18n.skillsEnableStatusChromeFor(.simplified_chinese, "").enable_failed, model.window_status());
    try testing.expect(!std.mem.eql(u8, could_not_update_status, model.window_status()));
    try testing.expectEqual(@as(u32, 1), cachedCount(&model));

    model.language_preference = .japanese;
    model.skill_rename_key = skills_rename_key_first;
    handleRenameExit(&model, &fx, .{ .key = skills_rename_key_first, .reason = .exited, .code = 1 });
    try testing.expectEqualStrings("スキルを更新できませんでした。", model.window_status());
    try testing.expectEqualStrings(i18n.skillsEnableStatusChromeFor(.japanese, "").enable_failed, model.window_status());

    model.language_preference = .english;
    model.setSystemLocaleId("ja_JP.UTF-8");
    model.skill_rename_key = skills_rename_key_first;
    handleRenameExit(&model, &fx, .{ .key = skills_rename_key_first, .reason = .exited, .code = 1 });
    try testing.expectEqualStrings(could_not_update_status, model.window_status());
    try testing.expectEqualStrings("Could not update skill.", model.window_status());

    model.language_preference = .system;
    model.setSystemLocaleId("zh_CN.UTF-8");
    model.skill_rename_key = skills_rename_key_first;
    handleRenameExit(&model, &fx, .{ .key = skills_rename_key_first, .reason = .exited, .code = 1 });
    try testing.expectEqualStrings("无法更新技能。", model.window_status());

    model.setSystemLocaleId("ja_JP.UTF-8");
    model.skill_rename_key = skills_rename_key_first;
    handleRenameExit(&model, &fx, .{ .key = skills_rename_key_first, .reason = .exited, .code = 1 });
    try testing.expectEqualStrings("スキルを更新できませんでした。", model.window_status());

    model.clearWindowStatus();
    model.skill_rename_key = skills_rename_key_first;
    handleRenameExit(&model, &fx, .{ .key = skills_rename_key_first, .reason = .exited, .code = 0 });
    try testing.expectEqual(@as(u64, 0), model.skill_rename_key);
    try testing.expectEqual(@as(u32, 0), cachedCount(&model));
    try testing.expect(!model.has_window_status());
}
