# Lalin Conventions

These conventions keep the repository grepable and keep the extensible language
auditable.

## Names

Use `Lalin` for the project and native compiled dialect.

Use `lalin` for package names, module names, file stems, CLI names, and local
variables that hold the public module.

## Two authoring surfaces

### Primary (hand-written code)

Use `.lln` value chunks for hand-written Lalin source. A `.lln` file is a Lua
chunk with Lalin parsed syntax active by default. It returns ordinary Lua values;
Lua `require` and returned tables are the module system.

```lln
-- primary.lln
local add = fn add(a: i32, b: i32): i32
  return a + b
end

return {
  add = add,
}
```

### Builder API (macros, generators, tooling)

Use the Lua/LLBL DSL when constructing declarations programmatically:

```lua
lln.fn. add { a [lln.i32], b [lln.i32] } [lln.i32] {
  lln.ret (a + b),
}
```

Use `lln` as the short authoring namespace inside the builder API.

Use exact subsystem prefixes:

```text
llbl_      LLBL substrate concepts
llpvm_    LLPVM concepts
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
lln.fn. add { a [lln.i32], b [lln.i32] } [lln.i32] {
  lln.ret (a + b),
}
```

Spacing:

```lua
i :lt (n)
value :eq (target)
as [lln.i32] (x)
```

Keep the space after the receiver and before the call parentheses. The method
comparison form is the readable replacement for unavailable Lua operator
overloading.

## Fragments

Reusable DSL pieces should return role-tagged fragments:

```lua
local function buffer_params()
  return lln.product {
    p [lln.ptr [lln.u8]],
    n [lln.index],
  }
end
```

Avoid returning raw arrays from public metaprogramming helpers.

## Regions

Use regions for control machines. Prefer `emit` for local composition. Use
region `call` when the region needs a frame for recursion, profiling, debugging,
or instrumentation. Functions are the sealed product-return ABI substrate.

`region.` is LLBL-owned. Lalin consumes it; Lalin does not own the generic region
concept.

Do not introduce semantic APIs named `stream`. Pull-shaped behavior is a region
protocol lowered through GPS.

## ASDL And Schemas

ASDL/schema values are semantic products. Do not hide meaning in strings,
callbacks, or side tables.

If lowering needs a fact, represent it in schema first.

## Backends

The target fast backend architecture is native residual materialization. Use
saturated stencil instances first, copy-patch to expand binary patch templates
for selected instances, and TCC-compiled C residuals for non-stencil native
code. See `docs/RESIDUAL_NATIVE_ARCHITECTURE.md`.

Backend decisions must be ASDL values. Exact stencil selection, patch-template
selection, patch coordinates, residual C calls to stencils, and
typed rejection reasons are not option bags, string tags, raw hole tables, or
side maps. The leaf that owns the semantic descriptor also owns whether its
fields are fixed in the template family, runtime ABI parameters, or typed patch
coordinates.

The current implementation still contains `residual_mc` bank stencils, optional
TCC residual wrappers, and the explicit `residual_bc` bytecode path. Treat the
LuaJIT trace/block path as an implementation/debug path, not the target
semantic fallback.

Keep the C/AOT path separate in wording and code. `emit_c_artifact` emits the
whole selected program as C so the user can compile it with GCC; it should fuse
selected stencil-shaped work at C level rather than describing itself as a
LuaJIT residual materializer.

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
