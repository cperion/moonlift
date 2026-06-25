# Owned CFG Design

`owned` is Lalin's explicit resource-obligation mechanism.  It is not RAII,
not `Drop`, not lifetime inference, and not a second hidden control-flow system.
It is a linear fact carried by the typed CFG.

The slogan:

```text
lease = temporary access
owned = mandatory discharge
region = the protocol that proves what happened
```

## Core Meaning

`owned T` means: this control path owns a value of type `T`, and that ownership
must be resolved exactly once.

A live owned value may be:

```text
consumed by a region/function that accepts owned T
transferred to another block as owned T
returned as owned T
yielded as owned T
```

It may not be:

```text
copied
dropped silently
passed to a plain T parameter
observed as plain T by accident
stored into ordinary durable memory
used after transfer
converted to T by accident
```

There is no implicit cleanup at scope exit.  If a value is owned at a return,
yield, trap, or region end, the checker rejects the program unless that edge
transfers the ownership explicitly.

## Syntax

`owned` is a type wrapper:

```lua
owned [SessionRef]
owned [FileRef]
```

It composes with the existing type grammar:

```lua
owned [ComponentRef]
lease [ptr [Component]]
readonly [ptr [Session]]
```

`owned lease T` is invalid.  A lease is temporary access, not a durable resource
obligation.  `lease owned T` is also invalid.

Access modifiers apply outside-in exactly like other type wrappers:

```lua
readonly [ptr [Store]]      -- access fact
owned [StoreRef]            -- ownership obligation
```

`owned ptr(T)` and access-qualified owned pointers are rejected.  Raw pointer
ownership requires allocator provenance, deallocator identity, and alias rules;
Lalin represents that as a named resource handle plus protocols, not as a
bare address with an ownership wrapper.

## Type Shape

ASDL:

```text
Type =
    ...
  | TOwned(Type base)
```

`TOwned(base)` is explicit semantic structure.  It is not represented as a flag
on bindings or a naming convention.

Owned-ness is part of type equality.  `T` and `owned T` do not match.

## Ownership Is Not Uniqueness

`owned T` is a discharge authority.  It is not a proof that no other plain `T`
values exist anywhere in the program.

For handles this distinction matters:

```text
SessionRef        copyable durable identity
owned SessionRef  obligation to eventually close/transfer one session authority
```

Other `SessionRef` values may exist.  After the owned authority is closed, those
plain handles become stale at resolver boundaries.  The owned value proves
cleanup responsibility, not global alias exclusion.

This keeps `owned` aligned with Lalin handles: stale use is a named runtime
outcome, while forgetting to discharge the authority is a compile-time CFG
error.

## Ownership State

The typechecker tracks a linear ownership state in addition to the value
environment.

Conceptually:

```text
TypeCheckEnv =
  values
  types
  layouts
  return_ty
  yield_ty
  owned_live: binding-id set
```

A binding enters `owned_live` when its type is `owned T`.

Examples:

```lua
fn. f { s [owned [SessionRef]] } {
    ...
}
```

At function entry, `s` is live.

```lua
let. s [owned [SessionRef]] { make () }
```

After the `let`, `s` is live.

An owned binding leaves `owned_live` only when ownership is moved out.

## Move Sites

An expression that refers to a live owned binding is a move when it appears in an
owned-consuming position.

Owned-consuming positions:

```text
argument to parameter of type owned T
jump argument to block parameter of type owned T
continuation argument to parameter of type owned T
return value when function result is owned T
yield value when region result is owned T
constructor field only if the constructed aggregate is itself owned
```

Non-consuming uses of a live owned binding are illegal.  To inspect the
resource, call or emit a protocol that accepts `owned T` and returns `owned T`
on every continuation that preserves the obligation.

Therefore, a non-consuming operation over an owned resource is written as a
region that accepts the owner and returns it on every continuation that preserves
the obligation:

```lua
region. borrow_owned_session
  { app [readonly [ptr [App]]], s [owned [SessionRef]] }
  {
    borrowed { s [owned [SessionRef]], session [lease (app, ptr [Session])] },
    missing { s [owned [SessionRef]] },
  }
```

The operation still owns `s` while it runs.  The `borrowed` and `missing`
continuations explicitly transfer the ownership obligation back to the caller.

This is illegal:

```lua
fn. bad { s [owned [SessionRef]] } [SessionRef] {
    ret (s)
}
```

This is legal:

```lua
fn. pass { s [owned [SessionRef]] } [owned [SessionRef]] {
    ret (s)
}
```

This is illegal because `s` is used after move:

```lua
fn. bad { app [ptr [App]], s [owned [SessionRef]] } {
    close_session (app, s)
    close_session (app, s)
}
```

## Copying

`owned T` is not copyable.

The checker rejects:

```lua
let. a [owned [FileRef]] { open_file (...) }
let. b [owned [FileRef]] { a }
let. c [owned [FileRef]] { a }
```

The first assignment moves `a` into `b`; the second use of `a` is use-after-move.

Plain `T` may still be copyable according to normal rules.  `owned T` is a
different type.

## Functions

Functions can consume ownership by taking `owned` parameters:

```lua
fn. destroy_buffer { buf [owned [BufferRef]] } {
    ...
}
```

Function calls have one outcome: if the call typechecks, all `owned` arguments
are moved into the callee and the result ownership is determined by the result
type.  A function that preserves an owned obligation must return it explicitly.

```lua
fn. transfer { s [owned [SessionRef]] } [owned [SessionRef]] {
    ret (s)
}
```

Function bodies must end with no live owned obligations unless those obligations
are returned.

## Regions

Regions are the primary ownership protocol mechanism.

Input ownership:

```lua
region. close_session
  { app [ptr [App]], s [owned [SessionRef]] }
  {
    closed,
    missing { s [owned [SessionRef]] },
  }
```

The call/emit starts by moving `s` into the region.  Each continuation says what
happens to ownership on that edge.

In the example:

```text
closed      consumes the session
missing     returns ownership to the caller
```

This is the central Lalin design point: ownership effects are
per-continuation, not hidden effects.

Preserving operations must return the owner:

```lua
region. poll_task
  { task [owned [TaskRef]] }
  {
    pending { task [owned [TaskRef]] },
    completed,
    failed { code [i32] },
  }
```

Here `pending` preserves the obligation, while `completed` and `failed` consume
it.  If failure should remain caller-owned, the failure continuation must carry
`task: owned TaskRef`.

Another valid shape:

```lua
region. retire_component { sess [ptr [Session]], c [owned [ComponentRef]] } { retired, stale, missing }
```

Here every continuation consumes `c`.  Even failure means the retirement machine
has taken responsibility for the invalid handle.

If the caller must keep responsibility on failure, the signature must say so:

```lua
region. retire_component
  { sess [ptr [Session]], c [owned [ComponentRef]] }
  {
    retired,
    stale { c [owned [ComponentRef]] },
    missing { c [owned [ComponentRef]] },
  }
```

## `emit` And Continuations

`emit` transfers owned arguments into the emitted region.  Continuation block
parameters receive whatever ownership the selected continuation grants.

```lua
emit. close_session { app, s } {
    closed = done,
    missing = retry,
}

block. retry { s [owned [SessionRef]] } {
    ...
}
```

The fill target for a continuation with `owned` payload must bind those payloads
to block params of matching `owned` type.  A continuation cannot silently drop an
owned payload by filling it to a block that lacks the parameter.

## Region Calls

Lalin has a distinction between zero-cost `emit` and expression-style region
calls.  Region calls package continuations into generated product data, and
product data is not allowed to contain linear authority.

Rule:

```text
If any continuation payload contains owned T, expression-style region call is rejected.
Use emit.
```

This matches the existing lease rule: temporary access must stay in control
flow.  Ownership obligations also stay in typed control flow; region `call`
uses generated product payloads and therefore cannot transport linear
authority.

## Blocks And Jumps

Block params may be owned:

```lua
block. use { s [owned [SessionRef]] } {
    jump. close { s = s }
}
```

A jump to a block transfers ownership to that block if the target parameter is
`owned`.  After the jump statement the current path terminates, so no use-after
move can occur on that path.

Jump argument checking must enforce:

```text
target param owned T requires argument owned T
target param T rejects argument owned T
owned target arg moves the source binding
```

## Branches And Merge

`if` and `switch` branches must agree on ownership state when control continues.

Legal:

```lua
when (cond) {
    assert_ (true)
} {
    assert_ (true)
}
-- s is still live on both paths
```

Legal:

```lua
when (cond) {
    close_session (app, s)
    ret ()
} {
    close_session (app, s)
    ret ()
}
```

Also legal: one branch consumes and terminates, the other keeps ownership and
continues.

```lua
when (cond) {
    close_session (app, s)
    ret ()
} {
    assert_ (true)
}
close_session (app, s)
ret ()
```

Illegal:

```lua
when (cond) {
    close_session (app, s)
} {
    -- s remains live
}
ret ()
```

The two paths reach `ret ()` with different ownership states.  The checker must
reject before or at the merge.

For a branch construct that does not syntactically terminate, all surviving
branches must produce the same `owned_live` set.

## Terminating Statements

These statements require the ownership state to be empty, except for ownership
transferred by the statement itself:

```text
return void
yield void
trap
falling off a function body
falling off a region block
```

These statements may transfer ownership:

```text
return owned T
yield owned T
jump owned block params
jump continuation with owned params
emit owned args
function call owned args
```

## `let` And `var`

`let` may bind owned values:

```lua
let. f [owned [FileRef]] { ... }
```

`var owned T` is rejected.

Reason: `var` is ordinary mutable storage.  A linear resource obligation must
stay in the CFG, not in a stack cell with hidden empty/full state.  Use block
parameters to thread changing ownership state.

## Fields And Aggregates

Durable fields of type `owned T` are rejected.

```lua
struct. Bad { f [owned [FileRef]] }
```

Reason: Lalin does not make products secretly linear.  If a product owns a
resource, store a durable handle in the product and carry the discharge
authority separately as `owned HandleRef` through the protocol that closes or
transfers it.

Aggregate constructors may not capture owned fields into ordinary durable
values.  Owned authority is a CFG fact, not product data.

## Leases And Owned Values

`lease` and `owned` solve different problems.

```text
lease ptr(T) = anonymous temporary access, no ownership
lease(store) ptr(T) = store-tied temporary access from resolver parameter store
owned T      = resource obligation, no implicit access
```

An owned handle does not grant access:

```lua
owned [ComponentRef]
```

still requires:

```lua
borrow_component (sess, c; borrowed = ...)
```

Borrowing from owned identity is allowed only through explicit resolver regions.
The resolver may accept either `ComponentRef` or `owned ComponentRef`.
If the handle declares `domain Store target T`, the successful continuation
must return `lease(store_param) ptr(T)` or `lease(store_param) view(T)`, and
`store_param` must be a `readonly` or `preserve` pointer/view of the domain.

If it accepts `ComponentRef`, the caller must already have a plain copyable
handle.  If it accepts `owned ComponentRef`, it must return the owner on every
continuation that preserves the close/retire obligation.

## Handles

Common pattern:

```lua
handle. SessionRef {
    invalid = 0,
    domain = "App",
    target = "Session",
}

region. open_session
  { app [ptr [App]] }
  {
    opened { s [owned [SessionRef]] },
    oom { needed [index] },
  }

region. borrow_session
  { app [readonly [ptr [App]]], s [SessionRef] }
  {
    borrowed { session [lease (app, ptr [Session])] },
    missing { s [SessionRef] },
  }

region. borrow_owned_session
  { app [readonly [ptr [App]]], s [owned [SessionRef]] }
  {
    borrowed { s [owned [SessionRef]], session [lease (app, ptr [Session])] },
    missing { s [owned [SessionRef]] },
  }

region. close_session
  { app [ptr [App]], s [owned [SessionRef]] }
  {
    closed,
    missing { s [owned [SessionRef]] },
  }
```

The copyable handle `SessionRef` is durable identity.  The owned wrapper says
this particular control path has responsibility to close or transfer it.  The
owned resolver form is explicit about preserving that responsibility.

## Diagnostics

The checker should distinguish these errors:

```text
owned dropped
owned use after move
owned observed without transfer
owned passed to non-owned parameter
owned stored in durable field
owned captured in aggregate
owned branch mismatch
owned var cell unsupported
owned region call payload unsupported
owned emit target mismatch
owned lease composition invalid
```

Diagnostics should name the binding when possible:

```text
owned value `s` is still live at return
owned value `s` was moved here and used again there
branch leaves owned obligations inconsistent: then={}, else={s}
```

## Checker Algorithm

The checker runs over typed statements with an ownership state.

State:

```text
owned_live: binding-id -> name/type
```

On binding introduction:

```text
if binding.ty is owned T:
    add binding to owned_live
```

On owned-consuming expression:

```text
if expression is ref to live owned binding:
    remove binding from owned_live
else:
    reject if not an owned-producing expression
```

On use of moved binding:

```text
if expression is ref to owned binding not in owned_live:
    owned use after move
```

On branch:

```text
check then with copy(state)
check else with copy(state)
if both continue:
    require same owned_live keys
if one terminates:
    use continuing state
if both terminate:
    result state is unreachable
```

On jump/return/yield:

```text
apply explicit ownership transfers
require remaining owned_live empty
mark path terminated
```

The implementation may encode "terminated" separately from `TypeCheckEnv`, but
the semantic rule is part of the language design.

## Non-Goals

No implicit destructors.

No scope-exit cleanup.

No inferred lifetimes.

No owned mutable cells.

No durable owned fields or owned aggregates.

No implicit dereference of owned handles.

## Design Consequence

Lalin gets explicit destruction without destructors:

```text
The developer authors the cleanup machine.
The CFG typechecker proves every path uses it or transfers ownership.
```

This preserves Lalin's core taste: mechanisms are explicit, protocols are
typed, and control edges carry the facts that become true on that edge.
