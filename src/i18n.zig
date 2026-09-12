//! Settings chrome locale: LanguagePreference, System env resolve, labels.
//!
//! Native has no locale / NSLocale API this cut. System follows process
//! `LC_ALL`, else `LC_MESSAGES`, else `LANG` (non-macOS Waku path), copied
//! at boot onto the model. Settings chrome strings, first-cut sidebar
//! date-bucket titles, first-cut sidebar New Task / Search / folder
//! chrome, session context-menu Rename / Remove, palette action
//! display labels (same `Sidebar` / `Chrome` strings for New Task /
//! Settings / Collapse all folders; remaining command names in
//! `Palette`), palette overlay section headers and empty-state
//! lines (`PaletteChrome`), composer / Settings General Ask / Auto /
//! Full access (same `Access` strings), first-cut composer effort chip /
//! Settings General effort labels (same `Effort` strings),
//! first-cut composer interaction chip / Settings General Build /
//! Plan (same `Interaction` strings), first-cut right-panel tab
//! button labels (same `RightPanelTabs` strings; EN Diff tab reads
//! Review), first-cut right-panel Diff filter + Files/Background
//! empty-state chrome (including Files empty secondary Open a
//! project to browse its files / Loading files…) plus Browser
//! start page / Open in browser / Open in Terminal (same
//! `RightPanelChrome` strings), and first-cut
//! composer project-row Pick folder / Reveal folder / Open in Editor /
//! Copy path (same `ComposerProjectChrome` strings; Open in Terminal
//! reuses `RightPanelChrome.open_in_terminal`), and first-cut Review
//! Diff header title / Cancel / source chips / gap expand
//! Start / End / Both / All (same `ReviewDiffChrome` strings),
//! and first-cut Background row kind /
//! status / stop·dismiss chrome (same `BackgroundChrome` strings;
//! Environment Summary + right-panel Background body), and
//! first-cut Environment info-button a11y + dropdown-menu header /
//! menu-item chrome (same `EnvironmentChrome` strings), and first-cut
//! Settings Skills filter placeholder plus Settings Usage Projects
//! search-field placeholder + a11y label and empty-state No project
//! usage (same `FilterChrome` strings), and first-cut Files
//! right-panel file-preview toolbar / find-replace / discard /
//! truncated·binary chrome (same `FilePreviewChrome` strings) live
//! here so `main.zig` does not grow. Palette ids / `PaletteAction` /
//! keywords stay English.
//! Wire `access_mode` ids stay `ask` / `auto` / `fullAccess`. Wire
//! `reasoning_effort` ids stay `auto` / `none` / `minimal` / `low` /
//! `medium` / `high` / `xhigh` / `max`. Wire `interaction_mode` ids
//! stay `build` / `plan`. Wire `right_panel_tab` ids stay `files` /
//! `diff` / `browser` / `terminal` / `background`. Diff filter
//! `on-input` and filter text stay English. Open in browser / Open
//! in Terminal `on-press` stay `open_url` / `open_terminal`. Composer
//! Pick folder / Reveal folder / Open in Editor / Copy path
//! `on-press` stay `pick_folder` / `reveal_folder` / `open_editor` /
//! `copy_project_path`. Review Diff Cancel / source chips / gap
//! expand `on-press` stay `close_review_diff` /
//! `set_review_diff_source_*` / `expand_review_diff_gap_*`. Background
//! Stop / Dismiss `on-press` stay `environment_stop_background:*` /
//! `open_background_work:*`. Environment info / menu `on-press`
//! stay `toggle_environment_summary` / `close_environment_summary` /
//! `environment_commit_or_push` / `environment_compare` /
//! `environment_copy_task_id` / `environment_copy_agent_thread_id` /
//! `environment_dismiss_settled_background`. Skills / Usage Projects
//! filter `on-input` stay `skills_filter_edit` /
//! `usage_project_filter_edit`; filter text stays English (user-typed).
//! File-preview toolbar `on-press` / `on-input` stay English
//! (`file_preview_save` / `close_right_panel_file_preview` /
//! `toggle_file_preview_find_replace` / `file_preview_find_edit` /
//! …). Aa / Ab / .* glyphs stay. Path text and body content stay data.
//! Not rust_i18n, not YAML catalogs, not full-app translation, not
//! tz-aware grouping.

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
/// `collapse_all_folders`. Palette New Task / Settings reuse
/// `new_task` / `Chrome.settings`. Remaining palette action labels
/// live in `Palette` (same resolve path). Composer Ask / Auto /
/// Full access live in `Access` (same resolve path). Composer
/// effort chip / Settings General effort labels live in `Effort`
/// (same resolve path). Composer Build / Plan live in `Interaction`
/// (same resolve path).
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

/// Composer chip, access picker rows, and Settings General Ask / Auto /
/// Full access buttons. Same resolve path as Sidebar. Wire `access_mode`
/// ids stay `ask` / `auto` / `fullAccess` (plus aliases `autoAcceptEdits`
/// / `yolo`); only the chrome label translates. English matches
/// `composer.accessLabel` / `access_chip_options`.
pub const Access = struct {
    ask: []const u8,
    auto: []const u8,
    full_access: []const u8,

    /// `id` is a chip option id (`ask` / `auto` / `fullAccess`), not a
    /// persisted alias. Unknown ids fall through to Full access.
    pub fn labelForId(self: Access, id: []const u8) []const u8 {
        if (std.mem.eql(u8, id, "ask")) return self.ask;
        if (std.mem.eql(u8, id, "auto")) return self.auto;
        return self.full_access;
    }
};

const access_en: Access = .{
    .ask = "Ask",
    .auto = "Auto",
    .full_access = "Full access",
};

const access_zh_cn: Access = .{
    .ask = "询问",
    .auto = "自动",
    .full_access = "完全访问",
};

const access_ja: Access = .{
    .ask = "確認",
    .auto = "自動",
    .full_access = "フルアクセス",
};

/// Composer effort chip, effort picker rows, and Settings General effort
/// select. Same resolve path as Access. Wire `reasoning_effort` ids stay
/// `auto` / `none` / `minimal` / `low` / `medium` / `high` / `xhigh` /
/// `max`; only the chrome label translates. English matches
/// `composer.effortLabel` / `effort_chip_options`.
pub const Effort = struct {
    auto: []const u8,
    none: []const u8,
    minimal: []const u8,
    low: []const u8,
    medium: []const u8,
    high: []const u8,
    extra_high: []const u8,
    max: []const u8,

    /// `id` is a chip option id (`auto` / `none` / `minimal` / `low` /
    /// `medium` / `high` / `xhigh` / `max`). Unknown ids fall through to Auto.
    pub fn labelForId(self: Effort, id: []const u8) []const u8 {
        if (std.mem.eql(u8, id, "none")) return self.none;
        if (std.mem.eql(u8, id, "minimal")) return self.minimal;
        if (std.mem.eql(u8, id, "low")) return self.low;
        if (std.mem.eql(u8, id, "medium")) return self.medium;
        if (std.mem.eql(u8, id, "high")) return self.high;
        if (std.mem.eql(u8, id, "xhigh")) return self.extra_high;
        if (std.mem.eql(u8, id, "max")) return self.max;
        return self.auto;
    }
};

const effort_en: Effort = .{
    .auto = "Auto",
    .none = "None",
    .minimal = "Minimal",
    .low = "Low",
    .medium = "Medium",
    .high = "High",
    .extra_high = "Extra high",
    .max = "Max",
};

const effort_zh_cn: Effort = .{
    .auto = "自动",
    .none = "无",
    .minimal = "最低",
    .low = "低",
    .medium = "中",
    .high = "高",
    .extra_high = "极高",
    .max = "最大",
};

const effort_ja: Effort = .{
    .auto = "自動",
    .none = "なし",
    .minimal = "最小",
    .low = "低",
    .medium = "中",
    .high = "高",
    .extra_high = "非常に高い",
    .max = "最大",
};

/// Composer interaction chip and Settings General Build / Plan buttons.
/// Same resolve path as Effort. Wire `interaction_mode` ids stay
/// `build` / `plan`; only the chrome label translates. English matches
/// the former hardcoded composer chip / Settings General buttons.
pub const Interaction = struct {
    build: []const u8,
    plan: []const u8,

    /// `id` is a wire id (`build` / `plan`). Unknown / empty fall through to Build.
    pub fn labelForId(self: Interaction, id: []const u8) []const u8 {
        if (std.mem.eql(u8, id, "plan")) return self.plan;
        return self.build;
    }
};

const interaction_en: Interaction = .{
    .build = "Build",
    .plan = "Plan",
};

const interaction_zh_cn: Interaction = .{
    .build = "构建",
    .plan = "计划",
};

const interaction_ja: Interaction = .{
    .build = "ビルド",
    .plan = "プラン",
};

/// Command-palette action display labels for the resolved locale.
/// Same resolve path as Interaction. New Task / Settings / Collapse
/// all folders reuse `Sidebar` / `Chrome` (not duplicated here).
/// Overlay Suggested / Commands / Tasks headers and empty-state
/// lines live in `PaletteChrome` (not duplicated here). Palette ids
/// / `PaletteAction` / keywords stay English; matching still checks
/// the English spec label, the localized label, and English keywords.
/// Expand / Collapse sidebar are chrome a11y
/// (`sidebar_toggle_label`), not the palette "Toggle sidebar"
/// command name.
pub const Palette = struct {
    focus_composer: []const u8,
    toggle_sidebar: []const u8,
    find_in_transcript: []const u8,
    minimize: []const u8,
    maximize: []const u8,
    copy_session_id: []const u8,
    copy_provider_session_id: []const u8,
    reveal_project_folder: []const u8,
    open_project_in_terminal: []const u8,
    open_project_in_editor: []const u8,
    copy_project_path: []const u8,
    show_right_panel: []const u8,
    hide_right_panel: []const u8,
    show_browser_tab: []const u8,
    show_terminal_tab: []const u8,
    expand_sidebar: []const u8,
    collapse_sidebar: []const u8,
};

const palette_en: Palette = .{
    .focus_composer = "Focus composer",
    .toggle_sidebar = "Toggle sidebar",
    .find_in_transcript = "Find in transcript",
    .minimize = "Minimize",
    .maximize = "Maximize",
    .copy_session_id = "Copy session id",
    .copy_provider_session_id = "Copy provider session id",
    .reveal_project_folder = "Reveal project folder",
    .open_project_in_terminal = "Open project in Terminal",
    .open_project_in_editor = "Open project in Editor",
    .copy_project_path = "Copy project path",
    .show_right_panel = "Show right panel",
    .hide_right_panel = "Hide right panel",
    .show_browser_tab = "Show Browser tab",
    .show_terminal_tab = "Show Terminal tab",
    .expand_sidebar = "Expand sidebar",
    .collapse_sidebar = "Collapse sidebar",
};

const palette_zh_cn: Palette = .{
    .focus_composer = "聚焦输入框",
    .toggle_sidebar = "切换侧边栏",
    .find_in_transcript = "在记录中查找",
    .minimize = "最小化",
    .maximize = "最大化",
    .copy_session_id = "复制会话 ID",
    .copy_provider_session_id = "复制提供商会话 ID",
    .reveal_project_folder = "显示项目文件夹",
    .open_project_in_terminal = "在终端中打开项目",
    .open_project_in_editor = "在编辑器中打开项目",
    .copy_project_path = "复制项目路径",
    .show_right_panel = "显示右侧面板",
    .hide_right_panel = "隐藏右侧面板",
    .show_browser_tab = "显示浏览器标签页",
    .show_terminal_tab = "显示终端标签页",
    .expand_sidebar = "展开侧边栏",
    .collapse_sidebar = "折叠侧边栏",
};

const palette_ja: Palette = .{
    .focus_composer = "入力欄にフォーカス",
    .toggle_sidebar = "サイドバーを切り替え",
    .find_in_transcript = "記録内を検索",
    .minimize = "最小化",
    .maximize = "最大化",
    .copy_session_id = "セッション ID をコピー",
    .copy_provider_session_id = "プロバイダーセッション ID をコピー",
    .reveal_project_folder = "プロジェクトフォルダを表示",
    .open_project_in_terminal = "ターミナルでプロジェクトを開く",
    .open_project_in_editor = "エディターでプロジェクトを開く",
    .copy_project_path = "プロジェクトパスをコピー",
    .show_right_panel = "右パネルを表示",
    .hide_right_panel = "右パネルを非表示",
    .show_browser_tab = "ブラウザーのタブを表示",
    .show_terminal_tab = "ターミナルのタブを表示",
    .expand_sidebar = "サイドバーを展開",
    .collapse_sidebar = "サイドバーを折りたたむ",
};

/// Command-palette overlay section headers and empty-state lines.
/// Same resolve path as Palette. Action names stay in `Palette`;
/// ids / `PaletteAction` / keywords stay English. Right-panel tab
/// button labels live in `RightPanelTabs` (not duplicated here).
pub const PaletteChrome = struct {
    suggested: []const u8,
    commands: []const u8,
    tasks: []const u8,
    no_matches: []const u8,
    try_query: []const u8,
};

const palette_chrome_en: PaletteChrome = .{
    .suggested = "Suggested",
    .commands = "Commands",
    .tasks = "Tasks",
    .no_matches = "No matching tasks or commands",
    .try_query = "Try a task title, project, provider, model, or command",
};

const palette_chrome_zh_cn: PaletteChrome = .{
    .suggested = "建议",
    .commands = "命令",
    .tasks = "任务",
    .no_matches = "没有匹配的任务或命令",
    .try_query = "试试任务标题、项目、提供商、模型或命令",
};

const palette_chrome_ja: PaletteChrome = .{
    .suggested = "おすすめ",
    .commands = "コマンド",
    .tasks = "タスク",
    .no_matches = "一致するタスクやコマンドはありません",
    .try_query = "タスク名、プロジェクト、プロバイダー、モデル、コマンドを試す",
};

/// Right-panel tab button labels for the resolved locale. Same resolve
/// path as PaletteChrome. Wire `right_panel_tab` ids stay `files` /
/// `diff` / `browser` / `terminal` / `background`; only the visible
/// label translates. English Diff tab reads Review (Waku
/// `right_panel.diff`), not Diff. Diff filter / Files empty
/// (including empty secondary Open a project to browse its files /
/// Loading files…) / Background empty / Browser start page /
/// Open in browser / Open in Terminal chrome live in
/// `RightPanelChrome`. Background row kind / status / stop·dismiss
/// chrome live in `BackgroundChrome`. Pane `label=` attributes stay
/// English.
pub const RightPanelTabs = struct {
    files: []const u8,
    diff: []const u8,
    browser: []const u8,
    terminal: []const u8,
    background: []const u8,
};

const right_panel_tabs_en: RightPanelTabs = .{
    .files = "Files",
    .diff = "Review",
    .browser = "Browser",
    .terminal = "Terminal",
    .background = "Background",
};

const right_panel_tabs_zh_cn: RightPanelTabs = .{
    .files = "文件",
    .diff = "审阅",
    .browser = "浏览器",
    .terminal = "终端",
    .background = "后台工作",
};

const right_panel_tabs_ja: RightPanelTabs = .{
    .files = "ファイル",
    .diff = "レビュー",
    .browser = "ブラウザ",
    .terminal = "ターミナル",
    .background = "バックグラウンド",
};

/// Right-panel Diff filter placeholder, Files/Background empty-state
/// chrome (including Files empty secondary Open a project to browse
/// its files / Loading files…), and Browser start-page / Open in
/// browser / Open in Terminal labels for the resolved locale. Same
/// resolve path as RightPanelTabs. Wire ids / on-press / filter text
/// stay English; only these visible strings translate. English Diff
/// filter reads "Filter files", not Filter. Composer Open in Terminal
/// reuses `open_in_terminal`. Background empty-state reuses
/// `no_background_work` / `no_output`; row kind / status /
/// stop·dismiss chrome live in `BackgroundChrome`.
pub const RightPanelChrome = struct {
    filter_files: []const u8,
    no_project_open: []const u8,
    open_project_to_browse_files: []const u8,
    loading_files: []const u8,
    no_background_work: []const u8,
    no_output: []const u8,
    browse_the_web: []const u8,
    address_focus_hint: []const u8,
    open_in_browser: []const u8,
    open_in_terminal: []const u8,
};

const right_panel_chrome_en: RightPanelChrome = .{
    .filter_files = "Filter files",
    .no_project_open = "No project open",
    .open_project_to_browse_files = "Open a project to browse its files",
    .loading_files = "Loading files…",
    .no_background_work = "No background work",
    .no_output = "No output",
    .browse_the_web = "Browse the web",
    .address_focus_hint = "Cmd/Ctrl-L focuses the address.",
    .open_in_browser = "Open in browser",
    .open_in_terminal = "Open in Terminal",
};

const right_panel_chrome_zh_cn: RightPanelChrome = .{
    .filter_files = "筛选文件",
    .no_project_open = "未打开项目",
    .open_project_to_browse_files = "打开项目以浏览文件",
    .loading_files = "正在加载文件…",
    .no_background_work = "没有后台工作",
    .no_output = "没有输出",
    .browse_the_web = "浏览网页",
    .address_focus_hint = "Cmd/Ctrl-L 聚焦地址栏。",
    .open_in_browser = "在浏览器中打开",
    .open_in_terminal = "在终端中打开",
};

const right_panel_chrome_ja: RightPanelChrome = .{
    .filter_files = "ファイルを絞り込む",
    .no_project_open = "プロジェクトが開かれていません",
    .open_project_to_browse_files = "プロジェクトを開いてファイルを閲覧",
    .loading_files = "ファイルを読み込み中…",
    .no_background_work = "バックグラウンド作業はありません",
    .no_output = "出力がありません",
    .browse_the_web = "ウェブを閲覧",
    .address_focus_hint = "Cmd/Ctrl-L でアドレス欄にフォーカス。",
    .open_in_browser = "ブラウザで開く",
    .open_in_terminal = "ターミナルで開く",
};

/// Composer project-row Pick folder / Reveal folder / Open in Editor /
/// Copy path for the resolved locale. Same resolve path as RightPanelChrome.
/// Open in Terminal reuses `RightPanelChrome.open_in_terminal` (not
/// duplicated here). Wire ids / on-press stay English. English matches
/// the former hardcoded composer buttons. Distinct from palette
/// `Open project in Editor` / `Reveal project folder` / `Copy project path`.
pub const ComposerProjectChrome = struct {
    pick_folder: []const u8,
    reveal_folder: []const u8,
    open_in_editor: []const u8,
    copy_path: []const u8,
};

const composer_project_chrome_en: ComposerProjectChrome = .{
    .pick_folder = "Pick folder",
    .reveal_folder = "Reveal folder",
    .open_in_editor = "Open in Editor",
    .copy_path = "Copy path",
};

const composer_project_chrome_zh_cn: ComposerProjectChrome = .{
    .pick_folder = "选择文件夹",
    .reveal_folder = "显示文件夹",
    .open_in_editor = "在编辑器中打开",
    .copy_path = "复制路径",
};

const composer_project_chrome_ja: ComposerProjectChrome = .{
    .pick_folder = "フォルダを選択",
    .reveal_folder = "フォルダを表示",
    .open_in_editor = "エディターで開く",
    .copy_path = "パスをコピー",
};

/// Review Diff header title / Cancel, source chips, and gap
/// expand Start / End / Both / All for the resolved locale. Same
/// resolve path as ComposerProjectChrome. Wire ids / on-press
/// stay English (`close_review_diff` / `set_review_diff_source_*`
/// / `expand_review_diff_gap_*`); selected-state bools stay
/// `review_diff_source_*`. English matches the former hardcoded
/// header, chips, and gap expand buttons. Title EN Review matches
/// the Diff tab (`RightPanelTabs.diff`), not Diff. Remaining hunk
/// chrome (unmodified-line gap labels, `label="Review hunk"`)
/// stays English.
pub const ReviewDiffChrome = struct {
    review_title: []const u8,
    cancel: []const u8,
    branch: []const u8,
    uncommitted: []const u8,
    staged: []const u8,
    unstaged: []const u8,
    committed: []const u8,
    last_turn: []const u8,
    gap_expand_start: []const u8,
    gap_expand_end: []const u8,
    gap_expand_both: []const u8,
    gap_expand_all: []const u8,
};

const review_diff_chrome_en: ReviewDiffChrome = .{
    .review_title = "Review",
    .cancel = "Cancel",
    .branch = "Branch",
    .uncommitted = "Uncommitted",
    .staged = "Staged",
    .unstaged = "Unstaged",
    .committed = "Committed",
    .last_turn = "Last turn",
    .gap_expand_start = "Start",
    .gap_expand_end = "End",
    .gap_expand_both = "Both",
    .gap_expand_all = "All",
};

const review_diff_chrome_zh_cn: ReviewDiffChrome = .{
    .review_title = "审阅",
    .cancel = "取消",
    .branch = "分支",
    .uncommitted = "未提交",
    .staged = "已暂存",
    .unstaged = "未暂存",
    .committed = "已提交",
    .last_turn = "上一轮",
    .gap_expand_start = "开头",
    .gap_expand_end = "末尾",
    .gap_expand_both = "两端",
    .gap_expand_all = "全部",
};

const review_diff_chrome_ja: ReviewDiffChrome = .{
    .review_title = "レビュー",
    .cancel = "キャンセル",
    .branch = "ブランチ",
    .uncommitted = "未コミット",
    .staged = "ステージ済み",
    .unstaged = "未ステージ",
    .committed = "コミット済み",
    .last_turn = "直前のターン",
    .gap_expand_start = "先頭",
    .gap_expand_end = "末尾",
    .gap_expand_both = "両端",
    .gap_expand_all = "すべて",
};

/// Background row kind / status / stop·dismiss chrome for the
/// resolved locale. Same resolve path as ReviewDiffChrome. Paints
/// Environment Summary `background_rows` and right-panel
/// `background_work_*` fields. Wire ids / on-press stay English
/// (`environment_stop_background:*` / `open_background_work:*`).
/// Empty-state No background work / No output stay on
/// `RightPanelChrome`. Environment info-button a11y + dropdown
/// header / menu-item chrome live in `EnvironmentChrome`. English
/// matches the former hardcoded constants. Custom daemon titles
/// are data, not chrome.
pub const BackgroundChrome = struct {
    kind_process: []const u8,
    kind_monitor: []const u8,
    kind_subagent: []const u8,
    process_row: []const u8,
    settled_completed: []const u8,
    settled_stopped: []const u8,
    settled_failed: []const u8,
    live_running: []const u8,
    live_monitoring: []const u8,
    live_stopping: []const u8,
    process_stop: []const u8,
    monitor_stop: []const u8,
    monitor_dismiss: []const u8,
    subagent_stop: []const u8,
    subagent_dismiss: []const u8,
    daemon_stop: []const u8,
    daemon_dismiss: []const u8,
};

pub const background_chrome_en: BackgroundChrome = .{
    .kind_process = "Process",
    .kind_monitor = "Monitor",
    .kind_subagent = "Subagent",
    .process_row = "Agent turn",
    .settled_completed = "Completed",
    .settled_stopped = "Stopped",
    .settled_failed = "Failed",
    .live_running = "Running",
    .live_monitoring = "Monitoring",
    .live_stopping = "Stopping",
    .process_stop = "Stop agent",
    .monitor_stop = "Stop monitor",
    .monitor_dismiss = "Dismiss monitor",
    .subagent_stop = "Stop subagent",
    .subagent_dismiss = "Dismiss subagent",
    .daemon_stop = "Stop",
    .daemon_dismiss = "Dismiss",
};

const background_chrome_zh_cn: BackgroundChrome = .{
    .kind_process = "进程",
    .kind_monitor = "监视器",
    .kind_subagent = "子代理",
    .process_row = "代理轮次",
    .settled_completed = "已完成",
    .settled_stopped = "已停止",
    .settled_failed = "失败",
    .live_running = "运行中",
    .live_monitoring = "监视中",
    .live_stopping = "正在停止",
    .process_stop = "停止代理",
    .monitor_stop = "停止监视器",
    .monitor_dismiss = "关闭监视器",
    .subagent_stop = "停止子代理",
    .subagent_dismiss = "关闭子代理",
    .daemon_stop = "停止",
    .daemon_dismiss = "关闭",
};

const background_chrome_ja: BackgroundChrome = .{
    .kind_process = "プロセス",
    .kind_monitor = "モニター",
    .kind_subagent = "サブエージェント",
    .process_row = "エージェントのターン",
    .settled_completed = "完了",
    .settled_stopped = "停止済み",
    .settled_failed = "失敗",
    .live_running = "実行中",
    .live_monitoring = "監視中",
    .live_stopping = "停止中",
    .process_stop = "エージェントを停止",
    .monitor_stop = "モニターを停止",
    .monitor_dismiss = "モニターを閉じる",
    .subagent_stop = "サブエージェントを停止",
    .subagent_dismiss = "サブエージェントを閉じる",
    .daemon_stop = "停止",
    .daemon_dismiss = "閉じる",
};

/// Environment info-button a11y label and dropdown-menu header +
/// menu-item chrome for the resolved locale. Same resolve path as
/// BackgroundChrome. Wire ids / on-press stay English
/// (`toggle_environment_summary` / `close_environment_summary` /
/// `environment_commit_or_push` / `environment_compare` /
/// `environment_copy_task_id` / `environment_copy_agent_thread_id` /
/// `environment_dismiss_settled_background`). English matches the
/// former hardcoded copy. Title EN Environment is also the a11y
/// label. Dropdown Background section header stays leftover English;
/// row chrome lives in `BackgroundChrome`.
pub const EnvironmentChrome = struct {
    environment: []const u8,
    commit_or_push: []const u8,
    compare: []const u8,
    copy_task_id: []const u8,
    copy_agent_thread_id: []const u8,
    dismiss_all_settled: []const u8,
};

const environment_chrome_en: EnvironmentChrome = .{
    .environment = "Environment",
    .commit_or_push = "Commit or Push",
    .compare = "Compare",
    .copy_task_id = "Copy task ID",
    .copy_agent_thread_id = "Copy agent CLI thread ID",
    .dismiss_all_settled = "Dismiss all settled",
};

const environment_chrome_zh_cn: EnvironmentChrome = .{
    .environment = "环境",
    .commit_or_push = "提交或推送",
    .compare = "比较",
    .copy_task_id = "复制任务 ID",
    .copy_agent_thread_id = "复制代理 CLI 线程 ID",
    .dismiss_all_settled = "关闭全部已结束项",
};

const environment_chrome_ja: EnvironmentChrome = .{
    .environment = "環境",
    .commit_or_push = "コミットまたはプッシュ",
    .compare = "比較",
    .copy_task_id = "タスク ID をコピー",
    .copy_agent_thread_id = "エージェント CLI スレッド ID をコピー",
    .dismiss_all_settled = "終了した項目をすべて閉じる",
};

/// Settings Skills filter placeholder and Settings Usage Projects
/// search-field placeholder + a11y label plus empty-state No project
/// usage for the resolved locale. Same resolve path as
/// EnvironmentChrome. Wire ids / on-input stay English
/// (`skills_filter_edit` / `usage_project_filter_edit`). Filter text
/// itself stays English (user-typed). English matches the former
/// hardcoded copy.
pub const FilterChrome = struct {
    filter_skills: []const u8,
    filter_projects: []const u8,
    no_project_usage: []const u8,
};

const filter_chrome_en: FilterChrome = .{
    .filter_skills = "Filter skills",
    .filter_projects = "Filter projects",
    .no_project_usage = "No project usage",
};

const filter_chrome_zh_cn: FilterChrome = .{
    .filter_skills = "筛选技能",
    .filter_projects = "筛选项目",
    .no_project_usage = "没有项目用量",
};

const filter_chrome_ja: FilterChrome = .{
    .filter_skills = "スキルを絞り込む",
    .filter_projects = "プロジェクトを絞り込む",
    .no_project_usage = "プロジェクトの使用量はありません",
};

/// Files right-panel file-preview toolbar / find-replace / discard /
/// truncated·binary chrome for the resolved locale. Same resolve path
/// as FilterChrome. Wire ids / on-press / on-input stay English
/// (`file_preview_save` / `close_right_panel_file_preview` /
/// `toggle_file_preview_find_replace` / `file_preview_find_edit` /
/// `file_preview_find_replace_edit`). English matches the former
/// hardcoded copy. Distinct from composer `Open in Editor` (title
/// case). Aa / Ab / .* glyphs stay. Path text and body content stay
/// data. Transcript Find placeholder stays on the transcript bar.
pub const FilePreviewChrome = struct {
    unsaved: []const u8,
    preview: []const u8,
    source: []const u8,
    edit: []const u8,
    save: []const u8,
    reload: []const u8,
    open_in_editor: []const u8,
    close: []const u8,
    hide_replace: []const u8,
    show_replace: []const u8,
    find: []const u8,
    find_in_file: []const u8,
    previous_file_match: []const u8,
    next_file_match: []const u8,
    close_file_find: []const u8,
    replace: []const u8,
    replace_in_file: []const u8,
    replace_all: []const u8,
    read_only: []const u8,
    discard_unsaved: []const u8,
    discard: []const u8,
    keep_editing: []const u8,
    truncated: []const u8,
    binary_file: []const u8,
};

const file_preview_chrome_en: FilePreviewChrome = .{
    .unsaved = "Unsaved",
    .preview = "Preview",
    .source = "Source",
    .edit = "Edit",
    .save = "Save",
    .reload = "Reload",
    .open_in_editor = "Open in editor",
    .close = "Close",
    .hide_replace = "Hide replace",
    .show_replace = "Show replace",
    .find = "Find",
    .find_in_file = "Find in file",
    .previous_file_match = "Previous file match",
    .next_file_match = "Next file match",
    .close_file_find = "Close file find",
    .replace = "Replace",
    .replace_in_file = "Replace in file",
    .replace_all = "Replace all",
    .read_only = "Read-only",
    .discard_unsaved = "Discard unsaved changes?",
    .discard = "Discard",
    .keep_editing = "Keep editing",
    .truncated = "Truncated — showing first 256 KB",
    .binary_file = "Binary file — not shown",
};

const file_preview_chrome_zh_cn: FilePreviewChrome = .{
    .unsaved = "未保存",
    .preview = "预览",
    .source = "源码",
    .edit = "编辑",
    .save = "保存",
    .reload = "重新加载",
    .open_in_editor = "在编辑器中打开",
    .close = "关闭",
    .hide_replace = "隐藏替换",
    .show_replace = "显示替换",
    .find = "查找",
    .find_in_file = "在文件中查找",
    .previous_file_match = "上一个文件匹配",
    .next_file_match = "下一个文件匹配",
    .close_file_find = "关闭文件查找",
    .replace = "替换",
    .replace_in_file = "在文件中替换",
    .replace_all = "全部替换",
    .read_only = "只读",
    .discard_unsaved = "放弃未保存的更改？",
    .discard = "放弃",
    .keep_editing = "继续编辑",
    .truncated = "已截断 — 仅显示前 256 KB",
    .binary_file = "二进制文件 — 未显示",
};

const file_preview_chrome_ja: FilePreviewChrome = .{
    .unsaved = "未保存",
    .preview = "プレビュー",
    .source = "ソース",
    .edit = "編集",
    .save = "保存",
    .reload = "再読み込み",
    .open_in_editor = "エディターで開く",
    .close = "閉じる",
    .hide_replace = "置換を隠す",
    .show_replace = "置換を表示",
    .find = "検索",
    .find_in_file = "ファイル内を検索",
    .previous_file_match = "前のファイル一致",
    .next_file_match = "次のファイル一致",
    .close_file_find = "ファイル検索を閉じる",
    .replace = "置換",
    .replace_in_file = "ファイル内を置換",
    .replace_all = "すべて置換",
    .read_only = "読み取り専用",
    .discard_unsaved = "未保存の変更を破棄しますか？",
    .discard = "破棄",
    .keep_editing = "編集を続ける",
    .truncated = "切り詰め済み — 先頭 256 KB を表示",
    .binary_file = "バイナリファイル — 非表示",
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

/// Composer / Settings General Ask / Auto / Full access for the
/// resolved locale. Callers pass Model `language_preference` +
/// `system_locale_id`; this file does not read process env.
pub fn accessFor(preference: LanguagePreference, system_locale_id: []const u8) Access {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => access_zh_cn,
        .japanese => access_ja,
        .system, .english => access_en,
    };
}

/// Composer / Settings General effort chrome for the resolved locale.
/// Callers pass Model `language_preference` + `system_locale_id`; this
/// file does not read process env.
pub fn effortFor(preference: LanguagePreference, system_locale_id: []const u8) Effort {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => effort_zh_cn,
        .japanese => effort_ja,
        .system, .english => effort_en,
    };
}

/// Composer / Settings General Build / Plan for the resolved locale.
/// Callers pass Model `language_preference` + `system_locale_id`; this
/// file does not read process env.
pub fn interactionFor(preference: LanguagePreference, system_locale_id: []const u8) Interaction {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => interaction_zh_cn,
        .japanese => interaction_ja,
        .system, .english => interaction_en,
    };
}

/// Palette action display labels for the resolved locale. Callers
/// pass Model `language_preference` + `system_locale_id`; this file
/// does not read process env. New Task / Settings / Collapse all
/// folders stay on `sidebarFor` / `chromeFor`.
pub fn paletteFor(preference: LanguagePreference, system_locale_id: []const u8) Palette {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => palette_zh_cn,
        .japanese => palette_ja,
        .system, .english => palette_en,
    };
}

/// Palette overlay section headers and empty-state lines for the
/// resolved locale. Callers pass Model `language_preference` +
/// `system_locale_id`; this file does not read process env. Action
/// names stay on `paletteFor`.
pub fn paletteChromeFor(preference: LanguagePreference, system_locale_id: []const u8) PaletteChrome {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => palette_chrome_zh_cn,
        .japanese => palette_chrome_ja,
        .system, .english => palette_chrome_en,
    };
}

/// Right-panel tab button labels for the resolved locale. Callers
/// pass Model `language_preference` + `system_locale_id`; this file
/// does not read process env. Wire ids stay on `right_panel.Tab`.
pub fn rightPanelTabsFor(preference: LanguagePreference, system_locale_id: []const u8) RightPanelTabs {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => right_panel_tabs_zh_cn,
        .japanese => right_panel_tabs_ja,
        .system, .english => right_panel_tabs_en,
    };
}

/// Right-panel Diff filter + Files/Background empty-state chrome
/// (including Files empty secondary / Loading files…) plus Browser
/// start page / Open in browser / Open in Terminal for the resolved
/// locale. Callers pass Model `language_preference` +
/// `system_locale_id`; this file does not read process env. Wire ids /
/// on-press / filter text stay English.
pub fn rightPanelChromeFor(preference: LanguagePreference, system_locale_id: []const u8) RightPanelChrome {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => right_panel_chrome_zh_cn,
        .japanese => right_panel_chrome_ja,
        .system, .english => right_panel_chrome_en,
    };
}

/// Composer project-row Pick folder / Reveal folder / Open in Editor /
/// Copy path for the resolved locale. Callers pass Model
/// `language_preference` + `system_locale_id`; this file does not read
/// process env. Open in Terminal stays on `rightPanelChromeFor`.
pub fn composerProjectChromeFor(preference: LanguagePreference, system_locale_id: []const u8) ComposerProjectChrome {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => composer_project_chrome_zh_cn,
        .japanese => composer_project_chrome_ja,
        .system, .english => composer_project_chrome_en,
    };
}

/// Review Diff header title / Cancel / source chips / gap expand
/// Start / End / Both / All for the resolved locale. Callers pass
/// Model `language_preference` + `system_locale_id`; this file
/// does not read process env. Wire ids / on-press stay English.
pub fn reviewDiffChromeFor(preference: LanguagePreference, system_locale_id: []const u8) ReviewDiffChrome {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => review_diff_chrome_zh_cn,
        .japanese => review_diff_chrome_ja,
        .system, .english => review_diff_chrome_en,
    };
}

/// Background row kind / status / stop·dismiss chrome for the
/// resolved locale. Callers pass Model `language_preference` +
/// `system_locale_id`; this file does not read process env. Wire
/// ids / on-press stay English. Empty-state strings stay on
/// `rightPanelChromeFor`.
pub fn backgroundChromeFor(preference: LanguagePreference, system_locale_id: []const u8) BackgroundChrome {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => background_chrome_zh_cn,
        .japanese => background_chrome_ja,
        .system, .english => background_chrome_en,
    };
}

/// Environment info-button a11y + dropdown-menu header / menu-item
/// chrome for the resolved locale. Callers pass Model
/// `language_preference` + `system_locale_id`; this file does not
/// read process env. Wire ids / on-press stay English.
pub fn environmentChromeFor(preference: LanguagePreference, system_locale_id: []const u8) EnvironmentChrome {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => environment_chrome_zh_cn,
        .japanese => environment_chrome_ja,
        .system, .english => environment_chrome_en,
    };
}

/// Settings Skills / Usage Projects filter chrome for the resolved
/// locale. Callers pass Model `language_preference` +
/// `system_locale_id`; this file does not read process env. Wire ids /
/// on-input / filter text stay English.
pub fn filterChromeFor(preference: LanguagePreference, system_locale_id: []const u8) FilterChrome {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => filter_chrome_zh_cn,
        .japanese => filter_chrome_ja,
        .system, .english => filter_chrome_en,
    };
}

/// Files right-panel file-preview toolbar chrome for the resolved
/// locale. Callers pass Model `language_preference` +
/// `system_locale_id`; this file does not read process env. Wire ids /
/// on-press / on-input stay English.
pub fn filePreviewChromeFor(preference: LanguagePreference, system_locale_id: []const u8) FilePreviewChrome {
    return switch (resolve(preference, system_locale_id)) {
        .simplified_chinese => file_preview_chrome_zh_cn,
        .japanese => file_preview_chrome_ja,
        .system, .english => file_preview_chrome_en,
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

test "accessFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("Ask", accessFor(.english, "ja").ask);
    try testing.expectEqualStrings("Auto", accessFor(.english, "").auto);
    try testing.expectEqualStrings("Full access", accessFor(.english, "").full_access);
    try testing.expectEqualStrings("Ask", accessFor(.system, "").ask);
    try testing.expectEqualStrings("Ask", accessFor(.english, "").labelForId("ask"));
    try testing.expectEqualStrings("Auto", accessFor(.english, "").labelForId("auto"));
    try testing.expectEqualStrings("Full access", accessFor(.english, "").labelForId("fullAccess"));
    try testing.expectEqualStrings("Full access", accessFor(.english, "").labelForId("yolo"));

    try testing.expectEqualStrings("询问", accessFor(.simplified_chinese, "").ask);
    try testing.expectEqualStrings("自动", accessFor(.simplified_chinese, "").auto);
    try testing.expectEqualStrings("完全访问", accessFor(.simplified_chinese, "").full_access);
    try testing.expectEqualStrings("询问", accessFor(.simplified_chinese, "").labelForId("ask"));
    try testing.expectEqualStrings("自动", accessFor(.simplified_chinese, "").labelForId("auto"));
    try testing.expectEqualStrings("完全访问", accessFor(.simplified_chinese, "").labelForId("fullAccess"));

    try testing.expectEqualStrings("確認", accessFor(.japanese, "").ask);
    try testing.expectEqualStrings("自動", accessFor(.japanese, "").auto);
    try testing.expectEqualStrings("フルアクセス", accessFor(.japanese, "").full_access);

    try testing.expectEqualStrings("询问", accessFor(.system, "zh_CN.UTF-8").ask);
    try testing.expectEqualStrings("自動", accessFor(.system, "ja_JP.UTF-8").auto);
    try testing.expectEqualStrings("Ask", accessFor(.english, "ja_JP.UTF-8").ask);
    try testing.expectEqualStrings("Auto", accessFor(.english, "zh_CN.UTF-8").auto);
    try testing.expectEqualStrings("Full access", accessFor(.english, "ja_JP.UTF-8").full_access);
}

test "effortFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("Auto", effortFor(.english, "ja").auto);
    try testing.expectEqualStrings("None", effortFor(.english, "").none);
    try testing.expectEqualStrings("Minimal", effortFor(.english, "").minimal);
    try testing.expectEqualStrings("Low", effortFor(.english, "").low);
    try testing.expectEqualStrings("Medium", effortFor(.english, "").medium);
    try testing.expectEqualStrings("High", effortFor(.english, "").high);
    try testing.expectEqualStrings("Extra high", effortFor(.english, "").extra_high);
    try testing.expectEqualStrings("Max", effortFor(.english, "").max);
    try testing.expectEqualStrings("Auto", effortFor(.system, "").auto);
    try testing.expectEqualStrings("Auto", effortFor(.english, "").labelForId("auto"));
    try testing.expectEqualStrings("None", effortFor(.english, "").labelForId("none"));
    try testing.expectEqualStrings("Minimal", effortFor(.english, "").labelForId("minimal"));
    try testing.expectEqualStrings("Low", effortFor(.english, "").labelForId("low"));
    try testing.expectEqualStrings("Medium", effortFor(.english, "").labelForId("medium"));
    try testing.expectEqualStrings("High", effortFor(.english, "").labelForId("high"));
    try testing.expectEqualStrings("Extra high", effortFor(.english, "").labelForId("xhigh"));
    try testing.expectEqualStrings("Max", effortFor(.english, "").labelForId("max"));
    try testing.expectEqualStrings("Auto", effortFor(.english, "").labelForId(""));
    try testing.expectEqualStrings("Auto", effortFor(.english, "").labelForId("nope"));

    try testing.expectEqualStrings("自动", effortFor(.simplified_chinese, "").auto);
    try testing.expectEqualStrings("无", effortFor(.simplified_chinese, "").none);
    try testing.expectEqualStrings("最低", effortFor(.simplified_chinese, "").minimal);
    try testing.expectEqualStrings("低", effortFor(.simplified_chinese, "").low);
    try testing.expectEqualStrings("中", effortFor(.simplified_chinese, "").medium);
    try testing.expectEqualStrings("高", effortFor(.simplified_chinese, "").high);
    try testing.expectEqualStrings("极高", effortFor(.simplified_chinese, "").extra_high);
    try testing.expectEqualStrings("最大", effortFor(.simplified_chinese, "").max);
    try testing.expectEqualStrings("自动", effortFor(.simplified_chinese, "").labelForId("auto"));
    try testing.expectEqualStrings("无", effortFor(.simplified_chinese, "").labelForId("none"));
    try testing.expectEqualStrings("极高", effortFor(.simplified_chinese, "").labelForId("xhigh"));
    try testing.expectEqualStrings("最大", effortFor(.simplified_chinese, "").labelForId("max"));

    try testing.expectEqualStrings("自動", effortFor(.japanese, "").auto);
    try testing.expectEqualStrings("なし", effortFor(.japanese, "").none);
    try testing.expectEqualStrings("最小", effortFor(.japanese, "").minimal);
    try testing.expectEqualStrings("低", effortFor(.japanese, "").low);
    try testing.expectEqualStrings("中", effortFor(.japanese, "").medium);
    try testing.expectEqualStrings("高", effortFor(.japanese, "").high);
    try testing.expectEqualStrings("非常に高い", effortFor(.japanese, "").extra_high);
    try testing.expectEqualStrings("最大", effortFor(.japanese, "").max);
    try testing.expectEqualStrings("自動", effortFor(.japanese, "").labelForId("auto"));
    try testing.expectEqualStrings("非常に高い", effortFor(.japanese, "").labelForId("xhigh"));

    try testing.expectEqualStrings("自动", effortFor(.system, "zh_CN.UTF-8").auto);
    try testing.expectEqualStrings("なし", effortFor(.system, "ja_JP.UTF-8").none);
    try testing.expectEqualStrings("Auto", effortFor(.english, "ja_JP.UTF-8").auto);
    try testing.expectEqualStrings("None", effortFor(.english, "zh_CN.UTF-8").none);
    try testing.expectEqualStrings("Extra high", effortFor(.english, "ja_JP.UTF-8").extra_high);
    try testing.expectEqualStrings("Max", effortFor(.english, "zh_CN.UTF-8").max);
}

test "interactionFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("Build", interactionFor(.english, "ja").build);
    try testing.expectEqualStrings("Plan", interactionFor(.english, "").plan);
    try testing.expectEqualStrings("Build", interactionFor(.system, "").build);
    try testing.expectEqualStrings("Build", interactionFor(.english, "").labelForId("build"));
    try testing.expectEqualStrings("Plan", interactionFor(.english, "").labelForId("plan"));
    try testing.expectEqualStrings("Build", interactionFor(.english, "").labelForId(""));
    try testing.expectEqualStrings("Build", interactionFor(.english, "").labelForId("nope"));

    try testing.expectEqualStrings("构建", interactionFor(.simplified_chinese, "").build);
    try testing.expectEqualStrings("计划", interactionFor(.simplified_chinese, "").plan);
    try testing.expectEqualStrings("构建", interactionFor(.simplified_chinese, "").labelForId("build"));
    try testing.expectEqualStrings("计划", interactionFor(.simplified_chinese, "").labelForId("plan"));
    try testing.expectEqualStrings("构建", interactionFor(.simplified_chinese, "").labelForId(""));
    try testing.expectEqualStrings("构建", interactionFor(.simplified_chinese, "").labelForId("nope"));

    try testing.expectEqualStrings("ビルド", interactionFor(.japanese, "").build);
    try testing.expectEqualStrings("プラン", interactionFor(.japanese, "").plan);
    try testing.expectEqualStrings("ビルド", interactionFor(.japanese, "").labelForId("build"));
    try testing.expectEqualStrings("プラン", interactionFor(.japanese, "").labelForId("plan"));

    try testing.expectEqualStrings("构建", interactionFor(.system, "zh_CN.UTF-8").build);
    try testing.expectEqualStrings("プラン", interactionFor(.system, "ja_JP.UTF-8").plan);
    try testing.expectEqualStrings("Build", interactionFor(.english, "ja_JP.UTF-8").build);
    try testing.expectEqualStrings("Plan", interactionFor(.english, "zh_CN.UTF-8").plan);
}

test "paletteFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("Focus composer", paletteFor(.english, "ja").focus_composer);
    try testing.expectEqualStrings("Toggle sidebar", paletteFor(.english, "").toggle_sidebar);
    try testing.expectEqualStrings("Find in transcript", paletteFor(.english, "").find_in_transcript);
    try testing.expectEqualStrings("Minimize", paletteFor(.english, "").minimize);
    try testing.expectEqualStrings("Maximize", paletteFor(.english, "").maximize);
    try testing.expectEqualStrings("Copy session id", paletteFor(.english, "").copy_session_id);
    try testing.expectEqualStrings("Copy provider session id", paletteFor(.english, "").copy_provider_session_id);
    try testing.expectEqualStrings("Reveal project folder", paletteFor(.english, "").reveal_project_folder);
    try testing.expectEqualStrings("Open project in Terminal", paletteFor(.english, "").open_project_in_terminal);
    try testing.expectEqualStrings("Open project in Editor", paletteFor(.english, "").open_project_in_editor);
    try testing.expectEqualStrings("Copy project path", paletteFor(.english, "").copy_project_path);
    try testing.expectEqualStrings("Show right panel", paletteFor(.english, "").show_right_panel);
    try testing.expectEqualStrings("Hide right panel", paletteFor(.english, "").hide_right_panel);
    try testing.expectEqualStrings("Show Browser tab", paletteFor(.english, "").show_browser_tab);
    try testing.expectEqualStrings("Show Terminal tab", paletteFor(.english, "").show_terminal_tab);
    try testing.expectEqualStrings("Expand sidebar", paletteFor(.english, "").expand_sidebar);
    try testing.expectEqualStrings("Collapse sidebar", paletteFor(.english, "").collapse_sidebar);
    try testing.expectEqualStrings("Focus composer", paletteFor(.system, "").focus_composer);

    try testing.expectEqualStrings("聚焦输入框", paletteFor(.simplified_chinese, "").focus_composer);
    try testing.expectEqualStrings("切换侧边栏", paletteFor(.simplified_chinese, "").toggle_sidebar);
    try testing.expectEqualStrings("在记录中查找", paletteFor(.simplified_chinese, "").find_in_transcript);
    try testing.expectEqualStrings("最小化", paletteFor(.simplified_chinese, "").minimize);
    try testing.expectEqualStrings("最大化", paletteFor(.simplified_chinese, "").maximize);
    try testing.expectEqualStrings("复制会话 ID", paletteFor(.simplified_chinese, "").copy_session_id);
    try testing.expectEqualStrings("复制提供商会话 ID", paletteFor(.simplified_chinese, "").copy_provider_session_id);
    try testing.expectEqualStrings("显示项目文件夹", paletteFor(.simplified_chinese, "").reveal_project_folder);
    try testing.expectEqualStrings("在终端中打开项目", paletteFor(.simplified_chinese, "").open_project_in_terminal);
    try testing.expectEqualStrings("在编辑器中打开项目", paletteFor(.simplified_chinese, "").open_project_in_editor);
    try testing.expectEqualStrings("复制项目路径", paletteFor(.simplified_chinese, "").copy_project_path);
    try testing.expectEqualStrings("显示右侧面板", paletteFor(.simplified_chinese, "").show_right_panel);
    try testing.expectEqualStrings("隐藏右侧面板", paletteFor(.simplified_chinese, "").hide_right_panel);
    try testing.expectEqualStrings("显示浏览器标签页", paletteFor(.simplified_chinese, "").show_browser_tab);
    try testing.expectEqualStrings("显示终端标签页", paletteFor(.simplified_chinese, "").show_terminal_tab);
    try testing.expectEqualStrings("展开侧边栏", paletteFor(.simplified_chinese, "").expand_sidebar);
    try testing.expectEqualStrings("折叠侧边栏", paletteFor(.simplified_chinese, "").collapse_sidebar);

    try testing.expectEqualStrings("入力欄にフォーカス", paletteFor(.japanese, "").focus_composer);
    try testing.expectEqualStrings("サイドバーを切り替え", paletteFor(.japanese, "").toggle_sidebar);
    try testing.expectEqualStrings("記録内を検索", paletteFor(.japanese, "").find_in_transcript);
    try testing.expectEqualStrings("最小化", paletteFor(.japanese, "").minimize);
    try testing.expectEqualStrings("最大化", paletteFor(.japanese, "").maximize);
    try testing.expectEqualStrings("セッション ID をコピー", paletteFor(.japanese, "").copy_session_id);
    try testing.expectEqualStrings("プロバイダーセッション ID をコピー", paletteFor(.japanese, "").copy_provider_session_id);
    try testing.expectEqualStrings("プロジェクトフォルダを表示", paletteFor(.japanese, "").reveal_project_folder);
    try testing.expectEqualStrings("ターミナルでプロジェクトを開く", paletteFor(.japanese, "").open_project_in_terminal);
    try testing.expectEqualStrings("エディターでプロジェクトを開く", paletteFor(.japanese, "").open_project_in_editor);
    try testing.expectEqualStrings("プロジェクトパスをコピー", paletteFor(.japanese, "").copy_project_path);
    try testing.expectEqualStrings("右パネルを表示", paletteFor(.japanese, "").show_right_panel);
    try testing.expectEqualStrings("右パネルを非表示", paletteFor(.japanese, "").hide_right_panel);
    try testing.expectEqualStrings("ブラウザーのタブを表示", paletteFor(.japanese, "").show_browser_tab);
    try testing.expectEqualStrings("ターミナルのタブを表示", paletteFor(.japanese, "").show_terminal_tab);
    try testing.expectEqualStrings("サイドバーを展開", paletteFor(.japanese, "").expand_sidebar);
    try testing.expectEqualStrings("サイドバーを折りたたむ", paletteFor(.japanese, "").collapse_sidebar);

    try testing.expectEqualStrings("聚焦输入框", paletteFor(.system, "zh_CN.UTF-8").focus_composer);
    try testing.expectEqualStrings("サイドバーを切り替え", paletteFor(.system, "ja_JP.UTF-8").toggle_sidebar);
    try testing.expectEqualStrings("Focus composer", paletteFor(.english, "ja_JP.UTF-8").focus_composer);
    try testing.expectEqualStrings("Toggle sidebar", paletteFor(.english, "zh_CN.UTF-8").toggle_sidebar);
    try testing.expectEqualStrings("Show right panel", paletteFor(.english, "ja_JP.UTF-8").show_right_panel);
    try testing.expectEqualStrings("Hide right panel", paletteFor(.english, "zh_CN.UTF-8").hide_right_panel);
    try testing.expectEqualStrings("Expand sidebar", paletteFor(.english, "ja_JP.UTF-8").expand_sidebar);
    try testing.expectEqualStrings("Collapse sidebar", paletteFor(.english, "zh_CN.UTF-8").collapse_sidebar);
}

test "paletteChromeFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("Suggested", paletteChromeFor(.english, "ja").suggested);
    try testing.expectEqualStrings("Commands", paletteChromeFor(.english, "").commands);
    try testing.expectEqualStrings("Tasks", paletteChromeFor(.english, "").tasks);
    try testing.expectEqualStrings("No matching tasks or commands", paletteChromeFor(.english, "").no_matches);
    try testing.expectEqualStrings("Try a task title, project, provider, model, or command", paletteChromeFor(.english, "").try_query);
    try testing.expectEqualStrings("Suggested", paletteChromeFor(.system, "").suggested);

    try testing.expectEqualStrings("建议", paletteChromeFor(.simplified_chinese, "").suggested);
    try testing.expectEqualStrings("命令", paletteChromeFor(.simplified_chinese, "").commands);
    try testing.expectEqualStrings("任务", paletteChromeFor(.simplified_chinese, "").tasks);
    try testing.expectEqualStrings("没有匹配的任务或命令", paletteChromeFor(.simplified_chinese, "").no_matches);
    try testing.expectEqualStrings("试试任务标题、项目、提供商、模型或命令", paletteChromeFor(.simplified_chinese, "").try_query);

    try testing.expectEqualStrings("おすすめ", paletteChromeFor(.japanese, "").suggested);
    try testing.expectEqualStrings("コマンド", paletteChromeFor(.japanese, "").commands);
    try testing.expectEqualStrings("タスク", paletteChromeFor(.japanese, "").tasks);
    try testing.expectEqualStrings("一致するタスクやコマンドはありません", paletteChromeFor(.japanese, "").no_matches);
    try testing.expectEqualStrings("タスク名、プロジェクト、プロバイダー、モデル、コマンドを試す", paletteChromeFor(.japanese, "").try_query);

    try testing.expectEqualStrings("建议", paletteChromeFor(.system, "zh_CN.UTF-8").suggested);
    try testing.expectEqualStrings("コマンド", paletteChromeFor(.system, "ja_JP.UTF-8").commands);
    try testing.expectEqualStrings("Suggested", paletteChromeFor(.english, "ja_JP.UTF-8").suggested);
    try testing.expectEqualStrings("Commands", paletteChromeFor(.english, "zh_CN.UTF-8").commands);
    try testing.expectEqualStrings("Tasks", paletteChromeFor(.english, "ja_JP.UTF-8").tasks);
    try testing.expectEqualStrings("No matching tasks or commands", paletteChromeFor(.english, "zh_CN.UTF-8").no_matches);
    try testing.expectEqualStrings("Try a task title, project, provider, model, or command", paletteChromeFor(.english, "ja_JP.UTF-8").try_query);
}

test "rightPanelTabsFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("Files", rightPanelTabsFor(.english, "ja").files);
    try testing.expectEqualStrings("Review", rightPanelTabsFor(.english, "").diff);
    try testing.expectEqualStrings("Browser", rightPanelTabsFor(.english, "").browser);
    try testing.expectEqualStrings("Terminal", rightPanelTabsFor(.english, "").terminal);
    try testing.expectEqualStrings("Background", rightPanelTabsFor(.english, "").background);
    try testing.expectEqualStrings("Files", rightPanelTabsFor(.system, "").files);

    try testing.expectEqualStrings("文件", rightPanelTabsFor(.simplified_chinese, "").files);
    try testing.expectEqualStrings("审阅", rightPanelTabsFor(.simplified_chinese, "").diff);
    try testing.expectEqualStrings("浏览器", rightPanelTabsFor(.simplified_chinese, "").browser);
    try testing.expectEqualStrings("终端", rightPanelTabsFor(.simplified_chinese, "").terminal);
    try testing.expectEqualStrings("后台工作", rightPanelTabsFor(.simplified_chinese, "").background);

    try testing.expectEqualStrings("ファイル", rightPanelTabsFor(.japanese, "").files);
    try testing.expectEqualStrings("レビュー", rightPanelTabsFor(.japanese, "").diff);
    try testing.expectEqualStrings("ブラウザ", rightPanelTabsFor(.japanese, "").browser);
    try testing.expectEqualStrings("ターミナル", rightPanelTabsFor(.japanese, "").terminal);
    try testing.expectEqualStrings("バックグラウンド", rightPanelTabsFor(.japanese, "").background);

    try testing.expectEqualStrings("文件", rightPanelTabsFor(.system, "zh_CN.UTF-8").files);
    try testing.expectEqualStrings("レビュー", rightPanelTabsFor(.system, "ja_JP.UTF-8").diff);
    try testing.expectEqualStrings("Files", rightPanelTabsFor(.english, "ja_JP.UTF-8").files);
    try testing.expectEqualStrings("Review", rightPanelTabsFor(.english, "zh_CN.UTF-8").diff);
    try testing.expectEqualStrings("Browser", rightPanelTabsFor(.english, "ja_JP.UTF-8").browser);
    try testing.expectEqualStrings("Terminal", rightPanelTabsFor(.english, "zh_CN.UTF-8").terminal);
    try testing.expectEqualStrings("Background", rightPanelTabsFor(.english, "ja_JP.UTF-8").background);
}

test "rightPanelChromeFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("Filter files", rightPanelChromeFor(.english, "ja").filter_files);
    try testing.expectEqualStrings("No project open", rightPanelChromeFor(.english, "").no_project_open);
    try testing.expectEqualStrings("Open a project to browse its files", rightPanelChromeFor(.english, "").open_project_to_browse_files);
    try testing.expectEqualStrings("Loading files…", rightPanelChromeFor(.english, "").loading_files);
    try testing.expectEqualStrings("No background work", rightPanelChromeFor(.english, "").no_background_work);
    try testing.expectEqualStrings("No output", rightPanelChromeFor(.english, "").no_output);
    try testing.expectEqualStrings("Browse the web", rightPanelChromeFor(.english, "").browse_the_web);
    try testing.expectEqualStrings("Cmd/Ctrl-L focuses the address.", rightPanelChromeFor(.english, "").address_focus_hint);
    try testing.expectEqualStrings("Open in browser", rightPanelChromeFor(.english, "").open_in_browser);
    try testing.expectEqualStrings("Open in Terminal", rightPanelChromeFor(.english, "").open_in_terminal);
    try testing.expectEqualStrings("Filter files", rightPanelChromeFor(.system, "").filter_files);

    try testing.expectEqualStrings("筛选文件", rightPanelChromeFor(.simplified_chinese, "").filter_files);
    try testing.expectEqualStrings("未打开项目", rightPanelChromeFor(.simplified_chinese, "").no_project_open);
    try testing.expectEqualStrings("打开项目以浏览文件", rightPanelChromeFor(.simplified_chinese, "").open_project_to_browse_files);
    try testing.expectEqualStrings("正在加载文件…", rightPanelChromeFor(.simplified_chinese, "").loading_files);
    try testing.expectEqualStrings("没有后台工作", rightPanelChromeFor(.simplified_chinese, "").no_background_work);
    try testing.expectEqualStrings("没有输出", rightPanelChromeFor(.simplified_chinese, "").no_output);
    try testing.expectEqualStrings("浏览网页", rightPanelChromeFor(.simplified_chinese, "").browse_the_web);
    try testing.expectEqualStrings("Cmd/Ctrl-L 聚焦地址栏。", rightPanelChromeFor(.simplified_chinese, "").address_focus_hint);
    try testing.expectEqualStrings("在浏览器中打开", rightPanelChromeFor(.simplified_chinese, "").open_in_browser);
    try testing.expectEqualStrings("在终端中打开", rightPanelChromeFor(.simplified_chinese, "").open_in_terminal);

    try testing.expectEqualStrings("ファイルを絞り込む", rightPanelChromeFor(.japanese, "").filter_files);
    try testing.expectEqualStrings("プロジェクトが開かれていません", rightPanelChromeFor(.japanese, "").no_project_open);
    try testing.expectEqualStrings("プロジェクトを開いてファイルを閲覧", rightPanelChromeFor(.japanese, "").open_project_to_browse_files);
    try testing.expectEqualStrings("ファイルを読み込み中…", rightPanelChromeFor(.japanese, "").loading_files);
    try testing.expectEqualStrings("バックグラウンド作業はありません", rightPanelChromeFor(.japanese, "").no_background_work);
    try testing.expectEqualStrings("出力がありません", rightPanelChromeFor(.japanese, "").no_output);
    try testing.expectEqualStrings("ウェブを閲覧", rightPanelChromeFor(.japanese, "").browse_the_web);
    try testing.expectEqualStrings("Cmd/Ctrl-L でアドレス欄にフォーカス。", rightPanelChromeFor(.japanese, "").address_focus_hint);
    try testing.expectEqualStrings("ブラウザで開く", rightPanelChromeFor(.japanese, "").open_in_browser);
    try testing.expectEqualStrings("ターミナルで開く", rightPanelChromeFor(.japanese, "").open_in_terminal);

    try testing.expectEqualStrings("筛选文件", rightPanelChromeFor(.system, "zh_CN.UTF-8").filter_files);
    try testing.expectEqualStrings("打开项目以浏览文件", rightPanelChromeFor(.system, "zh_CN.UTF-8").open_project_to_browse_files);
    try testing.expectEqualStrings("正在加载文件…", rightPanelChromeFor(.system, "zh_CN.UTF-8").loading_files);
    try testing.expectEqualStrings("出力がありません", rightPanelChromeFor(.system, "ja_JP.UTF-8").no_output);
    try testing.expectEqualStrings("プロジェクトを開いてファイルを閲覧", rightPanelChromeFor(.system, "ja_JP.UTF-8").open_project_to_browse_files);
    try testing.expectEqualStrings("ファイルを読み込み中…", rightPanelChromeFor(.system, "ja_JP.UTF-8").loading_files);
    try testing.expectEqualStrings("浏览网页", rightPanelChromeFor(.system, "zh_CN.UTF-8").browse_the_web);
    try testing.expectEqualStrings("ターミナルで開く", rightPanelChromeFor(.system, "ja_JP.UTF-8").open_in_terminal);
    try testing.expectEqualStrings("Filter files", rightPanelChromeFor(.english, "ja_JP.UTF-8").filter_files);
    try testing.expectEqualStrings("No project open", rightPanelChromeFor(.english, "zh_CN.UTF-8").no_project_open);
    try testing.expectEqualStrings("Open a project to browse its files", rightPanelChromeFor(.english, "ja_JP.UTF-8").open_project_to_browse_files);
    try testing.expectEqualStrings("Loading files…", rightPanelChromeFor(.english, "zh_CN.UTF-8").loading_files);
    try testing.expectEqualStrings("No background work", rightPanelChromeFor(.english, "ja_JP.UTF-8").no_background_work);
    try testing.expectEqualStrings("No output", rightPanelChromeFor(.english, "zh_CN.UTF-8").no_output);
    try testing.expectEqualStrings("Browse the web", rightPanelChromeFor(.english, "ja_JP.UTF-8").browse_the_web);
    try testing.expectEqualStrings("Cmd/Ctrl-L focuses the address.", rightPanelChromeFor(.english, "zh_CN.UTF-8").address_focus_hint);
    try testing.expectEqualStrings("Open in browser", rightPanelChromeFor(.english, "ja_JP.UTF-8").open_in_browser);
    try testing.expectEqualStrings("Open in Terminal", rightPanelChromeFor(.english, "zh_CN.UTF-8").open_in_terminal);
}

test "composerProjectChromeFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("Pick folder", composerProjectChromeFor(.english, "ja").pick_folder);
    try testing.expectEqualStrings("Reveal folder", composerProjectChromeFor(.english, "").reveal_folder);
    try testing.expectEqualStrings("Open in Editor", composerProjectChromeFor(.english, "").open_in_editor);
    try testing.expectEqualStrings("Copy path", composerProjectChromeFor(.english, "").copy_path);
    try testing.expectEqualStrings("Pick folder", composerProjectChromeFor(.system, "").pick_folder);

    try testing.expectEqualStrings("选择文件夹", composerProjectChromeFor(.simplified_chinese, "").pick_folder);
    try testing.expectEqualStrings("显示文件夹", composerProjectChromeFor(.simplified_chinese, "").reveal_folder);
    try testing.expectEqualStrings("在编辑器中打开", composerProjectChromeFor(.simplified_chinese, "").open_in_editor);
    try testing.expectEqualStrings("复制路径", composerProjectChromeFor(.simplified_chinese, "").copy_path);

    try testing.expectEqualStrings("フォルダを選択", composerProjectChromeFor(.japanese, "").pick_folder);
    try testing.expectEqualStrings("フォルダを表示", composerProjectChromeFor(.japanese, "").reveal_folder);
    try testing.expectEqualStrings("エディターで開く", composerProjectChromeFor(.japanese, "").open_in_editor);
    try testing.expectEqualStrings("パスをコピー", composerProjectChromeFor(.japanese, "").copy_path);

    try testing.expectEqualStrings("选择文件夹", composerProjectChromeFor(.system, "zh_CN.UTF-8").pick_folder);
    try testing.expectEqualStrings("パスをコピー", composerProjectChromeFor(.system, "ja_JP.UTF-8").copy_path);
    try testing.expectEqualStrings("Pick folder", composerProjectChromeFor(.english, "ja_JP.UTF-8").pick_folder);
    try testing.expectEqualStrings("Reveal folder", composerProjectChromeFor(.english, "zh_CN.UTF-8").reveal_folder);
    try testing.expectEqualStrings("Open in Editor", composerProjectChromeFor(.english, "ja_JP.UTF-8").open_in_editor);
    try testing.expectEqualStrings("Copy path", composerProjectChromeFor(.english, "zh_CN.UTF-8").copy_path);

    try testing.expect(!std.mem.eql(u8, composerProjectChromeFor(.english, "").open_in_editor, paletteFor(.english, "").open_project_in_editor));
    try testing.expect(!std.mem.eql(u8, composerProjectChromeFor(.english, "").reveal_folder, paletteFor(.english, "").reveal_project_folder));
    try testing.expect(!std.mem.eql(u8, composerProjectChromeFor(.english, "").copy_path, paletteFor(.english, "").copy_project_path));
    try testing.expect(!std.mem.eql(u8, composerProjectChromeFor(.simplified_chinese, "").open_in_editor, paletteFor(.simplified_chinese, "").open_project_in_editor));
    try testing.expect(!std.mem.eql(u8, composerProjectChromeFor(.simplified_chinese, "").reveal_folder, paletteFor(.simplified_chinese, "").reveal_project_folder));
    try testing.expect(!std.mem.eql(u8, composerProjectChromeFor(.simplified_chinese, "").copy_path, paletteFor(.simplified_chinese, "").copy_project_path));
    try testing.expect(!std.mem.eql(u8, composerProjectChromeFor(.japanese, "").open_in_editor, paletteFor(.japanese, "").open_project_in_editor));
    try testing.expect(!std.mem.eql(u8, composerProjectChromeFor(.japanese, "").reveal_folder, paletteFor(.japanese, "").reveal_project_folder));
    try testing.expect(!std.mem.eql(u8, composerProjectChromeFor(.japanese, "").copy_path, paletteFor(.japanese, "").copy_project_path));
}

test "reviewDiffChromeFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("Review", reviewDiffChromeFor(.english, "ja").review_title);
    try testing.expectEqualStrings("Cancel", reviewDiffChromeFor(.english, "").cancel);
    try testing.expectEqualStrings("Branch", reviewDiffChromeFor(.english, "").branch);
    try testing.expectEqualStrings("Uncommitted", reviewDiffChromeFor(.english, "").uncommitted);
    try testing.expectEqualStrings("Staged", reviewDiffChromeFor(.english, "").staged);
    try testing.expectEqualStrings("Unstaged", reviewDiffChromeFor(.english, "").unstaged);
    try testing.expectEqualStrings("Committed", reviewDiffChromeFor(.english, "").committed);
    try testing.expectEqualStrings("Last turn", reviewDiffChromeFor(.english, "").last_turn);
    try testing.expectEqualStrings("Start", reviewDiffChromeFor(.english, "").gap_expand_start);
    try testing.expectEqualStrings("End", reviewDiffChromeFor(.english, "").gap_expand_end);
    try testing.expectEqualStrings("Both", reviewDiffChromeFor(.english, "").gap_expand_both);
    try testing.expectEqualStrings("All", reviewDiffChromeFor(.english, "").gap_expand_all);
    try testing.expectEqualStrings("Review", reviewDiffChromeFor(.system, "").review_title);
    try testing.expectEqualStrings(rightPanelTabsFor(.english, "").diff, reviewDiffChromeFor(.english, "").review_title);

    try testing.expectEqualStrings("审阅", reviewDiffChromeFor(.simplified_chinese, "").review_title);
    try testing.expectEqualStrings("取消", reviewDiffChromeFor(.simplified_chinese, "").cancel);
    try testing.expectEqualStrings("分支", reviewDiffChromeFor(.simplified_chinese, "").branch);
    try testing.expectEqualStrings("未提交", reviewDiffChromeFor(.simplified_chinese, "").uncommitted);
    try testing.expectEqualStrings("已暂存", reviewDiffChromeFor(.simplified_chinese, "").staged);
    try testing.expectEqualStrings("未暂存", reviewDiffChromeFor(.simplified_chinese, "").unstaged);
    try testing.expectEqualStrings("已提交", reviewDiffChromeFor(.simplified_chinese, "").committed);
    try testing.expectEqualStrings("上一轮", reviewDiffChromeFor(.simplified_chinese, "").last_turn);
    try testing.expectEqualStrings("开头", reviewDiffChromeFor(.simplified_chinese, "").gap_expand_start);
    try testing.expectEqualStrings("末尾", reviewDiffChromeFor(.simplified_chinese, "").gap_expand_end);
    try testing.expectEqualStrings("两端", reviewDiffChromeFor(.simplified_chinese, "").gap_expand_both);
    try testing.expectEqualStrings("全部", reviewDiffChromeFor(.simplified_chinese, "").gap_expand_all);
    try testing.expectEqualStrings(rightPanelTabsFor(.simplified_chinese, "").diff, reviewDiffChromeFor(.simplified_chinese, "").review_title);

    try testing.expectEqualStrings("レビュー", reviewDiffChromeFor(.japanese, "").review_title);
    try testing.expectEqualStrings("キャンセル", reviewDiffChromeFor(.japanese, "").cancel);
    try testing.expectEqualStrings("ブランチ", reviewDiffChromeFor(.japanese, "").branch);
    try testing.expectEqualStrings("未コミット", reviewDiffChromeFor(.japanese, "").uncommitted);
    try testing.expectEqualStrings("ステージ済み", reviewDiffChromeFor(.japanese, "").staged);
    try testing.expectEqualStrings("未ステージ", reviewDiffChromeFor(.japanese, "").unstaged);
    try testing.expectEqualStrings("コミット済み", reviewDiffChromeFor(.japanese, "").committed);
    try testing.expectEqualStrings("直前のターン", reviewDiffChromeFor(.japanese, "").last_turn);
    try testing.expectEqualStrings("先頭", reviewDiffChromeFor(.japanese, "").gap_expand_start);
    try testing.expectEqualStrings("末尾", reviewDiffChromeFor(.japanese, "").gap_expand_end);
    try testing.expectEqualStrings("両端", reviewDiffChromeFor(.japanese, "").gap_expand_both);
    try testing.expectEqualStrings("すべて", reviewDiffChromeFor(.japanese, "").gap_expand_all);
    try testing.expectEqualStrings(rightPanelTabsFor(.japanese, "").diff, reviewDiffChromeFor(.japanese, "").review_title);

    try testing.expectEqualStrings("审阅", reviewDiffChromeFor(.system, "zh_CN.UTF-8").review_title);
    try testing.expectEqualStrings("取消", reviewDiffChromeFor(.system, "zh_CN.UTF-8").cancel);
    try testing.expectEqualStrings("上一轮", reviewDiffChromeFor(.system, "zh_CN.UTF-8").last_turn);
    try testing.expectEqualStrings("开头", reviewDiffChromeFor(.system, "zh_CN.UTF-8").gap_expand_start);
    try testing.expectEqualStrings("末尾", reviewDiffChromeFor(.system, "zh_CN.UTF-8").gap_expand_end);
    try testing.expectEqualStrings("两端", reviewDiffChromeFor(.system, "zh_CN.UTF-8").gap_expand_both);
    try testing.expectEqualStrings("全部", reviewDiffChromeFor(.system, "zh_CN.UTF-8").gap_expand_all);
    try testing.expectEqualStrings("レビュー", reviewDiffChromeFor(.system, "ja_JP.UTF-8").review_title);
    try testing.expectEqualStrings("キャンセル", reviewDiffChromeFor(.system, "ja_JP.UTF-8").cancel);
    try testing.expectEqualStrings("直前のターン", reviewDiffChromeFor(.system, "ja_JP.UTF-8").last_turn);
    try testing.expectEqualStrings("先頭", reviewDiffChromeFor(.system, "ja_JP.UTF-8").gap_expand_start);
    try testing.expectEqualStrings("末尾", reviewDiffChromeFor(.system, "ja_JP.UTF-8").gap_expand_end);
    try testing.expectEqualStrings("両端", reviewDiffChromeFor(.system, "ja_JP.UTF-8").gap_expand_both);
    try testing.expectEqualStrings("すべて", reviewDiffChromeFor(.system, "ja_JP.UTF-8").gap_expand_all);
    try testing.expectEqualStrings("Review", reviewDiffChromeFor(.english, "ja_JP.UTF-8").review_title);
    try testing.expectEqualStrings("Cancel", reviewDiffChromeFor(.english, "zh_CN.UTF-8").cancel);
    try testing.expectEqualStrings("Branch", reviewDiffChromeFor(.english, "ja_JP.UTF-8").branch);
    try testing.expectEqualStrings("Uncommitted", reviewDiffChromeFor(.english, "zh_CN.UTF-8").uncommitted);
    try testing.expectEqualStrings("Staged", reviewDiffChromeFor(.english, "ja_JP.UTF-8").staged);
    try testing.expectEqualStrings("Unstaged", reviewDiffChromeFor(.english, "zh_CN.UTF-8").unstaged);
    try testing.expectEqualStrings("Committed", reviewDiffChromeFor(.english, "ja_JP.UTF-8").committed);
    try testing.expectEqualStrings("Last turn", reviewDiffChromeFor(.english, "zh_CN.UTF-8").last_turn);
    try testing.expectEqualStrings("Start", reviewDiffChromeFor(.english, "ja_JP.UTF-8").gap_expand_start);
    try testing.expectEqualStrings("End", reviewDiffChromeFor(.english, "zh_CN.UTF-8").gap_expand_end);
    try testing.expectEqualStrings("Both", reviewDiffChromeFor(.english, "ja_JP.UTF-8").gap_expand_both);
    try testing.expectEqualStrings("All", reviewDiffChromeFor(.english, "zh_CN.UTF-8").gap_expand_all);
}

test "backgroundChromeFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("Process", backgroundChromeFor(.english, "ja").kind_process);
    try testing.expectEqualStrings("Monitor", backgroundChromeFor(.english, "").kind_monitor);
    try testing.expectEqualStrings("Subagent", backgroundChromeFor(.english, "").kind_subagent);
    try testing.expectEqualStrings("Agent turn", backgroundChromeFor(.english, "").process_row);
    try testing.expectEqualStrings("Completed", backgroundChromeFor(.english, "").settled_completed);
    try testing.expectEqualStrings("Stopped", backgroundChromeFor(.english, "").settled_stopped);
    try testing.expectEqualStrings("Failed", backgroundChromeFor(.english, "").settled_failed);
    try testing.expectEqualStrings("Running", backgroundChromeFor(.english, "").live_running);
    try testing.expectEqualStrings("Monitoring", backgroundChromeFor(.english, "").live_monitoring);
    try testing.expectEqualStrings("Stopping", backgroundChromeFor(.english, "").live_stopping);
    try testing.expectEqualStrings("Stop agent", backgroundChromeFor(.english, "").process_stop);
    try testing.expectEqualStrings("Stop monitor", backgroundChromeFor(.english, "").monitor_stop);
    try testing.expectEqualStrings("Dismiss monitor", backgroundChromeFor(.english, "").monitor_dismiss);
    try testing.expectEqualStrings("Stop subagent", backgroundChromeFor(.english, "").subagent_stop);
    try testing.expectEqualStrings("Dismiss subagent", backgroundChromeFor(.english, "").subagent_dismiss);
    try testing.expectEqualStrings("Stop", backgroundChromeFor(.english, "").daemon_stop);
    try testing.expectEqualStrings("Dismiss", backgroundChromeFor(.english, "").daemon_dismiss);
    try testing.expectEqualStrings("Process", backgroundChromeFor(.system, "").kind_process);

    try testing.expectEqualStrings("进程", backgroundChromeFor(.simplified_chinese, "").kind_process);
    try testing.expectEqualStrings("监视器", backgroundChromeFor(.simplified_chinese, "").kind_monitor);
    try testing.expectEqualStrings("子代理", backgroundChromeFor(.simplified_chinese, "").kind_subagent);
    try testing.expectEqualStrings("代理轮次", backgroundChromeFor(.simplified_chinese, "").process_row);
    try testing.expectEqualStrings("已完成", backgroundChromeFor(.simplified_chinese, "").settled_completed);
    try testing.expectEqualStrings("已停止", backgroundChromeFor(.simplified_chinese, "").settled_stopped);
    try testing.expectEqualStrings("失败", backgroundChromeFor(.simplified_chinese, "").settled_failed);
    try testing.expectEqualStrings("运行中", backgroundChromeFor(.simplified_chinese, "").live_running);
    try testing.expectEqualStrings("监视中", backgroundChromeFor(.simplified_chinese, "").live_monitoring);
    try testing.expectEqualStrings("正在停止", backgroundChromeFor(.simplified_chinese, "").live_stopping);
    try testing.expectEqualStrings("停止代理", backgroundChromeFor(.simplified_chinese, "").process_stop);
    try testing.expectEqualStrings("停止监视器", backgroundChromeFor(.simplified_chinese, "").monitor_stop);
    try testing.expectEqualStrings("关闭监视器", backgroundChromeFor(.simplified_chinese, "").monitor_dismiss);
    try testing.expectEqualStrings("停止子代理", backgroundChromeFor(.simplified_chinese, "").subagent_stop);
    try testing.expectEqualStrings("关闭子代理", backgroundChromeFor(.simplified_chinese, "").subagent_dismiss);
    try testing.expectEqualStrings("停止", backgroundChromeFor(.simplified_chinese, "").daemon_stop);
    try testing.expectEqualStrings("关闭", backgroundChromeFor(.simplified_chinese, "").daemon_dismiss);

    try testing.expectEqualStrings("プロセス", backgroundChromeFor(.japanese, "").kind_process);
    try testing.expectEqualStrings("モニター", backgroundChromeFor(.japanese, "").kind_monitor);
    try testing.expectEqualStrings("サブエージェント", backgroundChromeFor(.japanese, "").kind_subagent);
    try testing.expectEqualStrings("エージェントのターン", backgroundChromeFor(.japanese, "").process_row);
    try testing.expectEqualStrings("完了", backgroundChromeFor(.japanese, "").settled_completed);
    try testing.expectEqualStrings("停止済み", backgroundChromeFor(.japanese, "").settled_stopped);
    try testing.expectEqualStrings("失敗", backgroundChromeFor(.japanese, "").settled_failed);
    try testing.expectEqualStrings("実行中", backgroundChromeFor(.japanese, "").live_running);
    try testing.expectEqualStrings("監視中", backgroundChromeFor(.japanese, "").live_monitoring);
    try testing.expectEqualStrings("停止中", backgroundChromeFor(.japanese, "").live_stopping);
    try testing.expectEqualStrings("エージェントを停止", backgroundChromeFor(.japanese, "").process_stop);
    try testing.expectEqualStrings("モニターを停止", backgroundChromeFor(.japanese, "").monitor_stop);
    try testing.expectEqualStrings("モニターを閉じる", backgroundChromeFor(.japanese, "").monitor_dismiss);
    try testing.expectEqualStrings("サブエージェントを停止", backgroundChromeFor(.japanese, "").subagent_stop);
    try testing.expectEqualStrings("サブエージェントを閉じる", backgroundChromeFor(.japanese, "").subagent_dismiss);
    try testing.expectEqualStrings("停止", backgroundChromeFor(.japanese, "").daemon_stop);
    try testing.expectEqualStrings("閉じる", backgroundChromeFor(.japanese, "").daemon_dismiss);

    try testing.expectEqualStrings("进程", backgroundChromeFor(.system, "zh_CN.UTF-8").kind_process);
    try testing.expectEqualStrings("关闭监视器", backgroundChromeFor(.system, "zh_CN.UTF-8").monitor_dismiss);
    try testing.expectEqualStrings("代理轮次", backgroundChromeFor(.system, "zh_CN.UTF-8").process_row);
    try testing.expectEqualStrings("プロセス", backgroundChromeFor(.system, "ja_JP.UTF-8").kind_process);
    try testing.expectEqualStrings("モニターを閉じる", backgroundChromeFor(.system, "ja_JP.UTF-8").monitor_dismiss);
    try testing.expectEqualStrings("エージェントのターン", backgroundChromeFor(.system, "ja_JP.UTF-8").process_row);
    try testing.expectEqualStrings("Process", backgroundChromeFor(.english, "ja_JP.UTF-8").kind_process);
    try testing.expectEqualStrings("Monitor", backgroundChromeFor(.english, "zh_CN.UTF-8").kind_monitor);
    try testing.expectEqualStrings("Subagent", backgroundChromeFor(.english, "ja_JP.UTF-8").kind_subagent);
    try testing.expectEqualStrings("Agent turn", backgroundChromeFor(.english, "zh_CN.UTF-8").process_row);
    try testing.expectEqualStrings("Completed", backgroundChromeFor(.english, "ja_JP.UTF-8").settled_completed);
    try testing.expectEqualStrings("Stopped", backgroundChromeFor(.english, "zh_CN.UTF-8").settled_stopped);
    try testing.expectEqualStrings("Failed", backgroundChromeFor(.english, "ja_JP.UTF-8").settled_failed);
    try testing.expectEqualStrings("Running", backgroundChromeFor(.english, "zh_CN.UTF-8").live_running);
    try testing.expectEqualStrings("Monitoring", backgroundChromeFor(.english, "ja_JP.UTF-8").live_monitoring);
    try testing.expectEqualStrings("Stopping", backgroundChromeFor(.english, "zh_CN.UTF-8").live_stopping);
    try testing.expectEqualStrings("Stop agent", backgroundChromeFor(.english, "ja_JP.UTF-8").process_stop);
    try testing.expectEqualStrings("Stop monitor", backgroundChromeFor(.english, "zh_CN.UTF-8").monitor_stop);
    try testing.expectEqualStrings("Dismiss monitor", backgroundChromeFor(.english, "ja_JP.UTF-8").monitor_dismiss);
    try testing.expectEqualStrings("Stop subagent", backgroundChromeFor(.english, "zh_CN.UTF-8").subagent_stop);
    try testing.expectEqualStrings("Dismiss subagent", backgroundChromeFor(.english, "ja_JP.UTF-8").subagent_dismiss);
    try testing.expectEqualStrings("Stop", backgroundChromeFor(.english, "zh_CN.UTF-8").daemon_stop);
    try testing.expectEqualStrings("Dismiss", backgroundChromeFor(.english, "ja_JP.UTF-8").daemon_dismiss);

    try testing.expectEqualStrings(rightPanelChromeFor(.english, "").no_background_work, "No background work");
    try testing.expectEqualStrings(rightPanelChromeFor(.english, "").no_output, "No output");
}

test "environmentChromeFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("Environment", environmentChromeFor(.english, "ja").environment);
    try testing.expectEqualStrings("Commit or Push", environmentChromeFor(.english, "").commit_or_push);
    try testing.expectEqualStrings("Compare", environmentChromeFor(.english, "").compare);
    try testing.expectEqualStrings("Copy task ID", environmentChromeFor(.english, "").copy_task_id);
    try testing.expectEqualStrings("Copy agent CLI thread ID", environmentChromeFor(.english, "").copy_agent_thread_id);
    try testing.expectEqualStrings("Dismiss all settled", environmentChromeFor(.english, "").dismiss_all_settled);
    try testing.expectEqualStrings("Environment", environmentChromeFor(.system, "").environment);

    try testing.expectEqualStrings("环境", environmentChromeFor(.simplified_chinese, "").environment);
    try testing.expectEqualStrings("提交或推送", environmentChromeFor(.simplified_chinese, "").commit_or_push);
    try testing.expectEqualStrings("比较", environmentChromeFor(.simplified_chinese, "").compare);
    try testing.expectEqualStrings("复制任务 ID", environmentChromeFor(.simplified_chinese, "").copy_task_id);
    try testing.expectEqualStrings("复制代理 CLI 线程 ID", environmentChromeFor(.simplified_chinese, "").copy_agent_thread_id);
    try testing.expectEqualStrings("关闭全部已结束项", environmentChromeFor(.simplified_chinese, "").dismiss_all_settled);

    try testing.expectEqualStrings("環境", environmentChromeFor(.japanese, "").environment);
    try testing.expectEqualStrings("コミットまたはプッシュ", environmentChromeFor(.japanese, "").commit_or_push);
    try testing.expectEqualStrings("比較", environmentChromeFor(.japanese, "").compare);
    try testing.expectEqualStrings("タスク ID をコピー", environmentChromeFor(.japanese, "").copy_task_id);
    try testing.expectEqualStrings("エージェント CLI スレッド ID をコピー", environmentChromeFor(.japanese, "").copy_agent_thread_id);
    try testing.expectEqualStrings("終了した項目をすべて閉じる", environmentChromeFor(.japanese, "").dismiss_all_settled);

    try testing.expectEqualStrings("环境", environmentChromeFor(.system, "zh_CN.UTF-8").environment);
    try testing.expectEqualStrings("提交或推送", environmentChromeFor(.system, "zh_CN.UTF-8").commit_or_push);
    try testing.expectEqualStrings("关闭全部已结束项", environmentChromeFor(.system, "zh_CN.UTF-8").dismiss_all_settled);
    try testing.expectEqualStrings("環境", environmentChromeFor(.system, "ja_JP.UTF-8").environment);
    try testing.expectEqualStrings("コミットまたはプッシュ", environmentChromeFor(.system, "ja_JP.UTF-8").commit_or_push);
    try testing.expectEqualStrings("終了した項目をすべて閉じる", environmentChromeFor(.system, "ja_JP.UTF-8").dismiss_all_settled);
    try testing.expectEqualStrings("Environment", environmentChromeFor(.english, "ja_JP.UTF-8").environment);
    try testing.expectEqualStrings("Commit or Push", environmentChromeFor(.english, "zh_CN.UTF-8").commit_or_push);
    try testing.expectEqualStrings("Compare", environmentChromeFor(.english, "ja_JP.UTF-8").compare);
    try testing.expectEqualStrings("Copy task ID", environmentChromeFor(.english, "zh_CN.UTF-8").copy_task_id);
    try testing.expectEqualStrings("Copy agent CLI thread ID", environmentChromeFor(.english, "ja_JP.UTF-8").copy_agent_thread_id);
    try testing.expectEqualStrings("Dismiss all settled", environmentChromeFor(.english, "zh_CN.UTF-8").dismiss_all_settled);
}

test "filterChromeFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("Filter skills", filterChromeFor(.english, "ja").filter_skills);
    try testing.expectEqualStrings("Filter projects", filterChromeFor(.english, "").filter_projects);
    try testing.expectEqualStrings("No project usage", filterChromeFor(.english, "").no_project_usage);
    try testing.expectEqualStrings("Filter skills", filterChromeFor(.system, "").filter_skills);
    try testing.expectEqualStrings("Filter projects", filterChromeFor(.system, "").filter_projects);
    try testing.expectEqualStrings("No project usage", filterChromeFor(.system, "").no_project_usage);

    try testing.expectEqualStrings("筛选技能", filterChromeFor(.simplified_chinese, "").filter_skills);
    try testing.expectEqualStrings("筛选项目", filterChromeFor(.simplified_chinese, "").filter_projects);
    try testing.expectEqualStrings("没有项目用量", filterChromeFor(.simplified_chinese, "").no_project_usage);

    try testing.expectEqualStrings("スキルを絞り込む", filterChromeFor(.japanese, "").filter_skills);
    try testing.expectEqualStrings("プロジェクトを絞り込む", filterChromeFor(.japanese, "").filter_projects);
    try testing.expectEqualStrings("プロジェクトの使用量はありません", filterChromeFor(.japanese, "").no_project_usage);

    try testing.expectEqualStrings("筛选技能", filterChromeFor(.system, "zh_CN.UTF-8").filter_skills);
    try testing.expectEqualStrings("筛选项目", filterChromeFor(.system, "zh_CN.UTF-8").filter_projects);
    try testing.expectEqualStrings("没有项目用量", filterChromeFor(.system, "zh_CN.UTF-8").no_project_usage);
    try testing.expectEqualStrings("スキルを絞り込む", filterChromeFor(.system, "ja_JP.UTF-8").filter_skills);
    try testing.expectEqualStrings("プロジェクトを絞り込む", filterChromeFor(.system, "ja_JP.UTF-8").filter_projects);
    try testing.expectEqualStrings("プロジェクトの使用量はありません", filterChromeFor(.system, "ja_JP.UTF-8").no_project_usage);
    try testing.expectEqualStrings("Filter skills", filterChromeFor(.english, "ja_JP.UTF-8").filter_skills);
    try testing.expectEqualStrings("Filter projects", filterChromeFor(.english, "zh_CN.UTF-8").filter_projects);
    try testing.expectEqualStrings("No project usage", filterChromeFor(.english, "ja_JP.UTF-8").no_project_usage);
}

test "filePreviewChromeFor english default; zh and ja chrome; english ignores ja LANG" {
    const testing = std.testing;
    try testing.expectEqualStrings("Unsaved", filePreviewChromeFor(.english, "ja").unsaved);
    try testing.expectEqualStrings("Preview", filePreviewChromeFor(.english, "").preview);
    try testing.expectEqualStrings("Source", filePreviewChromeFor(.english, "").source);
    try testing.expectEqualStrings("Edit", filePreviewChromeFor(.english, "").edit);
    try testing.expectEqualStrings("Save", filePreviewChromeFor(.english, "").save);
    try testing.expectEqualStrings("Reload", filePreviewChromeFor(.english, "").reload);
    try testing.expectEqualStrings("Open in editor", filePreviewChromeFor(.english, "").open_in_editor);
    try testing.expectEqualStrings("Close", filePreviewChromeFor(.english, "").close);
    try testing.expectEqualStrings("Hide replace", filePreviewChromeFor(.english, "").hide_replace);
    try testing.expectEqualStrings("Show replace", filePreviewChromeFor(.english, "").show_replace);
    try testing.expectEqualStrings("Find", filePreviewChromeFor(.english, "").find);
    try testing.expectEqualStrings("Find in file", filePreviewChromeFor(.english, "").find_in_file);
    try testing.expectEqualStrings("Previous file match", filePreviewChromeFor(.english, "").previous_file_match);
    try testing.expectEqualStrings("Next file match", filePreviewChromeFor(.english, "").next_file_match);
    try testing.expectEqualStrings("Close file find", filePreviewChromeFor(.english, "").close_file_find);
    try testing.expectEqualStrings("Replace", filePreviewChromeFor(.english, "").replace);
    try testing.expectEqualStrings("Replace in file", filePreviewChromeFor(.english, "").replace_in_file);
    try testing.expectEqualStrings("Replace all", filePreviewChromeFor(.english, "").replace_all);
    try testing.expectEqualStrings("Read-only", filePreviewChromeFor(.english, "").read_only);
    try testing.expectEqualStrings("Discard unsaved changes?", filePreviewChromeFor(.english, "").discard_unsaved);
    try testing.expectEqualStrings("Discard", filePreviewChromeFor(.english, "").discard);
    try testing.expectEqualStrings("Keep editing", filePreviewChromeFor(.english, "").keep_editing);
    try testing.expectEqualStrings("Truncated — showing first 256 KB", filePreviewChromeFor(.english, "").truncated);
    try testing.expectEqualStrings("Binary file — not shown", filePreviewChromeFor(.english, "").binary_file);
    try testing.expectEqualStrings("Unsaved", filePreviewChromeFor(.system, "").unsaved);
    try testing.expectEqualStrings("Find in file", filePreviewChromeFor(.system, "").find_in_file);
    try testing.expect(!std.mem.eql(u8, filePreviewChromeFor(.english, "").open_in_editor, composerProjectChromeFor(.english, "").open_in_editor));

    try testing.expectEqualStrings("未保存", filePreviewChromeFor(.simplified_chinese, "").unsaved);
    try testing.expectEqualStrings("预览", filePreviewChromeFor(.simplified_chinese, "").preview);
    try testing.expectEqualStrings("源码", filePreviewChromeFor(.simplified_chinese, "").source);
    try testing.expectEqualStrings("编辑", filePreviewChromeFor(.simplified_chinese, "").edit);
    try testing.expectEqualStrings("保存", filePreviewChromeFor(.simplified_chinese, "").save);
    try testing.expectEqualStrings("重新加载", filePreviewChromeFor(.simplified_chinese, "").reload);
    try testing.expectEqualStrings("在编辑器中打开", filePreviewChromeFor(.simplified_chinese, "").open_in_editor);
    try testing.expectEqualStrings("关闭", filePreviewChromeFor(.simplified_chinese, "").close);
    try testing.expectEqualStrings("隐藏替换", filePreviewChromeFor(.simplified_chinese, "").hide_replace);
    try testing.expectEqualStrings("显示替换", filePreviewChromeFor(.simplified_chinese, "").show_replace);
    try testing.expectEqualStrings("查找", filePreviewChromeFor(.simplified_chinese, "").find);
    try testing.expectEqualStrings("在文件中查找", filePreviewChromeFor(.simplified_chinese, "").find_in_file);
    try testing.expectEqualStrings("上一个文件匹配", filePreviewChromeFor(.simplified_chinese, "").previous_file_match);
    try testing.expectEqualStrings("下一个文件匹配", filePreviewChromeFor(.simplified_chinese, "").next_file_match);
    try testing.expectEqualStrings("关闭文件查找", filePreviewChromeFor(.simplified_chinese, "").close_file_find);
    try testing.expectEqualStrings("替换", filePreviewChromeFor(.simplified_chinese, "").replace);
    try testing.expectEqualStrings("在文件中替换", filePreviewChromeFor(.simplified_chinese, "").replace_in_file);
    try testing.expectEqualStrings("全部替换", filePreviewChromeFor(.simplified_chinese, "").replace_all);
    try testing.expectEqualStrings("只读", filePreviewChromeFor(.simplified_chinese, "").read_only);
    try testing.expectEqualStrings("放弃未保存的更改？", filePreviewChromeFor(.simplified_chinese, "").discard_unsaved);
    try testing.expectEqualStrings("放弃", filePreviewChromeFor(.simplified_chinese, "").discard);
    try testing.expectEqualStrings("继续编辑", filePreviewChromeFor(.simplified_chinese, "").keep_editing);
    try testing.expectEqualStrings("已截断 — 仅显示前 256 KB", filePreviewChromeFor(.simplified_chinese, "").truncated);
    try testing.expectEqualStrings("二进制文件 — 未显示", filePreviewChromeFor(.simplified_chinese, "").binary_file);

    try testing.expectEqualStrings("未保存", filePreviewChromeFor(.japanese, "").unsaved);
    try testing.expectEqualStrings("プレビュー", filePreviewChromeFor(.japanese, "").preview);
    try testing.expectEqualStrings("ソース", filePreviewChromeFor(.japanese, "").source);
    try testing.expectEqualStrings("編集", filePreviewChromeFor(.japanese, "").edit);
    try testing.expectEqualStrings("保存", filePreviewChromeFor(.japanese, "").save);
    try testing.expectEqualStrings("再読み込み", filePreviewChromeFor(.japanese, "").reload);
    try testing.expectEqualStrings("エディターで開く", filePreviewChromeFor(.japanese, "").open_in_editor);
    try testing.expectEqualStrings("閉じる", filePreviewChromeFor(.japanese, "").close);
    try testing.expectEqualStrings("置換を隠す", filePreviewChromeFor(.japanese, "").hide_replace);
    try testing.expectEqualStrings("置換を表示", filePreviewChromeFor(.japanese, "").show_replace);
    try testing.expectEqualStrings("検索", filePreviewChromeFor(.japanese, "").find);
    try testing.expectEqualStrings("ファイル内を検索", filePreviewChromeFor(.japanese, "").find_in_file);
    try testing.expectEqualStrings("前のファイル一致", filePreviewChromeFor(.japanese, "").previous_file_match);
    try testing.expectEqualStrings("次のファイル一致", filePreviewChromeFor(.japanese, "").next_file_match);
    try testing.expectEqualStrings("ファイル検索を閉じる", filePreviewChromeFor(.japanese, "").close_file_find);
    try testing.expectEqualStrings("置換", filePreviewChromeFor(.japanese, "").replace);
    try testing.expectEqualStrings("ファイル内を置換", filePreviewChromeFor(.japanese, "").replace_in_file);
    try testing.expectEqualStrings("すべて置換", filePreviewChromeFor(.japanese, "").replace_all);
    try testing.expectEqualStrings("読み取り専用", filePreviewChromeFor(.japanese, "").read_only);
    try testing.expectEqualStrings("未保存の変更を破棄しますか？", filePreviewChromeFor(.japanese, "").discard_unsaved);
    try testing.expectEqualStrings("破棄", filePreviewChromeFor(.japanese, "").discard);
    try testing.expectEqualStrings("編集を続ける", filePreviewChromeFor(.japanese, "").keep_editing);
    try testing.expectEqualStrings("切り詰め済み — 先頭 256 KB を表示", filePreviewChromeFor(.japanese, "").truncated);
    try testing.expectEqualStrings("バイナリファイル — 非表示", filePreviewChromeFor(.japanese, "").binary_file);

    try testing.expectEqualStrings("未保存", filePreviewChromeFor(.system, "zh_CN.UTF-8").unsaved);
    try testing.expectEqualStrings("在文件中查找", filePreviewChromeFor(.system, "zh_CN.UTF-8").find_in_file);
    try testing.expectEqualStrings("放弃未保存的更改？", filePreviewChromeFor(.system, "zh_CN.UTF-8").discard_unsaved);
    try testing.expectEqualStrings("未保存", filePreviewChromeFor(.system, "ja_JP.UTF-8").unsaved);
    try testing.expectEqualStrings("ファイル内を検索", filePreviewChromeFor(.system, "ja_JP.UTF-8").find_in_file);
    try testing.expectEqualStrings("未保存の変更を破棄しますか？", filePreviewChromeFor(.system, "ja_JP.UTF-8").discard_unsaved);
    try testing.expectEqualStrings("Unsaved", filePreviewChromeFor(.english, "ja_JP.UTF-8").unsaved);
    try testing.expectEqualStrings("Open in editor", filePreviewChromeFor(.english, "zh_CN.UTF-8").open_in_editor);
    try testing.expectEqualStrings("Find in file", filePreviewChromeFor(.english, "ja_JP.UTF-8").find_in_file);
    try testing.expectEqualStrings("Keep editing", filePreviewChromeFor(.english, "zh_CN.UTF-8").keep_editing);
    try testing.expectEqualStrings("Binary file — not shown", filePreviewChromeFor(.english, "ja_JP.UTF-8").binary_file);
}

