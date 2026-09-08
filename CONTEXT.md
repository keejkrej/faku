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
| **workspace** | Session workspace kind. `local` (default; omitted from `sessions.json`) is the ordinary `project_path` checkout. `newWorktree` is a composer draft until Send — it does not spawn `git worktree add` yet. `worktree` is `{path, branch}` after Send materializes that dest and retargets `project_path`. Composer **Work in**. Optional Base for `newWorktree` persists camelCase `baseBranch` (Waku `SessionWorkspace::NewWorktree { base_branch }`; omitted when empty) and keeps the runtime New worktree… picker (`git_worktree_base_override_*`) in sync. Fork copies `project_path` (including a materialized dest) and resets kind to `local`. First-cut daemon `WorkspaceOperation::CreateWorktree` is a best-effort sidecar on Send when a daemon address is set; no address keeps local `git worktree add`. |
| **access_mode** | Stored Waku runtime mode. Maps onto fx `ask` / `code` (ACP) and `FX_PERMISSION_MODE` (`ask` / `auto` / `yolo`). New sessions default to Waku `fullAccess`. |
| **loadTaskState** | Catalog fill. Local JSON today. Daemon `loadTaskState` is only a first-run fill when the local catalog is missing. |
| **saveTaskState** | Best-effort daemon mirror of one started-session skeleton. Does not replace the local catalog. |
| **hydrateSession** | Daemon transcript fill when the local transcript is empty. Local turns win. |
| **argv slot** | Every flag and operand is its own spawn argument. Never interpolate into the chdir `-c` script. |
| **right panel** | First-cut Files + Diff + Browser + Terminal + Background pane to the right of the conversation. Default closed. Browser and Terminal are honest OS-open workarounds (system browser / host terminal), not an embedded webview or PTY. |
| **Settings Providers** | Settings page listing `protocol.ProviderId` catalog rows. fx probe status is live (`fx_available` / `fxPath()`); other ids `--help`-probe PATH `defaultBinary()` (Available / Not found). Apply sets the selected session's `provider`. First-cut Enable/Disable persists `disabled_providers` (wire names) on `sessions.json` extras (default empty = all enabled; Enable/Disable chip is disable-flag-only; `providerEnabled` is `!disabled && isAvailable`; boot starts non-fx PATH `--help` probes alongside fx). Live Send for probed ACP stdio providers (cursor / opencode / kimi `acp`, grok `agent stdio`) uses the same one-shot acp-proxy as fx (first-cut official ACP v1 image content blocks on `session/prompt` when a composer image is attached: base64 + mimeType, ~256KB raw, fail-closed on overflow / bad file; fx still `fx ask --image`, no ACP image blocks); Available Claude is one-shot `claude -p --output-format stream-json --verbose --include-partial-messages --forward-subagent-text` (not ACP; later Sends pass documented `--resume {fx_session_id}` when that field is non-empty; first Send and Fork omit it; not `--continue`; documented image path inside that `-p` prompt when a composer image is attached; stdout is NDJSON with live `text_delta`; live Subagent Background from `parent_tool_use_id` plus a bounded 512KB last-window from forwarded `parent_tool_use_id` text (Environment Summary stays a one-line preview; right-panel Background shows the stored log with CSI stripped for display); live Monitor Background from Claude `Monitor` `tool_use` plus a bounded 512KB last-window log from matching user `tool_result` (Environment Summary stays a one-line preview; right-panel Background shows the stored log with CSI stripped for display); first-cut settled Monitor / Subagent stay in the runtime registry after the turn (status from Process settle; Monitor / Subagent last-window kept; Faku-side Dismiss, not Claude TaskStop; not live / Running / Monitoring after `-p` exits); Available Codex is one-shot `codex exec {prompt}` (not ACP; documented `--image {path}` after the prompt when a composer image is attached); Available Amp is one-shot `amp -x {prompt}` (not ACP; documented `@{path}` in the `-x` prompt when a composer image is attached); Available Pi is one-shot `pi --mode json {prompt}` (not ACP, not `--mode rpc`; documented `@{path}` after json when a composer image is attached; stdout is JSON events with live `text_delta`). fx Not found copies the verified keejkrej/fx Unix install script (`curl -fsSL https://github.com/keejkrej/fx/releases/latest/download/install | bash` into `~/.fx/bin`; not fx.sh); fx Available copies `fx login` (convenience; `--help` is not auth). Other missing CLIs get a PATH hint only. Not Waku onboarding / OAuth / auto-install. |
| **Settings Appearance** | Settings page for chrome theme and language. Theme: System (follow OS `on_appearance`), Light, or Dark. Default System. Language: System / English / 简体中文 / 日本語. Default System. System language follows process `LC_ALL` / `LC_MESSAGES` / `LANG` (Native has no locale API). Explicit language chips are autonyms in every locale. Persists `theme_preference` and `language_preference` on `sessions.json` extras (same bag as model/access/effort/project/daemon). Missing / unknown → System. High contrast / reduce motion still follow the OS. Settings chrome strings (title, nav, Appearance Theme / Language), first-cut sidebar date-bucket titles, and the chrome unassign Today list-item follow the resolved locale this cut. |
| **Settings Skills** | Settings page that scans project `SKILL.md` files. Runtime-only. Composer `$name` insert; not body auto-prepend and not enable toggles. |
| **Settings Usage** | Settings page showing the selected session's local context window (`context_used` / `context_size` from ACP `usage_update`) and thread-goal tokens (`threadGoalUsageLabel`), plus first-cut Daily / Monthly / Projects chrome and a Daily / Projects window selector (7 / 30 / 90 days, this month, last month; default `trailingDays: 30`). Daemon `LoadUsageHistory` is a best-effort one-shot when `WAKU_DAEMON_ADDRESS` or persisted `last_daemon_address` is set (Daily / Projects use the selected window; Monthly requests `months: 12` and hides the selector). Daily paints per-provider share bars (`costShare` / `tokenShare`, or computed from totals) with a runtime-only Cost | Tokens metric chip (default Cost) and a Daily-only Model | Days breakdown chip (default Model, matching Waku `breakdown === 'model'`). Model paints model share bars (provider label + model name; Cost prefers wire `costShare`, Tokens always computed from `totalTokens` / history totals — ModelSlice has no `tokenShare`); a compact per-MTok hint appends when the Faku-side LiteLLM rate table hits (unpriceable names stay unpriced). Days keeps a first-cut layered Native `<chart>` of the painted window (oldest-first Claude/Codex `kind="area"` series from a shared zero baseline for the active Cost|Tokens metric, not stacked offsets; `y-max` pins to the max finite single-provider-day sample when that peak is > 0, else Native auto-domain; documented `stroke-width` 2; paint-order by period total paints the smaller series first so the larger fill sits on top, ties keep Claude then Codex; empty `daily[]` hides the chart; still not Waku GPUI / T3 canvas: no curve smoothing, no 12% fill opacity) plus first-cut nested Claude/Codex Native `<progress>` rows from `daily[].byProvider` (share within that day's Cost|Tokens total; empty/missing/short `byProvider` stays day-total-only; chip flip recomputes nested shares from the cached snapshot). Empty `models` paints no model rows. Daily, Monthly, and Projects paint a first-cut five-tile Native metric strip (processed tokens / cached input / uncached input / output / cache savings) when history is painted, including zeros (Daily / Projects: active-day averages from `daily[]`; Monthly: active-month averages from `months[]`). Provider bars, Cost quality, notices, and the scan footer stay on Daily regardless of the breakdown chip. Monthly keeps a first-cut layered Native `<chart>` of the painted window (oldest-first Claude/Codex `kind="area"` series from a shared zero baseline for the active Cost|Tokens metric, not stacked offsets; `y-max` pins to the max finite single-provider-month sample when that peak is > 0, else Native auto-domain; documented `stroke-width` 2; paint-order by period total paints the smaller series first so the larger fill sits on top, ties keep Claude then Codex; empty `months[]` hides the chart; still not Waku GPUI / T3 canvas: no curve smoothing, no 12% fill opacity) plus first-cut relative bars vs the max month in the window for that same Cost | Tokens chip (chip flip recomputes from the cached months snapshot; zero months stay text-only) plus first-cut nested Claude/Codex Native `<progress>` rows from `months[].byProvider` (share within that month's Cost|Tokens total; empty/missing/short `byProvider` stays month-total-only; chip flip recomputes nested shares from the cached snapshot). Projects paints a first-cut layered Native `<chart>` of the **visible** filtered set (Claude/Codex `kind="area"` series from a shared zero baseline for the active Cost|Tokens metric, not stacked offsets; `y-max` pins to the max finite single-provider-project sample among visible rows when that peak is > 0, else Native auto-domain; documented `stroke-width` 2; paint-order by period total over the visible set paints the smaller series first so the larger fill sits on top, ties keep Claude then Codex; empty visible set / empty `projects[]` hides the chart; still not Waku GPUI / T3 canvas: no curve smoothing, no 12% fill opacity) plus first-cut relative bars vs the max Cost|Tokens among **visible** filtered rows for that same chip (runtime-only `usage_project_filter`; case-insensitive contains on basename or full path; empty shows all; chip flip recomputes from the cached projects snapshot and respects the filter; zero-value rows stay text-only; no-match is distinct from no project usage; not persisted) plus first-cut nested Claude/Codex Native `<progress>` rows from `projects[].byProvider` on visible rows (share within that project's Cost|Tokens total; empty/missing/short `byProvider` stays project-total-only; chip flip recomputes nested shares from the cached snapshot). Unknown-command / parse / overflow keep the local session cards. Daily paints a first-cut Cost quality panel from daemon `quality` (Provider reported / Model priced / Unpriced percents + Cache savings USD) and muted notices when `errors` are non-empty or `pricing` is `unavailable`, plus a muted Faku-side LiteLLM rates status (`Rates fresh` / `Rates cached` / `Rates unavailable`) when history is painted. First-cut LiteLLM rate-table fetch ships (one-shot `fx.spawn` curl `-o` into the Faku data dir, 24h compact `usage-model-rates.json`, runtime map only). Still not Waku's GPUI / T3 layered / stacked canvas chart, not a local transcript scan. Settings Usage context card still hides until `context_size > 0`. |
| **Usage meter** | First-cut composer footer meter (Native `<progress>`, not a circular GPUI gauge). Visible whenever a session is selected, including an empty bar when nothing is measured yet. Opens a panel with local context occupancy plus, for Claude / Codex / OpenCode / Grok, plan rate-limit lanes from daemon `FetchPlanUsage` (`fetchPlanUsage` → `planUsage`). One-shot sidecar when a daemon address is set. Runtime-only first-cut per-provider plan_usage map (four slots: Claude / Codex / OpenCode / Grok; not a HashMap). Switching session/provider shows that slot immediately (cached snapshot, unconfigured, or errored) and does not clear the others. `checked_at` / `stale` / `pending_key` are per provider. First-cut Waku refresh cadence piggybacks `now_ms` / the update tick (`maybeRefresh` loops all four: 300s idle, 600s Grok, 30s stale after panel open / turn settle, 90s retry on fetch error; at most one in-flight sidecar per provider; skip when `!providerEnabled && selectedProvider != provider` — `providerEnabled` is `!disabled && isAvailable`; boot starts non-fx CLI `--help` probes; Enable/Disable chip is still disable-flag-only; open / Refresh stay immediate for the selected provider only, including a disabled or not-yet-Available selected id). fx / cursor / amp / pi / kimi stay context-only. Still not a circular GPUI gauge. LiteLLM rate-table fetch ships on Settings Usage, not on this meter. |
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

Session `workspace` on `sessions.json` is omitted when `local`. A
`newWorktree` skeleton is `{"kind":"newWorktree"}`, or
`{"kind":"newWorktree","baseBranch":"…"}` when Work-in Base is
set (camelCase; omitted when empty). After Send prep
succeeds it is `{"kind":"worktree","path":"…","branch":"…"}`.
Composer **Work in** (Local / New worktree) is draft-only until
Send; the branch-menu **New worktree…** immediate create path is
separate. Send on `newWorktree` queues the prompt, shows Creating
worktree…, and reuses the existing `git worktree add` spawn /
retry / candidate path when no daemon address is set. When
`WAKU_DAEMON_ADDRESS` or persisted `last_daemon_address` is set,
Send prefers hello + daemon `WorkspaceOperation::CreateWorktree`
(ok is `worktreeCreated` path + branch; Native 4 KiB stdin
overflow falls back to local git). Success retargets
`project_path` then `startPrompt`. Failure leaves `newWorktree`
and does not start the provider. Base for that draft persists
`baseBranch` and stays in sync with `git_worktree_base_override_*`.

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
`steer`, `cancel`, `goal`, `workspace`, `closeSession`, `loadUsageHistory`,
`refreshBackgroundWork`, `stopBackgroundWork`. Start defaults to provider
`fx`. fx-first (`fx acp` / `fx ask` / demo) does not use daemon hello.
First-cut `workspace` ships Push, CreateWorktree, Commit,
InspectBranches, CheckoutBranch, InspectCommit, CaptureTurnStart,
CaptureTurn, GenerateCommitMessage, ListTree, CollectReviewDiff,
BrowseDirectory, ReadTextFile, WriteTextFile, CopySessionRefs,
DeleteSessionRefs, HasRef, CaptureRef, RestoreRef, DeleteRef,
DeleteTurnRefsAfter, SessionTurnRefs, ListProjectFiles,
DiscoverSlashCommands, CreateProjectlessWorkspace, and
MigrateProjectlessWorkspace.

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
- `SpawnOptions` has no `cwd` field. `fx ask` and Unix git probes chdir via
  `/bin/sh -c 'cd -- "$1" && shift && exec "$@"'`. `PWD` is not used.
  Windows `file_mention` uses documented `git.exe -C <project_path>` and a
  PowerShell walk with `-Args` / `$args[0]` so the path stays its own argv
  slot (not interpolated into `-Command`). Composer git_branch / git_dirty /
  git_ahead_behind / git_remotes / git_toplevel / git_common_dir / git_commit / git_checkout / review_diff use the same `git.exe -C` pattern (no
  PowerShell except New worktree…, git_numstat untracked, empty-message
  `fx ask` generate, and Environment Compare Uncommitted numstat). git_commit add / cached-quiet preflight / commit / amend and
  CommitSnapshot (tracked / cached) use `git.exe -C`; empty-message `fx ask`
  generate is `powershell.exe -NoProfile -Command {scriptblock} -Args`
  cwd, fx path, prompt (`$args[0]` / `$args[1]` / `$args[2]`; documented
  `ask --no-save --auto --json --` literals stay in the scriptblock).
  git_numstat on Windows is `powershell.exe
  -NoProfile -Command {scriptblock} -Args <project_path>` (`$args[0]`;
  tracked `git.exe diff --numstat HEAD --` plus untracked synthetic
  `N\t0\tpath` rows). Review Uncommitted numstat is the same
  PowerShell `-Command` + `-Args` shape with a distinct script body
  (`git.exe diff --numstat HEAD` plus synthetic `N\t0\tpath`; no
  binary / 1MiB / zero-line filters). Untracked `?` hunks are
  `git.exe -C PATH diff --no-index -- NUL <path>`. git_common_dir resolve
  treats Unix `/…` and Windows `X:\…` / `X:/…` as absolute and stores `/`
  separators so nest FNV matches. git_checkout list / checkout / track /
  create / delete / fetch / push / first-push / worktree-base use `git.exe -C`;
  New worktree… is `powershell.exe -NoProfile -Command {scriptblock} -Args`
  with parent, cwd, git.exe, flags, branch, dest, and optional base as argv
  slots.
- No Native git effect. Git is sidecar `fx.spawn` of `git`.
- No `fx.pickFile` / file-open effect. Folder and image pickers are OS
  sidecars. Cmd/Ctrl-O is selected-session Pick folder (`project_path`),
  not Waku's Project catalog; Cmd/Ctrl-N stays New Task.
- No `fx.revealPath`. Reveal folder is `open` / `xdg-open` / Windows
  `explorer.exe PATH`.
- No `fx.maximizeWindow`. Maximize is an OS zoom sidecar.
- No window-focus observation, caret API, PTY, FS watcher, or debounce
  timer.

Every git flag and operand is its own **argv slot**. Never interpolate
user strings into the chdir `-c` script or a PowerShell `-Command` body.

## Sidecar git

Composer project-row git (branch, checkout, commit, push, fetch,
worktree, dirty / numstat / ahead-behind) and Environment Compare are
one-shot `git` spawns. Runtime-only labels are not stored on
`sessions.json`. This is not Waku's daemon `InspectBranches` live
watch, not `{project_id}` UUID nesting. First-cut composer Force
push ships (runtime-only ghost toggle on Push… confirm and
Commit…; default off; reset when those cards open; not persisted;
`--force` its own argv slot after `push`). First-cut daemon
`WorkspaceOperation::Push` ships (best-effort sidecar when
`WAKU_DAEMON_ADDRESS` or persisted `last_daemon_address` is set;
Force stays local `git push --force` / set-upstream force). First-cut
daemon `WorkspaceOperation::CreateWorktree` ships on Send prep for
a `newWorktree` draft when a daemon address is set (Force / Amend
are irrelevant; Native 4 KiB stdin overflow falls back to local
`git worktree add`; no address keeps today's local path). First-cut
daemon `WorkspaceOperation::Commit` ships on Commit… when a daemon
address is set (Amend and Force+Commit and Push stay local git;
no address keeps today's local add/preflight/commit). First-cut
daemon `WorkspaceOperation::InspectBranches` ships on the composer
branch-list picker when a daemon address is set (ok is nested
`branches` + snake_case snapshot; local heads from that snapshot
are the source of truth for heads/current/occupied; a follow-up
local `git for-each-ref` merges remote-tracking rows the same as
the no-daemon path; Native 4 KiB stdin overflow / error /
null snapshot falls back to local `git for-each-ref`; not a live
watch). The open picker filters listed names with a runtime-only
case-insensitive substring (empty query shows every row; not
persisted to sessions.json). First-cut daemon `WorkspaceOperation::CheckoutBranch` ships
on picker local-head checkout (`create: false`) and New branch
create (`create: true`) when a daemon address is set (ok is nested
`branchChanged` + snake_case snapshot; Native 4 KiB stdin overflow
falls back to local `git checkout` / `git checkout -b`; remote
`--track` stays local git; no address keeps today's local path).
First-cut daemon `WorkspaceOperation::InspectCommit` ships on
Commit… open / include-unstaged re-probe when a daemon address is
set (ok is nested `commitSnapshot` + snake_case snapshot; paints
the card from `additions`/`deletions` or `staged_*` when
include-unstaged is off; Native 4 KiB stdin overflow / error /
unusable snapshot falls back to local numstat; no address keeps
today's local path). First-cut daemon
`WorkspaceOperation::GenerateCommitMessage` ships on empty-message
Commit… generate when a daemon address is set (ok is nested
`commitMessage` + `message`; fills the normalized subject then
auto-proceeds; Native 4 KiB stdin overflow / error / empty /
parse miss falls back to local `fx ask`; no address keeps today's
local path). First-cut daemon
`WorkspaceOperation::ListProjectFiles` ships on composer `@` / Files
refresh when a daemon address is set (ok is nested `projectFiles`
+ `{ path, is_dir }` FileEntry rows; paints the same file-mention
cache from files + trailing-slash dir sentinels; Native 4 KiB
stdin overflow / error / unusable parse falls back to ListTree
then local `git ls-files` then walk; no address keeps today's
local path). First-cut daemon
`WorkspaceOperation::DiscoverSlashCommands` ships on composer `/`
slash-prefix / session or provider change when a daemon address is
set and the selected session has a usable non-empty `project_path`
(ok is nested `slashCommands` + `{ name, description, scope,
argument_hint, template }` rows; paints the same
`session.available_commands` list ACP `available_commands_update`
already paints; Native 4 KiB stdin overflow / error / empty /
unusable parse keep today's ACP-only catalog and must not clear a
good ACP list; later live ACP replace/wins; no address keeps
today's ACP path). First-cut daemon
`WorkspaceOperation::CreateProjectlessWorkspace` ships on New Task
when there is no ordinary project (empty `last_project_path`, or
the selected session's `project_path` is already a projectless path
under `~/.waku/projects` / legacy `~/.waku/<date>/…`) and a daemon
address is set (ok is nested `projectlessWorkspace` + `cwd`; paints
the new session `project_path` and `last_project_path`; Native 4 KiB
stdin overflow / error / unusable parse / empty cwd fall back to
local mkdir under `~/.waku/projects/<YYYY-MM-DD>/<slug>` with
`new-chat` for a null prompt; no address keeps that local mkdir;
home/`~/.waku/projects` failure keeps today's empty/copied
`last_project_path`). First-cut daemon
`WorkspaceOperation::MigrateProjectlessWorkspace` ships on session
select / boot when the selected session's `project_path` still
needs migration (legacy projectless, not under `~/.waku/projects` —
dated `~/.waku/<date>/<slug>` or bare `~/.waku`) and a daemon
address is set (ok is nested `projectlessWorkspace` + `cwd`; paints
that session `project_path` and `last_project_path`; Native 4 KiB
stdin overflow / error / unusable parse / empty cwd fall back to
local rename into `~/.waku/projects/<date>/<slug>` with numbered
`-2`… if taken, or a fresh mkdir like Create when the path is bare
`~/.waku`; already-under-projects is a no-op; no address keeps that
local fallback; home/failure must not toast-block session select).
Ordinary real project paths do not spawn migrate. First-cut daemon
`WorkspaceOperation::ListTree` ships on Files expand after a
daemon fill when a daemon address is set (ok is nested
`workingTree` + camelCase `WorkingTreeEntry` rows; paints the
Files cache from file entries; expand after a daemon fill
re-prefers ListTree; Native 4 KiB stdin overflow / error /
unusable parse falls back to local `git ls-files` then walk; no
address keeps today's local path). First-cut daemon
`WorkspaceOperation::CollectReviewDiff` ships on Review / Diff
open / refresh / source-switch when a daemon address is set (ok is
nested `reviewDiff` + camelCase `ReviewDiffData`; paints the file
list from `numstat` (per-file `+N` / `-M` when those counts are
non-zero) and selected hunk from `patch` (Gap rows; local numstat
paints the same counts; LastTurn stays
local; Native 4 KiB stdin overflow / error / unusable parse falls
back to local numstat + hunk probes; no address keeps today's
local path). First-cut daemon
`WorkspaceOperation::BrowseDirectory` ships on Pick folder (or Cmd/Ctrl-O;
Cmd/Ctrl-N stays New Task) when a
daemon address is set (ok is nested `directory` + camelCase `path` /
`parent` / `home` / `filesystemRoot` / `WorkingTreeEntry` rows;
paints a first-cut in-app directory browser from `entries`; Choose
sets `project_path` on the selected session (not Waku's Project catalog);
Native 4 KiB stdin overflow / error / unusable
parse falls back to the local OS folder dialog; no address keeps
today's OS path). First-cut daemon
`WorkspaceOperation::ReadTextFile` ships on Files preview load
(select / Reload) when a daemon address is set (ok is nested
`textFile` + `content`; Native 4 KiB stdin overflow / error /
unusable parse falls back to local `readFileAlloc`; no address
keeps today's local path). First-cut daemon
`WorkspaceOperation::WriteTextFile` ships on Files preview Save
when a daemon address is set (ok is workspace Ack; Native 4 KiB
stdin overflow / spawn failure / non-ok / non-ack / unusable parse
falls back to local atomic write; truncated / binary / gated
refuse stay local; Open-in-editor stays local; no address keeps
today's local path). First-cut daemon
`WorkspaceOperation::CaptureTurnStart` ships on Send after local
`fork.recordRewindRefIfPossible` when a daemon address is set
(best-effort sidecar; ok is workspace Ack; local
`worktree_snapshot_sha` / `refs/faku/...` stay canonical; Native
4 KiB stdin overflow / sidecar failure must not break Send or
clear the local sha; no address keeps today's local-only path).
First-cut daemon `WorkspaceOperation::CaptureTurn` ships after
successful local finish-time capture
(`fork.recordTurnEndIfPossible`) when a daemon address is set
(best-effort sidecar; ok is nested `WorkspaceResult::Checkpoint`;
local `worktree_turn_end_sha` / `worktree_turn_diff_sha` /
`refs/faku/...` stay canonical; daemon Checkpoint must not
replace those; Native 4 KiB stdin overflow / sidecar failure / no
address leave local alone).
First-cut daemon `WorkspaceOperation::CopySessionRefs` ships after
a local `sessions.json` fork (`fork.forkSelectedThrough`) when a
daemon address is set (best-effort sidecar; ok is workspace Ack;
local fork / `refs/faku/...` stay canonical; Native 4 KiB stdin
overflow / sidecar failure / no address leave the local fork
alone).
First-cut daemon `WorkspaceOperation::DeleteSessionRefs` ships after
a local `sessions.json` remove (`store.removeIfPossible`) when a
daemon address is set (best-effort sidecar; ok is workspace Ack;
local catalog remove / `closeSession` stay canonical; Native 4 KiB
stdin overflow / sidecar failure / no address leave the local
remove alone).
First-cut daemon `WorkspaceOperation::HasRef` ships on Send after
local turn-start capture when a daemon address is set (prefer hello
+ hasRef for the baseline check that otherwise calls local
`checkpoint.hasFakuRef`; snake_case `git_ref`; ok is nested
`WorkspaceResult::Bool`; Native 4 KiB stdin overflow / miss /
non-bool / error fall back to local `hasFakuRef`; no address keeps
today's local path; spawn only when cwd is a git worktree).
First-cut daemon `WorkspaceOperation::CaptureRef` ships after a
successful local `refs/faku` `update-ref` (`checkpoint.updateFakuRef`
and the fork Send / finish capture path) when a daemon address is
set (best-effort sidecar; snake_case `git_ref`; ok is workspace
Ack; local refs stay canonical; Native 4 KiB stdin overflow /
sidecar failure / miss / non-ack leave local refs alone with no
rollback; no address keeps today's local-only path; spawn only
when cwd is a git worktree).
First-cut daemon `WorkspaceOperation::RestoreRef` ships on Header
Rewind when a daemon address is set and cwd is a git worktree
(prefer hello + restoreRef for the snapshot being rewound;
snake_case `git_ref` is `refs/faku/session-{id}-turn-start-{n}`;
ok is workspace Ack; Native 4 KiB stdin overflow / miss / non-ack
/ error fall back to local `restoreRef(sha)` / `resetHard`; no
address keeps today's local path; spawn only when a snapshot sha
is stored).
First-cut daemon `WorkspaceOperation::DeleteRef` ships after
successful Header Rewind bookkeeping (`completeRewindTranscript`,
both local restore and daemon RestoreRef Ack) when a daemon
address is set and cwd is a git worktree (best-effort sidecar;
snake_case `git_ref` is the same turn-start ref RestoreRef used;
ok is workspace Ack; local `deleteFakuRef` / `git update-ref -d`
runs first; Native 4 KiB stdin overflow / miss / non-ack leave
rewind transcript bookkeeping alone; no address keeps today's
local-only delete).
First-cut daemon `WorkspaceOperation::DeleteTurnRefsAfter` ships
after that same successful Header Rewind bookkeeping when a daemon
address is set and cwd is a git worktree (best-effort sidecar;
snake_case `session_id` / `retained_turn_count` /
`previous_turn_count`; `session_id` is `daemon_proxy.wireUuid`;
Header Rewind of the last prompt uses `previous_turn_count =
turn_n` before `dropLastPromptTurns` and `retained_turn_count =
turn_n - 1` when `turn_n > 0` else 0; ok is workspace Ack; Waku
deletes refs for turns `retained_turn_count+1 ..= previous_turn_count`;
local `deleteFakuRef` + DeleteRef stay; Native 4 KiB stdin overflow /
miss / non-ack leave rewind transcript bookkeeping alone; no
address keeps today's local-only path).
First-cut daemon `WorkspaceOperation::SessionTurnRefs` prefers
hello + `sessionTurnRefs` on session select / boot when a daemon
address is set and cwd is a git worktree (snake_case `session_id`
is `daemon_proxy.wireUuid`; ok is nested `turnRefs.turn_counts`;
empty array is still ok). Local `checkpoint.sessionTurnRefs`
(`git for-each-ref` of `refs/faku/session-{id}-*`, `turn-{n}`
ordinals only) stays the overflow / miss / non-ok / no-address
path and remains canonical. Runtime cache only (not
`sessions.json`). Miss must not break rewind/checkpoint
bookkeeping.
New worktree… first-cut
Base picker ships (listed unoccupied local heads; runtime-only
override on the immediate card; Work-in `newWorktree` persists
camelCase `baseBranch` and keeps `git_worktree_base_override_*`
in sync; default still today's origin/HEAD probe then composer
branch label then omit/HEAD). First-cut defer-until-Send workspace
mode ships (composer Work in Local / New worktree; optional
`baseBranch` persist on that draft; Send queues the prompt, one-shots the same `git worktree add` as New worktree… when no daemon address is set,
retargets `project_path`, then `startPrompt`). Leftovers: amend/force over daemon,
remote `--track` over daemon, etc. Fetch already
`--prune`; there is no prune-alone menu (not in Waku).
Windows probes, checkout / push / worktree, and commit mutations (add / cached-quiet / commit /
amend / CommitSnapshot tracked-cached) use `git.exe -C <project_path>`;
New worktree…, git_numstat untracked rows, empty-message `fx ask` generate, and
Environment Compare Uncommitted numstat use PowerShell `-Command` + `-Args`.
Environment Compare / Review Branch / Staged / Unstaged / Committed / LastTurn
stay `git.exe -C`; Uncommitted untracked `?` rows are PowerShell synthetic
`N\t0\tpath`, and `?` hunks are `git.exe -C … diff --no-index -- NUL <path>`.

Send may snapshot the worktree (`worktree_snapshot_sha` /
`worktree_turn_end_sha` / `worktree_turn_diff_sha`; refs under
`refs/faku/`, not `refs/waku/`). When a daemon address is set, Send
also one-shots hello + daemon `WorkspaceOperation::CaptureTurnStart`
as a best-effort sidecar (Ack; does not replace local capture).
Successful finish also one-shots hello + daemon
`WorkspaceOperation::CaptureTurn` after local end capture
(Checkpoint; does not replace local end / turn-diff shas).
When a daemon address is set, Send also prefers hello + daemon
`WorkspaceOperation::HasRef` for the baseline `hasFakuRef` check
(Bool; overflow / miss / non-bool / error fall back to local
`show-ref --verify`). After a successful local `refs/faku`
`update-ref`, Send / finish also one-shots hello + daemon
`WorkspaceOperation::CaptureRef` when a daemon address is set
(Ack; does not replace or roll back local refs).
Rewind undoes the last turn's files
and those chat turns using the Send-time HEAD / snapshot. When a
daemon address is set and cwd is a git worktree, Rewind prefers
hello + daemon `WorkspaceOperation::RestoreRef` for that
turn-start ref (Ack; overflow / miss / non-ack fall back to local
`restoreRef(sha)` / `resetHard`). After successful Rewind
bookkeeping, a local `deleteFakuRef` drops that turn-start name;
when a daemon address is set, Rewind also one-shots hello + daemon
`WorkspaceOperation::DeleteRef` as a best-effort sidecar (Ack;
does not undo transcript bookkeeping; Faku refs stay
`refs/faku/...`). After that same bookkeeping, Rewind also
one-shots hello + daemon
`WorkspaceOperation::DeleteTurnRefsAfter` as a best-effort range
cleanup (Ack; covers turn / turn-start / turn-diff for
`retained_turn_count+1 ..= previous_turn_count`; does not undo
transcript bookkeeping). When a daemon address is set, session
select / boot prefers hello + daemon
`WorkspaceOperation::SessionTurnRefs` to learn which prompt
ordinals have daemon-side `refs/faku` turn refs (ok nested
`turnRefs.turn_counts`; overflow / miss / non-ok fall back to
local `git for-each-ref`; runtime cache only; miss must not break
rewind/checkpoint bookkeeping). Fork clones
the local transcript into a new `sessions.json` row; it is not a
provider session fork. When a daemon address is set, Fork also
one-shots hello + daemon `WorkspaceOperation::CopySessionRefs`
as a best-effort sidecar (Ack; does not replace the local fork;
Faku refs stay `refs/faku/...`). When a daemon address is set, Remove
also one-shots hello + daemon `WorkspaceOperation::DeleteSessionRefs`
as a best-effort sidecar after the local catalog drop (Ack; does not
replace local remove or `closeSession`). Fork copies `project_path` (including a
materialized worktree dest) and resets workspace kind to `local`;
it does not spawn a second worktree.

## Right panel: Files / Diff / Browser / Terminal / Background

Command palette Show / Hide right panel (or Cmd/Ctrl-Shift-B; Cmd/Ctrl-B stays the sidebar) toggles a first-cut Files +
Diff + Browser + Terminal + Background pane. Default closed. Files tab clamps to Waku file-tree 184 / 140 / 360 when no
inline preview is open. First-cut: the first Files preview open widens the pane with Waku `FILE_EDITOR_INITIAL_WIDTH`
500 (`widenedPanelWidthForFileEditor`: sanitize to RIGHT_PANEL 280–1000, then max with tree+500; measured
`(460, 184) → 684`, already-wide stays) and while that preview is open Files uses the wide panel clamp (min 280 /
max 1000) so the bump does not snap back. Closing the preview keeps the pixel width until the next Files clamp
(hide / Files tab without a preview / persist load). First-cut: opening Diff / Review widens the pane with Waku
`REVIEW_INITIAL_WIDTH` 820 (`widenedPanelWidthForReview`: sanitize to RIGHT_PANEL 280–1000, then max with 820;
measured `460 → 820`, already-wide ≥820 stays). When Diff has a file list and hunk
text or hunk status, the Review body is a nested horizontal split: hunk/content
on the left (grow) and the file list on the right at the same fitted FILE_TREE
width as Files (default 184, clamp 140…min(360, panel−140);
`right_panel_diff_file_list_width` persists on `sessions.json` extras). File-list-only or status/empty
stays a full-height list (no forced empty split). Browser / Terminal / Background bump toward Waku
`DEFAULT_RIGHT_PANEL_WIDTH` 460 when still file-tree-narrow
and clamp from Waku `RIGHT_PANEL_MIN_WIDTH` 280 up to Waku `RIGHT_PANEL_MAX_WIDTH` 1000; switching back to Files without a preview reclamps to 360. Files width persists (`right_panel_open` /
`right_panel_width`). Nested Files-tree width and Diff file-list width persist (`right_panel_file_tree_width` /
`right_panel_diff_file_list_width`, u32 pixels; missing / 0 keep 184 then FILE_TREE clamp). Selected tab persists (`right_panel_tab`: `files` /
`diff` / `browser` / `terminal` / `background`; missing / unknown → Files).
Browser draft URL persists (`browser_url`, raw, cap 2048; missing / empty /
overflow → empty draft). Background row selection, Files preview content,
and directory expands stay runtime-only. Files
lists the same bounded `file_mention` cache used by composer `@`
mentions (git ls-files, then a bounded walk; Windows `git.exe -C` /
PowerShell walk with `-Args`; first-cut daemon
`WorkspaceOperation::ListProjectFiles` prefers hello +
ListProjectFiles when a daemon address is set and falls back to
ListTree then that local path; expand after a daemon fill
re-prefers ListTree; Waku-scale ~50k heap last-window, still not
a Native FS watcher), with a bounded inline preview on file click
(256KB cap, truncated / binary / unreadable honest states; Native
`<code>` highlighting with `line-numbers`; language is a documented
lexer name from the path, unknown / Dockerfile / Makefile /
Cargo.toml → `plain`; Native numbered mode omits the gutter above 128
logical lines but keeps the source; markdown `.md` / `.markdown` adds
a runtime-only Preview | Source chip (default Preview paints Native
`<markdown source>` GFM, Source keeps highlighted `<code>`; http(s)
links reuse `open_url` OS browser spawn; relative / file links are a
muted status; no `images=` this cut; mode resets when the preview
closes / file switches / session clears); first-cut Edit switches a full
text window to `<textarea>`, Save (or Cmd/Ctrl-S when dirty-editing) prefers hello + daemon
`WorkspaceOperation::WriteTextFile` when a daemon address is set
(ok Ack adopts the saved buffer; Native 4 KiB stdin overflow /
sidecar failure / non-ack falls back to Zig `std.fs` atomic
replace), Reload re-reads disk and discards dirty; truncated stays
Open-in-editor + Reload; first-cut live reload via mtime/size poll
on the update tick — still not a real FS watcher / Native watch API;
first-cut Files preview find/replace ships when a preview is open:
Native bar above the body (Find, `n of m` / `0` / capped `m+` / `invalid`,
prev/next, close, case-sensitive toggle, whole-word toggle, regex toggle, Replace row via chevron or
Cmd/Ctrl-Alt-F when Native keyboard exposes `alt`/`option`). Cmd/Ctrl-F
opens that bar instead of transcript find; transcript find paints a muted
Match chip on the current hit's chrome row (not Waku glyph washes);
Cmd/Ctrl-G / Shift-G
navigate file matches while it is active; Enter in the find field is
FindNext via Native `on-submit` (Shift-Enter FindPrevious stays unbound
globally; prev remains the chevron / Cmd-Shift-G); Escape closes it without
Stop. Plain substring with optional ASCII case-sensitivity and
whole-word (`[A-Za-z0-9_]` boundaries) until the `.*` chip is on
(self-contained Zig subset: `.` `^$` `|` greedy `*+?{n,m}` `(…)`
`(?:…)` `[…]` `\d\w\s` `\b`, `$n` replace expand; invalid pattern is
an honest `invalid` count, not a crash or silent fallback). Cap 20000
(Waku FileSearch is 20k). No GPUI match washes. Runtime-only). Diff hosts Environment Compare / Review (Branch,
Uncommitted, Staged, Unstaged, Committed, LastTurn; first-cut daemon
`WorkspaceOperation::CollectReviewDiff` prefers hello + CollectReviewDiff
for those sources except LastTurn when a daemon address is set). Selected-file hunks
parse into HunkHeader / Context / Addition / Deletion / Gap rows (Waku
`review_diff` Gap model: `DEFAULT_EXPANSION_LINE_COUNT` 100, collapse 3 /
threshold 1). Daemon `completeContext` collapses long context into expandable
Gaps; local compact `git diff` inserts count-only Gaps between hunks.
Start / End reveal 100 retained lines, Both up to 200, All the rest
(subject to the Faku render cap). Expand rearranges retained lines in
memory; no new git spawn. Line retain/render cap matches Waku
`MAX_RENDERED_DIFF_LINES` 50_000. Byte cap is a Faku fixed table
(~32 B/line × 50_000; Waku has no byte cap). Native daemon stdout is
still `daemon_line_bytes`. Native paints a `shown_line` gutter and
additions `success`, deletions `destructive`, context/gaps `text_muted`.
Code-row body is Waku `Line.content` (unified-diff marker stripped);
no syntax-token highlighting (Native has no per-span Token). File-list
rows paint a first-cut nested directory tree matching Waku
`review_diff_tree_rows` (collapsible Directory + File, default
collapsed, basename leaves, Native `file-text` icon, colored status
letter `A`/`D`/`B`/`M`/`?` separate from the basename, optional `+N` / `-M` from
numstat; zeros omitted; numstat `-` is Binary `B`; daemon CollectReviewDiff and local
`--numstat`). A Native search-field above that tree is Waku
`right_panel_diff_filter`: runtime-only (not `sessions.json`); trim
+ ascii-lowercase contains on the full path; a non-empty query
auto-expands ancestor directories. Empty / whitespace-only is
today's collapsed tree. Leaving Diff (other tab / panel hide)
clears the filter. First-cut selected-file Diff header chrome ships
above the hunk pane (`file-text` + path + optional `+N` / `-M`, ~36px, outside
Native `<scroll>`, nested-split and stacked hunk layouts). Waku's
scroll-driven sticky overlay (`file_headers_around` / item_ix)
stays Native-blocked (no documented virtualized item index /
absolute sticky-over-scroll API). Browser is an
honest empty: Native has no webview; a persisted URL draft plus
**Open in browser** spawns `open` / `xdg-open` / Windows
`cmd.exe /c start "" <url>` (effect key 25; empty `start` title so
the URL is not eaten; light `http://` / `https://` /
bare-host→`https://` gate). Terminal is an
honest empty: Native has no PTY; **Open in Terminal** reuses the
composer host-terminal sidecar (`open -a Terminal` / `x-terminal-emulator`
else `gnome-terminal` / Windows `wt.exe -d` else
`cmd.exe /c start "" /D <path> cmd.exe`; effect key 27; empty `start`
title so `/D` is not eaten). Background is the
Environment Summary Process / Monitor / Subagent row surface (kind,
title, live-or-settled status, Monitor / Subagent 512KB last-window log). Not an embedded BrowserView or alacritty PTY,
or a full BackgroundWorkRegistry. Faku-side Monitor and Subagent Stop
on one-shot `claude -p` ships (live Stop dismisses that live row;
settled rows offer Dismiss; not Claude TaskStop mid-turn). First-cut
daemon `refreshBackgroundWork` prefers hello + that command when a
daemon address and usable session `runtimeId` are set on Background
tab open/select or Environment Summary open (immediate one-shot
sidecar; Ack plus `backgroundWork` events apply reconcileProcesses /
reconcileLive / upsert / outputDelta / stopFailed into daemon-sourced rows; miss / no runtimeId /
no address keeps local Process / Monitor / Subagent). First-cut 5s
Waku `BACKGROUND_WORK_REFRESH_INTERVAL` tick ships as
`background_work.maybeRefresh` on the existing update / stream tick
(same `now_ms` piggyback as the 100ms output cache; Native has no
dedicated timer; skips when a refresh sidecar is already in flight;
prefers the selected session when it has a usable `runtimeId` and
the Background tab is showing, Environment Summary is open, or that
session has live Process / Monitor / Subagent / daemon-sourced
rows; else one other live session with a usable `runtimeId` and a
daemon address, single in-flight sidecar). First-cut 1s Waku
`BACKGROUND_WORK_TICK_INTERVAL` elapsed duration labels ship as
`environment_summary.maybeTickElapsed` on that same update tick
(stamps `started_ms` on become-live for Process / Monitor / Subagent /
daemon-sourced rows; compact `0s` / `12s` / `1m 5s` / `1h 2m` on live
rows; empty on settled; Native has no dedicated timer; skips when
nothing live needs a duration). First-cut daemon
`stopBackgroundWork` prefers hello + that command when Background
Stop targets a daemon-sourced live row and a daemon address, usable
session `runtimeId`, and usable `controlId` are set (one-shot sidecar,
distinct from refresh; optimistic Stopping; miss / overflow / no
controlId keep Faku-side dismiss). First-cut `outputDelta` appends a
bounded 512KB last-window onto an existing daemon-sourced row (empty
delta / missing key are no-ops; does not mint a row). First-cut
`stopFailed` clears Stopping on a still-live daemon row, restores
Running / Monitoring, and surfaces `message` as detail. Fuller
BackgroundWorkRegistry / GPUI SharedString parity still leftover.
Not daemon `WorkspaceOperation` for Background (first-cut daemon Push,
CreateWorktree, Commit, InspectBranches, CheckoutBranch,
InspectCommit, GenerateCommitMessage, ListTree, ListProjectFiles, DiscoverSlashCommands, CreateProjectlessWorkspace, MigrateProjectlessWorkspace, CollectReviewDiff,
BrowseDirectory, ReadTextFile, and WriteTextFile live on composer git / Send prep / Commit… / the
branch picker / Files refresh / Review Diff / Pick folder / Files
preview load / Files preview Save; CaptureTurnStart is a best-effort Send sidecar
alongside local snapshot capture; CaptureTurn is a best-effort
finish sidecar after local end capture; CopySessionRefs is a
best-effort Fork sidecar after the local catalog clone; DeleteSessionRefs
is a best-effort Remove sidecar after the local catalog drop; HasRef
is a prefer+fallback Send sidecar for the baseline `hasFakuRef`
check; CaptureRef is a best-effort sidecar after a successful local
`refs/faku` update-ref; RestoreRef is a prefer+fallback Rewind
sidecar for the stored turn-start snapshot; DeleteRef is a
best-effort sidecar after successful Rewind bookkeeping that drops
that same turn-start `refs/faku` name; DeleteTurnRefsAfter is a
best-effort sidecar after that same bookkeeping that range-deletes
turn / turn-start / turn-diff names for the dropped prompt;
SessionTurnRefs is a prefer+fallback sidecar on session select /
boot that lists daemon-side turn ordinals; DiscoverSlashCommands is
a prefer+fallback sidecar on composer `/` / session or provider
change that seeds `session.available_commands`; CreateProjectlessWorkspace is
a prefer+fallback sidecar on New Task when there is no ordinary
project that seeds `project_path`; MigrateProjectlessWorkspace is
a prefer+fallback sidecar on session select / boot when the
selected cwd still needs migration that retargets `project_path`). Environment Summary Background is
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
TaskStop. First-cut daemon `refreshBackgroundWork` prefer path
ships as above (open plus first-cut 5s tick); first-cut daemon `stopBackgroundWork` prefer path
ships for live daemon-sourced rows with a controlId; first-cut
`outputDelta` / `stopFailed` apply onto daemon-sourced rows; local Faku-side
Stop / Dismiss remains.

## Settings Providers

The settings gear chrome is General | Appearance | Providers | Skills | Usage | Computer Use. Providers
lists every `protocol.ProviderId` (fx, claude, codex, amp, grok,
opencode, cursor, pi, kimi). fx is the first-party default: status is
`Available` + probed path or `Not found` from the existing boot
`--help` probe (`fx_available` / `fxPath()`). Other rows one-shot
PATH `{defaultBinary()} --help` (no `~/.local/bin/<binary>` fallback
this cut) and show `Available` / `Not found` when that exit lands.
Refresh re-runs the fx probe and every non-fx probe. Boot starts
non-fx probes alongside fx (`initFx` → `startCliProbes`); Settings
→ Providers open is a no-op when already started. First-cut per-row
Enable/Disable persists `disabled_providers` (wire names) on
`sessions.json` extras (default empty = all enabled). The chip is
disable-flag-only (user can Enable/Disable regardless of install).
`providerEnabled` (plan-usage `maybeRefresh` gate) is `!disabled &&
isAvailable`. Disabled or Not-found / unset skips background
plan-usage refresh unless the selected session already uses that id;
Apply / started sessions on that provider still work. Not
full onboarding / OAuth / auto-install.

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

First-cut local meters for the selected session, plus a best-effort
daemon history slice. Context window uses `Session.context_used` /
`Session.context_size` (ACP `usage_update`; compact `12.4k / 200k`).
`context_size == 0` is an honest empty: "No context usage reported
yet". Thread goal tokens reuse `threadGoalUsageLabel()` (`12k/100k ·
3m`); missing fields stay "No thread goal usage". Identity is the
session header title. Persist is already on `sessions.json`; local
cards stay display-only.

View chips Daily | Monthly | Projects are runtime-only (default Daily;
not persisted). Daily and Projects share a runtime-only window selector
(7d / 30d / 90d / This month / Last month; default `{"trailingDays":30}`;
not persisted). When `WAKU_DAEMON_ADDRESS` or persisted
`last_daemon_address` is set, opening Usage or Refresh one-shots hello
+ `loadUsageHistory` (`window` + `projectRoots` from unique local
session `project_path` values, cap 32). Daily / Projects use the
selected window; Monthly always requests `{"months":12}` and hides the
selector. Same-window select is a no-op; Daily↔Projects that share
the window do not re-fetch. Ok payload
`usageHistory` paints a first-cut section: Daily shows
`sinceDay`–`untilDay`, `totalTokens` (+ `costUsd` when > 0),
`sessions`, a few provider rows (Claude Code / Codex) with first-cut
share bars (Cost | Tokens metric; bars use `costShare` / `tokenShare`
or computed shares) and a percent label, a Daily-only Model | Days
breakdown chip (default Model), model share bars when Model is
selected (provider label + model name; Cost prefers wire `costShare`,
Tokens always computed from totals), and up to ~8 recent `daily`
rows when Days is selected with a first-cut layered Native `<chart>` of that
window (Cost → `costUsd` or Tokens → `totalTokens` as oldest-first Claude/Codex
`kind="area"` series from a shared zero baseline, not stacked; `y-max` pins to
the max finite single-provider-day sample when that peak is > 0, else Native
auto-domain; documented `stroke-width` 2; paint-order by period total paints
the smaller series first so the larger fill sits on top, ties keep Claude then
Codex; empty `daily[]` hides the chart; still not Waku GPUI / T3 canvas:
no curve smoothing, no 12% fill opacity) plus first-cut nested Claude/Codex Native
`<progress>` rows from `daily[].byProvider` when any slot is non-zero
for the active metric (share within that day's Cost|Tokens total;
empty / missing / short `byProvider` stays day-total-only; chip flip
recomputes nested shares from the cached snapshot, no re-fetch). Monthly lists up to ~12 `months` rows
with a first-cut layered Native `<chart>` of that window (Cost →
`costUsd` or Tokens → `totalTokens` as oldest-first Claude/Codex
`kind="area"` series from a shared zero baseline, not stacked; `y-max`
pins to the max finite single-provider-month sample when that peak is
> 0, else Native auto-domain; documented `stroke-width` 2; paint-order
by period total paints the smaller series first so the larger fill sits
on top, ties keep Claude then Codex; empty `months[]` hides the chart;
still not Waku GPUI / T3 canvas: no curve smoothing, no 12% fill
opacity) plus first-cut relative bars
(share vs the max month in the window for Cost → `costUsd` or Tokens
→ `totalTokens`; Native `<progress>`; months with 0 stay text-only)
plus first-cut nested Claude/Codex Native `<progress>` rows from
`months[].byProvider` when any slot is non-zero for the active metric
(share within that month's Cost|Tokens total; empty / missing / short
`byProvider` stays month-total-only; chip flip recomputes nested
shares from the cached snapshot, no re-fetch) and the same Cost |
Tokens chip (flip recomputes from the cached months snapshot, no
re-fetch); Projects
lists up to ~16 `projects` rows (path basename) with a runtime-only
search filter (Waku `usage_project_filter`; case-insensitive
contains on basename or full path; trim; empty shows all) and a
first-cut layered Native `<chart>` of the visible filtered set (Cost →
`costUsd` or Tokens → `totalTokens` as Claude/Codex `kind="area"`
series from a shared zero baseline, not stacked; `y-max` pins to the
max finite single-provider-project sample among visible rows when that
peak is > 0, else Native auto-domain; documented `stroke-width` 2;
paint-order by period total over the visible set paints the smaller
series first so the larger fill sits on top, ties keep Claude then Codex;
empty visible set / empty
`projects[]` hides the chart; x-labels are path basename in painted
row order; still not Waku GPUI / T3 canvas: no curve smoothing, no 12%
fill opacity) plus first-cut
relative bars (share vs the max Cost|Tokens among
**visible** filtered rows; Native `<progress>`; zero-value rows stay
text-only) plus first-cut nested Claude/Codex Native `<progress>` rows
from `projects[].byProvider` on visible rows (share within that
project's Cost|Tokens total; empty / missing / short stays
project-total-only). The same Cost | Tokens chip (flip recomputes from the
cached projects snapshot, no re-fetch, respects the filter; nested
bars and chart samples only on visible rows).
No-match empty ("No matching projects") is distinct from no project
usage. Filter is not persisted and clears when leaving Usage or
Projects. A same-shape
snapshot (trailing vs months) stays painted while a replacement scan
is in flight. Native 4 KiB stdin
overflow / error / unusable parse / no daemon keep the local session
cards and must not toast-block Settings — history shows a muted
"Connect a daemon for usage history" or stays empty. Share bars and
a Daily Model | Days breakdown (default Model; Days keeps a
first-cut layered Native `<chart>` plus first-cut nested byProvider Claude/Codex
Native `<progress>` rows; documented `stroke-width` 2 and paint-order by
period total; still not Waku GPUI / T3 canvas: no curve smoothing, no 12% fill opacity) ship on Daily; first-cut Monthly layered Native `<chart>`
plus first-cut monthly bars plus first-cut nested byProvider Claude/Codex Native `<progress>` rows
ship on Monthly with the same Cost | Tokens chip; first-cut Projects layered Native `<chart>`
plus first-cut project
bars plus first-cut nested byProvider Claude/Codex Native `<progress>`
rows ship on Projects with that same chip plus a runtime-only
project search filter (peak-of-visible shares; nested bars and chart
samples only on visible rows); Daily, Monthly, and Projects paint a first-cut
five-tile Native metric strip (`totalTokens` plus `totals.cachedInput` /
`uncachedInput` / `output` / `cacheCreation` / `reasoning` and
`quality.cacheSavingsUsd`; zeros still paint; Daily / Projects use
active-day averages from `daily[]`; Monthly prefers active-month
averages from `months[]`) and Daily paints a
first-cut Cost quality panel (`quality` shares + cache savings) and
muted notices when `errors` are non-empty or `pricing` is
`unavailable`, plus a tiny scan-summary footer when `records` /
`scannedFiles` are present. First-cut LiteLLM rate-table fetch ships
(one-shot `fx.spawn` curl `-o` into the Faku data dir; 24h compact
`usage-model-rates.json` beside `sessions.json`; runtime map; Daily
paints `Rates fresh` / `Rates cached` / `Rates unavailable` and a
per-MTok hint on Model rows when lookup hits). First-cut Daily Days,
Monthly, and Projects layered Native `<chart>` ship (Claude/Codex area
from zero, not stacked; documented `stroke-width` 2; paint-order by
period total paints the smaller series first so the larger fill sits on
top, ties keep Claude then Codex; still not Waku GPUI / T3 canvas: no
curve smoothing, no 12% fill opacity; not a local
transcript scan).

## Composer usage meter

First-cut Waku-shaped meter under the composer. Visible whenever a
session is selected; Native `<progress>` (width 48 height 6) stands in
for Waku's circular GPUI gauge, including an empty bar when
`context_size == 0`. Opening Usage shows a panel with the session
context row (compact `12.4k / 200k`, or "Nothing measured yet") plus,
when the selected provider is Claude / Codex / OpenCode / Grok, plan
rate-limit lanes from daemon `FetchPlanUsage`. On panel open (and
Refresh) Faku one-shots hello + `fetchPlanUsage` (`provider` is Waku
`ProviderKind` camelCase `openCode`; `binaryOverride` / `cliVersion`
are JSON null this cut) when `WAKU_DAEMON_ADDRESS` or persisted
`last_daemon_address` is set. Open marks the selected path stale then
still fetches immediately. Ok payload `planUsage` paints
`planLabel` and up to 8 `windows` (`label`, `percent` 0..100, optional
unix-seconds `resetsAt`). JSON-null `usage` is unconfigured. No daemon
keeps local context and a muted connect hint. Unknown-command / parse
miss keep a prior snapshot or a muted error. First-cut Waku cadence
ships as `maybeRefresh` on the same `now_ms` / update tick as
`background_work.maybeRefresh` (Native has no dedicated timer): loop
all four plan-usage providers (Claude / Codex / OpenCode / Grok);
300s idle for Claude / Codex / OpenCode, 600s Grok, 30s when that
slot is stale (panel open or a settled turn), 90s retry after that
slot's fetch error; skip a provider that already has an in-flight
sidecar (`pending_key`); skip when `!providerEnabled &&
selectedProvider != provider` (`providerEnabled` is `!disabled &&
isAvailable`; boot starts CLI probes; Enable/Disable chip is still
disable-flag-only); unset per-provider
`checked_at` may fire once when eligible. Settle stamps that provider's `checked_at` and
clears its stale. Open / Refresh force the **selected** provider
only (cancel that slot's pending, then spawn) and do not cancel
other providers' in-flight fetches, including when the selected id
is disabled or not yet Available. Runtime-only first-cut plan_usage map
(four slots: Claude / Codex / OpenCode / Grok; not a HashMap);
switching session/provider shows that slot immediately and does not
clear the others. fx / cursor / amp / pi / kimi stay context-only. Still not a circular GPUI gauge, not a T3 chart. LiteLLM rate-table fetch ships on Settings Usage, not on this meter.

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
| Keyboard dispatch | `src/keys.zig` |
| Msg update / initFx | `src/update.zig` |
| Model / Msg / Turn / Folder | `src/model.zig` |
| Session type | `src/session.zig` |
| Defer-until-Send workspace | `src/session_workspace.zig` |
| Local catalog | `src/store.zig` |
| ACP builders | `src/acp.zig`, `src/acp_proxy.zig` |
| Daemon sidecar | `src/daemon_proxy.zig`, `src/protocol.zig` |
| Send / stream | `src/spawn.zig`, `src/stream.zig`, `src/lines.zig` |
| Environment Summary | `src/environment_summary.zig` |
| Right panel | `src/right_panel.zig`, `src/review_diff.zig`, `src/open_url.zig` |
| Skills scan | `src/skills.zig` |
| Providers catalog | `src/providers.zig`, `src/cli_probe.zig` |
| Composer / attach | `src/composer.zig`, `src/attach.zig`, `src/slash_commands.zig` |
| Settings chrome + sidebar date i18n | `src/i18n.zig`, `src/sidebar_dates.zig` |
| Settings Usage history | `src/usage_history.zig`, `src/protocol.zig` |
| LiteLLM rate table | `src/litellm_rates.zig` |
| Composer usage meter | `src/usage_meter.zig`, `src/protocol.zig` |

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
- Usage history from daemon `LoadUsageHistory` ships as a first-cut
  Settings Usage slice (Daily / Monthly / Projects chrome; Daily /
  Projects window selector for 7 / 30 / 90 / this / last month,
  default `trailingDays: 30`; Monthly stays `months: 12` and hides the
  selector; headline tokens/cost/sessions + provider / day / month /
  project text rows when a daemon address is set; Daily per-provider
  share bars with a runtime-only Cost | Tokens metric, default Cost,
  using wire `costShare` / `tokenShare` or client-computed shares;
  Daily-only Model | Days breakdown chip (default Model; model share
  bars from `models[]` ModelSlice — Cost prefers wire `costShare`,
  Tokens computed from totals; Days keeps a first-cut layered Native
  `<chart>` of oldest-first Claude/Codex `kind="area"` series from zero
  (not stacked; `y-max` pins to the max finite single-provider-day
  sample when that peak is > 0, else Native auto-domain; documented
  `stroke-width` 2; paint-order by period total; still not Waku
  GPUI / T3 canvas: no curve smoothing, no 12% fill opacity), plus first-cut nested Claude/Codex Native `<progress>`
  from `daily[].byProvider` (share within that day's Cost|Tokens
  total; empty/missing/short stays day-total-only; chip flip does
  not re-fetch); first-cut Monthly layered Native `<chart>` of
  oldest-first Claude/Codex `kind="area"` series from zero (not
  stacked; `y-max` pins to the max finite single-provider-month sample
  when that peak is > 0, else Native auto-domain; documented
  `stroke-width` 2; paint-order by period total; empty `months[]`
  hides the chart; still not Waku GPUI / T3 canvas: no curve smoothing,
  no 12% fill opacity) plus
  first-cut Monthly bars relative to the max month in the window for
  that same Cost | Tokens chip, Native `<progress>`, plus first-cut
  nested Claude/Codex Native `<progress>` from `months[].byProvider`
  (share within that month's Cost|Tokens total; empty/missing/short
  stays month-total-only; chip flip does not re-fetch); first-cut
  Projects layered Native `<chart>` of visible-filtered Claude/Codex
  `kind="area"` series from zero (not stacked; `y-max` pins to the max
  finite single-provider-project sample among visible rows when that
  peak is > 0, else Native auto-domain; documented `stroke-width` 2;
  paint-order by period total over the visible set; empty visible set /
  empty `projects[]` hides the chart; still not Waku GPUI / T3 canvas:
  no curve smoothing, no 12% fill opacity)
  plus first-cut Projects bars relative to the max Cost|Tokens
  among visible filtered rows for that same chip, Native `<progress>`,
  plus first-cut nested Claude/Codex Native `<progress>` from
  `projects[].byProvider` on visible rows (share within that project's
  Cost|Tokens total; empty/missing/short stays project-total-only),
  runtime-only `usage_project_filter` (basename or path; peak-of-visible;
  chip flip does not re-fetch); first-cut Daily / Monthly / Projects
  five-tile Native metric strip from `totalTokens` / `totals` /
  `quality.cacheSavingsUsd` (processed tokens / cached input /
  uncached input / output / cache savings; zeros still paint; Daily /
  Projects: active-day averages from `daily[]`; Monthly: active-month
  averages from `months[]`); first-cut Daily Cost quality panel from
  `quality` (Provider reported / Model priced / Unpriced percents +
  Cache savings USD) plus muted notices when `errors` are non-empty or
  `pricing` is `unavailable`. First-cut LiteLLM rate-table fetch ships
  (one-shot curl `-o` into the Faku data dir, 24h compact
  `usage-model-rates.json`, runtime map, Daily `Rates fresh` /
  `Rates cached` / `Rates unavailable`, Model-row per-MTok hint on
  lookup hit). First-cut Daily Days, Monthly, and Projects layered Native
  `<chart>` ship (Claude/Codex area from zero, not stacked; documented
  `stroke-width` 2; paint-order by period total); still not
  Waku GPUI / T3 canvas (no curve smoothing, no 12% fill opacity), not a local transcript
  scan. Local session
  context + thread-goal cards
  stay when the daemon is absent.
- Composer usage meter ships as a first-cut Native `<progress>` under
  the composer (always visible with a selected session) plus a panel
  with local context and daemon `FetchPlanUsage` plan lanes for
  Claude / Codex / OpenCode / Grok. First-cut Waku cadence ships
  (`maybeRefresh` on the `now_ms` / update tick loops all four: 300s
  idle, 600s Grok, 30s stale after panel open / turn settle, 90s
  retry on error; at most one in-flight sidecar per provider; skip
  when `!providerEnabled && selectedProvider != provider`; open /
  Refresh stay immediate for the selected provider only, including a
  disabled or not-yet-Available selected id). First-cut
  `disabled_providers` persist + Settings → Providers Enable/Disable
  ships (`providerEnabled` is `!disabled && isAvailable`; boot starts
  non-fx CLI `--help` probes; Enable/Disable chip is still
  disable-flag-only). Disabling does not move unstarted drafts /
  last_provider — Faku new sessions stay fx and drafts.json has no
  provider. First-cut
  per-provider plan_usage map ships (four runtime slots keyed by
  Claude / Codex / OpenCode / Grok; `checked_at` / `stale` /
  `pending_key` per slot; adopt / error write the slot whose
  pending_key matched; view helpers read the selected slot; switching
  does not clear the others). Still not Waku's circular GPUI gauge,
  not LiteLLM on the meter (rate-table fetch ships on Settings Usage),
  not a T3 layered / stacked canvas chart.
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
- Claude CLI TaskStop / long-lived ACP, full
  BackgroundWorkRegistry event/reconcile parity (Environment Summary
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
  Faku-side Dismiss, not Claude TaskStop; not live after `-p`
  exits); Faku-side
  Dismiss all settled for the selected session (settled Monitor /
  Subagent plus the cap-1 Process settle; live rows and the stream
  stay; not Claude TaskStop); first-cut
  daemon `refreshBackgroundWork` prefers hello + that command when a
  daemon address and usable session `runtimeId` are set on Background
  tab / Environment Summary open (immediate one-shot sidecar; Ack plus
  `backgroundWork` events apply reconcileProcesses / reconcileLive /
  upsert / outputDelta / stopFailed into daemon-sourced rows; miss keeps local rows) and on a
  first-cut 5s `BACKGROUND_WORK_REFRESH_INTERVAL` tick piggybacked
  off `now_ms` / the update tick (prefers selected when it has a
  usable `runtimeId` and the Background tab is showing, Environment
  Summary is open, or that session has live Process / Monitor /
  Subagent / daemon-sourced rows; else one other live session with
  a usable `runtimeId` and a daemon address; one in-flight sidecar;
  skips an in-flight refresh sidecar; Native has no dedicated
  timer); first-cut
  daemon `stopBackgroundWork` prefers hello + that command when
  Background Stop targets a daemon-sourced live row and a daemon
  address, usable `runtimeId`, and usable `controlId` are set
  (one-shot sidecar, distinct from refresh; optimistic Stopping;
  miss / overflow / no controlId keep Faku-side dismiss; settled
  daemon rows stay Faku-side Dismiss); first-cut `outputDelta`
  appends a bounded last-window onto an existing daemon-sourced row
  (empty delta / missing key are no-ops); first-cut `stopFailed`
  restores a still-live Stopping row (Running / Monitoring) and
  surfaces `message` as detail; and a first-cut
  right-panel Background surface from those rows that shows the
  stored Monitor / Subagent log, Stop when the selected row is
  a live Process, live Monitor, live Subagent, or a live daemon
  row with canStop + controlId, and Dismiss when
  the selected row is a settled Monitor, Subagent, or daemon row;
  first-cut 1s `BACKGROUND_WORK_TICK_INTERVAL` elapsed duration
  labels ship (`maybeTickElapsed` piggybacks `now_ms` / the update
  tick; stamps `started_ms` on become-live; compact `0s` / `12s` /
  `1m 5s` / `1h 2m` on live rows; empty on settled); not Waku
  BackgroundWorkRegistry event/reconcile/driver-refresh / GPUI
  SharedString parity)
- First-cut GitHub Releases wrap documented `native package` trees
  (host-native; no eject) as user-facing installers: unsigned macOS
  DMG (`--signing none`; no Apple identity / notarize), amd64 Debian
  `.deb` from the Linux FHS install tree, silent NSIS `.exe` from the
  early Windows directory. No zip. Unsigned NSIS (SmartScreen).
  Fedora/Arch compile with Native CLI. Not iOS/Android.
  README Install Faku leads with the live `v0.1.0` downloaders;
  clone / Native CLI is secondary.
- Further `main.zig` extract (`initialModel` / appearance boot live in
  `boot.zig`; icons + shell scene live in `shell.zig`; layout chrome
  lives in `layout.zig`; spawn / stream effect keys live in
  `effect_keys.zig`; remaining `main.zig` leftovers are
  re-exports + `main()` + demo seed strings)
- Embedded BrowserView / alacritty PTY (right-panel Browser and
  Terminal first-cuts ship as OS-open workarounds: system browser via
  `open` / `xdg-open` / Windows `cmd.exe /c start "" <url>`, host
  terminal via existing Open in Terminal (`open -a Terminal` /
  `x-terminal-emulator` / Windows `wt.exe -d` then
  `cmd.exe /c start "" /D`);
  Native has no PTY or documented webview effect. Compact File editor:
  Files ships a
  256KB inline preview with Native `<code>` highlighting and
  `line-numbers`; language from a documented lexer name, unknown →
  plain. Markdown `.md` / `.markdown` first-cut: runtime-only Preview |
  Source chips (default Preview is Native `<markdown>`; Source is
  highlighted `<code language="markdown">`; http(s) on-link reuses
  `open_url` OS browser spawn; relative / file links muted; no
  `images=` this cut). First-cut: opening the first Files preview widens the pane
  with Waku `FILE_EDITOR_INITIAL_WIDTH` 500 (wide clamp 280–1000 while
  that preview is open). First-cut: opening Diff / Review widens the pane
  with Waku `REVIEW_INITIAL_WIDTH` 820 (wide clamp 280–1000; Browser /
  Terminal / Background stay the 460 bump). First-cut Edit / Save / Reload ships: textarea while dirty,
  Save prefers hello + daemon `WriteTextFile` when a daemon address
  is set (ok Ack; Native 4 KiB stdin overflow falls back to Zig
  `std.fs` atomic write), Reload discards unsaved edits. First-cut
  live reload via mtime/size poll on the update tick. First-cut Files
  preview find/replace ships (Native bar: query, match count, prev/next,
  close, case toggle, whole-word toggle, regex `.*` toggle, Replace when
  editable). Plain substring with optional ASCII case-sensitivity and
  whole-word (`[A-Za-z0-9_]` boundaries) until regex is on (self-contained
  Zig subset, `$n` capture expand; invalid pattern shows `invalid`);
  cap 20000 navigable matches; no GPUI washes. Not a
  real FS watcher / Native watch API)
- Amend/force and remote `--track` stay local (not daemon
  WorkspaceOperation variants). First-cut
  `WorkspaceOperation::Push` ships as a best-effort sidecar when
  `WAKU_DAEMON_ADDRESS` or persisted `last_daemon_address` is set;
  Force stays local `git push --force`. First-cut
  `WorkspaceOperation::CreateWorktree` ships on Send prep for a
  `newWorktree` draft when a daemon address is set; Native 4 KiB
  stdin overflow falls back to local `git worktree add`; no address
  keeps today's local path. First-cut `WorkspaceOperation::Commit`
  ships on Commit… when a daemon address is set; Amend and
  Force+Commit and Push stay local git; Native 4 KiB stdin overflow
  falls back to local add/preflight/commit. First-cut
  `WorkspaceOperation::InspectBranches` ships on the composer
  branch-list picker when a daemon address is set; Waku lists local
  heads only; remotes-on-daemon-list ships as a follow-up local
  `git for-each-ref` merge (daemon heads stay source of truth);
  Native 4 KiB stdin overflow / error / null snapshot falls back to
  local `git for-each-ref`; not a live watch. First-cut
  `WorkspaceOperation::CheckoutBranch` ships on picker local-head
  checkout and New branch create when a daemon address is set; ok is
  nested `branchChanged` + snake_case snapshot; Native 4 KiB stdin
  overflow falls back to local `git checkout` / `git checkout -b`;
  remote `--track` stays local git; no address keeps today's local
  path. First-cut `WorkspaceOperation::InspectCommit` ships on
  Commit… open / include-unstaged re-probe when a daemon address is
  set; ok is nested `commitSnapshot` + snake_case snapshot; Native
  4 KiB stdin overflow / error / unusable snapshot falls back to
  local numstat; no address keeps today's local path. First-cut
  `WorkspaceOperation::GenerateCommitMessage` ships on empty-message
  Commit… generate when a daemon address is set; ok is nested
  `commitMessage` + `message`; Native 4 KiB stdin overflow / error /
  empty / parse miss falls back to local `fx ask`; no address keeps
  today's local path. First-cut
  `WorkspaceOperation::ListProjectFiles` ships on composer `@` /
  Files refresh when a daemon address is set; ok is nested
  `projectFiles` + `{ path, is_dir }` FileEntry rows (not camelCase
  `isDir`); paints the file-mention cache from files + trailing-slash
  dir sentinels; Native 4 KiB stdin overflow / error / unusable parse
  falls back to ListTree then local `git ls-files` then walk; no
  address keeps today's local path. First-cut
  `WorkspaceOperation::DiscoverSlashCommands` ships on composer `/`
  slash-prefix / session or provider change when a daemon address is
  set and the selected session has a usable non-empty `project_path`;
  ok is nested `slashCommands` + `{ name, description, scope,
  argument_hint, template }` rows; paints
  `session.available_commands`; Native 4 KiB stdin overflow / error /
  empty / unusable parse keep today's ACP-only catalog and must not
  clear a good ACP list; later live ACP replace/wins; no address
  keeps today's ACP path. First-cut
  `WorkspaceOperation::CreateProjectlessWorkspace` ships on New Task
  when there is no ordinary project (empty `last_project_path`, or
  the selected session's `project_path` is already a projectless path
  under `~/.waku/projects`); ok is nested `projectlessWorkspace` +
  `cwd`; Native 4 KiB stdin overflow / error / unusable parse / empty
  cwd fall back to local mkdir under `~/.waku/projects/<date>/<slug>`;
  no address keeps that local mkdir. First-cut
  `WorkspaceOperation::ListTree` ships on Files expand after a
  daemon fill when a daemon address is set; ok is nested `workingTree`
  + camelCase `WorkingTreeEntry` rows; paints the Files cache from
  file entries; expand after a daemon fill re-prefers ListTree;
  Native 4 KiB stdin overflow / error / unusable parse falls back to
  local `git ls-files` then walk; no address keeps today's local
  path. First-cut
  `WorkspaceOperation::CollectReviewDiff` ships on Review / Diff
  open / refresh / source-switch when a daemon address is set; ok is
  nested `reviewDiff` + camelCase `ReviewDiffData` (`source`,
  `numstat`, `patch`, `completeContext`); paints the file list from
  `numstat` (cap 64, with per-file `+N` / `-M` when those counts are
  non-zero) and selected hunk from `patch` without per-file
  hunk spawns; selected hunk parses into Gap rows (`completeContext`
  collapses expandable context; compact patches insert count-only Gaps);
  local `--numstat` Diff paints the same counts; LastTurn stays local; Native 4 KiB stdin overflow /
  error / unusable parse falls back to local numstat + hunk
  probes; no address keeps today's local path. First-cut
  `WorkspaceOperation::BrowseDirectory` ships on Pick folder (or Cmd/Ctrl-O;
  Cmd/Ctrl-N stays New Task) when a
  daemon address is set; ok is nested `directory` + camelCase `path` /
  `parent` / `home` / `filesystemRoot` / `WorkingTreeEntry` rows;
  paints a first-cut in-app directory browser from `entries`; Choose
  sets `project_path` on the selected session (not Waku's Project catalog);
  Native 4 KiB stdin overflow / error / unusable
  parse falls back to the local OS folder dialog; no address keeps
  today's OS path. First-cut
  `WorkspaceOperation::ReadTextFile` ships on Files preview load
  (select / Reload that re-reads) when a daemon address is set; ok is
  nested `textFile` + `content`; paints the same 256KB UTF-8 preview
  buffers (client-side cap / binary / truncated label); fingerprint
  refresh matches local when stat works; Native 4 KiB stdin overflow
  / error / unusable parse falls back to local `readFileAlloc`;
  Reload re-prefers ReadTextFile while an address is set. First-cut
  `WorkspaceOperation::WriteTextFile` ships on Files preview Save
  when a daemon address is set; ok is workspace Ack (same nested
  `result: { "type": "ack" }` as Push / Commit / CaptureTurnStart);
  adopts the saved buffer as the preview body; Native 4 KiB stdin
  overflow / spawn failure / non-ok / non-ack / unusable parse falls
  back to local atomic write; truncated / binary / gated refuse stay
  local (no daemon attempt); Open-in-editor stays local; no address
  keeps today's local path. First-cut
  `WorkspaceOperation::CaptureTurnStart` ships on Send after local
  capture when a daemon address is set; ok is workspace Ack; local
  `worktree_snapshot_sha` / `refs/faku/...` stay canonical; Native
  4 KiB stdin overflow / sidecar failure must not break Send or
  clear the local sha; no address keeps today's local-only path.
  First-cut `WorkspaceOperation::CaptureTurn` ships after successful
  local finish-time capture when a daemon address is set; ok is
  nested `WorkspaceResult::Checkpoint`; local
  `worktree_turn_end_sha` / `worktree_turn_diff_sha` /
  `refs/faku/...` stay canonical; daemon Checkpoint must not
  replace those; Native 4 KiB stdin overflow / sidecar failure / no
  address leave local alone. First-cut
  `WorkspaceOperation::CopySessionRefs` ships after a local
  `sessions.json` fork when a daemon address is set; ok is workspace
  Ack; local fork / `refs/faku/...` stay canonical; Native 4 KiB
  stdin overflow / sidecar failure / no address leave the local
  fork alone. First-cut
  `WorkspaceOperation::DeleteSessionRefs` ships after a local
  `sessions.json` remove when a daemon address is set; ok is
  workspace Ack; local catalog remove / `closeSession` stay
  canonical; Native 4 KiB stdin overflow / sidecar failure / no
  address leave the local remove alone. First-cut
  `WorkspaceOperation::HasRef` ships on Send after local turn-start
  capture when a daemon address is set; ok is nested
  `WorkspaceResult::Bool`; prefers hello + hasRef for the baseline
  check that otherwise calls local `checkpoint.hasFakuRef`; Native
  4 KiB stdin overflow / miss / non-bool / error fall back to local
  `hasFakuRef`; no address keeps today's local path; spawn only when
  cwd is a git worktree. First-cut
  `WorkspaceOperation::CaptureRef` ships after a successful local
  `refs/faku` update-ref when a daemon address is set; ok is
  workspace Ack; local `refs/faku/...` stay canonical; Native 4 KiB
  stdin overflow / sidecar failure / miss / non-ack / no address
  leave local refs alone (no rollback); spawn only when cwd is a
  git worktree. First-cut
  `WorkspaceOperation::RestoreRef` ships on Header Rewind when a
  daemon address is set and cwd is a git worktree; ok is workspace
  Ack; prefers hello + restoreRef for the matching
  `refs/faku/session-{id}-turn-start-{n}`; Native 4 KiB stdin
  overflow / miss / non-ack / error fall back to local
  `restoreRef(sha)` / `resetHard`; no address keeps today's local
  path; spawn only when a snapshot sha is stored. First-cut
  `WorkspaceOperation::DeleteRef` ships after successful Header
  Rewind bookkeeping when a daemon address is set and cwd is a git
  worktree; ok is workspace Ack; local `deleteFakuRef` runs first
  for `refs/faku/session-{id}-turn-start-{n}`; Native 4 KiB stdin
  overflow / miss / non-ack / no address leave rewind transcript
  bookkeeping alone; spawn only when cwd is a git worktree.
  First-cut
  `WorkspaceOperation::DeleteTurnRefsAfter` ships after successful
  Header Rewind bookkeeping when a daemon address is set and cwd is
  a git worktree; ok is workspace Ack; hello +
  `{ "type": "deleteTurnRefsAfter", "cwd", "session_id",
  "retained_turn_count", "previous_turn_count" }` (snake_case
  session/turn fields; `session_id` is `daemon_proxy.wireUuid`);
  Header Rewind of the last prompt uses `previous_turn_count =
  turn_n` before `dropLastPromptTurns` and `retained_turn_count =
  turn_n - 1` when `turn_n > 0` else 0; local `deleteFakuRef` +
  DeleteRef stay; Native 4 KiB stdin overflow / miss / non-ack /
  no address leave rewind transcript bookkeeping alone; spawn only
  when cwd is a git worktree. First-cut
  `WorkspaceOperation::SessionTurnRefs` prefers hello +
  sessionTurnRefs on session select / boot when a daemon address is
  set and cwd is a git worktree; ok is nested `turnRefs.turn_counts`
  (empty array still ok); snake_case `session_id` is
  `daemon_proxy.wireUuid`; local `checkpoint.sessionTurnRefs` stays
  the overflow / miss / non-ok / no-address path and remains
  canonical; runtime cache only; miss must not break rewind /
  checkpoint bookkeeping. First-cut
  `WorkspaceOperation::ListProjectFiles` prefers hello +
  listProjectFiles on composer `@` / Files refresh when a daemon
  address is set; ok is nested `projectFiles.entries` (`path`,
  `is_dir`); paints the file-mention cache; Native 4 KiB stdin
  overflow / miss / non-ok fall back to ListTree then local `git
  ls-files` then walk; expand after a daemon fill re-prefers
  ListTree; no address keeps today's local path; miss must not
  break `@` / Files. First-cut
  `WorkspaceOperation::DiscoverSlashCommands` prefers hello +
  discoverSlashCommands on composer `/` slash-prefix / session or
  provider change when a daemon address is set and `project_path`
  exists; ok is nested `slashCommands.commands` (`name`,
  `description`, `scope`, snake_case `argument_hint` / `template`);
  `provider` is Waku `ProviderKind` camelCase (`openCode`);
  `binary_override` omitted when null; paints
  `session.available_commands`; Native 4 KiB stdin overflow / miss /
  non-ok / empty keep today's ACP-only catalog and must not clear a
  good ACP list; later live ACP `available_commands_update`
  replace/wins; no address keeps today's ACP path. First-cut
  `WorkspaceOperation::CreateProjectlessWorkspace` prefers hello +
  createProjectlessWorkspace on New Task when there is no ordinary
  project (empty `last_project_path`, or the selected session's
  `project_path` is already a projectless path under
  `~/.waku/projects` and legacy `~/.waku/<date>/…`); ok is nested
  `projectlessWorkspace.cwd` (not Ack, not Bool, not a bare
  object; empty cwd rejected); `prompt` is JSON null on this
  first-cut; Native 4 KiB stdin overflow / miss / non-ok fall back
  to local mkdir under `~/.waku/projects/<YYYY-MM-DD>/<slug>`
  (`new-chat` for a null prompt; numbered candidates if taken); home
  / mkdir failure keeps today's empty/copied `last_project_path`
  and must not toast-block New Task; ordinary New Task with a real
  project path still copies `last_project_path`. First-cut
  `WorkspaceOperation::MigrateProjectlessWorkspace` prefers hello +
  migrateProjectlessWorkspace on session select / boot when the
  selected session's `project_path` still needs migration (legacy
  projectless, not under `~/.waku/projects`); ok is nested
  `projectlessWorkspace.cwd` (same as Create; not Ack, not Bool,
  not a bare object; empty cwd rejected); `path` is always present;
  Native 4 KiB stdin overflow / miss / non-ok fall back to local
  rename of dated `~/.waku/<date>/<slug>` into
  `~/.waku/projects/<date>/<slug>` (numbered `-2`… if taken) or a
  fresh mkdir like Create when the path is bare `~/.waku`;
  already-under-projects is a no-op; home / failure must not
  toast-block session select; ordinary real project paths do not
  spawn migrate. Leftover: reusing an unstarted projectless
  draft is skipped this cut. Amend/force and remote `--track`
  stay local (not daemon WorkspaceOperation variants)
- Long-lived ACP or daemon socket in the update loop
- fx ACP still rejects image blocks (`fx ask --image`). First-cut
  ACP image content blocks (base64 + mimeType, ~256KB raw, size
  fail-closed) ship for probed cursor / opencode / grok / kimi. Codex uses
  `codex exec --image`, not ACP; Amp uses execute-mode `@{path}` in
  the `-x` prompt, not ACP; Pi uses json-mode `@{path}`, not ACP;
  Claude uses print-mode path-in-prompt, not ACP

