//! Composer chip, access, effort, slash-prefix, and attach helpers.
//!
//! Access / effort labels, chip option tables, slash command prefix,
//! and image-drop path checks live here. Model chip cycling and
//! persist stay in `main.zig`. Behavior is unchanged from the former
//! `main` composer helpers.

const std = @import("std");

pub const access_chip_options = [_]struct { id: []const u8, label: []const u8 }{
    .{ .id = "ask", .label = "Ask" },
    .{ .id = "auto", .label = "Auto" },
    .{ .id = "fullAccess", .label = "Full access" },
};

pub const effort_chip_options = [_]struct { id: []const u8, label: []const u8 }{
    .{ .id = "auto", .label = "Auto" },
    .{ .id = "none", .label = "None" },
    .{ .id = "minimal", .label = "Minimal" },
    .{ .id = "low", .label = "Low" },
    .{ .id = "medium", .label = "Medium" },
    .{ .id = "high", .label = "High" },
    .{ .id = "xhigh", .label = "Extra high" },
    .{ .id = "max", .label = "Max" },
};

/// Waku `runtime_mode` → verified `FX_PERMISSION_MODE` (`ask`/`auto`/`yolo`).
/// Unknown strings persist but do not set the env.
pub fn fxPermissionMode(access_mode: []const u8) []const u8 {
    if (std.mem.eql(u8, access_mode, "ask")) return "ask";
    if (std.mem.eql(u8, access_mode, "autoAcceptEdits")) return "auto";
    if (std.mem.eql(u8, access_mode, "auto")) return "auto";
    if (std.mem.eql(u8, access_mode, "fullAccess")) return "yolo";
    if (std.mem.eql(u8, access_mode, "yolo")) return "yolo";
    return "";
}

/// ask → auto → fullAccess. `autoAcceptEdits` counts as auto; `yolo` / empty
/// count as fullAccess. Unknown strings restart at ask.
pub fn nextAccessMode(access_mode: []const u8) []const u8 {
    if (std.mem.eql(u8, access_mode, "ask")) return "auto";
    if (std.mem.eql(u8, access_mode, "auto") or std.mem.eql(u8, access_mode, "autoAcceptEdits")) return "fullAccess";
    return "ask";
}

pub fn accessLabel(access_mode: []const u8) []const u8 {
    if (std.mem.eql(u8, access_mode, "ask")) return "Ask";
    if (std.mem.eql(u8, access_mode, "auto") or std.mem.eql(u8, access_mode, "autoAcceptEdits")) return "Auto";
    return "Full access";
}

/// auto → none → minimal → low → medium → high → xhigh → max → auto.
/// Empty and unknown strings restart at none (same as starting from auto).
pub fn nextReasoningEffort(effort: []const u8) []const u8 {
    if (std.mem.eql(u8, effort, "auto") or effort.len == 0) return "none";
    if (std.mem.eql(u8, effort, "none")) return "minimal";
    if (std.mem.eql(u8, effort, "minimal")) return "low";
    if (std.mem.eql(u8, effort, "low")) return "medium";
    if (std.mem.eql(u8, effort, "medium")) return "high";
    if (std.mem.eql(u8, effort, "high")) return "xhigh";
    if (std.mem.eql(u8, effort, "xhigh")) return "max";
    return "auto";
}

pub fn effortLabel(effort: []const u8) []const u8 {
    if (std.mem.eql(u8, effort, "none")) return "None";
    if (std.mem.eql(u8, effort, "minimal")) return "Minimal";
    if (std.mem.eql(u8, effort, "low")) return "Low";
    if (std.mem.eql(u8, effort, "medium")) return "Medium";
    if (std.mem.eql(u8, effort, "high")) return "High";
    if (std.mem.eql(u8, effort, "xhigh")) return "Extra high";
    if (std.mem.eql(u8, effort, "max")) return "Max";
    return "Auto";
}

pub fn isDocumentedReasoningEffort(effort: []const u8) bool {
    return std.mem.eql(u8, effort, "auto") or
        std.mem.eql(u8, effort, "none") or
        std.mem.eql(u8, effort, "minimal") or
        std.mem.eql(u8, effort, "low") or
        std.mem.eql(u8, effort, "medium") or
        std.mem.eql(u8, effort, "high") or
        std.mem.eql(u8, effort, "xhigh") or
        std.mem.eql(u8, effort, "max");
}

/// Active slash prefix: draft starts with `/` and the first token has
/// no whitespace yet. Returns the name after `/` (`""` for `/` alone).
/// `/commit ` or later text is a completed command — not a prefix.
pub fn slashCommandPrefix(draft: []const u8) ?[]const u8 {
    if (draft.len == 0 or draft[0] != '/') return null;
    const rest = draft[1..];
    for (rest) |c| {
        if (std.ascii.isWhitespace(c)) return null;
    }
    return rest;
}

/// First dropped path that is a local image Faku already understands
/// for `fx ask --image` / attach preview. Existing extensions only:
/// png, jpg, jpeg, webp, gif. Directories (trailing separator) and
/// empty lists are ignored.
pub fn imagePathFromDrop(paths: []const []const u8) ?[]const u8 {
    for (paths) |raw| {
        const path = std.mem.trim(u8, raw, " \t\r\n");
        if (!isAttachImagePath(path)) continue;
        return path;
    }
    return null;
}

pub fn isAttachImagePath(path: []const u8) bool {
    if (path.len == 0) return false;
    const last = path[path.len - 1];
    if (last == '/' or last == '\\') return false;
    const ext = std.fs.path.extension(path);
    return std.ascii.eqlIgnoreCase(ext, ".png") or
        std.ascii.eqlIgnoreCase(ext, ".jpg") or
        std.ascii.eqlIgnoreCase(ext, ".jpeg") or
        std.ascii.eqlIgnoreCase(ext, ".webp") or
        std.ascii.eqlIgnoreCase(ext, ".gif");
}
