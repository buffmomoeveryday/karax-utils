## View mount / destroy hooks.
##
## Karax view procs rebuild a `VNode` every redraw — you cannot do
## `homeView().onMount:`. Declare hooks **inside** the view with a stable key;
## `dispatchRoute` flushes them after the handler runs:
##
##   proc homeView(): VNode =
##     onMount("home"):
##       echo "entered"
##     onDestroy("home"):
##       echo "left"
##     buildHtml(tdiv): text "Home"
##
## Mount runs once when the key becomes active; destroy runs when a later
## dispatch does not activate that key (typically a route change).

import std/[sets, tables]

var
  mountedKeys: HashSet[string]
  activeThisFrame: HashSet[string]
  mountFns: Table[string, proc()]
  destroyFns: Table[string, proc()]

template onMount*(key: string; body: untyped) =
  if not mountFns.hasKey(key):
    mountFns[key] = proc() =
      body
  activeThisFrame.incl(key)

template onDestroy*(key: string; body: untyped) =
  destroyFns[key] = proc() =
    body
  activeThisFrame.incl(key)

proc flushLifecycle*() =
  var toDestroy: seq[string]
  for k in mountedKeys:
    if k notin activeThisFrame:
      toDestroy.add k
  for k in toDestroy:
    if destroyFns.hasKey(k):
      destroyFns[k]()
    mountedKeys.excl k
    mountFns.del k
    destroyFns.del k

  for k in activeThisFrame:
    if k notin mountedKeys:
      if mountFns.hasKey(k):
        mountFns[k]()
      mountedKeys.incl k

  activeThisFrame.clear()

proc resetLifecycle*() =
  mountedKeys.clear()
  activeThisFrame.clear()
  mountFns.clear()
  destroyFns.clear()
