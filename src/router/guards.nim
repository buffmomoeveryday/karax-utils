## Navigation guard verdicts and guard proc adapters.

import std/options

import router/path
import router/types

proc allowRoute*(): GuardVerdict {.inline.} =
  GuardVerdict(kind: gvkAllow)

proc blockRoute*(): GuardVerdict {.inline.} =
  GuardVerdict(kind: gvkBlock)

proc redirectTo*(path: string): GuardVerdict {.inline.} =
  GuardVerdict(kind: gvkRedirect, target: normalizeRoutePath(path))

proc renderGuardNode*(node: VNode): GuardVerdict {.inline.} =
  GuardVerdict(kind: gvkRender, node: node)

converter boolToGuardVerdict*(allowed: bool): GuardVerdict =
  if allowed:
    GuardVerdict(kind: gvkAllow)
  else:
    GuardVerdict(kind: gvkBlock)

converter stringToGuardVerdict*(redirectPath: string): GuardVerdict =
  if redirectPath.len == 0:
    GuardVerdict(kind: gvkAllow)
  else:
    GuardVerdict(kind: gvkRedirect, target: normalizeRoutePath(redirectPath))

converter optionStringToGuardVerdict*(redirectOpt: Option[string]): GuardVerdict =
  if redirectOpt.isSome:
    GuardVerdict(kind: gvkRedirect, target: normalizeRoutePath(redirectOpt.get()))
  else:
    GuardVerdict(kind: gvkAllow)

converter vnodeToGuardVerdict*(node: VNode): GuardVerdict =
  if node.isNil:
    GuardVerdict(kind: gvkAllow)
  else:
    GuardVerdict(kind: gvkRender, node: node)

proc toGuardProc*(p: GuardProc): GuardProc {.inline.} =
  p

proc toGuardProc*(p: proc(route: string): bool {.closure.}): GuardProc =
  result = proc(route: string): GuardVerdict =
    if p(route):
      allowRoute()
    else:
      blockRoute()

proc toGuardProc*(p: proc(): bool {.closure.}): GuardProc =
  result = proc(route: string): GuardVerdict =
    if p():
      allowRoute()
    else:
      blockRoute()

proc toGuardProc*(p: proc(): GuardVerdict {.closure.}): GuardProc =
  result = proc(route: string): GuardVerdict =
    p()

proc toGuardProc*(p: proc(route: string): string {.closure.}): GuardProc =
  result = proc(route: string): GuardVerdict =
    let target = p(route)
    if target.len == 0:
      allowRoute()
    else:
      redirectTo(target)

proc toGuardProc*(p: proc(): string {.closure.}): GuardProc =
  result = proc(route: string): GuardVerdict =
    let target = p()
    if target.len == 0:
      allowRoute()
    else:
      redirectTo(target)

proc toGuardProc*(p: proc(route: string): Option[string] {.closure.}): GuardProc =
  result = proc(route: string): GuardVerdict =
    let target = p(route)
    if target.isSome:
      redirectTo(target.get())
    else:
      allowRoute()

proc toGuardProc*(p: proc(): Option[string] {.closure.}): GuardProc =
  result = proc(route: string): GuardVerdict =
    let target = p()
    if target.isSome:
      redirectTo(target.get())
    else:
      allowRoute()

proc toGuardProc*(p: proc(route: string): VNode {.closure.}): GuardProc =
  result = proc(route: string): GuardVerdict =
    let n = p(route)
    if n.isNil:
      allowRoute()
    else:
      renderGuardNode(n)

proc toGuardProc*(p: proc(): VNode {.closure.}): GuardProc =
  result = proc(route: string): GuardVerdict =
    let n = p()
    if n.isNil:
      allowRoute()
    else:
      renderGuardNode(n)

converter procBoolWithRouteToGuard*(
    p: proc(route: string): bool {.closure.}
): GuardProc =
  toGuardProc(p)

converter procBoolNoArgsToGuard*(p: proc(): bool {.closure.}): GuardProc =
  toGuardProc(p)

converter procVerdictNoArgsToGuard*(p: proc(): GuardVerdict {.closure.}): GuardProc =
  toGuardProc(p)

converter procStringWithRouteToGuard*(
    p: proc(route: string): string {.closure.}
): GuardProc =
  toGuardProc(p)

converter procStringNoArgsToGuard*(p: proc(): string {.closure.}): GuardProc =
  toGuardProc(p)

converter procOptStringWithRouteToGuard*(
    p: proc(route: string): Option[string] {.closure.}
): GuardProc =
  toGuardProc(p)

converter procOptStringNoArgsToGuard*(
    p: proc(): Option[string] {.closure.}
): GuardProc =
  toGuardProc(p)

converter procVNodeWithRouteToGuard*(
    p: proc(route: string): VNode {.closure.}
): GuardProc =
  toGuardProc(p)

converter procVNodeNoArgsToGuard*(p: proc(): VNode {.closure.}): GuardProc =
  toGuardProc(p)

type
  GuardChainOutcome* = enum
    gcoContinue
    gcoBlocked
    gcoRender
    gcoRedirect

proc runGuardChain*(
    guards: openArray[GuardProc],
    targetRoute: string,
    blockedHandler: NotFoundHandlerProc,
    data: RouterData,
): tuple[outcome: GuardChainOutcome, node: VNode, redirectTarget: string] =
  for guard in guards:
    if guard.isNil:
      continue
    let verdict = guard(targetRoute)
    case verdict.kind
    of gvkAllow:
      discard
    of gvkBlock:
      return (
        outcome: gcoBlocked,
        node: blockedHandler(targetRoute, data),
        redirectTarget: "",
      )
    of gvkRender:
      return (outcome: gcoRender, node: verdict.node, redirectTarget: "")
    of gvkRedirect:
      let nextTarget = normalizeRoutePath(verdict.target)
      if nextTarget != targetRoute:
        return (outcome: gcoRedirect, node: nil, redirectTarget: nextTarget)
  (outcome: gcoContinue, node: nil, redirectTarget: "")
