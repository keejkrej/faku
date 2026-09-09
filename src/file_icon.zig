//! First-cut file-type icon names for Files, Diff, and composer `@`
//! mention rows.
//!
//! Behavior follows Waku `file_icon_for_path` / `file_icon_for_name`
//! (basename specials, then extension) and maps onto a curated MIT
//! Material app-icon subset (`app:zig`, `app:rust`, … from
//! `src/icons/file-types/`) plus Native built-ins for directories
//! (`folder` / `folder-open`), shells (`terminal`), archives
//! (`archive`), audio (`music`), leftover config (`settings`), and
//! unknown files (`file-text`). Diff tree rows, the selected-file
//! Diff header, and composer `@` mention rows reuse this same map
//! (dirs stay `folder` in `@`; the list has no expand chevron).
//! Browser and Terminal do not.

const std = @import("std");
const composer = @import("composer.zig");
const file_type_icons = @import("file_type_icons.zig");

fn app(comptime name: []const u8) []const u8 {
    return "app:" ++ name;
}

/// Native `icon name=` for a Files, Diff, or composer `@` row.
pub fn filesTreeIcon(path: []const u8, is_file: bool, expanded: bool) []const u8 {
    if (!is_file) {
        return if (expanded) "folder-open" else "folder";
    }
    return fileIconForPath(path);
}

/// Native built-in or `app:` name for a file path (basename of a
/// repo-relative path).
pub fn fileIconForPath(path: []const u8) []const u8 {
    return fileIconForName(composer.fileMentionBasename(path));
}

/// Native built-in or `app:` name for a file basename.
/// Case-insensitive, like Waku.
pub fn fileIconForName(name: []const u8) []const u8 {
    if (basenameSpecial(name)) |icon| return icon;

    const ext = extensionOf(name);
    if (extensionIs(ext, &.{ "sh", "bash", "zsh", "fish", "ps1", "psm1" })) return "terminal";
    if (extensionIs(ext, &.{ "zip", "tar", "gz", "tgz", "7z", "rar" })) return "archive";
    if (extensionIs(ext, &.{ "mp3", "wav", "ogg", "flac", "m4a" })) return "music";
    if (extensionIs(ext, &.{ "zig" })) return app("zig");
    if (extensionIs(ext, &.{ "rs" })) return app("rust");
    if (extensionIs(ext, &.{ "go" })) return app("go");
    if (extensionIs(ext, &.{ "py", "pyi", "pyw" })) return app("python");
    if (extensionIs(ext, &.{ "js", "mjs", "cjs" })) return app("javascript");
    if (extensionIs(ext, &.{ "ts", "mts", "cts" })) return app("typescript");
    if (extensionIs(ext, &.{ "jsx", "tsx" })) return app("react");
    if (extensionIs(ext, &.{ "vue" })) return app("vue");
    if (extensionIs(ext, &.{ "svelte" })) return app("svelte");
    if (extensionIs(ext, &.{ "html", "htm" })) return app("html");
    if (extensionIs(ext, &.{ "css" })) return app("css");
    if (extensionIs(ext, &.{ "md", "mdx", "markdown" })) return app("markdown");
    if (extensionIs(ext, &.{ "json", "jsonc", "jsonl" })) return app("json");
    if (extensionIs(ext, &.{ "yaml", "yml" })) return app("yaml");
    if (extensionIs(ext, &.{ "xml", "xsl", "plist" })) return app("xml");
    if (extensionIs(ext, &.{ "png", "jpg", "jpeg", "gif", "webp", "avif", "ico", "tiff" })) return app("image");
    if (extensionIs(ext, &.{ "c", "h" })) return app("c");
    if (extensionIs(ext, &.{ "cc", "cpp", "cxx", "hh", "hpp", "hxx" })) return app("cpp");
    if (extensionIs(ext, &.{ "java" })) return app("java");
    if (extensionIs(ext, &.{ "ini", "cfg", "conf", "config", "toml" })) return "settings";
    return "file-text";
}

fn basenameSpecial(name: []const u8) ?[]const u8 {
    if (startsWithIgnoreCase(name, "readme")) return app("readme");
    if (isDockerfileName(name)) return app("docker");
    if (isMakefileName(name)) return app("makefile");
    if (std.ascii.eqlIgnoreCase(name, "Cargo.toml") or
        std.ascii.eqlIgnoreCase(name, "Cargo.lock") or
        std.ascii.eqlIgnoreCase(name, "rust-toolchain.toml")) return app("rust");
    if (std.ascii.eqlIgnoreCase(name, "go.mod") or
        std.ascii.eqlIgnoreCase(name, "go.sum") or
        std.ascii.eqlIgnoreCase(name, "go.work")) return app("go");
    if (std.ascii.eqlIgnoreCase(name, "package.json")) return app("nodejs");
    if (startsWithIgnoreCase(name, "tsconfig.") or std.ascii.eqlIgnoreCase(name, "tsconfig.json"))
        return app("typescript");
    if (startsWithIgnoreCase(name, ".git")) return app("git");
    if (isSettingsName(name)) return "settings";
    return null;
}

fn isMakefileName(name: []const u8) bool {
    return std.ascii.eqlIgnoreCase(name, "Makefile") or
        std.ascii.eqlIgnoreCase(name, "GNUmakefile") or
        std.ascii.eqlIgnoreCase(name, "justfile") or
        startsWithIgnoreCase(name, "makefile.");
}

fn isDockerfileName(name: []const u8) bool {
    return startsWithIgnoreCase(name, "dockerfile") or
        std.ascii.eqlIgnoreCase(name, "Containerfile") or
        startsWithIgnoreCase(name, "compose.");
}

fn isSettingsName(name: []const u8) bool {
    return startsWithIgnoreCase(name, ".env") or
        std.ascii.eqlIgnoreCase(name, ".editorconfig");
}

fn extensionOf(name: []const u8) []const u8 {
    if (std.mem.lastIndexOfScalar(u8, name, '.')) |dot| {
        if (dot == 0 or dot + 1 >= name.len) return "";
        return name[dot + 1 ..];
    }
    return "";
}

fn extensionIs(ext: []const u8, comptime options: []const []const u8) bool {
    inline for (options) |option| {
        if (std.ascii.eqlIgnoreCase(ext, option)) return true;
    }
    return false;
}

fn startsWithIgnoreCase(haystack: []const u8, prefix: []const u8) bool {
    if (haystack.len < prefix.len) return false;
    return std.ascii.eqlIgnoreCase(haystack[0..prefix.len], prefix);
}

fn iconIsResolvable(name: []const u8) bool {
    const canvas = @import("native_sdk").canvas;
    if (canvas.icons.find(name) != null) return true;
    const bare = canvas.icons.appIconName(name) orelse return false;
    return file_type_icons.contains(bare);
}

test "filesTreeIcon uses folder-open when expanded and folder when collapsed" {
    try std.testing.expectEqualStrings("folder", filesTreeIcon("src/", false, false));
    try std.testing.expectEqualStrings("folder-open", filesTreeIcon("src/", false, true));
    try std.testing.expectEqualStrings("folder", filesTreeIcon(".github/", false, false));
    try std.testing.expectEqualStrings("folder-open", filesTreeIcon(".git/", false, true));
}

test "fileIconForName maps shells, archives, audio, leftover config" {
    try std.testing.expectEqualStrings("terminal", fileIconForName("run.sh"));
    try std.testing.expectEqualStrings("terminal", fileIconForName("setup.BASH"));
    try std.testing.expectEqualStrings("terminal", fileIconForName("rc.zsh"));
    try std.testing.expectEqualStrings("terminal", fileIconForName("config.fish"));
    try std.testing.expectEqualStrings("terminal", fileIconForName("build.ps1"));
    try std.testing.expectEqualStrings("terminal", fileIconForName("Tools.psm1"));

    try std.testing.expectEqualStrings("settings", fileIconForName("php.ini"));
    try std.testing.expectEqualStrings("settings", fileIconForName("app.cfg"));
    try std.testing.expectEqualStrings("settings", fileIconForName("nginx.conf"));
    try std.testing.expectEqualStrings("settings", fileIconForName("app.config"));
    try std.testing.expectEqualStrings("settings", fileIconForName(".env"));
    try std.testing.expectEqualStrings("settings", fileIconForName(".env.local"));
    try std.testing.expectEqualStrings("settings", fileIconForName(".editorconfig"));

    try std.testing.expectEqualStrings("archive", fileIconForName("out.zip"));
    try std.testing.expectEqualStrings("archive", fileIconForName("src.tar"));
    try std.testing.expectEqualStrings("archive", fileIconForName("src.tar.gz"));
    try std.testing.expectEqualStrings("archive", fileIconForName("pkg.tgz"));
    try std.testing.expectEqualStrings("archive", fileIconForName("pack.7z"));
    try std.testing.expectEqualStrings("archive", fileIconForName("old.rar"));

    try std.testing.expectEqualStrings("music", fileIconForName("track.mp3"));
    try std.testing.expectEqualStrings("music", fileIconForName("loop.wav"));
    try std.testing.expectEqualStrings("music", fileIconForName("clip.ogg"));
    try std.testing.expectEqualStrings("music", fileIconForName("song.flac"));
    try std.testing.expectEqualStrings("music", fileIconForName("voice.m4a"));
}

test "fileIconForName maps Material app icons for common extensions" {
    try std.testing.expectEqualStrings("app:zig", fileIconForName("main.zig"));
    try std.testing.expectEqualStrings("app:rust", fileIconForName("lib.rs"));
    try std.testing.expectEqualStrings("app:go", fileIconForName("main.go"));
    try std.testing.expectEqualStrings("app:python", fileIconForName("app.py"));
    try std.testing.expectEqualStrings("app:javascript", fileIconForName("index.js"));
    try std.testing.expectEqualStrings("app:typescript", fileIconForName("index.ts"));
    try std.testing.expectEqualStrings("app:react", fileIconForName("Panel.tsx"));
    try std.testing.expectEqualStrings("app:react", fileIconForName("Widget.jsx"));
    try std.testing.expectEqualStrings("app:vue", fileIconForName("App.vue"));
    try std.testing.expectEqualStrings("app:svelte", fileIconForName("App.svelte"));
    try std.testing.expectEqualStrings("app:html", fileIconForName("index.html"));
    try std.testing.expectEqualStrings("app:css", fileIconForName("app.css"));
    try std.testing.expectEqualStrings("app:markdown", fileIconForName("notes.md"));
    try std.testing.expectEqualStrings("app:json", fileIconForName("data.jsonc"));
    try std.testing.expectEqualStrings("app:yaml", fileIconForName("app.yml"));
    try std.testing.expectEqualStrings("app:xml", fileIconForName("pom.xml"));
    try std.testing.expectEqualStrings("app:image", fileIconForName("photo.png"));
    try std.testing.expectEqualStrings("app:c", fileIconForName("main.c"));
    try std.testing.expectEqualStrings("app:cpp", fileIconForName("main.cpp"));
    try std.testing.expectEqualStrings("app:java", fileIconForName("Main.java"));
}

test "fileIconForName maps high-value basename specials" {
    try std.testing.expectEqualStrings("app:docker", fileIconForName("Dockerfile"));
    try std.testing.expectEqualStrings("app:docker", fileIconForName("Dockerfile.dev"));
    try std.testing.expectEqualStrings("app:docker", fileIconForName("compose.yaml"));
    try std.testing.expectEqualStrings("app:makefile", fileIconForName("Makefile"));
    try std.testing.expectEqualStrings("app:makefile", fileIconForName("makefile.inc"));
    try std.testing.expectEqualStrings("app:makefile", fileIconForName("justfile"));
    try std.testing.expectEqualStrings("app:readme", fileIconForName("README.md"));
    try std.testing.expectEqualStrings("app:readme", fileIconForName("README"));
    try std.testing.expectEqualStrings("app:nodejs", fileIconForName("package.json"));
    try std.testing.expectEqualStrings("app:rust", fileIconForName("Cargo.toml"));
    try std.testing.expectEqualStrings("app:go", fileIconForName("go.mod"));
    try std.testing.expectEqualStrings("app:typescript", fileIconForName("tsconfig.json"));
    try std.testing.expectEqualStrings("app:typescript", fileIconForName("tsconfig.app.json"));
    try std.testing.expectEqualStrings("app:typescript", fileIconForName("tsconfig.jsonc"));
    try std.testing.expectEqualStrings("app:git", fileIconForName(".gitignore"));
    try std.testing.expectEqualStrings("app:git", fileIconForName(".gitattributes"));
    try std.testing.expectEqualStrings("app:git", fileIconForName(".gitmodules"));
    try std.testing.expectEqualStrings("app:git", fileIconForName(".gitconfig"));
    try std.testing.expectEqualStrings("app:git", fileIconForName(".gitkeep"));
}

test "fileIconForName unknown files stay file-text" {
    try std.testing.expectEqualStrings("file-text", fileIconForName("unknown.data"));
    try std.testing.expectEqualStrings("file-text", fileIconForName("notes.txt"));
}

test "fileIconForPath uses the basename of a repo-relative path" {
    try std.testing.expectEqualStrings("terminal", fileIconForPath("scripts/setup.sh"));
    try std.testing.expectEqualStrings("app:nodejs", fileIconForPath("src/package.json"));
    try std.testing.expectEqualStrings("app:git", fileIconForPath(".gitignore"));
    try std.testing.expectEqualStrings("app:zig", fileIconForPath("src/main.zig"));
}

test "filesTreeIcon file rows ignore expand state" {
    try std.testing.expectEqualStrings("terminal", filesTreeIcon("run.sh", true, true));
    try std.testing.expectEqualStrings("terminal", filesTreeIcon("run.sh", true, false));
    try std.testing.expectEqualStrings("app:readme", filesTreeIcon("README.md", true, true));
}

test "files tree icons stay in Native built-ins or registered app: names" {
    const samples = [_][]const u8{
        filesTreeIcon("src/", false, false),
        filesTreeIcon("src/", false, true),
        fileIconForName("run.sh"),
        fileIconForName("package.json"),
        fileIconForName("out.zip"),
        fileIconForName("track.mp3"),
        fileIconForName(".gitignore"),
        fileIconForName("README.md"),
        fileIconForName("Makefile"),
        fileIconForName("Dockerfile"),
        fileIconForName("main.zig"),
        fileIconForName("lib.rs"),
        fileIconForName("Panel.tsx"),
        fileIconForName("unknown.data"),
    };
    for (samples) |name| {
        try std.testing.expect(iconIsResolvable(name));
    }
}
