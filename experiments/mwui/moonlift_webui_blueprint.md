# Moonlift WebUI Blueprint

**Status:** canonical blueprint for the Moonlift WebUI framework: authoring API, generated Moonlift shape, runtime product/protocol tree, memory model, and public ABI.

This document folds together:

1. the Moonlift WebUI `.mlua` design header, where the product graph and protocol graph are the design;
2. the final authoring decision: every tree-shaped thing is built with Lua callable tables and no parentheses, while executable leaves are already Moonlift values.

The blueprint is intentionally not a “v1.” It describes the full architecture. Individual implementations may be staged, but the design is not partial.

**Revision — tightening pass.** The following hardening fixes are folded in below:

1. Guard/action exits are scoped *inside* the guard/action builder, so exit names can never collide with transition keys (§3.3, §4.2, §6.2, §6.3); reserved-name rule added (§6.5).
2. Behavior leaves are provenance-agnostic (`readonly view(u8)` text); the lease/owned dispatch paths are a stamped factory family, not hand-written twins (§4.3, §6.6, §11.3).
3. Linear effect sequences with a shared error sink: `steps { } rescue { }` (§6.3).
4. `ViewNodeRef` (compile-time, template-local) and `NodeId` (runtime, per-session) are split by law, bridged by `Component.node_base` (§9.6, §9.10).
5. Render-phase termination is stated as an invariant and enforced by a validation rule (§10.5, §12.3).
6. Imperative parent→child commands ride a monotonic nonce prop, preserving outputs-up/props-down (§16.4).
7. `oom` is removed from the `raise`/output channel; it rides each protocol's `oom(needed)` exit to the session (§6.3, §12.2).
8. The `+` operator is specified as three precise per-kind monoids with identities (§3.2).
9. Field-name strings are compile-time-resolved against the context (§12.3).
10. The browser client is specified as a small JS patch applier defined by the wire format only; WASM is demoted to an optional app-level compute-kernel note, not a framework feature (§22).

---

## 0. Thesis

A UI is a machine.

A component is not a render function. A component is:

```text
Component = compiled state machine + keyed view + binding graph
```

The backend owns the remembered state and compiled component machines. The browser owns the real DOM and runs a tiny JS patch applier. The wire is not HTML and not a VDOM snapshot. The wire is:

```text
backend → browser: mutation bytecode
browser → backend: event stream
```

There is no runtime VDOM diff. A state transition dirties context fields. The precomputed field-to-node binding graph maps those dirty fields into concrete mutation bytecode. The one bounded reconciliation operation is keyed-list reconciliation.

An event text payload is a lease into the socket receive buffer. It may be streamed through guards/actions during the dispatch. If it is stored into component context, it must be materialized into owned memory. Storing into context is the breaker boundary.

---

## 1. The three committed decisions

### 1.1 Atom

```text
Component = Context product + state machine + keyed view + child protocol surface
```

The app author defines a component as a Lua tree. The compiler stamps it into monomorphic Moonlift:

```text
<Name>_Context             -- generated product
<Name>_send                -- generated region: statechart
<Name>_mount               -- generated region: mount/create-tree plan
<Name>_render_delta        -- generated region: dirty fields → mutation set
<Name>_output_dispatch     -- generated region: child outputs → parent continuations
binding graph              -- field/expression → node/attr/prop/class/style targets
route table fragment       -- NodeId + event kind → component handler
keyed-list emitters        -- mount/reconcile/render item fragments
```

### 1.2 Wire

```text
Mutation bytecode down, Event stream up.
```

The browser is a small JS patch applier keyed by `NodeId`. The backend holds only durable node IDs, route bindings, component handles, dirty queues, and keyed-list order. It does not hold or diff a tree of DOM nodes.

### 1.3 Authoring surface

```text
All tree-shaped authoring surfaces are Lua callable-table monoids.
All executable behavior leaves are already Moonlift values.
```

Lua writes the trees. Moonlift supplies the typed leaves. The compiler wires the forest into native state machines.

This means:

```text
component/state/view/list/when/child = Lua tree DSL
called guards/actions/expressions    = Moonlift region/expr/function values
runtime behavior                     = generated Moonlift regions
runtime rendering                    = mutation bytecode, not HTML
```

---

## 2. Layer map

```text
┌─────────────────────────────────────────────────────────────────────┐
│ Authoring layer: Lua callable-table monoids                         │
│   component "Name" { context{...}, state{...}, view{...} }          │
│   div.card { on.click "save", bind.text { title_expr } }            │
│   guard/action leaves are Moonlift values                            │
└─────────────────────────────────────────────────────────────────────┘
                                ↓
┌─────────────────────────────────────────────────────────────────────┐
│ Compile layer: build-time Lua factory                               │
│   validates component spec                                           │
│   checks Moonlift value signatures                                   │
│   emits generated Context structs and regions                        │
│   emits binding graph, route table, dispatch switches                │
└─────────────────────────────────────────────────────────────────────┘
                                ↓
┌─────────────────────────────────────────────────────────────────────┐
│ Runtime layer: Moonlift product/protocol tree                       │
│   App → Session → Conn/ComponentStore/Arena/MutBuf/TaskStore         │
│   conn_read/ws_decode/event_decode/route_event/dispatch/render/flush │
└─────────────────────────────────────────────────────────────────────┘
                                ↓
┌─────────────────────────────────────────────────────────────────────┐
│ Browser layer: JS patch applier                                    │
│   holds real DOM keyed by NodeId                                     │
│   applies mutation bytecode                                          │
│   captures events and sends encoded events                           │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 3. Authoring law

### 3.1 No-parens callable-table grammar

The API is uniform:

```lua
builder "name"          -- select/name/curried builder
builder { ... }         -- build an unnamed fragment/tree
builder "name" { ... }  -- build a named fragment/tree
builder.key             -- specialize builder by property/event/class/tag
builder.key { ... }     -- build specialized fragment
builder.key "name" { ... }
```

Because Lua no-parentheses calls naturally accept string literals and table constructors, every non-string value is passed inside a table:

```lua
field "email" { Text }
guard { can_submit }
action { store_email }
prop.value { email_expr }
```

Do not rely on invalid pseudo-Lua like `guard can_submit`.

### 3.2 Monoid rule

Every same-kind fragment composes into a larger same-kind fragment.

```lua
local identity_fields = context {
    field "id" { moon.u64 },
    field "created_at" { moon.i64 },
}

local auth_fields = context {
    field "email" { Text },
    field "token" { Text },
}

local UserContext = identity_fields + auth_fields
```

The `+` operator is defined only for same-kind fragments, and it is a **different monoid per kind**. Each has an identity and a precise law:

```text
ContextSpec + ContextSpec → ContextSpec   CHECKED MERGE. Eager: a duplicate field
                                          name is an error at `+` time. Identity: context{}.
StateSet    + StateSet    → StateSet       CHECKED MERGE. Duplicate state name errors
                                          at `+`. Identity: an empty state set.
ViewNodes   + ViewNodes   → ViewNodes      ORDERED CONCAT (free monoid). Order-preserving,
                                          no dedup. Non-commutative. Identity: view{}.
Bindings    + Bindings    → Bindings        CONCAT with a DEFERRED uniqueness pass (NodeId
                                          collisions need the whole tree). Identity: empty.
Routes      + Routes      → Routes          CONCAT, deferred (NodeId+kind) uniqueness pass.
                                          Identity: empty.
```

So `+` is eager-checked for the unordered set-like kinds (context, state) and concat for the ordered/positional kinds (view, bindings, routes), whose uniqueness can only be validated once the full forest exists. `identity_fields + auth_fields` errors immediately if both declare `id`; two view fragments never dedup and never reorder.

For mixed lists, use `seq { ... }` to flatten and validate.

### 3.3 Runtime variation is AST, not Lua control flow

Build-time Lua is allowed:

```lua
if ENABLE_DEBUG then
    extra = extra + view { DebugPanel {} }
end
```

Runtime UI variation must be represented as a view AST node:

```lua
when "logged_in" {
    child "UserMenu" {}
}
```

Runtime behavior branching must be represented as state-machine/guard wiring. Guard exits are filled **inside the guard builder**, never as siblings of `target`/`action`, so an exit name can never collide with a transition key:

```lua
on.click "submit" {
    guard { can_submit } {
        pass        { action { submit_login }, target "submitting" },
        empty_email { target "editing" },
        busy        { target "editing" },
    },
}
```

---

## 4. Authoring API

### 4.1 Namespace

```lua
local moon = require("moonlift")
local ui = require("moonlift.webui")

local component = ui.component
local context   = ui.context
local field     = ui.field
local initial   = ui.initial
local state     = ui.state
local on        = ui.on
local guard     = ui.guard
local action    = ui.action
local target    = ui.target
local view      = ui.view
local bind      = ui.bind
local prop      = ui.prop
local attr      = ui.attr
local class     = ui.class
local style     = ui.style
local when      = ui.when
local list      = ui.list
local key       = ui.key
local each      = ui.each
local child     = ui.child
local out       = ui.out
local task      = ui.task
local seq       = ui.seq

local div, h1, input, button, span, ul, li = ui.tags {
    "div", "h1", "input", "button", "span", "ul", "li",
}
```

### 4.2 Component shape

```lua
local Login = component "Login" {
    context {
        field "email" { Text },
        field "busy"  { moon.bool },
        field "error" { Text },
    },

    initial "editing",

    state "editing" {
        on.input "edit_email" {
            action { store_email },
            target "editing",
        },

        on.click "submit" {
            guard { can_submit } {
                pass {
                    action { submit_login },
                    target "submitting",
                },

                empty_email {
                    action { show_empty },
                    target "editing",
                },

                busy {
                    target "editing",
                },
            },
        },
    },

    state "submitting" {
        on.task_done "login_done" {
            action { accept_login },
            target "done",
        },

        on.task_err "login_err" {
            action { show_task_error },
            target "editing",
        },
    },

    view {
        div.login {
            h1 { "Login" },

            input {
                prop.value { email_value },
                attr.placeholder "Email",
                on.input "edit_email",
            },

            button.primary {
                prop.disabled { busy_value },
                on.click "submit",
                "Sign in",
            },

            when "has_error" {
                div.error { bind.text "error" },
            },
        },
    },
}
```

### 4.3 Executable leaves are Moonlift values

The following are not Lua callbacks. They are hosted Moonlift declarations bound to Lua values.

Behavior leaves are **provenance-agnostic**: they receive `e: ptr(Event)` whose `text` field is `readonly view(u8)`. A lease *and* an owned view both satisfy a non-escaping read, so a guard/action is written **once** and works whether the event came off the socket (`EventIn`) or from a task/server (`EventOwned`). Only the store boundary and the dispatch wrapper are provenance-specific (§6.6).

```lua
local can_submit = region(readonly self: ptr(Login_Context), e: ptr(Event);
    pass
  | empty_email
  | busy)
entry start()
    -- inspects e.text (readonly view(u8)); does not store it
end
end

local store_email = region(invalidate self: ptr(Login_Context),
                           e: ptr(Event),
                           arena: ptr(Arena),
                           dirty: ptr(DirtyQueue);
    stored
  | oom(needed: index))
entry start()
    -- materializes e.text via ctx_store_text* into Login_Context.email
end
end

local email_value = expr(readonly self: ptr(Login_Context)): view(u8)
    self.email
end

local busy_value = expr(readonly self: ptr(Login_Context)): bool
    self.busy
end
```

They are inserted directly into the component tree:

```lua
guard { can_submit }
action { store_email }
prop.value { email_value }
prop.disabled { busy_value }
```

The compiler validates their signatures and wires them with `emit`.

---

## 5. Builder object semantics

### 5.1 Builder values

Every authoring constructor returns a typed Lua builder object:

```text
component "Name" { ... }     → ComponentSpec
context { ... }              → ContextSpec
field "name" { T }           → FieldSpec
state "name" { ... }         → StateSpec
on.click "handler" { ... }   → TransitionSpec
guard { region_value }       → GuardSpec
action { region_value }      → ActionSpec
target "state"               → TargetSpec
view { ... }                 → ViewSpec
div.card { ... }             → ViewNodeSpec
prop.value { expr_value }    → BindingSpec
bind.text "field"            → BindingSpec
when "field" { ... }         → ConditionalSpec
list "items" { ... }         → ListSpec
child { ComponentSpec } { ... } → ChildSpec
out.delete "handler"         → ChildOutputRouteSpec
```

### 5.2 No runtime Lua closures in behavior

Runtime behavior is never a Lua callback. Lua may create the AST at build time, but guards/actions/effects are Moonlift values. If an author wants a custom behavior leaf, they write a Moonlift `region`, `func`, or `expr` and place that value into the tree.

### 5.3 Curried environment pattern

Builders support environment currying like Moonlift’s quote/binder style:

```lua
local Form = ui.with {
    Text = Text,
    can_submit = can_submit,
    store_email = store_email,
}

local edit_transition = Form.transition "edit_email" {
    on.input,
    action { Form.store_email },
    target "editing",
}
```

This is not string interpolation. It is composition of typed Lua values.

---

## 6. State machine API

### 6.1 Event handlers

Event handlers are named route targets. A browser event comes in with `NodeId + event_kind`. The route table resolves it to:

```text
ComponentRef + HandlerRef
```

The handler name in authoring is not a runtime string bus; it is a compile-time name resolved to a generated handler ID.

```lua
on.click "submit" { ... }
on.input "edit_email" { ... }
```

### 6.2 Guard exits become branch builders

A guard is a Moonlift region whose continuation names become legal branch names.

If the guard is:

```lua
local can_submit = region(readonly self: ptr(Login_Context), e: ptr(Event);
    pass
  | empty_email
  | invalid_email
  | busy)
entry start()
end
end
```

then the transition fills the exits **inside the guard builder**:

```lua
on.click "submit" {
    guard { can_submit } {
        pass {
            action { submit_login },
            target "submitting",
        },

        empty_email {
            action { show_empty },
            target "editing",
        },

        invalid_email {
            action { show_invalid },
            target "editing",
        },

        busy {
            target "editing",
        },
    },
}
```

Default policy: guard fills are exhaustive. Missing guard exits are compile errors unless explicitly ignored *inside the guard*:

```lua
guard { can_submit } {
    pass { target "submitting" },
    ignore.empty_email,
    ignore.busy,
}
```

Scoping the exits inside the guard means exit names live in the guard's own table, never as siblings of `target`/`action`/`on`, so a guard exit named `target` or two guards with overlapping exit names can never collide.

### 6.3 Action exits are also protocols

An action is a Moonlift region. The transition must either use a conventional exit (`done`, `stored`, `spawned`) or fill its action exits explicitly.

```lua
action { submit_login } {
    spawned {
        target "submitting",
    },

    rejected {
        action { show_rejected },
        target "editing",
    },

    oom {
        fail "oom",          -- propagates as the protocol's oom(needed) exit to the session,
    },                       -- NOT as a domain output. `raise` is for declared outputs only.
}
```

Generated `send` is therefore nested protocol wiring:

```text
event route → guard protocol → action protocol → target/output/spawn/dirty
```

`fail` is distinct from `raise`: `raise`/`out` carry declared *domain* outputs (`delete`, `toggle`); `fail` routes a resource/protocol failure (`oom`, `action_failed`) up the region's own failure exit to the session, which owns the backpressure/close decision. Mixing `oom` into the output channel is a compile error (§12.2).

### 6.3.1 Linear effect sequences

When a transition runs several fallible effects in order, nesting their exits produces a staircase. `steps { } rescue { }` lowers a linear sequence with a shared error sink: each action's success exit jumps to the next; any action's failure exit of a given kind jumps to the matching `rescue` block.

```lua
on.click "submit" {
    guard { can_submit } {
        pass {
            steps {
                action { validate },
                action { persist },
                action { notify },
                target "done",
            } rescue {
                rejected { action { show_rejected }, target "editing" },
                oom      { fail "oom" },
            },
        },
        empty_email { target "editing" },
        busy        { target "editing" },
    },
}
```

Linear transitions stay linear; the explicit nested form remains available when branches genuinely diverge mid-sequence.

### 6.4 State blocks

Generated `<Name>_send` lowers each state to blocks and switches:

```text
switch self.state
  case editing:
    switch handler
      case edit_email: emit StoreEmail(...)
      case submit: emit CanSubmit(...)
  case submitting:
    ...
```

Transitions use `jump` to generated continuation blocks. Every state path exits by a named continuation of `<Name>_send`.

### 6.5 Reserved exit names

Because guard/action exit names become authoring keys, they may not shadow the structural transition keywords. The reserved set is:

```text
guard  action  steps  rescue  target  out  raise  fail  spawn  on  when  ignore
```

A guard or action whose continuation uses a reserved name is a compile error. (Exits are already scoped inside their builder, §6.2/§6.3; this rule additionally keeps generated code and authoring trees readable.)

### 6.6 Provenance is a generated family, not hand-written twins

Events have two provenances — `EventIn` (text leases the rx buffer) and `EventOwned` (text owned by a task/server). Behavior **leaves** are provenance-agnostic (§4.3), so the only provenance-specific code is the dispatch wrapper and the store boundary. These are stamped by one factory call rather than written twice:

```text
make_event_path(prov)  →  route_event_<prov>
                          dispatch_event_<prov>
                          component_step_<prov>
```

The author writes one handler; the compiler emits the `_in` and `_owned` wrappers. `route_event` / `route_event_owned`, `dispatch_event` / `dispatch_event_owned`, `component_step` / `component_step_owned`, and `raised` / `raised_owned` in §10 are the two monomorphic outputs of this single template, not independent declarations. The component step receives a generated `Event` projection in both cases.

---

## 7. View API

### 7.1 Static DOM nodes

```lua
view {
    div.app {
        h1 { "Dashboard" },
        button.primary { on.click "refresh", "Refresh" },
    },
}
```

Tag builders support class specialization:

```lua
button.primary.large { ... }
div.card.error { ... }
```

This is authoring sugar. The compiler records static classes in the `ViewPlan`.

### 7.2 Binding forms

```lua
bind.text "title"          -- context field binding
bind.text { title_expr }   -- Moonlift expr binding
prop.value "draft"         -- context field → DOM property
prop.value { draft_expr }  -- expr → DOM property
attr.href "url"            -- field → attribute
attr.placeholder "Email"   -- static attribute string
class.active { is_active } -- bool expr → class toggle
style.width { width_expr } -- expr → style property
```

Static strings inside node bodies become static text nodes.

### 7.3 Event listeners

```lua
on.click "save"
on.input "edit_email"
on.submit "submit_form"
```

Listeners generate route-table entries:

```text
NodeId + event_kind → ComponentRef + HandlerRef
```

There is no implicit bubbling. Parent/child semantics are explicit component-output protocols.

### 7.4 Conditionals

```lua
when "logged_in" {
    child "UserMenu" {}
}

when { is_admin_expr } {
    button.danger { on.click "delete", "Delete" }
}
```

A conditional is a keyed fragment of cardinality 0 or 1. It uses the same reconciliation machinery as lists.

### 7.5 Keyed lists

No unkeyed dynamic lists.

```lua
list "todos" {
    key "id",

    each {
        child "TodoItem" {
            prop.text "text",
            prop.done "done",
            out.delete "delete_todo",
            out.toggle "toggle_todo",
        },
    },
}
```

For pure DOM items:

```lua
list "todos" {
    key "id",

    each {
        li.todo {
            span { bind.text "text" },
            button { on.click "delete_todo", "Delete" },
        },
    },
}
```

The compiler generates:

```text
ListSpec
ListItemSpec
mount_item region
render_item_delta region
route entries
list_reconcile calls
```

### 7.6 Child components

Prefer component values when available:

```lua
child { TodoItem } {
    prop.text "text",
    prop.done "done",
    out.delete "delete_todo",
}
```

Allow string names for mutual recursion or forward resolution:

```lua
child "TodoItem" { ... }
```

Child output is not DOM bubbling. It is a generated protocol route:

```lua
out.delete "delete_todo"
```

---

## 8. Compile-time products

These exist in Lua/ASDL builder space, not necessarily runtime memory.

```moonlift
handle ViewNodeRef : u32 invalid 0 end
handle FieldRef : u32 invalid 0 end
handle HandlerRef : u32 invalid 0 end
handle AttrRef : u32 invalid 0 end
handle PropRef : u32 invalid 0 end
handle StyleRef : u32 invalid 0 end
handle FragmentRef : u32 invalid 0 end
handle OutputRef : u32 invalid 0 end
```

If the hosted parser requires one handle island per declaration, split the declarations.

```moonlift
struct ViewName
    data: ptr(u8)
    len: index
end

struct ViewAttrSpec
    name: AttrRef
    value: ViewName
end

struct ViewNodeSpec
    ref: ViewNodeRef
    kind: u8              -- element | text | component | list | if | anchor
    tag: ViewName
    first_child: u32
    n_child: u32
    first_attr: u32
    n_attr: u32
end

struct ViewBindingSpec
    source_kind: u8       -- field | expr | item_field
    field: FieldRef
    expr_id: u32          -- compiler-private handle to Moonlift expr value if source_kind=expr
    node: ViewNodeRef
    target: u8            -- text | attr | prop | class | style | child_prop
    target_id: u32
end

struct ViewListenerSpec
    node: ViewNodeRef
    event_kind: u8
    handler: HandlerRef
end

struct ViewListSpec
    fragment: FragmentRef
    source_field: FieldRef
    key_field: FieldRef
    item_component_kind: u16
end

struct ViewPlan
    root: ViewNodeRef

    nodes: ptr(ViewNodeSpec)
    n_node: index

    attrs: ptr(ViewAttrSpec)
    n_attr: index

    bindings: ptr(ViewBindingSpec)
    n_binding: index

    listeners: ptr(ViewListenerSpec)
    n_listener: index

    lists: ptr(ViewListSpec)
    n_list: index
end
```

---

## 9. Runtime type forest

### 9.1 Handles

Stable identity uses handles, not raw pointers.  Handles that resolve to local
memory declare the public resolver domain and the product granted by the
successful resolver continuation.  `NodeId` is intentionally bare: it names a
browser-owned DOM node, not a backend memory product.

```moonlift
handle NodeId : u32 invalid 0 end
handle ComponentRef : u64 invalid 0
    domain Session
    target Component
end
handle SessionRef : u64 invalid 0
    domain App
    target Session
end
handle TaskRef : u32 invalid 0
    domain Session
    target Task
end
```

### 9.2 Transport products

```moonlift
struct Listener
    fd: i32
    port: u16
end

struct RingBuf
    data: ptr(u8)
    head: index
    tail: index
    cap: index
end

struct Conn
    fd: i32
    state: u8
    rx: RingBuf
    tx: RingBuf
    session: SessionRef
end

struct WsMessage
    kind: u8              -- text | binary
    payload: lease view(u8)
end
```

### 9.3 Event products

`EventIn` and `EventOwned` are the dispatch-level products (they differ in text provenance). `EventIn` carries only durable metadata; the borrowed socket text stays in region payloads until the generated dispatch wrapper projects it into the leaf-facing `Event`. Behavior leaves never see `EventIn` or `EventOwned` directly: the generated wrapper presents a provenance-agnostic **`Event`** whose `text` is `readonly view(u8)`, which a lease and an owned view both satisfy (§4.3, §6.6). So leaves are written once; only the wrapper and the store boundary are provenance-specific.

```moonlift
struct EventIn
    kind: u8              -- browser event kind; owner: route_event
    target: NodeId
    n: i64
end

struct EventOwned
    kind: u8              -- task/server event kind; owner: route_event_owned
    target: NodeId
    n: i64
    text: view(u8)        -- owned by task/session/host boundary
end

-- leaf-facing projection (what guards/actions receive):
struct Event
    kind: u8
    target: NodeId
    n: i64
    text: readonly view(u8)   -- provenance-erased; non-escaping read of either source
end
```

### 9.4 Mutation products

Mutations own payloads through `MutBuf`. A mutation stores offsets, not arbitrary views.

```moonlift
struct Mut
    op: u8
    node: NodeId
    a: u32
    b: u32
    z_off: u32
    z_len: u32
end

struct MutBuf
    data: ptr(u8)
    len: index
    cap: index
    n_mut: index
end
```

### 9.5 Routing products

```moonlift
struct Binding
    node: NodeId
    event_kind: u8
    component: ComponentRef
    handler: HandlerRef
end

struct BindingTable
    data: ptr(Binding)
    n: index
    cap: index
end
```

### 9.6 Component store

```moonlift
struct Component
    kind: u16
    state: u16
    ctx: ptr(u8)          -- generated Context layout, owned by session arena
    root: NodeId
    node_base: u32        -- this instance's NodeId block start; NodeId = node_base + ViewNodeRef
    dirty: u64
    parent: ComponentRef
    first_child: u32
    n_child: index
    first_list: u32
    n_list: index
end

struct ComponentSlot
    gen: u32
    live: bool
    component: Component
end

struct ComponentStore
    slots: ptr(ComponentSlot)
    n: index
    cap: index
    free_head: u32
end
```

### 9.7 Dirty queue

```moonlift
struct DirtyItem
    component: ComponentRef
    bits: u64
end

struct DirtyQueue
    items: ptr(DirtyItem)
    n: index
    cap: index
end
```

### 9.8 Keyed-list store

```moonlift
struct ListSlot
    key: u64
    node: NodeId
    child: ComponentRef
end

struct ListState
    anchor: NodeId
    items: ptr(ListSlot)
    n: index
    cap: index
end

struct ListItemSpec
    key: u64
    kind: u16
    data: ptr(u8)         -- generated item input product; owner: generated caller
end
```

### 9.9 Session/app products

```moonlift
struct Arena
    base: ptr(u8)
    used: index
    cap: index
    chunks: ptr(u8)
end

struct Task
    kind: u8
    tag: u32
    owner: ComponentRef
    state: u8
end

struct TaskStore
    data: ptr(Task)
    n: index
    cap: index
end

struct Session
    conn: Conn
    components: ComponentStore
    root: ComponentRef
    arena: Arena
    out: MutBuf
    routes: BindingTable
    dirty: DirtyQueue
    tasks: TaskStore
    next_node: u32
end

struct EventLoop
    fd: i32
    timers: ptr(u8)
end

struct App
    listener: Listener
    loop: EventLoop
    sessions: ptr(Session)
    n_session: index
    root_kind: u16
end
```

### 9.10 NodeId addressing law (compile-time vs runtime)

A single generated `<Name>_render_delta` / `<Name>_mount` must serve thousands of live instances. The bridge is a per-instance base offset:

```text
ViewNodeRef : template-local, COMPILE-TIME. Lives in the binding graph, route specs,
              and ViewPlan. Stable within a component KIND. Never crosses the wire.
NodeId      : RUNTIME, per-session. NodeId = Component.node_base + ViewNodeRef.
              Assigned at mount; the only node identity on the wire.
```

`component_mount` allocates a contiguous `NodeId` block of width `n_node(kind)` from `Session.next_node`, stores its start in `Component.node_base`, and emits create mutations. Thereafter every generated region resolves a template `ViewNodeRef` to a concrete `NodeId` by adding `node_base`; route-table entries are likewise materialized per instance. Keyed-list items get their own sub-blocks per mounted item. This is what lets the binding graph be per-kind while the wire is per-instance.

---

## 10. Runtime region tree

The actual `.mlua` header should use regular hosted regions, each closed with `end`. Signatures below are canonical.

### 10.1 Transport

```moonlift
extern os_accept(fd: i32): i32 as "os_accept" end
extern os_read(fd: i32, buf: ptr(u8), n: index): i64 as "os_read" end
extern os_write(fd: i32, buf: ptr(u8), n: index): i64 as "os_write" end
extern os_close(fd: i32): i32 as "os_close" end
extern os_poll_wait(epfd: i32, out: ptr(u8), n: index, ms: i32): i32 as "os_poll_wait" end
extern os_poll_add(epfd: i32, fd: i32, flags: u32): i32 as "os_poll_add" end

region ev_wait(loop: ptr(EventLoop), timeout_ms: i32;
    readable(fd: i32)
  | writable(fd: i32)
  | timer(id: u32)
  | woken
  | poll_failed(errno: i32))
end

region conn_read(invalidate c: ptr(Conn);
    data(bytes: lease view(u8))
  | would_block
  | peer_closed
  | read_failed(errno: i32))
end

region conn_write(invalidate c: ptr(Conn), bytes: view(u8);
    written
  | partial(wrote: index)
  | would_block
  | peer_closed
  | write_failed(errno: i32))
end

region rx_window(readonly c: ptr(Conn);
    window(bytes: lease view(u8))
  | empty)
end

region rx_consume(invalidate c: ptr(Conn), n: index;
    consumed
  | out_of_range)
end

region rx_compact(invalidate c: ptr(Conn);
    compacted
  | no_space
  | oom(needed: index))
end

func conn_close(invalidate c: ptr(Conn))
end
```

### 10.2 WebSocket codec

```moonlift
region ws_handshake(c: ptr(Conn), req: lease view(u8);
    accept(resp: view(u8))
  | incomplete
  | bad_request(code: i32))
end

region ws_decode(rx: lease view(u8);
    text(payload: lease view(u8), next: index)
  | binary(payload: lease view(u8), next: index)
  | continued(payload: lease view(u8), next: index)
  | ping(payload: lease view(u8), next: index)
  | pong(payload: lease view(u8), next: index)
  | close(code: u16, reason: lease view(u8), next: index)
  | incomplete
  | bad_frame(code: i32))
end

region ws_encode(out: ptr(MutBuf), opcode: u8, payload: view(u8);
    encoded
  | oom(needed: index))
end
```

### 10.3 Event decoding and routing

```moonlift
region event_decode(payload: lease view(u8);
    event(e: EventIn, text: lease view(u8))
  | bad_event(code: i32))
end

region event_decode_owned(payload: view(u8);
    event(e: EventOwned)
  | bad_event(code: i32))
end

region route_event(readonly sess: ptr(Session), e: ptr(EventIn);
    routed(component: ComponentRef, handler: HandlerRef)
  | no_listener(target: NodeId, kind: u8)
  | stale_component(component: ComponentRef))
end

region route_event_owned(readonly sess: ptr(Session), e: ptr(EventOwned);
    routed(component: ComponentRef, handler: HandlerRef)
  | no_listener(target: NodeId, kind: u8)
  | stale_component(component: ComponentRef))
end
```

### 10.4 Component access

```moonlift
region borrow_session(app: ptr(App), s: SessionRef;
    borrowed(session: lease ptr(Session))
  | missing(s: SessionRef)
  | closed(s: SessionRef))
end

region borrow_component(sess: ptr(Session), c: ComponentRef;
    borrowed(component: lease ptr(Component))
  | stale(c: ComponentRef)
  | missing(c: ComponentRef)
  | unmounted(c: ComponentRef))
end

region alloc_component(invalidate sess: ptr(Session), kind: u16;
    allocated(c: ComponentRef, component: lease ptr(Component))
  | bad_kind(kind: u16)
  | oom(needed: index))
end

region retire_component(invalidate sess: ptr(Session), c: ComponentRef;
    retired
  | stale(c: ComponentRef)
  | missing(c: ComponentRef))
end

region borrow_task(sess: ptr(Session), task: TaskRef;
    borrowed(task: lease ptr(Task))
  | missing(task: TaskRef)
  | completed(task: TaskRef))
end

region cancel_task(invalidate sess: ptr(Session), task: TaskRef;
    cancelled
  | missing(task: TaskRef)
  | completed(task: TaskRef))
end
```

### 10.5 Behavior/render split

```moonlift
region component_step(invalidate self: lease ptr(Component),
                      handler: HandlerRef,
                      e: ptr(Event),
                      dirty: ptr(DirtyQueue);
    handled
  | ignored
  | guard_blocked
  | raised(kind: u16, payload: lease view(u8))
  | spawned(task: Task)
  | bad_handler(handler: HandlerRef)
  | bad_state(state: u16)
  | action_failed(code: i32)
  | oom(needed: index))
end

region component_step_owned(invalidate self: lease ptr(Component),
                            handler: HandlerRef,
                            e: ptr(Event),
                            dirty: ptr(DirtyQueue);
    handled
  | ignored
  | guard_blocked
  | raised_owned(kind: u16, payload: view(u8))
  | spawned(task: Task)
  | bad_handler(handler: HandlerRef)
  | bad_state(state: u16)
  | action_failed(code: i32)
  | oom(needed: index))
end

region dispatch_event(invalidate sess: ptr(Session), e: ptr(EventIn), text: lease view(u8);
    dispatched
  | ignored
  | protocol_error(code: i32)
  | oom(needed: index))
end

region dispatch_event_owned(invalidate sess: ptr(Session), e: ptr(EventOwned);
    dispatched
  | ignored
  | protocol_error(code: i32)
  | oom(needed: index))
end

region render_dirty(invalidate sess: ptr(Session), out: ptr(MutBuf);
    rendered
  | component_gone(c: ComponentRef)
  | bad_binding(code: i32)
  | oom(needed: index))
end
```

**Termination invariant.** `render_dirty` drains the `DirtyQueue` in parent-before-child (tree-topological) order. A binding may propagate a parent field into a child prop (`child_update_prop` appends the child to the queue), but props flow only downward — a binding edge may never target an ancestor (enforced in §12.3). The propagation graph is therefore the component-tree DAG, the queue drains in bounded passes, and a render cycle is impossible by construction. Child→parent communication is outputs, which are a *behavior*-phase concern, never raised during render.

### 10.6 Mount/unmount/list

```moonlift
region component_mount(invalidate self: lease ptr(Component),
                       parent_node: NodeId,
                       sess: ptr(Session),
                       out: ptr(MutBuf);
    mounted(root: NodeId)
  | bad_component(kind: u16)
  | oom(needed: index))
end

region component_unmount(invalidate sess: ptr(Session), c: ComponentRef, out: ptr(MutBuf);
    unmounted
  | stale(c: ComponentRef)
  | missing(c: ComponentRef)
  | oom(needed: index))
end

region child_mount(invalidate parent: lease ptr(Component),
                   child_kind: u16,
                   slot: NodeId,
                   sess: ptr(Session),
                   out: ptr(MutBuf);
    mounted(child: ComponentRef, root: NodeId)
  | bad_child_kind(child_kind: u16)
  | oom(needed: index))
end

region child_update_prop(invalidate child: lease ptr(Component),
                         prop: FieldRef,
                         value: view(u8),
                         dirty: ptr(DirtyQueue);
    updated
  | bad_prop(prop: FieldRef)
  | type_mismatch(prop: FieldRef)
  | oom(needed: index))
end

region component_output_dispatch(invalidate sess: ptr(Session),
                                 parent: ComponentRef,
                                 child: ComponentRef,
                                 output_kind: u16,
                                 payload: lease view(u8));
    delivered
  | parent_gone(parent: ComponentRef)
  | child_not_owned(child: ComponentRef)
  | unhandled(output_kind: u16)
  | oom(needed: index))
end

region list_reconcile(invalidate ls: ptr(ListState),
                      parent: ComponentRef,
                      new_items: view(ListItemSpec),
                      sess: ptr(Session),
                      out: ptr(MutBuf);
    reconciled
  | duplicate_key(key: u64)
  | kind_changed(key: u64, old_kind: u16, new_kind: u16)
  | oom(needed: index))
end
```

### 10.7 Context materialization

```moonlift
region ctx_store_text(invalidate arena: ptr(Arena),
                      field: ptr(view(u8)),
                      src: lease view(u8);
    stored
  | oom(needed: index))
end

region ctx_store_owned_text(invalidate arena: ptr(Arena),
                            field: ptr(view(u8)),
                            src: view(u8);
    stored
  | oom(needed: index))
end

func ctx_release(invalidate arena: ptr(Arena), field: ptr(view(u8)))
end
```

### 10.8 Mutation construction

```moonlift
region mut_reserve(invalidate out: ptr(MutBuf), needed: index;
    ready
  | oom(needed: index))
end

region mut_node(invalidate out: ptr(MutBuf), op: u8, node: NodeId, a: u32, b: u32;
    emitted
  | oom(needed: index))
end

region mut_text(invalidate out: ptr(MutBuf), op: u8, node: NodeId, text: view(u8);
    emitted
  | oom(needed: index))
end

region mut_attr(invalidate out: ptr(MutBuf), node: NodeId, attr_id: u32, value: view(u8);
    emitted
  | oom(needed: index))
end

region mut_prop(invalidate out: ptr(MutBuf), node: NodeId, prop_id: u32, value: view(u8);
    emitted
  | oom(needed: index))
end

region mut_class(invalidate out: ptr(MutBuf), node: NodeId, class_id: u32, enabled: bool;
    emitted
  | oom(needed: index))
end

region mut_style(invalidate out: ptr(MutBuf), node: NodeId, style_id: u32, value: view(u8);
    emitted
  | oom(needed: index))
end

region mut_flush(invalidate c: ptr(Conn), out: ptr(MutBuf);
    flushed
  | would_block
  | peer_closed
  | write_failed(errno: i32))
end
```

### 10.9 Tasks and app runtime

```moonlift
region task_spawn(invalidate sess: ptr(Session), t: Task;
    spawned(task: TaskRef)
  | owner_gone(owner: ComponentRef)
  | oom(needed: index))
end

region task_poll(invalidate sess: ptr(Session);
    ready(e: EventOwned)
  | none
  | task_failed(task: TaskRef, code: i32)
  | owner_gone(owner: ComponentRef))
end

region session_on_bytes(invalidate sess: ptr(Session), bytes: lease view(u8);
    progressed
  | want_more
  | protocol_error(code: i32)
  | peer_closed
  | oom(needed: index))
end

region session_open(invalidate app: ptr(App), c: Conn;
    opened(s: SessionRef)
  | oom(needed: index))
end

region session_close(invalidate app: ptr(App), s: SessionRef;
    closed
  | missing(s: SessionRef))
end

region app_accept(invalidate app: ptr(App);
    session(s: SessionRef)
  | again
  | accept_failed(errno: i32)
  | oom(needed: index))
end

region app_run(invalidate app: ptr(App);
    stopped
  | poll_failed(errno: i32)
  | session_failed(sess: SessionRef, code: i32))
end

region app_broadcast(invalidate app: ptr(App), e: ptr(EventOwned);
    broadcasted
  | oom(needed: index))
end
```

### 10.10 Public ABI seals

```moonlift
func mwui_app_new(port: u16, root_component: u16, out_app: ptr(ptr(App))): i32
end

func mwui_app_run(app: ptr(App)): i32
end

func mwui_app_stop(app: ptr(App)): i32
end

func mwui_app_close(app: ptr(App)): i32
end

func mwui_send(sess: SessionRef, kind: u8, target: NodeId, payload: view(u8)): i32
end

func mwui_broadcast(app: ptr(App), kind: u8, payload: view(u8)): i32
end

func mwui_session_count(readonly app: ptr(App)): i32
end

func mwui_errmsg(readonly app: ptr(App)): ptr(u8)
end
```

---

## 11. Compiler pipeline

```text
ComponentSpec[]
  ↓ validate authoring tree
ContextSpec
StateSpec
ViewSpec
ChildSpec
TaskSpec
  ↓ resolve names
FieldRef / HandlerRef / ComponentKind / OutputRef / Node templates
  ↓ check Moonlift leaves
Guard region signatures
Action region signatures
Expr binding result types
Task region signatures
  ↓ lower behavior
<Name>_send region
<Name>_output_dispatch region
state enum
handler enum
  ↓ lower view
<Name>_mount region
<Name>_render_delta region
binding graph
route table fragment
keyed-list fragments
  ↓ lower app
component dispatch switch
mount dispatch switch
render dispatch switch
public ABI funcs
browser client assets (JS applier + shared id tables)
```

### 11.1 Generated artifacts per component

```text
struct <Name>_Context
region <Name>_send(...)
region <Name>_mount(...)
region <Name>_render_delta(...)
region <Name>_output_dispatch(...)
const <Name>_binding_graph
const <Name>_route_specs
const <Name>_state_ids
const <Name>_handler_ids
const <Name>_field_ids
```

### 11.2 Generated global dispatch

```text
region component_step_dispatch(...)
region component_mount_dispatch(...)
region component_render_dispatch(...)
region component_output_dispatch(...)
```

These switch on `Component.kind`. This is the stored encoded fact. Its owning consumers are the generated dispatch regions.

### 11.3 Generated provenance family

The event path is stamped for both provenances from one template (§6.6), not written twice:

```text
make_event_path("in")    → route_event,        dispatch_event,        component_step
make_event_path("owned") → route_event_owned,  dispatch_event_owned,  component_step_owned
```

Behavior leaves (guards/actions) are shared verbatim across both, because they take a provenance-agnostic `e: ptr(Event)` with `readonly view(u8)` text. Only the store boundary (`ctx_store_text` vs `ctx_store_owned_text`) and the wrapper differ, and both are generated.

---

## 12. Validation rules

### 12.1 Context

```text
field names unique
types are Moonlift type values
context fields that own bytes declare release/materialize policy
no derived data unless it is a phase output/cache with an owner region
```

### 12.2 State machine

```text
initial state exists
state names unique
handler names unique per component
target states exist
guard is a Moonlift region value
action is a Moonlift region value
guard/action continuation names are not in the reserved set (§6.5)
guard continuations are fully filled or explicitly ignored (inside the guard builder)
action exits are filled or mapped to policy
raise targets are declared DOMAIN outputs; oom/bad_*/action_failed use `fail`, not `raise`
raised outputs are declared
spawned tasks are declared
```

### 12.3 View

```text
node refs unique inside component
static attrs valid for target kind
dynamic lists are keyed
conditionals lower to 0/1 keyed fragments
event listener handlers exist
field-name strings (bind.text "f", prop.value "f", ...) resolve to a declared context field
binding expressions type-check against target kind
no binding edge targets an ancestor component (render-phase termination, §10.5)
child props match child input schema
child outputs are wired or explicitly ignored
no raw HTML unless TrustedHtml is used
mutation payloads are owned by MutBuf offsets
```

### 12.4 Memory

```text
event_decode returns EventIn metadata plus a text lease
borrowed event text may not be stored directly into context
ctx_store_text is the only borrowed-text materialization boundary
conn_read/rx_consume/rx_compact invalidate rx leases
ComponentRef/SessionRef/TaskRef are durable handles, never raw stable pointers
borrow_session/borrow_component/borrow_task are the handle-to-lease boundaries
component_unmount/session_close retire handles and release arenas
rendering never stores leases
```

---

## 13. Memory model

### 13.1 Ownership forest

```text
App
  owns Listener
  owns EventLoop
  owns Session store

Session
  owns Conn
  owns ComponentStore
  owns Arena
  owns MutBuf
  owns BindingTable
  owns DirtyQueue
  owns TaskStore

Conn
  owns rx RingBuf
  owns tx RingBuf

ComponentStore
  owns ComponentSlot[]

Component
  owns generated context bytes indirectly through Session.arena
  owns child/list references by handles/spans

Browser
  owns real DOM keyed by NodeId
```

### 13.2 Borrow/discharge law

```text
GRANT
  conn_read → lease view(u8)
  rx_window → lease view(u8)
  ws_decode → lease payload
  event_decode → EventIn metadata + text lease

FORWARD
  route_event forwards metadata
  dispatch_event forwards the text lease
  component_step receives generated Event projection
  guard/action regions that only inspect the text

DISCHARGE
  ctx_store_text copies lease into Session.arena
  EventOwned carries owned or host-controlled view

RETIRE
  rx_consume/rx_compact/conn_read refill invalidates socket leases
  ctx_release releases owned context text
  component_unmount retires component context/list state
  session_close releases arena and all components/tasks/routes
```

### 13.3 The breaker boundary

Storing into component context is the breaker boundary.

A borrowed event payload is like a database page borrow: valid only until the buffer moves. If a component needs to remember the value, it must copy it into owned context storage.

```text
event_decode.text : lease view(u8)  -- streaming/borrowed payload
ctx_store_text                     -- materialization
Context.email : view(u8)           -- owned by Session.arena
```

---

## 14. Wire model

### 14.1 Event stream

Browser sends encoded events:

```text
kind: u8
target: NodeId
n: i64
payload_len: varint
payload bytes
```

The backend decodes into `EventIn` where payload bytes are a lease into the rx buffer.

### 14.2 Mutation bytecode

Backend sends mutation bytecode batches. Mutation payloads live inside `MutBuf.data`; `Mut` stores offsets.

Core operations:

```text
MUT_CREATE_ELEM
MUT_CREATE_TEXT
MUT_SET_TEXT
MUT_SET_ATTR
MUT_SET_PROP
MUT_SET_STYLE
MUT_ADD_CLASS
MUT_RM_CLASS
MUT_INSERT
MUT_REMOVE
MUT_MOVE
MUT_LISTEN
MUT_BATCH
```

The browser client applies the batch to the real DOM keyed by `NodeId`.

---

## 15. Session transaction pipeline

The root event pipeline is:

```text
conn_read
  → rx_window
  → ws_decode
  → event_decode (EventIn + text lease)
  → route_event
  → dispatch_event (forwards text lease)
      → borrow_component
      → component_step_dispatch
      → DirtyQueue append
      → child output dispatch / task spawn as needed
  → render_dirty
      → component_render_dispatch
      → mut_* emitters
  → rx_consume
  → mut_flush
```

Behavior and rendering remain separated:

```text
dispatch_event = behavior only
render_dirty   = view projection only
mut_flush      = transport only
```

---

## 16. Cross-component semantics

### 16.1 Parent-child rule

No implicit DOM bubbling. Parent-child communication is typed output routing.

```text
child raises output
  → generated child output dispatch
  → parent handler
  → parent state machine transition
```

### 16.2 Child props

Parent-to-child data flow is generated prop update regions. A parent may not mutate child context directly.

```text
parent field dirty → child prop binding → child_update_prop → child dirty queue
```

### 16.3 Child lifetime

`ComponentRef` is durable identity. `borrow_component` grants temporary access. Tasks store `ComponentRef`, not `ptr(Component)`, so unmounting a component while a task is pending produces `owner_gone`, not a dangling pointer.

### 16.4 Imperative parent→child commands

Strict outputs-up / props-down cannot express "reset this child" or "focus this input." Do **not** add a downward behavior edge — it would break the render-phase termination guarantee (§10.5). Model a command as a **monotonic nonce prop**: the parent bumps a counter field, the child reacts to the prop change.

```lua
-- parent: bump on demand
action { bump_reset_nonce }        -- reset_nonce := reset_nonce + 1

-- child: a transition keyed on the prop change
state "ready" {
    on.prop_changed "reset_nonce" {
        action { do_reset },
        target "ready",
    },
}
```

The command rides the existing props-down channel, so the tree DAG and the termination story are untouched. This is the official pattern; no other parent→child behavior path is permitted.

---

## 17. Keyed-list semantics

A keyed list is the only bounded diff in the system.

Inputs:

```text
old ListState: key → NodeId/ComponentRef
new ListItemSpec[]: key + component kind + item input
```

Outcomes:

```text
reconciled
duplicate_key
kind_changed
oom
```

Policy:

```text
duplicate_key    = design/runtime error, caller decides
kind_changed     = named continuation; default filler may remove+mount
missing old key  = remove/unmount
new key          = mount/insert
same key         = update props/render item
moved key        = MUT_MOVE
```

No unkeyed dynamic list is accepted by the compiler.

---

## 18. Public runtime API

The public API is sealed, product-to-product C-style ABI. All meaningful choices inside remain protocols.

```text
mwui_app_new
mwui_app_run
mwui_app_stop
mwui_app_close
mwui_send
mwui_broadcast
mwui_session_count
mwui_errmsg
```

Components are defined at build time. The runtime API controls server/session/event injection only.

---

## 19. Naming rules

### 19.1 General

```text
products:       Noun / NounRec / NounSlot / NounStore
handles:        NounRef or NounId
regions:        verb_noun or noun_verb when scoped
continuations:  past-tense or outcome nouns: routed, stored, stale, missing
encoded owners: field comments name the owner region
```

### 19.2 Suffix underscore

Use trailing `_` only when it avoids a keyword collision or variant ambiguity:

```text
null_
int_
real_
type_
default_
end_
```

Do not decorate every continuation with `_`.

### 19.3 Avoid vague names

Prefer:

```text
read_failed(errno)
peer_closed
bad_frame(code)
stale_component(component)
oom(needed)
```

Avoid:

```text
ok
error(code)
failed
none
```

unless the consumer truly does not distinguish further.

---

## 20. Completion checklist

The blueprint is complete only if all of these are true:

```text
[ ] Every tree-shaped user surface is a Lua callable-table builder.
[ ] Every executable leaf is a Moonlift value, not a runtime Lua callback.
[ ] Behavior leaves are provenance-agnostic (readonly view(u8) text); lease/owned paths are generated.
[ ] Guard/action exits are scoped inside their builder and avoid reserved names.
[ ] Every durable runtime reference is a handle.
[ ] Every handle-to-pointer conversion is a resolving region.
[ ] EventIn payload text is a lease payload, not a durable field, and cannot be stored except via ctx_store_text.
[ ] Mutation payloads are owned by MutBuf offsets.
[ ] NodeId = Component.node_base + ViewNodeRef; ViewNodeRef never crosses the wire.
[ ] No binding edge targets an ancestor; render_dirty drains in bounded passes.
[ ] oom/failures use the protocol oom/fail exit, never the raise/output channel.
[ ] There is no implicit event bubbling.
[ ] Parent-child communication is explicit output protocol routing; commands ride a nonce prop.
[ ] Behavior dispatch and render projection are separate session phases.
[ ] Lists are keyed; conditionals are 0/1 keyed fragments.
[ ] Browser applies mutation bytecode; backend never diffs VDOM.
[ ] Component kind/state/handler IDs are stored encodings with generated owner regions.
[ ] Public APIs are sealed funcs; internal choices are protocols.
```

---

## 21. Final compressed doctrine

```text
Lua shapes the trees.
Moonlift values are the leaves.
Factories check the forest.
Regions wire the machines.
Handles survive time.
Leases grant momentary access.
Context is where memory comes to rest.
Dirty fields become mutation bytecode.
The browser reflects; it does not decide.
```

---

## 22. Browser client

The browser client is **just JavaScript** — a small patch applier and event encoder. It is not a Moonlift machine and not WASM. WASM in the browser cannot touch the DOM or the socket directly; it must import them as host functions, so a patch applier — whose entire job *is* DOM calls — would pay the JS↔WASM boundary cost on every mutation to run trivial per-op logic. For this workload that is overhead, not speed. The client is a few hundred lines of JS, fully specified by the **wire format** it consumes; the language it is written in is not a contract.

### 22.1 Responsibilities

```text
- hold the real DOM, keyed by NodeId
- apply mutation bytecode batches to the DOM
- capture DOM events on listened nodes, encode them, send them back
- nothing else: it never decides, never branches on app state
```

### 22.2 Wire format (the contract — language-independent)

A batch is a length-prefixed sequence of ops; payloads are inline, referenced by offset/len within the batch (the mirror of `MutBuf` offsets on the backend):

```text
batch   ::= u32 n_op  op*
op      ::= u8 opcode  operands
operands per opcode:
  MUT_CREATE_ELEM  node:u32  parent:u32  tag_id:u16
  MUT_CREATE_TEXT  node:u32  parent:u32  text:(off:u32,len:u32)
  MUT_SET_TEXT     node:u32  text:(off,len)
  MUT_SET_ATTR     node:u32  attr_id:u16  value:(off,len)
  MUT_SET_PROP     node:u32  prop_id:u16  value:(off,len)
  MUT_SET_STYLE    node:u32  style_id:u16 value:(off,len)
  MUT_ADD_CLASS    node:u32  class_id:u16
  MUT_RM_CLASS     node:u32  class_id:u16
  MUT_INSERT       node:u32  parent:u32   ref:u32
  MUT_REMOVE       node:u32
  MUT_MOVE         node:u32  parent:u32   ref:u32
  MUT_LISTEN       node:u32  event_kind:u8
```

`tag_id`/`attr_id`/`prop_id`/`class_id`/`style_id`/`event_kind` are small interned ids from a shared table emitted at build time (the client ships the same id table the compiler used), so the wire carries no strings except dynamic text/values. The event direction uses the `EventIn` wire shape (§14.1).

### 22.3 Client model

The client keeps one map, `NodeId → DOM node`, the per-session mirror of the backend's NodeId namespace — the single shared coordinate system across the socket. On a batch it walks the ops and makes the corresponding DOM call; on a listened event it looks up the source NodeId, encodes `(kind, target, n, payload)`, and sends it. That is the entire client.

### 22.4 What the client never does

```text
- no diffing (the backend already computed the minimal mutation set)
- no app state, no guards, no transitions
- no string-keyed lookups on the hot path (ids are interned)
```

The asymmetry is the whole point: all decisions live in compiled Moonlift machines; the browser is a fast, dumb, swappable reflector.

### 22.5 WASM is not part of the framework

WASM earns its place only for a genuine compute kernel that runs many iterations *without* crossing back to JS per step — a physics tick, a geometry/layout solver, signal/image processing, a parse over a large buffer. That is the opposite shape from the patch applier (which is maximum boundary-crossing, minimum per-call compute). If an app happens to have such a kernel, the author may compile *that one kernel* Moonlift → C → emcc and call it from their JS. It is an optional, app-level choice, not a moonlift-webui feature, and the framework specifies nothing about it.

---

## 23. Final compressed doctrine

```text
Lua shapes the trees.
Moonlift values are the leaves.
Factories check the forest.
Regions wire the machines.
Handles survive time.
Leases grant momentary access.
Context is where memory comes to rest.
Dirty fields become mutation bytecode.
The browser reflects; it does not decide.
```
