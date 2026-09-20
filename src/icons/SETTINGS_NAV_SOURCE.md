# Settings nav icons

Lucide-shaped strokes taken from [egoist/waku](https://github.com/egoist/waku)
`assets/icons/` (GPL-3.0) and adapted to `currentColor` for Native.
Faku mapping and registration code stays GPL-3.0-only. Do not copy
Waku Rust/TS.

| File | Registry name | Settings tab |
| --- | --- | --- |
| `appearance.svg` | `app:appearance` | Appearance |
| `bot.svg` | `app:bot` | Providers |
| `package.svg` | `app:package` | Skills |
| `chart-column.svg` | `app:chart-column` | Usage |
| `server.svg` | `app:server` | Daemon |
| `cursor-spark.svg` | `app:cursor-spark` | Computer Use |

General uses the built-in Native `settings` icon (`icon="settings"`),
not a registered app icon (file-type `app:settings` stays the Material
settings glyph).

Native's comptime SVG dialect has no `style=""`, no `transform=`, and
no `url(#…)` paints. Stroke `#000` became `currentColor`; appearance's
filled half-circle uses `fill="currentColor"`. `cursor-spark.svg` keeps
`fill="currentColor"` fill-rule paths (`fill-rule` / `clip-rule` are
unknown attributes the parser ignores).
