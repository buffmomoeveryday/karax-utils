## Microtask batching and Karax redraw scheduling.

when defined(js):
  import karax/karax

  import runes/runtime
  import runes/types
  proc queueMicrotask(f: proc()) {.importjs: "queueMicrotask(#)".}

  proc flushEffects() =
    flushScheduled = false
    var rounds = 0
    while pendingEffects.len > 0 and rounds < 100:
      let batch = pendingEffects
      pendingEffects = @[]
      for o in batch:
        o.queued = false
        if o.active:
          o.runFn()
      inc rounds
    if redrawNeeded:
      redrawNeeded = false
      try:
        redraw()
      except CatchableError:
        discard

  proc scheduleEffects() =
    if not flushScheduled:
      flushScheduled = true
      queueMicrotask(flushEffects)

  proc requestRedraw*() =
    ## Manual escape hatch (batched).
    redrawNeeded = true
    scheduleEffects()

  proc scheduleEffectRun*(o: Observer) =
    if not o.queued and o.active:
      o.queued = true
      pendingEffects.add o
      scheduleEffects()

else:
  {.error: "Js backend is required".}
