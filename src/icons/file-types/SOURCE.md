# Material file icons

This directory contains a curated subset of the
[Material Icon Theme](https://github.com/PKief/vscode-material-icon-theme)
file icons (58 SVGs: first-cut coding-agent languages, a
second-cut language/data expansion, plus a third-cut tooling
subset). That project is MIT; see its
[upstream license](https://github.com/PKief/vscode-material-icon-theme/blob/main/LICENSE).

SVG bytes come from the already-curated Waku subset (`egoist/waku`
`assets/icons/file-types/`, same Material pack + SOURCE) rather than
the full Material catalog. Native's comptime SVG dialect has no
`style=""`; CSS `fill` / `stroke-width` on those files were promoted
to presentation attributes so the Material colors still paint. Paths
and viewBoxes are otherwise unchanged. Waku `kotlin` (gradient
`fill="url(#…)"`), `graphql` (`transform=` on connecting bars), and
`prettier` (`transform=` on the wrapping group) are omitted — Native
rejects those paints / ignores transforms.

Faku mapping and registration code stays GPL-3.0-only; these SVG
files remain MIT.
