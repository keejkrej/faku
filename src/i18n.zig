//! Settings chrome locale: LanguagePreference, System env resolve, labels.
//!
//! Native has no locale / NSLocale API this cut. System follows process
//! `LC_ALL`, else `LC_MESSAGES`, else `LANG` (non-macOS Waku path), copied
//! at boot onto the model. Settings chrome strings live here so
//! `main.zig` does not grow. Not rust_i18n, not YAML catalogs, not
//! full-app translation.

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
