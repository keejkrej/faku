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
(chromeless 48px header, measured sidebar, composer send circle); sidebar
Search filters the local `sessions.json` catalog; the sidebar collapse
control works and is restored; headless paths are unchanged.

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
`{fx_path} acp` (same probe as today: `~/.local/bin/fx`, then `fx` on
PATH). Native `fx.spawn` writes **one stdin buffer and then closes
stdin**. There is no write-to-running-child. The buffer is NDJSON
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
`session/load`, `session/close`, or `session/list`. `session/cancel`
cannot be written after spawn; Stop / Esc uses `fx.cancel`.
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
turn. The `session/prompt` result `stopReason` settles the turn and
drains the success-only queue (`cancelled` / `refusal` / JSON-RPC
error do not drain). This is **not** a long-lived ACP loop: each Send
starts a new `fx acp` process and closes stdin.

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
`PWD` is not used. Protocol `StartOptions.cwd` stays unused.

New sessions inherit `last_project_path` from `sessions.json` when one
was persisted. There is no project picker and no worktree materialization.

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

`fx acp` is spawned one-shot per Send (same family as cursor-agent / grok).
`src/acp.zig` has newline-delimited JSON-RPC 2.0 builders/parsers for
`initialize`, `session/new`, `session/resume`, `session/set_mode`,
`session/set_config_option`, `session/prompt`, `session/cancel`, plus
a `session/update` / `stopReason` scanner.

This is **not** a long-lived ACP connection. Native `fx.spawn` accepts
stdin only at spawn time (one buffer, then stdin closes). Permission
requests and mid-turn `session/cancel` cannot be written to the child.
Do not treat this as a working interactive ACP loop. A later cut can
keep the process open once a stdin-write effect exists.

## Scope

Ready: desktop shell, demo sessions + timer fallback, one-shot `fx acp`
when the CLI is present, `fx ask --image` / `fx ask` fallback, local
session catalog + hydrate, waku-protocol v3 JSON builders + server-frame
parser, one-shot daemon sidecar, provider id "fx".

Later: a long-lived daemon socket in the update loop (not this cut),
a long-lived `fx acp` loop once a stdin-write effect exists.

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
access_mode) — no demo rows and no transcripts. The document also stores
`last_project_path`, `last_model`, `last_access_mode`,
`last_daemon_address`, `sidebar_collapsed`, and `sidebar_width` so a
new session can inherit the last workspace and last model/access, a
later send can reuse the last sidecar address, and the sidebar collapse
control is restored. The sidebar settings gear opens a panel that edits
those persisted defaults. There is no daemon picker.
Selecting a session hydrates its turns and `queued_messages` from the same
file. Daemon `hydrateSession` runs only when that local transcript is empty.
Composer drafts are a sibling `drafts.json` (not mixed into the
session catalog) so a New Task can persist before the session row exists.
Keys match Waku: `newSession` or `newSession{project_path}` for untitled
drafts, `session{id}` after the session has started. Each record is
`{ text, image_path }` — one optional local path, not a Waku
`waku-attachment:` blob. When that file exists, Send adds
`fx ask --image PATH` before `--`. A missing file omits the flag.
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
`RemoveSession` is the only delete. After a successful local remove,
`closeSession` is a best-effort one-shot when a daemon address is set.
New untitled sessions are not written
until they have real content.

Send while that session is streaming appends to its follow-up queue and
persists. A successful finish (demo timer complete, ACP `stopReason`
other than cancelled/refusal, or `fx ask` exit 0) drains the next queued
prompt. Stop, Esc, a cancelled/refused ACP prompt, and a non-zero
`fx ask` exit do not drain; partial assistant text stays, then the
session is saved.

One-shot `fx acp` mints and resumes an `fx_session_id` (same saved fx
session). `fx ask --json` still mints/resumes that field on the image
and fallback path. After a successful turn, Faku stores that workspace's
`HEAD` sha on the session (`rewind_refs` in `sessions.json`); rewind is
not offered yet.

## Demo vs daemon

Demo fallback: "port waku to zig" on fx, "fix auth listener" on claude.
New sessions default to fx. Without the fx binary, Send streams a local
canned reply (about 12 ticks / 90ms). Send while streaming with a draft
queues on that session (persisted). Successful finish drains the next
item; empty Send, Stop, or Esc cancels without draining.

Keys: Cmd/Ctrl-N new session, Enter send/queue, Esc cancel. Cmd-Enter is
not a live steer yet.

Daemon (sidecar, not embedded): when `WAKU_DAEMON_ADDRESS` is set, Send
spawns the same binary as `faku daemon-proxy <addr>` with hello +
`attachSession` + prompt JSON in the one-shot spawn stdin.
`attachSession` is a one-shot before the daemon prompt, not a live
runtime loop. The sidecar does the TCP + WebSocket handshake to
`ws://{addr}/v1`, prints each incoming text frame as one stdout line,
and exits on `turnFinished` / `rejected` / `error`. The desktop update
loop never holds that socket. `textDelta` appends to the assistant
turn; `turnFinished` settles and drains the success-only queue. Stop /
Esc cancels the spawn.

Missing `WAKU_DAEMON_ADDRESS` keeps one-shot `fx acp` / `fx ask` / the demo timer. The
address is persisted as `last_daemon_address` in `sessions.json` for a
later send in the same catalog; there is no picker UI. Token comes from
`WAKU_DAEMON_TOKEN` when set. Local `sessions.json` remains the catalog
of record; `saveTaskState` is a best-effort one-shot mirror when a daemon
address is set. Wire `loadTaskState` talks to the daemon only, and is
only a first-run fill when that local catalog is missing.

This is a sidecar. The Waku daemon is not embedded.

Client Hello: { type, protocolVersion, token, clientId, resumeFrom }.
Request: { type, requestId, sessionId, runtimeId, command }. Nil UUID
requestId = notify. Timeout 120s. First-cut commands: loadTaskState,
hydrateSession, saveTaskState, attachSession, start, prompt, steer, cancel,
closeSession. Start defaults to provider/binary "fx".

## License

GPL-3.0-only for this Waku-inspired client. Not a verbatim copy of Waku's
Rust or TypeScript sources. Native SDK and Vercel fx are Apache-2.0.
See LICENSE and NOTICE.
