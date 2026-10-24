## Runtime route registration and default error views.

import std/[sets, tables]

import karax/vdom

when defined(js):
  import karax/karaxdsl

import router/path
import router/state
import router/trie
import router/types

proc defaultNotFoundView*(route: string, data: RouterData): VNode =
  when defined(js):
    result = buildHtml(tdiv(class = "karax-router-not-found")):
      h1(text("404 - Page Not Found"))
      p(text("No route matched: " & route))
  else:
    result = newVNode(VNodeKind.tdiv)
    let heading = newVNode(VNodeKind.h1)
    heading.add(newVNode(VNodeKind.verbatim))
    result.add(heading)

proc defaultBlockedView*(route: string, data: RouterData): VNode =
  when defined(js):
    result = buildHtml(tdiv(class = "karax-router-blocked")):
      h1(text("403 - Access Denied"))
      p(text("Navigation blocked by route guard for: " & route))
  else:
    result = newVNode(VNodeKind.tdiv)

proc createKaraxRouterRuntime*(
    guards: openArray[GuardProc] = [], ignoreRoutes: openArray[string] = []
): KaraxRouter =
  var ignoreSet = initHashSet[string]()
  for r in ignoreRoutes:
    ignoreSet.incl(normalizeRoutePath(r))
  result = KaraxRouter(
    guards: @guards,
    ignoreRoutes: ignoreSet,
    routes: @[],
    staticMap: initTable[string, int](),
    trieRoot: newTrieNode(),
    routeGuards: initTable[string, seq[GuardProc]](),
    notFoundPath: "/404",
    notFoundHandler: defaultNotFoundView,
    blockedHandler: defaultBlockedView,
  )
  activeRouter = result

proc registerRouteRuntime*(
    router: KaraxRouter,
    pattern: string,
    handler: RouteHandlerProc,
    guards: openArray[GuardProc] = [],
) =
  let parsed = parseRoutePattern(pattern)
  let norm = parsed.normalized

  var combinedGuards: seq[GuardProc] = @[]
  if router.routeGuards.hasKey(norm):
    combinedGuards.add(router.routeGuards[norm])
  for g in guards:
    combinedGuards.add(g)
  router.routeGuards[norm] = combinedGuards

  var existingIdx = -1
  for i, entry in router.routes:
    if entry.normalizedPattern == norm:
      existingIdx = i
      break

  if existingIdx >= 0:
    if not handler.isNil:
      router.routes[existingIdx].handler = handler
    router.routes[existingIdx].guards = combinedGuards
    return

  let idx = router.routes.len
  let entry = RouteEntry(
    pattern: pattern,
    normalizedPattern: norm,
    segments: parsed.segments,
    handler: handler,
    guards: combinedGuards,
    isStatic: parsed.isStatic,
  )
  router.routes.add(entry)
  if parsed.isStatic:
    router.staticMap[norm] = idx
  else:
    insertTrie(router.trieRoot, parsed.segments, idx)

proc registerGuardsRuntime*(
    router: KaraxRouter, pattern: string, guards: openArray[GuardProc]
) =
  let parsed = parseRoutePattern(pattern)
  let norm = parsed.normalized
  var current = router.routeGuards.getOrDefault(norm, @[])
  for g in guards:
    current.add(g)
  router.routeGuards[norm] = current

  for i in 0 ..< router.routes.len:
    if router.routes[i].normalizedPattern == norm:
      router.routes[i].guards = current
      break

proc addNotFoundHandler*(
    router: KaraxRouter, path: string, handler: proc(): VNode {.closure.}
) =
  router.notFoundPath = normalizeRoutePath(path)
  router.notFoundHandler = proc(route: string, data: RouterData): VNode =
    handler()

proc addNotFoundHandler*(
    router: KaraxRouter, path: string, handler: proc(route: string): VNode {.closure.}
) =
  router.notFoundPath = normalizeRoutePath(path)
  router.notFoundHandler = proc(route: string, data: RouterData): VNode =
    handler(route)

proc addNotFoundHandler*(
    router: KaraxRouter,
    path: string,
    handler: proc(data: RouterData): VNode {.closure.},
) =
  router.notFoundPath = normalizeRoutePath(path)
  router.notFoundHandler = proc(route: string, data: RouterData): VNode =
    handler(data)

proc addNotFoundHandler*(
    router: KaraxRouter, path: string, handler: NotFoundHandlerProc
) =
  router.notFoundPath = normalizeRoutePath(path)
  router.notFoundHandler = handler

proc addNotFoundHandler*(router: KaraxRouter, handler: proc(): VNode {.closure.}) =
  router.notFoundHandler = proc(route: string, data: RouterData): VNode =
    handler()

proc addNotFoundHandler*(
    router: KaraxRouter, handler: proc(route: string): VNode {.closure.}
) =
  router.notFoundHandler = proc(route: string, data: RouterData): VNode =
    handler(route)
