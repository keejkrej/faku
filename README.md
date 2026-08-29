# Faku

Faku = fx + Waku.

Native SDK Zig desktop for coding agents. First-party Vercel fx. Waku-protocol
compatible. See NOTICE and LICENSE.

A Native SDK Zig desktop for local coding agents. Egoist asked for a Zig GPUI
slopfork so Waku compiles faster and uses less disk:
https://x.com/localhost_5173/status/2090464458695192842

This app replaces the GPUI window with Vercel Native SDK markup plus a Zig
Model / Msg / update loop. waku-daemon can stay the brain. Faku is the window,
and it is fx-first. Desktop chrome matches the stopped Waku-parity cut
(chromeless 48px header, measured sidebar, composer send circle).
Header, sidebar, and Ctrl-Tab switcher titles stay on one line with
Native ellipsis; the full name remains the accessible list-item
label. That is in-window chrome, not the OS window title. Ctrl-Tab
session switcher helpers live in `src/switcher.zig`. Sidebar
row builders live in `src/sidebar_rows.zig`. The
header X closes the window because chrome is off; the header
Minimize control and Cmd/Ctrl-M call Native `fx.minimizeWindow`; the
header Maximize control and Cmd/Ctrl-Shift-M one-shot an OS zoom
sidecar because Native still has no `fx.maximizeWindow`; sidebar
Search and Cmd/Ctrl-K open a local command palette (actions + session
jump, no daemon; Commands can copy the selected session's local
numeric id and fx/ACP session id); the sidebar collapse
control works and is restored; the sidebar chevrons walk session
selection history; clicking a session focuses the composer; New folder creates a local catalog folder; clicking
a folder (or the move control) assigns the selected session; folder
titles are editable; collapsed folder headers show a right chevron (expand) and expanded ones a down chevron (collapse); Collapse all folders collapses every sidebar folder (restored via `collapsed_folder_ids`); the selected session title is editable; deleting a folder unassigns its sessions;
sidebar trash removes a session (and closeSession if a daemon is set);
sidebar session rows have a Native context menu (Rename / Remove);
a working sidebar session shows a Native spinner beside the title;
ungrouped and folder session rows can show a muted relative
last-activity time from `updated_at` (just now / Nm / Nh /
Yesterday / Nd / date; omitted when `updated_at` is missing/0;
static from last `wallMs`, not a live ticker);
sidebar folder rows have a Native context menu (Rename / Delete);
the composer project row sets the selected session cwd and, when that
path exists, shows a muted one-shot `git branch --show-current` label
that can open a checkout picker (`for-each-ref` `%(refname)%00%(worktreepath)` +
`git checkout`, or `git checkout --track` for a remote-tracking ref with no
local counterpart; local heads checked out in another worktree stay listed
and are refused for checkout/delete)
or create-and-checkout a new local branch from HEAD (`git checkout -b`)
or create a new worktree (`git worktree add -b faku/<slug>`
under `~/.faku/worktrees/<16-hex of source project_path>/<slug>`
from a probed default base, with `slug-2` … `slug-8` on dest/branch
collision, then retarget the session `project_path` to the dest
actually used)
or commit dirty work via Commit… (porcelain XY inspect +
include-unstaged toggle, default on; first-cut CommitSnapshot
`+N −M` of working tree vs HEAD plus untracked text-line
additions when the toggle is on, or index vs HEAD when it is
off; empty / whitespace on Commit
or Commit and Push one-shots `fx ask --no-save --auto --json`
when fx is available, fills a normalized subject, then
auto-proceeds; `git add -A -- .` then
`git diff --cached --quiet --` then `git commit -m`
when the toggle is on, or the same preflight then
`git commit -m` only when it is off (exit 1 proceeds;
exit 0 is `Nothing staged to commit.`); message trimmed
to one line, max 200
chars; offered when the dirty probe is not in flight and
there is staged work, or unstaged work while include-unstaged
is on; Commit and Push on that card runs the same commit
path then the existing Push… probe/spawn, even when the stale
ahead/behind gate would hide Push…, and is offered only when
first-push remotes are OK — known upstream, or a `git remote`
probe found at least one remote; Push on that card is a
first-cut Waku `CommitAction::Push` that reuses Push… and is
offered only when `can_push`)
or safe-delete a non-current, unoccupied local head (`git branch -d`)
or fetch remotes via `git fetch --prune`
or push the current branch via `git push` when it has an upstream,
or `git push --set-upstream <remote> <branch>` when it does not
(Push… only when Waku `can_push` would be true: ahead of
`@{upstream}`, or that name does not resolve and at least one
remote exists)
plus a one-shot `git status --porcelain` dirty file count, a
one-shot `git diff --numstat HEAD` +/- that also adds untracked
text-line counts on the + side, and muted ahead/behind vs
`@{upstream}` (`↑A ↓B`) when that name exists (not Waku's daemon
InspectBranches live watch / `{project_id}` UUID nest /
git-common-dir nest identity / Environment
Summary / force delete / prune-alone / base-ref picker;
Native still has no git
effect);
typing `@` in the composer (last whitespace token; caret assumed at
the end — Native has no caret API) opens a small card of files and
derived parent directories (trailing slash) from a one-shot
`git ls-files --cached --others --exclude-standard` of that same
workspace, or a bounded directory walk when git cannot list, when
the cache has matches (`user@host` does not trigger; slash prefix
stays authoritative; visible rows are scored over that bounded
cache, not Waku's 50k-file index or caret-aware trigger);
the usage control stays empty unless ACP reports `usage_update`; user and
assistant turns render Native markdown; the transcript stays pinned
to the latest turn via Native `scroll` `value` / `on-scroll`
(`canvas.ScrollState` extents; overshoot `value` clamps to the end)
while the user is at the bottom, and Jump to latest sets that same
`value` after they scroll away; Copy on a turn writes that turn's
visible text through Native `fx.writeClipboard` (empty text is a
no-op); Copy session joins that session's visible user / assistant /
tool / thought text the same way (empty session is a no-op); Fork
clones the selected local transcript into a new `sessions.json` row
(empty `fx_session_id` / `runtime_id`) and is not a provider session
fork; Rewind undoes the last turn's files and those chat turns, using
the Send-time HEAD, not a provider session fork; a successful stream
turn fires a desktop notification through Native `fx.showNotification`
(session title or Faku; truncated last assistant text or Reply ready).
Native has no window-focus observation, so this is not Waku's
unfocused-only gate — it always notifies on success. Headless paths are
unchanged. Clipboard and turn-complete notify helpers live in
`src/copy.zig`. Session fork / rewind helpers live in
`src/fork.zig`. Prompt-start / fx ask / fx acp / daemon spawn
helpers live in `src/spawn.zig`. Send / stream lifecycle /
daemon steer-cancel helpers live in `src/stream.zig`. Sidecar
stdout / ACP / daemon line handlers and fx-exit routing live in
`src/lines.zig`. Maximize spawn/exit helpers live in
`src/maximize_window.zig`. Composer Pick folder helpers live in
`src/pick_folder.zig`. Composer Reveal folder helpers live in
`src/reveal_folder.zig`. Composer Open in Terminal helpers live in
`src/open_terminal.zig`. Composer Open in Editor helpers live in
`src/open_editor.zig`. Composer git-branch probe helpers live in
`src/git_branch.zig`. Composer branch list / checkout helpers live in
`src/git_checkout.zig` (list, local checkout, remote-tracking `--track`,
create-and-checkout, safe delete, fetch, push, and New worktree…
slug-prefill plus default-base probe, collision suffixes, and
per-project path-hash nest). Composer include-unstaged Commit… / Commit and Push /
first-cut CommitSnapshot numstat / empty-message `fx ask`
generate helpers live in
`src/git_commit.zig`. Composer git-dirty probe helpers (count
plus porcelain XY `has_staged` / `has_unstaged`) live in
`src/git_dirty.zig`. Composer git-numstat probe helpers live in
`src/git_numstat.zig`. Composer git ahead/behind probe helpers live in
`src/git_ahead_behind.zig`. Composer `@` file-mention probe helpers live in
`src/file_mention.zig`. Boot fx-probe spawn/exit lives in
`src/fx_probe.zig`. Folder/chip persist helpers live in
`src/persist.zig`. Session / folder / title-edit update helpers live
in `src/session_actions.zig`. Settings / Esc-stop / composer-picker
update helpers live in `src/settings_actions.zig`. Session type lives
in `src/session.zig`. Model / Msg / Turn / Folder live in
`src/model.zig`. Util helpers / bindDaemonEnv live in
`src/util.zig`.

## Why fx

Waku does not ship Vercel fx (https://fx.sh, https://github.com/vercel-labs/fx).
Faku does, as the default first-class provider.

fx is a minimal Zig coding-agent harness (about 7.8 MiB, Apache-2.0,
model-agnostic via AI_GATEWAY_API_KEY / VERCEL_OIDC_TOKEN / FX_MODEL).
Install lands at ~/.local/bin/fx.

Surfaces: fx interactive, fx ask (headless), fx acp (Agent Client Protocol
over stdio), fx resume.

## Live path: one-shot `fx acp`

When the fx CLI is installed, Send on an fx session spawns a one-shot
`faku acp-proxy -- {fx_path} acp` (same probe as today: `~/.local/bin/fx`,
then `fx` on PATH). Native `fx.spawn` writes **one stdin buffer and then
closes stdin**. The sidecar owns the child stdin. The buffer is NDJSON
JSON-RPC 2.0 (ACP protocol version 1):

    initialize
    session/new          # first turn
    session/resume       # later turns, stored fx_session_id
    session/set_mode     # access_mode → fx ask|code
    session/set_config_option  # model, omitted when empty
    session/prompt

Cwd on `session/new` / `session/resume` is the session `project_path`
when that directory exists, else `"."`. Official methods only
(https://fx.sh/docs/using-fx/acp): this cut does not call
`session/load`, `session/close`, or `session/list`. The sidecar
auto-answers official `session/request_permission` from that run's
access mode (env / `session/set_mode`), not a prompt dialog.
`session/cancel` cannot be written from the window after spawn; Stop /
Esc uses `fx.cancel`.
Model and access now also go out on the ACP stdin batch
(`session/set_config_option` / `session/set_mode`) in addition to the
`FX_MODEL` / `FX_PERMISSION_MODE` env prefix.

`session/new` returns `{ sessionId }`. fx ACP sessions are the same
saved sessions as interactive fx, so that id is stored as
`fx_session_id` (the field `fx ask --json` already used). Follow-ups
send `session/resume` + `session/prompt` with that id. First-turn
`session/prompt` is in the same stdin buffer as `session/new`, so its
`sessionId` is empty until the result arrives on stdout.

`session/update` `agent_message_chunk` text appends to the assistant
turn. `agent_thought_chunk` text shows as a muted reasoning turn.
`tool_call` and `tool_call_update` show as tool turns
(`title` · `kind` · `status`, plus text/diff `content` replaced on
update; image, audio, terminal, and unknown blocks are skipped).
The access chip follows ACP
`current_mode_update` (`ask` → ask / Ask, `code` → fullAccess / Full access).
The model chip follows ACP `config_option_update` (`configOptions` id
`model` `currentValue`; empty stays `FX_MODEL`). When that option
includes `options[]`, Faku stores the catalog for the composer picker
(empty array clears it). A `session/set_config_option` result (`id` 5)
updates the same catalog. There is no invented model list on first
launch — without a stored catalog the picker shows `FX_MODEL` (empty)
and last-used when one exists.
ACP `available_commands_update` stores command names (and descriptions)
on the session. Composer Commands inserts `/name ` into the draft; typing
`/` in the composer opens that same stored list. It does not run the command.
Typing `@` (last whitespace-separated token; `user@host` does not
trigger; mid-prompt `@foo` with more text after it is not a mention
under the caret-at-end assumption) opens a mention list from the
runtime file-mention cache when that cache has matches. Git
`ls-files --cached --others --exclude-standard` is first; a bounded
`find` walk (depth 8, skip hidden / `node_modules` / build output)
fills the same cache only when that spawn fails. Git success with
zero files stays empty. Derived parent directories of those cached
files join the ranked list as `path/` (trailing slash).
A non-empty `@query` ranks visible rows by match quality (basename
prefix, then basename contains / path-segment prefix, then full-path
contains) rather than first-N contains in cache order. Empty `@`
matches every file and derived dir; ties prefer shallower paths,
then path, then id, so the card opens on the project's top level.
Cap remains 12. Still not Waku's 50k-file index or caret-aware
trigger, and still not persisted. Slash prefix stays authoritative;
the two lists never show together.
Clicking a row replaces only that last `@query` token with `@relpath`
plus a trailing space (`@src/` for a directory). File paths stay
relative as git or the walk printed them (`find`'s leading `./` is
stripped). Not a provider/ACP method, not Open-in, and not copy path.
Enter on the composer confirms the first visible `@` mention or
slash-command row instead of sending; Esc dismisses that card for the
current draft (typing again reopens). Not Waku's up/down/tab key
context — Native textarea eats those keys. Click still inserts. The
Send button still sends.
ACP `session_info_update` applies a non-empty `title` to the session
(header / sidebar); official `cwd` is not on this notification.
The `session/prompt` result `stopReason`
settles the turn and drains the success-only queue (`cancelled` /
`refusal` / JSON-RPC error do not drain). This is **not** a long-lived
ACP loop: each Send starts a new `acp-proxy` → `fx acp` process and
Native closes stdin.

ACP does not accept image or audio blocks. When draft `image_path` is
set and the file exists, Send keeps today's `fx ask --image` path
(`--json`, `--resume` after a minted id). `WAKU_DAEMON_ADDRESS` still
selects the daemon sidecar. Missing fx still uses the demo timer.

There is no `--model` argv on the ACP spawn. `fx acp --model` exists
on the server process; this cut still prefixes `FX_MODEL` /
`FX_PERMISSION_MODE` via `/usr/bin/env` (Native `SpawnOptions` has
no `env`) and also writes those values on the ACP stdin batch.
`--no-save` and `--auto`/`--yolo` flags are not used. fx ACP modes
are `ask` and `code` (not Waku `fullAccess`). Waku `ask` → `ask`;
`autoAcceptEdits` / `auto` / `fullAccess` / `yolo` → `code`. Empty
`model` omits `session/set_config_option`.

Model and access ride env, not flags. Official fx values
([configuration](https://fx.sh/docs/configure-fx/configuration)):
`FX_MODEL` and `FX_PERMISSION_MODE` (`ask` | `auto` | `yolo`). Native
`SpawnOptions` has no `env` field, so Faku prefixes
`/usr/bin/env KEY=val` on the child only and does not export on the
Faku process. Empty `model` omits `FX_MODEL` (fx's own default).
Waku `runtime_mode` is stored as `access_mode`: `ask` → `ask`,
`autoAcceptEdits`/`auto` → `auto`, `fullAccess` → `yolo`. New sessions
default to Waku `fullAccess` (`FX_PERMISSION_MODE=yolo`) and inherit
`last_model` / `last_access_mode` when those were persisted.

If that session has a non-empty `project_path` that exists on disk, ACP
puts that path in `session/new` / `session/resume` `cwd`; otherwise
`"."`. Native 0.9.3 `SpawnOptions` has no `cwd` field, so the `fx ask`
image / fallback path still starts
`/bin/sh -c 'cd -- "$1" && shift && exec "$@"'` with the workspace as
`$1`. Empty or missing paths leave the host process cwd for `fx ask`.
`PWD` is not used. Daemon `start` uses stored `project_path` as
`StartOptions.cwd`, or `"."` when that field is empty.

New sessions inherit `last_project_path` from `sessions.json` when one
was persisted. The composer project row under the prompt sets that
session `project_path` (empty is Local / host cwd). Pick folder
one-shots an OS directory dialog (macOS `osascript` `choose folder`
POSIX path; Linux `zenity --file-selection --directory`, else
`kdialog --getexistingdirectory`) because Native still has no
`fx.pickFile` — this is not Waku's daemon project picker. Typed path
remains. Reveal folder opens the selected session workspace in the OS
file manager via an `open` / `xdg-open` sidecar (not Native
`fx.revealPath`, which this SDK does not expose on Effects, and not
Waku's Open-in app picker). Open in Terminal opens that same workspace
in the host terminal via `open -a Terminal` / `x-terminal-emulator
--working-directory=` (else `gnome-terminal`) — an OS sidecar, not
Waku's embedded right-panel terminal and not a full Open-in app picker.
Open in Editor is the third honest cut of Waku 0.1.11 "Open in.." —
it opens that same workspace in Cursor (`cursor`) then VS Code (`code`)
via an OS sidecar (`open -a Cursor` / `open -a "Visual Studio Code"`
on macOS when those bins are missing; Linux stays `cursor` then `code`).
This is not Waku's full Open-in app picker, not a persisted
`open_in_app`, and not an embedded editor panel.
Copy path writes that same absolute workspace path through Native
`fx.writeClipboard`, gated like Reveal (hidden for Local / empty /
missing / relative / file paths), and is not Waku's Open-in picker.
When that path exists, the same row shows
a muted current-branch select from a
one-shot `fx.spawn` of `git branch --show-current` (chdir via the
same `/bin/sh -c 'cd -- "$1" && shift && exec "$@"'` workaround
`fx ask` uses, because Native `SpawnOptions` has no `cwd`). Detached
HEAD prints empty; a follow-up `git rev-parse --short HEAD` may
show a conservative short hex as the select label. Non-repos omit
the control. The same refresh also one-shots
`git for-each-ref --format=%(refname)%00%(worktreepath) refs/heads refs/remotes`
(64 local heads plus 32 remote-tracking names, lexicographic) so
that select can check out another local head via one-shot
`git checkout <name>` or a remote-tracking ref with no local
counterpart via `git checkout --track <name>` (`--track` and the
name each their own argv slot). A local head with a non-empty
`%(worktreepath)` that is not this session's `project_path` / list
probe cwd (or a parent of that path) stays listed with a short
`(worktree)` marker; picking it refuses checkout and sets
`Already checked out in another worktree.` Symbolic `*/HEAD` is
omitted; `origin/feat` is omitted when local `feat` exists.
Remotes are never occupied. New branch… on that picker opens a
runtime-only create card and one-shots `git checkout -b <name>`
from current HEAD the same way.
New worktree… opens a runtime-only create card prefilled from a
prompt slug of the selected session title (lowercase, split on
non-ascii-alnum, six words, 48 bytes; empty → `new-worktree`; the
user can still edit). Confirm probes
`git symbolic-ref --quiet --short refs/remotes/origin/HEAD` (chdir
script; own argv slots; key band 390+) then one-shots
`git worktree add -b faku/<name> <path>` with that default base as
its own trailing argv slot when one resolves (`-b`, the branch,
the path, and the optional base each their own slot; `mkdir -p` of
`~/.faku/worktrees/<nest>` via a fixed script). `origin/<name>` prefers
`<name>` when that is a plausible branch; otherwise the whole
`origin/<name>` string when it is a safe argv. Failed / empty /
exit 1 falls back to the cached composer branch label (not a
detached short SHA) and otherwise omits the base (today's HEAD).
The dest path is
`~/.faku/worktrees/<16-hex of source project_path>/<name>`
(absolute from `$HOME`; nest is FNV-1a 64 of the ready
`git rev-parse --show-toplevel` root when that probe finished,
else the probe cwd used for `git worktree add`, not a daemon
UUID / `{project_id}`). Unsafe
/ empty names are refused.
A dest directory that exists or a listed local `faku/<name>` walks
Waku candidates (`slug`, `slug-2`, … `slug-8`; cap 8 because
Native is one-shot, not Waku's 100 + session-id hex). A failed
`worktree add` retries the next free candidate the same way.
Exhausted candidates set `Could not create worktree.` and leave
`project_path` alone. On success the selected session's
`project_path` is set to the dest actually used and persisted;
probes refresh against that path. This is not Waku's `waku/`
prefix, `~/.waku/worktrees/{project_id}` UUID nest, daemon
`WorkspaceOperation::NewWorktree`, defer-until-Send,
git-common-dir identity, or a
base-ref picker UI.
Delete branch… opens a runtime-only delete card of non-current,
unoccupied listed local heads and one-shots `git branch -d <name>`
(safe delete only; never `-D` / force; never `origin/…`; occupied
locals are omitted because `-d` of a worktree checkout fails).
Fetch… on that picker one-shots `git fetch --prune` (`--prune` its
own argv slot). Commit… opens a runtime-only message card with an
Include unstaged ghost toggle (default on; not persisted) and
one-shots `git add -A -- .` then `git diff --cached --quiet --`
then `git commit -m <message>` when that toggle is on, or the
same cached-quiet preflight then `git commit -m` only when it
is off (exit 1 means staged changes and proceeds; exit 0 is
`Nothing staged to commit.` and does not run commit; any other
exit fails). (`-A`, `--`, `.`, `--cached`, `--quiet`, `-m`,
and the message each their own argv slot; message trimmed to
one line, max 200 chars). Opening the card
(and toggling Include unstaged) one-shots CommitSnapshot
numstat: the project-row `git_numstat` script (`git diff
--numstat HEAD --` plus untracked text-line additions) when the
toggle is on, or `git diff --cached --numstat --` when it is
off (cached flags each their own argv slot; include-unstaged
reuses the shared script on a distinct 460+ key band). A muted
`+N −M` shows on the card when either count is non-zero; zero /
failed / empty / in-flight omits the label (no invented
"clean"). Deletions stay tracked-only. Empty / whitespace on Commit /
Commit and Push one-shots documented `fx ask --no-save --auto
--json` when `fx_available` and `fxPath` are set (prompt is its
own argv slot; include-unstaged on vs off changes the prompt;
fx inspects the repo itself), fills the normalized subject, then
auto-proceeds into add/preflight/commit. A muted `Generating…` shows while
that spawn is live. If fx is unavailable or the path is empty,
empty confirm sets `Enter a commit message.` and does not spawn.
Generate fail / empty output keeps the card open with
`Could not generate a commit message.` Offered only
when the dirty probe is not in flight and porcelain XY has staged
changes, or unstaged changes while include-unstaged is on (Waku
`can_commit`). Commit and Push on that card uses the same commit
path, then the existing Push… probe/spawn without re-checking
`can_push`. Offered only when `can_commit` and first-push remotes
are OK: known upstream, or a remotes probe ready with at least one
remote (hide while that probe is still needed or in-flight on the
no-upstream path). Push on that card is a first-cut Waku
`CommitAction::Push`: no commit, no message, no generate; offered
only when `can_push` (same binding as composer Push…); on start it
closes the card then reuses Push… (`startPush`, gated). This is
not Waku's in-dialog pending spinner. Commit / Commit and
Push now run the `git diff --cached --quiet` preflight; Push
on that card does not. Push… probes `@{upstream}` and one-shots `git push`
when that name exists (`push` its own argv slot). When there is no
upstream it one-shots `git push --set-upstream <remote> <branch>`
(`--set-upstream`, remote, and branch each their own argv slot;
remote prefers `origin` from `git remote`, else the first name).
Detached HEAD or no remotes set `Could not push.` and do not spawn
a push. Not force, not daemon `WorkspaceOperation::Push`, not
`InspectCommit`. Push… is offered only when Waku
`can_push` would be true: the ahead/behind probe resolved
`@{upstream}` and `git_ahead_behind_ahead > 0`, or that probe
failed / `@{upstream}` does not exist and a one-shot `git remote`
found at least one remote (prefer `origin`, else the first name).
Hidden while those probes are in flight (no flash), when remotes
are empty or failed on the no-upstream path, and when it resolved
an upstream with ahead 0 (synced or behind-only). The current
branch is never
offered. Selecting the current local branch is a no-op; picking a
remote-tracking name is not. A failed checkout, create, delete,
fetch, push, worktree-add, or commit sets a short composer status and leaves
the previous label until refresh.
The same refresh also one-shots `git status --porcelain` and, when that
stdout has non-empty lines, a muted `N change` / `N changes` label
next to the branch (one line per path; blank lines ignored). The
same refresh also one-shots `git diff --numstat HEAD --` plus
untracked text-line additions (`git ls-files --others
--exclude-standard`; `grep -Iq` skips binaries; files over 1 MiB
are skipped) and, when the combined additions or tracked deletions
are non-zero, a muted `+N −M` label next to the dirty count
(tracked binary `-` rows skipped; blank lines ignored; deletions
stay tracked-only). The same refresh also one-shots
`git rev-list --left-right --count @{upstream}...HEAD`
(`@{upstream}...HEAD` its own argv slot, same chdir workaround)
and, when either count is non-zero, a muted `↑A ↓B` label next to
dirty / +/- (omit a side when that count is 0; left = behind
upstream, right = ahead of upstream). No upstream, both-zero,
failed, rejected, Local, empty/missing path, or Windows omits that
label — this cut does not invent "synced" or "0 ahead". The same
refresh also one-shots `git remote` (`remote` its own argv slot;
prefer `origin`, else the first name) so first-push remotes can
gate Push… and Commit and Push. The same refresh also one-shots
`git rev-parse --show-toplevel` (`--show-toplevel` its own argv
slot) so occupancy and New worktree… nest can canonicalize the
session `project_path`; failed / empty / in-flight keep today's
`project_path` fallback. Zero,
failed, or skipped dirty / +/- probes omit those labels — this cut
does not invent "clean". This is not Waku's daemon
`InspectBranches` live watch, not Waku `{project_id}` UUID
nesting / `waku/` prefix, not defer-until-Send
workspace mode, not a worktree base-ref picker UI, not
git-common-dir identity, not Waku's
Environment Summary, not force delete (`git branch -D`), not
force push, not prune-alone (`git prune` without fetch), and not
Review. Leftovers: git-common-dir worktree nest identity /
Waku's in-dialog Pushing spinner (this cut closes the card then
starts Push…) / force / amend / daemon `WorkspaceOperation`.
Native still has no git effect. The branch, dirty count,
+/-, ahead/behind, remotes-ready bit, and show-toplevel path
are runtime-only (like the
busy spinner) and
are not stored on `sessions.json`. Occupancy uses a ready
`git rev-parse --show-toplevel` root when that probe finished
(`worktreepath` equal to that toplevel), else the session
`project_path` / probe cwd heuristic. New worktree… materializes
one-shot under
`~/.faku/worktrees/<16-hex of source toplevel or project_path>/<name>`
(or `.../<name>-2` … `-8` on collision) and retargets that
session path. This is not daemon
`WorkspaceOperation::NewWorktree`.
The same refresh also one-shots
`git ls-files --cached --others --exclude-standard` (same chdir
workaround) and keeps a bounded runtime list of relative paths for
composer `@` mentions. When that git spawn cannot run or exits
non-zero, a bounded `find` walk (max depth 8; prune names starting
with `.` and `node_modules` / `target` / `dist` / `build` / `out` /
`vendor` / `__pycache__`) fills the same files-only cache. Git
success with zero files is an empty repo and does not walk.
The cache is not stored on `sessions.json`.
The visible mention card scores those files plus unique parent
directories derived at row time (`composer.fileMentionScore`);
it is still not Waku's 50k-file index, caret-aware trigger, a
daemon catalog, or a live watch. Windows stays empty this cut.

A stdout ACP `session/new` result with `sessionId` updates the stored
id and is not appended to the assistant turn. `fx ask --json` lines
with `session_id` still do the same on the image / fallback path.
Exit settles the turn when the process ends without a prompt result.
Stop / Esc cancels the spawn and the demo timer; partial assistant
text stays.

Probe (boot `init_fx`, or first Send): `~/.local/bin/fx --help`, then
`fx --help` on PATH. Success stores `fx_available` and `fx_path`. Missing
or rejected binary keeps the demo timer (90ms ticks, canned reply) so
`native test --yes` stays green without a real fx install.

Non-fx providers (the claude demo session) still use the demo timer.
Reply path is still `fx` / `demo` / `daemon` on the model; the chrome no longer
shows a status-bar.

New sessions still default to fx.

## ACP (one-shot, not a live loop)

`fx acp` is spawned one-shot per Send through `faku acp-proxy` (same
family as cursor-agent / grok). `src/acp.zig` has newline-delimited
JSON-RPC 2.0 builders/parsers for `initialize`, `session/new`,
`session/resume`, `session/set_mode`, `session/set_config_option`,
`session/prompt`, `session/cancel`, `session/request_permission`, plus
a `session/update` / `stopReason` scanner.

This is **not** a long-lived ACP connection. Native `fx.spawn` accepts
stdin only at spawn time (one buffer, then stdin closes). The sidecar
keeps fx stdin open and auto-answers `session/request_permission` from
the access mode already sent on that run — not a prompt dialog.
Mid-turn `session/cancel` still cannot be written from the window.

## Scope

Ready: desktop shell, demo sessions + timer fallback, one-shot `fx acp`
when the CLI is present (via `acp-proxy`, which auto-answers
`session/request_permission`), `fx ask --image` / `fx ask` fallback, local
session catalog + hydrate, waku-protocol v4 JSON builders + server-frame
parser, one-shot daemon sidecar, provider id "fx".

Later: a long-lived daemon socket in the update loop (not this cut),
a long-lived `fx acp` loop once a window-side stdin-write effect exists.

No listSessions / createSession. Catalog is loadTaskState (local JSON
today). New session is a client-built session saved after first content.

## Run

Install the Native CLI globally, then from this directory:

    native test --yes
    native dev --yes
    native check
    native build

## Local session store

Sessions persist on disk beside the app. This is **not** the Waku daemon
and does not open a WebSocket. Native has no daemon/WebSocket client; the
store is a local JSON document that follows Waku's catalog / hydrate /
merge-only save rules.

Path (Native `app_dirs` data directory, app name `faku`):

    Linux:  $XDG_DATA_HOME/faku/sessions.json  or  ~/.local/share/faku/sessions.json
    macOS:  ~/Library/Application Support/faku/sessions.json

Boot: if that file loads, the sidebar is session skeletons only (id, title,
provider, untitled/has_started, project_path, fx_session_id, runtime_id, model,
access_mode, interaction_mode, reasoning_effort, folder_id, context_used, context_size,
available_commands, thread_goal_objective, thread_goal_status, thread_goal_token_budget, thread_goal_tokens_used, thread_goal_time_used_seconds, updated_at) — no demo rows and no transcripts. The document also stores
`last_project_path`, `last_model`, `last_access_mode`,
`last_interaction_mode`, `last_reasoning_effort`, `last_daemon_address`, `sidebar_collapsed`,
`sidebar_width`, `folders`, and `collapsed_folder_ids` so a new session can inherit the last workspace and last
model/access/interaction, a later send can reuse the last sidecar address,
the sidebar collapse control is restored, and New folder groups persist.
Ungrouped sessions (`folder_id` 0 or omitted) group into Today / Yesterday /
This week / This month / This year / Older date buckets from each session `updated_at`
(unix ms). Missing or 0 is Today so existing catalogs stay in one bucket.
This week is after yesterday and still in the current UTC week (Monday
start). This month is the same UTC month, older than this week. This year
is the same UTC calendar year, older than this month. Boundaries
are UTC civil days from the loop clock (`Effects.wallMs`); Zig std has no
tz database.
Ungrouped and folder session rows can show a muted one-line relative
last-activity label from that same `updated_at` vs `Effects.wallMs`
(just now / Nm / Nh / Yesterday / Nd / UTC `YYYY-MM-DD`). Missing or 0
omits the label so chrome does not invent a time. The label is static
from the last loop clock; there is no repeating live ticker.
This is not full Waku date grouping (no More, no Project/Updated
sort, no "working Xm" live labels). A session `folder_id`
lists it under that folder. Folder sessions get a 1px Native separator rail
and 15px inset (Waku group guides); ungrouped date-bucket rows stay flush.
Clicking a folder header (or its move control) assigns the
selected session; clicking Today unassigns it (`folder_id` 0). A second
click on a folder already holding the selected session edits its title.
Deleting a folder unassigns its sessions (`folder_id` 0); it does not
remove them.
The sidebar settings gear
opens a panel that edits those persisted defaults. Composer chips are the
quick session toggle: the access chip is a Native select listing
`ask` / `auto` / `fullAccess` (Ask, Auto, Full access), Build
cycles `build` / `plan`, and the model chip is a Native select whose
dropdown lists stored ACP model options, or else `FX_MODEL` (empty) and
last-used; Cmd/Ctrl-/ toggles that picker. Settings `FX_MODEL` stays a
free-text last-used field. Settings Ask / Auto / Full access stay
segmented buttons. Settings also edits last interaction (Build/Plan)
and last effort (fx's documented closed set); those remain `last_*`
defaults for new sessions, while composer chips stay the
selected-session toggle. The composer effort chip is a Native select listing
fx's documented effort values (auto / none / minimal / low / medium /
high / xhigh / max), persists on the session / `last_reasoning_effort`,
and rides daemon `StartOptions.reasoningEffort`. One-shot `fx acp` does
not get an invented env/flag.
Composer chip, access, effort, slash-prefix, file-mention, and attach helpers live
in `src/composer.zig`.
The composer project row edits the selected session cwd and persists
it as `last_project_path`. The under-composer usage control is Native
`progress` (0–1): it fills from an ACP `session/update` `usage_update`
`{used,size}` when that notification arrives; `fx ask --json` and
current `fx acp` do not emit usage, so the control stays empty. There is no daemon picker.
Selecting a session hydrates its turns and `queued_messages` from the same
file. Daemon `hydrateSession` runs only when that local transcript is empty.
Composer drafts are a sibling `drafts.json` (not mixed into the
session catalog) so a New Task can persist before the session row exists.
Keys match Waku: `newSession` or `newSession{project_path}` for untitled
drafts, `session{id}` after the session has started. Each record is
`{ text, image_path }` — one optional local path, not a Waku
`waku-attachment:` blob. Composer Attach pastes that same `image_path`
and shows a clearable chip. Pick image one-shots a platform sidecar that
opens a real OS file dialog (macOS `osascript` `choose file` of type
`public.image`; Linux `zenity --file-selection` with the image filter,
else `kdialog --getopenfilename`). Native still has no `fx.pickFile` /
file-open effect — `Runtime.showOpenDialog` is a host-bridge / WebView
API, not an fx effect. Spawn stdin is unused. If Linux has neither
zenity nor kdialog, composer status says so and typed-path + drop stay.
Windows has no picker in this cut (app.zon is macos/linux). Dropping an
image file onto the window sets that same composer attach path
(`fx ask --image`); it is a Native file drop, not an OS picker and not
an ACP image block.
When that file exists,
the chip row binds a Native `<image>` via `fx.loadImage` (ImageId, 0
until `.loaded`) and Send adds `fx ask --image PATH` before `--`; a
missing file keeps the chip only and omits the flag.
Attach preview, file drop, and OS picker helpers live in `src/attach.zig`.
Saves are cheap rewrites on each `draft_edit` and when leaving a
session. The `newSession` key (text and image) is discarded after the
first successful send so the next New Task does not resurrect that
prompt. There is no Native debounce
timer; last write wins.

Missing `sessions.json` keeps the two first-run demo sessions. When
`WAKU_DAEMON_ADDRESS` or persisted `last_daemon_address` is set, a one-shot
sidecar may send `loadTaskState` and replace those demos with returned
session skeletons — `loadTaskState` is only a first-run fill when the local
catalog is missing. A corrupt file
also keeps the demos and is not overwritten until a successful load
(`task_state_loaded`, same guard as waku-client). Save is merge-only;
`RemoveSession` is the only delete. Sidebar trash (Remove session)
is that delete; after a successful local remove, `closeSession` is a
best-effort one-shot when a daemon address is set.
New untitled sessions are not written
until they have real content.

Send while that session is streaming appends to its follow-up queue and
persists. Chrome lists each queued follow-up for the selected session
so one item can be dropped without clearing the rest; Dismiss all still
clears that session's queue. A successful finish (demo timer complete,
ACP `stopReason` other than cancelled/refusal, or `fx ask` exit 0)
drains the next queued prompt and shows `fx.showNotification`. Stop, Esc, a cancelled/refused ACP
prompt, and a non-zero `fx ask` exit do not drain and do not notify; partial assistant
text stays, then the session is saved.

One-shot `fx acp` mints and resumes an `fx_session_id` (same saved fx
session). `fx ask --json` still mints/resumes that field on the image
and fallback path. Send stores that workspace's HEAD sha on the session
(`rewind_refs` in `sessions.json`) when `project_path` is a git work
tree. Rewind undoes the last turn's files and those chat turns, using
the Send-time HEAD (`git reset --hard` that latest stored sha, then
pop it), not a provider session fork. `fx_session_id` stays.
Fork copies turns through the last turn into a new local session id
and leaves `fx_session_id` / `runtime_id` empty so the next Send
calls `session/new`; the source row is unchanged. That is a local
catalog clone, not a provider session fork. Fork on a turn cuts
there (`0..=index`) the same way.

## Demo vs daemon

Demo fallback: "port waku to zig" on fx, "fix auth listener" on claude.
New sessions default to fx. Without the fx binary, Send streams a local
canned reply (about 12 ticks / 90ms). Send while streaming with a draft
queues on that session (persisted). Successful finish drains the next
item; empty Send, Stop, or Esc cancels without draining.
The composer circle is Stop while streaming (cancels; does not queue).
Enter still queues a follow-up. The placeholder becomes
"Queue a follow-up...". Esc still closes overlays first, then cancels.

Keys: Cmd/Ctrl-N is sidebar New Task and focuses the composer, Cmd/Ctrl-K and sidebar Search open the local command palette (actions + session jump; no daemon; title / provider / project_path / model match is the palette Tasks section, not an inline sidebar filter; Commands Copy session id / Copy provider session id write the selected session's local decimal id or `fx_session_id` / ACP sessionId through Native `fx.writeClipboard` — empty provider id sets a short status and does not overwrite the clipboard), Cmd/Ctrl-/ toggles the composer model picker (stored ACP options, or `FX_MODEL` + last-used; plain `/` still types in the composer), Cmd/Ctrl-F filters the selected transcript to matching turns; the find bar shows k of N and Cmd/Ctrl-G / Cmd/Ctrl-Shift-G cycle the current matching turn (turn-level, no glyph highlight), Cmd/Ctrl-L focuses the composer, Cmd/Ctrl-M minimizes the chromeless window via `fx.minimizeWindow`, Cmd/Ctrl-Shift-M maximizes via an OS sidecar (macOS `osascript` System Events `zoomed` on the Faku-named / frontmost window; Linux `wmctrl -r :ACTIVE: -b toggle,maximized_vert,maximized_horz`, else `xdotool getactivewindow windowstate --add MAXIMIZED_VERT MAXIMIZED_HORZ`; missing Linux tools set a status string and do not crash; Windows is skipped because app.zon is macos/linux). Native still has no `fx.maximizeWindow` — this is the documented workaround, not an invented Native API. Cmd/Ctrl-W closes the chromeless window via `fx.closeWindow` (same as header X; settings hides the header Close/Minimize/Maximize controls, so these keys are the keyboard path), Cmd/Ctrl-Q calls Native `fx.quitApp`, Cmd/Ctrl-, opens settings, Cmd/Ctrl-[ and Cmd/Ctrl-] walk sidebar session history, Cmd/Ctrl-B toggles the sidebar rail, Cmd/Ctrl-C copies the last non-empty turn via `fx.writeClipboard`, Enter send/queue, the composer circle is Stop while streaming (cancels; does not queue), Esc overlay-then-cancel (closes the model, access, effort, goal-status, or git-branch picker first when one is open). Ctrl-Tab opens a local session switcher (cycle with Ctrl-Tab / Ctrl-Shift-Tab, click to switch, Esc cancels); it is not a provider session fork. Cmd/Ctrl-Enter
steers a live daemon turn via a one-shot sidecar (hello + `steer`).
Waku does not steer when attach `supportsSteer` is false or unknown —
those follow-ups queue, same as Send while busy. fx ask / fx acp / demo
stay queue-only.
When `WAKU_DAEMON_ADDRESS` or persisted `last_daemon_address` is set,
composer Set goal / Clear goal / Refresh goal one-shots hello + `goal`
(set/clear/refresh). Set reuses the composer draft as the objective
(status `active`). The current objective shows with ellipsis. The goal
row can set Codex `ThreadGoalStatus` (`active` / `paused` / `blocked` /
`usageLimited` / `budgetLimited` / `complete`) over the daemon sidecar
(`goal` set, `objective: null`, `replace: false`). When `goalUpdated`
includes `tokensUsed` / `tokenBudget` / `timeUsedSeconds`, the goal
row shows a muted one-line meter (`12k/100k · 3m`, or `tokensUsed`
only if there is no budget). This is not the full Waku goal dialog
(no editable budget field). fx ask / fx acp / demo do not get Goal.

Daemon (sidecar, not embedded): when `WAKU_DAEMON_ADDRESS` is set, Send
spawns the same binary as `faku daemon-proxy <addr>` with hello +
`attachSession` + prompt JSON in the one-shot spawn stdin.
When the session has no persisted runtime id, that first stdin also
includes `start` (mapped from stored `access_mode`, `interaction_mode`,
`model`, `reasoning_effort`, and `project_path`) before prompt; later sends keep attach +
prompt.
`attachSession` is a one-shot before the daemon prompt, not a live
runtime loop. The sidecar does the TCP + WebSocket handshake to
`ws://{addr}/v1`, prints each incoming text frame as one stdout line,
and exits on `turnFinished` / `rejected` / `error`. The desktop update
loop never holds that socket. `textDelta` appends to the assistant
turn; `turnFinished` settles and drains the success-only queue. Stop /
Esc cancels the spawn and one-shots hello + `cancel` for that
session/runtime so the daemon tears down the provider turn too.
Cmd/Ctrl-Enter steers a live daemon turn via a second one-shot sidecar
(hello + `steer`); regular Send while busy still queues.

Missing `WAKU_DAEMON_ADDRESS` keeps one-shot `fx acp` / `fx ask` / the demo timer. The
address is persisted as `last_daemon_address` in `sessions.json` for a
later send in the same catalog; there is no picker UI. Token comes from
`WAKU_DAEMON_TOKEN` when set. Local `sessions.json` remains the catalog
of record; `saveTaskState` is a best-effort one-shot mirror when a daemon
address is set. Wire `loadTaskState` talks to the daemon only, and is
only a first-run fill when that local catalog is missing.

This is a sidecar. The Waku daemon is not embedded.
Daemon sidecar hello is protocol v4 (`protocolVersion: 4`) to match
current waku-daemon. Codex `/goal` is a first cut over that sidecar
(hello + `goal` set/clear/refresh and a composer status picker; persist
last-known objective/status/usage from `goalUpdated` when it arrives
in the same spawn). Usage is documented `ThreadGoal` fields only
(`tokenBudget`, `tokensUsed`, `timeUsedSeconds`). It is not on
fx ask / fx acp / demo and not the full Waku goal dialog. fx-first
(`fx acp` / `fx ask` / demo) does not use daemon hello.

Client Hello: { type, protocolVersion, token, clientId, resumeFrom }.
Request: { type, requestId, sessionId, runtimeId, command }. Nil UUID
requestId = notify. Timeout 120s. First-cut commands: loadTaskState,
hydrateSession, saveTaskState, attachSession, start, prompt, steer, cancel,
goal, closeSession. Start defaults to provider/binary "fx".

## License

GPL-3.0-only for this Waku-inspired client. Not a verbatim copy of Waku's
Rust or TypeScript sources. Native SDK and Vercel fx are Apache-2.0.
See LICENSE and NOTICE.
