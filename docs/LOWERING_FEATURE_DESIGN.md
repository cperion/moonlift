# Moonlift Lowering Feature Design

This document fixes the contract for language features that must not be treated
as ad-hoc `CmdTrap` fallbacks. A lowerer may either implement a feature exactly
as described here or reject it before native code emission with a compile-time
error. It must not emit a trap as an implementation placeholder.

## 1. Closure values and closure calls

### Value representation

A closure value is a 16-byte aggregate descriptor:

```c
struct MoonliftClosure {
    void *fn;   // native code pointer
    void *ctx;  // environment pointer, null for capture-free closures
};
```

`closure(P...) -> R` is distinct from `func(P...) -> R`:

- `func(P...) -> R` is a scalar code pointer with ABI `(P...) -> R`.
- `closure(P...) -> R` is a descriptor with call ABI `(ctx: ptr(u8), P...) -> R`.

### Capture model

Closure literals must be closure-converted before backend lowering. Two
rewrites are valid:

1. **Immediately-called closure literals** are lambda-lifted. The converter
   collects referenced outer bindings, appends them as explicit helper
   parameters, emits a private helper function, and appends the captured values
   to the rewritten call.
2. **Escaping closure values** use the descriptor representation. The converter
   collects referenced outer bindings, materializes an environment object,
   emits a private helper taking hidden `ctx` first, rewrites captured references
   as loads from `ctx`, and produces `{ fn = helper, ctx = env }`.

Capture-free escaping closures use `ctx = null`, but still use the closure ABI
for uniform call lowering.

### Lowering contract

`Sem.CallClosure(closure, fn_ty)` lowers by:

1. Lower closure value to descriptor address or value.
2. Load `fn` and `ctx` from offsets 0 and pointer-size.
3. Create/use a call signature with hidden `ptr` context first.
4. Emit indirect call with args `{ctx, user_args...}`.

`ExprClosure(params, result, body)` is source/metaprogramming IR. The
`closure_convert` phase is responsible for making closure bodies explicit before
`tree_to_back`. Backend lowering only accepts converted helper functions and
resolved call sites; it rejects raw closure literals.

## 2. Open slots and expression fragments

`ExprSlotValue`, `PlaceSlotValue`, and `ExprUseExprFrag` are open/metaprogramming
IR. They are not backend IR.

Required invariant before lowering:

```text
open_expand + open_validate must eliminate every open slot and fragment use.
```

If one reaches `tree_to_back`, the compilation pipeline is malformed. The
lowerer must reject it with a compile-time error. It must not lower it and must
not emit `CmdTrap`.

## 3. Advanced view forms

The backend ABI for a view is still the existing descriptor:

```c
struct MoonliftView {
    T *data;
    index len;
    index stride; // in elements, not bytes
};
```

All advanced view lowering must preserve that descriptor form.

### Restrided view

Implemented as descriptor rewrite:

```text
base = lower_view(base)
stride = lower_expr(new_stride)
result = { data = base.data, len = base.len, stride = stride }
```

### Window view

Already implemented as data pointer adjustment:

```text
data' = base.data + start * base.stride * sizeof(T)
len' = len
stride' = base.stride
```

### Row-base view

Design contract:

```text
data' = base.data + row_offset * base.stride * sizeof(T)
len' = base.len
stride' = base.stride
```

This is a named convenience for row starts in row-major data. It requires
`row_offset` to be index-like and `base` to have a known element size.

### Interleaved view from raw data

Design contract:

```text
data' = data + lane * sizeof(T)
len' = len
stride' = stride
```

`stride` is the element distance between successive logical elements of the same
lane. Example: RGB data with R lane is `lane=0, stride=3`.

### Interleaved view from a base view

Design contract:

```text
data' = base.data + lane * base.stride * sizeof(T)
len' = base.len
stride' = base.stride * stride
```

This preserves composition with previous windows/restrides.

## 4. Dot and slot place nodes

`ExprDot` / `PlaceDot` are pre-layout nodes. Semantic layout resolution must
rewrite them to `ExprField` / `PlaceField` or another resolved meaning before
lowering. Reaching `tree_to_back` is a pipeline error.

`PlaceSlotValue` is open IR and follows the slot invariant above.

## 5. Floating fused multiply-add

The source/core intrinsic `IntrinsicFma(a, b, c)` lowers to `MoonBack.CmdFma`.
The Rust Cranelift backend emits Cranelift's `fma` instruction builder for this
command, preserving fused multiply-add semantics through Back IR and MLBT.

## 6. Non-negotiable lowering rule

No backend path may use `CmdTrap` to mean “not implemented”. `CmdTrap` is only a
source-level trap operation once such an operation has an explicit surface
contract. Until then, hosted and native pipelines must reject any emitted
`CmdTrap` before codegen.
