# Material file icons

This directory contains a curated subset of the
[Material Icon Theme](https://github.com/PKief/vscode-material-icon-theme)
file icons (97 SVGs: first-cut coding-agent languages, a
second-cut language/data expansion, a third-cut tooling
subset, a fourth-cut frameworks/meta subset, a fifth-cut
media/config swap, a sixth-cut cert/lock/exe/nginx, a
seventh-cut cmake/coffee/gitlab/gradle/kubernetes/tex, an
eighth-cut crystal/elm/erlang/haxe/jinja/xaml/diff/file, a
ninth-cut julia/prettier/kotlin dialect-workaround swap, plus
a tenth-cut clojure/helm/editorconfig dialect-workaround
swap). That project is MIT; see its
[upstream license](https://github.com/PKief/vscode-material-icon-theme/blob/main/LICENSE).

SVG bytes come from the already-curated Waku subset (`egoist/waku`
`assets/icons/file-types/`, same Material pack + SOURCE) rather than
the full Material catalog. Native's comptime SVG dialect has no
`style=""`, no `transform=`, and no `fill="url(#…)"` gradients. CSS
`fill` / `stroke-width` on earlier files were promoted to presentation
attributes so the Material colors still paint. Ninth-cut workarounds
bake group transforms into coordinates (`julia` translate into circle
`cx`/`cy`; `prettier` `matrix(.9 0 0 .9 10.5 10.5)` into each rect's
`x`/`y`/`width`/`height`/`rx`) and replace `kotlin` linearGradient
`fill="url(#…)"` with solid brand fills (`#7F52FF` / `#F28E0E`) so
there are no `<defs>` or `url(#)`. Tenth-cut workarounds promote CSS
fills and drop Native-ignored transforms without rewriting path `d`
data: `clojure` four-path `style="fill:#…"` plus near-identity
`translate(6.496 6.395) scale(.94843)` on viewBox `0 0 256 256`;
`helm` one-path `style="fill:#00acc1"` plus `translate(16.994 11.498)
scale(2.1985)` (viewBox retuned to pre-transform content bounds
`0.551 0.185 119.882 125.663` so the cyan glyph still fills icon size);
`editorconfig` late-path `style="fill:…"` plus shared
`translate(124.37 282.35) scale(.89449)` dropped so early untransformed
face paths and the silhouette still compose in the original
`0 0 3473 3473` viewBox. Paths are otherwise unchanged. `lock.svg`
registers as `lockfile` (`app:lockfile`) so it does not collide with
chrome Browser address `app:lock`. Waku `nest` stays omitted: stripping
the root `style="enable-background:…"` still leaves a path
`transform="translate(…) scale(…)"` (and a path `style="fill:…"`)
that Native ignores; baking that path would invent markup. `graphql`
(many `rotate` transforms on connector bars), `nest` (path
translate+scale + style), and `pug` (group translate + ellipse rotates)
stay omitted — Native ignores those transforms; baking would invent
markup.

Faku mapping and registration code stays GPL-3.0-only; these SVG
files remain MIT.
