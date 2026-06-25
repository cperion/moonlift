# Lalin Conventions

These conventions keep the repository grepable and keep the language family
reduced.

## Names

Use `Lalin` for the project and native language family.

Use `lalin` for package names, module names, file stems, CLI names, and local
variables that hold the public module.

Use `ll` as the short authoring namespace inside family DSL code:

```lua
ll.fn. add { a [ll.i32], b [ll.i32] } [ll.i32] {
  ll.ret (a + b),
}
```

Use exact subsystem prefixes:

```text
llb_      LLB substrate concepts
llpvm_    LLPVM concepts
llisle_   Llisle concepts
luajit_   LuaJIT backend concepts
stencil_  stencil descriptor/materializer concepts
schema_   schema projection/runtime concepts
```

Avoid vague names such as `helper`, `info`, `data`, `thing`, or `state` when a
semantic name exists.

## Files

Prefer one flat folder per subsystem. Split by semantic ownership, not by
chronological step.

Good:

```text
lua/lalin/code_type.lua
lua/lalin/code_validate.lua
lua/lalin/code_kernel_plan.lua
```

Bad:

```text
lua/lalin/core/runtime/protocols/helpers/misc.lua
```

Documentation should be small and authoritative. Migration journals, old
backend notes, and duplicated design drafts should be archived outside `docs/`
or removed.

## Lua DSL Style

Use namespace prefixes in examples unless the surrounding text is explicitly
about `use()` globals.

Preferred:

```lua
ll.fn. add { a [ll.i32], b [ll.i32] } [ll.i32] {
  ll.ret (a + b),
}
```

Spacing:

```lua
i :lt (n)
value :eq (target)
as [ll.i32] (x)
```

Keep the space after the receiver and before the call parentheses. The method
comparison form is the readable replacement for unavailable Lua operator
overloading.

## Fragments

Reusable DSL pieces should return role-tagged fragments:

```lua
local function buffer_params()
  return ll.product {
    p [ll.ptr [ll.u8]],
    n [ll.index],
  }
end
```

Avoid returning raw arrays from public metaprogramming helpers.

## Regions

Use regions for control machines. Prefer `emit` for local composition. Use
region `call` when the region needs a frame for recursion, profiling, debugging,
or instrumentation. Functions are the sealed product-return ABI substrate.

`region.` is LLB-owned. Lalin consumes it; Lalin does not own the generic region
concept.

Do not introduce semantic APIs named `stream`. Pull-shaped behavior is a region
protocol lowered through GPS.

## ASDL And Schemas

ASDL/schema values are semantic products. Do not hide meaning in strings,
callbacks, or side tables.

If lowering needs a fact, represent it in schema first.

## Backends

The active runtime backend is LuaTrace bytecode copy-patch.

Backend code should consume typed facts:

- type and ABI facts
- bounds/alias/residence facts
- kernel descriptors
- schedule policies
- stencil descriptors
- materializer constraints

No backend should rediscover semantics by pattern-matching user source text.

## Ownership

Owned values move exactly once. Leases are explicit. Handle representation casts
are trust boundaries.

Do not put owned values in aggregates, fields, or copied temporary structures.

## Comments And Diagnostics

Comments near declarations can carry useful prose context. Diagnostics should
prefer structured context but may include captured comments as related semantic
notes when available.

Error messages should say:

- what was expected
- what was received
- which head/slot/role/phase was active
- where the value came from

## Tests

Tests are standalone LuaJIT scripts. Name them by boundary:

```text
tests/frontend/test_*.lua
tests/code_ir/test_*.lua
tests/runtime/test_*.lua
tests/llpvm/test_*.lua
tests/schema/test_*.lua
```

Prefer focused tests that pin one semantic boundary. Broaden tests when a change
touches a shared contract or backend materializer.
