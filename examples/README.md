# Examples

## Router + Runes (`router_runes/`)

Small Karax app showing:

- **Router** — `karaxRouter`, typed routes (`/user/{id:int}`), global `authGuard` with redirect to `/login`, `navigateTo`, `getRoute`, and `getQuery`.
- **Runes** — `state`, `derived`, and automatic batched `redraw()` when values change.
- **Persisted** — `persisted("karax-utils-demo-theme", …)` for theme in `localStorage` (survives refresh).
- **Tailwind CDN** — layout/theme via utility classes + `karax_utils/tailwind` (`cn` / `withClass`); no custom CSS file.

### Build and run

From the repository root:

```bash
nim js -d:release --path:src \
  -o:examples/router_runes/app.js \
  examples/router_runes/app.nim
```

Open `examples/router_runes/index.html` in a browser (file URL is fine for this demo).

### Editor / LSP (nimsuggest / nimlangserver)

This example is a **JavaScript** Karax app. The language server defaults to the **native** backend, so you often get false errors (`importjs requires JavaScript target`, broken `buildHtml` blocks, unresolved `router/` imports) even when `nim js` succeeds.

Mitigations in this repo:

- `examples/router_runes/app.nim.cfg` — sets `backend = "js"` and `path = "../../src"`.
- `.vscode/settings.json` — maps this example to `app.nim` as the nimsuggest root and sets `nim.useNimCheck` to `false` (so diagnostics use nimsuggest with that cfg instead of native `nim check`).

With **NimLang** (`NimLang.nimlang`) and **nimlangserver** 1.16+, use the command palette:

- **Nim: Restarts nimsuggest** — after changing cfg or when diagnostics look stale
- **Nim: Clear internal caches** — if symbols or errors stick around
- **Nim: List candidate nim projects** — verify the server picked `app.nim` for the example

Ensure **Nim › Provider** is `lsp` (default) and **Nim › Use Nim Check** stays off for this JS example.
Set **Nim › Lsp: Path** only if `nimlangserver` is not on your `PATH`.

Some noise is normal: Karax `buildHtml` and router `addHandler` macros are hard for nimsuggest. Treat a clean `nim js` build as the source of truth.

### Things to try

1. Home — links into the demos.
2. **Bindings** (`#/bindings`) — `Input(bindValue=…)`, `withClass`, `withAttr`, counter/step.
3. **Todos** (`#/todos`) — add / toggle / filter / clear; **persisted** in `localStorage`; filters use `addUrlQuery` (`#/todos?filter=active`).
4. Toggle theme in the footer — survives refresh.
5. **Admin** — redirects to login until you sign in.
