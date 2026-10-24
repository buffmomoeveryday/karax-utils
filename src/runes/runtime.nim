## Global reactivity runtime (current observer, effect queue, redraw flag).

import runes/types

var
  currentObserver*: Observer
  pendingEffects*: seq[Observer]
  flushScheduled*, redrawNeeded*: bool
