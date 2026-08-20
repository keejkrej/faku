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

## UI

The window is Waku-shaped chrome, not a pixel-perfect GPUI clone: 1380×880
(min 980×680), Geist light tokens mapped from Waku 0.1.9 Theme::light, a
sidebar with New Task / Search / Today, `{header_title}` plus muted Faku
in the toolbar, right-aligned user bubbles, a queued-follow-up card, and
an Enter-to-send composer ("Do anything...") with provider/access chips.
Cmd/Ctrl-N starts a session; Esc cancels. Live `fx ask` and the demo timer
are unchanged — this is the shell, not a new backend.

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

    fx ask <prompt>

Stdout lines stream into the assistant turn. Exit settles the turn and
dequeues the next prompt if one was queued. Stop / Esc cancels the spawn
and the demo timer; partial assistant text stays.

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
the CLI is present, waku-protocol v3 JSON builders, ACP JSON-RPC stubs,
provider id "fx".

Later: live waku-daemon WebSocket, live `fx acp` once a stdin-write
effect exists, saveTaskState queue.

No listSessions / createSession. Catalog is loadTaskState. New session is a
client-built AgentSession + saveTaskState.

## Run

Install the Native CLI globally, then from this directory:

    native test --yes
    native dev --yes
    native check
    native build

## Demo vs daemon

Demo fallback: "port waku to zig" on fx, "fix auth listener" on claude.
New sessions default to fx. Without the fx binary, Send streams a local
canned reply (about 12 ticks / 90ms). Send while streaming with a draft
queues; empty Send, Stop, or Esc cancels.

Keys: Cmd/Ctrl-N new session, Enter send/queue (Shift-Enter newline),
Cmd-Enter also submits (no live steer yet), Esc cancel.

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
