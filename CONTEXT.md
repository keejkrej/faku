# CONTEXT

Single-context glossary and architecture for Faku. Durable product
language lives here; per-file behavior stays in `src/` comments.
Do not invent Native APIs, git recipes, or Waku surfaces this cut
does not implement.

## Product

Faku = fx + Waku. A Native SDK Zig desktop for local coding agents.
First-party provider is the keejkrej/fx fork
(https://github.com/keejkrej/fx). Waku-protocol compatible. Faku is
the window; waku-daemon can stay the brain. Chrome matches the stopped
Waku-parity cut: chromeless 48px header, measured sidebar, composer
send circle.

## Glossary

| Term | Meaning here |
| --- | --- |
| **Faku** | This desktop. Not a copy of Waku's Rust or TypeScript sources. |
| **fx** | keejkrej/fx fork of vercel-labs/fx (https://github.com/keejkrej/fx). Default first-class provider. Install from GitHub Releases into `~/.fx/bin`, not fx.sh. Surfaces: interactive, `fx ask`, `fx acp`, `fx login` / `fx login grok` / `fx login codex`. |
| **Waku** | Egoist's coding-agent app. Faku is Waku-shaped chrome + protocol, not an embedded daemon. |
| **waku-daemon** | Optional brain. Talked to only through a one-shot sidecar when `WAKU_DAEMON_ADDRESS` (or persisted `last_daemon_address`) is set. Not embedded. |
| **Native / Native SDK** | Vercel Native: markup + Zig Model / Msg / update loop. Effects are the only window-side I/O. |
| **ACP** | Agent Client Protocol. fx ACP is JSON-RPC 2.0 over stdio, protocol version 1. |
| **one-shot** | Spawn writes one stdin buffer, then Native closes stdin. Each Send starts a new process. Not a live loop. |
| **sidecar** | A `faku acp-proxy` or `faku daemon-proxy` child. The desktop update loop never holds the child stdin or a WebSocket. |
| **sessions.json** | Local catalog of record (Native `app_dirs` data, app name `faku`). Not the daemon. |
| **drafts.json** | Sibling file for composer drafts. Not mixed into the session catalog. |
| **session** | A client-built catalog row. New sessions are not written until they have real content. |
| **fx_session_id** | Saved fx / ACP `sessionId`, or Claude stream-json `session_id`. Same field `fx ask --json` uses. Empty on a Fork clone so the next Send calls `session/new` (ACP) or omits `--resume` (Claude). |
| **runtime_id** | Daemon runtime id. Empty until a daemon `start` / attach path stores one. |
| **project_path** | Session cwd. Empty is Local / host cwd. |
| **access_mode** | Stored Waku runtime mode. Maps onto fx `ask` / `code` (ACP) and `FX_PERMISSION_MODE` (`ask` / `auto` / `yolo`). New sessions default to Waku `fullAccess`. |
| **loadTaskState** | Catalog fill. Local JSON today. Daemon `loadTaskState` is only a first-run fill when the local catalog is missing. |
| **saveTaskState** | Best-effort daemon mirror of one started-session skeleton. Does not replace the local catalog. |
| **hydrateSession** | Daemon transcript fill when the local transcript is empty. Local turns win. |
| **argv slot** | Every flag and operand is its own spawn argument. Never interpolate into the chdir `-c` script. |
| **right panel** | First-cut Files + Diff + Background pane to the right of the conversation. Default closed. |
| **Settings Providers** | Settings page listing `protocol.ProviderId` catalog rows. fx probe status is live (`fx_available` / `fxPath()`); other ids `--help`-probe PATH `defaultBinary()` (Available / Not found). Apply sets the selected session's `provider`. Live Send for probed ACP stdio providers (cursor / opencode / kimi `acp`, grok `agent stdio`) uses the same one-shot acp-proxy as fx (first-cut official ACP v1 image content blocks on `session/prompt` when a composer image is attached: base64 + mimeType, ~256KB raw, fail-closed on overflow / bad file; fx still `fx ask --image`, no ACP image blocks); Available Claude is one-shot `claude -p --output-format stream-json --verbose --include-partial-messages --forward-subagent-text` (not ACP; later Sends pass documented `--resume {fx_session_id}` when that field is non-empty; first Send and Fork omit it; not `--continue`; documented image path inside that `-p` prompt when a composer image is attached; stdout is NDJSON with live `text_delta`; live Subagent Background from `parent_tool_use_id` plus a bounded 512KB last-window from forwarded `parent_tool_use_id` text (Environment Summary stays a one-line preview; right-panel Background shows the stored log with CSI stripped for display); live Monitor Background from Claude `Monitor` `tool_use` plus a bounded 512KB last-window log from matching user `tool_result` (Environment Summary stays a one-line preview; right-panel Background shows the stored log with CSI stripped for display); first-cut settled Monitor / Subagent stay in the runtime registry after the turn (status from Process settle; Monitor / Subagent last-window kept; Faku-side Dismiss, not Claude TaskStop; not live / Running / Monitoring after `-p` exits); Available Codex is one-shot `codex exec {prompt}` (not ACP; documented `--image {path}` after the prompt when a composer image is attached); Available Amp is one-shot `amp -x {prompt}` (not ACP; documented `@{path}` in the `-x` prompt when a composer image is attached); Available Pi is one-shot `pi --mode json {prompt}` (not ACP, not `--mode rpc`; documented `@{path}` after json when a composer image is attached; stdout is JSON events with live `text_delta`). fx Not found copies the verified keejkrej/fx Unix install script (`curl -fsSL https://github.com/keejkrej/fx/releases/latest/download/install | bash` into `~/.fx/bin`; not fx.sh); fx Available copies `fx login` (convenience; `--help` is not auth). Other missing CLIs get a PATH hint only. Not Waku onboarding / OAuth / auto-install. |
| **Settings Appearance** | Settings page for chrome theme and language. Theme: System (follow OS `on_appearance`), Light, or Dark. Default System. Language: System / English / 简体中文 / 日本語. Default System. System language follows process `LC_ALL` / `LC_MESSAGES` / `LANG` (Native has no locale API). Explicit language chips are autonyms in every locale. Persists `theme_preference` and `language_preference` on `sessions.json` extras (same bag as model/access/effort/project/daemon). Missing / unknown → System. High contrast / reduce motion still follow the OS. Settings chrome strings (title, nav, Appearance Theme / Language), first-cut sidebar date-bucket titles, and the chrome unassign Today list-item follow the resolved locale this cut. |
| **Settings Skills** | Settings page that scans project `SKILL.md` files. Runtime-only. Composer `$name` insert; not body auto-prepend and not enable toggles. |
| **Settings Usage** | Settings page showing the selected session's local context window (`context_used` / `context_size` from ACP `usage_update`) and thread-goal tokens (`threadGoalUsageLabel`). Read-only. Not daemon `LoadUsageHistory`, not a cost chart, not Daily / Monthly / Projects. |
| **Settings Computer Use** | Settings page for Waku-nav parity. First-cut is Unavailable / Off / empty always-allowed apps. Native has no Screen Recording or Accessibility APIs; no Swift helper, permission probe, or app grants this cut. |

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
`$HOME/.fx/bin/fx --help`, leftover `~/.local/bin/fx --help` (not the
fork layout), then `fx --help` on PATH. Missing or rejected
binary keeps the demo timer so `native test --yes` stays green without
a real fx install. ACP does not accept image or audio blocks; draft
`image_path` keeps `fx ask --image`.

**ACP stdio providers (first-cut live non-fx).** After daemon and fx
branches, Send on a live ACP stdio provider — `speaksBareAcp`
(cursor, opencode, kimi; Waku `launch_for` argv `["acp"]`, Faku binaries
`cursor-agent` / `opencode` / `kimi`) or grok (`agent stdio`, not a bare
`acp` subcommand) — when `providers.isAvailable` (PATH `--help`
probe) spawns one-shot `faku acp-proxy -- {binary} …transport…`
with the existing ACP stdin batch. Transport argv is `acp` for
bare-acp ids and `agent stdio` for grok (`faku acp-proxy -- grok
agent stdio`). `reply_path` stays `.fx` so ACP stream parsing
(`fx_line` / `fx_exit` / `fx_spawn_acp`) is unchanged. Permission
mode and project cwd / resume id follow the fx rules. Composer
image attach ships first-cut official ACP v1 image content blocks
on `session/prompt` (`{ "type": "image", "data": "<base64>",
"mimeType": "image/png" }`; optional `uri` omitted; png / jpeg /
jpg / gif / webp; ~256KB raw cap). Missing, unreadable, unknown
type, or encoded-batch overflow fail closed to demo (never a
truncated image). Agents that reject image blocks surface via
existing error/demo paths. fx still uses `fx ask --image` and
never puts image blocks on the fx ACP stdin batch. Unavailable
cursor / opencode / grok / kimi still use the demo timer.
Not a long-lived ACP loop.

**Claude print-mode stream-json (first-cut live non-ACP).** After daemon, fx, and
ACP stdio branches, Send on `ProviderId.claude` when
`providers.isAvailable` spawns one-shot
`{binary} -p --output-format stream-json --verbose
--include-partial-messages --forward-subagent-text {prompt}` (argv
slots; empty stdin). `--forward-subagent-text` is always its own slot
after `--include-partial-messages` (code.claude.com/docs/en/cli-reference;
prefer the argv flag). When `session.fx_session_id` is non-empty,
documented `--resume {fx_session_id}` is two argv slots after
`--forward-subagent-text` and before the prompt
(code.claude.com/docs/en/headless "Continue conversations"). First
Send and Fork omit both resume slots — never a
bare `--resume`. Not `--continue` / `-c` (that is most-recent in the
current directory). Composer image attach adds the documented
filesystem path inside that single `-p` prompt (`claude -p 'Analyze
this image: {path}\n{prompt}'`;
code.claude.com/docs/en/common-workflows "Work with images"). There is
no `--image` flag (code.claude.com/docs/en/cli-reference). Join
overflow fails closed to demo rather than truncating. `reply_path`
stays `.fx` with `fx_spawn_acp = false` and `fx_spawn_claude_json` so
stdout lines use the Claude JSON parser in `lines.zig` (live
`stream_event` / `event.delta.type == text_delta`, not a prose dump of
raw NDJSON). Non-empty `parent_tool_use_id` is subagent traffic: it
does not `appendToTurn` on the main stream, and it (plus Agent
`tool_use`) fills live Subagent Background rows while streaming.
Forwarded `parent_tool_use_id` text (`text_delta` / assistant
text content) fills a bounded 512KB last-window on that live
Subagent (same size/policy as Monitor; not `appendToTurn`).
Main-turn `tool_use` / `content_block` with `name` `Monitor` and a
non-empty `id` fills live Monitor Background rows while streaming
(stable title `Monitor`; not Bash / Agent / `parent_tool_use_id`).
Matching user `tool_result` (`tool_use_id`) fills a bounded
runtime-only output preview on that row (not `appendToTurn`; does
not register a new Monitor). When the turn settles, those
Monitor / Subagent rows stay as settled registry rows (status from
Process settle; Monitor / Subagent last-window kept; Faku-side Dismiss
plus Dismiss all settled for the selected session;
not live
after `-p` exits).
If no deltas arrived, the final `result` text is the
fallback. `session_id` from a `result` or `system`/`init` event reuses
`fx_session_id` when that documented field is present. Project cwd
reuses `fx_ask_chdir_script`. Not ACP, not `claude acp`, not
`--input-format stream-json`, not `--mode rpc`, not `--bare`, not
permissions bypass, not acp-proxy. Unavailable claude stays demo.

**Codex exec (first-cut live non-ACP).** After the Claude branch, Send
on `ProviderId.codex` when `providers.isAvailable` spawns one-shot
`{binary} exec {prompt}` (argv slots; empty stdin). Composer image
attach adds documented `--image {path}` after the positional prompt
(`codex exec {prompt} --image {path}`). `--image` is clap
`num_args = 1..`; putting the prompt after the flag makes clap treat
it as another image path. Same argv-slot pattern as `fx ask --image`
(flag then path); not path-in-prompt. Progress streams to stderr;
the final agent message prints to stdout. `reply_path` stays `.fx`
with `fx_spawn_acp = false` so stdout lines use the existing non-ACP
`handleFxLine` path. Project cwd reuses `fx_ask_chdir_script`. Not
ACP, not acp-proxy, not stream-json, not `--full-auto` / sandbox
bypass / `--ask-for-approval never`. Unavailable Codex stays demo.

**Amp execute-mode (first-cut live non-ACP).** After the Codex branch,
Send on `ProviderId.amp` when `providers.isAvailable` spawns one-shot
`{binary} -x {prompt}` (argv slots; empty stdin; `--execute` is the
long form). Composer image attach adds a documented `@{path}` mention
inside that single `-x` prompt (`amp -x '@{path}\n{prompt}'`). There
is no `--image` flag. Execute mode sends the message, waits until the
agent ends its turn, prints its final message, and exits. `reply_path`
stays `.fx` with `fx_spawn_acp = false` so stdout lines use the
existing non-ACP `handleFxLine` path. Project cwd reuses
`fx_ask_chdir_script`. Not ACP, not `amp acp`, not acp-proxy, not
`--stream-json`, not `--dangerously-allow-all` /
`dangerouslyAllowAll`. Unavailable Amp stays demo.

**Pi json-mode (first-cut live non-ACP).** After the Amp branch,
Send on `ProviderId.pi` when `providers.isAvailable` spawns one-shot
`{binary} --mode json {prompt}` (argv slots; empty stdin). Composer
image attach adds documented `@{path}` after `--mode json`
(`pi --mode json @{path} {prompt}`). File args are `@path` prefixes;
there is no `--image` flag. JSON mode emits session events as JSON
lines; `text_delta` streams into the live assistant turn. Raw JSON
is not dumped as prose. `reply_path` stays `.fx` with
`fx_spawn_acp = false` and `fx_spawn_pi_json` so stdout lines use
the Pi JSON parser. Project cwd reuses `fx_ask_chdir_script`. Not
ACP, not acp-proxy, not `--mode rpc`, not `-p` / `--print`, not
`-a` / `--approve` / invented dangerously-* flags. Unavailable Pi
stays demo.

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

`fx acp`, probed bare-`acp` providers (`cursor-agent acp`,
`opencode acp`, `kimi acp`), and grok `agent stdio` are spawned one-shot per
Send through `faku acp-proxy`. Native
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

## Right panel: Files / Diff / Background

Command palette Show / Hide right panel toggles a first-cut Files +
Diff + Background pane. Default closed. Files width persists (`right_panel_open` /
`right_panel_width`); Diff and Background tabs are runtime-only (default Files). Files
lists the same bounded `file_mention` cache used by composer `@`
mentions. Diff hosts Environment Compare / Review (Branch,
Uncommitted, Staged, Unstaged, Committed, LastTurn). Background is the
Environment Summary Process / Monitor / Subagent row surface (kind,
title, live-or-settled status, Monitor / Subagent 512KB last-window log). Not Browser, Terminal (no Native PTY), compact File editor,
or a full BackgroundWorkRegistry. Faku-side Monitor and Subagent Stop
on one-shot `claude -p` ships (live Stop dismisses that live row;
settled rows offer Dismiss; not Claude TaskStop mid-turn). Not daemon
`WorkspaceOperation`. Environment Summary Background is
Faku-side kind chrome (Process / Monitor / Subagent labels) plus a
runtime-only multi-row registry. This cut populates Process
("Agent turn") from window-side `is_streaming`, plus Stop agent,
and one last-turn settle (Completed / Stopped / Failed, cap 1).
Live Monitor rows come from real Claude stream-json `Monitor`
`tool_use` while streaming (stable title `Monitor`). Matching user
`tool_result` fills a bounded 512KB last-window log on that row
(runtime-only; newlines kept; CSI stored raw).
Environment Summary `detail` stays a short one-line preview. The
right-panel Background body reads a 100ms CSI-stripped render cache
of that stored log (rebuilt when dirty and at least 100ms of
`now_ms` have passed; Native view bind does not strip). Live Monitor
rows offer Stop (Faku-side dismiss of that slot; Process Stop still
`stopStream`). Live Subagent
rows come from real Claude stream-json `parent_tool_use_id` /
Agent `tool_use` while streaming, with Faku-side Subagent Stop
(dismiss that live row on one-shot `claude -p`; not Claude TaskStop
mid-turn; later `noteLiveSubagent` for that id is ignored until
`clearDismissedSubagentIds`). Forwarded `parent_tool_use_id` text
(`text_delta` / assistant text) fills a bounded 512KB last-window
on that row (runtime-only; newlines kept; same 100ms CSI-stripped
render cache; Environment Summary `detail` stays a short one-line
preview).
When the turn settles, currently-live
Monitor and Subagent become settled registry rows (status from
Process settle; Monitor / Subagent last-window kept; Faku-side
Dismiss, not live Stop / not Claude TaskStop). Honest
about one-shot `-p`: after the run's final result they are not
live / Running / Monitoring. `startPrompt` does not wipe settled
rows. Fill order is Process, then Monitor (live first, then
settled), then Subagent (live first, then settled). Settled rows
for other sessions are hidden; remove session frees that session's
Monitor / Subagent heap logs. Not sessions.json. Clicking a visible row closes the
dropdown and opens the right-panel Background tab for that id.
Dismiss all settled on Environment Summary clears the selected
session's settled leftovers (Monitor / Subagent slots plus the
cap-1 Process settle) without stopping a live stream. Not Claude
TaskStop. Not daemon `refreshBackgroundWork`.

## Settings Providers

The settings gear chrome is General | Appearance | Providers | Skills | Usage | Computer Use. Providers
lists every `protocol.ProviderId` (fx, claude, codex, amp, grok,
opencode, cursor, pi, kimi). fx is the first-party default: status is
`Available` + probed path or `Not found` from the existing boot
`--help` probe (`fx_available` / `fxPath()`). Other rows one-shot
PATH `{defaultBinary()} --help` (no `~/.local/bin/<binary>` fallback
this cut) and show `Available` / `Not found` when that exit lands.
Refresh re-runs the fx probe and every non-fx probe. Open starts
non-fx probes only. Not full onboarding / OAuth / auto-install, not
Send enable toggles.

Selecting a row highlights and shows a short blurb (name, binary, fx
path when applicable, probe status, and that live Send is one-shot
`acp` via acp-proxy for fx and probed ACP `acp` providers (cursor,
opencode, kimi; first-cut ACP v1 image content blocks when a composer
image is attached), or one-shot `grok agent stdio` via acp-proxy when grok
is Available (same image content blocks), or one-shot `claude -p --output-format stream-json
--forward-subagent-text` when claude is Available (later Sends pass
documented `--resume {fx_session_id}` when that field is non-empty;
first Send and Fork omit it; documented image path in the `-p`
prompt when a composer image is attached; stdout is NDJSON with live
`text_delta`; live Subagent Background from `parent_tool_use_id` plus a bounded 512KB last-window from forwarded `parent_tool_use_id` text (Environment Summary stays a one-line preview; right-panel Background shows the stored log with CSI stripped); live Monitor Background from Claude `Monitor` `tool_use` plus a bounded 512KB last-window log from matching user `tool_result` (Environment Summary stays a one-line preview; right-panel Background shows the stored log with CSI stripped)), or one-shot `codex exec {prompt}` when Codex
is Available (documented `--image {path}` after the prompt when a
composer image is attached), or one-shot `amp -x` / `--execute` when Amp is
Available (documented `@{path}` in the `-x` prompt when a composer
image is attached), or one-shot `pi --mode json` when Pi is Available
(documented `@{path}` after json when a composer image is attached).
fx Not found shows **Copy install
command** (clipboard
`curl -fsSL https://github.com/keejkrej/fx/releases/latest/download/install | bash`
into `~/.fx/bin`; never auto-run; not fx.sh). fx
Available shows **Copy login command** (`fx login`; Faku does not
detect auth from `--help`; optional note `fx login grok` /
`fx login codex`). Other
ids when Not found show a muted PATH hint only (no invented install
URLs). Apply ("Use for this session") sets the selected chat
session's `provider` and persists via `sessions.json`. New sessions
stay fx. Runtime-only catalog.

## Settings Appearance

First-cut theme preference plus language selector. System theme follows
OS `on_appearance` (`model.appearance.color_scheme`). Light / Dark force
that scheme in `designTokens` / `DesignTokens.themeWithOverrides`. House
pack, high contrast, and reduce motion still come from OS appearance;
pixel-snap geometry stays off. Preference persists as
`theme_preference` on `sessions.json` extras (`system` / `light` /
`dark`). Missing or unknown loads as System.

Language is System / English / 简体中文 / 日本語 chips under Theme.
Default System. Explicit labels stay autonyms in every locale; the
System chip follows the resolved locale. System resolution reads
process `LC_ALL`, else `LC_MESSAGES`, else `LANG` (take the part before
`.`, `_` → `-`, lowercase; `zh-cn` / `zh-sg` / `zh-hans*` → Simplified
Chinese; `ja` / `ja-*` → Japanese; else English, including
`zh-hant` / `zh-tw`). Native has no locale / NSLocale API this cut.
Preference persists as `language_preference` (`system` / `english` /
`simplified-chinese` / `japanese`). Missing or unknown loads as System.
Resolved locale re-labels Settings chrome (title, nav, Appearance Theme
/ Language, theme chips, OS caption), first-cut sidebar date-bucket
titles (Today / Yesterday / This week / This month / This year / Older,
plus the static relative-time words `just now` / Yesterday), and the
chrome unassign Today list-item (same `i18n.Dates.today` string as the
Today date-bucket header). UTC-day bucketing is unchanged. Not
full-app catalogs, not Native NSLocale, not tz-aware or east-asian
calendar formatting.

## Settings Usage

First-cut local meters for the selected session only. Context window
uses `Session.context_used` / `Session.context_size` (ACP
`usage_update`; compact `12.4k / 200k`). `context_size == 0` is an
honest empty: "No context usage reported yet". Thread goal tokens
reuse `threadGoalUsageLabel()` (`12k/100k · 3m`); missing fields stay
"No thread goal usage". Identity is the session header title. Persist
is already on `sessions.json`; this page is display-only. Not daemon
`LoadUsageHistory`, not a dollar chart, not Daily / Monthly / Projects
tabs.

## Settings Computer Use

First-cut nav + Unavailable page. Native has no Screen Recording,
Accessibility, or permission-probe APIs; Waku's `Waku Computer Use`
helper is macOS-only. Availability is always "Unavailable". Enable is
locked Off (no persist, no toggle). Always-allowed apps is the empty
state only. Not a Swift helper, not sky MCP, not System Settings
grant-access buttons, not an app picker.

## Settings Skills scan

The settings gear opens a panel for persisted defaults. A runtime-only
General | Appearance | Providers | Skills | Usage | Computer Use switch lists project `SKILL.md` files from
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
| Seed model / theme boot | `src/boot.zig` |
| Shell scene / app icons | `src/shell.zig` |
| Layout chrome widths | `src/layout.zig` |
| Spawn / stream effect keys | `src/effect_keys.zig` |
| Msg update / initFx | `src/update.zig` |
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
| Settings chrome + sidebar date i18n | `src/i18n.zig`, `src/sidebar_dates.zig` |

## Leftovers

Honest gaps this cut does not implement:

- Full onboarding / OAuth / auto-install (fx install/login copy
  ships; other CLIs get a PATH hint only)
- Native Pi ACP / `--mode rpc` (json-mode one-shot
  `pi --mode json {prompt}`, documented `@{path}` after json when a
  composer image is attached, ships; stdout is parsed as JSON events
  with live `text_delta`, not dumped as prose). Claude print-mode
  stream-json one-shot (`claude -p --output-format stream-json
  --verbose --include-partial-messages --forward-subagent-text`,
  documented `--resume {fx_session_id}` on later Sends when that
  field is non-empty; first Send and Fork omit it; documented image
  path in the `-p` prompt when a composer image is attached, ships;
  stdout is parsed as NDJSON — live `text_delta`, not dumped as
  prose; live Subagent Background from `parent_tool_use_id` plus a
  bounded 512KB last-window from forwarded `parent_tool_use_id`
  text; live Monitor Background from Claude `Monitor` `tool_use`
  plus a bounded 512KB last-window log from matching user
  `tool_result`; first-cut 100ms CSI-stripped render cache on those
  last-windows (piggybacks `now_ms` / the stream tick); first-cut
  settled Monitor / Subagent persist after
  the turn; Faku-side Dismiss all settled for the selected session
  ships; Environment Summary stays a one-line preview). Codex exec
  one-shot (`codex exec {prompt}`, documented `--image {path}` after
  the prompt when a composer image is attached) ships; Amp execute-mode
  one-shot (`amp -x {prompt}`, documented `@{path}` in the `-x` prompt
  when a composer image is attached) ships. Claude, Codex, Amp, and
  Pi are not ACP / a long-lived SDK session (Claude stream-json and
  Pi json-mode are one-shot JSON lines; Claude later Sends pass
  `--resume {fx_session_id}` when stored. `--forward-subagent-text`
  always. Not `--continue`, not `--input-format stream-json`, not
  `--mode rpc`). First-cut Available kimi ships via one-shot `kimi
  acp` + acp-proxy (not long-lived; ACP v1 image blocks like other
  bare-ACP ids; no invented flags).
- Usage history from daemon `LoadUsageHistory`, cost / dollar chart,
  Daily / Monthly / Projects tabs (Settings Usage ships local context
  + thread-goal tokens for the selected session)
- Real Computer Use: Native Screen Recording / Accessibility APIs,
  macOS helper, permission probe, always-allowed app picker (Settings
  Computer Use first-cut is nav + Unavailable / Off / empty apps)
- Full-app i18n catalogs / rust_i18n-style YAML, Native locale /
  NSLocale API, tz-aware date grouping (Appearance language selector
  ships: System / English / 简体中文 / 日本語; Settings chrome,
  first-cut sidebar date-bucket titles, and the chrome unassign Today
  list-item follow the resolved locale — unassign Today reuses
  `i18n.Dates.today`, same string as the Today date-bucket header.
  UTC-day bucketing is unchanged. Not full-app catalogs, not Native
  NSLocale, not east-asian calendar formatting)
- Claude CLI TaskStop / long-lived ACP, daemon
  `refreshBackgroundWork`, full BackgroundWorkRegistry
  event/reconcile parity (Environment Summary
  ships Process / Monitor / Subagent kind chrome, a Process
  registry from stream/settle, live Monitor rows from Claude
  `Monitor` `tool_use` with a Waku-sized 512KB last-window log from
  matching user `tool_result` — newlines kept, CSI stripped for
  display via a 100ms render cache piggybacking `now_ms` / the
  stream tick (not GPUI SharedString, not a dedicated Native
  timer), Environment Summary stays a one-line preview — plus
  Faku-side Monitor Stop that dismisses that live row on one-shot
  `claude -p` without invoking Claude's TaskStop tool mid-turn;
  live Subagent rows from Claude `parent_tool_use_id` / Agent
  `tool_use` with a matching 512KB last-window from forwarded
  `parent_tool_use_id` text (`text_delta` / assistant text; still
  off the main turn) — newlines kept, same 100ms CSI-stripped
  render cache, Environment Summary stays a one-line preview —
  plus Faku-side
  Subagent Stop that dismisses that live row on one-shot `claude
  -p` (later `noteLiveSubagent` for a dismissed id is ignored until
  `clearDismissedSubagentIds`; not Claude TaskStop mid-turn);
  first-cut settled Monitor / Subagent persist after the turn
  (status from Process settle; Monitor / Subagent last-window kept;
  Faku-side Dismiss, not Claude TaskStop / daemon
  `refreshBackgroundWork`; not live after `-p` exits); Faku-side
  Dismiss all settled for the selected session (settled Monitor /
  Subagent plus the cap-1 Process settle; live rows and the stream
  stay; not Claude TaskStop / daemon registry reconcile); and a first-cut
  right-panel Background surface from those rows that shows the
  stored Monitor / Subagent log, Stop when the selected row is
  a live Process, live Monitor, or live Subagent, and Dismiss when
  the selected row is a settled Monitor or Subagent; not Waku
  BackgroundWorkRegistry event/reconcile/driver-refresh parity)
- First-cut GitHub Releases wrap documented `native package` trees
  (host-native; no eject) as user-facing installers: unsigned macOS
  DMG (`--signing none`; no Apple identity / notarize), amd64 Debian
  `.deb` from the Linux FHS install tree, silent NSIS `.exe` from the
  early Windows directory. No zip. Unsigned NSIS (SmartScreen).
  Fedora/Arch compile with Native CLI. Not iOS/Android.
- Further `main.zig` extract (`initialModel` / appearance boot live in
  `boot.zig`; icons + shell scene live in `shell.zig`; layout chrome
  lives in `layout.zig`; spawn / stream effect keys live in
  `effect_keys.zig`; remaining `main.zig` leftovers are
  re-exports + `main()` + demo seed strings)
- Long-lived ACP or daemon socket in the update loop
- fx ACP still rejects image blocks (`fx ask --image`). First-cut
  ACP image content blocks (base64 + mimeType, ~256KB raw, size
  fail-closed) ship for probed cursor / opencode / grok / kimi. Codex uses
  `codex exec --image`, not ACP; Amp uses execute-mode `@{path}` in
  the `-x` prompt, not ACP; Pi uses json-mode `@{path}`, not ACP;
  Claude uses print-mode path-in-prompt, not ACP

