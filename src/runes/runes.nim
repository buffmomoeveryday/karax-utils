## runes: Svelte-5-style reactive primitives for Karax (JS backend).
##
##   let count   = state(0)                      # $state
##   let doubled = derived(int): count.value * 2 # $derived
##   effect: echo "count is ", count.value       # $effect
##
## Writing to a state automatically schedules ONE batched `redraw()`
## (microtask), so you never call redraw() by hand.

import runes/types as runesTypes
import runes/reactivity as runesReactivity
import runes/scheduler as runesScheduler

export runesTypes, runesReactivity, runesScheduler
