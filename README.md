# karax-utils

Utilities for [Karax](https://github.com/karaxnim/karax) apps on the JavaScript backend.

- **Router** — hash routes, typed params, compile-time duplicate checks, and navigation guards.
- **Runes** — `state`, `derived`, and `effect`. Writes schedule one batched `redraw()`.
- **Persisted state** — `localStorage` / `sessionStorage` with cross-tab sync.
- **Bindings** — two-way inputs bound to rune state, with caret restore after redraw.
- **View helpers** — Tailwind class composition, keyed lists, conditional nodes, and mount/destroy hooks.
- **Leaflet** — typed wrapper that loads the Leaflet CDN and mounts a map.

## Requirements

- Nim `>= 2.2.12`
- Karax `>= 1.5.0`
- The JavaScript backend (`nim js`). These modules use the DOM and are not for the native backend.

## Use it

Clone the repo and pass `src` on the compiler path:

```bash
nim js --path:/path/to/karax-utils/src -o:app.js app.nim
```

Or depend on it from a `.nimble` file (the GitHub repo is private):

```nim
requires "https://github.com/buffmomoeveryday/karax-utils >= 0.1.0"
```

Import the module you need. There is no single barrel export.

```nim
include karax/prelude

import router/router
import runes/runes
import runes/presistent
import karax_utils/bindings
import karax_utils/tailwind
import karax_utils/lists
import karax_utils/whenview
import karax_utils/lifecycle
```

## Router

Hash router. Patterns such as `/user/{id:int}` are checked at compile time, including duplicate routes. Param types are `string`, `int`, `float`, and `bool`.

```nim
import router/router

proc authGuard(route: string): GuardVerdict =
  if route.startsWith("/admin") and not isLoggedIn.value:
    redirectTo("/login")
  else:
    allowRoute()

let appRouter = karaxRouter(guards = @[authGuard], ignoreRoutes = @["/login"])

proc userView(id: int): VNode =
  buildHtml(tdiv):
    text "User " & $id

appRouter.addHandler("/", homeView)
appRouter.addHandler("/user/{id:int}", userView(id))
appRouter.addHandler("/admin", adminView, guards = @[authGuard])

setRenderer(appRouter)
```

`navigateTo("/todos")` updates the hash. `getRoute()` is the current path. Query helpers read and write the hash query: `getQuery`, `getQueryInt`, `addUrlQuery`, `setUrlQuery`, `replaceUrlQuery`, and `removeUrlQuery`.

Guards return `allowRoute()`, `blockRoute()`, `redirectTo(path)`, or `renderGuardNode(vnode)`. A guard can also be a `bool`, a redirect `string`, an `Option[string]`, or a `VNode`.

## Runes

Svelte-style state. Assigning `.value` notifies subscribers and schedules one redraw.

```nim
import runes/runes

let count = state(0)
let doubled = derived(int):
  count.value * 2

let stop = effect:
  echo "count is ", count.value

count.value = count.value + 1
count.update(proc(v: var int) = v += 1)
count.mutate:
  it += 1
```

`untrack` reads state without subscribing. `effect` returns a proc that stops the effect.

## Persisted state

`PersistedState[T]` is a `State[T]`, so `derived`, `effect`, and `mutate` work on it. Values are stored as JSON unless you pass `serialize` / `deserialize`.

```nim
import runes/presistent

let theme = persisted("theme", "light")          # localStorage
let tab = persisted("tab", "a", storage = skSession)

theme.value = "dark"   # saved, other tabs update, UI redraws
theme.reset()
```

## Bindings

Karax `buildHtml` treats `input` as a tag, so two-way binding is a component instead of `bind:value`.

```nim
import karax_utils/bindings

let name = state("")
let step = state(1)
let done = state(false)

Input(bindValue = name, class = "w-full", placeholder = "Name")
Input(bindValue = step, class = "w-full", minVal = 1)
Input(bindValue = done)
```

`textInput`, `textareaInput`, `numberInput`, and `checkboxInput` are the same bindings as procedures. Int fields use `inputmode=numeric` so the caret can be restored after Karax redraws.

## Classes and attributes

`cn`, `withClass`, `removeClass`, and `toggleClass` only edit the `class` string. They do not generate CSS. Load Tailwind yourself (CDN or a build).

```nim
import karax_utils/tailwind

var btn = buildHtml(button(class = "px-3 py-2")): text "Save"
btn.withClass("bg-red-600", step.value > 10)
btn.withAttr("disabled", step.value <= 1)
btn.removeClass("cursor-pointer", step.value <= 1)
```

`cn("px-3", ("bg-red-600", on))` joins class fragments and keeps only the pairs whose flag is true.

## Lists and conditionals

`each` sets a stable `vnode.id` from a key so Karax can reuse DOM nodes across reorder and delete.

```nim
import karax_utils/lists
import karax_utils/whenview

let list = buildHtml(ul())
list.each(todos.value, it.id):
  buildHtml(li):
    text it.title

whenView(todos.value.len == 0):
  buildHtml(p): text "Nothing here"
```

`show(cond, node)` and `hide(cond, node)` return the node or `nil`.

## Lifecycle

View procs rebuild a `VNode` on every redraw, so hooks go inside the view with a stable string key. `dispatchRoute` runs mount when the key becomes active and destroy when a later dispatch drops it.

```nim
import karax_utils/lifecycle

proc homeView(): VNode =
  onMount("home"):
    echo "entered"
  onDestroy("home"):
    echo "left"
  buildHtml(tdiv): text "Home"
```

## Leaflet

```nim
import karax_utils/leaflet

var map: LeafletMap

proc mapView(): VNode =
  onMount("map"):
    loadLeaflet().then(
      proc() =
        mountMap(
          "map-el",
          defaultMapConfig(latLng(27.7172, 85.3240), 13),
          proc(m: LeafletMap) =
            map = m
            discard m.addMarker(latLng(27.7172, 85.3240), "Kathmandu"),
        )
    )
  onDestroy("map"):
    map.destroy()
    map = nil
  buildHtml(tdiv(id = "map-el", class = "h-80 w-full"))
```

`loadLeaflet` injects the Leaflet CSS and JS from unpkg. `loadCss` and `loadScript` live in `karax_utils/jsbind` if you need them on their own.

## Example

`examples/router_runes/` is a small app that uses the router, runes, persisted theme and todos, bindings, Tailwind classes, and `each`. Details and editor setup are in [examples/README.md](examples/README.md).

From the repository root:

```bash
nim js -d:release --path:src \
  -o:examples/router_runes/app.js \
  examples/router_runes/app.nim
```

Open `examples/router_runes/index.html` in a browser.

## License

MIT
