## Hash routing, browser location sync, and navigation.

import std/[strutils, tables, uri]

when defined(js):
  import karax/karax

import router/path
import router/state
import router/types

proc readBrowserHashAndSearch(): tuple[hashVal: string, searchVal: string] =
  when defined(js):
    var hasWindow = false
    {.
      emit: [
        hasWindow,
        " = (typeof window !== 'undefined' && typeof window.location !== 'undefined');",
      ]
    .}
    if hasWindow:
      var rawHash: cstring
      var rawSearch: cstring
      {.
        emit: [
          rawHash, " = window.location.hash || ''; ", rawSearch,
          " = window.location.search || '';",
        ]
      .}
      let h =
        if rawHash.isNil:
          ""
        else:
          $rawHash
      let s =
        if rawSearch.isNil:
          ""
        else:
          $rawSearch
      return (hashVal: h, searchVal: s)
    else:
      return (hashVal: currentRawHash, searchVal: currentRawQuery)
  else:
    result = (hashVal: currentRawHash, searchVal: currentRawQuery)

proc extractRouteAndQuery(
    rawHash, rawSearch: string
): tuple[route: string, query: string] =
  var h = rawHash.strip()
  if h.startsWith("#"):
    h = h[1 ..^ 1]

  var hashQuery = ""
  var routePart = h
  let qIdx = h.find('?')
  if qIdx >= 0:
    routePart = h[0 ..< qIdx]
    hashQuery = h[qIdx + 1 ..^ 1]

  var searchQuery = rawSearch.strip()
  if searchQuery.startsWith("?"):
    searchQuery = searchQuery[1 ..^ 1]

  let combinedQuery =
    if hashQuery.len > 0 and searchQuery.len > 0:
      searchQuery & "&" & hashQuery
    elif hashQuery.len > 0:
      hashQuery
    else:
      searchQuery

  result = (route: normalizeRoutePath(routePart), query: combinedQuery)

proc parseQueryIntoTable*(queryStr: string): Table[string, seq[string]] =
  result = initTable[string, seq[string]]()
  let trimmed =
    if queryStr.startsWith("?"):
      queryStr[1 ..^ 1]
    else:
      queryStr
  if trimmed.len == 0:
    return

  for pair in trimmed.split('&'):
    if pair.len == 0:
      continue
    let eqPos = pair.find('=')
    var rawKey = ""
    var rawVal = ""
    if eqPos >= 0:
      rawKey = pair[0 ..< eqPos]
      rawVal = pair[eqPos + 1 ..^ 1]
    else:
      rawKey = pair
      rawVal = ""

    let key = decodeUrl(rawKey)
    if key.len == 0:
      continue
    let val = decodeUrl(rawVal)

    if not result.hasKey(key):
      result[key] = @[]
    if ',' in val:
      for sub in val.split(','):
        result[key].add(sub)
    else:
      result[key].add(val)

proc syncLocationState*(data: RouterData = nil) =
  if not data.isNil:
    let h =
      when defined(js):
        if data.hashPart.isNil:
          ""
        else:
          $data.hashPart
      else:
        data.hashPart
    let q =
      when defined(js):
        if data.queryString.isNil:
          ""
        else:
          $data.queryString
      else:
        data.queryString
    currentRawHash = h
    currentRawQuery = q
  elif defined(js):
    let (h, s) = readBrowserHashAndSearch()
    currentRawHash = h
    currentRawQuery = s

  let (route, query) = extractRouteAndQuery(currentRawHash, currentRawQuery)
  currentRoutePath = route
  if query != cachedQuerySource:
    cachedQuerySource = query
    cachedQueryTable = parseQueryIntoTable(query)

proc setBrowserHashIfAvailable*(h: string) {.inline.} =
  when defined(js):
    let ch = cstring(h)
    {.
      emit: [
        "if (typeof window !== 'undefined' && typeof window.location !== 'undefined') { window.location.hash = ",
        ch, "; }",
      ]
    .}

proc setTestLocation*(hashOrUrl: string, search: string = "") =
  ## Sets the current location in non-JS or test environments (and updates browser hash on JS).
  var h = hashOrUrl.strip()
  if not h.startsWith("#") and h.len > 0:
    h = "#" & (if h.startsWith("/"): h else: "/" & h)
  currentRawHash = h
  currentRawQuery = search
  setBrowserHashIfAvailable(h)
  syncLocationState(nil)

proc navigateTo*(path: string) =
  ## Navigates to the given hash route and triggers a Karax redraw when on JS.
  var clean = path.strip()
  if clean.startsWith("#"):
    clean = clean[1 ..^ 1]
  if not clean.startsWith("/"):
    clean = "/" & clean
  currentRawHash = "#" & clean
  setBrowserHashIfAvailable(currentRawHash)
  syncLocationState(nil)
  when defined(js):
    if not kxi.isNil:
      redraw(kxi)

proc getRoute*(): string =
  ## Returns the normalized current hash route (e.g. `"/"`, `"/users/42"`).
  when defined(js):
    syncLocationState(nil)
  else:
    if cachedQuerySource == "\x00":
      syncLocationState(nil)
  result = currentRoutePath

proc ensureQueryLoaded*() {.inline.} =
  when defined(js):
    syncLocationState(nil)
  else:
    if cachedQuerySource == "\x00":
      syncLocationState(nil)
