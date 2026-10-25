## Dependency graph, state, derived values, and effects.

import runes/runtime
import runes/scheduler
import runes/types

proc track(src: Source) =
  if currentObserver != nil and src notin currentObserver.deps:
    currentObserver.deps.add src
    src.subs.add currentObserver

proc cleanupObserver(o: Observer) =
  for d in o.deps:
    let i = d.subs.find(o)
    if i >= 0:
      d.subs.delete(i)
  o.deps.setLen 0

proc notifySubs(src: Source) =
  let copy = src.subs
  for o in copy:
    o.onChange()

template withObserver(o: Observer, body: untyped) =
  let prev = currentObserver
  currentObserver = o
  try:
    body
  finally:
    currentObserver = prev

proc untrack*[T](f: proc(): T): T =
  let prev = currentObserver
  currentObserver = nil
  try:
    result = f()
  finally:
    currentObserver = prev

proc state*[T](v: T): State[T] =
  State[T](val: v)

proc value*[T](s: State[T]): T =
  track(s)
  s.val

proc touch*[T](s: State[T]) =
  notifySubs(s)
  requestRedraw()

proc `value=`*[T](s: State[T], v: T) =
  when compiles(s.val == v):
    if s.val == v:
      return
  s.val = v
  s.touch()

proc set*[T](s: State[T], v: T) =
  s.value = v

proc get*[T](s: State[T]): T =
  s.value

proc `$`*[T](s: State[T]): string =
  $s.value

proc update*[T](s: State[T], f: proc(v: var T)) =
  f(s.val)
  s.touch()

template mutate*[T](s: State[T], body: untyped) =
  block:
    template it(): untyped {.inject.} =
      s.val

    body
  s.touch()

proc newDerived*[T](fn: proc(): T {.closure.}): Derived[T] =
  let d = Derived[T](fn: fn, dirty: true)
  d.obs = Observer(active: true)
  d.obs.onChange = proc() =
    if not d.dirty:
      d.dirty = true
      notifySubs(d)
  d

proc value*[T](d: Derived[T]): T =
  track(d)
  if d.dirty:
    cleanupObserver(d.obs)
    withObserver(d.obs):
      d.cache = d.fn()
    d.dirty = false
  d.cache

proc `$`*[T](d: Derived[T]): string =
  $d.value

template derived*(T: typedesc, body: untyped): Derived[T] =
  newDerived[T](
    proc(): T {.closure.} =
      body
  )

proc createEffect*(fn: proc() {.closure.}): proc() =
  let o = Observer(active: true)
  o.runFn = proc() =
    cleanupObserver(o)
    withObserver(o):
      fn()
  o.onChange = proc() =
    scheduleEffectRun(o)
  o.runFn()
  result = proc() =
    o.active = false
    cleanupObserver(o)

template effect*(body: untyped): proc() =
  createEffect(
    proc() {.closure.} =
      body
  )
