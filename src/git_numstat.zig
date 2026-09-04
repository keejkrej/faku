//! One-shot tracked +/- plus untracked text-line additions for the
//! composer project row.
//!
//! Native has no git/workspace effect. When the selected session has a
//! non-empty `project_path` that exists, Faku `fx.spawn`s
//! `git diff --numstat HEAD --`. Tracked binary rows (`-` in either
//! column) are skipped. Zero / failed / empty omits the label — this
//! cut does not invent "clean". Deletions stay tracked-only. On Unix,
//! the same spawn also prints synthetic `N\t0\tpath` rows for
//! untracked, non-ignored text files (`git ls-files --others
//! --exclude-standard`). Binary / unreadable / oversized (over 1 MiB)
//! untracked files are skipped. The Commit… include-unstaged snapshot
//! reuses `argvFor` / `numstat_untracked_script` on its own 460+ key
//! band. Not Waku's daemon `InspectBranches`, not a live watch, not a
//! staged/unstaged split, not Waku's Environment Summary, and not
//! Review.
//!
//! Unix uses the same `/bin/sh -c` chdir workaround `fx ask` uses
//! (`fx_ask_chdir_script`) plus a packed `numstat_untracked_script`
//! (tracked numstat first, then find+grep untracked text rows).
//! Windows cannot use `/bin/sh` or that untracked path:
//! `git.exe -C <project_path> diff --numstat HEAD --` (path is its
//! own argv slot, not interpolated into a script). Tracked numstat
//! stdout is the same on Windows; CRLF is already trimmed in the line
//! helpers. Untracked synthetic rows stay Unix-only this cut — no
//! PowerShell untracked path. app.zon already includes windows.
//! Remaining git modules (common_dir, checkout/commit) still skip
//! Windows this cut. Windows numstat is tracked-only.
//!
//! Spawn/line/exit orchestration lives here. Effect key stays
//! `git_numstat_key_first` (350+).

const std = @import("std");
const builtin = @import("builtin");
const native_sdk = @import("native_sdk");
const main = @import("main.zig");

const Model = main.Model;
const Effects = main.Effects;
const writeFixed = main.writeFixed;

/// One-shot numstat + untracked-text probe. Distinct from
/// git_branch (200+), git_dirty (300+), git_push (360+),
/// git_worktree_add (370+), git_ahead_behind (380+), maximize /
/// pick-image / fx-ask / daemon / clipboard / probe keys, and from
/// file_mention (400+). Incremented per refresh so a cancelled spawn
/// cannot paint a later session.
pub const git_numstat_key_first: u64 = 350;

/// `+18446744073709551615 −18446744073709551615` is 45 bytes.
pub const max_git_numstat_label: usize = 48;

/// Untracked files larger than this are skipped so one huge file
/// does not hang the one-shot. Tracked numstat has no extra bound.
pub const untracked_max_bytes: u32 = 1 * 1024 * 1024;
pub const untracked_max_bytes_s = "1048576";

pub const git_bin = "git";
/// PATH-resolved Windows Git (explicit `.exe` like sibling
/// `powershell.exe` / `explorer.exe` / `wt.exe` / `cmd.exe`).
pub const windows_git_bin = "git.exe";
pub const git_c_flag = "-C";
pub const git_diff_cmd = "diff";
pub const git_numstat = "--numstat";
pub const git_head = "HEAD";
pub const git_pathspec_end = "--";
pub const git_ls_files_cmd = "ls-files";
pub const git_ls_files_others = "--others";
pub const git_ls_files_exclude_standard = "--exclude-standard";
pub const sh_bin = "/bin/sh";
pub const grep_bin = "grep";
pub const grep_text_flag = "-Iq";

/// Packed into one `-c` string so the spawn stays under Native
/// `max_effect_argv` (16). Real numstat first; then synthetic
/// `N\t0\tpath` rows so the existing parse/sum path counts
/// untracked text as additions. `grep -Iq '^'` is a portable
/// macos/linux text check (binary files fail). `find -size` skips
/// files over 1 MiB without reading them.
pub const numstat_untracked_script =
    \\git diff --numstat HEAD -- || exit $?
    \\git ls-files --others --exclude-standard 2>/dev/null | while IFS= read -r f || [ -n "$f" ]; do
    \\[ -z "$f" ] && continue
    \\[ -f "$f" ] || continue
    \\[ -n "$(find "$f" -size +1048576c -print)" ] && continue
    \\grep -Iq '^' -- "$f" || continue
    \\n=$(grep -c '^' -- "$f" || true)
    \\[ "$n" -gt 0 ] || continue
    \\printf '%s\t0\t%s\n' "$n" "$f"
    \\done
;

/// Unix `/bin/sh -c` chdir + nested `/bin/sh -c` +
/// `numstat_untracked_script` (8). Windows `git.exe -C` tracked-only
/// is 7; this is the spawn buffer (max of the two).
pub const argv_len: usize = 8;
pub const unix_argv_len: usize = 8;
pub const windows_argv_len: usize = 7;

pub const NumstatDelta = struct {
    additions: u64 = 0,
    deletions: u64 = 0,
};

pub fn unixArgvFor(cwd: []const u8, buf: *[argv_len][]const u8) []const []const u8 {
    buf.* = .{
        sh_bin,
        "-c",
        main.fx_ask_chdir_script,
        "sh",
        cwd,
        sh_bin,
        "-c",
        numstat_untracked_script,
    };
    return buf[0..unix_argv_len];
}

/// Windows: `git.exe -C <project_path> diff --numstat HEAD --`.
/// Path is its own argv slot (no `/bin/sh`, no packing into a cmd
/// string). Tracked-only — untracked synthetic rows stay Unix-only.
pub fn windowsArgvFor(cwd: []const u8, buf: *[argv_len][]const u8) []const []const u8 {
    buf[0] = windows_git_bin;
    buf[1] = git_c_flag;
    buf[2] = cwd;
    buf[3] = git_diff_cmd;
    buf[4] = git_numstat;
    buf[5] = git_head;
    buf[6] = git_pathspec_end;
    return buf[0..windows_argv_len];
}

pub fn argvFor(cwd: []const u8, buf: *[argv_len][]const u8) []const []const u8 {
    return switch (builtin.os.tag) {
        .windows => windowsArgvFor(cwd, buf),
        else => unixArgvFor(cwd, buf),
    };
}

fn scriptHas(script: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, script, needle) != null;
}

fn isUnixGitNumstatArgv(argv: []const []const u8) bool {
    if (argv.len != unix_argv_len) return false;
    if (!std.mem.eql(u8, argv[0], sh_bin)) return false;
    if (!std.mem.eql(u8, argv[1], "-c")) return false;
    if (!std.mem.eql(u8, argv[2], main.fx_ask_chdir_script)) return false;
    if (!std.mem.eql(u8, argv[5], sh_bin)) return false;
    if (!std.mem.eql(u8, argv[6], "-c")) return false;
    return std.mem.eql(u8, argv[7], numstat_untracked_script);
}

fn isWindowsGitNumstatArgv(argv: []const []const u8) bool {
    if (argv.len != windows_argv_len) return false;
    const bin_ok = std.mem.eql(u8, argv[0], windows_git_bin) or std.mem.eql(u8, argv[0], git_bin);
    if (!bin_ok) return false;
    if (!std.mem.eql(u8, argv[1], git_c_flag)) return false;
    if (argv[2].len == 0) return false;
    if (!std.mem.eql(u8, argv[3], git_diff_cmd)) return false;
    if (!std.mem.eql(u8, argv[4], git_numstat)) return false;
    if (!std.mem.eql(u8, argv[5], git_head)) return false;
    return std.mem.eql(u8, argv[6], git_pathspec_end);
}

pub fn isGitNumstatArgv(argv: []const []const u8) bool {
    return isUnixGitNumstatArgv(argv) or isWindowsGitNumstatArgv(argv);
}

pub fn probeSupported() bool {
    return true;
}

/// One `added\tdeleted\tpath` row. Binary (`-` in either column) and
/// blank / malformed lines are skipped. Synthetic untracked rows are
/// `N\t0\tpath`.
pub fn parseNumstatLine(raw: []const u8) ?NumstatDelta {
    const line = std.mem.trim(u8, raw, " \t\r\n");
    if (line.len == 0) return null;
    const first_tab = std.mem.indexOfScalar(u8, line, '\t') orelse return null;
    const added_s = line[0..first_tab];
    const rest = line[first_tab + 1 ..];
    const second_tab = std.mem.indexOfScalar(u8, rest, '\t') orelse return null;
    const deleted_s = rest[0..second_tab];
    if (std.mem.eql(u8, added_s, "-") or std.mem.eql(u8, deleted_s, "-")) return null;
    const additions = std.fmt.parseInt(u64, added_s, 10) catch return null;
    const deletions = std.fmt.parseInt(u64, deleted_s, 10) catch return null;
    return .{ .additions = additions, .deletions = deletions };
}

/// Sum numstat rows in a stdout chunk. Saturating u64. Binary and
/// blank lines ignored. Untracked text rows (`N\t0\tpath`) add to
/// additions only.
pub fn sumNumstat(raw: []const u8) NumstatDelta {
    var delta = NumstatDelta{};
    var it = std.mem.splitScalar(u8, raw, '\n');
    while (it.next()) |line| {
        const parsed = parseNumstatLine(line) orelse continue;
        delta.additions +|= parsed.additions;
        delta.deletions +|= parsed.deletions;
    }
    return delta;
}

/// `+N −M`. Empty when both counts are 0 (do not invent "clean").
/// Exact numbers even when huge; `buf` holds two u64 plus signs.
pub fn numstatLabel(additions: u64, deletions: u64, buf: *[max_git_numstat_label]u8) []const u8 {
    if (additions == 0 and deletions == 0) return "";
    return std.fmt.bufPrint(buf, "+{d} −{d}", .{ additions, deletions }) catch "";
}

pub fn gitNumstatLabel(model: *const Model) []const u8 {
    return model.git_numstat_label_storage[0..model.git_numstat_label_len];
}

pub fn hasGitNumstat(model: *const Model) bool {
    return model.git_numstat_additions > 0 or model.git_numstat_deletions > 0;
}

pub fn clearGitNumstat(model: *Model) void {
    setNumstat(model, 0, 0);
}

fn setNumstat(model: *Model, additions: u64, deletions: u64) void {
    model.git_numstat_additions = additions;
    model.git_numstat_deletions = deletions;
    if (additions == 0 and deletions == 0) {
        model.git_numstat_label_len = 0;
        return;
    }
    const written = numstatLabel(additions, deletions, &model.git_numstat_label_storage);
    model.git_numstat_label_len = written.len;
}

fn addNumstat(model: *Model, delta: NumstatDelta) void {
    if (delta.additions == 0 and delta.deletions == 0) return;
    setNumstat(
        model,
        model.git_numstat_additions +| delta.additions,
        model.git_numstat_deletions +| delta.deletions,
    );
}

fn cancelInFlight(model: *Model, fx: *Effects) void {
    if (model.git_numstat_key == 0) return;
    fx.cancel(model.git_numstat_key);
    model.git_numstat_key = 0;
}

fn probePath(model: *const Model) []const u8 {
    const path = model.selectedProjectPath();
    if (path.len == 0) return "";
    const io = model.store_io orelse return "";
    if (!main.directoryExists(io, path)) return "";
    return path;
}

/// Cancel any in-flight probe, drop the label, and spawn again when the
/// selected session has an existing `project_path`. Empty / missing
/// skips the spawn so the label stays omitted.
pub fn refresh(model: *Model, fx: *Effects) void {
    cancelInFlight(model, fx);
    clearGitNumstat(model);
    if (!probeSupported()) return;
    const cwd = probePath(model);
    if (cwd.len == 0) return;

    const key = model.next_git_numstat_key;
    model.next_git_numstat_key = key + 1;
    model.git_numstat_key = key;
    model.git_numstat_probe_session = model.selected;
    writeFixed(&model.git_numstat_probe_path_storage, &model.git_numstat_probe_path_len, cwd);

    var argv_buf: [argv_len][]const u8 = undefined;
    fx.spawn(.{
        .key = key,
        .argv = argvFor(cwd, &argv_buf),
        .on_line = Effects.lineMsg(.fx_line),
        .on_exit = Effects.exitMsg(.fx_exit),
    });
}

fn probeStillCurrent(model: *const Model) bool {
    if (model.git_numstat_key == 0) return false;
    if (model.git_numstat_probe_session != model.selected) return false;
    const path = model.selectedProjectPath();
    const probed = model.git_numstat_probe_path_storage[0..model.git_numstat_probe_path_len];
    return std.mem.eql(u8, path, probed);
}

pub fn applyLine(model: *Model, line: native_sdk.EffectLine) void {
    if (line.key != model.git_numstat_key or model.git_numstat_key == 0) return;
    if (!probeStillCurrent(model)) return;
    addNumstat(model, sumNumstat(line.line));
}

pub fn handleExit(model: *Model, exit: native_sdk.EffectExit) void {
    if (exit.key != model.git_numstat_key or model.git_numstat_key == 0) return;
    const current = probeStillCurrent(model);
    model.git_numstat_key = 0;
    if (!current or exit.reason != .exited or exit.code != 0) {
        clearGitNumstat(model);
    }
}

test "argv is chdir script plus numstat then untracked text rows" {
    const git_branch = @import("git_branch.zig");
    const git_dirty = @import("git_dirty.zig");
    const git_ahead_behind = @import("git_ahead_behind.zig");
    const file_mention = @import("file_mention.zig");
    var buf: [argv_len][]const u8 = undefined;
    const argv = unixArgvFor("/tmp/faku-numstat", &buf);
    try std.testing.expectEqual(@as(usize, unix_argv_len), argv.len);
    try std.testing.expectEqualStrings(sh_bin, argv[0]);
    try std.testing.expectEqualStrings("-c", argv[1]);
    try std.testing.expectEqualStrings(main.fx_ask_chdir_script, argv[2]);
    try std.testing.expectEqualStrings("sh", argv[3]);
    try std.testing.expectEqualStrings("/tmp/faku-numstat", argv[4]);
    try std.testing.expectEqualStrings(sh_bin, argv[5]);
    try std.testing.expectEqualStrings("-c", argv[6]);
    try std.testing.expectEqualStrings(numstat_untracked_script, argv[7]);
    try std.testing.expect(isGitNumstatArgv(argv));
    try std.testing.expect(!isGitNumstatArgv(&.{ git_bin, git_diff_cmd, git_numstat, git_head, git_pathspec_end }));
    try std.testing.expect(!isGitNumstatArgv(&.{
        sh_bin,
        "-c",
        main.fx_ask_chdir_script,
        "sh",
        "/tmp/faku-numstat",
        git_bin,
        git_diff_cmd,
        git_numstat,
        git_head,
        git_pathspec_end,
    }));
    try std.testing.expect(scriptHas(argv[7], git_diff_cmd));
    try std.testing.expect(scriptHas(argv[7], git_numstat));
    try std.testing.expect(scriptHas(argv[7], git_head));
    try std.testing.expect(scriptHas(argv[7], git_ls_files_cmd));
    try std.testing.expect(scriptHas(argv[7], git_ls_files_others));
    try std.testing.expect(scriptHas(argv[7], git_ls_files_exclude_standard));
    try std.testing.expect(scriptHas(argv[7], grep_bin));
    try std.testing.expect(scriptHas(argv[7], grep_text_flag));
    try std.testing.expect(scriptHas(argv[7], untracked_max_bytes_s));
    try std.testing.expect(scriptHas(argv[7], "\\t0\\t"));
    var branch_buf: [git_branch.argv_len][]const u8 = undefined;
    const branch = git_branch.unixArgvFor("/tmp/faku-numstat", &branch_buf);
    try std.testing.expect(!isGitNumstatArgv(branch));
    try std.testing.expect(!git_branch.isGitBranchArgv(argv));
    var dirty_buf: [git_dirty.argv_len][]const u8 = undefined;
    const dirty = git_dirty.unixArgvFor("/tmp/faku-numstat", &dirty_buf);
    try std.testing.expect(!isGitNumstatArgv(dirty));
    try std.testing.expect(!git_dirty.isGitDirtyArgv(argv));
    var ahead_buf: [git_ahead_behind.argv_len][]const u8 = undefined;
    const ahead = git_ahead_behind.unixArgvFor("/tmp/faku-numstat", &ahead_buf);
    try std.testing.expect(!isGitNumstatArgv(ahead));
    try std.testing.expect(!git_ahead_behind.isGitAheadBehindArgv(argv));
    var mention_buf: [file_mention.git_argv_len][]const u8 = undefined;
    const mention = file_mention.unixArgvFor("/tmp/faku-numstat", &mention_buf);
    try std.testing.expect(!isGitNumstatArgv(mention));
    try std.testing.expect(!file_mention.isGitLsFilesArgv(argv));
    var walk_buf: [file_mention.walk_argv_len][]const u8 = undefined;
    const walk = file_mention.unixWalkArgvFor("/tmp/faku-numstat", &walk_buf);
    try std.testing.expect(!isGitNumstatArgv(walk));
    try std.testing.expect(!file_mention.isWalkArgv(argv));
    try std.testing.expect(git_numstat_key_first > git_dirty.git_dirty_key_first);
    try std.testing.expect(git_dirty.git_dirty_key_first > git_branch.git_branch_key_first);
    try std.testing.expect(git_ahead_behind.git_ahead_behind_key_first > git_numstat_key_first);
    try std.testing.expect(file_mention.file_mention_key_first > git_ahead_behind.git_ahead_behind_key_first);
}

test "windows git argv is git.exe -C PATH diff --numstat HEAD --; path is its own slot" {
    const git_branch = @import("git_branch.zig");
    const git_dirty = @import("git_dirty.zig");
    const git_ahead_behind = @import("git_ahead_behind.zig");
    const file_mention = @import("file_mention.zig");
    var buf: [argv_len][]const u8 = undefined;
    const cwd = "C:\\Users\\me\\proj";
    const argv = windowsArgvFor(cwd, &buf);
    try std.testing.expectEqual(@as(usize, windows_argv_len), argv.len);
    try std.testing.expect(argv.len <= 16);
    try std.testing.expectEqualStrings(windows_git_bin, argv[0]);
    try std.testing.expectEqualStrings(git_c_flag, argv[1]);
    try std.testing.expectEqualStrings(cwd, argv[2]);
    try std.testing.expectEqualStrings(git_diff_cmd, argv[3]);
    try std.testing.expectEqualStrings(git_numstat, argv[4]);
    try std.testing.expectEqualStrings(git_head, argv[5]);
    try std.testing.expectEqualStrings(git_pathspec_end, argv[6]);
    try std.testing.expect(isGitNumstatArgv(argv));
    try std.testing.expect(!std.mem.eql(u8, argv[0], sh_bin));
    try std.testing.expect(!isGitNumstatArgv(&.{ windows_git_bin, git_c_flag, cwd }));
    try std.testing.expect(!isGitNumstatArgv(&.{
        windows_git_bin,
        git_c_flag,
        cwd,
        git_diff_cmd,
        git_numstat,
        git_head,
    }));
    var git_only: [argv_len][]const u8 = undefined;
    git_only[0] = git_bin;
    git_only[1] = git_c_flag;
    git_only[2] = cwd;
    git_only[3] = git_diff_cmd;
    git_only[4] = git_numstat;
    git_only[5] = git_head;
    git_only[6] = git_pathspec_end;
    try std.testing.expect(isGitNumstatArgv(git_only[0..windows_argv_len]));
    var branch_buf: [git_branch.argv_len][]const u8 = undefined;
    try std.testing.expect(!isGitNumstatArgv(git_branch.windowsArgvFor(cwd, &branch_buf)));
    try std.testing.expect(!git_branch.isGitBranchArgv(argv));
    var dirty_buf: [git_dirty.argv_len][]const u8 = undefined;
    try std.testing.expect(!isGitNumstatArgv(git_dirty.windowsArgvFor(cwd, &dirty_buf)));
    try std.testing.expect(!git_dirty.isGitDirtyArgv(argv));
    var ahead_buf: [git_ahead_behind.argv_len][]const u8 = undefined;
    try std.testing.expect(!isGitNumstatArgv(git_ahead_behind.windowsArgvFor(cwd, &ahead_buf)));
    try std.testing.expect(!git_ahead_behind.isGitAheadBehindArgv(argv));
    var mention_buf: [file_mention.git_argv_len][]const u8 = undefined;
    try std.testing.expect(!isGitNumstatArgv(file_mention.windowsArgvFor(cwd, &mention_buf)));
    try std.testing.expect(!file_mention.isGitLsFilesArgv(argv));
}

test "host argvFor matches the process OS" {
    var buf: [argv_len][]const u8 = undefined;
    const argv = argvFor("/tmp/faku-numstat", &buf);
    try std.testing.expect(isGitNumstatArgv(argv));
    switch (builtin.os.tag) {
        .windows => {
            try std.testing.expectEqualStrings(windows_git_bin, argv[0]);
            try std.testing.expectEqualStrings(git_c_flag, argv[1]);
            try std.testing.expectEqualStrings(git_diff_cmd, argv[3]);
            try std.testing.expectEqualStrings(git_numstat, argv[4]);
            try std.testing.expectEqualStrings(git_head, argv[5]);
            try std.testing.expectEqualStrings(git_pathspec_end, argv[6]);
        },
        else => {
            try std.testing.expectEqualStrings(sh_bin, argv[0]);
            try std.testing.expectEqualStrings(numstat_untracked_script, argv[7]);
        },
    }
}

test "probeSupported is true on macOS, Linux, and Windows" {
    try std.testing.expect(probeSupported());
}

test "sumNumstat skips binary and blanks; untracked rows add to +; numstatLabel omits zero" {
    try std.testing.expectEqual(NumstatDelta{}, sumNumstat(""));
    try std.testing.expectEqual(NumstatDelta{}, sumNumstat("   \n\n  \t"));
    try std.testing.expectEqual(NumstatDelta{ .additions = 3, .deletions = 1 }, sumNumstat("3\t1\tsrc/a.zig\n"));
    try std.testing.expectEqual(NumstatDelta{ .additions = 3, .deletions = 1 }, sumNumstat("3\t1\tsrc/a.zig\r\n"));
    try std.testing.expectEqual(NumstatDelta{ .additions = 12, .deletions = 0 }, sumNumstat("12\t0\tbar.txt"));
    try std.testing.expectEqual(NumstatDelta{ .additions = 0, .deletions = 4 }, sumNumstat("0\t4\tdel.txt\n"));
    try std.testing.expectEqual(NumstatDelta{}, sumNumstat("-\t-\timage.png\n"));
    try std.testing.expectEqual(NumstatDelta{}, sumNumstat("-\t12\tbin.dat\n"));
    try std.testing.expectEqual(NumstatDelta{}, sumNumstat("8\t-\tother.bin\n"));
    try std.testing.expectEqual(
        NumstatDelta{ .additions = 15, .deletions = 1 },
        sumNumstat("3\t1\ta.zig\n\n-\t-\tpic.png\n12\t0\tb.zig\n"),
    );
    try std.testing.expectEqual(
        NumstatDelta{ .additions = 8, .deletions = 1 },
        sumNumstat("3\t1\ta.zig\n5\t0\tnew.txt\n-\t-\tpic.png\n"),
    );
    try std.testing.expectEqual(
        NumstatDelta{ .additions = 5, .deletions = 0 },
        sumNumstat("5\t0\tuntracked.txt\n"),
    );
    try std.testing.expect(parseNumstatLine("not-numstat") == null);
    try std.testing.expect(parseNumstatLine("3\t1") == null);
    const max_u64 = std.math.maxInt(u64);
    try std.testing.expectEqual(
        NumstatDelta{ .additions = max_u64, .deletions = max_u64 },
        sumNumstat("1\t1\ta\n18446744073709551615\t18446744073709551615\tb\n"),
    );
    var buf: [max_git_numstat_label]u8 = undefined;
    try std.testing.expectEqualStrings("", numstatLabel(0, 0, &buf));
    try std.testing.expectEqualStrings("+3 −1", numstatLabel(3, 1, &buf));
    try std.testing.expectEqualStrings("+12 −0", numstatLabel(12, 0, &buf));
    try std.testing.expectEqualStrings("+0 −4", numstatLabel(0, 4, &buf));
    try std.testing.expectEqualStrings("+5 −0", numstatLabel(5, 0, &buf));
    try std.testing.expectEqualStrings("+18446744073709551615 −18446744073709551615", numstatLabel(max_u64, max_u64, &buf));
}
