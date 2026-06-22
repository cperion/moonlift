# Moonlift Conventions

Moonlift code should be flat, explicit, and grep-shaped.  The language core is
small; conventions should make the semantic structure easier to see, not hide
it behind framework names or folder depth.

## File Names

Use lowercase words separated by `_`.

```text
<subsystem>_header.mlua
<subsystem>_<machine>.mlua
<subsystem>_build.lua
<subsystem>_blueprint.md
```

Examples:

```text
mwui_header.mlua
mwui_component_store.mlua
mwui_session_store.mlua
mwui_transport.mlua
mwui_event.mlua
mwui_render.mlua
mwui_mutation.mlua
mwui_task.mlua
mwui_app.mlua
mwui_build.lua
mwui_blueprint.md
```

Avoid vague names:

```text
core.mlua
utils.mlua
helpers.mlua
manager.mlua
impl.mlua
runtime.mlua
```

If a file implements a machine, the filename should name that machine.

## Folder Shape

Prefer one flat folder per subsystem.

```text
experiments/mwui/
  mwui_header.mlua
  mwui_component_store.mlua
  mwui_event.mlua
  mwui_render.mlua
  mwui_app.mlua
  mwui_build.lua
  mwui_blueprint.md
```

Do not split small systems into deep folders like `core/runtime/protocols`.
Depth must buy ownership or build isolation, not aesthetic grouping.

## Header Files

`*_header.mlua` is the system contract.  It may contain:

```moonlift
struct
union
handle
extern
region ... end
expr ... end
func ... end
```

It should not contain bodies:

```moonlift
entry
block
jump
return
```

Headers are allowed to be rich.  They should declare products, durable identity,
access protocols, machines, and ABI seals before implementation exists.

The usual header shape is:

```lua
local M = {
    T = {},
    R = {},
    F = {},
}

local T = M.T
local R = M.R
local F = M.F

-- identity and stores
-- products
-- access protocols
-- machines
-- ABI seals

return M
```

For an LLPVM stack, the preferred contract may be one larger canonical machine
definition file instead of a separate header.  This is appropriate when the
same file owns the language declarations, type forest, worlds, machines, phase
metadata, row profiles, constants, and public Moonlift `T/R/F` declarations.
In that shape, the file should still expose the usual tables:

```lua
local M = {
    T = {},
    R = {},
    F = {},
}

M.vm = ll.vm { ... }
-- LLPVM languages/worlds/machines/phases
-- Moonlift products/protocols/ABI seals

return M
```

Keep compatibility headers thin and Moonlift-aware:

```lua
local M = moon.require("mlui_stack")
return { T = M.T, R = M.R, F = M.F, stack = M }
```

Do not use plain Lua `dofile` to load `.mlua` modules that contain Moonlift
declarations.  Use `moon.require`, `moon.loadfile`, or `moon.dofile`.

## Implementation Files

`<subsystem>_<machine>.mlua` imports the header and implements one semantic
machine or a small family of adjacent machines.

```lua
local H = moon.require("mwui_header")
local T = H.T
local R = H.R
local F = H.F

local borrow_component = region @{R.borrow_component}
entry start()
    ...
end
end

return {
    borrow_component = borrow_component,
}
```

Implementation files may define private helpers.  Public products, handles,
regions, and ABI functions belong in the header first.

## Group By Purpose

Within a header, prefer semantic grouping over syntax-kind grouping.

Good:

```text
Component Identity And Store
  ComponentRef
  Component
  ComponentSlot
  ComponentStore
  borrow_component
  alloc_component
  retire_component

Event Machine
  EventIn
  EventOwned
  Event
  event_decode
  route_event
  dispatch_event
```

Weak:

```text
All handles
All structs
All regions
```

Put declarations near the machine that gives them meaning.

## Naming

Products are nouns:

```text
Component
ComponentSlot
ComponentStore
DirtyQueue
EventOwned
```

Handles name durable identity:

```text
ComponentRef
SessionRef
TaskRef
NodeId
```

Use `Ref` for backend-resolved identity.  Use `Id` for external, wire, browser,
or opaque identity that does not resolve to a backend lease.

Regions are verbs or verb_noun:

```text
borrow_component
alloc_component
retire_component
route_event
dispatch_event
render_dirty
ctx_store_text
```

ABI functions are the only place where status-code APIs are expected:

```text
mwui_app_new
mwui_app_run
mwui_send
```

## Lua Authoring Surfaces

Lua DSLs should keep semantic constructors visible in the call path. Prefer
named callable/type tables over generic helper functions when the user is
constructing a typed IR value.

Good LLPVM style:

```lua
local moon = require "moonlift"

local Expr = vm.language "Expr"
local Node = Expr "Node"
Node.Int = { value = moon.i64 }
Node.Add = { left = Node, right = Node }

local raw = Expr:world()
local one = raw.Node.Int { value = 1 }
local two = raw.Node.Int { value = 2 }
local sum = raw.Node.Add { left = one, right = two }
```

Weak style:

```lua
ll.node
ll.ref "Node"
vm.op "Add" { left = one, right = two }
```

The weak form hides the type forest behind an erased helper name. If a subsystem
is authoring a VM instruction language, use type tables and named constructors
so `rg 'Node.Add'` finds the semantic operation directly.

## Continuations

Keep the visual grammar meaningful: commas are for product-shaped lists, and
`|` is for semantic alternatives. In a region signature, runtime params and
payload fields are products; continuation exits are the protocol alternatives.

Continuation names are outcomes, not status words.

Prefer:

```moonlift
borrowed(component: lease(sess) ptr(Component))
allocated(c: ComponentRef, component: lease(sess) ptr(Component))
routed(component: ComponentRef, handler: HandlerRef)
would_block
peer_closed
bad_frame(code: i32)
stale(c: ComponentRef)
missing(c: ComponentRef)
oom(needed: index)
```

Avoid:

```moonlift
ok
done
error(code: i32)
failed
none
```

Use vague names only when the consumer truly does not distinguish further.

## Handle And Lease Law

A handle is durable identity.  It never grants memory access by itself.

For C-bound code, distinct handle types must remain distinct in Moonlift even
when they share the same raw C representation. `FooRef` and `BarRef` may both
lower to `uint32_t`, but protocols and helper functions must keep their typed
handle names in source instead of collapsing them to raw integers.

Store-resolved handles declare their resolver facts:

```moonlift
handle ComponentRef : u64 invalid 0
    domain Session
    target Component
end
```

`domain` names the public resolver product.  It does not have to be the physical
field that stores the target.  `target` names the product granted by a
successful resolver continuation.

The resolver region grants the lease:

```moonlift
region borrow_component(readonly sess: ptr(Session), c: ComponentRef;
    borrowed(component: lease(sess) ptr(Component))
  | stale(c: ComponentRef)
  | missing(c: ComponentRef)
  | unmounted(c: ComponentRef))
end
```

Rules:

- `Ref` handles that resolve to backend memory should have `domain` and `target`.
- Every `handle ... target T` should have a resolver region that grants
  `lease(domain_param) ptr(T)` or `lease(domain_param) view(T)`.
- The resolver domain parameter must be `readonly` or `preserve`, so live
  leases cannot be invalidated through the same region signature.
- Failed continuations must not carry the target lease.
- Invalidating operations mark the owner parameter with `invalidate`.
- Borrowed views are not stored except through a named materialization region.
- Stable fields should use handles, not raw pointers.

## Handle Representation

Reusable store-backed `Ref` handles should carry a generation number.

```text
Ref handle = slot index + generation
Store slot = generation + live bit + product
```

Without a generation, an old handle can accidentally resolve to a new occupant
after a slot is retired and reused.  With a generation, the resolver can reject
that old handle as `stale`.

```moonlift
struct ComponentSlot
    gen: u32,
    live: bool32,
    component: Component,
end

struct ComponentStore
    slots: ptr(ComponentSlot),
    n: index,
    cap: index,
    free_head: u32,
end
```

Resolver shape:

```text
unpack handle -> index, gen
index out of range      -> missing
slot not live           -> missing
slot.gen != gen         -> stale
otherwise               -> borrowed(lease(store) ptr(slot.product))
```

Rules:

- `Ref` plus reusable store means slot + generation.
- `Id` for external identity does not require generation.
- Monotonic never-reused handles may omit generation, but the reason should be
  visible in the header or blueprint.
- Handle packing and unpacking are store-private trust boundaries.
- Public code should use resolver regions, not representation operations.

## Owned Obligations

Use `owned T` for resources that must be explicitly discharged or transferred.
See `OWNED_CFG_DESIGN.md` for the full language design.

Short rule:

```text
handle TRef    durable identity
lease ptr(T)   anonymous temporary access
lease(s) ptr(T) store-tied temporary access from resolver parameter s
owned TRef     mandatory discharge authority
```

`owned` does not grant access and does not create an implicit destructor.  The
cleanup machine is a normal region, and the CFG checker must prove every path
consumes or transfers the owned value.

```moonlift
region close_session(app: ptr(App), s: owned SessionRef;
    closed
  | missing(s: owned SessionRef))
end
```

If an operation preserves the obligation, the continuation returns it:

```moonlift
region poll_task(task: owned TaskRef;
    pending(task: owned TaskRef)
  | completed
  | failed(code: i32))
end
```

## Access Verbs

Use consistent verbs for memory machines:

```text
borrow_*    handle -> temporary lease
alloc_*     create product, return handle and possibly lease
retire_*    invalidate durable identity
resolve_*   non-borrowing lookup or identity resolution
store_*     materialize borrowed data into owned storage
release_*   release owned storage
cancel_*    request task/resource cancellation
```

If a verb means something else in a subsystem, write the convention in that
subsystem's blueprint.

## Lua And Moonlift Boundary

Lua is the generation and policy layer.  Moonlift is the monomorphic native
artifact.

Use Lua for:

```text
factories
tables of generated declarations
name resolution
component authoring APIs
platform selection
code generation
```

Use Moonlift for:

```text
products
handles
regions
typed control
memory contracts
native bodies
ABI seals
```

Do not encode Moonlift semantics in Lua strings, callbacks, or side tables when
an ASDL declaration can carry the meaning.

## Grep Shape

Conventions should make these queries complete:

```sh
rg '^T\..* = handle'      # durable identity
rg '^R\.borrow_'          # resolver regions
rg '^R\.alloc_'           # allocation regions
rg '^R\.retire_'          # retirement regions
rg 'lease ptr'            # access grants
rg 'invalidate .*ptr'     # mutation boundaries
rg '^F\.'                 # ABI seals
```

If an important architectural question cannot be answered with a simple search,
the declarations probably need a better name or a stronger ASDL shape.
