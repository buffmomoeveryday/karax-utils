## Conditional render helpers (Vue `v-if` / Solid `<Show>`).

import karax/vdom

template whenView*(cond: bool, body: untyped): untyped =
  ## Emit `body` (a VNode) only when `cond` is true; otherwise nothing.
  if cond:
    body

proc show*(cond: bool, node: VNode): VNode =
  if cond: node else: nil

proc hide*(cond: bool, node: VNode): VNode =
  ## Hide when `cond` is true (inverse of `show`).
  if cond: nil else: node
