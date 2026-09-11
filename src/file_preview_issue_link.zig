//! Files Preview + transcript markdown `issue-link-base`
//! (first-cut).
//!
//! Rendered Files `<markdown>` and transcript user / tool / reasoning /
//! assistant `<markdown>` bind the same Native `issue-link-base` so
//! bare `#N` refs become `base ++ number`. The prefix is derived from
//! the selected session `project_path` via one-shot local `git remote`
//! then `git remote get-url <name>` (prefer `origin`, else the first
//! plausible name — same as `git_checkout.pickRemoteName`). GitHub /
//! GitLab HTTPS and SSH remotes become
//! `https://github.com/<owner>/<repo>/issues/` or
//! `https://<gitlab-host>/<path>/-/issues/` (gitlab.com or a
//! GitLab-shaped self-hosted host). `.git` is stripped. Empty /
//! non-forge remotes leave the binding empty so `#N` stays unlinked
//! (no invented default repo). Runtime-only — not sessions.json.
//! Probe runs on session select / `project_path` change / boot even
//! when Files Preview is closed, so transcript `#N` does not need
//! Files open. Clicks still go through existing `on-link` →
//! `file_preview_open_url` / `transcript_open_url` / `open_url` OS
//! spawn. Verified: Native markdown `issue-link-base` (literal URL
//! prefix or one `{binding}`).
//!
//! Distinct spawn-key band (540+). Unix uses the same `/bin/sh -c`
//! chdir workaround `fx ask` uses (`fx_ask_chdir_script`); `remote`,
//! `get-url`, and the remote name are their own argv slots — never
//! interpolated into the `-c` script. Windows: `git.exe -C
//! <project_path> remote get-url <name>`.

const std = @import("std");
const builtin = @import("builtin");
const native_sdk = @import("native_sdk");
const main = @import("main.zig");
const git_checkout = @import("git_checkout.zig");
const git_remotes = @import("git_remotes.zig");
const git_branch = @import("git_branch.zig");

const Model = main.Model;
const Effects = main.Effects;
const writeFixed = main.writeFixed;

/// Files Preview + transcript `git remote` / `git remote get-url`.
/// Distinct from skills (530+) and git_common_dir (500+). Band is 540+.
/// Incremented per spawn so a cancelled probe cannot paint a later
/// preview / session.
pub const key_first: u64 = 540;

pub const git_bin = git_checkout.git_bin;
pub const windows_git_bin = git_checkout.windows_git_bin;
pub const git_c_flag = git_checkout.git_c_flag;
pub const git_remote_cmd = git_checkout.git_remote_cmd;
pub const git_get_url_cmd = "get-url";
pub const sh_bin = git_checkout.sh_bin;

pub const max_issue_link_base: usize = 512;
pub const max_remote_name: usize = git_branch.max_git_branch;

pub const ProbePhase = enum { list, url };

/// Unix `/bin/sh -c` chdir + git remote get-url NAME (9). Windows
/// `git.exe -C` is 6; this is the spawn buffer (max of the two).
pub const get_url_argv_len: usize = 9;
pub const unix_get_url_argv_len: usize = 9;
pub const windows_get_url_argv_len: usize = 6;

pub const github_issues_suffix = "/issues/";
pub const gitlab_issues_suffix = "/-/issues/";
pub const https_prefix = "https://";

pub fn unixGetUrlArgvFor(cwd: []const u8, remote: []const u8, buf: *[get_url_argv_len][]const u8) []const []const u8 {
    buf.* = .{
        sh_bin,
        "-c",
        main.fx_ask_chdir_script,
        "sh",
        cwd,
        git_bin,
        git_remote_cmd,
        git_get_url_cmd,
        remote,
    };
    return buf[0..unix_get_url_argv_len];
}

pub fn windowsGetUrlArgvFor(cwd: []const u8, remote: []const u8, buf: *[get_url_argv_len][]const u8) []const []const u8 {
    buf[0] = windows_git_bin;
    buf[1] = git_c_flag;
    buf[2] = cwd;
    buf[3] = git_remote_cmd;
    buf[4] = git_get_url_cmd;
    buf[5] = remote;
    return buf[0..windows_get_url_argv_len];
}

pub fn getUrlArgvFor(cwd: []const u8, remote: []const u8, buf: *[get_url_argv_len][]const u8) []const []const u8 {
    return switch (builtin.os.tag) {
        .windows => windowsGetUrlArgvFor(cwd, remote, buf),
        else => unixGetUrlArgvFor(cwd, remote, buf),
    };
}

fn isUnixGitRemoteGetUrlArgv(argv: []const []const u8) bool {
    if (argv.len != unix_get_url_argv_len) return false;
    if (!std.mem.eql(u8, argv[0], sh_bin)) return false;
    if (!std.mem.eql(u8, argv[1], "-c")) return false;
    if (!std.mem.eql(u8, argv[2], main.fx_ask_chdir_script)) return false;
    if (!std.mem.eql(u8, argv[5], git_bin)) return false;
    if (!std.mem.eql(u8, argv[6], git_remote_cmd)) return false;
    if (!std.mem.eql(u8, argv[7], git_get_url_cmd)) return false;
    return git_checkout.isPlausibleRemoteName(argv[8]);
}

fn isWindowsGitRemoteGetUrlArgv(argv: []const []const u8) bool {
    if (argv.len != windows_get_url_argv_len) return false;
    const bin_ok = std.mem.eql(u8, argv[0], windows_git_bin) or std.mem.eql(u8, argv[0], git_bin);
    if (!bin_ok) return false;
    if (!std.mem.eql(u8, argv[1], git_c_flag)) return false;
    if (argv[2].len == 0) return false;
    if (!std.mem.eql(u8, argv[3], git_remote_cmd)) return false;
    if (!std.mem.eql(u8, argv[4], git_get_url_cmd)) return false;
    return git_checkout.isPlausibleRemoteName(argv[5]);
}

pub fn isGitRemoteGetUrlArgv(argv: []const []const u8) bool {
    return isUnixGitRemoteGetUrlArgv(argv) or isWindowsGitRemoteGetUrlArgv(argv);
}

pub fn isGitRemoteListArgv(argv: []const []const u8) bool {
    return git_remotes.isGitRemotesArgv(argv);
}

pub fn probeSupported() bool {
    return true;
}

/// Slice binding for Files Preview and transcript
/// `<markdown issue-link-base="{file_preview_issue_link_base}">`.
/// Empty when missing / in-flight / non-forge so `#N` stays unlinked.
pub fn base(model: *const Model) []const u8 {
    return model.file_preview_issue_link_base_storage[0..model.file_preview_issue_link_base_len];
}

fn remoteName(model: *const Model) []const u8 {
    return model.file_preview_issue_link_remote_storage[0..model.file_preview_issue_link_remote_len];
}

fn probedPath(model: *const Model) []const u8 {
    return model.file_preview_issue_link_probe_path_storage[0..model.file_preview_issue_link_probe_path_len];
}

fn firstStdoutLine(raw: []const u8) []const u8 {
    const trimmed = std.mem.trim(u8, raw, " \t\r\n");
    if (trimmed.len == 0) return "";
    const end = std.mem.indexOfAny(u8, trimmed, "\r\n") orelse trimmed.len;
    return std.mem.trim(u8, trimmed[0..end], " \t");
}

fn looksLikeLocalPath(raw: []const u8) bool {
    if (raw.len == 0) return true;
    if (raw[0] == '/' or raw[0] == '\\' or raw[0] == '.') return true;
    if (raw.len >= 2 and std.ascii.isAlphabetic(raw[0]) and raw[1] == ':') {
        if (raw.len == 2) return true;
        return raw[2] == '/' or raw[2] == '\\';
    }
    return false;
}

fn stripScheme(raw: []const u8) ?[]const u8 {
    const schemes = [_][]const u8{
        "https://",
        "http://",
        "git+https://",
        "git+ssh://",
        "ssh://",
        "git://",
    };
    for (schemes) |scheme| {
        if (std.ascii.startsWithIgnoreCase(raw, scheme)) {
            return raw[scheme.len..];
        }
    }
    return null;
}

fn hostIsGitHub(host: []const u8) bool {
    return std.ascii.eqlIgnoreCase(host, "github.com") or std.ascii.eqlIgnoreCase(host, "www.github.com");
}

fn hostIsGitLab(host: []const u8) bool {
    if (std.ascii.eqlIgnoreCase(host, "gitlab.com") or std.ascii.eqlIgnoreCase(host, "www.gitlab.com")) {
        return true;
    }
    var it = std.mem.splitScalar(u8, host, '.');
    while (it.next()) |label| {
        if (std.ascii.eqlIgnoreCase(label, "gitlab")) return true;
    }
    return false;
}

const Forge = enum { github, gitlab };

fn forgeKind(host: []const u8) ?Forge {
    if (hostIsGitHub(host)) return .github;
    if (hostIsGitLab(host)) return .gitlab;
    return null;
}

fn canonicalHost(host: []const u8, kind: Forge, dest: []u8) ?[]const u8 {
    if (kind == .github) {
        const name = "github.com";
        if (name.len > dest.len) return null;
        @memcpy(dest[0..name.len], name);
        return dest[0..name.len];
    }
    if (std.ascii.eqlIgnoreCase(host, "www.gitlab.com") or std.ascii.eqlIgnoreCase(host, "gitlab.com")) {
        const name = "gitlab.com";
        if (name.len > dest.len) return null;
        @memcpy(dest[0..name.len], name);
        return dest[0..name.len];
    }
    if (host.len == 0 or host.len > dest.len) return null;
    var i: usize = 0;
    while (i < host.len) : (i += 1) {
        dest[i] = std.ascii.toLower(host[i]);
    }
    return dest[0..host.len];
}

const HostPath = struct {
    host: []const u8,
    path: []const u8,
};

fn parseUrlHostPath(rest: []const u8) ?HostPath {
    var cursor = rest;
    if (std.mem.indexOfScalar(u8, rest, '@')) |at| {
        const slash = std.mem.indexOfScalar(u8, rest, '/') orelse rest.len;
        if (at < slash) {
            cursor = rest[at + 1 ..];
        }
    }
    if (cursor.len == 0 or cursor[0] == '[') return null;
    var host_end: usize = 0;
    while (host_end < cursor.len) : (host_end += 1) {
        const c = cursor[host_end];
        if (c == '/' or c == ':' or c == '?' or c == '#') break;
    }
    const host = cursor[0..host_end];
    if (host.len == 0) return null;
    var path_start = host_end;
    if (path_start < cursor.len and cursor[path_start] == ':') {
        path_start += 1;
        while (path_start < cursor.len and std.ascii.isDigit(cursor[path_start])) : (path_start += 1) {}
    }
    if (path_start < cursor.len and cursor[path_start] == '/') path_start += 1;
    var path = if (path_start < cursor.len) cursor[path_start..] else "";
    if (std.mem.indexOfAny(u8, path, "?#")) |cut| path = path[0..cut];
    return .{ .host = host, .path = path };
}

fn parseScpHostPath(raw: []const u8) ?HostPath {
    const colon = std.mem.indexOfScalar(u8, raw, ':') orelse return null;
    if (colon == 0) return null;
    var host_start: usize = 0;
    if (std.mem.lastIndexOfScalar(u8, raw[0..colon], '@')) |at| {
        host_start = at + 1;
    }
    const host = raw[host_start..colon];
    if (host.len == 0 or std.mem.indexOfScalar(u8, host, '/') != null) return null;
    var path = raw[colon + 1 ..];
    if (path.len > 0 and path[0] == '/') path = path[1..];
    if (std.mem.indexOfAny(u8, path, "?#")) |cut| path = path[0..cut];
    return .{ .host = host, .path = path };
}

fn endsWithIgnoreCase(haystack: []const u8, suffix: []const u8) bool {
    if (haystack.len < suffix.len) return false;
    return std.ascii.eqlIgnoreCase(haystack[haystack.len - suffix.len ..], suffix);
}

fn stripGitSuffix(path: []const u8) []const u8 {
    var p = std.mem.trim(u8, path, "/");
    if (endsWithIgnoreCase(p, ".git")) {
        p = p[0 .. p.len - ".git".len];
        p = std.mem.trimEnd(u8, p, "/");
    }
    return p;
}

fn pathHasUsableSegments(path: []const u8, github: bool) bool {
    var count: usize = 0;
    var it = std.mem.splitScalar(u8, path, '/');
    while (it.next()) |seg| {
        if (seg.len == 0) continue;
        if (std.mem.eql(u8, seg, ".") or std.mem.eql(u8, seg, "..")) return false;
        count += 1;
        if (github and count == 2) return true;
    }
    return count >= 2;
}

fn writeIssueBase(
    dest: []u8,
    host: []const u8,
    path: []const u8,
    kind: Forge,
) ?[]const u8 {
    var len: usize = 0;
    const prefix = https_prefix;
    if (prefix.len + host.len + 1 + path.len + gitlab_issues_suffix.len > dest.len) return null;
    @memcpy(dest[len..][0..prefix.len], prefix);
    len += prefix.len;
    @memcpy(dest[len..][0..host.len], host);
    len += host.len;
    dest[len] = '/';
    len += 1;

    var written_segs: usize = 0;
    var it = std.mem.splitScalar(u8, path, '/');
    while (it.next()) |seg| {
        if (seg.len == 0) continue;
        if (kind == .github and written_segs == 2) break;
        if (written_segs > 0) {
            dest[len] = '/';
            len += 1;
        }
        @memcpy(dest[len..][0..seg.len], seg);
        len += seg.len;
        written_segs += 1;
    }
    if (written_segs < 2) return null;
    const suffix = if (kind == .gitlab) gitlab_issues_suffix else github_issues_suffix;
    @memcpy(dest[len..][0..suffix.len], suffix);
    len += suffix.len;
    return dest[0..len];
}

/// Parse a git remote URL into a Native `issue-link-base` prefix, or
/// `null` when the remote is empty / not a GitHub or GitLab forge.
pub fn issueLinkBaseFromRemoteUrl(raw: []const u8, dest: []u8) ?[]const u8 {
    const line = firstStdoutLine(raw);
    if (line.len == 0 or line.len > 2048) return null;
    if (looksLikeLocalPath(line)) return null;

    const host_path = if (stripScheme(line)) |rest|
        parseUrlHostPath(rest)
    else
        parseScpHostPath(line);
    const parsed = host_path orelse return null;
    const kind = forgeKind(parsed.host) orelse return null;
    const path = stripGitSuffix(parsed.path);
    if (!pathHasUsableSegments(path, kind == .github)) return null;

    var host_buf: [253]u8 = undefined;
    const host = canonicalHost(parsed.host, kind, host_buf[0..]) orelse return null;
    return writeIssueBase(dest, host, path, kind);
}

fn probePath(model: *const Model) []const u8 {
    const path = model.selectedProjectPath();
    if (path.len == 0) return "";
    const io = model.store_io orelse return "";
    if (!main.directoryExists(io, path)) return "";
    return path;
}

fn cancelInFlight(model: *Model, fx: *Effects) void {
    if (model.file_preview_issue_link_key == 0) return;
    fx.cancel(model.file_preview_issue_link_key);
    model.file_preview_issue_link_key = 0;
}

fn clearCache(model: *Model) void {
    model.file_preview_issue_link_ready = false;
    model.file_preview_issue_link_base_len = 0;
    model.file_preview_issue_link_remote_len = 0;
    model.file_preview_issue_link_phase = .list;
    model.file_preview_issue_link_probe_session = 0;
    model.file_preview_issue_link_probe_path_len = 0;
}

/// Cancel any in-flight probe and clear the binding. Session-switch /
/// New Task / remove / empty `project_path` — not Files Preview close
/// or hide (transcript `#N` still needs the same-project cache).
pub fn drop(model: *Model, fx: ?*Effects) void {
    if (fx) |effects| cancelInFlight(model, effects) else {
        model.file_preview_issue_link_key = 0;
    }
    clearCache(model);
}

fn probeMatches(model: *const Model, cwd: []const u8) bool {
    if (model.file_preview_issue_link_probe_session != model.selected) return false;
    return std.mem.eql(u8, cwd, probedPath(model));
}

fn spawnList(model: *Model, fx: *Effects, cwd: []const u8) void {
    const key = model.next_file_preview_issue_link_key;
    model.next_file_preview_issue_link_key = key + 1;
    model.file_preview_issue_link_key = key;
    model.file_preview_issue_link_phase = .list;
    model.file_preview_issue_link_probe_session = model.selected;
    writeFixed(&model.file_preview_issue_link_probe_path_storage, &model.file_preview_issue_link_probe_path_len, cwd);
    model.file_preview_issue_link_remote_len = 0;

    var argv_buf: [git_remotes.argv_len][]const u8 = undefined;
    fx.spawn(.{
        .key = key,
        .argv = git_remotes.argvFor(cwd, &argv_buf),
        .on_line = Effects.lineMsg(.fx_line),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
}

fn spawnGetUrl(model: *Model, fx: *Effects, cwd: []const u8) void {
    const remote = remoteName(model);
    if (!git_checkout.isPlausibleRemoteName(remote)) {
        model.file_preview_issue_link_ready = true;
        model.file_preview_issue_link_base_len = 0;
        return;
    }
    const key = model.next_file_preview_issue_link_key;
    model.next_file_preview_issue_link_key = key + 1;
    model.file_preview_issue_link_key = key;
    model.file_preview_issue_link_phase = .url;

    var argv_buf: [get_url_argv_len][]const u8 = undefined;
    fx.spawn(.{
        .key = key,
        .argv = getUrlArgvFor(cwd, remote, &argv_buf),
        .on_line = Effects.lineMsg(.fx_line),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
}

/// Spawn `git remote` when the selected session has a usable
/// `project_path` and this project has not already been probed.
/// Empty / missing `project_path` clears the binding. Same-project
/// Files Preview Source / file switch / close keeps a ready
/// (possibly empty) cache so transcript `#N` still linkifies
/// without opening Files.
pub fn refresh(model: *Model, fx: ?*Effects) void {
    if (!probeSupported()) {
        drop(model, fx);
        return;
    }
    const cwd = probePath(model);
    if (cwd.len == 0) {
        drop(model, fx);
        return;
    }
    if ((model.file_preview_issue_link_key != 0 or model.file_preview_issue_link_ready) and probeMatches(model, cwd)) {
        return;
    }
    const effects = fx orelse return;
    cancelInFlight(model, effects);
    clearCache(model);
    spawnList(model, effects, cwd);
}

fn probeStillCurrent(model: *const Model) bool {
    if (model.file_preview_issue_link_key == 0) return false;
    const cwd = model.selectedProjectPath();
    return probeMatches(model, cwd);
}

fn rememberRemoteName(model: *Model, raw: []const u8) void {
    var it = std.mem.splitScalar(u8, raw, '\n');
    while (it.next()) |line| {
        const name = std.mem.trim(u8, line, " \t\r\n");
        if (!git_checkout.isPlausibleRemoteName(name)) continue;
        if (std.mem.eql(u8, name, git_checkout.git_origin_remote)) {
            writeFixed(&model.file_preview_issue_link_remote_storage, &model.file_preview_issue_link_remote_len, name);
            return;
        }
        if (model.file_preview_issue_link_remote_len == 0) {
            writeFixed(&model.file_preview_issue_link_remote_storage, &model.file_preview_issue_link_remote_len, name);
        }
    }
}

pub fn applyLine(model: *Model, line: native_sdk.EffectLine) void {
    if (line.key != model.file_preview_issue_link_key or model.file_preview_issue_link_key == 0) return;
    if (!probeStillCurrent(model)) return;
    switch (model.file_preview_issue_link_phase) {
        .list => rememberRemoteName(model, line.line),
        .url => {
            var buf: [max_issue_link_base]u8 = undefined;
            const parsed = issueLinkBaseFromRemoteUrl(line.line, buf[0..]) orelse {
                model.file_preview_issue_link_base_len = 0;
                return;
            };
            writeFixed(&model.file_preview_issue_link_base_storage, &model.file_preview_issue_link_base_len, parsed);
        },
    }
}

pub fn handleExit(model: *Model, fx: *Effects, exit: native_sdk.EffectExit) void {
    if (exit.key != model.file_preview_issue_link_key or model.file_preview_issue_link_key == 0) return;
    const current = probeStillCurrent(model);
    const phase = model.file_preview_issue_link_phase;
    model.file_preview_issue_link_key = 0;
    if (!current or exit.reason != .exited) {
        clearCache(model);
        return;
    }
    switch (phase) {
        .list => {
            if (exit.code != 0 or remoteName(model).len == 0) {
                model.file_preview_issue_link_ready = true;
                model.file_preview_issue_link_base_len = 0;
                return;
            }
            const cwd = probedPath(model);
            spawnGetUrl(model, fx, cwd);
        },
        .url => {
            if (exit.code != 0) model.file_preview_issue_link_base_len = 0;
            model.file_preview_issue_link_ready = true;
        },
    }
}

test "argv is chdir script plus git remote get-url as its own slots" {
    var buf: [get_url_argv_len][]const u8 = undefined;
    const argv = unixGetUrlArgvFor("/tmp/faku-issue-link", "origin", &buf);
    try std.testing.expectEqual(@as(usize, unix_get_url_argv_len), argv.len);
    try std.testing.expectEqualStrings(sh_bin, argv[0]);
    try std.testing.expectEqualStrings("-c", argv[1]);
    try std.testing.expectEqualStrings(main.fx_ask_chdir_script, argv[2]);
    try std.testing.expectEqualStrings("sh", argv[3]);
    try std.testing.expectEqualStrings("/tmp/faku-issue-link", argv[4]);
    try std.testing.expectEqualStrings(git_bin, argv[5]);
    try std.testing.expectEqualStrings(git_remote_cmd, argv[6]);
    try std.testing.expectEqualStrings(git_get_url_cmd, argv[7]);
    try std.testing.expectEqualStrings("origin", argv[8]);
    try std.testing.expect(isGitRemoteGetUrlArgv(argv));
    try std.testing.expect(!isGitRemoteListArgv(argv));
    try std.testing.expect(!git_remotes.isGitRemotesArgv(argv));
    try std.testing.expect(std.mem.indexOf(u8, argv[2], git_get_url_cmd) == null);
    try std.testing.expect(std.mem.indexOf(u8, argv[2], "origin") == null);
    try std.testing.expect(key_first >= 540);
    try std.testing.expect(key_first > git_remotes.git_remotes_key_first);
    try std.testing.expect(key_first > @import("skills.zig").skills_key_first);
}

test "windows git argv is git.exe -C PATH remote get-url NAME" {
    var buf: [get_url_argv_len][]const u8 = undefined;
    const cwd = "C:\\Users\\me\\proj";
    const argv = windowsGetUrlArgvFor(cwd, "origin", &buf);
    try std.testing.expectEqual(@as(usize, windows_get_url_argv_len), argv.len);
    try std.testing.expectEqualStrings(windows_git_bin, argv[0]);
    try std.testing.expectEqualStrings(git_c_flag, argv[1]);
    try std.testing.expectEqualStrings(cwd, argv[2]);
    try std.testing.expectEqualStrings(git_remote_cmd, argv[3]);
    try std.testing.expectEqualStrings(git_get_url_cmd, argv[4]);
    try std.testing.expectEqualStrings("origin", argv[5]);
    try std.testing.expect(isGitRemoteGetUrlArgv(argv));
    try std.testing.expect(!isGitRemoteListArgv(argv));
    var git_only: [get_url_argv_len][]const u8 = undefined;
    git_only[0] = git_bin;
    git_only[1] = git_c_flag;
    git_only[2] = cwd;
    git_only[3] = git_remote_cmd;
    git_only[4] = git_get_url_cmd;
    git_only[5] = "upstream";
    try std.testing.expect(isGitRemoteGetUrlArgv(git_only[0..windows_get_url_argv_len]));
    try std.testing.expect(!isGitRemoteGetUrlArgv(&.{ windows_git_bin, git_c_flag, cwd, git_remote_cmd }));
}

test "issueLinkBaseFromRemoteUrl parses github/gitlab https+ssh and rejects junk" {
    var dest: [max_issue_link_base]u8 = undefined;

    try std.testing.expectEqualStrings(
        "https://github.com/owner/repo/issues/",
        issueLinkBaseFromRemoteUrl("https://github.com/owner/repo.git", dest[0..]).?,
    );
    try std.testing.expectEqualStrings(
        "https://github.com/owner/repo/issues/",
        issueLinkBaseFromRemoteUrl("https://github.com/owner/repo", dest[0..]).?,
    );
    try std.testing.expectEqualStrings(
        "https://github.com/owner/repo/issues/",
        issueLinkBaseFromRemoteUrl("https://github.com/owner/repo.git/\n", dest[0..]).?,
    );
    try std.testing.expectEqualStrings(
        "https://github.com/owner/repo/issues/",
        issueLinkBaseFromRemoteUrl("git@github.com:owner/repo.git", dest[0..]).?,
    );
    try std.testing.expectEqualStrings(
        "https://github.com/Keej/Faku/issues/",
        issueLinkBaseFromRemoteUrl("ssh://git@github.com/Keej/Faku.git", dest[0..]).?,
    );
    try std.testing.expectEqualStrings(
        "https://github.com/owner/repo/issues/",
        issueLinkBaseFromRemoteUrl("ssh://git@github.com:22/owner/repo.git", dest[0..]).?,
    );
    try std.testing.expectEqualStrings(
        "https://github.com/owner/repo/issues/",
        issueLinkBaseFromRemoteUrl("https://user:token@github.com/owner/repo.git", dest[0..]).?,
    );
    try std.testing.expectEqualStrings(
        "https://github.com/owner/repo/issues/",
        issueLinkBaseFromRemoteUrl("HTTPS://WWW.GITHUB.COM/owner/repo.GIT", dest[0..]).?,
    );
    try std.testing.expectEqualStrings(
        "https://github.com/owner/repo/issues/",
        issueLinkBaseFromRemoteUrl("git://github.com/owner/repo.git", dest[0..]).?,
    );

    try std.testing.expectEqualStrings(
        "https://gitlab.com/owner/repo/-/issues/",
        issueLinkBaseFromRemoteUrl("https://gitlab.com/owner/repo.git", dest[0..]).?,
    );
    try std.testing.expectEqualStrings(
        "https://gitlab.com/group/sub/repo/-/issues/",
        issueLinkBaseFromRemoteUrl("git@gitlab.com:group/sub/repo.git", dest[0..]).?,
    );
    try std.testing.expectEqualStrings(
        "https://gitlab.example.com/owner/repo/-/issues/",
        issueLinkBaseFromRemoteUrl("https://gitlab.example.com/owner/repo.git", dest[0..]).?,
    );
    try std.testing.expectEqualStrings(
        "https://gitlab.com/owner/repo/-/issues/",
        issueLinkBaseFromRemoteUrl("ssh://git@gitlab.com/owner/repo.git", dest[0..]).?,
    );

    try std.testing.expect(issueLinkBaseFromRemoteUrl("", dest[0..]) == null);
    try std.testing.expect(issueLinkBaseFromRemoteUrl("   \n", dest[0..]) == null);
    try std.testing.expect(issueLinkBaseFromRemoteUrl("/tmp/local-repo.git", dest[0..]) == null);
    try std.testing.expect(issueLinkBaseFromRemoteUrl("file:///tmp/repo.git", dest[0..]) == null);
    try std.testing.expect(issueLinkBaseFromRemoteUrl("C:\\Users\\me\\repo.git", dest[0..]) == null);
    try std.testing.expect(issueLinkBaseFromRemoteUrl("https://bitbucket.org/owner/repo.git", dest[0..]) == null);
    try std.testing.expect(issueLinkBaseFromRemoteUrl("https://example.com/owner/repo.git", dest[0..]) == null);
    try std.testing.expect(issueLinkBaseFromRemoteUrl("https://github.com/owner", dest[0..]) == null);
    try std.testing.expect(issueLinkBaseFromRemoteUrl("git@github.com:owner", dest[0..]) == null);
    try std.testing.expect(issueLinkBaseFromRemoteUrl("https://gist.github.com/owner/repo.git", dest[0..]) == null);
    try std.testing.expect(issueLinkBaseFromRemoteUrl("not-a-url", dest[0..]) == null);
}

test "Files Preview markdown sets issue-link-base from origin get-url; close keeps cache" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, "/tmp/faku-md-issue-link-{s}", .{tmp.sub_path});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);
    var readme_buf: [300]u8 = undefined;
    const readme = try std.fmt.bufPrint(&readme_buf, "{s}/README.md", .{project});
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{
        .sub_path = readme,
        .data = "# Hello\n\nSee #123 and #412.\n",
    });
    var other_buf: [300]u8 = undefined;
    const other = try std.fmt.bufPrint(&other_buf, "{s}/other.md", .{project});
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{
        .sub_path = other,
        .data = "# Other #99\n",
    });

    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("md issue link", .fx);
    model.selected = id;
    model.setSelectedProjectPath(project);
    const file_mention = @import("file_mention.zig");
    const right_panel = @import("right_panel.zig");
    file_mention.applyStdoutPaths(&model, "README.md\nother.md\n");
    defer right_panel.clearFilePreview(&model);
    defer file_mention.clearCache(&model);

    right_panel.selectCachedFile(&model, &fx, 1);
    try std.testing.expect(model.file_preview_shows_rendered_markdown());
    try std.testing.expectEqualStrings("", base(&model));
    try std.testing.expectEqual(key_first, model.file_preview_issue_link_key);
    try std.testing.expect(!git_checkout.gitMutationInFlight(&model));

    var found_list: ?@TypeOf(fx.pendingSpawnAt(0).?) = null;
    var i: usize = 0;
    while (i < fx.pendingSpawnCount()) : (i += 1) {
        const spawn = fx.pendingSpawnAt(i).?;
        if (spawn.key == model.file_preview_issue_link_key and isGitRemoteListArgv(spawn.argv)) {
            found_list = spawn;
            break;
        }
    }
    const list_spawn = found_list orelse return error.MissingIssueLinkRemoteListSpawn;
    try std.testing.expect(list_spawn.key >= key_first);
    try std.testing.expect(std.mem.indexOf(u8, list_spawn.argv[2], git_remote_cmd) == null);
    try std.testing.expect(std.mem.indexOf(u8, main.app_markup, "issue-link-base=\"{file_preview_issue_link_base}\"") != null);

    applyLine(&model, .{ .key = list_spawn.key, .line = "upstream\norigin\n" });
    handleExit(&model, &fx, .{ .key = list_spawn.key, .reason = .exited, .code = 0 });
    try std.testing.expectEqualStrings("origin", remoteName(&model));
    try std.testing.expectEqual(key_first + 1, model.file_preview_issue_link_key);

    var found_url: ?@TypeOf(fx.pendingSpawnAt(0).?) = null;
    i = 0;
    while (i < fx.pendingSpawnCount()) : (i += 1) {
        const spawn = fx.pendingSpawnAt(i).?;
        if (spawn.key == model.file_preview_issue_link_key and isGitRemoteGetUrlArgv(spawn.argv)) {
            found_url = spawn;
            break;
        }
    }
    const url_spawn = found_url orelse return error.MissingIssueLinkGetUrlSpawn;
    try std.testing.expect(isGitRemoteGetUrlArgv(url_spawn.argv));
    try std.testing.expectEqualStrings("origin", url_spawn.argv[url_spawn.argv.len - 1]);
    try std.testing.expect(std.mem.indexOf(u8, url_spawn.argv[2], "origin") == null);
    try std.testing.expect(std.mem.indexOf(u8, url_spawn.argv[2], git_get_url_cmd) == null);

    applyLine(&model, .{ .key = url_spawn.key, .line = "git@github.com:keejkrej/faku.git\n" });
    handleExit(&model, &fx, .{ .key = url_spawn.key, .reason = .exited, .code = 0 });
    try std.testing.expectEqual(@as(u64, 0), model.file_preview_issue_link_key);
    try std.testing.expect(model.file_preview_issue_link_ready);
    try std.testing.expectEqualStrings("https://github.com/keejkrej/faku/issues/", base(&model));
    try std.testing.expectEqualStrings("https://github.com/keejkrej/faku/issues/", model.file_preview_issue_link_base());

    right_panel.selectCachedFile(&model, &fx, 2);
    try std.testing.expect(model.file_preview_shows_rendered_markdown());
    try std.testing.expectEqualStrings("https://github.com/keejkrej/faku/issues/", base(&model));
    try std.testing.expectEqual(@as(u64, 0), model.file_preview_issue_link_key);

    main.update(&model, .set_file_preview_markdown_source, &fx);
    try std.testing.expect(!model.file_preview_shows_rendered_markdown());
    try std.testing.expectEqualStrings("https://github.com/keejkrej/faku/issues/", base(&model));

    main.update(&model, .set_file_preview_markdown_preview, &fx);
    try std.testing.expectEqualStrings("https://github.com/keejkrej/faku/issues/", base(&model));

    main.update(&model, .close_right_panel_file_preview, &fx);
    try std.testing.expectEqualStrings("https://github.com/keejkrej/faku/issues/", base(&model));
    try std.testing.expect(model.file_preview_issue_link_ready);
    try std.testing.expectEqual(@as(u64, 0), model.file_preview_issue_link_key);

    main.update(&model, .hide_right_panel, &fx);
    try std.testing.expectEqualStrings("https://github.com/keejkrej/faku/issues/", base(&model));
    try std.testing.expect(model.file_preview_issue_link_ready);
}

test "Files Preview markdown leaves issue-link-base empty for non-forge remotes" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, "/tmp/faku-md-issue-link-junk-{s}", .{tmp.sub_path});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);
    var readme_buf: [300]u8 = undefined;
    const readme = try std.fmt.bufPrint(&readme_buf, "{s}/README.md", .{project});
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{
        .sub_path = readme,
        .data = "See #1\n",
    });

    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("md issue junk", .fx);
    model.selected = id;
    model.setSelectedProjectPath(project);
    const file_mention = @import("file_mention.zig");
    const right_panel = @import("right_panel.zig");
    file_mention.applyStdoutPaths(&model, "README.md\n");
    defer right_panel.clearFilePreview(&model);
    defer file_mention.clearCache(&model);

    right_panel.selectCachedFile(&model, &fx, 1);
    const list_key = model.file_preview_issue_link_key;
    try std.testing.expect(list_key != 0);
    applyLine(&model, .{ .key = list_key, .line = "origin\n" });
    handleExit(&model, &fx, .{ .key = list_key, .reason = .exited, .code = 0 });
    const url_key = model.file_preview_issue_link_key;
    try std.testing.expect(url_key != 0);
    applyLine(&model, .{ .key = url_key, .line = "https://example.com/owner/repo.git\n" });
    handleExit(&model, &fx, .{ .key = url_key, .reason = .exited, .code = 0 });
    try std.testing.expect(model.file_preview_issue_link_ready);
    try std.testing.expectEqualStrings("", base(&model));

    drop(&model, &fx);
    try std.testing.expectEqualStrings("", base(&model));
}

fn completeOriginGetUrl(model: *Model, fx: *Effects, url: []const u8) !void {
    const list_key = model.file_preview_issue_link_key;
    try std.testing.expect(list_key != 0);
    applyLine(model, .{ .key = list_key, .line = "origin\n" });
    handleExit(model, fx, .{ .key = list_key, .reason = .exited, .code = 0 });
    const url_key = model.file_preview_issue_link_key;
    try std.testing.expect(url_key != 0);
    applyLine(model, .{ .key = url_key, .line = url });
    handleExit(model, fx, .{ .key = url_key, .reason = .exited, .code = 0 });
}

test "transcript markdown probes issue-link-base without Files Preview" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, "/tmp/faku-tx-issue-link-{s}", .{tmp.sub_path});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("tx issue link", .fx);
    model.selected = id;
    model.setSelectedProjectPath(project);
    _ = model.appendTurn(id, .assistant, "See #415\n");
    try std.testing.expectEqual(@as(u32, 0), model.right_panel_file_preview_id);
    try std.testing.expect(!model.file_preview_shows_rendered_markdown());
    try std.testing.expectEqualStrings("", base(&model));

    refresh(&model, &fx);
    try std.testing.expectEqual(key_first, model.file_preview_issue_link_key);
    try std.testing.expect(!git_checkout.gitMutationInFlight(&model));
    try completeOriginGetUrl(&model, &fx, "git@github.com:keejkrej/faku.git\n");
    try std.testing.expectEqual(@as(u64, 0), model.file_preview_issue_link_key);
    try std.testing.expect(model.file_preview_issue_link_ready);
    try std.testing.expectEqualStrings("https://github.com/keejkrej/faku/issues/", base(&model));
    try std.testing.expectEqualStrings("https://github.com/keejkrej/faku/issues/", model.file_preview_issue_link_base());
    try std.testing.expect(std.mem.indexOf(u8, main.app_markup, "<markdown source=\"{t.text}\" images=\"{transcript_images}\" details-expanded=\"{transcript_details_expanded}\" issue-link-base=\"{file_preview_issue_link_base}\" on-details=\"transcript_toggle_details\" on-link=\"transcript_open_url\"") != null);

    const before_key = model.next_file_preview_issue_link_key;
    refresh(&model, &fx);
    try std.testing.expectEqual(before_key, model.next_file_preview_issue_link_key);
    try std.testing.expectEqualStrings("https://github.com/keejkrej/faku/issues/", base(&model));

    drop(&model, &fx);
    try std.testing.expectEqualStrings("", base(&model));
    try std.testing.expect(!model.file_preview_issue_link_ready);
    try std.testing.expectEqual(@as(u64, 0), model.file_preview_issue_link_key);

    const other = model.addSession("tx issue other", .fx);
    if (model.sessionById(other)) |session| session.setProjectPath("");
    main.update(&model, .{ .select = other }, &fx);
    try std.testing.expectEqualStrings("", base(&model));
    try std.testing.expect(!model.file_preview_issue_link_ready);
    try std.testing.expectEqual(@as(u64, 0), model.file_preview_issue_link_key);
}

test "transcript markdown leaves issue-link-base empty for non-forge remotes without Files Preview" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, "/tmp/faku-tx-issue-link-junk-{s}", .{tmp.sub_path});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.store_io = std.testing.io;
    const id = model.addSession("tx issue junk", .fx);
    model.selected = id;
    model.setSelectedProjectPath(project);
    try std.testing.expectEqual(@as(u32, 0), model.right_panel_file_preview_id);

    refresh(&model, &fx);
    try completeOriginGetUrl(&model, &fx, "https://example.com/owner/repo.git\n");
    try std.testing.expect(model.file_preview_issue_link_ready);
    try std.testing.expectEqualStrings("", base(&model));
}

test "issue-link-base stays out of sessions.json" {
    const store = @import("store.zig");
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [256]u8 = undefined;
    const dir = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}/faku-tx-issue-link-catalog", .{tmp.sub_path[0..]});

    var project_buf: [256]u8 = undefined;
    const project = try std.fmt.bufPrint(&project_buf, "/tmp/faku-tx-issue-link-catalog-{s}", .{tmp.sub_path});
    try std.Io.Dir.cwd().createDirPath(std.testing.io, project);

    var fx = Effects.init(std.testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;

    var model = Model{};
    model.task_state_loaded = true;
    model.setStoreDir(dir);
    model.store_io = std.testing.io;
    const id = model.addSession("tx issue catalog", .fx);
    model.selected = id;
    model.setSelectedProjectPath(project);
    _ = model.appendTurn(id, .assistant, "See #415\n");
    refresh(&model, &fx);
    try completeOriginGetUrl(&model, &fx, "git@github.com:keejkrej/faku.git\n");
    try std.testing.expectEqualStrings("https://github.com/keejkrej/faku/issues/", base(&model));

    try store.saveSession(&model, id, std.testing.allocator, std.testing.io);

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = store.catalogPath(dir, &path_buf).?;
    try std.testing.expectEqualStrings("sessions.json", store.catalog_name);
    const bytes = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "issue_link") == null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "issue-link-base") == null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "file_preview_issue_link") == null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "keejkrej/faku") == null);

    var loaded = Model{};
    loaded.setStoreDir(dir);
    try std.testing.expectEqual(store.LoadKind.loaded, store.loadCatalog(&loaded, std.testing.allocator, std.testing.io));
    store.hydrateSession(&loaded, id, std.testing.allocator, std.testing.io);
    try std.testing.expectEqualStrings("", loaded.file_preview_issue_link_base());
}
