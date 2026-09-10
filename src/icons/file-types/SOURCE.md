# Material file icons

This directory contains a curated subset of the
[Material Icon Theme](https://github.com/PKief/vscode-material-icon-theme)
file icons (94 SVGs: first-cut coding-agent languages, a
second-cut language/data expansion, a third-cut tooling
subset, a fourth-cut frameworks/meta subset, a fifth-cut
media/config swap, a sixth-cut cert/lock/exe/nginx, a
seventh-cut cmake/coffee/gitlab/gradle/kubernetes/tex, an
eighth-cut crystal/elm/erlang/haxe/jinja/xaml/diff/file, plus
a ninth-cut julia/prettier/kotlin dialect-workaround swap). That project is MIT; see its
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
there are no `<defs>` or `url(#)`. Paths and viewBoxes are otherwise
unchanged. `lock.svg` registers as
`lockfile` (`app:lockfile`) so it does not collide with chrome Browser
address `app:lock`. Waku `nest` stays omitted: stripping the root
`style="enable-background:…"` still leaves a path
`transform="translate(…) scale(…)"` (and a path `style="fill:…"`)
that Native ignores; baking that path would invent markup. `graphql`
(`transform=` on connecting bars), `clojure` (`transform=`),
`editorconfig` (`transform=`), `helm` (`transform=`), and `pug` stay
omitted — Native ignores those transforms.

Faku mapping and registration code stays GPL-3.0-only; these SVG
files remain MIT.
