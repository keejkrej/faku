//! Git / review / skills / probe spawn effect-key re-exports.
//!
//! One-shot git_branch / checkout / dirty / numstat / commit / remotes /
//! toplevel / common-dir keys, plus file_mention, review diff, skills
//! scan / rename, Files Preview issue-link, CLI `--help` / `--version`
//! probes, and LiteLLM rate-table keys. Owning modules keep the values;
//! this file only re-exports them.
//! Callers import this module directly (`git_keys.git_branch_key_first` /
//! `git_keys.litellm_rates_key`). Not re-exported from `main`. Behavior is
//! unchanged from the former `main` constants.

const std = @import("std");
const git_branch = @import("git_branch.zig");
const git_checkout = @import("git_checkout.zig");
const git_dirty = @import("git_dirty.zig");
const git_numstat = @import("git_numstat.zig");
const git_ahead_behind = @import("git_ahead_behind.zig");
const git_remotes = @import("git_remotes.zig");
const git_toplevel = @import("git_toplevel.zig");
const git_common_dir = @import("git_common_dir.zig");
const git_commit = @import("git_commit.zig");
const file_mention = @import("file_mention.zig");
const review_diff = @import("review_diff.zig");
const skills = @import("skills.zig");
const file_preview_issue_link = @import("file_preview_issue_link.zig");
const cli_probe = @import("cli_probe.zig");
const cli_version = @import("cli_version.zig");
const litellm_rates = @import("litellm_rates.zig");

/// One-shot `git branch --show-current` probe. Distinct from maximize /
/// pick-image / fx-ask / daemon / clipboard / probe keys, from
/// git_branch_list (250+), git_checkout (275+), and from
/// git_dirty (300+). Incremented per refresh from
/// `git_branch_key_first`.
pub const git_branch_key_first = git_branch.git_branch_key_first;
/// One-shot `refs/heads` + `refs/remotes` list. Distinct from
/// git_branch (200+), git_checkout (275+; also `--track`), git_dirty
/// (300+), git_numstat (350+), git_push (360+), git_ahead_behind
/// (380+), and file_mention (400+).
pub const git_branch_list_key_first = git_checkout.git_branch_list_key_first;
/// One-shot `git checkout <name>`. Distinct from git_branch (200+),
/// git_branch_list (250+), git_create (290+), git_dirty (300+),
/// git_numstat (350+), git_push (360+), git_ahead_behind (380+),
/// and file_mention (400+).
pub const git_checkout_key_first = git_checkout.git_checkout_key_first;
/// One-shot `git checkout -b <name>`. Distinct from list (250+),
/// checkout (275+), git_dirty (300+). Band is 290+.
pub const git_create_key_first = git_checkout.git_create_key_first;
/// One-shot `git branch -d <name>`. Distinct from create (290+),
/// git_dirty (300+), git_fetch (340+), git_numstat (350+), and
/// git_push (360+). Band is 320+.
pub const git_delete_key_first = git_checkout.git_delete_key_first;
/// One-shot `git fetch --prune`. Distinct from delete (320+) and
/// git_numstat (350+). Band is 340+.
pub const git_fetch_key_first = git_checkout.git_fetch_key_first;
/// One-shot `git push` (bare or `--set-upstream`) plus the probes
/// that choose the path. Distinct from fetch (340+), git_numstat
/// (350+), git_worktree_add (370+), git_ahead_behind (380+), and
/// file_mention (400+). Band is 360+.
pub const git_push_key_first = git_checkout.git_push_key_first;
/// One-shot `git worktree add -b`. Distinct from push (360+),
/// git_ahead_behind (380+), git_worktree_base (390+), and
/// file_mention (400+). Band is 370+.
pub const git_worktree_add_key_first = git_checkout.git_worktree_add_key_first;
/// One-shot `git rev-list --left-right --count @{upstream}...HEAD`.
/// Distinct from git_worktree_add (370+), git_worktree_base (390+),
/// and file_mention (400+). Band is 380+. Incremented per refresh
/// from `git_ahead_behind_key_first`.
pub const git_ahead_behind_key_first = git_ahead_behind.git_ahead_behind_key_first;
/// One-shot `git symbolic-ref --quiet --short refs/remotes/origin/HEAD`
/// for New worktree… base. Distinct from git_ahead_behind (380+)
/// and file_mention (400+). Band is 390+.
pub const git_worktree_base_key_first = git_checkout.git_worktree_base_key_first;
/// One-shot `git status --porcelain` dirty count. Distinct from
/// git_branch (200+), git_branch_list (250+), git_checkout (275+),
/// git_create (290+), git_delete (320+), git_fetch (340+),
/// git_numstat (350+), git_push (360+), git_ahead_behind (380+),
/// and file_mention (400+). Incremented per refresh from
/// `git_dirty_key_first`.
pub const git_dirty_key_first = git_dirty.git_dirty_key_first;
/// One-shot `git diff --numstat HEAD --` +/- plus untracked text-line
/// additions. Distinct from git_branch (200+), git_dirty (300+),
/// git_push (360+), git_ahead_behind (380+), and file_mention (400+).
/// Incremented per refresh from `git_numstat_key_first`.
pub const git_numstat_key_first = git_numstat.git_numstat_key_first;
/// One-shot file-mention probe (git ls-files, then a bounded walk
/// when git cannot list) for composer `@` mentions. Distinct from
/// git_branch (200+), git_dirty (300+), git_numstat (350+),
/// git_push (360+), git_worktree_add (370+), git_ahead_behind
/// (380+), and git_worktree_base (390+). Incremented per spawn
/// from `file_mention_key_first` (400).
pub const file_mention_key_first = file_mention.file_mention_key_first;
/// One-shot `git add -A -- .` then `git commit -m`. Distinct from
/// file_mention (400+); band is 450+ so it does not sit on 400–409.
/// Incremented per spawn from `git_commit_key_first`.
pub const git_commit_key_first = git_commit.git_commit_key_first;
/// One-shot CommitSnapshot numstat on the Commit… card (include-
/// unstaged reuses the project-row script; off is `--cached`).
/// Distinct from add/commit (450+) and project-row keys (350+).
/// Band is 460+. Incremented per probe from
/// `git_commit_numstat_key_first`.
pub const git_commit_numstat_key_first = git_commit.git_commit_numstat_key_first;
/// One-shot empty-message generate on the Commit… card (session
/// provider CLI, last-resort `fx ask`, or daemon GenerateCommitMessage).
/// Distinct from add/commit (450+) and CommitSnapshot numstat (460+).
/// Band is 470+. Incremented per spawn from
/// `git_commit_generate_key_first`.
pub const git_commit_generate_key_first = git_commit.git_commit_generate_key_first;
/// One-shot `git remote` for first-push remotes. Distinct from
/// generate (470+) and git_push remotes (360+). Band is 480+.
/// Incremented per refresh from `git_remotes_key_first`.
pub const git_remotes_key_first = git_remotes.git_remotes_key_first;
/// One-shot `git rev-parse --show-toplevel`. Distinct from remotes
/// (480+). Band is 490+. Incremented per refresh from
/// `git_toplevel_key_first`.
pub const git_toplevel_key_first = git_toplevel.git_toplevel_key_first;
/// One-shot `git rev-parse --git-common-dir`. Distinct from
/// toplevel (490+). Band is 500+. Incremented per refresh from
/// `git_common_dir_key_first`.
pub const git_common_dir_key_first = git_common_dir.git_common_dir_key_first;
/// One-shot Branch `git diff --numstat @{upstream}...HEAD` for
/// the Environment Compare Review card. Distinct from common-dir
/// (500+). Band is 510+. Incremented per open from
/// `review_diff_key_first`.
pub const review_diff_key_first = review_diff.review_diff_key_first;
/// One-shot Review `git diff [operand] -- <path>` hunk probe.
/// Distinct from file-list 510+. Band is 520+. Incremented
/// per file click from `review_diff_hunk_key_first`.
pub const review_diff_hunk_key_first = review_diff.review_diff_hunk_key_first;
/// One-shot Settings Skills `find` for `SKILL.md` /
/// `SKILL.md.disabled`. Distinct from review hunk (520+). Band is
/// 530+. Incremented per scan from `skills_key_first`.
pub const skills_key_first = skills.skills_key_first;
/// One-shot Settings Skills enable/disable `mv` rename
/// (`SKILL.md` ↔ `SKILL.md.disabled`) — the no-daemon fallback.
/// Distinct from the scan key (530+), Files Preview issue-link
/// (540+), and `setSkillsEnabled` / `trashSkills` (`next_daemon_key`).
/// Band is 580+. Incremented per toggle from `skills_rename_key_first`.
pub const skills_rename_key_first = skills.skills_rename_key_first;
/// One-shot Settings Skills Delete `rm -rf` / Remove-Item fallback
/// (permanent directory remove, not OS Trash). Distinct from rename
/// (580+) and daemon `trashSkills` (`next_daemon_key`). Band is 590+.
pub const skills_remove_key_first = skills.skills_remove_key_first;
/// One-shot Files Preview + transcript `git remote` / `git remote get-url`
/// for markdown `issue-link-base`. Distinct from skills scan (530+),
/// skills rename (580+), and skills remove (590+). Band is 540+. Incremented per spawn from
/// `file_preview_issue_link_key_first`.
pub const file_preview_issue_link_key_first = file_preview_issue_link.key_first;
/// One-shot Settings Providers non-fx `{binary} --help` probes.
/// Distinct from skills remove (590+). Band is 600+ `@intFromEnum(id)`
/// so claude=601 … opencode2=610, deepseek=611. fx stays on `fx_probe_key` (3).
pub const cli_probe_key_first = cli_probe.cli_probe_key_first;
/// One-shot Settings Providers `{binary} --version` probes (runtime
/// badge). Distinct from cli_probe 600–611. Band is 620+
/// `@intFromEnum(id)` so fx=620 … opencode2=630, deepseek=631.
pub const cli_version_key_first = cli_version.cli_version_key_first;
/// One-shot LiteLLM rate-table curl (`-o` into the Faku data dir).
/// Distinct from cli_probe (600+) and cli_version (620+). Fixed key
/// 650. Browser `page_title` curl is 660–699 (`browser_pane` /
/// `sidecar_keys`).
pub const litellm_rates_key = litellm_rates.litellm_rates_key;

test "git/review/skills/probe spawn keys match owning modules" {
    try std.testing.expectEqual(git_branch.git_branch_key_first, git_branch_key_first);
    try std.testing.expectEqual(git_checkout.git_branch_list_key_first, git_branch_list_key_first);
    try std.testing.expectEqual(git_checkout.git_checkout_key_first, git_checkout_key_first);
    try std.testing.expectEqual(git_checkout.git_create_key_first, git_create_key_first);
    try std.testing.expectEqual(git_checkout.git_delete_key_first, git_delete_key_first);
    try std.testing.expectEqual(git_checkout.git_fetch_key_first, git_fetch_key_first);
    try std.testing.expectEqual(git_checkout.git_push_key_first, git_push_key_first);
    try std.testing.expectEqual(git_checkout.git_worktree_add_key_first, git_worktree_add_key_first);
    try std.testing.expectEqual(git_ahead_behind.git_ahead_behind_key_first, git_ahead_behind_key_first);
    try std.testing.expectEqual(git_checkout.git_worktree_base_key_first, git_worktree_base_key_first);
    try std.testing.expectEqual(git_dirty.git_dirty_key_first, git_dirty_key_first);
    try std.testing.expectEqual(git_numstat.git_numstat_key_first, git_numstat_key_first);
    try std.testing.expectEqual(file_mention.file_mention_key_first, file_mention_key_first);
    try std.testing.expectEqual(git_commit.git_commit_key_first, git_commit_key_first);
    try std.testing.expectEqual(git_commit.git_commit_numstat_key_first, git_commit_numstat_key_first);
    try std.testing.expectEqual(git_commit.git_commit_generate_key_first, git_commit_generate_key_first);
    try std.testing.expectEqual(git_remotes.git_remotes_key_first, git_remotes_key_first);
    try std.testing.expectEqual(git_toplevel.git_toplevel_key_first, git_toplevel_key_first);
    try std.testing.expectEqual(git_common_dir.git_common_dir_key_first, git_common_dir_key_first);
    try std.testing.expectEqual(review_diff.review_diff_key_first, review_diff_key_first);
    try std.testing.expectEqual(review_diff.review_diff_hunk_key_first, review_diff_hunk_key_first);
    try std.testing.expectEqual(skills.skills_key_first, skills_key_first);
    try std.testing.expectEqual(skills.skills_rename_key_first, skills_rename_key_first);
    try std.testing.expectEqual(skills.skills_remove_key_first, skills_remove_key_first);
    try std.testing.expectEqual(file_preview_issue_link.key_first, file_preview_issue_link_key_first);
    try std.testing.expectEqual(cli_probe.cli_probe_key_first, cli_probe_key_first);
    try std.testing.expectEqual(cli_version.cli_version_key_first, cli_version_key_first);
    try std.testing.expectEqual(litellm_rates.litellm_rates_key, litellm_rates_key);

    try std.testing.expectEqual(@as(u64, 200), git_branch_key_first);
    try std.testing.expectEqual(@as(u64, 250), git_branch_list_key_first);
    try std.testing.expectEqual(@as(u64, 275), git_checkout_key_first);
    try std.testing.expectEqual(@as(u64, 290), git_create_key_first);
    try std.testing.expectEqual(@as(u64, 320), git_delete_key_first);
    try std.testing.expectEqual(@as(u64, 340), git_fetch_key_first);
    try std.testing.expectEqual(@as(u64, 360), git_push_key_first);
    try std.testing.expectEqual(@as(u64, 370), git_worktree_add_key_first);
    try std.testing.expectEqual(@as(u64, 380), git_ahead_behind_key_first);
    try std.testing.expectEqual(@as(u64, 390), git_worktree_base_key_first);
    try std.testing.expectEqual(@as(u64, 300), git_dirty_key_first);
    try std.testing.expectEqual(@as(u64, 350), git_numstat_key_first);
    try std.testing.expectEqual(@as(u64, 400), file_mention_key_first);
    try std.testing.expectEqual(@as(u64, 450), git_commit_key_first);
    try std.testing.expectEqual(@as(u64, 460), git_commit_numstat_key_first);
    try std.testing.expectEqual(@as(u64, 470), git_commit_generate_key_first);
    try std.testing.expectEqual(@as(u64, 480), git_remotes_key_first);
    try std.testing.expectEqual(@as(u64, 490), git_toplevel_key_first);
    try std.testing.expectEqual(@as(u64, 500), git_common_dir_key_first);
    try std.testing.expectEqual(@as(u64, 510), review_diff_key_first);
    try std.testing.expectEqual(@as(u64, 520), review_diff_hunk_key_first);
    try std.testing.expectEqual(@as(u64, 530), skills_key_first);
    try std.testing.expectEqual(@as(u64, 540), file_preview_issue_link_key_first);
    try std.testing.expectEqual(@as(u64, 580), skills_rename_key_first);
    try std.testing.expectEqual(@as(u64, 590), skills_remove_key_first);
    try std.testing.expectEqual(@as(u64, 600), cli_probe_key_first);
    try std.testing.expectEqual(@as(u64, 620), cli_version_key_first);
    try std.testing.expectEqual(@as(u64, 650), litellm_rates_key);
}
