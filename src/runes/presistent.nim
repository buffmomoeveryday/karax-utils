## persisted.nim: localStorage/sessionStorage-backed state with cross-tab sync
## (like runed's PersistedState) built on runes.nim. JS backend only.
##
##   let theme = persisted("theme", "light")
##   theme.value = "dark"        # saved + other tabs update + UI redraws
##
## A PersistedState IS a State[T], so derived/effect/mutate all work on it.

import std/[json, tables]
import runes

type
  StorageKind* = enum
    skLocal = "localStorage"
    skSession = "sessionStorage"

  PersistedState*[T] = ref object of State[T]
    key: string
    default: T

var registry: Table[string, Source] # same key in one tab -> same instance

# ---- raw browser access (try/catch inside JS: private mode, quota, etc.) ----
proc storeGet(area, key: cstring): cstring {.
  # Arrow IIFE: a plain `function(){}` would lose `this`, and callers may
  # pass closure fields (`this.*`) as arguments — those must resolve in
  # the enclosing scope or every access silently fails in the catch below.
  importjs: "(() => { try { return window[#].getItem(#) } catch(e) { return null } })()"
.}

proc storeSet(
  area, key, val: cstring
) {.importjs: "(() => { try { window[#].setItem(#,#) } catch(e) {} })()".}

proc listenStorage(
  area: cstring, cb: proc(key, newValue: cstring) {.closure.}
) {.
  importjs:
    "window.addEventListener('storage', function(e){ if (e.storageArea === window[#]) #(e.key, e.newValue); })"
.}

proc persisted*[T](
    key: string,
    default: T,
    storage = skLocal,
    syncTabs = true,
    serialize: proc(v: T): string {.closure.} = nil,
    deserialize: proc(s: string): T {.closure.} = nil,
): PersistedState[T] =
  ## Create (or fetch) a persisted state. Defaults to JSON (std/json) for
  ## serialization; pass `serialize`/`deserialize` to customize.
  let rk = $storage & ":" & key
  if rk in registry:
    return PersistedState[T](registry[rk])

  let ser: proc(v: T): string {.closure.} =
    if serialize != nil:
      serialize
    else:
      (
        proc(v: T): string =
          $(%v)
      )
  let deser: proc(s: string): T {.closure.} =
    if deserialize != nil:
      deserialize
    else:
      (
        proc(s: string): T =
          parseJson(s).to(T)
      )

  # load initial value (falls back to default on missing/corrupt data)
  var initial = default
  let raw = storeGet(($storage).cstring, key.cstring)
  if not raw.isNil:
    try:
      initial = deser($raw)
    except CatchableError:
      discard

  # `val` is private to runes, so seed it through the public `value=` setter
  # (no subscribers exist yet, so the scheduled redraw is a harmless no-op).
  let p = PersistedState[T](key: key, default: default)
  p.value = initial
  registry[rk] = p
  let area = $storage

  # write-through: runs whenever the state changes (first run only tracks)
  var first = true
  discard createEffect(
    proc() =
      let s = ser(p.value) # reading .value subscribes
      if first:
        first = false
        return
      if storeGet(area.cstring, key.cstring) != s.cstring:
        storeSet(area.cstring, key.cstring, s.cstring)
  )

  # cross-tab sync (browsers only fire `storage` in OTHER tabs)
  if syncTabs and storage == skLocal:
    listenStorage(
      area.cstring,
      proc(k, nv: cstring) =
        if k.isNil or $k == key: # nil key => storage.clear()
          if nv.isNil:
            p.value = p.default
          else:
            try:
              p.value = deser($nv)
            except CatchableError:
              discard
      ,
    )
  p

proc reset*[T](p: PersistedState[T]) =
  ## Back to the default value (also persisted).
  p.value = p.default
