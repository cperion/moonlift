# Complete Moonlift C Backend Design

Status: canonical design and execution contract. This document is intentionally broader
than any single implementation pass. It defines what a **complete** C backend means, and
now also records the ASDL/MoonCode refactor required to make that backend good by default.

Current checkpoint — 2026-06-15:

- schema source files in `lua/moonlift/schema/` have been converted from Lua-builder modules
  to MoonSchema Lua data, loaded by `schema/init.lua`;
- `MoonCode` is the active normalized typed SSA/control ASDL layer in
  `lua/moonlift/schema/code.lua`;
- public native lowering now routes through `tree_to_code -> code_validate -> Flow/Mem/Kernel/Lower -> lower_to_back/code_to_back`;
- public C lowering now routes through `tree_to_code -> code_validate -> code_to_c ->
  c_validate`, not direct `tree_to_c`;
- the old direct Tree-to-C implementation modules have been deleted with no compatibility
  shims: `tree_to_c`, `tree_control_to_c`, `type_to_c`, `c_places`, `c_residence`, `c_cfg`,
  `c_data`, and `c_layout`;
- the C path has MoonCode-driven TCC/libtcc/gcc coverage for a substantial subset, but final
  full-support status still requires closing remaining feature gaps and final gate suites.

The C backend is a PVM side projection.  The target architecture is:

```text
Lua DSL value
  -> parse
  -> open_expand
  -> closure_convert
  -> tree_typecheck
  -> sem_layout_resolve(target = c_target)
  -> tree_to_code
  -> code_validate
  -> code_to_c
  -> c_validate
  -> c_emit
  -> .c
```

The historical direct `tree_to_c` path has been removed. There is no long-lived compatibility
shim; `code_to_c` is the C projection entry point.

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

The printer must stay dumb. Semantics belong in `tree_to_code`, `code_to_c`, CodeType helpers,
and validation.

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

## 23. Completion invariant

The C backend is not allowed to keep scaffold-only accept/reject paths. Every source or ASDL
shape that can reach C projection must be classified in the enforced coverage matrix as one of:

1. `supported` — emitted to C and covered by gcc compile/run tests;
2. `phase_unreachable` — impossible after earlier phases, proven by tests at the phase boundary;
3. `language_rejected` — rejected by Moonlift itself/native parity before backend lowering.

There is no backend-level TODO status. If a feature is not emitted by C, it must either be
removed from the language path before C projection or rejected by the same language rules that
apply to native lowering.

### 23.1 Phase-boundary proof

The following are phase-boundary assertions, not backend gaps:

- raw `ExprDot` / `PlaceDot` are resolved to field-offset forms before Code lowering;
- surface casts are converted to machine casts before Code lowering;
- direct closure literals are closure-converted before Code lowering;
- open slots/fragments/import forms are expanded or diagnosed before Code lowering;
- open funcs/externs cannot reach `tree_to_code` / `code_to_c` through the normal pipeline.

The C backend phase-boundary tests enforce those claims.

### 23.2 User-facing completion test

The acceptance condition is not only Lua unit tests. It is a source corpus that does:

```text
Moonlift source -> moon.emit_c -> gcc/cc -> executable/shared object -> run/compare result
```

for every supported language feature.

## 24. Implementation checkpoint correction — 2026-06-10

The current implementation should be described precisely, not as unrestricted completion.
It has a working hosted/native64 C path for a substantial supported subset and it can run
through TCC/libtcc/gcc, but that is not the final architecture for full support or good
default C quality.

The important correction is architectural:

```text
resolved MoonTree
  -> MoonCode normalized typed SSA/control layer
      -> code_to_c
      -> code_to_back
```

The C backend must remain a side projection from the typed/resolved program layer, but it
should not recursively rediscover SSA from nested `MoonTree.Expr` trees.  The bad TCC/no-O
shape is a symptom of this missing middle layer:

```c
ml_bin_2 = ml_i32_add_intwrap(i, 1);
ml_bin_3 = ml_i32_add_intwrap(acc, i);
__xfer_loop_1 = ml_bin_2;
__xfer_loop_2 = ml_bin_3;
goto loop;

loop:
  i = __xfer_loop_1;
  acc = __xfer_loop_2;
  ml_cmp_1 = (i >= n);
  if (ml_cmp_1) goto then; else goto else;
```

The desired default C shape comes naturally from normalized values/control, not from a
post-printer optimization profile:

```c
int32_t i = 0;
int32_t acc = 0;
loop:
  if (i >= n) return acc;
  acc = (int32_t)((uint32_t)acc + (uint32_t)i);
  i = (int32_t)((uint32_t)i + 1u);
  goto loop;
```

Completion claims must therefore be milestone-specific:

| Milestone | Meaning | Status |
|---|---|---|
| C hosted subset | Moonlift source can emit C and run through TCC/gcc for covered features | working subset |
| C native64 full coverage | every resolved supported language construct classified and tested through C | in progress |
| MoonCode normalized layer | typed SSA/control ASDL validates defs/uses, places, calls, blocks, terms | implemented |
| C-on-MoonCode | C lowering consumes normalized code instead of nested MoonTree | implemented |
| C quality/perf readiness | TCC/no-O code has clean shape; gcc -O2 remains competitive | active |
| target-aware C | pointer/index/layout/endian/freestanding profiles beyond hosted native64 | future |

Historical sections above remain useful as design contract and coverage rationale, but the
current final gate is the full compile/run corpus plus target-model coverage, not the deleted
recursive `tree_to_c` implementation.

## 25. MoonSchema source projection

The schema source of truth is MoonSchema Lua data under:

```text
lua/moonlift/schema/*.lua
```

The runtime path is:

```text
MoonSchema Lua module
  -> MoonSchema module value
  -> MoonAsdl.Schema projection value
  -> context_define_schema.define
  -> live runtime classes
```

`MoonAsdl.Schema` is a projection value used by existing compiler/runtime class
machinery. It is not the authored representation. There is no schema text parser
or `.asdl` source path in the active compiler.

The C backend consumes typed compiler values produced from this projection.
The embedded standalone binary includes schema Lua modules like every other
hosted Lua module.

Current contract:

1. every `lua/moonlift/schema/*.lua` loads as a MoonSchema module;
2. `require("moonlift.schema_projection")(T)` defines all expected runtime modules;
3. docs and source references point at MoonSchema Lua modules, not schema text files;
4. `MoonAsdl` names remain internal projection vocabulary only.

## 26. MoonCode normalized layer

`MoonCode` is the backend-neutral ASDL layer between resolved `MoonTree` and concrete
backend projections.  It is neither `MoonBack` nor `MoonC.CBackend*`.  Its purpose is to
make value dependencies, control dependencies, storage residence, places, memory effects,
ABI signatures, and variant/tagged-union operations explicit once.

### 26.1 Pipeline

The target pipeline is:

```text
Lua DSL value
  -> parse
  -> open_expand
  -> closure_convert
  -> tree_typecheck
  -> sem_layout_resolve(target)
  -> tree_to_code
  -> code_validate
  -> code_to_c       -> c_validate    -> c_emit
  -> code_to_back    -> back_validate -> back_jit/back_object
```

The final architecture has one normalized native lowering route. Direct Tree-to-Back lowering
has been deleted so native and C projection cannot drift behind separate Tree walkers.

### 26.2 What MoonCode must preserve

MoonCode must preserve all facts needed by both C and Cranelift-like backends:

- typed values with stable `CodeValueId`s;
- block params as the only phi form;
- terminators with typed block edge arguments;
- expression normalization into ANF/SSA instructions;
- local/storage residence;
- explicit places for local/global/deref/field/index/byte access;
- memory access metadata: type, align, volatile, ordering, trap mode;
- direct, extern, indirect, and closure call targets with exact signatures;
- data pointer vs code pointer distinction;
- aggregate, array, view, closure, and variant construction as semantic operations;
- variant tag/payload extraction and variant-switch branch facts;
- source origins for diagnostics and debugging.

### 26.3 Why C quality depends on MoonCode

C wants local variables and gotos, not a pile of invented recursive-expression temporaries.
MoonCode gives C lowering enough information to choose direct shapes safely:

- branch directly on compare values when the compare is single-use by a terminator;
- assign jump args directly when no parallel-assignment hazard exists;
- use transfer temps only for real cycles/hazards;
- coalesce single-use arithmetic values into UB-free inline expressions;
- keep loop-carried block params as ordinary C locals for reducible self-loops;
- avoid bool temps for condition-only comparisons;
- still preserve exact Moonlift semantics for overflow, div/rem, shifts, traps, and memory.

This is not an optional optimized profile.  It is the default lowering from the right IR.

## 27. Full execution plan

The structured edit plan for this work is stored as:

```text
.pi/workflows/wf-asdl-c-backend-full-support.edit-plan.json
```

Summary order:

1. freeze MoonSchema Lua files as schema source of truth and harden loader/embedding;
2. harden MoonSchema diagnostics and projection validation;
3. validate/revise `MoonCode` ASDL before depending on it;
4. implement `code_validate`;
5. implement `tree_to_code`;
6. add MoonCode semantic/validation tests;
7. implement `code_to_c` and migrate public C APIs to it;
8. make default C output naturally optimizable: direct branches, minimal transfers,
   single-use expression coalescing, and clean loop-shaped gotos;
9. implement or bridge `code_to_back` to keep native parity;
10. reclassify C coverage around MoonCode boundaries;
11. expand TCC/libtcc/gcc compile-run and Cranelift equivalence corpus;
12. update this document only when gates actually pass.

Final full-support gates:

```sh
luajit tests/test_schema_core.lua
luajit tests/test_schema_compile_pipeline.lua
luajit tests/test_tree_to_code.lua
luajit tests/test_code_validate.lua
luajit tests/test_code_to_c.lua
luajit tests/test_code_to_back.lua
MOONLIFT_C_BACKEND_FINAL=1 luajit tests/test_c_backend_coverage_matrix.lua
luajit tests/test_c_gcc_feature_corpus.lua
MOONLIFT_C_USE_LIBTCC=1 luajit tests/test_c_gcc_feature_corpus.lua
luajit tests/test_c_full_semantic_equivalence.lua
luajit benchmarks/bench_c_vs_cranelift.lua quick
MOONLIFT_BENCH_C_RUNNER=gcc MOONLIFT_C_CC=gcc \
  MOONLIFT_BENCH_CFLAGS='-std=c99 -O2 -fPIC -shared' \
  luajit benchmarks/bench_c_vs_cranelift.lua quick
```

A completion claim must name the milestone it satisfies.  The phrase "C backend complete"
without a milestone means all final full-support gates above have passed.


## 28. Retirement map: removed direct Tree-to-C modules

The refactor must make removal explicit.  A lot of current files exist because the first C
backend tried to lower directly from nested `MoonTree` into `MoonC.CBackend*`.  That was a
useful bootstrap, but it is not the final architecture.

### 28.1 Public API that stays

These are user-facing or stable integration points and should survive the refactor:

| API/file | Fate |
|---|---|
| `moon.emit_c`, `moon.compile_c` | stay; internally call the new MoonCode path |
| `BundleValue:emit_c`, `BundleValue:compile_c` | stay; internally call the new MoonCode path |
| `lua/moonlift/c_tcc.lua` | stay; runner/toolchain integration, independent of lowering IR |
| `lua/moonlift/c_emit.lua` | stay if `MoonC.CBackend*` remains the restricted C dialect printer |
| `lua/moonlift/c_validate.lua` | stay, but validate output from `code_to_c`; may shrink if checks move to `code_validate` |
| `lua/moonlift/c_helpers.lua` | stay; semantic helper library for UB-free C operations |
| `lua/moonlift/schema/c.lua` | canonical `MoonC` / `CBackend` ASDL consumed by C emission |
| `tests/test_c_gcc_harness.lua` | stay; compile/run harness is backend-path neutral |
| `benchmarks/bench_c_vs_cranelift.lua` | stay; should measure the new path |

### 28.2 Direct Tree-to-C lowering removed

These old-approach implementation details have been removed with no compatibility shims:

| File | Why it was removed | Replacement / current owner |
|---|---|---|
| `lua/moonlift/tree_to_c.lua` | recursively lowered nested MoonTree, invented temps, and mixed normalization/control/place/type concerns | `tree_to_code.lua` normalizes; `code_to_c.lua` projects MoonCode to CBackend |
| `lua/moonlift/tree_control_to_c.lua` | C-specific source-region lowering duplicated logic that belongs in MoonCode block params/terminators | control lowering in `tree_to_code.lua`; C block/term emission in `code_to_c.lua` |
| `lua/moonlift/type_to_c.lua` | projected MoonType directly to C during recursive lowering | `code_type.lua` maps MoonType -> CodeType and CodeType -> CBackend type spelling |
| `lua/moonlift/c_places.lua` | lowered MoonTree places directly to C places | CodePlace construction in `tree_to_code.lua`; place emission in `code_to_c.lua` |
| `lua/moonlift/c_residence.lua` | computed C residence from MoonTree bindings in the C lowerer | CodeLocal/CodeResidence facts from `tree_to_code.lua`, consumed by `code_to_c.lua` |
| `lua/moonlift/c_cfg.lua` | ad-hoc direct-C CFG builder | MoonCode CodeBlock/CodeTerm plus `code_to_c` block/term lowering |
| `lua/moonlift/c_data.lua` | lowered MoonTree static/data directly to C globals | CodeGlobal/CodeData lowering in `tree_to_code.lua` and C global/data projection in `code_to_c.lua` |
| `lua/moonlift/c_layout.lua` | projected layout facts directly from the old Tree-to-C path | layout-backed CBackend declarations are synthesized from MoonCode/CodeType/layout facts in `code_to_c.lua` |

Deletion happened after the public native and C APIs were hard-switched to MoonCode and the
focused CodeType/code_to_c/public API tests were rerouted.

### 28.3 Tests renamed, replaced, or rerouted

Old behavior specs have been kept where useful, but test names/imports now refer to public APIs
or MoonCode/code-to-C layers rather than the retired direct Tree-to-C modules.

| Historical tests/imports | Current fate |
|---|---|
| `tests/test_tree_to_c_smoke.lua` | replaced by `tests/test_code_to_c_smoke.lua` |
| `tests/test_tree_to_c_semantics_smoke.lua` | replaced by `tests/test_code_to_c_semantics_smoke.lua` |
| `tests/test_tree_to_c_logic_select.lua` | replaced by `tests/test_code_to_c_logic_select.lua` |
| `tests/test_tagged_union_to_c.lua` | kept as behavior coverage, rerouted through `tree_to_code` + `code_to_c` |
| direct imports of `tree_to_c`, `tree_control_to_c`, `type_to_c` in tests | removed; tests exercise public API, CodeType, `tree_to_code`, or `code_to_c` |

Tests for the public C API, TCC/libtcc runner, C helpers, C validation, and gcc feature
corpus stay as proof that removing direct Tree-to-C lowering did not reduce supported behavior.

### 28.4 Frontend/API migration points

These call sites have been changed deliberately:

| File | Old dependency | Current dependency |
|---|---|---|
| `lua/moonlift/frontend_pipeline.lua` | `tree_to_c`, `type_to_c` | `tree_to_code`, `code_validate`, `code_to_c`, `c_validate` |
| `lua/moonlift/init.lua` | exported `type_to_c`, `tree_to_c` | public C APIs stay stable; MoonCode diagnostics are exposed where useful |
| `lua/moonlift/host_module_values.lua` | bundle C emission assumed the old CBackend unit path | bundle methods call the new pipeline but keep method names |
| examples under `examples/c_backend/` | user-facing scripts should continue unchanged | only internals changed |

### 28.5 Deletion evidence / remaining grep gate

The deletion gate has been crossed for section 30.2 modules:

1. production code no longer requires them;
2. tests were rerouted to public APIs, CodeType, `tree_to_code`, or `code_to_c`;
3. public `moon.emit_c`, `moon.compile_c`, `BundleValue:emit_c`, and `BundleValue:compile_c`
   pass through the MoonCode C path;
4. the C feature corpus and renamed code-to-C smoke tests run on the new path;
5. benchmarks report `tree_to_code`, `code_validate`, `code_to_c`, and `code_to_back` phase names;
6. this section records the modules as removed, not migration scaffolding.

The remaining final grep gate is documentation hygiene: references to the retired names should
only appear as historical notes saying they were deleted/retired, not as active API guidance.

## 29. Kernel tower checkpoint — MoonCode facts to semantic lowering

The kernel tower is now a semantic side path over `MoonCode`, not a source-tree replacement
mechanism.  The intended flow is:

```text
MoonCode
  -> CodeFlowFacts   -- CFG edges, counted-loop domains, inductions, exits
  -> CodeMemFacts    -- memory bases, access streams, alignment/bounds/trap facts
  -> CodeKernelPlan  -- semantic KernelBody facts and safety/schedule choices
  -> CodeLowerPlan   -- choose Code projection or whole-function Kernel projection
  -> LowerToBack     -- Back projection from KernelBodyCounted or Code projection
  -> LowerToC        -- CodeToC projection until generic C KernelBody lowering exists
```

### 29.1 KernelBodyCounted is the semantic core

`MoonKernel` should describe executable meaning, not backend recipes.  The current core is
`KernelBodyCounted`:

```text
KernelBodyCounted(
  loop,        -- FlowLoopFacts / counted iteration domain
  counter,     -- executable counter policy
  streams,     -- memory streams used by the body
  bindings,    -- named kernel-local expression equations (reserved for growth)
  effects,     -- stores and folds
  result,      -- function result semantics
  safety       -- proofs/assumptions/rejections
)
```

Effects are explicit:

```text
KernelEffectStore(KernelStore)
KernelEffectFold(KernelFold)
```

Results are explicit:

```text
KernelResultVoid
KernelResultExpr(expr)
KernelResultFold(fold_id)
KernelResultUnmodeled(reason)
```

So a loop such as copy-and-sum is one body with one store effect and one fold effect, not a
choice between a "map core" and a "reduce core".  Map/reduce/store-only/fold-only are
classifications derived from effects, not primary ASDL variants.

### 29.2 Subject rule: loop facts vs whole-function equivalence

`KernelSubjectLoop(func, loop)` means "this loop has semantic facts".  It is analysis
evidence only and is not enough to replace a function body.

`KernelSubjectFunc(func)` means the planner proved a whole-function equivalence: the counted
body plus its `KernelResult` accounts for the function's observable result and effects.  Only
`KernelSubjectFunc` may become `LowerFuncKernel` in `CodeLowerPlan`.

This rule prevents CFG-splicing and live-in/live-out replacement architecture from returning
under another name.

### 29.3 Schedule is not semantics

`KernelScheduleScalarIndex`, `KernelScheduleVector`, and future schedules are lowering
choices over an already-complete `KernelBody`.  A schedule may choose vector lanes, unroll,
interleave, and tail strategy, but it must not invent stores, folds, results, or safety.

Back lowering therefore consumes:

```text
KernelBodyCounted + KernelSchedule
```

and projects Back commands.  C lowering currently does not consume schedules at all.

### 29.4 Back projection policy

`lower_to_back` is now a first-class `LowerModule` projector:

- module prelude and function declarations come from `code_to_back` helpers;
- `LowerFuncCode` uses ordinary `CodeToBack` function body projection;
- `LowerFuncKernel` emits a whole-function kernel body directly;
- kernel lowering no longer goes through `replacement_funcs`.

The current Back kernel projector supports the generic `KernelExpr` subset needed for stores
and folds:

- values;
- constants;
- loads;
- integer/bit binary ops;
- compares;
- selects.

Unsupported kernel expressions must fail explicitly.  They should not silently become opaque
backend values unless the ASDL intentionally models them as external values.

### 29.5 C projection policy

`lower_to_c` is deliberately a pure `CodeToC` projection today.  It accepts `LowerModule` only
so frontend pipelines have one shape.  It must not install partial C-only kernel
optimizations.  A future C kernel path should consume the same generic `KernelBodyCounted`
semantics as Back, not special-case individual reductions, benchmark loops, or algebraic
closed forms.

### 29.6 Retired vector stack hard-yanked

The tree-shaped vector stack was deleted, not quarantined:

- `tree_to_back.lua`
- `schema/vec.lua`
- `vec_loop_facts.lua`
- `vec_loop_decide.lua`
- `vec_kernel_plan.lua`
- `vec_kernel_safety.lua`
- `vec_kernel_to_back.lua`
- `vec_to_back.lua`
- `vec_inspect.lua`

Public native lowering now routes through the MoonCode fact tower. Vector code generation that
remains is Back-level vector command support plus `KernelBodyCounted` scheduling in
`lower_to_back`. Any future vector-specific semantics must be expressed as Flow/Mem/Kernel
facts and schedules, not as a competing source-tree recognizer.

## 30. Hard-yank completion boundary

This refactor is considered complete only when active code has no loadable retired frontend
backend path:

- no direct Tree-to-Back module;
- no MoonVec schema or tree-vector modules;
- no `replacement_funcs` body-substitution API;
- no tests or benchmarks requiring the deleted modules;
- documentation describes the deleted modules only as removed history, not as available APIs.

Current inspection result: `lua/moonlift`, `tests`, and `benchmarks` contain no references to
`tree_to_back`, `MoonVec`, `vec_loop_facts`, `vec_loop_decide`, `vec_kernel_plan`,
`vec_kernel_safety`, `vec_kernel_to_back`, `vec_to_back`, or `vec_inspect`.
