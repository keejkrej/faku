# Faku

Faku = fx + Waku.

A Native SDK Zig desktop for local coding agents. First-party Vercel
fx. Waku-protocol compatible. See [NOTICE](NOTICE) and [LICENSE](LICENSE).

Faku is the window; waku-daemon can stay the brain. Chrome is a
chromeless 48px header (measured sidebar, composer send circle). It is
fx-first: Native SDK markup plus a Zig Model / Msg / update loop.

Egoist asked for a Zig GPUI slopfork so Waku compiles faster and uses
less disk:
https://x.com/localhost_5173/status/2090464458695192842

Product and architecture context lives in [CONTEXT.md](CONTEXT.md).
Agent wayfinding is in [AGENTS.md](AGENTS.md) and
[docs/agents/](docs/agents/). Zig sources are under [src/](src/).

## Why fx

Waku does not ship Vercel fx (https://fx.sh, https://github.com/vercel-labs/fx).
Faku does, as the default first-class provider.

fx is a minimal Zig coding-agent harness (about 7.8 MiB, Apache-2.0,
model-agnostic via `AI_GATEWAY_API_KEY` / `VERCEL_OIDC_TOKEN` /
`FX_MODEL`). Install lands at `~/.local/bin/fx`.

Surfaces: `fx` interactive, `fx ask` (headless), `fx acp` (Agent Client
Protocol over stdio), `fx resume`.

## Live path

When the fx CLI is installed, Send on an fx session spawns a one-shot
`faku acp-proxy -- {fx_path} acp`. Send on a probed ACP stdio provider
(cursor, PATH `cursor-agent`; OpenCode, PATH `opencode`; grok, PATH
`grok`) uses the same sidecar: `faku acp-proxy -- {binary} acp` for
bare-`acp` ids, or `faku acp-proxy -- grok agent stdio`. Native
`fx.spawn` writes **one stdin buffer and then closes stdin**. This is
not a long-lived ACP or WebSocket loop.

The local catalog `sessions.json` is canonical. Daemon and ACP are
best-effort sidecars: the desktop update loop never holds a socket.
`WAKU_DAEMON_ADDRESS` still selects the daemon sidecar. Missing fx
still uses the demo timer. Available Claude is one-shot
`claude -p --output-format stream-json --verbose
--include-partial-messages --forward-subagent-text` (not ACP; later
Sends pass documented `--resume {fx_session_id}` when that field is
non-empty; first Send and Fork omit it; not `--continue`; documented
image path inside that `-p` prompt when a composer image is attached;
stdout is NDJSON with live `text_delta` into the transcript; live
Subagent Background from real `parent_tool_use_id`; live Monitor
Background from real Claude `Monitor` `tool_use`, with a bounded
512KB last-window log from matching user `tool_result` (newlines
kept; CSI stripped for display; Environment Summary stays a
one-line preview). Available
Codex is
one-shot `codex exec {prompt}` (not ACP; documented `--image {path}`
after the prompt when a composer image is attached). Available Amp is
one-shot `amp -x {prompt}` (not ACP; documented `@{path}` in the `-x`
prompt when a composer image is attached). Available Pi is one-shot
`pi --mode json {prompt}`
(not ACP, not `--mode rpc`; documented `@{path}` after json when a
composer image is attached; stdout is JSON events with live
`text_delta` into the transcript). Unavailable cursor / opencode / grok / claude / codex /
amp / pi stay demo.
Apply on Settings →
Providers sets `session.provider`. fx missing copies the verified
install command; fx available copies `fx login`. Other missing CLIs
get a PATH hint. Not OAuth or auto-install.

Probe (boot `init_fx`, or first Send): `~/.local/bin/fx --help`, then
`fx --help` on PATH. New sessions default to fx.

## Local session store

Sessions persist on disk beside the app. This is **not** the Waku
daemon and does not open a WebSocket. Native has no daemon/WebSocket
client; the store is a local JSON document that follows Waku's catalog
/ hydrate / merge-only save rules.

Path (Native `app_dirs` data directory, app name `faku`):

    Linux:  $XDG_DATA_HOME/faku/sessions.json  or  ~/.local/share/faku/sessions.json
    macOS:  ~/Library/Application Support/faku/sessions.json

Missing `sessions.json` keeps the two first-run demo sessions. Save is
merge-only; `RemoveSession` is the only delete. New untitled sessions
are not written until they have real content.

## Scope

Ready: desktop shell, demo sessions + timer fallback, one-shot `fx acp`
when the CLI is present (via `acp-proxy`, which auto-answers
`session/request_permission`), first-cut live Send for probed ACP
stdio providers (cursor / OpenCode `acp`, grok `agent stdio`),
first-cut live Send for Available Claude via official print-mode
stream-json (`claude -p --output-format stream-json --verbose
--include-partial-messages --forward-subagent-text`; later Sends pass
documented `--resume {fx_session_id}` when that field is non-empty;
first Send and Fork omit it; stdout is parsed as NDJSON — live
`text_delta` into the assistant turn, not a dump of raw JSON;
non-empty `parent_tool_use_id` does not append into that turn;
documented image path in the `-p` prompt when a composer
image is attached), first-cut live Send for Available Codex via official
non-interactive `codex exec {prompt}` (stdout is the same non-ACP
fx line path; not ACP; documented `--image {path}` after the prompt
when a composer image is attached), first-cut live Send for Available Amp via
official execute mode (`amp -x {prompt}`; stdout is the same
non-ACP fx line path; not ACP; documented `@{path}` in the `-x`
prompt when a composer image is attached), first-cut live Send for Available
Pi via official JSON event-stream mode (`pi --mode json {prompt}`;
stdout is parsed as JSON lines — live `text_delta` into the
assistant turn, not a dump of raw JSON or print-mode prose; not ACP;
documented `@{path}` after json when a composer image is attached),
`fx ask --image` / `fx ask` fallback, local session catalog + hydrate,
waku-protocol v4 JSON builders + server-frame parser, one-shot daemon
sidecar, provider id `"fx"`, Environment Summary Background kind
chrome (Process / Monitor / Subagent labels) with Process rows from
window-side stream/settle, live Monitor rows from real Claude
`Monitor` `tool_use` plus a first-cut Waku-sized 512KB last-window
log in the right-panel Background surface from matching user
`tool_result` (runtime-only; newlines kept; CSI stripped for
display; Environment Summary stays a one-line preview),
live Subagent rows from real Claude
`parent_tool_use_id` / Agent `tool_use` signals while streaming, and a
first-cut right-panel Background surface (kind / title / live-or-settled
status / Monitor log / Stop when the selected row is a live Process,
live Monitor, or live Subagent) opened from those rows. Live Monitor
and Subagent Stop is Faku-side dismiss of that row on one-shot
`claude -p` (not Claude TaskStop mid-turn).

Later: Pi ACP / `--mode rpc`, Claude ACP, `--continue`,
full onboarding / OAuth / auto-install, a long-lived daemon socket in
the update loop
(not this cut), a long-lived ACP loop once a window-side stdin-write
effect exists, Claude CLI TaskStop,
daemon `refreshBackgroundWork`, full BackgroundWorkRegistry, 100ms
render cache.

No `listSessions` / `createSession`. Catalog is `loadTaskState` (local
JSON today). New session is a client-built session saved after first
content.

## Run

Install the Native CLI globally, then from this directory:

    native test --yes
    native dev --yes
    native check
    native build

## License

GPL-3.0-only for this Waku-inspired client. Not a verbatim copy of
Waku's Rust or TypeScript sources. Native SDK and Vercel fx are
Apache-2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
