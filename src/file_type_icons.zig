//! Material file-type app icons (MIT SVGs under
//! `src/icons/file-types/`). Registry names are the bare `zig` /
//! `rust` / … strings; markup and `file_icon` return `app:<name>`.
//! Combined with shell chrome icons in `shell.app_icons` so the
//! model contract / `native check` see one table.

const std = @import("std");
const native_sdk = @import("native_sdk");

const canvas = native_sdk.canvas;

fn parse(comptime name: []const u8) canvas.svg_icon.Icon {
    return canvas.svg_icon.parseComptime(@embedFile("icons/file-types/" ++ name ++ ".svg"));
}

const zig_icon = parse("zig");
const rust_icon = parse("rust");
const go_icon = parse("go");
const python_icon = parse("python");
const javascript_icon = parse("javascript");
const typescript_icon = parse("typescript");
const react_icon = parse("react");
const vue_icon = parse("vue");
const svelte_icon = parse("svelte");
const html_icon = parse("html");
const css_icon = parse("css");
const markdown_icon = parse("markdown");
const json_icon = parse("json");
const yaml_icon = parse("yaml");
const xml_icon = parse("xml");
const image_icon = parse("image");
const docker_icon = parse("docker");
const c_icon = parse("c");
const cpp_icon = parse("cpp");
const java_icon = parse("java");
const makefile_icon = parse("makefile");
const nodejs_icon = parse("nodejs");
const readme_icon = parse("readme");
const git_icon = parse("git");
const ruby_icon = parse("ruby");
const php_icon = parse("php");
const swift_icon = parse("swift");
const scala_icon = parse("scala");
const dart_icon = parse("dart");
const lua_icon = parse("lua");
const haskell_icon = parse("haskell");
const elixir_icon = parse("elixir");
const csharp_icon = parse("csharp");
const perl_icon = parse("perl");
const ocaml_icon = parse("ocaml");
const solidity_icon = parse("solidity");
const nix_icon = parse("nix");
const astro_icon = parse("astro");
const sass_icon = parse("sass");
const proto_icon = parse("proto");
const database_icon = parse("database");
const pdf_icon = parse("pdf");
const svg_icon = parse("svg");
const terraform_icon = parse("terraform");
const webassembly_icon = parse("webassembly");
const bun_icon = parse("bun");
const npm_icon = parse("npm");
const yarn_icon = parse("yarn");
const pnpm_icon = parse("pnpm");
const deno_icon = parse("deno");
const console_icon = parse("console");
const powershell_icon = parse("powershell");
const vite_icon = parse("vite");
const vitest_icon = parse("vitest");
const eslint_icon = parse("eslint");
const biome_icon = parse("biome");
const babel_icon = parse("babel");
const webpack_icon = parse("webpack");

/// Bare names (no `app:` prefix). `file_icon` returns `app:` + these.
pub const app_icons = [_]canvas.icons.Entry{
    .{ .name = "zig", .icon = &zig_icon },
    .{ .name = "rust", .icon = &rust_icon },
    .{ .name = "go", .icon = &go_icon },
    .{ .name = "python", .icon = &python_icon },
    .{ .name = "javascript", .icon = &javascript_icon },
    .{ .name = "typescript", .icon = &typescript_icon },
    .{ .name = "react", .icon = &react_icon },
    .{ .name = "vue", .icon = &vue_icon },
    .{ .name = "svelte", .icon = &svelte_icon },
    .{ .name = "html", .icon = &html_icon },
    .{ .name = "css", .icon = &css_icon },
    .{ .name = "markdown", .icon = &markdown_icon },
    .{ .name = "json", .icon = &json_icon },
    .{ .name = "yaml", .icon = &yaml_icon },
    .{ .name = "xml", .icon = &xml_icon },
    .{ .name = "image", .icon = &image_icon },
    .{ .name = "docker", .icon = &docker_icon },
    .{ .name = "c", .icon = &c_icon },
    .{ .name = "cpp", .icon = &cpp_icon },
    .{ .name = "java", .icon = &java_icon },
    .{ .name = "makefile", .icon = &makefile_icon },
    .{ .name = "nodejs", .icon = &nodejs_icon },
    .{ .name = "readme", .icon = &readme_icon },
    .{ .name = "git", .icon = &git_icon },
    .{ .name = "ruby", .icon = &ruby_icon },
    .{ .name = "php", .icon = &php_icon },
    .{ .name = "swift", .icon = &swift_icon },
    .{ .name = "scala", .icon = &scala_icon },
    .{ .name = "dart", .icon = &dart_icon },
    .{ .name = "lua", .icon = &lua_icon },
    .{ .name = "haskell", .icon = &haskell_icon },
    .{ .name = "elixir", .icon = &elixir_icon },
    .{ .name = "csharp", .icon = &csharp_icon },
    .{ .name = "perl", .icon = &perl_icon },
    .{ .name = "ocaml", .icon = &ocaml_icon },
    .{ .name = "solidity", .icon = &solidity_icon },
    .{ .name = "nix", .icon = &nix_icon },
    .{ .name = "astro", .icon = &astro_icon },
    .{ .name = "sass", .icon = &sass_icon },
    .{ .name = "proto", .icon = &proto_icon },
    .{ .name = "database", .icon = &database_icon },
    .{ .name = "pdf", .icon = &pdf_icon },
    .{ .name = "svg", .icon = &svg_icon },
    .{ .name = "terraform", .icon = &terraform_icon },
    .{ .name = "webassembly", .icon = &webassembly_icon },
    .{ .name = "bun", .icon = &bun_icon },
    .{ .name = "npm", .icon = &npm_icon },
    .{ .name = "yarn", .icon = &yarn_icon },
    .{ .name = "pnpm", .icon = &pnpm_icon },
    .{ .name = "deno", .icon = &deno_icon },
    .{ .name = "console", .icon = &console_icon },
    .{ .name = "powershell", .icon = &powershell_icon },
    .{ .name = "vite", .icon = &vite_icon },
    .{ .name = "vitest", .icon = &vitest_icon },
    .{ .name = "eslint", .icon = &eslint_icon },
    .{ .name = "biome", .icon = &biome_icon },
    .{ .name = "babel", .icon = &babel_icon },
    .{ .name = "webpack", .icon = &webpack_icon },
};

pub fn contains(name: []const u8) bool {
    for (app_icons) |entry| {
        if (std.mem.eql(u8, entry.name, name)) return true;
    }
    return false;
}

test "file-type app_icons names are unique and parse to shapes" {
    try std.testing.expectEqual(@as(usize, 58), app_icons.len);
    var i: usize = 0;
    while (i < app_icons.len) : (i += 1) {
        try std.testing.expect(app_icons[i].icon.shapes.len > 0);
        var j: usize = i + 1;
        while (j < app_icons.len) : (j += 1) {
            try std.testing.expect(!std.mem.eql(u8, app_icons[i].name, app_icons[j].name));
        }
    }
    try std.testing.expect(contains("zig"));
    try std.testing.expect(contains("git"));
    try std.testing.expect(contains("ruby"));
    try std.testing.expect(contains("webassembly"));
    try std.testing.expect(contains("svg"));
    try std.testing.expect(contains("bun"));
    try std.testing.expect(contains("console"));
    try std.testing.expect(contains("webpack"));
    try std.testing.expect(!contains("kotlin"));
    try std.testing.expect(!contains("graphql"));
    try std.testing.expect(!contains("prettier"));
    try std.testing.expect(!contains("app:zig"));
    try std.testing.expect(!contains("file-text"));
}
