# Moonlift Closed-Language Semantic Decisions

Status: **frozen semantic target** for the current rebooted **closed** Moonlift language.

This document exists to stop architectural drift.
It records the semantic choices that have now been settled for the current closed compiler path, even where implementation still lags behind the target.

Primary closed compiler path:

```text
Surface -> Elab -> Sem -> Back -> Artifact
```

This document is about that path only.
It does **not** define the future `Meta` layer or deferred hosted integration.

Companion docs:

- `moonlift/CONTRIBUTING.md`
- `moonlift/REBOOT_SOURCE_SPEC.md`
- `moonlift/TYPED_LOOP_SIGNATURE_PROPOSAL.md`
- `moonlift/CURRENT_IMPLEMENTATION_STATUS.md`
- `moonlift/COMPLETE_LANGUAGE_CHECKLIST.md`

---

# 1. How to use this document

Use this file when a contribution would otherwise reopen a semantic question such as:

- is this a value or a stored cell?
- does this loop produce one result or many?
- is `select` just syntax sugar for `if`?
- are function values really first-class?
- are slices/views real runtime values or just helper lowering notions?
- does the language have multi-result returns?

If this file and the implementation disagree:

- the implementation/status/checklist should be updated explicitly
- do **not** silently drift by treating old uncertainty as permission to improvise

Short rule:

> implement against these decisions unless the user explicitly asks to reopen one.

---

# 2. Single-result language, no anonymous product values

The closed language is a **single-result** language.

That means:

- expressions produce exactly one value
- loop expressions produce exactly one value
- functions return exactly one value
- calls receive exactly one result value
- the language does **not** use anonymous tuple/product values
- the language does **not** have multi-result returns

If multiple logical results are needed, they must be packaged in an explicit named aggregate value.

Canonical pattern:

```text
end -> Stats { sum = sum, count = count }
```

not:

```text
end -> (sum, count)
```

This is a deliberate simplification for:

- ASDL clarity
- simpler `Sem` and `Back` result shapes
- easier Cranelift-facing lowering
- avoiding tuple/multi-result pressure infecting the entire language

---

# 3. Loop semantics

Moonlift loops are explicit state-transition forms grounded in Cranelift's block-param / jump-arg CFG model.
The loop body is the only user-authored section; the header declares state and the recurrence is explicit via `next`.

## 3.1 Carries live after the loop

Loop carries represent the evolving loop state.
After the loop terminates, carry values **survive into the surrounding scope** — they are the loop's natural "output."

There is no separate `end -> result` projection and no `break value`.

- Carries live after the loop as ordinary local bindings
- A `break` preserves the current carry values at the point of exit
- The destination Cranelift block receives all carries as block params

## 3.2 `next` is the recurrence statement

`next` is a statement inside the loop body that explicitly updates carries for the next iteration.
It is required on every path through the body.

```text
next carry1 = expr1, carry2 = expr2
```

This lowers directly to Cranelift jump arguments.

## 3.3 Two loop families

### `for ... in ...` — domain-driven iteration

```moonlift
for i in 0..n do                        -- index-only, no carries
    xs[i] = f(i)
end

for i in 0..n with acc: i32 = 0 do      -- carries survive after loop
    next acc = acc + xs[i]
end
-- acc is alive here
```

The `for` keyword signals an induction variable to Cranelift's loop optimizer.
Domains include ranges (`0..n`, `start..stop`), views, slices, and `zip(xs, ys)`.

### `while ... with ...` — condition-driven iteration

```moonlift
while i < n with i: i32 = 0, acc: i32 = 0 do
    next i = i + 1, acc = acc + xs[i]
end
-- i = n, acc = sum
```

## 3.4 `break`

`break` exits the loop preserving the current carry values.
Bare `break` has no associated value — carries speak for themselves.

## 3.5 Cranelift lowering

All loop forms lower to the same Cranelift three-block shape:

```text
block_header(carry0, carry1):    ; block params = loop state
    cond = check condition        ; or domain exhaustion check
    brnz cond, body(...)          ; continue
    jump exit(carry0, carry1)     ; exit — carries flow naturally

block_body(carry0, carry1):
    ... body + next updates ...
    jump header(next0, next1)     ; recur with next state

block_exit(carry0, carry1):
    ... carries live after loop ...
```

There is no separate "loop output variable" — block params flow to the exit block.
This matches Cranelift's actual dataflow, not an invented language concept.

## 3.6 Shared body-local values are one value

If a loop body computes a local value and uses it in multiple places in the same iteration,
that is semantically one SSA value. Cranelift preserves sharing naturally.

---

# 4. Value, place, and storage model

## 4.1 Source-level binding meaning

The closed language uses these source-level meanings:

- `let` = immutable value binding
- `var` = mutable cell binding
- params = value bindings
- loop carries = value bindings
- loop indices = value bindings

So storage is **not** a general source-level property.
The main authored storage-bearing construct is `var`.

## 4.2 Storage is decided later and explicitly

For immutable locals/params/carries/indices:

- they are values first
- they become stored/addressable only when semantics or ABI/materialization require it

That classification belongs in explicit machine-facing `Sem` answers, not in early/source-facing binders.

## 4.3 Addressability

Addressability flows through explicit place forms.
The language should not treat arbitrary expressions as implicitly addressable.

Address-of applies to real places rooted in explicit place categories such as:

- immutable locals
- mutable locals
- params
- loop carries
- loop indices
- statics
- projections/dereferences/indexes rooted in those addressable bases

Address-of does **not** apply to:

- pure compile-time `const` values
- arbitrary temporary rvalues
- ad hoc computed expressions that are not real places

## 4.4 Required `Sem` truth

Because lowering materially differs, `Sem` should distinguish binding/storage classes when needed, rather than hiding the difference in helper logic.

Important intended distinctions include:

- pure immutable local value
- stored immutable local
- mutable local cell
- pure value param
- stored/address-taken param
- pure value loop carry / index
- stored/address-taken loop carry / index

---

# 5. Conditional and dispatch forms

## 5.1 `if`

`if` is the ordinary control-flow conditional.
It has lazy branch semantics:

- only the taken branch is evaluated
- it may lower through CFG/control structure

## 5.2 `select`

`select(cond, a, b)` is a distinct dataflow choose form.
It is **not** merely a generic `if` with a codegen hint attached.

It should remain explicit in the semantic layers as the choose-shaped operation.

So the intended split is:

- `if` = control-flow conditional
- `select` = explicit choose/dataflow conditional

## 5.3 `switch`

`switch` is a first-class semantic dispatch form and should be preserved as such through `Sem`.
It should not be collapsed early into compare chains unless that is the deliberate lowering step.

Frozen closed-language switch rules:

- no fallthrough
- stmt-switch and expr-switch remain distinct
- expr-switch arms remain `stmt* + result expr`
- intended key kinds are:
  - `bool`
  - integral scalar values
  - `index`
- non-scalar switch keys are **not** part of the closed language target
- float switch keys are **not** part of the closed language target

---

# 6. Value categories

## 6.1 Structs and arrays

Named structs and arrays are first-class language values.
If multiple logical values must move together, use an explicit struct.

## 6.2 Slices

Slices are first-class descriptor values.
Their canonical runtime meaning is:

```text
data + len
```

That is the intended language/runtime model, even if some implementation paths still lag.

## 6.3 Views

Views are also first-class descriptor values.
Their canonical runtime meaning is:

```text
data + len + stride
```

Richer semantic view forms such as:

- contiguous
- strided
- windowed
- interleaved

may normalize into that canonical descriptor-oriented runtime story.

So views are not merely ad hoc lowering helpers.
They are real closed-language value/iteration nouns.

## 6.4 Function values

Function values are first-class immutable callable values.
They are one-word code pointers, storable in structs, arrays, and passed as arguments.

That includes:

- ordinary function items
- extern function items
- direct call targets
- indirect call targets

The closed language does **not** include garbage-collected closures.

## 6.5 Closures

Closures are **surface sugar** over a `struct { fn, ctx }` pair.

A `closure(T) -> R` is structurally distinct from `func(T) -> R` because Cranelift requires
two words (code pointer + context pointer) for a closure but one word for a plain function.

```moonlift
let f: closure(i32) -> i32 = fn(x) x * factor
-- desugars to:
-- type _ctx = struct { factor: i32 }
-- func _fn(ctx: *_ctx, x: i32) -> i32 = return x * ctx.factor
-- let f = closure(_ctx { factor = factor }, _fn)
```

Calling a closure `f(x)` desugars to `f.fn(f.ctx, x)`.
Free variables in the closure body become fields of the generated context struct.
The desugaring happens at `Surface -> Elab`.

## 6.6 Enum and union types

### Enums

Enums are named integer constants — pure surface sugar that desugars at `Surface -> Elab`:

```moonlift
type Color = enum { red, green, blue }
-- desugars: const red: i32 = 0; const green: i32 = 1; const blue: i32 = 2
```

### Tagged unions

Tagged unions desugar to a discriminant + payload struct:

```moonlift
type Result = ok(i32) | err(i32)
-- desugars: type Result = struct { tag: i32, _0: i32 }
--          const Result_tag_ok: i32 = 0; const Result_tag_err: i32 = 1
```

Pattern matching on tagged unions desugars to `switch` on the tag field.

### Untagged unions

Untagged unions desugar to a struct with overlapping field offsets:

```moonlift
type U = union { x: i32, y: f32 }
-- desugars: type U = struct { x: i32, y: f32 }  with x at offset 0, y at offset 0
```

All three forms are surface-only — Cranelift sees ordinary structs and integer constants.

## 6.7 View construction

Views are `(data, len, stride)` descriptor values. The following construction primitives produce them:

```moonlift
view(xs)                  -- from array/slice, stride = elem_size
view(xs, start, len)      -- window into array/slice
view_from_ptr(ptr, len)   -- from raw pointer, stride = elem_size
view_from_ptr(ptr, len, stride)  -- explicit stride
view_window(v, start, len)       -- sub-range of an existing view
view_strided(v, stride)          -- change stride of a view
view_interleaved(v, stride, lane) -- interleaved lane extraction
```

All normalize to the three-word descriptor. Cranelift sees scalar values.

---

# 7. ABI target

The intended ABI target for the closed language is:

- exactly one result
- no multi-result returns

## 7.1 By-value categories

These travel directly by value in the current backend ABI:

- scalar ints/floats/bool/index
- pointers
- function values (one word)

Descriptor-shaped values are ordinary materializable values in the language:

- closure descriptors (`fn + ctx`)
- slice descriptors (`data + len`)
- view descriptors (`data + len + stride`)

At ABI boundaries they currently lower through the same explicit pointer/materialization convention as other non-scalar values. That keeps the Back signature model single-result and avoids anonymous multi-result descriptor ABIs.

## 7.2 Materialized categories

These lower through hidden-pointer/materialization conventions rather than anonymous tuple-like or multi-result ABIs:

- closure descriptors
- slice descriptors
- view descriptors
- named structs
- arrays
- other aggregate values in the same family

That means the ABI model is deliberately friendly to a Cranelift-facing lowering path:

- one scalar/pointer result when the result is scalar-like
- hidden result pointer (`sret`) for non-scalar results
- explicit materialization/copy for descriptor and aggregate values

## 7.3 Back / Cranelift-facing command-layer decisions

The `Back` layer remains a small explicit machine-facing command language.
It should mirror meaningful Cranelift/module primitives where that preserves structure honestly.
It should **not** become a hidden second compiler IR.

### `BackCmd` sufficiency

The current `BackCmd` set is **not** sufficient for the finished closed language.
The missing pressure is not generic scalar arithmetic/control-flow; it is mainly:

- aggregate copy/fill/materialization support
- full descriptor/aggregate ABI support
- remaining non-scalar value movement

So future completion should add missing machine-facing nouns explicitly instead of encoding them indirectly through helper conventions.

### Copy/fill commands

Explicit bulk-memory/data-movement commands should exist in `Back`.

Concretely, the intended direction is to add explicit command nouns for operations in the family of:

- memcpy / non-overlapping aggregate copy
- memset / zero-or-byte fill

This matches Cranelift's own explicit libcall vocabulary (`Memcpy`, `Memset`, `Memmove`, `Memcmp`) and avoids forcing `Sem -> Back` to rediscover bulk copy/fill as scalar loops or long store sequences.

### Scalar choose

When the language means a pure scalar choose, the `Back` layer should preserve that as explicit select-shaped structure.

So the intended split remains:

- `if` -> ordinary CFG conditional
- `select` -> explicit choose/dataflow conditional
- pure scalar choose at `Back` -> `BackCmdSelect`, not mandatory early collapse into branch CFG

### Cast/conversion boundary

Direct `Back` support is intended for scalar conversions that map naturally to Cranelift scalar ops.
That includes the current family of commands such as:

- bitcast
- integer reduce / sign-extend / zero-extend
- float promote / demote
- int<->float conversions

Aggregate/descriptor/materialization conversions do **not** belong as generic `Back` casts.
Those should be resolved earlier into explicit address/materialization/copy plans.

### Slice/view runtime primitives

The closed language keeps slices/views as first-class semantic descriptor values.
But that does **not** imply a separate family of generic slice/view runtime primitives in `Back`.

The intended `Back` story is:

- descriptor fields (`data`, `len`, `stride`) lower to ordinary scalar values
- indexing/windowing/zip structure is resolved in `Sem`
- `Back` only needs explicit extra nouns where there is a real machine/runtime primitive worth naming (such as copy/fill), not a second slice/view mini-IR

So dedicated generic slice/view runtime primitives are **not** part of the intended `BackCmd` design.

### Layout resolution boundary

Unresolved field references must not survive past layout resolution.
After the explicit `Sem` layout-resolution boundary, downstream lowering should only see resolved field-by-offset forms.

### Artifact vs future session model

If a richer persistent session/module model is added later, it should **extend** the current artifact model, not replace it.

The direct artifact path stays a first-class honest path:

- compile `BackProgram`
- keep artifact alive
- use pointers while artifact lives

Any future session/cache layer should be an additional host-side layer over that reality, not a second ownership story.

---

# 8. Global/item semantics

## 8.1 `const`

`const` means a pure compile-time value.
It is not an addressable runtime storage location.

## 8.2 `static`

`static` means addressable storage.
It is the addressable global-data form.

## 8.3 Mutable globals

If mutable global storage exists, it belongs to the `static`/addressable-data story, not the pure `const` story.

## 8.4 Externs

Extern function items are semantically function values in the same callable family, even if current implementation still supports them incompletely outside call-target position.

## 8.5 Visibility

```moonlift
export func public_fn(...) -> R ... end   -- visible to importing modules
func private_fn(...) -> R ... end         -- module-local only
```

Plain `func` produces a module-local function. `export func` produces an exported function reachable via `import`.

## 8.6 Floating-point remainder

Floating-point remainder (`%` on float types) is not part of the language.
Integer remainder is supported. The `BackCmdFrem` command is removed from the backend.

## 8.7 Const evaluation

### Cross-module const references

A const in module A may reference a const in module B. The const evaluator has access to the full const environment across all modules being compiled together.

### Const intrinsics

Intrinsics with pure scalar semantics (`abs`, `sqrt`, `clz`, `ctz`, `floor`, `ceil`, `round`, `trunc_float`) are evaluated at compile time when all arguments are const. The evaluator dispatches through `pvm.phase` on the intrinsic kind.

## 8.8 Type-directed integer literal elaboration

Integer literals are elaborated to their expected type at `Surface -> Elab` when context provides one:
- `let x: u32 = 42` → `42u32`
- `switch` arm keys acquire the switch-value type
- function params acquire their declared type
- array counts acquire index type

No new ASDL. The elaboration is a lowering rule in `Surface -> Elab`.

---

# 9. What these decisions imply for implementation

These decisions freeze the target.
They do **not** claim every implementation piece is complete today.

In particular, the implementation still needs to finish work such as:

- adding const intrinsic evaluation via pvm dispatch if const intrinsics become part of the language
- completing remaining non-scalar direct-load and expression-value forms where needed
- documenting the public C ABI spelling for hidden result pointers and non-scalar parameters
- aligning Rust/FFI user-facing helpers with the frozen single-result descriptor/aggregate strategy

Use `moonlift/CURRENT_IMPLEMENTATION_STATUS.md` for what exists today.
Use `moonlift/COMPLETE_LANGUAGE_CHECKLIST.md` for the remaining implementation work.

---

# 10. Short summary

The closed Moonlift language is now frozen around these core choices:

- one-result language, no anonymous tuple/product values
- explicit structs for multi-field results
- `for ... in ...` and `while ... with ...` loop forms; carries survive after loop; `next` inline in body; no separate `end ->` projection
- `break` preserves current carry values; no `break value`
- value-first bindings with later explicit storage classification
- `if` distinct from `select`; `switch` preserved as switch
- slices (`data+len`) and views (`data+len+stride`) as real descriptor values
- function values as storable one-word code pointers
- closures as surface sugar over `struct { fn, ctx }`, distinct type from plain functions
- enums, tagged unions, and untagged unions as surface sugar desugaring to structs and constants
- view construction through six explicit primitives
- `export func` for visibility; plain `func` is module-local
- no floating-point remainder
- cross-module const references and const intrinsic evaluation
- type-directed integer literal elaboration at `Surface -> Elab`
- one-result ABI with aggregates lowered through materialization/hidden-pointer paths
- explicit select/copy/fill-friendly `Back` design over a thin Cranelift-facing command layer

That is the current closed-language target.