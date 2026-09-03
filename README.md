# Faku

A Native SDK Zig desktop for local coding agents. Faku is the window;
[fx](https://github.com/keejkrej/fx) is the default agent; waku-daemon
can stay the brain.

## Why

Egoist asked for a Zig GPUI slopfork so Waku compiles faster and uses
less disk:
https://x.com/localhost_5173/status/2090464458695192842

Faku answers that with Vercel Native (markup + Zig Model / Msg / update)
and an **fx-first** default: the fx fork from [keejkrej/fx](https://github.com/keejkrej/fx),
not stock [vercel-labs/fx](https://github.com/vercel-labs/fx) and not
`curl | bash` from fx.sh.

Chrome is a chromeless 48px header, measured sidebar, and 26px send
circle. Local `sessions.json` is canonical. Sidecars are one-shot
(Native spawn writes one stdin buffer, then closes stdin). Zero-config
Native app — no `build.zig`.

No Vercel Gateway required: `fx login grok`, `fx login codex`, or any
OpenAI-compatible `/v1/chat/completions` server.

## Install Faku

Clone and run with the Native CLI:

```bash
git clone https://github.com/keejkrej/faku.git
cd faku
native dev --yes
```

`native build` produces a binary. Need the Native CLI?
`npm install -g @native-sdk/cli`. Push a `v*` tag to publish a GitHub
Release (unsigned macOS DMG, amd64 `.deb`, silent NSIS `.exe`; no zip;
no live `v0.1.0` tag yet — see GitHub Releases below).

## Install fx

Faku probes `$HOME/.fx/bin/fx`, then PATH `fx`. Install the keejkrej/fx fork
from GitHub Releases. Default dir is `~/.fx/bin` — put it on PATH
ahead of any fx.sh install. Binary name stays `fx`.

Unix:

```bash
curl -fsSL https://github.com/keejkrej/fx/releases/latest/download/install | bash
```

Windows PowerShell:

```powershell
irm https://github.com/keejkrej/fx/releases/latest/download/install.ps1 | iex
```

Optional tarball fallback (linux/macos; swap arch: `linux-aarch64`,
`macos-x86_64`, `macos-aarch64`):

```bash
mkdir -p "$HOME/.fx/bin" && curl -fsSL -o /tmp/fx.tgz https://github.com/keejkrej/fx/releases/latest/download/fx-linux-x86_64.tar.gz && tar -xzf /tmp/fx.tgz -C /tmp && install -m 0755 /tmp/fx "$HOME/.fx/bin/fx"
```

Then:

```bash
fx login grok    # or: fx login codex
```

Or set `FX_OPENAI_BASE_URL` and `FX_OPENAI_API_KEY` for an
OpenAI-compatible endpoint. Gateway `fx login` is optional.

Build from source: clone https://github.com/keejkrej/fx, Zig 0.16.0,
`zig build -Doptimize=ReleaseSafe` → `zig-out/bin/fx`.

## What works

- Desktop chrome and local `sessions.json` (not the daemon)
- One-shot Send via `fx acp` (acp-proxy) when fx is installed
- Other probed providers when their CLIs are on PATH
- Demo fallback if fx is missing

Protocol dump: [CONTEXT.md](CONTEXT.md).

## Dev

```bash
native check
native test --yes
```

Agent wayfinding: [AGENTS.md](AGENTS.md).

Host-native packaging uses the same documented verbs CI does
(`native build` then `native package --target macos|linux|windows`).
Do not eject.

### GitHub Releases

Desktop installers for macOS, Linux, and Windows are built by
[`.github/workflows/release.yml`](.github/workflows/release.yml).
Set `version` in both `app.json` and `app.zon` to the same value as
the `v*` tag, then push the tag:

    git tag v0.1.0
    git push origin v0.1.0

`workflow_dispatch` still uploads Actions artifacts. A GitHub Release
is created only for a `v*` tag, or when dispatch is given that tag.

Honest about this cut:

- User-facing assets are an unsigned macOS `.dmg`, a Debian `.deb`
  (amd64, Debian/Ubuntu), and a silent NSIS `.exe`. No zip.
  Fedora/Arch and other distros compile with Native CLI.
- macOS CI builds are unsigned (`native package --signing none`).
  There is no Apple identity and no notarize in CI.
- Linux `.deb` wraps Native's documented FHS install tree (`bin/`,
  `.desktop`, hicolor icons) with prefix `/usr`. `--archive` is a
  macOS DMG, not a Linux tarball.
- Windows is a silent NSIS installer wrapping Native's early
  directory packaging (exe + ico + assets). Unsigned (SmartScreen).
  Double-click installs with no wizard. Not MSI.
- iOS and Android are experimental Native hosts and not a Faku
  desktop product. They are not packaged here.

## License

GPL-3.0-only for this Waku-inspired client. Not a verbatim copy of
Waku's Rust or TypeScript sources. Native SDK and fx are Apache-2.0.
See [LICENSE](LICENSE) and [NOTICE](NOTICE).
