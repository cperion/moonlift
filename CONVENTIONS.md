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

## Continuations

Continuation names are outcomes, not status words.

Prefer:

```moonlift
borrowed(component: lease ptr(Component))
allocated(c: ComponentRef, component: lease ptr(Component))
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
region borrow_component(sess: ptr(Session), c: ComponentRef;
    borrowed(component: lease ptr(Component))
  | stale(c: ComponentRef)
  | missing(c: ComponentRef)
  | unmounted(c: ComponentRef))
end
```

Rules:

- `Ref` handles that resolve to backend memory should have `domain` and `target`.
- Every `handle ... target T` should have a resolver region that grants
  `lease ptr(T)` or `lease view(T)`.
- Failed continuations must not carry the target lease.
- Invalidating operations mark the owner parameter with `invalidate`.
- Borrowed views are not stored except through a named materialization region.
- Stable fields should use handles, not raw pointers.

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
