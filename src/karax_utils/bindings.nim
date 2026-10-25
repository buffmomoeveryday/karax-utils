## Two-way binding sugar for Karax + runes `State`.
##
## Svelte:  `<input bind:value={name} />`
##
## Karax cannot use `bind:value` (invalid Nim) or shadow HTML `input` inside
## `buildHtml` (the DSL always treats `input` as a tag). Closest sugar:
##
##   Input(bindValue = name, class = "…", placeholder = "…")
##   Input(bindValue = step, class = "…")          # State[int]
##   Input(bindValue = done, class = "…")          # State[bool]
##
## Or positional: `textInput(name)`, `numberInput(step)`, `checkboxInput(done)`.
##
## Caret note: Karax redraws on every `oninput`. Patching `input.value` (or
## replacing the node) resets the caret — especially bad for `type=number`,
## which cannot restore selection in Chrome. We keep a text caret via
## `setSelectionRange` after redraw, and bind ints as `inputmode=numeric`
## text fields.

when defined(js):
  import std/strutils
  import karax/[karax, karaxdsl, vdom, kdom]
  import karax/prelude
  import runes/runes

  proc selectionStart(n: Node): int {.importjs: "(#.selectionStart || 0)".}
  proc selectionEnd(n: Node): int {.importjs: "(#.selectionEnd || 0)".}
  proc setSelectionRange(n: Node, a, b: int) {.importjs: "#.setSelectionRange(#, #)".}
  proc trySetSelectionRange(n: Node, a, b: int) =
    try:
      n.setSelectionRange(a, b)
    except CatchableError:
      discard

  proc reqFrame(cb: proc()): int {.importjs: "window.requestAnimationFrame(#)".}
  proc activeElement(d: Document): Node {.importjs: "#.activeElement".}
  proc getElementById(
    d: Document, id: cstring
  ): Node {.importjs: "#.getElementById(#)".}

    # Stable DOM ids for State refs. `cast[uint](ref)` becomes BigInt on JS and
    # throws; use a WeakMap keyed by the ref object instead.

  proc bindDomId(s: RootRef, kind: cstring): cstring {.
    importjs: """
    (function(obj, kind) {
      var g = globalThis;
      var m = g.__kuBindIds || (g.__kuBindIds = new WeakMap());
      var id = m.get(obj);
      if (!id) {
        id = "ku-bind-" + kind + "-" + (m._n = (m._n|0) + 1);
        m.set(obj, id);
      }
      return id;
    })(#, #)
  """
  .}

  proc restoreCaretAfterRedraw(domId: cstring, startPos, endPos: int) =
    ## Karax schedules redraw on rAF; restore on the following frame.
    ## Look up by id so a replaced input node is still found.
    discard reqFrame(
      proc() =
        discard reqFrame(
          proc() =
            let el = getElementById(document, domId)
            if el.isNil:
              return
            if activeElement(document) != el:
              el.focus()
            el.trySetSelectionRange(startPos, endPos)
        )
    )

  proc textInput*(
      s: State[string],
      className = "",
      placeholder = "",
      inputType = "text",
      onEnter: proc() = nil,
  ): VNode =
    ## Two-way bind a string state to a text-like `<input>`.
    ## Optional `onEnter` runs on Karax `onkeyupenter` (Enter key).
    let v = s.value
    let id = bindDomId(s, cstring"str")
    buildHtml(
      input(
        id = id.kstring(),
        class = className,
        `type` = inputType,
        placeholder = placeholder,
        value = v.cstring(),
        oninput = proc(ev: Event, n: VNode) =
          let el = cast[Node](ev.target)
          let startPos = el.selectionStart
          let endPos = el.selectionEnd
          s.value = $n.value
          restoreCaretAfterRedraw(id, startPos, endPos),
        onkeyupenter = proc(ev: Event, n: VNode) =
          if not onEnter.isNil:
            onEnter()
        ,
      )
    )

  proc textareaInput*(s: State[string], className = "", rows = 3): VNode =
    let v = s.value
    let id = bindDomId(s, cstring"area")
    buildHtml(
      textarea(
        id = id,
        class = className,
        rows = $rows,
        value = v,
        oninput = proc(ev: Event, n: VNode) =
          let el = cast[Node](ev.target)
          let startPos = el.selectionStart
          let endPos = el.selectionEnd
          s.value = $n.value
          restoreCaretAfterRedraw(id, startPos, endPos),
      )
    )

  proc numberInput*(
      s: State[int], className = "", minVal = int.low, maxVal = int.high
  ): VNode =
    ## Two-way bind an int state. Invalid/empty/out-of-range input leaves state
    ## unchanged. Uses a text field with `inputmode=numeric` so the caret can be
    ## restored after Karax redraws (`type=number` cannot in Chrome).
    let v = $s.value
    let id = bindDomId(s, cstring"int")
    result = buildHtml(
      input(
        id = id,
        class = className,
        `type` = "text",
        value = v,
        oninput = proc(ev: Event, n: VNode) =
          let el = cast[Node](ev.target)
          let startPos = el.selectionStart
          let endPos = el.selectionEnd
          let raw = ($n.value).strip()
          if raw.len > 0:
            try:
              let parsed = parseInt(raw)
              if parsed >= minVal and parsed <= maxVal:
                s.value = parsed
            except ValueError:
              discard
          restoreCaretAfterRedraw(id, startPos, endPos),
      )
    )
    result.setAttr("inputmode", "numeric")
    result.setAttr("autocomplete", "off")

  proc checkboxInput*(s: State[bool], className = ""): VNode =
    ## Two-way bind a bool state to a checkbox.
    result = buildHtml(
      input(
        class = className,
        `type` = "checkbox",
        onchange = proc(ev: Event, n: VNode) =
          s.value = not s.value,
      )
    )
    result.setAttr("checked", s.value)

  template bindValue*(s: State[string], className = "", placeholder = ""): VNode =
    ## Naming closer to Svelte's `bind:value`.
    textInput(s, className, placeholder)

  # ---------------------------------------------------------------------------
  # Svelte-like named API: Input(bindValue = state, …)
  # Capital `Input` so it is NOT the HTML tag inside buildHtml.
  # ---------------------------------------------------------------------------

  proc Input*(
      bindValue: State[string],
      class = "",
      placeholder = "",
      `type` = "text",
      onEnter: proc() = nil,
  ): VNode =
    ## Like `<input bind:value={…}>` — use inside or outside `buildHtml`.
    ## Pass `onEnter = someProc` to handle Enter (Karax `onkeyupenter`).
    textInput(bindValue, class, placeholder, `type`, onEnter)

  proc Input*(
      bindValue: State[int], class = "", minVal = int.low, maxVal = int.high
  ): VNode =
    numberInput(bindValue, class, minVal, maxVal)

  proc Input*(bindValue: State[bool], class = ""): VNode =
    checkboxInput(bindValue, class)

else:
  discard
