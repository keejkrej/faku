//! First-cut Native built-in icon names for Files and Diff tree rows.
//!
//! Behavior follows Waku `file_icon_for_path` / `file_icon_for_name`
//! (basename specials, then extension) but maps onto Native's
//! documented `canvas.icons.known_icon_names` set — not Waku's SVG
//! file-type pack. Directories paint `folder-open` when expanded and
//! `folder` when collapsed. Unknown files stay `file-text`. Diff
//! tree rows and the selected-file Diff header reuse this same map.
//! Browser, Terminal, and composer `@` do not.

const std = @import("std");
const composer = @import("composer.zig");

/// Native built-in `icon name=` for a Files or Diff tree row.
pub fn filesTreeIcon(path: []const u8, is_file: bool, expanded: bool) []const u8 {
    if (!is_file) {
        return if (expanded) "folder-open" else "folder";
    }
    return fileIconForPath(path);
}

/// Native built-in for a file path (basename of a repo-relative path).
pub fn fileIconForPath(path: []const u8) []const u8 {
    return fileIconForName(composer.fileMentionBasename(path));
}

/// Native built-in for a file basename. Case-insensitive, like Waku.
pub fn fileIconForName(name: []const u8) []const u8 {
    if (startsWithIgnoreCase(name, ".git")) return "git-branch";
    if (isMakefileName(name) or isDockerfileName(name) or isSettingsName(name)) return "settings";

    const ext = extensionOf(name);
    if (extensionIs(ext, &.{ "sh", "bash", "zsh", "fish", "ps1", "psm1" })) return "terminal";
    if (extensionIs(ext, &.{ "json", "jsonc", "toml", "yaml", "yml", "ini", "cfg", "conf", "config" })) return "settings";
    if (extensionIs(ext, &.{ "zip", "tar", "gz", "tgz", "7z", "rar" })) return "archive";
    if (extensionIs(ext, &.{ "mp3", "wav", "ogg", "flac", "m4a" })) return "music";
    return "file-text";
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

test "filesTreeIcon uses folder-open when expanded and folder when collapsed" {
    try std.testing.expectEqualStrings("folder", filesTreeIcon("src/", false, false));
    try std.testing.expectEqualStrings("folder-open", filesTreeIcon("src/", false, true));
    try std.testing.expectEqualStrings("folder", filesTreeIcon(".github/", false, false));
    try std.testing.expectEqualStrings("folder-open", filesTreeIcon(".git/", false, true));
}

test "fileIconForName maps shells, config, archives, audio, git, and specials" {
    try std.testing.expectEqualStrings("terminal", fileIconForName("run.sh"));
    try std.testing.expectEqualStrings("terminal", fileIconForName("setup.BASH"));
    try std.testing.expectEqualStrings("terminal", fileIconForName("rc.zsh"));
    try std.testing.expectEqualStrings("terminal", fileIconForName("config.fish"));
    try std.testing.expectEqualStrings("terminal", fileIconForName("build.ps1"));
    try std.testing.expectEqualStrings("terminal", fileIconForName("Tools.psm1"));

    try std.testing.expectEqualStrings("settings", fileIconForName("package.json"));
    try std.testing.expectEqualStrings("settings", fileIconForName("tsconfig.jsonc"));
    try std.testing.expectEqualStrings("settings", fileIconForName("Cargo.toml"));
    try std.testing.expectEqualStrings("settings", fileIconForName("compose.yaml"));
    try std.testing.expectEqualStrings("settings", fileIconForName("app.yml"));
    try std.testing.expectEqualStrings("settings", fileIconForName("php.ini"));
    try std.testing.expectEqualStrings("settings", fileIconForName("app.cfg"));
    try std.testing.expectEqualStrings("settings", fileIconForName("nginx.conf"));
    try std.testing.expectEqualStrings("settings", fileIconForName("app.config"));
    try std.testing.expectEqualStrings("settings", fileIconForName("Makefile"));
    try std.testing.expectEqualStrings("settings", fileIconForName("makefile.inc"));
    try std.testing.expectEqualStrings("settings", fileIconForName("justfile"));
    try std.testing.expectEqualStrings("settings", fileIconForName("Dockerfile"));
    try std.testing.expectEqualStrings("settings", fileIconForName("Dockerfile.dev"));
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

    try std.testing.expectEqualStrings("git-branch", fileIconForName(".gitignore"));
    try std.testing.expectEqualStrings("git-branch", fileIconForName(".gitattributes"));
    try std.testing.expectEqualStrings("git-branch", fileIconForName(".gitmodules"));
    try std.testing.expectEqualStrings("git-branch", fileIconForName(".gitconfig"));
    try std.testing.expectEqualStrings("git-branch", fileIconForName(".gitkeep"));

    try std.testing.expectEqualStrings("file-text", fileIconForName("README.md"));
    try std.testing.expectEqualStrings("file-text", fileIconForName("README"));
    try std.testing.expectEqualStrings("file-text", fileIconForName("main.zig"));
    try std.testing.expectEqualStrings("file-text", fileIconForName("unknown.data"));
    try std.testing.expectEqualStrings("file-text", fileIconForName("notes.txt"));
}

test "fileIconForPath uses the basename of a repo-relative path" {
    try std.testing.expectEqualStrings("terminal", fileIconForPath("scripts/setup.sh"));
    try std.testing.expectEqualStrings("settings", fileIconForPath("src/package.json"));
    try std.testing.expectEqualStrings("git-branch", fileIconForPath(".gitignore"));
    try std.testing.expectEqualStrings("file-text", fileIconForPath("src/main.zig"));
}

test "filesTreeIcon file rows ignore expand state" {
    try std.testing.expectEqualStrings("terminal", filesTreeIcon("run.sh", true, true));
    try std.testing.expectEqualStrings("terminal", filesTreeIcon("run.sh", true, false));
    try std.testing.expectEqualStrings("file-text", filesTreeIcon("README.md", true, true));
}

test "files tree icons stay in Native known built-in names" {
    const canvas = @import("native_sdk").canvas;
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
    };
    for (samples) |name| {
        try std.testing.expect(canvas.icons.find(name) != null);
    }
}
