# Faku

Faku = fx + Waku.

Native SDK Zig desktop for coding agents. First-party Vercel fx. Waku-protocol
compatible. See NOTICE and LICENSE.

A Native SDK Zig desktop for local coding agents. Egoist asked for a Zig GPUI
slopfork so Waku compiles faster and uses less disk:
https://x.com/localhost_5173/status/2090464458695192842

This app replaces the GPUI window with Vercel Native SDK markup plus a Zig
Model / Msg / update loop. waku-daemon can stay the brain. Faku is the window,
and it is fx-first.

## Why fx

Waku does not ship Vercel fx (https://fx.sh, https://github.com/vercel-labs/fx).
Faku does, as the default first-class provider.

fx is a minimal Zig coding-agent harness (about 7.8 MiB, Apache-2.0,
model-agnostic via AI_GATEWAY_API_KEY / VERCEL_OIDC_TOKEN / FX_MODEL).
Install lands at ~/.local/bin/fx.

Surfaces: fx interactive, fx ask (headless), fx acp (Agent Client Protocol
over stdio), fx resume.

## Live path: `fx ask`

When the fx CLI is installed, Send on an fx session runs a one-shot:

    fx ask --json -- <prompt>
    fx ask --json --resume <id> -- <prompt>

`--json` prints a JSON object that includes `session_id`. Faku stores that
id on the session (`fx_session_id` in `sessions.json`) and passes it back
as `--resume` on later sends. The prompt stays after `--` so flag-like
text is safe. There is no `--model` argv. `--no-save`, `--image`, and
`--auto`/`--yolo` flags are not used.

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

If that session has a non-empty `project_path` that exists on disk, the
child's working directory is that path. Native 0.9.3 `SpawnOptions` has
no `cwd` field (only `key`, `argv`, `stdin`, `output`, callbacks), so
Faku starts `/bin/sh -c 'cd -- "$1" && shift && exec "$@"'` with the
workspace as `$1` and then `fx ask`. Empty or missing paths leave the
host process cwd (same as `fx ask` with no extra flags). `PWD` is not
used. Protocol `StartOptions.cwd` stays unused.

New sessions inherit `last_project_path` from `sessions.json` when one
was persisted. There is no project picker and no worktree materialization.

A stdout line that is JSON with `session_id` updates the stored id and
is not appended to the assistant turn. Other lines stream as today.
Exit settles the turn and dequeues the next prompt if one was queued.
Stop / Esc cancels the spawn and the demo timer; partial assistant
text stays.

Probe (boot `init_fx`, or first Send): `~/.local/bin/fx --help`, then
`fx --help` on PATH. Success stores `fx_available` and `fx_path`. Missing
or rejected binary keeps the demo timer (90ms ticks, canned reply) so
`native test --yes` stays green without a real fx install.

Non-fx providers (the claude demo session) still use the demo timer.
The status bar shows which reply path last ran: `N sessions · fx|demo · provider`.

New sessions still default to fx.

## ACP (stub only)

`fx acp` is the longer-term embed path (same family as cursor-agent / grok).
`src/acp.zig` has newline-delimited JSON-RPC 2.0 builders/parsers for
`initialize`, `session/new`, `session/prompt`, and `session/cancel`.

This cut does **not** spawn `fx acp`. Native `fx.spawn` accepts stdin only
at spawn time (one buffer). ACP needs ongoing stdin writes, and there is
no documented write-to-running-child effect yet. Do not treat the stub as
a working ACP loop.

## Scope

Ready: desktop shell, demo sessions + timer fallback, live `fx ask` when
the CLI is present, local session catalog + hydrate, waku-protocol v3 JSON
builders, ACP JSON-RPC stubs, provider id "fx".

Later: live waku-daemon WebSocket, live `fx acp` once a stdin-write
effect exists.

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
provider, untitled/has_started, project_path, fx_session_id, model,
access_mode) — no demo rows and no transcripts. The document also stores
`last_project_path`, `last_model`, and `last_access_mode` so a new
session can inherit the last workspace and last model/access.
Selecting a session hydrates its turns and `queued_messages` from the same
file. Composer drafts are a sibling `drafts.json` (not mixed into the
session catalog) so a New Task can persist before the session row exists.
Keys match Waku: `newSession` or `newSession{project_path}` for untitled
drafts, `session{id}` after the session has started. Saves are cheap
rewrites on each `draft_edit` and when leaving a session. The
`newSession` key is discarded after the first successful send so the
next New Task does not resurrect that prompt. Missing file keeps the two first-run demo sessions. A corrupt file
also keeps the demos and is not overwritten until a successful load
(`task_state_loaded`, same guard as waku-client). Save is merge-only;
`RemoveSession` is the only delete. New untitled sessions are not written
until they have real content.

Send while that session is streaming appends to its follow-up queue and
persists. A successful finish (demo timer complete or `fx ask` exit 0)
drains the next queued prompt. Stop, Esc, and a non-zero `fx ask` exit do
not drain; partial assistant text stays, then the session is saved.

`fx ask --json` mints and resumes an `fx_session_id`. This cut does not
spawn `fx acp`.

## Demo vs daemon

Demo fallback: "port waku to zig" on fx, "fix auth listener" on claude.
New sessions default to fx. Without the fx binary, Send streams a local
canned reply (about 12 ticks / 90ms). Send while streaming with a draft
queues on that session (persisted). Successful finish drains the next
item; empty Send, Stop, or Esc cancels without draining.

Product keys (not all wired): Cmd-N new, Enter send/queue, Cmd-Enter steer,
Esc cancel.

Daemon (typed, not connected): JSON frames over ws://{addr}/v1. Native has no
socket client for that. Env: WAKU_DAEMON_TOKEN, WAKU_DAEMON_ADDRESS. First
stdout line: { address, protocolVersion, pid }.

Client Hello: { type, protocolVersion, token, clientId, resumeFrom }.
Request: { type, requestId, sessionId, runtimeId, command }. Nil UUID
requestId = notify. Timeout 120s. First-cut commands: loadTaskState,
hydrateSession, saveTaskState, attachSession, start, prompt, steer, cancel,
closeSession. Start defaults to provider/binary "fx".

## License

GPL-3.0-only for this Waku-inspired client. Not a verbatim copy of Waku's
Rust or TypeScript sources. Native SDK and Vercel fx are Apache-2.0.
See LICENSE and NOTICE.
