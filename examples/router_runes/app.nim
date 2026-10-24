## Hash router + runes reactive state (and persisted theme).
## Styled with Tailwind CDN only (see index.html).
##
## Build (from repo root):
##   nim js -d:release --path:src -o:examples/router_runes/app.js examples/router_runes/app.nim
## Then open examples/router_runes/index.html in a browser.

import std/[json, sequtils, strutils]
import dom

include karax/prelude

import karax_utils/bindings
import karax_utils/lists
import karax_utils/tailwind
import router/router
import runes/runes
import runes/presistent

type
  Todo = object
    id*, title*: string
    done*: bool

  TodoFilter = enum
    tfAll
    tfActive
    tfCompleted

proc `%`*(t: Todo): JsonNode =
  %*{"id": t.id, "title": t.title, "done": t.done}

# --- Tailwind class recipes --------------------------------------------------

const
  shell =
    "min-h-screen flex flex-col bg-zinc-100 text-zinc-900 dark:bg-zinc-950 dark:text-zinc-50"
  headerBar =
    "flex flex-wrap items-center justify-between gap-4 border-b border-zinc-200 bg-white px-4 py-3 dark:border-zinc-700 dark:bg-zinc-900"
  navRow = "flex flex-wrap gap-2"
  navIdle =
    "cursor-pointer rounded-md border border-zinc-200 bg-white px-3 py-1.5 text-sm hover:bg-zinc-100 dark:border-zinc-600 dark:bg-zinc-800 dark:hover:bg-zinc-700"
  navActive =
    "cursor-pointer rounded-md border border-blue-600 bg-blue-600 px-3 py-1.5 text-sm text-white"
  routeBadge = "font-mono text-sm text-zinc-500 dark:text-zinc-400"
  mainWrap = "mx-auto w-full max-w-xl flex-1 px-4 py-6"
  panel =
    "rounded-xl border border-zinc-200 bg-white p-6 dark:border-zinc-700 dark:bg-zinc-900"
  heading = "mt-0 mb-3 text-2xl font-semibold"
  bodyText = "leading-relaxed text-zinc-700 dark:text-zinc-300"
  statLine = "font-mono text-base"
  codeChip = "rounded bg-zinc-200 px-1.5 py-0.5 font-mono text-sm dark:bg-zinc-700"
  row = "mt-4 flex flex-wrap gap-2"
  btn =
    "cursor-pointer rounded-md border border-zinc-300 bg-white px-3 py-2 text-sm hover:bg-zinc-100 dark:border-zinc-600 dark:bg-zinc-800 dark:hover:bg-zinc-700"
  btnPrimary =
    "cursor-pointer rounded-md border border-blue-600 bg-blue-600 px-3 py-2 text-sm text-white hover:bg-blue-500"
  btnDanger =
    "cursor-pointer rounded-md border border-red-600 bg-red-600 px-3 py-2 text-sm text-white hover:bg-red-500"
  footerBar =
    "border-t border-zinc-200 bg-white px-4 py-3 text-center text-sm text-zinc-500 dark:border-zinc-700 dark:bg-zinc-900 dark:text-zinc-400"
  field =
    "w-full rounded-md border border-zinc-300 bg-white px-3 py-2 text-sm dark:border-zinc-600 dark:bg-zinc-800"
  filterIdle =
    "cursor-pointer rounded-full border border-zinc-300 px-3 py-1 text-xs dark:border-zinc-600"
  filterActive =
    "cursor-pointer rounded-full border border-blue-600 bg-blue-600 px-3 py-1 text-xs text-white"

# --- shared reactive state (runes) -------------------------------------------

let count = state(0)
let step = state(1)
let name = state("")
let isLoggedIn = state(false)
let theme = persisted("karax-utils-demo-theme", "light")

let draft = state("")
let todoFilter = state(tfAll)
let nextTodoId = state(4)
let todos = persisted(
  "karax-utils-demo-todos",
  @[
    Todo(id: "1", title: "Learn runes", done: false),
    Todo(id: "2", title: "Wire the router", done: true),
    Todo(id: "3", title: "Ship each() helper", done: false),
  ],
)

let doubled = derived(int):
  count.value * 2

let themeLabel = derived(string):
  if theme.value == "dark": "Dark" else: "Light"

let activeCount = derived(int):
  todos.value.countIt(not it.done)

let doneCount = derived(int):
  todos.value.countIt(it.done)

proc syncHtmlDarkClass() =
  let on = theme.value == "dark"
  {.emit: ["document.documentElement.classList.toggle('dark', ", on, ");"].}

proc visibleTodos(): seq[Todo] =
  case todoFilter.value
  of tfAll:
    todos.value
  of tfActive:
    todos.value.filterIt(not it.done)
  of tfCompleted:
    todos.value.filterIt(it.done)

proc filterToQuery(f: TodoFilter): string =
  case f
  of tfAll: ""
  of tfActive: "active"
  of tfCompleted: "completed"

proc queryToFilter(s: string): TodoFilter =
  case s.toLowerAscii()
  of "active": tfActive
  of "completed": tfCompleted
  else: tfAll

proc syncTodosFilterFromUrl() =
  ## Browser back/forward / deep link → state.
  let f = queryToFilter(getQuery("filter", ""))
  if todoFilter.value != f:
    todoFilter.value = f
  let q = getQuery("q", "")
  if draft.value.len == 0 and q.len > 0:
    draft.value = q

proc applyTodoFilter(f: TodoFilter) =
  ## State → URL (`#/todos?filter=active`).
  todoFilter.value = f
  let fv = filterToQuery(f)
  if fv.len == 0:
    removeUrlQuery("filter")
  else:
    addUrlQuery(("filter", fv))

proc addTodo() =
  let title = draft.value.strip()
  if title.len == 0:
    return
  let id = $nextTodoId.value
  nextTodoId.value = nextTodoId.value + 1
  todos.mutate:
    it.add Todo(id: id, title: title, done: false)
  draft.value = ""
  removeUrlQuery("q")

proc toggleTodo(id: string) =
  todos.mutate:
    for t in it.mitems:
      if t.id == id:
        t.done = not t.done

proc removeTodo(id: string) =
  todos.mutate:
    it = it.filterIt(it.id != id)

proc clearCompleted() =
  todos.mutate:
    it = it.filterIt(not it.done)

proc toggleAll() =
  let allDone = todos.value.len > 0 and todos.value.allIt(it.done)
  todos.mutate:
    for t in it.mitems:
      t.done = not allDone

# --- navigation guard (router) -----------------------------------------------

proc authGuard(route: string): GuardVerdict =
  if route.startsWith("/admin") and not isLoggedIn.value:
    redirectTo("/login")
  else:
    allowRoute()

let appRouter = karaxRouter(guards = @[authGuard], ignoreRoutes = @["/login"])

# --- layout helpers ----------------------------------------------------------

proc navLink(path, label: string): VNode =
  let here = getRoute() == path
  buildHtml(
    button(
      class = if here: navActive else: navIdle,
      onclick = proc(ev: Event, n: VNode) =
        navigateTo(path),
    )
  ):
    text label

template layout*(contents: untyped): VNode =
  syncHtmlDarkClass()
  buildHtml(tdiv(class = shell)):
    header(class = headerBar):
      nav(class = navRow):
        navLink("/", "Home")
        navLink("/bindings", "Bindings")
        navLink("/todos", "Todos")
        navLink("/about", "About")
        navLink("/user/42", "User 42")
        navLink("/admin", "Admin")
        navLink("/login", "Login")
      span(class = routeBadge):
        text "Route: " & getRoute()
    main(class = mainWrap):
      contents
    footer(class = footerBar):
      text "Theme (persisted): " & themeLabel.value & " · "
      button(
        class = btn,
        onclick = proc(ev: dom.Event, n: VNode) =
          theme.value = if theme.value == "dark": "light" else: "dark"
          syncHtmlDarkClass(),
      ):
        text "Toggle theme"

# --- Home --------------------------------------------------------------------

proc homeView(): VNode =
  # Not `homeView().onMount:` — that calls the view and passes a VNode.
  # Hooks go *inside* the view with a stable string key:
  onMount("home"):
    echo "[lifecycle] home mount"
  onDestroy("home"):
    echo "[lifecycle] home destroy"

  layout:
    tdiv(class = panel):
      h1(class = heading):
        text "Home"
      p(class = bodyText):
        text "Karax utils demo — pick a playground:"
      p(class = bodyText):
        text "Console: "
        code(class = codeChip):
          text "onMount"
        text " / "
        code(class = codeChip):
          text "onDestroy"
        text " when you leave this route."
      tdiv(class = row):
        button(
          class = btnPrimary,
          onclick = proc(ev: Event, n: VNode) =
            navigateTo("/bindings"),
        ):
          text "Bindings"
        button(
          class = btnPrimary,
          onclick = proc(ev: Event, n: VNode) =
            navigateTo("/todos"),
        ):
          text "Todos"
      p(class = bodyText):
        text "Also: About, typed "
        code(class = codeChip):
          text "/user/{id}"
        text ", and guarded Admin."

# --- Bindings ----------------------------------------------------------------

proc stepStatNode(): VNode =
  result = buildHtml(p(class = statLine)):
    text "step = " & $step.value
  result.withClass("text-red-500 font-semibold", step.value > 10)

proc stepDownButton(): VNode =
  let atMin = step.value <= 1
  result = buildHtml(
    button(
      class = btn,
      onclick = proc(ev: Event, n: VNode) =
        if step.value > 1:
          step.value = step.value - 1
      ,
    )
  ):
    text "step −"
  result.withAttr("disabled", atMin)
  result.withClass("opacity-50 cursor-not-allowed", atMin)
  result.removeClass("cursor-pointer", atMin)

proc bindingsView(): VNode =
  layout:
    tdiv(class = panel):
      h1(class = heading):
        text "Bindings"

      p(class = bodyText):
        text "Svelte-like "
        code(class = codeChip):
          text "Input(bindValue = …)"

        text ", "
        code(class = codeChip):
          text "withClass"

        text ", and "
        code(class = codeChip):
          text "withAttr"
        text "."

      p(class = statLine):
        text "count = " & $count.value
      p(class = statLine):
        text "doubled = " & $doubled.value
      stepStatNode()
      label(class = bodyText):
        text "Name: "
        Input(bindValue = name, class = field, placeholder = "type here…")
      p(class = statLine):
        text "Hello, " & (if name.value.len == 0: "…" else: name.value)
      label(class = bodyText):
        text "Step: "
        Input(bindValue = step, class = field, minVal = 1)
      p(class = bodyText):
        text "Step turns red when > 10. "
        code(class = codeChip):
          text "step −"
        text " is disabled at 1."
      tdiv(class = row):
        button(
          class = btn,
          onclick = proc(ev: Event, n: VNode) =
            count.value = count.value - step.value,
        ):
          text "count −"
        button(
          class = btnPrimary,
          onclick = proc(ev: Event, n: VNode) =
            count.value = count.value + step.value,
        ):
          text "count +"
        button(
          class = btn,
          onclick = proc(ev: Event, n: VNode) =
            count.value = 0,
        ):
          text "Reset count"
        stepDownButton()
        button(
          class = btn,
          onclick = proc(ev: Event, n: VNode) =
            step.value = step.value + 1,
        ):
          text "step +"

# --- Todos -------------------------------------------------------------------

proc filterChip(label: string, f: TodoFilter): VNode =
  let on = todoFilter.value == f
  buildHtml(
    button(
      class = if on: filterActive else: filterIdle,
      onclick = proc(ev: Event, n: VNode) =
        applyTodoFilter(f),
    )
  ):
    text label

proc todoRow(item: Todo): VNode =
  let id = item.id
  let titleClass =
    if item.done: "flex-1 text-sm line-through text-zinc-400" else: "flex-1 text-sm"
  let box = buildHtml(
    input(
      `type` = "checkbox",
      class = "h-4 w-4 cursor-pointer",
      onclick = proc(ev: Event, n: VNode) =
        toggleTodo(id),
    )
  )
  box.setAttr("checked", item.done)
  buildHtml(
    li(
      class =
        "flex items-center gap-2 rounded-lg border border-zinc-200 px-3 py-2 dark:border-zinc-700"
    )
  ):
    box
    span(class = titleClass):
      text item.title
    button(
      class = btn,
      onclick = proc(ev: Event, n: VNode) =
        removeTodo(id),
    ):
      text "✕"

proc todosView(): VNode =
  onMount("todos"):
    echo "[lifecycle] todos mount"
    syncTodosFilterFromUrl()

  onDestroy("todos"):
    echo "[lifecycle] todos destroy"

  let items = visibleTodos()
  let list = buildHtml(ul(class = "mt-4 space-y-2"))

  list.each(items, it.id):
    todoRow(it)

  let canAdd = draft.value.strip().len > 0
  var addBtn = buildHtml(
    button(
      class = btnPrimary,
      onclick = proc(ev: Event, n: VNode) =
        addTodo(),
    )
  ):
    text "Add"
  addBtn.withAttr("disabled", not canAdd)
  addBtn.withClass("opacity-50 cursor-not-allowed", not canAdd)
  addBtn.removeClass("cursor-pointer", not canAdd)

  layout:
    tdiv(class = panel):
      h1(class = heading):
        text "Todos"
      p(class = bodyText):
        text "Filters sync to the URL via "
        code(class = codeChip):
          text "addUrlQuery"
        text " — try "
        code(class = codeChip):
          text "#/todos?filter=active&q=milk"
        text ". "
        code(class = codeChip):
          text "q"
        text " hydrates the draft; cleared after Add."
      p(class = statLine):
        text $activeCount.value & " active · " & $doneCount.value & " done · " &
          $todos.value.len & " total"
      tdiv(class = "mt-3 flex gap-2"):
        tdiv(class = "min-w-0 flex-1"):
          Input(
            bindValue = draft,
            class = field,
            placeholder = "What needs doing? (Enter to add)",
            onEnter = addTodo,
          )
        addBtn
      tdiv(class = row):
        filterChip("All", tfAll)
        filterChip("Active", tfActive)
        filterChip("Completed", tfCompleted)
        button(
          class = btn,
          onclick = proc(ev: Event, n: VNode) =
            toggleAll(),
        ):
          text "Toggle all"
        button(
          class = btnDanger,
          onclick = proc(ev: Event, n: VNode) =
            clearCompleted(),
        ):
          text "Clear completed"
      if items.len == 0:
        p(class = "mt-6 text-center text-sm text-zinc-500"):
          text "Nothing here — add a todo or change the filter."
      else:
        list

# --- Other routes ------------------------------------------------------------
proc aboutView(): VNode =
  layout:
    tdiv(class = panel):
      h1(class = heading):
        text "About"
      p(class = bodyText):
        text "Router + runes + Tailwind helpers demo."
      p(class = bodyText):
        text "Query from= " & getQuery("from", "none")

proc userView(id: int): VNode =
  layout:
    tdiv(class = panel):
      h1(class = heading):
        text "User profile"
      p(class = bodyText):
        text "id = " & $id

proc adminView(): VNode =
  layout:
    tdiv(class = panel):
      h1(class = heading):
        text "Admin"
      p(class = bodyText):
        text "Logged in: " & $isLoggedIn.value

proc loginView(): VNode =
  layout:
    tdiv(class = panel):
      h1(class = heading):
        text "Login"
      tdiv(class = row):
        button(
          class = btnPrimary,
          onclick = proc(ev: dom.Event, n: VNode) =
            isLoggedIn.value = true
            navigateTo("/admin"),
        ):
          text "Sign in → Admin"
        button(
          class = btn,
          onclick = proc(ev: dom.Event, n: VNode) =
            isLoggedIn.value = false,
        ):
          text "Sign out"

appRouter.addHandler("/", homeView)
appRouter.addHandler("/bindings", bindingsView)
appRouter.addHandler("/todos", todosView)
appRouter.addHandler("/about", aboutView)
appRouter.addHandler("/user/{id:int}", userView(id))
appRouter.addHandler("/admin", adminView)
appRouter.addHandler("/login", loginView)

setRenderer(appRouter)
