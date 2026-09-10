//! File-type icon names for Files, Diff, and composer `@` mention
//! rows.
//!
//! Behavior follows Waku `file_icon_for_path` / `file_icon_for_name`
//! (basename specials, then extension) and maps onto a curated MIT
//! Material app-icon subset (`app:zig`, `app:rust`, `app:ruby`, … from
//! `src/icons/file-types/`, including `app:zip` / `app:audio` /
//! `app:video` / `app:settings` / `app:certificate` / `app:lockfile` /
//! `app:exe` / `app:nginx` / `app:cmake` / `app:coffee` / `app:gitlab` /
//! `app:gradle` / `app:kubernetes` / `app:tex` / `app:crystal` /
//! `app:elm` / `app:erlang` / `app:haxe` / `app:jinja` / `app:xaml` /
//! `app:diff` / `app:file` / `app:julia` / `app:prettier` /
//! `app:kotlin` / `app:clojure` / `app:helm` / `app:editorconfig` /
//! `app:graphql` / `app:nest` / `app:pug`)
//! plus Native built-ins for directories
//! (`folder` / `folder-open`) and unknown files (`app:file`). Diff tree
//! rows, the selected-file Diff header, and composer `@` mention
//! rows reuse this same map
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
    if (extensionIs(ext, &.{ "sh", "bash", "zsh", "fish" })) return app("console");
    if (extensionIs(ext, &.{ "ps1", "psm1" })) return app("powershell");
    if (extensionIs(ext, &.{ "zip", "gz", "tgz", "bz2", "xz", "7z", "rar", "tar", "jar" })) return app("zip");
    if (extensionIs(ext, &.{ "mp3", "wav", "flac", "ogg", "m4a" })) return app("audio");
    if (extensionIs(ext, &.{ "mp4", "mov", "avi", "webm", "mkv" })) return app("video");
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
    if (extensionIs(ext, &.{ "kt", "kts" })) return app("kotlin");
    if (extensionIs(ext, &.{ "rb" })) return app("ruby");
    if (extensionIs(ext, &.{ "php" })) return app("php");
    if (extensionIs(ext, &.{ "swift" })) return app("swift");
    if (extensionIs(ext, &.{ "scala" })) return app("scala");
    if (extensionIs(ext, &.{ "dart" })) return app("dart");
    if (extensionIs(ext, &.{ "lua" })) return app("lua");
    if (extensionIs(ext, &.{ "hs" })) return app("haskell");
    if (extensionIs(ext, &.{ "ex", "exs" })) return app("elixir");
    if (extensionIs(ext, &.{ "cs" })) return app("csharp");
    if (extensionIs(ext, &.{ "pl", "pm" })) return app("perl");
    if (extensionIs(ext, &.{ "ml", "mli" })) return app("ocaml");
    if (extensionIs(ext, &.{ "sol" })) return app("solidity");
    if (extensionIs(ext, &.{ "nix" })) return app("nix");
    if (extensionIs(ext, &.{ "astro" })) return app("astro");
    if (extensionIs(ext, &.{ "scss", "sass" })) return app("sass");
    if (extensionIs(ext, &.{ "proto" })) return app("proto");
    if (extensionIs(ext, &.{ "prisma" })) return app("prisma");
    if (extensionIs(ext, &.{ "sql" })) return app("database");
    if (extensionIs(ext, &.{ "pdf" })) return app("pdf");
    if (extensionIs(ext, &.{ "svg" })) return app("svg");
    if (extensionIs(ext, &.{ "tf", "tfvars" })) return app("terraform");
    if (extensionIs(ext, &.{ "wasm" })) return app("webassembly");
    if (extensionIs(ext, &.{ "exe", "dll", "so", "dylib" })) return app("exe");
    if (extensionIs(ext, &.{ "lock" })) return app("lockfile");
    if (extensionIs(ext, &.{ "coffee", "cson" })) return app("coffee");
    if (extensionIs(ext, &.{ "tex", "sty", "cls" })) return app("tex");
    if (extensionIs(ext, &.{ "cr" })) return app("crystal");
    if (extensionIs(ext, &.{ "elm" })) return app("elm");
    if (extensionIs(ext, &.{ "erl", "hrl" })) return app("erlang");
    if (extensionIs(ext, &.{ "hx", "hxml" })) return app("haxe");
    if (extensionIs(ext, &.{ "jinja", "jinja2", "j2" })) return app("jinja");
    if (extensionIs(ext, &.{ "jl" })) return app("julia");
    if (extensionIs(ext, &.{ "clj", "cljs", "cljc", "edn" })) return app("clojure");
    if (extensionIs(ext, &.{ "graphql", "gql" })) return app("graphql");
    if (extensionIs(ext, &.{ "pug", "jade" })) return app("pug");
    if (extensionIs(ext, &.{ "xaml" })) return app("xaml");
    if (extensionIs(ext, &.{ "diff", "patch" })) return app("diff");
    if (extensionIs(ext, &.{ "ini", "cfg", "conf", "config", "toml" })) return app("settings");
    return app("file");
}

fn basenameSpecial(name: []const u8) ?[]const u8 {
    if (startsWithIgnoreCase(name, "readme")) return app("readme");
    if (startsWithIgnoreCase(name, "license") or
        startsWithIgnoreCase(name, "licence") or
        startsWithIgnoreCase(name, "copying")) return app("certificate");
    if (isDockerfileName(name)) return app("docker");
    if (isCmakeName(name)) return app("cmake");
    if (isMakefileName(name)) return app("makefile");
    if (std.ascii.eqlIgnoreCase(name, "Cargo.toml") or
        std.ascii.eqlIgnoreCase(name, "Cargo.lock") or
        std.ascii.eqlIgnoreCase(name, "rust-toolchain.toml")) return app("rust");
    if (std.ascii.eqlIgnoreCase(name, "go.mod") or
        std.ascii.eqlIgnoreCase(name, "go.sum") or
        std.ascii.eqlIgnoreCase(name, "go.work")) return app("go");
    if (std.ascii.eqlIgnoreCase(name, "bun.lock") or
        std.ascii.eqlIgnoreCase(name, "bun.lockb") or
        std.ascii.eqlIgnoreCase(name, "bunfig.toml")) return app("bun");
    if (startsWithIgnoreCase(name, "pnpm-") or
        std.ascii.eqlIgnoreCase(name, ".pnpmfile.cjs")) return app("pnpm");
    if (std.ascii.eqlIgnoreCase(name, "yarn.lock") or
        startsWithIgnoreCase(name, ".yarnrc")) return app("yarn");
    if (std.ascii.eqlIgnoreCase(name, "package.json")) return app("nodejs");
    if (std.ascii.eqlIgnoreCase(name, "package-lock.json")) return app("npm");
    if (startsWithIgnoreCase(name, "tsconfig.") or std.ascii.eqlIgnoreCase(name, "tsconfig.json"))
        return app("typescript");
    if (std.ascii.eqlIgnoreCase(name, ".gitlab-ci.yml") or
        std.ascii.eqlIgnoreCase(name, ".gitlab-ci.yaml")) return app("gitlab");
    if (startsWithIgnoreCase(name, ".git")) return app("git");
    if (std.ascii.eqlIgnoreCase(name, "Gemfile") or
        std.ascii.eqlIgnoreCase(name, "Gemfile.lock")) return app("ruby");
    if (std.ascii.eqlIgnoreCase(name, "composer.json") or
        std.ascii.eqlIgnoreCase(name, "composer.lock")) return app("php");
    if (startsWithIgnoreCase(name, "astro.config.")) return app("astro");
    if (startsWithIgnoreCase(name, ".eslint") or startsWithIgnoreCase(name, "eslint.config."))
        return app("eslint");
    if (startsWithIgnoreCase(name, ".prettier") or startsWithIgnoreCase(name, "prettier.config."))
        return app("prettier");
    if (startsWithIgnoreCase(name, "biome.json")) return app("biome");
    if (startsWithIgnoreCase(name, ".babel") or startsWithIgnoreCase(name, "babel.config."))
        return app("babel");
    if (startsWithIgnoreCase(name, "vite.config.")) return app("vite");
    if (startsWithIgnoreCase(name, "vitest.config.") or startsWithIgnoreCase(name, "vitest.workspace."))
        return app("vitest");
    if (startsWithIgnoreCase(name, "webpack.")) return app("webpack");
    if (startsWithIgnoreCase(name, "rollup.config.")) return app("rollup");
    if (startsWithIgnoreCase(name, ".stylelint") or startsWithIgnoreCase(name, "stylelint.config."))
        return app("stylelint");
    if (startsWithIgnoreCase(name, "next.config.") or std.ascii.eqlIgnoreCase(name, "next-env.d.ts"))
        return app("next");
    if (startsWithIgnoreCase(name, "nuxt.config.") or std.ascii.eqlIgnoreCase(name, ".nuxtrc"))
        return app("nuxt");
    if (std.ascii.eqlIgnoreCase(name, "angular.json") or endsWithIgnoreCase(name, ".component.ts"))
        return app("angular");
    if (std.ascii.eqlIgnoreCase(name, "nest-cli.json")) return app("nest");
    if (startsWithIgnoreCase(name, "tailwind.config.")) return app("tailwindcss");
    if (startsWithIgnoreCase(name, "svelte.config.")) return app("svelte");
    if (startsWithIgnoreCase(name, "vue.config.")) return app("vue");
    if (std.ascii.eqlIgnoreCase(name, "firebase.json") or std.ascii.eqlIgnoreCase(name, ".firebaserc"))
        return app("firebase");
    if (std.ascii.eqlIgnoreCase(name, "supabase.toml")) return app("supabase");
    if (startsWithIgnoreCase(name, "prisma.config.")) return app("prisma");
    if (std.ascii.eqlIgnoreCase(name, "turbo.json")) return app("turborepo");
    if (containsIgnoreCase(name, ".stories.") or containsIgnoreCase(name, ".story."))
        return app("storybook");
    if (startsWithIgnoreCase(name, "deno.json") or std.ascii.eqlIgnoreCase(name, "deno.lock"))
        return app("deno");
    if (std.ascii.eqlIgnoreCase(name, "kustomization.yaml") or
        std.ascii.eqlIgnoreCase(name, "kustomization.yml")) return app("kubernetes");
    if (isHelmName(name)) return app("helm");
    if (isGradleName(name)) return app("gradle");
    if (std.ascii.eqlIgnoreCase(name, "nginx.conf")) return app("nginx");
    if (std.ascii.eqlIgnoreCase(name, ".editorconfig")) return app("editorconfig");
    if (isSettingsName(name)) return app("settings");
    return null;
}

fn isMakefileName(name: []const u8) bool {
    return std.ascii.eqlIgnoreCase(name, "Makefile") or
        std.ascii.eqlIgnoreCase(name, "GNUmakefile") or
        std.ascii.eqlIgnoreCase(name, "justfile") or
        startsWithIgnoreCase(name, "makefile.");
}

fn isCmakeName(name: []const u8) bool {
    return std.ascii.eqlIgnoreCase(name, "CMakeLists.txt") or
        startsWithIgnoreCase(name, "cmake.");
}

fn isGradleName(name: []const u8) bool {
    return std.ascii.eqlIgnoreCase(name, "build.gradle") or
        std.ascii.eqlIgnoreCase(name, "settings.gradle") or
        std.ascii.eqlIgnoreCase(name, "gradlew") or
        std.ascii.eqlIgnoreCase(name, "gradlew.bat");
}

fn isDockerfileName(name: []const u8) bool {
    return startsWithIgnoreCase(name, "dockerfile") or
        std.ascii.eqlIgnoreCase(name, "Containerfile") or
        startsWithIgnoreCase(name, "compose.");
}

fn isHelmName(name: []const u8) bool {
    return std.ascii.eqlIgnoreCase(name, "Chart.yaml") or
        std.ascii.eqlIgnoreCase(name, "Chart.yml") or
        std.ascii.eqlIgnoreCase(name, "values.yaml") or
        std.ascii.eqlIgnoreCase(name, "values.yml") or
        std.ascii.eqlIgnoreCase(name, "helmfile.yaml") or
        std.ascii.eqlIgnoreCase(name, "helmfile.yml");
}

fn isSettingsName(name: []const u8) bool {
    return startsWithIgnoreCase(name, ".env");
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

fn endsWithIgnoreCase(haystack: []const u8, suffix: []const u8) bool {
    if (haystack.len < suffix.len) return false;
    return std.ascii.eqlIgnoreCase(haystack[haystack.len - suffix.len ..], suffix);
}

fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (haystack.len < needle.len) return false;
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[i .. i + needle.len], needle)) return true;
    }
    return false;
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
    try std.testing.expectEqualStrings("app:console", fileIconForName("run.sh"));
    try std.testing.expectEqualStrings("app:console", fileIconForName("setup.BASH"));
    try std.testing.expectEqualStrings("app:console", fileIconForName("rc.zsh"));
    try std.testing.expectEqualStrings("app:console", fileIconForName("config.fish"));
    try std.testing.expectEqualStrings("app:powershell", fileIconForName("build.ps1"));
    try std.testing.expectEqualStrings("app:powershell", fileIconForName("Tools.psm1"));

    try std.testing.expectEqualStrings("app:settings", fileIconForName("php.ini"));
    try std.testing.expectEqualStrings("app:settings", fileIconForName("app.cfg"));
    try std.testing.expectEqualStrings("app:nginx", fileIconForName("nginx.conf"));
    try std.testing.expectEqualStrings("app:settings", fileIconForName("app.config"));
    try std.testing.expectEqualStrings("app:settings", fileIconForName("other.toml"));
    try std.testing.expectEqualStrings("app:settings", fileIconForName(".env"));
    try std.testing.expectEqualStrings("app:settings", fileIconForName(".env.local"));
    try std.testing.expectEqualStrings("app:editorconfig", fileIconForName(".editorconfig"));

    try std.testing.expectEqualStrings("app:zip", fileIconForName("out.zip"));
    try std.testing.expectEqualStrings("app:zip", fileIconForName("lib.jar"));
    try std.testing.expectEqualStrings("app:zip", fileIconForName("src.tar"));
    try std.testing.expectEqualStrings("app:zip", fileIconForName("src.tar.gz"));
    try std.testing.expectEqualStrings("app:zip", fileIconForName("pkg.tgz"));
    try std.testing.expectEqualStrings("app:zip", fileIconForName("src.tar.bz2"));
    try std.testing.expectEqualStrings("app:zip", fileIconForName("src.tar.xz"));
    try std.testing.expectEqualStrings("app:zip", fileIconForName("pack.7z"));
    try std.testing.expectEqualStrings("app:zip", fileIconForName("old.rar"));

    try std.testing.expectEqualStrings("app:audio", fileIconForName("track.mp3"));
    try std.testing.expectEqualStrings("app:audio", fileIconForName("loop.wav"));
    try std.testing.expectEqualStrings("app:audio", fileIconForName("clip.ogg"));
    try std.testing.expectEqualStrings("app:audio", fileIconForName("song.flac"));
    try std.testing.expectEqualStrings("app:audio", fileIconForName("voice.m4a"));

    try std.testing.expectEqualStrings("app:video", fileIconForName("clip.mp4"));
    try std.testing.expectEqualStrings("app:video", fileIconForName("clip.mov"));
    try std.testing.expectEqualStrings("app:video", fileIconForName("clip.avi"));
    try std.testing.expectEqualStrings("app:video", fileIconForName("clip.webm"));
    try std.testing.expectEqualStrings("app:video", fileIconForName("clip.mkv"));
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
    try std.testing.expectEqualStrings("app:ruby", fileIconForName("app.rb"));
    try std.testing.expectEqualStrings("app:php", fileIconForName("index.php"));
    try std.testing.expectEqualStrings("app:swift", fileIconForName("App.swift"));
    try std.testing.expectEqualStrings("app:scala", fileIconForName("Main.scala"));
    try std.testing.expectEqualStrings("app:dart", fileIconForName("main.dart"));
    try std.testing.expectEqualStrings("app:lua", fileIconForName("init.lua"));
    try std.testing.expectEqualStrings("app:haskell", fileIconForName("Main.hs"));
    try std.testing.expectEqualStrings("app:elixir", fileIconForName("mix.exs"));
    try std.testing.expectEqualStrings("app:elixir", fileIconForName("lib.ex"));
    try std.testing.expectEqualStrings("app:csharp", fileIconForName("Program.cs"));
    try std.testing.expectEqualStrings("app:perl", fileIconForName("script.pl"));
    try std.testing.expectEqualStrings("app:perl", fileIconForName("Foo.pm"));
    try std.testing.expectEqualStrings("app:ocaml", fileIconForName("main.ml"));
    try std.testing.expectEqualStrings("app:ocaml", fileIconForName("main.mli"));
    try std.testing.expectEqualStrings("app:solidity", fileIconForName("Token.sol"));
    try std.testing.expectEqualStrings("app:nix", fileIconForName("flake.nix"));
    try std.testing.expectEqualStrings("app:astro", fileIconForName("index.astro"));
    try std.testing.expectEqualStrings("app:sass", fileIconForName("app.scss"));
    try std.testing.expectEqualStrings("app:sass", fileIconForName("app.sass"));
    try std.testing.expectEqualStrings("app:proto", fileIconForName("api.proto"));
    try std.testing.expectEqualStrings("app:prisma", fileIconForName("schema.prisma"));
    try std.testing.expectEqualStrings("app:database", fileIconForName("schema.sql"));
    try std.testing.expectEqualStrings("app:pdf", fileIconForName("spec.pdf"));
    try std.testing.expectEqualStrings("app:svg", fileIconForName("logo.svg"));
    try std.testing.expectEqualStrings("app:terraform", fileIconForName("main.tf"));
    try std.testing.expectEqualStrings("app:terraform", fileIconForName("prod.tfvars"));
    try std.testing.expectEqualStrings("app:webassembly", fileIconForName("app.wasm"));
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
    try std.testing.expectEqualStrings("app:ruby", fileIconForName("Gemfile"));
    try std.testing.expectEqualStrings("app:ruby", fileIconForName("Gemfile.lock"));
    try std.testing.expectEqualStrings("app:php", fileIconForName("composer.json"));
    try std.testing.expectEqualStrings("app:php", fileIconForName("composer.lock"));
    try std.testing.expectEqualStrings("app:astro", fileIconForName("astro.config.mjs"));
    try std.testing.expectEqualStrings("app:bun", fileIconForName("bun.lock"));
    try std.testing.expectEqualStrings("app:bun", fileIconForName("bun.lockb"));
    try std.testing.expectEqualStrings("app:bun", fileIconForName("bunfig.toml"));
    try std.testing.expectEqualStrings("app:pnpm", fileIconForName("pnpm-lock.yaml"));
    try std.testing.expectEqualStrings("app:pnpm", fileIconForName("pnpm-workspace.yaml"));
    try std.testing.expectEqualStrings("app:pnpm", fileIconForName(".pnpmfile.cjs"));
    try std.testing.expectEqualStrings("app:yarn", fileIconForName("yarn.lock"));
    try std.testing.expectEqualStrings("app:yarn", fileIconForName(".yarnrc"));
    try std.testing.expectEqualStrings("app:yarn", fileIconForName(".yarnrc.yml"));
    try std.testing.expectEqualStrings("app:npm", fileIconForName("package-lock.json"));
    try std.testing.expectEqualStrings("app:deno", fileIconForName("deno.json"));
    try std.testing.expectEqualStrings("app:deno", fileIconForName("deno.jsonc"));
    try std.testing.expectEqualStrings("app:deno", fileIconForName("deno.lock"));
    try std.testing.expectEqualStrings("app:vite", fileIconForName("vite.config.ts"));
    try std.testing.expectEqualStrings("app:vite", fileIconForName("vite.config.mjs"));
    try std.testing.expectEqualStrings("app:vitest", fileIconForName("vitest.config.ts"));
    try std.testing.expectEqualStrings("app:vitest", fileIconForName("vitest.workspace.ts"));
    try std.testing.expectEqualStrings("app:eslint", fileIconForName(".eslintrc.json"));
    try std.testing.expectEqualStrings("app:eslint", fileIconForName("eslint.config.js"));
    try std.testing.expectEqualStrings("app:biome", fileIconForName("biome.json"));
    try std.testing.expectEqualStrings("app:biome", fileIconForName("biome.jsonc"));
    try std.testing.expectEqualStrings("app:babel", fileIconForName(".babelrc"));
    try std.testing.expectEqualStrings("app:babel", fileIconForName("babel.config.js"));
    try std.testing.expectEqualStrings("app:webpack", fileIconForName("webpack.config.js"));
    try std.testing.expectEqualStrings("app:rollup", fileIconForName("rollup.config.js"));
    try std.testing.expectEqualStrings("app:rollup", fileIconForName("rollup.config.mjs"));
    try std.testing.expectEqualStrings("app:stylelint", fileIconForName(".stylelintrc"));
    try std.testing.expectEqualStrings("app:stylelint", fileIconForName(".stylelintrc.json"));
    try std.testing.expectEqualStrings("app:stylelint", fileIconForName("stylelint.config.js"));
    try std.testing.expectEqualStrings("app:stylelint", fileIconForName("stylelint.config.mjs"));
    try std.testing.expectEqualStrings("app:next", fileIconForName("next.config.js"));
    try std.testing.expectEqualStrings("app:next", fileIconForName("next.config.mjs"));
    try std.testing.expectEqualStrings("app:next", fileIconForName("next.config.ts"));
    try std.testing.expectEqualStrings("app:next", fileIconForName("next-env.d.ts"));
    try std.testing.expectEqualStrings("app:nuxt", fileIconForName("nuxt.config.ts"));
    try std.testing.expectEqualStrings("app:nuxt", fileIconForName(".nuxtrc"));
    try std.testing.expectEqualStrings("app:angular", fileIconForName("angular.json"));
    try std.testing.expectEqualStrings("app:angular", fileIconForName("app.component.ts"));
    try std.testing.expectEqualStrings("app:tailwindcss", fileIconForName("tailwind.config.js"));
    try std.testing.expectEqualStrings("app:tailwindcss", fileIconForName("tailwind.config.ts"));
    try std.testing.expectEqualStrings("app:svelte", fileIconForName("svelte.config.js"));
    try std.testing.expectEqualStrings("app:svelte", fileIconForName("svelte.config.ts"));
    try std.testing.expectEqualStrings("app:vue", fileIconForName("vue.config.js"));
    try std.testing.expectEqualStrings("app:firebase", fileIconForName("firebase.json"));
    try std.testing.expectEqualStrings("app:firebase", fileIconForName(".firebaserc"));
    try std.testing.expectEqualStrings("app:supabase", fileIconForName("supabase.toml"));
    try std.testing.expectEqualStrings("app:prisma", fileIconForName("prisma.config.ts"));
    try std.testing.expectEqualStrings("app:turborepo", fileIconForName("turbo.json"));
    try std.testing.expectEqualStrings("app:storybook", fileIconForName("Button.stories.tsx"));
    try std.testing.expectEqualStrings("app:storybook", fileIconForName("foo.story.js"));
}

test "fileIconForName maps sixth-cut certificate lock exe nginx" {
    try std.testing.expectEqualStrings("app:certificate", fileIconForName("LICENSE"));
    try std.testing.expectEqualStrings("app:certificate", fileIconForName("licence"));
    try std.testing.expectEqualStrings("app:certificate", fileIconForName("COPYING"));
    try std.testing.expectEqualStrings("app:certificate", fileIconForName("LICENSE.md"));
    try std.testing.expectEqualStrings("app:nginx", fileIconForName("nginx.conf"));
    try std.testing.expectEqualStrings("app:nginx", fileIconForName("NGINX.CONF"));
    try std.testing.expectEqualStrings("app:exe", fileIconForName("a.exe"));
    try std.testing.expectEqualStrings("app:exe", fileIconForName("lib.dll"));
    try std.testing.expectEqualStrings("app:exe", fileIconForName("lib.so"));
    try std.testing.expectEqualStrings("app:exe", fileIconForName("lib.dylib"));
    try std.testing.expectEqualStrings("app:lockfile", fileIconForName("foo.lock"));
    try std.testing.expectEqualStrings("app:rust", fileIconForName("Cargo.lock"));
    try std.testing.expectEqualStrings("app:npm", fileIconForName("package-lock.json"));
    try std.testing.expectEqualStrings("app:bun", fileIconForName("bun.lock"));
    try std.testing.expectEqualStrings("app:yarn", fileIconForName("yarn.lock"));
    try std.testing.expectEqualStrings("app:ruby", fileIconForName("Gemfile.lock"));
    try std.testing.expectEqualStrings("app:php", fileIconForName("composer.lock"));
    try std.testing.expectEqualStrings("app:deno", fileIconForName("deno.lock"));
    try std.testing.expectEqualStrings("app:settings", fileIconForName("other.conf"));
}

test "fileIconForName maps seventh-cut cmake coffee gitlab gradle kubernetes tex" {
    try std.testing.expectEqualStrings("app:cmake", fileIconForName("CMakeLists.txt"));
    try std.testing.expectEqualStrings("app:cmake", fileIconForName("cmakelists.txt"));
    try std.testing.expectEqualStrings("app:cmake", fileIconForName("cmake.in"));
    try std.testing.expectEqualStrings("app:cmake", fileIconForName("CMake.user"));
    try std.testing.expectEqualStrings("app:file", fileIconForName("FindFoo.cmake"));

    try std.testing.expectEqualStrings("app:coffee", fileIconForName("app.coffee"));
    try std.testing.expectEqualStrings("app:coffee", fileIconForName("data.cson"));
    try std.testing.expectEqualStrings("app:coffee", fileIconForName("APP.COFFEE"));
    try std.testing.expectEqualStrings("app:file", fileIconForName("Widget.cjsx"));

    try std.testing.expectEqualStrings("app:gitlab", fileIconForName(".gitlab-ci.yml"));
    try std.testing.expectEqualStrings("app:gitlab", fileIconForName(".gitlab-ci.yaml"));
    try std.testing.expectEqualStrings("app:gitlab", fileIconForName(".GITLAB-CI.YML"));
    try std.testing.expectEqualStrings("app:git", fileIconForName(".gitignore"));
    try std.testing.expectEqualStrings("app:git", fileIconForName(".gitkeep"));

    try std.testing.expectEqualStrings("app:gradle", fileIconForName("build.gradle"));
    try std.testing.expectEqualStrings("app:gradle", fileIconForName("settings.gradle"));
    try std.testing.expectEqualStrings("app:gradle", fileIconForName("gradlew"));
    try std.testing.expectEqualStrings("app:gradle", fileIconForName("gradlew.bat"));
    try std.testing.expectEqualStrings("app:gradle", fileIconForName("BUILD.GRADLE"));
    try std.testing.expectEqualStrings("app:file", fileIconForName("lib.gradle"));
    try std.testing.expectEqualStrings("app:file", fileIconForName("gradle.properties"));
    try std.testing.expectEqualStrings("app:kotlin", fileIconForName("settings.gradle.kts"));

    try std.testing.expectEqualStrings("app:kubernetes", fileIconForName("kustomization.yaml"));
    try std.testing.expectEqualStrings("app:kubernetes", fileIconForName("kustomization.yml"));
    try std.testing.expectEqualStrings("app:kubernetes", fileIconForName("Kustomization.yaml"));
    try std.testing.expectEqualStrings("app:yaml", fileIconForName("deployment.yaml"));
    try std.testing.expectEqualStrings("app:helm", fileIconForName("chart.yaml"));
    try std.testing.expectEqualStrings("app:helm", fileIconForName("values.yaml"));

    try std.testing.expectEqualStrings("app:tex", fileIconForName("paper.tex"));
    try std.testing.expectEqualStrings("app:tex", fileIconForName("macro.sty"));
    try std.testing.expectEqualStrings("app:tex", fileIconForName("article.cls"));
    try std.testing.expectEqualStrings("app:tex", fileIconForName("PAPER.TEX"));
    try std.testing.expectEqualStrings("app:file", fileIconForName("paper.ltx"));
    try std.testing.expectEqualStrings("app:file", fileIconForName("refs.bib"));
}

test "fileIconForName framework mappings are case-insensitive" {
    try std.testing.expectEqualStrings("app:next", fileIconForName("NEXT.CONFIG.MJS"));
    try std.testing.expectEqualStrings("app:next", fileIconForName("Next-Env.d.ts"));
    try std.testing.expectEqualStrings("app:nuxt", fileIconForName("NUXT.CONFIG.TS"));
    try std.testing.expectEqualStrings("app:nuxt", fileIconForName(".NUXTRC"));
    try std.testing.expectEqualStrings("app:angular", fileIconForName("ANGULAR.JSON"));
    try std.testing.expectEqualStrings("app:angular", fileIconForName("Hero.COMPONENT.TS"));
    try std.testing.expectEqualStrings("app:prisma", fileIconForName("SCHEMA.PRISMA"));
    try std.testing.expectEqualStrings("app:prisma", fileIconForName("PRISMA.CONFIG.TS"));
    try std.testing.expectEqualStrings("app:turborepo", fileIconForName("TURBO.JSON"));
    try std.testing.expectEqualStrings("app:storybook", fileIconForName("Button.STORIES.tsx"));
    try std.testing.expectEqualStrings("app:storybook", fileIconForName("Foo.STORY.js"));
    try std.testing.expectEqualStrings("app:tailwindcss", fileIconForName("TAILWIND.CONFIG.JS"));
    try std.testing.expectEqualStrings("app:firebase", fileIconForName("FIREBASE.JSON"));
    try std.testing.expectEqualStrings("app:firebase", fileIconForName(".FIREBASERC"));
    try std.testing.expectEqualStrings("app:supabase", fileIconForName("SUPABASE.TOML"));
    try std.testing.expectEqualStrings("app:rollup", fileIconForName("ROLLUP.CONFIG.JS"));
    try std.testing.expectEqualStrings("app:stylelint", fileIconForName(".STYLELINTRC"));
    try std.testing.expectEqualStrings("app:svelte", fileIconForName("SVELTE.CONFIG.JS"));
    try std.testing.expectEqualStrings("app:vue", fileIconForName("VUE.CONFIG.JS"));
}

test "fileIconForName unknown files use app:file" {
    try std.testing.expectEqualStrings("app:file", fileIconForName("unknown.data"));
    try std.testing.expectEqualStrings("app:file", fileIconForName("notes.txt"));
}

test "fileIconForName maps eighth-cut crystal elm erlang haxe jinja xaml diff file" {
    try std.testing.expectEqualStrings("app:crystal", fileIconForName("shard.cr"));
    try std.testing.expectEqualStrings("app:crystal", fileIconForName("SHARD.CR"));

    try std.testing.expectEqualStrings("app:elm", fileIconForName("Main.elm"));
    try std.testing.expectEqualStrings("app:elm", fileIconForName("MAIN.ELM"));

    try std.testing.expectEqualStrings("app:erlang", fileIconForName("mod.erl"));
    try std.testing.expectEqualStrings("app:erlang", fileIconForName("mod.hrl"));
    try std.testing.expectEqualStrings("app:erlang", fileIconForName("MOD.ERL"));

    try std.testing.expectEqualStrings("app:haxe", fileIconForName("Main.hx"));
    try std.testing.expectEqualStrings("app:haxe", fileIconForName("build.hxml"));
    try std.testing.expectEqualStrings("app:haxe", fileIconForName("MAIN.HX"));

    try std.testing.expectEqualStrings("app:jinja", fileIconForName("page.jinja"));
    try std.testing.expectEqualStrings("app:jinja", fileIconForName("page.jinja2"));
    try std.testing.expectEqualStrings("app:jinja", fileIconForName("page.j2"));
    try std.testing.expectEqualStrings("app:jinja", fileIconForName("PAGE.JINJA"));

    try std.testing.expectEqualStrings("app:xaml", fileIconForName("Window.xaml"));
    try std.testing.expectEqualStrings("app:xaml", fileIconForName("WINDOW.XAML"));
    try std.testing.expectEqualStrings("app:xml", fileIconForName("pom.xml"));

    try std.testing.expectEqualStrings("app:diff", fileIconForName("changes.diff"));
    try std.testing.expectEqualStrings("app:diff", fileIconForName("changes.patch"));
    try std.testing.expectEqualStrings("app:diff", fileIconForName("CHANGES.DIFF"));
}

test "fileIconForName maps ninth-cut julia prettier kotlin" {
    try std.testing.expectEqualStrings("app:julia", fileIconForName("main.jl"));
    try std.testing.expectEqualStrings("app:julia", fileIconForName("MAIN.JL"));

    try std.testing.expectEqualStrings("app:kotlin", fileIconForName("Main.kt"));
    try std.testing.expectEqualStrings("app:kotlin", fileIconForName("build.kts"));
    try std.testing.expectEqualStrings("app:kotlin", fileIconForName("MAIN.KT"));
    try std.testing.expectEqualStrings("app:kotlin", fileIconForName("settings.gradle.kts"));

    try std.testing.expectEqualStrings("app:prettier", fileIconForName(".prettierrc"));
    try std.testing.expectEqualStrings("app:prettier", fileIconForName(".prettierrc.json"));
    try std.testing.expectEqualStrings("app:prettier", fileIconForName(".prettierrc.yml"));
    try std.testing.expectEqualStrings("app:prettier", fileIconForName(".prettierignore"));
    try std.testing.expectEqualStrings("app:prettier", fileIconForName("prettier.config.js"));
    try std.testing.expectEqualStrings("app:prettier", fileIconForName("prettier.config.mjs"));
    try std.testing.expectEqualStrings("app:prettier", fileIconForName("prettier.config.ts"));
    try std.testing.expectEqualStrings("app:prettier", fileIconForName(".PRETTIERRC"));
    try std.testing.expectEqualStrings("app:prettier", fileIconForName("PRETTIER.CONFIG.JS"));
    try std.testing.expectEqualStrings("app:javascript", fileIconForName("prettier.js"));
}

test "fileIconForName maps tenth-cut clojure helm editorconfig" {
    try std.testing.expectEqualStrings("app:clojure", fileIconForName("core.clj"));
    try std.testing.expectEqualStrings("app:clojure", fileIconForName("main.cljs"));
    try std.testing.expectEqualStrings("app:clojure", fileIconForName("lib.cljc"));
    try std.testing.expectEqualStrings("app:clojure", fileIconForName("deps.edn"));
    try std.testing.expectEqualStrings("app:clojure", fileIconForName("CORE.CLJ"));
    try std.testing.expectEqualStrings("app:clojure", fileIconForName("DEPS.EDN"));

    try std.testing.expectEqualStrings("app:helm", fileIconForName("Chart.yaml"));
    try std.testing.expectEqualStrings("app:helm", fileIconForName("Chart.yml"));
    try std.testing.expectEqualStrings("app:helm", fileIconForName("values.yaml"));
    try std.testing.expectEqualStrings("app:helm", fileIconForName("values.yml"));
    try std.testing.expectEqualStrings("app:helm", fileIconForName("helmfile.yaml"));
    try std.testing.expectEqualStrings("app:helm", fileIconForName("helmfile.yml"));
    try std.testing.expectEqualStrings("app:helm", fileIconForName("CHART.YAML"));
    try std.testing.expectEqualStrings("app:helm", fileIconForName("VALUES.YML"));
    try std.testing.expectEqualStrings("app:helm", fileIconForName("HELMFILE.YAML"));
    try std.testing.expectEqualStrings("app:kubernetes", fileIconForName("kustomization.yaml"));
    try std.testing.expectEqualStrings("app:yaml", fileIconForName("deployment.yaml"));
    try std.testing.expectEqualStrings("app:yaml", fileIconForName("app.yaml"));
    try std.testing.expectEqualStrings("app:file", fileIconForName("chart.helm"));

    try std.testing.expectEqualStrings("app:editorconfig", fileIconForName(".editorconfig"));
    try std.testing.expectEqualStrings("app:editorconfig", fileIconForName(".EDITORCONFIG"));
    try std.testing.expectEqualStrings("app:settings", fileIconForName(".env"));
    try std.testing.expectEqualStrings("app:settings", fileIconForName(".env.local"));
}

test "fileIconForName maps eleventh-cut graphql nest pug" {
    try std.testing.expectEqualStrings("app:graphql", fileIconForName("schema.graphql"));
    try std.testing.expectEqualStrings("app:graphql", fileIconForName("query.gql"));
    try std.testing.expectEqualStrings("app:graphql", fileIconForName("SCHEMA.GRAPHQL"));
    try std.testing.expectEqualStrings("app:graphql", fileIconForName("QUERY.GQL"));

    try std.testing.expectEqualStrings("app:nest", fileIconForName("nest-cli.json"));
    try std.testing.expectEqualStrings("app:nest", fileIconForName("NEST-CLI.JSON"));
    try std.testing.expectEqualStrings("app:json", fileIconForName("nest-cli.dev.json"));

    try std.testing.expectEqualStrings("app:pug", fileIconForName("index.pug"));
    try std.testing.expectEqualStrings("app:pug", fileIconForName("layout.jade"));
    try std.testing.expectEqualStrings("app:pug", fileIconForName("INDEX.PUG"));
    try std.testing.expectEqualStrings("app:pug", fileIconForName("LAYOUT.JADE"));
}

test "fileIconForName unmatched stories stay generic" {
    try std.testing.expectEqualStrings("app:typescript", fileIconForName("index.ts"));
    try std.testing.expectEqualStrings("app:javascript", fileIconForName("stories.js"));
    try std.testing.expectEqualStrings("app:settings", fileIconForName("other.toml"));
}

test "fileIconForPath uses the basename of a repo-relative path" {
    try std.testing.expectEqualStrings("app:console", fileIconForPath("scripts/setup.sh"));
    try std.testing.expectEqualStrings("app:nodejs", fileIconForPath("src/package.json"));
    try std.testing.expectEqualStrings("app:git", fileIconForPath(".gitignore"));
    try std.testing.expectEqualStrings("app:zig", fileIconForPath("src/main.zig"));
    try std.testing.expectEqualStrings("app:ruby", fileIconForPath("lib/app.rb"));
    try std.testing.expectEqualStrings("app:svg", fileIconForPath("assets/logo.svg"));
    try std.testing.expectEqualStrings("app:zip", fileIconForPath("dist/out.zip"));
    try std.testing.expectEqualStrings("app:audio", fileIconForPath("assets/track.mp3"));
    try std.testing.expectEqualStrings("app:video", fileIconForPath("assets/clip.mp4"));
    try std.testing.expectEqualStrings("app:settings", fileIconForPath("config/php.ini"));
    try std.testing.expectEqualStrings("app:certificate", fileIconForPath("LICENSE"));
    try std.testing.expectEqualStrings("app:nginx", fileIconForPath("deploy/nginx.conf"));
    try std.testing.expectEqualStrings("app:exe", fileIconForPath("bin/a.exe"));
    try std.testing.expectEqualStrings("app:lockfile", fileIconForPath("foo.lock"));
    try std.testing.expectEqualStrings("app:next", fileIconForPath("apps/web/next.config.ts"));
    try std.testing.expectEqualStrings("app:prisma", fileIconForPath("prisma/schema.prisma"));
    try std.testing.expectEqualStrings("app:storybook", fileIconForPath("src/Button.stories.tsx"));
    try std.testing.expectEqualStrings("app:cmake", fileIconForPath("src/CMakeLists.txt"));
    try std.testing.expectEqualStrings("app:gitlab", fileIconForPath(".gitlab-ci.yml"));
    try std.testing.expectEqualStrings("app:gradle", fileIconForPath("android/build.gradle"));
    try std.testing.expectEqualStrings("app:kubernetes", fileIconForPath("k8s/kustomization.yaml"));
    try std.testing.expectEqualStrings("app:coffee", fileIconForPath("src/app.coffee"));
    try std.testing.expectEqualStrings("app:tex", fileIconForPath("docs/paper.tex"));
    try std.testing.expectEqualStrings("app:crystal", fileIconForPath("src/shard.cr"));
    try std.testing.expectEqualStrings("app:elm", fileIconForPath("src/Main.elm"));
    try std.testing.expectEqualStrings("app:erlang", fileIconForPath("src/mod.erl"));
    try std.testing.expectEqualStrings("app:haxe", fileIconForPath("src/Main.hx"));
    try std.testing.expectEqualStrings("app:jinja", fileIconForPath("templates/page.j2"));
    try std.testing.expectEqualStrings("app:xaml", fileIconForPath("ui/Window.xaml"));
    try std.testing.expectEqualStrings("app:diff", fileIconForPath("changes.patch"));
    try std.testing.expectEqualStrings("app:julia", fileIconForPath("src/main.jl"));
    try std.testing.expectEqualStrings("app:kotlin", fileIconForPath("src/Main.kt"));
    try std.testing.expectEqualStrings("app:kotlin", fileIconForPath("src/build.kts"));
    try std.testing.expectEqualStrings("app:prettier", fileIconForPath(".prettierrc"));
    try std.testing.expectEqualStrings("app:prettier", fileIconForPath("prettier.config.mjs"));
    try std.testing.expectEqualStrings("app:clojure", fileIconForPath("src/core.clj"));
    try std.testing.expectEqualStrings("app:clojure", fileIconForPath("src/deps.edn"));
    try std.testing.expectEqualStrings("app:helm", fileIconForPath("charts/app/Chart.yaml"));
    try std.testing.expectEqualStrings("app:helm", fileIconForPath("charts/app/values.yml"));
    try std.testing.expectEqualStrings("app:helm", fileIconForPath("helmfile.yaml"));
    try std.testing.expectEqualStrings("app:editorconfig", fileIconForPath(".editorconfig"));
    try std.testing.expectEqualStrings("app:graphql", fileIconForPath("schema.graphql"));
    try std.testing.expectEqualStrings("app:graphql", fileIconForPath("api/query.gql"));
    try std.testing.expectEqualStrings("app:nest", fileIconForPath("nest-cli.json"));
    try std.testing.expectEqualStrings("app:pug", fileIconForPath("views/index.pug"));
    try std.testing.expectEqualStrings("app:pug", fileIconForPath("views/layout.jade"));
    try std.testing.expectEqualStrings("app:file", fileIconForPath("notes.txt"));
}

test "filesTreeIcon file rows ignore expand state" {
    try std.testing.expectEqualStrings("app:console", filesTreeIcon("run.sh", true, true));
    try std.testing.expectEqualStrings("app:console", filesTreeIcon("run.sh", true, false));
    try std.testing.expectEqualStrings("app:readme", filesTreeIcon("README.md", true, true));
}

test "files tree icons stay in Native built-ins or registered app: names" {
    const samples = [_][]const u8{
        filesTreeIcon("src/", false, false),
        filesTreeIcon("src/", false, true),
        fileIconForName("run.sh"),
        fileIconForName("build.ps1"),
        fileIconForName("package.json"),
        fileIconForName("package-lock.json"),
        fileIconForName("bun.lock"),
        fileIconForName("vite.config.ts"),
        fileIconForName("out.zip"),
        fileIconForName("lib.jar"),
        fileIconForName("src.tar.xz"),
        fileIconForName("track.mp3"),
        fileIconForName("clip.mp4"),
        fileIconForName("clip.mkv"),
        fileIconForName("php.ini"),
        fileIconForName("other.toml"),
        fileIconForName("LICENSE"),
        fileIconForName("licence"),
        fileIconForName("COPYING"),
        fileIconForName("nginx.conf"),
        fileIconForName("a.exe"),
        fileIconForName("lib.dll"),
        fileIconForName("lib.so"),
        fileIconForName("lib.dylib"),
        fileIconForName("foo.lock"),
        fileIconForName("Cargo.lock"),
        fileIconForName("package-lock.json"),
        fileIconForName(".gitignore"),
        fileIconForName("README.md"),
        fileIconForName("Makefile"),
        fileIconForName("Dockerfile"),
        fileIconForName("main.zig"),
        fileIconForName("lib.rs"),
        fileIconForName("Panel.tsx"),
        fileIconForName("app.rb"),
        fileIconForName("index.php"),
        fileIconForName("Gemfile"),
        fileIconForName("composer.json"),
        fileIconForName("logo.svg"),
        fileIconForName("schema.sql"),
        fileIconForName("app.wasm"),
        fileIconForName("next.config.ts"),
        fileIconForName("app.component.ts"),
        fileIconForName("schema.prisma"),
        fileIconForName("turbo.json"),
        fileIconForName("Button.stories.tsx"),
        fileIconForName("tailwind.config.js"),
        fileIconForName("firebase.json"),
        fileIconForName("supabase.toml"),
        fileIconForName("rollup.config.mjs"),
        fileIconForName(".stylelintrc"),
        fileIconForName("svelte.config.js"),
        fileIconForName("vue.config.js"),
        fileIconForName("CMakeLists.txt"),
        fileIconForName("cmake.in"),
        fileIconForName("app.coffee"),
        fileIconForName("data.cson"),
        fileIconForName(".gitlab-ci.yml"),
        fileIconForName(".gitlab-ci.yaml"),
        fileIconForName("build.gradle"),
        fileIconForName("settings.gradle"),
        fileIconForName("gradlew"),
        fileIconForName("gradlew.bat"),
        fileIconForName("kustomization.yaml"),
        fileIconForName("kustomization.yml"),
        fileIconForName("paper.tex"),
        fileIconForName("macro.sty"),
        fileIconForName("article.cls"),
        fileIconForName("shard.cr"),
        fileIconForName("Main.elm"),
        fileIconForName("mod.erl"),
        fileIconForName("mod.hrl"),
        fileIconForName("Main.hx"),
        fileIconForName("build.hxml"),
        fileIconForName("page.jinja"),
        fileIconForName("page.j2"),
        fileIconForName("Window.xaml"),
        fileIconForName("changes.diff"),
        fileIconForName("changes.patch"),
        fileIconForName("main.jl"),
        fileIconForName("Main.kt"),
        fileIconForName("build.kts"),
        fileIconForName(".prettierrc"),
        fileIconForName(".prettierrc.json"),
        fileIconForName(".prettierignore"),
        fileIconForName("prettier.config.js"),
        fileIconForName("core.clj"),
        fileIconForName("deps.edn"),
        fileIconForName("Chart.yaml"),
        fileIconForName("values.yml"),
        fileIconForName("helmfile.yaml"),
        fileIconForName(".editorconfig"),
        fileIconForName("schema.graphql"),
        fileIconForName("query.gql"),
        fileIconForName("nest-cli.json"),
        fileIconForName("index.pug"),
        fileIconForName("layout.jade"),
        fileIconForName("unknown.data"),
        fileIconForName("notes.txt"),
    };
    for (samples) |name| {
        try std.testing.expect(iconIsResolvable(name));
    }
}
