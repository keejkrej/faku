//! First-cut Material file-type app icons (MIT SVGs under
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
};

pub fn contains(name: []const u8) bool {
    for (app_icons) |entry| {
        if (std.mem.eql(u8, entry.name, name)) return true;
    }
    return false;
}

test "file-type app_icons names are unique and parse to shapes" {
    try std.testing.expectEqual(@as(usize, 24), app_icons.len);
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
    try std.testing.expect(!contains("app:zig"));
    try std.testing.expect(!contains("file-text"));
}
