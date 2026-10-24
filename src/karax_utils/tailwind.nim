## Karax VNode helpers: Tailwind class composition + attribute helpers.
##
## Pair class helpers with Tailwind CSS (CDN or built CSS). These helpers only
## compose `class` / attrs on VNodes — they do not generate CSS.

import std/strutils
import karax/[kbase, vdom]

# ---------------------------------------------------------------------------
# Classes
# ---------------------------------------------------------------------------

proc cn*(parts: varargs[string]): string =
  ## Join non-empty class fragments with a single space.
  var acc: seq[string]
  for p in parts:
    let t = p.strip()
    if t.len > 0:
      acc.add t
  acc.join(" ")

proc cn*(conditionals: openArray[(string, bool)]): string =
  ## Include each class string only when its flag is true.
  var acc: seq[string]
  for (cls, on) in conditionals:
    if on:
      let t = cls.strip()
      if t.len > 0:
        acc.add t
  acc.join(" ")

proc cn*(base: string, conditionals: openArray[(string, bool)]): string =
  cn(base, cn(conditionals))

proc withClass*(n: VNode, classes: string): VNode {.discardable.} =
  ## Append `classes` to an existing VNode (keeps any prior class).
  let extra = classes.strip()
  if n.isNil or extra.len == 0:
    return n
  if n.class == "" or n.class.len == 0:
    n.class = kstring(extra)
  else:
    n.class = kstring($n.class & " " & extra)
  n

proc withClass*(n: VNode, parts: varargs[string]): VNode {.discardable.} =
  n.withClass(cn(parts))

proc withClass*(n: VNode, classes: string, cond: bool): VNode {.discardable.} =
  ## Append `classes` only when `cond` is true (same shape as `withAttr(key, bool)`).
  if cond:
    n.withClass(classes)
  else:
    n

proc withClass*(
    n: VNode, conditionals: openArray[(string, bool)]
): VNode {.discardable.} =
  ## Append several conditional class groups at once.
  ## Prefer `withClass(classes, cond)` when you only have one condition.
  n.withClass(cn(conditionals))

proc classTokens(s: string): seq[string] =
  for part in s.split(Whitespace):
    if part.len > 0:
      result.add part

proc removeClass*(n: VNode, classes: string): VNode {.discardable.} =
  ## Remove each class token in `classes` from the VNode (no-op if absent).
  if n.isNil or n.class == "" or n.class.len == 0:
    return n
  let drop = classTokens(classes)
  if drop.len == 0:
    return n
  var keep: seq[string]
  for tok in classTokens($n.class):
    if tok notin drop:
      keep.add tok
  n.class =
    if keep.len == 0:
      kstring""
    else:
      kstring(keep.join(" "))
  n

proc removeClass*(n: VNode, parts: varargs[string]): VNode {.discardable.} =
  n.removeClass(cn(parts))

proc removeClass*(n: VNode, classes: string, cond: bool): VNode {.discardable.} =
  ## Remove `classes` only when `cond` is true (same shape as `withClass` / `withAttr`).
  if cond:
    n.removeClass(classes)
  else:
    n

proc toggleClass*(n: VNode, classes: string, on: bool): VNode {.discardable.} =
  ## Add `classes` when `on`, otherwise remove them.
  if on:
    n.withClass(classes)
  else:
    n.removeClass(classes)

# ---------------------------------------------------------------------------
# Attributes
# ---------------------------------------------------------------------------

proc withAttr*(n: VNode, key, val: string): VNode {.discardable.} =
  ## Set a string attribute (`id`, `type`, `aria-label`, …).
  if not n.isNil:
    n.setAttr(kstring(key), kstring(val))
  n

proc withAttr*(n: VNode, key: string, val: bool): VNode {.discardable.} =
  ## Set a boolean HTML attribute (`disabled`, `checked`, `required`, …).
  ## `true` adds the attribute; `false` clears it (Karax/`setAttr` semantics).
  if not n.isNil:
    n.setAttr(kstring(key), val)
  n

proc withAttr*(n: VNode, attrs: openArray[(string, string)]): VNode {.discardable.} =
  for (k, v) in attrs:
    discard n.withAttr(k, v)
  n

proc withAttr*(n: VNode, attrs: openArray[(string, bool)]): VNode {.discardable.} =
  ## Apply several boolean attrs at once, e.g. `[("disabled", busy), ("aria-busy", busy)]`.
  for (k, v) in attrs:
    discard n.withAttr(k, v)
  n

proc withAttrWhen*(n: VNode, key, val: string, cond: bool): VNode {.discardable.} =
  ## Set a string attribute only when `cond` is true (does not clear when false).
  if cond:
    n.withAttr(key, val)
  else:
    n
