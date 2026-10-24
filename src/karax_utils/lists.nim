## Keyed list helpers for Karax (Vue `v-for` / Svelte `{#each}`).
##
## Stable `vnode.id` from a key expression avoids bad DOM reuse on reorder/delete.
##
## Clean form — `it` is the current item:
##
##   result = buildHtml(ul(class = "…"))
##   result.each(todos.value, it.id):
##     buildHtml(li):
##       text it.title

import karax/[kbase, vdom]

template each*(parent: VNode, items: typed, keyExpr, body: untyped) =
  ## Append one child per item. Key: any expression using `it` (e.g. `it.id`).
  bind kstring
  block:
    let parentNode = parent
    for it {.inject.} in items:
      var n: VNode = body
      if not n.isNil:
        n.id = kstring(keyExpr)
        parentNode.add n

template eachNodes*(items: typed, keyExpr, body: untyped): seq[VNode] =
  ## Same mapping, but returns a `seq[VNode]` (for manual loops).
  bind kstring
  var acc: seq[VNode]
  for it {.inject.} in items:
    var n: VNode = body
    if not n.isNil:
      n.id = kstring(keyExpr)
      acc.add n
  acc

# --- lower-level (explicit procs / `do`) ------------------------------------

proc each*[T](
    items: openArray[T], key: proc(item: T): string, render: proc(item: T): VNode
): seq[VNode] =
  result = newSeqOfCap[VNode](items.len)
  for item in items:
    var n = render(item)
    if not n.isNil:
      let k = key(item)
      if k.len > 0:
        n.id = kstring(k)
      result.add n

proc eachInto*[T](
    parent: VNode,
    items: openArray[T],
    key: proc(item: T): string,
    render: proc(item: T): VNode,
): VNode {.discardable.} =
  for n in each(items, key, render):
    parent.add n
  parent
