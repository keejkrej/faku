# Material file icons

This directory contains a curated first-cut subset of the
[Material Icon Theme](https://github.com/PKief/vscode-material-icon-theme)
file icons. That project is MIT; see its
[upstream license](https://github.com/PKief/vscode-material-icon-theme/blob/main/LICENSE).

SVG bytes come from the already-curated Waku subset (`egoist/waku`
`assets/icons/file-types/`, same Material pack + SOURCE) rather than
the full Material catalog. Native's comptime SVG dialect has no
`style=""`; CSS `fill` / `stroke-width` on those files were promoted
to presentation attributes so the Material colors still paint. Paths
and viewBoxes are otherwise unchanged.

Faku mapping and registration code stays GPL-3.0-only; these SVG
files remain MIT.
