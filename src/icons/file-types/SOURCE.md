# Material file icons

This directory contains a curated subset of the
[Material Icon Theme](https://github.com/PKief/vscode-material-icon-theme)
file icons (83 SVGs: first-cut coding-agent languages, a
second-cut language/data expansion, a third-cut tooling
subset, a fourth-cut frameworks/meta subset, a fifth-cut
media/config swap, a sixth-cut cert/lock/exe/nginx, plus a
seventh-cut cmake/coffee/gitlab/gradle/kubernetes/tex). That project is MIT; see its
[upstream license](https://github.com/PKief/vscode-material-icon-theme/blob/main/LICENSE).

SVG bytes come from the already-curated Waku subset (`egoist/waku`
`assets/icons/file-types/`, same Material pack + SOURCE) rather than
the full Material catalog. Native's comptime SVG dialect has no
`style=""`; CSS `fill` / `stroke-width` on those files were promoted
to presentation attributes so the Material colors still paint. Paths
and viewBoxes are otherwise unchanged. `lock.svg` registers as
`lockfile` (`app:lockfile`) so it does not collide with chrome Browser
address `app:lock`. Waku `kotlin` (gradient
`fill="url(#…)"`), `graphql` (`transform=` on connecting bars),
`prettier` (`transform=` on the wrapping group), `nest`
(`transform=` on the path), `clojure` (`transform=`), `editorconfig`
(`transform=`), and `helm` (`transform=`) are omitted — Native rejects
those paints / ignores transforms.

Faku mapping and registration code stays GPL-3.0-only; these SVG
files remain MIT.
