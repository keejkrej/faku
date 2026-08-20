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

The embed path is ACP (fx acp), same family as cursor-agent / grok. Live mode
will spawn argv [fx, acp] with the command permission (probe ~/.local/bin/fx,
then PATH). One-shot demo can use fx ask. This cut does not exec fx. Demo mode
fake-streams a canned reply that mentions fx.

## Scope

Ready: desktop shell, demo sessions + timer stream, waku-protocol v3 JSON
builders, provider id "fx".

Later: live waku-daemon WebSocket, live fx acp spawn, saveTaskState queue,
provider probe.

No listSessions / createSession. Catalog is loadTaskState. New session is a
client-built AgentSession + saveTaskState.

## Run

Install the Native CLI globally, then from this directory:

    native test --yes
    native dev --yes
    native check
    native build

## Demo vs daemon

Demo (default): "port waku to zig" on fx, "fix auth listener" on claude. New
sessions default to fx. Send streams a local canned reply (about 12 ticks / 90ms).
Send while streaming with a draft queues; empty Send, Stop, or Esc cancels.

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
