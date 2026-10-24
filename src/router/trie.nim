## Prefix trie for parameterized route matching.

import std/[strutils, tables, uri]

import router/types

proc matchesParamType*(val: string, kind: ParamKind): bool {.inline.} =
  case kind
  of pkString:
    result = val.len > 0
  of pkInt:
    if val.len == 0:
      return false
    var parsed: int
    try:
      parsed = parseInt(val)
      discard parsed
      result = true
    except ValueError:
      result = false
  of pkFloat:
    if val.len == 0:
      return false
    var parsed: float
    try:
      parsed = parseFloat(val)
      discard parsed
      result = true
    except ValueError:
      result = false
  of pkBool:
    let lower = val.toLowerAscii()
    result = lower in ["true", "false", "1", "0", "yes", "no", "on", "off", "y", "n"]

proc parseBoolValue*(val: string): bool {.inline.} =
  let lower = val.toLowerAscii().strip()
  case lower
  of "true", "1", "yes", "on", "y":
    true
  of "false", "0", "no", "off", "n":
    false
  else:
    raise newException(ValueError, "Cannot parse bool from '" & val & "'")

proc newTrieNode*(): TrieNode =
  TrieNode(
    staticChildren: initTable[string, TrieNode](),
    paramChildren: @[],
    wildcardChild: nil,
    catchAllChild: (name: "", paramType: pkString, node: nil),
    entryIndex: -1,
  )

proc insertTrie*(root: TrieNode, segments: seq[RouteSegment], entryIdx: int) =
  var curr = root
  for seg in segments:
    case seg.kind
    of skStatic:
      if not curr.staticChildren.hasKey(seg.text):
        curr.staticChildren[seg.text] = newTrieNode()
      curr = curr.staticChildren[seg.text]
    of skParam:
      var found: TrieNode = nil
      for item in curr.paramChildren:
        if item.name == seg.text and item.paramType == seg.paramType:
          found = item.node
          break
      if found.isNil:
        found = newTrieNode()
        curr.paramChildren.add((name: seg.text, paramType: seg.paramType, node: found))
      curr = found
    of skWildcard:
      if curr.wildcardChild.isNil:
        curr.wildcardChild = newTrieNode()
      curr = curr.wildcardChild
    of skCatchAll:
      if curr.catchAllChild.node.isNil:
        curr.catchAllChild =
          (name: seg.text, paramType: seg.paramType, node: newTrieNode())
      curr = curr.catchAllChild.node
  curr.entryIndex = entryIdx

proc matchTrie*(
    node: TrieNode,
    segments: openArray[string],
    depth: int,
    params: var Table[string, string],
): int =
  if node.isNil:
    return -1

  if depth == segments.len:
    if node.entryIndex >= 0:
      return node.entryIndex
    if not node.catchAllChild.node.isNil and node.catchAllChild.node.entryIndex >= 0:
      params[node.catchAllChild.name] = ""
      return node.catchAllChild.node.entryIndex
    return -1

  let seg = segments[depth]

  let staticNext = node.staticChildren.getOrDefault(seg, nil)
  if not staticNext.isNil:
    let matched = matchTrie(staticNext, segments, depth + 1, params)
    if matched >= 0:
      return matched

  for paramChild in node.paramChildren:
    if matchesParamType(seg, paramChild.paramType):
      let hadPrev = params.hasKey(paramChild.name)
      let prevVal =
        if hadPrev:
          params[paramChild.name]
        else:
          ""
      params[paramChild.name] = decodeUrl(seg)
      let matched = matchTrie(paramChild.node, segments, depth + 1, params)
      if matched >= 0:
        return matched
      if hadPrev:
        params[paramChild.name] = prevVal
      else:
        params.del(paramChild.name)

  if not node.wildcardChild.isNil:
    let matched = matchTrie(node.wildcardChild, segments, depth + 1, params)
    if matched >= 0:
      return matched

  if not node.catchAllChild.node.isNil and node.catchAllChild.node.entryIndex >= 0:
    let tail = segments[depth ..^ 1].join("/")
    if matchesParamType(tail, node.catchAllChild.paramType):
      params[node.catchAllChild.name] = decodeUrl(tail)
      return node.catchAllChild.node.entryIndex

  -1
