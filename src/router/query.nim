## Typed query-string accessors and URL query mutators.

import std/[options, strutils, tables, uri]

import router/location
import router/state
import router/trie

proc getFirstQueryRaw(key: string): Option[string] {.inline.} =
  ensureQueryLoaded()
  if cachedQueryTable.hasKey(key):
    let vals = cachedQueryTable[key]
    if vals.len > 0:
      return some(vals[0])
  return none(string)

type QueryOptionValue* = object
  key*: string

proc getQuery*(key: string): QueryOptionValue {.inline.} =
  QueryOptionValue(key: key)

proc getQueryStr*(key: string): Option[string] =
  getFirstQueryRaw(key)

proc getQueryStr*(key: string, default: string): string =
  let opt = getFirstQueryRaw(key)
  if opt.isSome:
    opt.get()
  else:
    default

proc getQuery*(key: string, default: string): string =
  getQueryStr(key, default)

proc getQueryInt*(key: string): Option[int] =
  let opt = getFirstQueryRaw(key)
  if opt.isSome:
    try:
      return some(parseInt(opt.get().strip()))
    except ValueError:
      return none(int)
  return none(int)

proc getQueryInt*(key: string, default: int): int =
  let opt = getQueryInt(key)
  if opt.isSome:
    opt.get()
  else:
    default

proc getQuery*(key: string, default: int): int {.inline.} =
  getQueryInt(key, default)

proc getQueryFloat*(key: string): Option[float] =
  let opt = getFirstQueryRaw(key)
  if opt.isSome:
    try:
      return some(parseFloat(opt.get().strip()))
    except ValueError:
      return none(float)
  return none(float)

proc getQueryFloat*(key: string, default: float): float =
  let opt = getQueryFloat(key)
  if opt.isSome:
    opt.get()
  else:
    default

proc getQuery*(key: string, default: float): float {.inline.} =
  getQueryFloat(key, default)

proc getQueryBool*(key: string): Option[bool] =
  let opt = getFirstQueryRaw(key)
  if opt.isSome:
    try:
      return some(parseBoolValue(opt.get()))
    except ValueError:
      return none(bool)
  return none(bool)

proc getQueryBool*(key: string, default: bool): bool =
  let opt = getQueryBool(key)
  if opt.isSome:
    opt.get()
  else:
    default

proc getQueryBook*(key: string): Option[bool] {.inline.} =
  getQueryBool(key)

proc getQueryBook*(key: string, default: bool): bool {.inline.} =
  getQueryBool(key, default)

proc getQuery*(key: string, default: bool): bool {.inline.} =
  getQueryBool(key, default)

proc getQuerySeq*(key: string): Option[seq[string]] =
  ensureQueryLoaded()
  if cachedQueryTable.hasKey(key):
    let vals = cachedQueryTable[key]
    if vals.len > 0:
      return some(vals)
  return none(seq[string])

proc getQuerySeq*(key: string, default: seq[string]): seq[string] =
  let opt = getQuerySeq(key)
  if opt.isSome:
    opt.get()
  else:
    default

proc getQuery*(key: string, default: seq[string]): seq[string] {.inline.} =
  getQuerySeq(key, default)

converter queryOptionToString*(q: QueryOptionValue): Option[string] =
  getQueryStr(q.key)

converter queryOptionToInt*(q: QueryOptionValue): Option[int] =
  getQueryInt(q.key)

converter queryOptionToFloat*(q: QueryOptionValue): Option[float] =
  getQueryFloat(q.key)

converter queryOptionToBool*(q: QueryOptionValue): Option[bool] =
  getQueryBool(q.key)

converter queryOptionToSeq*(q: QueryOptionValue): Option[seq[string]] =
  getQuerySeq(q.key)

proc isSome*(q: QueryOptionValue): bool {.inline.} =
  getQueryStr(q.key).isSome

proc isNone*(q: QueryOptionValue): bool {.inline.} =
  getQueryStr(q.key).isNone

proc get*(q: QueryOptionValue): string {.inline.} =
  getQueryStr(q.key).get()

proc get*(q: QueryOptionValue, otherwise: string): string {.inline.} =
  getQueryStr(q.key, otherwise)

proc `==`*(q: QueryOptionValue, rhs: Option[string]): bool {.inline.} =
  getQueryStr(q.key) == rhs

proc `==`*(q: QueryOptionValue, rhs: Option[int]): bool {.inline.} =
  getQueryInt(q.key) == rhs

proc `==`*(q: QueryOptionValue, rhs: Option[bool]): bool {.inline.} =
  getQueryBool(q.key) == rhs

proc `==`*(q: QueryOptionValue, rhs: Option[seq[string]]): bool {.inline.} =
  getQuerySeq(q.key) == rhs

proc `$`*(q: QueryOptionValue): string {.inline.} =
  $getQueryStr(q.key)

# ---------------------------------------------------------------------------
# Write / navigate helpers (hash route + `?query`)
# ---------------------------------------------------------------------------

proc copyQueryTable(): Table[string, seq[string]] =
  ensureQueryLoaded()
  result = initTable[string, seq[string]]()
  for k, vals in cachedQueryTable:
    result[k] = vals

proc queryTableToString(t: Table[string, seq[string]]): string =
  var parts: seq[string]
  for k, vals in t.pairs:
    for v in vals:
      parts.add(encodeUrl(k) & "=" & encodeUrl(v))
  parts.join("&")

proc hrefWithQuery*(path: string; pairs: openArray[(string, string)]): string =
  ## Build `/todos?filter=active&q=milk` from a path and key/value pairs.
  ## Empty values are skipped.
  var p = path.strip()
  if p.startsWith("#"):
    p = p[1 ..^ 1]
  if not p.startsWith("/"):
    p = "/" & p
  let qIdx = p.find('?')
  if qIdx >= 0:
    p = p[0 ..< qIdx]
  var parts: seq[string]
  for (k, v) in pairs:
    if v.len > 0:
      parts.add(encodeUrl(k) & "=" & encodeUrl(v))
  if parts.len == 0:
    return p
  p & "?" & parts.join("&")

proc navigateWithQuery(pairs: openArray[(string, string)]; replaceAll: bool) =
  ## Apply query updates on the **current** route and navigate.
  ## Empty value → remove that key. `replaceAll` replaces the whole query.
  var t =
    if replaceAll:
      initTable[string, seq[string]]()
    else:
      copyQueryTable()
  for (k, v) in pairs:
    if v.len == 0:
      t.del(k)
    else:
      t[k] = @[v]
  let q = queryTableToString(t)
  let route = getRoute()
  if q.len == 0:
    navigateTo(route)
  else:
    navigateTo(route & "?" & q)

proc setUrlQuery*(key, value: string) =
  ## Set one query param on the current hash route.
  ## `setUrlQuery("filter", "active")` → `#/todos?filter=active`
  ## Pass `value = ""` to remove the key.
  navigateWithQuery([(key, value)], replaceAll = false)

proc setUrlQuery*(pairs: openArray[(string, string)]) =
  ## Merge several query params at once.
  ##   setUrlQuery([("filter", "active"), ("q", "milk")])
  navigateWithQuery(pairs, replaceAll = false)

proc replaceUrlQuery*(pairs: openArray[(string, string)]) =
  ## Replace the entire query string with `pairs` (drops unspecified keys).
  navigateWithQuery(pairs, replaceAll = true)

proc removeUrlQuery*(keys: varargs[string]) =
  ## Remove one or more query keys from the current URL.
  var pairs: seq[(string, string)]
  for k in keys:
    pairs.add((k, ""))
  navigateWithQuery(pairs, replaceAll = false)

proc addUrlQuery*(key, value: string) {.inline.} =
  ## Alias for `setUrlQuery` (set/overwrite a single key).
  setUrlQuery(key, value)

proc addUrlQuery*(pair: (string, string)) {.inline.} =
  ## `addUrlQuery(("filter", "completed"))`
  setUrlQuery(pair[0], pair[1])
