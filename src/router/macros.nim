## Compile-time router construction and `addHandler` macro.

import std/[macros, sets, strutils, tables]

import router/guards
import router/path
import router/registration
import router/trie
import router/types

var ctRegisteredRoutes {.compileTime.} = initTable[string, int]()

proc resetCompileTimeRoutes*() {.compileTime.} =
  ## Clears the compile-time route registry (useful in test suites).
  ctRegisteredRoutes.clear()

proc registerRouteAtCompileTime*(canonicalSig, pattern: string, line: int) {.compileTime.} =
  if canonicalSig in ctRegisteredRoutes:
    if ctRegisteredRoutes[canonicalSig] != line:
      error(
        "Duplicate route registration detected at compile time for route '" &
          pattern & "' (canonical signature: '" & canonicalSig & "').",
      )
  else:
    ctRegisteredRoutes[canonicalSig] = line

proc extractGuardSeqExpr(guardsNode: NimNode): NimNode {.compileTime.} =
  var bracketNode: NimNode = nil
  if guardsNode.kind == nnkPrefix and guardsNode[0].eqIdent("@") and
      guardsNode[1].kind == nnkBracket:
    bracketNode = guardsNode[1]
  elif guardsNode.kind == nnkBracket:
    bracketNode = guardsNode

  if not bracketNode.isNil:
    var converted = newNimNode(nnkBracket)
    for elem in bracketNode:
      converted.add(newCall(bindSym"toGuardProc", elem))
    return prefix(converted, "@")
  else:
    return quote:
      block:
        var res: seq[GuardProc] = @[]
        for item in `guardsNode`:
          res.add(toGuardProc(item))
        res

macro karaxRouter*(args: varargs[untyped]): KaraxRouter =
  var guardsExpr = newNimNode(nnkBracket)
  var ignoreExpr = newNimNode(nnkBracket)
  var posIdx = 0

  for arg in args:
    if arg.kind in {nnkExprEqExpr, nnkAsgn}:
      let key = arg[0].strVal
      case key
      of "guards":
        guardsExpr = extractGuardSeqExpr(arg[1])
      of "ignoreRoutes":
        ignoreExpr = arg[1]
      else:
        error(
          "Unknown parameter '" & key &
            "' for karaxRouter. Expected 'guards' or 'ignoreRoutes'.",
          arg,
        )
    else:
      if posIdx == 0:
        guardsExpr = extractGuardSeqExpr(arg)
      elif posIdx == 1:
        ignoreExpr = arg
      else:
        error("Too many arguments to karaxRouter.", arg)
      inc posIdx

  result = quote:
    createKaraxRouterRuntime(`guardsExpr`, `ignoreExpr`)

macro fastKaraxRouter*(args: varargs[untyped]): KaraxRouter =
  result = newCall(bindSym"karaxRouter")
  for a in args:
    result.add(a)

proc buildParamConversionExpr(
    paramIdent: NimNode, pKind: ParamKind, paramsTableSym: NimNode, paramName: string
): NimNode {.compileTime.} =
  let rawLookup = newCall(bindSym"[]", paramsTableSym, newLit(paramName))
  let parsedExpr =
    case pKind
    of pkString:
      rawLookup
    of pkInt:
      newCall(bindSym"parseInt", rawLookup)
    of pkFloat:
      newCall(bindSym"parseFloat", rawLookup)
    of pkBool:
      newCall(bindSym"parseBoolValue", rawLookup)
  result = newLetStmt(paramIdent, parsedExpr)

proc replaceParamIdents(
    node: NimNode, paramNames: HashSet[string]
): NimNode {.compileTime.} =
  result = copyNimNode(node)
  for child in node:
    result.add(replaceParamIdents(child, paramNames))

proc buildHandlerClosure(
    patternLit: string,
    params: seq[tuple[name: string, kind: ParamKind]],
    handlerExpr: NimNode,
): NimNode {.compileTime.} =
  let paramsSym = genSym(nskParam, "params")
  let dataSym = genSym(nskParam, "data")
  var bodyStmts = newStmtList()

  var paramIdents: seq[NimNode] = @[]
  var paramNameSet = initHashSet[string]()
  for p in params:
    let pIdent = ident(p.name)
    paramIdents.add(pIdent)
    paramNameSet.incl(p.name)
    bodyStmts.add(buildParamConversionExpr(pIdent, p.kind, paramsSym, p.name))

  case handlerExpr.kind
  of nnkCall, nnkCommand:
    var usedParams = initHashSet[string]()
    proc collectIdents(n: NimNode) =
      if n.kind == nnkIdent:
        let s = n.strVal
        if s in paramNameSet:
          usedParams.incl(s)
      for c in n:
        collectIdents(c)

    for i in 1 ..< handlerExpr.len:
      collectIdents(handlerExpr[i])

    for i in 1 ..< handlerExpr.len:
      let arg = handlerExpr[i]
      if arg.kind == nnkIdent:
        let argName = arg.strVal
        if argName notin paramNameSet:
          let errMsg =
            "Route '" & patternLit & "' does not define parameter '" & argName & "'."
          bodyStmts.add(
            quote do:
              when not declared(`arg`):
                {.error: `errMsg`.}
          )

    if params.len > 0 and handlerExpr.len - 1 != params.len and
        usedParams.len < params.len:
      error(
        "Route '" & patternLit & "' defines " & $params.len &
          " parameter(s), but handler call '" & handlerExpr.repr &
          "' does not match all route parameters.",
        handlerExpr,
      )

    let callExpr = replaceParamIdents(handlerExpr, paramNameSet)
    bodyStmts.add(callExpr)
  else:
    if params.len == 0:
      bodyStmts.add(
        quote do:
          when compiles(`handlerExpr`(`dataSym`)):
            `handlerExpr`(`dataSym`)
          elif compiles(`handlerExpr`()):
            `handlerExpr`()
          else:
            {.
              error:
                "Route handler for '" & `patternLit` &
                "' must accept () or (RouterData) and return VNode."
            .}
      )
    else:
      var callWithoutData = newCall(handlerExpr)
      var callWithData = newCall(handlerExpr)
      for pIdent in paramIdents:
        callWithoutData.add(pIdent)
        callWithData.add(pIdent)
      callWithData.add(dataSym)

      bodyStmts.add(
        quote do:
          when compiles(`callWithoutData`):
            `callWithoutData`
          elif compiles(`callWithData`):
            `callWithData`
          else:
            {.
              error:
                "Route handler for '" & `patternLit` &
                "' does not match extracted parameter types."
            .}
      )

  result = quote:
    RouteHandlerProc(
      proc(`paramsSym`: Table[string, string], `dataSym`: RouterData): VNode =
        `bodyStmts`
    )

macro addHandler*(
    router: KaraxRouter, pattern: static[string], args: varargs[untyped]
): untyped =
  if args.len == 0:
    error("addHandler requires a handler proc/call and/or `guards = @[...]`.", router)

  var parsed: ParsedRoutePattern
  try:
    parsed = parseRoutePattern(pattern)
  except ValueError as e:
    error("Invalid route pattern '" & pattern & "': " & e.msg, router)

  var handlerNode: NimNode = nil
  var guardsNode: NimNode = nil

  for arg in args:
    if arg.kind in {nnkExprEqExpr, nnkAsgn}:
      let key = arg[0].strVal
      case key
      of "guards":
        guardsNode = arg[1]
      of "handler", "action":
        handlerNode = arg[1]
      else:
        error(
          "Unknown named argument '" & key & "' in addHandler. Allowed: handler, guards.",
          arg,
        )
    else:
      if handlerNode.isNil:
        handlerNode = arg
      elif guardsNode.isNil:
        guardsNode = arg
      else:
        error(
          "Too many arguments passed to addHandler for route '" & pattern & "'.", arg
        )

  if handlerNode.isNil and not guardsNode.isNil:
    let convertedGuards = extractGuardSeqExpr(guardsNode)
    let patLit = newLit(pattern)
    return quote:
      registerGuardsRuntime(`router`, `patLit`, `convertedGuards`)

  let canonicalSig = parsed.canonicalSignature
  registerRouteAtCompileTime(canonicalSig, pattern, instantiationInfo().line)

  let wrapperClosure = buildHandlerClosure(pattern, parsed.params, handlerNode)
  let patLit = newLit(pattern)

  if guardsNode.isNil:
    result = quote:
      registerRouteRuntime(`router`, `patLit`, `wrapperClosure`)
  else:
    let convertedGuards = extractGuardSeqExpr(guardsNode)
    result = quote:
      registerRouteRuntime(`router`, `patLit`, `wrapperClosure`, `convertedGuards`)
