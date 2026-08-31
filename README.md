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
`claude -p --output-format text` (not ACP). Available Codex is
one-shot `codex exec {prompt}` (not ACP). Amp / Pi and unavailable
cursor / opencode / grok / claude / codex stay demo.
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
first-cut live Send for Available Claude via official print mode
(`claude -p --output-format text`; stdout is the non-ACP fx line
path), first-cut live Send for Available Codex via official
non-interactive `codex exec {prompt}` (stdout is the same non-ACP
fx line path; not ACP),
`fx ask --image` / `fx ask` fallback, local session catalog + hydrate,
waku-protocol v4 JSON builders + server-frame parser, one-shot daemon
sidecar, provider id `"fx"`.

Later: Amp / Pi native drivers, Claude image attach / ACP /
stream-json, Codex image attach, full onboarding /
OAuth / auto-install, a long-lived daemon socket in the update loop
(not this cut), a long-lived ACP loop once a window-side stdin-write
effect exists.

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
