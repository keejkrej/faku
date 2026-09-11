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
//! reuses `RightPanelChrome.open_in_terminal`) live here so
//! `main.zig` does not grow. Palette ids / `PaletteAction` / keywords
//! stay English. Wire `access_mode` ids stay `ask` / `auto` /
//! `fullAccess`. Wire `reasoning_effort` ids stay `auto` / `none` /
//! `minimal` / `low` / `medium` / `high` / `xhigh` / `max`. Wire
//! `interaction_mode` ids stay `build` / `plan`. Wire
//! `right_panel_tab` ids stay `files` / `diff` / `browser` /
//! `terminal` / `background`. Diff filter `on-input` and filter text
//! stay English. Open in browser / Open in Terminal `on-press` stay
//! `open_url` / `open_terminal`. Composer Pick folder / Reveal folder /
//! Open in Editor / Copy path `on-press` stay `pick_folder` /
//! `reveal_folder` / `open_editor` / `copy_project_path`. Not rust_i18n,
//! not YAML catalogs, not full-app translation, not tz-aware grouping.

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
/// `RightPanelChrome`. Pane `label=` attributes and remaining
/// Background row chrome stay English.
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
/// reuses `open_in_terminal`. Remaining Background row chrome stays
/// English.
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
