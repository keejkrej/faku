//! Settings Skills + composer `$` insert / `/` slash rows: bounded
//! `SKILL.md` scan plus first-cut enable/disable via daemon
//! `setSkillsEnabled` (ack) or on-disk rename fallback, and first-cut
//! Delete via daemon `trashSkills` (ack) or a Faku-side permanent
//! directory-remove fallback.
//!
//! Native has no FS watcher. Unix one-shots a packed `find` for
//! `SKILL.md` and `SKILL.md.disabled` (Waku `DISABLED_SKILL_FILE`)
//! through the same `/bin/sh -c` chdir workaround `fx ask` uses
//! (`cd -- "$1"`; project cwd and user roots stay argv slots). Windows
//! cannot use `/bin/sh` or `find`:
//! `powershell.exe -NoProfile -Command {…} -Args <project_path> [user roots…]`
//! (`$args[0]` project, `$args[1…]` existing user roots; never
//! interpolate `$HOME` into `-Command`). Same skip names / project
//! depth 8 / user-root depth 2 / cap `max_skills`. Does **not** prune
//! `.*` — project skills live under `.cursor/skills` / `.agents/skills`.
//! Local walk prints project-relative lines first, then absolute paths
//! from Waku `user_skill_locations` that exist (HOME missing skips
//! user roots fail-closed). One scan cycle / in-flight flag. Nested
//! chdir wrapper + 9 user slots would exceed Native `max_effect_argv`
//! 16, so one packed script stays under the cap. Settings → Skills
//! still `refresh`s on page open.
//! Composer `$` / `/` slash-prefix calls `ensureScanned` even when
//! `settings_page != .skills`. Scan root is the selected session
//! `project_path` when that directory exists, else settings
//! `last_project_path`. Skip `node_modules` / `target` / `dist` /
//! `build` / `out` / `vendor` / `__pycache__`. Cap 64 rows (project
//! hits first, then user roots in Waku order). Name comes
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
//! / no address keep today's local project+user `find` / powershell
//! walk. Own daemon spawn key (`next_daemon_key` on
//! `daemon_load_skills_key`) — not the find-walk band (530+) or
//! rename band (580+). Local user roots (only those that exist):
//! `$HOME/.agents/skills`; `$CLAUDE_CONFIG_DIR/skills` when
//! `CLAUDE_CONFIG_DIR` is set and absolute, else `$HOME/.claude/skills`;
//! `$HOME/.codex/skills`; `$HOME/.config/opencode/skills`;
//! `$HOME/.cursor/skills`; `$HOME/.fx/skills`; `$HOME/.pi/agent/skills`;
//! `$HOME/.omp/agent/skills`; `$HOME/.config/agents/skills`.
//! `HOME` / `USERPROFILE` / `CLAUDE_CONFIG_DIR` via Zig std process
//! env (same class as locale env). Windows home prefers
//! `USERPROFILE`. Daemon `loadSkills` still replaces `skill_store`
//! on ok.
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
//! project / Scanning skill folders… / No skills found / No skills
//! match your search follow `i18n.SkillsEmptyChrome`
//! (distinct from FilterChrome / RightPanelChrome; composer `$`
//! insert empty reuses Open a project / No skills found only).
//! Richer empty title / description when a project is open, scan is
//! idle, and `skill_count == 0` follow `i18n.SkillsEmptyRichChrome`
//! (distinct from SkillsEmptyChrome so the single-line hints stay
//! independently evolvable; composer `$` insert empty unchanged). Enable / Disable / Disabled
//! badge follow `i18n.SkillsEnableChrome` (distinct from
//! ProvidersChrome). Enable/Disable rename-fail window_status
//! Could not update skill. follows `i18n.SkillsEnableStatusChrome`
//! (distinct from SkillsEnableChrome Enable / Disable / Disabled
//! and from SkillsTrashStatusChrome). Delete / Confirm delete follow
//! `i18n.SkillsTrashChrome` (distinct from SkillsEnableChrome /
//! SkillsEmptyChrome). Delete miss / remove-fail window_status
//! Could not delete skill. follows `i18n.SkillsTrashStatusChrome`
//! (distinct from SkillsTrashChrome Delete / Confirm delete).
//! Delete success window_status Moved “%{name}” to the Trash
//! follows `i18n.SkillsDeletedToastChrome` (distinct from
//! SkillsTrashChrome / SkillsTrashStatusChrome /
//! SkillsPathCopiedChrome; `%{name}` is captured from `skill_store`
//! before `skill_selected_id = 0`). Daemon `trashSkills` is best-effort; the fallback is a
//! permanent directory remove, not OS Trash. First-cut Open in
//! editor for the selected skill calls
//! `open_editor.startOpenEditorAt` at the absolute `SKILL.md` /
//! `SKILL.md.disabled` path from `joinProbeRelpath` (same Cursor /
//! code / `open -a` sidecar as Files preview). Fail closed with no
//! selection / empty / invalid path. Label follows
//! `i18n.SkillsOpenFileChrome.open_file` via Model
//! `skill_open_file_label` (English matches Waku `skills.open_file`;
//! distinct from FilePreviewChrome / ComposerProjectChrome). Not an embedded editor, not
//! `open_in_app`, not a daemon method. First-cut Reveal for the
//! selected skill calls `reveal_folder.startRevealPath` at the
//! absolute `SKILL.md` / `SKILL.md.disabled` path from
//! `selectedSkillAbsPath` (parent directory via Finder / xdg-open /
//! explorer — same sidecar as composer Reveal folder). Fail closed
//! with no selection / empty / unresolved path (no spawn).
//! `.missing_bin` paints `hostMissingStatusFor`. Label follows
//! `i18n.SkillsRevealChrome.reveal` via Model
//! `skill_reveal_label` (English matches Waku `skills.reveal`;
//! distinct from ComposerProjectChrome Reveal folder). Not Open in
//! editor, not a daemon method.
//! First-cut Copy path for the selected skill writes the absolute
//! skill parent directory (install dir, not `SKILL.md`) through
//! Native `fx.writeClipboard` via `copy.copyText` / `copy_turn_key`.
//! Same parent as Enable/Disable / Delete (`absSkillParent` from
//! selected store path + probe root). Fail closed with no
//! selection / empty / unresolved path (no clipboard write, no
//! window_status, no crash). Successful write sets window_status
//! Path copied (`i18n.SkillsPathCopiedChrome.path_copied` via Model
//! `skill_path_copied_status`). Label follows
//! `i18n.SkillsCopyPathChrome.copy_path` via
//! Model `skill_copy_path_label` (English matches Waku
//! `skills.copy_path`; distinct from ComposerProjectChrome Copy
//! path). Not Reveal, not Open in editor,
//! not a daemon method. Delete success (daemon `trashSkills` ack
//! or permanent-remove exit 0) sets window_status Moved
//! “%{name}” to the Trash (`i18n.SkillsDeletedToastChrome.deleted_toast`
//! via Model `skill_deleted_status`; name from cache before clear;
//! Faku has no OS Trash crate on the fallback — chrome still
//! matches Waku `skills.deleted_toast`). Not a Native FS API. Unselected-detail
//! Select a skill follows `i18n.SkillsSelectChrome` (distinct from
//! SkillsEmptyChrome; muted Native text when the list has rows and
//! none is selected). Count / filter caption follows
//! `i18n.SkillsCountChrome` (distinct from FilterChrome /
//! SkillsEmptyChrome / SkillsSelectChrome; muted Native text after
//! the filter field when emptyHint does not own that space;
//! `disabled` is total cached disabled like Waku library header;
//! a trimmed text query or a source filter uses `N of M shown`).
//! Settings Skills source filter follows Waku `skills.filter_all`
//! (`i18n.SkillsFilterAllChrome`; All skills chip, then Shared /
//! Claude / Codex / Cursor / fx / OpenCode / Pi / OMP from
//! `SkillSourceKind` skipping `unknown`; a grouped skill stays
//! visible when any same-scope install lives under that source
//! tree). Composer `$` insert / slash skill rows stay flat and
//! unfiltered by source. Settings Skills library / details pane
//! titles follow `i18n.SkillsPaneChrome` (`library` / `details`;
//! English matches Waku `skills.library` / `skills.details`;
//! muted/bold Native text above the stacked library block and
//! above the detail block; distinct from SkillsSectionChrome User /
//! SkillsSelectChrome Select a skill / SkillsDetailChrome /
//! SkillsEmptyChrome / SkillsCountChrome / Chrome.skills /
//! StructuralRegionChrome; not a side-by-side two-pane layout).
//! Settings Skills library section headers follow
//! `i18n.SkillsSectionChrome` (`section_user` only; English matches
//! Waku GPUI `skills.section_user`; project section paints the
//! project name; distinct from SkillsEmptyChrome / SkillsCountChrome
//! / SkillsSelectChrome). Composer `$` insert / slash skill rows
//! stay flat. Selected-detail No description / Invoke / Location /
//! Contents follow `i18n.SkillsDetailChrome` (distinct from
//! SkillsEmptyChrome / SkillsSelectChrome / SkillsCountChrome /
//! SkillsSectionChrome; description / `/name` / path stay data;
//! Contents value is supporting-file count · bytes
//! (`SkillsFileCountChrome` + Latin B/KB/MB; `{skill_body}` stays
//! a separate block); Updated lives in `SkillsUpdatedChrome`;
//! Allowed tools lives in `SkillsAllowedToolsChrome`). Settings
//! list folds same-name installs within a scope (project vs user;
//! case-insensitive name; primary is first in Waku user-root order).
//! Selected-detail multi-location lines follow `i18n.SkillsSourceChrome`
//! (Shared + provider shorts) when a row has more than one install;
//! a single install still uses SkillsDetailChrome Location.
//! Cross-scope same name shows `i18n.SkillsDuplicateChrome`
//! (`has_skill_duplicate_badge` fail-closed when duplicates==0).
//! Selected-detail header paints the grouped primary name, optional
//! Disabled badge (`i18n.SkillsEnableChrome.disabled`), and a muted
//! sources · scope caption (`i18n.SkillsScopeChrome`; unique
//! `SkillsSourceChrome` labels in Waku user-root / `collectGroupIndices`
//! order; project-relative primary uses `scope_in_project` with
//! `sectionProjectLabel`, else `scope_user_detail`;
//! `has_skill_scope_caption` fail-closed). Enable / Disable / Delete / Open / Reveal / Copy path operate on
//! the primary install this cut. Composer `$` insert / slash skill
//! rows stay flat (ungrouped) and ignore the Settings source
//! filter.
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
const copy = @import("copy.zig");

const Model = model_exports.Model;
const Effects = main.Effects;
const writeFixed = model_exports.writeFixed;
const ChipPickerRow = model_exports.ChipPickerRow;

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
/// Waku `user_skill_locations` count. Only existing roots are argv slots.
pub const max_user_skill_roots: usize = 9;
/// Cap extra install dirs per Settings list row (Waku user-root
/// count plus one project install). Overflow fail-closed.
pub const max_skill_installs: usize = max_user_skill_roots + 1;
/// One-line UI cap for YAML `description:` (larger than name; not the body).
pub const max_skill_description: usize = 160;
/// One-line UI cap for YAML `allowed-tools:` on the selected-detail
/// Tools row. Same order as `max_skill_description`. Overflow
/// truncates; missing / empty / unfenced stays empty (no row).
pub const max_skill_allowed_tools: usize = 160;
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
/// English default for Copy path success window_status.
/// Localized copy lives on `i18n.SkillsPathCopiedChrome.path_copied`
/// via Model `skill_path_copied_status`. Distinct from
/// SkillsCopyPathChrome Copy Path and ComposerProjectChrome Copy
/// path.
pub const path_copied_status = i18n.skillsPathCopiedChromeFor(.english, "").path_copied;
/// English default template for Delete success window_status.
/// Localized copy lives on `i18n.SkillsDeletedToastChrome.deleted_toast`
/// via Model `skill_deleted_status` (`%{name}` substituted). Distinct
/// from SkillsTrashStatusChrome Could not delete skill. and from
/// SkillsPathCopiedChrome Path copied.
pub const deleted_toast_template = i18n.skillsDeletedToastChromeFor(.english, "").deleted_toast;

pub const sh_bin = file_mention.sh_bin;
pub const find_bin = file_mention.find_bin;
pub const find_maxdepth_flag = file_mention.find_maxdepth_flag;
pub const find_maxdepth = file_mention.find_maxdepth;
pub const find_prune = file_mention.find_prune;
pub const find_type_file = file_mention.find_type_file;
pub const find_name_flag = "-name";
/// Shallow user-root walk: `root/<skill>/SKILL.md` is depth 2.
pub const find_user_maxdepth = "2";
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

/// User-root find: `$root` is the loop variable after `shift` (argv
/// slots, not interpolated). Shallow `maxdepth` 2.
pub const find_user_skills_script =
    "find \"$root\" -maxdepth 2 \\( -name node_modules -o -name target -o -name dist -o -name build -o -name out -o -name vendor -o -name __pycache__ \\) -prune -o -type f \\( -name SKILL.md -o -name SKILL.md.disabled \\) -print";

/// One `-c` body: `cd -- "$1"` (project cwd argv slot), project
/// `find .` (relative lines), then remaining argv slots as user roots
/// (absolute lines). Nested `fx_ask_chdir_script` + inner `-c` + 9
/// user slots would be 17 argv (over Native 16), so this packed
/// script stays 5+N (max 14).
pub const unix_skills_walk_script =
    "cd -- \"$1\" || exit 1; " ++ find_skills_script ++ "; st=$?; shift; for root; do [ -d \"$root\" ] || continue; " ++ find_user_skills_script ++ " || :; done; exit $st";

/// Scriptblock + `$args[0]` project path, `$args[1…]` existing user
/// roots: all stay argv slots after `-Args`, never spliced into the
/// `-Command` body. Distinct from `file_mention.powershell_walk_script`:
/// does **not** skip names starting with `.` (skills live under
/// `.cursor` / `.agents`). Files named exactly `SKILL.md` /
/// `SKILL.md.disabled` only. Project walk depth 8 / relative `/`
/// paths; user-root walk depth 2 / absolute `/` paths; same skip
/// names; cap `max_skills` across both. 6+N argv slots (max 15).
pub const powershell_skills_walk_script =
    "{ $ErrorActionPreference='Stop'; $script:skip=@('node_modules','target','dist','build','out','vendor','__pycache__'); $script:want=@('SKILL.md','SKILL.md.disabled'); $script:n=0; function Walk($dir,$depth,$maxd,$asAbs){ if($script:n -ge " ++ max_skills_s ++ "){return}; foreach($item in (Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue)){ if($script:n -ge " ++ max_skills_s ++ "){return}; $d=$depth+1; if($d -gt $maxd){continue}; $name=$item.Name; if($script:skip -contains $name){continue}; if($item.PSIsContainer){ if($d -lt $maxd){ Walk $item.FullName $d $maxd $asAbs } } else { if($script:want -cnotcontains $name){continue}; if($asAbs){ Write-Output ($item.FullName -replace '\\\\','/') } else { $rel=$item.FullName.Substring($script:root.Length).TrimStart('\\','/'); Write-Output ($rel -replace '\\\\','/') }; $script:n++ } } }; $script:root=$args[0].TrimEnd('\\','/'); Walk $script:root 0 8 $false; for($i=1; $i -lt $args.Count; $i++){ if($script:n -ge " ++ max_skills_s ++ "){break}; $u=[string]$args[$i]; if([string]::IsNullOrWhiteSpace($u)){continue}; $u=$u.TrimEnd('\\','/'); if(-not (Test-Path -LiteralPath $u -PathType Container)){continue}; Walk $u 0 2 $true } }";

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

/// Unix packed `-c` is 5 + user roots (max 14). Windows powershell
/// `-Command` + `-Args` is 6 + user roots (max 15). Spawn buffer is
/// Native `max_effect_argv` 16.
pub const walk_argv_len: usize = 16;
pub const unix_walk_argv_base: usize = 5;
pub const windows_walk_argv_base: usize = 6;
pub const unix_walk_argv_len: usize = unix_walk_argv_base + max_user_skill_roots;
pub const windows_walk_argv_len: usize = windows_walk_argv_base + max_user_skill_roots;
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

pub fn unixWalkArgvLen(user_n: usize) usize {
    return unix_walk_argv_base + @min(user_n, max_user_skill_roots);
}

pub fn windowsWalkArgvLen(user_n: usize) usize {
    return windows_walk_argv_base + @min(user_n, max_user_skill_roots);
}

/// Unix: `/bin/sh -c <packed> sh <project_cwd> [user_root…]`.
/// Project cwd is `$1`; user roots stay later argv slots.
pub fn unixWalkArgvFor(cwd: []const u8, user_roots: []const []const u8, buf: *[walk_argv_len][]const u8) []const []const u8 {
    buf[0] = sh_bin;
    buf[1] = "-c";
    buf[2] = unix_skills_walk_script;
    buf[3] = "sh";
    buf[4] = cwd;
    const n = @min(user_roots.len, max_user_skill_roots);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        buf[unix_walk_argv_base + i] = user_roots[i];
    }
    return buf[0..unixWalkArgvLen(n)];
}

/// Windows: `powershell.exe -NoProfile -Command {scriptblock} -Args
/// <project_path> [user_root…]`. Paths stay `$args[0]` / `$args[1…]`
/// — not interpolated into the `-Command` body.
pub fn windowsWalkArgvFor(cwd: []const u8, user_roots: []const []const u8, buf: *[walk_argv_len][]const u8) []const []const u8 {
    buf[0] = powershell_bin;
    buf[1] = powershell_noprofile;
    buf[2] = powershell_command;
    buf[3] = powershell_skills_walk_script;
    buf[4] = powershell_args_flag;
    buf[5] = cwd;
    const n = @min(user_roots.len, max_user_skill_roots);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        buf[windows_walk_argv_base + i] = user_roots[i];
    }
    return buf[0..windowsWalkArgvLen(n)];
}

pub fn argvFor(cwd: []const u8, user_roots: []const []const u8, buf: *[walk_argv_len][]const u8) []const []const u8 {
    return switch (builtin.os.tag) {
        .windows => windowsWalkArgvFor(cwd, user_roots, buf),
        else => unixWalkArgvFor(cwd, user_roots, buf),
    };
}

fn scriptHas(script: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, script, needle) != null;
}

fn isUnixSkillsWalkArgv(argv: []const []const u8) bool {
    if (argv.len < unix_walk_argv_base or argv.len > unix_walk_argv_len) return false;
    if (!std.mem.eql(u8, argv[0], sh_bin)) return false;
    if (!std.mem.eql(u8, argv[1], "-c")) return false;
    if (!std.mem.eql(u8, argv[2], unix_skills_walk_script)) return false;
    if (!std.mem.eql(u8, argv[3], "sh")) return false;
    if (argv[4].len == 0) return false;
    var i: usize = unix_walk_argv_base;
    while (i < argv.len) : (i += 1) {
        if (argv[i].len == 0) return false;
        if (scriptHas(argv[2], argv[i])) return false;
    }
    if (!scriptHas(argv[2], find_skills_script)) return false;
    if (!scriptHas(argv[2], find_user_skills_script)) return false;
    if (!scriptHas(argv[2], find_maxdepth_flag)) return false;
    if (!scriptHas(argv[2], find_maxdepth)) return false;
    if (!scriptHas(argv[2], find_user_maxdepth)) return false;
    if (!scriptHas(argv[2], find_prune)) return false;
    if (!scriptHas(argv[2], find_type_file)) return false;
    if (!scriptHas(argv[2], find_name_flag)) return false;
    if (!scriptHas(argv[2], skill_filename)) return false;
    if (!scriptHas(argv[2], disabled_skill_filename)) return false;
    if (!scriptHas(argv[2], "$1")) return false;
    inline for (walk_skip_names) |name| {
        if (!scriptHas(argv[2], name)) return false;
    }
    return true;
}

fn isWindowsSkillsWalkArgv(argv: []const []const u8) bool {
    if (argv.len < windows_walk_argv_base or argv.len > windows_walk_argv_len) return false;
    if (!std.mem.eql(u8, argv[0], powershell_bin)) return false;
    if (!std.mem.eql(u8, argv[1], powershell_noprofile)) return false;
    if (!std.mem.eql(u8, argv[2], powershell_command)) return false;
    if (!std.mem.eql(u8, argv[3], powershell_skills_walk_script)) return false;
    if (!std.mem.eql(u8, argv[4], powershell_args_flag)) return false;
    if (argv[5].len == 0) return false;
    var i: usize = windows_walk_argv_base;
    while (i < argv.len) : (i += 1) {
        if (argv[i].len == 0) return false;
        if (scriptHas(argv[3], argv[i])) return false;
    }
    if (!scriptHas(argv[3], "$args[0]")) return false;
    if (!scriptHas(argv[3], find_maxdepth)) return false;
    if (!scriptHas(argv[3], find_user_maxdepth)) return false;
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
/// segment, and must look like the selected skill's parent from
/// cache (`skillDirKey`): either equal when that parent is already
/// absolute (user-root catalog paths) or contain it as a path
/// suffix. Absolute paths preferred; nested relative paths (test
/// zig-cache / unusual relative `project_path`) are allowed when they
/// still look like that skill parent.
pub fn trashDirAllowed(dir: []const u8, parent_from_cache: []const u8) bool {
    if (dir.len == 0 or parent_from_cache.len == 0) return false;
    if (std.mem.eql(u8, dir, "/") or std.mem.eql(u8, dir, "\\")) return false;
    if (std.mem.eql(u8, dir, ".") or std.mem.eql(u8, dir, "..")) return false;
    if (std.mem.indexOf(u8, dir, "..") != null) return false;
    const abs_dir = isAbsoluteSkillPath(dir) or std.fs.path.isAbsolute(dir);
    const same_abs = abs_dir and std.mem.eql(u8, dir, parent_from_cache);
    if (!same_abs and !pathEndsWithDir(dir, parent_from_cache)) return false;
    if (abs_dir) return true;
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

/// Process-env inputs for Waku `user_skill_locations`. Tests inject
/// these instead of reading live `$HOME`.
pub const UserSkillEnv = struct {
    home: []const u8 = "",
    userprofile: []const u8 = "",
    claude_config_dir: []const u8 = "",
};

/// `HOME` on Unix; `USERPROFILE` on Windows (then `HOME`). Empty
/// when both are missing (user-root scan fail-closed).
pub fn processHomeDirOn(tag: std.Target.Os.Tag, home: []const u8, userprofile: []const u8) []const u8 {
    return switch (tag) {
        .windows => if (userprofile.len > 0) userprofile else home,
        else => if (home.len > 0) home else userprofile,
    };
}

pub fn processHomeDir(home: []const u8, userprofile: []const u8) []const u8 {
    return processHomeDirOn(builtin.os.tag, home, userprofile);
}

/// Host-agnostic absolute check for `CLAUDE_CONFIG_DIR` (Unix `/…`
/// or Windows drive-letter). Relative / empty → no override.
pub fn isAbsoluteEnvPath(path: []const u8) bool {
    if (path.len == 0) return false;
    if (path[0] == '/' or path[0] == '\\') return true;
    return path.len >= 2 and std.ascii.isAlphabetic(path[0]) and path[1] == ':';
}

fn liveProcessEnviron() std.process.Environ {
    return switch (builtin.os.tag) {
        .windows => .{ .block = .global },
        else => posix: {
            const raw = std.c.environ;
            if (@intFromPtr(raw) == 0) break :posix .{ .block = .empty };
            var n: usize = 0;
            while (raw[n] != null) : (n += 1) {}
            break :posix .{ .block = .{ .slice = raw[0..n :null] } };
        },
    };
}

fn copyProcessEnv(name: []const u8, dest: []u8) []const u8 {
    const value = std.process.Environ.getAlloc(liveProcessEnviron(), std.heap.page_allocator, name) catch return "";
    defer std.heap.page_allocator.free(value);
    if (value.len == 0 or value.len > dest.len) return "";
    @memcpy(dest[0..value.len], value);
    return dest[0..value.len];
}

/// `HOME` / `USERPROFILE` / `CLAUDE_CONFIG_DIR` via Zig std process
/// env (same class as locale env; not a Native env API).
pub fn readProcessUserSkillEnv(home_buf: []u8, userprofile_buf: []u8, claude_buf: []u8) UserSkillEnv {
    return .{
        .home = copyProcessEnv("HOME", home_buf),
        .userprofile = copyProcessEnv("USERPROFILE", userprofile_buf),
        .claude_config_dir = copyProcessEnv("CLAUDE_CONFIG_DIR", claude_buf),
    };
}

fn joinRootRel(root: []const u8, rel: []const u8, buf: []u8) ?[]const u8 {
    const base = std.mem.trimEnd(u8, root, "/\\");
    const rest = std.mem.trim(u8, rel, "/\\");
    if (base.len == 0 or rest.len == 0) return null;
    const printed = std.fmt.bufPrint(buf, "{s}/{s}", .{ base, rest }) catch return null;
    slashNormalizeInPlace(printed);
    return printed;
}

fn claudeSkillsRoot(env: UserSkillEnv, home: []const u8, buf: []u8) ?[]const u8 {
    const claude = std.mem.trim(u8, env.claude_config_dir, " \t\r\n");
    if (claude.len > 0 and isAbsoluteEnvPath(claude)) {
        return joinRootRel(claude, "skills", buf);
    }
    return joinRootRel(home, ".claude/skills", buf);
}

/// Candidate user skill roots in Waku `user_skill_locations` order.
/// Does not check existence. Empty `HOME`/`USERPROFILE` yields zero
/// (fail-closed). Claude is `$CLAUDE_CONFIG_DIR/skills` when that
/// env is set and absolute, else `$HOME/.claude/skills`.
pub fn collectUserSkillRootCandidates(
    env: UserSkillEnv,
    store: *[max_user_skill_roots][max_skill_path]u8,
    dest: *[max_user_skill_roots][]const u8,
) usize {
    const home = processHomeDir(env.home, env.userprofile);
    if (home.len == 0) return 0;

    const rels = [_][]const u8{
        ".agents/skills",
        ".codex/skills",
        ".config/opencode/skills",
        ".cursor/skills",
        ".fx/skills",
        ".pi/agent/skills",
        ".omp/agent/skills",
        ".config/agents/skills",
    };

    var n: usize = 0;
    if (joinRootRel(home, ".agents/skills", store[n][0..])) |path| {
        dest[n] = path;
        n += 1;
    }
    if (claudeSkillsRoot(env, home, store[n][0..])) |path| {
        dest[n] = path;
        n += 1;
    }
    for (rels[1..]) |rel| {
        if (n >= max_user_skill_roots) break;
        if (joinRootRel(home, rel, store[n][0..])) |path| {
            dest[n] = path;
            n += 1;
        }
    }
    return n;
}

/// Keep only directories that exist, in candidate order.
pub fn existingUserSkillRoots(
    io: std.Io,
    candidates: []const []const u8,
    dest: *[max_user_skill_roots][]const u8,
) usize {
    var n: usize = 0;
    for (candidates) |path| {
        if (n >= max_user_skill_roots) break;
        if (path.len == 0) continue;
        if (!util.directoryExists(io, path)) continue;
        dest[n] = path;
        n += 1;
    }
    return n;
}

fn storeUserRootsOnModel(model: *Model, roots: []const []const u8) void {
    const n = @min(roots.len, max_user_skill_roots);
    model.skill_user_root_count = n;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        writeFixed(&model.skill_user_root_storage[i], &model.skill_user_root_len[i], roots[i]);
        slashNormalizeInPlace(model.skill_user_root_storage[i][0..model.skill_user_root_len[i]]);
    }
    while (i < max_user_skill_roots) : (i += 1) {
        model.skill_user_root_len[i] = 0;
    }
}

/// Collect Waku user-root candidates from `env`, keep directories
/// that exist, store them on the model for the packed walk argv.
fn bindUserSkillRootsFromEnv(model: *Model, env: UserSkillEnv) void {
    var cand_store: [max_user_skill_roots][max_skill_path]u8 = undefined;
    var cand_ptrs: [max_user_skill_roots][]const u8 = undefined;
    const cand_n = collectUserSkillRootCandidates(env, &cand_store, &cand_ptrs);
    var existing: [max_user_skill_roots][]const u8 = undefined;
    const exist_n = if (model.store_io) |io|
        existingUserSkillRoots(io, cand_ptrs[0..cand_n], &existing)
    else
        0;
    storeUserRootsOnModel(model, existing[0..exist_n]);
}

fn userRootsOnModel(model: *const Model, dest: *[max_user_skill_roots][]const u8) []const []const u8 {
    const n = @min(model.skill_user_root_count, max_user_skill_roots);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        dest[i] = model.skill_user_root_storage[i][0..model.skill_user_root_len[i]];
    }
    return dest[0..n];
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

/// Native `select_skill` ids for Settings Skills section headers.
/// Sit well above `skillId` (1-based cache, cap `max_skills`) so
/// `for` keys never collide and `selectSkill` can fail closed.
pub const skill_header_id_base: u32 = 1000;
pub const skill_header_id_project: u32 = skill_header_id_base;
pub const skill_header_id_user: u32 = skill_header_id_base + 1;

pub fn isSkillHeaderId(id: u32) bool {
    return id >= skill_header_id_base;
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
    clearSelectedSkillBody(model);
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
    model.skills_source_filter = null;
    model.closeSkillsSourcePicker();
}

/// Leaving Settings → Skills: drop Delete arming and cancel in-flight
/// `trashSkills` / remove (same cancel band refresh uses for
/// `setSkillsEnabled`). Catalog cache stays for composer `$` / `/`.
pub fn leavePage(model: *Model, fx: *Effects) void {
    clearDeleteArming(model);
    cancelTrashSkills(model, fx);
    cancelRemove(model, fx);
    model.closeSkillsSourcePicker();
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

/// Settings Skills project-section label: basename of the open
/// probe path, else `"project"` (same as daemon `loadSkills`
/// projectName). Not i18n.
pub fn sectionProjectLabel(model: *const Model) []const u8 {
    return projectLabel(probePath(model));
}

/// ASCII-uppercase copy for Waku section-header paint. Non-ASCII
/// bytes stay as stored (zh-CN 用户 / ja ユーザー). Native has no
/// text-transform API.
pub fn paintedSectionLabel(arena: std.mem.Allocator, label: []const u8) []const u8 {
    const out = arena.alloc(u8, label.len) catch return label;
    for (label, out) |c, *d| {
        d.* = std.ascii.toUpper(c);
    }
    return out;
}

/// Latin digit count for a section header. Cap is `max_skills`.
pub fn latinCount(arena: std.mem.Allocator, n: usize) []const u8 {
    return std.fmt.allocPrint(arena, "{d}", .{n}) catch "";
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
    var home_buf: [max_skill_path]u8 = undefined;
    var userprofile_buf: [max_skill_path]u8 = undefined;
    var claude_buf: [max_skill_path]u8 = undefined;
    const env = readProcessUserSkillEnv(&home_buf, &userprofile_buf, &claude_buf);
    bindUserSkillRootsFromEnv(model, env);
    var root_ptrs: [max_user_skill_roots][]const u8 = undefined;
    const roots = userRootsOnModel(model, &root_ptrs);

    const key = model.next_skill_key;
    model.next_skill_key = key + 1;
    model.skill_key = key;
    var argv_buf: [walk_argv_len][]const u8 = undefined;
    fx.spawn(.{
        .key = key,
        .argv = argvFor(cwd, roots, &argv_buf),
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

/// Light YAML `allowed-tools:` in a leading `---` fence. Empty when
/// missing. Plain / single-quoted / double-quoted like `description:`.
/// No block-scalar folding / YAML lists this cut (same class as
/// description). Empty / missing / unfenced → fail closed.
pub fn parseFrontmatterAllowedTools(source: []const u8) []const u8 {
    return parseFrontmatterField(source, "allowed-tools:");
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
        const entry = parsed.skills[i];
        const n = if (entry.install_count > 0) entry.install_count else @as(usize, 1);
        var k: usize = 0;
        while (k < n) : (k += 1) {
            if (model.skill_count >= max_skills) break;
            var raw: []const u8 = entry.path;
            var enabled = entry.enabled;
            if (entry.install_count > 0) {
                const inst = entry.installs[k];
                raw = if (inst.skill_file.len > 0) inst.skill_file else inst.dir;
                enabled = inst.enabled;
            }
            var path_buf: [max_skill_path]u8 = undefined;
            const path = catalogStorePath(root, raw, enabled, &path_buf) orelse continue;
            if (path.len == 0 or path.len > max_skill_path) continue;
            const dir = skillDirKey(path);
            if (indexOfSkillDir(model, dir) != null) continue;
            const index = model.skill_count;
            storeSkillAt(model, index, path, enabled);
            if (entry.name.len > 0) {
                model.skill_store[index].setName(displayName(path, entry.name));
            }
            if (entry.description.len > 0) {
                model.skill_store[index].setDescription(entry.description);
            }
            model.skill_count += 1;
        }
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

/// Ok Ack then set deleted-toast window_status, clear arming, and
/// `refresh`. Unknown-command / parse miss / sidecar fail fall back
/// to today's permanent directory remove using the stored skill dir.
pub fn handleTrashSkillsExit(model: *Model, fx: *Effects, exit: native_sdk.EffectExit) void {
    if (exit.key != model.daemon_trash_skills_key or model.daemon_trash_skills_key == 0) return;
    model.daemon_trash_skills_key = 0;
    const ok = model.skill_trash_ok;
    model.skill_trash_ok = false;
    if (ok) {
        applyDeletedToast(model);
        clearDeleteArming(model);
        model.skill_selected_id = 0;
        clearSelectedSkillBody(model);
        refresh(model, fx);
        return;
    }
    if (model.skill_trash_cwd_len == 0) {
        failTrash(model);
        return;
    }
    spawnRemove(model, fx);
}

/// Permanent directory remove settled. Exit 0 paints the same
/// Waku `skills.deleted_toast` as a daemon `trashSkills` ack
/// (Faku has no OS Trash crate on this fallback; chrome still
/// matches Settings Skills parity). Non-zero / cancelled keeps
/// Could not delete skill.
pub fn handleRemoveExit(model: *Model, fx: *Effects, exit: native_sdk.EffectExit) void {
    if (exit.key != model.skill_remove_key or model.skill_remove_key == 0) return;
    model.skill_remove_key = 0;
    const succeeded = exit.reason == .exited and exit.code == 0;
    if (!succeeded) {
        failTrash(model);
        return;
    }
    applyDeletedToast(model);
    clearDeleteArming(model);
    model.skill_selected_id = 0;
    clearSelectedSkillBody(model);
    refresh(model, fx);
}

fn failTrash(model: *Model) void {
    model.setWindowStatus(model.skill_delete_failed_status());
}

/// Capture the selected skill name from cache, then set
/// window_status to the localized deleted toast. Call before
/// `skill_selected_id = 0` / body clear / `refresh` (refresh
/// `clearCache`s the store). Empty name still paints.
fn applyDeletedToast(model: *Model) void {
    var buf: [i18n.skills_deleted_toast_max]u8 = undefined;
    model.setWindowStatus(model.skill_deleted_status(selectedSkillName(model), &buf));
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
    if (isSkillHeaderId(id)) return;
    if (id != model.skill_selected_id) {
        model.skill_delete_arming = false;
    }
    if (id == 0 or id > model.skill_count) {
        model.skill_selected_id = 0;
        clearSelectedSkillBody(model);
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

/// Absolute skill install directory for the selected Settings Skills
/// row. Same join as Enable/Disable / Delete (`absSkillParent` from
/// selected store path + probe root). Null when nothing is selected,
/// the store path is empty, or the join does not resolve.
pub fn selectedSkillAbsParent(model: *const Model, buf: []u8) ?[]const u8 {
    if (model.skill_selected_id == 0 or model.skill_selected_id > model.skill_count) return null;
    const relpath = model.skill_store[model.skill_selected_id - 1].path();
    if (relpath.len == 0) return null;
    const root = model.skill_probe_path_storage[0..model.skill_probe_path_len];
    const parent = absSkillParent(root, relpath, buf) orelse return null;
    if (parent.len == 0) return null;
    return parent;
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

/// YAML `description:` for the selected Settings Skills row.
/// Empty when nothing is selected or the field is missing.
pub fn selectedSkillDescription(model: *const Model) []const u8 {
    if (model.skill_selected_id == 0 or model.skill_selected_id > model.skill_count) return "";
    return model.skill_store[model.skill_selected_id - 1].description();
}

/// `/` + selected skill name. Empty when nothing is selected.
/// Name is skill data, not i18n.
pub fn selectedSkillInvokeLine(model: *const Model, arena: std.mem.Allocator) []const u8 {
    if (model.skill_selected_id == 0 or model.skill_selected_id > model.skill_count) return "";
    const name = model.skill_store[model.skill_selected_id - 1].name();
    var buf: [1 + max_skill_name]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, "/{s}", .{name}) catch return "";
    return copyCaption(arena, text);
}

/// Selected-skill Location value. Prefers the absolute install
/// parent from `selectedSkillAbsParent` (same join as Copy path /
/// Enable/Disable / Delete) when it resolves; else the cached store
/// path the list already shows. Empty when nothing is selected.
pub fn selectedSkillLocation(model: *const Model, arena: std.mem.Allocator) []const u8 {
    if (model.skill_selected_id == 0 or model.skill_selected_id > model.skill_count) return "";
    var parent_buf: [model_exports.max_project_path + max_skill_path + 1]u8 = undefined;
    if (selectedSkillAbsParent(model, &parent_buf)) |parent| {
        return copyCaption(arena, parent);
    }
    return model.skill_store[model.skill_selected_id - 1].path();
}

/// Settings Skills selected-detail relative Updated value.
/// Injects live `std.Io` clock "now"; tests pin buckets through
/// `selectedSkillUpdatedLabelAt`. Empty when unselected, mtime is
/// unknown, or `store_io` is missing.
pub fn selectedSkillUpdatedLabel(model: *const Model, arena: std.mem.Allocator) []const u8 {
    const io = model.store_io orelse return "";
    return selectedSkillUpdatedLabelAt(model, std.Io.Clock.real.now(io).toSeconds(), arena);
}

/// Same as `selectedSkillUpdatedLabel` with caller-injected `now`
/// unix seconds (Waku `updated_label` buckets).
pub fn selectedSkillUpdatedLabelAt(model: *const Model, now_unix: i64, arena: std.mem.Allocator) []const u8 {
    if (model.skill_selected_id == 0 or model.skill_selected_id > model.skill_count) return "";
    if (!model.skill_mtime_valid) return "";
    var buf: [i18n.skills_updated_label_max]u8 = undefined;
    const chrome = i18n.skillsUpdatedChromeFor(model.language_preference, model.systemLocaleId());
    const text = i18n.formatSkillsUpdatedRelative(chrome, model.skill_mtime_unix, now_unix, &buf);
    return copyCaption(arena, text);
}

/// Settings Skills selected-detail Contents value: supporting-file
/// count · bytes (Waku `file_count_one` / `file_count_many` +
/// Latin `format_bytes`). Empty when unselected or when the skill
/// dir cannot be walked.
pub fn selectedSkillContentsSummary(model: *const Model, arena: std.mem.Allocator) []const u8 {
    if (model.skill_selected_id == 0 or model.skill_selected_id > model.skill_count) return "";
    if (!model.skill_contents_valid) return "";
    var buf: [i18n.skills_contents_summary_max]u8 = undefined;
    const chrome = i18n.skillsFileCountChromeFor(model.language_preference, model.systemLocaleId());
    const text = i18n.formatSkillsContentsSummary(chrome, model.skill_supporting_files, model.skill_total_bytes, &buf);
    return copyCaption(arena, text);
}

/// Settings Skills Copy path. Writes the absolute skill parent
/// directory (install dir, not `SKILL.md`) through Native
/// `fx.writeClipboard` via `copy.copyText` / `copy_turn_key`. Fail
/// closed with no selection / empty / unresolved path (no clipboard
/// write, no window_status, no crash). Successful write sets
/// window_status Path copied (`skill_path_copied_status`). Not
/// Reveal, not Open in editor, not a daemon method.
pub fn copySelectedSkillPath(model: *Model, fx: *Effects) void {
    var parent_buf: [model_exports.max_project_path + max_skill_path + 1]u8 = undefined;
    const parent = selectedSkillAbsParent(model, &parent_buf) orelse return;
    copy.copyText(fx, parent);
    model.setWindowStatus(model.skill_path_copied_status());
}

fn clearSelectedSkillBody(model: *Model) void {
    model.skill_body_len = 0;
    model.skill_mtime_unix = 0;
    model.skill_mtime_valid = false;
    model.skill_supporting_files = 0;
    model.skill_total_bytes = 0;
    model.skill_contents_valid = false;
    model.skill_allowed_tools_len = 0;
}

/// Zig `File.Stat.mtime` is ns since epoch: a raw integer on some
/// std cuts, `Io.Timestamp{ .nanoseconds }` on others. Compile
/// against whichever this repo's Zig exposes. Same class as Files
/// preview `mtimeToNs`.
fn mtimeToNs(mtime: anytype) i64 {
    return switch (@typeInfo(@TypeOf(mtime))) {
        .int => @intCast(mtime),
        .@"struct" => @intCast(mtime.nanoseconds),
        else => @compileError("unexpected File.Stat.mtime type"),
    };
}

/// SKILL.md mtime as unix seconds. Null when the file cannot be
/// opened or stat fails. Not a Native FS watcher.
fn readSkillMtimeUnix(io: std.Io, abs: []const u8) ?i64 {
    var file = std.Io.Dir.cwd().openFile(io, abs, .{}) catch return null;
    defer file.close(io);
    const st = file.stat(io) catch return null;
    const ns = mtimeToNs(st.mtime);
    if (ns < 0) return null;
    return @divTrunc(ns, 1_000_000_000);
}

/// Waku `DIR_WALK_MAX_DEPTH` / `DIR_WALK_MAX_FILES` for the
/// selected-skill Contents supporting-file walk.
const skill_dir_walk_max_depth: usize = 6;
const skill_dir_walk_max_files: usize = 500;

const SkillDirMeasure = struct {
    files: usize,
    bytes: u64,
};

/// Waku `measure_skill_dir`: walk the skill parent, skip names
/// starting with `.`, follow metadata for files/dirs, cap depth 6
/// / 500 files. Skill file counts in bytes but not as a supporting
/// file (`files.saturating_sub(1)`). Null when the dir cannot be
/// opened — fail closed, do not invent counts.
fn measureSkillDir(io: std.Io, abs: []const u8) ?SkillDirMeasure {
    if (abs.len == 0) return null;
    var root = std.Io.Dir.cwd().openDir(io, abs, .{ .iterate = true }) catch return null;
    defer root.close(io);
    var files: usize = 0;
    var bytes: u64 = 0;
    walkSkillDir(io, root, 0, &files, &bytes);
    return .{ .files = files -| 1, .bytes = bytes };
}

fn walkSkillDir(io: std.Io, dir: std.Io.Dir, depth: usize, files: *usize, bytes: *u64) void {
    if (depth > skill_dir_walk_max_depth or files.* >= skill_dir_walk_max_files) return;
    var it = dir.iterate();
    while (it.next(io) catch return) |entry| {
        if (files.* >= skill_dir_walk_max_files) return;
        if (entry.name.len == 0 or entry.name[0] == '.') continue;
        const st = dir.statFile(io, entry.name, .{ .follow_symlinks = true }) catch continue;
        switch (st.kind) {
            .directory => {
                var child = dir.openDir(io, entry.name, .{ .iterate = true, .follow_symlinks = true }) catch continue;
                defer child.close(io);
                walkSkillDir(io, child, depth + 1, files, bytes);
            },
            .file => {
                files.* += 1;
                bytes.* +|= st.size;
            },
            else => {},
        }
    }
}

fn loadBody(model: *Model, index: usize) void {
    clearSelectedSkillBody(model);
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
    writeFixed(&model.skill_allowed_tools_storage, &model.skill_allowed_tools_len, parseFrontmatterAllowedTools(source));
    if (readSkillMtimeUnix(io, abs)) |mtime| {
        model.skill_mtime_unix = mtime;
        model.skill_mtime_valid = true;
    }
    var parent_buf: [model_exports.max_project_path + max_skill_path + 1]u8 = undefined;
    const parent = absSkillParent(root, relpath, &parent_buf) orelse return;
    if (measureSkillDir(io, parent)) |measured| {
        model.skill_supporting_files = measured.files;
        model.skill_total_bytes = measured.bytes;
        model.skill_contents_valid = true;
    }
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
pub const scanning = skills_empty_chrome_en.scanning;
pub const no_skills_found = skills_empty_chrome_en.no_skills_found;
pub const no_matching = skills_empty_chrome_en.no_matching;

/// English default from `i18n.SkillsSelectChrome`. Distinct from
/// SkillsEmptyChrome Open a project / Scanning / No skills found /
/// No skills match your search.
const skills_select_chrome_en = i18n.skillsSelectChromeFor(.english, "");
pub const select_placeholder = skills_select_chrome_en.select_placeholder;

/// English default from `i18n.SkillsSectionChrome`. Distinct from
/// SkillsEmptyChrome / SkillsCountChrome / SkillsSelectChrome.
/// Matches Waku GPUI `skills.section_user`.
const skills_section_chrome_en = i18n.skillsSectionChromeFor(.english, "");
pub const section_user = skills_section_chrome_en.section_user;

/// English defaults from `i18n.SkillsDetailChrome`. Distinct from
/// SkillsEmptyChrome / SkillsSelectChrome / SkillsCountChrome /
/// SkillsSectionChrome. Matches Waku `skills.no_description` /
/// `detail_invoke` / `detail_location` / `detail_contents`.
const skills_detail_chrome_en = i18n.skillsDetailChromeFor(.english, "");
pub const no_description = skills_detail_chrome_en.no_description;
pub const detail_invoke = skills_detail_chrome_en.detail_invoke;
pub const detail_location = skills_detail_chrome_en.detail_location;
pub const detail_contents = skills_detail_chrome_en.detail_contents;

/// English defaults from `i18n.SkillsUpdatedChrome`. Distinct from
/// SkillsDetailChrome No description / Invoke / Location /
/// Contents. Matches Waku `skills.detail_updated` /
/// `updated_just_now` / `updated_minutes` / `updated_hours` /
/// `updated_days`.
const skills_updated_chrome_en = i18n.skillsUpdatedChromeFor(.english, "");
pub const detail_updated = skills_updated_chrome_en.detail_updated;
pub const updated_just_now = skills_updated_chrome_en.updated_just_now;

/// English defaults from `i18n.SkillsFileCountChrome`. Distinct from
/// SkillsDetailChrome Contents label and SkillsUpdatedChrome.
/// Matches Waku `skills.file_count_one` / `file_count_many`.
const skills_file_count_chrome_en = i18n.skillsFileCountChromeFor(.english, "");
pub const file_count_one = skills_file_count_chrome_en.file_count_one;
pub const file_count_many = skills_file_count_chrome_en.file_count_many;

/// English defaults from `i18n.SkillsAllowedToolsChrome`. Distinct from
/// SkillsDetailChrome / SkillsUpdatedChrome / SkillsFileCountChrome.
/// Matches Waku `skills.allowed_tools`.
const skills_allowed_tools_chrome_en = i18n.skillsAllowedToolsChromeFor(.english, "");
pub const allowed_tools = skills_allowed_tools_chrome_en.allowed_tools;

/// English default from `i18n.SkillsSourceChrome`. Distinct from
/// SkillsDetailChrome Location. Matches Waku `skills.source_shared`.
const skills_source_chrome_en = i18n.skillsSourceChromeFor(.english, "");
pub const source_shared = skills_source_chrome_en.source_shared;

/// English default from `i18n.SkillsFilterAllChrome`. Distinct from
/// SkillsSourceChrome Shared / provider shorts and FilterChrome
/// Filter skills. Matches Waku `skills.filter_all`.
const skills_filter_all_chrome_en = i18n.skillsFilterAllChromeFor(.english, "");
pub const filter_all = skills_filter_all_chrome_en.filter_all;

/// English defaults from `i18n.SkillsDuplicateChrome`. Distinct from
/// SkillsDetailChrome / SkillsSourceChrome. Matches Waku
/// `skills.duplicate_one` / `duplicate_many`.
const skills_duplicate_chrome_en = i18n.skillsDuplicateChromeFor(.english, "");
pub const duplicate_one = skills_duplicate_chrome_en.duplicate_one;
pub const duplicate_many = skills_duplicate_chrome_en.duplicate_many;

/// English defaults from `i18n.SkillsScopeChrome`. Distinct from
/// SkillsDetailChrome / SkillsSourceChrome / SkillsSectionChrome /
/// SkillsDuplicateChrome. Matches Waku `skills.scope_user_detail` /
/// `scope_in_project`.
const skills_scope_chrome_en = i18n.skillsScopeChromeFor(.english, "");
pub const scope_user_detail = skills_scope_chrome_en.scope_user_detail;
pub const scope_in_project = skills_scope_chrome_en.scope_in_project;

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

fn skillsCountChrome(model: *const Model) i18n.SkillsCountChrome {
    return i18n.skillsCountChromeFor(model.language_preference, model.systemLocaleId());
}

/// Settings Skills empty hint. Localized via `i18n.SkillsEmptyChrome`.
/// Priority: no project → `open_project`; scan in flight → `scanning`
/// (even when `skill_count == 0`); else no skills → `no_skills_found`;
/// else a trimmed filter or source filter with no visible grouped
/// skill → `no_matching`; else `""` (list shows rows). Composer `$`
/// insert uses `insertEmptyHint` so scanning / no-match stay off
/// that surface. Settings markup prefers `SkillsEmptyRichChrome`
/// title + description over painting `no_skills_found` when
/// `isNoSkillsEmpty`; `emptyHint` still returns `no_skills_found`
/// so `skills_empty` / `hasCountCaption` / `skills_needs_select`
/// keep owning that space.
pub fn emptyHint(model: *const Model) []const u8 {
    const chrome = skillsEmptyChrome(model);
    if (probePath(model).len == 0) return chrome.open_project;
    if (scanInFlight(model)) return chrome.scanning;
    if (model.skill_count == 0) return chrome.no_skills_found;
    const query = std.mem.trim(u8, model.skills_filter_buffer.text(), " \t\r\n");
    if ((query.len != 0 or model.skills_source_filter != null) and !anyVisibleGroupedSkill(model, query))
        return chrome.no_matching;
    return "";
}

/// True when Settings emptyHint would be the no-skills case: a
/// project is open, the scan is idle, and `skill_count == 0`.
/// Open a project / scanning / filter no-match stay on the
/// single-line `SkillsEmptyChrome` hints. Does not check
/// `settings_page` — Model `skills_empty_rich` gates the page.
pub fn isNoSkillsEmpty(model: *const Model) bool {
    if (probePath(model).len == 0) return false;
    if (scanInFlight(model)) return false;
    return model.skill_count == 0;
}

/// Composer `$` insert empty. Same `i18n.SkillsEmptyChrome` pack, but
/// only Open a project / No skills found / `""`. Settings scanning
/// and filter no-match stay on `emptyHint` (this surface has no
/// Skills filter).
pub fn insertEmptyHint(model: *const Model) []const u8 {
    const chrome = skillsEmptyChrome(model);
    if (probePath(model).len == 0) return chrome.open_project;
    if (scanInFlight(model) and model.skill_count == 0) return "";
    if (model.skill_count == 0) return chrome.no_skills_found;
    return "";
}

/// Settings Skills count / filter caption. Empty when `emptyHint`
/// owns the space (no project / scanning / no skills / no match) or
/// when `skill_count == 0`. Else a trimmed text query or a source
/// filter uses `filter_caption`; otherwise `count_one` /
/// `count_many`, appending ` · ` + `count_disabled` when any cached
/// skill is disabled (total cache, not among shown — same as Waku
/// library header). Numbers stay Latin.
pub fn countCaption(model: *const Model, arena: std.mem.Allocator) []const u8 {
    if (!hasCountCaption(model)) return "";
    const chrome = skillsCountChrome(model);
    var buf: [i18n.skills_count_caption_max]u8 = undefined;
    const query = std.mem.trim(u8, model.skills_filter_buffer.text(), " \t\r\n");
    const total: usize = model.skill_count;
    const shown = shownSkillCount(model, query);
    const filtering = query.len != 0 or model.skills_source_filter != null;
    const text = if (filtering)
        i18n.formatSkillsFilterCaption(chrome, shown, total, &buf)
    else
        i18n.formatSkillsCountCaption(chrome, total, disabledSkillCount(model), &buf);
    return copyCaption(arena, text);
}

pub fn hasCountCaption(model: *const Model) bool {
    if (emptyHint(model).len != 0) return false;
    if (model.skill_count == 0) return false;
    return true;
}

fn shownSkillCount(model: *const Model, query: []const u8) usize {
    var shown: usize = 0;
    var i: usize = 0;
    while (i < model.skill_count) : (i += 1) {
        if (!isPrimaryGroupedIndex(model, i)) continue;
        if (groupedSkillVisible(model, i, query)) shown += 1;
    }
    return shown;
}

/// Total cached disabled **groups** (not among the filtered shown
/// set). Matches Waku library header `disabled_count` after folding
/// same-name installs within a scope (`enabled` is OR of installs).
fn disabledSkillCount(model: *const Model) usize {
    var n: usize = 0;
    var i: usize = 0;
    while (i < model.skill_count) : (i += 1) {
        if (!isPrimaryGroupedIndex(model, i)) continue;
        if (!groupEnabled(model, i)) n += 1;
    }
    return n;
}

fn copyCaption(arena: std.mem.Allocator, text: []const u8) []const u8 {
    if (text.len == 0) return "";
    const out = arena.alloc(u8, text.len) catch return "";
    @memcpy(out, text);
    return out;
}

fn anyVisibleGroupedSkill(model: *const Model, query: []const u8) bool {
    var i: usize = 0;
    while (i < model.skill_count) : (i += 1) {
        if (!isPrimaryGroupedIndex(model, i)) continue;
        if (groupedSkillVisible(model, i, query)) return true;
    }
    return false;
}

fn skillRowMatches(skill: *const CachedSkill, query: []const u8) bool {
    if (query.len == 0) return true;
    return util.asciiContainsIgnoreCase(skill.name(), query) or
        util.asciiContainsIgnoreCase(skill.path(), query) or
        util.asciiContainsIgnoreCase(skill.description(), query);
}

pub fn namesEqualIgnoreCase(left: []const u8, right: []const u8) bool {
    if (left.len != right.len) return false;
    for (left, right) |a, b| {
        if (std.ascii.toLower(a) != std.ascii.toLower(b)) return false;
    }
    return true;
}

pub fn sameSkillGroup(left: *const CachedSkill, right: *const CachedSkill) bool {
    return isAbsoluteSkillPath(left.path()) == isAbsoluteSkillPath(right.path()) and
        namesEqualIgnoreCase(left.name(), right.name());
}

/// First store index in Waku walk / catalog order is primary.
pub fn isPrimaryGroupedIndex(model: *const Model, index: usize) bool {
    if (index >= model.skill_count) return false;
    const skill = &model.skill_store[index];
    var i: usize = 0;
    while (i < index) : (i += 1) {
        if (sameSkillGroup(&model.skill_store[i], skill)) return false;
    }
    return true;
}

pub fn groupEnabled(model: *const Model, index: usize) bool {
    if (index >= model.skill_count) return false;
    const skill = &model.skill_store[index];
    var i: usize = 0;
    while (i < model.skill_count) : (i += 1) {
        if (!sameSkillGroup(&model.skill_store[i], skill)) continue;
        if (model.skill_store[i].enabled) return true;
    }
    return false;
}

pub fn groupedSkillMatches(model: *const Model, index: usize, query: []const u8) bool {
    if (index >= model.skill_count) return false;
    const skill = &model.skill_store[index];
    var i: usize = 0;
    while (i < model.skill_count) : (i += 1) {
        if (!sameSkillGroup(&model.skill_store[i], skill)) continue;
        if (skillRowMatches(&model.skill_store[i], query)) return true;
    }
    return false;
}

/// Settings list visibility: text query **and** source filter. A
/// grouped skill stays visible when any same-scope install matches
/// the query and (when a source is picked) any install lives under
/// that source tree. Waku `visible_skill_indices`.
pub fn groupedSkillVisible(model: *const Model, index: usize, query: []const u8) bool {
    if (!groupedSkillMatches(model, index, query)) return false;
    const kind = model.skills_source_filter orelse return true;
    return groupedSkillHasSource(model, index, kind);
}

/// True when any install in the same-scope group lives under `kind`.
pub fn groupedSkillHasSource(model: *const Model, primary_index: usize, kind: SkillSourceKind) bool {
    var idxs: [max_skill_installs]usize = undefined;
    const n = collectGroupIndices(model, primary_index, &idxs);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (skillSourceKind(model.skill_store[idxs[i]].path()) == kind) return true;
    }
    return false;
}

/// Other-scope grouped entries with the same case-insensitive name.
/// Same-scope copies are folded, so those do not add to `duplicates`.
pub fn groupedDuplicates(model: *const Model, index: usize) usize {
    if (index >= model.skill_count) return 0;
    const skill = &model.skill_store[index];
    const user = isAbsoluteSkillPath(skill.path());
    var n: usize = 0;
    var i: usize = 0;
    while (i < model.skill_count) : (i += 1) {
        if (!isPrimaryGroupedIndex(model, i)) continue;
        if (isAbsoluteSkillPath(model.skill_store[i].path()) == user) continue;
        if (!namesEqualIgnoreCase(model.skill_store[i].name(), skill.name())) continue;
        n += 1;
    }
    return n;
}

pub fn collectGroupIndices(model: *const Model, index: usize, dest: *[max_skill_installs]usize) usize {
    if (index >= model.skill_count) return 0;
    const skill = &model.skill_store[index];
    var n: usize = 0;
    var i: usize = 0;
    while (i < model.skill_count) : (i += 1) {
        if (!sameSkillGroup(&model.skill_store[i], skill)) continue;
        if (n >= dest.len) break;
        dest[n] = i;
        n += 1;
    }
    return n;
}

pub const SkillSourceKind = enum {
    shared,
    claude,
    codex,
    opencode,
    cursor,
    fx,
    pi,
    omp,
    unknown,
};

fn hasSkillRootSegment(path: []const u8, segment: []const u8) bool {
    if (segment.len == 0 or path.len < segment.len) return false;
    if (std.mem.startsWith(u8, path, segment) and (path.len == segment.len or path[segment.len] == '/')) {
        return true;
    }
    var i: usize = 0;
    while (i < path.len) : (i += 1) {
        if (path[i] != '/') continue;
        const rest = path[i + 1 ..];
        if (rest.len < segment.len) continue;
        if (!std.mem.eql(u8, rest[0..segment.len], segment)) continue;
        if (rest.len == segment.len or rest[segment.len] == '/') return true;
    }
    return false;
}

pub fn skillSourceKind(path: []const u8) SkillSourceKind {
    if (hasSkillRootSegment(path, ".config/agents/skills")) return .shared;
    if (hasSkillRootSegment(path, ".config/opencode/skills")) return .opencode;
    if (hasSkillRootSegment(path, ".pi/agent/skills")) return .pi;
    if (hasSkillRootSegment(path, ".omp/agent/skills")) return .omp;
    if (hasSkillRootSegment(path, ".agents/skills")) return .shared;
    if (hasSkillRootSegment(path, ".claude/skills")) return .claude;
    if (hasSkillRootSegment(path, ".codex/skills")) return .codex;
    if (hasSkillRootSegment(path, ".cursor/skills")) return .cursor;
    if (hasSkillRootSegment(path, ".fx/skills")) return .fx;
    return .unknown;
}

pub fn skillSourceLabel(kind: SkillSourceKind, chrome: i18n.SkillsSourceChrome, fallback_location: []const u8) []const u8 {
    return switch (kind) {
        .shared => chrome.source_shared,
        .claude => chrome.source_claude,
        .codex => chrome.source_codex,
        .opencode => chrome.source_opencode,
        .cursor => chrome.source_cursor,
        .fx => chrome.source_fx,
        .pi => chrome.source_pi,
        .omp => chrome.source_omp,
        .unknown => fallback_location,
    };
}

/// Wire ids for `pick_skills_source:{id}`. `all` clears the filter.
pub const source_filter_all_id = "all";

/// Menu order matches Waku's Shared / Claude / Codex / Cursor / fx /
/// OpenCode / Pi / OMP chip list. `unknown` is skipped.
pub const source_filter_kinds = [_]SkillSourceKind{
    .shared,
    .claude,
    .codex,
    .cursor,
    .fx,
    .opencode,
    .pi,
    .omp,
};

pub fn skillSourceKindId(kind: SkillSourceKind) []const u8 {
    return switch (kind) {
        .shared => "shared",
        .claude => "claude",
        .codex => "codex",
        .cursor => "cursor",
        .fx => "fx",
        .opencode => "opencode",
        .pi => "pi",
        .omp => "omp",
        .unknown => "",
    };
}

pub fn pickSourceFilter(model: *Model, id: []const u8) void {
    if (std.mem.eql(u8, id, source_filter_all_id)) {
        model.skills_source_filter = null;
    } else {
        for (source_filter_kinds) |kind| {
            if (std.mem.eql(u8, id, skillSourceKindId(kind))) {
                model.skills_source_filter = kind;
                break;
            }
        }
    }
    model.closeSkillsSourcePicker();
}

fn skillsFilterAllChrome(model: *const Model) i18n.SkillsFilterAllChrome {
    return i18n.skillsFilterAllChromeFor(model.language_preference, model.systemLocaleId());
}

fn skillsSourceChrome(model: *const Model) i18n.SkillsSourceChrome {
    return i18n.skillsSourceChromeFor(model.language_preference, model.systemLocaleId());
}

/// Chip label: All skills when the filter is none, else that source's
/// SkillsSourceChrome label. Counts stay on picker rows only.
pub fn sourceFilterLabel(model: *const Model) []const u8 {
    const kind = model.skills_source_filter orelse return skillsFilterAllChrome(model).filter_all;
    return skillSourceLabel(kind, skillsSourceChrome(model), "");
}

fn groupedSkillCountForSource(model: *const Model, kind: SkillSourceKind) usize {
    var n: usize = 0;
    var i: usize = 0;
    while (i < model.skill_count) : (i += 1) {
        if (!isPrimaryGroupedIndex(model, i)) continue;
        if (groupedSkillHasSource(model, i, kind)) n += 1;
    }
    return n;
}

fn formatSourceFilterMenuLabel(arena: std.mem.Allocator, label: []const u8, count: usize) []const u8 {
    if (count == 0) return label;
    return std.fmt.allocPrint(arena, "{s} · {d}", .{ label, count }) catch label;
}

/// All skills (selected when none) then each `source_filter_kinds`
/// row. Optional `Label · {count}` when that source has at least one
/// grouped skill. Counts are Latin.
pub fn sourcePickerRows(model: *const Model, arena: std.mem.Allocator) []const ChipPickerRow {
    const out = arena.alloc(ChipPickerRow, 1 + source_filter_kinds.len) catch return &.{};
    const all_selected = model.skills_source_filter == null;
    out[0] = .{
        .row_id = 1,
        .id = source_filter_all_id,
        .label = skillsFilterAllChrome(model).filter_all,
        .selected = all_selected,
    };
    const source_chrome = skillsSourceChrome(model);
    for (source_filter_kinds, 0..) |kind, index| {
        const count = groupedSkillCountForSource(model, kind);
        const label = skillSourceLabel(kind, source_chrome, "");
        out[index + 1] = .{
            .row_id = @intCast(index + 2),
            .id = skillSourceKindId(kind),
            .label = formatSourceFilterMenuLabel(arena, label, count),
            .selected = if (model.skills_source_filter) |current| current == kind else false,
        };
    }
    return out;
}

/// Replace a home-directory prefix with `~`. Fail closed (return
/// `path`) when home is empty / mismatch / overflow.
pub fn compactHomePath(path: []const u8, home: []const u8, buf: []u8) []const u8 {
    if (home.len == 0 or path.len < home.len) return path;
    var home_buf: [max_skill_path]u8 = undefined;
    const home_norm = copySlashNormalized(home, &home_buf) orelse return path;
    if (path.len < home_norm.len) return path;
    if (!std.mem.eql(u8, path[0..home_norm.len], home_norm)) return path;
    if (path.len > home_norm.len and path[home_norm.len] != '/') return path;
    const rest = path[home_norm.len..];
    return std.fmt.bufPrint(buf, "~{s}", .{rest}) catch path;
}

pub fn selectedSkillDuplicateCount(model: *const Model) usize {
    if (model.skill_selected_id == 0 or model.skill_selected_id > model.skill_count) return 0;
    return groupedDuplicates(model, model.skill_selected_id - 1);
}

pub fn selectedSkillDuplicateBadge(model: *const Model, arena: std.mem.Allocator) []const u8 {
    const count = selectedSkillDuplicateCount(model);
    if (count == 0) return "";
    var buf: [i18n.skills_duplicate_badge_max]u8 = undefined;
    const chrome = i18n.skillsDuplicateChromeFor(model.language_preference, model.systemLocaleId());
    const text = i18n.formatSkillsDuplicateBadge(chrome, count, &buf);
    return copyCaption(arena, text);
}

/// Absolute install parent for a cached store path (not necessarily
/// the selected primary).
fn absParentForStorePath(model: *const Model, relpath: []const u8, buf: []u8) ?[]const u8 {
    if (relpath.len == 0) return null;
    const root = model.skill_probe_path_storage[0..model.skill_probe_path_len];
    const parent = absSkillParent(root, relpath, buf) orelse return null;
    if (parent.len == 0) return null;
    return parent;
}

pub const SkillLocationRow = struct {
    id: u32,
    label: []const u8,
    path: []const u8,
};

pub fn selectedSkillLocationRows(model: *const Model, arena: std.mem.Allocator) []const SkillLocationRow {
    if (model.skill_selected_id == 0 or model.skill_selected_id > model.skill_count) return &.{};
    const index = model.skill_selected_id - 1;
    var idxs: [max_skill_installs]usize = undefined;
    const n = collectGroupIndices(model, index, &idxs);
    if (n == 0) return &.{};
    const out = arena.alloc(SkillLocationRow, n) catch return &.{};
    const source_chrome = i18n.skillsSourceChromeFor(model.language_preference, model.systemLocaleId());
    const location_label = i18n.skillsDetailChromeFor(model.language_preference, model.systemLocaleId()).detail_location;
    var home_buf: [max_skill_path]u8 = undefined;
    var userprofile_buf: [max_skill_path]u8 = undefined;
    var claude_buf: [max_skill_path]u8 = undefined;
    const env = readProcessUserSkillEnv(&home_buf, &userprofile_buf, &claude_buf);
    const home = processHomeDir(env.home, env.userprofile);
    var row_i: usize = 0;
    while (row_i < n) : (row_i += 1) {
        const relpath = model.skill_store[idxs[row_i]].path();
        var parent_buf: [model_exports.max_project_path + max_skill_path + 1]u8 = undefined;
        const raw_path = absParentForStorePath(model, relpath, &parent_buf) orelse relpath;
        var compact_buf: [max_skill_path + 2]u8 = undefined;
        const shown_path = if (n > 1) compactHomePath(raw_path, home, &compact_buf) else raw_path;
        const label = if (n > 1)
            skillSourceLabel(skillSourceKind(relpath), source_chrome, location_label)
        else
            location_label;
        out[row_i] = .{
            .id = @intCast(row_i + 1),
            .label = label,
            .path = copyCaption(arena, shown_path),
        };
    }
    return out;
}

/// Selected grouped primary name. Empty when nothing is selected.
pub fn selectedSkillName(model: *const Model) []const u8 {
    if (model.skill_selected_id == 0 or model.skill_selected_id > model.skill_count) return "";
    return model.skill_store[model.skill_selected_id - 1].name();
}

const skill_source_kind_count = @typeInfo(SkillSourceKind).@"enum".fields.len;

/// Unique install-source labels for the selected group, in Waku
/// user-root / `collectGroupIndices` order, joined with Latin ` · `.
/// Unknown kinds are omitted (fail closed). Empty when unselected
/// or every install is unknown.
pub fn writeSelectedSkillSourcesLabel(model: *const Model, buf: []u8) []const u8 {
    if (model.skill_selected_id == 0 or model.skill_selected_id > model.skill_count) return "";
    var idxs: [max_skill_installs]usize = undefined;
    const n = collectGroupIndices(model, model.skill_selected_id - 1, &idxs);
    if (n == 0) return "";
    const source_chrome = i18n.skillsSourceChromeFor(model.language_preference, model.systemLocaleId());
    var seen = [_]bool{false} ** skill_source_kind_count;
    var out: usize = 0;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const kind = skillSourceKind(model.skill_store[idxs[i]].path());
        if (kind == .unknown) continue;
        const bit = @intFromEnum(kind);
        if (seen[bit]) continue;
        seen[bit] = true;
        const label = skillSourceLabel(kind, source_chrome, "");
        if (label.len == 0) continue;
        if (out > 0) {
            const sep = " · ";
            if (out + sep.len > buf.len) return "";
            @memcpy(buf[out .. out + sep.len], sep);
            out += sep.len;
        }
        if (out + label.len > buf.len) return "";
        @memcpy(buf[out .. out + label.len], label);
        out += label.len;
    }
    return buf[0..out];
}

/// Selected-detail muted sources · scope caption. Project-relative
/// primary uses `scope_in_project` + `sectionProjectLabel`; absolute
/// / user uses `scope_user_detail`. Empty sources paints scope
/// alone. Empty when unselected or format overflow.
pub fn writeSelectedSkillScopeCaption(model: *const Model, buf: []u8) []const u8 {
    if (model.skill_selected_id == 0 or model.skill_selected_id > model.skill_count) return "";
    var sources_buf: [i18n.skills_scope_caption_max]u8 = undefined;
    const sources = writeSelectedSkillSourcesLabel(model, &sources_buf);
    const chrome = i18n.skillsScopeChromeFor(model.language_preference, model.systemLocaleId());
    const in_project = !isAbsoluteSkillPath(model.skill_store[model.skill_selected_id - 1].path());
    const project = if (in_project) sectionProjectLabel(model) else "";
    return i18n.formatSkillsScopeCaption(chrome, sources, in_project, project, buf);
}

pub fn selectedSkillScopeCaption(model: *const Model, arena: std.mem.Allocator) []const u8 {
    var buf: [i18n.skills_scope_caption_max]u8 = undefined;
    return copyCaption(arena, writeSelectedSkillScopeCaption(model, &buf));
}

pub fn hasSelectedSkillScopeCaption(model: *const Model) bool {
    var buf: [i18n.skills_scope_caption_max]u8 = undefined;
    return writeSelectedSkillScopeCaption(model, &buf).len > 0;
}

test "argv is packed chdir plus find SKILL.md then user-root slots; not file-mention walk" {
    var buf: [walk_argv_len][]const u8 = undefined;
    const argv = unixWalkArgvFor("/tmp/faku-skills", &.{}, &buf);
    try std.testing.expectEqual(@as(usize, unix_walk_argv_base), argv.len);
    try std.testing.expectEqualStrings(sh_bin, argv[0]);
    try std.testing.expectEqualStrings("-c", argv[1]);
    try std.testing.expectEqualStrings(unix_skills_walk_script, argv[2]);
    try std.testing.expectEqualStrings("sh", argv[3]);
    try std.testing.expectEqualStrings("/tmp/faku-skills", argv[4]);
    try std.testing.expect(isSkillsWalkArgv(argv));
    try std.testing.expect(!file_mention.isWalkArgv(argv));
    try std.testing.expect(!file_mention.isGitLsFilesArgv(argv));
    try std.testing.expect(scriptHas(argv[2], find_skills_script));
    try std.testing.expect(scriptHas(argv[2], find_user_skills_script));
    try std.testing.expect(scriptHas(argv[2], find_maxdepth_flag));
    try std.testing.expect(scriptHas(argv[2], find_maxdepth));
    try std.testing.expect(scriptHas(argv[2], find_user_maxdepth));
    try std.testing.expect(scriptHas(argv[2], find_prune));
    try std.testing.expect(scriptHas(argv[2], find_type_file));
    try std.testing.expect(scriptHas(argv[2], skill_filename));
    try std.testing.expect(scriptHas(argv[2], disabled_skill_filename));
    try std.testing.expect(scriptHas(argv[2], "$1"));
    try std.testing.expect(!scriptHas(argv[2], file_mention.find_dot_star));
    inline for (walk_skip_names) |name| {
        try std.testing.expect(scriptHas(argv[2], name));
    }
    const user_root = "/tmp/faku-user/.cursor/skills";
    const with_user = unixWalkArgvFor("/tmp/faku-skills", &.{user_root}, &buf);
    try std.testing.expectEqual(@as(usize, unix_walk_argv_base + 1), with_user.len);
    try std.testing.expectEqualStrings(user_root, with_user[5]);
    try std.testing.expect(std.mem.indexOf(u8, with_user[2], user_root) == null);
    try std.testing.expect(isSkillsWalkArgv(with_user));
    try std.testing.expect(with_user.len <= 16);
    const nine = [_][]const u8{
        "/home/me/.agents/skills",
        "/home/me/.claude/skills",
        "/home/me/.codex/skills",
        "/home/me/.config/opencode/skills",
        "/home/me/.cursor/skills",
        "/home/me/.fx/skills",
        "/home/me/.pi/agent/skills",
        "/home/me/.omp/agent/skills",
        "/home/me/.config/agents/skills",
    };
    const nine_argv = unixWalkArgvFor("/tmp/faku-skills", &nine, &buf);
    try std.testing.expectEqual(@as(usize, unix_walk_argv_base + 9), nine_argv.len);
    try std.testing.expect(nine_argv.len <= 16);
    try std.testing.expectEqualStrings("/tmp/faku-skills", nine_argv[4]);
    try std.testing.expectEqualStrings(nine[0], nine_argv[5]);
    try std.testing.expectEqualStrings(nine[8], nine_argv[13]);
    try std.testing.expect(std.mem.indexOf(u8, nine_argv[2], nine[0]) == null);
    try std.testing.expect(std.mem.indexOf(u8, nine_argv[2], nine[5]) == null);
    try std.testing.expect(isSkillsWalkArgv(nine_argv));
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

test "windows walk argv is powershell scriptblock -Args PATH then user roots; descends into hidden dirs" {
    var buf: [walk_argv_len][]const u8 = undefined;
    const cwd = "C:\\Users\\me\\proj";
    const argv = windowsWalkArgvFor(cwd, &.{}, &buf);
    try std.testing.expectEqual(@as(usize, windows_walk_argv_base), argv.len);
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
    try std.testing.expect(scriptHas(argv[3], find_user_maxdepth));
    try std.testing.expect(scriptHas(argv[3], max_skills_s));
    try std.testing.expect(scriptHas(argv[3], skill_filename));
    try std.testing.expect(scriptHas(argv[3], disabled_skill_filename));
    try std.testing.expect(!scriptHas(argv[3], "StartsWith('.'"));
    try std.testing.expect(!std.mem.eql(u8, argv[3], file_mention.powershell_walk_script));
    inline for (walk_skip_names) |name| {
        try std.testing.expect(scriptHas(argv[3], name));
    }
    const user_root = "C:\\Users\\me\\.cursor\\skills";
    const with_user = windowsWalkArgvFor(cwd, &.{user_root}, &buf);
    try std.testing.expectEqual(@as(usize, windows_walk_argv_base + 1), with_user.len);
    try std.testing.expectEqualStrings(user_root, with_user[6]);
    try std.testing.expect(std.mem.indexOf(u8, with_user[3], user_root) == null);
    try std.testing.expect(std.mem.indexOf(u8, with_user[3], "$HOME") == null);
    try std.testing.expect(std.mem.indexOf(u8, with_user[3], "USERPROFILE") == null);
    try std.testing.expect(isSkillsWalkArgv(with_user));
    try std.testing.expect(with_user.len <= 16);
    const nine = [_][]const u8{
        "C:\\Users\\me\\.agents\\skills",
        "C:\\Users\\me\\.claude\\skills",
        "C:\\Users\\me\\.codex\\skills",
        "C:\\Users\\me\\.config\\opencode\\skills",
        "C:\\Users\\me\\.cursor\\skills",
        "C:\\Users\\me\\.fx\\skills",
        "C:\\Users\\me\\.pi\\agent\\skills",
        "C:\\Users\\me\\.omp\\agent\\skills",
        "C:\\Users\\me\\.config\\agents\\skills",
    };
    const nine_argv = windowsWalkArgvFor(cwd, &nine, &buf);
    try std.testing.expectEqual(@as(usize, windows_walk_argv_base + 9), nine_argv.len);
    try std.testing.expect(nine_argv.len <= 16);
    try std.testing.expectEqualStrings(cwd, nine_argv[5]);
    try std.testing.expectEqualStrings(nine[0], nine_argv[6]);
    try std.testing.expectEqualStrings(nine[8], nine_argv[14]);
    try std.testing.expect(std.mem.indexOf(u8, nine_argv[3], nine[0]) == null);
    try std.testing.expect(std.mem.indexOf(u8, nine_argv[3], "$HOME") == null);
    try std.testing.expect(isSkillsWalkArgv(nine_argv));
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
    const walk_argv = argvFor("/tmp/faku-skills", &.{}, &walk_buf);
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
            try std.testing.expectEqual(@as(usize, windows_walk_argv_base), walk_argv.len);
            try std.testing.expectEqualStrings(powershell_bin, rename_argv[0]);
            try std.testing.expectEqualStrings(powershell_args_flag, rename_argv[4]);
            try std.testing.expectEqualStrings(powershell_bin, remove_argv[0]);
            try std.testing.expectEqualStrings(powershell_args_flag, remove_argv[4]);
        },
        else => {
            try std.testing.expectEqualStrings(sh_bin, walk_argv[0]);
            try std.testing.expectEqualStrings(unix_skills_walk_script, walk_argv[2]);
            try std.testing.expectEqual(@as(usize, unix_walk_argv_base), walk_argv.len);
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

test "userSkillRootCandidates lists Waku order; HOME missing is empty; CLAUDE_CONFIG_DIR absolute override" {
    var store: [max_user_skill_roots][max_skill_path]u8 = undefined;
    var dest: [max_user_skill_roots][]const u8 = undefined;

    try std.testing.expectEqual(@as(usize, 0), collectUserSkillRootCandidates(.{}, &store, &dest));
    try std.testing.expectEqual(@as(usize, 0), collectUserSkillRootCandidates(.{ .claude_config_dir = "/opt/claude" }, &store, &dest));
    try std.testing.expectEqualStrings("", processHomeDirOn(.linux, "", ""));
    try std.testing.expectEqualStrings("/home/me", processHomeDirOn(.linux, "/home/me", "C:\\Users\\me"));
    try std.testing.expectEqualStrings("C:\\Users\\me", processHomeDirOn(.windows, "/home/me", "C:\\Users\\me"));
    try std.testing.expectEqualStrings("/home/me", processHomeDirOn(.windows, "/home/me", ""));
    try std.testing.expect(isAbsoluteEnvPath("/opt/claude"));
    try std.testing.expect(isAbsoluteEnvPath("C:\\Users\\me\\.claude"));
    try std.testing.expect(!isAbsoluteEnvPath(""));
    try std.testing.expect(!isAbsoluteEnvPath(".claude"));
    try std.testing.expect(!isAbsoluteEnvPath("claude-config"));

    const n = collectUserSkillRootCandidates(.{ .home = "/home/me" }, &store, &dest);
    try std.testing.expectEqual(@as(usize, 9), n);
    try std.testing.expectEqualStrings("/home/me/.agents/skills", dest[0]);
    try std.testing.expectEqualStrings("/home/me/.claude/skills", dest[1]);
    try std.testing.expectEqualStrings("/home/me/.codex/skills", dest[2]);
    try std.testing.expectEqualStrings("/home/me/.config/opencode/skills", dest[3]);
    try std.testing.expectEqualStrings("/home/me/.cursor/skills", dest[4]);
    try std.testing.expectEqualStrings("/home/me/.fx/skills", dest[5]);
    try std.testing.expectEqualStrings("/home/me/.pi/agent/skills", dest[6]);
    try std.testing.expectEqualStrings("/home/me/.omp/agent/skills", dest[7]);
    try std.testing.expectEqualStrings("/home/me/.config/agents/skills", dest[8]);

    const overridden = collectUserSkillRootCandidates(.{
        .home = "/home/me",
        .claude_config_dir = "/opt/claude",
    }, &store, &dest);
    try std.testing.expectEqual(@as(usize, 9), overridden);
    try std.testing.expectEqualStrings("/home/me/.agents/skills", dest[0]);
    try std.testing.expectEqualStrings("/opt/claude/skills", dest[1]);
    try std.testing.expectEqualStrings("/home/me/.codex/skills", dest[2]);

    const relative_claude = collectUserSkillRootCandidates(.{
        .home = "/home/me",
        .claude_config_dir = "claude-config",
    }, &store, &dest);
    try std.testing.expectEqual(@as(usize, 9), relative_claude);
    try std.testing.expectEqualStrings("/home/me/.claude/skills", dest[1]);

    const win = collectUserSkillRootCandidates(.{
        .userprofile = "C:\\Users\\me",
        .claude_config_dir = "C:\\Claude",
    }, &store, &dest);
    try std.testing.expectEqual(@as(usize, 9), win);
    try std.testing.expectEqualStrings("C:/Users/me/.agents/skills", dest[0]);
    try std.testing.expectEqualStrings("C:/Claude/skills", dest[1]);
    try std.testing.expectEqualStrings("C:/Users/me/.fx/skills", dest[5]);
}

test "existingUserSkillRoots keeps Waku order of dirs that exist" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var home_buf: [256]u8 = undefined;
    const home = try std.fmt.bufPrint(&home_buf, ".zig-cache/tmp/{s}/faku-user-roots", .{tmp.sub_path[0..]});
    var cursor_buf: [256]u8 = undefined;
    const cursor = try std.fmt.bufPrint(&cursor_buf, "{s}/.cursor/skills", .{home});
    var fx_buf: [256]u8 = undefined;
    const fx_root = try std.fmt.bufPrint(&fx_buf, "{s}/.fx/skills", .{home});
    try std.Io.Dir.cwd().createDirPath(testing.io, cursor);
    try std.Io.Dir.cwd().createDirPath(testing.io, fx_root);

    var store: [max_user_skill_roots][max_skill_path]u8 = undefined;
    var cand: [max_user_skill_roots][]const u8 = undefined;
    const cand_n = collectUserSkillRootCandidates(.{ .home = home }, &store, &cand);
    try std.testing.expectEqual(@as(usize, 9), cand_n);
    var existing: [max_user_skill_roots][]const u8 = undefined;
    const exist_n = existingUserSkillRoots(testing.io, cand[0..cand_n], &existing);
    try std.testing.expectEqual(@as(usize, 2), exist_n);
    try std.testing.expectEqualStrings(cursor, existing[0]);
    try std.testing.expectEqualStrings(fx_root, existing[1]);

    var model = Model{};
    model.store_io = testing.io;
    bindUserSkillRootsFromEnv(&model, .{ .home = home });
    try std.testing.expectEqual(@as(usize, 2), model.skill_user_root_count);
    var root_ptrs: [max_user_skill_roots][]const u8 = undefined;
    const bound = userRootsOnModel(&model, &root_ptrs);
    try std.testing.expectEqual(@as(usize, 2), bound.len);
    try std.testing.expectEqualStrings(cursor, bound[0]);
    try std.testing.expectEqualStrings(fx_root, bound[1]);
    var argv_buf: [walk_argv_len][]const u8 = undefined;
    const argv = unixWalkArgvFor("/tmp/faku-proj", bound, &argv_buf);
    try std.testing.expectEqual(@as(usize, unix_walk_argv_base + 2), argv.len);
    try std.testing.expectEqualStrings("/tmp/faku-proj", argv[4]);
    try std.testing.expectEqualStrings(cursor, argv[5]);
    try std.testing.expectEqualStrings(fx_root, argv[6]);
    try std.testing.expect(std.mem.indexOf(u8, argv[2], cursor) == null);
    try std.testing.expect(isSkillsWalkArgv(argv));
}

test "applyStdoutPaths merges relative project then absolute user; cap prefers project then user order" {
    var model = Model{};
    applyStdoutPaths(&model, ".cursor/skills/alpha/SKILL.md\n/home/me/.cursor/skills/user-one/SKILL.md\n");
    try std.testing.expectEqual(@as(u32, 2), cachedCount(&model));
    try std.testing.expectEqualStrings(".cursor/skills/alpha/SKILL.md", cachedPath(&model, 0));
    try std.testing.expect(!isAbsoluteSkillPath(cachedPath(&model, 0)));
    try std.testing.expectEqualStrings("/home/me/.cursor/skills/user-one/SKILL.md", cachedPath(&model, 1));
    try std.testing.expect(isAbsoluteSkillPath(cachedPath(&model, 1)));
    try std.testing.expectEqualStrings("alpha", cachedName(&model, 0));
    try std.testing.expectEqualStrings("user-one", cachedName(&model, 1));

    applyStdoutPaths(&model, "/home/me/.cursor/skills/user-one/SKILL.md.disabled\n.cursor/skills/alpha/SKILL.md.disabled\n");
    try std.testing.expectEqual(@as(u32, 2), cachedCount(&model));
    try std.testing.expect(cachedEnabled(&model, 0));
    try std.testing.expect(cachedEnabled(&model, 1));

    clearCache(&model);
    var overflow: [max_skills * 80 + 64]u8 = undefined;
    var n: usize = 0;
    var i: usize = 0;
    while (i < max_skills) : (i += 1) {
        const piece = try std.fmt.bufPrint(overflow[n..], "skills/p{d}/SKILL.md\n", .{i});
        n += piece.len;
    }
    const extra = try std.fmt.bufPrint(overflow[n..], "/home/me/.cursor/skills/overflow/SKILL.md\n", .{});
    n += extra.len;
    applyStdoutPaths(&model, overflow[0..n]);
    try std.testing.expectEqual(@as(u32, max_skills), cachedCount(&model));
    try std.testing.expectEqualStrings("skills/p0/SKILL.md", cachedPath(&model, 0));
    try std.testing.expect(!isAbsoluteSkillPath(cachedPath(&model, 0)));
    try std.testing.expect(!isAbsoluteSkillPath(cachedPath(&model, max_skills - 1)));

    clearCache(&model);
    n = 0;
    i = 0;
    while (i < max_skills - 2) : (i += 1) {
        const piece = try std.fmt.bufPrint(overflow[n..], "skills/p{d}/SKILL.md\n", .{i});
        n += piece.len;
    }
    const user0 = try std.fmt.bufPrint(overflow[n..], "/home/me/.agents/skills/ua/SKILL.md\n", .{});
    n += user0.len;
    const user1 = try std.fmt.bufPrint(overflow[n..], "/home/me/.cursor/skills/ub/SKILL.md\n", .{});
    n += user1.len;
    const user2 = try std.fmt.bufPrint(overflow[n..], "/home/me/.fx/skills/uc/SKILL.md\n", .{});
    n += user2.len;
    applyStdoutPaths(&model, overflow[0..n]);
    try std.testing.expectEqual(@as(u32, max_skills), cachedCount(&model));
    try std.testing.expectEqualStrings("skills/p0/SKILL.md", cachedPath(&model, 0));
    try std.testing.expectEqualStrings("/home/me/.agents/skills/ua/SKILL.md", cachedPath(&model, max_skills - 2));
    try std.testing.expectEqualStrings("/home/me/.cursor/skills/ub/SKILL.md", cachedPath(&model, max_skills - 1));
}

test "skill_rows User section classifies absolute catalog paths" {
    const testing = std.testing;
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const root = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-skills-user-class", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(testing.io, root);

    var model = Model{};
    model.store_io = testing.io;
    model.setLastProjectPath(root);
    model.settings_page = .skills;
    applyStdoutPaths(&model, ".cursor/skills/proj/SKILL.md\n/home/me/.fx/skills/from-home/SKILL.md\n");
    const rows = model.skill_rows(arena);
    try testing.expectEqual(@as(usize, 4), rows.len);
    try testing.expect(rows[0].is_header);
    try testing.expectEqual(skill_header_id_project, rows[0].id);
    try testing.expect(!rows[1].is_header);
    try testing.expectEqualStrings(".cursor/skills/proj/SKILL.md", rows[1].path);
    try testing.expect(rows[2].is_header);
    try testing.expectEqual(skill_header_id_user, rows[2].id);
    try testing.expectEqualStrings("USER", rows[2].name);
    try testing.expectEqualStrings("1", rows[2].count);
    try testing.expect(!rows[3].is_header);
    try testing.expectEqualStrings("/home/me/.fx/skills/from-home/SKILL.md", rows[3].path);
    try testing.expectEqualStrings("from-home", rows[3].name);
}

test "absolute user catalog paths keep Enable/Disable Delete Open Reveal Copy insert slash Send prepend" {
    const testing = std.testing;
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&dir_buf, "/tmp/faku-user-abs-{s}", .{tmp.sub_path});
    try std.Io.Dir.cwd().createDirPath(testing.io, project);

    var user_dir_buf: [320]u8 = undefined;
    const user_dir = try std.fmt.bufPrint(&user_dir_buf, "/tmp/faku-user-home-{s}/.fx/skills/from-home", .{tmp.sub_path});
    try writeTestSkill(testing.io, user_dir, "from-home", "User skill body.", false);
    var user_file_buf: [360]u8 = undefined;
    const user_file = try std.fmt.bufPrint(&user_file_buf, "{s}/SKILL.md", .{user_dir});
    try testing.expect(isAbsoluteSkillPath(user_file));

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = testing.io;
    model.setLastProjectPath(project);
    writeFixed(&model.skill_probe_path_storage, &model.skill_probe_path_len, project);
    model.settings_page = .skills;
    var stdout_buf: [512]u8 = undefined;
    const stdout = try std.fmt.bufPrint(&stdout_buf, ".cursor/skills/proj/SKILL.md\n{s}\n", .{user_file});
    applyStdoutPaths(&model, stdout);
    try testing.expectEqual(@as(u32, 2), cachedCount(&model));
    try testing.expect(!isAbsoluteSkillPath(cachedPath(&model, 0)));
    try testing.expectEqualStrings(user_file, cachedPath(&model, 1));
    try testing.expect(isAbsoluteSkillPath(cachedPath(&model, 1)));
    try testing.expectEqualStrings("from-home", cachedName(&model, 1));
    try testing.expect(cachedEnabled(&model, 1));

    {
        const rows = model.skill_rows(arena);
        try testing.expectEqual(@as(usize, 4), rows.len);
        try testing.expectEqual(skill_header_id_user, rows[2].id);
        try testing.expectEqualStrings(user_file, rows[3].path);
    }

    model.draft_buffer.set("$");
    {
        const rows = model.skill_insert_rows(arena);
        try testing.expectEqual(@as(usize, 2), rows.len);
        try testing.expect(!rows[0].is_header);
        try testing.expect(!rows[1].is_header);
        try testing.expectEqualStrings("proj", rows[0].name);
        try testing.expectEqualStrings("from-home", rows[1].name);
        try testing.expectEqual(skillId(1), rows[1].id);
    }

    const id = model.addSession("user abs actions", .fx);
    model.selected = id;
    model.draft_buffer.set("/");
    {
        const rows = model.command_rows(arena);
        try testing.expectEqual(@as(usize, 2), rows.len);
        try testing.expectEqualStrings("/proj", rows[0].slash_name);
        try testing.expectEqualStrings("/from-home", rows[1].slash_name);
        try testing.expectEqual(slashCommandId(1), rows[1].id);
    }

    var prompt_buf: [model_exports.max_body]u8 = undefined;
    const expanded = expandPrompt(&model, "$from-home do it", &prompt_buf);
    try testing.expect(std.mem.indexOf(u8, expanded, "### Skill: from-home") != null);
    try testing.expect(std.mem.indexOf(u8, expanded, "User skill body.") != null);
    try testing.expect(std.mem.endsWith(u8, expanded, "$from-home do it"));
    const slash_expanded = expandPrompt(&model, "/from-home do it", &prompt_buf);
    try testing.expect(std.mem.indexOf(u8, slash_expanded, "### Skill: from-home") != null);
    const sent = prepareSendPrompt(&model, &fx, "$from-home do it", &prompt_buf);
    try testing.expect(std.mem.indexOf(u8, sent, "User skill body.") != null);

    selectSkill(&model, 2);
    try testing.expectEqualStrings("User skill body.", model.skill_body_storage[0..model.skill_body_len]);
    var abs_buf: [model_exports.max_project_path + max_skill_path + 1]u8 = undefined;
    try testing.expectEqualStrings(user_file, selectedSkillAbsPath(&model, &abs_buf).?);
    try testing.expectEqualStrings(user_dir, selectedSkillAbsParent(&model, &abs_buf).?);

    copySelectedSkillPath(&model, &fx);
    try testing.expectEqual(@as(usize, 1), fx.pendingClipboardCount());
    try testing.expectEqualStrings(user_dir, fx.pendingClipboardAt(0).?.text);
    try testing.expectEqualStrings(path_copied_status, model.window_status());

    openSelectedSkillInEditor(&model, &fx);
    const open_spawn = fx.pendingSpawnAt(0) orelse return error.MissingOpenEditorSpawn;
    try testing.expect(open_editor.isEditorArgv(open_spawn.argv));
    const open_slot: usize = if (open_spawn.argv.len == 4) 3 else 1;
    try testing.expectEqualStrings(user_file, open_spawn.argv[open_slot]);

    revealSelectedSkill(&model, &fx);
    var reveal: ?@TypeOf(fx.pendingSpawnAt(0).?) = null;
    var ri: usize = 0;
    while (fx.pendingSpawnAt(ri)) |item| : (ri += 1) {
        if (reveal_folder.isRevealArgv(item.argv)) {
            reveal = item;
            break;
        }
    }
    try testing.expect(reveal != null);
    try testing.expectEqualStrings(user_dir, reveal.?.argv[1]);

    toggleSkillEnabled(&model, &fx);
    try testing.expect(model.skill_rename_key >= skills_rename_key_first);
    const rename = pendingSpawnKey(&fx, model.skill_rename_key) orelse return error.MissingUserRename;
    try testing.expect(isSkillsRenameArgv(rename.argv));
    switch (builtin.os.tag) {
        .windows => try testing.expectEqualStrings(user_dir, rename.argv[5]),
        else => try testing.expectEqualStrings(user_dir, rename.argv[4]),
    }

    model.skill_rename_key = 0;
    armSkillDelete(&model);
    confirmSkillDelete(&model, &fx);
    try testing.expectEqual(@as(u64, 0), model.daemon_trash_skills_key);
    try testing.expect(model.skill_remove_key >= skills_remove_key_first);
    const remove = pendingSpawnKey(&fx, model.skill_remove_key) orelse return error.MissingUserRemove;
    try testing.expect(isSkillsRemoveArgv(remove.argv));
    switch (builtin.os.tag) {
        .windows => try testing.expectEqualStrings(user_dir, remove.argv[5]),
        else => try testing.expectEqualStrings(user_dir, remove.argv[8]),
    }
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

test "parse allowed-tools from frontmatter; quoted and missing" {
    try std.testing.expectEqualStrings("Bash, Read", parseFrontmatterAllowedTools(
        \\---
        \\name: my-skill
        \\allowed-tools: Bash, Read
        \\---
        \\
        \\# Body
    ));
    try std.testing.expectEqualStrings("Pretty Tools", parseFrontmatterAllowedTools(
        \\---
        \\allowed-tools: "Pretty Tools"
        \\---
        \\body
    ));
    try std.testing.expectEqualStrings("quoted", parseFrontmatterAllowedTools(
        \\---
        \\allowed-tools: 'quoted'
        \\---
    ));
    try std.testing.expectEqualStrings("", parseFrontmatterAllowedTools("# no fence\nallowed-tools: nope\n"));
    try std.testing.expectEqualStrings("", parseFrontmatterAllowedTools("---\nname: x\n---\n"));
    try std.testing.expectEqualStrings("", parseFrontmatterAllowedTools(""));
    try std.testing.expectEqualStrings("", parseFrontmatterAllowedTools(
        \\---
        \\allowed-tools:
        \\---
    ));
    try std.testing.expectEqualStrings("", parseFrontmatterAllowedTools(
        \\---
        \\allowed_tools: Bash
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

test "emptyHint follows Appearance language; scanning and no-match vs No skills found" {
    const testing = std.testing;
    var model = Model{};
    try testing.expectEqualStrings("Open a project", emptyHint(&model));
    try testing.expectEqualStrings(open_project, emptyHint(&model));
    try testing.expectEqualStrings("Open a project", insertEmptyHint(&model));
    try testing.expectEqualStrings("Open a project", i18n.skillsEmptyChromeFor(.english, "").open_project);
    try testing.expectEqualStrings("Scanning skill folders…", scanning);
    try testing.expectEqualStrings("No skills found", no_skills_found);
    try testing.expectEqualStrings("No skills match your search", no_matching);

    model.language_preference = .simplified_chinese;
    try testing.expectEqualStrings("打开项目", emptyHint(&model));
    try testing.expectEqualStrings("打开项目", insertEmptyHint(&model));
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
    try testing.expectEqualStrings("No skills found", insertEmptyHint(&model));
    model.language_preference = .simplified_chinese;
    try testing.expectEqualStrings("未找到技能", emptyHint(&model));
    try testing.expectEqualStrings("未找到技能", insertEmptyHint(&model));
    model.language_preference = .japanese;
    try testing.expectEqualStrings("スキルが見つかりません", emptyHint(&model));
    model.language_preference = .english;
    model.setSystemLocaleId("zh_CN.UTF-8");
    try testing.expectEqualStrings("No skills found", emptyHint(&model));
    model.language_preference = .system;
    try testing.expectEqualStrings("未找到技能", emptyHint(&model));
    model.setSystemLocaleId("ja_JP.UTF-8");
    try testing.expectEqualStrings("スキルが見つかりません", emptyHint(&model));
    model.setSystemLocaleId("");
    model.language_preference = .english;
    model.skill_key = 1;
    try testing.expect(scanInFlight(&model));
    try testing.expectEqualStrings("Scanning skill folders…", emptyHint(&model));
    try testing.expectEqualStrings("", insertEmptyHint(&model));
    model.language_preference = .simplified_chinese;
    try testing.expectEqualStrings("正在扫描技能目录…", emptyHint(&model));
    try testing.expectEqualStrings("", insertEmptyHint(&model));
    model.language_preference = .japanese;
    try testing.expectEqualStrings("スキルフォルダをスキャン中…", emptyHint(&model));
    model.language_preference = .english;
    model.skill_key = 0;
    try testing.expectEqualStrings("No skills found", emptyHint(&model));
    try testing.expectEqualStrings("No skills found", insertEmptyHint(&model));

    applyStdoutPaths(&model, "./.cursor/skills/demo/SKILL.md\n");
    try testing.expectEqual(@as(u32, 1), cachedCount(&model));
    try testing.expectEqualStrings("", emptyHint(&model));
    try testing.expectEqualStrings("", insertEmptyHint(&model));
    model.skills_filter_buffer.apply(.{ .insert_text = "zzz" });
    try testing.expectEqualStrings("No skills match your search", emptyHint(&model));
    try testing.expectEqualStrings("", insertEmptyHint(&model));
    model.language_preference = .simplified_chinese;
    try testing.expectEqualStrings("没有匹配的技能", emptyHint(&model));
    try testing.expectEqualStrings("", insertEmptyHint(&model));
    model.language_preference = .japanese;
    try testing.expectEqualStrings("検索に一致するスキルはありません", emptyHint(&model));
    model.language_preference = .english;
    model.skills_filter_buffer.clear();
    try testing.expectEqualStrings("", emptyHint(&model));
    model.skills_filter_buffer.apply(.{ .insert_text = "demo" });
    try testing.expectEqualStrings("", emptyHint(&model));
    model.skill_key = 1;
    try testing.expectEqualStrings("Scanning skill folders…", emptyHint(&model));
    try testing.expectEqualStrings("", insertEmptyHint(&model));
}

test "isNoSkillsEmpty only when project open, scan idle, skill_count 0" {
    const testing = std.testing;
    var model = Model{};
    try testing.expect(!isNoSkillsEmpty(&model));
    try testing.expectEqualStrings("Open a project", emptyHint(&model));
    try testing.expectEqualStrings("Open a project", insertEmptyHint(&model));

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const root = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-skills-rich-empty", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(testing.io, root);
    model.store_io = testing.io;
    model.setLastProjectPath(root);
    try testing.expect(isNoSkillsEmpty(&model));
    try testing.expectEqualStrings("No skills found", emptyHint(&model));
    try testing.expectEqualStrings("No skills found", insertEmptyHint(&model));

    model.skill_key = 1;
    try testing.expect(scanInFlight(&model));
    try testing.expect(!isNoSkillsEmpty(&model));
    try testing.expectEqualStrings("Scanning skill folders…", emptyHint(&model));
    try testing.expectEqualStrings("", insertEmptyHint(&model));
    model.skill_key = 0;
    try testing.expect(isNoSkillsEmpty(&model));
    try testing.expectEqualStrings("No skills found", insertEmptyHint(&model));

    applyStdoutPaths(&model, "./.cursor/skills/demo/SKILL.md\n");
    try testing.expectEqual(@as(u32, 1), cachedCount(&model));
    try testing.expect(!isNoSkillsEmpty(&model));
    try testing.expectEqualStrings("", emptyHint(&model));
    try testing.expectEqualStrings("", insertEmptyHint(&model));
    model.skills_filter_buffer.apply(.{ .insert_text = "zzz" });
    try testing.expect(!isNoSkillsEmpty(&model));
    try testing.expectEqualStrings("No skills match your search", emptyHint(&model));
    try testing.expectEqualStrings("", insertEmptyHint(&model));
}

test "skills_needs_select true only on Skills page with rows and no selection" {
    const testing = std.testing;
    var model = Model{};
    try testing.expectEqualStrings("Select a skill", select_placeholder);
    try testing.expectEqualStrings("Select a skill", i18n.skillsSelectChromeFor(.english, "").select_placeholder);
    try testing.expect(!model.skills_needs_select());
    try testing.expectEqualStrings("", model.skills_select_placeholder());

    model.settings_page = .skills;
    try testing.expect(model.skills_empty());
    try testing.expect(!model.skills_empty_rich());
    try testing.expect(!model.skills_needs_select());
    try testing.expectEqualStrings("", model.skills_select_placeholder());
    try testing.expectEqualStrings("", model.skills_empty_title());
    try testing.expectEqualStrings("", model.skills_empty_description());
    try testing.expectEqualStrings("Open a project", emptyHint(&model));
    try testing.expectEqualStrings("Open a project", model.skills_empty_hint());

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const root = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-skills-select", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(testing.io, root);
    model.store_io = testing.io;
    model.setLastProjectPath(root);
    try testing.expect(model.skills_empty());
    try testing.expect(model.skills_empty_rich());
    try testing.expect(!model.skills_needs_select());
    try testing.expectEqualStrings("No skills found", emptyHint(&model));
    try testing.expectEqualStrings("", model.skills_empty_hint());
    try testing.expectEqualStrings("No skills yet", model.skills_empty_title());
    try testing.expectEqualStrings(
        i18n.skillsEmptyRichChromeFor(.english, "").empty_description,
        model.skills_empty_description(),
    );
    try testing.expectEqualStrings("No skills found", insertEmptyHint(&model));

    model.language_preference = .simplified_chinese;
    try testing.expectEqualStrings("还没有技能", model.skills_empty_title());
    try testing.expectEqualStrings(
        i18n.skillsEmptyRichChromeFor(.simplified_chinese, "").empty_description,
        model.skills_empty_description(),
    );
    try testing.expectEqualStrings("", model.skills_empty_hint());
    try testing.expectEqualStrings("未找到技能", insertEmptyHint(&model));
    model.language_preference = .japanese;
    try testing.expectEqualStrings("スキルはまだありません", model.skills_empty_title());
    try testing.expectEqualStrings("スキルが見つかりません", insertEmptyHint(&model));
    model.language_preference = .english;
    model.setSystemLocaleId("zh_CN.UTF-8");
    try testing.expectEqualStrings("No skills yet", model.skills_empty_title());
    model.language_preference = .system;
    try testing.expectEqualStrings("还没有技能", model.skills_empty_title());
    model.setSystemLocaleId("");
    model.language_preference = .english;

    model.settings_page = .general;
    try testing.expect(!model.skills_empty());
    try testing.expect(!model.skills_empty_rich());
    try testing.expectEqualStrings("", model.skills_empty_title());
    try testing.expectEqualStrings("No skills found", emptyHint(&model));
    try testing.expectEqualStrings("No skills found", insertEmptyHint(&model));
    model.settings_page = .skills;
    try testing.expect(model.skills_empty_rich());

    model.skill_key = 1;
    try testing.expect(scanInFlight(&model));
    try testing.expect(model.skills_empty());
    try testing.expect(!model.skills_empty_rich());
    try testing.expect(!model.skills_needs_select());
    try testing.expectEqualStrings("Scanning skill folders…", emptyHint(&model));
    try testing.expectEqualStrings("Scanning skill folders…", model.skills_empty_hint());
    try testing.expectEqualStrings("", model.skills_empty_title());
    try testing.expectEqualStrings("", insertEmptyHint(&model));
    model.skill_key = 0;

    applyStdoutPaths(&model, "./.cursor/skills/demo/SKILL.md\n");
    try testing.expectEqual(@as(u32, 1), cachedCount(&model));
    try testing.expectEqual(@as(u32, 0), model.skill_selected_id);
    try testing.expect(!model.has_selected_skill());
    try testing.expect(!model.skills_empty());
    try testing.expect(model.skills_needs_select());
    try testing.expectEqualStrings("Select a skill", model.skills_select_placeholder());

    model.language_preference = .simplified_chinese;
    try testing.expectEqualStrings("选择一个技能", model.skills_select_placeholder());
    model.language_preference = .japanese;
    try testing.expectEqualStrings("スキルを選択", model.skills_select_placeholder());
    model.language_preference = .english;
    model.setSystemLocaleId("ja_JP.UTF-8");
    try testing.expectEqualStrings("Select a skill", model.skills_select_placeholder());
    model.language_preference = .system;
    try testing.expectEqualStrings("スキルを選択", model.skills_select_placeholder());
    model.setSystemLocaleId("zh_CN.UTF-8");
    try testing.expectEqualStrings("选择一个技能", model.skills_select_placeholder());
    model.setSystemLocaleId("");
    model.language_preference = .english;
    try testing.expectEqualStrings("Select a skill", model.skills_select_placeholder());

    model.settings_page = .general;
    try testing.expect(!model.skills_needs_select());
    try testing.expectEqualStrings("", model.skills_select_placeholder());
    try testing.expect(!model.skills_empty());
    model.settings_page = .appearance;
    try testing.expect(!model.skills_needs_select());
    model.settings_page = .skills;
    try testing.expect(model.skills_needs_select());

    selectSkill(&model, 1);
    try testing.expect(model.has_selected_skill());
    try testing.expect(!model.skills_empty());
    try testing.expect(!model.skills_needs_select());
    try testing.expectEqualStrings("", model.skills_select_placeholder());

    model.skill_selected_id = 0;
    try testing.expect(model.skills_needs_select());
    model.skills_filter_buffer.apply(.{ .insert_text = "zzz" });
    try testing.expect(model.skills_empty());
    try testing.expect(!model.skills_empty_rich());
    try testing.expect(!model.skills_needs_select());
    try testing.expectEqualStrings("", model.skills_select_placeholder());
    try testing.expectEqualStrings("", model.skills_empty_title());
    try testing.expectEqualStrings("No skills match your search", emptyHint(&model));
    try testing.expectEqualStrings("No skills match your search", model.skills_empty_hint());
    try testing.expectEqualStrings("", insertEmptyHint(&model));
    model.skills_filter_buffer.clear();
    try testing.expect(model.skills_needs_select());
    try testing.expectEqualStrings("Select a skill", model.skills_select_placeholder());
}

test "selected-detail chrome description vs no_description; invoke / location / contents; updated mtime; unselected empty" {
    const testing = std.testing;
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    try testing.expectEqualStrings("No description", no_description);
    try testing.expectEqualStrings("Invoke", detail_invoke);
    try testing.expectEqualStrings("Location", detail_location);
    try testing.expectEqualStrings("Contents", detail_contents);
    try testing.expectEqualStrings("Updated", detail_updated);
    try testing.expectEqualStrings("Just now", updated_just_now);
    try testing.expectEqualStrings("No description", i18n.skillsDetailChromeFor(.english, "").no_description);
    try testing.expectEqualStrings("暂无描述", i18n.skillsDetailChromeFor(.simplified_chinese, "").no_description);
    try testing.expectEqualStrings("説明なし", i18n.skillsDetailChromeFor(.japanese, "").no_description);
    try testing.expectEqualStrings("Invoke", i18n.skillsDetailChromeFor(.english, "").detail_invoke);
    try testing.expectEqualStrings("调用", i18n.skillsDetailChromeFor(.simplified_chinese, "").detail_invoke);
    try testing.expectEqualStrings("呼び出し", i18n.skillsDetailChromeFor(.japanese, "").detail_invoke);
    try testing.expectEqualStrings("Location", i18n.skillsDetailChromeFor(.english, "").detail_location);
    try testing.expectEqualStrings("位置", i18n.skillsDetailChromeFor(.simplified_chinese, "").detail_location);
    try testing.expectEqualStrings("場所", i18n.skillsDetailChromeFor(.japanese, "").detail_location);
    try testing.expectEqualStrings("Contents", i18n.skillsDetailChromeFor(.english, "").detail_contents);
    try testing.expectEqualStrings("内容", i18n.skillsDetailChromeFor(.simplified_chinese, "").detail_contents);
    try testing.expectEqualStrings("内容", i18n.skillsDetailChromeFor(.japanese, "").detail_contents);
    try testing.expectEqualStrings("Updated", i18n.skillsUpdatedChromeFor(.english, "").detail_updated);
    try testing.expectEqualStrings("更新", i18n.skillsUpdatedChromeFor(.simplified_chinese, "").detail_updated);
    try testing.expectEqualStrings("更新日時", i18n.skillsUpdatedChromeFor(.japanese, "").detail_updated);
    try testing.expectEqualStrings("Just now", i18n.skillsUpdatedChromeFor(.english, "").updated_just_now);
    try testing.expectEqualStrings("刚刚", i18n.skillsUpdatedChromeFor(.simplified_chinese, "").updated_just_now);
    try testing.expectEqualStrings("たった今", i18n.skillsUpdatedChromeFor(.japanese, "").updated_just_now);

    var model = Model{};
    try testing.expect(!model.has_selected_skill());
    try testing.expect(!model.has_skill_description());
    try testing.expectEqualStrings("", model.skill_description());
    try testing.expectEqualStrings("", model.skill_no_description());
    try testing.expectEqualStrings("", model.skill_detail_invoke());
    try testing.expectEqualStrings("", model.skill_invoke_line(arena));
    try testing.expectEqualStrings("", model.skill_detail_location());
    try testing.expectEqualStrings("", model.skill_location(arena));
    try testing.expectEqualStrings("", model.skill_detail_contents());
    try testing.expect(!model.has_skill_updated());
    try testing.expectEqualStrings("", model.skill_detail_updated());
    try testing.expectEqualStrings("", model.skill_updated_label(arena));
    try testing.expect(!model.has_skill_contents_summary());
    try testing.expectEqualStrings("", model.skill_contents_summary(arena));
    try testing.expect(!model.has_skill_allowed_tools());
    try testing.expectEqualStrings("", model.skill_detail_allowed_tools());
    try testing.expectEqualStrings("", model.skill_allowed_tools());
    try testing.expectEqualStrings("", model.skill_name());
    try testing.expect(!model.has_skill_disabled_badge());
    try testing.expectEqualStrings("", model.skill_disabled_badge());
    try testing.expect(!model.has_skill_scope_caption());
    try testing.expectEqualStrings("", model.skill_scope_caption(arena));
    try testing.expectEqualStrings("1 supporting file", i18n.skillsFileCountChromeFor(.english, "").file_count_one);
    try testing.expectEqualStrings("%{count} supporting files", i18n.skillsFileCountChromeFor(.english, "").file_count_many);
    try testing.expectEqualStrings("1 个附属文件", i18n.skillsFileCountChromeFor(.simplified_chinese, "").file_count_one);
    try testing.expectEqualStrings("補助ファイル 1 件", i18n.skillsFileCountChromeFor(.japanese, "").file_count_one);
    try testing.expectEqualStrings("", selectedSkillDescription(&model));
    try testing.expectEqualStrings("", selectedSkillInvokeLine(&model, arena));
    try testing.expectEqualStrings("", selectedSkillLocation(&model, arena));

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const root = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-skills-detail", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(testing.io, root);

    var with_dir_buf: [320]u8 = undefined;
    const with_dir = try std.fmt.bufPrint(&with_dir_buf, "{s}/.cursor/skills/with-desc", .{root});
    try std.Io.Dir.cwd().createDirPath(testing.io, with_dir);
    var with_file_buf: [360]u8 = undefined;
    const with_file = try std.fmt.bufPrint(&with_file_buf, "{s}/SKILL.md", .{with_dir});
    try std.Io.Dir.cwd().writeFile(testing.io, .{
        .sub_path = with_file,
        .data =
        \\---
        \\name: with-desc
        \\description: Does the described thing.
        \\---
        \\
        \\Body stays in the detail pane.
        \\
        ,
    });
    var bare_dir_buf: [320]u8 = undefined;
    const bare_dir = try std.fmt.bufPrint(&bare_dir_buf, "{s}/.cursor/skills/bare", .{root});
    try writeTestSkill(testing.io, bare_dir, "bare", "", false);
    var user_dir_buf: [320]u8 = undefined;
    const user_dir = try std.fmt.bufPrint(&user_dir_buf, "/tmp/faku-skills-detail-user-{s}/.fx/skills/from-home", .{tmp.sub_path});
    try writeTestSkill(testing.io, user_dir, "from-home", "User skill body.", false);
    var user_file_buf: [360]u8 = undefined;
    const user_file = try std.fmt.bufPrint(&user_file_buf, "{s}/SKILL.md", .{user_dir});

    model.store_io = testing.io;
    model.setLastProjectPath(root);
    writeFixed(&model.skill_probe_path_storage, &model.skill_probe_path_len, root);
    model.settings_page = .skills;
    var stdout_buf: [512]u8 = undefined;
    const stdout = try std.fmt.bufPrint(&stdout_buf, ".cursor/skills/with-desc/SKILL.md\n.cursor/skills/bare/SKILL.md\n{s}\n", .{user_file});
    applyStdoutPaths(&model, stdout);
    try testing.expectEqual(@as(u32, 3), cachedCount(&model));
    try testing.expect(!model.has_selected_skill());
    try testing.expect(model.skills_needs_select());
    try testing.expectEqualStrings("Select a skill", model.skills_select_placeholder());
    try testing.expectEqualStrings("", model.skill_no_description());
    try testing.expectEqualStrings("", model.skill_detail_invoke());
    try testing.expectEqualStrings("", model.skill_invoke_line(arena));
    try testing.expectEqualStrings("", model.skill_detail_location());
    try testing.expectEqualStrings("", model.skill_location(arena));
    try testing.expectEqualStrings("", model.skill_detail_contents());
    try testing.expect(!model.has_skill_body());
    try testing.expect(!model.has_skill_updated());
    try testing.expectEqualStrings("", model.skill_detail_updated());
    try testing.expectEqualStrings("", model.skill_updated_label(arena));
    try testing.expectEqualStrings("", insertEmptyHint(&model));
    try testing.expect(!model.has_skill_allowed_tools());
    try testing.expectEqualStrings("", model.skill_detail_allowed_tools());
    try testing.expectEqualStrings("", model.skill_allowed_tools());

    selectSkill(&model, 1);
    try testing.expect(model.has_selected_skill());
    try testing.expect(!model.skills_needs_select());
    try testing.expectEqualStrings("", model.skills_select_placeholder());
    try testing.expectEqualStrings("with-desc", model.skill_name());
    try testing.expect(!model.has_skill_disabled_badge());
    try testing.expect(model.has_skill_scope_caption());
    try testing.expectEqualStrings("Cursor · in faku-skills-detail", model.skill_scope_caption(arena));
    try testing.expect(model.has_skill_description());
    try testing.expectEqualStrings("Does the described thing.", model.skill_description());
    try testing.expectEqualStrings("", model.skill_no_description());
    try testing.expectEqualStrings("Invoke", model.skill_detail_invoke());
    try testing.expectEqualStrings("/with-desc", model.skill_invoke_line(arena));
    try testing.expectEqualStrings("Location", model.skill_detail_location());
    try testing.expectEqualStrings(with_dir, model.skill_location(arena));
    try testing.expectEqualStrings("Contents", model.skill_detail_contents());
    try testing.expect(model.has_skill_body());
    try testing.expectEqualStrings("Body stays in the detail pane.", model.skill_body());
    try testing.expect(model.has_skill_updated());
    try testing.expectEqualStrings("Updated", model.skill_detail_updated());
    try testing.expectEqualStrings("Just now", model.skill_updated_label(arena));
    try testing.expect(model.has_skill_contents_summary());
    {
        const with_bytes = try testFileSize(testing.io, with_file);
        var sum_buf: [i18n.skills_contents_summary_max]u8 = undefined;
        const expected = i18n.formatSkillsContentsSummary(i18n.skillsFileCountChromeFor(.english, ""), 0, with_bytes, &sum_buf);
        try testing.expectEqualStrings(expected, model.skill_contents_summary(arena));
        try testing.expect(std.mem.indexOf(u8, expected, "supporting") == null);
    }
    try testing.expectEqualStrings("Just now", selectedSkillUpdatedLabelAt(&model, model.skill_mtime_unix, arena));
    try testing.expectEqualStrings("1m ago", selectedSkillUpdatedLabelAt(&model, model.skill_mtime_unix + 60, arena));
    try testing.expectEqualStrings("1h ago", selectedSkillUpdatedLabelAt(&model, model.skill_mtime_unix + 3600, arena));
    try testing.expectEqualStrings("1d ago", selectedSkillUpdatedLabelAt(&model, model.skill_mtime_unix + 86400, arena));

    model.language_preference = .simplified_chinese;
    try testing.expectEqualStrings("", model.skill_no_description());
    try testing.expectEqualStrings("调用", model.skill_detail_invoke());
    try testing.expectEqualStrings("位置", model.skill_detail_location());
    try testing.expectEqualStrings("内容", model.skill_detail_contents());
    try testing.expectEqualStrings("更新", model.skill_detail_updated());
    try testing.expectEqualStrings("刚刚", model.skill_updated_label(arena));
    try testing.expect(model.has_skill_contents_summary());
    try testing.expect(std.mem.indexOf(u8, model.skill_contents_summary(arena), "附属文件") == null);
    try testing.expectEqualStrings("5 分钟前", selectedSkillUpdatedLabelAt(&model, model.skill_mtime_unix + 300, arena));
    try testing.expectEqualStrings("/with-desc", model.skill_invoke_line(arena));
    try testing.expectEqualStrings("Does the described thing.", model.skill_description());
    try testing.expect(!model.has_skill_allowed_tools());
    try testing.expectEqualStrings("", model.skill_detail_allowed_tools());
    try testing.expectEqualStrings("", model.skill_allowed_tools());
    model.language_preference = .japanese;
    try testing.expectEqualStrings("呼び出し", model.skill_detail_invoke());
    try testing.expectEqualStrings("場所", model.skill_detail_location());
    try testing.expectEqualStrings("内容", model.skill_detail_contents());
    try testing.expectEqualStrings("更新日時", model.skill_detail_updated());
    try testing.expectEqualStrings("たった今", model.skill_updated_label(arena));
    try testing.expect(std.mem.indexOf(u8, model.skill_contents_summary(arena), "補助ファイル") == null);
    try testing.expectEqualStrings("2 時間前", selectedSkillUpdatedLabelAt(&model, model.skill_mtime_unix + 7200, arena));
    model.language_preference = .english;
    model.setSystemLocaleId("zh_CN.UTF-8");
    try testing.expectEqualStrings("Invoke", model.skill_detail_invoke());
    try testing.expectEqualStrings("Updated", model.skill_detail_updated());
    model.language_preference = .system;
    try testing.expectEqualStrings("调用", model.skill_detail_invoke());
    try testing.expectEqualStrings("更新", model.skill_detail_updated());
    try testing.expectEqualStrings("刚刚", model.skill_updated_label(arena));
    try testing.expectEqualStrings("暂无描述", i18n.skillsDetailChromeFor(.system, "zh_CN.UTF-8").no_description);
    model.setSystemLocaleId("");
    model.language_preference = .english;

    selectSkill(&model, 2);
    try testing.expect(model.has_selected_skill());
    try testing.expect(!model.has_skill_description());
    try testing.expectEqualStrings("", model.skill_description());
    try testing.expectEqualStrings("No description", model.skill_no_description());
    try testing.expectEqualStrings("/bare", model.skill_invoke_line(arena));
    try testing.expectEqualStrings(bare_dir, model.skill_location(arena));
    try testing.expectEqualStrings("Contents", model.skill_detail_contents());
    try testing.expect(!model.has_skill_body());
    try testing.expectEqualStrings("", model.skill_body());
    try testing.expect(model.has_skill_updated());
    try testing.expectEqualStrings("Updated", model.skill_detail_updated());
    try testing.expectEqualStrings("Just now", model.skill_updated_label(arena));
    try testing.expect(model.has_skill_contents_summary());
    try testing.expect(std.mem.indexOf(u8, model.skill_contents_summary(arena), "supporting") == null);
    try testing.expect(!model.has_skill_allowed_tools());
    try testing.expectEqualStrings("", model.skill_detail_allowed_tools());
    try testing.expectEqualStrings("", model.skill_allowed_tools());
    model.language_preference = .simplified_chinese;
    try testing.expectEqualStrings("暂无描述", model.skill_no_description());
    try testing.expectEqualStrings("调用", model.skill_detail_invoke());
    try testing.expectEqualStrings("更新", model.skill_detail_updated());
    model.language_preference = .japanese;
    try testing.expectEqualStrings("説明なし", model.skill_no_description());
    try testing.expectEqualStrings("呼び出し", model.skill_detail_invoke());
    try testing.expectEqualStrings("更新日時", model.skill_detail_updated());
    model.language_preference = .english;

    const saved_probe = model.skill_probe_path_len;
    model.skill_probe_path_len = 0;
    try testing.expectEqualStrings(".cursor/skills/bare/SKILL.md", model.skill_location(arena));
    model.skill_probe_path_len = saved_probe;
    try testing.expectEqualStrings(bare_dir, model.skill_location(arena));

    selectSkill(&model, 3);
    try testing.expectEqualStrings("/from-home", model.skill_invoke_line(arena));
    try testing.expectEqualStrings("from-home", model.skill_name());
    try testing.expectEqualStrings("fx · available in every project", model.skill_scope_caption(arena));
    try testing.expectEqualStrings(user_dir, model.skill_location(arena));
    try testing.expect(model.has_skill_body());
    try testing.expectEqualStrings("User skill body.", model.skill_body());
    try testing.expect(!model.has_skill_description());
    try testing.expectEqualStrings("No description", model.skill_no_description());
    try testing.expect(model.has_skill_updated());
    try testing.expectEqualStrings("Updated", model.skill_detail_updated());
    try testing.expectEqualStrings("Just now", model.skill_updated_label(arena));

    model.settings_page = .general;
    try testing.expect(!model.has_selected_skill());
    try testing.expectEqualStrings("", model.skill_no_description());
    try testing.expectEqualStrings("", model.skill_detail_invoke());
    try testing.expectEqualStrings("", model.skill_invoke_line(arena));
    try testing.expectEqualStrings("", model.skill_detail_location());
    try testing.expectEqualStrings("", model.skill_location(arena));
    try testing.expectEqualStrings("", model.skill_detail_contents());
    try testing.expect(!model.has_skill_body());
    try testing.expect(!model.has_skill_updated());
    try testing.expectEqualStrings("", model.skill_detail_updated());
    try testing.expectEqualStrings("", model.skill_updated_label(arena));
    try testing.expect(!model.has_skill_contents_summary());
    try testing.expectEqualStrings("", model.skill_contents_summary(arena));
    try testing.expect(!model.has_skill_allowed_tools());
    try testing.expectEqualStrings("", model.skill_detail_allowed_tools());
    try testing.expectEqualStrings("", model.skill_allowed_tools());
    model.settings_page = .skills;
    try testing.expect(model.has_selected_skill());
    try testing.expectEqualStrings("/from-home", model.skill_invoke_line(arena));
    try testing.expect(model.has_skill_updated());
    try testing.expectEqualStrings("Updated", model.skill_detail_updated());

    model.skill_selected_id = 0;
    try testing.expect(model.skills_needs_select());
    try testing.expectEqualStrings("Select a skill", model.skills_select_placeholder());
    try testing.expectEqualStrings("", model.skill_no_description());
    try testing.expectEqualStrings("", model.skill_detail_invoke());
    try testing.expectEqualStrings("", model.skill_invoke_line(arena));
    try testing.expect(!model.has_skill_updated());
    try testing.expectEqualStrings("", model.skill_detail_updated());
    try testing.expectEqualStrings("", model.skill_updated_label(arena));
    try testing.expect(!model.has_skill_contents_summary());
    try testing.expectEqualStrings("", model.skill_contents_summary(arena));
    try testing.expect(!model.has_skill_allowed_tools());
    try testing.expectEqualStrings("", model.skill_detail_allowed_tools());
    try testing.expectEqualStrings("", model.skill_allowed_tools());
    try testing.expectEqualStrings("", insertEmptyHint(&model));

    clearCache(&model);
    applyStdoutPaths(&model, ".cursor/skills/missing/SKILL.md\n");
    try testing.expectEqual(@as(u32, 1), cachedCount(&model));
    model.settings_page = .skills;
    selectSkill(&model, 1);
    try testing.expect(model.has_selected_skill());
    try testing.expect(!model.has_skill_body());
    try testing.expect(!model.has_skill_updated());
    try testing.expectEqualStrings("", model.skill_detail_updated());
    try testing.expectEqualStrings("", model.skill_updated_label(arena));
    try testing.expect(!model.has_skill_contents_summary());
    try testing.expectEqualStrings("", model.skill_contents_summary(arena));
    try testing.expect(!model.has_skill_allowed_tools());
    try testing.expectEqualStrings("", model.skill_detail_allowed_tools());
    try testing.expectEqualStrings("", model.skill_allowed_tools());
    try testing.expectEqualStrings("Updated", i18n.skillsUpdatedChromeFor(.english, "").detail_updated);
    model.skill_mtime_valid = false;
    try testing.expectEqualStrings("", model.skill_detail_updated());
}

test "selected-detail Contents file_count · bytes; one/many/zero; locales; fail closed" {
    const testing = std.testing;
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const root = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-skills-contents", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(testing.io, root);

    var one_dir_buf: [320]u8 = undefined;
    const one_dir = try std.fmt.bufPrint(&one_dir_buf, "{s}/.cursor/skills/one-file", .{root});
    try writeTestSkill(testing.io, one_dir, "one-file", "One body.", false);
    var one_skill_buf: [360]u8 = undefined;
    const one_skill = try std.fmt.bufPrint(&one_skill_buf, "{s}/SKILL.md", .{one_dir});
    var one_extra_buf: [360]u8 = undefined;
    const one_extra = try std.fmt.bufPrint(&one_extra_buf, "{s}/runbook.md", .{one_dir});
    try std.Io.Dir.cwd().writeFile(testing.io, .{ .sub_path = one_extra, .data = "details" });
    var one_hidden_buf: [360]u8 = undefined;
    const one_hidden = try std.fmt.bufPrint(&one_hidden_buf, "{s}/.secret", .{one_dir});
    try std.Io.Dir.cwd().writeFile(testing.io, .{ .sub_path = one_hidden, .data = "skip-me" });

    var many_dir_buf: [320]u8 = undefined;
    const many_dir = try std.fmt.bufPrint(&many_dir_buf, "{s}/.cursor/skills/many-files", .{root});
    try writeTestSkill(testing.io, many_dir, "many-files", "Many body.", false);
    var many_skill_buf: [360]u8 = undefined;
    const many_skill = try std.fmt.bufPrint(&many_skill_buf, "{s}/SKILL.md", .{many_dir});
    var many_a_buf: [360]u8 = undefined;
    const many_a = try std.fmt.bufPrint(&many_a_buf, "{s}/a.md", .{many_dir});
    var many_b_buf: [360]u8 = undefined;
    const many_b = try std.fmt.bufPrint(&many_b_buf, "{s}/b.md", .{many_dir});
    var many_c_buf: [360]u8 = undefined;
    const many_c = try std.fmt.bufPrint(&many_c_buf, "{s}/nested", .{many_dir});
    try std.Io.Dir.cwd().createDirPath(testing.io, many_c);
    var many_c_file_buf: [400]u8 = undefined;
    const many_c_file = try std.fmt.bufPrint(&many_c_file_buf, "{s}/c.md", .{many_c});
    try std.Io.Dir.cwd().writeFile(testing.io, .{ .sub_path = many_a, .data = "aaa" });
    try std.Io.Dir.cwd().writeFile(testing.io, .{ .sub_path = many_b, .data = "bb" });
    try std.Io.Dir.cwd().writeFile(testing.io, .{ .sub_path = many_c_file, .data = "c" });

    var zero_dir_buf: [320]u8 = undefined;
    const zero_dir = try std.fmt.bufPrint(&zero_dir_buf, "{s}/.cursor/skills/zero-files", .{root});
    try writeTestSkill(testing.io, zero_dir, "zero-files", "", false);
    var zero_skill_buf: [360]u8 = undefined;
    const zero_skill = try std.fmt.bufPrint(&zero_skill_buf, "{s}/SKILL.md", .{zero_dir});

    var model = Model{};
    model.store_io = testing.io;
    model.setLastProjectPath(root);
    writeFixed(&model.skill_probe_path_storage, &model.skill_probe_path_len, root);
    model.settings_page = .skills;
    applyStdoutPaths(&model, ".cursor/skills/one-file/SKILL.md\n.cursor/skills/many-files/SKILL.md\n.cursor/skills/zero-files/SKILL.md\n");
    try testing.expectEqual(@as(u32, 3), cachedCount(&model));
    try testing.expect(!model.has_skill_contents_summary());
    try testing.expectEqualStrings("", model.skill_contents_summary(arena));

    selectSkill(&model, 1);
    try testing.expect(model.has_selected_skill());
    try testing.expect(model.has_skill_body());
    try testing.expectEqualStrings("One body.", model.skill_body());
    try testing.expect(model.has_skill_contents_summary());
    {
        const bytes = (try testFileSize(testing.io, one_skill)) + (try testFileSize(testing.io, one_extra));
        var sum_buf: [i18n.skills_contents_summary_max]u8 = undefined;
        const expected = i18n.formatSkillsContentsSummary(i18n.skillsFileCountChromeFor(.english, ""), 1, bytes, &sum_buf);
        try testing.expectEqualStrings(expected, model.skill_contents_summary(arena));
        try testing.expect(std.mem.startsWith(u8, expected, "1 supporting file · "));
    }
    model.language_preference = .simplified_chinese;
    try testing.expect(std.mem.startsWith(u8, model.skill_contents_summary(arena), "1 个附属文件 · "));
    model.language_preference = .japanese;
    try testing.expect(std.mem.startsWith(u8, model.skill_contents_summary(arena), "補助ファイル 1 件 · "));
    model.language_preference = .system;
    model.setSystemLocaleId("zh_CN.UTF-8");
    try testing.expect(std.mem.startsWith(u8, model.skill_contents_summary(arena), "1 个附属文件 · "));
    model.setSystemLocaleId("");
    model.language_preference = .english;

    selectSkill(&model, 2);
    try testing.expect(model.has_skill_contents_summary());
    try testing.expect(model.has_skill_body());
    {
        const bytes = (try testFileSize(testing.io, many_skill)) +
            (try testFileSize(testing.io, many_a)) +
            (try testFileSize(testing.io, many_b)) +
            (try testFileSize(testing.io, many_c_file));
        var sum_buf: [i18n.skills_contents_summary_max]u8 = undefined;
        const expected = i18n.formatSkillsContentsSummary(i18n.skillsFileCountChromeFor(.english, ""), 3, bytes, &sum_buf);
        try testing.expectEqualStrings(expected, model.skill_contents_summary(arena));
        try testing.expect(std.mem.startsWith(u8, expected, "3 supporting files · "));
    }
    model.language_preference = .simplified_chinese;
    try testing.expect(std.mem.startsWith(u8, model.skill_contents_summary(arena), "3 个附属文件 · "));
    model.language_preference = .japanese;
    try testing.expect(std.mem.startsWith(u8, model.skill_contents_summary(arena), "補助ファイル 3 件 · "));
    model.language_preference = .english;

    selectSkill(&model, 3);
    try testing.expect(model.has_skill_contents_summary());
    try testing.expect(!model.has_skill_body());
    {
        const bytes = try testFileSize(testing.io, zero_skill);
        var sum_buf: [i18n.skills_contents_summary_max]u8 = undefined;
        const expected = i18n.formatSkillsContentsSummary(i18n.skillsFileCountChromeFor(.english, ""), 0, bytes, &sum_buf);
        try testing.expectEqualStrings(expected, model.skill_contents_summary(arena));
        try testing.expect(std.mem.indexOf(u8, expected, "supporting") == null);
        try testing.expect(std.mem.endsWith(u8, expected, " B"));
    }

    model.skill_selected_id = 0;
    try testing.expect(!model.has_skill_contents_summary());
    try testing.expectEqualStrings("", model.skill_contents_summary(arena));
    try testing.expectEqualStrings("", model.skill_detail_contents());

    clearCache(&model);
    applyStdoutPaths(&model, ".cursor/skills/missing/SKILL.md\n");
    selectSkill(&model, 1);
    try testing.expect(model.has_selected_skill());
    try testing.expectEqualStrings("Contents", model.skill_detail_contents());
    try testing.expect(!model.has_skill_contents_summary());
    try testing.expectEqualStrings("", model.skill_contents_summary(arena));
}

test "selected-detail Allowed tools from YAML allowed-tools; locales; fail closed" {
    const testing = std.testing;

    try testing.expectEqualStrings("Tools", allowed_tools);
    try testing.expectEqualStrings("Tools", i18n.skillsAllowedToolsChromeFor(.english, "").allowed_tools);
    try testing.expectEqualStrings("工具", i18n.skillsAllowedToolsChromeFor(.simplified_chinese, "").allowed_tools);
    try testing.expectEqualStrings("ツール", i18n.skillsAllowedToolsChromeFor(.japanese, "").allowed_tools);

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const root = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-skills-allowed-tools", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(testing.io, root);

    var with_dir_buf: [360]u8 = undefined;
    const with_dir = try std.fmt.bufPrint(&with_dir_buf, "{s}/.cursor/skills/with-tools", .{root});
    try std.Io.Dir.cwd().createDirPath(testing.io, with_dir);
    var with_file_buf: [400]u8 = undefined;
    const with_file = try std.fmt.bufPrint(&with_file_buf, "{s}/SKILL.md", .{with_dir});
    try std.Io.Dir.cwd().writeFile(testing.io, .{
        .sub_path = with_file,
        .data =
        \\---
        \\name: with-tools
        \\description: Uses tools.
        \\allowed-tools: Bash, Read
        \\---
        \\
        \\Body stays in the detail pane.
        \\
        ,
    });
    var quoted_dir_buf: [360]u8 = undefined;
    const quoted_dir = try std.fmt.bufPrint(&quoted_dir_buf, "{s}/.cursor/skills/quoted-tools", .{root});
    try std.Io.Dir.cwd().createDirPath(testing.io, quoted_dir);
    var quoted_file_buf: [400]u8 = undefined;
    const quoted_file = try std.fmt.bufPrint(&quoted_file_buf, "{s}/SKILL.md", .{quoted_dir});
    try std.Io.Dir.cwd().writeFile(testing.io, .{
        .sub_path = quoted_file,
        .data =
        \\---
        \\name: quoted-tools
        \\allowed-tools: "Write, Edit"
        \\---
        \\
        \\Quoted tools body.
        \\
        ,
    });
    var bare_dir_buf: [360]u8 = undefined;
    const bare_dir = try std.fmt.bufPrint(&bare_dir_buf, "{s}/.cursor/skills/bare", .{root});
    try writeTestSkill(testing.io, bare_dir, "bare", "Bare body.", false);

    var model = Model{};
    model.store_io = testing.io;
    model.setLastProjectPath(root);
    writeFixed(&model.skill_probe_path_storage, &model.skill_probe_path_len, root);
    model.settings_page = .skills;
    applyStdoutPaths(&model, ".cursor/skills/with-tools/SKILL.md\n.cursor/skills/quoted-tools/SKILL.md\n.cursor/skills/bare/SKILL.md\n");
    try testing.expectEqual(@as(u32, 3), cachedCount(&model));
    try testing.expect(!model.has_selected_skill());
    try testing.expect(!model.has_skill_allowed_tools());
    try testing.expectEqualStrings("", model.skill_detail_allowed_tools());
    try testing.expectEqualStrings("", model.skill_allowed_tools());

    selectSkill(&model, 1);
    try testing.expect(model.has_selected_skill());
    try testing.expect(model.has_skill_allowed_tools());
    try testing.expectEqualStrings("Tools", model.skill_detail_allowed_tools());
    try testing.expectEqualStrings("Bash, Read", model.skill_allowed_tools());
    try testing.expectEqualStrings("Invoke", model.skill_detail_invoke());
    try testing.expectEqualStrings("Contents", model.skill_detail_contents());
    try testing.expect(model.has_skill_body());
    try testing.expectEqualStrings("Body stays in the detail pane.", model.skill_body());
    model.language_preference = .simplified_chinese;
    try testing.expectEqualStrings("工具", model.skill_detail_allowed_tools());
    try testing.expectEqualStrings("Bash, Read", model.skill_allowed_tools());
    try testing.expectEqualStrings("调用", model.skill_detail_invoke());
    model.language_preference = .japanese;
    try testing.expectEqualStrings("ツール", model.skill_detail_allowed_tools());
    try testing.expectEqualStrings("Bash, Read", model.skill_allowed_tools());
    model.language_preference = .english;
    model.setSystemLocaleId("zh_CN.UTF-8");
    try testing.expectEqualStrings("Tools", model.skill_detail_allowed_tools());
    model.language_preference = .system;
    try testing.expectEqualStrings("工具", model.skill_detail_allowed_tools());
    model.setSystemLocaleId("ja_JP.UTF-8");
    try testing.expectEqualStrings("ツール", model.skill_detail_allowed_tools());
    model.setSystemLocaleId("");
    model.language_preference = .english;
    try testing.expectEqualStrings("Tools", model.skill_detail_allowed_tools());

    selectSkill(&model, 2);
    try testing.expect(model.has_skill_allowed_tools());
    try testing.expectEqualStrings("Tools", model.skill_detail_allowed_tools());
    try testing.expectEqualStrings("Write, Edit", model.skill_allowed_tools());

    selectSkill(&model, 3);
    try testing.expect(model.has_selected_skill());
    try testing.expect(!model.has_skill_allowed_tools());
    try testing.expectEqualStrings("", model.skill_detail_allowed_tools());
    try testing.expectEqualStrings("", model.skill_allowed_tools());
    try testing.expectEqualStrings("No description", model.skill_no_description());

    model.settings_page = .general;
    try testing.expect(!model.has_selected_skill());
    try testing.expect(!model.has_skill_allowed_tools());
    try testing.expectEqualStrings("", model.skill_detail_allowed_tools());
    try testing.expectEqualStrings("", model.skill_allowed_tools());
    model.settings_page = .skills;
    try testing.expect(model.has_selected_skill());
    try testing.expect(!model.has_skill_allowed_tools());

    model.skill_selected_id = 0;
    try testing.expect(!model.has_skill_allowed_tools());
    try testing.expectEqualStrings("", model.skill_detail_allowed_tools());
    try testing.expectEqualStrings("", model.skill_allowed_tools());

    clearCache(&model);
    applyStdoutPaths(&model, ".cursor/skills/missing/SKILL.md\n");
    selectSkill(&model, 1);
    try testing.expect(model.has_selected_skill());
    try testing.expect(!model.has_skill_allowed_tools());
    try testing.expectEqualStrings("", model.skill_detail_allowed_tools());
    try testing.expectEqualStrings("", model.skill_allowed_tools());
}

test "countCaption empty-filter counts, filter caption, emptyHint owns, disabled append" {
    const testing = std.testing;
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var model = Model{};
    try testing.expect(!hasCountCaption(&model));
    try testing.expectEqualStrings("", countCaption(&model, arena));
    try testing.expect(!model.has_skills_count_caption());
    try testing.expectEqualStrings("", model.skills_count_caption(arena));
    try testing.expectEqualStrings("Open a project", emptyHint(&model));

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const root = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-skills-count", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(testing.io, root);
    model.store_io = testing.io;
    model.setLastProjectPath(root);
    try testing.expectEqualStrings("No skills found", emptyHint(&model));
    try testing.expect(!hasCountCaption(&model));
    try testing.expectEqualStrings("", countCaption(&model, arena));

    model.skill_key = 1;
    try testing.expect(scanInFlight(&model));
    try testing.expectEqualStrings("Scanning skill folders…", emptyHint(&model));
    try testing.expect(!hasCountCaption(&model));
    try testing.expectEqualStrings("", countCaption(&model, arena));
    model.skill_key = 0;

    applyStdoutPaths(&model, "./.cursor/skills/demo/SKILL.md\n");
    try testing.expectEqual(@as(u32, 1), cachedCount(&model));
    try testing.expect(hasCountCaption(&model));
    try testing.expectEqualStrings("1 skill", countCaption(&model, arena));
    try testing.expectEqualStrings(
        i18n.skillsCountChromeFor(.english, "").count_one,
        countCaption(&model, arena),
    );
    model.settings_page = .skills;
    try testing.expect(model.has_skills_count_caption());
    try testing.expectEqualStrings("1 skill", model.skills_count_caption(arena));
    model.settings_page = .general;
    try testing.expect(!model.has_skills_count_caption());
    try testing.expectEqualStrings("", model.skills_count_caption(arena));
    model.settings_page = .skills;

    model.language_preference = .simplified_chinese;
    try testing.expectEqualStrings("1 个技能", countCaption(&model, arena));
    try testing.expectEqualStrings("1 个技能", model.skills_count_caption(arena));
    model.language_preference = .japanese;
    try testing.expectEqualStrings("1 個のスキル", countCaption(&model, arena));
    model.language_preference = .english;
    model.setSystemLocaleId("ja_JP.UTF-8");
    try testing.expectEqualStrings("1 skill", countCaption(&model, arena));
    model.language_preference = .system;
    try testing.expectEqualStrings("1 個のスキル", countCaption(&model, arena));
    model.setSystemLocaleId("zh_CN.UTF-8");
    try testing.expectEqualStrings("1 个技能", countCaption(&model, arena));
    model.setSystemLocaleId("");
    model.language_preference = .english;
    try testing.expectEqualStrings("1 skill", countCaption(&model, arena));

    applyStdoutPaths(&model, "./.cursor/skills/other/SKILL.md\n./.agents/skills/off/SKILL.md.disabled\n");
    try testing.expectEqual(@as(u32, 3), cachedCount(&model));
    try testing.expectEqualStrings("3 skills · 1 disabled", countCaption(&model, arena));
    try testing.expectEqualStrings("3 skills · 1 disabled", model.skills_count_caption(arena));
    model.language_preference = .simplified_chinese;
    try testing.expectEqualStrings("3 个技能 · 已禁用 1 个", countCaption(&model, arena));
    model.language_preference = .japanese;
    try testing.expectEqualStrings("3 個のスキル · 無効 1 件", countCaption(&model, arena));
    model.language_preference = .english;
    try testing.expectEqualStrings("3 skills · 1 disabled", countCaption(&model, arena));

    model.skills_filter_buffer.apply(.{ .insert_text = "demo" });
    try testing.expect(!model.skills_empty());
    try testing.expectEqualStrings("", emptyHint(&model));
    try testing.expect(hasCountCaption(&model));
    try testing.expectEqualStrings("1 of 3 shown", countCaption(&model, arena));
    try testing.expectEqualStrings("1 of 3 shown", model.skills_count_caption(arena));
    model.language_preference = .simplified_chinese;
    try testing.expectEqualStrings("显示 1 / 3 个", countCaption(&model, arena));
    model.language_preference = .japanese;
    try testing.expectEqualStrings("3 件中 1 件を表示", countCaption(&model, arena));
    model.language_preference = .english;
    try testing.expectEqualStrings("1 of 3 shown", countCaption(&model, arena));

    model.skills_filter_buffer.clear();
    model.skills_filter_buffer.apply(.{ .insert_text = "SKILL" });
    try testing.expectEqualStrings("3 of 3 shown", countCaption(&model, arena));
    model.skills_filter_buffer.clear();
    model.skills_filter_buffer.apply(.{ .insert_text = "   " });
    try testing.expectEqualStrings("3 skills · 1 disabled", countCaption(&model, arena));

    model.skills_filter_buffer.clear();
    model.skills_filter_buffer.apply(.{ .insert_text = "zzz" });
    try testing.expect(model.skills_empty());
    try testing.expectEqualStrings("No skills match your search", emptyHint(&model));
    try testing.expect(!hasCountCaption(&model));
    try testing.expectEqualStrings("", countCaption(&model, arena));
    try testing.expect(!model.has_skills_count_caption());
    try testing.expectEqualStrings("", model.skills_count_caption(arena));
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
    try std.testing.expect(!isSkillsRenameArgv(unixWalkArgvFor("/tmp/faku-skills", &.{}, &walk_buf)));
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
    try std.testing.expect(!isSkillsRenameArgv(windowsWalkArgvFor(cwd, &.{}, &walk_buf)));
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
    try std.testing.expect(trashDirAllowed("/home/me/.cursor/skills/user-one", "/home/me/.cursor/skills/user-one"));
    try std.testing.expect(trashDirAllowed("C:/Users/me/.fx/skills/from-home", "C:/Users/me/.fx/skills/from-home"));
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

test "skill_reveal_label equals SkillsRevealChrome reveal" {
    var model = Model{};
    try std.testing.expectEqualStrings(
        i18n.skillsRevealChromeFor(.english, "").reveal,
        model.skill_reveal_label(),
    );
    try std.testing.expectEqualStrings("Show in File Manager", model.skill_reveal_label());
    try std.testing.expectEqualStrings("Reveal folder", model.reveal_folder_label());
    try std.testing.expect(!std.mem.eql(u8, model.reveal_folder_label(), model.skill_reveal_label()));
    try std.testing.expect(!std.mem.eql(u8, i18n.composerProjectChromeFor(.english, "").reveal_folder, model.skill_reveal_label()));
    model.language_preference = .simplified_chinese;
    try std.testing.expectEqualStrings(
        i18n.skillsRevealChromeFor(.simplified_chinese, "").reveal,
        model.skill_reveal_label(),
    );
    try std.testing.expectEqualStrings("在文件管理器中显示", model.skill_reveal_label());
    try std.testing.expect(!std.mem.eql(u8, model.reveal_folder_label(), model.skill_reveal_label()));
    model.language_preference = .japanese;
    try std.testing.expectEqualStrings(
        i18n.skillsRevealChromeFor(.japanese, "").reveal,
        model.skill_reveal_label(),
    );
    try std.testing.expectEqualStrings("ファイルマネージャーで表示", model.skill_reveal_label());
    try std.testing.expect(!std.mem.eql(u8, model.reveal_folder_label(), model.skill_reveal_label()));
}

test "copySelectedSkillPath queues writeClipboard with the absolute skill parent directory" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const root = try std.fmt.bufPrint(&dir_buf, "/tmp/faku-skills-copy-path-{s}", .{tmp.sub_path});
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
    try std.testing.expectEqualStrings(skill_dir, selectedSkillAbsParent(&model, &abs_buf).?);

    copySelectedSkillPath(&model, &fx);
    try std.testing.expectEqual(@as(usize, 1), fx.pendingClipboardCount());
    try std.testing.expectEqual(@as(usize, 0), fx.pendingSpawnCount());
    const written = fx.pendingClipboardAt(0).?;
    try std.testing.expectEqual(copy.copy_turn_key, written.key);
    try std.testing.expectEqual(native_sdk.EffectClipboardOp.write, written.op);
    try std.testing.expectEqualStrings(skill_dir, written.text);
    try std.testing.expect(!std.mem.eql(u8, written.text, file_path));
    try std.testing.expect(!std.mem.endsWith(u8, written.text, "/SKILL.md"));
    try std.testing.expectEqualStrings("Path copied", model.window_status());
    try std.testing.expectEqualStrings(model.skill_path_copied_status(), model.window_status());
    try std.testing.expectEqualStrings(path_copied_status, model.window_status());
    try std.testing.expectEqualStrings(i18n.skillsPathCopiedChromeFor(.english, "").path_copied, model.window_status());

    model.language_preference = .simplified_chinese;
    copySelectedSkillPath(&model, &fx);
    try std.testing.expectEqual(@as(usize, 1), fx.pendingClipboardCount());
    try std.testing.expectEqualStrings("已复制路径", model.window_status());
    try std.testing.expectEqualStrings(model.skill_path_copied_status(), model.window_status());
    try std.testing.expectEqualStrings(i18n.skillsPathCopiedChromeFor(.simplified_chinese, "").path_copied, model.window_status());
    try std.testing.expect(!std.mem.eql(u8, path_copied_status, model.window_status()));

    model.language_preference = .japanese;
    copySelectedSkillPath(&model, &fx);
    try std.testing.expectEqual(@as(usize, 1), fx.pendingClipboardCount());
    try std.testing.expectEqualStrings("パスをコピーしました", model.window_status());
    try std.testing.expectEqualStrings(model.skill_path_copied_status(), model.window_status());
    try std.testing.expectEqualStrings(i18n.skillsPathCopiedChromeFor(.japanese, "").path_copied, model.window_status());

    model.language_preference = .english;
    model.setSystemLocaleId("ja_JP.UTF-8");
    copySelectedSkillPath(&model, &fx);
    try std.testing.expectEqualStrings("Path copied", model.window_status());
    try std.testing.expectEqualStrings(path_copied_status, model.window_status());

    model.language_preference = .system;
    model.setSystemLocaleId("zh_CN.UTF-8");
    copySelectedSkillPath(&model, &fx);
    try std.testing.expectEqualStrings("已复制路径", model.window_status());

    model.setSystemLocaleId("ja_JP.UTF-8");
    copySelectedSkillPath(&model, &fx);
    try std.testing.expectEqualStrings("パスをコピーしました", model.window_status());
}

test "copySelectedSkillPath fails closed with no selection or unresolved path" {
    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    copySelectedSkillPath(&model, &fx);
    try std.testing.expectEqual(@as(usize, 0), fx.pendingClipboardCount());
    try std.testing.expectEqualStrings("", model.window_status());

    applyStdoutPaths(&model, ".cursor/skills/demo/SKILL.md\n");
    selectSkill(&model, 1);
    copySelectedSkillPath(&model, &fx);
    try std.testing.expectEqual(@as(usize, 0), fx.pendingClipboardCount());
    try std.testing.expectEqualStrings("", model.window_status());
}

test "skill_copy_path_label equals SkillsCopyPathChrome copy_path" {
    var model = Model{};
    try std.testing.expectEqualStrings(
        i18n.skillsCopyPathChromeFor(.english, "").copy_path,
        model.skill_copy_path_label(),
    );
    try std.testing.expectEqualStrings("Copy Path", model.skill_copy_path_label());
    try std.testing.expectEqualStrings("Copy path", model.copy_path_label());
    try std.testing.expect(!std.mem.eql(u8, model.copy_path_label(), model.skill_copy_path_label()));
    try std.testing.expect(!std.mem.eql(u8, i18n.composerProjectChromeFor(.english, "").copy_path, model.skill_copy_path_label()));
    model.language_preference = .simplified_chinese;
    try std.testing.expectEqualStrings(
        i18n.skillsCopyPathChromeFor(.simplified_chinese, "").copy_path,
        model.skill_copy_path_label(),
    );
    try std.testing.expectEqualStrings("复制路径", model.skill_copy_path_label());
    model.language_preference = .japanese;
    try std.testing.expectEqualStrings(
        i18n.skillsCopyPathChromeFor(.japanese, "").copy_path,
        model.skill_copy_path_label(),
    );
    try std.testing.expectEqualStrings("パスをコピー", model.skill_copy_path_label());
}

test "skill_path_copied_status equals SkillsPathCopiedChrome path_copied" {
    var model = Model{};
    try std.testing.expectEqualStrings(
        i18n.skillsPathCopiedChromeFor(.english, "").path_copied,
        model.skill_path_copied_status(),
    );
    try std.testing.expectEqualStrings("Path copied", model.skill_path_copied_status());
    try std.testing.expectEqualStrings(path_copied_status, model.skill_path_copied_status());
    try std.testing.expect(!std.mem.eql(u8, model.skill_copy_path_label(), model.skill_path_copied_status()));
    model.language_preference = .simplified_chinese;
    try std.testing.expectEqualStrings(
        i18n.skillsPathCopiedChromeFor(.simplified_chinese, "").path_copied,
        model.skill_path_copied_status(),
    );
    try std.testing.expectEqualStrings("已复制路径", model.skill_path_copied_status());
    model.language_preference = .japanese;
    try std.testing.expectEqualStrings(
        i18n.skillsPathCopiedChromeFor(.japanese, "").path_copied,
        model.skill_path_copied_status(),
    );
    try std.testing.expectEqualStrings("パスをコピーしました", model.skill_path_copied_status());
    model.language_preference = .english;
    model.setSystemLocaleId("ja_JP.UTF-8");
    try std.testing.expectEqualStrings("Path copied", model.skill_path_copied_status());
    model.language_preference = .system;
    model.setSystemLocaleId("zh_CN.UTF-8");
    try std.testing.expectEqualStrings("已复制路径", model.skill_path_copied_status());
    model.setSystemLocaleId("ja_JP.UTF-8");
    try std.testing.expectEqualStrings("パスをコピーしました", model.skill_path_copied_status());
}

test "skill_deleted_status formats %{name} from SkillsDeletedToastChrome" {
    var model = Model{};
    var buf: [i18n.skills_deleted_toast_max]u8 = undefined;
    try std.testing.expectEqualStrings(deleted_toast_template, i18n.skillsDeletedToastChromeFor(.english, "").deleted_toast);
    try std.testing.expectEqualStrings(
        "Moved “demo” to the Trash",
        model.skill_deleted_status("demo", &buf),
    );
    try std.testing.expectEqualStrings(
        i18n.formatSkillsDeletedToast(i18n.skillsDeletedToastChromeFor(.english, ""), "demo", &buf),
        model.skill_deleted_status("demo", &buf),
    );
    try std.testing.expect(!std.mem.eql(u8, model.skill_deleted_status("demo", &buf), model.skill_delete_failed_status()));
    try std.testing.expect(!std.mem.eql(u8, model.skill_deleted_status("demo", &buf), model.skill_path_copied_status()));
    try std.testing.expectEqualStrings(
        "Moved “” to the Trash",
        model.skill_deleted_status("", &buf),
    );

    model.language_preference = .simplified_chinese;
    try std.testing.expectEqualStrings(
        "已将“demo”移到废纸篓",
        model.skill_deleted_status("demo", &buf),
    );
    model.language_preference = .japanese;
    try std.testing.expectEqualStrings(
        "「demo」をゴミ箱に移動しました",
        model.skill_deleted_status("demo", &buf),
    );
    model.language_preference = .english;
    model.setSystemLocaleId("ja_JP.UTF-8");
    try std.testing.expectEqualStrings(
        "Moved “demo” to the Trash",
        model.skill_deleted_status("demo", &buf),
    );
    model.language_preference = .system;
    model.setSystemLocaleId("zh_CN.UTF-8");
    try std.testing.expectEqualStrings(
        "已将“demo”移到废纸篓",
        model.skill_deleted_status("demo", &buf),
    );
    model.setSystemLocaleId("ja_JP.UTF-8");
    try std.testing.expectEqualStrings(
        "「demo」をゴミ箱に移動しました",
        model.skill_deleted_status("demo", &buf),
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
    try testing.expect(!rows[0].is_header);

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
        try testing.expectEqual(@as(usize, 3), rows.len);
        try testing.expect(rows[0].is_header);
        try testing.expectEqualStrings("2", rows[0].count);
        try testing.expect(rows[1].has_description);
        try testing.expectEqualStrings("Does the described thing.", rows[1].description);
        try testing.expect(!rows[1].is_header);
        try testing.expect(!rows[2].has_description);
        try testing.expectEqualStrings("", rows[2].description);
        try testing.expect(!rows[2].is_header);
    }

    model.draft_buffer.set("$");
    {
        const rows = model.skill_insert_rows(arena);
        try testing.expectEqual(@as(usize, 2), rows.len);
        try testing.expect(rows[0].has_description);
        try testing.expectEqualStrings("Does the described thing.", rows[0].description);
        try testing.expect(!rows[0].is_header);
        try testing.expect(!rows[1].has_description);
        try testing.expect(!rows[1].is_header);
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

test "skill_rows groups project then user with section headers; insert stays flat" {
    const testing = std.testing;
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const root = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-skills-sections", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(testing.io, root);

    var model = Model{};
    model.store_io = testing.io;
    model.setLastProjectPath(root);
    model.settings_page = .skills;
    try testing.expectEqualStrings("User", section_user);
    try testing.expectEqualStrings("User", i18n.skillsSectionChromeFor(.english, "").section_user);
    try testing.expectEqualStrings("用户", i18n.skillsSectionChromeFor(.simplified_chinese, "").section_user);
    try testing.expectEqualStrings("ユーザー", i18n.skillsSectionChromeFor(.japanese, "").section_user);
    try testing.expectEqualStrings("faku-skills-sections", sectionProjectLabel(&model));

    applyStdoutPaths(&model, ".cursor/skills/alpha/SKILL.md\n.cursor/skills/beta/SKILL.md\n");
    {
        const rows = model.skill_rows(arena);
        try testing.expectEqual(@as(usize, 3), rows.len);
        try testing.expect(rows[0].is_header);
        try testing.expectEqual(skill_header_id_project, rows[0].id);
        try testing.expectEqualStrings("FAKU-SKILLS-SECTIONS", rows[0].name);
        try testing.expectEqualStrings("2", rows[0].count);
        try testing.expectEqualStrings("", rows[0].path);
        try testing.expect(!rows[0].selected);
        try testing.expect(!rows[0].disabled);
        try testing.expect(!rows[1].is_header);
        try testing.expectEqualStrings("alpha", rows[1].name);
        try testing.expectEqual(skillId(0), rows[1].id);
        try testing.expectEqualStrings("beta", rows[2].name);
        try testing.expectEqual(skillId(1), rows[2].id);
    }

    model.skill_count = 0;
    applyStdoutPaths(&model, "/home/me/.cursor/skills/user-one/SKILL.md\n/home/me/.cursor/skills/user-two/SKILL.md\n");
    {
        const rows = model.skill_rows(arena);
        try testing.expectEqual(@as(usize, 3), rows.len);
        try testing.expect(rows[0].is_header);
        try testing.expectEqual(skill_header_id_user, rows[0].id);
        try testing.expectEqualStrings("USER", rows[0].name);
        try testing.expectEqualStrings("2", rows[0].count);
        try testing.expect(!rows[1].is_header);
        try testing.expectEqualStrings("user-one", rows[1].name);
        try testing.expectEqualStrings("/home/me/.cursor/skills/user-one/SKILL.md", rows[1].path);
        try testing.expectEqualStrings("user-two", rows[2].name);
    }

    model.language_preference = .simplified_chinese;
    {
        const rows = model.skill_rows(arena);
        try testing.expectEqualStrings("用户", rows[0].name);
    }
    model.language_preference = .japanese;
    {
        const rows = model.skill_rows(arena);
        try testing.expectEqualStrings("ユーザー", rows[0].name);
    }
    model.language_preference = .english;

    model.skill_count = 0;
    applyStdoutPaths(&model, "/home/me/.cursor/skills/user-one/SKILL.md\n.cursor/skills/alpha/SKILL.md\n/home/me/.cursor/skills/user-two/SKILL.md\n.cursor/skills/beta/SKILL.md\n");
    {
        const rows = model.skill_rows(arena);
        try testing.expectEqual(@as(usize, 6), rows.len);
        try testing.expect(rows[0].is_header);
        try testing.expectEqual(skill_header_id_project, rows[0].id);
        try testing.expectEqualStrings("FAKU-SKILLS-SECTIONS", rows[0].name);
        try testing.expectEqualStrings("2", rows[0].count);
        try testing.expectEqualStrings("alpha", rows[1].name);
        try testing.expectEqualStrings("beta", rows[2].name);
        try testing.expect(rows[3].is_header);
        try testing.expectEqual(skill_header_id_user, rows[3].id);
        try testing.expectEqualStrings("USER", rows[3].name);
        try testing.expectEqualStrings("2", rows[3].count);
        try testing.expectEqualStrings("user-one", rows[4].name);
        try testing.expectEqualStrings("user-two", rows[5].name);
    }

    model.skills_filter_buffer.apply(.{ .insert_text = "user-one" });
    {
        const rows = model.skill_rows(arena);
        try testing.expectEqual(@as(usize, 2), rows.len);
        try testing.expect(rows[0].is_header);
        try testing.expectEqual(skill_header_id_user, rows[0].id);
        try testing.expectEqualStrings("USER", rows[0].name);
        try testing.expectEqualStrings("1", rows[0].count);
        try testing.expectEqualStrings("user-one", rows[1].name);
        try testing.expect(!rows[1].is_header);
    }
    model.skills_filter_buffer.clear();
    model.skills_filter_buffer.apply(.{ .insert_text = "alpha" });
    {
        const rows = model.skill_rows(arena);
        try testing.expectEqual(@as(usize, 2), rows.len);
        try testing.expect(rows[0].is_header);
        try testing.expectEqual(skill_header_id_project, rows[0].id);
        try testing.expectEqualStrings("1", rows[0].count);
        try testing.expectEqualStrings("alpha", rows[1].name);
    }
    model.skills_filter_buffer.clear();
    model.skills_filter_buffer.apply(.{ .insert_text = "zzz" });
    try testing.expectEqual(@as(usize, 0), model.skill_rows(arena).len);
    try testing.expectEqualStrings("No skills match your search", emptyHint(&model));
    try testing.expect(!isNoSkillsEmpty(&model));
    model.skills_filter_buffer.clear();

    model.skill_count = 0;
    try testing.expect(isNoSkillsEmpty(&model));
    try testing.expectEqual(@as(usize, 0), model.skill_rows(arena).len);
    try testing.expectEqualStrings("No skills found", emptyHint(&model));
    model.skill_key = 1;
    try testing.expect(scanInFlight(&model));
    try testing.expectEqual(@as(usize, 0), model.skill_rows(arena).len);
    try testing.expectEqualStrings("Scanning skill folders…", emptyHint(&model));
    model.skill_key = 0;

    applyStdoutPaths(&model, "/home/me/.cursor/skills/user-one/SKILL.md\n.cursor/skills/alpha/SKILL.md\n");
    model.draft_buffer.set("$");
    {
        const rows = model.skill_insert_rows(arena);
        try testing.expectEqual(@as(usize, 2), rows.len);
        try testing.expect(!rows[0].is_header);
        try testing.expect(!rows[1].is_header);
        try testing.expectEqualStrings("", rows[0].count);
        try testing.expectEqualStrings("user-one", rows[0].name);
        try testing.expectEqualStrings("alpha", rows[1].name);
    }

    selectSkill(&model, 1);
    try testing.expectEqual(@as(u32, 1), model.skill_selected_id);
    armSkillDelete(&model);
    try testing.expect(model.skill_delete_arming);
    selectSkill(&model, skill_header_id_project);
    try testing.expectEqual(@as(u32, 1), model.skill_selected_id);
    try testing.expect(model.skill_delete_arming);
    selectSkill(&model, skill_header_id_user);
    try testing.expectEqual(@as(u32, 1), model.skill_selected_id);
    try testing.expect(model.skill_delete_arming);

    model.settings_page = .general;
    try testing.expectEqual(@as(usize, 0), model.skill_rows(arena).len);
}

test "skill_rows folds same-name user installs; multi-location source labels; insert stays flat" {
    const testing = std.testing;
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    try testing.expectEqual(SkillSourceKind.shared, skillSourceKind("/home/me/.agents/skills/demo/SKILL.md"));
    try testing.expectEqual(SkillSourceKind.shared, skillSourceKind("/home/me/.config/agents/skills/demo/SKILL.md"));
    try testing.expectEqual(SkillSourceKind.claude, skillSourceKind("/home/me/.claude/skills/demo/SKILL.md"));
    try testing.expectEqual(SkillSourceKind.codex, skillSourceKind("/home/me/.codex/skills/demo/SKILL.md"));
    try testing.expectEqual(SkillSourceKind.opencode, skillSourceKind("/home/me/.config/opencode/skills/demo/SKILL.md"));
    try testing.expectEqual(SkillSourceKind.cursor, skillSourceKind("/home/me/.cursor/skills/demo/SKILL.md"));
    try testing.expectEqual(SkillSourceKind.fx, skillSourceKind("/home/me/.fx/skills/demo/SKILL.md"));
    try testing.expectEqual(SkillSourceKind.pi, skillSourceKind("/home/me/.pi/agent/skills/demo/SKILL.md"));
    try testing.expectEqual(SkillSourceKind.omp, skillSourceKind("/home/me/.omp/agent/skills/demo/SKILL.md"));
    try testing.expectEqual(SkillSourceKind.unknown, skillSourceKind("/tmp/unrelated/demo/SKILL.md"));
    var compact_buf: [max_skill_path + 2]u8 = undefined;
    try testing.expectEqualStrings("~/.cursor/skills/demo", compactHomePath("/home/me/.cursor/skills/demo", "/home/me", &compact_buf));
    try testing.expectEqualStrings("/tmp/other", compactHomePath("/tmp/other", "/home/me", &compact_buf));

    var model = Model{};
    model.settings_page = .skills;
    applyStdoutPaths(&model, "/home/me/.agents/skills/demo/SKILL.md\n/home/me/.cursor/skills/demo/SKILL.md\n/home/me/.fx/skills/other/SKILL.md\n");
    try testing.expectEqual(@as(u32, 3), cachedCount(&model));
    {
        const rows = model.skill_rows(arena);
        try testing.expectEqual(@as(usize, 3), rows.len);
        try testing.expect(rows[0].is_header);
        try testing.expectEqual(skill_header_id_user, rows[0].id);
        try testing.expectEqualStrings("2", rows[0].count);
        try testing.expectEqualStrings("demo", rows[1].name);
        try testing.expectEqualStrings("/home/me/.agents/skills/demo/SKILL.md", rows[1].path);
        try testing.expectEqual(skillId(0), rows[1].id);
        try testing.expectEqualStrings("other", rows[2].name);
    }

    selectSkill(&model, skillId(0));
    try testing.expect(!model.has_skill_duplicate_badge());
    try testing.expectEqualStrings("", model.skill_duplicate_badge(arena));
    {
        const locs = model.skill_location_rows(arena);
        try testing.expectEqual(@as(usize, 2), locs.len);
        try testing.expectEqualStrings(source_shared, locs[0].label);
        try testing.expect(std.mem.endsWith(u8, locs[0].path, "/.agents/skills/demo") or std.mem.endsWith(u8, locs[0].path, ".agents/skills/demo"));
        try testing.expectEqualStrings("Cursor", locs[1].label);
        try testing.expect(std.mem.endsWith(u8, locs[1].path, "/.cursor/skills/demo") or std.mem.endsWith(u8, locs[1].path, ".cursor/skills/demo"));
    }

    model.draft_buffer.set("$");
    {
        const rows = model.skill_insert_rows(arena);
        try testing.expectEqual(@as(usize, 3), rows.len);
        try testing.expect(!rows[0].is_header);
        try testing.expect(!rows[1].is_header);
        try testing.expect(!rows[2].is_header);
        try testing.expectEqualStrings("demo", rows[0].name);
        try testing.expectEqualStrings("/home/me/.agents/skills/demo/SKILL.md", rows[0].path);
        try testing.expectEqualStrings("demo", rows[1].name);
        try testing.expectEqualStrings("/home/me/.cursor/skills/demo/SKILL.md", rows[1].path);
        try testing.expectEqualStrings("other", rows[2].name);
    }
}

test "source filter All skills; claude hides groups with no Claude install; any-install-in-group passes; insert stays unfiltered" {
    const testing = std.testing;
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const root = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-skills-source-filter", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(testing.io, root);

    var fx = Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = testing.io;
    model.setLastProjectPath(root);
    model.settings_page = .skills;
    applyStdoutPaths(&model, "/home/me/.agents/skills/demo/SKILL.md\n/home/me/.claude/skills/demo/SKILL.md\n/home/me/.fx/skills/other/SKILL.md\n/home/me/.codex/skills/solo/SKILL.md\n");
    try testing.expectEqual(@as(u32, 4), cachedCount(&model));
    try testing.expectEqualStrings(filter_all, sourceFilterLabel(&model));
    try testing.expect(groupedSkillHasSource(&model, 0, .shared));
    try testing.expect(groupedSkillHasSource(&model, 0, .claude));
    try testing.expect(!groupedSkillHasSource(&model, 0, .fx));
    try testing.expect(groupedSkillHasSource(&model, 2, .fx));
    try testing.expect(!groupedSkillHasSource(&model, 2, .claude));
    {
        const rows = model.skill_rows(arena);
        try testing.expectEqual(@as(usize, 4), rows.len);
        try testing.expect(rows[0].is_header);
        try testing.expectEqualStrings("3", rows[0].count);
        try testing.expectEqualStrings("demo", rows[1].name);
        try testing.expectEqualStrings("other", rows[2].name);
        try testing.expectEqualStrings("solo", rows[3].name);
    }
    try testing.expectEqualStrings("4 skills", countCaption(&model, arena));

    const picker = sourcePickerRows(&model, arena);
    try testing.expectEqual(@as(usize, 1 + source_filter_kinds.len), picker.len);
    try testing.expectEqualStrings(source_filter_all_id, picker[0].id);
    try testing.expectEqualStrings(filter_all, picker[0].label);
    try testing.expect(picker[0].selected);
    try testing.expectEqualStrings("shared", picker[1].id);
    try testing.expectEqualStrings("Shared · 1", picker[1].label);
    try testing.expect(!picker[1].selected);
    try testing.expectEqualStrings("claude", picker[2].id);
    try testing.expectEqualStrings("Claude · 1", picker[2].label);
    try testing.expectEqualStrings("codex", picker[3].id);
    try testing.expectEqualStrings("Codex · 1", picker[3].label);
    try testing.expectEqualStrings("cursor", picker[4].id);
    try testing.expectEqualStrings("Cursor", picker[4].label);
    try testing.expectEqualStrings("fx", picker[5].id);
    try testing.expectEqualStrings("fx · 1", picker[5].label);
    try testing.expectEqualStrings("opencode", picker[6].id);
    try testing.expectEqualStrings("OpenCode", picker[6].label);

    model.skills_source_picker_open = true;
    pickSourceFilter(&model, "claude");
    try testing.expect(!model.skills_source_picker_open);
    try testing.expectEqual(SkillSourceKind.claude, model.skills_source_filter.?);
    try testing.expectEqualStrings("Claude", sourceFilterLabel(&model));
    {
        const rows = model.skill_rows(arena);
        try testing.expectEqual(@as(usize, 2), rows.len);
        try testing.expect(rows[0].is_header);
        try testing.expectEqualStrings("1", rows[0].count);
        try testing.expectEqualStrings("demo", rows[1].name);
        try testing.expectEqual(skillId(0), rows[1].id);
    }
    try testing.expectEqualStrings("", emptyHint(&model));
    try testing.expectEqualStrings("1 of 4 shown", countCaption(&model, arena));
    try testing.expect(hasCountCaption(&model));

    model.language_preference = .simplified_chinese;
    try testing.expectEqualStrings("显示 1 / 4 个", countCaption(&model, arena));
    try testing.expectEqualStrings("Claude", sourceFilterLabel(&model));
    model.skills_source_filter = null;
    try testing.expectEqualStrings("全部技能", sourceFilterLabel(&model));
    model.skills_source_filter = .claude;
    model.language_preference = .japanese;
    try testing.expectEqualStrings("4 件中 1 件を表示", countCaption(&model, arena));
    try testing.expectEqualStrings("Claude", sourceFilterLabel(&model));
    model.skills_source_filter = null;
    try testing.expectEqualStrings("すべてのスキル", sourceFilterLabel(&model));
    model.language_preference = .english;
    model.skills_source_filter = .claude;

    model.draft_buffer.set("$");
    {
        const rows = model.skill_insert_rows(arena);
        try testing.expectEqual(@as(usize, 4), rows.len);
        try testing.expectEqualStrings("demo", rows[0].name);
        try testing.expectEqualStrings("/home/me/.agents/skills/demo/SKILL.md", rows[0].path);
        try testing.expectEqualStrings("demo", rows[1].name);
        try testing.expectEqualStrings("/home/me/.claude/skills/demo/SKILL.md", rows[1].path);
        try testing.expectEqualStrings("other", rows[2].name);
        try testing.expectEqualStrings("solo", rows[3].name);
    }

    pickSourceFilter(&model, "pi");
    try testing.expectEqual(SkillSourceKind.pi, model.skills_source_filter.?);
    try testing.expectEqualStrings("No skills match your search", emptyHint(&model));
    try testing.expect(!hasCountCaption(&model));
    try testing.expectEqualStrings("", countCaption(&model, arena));
    try testing.expectEqual(@as(usize, 0), model.skill_rows(arena).len);

    model.skills_source_picker_open = true;
    pickSourceFilter(&model, "all");
    try testing.expect(!model.skills_source_picker_open);
    try testing.expectEqual(@as(?SkillSourceKind, null), model.skills_source_filter);
    try testing.expectEqualStrings(filter_all, sourceFilterLabel(&model));
    try testing.expectEqual(@as(usize, 4), model.skill_rows(arena).len);

    model.skills_source_filter = .codex;
    model.skills_source_picker_open = true;
    leavePage(&model, &fx);
    try testing.expect(!model.skills_source_picker_open);
    try testing.expectEqual(SkillSourceKind.codex, model.skills_source_filter.?);
    try testing.expectEqual(@as(u32, 4), cachedCount(&model));

    model.skills_source_picker_open = true;
    close(&model, &fx);
    try testing.expect(!model.skills_source_picker_open);
    try testing.expectEqual(@as(?SkillSourceKind, null), model.skills_source_filter);
    try testing.expectEqual(@as(u32, 0), cachedCount(&model));
}

test "skill_rows same name project and user stay two rows; duplicate badge EN/zh/ja; single Location" {
    const testing = std.testing;
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const root = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-skills-dup", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(testing.io, root);

    var model = Model{};
    model.store_io = testing.io;
    model.setLastProjectPath(root);
    model.settings_page = .skills;
    applyStdoutPaths(&model, ".cursor/skills/demo/SKILL.md\n/home/me/.agents/skills/demo/SKILL.md\n.cursor/skills/solo/SKILL.md\n");
    try testing.expectEqual(@as(u32, 3), cachedCount(&model));
    {
        const rows = model.skill_rows(arena);
        try testing.expectEqual(@as(usize, 5), rows.len);
        try testing.expect(rows[0].is_header);
        try testing.expectEqual(skill_header_id_project, rows[0].id);
        try testing.expectEqualStrings("2", rows[0].count);
        try testing.expectEqualStrings("demo", rows[1].name);
        try testing.expectEqualStrings("solo", rows[2].name);
        try testing.expect(rows[3].is_header);
        try testing.expectEqual(skill_header_id_user, rows[3].id);
        try testing.expectEqualStrings("1", rows[3].count);
        try testing.expectEqualStrings("demo", rows[4].name);
    }

    selectSkill(&model, skillId(0));
    try testing.expect(model.has_skill_duplicate_badge());
    try testing.expectEqualStrings(duplicate_one, model.skill_duplicate_badge(arena));
    {
        const locs = model.skill_location_rows(arena);
        try testing.expectEqual(@as(usize, 1), locs.len);
        try testing.expectEqualStrings(detail_location, locs[0].label);
    }
    try testing.expectEqualStrings(".cursor/skills/demo/SKILL.md", model.skill_location(arena));

    selectSkill(&model, skillId(1));
    try testing.expect(model.has_skill_duplicate_badge());
    try testing.expectEqualStrings(duplicate_one, model.skill_duplicate_badge(arena));
    {
        const locs = model.skill_location_rows(arena);
        try testing.expectEqual(@as(usize, 1), locs.len);
        try testing.expectEqualStrings(detail_location, locs[0].label);
    }

    selectSkill(&model, skillId(2));
    try testing.expect(!model.has_skill_duplicate_badge());
    try testing.expectEqualStrings("", model.skill_duplicate_badge(arena));
    {
        const locs = model.skill_location_rows(arena);
        try testing.expectEqual(@as(usize, 1), locs.len);
        try testing.expectEqualStrings(detail_location, locs[0].label);
    }

    model.language_preference = .simplified_chinese;
    selectSkill(&model, skillId(0));
    try testing.expectEqualStrings("另有 1 处同名技能 — 更具体的一份生效", model.skill_duplicate_badge(arena));
    model.language_preference = .japanese;
    try testing.expectEqualStrings(
        "同名のスキルが他の 1 か所にもあります — 最も限定的な場所にあるスキルが優先されます",
        model.skill_duplicate_badge(arena),
    );
    model.language_preference = .english;

    model.draft_buffer.set("$");
    {
        const rows = model.skill_insert_rows(arena);
        try testing.expectEqual(@as(usize, 3), rows.len);
        try testing.expect(!rows[0].is_header);
        try testing.expectEqualStrings("demo", rows[0].name);
        try testing.expectEqualStrings("demo", rows[1].name);
        try testing.expectEqualStrings("solo", rows[2].name);
    }
}

test "selected-detail header name plus sources · scope caption; project vs user; multi-source join" {
    const testing = std.testing;
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    try testing.expectEqualStrings("available in every project", scope_user_detail);
    try testing.expectEqualStrings("in %{project}", scope_in_project);
    try testing.expectEqualStrings("available in every project", i18n.skillsScopeChromeFor(.english, "").scope_user_detail);
    try testing.expectEqualStrings("在所有项目中可用", i18n.skillsScopeChromeFor(.simplified_chinese, "").scope_user_detail);
    try testing.expectEqualStrings("すべてのプロジェクトで利用可能", i18n.skillsScopeChromeFor(.japanese, "").scope_user_detail);
    try testing.expectEqualStrings("in %{project}", i18n.skillsScopeChromeFor(.english, "").scope_in_project);
    try testing.expectEqualStrings("位于 %{project}", i18n.skillsScopeChromeFor(.simplified_chinese, "").scope_in_project);
    try testing.expectEqualStrings("%{project} 内", i18n.skillsScopeChromeFor(.japanese, "").scope_in_project);

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const root = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-skills-scope", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(testing.io, root);

    var model = Model{};
    model.store_io = testing.io;
    model.setLastProjectPath(root);
    writeFixed(&model.skill_probe_path_storage, &model.skill_probe_path_len, root);
    model.settings_page = .skills;
    try testing.expectEqualStrings("", model.skill_name());
    try testing.expect(!model.has_skill_scope_caption());
    try testing.expectEqualStrings("", model.skill_scope_caption(arena));
    try testing.expect(!model.has_skill_disabled_badge());

    applyStdoutPaths(&model,
        ".cursor/skills/demo/SKILL.md\n/home/me/.agents/skills/demo/SKILL.md\n/home/me/.cursor/skills/demo/SKILL.md\n/home/me/.config/agents/skills/demo/SKILL.md\n/home/me/.fx/skills/solo/SKILL.md\n/tmp/unrelated/orphan/SKILL.md\n",
    );
    try testing.expectEqual(@as(u32, 6), cachedCount(&model));

    selectSkill(&model, skillId(0));
    try testing.expectEqualStrings("demo", model.skill_name());
    try testing.expectEqualStrings("demo", selectedSkillName(&model));
    try testing.expect(model.has_skill_scope_caption());
    try testing.expectEqualStrings("Cursor · in faku-skills-scope", model.skill_scope_caption(arena));
    try testing.expect(!model.has_skill_disabled_badge());
    try testing.expectEqualStrings("", model.skill_disabled_badge());

    model.language_preference = .simplified_chinese;
    try testing.expectEqualStrings("Cursor · 位于 faku-skills-scope", model.skill_scope_caption(arena));
    model.language_preference = .japanese;
    try testing.expectEqualStrings("Cursor · faku-skills-scope 内", model.skill_scope_caption(arena));
    model.language_preference = .english;

    selectSkill(&model, skillId(1));
    try testing.expectEqualStrings("demo", model.skill_name());
    try testing.expectEqualStrings("Shared · Cursor · available in every project", model.skill_scope_caption(arena));
    {
        var sources_buf: [i18n.skills_scope_caption_max]u8 = undefined;
        try testing.expectEqualStrings("Shared · Cursor", writeSelectedSkillSourcesLabel(&model, &sources_buf));
    }

    model.language_preference = .simplified_chinese;
    try testing.expectEqualStrings("共享 · Cursor · 在所有项目中可用", model.skill_scope_caption(arena));
    model.language_preference = .japanese;
    try testing.expectEqualStrings("共有 · Cursor · すべてのプロジェクトで利用可能", model.skill_scope_caption(arena));
    model.language_preference = .english;

    selectSkill(&model, skillId(4));
    try testing.expectEqualStrings("solo", model.skill_name());
    try testing.expectEqualStrings("fx · available in every project", model.skill_scope_caption(arena));

    selectSkill(&model, skillId(5));
    try testing.expectEqualStrings("orphan", model.skill_name());
    try testing.expectEqualStrings("available in every project", model.skill_scope_caption(arena));
    {
        var sources_buf: [i18n.skills_scope_caption_max]u8 = undefined;
        try testing.expectEqualStrings("", writeSelectedSkillSourcesLabel(&model, &sources_buf));
    }

    selectSkill(&model, skillId(1));
    model.skill_store[1].enabled = false;
    model.skill_store[2].enabled = false;
    model.skill_store[3].enabled = false;
    try testing.expect(model.has_skill_disabled_badge());
    try testing.expectEqualStrings(disabled_badge, model.skill_disabled_badge());
    try testing.expectEqualStrings("Disabled", model.skill_disabled_badge());
    model.language_preference = .simplified_chinese;
    try testing.expectEqualStrings("已禁用", model.skill_disabled_badge());
    model.language_preference = .japanese;
    try testing.expectEqualStrings("無効", model.skill_disabled_badge());
    model.language_preference = .english;

    model.settings_page = .general;
    try testing.expectEqualStrings("", model.skill_name());
    try testing.expect(!model.has_skill_scope_caption());
    try testing.expect(!model.has_skill_disabled_badge());
    try testing.expectEqualStrings("", model.skill_disabled_badge());
}

test "applyCatalog keeps every install; Settings folds; insert stays flat" {
    const testing = std.testing;
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const root = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-skills-catalog-multi", .{tmp.sub_path[0..]});
    try std.Io.Dir.cwd().createDirPath(testing.io, root);

    var model = Model{};
    model.store_io = testing.io;
    model.setLastProjectPath(root);
    writeFixed(&model.skill_probe_path_storage, &model.skill_probe_path_len, root);
    model.settings_page = .skills;
    model.daemon_load_skills_key = 7;
    const line =
        \\{"type":"response","outcome":{"status":"ok","payload":{"type":"skillsCatalog","catalog":{"skills":[{"name":"demo","description":"From catalog.","enabled":true,"installs":[{"dir":"/home/me/.agents/skills/demo","skillFile":"/home/me/.agents/skills/demo/SKILL.md","enabled":true},{"dir":"/home/me/.cursor/skills/demo","skillFile":"/home/me/.cursor/skills/demo/SKILL.md","enabled":true}]}]}}}}
    ;
    applyDaemonLine(&model, .{ .key = 7, .line = line });
    try testing.expectEqual(@as(u32, 2), cachedCount(&model));
    try testing.expectEqualStrings("demo", cachedName(&model, 0));
    try testing.expectEqualStrings("From catalog.", cachedDescription(&model, 0));
    try testing.expectEqualStrings("/home/me/.agents/skills/demo/SKILL.md", cachedPath(&model, 0));
    try testing.expectEqualStrings("/home/me/.cursor/skills/demo/SKILL.md", cachedPath(&model, 1));
    {
        const rows = model.skill_rows(arena);
        try testing.expectEqual(@as(usize, 2), rows.len);
        try testing.expect(rows[0].is_header);
        try testing.expectEqualStrings("1", rows[0].count);
        try testing.expectEqualStrings("demo", rows[1].name);
        try testing.expectEqualStrings("/home/me/.agents/skills/demo/SKILL.md", rows[1].path);
    }
    selectSkill(&model, skillId(0));
    {
        const locs = model.skill_location_rows(arena);
        try testing.expectEqual(@as(usize, 2), locs.len);
        try testing.expectEqualStrings(source_shared, locs[0].label);
        try testing.expectEqualStrings("Cursor", locs[1].label);
    }
    model.draft_buffer.set("$");
    {
        const rows = model.skill_insert_rows(arena);
        try testing.expectEqual(@as(usize, 2), rows.len);
        try testing.expect(!rows[0].is_header);
        try testing.expectEqualStrings("demo", rows[0].name);
        try testing.expectEqualStrings("demo", rows[1].name);
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

fn testFileSize(io: std.Io, path: []const u8) !u64 {
    var file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);
    return (try file.stat(io)).size;
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
    try testing.expect(isSkillHeaderId(skill_header_id_project));
    try testing.expect(isSkillHeaderId(skill_header_id_user));
    try testing.expect(!isSkillHeaderId(skillId(0)));
    try testing.expect(!isSkillHeaderId(skillId(max_skills - 1)));
    try testing.expect(skill_header_id_project > skillId(max_skills - 1));
    try testing.expect(skill_header_id_user != skill_header_id_project);
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
    try testing.expect(scanInFlight(&model));
    const walk = pendingSpawnKey(&fx, model.skill_key) orelse return error.MissingSkillsWalk;
    try testing.expect(isSkillsWalkArgv(walk.argv));
    try testing.expect(!daemon_proxy.isSidecarArgv(walk.argv));
    switch (builtin.os.tag) {
        .windows => {
            try testing.expectEqualStrings(root, walk.argv[5]);
            try testing.expectEqual(windowsWalkArgvLen(model.skill_user_root_count), walk.argv.len);
        },
        else => {
            try testing.expectEqualStrings(root, walk.argv[4]);
            try testing.expectEqual(unixWalkArgvLen(model.skill_user_root_count), walk.argv.len);
        },
    }
    try testing.expect(walk.argv.len <= 16);
    var extra: usize = switch (builtin.os.tag) {
        .windows => windows_walk_argv_base,
        else => unix_walk_argv_base,
    };
    while (extra < walk.argv.len) : (extra += 1) {
        const slot = walk.argv[extra];
        try testing.expect(slot.len > 0);
        const script = switch (builtin.os.tag) {
            .windows => walk.argv[3],
            else => walk.argv[2],
        };
        try testing.expect(std.mem.indexOf(u8, script, slot) == null);
    }
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
    try testing.expectEqualStrings("Moved “trash-me” to the Trash", model.window_status());
    {
        var toast_buf: [i18n.skills_deleted_toast_max]u8 = undefined;
        try testing.expectEqualStrings(
            model.skill_deleted_status("trash-me", &toast_buf),
            model.window_status(),
        );
        try testing.expectEqualStrings(
            i18n.formatSkillsDeletedToast(i18n.skillsDeletedToastChromeFor(.english, ""), "trash-me", &toast_buf),
            model.window_status(),
        );
    }
    try testing.expect(!std.mem.eql(u8, could_not_delete_status, model.window_status()));
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

test "permanent remove success sets deleted toast; fail path stays Could not delete skill" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const root = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-skills-remove-ok", .{tmp.sub_path[0..]});
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
    try testing.expectEqualStrings("trash-me", selectedSkillName(&model));
    armSkillDelete(&model);

    model.skill_remove_key = skills_remove_key_first;
    handleRemoveExit(&model, &fx, .{ .key = skills_remove_key_first, .reason = .exited, .code = 0 });
    try testing.expectEqual(@as(u64, 0), model.skill_remove_key);
    try testing.expectEqual(@as(u32, 0), cachedCount(&model));
    try testing.expectEqualStrings("Moved “trash-me” to the Trash", model.window_status());
    {
        var toast_buf: [i18n.skills_deleted_toast_max]u8 = undefined;
        try testing.expectEqualStrings(
            model.skill_deleted_status("trash-me", &toast_buf),
            model.window_status(),
        );
    }
    try testing.expect(!std.mem.eql(u8, could_not_delete_status, model.window_status()));
    try testing.expect(!model.skill_delete_arming);
    try testing.expectEqual(@as(u32, 0), model.skill_selected_id);

    applyStdoutPaths(&model, "skills/demo/SKILL.md\n");
    selectSkill(&model, 1);
    model.skill_remove_key = skills_remove_key_first + 1;
    handleRemoveExit(&model, &fx, .{ .key = skills_remove_key_first + 1, .reason = .exited, .code = 1 });
    try testing.expectEqualStrings(could_not_delete_status, model.window_status());
    try testing.expectEqualStrings(model.skill_delete_failed_status(), model.window_status());
    try testing.expectEqual(@as(u32, 1), cachedCount(&model));
}

test "deleted toast follows Appearance language on trash ack and remove success" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const root = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-skills-deleted-i18n", .{tmp.sub_path[0..]});
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
    const id = model.addSession("skills deleted i18n", .fx);
    model.selected = id;
    model.sessionById(id).?.setProjectPath(root);
    writeFixed(&model.skill_probe_path_storage, &model.skill_probe_path_len, root);
    applyStdoutPaths(&model, "skills/demo/SKILL.md\n");
    selectSkill(&model, 1);
    armSkillDelete(&model);
    confirmSkillDelete(&model, &fx);
    const sidecar = pendingSpawnKey(&fx, model.daemon_trash_skills_key) orelse return error.MissingTrashSkillsAck;
    const ack_key = sidecar.key;
    applyTrashSkillsLine(&model, .{ .key = ack_key, .line = trash_skills_ack_line });
    handleTrashSkillsExit(&model, &fx, .{ .key = ack_key, .reason = .exited, .code = 0 });
    try testing.expectEqualStrings("Moved “trash-me” to the Trash", model.window_status());

    applyStdoutPaths(&model, "skills/demo/SKILL.md\n");
    selectSkill(&model, 1);
    model.language_preference = .simplified_chinese;
    model.skill_remove_key = skills_remove_key_first;
    handleRemoveExit(&model, &fx, .{ .key = skills_remove_key_first, .reason = .exited, .code = 0 });
    try testing.expectEqualStrings("已将“trash-me”移到废纸篓", model.window_status());
    {
        var toast_buf: [i18n.skills_deleted_toast_max]u8 = undefined;
        try testing.expectEqualStrings(
            i18n.formatSkillsDeletedToast(i18n.skillsDeletedToastChromeFor(.simplified_chinese, ""), "trash-me", &toast_buf),
            model.window_status(),
        );
    }

    applyStdoutPaths(&model, "skills/demo/SKILL.md\n");
    selectSkill(&model, 1);
    model.language_preference = .japanese;
    model.skill_remove_key = skills_remove_key_first + 1;
    handleRemoveExit(&model, &fx, .{ .key = skills_remove_key_first + 1, .reason = .exited, .code = 0 });
    try testing.expectEqualStrings("「trash-me」をゴミ箱に移動しました", model.window_status());

    applyStdoutPaths(&model, "skills/demo/SKILL.md\n");
    selectSkill(&model, 1);
    model.language_preference = .english;
    model.setSystemLocaleId("ja_JP.UTF-8");
    model.skill_remove_key = skills_remove_key_first + 2;
    handleRemoveExit(&model, &fx, .{ .key = skills_remove_key_first + 2, .reason = .exited, .code = 0 });
    try testing.expectEqualStrings("Moved “trash-me” to the Trash", model.window_status());

    applyStdoutPaths(&model, "skills/demo/SKILL.md\n");
    selectSkill(&model, 1);
    model.language_preference = .system;
    model.setSystemLocaleId("zh_CN.UTF-8");
    model.skill_remove_key = skills_remove_key_first + 3;
    handleRemoveExit(&model, &fx, .{ .key = skills_remove_key_first + 3, .reason = .exited, .code = 0 });
    try testing.expectEqualStrings("已将“trash-me”移到废纸篓", model.window_status());

    applyStdoutPaths(&model, "skills/demo/SKILL.md\n");
    selectSkill(&model, 1);
    model.setSystemLocaleId("ja_JP.UTF-8");
    model.skill_remove_key = skills_remove_key_first + 4;
    handleRemoveExit(&model, &fx, .{ .key = skills_remove_key_first + 4, .reason = .exited, .code = 0 });
    try testing.expectEqualStrings("「trash-me」をゴミ箱に移動しました", model.window_status());
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
