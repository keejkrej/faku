# Settings Providers row icons

Brand marks taken from [egoist/waku](https://github.com/egoist/waku)
`assets/icons/provider-*.svg` (GPL-3.0) and adapted to `currentColor`
for Native. Faku mapping and registration code stays GPL-3.0-only.
Do not copy Waku Rust/TS.

| Waku file | Registry name | ProviderId |
| --- | --- | --- |
| `provider-fx.svg` | `app:provider-fx` | fx |
| `provider-claude.svg` | `app:provider-claude` | claude |
| `provider-openai.svg` | `app:provider-openai` | codex |
| `provider-cursor.svg` | `app:provider-cursor` | cursor |
| `provider-amp.svg` | `app:provider-amp` | amp |
| `provider-grok.svg` | `app:provider-grok` | grok |
| `provider-opencode.svg` | `app:provider-opencode` | opencode |
| `provider-pi.svg` | `app:provider-pi` | pi |
| `provider-kimi.svg` | `app:provider-kimi` | kimi |
| `provider-ohmypi.svg` | `app:provider-ohmypi` | ohmypi |
| `provider-opencode2.svg` | `app:provider-opencode2` | opencode2 |
| `provider-deepseek.svg` | `app:provider-deepseek` | deepseek |

Codex uses the OpenAI mark in Waku (`provider-openai.svg`); there is
no `provider-codex.svg`.

Native's comptime SVG dialect has no `style=""`, no `transform=`, and
no `url(#…)` paints. Stroke / fill `#000` became `currentColor`.
`fill-rule` / `clip-rule` / `fill-opacity` are unknown attributes the
parser ignores (same note as `cursor-spark.svg`).

OpenCode's evenodd frame plus `fill-opacity=".28"` inner would paint
solid without those attributes, so `provider-opencode.svg` is a nested
`currentColor` stroke-rect mark that still reads as that window logo.
Pi's evenodd hole would fill solid, so `provider-pi.svg` is the same
π-plus-square as separate `<rect>`s (original viewBox kept).
Oh My Pi's Waku mark is a linearGradient `url(#…)` paint Native
cannot keep, so `provider-ohmypi.svg` is the same π path with
`fill="currentColor"` (original viewBox kept).
OpenCode 2's evenodd frame plus `fill-opacity=".28"` inner bars would
paint solid, so `provider-opencode2.svg` is the window as separate
`<rect>`s (original viewBox kept) plus the Waku red `#D95A50` "2"
badge as a literal fill. Inner bars are solid `currentColor` because
Native ignores `fill-opacity`.
DeepSeek's Waku mark is a single `#000` path (`fill-rule="nonzero"`
is ignored). `provider-deepseek.svg` keeps that path with
`fill="currentColor"` (original viewBox kept).

Availability is the existing status / model_count caption, not a Waku
GPUI colored overlay dot. Native `list-item` `icon=` is one leading
slot on the same hit target; disabling the row to mute the mark would
block Enable / expand / select, so Available-disabled and Not found
keep the mark at normal tint.
