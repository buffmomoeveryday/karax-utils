## Core router types and Karax platform bindings.

import std/[tables, sets]

when defined(js):
  import karax/[karax, vdom]
  export vdom.VNode, karax.RouterData
else:
  import karax/[vdom]
  export vdom.VNode
  type RouterData* = ref object
    hashPart*: string
    queryString*: string

type
  GuardVerdictKind* = enum
    gvkAllow
    gvkBlock
    gvkRedirect
    gvkRender

  GuardVerdict* = object
    case kind*: GuardVerdictKind
    of gvkAllow, gvkBlock:
      discard
    of gvkRedirect:
      target*: string
    of gvkRender:
      node*: VNode

  GuardProc* = proc(route: string): GuardVerdict {.closure.}
  RouteHandlerProc* =
    proc(params: Table[string, string], data: RouterData): VNode {.closure.}
  NotFoundHandlerProc* = proc(route: string, data: RouterData): VNode {.closure.}

  ParamKind* = enum
    pkString
    pkInt
    pkFloat
    pkBool

  SegmentKind* = enum
    skStatic
    skParam
    skWildcard
    skCatchAll

  RouteSegment* = object
    kind*: SegmentKind
    text*: string
    paramType*: ParamKind

  RouteEntry* = object
    pattern*: string
    normalizedPattern*: string
    segments*: seq[RouteSegment]
    handler*: RouteHandlerProc
    guards*: seq[GuardProc]
    isStatic*: bool

  TrieNode* = ref object
    staticChildren*: Table[string, TrieNode]
    paramChildren*: seq[tuple[name: string, paramType: ParamKind, node: TrieNode]]
    wildcardChild*: TrieNode
    catchAllChild*: tuple[name: string, paramType: ParamKind, node: TrieNode]
    entryIndex*: int

  KaraxRouter* = ref object
    guards*: seq[GuardProc]
    ignoreRoutes*: HashSet[string]
    routes*: seq[RouteEntry]
    staticMap*: Table[string, int]
    trieRoot*: TrieNode
    routeGuards*: Table[string, seq[GuardProc]]
    notFoundPath*: string
    notFoundHandler*: NotFoundHandlerProc
    blockedHandler*: NotFoundHandlerProc

  FastKaraxRouter* = KaraxRouter

  ParsedRoutePattern* = object
    normalized*: string
    canonicalSignature*: string
    segments*: seq[RouteSegment]
    params*: seq[tuple[name: string, kind: ParamKind]]
    isStatic*: bool
