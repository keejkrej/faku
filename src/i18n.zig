//! Settings chrome locale: LanguagePreference, System env resolve, labels.
//!
//! Native has no locale / NSLocale API this cut. System follows process
//! `LC_ALL`, else `LC_MESSAGES`, else `LANG` (non-macOS Waku path), copied
//! at boot onto the model. Settings chrome strings, first-cut sidebar
//! date-bucket titles, first-cut sidebar New Task / Search / folder
//! chrome, session context-menu Rename / Remove, and the palette
//! Collapse all folders command (same `Sidebar.collapse_all_folders`
//! string as the sidebar button) live here so `main.zig` does not
//! grow. Composer Ask / Full access stay English. Not rust_i18n, not
//! YAML catalogs, not full-app translation, not tz-aware grouping.

const std = @import("std");

/// Settings → Appearance chrome language. Default System. Missing /
/// unknown persist strings load as System. Explicit chips are
/// autonyms (English / 简体中文 / 日本語) in every locale.
pub const LanguagePreference = enum {
    system,
    english,
    simplified_chinese,
    japanese,

    pub fn persistName(self: LanguagePreference) []const u8 {
        return switch (self) {
            .system => "system",
            .english => "english",
            .simplified_chinese => "simplified-chinese",
            .japanese => "japanese",
        };
    }

    pub fn fromPersist(value: []const u8) LanguagePreference {
        if (std.mem.eql(u8, value, "english")) return .english;
        if (std.mem.eql(u8, value, "simplified-chinese")) return .simplified_chinese;
        if (std.mem.eql(u8, value, "japanese")) return .japanese;
        return .system;
    }
};

pub const english_autonym = "English";
pub const simplified_chinese_autonym = "简体中文";
pub const japanese_autonym = "日本語";

pub const Chrome = struct {
    settings: []const u8,
    general: []const u8,
    appearance: []const u8,
    providers: []const u8,
    skills: []const u8,
    usage: []const u8,
    computer_use: []const u8,
    theme: []const u8,
    light: []const u8,
    dark: []const u8,
    language: []const u8,
    language_description: []const u8,
    system: []const u8,
    os_caption_hc_on_rm_on: []const u8,
    os_caption_hc_on_rm_off: []const u8,
    os_caption_hc_off_rm_on: []const u8,
    os_caption_hc_off_rm_off: []const u8,
};

const chrome_en: Chrome = .{
    .settings = "Settings",
    .general = "General",
    .appearance = "Appearance",
    .providers = "Providers",
    .skills = "Skills",
    .usage = "Usage",
    .computer_use = "Computer Use",
    .theme = "Theme",
    .light = "Light",
    .dark = "Dark",
    .language = "Language",
    .language_description = "Language for Faku chrome. System follows LC_ALL / LC_MESSAGES / LANG.",
    .system = "System",
    .os_caption_hc_on_rm_on = "High contrast on, reduce motion on. These follow the OS.",
    .os_caption_hc_on_rm_off = "High contrast on, reduce motion off. These follow the OS.",
    .os_caption_hc_off_rm_on = "High contrast off, reduce motion on. These follow the OS.",
    .os_caption_hc_off_rm_off = "High contrast off, reduce motion off. These follow the OS.",
};

const chrome_zh_cn: Chrome = .{
    .settings = "设置",
    .general = "通用",
    .appearance = "外观",
    .providers = "提供商",
    .skills = "技能",
    .usage = "用量",
    .computer_use = "电脑使用",
    .theme = "主题",
    .light = "浅色",
    .dark = "深色",
    .language = "语言",
    .language_description = "Faku 界面语言。系统跟随 LC_ALL / LC_MESSAGES / LANG。",
    .system = "系统",
    .os_caption_hc_on_rm_on = "高对比度开，减弱动态效果开。这些跟随操作系统。",
    .os_caption_hc_on_rm_off = "高对比度开，减弱动态效果关。这些跟随操作系统。",
    .os_caption_hc_off_rm_on = "高对比度关，减弱动态效果开。这些跟随操作系统。",
    .os_caption_hc_off_rm_off = "高对比度关，减弱动态效果关。这些跟随操作系统。",
};

const chrome_ja: Chrome = .{
    .settings = "設定",
    .general = "一般",
    .appearance = "外観",
    .providers = "プロバイダー",
    .skills = "スキル",
    .usage = "使用量",
    .computer_use = "コンピュータ使用",
    .theme = "テーマ",
    .light = "ライト",
    .dark = "ダーク",
    .language = "言語",
    .language_description = "Faku の画面言語です。システムは LC_ALL / LC_MESSAGES / LANG に従います。",
    .system = "システム",
    .os_caption_hc_on_rm_on = "ハイコントラストオン、動きを減らすオン。これらは OS に従います。",
    .os_caption_hc_on_rm_off = "ハイコントラストオン、動きを減らすオフ。これらは OS に従います。",
    .os_caption_hc_off_rm_on = "ハイコントラストオフ、動きを減らすオン。これらは OS に従います。",
    .os_caption_hc_off_rm_off = "ハイコントラストオフ、動きを減らすオフ。これらは OS に従います。",
};

/// First-cut sidebar date-bucket titles plus the static relative-time
/// words that are already string literals. Chrome unassign Today reuses
/// `today`. Numeric `{d}m` / `{d}h` / `{d}d` / `YYYY-MM-DD` stay
/// untranslated. Same resolve path as Chrome.
pub const Dates = struct {
    today: []const u8,
    yesterday: []const u8,
    this_week: []const u8,
    this_month: []const u8,
    this_year: []const u8,
    older: []const u8,
    just_now: []const u8,
};

const dates_en: Dates = .{
    .today = "Today",
    .yesterday = "Yesterday",
    .this_week = "This week",
    .this_month = "This month",
    .this_year = "This year",
    .older = "Older",
    .just_now = "just now",
};

const dates_zh_cn: Dates = .{
    .today = "今日",
    .yesterday = "昨天",
    .this_week = "本周",
    .this_month = "本月",
    .this_year = "今年",
    .older = "更早",
    .just_now = "刚刚",
};

const dates_ja: Dates = .{
    .today = "今日",
    .yesterday = "昨日",
    .this_week = "今週",
    .this_month = "今月",
    .this_year = "今年",
    .older = "以前",
    .just_now = "たった今",
};

/// First-cut high-traffic sidebar chrome. Same resolve path as Chrome /
/// Dates. Search is the sidebar entry and the command-palette overlay
/// placeholder (same wording). New folder is the button label and the
/// folder title-field placeholder; stored catalog titles stay English
/// `New folder` (data, not chrome). Folder context-menu Rename / Delete
/// are chrome (plain Delete, not `delete_folder`). Session context-menu
/// Rename reuses `rename` (same wording). Session Remove is distinct
/// from folder Delete (`remove` vs `delete`); trash a11y is
/// `remove_session` ("Remove session"). Folder-header chevron a11y is
/// `expand_folder` / `collapse_folder` (distinct from
/// `collapse_all_folders`). Palette Collapse all folders reuses
/// `collapse_all_folders`. Composer Ask / Full access stay English.
pub const Sidebar = struct {
    new_task: []const u8,
    search: []const u8,
    new_folder: []const u8,
    collapse_all_folders: []const u8,
    expand_folder: []const u8,
    collapse_folder: []const u8,
    delete_folder: []const u8,
    rename: []const u8,
    delete: []const u8,
    remove: []const u8,
    remove_session: []const u8,
};

const sidebar_en: Sidebar = .{
    .new_task = "New Task",
    .search = "Search",
    .new_folder = "New folder",
    .collapse_all_folders = "Collapse all folders",
    .expand_folder = "Expand folder",
    .collapse_folder = "Collapse folder",
    .delete_folder = "Delete folder",
    .rename = "Rename",
    .delete = "Delete",
    .remove = "Remove",
    .remove_session = "Remove session",
};

const sidebar_zh_cn: Sidebar = .{
    .new_task = "新建任务",
    .search = "搜索",
    .new_folder = "新建文件夹",
    .collapse_all_folders = "折叠所有文件夹",
    .expand_folder = "展开文件夹",
    .collapse_folder = "折叠文件夹",
    .delete_folder = "删除文件夹",
    .rename = "重命名",
    .delete = "删除",
    .remove = "移除",
    .remove_session = "移除会话",
};

const sidebar_ja: Sidebar = .{
    .new_task = "新しいタスク",
    .search = "検索",
    .new_folder = "新しいフォルダ",
    .collapse_all_folders = "すべてのフォルダを折りたたむ",
    .expand_folder = "フォルダを展開",
    .collapse_folder = "フォルダを折りたたむ",
    .delete_folder = "フォルダを削除",
    .rename = "名前を変更",
    .delete = "削除",
    .remove = "取り除く",
    .remove_session = "セッションを取り除く",
};

/// Map a POSIX locale id (or env fragment) onto english / simplified_chinese /
/// japanese. Never returns `.system`. Empty / C / unknown → english.
/// Tests pass an explicit id so they do not depend on the runner's LANG.
pub fn fromLocaleId(id: []const u8) LanguagePreference {
    const before_dot = if (std.mem.indexOfScalar(u8, id, '.')) |dot| id[0..dot] else id;
    if (before_dot.len == 0) return .english;

    var buf: [128]u8 = undefined;
    const n = @min(before_dot.len, buf.len);
    for (before_dot[0..n], 0..) |c, i| {
        buf[i] = if (c == '_') '-' else std.ascii.toLower(c);
    }
    const loc = buf[0..n];

    if (std.mem.eql(u8, loc, "zh-cn") or
        std.mem.eql(u8, loc, "zh-sg") or
        std.mem.startsWith(u8, loc, "zh-hans"))
        return .simplified_chinese;
    if (std.mem.eql(u8, loc, "ja") or std.mem.startsWith(u8, loc, "ja-"))
        return .japanese;
    return .english;
}

/// LC_ALL, else LC_MESSAGES, else LANG, else `"en"`. Empty values are skipped.
/// Native has no locale API; the window copies these process env strings at boot.
pub fn pickSystemLocaleId(lc_all: []const u8, lc_messages: []const u8, lang: []const u8) []const u8 {
    if (lc_all.len > 0) return lc_all;
    if (lc_messages.len > 0) return lc_messages;
    if (lang.len > 0) return lang;
    return "en";
}

/// Resolved chrome locale. `.system` follows `system_locale_id`; explicit
/// preferences ignore it (English stays English even when LANG is ja).
pub fn resolve(preference: LanguagePreference, system_locale_id: []const u8) LanguagePreference {
    if (preference == .system) return fromLocaleId(system_locale_id);
    return preference;
}

pub fn chromeFor(preference: LanguagePreference, system_locale_id: []const u8) Chrome {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => chrome_zh_cn,
        .japanese => chrome_ja,
        .system, .english => chrome_en,
    };
}

/// Sidebar date-bucket titles for the resolved chrome locale. Callers
/// pass Model `language_preference` + `system_locale_id`; this file
/// does not read process env.
pub fn datesFor(preference: LanguagePreference, system_locale_id: []const u8) Dates {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => dates_zh_cn,
        .japanese => dates_ja,
        .system, .english => dates_en,
    };
}

/// Sidebar New Task / Search / folder / session chrome for the resolved
/// locale. Callers pass Model `language_preference` + `system_locale_id`;
/// this file does not read process env.
pub fn sidebarFor(preference: LanguagePreference, system_locale_id: []const u8) Sidebar {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => sidebar_zh_cn,
        .japanese => sidebar_ja,
        .system, .english => sidebar_en,
    };
}

test "LanguagePreference persist names and unknown load as System" {
    const testing = std.testing;
    try testing.expectEqual(LanguagePreference.system, LanguagePreference.fromPersist(""));
    try testing.expectEqual(LanguagePreference.system, LanguagePreference.fromPersist("nope"));
    try testing.expectEqual(LanguagePreference.system, LanguagePreference.fromPersist("system"));
    try testing.expectEqual(LanguagePreference.english, LanguagePreference.fromPersist("english"));
    try testing.expectEqual(LanguagePreference.simplified_chinese, LanguagePreference.fromPersist("simplified-chinese"));
    try testing.expectEqual(LanguagePreference.japanese, LanguagePreference.fromPersist("japanese"));
    try testing.expectEqualStrings("system", LanguagePreference.system.persistName());
    try testing.expectEqualStrings("english", LanguagePreference.english.persistName());
    try testing.expectEqualStrings("simplified-chinese", LanguagePreference.simplified_chinese.persistName());
    try testing.expectEqualStrings("japanese", LanguagePreference.japanese.persistName());
}

test "fromLocaleId maps ja and zh-Hans; C empty and zh-Hant stay english" {
    const testing = std.testing;
    try testing.expectEqual(LanguagePreference.japanese, fromLocaleId("ja"));
    try testing.expectEqual(LanguagePreference.japanese, fromLocaleId("ja_JP"));
    try testing.expectEqual(LanguagePreference.japanese, fromLocaleId("ja-JP"));
    try testing.expectEqual(LanguagePreference.japanese, fromLocaleId("ja_JP.UTF-8"));
    try testing.expectEqual(LanguagePreference.simplified_chinese, fromLocaleId("zh-CN"));
    try testing.expectEqual(LanguagePreference.simplified_chinese, fromLocaleId("zh_SG"));
    try testing.expectEqual(LanguagePreference.simplified_chinese, fromLocaleId("zh-Hans-CN"));
    try testing.expectEqual(LanguagePreference.english, fromLocaleId("zh-Hant-TW"));
    try testing.expectEqual(LanguagePreference.english, fromLocaleId("en"));
    try testing.expectEqual(LanguagePreference.english, fromLocaleId("C"));
    try testing.expectEqual(LanguagePreference.english, fromLocaleId(""));
    try testing.expectEqual(LanguagePreference.english, fromLocaleId("en_US.UTF-8"));
}

test "resolve english ignores a japanese locale id" {
    const testing = std.testing;
    try testing.expectEqual(LanguagePreference.english, resolve(.english, "ja_JP.UTF-8"));
    try testing.expectEqual(LanguagePreference.japanese, resolve(.system, "ja"));
    try testing.expectEqualStrings("LC_ALL", pickSystemLocaleId("LC_ALL", "LC_MESSAGES", "LANG"));
    try testing.expectEqualStrings("LC_MESSAGES", pickSystemLocaleId("", "LC_MESSAGES", "LANG"));
    try testing.expectEqualStrings("LANG", pickSystemLocaleId("", "", "LANG"));
    try testing.expectEqualStrings("en", pickSystemLocaleId("", "", ""));
    try testing.expectEqualStrings("Appearance", chromeFor(.english, "ja").appearance);
    try testing.expectEqualStrings("外观", chromeFor(.simplified_chinese, "").appearance);
    try testing.expectEqualStrings("外観", chromeFor(.japanese, "").appearance);
    try testing.expectEqualStrings("Language", chromeFor(.english, "").language);
    try testing.expectEqualStrings("语言", chromeFor(.simplified_chinese, "").language);
    try testing.expectEqualStrings("言語", chromeFor(.japanese, "").language);
    try testing.expectEqualStrings("Theme", chromeFor(.english, "").theme);
    try testing.expectEqualStrings("主题", chromeFor(.simplified_chinese, "").theme);
    try testing.expectEqualStrings("テーマ", chromeFor(.japanese, "").theme);
    try testing.expectEqualStrings("Appearance", chromeFor(.system, "").appearance);
    try testing.expectEqualStrings("外観", chromeFor(.system, "ja_JP.UTF-8").appearance);
}

test "datesFor english default; zh and ja bucket titles; System follows locale id" {
    const testing = std.testing;
    try testing.expectEqualStrings("Today", datesFor(.english, "ja").today);
    try testing.expectEqualStrings("Yesterday", datesFor(.english, "").yesterday);
    try testing.expectEqualStrings("This week", datesFor(.english, "").this_week);
    try testing.expectEqualStrings("This month", datesFor(.english, "").this_month);
    try testing.expectEqualStrings("This year", datesFor(.english, "").this_year);
    try testing.expectEqualStrings("Older", datesFor(.english, "").older);
    try testing.expectEqualStrings("just now", datesFor(.english, "").just_now);
    try testing.expectEqualStrings("Today", datesFor(.system, "").today);

    try testing.expectEqualStrings("今日", datesFor(.simplified_chinese, "").today);
    try testing.expectEqualStrings("昨天", datesFor(.simplified_chinese, "").yesterday);
    try testing.expectEqualStrings("本周", datesFor(.simplified_chinese, "").this_week);
    try testing.expectEqualStrings("本月", datesFor(.simplified_chinese, "").this_month);
    try testing.expectEqualStrings("今年", datesFor(.simplified_chinese, "").this_year);
    try testing.expectEqualStrings("更早", datesFor(.simplified_chinese, "").older);
    try testing.expectEqualStrings("刚刚", datesFor(.simplified_chinese, "").just_now);

    try testing.expectEqualStrings("今日", datesFor(.japanese, "").today);
    try testing.expectEqualStrings("昨日", datesFor(.japanese, "").yesterday);
    try testing.expectEqualStrings("今週", datesFor(.japanese, "").this_week);
    try testing.expectEqualStrings("今月", datesFor(.japanese, "").this_month);
    try testing.expectEqualStrings("今年", datesFor(.japanese, "").this_year);
    try testing.expectEqualStrings("以前", datesFor(.japanese, "").older);
    try testing.expectEqualStrings("たった今", datesFor(.japanese, "").just_now);

    try testing.expectEqualStrings("今日", datesFor(.system, "zh_CN.UTF-8").today);
    try testing.expectEqualStrings("昨日", datesFor(.system, "ja_JP.UTF-8").yesterday);
    try testing.expectEqualStrings("Today", datesFor(.english, "ja_JP.UTF-8").today);
}

test "sidebarFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("New Task", sidebarFor(.english, "ja").new_task);
    try testing.expectEqualStrings("Search", sidebarFor(.english, "").search);
    try testing.expectEqualStrings("New folder", sidebarFor(.english, "").new_folder);
    try testing.expectEqualStrings("Collapse all folders", sidebarFor(.english, "").collapse_all_folders);
    try testing.expectEqualStrings("Expand folder", sidebarFor(.english, "").expand_folder);
    try testing.expectEqualStrings("Collapse folder", sidebarFor(.english, "").collapse_folder);
    try testing.expectEqualStrings("Delete folder", sidebarFor(.english, "").delete_folder);
    try testing.expectEqualStrings("Rename", sidebarFor(.english, "").rename);
    try testing.expectEqualStrings("Delete", sidebarFor(.english, "").delete);
    try testing.expectEqualStrings("Remove", sidebarFor(.english, "").remove);
    try testing.expectEqualStrings("Remove session", sidebarFor(.english, "").remove_session);
    try testing.expectEqualStrings("New Task", sidebarFor(.system, "").new_task);

    try testing.expectEqualStrings("新建任务", sidebarFor(.simplified_chinese, "").new_task);
    try testing.expectEqualStrings("搜索", sidebarFor(.simplified_chinese, "").search);
    try testing.expectEqualStrings("新建文件夹", sidebarFor(.simplified_chinese, "").new_folder);
    try testing.expectEqualStrings("折叠所有文件夹", sidebarFor(.simplified_chinese, "").collapse_all_folders);
    try testing.expectEqualStrings("展开文件夹", sidebarFor(.simplified_chinese, "").expand_folder);
    try testing.expectEqualStrings("折叠文件夹", sidebarFor(.simplified_chinese, "").collapse_folder);
    try testing.expectEqualStrings("删除文件夹", sidebarFor(.simplified_chinese, "").delete_folder);
    try testing.expectEqualStrings("重命名", sidebarFor(.simplified_chinese, "").rename);
    try testing.expectEqualStrings("删除", sidebarFor(.simplified_chinese, "").delete);
    try testing.expectEqualStrings("移除", sidebarFor(.simplified_chinese, "").remove);
    try testing.expectEqualStrings("移除会话", sidebarFor(.simplified_chinese, "").remove_session);

    try testing.expectEqualStrings("新しいタスク", sidebarFor(.japanese, "").new_task);
    try testing.expectEqualStrings("検索", sidebarFor(.japanese, "").search);
    try testing.expectEqualStrings("新しいフォルダ", sidebarFor(.japanese, "").new_folder);
    try testing.expectEqualStrings("すべてのフォルダを折りたたむ", sidebarFor(.japanese, "").collapse_all_folders);
    try testing.expectEqualStrings("フォルダを展開", sidebarFor(.japanese, "").expand_folder);
    try testing.expectEqualStrings("フォルダを折りたたむ", sidebarFor(.japanese, "").collapse_folder);
    try testing.expectEqualStrings("フォルダを削除", sidebarFor(.japanese, "").delete_folder);
    try testing.expectEqualStrings("名前を変更", sidebarFor(.japanese, "").rename);
    try testing.expectEqualStrings("削除", sidebarFor(.japanese, "").delete);
    try testing.expectEqualStrings("取り除く", sidebarFor(.japanese, "").remove);
    try testing.expectEqualStrings("セッションを取り除く", sidebarFor(.japanese, "").remove_session);

    try testing.expectEqualStrings("新建任务", sidebarFor(.system, "zh_CN.UTF-8").new_task);
    try testing.expectEqualStrings("検索", sidebarFor(.system, "ja_JP.UTF-8").search);
    try testing.expectEqualStrings("New Task", sidebarFor(.english, "ja_JP.UTF-8").new_task);
    try testing.expectEqualStrings("Search", sidebarFor(.english, "ja_JP.UTF-8").search);
    try testing.expectEqualStrings("New folder", sidebarFor(.english, "zh_CN.UTF-8").new_folder);
    try testing.expectEqualStrings("Rename", sidebarFor(.english, "ja_JP.UTF-8").rename);
    try testing.expectEqualStrings("Delete", sidebarFor(.english, "zh_CN.UTF-8").delete);
    try testing.expectEqualStrings("Remove", sidebarFor(.english, "zh_CN.UTF-8").remove);
    try testing.expectEqualStrings("Remove session", sidebarFor(.english, "ja_JP.UTF-8").remove_session);
    try testing.expectEqualStrings("Expand folder", sidebarFor(.english, "zh_CN.UTF-8").expand_folder);
    try testing.expectEqualStrings("Collapse folder", sidebarFor(.english, "ja_JP.UTF-8").collapse_folder);
}
