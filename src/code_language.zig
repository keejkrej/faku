//! Documented Native `<code language>` lexer names from a path.
//!
//! Shared by Files preview and Diff hunk code-diff so the maps cannot
//! drift. Unknown extensions and well-known names Native has no lexer
//! for (Dockerfile, Makefile, Cargo.toml) are `"plain"`. Never invents
//! a lexer id; names match `native_sdk.canvas.code.languageFromName`.

const std = @import("std");
const composer = @import("composer.zig");

/// Documented Native `language=` lexer name for a preview / Diff path.
pub fn previewLanguage(path: []const u8) []const u8 {
    const base = composer.fileMentionBasename(path);
    if (std.ascii.eqlIgnoreCase(base, "Dockerfile") or
        std.ascii.eqlIgnoreCase(base, "Containerfile") or
        std.ascii.eqlIgnoreCase(base, "Makefile") or
        std.ascii.eqlIgnoreCase(base, "GNUmakefile") or
        std.ascii.eqlIgnoreCase(base, "Cargo.toml"))
    {
        return "plain";
    }
    const ext = extensionOf(base);
    if (std.ascii.eqlIgnoreCase(ext, "zig")) return "zig";
    if (std.ascii.eqlIgnoreCase(ext, "js") or
        std.ascii.eqlIgnoreCase(ext, "mjs") or
        std.ascii.eqlIgnoreCase(ext, "cjs")) return "javascript";
    if (std.ascii.eqlIgnoreCase(ext, "tsx")) return "tsx";
    if (std.ascii.eqlIgnoreCase(ext, "jsx")) return "jsx";
    if (std.ascii.eqlIgnoreCase(ext, "ts")) return "typescript";
    if (std.ascii.eqlIgnoreCase(ext, "json") or std.ascii.eqlIgnoreCase(ext, "jsonc")) return "json";
    if (std.ascii.eqlIgnoreCase(ext, "yaml") or std.ascii.eqlIgnoreCase(ext, "yml")) return "yaml";
    if (std.ascii.eqlIgnoreCase(ext, "sh") or
        std.ascii.eqlIgnoreCase(ext, "bash") or
        std.ascii.eqlIgnoreCase(ext, "zsh")) return "shell";
    if (std.ascii.eqlIgnoreCase(ext, "py") or std.ascii.eqlIgnoreCase(ext, "pyi")) return "python";
    if (std.ascii.eqlIgnoreCase(ext, "rs")) return "rust";
    if (std.ascii.eqlIgnoreCase(ext, "c") or std.ascii.eqlIgnoreCase(ext, "h") or
        std.ascii.eqlIgnoreCase(ext, "cc") or std.ascii.eqlIgnoreCase(ext, "cpp") or
        std.ascii.eqlIgnoreCase(ext, "cxx") or std.ascii.eqlIgnoreCase(ext, "hpp") or
        std.ascii.eqlIgnoreCase(ext, "hh") or std.ascii.eqlIgnoreCase(ext, "cs") or
        std.ascii.eqlIgnoreCase(ext, "java") or std.ascii.eqlIgnoreCase(ext, "kt") or
        std.ascii.eqlIgnoreCase(ext, "kts") or std.ascii.eqlIgnoreCase(ext, "swift")) return "c";
    if (std.ascii.eqlIgnoreCase(ext, "go")) return "go";
    if (std.ascii.eqlIgnoreCase(ext, "html") or std.ascii.eqlIgnoreCase(ext, "htm") or
        std.ascii.eqlIgnoreCase(ext, "xml") or std.ascii.eqlIgnoreCase(ext, "svg")) return "html";
    if (std.ascii.eqlIgnoreCase(ext, "css") or
        std.ascii.eqlIgnoreCase(ext, "scss") or
        std.ascii.eqlIgnoreCase(ext, "less")) return "css";
    if (std.ascii.eqlIgnoreCase(ext, "sql")) return "sql";
    if (std.ascii.eqlIgnoreCase(ext, "md") or std.ascii.eqlIgnoreCase(ext, "markdown")) return "markdown";
    return "plain";
}

fn extensionOf(name: []const u8) []const u8 {
    if (std.mem.lastIndexOfScalar(u8, name, '.')) |dot| {
        if (dot == 0 or dot + 1 >= name.len) return "";
        return name[dot + 1 ..];
    }
    return "";
}
