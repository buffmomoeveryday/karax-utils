## Reactive graph node types.

type
  Source* = ref object of RootObj
    subs*: seq[Observer]

  Observer* = ref object
    deps*: seq[Source]
    onChange*: proc() {.closure.}
    runFn*: proc() {.closure.}
    queued*, active*: bool

  State*[T] = ref object of Source
    val*: T

  Derived*[T] = ref object of Source
    fn*: proc(): T {.closure.}
    cache*: T
    dirty*: bool
    obs*: Observer
