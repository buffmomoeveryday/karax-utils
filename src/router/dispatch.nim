## Route matching, guard execution, and Karax renderer integration.

import std/[sets, tables]

when defined(js):
  import karax/karax

import router/guards
import router/lifecycle
import router/location
import router/path
import router/registration
import router/state
import router/trie
import router/types

proc matchRoute*(
    router: KaraxRouter, routePath: string, params: var Table[string, string]
): int =
  let norm = normalizeRoutePath(routePath)
  if router.staticMap.hasKey(norm):
    return router.staticMap[norm]
  let segs = splitRouteSegments(norm)
  matchTrie(router.trieRoot, segs, 0, params)

proc finishDispatch(node: VNode): VNode =
  flushLifecycle()
  node

proc dispatchRoute*(router: KaraxRouter, data: RouterData = nil): VNode =
  activeRouter = router
  syncLocationState(data)

  var effectiveData = data
  if effectiveData.isNil:
    when defined(js):
      effectiveData = RouterData(
        hashPart: cstring(currentRawHash), queryString: cstring(currentRawQuery)
      )
    else:
      effectiveData = RouterData(hashPart: currentRawHash, queryString: currentRawQuery)

  var targetRoute = currentRoutePath
  var redirectHop = 0
  const maxRedirects = 8

  while redirectHop <= maxRedirects:
    currentRoutePath = targetRoute

    if targetRoute notin router.ignoreRoutes:
      let globalResult = runGuardChain(
        router.guards, targetRoute, router.blockedHandler, effectiveData
      )
      case globalResult.outcome
      of gcoContinue:
        discard
      of gcoBlocked, gcoRender:
        return finishDispatch(globalResult.node)
      of gcoRedirect:
        targetRoute = globalResult.redirectTarget
        currentRawHash = "#" & targetRoute
        setBrowserHashIfAvailable(currentRawHash)
        inc redirectHop
        continue

    var extractedParams = initTable[string, string]()
    let matchIdx = router.matchRoute(targetRoute, extractedParams)

    if matchIdx < 0:
      if not router.notFoundHandler.isNil:
        return finishDispatch(router.notFoundHandler(targetRoute, effectiveData))
      return finishDispatch(defaultNotFoundView(targetRoute, effectiveData))

    let entry = router.routes[matchIdx]

    let routeResult = runGuardChain(
      entry.guards, targetRoute, router.blockedHandler, effectiveData
    )
    case routeResult.outcome
    of gcoContinue:
      discard
    of gcoBlocked, gcoRender:
      return finishDispatch(routeResult.node)
    of gcoRedirect:
      targetRoute = routeResult.redirectTarget
      currentRawHash = "#" & targetRoute
      setBrowserHashIfAvailable(currentRawHash)
      inc redirectHop
      continue

    if not entry.handler.isNil:
      return finishDispatch(entry.handler(extractedParams, effectiveData))
    if not router.notFoundHandler.isNil:
      return finishDispatch(router.notFoundHandler(targetRoute, effectiveData))
    return finishDispatch(defaultNotFoundView(targetRoute, effectiveData))

  if not router.notFoundHandler.isNil:
    return finishDispatch(router.notFoundHandler(targetRoute, effectiveData))
  finishDispatch(defaultNotFoundView(targetRoute, effectiveData))

proc toRenderer*(router: KaraxRouter): proc(data: RouterData): VNode {.closure.} =
  result = proc(data: RouterData): VNode =
    router.dispatchRoute(data)

when defined(js):
  proc setRenderer*(
      router: KaraxRouter,
      root: cstring = "ROOT",
      clientPostRenderCallback: proc(data: RouterData) = nil,
  ): KaraxInstance {.discardable.} =
    activeRouter = router
    var hasDom = false
    {.
      emit: [
        hasDom, " = (typeof document !== 'undefined' && typeof window !== 'undefined');"
      ]
    .}
    if hasDom:
      result = karax.setRenderer(router.toRenderer(), root, clientPostRenderCallback)

else:
  proc setRenderer*(
      router: KaraxRouter,
      root: string = "ROOT",
      clientPostRenderCallback: proc(data: RouterData) = nil,
  ) {.discardable.} =
    activeRouter = router
