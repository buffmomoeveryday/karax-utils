## Route path normalization and pattern parsing.

import std/[macros, sets, strutils]

import router/types

proc paramKindFromTypeName*(typeName: string): ParamKind =
  case typeName.toLowerAscii().strip()
  of "", "string", "str":
    pkString
  of "int", "int64", "int32", "uint":
    pkInt
  of "float", "float64", "float32":
    pkFloat
  of "bool", "boolean":
    pkBool
  else:
    raise newException(
      ValueError,
      "Unsupported parameter type '" & typeName &
        "'. Supported types: int, float, bool, string.",
    )

proc parseParamKindCT*(typeName: string): ParamKind {.compileTime.} =
  case typeName.toLowerAscii().strip()
  of "", "string", "str":
    pkString
  of "int", "int64", "int32", "uint":
    pkInt
  of "float", "float64", "float32":
    pkFloat
  of "bool", "boolean":
    pkBool
  else:
    error(
      "Unsupported route parameter type '" & typeName &
        "'. Supported types: int, float, bool, string."
    )

proc normalizeRoutePath*(path: string): string =
  ## Normalizes a route path so that "", "/", "#/", and "/users/" map canonically.
  var p = path.strip()
  if p.startsWith("#"):
    p = p[1 ..^ 1]
  let qIdx = p.find('?')
  if qIdx >= 0:
    p = p[0 ..< qIdx]
  if p.len == 0:
    return "/"
  if not p.startsWith("/"):
    p = "/" & p
  var collapsed = newStringOfCap(p.len)
  var prevSlash = false
  for ch in p:
    if ch == '/':
      if not prevSlash:
        collapsed.add(ch)
      prevSlash = true
    else:
      collapsed.add(ch)
      prevSlash = false
  if collapsed.len > 1 and collapsed.endsWith("/"):
    collapsed.setLen(collapsed.len - 1)
  result = collapsed

proc splitRouteSegments*(normPath: string): seq[string] =
  if normPath == "/" or normPath.len == 0:
    return @[]
  let trimmed =
    if normPath.startsWith("/"):
      normPath[1 ..^ 1]
    else:
      normPath
  if trimmed.len == 0:
    return @[]
  result = trimmed.split('/')

proc validateParamName*(paramName, pattern, seg: string) =
  if paramName.len == 0:
    raise newException(
      ValueError,
      "Missing parameter name in segment '" & seg & "' of route '" & pattern & "'.",
    )
  for cIdx, ch in paramName:
    if cIdx == 0 and not (ch in {'a' .. 'z', 'A' .. 'Z', '_'}):
      raise newException(
        ValueError,
        "Invalid parameter identifier '" & paramName & "' in route '" & pattern & "'.",
      )
    elif not (ch in {'a' .. 'z', 'A' .. 'Z', '0' .. '9', '_'}):
      raise newException(
        ValueError,
        "Invalid character '" & $ch & "' in parameter identifier '" & paramName &
          "'.",
      )

proc parseNameAndTypeFromInner*(
    rawInner: string, pattern, seg: string
): tuple[name: string, typeStr: string] =
  let colonPos = rawInner.find(':')
  if colonPos >= 0:
    result.name = rawInner[0 ..< colonPos].strip()
    result.typeStr = rawInner[colonPos + 1 ..^ 1].strip()
    if result.typeStr.len == 0:
      raise newException(
        ValueError,
        "Missing parameter type after ':' in segment '" & seg & "' of route '" &
          pattern & "'.",
      )
  else:
    result.name = rawInner
    result.typeStr = "string"

proc addParsedParam*(
    pattern: string,
    paramName: string,
    pKind: ParamKind,
    sKind: SegmentKind,
    seenParams: var HashSet[string],
    segments: var seq[RouteSegment],
    params: var seq[tuple[name: string, kind: ParamKind]],
    sigParts: var seq[string],
) =
  if paramName in seenParams:
    raise newException(
      ValueError,
      "Duplicate parameter name '" & paramName & "' in route '" & pattern & "'.",
    )
  seenParams.incl(paramName)
  segments.add(RouteSegment(kind: sKind, text: paramName, paramType: pKind))
  params.add((name: paramName, kind: pKind))
  case sKind
  of skCatchAll:
    sigParts.add("{*:" & $pKind & "}")
  of skParam:
    sigParts.add("{:" & $pKind & "}")
  else:
    discard

proc parseRoutePattern*(pattern: string): ParsedRoutePattern =
  let norm = normalizeRoutePath(pattern)
  let rawSegs = splitRouteSegments(norm)
  var segments: seq[RouteSegment] = @[]
  var params: seq[tuple[name: string, kind: ParamKind]] = @[]
  var seenParams = initHashSet[string]()
  var sigParts: seq[string] = @[]
  var isStatic = true

  for idx, seg in rawSegs:
    if seg.len == 0:
      continue
    if seg.startsWith("{") or seg.endsWith("}"):
      if not (seg.startsWith("{") and seg.endsWith("}")):
        raise newException(
          ValueError,
          "Malformed route parameter segment '" & seg & "' in route '" & pattern &
            "': unmatched '{' or '}'.",
        )
      let inner = seg[1 ..^ 2].strip()
      if inner.len == 0:
        raise newException(
          ValueError, "Empty parameter definition '{}' in route '" & pattern & "'."
        )
      var isCatchAll = false
      var rawInner = inner
      if rawInner.startsWith("*"):
        isCatchAll = true
        rawInner = rawInner[1 ..^ 1].strip()
        if idx != rawSegs.high:
          raise newException(
            ValueError,
            "Catch-all parameter '" & seg & "' must be the last segment in route '" &
              pattern & "'.",
          )
      let (paramName, paramTypeStr) = parseNameAndTypeFromInner(rawInner, pattern, seg)
      validateParamName(paramName, pattern, seg)
      let pKind = paramKindFromTypeName(paramTypeStr)
      isStatic = false
      let sKind = if isCatchAll: skCatchAll else: skParam
      addParsedParam(
        pattern, paramName, pKind, sKind, seenParams, segments, params, sigParts
      )
    elif seg.startsWith(":"):
      let rest = seg[1 ..^ 1].strip()
      if rest.len == 0:
        raise
          newException(ValueError, "Empty ':param' segment in route '" & pattern & "'.")
      let (paramName, paramTypeStr) = parseNameAndTypeFromInner(rest, pattern, seg)
      validateParamName(paramName, pattern, seg)
      let pKind = paramKindFromTypeName(paramTypeStr)
      isStatic = false
      addParsedParam(
        pattern, paramName, pKind, skParam, seenParams, segments, params, sigParts
      )
    elif seg == "**":
      if idx != rawSegs.high:
        raise newException(
          ValueError,
          "Catch-all '**' must be the final segment in route '" & pattern & "'.",
        )
      isStatic = false
      segments.add(RouteSegment(kind: skCatchAll, text: "*", paramType: pkString))
      sigParts.add("{*:pkString}")
    elif seg == "*":
      isStatic = false
      segments.add(RouteSegment(kind: skWildcard, text: "*", paramType: pkString))
      sigParts.add("*")
    else:
      if '{' in seg or '}' in seg:
        raise newException(
          ValueError,
          "Malformed braces in segment '" & seg & "' of route '" & pattern & "'.",
        )
      segments.add(RouteSegment(kind: skStatic, text: seg, paramType: pkString))
      sigParts.add(seg)

  result = ParsedRoutePattern(
    normalized: norm,
    canonicalSignature: "/" & sigParts.join("/"),
    segments: segments,
    params: params,
    isStatic: isStatic,
  )
