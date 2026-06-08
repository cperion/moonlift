# Complete Moonlift C Backend Design

Status: design contract. This document is intentionally broader than the first C backend
scaffold. It defines what a **complete** C backend means before further implementation.

The C backend is a PVM side projection:

```text
source / .mlua
  -> parse
  -> open_expand
  -> closure_convert
  -> tree_typecheck
  -> sem_layout_resolve(target = c_target)
  -> tree_to_c
  -> c_validate
  -> c_emit
  -> .c
```

It is not a WASM backend. It emits C. Support for wasm-capable toolchains, embedded
platforms, and cross compilation is a consequence of C emission.

## 1. Non-negotiable completeness rule

A complete C backend must classify every construct in the resolved typed MoonTree schema:

- supported and emitted correctly;
- unreachable after earlier phases, with a validator/assertion if it appears;
- intentionally rejected with a real diagnostic because Moonlift itself does not support it
  for native code generation.

No construct may be silently ignored, partially lowered, or fall through to generic
`unsupported` after implementation is declared complete.

## 2. Projection source

The source of truth is the typed/resolved MoonTree program after:

1. open expansion;
2. closure conversion;
3. typecheck;
4. target-aware layout resolution.

The C backend does not consume `MoonBack.Cmd[]`. `MoonBack` is the Cranelift projection.
The C backend preserves program-layer facts that would otherwise be erased:

- typed pointers (`ptr(T)`), arrays, views, closures;
- field refs and layout facts;
- source-level function/extern/call structure;
- statement/control-region structure;
- aggregate and view construction intent;
- addressable places.

## 3. Target and layout model

### 3.1 Target selection comes before layout

The C target must be known before `sem_layout_resolve`.

```lua
CBackendTarget {
  dialect,      -- C99/C11/GNU/Clang subset
  platform,     -- hosted native/freestanding/wasm-capable/embedded
  pointer_bits,
  index_bits,
  endian,
  hosted,
}
```

Current Moonlift layout code assumes 64-bit pointer/index in several places. A complete C
backend must make pointer/index size target-aware before claiming non-native64 portability.
For native64 C, pointer/index layout may match the current Cranelift path.

### 3.2 One layout authority

All generated C structs, view descriptors, closure descriptors, array sizes, stack slots,
and data initializers must agree with `Sem.LayoutEnv` / `type_size_align` for the selected
C target.

Generated C should emit static assertions when the dialect supports them:

```c
_Static_assert(sizeof(struct ml_X) == EXPECTED, "layout size mismatch");
_Static_assert(_Alignof(struct ml_X) == EXPECTED_ALIGN, "layout align mismatch");
```

When static assertions are not available, syntax emission must still encode explicit layout
choices and tests must compile/run layout probes.

## 4. CBackend ASDL role

`MoonC.CBackend*` is the backend's restricted C dialect. It is not parsed-C `MoonCAst`.
It should be extended as needed, but the final shape must preserve these layers:

```text
MoonTree resolved program
  -> semantic C projection (`CBackendUnit`)
  -> validated restricted C
  -> deterministic C text
```

The printer must stay dumb. Semantics belong in `tree_to_c`, `type_to_c`, helpers, and
validation.

## 5. Required CBackend ASDL extensions beyond the scaffold

The first scaffold is not enough for completeness. The complete design needs these semantic
nodes or equivalent representation.

### 5.1 Places / addressable storage

Add an explicit place/address layer:

```lua
CBackendPlaceLocal(local)
CBackendPlaceGlobal(global)
CBackendPlaceDeref(addr, pointee_type)
CBackendPlaceField(base, field, offset, field_type)
CBackendPlaceIndex(base, index, elem_size, elem_type)
CBackendPlaceBytes(addr, value_type)
```

`place_to_c` returns either:

- direct C lvalue place, safe for typed locals/structs/arrays; or
- byte-addressed place requiring load/store helper.

This is required for `StmtSet`, `ExprAddrOf`, `ExprDeref`, `ExprField`, `ExprIndex`,
aggregate field construction, views, and address-taken locals.

### 5.2 Storage residence

Each binding/local needs residence:

```lua
CResidenceValue      -- ordinary scalar C local
CResidenceAddressed  -- materialized C storage object because address is taken
CResidenceAggregate  -- struct/array storage
CResidenceDescriptor -- view/closure/slice descriptor
```

Address-taken scalar locals must not remain purely SSA-like values. They need real C storage.

### 5.3 Aggregate initializers

Add or define lowering for:

```lua
CBackendAggregateInit(dst_place, fields/elements)
CBackendArrayInit(dst_place, elements)
CBackendZeroInit(dst_place, size)
```

These can lower further to stores/memcpy before emission, but the projection must not lose
aggregate construction semantics.

### 5.4 Typed data initializers

Global/static data must support:

- zero ranges;
- exact byte ranges;
- exact scalar literals, without Lua-number precision loss;
- relocations to data, function, and extern symbols;
- aggregate/array layout-derived initializers.

## 6. Type coverage matrix

| MoonType | Complete C backend rule |
|---|---|
| `TScalar` | fixed-width C scalar typedef or standard integer/float type; bool is `uint8_t` invariant 0/1 |
| `TPtr(T)` | data pointer; typed for C lvalues when safe, byte-addressed for raw memory helpers |
| `TArray(n,T)` | fixed-size C array/storage type; ABI generally by address |
| `TSlice(T)` | descriptor type if source slices are supported; otherwise intentionally rejected before backend |
| `TView(T)` | descriptor `{data,len,stride}` with target-sized index; view operations lower from descriptor fields |
| `TFunc(params,result)` | typed code pointer, never `void*` |
| `TClosure(params,result)` | descriptor `{fn,ctx}`; calls pass ctx according to closure-conversion convention |
| `TNamed` | layout-backed struct/union/opaque C declaration from `Sem.LayoutEnv` |
| `TCType` | imported C type id; emitted as existing C type spelling/header contract |
| `TCFuncPtr` | imported C function pointer signature; exact C call type |
| `TSlot` | unreachable after open expansion; hard backend error if present |

## 7. Item coverage matrix

| MoonTree item | Complete C backend rule |
|---|---|
| `ItemFunc` | emit C function/prototype/body if concrete function; contracts/declarations classified below |
| `ItemExtern` | emit extern declaration; preserve symbol and signature exactly |
| `ItemConst` | lower if compile-time constant is used for data/expression; otherwise no emitted storage |
| `ItemStatic` | emit global/static data with exact layout/init |
| `ItemImport` | already resolved before backend; hard error if unresolved |
| `ItemType` | emit required struct/union/typedef/opaque declarations from layout env |
| `ItemUseTypeDeclSlot` | unreachable after open expansion; hard error |
| `ItemUseItemsSlot` | unreachable after open expansion; hard error |
| `ItemUseModule` | recursively project nested module items |
| `ItemUseModuleSlot` | unreachable after open expansion; hard error |
| `ItemData` | emit data object with exact initializer bytes/relocs |

Function variants:

| Func variant | Rule |
|---|---|
| `FuncLocal` | emit static/local C function unless referenced/exported needs external linkage |
| `FuncExport` | emit exported C symbol according to Moonlift ABI |
| `FuncLocalContract` | no body; if still present at emission, diagnostic unless lowered to declaration intentionally |
| `FuncExportContract` | no body; declaration/export contract only if language permits; otherwise diagnostic |
| `FuncDecl` | declaration only; no body |
| `FuncOpen` | unreachable after open expansion; hard error |

## 8. Expression coverage matrix

| Expr | Complete C backend rule |
|---|---|
| `ExprLit` | exact literal; integer literals emitted with width/suffix or helper parser for large values |
| `ExprRef` | local/global/function/extern/codeptr/data refs according to binding class |
| `ExprDot` | must be resolved to field refs by layout; hard error if raw dot reaches backend |
| `ExprUnary` | helper/direct op with UB-free semantics (`neg`, `not`, bitnot) |
| `ExprBinary` | helper/direct op by type/op; signed overflow, div/rem, shifts never UB |
| `ExprCompare` | emits `uint8_t` 0/1; signed/unsigned/float comparison selected by typed operands |
| `ExprLogic` | short-circuit CFG, not eager C `&&` unless proven safe and normalized to bool8 |
| `ExprCast` | surface cast must already be resolved; hard error if unresolved |
| `ExprMachineCast` | exact cast helpers for dangerous cases, especially float-to-int and pointer/codeptr casts |
| `ExprIntrinsic` | helper per intrinsic; no builtin UB for clz/ctz zero, bswap widths, fma, math funcs |
| `ExprAddrOf` | lower place to address; materialize storage if needed |
| `ExprDeref` | produce place/load through pointer type and memory model |
| `ExprCall` | direct/extern/indirect/closure calls with exact ABI/signature |
| `ExprLen` | descriptor/array length extraction |
| `ExprField` | layout field load or address depending context |
| `ExprIndex` | array/pointer/view indexing through place/address rules |
| `ExprAgg` | aggregate storage construction; result residence is aggregate/addressed value |
| `ExprArray` | array storage construction with exact element layout |
| `ExprIf` | CFG with result temp and join label; not C ternary unless trivial |
| `ExprSelect` | shallow select; result normalized and no side effects in arms |
| `ExprSwitch` | CFG with result temp and join label; default required |
| `ExprControl` | inline region CFG; expression result via yield local and join label |
| `ExprBlock` | statement sequence plus final expression; creates local scope/storage |
| `ExprClosure` | should be eliminated by closure conversion; hard error if present |
| `ExprView` | descriptor construction for all view forms |
| `ExprLoad` | explicit memory load helper/direct typed load per place/address safety |
| `ExprAtomicLoad` | C11 atomics or target-specific helper; diagnostic if target lacks atomics |
| `ExprAtomicRmw` | C11 atomic fetch ops/CAS loop as needed; diagnostic if unsupported |
| `ExprAtomicCas` | C11 compare_exchange helper; exact result semantics |
| `ExprSlotValue` | unreachable after open expansion; hard error |
| `ExprUseExprFrag` | unreachable after expansion/inlining; hard error unless fragment inlining is explicitly supported here |
| `ExprCtor` | tagged union constructor if language frontend supports it; otherwise intentional diagnostic matching native path |
| `ExprNull` | typed null data pointer/code pointer where legal; no data/code confusion |
| `ExprSizeOf` | should be resolved to literal by layout; if present, emit target layout constant |
| `ExprAlignOf` | should be resolved to literal by layout; if present, emit target layout constant |
| `ExprIsNull` | compare pointer/code pointer to null, normalized bool8 |

## 9. Statement coverage matrix

| Stmt | Complete C backend rule |
|---|---|
| `StmtLet` | bind immutable value/storage; materialize if address is taken or aggregate |
| `StmtVar` | bind mutable storage; scalar direct local unless address taken |
| `StmtSet` | lower place assignment/store; supports locals, deref, field, index, view element |
| `StmtAtomicStore` | C11 atomic store/helper; target diagnostic if unsupported |
| `StmtAtomicFence` | C11 `atomic_thread_fence`/helper; target diagnostic if unsupported |
| `StmtExpr` | emit expression side effects; discard result correctly |
| `StmtAssert` | lower to conditional trap/helper preserving condition evaluation |
| `StmtIf` | CFG split with then/else/join; supports non-terminal statement position |
| `StmtSwitch` | CFG split with cases/default/join; default always emitted |
| `StmtJump` | region/block jump with parallel arg assignment |
| `StmtJumpCont` | continuation jump protocol; lower according to named protocol/control facts |
| `StmtYieldVoid` | region yield to enclosing join/return |
| `StmtYieldValue` | assign yield temp then jump enclosing join/return |
| `StmtReturnVoid` | C return void |
| `StmtReturnValue` | ABI-aware return; hidden out param for view/aggregate if required |
| `StmtControl` | inline statement control region |
| `StmtUseRegionSlot` | unreachable after expansion; hard error |
| `StmtUseRegionFrag` | unreachable after expansion/inlining; hard error unless explicitly supported |
| `StmtTrap` | trap helper/abort/unreachable according to target |

Non-terminal `StmtIf`, `StmtSwitch`, and control constructs require a CFG builder, not a
single-block statement list. The complete backend must be able to split the current block,
create labels, and resume at joins.

## 10. Control-region design

Moonlift control maps to labels/gotos.

Rules:

1. Every CBackend block has one terminator.
2. Block params are represented explicitly in ASDL.
3. Jump args use transfer temps to preserve parallel assignment:

```c
__xfer_loop_i = next_i;
__xfer_loop_acc = next_acc;
goto loop;

loop:
  loop_i = __xfer_loop_i;
  loop_acc = __xfer_loop_acc;
```

4. Expression regions use a result local plus yield/join label.
5. Statement regions jump/return directly or yield to a continuation label.
6. Named continuation protocols must be checked before emission; missing protocol arms are
   diagnostics, not fallthrough.
7. Irreducible regions are allowed if they are representable with labels/goto; no loop
   reconstruction is required.

## 11. ABI design

The C backend must define two related ABIs:

1. **Internal C projection ABI** for functions generated into the same C unit.
2. **External Moonlift C ABI** for exported functions and extern declarations.

To stay aligned with the native path, the external ABI follows `type_func_abi_plan.lua`:

- scalar, raw pointer, index, function pointer: direct;
- view params: flattened descriptor fields or a specified descriptor type, consistently;
- named aggregates and arrays: by pointer/address;
- closure params: descriptor `{fn,ctx}` or flattened according to closure ABI;
- scalar/direct returns: direct;
- view/aggregate returns: hidden out pointer when supported, otherwise same rejection as native path.

If internal C ABI is more convenient, wrappers must be generated at export/import boundaries.
No mismatch is allowed between direct calls, indirect calls, extern calls, and emitted
function pointer typedefs.

## 12. Function pointers and closures

C data pointers and C function pointers are distinct.

Rules:

- `TFunc` and `TCFuncPtr` project to `CBackendCodePtr(sig)`.
- `ptr(T)` projects to `CBackendDataPtr`.
- `ExprAddrOf(function)` produces code pointer, not data pointer.
- indirect calls require exact signature match.
- closure conversion must produce functions with explicit context parameter and descriptors
  containing `{fn, ctx}`.
- calling a closure loads `fn` as code pointer and `ctx` as data pointer, then calls exact
  closure signature.

No generated C may cast arbitrary `void*` to a function pointer except through an explicitly
specified non-portable target profile. Portable C mode rejects such casts.

## 13. Memory and place semantics

### 13.1 Local typed storage

For ordinary scalar locals not address-taken, use C scalar locals.

For mutable/address-taken/aggregate locals, use C storage objects:

```c
int32_t x;
struct ml_S s;
uint8_t raw_slot[N];
```

### 13.2 External/raw memory

Loads/stores through arbitrary pointers default to helper-mediated byte copies:

```c
static inline int32_t ml_load_i32(void const *p) {
  int32_t v;
  memcpy(&v, p, sizeof(v));
  return v;
}
```

This avoids alignment, strict-aliasing, effective-type, and provenance UB.

### 13.3 Typed aggregate fields

Accessing fields of a C struct object generated by this backend may use direct field syntax.
Accessing fields through raw pointer memory must use offset + helper load/store unless the
place is proven to be a valid typed C object.

### 13.4 Pointer arithmetic

Pointer offsets are emitted through byte pointers for data pointers:

```c
(void *)((unsigned char *)base + scaled_offset)
```

Integer overflow in offset calculation must be defined by Moonlift semantics or checked.
The target pointer width controls index arithmetic.

## 14. Helper semantics contract

All dangerous operations are helper-mediated unless the C operation is proven safe.

### 14.1 Integer wrapping add/sub/mul

Signed wrapping uses unsigned arithmetic of equal width:

```c
static inline int32_t ml_i32_add_wrap(int32_t a, int32_t b) {
  return (int32_t)((uint32_t)a + (uint32_t)b);
}
```

Equivalent helpers exist for every integer width/sign.

### 14.2 Division/remainder

Signed division/remainder helpers check:

- divisor zero;
- signed minimum divided/remainder by `-1` where C would overflow/UB.

Unsigned division checks divisor zero.

Trap behavior uses the backend trap helper.

### 14.3 Shifts/rotates

Shift count semantics must match the MoonBack/Cranelift contract. The complete design uses
one explicit mode per operation:

- mask count modulo bit width; or
- trap if out of range.

Generated C never shifts by a count >= width. Signed left shifts are performed on unsigned
storage and cast back.

Rotates are helper functions using masked counts and unsigned storage.

### 14.4 Casts

Dangerous casts use helpers:

- float to signed/unsigned int checks NaN/out-of-range if Moonlift semantics trap;
- int extension/truncation uses explicit fixed-width casts;
- bitcast uses `memcpy` or unions only under a target profile that permits it;
- data pointer/code pointer casts are rejected unless semantically explicit and target-permitted.

### 14.5 Intrinsics

Required helpers:

- popcount;
- clz/ctz with explicit zero behavior;
- bswap by width;
- sqrt/abs/floor/ceil/trunc/round;
- fma;
- trap;
- assume.

Compiler builtins may be used only behind wrappers that preserve defined behavior for edge
cases.

### 14.6 Floats

Strict float mode emits ordinary C floating operations under assumptions documented by the
C target profile. Fast-math/reassoc facts are not used unless explicitly requested.

If exact IEEE behavior is required for a target, the profile must select flags/pragmas and
tests must verify it.

## 15. Views

A `view(T)` is a descriptor:

```c
typedef struct {
  T *data;       /* or void* plus typed helper rules */
  ml_index len;
  ml_index stride;
} ml_view_T;
```

All `ExprView` forms are required:

- `ViewFromExpr`
- `ViewContiguous`
- `ViewStrided`
- `ViewRestrided`
- `ViewWindow`
- `ViewRowBase`
- `ViewInterleaved`
- `ViewInterleavedView`

Indexing a view computes:

```text
addr = data + index * stride_or_elem_size
```

using target index arithmetic and helper-mediated memory access unless a typed place is safe.

## 16. Aggregates, arrays, structs, unions

Named structs/unions are emitted from layout facts, not guessed from syntax.

Rules:

- field offsets/sizes/alignments must match layout env;
- aggregate values are storage values, not scalar rvalues;
- passing aggregates follows ABI plan;
- field access uses typed C fields for backend-owned objects;
- raw-memory aggregate access uses byte offsets and helpers;
- array literals initialize exact element slots;
- array indexing respects element layout and addressability.

Unions/tagged unions/constructors require explicit tag/payload layout. If `ExprCtor` is not
implemented in the frontend/native path, the C backend must produce the same diagnostic,
not invent separate semantics.

### 16.1 Enum and tagged-union runtime representation

Enum sugar and tagged-union sugar are resolved into ordinary layout facts before either
native or C lowering. The representation is shared by both backends; the C backend must not
invent a C-only ABI.

**Tag model.** Every enum/tagged union has an unsigned integer tag field named `__tag` in
semantic layout facts. Tag values are assigned deterministically in source declaration order,
starting at zero, unless future syntax adds explicit discriminants. The initial complete
native64 profile uses `u32` tag storage with 4-byte alignment. A target-aware profile may
select the smallest unsigned storage that holds all variants, but that choice must be present
in `Sem.LayoutEnv` and used by both backends.

**Payload layout.** A zero-payload enum is represented as tag storage only. A tagged union is
represented as `{ __tag, __payload }`, where `__payload` is an aligned byte region large
enough for the largest variant payload. Payload alignment is the maximum payload alignment;
total size and tail padding come from the same layout algorithm used for structs/unions.
Each variant has a `Sem.VariantLayout`-equivalent fact containing variant name, tag value,
payload type/fields, payload offset, payload size, and payload alignment.

**Constructors.** `ExprCtor(T, V, args)` lowers to aggregate storage initialization: zero the
whole object, store the tag value for `V`, then initialize the payload bytes/fields according
to `V`'s payload layout. Constructor argument count and field names are checked in the
frontend/typechecker. The native path emits the same tag store and payload stores; C emits a
compound local/global initializer only when it is layout-equivalent, otherwise explicit stores.

**Variant binds.** A variant bind is valid only in the control scope of a successful variant
arm. For a scalar payload it binds a typed value loaded from the payload offset. For aggregate
payloads it binds an addressable typed place pointing at the payload storage. Multi-field
payload sugar binds one local/place per named field using the variant payload layout. Binds
must not be visible on default arms or after the arm join unless explicitly assigned to an
outer local through normal control flow.

**Variant switches.** A variant switch first evaluates the scrutinee once, reads `__tag`, and
branches by tag. Statement switches lower to tag tests/cases and arm-local bind setup before
executing each arm body. Expression switches allocate a result temporary, execute exactly one
arm, assign the result, and jump to a join label. Default arms are required unless the
frontend proves all declared tag values are covered. Duplicate arms, impossible variant names,
missing required default, and payload-bind shape mismatches are frontend/typecheck
diagnostics, not backend fallthrough.

**ABI.** Tagged unions and enum aggregates follow the named-aggregate ABI plan: by pointer for
parameters where aggregate passing is not supported, direct scalar tag return for zero-payload
enums when the ABI plan says scalar-direct, and hidden out pointer for aggregate returns when
required. Function pointer, extern, native, and C signatures must all use the same ABI plan.
No backend may reinterpret a tagged union as a raw integer unless its layout fact says the type
is a zero-payload enum with scalar-tag ABI.

**Data initialization.** Static/data constructors use the same layout facts: tag scalar bytes
are emitted exactly in target endian order and payload bytes/relocations are emitted at the
payload offset. Uninitialized padding is deterministic zero unless a future target profile
explicitly permits unspecified padding. Large tag values and payload scalars must not pass
through Lua `number`.

**Diagnostics.** Required diagnostics include unknown type/variant, duplicate variant tag,
constructor arity/field mismatch, variant switch on a non-tagged type, duplicate switch arm,
missing non-exhaustive default, impossible variant arm, payload bind requested for no-payload
variant, and aggregate payload bind used where only by-address binding is legal. Native and C
frontend paths must report equivalent diagnostics before backend emission.

## 17. Atomics

Atomics are target-feature-sensitive.

Complete C backend behavior:

- C11-hosted target with atomics: emit `_Atomic`/`atomic_*` helpers.
- freestanding/embedded target: require supplied runtime helpers or reject atomics.
- wasm-capable C target: atomics require toolchain/thread/shared-memory feature flag.

Supported operations:

- `ExprAtomicLoad`
- `StmtAtomicStore`
- `ExprAtomicRmw`
- `ExprAtomicCas`
- `StmtAtomicFence`

Ordering currently has `AtomicSeqCst`; helpers still carry ordering so future orderings do
not require ASDL redesign.

## 18. Data/global emission

Data emission must be exact and deterministic.

- integer literals are preserved as exact strings/bytes until target-width encoding;
- endian controls byte order;
- relocations to data/function/extern are explicit;
- C source may represent binary data as byte arrays plus relocation initializers where C can
  express them;
- if C cannot express a relocation in a byte array portably, emit typed global objects or a
  target-specific initializer form.

No large integer may pass through Lua `number` as part of C backend data emission.

## 19. Validation contract

`c_validate` must check:

- every schema variant has a support/reject classification;
- all references exist;
- names are valid and unique in their C namespace;
- all function signatures match params/results;
- direct/extern/indirect calls match exact signatures;
- no data pointer/code pointer confusion;
- all block transfers match parameter count/types;
- every block terminates exactly once;
- all locals have residence/type and are initialized before use where required;
- place/load/store types match;
- address-taken values have materialized storage;
- helper id matches helper kind;
- helper args/results match helper signature;
- global initializers are in bounds and exact;
- layout assertions can be generated for every emitted type;
- target feature requirements are satisfied for atomics, builtins, alignment, and freestanding mode.

Validation returns typed issues. It must not collapse failures into string-only errors.

## 20. Emission discipline

The emitted C file order:

1. generated banner and target facts;
2. includes or freestanding declarations;
3. core typedefs (`ml_index`, bool8, pointer-size aliases);
4. signature typedefs for code pointers;
5. type declarations and layout assertions;
6. extern declarations;
7. global/data declarations;
8. helper declarations/definitions;
9. function prototypes;
10. function bodies.

Generated functions use labels/gotos. Do not reconstruct `while`/`for` loops.

## 21. Testing contract

A complete backend requires tests in these categories.

### 21.1 Exhaustiveness tests

A schema coverage test enumerates every MoonTree `Expr`, `Stmt`, `Item`, `Func`, `Type`,
`Place`, and view variant and verifies that the C backend has a table entry classified as
supported/unreachable/rejected.

### 21.2 Unit tests

- type projection for every MoonType;
- helper semantics for every op/width/sign edge case;
- place lowering and residence;
- validator issue variants;
- C emitter deterministic sections and syntax.

### 21.3 Source smoke tests

Source programs covering each language feature must pass `moon.emit_c` and C syntax checks.

### 21.4 Semantic equivalence tests

For executable subsets, each test runs both:

```text
Moonlift -> Cranelift/JIT
Moonlift -> C -> cc -> executable/shared object
```

and compares results.

Required equivalence groups:

- scalar arithmetic edge cases;
- div/rem/shift edge cases;
- casts including float/int boundaries;
- bool/select/logical short-circuit;
- block/jump/yield regions;
- if/switch expressions and statements;
- mutable vars and assignment;
- pointers/load/store/address-of/deref;
- structs/unions/arrays/aggregate literals;
- views and view indexing/windowing/striding;
- function pointers and indirect calls;
- closures after closure conversion;
- extern calls;
- data/static globals;
- atomics where target supports them.

### 21.5 Negative tests

For constructs intentionally rejected or unreachable, tests assert exact diagnostics.

## 22. Implementation phasing after this design

Implementation may be phased, but each phase must declare its coverage matrix and diagnostics.
A phase is not called "the C backend is complete" unless every row in this document is
implemented or intentionally rejected in parity with the native path.

Acceptable phase labels:

- `C backend scaffold`
- `C backend scalar/control subset`
- `C backend memory/aggregate subset`
- `C backend complete native64`
- `C backend complete target-aware`

Unacceptable label before full coverage:

- `C backend complete`

## 23. Current scaffold gap summary

The current scaffold is useful but incomplete. Known gaps include:

- no complete construct coverage table enforced by tests;
- `StmtSet` missing;
- direct non-terminal `StmtIf`/`StmtSwitch` not generally lowered;
- many expression variants missing;
- arrays/views/closures/named aggregate type projection incomplete;
- helper semantics still too naive for UB-free C;
- atomics not implemented;
- data/global initializers are basic;
- layout/ABI wrappers incomplete;
- semantic equivalence tests against Cranelift are not yet present.

This document is the scope correction: complete means this whole contract, not the scaffold.

## 24. Completion correction — 2026-06-08

The current implementation is **not** a complete C backend. It is a working C emission path
for a substantial subset. The previous edit-plan completion only meant that a flawed plan was
finished; it did not prove the actual user goal:

> write Moonlift, emit C, compile it with gcc, and run it for the whole supported language.

The coverage matrix must not be used as a completion claim while it contains backend-level
`rejected` entries. For the real complete backend, every row must be one of:

1. `supported` — emitted to C and covered by gcc compile/run tests;
2. `phase_unreachable` — impossible after earlier phases, proven by tests at the phase boundary;
3. `language_rejected` — rejected by Moonlift itself/native parity before backend lowering.

A backend TODO may not be hidden behind `rejected`.

### 24.1 Rows that must stop being backend rejections

These rows require design/implementation, not a final rejection:

- `ExprCtor`
- `SwitchVariantStmtArm`
- `SwitchVariantExprArm`
- `VariantBind`
- `ControlVariantArmFact`
- `TypeDeclEnumSugar`
- `TypeDeclTaggedUnionSugar`

They represent enum/tagged-union constructor and variant-switch semantics. A complete C
backend either implements them in parity with native lowering, or the Moonlift frontend/type
checker rejects the feature before any backend. The backend may not silently be the place
where this language design disappears.

### 24.2 Rows that should be phase-unreachable, not backend-rejected

These rows are valid only as phase-boundary assertions:

- raw `ExprDot` / `PlaceDot` after layout resolution;
- unresolved `ExprCast` / `MoonCore.SurfaceCastOp` after typechecking;
- direct `ExprClosure` after closure conversion;
- open slots/fragments/import forms after open expansion;
- `FuncOpen` / `ExternFuncOpen` after open expansion.

The complete plan must add tests proving they are resolved before `tree_to_c`, or fail with
an upstream diagnostic if a phase is skipped.

### 24.3 Real user-facing completion test

The final acceptance condition is not only Lua unit tests. It is a source corpus that does:

```text
Moonlift source -> moon.emit_c -> gcc/cc -> executable/shared object -> run/compare result
```

for every supported language feature.

## 25. Full-support implementation plan

This is the canonical plan for finishing the backend for the real goal.

1. Correct `lua/moonlift/c_coverage.lua` so `rejected` no longer conflates backend TODO,
   phase-unreachable, and language-level rejection.
2. Add a coverage proof test that fails if any backend-TODO row remains.
3. Add phase-boundary tests proving raw dots, surface casts, closure literals, open slots,
   imports, and open funcs/externs cannot reach `tree_to_c` through the normal pipeline.
4. Design enum/tagged-union representation once: tag layout, payload layout, constructors,
   variant binds, variant switches, ABI, data initialization, and diagnostics.
5. Implement enum/tagged-union typing/layout support needed by both native and C paths.
6. Implement `ExprCtor` and variant switch lowering for `tree_to_back` to preserve native
   parity.
7. Implement `ExprCtor` and variant switch lowering for `tree_to_c` using the same layout
   and control semantics.
8. Decide and implement the dynamic array-length policy: constant-fold before layout, or
   reject in typechecking before backend.
9. Replace smoke-only C equivalence with a gcc compile/run feature corpus covering scalars,
   casts, div/rem/shift edge cases, bool/logic/select, regions, assignments, pointers,
   structs/unions, arrays, views, function pointers, closures after conversion, externs,
   statics/data, atomics where target-supported, and tagged unions.
10. Add a user-facing examples directory with `.mlua -> .c -> gcc -> run` scripts.
11. Only after all of the above pass, update this appendix to claim `C backend complete`.

## 26. Completion status — 2026-06-08

The accepted implementation status is now **C backend complete native64 / hosted C fast path**.
For the supported language covered by the current native64 target model, the user-facing path
is proven:

```text
Moonlift source -> moon.emit_c -> TCC/cc -> runnable executable
```

The default development loop prefers TCC: `MOONLIFT_C_CC`, then `tcc`, then `cc`/`gcc`/`clang`.
Optional `MOONLIFT_C_USE_LIBTCC=1` uses the self-contained LuaJIT FFI libtcc runner when
libtcc is installed; absence is a skip diagnostic and falls back to the subprocess compiler.

Acceptance evidence:

- `MOONLIFT_C_BACKEND_FINAL=1 luajit tests/test_c_backend_coverage_matrix.lua` — no
  backend-TODO coverage rows remain.
- `luajit tests/test_c_backend_phase_boundaries.lua` — phase-unreachable rows are proven at
  the frontend/C boundary.
- `luajit tests/test_c_gcc_feature_corpus.lua` and
  `MOONLIFT_C_CC=cc luajit tests/test_c_gcc_feature_corpus.lua` — supported source features
  compile and run through TCC and cc, including pointers/views, arrays/aggregates, data
  globals, closure descriptors, C11 atomics when target-supported, and tagged unions.
- `luajit tests/test_c_gcc_tagged_union.lua` — ASDL/tagged-union constructor and variant
  switch corpus compiles and runs.
- `luajit tests/test_c_full_semantic_equivalence.lua` — C output is compared against
  Cranelift/JIT results for representative executable corpus groups.
- `luajit examples/c_backend/run_examples.lua` — user-facing examples cover return code,
  arithmetic, pointer/view, struct/array, extern, function pointer, and tagged union.

Legitimate non-`supported` coverage rows are not backend gaps:

- `phase_unreachable` rows are constructs resolved or eliminated before `tree_to_c`
  (raw dot/place-dot, surface casts, direct closure expressions, open slots/fragments/imports,
  and open funcs/externs); proof lives in `tests/test_c_backend_phase_boundaries.lua`.
- `language_rejected` rows are rejected before C lowering with frontend/native parity, such as
  dynamic array lengths in type positions; proof includes `tests/test_array_len_policy.lua`
  and the coverage matrix final gate.

Do not use the historical scaffold-gap sections above as the current status; they record why
this completion pass was required. The current completion claim is only the native64/hosted C
fast path proven by the tests listed here, not yet a target-aware cross-compilation claim.
