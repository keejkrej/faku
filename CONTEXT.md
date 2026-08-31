# CONTEXT

Single-context glossary and architecture for Faku. Durable product
language lives here; per-file behavior stays in `src/` comments.
Do not invent Native APIs, git recipes, or Waku surfaces this cut
does not implement.

## Product

Faku = fx + Waku. A Native SDK Zig desktop for local coding agents.
First-party provider is Vercel fx. Waku-protocol compatible. Faku is
the window; waku-daemon can stay the brain. Chrome matches the stopped
Waku-parity cut: chromeless 48px header, measured sidebar, composer
send circle.

## Glossary

| Term | Meaning here |
| --- | --- |
| **Faku** | This desktop. Not a copy of Waku's Rust or TypeScript sources. |
| **fx** | Vercel coding-agent harness (`https://fx.sh`). Default first-class provider. Surfaces: interactive, `fx ask`, `fx acp`, `fx resume`. |
| **Waku** | Egoist's coding-agent app. Faku is Waku-shaped chrome + protocol, not an embedded daemon. |
| **waku-daemon** | Optional brain. Talked to only through a one-shot sidecar when `WAKU_DAEMON_ADDRESS` (or persisted `last_daemon_address`) is set. Not embedded. |
| **Native / Native SDK** | Vercel Native: markup + Zig Model / Msg / update loop. Effects are the only window-side I/O. |
| **ACP** | Agent Client Protocol. fx ACP is JSON-RPC 2.0 over stdio, protocol version 1. |
| **one-shot** | Spawn writes one stdin buffer, then Native closes stdin. Each Send starts a new process. Not a live loop. |
| **sidecar** | A `faku acp-proxy` or `faku daemon-proxy` child. The desktop update loop never holds the child stdin or a WebSocket. |
| **sessions.json** | Local catalog of record (Native `app_dirs` data, app name `faku`). Not the daemon. |
| **drafts.json** | Sibling file for composer drafts. Not mixed into the session catalog. |
| **session** | A client-built catalog row. New sessions are not written until they have real content. |
| **fx_session_id** | Saved fx / ACP `sessionId`. Same field `fx ask --json` uses. Empty on a Fork clone so the next Send calls `session/new`. |
| **runtime_id** | Daemon runtime id. Empty until a daemon `start` / attach path stores one. |
| **project_path** | Session cwd. Empty is Local / host cwd. |
| **access_mode** | Stored Waku runtime mode. Maps onto fx `ask` / `code` (ACP) and `FX_PERMISSION_MODE` (`ask` / `auto` / `yolo`). New sessions default to Waku `fullAccess`. |
| **loadTaskState** | Catalog fill. Local JSON today. Daemon `loadTaskState` is only a first-run fill when the local catalog is missing. |
| **saveTaskState** | Best-effort daemon mirror of one started-session skeleton. Does not replace the local catalog. |
| **hydrateSession** | Daemon transcript fill when the local transcript is empty. Local turns win. |
| **argv slot** | Every flag and operand is its own spawn argument. Never interpolate into the chdir `-c` script. |
| **right panel** | First-cut Files + Diff pane to the right of the conversation. Default closed. |
| **Settings Providers** | Settings page listing `protocol.ProviderId` catalog rows. fx probe status is live (`fx_available` / `fxPath()`); other ids `--help`-probe PATH `defaultBinary()` (Available / Not found). Not Waku install/auth/onboarding; not a live non-fx Send driver. |
| **Settings Skills** | Settings page that scans project `SKILL.md` files. Runtime-only. Composer `$name` insert; not body auto-prepend and not enable toggles. |

Avoid: calling ACP a live WebSocket; treating the daemon as the catalog
of record; inventing Native git / pick-file / maximize / caret / PTY /
FS-watcher / env / cwd effects; inventing `session/load`,
`listSessions`, or `createSession` on this cut.

## Sessions

Path (Native `app_dirs` data directory, app name `faku`):

- Linux: `$XDG_DATA_HOME/faku/sessions.json` or `~/.local/share/faku/sessions.json`
- macOS: `~/Library/Application Support/faku/sessions.json`

Boot: if that file loads, the sidebar is session skeletons only — no
demo rows and no transcripts. Selecting a session hydrates its turns
and `queued_messages` from the same file. Missing or corrupt
`sessions.json` keeps the two first-run demo sessions and is not
overwritten until a successful load (`task_state_loaded`). Save is
merge-only; `RemoveSession` is the only delete.

Composer drafts are a sibling `drafts.json`. Keys match Waku:
`newSession` or `newSession{project_path}` for untitled drafts,
`session{id}` after the session has started. Each record is
`{ text, image_path }` — one optional local path, not a Waku
`waku-attachment:` blob.

There is no `listSessions` / `createSession`. Catalog is
`loadTaskState`. New session is a client-built session saved after
first content.

## fx vs daemon

Reply path is `fx` / `demo` / `daemon` on the model. New sessions
default to fx.

**fx (first path).** When the CLI is installed, Send on an fx session
spawns one-shot `faku acp-proxy -- {fx_path} acp`. Probe:
`~/.local/bin/fx --help`, then `fx --help` on PATH. Missing or rejected
binary keeps the demo timer so `native test --yes` stays green without
a real fx install. ACP does not accept image or audio blocks; draft
`image_path` keeps `fx ask --image`. Non-fx providers (the claude demo
session) still use the demo timer.

**daemon (sidecar, not embedded).** When `WAKU_DAEMON_ADDRESS` or
persisted `last_daemon_address` is set, Send spawns `faku daemon-proxy
<addr>` with hello + `attachSession` + prompt (and `start` when there
is no persisted runtime id) in the one-shot spawn stdin. The sidecar
does the TCP + WebSocket handshake to `ws://{addr}/v1`, prints each
incoming text frame as one stdout line, and exits on `turnFinished` /
`rejected` / `error`. Token comes from `WAKU_DAEMON_TOKEN` when set.
Hello is protocol v4. First-cut commands: `loadTaskState`,
`hydrateSession`, `saveTaskState`, `attachSession`, `start`, `prompt`,
`steer`, `cancel`, `goal`, `closeSession`. Start defaults to provider
`fx`. fx-first (`fx acp` / `fx ask` / demo) does not use daemon hello.

Local `sessions.json` remains the catalog of record. Daemon
`saveTaskState` is a best-effort one-shot mirror. Wire `loadTaskState`
talks to the daemon only, and is only a first-run fill when that local
catalog is missing.

## ACP (one-shot, not a live loop)

`fx acp` is spawned one-shot per Send through `faku acp-proxy`. Native
`fx.spawn` accepts stdin only at spawn time (one buffer, then stdin
closes). The sidecar owns the child stdin and auto-answers official
`session/request_permission` from that run's access mode — not a prompt
dialog. Mid-turn `session/cancel` cannot be written from the window;
Stop / Esc uses `fx.cancel`.

Official methods on this cut: `initialize`, `session/new` (first
turn), `session/resume` (later turns, stored `fx_session_id`),
`session/set_mode`, `session/set_config_option` (model, omitted when
empty), `session/prompt`. This cut does not call `session/load`,
`session/close`, or `session/list`. Cwd on `session/new` /
`session/resume` is the session `project_path` when that directory
exists, else `"."`.

`--no-save` and `--auto`/`--yolo` flags are not used on the ACP spawn.
fx ACP modes are `ask` and `code` (not Waku `fullAccess`). There is no
`--model` argv on the ACP spawn; model and access also ride
`FX_MODEL` / `FX_PERMISSION_MODE` via `/usr/bin/env`.

## Native effect limits

Do not invent Native APIs. Documented gaps this cut works around:

- `fx.spawn` writes one stdin buffer, then closes stdin.
- `SpawnOptions` has no `env` field. Prefix `/usr/bin/env KEY=val` on
  the child only; do not export on the Faku process.
- `SpawnOptions` has no `cwd` field. `fx ask` and git probes chdir via
  `/bin/sh -c 'cd -- "$1" && shift && exec "$@"'`. `PWD` is not used.
- No Native git effect. Git is sidecar `fx.spawn` of `git`.
- No `fx.pickFile` / file-open effect. Folder and image pickers are OS
  sidecars.
- No `fx.revealPath`. Reveal folder is `open` / `xdg-open`.
- No `fx.maximizeWindow`. Maximize is an OS zoom sidecar.
- No window-focus observation, caret API, PTY, FS watcher, or debounce
  timer.

Every git flag and operand is its own **argv slot**. Never interpolate
user strings into the chdir `-c` script.

## Sidecar git

Composer project-row git (branch, checkout, commit, push, fetch,
worktree, dirty / numstat / ahead-behind) and Environment Compare are
one-shot `git` spawns. Runtime-only labels are not stored on
`sessions.json`. This is not Waku's daemon `InspectBranches` live
watch, not `{project_id}` UUID nesting, and not force push.

Send may snapshot the worktree (`worktree_snapshot_sha` /
`worktree_turn_end_sha` / `worktree_turn_diff_sha`; refs under
`refs/faku/`, not `refs/waku/`). Rewind undoes the last turn's files
and those chat turns using the Send-time HEAD / snapshot. Fork clones
the local transcript into a new `sessions.json` row; it is not a
provider session fork.

## Right panel: Files / Diff

Command palette Show / Hide right panel toggles a first-cut Files +
Diff pane. Default closed. Files width persists (`right_panel_open` /
`right_panel_width`); Diff tab is runtime-only (default Files). Files
lists the same bounded `file_mention` cache used by composer `@`
mentions. Diff hosts Environment Compare / Review (Branch,
Uncommitted, Staged, Unstaged, Committed, LastTurn). Not Browser,
Terminal (no Native PTY), compact File editor, or BackgroundWork tabs.
Not daemon `WorkspaceOperation`. Environment Summary Background is a
Faku-side stream row: Process ("Agent turn") while window-side
`is_streaming`, plus Stop agent, and one runtime-only last-turn settle
(Completed / Stopped / Failed, cap 1). Not a Waku
BackgroundWorkRegistry, not daemon `refreshBackgroundWork`, not
Monitor / Subagent kinds.

## Settings Providers

The settings gear chrome is General | Providers | Skills. Providers
lists every `protocol.ProviderId` (fx, claude, codex, amp, grok,
opencode, cursor, pi). fx is the first-party default: status is
`Available` + probed path or `Not found` from the existing boot
`--help` probe (`fx_available` / `fxPath()`). Other rows one-shot
PATH `{defaultBinary()} --help` (no `~/.local/bin/<binary>` fallback
this cut) and show `Available` / `Not found` when that exit lands.
Refresh re-runs the fx probe and every non-fx probe. Open starts
non-fx probes only. Not live drivers, not install/sign-in, not Send
enable toggles, not a change to `session.provider`. Selecting a row
shows a short blurb (name, binary, fx path when applicable, probe
status, and that the live fx path is one-shot `fx acp` via
acp-proxy). Runtime-only. Leftovers: onboarding, enabling non-fx on
Send, Appearance / Usage / Computer Use pages.

## Settings Skills scan

The settings gear opens a panel for persisted defaults. A runtime-only
General | Providers | Skills switch lists project `SKILL.md` files from
a bounded one-shot `find` (selected session `project_path`, else last
project path). Name is YAML `name:` when present, else the parent
folder. Selecting a row shows the body with frontmatter stripped.
Refresh on open / Refresh. Composer `$name` insert ships from this
scan (Send still ships the composer text as-is; fx loads the skill).
Not SKILL.md body stuffing, not enable/disable. Not persisted, not a
live watch.

## Code map

| Area | Start here |
| --- | --- |
| Window loop | `src/main.zig` |
| Model / Msg / Turn / Folder | `src/model.zig` |
| Session type | `src/session.zig` |
| Local catalog | `src/store.zig` |
| ACP builders | `src/acp.zig`, `src/acp_proxy.zig` |
| Daemon sidecar | `src/daemon_proxy.zig`, `src/protocol.zig` |
| Send / stream | `src/spawn.zig`, `src/stream.zig`, `src/lines.zig` |
| Environment Summary | `src/environment_summary.zig` |
| Right panel | `src/right_panel.zig`, `src/review_diff.zig` |
| Skills scan | `src/skills.zig` |
| Providers catalog | `src/providers.zig`, `src/cli_probe.zig` |
| Composer / attach | `src/composer.zig`, `src/attach.zig` |
